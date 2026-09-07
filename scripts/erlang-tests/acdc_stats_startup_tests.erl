%%% Production callbacks, real gen_listener and real owner-local ETS migration.
%%% Only external broker/config/monitor/archive scheduling dependencies are
%%% controlled. No copied acdc_stats/gen_listener state records or TEST exports.
-module(acdc_stats_startup_tests).
-include_lib("eunit/include/eunit.hrl").
-include("acdc_stats.hrl").
-define(A, <<"11111111111111111111111111111111">>).
-define(Q, <<"22222222222222222222222222222222">>).
-define(COUNTS, acdc_stats_startup_fixture_counts).

startup_test_() -> {timeout,90,{setup,fun setup/0,fun teardown/1,fun(_)->[
    {"init has only bounded startup timer and rejects all pre-ready work",wrap(fun initial_closed/0)},
    {"real ETS transfers in either order precede any listener activation",wrap(fun both_orders/0)},
    {"foreign, stale and not-owned transfer claims do not open admission",wrap(fun wrong_transfers/0)},
    {"multi-step actual legacy migration preserves all fields before activation",wrap(fun batched_migration/0)},
    {"unsupported retained layout fails closed without changing records",wrap(fun bad_layout/0)},
    {"table reincarnation during migration fails and preserves replacement",wrap(fun table_changed/0)},
    {"matching migration timeout fails; stale timeout after ready is ignored",wrap(fun timeout_tokens/0)},
    {"nonready termination never archives and legacy code_change is refused",wrap(fun termination_and_upgrade/0)},
    {"OTP status formatting excludes continuation and private dictionary",wrap(fun status_redaction/0)},
    {"direct lookups reject missing and legacy stats owners",wrap(fun read_unavailable/0)},
    {"unresponsive read admission has a bounded timeout",wrap(fun read_timeout/0)},
    {"direct lookup discards a result when its table is replaced",wrap(fun read_replaced/0)},
    {"second admission refusal with the same owner and tid withholds JSON",wrap(fun()->read_revoked(refused) end)},
    {"second admission timeout with the same owner and tid withholds JSON",wrap(fun()->read_revoked(timeout) end)},
    {"ready source admission refuses replacement table identities",wrap(fun ready_read_source/0)},
    {"installer readiness requires matching admission, consumption and current worker",wrap(fun maintenance_readiness/0)},
    {"actual gen_listener defers responder/channel setup until real migration",wrap(fun native_listener/0)}
] end}}.

setup() ->
    T=ets:new(?COUNTS,[named_table,public,set]),
    Modules=[kz_datamgr,kapps_config,acdc_dashboard_events,kz_process,kz_monitor,
             kz_amqp_channel,kz_amqp_assignments,acdc_stats_sup,kz_amqp_worker],
    meck:new(Modules,[non_strict,no_link]),
    meck:expect(kz_datamgr,suppress_change_notice,fun()->bump(suppress),ok end),
    meck:expect(kapps_config,get_integer,fun(_,Key,Default)->bump({config,Key}),Default end),
    meck:expect(acdc_dashboard_events,changed,fun(_,_) -> bump(changed),ok end),
    meck:expect(acdc_dashboard_events,bulk_removed,fun(_) -> bump(changed),ok end),
    meck:expect(kz_process,get_application,fun()->acdc end),
    meck:expect(kz_process,put_application,fun(_)->acdc end),
    meck:expect(kz_process,spawn,fun(_,_) -> bump(archive_spawn),error(forbidden_archive_spawn) end),
    meck:expect(kz_process,spawn_monitor,fun(_) -> bump(archive_spawn),error(forbidden_archive_spawn) end),
    meck:expect(kz_monitor,track_me,fun()->ok end),
    meck:expect(kz_monitor,track_me,fun(_)->ok end),
    meck:expect(kz_amqp_channel,has_channel,fun()->false end),
    meck:expect(kz_amqp_channel,consumer_pid,fun()->self() end),
    meck:expect(kz_amqp_channel,requisition,fun()->bump(channel),false end),
    meck:expect(kz_amqp_assignments,release_consumer,fun(_)->ok end),
    meck:expect(acdc_stats_sup,stats_srv,fun()->{error,not_found} end),
    meck:expect(kz_amqp_worker,cast,fun(_,_) -> bump(forbidden_publish),error(forbidden_publish) end),
    {T,Modules}.
teardown({T,Modules}) -> meck:unload(Modules),ets:delete(T).
bump(K) -> ets:update_counter(?COUNTS,K,1,{K,0}).
count(K) -> case ets:lookup(?COUNTS,K) of [{_,N}]->N; []->0 end.
reset_counts() -> ets:delete_all_objects(?COUNTS).
wrap(F) -> {timeout,15,fun() ->
    ?assertEqual(undefined,ets:whereis(acdc_stats:call_table_id())),
    ?assertEqual(undefined,ets:whereis(acdc_agent_stats:status_table_id())),
    reset_counts(),put(startup_test_refs,[]),put(startup_test_children,[]),
    try F()
    after
        [exit(P,kill) || P<-get(startup_test_children),is_process_alive(P)],
        [erlang:cancel_timer(R) || R<-get(startup_test_refs)],
        delete_owned(acdc_stats:call_table_id()),delete_owned(acdc_agent_stats:status_table_id()),
        drain(),erase(startup_test_refs),erase(startup_test_children)
    end
end}.
delete_owned(Name) ->
    case ets:whereis(Name) of
        undefined->ok;
        Tid->case ets:info(Tid,owner) of Owner when Owner=:=self()->ets:delete(Tid); _->ok end
    end.
drain() -> receive
    {stats_migration_step,_}->drain(); {stats_startup_timeout,_}->drain();
    {'$gen_cast',_}->drain(); {'ETS-TRANSFER',_,_,startup_fixture}->drain();
    {'DOWN',_,process,_,_}->drain()
after 0->ok end.
refs(R) when is_reference(R)->[R];
refs(T) when is_tuple(T)->lists:append([refs(V)||V<-tuple_to_list(T)]);
refs(M) when is_map(M)->lists:append([refs(V)||V<-maps:values(M)]);
refs(L) when is_list(L)->lists:append([refs(V)||V<-L]);
refs(_)->[].
remember(S)->put(startup_test_refs,lists:usort(refs(S)++get(startup_test_refs))),S.
timers(S)->[{R,N} || R<-refs(S),N<-[erlang:read_timer(R)],is_integer(N)].
initial()->{ok,S}=acdc_stats:init([]),remember(S).
readiness(S)->{reply,R,S}=acdc_stats:handle_call(stats_readiness,{self(),make_ref()},S),
    ?assertEqual([phase,reason],lists:sort(maps:keys(R))),R.
phase(S,P)->?assertEqual(P,maps:get(phase,readiness(S))).
info(Msg,S)->{noreply,N}=acdc_stats:handle_info(Msg,S),remember(N).
cast(Msg,S)->{noreply,N}=acdc_stats:handle_cast(Msg,S),remember(N).
no_activation()->
    ?assertEqual(0,count({config,<<"archive_period_ms">>})),
    ?assertEqual(0,count({config,<<"cleanup_period_ms">>})),
    ?assertEqual(0,count(archive_spawn)),?assertEqual(0,count(channel)),
    receive {'$gen_cast',{start_listener,_}}->error(early_listener_activation) after 0->ok end.
record(I)->#call_stat{id=integer_to_binary(I),call_id=integer_to_binary(I),account_id=?A,queue_id=?Q,
    entered_timestamp=63800000000+I,status= <<"waiting">>,
    misses=[#agent_miss{agent_id= <<"preserved-agent">>,miss_reason= <<"preserved-reason">>,miss_timestamp=63800000000}],
    caller_id_name= <<"PRIVATE-RAW-CALLER">>,caller_id_number= <<"PRIVATE-NUMBER">>,
    caller_priority=I,is_archived=true}.
legacy(R)->list_to_tuple(lists:sublist(tuple_to_list(R),18)).
status()->#status_stat{key=#status_stat_key{account_id=?A,agent_id= <<"fixture-agent">>,timestamp=63800000000},
    id= <<"fixture-status">>,status= <<"ready">>,is_archived=true}.
options(call)->{acdc_stats:call_table_id(),acdc_stats:call_table_opts()};
options(status)->{acdc_agent_stats:status_table_id(),acdc_agent_stats:status_table_opts()}.
donate(Kind,Rows,Recipient)->
    Parent=self(),{Name,Opts}=options(Kind),
    {Pid,Ref}=spawn_monitor(fun()->
        Name=ets:new(Name,Opts++[{heir,Parent,startup_fixture}]),Tid=ets:whereis(Name),
        ets:insert(Tid,Rows),true=ets:give_away(Tid,Recipient,startup_fixture),
        Parent!{startup_donated,self(),Tid}
    end),
    receive {startup_donated,Pid,Tid}->
        receive {'DOWN',Ref,process,Pid,normal}->ok after 1000->error(donor_exit_timeout) end,
        case Recipient=:=self() of
            true->receive {'ETS-TRANSFER',Name,Pid,startup_fixture}=Transfer->
                      ?assertEqual(Tid,ets:whereis(Name)),{Tid,Transfer}
                  after 1000->error(table_transfer_timeout) end;
            false->{Tid,Pid}
        end
    after 1000->error(donor_timeout) end.
tables(Rows)->{Call,CM}=donate(call,Rows,self()),{Status,SM}=donate(status,[status()],self()),
    {Call,Status,CM,SM}.
migrating(Rows)->{C,T,CM,SM}=tables(Rows),S=info(SM,info(CM,initial())),phase(S,migrating),{C,T,S}.
next_step()->receive {stats_migration_step,Token}=Step->{Token,Step} after 1000->error(step_missing) end.
finish(S)->finish(S,0).
finish(S,N) when N<100 ->
    case maps:get(phase,readiness(S)) of
        migrating->no_activation(),{Token,Step}=next_step(),
            ?assertEqual(S,info({stats_migration_step,make_ref()},S)),
            finish(info(Step,S),N+1,Token);
        P->error({unexpected_finish_phase,P})
    end.
finish(S,N,Token)->
    case maps:get(phase,readiness(S)) of
        migrating->finish(S,N);
        ready->{S,N,Token};
        failed->{S,N,Token}
    end.
activation()->
    Params=receive {'$gen_cast',{start_listener,P}}->P after 1000->error(listener_missing) end,
    ?assertEqual([{self,[]},{acdc_stats,[]},{acdc_dashboard,[federate]}],props:get_value(bindings,Params)),
    ?assertEqual(<<>>,props:get_value(queue_name,Params)),
    ?assert(lists:keymember({acdc_dashboard_snapshot,handle_req},1,props:get_value(responders,Params))),
    ?assertEqual(1,count({config,<<"archive_period_ms">>})),
    ?assertEqual(1,count({config,<<"cleanup_period_ms">>})),Params.
closed_work(S,C,T)->
    Before={lists:sort(ets:tab2list(C)),ets:tab2list(T)},R=record(1000),St=status(),
    ?assertEqual(ignore,acdc_stats:handle_event(kz_json:new(),S)),
    ?assertEqual({reply,{error,source_unavailable},S},
                 acdc_stats:handle_call(stats_call_read_source,{self(),make_ref()},S)),
    Messages=[{create_call,R},{update_call,<<"1">>,[{#call_stat.caller_priority,99}]},
        {flush_call,<<"1">>},{remove_call,[{'_',[],['$_']}]},
        {create_status,St#status_stat{id= <<"changed">>}},{update_status,St#status_stat.key,[{#status_stat.status,<<"paused">>}]},
        {remove_status,[{'_',[],['$_']}]},{archive_call_saved,record(1)},{archive_status_saved,St}],
    [?assertEqual(S,cast(M,S))||M<-Messages],
    ?assertEqual(S,info(?ARCHIVE_MSG,S)),?assertEqual(S,info(?CLEANUP_MSG,S)),
    ?assertEqual(Before,{lists:sort(ets:tab2list(C)),ets:tab2list(T)}),
    ?assertEqual(0,count(changed)),no_activation().

initial_closed()->
    {C,T,_,_}=tables([legacy(record(1))]),S=initial(),phase(S,waiting_tables),
    ?assertEqual(undefined,maps:get(reason,readiness(S))),
    [{_,Remaining}]=timers(S),?assert(Remaining>25000 andalso Remaining=<30000),
    closed_work(S,C,T),?assertEqual(S,info({stats_startup_timeout,make_ref()},S)).
both_orders()->
    [begin reset_counts(),{C,T,CM,SM}=tables([]),S=initial(),
        {First,Last}=case Order of call_first->{CM,SM}; status_first->{SM,CM} end,
        One=info(First,S),phase(One,waiting_tables),no_activation(),
        ?assertEqual(One,info(First,One)),
        Two=info(Last,One),phase(Two,migrating),no_activation(),
        {Ready,Steps,_}=finish(Two),phase(Ready,ready),?assertEqual(3,Steps),activation(),
        ?assertEqual({reply,[]},acdc_stats:handle_event(kz_json:new(),Ready)),
        ?assertEqual(2,length(timers(Ready))),
        [erlang:cancel_timer(R)||{R,_}<-timers(Ready)],ets:delete(C),ets:delete(T)
     end||Order<-[call_first,status_first]].
wrong_transfers()->
    S=initial(),Foreign=ets:new(startup_foreign,[set,protected]),
    try ?assertEqual(S,info({'ETS-TRANSFER',Foreign,self(),ok},S)) after ets:delete(Foreign) end,
    {C,_CM}=donate(call,[legacy(record(1))],self()),ets:delete(C),
    {New,NewCM}=donate(call,[legacy(record(1))],self()),
    %% A stale opaque incarnation cannot substitute a new owned table. A
    %% named transfer is resolved once and ownership/migration verified;
    %% the name alone does not attest the age of the transfer signal.
    ?assertNotEqual(C,New),?assertEqual(S,info({'ETS-TRANSFER',C,self(),startup_fixture},S)),
    Holder=spawn(fun()->receive {'ETS-TRANSFER',Tid,_,_}->receive {return_to,P}->ets:give_away(Tid,P,startup_fixture) end end end),
    put(startup_test_children,[Holder|get(startup_test_children)]),
    true=ets:give_away(New,Holder,startup_fixture),
    ?assertEqual(S,info(NewCM,S)),no_activation(),
    Holder!{return_to,self()},CallName=acdc_stats:call_table_id(),
    Back=receive {'ETS-TRANSFER',CallName,Holder,startup_fixture}=M->
             ?assertEqual(New,ets:whereis(CallName)),M after 1000->error(holder_timeout) end,
    One=info(Back,S),phase(One,waiting_tables),
    {_,SM}=donate(status,[status()],self()),{Ready,_,_}=finish(info(SM,One)),phase(Ready,ready),activation().
batched_migration()->
    Expected=[record(I)||I<-lists:seq(1,205)],Rows=[legacy(R)||R<-Expected]++[record(206)],
    {C,T,S}=migrating(Rows),closed_work(S,C,T),
    {Ready,Steps,_}=finish(S),phase(Ready,ready),?assert(Steps>3),activation(),
    ?assertEqual(lists:sort(Expected++[record(206)]),lists:sort(ets:tab2list(C))),
    ?assertEqual([status()],ets:tab2list(T)),
    ?assertEqual(0,count(changed)),
    Next=cast({update_call,<<"1">>,[{#call_stat.dashboard_caller_id,undefined}]},Ready),
    phase(Next,ready),?assertEqual(19,tuple_size(hd(ets:lookup(C,<<"1">>)))).
bad_layout()->
    Rows=[legacy(record(1)),{unknown,<<"bad">>,private_payload}],{C,T,S}=migrating(Rows),
    {Failed,_,Token}=finish(S),phase(Failed,failed),
    ?assertEqual(unsupported_layout,maps:get(reason,readiness(Failed))),
    ?assertEqual(lists:sort(Rows),lists:sort(ets:tab2list(C))),closed_work(Failed,C,T),
    ?assertEqual([],timers(Failed)),?assertEqual(Failed,info({stats_migration_step,Token},Failed)).
table_changed()->
    {C,T,S}=migrating([legacy(record(1))]),ets:delete(C),
    {New,_}=donate(call,[legacy(record(2))],self()),{_,Step}=next_step(),Failed=info(Step,S),
    phase(Failed,failed),?assertEqual(table_changed,maps:get(reason,readiness(Failed))),
    ?assertEqual([legacy(record(2))],ets:tab2list(New)),closed_work(Failed,New,T).
timeout_tokens()->
    {C,T,S}=migrating([legacy(record(1))]),{Token,Step}=next_step(),
    ?assertEqual(S,info({stats_startup_timeout,make_ref()},S)),
    Failed=info({stats_startup_timeout,Token},S),phase(Failed,failed),
    ?assertEqual(startup_timeout,maps:get(reason,readiness(Failed))),
    ?assertEqual(Failed,info(Step,Failed)),closed_work(Failed,C,T),
    ets:delete(C),ets:delete(T),reset_counts(),
    {_,_,Fresh}=migrating([]),{Ready,_,NewToken}=finish(Fresh),activation(),
    ?assertEqual(Ready,info({stats_startup_timeout,NewToken},Ready)),
    ?assertEqual(Ready,info({stats_startup_timeout,Token},Ready)),
    ?assertEqual(Ready,info({stats_migration_step,NewToken},Ready)).
termination_and_upgrade()->
    {C,T,CM,SM}=tables([legacy(record(1))]),Waiting=initial(),
    %% Direct client callback only. Native gen_listener:code_change/3 does
    %% not delegate to it; this is NOT a sys:change_code safety proof.
    ?assertEqual({ok,Waiting},acdc_stats:code_change(old,Waiting,extra)),
    [?assertEqual({error,restart_with_retained_tables_required},acdc_stats:code_change(old,Old,extra)) ||
        Old<-[{state,make_ref(),make_ref()},undefined,test_state]],
    ?assertEqual(ok,acdc_stats:terminate(shutdown,Waiting)),
    Migrating=info(SM,info(CM,initial())),{Token,_}=next_step(),
    ?assertEqual(ok,acdc_stats:terminate(shutdown,Migrating)),
    Failed=info({stats_startup_timeout,Token},Migrating),
    ?assertEqual(ok,acdc_stats:terminate(shutdown,Failed)),
    ?assertEqual([legacy(record(1))],ets:tab2list(C)),?assertEqual([status()],ets:tab2list(T)),no_activation().
status_redaction()->
    {_,_,S}=migrating([legacy(record(1))]),
    Expected=[{data,[{"Phase",migrating},{"Reason",undefined}]}],
    ?assertEqual(Expected,acdc_stats:format_status(normal,[[{secret,<<"PRIVATE-DICTIONARY">>}],S])),
    ?assertEqual(Expected,acdc_stats:format_status(terminate,[[],S])),
    ?assertEqual([{data,[{"Phase",unavailable}]}],acdc_stats:format_status(normal,[[],{legacy,private}])).
read_unavailable()->
    Unavailable={error,source_unavailable},
    meck:expect(acdc_stats_sup,stats_srv,fun()->{error,not_found} end),
    ?assertEqual(Unavailable,acdc_stats:find_call(<<"1">>)),
    ?assertEqual(Unavailable,acdc_maintenance:stats_ready()),
    ?assertEqual(ok,acdc_maintenance:flush_call_stat(<<"1">>)),
    ?assertEqual(0,count(changed)),
    ?assertEqual(0,count(forbidden_publish)),
    meck:expect(acdc_stats_sup,stats_srv,fun()->exit(noproc) end),
    ?assertEqual(Unavailable,acdc_stats:find_call(<<"1">>)),
    Pid=spawn(fun()->receive {'$gen_call',From,{'$client_call',stats_call_read_source}} ->
        gen_server:reply(From,ok) end end),
    Ref=monitor(process,Pid),put(startup_test_children,[Pid|get(startup_test_children)]),
    meck:expect(acdc_stats_sup,stats_srv,fun()->{ok,Pid} end),
    ?assertEqual(Unavailable,acdc_stats:find_call(<<"1">>)),
    receive {'DOWN',Ref,process,Pid,normal}->ok after 1000->error(legacy_reply_timeout) end,
    ?assertEqual(Unavailable,acdc_stats:find_call(<<"1">>)).
read_timeout()->
    Parent=self(),Pid=spawn(fun()->
        receive {'$gen_call',_,{'$client_call',stats_call_read_source}} ->
            Parent!{admission_request_received,self()},receive finish->ok end end
    end),
    Ref=monitor(process,Pid),put(startup_test_children,[Pid|get(startup_test_children)]),
    meck:expect(acdc_stats_sup,stats_srv,fun()->{ok,Pid} end),
    Started=erlang:monotonic_time(millisecond),
    ?assertEqual({error,source_unavailable},acdc_stats:find_call(<<"1">>)),
    Elapsed=erlang:monotonic_time(millisecond)-Started,
    ?assert(Elapsed>=900 andalso Elapsed<4000),
    receive {admission_request_received,Pid}->ok after 1000->error(admission_not_received) end,
    Pid!finish,receive {'DOWN',Ref,process,Pid,normal}->ok after 1000->error(reader_exit_timeout) end.
read_replaced()->
    Parent=self(),Pid=spawn(fun()->
        {Name,Opts}=options(call),Name=ets:new(Name,Opts),Tid=ets:whereis(Name),
        ets:insert(Tid,record(1)),
        receive {'$gen_call',First,{'$client_call',stats_call_read_source}} ->
            gen_server:reply(First,{ok,Tid}) end,
        receive {'$gen_call',Second,{'$client_call',stats_call_read_source}} ->
            %% Reaching this call means the first real ETS select completed.
            %% Keep the process alive and return the same old admission value:
            %% the client must still reject the replacement incarnation.
            ets:delete(Tid),Name=ets:new(Name,Opts),
            ets:insert(Name,record(2)),Parent!{read_completed_before_replacement,self()},
            gen_server:reply(Second,{ok,Tid}) end,
        receive finish->ok end
    end),
    Ref=monitor(process,Pid),put(startup_test_children,[Pid|get(startup_test_children)]),
    meck:expect(acdc_stats_sup,stats_srv,fun()->{ok,Pid} end),
    ?assertEqual({error,source_unavailable},acdc_stats:find_call(<<"1">>)),
    receive {read_completed_before_replacement,Pid}->ok after 1000->error(read_not_completed) end,
    ?assertEqual([record(2)],ets:tab2list(acdc_stats:call_table_id())),
    Pid!finish,receive {'DOWN',Ref,process,Pid,normal}->ok after 1000->error(reader_exit_timeout) end.
read_revoked(Mode)->
    Parent=self(),Pid=spawn(fun()->
        {Name,Opts}=options(call),Name=ets:new(Name,Opts),Tid=ets:whereis(Name),
        ets:insert(Tid,record(1)),
        receive {'$gen_call',First,{'$client_call',stats_call_read_source}} ->
            gen_server:reply(First,{ok,Tid}) end,
        receive {'$gen_call',Second,{'$client_call',stats_call_read_source}} ->
            Parent!{second_admission,self(),Tid},
            case Mode of
                refused->gen_server:reply(Second,{error,source_unavailable});
                timeout->ok
            end end,
        receive finish->ok end
    end),
    Ref=monitor(process,Pid),put(startup_test_children,[Pid|get(startup_test_children)]),
    meck:expect(acdc_stats_sup,stats_srv,fun()->{ok,Pid} end),
    ?assertEqual({error,source_unavailable},acdc_stats:find_call(<<"1">>)),
    Tid=receive {second_admission,Pid,T}->T after 1000->error(second_admission_missing) end,
    ?assertEqual(Tid,ets:whereis(acdc_stats:call_table_id())),
    ?assertEqual(Pid,ets:info(Tid,owner)),?assertEqual([record(1)],ets:tab2list(Tid)),
    Pid!finish,receive {'DOWN',Ref,process,Pid,normal}->ok after 1000->error(reader_exit_timeout) end.
ready_read_source()->
    {C,_,S}=migrating([legacy(record(1))]),{Ready,_,_}=finish(S),activation(),
    ?assertEqual({reply,{ok,C},Ready},
        acdc_stats:handle_call(stats_call_read_source,{self(),make_ref()},Ready)),
    ets:delete(C),{_,_}=donate(call,[record(2)],self()),
    ?assertEqual({reply,{error,source_unavailable},Ready},
        acdc_stats:handle_call(stats_call_read_source,{self(),make_ref()},Ready)).
maintenance_readiness()->
    Tid=make_ref(),Gate={'$client_call',stats_call_read_source},
    Unavailable={error,source_unavailable},
    Cases=[{[{Gate,{ok,Tid}},{is_consuming,true},{Gate,{ok,Tid}}],false,ready},
        {[{Gate,ok}],false,Unavailable},
        {[{Gate,{error,source_unavailable}}],false,Unavailable},
        {[{Gate,{ok,not_a_tid}}],false,Unavailable},
        {[{Gate,{ok,Tid}},{is_consuming,false}],false,{error,not_consuming}},
        {[{Gate,{ok,Tid}},{is_consuming,<<"true">>}],false,Unavailable},
        {[{Gate,{ok,Tid}},{is_consuming,true},{Gate,{error,source_unavailable}}],false,Unavailable},
        {[{Gate,{ok,Tid}},{is_consuming,true},{Gate,{ok,make_ref()}}],false,Unavailable},
        {[{Gate,{ok,Tid}},{is_consuming,true},{Gate,{ok,Tid}}],true,Unavailable}],
    [begin
        Parent=self(),Pid=spawn(fun()->readiness_protocol(Plan,Parent) end),
        Ref=monitor(process,Pid),put(startup_test_children,[Pid|get(startup_test_children)]),
        ets:delete(?COUNTS,readiness_sup),
        meck:expect(acdc_stats_sup,stats_srv,fun()->
            case bump(readiness_sup) of
                2 when Replace -> {ok,Parent};
                _ -> {ok,Pid}
            end end),
        ?assertEqual(Expected,acdc_maintenance:stats_ready()),
        receive {readiness_protocol_complete,Pid}->ok after 1000->error(readiness_protocol_incomplete) end,
        Pid!finish,receive {'DOWN',Ref,process,Pid,normal}->ok after 1000->error(readiness_owner_exit_timeout) end
    end||{Plan,Replace,Expected}<-Cases].
readiness_protocol([],Parent)->
    Parent!{readiness_protocol_complete,self()},receive finish->ok end;
readiness_protocol([{Request,Reply}|Rest],Parent)->
    receive {'$gen_call',From,Request}->gen_server:reply(From,Reply),readiness_protocol(Rest,Parent)
    after 2000->error(readiness_request_missing) end.
native_listener()->
    {ok,Pid}=acdc_stats:start_link(),unlink(Pid),Ref=monitor(process,Pid),
    put(startup_test_children,[Pid|get(startup_test_children)]),
    meck:expect(acdc_stats_sup,stats_srv,fun()->{ok,Pid} end),
    try
        ?assertEqual(#{phase=>waiting_tables,reason=>undefined},gen_listener:call(Pid,stats_readiness)),
        ?assertEqual({error,source_unavailable},acdc_maintenance:stats_ready()),
        ?assertEqual({error,source_unavailable},acdc_stats:find_call(<<"1">>)),
        ?assertEqual([],gen_listener:responders(Pid)),?assertEqual(undefined,gen_listener:queue_name(Pid)),
        ?assertEqual(false,gen_listener:is_consuming(Pid)),no_activation(),
        {C,_}=donate(call,[legacy(record(1))],Pid),
        ?assertEqual(#{phase=>waiting_tables,reason=>undefined},gen_listener:call(Pid,stats_readiness)),
        no_activation(),{T,_}=donate(status,[status()],Pid),
        wait_ready(Pid,erlang:monotonic_time(millisecond)+5000),
        ?assertEqual([record(1)],ets:tab2list(C)),?assertEqual([status()],ets:tab2list(T)),
        ?assertEqual(acdc_stats:call_stat_to_json(record(1)),acdc_stats:find_call(<<"1">>)),
        ?assertEqual(undefined,acdc_stats:find_call(<<"missing">>)),
        Newer=(record(2))#call_stat{call_id= <<"1">>},
        gen_listener:cast(Pid,{create_call,Newer}),
        ?assertEqual(acdc_stats:call_stat_to_json(Newer),acdc_stats:find_call(<<"1">>)),
        wait_responders(Pid,erlang:monotonic_time(millisecond)+1000),?assert(count(channel)>0),
        ?assertEqual(1,count({config,<<"archive_period_ms">>})),
        ?assertEqual(1,count({config,<<"cleanup_period_ms">>})),
        %% Requisition is controlled false: local readiness is not AMQP ACK.
        ?assertEqual(false,gen_listener:is_consuming(Pid)),
        ?assertEqual({error,not_consuming},acdc_maintenance:stats_ready()),
        exit(Pid,kill),receive {'DOWN',Ref,process,Pid,killed}->ok after 1000->error(listener_exit_timeout) end,
        [receive {'ETS-TRANSFER',Name,Pid,startup_fixture}->?assertEqual(Tid,ets:whereis(Name))
         after 1000->error(heir_return_timeout) end ||
            {Tid,Name}<-[{C,acdc_stats:call_table_id()},{T,acdc_agent_stats:status_table_id()}]],
        ?assertEqual(self(),ets:info(C,owner)),
        ?assertEqual(lists:sort([record(1),Newer]),lists:sort(ets:tab2list(C))),
        ?assertEqual({error,source_unavailable},acdc_stats:find_call(<<"1">>))
    after case is_process_alive(Pid) of true->exit(Pid,kill);false->ok end end.
wait_ready(Pid,Until)->
    case gen_listener:call(Pid,stats_readiness) of
        #{phase:=ready,reason:=undefined}->ok;
        #{phase:=Phase} when Phase=:=waiting_tables;Phase=:=migrating ->
            ?assert(erlang:monotonic_time(millisecond)<Until),
            receive after 1->ok end,wait_ready(Pid,Until);
        _->error(native_startup_failed)
    end.
wait_responders(Pid,Until)->
    case lists:keymember({<<"acdc_dashboard">>,<<"snapshot_req">>},1,gen_listener:responders(Pid)) of
        false->?assert(erlang:monotonic_time(millisecond)<Until),
            receive after 1->ok end,wait_responders(Pid,Until);
        true->ok
    end.
