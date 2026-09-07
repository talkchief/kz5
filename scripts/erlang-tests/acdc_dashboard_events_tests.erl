%%% Actual production KAPI, coalescer, stats mutations and configuration hook.
%%% Only broker/pool and existing queue lifecycle side effects are doubled.
%%% No delivery completeness, deployed listener or real AMQP claim.
-module(acdc_dashboard_events_tests).
-include_lib("eunit/include/eunit.hrl").
-include("acdc_stats.hrl").
-define(A, <<"11111111111111111111111111111111">>).
-define(B, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(Q, <<"22222222222222222222222222222222">>).
-define(Q2, <<"33333333333333333333333333333333">>).
-define(T, acdc_dashboard_events_pending).

dashboard_events_test_() ->
    {timeout,50,{setup,fun setup/0,fun cleanup/1,fun(_) ->
        [fun changed_roundtrip/0,fun closed_wire/0,fun native_transport/0,
         fun exact_bindings/0,fun invalid_bindings/0,fun actual_publish/0,
         fun missing_publisher/0,fun bounded_coalescing/0,fun collision_loss/0,
         fun concurrent_producers/0,fun unconfirmed_attempt/0,fun same_token_race/0,
         fun failed_attempt/0,fun stale_timer/0,fun fair_cursor/0,
         fun stats_ordering_and_noops/0,fun stats_scope_move/0,
         fun stats_bulk_and_archive/0,fun stats_missing_publisher/0,
         fun config_success_order/0,fun config_failure/0,fun config_rejection/0,
         fun supervisor_contract/0,fun blocked_publisher/0]
    end}}.

setup() ->
    Mods=[kz_amqp_worker,kz_amqp_util,kz_datamgr,acdc_queues_sup,acdc_queue_sup,
          acdc_queue_workers_sup,acdc_queue_manager],
    [meck:new(M,[non_strict,no_link]) || M<-Mods], Mods.
cleanup(Mods) -> [meck:unload(M) || M<-Mods], ok.

wire() ->
    [{<<"Version">>,1},{<<"Account-ID">>,?A},{<<"Queue-ID">>,?Q},
     {<<"App-Name">>,<<"test">>},{<<"App-Version">>,<<"1">>},
     {<<"Msg-ID">>,<<"event-test">>},{<<"Event-Category">>,<<"acdc_dashboard">>},
     {<<"Event-Name">>,<<"changed">>}].
put(K,V,P) -> [{K,V}|proplists:delete(K,P)].
rk(A,Q) -> <<"acdc.dashboard.changed.",A/binary,".",Q/binary>>.
hex(N) -> list_to_binary(io_lib:format("~32.16.0b",[N])).
headers(Name) -> [{<<"App-Name">>,<<"test">>},{<<"App-Version">>,<<"1">>},
    {<<"Msg-ID">>,<<"configuration-test">>},{<<"Event-Category">>,<<"configuration">>},
    {<<"Event-Name">>,Name}].
config(Name) -> kz_json:from_list([{<<"Account-ID">>,?A},{<<"ID">>,?Q},
    {<<"Database">>,<<"account/test">>},{<<"Type">>,<<"queue">>}|headers(Name)]).

changed_roundtrip() ->
    P=wire(), ?assert(kapi_acdc_dashboard_events:changed_v(P)),
    {ok,Bytes}=kapi_acdc_dashboard_events:changed(P),
    J=kz_json:decode(iolist_to_binary(Bytes)),
    ?assert(kapi_acdc_dashboard_events:changed_v(J)),
    ?assertEqual(lists:sort(P),lists:sort(kz_json:to_proplist(J))).

closed_wire() ->
    P=wire(),
    [?assertNot(kapi_acdc_dashboard_events:changed_v(put(K,V,P))) || {K,V}<-[
        {<<"Version">>,<<"1">>},{<<"Version">>,1.0},{<<"Version">>,2},
        {<<"Account-ID">>,<<"*">>},{<<"Account-ID">>,binary:copy(<<"A">>,32)},
        {<<"Queue-ID">>,<<"#">>},{<<"Queue-ID">>,<<"x">>},
        {<<"Event-Category">>,<<"call">>},{<<"Event-Name">>,<<"resync">>},
        {<<"Msg-ID">>,<<>>},{<<"Msg-ID">>,binary:copy(<<"x">>,129)},
        {<<"App-Name">>,<<"bad\nname">>},{<<"Node">>,binary:copy(<<"x">>,1025)},
        {<<"Server-ID">>,null},{<<"Server-Queue-ID">>,false},
        {<<"Call-ID">>,<<"private">>},{<<"revision">>,1},{<<"source_count">>,2}]],
    [?assertNot(kapi_acdc_dashboard_events:changed_v(proplists:delete(K,P))) ||
        K<-[<<"Version">>,<<"Queue-ID">>,<<"Account-ID">>,<<"Msg-ID">>]],
    [?assertNot(kapi_acdc_dashboard_events:changed_v(Bad)) ||
        Bad<-[42,undefined,[bad],[{<<"Version">>,1}|P],P++[bad],
              [{<<"private">>,undefined}|P]]],
    ?assertMatch({error,_},kapi_acdc_dashboard_events:changed([{<<"private">>,1}|P])).

native_transport() ->
    %% Exact listener_federator/gen_listener additions remain accepted, but do
    %% not change the A/Q business identity or allow arbitrary extra fields.
    P=[{<<"Server-ID">>,<<"consumer://<0.12.0>/broker-queue">>},
       {<<"Server-Queue-ID">>,null},{<<"Node">>,<<"test@node">>},
       {<<"AMQP-Broker">>,<<"amqp://synthetic-broker">>},
       {<<"AMQP-Broker-Zone">>,<<"test-zone">>},{<<"AMQP-Zone">>,<<"zone">>}|wire()],
    ?assert(kapi_acdc_dashboard_events:changed_v(P)),
    ?assert(kapi_acdc_dashboard_events:changed_v(kz_json:from_list(P))),
    ?assert(kapi_acdc_dashboard_events:changed_v(put(<<"Server-Queue-ID">>,
        <<"consumer://<0.12.0>/reply">>,P))),
    ?assertNot(kapi_acdc_dashboard_events:changed_v([{<<"AMQP-Zone">>,<<"duplicate">>}|P])).

exact_bindings() ->
    Parent=self(),
    meck:expect(kz_amqp_util,bind_q_to_callmgr,fun(Q,R)->Parent!{bound,Q,R},ok end),
    meck:expect(kz_amqp_util,unbind_q_from_callmgr,fun(Q,R)->Parent!{unbound,Q,R},ok end),
    [begin
        P=[{account_id,A},{queue_id,?Q}|Fed],
        ?assertEqual(ok,kapi_acdc_dashboard_events:bind_q(<<"test-q">>,P)),
        receive {bound,<<"test-q">>,R}->?assertEqual(rk(A,?Q),R) after 50->error(no_bind) end,
        ?assertEqual(ok,kapi_acdc_dashboard_events:unbind_q(<<"test-q">>,lists:reverse(P))),
        receive {unbound,<<"test-q">>,R2}->?assertEqual(rk(A,?Q),R2) after 50->error(no_unbind) end
     end || A<-[?A,?B],Fed<-[[],[federate],[{federate,true}]]].

invalid_bindings() ->
    meck:expect(kz_amqp_util,bind_q_to_callmgr,fun(_,_)->error(unexpected_binding) end),
    P=[{account_id,?A},{queue_id,?Q}],
    [?assertMatch({error,_},kapi_acdc_dashboard_events:bind_q(<<"test-q">>,Bad)) ||
        Bad<-[[],[federate],[{account_id,?A}],[{queue_id,?Q}],
              [{account_id,<<"*">>},{queue_id,?Q}],
              [{account_id,?A},{queue_id,<<"#">>}],
              [{account_id,?A}|P],[federate,{federate,true}|P],
              [{federate,false}|P],[{restrict_to,[changed]}|P],[bad|P],42]],
    [?assertMatch({error,_},kapi_acdc_dashboard_events:unbind_q(Q,P)) ||
        Q<-[<<>>,<<"bad\nqueue">>,binary:copy(<<"q">>,256)]].

actual_publish() ->
    Parent=self(),
    meck:expect(kz_amqp_util,callmgr_publish,fun(Bytes,<<"application/json">>,R)->
        Parent!{published,R,kz_json:decode(iolist_to_binary(Bytes))},ok end),
    ?assertEqual(ok,kapi_acdc_dashboard_events:publish_changed(wire())),
    receive {published,R,J}->
        ?assertEqual(rk(?A,?Q),R), ?assert(kapi_acdc_dashboard_events:changed_v(J)),
        ?assertEqual(undefined,kz_json:get_value(<<"Call-ID">>,J))
    after 100->error(no_publish) end,
    ?assertMatch({error,_},kapi_acdc_dashboard_events:publish_changed([{<<"private">>,undefined}|wire()])),
    receive {published,_,_}->error(invalid_published) after 0->ok end.

with_tables(F) ->
    {ok,S}=acdc_dashboard_events:init([]), _=erlang:cancel_timer(maps:get(timer,S)),
    T=ets:new(acdc_stats_call,[named_table,protected,{keypos,#call_stat.id}]),
    meck:expect(kz_amqp_worker,cast,fun(_,_)->error(unexpected_producer_publish) end),
    try F(S,T)
    after acdc_dashboard_events:terminate(normal,S),ets:delete(T),ets:delete(?T) end.
tick(S) ->
    Ref=maps:get(timer,S),_=erlang:cancel_timer(Ref),
    {noreply,N}=acdc_dashboard_events:handle_info({timeout,Ref,publish_tick},S),
    _=erlang:cancel_timer(maps:get(timer,N)),N.
d(K) -> maps:get(K,acdc_dashboard_events:diagnostics()).
pending() -> [E || E={K,_,_,_}<-ets:tab2list(?T),is_integer(K)].
clear() -> [ets:delete_object(?T,E) || E<-pending()],ok.
stat() -> #call_stat{id = <<"private-call::",?Q/binary>>,call_id = <<"private-call">>,
    account_id=?A,queue_id=?Q,status = <<"waiting">>,entered_timestamp=100,
    caller_id_name = <<"private-name">>,caller_id_number = <<"private-number">>}.
mutate(M) -> ?assertEqual({noreply,fixture_state},acdc_stats:handle_cast(M,fixture_state)).

missing_publisher() ->
    ?assertEqual({error,unavailable},acdc_dashboard_events:changed(?A,?Q)),
    ?assertEqual({error,unavailable},acdc_dashboard_events:bulk_removed(1)),
    ?assertEqual(false,d(available)), ?assertEqual(false,d(delivery_confirmed)).

bounded_coalescing() -> with_tables(fun(_,_) ->
    ?assertEqual(ok,acdc_dashboard_events:changed(?A,?Q)), [Old]=pending(),
    [?assertEqual(ok,acdc_dashboard_events:changed(?A,?Q)) || _<-lists:seq(1,1000)],
    [New]=pending(), ?assertNotEqual(Old,New),
    ?assertEqual(1,d(pending_slots)),?assertEqual(1000,d(coalesced)),
    [?assertEqual({error,invalid_scope},acdc_dashboard_events:changed(A,Q)) ||
        {A,Q}<-[{undefined,?Q},{?A,<<"*">>},{?A,<<>>},{?A,42}]],
    ?assertEqual(2,ets:info(?T,size))
end).

collision_loss() -> with_tables(fun(_,_) ->
    Slot=erlang:phash2({?A,?Q},1024),
    %% A concrete occupied hash slot, not an unbounded identity map.
    Other={Slot,make_ref(),?B,?Q2}, ets:insert(?T,Other),
    ?assertEqual({error,overloaded},acdc_dashboard_events:changed(?A,?Q)),
    ?assertEqual([Other],pending()),?assertEqual(1,d(dropped)),
    [acdc_dashboard_events:changed(?A,hex(N)) || N<-lists:seq(1,10000)],
    ?assert(ets:info(?T,size)=<1025),?assert(d(dropped)>0),
    ?assertEqual(true,d(reconciliation_required)),?assertEqual(15000,d(reconciliation_interval_ms))
end).

concurrent_producers() -> with_tables(fun(_,_) ->
    Parent=self(),
    Refs=[begin {_,Ref}=spawn_monitor(fun()->
        [acdc_dashboard_events:changed(?A,hex(I)) || I<-lists:seq(1,256)],
        Parent!producer_done end),Ref end || _<-lists:seq(1,16)],
    [receive producer_done->ok after 1000->error(producer_blocked) end || _<-Refs],
    [receive {'DOWN',R,process,_,normal}->ok after 1000->error(producer_failed) end || R<-Refs],
    ?assert(ets:info(?T,size)=<1025),
    %% Producers sent only their fixture completion, never a publisher cast.
    receive {'$gen_cast',_}->error(producer_cast) after 0->ok end
end).

unconfirmed_attempt() -> with_tables(fun(S,_) ->
    Parent=self(), meck:expect(kz_amqp_worker,cast,fun(P,F)->
        Parent!{attempt_payload,P},?assertEqual({kapi_acdc_dashboard_events,publish_changed},
            {proplists:get_value(module,erlang:fun_info(F)),proplists:get_value(name,erlang:fun_info(F))}),ok end),
    ok=acdc_dashboard_events:changed(?A,?Q),_=tick(S),
    ?assertEqual(0,d(pending_slots)),?assertEqual(1,d(attempts)),
    ?assertEqual(1,d(unconfirmed)),?assertEqual(false,d(delivery_confirmed)),
    receive {attempt_payload,P}->
        ?assertEqual(?A,proplists:get_value(<<"Account-ID">>,P)),
        ?assertEqual(?Q,proplists:get_value(<<"Queue-ID">>,P)),
        ?assertEqual(undefined,proplists:get_value(<<"Call-ID">>,P))
    after 100->error(no_attempt) end
end).

same_token_race() -> with_tables(fun(S,_) ->
    meck:expect(kz_amqp_worker,cast,fun(_,_)->
        ok=acdc_dashboard_events:changed(?A,?Q),ok end),
    ok=acdc_dashboard_events:changed(?A,?Q),[Old]=pending(),_=tick(S),
    [New]=pending(),?assertNotEqual(Old,New),?assertEqual(1,d(coalesced)),
    ?assertEqual(1,d(unconfirmed))
end).

failed_attempt() -> with_tables(fun(S,_) ->
    ok=acdc_dashboard_events:changed(?A,?Q),[Old]=pending(),
    meck:expect(kz_amqp_worker,cast,fun(_,_)->{error,pool_full} end), S2=tick(S),
    ?assertEqual([Old],pending()),?assertEqual(1,d(local_errors)),
    meck:expect(kz_amqp_worker,cast,fun(_,_)->exit(timeout) end),_=tick(S2),
    ?assertEqual([Old],pending()),?assertEqual(2,d(local_errors)),
    ?assertEqual(0,d(unconfirmed)),?assertEqual(2,d(attempts))
end).

stale_timer() -> with_tables(fun(S,_) ->
    ok=acdc_dashboard_events:changed(?A,?Q),
    ?assertEqual({noreply,S},acdc_dashboard_events:handle_info({timeout,make_ref(),publish_tick},S)),
    ?assertEqual({noreply,S},acdc_dashboard_events:handle_cast(changed,S)),
    ?assertEqual({reply,{error,unsupported},S},acdc_dashboard_events:handle_call(publish,self(),S)),
    ?assertEqual(0,d(attempts))
end).

fair_cursor() -> with_tables(fun(S,_) ->
    Parent=self(),
    meck:expect(kz_amqp_worker,cast,fun(P,_)->Parent!{scope,proplists:get_value(<<"Queue-ID">>,P)},
        {error,no_channel} end),
    ets:insert(?T,[{1,make_ref(),?A,?Q},{1000,make_ref(),?A,?Q2}]),
    S2=tick(S),S3=tick(S2),_=tick(S3),
    [?assertEqual(Q,receive {scope,V}->V after 100->error(no_scope) end) || Q<-[?Q,?Q2,?Q]],
    ?assertEqual(2,d(pending_slots))
end).

stats_ordering_and_noops() -> with_tables(fun(S,T) ->
    %% Observe ETS at the *mark call*, not only at the later publish. A broken
    %% pre-mutation mark must fail even if the later publisher sees new data.
    C=stat(),meck:new(acdc_dashboard_events,[passthrough,no_link]),
    try
        meck:expect(acdc_dashboard_events,changed,fun(A,Q)->
            ?assertEqual([C],ets:lookup(T,C#call_stat.id)),meck:passthrough([A,Q]) end),
        mutate({create_call,C}),?assertEqual(1,d(admitted)),clear(),
        meck:expect(acdc_dashboard_events,changed,fun(_,_)->error(noop_marked) end),
        mutate({create_call,C}),mutate({update_call,<<"missing">>,[{#call_stat.status,<<"handled">>}]}),
        mutate({flush_call,<<"missing">>}),mutate({update_call,C#call_stat.id,[{#call_stat.status,<<"waiting">>}]}),
        ?assertEqual([],pending()),
        meck:expect(acdc_dashboard_events,changed,fun(A,Q)->
            [After]=ets:lookup(T,C#call_stat.id),?assertEqual(<<"handled">>,After#call_stat.status),
            meck:passthrough([A,Q]) end),
        mutate({update_call,C#call_stat.id,[{#call_stat.status,<<"handled">>}]}),
        meck:expect(kz_amqp_worker,cast,fun(_,_)->ok end),
        S2=tick(S),?assertEqual([],pending()),
        meck:expect(acdc_dashboard_events,changed,fun(A,Q)->
            ?assertEqual([],ets:lookup(T,C#call_stat.id)),meck:passthrough([A,Q]) end),
        mutate({flush_call,C#call_stat.id}),_=tick(S2),?assertEqual([],pending())
    after meck:unload(acdc_dashboard_events) end
end).

stats_scope_move() -> with_tables(fun(_,T) ->
    C=stat(),ets:insert(T,C),
    mutate({update_call,C#call_stat.id,[{#call_stat.account_id,?B},{#call_stat.queue_id,?Q2}]}),
    Scopes=[{A,Q} || {_,_,A,Q}<-pending()],
    ?assertEqual(lists:sort([{?A,?Q},{?B,?Q2}]),lists:sort(Scopes)),
    %% A malformed update still fails before any hint is admitted.
    clear(),?assertError(badarg,acdc_stats:handle_cast({update_call,C#call_stat.id,[{999,bad}]},state)),
    ?assertEqual([],pending())
end).

stats_bulk_and_archive() -> with_tables(fun(_,T) ->
    C=stat(),ets:insert(T,C),
    mutate({archive_call_saved,C}),?assertEqual([],pending()),
    [Archived]=ets:lookup(T,C#call_stat.id),?assertEqual(true,Archived#call_stat.is_archived),
    mutate({update_call,C#call_stat.id,[]}),?assertEqual([],pending()),
    Match=[{#call_stat{status = <<"waiting">>,_='_'},[],['$_']}],
    mutate({remove_call,Match}),?assertEqual(0,ets:info(T,size)),?assertEqual([],pending()),
    ?assertEqual(1,d(bulk_operations)),?assertEqual(1,d(bulk_rows)),
    mutate({remove_call,Match}),?assertEqual(1,d(bulk_operations))
end).

stats_missing_publisher() ->
    T=ets:new(acdc_stats_call,[named_table,protected,{keypos,#call_stat.id}]),
    try C=stat(),mutate({create_call,C}),mutate({update_call,C#call_stat.id,[{#call_stat.status,<<"handled">>}]}),
        mutate({flush_call,C#call_stat.id}),?assertEqual(0,ets:info(T,size))
    after ets:delete(T) end.

config_success_order() -> with_tables(fun(_,_) ->
    meck:expect(acdc_queues_sup,find_queue_supervisor,fun(_,_)->undefined end),
    meck:expect(acdc_queues_sup,new,fun(A,Q)->?assertEqual({?A,?Q},{A,Q}),
        ?assertEqual([],pending()),{ok,self()} end),
    ?assertMatch({ok,_},acdc_queue_handler:handle_config_change(config(<<"doc_created">>),[])),
    ?assertEqual(1,d(pending_slots)),clear(),
    meck:expect(acdc_queues_sup,find_queue_supervisor,fun(_,_)->self() end),
    meck:expect(acdc_queue_sup,stop,fun(_)->?assertEqual([],pending()),ok end),
    ?assertEqual(ok,acdc_queue_handler:handle_config_change(config(<<"doc_deleted">>),[])),
    ?assertEqual(1,d(pending_slots)),clear(),
    meck:expect(kz_datamgr,open_doc,fun(_,_)->{ok,kz_json:new()} end),
    meck:expect(acdc_queue_sup,workers_sup,fun(P)->P end),
    meck:expect(acdc_queue_workers_sup,workers,fun(_)->[] end),
    meck:expect(acdc_queue_sup,manager,fun(P)->P end),
    meck:expect(acdc_queue_manager,refresh,fun(_,_)->?assertEqual([],pending()),ok end),
    ?assertEqual(ok,acdc_queue_handler:handle_config_change(config(<<"doc_edited">>),[])),
    ?assertEqual(1,d(pending_slots))
end).

config_failure() -> with_tables(fun(_,_) ->
    meck:expect(acdc_queues_sup,find_queue_supervisor,fun(_,_)->undefined end),
    meck:expect(acdc_queues_sup,new,fun(_,_)->{error,fixture_failure} end),
    ?assertEqual({error,fixture_failure},acdc_queue_handler:handle_config_change(config(<<"doc_created">>),[])),
    ?assertEqual([],pending()),
    meck:expect(acdc_queues_sup,new,fun(_,_)->error(fixture_failure) end),
    ?assertError(fixture_failure,acdc_queue_handler:handle_config_change(config(<<"doc_created">>),[])),
    ?assertEqual([],pending())
end).

config_rejection() -> with_tables(fun(_,_) ->
    [bounded_result(fun()->acdc_queue_handler:handle_config_change(Bad,[]) end,
                    {raised,error,{badmatch,false}}) ||
        Bad<-[kz_json:new(),[],undefined,42,[bad],{[bad]},{[{42,bad}]},
              kz_json:from_list([{<<"ID">>,?Q}])]],
    [bounded_result(fun()->kapi_acdc_dashboard_events:changed_v(Bad) end,{returned,false}) ||
        Bad<-[kz_json:new(),[],undefined,{[bad]}]],
    ?assertEqual([],pending())
end).

bounded_result(F,Expected) ->
    Parent=self(),Tag=make_ref(),
    {Pid,Ref}=spawn_monitor(fun()->
        Result=try {returned,F()} catch Class:Reason->{raised,Class,Reason} end,
        Parent!{Tag,Result}
    end),
    receive
        {Tag,Result}->
            receive {'DOWN',Ref,process,Pid,normal}->ok after 200->error(rejection_process_stuck) end,
            ?assertEqual(Expected,Result)
    after 200->
        exit(Pid,kill),
        receive {'DOWN',Ref,process,Pid,_}->ok after 200->ok end,
        error(malformed_validation_exceeded_200ms)
    end.

supervisor_contract() ->
    {ok,{{one_for_one,_,_},Children}}=acdc_stats_sup:init([]),
    Ids=[element(1,C) || C<-Children],
    ?assertEqual(1,length([X || X<-Ids,X=:=acdc_dashboard_events])),
    ?assert(lists:nth(3,Ids)=:=acdc_dashboard_events),
    ?assert(lists:nth(4,Ids)=:=acdc_stats),
    ?assertMatch({acdc_dashboard_events,{acdc_dashboard_events,start_link,[]},permanent,5000,worker,_},
        lists:keyfind(acdc_dashboard_events,1,Children)).

blocked_publisher() ->
    Parent=self(),
    meck:expect(kz_amqp_worker,cast,fun(_,_)->Parent!{blocked,self()},
        receive release_fixture->ok after 1500->error(block_deadline) end end),
    {ok,Pid}=acdc_dashboard_events:start_link(),unlink(Pid),
    try
        ok=acdc_dashboard_events:changed(?A,?Q),
        Worker=receive {blocked,W}->W after 1000->error(no_publisher) end,
        ?assertEqual(Pid,Worker),
        {message_queue_len,Before}=process_info(Pid,message_queue_len),
        [acdc_dashboard_events:changed(?A,hex(N)) || N<-lists:seq(1,2000)],
        {message_queue_len,After}=process_info(Pid,message_queue_len),
        ?assertEqual(Before,After),?assert(ets:info(?T,size)=<1025),
        %% No next timer is scheduled while the native call is blocked.
        receive {blocked,_}->error(second_inflight) after 20->ok end,
        Pid!release_fixture,
        ok=gen_server:stop(Pid,normal,1500)
    after
        case is_process_alive(Pid) of true->exit(Pid,kill);false->ok end
    end,
    ?assertEqual(false,d(available)).
