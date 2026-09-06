%%%-----------------------------------------------------------------------------
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%-----------------------------------------------------------------------------
-module(acdc_queue_member_tests).

-include_lib("eunit/include/eunit.hrl").

-define(LOGICAL_ID, <<"acdc_logical_member_id">>).
-define(ENQUEUED_AT, <<"acdc_enqueued_at">>).
-define(ENQUEUE_SEQUENCE, <<"acdc_enqueue_sequence">>).
-define(PRIORITY, <<"acdc_member_priority">>).
-define(CALLBACK_ID, <<"acdc_callback_id">>).
-define(CALLBACK_ATTEMPT, <<"acdc_callback_attempt">>).
-define(CALLBACK_ATTEMPT_ID, <<"acdc_callback_attempt_id">>).
-define(CALLBACK_LEASE_TOKEN, <<"acdc_callback_lease_token">>).

stamp_overwrites_untrusted_metadata_test() ->
    Seeded = kapps_call:kvs_store_proplist(
               [{?LOGICAL_ID, <<"forged">>}
               ,{?ENQUEUED_AT, 1}
               ,{?ENQUEUE_SEQUENCE, 2}
               ,{?PRIORITY, 255}
               ,{?CALLBACK_ID, <<"forged-callback">>}
               ,{?CALLBACK_ATTEMPT, 9}
               ,{?CALLBACK_ATTEMPT_ID, <<"forged-attempt">>}
               ,{?CALLBACK_LEASE_TOKEN, <<"private">>}
               ], call(<<"original">>)),
    Stamped = acdc_queue_member:stamp(Seeded, 100, 7, 3),
    ?assertEqual(<<"original">>, acdc_queue_member:logical_id(Stamped)),
    ?assertEqual({-3, 100, 7, <<"original">>},
                 acdc_queue_member:member_order_key(Stamped)),
    ?assertEqual('undefined', kapps_call:kvs_fetch(?CALLBACK_ID, Stamped)),
    ?assertEqual('undefined', kapps_call:kvs_fetch(?CALLBACK_ATTEMPT, Stamped)),
    ?assertEqual('undefined', kapps_call:kvs_fetch(?CALLBACK_ATTEMPT_ID, Stamped)),
    ?assertEqual('undefined', kapps_call:kvs_fetch(?CALLBACK_LEASE_TOKEN, Stamped)).

ordering_and_idempotent_ensure_test() ->
    Old = stamped(<<"old">>, 100, 1, 0),
    New = stamped(<<"new">>, 101, 2, 0),
    Priority = stamped(<<"priority">>, 102, 3, 10),
    {'ok', Calls1, 1, 'inserted'} = acdc_queue_member:ensure(Old, []),
    {'ok', Calls2, 2, 'inserted'} = acdc_queue_member:ensure(New, Calls1),
    {'ok', Calls3, 1, 'inserted'} = acdc_queue_member:ensure(Priority, Calls2),
    ?assertEqual(2, acdc_queue_member:position(<<"old">>, Calls3)),
    ?assertEqual(3, acdc_queue_member:position(<<"new">>, Calls3)),
    ?assertEqual(1, acdc_queue_member:position(<<"priority">>, Calls3)),
    ?assertMatch({'ok', _, 2, 'existing'}, acdc_queue_member:ensure(Old, Calls3)).

roundtrip_keeps_recovery_metadata_test() ->
    Original = stamped(<<"roundtrip">>, 123, 44, 5),
    with_config_defaults(fun() ->
        Recovered = kapps_call:from_json(kapps_call:to_json(Original)),
        ?assertEqual(acdc_queue_member:logical_id(Original),
                     acdc_queue_member:logical_id(Recovered)),
        ?assertEqual(acdc_queue_member:member_order_key(Original),
                     acdc_queue_member:member_order_key(Recovered)),
        ?assertEqual({'ok', kz_json:from_list([{<<"enqueued_at">>, 123}
                                             ,{<<"enqueue_sequence">>, 44}
                                             ,{<<"priority">>, 5}
                                             ,{<<"language">>, <<"en-us">>}])},
                     acdc_queue_member:registration_metadata(Recovered))
    end).

replacement_preserves_slot_and_metadata_test() ->
    Original = stamped(<<"original">>, 100, 7, 3),
    Other = stamped(<<"other">>, 101, 8, 3),
    {'ok', Calls1, 1, 'inserted'} = acdc_queue_member:ensure(Original, []),
    {'ok', Calls2, 2, 'inserted'} = acdc_queue_member:ensure(Other, Calls1),
    CallbackId = callback_id(),
    NewPhysical = kapps_call:kvs_store(?CALLBACK_LEASE_TOKEN, <<"private">>,
                                       call(<<"callback-leg-1">>)),
    {'ok', Calls3, 1, 'replaced'} =
        acdc_queue_member:replace(<<"original">>, CallbackId, 1,
                                  <<"callback-leg-1">>, NewPhysical, Calls2),
    {Canonical, 1} = acdc_queue_member:lookup(<<"original">>, Calls3),
    ?assertEqual(<<"callback-leg-1">>, acdc_queue_member:physical_id(Canonical)),
    ?assertEqual(<<"original">>, acdc_queue_member:logical_id(Canonical)),
    ?assertEqual({-3, 100, 7, <<"original">>},
                 acdc_queue_member:member_order_key(Canonical)),
    ?assertEqual(CallbackId, kapps_call:kvs_fetch(?CALLBACK_ID, Canonical)),
    ?assertEqual(1, kapps_call:kvs_fetch(?CALLBACK_ATTEMPT, Canonical)),
    ?assertEqual(<<"callback-leg-1">>,
                 kapps_call:kvs_fetch(?CALLBACK_ATTEMPT_ID, Canonical)),
    ?assertEqual('undefined', kapps_call:kvs_fetch(?CALLBACK_LEASE_TOKEN, Canonical)),
    ?assertMatch({'ok', _, 1, 'duplicate'},
                 acdc_queue_member:replace(<<"original">>, CallbackId, 1,
                                           <<"callback-leg-1">>, NewPhysical, Calls3)).

replacement_rejects_stale_or_conflicting_attempt_test() ->
    Original = stamped(<<"original">>, 100, 7, 3),
    {'ok', Calls1, 1, 'inserted'} = acdc_queue_member:ensure(Original, []),
    CallbackId = callback_id(),
    {'ok', Calls2, 1, 'replaced'} =
        acdc_queue_member:replace(<<"original">>, CallbackId, 2,
                                  <<"callback-leg-2">>, call(<<"callback-leg-2">>), Calls1),
    ?assertEqual({'error', 'stale_attempt'},
                 acdc_queue_member:replace(<<"original">>, CallbackId, 1,
                                           <<"callback-leg-1">>, call(<<"callback-leg-1">>), Calls2)),
    ?assertEqual({'error', 'attempt_conflict'},
                 acdc_queue_member:replace(<<"original">>, CallbackId, 2,
                                           <<"different-leg">>, call(<<"different-leg">>), Calls2)),
    ?assertEqual({'error', 'callback_conflict'},
                 acdc_queue_member:replace(<<"original">>, other_callback_id(), 3,
                                           <<"callback-leg-3">>, call(<<"callback-leg-3">>), Calls2)),
    ?assertEqual({'error', 'invalid_replacement'},
                 acdc_queue_member:replace(<<"original">>, CallbackId, 3,
                                           <<"persisted-id">>, call(<<"different-id">>), Calls2)).

replacement_rejects_physical_identity_collision_test() ->
    One = stamped(<<"one">>, 100, 1, 0),
    Two = stamped(<<"two">>, 101, 2, 0),
    {'ok', Calls1, _, _} = acdc_queue_member:ensure(One, []),
    {'ok', Calls2, _, _} = acdc_queue_member:ensure(Two, Calls1),
    ?assertEqual({'error', 'identity_conflict'},
                 acdc_queue_member:replace(<<"one">>, callback_id(), 1,
                                           <<"two">>, call(<<"two">>), Calls2)).

replace_api_contract_test() ->
    with_config_defaults(fun() ->
        Props = [{<<"Account-ID">>, <<"account">>}
                ,{<<"Queue-ID">>, <<"queue">>}
                ,{<<"Logical-Call-ID">>, <<"original">>}
                ,{<<"Callback-ID">>, callback_id()}
                ,{<<"Attempt">>, 1}
                ,{<<"Attempt-ID">>, <<"callback-leg-1">>}
                ,{<<"Call">>, kapps_call:to_json(call(<<"callback-leg-1">>))}
                ,{<<"Event-Category">>, <<"queue">>}
                ,{<<"Event-Name">>, <<"member_replace">>}
                ,{<<"Msg-ID">>, <<"test-message">>}
                 | kz_api:default_headers(<<"test">>, <<"1">>)],
        ?assert(kapi_acdc_queue:queue_member_replace_v(Props)),
        ?assertNot(kapi_acdc_queue:queue_member_replace_v(
                     props:delete(<<"Logical-Call-ID">>, Props))),
        ?assertNot(kapi_acdc_queue:queue_member_replace_v(
                     props:set_value(<<"Attempt">>, 0, Props))),
        ?assertNot(kapi_acdc_queue:queue_member_replace_v(
                     props:set_value(<<"Attempt-ID">>, <<"different-leg">>, Props))),
        ?assertNot(kapi_acdc_queue:queue_member_replace_v(
                     props:set_value(<<"Callback-ID">>, <<"bad-id">>, Props))),
        ?assertNot(kapi_acdc_queue:queue_member_replace_v(
                     props:set_value(<<"Call">>, <<"not-json">>, Props)))
    end).

trusted_restore_overwrites_untrusted_values_test() ->
    Seeded = kapps_call:kvs_store_proplist(
               [{?LOGICAL_ID, <<"forged-logical">>}
               ,{?ENQUEUED_AT, 999}
               ,{?ENQUEUE_SEQUENCE, 999}
               ,{?PRIORITY, 255}
               ,{?CALLBACK_ID, callback_id()}
               ,{?CALLBACK_ATTEMPT, 9}
               ,{?CALLBACK_ATTEMPT_ID, <<"forged-leg">>}
               ,{?CALLBACK_LEASE_TOKEN, <<"private">>}
               ], call(<<"returned-leg">>)),
    {'ok', Restored} = acdc_queue_member:restore(
                         Seeded, <<"original-call">>, 100, 7, 3),
    ?assertEqual(<<"original-call">>, acdc_queue_member:logical_id(Restored)),
    ?assertEqual(<<"returned-leg">>, acdc_queue_member:physical_id(Restored)),
    ?assertEqual({-3, 100, 7, <<"original-call">>},
                 acdc_queue_member:member_order_key(Restored)),
    ?assertEqual('undefined', kapps_call:kvs_fetch(?CALLBACK_ID, Restored)),
    ?assertEqual('undefined', kapps_call:kvs_fetch(?CALLBACK_ATTEMPT, Restored)),
    ?assertEqual('undefined', kapps_call:kvs_fetch(?CALLBACK_ATTEMPT_ID, Restored)),
    ?assertEqual('undefined', kapps_call:kvs_fetch(?CALLBACK_LEASE_TOKEN, Restored)).

trusted_restore_rejects_missing_or_invalid_metadata_test() ->
    Call = call(<<"returned-leg">>),
    Invalid = [{<<>>, 100, 7, 3}
              ,{<<"original-call">>, 0, 7, 3}
              ,{<<"original-call">>, 100, -1, 3}
              ,{<<"original-call">>, 100, 7, -1}
              ,{<<"original-call">>, 100, 7, 256}],
    lists:foreach(
      fun({LogicalId, EnqueuedAt, Sequence, Priority}) ->
          ?assertEqual({'error', 'invalid_metadata'},
                       acdc_queue_member:restore(
                         Call, LogicalId, EnqueuedAt, Sequence, Priority))
      end, Invalid).

trusted_callback_restore_requires_exact_persisted_leg_test() ->
    CallbackId = callback_id(),
    {'ok', Restored} = acdc_queue_member:restore_callback(
                         call(<<"returned-leg">>), <<"original-call">>, 100, 7, 3,
                         CallbackId, 2, <<"returned-leg">>),
    ?assertEqual(<<"original-call">>, acdc_queue_member:logical_id(Restored)),
    ?assertEqual(CallbackId, kapps_call:kvs_fetch(?CALLBACK_ID, Restored)),
    ?assertEqual(2, kapps_call:kvs_fetch(?CALLBACK_ATTEMPT, Restored)),
    ?assertEqual(<<"returned-leg">>, kapps_call:kvs_fetch(?CALLBACK_ATTEMPT_ID, Restored)),
    ?assertEqual({'error', 'invalid_metadata'},
                 acdc_queue_member:restore_callback(
                   call(<<"foreign-leg">>), <<"original-call">>, 100, 7, 3,
                   CallbackId, 2, <<"returned-leg">>)),
    ?assertEqual({'error', 'invalid_metadata'},
                 acdc_queue_member:restore_callback(
                   call(<<"returned-leg">>), <<"original-call">>, 100, 7, 3,
                   <<"bad-callback">>, 2, <<"returned-leg">>)).

stamped(Id, EnqueuedAt, Sequence, Priority) ->
    acdc_queue_member:stamp(call(Id), EnqueuedAt, Sequence, Priority).

call(Id) ->
    kapps_call:set_language(
      <<"en-us">>,
      kapps_call:set_controller_queue(
        <<"controller">>,
        kapps_call:set_control_queue(
          <<"control">>, kapps_call:set_call_id(Id, kapps_call:new())))).

with_config_defaults(Fun) ->
    meck:new(kapps_config, [passthrough, no_link]),
    meck:expect(kapps_config, get_ne_binary, fun(_, _, Default) -> Default end),
    meck:expect(kapps_config, get_ne_binary, fun(_, _, Default, _) -> Default end),
    meck:expect(kapps_config, get_binary, fun(_, _, Default) -> Default end),
    meck:expect(kapps_config, get_binary, fun(_, _, Default, _) -> Default end),
    try Fun() after meck:unload(kapps_config) end.

callback_id() ->
    <<"acdc-callback-0000000000000000000000000000000000000000000000000000000000000000">>.

other_callback_id() ->
    <<"acdc-callback-1111111111111111111111111111111111111111111111111111111111111111">>.
