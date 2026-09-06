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
