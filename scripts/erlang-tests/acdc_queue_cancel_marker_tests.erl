%% Cancellation markers: released only by the delivery owner's acknowledgement.
-module(acdc_queue_cancel_marker_tests).
-include_lib("eunit/include/eunit.hrl").
-include("acdc.hrl").
-include("acdc_queue_manager.hrl").

-define(ACCOUNT, <<"account">>).
-define(QUEUE, <<"queue">>).
-define(KEY(CallId), {?ACCOUNT, ?QUEUE, CallId}).

state() -> #state{account_id=?ACCOUNT, queue_id=?QUEUE, supervisor=self()}.
cancel(CallId) ->
    kz_json:from_list([{<<"Account-ID">>,?ACCOUNT},{<<"Queue-ID">>,?QUEUE},{<<"Call-ID">>,CallId},{<<"Reason">>,<<"member_hangup">>}]).
cast(Msg, State) -> {noreply, Next} = noreply(acdc_queue_manager:handle_cast(Msg, State)), Next.
noreply({noreply, S}) -> {noreply, S};
noreply({noreply, S, _}) -> {noreply, S}.
markers(#state{ignored_member_calls=D}) -> lists:sort(dict:fetch_keys(D)).
member(CallId) -> kapps_call:set_call_id(CallId, kapps_call:new()).
snapshot(State) -> {reply,Reply,State}=acdc_queue_manager:handle_call(maintenance_state,{self(),make_ref()},State), Reply.

with_mocks(Fun) ->
    Mods=[acdc_stats, kapi_acdc_queue, acdc_util, acdc_queue_shared, kapps_call_command, gen_listener],
    [meck:new(M,[non_strict,no_link,passthrough]) || M <- Mods, M =/= acdc_stats, M =/= gen_listener],
    meck:new(acdc_stats,[non_strict,no_link]), meck:new(gen_listener,[non_strict,no_link]),
    try
        meck:expect(acdc_stats,call_abandoned,fun(_,_,_,_) -> ok end),
        meck:expect(kapi_acdc_queue,publish_queue_member_remove,fun(_) -> ok end),
        meck:expect(kapi_acdc_queue,publish_member_call_failure,fun(_,_) -> ok end),
        meck:expect(acdc_util,unbind_from_call_events,fun(_) -> ok end),
        meck:expect(acdc_util,queue_presence_update,fun(_,_) -> ok end),
        meck:expect(acdc_queue_shared,ack,fun(_,_) -> ok end),
        meck:expect(acdc_queue_shared,nack,fun(_,_) -> ok end),
        meck:expect(gen_listener,rm_binding,fun(_,_,_) -> ok end),
        meck:expect(gen_listener,cast,fun(Pid,Msg) -> Pid ! {cast,Msg}, ok end),
        Fun()
    after meck:unload(Mods) end.

%% The reproduced leak: a cancellation nobody consumes stays on this manager.
owner_settlement_releases_marker_and_reopens_maintenance_gate_test() -> with_mocks(fun() ->
    S1=cast({member_call_cancel,?KEY(<<"c1">>),cancel(<<"c1">>)},state()),
    ?assertEqual([?KEY(<<"c1">>)],markers(S1)),
    ?assertEqual({error,queue_manager_not_drained},snapshot(S1)),
    S2=cast({member_delivery_settled,<<"c1">>},S1),
    ?assertEqual([],markers(S2)),
    ?assertMatch({ok,#{queue_id:=?QUEUE}},snapshot(S2)),
    ?assertEqual(1,meck:num_calls(acdc_stats,call_abandoned,'_'))
end).

%% A nacked delivery is requeued, so its plain removal must keep suppression.
unsettled_removal_and_foreign_settlement_retain_marker_test() -> with_mocks(fun() ->
    S1=cast({member_call_cancel,?KEY(<<"c1">>),cancel(<<"c1">>)},state()),
    S2=cast({handle_queue_member_remove,<<"c1">>},S1),
    S3=cast({member_delivery_settled,<<"other-call">>},S2),
    S4=cast({member_delivery_settled,undefined},S3),
    ?assertEqual([?KEY(<<"c1">>)],markers(S4)),
    {reply,true,S5}=acdc_queue_manager:handle_call({should_ignore_member_call,?KEY(<<"c1">>)},self(),S4),
    ?assertEqual([],markers(S5))
end).

settlement_may_overtake_its_cancellation_only_for_an_unlisted_call_test() -> with_mocks(fun() ->
    Settled=cast({member_delivery_settled,<<"c1">>},state()),
    Skipped=cast({member_call_cancel,?KEY(<<"c1">>),cancel(<<"c1">>)},Settled),
    ?assertEqual([],markers(Skipped)),
    %% One settlement answers one cancellation.
    Again=cast({member_call_cancel,?KEY(<<"c1">>),cancel(<<"c1">>)},Skipped),
    ?assertEqual([?KEY(<<"c1">>)],markers(Again)),
    %% Enqueued again after settlement: a waiting member keeps full protection.
    Waiting=Settled#state{current_member_calls=[member(<<"c1">>)]},
    ?assertEqual([?KEY(<<"c1">>)],markers(cast({member_call_cancel,?KEY(<<"c1">>),cancel(<<"c1">>)},Waiting)))
end).

%% The preceding record has no settlement field; --baseline omits only this case
%% so the remaining behavioural failures are reproduced rather than masked.
-ifndef(BASELINE).
expired_settlement_never_suppresses_a_marker_and_cache_is_bounded_test() -> with_mocks(fun() ->
    Now=erlang:monotonic_time(millisecond),
    Old=(state())#state{settled_member_calls=#{?KEY(<<"c1">>) => Now - 6*60*1000}},
    ?assertEqual([?KEY(<<"c1">>)],markers(cast({member_call_cancel,?KEY(<<"c1">>),cancel(<<"c1">>)},Old))),
    Pruned=cast({member_delivery_settled,<<"c2">>},Old),
    ?assertEqual([?KEY(<<"c2">>)],maps:keys(Pruned#state.settled_member_calls)),
    Many=maps:from_list([{?KEY(integer_to_binary(N)),Now - N} || N <- lists:seq(1,2500)]),
    Bounded=cast({member_delivery_settled,<<"newest">>},(state())#state{settled_member_calls=Many}),
    Kept=Bounded#state.settled_member_calls,
    ?assertEqual(2000,maps:size(Kept)),
    ?assert(maps:is_key(?KEY(<<"newest">>),Kept)), ?assert(maps:is_key(?KEY(<<"1">>),Kept)),
    ?assertNot(maps:is_key(?KEY(<<"2500">>),Kept))
end).

-endif.

amqp_handlers_forward_settlement_only_when_the_owner_declared_it_test() -> with_mocks(fun() ->
    Base=[{<<"Account-ID">>,?ACCOUNT},{<<"Queue-ID">>,?QUEUE},{<<"Call-ID">>,<<"logical">>}],
    Props=[{server,self()}],
    ok=acdc_queue_manager:handle_queue_member_remove(kz_json:from_list(Base),Props),
    ?assertEqual([{handle_queue_member_remove,<<"logical">>}],drain()),
    ok=acdc_queue_manager:handle_queue_member_remove(kz_json:from_list([{<<"Settled-Call-ID">>,<<"physical">>}|Base]),Props),
    ?assertEqual([{handle_queue_member_remove,<<"logical">>},{member_delivery_settled,<<"physical">>}],drain()),
    ok=acdc_queue_manager:handle_queue_member_remove(kz_json:from_list([{<<"Settled-Call-ID">>,<<>>}|Base]),Props),
    ?assertEqual([{handle_queue_member_remove,<<"logical">>}],drain()),
    ok=acdc_queue_manager:handle_member_call_success(kz_json:from_list(Base),Props),
    ?assertEqual([{handle_queue_member_remove,<<"logical">>},{member_delivery_settled,<<"logical">>}],drain()),
    %% A returned callback leg: the marker key is the physical id.
    ok=acdc_queue_manager:handle_member_call_success(kz_json:from_list([{<<"Settled-Call-ID">>,<<"physical">>}|Base]),Props),
    ?assertEqual([{handle_queue_member_remove,<<"logical">>},{member_delivery_settled,<<"physical">>}],drain())
end).

drain() -> receive {cast,Msg} -> [Msg|drain()] after 0 -> [] end.

settled_header_schema_test() ->
    Base=[{<<"Account-ID">>,?ACCOUNT},{<<"Queue-ID">>,?QUEUE},{<<"Call-ID">>,<<"c1">>},{<<"Msg-ID">>,<<"m">>}
          |kz_api:default_headers(<<"server">>,<<"queue">>,<<"member_remove">>,<<"acdc">>,<<"1">>)],
    ?assert(kapi_acdc_queue:queue_member_remove_v(Base)),
    ?assert(kapi_acdc_queue:queue_member_remove_v([{<<"Settled-Call-ID">>,<<"c1">>}|Base])),
    ?assertNot(kapi_acdc_queue:queue_member_remove_v([{<<"Settled-Call-ID">>,true}|Base])),
    {ok,Payload}=kapi_acdc_queue:queue_member_remove([{<<"Settled-Call-ID">>,<<"c1">>}|Base]),
    ?assertEqual(<<"c1">>,kz_json:get_value(<<"Settled-Call-ID">>,kz_json:decode(iolist_to_binary(Payload)))).

%% Listener: the announcement follows the acknowledgement, never a nack.
listener(Call) ->
    acdc_queue_listener:callback_test_state([{call,Call},{account_id,?ACCOUNT},{queue_id,?QUEUE},{mgr_pid,self()}
                                            ,{shared_pid,self()},{delivery,delivery},{my_id,<<"me">>}
                                            ,{member_call_queue,<<"q">>}]).
published() ->
    [kz_json:from_list(P) || {_,{kapi_acdc_queue,publish_queue_member_remove,[P]},_} <- meck:history(kapi_acdc_queue)].
settled(JObj) -> kz_json:get_value(<<"Settled-Call-ID">>,JObj).

handled_callback_leg_announces_its_physical_id_test() -> with_mocks(fun() ->
    meck:expect(kapi_acdc_queue,publish_member_call_success,fun(_,_) -> ok end),
    Call=kapps_call:kvs_store(<<"acdc_logical_member_id">>,<<"logical">>,member(<<"physical">>)),
    Logical=acdc_queue_member:logical_id(Call),
    {noreply,_,hibernate}=acdc_queue_listener:handle_cast({finish_member_call},listener(Call)),
    [Sent]=[kz_json:from_list(P) || {_,{kapi_acdc_queue,publish_member_call_success,[_,P]},_} <- meck:history(kapi_acdc_queue)],
    ?assertEqual(Logical,kz_json:get_value(<<"Call-ID">>,Sent)),
    ?assertEqual(<<"physical">>,kz_json:get_value(<<"Settled-Call-ID">>,Sent)),
    ?assertEqual(1,meck:num_calls(acdc_queue_shared,ack,'_')),
    Wire=[{<<"Msg-ID">>,<<"m">>}|kz_api:default_headers(<<"server">>,<<"member">>,<<"call_success">>,<<"acdc">>,<<"1">>)]
        ++[{K,V} || {K,V} <- kz_json:to_proplist(Sent), not lists:member(K,[<<"App-Name">>,<<"App-Version">>])],
    ?assert(kapi_acdc_queue:member_call_success_v(Wire)),
    ?assert(kapi_acdc_queue:member_call_success_v(proplists:delete(<<"Settled-Call-ID">>,Wire))),
    ?assertNot(kapi_acdc_queue:member_call_success_v([{<<"Settled-Call-ID">>,true}|proplists:delete(<<"Settled-Call-ID">>,Wire)]))
end).

listener_announces_settlement_after_ack_and_never_after_nack_test() -> with_mocks(fun() ->
    Call=member(<<"c1">>),
    meck:expect(kapps_call_command,b_channel_status,fun(_) -> {error,not_found} end),
    {noreply,_,hibernate}=acdc_queue_listener:handle_cast({cancel_member_call,kz_json:new()},listener(Call)),
    ?assertEqual([<<"c1">>],[settled(J) || J <- published()]),
    ?assertEqual(1,meck:num_calls(acdc_queue_shared,ack,'_')),
    ?assertEqual(0,meck:num_calls(acdc_queue_shared,nack,'_')),
    ?assert(ack_precedes_publish()),
    meck:reset([kapi_acdc_queue,acdc_queue_shared]),
    meck:expect(kapps_call_command,b_channel_status,fun(_) -> {ok,kz_json:new()} end),
    {noreply,_,hibernate}=acdc_queue_listener:handle_cast({cancel_member_call,kz_json:new()},listener(Call)),
    ?assertEqual([undefined],[settled(J) || J <- published()]),
    ?assertEqual(1,meck:num_calls(acdc_queue_shared,nack,'_')),
    ?assertEqual(0,meck:num_calls(acdc_queue_shared,ack,'_')),
    meck:reset([kapi_acdc_queue,acdc_queue_shared]),
    {noreply,_,hibernate}=acdc_queue_listener:handle_cast({ignore_member_call,Call,delivery},listener(Call)),
    ?assertEqual([<<"c1">>],[settled(J) || J <- published()]),
    ?assertEqual(1,meck:num_calls(acdc_queue_shared,ack,'_'))
end).

ack_precedes_publish() ->
    Ack=hd([Pid_T || {Pid_T,{acdc_queue_shared,ack,_},_} <- meck:history(acdc_queue_shared)]),
    is_pid(Ack) andalso published() =/= [].
