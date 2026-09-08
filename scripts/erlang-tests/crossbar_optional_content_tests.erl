%%% Public production callbacks; datastore/service reads are controlled.
%%% Real cb_context, JSON/document helpers and transformed Lager diagnostics.
-module(crossbar_optional_content_tests).
-include_lib("eunit/include/eunit.hrl").
-define(MASTER, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(ACCOUNT, <<"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb">>).
-define(APP, <<"cccccccccccccccccccccccccccccccc">>).

default_content_test_() ->
    [{atom_to_list(M) ++ "/" ++ integer_to_list(length(Tokens) + 1), fun() ->
        C = cb_context:set_req_verb(cb_context:new(), <<"GET">>),
        ?assertEqual(C, apply(M, content_types_provided, [C|Tokens]))
     end} || {M, Tokens} <- [{cb_apps_store, []}, {cb_apps_store, [?APP]},
        {cb_vmboxes, []}, {cb_vmboxes, [<<"box">>]}, {cb_directories, []}]].

specialized_content_test() ->
    C = cb_context:set_req_verb(cb_context:new(), <<"GET">>),
    PDF = cb_directories:content_types_provided(C, <<"directory">>),
    ?assert(C =/= PDF),
    ?assert(lists:keymember(to_pdf, 1, cb_context:content_types_provided(PDF))),
    Audio = cb_vmboxes:content_types_provided(C, <<"box">>, <<"messages">>, <<"msg">>, <<"raw">>),
    ?assert(C =/= Audio),
    ?assert(lists:keymember(to_binary, 1, cb_context:content_types_provided(Audio))),
    ?assertEqual(C, cb_apps_store:content_types_provided(C, ?APP, <<"nonbinary">>)).

apps_store_test_() ->
    [{Name, {timeout, 40, fun() -> store_case(Result, Published, ErrorCount) end}}
     || {Name, Result, Published, ErrorCount} <-
       [{"absent optional overrides preserve inherited apps without error", {error, not_found}, true, 0},
        {"real datastore timeout still logs error", {error, timeout}, true, 1},
        {"existing blacklist still denies app", {ok, blacklist}, false, 0}]].

store_case(Result, Published, ErrorCount) ->
    Modules = [kapps_util, kz_datamgr, kz_services_applications,
               kz_services_reseller, kz_nodes, kzd_apps_store, kzd_whitelabel],
    ok = lager_config:new(),
    _ = lager_config:set(loglevel, {255, []}),
    _ = lager_config:set(async, false),
    {ok, Sink} = gen_event:start_link({local, lager_event}),
    unlink(Sink),
    try
        ok = gen_event:add_handler(Sink, kazoo_bindings_lager_tests, []),
        lists:foreach(fun(M) -> meck:new(M, [non_strict, no_link]) end, Modules),
        meck:expect(kapps_util, get_master_account_id, fun() -> {ok, ?MASTER} end),
        meck:expect(kapps_util, get_master_account_db, fun() -> {ok, kzs_util:format_account_db(?MASTER)} end),
        App = kz_json:from_list([{<<"_id">>, ?APP}, {<<"name">>, <<"fixture">>},
            {<<"published">>, true}, {<<"pvt_account_id">>, ?MASTER},
            {<<"pvt_account_db">>, kzs_util:format_account_db(?MASTER)}]),
        meck:expect(kz_datamgr, get_results, fun(_, <<"apps_store/crossbar_listing">>, [include_docs]) ->
            {ok, [App]} end),
        meck:expect(kz_datamgr, open_docs, fun(?ACCOUNT, _) -> {ok, []} end),
        meck:expect(kz_services_applications, fetch, fun(_) -> kz_json:new() end),
        meck:expect(kz_services_reseller, is_reseller, fun(_) -> false end),
        meck:expect(kz_services_reseller, get_id, fun(_) -> ?MASTER end),
        meck:expect(kz_nodes, status_to_json, fun() -> kz_json:new() end),
        meck:expect(kzd_apps_store, fetch, fun(?ACCOUNT) -> Result end),
        meck:expect(kzd_apps_store, apps, fun(blacklist) -> kz_json:new() end),
        meck:expect(kzd_apps_store, blacklist, fun(blacklist) -> [?APP] end),
        meck:expect(kzd_whitelabel, fetch, fun(_) -> {error, not_found} end),
        meck:expect(kzd_whitelabel, new, fun() -> kz_json:new() end),
        [Actual] = cb_apps_util:allowed_apps(?ACCOUNT, <<"fixture-user">>),
        ?assertEqual(?APP, kz_doc:id(Actual)),
        ?assertEqual(Published, kzd_app:is_published(Actual)),
        Rows = gen_event:call(Sink, kazoo_bindings_lager_tests, rows),
        Errors = [Text || #{severity := error, rendered := Text} <- Rows],
        ?assertEqual(ErrorCount, length(Errors)),
        case Errors of
            [Text] -> ?assertNotEqual(nomatch, binary:match(Text, <<"failed to fetch apps store doc">>));
            [] -> ok
        end,
        ?assertNot(meck:called(kz_datamgr, save_doc, '_')),
        ?assert(lists:all(fun meck:validate/1, Modules))
    after
        lists:foreach(fun(M) -> catch meck:unload(M) end, Modules),
        gen_event:stop(Sink), lager_config:cleanup()
    end.
