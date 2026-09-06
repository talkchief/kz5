%%% SPDX-License-Identifier: MPL-2.0
%%% Durable, account-scoped virtual queue reservations. This module never dials.
%%% Only the queue coordinator may supply enqueue metadata or activate a record;
%%% HTTP callers must not be allowed to create arbitrary callback reservations.
-module(acdc_callback_store).

-export([create/5, get/3, find/3, list/4, activate/3, claim/5
        ,bind_leg/6, bind_originate/7, bind_control/6, bind_registration/6, bind_selection/5
        ,advance/6, renew/5, adopt/5, mark_reconciliation/5, cancel/3, expire/3, public/1
        ]).

-include("acdc.hrl").

-define(TYPE, <<"acdc_callback">>).
-define(IDENTITY_KEYS, [<<"queue_id">>, <<"original_call_id">>, <<"number">>
                       ,<<"enqueued_at">>, <<"enqueue_sequence">>, <<"priority">>
                       ,<<"language">>, <<"max_attempts">>, <<"retry_delay">>, <<"ttl">>]).
-define(AUTHORITY_KEYS, [<<"pvt_authority_id">>, <<"pvt_authority_type">>, <<"pvt_account_realm">>]).
-define(ACTIVE, [<<"dialing">>, <<"confirming">>, <<"connecting">>]).
-define(TERMINAL, [<<"completed">>, <<"cancelled">>, <<"failed">>, <<"expired">>]).

-type doc_result() :: {'ok', kz_json:object()} | {'error', any()}.
-type cursor() :: 'undefined' | list().

%% The deterministic ID makes retransmitted registration requests idempotent.
%% Original enqueue order is immutable; activating/retrying never changes it.
-spec create(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object(), kz_json:object()) -> doc_result().
create(AccountId, QueueId, CallId, Registration, Authority) ->
    case valid_scope(AccountId, QueueId) andalso valid_text(CallId, 512)
        andalso kz_json:is_json_object(Registration) andalso valid_authority(Authority) of
        'false' -> {'error', 'invalid_registration'};
        'true' ->
            %% The coordinator supplies this separately after resolving the
            %% queue's configured outbound identity. Inbound SIP/CID fields
            %% and caller/menu registration payloads are not authority.
            Values = kz_json:set_values(
                       [{<<"pvt_authority_id">>, kz_json:get_value(<<"id">>, Authority)}
                       ,{<<"pvt_authority_type">>, kz_json:get_value(<<"type">>, Authority)}
                       ,{<<"pvt_account_realm">>, kz_json:get_value(<<"account_realm">>, Authority)}]
                       ,registration_values(QueueId, CallId, Registration)),
            case valid_registration(Values) of
                'false' -> {'error', 'invalid_registration'};
                'true' -> create_doc(AccountId, QueueId, CallId, Values)
            end
    end.

create_doc(AccountId, QueueId, CallId, Values) ->
    Now = kz_time:now_s(),
    Db = kzs_util:format_account_db(AccountId),
    Id = callback_id(QueueId, CallId),
    Doc = kz_json:set_values([{<<"_id">>, Id}, {<<"pvt_type">>, ?TYPE}
                             ,{<<"pvt_account_id">>, AccountId}, {<<"pvt_account_db">>, Db}
                             ,{<<"pvt_vsn">>, <<"1">>}, {<<"pvt_created">>, Now}
                             ,{<<"pvt_modified">>, Now}, {<<"status">>, <<"registering">>}
                             ,{<<"attempts">>, 0}, {<<"next_attempt_at">>, Now}
                             ,{<<"expires_at">>, Now + kz_json:get_value(<<"ttl">>, Values)}
                             ], Values),
    case kz_datamgr:save_doc(Db, Doc) of
        {'error', 'conflict'} ->
            case get(AccountId, QueueId, Id) of
                {'ok', Existing} ->
                    case same_registration(Values, Existing) of
                        'true' -> {'ok', Existing};
                        'false' -> {'error', 'registration_conflict'}
                    end;
                Error -> Error
            end;
        Result -> Result
    end.

-spec get(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> doc_result().
get(AccountId, QueueId, Id) ->
    case valid_scope(AccountId, QueueId) andalso valid_id(Id) of
        'false' -> {'error', 'not_found'};
        'true' ->
            %% Never use a cached document for ownership or cancellation.
            case kz_datamgr:open_doc(kzs_util:format_account_db(AccountId), Id) of
                {'ok', Doc} ->
                    case owns_doc(AccountId, QueueId, Doc) of
                        'true' -> {'ok', Doc};
                        'false' -> {'error', 'not_found'}
                    end;
                Error -> Error
            end
    end.

%% Queue redelivery resolves the reservation from the immutable original UUID;
%% no live-channel presence assumption may discard a virtual member.
-spec find(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> doc_result().
find(AccountId, QueueId, OriginalCallId) ->
    case valid_scope(AccountId, QueueId) andalso valid_text(OriginalCallId, 512) of
        'true' -> get(AccountId, QueueId, callback_id(QueueId, OriginalCallId));
        'false' -> {'error', 'not_found'}
    end.

%% Bounded, keyset-paginated listing. The cursor is the last returned view key.
%% The HTTP adapter must return public/1, never the documents' private leases.
-spec list(kz_term:ne_binary(), kz_term:ne_binary(), cursor(), pos_integer()) ->
          {'ok', kz_json:objects(), cursor()} | {'error', any()}.
list(AccountId, QueueId, Cursor, Limit)
  when is_integer(Limit), Limit >= 1, Limit =< 100 ->
    case valid_scope(AccountId, QueueId) andalso valid_cursor(QueueId, Cursor) of
        'false' -> {'error', 'invalid_cursor'};
        'true' ->
            %% A longer key sorts strictly after the last returned four-part
            %% key. skip=1 loses the next record if the cursor doc was deleted.
            Start = case Cursor of 'undefined' -> [QueueId]; _ -> Cursor ++ [kz_json:new()] end,
            %% This pinned Couchbeam accepts the include_docs atom, but silently
            %% drops {include_docs,true}; rows without their docs cannot be used.
            Options = ['include_docs', {'startkey', Start}, {'endkey', [QueueId, kz_json:new()]}
                       ,{'limit', Limit + 1}],
            case kz_datamgr:get_results(kzs_util:format_account_db(AccountId)
                                      ,<<"acdc_callbacks/by_queue">>, Options) of
                {'ok', Rows} -> list_result(AccountId, QueueId, Rows, Limit);
                Error -> Error
            end
    end;
list(_, _, _, _) -> {'error', 'invalid_limit'}.

list_result(AccountId, QueueId, Rows, Limit) ->
    Page = lists:sublist(Rows, Limit),
    Docs = [kz_json:get_json_value(<<"doc">>, Row) || Row <- Page],
    case lists:all(fun(Doc) -> owns_doc(AccountId, QueueId, Doc) end, Docs) of
        'false' -> {'error', 'invalid_stored_reservation'};
        'true' ->
            Next = case length(Rows) > Limit of
                       'true' -> kz_json:get_value(<<"key">>, lists:last(Page));
                       'false' -> 'undefined'
                   end,
            {'ok', Docs, Next}
    end.

%% Activation is the durable half of the queue acknowledgement barrier. The
%% coordinator must retain the original member until this write succeeds.
-spec activate(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> doc_result().
activate(AccountId, QueueId, Id) ->
    update(AccountId, QueueId, Id,
           fun(Doc, Now) ->
                   case {status(Doc), expired(Doc, Now)} of
                       {<<"registering">>, 'false'} -> changed(Doc, <<"queued">>, Now);
                       {<<"queued">>, 'false'} -> {'unchanged', Doc};
                       {_, 'true'} -> {'error', 'expired'};
                       _ -> {'error', 'invalid_state'}
                   end
           end).

%% Preserve the handshake identity before activation so a redelivered worker
%% can replay the same ACK and honor a timed-out caller's correlated resume.
-spec bind_registration(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> doc_result().
bind_registration(AccountId, QueueId, Id, RequestId, PauseId, Controller) ->
    case matches(RequestId, <<"^[0-9a-f]{32}$">>) andalso matches(PauseId, <<"^[0-9a-f]{48}$">>)
        andalso valid_text(Controller, 255) of
        'false' -> {'error', 'invalid_registration'};
        'true' ->
            Values = [{<<"pvt_registration_request_id">>, RequestId}, {<<"pvt_pause_id">>, PauseId}
                      ,{<<"pvt_controller_queue">>, Controller}],
            update(AccountId, QueueId, Id,
                   fun(Doc, Now) ->
                       Same = lists:all(fun({Key, Value}) -> kz_json:get_value(Key, Doc) =:= Value end, Values),
                       Empty = lists:all(fun({Key, _}) -> kz_json:get_value(Key, Doc) =:= 'undefined' end, Values),
                       case {Same, Empty, status(Doc)} of
                           {'true', _, _} -> {'unchanged', Doc};
                           {_, 'true', <<"registering">>} -> changed(kz_json:set_values(Values, Doc), status(Doc), Now);
                           _ -> {'error', 'registration_conflict'}
                       end
                   end)
    end.

%% Exactly one revision-CAS winner owns a given attempt. A lease expiry is NOT
%% permission to redial: the previous worker may have an outstanding channel.
%% Reconciliation of all recorded call IDs must precede any future recovery.
-spec claim(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), pos_integer()) -> doc_result().
claim(AccountId, QueueId, Id, Owner, LeaseSeconds) ->
    case valid_text(Owner, 128) andalso bounded(LeaseSeconds, 5, 300) of
        'false' -> {'error', 'invalid_lease'};
        'true' -> update(AccountId, QueueId, Id,
                         fun(Doc, Now) -> claim_doc(Doc, Owner, LeaseSeconds, Now) end)
    end.

claim_doc(Doc, Owner, Seconds, Now) ->
    case lists:member(status(Doc), ?ACTIVE ++ [<<"cancelling">>]) of
        'true' ->
            case lease_until(Doc) =< Now of
                'true' -> {'error', 'reconciliation_required'};
                'false' -> {'error', 'busy'}
            end;
        'false' -> claim_waiting(Doc, Owner, Seconds, Now)
    end.

claim_waiting(Doc, Owner, Seconds, Now) ->
    case {lists:member(status(Doc), [<<"queued">>, <<"retry_wait">>])
         ,expired(Doc, Now), attempts(Doc) >= kz_json:get_integer_value(<<"max_attempts">>, Doc, 0)
         ,kz_json:get_integer_value(<<"next_attempt_at">>, Doc, 0) > Now} of
        {'false', _, _, _} -> {'error', 'invalid_state'};
        {_, 'true', _, _} -> {'error', 'expired'};
        {_, _, 'true', _} -> {'error', 'attempt_limit'};
        {_, _, _, 'true'} -> {'error', 'not_due'};
        _ ->
            Lease = kz_json:from_list([{<<"owner">>, Owner}, {<<"token">>, kz_binary:rand_hex(24)}
                                      ,{<<"until">>, min(Now + Seconds, expires_at(Doc))}]),
            changed(kz_json:set_values([{<<"pvt_lease">>, Lease}, {<<"attempts">>, attempts(Doc) + 1}
                                       %% Record a deterministic-for-this-attempt
                                       %% caller UUID BEFORE any originate command.
                                       ,{<<"pvt_caller_call_id">>, kz_binary:rand_hex(16)}
                                       ,{<<"attempt_started_at">>, Now}], Doc)
                   ,<<"dialing">>, Now)
    end.

%% If an existing parked agent leg participates, persist its ID before issuing
%% commands against it. Rebinding to a different leg requires a new attempt.
-spec bind_leg(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), 'agent', kz_term:ne_binary()) -> doc_result().
bind_leg(AccountId, QueueId, Id, Token, 'agent', CallId) ->
    case valid_text(Token, 128) andalso valid_text(CallId, 512) of
        'false' -> {'error', 'invalid_leg'};
        'true' -> update(AccountId, QueueId, Id,
                         fun(Doc, Now) ->
                                 case owns_lease(Doc, Token, Now) of
                                     'ok' ->
                                         case kz_json:get_value(<<"pvt_agent_call_id">>, Doc) of
                                             'undefined' -> changed(kz_json:set_value(<<"pvt_agent_call_id">>, CallId, Doc)
                                                                    ,status(Doc), Now);
                                             CallId -> {'unchanged', Doc};
                                             _ -> {'error', 'leg_conflict'}
                                         end;
                                     Error -> Error
                                 end
                         end)
    end;
bind_leg(_, _, _, _, _, _) -> {'error', 'invalid_leg'}.

%% READY's originate handles are committed before acknowledging execute. This
%% closes the crash window where only an ephemeral worker knew how to cancel
%% a pending outbound request. Handles cannot be rebound within an attempt.
-spec bind_originate(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> doc_result().
bind_originate(AccountId, QueueId, Id, Token, UUID, OriginateQueue, OriginalMsgId) ->
    bind_private_values(AccountId, QueueId, Id, Token
                        ,[{<<"pvt_originate_uuid">>, UUID}, {<<"pvt_originate_queue">>, OriginateQueue}
                         ,{<<"pvt_originate_msg_id">>, OriginalMsgId}]
                        ,'undefined').

-spec bind_control(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> doc_result().
bind_control(AccountId, QueueId, Id, Token, CallerId, ControlQueue) ->
    case valid_text(CallerId, 512) of
        'true' -> bind_private_values(AccountId, QueueId, Id, Token
                                      ,[{<<"pvt_caller_control_queue">>, ControlQueue}], CallerId);
        'false' -> {'error', 'invalid_leg'}
    end.

%% Persist only the identities of native agent workers before sending wins.
%% Recovery may query these workers, but these values are not call authority.
-spec bind_selection(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:objects()) -> doc_result().
bind_selection(AccountId, QueueId, Id, Token, Winners) ->
    Valid = is_list(Winners) andalso Winners =/= [] andalso length(Winners) =< 32
        andalso lists:all(fun(Win) -> kz_json:is_json_object(Win)
                                      andalso valid_text(kz_json:get_value(<<"Agent-ID">>, Win), 128)
                                      andalso valid_text(kz_json:get_value(<<"Process-ID">>, Win), 512) end, Winners),
    case Valid andalso valid_text(Token, 128) of
        'false' -> {'error', 'invalid_selection'};
        'true' ->
            Safe = [kz_json:from_list([{Key, kz_json:get_value(Key, Win)}
                                      || Key <- [<<"Agent-ID">>, <<"Process-ID">>]]) || Win <- Winners],
            update(AccountId, QueueId, Id, fun(Doc, Now) ->
                case owns_lease(Doc, Token, Now) of
                    'ok' ->
                        case status(Doc) =:= <<"connecting">> of
                            'true' -> changed(kz_json:set_value(<<"pvt_selected_agents">>, Safe, Doc), status(Doc), Now);
                            'false' -> {'error', 'invalid_state'}
                        end;
                    Error -> Error
                end
            end)
    end.

bind_private_values(AccountId, QueueId, Id, Token, Values, CallerId) ->
    case valid_text(Token, 128) andalso lists:all(fun({_, Value}) -> valid_text(Value, 512) end, Values) of
        'false' -> {'error', 'invalid_leg'};
        'true' -> update(AccountId, QueueId, Id,
                         fun(Doc, Now) ->
                             case owns_lease(Doc, Token, Now) of
                                 'ok' ->
                                     SameCaller = CallerId =:= 'undefined'
                                         orelse CallerId =:= kz_json:get_value(<<"pvt_caller_call_id">>, Doc),
                                     Unchanged = lists:all(fun({Key, Value}) -> kz_json:get_value(Key, Doc) =:= Value end, Values),
                                     Empty = lists:all(fun({Key, _}) -> kz_json:get_value(Key, Doc) =:= 'undefined' end, Values),
                                     case {SameCaller, Unchanged, Empty} of
                                         {'true', 'true', _} -> {'unchanged', Doc};
                                         {'true', _, 'true'} -> changed(kz_json:set_values(Values, Doc), status(Doc), Now);
                                         _ -> {'error', 'leg_conflict'}
                                     end;
                                 Error -> Error
                             end
                         end)
    end.

%% Advance only through the explicit state machine. The coordinator supplies
%% actual returned-leg confirmation events, not agent-side answer events.
%% Data contains only allowlisted call IDs/cause codes, never dialstrings/Call JSON.
-spec advance(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), atom(), kz_json:object()) -> doc_result().
advance(AccountId, QueueId, Id, Token, Action, Data) ->
    case kz_json:is_json_object(Data) andalso valid_text(Token, 128) of
        'false' -> {'error', 'invalid_transition'};
        'true' -> update(AccountId, QueueId, Id,
                         fun(Doc, Now) ->
                                 case transition_ownership(Doc, Token, Action, Data, Now) of
                                     'ok' -> transition(Doc, Action, Data, Now);
                                     Error -> Error
                                 end
                         end)
    end.

%% Cleanup is permitted after cancellation/lease expiry only for the exact
%% persisted attempt and after its coordinator observed definitive originate
%% settlement AND all participating channels down. Timeouts/absence alone are
%% not that evidence. No HTTP adapter can invoke this operational action.
transition_ownership(Doc, Token, 'attempt_settled', Data, _Now) ->
    case lists:member(status(Doc), ?ACTIVE ++ [<<"cancelling">>])
        andalso Token =:= kz_json:get_ne_binary_value([<<"pvt_lease">>, <<"token">>], Doc)
        andalso valid_text(kz_json:get_value(<<"pvt_caller_call_id">>, Doc), 512)
        andalso kz_json:get_value(<<"caller_call_id">>, Data) =:= kz_json:get_value(<<"pvt_caller_call_id">>, Doc)
        andalso kz_json:get_value(<<"agent_call_id">>, Data) =:= kz_json:get_value(<<"pvt_agent_call_id">>, Doc)
        andalso kz_json:get_value(<<"originate_settled">>, Data) =:= 'true'
        andalso kz_json:get_value(<<"channels_down">>, Data) =:= 'true' of
        'true' -> 'ok';
        'false' -> {'error', 'reconciliation_required'}
    end;
transition_ownership(Doc, Token, _, _, Now) -> owns_lease(Doc, Token, Now).

transition(Doc, 'attempt_settled', Data, Now) ->
    case status(Doc) of
        <<"cancelling">> ->
            changed(kz_json:delete_key(<<"pvt_lease">>, Doc), <<"cancelled">>, Now);
        _ -> transition(Doc, 'attempt_ended', Data, Now)
    end;

transition(Doc, 'caller_answered', Data, Now) ->
    CallerId = kz_json:get_value(<<"caller_call_id">>, Data),
    case status(Doc) =:= <<"dialing">> andalso valid_text(CallerId, 512)
        andalso CallerId =:= kz_json:get_value(<<"pvt_caller_call_id">>, Doc) of
        'true' -> changed(Doc, <<"confirming">>, Now);
        'false' -> {'error', 'invalid_transition'}
    end;
transition(Doc, 'caller_confirmed', Data, Now) ->
    CallerId = kz_json:get_value(<<"caller_call_id">>, Data),
    case status(Doc) =:= <<"confirming">> andalso valid_text(CallerId, 512)
        andalso CallerId =:= kz_json:get_value(<<"pvt_caller_call_id">>, Doc) of
        'true' -> changed(Doc, <<"connecting">>, Now);
        'false' -> {'error', 'invalid_transition'}
    end;
transition(Doc, 'bridged', Data, Now) ->
    CallerId = kz_json:get_value(<<"caller_call_id">>, Data),
    AgentId = kz_json:get_value(<<"agent_call_id">>, Data),
    case status(Doc) =:= <<"connecting">> andalso valid_text(AgentId, 512)
        andalso CallerId =:= kz_json:get_value(<<"pvt_caller_call_id">>, Doc)
        andalso AgentId =:= kz_json:get_value(<<"pvt_agent_call_id">>, Doc) of
        'true' ->
            changed(kz_json:delete_key(<<"pvt_lease">>
                                      ,kz_json:set_value(<<"pvt_agent_call_id">>, AgentId, Doc))
                   ,<<"completed">>, Now);
        'false' -> {'error', 'invalid_transition'}
    end;
transition(Doc, 'attempt_ended', Data, Now) ->
    Cause = kz_json:get_value(<<"cause">>, Data),
    %% Only a coordinator that has observed BOTH legs down can call this action.
    %% A timeout/lease expiry alone must never schedule another outbound attempt.
    case lists:member(status(Doc), ?ACTIVE) andalso valid_cause(Cause) of
        'false' -> {'error', 'invalid_transition'};
        'true' ->
            RetryAt = Now + kz_json:get_integer_value(<<"retry_delay">>, Doc),
            NextState = case {RetryAt >= expires_at(Doc)
                             ,attempts(Doc) >= kz_json:get_integer_value(<<"max_attempts">>, Doc)} of
                            {'true', _} -> <<"expired">>;
                            {_, 'true'} -> <<"failed">>;
                            _ -> <<"retry_wait">>
                        end,
            Next = kz_json:set_values([{<<"last_cause">>, Cause}, {<<"next_attempt_at">>, RetryAt}]
                                     ,kz_json:delete_keys([<<"pvt_lease">>, <<"pvt_caller_call_id">>
                                                          ,<<"pvt_agent_call_id">>, <<"pvt_originate_uuid">>
                                                          ,<<"pvt_originate_queue">>, <<"pvt_caller_control_queue">>
                                                          ,<<"pvt_selected_agents">>, <<"pvt_originate_msg_id">>], Doc)),
            changed(Next, NextState, Now)
    end;
transition(_, _, _, _) -> {'error', 'invalid_transition'}.

-spec renew(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), pos_integer()) -> doc_result().
renew(AccountId, QueueId, Id, Token, Seconds) ->
    case bounded(Seconds, 5, 300) andalso valid_text(Token, 128) of
        'false' -> {'error', 'invalid_lease'};
        'true' -> update(AccountId, QueueId, Id,
                         fun(Doc, Now) ->
                                 case owns_lease(Doc, Token, Now) of
                                     'ok' ->
                                         Next = kz_json:set_value([<<"pvt_lease">>, <<"until">>]
                                                                  ,min(Now + Seconds, expires_at(Doc)), Doc),
                                         changed(Next, status(Doc), Now);
                                     Error -> Error
                                 end
                         end)
    end.

%% Adopt the SAME confirmed attempt after a demonstrably dead local queue
%% worker. This never changes its caller UUID/attempt count or permits dial.
%% Remote/unknown ownership is deliberately not inferred from lease timeout.
-spec adopt(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), pos_integer()) -> doc_result().
adopt(AccountId, QueueId, Id, Token, Seconds) ->
    case valid_text(Token, 128) andalso bounded(Seconds, 5, 300) of
        'false' -> {'error', 'invalid_lease'};
        'true' -> update(AccountId, QueueId, Id, fun(Doc, Now) ->
            CurrentOwner = kz_json:get_ne_binary_value([<<"pvt_lease">>, <<"owner">>], Doc),
            OwnId = iolist_to_binary([atom_to_binary(node(), utf8), <<":">>, pid_to_list(self())]),
            case status(Doc) =:= <<"connecting">> andalso not expired(Doc, Now)
                andalso Token =:= kz_json:get_ne_binary_value([<<"pvt_lease">>, <<"token">>], Doc)
                andalso (CurrentOwner =:= OwnId orelse dead_local_owner(CurrentOwner)) of
                'false' -> {'error', 'reconciliation_required'};
                'true' ->
                    Lease = kz_json:from_list([{<<"owner">>, OwnId}, {<<"token">>, kz_binary:rand_hex(24)}
                                               ,{<<"until">>, min(Now + Seconds, expires_at(Doc))}]),
                    changed(kz_json:set_value(<<"pvt_lease">>, Lease, clear_reconciliation(Doc)), status(Doc), Now)
            end
        end)
    end.

dead_local_owner(Owner) when is_binary(Owner) ->
    Prefix = <<(atom_to_binary(node(), utf8))/binary, ":">>, Size = byte_size(Prefix),
    case Owner of
        <<Prefix:Size/binary, PidText/binary>> ->
            try list_to_pid(binary_to_list(PidText)) of
                Pid -> not erlang:is_process_alive(Pid)
            catch _:_ -> 'false' end;
        _ -> 'false'
    end;
dead_local_owner(_) -> 'false'.

-spec mark_reconciliation(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> doc_result().
mark_reconciliation(AccountId, QueueId, Id, Token, Reason) ->
    case valid_text(Token, 128) andalso lists:member(Reason, [<<"engine_restart">>, <<"owner_lost">>
                                                           ,<<"channel_snapshot_incomplete">>, <<"originate_pending">>
                                                           ,<<"cleanup_pending">>, <<"bridge_proof_pending">>]) of
        'false' -> {'error', 'invalid_reconciliation_reason'};
        'true' -> update(AccountId, QueueId, Id, fun(Doc, Now) ->
            case lists:member(status(Doc), ?ACTIVE ++ [<<"cancelling">>])
                andalso kz_json:get_value([<<"pvt_lease">>, <<"token">>], Doc) =:= Token of
                'false' -> {'error', 'stale_lease'};
                'true' ->
                    case kz_json:is_true(<<"reconciliation_required">>, Doc, 'false')
                        andalso kz_json:get_value(<<"reconciliation_reason">>, Doc) =:= Reason of
                        'true' -> {'unchanged', Doc};
                        'false' -> changed(kz_json:set_values([{<<"reconciliation_required">>, 'true'}
                                                               ,{<<"reconciliation_reason">>, Reason}], Doc), status(Doc), Now)
                    end
            end
        end)
    end.

-spec cancel(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> doc_result().
cancel(AccountId, QueueId, Id) ->
    update(AccountId, QueueId, Id,
           fun(Doc, Now) ->
                   State = status(Doc),
                   case {lists:member(State, [<<"cancelled">>, <<"cancelling">>])
                        ,lists:member(State, ?TERMINAL), lists:member(State, ?ACTIVE)} of
                       {'true', _, _} -> {'unchanged', Doc};
                       {_, 'true', _} -> {'error', 'already_finished'};
                       {_, _, 'true'} ->
                           %% Preserve lease/channel IDs for the cleanup worker.
                           changed(Doc, <<"cancelling">>, Now);
                       _ -> changed(Doc, <<"cancelled">>, Now)
                   end
           end).

-spec expire(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> doc_result().
expire(AccountId, QueueId, Id) ->
    update(AccountId, QueueId, Id,
           fun(Doc, Now) ->
                   case {status(Doc), expired(Doc, Now)} of
                       {<<"expired">>, _} -> {'unchanged', Doc};
                       {_, 'false'} -> {'error', 'not_expired'};
                       {State, 'true'} ->
                           case lists:member(State, [<<"registering">>, <<"queued">>, <<"retry_wait">>]) of
                               'true' -> changed(Doc, <<"expired">>, Now);
                               'false' -> {'error', 'reconciliation_required'}
                           end
                   end
           end).

%% Public projection is explicit so future private operational fields cannot
%% accidentally leak through a new list/detail API or Monster UI.
-spec public(kz_json:object()) -> kz_json:object().
public(Doc) ->
    Keys = ?IDENTITY_KEYS ++ [<<"status">>, <<"attempts">>, <<"next_attempt_at">>
                             ,<<"expires_at">>, <<"last_cause">>, <<"reconciliation_required">>, <<"reconciliation_reason">>],
    kz_json:from_list([{<<"id">>, kz_doc:id(Doc)}
                      | [{Key, Value} || Key <- Keys,
                                         (Value = kz_json:get_value(Key, Doc)) =/= 'undefined']]).

update(AccountId, QueueId, Id, Fun) ->
    case get(AccountId, QueueId, Id) of
        {'ok', Doc} ->
            case Fun(Doc, kz_time:now_s()) of
                {'unchanged', Same} -> {'ok', Same};
                {'changed', Next} ->
                    %% No automatic conflict retry: the caller must re-evaluate
                    %% its event/state against the winning revision first.
                    kz_datamgr:save_doc(kzs_util:format_account_db(AccountId), Next);
                Error -> Error
            end;
        Error -> Error
    end.

changed(Doc, State, Now) ->
    Next = case lists:member(State, ?TERMINAL ++ [<<"queued">>, <<"retry_wait">>]) of
        'true' -> clear_reconciliation(Doc);
        'false' -> Doc
    end,
    {'changed', kz_json:set_values([{<<"status">>, State}, {<<"pvt_modified">>, Now}], Next)}.

clear_reconciliation(Doc) -> kz_json:delete_keys([<<"reconciliation_required">>, <<"reconciliation_reason">>], Doc).

owns_lease(Doc, Token, Now) ->
    case {lists:member(status(Doc), ?ACTIVE)
         ,Token =:= kz_json:get_ne_binary_value([<<"pvt_lease">>, <<"token">>], Doc)
         ,lease_until(Doc) > Now, expired(Doc, Now)} of
        {'false', _, _, _} -> {'error', 'invalid_state'};
        {_, 'false', _, _} -> {'error', 'stale_lease'};
        {_, _, 'false', _} -> {'error', 'reconciliation_required'};
        {_, _, _, 'true'} -> {'error', 'expired'};
        _ -> 'ok'
    end.

status(Doc) -> kz_json:get_ne_binary_value(<<"status">>, Doc).
attempts(Doc) -> kz_json:get_integer_value(<<"attempts">>, Doc, 0).
lease_until(Doc) -> kz_json:get_integer_value([<<"pvt_lease">>, <<"until">>], Doc, 0).
expires_at(Doc) -> kz_json:get_integer_value(<<"expires_at">>, Doc, 0).
expired(Doc, Now) -> expires_at(Doc) =< Now.

owns_doc(AccountId, QueueId, Doc) ->
    kz_json:is_json_object(Doc) andalso kz_doc:type(Doc) =:= ?TYPE
        andalso kz_doc:account_id(Doc) =:= AccountId
        andalso kz_json:get_value(<<"queue_id">>, Doc) =:= QueueId
        andalso not kz_doc:is_soft_deleted(Doc).

callback_id(QueueId, CallId) ->
    Digest = kz_term:to_hex_binary(crypto:hash('sha256', term_to_binary({QueueId, CallId}))),
    <<"acdc-callback-", Digest/binary>>.

registration_values(QueueId, CallId, R) ->
    kz_json:from_list([{<<"queue_id">>, QueueId}, {<<"original_call_id">>, CallId}
                      ,{<<"number">>, kz_json:get_value(<<"number">>, R)}
                      ,{<<"enqueued_at">>, kz_json:get_value(<<"enqueued_at">>, R)}
                      ,{<<"enqueue_sequence">>, kz_json:get_value(<<"enqueue_sequence">>, R)}
                      ,{<<"priority">>, kz_json:get_value(<<"priority">>, R, 0)}
                      ,{<<"language">>, kz_json:get_value(<<"language">>, R, <<"en-us">>)}
                      ,{<<"max_attempts">>, kz_json:get_value(<<"max_attempts">>, R, 3)}
                      ,{<<"retry_delay">>, kz_json:get_value(<<"retry_delay">>, R, 60)}
                      ,{<<"ttl">>, kz_json:get_value(<<"ttl">>, R, 3600)}]).

valid_registration(R) ->
    matches(kz_json:get_value(<<"number">>, R), <<"^\\+?[0-9]{1,15}$">>)
        andalso bounded(kz_json:get_value(<<"enqueued_at">>, R), 1, kz_time:now_s())
        andalso bounded(kz_json:get_value(<<"enqueue_sequence">>, R), 0, 16#1fffffffffffff)
        andalso bounded(kz_json:get_value(<<"priority">>, R), 0, 255)
        andalso matches(kz_json:get_value(<<"language">>, R), <<"^[a-z]{2,3}(-[a-z0-9]{2,8}){0,3}$">>)
        andalso bounded(kz_json:get_value(<<"max_attempts">>, R), 1, 10)
        andalso bounded(kz_json:get_value(<<"retry_delay">>, R), 15, 3600)
        andalso bounded(kz_json:get_value(<<"ttl">>, R), 60, 86400).

same_registration(Left, Right) ->
    lists:all(fun(Key) -> kz_json:get_value(Key, Left) =:= kz_json:get_value(Key, Right) end
              ,?IDENTITY_KEYS ++ ?AUTHORITY_KEYS).

%% These are bounded identifiers, not proof of permission. The policy adapter
%% must freshly verify account/endpoint ownership and restrictions before
%% registration and every originate; storing a snapshot cannot grant access.
valid_authority(Authority) ->
    kz_json:is_json_object(Authority)
        andalso matches(kz_json:get_value(<<"id">>, Authority), <<"^[A-Za-z0-9_-]{1,128}$">>)
        andalso lists:member(kz_json:get_value(<<"type">>, Authority), [<<"device">>, <<"user">>])
        andalso matches(kz_json:get_value(<<"account_realm">>, Authority)
                        ,<<"^[A-Za-z0-9][A-Za-z0-9.-]{0,251}[A-Za-z0-9]$">>).

valid_scope(AccountId, QueueId) ->
    matches(AccountId, <<"^[0-9a-f]{32}$">>)
        andalso matches(QueueId, <<"^[A-Za-z0-9_-]{1,128}$">>).
valid_id(Id) -> matches(Id, <<"^acdc-callback-[0-9a-f]{64}$">>).
valid_text(Value, Max) when is_binary(Value), byte_size(Value) > 0, byte_size(Value) =< Max ->
    re:run(Value, <<"[\\x00-\\x1f\\x7f]">>, [{'capture', 'none'}]) =:= 'nomatch';
valid_text(_, _) -> 'false'.
matches(Value, Regex) when is_binary(Value), byte_size(Value) =< 512 ->
    valid_text(Value, 512) andalso re:run(Value, Regex, [{'capture', 'none'}]) =:= 'match';
matches(_, _) -> 'false'.
bounded(Value, Min, Max) -> is_integer(Value) andalso Value >= Min andalso Value =< Max.
valid_cursor(_, 'undefined') -> 'true';
valid_cursor(QueueId, [QueueId, EnqueuedAt, Sequence, Id]) ->
    bounded(EnqueuedAt, 1, 16#1fffffffffffff) andalso bounded(Sequence, 0, 16#1fffffffffffff)
        andalso valid_id(Id);
valid_cursor(_, _) -> 'false'.
valid_cause(Cause) ->
    lists:member(Cause, [<<"busy">>, <<"no_answer">>, <<"rejected">>, <<"confirmation_timeout">>
                        ,<<"wrong_digit">>, <<"caller_hangup">>, <<"agent_unavailable">>
                        ,<<"routing_failed">>, <<"media_failed">>]).
