%%%-----------------------------------------------------------------------------
%%% SPDX-License-Identifier: MPL-2.0
%%% @copyright (C) 2026 Talkchief
%%% @doc Bounded proof that a selected ACDC agent process answered a callback.
%%%
%%% This module only publishes the existing read-only agent sync request.  It
%%% never sends an agent command or a call/bridge command.
%%% @end
%%%-----------------------------------------------------------------------------
-module(acdc_callback_agent_probe).

-export([probe/4]).

-ifdef(TEST).
-export([probe_for_test/5
        ,response_matches/6
        ]).
-endif.

-include("acdc.hrl").

-define(MAX_WINNERS, 32).
-define(GLOBAL_TIMEOUT, 5000).
-define(CALL_TIMEOUT, 4500).

-type probe_result() :: {'ok', kz_json:object()} | {'error', 'unknown'}.

-spec probe(kz_term:ne_binary(), kz_term:ne_binary(), kz_json:objects(),
            kz_term:ne_binary()) -> probe_result().
probe(AccountId, PhysicalCallerId, SelectedWins, ExpectedAgentLeg) ->
    probe_with_timeout(AccountId, PhysicalCallerId, SelectedWins, ExpectedAgentLeg, ?GLOBAL_TIMEOUT).

-ifdef(TEST).
-spec probe_for_test(kz_term:ne_binary(), kz_term:ne_binary(), kz_json:objects(),
                     kz_term:ne_binary(), pos_integer()) ->
          probe_result().
probe_for_test(AccountId, PhysicalCallerId, SelectedWins, ExpectedAgentLeg, Timeout) ->
    probe_with_timeout(AccountId, PhysicalCallerId, SelectedWins, ExpectedAgentLeg, Timeout).
-endif.

probe_with_timeout(AccountId, PhysicalCallerId, SelectedWins, ExpectedAgentLeg, Timeout)
  when is_binary(AccountId), byte_size(AccountId) > 0,
       is_binary(PhysicalCallerId), byte_size(PhysicalCallerId) > 0,
       is_binary(ExpectedAgentLeg), byte_size(ExpectedAgentLeg) > 0,
       is_list(SelectedWins), SelectedWins =/= [], length(SelectedWins) =< ?MAX_WINNERS,
       is_integer(Timeout), Timeout > 0, Timeout =< ?GLOBAL_TIMEOUT ->
    case normalize_winners(SelectedWins) of
        {'error', _} -> {'error', 'unknown'};
        Winners -> run_probes(AccountId, PhysicalCallerId, ExpectedAgentLeg, Winners, Timeout)
    end;
probe_with_timeout(_, _, _, _, _) -> {'error', 'unknown'}.

normalize_winners(Wins) -> normalize_winners(Wins, #{}, []).

normalize_winners([], _, Acc) -> lists:reverse(Acc);
normalize_winners([Win | Wins], Seen, Acc) ->
    AgentId = kz_json:get_ne_binary_value(<<"Agent-ID">>, Win),
    ProcessId = kz_json:get_ne_binary_value(<<"Process-ID">>, Win),
    case is_ne_binary(AgentId) andalso is_ne_binary(ProcessId) of
        'false' -> {'error', 'invalid_winner'};
        'true' ->
            Key = {AgentId, ProcessId},
            case maps:is_key(Key, Seen) of
                'true' -> normalize_winners(Wins, Seen, Acc);
                'false' -> normalize_winners(Wins, Seen#{Key => 'true'}, [Key | Acc])
            end
    end.

run_probes(AccountId, PhysicalCallerId, ExpectedAgentLeg, Winners, Timeout) ->
    Parent = self(), ProbeRef = make_ref(),
    CallTimeout = erlang:max(1, erlang:min(?CALL_TIMEOUT, Timeout - erlang:min(100, Timeout - 1))),
    Monitors = [spawn_monitor(
                  fun() ->
                      Result = probe_winner(AccountId, PhysicalCallerId, ExpectedAgentLeg,
                                            AgentId, ProcessId, CallTimeout),
                      Parent ! {ProbeRef, self(), Result}
                  end) || {AgentId, ProcessId} <- Winners],
    Deadline = erlang:monotonic_time('millisecond') + Timeout,
    await_result(ProbeRef, Monitors, Deadline).

await_result(ProbeRef, Monitors, Deadline) ->
    Remaining = Deadline - erlang:monotonic_time('millisecond'),
    case Remaining =< 0 orelse Monitors =:= [] of
        'true' -> stop_probes(Monitors), {'error', 'unknown'};
        'false' ->
            receive
                {ProbeRef, _Pid, {'ok', Response}} ->
                    stop_probes(Monitors),
                    flush_probe_messages(ProbeRef),
                    {'ok', Response};
                {ProbeRef, Pid, _} ->
                    await_result(ProbeRef, remove_probe(Pid, Monitors), Deadline);
                {'DOWN', Monitor, 'process', _Pid, _Reason} ->
                    await_result(ProbeRef, lists:keydelete(Monitor, 2, Monitors), Deadline)
            after Remaining ->
                stop_probes(Monitors),
                flush_probe_messages(ProbeRef),
                {'error', 'unknown'}
            end
    end.

probe_winner(AccountId, PhysicalCallerId, ExpectedAgentLeg, AgentId, ProcessId, Timeout) ->
    RequestId = kz_binary:rand_hex(16),
    ProbeProcess = kz_binary:rand_hex(16),
    Request = [{<<"Account-ID">>, AccountId}, {<<"Agent-ID">>, AgentId}
              ,{<<"Process-ID">>, ProbeProcess}, {<<"Msg-ID">>, RequestId}
               | kz_api:default_headers(?APP_NAME, ?APP_VERSION)],
    Validator = fun(Response) ->
                        response_matches(Response, AccountId, PhysicalCallerId, ExpectedAgentLeg,
                                         {AgentId, ProcessId}, RequestId)
                end,
    case kz_amqp_worker:call(Request, fun kapi_acdc_agent:publish_sync_req/1, Validator, Timeout) of
        {'ok', Response} -> {'ok', Response};
        _ -> {'error', 'unknown'}
    end.

-spec response_matches(kz_json:object(), kz_term:ne_binary(), kz_term:ne_binary(),
                       kz_term:ne_binary(), {kz_term:ne_binary(), kz_term:ne_binary()},
                       kz_term:ne_binary()) -> boolean().
response_matches(Response, AccountId, PhysicalCallerId, ExpectedAgentLeg,
                 {AgentId, ProcessId}, RequestId) ->
    kapi_acdc_agent:sync_resp_v(Response)
        andalso kz_json:get_value(<<"Account-ID">>, Response) =:= AccountId
        andalso kz_json:get_value(<<"Agent-ID">>, Response) =:= AgentId
        andalso kz_json:get_value(<<"Process-ID">>, Response) =:= ProcessId
        andalso kz_json:get_value(<<"Status">>, Response) =:= <<"answered">>
        andalso kz_json:get_value(<<"Call-ID">>, Response) =:= PhysicalCallerId
        andalso kz_json:get_value(<<"Agent-Call-ID">>, Response) =:= ExpectedAgentLeg
        andalso kz_api:msg_id(Response) =:= RequestId.

remove_probe(Pid, Monitors) ->
    case lists:keytake(Pid, 1, Monitors) of
        {'value', {Pid, Monitor}, Rest} -> erlang:demonitor(Monitor, ['flush']), Rest;
        'false' -> Monitors
    end.

stop_probes(Monitors) ->
    lists:foreach(
      fun({Pid, Monitor}) ->
          erlang:demonitor(Monitor, ['flush']),
          exit(Pid, 'kill')
      end, Monitors).

flush_probe_messages(ProbeRef) ->
    receive {ProbeRef, _, _} -> flush_probe_messages(ProbeRef)
    after 0 -> 'ok'
    end.

is_ne_binary(Value) -> is_binary(Value) andalso byte_size(Value) > 0.
