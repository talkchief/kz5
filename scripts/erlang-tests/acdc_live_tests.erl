%%% Real Crossbar context/route/DTO and real kapi serialization/validation.
%%% Provider mecks only: no HTTP listener, live broker, auth service or database.
-module(acdc_live_tests).
-include_lib("eunit/include/eunit.hrl").
-include_lib("kazoo_stdlib/include/kz_records.hrl").
-define(A, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(Q, <<"11111111111111111111111111111111">>).
-define(Q2, <<"22222222222222222222222222222222">>).
-define(Q3, <<"33333333333333333333333333333333">>).
-define(N1, 'first@offline.invalid').
-define(N2, 'second@offline.invalid').
-define(N3, 'third@offline.invalid').
-define(EPOCH, 62167219200).
j(P)->kz_json:from_list(P).
val(K,J)->kz_json:get_value(K,J).
now_s()->calendar:datetime_to_gregorian_seconds(calendar:universal_time()).
source_id(N)->kz_binary:hexencode(crypto:hash(sha256,atom_to_binary(N,utf8))).
incarnation(1)->binary:copy(<<"1">>,64);
incarnation(2)->binary:copy(<<"2">>,64).
doc(Q)->j([{<<"_id">>,Q},{<<"pvt_type">>,<<"queue">>},{<<"pvt_account_id">>,?A},
    {<<"name">>,<<"Support">>},{<<"strategy">>,<<"round_robin">>},
    {<<"pvt_secret">>,<<"NEVER-RETURN-PRIVATE">>}]).
context(Queue,Query)->
    Params=case Queue of undefined->[<<"live">>]; _->[Queue,<<"live">>] end,
    cb_context:setters(cb_context:new(),[
        {fun cb_context:set_account_id/2,?A},{fun cb_context:set_auth_account_id/2,?A},
        {fun cb_context:set_auth_doc/2,j([{<<"owner_id">>,?Q3},{<<"method">>,<<"cb_user_auth">>}])},
        {fun cb_context:set_auth_token_type/2,'x-auth-token'},{fun cb_context:set_auth_token/2,<<"fixture-token">>},
        {fun cb_context:set_api_version/2,<<"v2">>},{fun cb_context:set_req_verb/2,<<"GET">>},
        {fun cb_context:set_req_nouns/2,[{<<"queues">>,Params},{<<"accounts">>,[?A]}]},
        {fun cb_context:set_raw_path/2,<<"/v2/accounts/",?A/binary,"/queues/live">>},
        {fun cb_context:set_query_string/2,Query},{fun cb_context:set_db_name/2,kzs_util:format_account_db(?A)},
        {fun cb_context:set_resp_etag/2,<<"old-cache-tag">>}]).
get(Queue,Query)->
    C=context(Queue,Query),
    case Queue of undefined->cb_queues:validate(C,<<"live">>); _->cb_queues:validate(C,Queue,<<"live">>) end.
no_store(C)->
    ?assertEqual(<<"no-store">>,maps:get(<<"cache-control">>,cb_context:resp_headers(C))),
    ?assertEqual(undefined,cb_context:resp_etag(C)).
error_code(Code,C)->?assertEqual(Code,cb_context:resp_error_code(C)),no_store(C).
put_state(K,V)->ets:insert(acdc_live_fixture,{K,V}).
state(K)->[{K,V}]=ets:lookup(acdc_live_fixture,K),V.
bump(K)->ets:update_counter(acdc_live_fixture,K,1).
reset()->
    [put_state(K,V) || {K,V}<-[{docs,[doc(?Q)]},{doc_result,default},{denied,none},
        {auth_result,normal},{scope,true},{catalog_calls,0},{open_calls,0},{broker_calls,0},
        {node_calls,0},{permits,[]},{nodes,[?N1,?N2]},{nodes_after,same},{broker_mode,consensus}]],ok.
setup()->
    T=ets:new(acdc_live_fixture,[named_table,public]),reset(),
    meck:new([kz_datamgr,kz_nodes,kz_amqp_worker,crossbar_bindings,kz_auth_scope],[non_strict,no_link]),
    meck:expect(crossbar_bindings,pmap,fun auth/2),
    meck:expect(kz_auth_scope,all,fun(<<"fixture-token">>,[<<"fixture:queues">>])->state(scope) end),
    meck:expect(kz_datamgr,get_results,fun(Db,<<"queues/crossbar_listing">>,Opts)->
        ?assertEqual(kzs_util:format_account_db(?A),Db),bump(catalog_calls),
        put_state(catalog_options,Opts),{ok,[j([{<<"doc">>,D}]) || D<-state(docs)]} end),
    meck:expect(kz_datamgr,open_doc,fun(Db,Q)->
        ?assertEqual(kzs_util:format_account_db(?A),Db),bump(open_calls),put_state(open_id,Q),
        case state(doc_result) of default->{ok,doc(Q)}; Result->Result end end),
    meck:expect(kz_nodes,nodes,fun()->
        Call=bump(node_calls),Ns=case {Call,state(nodes_after)} of {1,_}->state(nodes); {_,same}->state(nodes); {_,Other}->Other end,
        [#kz_node{node=N,kapps=[{<<"acdc">>,#whapp_info{startup=1}}],last_heartbeat=1} || N<-Ns] end),
    meck:expect(kz_amqp_worker,call_collect,fun broker/4),T.
teardown(T)->meck:unload([kz_datamgr,kz_nodes,kz_amqp_worker,crossbar_bindings,kz_auth_scope]),ets:delete(T).
auth(<<"v2_resource.authorize">>,C)->
    [{<<"queues">>,Params}|_]=cb_context:req_nouns(C),
    put_state(permits,[Params|state(permits)]),
    case lists:member(<<"live">>,Params) of
        true->ok;
        false->?assertEqual([],kz_json:to_proplist(cb_context:query_string(C))),
               ?assertEqual(<<"GET">>,cb_context:req_verb(C)),
               ?assertEqual(?A,cb_context:account_id(C))
    end,
    case state(auth_result) of
        normal->case state(denied)=:=Params of true->[false]; false->[true] end;
        Other->Other
    end;
auth(<<"v2_resource.authorize.queues">>,[_|_])->[];
auth(<<"v2_resource.allowed_scopes.queues">>,<<"cb_user_auth">>)->[[<<"fixture:queues">>]];
auth(Event,_)->error({unexpected_auth_event,Event}).
broker(Req,Publish,Until,3000)->
    bump(broker_calls),?assert(is_function(Publish,1)),?assert(is_function(Until,1)),
    ?assertEqual(?A,props:get_value(<<"Account-ID">>,Req)),
    ?assertEqual(3600,props:get_value(<<"To">>,Req)-props:get_value(<<"From">>,Req)),
    R1=reply(Req,?N1,1,2,props:get_value(<<"To">>,Req),100,true),
    R2=reply(Req,?N2,1,2,props:get_value(<<"To">>,Req),100,true),
    ?assertNot(Until([])),?assertNot(Until([R1])),?assert(Until([R1,R2])),
    ?assert(Until(lists:duplicate(64,R1))),
    case state(broker_mode) of
        consensus->{ok,[R1,R2]}; timeout->{timeout,[R1]};
        conflict->{ok,[R1,reply(Req,?N2,1,3,props:get_value(<<"To">>,Req),100,true)]};
        duplicate->{ok,[R1,R1,R2]};
        call_conflict->{ok,[R1,kz_json:set_value([<<"Snapshot">>,<<"active_calls">>,<<"rows">>],
            lists:sublist(kz_json:get_value([<<"Snapshot">>,<<"active_calls">>,<<"rows">>],R2),1) ++
            [kz_json:set_value(<<"call_id">>,<<"different-active-call">>,Row) || Row <-
                lists:nthtail(1,kz_json:get_value([<<"Snapshot">>,<<"active_calls">>,<<"rows">>],R2))],R2)]};
        capped->{ok,[reply(Req,Node,1,201,props:get_value(<<"To">>,Req),100,true) || Node<-[?N1,?N2]]};
        empty->{ok,[reply(Req,Node,1,0,props:get_value(<<"To">>,Req),null,true) || Node<-[?N1,?N2]]};
        missing_flag->{ok,[kz_json:delete_key(<<"Include-Calls">>,R1),R2]};
        invalid->{ok,[kz_json:set_value(<<"Msg-ID">>,<<"wrong">>,R1),R2]}
    end.

public_route_test_()->{setup,fun setup/0,fun teardown/1,fun(_)->[
    {"real overview and detail routes, no-store and no replica summation",fun public_success/0},
    {"detail call rows, bounded truncation and unknown versus empty",fun detail_calls/0},
    {"bounded catalog pagination and lookahead permissions",fun pagination/0},
    {"auth, tenant DB, underlying stats and queue permissions",fun authorization/0},
    {"unsupported queries fail before catalog or broker",fun bad_queries/0},
    {"invalid/oversized/unsorted/deleted catalog is never returned",fun bad_catalog/0},
    {"missing/conflicting/changed replicas produce unknown metrics",fun partial_sources/0},
    {"node inventory and selected source caps are enforced",fun inventory_limits/0},
    {"empty inventory and no known source do not call broker",fun no_source/0}
] end}.
public_success()->
    reset(),?assertEqual([<<"GET">>],cb_queues:allowed_methods(<<"live">>)),
    ?assertEqual([<<"GET">>],cb_queues:allowed_methods(?Q,<<"live">>)),
    ?assert(cb_queues:resource_exists(?Q,<<"live">>)),
    R=get(undefined,j([])),?assertEqual(success,cb_context:resp_status(R)),no_store(R),
    D=cb_context:resp_data(R),[Q]=val(<<"queues">>,D),
    ?assertEqual(2,kz_json:get_value([<<"metrics">>,<<"current_waiting">>],Q)),
    ?assertEqual(true,val(<<"metrics_available">>,Q)),
    ?assertEqual(<<"available">>,kz_json:get_value([<<"source">>,<<"status">>],D)),
    ?assertEqual(false,kz_json:get_value([<<"source">>,<<"atomic_snapshot">>],D)),
    ?assertEqual(3600,kz_json:get_value([<<"window">>,<<"seconds">>],D)),
    ?assert(val(<<"generated_at">>,D)>1000000000),
    B=iolist_to_binary(kz_json:encode(D)),
    [?assertEqual(nomatch,binary:match(B,X)) || X<-[<<"NEVER-RETURN">>,<<"Source-ID">>,<<"Source-Incarnation">>,<<"scan_keys">>,<<"offline.invalid">>]],
    [ ?assertEqual(false,kz_json:get_value([<<"capabilities">>,K],D)) || K<-[<<"live_call_details">>,<<"agent_runtime">>,<<"websocket_updates">>,<<"historical_reporting">>]],
    reset(),Detail=get(?Q,j([])),?assertEqual(success,cb_context:resp_status(Detail)),no_store(Detail),
    ?assertEqual(0,state(catalog_calls)),?assertEqual(1,state(open_calls)),?assertEqual(?Q,state(open_id)),
    DD=cb_context:resp_data(Detail),
    ?assertEqual(null,val(<<"calls">>,D)),
    ?assertEqual(true,kz_json:get_value([<<"capabilities">>,<<"live_call_details">>],DD)),
    Calls=val(<<"calls">>,DD),?assertEqual(true,val(<<"available">>,Calls)),
    ?assertEqual(2,val(<<"observed_count">>,Calls)),
    [First|_]=val(<<"rows">>,Calls),?assertEqual(?Q,val(<<"queue_id">>,First)),
    ?assertEqual(null,val(<<"handled_at">>,First)),
    ?assertEqual(5,length(kz_json:to_proplist(First))),
    ?assert(abs(val(<<"entered_at">>,First)-(now_s()-?EPOCH-100))<5).
detail_calls()->
    [begin reset(),put_state(broker_mode,Mode),R=get(?Q,j([])),
        ?assertEqual(success,cb_context:resp_status(R)),D=cb_context:resp_data(R),
        C=val(<<"calls">>,D),?assertEqual(false,val(<<"available">>,C)),
        ?assertEqual(null,val(<<"observed_count">>,C)),?assertEqual([],val(<<"rows">>,C)),
        [Q]=val(<<"queues">>,D),?assertEqual(null,val(<<"metrics">>,Q)) end ||
        Mode<-[timeout,call_conflict,missing_flag]],
    reset(),put_state(broker_mode,capped),Capped=val(<<"calls">>,cb_context:resp_data(get(?Q,j([])))),
    ?assertEqual(true,val(<<"available">>,Capped)),?assertEqual(true,val(<<"truncated">>,Capped)),
    ?assertEqual(false,val(<<"complete">>,Capped)),?assertEqual(201,val(<<"observed_count">>,Capped)),
    ?assertEqual(200,length(val(<<"rows">>,Capped))),
    reset(),put_state(broker_mode,empty),Empty=val(<<"calls">>,cb_context:resp_data(get(?Q,j([])))),
    ?assertEqual(true,val(<<"available">>,Empty)),?assertEqual(true,val(<<"complete">>,Empty)),
    ?assertEqual(0,val(<<"observed_count">>,Empty)),?assertEqual([],val(<<"rows">>,Empty)),
    reset(),put_state(nodes,[]),Missing=val(<<"calls">>,cb_context:resp_data(get(?Q,j([])))),
    ?assertEqual(false,val(<<"available">>,Missing)),?assertEqual(null,val(<<"observed_count">>,Missing)).
pagination()->
    reset(),put_state(docs,[doc(?Q),doc(?Q2)]),
    R=get(undefined,j([{<<"page_size">>,<<"1">>}])),?assertEqual(success,cb_context:resp_status(R)),
    Opts=state(catalog_options),?assertEqual(2,proplists:get_value(limit,Opts)),
    ?assert(lists:member(include_docs,Opts)),?assertEqual(false,proplists:get_value(reduce,Opts)),
    D=cb_context:resp_data(R),?assertEqual(?Q2,kz_json:get_value([<<"pagination">>,<<"next_start_queue_id">>],D)),
    ?assert(lists:member([?Q2],state(permits))),
    reset(),put_state(docs,[doc(?Q2)]),
    R2=get(undefined,j([{<<"page_size">>,1},{<<"start_queue_id">>,?Q2}])),
    ?assertEqual(success,cb_context:resp_status(R2)),?assertEqual(?Q2,proplists:get_value(startkey,state(catalog_options))),
    reset(),put_state(docs,[doc(?Q),doc(?Q2)]),put_state(denied,[?Q2]),
    error_code(403,get(undefined,j([{<<"page_size">>,1}]))),?assertEqual(0,state(broker_calls)).
authorization()->
    [begin reset(),put_state(denied,P),error_code(403,get(undefined,j([]))),?assertEqual(0,state(broker_calls)) end || P<-[ [<<"live">>],[<<"stats">>],[],[?Q] ]],
    [begin reset(),put_state(auth_result,A),error_code(403,get(undefined,j([]))),?assertEqual(0,state(catalog_calls)) end || A<-[[],[false],[unexpected]]],
    reset(),put_state(scope,false),error_code(403,get(undefined,j([]))),?assertEqual(0,state(catalog_calls)),
    reset(),error_code(403,cb_acdc_live:get(cb_context:set_auth_doc(context(undefined,j([])),undefined),undefined)),
    ?assertEqual(0,state(catalog_calls)),
    reset(),error_code(403,cb_acdc_live:get(cb_context:set_db_name(context(undefined,j([])),kzs_util:format_account_db(?Q3)),undefined)),
    ?assertEqual(0,state(catalog_calls)),
    reset(),error_code(403,cb_acdc_live:get(cb_context:set_account_id(context(undefined,j([])),<<"bad">>),undefined)).
bad_queries()->
    Queries=[[{<<"page_size">>,V}] || V<-[0,101,<<"01">>,<<"+1">>,<<"1.0">>,1.5]]++
        [[{K,V}] || {K,V}<-[{<<"from">>,1},{<<"to">>,2},{<<"fields">>,[]},{<<"paginate">>,false},
             {<<"filter_account_id">>,?Q3},{<<"start_queue_id">>,<<"bad">>}]]++
        [[{<<"page_size">>,1},{<<"page_size">>,2}]],
    [begin reset(),error_code(400,get(undefined,j(P))),?assertEqual(0,state(catalog_calls)),?assertEqual(0,state(broker_calls)) end || P<-Queries],
    reset(),error_code(400,get(?Q,j([{<<"page_size">>,1}]))),?assertEqual(0,state(open_calls)),
    reset(),error_code(404,get(<<"bad">>,j([]))),?assertEqual(0,state(open_calls)).
bad_catalog()->
    BadDocs=[kz_json:set_value(<<"pvt_account_id">>,?Q3,doc(?Q)),
        kz_json:set_value(<<"pvt_type">>,<<"user">>,doc(?Q)),
        kz_json:set_value(<<"pvt_deleted">>,true,doc(?Q)),
        kz_json:set_value(<<"_deleted">>,true,doc(?Q))],
    [begin reset(),put_state(docs,[D]),error_code(503,get(undefined,j([]))),?assertEqual(0,state(broker_calls)) end || D<-BadDocs],
    [begin reset(),put_state(docs,Ds),error_code(503,get(undefined,j([{<<"page_size">>,1}]))),?assertEqual(0,state(broker_calls)) end ||
        Ds<-[[doc(?Q),doc(?Q2),doc(?Q3)],[doc(?Q2),doc(?Q)],[doc(?Q),doc(?Q)]]],
    reset(),put_state(doc_result,{error,not_found}),error_code(404,get(?Q,j([]))),
    reset(),put_state(doc_result,{ok,doc(?Q2)}),error_code(404,get(?Q,j([]))).
partial_sources()->
    [begin reset(),put_state(broker_mode,Mode),R=get(undefined,j([])),no_store(R),
        ?assertEqual(success,cb_context:resp_status(R)),D=cb_context:resp_data(R),[Q]=val(<<"queues">>,D),
        ?assertEqual(null,val(<<"metrics">>,Q)),?assertEqual(false,val(<<"metrics_available">>,Q)),
        ?assertEqual(Reason,kz_json:get_value([<<"source">>,<<"reason">>],D)) end ||
        {Mode,Reason}<-[{timeout,<<"source_timeout">>},{conflict,<<"inconsistent_sources">>},{invalid,<<"invalid_response">>}]],
    reset(),put_state(nodes_after,[?N1]),R=get(undefined,j([])),
    ?assertEqual(<<"source_set_changed">>,kz_json:get_value([<<"source">>,<<"reason">>],cb_context:resp_data(R))),
    reset(),put_state(broker_mode,duplicate),R2=get(undefined,j([])),
    [Q2]=val(<<"queues">>,cb_context:resp_data(R2)),?assertEqual(2,kz_json:get_value([<<"metrics">>,<<"current_waiting">>],Q2)).
no_source()->
    reset(),put_state(docs,[]),R=get(undefined,j([])),?assertEqual(success,cb_context:resp_status(R)),
    ?assertEqual([],val(<<"queues">>,cb_context:resp_data(R))),?assertEqual(0,state(node_calls)),?assertEqual(0,state(broker_calls)),
    reset(),put_state(nodes,[]),R2=get(undefined,j([])),[Q]=val(<<"queues">>,cb_context:resp_data(R2)),
    ?assertEqual(null,val(<<"metrics">>,Q)),?assertEqual(0,state(broker_calls)),
    ?assertEqual(<<"source_unavailable">>,kz_json:get_value([<<"source">>,<<"reason">>],cb_context:resp_data(R2))).
inventory_limits()->
    reset(),put_state(nodes,lists:duplicate(257,?N1)),error_code(503,get(undefined,j([]))),
    ?assertEqual(0,state(broker_calls)),
    reset(),put_state(nodes,[n01,n02,n03,n04,n05,n06,n07,n08,n09,n10,n11,n12,n13,n14,n15,n16,
        n17,n18,n19,n20,n21,n22,n23,n24,n25,n26,n27,n28,n29,n30,n31,n32,n33]),
    error_code(503,get(undefined,j([]))),?assertEqual(0,state(broker_calls)).

bounded_options_test()->
    ?assertEqual({50,undefined},cb_acdc_live:options(j([]),undefined)),
    ?assertEqual({100,?Q},cb_acdc_live:options(j([{<<"page_size">>,<<"100">>},{<<"start_queue_id">>,?Q}]),undefined)),
    ?assertEqual({1,undefined},cb_acdc_live:options(j([]),?Q)),
    [?assertThrow({live_error,400,_},cb_acdc_live:options(j([{K,V}]),undefined)) ||
        {K,V}<-[{<<"page_size">>,101},{<<"page_size">>,<<"0">>},{<<"page_size">>,<<"001">>},
               {<<"from">>,0},{<<"to">>,0},{<<"start_queue_id">>,<<"bad">>}]].

%% Every reply is formatted and validated by the actual current kapi module.
reply(Req,Node,Inc,N,AsOf,Wait,Complete)->
    Counts=j([{<<"current_waiting">>,N},{<<"current_handled">>,0},{<<"max_current_wait_seconds">>,Wait},
        {<<"records_entered">>,0},{<<"waiting_in_cohort">>,0},{<<"handled_in_cohort">>,0},
        {<<"processed_in_cohort">>,0},{<<"abandoned_in_cohort">>,0},
        {<<"average_answered_wait_seconds">>,null},{<<"average_processed_talk_seconds">>,null}]),
    Queues=[j([{<<"queue_id">>,Q},{<<"source_exhausted">>,Complete},{<<"observed">>,Counts},
        {<<"metrics">>,case Complete of true->Counts; false->null end}]) || Q<-props:get_value(<<"Queue-IDs">>,Req)],
    S0=j([{<<"version">>,1},{<<"account_id">>,props:get_value(<<"Account-ID">>,Req)},{<<"as_of">>,AsOf},
        {<<"timestamp_unit">>,<<"kazoo_gregorian_seconds">>},{<<"identity_semantics">>,<<"call_queue_pair">>},
        {<<"distinct_visit_metrics_available">>,false},{<<"agent_eligibility_available">>,false},{<<"workforce_metrics_available">>,false},
        {<<"window">>,j([{<<"from">>,props:get_value(<<"From">>,Req)},{<<"to">>,props:get_value(<<"To">>,Req)},
            {<<"predicate">>,<<"entered_from_inclusive_to_exclusive">>}])},
        {<<"source">>,j([{<<"availability">>,<<"available">>},{<<"coverage">>,<<"local_table_only">>},
            {<<"atomic_snapshot">>,false},{<<"exhausted">>,Complete},{<<"projection_complete">>,true},
            {<<"cluster_complete">>,false},{<<"archive_coverage">>,<<"unknown">>},
            {<<"completion_reason">>,case Complete of true-> <<"exhausted">>; false-> <<"scan_limit">> end},
            {<<"observation_started">>,props:get_value(<<"To">>,Req)},{<<"observation_finished">>,AsOf}])},
        {<<"queues">>,Queues}]),
    S=case props:get_value(<<"Include-Calls">>,Req) of
        true ->
            [Selected]=props:get_value(<<"Queue-IDs">>,Req),
            Rows=[j([{<<"call_id">>,<<"active-",(integer_to_binary(100000+I))/binary>>},
                {<<"queue_id">>,Selected},{<<"status">>,<<"waiting">>},
                {<<"entered_timestamp">>,AsOf-Wait},{<<"handled_timestamp">>,null}]) || I<-lists:seq(1,min(N,200))],
            kz_json:set_value(<<"active_calls">>,j([{<<"rows">>,Rows},{<<"limit">>,200},
                {<<"observed_count">>,N},{<<"truncated">>,N>200},{<<"complete">>,Complete andalso N=<200},
                {<<"order">>,<<"queue_id_entered_call_id">>},{<<"coverage">>,<<"local_table_only">>},
                {<<"atomic_snapshot">>,false}]),S0);
        _ -> S0
    end,
    Props=[{<<"Status">>,<<"ok">>},{<<"Snapshot">>,S},{<<"Source-ID">>,source_id(Node)},
        {<<"Source-Incarnation">>,incarnation(Inc)},{<<"Event-Category">>,<<"acdc_dashboard">>},
        {<<"Event-Name">>,<<"snapshot_resp">>},{<<"App-Name">>,<<"test">>},{<<"App-Version">>,<<"1">>}|Req],
    {ok,Encoded}=kapi_acdc_dashboard:snapshot_resp(Props),R=kz_json:decode(iolist_to_binary(Encoded)),
    ?assert(kapi_acdc_dashboard:snapshot_resp_v(R)),R.
pure_request()->Now=now_s()-5,[{<<"Account-ID">>,?A},{<<"Queue-IDs">>,[?Q]},
    {<<"From">>,Now-3600},{<<"To">>,Now},{<<"Msg-ID">>,<<"pure-correlation">>}].
assess(Responses,Req,Expected)->cb_acdc_live:assess({ok,Responses},Req,lists:sort(Expected),lists:sort(Expected)).
assert_unknown(Reason,{M,S})->?assertEqual(#{},M),?assertEqual(Reason,val(<<"reason">>,S)).

replica_assessment_test()->
    Req=pure_request(),To=props:get_value(<<"To">>,Req),A=source_id(?N1),B=source_id(?N2),
    R1=reply(Req,?N1,1,2,To,100,true),R2=reply(Req,?N2,1,2,To+1,101,true),
    ?assert(cb_acdc_live:correlated(R1,Req)),?assertEqual(cb_acdc_live:normalized(R1),cb_acdc_live:normalized(R2)),
    {M,S}=assess([R1,R2],Req,[A,B]),?assertEqual(2,kz_json:get_value(<<"current_waiting">>,maps:get(?Q,M))),
    ?assertEqual(<<"consensus">>,val(<<"reason">>,S)),
    ?assertNot(cb_acdc_live:correlated(kz_json:set_value(<<"Msg-ID">>,<<"old">>,R1),Req)),
    assert_unknown(<<"source_timeout">>,assess([R1],Req,[A,B])),
    assert_unknown(<<"inconsistent_sources">>,assess([R1,reply(Req,?N1,2,2,To,100,true)],Req,[A])),
    assert_unknown(<<"inconsistent_sources">>,assess([R1,reply(Req,?N2,1,3,To,100,true)],Req,[A,B])),
    assert_unknown(<<"incomplete_source">>,assess([reply(Req,?N1,1,0,To,null,false)],Req,[A])),
    assert_unknown(<<"source_set_changed">>,assess([R1,reply(Req,?N3,1,2,To,100,true)],Req,[A,B])),
    assert_unknown(<<"invalid_response">>,assess([kz_json:set_value(<<"Account-ID">>,?Q3,R1)],Req,[A])),
    assert_unknown(<<"response_limit">>,assess(lists:duplicate(64,R1),Req,[A])),
    assert_unknown(<<"source_set_changed">>,cb_acdc_live:assess({ok,[R1]},Req,[A],[B])),
    assert_unknown(<<"source_timeout">>,cb_acdc_live:assess({timeout,[R1]},Req,[A],[A])),
    assert_unknown(<<"source_unavailable">>,cb_acdc_live:assess({error,offline},Req,[A],[A])).
