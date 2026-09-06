%%% SPDX-License-Identifier: MPL-2.0
-module(acdc_agent_recovery_tests).

-export([enter_fsm/1]).

-include_lib("eunit/include/eunit.hrl").

-define(ACCOUNT, <<"11111111111111111111111111111111">>).
-define(AGENT, <<"agent">>).
-define(MEMBER, <<"member-call">>).
-define(CONNECT, <<"queue-offer-1">>).

agent_recovery_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(Modules) ->
     [{atom_to_list(element(2, erlang:fun_info(F, name))),
       {timeout, 30, fun() -> [meck:reset(M) || M <- Modules], F() end}} || F <- [fun failure_recovers_without_its_broadcast/0
                               ,fun publish_failure_still_recovers/0
                               ,fun timeout_correlates_and_cleans_up/0
                               ,fun stale_and_duplicate_failures_are_ignored/0
                               ,fun old_channel_events_cannot_claim_new_offer/0
                               ,fun monitoring_failure_is_offer_scoped/0
                               ,fun success_does_not_wait_for_its_broadcast/0
                               ,fun pending_pause_and_logout_limit_survive/0
                               ,fun losing_race_preserves_failure_count/0
                               ,fun missed_outbound_hangups_recover/0
                               ,fun incomplete_status_never_frees_agent/0
                               ,fun missed_queue_hangups_preserve_wrapup/0
                               ,fun active_agent_leg_prevents_recovery/0
                               ,fun ringing_member_hangup_recovers/0
                               ,fun stale_probe_cannot_affect_new_call/0
                               ,fun blocked_probe_does_not_block_fsm/0
                               ,fun running_fsm_handles_hangup_during_probe/0
                               ,fun status_checks_are_read_only_and_correlated/0
                               ,fun repeated_calls_remain_available/0
                               ,fun upgrade_preserves_existing_state/0
                               ,fun upgrade_rejects_active_legacy_state/0
                               ,fun upgrade_rejects_unknown_layouts/0
                               ,fun upgrade_current_state_is_idempotent/0
                               ]] end}.

setup() ->
    Modules = [acdc_agent_listener, acdc_agent_stats, acdc_stats, acdc_util, kz_amqp_worker, kapps_config],
    [meck:new(M, [non_strict, no_link]) || M <- Modules],
    meck:new(kapi_acdc_agent, [passthrough, no_link]),
    meck:expect(kapps_config, get_ne_binary, fun(_, _, Default) -> Default end),
    meck:expect(kapps_config, get_binary, fun(_, _, Default) -> Default end),
    [meck:expect(acdc_agent_listener, F, fun(_, _) -> ok end)
     || F <- [channel_hungup, presence_update, send_availability_update,
              member_connect_resp, member_connect_retry, member_connect_accepted,
              monitor_connect_accepted, unbind_from_events, originate_execute, outbound_call]],
    meck:expect(acdc_agent_listener, bridge_to_member, fun(_, _, _, _, _, _) -> ok end),
    meck:expect(acdc_agent_listener, monitor_call, fun(_, _, _, _) -> ok end),
    [meck:expect(acdc_agent_stats, F, fun(_, _) -> ok end)
     || F <- [agent_ready, agent_logged_out]],
    [meck:expect(acdc_agent_stats, F, fun(_, _, _) -> ok end)
     || F <- [agent_paused, agent_wrapup, agent_outbound]],
    [meck:expect(acdc_agent_stats, F, fun(_, _, _, _, _, _) -> ok end)
     || F <- [agent_connected, agent_connecting]],
    meck:expect(acdc_stats, call_missed, fun(_, _, _, _, _) -> ok end),
    meck:expect(acdc_stats, call_processed, fun(_, _, _, _, _) -> ok end),
    meck:expect(acdc_util, caller_id, fun(_) -> {<<"1000">>, <<"Caller">>} end),
    meck:expect(acdc_util, bind_to_call_events, fun(_, _) -> ok end),
    meck:expect(acdc_util, unbind_from_call_events, fun(_, _) -> ok end),
    meck:expect(acdc_util, get_endpoints, fun(_, _) -> [j([{<<"_id">>, <<"endpoint">>}])] end),
    %% Deliberately do not loop these events back to the originating FSM.
    meck:expect(kapi_acdc_agent, publish_shared_originate_failure, fun(_) -> ok end),
    meck:expect(kapi_acdc_agent, publish_shared_call_id, fun(_) -> ok end),
    Modules ++ [kapi_acdc_agent].

cleanup(Modules) ->
    [meck:unload(M) || M <- Modules].

state(Extra) ->
    acdc_agent_fsm:strategy_test_state(
      Extra ++ [{account_id, ?ACCOUNT}, {agent_id, ?AGENT}, {agent_listener, self()}
               ,{statem_call_id, <<"recovery-test">>}, {member_call_id, ?MEMBER}
               ,{member_connect_id, ?CONNECT}, {member_call_queue_id, <<"queue">>}
               ,{member_call, kapps_call:new()}, {member_call_start, kz_time:start_time()}
               ,{connect_failures, 0}, {max_connect_failures, 3}]).

field(Name, State) -> acdc_agent_fsm:strategy_test_field(Name, State).
j(Props) -> kz_json:from_list(Props).
failure() ->
    j([{<<"Msg-ID">>, ?CONNECT}, {<<"Error-Message">>, <<"NO_USER_RESPONSE">>}
      ,{<<"Request">>, j([{<<"Existing-Call-ID">>, ?MEMBER}, {<<"Msg-ID">>, ?CONNECT}])}]).
shared() ->
    j([{<<"Account-ID">>, ?ACCOUNT}, {<<"Agent-ID">>, ?AGENT}
      ,{<<"Member-Call-ID">>, ?MEMBER}, {<<"Connect-ID">>, ?CONNECT}]).

assert_accepts_next_offer(State) ->
    Offer = j([{<<"Call-ID">>, <<"next-member">>}]),
    ?assertEqual({next_state, ready, State},
                 acdc_agent_fsm:ready(cast, {member_connect_req, Offer}, State)),
    ?assert(meck:called(acdc_agent_listener, member_connect_resp, [self(), Offer])).

failure_recovers_without_its_broadcast() ->
    {next_state, ready, Ready} = acdc_agent_fsm:ringing(cast, {originate_failed, failure()}, state([])),
    ?assertEqual(1, field(connect_failures, Ready)),
    ?assertEqual(undefined, field(member_call_id, Ready)),
    ?assert(meck:called(acdc_agent_listener, member_connect_retry, [self(), ?MEMBER])),
    ?assertEqual(1, meck:num_calls(acdc_stats, call_missed, '_')),
    assert_accepts_next_offer(Ready),
    Props = meck:capture(first, kapi_acdc_agent, publish_shared_originate_failure, '_', 1),
    {ok, Encoded} = kz_api:prepare_api_payload(Props,
                        [{<<"Event-Category">>, <<"agent">>}, {<<"Event-Name">>, <<"shared_failure">>}],
                        fun kapi_acdc_agent:shared_originate_failure/1),
    Decoded = kz_json:decode(Encoded),
    ?assertEqual(?MEMBER, kz_json:get_value(<<"Member-Call-ID">>, Decoded)),
    ?assertEqual(?CONNECT, kz_json:get_value(<<"Connect-ID">>, Decoded)).

publish_failure_still_recovers() ->
    meck:expect(kapi_acdc_agent, publish_shared_originate_failure, fun(_) -> erlang:error(disconnected) end),
    {next_state, ready, Ready} = acdc_agent_fsm:ringing(cast, {originate_failed, failure()}, state([])),
    assert_accepts_next_offer(Ready),
    meck:expect(kapi_acdc_agent, publish_shared_originate_failure, fun(_) -> ok end).

timeout_correlates_and_cleans_up() ->
    State = state([]),
    Bad = j([{<<"Call-ID">>, <<"old-call">>}]),
    ?assertEqual({next_state, ringing, State}, acdc_agent_fsm:ringing(cast, {agent_timeout, Bad}, State)),
    ?assertEqual(0, meck:num_calls(acdc_agent_listener, member_connect_retry, '_')),
    Timeout = j([{<<"Call-ID">>, ?MEMBER}, {<<"Connect-ID">>, ?CONNECT}]),
    Stale = kz_json:set_value(<<"Connect-ID">>, <<"previous-offer">>, Timeout),
    ?assertEqual({next_state, ringing, State}, acdc_agent_fsm:ringing(cast, {agent_timeout, Stale}, State)),
    {next_state, ready, Ready} = acdc_agent_fsm:ringing(cast, {agent_timeout, Timeout}, State),
    ?assertEqual(1, field(connect_failures, Ready)),
    ?assert(meck:called(acdc_agent_listener, member_connect_retry, [self(), ?MEMBER])),
    assert_accepts_next_offer(Ready).

stale_and_duplicate_failures_are_ignored() ->
    State = state([]),
    Bad = kz_json:set_value(<<"Msg-ID">>, <<"previous-attempt-for-same-member">>, failure()),
    ?assertEqual({next_state, ringing, State}, acdc_agent_fsm:ringing(cast, {originate_failed, Bad}, State)),
    %% Primary FSMs complete locally; even a matching delayed echo is ignored.
    ?assertEqual({next_state, ringing, State}, acdc_agent_fsm:ringing(cast, {shared_failure, shared()}, State)),
    {next_state, ready, Ready} = acdc_agent_fsm:ringing(cast, {originate_failed, failure()}, State),
    ?assertEqual({next_state, ready, Ready}, acdc_agent_fsm:ready(cast, {originate_failed, failure()}, Ready)),
    ?assertEqual(1, field(connect_failures, Ready)),
    ?assertEqual(1, meck:num_calls(acdc_stats, call_missed, '_')).

old_channel_events_cannot_claim_new_offer() ->
    State = state([]),
    Event = j([{<<"Call-ID">>, <<"new-agent-leg">>}, {<<"Other-Leg-Call-ID">>, ?MEMBER}
               ,{<<"Custom-Channel-Vars">>, j([{<<"Account-ID">>, ?ACCOUNT}, {<<"Agent-ID">>, ?AGENT}
                                             ,{<<"Member-Call-ID">>, ?MEMBER}, {<<"Request-ID">>, ?CONNECT}])}]),
    Old = kz_json:set_value([<<"Custom-Channel-Vars">>, <<"Request-ID">>], <<"old-offer">>, Event),
    [begin
        ?assertEqual({next_state, ringing, State}, acdc_agent_fsm:ringing(cast, {Type, Old}, State))
     end || Type <- [channel_answered, channel_bridge_event]],
    {next_state, ringing, WithLeg} = acdc_agent_fsm:ringing(cast, {channel_answered, Event}, State),
    ?assertEqual(<<"new-agent-leg">>, field(agent_call_id, WithLeg)),
    ?assertMatch({next_state, answered, _}, acdc_agent_fsm:ringing(cast, {channel_bridge_event, Event}, State)).

monitoring_failure_is_offer_scoped() ->
    State = state([{monitoring, true}]),
    [begin
         Bad = kz_json:set_value(Key, <<"other">>, shared()),
         ?assertEqual({next_state, ringing, State}, acdc_agent_fsm:ringing(cast, {shared_failure, Bad}, State))
     end || Key <- [<<"Account-ID">>, <<"Agent-ID">>, <<"Member-Call-ID">>, <<"Connect-ID">>]],
    ?assertEqual({next_state, ringing, State}, acdc_agent_fsm:ringing(cast, {shared_failure, j([])}, State)),
    {next_state, ready, Ready} = acdc_agent_fsm:ringing(cast, {shared_failure, shared()}, State),
    ?assertEqual(1, field(connect_failures, Ready)),
    ?assert(meck:called(acdc_agent_listener, channel_hungup, [self(), ?MEMBER])).

success_does_not_wait_for_its_broadcast() ->
    State = state([]),
    Response = j([{<<"Msg-ID">>, ?CONNECT}, {<<"Call-ID">>, <<"agent-leg">>}]),
    Stale = kz_json:set_value(<<"Msg-ID">>, <<"old-attempt">>, Response),
    ?assertEqual({next_state, ringing, State}, acdc_agent_fsm:ringing(cast, {originate_resp, Stale}, State)),
    ?assertEqual({next_state, ringing, State}, acdc_agent_fsm:ringing(cast, {originate_ready, Stale}, State)),
    acdc_agent_fsm:originate_resp(self(), Response),
    receive {'$gen_cast', Event} ->
        {next_state, answered, Answered} = acdc_agent_fsm:ringing(cast, Event, State),
        ?assertEqual(<<"agent-leg">>, field(agent_call_id, Answered))
    after 1000 -> error(no_originate_event)
    end,
    Props = meck:capture(first, kapi_acdc_agent, publish_shared_call_id, '_', 1),
    {ok, Encoded} = kz_api:prepare_api_payload(Props,
                        [{<<"Event-Category">>, <<"agent">>}, {<<"Event-Name">>, <<"shared_call_id">>}],
                        fun kapi_acdc_agent:shared_call_id/1),
    Shared = kz_json:decode(Encoded),
    ?assertEqual(?CONNECT, kz_json:get_value(<<"Connect-ID">>, Shared)),
    Monitor = state([{monitoring, true}]),
    Bad = kz_json:set_value(<<"Connect-ID">>, <<"old">>, Shared),
    ?assertEqual({next_state, ringing, Monitor}, acdc_agent_fsm:ringing(cast, {shared_call_id, Bad}, Monitor)),
    ?assertMatch({next_state, answered, _}, acdc_agent_fsm:ringing(cast, {shared_call_id, Shared}, Monitor)).

pending_pause_and_logout_limit_survive() ->
    Pause = state([{agent_state_updates, [{pause, infinity}]}]),
    {next_state, paused, Paused} = acdc_agent_fsm:ringing(cast, {originate_failed, failure()}, Pause),
    ?assertEqual(infinity, field(pause_ref, Paused)),
    Limit = state([{connect_failures, 2}]),
    {next_state, paused, LoggedOut} = acdc_agent_fsm:ringing(cast, {originate_failed, failure()}, Limit),
    ?assertEqual(3, field(connect_failures, LoggedOut)),
    ?assertEqual(1, meck:num_calls(acdc_agent_stats, agent_logged_out, '_')),
    receive {'$gen_cast', {agent_logout}} -> ok after 1000 -> error(no_logout) end.

losing_race_preserves_failure_count() ->
    State = state([{connect_failures, 2}]),
    Failure = kz_json:set_value(<<"Error-Message">>, <<"LOSE_RACE">>, failure()),
    {next_state, ready, Ready} = acdc_agent_fsm:ringing(cast, {originate_failed, Failure}, State),
    ?assertEqual(2, field(connect_failures, Ready)),
    assert_accepts_next_offer(Ready),
    Monitor = state([{connect_failures, 2}, {monitoring, true}]),
    Message = kz_json:set_value(<<"Blame">>, <<"member">>, shared()),
    {next_state, ready, MonitorReady} = acdc_agent_fsm:ringing(cast, {shared_failure, Message}, Monitor),
    ?assertEqual(2, field(connect_failures, MonitorReady)),
    ?assertEqual(0, meck:num_calls(acdc_agent_stats, agent_logged_out, '_')),
    Satisfied = j([{<<"Call">>, j([{<<"Call-ID">>, ?MEMBER}])}, {<<"Connect-ID">>, ?CONNECT}]),
    Stale = kz_json:set_value(<<"Connect-ID">>, <<"previous-offer">>, Satisfied),
    ?assertEqual({next_state, ringing, State}, acdc_agent_fsm:ringing(cast, {member_connect_satisfied, Stale}, State)),
    {next_state, ready, LoserReady} = acdc_agent_fsm:ringing(cast, {member_connect_satisfied, Satisfied}, State),
    ?assertEqual(2, field(connect_failures, LoserReady)).

probe(StateName, State) ->
    {Pending, Message} = begin_probe(StateName, State),
    acdc_agent_fsm:StateName(info, Message, Pending).

begin_probe(StateName, State) ->
    Ref = field(call_check_ref, State),
    {next_state, StateName, Pending} = acdc_agent_fsm:StateName(info, {timeout, Ref, check_agent_calls}, State),
    erlang:cancel_timer(field(call_check_ref, Pending)),
    receive {agent_calls_checked, _, _}=Message -> {Pending, Message}
    after 2000 -> error(no_call_check_result)
    end.

probe_state(Extra) -> state([{call_check_ref, make_ref()} | Extra]).

statuses(Statuses) ->
    meck:expect(kz_amqp_worker, call_collect,
                fun(Request, _Publish, {ecallmgr, true}, 5000) ->
                    Id = props:get_value(<<"Call-ID">>, Request),
                    Msg = props:get_value(<<"Msg-ID">>, Request),
                    Status = proplists:get_value(Id, Statuses, <<"terminated">>),
                    {ok, [status_response(Id, Msg, Status)]}
                end).

status_response(Id, Msg, Status) ->
    j([{<<"Event-Category">>, <<"channel">>}, {<<"Event-Name">>, <<"channel_status_resp">>}
      ,{<<"App-Name">>, <<"ecallmgr">>}, {<<"App-Version">>, <<"test">>}
      ,{<<"Node">>, <<"ecallmgr@test">>}, {<<"Call-ID">>, Id}, {<<"Msg-ID">>, Msg}
      ,{<<"Status">>, Status}
      ,{<<"Channel-Record">>, j([{<<"Call-ID">>, Id}, {<<"Account-ID">>, ?ACCOUNT}
                                ,{<<"Media-Node">>, <<"freeswitch@test">>}
                                ,{<<"Custom-Channel-Vars">>, j([{<<"Account-ID">>, ?ACCOUNT}])}])}]).

missed_outbound_hangups_recover() ->
    State = probe_state([{outbound_call_ids, [<<"ended">>, <<"active">>]}]),
    statuses([{<<"active">>, <<"active">>}]),
    {next_state, outbound, Busy} = probe(outbound, State),
    ?assertEqual([<<"active">>], field(outbound_call_ids, Busy)),
    ?assertEqual(0, meck:num_calls(acdc_agent_listener, send_availability_update, '_')),
    statuses([]),
    {next_state, ready, Ready} = probe(outbound, Busy),
    ?assertEqual([], field(outbound_call_ids, Ready)),
    assert_accepts_next_offer(Ready),
    {next_state, paused, Paused} = probe(outbound, probe_state([{outbound_call_ids, [<<"ended">>]}, {pause_ref, infinity}])),
    ?assertEqual(infinity, field(pause_ref, Paused)),
    ?assertMatch({stop, normal, _}, probe(outbound, probe_state([{outbound_call_ids, [<<"ended">>]}
                                                             ,{agent_state_updates, [{agent_logout}]}]))).

incomplete_status_never_frees_agent() ->
    State = probe_state([{outbound_call_ids, [<<"direct">>]}]),
    [begin
         meck:expect(kz_amqp_worker, call_collect, fun(_, _, _, _) -> Result end),
         {next_state, outbound, Busy} = probe(outbound, State),
         ?assertEqual([<<"direct">>], field(outbound_call_ids, Busy))
     end || Result <- [{ok, []}, {error, timeout}, {timeout, []}]],
    statuses([{<<"direct">>, <<"tmpdown">>}]),
    ?assertMatch({next_state, outbound, _}, probe(outbound, State)),
    ?assertEqual(0, meck:num_calls(acdc_agent_listener, send_availability_update, '_')).

missed_queue_hangups_preserve_wrapup() ->
    statuses([]),
    State = probe_state([{agent_call_id, <<"agent-leg">>}, {wrapup_timeout, 20}]),
    {next_state, wrapup, Wrapup} = probe(answered, State),
    Ref = field(wrapup_ref, Wrapup),
    ?assert(erlang:read_timer(Ref) > 0),
    ?assertEqual(0, meck:num_calls(acdc_agent_listener, member_connect_resp, '_')),
    ?assertEqual(1, meck:num_calls(acdc_stats, call_processed, '_')),
    erlang:cancel_timer(Ref),
    {next_state, ready, Ready} = acdc_agent_fsm:wrapup(info, {timeout, Ref, wrapup_finished}, Wrapup),
    assert_accepts_next_offer(Ready).

active_agent_leg_prevents_recovery() ->
    statuses([{<<"agent-leg">>, <<"active">>}]),
    State = probe_state([{agent_call_id, <<"agent-leg">>}]),
    ?assertMatch({next_state, answered, _}, probe(answered, State)),
    ?assertEqual(0, meck:num_calls(acdc_stats, call_processed, '_')).

ringing_member_hangup_recovers() ->
    statuses([]),
    {next_state, ready, Ready} = probe(ringing, probe_state([])),
    ?assertEqual(0, field(connect_failures, Ready)),
    assert_accepts_next_offer(Ready).

stale_probe_cannot_affect_new_call() ->
    statuses([]),
    {Pending, Message} = begin_probe(outbound, probe_state([{outbound_call_ids, [<<"old-direct">>]}])),
    {next_state, outbound, NewCall} = acdc_agent_fsm:outbound(info, {call_from, <<"new-direct">>}, Pending),
    {next_state, outbound, StillBusy} = acdc_agent_fsm:outbound(info, Message, NewCall),
    ?assertEqual([<<"new-direct">>, <<"old-direct">>], field(outbound_call_ids, StillBusy)),
    ?assertEqual(0, meck:num_calls(acdc_agent_listener, channel_hungup, '_')),
    %% A duplicate result cannot perform cleanup twice.
    ?assertEqual({next_state, outbound, StillBusy}, acdc_agent_fsm:outbound(info, Message, StillBusy)).

blocked_probe_does_not_block_fsm() ->
    Test = self(),
    meck:expect(kz_amqp_worker, call_collect,
                fun(_, _, _, _) -> Test ! {query_started, self()}, receive release -> {error, timeout} end end),
    State = probe_state([{outbound_call_ids, [<<"direct">>]}]),
    Ref = field(call_check_ref, State),
    {next_state, outbound, Busy} = acdc_agent_fsm:outbound(info, {timeout, Ref, check_agent_calls}, State),
    erlang:cancel_timer(field(call_check_ref, Busy)),
    Worker = receive {query_started, Pid} -> Pid after 1000 -> error(no_query) end,
    {CheckId, Worker, Monitor, _} = field(call_check, Busy),
    ?assertMatch({next_state, outbound, _, _}, acdc_agent_fsm:outbound({call, {self(), make_ref()}}, status, Busy)),
    %% The next tick bounds a stuck worker; callbacks and hangups remain usable.
    statuses([]),
    {next_state, outbound, Next} = acdc_agent_fsm:outbound(info, {timeout, field(call_check_ref, Busy), check_agent_calls}, Busy),
    erlang:cancel_timer(field(call_check_ref, Next)),
    ?assertEqual({next_state, outbound, Next}, acdc_agent_fsm:outbound(info, {agent_calls_checked, CheckId, {ok, #{}}}, Next)),
    erlang:demonitor(Monitor, [flush]),
    receive {agent_calls_checked, _, _}=Message ->
        ?assertMatch({next_state, ready, _}, acdc_agent_fsm:outbound(info, Message, Next))
    after 2000 -> error(no_replacement_query)
    end.

running_fsm_handles_hangup_during_probe() ->
    Test = self(),
    meck:expect(kz_amqp_worker, call_collect,
                fun(_, _, _, _) -> Test ! {query_started, self()}, receive release -> {error, timeout} end end),
    Ref = make_ref(),
    State = state([{call_check_ref, Ref}, {outbound_call_ids, [<<"direct">>]}]),
    {ok, FSM} = proc_lib:start(?MODULE, enter_fsm, [State]),
    try
        FSM ! {timeout, Ref, check_agent_calls},
        Worker = receive {query_started, Pid} -> Pid after 1000 -> error(no_query) end,
        Monitor = erlang:monitor(process, Worker),
        ?assertEqual(<<"outbound">>, props:get_value(state, gen_statem:call(FSM, status, 1000))),
        FSM ! {call_down, <<"direct">>, <<"NORMAL_CLEARING">>},
        ?assertEqual(<<"ready">>, props:get_value(state, gen_statem:call(FSM, status, 1000))),
        Offer = j([{<<"Call-ID">>, <<"next-call">>}]),
        acdc_agent_fsm:member_connect_req(FSM, Offer),
        _ = gen_statem:call(FSM, status, 1000),
        ?assert(meck:called(acdc_agent_listener, member_connect_resp, [Test, Offer])),
        gen_statem:stop(FSM, shutdown, 1000),
        receive {'DOWN', Monitor, process, Worker, _} -> ok
        after 1000 -> error(orphaned_probe)
        end
    after
        case is_process_alive(FSM) of true -> gen_statem:stop(FSM, shutdown, 1000); false -> ok end
    end.

enter_fsm(State) ->
    proc_lib:init_ack({ok, self()}),
    gen_statem:enter_loop(acdc_agent_fsm, [], outbound, State).

status_checks_are_read_only_and_correlated() ->
    meck:expect(kz_amqp_worker, call_collect,
                fun(Request, _, _, _) ->
                    ?assertEqual(false, props:get_value(<<"Active-Only">>, Request)),
                    ?assertEqual(true, props:get_value(<<"Channel-Record">>, Request)),
                    Id = props:get_value(<<"Call-ID">>, Request),
                    {ok, [status_response(Id, <<"stale-response-id">>, <<"terminated">>)]}
                end),
    ?assertMatch({unknown, _}, acdc_callback_recovery_io:observe_channels(?ACCOUNT, [<<"direct">>])),
    ?assertEqual({error, invalid_input}, acdc_callback_recovery_io:observe_channels(?ACCOUNT, [])),
    ?assertEqual({error, invalid_input}, acdc_callback_recovery_io:observe_channels(undefined, [<<"direct">>])).

repeated_calls_remain_available() ->
    statuses([]),
    Initial = probe_state([{member_call_id, undefined}, {member_connect_id, undefined}
                          ,{member_call, undefined}, {max_connect_failures, infinity}
                          ,{endpoints, [j([{<<"_id">>, <<"endpoint">>}])]}]),
    lists:foldl(fun(N, Ready) ->
        Connect = integer_to_binary(N),
        Win = j([{<<"Msg-ID">>, Connect}, {<<"Queue-ID">>, <<"queue">>}
                ,{<<"Call">>, j([{<<"Call-ID">>, ?MEMBER}, {<<"Account-ID">>, ?ACCOUNT}])}]),
        {next_state, ringing, Ringing} = acdc_agent_fsm:ready(cast, {member_connect_win, Win, same_node}, Ready),
        ?assertEqual(Connect, field(member_connect_id, Ringing)),
        Failure = kz_json:set_value(<<"Msg-ID">>, Connect, failure()),
        {next_state, ready, Again} = acdc_agent_fsm:ringing(cast, {originate_failed, Failure}, Ringing),
        assert_accepts_next_offer(Again),
        Again
    end, Initial, lists:seq(1, 20)),
    ?assertEqual(20, meck:num_calls(acdc_agent_listener, bridge_to_member, '_')),
    ?assertEqual(0, meck:num_calls(acdc_agent_stats, agent_logged_out, '_')).

upgrade_preserves_existing_state() ->
    lists:foreach(fun(Name) ->
        Current = drained_upgrade_state([{pause_ref, infinity}
                                         ,{agent_state_updates, [{pause, 60}]}
                                         ,{endpoints, [j([{<<"_id">>, <<"endpoint">>}])]}]),
        Old = legacy_state(Current),
        {ok, Name, Upgraded} = acdc_agent_fsm:code_change(old, Name, Old, []),
        try
            ?assertEqual(Old, legacy_state(Upgraded)),
            ?assertEqual(undefined, field(member_connect_id, Upgraded)),
            ?assertEqual(undefined, field(call_check, Upgraded)),
            ?assert(is_reference(field(call_check_ref, Upgraded))),
            ?assert(is_integer(erlang:read_timer(field(call_check_ref, Upgraded))))
        after erlang:cancel_timer(field(call_check_ref, Upgraded))
        end
    end, [ready, paused]).

drained_upgrade_state(Extra) ->
    acdc_agent_fsm:strategy_test_state(Extra ++ [{account_id, ?ACCOUNT}, {agent_id, ?AGENT}]).

legacy_state(Current) ->
    list_to_tuple(lists:sublist(tuple_to_list(Current), tuple_size(Current) - 3)).

upgrade_rejects_active_legacy_state() ->
    Old = legacy_state(drained_upgrade_state([])),
    lists:foreach(fun(Name) ->
        ?assertEqual({error, agent_upgrade_requires_drain},
                     acdc_agent_fsm:code_change(old, Name, Old, []))
    end, [wait, sync, ringing, answered, wrapup, outbound]),
    lists:foreach(fun(Name) ->
        lists:foreach(fun(Extra) ->
            Busy = legacy_state(drained_upgrade_state([Extra])),
            ?assertEqual({error, agent_upgrade_requires_drain},
                         acdc_agent_fsm:code_change(old, Name, Busy, []))
        end, [{member_call, kapps_call:new()}, {member_call_id, ?MEMBER}
              ,{member_call_queue_id, <<"queue">>}, {member_call_start, 1}
              ,{agent_call_id, <<"agent-leg">>}, {outbound_call_ids, [<<"direct">>]}
              ,{outbound_call_ids, undefined}, {monitoring, true}])
    end, [ready, paused]).

upgrade_rejects_unknown_layouts() ->
    Current = drained_upgrade_state([]),
    Old = legacy_state(Current),
    lists:foreach(fun(Bad) ->
        ?assertEqual({error, unsupported_agent_state_layout},
                     acdc_agent_fsm:code_change(old, ready, Bad, []))
    end, [undefined, #{}, {}, {state}, setelement(1, Old, foreign)
          ,setelement(1, Current, foreign), erlang:append_element(Old, undefined)
          ,erlang:append_element(Current, undefined)]),
    ?assertEqual({error, unsupported_agent_state},
                 acdc_agent_fsm:code_change(old, unknown, Current, [])).

upgrade_current_state_is_idempotent() ->
    Ref = erlang:start_timer(30000, self(), upgrade_test),
    try
        Current = state([{call_check_ref, Ref}, {call_check, {make_ref(), self(), make_ref(), {snapshot}}}]),
        lists:foreach(fun(Name) ->
            ?assertEqual({ok, Name, Current}, acdc_agent_fsm:code_change(old, Name, Current, []))
        end, [wait, sync, ready, ringing, answered, wrapup, paused, outbound]),
        ?assert(is_integer(erlang:read_timer(Ref)))
    after erlang:cancel_timer(Ref)
    end.

listener_preserves_offer_correlation_test_() ->
    {timeout, 30, fun() ->
        Modules = [kapi_resource, acdc_util],
        [meck:new(M, [non_strict, no_link]) || M <- Modules],
        try
            meck:expect(kapi_resource, publish_originate_req, fun(_) -> ok end),
            meck:expect(acdc_util, caller_id, fun(_) -> {<<"1000">>, <<"Caller">>} end),
            meck:expect(acdc_util, bind_to_call_events, fun(_) -> ok end),
            Call = kapps_call:exec([{fun kapps_call:set_call_id/2, ?MEMBER}
                                   ,{fun kapps_call:set_account_id/2, ?ACCOUNT}], kapps_call:new()),
            [_] = acdc_agent_listener:maybe_connect_to_agent(<<"listener-q">>, [j([])], Call,
                                                              15, ?AGENT, undefined, ?CONNECT),
            Request = meck:capture(first, kapi_resource, publish_originate_req, '_', 1),
            ?assertEqual(?CONNECT, props:get_value(<<"Msg-ID">>, Request)),
            ?assertEqual(?MEMBER, props:get_value(<<"Existing-Call-ID">>, Request)),
            CCVs = props:get_value(<<"Custom-Channel-Vars">>, Request),
            ?assertEqual(?CONNECT, kz_json:get_value(<<"Request-ID">>, CCVs)),
            ?assertEqual(?MEMBER, kz_json:get_value(<<"Member-Call-ID">>, CCVs)),
            ?assertEqual(?AGENT, kz_json:get_value(<<"Agent-ID">>, CCVs))
        after [meck:unload(M) || M <- Modules]
        end
    end}.

queue_notifications_preserve_offer_correlation_test_() ->
    {timeout, 30, fun() ->
        meck:new(kz_amqp_util, [non_strict, no_link]),
        meck:new(kapps_config, [non_strict, no_link]),
        try
            meck:expect(kapps_config, get_ne_binary, fun(_, _, Default) -> Default end),
            meck:expect(kapps_config, get_binary, fun(_, _, Default) -> Default end),
            meck:expect(kz_amqp_util, kapps_publish, fun(_, _, _) -> ok end),
            meck:expect(kz_amqp_util, targeted_publish, fun(_, _, _) -> ok end),
            Call = kapps_call:set_call_id(?MEMBER, kapps_call:new()),
            State = acdc_queue_listener:callback_test_state(
                      [{call, Call}, {queue_id, <<"queue">>}, {my_id, <<"queue-process">>}
                       ,{my_q, <<"queue-mailbox">>}]),
            Response = j([{<<"Msg-ID">>, ?CONNECT}, {<<"Agent-ID">>, ?AGENT}
                         ,{<<"Agent-Process-IDs">>, [<<"agent-process">>]}
                         ,{<<"Server-ID">>, <<"agent-mailbox">>}]),
            {noreply, _, hibernate} = acdc_queue_listener:handle_cast({member_connect_win, Response, []}, State),
            Win = kz_json:decode(meck:capture(first, kz_amqp_util, kapps_publish, '_', 2)),
            ?assertEqual(?CONNECT, kz_api:msg_id(Win)),
            ?assert(kapi_acdc_agent:member_connect_win_v(Win)),
            {noreply, _, hibernate} = acdc_queue_listener:handle_cast({timeout_agent, Response}, State),
            Timeout = kz_json:decode(meck:capture(first, kz_amqp_util, targeted_publish, '_', 2)),
            ?assert(kapi_acdc_queue:agent_timeout_v(Timeout)),
            ?assertEqual(?CONNECT, kz_json:get_value(<<"Connect-ID">>, Timeout)),
            ?assertEqual(?MEMBER, kz_api:call_id(Timeout)),
            {noreply, _, hibernate} = acdc_queue_listener:handle_cast({member_connect_satisfied, Response, []}, State),
            Satisfied = kz_json:decode(meck:capture(last, kz_amqp_util, targeted_publish, '_', 2)),
            ?assert(kapi_acdc_queue:member_connect_satisfied_v(Satisfied)),
            ?assertEqual(?CONNECT, kz_json:get_value(<<"Connect-ID">>, Satisfied))
        after meck:unload(kz_amqp_util), meck:unload(kapps_config)
        end
    end}.
