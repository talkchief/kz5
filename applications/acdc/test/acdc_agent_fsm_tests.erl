%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2012-2020, 2600Hz
%%% @doc
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(acdc_agent_fsm_tests).

-include_lib("eunit/include/eunit.hrl").

changed_endpoints_test_() ->
    X = kz_json:from_list([{<<"_id">>, <<"x">>}]),
    Y = kz_json:from_list([{<<"_id">>, <<"y">>}]),

    [?_assertEqual({[], []}, acdc_agent_fsm:changed_endpoints([], []))
    ,?_assertEqual({[], []}, acdc_agent_fsm:changed_endpoints([X], [X]))

    ,?_assertEqual({[], []}, acdc_agent_fsm:changed_endpoints([X, Y], [X, Y]))
    ,?_assertEqual({[], []}, acdc_agent_fsm:changed_endpoints([X, Y], [Y, X]))

    ,?_assertEqual({[X], []}, acdc_agent_fsm:changed_endpoints([], [X]))
    ,?_assertEqual({[], [X]}, acdc_agent_fsm:changed_endpoints([X], []))

    ,?_assertEqual({[X, Y], []}, acdc_agent_fsm:changed_endpoints([], [X, Y]))
    ,?_assertEqual({[], [X, Y]}, acdc_agent_fsm:changed_endpoints([X, Y], []))

    ,?_assertEqual({[Y], []}, acdc_agent_fsm:changed_endpoints([X], [X, Y]))
    ,?_assertEqual({[], [X]}, acdc_agent_fsm:changed_endpoints([X, Y], [Y]))

    ,?_assertEqual({[X], [Y]}, acdc_agent_fsm:changed_endpoints([Y], [X]))
    ].

%% A losing queue offer can complete after this agent switched to a direct
%% call. It must not strand the agent in wrapup without a wrapup timer.
outbound_connect_satisfied_recovery_test_() ->
    [{"direct calls finish and the next queue offer is accepted",
      fun() -> outbound_connect_satisfied_recovery(undefined, [], ready) end}
    ,{"an existing pause survives the late queue notification",
      fun() -> outbound_connect_satisfied_recovery(infinity, [], paused) end}
    ,{"a pending logout is applied after the direct calls finish",
      fun() -> outbound_connect_satisfied_recovery(undefined, [{agent_logout}], logout) end}
    ].

outbound_connect_satisfied_recovery(PauseRef, Updates, Expected) ->
    Modules = [acdc_agent_listener, acdc_agent_stats],
    [meck:new(M, [non_strict, no_link]) || M <- Modules],
    try
        meck:expect(acdc_agent_listener, channel_hungup, fun(_, _) -> ok end),
        meck:expect(acdc_agent_listener, presence_update, fun(_, _) -> ok end),
        meck:expect(acdc_agent_listener, send_availability_update, fun(_, _) -> ok end),
        meck:expect(acdc_agent_listener, member_connect_resp, fun(_, _) -> ok end),
        meck:expect(acdc_agent_stats, agent_ready, fun(_, _) -> ok end),
        meck:expect(acdc_agent_stats, agent_paused, fun(_, _, _) -> ok end),
        meck:expect(acdc_agent_stats, agent_logged_out, fun(_, _) -> ok end),
        State = acdc_agent_fsm:strategy_test_state(
                  [{account_id, <<"account">>}, {agent_id, <<"agent">>}
                  ,{agent_listener, self()}, {statem_call_id, <<"outbound-regression">>}
                  ,{outbound_call_ids, [<<"direct-1">>, <<"direct-2">>]}
                  ,{connect_failures, 2}, {max_connect_failures, 3}
                  ,{pause_ref, PauseRef}, {agent_state_updates, Updates}
                  ]),
        Satisfied = kz_json:from_list(
                      [{<<"Call">>, kz_json:from_list([{<<"Call-ID">>, <<"old-queue-call">>}])}]),
        ?assertEqual({next_state, outbound, State},
                     acdc_agent_fsm:outbound(cast, {member_connect_satisfied, Satisfied}, State)),
        ?assertEqual({next_state, outbound, State},
                     acdc_agent_fsm:outbound(cast, {member_connect_req, kz_json:new()}, State)),
        {next_state, outbound, OneCallLeft} =
            acdc_agent_fsm:outbound(info, {call_down, <<"direct-1">>, <<"NORMAL_CLEARING">>}, State),
        ?assertEqual([<<"direct-2">>], acdc_agent_fsm:strategy_test_field(outbound_call_ids, OneCallLeft)),
        ?assertEqual(0, meck:num_calls(acdc_agent_listener, send_availability_update, '_')),
        ?assertEqual(0, meck:num_calls(acdc_agent_listener, member_connect_resp, '_')),
        ?assertEqual(0, meck:num_calls(acdc_agent_stats, agent_logged_out, '_')),
        Result = acdc_agent_fsm:outbound(info, {call_down, <<"direct-2">>, <<"NORMAL_CLEARING">>}, OneCallLeft),
        Cleared = case Expected of
                      logout ->
                          {stop, normal, Final} = Result,
                          ?assert(meck:called(acdc_agent_stats, agent_logged_out, [<<"account">>, <<"agent">>])),
                          Final;
                      NextState ->
                          {next_state, NextState, Final} = Result,
                          ?assert(meck:called(acdc_agent_listener, send_availability_update, [self(), NextState])),
                          Offer = kz_json:from_list([{<<"Call-ID">>, <<"next-queue-call">>}]),
                          ?assertEqual({next_state, NextState, Final},
                                       acdc_agent_fsm:NextState(cast, {member_connect_req, Offer}, Final)),
                          ?assertEqual(NextState =:= ready,
                                       meck:called(acdc_agent_listener, member_connect_resp, [self(), Offer])),
                          ?assertEqual(0, meck:num_calls(acdc_agent_stats, agent_logged_out, '_')),
                          Final
                  end,
        ?assertEqual([], acdc_agent_fsm:strategy_test_field(outbound_call_ids, Cleared)),
        ?assertEqual(undefined, acdc_agent_fsm:strategy_test_field(wrapup_ref, Cleared)),
        ?assertEqual(2, acdc_agent_fsm:strategy_test_field(connect_failures, Cleared)),
        ?assert(lists:all(fun meck:validate/1, Modules))
    after
        [meck:unload(M) || M <- Modules]
    end.

%% Automatic-logout threshold. Zero used to compare as already exceeded and
%% logged every agent out on the first queue offer.
connect_failure_limit_test_() ->
    [?_assertEqual(3, acdc_agent_fsm:connect_failure_limit(3, 7))
    ,?_assertEqual(5, acdc_agent_fsm:connect_failure_limit(<<"5">>, 7))
    ,?_assertEqual('infinity', acdc_agent_fsm:connect_failure_limit(0, 7))
    ,?_assertEqual('infinity', acdc_agent_fsm:connect_failure_limit(-1, 7))
    ,?_assertEqual('infinity', acdc_agent_fsm:connect_failure_limit(<<"0">>, 7))
    ,?_assertEqual('infinity', acdc_agent_fsm:connect_failure_limit(<<"infinity">>, 7))
    ,?_assertEqual('infinity', acdc_agent_fsm:connect_failure_limit(<<"disabled">>, 7))
    ,?_assertEqual('infinity', acdc_agent_fsm:connect_failure_limit('infinity', 7))
    ,?_assertEqual(7, acdc_agent_fsm:connect_failure_limit(<<"three">>, 7))
    ,?_assertEqual(7, acdc_agent_fsm:connect_failure_limit(2.5, 7))
    ,?_assertEqual('infinity', acdc_agent_fsm:connect_failure_limit('true', 'infinity'))
    ].

disabled_failure_limit_never_logs_an_agent_out_test() ->
    Modules = [acdc_agent_listener, acdc_agent_stats],
    [meck:new(M, [non_strict, no_link]) || M <- Modules],
    try
        meck:expect(acdc_agent_listener, member_connect_resp, fun(_, _) -> ok end),
        meck:expect(acdc_agent_stats, agent_logged_out, fun(_, _) -> ok end),
        Offer = kz_json:from_list([{<<"Call-ID">>, <<"queue-call">>}]),
        Disabled = acdc_agent_fsm:strategy_test_state(
                     [{account_id, <<"account">>}, {agent_id, <<"agent">>}, {agent_listener, self()}
                     ,{connect_failures, 50}
                     ,{max_connect_failures, acdc_agent_fsm:connect_failure_limit(0, 3)}
                     ]),
        ?assertEqual({next_state, ready, Disabled},
                     acdc_agent_fsm:ready(cast, {member_connect_req, Offer}, Disabled)),
        ?assertEqual(1, meck:num_calls(acdc_agent_listener, member_connect_resp, '_')),
        ?assertEqual(0, meck:num_calls(acdc_agent_stats, agent_logged_out, '_')),
        %% The configured protection itself is unchanged.
        Limited = acdc_agent_fsm:strategy_test_state(
                    [{account_id, <<"account">>}, {agent_id, <<"agent">>}, {agent_listener, self()}
                    ,{connect_failures, 3}, {max_connect_failures, 3}
                    ]),
        ?assertMatch({next_state, paused, _},
                     acdc_agent_fsm:ready(cast, {member_connect_req, Offer}, Limited)),
        ?assert(meck:called(acdc_agent_stats, agent_logged_out, [<<"account">>, <<"agent">>])),
        ?assertEqual(1, meck:num_calls(acdc_agent_listener, member_connect_resp, '_'))
    after
        meck:unload(Modules)
    end.

%% The stored pause is applied only when no live peer says otherwise. Updates are
%% applied oldest first from the reversed queue, so the restored pause goes last
%% in the list and anything received since start still wins.
restored_pause_test_() ->
    Resume = {'resume'},
    [?_assertEqual([], acdc_agent_fsm:restore_pause_updates('undefined', []))
    ,?_assertEqual([{'pause', 240}], acdc_agent_fsm:restore_pause_updates(240, []))
    ,?_assertEqual([Resume, {'pause', 'infinity'}], acdc_agent_fsm:restore_pause_updates('infinity', [Resume]))
     %% A paused peer: the time left found at start, else follow the peer open-ended.
    ,?_assertEqual([{'pause', 240}], acdc_agent_fsm:peer_paused_updates(240, []))
    ,?_assertEqual([{'pause', 'infinity'}], acdc_agent_fsm:peer_paused_updates('undefined', []))
    ].

%% Seconds of pause still owed after a restart.
pause_left_test_() ->
    [?_assertEqual('infinity', acdc_agent_util:pause_left('undefined', 1000, 1100))
    ,?_assertEqual('infinity', acdc_agent_util:pause_left(0, 1000, 1100))
    ,?_assertEqual(200, acdc_agent_util:pause_left(300, 1000, 1100))
    ,?_assertEqual(1, acdc_agent_util:pause_left(300, 1000, 1299))
     %% The break ended while the node was down: nothing to restore.
    ,?_assertEqual('undefined', acdc_agent_util:pause_left(300, 1000, 1300))
    ,?_assertEqual('undefined', acdc_agent_util:pause_left(300, 1000, 5000))
    ,?_assertEqual('undefined', acdc_agent_util:pause_left(300, 'undefined', 1100))
    ].

%% An agent whose processes start while its devices are in calls is busy, not ready.
live_calls_at_start_test_() ->
    Device = fun(User) -> kz_json:from_list([{<<"sip">>, kz_json:from_list([{<<"username">>, User}])}]) end,
    Resp = fun(Ids) -> kz_json:from_list([{<<"Channels">>, [kz_json:from_list([{<<"uuid">>, Id}]) || Id <- Ids]}]) end,
    [?_assertEqual([<<"dev_a">>, <<"dev_b">>], acdc_agent_fsm:device_usernames([Device(<<"dev_b">>), Device(<<"dev_a">>), Device(<<"dev_b">>)]))
    ,?_assertEqual([], acdc_agent_fsm:device_usernames([kz_json:new()]))
    ,?_assertEqual([], acdc_agent_fsm:device_usernames('undefined'))
     %% Two media controllers report the same leg; one reports nothing.
    ,?_assertEqual([<<"leg-1">>, <<"leg-2">>]
                  ,acdc_agent_fsm:live_call_ids([Resp([<<"leg-2">>, <<"leg-1">>]), Resp([<<"leg-1">>]), Resp([]), kz_json:new()]))
    ,?_assertEqual([], acdc_agent_fsm:live_call_ids([]))
    ].

