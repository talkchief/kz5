%%%-----------------------------------------------------------------------------
%%% SPDX-License-Identifier: MPL-2.0
%%% @copyright (C) 2026 Talkchief
%%% @doc Fresh, fail-closed I/O for durable callback reconciliation.
%%%
%%% Channel absence is evidence only when every advertised ecallmgr supplied a
%%% fresh, correlated `terminated' response. Originate settlement is separate
%%% evidence, obtained from an exact UUID/request/caller query against the
%%% FreeSWITCH lifecycle registry; timeout, absence and an epoch change remain
%%% unknown.
%%% @end
%%%-----------------------------------------------------------------------------
-module(acdc_callback_recovery_io).

-export([observe/1
        ,observe_channels/2
        ,request_cleanup/1
        ,reconcile_originate/2
        ]).

-ifdef(TEST).
-export([observe_with/2
        ,classify_collection/4
        ,relevant_call_ids/1
        ,bridge_summary/1
        ,build_cleanup_requests/2
        ,request_cleanup_with/4
        ,reconcile_originate_with/3
        ,classify_reconcile_collection/6
        ]).
-endif.

-include("acdc.hrl").

-define(QUERY_TIMEOUT, 5000).
-define(MAX_CALL_IDS, 8).

-type channel_state() :: 'active' | 'terminated' | 'unknown'.
-type observation() :: map().
-type evidence() :: map().

%% The injected form is intentionally available only to isolated tests.  The
%% function receives the exact request and correlation ID and must return the
%% kz_amqp_worker:call_collect/4 result.
-spec observe(kz_json:object()) -> {'ok', evidence()} | {'unknown', evidence()} |
                                   {'error', 'invalid_input'}.
observe(Doc) ->
    observe_with(Doc, fun query_channel/2).

%% Also used by the agent FSM's asynchronous lost-hangup check. Keep the same
%% strict correlation, responder and account checks as callback recovery.
-spec observe_channels(kz_term:ne_binary(), kz_term:ne_binaries()) ->
          {'ok', evidence()} | {'unknown', evidence()} | {'error', 'invalid_input'}.
observe_channels(AccountId, CallIds) ->
    case is_ne_binary(AccountId) andalso is_list(CallIds)
        andalso CallIds =/= [] andalso lists:all(fun is_ne_binary/1, CallIds) of
        'true' -> observe_channels_with(AccountId, lists:usort(CallIds), fun query_channel/2);
        'false' -> {'error', 'invalid_input'}
    end.

-spec observe_with(kz_json:object(), fun((kz_term:proplist(), kz_term:ne_binary()) -> any())) ->
          {'ok', evidence()} | {'unknown', evidence()} | {'error', 'invalid_input'}.
observe_with(Doc, QueryFun) when is_function(QueryFun, 2) ->
    case observation_context(Doc) of
        {'error', _} -> {'error', 'invalid_input'};
        {AccountId, CallIds} -> observe_channels_with(AccountId, CallIds, QueryFun)
    end;
observe_with(_, _) -> {'error', 'invalid_input'}.

-spec observe_channels_with(kz_term:ne_binary(), kz_term:ne_binaries(), function()) ->
          {'ok', evidence()} | {'unknown', evidence()}.
observe_channels_with(AccountId, CallIds, QueryFun) ->
    {Complete, Observations, Reasons} =
        observe_call_ids(AccountId, CallIds, QueryFun, [], [], []),
    StableResponders = matching_responders(Observations),
    CompleteSnapshot = Complete andalso StableResponders,
    SnapshotReasons = case StableResponders of
        'true' -> Reasons;
        'false' -> ['inconsistent_responder_set' | Reasons]
    end,
    Evidence = #{'complete' => CompleteSnapshot
                ,'channels' => lists:sort(Observations)
                ,'bridge' => bridge_summary(Observations)
                ,'reasons' => lists:usort(SnapshotReasons)},
    case CompleteSnapshot of
        'true' -> {'ok', Evidence};
        'false' -> {'unknown', Evidence}
    end.

-spec matching_responders([observation()]) -> boolean().
matching_responders([]) -> 'false';
matching_responders([First | Rest]) ->
    Responders = maps:get('responders', First, []),
    Responders =/= [] andalso lists:all(
        fun(Observation) -> maps:get('responders', Observation, []) =:= Responders end, Rest).

-spec query_channel(kz_term:proplist(), kz_term:ne_binary()) -> any().
query_channel(Request, _MsgId) ->
    kz_amqp_worker:call_collect(Request
                               ,fun kapi_call:publish_channel_status_req/1
                               ,{'ecallmgr', 'true'}
                               ,?QUERY_TIMEOUT).

-spec observe_call_ids(kz_term:ne_binary(), [kz_term:ne_binary()],
                       fun((kz_term:proplist(), kz_term:ne_binary()) -> any()),
                       [kz_term:ne_binary()], [observation()], [atom()]) ->
          {boolean(), [observation()], [atom()]}.
observe_call_ids(_AccountId, [], _QueryFun, _Seen, Observations, Reasons) ->
    {Reasons =:= [], Observations, Reasons};
observe_call_ids(AccountId, [CallId | Rest], QueryFun, Seen, Observations, Reasons) ->
    case lists:member(CallId, Seen) of
        'true' -> observe_call_ids(AccountId, Rest, QueryFun, Seen, Observations, Reasons);
        'false' when length(Seen) >= ?MAX_CALL_IDS ->
            {false, Observations, ['call_id_limit' | Reasons]};
        'false' ->
            MsgId = kz_binary:rand_hex(12),
            Request = [{<<"Call-ID">>, CallId}
                      ,{<<"Active-Only">>, 'false'}
                      ,{<<"Channel-Record">>, 'true'}
                      ,{<<"Msg-ID">>, MsgId}
                       | kz_api:default_headers(<<"channel">>, <<"channel_status_req">>
                                               ,?APP_NAME, ?APP_VERSION)],
            Result = try QueryFun(Request, MsgId)
                     catch _:_ -> {'error', 'query_failed'}
                     end,
            case classify_collection(AccountId, CallId, MsgId, Result) of
                {'ok', Observation} ->
                    More = derived_call_ids(Observation, Seen ++ [CallId] ++ Rest),
                    observe_call_ids(AccountId, Rest ++ More, QueryFun, [CallId | Seen]
                                    ,[Observation | Observations], Reasons);
                {'unknown', Observation} ->
                    Reason = maps:get('reason', Observation, 'unknown_response'),
                    observe_call_ids(AccountId, Rest, QueryFun, [CallId | Seen]
                                    ,[Observation | Observations], [Reason | Reasons])
            end
    end.

-spec classify_collection(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), any()) ->
          {'ok', observation()} | {'unknown', observation()}.
classify_collection(AccountId, CallId, MsgId, {'ok', Responses}) when is_list(Responses) ->
    classify_complete(AccountId, CallId, MsgId, Responses);
classify_collection(AccountId, CallId, MsgId, {'timeout', Responses}) when is_list(Responses) ->
    {'unknown', partial_observation(AccountId, CallId, MsgId, Responses, 'collection_timeout')};
classify_collection(AccountId, CallId, MsgId, {'error', 'timeout', Responses}) when is_list(Responses) ->
    {'unknown', partial_observation(AccountId, CallId, MsgId, Responses, 'collection_timeout')};
classify_collection(_AccountId, CallId, _MsgId, _) ->
    {'unknown', base_observation(CallId, 'query_failed', 0)}.

-spec classify_complete(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), list()) ->
          {'ok', observation()} | {'unknown', observation()}.
classify_complete(_AccountId, CallId, _MsgId, []) ->
    {'unknown', base_observation(CallId, 'empty_collection', 0)};
classify_complete(AccountId, CallId, MsgId, Responses) ->
    Checked = [checked_response(AccountId, CallId, MsgId, Response) || Response <- Responses],
    case [Reason || {'error', Reason} <- Checked] of
        [_ | _] ->
            {'unknown', base_observation(CallId, 'invalid_response', length(Responses))};
        [] ->
            Values = [Value || {'ok', Value} <- Checked],
            Nodes = [maps:get('responder', Value) || Value <- Values],
            States = [maps:get('state', Value) || Value <- Values],
            Active = [Value || Value <- Values, maps:get('state', Value) =:= 'active'],
            case {length(lists:usort(Nodes)) =:= length(Nodes),
                  lists:member('tmpdown', States), length(Active)} of
                {'false', _, _} ->
                    {'unknown', base_observation(CallId, 'duplicate_responder', length(Values))};
                {_, 'true', _} ->
                    {'unknown', base_observation(CallId, 'temporary_node_failure', length(Values))};
                {'true', 'false', 0} ->
                    {'ok', (base_observation(CallId, 'complete', length(Values)))#{
                             'state' => 'terminated', 'responders' => lists:sort(Nodes)}};
                {'true', 'false', 1} ->
                    [ActiveResponse] = Active,
                    ActiveEvidence = maps:with(['state', 'switch_node'
                                               ,'other_leg_call_id', 'control_queue'
                                               ,'answered'], ActiveResponse),
                    {'ok', maps:merge((base_observation(CallId, 'complete', length(Values)))#{
                                      'responders' => lists:sort(Nodes)
                                     ,'active_responder' => maps:get('responder', ActiveResponse)}
                                     ,ActiveEvidence)};
                _ ->
                    {'unknown', base_observation(CallId, 'multiple_active_owners', length(Values))}
            end
    end.

-spec checked_response(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), any()) ->
          {'ok', map()} | {'error', atom()}.
checked_response(AccountId, CallId, MsgId, Response) ->
    try kapi_call:channel_status_resp_v(Response)
        andalso kz_api:msg_id(Response) =:= MsgId
        andalso kz_api:call_id(Response) =:= CallId
    of
        'false' -> {'error', 'invalid_correlation'};
        'true' -> checked_correlated_response(AccountId, Response)
    catch _:_ -> {'error', 'invalid_response'}
    end.

-spec checked_correlated_response(kz_term:ne_binary(), kz_json:object()) ->
          {'ok', map()} | {'error', atom()}.
checked_correlated_response(AccountId, Response) ->
    Node = kz_api:node(Response),
    Status = kz_json:get_ne_binary_value(<<"Status">>, Response),
    case is_ne_binary(Node) andalso status_atom(Status) of
        'false' -> {'error', 'invalid_responder'};
        'unknown' -> {'error', 'invalid_status'};
        'active' -> checked_active_response(AccountId, Node, Response);
        State -> {'ok', #{'state' => State, 'responder' => Node}}
    end.

-spec checked_active_response(kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) ->
          {'ok', map()} | {'error', atom()}.
checked_active_response(AccountId, Node, Response) ->
    Channel = kz_json:get_json_value(<<"Channel-Record">>, Response),
    CCVs = kz_json:get_json_value(<<"Custom-Channel-Vars">>, Channel),
    SwitchNode = bounded_binary(kz_json:get_ne_binary_value(<<"Media-Node">>, Channel), 512),
    case kz_json:is_json_object(Channel) andalso kz_json:is_json_object(CCVs)
        andalso kz_json:get_ne_binary_value(<<"Call-ID">>, Channel) =:= kz_api:call_id(Response)
        andalso kz_json:get_ne_binary_value(<<"Account-ID">>, Channel) =:= AccountId
        andalso kz_json:get_ne_binary_value(<<"Account-ID">>, CCVs) =:= AccountId
        andalso is_ne_binary(SwitchNode) of
        'false' -> {'error', 'account_mismatch'};
        'true' ->
            OtherLeg = bounded_binary(kz_json:get_ne_binary_value(<<"Other-Leg-Call-ID">>, Channel), 512),
            ControlQueue = bounded_binary(kz_json:get_ne_binary_value(<<"Control-Queue">>, Channel), 512),
            {'ok', maps:filter(fun(_, V) -> V =/= 'undefined' end
                              ,#{'state' => 'active', 'responder' => Node
                                ,'switch_node' => SwitchNode
                                ,'other_leg_call_id' => OtherLeg
                                ,'control_queue' => ControlQueue
                                ,'answered' => kz_json:is_true(<<"Answered">>, Channel, 'false')})}
    end.

-spec partial_observation(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(),
                          list(), atom()) -> observation().
partial_observation(AccountId, CallId, MsgId, Responses, Reason) ->
    Valid = [Value || Response <- Responses,
                      {'ok', Value} <- [checked_response(AccountId, CallId, MsgId, Response)]],
    Responders = lists:usort([maps:get('responder', Value) || Value <- Valid]),
    (base_observation(CallId, Reason, length(Valid)))#{'state' => 'unknown'
                                                     ,'responders' => Responders}.

-spec base_observation(kz_term:ne_binary(), atom(), non_neg_integer()) -> observation().
base_observation(CallId, Reason, Count) ->
    #{'call_id' => CallId, 'state' => 'unknown', 'reason' => Reason
     ,'responder_count' => Count}.

-spec derived_call_ids(observation(), [kz_term:ne_binary()]) -> [kz_term:ne_binary()].
derived_call_ids(#{'state' := 'active', 'other_leg_call_id' := OtherLeg}, Existing) ->
    case is_ne_binary(OtherLeg) andalso not lists:member(OtherLeg, Existing) of
        'true' -> [OtherLeg];
        'false' -> []
    end;
derived_call_ids(_, _) -> [].

-spec relevant_call_ids(kz_json:object()) -> [kz_term:ne_binary()].
relevant_call_ids(Doc) ->
    lists:usort([Id || Key <- [<<"original_call_id">>, <<"pvt_caller_call_id">>
                              ,<<"pvt_agent_call_id">>],
                       Id <- [bounded_binary(kz_json:get_ne_binary_value(Key, Doc), 512)],
                       is_ne_binary(Id)]).

-spec bridge_summary([observation()]) -> map().
bridge_summary(Observations) ->
    Active = maps:from_list([{maps:get('call_id', O), O} || O <- Observations,
                              maps:get('state', O, 'unknown') =:= 'active']),
    Pairs = lists:usort(
              [lists:sort([CallId, Other])
               || {CallId, O} <- maps:to_list(Active),
                  Other <- [maps:get('other_leg_call_id', O, 'undefined')],
                  is_ne_binary(Other),
                  maps:is_key(Other, Active),
                  maps:get('other_leg_call_id', maps:get(Other, Active), 'undefined') =:= CallId]),
    Mentioned = [O || O <- Observations,
                      is_ne_binary(maps:get('other_leg_call_id', O, 'undefined'))],
    PairMembers = lists:usort(lists:append(Pairs)),
    MentionedIds = lists:usort([maps:get('call_id', O) || O <- Mentioned]),
    case {Pairs, Mentioned, PairMembers =:= MentionedIds} of
        {[], [], _} -> #{'state' => 'not_observed'};
        {[], _, _} -> #{'state' => 'unknown', 'reason' => 'incomplete_or_conflicting_pair'};
        {[Pair], _, 'true'} -> #{'state' => 'bridged', 'call_ids' => Pair};
        {[_], _, 'false'} -> #{'state' => 'unknown', 'reason' => 'conflicting_pair'};
        {_, _, _} -> #{'state' => 'unknown', 'reason' => 'multiple_pairs'}
    end.

-spec reconcile_originate(kz_json:object(), 'status' | 'cancel') ->
          {'ok', evidence()} | {'unknown', evidence()} | {'error', 'invalid_input'}.
reconcile_originate(Doc, Operation) ->
    reconcile_originate_with(Doc, Operation, fun query_originate/2).

-spec reconcile_originate_with(kz_json:object(), 'status' | 'cancel',
                               fun((kz_term:proplist(), kz_term:ne_binary()) -> any())) ->
          {'ok', evidence()} | {'unknown', evidence()} | {'error', 'invalid_input'}.
reconcile_originate_with(Doc, Operation, QueryFun)
  when (Operation =:= 'status' orelse Operation =:= 'cancel'), is_function(QueryFun, 2) ->
    case originate_context(Doc) of
        {'error', _} -> {'error', 'invalid_input'};
        {UUID, OriginalRequestId, CallerId} ->
            MsgId = kz_binary:rand_hex(12),
            OperationBin = atom_to_binary(Operation, 'utf8'),
            Request = [{<<"Originate-UUID">>, UUID}
                      ,{<<"Originate-Request-ID">>, OriginalRequestId}
                      ,{<<"Outbound-Call-ID">>, CallerId}
                      ,{<<"Operation">>, OperationBin}
                      ,{<<"Msg-ID">>, MsgId}
                       | kz_api:default_headers(<<"channel">>, <<"originate_reconcile_req">>
                                               ,?APP_NAME, ?APP_VERSION)],
            Result = try QueryFun(Request, MsgId)
                     catch _:_ -> {'error', 'query_failed'}
                     end,
            Classified = classify_reconcile_collection(UUID, OriginalRequestId, CallerId
                                                       ,OperationBin, MsgId, Result),
            durable_originate_result(Doc, Operation, Classified)
    end;
reconcile_originate_with(_, _, _) -> {'error', 'invalid_input'}.

%% Only a complete collection with no surviving native record can fall back
%% to the exact durable success receipt. Never mask a timeout, partition,
%% malformed/conflicting reply or a native pending operation. Call teardown
%% still requires the independent, fresh all-node channel observation.
durable_originate_result(Doc, 'status', {'unknown', #{'reason' := 'not_observed_in_current_module_epochs'}=Evidence}=Result) ->
    case acdc_callback_store:originate_succeeded(Doc) of
        'true' -> {'ok', Evidence#{'complete' => 'true', 'status' => 'settled'
                                  ,'originate_settled' => 'true', 'outcome' => 'success'
                                  ,'reason' => 'durable_success_receipt'}};
        'false' -> Result
    end;
durable_originate_result(_, _, Result) -> Result.

-spec query_originate(kz_term:proplist(), kz_term:ne_binary()) -> any().
query_originate(Request, _MsgId) ->
    kz_amqp_worker:call_collect(Request
                               ,fun kapi_call:publish_originate_reconcile_req/1
                               ,{'ecallmgr', 'true'}
                               ,?QUERY_TIMEOUT).

-spec classify_reconcile_collection(kz_term:ne_binary(), kz_term:ne_binary(),
                                    kz_term:ne_binary(), kz_term:ne_binary(),
                                    kz_term:ne_binary(), any()) ->
          {'ok', evidence()} | {'unknown', evidence()}.
classify_reconcile_collection(UUID, OriginalRequestId, CallerId, Operation, MsgId
                             ,{'ok', Responses}) when is_list(Responses), Responses =/= [] ->
    Checked = [checked_reconcile_response(UUID, OriginalRequestId, CallerId
                                         ,Operation, MsgId, Response)
               || Response <- Responses],
    case [Reason || {'error', Reason} <- Checked] of
        [_ | _] -> {'unknown', reconcile_unknown('invalid_response', length(Responses))};
        [] -> aggregate_reconcile_responses([Value || {'ok', Value} <- Checked], Operation)
    end;
classify_reconcile_collection(_, _, _, _, _, {'ok', []}) ->
    {'unknown', reconcile_unknown('empty_collection', 0)};
classify_reconcile_collection(_, _, _, _, _, {'timeout', Responses}) when is_list(Responses) ->
    {'unknown', reconcile_unknown('collection_timeout', length(Responses))};
classify_reconcile_collection(_, _, _, _, _, {'error', 'timeout', Responses}) when is_list(Responses) ->
    {'unknown', reconcile_unknown('collection_timeout', length(Responses))};
classify_reconcile_collection(_, _, _, _, _, _) ->
    {'unknown', reconcile_unknown('query_failed', 0)}.

-spec checked_reconcile_response(binary(), binary(), binary(), binary(), binary(), any()) ->
          {'ok', map()} | {'error', atom()}.
checked_reconcile_response(UUID, OriginalRequestId, CallerId, Operation, MsgId, Response) ->
    try kapi_call:originate_reconcile_resp_v(Response)
        andalso kz_api:msg_id(Response) =:= MsgId
        andalso kz_json:get_ne_binary_value(<<"Originate-UUID">>, Response) =:= UUID
        andalso kz_json:get_ne_binary_value(<<"Originate-Request-ID">>, Response) =:= OriginalRequestId
        andalso kz_json:get_ne_binary_value(<<"Outbound-Call-ID">>, Response) =:= CallerId
        andalso kz_json:get_ne_binary_value(<<"Operation">>, Response) =:= Operation
    of
        'false' -> {'error', 'invalid_correlation'};
        'true' -> sanitize_reconcile_response(CallerId, Response)
    catch _:_ -> {'error', 'invalid_response'}
    end.

-spec sanitize_reconcile_response(binary(), kz_json:object()) ->
          {'ok', map()} | {'error', atom()}.
sanitize_reconcile_response(CallerId, Response) ->
    Responder = bounded_binary(kz_api:node(Response), 512),
    Status = kz_json:get_ne_binary_value(<<"Status">>, Response),
    Base = #{'responder' => Responder, 'status' => status_atom_reconcile(Status)},
    case {is_ne_binary(Responder), maps:get('status', Base)} of
        {'false', _} -> {'error', 'invalid_responder'};
        {_, 'unknown'} -> {'ok', Base};
        {_, State} ->
            MediaNode = bounded_binary(kz_json:get_ne_binary_value(<<"Media-Node">>, Response), 512),
            Epoch = bounded_binary(kz_json:get_ne_binary_value(<<"Module-Epoch">>, Response), 128),
            case is_ne_binary(MediaNode) andalso is_ne_binary(Epoch) of
                'false' -> {'error', 'missing_authoritative_identity'};
                'true' when State =:= 'pending' ->
                    {'ok', Base#{'media_node' => MediaNode, 'module_epoch' => Epoch}};
                'true' -> sanitize_settled_response(CallerId, Response
                                                   ,Base#{'media_node' => MediaNode
                                                         ,'module_epoch' => Epoch})
            end
    end.

-spec sanitize_settled_response(binary(), kz_json:object(), map()) ->
          {'ok', map()} | {'error', atom()}.
sanitize_settled_response(CallerId, Response, Base) ->
    case kz_json:get_ne_binary_value(<<"Outcome">>, Response) of
        <<"success">> ->
            case bounded_binary(kz_json:get_ne_binary_value(<<"Result-Call-ID">>, Response), 512) of
                CallerId -> {'ok', Base#{'outcome' => 'success', 'result_call_id' => CallerId}};
                _ -> {'error', 'result_call_mismatch'}
            end;
        <<"failure">> ->
            case bounded_binary(kz_json:get_ne_binary_value(<<"Failure-Cause">>, Response), 512) of
                'undefined' -> {'error', 'missing_failure_cause'};
                Cause -> {'ok', Base#{'outcome' => 'failure', 'failure_cause' => Cause}}
            end;
        _ -> {'error', 'invalid_outcome'}
    end.

-spec aggregate_reconcile_responses([map()], binary()) -> {'ok', evidence()} | {'unknown', evidence()}.
aggregate_reconcile_responses(Responses, Operation) ->
    Responders = [maps:get('responder', Response) || Response <- Responses],
    Authoritative = [maps:remove('responder', Response) || Response <- Responses,
                      maps:get('status', Response) =/= 'unknown'],
    case length(lists:usort(Responders)) =:= length(Responders) of
        'false' -> {'unknown', reconcile_unknown('duplicate_responder', length(Responses))};
        'true' -> aggregate_authoritative(lists:usort(Authoritative), Responders, Operation)
    end.

-spec aggregate_authoritative([map()], [binary()], binary()) ->
          {'ok', evidence()} | {'unknown', evidence()}.
aggregate_authoritative([], Responders, _Operation) ->
    {'unknown', (reconcile_unknown('not_observed_in_current_module_epochs', length(Responders)))#{
                  'responders' => lists:sort(Responders)}};
aggregate_authoritative([Authoritative], Responders, Operation) ->
    Status = maps:get('status', Authoritative),
    {'ok', Authoritative#{'complete' => 'true', 'responders' => lists:sort(Responders)
                         ,'cancel_acknowledged' => (Operation =:= <<"cancel">>
                                                   andalso Status =:= 'pending')
                         ,'originate_settled' => (Status =:= 'settled')}};
aggregate_authoritative(_, Responders, _Operation) ->
    {'unknown', (reconcile_unknown('conflicting_authoritative_results', length(Responders)))#{
                  'responders' => lists:sort(Responders)}}.

-spec reconcile_unknown(atom(), non_neg_integer()) -> evidence().
reconcile_unknown(Reason, Count) ->
    #{'complete' => 'false', 'status' => 'unknown', 'reason' => Reason
     ,'responder_count' => Count, 'cancel_acknowledged' => 'false'
     ,'originate_settled' => 'unknown'}.

-spec status_atom_reconcile(any()) -> 'pending' | 'settled' | 'unknown'.
status_atom_reconcile(<<"pending">>) -> 'pending';
status_atom_reconcile(<<"settled">>) -> 'settled';
status_atom_reconcile(_) -> 'unknown'.

-spec request_cleanup(kz_json:object()) -> {'ok', evidence()} | {'error', 'invalid_input'}.
request_cleanup(Doc) ->
    request_cleanup_with(Doc, fun query_channel/2, fun query_originate/2
                        ,fun publish_hangup/2).

-spec request_cleanup_with(kz_json:object(), fun((binary(), list()) -> any()),
                           fun((binary(), list()) -> any()),
                           fun((binary(), list()) -> any())) ->
          {'ok', evidence()} | {'error', 'invalid_input'}.
request_cleanup_with(Doc, ChannelQueryFun, ReconcileQueryFun, HangupFun)
  when is_function(ChannelQueryFun, 2), is_function(ReconcileQueryFun, 2)
       andalso is_function(HangupFun, 2) ->
    Observation = observe_with(Doc, ChannelQueryFun),
    case build_cleanup_requests(Doc, Observation) of
        {'error', _} -> {'error', 'invalid_input'};
        {'ok', Requests} ->
            Reconcile = reconcile_originate_with(Doc, 'cancel', ReconcileQueryFun),
            CancelEvidence = reconcile_action(Reconcile),
            HangupEvidence = publish_action('caller_hangup', maps:get('caller_hangup', Requests), HangupFun),
            AgentEvidence = publish_action('agent_hangup', maps:get('agent_hangup', Requests), HangupFun),
            Settled = reconcile_value('originate_settled', Reconcile, 'unknown'),
            {'ok', #{'actions' => [CancelEvidence, HangupEvidence, AgentEvidence]
                    ,'channel_observation' => observation_action(Observation)
                    ,'acknowledged' => reconcile_value('cancel_acknowledged', Reconcile, 'false')
                    ,'originate_settled' => Settled
                    ,'disposition' => 'reconciliation_required'}}
    end;
request_cleanup_with(_, _, _, _) -> {'error', 'invalid_input'}.

-spec build_cleanup_requests(kz_json:object(), {'ok', evidence()} | {'unknown', evidence()} |
                             {'error', 'invalid_input'}) ->
          {'ok', map()} | {'error', 'invalid_input'}.
build_cleanup_requests(Doc, Observation) ->
    case document_account(Doc) of
        {'error', _} -> {'error', 'invalid_input'};
        {_AccountId, _CallIds} ->
            CallerId = bounded_binary(kz_json:get_ne_binary_value(<<"pvt_caller_call_id">>, Doc), 512),
            AgentId = bounded_binary(kz_json:get_ne_binary_value(<<"pvt_agent_call_id">>, Doc), 512),
            PersistedCallerQueue = bounded_binary(
                                     kz_json:get_ne_binary_value(<<"pvt_caller_control_queue">>, Doc), 512),
            OriginalId = kz_json:get_ne_binary_value(<<"original_call_id">>, Doc),
            case CallerId =:= OriginalId orelse AgentId =:= OriginalId
                orelse (is_ne_binary(CallerId) andalso CallerId =:= AgentId) of
                'true' -> {'error', 'invalid_input'};
                'false' ->
                    Caller = proven_hangup(CallerId, PersistedCallerQueue, Observation),
                    Agent = proven_hangup(AgentId, 'undefined', Observation),
                    {'ok', #{'caller_hangup' => Caller, 'agent_hangup' => Agent}}
            end
    end.

-spec proven_hangup(kz_term:api_binary(), kz_term:api_binary(),
                    {'ok', evidence()} | {'unknown', evidence()} | {'error', atom()}) ->
          'unavailable' | {kz_term:ne_binary() | {'media_node', kz_term:ne_binary()}, kz_term:proplist()}.
proven_hangup(CallId, PersistedQueue, {'ok', #{'complete' := 'true', 'channels' := Channels}})
  when is_binary(CallId) ->
    case [Channel || #{'call_id' := Id, 'state' := 'active'}=Channel <- Channels,
                     Id =:= CallId,
                     is_ne_binary(maps:get('active_responder', Channel, 'undefined')),
                     is_ne_binary(maps:get('switch_node', Channel, 'undefined'))] of
        [Channel] -> proven_hangup_target(CallId, PersistedQueue, Channel);
        _ -> 'unavailable'
    end;
proven_hangup(_, _, _) -> 'unavailable'.

-spec proven_hangup_target(kz_term:ne_binary(), kz_term:api_binary(), observation()) ->
          {kz_term:ne_binary() | {'media_node', kz_term:ne_binary()}, kz_term:proplist()}.
proven_hangup_target(CallId, PersistedQueue, #{'switch_node' := Node}=Channel) ->
    %% Channel-Record from ecallmgr does not normally include Control-Queue.
    %% A persisted caller controller may no longer exist after an engine
    %% restart. Prefer it only if this fresh observation also confirms it.
    %% The agent may likewise no longer have a live call-control process,
    %% so the supported node call-command API supplies exact-ID cleanup without
    %% manufacturing a queue name or invoking an arbitrary FreeSWITCH command.
    ObservedQueue = maps:get('control_queue', Channel, 'undefined'),
    case is_ne_binary(PersistedQueue) andalso ObservedQueue =:= PersistedQueue of
        'true' -> {PersistedQueue, hangup_request(CallId)};
        'false' ->
            Request = [{<<"Command">>, <<"call_command">>}
                      ,{<<"Args">>, kz_json:from_list(hangup_request(CallId))}
                      ,{<<"FreeSWITCH-Node">>, Node}
                      ,{<<"Call-ID">>, CallId}
                      ,{<<"Msg-ID">>, kz_binary:rand_hex(12)}
                       | kz_api:default_headers(<<"switch_event">>, <<"command">>, ?APP_NAME, ?APP_VERSION)],
            {{'media_node', Node}, Request}
    end.

-spec publish_hangup(kz_term:ne_binary() | {'media_node', kz_term:ne_binary()}, kz_term:proplist()) -> 'ok'.
publish_hangup({'media_node', Node}, Request) ->
    Node = props:get_value(<<"FreeSWITCH-Node">>, Request),
    kapi_switch:publish_fs_command(Request);
publish_hangup(ControlQueue, Request) ->
    kapi_dialplan:publish_command(ControlQueue, Request).

-spec hangup_request(kz_term:ne_binary()) -> kz_term:proplist().
hangup_request(CallId) ->
    [{<<"Application-Name">>, <<"hangup">>}
    ,{<<"Insert-At">>, <<"now">>}
    ,{<<"Call-ID">>, CallId}
    ,{<<"Msg-ID">>, kz_binary:rand_hex(12)}
     | kz_api:default_headers(<<"call">>, <<"command">>, ?APP_NAME, ?APP_VERSION)].

-spec observation_action({'ok', evidence()} | {'unknown', evidence()} |
                         {'error', 'invalid_input'}) -> map().
observation_action({'ok', Evidence}) -> #{'status' => 'complete', 'evidence' => Evidence};
observation_action({'unknown', Evidence}) -> #{'status' => 'unknown', 'evidence' => Evidence};
observation_action({'error', _}) -> #{'status' => 'unavailable'}.

-spec reconcile_action({'ok', map()} | {'unknown', map()} | {'error', atom()}) -> map().
reconcile_action({'ok', Evidence}) ->
    #{'action' => 'originate_cancel', 'status' => maps:get('status', Evidence)
     ,'acknowledged' => maps:get('cancel_acknowledged', Evidence, 'false')
     ,'originate_settled' => maps:get('originate_settled', Evidence, 'unknown')
     ,'evidence' => Evidence};
reconcile_action({'unknown', Evidence}) ->
    #{'action' => 'originate_cancel', 'status' => 'unknown', 'acknowledged' => 'false'
     ,'originate_settled' => 'unknown', 'reason' => maps:get('reason', Evidence, 'unknown')
     ,'evidence' => Evidence};
reconcile_action({'error', _}) ->
    #{'action' => 'originate_cancel', 'status' => 'unavailable'
     ,'acknowledged' => 'false', 'originate_settled' => 'unknown'}.

-spec reconcile_value(atom(), {'ok', map()} | {'unknown', map()} | {'error', atom()}, any()) -> any().
reconcile_value(Key, {'ok', Evidence}, Default) -> maps:get(Key, Evidence, Default);
reconcile_value(Key, {'unknown', Evidence}, Default) -> maps:get(Key, Evidence, Default);
reconcile_value(_, {'error', _}, Default) -> Default.

-spec publish_action(atom(), 'unavailable' | {binary(), list()}, fun((binary(), list()) -> any())) -> map().
publish_action(Kind, 'unavailable', _PublishFun) ->
    #{'action' => Kind, 'status' => 'unavailable', 'acknowledged' => 'false'};
publish_action(Kind, {Target, Request}, PublishFun) ->
    Status = try PublishFun(Target, Request) of
                 'ok' -> 'requested';
                 _ -> 'publish_failed'
             catch _:_ -> 'publish_failed'
             end,
    Reference = case Kind of
                    'originate_cancel' -> props:get_value(<<"Originate-UUID">>, Request);
                    'caller_hangup' -> props:get_value(<<"Call-ID">>, Request);
                    'agent_hangup' -> props:get_value(<<"Call-ID">>, Request)
                end,
    #{'action' => Kind, 'reference' => Reference, 'status' => Status
     ,'acknowledged' => 'false'}.

-spec observation_context(kz_json:object()) ->
          {kz_term:ne_binary(), [kz_term:ne_binary()]} | {'error', 'invalid_input'}.
observation_context(Doc) ->
    case document_account(Doc) of
        {'error', _}=Error -> Error;
        {AccountId, CallIds} when CallIds =/= [] -> {AccountId, CallIds};
        _ -> {'error', 'invalid_input'}
    end.

-spec originate_context(kz_json:object()) ->
          {kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()} |
          {'error', 'invalid_input'}.
originate_context(Doc) ->
    case document_account(Doc) of
        {'error', _} -> {'error', 'invalid_input'};
        {_AccountId, _CallIds} ->
            UUID = bounded_binary(kz_json:get_ne_binary_value(<<"pvt_originate_uuid">>, Doc), 512),
            OriginalRequestId = bounded_binary(
                                  kz_json:get_ne_binary_value(<<"pvt_originate_msg_id">>, Doc), 512),
            CallerId = bounded_binary(kz_json:get_ne_binary_value(<<"pvt_caller_call_id">>, Doc), 512),
            case is_ne_binary(UUID) andalso is_ne_binary(OriginalRequestId)
                andalso is_ne_binary(CallerId) of
                'true' -> {UUID, OriginalRequestId, CallerId};
                'false' -> {'error', 'invalid_input'}
            end
    end.

-spec document_account(kz_json:object()) ->
          {kz_term:ne_binary(), [kz_term:ne_binary()]} | {'error', 'invalid_input'}.
document_account(Doc) ->
    try kz_json:is_json_object(Doc) of
        'true' ->
            AccountId = bounded_binary(kz_json:get_ne_binary_value(<<"pvt_account_id">>, Doc), 64),
            QueueId = bounded_binary(kz_json:get_ne_binary_value(<<"queue_id">>, Doc), 512),
            Type = kz_json:get_ne_binary_value(<<"pvt_type">>, Doc),
            case is_ne_binary(AccountId) andalso is_ne_binary(QueueId)
                andalso Type =:= <<"acdc_callback">> of
                'true' -> {AccountId, relevant_call_ids(Doc)};
                'false' -> {'error', 'invalid_input'}
            end;
        'false' -> {'error', 'invalid_input'}
    catch _:_ -> {'error', 'invalid_input'}
    end.

-spec status_atom(any()) -> channel_state() | 'tmpdown'.
status_atom(<<"active">>) -> 'active';
status_atom(<<"terminated">>) -> 'terminated';
status_atom(<<"tmpdown">>) -> 'tmpdown';
status_atom(_) -> 'unknown'.

-spec bounded_binary(any(), pos_integer()) -> kz_term:api_ne_binary().
bounded_binary(Value, Max) when is_binary(Value), byte_size(Value) > 0, byte_size(Value) =< Max -> Value;
bounded_binary(_, _) -> 'undefined'.

-spec is_ne_binary(any()) -> boolean().
is_ne_binary(Value) -> is_binary(Value) andalso byte_size(Value) > 0.
