%%% SPDX-License-Identifier: MPL-2.0
%%% Actual socket callbacks, context, bh_events and binding registry. Only
%%% synchronous authorization/rate/config/broker/log providers are doubled.
%%% This does not claim real-token crypto, a broker or a live Cowboy socket.
-module(blackhole_queue_live_tests).
-include_lib("eunit/include/eunit.hrl").
-define(T, blackhole_queue_live_fixture).
-define(A, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(B, <<"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb">>).
-define(Q, <<"cccccccccccccccccccccccccccccccc">>).
-define(R, <<"dddddddddddddddddddddddddddddddd">>).
-define(TOKEN, <<"private-queue-live-test-token">>).

queue_live_test_() ->
    {foreach,fun setup/0,fun cleanup/1,
     [fun(_) -> ?_test(async_subscribe()) end,
      fun(_) -> ?_test(closed_delivery()) end,
      fun(_) -> ?_test(strict_scope()) end,
      fun(_) -> ?_test(generic_denied()) end,
      fun(_) -> ?_test(single_worker_and_coalescing()) end,
      fun(_) -> ?_test(token_changed()) end,
      fun(_) -> ?_test(identity_changed()) end,
      fun(_) -> ?_test(fresh_identity()) end,
      fun(_) -> ?_test(delivery_identity_changed()) end,
      fun(_) -> ?_test(unsubscribe_pending()) end,
      fun(_) -> ?_test(unsubscribe_delivery()) end,
      fun(_) -> ?_test(stale_generation()) end,
      fun(_) -> ?_test(timeout_and_late_result()) end,
      fun(_) -> ?_test(real_watchdog()) end,
      fun(_) -> ?_test(worker_crash()) end,
      fun(_) -> ?_test(close_cleans_owned_binding()) end,
      fun(_) -> ?_test(subscription_limit()) end,
      fun(_) -> ?_test(dirty_bound()) end,
      fun(_) -> ?_test(private_state()) end,
      fun(_) -> ?_test(invalid_event()) end,
      fun(_) -> ?_test(unavailable_local_auth()) end,
      fun(_) -> ?_test(ordinary_path()) end]}.

mocks() -> [lager,kz_nodes,kz_buckets,kz_auth,kapps_config,blackhole_listener,acdc_live_auth].
setup() ->
    ets:new(?T,[named_table,public,bag]),
    lists:foreach(fun(M)->ok=meck:new(M,[non_strict,no_link]) end,mocks()),
    lists:foreach(fun(Level)->
        meck:expect(lager,Level,fun(_)->ok end),
        meck:expect(lager,Level,fun(_,_)->ok end)
    end,[debug,info,warning,error]),
    meck:expect(lager,md,fun()->[] end),meck:expect(lager,md,fun(_)->ok end),
    meck:expect(kz_nodes,node_hostname,fun()-><<"fixture.invalid">> end),
    meck:expect(kz_buckets,consume_token,fun(<<"blackhole">>,_)->true end),
    meck:expect(kz_auth,validate_token,fun(?TOKEN)->{ok,kz_json:from_list([{<<"account_id">>,?A}])} end),
    meck:expect(kapps_config,get_integer,fun(<<"blackhole">>,<<"max_queued_messages">>,50)->50 end),
    meck:expect(blackhole_listener,add_bindings,fun(L)->ets:insert(?T,{add,L}),ok end),
    meck:expect(blackhole_listener,remove_bindings,fun(L)->ets:insert(?T,{remove,L}),ok end),
    meck:expect(acdc_live_auth,fresh_token,fun(Token,A,Q)->
        [{owner,Owner}]=ets:lookup(?T,owner),
        ets:insert(?T,{worker,self()}),Owner!{auth_started,self(),Token,A,Q},
        receive {auth_release,Result}->Result after 4500->{error,fixture_timeout} end
    end),
    {ok,Pid}=kazoo_bindings:start_link(),unlink(Pid),
    Table=ets:new(kazoo_bindings:table_id(),kazoo_bindings:table_options()),
    true=ets:give_away(Table,Pid,ok),true=gen_server:call(Pid,is_ready),
    ok=bh_queue_live:init(),ok=bh_events:init(),Pid.
cleanup(Pid) ->
    %% Also cleans a worker left by a failing assertion; no success-only cleanup.
    lists:foreach(fun({worker,W})->exit(W,kill) end,ets:lookup(?T,worker)),
    gen_server:stop(Pid),meck:unload(mocks()),ets:delete(?T).
context() ->
    ets:delete(?T,owner),ets:insert(?T,{owner,self()}),
    bh_context:set_auth_token(bh_context:set_auth_account_id(
        bh_context:new(self(),<<"queue-live-fixture">>),?A),?TOKEN).
request(Action,A,Q) -> kz_json:from_list([{<<"action">>,Action},{<<"request_id">>,<<"req">>},
    {<<"data">>,kz_json:from_list([{<<"account_id">>,A},{<<"binding">>,client(Q)}])}]).
frame(J,C) -> blackhole_socket_handler:websocket_handle({text,kz_json:encode(J)},C).
info(M,C) -> blackhole_socket_handler:websocket_info(M,C).
client(Q) -> <<"queue_live.changed.",Q/binary>>.
route(A,Q) -> <<"acdc.dashboard.changed.",A/binary,".",Q/binary>>.
key(A,Q) -> {client(Q),[route(A,Q)]}.
state(C) -> bh_context:queue_live_state(C).
worker(C) -> maps:get(worker,state(C)).
auth_started(A,Q) ->
    receive {auth_started,Pid,?TOKEN,A,Q}->Pid after 1000->error(no_auth_worker) end.
release(Pid,A) -> Pid!{auth_release,{ok,cb_context:set_auth_account_id(cb_context:new(),A)}},ok.
result(C) ->
    Ref=maps:get(ref,worker(C)),
    receive {queue_live_result,Ref,_}=M->info(M,C) after 1000->error(no_auth_result) end.
reply_status({reply,{text,B},_}) -> kz_json:get_value(<<"status">>,kz_json:decode(B)).
sub(C,Q) ->
    {ok,Pending}=frame(request(<<"subscribe">>,?A,Q),C),
    Pid=auth_started(?A,Q),release(Pid,?A),
    {reply,{text,B},Done}=result(Pending),
    ?assertEqual(<<"success">>,kz_json:get_value(<<"status">>,kz_json:decode(B))),Done.
dirty(C,Q) -> {ok,Next}=info({queue_live_dirty,?A,Q},C),Next.
none_auth() -> receive {auth_started,_,_,_,_}->?assert(false) after 0->ok end.
none_hint() -> receive {queue_live_dirty,_,_}->?assert(false); {send_data,_}->?assert(false) after 0->ok end.
changed(A,Q) -> kz_json:from_list([{<<"Version">>,1},{<<"Account-ID">>,A},{<<"Queue-ID">>,Q},
    {<<"Event-Category">>,<<"acdc_dashboard">>},{<<"Event-Name">>,<<"changed">>},
    {<<"App-Name">>,<<"acdc">>},{<<"App-Version">>,<<"test">>},{<<"Msg-ID">>,<<"event">>}]).
deliver(A,Q,J) ->
    RK=route(A,Q),blackhole_bindings:map(<<"blackhole.event.",RK/binary>>,[RK,J]).

async_subscribe() ->
    C=context(),{ok,Pending}=frame(request(<<"subscribe">>,?A,?Q),C),
    Pid=auth_started(?A,?Q),?assert(Pid=/=self()),
    ?assertEqual([],bh_context:bindings(Pending)),?assertEqual([],ets:lookup(?T,add)),
    ?assertMatch({ok,_,hibernate},blackhole_socket_handler:websocket_handle(ping,Pending)),
    release(Pid,?A),{reply,{text,_},Done}=result(Pending),
    ?assertEqual([key(?A,?Q)],bh_context:bindings(Done)),
    ?assertEqual([{add,[{amqp,acdc_dashboard_events,[{account_id,?A},{queue_id,?Q},federate]}]}],ets:lookup(?T,add)),
    ?assertMatch({bh_queue_live,_},maps:get(key(?A,?Q),bh_context:binding_resources(Done))),
    ?assertEqual(undefined,maps:get(worker,state(Done))).
closed_delivery() ->
    C=sub(context(),?Q),deliver(?A,?Q,changed(?A,?Q)),
    Pending=receive {queue_live_dirty,?A,?Q}=M->{ok,N}=info(M,C),N after 1000->error(no_dirty) end,
    Pid=auth_started(?A,?Q),none_hint(),release(Pid,?A),
    {reply,{text,B},_}=result(Pending),J=kz_json:decode(B),
    ?assertEqual(<<"event">>,kz_json:get_value(<<"action">>,J)),
    ?assertEqual(<<"changed">>,kz_json:get_value(<<"name">>,J)),
    ?assertEqual(client(?Q),kz_json:get_value(<<"subscribed_key">>,J)),
    ?assertEqual(route(?A,?Q),kz_json:get_value(<<"routing_key">>,J)),
    ?assertEqual(lists:sort([{<<"version">>,1},{<<"account_id">>,?A},{<<"queue_id">>,?Q}]),
                 lists:sort(kz_json:to_proplist(kz_json:get_value(<<"data">>,J)))),none_hint().
strict_scope() ->
    C=context(),Base=request(<<"subscribe">>,?A,?Q),
    Bad=[request(<<"subscribe">>,<<"*">>,?Q),request(<<"subscribe">>,?A,<<"#">>),
         request(<<"subscribe">>,?A,<<"CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC">>),
         request(<<"noop">>,?A,?Q),
         kz_json:delete_key([<<"data">>,<<"account_id">>],Base),
         kz_json:set_value([<<"data">>,<<"bindings">>],[client(?Q)],Base),
         kz_json:set_value([<<"data">>,<<"bindings">>],[client(?Q),client(?R)],
             kz_json:delete_key([<<"data">>,<<"binding">>],Base)),
         kz_json:set_value(<<"auth_token">>,binary:copy(<<"x">>,16385),Base)],
    lists:foreach(fun(J)->?assertEqual(<<"error">>,reply_status(frame(J,C))) end,Bad),
    none_auth(),?assertEqual([],ets:lookup(?T,add)).
generic_denied() ->
    C=context(),P=kz_json:delete_key(<<"action">>,request(<<"subscribe">>,?A,?Q)),
    ?assertNot(bh_context:success(bh_events:authorize(C,P))),none_auth().
single_worker_and_coalescing() ->
    C=sub(sub(context(),?Q),?R),D=dirty(C,?Q),Pid=auth_started(?A,?Q),
    ?assertEqual(<<"error">>,reply_status(frame(request(<<"subscribe">>,?A,?R),D))),
    Coalesced=lists:foldl(fun(_,Acc)->dirty(dirty(Acc,?Q),?R) end,D,lists:seq(1,500)),
    ?assertEqual(2,length(maps:get(dirty,state(Coalesced)))),none_auth(),
    release(Pid,?A),{reply,{text,_},Next}=result(Coalesced),
    ?assert(is_pid(auth_started(?A,?Q))),?assertEqual(1,length(maps:get(dirty,state(Next)))),
    bh_queue_live:close(Next).
token_changed() ->
    C=sub(context(),?Q),D=dirty(C,?Q),Pid=auth_started(?A,?Q),release(Pid,?A),
    Changed=bh_context:set_auth_token(D,<<"replacement">>),
    ?assertMatch({ok,_},result(Changed)),none_hint().
identity_changed() ->
    {ok,C}=frame(request(<<"subscribe">>,?A,?Q),context()),
    Pid=auth_started(?A,?Q),release(Pid,?A),
    Changed=bh_context:set_auth_account_id(C,?B),
    ?assertEqual(<<"error">>,reply_status(result(Changed))),?assertEqual([],ets:lookup(?T,add)).
fresh_identity() ->
    %% Stale retained principal must not replace fresh helper identity.
    {ok,C}=frame(request(<<"subscribe">>,?A,?Q),context()),Pid=auth_started(?A,?Q),release(Pid,?B),
    {reply,{text,_},Done}=result(C),?assertEqual(?B,bh_context:auth_account_id(Done)),
    ?assertMatch({_,?B},maps:get({?A,?Q},maps:get(members,state(Done)))).
delivery_identity_changed() ->
    D=dirty(sub(context(),?Q),?Q),Pid=auth_started(?A,?Q),release(Pid,?B),
    ?assertMatch({ok,_},result(D)),none_hint().
unsubscribe_pending() ->
    {ok,C}=frame(request(<<"subscribe">>,?A,?Q),context()),Pid=auth_started(?A,?Q),W=worker(C),
    {reply,[{text,Cancel},{text,Ack}],Done}=frame(request(<<"unsubscribe">>,?A,?Q),C),
    ?assertEqual(<<"error">>,kz_json:get_value(<<"status">>,kz_json:decode(Cancel))),
    ?assertEqual(<<"success">>,kz_json:get_value(<<"status">>,kz_json:decode(Ack))),
    ?assertEqual([],bh_context:bindings(Done)),?assertEqual(undefined,worker(Done)),
    ?assertEqual({ok,Done},info({queue_live_result,maps:get(ref,W),{ok,?A}},Done)),
    wait_dead(Pid),?assertEqual([],ets:lookup(?T,add)).
unsubscribe_delivery() ->
    D=dirty(sub(context(),?Q),?Q),Pid=auth_started(?A,?Q),W=worker(D),
    {reply,{text,_},Done}=frame(request(<<"unsubscribe">>,?A,?Q),D),
    ?assertEqual([],bh_context:bindings(Done)),?assertEqual(#{},maps:get(members,state(Done))),
    ?assertEqual({ok,Done},info({queue_live_result,maps:get(ref,W),{ok,?A}},Done)),
    ?assertEqual([],deliver(?A,?Q,changed(?A,?Q))),wait_dead(Pid),none_hint().
stale_generation() ->
    D=dirty(sub(context(),?Q),?Q),Pid=auth_started(?A,?Q),release(Pid,?A),
    S=state(D),Members=maps:put({?A,?Q},{make_ref(),?A},maps:get(members,S)),
    Changed=bh_context:set_queue_live_state(D,S#{members:=Members}),
    ?assertMatch({ok,_},result(Changed)),none_hint().
timeout_and_late_result() ->
    {ok,C}=frame(request(<<"subscribe">>,?A,?Q),context()),Pid=auth_started(?A,?Q),
    W=worker(C),S=state(C),release(Pid,?A),
    Expired=bh_context:set_queue_live_state(C,S#{worker:=W#{deadline:=erlang:monotonic_time(millisecond)-1}}),
    {reply,{text,B},Done}=result(Expired),
    ?assertEqual(<<"error">>,kz_json:get_value(<<"status">>,kz_json:decode(B))),
    ?assertEqual({ok,Done},info({queue_live_result,maps:get(ref,W),{ok,?A}},Done)),
    ?assertEqual([],ets:lookup(?T,add)).
real_watchdog() ->
    {ok,C}=frame(request(<<"subscribe">>,?A,?Q),context()),Pid=auth_started(?A,?Q),
    ?assert(maps:get(deadline,worker(C))-erlang:monotonic_time(millisecond)=<3000),
    %% Deliberately do not dispatch the session timer; the worker must die on
    %% its independent watchdog, even if the websocket mailbox is not drained.
    Mon=monitor(process,Pid),receive {'DOWN',Mon,process,Pid,killed}->ok after 3500->error(watchdog_failed) end,
    {reply,{text,B},Done}=info({queue_live_timeout,maps:get(ref,worker(C))},C),
    ?assertEqual(<<"error">>,kz_json:get_value(<<"status">>,kz_json:decode(B))),
    ?assertEqual(undefined,worker(Done)),?assertEqual([],ets:lookup(?T,add)).
worker_crash() ->
    {ok,C}=frame(request(<<"subscribe">>,?A,?Q),context()),Pid=auth_started(?A,?Q),exit(Pid,kill),
    Mon=maps:get(monitor,worker(C)),
    receive {'DOWN',Mon,process,Pid,_}=M->?assertEqual(<<"error">>,reply_status(info(M,C)))
    after 1000->error(no_down) end.
close_cleans_owned_binding() ->
    D=dirty(sub(context(),?Q),?Q),Pid=auth_started(?A,?Q),
    Done=blackhole_socket_callback:close(D),
    ?assertEqual([],bh_context:bindings(Done)),?assertEqual(#{},state(Done)),wait_dead(Pid),
    ?assertEqual([],deliver(?A,?Q,changed(?A,?Q))),none_hint(),
    ?assertMatch([{remove,[_]}],ets:lookup(?T,remove)).
subscription_limit() ->
    C=context(),Members=maps:from_list([{{?A,integer_to_binary(N)},{make_ref(),?A}}||N<-lists:seq(1,100)]),
    Full=bh_context:set_queue_live_state(C,#{members=>Members,dirty=>[],worker=>undefined}),
    ?assertEqual(<<"error">>,reply_status(frame(request(<<"subscribe">>,?A,?Q),Full))),none_auth().
dirty_bound() ->
    C=sub(context(),?Q),D=dirty(C,?Q),auth_started(?A,?Q),
    S=state(D),Full=bh_context:set_queue_live_state(D,S#{dirty:=lists:duplicate(100,{?A,?R,make_ref()})}),
    {ok,Next}=info({queue_live_dirty,?A,?Q},Full),?assertEqual(100,length(maps:get(dirty,state(Next)))),
    bh_queue_live:close(Next).
private_state() ->
    C=sub(context(),?Q),D=dirty(C,?Q),auth_started(?A,?Q),
    Attack=kz_json:from_list([{<<"queue_live_state">>,kz_json:new()}]),
    ?assertEqual(state(D),state(bh_context:from_json(D,Attack))),
    J=bh_context:to_json(D),?assertEqual(undefined,kz_json:get_value(<<"queue_live_state">>,J)),
    ?assertEqual(nomatch,binary:match(term_to_binary(blackhole_bindings:bindings()),?TOKEN)),
    ?assertEqual(nomatch,binary:match(term_to_binary(bh_context:binding_resources(D)),?TOKEN)),
    ?assertNot(maps:is_key(auth_token,worker(D))),bh_queue_live:close(D).
invalid_event() ->
    C=sub(context(),?Q),
    deliver(?A,?Q,changed(?B,?Q)),
    deliver(?A,?Q,kz_json:set_value(<<"Caller-ID-Number">>,<<"secret">>,changed(?A,?Q))),
    deliver(?A,?Q,kz_json:set_value(<<"Version">>,2,changed(?A,?Q))),
    none_hint(),none_auth(),?assertEqual(undefined,worker(C)).
unavailable_local_auth() ->
    {ok,C}=frame(request(<<"subscribe">>,?A,?Q),context()),Pid=auth_started(?A,?Q),
    Pid!{auth_release,{error,local_crossbar_unavailable}},
    ?assertEqual(<<"error">>,reply_status(result(C))),?assertEqual([],ets:lookup(?T,add)).
ordinary_path() ->
    C=context(),?assertEqual(pass,bh_queue_live:handle(<<"noop">>,kz_json:new(),C)),
    ok=bh_ping:init(),ok=bh_token_auth:init(),
    ?assertMatch({ok,_,hibernate},frame(kz_json:from_list([{<<"action">>,<<"ping">>}]),C)),
    receive {send_data,Reply} ->
        ?assertEqual(<<"success">>,kz_json:get_value(<<"status">>,Reply)),
        ?assertEqual(<<"pong">>,kz_json:get_value([<<"data">>,<<"response">>],Reply))
    after 1000 -> error(missing_native_reply)
    end,
    ?assertEqual({reply,pong,C},info(pong,C)),none_auth().
wait_dead(Pid) ->
    Mon=monitor(process,Pid),receive {'DOWN',Mon,process,Pid,_}->ok after 1000->error(worker_survived) end.
