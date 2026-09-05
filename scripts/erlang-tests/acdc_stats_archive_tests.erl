-module(acdc_stats_archive_tests).
-include_lib("eunit/include/eunit.hrl").
-include("acdc_stats.hrl").
-define(ACCOUNT, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(AGENT, <<"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb">>).

status(Id, Timestamp, Value) ->
    #status_stat{id=Id, key=#status_stat_key{account_id=?ACCOUNT, agent_id=?AGENT, timestamp=Timestamp}, status=Value}.
call(Id) -> #call_stat{id=Id, account_id=?ACCOUNT, call_id=Id, queue_id = <<"queue">>, status = <<"processed">>, entered_timestamp=1}.
j(P) -> kz_json:from_list(P).
ack(D) -> j([{<<"id">>, kz_doc:id(D)}, {<<"rev">>, <<"1-persisted">>}, {<<"ok">>, true}]).

with_tables(Fun) ->
    Mods = [kz_datamgr, kapps_config, acdc_stats_util],
    [meck:new(M, [non_strict, no_link]) || M <- Mods],
    ets:new(acdc_stats_call, acdc_stats:call_table_opts()),
    ets:new(acdc_stats_status, acdc_agent_stats:status_table_opts()),
    try
        meck:expect(kapps_config, get_integer, fun(_, <<"stats_shutdown_flush_ms">>, _) -> 150;
                                                    (_, _, Default) -> Default end),
        meck:expect(acdc_stats_util, db_name, fun(A) -> A end),
        meck:expect(kz_datamgr, suppress_change_notice, fun() -> ok end),
        meck:expect(kz_datamgr, save_docs, fun(_, Docs) -> {ok, [ack(D) || D <- Docs]} end),
        Fun()
    after
        drain(), ets:delete(acdc_stats_call), ets:delete(acdc_stats_status),
        [meck:unload(M) || M <- Mods]
    end.
drain() ->
    receive {'$gen_cast', {'$client_cast', Msg}} -> acdc_stats:handle_cast(Msg, test), drain()
    after 0 -> ok end.
saved_status(Key) -> [S] = ets:lookup(acdc_stats_status, Key), S#status_stat.is_archived.
saved_call(Id) -> [S] = ets:lookup(acdc_stats_call, Id), S#call_stat.is_archived.

bulk_failure_keeps_status_and_calls_retryable_test() -> with_tables(fun() ->
    S = status(<<"s">>, 1, <<"ready">>), ets:insert(acdc_stats_status, S), ets:insert(acdc_stats_call, call(<<"c">>)),
    meck:expect(kz_datamgr, save_docs, fun(_, _) -> {error, timeout} end),
    acdc_agent_stats:archive_status_data(self(), true), acdc_stats:archive_call_data(self(), true), drain(),
    ?assertNot(saved_status(S#status_stat.key)), ?assertNot(saved_call(<<"c">>)),
    meck:expect(kz_datamgr, save_docs, fun(_, Docs) -> {ok, [ack(D) || D <- Docs]} end),
    acdc_agent_stats:archive_status_data(self(), true), acdc_stats:archive_call_data(self(), true), drain(),
    ?assert(saved_status(S#status_stat.key)), ?assert(saved_call(<<"c">>))
end).

partial_bulk_ack_marks_only_persisted_records_test() -> with_tables(fun() ->
    A = status(<<"a">>, 1, <<"ready">>), B = status(<<"b">>, 2, <<"paused">>),
    ets:insert(acdc_stats_status, [A,B]),
    meck:expect(kz_datamgr, save_docs, fun(_, Docs) ->
        {ok, [case kz_doc:id(D) of <<"a">> -> ack(D); _ -> j([{<<"id">>, <<"b">>}, {<<"error">>, <<"forbidden">>}]) end || D <- Docs]}
    end),
    acdc_agent_stats:archive_status_data(self(), true), drain(),
    ?assert(saved_status(A#status_stat.key)), ?assertNot(saved_status(B#status_stat.key))
end).

stale_snapshot_cannot_archive_newer_same_key_status_test() -> with_tables(fun() ->
    Old = status(<<"same">>, 1, <<"logged_in">>), New = Old#status_stat{status = <<"ready">>},
    ets:insert(acdc_stats_status, Old),
    acdc_agent_stats:archive_status_data(self(), true),
    ets:insert(acdc_stats_status, New), drain(),
    ?assertNot(saved_status(New#status_stat.key))
end).

conflict_requires_verified_identical_document_test() -> with_tables(fun() ->
    D = j([{<<"_id">>, <<"s">>}, {<<"status">>, <<"ready">>}, {<<"pvt_account_id">>, ?ACCOUNT}]),
    Groups = dict:store(?ACCOUNT, [D], dict:new()),
    meck:expect(kz_datamgr, save_docs, fun(_, _) -> {ok, [j([{<<"id">>, <<"s">>}, {<<"error">>, <<"conflict">>}])]} end),
    meck:expect(kz_datamgr, open_doc, fun(_, _) -> {ok, kz_json:set_value(<<"_rev">>, <<"1-x">>, D)} end),
    ?assertEqual([{?ACCOUNT, <<"s">>}], acdc_stats_archive:save(Groups)),
    meck:expect(kz_datamgr, open_doc, fun(_, _) -> {ok, kz_json:set_value(<<"status">>, <<"logged_out">>, D)} end),
    ?assertEqual([], acdc_stats_archive:save(Groups))
end).

cleanup_does_not_delete_unsaved_old_rows_test() -> with_tables(fun() ->
    A = status(<<"a">>, 1, <<"ready">>), B = (status(<<"b">>, 2, <<"ready">>))#status_stat{is_archived=true},
    ets:insert(acdc_stats_status, [A,B]),
    ets:insert(acdc_stats_call, [call(<<"pending">>), (call(<<"saved">>))#call_stat{is_archived=true}]),
    acdc_stats:cleanup_data(self()), drain(),
    ?assertEqual([A], ets:lookup(acdc_stats_status, A#status_stat.key)),
    ?assertEqual([], ets:lookup(acdc_stats_status, B#status_stat.key)),
    ?assertEqual([], ets:lookup(acdc_stats_call, <<"saved">>)),
    ?assertNotEqual([], ets:lookup(acdc_stats_call, <<"pending">>))
end).

shutdown_waits_and_acknowledges_before_owner_returns_test() -> with_tables(fun() ->
    S = status(<<"latest">>, kz_time:now_s(), <<"ready">>), ets:insert(acdc_stats_status, S),
    ets:insert(acdc_stats_call, call(<<"completed">>)),
    Parent = self(),
    meck:expect(kz_datamgr, save_docs, fun(_, Docs) ->
        ?assert(ets:info(acdc_stats_status) =/= undefined),
        Parent ! {persisted_before_return, [kz_doc:id(D) || D <- Docs]},
        timer:sleep(10), {ok, [ack(D) || D <- Docs]}
    end),
    ?assertEqual(ok, acdc_stats:force_archive_data()),
    ?assert(saved_status(S#status_stat.key)), ?assert(saved_call(<<"completed">>)),
    receive {persisted_before_return, [<<"latest">>]} -> ok after 0 -> error(status_not_flushed_first) end,
    receive {persisted_before_return, [<<"completed">>]} -> ok after 0 -> error(call_not_flushed) end
end).

shutdown_timeout_is_bounded_and_not_reported_success_test() -> with_tables(fun() ->
    S = status(<<"latest">>, 1, <<"ready">>), ets:insert(acdc_stats_status, S),
    Parent = self(),
    meck:expect(kz_datamgr, save_docs, fun(_, _) -> Parent ! {archive_worker, self()}, receive continue -> {error, timeout} end end),
    Before = erlang:monotonic_time(millisecond),
    ?assertEqual({error, timeout}, acdc_stats:force_archive_data()),
    ?assert(erlang:monotonic_time(millisecond) - Before < 1000),
    ?assertNot(saved_status(S#status_stat.key)),
    receive {archive_worker, Pid} -> ?assertNot(is_process_alive(Pid)) after 0 -> error(no_worker) end
end).

shutdown_partial_failure_is_not_success_test() -> with_tables(fun() ->
    ets:insert(acdc_stats_status, status(<<"latest">>, 1, <<"ready">>)),
    meck:expect(kz_datamgr, save_docs, fun(_, _) -> {error, unavailable} end),
    ?assertEqual({error, incomplete}, acdc_stats:force_archive_data())
end).

post_shutdown_periodic_worker_has_no_ets_badarg_test() ->
    ?assertEqual([], acdc_stats_archive:select(nonexistent_acdc_archive_test_table, [{'_', [], ['$_']}] )).

legacy_unverified_call_archive_update_cannot_skip_retry_test() -> with_tables(fun() ->
    ets:insert(acdc_stats_call, call(<<"c">>)),
    acdc_stats:handle_cast({update_call, <<"c">>, [{#call_stat.is_archived, true}]}, test),
    ?assertNot(saved_call(<<"c">>))
end).

supervisor_budget_exceeds_bounded_flush_test() ->
    {ok, {_, Children}} = acdc_stats_sup:init([]),
    {acdc_stats, _, _, Budget, _, _} = lists:keyfind(acdc_stats, 1, Children),
    ?assert(Budget > 13000).

restart_latest_status_is_available_from_persisted_database_test() -> with_tables(fun() ->
    Archive = ets:new(test_archive, [set, public]),
    meck:new(kz_amqp_worker, [non_strict, no_link]),
    try
        meck:expect(kz_datamgr, save_docs, fun(_, Docs) ->
            [ets:insert(Archive, {kz_doc:id(D), D}) || D <- Docs], {ok, [ack(D) || D <- Docs]}
        end),
        meck:expect(kz_datamgr, get_results, fun(_, <<"agent_stats/status_log">>, _) ->
            Docs = [D || {_, D} <- ets:tab2list(Archive)],
            [{_, Latest}|_] = lists:reverse(lists:keysort(1, [{kz_json:get_value(<<"timestamp">>, D), D} || D <- Docs])),
            {ok, [j([{<<"value">>, kz_json:get_value(<<"status">>, Latest)}])]}
        end),
        meck:expect(kz_amqp_worker, call_collect, fun(_, _, _, _) -> {ok, []} end),
        ets:insert(acdc_stats_status, [status(<<"old">>, 1, <<"logged_out">>), status(<<"new">>, 2, <<"ready">>)]),
        ?assertEqual(ok, acdc_stats:force_archive_data()),
        ets:delete_all_objects(acdc_stats_status),
        ?assertEqual({ok, <<"ready">>}, acdc_agent_util:most_recent_status(?ACCOUNT, ?AGENT)),
        ?assert(acdc_agent_util:status_should_auto_start(<<"ready">>))
    after meck:unload(kz_amqp_worker), ets:delete(Archive) end
end).
