%%% SPDX-License-Identifier: MPL-2.0
%%% Pure production context/filter checks; no bindings server or live socket.
-module(blackhole_binding_results_tests).
-include_lib("eunit/include/eunit.hrl").

context_results_test_() ->
    Good = bh_context:set_auth_account_id(bh_context:new(), <<"fixture-account">>),
    Bad = bh_context:add_error(Good, <<"fixture denied">>),
    [{"only successful contexts belong to succeeded",
      fun() -> ?assertEqual([Good], blackhole_bindings:succeeded([Good, Bad])) end},
     {"only denied contexts belong to failed",
      fun() -> ?assertEqual([Bad], blackhole_bindings:failed([Good, Bad])) end},
     {"denial classification is independent of callback order",
      fun() -> ?assertEqual([Bad], blackhole_bindings:failed([Bad, Good])),
               ?assertEqual([Good], blackhole_bindings:succeeded([Bad, Good])) end},
     {"single-context wrappers retain their result classification",
      fun() -> ?assertEqual([[Bad]], blackhole_bindings:failed([[Good], [Bad]])),
               ?assertEqual([[Good]], blackhole_bindings:succeeded([[Good], [Bad]])) end},
     {"single direct context and empty-result controls",
      fun() -> ?assertEqual([Good], blackhole_bindings:succeeded(Good)),
               ?assertEqual([Bad], blackhole_bindings:failed(Bad)),
               ?assertEqual([], blackhole_bindings:failed([])),
               ?assertEqual([], blackhole_bindings:succeeded([])) end},
     {"existing boolean and event-map classifications remain intact",
      fun() -> ?assertEqual([true], blackhole_bindings:succeeded([false, true])),
               ?assertEqual([false], blackhole_bindings:failed([true, false])),
               Map = #{requested => <<"call.CHANNEL_ANSWER.*">>},
               ?assertEqual([Map], blackhole_bindings:succeeded([Map])),
               ?assertEqual([], blackhole_bindings:failed([Map])) end}].
