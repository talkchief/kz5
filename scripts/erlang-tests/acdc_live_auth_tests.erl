%%% Real fresh cb_token_auth path and real local Crossbar binding registry.
%%% Token/DB/account/scope providers are controlled: no real credentials, HTTP,
%%% sockets or services. Expiry tests exercise native handling of token_expired,
%%% not cryptographic JWT validation or cache-independent revocation.
-module(acdc_live_auth_tests).
-include_lib("eunit/include/eunit.hrl").
-export([global_auth/1, scope/1, other_auth/1, internal_error_auth/2]).
-define(A, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(B, <<"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb">>).
-define(Q, <<"11111111111111111111111111111111">>).
-define(T, acdc_live_auth_fixture).
j(P) -> kz_json:from_list(P).
claims(A) -> j([{<<"account_id">>,A},{<<"method">>,<<"cb_user_auth">>}]).
doc() -> j([{<<"_id">>,?Q},{<<"pvt_type">>,<<"queue">>},{<<"pvt_account_id">>,?A}]).
set(K,V) -> ets:insert(?T,{K,V}).
get_state(K) -> [{K,V}]=ets:lookup(?T,K),V.
bump(K) -> ets:update_counter(?T,K,1).
reset() ->
    [set(K,V) || {K,V}<-[{token_result,{ok,claims(?A)}},{token_calls,0},{doc_calls,0},
        {doc_result,{ok,doc()}},{deny,none},{scope,true},{seen,[]},{allow_account,?A},{other,false}]],ok.
setup() ->
    ets:new(?T,[named_table,public]), reset(),
    meck:new([crossbar_auth,kzd_accounts,kz_datamgr,kz_auth_scope,kapi_acdc_agent,kapi_acdc_stats],[non_strict,no_link]),
    meck:expect(kapi_acdc_agent,declare_exchanges,fun()->ok end),
    meck:expect(kapi_acdc_stats,declare_exchanges,fun()->ok end),
    meck:expect(crossbar_auth,validate_auth_token,fun(Token,Options) ->
        bump(token_calls),set(last_token,Token),
        ?assertEqual([{<<"proxy_ips">>,[]}],Options),
        case get_state(token_result) of throw_error -> error(private_token_detail); V -> V end
    end),
    meck:expect(kzd_accounts,is_expired,fun(_)->false end),
    meck:expect(kzd_accounts,is_superduper_admin,fun(_)->false end),
    meck:expect(kz_datamgr,open_doc,fun(Db,Q) ->
        bump(doc_calls),?assertEqual(kzs_util:format_account_db(?A),Db),?assertEqual(?Q,Q),get_state(doc_result)
    end),
    meck:expect(kz_auth_scope,all,fun(Token,[<<"fixture:queues">>]) ->
        ?assertEqual(get_state(last_token),Token),get_state(scope)
    end),
    {ok,Pid}=kazoo_bindings:start_link(),unlink(Pid),
    Table=ets:new(kazoo_bindings:table_id(),kazoo_bindings:table_options()),
    true=ets:give_away(Table,Pid,fixture),true=gen_server:call(Pid,is_ready),
    init_bindings(),Pid.
init_bindings() ->
    ok=cb_token_auth:init(),
    %% Actual native agent registration, including its read/restart authorizer.
    %% Only broker exchange declarations above are controlled.
    ok=cb_agents:init(),
    %% Actual queue registration used by cb_queues:init, without its unrelated
    %% broker exchange declarations. This is a real binding, not a loaded-name mock.
    ok=crossbar_bindings:bind(<<"*.allowed_methods.queues">>,cb_queues,allowed_methods),
    fixture_bindings().
fixture_bindings() ->
    ok=crossbar_bindings:bind(<<"*.authorize">>,?MODULE,global_auth),
    ok=crossbar_bindings:bind(<<"*.allowed_scopes.queues">>,?MODULE,scope).
cleanup(Pid) ->
    gen_server:stop(Pid),
    meck:unload([crossbar_auth,kzd_accounts,kz_datamgr,kz_auth_scope,kapi_acdc_agent,kapi_acdc_stats]),
    ets:delete(?T).
unbind_module(Module) ->
    crossbar_bindings:flush_mod(Module),true=gen_server:call(whereis(kazoo_bindings),is_ready).
restore_fixture_bindings() ->
    %% Also runs after a failed assertion, so a missing scope callback cannot
    %% silently weaken later tests. Remove only this fixture's responders.
    unbind_module(?MODULE),fixture_bindings(),reset().
restore_native_bindings() ->
    unbind_module(cb_token_auth),unbind_module(cb_queues),
    ok=cb_token_auth:init(),
    ok=crossbar_bindings:bind(<<"*.allowed_methods.queues">>,cb_queues,allowed_methods),reset().

global_auth(C) ->
    [{Resource,Params},{<<"accounts">>,[?A]}]=cb_context:req_nouns(C),
    ?assert(lists:member(Resource,[<<"queues">>,<<"agents">>])),
    ?assertEqual(<<"GET">>,cb_context:req_verb(C)),
    ?assertEqual(<<"v2">>,cb_context:api_version(C)),
    ?assertEqual([],kz_json:to_proplist(cb_context:query_string(C))),
    ?assertEqual(?A,cb_context:account_id(C)),
    ?assertEqual(kzs_util:format_account_db(?A),cb_context:db_name(C)),
    ?assertEqual(iolist_to_binary([<<"/v2/accounts/">>,?A,<<"/">>,Resource,
        [[<<"/">>,P] || P<-Params]]),cb_context:raw_path(C)),
    set(seen,get_state(seen)++[Params]),
    cb_context:auth_account_id(C)=:=get_state(allow_account) andalso Params=/=get_state(deny).
scope(<<"cb_user_auth">>) -> [<<"fixture:queues">>].
other_auth(_) -> get_state(other).
internal_error_auth(_,_) -> error(private_resource_authorizer_failure).
fresh() -> acdc_live_auth:fresh_token(<<"offline-token">>,?A,?Q).

authorization_test_() -> {setup,fun setup/0,fun cleanup/1,fun(_)->[
    {"real fresh auth and global-only resource permissions",fun() ->
        reset(), {ok,C}=fresh(),
        ?assertEqual(?A,cb_context:auth_account_id(C)),
        ?assertEqual(<<"offline-token">>,cb_context:auth_token(C)),
        ?assertEqual([[?Q,<<"live">>],[<<"stats">>],[?Q]],get_state(seen)),
        ?assertEqual(1,get_state(token_calls)),?assertEqual(1,get_state(doc_calls)),
        ?assertEqual([],crossbar_bindings:pmap(<<"v2_resource.authorize.queues">>,[C,?Q])),
        ?assertEqual([<<"GET">>],cb_queues:allowed_methods(?Q,<<"live">>))
    end},
    {"invalid scope and token rejected before provider calls",fun() ->
        reset(),
        [?assertEqual({error,invalid_scope},acdc_live_auth:fresh_token(<<"offline-token">>,A,Q)) ||
            {A,Q}<-[{<<"*">>,?Q},{?A,<<"#">>},{?A,<<"QUEUE">>},{binary:copy(<<"A">>,32),?Q},{?A,[?Q]}]],
        [?assertEqual({error,invalid_token},acdc_live_auth:fresh_token(Token,?A,?Q)) ||
            Token<-[undefined,<<>>,<<"bad\ntoken">>,<<"bad token">>,binary:copy(<<"x">>,16385),j([])]],
        ?assertEqual(0,get_state(token_calls)),?assertEqual(0,get_state(doc_calls))
    end},
    {"current token revalidated after provider expiry and replacement",fun() ->
        reset(),{ok,_}=fresh(),set(token_result,{error,token_expired}),
        ?assertEqual({error,authentication_failed},fresh()),?assertEqual(2,get_state(token_calls)),
        ?assertEqual(1,get_state(doc_calls)),
        set(token_result,{ok,claims(?B)}),
        ?assertEqual({error,forbidden},acdc_live_auth:fresh_token(<<"replacement-token">>,?A,?Q)),
        ?assertEqual(<<"replacement-token">>,get_state(last_token)),
        %% Delegated access is decided by current resource policy, not by
        %% rewriting the auth account to the requested target account.
        set(allow_account,?B),{ok,C}=acdc_live_auth:fresh_token(<<"replacement-token">>,?A,?Q),
        ?assertEqual(?B,cb_context:auth_account_id(C)),?assertEqual(?A,cb_context:account_id(C)),
        ?assertEqual(?B,kz_json:get_value(<<"account_id">>,cb_context:auth_doc(C)))
    end},
    {"each live stats and queue permission can deny",fun() ->
        [begin reset(),set(deny,Denied),?assertEqual({error,forbidden},fresh()),
            ?assertEqual(0,get_state(doc_calls)) end || Denied<-[[?Q,<<"live">>],[<<"stats">>],[?Q]]],
        reset(),set(scope,false),?assertEqual({error,forbidden},fresh()),?assertEqual(0,get_state(doc_calls))
    end},
    {"scope absence retains native policy but no authorizer never authorizes",fun() ->
        reset(),
        try
            {ok,deleted_binding}=kazoo_bindings:unbind(<<"*.allowed_scopes.queues">>,?MODULE,scope),
            {ok,_}=fresh(),
            {ok,deleted_binding}=kazoo_bindings:unbind(<<"*.authorize">>,?MODULE,global_auth),
            ?assertEqual({error,forbidden},fresh())
        after restore_fixture_bindings() end
    end},
    {"local native token and queue bindings required and recoverable",fun() ->
        reset(),
        try
            unbind_module(cb_token_auth),
            ?assertEqual({error,local_authorization_unavailable},fresh()),?assertEqual(0,get_state(token_calls)),
            ok=cb_token_auth:init(),unbind_module(cb_queues),
            ?assertEqual({error,local_authorization_unavailable},fresh()),?assertEqual(0,get_state(token_calls)),
            ok=crossbar_bindings:bind(<<"*.allowed_methods.queues">>,cb_queues,allowed_methods),{ok,_}=fresh()
        after restore_native_bindings() end
    end},
    {"tenant-owned valid queue document required",fun() ->
        [begin reset(),set(doc_result,{ok,Bad}),?assertEqual({error,forbidden},fresh()) end ||
            Bad<-[kz_json:set_value(<<"_id">>,?B,doc()),kz_json:set_value(<<"pvt_account_id">>,?B,doc()),
                kz_json:set_value(<<"pvt_type">>,<<"device">>,doc()),
                kz_json:set_value(<<"_deleted">>,true,doc()),kz_json:set_value(<<"pvt_deleted">>,true,doc())]],
        reset(),set(doc_result,{error,not_found}),?assertEqual({error,forbidden},fresh()),
        set(doc_result,{error,timeout}),?assertEqual({error,queue_unavailable},fresh())
    end},
    {"malformed current claims and provider errors cannot reuse old identity",fun() ->
        reset(),{ok,_}=fresh(),
        [begin set(token_result,{ok,Claims}),?assertEqual({error,authentication_failed},fresh()) end ||
            Claims<-[j([{<<"method">>,<<"cb_user_auth">>}]),claims(<<"*">>)]],
        set(token_result,throw_error),?assertEqual({error,authorization_unavailable},fresh())
    end},
    {"malformed authorizer results fail closed without changing false-neutral semantics",fun() ->
        reset(),
        try
            ok=crossbar_bindings:bind(<<"*.authorize">>,?MODULE,other_auth),
            {ok,_}=fresh(),
            set(other,unexpected),?assertEqual({error,forbidden},fresh()),
            set(other,{stop,ignored}),?assertEqual({error,forbidden},fresh()),
            {ok,updated_binding}=kazoo_bindings:unbind(<<"*.authorize">>,?MODULE,other_auth)
        after restore_fixture_bindings() end
    end},
    {"extracted embedded permission retains sanitization and throw contract",fun() ->
        reset(),{ok,C}=fresh(),
        Dirty=cb_context:setters(C,[{fun cb_context:set_query_string/2,j([{<<"page_size">>,999}])},
            {fun cb_context:set_req_verb/2,<<"POST">>},{fun cb_context:set_doc/2,doc()}]),
        ?assertEqual(ok,acdc_live_auth:permit(Dirty,[?Q])),
        set(deny,[?Q]),?assertThrow({live_error,403,<<"queue_live_resource_forbidden">>},acdc_live_auth:permit(Dirty,[?Q]))
    end},
    {"real agent read binding abstains while global allow still authorizes",fun() ->
        reset(),{ok,C}=fresh(),
        lists:foreach(fun(Params)->
            AgentC=agent_context(C,Params,<<"GET">>),
            ?assertEqual([false],crossbar_bindings:pmap(<<"v2_resource.authorize.agents">>,[AgentC|Params])),
            ?assertEqual(ok,acdc_live_auth:permit(C,<<"agents">>,Params))
        end,[[],[?Q],[?Q,<<"status">>]])
    end},
    {"agent read abstention never grants without positive global authority",fun() ->
        reset(),{ok,C}=fresh(),set(allow_account,?B),
        lists:foreach(fun(Params)->
            ?assertThrow({live_error,403,<<"queue_live_resource_forbidden">>},
                acdc_live_auth:permit(C,<<"agents">>,Params))
        end,[[],[?Q],[?Q,<<"status">>]])
    end},
    {"native agent restart restrictions and non-GET failures remain",fun() ->
        reset(),{ok,C}=fresh(),
        Restart=agent_context(C,[?Q,<<"restart">>],<<"POST">>),
        Denied=cb_context:set_is_superduper_admin(Restart,false),
        ?assertMatch([{halt,_}],crossbar_bindings:pmap(<<"v2_resource.authorize.agents">>,
            [Denied,?Q,<<"restart">>])),
        Allowed=cb_context:set_is_superduper_admin(Restart,true),
        ?assertEqual([true],crossbar_bindings:pmap(<<"v2_resource.authorize.agents">>,
            [Allowed,?Q,<<"restart">>])),
        ?assertThrow({live_error,403,<<"queue_live_resource_forbidden">>},
            acdc_live_auth:permit(cb_context:set_is_superduper_admin(C,false),<<"agents">>,[?Q,<<"restart">>])),
        lists:foreach(fun(Params)->
            AgentC=agent_context(C,Params,<<"POST">>),
            ?assertMatch([{'EXIT',_}],crossbar_bindings:pmap(<<"v2_resource.authorize.agents">>,[AgentC|Params]))
        end,[[],[?Q],[?Q,<<"status">>]])
    end},
    {"internal agent authorizer exceptions are not swallowed as abstention",fun() ->
        reset(),{ok,C}=fresh(),
        try
            ok=crossbar_bindings:bind(<<"*.authorize.agents">>,?MODULE,internal_error_auth),
            ?assertThrow({live_error,403,<<"queue_live_resource_forbidden">>},
                acdc_live_auth:permit(C,<<"agents">>,[?Q]))
        after restore_fixture_bindings() end,
        ?assertEqual(ok,acdc_live_auth:permit(C,<<"agents">>,[?Q]))
    end}
] end}.

agent_context(C,Params,Verb) ->
    cb_context:setters(C,[{fun cb_context:set_req_verb/2,Verb},
        {fun cb_context:set_req_nouns/2,[{<<"agents">>,Params},{<<"accounts">>,[?A]}]},
        {fun cb_context:set_raw_path/2,iolist_to_binary([<<"/v2/accounts/">>,?A,<<"/agents">>,
            [[<<"/">>,P] || P<-Params]])}]).
