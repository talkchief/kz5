-module(acdc_stats_migration_tests).
-include_lib("eunit/include/eunit.hrl").
-include("acdc_stats.hrl").

record(N,Status) ->
    Call=integer_to_binary(N),
    #call_stat{id= <<Call/binary,"::q">>,call_id=Call,account_id= <<"a">>,queue_id= <<"q">>,
               entered_timestamp=63800000000,status=Status,is_archived=false,
               caller_id_name= <<"PRIVATE-FIXTURE-NAME">>,caller_id_number= <<"PRIVATE-FIXTURE-NUMBER">>}.
legacy(Record) -> list_to_tuple(lists:sublist(tuple_to_list(Record),18)).
table() -> ets:new(?MODULE,[set,protected,{keypos,#call_stat.id}]).
with_table(Fun) -> T=table(),try Fun(T) after ets:delete(T) end.
finish(State) ->
    case acdc_stats_migration:step(State) of
        {continue,Next} -> finish(Next);
        Result -> Result
    end.
phase(Phase,#{phase:=Phase}=State) -> State;
phase(Phase,State) -> {continue,Next}=acdc_stats_migration:step(State),phase(Phase,Next).

empty_and_current_tables_test() ->
    with_table(fun(T) ->
        {ok,S}=acdc_stats_migration:start(T,#{}),
        ?assertEqual({done,#{version=>1,layout=>19,records=>0,converted=>0,already_current=>0,verified=>true}},finish(S)),
        Current=(record(1,<<"waiting">>))#call_stat{dashboard_caller_id=
            {1,<<"Synthetic">>,undefined,<<"available">>,<<"unavailable">>}},
        true=ets:insert(T,Current), {ok,S2}=acdc_stats_migration:start(T,#{}),
        {done,R}=finish(S2), ?assertEqual(0,maps:get(converted,R)),
        ?assertEqual([Current],ets:lookup(T,Current#call_stat.id))
    end).

unarchived_active_and_all_original_fields_preserved_test() ->
    with_table(fun(T) ->
        Waiting=(record(1,<<"waiting">>))#call_stat{caller_priority=8,misses=[{arbitrary,preserved}],
            abandoned_reason= <<"unchanged">>},
        Handled=(record(2,<<"handled">>))#call_stat{handled_timestamp=63800000010,agent_id= <<"agent">>},
        Processed=(record(3,<<"processed">>))#call_stat{handled_timestamp=63800000010,
            processed_timestamp=63800000020,hung_up_by= <<"member">>},
        Expected=lists:sort([Waiting,Handled,Processed]),
        true=ets:insert(T,[legacy(R) || R<-Expected]),
        {ok,S}=acdc_stats_migration:start(T,#{batch_size=>1}),{done,Receipt}=finish(S),
        ?assertEqual(3,maps:get(converted,Receipt)),
        ?assertEqual(Expected,lists:sort(ets:tab2list(T))),
        [?assertEqual(false,R#call_stat.is_archived) || R<-ets:tab2list(T)]
    end).

preflight_unknown_layout_never_mutates_test() ->
    with_table(fun(T) ->
        Before=[legacy(record(1,<<"waiting">>)),legacy(record(2,<<"handled">>)),{unknown,<<"bad">>,payload}],
        true=ets:insert(T,Before),{ok,S}=acdc_stats_migration:start(T,#{batch_size=>1}),
        ?assertEqual({error,unsupported_layout},finish(S)),
        ?assertEqual(lists:sort(Before),lists:sort(ets:tab2list(T)))
    end).

wrong_tid_owner_and_source_properties_test() ->
    ?assertEqual({error,invalid_tid},acdc_stats_migration:start(?MODULE,#{})),
    T=table(),ets:delete(T),?assertEqual({error,source_changed},acdc_stats_migration:start(T,#{})),
    [?assertEqual({error,unsupported_table},begin
        Bad=ets:new(?MODULE,Opts),try acdc_stats_migration:start(Bad,#{}) after ets:delete(Bad) end
    end) || Opts<-[[set,public,{keypos,2}],[set,private,{keypos,2}],
                  [ordered_set,protected,{keypos,2}],[set,protected,{keypos,1}]]],
    with_table(fun(Owned) ->
        {ok,State}=acdc_stats_migration:start(Owned,#{}),Parent=self(),
        {Pid,Ref}=spawn_monitor(fun() -> Parent!{self(),acdc_stats_migration:start(Owned,#{}),
                                                       acdc_stats_migration:step(State)} end),
        receive {Pid,A,B} -> ?assertEqual({error,wrong_owner},A),?assertEqual({error,wrong_owner},B)
        after 1000 -> error(owner_result_timeout) end,
        receive {'DOWN',Ref,process,Pid,normal} -> ok after 1000 -> error(owner_exit_timeout) end
    end).

bounded_options_and_preflight_record_limit_test() ->
    [?assertEqual({error,invalid_options},acdc_stats_migration:start(not_a_tid,Options)) ||
        Options<-[[],#{other=>1},#{batch_size=>0},#{batch_size=>257},#{deadline_ms=>0},
                  #{deadline_ms=>60001},#{max_records=>0},#{max_records=>100001}]],
    with_table(fun(T) ->
        Before=[legacy(record(1,<<"waiting">>)),legacy(record(2,<<"handled">>))],ets:insert(T,Before),
        ?assertEqual({error,record_limit},acdc_stats_migration:start(T,#{max_records=>1})),
        ?assertEqual(lists:sort(Before),lists:sort(ets:tab2list(T)))
    end).

preflight_deadline_no_mutation_test() ->
    with_table(fun(T) ->
        Before=legacy(record(1,<<"waiting">>)),ets:insert(T,Before),
        {ok,S}=acdc_stats_migration:start(T,#{deadline_ms=>1}),
        receive after 5 -> ok end,
        ?assertEqual({error,deadline},acdc_stats_migration:step(S)),
        ?assertEqual([Before],ets:tab2list(T))
    end).

interrupted_conversion_and_mixed_replay_test() ->
    with_table(fun(T) ->
        Current=(record(3,<<"waiting">>))#call_stat{dashboard_caller_id={1,undefined,undefined,<<"withheld">>,<<"withheld">>}},
        Expected=[record(1,<<"waiting">>),record(2,<<"handled">>),Current],
        ets:insert(T,[legacy(record(1,<<"waiting">>)),legacy(record(2,<<"handled">>)),Current]),
        {ok,S}=acdc_stats_migration:start(T,#{batch_size=>1}),
        Convert=phase(convert,S),{continue,Partial}=acdc_stats_migration:step(Convert),
        ?assertEqual(1,maps:get(count,Partial)),
        %% Discard a continuation, as after a supervised owner interruption.
        {ok,Retry}=acdc_stats_migration:start(T,#{batch_size=>1}),{done,_}=finish(Retry),
        ?assertEqual(lists:sort(Expected),lists:sort(ets:tab2list(T))),
        {ok,Again}=acdc_stats_migration:start(T,#{}),{done,Receipt}=finish(Again),
        ?assertEqual(0,maps:get(converted,Receipt)),?assertEqual(3,maps:get(already_current,Receipt))
    end).

verification_detects_owner_side_content_and_count_drift_test() ->
    with_table(fun(T) ->
        Original=record(1,<<"waiting">>),ets:insert(T,legacy(Original)),
        {ok,S}=acdc_stats_migration:start(T,#{}),Convert=phase(convert,S),
        Changed=Original#call_stat{caller_priority=9},ets:insert(T,legacy(Changed)),
        ?assertEqual({error,content_changed},finish(Convert)),
        ?assertEqual([Changed],ets:tab2list(T)),
        {ok,S2}=acdc_stats_migration:start(T,#{}),Convert2=phase(convert,S2),
        ets:insert(T,record(2,<<"waiting">>)),
        ?assertEqual({error,source_changed},finish(Convert2))
    end).

deleted_tid_is_never_reresolved_test() ->
    T=table(),{ok,S}=acdc_stats_migration:start(T,#{}),ets:delete(T),
    with_table(fun(New) ->
        Before=legacy(record(1,<<"waiting">>)),ets:insert(New,Before),
        ?assertEqual({error,source_changed},acdc_stats_migration:step(S)),
        ?assertEqual([Before],ets:tab2list(New))
    end).

actual_heir_transfer_and_resumption_test() ->
    Parent=self(),{Pid,Ref}=spawn_monitor(fun() ->
        T=ets:new(?MODULE,[set,protected,{keypos,2},{heir,Parent,migration_fixture}]),
        ets:insert(T,[legacy(record(1,<<"waiting">>)),legacy(record(2,<<"handled">>))]),
        {ok,S}=acdc_stats_migration:start(T,#{batch_size=>1}),
        Convert=phase(convert,S),{continue,Partial}=acdc_stats_migration:step(Convert),
        Parent!{migration_partial,self(),T,Partial}
    end),
    receive {migration_partial,Pid,T,OldState} ->
        receive {'ETS-TRANSFER',T,Pid,migration_fixture} -> ok after 1000 -> error(transfer_timeout) end,
        try
            ?assertEqual(self(),ets:info(T,owner)),
            ?assertEqual({error,wrong_owner},acdc_stats_migration:step(OldState)),
            {ok,NewState}=acdc_stats_migration:start(T,#{batch_size=>1}),{done,R}=finish(NewState),
            ?assertEqual(1,maps:get(converted,R)),?assertEqual(1,maps:get(already_current,R)),
            ?assertEqual(lists:sort([record(1,<<"waiting">>),record(2,<<"handled">>)]),lists:sort(ets:tab2list(T)))
        after ets:delete(T) end
    after 1000 -> error(partial_timeout) end,
    receive {'DOWN',Ref,process,Pid,normal} -> ok after 1000 -> error(heir_exit_timeout) end.

legacy_native_record_selection_and_update_failure_test() ->
    with_table(fun(T) ->
        Current=record(1,<<"waiting">>),ets:insert(T,legacy(Current)),
        Match=[{#call_stat{id='_',_='_'},[],['$_']}],
        ?assertEqual([],ets:select(T,Match)),
        ?assertError(badarg,ets:update_element(T,Current#call_stat.id,{#call_stat.dashboard_caller_id,undefined})),
        {ok,S}=acdc_stats_migration:start(T,#{}),{done,_}=finish(S),
        ?assertEqual([Current],ets:select(T,Match)),
        ?assertEqual(true,ets:update_element(T,Current#call_stat.id,{#call_stat.dashboard_caller_id,undefined}))
    end).
