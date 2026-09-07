%%% Real Crossbar context/route/DTO and real kapi serialization/validation.
%%% Provider mecks only: no HTTP listener, live broker, auth service or database.
-module(acdc_live_tests).
-include_lib("eunit/include/eunit.hrl").
-include_lib("kazoo_stdlib/include/kz_records.hrl").
-define(A, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(Q, <<"11111111111111111111111111111111">>).
-define(Q2, <<"22222222222222222222222222222222">>).
-define(Q3, <<"33333333333333333333333333333333">>).
-define(U, <<"44444444444444444444444444444444">>).
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
agent_doc()->j([{<<"_id">>,?U},{<<"pvt_type">>,<<"user">>},{<<"pvt_account_id">>,?A},
    {<<"first_name">>,<<"Live">>},{<<"last_name">>,<<"Agent">>},{<<"queues">>,[?Q]},
    {<<"pvt_secret">>,<<"NEVER-RETURN-PRIVATE-AGENT">>}]).
context(Queue,Query)->
    Params=case Queue of undefined->[<<"live">>]; _->[Queue,<<"live">>] end,
    cb_context:setters(cb_context:new(),[
        {fun cb_context:set_account_id/2,?A},{fun cb_context:set_auth_account_id/2,?A},
        {fun cb_context:set_auth_doc/2,j([{<<"owner_id">>,?Q3},{<<"method">>,<<"cb_user_auth">>}])},
        {fun cb_context:set_auth_token_type/2,'x-auth-token'},{fun cb_context:set_auth_token/2,<<"fixture-token">>},
        {fun cb_context:set_api_version/2,<<"v2">>},{fun cb_context:set_req_verb/2,<<"GET">>},
        {fun cb_context:set_req_nouns/2,[{<<"queues">>,Params},{<<"accounts">>,[?A]}]},
        {fun cb_context:set_raw_path/2,iolist_to_binary([<<"/v2/accounts/">>,?A,<<"/queues/">>,
            case Queue of undefined->[];_->[Queue,<<"/">>] end,<<"live">>])},
        {fun cb_context:set_query_string/2,Query},{fun cb_context:set_db_name/2,kzs_util:format_account_db(?A)},
        {fun cb_context:set_resp_etag/2,<<"old-cache-tag">>}]).
get(Queue,Query)->
    C=context(Queue,Query),
    Result=case Queue of undefined->cb_queues:validate(C,<<"live">>); _->cb_queues:validate(C,Queue,<<"live">>) end,
    capture_response(Queue,Result),Result.
capture_response(Queue,C)->
    case {os:getenv("LIVE_SNAPSHOT_DIR"),cb_context:resp_status(C)} of
        {Dir,success} when is_list(Dir)->
            Row=j([{<<"route">>,case Queue of undefined-> <<"overview">>; _-> <<"detail">> end},
                {<<"data">>,cb_context:resp_data(C)}]),
            ok=file:write_file(filename:join(Dir,"public-responses.ndjson"),[kz_json:encode(Row),<<"\n">>],[append]);
        _ -> ok
    end.
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
        {roster_calls,0},{agent_docs,[agent_doc()]},{resource_permits,[]},{agent_mode,normal},
        {blackhole_modules,[]},{node_calls,0},{permits,[]},{nodes,[?N1,?N2]},{nodes_after,same},{broker_mode,consensus}]],ok.
setup()->
    T=ets:new(acdc_live_fixture,[named_table,public]),reset(),
    meck:new([kz_datamgr,kz_nodes,kz_amqp_worker,crossbar_bindings,kz_auth_scope,blackhole_bindings],[non_strict,no_link]),
    meck:expect(blackhole_bindings,modules_loaded,fun()->case state(blackhole_modules) of fail->error(unavailable);Ms->Ms end end),
    meck:expect(crossbar_bindings,pmap,fun auth/2),
    meck:expect(kz_auth_scope,all,fun(<<"fixture-token">>,[<<"fixture:queues">>])->state(scope) end),
    meck:expect(kz_datamgr,get_results,fun(Db,<<"queues/crossbar_listing">>,Opts)->
        ?assertEqual(kzs_util:format_account_db(?A),Db),bump(catalog_calls),
        put_state(catalog_options,Opts),{ok,[j([{<<"doc">>,D}]) || D<-state(docs)]};
        (Db,<<"queues/agents_listing">>,Opts)->
        ?assertEqual(kzs_util:format_account_db(?A),Db),bump(roster_calls),
        ?assertEqual([?Q],props:get_value(startkey,Opts)),?assertEqual(201,props:get_value(limit,Opts)),
        ?assert(lists:member(include_docs,Opts)),?assertEqual(false,props:get_value(reduce,Opts)),
        {ok,[j([{<<"id">>,kz_doc:id(D)},{<<"key">>,[?Q,kz_doc:id(D)]},{<<"doc">>,D}]) || D<-state(agent_docs)]} end),
    meck:expect(kz_datamgr,open_doc,fun(Db,Q)->
        ?assertEqual(kzs_util:format_account_db(?A),Db),bump(open_calls),put_state(open_id,Q),
        case state(doc_result) of default->{ok,doc(Q)}; Result->Result end end),
    meck:expect(kz_nodes,nodes,fun()->
        Call=bump(node_calls),Ns=case {Call,state(nodes_after)} of {1,_}->state(nodes); {_,same}->state(nodes); {_,Other}->Other end,
        [#kz_node{node=N,kapps=[{<<"acdc">>,#whapp_info{startup=1}}],last_heartbeat=1} || N<-Ns] end),
    meck:expect(kz_amqp_worker,call_collect,fun broker/4),T.
teardown(T)->meck:unload([kz_datamgr,kz_nodes,kz_amqp_worker,crossbar_bindings,kz_auth_scope,blackhole_bindings]),ets:delete(T).
auth(<<"v2_resource.authorize">>,C)->
    [{Resource,Params}|_]=cb_context:req_nouns(C),
    put_state(resource_permits,[{Resource,Params}|state(resource_permits)]),
    case Resource of <<"queues">>->put_state(permits,[Params|state(permits)]);_->ok end,
    case lists:member(<<"live">>,Params) of
        true->ok;
        false->?assertEqual([],kz_json:to_proplist(cb_context:query_string(C))),
               ?assertEqual(<<"GET">>,cb_context:req_verb(C)),
               ?assertEqual(?A,cb_context:account_id(C))
    end,
    case state(auth_result) of
        normal->case state(denied)=:=Params orelse state(denied)=:={Resource,Params} of true->[false]; false->[true] end;
        Other->Other
    end;
auth(<<"v2_resource.authorize.queues">>,[_|_])->[];
auth(<<"v2_resource.authorize.agents">>,[_|_])->[];
auth(<<"v2_resource.allowed_scopes.queues">>,<<"cb_user_auth">>)->[[<<"fixture:queues">>]];
auth(<<"v2_resource.allowed_scopes.agents">>,<<"cb_user_auth">>)->[[<<"fixture:queues">>]];
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
        {caller,Left,Right}->{ok,[with_caller(R1,Left),with_caller(R2,Right)]};
        invalid->{ok,[kz_json:set_value(<<"Msg-ID">>,<<"wrong">>,R1),R2]}
    end.
with_caller(R,legacy)->R;
with_caller(R,{Name,Number})->
    Path=[<<"Snapshot">>,<<"active_calls">>,<<"rows">>],
    Rows=[{kz_json:to_proplist(Row)++[{<<"caller_id_name">>,Name},{<<"caller_id_number">>,Number}]} ||
        Row<-kz_json:get_value(Path,R)],
    raw_set(Path,Rows,R).
%% Preserve hostile wire bytes; the public handler must reject, not repair.
raw_set([K],V,{Props}) -> {lists:keystore(K,1,Props,{K,V})};
raw_set([K|Rest],V,{Props}) ->
    {lists:keyreplace(K,1,Props,{K,raw_set(Rest,V,proplists:get_value(K,Props))})}.

public_route_test_()->{setup,fun setup/0,fun teardown/1,fun(_)->[
    {"WebSocket capability follows local registration without claiming delivery health",fun websocket_capability/0},
    {"real overview and detail routes, no-store and no replica summation",fun public_success/0},
    {"detail call rows, bounded truncation and unknown versus empty",fun detail_calls/0},
    {"selected caller identity is exact nullable and legacy fields stay unknown",fun detail_caller_identity/0},
    {"caller disagreement withholds replicas instead of choosing metadata",fun detail_caller_disagreement/0},
    {"malformed native caller text cannot reach public JSON",fun detail_caller_invalid/0},
    {"runtime agent observations share the authorized snapshot request",fun detail_agents/0},
    {"embedded roster and agent permissions fail closed before broker",fun agent_authorization/0},
    {"malformed or foreign roster documents cannot enter runtime scope",fun agent_roster_scope/0},
    {"bounded catalog pagination and lookahead permissions",fun pagination/0},
    {"auth, tenant DB, underlying stats and queue permissions",fun authorization/0},
    {"unsupported queries fail before catalog or broker",fun bad_queries/0},
    {"invalid/oversized/unsorted/deleted catalog is never returned",fun bad_catalog/0},
    {"missing/conflicting/changed replicas produce unknown metrics",fun partial_sources/0},
    {"node inventory and selected source caps are enforced",fun inventory_limits/0},
    {"empty inventory and no known source do not call broker",fun no_source/0}
] end}.
websocket_capability()->
    [begin reset(),put_state(blackhole_modules,Modules),
        C=get(undefined,j([])),?assertEqual(success,cb_context:resp_status(C)),
        ?assertEqual(Expected,kz_json:get_value([<<"capabilities">>,<<"websocket_updates">>],cb_context:resp_data(C)))
    end || {Modules,Expected}<-[{[],false},{[bh_call],false},{[bh_call,bh_queue_live],true},{fail,false}]].
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
    ?assertEqual(7,length(kz_json:to_proplist(First))),
    ?assertEqual(null,val(<<"caller_id_name">>,First)),
    ?assertEqual(null,val(<<"caller_id_number">>,First)),
    ?assert(abs(val(<<"entered_at">>,First)-(now_s()-?EPOCH-100))<5).
detail_caller_identity()->
    Name=unicode:characters_to_binary([16#0645,16#0631,16#062D,16#0628,16#0627]),
    Number= <<"+15550000100">>,
    [begin reset(),put_state(broker_mode,{caller,L,R}),
        C=get(?Q,j([])),?assertEqual(success,cb_context:resp_status(C)),no_store(C),
        D=cb_context:resp_data(C),Calls=val(<<"calls">>,D),
        ?assertEqual(true,val(<<"available">>,Calls)),
        ?assertEqual(<<"consensus">>,kz_json:get_value([<<"source">>,<<"reason">>],D)),
        [begin ?assertEqual(7,length(kz_json:to_proplist(Row))),
            ?assertEqual(Expected,{val(<<"caller_id_name">>,Row),val(<<"caller_id_number">>,Row)}),
            [?assertEqual(undefined,val(K,Row)) || K<-[<<"name_status">>,<<"number_status">>,<<"privacy">>]]
         end || Row<-val(<<"rows">>,Calls)]
     end || {L,R,Expected}<-[{legacy,legacy,{null,null}},
        {legacy,{null,null},{null,null}},{{null,null},legacy,{null,null}},
        {{Name,Number},{Name,Number},{Name,Number}},{{Name,null},{Name,null},{Name,null}},
        {{null,Number},{null,Number},{null,Number}}]],
    reset(),D=cb_context:resp_data(get(undefined,j([]))),
    ?assertEqual(null,val(<<"calls">>,D)),
    [?assertEqual(nomatch,binary:match(iolist_to_binary(kz_json:encode(D)),K)) ||
        K<-[<<"caller_id_name">>,<<"caller_id_number">>,Name,Number]].
detail_caller_disagreement()->
    A={<<"First identity">>,<<"+15550000100">>},
    [begin reset(),put_state(broker_mode,{caller,L,R}),
        D=cb_context:resp_data(get(?Q,j([]))),Calls=val(<<"calls">>,D),
        ?assertEqual(<<"inconsistent_sources">>,kz_json:get_value([<<"source">>,<<"reason">>],D)),
        ?assertEqual(false,val(<<"available">>,Calls)),?assertEqual([],val(<<"rows">>,Calls)),
        ?assertEqual(null,val(<<"observed_count">>,Calls)),
        [?assertEqual(null,val(<<"metrics">>,Q)) || Q<-val(<<"queues">>,D)],
        ?assertEqual(nomatch,binary:match(iolist_to_binary(kz_json:encode(D)),<<"First identity">>))
     end || {L,R}<-[{legacy,A},{A,legacy},{{null,null},A},{A,{null,null}},
        {A,{<<"Other identity">>,<<"+15550000100">>}},
        {A,{<<"First identity">>,<<"+15550000101">>}},
        {{<<"First identity">>,null},{null,<<"+15550000100">>}}]].
detail_caller_invalid()->
    [begin reset(),put_state(broker_mode,{caller,legacy,{Bad,null}}),
        D=cb_context:resp_data(get(?Q,j([]))),
        ?assertEqual(<<"invalid_response">>,kz_json:get_value([<<"source">>,<<"reason">>],D)),
        ?assertEqual([],kz_json:get_value([<<"calls">>,<<"rows">>],D)),
        ?assertEqual(false,kz_json:get_value([<<"calls">>,<<"available">>],D))
     end || Bad<-[<<"bad\nname">>,<<>>,<<" ">>,binary:copy(<<"x">>,257),<<255>>,
        unicode:characters_to_binary([16#202E]),[],false,j([{<<"name">>,<<"PRIVATE">>}])]].
detail_agents()->
    reset(),D=cb_context:resp_data(get(?Q,j([]))),A=val(<<"agents">>,D),
    ?assertEqual(1,state(roster_calls)),?assertEqual(1,state(broker_calls)),
    ?assertEqual(true,kz_json:get_value([<<"capabilities">>,<<"agent_runtime">>],D)),
    ?assertEqual(true,val(<<"runtime_complete">>,A)),
    [R]=val(<<"rows">>,A),?assertEqual(?U,val(<<"agent_id">>,R)),
    ?assertEqual(<<"Live Agent">>,val(<<"name">>,R)),
    ?assertEqual(true,val(<<"queue_member">>,R)),?assertEqual(<<"ready">>,val(<<"state">>,R)),
    ?assertEqual(undefined,val(<<"instance">>,R)),
    ?assertEqual(false,val(<<"endpoint_reachability_verified">>,A)),
    [begin reset(),put_state(agent_mode,Mode),AD=val(<<"agents">>,cb_context:resp_data(get(?Q,j([])))),
        ?assertEqual(false,val(<<"runtime_complete">>,AD)),[AR]=val(<<"rows">>,AD),
        ?assertEqual(false,val(<<"observed">>,AR)),?assertEqual(null,val(<<"queue_member">>,AR)),
        ?assertEqual(Reason,val(<<"reason">>,AR)) end ||
        {Mode,Reason}<-[{conflict,<<"inconsistent_sources">>},{timeout,<<"source_unavailable">>},
            {absent,<<"not_observed">>}]],
    reset(),put_state(broker_mode,timeout),Unknown=val(<<"agents">>,cb_context:resp_data(get(?Q,j([])))),
    ?assertEqual(null,val(<<"observation_started">>,Unknown)),
    reset(),put_state(agent_docs,[]),Empty=val(<<"agents">>,cb_context:resp_data(get(?Q,j([])))),
    ?assertEqual([],val(<<"rows">>,Empty)),?assertEqual(true,val(<<"runtime_complete">>,Empty)),
    reset(),Overview=cb_context:resp_data(get(undefined,j([]))),
    ?assertEqual(null,val(<<"agents">>,Overview)),?assertEqual(0,state(roster_calls)).
agent_authorization()->
    [begin reset(),put_state(denied,Deny),error_code(403,get(?Q,j([]))),
        ?assertEqual(0,state(broker_calls)) end || Deny<-[
        {<<"queues">>,[?Q,<<"roster">>]},
        {<<"agents">>,[?U]},{<<"agents">>,[?U,<<"status">>]}]].
agent_roster_scope()->
    [begin reset(),put_state(agent_docs,[D]),error_code(503,get(?Q,j([]))),
        ?assertEqual(0,state(broker_calls)) end || D<-[
        kz_json:set_value(<<"pvt_account_id">>,?Q3,agent_doc()),
        kz_json:set_value(<<"pvt_type">>,<<"queue">>,agent_doc()),
        kz_json:set_value(<<"pvt_deleted">>,true,agent_doc()),
        kz_json:set_value(<<"queues">>,[?Q2],agent_doc())]],
    reset(),put_state(agent_docs,[agent_doc(),agent_doc()]),error_code(503,get(?Q,j([]))).
detail_calls()->
    [begin reset(),put_state(broker_mode,Mode),R=get(?Q,j([])),
        ?assertEqual(success,cb_context:resp_status(R)),D=cb_context:resp_data(R),
        C=val(<<"calls">>,D),?assertEqual(false,val(<<"available">>,C)),
        ?assertEqual(null,val(<<"observed_count">>,C)),?assertEqual([],val(<<"rows">>,C)),
        [Q]=val(<<"queues">>,D),?assertEqual(null,val(<<"metrics">>,Q)),
        ?assertEqual(Reason,kz_json:get_value([<<"source">>,<<"reason">>],D)) end ||
        {Mode,Reason}<-[{timeout,<<"source_timeout">>},{call_conflict,<<"inconsistent_sources">>},
            {missing_flag,<<"invalid_response">>}]],
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
    SCalls=case props:get_value(<<"Include-Calls">>,Req) of
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
    S=case props:get_value(<<"Agent-IDs">>,Req) of
        undefined -> SCalls;
        AgentIds ->
            [SelectedQueue]=props:get_value(<<"Queue-IDs">>,Req),
            Mode=state(agent_mode),
            AgentRows=[agent_observation(Id,Node,Mode) || Id<-AgentIds],
            Observation=acdc_dashboard_agent_codec:encode(#{account_id=>?A,queue_id=>SelectedQueue,
                observation_started=>AsOf,observation_finished=>AsOf,rows=>AgentRows}),
            kz_json:set_value(<<"agents">>,Observation,SCalls)
    end,
    Props=[{<<"Status">>,<<"ok">>},{<<"Snapshot">>,S},{<<"Source-ID">>,source_id(Node)},
        {<<"Source-Incarnation">>,incarnation(Inc)},{<<"Event-Category">>,<<"acdc_dashboard">>},
        {<<"Event-Name">>,<<"snapshot_resp">>},{<<"App-Name">>,<<"test">>},{<<"App-Version">>,<<"1">>}|Req],
    {ok,Encoded}=kapi_acdc_dashboard:snapshot_resp(Props),R=kz_json:decode(iolist_to_binary(Encoded)),
    ?assert(kapi_acdc_dashboard:snapshot_resp_v(R)),R.
agent_observation(Id,Node,Mode)->
    Base=#{agent_id=>Id,observed=>false,member=>null,state=>null,reason=>not_observed,instance=>null},
    case {Mode,Node} of
        {absent,_}->Base;
        {timeout,?N2}->Base#{reason=>timeout};
        {conflict,?N2}->Base#{observed=>true,member=>false,state=><<"paused">>,reason=>observed,instance=>incarnation(2)};
        {_,?N1}->Base#{observed=>true,member=>true,state=><<"ready">>,reason=>observed,instance=>incarnation(1)};
        _->Base
    end.
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
    assert_unknown(<<"source_unavailable">>,cb_acdc_live:assess({error,offline},Req,[A],[A])),
    DetailReq=[{<<"Include-Calls">>,true}|Req],
    Legacy=reply(DetailReq,?N1,1,2,To,100,true),
    Unknown=with_caller(Legacy,{null,null}),
    Named=with_caller(Legacy,{<<"Synthetic identity">>,<<"+15550000100">>}),
    ?assertEqual(cb_acdc_live:normalized(Legacy),cb_acdc_live:normalized(Unknown)),
    ?assertNotEqual(cb_acdc_live:normalized(Legacy),cb_acdc_live:normalized(Named)),
    %% Even a single replica must not issue conflicting identity for one
    %% incarnation and be selected arbitrarily after duplicate suppression.
    assert_unknown(<<"inconsistent_sources">>,assess([Named,Legacy],DetailReq,[A])),
    assert_unknown(<<"inconsistent_sources">>,assess([Named,
        with_caller(Legacy,{<<"Changed identity">>,<<"+15550000100">>})],DetailReq,[A])),
    {_,Agreement}=assess([Legacy,Unknown],DetailReq,[A]),
    ?assertEqual(<<"consensus">>,val(<<"reason">>,Agreement)).
