%%% Actual production cb_agents and native binding/authorization dispatch.
%%% Broker declarations, global policy and terminal HTTP renderer are controlled.
-module(acdc_agent_status_authorization_tests).
-include_lib("eunit/include/eunit.hrl").
-export([global_allow/1,global_deny/1]).
-define(A, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(U, <<"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb">>).

setup() ->
    meck:new([kapi_acdc_agent,kapi_acdc_stats],[non_strict,no_link]),
    meck:expect(kapi_acdc_agent,declare_exchanges,fun()->ok end),
    meck:expect(kapi_acdc_stats,declare_exchanges,fun()->ok end),
    %% Keep actual is_permitted dispatch, replacing only its terminal renderer.
    meck:new(api_util,[passthrough,no_link]),
    meck:expect(api_util,stop,fun(Req,C)->{stop,Req,C} end),
    {ok,Pid}=kazoo_bindings:start_link(),unlink(Pid),
    Table=ets:new(kazoo_bindings:table_id(),kazoo_bindings:table_options()),
    true=ets:give_away(Table,Pid,fixture),true=gen_server:call(Pid,is_ready),
    ok=cb_agents:init(),Pid.
cleanup(Pid) ->
    try gen_server:stop(Pid)
    after meck:unload([api_util,kapi_acdc_agent,kapi_acdc_stats]) end.
global_allow(_) -> true.
global_deny(_) -> false.
context(Verb,Params) ->
    cb_context:setters(cb_context:new(),[
        {fun cb_context:set_api_version/2,<<"v2">>},
        {fun cb_context:set_account_id/2,?A},
        {fun cb_context:set_auth_account_id/2,?A},
        {fun cb_context:set_auth_token_type/2,basic},
        {fun cb_context:set_resp_status/2,success},
        {fun cb_context:set_is_superduper_admin/2,false},
        {fun cb_context:set_req_verb/2,Verb},
        {fun cb_context:set_req_nouns/2,[{<<"agents">>,Params},{<<"accounts">>,[?A]}]},
        {fun cb_context:set_raw_path/2,iolist_to_binary([<<"/v2/accounts/">>,?A,
            <<"/agents">>,[[<<"/">>,P] || P<-Params]])}]).
binding(C,Params) -> crossbar_bindings:pmap(<<"v2_resource.authorize.agents">>,[C|Params]).
with_policy(Fun,Work) ->
    ok=crossbar_bindings:bind(<<"*.authorize">>,?MODULE,Fun),
    try Work()
    after crossbar_bindings:flush_mod(?MODULE),true=gen_server:call(whereis(kazoo_bindings),is_ready) end.

authorization_test_() -> {setup,fun setup/0,fun cleanup/1,fun(_)->[
    {"POST status explicitly abstains instead of throwing before native dispatch",fun()->
        ?assertEqual(false,cb_agents:authorize(context(<<"POST">>,[?U,<<"status">>]),?U,<<"status">>))
    end},
    {"registered GET and POST status callback returns false without EXIT",fun()->
        lists:foreach(fun(Verb)->
            C=context(Verb,[?U,<<"status">>]),
            ?assertEqual([false],binding(C,[?U,<<"status">>])),
            ?assert(lists:member(Verb,cb_agents:allowed_methods(?U,<<"status">>)))
        end,[<<"GET">>,<<"POST">>])
    end},
    {"native public authorization allows GET and POST only with global grant",fun()->
        with_policy(global_allow,fun()->
            lists:foreach(fun(Verb)->
                C=context(Verb,[?U,<<"status">>]),
                ?assertMatch({true,fixture_request,_},api_util:is_permitted(fixture_request,C))
            end,[<<"GET">>,<<"POST">>])
        end)
    end},
    {"native public authorization denies GET and POST without global grant",fun()->
        with_policy(global_deny,fun()->
            lists:foreach(fun(Verb)->
                C=context(Verb,[?U,<<"status">>]),
                {stop,fixture_request,Denied}=api_util:is_permitted(fixture_request,C),
                ?assertEqual(403,cb_context:resp_error_code(Denied))
            end,[<<"GET">>,<<"POST">>])
        end)
    end},
    {"GET list and detail callbacks retain native abstention",fun()->
        [?assertEqual([false],binding(context(<<"GET">>,P),P)) || P<-[[],[?U]]]
    end},
    {"restart callback retains explicit admin grant and nonadmin halt",fun()->
        C=context(<<"POST">>,[?U,<<"restart">>]),
        ?assertEqual([true],binding(cb_context:set_is_superduper_admin(C,true),[?U,<<"restart">>])),
        [{halt,Denied}]=binding(C,[?U,<<"restart">>]),
        ?assertEqual(403,cb_context:resp_error_code(Denied))
    end}
] end}.
