%%% SPDX-License-Identifier: MPL-2.0
%%% Memory-only transport/catalog mocks. Never loads a live node or calls HTTP.
-module(cb_members_tests).
-include_lib("eunit/include/eunit.hrl").
-include_lib("couchbeam/include/couchbeam.hrl").
-define(A, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(U, <<"11111111111111111111111111111111">>).
-define(V, <<"22222222222222222222222222222222">>).
-define(D, <<"33333333333333333333333333333333">>).
-define(REALM, <<"members-test.invalid">>).
j(P) -> kz_json:from_list(P).
doc(Id, Type, Values) -> j([{<<"_id">>, Id}, {<<"pvt_type">>, Type}, {<<"pvt_account_id">>, ?A}|Values]).
user(Id) -> doc(Id, <<"user">>, [{<<"first_name">>, <<"Fixture">>}, {<<"password">>, <<"SECRET_SENTINEL">>}]).
device() -> doc(?D, <<"device">>, [{<<"owner_id">>, ?U}, {<<"name">>, <<"Desk">>}, {<<"device_type">>, <<"sip_device">>},
    {<<"sip">>, j([{<<"username">>, <<"desk">>}, {<<"realm">>, ?REALM}, {<<"password">>, <<"SECRET_SENTINEL">>}])}]).
context() -> cb_context:setters(cb_context:new(), [
    {fun cb_context:set_account_id/2, ?A}, {fun cb_context:set_auth_account_id/2, ?A},
    {fun cb_context:set_auth_doc/2, j([{<<"owner_id">>, ?U}, {<<"method">>, <<"test">>}])},
    {fun cb_context:set_auth_token_type/2, 'x-auth-token'}, {fun cb_context:set_auth_token/2, <<"test-token">>},
    {fun cb_context:set_api_version/2, <<"v2">>}, {fun cb_context:set_req_verb/2, <<"GET">>},
    {fun cb_context:set_req_nouns/2, [{<<"members">>, [<<"devices">>]}, {<<"accounts">>, [?A]}]},
    {fun cb_context:set_db_name/2, kzs_util:format_account_db(?A)}, {fun cb_context:set_query_string/2, j([])}]).

pagination_test() ->
    ?assertEqual(25, cb_members:page_size(undefined)), ?assertEqual(100, cb_members:page_size(<<"100">>)),
    lists:foreach(fun(V) -> ?assertThrow({members_error,400,_}, cb_members:page_size(V)) end,
        [0,101,-1,1.2,<<"01">>,<<"all">>,<<"10000">>,true]),
    Cursor = cb_members:encode_cursor(?A, ?U), ?assertEqual(?U, cb_members:decode_cursor(?A, Cursor)),
    ?assertThrow({members_error,400,_}, cb_members:decode_cursor(?V, Cursor)),
    ?assertThrow({members_error,400,_}, cb_members:decode_cursor(?A, <<"garbage">>)),
    ?assertEqual({[user(?U)], true}, cb_members:page([user(?U),user(?V)], undefined,1)),
    ?assertEqual({[user(?V)], false}, cb_members:page([user(?U),user(?V)], ?U,1)),
    ?assertEqual({[user(?V)], false}, cb_members:page([user(?V)], ?U,1)).

registration_semantics_test() ->
    On = {ok,#{<<"desk@members-test.invalid">> => [200]}}, Off = {ok,#{}},
    ?assertEqual(<<"online">>, state(cb_members:device_status(device(),?REALM,On,[],100))),
    ?assertEqual(200,kz_json:get_value(<<"expires_at_ms">>,cb_members:device_status(device(),?REALM,On,[],100))),
    ?assertEqual(<<"offline">>, state(cb_members:device_status(device(),?REALM,On,[],200))),
    ?assertEqual(<<"offline">>, state(cb_members:device_status(device(),?REALM,Off,[],100))),
    ?assertEqual(<<"unknown">>, state(cb_members:device_status(device(),?REALM,{error,timeout},[],100))),
    ?assertEqual(<<"unknown">>, state(cb_members:device_status(device(),?REALM,On,[<<"sip_device">>],100))),
    ?assertEqual(<<"unknown">>, state(cb_members:device_status(kz_json:set_value([<<"sip">>,<<"method">>],<<"ip">>,device()),?REALM,On,[],100))),
    ?assertEqual(<<"unknown">>, state(cb_members:device_status(kz_json:set_value([<<"sip">>,<<"realm">>],<<"other.invalid">>,device()),?REALM,On,[],100))),
    ?assertEqual(<<"unknown">>, state(cb_members:device_status(kz_json:delete_key([<<"sip">>,<<"username">>],device()),?REALM,On,[],100))),
    %% Disabled is independent of actual observed registration, not a fabricated
    %% outage while an old valid binding still exists.
    ?assertEqual(<<"online">>, state(cb_members:device_status(kz_json:set_value(<<"enabled">>,false,device()),?REALM,On,[],100))),
    lists:foreach(fun({Expiries,Expected})->
        ?assertEqual(Expected,state(cb_members:device_status(device(),?REALM,{ok,#{<<"desk@members-test.invalid">> => Expiries}},[],100)))
    end,[{[unknown],<<"unknown">>},{[90,unknown],<<"unknown">>},{[90,200,unknown],<<"online">>},
         {[permanent],<<"online">>},{[90],<<"offline">>}]).
state(J) -> kz_json:get_value(<<"status">>,J).

projection_test() ->
    Snap = {?REALM,{ok,#{}},[]},
    WithDevice = cb_members:project(user(?U),[device()],true,Snap,123),
    WithoutDevice = cb_members:project(user(?V),[device()],true,Snap,123),
    ?assertEqual(1,kz_json:get_value(<<"device_count">>,WithDevice)),
    ?assertEqual(0,kz_json:get_value(<<"device_count">>,WithoutDevice)),
    ?assertEqual([],kz_json:get_value(<<"devices">>,WithoutDevice)),
    Encoded = kz_json:encode(WithDevice),
    lists:foreach(fun(Secret) -> ?assertEqual(nomatch,binary:match(Encoded,Secret)) end,
        [<<"SECRET_SENTINEL">>,<<"password">>,<<"username">>,<<"realm">>,<<"pvt_">>,<<"queues">>]),
    Incomplete = cb_members:project(user(?U),[],false,Snap,123),
    ?assertEqual(null,kz_json:get_value(<<"device_count">>,Incomplete)),
    ?assertEqual(false,kz_json:get_value(<<"devices_complete">>,Incomplete)).

integration_test_() -> {foreach,fun setup/0,fun teardown/1,
    [fun(_) -> fun normal_get/0 end,fun(_) -> fun scope_gates/0 end,
     fun(_) -> fun incomplete_registrars/0 end,fun(_) -> fun inventory_overflow/0 end,
     fun(_) -> fun invalid_inventory/0 end,fun(_) -> fun actual_custom_route_parser/0 end,
     fun(_) -> fun expiry_filtering/0 end,fun(_) -> fun exact_inventory_boundary/0 end,
     fun(_) -> fun unassigned_inventory_overflow/0 end,fun(_) -> fun member_page_boundaries/0 end,
     fun(_) -> fun registrar_row_boundaries/0 end,fun(_) -> fun datastore_over_return/0 end]}.
setup() ->
    T = ets:new(members_test,[named_table,public]),
    ets:insert(T,[{auth,allow},{devices,[device()]},{users,[user(?U),user(?V)]},
        {view_queries,[]},{over_return,false},{user_limit,27},
        {registration,[j([{<<"AOR">>,<<"desk@members-test.invalid">>},{<<"Expires">>,erlang:system_time(second)+120},
            {<<"Contact">>,<<"SECRET_CONTACT">>},{<<"Path">>,<<"SECRET_PATH">>}])]},{queries,0},{custom,true}]),
    lists:foreach(fun(M) -> ok=meck:new(M,[no_link]) end,[kz_datamgr,crossbar_bindings,kz_auth_scope,kapps_config,kzd_accounts,kapi_registration]),
    meck:expect(kzd_accounts,fetch_realm,fun(?A)->?REALM end),
    meck:expect(kapps_config,get_ne_binaries,fun(_,Key,Default)->
        case Key of <<"custom_route_modules">> -> case val(custom) of true -> [<<"members">>|Default]; false -> Default end; _ -> Default end end),
    meck:expect(kz_auth_scope,all,fun(_,_) -> val(auth)=/=scope_denied end),
    meck:expect(crossbar_bindings,pmap,fun(Event,Payload) ->
        case binary:match(Event,<<"allowed_scopes">>) of
            {_,_} -> [[<<"test-scope">>]];
            nomatch ->
                case binary:match(Event,<<"authorize.">>) of
                    {_,_} -> [C|_]=Payload,
                        case {val(auth),cb_context:req_nouns(C)} of
                            {deny_devices,[{<<"devices">>,_}|_]} -> [{stop,C}];
                            {deny_users,[{<<"users">>,_}|_]} -> [{stop,C}];
                            {crash,_} -> [error];
                            _ -> [false]
                        end;
                    _ -> [true]
                end
        end end),
    meck:expect(kapi_registration,search_realm_regs,fun(?REALM,<<"detail">>) ->
        ets:update_counter(T,queries,1),case val(registration) of exception -> erlang:error(test_failure); V -> V end end),
    meck:expect(kz_datamgr,get_results,fun(Db,<<"crossbar_listings/by_type_id">>,Options) ->
        ?assertEqual(kzs_util:format_account_db(?A),Db),
        Parsed=couchbeam_view:parse_view_options(Options),
        ?assertEqual("true",proplists:get_value(include_docs,Parsed#view_query_args.options)),
        ?assertEqual(false,proplists:get_value(reduce,Options)),
        [Type|After]=proplists:get_value(startkey,Options),
        Limit=proplists:get_value(limit,Options),
        ?assertEqual(case Type of <<"user">> -> val(user_limit); <<"device">> -> 1001 end,Limit),
        ets:insert(T,{view_queries,val(view_queries)++[{Type,Limit}]}),
        Docs=case Type of <<"user">> -> val(users); <<"device">> -> val(devices) end,
        Filtered=case After of [] -> Docs; [A] -> [D||D<-Docs,kz_doc:id(D)>=A] end,
        Returned=case val(over_return) of Type -> Filtered; _ -> lists:sublist(Filtered,Limit) end,
        {ok,[j([{<<"doc">>,D}])||D<-Returned]}
    end),T.
teardown(T) -> meck:unload(),ets:delete(T).
val(K) -> [{K,V}]=ets:lookup(members_test,K),V.
response() -> cb_members:validate(context(),<<"devices">>).
normal_get() ->
    C=response(),?assertEqual(success,cb_context:resp_status(C)),D=cb_context:resp_data(C),
    ?assertEqual(2,kz_json:get_value(<<"count">>,D)),
    [A,B]=kz_json:get_value(<<"items">>,D),?assertEqual(1,kz_json:get_value(<<"device_count">>,A)),
    ?assertEqual(0,kz_json:get_value(<<"device_count">>,B)),?assertEqual(1,val(queries)),
    ?assertEqual(true,kz_json:get_value([<<"registration_snapshot">>,<<"complete">>],D)),
    ?assertEqual(true,kz_json:get_value([<<"registration_snapshot">>,<<"expiry_available">>],D)),
    ?assertEqual(<<"no-store">>,maps:get(<<"cache-control">>,cb_context:resp_headers(C))),
    lists:foreach(fun(S)->?assertEqual(nomatch,binary:match(kz_json:encode(D),S)) end,
        [<<"SECRET_SENTINEL">>,<<"SECRET_CONTACT">>,<<"SECRET_PATH">>]),
    ?assertNot(meck:called(kz_datamgr,save_doc,'_')).
scope_gates() ->
    lists:foreach(fun(Mode)->ets:insert(members_test,{auth,Mode}),?assertEqual(403,cb_context:resp_error_code(response())) end,
        [deny_devices,deny_users,scope_denied,crash]),?assertEqual(0,val(queries)),
    ets:insert(members_test,{auth,allow}),
    Bad=cb_context:set_auth_doc(context(),undefined),?assertEqual(403,cb_context:resp_error_code(cb_members:validate(Bad,<<"devices">>))),
    Query=cb_context:set_query_string(context(),j([{<<"paginate">>,false}])),
    ?assertEqual(400,cb_context:resp_error_code(cb_members:validate(Query,<<"devices">>))).
incomplete_registrars() ->
    lists:foreach(fun(V)->ets:insert(members_test,{registration,V}),
        C=response(),?assertEqual(success,cb_context:resp_status(C)),
        D=cb_context:resp_data(C),?assertEqual(false,kz_json:get_value([<<"registration_snapshot">>,<<"complete">>],D)),
        [U|_]=kz_json:get_value(<<"items">>,D),[Device]=kz_json:get_value(<<"devices">>,U),
        ?assertEqual(<<"unknown">>,kz_json:get_value([<<"registration">>,<<"status">>],Device))
    end,[{error,timeout},{error,incomplete_registration_response},exception,[j([])]]).
expiry_filtering() ->
    Now=erlang:system_time(second),
    lists:foreach(fun({Expires,Expected,Available})->
        Base=j([{<<"AOR">>,<<"desk@members-test.invalid">>},{<<"Contact">>,<<"NEVER_RETURN_CONTACT">>}]),
        Reg=case Expires of undefined -> Base; _ -> kz_json:set_value(<<"Expires">>,Expires,Base) end,
        ets:insert(members_test,{registration,[Reg]}),C=response(),?assertEqual(success,cb_context:resp_status(C)),
        Data=cb_context:resp_data(C),?assertEqual(true,kz_json:get_value([<<"registration_snapshot">>,<<"complete">>],Data)),
        ?assertEqual(Available,kz_json:get_value([<<"registration_snapshot">>,<<"expiry_available">>],Data)),
        [U|_]=kz_json:get_value(<<"items">>,Data),[D]=kz_json:get_value(<<"devices">>,U),
        ?assertEqual(Expected,kz_json:get_value([<<"registration">>,<<"status">>],D)),
        ?assertEqual(nomatch,binary:match(kz_json:encode(Data),<<"NEVER_RETURN_CONTACT">>))
    end,[{Now-30,<<"offline">>,true},{Now+120,<<"online">>,true},{0,<<"online">>,true},
         {undefined,<<"unknown">>,false},{3600,<<"unknown">>,false},{<<"bad">>,<<"unknown">>,false}]).
inventory_overflow() ->
    Many=[kz_doc:set_id(device(),iolist_to_binary(io_lib:format("~32.16.0b",[N])))||N<-lists:seq(1,1001)],
    ets:insert(members_test,{devices,Many}),C=response(),?assertEqual(success,cb_context:resp_status(C)),
    D=cb_context:resp_data(C),?assertEqual(false,kz_json:get_value([<<"device_inventory">>,<<"complete">>],D)),
    ?assertEqual(2,kz_json:get_value(<<"count">>,D)),?assertEqual(0,val(queries)),
    lists:foreach(fun(U)->?assertEqual(false,kz_json:get_value(<<"devices_complete">>,U)),
        ?assertEqual(null,kz_json:get_value(<<"device_count">>,U)),?assertEqual([],kz_json:get_value(<<"devices">>,U)) end,kz_json:get_value(<<"items">>,D)).
number_id(N) -> iolist_to_binary(io_lib:format("~32.16.0b",[N])).
exact_inventory_boundary() ->
    Many=[kz_doc:set_id(device(),number_id(N))||N<-lists:seq(1,1000)],
    ets:insert(members_test,{devices,Many}),C=response(),?assertEqual(success,cb_context:resp_status(C)),
    D=cb_context:resp_data(C),?assertEqual(true,kz_json:get_value([<<"device_inventory">>,<<"complete">>],D)),
    ?assertEqual(1000,kz_json:get_value([<<"device_inventory">>,<<"count">>],D)),
    [U,V]=kz_json:get_value(<<"items">>,D),?assertEqual(1000,kz_json:get_value(<<"device_count">>,U)),
    ?assertEqual(1000,length(kz_json:get_value(<<"devices">>,U))),
    ?assertEqual(0,kz_json:get_value(<<"device_count">>,V)),?assertEqual(1,val(queries)),
    ?assertEqual([{<<"user">>,27},{<<"device">>,1001}],val(view_queries)).
unassigned_inventory_overflow() ->
    Many=[kz_json:delete_key(<<"owner_id">>,kz_doc:set_id(device(),number_id(N)))||N<-lists:seq(1,1001)],
    ets:insert(members_test,{devices,Many}),C=response(),?assertEqual(success,cb_context:resp_status(C)),
    D=cb_context:resp_data(C),?assertEqual(false,kz_json:get_value([<<"device_inventory">>,<<"complete">>],D)),
    ?assertEqual(<<"limit_exceeded">>,kz_json:get_value([<<"device_inventory">>,<<"reason">>],D)),
    ?assertEqual(null,kz_json:get_value([<<"device_inventory">>,<<"count">>],D)),
    lists:foreach(fun(U)->?assertEqual(false,kz_json:get_value(<<"devices_complete">>,U)),
        ?assertEqual(null,kz_json:get_value(<<"device_count">>,U)),?assertEqual([],kz_json:get_value(<<"devices">>,U)) end,
        kz_json:get_value(<<"items">>,D)),
    ?assertEqual(0,val(queries)),?assertEqual([{<<"user">>,27},{<<"device">>,1001}],val(view_queries)).
member_page_boundaries() ->
    Users=[user(number_id(N))||N<-lists:seq(1,205)],
    ets:insert(members_test,[{users,Users},{devices,[]},{user_limit,102}]),
    {First,Next1}=member_page(undefined,100,true),
    {Second,Next2}=member_page(Next1,100,true),
    {Last,null}=member_page(Next2,5,false),
    ?assertEqual([kz_doc:id(U)||U<-Users],First++Second++Last),
    ?assertEqual(lists:flatten(lists:duplicate(3,[{<<"user">>,102},{<<"device">>,1001}])),val(view_queries)),
    ?assertEqual(0,val(queries)).
member_page(Cursor,Count,More) ->
    Query=case Cursor of undefined -> j([{<<"page_size">>,100}]);
        _ -> j([{<<"page_size">>,100},{<<"cursor">>,Cursor}]) end,
    C=cb_members:validate(cb_context:set_query_string(context(),Query),<<"devices">>),
    ?assertEqual(success,cb_context:resp_status(C)),D=cb_context:resp_data(C),
    ?assertEqual(Count,kz_json:get_value(<<"count">>,D)),?assertEqual(More,kz_json:get_value(<<"has_more">>,D)),
    ?assertEqual(100,kz_json:get_value(<<"page_size">>,D)),
    Items=kz_json:get_value(<<"items">>,D),
    lists:foreach(fun(U)->?assertEqual(true,kz_json:get_value(<<"devices_complete">>,U)),
        ?assertEqual(0,kz_json:get_value(<<"device_count">>,U)) end,Items),
    {[kz_json:get_value(<<"id">>,U)||U<-Items],kz_json:get_value(<<"next_cursor">>,D)}.
registrar_row_boundaries() ->
    [Reg]=val(registration),
    lists:foreach(fun({Count,Complete,State,Reason})->
        %% The real collector de-duplicates identical rows. Keep this returned
        %% inventory distinct, with the actual device binding plus other AORs.
        Others=[kz_json:set_value(<<"AOR">>,<<(integer_to_binary(N))/binary,"@members-test.invalid">>,Reg)
            ||N<-lists:seq(2,Count)],
        ets:insert(members_test,[{registration,[Reg|Others]},{queries,0},{view_queries,[]}]),
        C=response(),?assertEqual(success,cb_context:resp_status(C)),D=cb_context:resp_data(C),
        ?assertEqual(Complete,kz_json:get_value([<<"registration_snapshot">>,<<"complete">>],D)),
        ?assertEqual(Reason,kz_json:get_value([<<"registration_snapshot">>,<<"reason">>],D)),
        [U|_]=kz_json:get_value(<<"items">>,D),[Device]=kz_json:get_value(<<"devices">>,U),
        ?assertEqual(State,kz_json:get_value([<<"registration">>,<<"status">>],Device)),
        ?assertEqual(1,val(queries)),?assertEqual([{<<"user">>,27},{<<"device">>,1001}],val(view_queries))
    end,[{10000,true,<<"online">>,<<"complete">>},
         {10001,false,<<"unknown">>,<<"invalid_registration_response">>}]).
datastore_over_return() ->
    lists:foreach(fun(Type)->
        ets:insert(members_test,[{users,[user(number_id(N))||N<-lists:seq(1,28)]},
            {devices,[kz_doc:set_id(device(),number_id(N))||N<-lists:seq(1,1002)]},
            {over_return,Type},{queries,0},{view_queries,[]}]),
        C=response(),?assertEqual(503,cb_context:resp_error_code(C)),?assertEqual(0,val(queries)),
        ?assertEqual(undefined,kz_json:get_value(<<"items">>,cb_context:resp_data(C))),
        Expected=case Type of <<"user">> -> [{<<"user">>,27}];
            <<"device">> -> [{<<"user">>,27},{<<"device">>,1001}] end,
        ?assertEqual(Expected,val(view_queries))
    end,[<<"user">>,<<"device">>]).
invalid_inventory() ->
    ets:insert(members_test,{devices,[kz_json:set_value(<<"pvt_account_id">>,?V,device())]}),
    ?assertEqual(503,cb_context:resp_error_code(response())),?assertEqual(0,val(queries)).
actual_custom_route_parser() ->
    Tokens=[<<"accounts">>,?A,<<"members">>,<<"devices">>],
    ?assertEqual([{<<"members">>,[<<"devices">>]},{<<"accounts">>,[?A]}],api_util:parse_path_tokens(context(),Tokens)),
    ets:insert(members_test,{custom,false}),
    ?assertEqual([{<<"members">>,[<<"devices">>]},{<<"accounts">>,[?A]}],api_util:parse_path_tokens(context(),Tokens)),
    ?assertEqual([<<"GET">>],cb_members:allowed_methods(<<"devices">>)),
    ?assertEqual([],cb_members:allowed_methods()),?assertEqual(false,cb_members:resource_exists()).
