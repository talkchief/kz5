%%% Admin-only scope-management validation, using public production callbacks,
%%% real cb_context identity resolution and real kzd_users role interpretation.
%%% Schema/doc/view/config and identity datastore reads are controlled. This is
%%% not native HTTP, token cryptography, hierarchy/global-auth or cache proof.
-module(crossbar_scope_management_tests).
-include_lib("eunit/include/eunit.hrl").
-define(A, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(U, <<"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb">>).
-define(SCOPE, <<"api:offline-owned-scope">>).

scope_management_test_() ->
    [{Name, {timeout, 40, Fun}} || {Name, Fun} <-
        [{"nonadmin all routes forbidden before resource reads", fun deny_routes/0},
         {"account admin preserves all validators", fun admin_routes/0},
         {"superadmin preserves all validators", fun super_routes/0},
         {"missing owner and failed identity reads deny", fun missing_identity/0},
         {"real identity role interpretation", fun identity_roles/0},
         {"capability and corrected default module", fun capability_defaults/0},
         {"exact persisted alias normalization", fun configured_aliases/0}]].

context() ->
    cb_context:setters(cb_context:new(),
        [{fun cb_context:set_auth_account_id/2, ?A},
         {fun cb_context:set_account_id/2, ?A},
         {fun cb_context:set_db_name/2, kzs_util:format_account_db(?A)},
         {fun cb_context:set_auth_doc/2, kz_json:from_list([{<<"owner_id">>, ?U}])},
         {fun cb_context:set_is_superduper_admin/2, false},
         {fun cb_context:set_api_version/2, <<"v2">>},
         {fun cb_context:set_req_data/2, kz_json:from_list([{<<"id">>, ?SCOPE}, {<<"scopes">>, []}])},
         {fun cb_context:set_resp_status/2, success}]).

routes() -> [{list, <<"GET">>}, {create, <<"PUT">>}, {read, <<"GET">>},
             {update, <<"POST">>}, {delete, <<"DELETE">>}].
invoke(Kind, Verb, C) ->
    C1 = cb_context:set_req_verb(C, Verb),
    case Kind of
        list -> cb_scope_restrictions:validate(C1);
        create -> cb_scope_restrictions:validate(C1);
        _ -> cb_scope_restrictions:validate(C1, ?SCOPE)
    end.

with_seams(Fun) ->
    T = ets:new(scope_management_fixture, [public, set]),
    ets:insert(T, {calls, []}),
    Modules = [crossbar_doc, crossbar_view, kz_json_schema, kz_datamgr, kapps_config],
    try
        lists:foreach(fun(M) -> meck:new(M, [non_strict, no_link]) end, Modules),
        meck:expect(crossbar_doc, load, fun(Id, C, _Options) ->
            ?assertEqual(?SCOPE, Id), record(T, doc_load), C
        end),
        meck:expect(crossbar_doc, load_merge, fun(Id, C, _Options) ->
            ?assertEqual(?SCOPE, Id), record(T, doc_merge), C
        end),
        meck:expect(crossbar_view, get_doc_fun, fun() ->
            record(T, view_mapper), fun(J) -> J end
        end),
        meck:expect(crossbar_view, load, fun(C, View, Options) ->
            ?assertEqual(<<"scope_restrictions/crossbar_listing">>, View),
            record(T, {view_load, Options}), C
        end),
        meck:expect(kz_json_schema, load, fun(Id) ->
            ?assertEqual(<<"scope_restrictions">>, Id), record(T, schema_load), {ok, kz_json:new()}
        end),
        meck:expect(kz_json_schema, validate, fun(_Schema, Doc, _Options) ->
            record(T, schema_validate), {ok, Doc}
        end),
        %% Native v2 error formatting is identity; no schema/datastore read.
        meck:expect(kz_json_schema, build_error_message, fun(<<"v2">>, JObj) -> JObj end),
        meck:expect(kz_datamgr, open_cache_doc, fun(Db, User) ->
            ?assertEqual(kzs_util:format_account_db(?A), Db), ?assertEqual(?U, User),
            record(T, identity_read),
            case ets:lookup(T, identity) of [{identity, Result}] -> Result; [] -> {error, not_found} end
        end),
        meck:expect(kapps_config, get_binary, fun(_, _) -> undefined end),
        meck:expect(kapps_config, get_integer, fun(_, _) -> undefined end),
        meck:expect(kapps_config, get_is_true, fun(_, _, Default) -> Default end),
        meck:expect(kapps_config, is_true, fun(_, _, Default) -> Default end),
        meck:expect(kapps_config, get, fun(_, _, Default) -> Default end),
        Fun(T)
    after
        lists:foreach(fun(M) -> catch meck:unload(M) end, lists:reverse(Modules)),
        ets:delete(T)
    end.
record(T, Call) -> ets:insert(T, {calls, calls(T) ++ [Call]}).
calls(T) -> ets:lookup_element(T, calls, 2).
reset(T) -> ets:insert(T, {calls, []}).
forbidden(C) ->
    ?assertEqual(error, cb_context:resp_status(C)),
    ?assertEqual(403, cb_context:resp_error_code(C)).

deny_routes() ->
    with_seams(fun(T) ->
        C = cb_context:set_is_account_admin(context(), false),
        lists:foreach(fun({Kind, Verb}) ->
            reset(T), forbidden(invoke(Kind, Verb, C)), ?assertEqual([], calls(T))
        end, routes())
    end).

admin_routes() ->
    allowed_routes(fun(C) -> cb_context:set_is_account_admin(C, true) end).
super_routes() ->
    allowed_routes(fun(C) -> cb_context:set_is_superduper_admin(cb_context:set_is_account_admin(C, false), true) end).
allowed_routes(Role) ->
    with_seams(fun(T) ->
        lists:foreach(fun({Kind, Verb}) ->
            reset(T), Result = invoke(Kind, Verb, Role(context())),
            ?assertEqual(success, cb_context:resp_status(Result)),
            case {Kind, calls(T)} of
                {list, [view_mapper, {view_load, Options}]} ->
                    ?assertEqual(undefined, proplists:get_value(startkey, Options));
                {read, [view_mapper, {view_load, Options}]} ->
                    ?assertEqual(?SCOPE, proplists:get_value(startkey, Options)),
                    ?assertEqual(?SCOPE, proplists:get_value(endkey, Options));
                {create, [schema_load, schema_validate]} ->
                    ?assertEqual(?SCOPE, kz_doc:id(cb_context:doc(Result))),
                    ?assertEqual(<<"scope_restriction">>, kz_doc:type(cb_context:doc(Result)));
                {update, [schema_load, schema_validate, doc_merge]} -> ok;
                {delete, [doc_load]} -> ok;
                _ -> error(unexpected_validator_calls)
            end
        end, routes())
    end).

missing_identity() ->
    with_seams(fun(T) ->
        %% Do not preset account-admin: exercise the native context fallback.
        NoOwner = cb_context:set_auth_doc(context(), kz_json:new()),
        forbidden(invoke(delete, <<"DELETE">>, NoOwner)), ?assertEqual([], calls(T)),
        NoAccount = cb_context:set_auth_account_id(context(), undefined),
        forbidden(invoke(delete, <<"DELETE">>, NoAccount)), ?assertEqual([], calls(T)),
        lists:foreach(fun(Error) ->
            reset(T), ets:insert(T, {identity, Error}),
            forbidden(invoke(delete, <<"DELETE">>, context())),
            ?assertEqual([identity_read], calls(T))
        end, [{error, not_found}, {error, db_not_reachable}])
    end).

identity_roles() ->
    with_seams(fun(T) ->
        lists:foreach(fun(Role) ->
            reset(T), Doc = kz_json:from_list([{<<"_id">>, ?U}, {<<"priv_level">>, Role}]),
            ets:insert(T, {identity, {ok, Doc}}),
            Result = invoke(delete, <<"DELETE">>, context()),
            case Role of
                <<"admin">> ->
                    ?assertEqual(success, cb_context:resp_status(Result)),
                    ?assertEqual([identity_read, doc_load], calls(T));
                _ -> forbidden(Result), ?assertEqual([identity_read], calls(T))
            end
        end, [<<"user">>, <<"admin">>, <<"administrator">>])
    end).

capability_defaults() ->
    with_seams(fun(_T) ->
        ?assertEqual(1, cb_scope_restrictions:management_guard_version()),
        Modules = crossbar_config:autoload_modules(),
        ?assert(lists:member(<<"cb_scope_restrictions">>, Modules)),
        ?assertNot(lists:member(<<"cb_scope_retrictions">>, Modules)),
        ?assertEqual([<<"GET">>, <<"PUT">>], cb_scope_restrictions:allowed_methods()),
        ?assertEqual([<<"GET">>, <<"POST">>, <<"DELETE">>], cb_scope_restrictions:allowed_methods(?SCOPE))
    end).

configured_aliases() ->
    with_seams(fun(_T) ->
        lists:foreach(fun(Alias) ->
            Configured = [Alias, <<"cb_scope_restrictions">>, cb_users,
                          <<"cb_scope_retrictions_other">>, <<"prefix_cb_scope_retrictions">>,
                          <<"cb_agents_v1">>, <<"cb_users">>],
            meck:expect(kapps_config, get, fun(<<"crossbar">>, <<"autoload_modules">>, _Default) -> Configured end),
            ?assertEqual(lists:usort([<<"cb_scope_restrictions">>, <<"cb_users">>, <<"cb_agents">>,
                                     <<"cb_scope_retrictions_other">>, <<"prefix_cb_scope_retrictions">>]),
                         crossbar_config:autoload_modules())
        end, [<<"cb_scope_retrictions">>, cb_scope_retrictions,
              <<"cb_scope_retrictions_v1">>, cb_scope_retrictions_v2])
    end).
