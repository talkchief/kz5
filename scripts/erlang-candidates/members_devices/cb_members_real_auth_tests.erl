%%% SPDX-License-Identifier: MPL-2.0
%%% Real auth/authorization code, isolated event dispatch and in-memory stores.
%%% No live key, token, account, datastore, AMQP worker or HTTP listener is used.
-module(cb_members_real_auth_tests).
-include_lib("eunit/include/eunit.hrl").
-include_lib("public_key/include/public_key.hrl").
-define(A, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(B, <<"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb">>).
-define(U, <<"11111111111111111111111111111111">>).
-define(D, <<"33333333333333333333333333333333">>).
-define(REALM, <<"members-auth-test.invalid">>).

real_auth_test_() ->
    {setup,fun setup/0,fun teardown/1,fun(_) ->
        [{"restricted token permitted for all three collection reads",fun restricted_allow/0},
         {"members/users/devices restrictions each stop before inventory",fun restricted_denials/0},
         {"single-user grant does not authorize the users collection",fun collection_restriction/0},
         {"unrelated account principal denied; legitimate descendant allowed",fun account_boundary/0},
         {"expired signed JWT rejected by actual preauthentication",fun expired_tokens/0},
         {"actual JWT scope claims independently checked on all resources",fun resource_scopes/0},
         {"wrong path/database context denied before inventory",fun context_boundaries/0}]
    end}.

j(Pairs) -> kz_json:from_list(Pairs).
val(Key) -> [{Key,Value}]=ets:lookup(members_real_auth,Key),Value.
inc(Key) -> ets:update_counter(members_real_auth,Key,1).
reset() ->
    ets:insert(members_real_auth,[{target,?A},{descendant,false},{restrictions,allow},
        {required_scopes,false},{inventory_reads,0},{registrar_reads,0},{identity_reads,0},
        {key_reads,0},{restriction_reads,0}]).

setup() ->
    Table=ets:new(members_real_auth,[named_table,public]),
    reset(),
    %% Ephemeral test-only key: never read from disk or written to a token store.
    Key=public_key:generate_key({rsa,2048,65537}),
    Public=#'RSAPublicKey'{modulus=Key#'RSAPrivateKey'.modulus,
        publicExponent=Key#'RSAPrivateKey'.publicExponent},
    ets:insert(Table,{key,Key}),
    lists:foreach(fun(M)->ok=meck:new(M,[no_link]) end,
        [kz_datamgr,kapps_config,kzd_accounts,kapi_registration,kz_auth_keys,kz_auth_identity]),
    ok=meck:new(crossbar_bindings,[passthrough,no_link]),
    meck:expect(crossbar_bindings,pmap,fun dispatch/2),
    meck:expect(kz_auth_keys,from_token,fun(#{header := #{<<"kid">> := <<"members-memory-only">>}})->
        inc(key_reads),{ok,Public} end),
    meck:expect(kz_auth_identity,token,fun(Token=#{payload := #{<<"account_id">> := ?A}})->
        inc(identity_reads),Token#{identify_verified=>true} end),
    meck:expect(kapps_config,get_ne_binaries,fun(_,_,Default)->Default end),
    meck:expect(kapps_config,get_integer,fun(<<"crossbar">>,<<"password_expiry_s">>)->undefined end),
    meck:expect(kzd_accounts,is_superduper_admin,fun(_)->false end),
    meck:expect(kzd_accounts,is_expired,fun(?A)->false end),
    meck:expect(kzd_accounts,tree,fun(?B)->case val(descendant) of true -> [?A]; false -> [] end end),
    meck:expect(kzd_accounts,is_in_account_hierarchy,fun(?A,?B)->val(descendant) end),
    meck:expect(kzd_accounts,fetch_realm,fun(Account)->?assertEqual(val(target),Account),?REALM end),
    meck:expect(kz_datamgr,open_cache_doc,fun auth_document/2),
    meck:expect(kz_datamgr,get_results,fun inventory/3),
    meck:expect(kapi_registration,search_realm_regs,fun(?REALM,<<"detail">>)->
        inc(registrar_reads),[] end),
    Table.

teardown(Table) ->
    meck:unload(),ets:delete(Table).

%% These are the only substituted bindings. The real Crossbar result filtering,
%% preauthentication and permission pipeline run unchanged. Error serialization
%% is captured in memory instead of using Cowboy to send a response.
dispatch(<<"v2_resource.early_authenticate">>,Context) -> [cb_token_auth:early_authenticate(Context)];
dispatch(<<"v2_resource.authorize">>,Context) ->
    [cb_simple_authz:authorize(Context),cb_token_restrictions:authorize(Context)];
dispatch(<<"v2_resource.authorize.members">>,[_Context,<<"devices">>]) -> [];
dispatch(<<"v2_resource.authorize.users">>,[Context]) -> [cb_users:authorize(Context)];
dispatch(<<"v2_resource.authorize.devices">>,[Context]) -> [cb_devices:authorize(Context)];
dispatch(<<"v2_resource.allowed_scopes.",Resource/binary>>,<<"cb_user_auth">>) ->
    ?assert(lists:member(Resource,[<<"members">>,<<"users">>,<<"devices">>])),
    case val(required_scopes) of true -> [[<<Resource/binary,":GET">>]]; false -> [] end;
dispatch(<<"v2_resource.error.get.members">>,[{Req,Context},<<"devices">>]) -> [{Req,Context}];
dispatch(Event,_) -> erlang:error({unexpected_members_auth_event,Event}).

auth_document(Db,<<"token_restrictions">>) ->
    ?assertEqual(kzs_util:format_account_db(?A),Db),inc(restriction_reads),
    {ok,j([{<<"restrictions">>,j([{<<"cb_user_auth">>,j([{<<"user">>,restrictions()}])}])}])};
auth_document(Db,?U) ->
    ?assertEqual(kzs_util:format_account_db(?A),Db),
    {ok,j([{<<"_id">>,?U},{<<"priv_level">>,<<"user">>}])};
auth_document(_,_) -> erlang:error(unexpected_auth_document_read).

restrictions() ->
    j([{Resource,[j([{<<"allowed_accounts">>,[<<"{AUTH_ACCOUNT_ID}">>,<<"{DESCENDANT_ACCOUNT_ID}">>]},
        {<<"rules">>,j([{rule(Resource),[<<"GET">>]}])}])]} ||
        Resource <- [<<"members">>,<<"users">>,<<"devices">>],val(restrictions) =/= {deny,Resource}]).
rule(<<"members">>) -> <<"devices">>;
rule(<<"users">>) -> case val(restrictions) of user_only -> ?U; _ -> <<"/">> end;
rule(<<"devices">>) -> <<"/">>.

inventory(<<"system_auth">>,<<"scopes/crossbar_listing">>,[include_docs]) -> {ok,[]};
inventory(Db,<<"crossbar_listings/by_type_id">>,Options) ->
    ?assertEqual(kzs_util:format_account_db(val(target)),Db),
    ?assert(lists:member(include_docs,Options)),?assertEqual(false,proplists:get_value(reduce,Options)),
    inc(inventory_reads),
    Doc=case proplists:get_value(startkey,Options) of
        [<<"user">>] -> ?assertEqual(27,proplists:get_value(limit,Options)),
            doc(?U,<<"user">>,[{<<"name">>,<<"Fixture member">>},{<<"password">>,<<"NEVER_RETURN">>}]);
        [<<"device">>] -> ?assertEqual(1001,proplists:get_value(limit,Options)),
            doc(?D,<<"device">>,[{<<"owner_id">>,?U},{<<"device_type">>,<<"sip_device">>},
                {<<"sip">>,j([{<<"username">>,<<"fixture">>},{<<"password">>,<<"NEVER_RETURN">>}])}])
    end,
    {ok,[j([{<<"doc">>,Doc}])]};
inventory(_,_,_) -> erlang:error(unexpected_auth_view_read).
doc(Id,Type,Fields) -> j([{<<"_id">>,Id},{<<"pvt_type">>,Type},{<<"pvt_account_id">>,val(target)}|Fields]).

signed_token(Expiry,Scopes) ->
    Header=kz_base64url:encode(kz_json:encode(j([{<<"typ">>,<<"JWT">>},{<<"alg">>,<<"RS256">>},
        {<<"kid">>,<<"members-memory-only">>}]))),
    Claims=[{<<"account_id">>,?A},{<<"owner_id">>,?U},{<<"method">>,<<"cb_user_auth">>},{<<"exp">>,Expiry}],
    Payload=kz_base64url:encode(kz_json:encode(j(case Scopes of undefined -> Claims;
        _ -> [{<<"scope">>,Scopes}|Claims] end))),
    Input = <<Header/binary,".",Payload/binary>>,
    Signature=kz_base64url:encode(public_key:sign(Input,sha256,val(key))),
    <<Input/binary,".",Signature/binary>>.
context(Token) ->
    Account=val(target),
    cb_context:setters(cb_context:new(),[{fun cb_context:set_account_id/2,Account},
        {fun cb_context:set_auth_token_type/2,'x-auth-token'},{fun cb_context:set_auth_token/2,Token},
        {fun cb_context:set_api_version/2,<<"v2">>},{fun cb_context:set_req_verb/2,<<"GET">>},
        {fun cb_context:set_raw_path/2,<<"/v2/accounts/",Account/binary,"/members/devices">>},
        {fun cb_context:set_req_nouns/2,[{<<"members">>,[<<"devices">>]},{<<"accounts">>,[Account]}]},
        {fun cb_context:set_db_name/2,kzs_util:format_account_db(Account)},
        {fun cb_context:set_query_string/2,j([])}]).
fresh_context() -> context(signed_token(erlang:system_time(second)+3600,undefined)).
request(Context) ->
    case api_util:is_early_authentic(#{},Context) of
        {stop,_,Stopped} -> Stopped;
        {true,Req,Authenticated} ->
            {true,Req1,Authenticated1}=api_util:is_authentic(Req,Authenticated),
            case api_util:is_permitted(Req1,Authenticated1) of
                {stop,_,Denied} -> Denied;
                {true,_,Permitted} -> cb_members:validate(Permitted,<<"devices">>)
            end
    end.
assert_denied(Code,Context) ->
    ?assertEqual(Code,cb_context:resp_error_code(Context)),
    ?assertEqual(undefined,kz_json:get_value(<<"items">>,cb_context:resp_data(Context))),
    ?assertEqual(0,val(inventory_reads)),?assertEqual(0,val(registrar_reads)),assert_no_writes().
assert_no_writes() ->
    lists:foreach(fun(F)->?assertNot(meck:called(kz_datamgr,F,'_')) end,
        [save_doc,save_docs,del_doc,del_docs,ensure_saved,update_doc]).
assert_allowed(Context) ->
    ?assertEqual(success,cb_context:resp_status(Context)),D=cb_context:resp_data(Context),
    ?assertEqual(1,kz_json:get_value(<<"count">>,D)),
    ?assertEqual(2,val(inventory_reads)),?assertEqual(1,val(registrar_reads)),
    ?assert(val(restriction_reads)>=3),?assert(val(key_reads)>0),?assert(val(identity_reads)>0),
    ?assertEqual(<<"no-store">>,maps:get(<<"cache-control">>,cb_context:resp_headers(Context))),
    ?assertEqual(nomatch,binary:match(kz_json:encode(D),<<"NEVER_RETURN">>)),assert_no_writes().

restricted_allow() -> reset(),assert_allowed(request(fresh_context())).
restricted_denials() ->
    lists:foreach(fun(Resource)->reset(),ets:insert(members_real_auth,{restrictions,{deny,Resource}}),
        assert_denied(403,request(fresh_context())),?assert(val(restriction_reads)>0)
    end,[<<"members">>,<<"users">>,<<"devices">>]).
collection_restriction() ->
    reset(),ets:insert(members_real_auth,{restrictions,user_only}),assert_denied(403,request(fresh_context())).
account_boundary() ->
    reset(),ets:insert(members_real_auth,{target,?B}),assert_denied(403,request(fresh_context())),
    reset(),ets:insert(members_real_auth,[{target,?B},{descendant,true}]),assert_allowed(request(fresh_context())).
expired_tokens() ->
    lists:foreach(fun(Offset)->reset(),Now=erlang:system_time(second),
        Context=context(signed_token(Now+Offset,undefined)),
        ?assertEqual({error,token_expired},crossbar_auth:validate_auth_token(cb_context:auth_token(Context))),
        assert_denied(401,request(Context)),?assertEqual(0,val(restriction_reads)),
        ?assertEqual(0,val(identity_reads)),?assert(val(key_reads)>0)
    end,[-60,0]),
    reset(),assert_allowed(request(fresh_context())).
resource_scopes() ->
    Resources=[<<"members">>,<<"users">>,<<"devices">>],
    lists:foreach(fun(Missing)->reset(),ets:insert(members_real_auth,{required_scopes,true}),
        Scopes=kz_binary:join([<<R/binary,":GET">>||R<-Resources,R=/=Missing],<<" ">>),
        {true,_,Authenticated}=api_util:is_early_authentic(#{},context(signed_token(erlang:system_time(second)+3600,Scopes))),
        %% Exercise the resource's stricter all-three recheck, not a canned scope
        %% predicate. The configured scope callback itself is a fixture binding.
        assert_denied(403,cb_members:validate(Authenticated,<<"devices">>))
    end,Resources),
    reset(),ets:insert(members_real_auth,{required_scopes,true}),
    All=kz_binary:join([<<R/binary,":GET">>||R<-Resources],<<" ">>),
    assert_allowed(request(context(signed_token(erlang:system_time(second)+3600,All)))).
context_boundaries() ->
    lists:foreach(fun(Change)->reset(),
        {true,_,Authenticated}=api_util:is_early_authentic(#{},fresh_context()),
        assert_denied(403,cb_members:validate(Change(Authenticated),<<"devices">>))
    end,[fun(C)->cb_context:set_db_name(C,kzs_util:format_account_db(?B)) end,
        fun(C)->cb_context:set_req_nouns(C,[{<<"members">>,[<<"devices">>]},{<<"accounts">>,[?B]}]) end]).
