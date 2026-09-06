%%% SPDX-License-Identifier: MPL-2.0
%%% Real bh_events/context, binding server and listener reference-count callbacks.
%%% Broker/config providers are substituted; no authentication or wire proof.
-module(blackhole_binding_cleanup_tests).
-include_lib("eunit/include/eunit.hrl").
-export([bindings/2, event/3]).
-define(TABLE, blackhole_cleanup_fixture).

cleanup_test_() ->
    {foreach, fun setup/0, fun cleanup/1,
     [fun(_) -> ?_test(custom_unsubscribe()) end,
      fun(_) -> ?_test(custom_close()) end,
      fun(_) -> ?_test(default_unsubscribe()) end,
      fun(_) -> ?_test(default_close()) end,
      fun(_) -> ?_test(changed_resolver()) end,
      fun(_) -> ?_test(shared_bindings()) end,
      fun(_) -> ?_test(shared_sessions()) end,
      fun(_) -> ?_test(account_isolation()) end,
      fun(_) -> ?_test(private_metadata()) end,
      fun(_) -> ?_test(legacy_default()) end]}.

mocks() -> [lager, kz_nodes, kapps_config, kz_events, gen_listener].
setup() ->
    ets:new(?TABLE, [named_table, public]),
    ets:insert(?TABLE, {resolver, custom}),
    ok = meck:new(lager, [non_strict, no_link]),
    lists:foreach(fun(M) -> ok = meck:new(M, [no_link]) end,
                  [kz_nodes, kapps_config, kz_events, gen_listener]),
    lists:foreach(fun(Level) ->
        meck:expect(lager, Level, fun(_) -> ok end),
        meck:expect(lager, Level, fun(_, _) -> ok end)
    end, [debug, info, warning, error]),
    meck:expect(lager, md, fun() -> case get(cleanup_md) of undefined -> []; V -> V end end),
    meck:expect(lager, md, fun(V) -> put(cleanup_md, V), ok end),
    meck:expect(kz_nodes, node_hostname, fun() -> <<"cleanup.invalid">> end),
    meck:expect(kapps_config, get_integer,
                fun(<<"blackhole">>, <<"max_queued_messages">>, 50) -> 50 end),
    meck:expect(kz_events, add_async_call_event_handler, fun(<<"*">>, <<"*">>, _) -> ok end),
    meck:expect(gen_listener, cast, fun(blackhole_listener, Message) ->
        Ref = make_ref(), whereis(blackhole_cleanup_listener) ! {self(), Ref, Message},
        receive {Ref, ok} -> ok after 1000 -> error(listener_timeout) end
    end),
    meck:expect(gen_listener, add_binding, fun(_, fixture_api, Options) ->
        ets:update_counter(?TABLE, {add, Options}, 1, {{add, Options}, 0}), ok
    end),
    meck:expect(gen_listener, rm_binding, fun(_, fixture_api, Options) ->
        ets:update_counter(?TABLE, {remove, Options}, 1, {{remove, Options}, 0}), ok
    end),
    {ok, BindingPid} = kazoo_bindings:start_link(), unlink(BindingPid),
    Table = ets:new(kazoo_bindings:table_id(), kazoo_bindings:table_options()),
    true = ets:give_away(Table, BindingPid, ok),
    true = gen_server:call(BindingPid, is_ready),
    Parent = self(),
    Listener = spawn(fun() ->
        true = register(blackhole_cleanup_listener, self()),
        {ok, State} = blackhole_listener:init([]), Parent ! {listener_ready, self()},
        listener_loop(State)
    end),
    receive {listener_ready, Listener} -> ok after 1000 -> error(listener_start_timeout) end,
    ok = blackhole_bindings:bind(<<"blackhole.events.bindings.fixture">>, ?MODULE, bindings),
    {BindingPid, Listener}.

listener_loop(State) ->
    receive
        {From, Ref, stop} -> From ! {Ref, ok};
        {From, Ref, Message} ->
            {noreply, Next} = blackhole_listener:handle_cast(Message, State),
            From ! {Ref, ok}, listener_loop(Next)
    end.

cleanup({BindingPid, Listener}) ->
    Ref = make_ref(), Monitor = monitor(process, Listener), Listener ! {self(), Ref, stop},
    receive {Ref, ok} -> ok after 1000 -> exit(Listener, kill) end,
    receive {'DOWN', Monitor, process, Listener, _} -> ok after 1000 -> error(listener_stop_timeout) end,
    gen_server:stop(BindingPid), meck:unload(mocks()), ets:delete(?TABLE).

options(Account) -> [{account, Account}, {stream, shared}].
listener(Account) -> {amqp, fixture_api, options(Account)}.
count(Action, Account) ->
    case ets:lookup(?TABLE, {Action, options(Account)}) of [] -> 0; [{_, N}] -> N end.
context(Session) -> bh_context:set_auth_account_id(bh_context:new(self(), Session), <<"a">>).
payload(Account, Names) -> kz_json:from_list([{<<"data">>, kz_json:from_list([
    {<<"account_id">>, Account}, {<<"bindings">>, [<<"fixture.", N/binary>> || N <- Names]}])}]).
subscribe(C, A, Names) -> bh_events:subscribe(C, payload(A, Names)).
unsubscribe(C, A, Names) -> bh_events:unsubscribe(C, payload(A, Names)).
route(A, N) -> <<"fixture.", A/binary, ".", N/binary>>.
key(A, N) -> {<<"fixture.", N/binary>>, [route(A, N)]}.
bindings(_, #{account_id:=A, keys:=[N]}) ->
    [{resolver, Resolver}] = ets:lookup(?TABLE, resolver),
    Base = #{requested => <<"fixture.", N/binary>>, subscribed => [route(A, N)],
             listeners => [listener(A), listener(A)]},
    case {N, Resolver} of
        {<<"default">>, _} -> Base;
        {_, custom} -> Base#{module => ?MODULE};
        {_, changed} -> Base#{module => bh_events, listeners => [listener(<<"resolver-changed">>)]}
    end.
event(#{session_pid:=Pid, session_id:=Id}, Route, _) -> Pid ! {custom_event, Id, Route}, ok.
deliver(A, N) ->
    Route = route(A, N),
    blackhole_bindings:map(<<"blackhole.event.", Route/binary>>,
        [Route, kz_json:from_list([{<<"Event-Category">>, <<"fixture">>}, {<<"Event-Name">>, <<"changed">>}])]).
custom_received(Id, A, N) ->
    Route = route(A, N),
    receive {custom_event, Id, Route} -> ok after 1000 -> error(missing_custom_event) end.
default_received() -> receive {send_data, _} -> ok after 1000 -> error(missing_default_event) end.
none_received() -> receive {custom_event, _, _} -> ?assert(false); {send_data, _} -> ?assert(false)
                   after 0 -> ok end.
empty(C) -> ?assertEqual([], bh_context:bindings(C)), ?assertEqual([], bh_context:listeners(C)),
            ?assertEqual(#{}, bh_context:binding_resources(C)).

custom_unsubscribe() ->
    C = subscribe(context(<<"s">>), <<"a">>, [<<"one">>]),
    ?assertEqual([key(<<"a">>, <<"one">>)], bh_context:bindings(C)),
    deliver(<<"a">>, <<"one">>), custom_received(<<"s">>, <<"a">>, <<"one">>),
    After = unsubscribe(C, <<"a">>, [<<"one">>]), empty(After),
    ?assertEqual([], deliver(<<"a">>, <<"one">>)), none_received(),
    ?assertEqual(1, count(add, <<"a">>)), ?assertEqual(1, count(remove, <<"a">>)),
    empty(unsubscribe(After, <<"a">>, [<<"one">>])), empty(bh_events:close(After)),
    ?assertEqual(1, count(remove, <<"a">>)).
custom_close() ->
    C = subscribe(context(<<"s">>), <<"a">>, [<<"one">>, <<"two">>]),
    ets:insert(?TABLE, {resolver, changed}),
    After = bh_events:close(C), empty(After),
    ?assertEqual([], deliver(<<"a">>, <<"one">>)), ?assertEqual([], deliver(<<"a">>, <<"two">>)),
    ?assertEqual(1, count(remove, <<"a">>)), empty(bh_events:close(After)),
    ?assertEqual(1, count(remove, <<"a">>)), none_received().
default_unsubscribe() ->
    C = subscribe(context(<<"s">>), <<"a">>, [<<"default">>]),
    deliver(<<"a">>, <<"default">>), default_received(),
    empty(unsubscribe(C, <<"a">>, [<<"default">>])),
    ?assertEqual([], deliver(<<"a">>, <<"default">>)), none_received().
default_close() ->
    C = subscribe(context(<<"s">>), <<"a">>, [<<"default">>]), empty(bh_events:close(C)),
    ?assertEqual([], deliver(<<"a">>, <<"default">>)), ?assertEqual(1, count(remove, <<"a">>)).
changed_resolver() ->
    C = subscribe(context(<<"s">>), <<"a">>, [<<"one">>]),
    ets:insert(?TABLE, {resolver, changed}),
    Same = subscribe(C, <<"a">>, [<<"one">>]),
    ?assertEqual(bh_context:binding_resources(C), bh_context:binding_resources(Same)),
    deliver(<<"a">>, <<"one">>), custom_received(<<"s">>, <<"a">>, <<"one">>),
    empty(unsubscribe(Same, <<"a">>, [<<"one">>])),
    ?assertEqual([], deliver(<<"a">>, <<"one">>)), ?assertEqual(1, count(remove, <<"a">>)),
    ?assertEqual(0, count(add, <<"resolver-changed">>)), ?assertEqual(0, count(remove, <<"resolver-changed">>)).
shared_bindings() ->
    C = subscribe(context(<<"s">>), <<"a">>, [<<"one">>, <<"default">>, <<"one">>]),
    ?assertEqual(1, count(add, <<"a">>)),
    One = unsubscribe(C, <<"a">>, [<<"one">>, <<"one">>, <<"absent">>]),
    ?assertEqual(0, count(remove, <<"a">>)), ?assertEqual([listener(<<"a">>)], bh_context:listeners(One)),
    ?assertEqual([], deliver(<<"a">>, <<"one">>)), deliver(<<"a">>, <<"default">>), default_received(),
    empty(unsubscribe(One, <<"a">>, [<<"default">>])), ?assertEqual(1, count(remove, <<"a">>)).
shared_sessions() ->
    A = subscribe(context(<<"session-a">>), <<"a">>, [<<"one">>]),
    B = subscribe(context(<<"session-b">>), <<"a">>, [<<"one">>]),
    ?assertEqual(1, count(add, <<"a">>)), empty(bh_events:close(A)),
    ?assertEqual(0, count(remove, <<"a">>)), deliver(<<"a">>, <<"one">>),
    custom_received(<<"session-b">>, <<"a">>, <<"one">>), none_received(),
    empty(bh_events:close(B)), ?assertEqual(1, count(remove, <<"a">>)),
    ?assertEqual([], deliver(<<"a">>, <<"one">>)).
account_isolation() ->
    C = subscribe(context(<<"s">>), <<"a">>, [<<"one">>]),
    Both = subscribe(C, <<"b">>, [<<"one">>]),
    Left = unsubscribe(Both, <<"b">>, [<<"one">>]),
    ?assertEqual([key(<<"a">>, <<"one">>)], bh_context:bindings(Left)),
    ?assertEqual([], deliver(<<"b">>, <<"one">>)), deliver(<<"a">>, <<"one">>),
    custom_received(<<"s">>, <<"a">>, <<"one">>),
    ?assertEqual(0, count(remove, <<"a">>)), ?assertEqual(1, count(remove, <<"b">>)),
    empty(bh_events:close(Left)), ?assertEqual(1, count(remove, <<"a">>)).
private_metadata() ->
    C = subscribe(context(<<"s">>), <<"a">>, [<<"one">>]),
    Attack = kz_json:from_list([{<<"binding_resources">>, kz_json:new()},
                               {<<"metadata">>, kz_json:from_list([{<<"module">>, <<"bh_events">>}])}]),
    Next = bh_context:from_json(C, Attack),
    ?assertEqual(bh_context:binding_resources(C), bh_context:binding_resources(Next)),
    ?assertEqual(undefined, kz_json:get_value(<<"binding_resources">>, bh_context:to_json(Next))),
    empty(bh_events:close(Next)), ?assertEqual([], deliver(<<"a">>, <<"one">>)).
legacy_default() ->
    C = subscribe(context(<<"s">>), <<"a">>, [<<"default">>, <<"one">>]),
    %% New-size context constructed by existing setters, no saved resource map
    %% for its default binding. This is not old-tuple hot-upgrade support.
    Resources = maps:remove(key(<<"a">>, <<"default">>), bh_context:binding_resources(C)),
    Legacy = bh_context:set_binding_resources(C, Resources),
    Left = unsubscribe(Legacy, <<"a">>, [<<"one">>]),
    ?assertEqual(0, count(remove, <<"a">>)), deliver(<<"a">>, <<"default">>), default_received(),
    empty(bh_events:close(Left)), ?assertEqual(1, count(remove, <<"a">>)),
    ?assertEqual([], deliver(<<"a">>, <<"default">>)).
