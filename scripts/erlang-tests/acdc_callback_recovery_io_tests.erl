%%% SPDX-License-Identifier: MPL-2.0
-module(acdc_callback_recovery_io_tests).

-include_lib("eunit/include/eunit.hrl").

-define(ACCOUNT, <<"11111111111111111111111111111111">>).
-define(ORIGINAL, <<"original-call">>).
-define(CALLER, <<"returned-caller">>).
-define(AGENT, <<"agent-leg">>).

complete_active_and_terminated_collection_test() ->
    Msg = <<"msg-active">>,
    Result = {'ok', [response(<<"one@host">>, ?CALLER, Msg, <<"active">>,
                              [{<<"Other-Leg-Call-ID">>, ?AGENT}]),
                     response(<<"two@host">>, ?CALLER, Msg, <<"terminated">>, [])]},
    {'ok', Observation} = acdc_callback_recovery_io:classify_collection(
                            ?ACCOUNT, ?CALLER, Msg, Result),
    ?assertEqual(active, maps:get(state, Observation)),
    ?assertEqual(?AGENT, maps:get(other_leg_call_id, Observation)),
    ?assertEqual(2, maps:get(responder_count, Observation)).

complete_all_terminated_is_point_in_time_evidence_test() ->
    Msg = <<"msg-down">>,
    {'ok', Observation} = acdc_callback_recovery_io:classify_collection(
                            ?ACCOUNT, ?CALLER, Msg,
                            {'ok', [response(<<"one@host">>, ?CALLER, Msg, <<"terminated">>, []),
                                    response(<<"two@host">>, ?CALLER, Msg, <<"terminated">>, [])]}),
    ?assertEqual(terminated, maps:get(state, Observation)),
    ?assertEqual(complete, maps:get(reason, Observation)).

timeouts_empty_and_node_failures_are_unknown_test() ->
    Msg = <<"msg-unknown">>,
    lists:foreach(
      fun(Result) ->
          {'unknown', Observation} = acdc_callback_recovery_io:classify_collection(
                                       ?ACCOUNT, ?CALLER, Msg, Result),
          ?assertEqual(unknown, maps:get(state, Observation))
      end,
      [{'ok', []}
      ,{'timeout', [response(<<"one@host">>, ?CALLER, Msg, <<"terminated">>, [])]}
      ,{'error', timeout}
      ,{'ok', [response(<<"one@host">>, ?CALLER, Msg, <<"tmpdown">>, [])]}]).

correlation_account_and_unique_responder_are_mandatory_test() ->
    Msg = <<"msg-correlated">>,
    Active = response(<<"one@host">>, ?CALLER, Msg, <<"active">>, []),
    BadAccount = kz_json:set_value([<<"Channel-Record">>, <<"Custom-Channel-Vars">>, <<"Account-ID">>],
                                   <<"foreign-account">>, Active),
    WrongMsg = kz_json:set_value(<<"Msg-ID">>, <<"other">>, Active),
    WrongCall = kz_json:set_value(<<"Call-ID">>, <<"other">>, Active),
    WrongRecordCall = kz_json:set_value([<<"Channel-Record">>, <<"Call-ID">>], <<"other">>, Active),
    WrongRecordAccount = kz_json:set_value([<<"Channel-Record">>, <<"Account-ID">>], <<"other">>, Active),
    Duplicate = {'ok', [Active, response(<<"one@host">>, ?CALLER, Msg, <<"terminated">>, [])]},
    MultipleActive = {'ok', [Active, response(<<"two@host">>, ?CALLER, Msg, <<"active">>, [])]},
    lists:foreach(
      fun(Result) ->
          ?assertMatch({'unknown', _}, acdc_callback_recovery_io:classify_collection(
                                         ?ACCOUNT, ?CALLER, Msg, Result))
      end, [{'ok', [BadAccount]}, {'ok', [WrongMsg]}, {'ok', [WrongCall]},
            {'ok', [WrongRecordCall]}, {'ok', [WrongRecordAccount]}, Duplicate, MultipleActive]).

observe_queries_persisted_and_derived_legs_with_exact_bridge_test() ->
    Doc = reservation([{<<"pvt_agent_call_id">>, ?AGENT}]),
    Query = fun(Request, MsgId) ->
                    ?assertEqual(true, props:get_value(<<"Channel-Record">>, Request)),
                    CallId = props:get_value(<<"Call-ID">>, Request),
                    Other = case CallId of
                                ?CALLER -> [{<<"Other-Leg-Call-ID">>, ?AGENT}];
                                ?AGENT -> [{<<"Other-Leg-Call-ID">>, ?CALLER}];
                                _ -> []
                            end,
                    State = case CallId of ?ORIGINAL -> <<"terminated">>; _ -> <<"active">> end,
                    {'ok', [response(<<"one@host">>, CallId, MsgId, State, Other),
                            response(<<"two@host">>, CallId, MsgId, <<"terminated">>, [])]}
            end,
    {'ok', Evidence} = acdc_callback_recovery_io:observe_with(Doc, Query),
    ?assertEqual(true, maps:get(complete, Evidence)),
    ?assertEqual(bridged, maps:get(state, maps:get(bridge, Evidence))),
    ?assertEqual(lists:sort([?CALLER, ?AGENT]),
                 maps:get(call_ids, maps:get(bridge, Evidence))),
    ?assertEqual(3, length(maps:get(channels, Evidence))).

one_way_or_missing_bridge_is_never_bridge_proof_test() ->
    Caller = #{call_id => ?CALLER, state => active, other_leg_call_id => ?AGENT},
    AgentMissing = #{call_id => ?AGENT, state => terminated},
    ?assertEqual(unknown,
                 maps:get(state, acdc_callback_recovery_io:bridge_summary([Caller, AgentMissing]))),
    ?assertEqual(not_observed,
                 maps:get(state, acdc_callback_recovery_io:bridge_summary(
                                   [#{call_id => ?CALLER, state => active}]))).

cleanup_requests_are_correlated_and_use_supported_apis_test() ->
    Observation = cleanup_observation([active_channel(?CALLER, <<"caller-control">>)]),
    {'ok', Requests} = acdc_callback_recovery_io:build_cleanup_requests(
                         reservation([]), Observation),
    {<<"caller-control">>, Hangup} = maps:get(caller_hangup, Requests),
    ?assertEqual(true, kapi_dialplan:hangup_v(Hangup)),
    ?assertEqual(?CALLER, props:get_value(<<"Call-ID">>, Hangup)),
    ?assertEqual(unavailable, maps:get(agent_hangup, Requests)),
    AgentDoc = reservation([{<<"pvt_agent_call_id">>, ?AGENT}]),
    Both = cleanup_observation([active_channel(?CALLER, <<"caller-control">>),
                                active_channel(?AGENT, <<"agent-control">>)]),
    {'ok', BothRequests} = acdc_callback_recovery_io:build_cleanup_requests(AgentDoc, Both),
    {{media_node, <<"freeswitch@one">>}, AgentHangup} = maps:get(agent_hangup, BothRequests),
    assert_node_hangup(?AGENT, AgentHangup),
    Mismatched = kz_json:set_value(<<"pvt_caller_control_queue">>, <<"stale-control">>, AgentDoc),
    {'ok', MismatchRequests} = acdc_callback_recovery_io:build_cleanup_requests(Mismatched, Both),
    {{media_node, <<"freeswitch@one">>}, CallerFallback} = maps:get(caller_hangup, MismatchRequests),
    assert_node_hangup(?CALLER, CallerFallback).

real_channel_records_without_control_queue_clean_both_exact_legs_test() ->
    Self = self(),
    Doc = reservation([{<<"pvt_agent_call_id">>, ?AGENT}]),
    Query = fun(Request, MsgId) ->
        CallId = props:get_value(<<"Call-ID">>, Request),
        Status = case CallId of ?ORIGINAL -> <<"terminated">>; _ -> <<"active">> end,
        {'ok', [response(<<"one@host">>, CallId, MsgId, Status, []),
                response(<<"two@host">>, CallId, MsgId, <<"terminated">>, [])]}
    end,
    Hangup = fun({media_node, <<"freeswitch@one">>}, Request) ->
        CallId = props:get_value(<<"Call-ID">>, Request),
        assert_node_hangup(CallId, Request),
        Self ! {cleanup, CallId}, ok
    end,
    {'ok', Evidence} = acdc_callback_recovery_io:request_cleanup_with(
        Doc, Query, fun(_, _) -> {timeout, []} end, Hangup),
    ?assertEqual([unknown, requested, requested],
                 [maps:get(status, Action) || Action <- maps:get(actions, Evidence)]),
    ?assertEqual(unknown, maps:get(originate_settled, Evidence)),
    ?assertEqual(reconciliation_required, maps:get(disposition, Evidence)),
    receive {cleanup, ?CALLER} -> ok after 0 -> ?assert(false) end,
    receive {cleanup, ?AGENT} -> ok after 0 -> ?assert(false) end,
    receive {cleanup, _} -> ?assert(false) after 0 -> ok end.

cleanup_refuses_foreign_partial_conflicting_and_inconsistent_node_snapshots_test() ->
    Doc = reservation([{<<"pvt_agent_call_id">>, ?AGENT}]),
    lists:foreach(fun(Mode) ->
        Query = fun(Request, MsgId) ->
            CallId = props:get_value(<<"Call-ID">>, Request),
            Active = response(<<"one@host">>, CallId, MsgId, <<"active">>, []),
            Down = response(<<"two@host">>, CallId, MsgId, <<"terminated">>, []),
            case {Mode, CallId} of
                {foreign_account, ?AGENT} ->
                    {ok, [kz_json:set_value([<<"Channel-Record">>, <<"Custom-Channel-Vars">>, <<"Account-ID">>],
                                            <<"foreign">>, Active), Down]};
                {missing_node, ?AGENT} ->
                    {ok, [kz_json:delete_key([<<"Channel-Record">>, <<"Media-Node">>], Active), Down]};
                {partial, ?AGENT} -> {timeout, [Active]};
                {conflicting, ?AGENT} ->
                    {ok, [Active, response(<<"two@host">>, CallId, MsgId, <<"active">>, [])]};
                {different_responders, ?AGENT} -> {ok, [Active]};
                _ -> {ok, [Active, Down]}
            end
        end,
        Publish = fun(_, _) -> erlang:error(unproven_cleanup_must_not_publish) end,
        {'ok', Evidence} = acdc_callback_recovery_io:request_cleanup_with(
            Doc, Query, fun(_, _) -> {timeout, []} end, Publish),
        ?assertEqual([unknown, unavailable, unavailable],
                     [maps:get(status, Action) || Action <- maps:get(actions, Evidence)]),
        ?assertMatch(#{status := unknown}, maps:get(channel_observation, Evidence))
    end, [foreign_account, missing_node, partial, conflicting, different_responders]).

cleanup_never_targets_original_or_duplicate_reserved_leg_test() ->
    Observation = cleanup_observation([active_channel(?CALLER, <<"caller-control">>)]),
    lists:foreach(fun(Doc) ->
        ?assertEqual({error, invalid_input},
                     acdc_callback_recovery_io:build_cleanup_requests(Doc, Observation))
    end, [reservation([{<<"pvt_agent_call_id">>, ?ORIGINAL}]),
          reservation([{<<"pvt_agent_call_id">>, ?CALLER}]),
          kz_json:set_value(<<"pvt_caller_call_id">>, ?ORIGINAL, reservation([]))]).

cleanup_does_not_target_an_unpersisted_derived_leg_test() ->
    Observation = cleanup_observation([active_channel(?CALLER, <<"caller-control">>),
                                       active_channel(?AGENT, <<"agent-control">>)]),
    {ok, Requests} = acdc_callback_recovery_io:build_cleanup_requests(reservation([]), Observation),
    ?assertEqual(unavailable, maps:get(agent_hangup, Requests)).

reconcile_pending_cancel_is_acknowledged_but_never_settled_test() ->
    Self = self(),
    Query = fun(Request, MsgId) ->
                    Self ! {queried, Request},
                    {'ok', [kz_json:set_value(<<"Operation">>, <<"cancel">>,
                                              reconcile_response(<<"apps-one">>, MsgId, <<"pending">>
                                                                 ,[{<<"Media-Node">>, <<"fs@one">>}
                                                                  ,{<<"Module-Epoch">>, <<"epoch-one">>}]))
                           ,kz_json:set_value(<<"Operation">>, <<"cancel">>,
                                             reconcile_response(<<"apps-two">>, MsgId, <<"unknown">>, []))]}
            end,
    Hangup = fun(Target, Request) -> Self ! {published, Target, Request}, ok end,
    {'ok', Evidence} = acdc_callback_recovery_io:request_cleanup_with(
                         reservation([]), fun channel_query/2, Query, Hangup),
    ?assertEqual(true, maps:get(acknowledged, Evidence)),
    ?assertEqual(false, maps:get(originate_settled, Evidence)),
    ?assertEqual(reconciliation_required, maps:get(disposition, Evidence)),
    ?assertMatch(#{status := complete}, maps:get(channel_observation, Evidence)),
    ?assertEqual([pending, requested, unavailable],
                 [maps:get(status, Action) || Action <- maps:get(actions, Evidence)]),
    receive {queried, ReconcileReq} ->
                ?assertEqual(true, kapi_call:originate_reconcile_req_v(ReconcileReq)),
                ?assertEqual(<<"originate-request">>,
                             props:get_value(<<"Originate-Request-ID">>, ReconcileReq))
    after 0 -> ?assert(false)
    end,
    receive {published, {media_node, <<"freeswitch@one">>}, _} -> ok after 0 -> ?assert(false) end.

settled_reconciliation_requires_exact_success_call_id_test() ->
    Query = fun(_Request, MsgId) ->
                    {'ok', [reconcile_response(<<"apps-one">>, MsgId, <<"settled">>
                                              ,[{<<"Media-Node">>, <<"fs@one">>}
                                               ,{<<"Module-Epoch">>, <<"epoch-one">>}
                                               ,{<<"Outcome">>, <<"success">>}
                                               ,{<<"Result-Call-ID">>, ?CALLER}]),
                            reconcile_response(<<"apps-two">>, MsgId, <<"unknown">>, [])]}
            end,
    {'ok', Evidence} = acdc_callback_recovery_io:reconcile_originate_with(
                         reservation([]), status, Query),
    ?assertEqual(settled, maps:get(status, Evidence)),
    ?assertEqual(true, maps:get(originate_settled, Evidence)),
    Wrong = fun(_Request, MsgId) ->
                    {'ok', [reconcile_response(<<"apps-one">>, MsgId, <<"settled">>
                                              ,[{<<"Media-Node">>, <<"fs@one">>}
                                               ,{<<"Module-Epoch">>, <<"epoch-one">>}
                                               ,{<<"Outcome">>, <<"success">>}
                                               ,{<<"Result-Call-ID">>, <<"foreign-call">>}])]}
            end,
    ?assertMatch({unknown, _}, acdc_callback_recovery_io:reconcile_originate_with(
                                  reservation([]), status, Wrong)).

reconcile_timeout_conflict_and_unknown_never_settle_test() ->
    Timeout = fun(_, _) -> {timeout, []} end,
    ?assertMatch({unknown, _}, acdc_callback_recovery_io:reconcile_originate_with(
                                  reservation([]), cancel, Timeout)),
    Conflict = fun(_Request, MsgId) ->
                       {'ok', [reconcile_response(<<"apps-one">>, MsgId, <<"pending">>
                                                 ,[{<<"Media-Node">>, <<"fs@one">>}
                                                  ,{<<"Module-Epoch">>, <<"epoch-one">>}]),
                               reconcile_response(<<"apps-two">>, MsgId, <<"settled">>
                                                 ,[{<<"Media-Node">>, <<"fs@two">>}
                                                  ,{<<"Module-Epoch">>, <<"epoch-two">>}
                                                  ,{<<"Outcome">>, <<"failure">>}
                                                  ,{<<"Failure-Cause">>, <<"ORIGINATOR_CANCEL">>}])]}
               end,
    ?assertMatch({unknown, _}, acdc_callback_recovery_io:reconcile_originate_with(
                                  reservation([]), status, Conflict)).

publish_failure_and_missing_control_stay_reconciliation_required_test() ->
    Fail = fun(_, _) -> erlang:error(no_broker) end,
    {'ok', Failed} = acdc_callback_recovery_io:request_cleanup_with(
                       reservation([]), Fail, Fail, Fail),
    ?assertEqual([unknown, unavailable, unavailable],
                 [maps:get(status, Action) || Action <- maps:get(actions, Failed)]),
    Missing = kz_json:delete_key(<<"pvt_caller_control_queue">>, reservation([])),
    {'ok', Unavailable} = acdc_callback_recovery_io:request_cleanup_with(
                            Missing, fun channel_query/2, Fail, Fail),
    ?assertEqual([unknown, publish_failed, unavailable],
                 [maps:get(status, Action) || Action <- maps:get(actions, Unavailable)]),
    ?assertEqual(reconciliation_required, maps:get(disposition, Unavailable)).

invalid_reservations_are_rejected_test() ->
    ?assertEqual({error, invalid_input}, acdc_callback_recovery_io:observe_with(kz_json:new(), fun(_, _) -> ok end)),
    ?assertEqual({error, invalid_input}, acdc_callback_recovery_io:request_cleanup_with(
                                          kz_json:new(), fun(_, _) -> ok end,
                                          fun(_, _) -> ok end, fun(_, _) -> ok end)).

channel_query(Request, MsgId) ->
    CallId = props:get_value(<<"Call-ID">>, Request),
    case CallId of
        ?CALLER ->
            {'ok', [response(<<"one@host">>, CallId, MsgId, <<"active">>, []),
                    response(<<"two@host">>, CallId, MsgId, <<"terminated">>, [])]};
        _ ->
            {'ok', [response(<<"one@host">>, CallId, MsgId, <<"terminated">>, []),
                    response(<<"two@host">>, CallId, MsgId, <<"terminated">>, [])]}
    end.

cleanup_observation(Channels) ->
    {ok, #{complete => true, channels => Channels, bridge => #{state => not_observed}, reasons => []}}.

active_channel(CallId, ControlQueue) ->
    #{call_id => CallId, state => active, active_responder => <<"one@host">>,
      switch_node => <<"freeswitch@one">>, control_queue => ControlQueue, answered => false}.

assert_node_hangup(CallId, Request) ->
    ?assertEqual(true, kapi_switch:fs_command_v(Request)),
    ?assertEqual(<<"acdc">>, props:get_value(<<"App-Name">>, Request)),
    ?assertEqual(<<"call_command">>, props:get_value(<<"Command">>, Request)),
    ?assertEqual(<<"freeswitch@one">>, props:get_value(<<"FreeSWITCH-Node">>, Request)),
    ?assertEqual(CallId, props:get_value(<<"Call-ID">>, Request)),
    Hangup = props:get_value(<<"Args">>, Request),
    ?assertEqual(true, kapi_dialplan:hangup_v(Hangup)),
    ?assertEqual(CallId, kz_api:call_id(Hangup)),
    ?assertEqual(<<"hangup">>, kapi_dialplan:application_name(Hangup)).

reservation(Extra) ->
    kz_json:from_list([{<<"_id">>, <<"acdc-callback-fixture">>}
                      ,{<<"pvt_account_id">>, ?ACCOUNT}
                      ,{<<"pvt_type">>, <<"acdc_callback">>}
                      ,{<<"queue_id">>, <<"queue-fixture">>}
                      ,{<<"original_call_id">>, ?ORIGINAL}
                      ,{<<"pvt_caller_call_id">>, ?CALLER}
                      ,{<<"pvt_originate_uuid">>, <<"originate-uuid">>}
                      ,{<<"pvt_originate_queue">>, <<"originate-private">>}
                      ,{<<"pvt_originate_msg_id">>, <<"originate-request">>}
                      ,{<<"pvt_caller_control_queue">>, <<"caller-control">>} | Extra]).

reconcile_response(Node, MsgId, Status, Extra) ->
    kz_json:from_list([{<<"Originate-UUID">>, <<"originate-uuid">>}
                      ,{<<"Originate-Request-ID">>, <<"originate-request">>}
                      ,{<<"Outbound-Call-ID">>, ?CALLER}
                      ,{<<"Operation">>, <<"status">>}
                      ,{<<"Status">>, Status}
                      ,{<<"Msg-ID">>, MsgId}
                      ,{<<"Node">>, Node}
                       | Extra ++ kz_api:default_headers(<<"channel">>, <<"originate_reconcile_resp">>
                                                       ,<<"ecallmgr">>, <<"5.0.0">>)]).

response(Node, CallId, MsgId, Status, Extra) ->
    Base = [{<<"Call-ID">>, CallId}
           ,{<<"Status">>, Status}
           ,{<<"Msg-ID">>, MsgId}
           ,{<<"Node">>, Node}
            | kz_api:default_headers(<<"channel">>, <<"channel_status_resp">>
                                    ,<<"ecallmgr">>, <<"5.0.0">>)],
    ChannelRecord = case Status of
                        <<"active">> ->
                            [{<<"Channel-Record">>,
                              kz_json:from_list(
                                Extra ++ [{<<"Media-Node">>, <<"freeswitch@one">>}
                                         ,{<<"Call-ID">>, CallId}
                                         ,{<<"Account-ID">>, ?ACCOUNT}
                                         ,{<<"Custom-Channel-Vars">>,
                                           kz_json:from_list([{<<"Account-ID">>, ?ACCOUNT}])}])}];
                        _ -> []
                    end,
    kz_json:from_list(ChannelRecord ++ Base).
