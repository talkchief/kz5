%%% SPDX-License-Identifier: MPL-2.0
%%% Real JWT/preauthentication/restriction/hierarchy/scope code, offline providers.
%%% Validation only: no execute call, database write, AMQP worker or HTTP listener.
%%% Compile auth modules without -DTEST; especially cb_token_restrictions.
-module(acdc_queue_editor_real_auth_tests).
-compile({no_auto_import, [get/0]}).
-include_lib("eunit/include/eunit.hrl").
-include_lib("public_key/include/public_key.hrl").
-define(A, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(B, <<"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb">>).
-define(U, <<"11111111111111111111111111111111">>).
-define(V, <<"22222222222222222222222222222222">>).
-define(Q, <<"33333333333333333333333333333333">>).
-define(R, <<"44444444444444444444444444444444">>).
-define(M, <<"55555555555555555555555555555555">>).
-define(REQ, <<"66666666666666666666666666666666">>).
-define(REV, <<"1-11111111111111111111111111111111">>).

real_auth_test_() ->
    {setup, fun setup/0, fun teardown/1, fun(_) ->
        [{"restricted editor and underlying queue GET grants", fun queue_read_grants/0},
         {"embedded catalog denials remain explicit partial reads", fun catalog_read_grants/0},
         {"individual route GET and global media grants are distinct", fun embedded_special_grants/0},
         {"queue PATCH, roster POST and null-roster controls", fun queue_write_grants/0},
         {"callflow create/update/delete grants and null-route control", fun route_write_grants/0},
         {"changed selections require their permitted catalogs", fun selection_grants/0},
         {"real same-account, unrelated-account and descendant authorization", fun account_boundaries/0},
         {"expired signed JWT denied before editor reads", fun expired_tokens/0},
         {"real signed scope claims rechecked for each embedded resource", fun resource_scopes/0}]
    end}.

j(Pairs) -> kz_json:from_list(Pairs).
val(Key) -> [{Key, Value}] = ets:lookup(editor_real_auth, Key), Value.
inc(Key) -> ets:update_counter(editor_real_auth, Key, 1).
reset() ->
    ets:insert(editor_real_auth, [{target, ?A}, {descendant, false}, {denied, none},
        {user_only, false}, {global_media, true}, {required_scopes, false}, {has_route, true},
        {resource_reads, []}, {manifest_reads, 0}, {restriction_reads, 0},
        {identity_reads, 0}, {key_reads, 0}, {pipeline_stops, []}, {pipeline_editor_entries, 0}]),
    ok.

setup() ->
    Table = ets:new(editor_real_auth, [named_table, public]),
    reset(),
    Key = public_key:generate_key({rsa, 2048, 65537}),
    Public = #'RSAPublicKey'{modulus = Key#'RSAPrivateKey'.modulus,
                            publicExponent = Key#'RSAPrivateKey'.publicExponent},
    ets:insert(Table, {key, Key}),
    lists:foreach(fun(M) -> ok = meck:new(M, [no_link]) end,
        [kz_datamgr, kapps_config, kzd_accounts, kz_auth_keys, kz_auth_identity,
         cb_queues, cb_callflows, kz_amqp_worker]),
    ok = meck:new(crossbar_bindings, [passthrough, no_link]),
    meck:expect(crossbar_bindings, pmap, fun dispatch/2),
    meck:expect(kz_auth_keys, from_token,
        fun(#{header := #{<<"kid">> := <<"queue-editor-memory-only">>}}) ->
            inc(key_reads), {ok, Public}
        end),
    meck:expect(kz_auth_identity, token, fun(Token = #{payload := #{<<"account_id">> := ?A}}) ->
        inc(identity_reads), Token#{identify_verified => true}
    end),
    meck:expect(kapps_config, get_ne_binaries, fun(_, _, Default) -> Default end),
    meck:expect(kapps_config, get_integer,
        fun(<<"crossbar">>, <<"password_expiry_s">>) -> undefined end),
    %% An authorized global-media lookup reaches this unavailable in-memory
    %% provider, never a manifest file or an installed-language readiness claim.
    meck:expect(kapps_config, get_ne_binary,
        fun(<<"acdc.queues">>, <<"editor_language_capabilities_path">>) ->
            inc(manifest_reads), erlang:error(fixture_manifest_unavailable)
        end),
    meck:expect(kzd_accounts, is_superduper_admin, fun(_) -> false end),
    meck:expect(kzd_accounts, is_expired, fun(?A) -> false end),
    meck:expect(kzd_accounts, tree,
        fun(?B) -> case val(descendant) of true -> [?A]; false -> [] end end),
    meck:expect(kzd_accounts, is_in_account_hierarchy, fun(?A, ?B) -> val(descendant) end),
    meck:expect(kz_datamgr, open_cache_doc, fun auth_document/2),
    meck:expect(kz_datamgr, open_doc, fun document/2),
    meck:expect(kz_datamgr, get_results, fun inventory/3),
    %% Only schema/merge validation is substituted. No validator grants auth and
    %% no execute/save callback is installed. Auth decisions above remain real.
    meck:expect(cb_queues, validate, fun(C) -> validate_queue(C, undefined) end),
    meck:expect(cb_queues, validate, fun validate_queue/2),
    meck:expect(cb_callflows, validate, fun(C) -> validate_route(C, undefined) end),
    meck:expect(cb_callflows, validate, fun validate_route/2),
    Table.

teardown(Table) ->
    lists:foreach(fun meck:unload/1,
        [kz_datamgr, kapps_config, kzd_accounts, kz_auth_keys, kz_auth_identity,
         cb_queues, cb_callflows, kz_amqp_worker, crossbar_bindings]),
    ets:delete(Table).

dispatch(<<"v2_resource.early_authenticate">>, Context) -> [cb_token_auth:early_authenticate(Context)];
dispatch(<<"v2_resource.authorize">>, Context) ->
    [cb_simple_authz:authorize(Context), cb_token_restrictions:authorize(Context)];
%% Neither queues nor callflows registers a resource-specific authorize binding.
dispatch(<<"v2_resource.authorize.queues">>, [_Context|_]) -> [];
dispatch(<<"v2_resource.authorize.callflows">>, [_Context|_]) -> [];
dispatch(<<"v2_resource.authorize.users">>, [Context]) -> [cb_users:authorize(Context)];
dispatch(<<"v2_resource.authorize.media">>, [Context]) -> [cb_media:authorize(Context)];
dispatch(<<"v2_resource.authorize.phone_numbers">>, [Context]) -> [cb_phone_numbers:authorize(Context)];
dispatch(<<"v2_resource.allowed_scopes.", Resource/binary>>, <<"cb_user_auth">>) ->
    ?assert(lists:member(Resource, resources())),
    %% Fixture policy only, not a claim about globally configured scope names.
    case val(required_scopes) of true -> [[<<"fixture:", Resource/binary>>]]; false -> [] end;
dispatch(<<"v2_resource.error.get.queues">>, [{Req, Context}|_]) -> [{Req, Context}];
dispatch(<<"v2_resource.error.patch.queues">>, [{Req, Context}|_]) -> [{Req, Context}];
dispatch(<<"v2_resource.error.put.queues">>, [{Req, Context}|_]) -> [{Req, Context}];
dispatch(Event, _) -> erlang:error({unexpected_editor_auth_event, Event}).

resources() -> [<<"queues">>, <<"users">>, <<"media">>, <<"callflows">>, <<"phone_numbers">>].
auth_document(Db, <<"token_restrictions">>) ->
    ?assertEqual(kzs_util:format_account_db(?A), Db), inc(restriction_reads),
    {ok, j([{<<"restrictions">>, j([{<<"cb_user_auth">>, j([{<<"user">>, restrictions()}])}])}])};
auth_document(Db, ?U) ->
    ?assertEqual(kzs_util:format_account_db(?A), Db),
    {ok, j([{<<"_id">>, ?U}, {<<"priv_level">>, <<"user">>}])};
auth_document(_, _) -> erlang:error(unexpected_editor_auth_document).

restrictions() ->
    j([{Resource, [j([{<<"allowed_accounts">>, accounts(Resource)},
        {<<"rules">>, j([{Rule, [Verb || Verb <- Verbs, val(denied) =/= {Resource, Rule, Verb}]}
            || {Rule, Verbs} <- rules(Resource)])}])]} || Resource <- resources()]).
accounts(<<"media">>) ->
    %% crossbar_types.hrl defines the token-restriction catch-all as "_".
    case val(global_media) of true -> [<<"_">>]; false -> tenant_accounts() end;
accounts(_) -> tenant_accounts().
tenant_accounts() -> [<<"{AUTH_ACCOUNT_ID}">>, <<"{DESCENDANT_ACCOUNT_ID}">>].
rules(<<"queues">>) ->
    [{<<"editor">>, [<<"GET">>, <<"PUT">>]},
     {<<?Q/binary, "/editor">>, [<<"GET">>, <<"PATCH">>]},
     {<<"/">>, [<<"GET">>, <<"PUT">>]}, {?Q, [<<"GET">>, <<"PATCH">>]},
     {<<?Q/binary, "/roster">>, [<<"POST">>]}];
rules(<<"users">>) ->
    [{case val(user_only) of true -> ?U; false -> <<"/">> end, [<<"GET">>]}];
rules(<<"callflows">>) -> [{<<"/">>, [<<"GET">>, <<"PUT">>]}, {?R, [<<"GET">>, <<"POST">>, <<"DELETE">>]}];
rules(_) -> [{<<"/">>, [<<"GET">>]}].
deny(Resource, Rule, Verb) -> ets:insert(editor_real_auth, {denied, {Resource, Rule, Verb}}).

read_resource(Kind, Db) ->
    ?assertEqual(kzs_util:format_account_db(val(target)), Db),
    ets:insert(editor_real_auth, {resource_reads, [Kind|val(resource_reads)]}).
document(Db, <<"acdc_queue_editor_", _/binary>>) ->
    read_resource(receipt, Db), {error, not_found};
document(Db, ?Q) -> read_resource(queue, Db), {ok, queue()};
document(Db, <<"acdc_queue_extension_", _/binary>>) ->
    read_resource(extension, Db), {error, not_found};
document(_, _) -> erlang:error(unexpected_editor_document).
inventory(<<"system_auth">>, <<"scopes/crossbar_listing">>, [include_docs]) -> {ok, []};
inventory(Db, <<"crossbar_listings/by_type_id">>, Options) ->
    [Type] = proplists:get_value(startkey, Options),
    ?assertEqual(501, proplists:get_value(limit, Options)),
    ?assertEqual(false, proplists:get_value(reduce, Options)),
    ?assert(lists:member(include_docs, Options)), read_resource(Type, Db),
    Docs = case Type of
        <<"user">> -> users();
        <<"media">> -> [doc(?M, <<"media">>, [{<<"name">>, <<"Fixture media">>}])];
        <<"callflow">> -> routes()
    end,
    {ok, [j([{<<"doc">>, D}]) || D <- Docs]};
inventory(Db, <<"phone_numbers/crossbar_listing">>, Options) ->
    ?assertEqual([{limit, 501}, {reduce, false}], Options), read_resource(numbers, Db),
    {ok, [j([{<<"id">>, <<"+12025550199">>}, {<<"value">>, j([
        {<<"assigned_to">>, val(target)}, {<<"state">>, <<"in_service">>}])}])]};
inventory(_, _, _) -> erlang:error(unexpected_editor_view).
doc(Id, Type, Fields) -> j([{<<"_id">>, Id}, {<<"_rev">>, ?REV},
    {<<"pvt_type">>, Type}, {<<"pvt_account_id">>, val(target)}|Fields]).
queue() -> doc(?Q, <<"queue">>, [{<<"name">>, <<"Fixture queue">>}]).
users() -> [doc(Id, <<"user">>, [{<<"first_name">>, <<"Fixture">>}, {<<"enabled">>, true},
    {<<"password">>, <<"NEVER_RETURN">>}, {<<"queues">>, Queues}]) ||
    {Id, Queues} <- [{?U, [?Q]}, {?V, []}]].
routes() -> case val(has_route) of true -> [route()]; false -> [] end.
route() -> doc(?R, <<"callflow">>, [{<<"name">>, <<"Fixture route">>}, {<<"numbers">>, [<<"2099">>]},
    {<<"patterns">>, []}, {<<"flags">>, [<<"talkchief-acdc-managed">>, <<"talkchief-acdc-queue:", ?Q/binary>>]},
    {<<"flow">>, j([{<<"module">>, <<"acdc_member">>}, {<<"data">>, j([{<<"id">>, ?Q}])},
                   {<<"children">>, j([])}])}]).
validate_queue(C, QueueId) ->
    Original = case QueueId of undefined -> doc(?Q, <<"queue">>, []); ?Q -> queue() end,
    validated_doc(C, kz_json:merge_recursive(Original, cb_context:req_data(C))).
validate_route(C, RouteId) ->
    Original = case RouteId of undefined -> doc(?R, <<"callflow">>, []); ?R -> route() end,
    validated_doc(C, kz_json:merge_recursive(Original, cb_context:req_data(C))).
validated_doc(C, Doc) ->
    cb_context:setters(C, [{fun cb_context:set_doc/2, Doc}, {fun cb_context:set_resp_status/2, success}]).

signed_token(Expiry, Scopes) ->
    Header = kz_base64url:encode(kz_json:encode(j([{<<"typ">>, <<"JWT">>}, {<<"alg">>, <<"RS256">>},
        {<<"kid">>, <<"queue-editor-memory-only">>}]))),
    Claims = [{<<"account_id">>, ?A}, {<<"owner_id">>, ?U}, {<<"method">>, <<"cb_user_auth">>}, {<<"exp">>, Expiry}],
    Payload = kz_base64url:encode(kz_json:encode(j(case Scopes of undefined -> Claims;
        _ -> [{<<"scope">>, Scopes}|Claims] end))),
    Input = <<Header/binary, ".", Payload/binary>>,
    Signature = kz_base64url:encode(public_key:sign(Input, sha256, val(key))),
    <<Input/binary, ".", Signature/binary>>.
context(Verb, QueueId, Token) ->
    Account = val(target), Params = case QueueId of undefined -> [<<"editor">>]; _ -> [QueueId, <<"editor">>] end,
    Path = iolist_to_binary([<<"/v2/accounts/">>, Account, <<"/queues">>, [[<<"/">>, P] || P <- Params]]),
    cb_context:setters(cb_context:new(), [{fun cb_context:set_account_id/2, Account},
        {fun cb_context:set_auth_token_type/2, 'x-auth-token'}, {fun cb_context:set_auth_token/2, Token},
        {fun cb_context:set_api_version/2, <<"v2">>}, {fun cb_context:set_req_verb/2, Verb},
        {fun cb_context:set_raw_path/2, Path}, {fun cb_context:set_query_string/2, j([])},
        {fun cb_context:set_req_nouns/2, [{<<"queues">>, Params}, {<<"accounts">>, [Account]}]},
        {fun cb_context:set_db_name/2, kzs_util:format_account_db(Account)}]).
fresh_context(Verb, QueueId) -> context(Verb, QueueId, signed_token(erlang:system_time(second) + 3600, undefined)).
request(Context, QueueId) ->
    case api_util:is_early_authentic(#{}, Context) of
        {stop, _, Stopped} -> record_stop(preauthentication, Stopped);
        {true, Req, Authenticated} ->
            {true, Req1, Authenticated1} = api_util:is_authentic(Req, Authenticated),
            case api_util:is_permitted(Req1, Authenticated1) of
                {stop, _, Denied} -> record_stop(permission, Denied);
                {true, _, Permitted} ->
                    inc(pipeline_editor_entries),
                    case cb_context:req_verb(Permitted) of
                        <<"GET">> -> cb_acdc_queue_editor:get(Permitted, QueueId);
                        _ -> cb_acdc_queue_editor:validate_write(Permitted, QueueId)
                    end
            end
    end.
record_stop(Stage, Context) ->
    ets:insert(editor_real_auth, {pipeline_stops, [Stage|val(pipeline_stops)]}), Context.
get() -> request(fresh_context(<<"GET">>, ?Q), ?Q).
body() -> j([{<<"queue">>, j([{<<"name">>, <<"Edited">>}])}, {<<"roster">>, [?V]}, {<<"route">>, null},
    {<<"request_id">>, ?REQ}, {<<"revisions">>, j([{<<"queue">>, ?REV},
        {<<"users">>, j([{?U, ?REV}, {?V, ?REV}])},
        {<<"callflows">>, j([{kz_doc:id(R), ?REV} || R <- routes()])}])}]).
write(Body) -> request(cb_context:set_req_data(fresh_context(<<"PATCH">>, ?Q), Body), ?Q).
assert_no_writes() ->
    lists:foreach(fun(F) -> ?assertNot(meck:called(kz_datamgr, F, '_')) end,
        [save_doc, save_docs, del_doc, del_docs, ensure_saved, update_doc]),
    lists:foreach(fun({M, F}) -> ?assertNot(meck:called(M, F, '_')) end,
        [{cb_queues, put}, {cb_queues, post}, {cb_callflows, put}, {cb_callflows, post}, {cb_callflows, delete}]),
    ?assertEqual([], meck:history(kz_amqp_worker)).
assert_allowed(Context) ->
    ?assertEqual(success, cb_context:resp_status(Context)),
    ?assert(val(key_reads) > 0), ?assert(val(identity_reads) > 0), ?assert(val(restriction_reads) > 0),
    case cb_context:req_verb(Context) of
        <<"GET">> ->
            ?assert(kz_json:is_json_object(cb_context:resp_data(Context))),
            ?assertEqual(nomatch, binary:match(kz_json:encode(cb_context:resp_data(Context)), <<"NEVER_RETURN">>));
        _ ->
            %% Public write validation builds a private plan; only execute/1
            %% creates a response body. It must not run in this auth fixture.
            ?assertEqual(undefined, cb_context:resp_data(Context)),
            Plan = cb_context:fetch(Context, editor_plan),
            ?assert(is_map(Plan)), ?assert(maps:is_key(queue, Plan))
    end,
    assert_no_writes().
assert_denied(Code, Context) -> ?assertEqual(Code, cb_context:resp_error_code(Context)), assert_no_writes().
assert_early_denied(Code, Context) ->
    assert_denied(Code, Context), ?assertEqual([], val(resource_reads)), ?assertEqual(0, val(manifest_reads)).
assert_catalog_forbidden(Context, Key, ReadKind) ->
    assert_allowed(Context), Data = cb_context:resp_data(Context),
    ?assertEqual(false, kz_json:get_value([<<"catalogs">>, Key, <<"complete">>], Data)),
    ?assertEqual(<<"forbidden">>, kz_json:get_value([<<"catalogs">>, Key, <<"reason">>], Data)),
    ?assertNot(lists:member(ReadKind, val(resource_reads))).

queue_read_grants() ->
    reset(), assert_allowed(get()),
    lists:foreach(fun(Rule) -> reset(), deny(<<"queues">>, Rule, <<"GET">>), assert_early_denied(403, get()) end,
        [<<?Q/binary, "/editor">>, ?Q]),
    reset(), assert_allowed(request(fresh_context(<<"GET">>, undefined), undefined)),
    reset(), deny(<<"queues">>, <<"/">>, <<"GET">>),
    assert_early_denied(403, request(fresh_context(<<"GET">>, undefined), undefined)).
catalog_read_grants() ->
    lists:foreach(fun({Resource, Key, ReadKind}) ->
        reset(), deny(Resource, <<"/">>, <<"GET">>), C = get(),
        assert_catalog_forbidden(C, Key, ReadKind), D = cb_context:resp_data(C),
        case Resource of
            <<"users">> -> ?assertEqual([], kz_json:get_value(<<"users">>, D)),
                ?assertEqual([], kz_json:get_value(<<"roster">>, D)),
                ?assertEqual(j([]), kz_json:get_value([<<"revisions">>, <<"users">>], D));
            <<"callflows">> -> ?assertEqual([], kz_json:get_value([<<"callflows">>, <<"summaries">>], D)),
                ?assertEqual([], kz_json:get_value([<<"callflows">>, <<"routes">>], D));
            _ -> ?assertEqual([], kz_json:get_value(Key, D))
        end
    end, [{<<"users">>, <<"users">>, <<"user">>}, {<<"media">>, <<"media">>, <<"media">>},
          {<<"callflows">>, <<"callflows">>, <<"callflow">>}, {<<"phone_numbers">>, <<"numbers">>, numbers}]),
    reset(), ets:insert(editor_real_auth, {user_only, true}), assert_catalog_forbidden(get(), <<"users">>, <<"user">>).
embedded_special_grants() ->
    reset(), deny(<<"callflows">>, ?R, <<"GET">>), C = get(), assert_allowed(C), D = cb_context:resp_data(C),
    ?assertEqual(1, length(kz_json:get_value([<<"callflows">>, <<"summaries">>], D))),
    ?assertEqual([], kz_json:get_value([<<"callflows">>, <<"routes">>], D)),
    ?assertEqual(<<"forbidden">>, kz_json:get_value([<<"catalogs">>, <<"callflows">>, <<"reason">>], D)),
    reset(), ets:insert(editor_real_auth, {global_media, false}), Tenant = get(), assert_allowed(Tenant),
    ?assertEqual(true, kz_json:get_value([<<"catalogs">>, <<"media">>, <<"complete">>], cb_context:resp_data(Tenant))),
    ?assertEqual(<<"forbidden">>, kz_json:get_value([<<"catalogs">>, <<"system_media">>, <<"reason">>], cb_context:resp_data(Tenant))),
    ?assertEqual(0, val(manifest_reads)),
    reset(), Global = get(), assert_allowed(Global), ?assertEqual(1, val(manifest_reads)),
    ?assertEqual(<<"unverified_language_manifest">>,
        kz_json:get_value([<<"catalogs">>, <<"system_media">>, <<"reason">>], cb_context:resp_data(Global))).
queue_write_grants() ->
    reset(), assert_allowed(write(body())),
    reset(), deny(<<"queues">>, <<?Q/binary, "/editor">>, <<"PATCH">>),
    assert_early_denied(403, write(body())),
    reset(), deny(<<"queues">>, ?Q, <<"PATCH">>), assert_denied(403, write(body())),
    reset(), deny(<<"queues">>, <<?Q/binary, "/roster">>, <<"POST">>), assert_denied(403, write(body())),
    reset(), deny(<<"queues">>, <<?Q/binary, "/roster">>, <<"POST">>),
    assert_allowed(write(kz_json:set_value(<<"roster">>, null, body(), #{keep_null => true}))),
    reset(), deny(<<"users">>, <<"/">>, <<"GET">>),
    assert_denied(503, write(kz_json:set_value(<<"roster">>, null, body(), #{keep_null => true}))),
    reset(), CreateBody = kz_json:set_values([{<<"roster">>, null}, {[<<"revisions">>, <<"queue">>], null}], body(), #{keep_null => true}),
    Create = fun() -> request(cb_context:set_req_data(fresh_context(<<"PUT">>, undefined), CreateBody), undefined) end,
    assert_allowed(Create()),
    reset(), deny(<<"queues">>, <<"/">>, <<"PUT">>), assert_denied(403, Create()),
    reset(), deny(<<"queues">>, <<"editor">>, <<"PUT">>), assert_early_denied(403, Create()).
route_write_grants() ->
    lists:foreach(fun({HasRoute, Extension, Rule, Verb}) ->
        reset(), ets:insert(editor_real_auth, {has_route, HasRoute}),
        Body = kz_json:set_value(<<"route">>, j([{<<"extension">>, Extension}]), body()),
        assert_allowed(write(Body)),
        reset(), ets:insert(editor_real_auth, {has_route, HasRoute}), deny(<<"callflows">>, Rule, Verb),
        assert_denied(403, write(Body))
    end, [{false, <<"2098">>, <<"/">>, <<"PUT">>}, {true, <<"2098">>, ?R, <<"POST">>},
          {true, <<>>, ?R, <<"DELETE">>}]),
    reset(), deny(<<"callflows">>, ?R, <<"POST">>), assert_allowed(write(body())),
    reset(), deny(<<"callflows">>, <<"/">>, <<"GET">>), assert_allowed(write(body())),
    assert_denied(503, write(kz_json:set_value(<<"route">>, j([{<<"extension">>, <<"2098">>}]), body()))).
selection_grants() ->
    lists:foreach(fun({Resource, QueuePatch}) ->
        reset(), assert_allowed(write(kz_json:set_value(<<"queue">>, QueuePatch, body()))),
        reset(), deny(Resource, <<"/">>, <<"GET">>),
        assert_denied(503, write(kz_json:set_value(<<"queue">>, QueuePatch, body()))),
        assert_allowed(write(body()))
    end, [{<<"media">>, j([{<<"moh">>, ?M}])},
          {<<"phone_numbers">>, j([{<<"callback">>, j([{<<"outbound_caller_id">>, j([{<<"number">>, <<"+12025550199">>}])}])}])}]).
account_boundaries() ->
    reset(), assert_allowed(get()),
    reset(), ets:insert(editor_real_auth, {target, ?B}), assert_early_denied(403, get()),
    reset(), ets:insert(editor_real_auth, [{target, ?B}, {descendant, true}]), assert_allowed(get()).
expired_tokens() ->
    lists:foreach(fun(Offset) -> reset(), Token = signed_token(erlang:system_time(second) + Offset, undefined),
        ?assertEqual({error, token_expired}, crossbar_auth:validate_auth_token(Token)),
        assert_early_denied(401, request(context(<<"GET">>, ?Q, Token), ?Q)),
        ?assertEqual(0, val(identity_reads)), ?assertEqual(0, val(restriction_reads)), ?assert(val(key_reads) > 0)
    end, [-60, 0]),
    reset(), assert_allowed(get()).
resource_scopes() ->
    lists:foreach(fun(Missing) ->
        reset(), ets:insert(editor_real_auth, {required_scopes, true}),
        Scopes = kz_binary:join([<<"fixture:", R/binary>> || R <- resources(), R =/= Missing], <<" ">>),
        Token = signed_token(erlang:system_time(second) + 3600, Scopes),
        ?assertNot(kz_auth_scope:all(Token, [<<"fixture:", Missing/binary>>])),
        C = request(context(<<"GET">>, ?Q, Token), ?Q),
        case Missing of
            <<"queues">> ->
                %% api_util:enforce_scopes/3 stops before editor dispatch but
                %% does not populate resp_error_code. Record that real decision;
                %% do not invent a 403 in the in-memory response serializer.
                ?assertEqual([permission], val(pipeline_stops)),
                ?assertEqual(0, val(pipeline_editor_entries)),
                ?assertEqual([], val(resource_reads)), ?assertEqual(0, val(manifest_reads)),
                ?assertEqual(undefined, cb_context:resp_error_code(C)), assert_no_writes(),
                %% Independently retain the public editor recheck: with actual
                %% authenticated claims the missing queue scope is exactly 403.
                {true, _, Authenticated} = api_util:is_early_authentic(#{}, context(<<"GET">>, ?Q, Token)),
                assert_early_denied(403, cb_acdc_queue_editor:get(Authenticated, ?Q));
            <<"phone_numbers">> -> assert_catalog_forbidden(C, <<"numbers">>, numbers);
            <<"users">> -> assert_catalog_forbidden(C, Missing, <<"user">>);
            <<"callflows">> -> assert_catalog_forbidden(C, Missing, <<"callflow">>);
            <<"media">> -> assert_catalog_forbidden(C, Missing, <<"media">>)
        end
    end, resources()),
    reset(), ets:insert(editor_real_auth, {required_scopes, true}),
    All = kz_binary:join([<<"fixture:", R/binary>> || R <- resources()], <<" ">>),
    Token = signed_token(erlang:system_time(second) + 3600, All),
    ?assert(kz_auth_scope:all(Token, [<<"fixture:", R/binary>> || R <- resources()])),
    assert_allowed(request(context(<<"GET">>, ?Q, Token), ?Q)),
    ?assertEqual([], val(pipeline_stops)), ?assertEqual(1, val(pipeline_editor_entries)).
