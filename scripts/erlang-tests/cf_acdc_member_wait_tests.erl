%%% SPDX-License-Identifier: MPL-2.0
-module(cf_acdc_member_wait_tests).
-include_lib("eunit/include/eunit.hrl").

time(Milliseconds) ->
    {start_time, erlang:convert_time_unit(Milliseconds, millisecond, native)}.

subsecond_events_do_not_extend_deadline_test() ->
    ?assertEqual(1000, cf_acdc_member:remaining_wait_ms(1, time(0), time(0))),
    ?assertEqual(750, cf_acdc_member:remaining_wait_ms(1, time(0), time(250))),
    ?assertEqual(500, cf_acdc_member:remaining_wait_ms(1, time(0), time(500))),
    ?assertEqual(250, cf_acdc_member:remaining_wait_ms(1, time(0), time(750))),
    ?assertEqual(0, cf_acdc_member:remaining_wait_ms(1, time(0), time(1000))).

expired_wait_is_immediate_test() ->
    ?assertEqual(0, cf_acdc_member:remaining_wait_ms(1, time(0), time(5000))).

infinite_wait_stays_infinite_test() ->
    ?assertEqual(infinity, cf_acdc_member:remaining_wait_ms(infinity, time(0), time(99999999))).

long_wait_stays_within_otp_timer_range_test() ->
    ?assertEqual(16#ffffffff, cf_acdc_member:remaining_wait_ms(5000000, time(0), time(0))).
