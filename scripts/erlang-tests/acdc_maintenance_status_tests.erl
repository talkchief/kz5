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
