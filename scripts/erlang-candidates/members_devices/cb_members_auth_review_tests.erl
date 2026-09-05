-module(cb_members_auth_review_tests).
-include_lib("eunit/include/eunit.hrl").
-define(A, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
context() -> cb_context:setters(cb_context:new(), [
    {fun cb_context:set_account_id/2, ?A},
    {fun cb_context:set_api_version/2, <<"v2">>},
    {fun cb_context:set_auth_token_type/2, 'x-auth-token'},
    {fun cb_context:set_auth_token/2, <<"memory-only-test-token">>},
    {fun cb_context:set_auth_doc/2, kz_json:from_list([{<<"method">>, <<"memory-test">>}])},
    {fun cb_context:set_req_verb/2, <<"GET">>},
    {fun cb_context:set_req_nouns/2, [{<<"members">>, [<<"devices">>]}, {<<"accounts">>, [?A]}]}]).

auth_matrix_test() ->
    ok=meck:new(crossbar_bindings,[no_link]),
    ok=meck:new(kz_auth_scope,[no_link]),
    try
        C=context(),
        Cases=[{[true],[false],true},{[false],[true],true},{[false],[false],false},
            {[],[],false},{[{stop,C}],[true],false},{[true],[{stop,C}],false},
            {[true,{stop,C}],[true],false},{[true],[true,{stop,C}],false},
            {[{'EXIT',bad_callback}],[true],false},{[true],[{error,bad_callback}],false},
            {[undefined],[true],false},{[{true,C}],[false],true}],
        lists:foreach(fun({Global,Module,Expected}) ->
            meck:expect(crossbar_bindings,pmap,fun(Event,_) ->
                case binary:match(Event,<<"allowed_scopes.">>) of
                    {_,_} -> [];
                    nomatch -> case binary:match(Event,<<"authorize.">>) of
                        {_,_} -> Module; nomatch -> Global end
                end end),
            ?assertEqual(Expected,cb_members:authorized(C))
        end,Cases)
    after meck:unload() end.

resource_scope_dispatch_test() ->
    ok=meck:new(crossbar_bindings,[no_link]),
    ok=meck:new(kz_auth_scope,[no_link]),
    try
        C=context(),
        meck:expect(crossbar_bindings,pmap,fun(Event,Payload) ->
            case binary:split(Event,<<"allowed_scopes.">>) of
                [_,Resource] ->
                    ?assertEqual(<<"memory-test">>,Payload),
                    [[<<Resource/binary,":GET">>]];
                [_] ->
                    case binary:match(Event,<<"authorize.">>) of
                        {_,_} -> [false]; nomatch -> [true] end
            end end),
        lists:foreach(fun(Denied) ->
            meck:expect(kz_auth_scope,all,fun(Token,Scopes) ->
                ?assertEqual(<<"memory-only-test-token">>,Token),
                Scopes =/= [<<Denied/binary,":GET">>]
            end),
            lists:foreach(fun(Resource) ->
                Scoped=case Resource of <<"members">> -> C; _ -> cb_members:scoped(C,Resource) end,
                ?assertEqual(Resource =/= Denied,cb_members:authorized(Scoped)),
                ?assertEqual(?A,cb_context:account_id(Scoped)),
                ?assertEqual(<<"GET">>,cb_context:req_verb(Scoped)),
                case Resource of <<"members">> -> ok; _ ->
                    ?assertEqual([{Resource,[]},{<<"accounts">>,[?A]}],cb_context:req_nouns(Scoped)),
                    ?assertEqual(<<"/v2/accounts/",?A/binary,"/",Resource/binary>>,cb_context:raw_path(Scoped))
                end
            end,[<<"members">>,<<"users">>,<<"devices">>])
        end,[<<"members">>,<<"users">>,<<"devices">>])
    after meck:unload() end.

malformed_scope_results_fail_closed_test() ->
    ok=meck:new(crossbar_bindings,[no_link]),
    ok=meck:new(kz_auth_scope,[no_link]),
    try
        meck:expect(kz_auth_scope,all,fun(_,Scopes) -> Scopes =/= [<<"deny">>] end),
        lists:foreach(fun({Scopes,Expected}) ->
            meck:expect(crossbar_bindings,pmap,fun(Event,_) ->
                case binary:match(Event,<<"allowed_scopes.">>) of
                    {_,_} -> Scopes; nomatch -> [true] end end),
            ?assertEqual(Expected,cb_members:authorized(context()))
        end,[{[],true},{[[]],true},{[[<<"allow">>],[<<"deny">>]],false},
             {[false],false},{[undefined],false},{[{stop,context()}],false},
             {[{error,scope_callback_failed}],false}])
    after meck:unload() end.
