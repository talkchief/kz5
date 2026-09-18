%%% SPDX-License-Identifier: MPL-2.0
-module(acdc_maintenance_status_tests).
-include_lib("eunit/include/eunit.hrl").

doc(Timestamp, Status) ->
    kz_json:from_list([{<<"timestamp">>, Timestamp}, {<<"status">>, Status}]).

nested_history_selects_numeric_newest_test() ->
    Agents = kz_json:from_list([{<<"agent-a">>, kz_json:from_list(
        [{<<"9">>, doc(9, <<"logged_out">>)}, {<<"10">>, doc(10, <<"ready">>)}])}]),
    [Latest] = acdc_maintenance:current_status_rows(Agents),
    ?assertEqual(<<"agent-a">>, kz_json:get_value(<<"agent_id">>, Latest)),
    ?assertEqual(<<"ready">>, kz_json:get_value(<<"status">>, Latest)),
    ?assertEqual(10, kz_json:get_value(<<"timestamp">>, Latest)).

legacy_flat_and_missing_timestamp_test() ->
    Flat = kz_json:from_list([{<<"status">>, <<"ready">>}]),
    [Actual] = acdc_maintenance:current_status_rows(kz_json:from_list([{<<"agent-a">>, Flat}])),
    ?assertEqual(<<"ready">>, kz_json:get_value(<<"status">>, Actual)),
    ?assertEqual(<<"unknown">>, acdc_maintenance:status_timestamp(undefined)),
    ?assertEqual(<<"unknown">>, acdc_maintenance:status_timestamp(-1)),
    ?assertEqual(kz_time:pretty_print_datetime(63955852800),
                 acdc_maintenance:status_timestamp(63955852800)).

malformed_history_is_not_a_status_test() ->
    Bad = kz_json:from_list([{<<"timestamp">>, <<"not-a-time">>}]),
    History = kz_json:from_list([{<<"bad">>, Bad}, {<<"negative">>, doc(-5, <<"ready">>)},
                                {<<"not-an-object">>, <<"bad">>}]),
    ?assertEqual([], acdc_maintenance:current_status_rows(
                      kz_json:from_list([{<<"agent-a">>, History}, {<<"agent-b">>, false}]))).

public_current_statuses_handles_nested_response_test_() ->
    {timeout, 15, fun() ->
        ok = meck:new(acdc_agent_util, [passthrough, no_link]),
        Agents = kz_json:from_list([{<<"agent-a">>, kz_json:from_list(
            [{<<"63955852800">>, doc(63955852800, <<"ready">>)}])}]),
        meck:expect(acdc_agent_util, most_recent_statuses, fun(<<"account">>) -> {ok, Agents} end),
        try ?assertEqual(ok, acdc_maintenance:current_statuses(<<"account">>))
        after meck:unload(acdc_agent_util) end
    end}.

%% Two running agents used to crash the listing: the agent printer handed the
%% rest of the list to the queue printer (private lab, September 18, 2026).
agents_summary_lists_every_agent_test_() ->
    {timeout, 15, fun() ->
        ok = meck:new(acdc_agents_sup, [passthrough, no_link]),
        Running = [{self(), {<<"account">>, <<"agent-a">>, <<"amqp-queue-a">>}},
                   {self(), {<<"account">>, <<"agent-b">>, <<"amqp-queue-b">>}},
                   {self(), {<<"other">>, <<"agent-c">>, <<"amqp-queue-c">>}}],
        meck:expect(acdc_agents_sup, agents_running, fun() -> Running end),
        try
            ?assertEqual(ok, acdc_maintenance:agents_summary()),
            ?assertEqual(ok, acdc_maintenance:agents_summary(<<"account">>))
        after meck:unload(acdc_agents_sup) end
    end}.

%% The console passes the time limit as text. As text the request failed
%% validation and a timed pause silently did nothing.
console_timed_pause_publishes_an_integer_test_() ->
    {timeout, 15, fun() ->
        Self = self(),
        ok = meck:new(kz_amqp_worker, [passthrough, no_link]),
        meck:expect(kz_amqp_worker, cast, fun(Request, _Publisher) -> Self ! {published, Request}, ok end),
        try
            ?assertEqual(ok, acdc_maintenance:agent_pause(<<"account">>, <<"agent-a">>, <<"900">>)),
            Limit = receive {published, Request} -> props:get_value(<<"Time-Limit">>, Request) after 1000 -> missing end,
            ?assertEqual(900, Limit)
        after meck:unload(kz_amqp_worker) end
    end}.
