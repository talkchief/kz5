%%% Development-only real CouchDB primary-CAS probe. No account fixtures.
%%% Native delete -> kz_datamgr -> kzs_doc -> kz_couch_doc -> Couchbeam.
%%% Routing/cache/publication seams are controlled, not production processes.
-module(crossbar_soft_delete_couch_probe).
-export([run/0]).
-include_lib("kernel/include/file.hrl").

run() ->
    %% Never format exception values: transport exceptions may contain auth.
    _ = logger:remove_handler(default),
    application:set_env(lager, handlers, []),
    try
        main(),
        io:format("PASS: native primary CouchDB CAS; synthetic database retained~n"),
        halt(0)
    catch
        throw:expected_conflict_got_success ->
            io:format("FAIL: native stale delete reported success instead of conflict; fixture retained~n"),
            halt(1);
        _:_ ->
            io:format("FAIL: CouchDB revision probe; inspect sanitized receipt stage, not raw exceptions~n"),
            halt(1)
    end.

main() ->
    Out = os:getenv("KAZOO_COUCH_PROBE_OUTPUT"),
    true = is_list(Out),
    stage(Out, startup),
    {ok, _} = application:ensure_all_started(lager),
    {ok, _} = application:ensure_all_started(couchbeam),
    Conn = connection(),
    stage(Out, server_check),
    {ok, Info} = couchbeam:server_info(Conn),
    <<"3.", _/binary>> = kz_json:get_value(<<"version">>, Info),
    Nonce = kz_binary:rand_hex(16),
    Db = <<"kazoo_revision_probe_", Nonce/binary>>,
    %% Ledger contains only fresh fixture names; no credentials or payloads.
    ok = file:write_file(filename:join(Out, "database.txt"), <<Db/binary, "\n">>, [exclusive]),
    stage(Out, database_create),
    {ok, _} = couchbeam:create_db(Conn, Db, [], [{"q", "1"}, {"n", "1"}]),
    Marker = kz_json:from_list([{<<"_id">>, <<"owner">>},
        {<<"purpose">>, <<"kz5-p0-19-primary-cas-probe">>}, {<<"nonce">>, Nonce}]),
    {ok, _} = kz_couch_doc:save_doc(Conn, Db, Marker, []),
    stage(Out, route_setup),
    Modules = [kzs_plan, kzs_cache, kzs_publish],
    Effects = ets:new(couch_probe_effects, [public, set]),
    ets:insert(Effects, [{published, 0}, {cache_added, 0}]),
    try
        lists:foreach(fun(M) -> meck:new(M, [non_strict, no_link]) end, Modules),
        meck:expect(kzs_plan, plan, fun(D, _) when D =:= Db ->
            #{server => {kz_couch_doc, Conn}, secondary => []}
        end),
        meck:expect(kzs_cache, flush_cache_doc, fun(D, _) when D =:= Db -> ok end),
        meck:expect(kzs_cache, add_to_doc_cache, fun(D, _, _) when D =:= Db ->
            ets:update_counter(Effects, cache_added, 1), ok
        end),
        meck:expect(kzs_publish, publish_fields, fun(_) -> [] end),
        meck:expect(kzs_publish, maybe_publish_doc, fun(D, _, _) when D =:= Db ->
            ets:update_counter(Effects, published, 1), ok
        end),
        stage(Out, soft_delete_success),
        Soft = create(Conn, Db, <<"soft_success">>, Nonce),
        success = cb_context:resp_status(crossbar_doc:delete(context(Db, Soft), true)),
        {ok, SoftSaved} = kz_couch_doc:open_doc(Conn, Db, <<"soft_success">>),
        true = kz_doc:is_soft_deleted(SoftSaved),
        Nonce = kz_json:get_value(<<"fixture_nonce">>, SoftSaved),
        <<"original">> = kz_json:get_value(<<"marker">>, SoftSaved),
        stage(Out, concurrent_soft_delete_conflict),
        First = create(Conn, Db, <<"concurrent_edit">>, Nonce),
        Updated = kz_json:set_values([{<<"marker">>, <<"concurrent">>},
            {<<"pvt_fixture_marker">>, <<"concurrent-private">>}], First),
        {ok, _} = kz_couch_doc:save_doc(Conn, Db, Updated, []),
        {ok, Latest} = kz_couch_doc:open_doc(Conn, Db, <<"concurrent_edit">>),
        true = kz_doc:revision(First) =/= kz_doc:revision(Latest),
        BeforeConflict = lists:sort(ets:tab2list(Effects)),
        conflict(crossbar_doc:delete(context(Db, First), true)),
        BeforeConflict = lists:sort(ets:tab2list(Effects)),
        {ok, Latest} = kz_couch_doc:open_doc(Conn, Db, <<"concurrent_edit">>),
        false = kz_doc:is_soft_deleted(Latest),
        stage(Out, concurrent_hard_delete_conflict),
        conflict(crossbar_doc:delete(context(Db, First), false)),
        BeforeConflict = lists:sort(ets:tab2list(Effects)),
        {ok, Latest} = kz_couch_doc:open_doc(Conn, Db, <<"concurrent_edit">>),
        stage(Out, exact_owned_document_cleanup),
        %% Exact saved revisions, no lookup/retry. Conflicts retain fixtures.
        success = cb_context:resp_status(crossbar_doc:delete(context(Db, Latest), false)),
        {error, not_found} = kz_couch_doc:open_doc(Conn, Db, <<"concurrent_edit">>),
        success = cb_context:resp_status(crossbar_doc:delete(context(Db, SoftSaved), false)),
        {error, not_found} = kz_couch_doc:open_doc(Conn, Db, <<"soft_success">>),
        stage(Out, passed_marker_and_tombstones_retained)
    after
        lists:foreach(fun(M) -> catch meck:unload(M) end, lists:reverse(Modules)),
        ets:delete(Effects)
    end.

connection() ->
    %% Explicit local config; never source a shell secrets file or accept URLs.
    Path = "/etc/kazoo/core/config.ini",
    {ok, #file_info{type=regular, uid=0, mode=Mode}} = file:read_link_info(Path),
    0 = Mode band 8#027,
    {ok, Body} = file:read_file(Path),
    {ok, Sections} = eini:parse(Body),
    Props = value(<<"couchdb3">>, Sections),
    <<"127.0.0.1">> = kz_term:to_binary(value(<<"ip">>, Props)),
    Port = kz_term:to_integer(value(<<"port">>, Props)),
    5984 = Port,
    User = kz_term:to_list(value(<<"username">>, Props)),
    Pass = kz_term:to_list(value(<<"password">>, Props)),
    true = User =/= [] andalso Pass =/= [],
    couchbeam:server_connection("127.0.0.1", Port, <<>>,
        [{basic_auth, {User, Pass}}, {driver_version, couchdb_3},
         {connect_timeout, 3000}, {recv_timeout, 5000}]).

value(Name, Props) ->
    [V] = [V || {K, V} <- Props, kz_term:to_binary(K) =:= Name],
    V.

create(Conn, Db, Id, Nonce) ->
    Doc = kz_json:from_list([{<<"_id">>, Id}, {<<"pvt_type">>, <<"account">>},
        {<<"fixture_nonce">>, Nonce}, {<<"marker">>, <<"original">>},
        {<<"pvt_fixture_marker">>, <<"private-original">>}]),
    {ok, _} = kz_couch_doc:save_doc(Conn, Db, Doc, []),
    {ok, Saved} = kz_couch_doc:open_doc(Conn, Db, Id),
    Saved.

context(Db, Doc) ->
    cb_context:setters(cb_context:new(),
        [{fun cb_context:set_doc/2, Doc}, {fun cb_context:set_db_name/2, Db},
         {fun cb_context:set_api_version/2, <<"v2">>},
         {fun cb_context:set_req_id/2, <<"owned-primary-cas-probe">>},
         {fun cb_context:set_req_verb/2, <<"DELETE">>},
         {fun cb_context:set_resp_status/2, success}]).

conflict(Context) ->
    case cb_context:resp_status(Context) of
        success -> throw(expected_conflict_got_success);
        error -> ok
    end,
    409 = cb_context:resp_error_code(Context),
    <<"datastore_conflict">> = cb_context:resp_error_msg(Context),
    ok.

stage(Out, Name) ->
    ok = file:write_file(filename:join(Out, "stages.log"),
        [atom_to_list(Name), "\n"], [append]),
    ok.
