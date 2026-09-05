%%% SPDX-License-Identifier: MPL-2.0
-module(acdc_agent_channel_events_tests).
-include_lib("eunit/include/eunit.hrl").
-include("acdc.hrl").

-define(ACCOUNT, <<"test-account">>).
-define(CALL, <<"test-call">>).

event(Direction, Fields) ->
    kz_json:from_list(Fields ++ [{<<"Call-ID">>, ?CALL}
                               ,{<<"Msg-ID">>, <<"test-message">>}
                               ,{<<"Call-Direction">>, Direction}
                               ,{<<"Event-Category">>, <<"call_event">>}
                               ,{<<"Event-Name">>, <<"CHANNEL_CREATE">>}
                               | kz_api:default_headers(<<"test">>, <<"1">>)]).

with_registry(Fun) ->
    {ok, _} = application:ensure_all_started(gproc),
    Keys = [Key || Account <- [?ACCOUNT, <<"foreign-account">>],
                   User <- [<<"alice">>, <<"bob">>, <<"carol">>, <<"123">>, <<"null">>,
                            <<"false">>, <<>>, undefined],
                   Key <- [?NEW_CHANNEL_REG(Account, User), ?DESTROYED_CHANNEL_REG(Account, User)]],
    lists:foreach(fun(Key) -> true = gproc:reg(Key) end, Keys),
    try Fun()
    after lists:foreach(fun(Key) -> true = gproc:unreg(Key) end, Keys), drain() end.

drain() -> receive _ -> drain() after 0 -> ok end.
messages() -> messages([]).
messages(Acc) -> receive Message -> messages([Message | Acc]) after 0 -> lists:sort(Acc) end.

missing_all_optional_sip_fields_regression_test() -> with_registry(fun() ->
    lists:foreach(fun(Direction) ->
        Event = event(Direction, []),
        ?assert(kapi_call:event_v(Event)),
        ?assertEqual(ok, acdc_agent_handler:handle_new_channel(Event, ?ACCOUNT)),
        ?assertEqual(ok, acdc_agent_handler:handle_destroyed_channel(Event, ?ACCOUNT))
    end, [<<"inbound">>, <<"outbound">>, <<"unknown">>]),
    ?assertEqual([], messages())
end).

inbound_only_requires_from_test() -> with_registry(fun() ->
    Event = event(<<"inbound">>, [{<<"From">>, <<"alice@realm.invalid">>}]),
    ?assertEqual(ok, acdc_agent_handler:handle_new_channel(Event, ?ACCOUNT)),
    ?assertEqual([?NEW_CHANNEL_FROM(?CALL)], messages()),
    ?assertEqual(ok, acdc_agent_handler:handle_destroyed_channel(Event, ?ACCOUNT)),
    ?assertEqual([?DESTROYED_CHANNEL(?CALL, <<"unknown">>)], messages())
end).

outbound_does_not_require_from_test() -> with_registry(fun() ->
    Event = event(<<"outbound">>, [{<<"To">>, <<"bob@realm.invalid">>}
                                 ,{<<"Request">>, <<"carol@realm.invalid">>}
                                 ,{<<"Custom-Channel-Vars">>, kz_json:from_list(
                                     [{<<"Member-Call-ID">>, <<"member-call">>}])}]),
    ?assertEqual(ok, acdc_agent_handler:handle_new_channel(Event, ?ACCOUNT)),
    ?assertEqual(lists:duplicate(2, ?NEW_CHANNEL_TO(?CALL, <<"member-call">>)), messages()),
    ?assertEqual(ok, acdc_agent_handler:handle_destroyed_channel(Event, ?ACCOUNT)),
    ?assertEqual([?DESTROYED_CHANNEL(?CALL, <<"unknown">>)], messages())
end).

malformed_optional_fields_do_not_suppress_valid_peer_test() -> with_registry(fun() ->
    Bad = [undefined, null, false, 123, [<<"alice">>], kz_json:new(), <<>>,
           <<"@realm.invalid">>, <<"alice@">>, <<"alice@realm@other">>],
    lists:foreach(fun(Value) ->
        Event = event(<<"outbound">>, [{<<"From">>, Value}, {<<"To">>, Value},
                                      {<<"Request">>, <<"carol@realm.invalid">>}]),
        ?assertEqual(ok, acdc_agent_handler:handle_new_channel(Event, ?ACCOUNT)),
        ?assertEqual([?NEW_CHANNEL_TO(?CALL, undefined)], messages()),
        ?assertEqual(ok, acdc_agent_handler:handle_destroyed_channel(Event, ?ACCOUNT)),
        ?assertEqual([], messages()),
        Reverse = kz_json:set_values([{<<"To">>, <<"bob@realm.invalid">>},
                                      {<<"Request">>, Value}],
                                     kz_json:delete_key(<<"Request">>, Event)),
        ?assertEqual(ok, acdc_agent_handler:handle_new_channel(Reverse, ?ACCOUNT)),
        ?assertEqual([?NEW_CHANNEL_TO(?CALL, undefined)], messages())
    end, Bad)
end).

duplicate_destinations_notify_once_test() -> with_registry(fun() ->
    Event = event(<<"outbound">>, [{<<"From">>, <<"bob@realm.invalid">>},
                                  {<<"To">>, <<"bob@realm.invalid">>},
                                  {<<"Request">>, <<"bob@realm.invalid">>}]),
    ok = acdc_agent_handler:handle_new_channel(Event, ?ACCOUNT),
    ?assertEqual([?NEW_CHANNEL_TO(?CALL, undefined)], messages()),
    ok = acdc_agent_handler:handle_destroyed_channel(Event, ?ACCOUNT),
    ?assertEqual([?DESTROYED_CHANNEL(?CALL, <<"unknown">>)], messages())
end).

bare_normalized_username_remains_compatible_test() -> with_registry(fun() ->
    Event = event(<<"inbound">>, [{<<"From">>, <<"alice">>}]),
    ok = acdc_agent_handler:handle_new_channel(Event, ?ACCOUNT),
    ?assertEqual([?NEW_CHANNEL_FROM(?CALL)], messages())
end).

direction_selects_only_the_existing_routing_fields_test() -> with_registry(fun() ->
    Event = event(<<"outbound">>, [{<<"From">>, <<"alice@realm.invalid">>}]),
    ok = acdc_agent_handler:handle_new_channel(Event, ?ACCOUNT),
    ?assertEqual([], messages()),
    ok = acdc_agent_handler:handle_destroyed_channel(Event, ?ACCOUNT),
    ?assertEqual([?DESTROYED_CHANNEL(?CALL, <<"unknown">>)], messages()),
    Inbound = event(<<"inbound">>, [{<<"To">>, <<"bob@realm.invalid">>},
                                    {<<"Request">>, <<"carol@realm.invalid">>}]),
    ok = acdc_agent_handler:handle_new_channel(Inbound, ?ACCOUNT),
    ok = acdc_agent_handler:handle_destroyed_channel(Inbound, ?ACCOUNT),
    ?assertEqual([], messages())
end).

unregistered_user_does_not_match_other_agent_test() -> with_registry(fun() ->
    Event = event(<<"inbound">>, [{<<"From">>, <<"unregistered@realm.invalid">>}]),
    ok = acdc_agent_handler:handle_new_channel(Event, ?ACCOUNT),
    ok = acdc_agent_handler:handle_destroyed_channel(Event, ?ACCOUNT),
    ?assertEqual([], messages())
end).

unknown_direction_and_account_never_dispatch_test() -> with_registry(fun() ->
    Event = event(<<"inbound">>, [{<<"From">>, <<"alice@realm.invalid">>}]),
    lists:foreach(fun(Account) ->
        ok = acdc_agent_handler:handle_new_channel(Event, Account),
        ok = acdc_agent_handler:handle_destroyed_channel(Event, Account)
    end, [undefined, <<>>, false, 123, []]),
    Unknown = kz_json:set_value(<<"Call-Direction">>, <<"unknown">>, Event),
    ok = acdc_agent_handler:handle_new_channel(Unknown, ?ACCOUNT),
    ok = acdc_agent_handler:handle_destroyed_channel(Unknown, ?ACCOUNT),
    ?assertEqual([], messages())
end).

account_scope_is_not_inferred_from_sip_realm_test() -> with_registry(fun() ->
    %% A third account has no registered listener, even when the URI resembles
    %% the name of an account with the same username.
    Event = event(<<"inbound">>, [{<<"From">>, <<"alice@test-account">>}]),
    ok = acdc_agent_handler:handle_new_channel(Event, <<"unregistered-account">>),
    ok = acdc_agent_handler:handle_destroyed_channel(Event, <<"unregistered-account">>),
    ?assertEqual([], messages())
end).

destroyed_missing_or_nonbinary_call_id_never_dispatch_test() -> with_registry(fun() ->
    Event = event(<<"outbound">>, [{<<"From">>, <<"alice@realm.invalid">>},
                                  {<<"To">>, <<"bob@realm.invalid">>}]),
    lists:foreach(fun(Value) ->
        ok = acdc_agent_handler:handle_destroyed_channel(
                 kz_json:set_value(<<"Call-ID">>, Value,
                                   kz_json:delete_key(<<"Call-ID">>, Event)), ?ACCOUNT)
    end, [undefined, <<>>, 123, false, null, []]),
    ?assertEqual([], messages())
end).

invalid_api_event_is_not_silently_swallowed_test() ->
    Event = kz_json:delete_key(<<"Event-Category">>, event(<<"inbound">>, [])),
    ?assertError({badmatch, false}, acdc_agent_handler:handle_new_channel(Event, ?ACCOUNT)).

unexpected_registry_failure_is_not_swallowed_test() ->
    ok = meck:new(gproc, [passthrough, no_link]),
    meck:expect(gproc, send, fun(_, _) -> erlang:error(registry_failed) end),
    Event = event(<<"inbound">>, [{<<"From">>, <<"alice@realm.invalid">>}]),
    try
        ?assertError(registry_failed, acdc_agent_handler:handle_new_channel(Event, ?ACCOUNT)),
        ?assertError(registry_failed, acdc_agent_handler:handle_destroyed_channel(Event, ?ACCOUNT))
    after meck:unload(gproc) end.
