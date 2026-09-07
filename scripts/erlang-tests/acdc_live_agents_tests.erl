%%% Provider-free selected-roster helper proof. Actual helper/JSON/document/
%%% Crossbar context; only datastore and permission decisions are controlled.
-module(acdc_live_agents_tests).
-compile({no_auto_import,[put/2,get/1]}).
-include_lib("eunit/include/eunit.hrl").
-define(A,<<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(Q,<<"11111111111111111111111111111111">>).
-define(U,<<"22222222222222222222222222222222">>).
-define(V,<<"33333333333333333333333333333333">>).
-define(EPOCH,62167219200).
-define(T,acdc_live_agents_fixture).
j(P)->kz_json:from_list(P).
v(K,J)->kz_json:get_value(K,J).
hex(N)->list_to_binary(io_lib:format("~32.16.0b",[N])).
put(K,V)->ets:insert(?T,{K,V}).
get(K)->[{K,V}]=ets:lookup(?T,K),V.
doc(I)->j([{<<"_id">>,I},{<<"pvt_type">>,<<"user">>},{<<"pvt_account_id">>,?A},
    {<<"queues">>,[?Q]},{<<"first_name">>,<<"Test">>},{<<"last_name">>,<<"Agent">>},
    {<<"email">>,<<"NEVER-RETURN-EMAIL">>},{<<"pvt_secret">>,<<"NEVER-RETURN-SECRET">>}]).
row(D)->j([{<<"id">>,kz_doc:id(D)},{<<"key">>,[?Q,kz_doc:id(D)]},{<<"doc">>,D}]).
context()->cb_context:setters(cb_context:new(),[
    {fun cb_context:set_account_id/2,?A},{fun cb_context:set_auth_account_id/2,?A},
    {fun cb_context:set_auth_doc/2,j([{<<"account_id">>,?A},{<<"owner_id">>,?U}])},
    {fun cb_context:set_db_name/2,kzs_util:format_account_db(?A)}]).
reset()->
    [put(K,V) || {K,V}<-[{rows,[row(doc(?U))]},{result,default},{permits,[]},{denied,none},{reads,0}]],ok.
setup()->
    T=ets:new(?T,[named_table,public]),reset(),
    meck:new([kz_datamgr,acdc_live_auth],[non_strict,no_link]),
    meck:expect(acdc_live_auth,permit,fun(C,Resource,Params)->
        ?assertEqual(?A,cb_context:account_id(C)),
        put(permits,get(permits)++[{Resource,Params}]),
        case get(denied) of
            {Resource,Params}->throw({live_error,403,<<"fixture_denied">>});
            _->ok
        end
    end),
    meck:expect(kz_datamgr,get_results,fun(Db,View,Opts)->
        ?assertEqual(kzs_util:format_account_db(?A),Db),
        ?assertEqual(<<"queues/agents_listing">>,View),
        ?assertEqual([{<<"queues">>,[?Q,<<"roster">>]}],get(permits)),
        put(reads,get(reads)+1),put(options,Opts),
        case get(result) of default->{ok,get(rows)};raise->error(storage_failure);R->R end
    end),T.
cleanup(T)->meck:unload([kz_datamgr,acdc_live_auth]),ets:delete(T).

agents_test_()->{timeout,40,{setup,fun setup/0,fun cleanup/1,fun(_)->[
    fun overview_no_reads/0,fun selected_view_and_auth/0,fun sorted_roster/0,
    fun bounded_lookahead/0,fun permission_denials/0,fun storage_failures/0,
    fun invalid_scope_and_docs/0,fun invalid_roster_rows/0,
    fun public_unknown_empty/0,fun observed_states/0,fun runtime_missing_and_mixed/0,
    fun invalid_runtime/0,fun authorized_names/0,fun capped_completeness/0
] end}}.
prepare()->cb_acdc_live_agents:prepare(context(),?Q).
prepared(Docs)->#{ids=>[kz_doc:id(D)||D<-Docs],docs=>Docs,truncated=>false}.
obs(I)->j([{<<"agent_id">>,I},{<<"observed">>,true},{<<"queue_member">>,true},
    {<<"state">>,<<"ready">>},{<<"reason">>,<<"observed">>}]).
unknown(I,R)->j([{<<"agent_id">>,I},{<<"observed">>,false},{<<"queue_member">>,null},
    {<<"state">>,null},{<<"reason">>,R}]).
runtime(Rows)->#{rows=>Rows,observation_started=>?EPOCH+1700000000,observation_finished=>?EPOCH+1700000001}.
public(P,R)->
    J=cb_acdc_live_agents:public(P,R),
    ?assertEqual(lists:sort([<<"limit">>,<<"roster_complete">>,<<"truncated">>,<<"runtime_complete">>,
        <<"endpoint_reachability_verified">>,<<"observation_started">>,<<"observation_finished">>,<<"rows">>]),
        lists:sort(kz_json:get_keys(J))),
    [?assertEqual(lists:sort([<<"agent_id">>,<<"name">>,<<"observed">>,<<"queue_member">>,<<"state">>,<<"reason">>]),
        lists:sort(kz_json:get_keys(Row))) || Row<-v(<<"rows">>,J)],
    ?assertEqual(false,v(<<"endpoint_reachability_verified">>,J)),J.
code(Code,F)->
    Result=try F(),no_failure catch throw:{live_error,C,_}->{live_error,C} end,
    ?assertEqual({live_error,Code},Result).

overview_no_reads()->
    reset(),?assertEqual(undefined,cb_acdc_live_agents:prepare(undefined,undefined)),
    ?assertEqual(null,cb_acdc_live_agents:public(undefined,invalid)),
    ?assertEqual([],get(permits)),?assertEqual(0,get(reads)).
selected_view_and_auth()->
    reset(),P=prepare(),?assertEqual([?U],maps:get(ids,P)),?assertEqual([doc(?U)],maps:get(docs,P)),
    ?assertEqual(false,maps:get(truncated,P)),?assertEqual(1,get(reads)),
    ?assertEqual([{startkey,[?Q]},{endkey,[?Q,j([])]},{reduce,false},include_docs,{limit,201}],get(options)),
    ?assertEqual([{<<"queues">>,[?Q,<<"roster">>]},{<<"agents">>,[?U]},
        {<<"agents">>,[?U,<<"status">>]}],get(permits)).
sorted_roster()->
    reset(),put(rows,[row(doc(?V)),row(doc(?U))]),P=prepare(),
    ?assertEqual([?U,?V],maps:get(ids,P)),?assertEqual([doc(?U),doc(?V)],maps:get(docs,P)).
bounded_lookahead()->
    reset(),Docs=[doc(hex(N))||N<-lists:seq(1,201)],put(rows,[row(D)||D<-Docs]),
    P=prepare(),?assertEqual(200,length(maps:get(ids,P))),?assertEqual(true,maps:get(truncated,P)),
    ?assertEqual(hex(200),lists:last(maps:get(ids,P))),
    ?assert(lists:member({<<"agents">>,[hex(201)]},get(permits))),
    ?assert(lists:member({<<"agents">>,[hex(201),<<"status">>]},get(permits))),
    reset(),put(rows,[row(D)||D<-Docs]),put(denied,{<<"agents">>,[hex(201),<<"status">>]}),
    code(403,fun prepare/0).
permission_denials()->
    [begin reset(),put(denied,D),code(403,fun prepare/0),
        ?assertEqual(case D of {<<"queues">>,_}->0;_->1 end,get(reads)) end ||
        D<-[{<<"queues">>,[?Q,<<"roster">>]},{<<"agents">>,[?U]},{<<"agents">>,[?U,<<"status">>]}]].
storage_failures()->
    [begin reset(),put(result,R),code(503,fun prepare/0) end ||
        R<-[{error,timeout},{error,not_found},raise,{ok,42},{ok,[bad]},{ok,undefined}]].
invalid_scope_and_docs()->
    reset(),code(403,fun()->cb_acdc_live_agents:prepare(context(),<<"bad">>) end),?assertEqual(0,get(reads)),
    code(403,fun()->cb_acdc_live_agents:prepare(cb_context:set_db_name(context(),<<"wrong-tenant">>),?Q) end),
    ?assertEqual(0,get(reads)),
    [begin reset(),put(rows,[row(kz_json:set_value(K,V,doc(?U)))]),code(503,fun prepare/0) end ||
        {K,V}<-[{<<"pvt_type">>,<<"device">>},{<<"pvt_account_id">>,?V},
        {<<"pvt_deleted">>,true},{<<"_deleted">>,true},{<<"_id">>,<<"bad">>},
        {<<"queues">>,[]},{<<"queues">>,[?V]},{<<"queues">>,[?Q,?Q]},
        {<<"queues">>,[?Q,42]},{<<"queues">>,j([{<<"0">>,?Q}])},
        {<<"queues">>,[?Q|[hex(N)||N<-lists:seq(1,1024)]]}]].
invalid_roster_rows()->
    R=row(doc(?U)),
    [begin reset(),put(rows,Rows),code(503,fun prepare/0) end || Rows<-[
        [R,R],[kz_json:set_value(<<"id">>,?V,R)],[kz_json:set_value(<<"key">>,[?V,?U],R)],
        [kz_json:delete_key(<<"doc">>,R)],[row(doc(hex(N)))||N<-lists:seq(1,202)],
        lists:duplicate(202,R),[R|invalid_tail]]].

public_unknown_empty()->
    P=prepared([doc(?U)]),J=public(P,null),[R]=v(<<"rows">>,J),
    ?assertEqual(false,v(<<"runtime_complete">>,J)),?assertEqual(true,v(<<"roster_complete">>,J)),
    ?assertEqual(null,v(<<"observation_started">>,J)),?assertEqual(null,v(<<"observation_finished">>,J)),
    ?assertEqual(false,v(<<"observed">>,R)),?assertEqual(null,v(<<"queue_member">>,R)),
    ?assertEqual(null,v(<<"state">>,R)),?assertEqual(<<"source_unavailable">>,v(<<"reason">>,R)),
    ?assertEqual(false,v(<<"runtime_complete">>,public(prepared([]),null))),
    Empty=public(prepared([]),runtime([])),?assertEqual([],v(<<"rows">>,Empty)),
    ?assertEqual(true,v(<<"runtime_complete">>,Empty)).
observed_states()->
    P=prepared([doc(?U)]),
    [begin J=public(P,runtime([kz_json:set_values([{<<"state">>,S},{<<"queue_member">>,M}],obs(?U))])),
        ?assertEqual(true,v(<<"runtime_complete">>,J)),[R]=v(<<"rows">>,J),
        ?assertEqual(S,v(<<"state">>,R)),?assertEqual(M,v(<<"queue_member">>,R)),
        ?assertEqual(1700000000,v(<<"observation_started">>,J)),
        ?assertEqual(1700000001,v(<<"observation_finished">>,J)) end ||
        S<-[<<"wait">>,<<"sync">>,<<"ready">>,<<"ringing">>,<<"answered">>,<<"wrapup">>,<<"paused">>,<<"outbound">>],M<-[true,false]].
runtime_missing_and_mixed()->
    P=prepared([doc(?U),doc(?V)]),J=public(P,runtime([obs(?U)])),
    ?assertEqual(false,v(<<"runtime_complete">>,J)),[_,Missing]=v(<<"rows">>,J),
    ?assertEqual(<<"not_observed">>,v(<<"reason">>,Missing)),
    [begin M=public(P,runtime([obs(?U),unknown(?V,Reason)])),
        ?assertEqual(false,v(<<"runtime_complete">>,M)) end ||
        Reason<-[<<"not_observed">>,<<"inconsistent_sources">>,<<"source_unavailable">>]].
invalid_runtime()->
    P=prepared([doc(?U)]),R=obs(?U),
    [code(503,fun()->public(P,Runtime) end) || Runtime<-[invalid,#{},
        runtime([obs(?V)]),runtime([R,R]),runtime([bad]),runtime([R|bad_tail]),
        runtime([kz_json:set_value(<<"private">>,<<"never">>,R)]),
        runtime([kz_json:set_value(<<"observed">>,false,R)]),
        runtime([kz_json:set_value(<<"queue_member">>,null,R)]),
        runtime([kz_json:set_value(<<"state">>,<<"logged_out">>,R)]),
        runtime([unknown(?U,<<"invented">>)]),
        (runtime([R]))#{observation_started=>?EPOCH},
        (runtime([R]))#{observation_finished=>?EPOCH+1}]],
    [code(503,fun()->cb_acdc_live_agents:public(Bad,null) end) ||
        Bad<-[#{},P#{ids=>[?V]},P#{ids=>[?U,?U],docs=>[doc(?U),doc(?U)]},P#{truncated=>true}]].
authorized_names()->
    D=doc(?U),P=prepared([D]),J=public(P,runtime([obs(?U)])),[R]=v(<<"rows">>,J),
    ?assertEqual(<<"Test Agent">>,v(<<"name">>,R)),
    Bytes=iolist_to_binary(kz_json:encode(J)),?assertEqual(nomatch,binary:match(Bytes,<<"NEVER-RETURN">>)),
    [begin Bad=kz_json:set_values([{<<"first_name">>,Value},{<<"last_name">>,Value}],D),
        [Row]=v(<<"rows">>,public(prepared([Bad]),null)),?assertEqual(?U,v(<<"name">>,Row)) end ||
        Value<-[null,42,<<>>,<<"bad\nname">>,binary:copy(<<"x">>,128),binary:copy(<<"x">>,129)]],
    %% set_values normalizes invalid UTF-8 to U+FFFD before the helper sees it.
    %% Use the raw JSON wrapper to actually exercise rejection of invalid bytes.
    RawBad={[{<<"first_name">>,<<255>>},{<<"last_name">>,<<255>>} |
        [{K,V} || {K,V}<-kz_json:to_proplist(D),
                   K=/= <<"first_name">>,K=/= <<"last_name">>]]},
    [RawRow]=v(<<"rows">>,public(prepared([RawBad]),null)),
    ?assertEqual(?U,v(<<"name">>,RawRow)),
    Hebrew=unicode:characters_to_binary([16#5D3,16#5E0,16#5D4]),
    Only=kz_json:delete_key(<<"last_name">>,kz_json:set_value(<<"first_name">>,Hebrew,D)),
    [H]=v(<<"rows">>,public(prepared([Only]),null)),?assertEqual(Hebrew,v(<<"name">>,H)),
    %% Runtime cannot supply or replace an authorized document name.
    code(503,fun()->public(P,runtime([kz_json:set_value(<<"name">>,<<"Injected">>,obs(?U))])) end).
capped_completeness()->
    Docs=[doc(hex(N))||N<-lists:seq(1,200)],P=(prepared(Docs))#{truncated=>true},
    J=public(P,runtime([obs(kz_doc:id(D))||D<-Docs])),
    ?assertEqual(200,length(v(<<"rows">>,J))),?assertEqual(true,v(<<"truncated">>,J)),
    ?assertEqual(false,v(<<"roster_complete">>,J)),?assertEqual(false,v(<<"runtime_complete">>,J)).
