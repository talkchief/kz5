-module(acdc_dashboard_collector_tests).
-include_lib("eunit/include/eunit.hrl").
-include("acdc_stats.hrl").

now_s() -> calendar:datetime_to_gregorian_seconds(calendar:universal_time()).
row(N, Account, Queue, Status, Entered) ->
    Call = integer_to_binary(N),
    #call_stat{id = <<Call/binary, "::", Queue/binary>>, call_id=Call,
               account_id=Account, queue_id=Queue, status=Status,
               entered_timestamp=Entered}.
waiting(N) -> row(N, <<"a">>, <<"q">>, <<"waiting">>, now_s()-20).
table() -> ets:new(?MODULE, [set, protected, {keypos, #call_stat.id}]).
with_table(F) -> T=table(), try F(T) after ets:delete(T) end.
collect(T, Options) ->
    Now=now_s(), acdc_dashboard_collector:collect(T, <<"a">>, [<<"q">>], Now-100, Now, Options).
source(R) -> maps:get(source, R).
queue(R) -> [Q]=maps:get(queues, R), Q.
metrics(R) -> maps:get(metrics, queue(R)).
active(R) -> maps:get(active_calls, R).
active_rows(R) -> maps:get(rows, active(R)).

complete_empty_local_is_not_cluster_complete_test() ->
    with_table(fun(T) ->
        {ok, R}=collect(T, #{}), S=source(R),
        ?assertEqual(0, maps:get(current_waiting, metrics(R))),
        ?assertEqual(undefined, maps:get(average_answered_wait_seconds, metrics(R))),
        ?assertEqual(local_table_only, maps:get(coverage, S)),
        ?assertEqual(false, maps:get(cluster_complete, S)),
        ?assertEqual(false, maps:get(atomic_snapshot, S)),
        ?assertEqual(unknown, maps:get(archive_coverage, S)),
        ?assertEqual(available, maps:get(availability, S)),
        ?assertEqual(0, maps:get(scan_keys, S)),
        ?assertEqual(exhausted, maps:get(completion_reason, S)),
        ?assertEqual(kazoo_gregorian_seconds, maps:get(timestamp_unit, R)),
        ?assertEqual(#{rows=>[],limit=>200,observed_count=>0,truncated=>false,
                       complete=>true,order=>queue_id_entered_call_id,
                       coverage=>local_table_only,atomic_snapshot=>false},active(R)),
        ?assertEqual(false, ets:info(T, safe_fixed))
    end).

scope_and_options_rejected_before_missing_source_test_() ->
    Now=now_s(), Missing=dashboard_collector_missing,
    [?_assertEqual({error, Why}, acdc_dashboard_collector:collect(Missing, A, Q, F, To, O)) ||
     {A,Q,F,To,O,Why} <- [
        {<<>>, [<<"q">>], Now-10, Now, #{}, invalid_projection_scope},
        {<<"a">>, [], Now-10, Now, #{}, invalid_queue_scope},
        {<<"a">>, [<<"q">>,<<"q">>], Now-10, Now, #{}, invalid_queue_scope},
        {<<"a">>, [<<"q">>], Now, Now, #{}, invalid_projection_scope},
        {<<"a">>, [<<"q">>], Now-10, Now, #{max_scan=>10001}, invalid_collector_options},
        {<<"a">>, [<<"q">>], Now-10, Now, #{max_scan=>0}, invalid_collector_options},
        {<<"a">>, [<<"q">>], Now-10, Now, #{budget_ms=>1001}, invalid_collector_options},
        {<<"a">>, [<<"q">>], Now-10, Now, #{budget_ms=>-1}, invalid_collector_options},
        {<<"a">>, [<<"q">>], Now-10, Now, #{include_caller_identity=>1}, invalid_collector_options},
        {<<"a">>, [<<"q">>], Now-10, Now, #{include_caller_identity=>undefined}, invalid_collector_options},
        {<<"a">>, [<<"q">>,<<"r">>], Now-10, Now, #{include_caller_identity=>true}, invalid_collector_options},
        {<<"a">>, [<<"q">>], Now-10, Now, #{unknown=>true}, invalid_collector_options},
        {<<"a">>, [<<"q">>], Now-10, Now, [], invalid_collector_options}]].

missing_deleted_and_invalid_sources_not_zero_test() ->
    ?assertEqual({error, source_unavailable}, collect(dashboard_collector_missing, #{})),
    T=table(), ets:delete(T), ?assertEqual({error, source_unavailable}, collect(T, #{})),
    ?assertEqual({error, source_unavailable}, collect({invalid, table}, #{})).

missing_table_cannot_alias_named_undefined_test() ->
    undefined=ets:new(undefined,[named_table,protected,{keypos,2}]),
    try
        ets:insert(undefined,waiting(1)),
        ?assertEqual({error,source_unavailable},collect(dashboard_collector_missing,#{})),
        ?assertEqual(false,ets:info(undefined,safe_fixed)),
        %% An explicitly requested existing table named undefined is valid;
        %% it resolves to its real tid, not the absence sentinel.
        {ok,R}=collect(undefined,#{}), ?assertEqual(1,maps:get(current_waiting,metrics(R)))
    after ets:delete(undefined) end.

unsupported_shape_test_() ->
    [?_test(begin T=ets:new(?MODULE, Opts),
                 try ?assertEqual({error, unsupported_source_table}, collect(T, #{}))
                 after ets:delete(T) end
            end) || Opts <- [[bag,{keypos,2}], [ordered_set,{keypos,2}], [set,{keypos,1}]]].

private_table_is_unavailable_test() ->
    Parent=self(), {Pid,Ref}=spawn_monitor(fun() ->
        T=ets:new(?MODULE,[private,{keypos,2}]), Parent!{private_table,self(),T},
        receive stop -> ok end
    end),
    receive {private_table,Pid,T} -> ?assertEqual({error,source_unavailable},collect(T,#{})) end,
    Pid!stop, receive {'DOWN',Ref,process,Pid,normal} -> ok end.

older_live_occupancy_and_selected_scope_test() ->
    with_table(fun(T) ->
        E=now_s()-500,
        ets:insert(T, [row(1,<<"a">>,<<"q">>,<<"waiting">>,E),
                       (row(2,<<"a">>,<<"q">>,<<"handled">>,E))#call_stat{handled_timestamp=E+5},
                       row(3,<<"foreign">>,<<"q">>,<<"waiting">>,E),
                       row(4,<<"a">>,<<"foreign">>,<<"waiting">>,E)]),
        {ok,R}=collect(T,#{}), C=metrics(R),
        ?assertEqual(4,maps:get(scan_keys,source(R))),
        ?assertEqual(2,maps:get(input_rows,source(R))),
        ?assertEqual(1,maps:get(current_waiting,C)), ?assertEqual(1,maps:get(current_handled,C)),
        ?assertEqual(0,maps:get(records_entered,C)),
        ?assertEqual([#{call_id=><<"1">>,queue_id=><<"q">>,status=><<"waiting">>,
                        entered_timestamp=>E,handled_timestamp=>undefined},
                       #{call_id=><<"2">>,queue_id=><<"q">>,status=><<"handled">>,
                        entered_timestamp=>E,handled_timestamp=>E+5}],active_rows(R)),
        ?assertEqual(true,maps:get(complete,active(R))),
        ?assert(maps:get(max_current_wait_seconds,C)>=500),
        ?assertEqual(false,ets:info(T,safe_fixed))
    end).

all_foreign_keys_count_against_scan_budget_test() ->
    with_table(fun(T) ->
        ets:insert(T,[row(I,<<"foreign">>,<<"other">>,<<"waiting">>,now_s()-20) || I<-lists:seq(1,100)]),
        {ok,R}=collect(T,#{max_scan=>7}),
        ?assertEqual(7,maps:get(scan_keys,source(R))),
        ?assertEqual(0,maps:get(input_rows,source(R))),
        ?assertEqual(scan_limit,maps:get(completion_reason,source(R))),
        ?assertEqual(false,maps:get(exhausted,source(R))),
        ?assertEqual([],active_rows(R)),
        ?assertEqual(false,maps:get(complete,active(R))),
        ?assertEqual(undefined,metrics(R)), ?assertEqual(false,ets:info(T,safe_fixed))
    end).

exact_scan_budget_can_exhaust_test() ->
    with_table(fun(T) ->
        ets:insert(T,[waiting(I) || I<-lists:seq(1,7)]),
        {ok,R}=collect(T,#{max_scan=>7}),
        ?assertEqual(7,maps:get(scan_keys,source(R))),
        ?assertEqual(true,maps:get(exhausted,source(R))),
        ?assertEqual(7,maps:get(current_waiting,metrics(R)))
    end).

zero_deadline_does_not_read_or_invent_metrics_test() ->
    {ok,R}=collect(dashboard_collector_missing,#{budget_ms=>0}),
    ?assertEqual(not_read,maps:get(availability,source(R))),
    ?assertEqual(deadline,maps:get(completion_reason,source(R))),
    ?assertEqual(0,maps:get(scan_keys,source(R))),
    ?assertEqual([],active_rows(R)),
    ?assertEqual(0,maps:get(observed_count,active(R))),
    ?assertEqual(false,maps:get(truncated,active(R))),
    ?assertEqual(false,maps:get(complete,active(R))),
    ?assertEqual(undefined,metrics(R)).

large_source_respects_small_deadline_and_releases_test() ->
    with_table(fun(T) ->
        ets:insert(T,[waiting(I) || I<-lists:seq(1,10000)]),
        Start=erlang:monotonic_time(millisecond), {ok,R}=collect(T,#{budget_ms=>1}),
        Elapsed=erlang:monotonic_time(millisecond)-Start,
        ?assert(maps:get(scan_keys,source(R))=<10000),
        ?assertEqual(false,maps:get(exhausted,source(R))),
        ?assertEqual(deadline,maps:get(completion_reason,source(R))),
        ?assertEqual(undefined,metrics(R)),
        ?assertEqual(false,maps:get(complete,active(R))),
        ?assert(length(active_rows(R))=<200),
        %% Scheduler delays are not a strict wall-clock/SLA assertion.
        ?assert(Elapsed<2000), ?assertEqual(false,ets:info(T,safe_fixed))
    end).

caller_and_misses_fields_not_copied_into_projection_test() ->
    with_table(fun(T) ->
        Secret=binary:copy(<<"DO-NOT-RETURN-PII">>,100000),
        W=(waiting(1))#call_stat{caller_id_name=Secret,caller_id_number=Secret,
                                agent_id=Secret,misses=lists:seq(1,100000)},
        ets:insert(T,W), {ok,R}=collect(T,#{}),
        ?assertEqual(1,maps:get(current_waiting,metrics(R))),
        Encoded=term_to_binary(R), ?assert(byte_size(Encoded)<4096),
        ?assertEqual(nomatch,binary:match(Encoded,<<"DO-NOT-RETURN-PII">>))
    end).

explicit_detail_identity_and_overview_absence_test() ->
    with_table(fun(T) ->
        Marker={1,<<"Synthetic caller">>,<<"+15550000100">>,<<"available">>,<<"available">>},
        ets:insert(T,(waiting(1))#call_stat{dashboard_caller_id=Marker,
            caller_id_name= <<"RAW-MUST-NOT-LEAK">>,caller_id_number= <<"RAW-MUST-NOT-LEAK">>}),
        {ok,Overview}=collect(T,#{}), {ok,ExplicitFalse}=collect(T,#{include_caller_identity=>false}),
        ?assertEqual(active_rows(Overview),active_rows(ExplicitFalse)),
        ?assertEqual(nomatch,binary:match(term_to_binary(Overview),<<"Synthetic caller">>)),
        {ok,Detail}=collect(T,#{include_caller_identity=>true}), [Call]=active_rows(Detail),
        ?assertEqual(<<"Synthetic caller">>,maps:get(caller_id_name,Call)),
        ?assertEqual(<<"+15550000100">>,maps:get(caller_id_number,Call)),
        ?assertEqual(active_rows(Overview),[maps:without([caller_id_name,caller_id_number],Call)]),
        ?assertEqual(1,maps:get(current_waiting,metrics(Detail))),
        ?assertEqual(1,maps:get(scan_keys,source(Detail))),
        ?assertEqual(nomatch,binary:match(term_to_binary(Detail),<<"RAW-MUST-NOT-LEAK">>))
    end).

detail_identity_independent_withholding_test() ->
    with_table(fun(T) ->
        E=now_s()-50,
        ets:insert(T,[(row(1,<<"a">>,<<"q">>,<<"waiting">>,E))#call_stat{
            dashboard_caller_id={1,undefined,<<"+15550000100">>,<<"withheld">>,<<"available">>}},
            (row(2,<<"a">>,<<"q">>,<<"handled">>,E+1))#call_stat{handled_timestamp=E+2,
            dashboard_caller_id={1,<<"Synthetic caller">>,undefined,<<"available">>,<<"unavailable">>}}]),
        {ok,R}=collect(T,#{include_caller_identity=>true}), [First,Second]=active_rows(R),
        ?assertEqual({null,<<"+15550000100">>},{maps:get(caller_id_name,First),maps:get(caller_id_number,First)}),
        ?assertEqual({<<"Synthetic caller">>,null},{maps:get(caller_id_name,Second),maps:get(caller_id_number,Second)}),
        ?assertEqual(1,maps:get(current_handled,metrics(R)))
    end).

malformed_detail_markers_preserve_occupancy_test() ->
    BadMarkers=[undefined,#{untrusted=><<"SENTINEL">>},{1,<<"SENTINEL">>},
        {1,binary:copy(<<"SENTINEL">>,100000),undefined,<<"available">>,<<"unavailable">>},
        {1,<<"SENTINEL">>,binary:copy(<<"9">>,65),<<"available">>,<<"available">>},
        {1,<<"SENTINEL">>,undefined,binary:copy(<<"x">>,100000),<<"unavailable">>},
        {1,<<"SENTINEL">>,undefined,<<"withheld">>,<<"unavailable">>},
        {1,<<255>>,undefined,<<"available">>,<<"unavailable">>},
        {1,<<"SENTINEL\n">>,undefined,<<"available">>,<<"unavailable">>},
        {1,[<<"SENTINEL">>],undefined,<<"available">>,<<"unavailable">>}],
    with_table(fun(T) ->
        ets:insert(T,[(waiting(I))#call_stat{dashboard_caller_id=M,
            caller_id_name= <<"SENTINEL-RAW">>,caller_id_number= <<"SENTINEL-RAW">>} ||
            {I,M}<-lists:zip(lists:seq(1,length(BadMarkers)),BadMarkers)]),
        {ok,R}=collect(T,#{include_caller_identity=>true}),
        ?assertEqual(length(BadMarkers),maps:get(current_waiting,metrics(R))),
        ?assertEqual(length(BadMarkers),length(active_rows(R))),
        [?assertEqual({null,null},{maps:get(caller_id_name,C),maps:get(caller_id_number,C)}) || C<-active_rows(R)],
        ?assertEqual(nomatch,binary:match(term_to_binary(R),<<"SENTINEL">>)),
        ?assert(byte_size(term_to_binary(R))<10000),
        ?assertEqual(false,ets:info(T,safe_fixed))
    end).

detail_identity_foreign_and_terminal_never_returned_test() ->
    with_table(fun(T) ->
        E=now_s()-20, Marker={1,<<"FOREIGN-TERMINAL-SENTINEL">>,undefined,<<"available">>,<<"unavailable">>},
        ets:insert(T,[waiting(1),
            (row(2,<<"foreign">>,<<"q">>,<<"waiting">>,E))#call_stat{dashboard_caller_id=Marker},
            (row(3,<<"a">>,<<"other">>,<<"waiting">>,E))#call_stat{dashboard_caller_id=Marker},
            (row(4,<<"a">>,<<"q">>,<<"abandoned">>,E))#call_stat{abandoned_timestamp=E+1,dashboard_caller_id=Marker}]),
        {ok,R}=collect(T,#{include_caller_identity=>true}),
        ?assertEqual(4,maps:get(scan_keys,source(R))),
        ?assertEqual(1,length(active_rows(R))),
        ?assertEqual(nomatch,binary:match(term_to_binary(R),<<"FOREIGN-TERMINAL-SENTINEL">>))
    end).

detail_identity_budget_cap_and_timeline_unchanged_test() ->
    {ok,Zero}=collect(dashboard_collector_missing,#{include_caller_identity=>true,budget_ms=>0}),
    ?assertEqual(not_read,maps:get(availability,source(Zero))),
    with_table(fun(T) ->
        E=now_s()-500, M={1,<<"Synthetic">>,undefined,<<"available">>,<<"unavailable">>},
        ets:insert(T,[(row(I,<<"a">>,<<"q">>,<<"waiting">>,E+I))#call_stat{dashboard_caller_id=M} || I<-lists:seq(1,201)]),
        {ok,R}=collect(T,#{include_caller_identity=>true}),
        ?assertEqual(200,length(active_rows(R))),
        ?assertEqual(201,maps:get(current_waiting,metrics(R))),
        ?assertEqual(true,maps:get(truncated,active(R))),
        ?assertEqual([integer_to_binary(I) || I<-lists:seq(1,200)], [maps:get(call_id,C) || C<-active_rows(R)]),
        {ok,Limited}=collect(T,#{include_caller_identity=>true,max_scan=>7}),
        ?assertEqual(7,maps:get(scan_keys,source(Limited))),
        ?assertEqual(false,maps:get(complete,active(Limited))),
        ?assertEqual(undefined,metrics(Limited)),
        ets:insert(T,(waiting(1))#call_stat{handled_timestamp=now_s(),dashboard_caller_id=M}),
        ?assertEqual({error,invalid_record_timeline},collect(T,#{include_caller_identity=>true})),
        ?assertEqual(false,ets:info(T,safe_fixed))
    end).

active_row_cap_preserves_overview_test_() ->
    [?_test(with_table(fun(T) ->
        E=now_s()-500,
        Rows=[row(I,<<"a">>,<<"q">>,<<"waiting">>,E+I) || I<-lists:seq(1,N)],
        ets:insert(T,lists:reverse(Rows)), {ok,R}=collect(T,#{}), A=active(R),
        ?assertEqual(N,maps:get(current_waiting,metrics(R))),
        ?assertEqual(N,maps:get(input_rows,source(R))),
        ?assertEqual(N,maps:get(scan_keys,source(R))),
        ?assertEqual(true,maps:get(exhausted,source(R))),
        ?assertEqual(N,maps:get(observed_count,A)),
        ?assertEqual(N>200,maps:get(truncated,A)),
        ?assertEqual(N=<200,maps:get(complete,A)),
        ?assertEqual([integer_to_binary(I) || I<-lists:seq(1,erlang:min(N,200))],
                     [maps:get(call_id,Call) || Call<-active_rows(R)]),
        ?assertEqual(false,ets:info(T,safe_fixed))
    end)) || N<-[199,200,201]].

active_order_scope_and_terminal_exclusion_test() ->
    with_table(fun(T) ->
        E=now_s()-500,
        Rows=[row(20,<<"a">>,<<"q">>,<<"waiting">>,E),
              row(10,<<"a">>,<<"q">>,<<"waiting">>,E),
              row(1,<<"a">>,<<"q">>,<<"waiting">>,E+1),
              (row(2,<<"a">>,<<"p">>,<<"handled">>,E+10))#call_stat{handled_timestamp=E+20},
              (row(3,<<"a">>,<<"q">>,<<"processed">>,E))#call_stat{
                  handled_timestamp=E+10,processed_timestamp=E+20},
              (row(4,<<"a">>,<<"q">>,<<"abandoned">>,E))#call_stat{abandoned_timestamp=E+20},
              row(5,<<"foreign">>,<<"q">>,<<"waiting">>,E),
              row(6,<<"a">>,<<"other">>,<<"waiting">>,E)],
        ets:insert(T,Rows), Now=now_s(),
        {ok,R}=acdc_dashboard_collector:collect(T,<<"a">>,[<<"q">>,<<"p">>],Now-100,Now,#{}),
        Expected=[{<<"p">>,<<"2">>},{<<"q">>,<<"10">>},{<<"q">>,<<"20">>},{<<"q">>,<<"1">>}],
        ?assertEqual(Expected,[{maps:get(queue_id,C),maps:get(call_id,C)} || C<-active_rows(R)]),
        ?assertEqual(4,maps:get(observed_count,active(R))),
        ?assertEqual(true,maps:get(complete,active(R))),
        ?assertEqual(8,maps:get(scan_keys,source(R))),
        ?assertEqual(6,maps:get(input_rows,source(R))),
        [ ?assertEqual([call_id,entered_timestamp,handled_timestamp,queue_id,status],
                       lists:sort(maps:keys(C))) || C<-active_rows(R)],
        %% Reinsert in another order: order means entry age plus identity only,
        %% never a queue position or a promise of an atomic observation.
        ets:delete_all_objects(T),ets:insert(T,lists:reverse(Rows)),
        {ok,R2}=acdc_dashboard_collector:collect(T,<<"a">>,[<<"p">>,<<"q">>],Now-100,Now,#{}),
        ?assertEqual(active(R),active(R2))
    end).

active_scan_limit_is_not_complete_test() ->
    with_table(fun(T) ->
        ets:insert(T,[waiting(I) || I<-lists:seq(1,20)]),
        {ok,R}=collect(T,#{max_scan=>7}), A=active(R),
        ?assertEqual(7,maps:get(observed_count,A)),
        ?assertEqual(7,length(maps:get(rows,A))),
        ?assertEqual(false,maps:get(truncated,A)),
        ?assertEqual(false,maps:get(complete,A)),
        ?assertEqual(undefined,metrics(R)),
        ?assertEqual(scan_limit,maps:get(completion_reason,source(R)))
    end).

terminal_only_source_has_complete_empty_active_list_test() ->
    with_table(fun(T) ->
        E=now_s()-20,
        ets:insert(T,[(row(1,<<"a">>,<<"q">>,<<"processed">>,E))#call_stat{
                          handled_timestamp=E+1,processed_timestamp=E+2},
                      (row(2,<<"a">>,<<"q">>,<<"abandoned">>,E))#call_stat{
                          abandoned_timestamp=E+2}]),
        {ok,R}=collect(T,#{}),
        ?assertEqual([],active_rows(R)),
        ?assertEqual(0,maps:get(observed_count,active(R))),
        ?assertEqual(true,maps:get(complete,active(R))),
        ?assertEqual(2,maps:get(records_entered,metrics(R))),
        ?assertEqual(1,maps:get(processed_in_cohort,metrics(R))),
        ?assertEqual(1,maps:get(abandoned_in_cohort,metrics(R)))
    end).

invalid_active_timeline_never_returns_partial_detail_test() ->
    with_table(fun(T) ->
        ets:insert(T,[waiting(1),(waiting(2))#call_stat{handled_timestamp=now_s()}]),
        ?assertEqual({error,invalid_record_timeline},collect(T,#{})),
        ?assertEqual(false,ets:info(T,safe_fixed))
    end).

invalid_selected_record_releases_fixation_test_() ->
    [?_test(with_table(fun(T) -> ets:insert(T,W),
        ?assertMatch({error,_},collect(T,#{})), ?assertEqual(false,ets:info(T,safe_fixed)) end)) ||
        W <- [(waiting(1))#call_stat{call_id=binary:copy(<<"x">>,257)},
              (waiting(1))#call_stat{status=binary:copy(<<"x">>,33)},
              (waiting(1))#call_stat{entered_timestamp=0},
              (waiting(1))#call_stat{entered_timestamp=1 bsl 2000},
              (waiting(1))#call_stat{id = <<"forged">>},
              (waiting(1))#call_stat{status = <<"unknown">>},
              (waiting(1))#call_stat{handled_timestamp=now_s()},
              {bad_record,<<"bad-key">>}, {call_stat,<<"bad-key">>},
              (waiting(1))#call_stat{id=42}]].

named_table_resolution_test() ->
    T=ets:new(dashboard_collector_named,[named_table,protected,{keypos,2}]),
    try ets:insert(T,waiting(1)), {ok,R}=collect(dashboard_collector_named,#{}),
        ?assertEqual(1,maps:get(current_waiting,metrics(R))),
        ?assertEqual(false,ets:info(T,safe_fixed))
    after ets:delete(T) end.

named_table_replacement_does_not_switch_source_test_() ->
    {timeout, 5, fun() ->
        Name=dashboard_collector_replaced,
        T=ets:new(Name,[named_table,protected,{keypos,2}]),
        Tid=ets:whereis(Name),
        ets:insert(T,[waiting(I) || I<-lists:seq(1,10000)]),
        Parent=self(), {Pid,Ref}=spawn_monitor(fun() -> Parent!{collected,self(),collect(Name,#{})} end),
        try
            %% Use the actual fixation as the synchronization point. No test
            %% hook, injected resolver, or alternative collector is involved.
            ok=await_fixed(Tid,Pid,erlang:monotonic_time(millisecond)+1500),
            true=erlang:suspend_process(Pid),
            ets:delete(T),
            Name=ets:new(Name,[named_table,protected,{keypos,2}]),
            ets:insert(Name,waiting(20000)),
            ?assertNotEqual(Tid,ets:whereis(Name)),
            true=erlang:resume_process(Pid),
            receive {collected,Pid,Result} -> ?assertEqual({error,source_unavailable},Result)
            after 1500 -> error(collector_did_not_finish) end,
            receive {'DOWN',Ref,process,Pid,normal} -> ok after 1500 -> error(collector_did_not_exit) end,
            ?assertEqual(false,ets:info(Name,safe_fixed)),
            ?assertEqual(1,ets:info(Name,size))
        after
            case is_process_alive(Pid) of true -> exit(Pid,kill); false -> ok end,
            case ets:whereis(Name) of undefined -> ok; _ -> ets:delete(Name) end
        end
    end}.

await_fixed(Tid,Pid,Deadline) ->
    case ets:info(Tid,safe_fixed) of
        {_,Fixers} ->
            case lists:keymember(Pid,1,Fixers) of
                true -> ok;
                false -> await_fixed_again(Tid,Pid,Deadline)
            end;
        false -> await_fixed_again(Tid,Pid,Deadline)
    end.
await_fixed_again(Tid,Pid,Deadline) ->
    case erlang:monotonic_time(millisecond)>=Deadline of
        true -> error(fixation_not_observed);
        false -> receive after 1 -> await_fixed(Tid,Pid,Deadline) end
    end.
