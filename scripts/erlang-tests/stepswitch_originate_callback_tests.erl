%%% SPDX-License-Identifier: MPL-2.0
-module(stepswitch_originate_callback_tests).
-include_lib("eunit/include/eunit.hrl").

b_leg_events_are_forwarded_unchanged_test() ->
    Events = [<<"CHANNEL_ANSWER">>, <<"DTMF">>, <<"CHANNEL_DESTROY">>
             ,<<"CHANNEL_EXECUTE_COMPLETE">>, <<"CHANNEL_EXECUTE_ERROR">>
             ,<<"CHANNEL_BRIDGE">>],
    Request = kz_json:from_list([{<<"B-Leg-Events">>, Events}]),
    ?assertEqual(Events, stepswitch_originate:originate_b_leg_events(Request)),
    ?assertEqual([], stepswitch_originate:originate_b_leg_events(kz_json:new())).

ready_is_nonterminal_but_final_results_stop_test() ->
    ?assertEqual(retain, stepswitch_originate:originate_result_action(
                           [{<<"Response-Message">>, <<"READY">>}])),
    ?assertEqual(stop, stepswitch_originate:originate_result_action(
                         [{<<"Response-Message">>, <<"SUCCESS">>}])),
    ?assertEqual(stop, stepswitch_originate:originate_result_action(
                         [{<<"Response-Message">>, <<"NO_ROUTE_DESTINATION">>}])),
    ?assertEqual(stop, stepswitch_originate:originate_result_action([])).
