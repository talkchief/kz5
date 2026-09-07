-module(acdc_stats_upgrade_drain_tests).
-include_lib("eunit/include/eunit.hrl").
-export([init/1,start_keeper/2,start_idle/0,handle_call/3,handle_cast/2,handle_info/2,terminate/2]).

%% Real OTP supervisor child-ID lookup and unregistered gen_server keepers.
%% Keeper callbacks are controlled fixtures, not a claim that the complete
%% kazoo_etsmgr find-me/heir lifecycle is exercised by this focused suite.
init(supervisor_fixture) ->
    Children=[{Name,{?MODULE,start_keeper,[Name,Type]},permanent,500,worker,[?MODULE]} ||
        {Name,Type}<-[{acdc_stats_call,set},{acdc_stats_status,ordered_set}]],
    {ok,{{one_for_one,1,5},Children++[{acdc_stats,{?MODULE,start_idle,[]},permanent,500,worker,[?MODULE]}]}};
init(idle) -> {ok,idle};
init({keeper,Name,Type}) ->
    Name=ets:new(Name,[named_table,Type,protected,{keypos,2}]),
    ets:insert(Name,{fixture,<<"retained">>,unarchived}),{ok,{Name,Type}}.
start_keeper(Name,Type) -> gen_server:start_link(?MODULE,{keeper,Name,Type},[]).
start_idle() -> gen_server:start_link(?MODULE,idle,[]).
handle_call(tid,_,State={Name,_}) -> {reply,ets:whereis(Name),State};
handle_call(_,_,State) -> {reply,{error,unsupported},State}.
handle_cast(_,State) -> {noreply,State}.
handle_info({replace,Parent},State={Name,Type}) ->
    ets:delete(Name),Name=ets:new(Name,[named_table,Type,protected,{keypos,2}]),
    Parent!{replaced,self()},{noreply,State};
handle_info({transfer,Parent},State={Name,_}) ->
    ets:give_away(Name,Parent,fixture),{noreply,State};
handle_info(_,State) -> {noreply,State}.
terminate(_,_) -> ok.
with_sources(Fun) ->
    {ok,Sup}=supervisor:start_link({local,acdc_stats_sup},?MODULE,supervisor_fixture),
    unlink(Sup),Ref=monitor(process,Sup),
    Children=supervisor:which_children(Sup),
    {acdc_stats_call,CP,worker,_}=lists:keyfind(acdc_stats_call,1,Children),
    {acdc_stats_status,SP,worker,_}=lists:keyfind(acdc_stats_status,1,Children),
    {acdc_stats,Old,worker,_}=lists:keyfind(acdc_stats,1,Children),
    OldRef=monitor(process,Old),ok=supervisor:terminate_child(Sup,acdc_stats),
    receive {'DOWN',OldRef,process,Old,_}->ok after 1000->error(old_down_timeout) end,
    C=gen_server:call(CP,tid),S=gen_server:call(SP,tid),
    try
        ?assertEqual(undefined,whereis(acdc_stats_call)),
        ?assertEqual(undefined,whereis(acdc_stats_status)),
        Fun(Old,{C,CP},{S,SP})
    after
        gen_server:stop(Sup,normal,2000),
        receive {'DOWN',Ref,process,Sup,normal}->ok after 1000->error(supervisor_stop_timeout) end,
        [case ets:whereis(Name) of
             undefined->ok;
             Tid->case ets:info(Tid,owner)=:=self() of true->ets:delete(Tid);false->ok end
         end || Name<-[acdc_stats_call,acdc_stats_status]]
    end.
scanned(#{phase:=wait}=S)->S;
scanned(S)->{continue,N}=acdc_stats_upgrade_drain:step(S),scanned(N).
finish(S)->
    case acdc_stats_upgrade_drain:step(S) of
        {continue,N}->receive after 1->ok end,finish(N);
        Result->Result
    end.

empty_cohort_preserves_sources_test() ->
    with_sources(fun(Old,C={CT,_},S={ST,_})->
        Before={ets:tab2list(CT),ets:tab2list(ST)},
        {ok,D}=acdc_stats_upgrade_drain:start(Old,C,S,#{}),{done,R}=finish(D),
        ?assertEqual(true,maps:get(verified,R)),?assertEqual(0,maps:get(captured,R)),
        ?assertEqual(Before,{ets:tab2list(CT),ets:tab2list(ST)})
    end).

alive_old_and_invalid_sources_refused_test() ->
    with_sources(fun(Old,C={CT,CP},S)->
        ?assertEqual({error,old_worker_alive},acdc_stats_upgrade_drain:start(self(),C,S,#{})),
        ?assertEqual({error,invalid_sources},acdc_stats_upgrade_drain:start(Old,{acdc_stats_call,CP},S,#{})),
        ?assertEqual({error,invalid_sources},acdc_stats_upgrade_drain:start(Old,{CT,Old},S,#{})),
        ?assertEqual({error,invalid_sources},acdc_stats_upgrade_drain:start(Old,C,C,#{})),
        ?assertEqual({error,retained_source_changed},acdc_stats_upgrade_drain:start(Old,{CT,self()},S,#{}))
    end).

bounded_options_and_process_cap_test() ->
    [?assertEqual({error,invalid_options},acdc_stats_upgrade_drain:start(not_pid,none,none,O)) ||
        O<-[[],#{extra=>true},#{batch_size=>0},#{batch_size=>257},#{deadline_ms=>0},
            #{deadline_ms=>60001},#{max_processes=>10001},#{max_cohort=>1001}]],
    with_sources(fun(Old,C,S)->
        ?assertEqual({error,process_limit},acdc_stats_upgrade_drain:start(Old,C,S,#{max_processes=>1}))
    end).

%% Actual production kz_process wrapper is held BEFORE it sets application
%% metadata and before the supplied callback/local fun is invoked. kz_log is
%% only the scheduling seam; no consumer metadata or purge is used by drain.
with_paused(Count,Fun) ->
    Parent=self(),meck:new(kz_log,[non_strict,no_link]),
    meck:expect(kz_log,get_callid,fun()-><<"synthetic">> end),
    meck:expect(kz_log,put_callid,fun(_)->Parent!{paused,self()},receive release->ok end end),
    Workers=[kz_process:spawn(fun()->
        put('$kz_amqp_consumer_pid',Parent),Parent!{invoked,self()},receive finish->ok end
    end) || _<-lists:seq(1,Count)],
    Refs=[{P,monitor(process,P)} || P<-Workers],
    try
        [receive {paused,P}->ok after 1000->error(pause_timeout) end || P<-Workers],
        Fun(Workers)
    after
        [begin P!release,P!finish,receive {'DOWN',R,process,P,_}->ok after 1000->error(worker_stop_timeout) end end || {P,R}<-Refs],
        meck:unload(kz_log),
        [receive {invoked,P}->ok after 0->ok end || P<-Workers]
    end.

paused_wrapper_needs_actual_down_not_metadata_test() ->
    with_sources(fun(Old,C,S)->with_paused(1,fun([P])->
        {dictionary,Dictionary}=process_info(P,dictionary),
        ?assertEqual(undefined,proplists:get_value('$kz_amqp_consumer_pid',Dictionary)),
        {ok,D}=acdc_stats_upgrade_drain:start(Old,C,S,#{}),Waiting=scanned(D),
        ?assertEqual(1,maps:get(captured,Waiting)),
        {continue,Still}=acdc_stats_upgrade_drain:step(Waiting),
        ?assertEqual(0,maps:get(down,Still)),
        P!release,receive {invoked,P}->ok after 1000->error(invoke_timeout) end,
        {continue,Running}=acdc_stats_upgrade_drain:step(Still),
        ?assertEqual(0,maps:get(down,Running)),
        P!finish,{done,R}=finish(Running),
        ?assertEqual(1,maps:get(captured,R)),?assertEqual(1,maps:get(down,R))
    end) end).

cohort_overflow_cleans_own_monitors_test() ->
    with_sources(fun(Old,C,S)->with_paused(2,fun(_)->
        {monitors,Before}=process_info(self(),monitors),
        {ok,D}=acdc_stats_upgrade_drain:start(Old,C,S,#{max_cohort=>1}),
        ?assertEqual({error,cohort_limit},finish(D)),
        {monitors,After}=process_info(self(),monitors),?assertEqual(lists:sort(Before),lists:sort(After))
    end) end).

cancel_and_deadline_leave_workers_and_other_monitors_test() ->
    with_sources(fun(Old,C,S)->with_paused(1,fun([P])->
        {monitors,Before}=process_info(self(),monitors),
        {ok,D}=acdc_stats_upgrade_drain:start(Old,C,S,#{}),Waiting=scanned(D),
        ?assertEqual(ok,acdc_stats_upgrade_drain:cancel(Waiting)),
        {monitors,AfterCancel}=process_info(self(),monitors),
        ?assertEqual(lists:sort(Before),lists:sort(AfterCancel)),?assert(is_process_alive(P)),
        {ok,Expiring}=acdc_stats_upgrade_drain:start(Old,C,S,#{deadline_ms=>1000}),
        ExpiringWait=scanned(Expiring),?assertEqual(1,maps:get(captured,ExpiringWait)),
        receive after 1005->ok end,
        ?assertEqual({error,deadline},acdc_stats_upgrade_drain:step(ExpiringWait)),
        {monitors,AfterDeadline}=process_info(self(),monitors),
        ?assertEqual(lists:sort(Before),lists:sort(AfterDeadline)),
        ?assert(is_process_alive(P))
    end) end).

replacement_tid_and_transferred_owner_refused_test() ->
    with_sources(fun(Old,C={_,CP},S={_,SP})->
        {ok,D}=acdc_stats_upgrade_drain:start(Old,C,S,#{}),
        CP!{replace,self()},receive {replaced,CP}->ok after 1000->error(replacement_timeout) end,
        ?assertEqual({error,retained_source_changed},acdc_stats_upgrade_drain:step(D)),
        C2={ets:whereis(acdc_stats_call),CP},
        {ok,D2}=acdc_stats_upgrade_drain:start(Old,C2,S,#{}),
        SP!{transfer,self()},receive {'ETS-TRANSFER',_,SP,fixture}->ok after 1000->error(transfer_timeout) end,
        ?assertEqual({error,retained_source_changed},acdc_stats_upgrade_drain:step(D2))
    end).

foreign_continuation_cannot_cancel_owner_monitors_test() ->
    with_sources(fun(Old,C,S)->
        {ok,D}=acdc_stats_upgrade_drain:start(Old,C,S,#{}),Parent=self(),
        {P,R}=spawn_monitor(fun()->Parent!{foreign,self(),acdc_stats_upgrade_drain:step(D),
                                                          acdc_stats_upgrade_drain:cancel(D)} end),
        receive {foreign,P,A,B}->?assertEqual({error,invalid_owner_state},A),?assertEqual(A,B)
        after 1000->error(foreign_timeout) end,
        receive {'DOWN',R,process,P,normal}->ok after 1000->error(foreign_exit_timeout) end
    end).

caller_inside_conservative_cohort_is_not_silently_excluded_test() ->
    with_sources(fun(Old,C,S)->
        Parent=self(),meck:new(kz_log,[non_strict,no_link]),
        meck:expect(kz_log,get_callid,fun()-><<"synthetic">> end),
        meck:expect(kz_log,put_callid,fun(_)->ok end),
        P=kz_process:spawn(fun()->
            {ok,D}=acdc_stats_upgrade_drain:start(Old,C,S,#{}),
            Parent!{self_refusal,self(),finish(D)}
        end),Ref=monitor(process,P),
        try
            receive {self_refusal,P,Result}->?assertEqual({error,caller_in_cohort},Result)
            after 1000->error(self_refusal_timeout) end,
            receive {'DOWN',Ref,process,P,normal}->ok after 1000->error(self_refusal_exit_timeout) end
        after meck:unload(kz_log) end
    end).

malformed_continuation_cleans_registered_monitors_test() ->
    ?assertEqual({error,invalid_state},acdc_stats_upgrade_drain:step(#{owner=>self()})),
    ?assertEqual({error,invalid_state},acdc_stats_upgrade_drain:cancel(#{owner=>self()})),
    with_sources(fun(Old,C,S)->with_paused(1,fun([P])->
        {monitors,Before}=process_info(self(),monitors),
        {ok,D}=acdc_stats_upgrade_drain:start(Old,C,S,#{}),Waiting=scanned(D),
        %% Corrupt fields cannot bypass the registered last-issued state or
        %% hide its real monitor references from cleanup.
        Bad=Waiting#{monitors:=broken,pending:=[],deadline:=not_an_integer},
        ?assertEqual({error,invalid_state},acdc_stats_upgrade_drain:step(Bad)),
        {monitors,After}=process_info(self(),monitors),
        ?assertEqual(lists:sort(Before),lists:sort(After)),?assert(is_process_alive(P)),
        ?assertEqual(ok,acdc_stats_upgrade_drain:cancel(Waiting)),
        ?assertEqual({error,invalid_state},acdc_stats_upgrade_drain:step(Waiting))
    end) end).

supervisor_incarnation_and_mapping_required_test() ->
    with_sources(fun(Old,C,S)->
        {ok,D}=acdc_stats_upgrade_drain:start(Old,C,S,#{}),
        Sup=whereis(acdc_stats_sup),true=unregister(acdc_stats_sup),
        try
            ?assertEqual({error,retained_source_changed},acdc_stats_upgrade_drain:step(D)),
            ?assertEqual({error,retained_source_changed},acdc_stats_upgrade_drain:start(Old,C,S,#{}))
        after true=register(acdc_stats_sup,Sup) end,
        ?assertEqual({error,retained_source_changed},acdc_stats_upgrade_drain:start(Old,S,C,#{}))
    end).

stopped_stats_child_spec_is_required_test() ->
    with_sources(fun(Old,C,S)->
        {ok,D}=acdc_stats_upgrade_drain:start(Old,C,S,#{}),
        Sup=whereis(acdc_stats_sup),{ok,New}=supervisor:restart_child(Sup,acdc_stats),
        ?assert(is_process_alive(New)),
        ?assertEqual({error,retained_source_changed},acdc_stats_upgrade_drain:step(D)),
        ?assertEqual({error,retained_source_changed},acdc_stats_upgrade_drain:start(Old,C,S,#{})),
        ok=supervisor:terminate_child(Sup,acdc_stats),ok=supervisor:delete_child(Sup,acdc_stats),
        ?assertEqual({error,retained_source_changed},acdc_stats_upgrade_drain:start(Old,C,S,#{}))
    end).
