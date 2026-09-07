%%% Actual kapi/JSON/collector/ETS; only broker delivery and stats supervisor
%%% discovery are controlled. This does not claim a real AMQP round trip.
-module(acdc_dashboard_amqp_tests).
-include_lib("eunit/include/eunit.hrl").
-include("acdc_stats.hrl").
-define(A, <<"11111111111111111111111111111111">>).
-define(Q, <<"22222222222222222222222222222222">>).
-define(Q2, <<"33333333333333333333333333333333">>).

now_s() -> calendar:datetime_to_gregorian_seconds(calendar:universal_time()).
request() -> kz_json:from_list([{<<"Account-ID">>,?A},{<<"Queue-IDs">>,[?Q]},
    {<<"From">>,now_s()-3600},{<<"To">>,now_s()},{<<"Msg-ID">>,<<"request-123">>},
    {<<"Server-ID">>,<<"reply-test">>},{<<"Event-Category">>,<<"acdc_dashboard">>},
    {<<"Event-Name">>,<<"snapshot_req">>},{<<"App-Name">>,<<"test">>},{<<"App-Version">>,<<"1">>}]).
waiting() -> #call_stat{id = <<"call::",?Q/binary>>,call_id = <<"call">>,account_id=?A,
    queue_id=?Q,entered_timestamp=now_s()-5000,status = <<"waiting">>,
    caller_id_name = <<"NEVER-COPY-CALLER">>,caller_id_number = <<"NEVER-COPY-NUMBER">>,
    misses=[{private,<<"NEVER-COPY-MISSES">>}]}.
detail_request() -> kz_json:set_value(<<"Include-Calls">>,true,request()).
detail(R) -> kz_json:get_value([<<"Snapshot">>,<<"active_calls">>],R).

include_calls_request_scope_and_roundtrip_test() ->
    %% Default set_value/3 treats null as deletion; explicitly retain the bad
    %% wire value so this is not accidentally a valid absent/legacy request.
    [begin
        BadReq=kz_json:set_value(<<"Include-Calls">>,Bad,request(),#{keep_null=>true}),
        ?assertEqual(Bad,kz_json:get_value(<<"Include-Calls">>,BadReq)),
        Wire=kz_json:decode(iolist_to_binary(kz_json:encode(BadReq))),
        ?assertEqual(Bad,kz_json:get_value(<<"Include-Calls">>,Wire)),
        ?assertNot(kapi_acdc_dashboard:snapshot_req_v(Wire)),
        ?assertNot(kapi_acdc_dashboard:snapshot_req_v(kz_json:to_proplist(Wire)))
     end ||
        Bad<-[null,0,1,<<"true">>,[],kz_json:new()]],
    ?assertNot(kapi_acdc_dashboard:snapshot_req_v(kz_json:set_value(<<"Queue-IDs">>,[?Q,?Q2],detail_request()))),
    [?assert(kapi_acdc_dashboard:snapshot_req_v(Req)) || Req<-[detail_request(),
        kz_json:set_values([{<<"Include-Calls">>,false},{<<"Queue-IDs">>,[?Q,?Q2]}],request())]],
    [begin {ok,Encoded}=kapi_acdc_dashboard:snapshot_req(kz_json:set_value(<<"Include-Calls">>,Flag,request())),
     ?assertEqual(Flag,kz_json:get_value(<<"Include-Calls">>,kz_json:decode(iolist_to_binary(Encoded)))) end ||
     Flag<-[false,true]],
    {ok,Legacy}=kapi_acdc_dashboard:snapshot_req(request()),
    ?assertEqual(undefined,kz_json:get_value(<<"Include-Calls">>,kz_json:decode(iolist_to_binary(Legacy)))).

request_roundtrip_and_closed_fields_test() ->
    Req=request(), ?assert(kapi_acdc_dashboard:snapshot_req_v(Req)),
    Extra=kz_json:set_values([{<<"Budget-Ms">>,999999},{<<"Max-Scan">>,999999},
                              {<<"private">>,<<"NEVER-COPY">>}],Req),
    {ok,Payload}=kapi_acdc_dashboard:snapshot_req(Extra),
    Decoded=kz_json:decode(iolist_to_binary(Payload)),
    ?assert(kapi_acdc_dashboard:snapshot_req_v(Decoded)),
    ?assertEqual(undefined,kz_json:get_value(<<"Budget-Ms">>,Decoded)),
    ?assertEqual(undefined,kz_json:get_value(<<"private">>,Decoded)),
    ?assertEqual(?A,kz_json:get_value(<<"Account-ID">>,Decoded)).

invalid_request_scope_test_() ->
    [?_assertNot(kapi_acdc_dashboard:snapshot_req_v(kz_json:set_value(K,V,request()))) || {K,V}<-[
        {<<"Account-ID">>,<<"*">>},{<<"Account-ID">>,binary:copy(<<"A">>,32)},
        {<<"Queue-IDs">>,[]},{<<"Queue-IDs">>,[?Q,?Q]},
        {<<"Queue-IDs">>,lists:duplicate(101,?Q)},{<<"Queue-IDs">>,[<<"queue.#">>]},
        {<<"From">>,now_s()-86401},
        {<<"From">>,now_s()},{<<"To">>,now_s()+100},
        {<<"Msg-ID">>,<<>>},{<<"Msg-ID">>,binary:copy(<<"x">>,129)},
        {<<"Server-ID">>,<<>>},{<<"Server-ID">>,<<"reply\nqueue">>},
        {<<"Event-Category">>,<<"acdc_stat">>},{<<"Event-Name">>,<<"current_calls_req">>}]].

malformed_raw_request_terms_test() ->
    Props=kz_json:to_proplist(request()),
    Raw=[{<<"Queue-IDs">>,[?Q|bad_tail]}|proplists:delete(<<"Queue-IDs">>,Props)],
    ?assertNot(kapi_acdc_dashboard:snapshot_req_v(Raw)),
    [?assertNot(kapi_acdc_dashboard:snapshot_req_v(V)) || V<-[undefined,42,[bad],[],kz_json:new()]].

agent_scope_contract_test() ->
    Id=binary:copy(<<"a">>,32),
    [begin R=kz_json:set_value(<<"Agent-IDs">>,Ids,detail_request()),
        ?assert(kapi_acdc_dashboard:snapshot_req_v(R)),
        {ok,Wire}=kapi_acdc_dashboard:snapshot_req(R),
        ?assertEqual(Ids,kz_json:get_value(<<"Agent-IDs">>,kz_json:decode(iolist_to_binary(Wire))))
     end || Ids<-[[],[Id]]],
    [begin R=kz_json:set_value(<<"Agent-IDs">>,Ids,detail_request(),#{keep_null=>true}),
        ?assertNot(kapi_acdc_dashboard:snapshot_req_v(R))
     end || Ids<-[null,[<<"bad">>],[Id,Id],[Id,?Q],lists:duplicate(201,Id),false]],
    ?assertNot(kapi_acdc_dashboard:snapshot_req_v(kz_json:set_values([
        {<<"Agent-IDs">>,[]},{<<"Include-Calls">>,false},{<<"Queue-IDs">>,[?Q,?Q2]}],request()))).

agent_observation_transport_test() -> with_source(fun(_)->
    Id=binary:copy(<<"a">>,32),
    %% A deliberately absent local registry is unknown, never logged out.
    Req=kz_json:set_value(<<"Agent-IDs">>,[Id],detail_request()),
    R=response(Req,self()),J=kz_json:get_value([<<"Snapshot">>,<<"agents">>],R),
    ?assertEqual([Id],kz_json:get_value(<<"Agent-IDs">>,R)),
    [Row]=kz_json:get_value(<<"rows">>,J),
    ?assertEqual(false,kz_json:get_value(<<"observed">>,Row)),
    ?assertEqual(null,kz_json:get_value(<<"member">>,Row)),
    ?assertEqual(null,kz_json:get_value(<<"state">>,Row)),
    [begin Bad=kz_json:set_value([<<"Snapshot">>,<<"agents">>,K],V,R,#{keep_null=>true}),
        ?assertNot(kapi_acdc_dashboard:snapshot_resp_v(Bad))
     end || {K,V}<-[{<<"account_id">>,?Q2},{<<"queue_id">>,?Q2},{<<"limit">>,201},
        {<<"endpoint_reachability_verified">>,true},{<<"atomic_snapshot">>,true},
        {<<"observation_started">>,1},{<<"rows">>,[Row,Row]},{<<"private">>,<<"secret">>}]],
    ?assertNot(kapi_acdc_dashboard:snapshot_resp_v(kz_json:delete_key(<<"Agent-IDs">>,R))),
    ?assertNot(kapi_acdc_dashboard:snapshot_resp_v(kz_json:delete_key([<<"Snapshot">>,<<"agents">>],R)))
end).

agent_codec_merge_test() ->
    Id=binary:copy(<<"a">>,32),Now=now_s(),
    Unknown=#{agent_id=>Id,observed=>false,member=>null,state=>null,reason=>not_observed,instance=>null},
    Ready=#{agent_id=>Id,observed=>true,member=>true,state=><<"ready">>,reason=>observed,
        instance=>binary:copy(<<"b">>,64)},
    Snap=fun(Row)->acdc_dashboard_agent_codec:encode(#{account_id=>?A,queue_id=>?Q,
        observation_started=>Now,observation_finished=>Now,rows=>[Row]}) end,
    U=Snap(Unknown),Yes=Snap(Ready),No=Snap(Ready#{member=>false}),
    lists:foreach(fun(J)->?assert(acdc_dashboard_agent_codec:valid(J,?A,?Q,[Id],Now)) end,[U,Yes,No]),
    [Combined]=acdc_dashboard_agent_codec:combine([Id],[U,Yes]),
    ?assertEqual(true,kz_json:get_value(<<"queue_member">>,Combined)),
    ?assertEqual(undefined,kz_json:get_value(<<"instance">>,Combined)),
    [Conflict]=acdc_dashboard_agent_codec:combine([Id],[Yes,No]),
    ?assertEqual(<<"inconsistent_sources">>,kz_json:get_value(<<"reason">>,Conflict)),
    [Missing]=acdc_dashboard_agent_codec:combine([Id],[U,U]),
    ?assertEqual(<<"not_observed">>,kz_json:get_value(<<"reason">>,Missing)),
    [Timeout]=acdc_dashboard_agent_codec:combine([Id],[Yes,Snap(Unknown#{reason=>timeout})]),
    ?assertEqual(<<"source_unavailable">>,kz_json:get_value(<<"reason">>,Timeout)),
    [begin Bad=kz_json:set_value([<<"rows">>],[kz_json:set_value(K,V,hd(kz_json:get_value(<<"rows">>,Yes)))],Yes),
        ?assertNot(acdc_dashboard_agent_codec:valid(Bad,?A,?Q,[Id],Now))
     end || {K,V}<-[{<<"state">>,<<"logged_out">>},{<<"member">>,1},{<<"instance">>,<<"raw-pid">>}]].

with_source(F) ->
    Parent=self(), T=ets:new(acdc_stats_call,[named_table,protected,{keypos,#call_stat.id}]),
    meck:new(kz_amqp_util,[non_strict,no_link]),
    meck:new(acdc_stats_sup,[non_strict,no_link]),
    try
        meck:expect(acdc_stats_sup,stats_srv,fun()->{ok,Parent} end),
        meck:expect(kz_amqp_util,targeted_publish,fun(<<"reply-test">>,Payload,<<"application/json">>)->
            J=kz_json:decode(iolist_to_binary(Payload)), Parent!{dashboard_response,J}, ok end),
        F(T)
    after
        meck:unload(kz_amqp_util),meck:unload(acdc_stats_sup),
        case ets:whereis(acdc_stats_call) of undefined->ok; _->ets:delete(acdc_stats_call) end
    end.
response(Req,Server) ->
    ?assertEqual(ok,acdc_dashboard_snapshot:handle_req(Req,[{server,Server}])),
    receive {dashboard_response,J}->?assert(kapi_acdc_dashboard:snapshot_resp_v(J)),J
    after 1000->error(missing_response) end.

actual_collector_response_and_strict_schema_test() -> with_source(fun(T)->
    ets:insert(T,waiting()), Req=request(), R=response(Req,self()), S=kz_json:get_value(<<"Snapshot">>,R),
    ?assertEqual(<<"ok">>,kz_json:get_value(<<"Status">>,R)),
    ?assertEqual(?A,kz_json:get_value(<<"Account-ID">>,R)),
    ?assertEqual([?Q],kz_json:get_value(<<"Queue-IDs">>,R)),
    ?assertEqual(<<"request-123">>,kz_json:get_value(<<"Msg-ID">>,R)),
    ?assertEqual(kz_term:to_hex_binary(crypto:hash(sha256,atom_to_binary(node(),utf8))),kz_json:get_value(<<"Source-ID">>,R)),
    ?assertEqual(kz_term:to_hex_binary(crypto:hash(sha256,term_to_binary({acdc_dashboard,node(),self()}))),kz_json:get_value(<<"Source-Incarnation">>,R)),
    [Q]=kz_json:get_value(<<"queues">>,S), C=kz_json:get_value(<<"metrics">>,Q),
    ?assertEqual(undefined,kz_json:get_value(<<"Include-Calls">>,R)),
    ?assertEqual(undefined,detail(R)),
    ?assertEqual(1,kz_json:get_value(<<"current_waiting">>,C)),
    ?assertEqual(0,kz_json:get_value(<<"records_entered">>,C)),
    ?assertEqual(null,kz_json:get_value(<<"average_answered_wait_seconds">>,C)),
    Src=kz_json:get_value(<<"source">>,S),
    ?assertEqual(false,kz_json:get_value(<<"cluster_complete">>,Src)),
    [?assertEqual(undefined,kz_json:get_value(K,Src)) || K<-[<<"scan_keys">>,<<"node">>,<<"input_rows">>]],
    Bytes=iolist_to_binary(kz_json:encode(S)),
    [?assertEqual(nomatch,binary:match(Bytes,Secret)) || Secret<-[<<"NEVER-COPY">>,<<"call::">>]],
    Mutations=[{[<<"Account-ID">>],?Q2},{[<<"Queue-IDs">>],[?Q2]},
        {[<<"Source-ID">>],<<"raw-node">>},{[<<"Source-Incarnation">>],<<"bad">>},
        {[<<"Snapshot">>,<<"private">>],<<"PII">>},
        {[<<"Snapshot">>,<<"source">>,<<"node">>],<<"private@host">>},
        {[<<"Snapshot">>,<<"source">>,<<"scan_keys">>],123},
        {[<<"Snapshot">>,<<"source">>,<<"cluster_complete">>],true},
        {[<<"Snapshot">>,<<"source">>,<<"observation_started">>],1},
        {[<<"Snapshot">>,<<"window">>,<<"from">>],1},
        {[<<"Snapshot">>,<<"as_of">>],now_s()+100}],
    [?assertNot(kapi_acdc_dashboard:snapshot_resp_v(kz_json:set_value(Path,V,R))) || {Path,V}<-Mutations],
    [?assertNot(kapi_acdc_dashboard:snapshot_resp_v(kz_json:set_value([<<"Snapshot">>,<<"queues">>],Qs,R))) ||
        Qs<-[[Q,Q],[],[kz_json:set_value(<<"queue_id">>,?Q2,Q)],
             [kz_json:set_value([<<"metrics">>,<<"current_waiting">>],10001,Q)],
             [kz_json:set_value(<<"metrics">>,null,Q)],
             [kz_json:set_value(<<"caller">>,<<"private">>,Q)]]],
    %% Same stats process, different requests: stable source incarnation.
    R2=response(kz_json:set_value(<<"Msg-ID">>,<<"second">>,Req),self()),
    ?assertEqual(kz_json:get_value(<<"Source-Incarnation">>,R),kz_json:get_value(<<"Source-Incarnation">>,R2)),
    ?assertEqual(false,ets:info(T,safe_fixed))
end).

actual_detail_response_and_strict_schema_test() -> with_source(fun(T)->
    E=now_s()-50,
    H=(waiting())#call_stat{id= <<"handled::",?Q/binary>>,call_id= <<"handled">>,
        status= <<"handled">>,entered_timestamp=E,handled_timestamp=E+5},
    ets:insert(T,[waiting(),H]),
    R=response(detail_request(),self()), A=detail(R),
    ?assertEqual(true,kz_json:get_value(<<"Include-Calls">>,R)),
    ?assertEqual(2,kz_json:get_value(<<"observed_count">>,A)),
    ?assertEqual(true,kz_json:get_value(<<"complete">>,A)),
    ?assertEqual(false,kz_json:get_value(<<"truncated">>,A)),
    ?assertEqual(200,kz_json:get_value(<<"limit">>,A)),
    ?assertEqual(<<"queue_id_entered_call_id">>,kz_json:get_value(<<"order">>,A)),
    [WRow,HRow]=kz_json:get_value(<<"rows">>,A),
    ?assertEqual(<<"call">>,kz_json:get_value(<<"call_id">>,WRow)),
    ?assertEqual(null,kz_json:get_value(<<"handled_timestamp">>,WRow)),
    ?assert(kz_json:get_value(<<"entered_timestamp">>,WRow)<kz_json:get_value(<<"From">>,R)),
    ?assertEqual(E+5,kz_json:get_value(<<"handled_timestamp">>,HRow)),
    ?assertEqual(?Q,kz_json:get_value(<<"queue_id">>,HRow)),
    ?assertEqual(nomatch,binary:match(iolist_to_binary(kz_json:encode(A)),<<"NEVER-COPY">>)),
    Prefix=[<<"Snapshot">>,<<"active_calls">>],
    Mutations=[{<<"limit">>,201},{<<"observed_count">>,-1},{<<"observed_count">>,10001},
        {<<"observed_count">>,3},{<<"complete">>,false},{<<"truncated">>,true},
        {<<"order">>,<<"queue_position">>},{<<"coverage">>,<<"cluster">>},
        {<<"atomic_snapshot">>,true},{<<"caller_id_name">>,<<"private">>}],
    [?assertNot(kapi_acdc_dashboard:snapshot_resp_v(kz_json:set_value(Prefix++[K],V,R))) || {K,V}<-Mutations],
    BadRows=[[],[WRow],[WRow,WRow],[HRow,WRow],lists:duplicate(201,WRow),
        [kz_json:set_value(<<"queue_id">>,?Q2,WRow),HRow],
        [kz_json:set_value(<<"call_id">>,<<>>,WRow),HRow],
        [kz_json:set_value(<<"call_id">>,binary:copy(<<"x">>,257),WRow),HRow],
        [kz_json:set_value(<<"call_id">>,<<"bad\ncall">>,WRow),HRow],
        [kz_json:set_value(<<"status">>,<<"processed">>,WRow),HRow],
        [kz_json:set_value(<<"entered_timestamp">>,0,WRow),HRow],
        [kz_json:set_value(<<"entered_timestamp">>,now_s()+100,WRow),HRow],
        [kz_json:set_value(<<"handled_timestamp">>,E,WRow),HRow],
        [WRow,kz_json:set_value(<<"handled_timestamp">>,null,HRow)],
        [WRow,kz_json:set_value(<<"handled_timestamp">>,E-1,HRow)],
        [WRow,kz_json:set_value(<<"handled_timestamp">>,now_s()+100,HRow)],
        [WRow,kz_json:set_value(<<"call_id">>,<<"call">>,HRow)],
        [WRow,kz_json:set_value(<<"agent_id">>,<<"private">>,HRow)]],
    [?assertNot(kapi_acdc_dashboard:snapshot_resp_v(kz_json:set_value(Prefix++[<<"rows">>],Rs,R))) || Rs<-BadRows],
    ?assertNot(kapi_acdc_dashboard:snapshot_resp_v(kz_json:delete_key(Prefix,R))),
    ?assertNot(kapi_acdc_dashboard:snapshot_resp_v(kz_json:delete_key(<<"Include-Calls">>,R))),
    ?assertNot(kapi_acdc_dashboard:snapshot_resp_v(kz_json:set_value(<<"Include-Calls">>,false,R))),
    %% Row length still matches metadata, but exhausted queue counts do not.
    [Q]=kz_json:get_value([<<"Snapshot">>,<<"queues">>],R),
    WrongQ=kz_json:set_values([{[<<"observed">>,<<"current_waiting">>],2},
                               {[<<"metrics">>,<<"current_waiting">>],2}],Q),
    ?assertNot(kapi_acdc_dashboard:snapshot_resp_v(kz_json:set_value([<<"Snapshot">>,<<"queues">>],[WrongQ],R))),
    False=response(kz_json:set_value(<<"Include-Calls">>,false,request()),self()),
    ?assertEqual(false,kz_json:get_value(<<"Include-Calls">>,False)),
    ?assertEqual(undefined,detail(False)),
    ?assertNot(kapi_acdc_dashboard:snapshot_resp_v(kz_json:set_value(<<"Include-Calls">>,true,False)))
end).

actual_detail_cap_and_error_echo_test() -> with_source(fun(T)->
    E=now_s()-500,
    ets:insert(T,[(waiting())#call_stat{id= <<(integer_to_binary(I))/binary,"::",?Q/binary>>,
        call_id=integer_to_binary(I),entered_timestamp=E+I} || I<-lists:seq(1,201)]),
    R=response(detail_request(),self()), A=detail(R), Rows=kz_json:get_value(<<"rows">>,A),
    ?assertEqual(200,length(Rows)),?assertEqual(201,kz_json:get_value(<<"observed_count">>,A)),
    ?assertEqual(true,kz_json:get_value(<<"truncated">>,A)),
    ?assertEqual(false,kz_json:get_value(<<"complete">>,A)),
    ?assertEqual([integer_to_binary(I) || I<-lists:seq(1,200)],
                 [kz_json:get_value(<<"call_id">>,Row) || Row<-Rows]),
    ?assertEqual(true,kz_json:get_value([<<"Snapshot">>,<<"source">>,<<"exhausted">>],R)),
    ?assertNot(kapi_acdc_dashboard:snapshot_resp_v(kz_json:set_value([<<"Snapshot">>,<<"active_calls">>,<<"complete">>],true,R))),
    meck:expect(acdc_stats_sup,stats_srv,fun()->{error,not_found} end),
    Err=response(detail_request(),self()),
    ?assertEqual(true,kz_json:get_value(<<"Include-Calls">>,Err)),
    ?assertEqual(<<"source_unavailable">>,kz_json:get_value(<<"Error-Code">>,Err)),
    ?assertEqual(undefined,kz_json:get_value(<<"Snapshot">>,Err))
end).

actual_empty_and_incomplete_detail_test() -> with_source(fun(T)->
    Empty=response(detail_request(),self()),
    ?assertEqual([],kz_json:get_value(<<"rows">>,detail(Empty))),
    ?assertEqual(true,kz_json:get_value(<<"complete">>,detail(Empty))),
    E=now_s()-20,
    ets:insert(T,[(waiting())#call_stat{id= <<(integer_to_binary(I))/binary,"::",?Q2/binary>>,
        call_id=integer_to_binary(I),queue_id=?Q2,entered_timestamp=E} || I<-lists:seq(1,10001)]),
    Partial=response(detail_request(),self()), A=detail(Partial),
    ?assertEqual([],kz_json:get_value(<<"rows">>,A)),
    ?assertEqual(0,kz_json:get_value(<<"observed_count">>,A)),
    ?assertEqual(false,kz_json:get_value(<<"truncated">>,A)),
    ?assertEqual(false,kz_json:get_value(<<"complete">>,A)),
    ?assertNot(kapi_acdc_dashboard:snapshot_resp_v(kz_json:set_value([<<"Snapshot">>,<<"active_calls">>,<<"complete">>],true,Partial)))
end).

invalid_requests_do_not_discover_or_read_or_publish_test() -> with_source(fun(T)->
    meck:expect(acdc_stats_sup,stats_srv,fun()->error(source_must_not_be_read) end),
    Bad=kz_json:set_value(<<"Queue-IDs">>,[<<"bad">>],request()),
    ?assertEqual({error,invalid_request},acdc_dashboard_snapshot:handle_req(Bad,[{server,self()}])),
    [?assertEqual({error,invalid_request},acdc_dashboard_snapshot:handle_req(Req,[{server,self()}])) ||
        Req<-[kz_json:set_value(<<"Queue-IDs">>,[?Q,?Q2],detail_request()),
              kz_json:set_value(<<"Include-Calls">>,<<"true">>,request())]],
    ?assertEqual({error,invalid_listener},acdc_dashboard_snapshot:handle_req(request(),[])),
    ?assertEqual(0,meck:num_calls(acdc_stats_sup,stats_srv,'_')),
    ?assertEqual(0,meck:num_calls(kz_amqp_util,targeted_publish,'_')),
    ?assertEqual(false,ets:info(T,safe_fixed))
end).

real_scan_limit_never_becomes_complete_zero_test() -> with_source(fun(T)->
    E=now_s()-20,
    ets:insert(T,[#call_stat{id= <<(integer_to_binary(I))/binary,"::",?Q2/binary>>,
        call_id=integer_to_binary(I),account_id=?A,queue_id=?Q2,
        status= <<"waiting">>,entered_timestamp=E} || I<-lists:seq(1,10001)]),
    R=response(request(),self()),S=kz_json:get_value(<<"Snapshot">>,R),
    ?assertEqual(false,kz_json:get_value([<<"source">>,<<"exhausted">>],S)),
    [Q]=kz_json:get_value(<<"queues">>,S),?assertEqual(null,kz_json:get_value(<<"metrics">>,Q)),
    ?assertEqual(undefined,kz_json:get_value([<<"source">>,<<"scan_keys">>],S)),
    Forged=kz_json:set_value([<<"Snapshot">>,<<"queues">>],
        [kz_json:set_value(<<"metrics">>,kz_json:get_value(<<"observed">>,Q),Q)],R),
    ?assertNot(kapi_acdc_dashboard:snapshot_resp_v(Forged)),
    ?assertEqual(false,ets:info(T,safe_fixed))
end).

explicit_source_failures_test() -> with_source(fun(T)->
    Parent=self(),
    meck:expect(acdc_stats_sup,stats_srv,fun()->{error,not_found} end),
    R1=response(request(),Parent), ?assertEqual(<<"source_unavailable">>,kz_json:get_value(<<"Error-Code">>,R1)),
    meck:expect(acdc_stats_sup,stats_srv,fun()->{ok,Parent} end),
    ets:insert(T,(waiting())#call_stat{handled_timestamp=now_s()}),
    R2=response(request(),Parent), ?assertEqual(<<"invalid_source">>,kz_json:get_value(<<"Error-Code">>,R2)),
    ?assertEqual(undefined,kz_json:get_value(<<"Snapshot">>,R2)),
    ets:insert(T,waiting()),
    meck:expect(acdc_stats_sup,stats_srv,0,meck:seq([{ok,Parent},{error,not_found}])),
    R3=response(request(),Parent), ?assertEqual(<<"source_changed">>,kz_json:get_value(<<"Error-Code">>,R3)),
    meck:expect(acdc_stats_sup,stats_srv,fun()->error(private_supervisor_detail) end),
    R4=response(request(),Parent), ?assertEqual(<<"collection_failed">>,kz_json:get_value(<<"Error-Code">>,R4)),
    ?assertEqual(nomatch,binary:match(iolist_to_binary(kz_json:encode(R4)),<<"private_supervisor_detail">>)),
    ?assertEqual(false,ets:info(T,safe_fixed))
end).

actual_owner_handoff_and_source_incarnation_test() -> with_source(fun(T)->
    Parent=self(), ets:insert(T,waiting()), Original=response(request(),Parent),
    Holder=spawn(fun()->
        receive {'ETS-TRANSFER',Owned,Parent,_}->
            Parent!{owner_ready,self()},
            receive return_table->ets:give_away(Owned,Parent,returned) end
        end
    end),
    try
        true=ets:give_away(T,Holder,test_handoff),
        receive {owner_ready,Holder}->ok after 1000->error(owner_not_ready) end,
        %% An ETS manager/heir or a different writer must not be mislabeled
        %% as this stats incarnation merely because the table name matches.
        Missing=response(request(),Parent),
        ?assertEqual(<<"source_unavailable">>,kz_json:get_value(<<"Error-Code">>,Missing)),
        meck:expect(acdc_stats_sup,stats_srv,fun()->{ok,Holder} end),
        New=response(request(),Holder),
        ?assertEqual(kz_json:get_value(<<"Source-ID">>,Original),kz_json:get_value(<<"Source-ID">>,New)),
        ?assertNotEqual(kz_json:get_value(<<"Source-Incarnation">>,Original),kz_json:get_value(<<"Source-Incarnation">>,New)),
        ?assertEqual(<<"ok">>,kz_json:get_value(<<"Status">>,New))
    after
        Holder!return_table,
        receive {'ETS-TRANSFER',_,Holder,returned}->ok after 1000->exit(Holder,kill) end
    end
end).

topic_binding_and_publication_test() ->
    meck:new(kz_amqp_util,[non_strict,no_link]),
    try
        Key= <<"acdc.dashboard.snapshot.",?A/binary>>,
        meck:expect(kz_amqp_util,bind_q_to_callmgr,fun(<<"listener">>,<<"acdc.dashboard.snapshot.*">>)->ok end),
        meck:expect(kz_amqp_util,unbind_q_from_callmgr,fun(<<"listener">>,<<"acdc.dashboard.snapshot.*">>)->ok end),
        meck:expect(kz_amqp_util,callmgr_publish,fun(Payload,<<"application/json">>,Actual)->
            ?assertEqual(Key,Actual),?assert(kapi_acdc_dashboard:snapshot_req_v(kz_json:decode(iolist_to_binary(Payload)))),ok end),
        ?assertEqual(Key,kapi_acdc_dashboard:routing_key(?A)),
        ?assertEqual(ok,kapi_acdc_dashboard:bind_q(<<"listener">>,[])),
        ?assertEqual(ok,kapi_acdc_dashboard:unbind_q(<<"listener">>,[])),
        ?assertMatch({error,_},kapi_acdc_dashboard:bind_q(<<"listener">>,[{account_id,<<"#">>}])),
        ?assertEqual(ok,kapi_acdc_dashboard:publish_snapshot_req(request())),
        ?assertMatch({error,_},kapi_acdc_dashboard:publish_snapshot_req(kz_json:set_value(<<"Account-ID">>,<<"#">>,request()))),
        ?assertEqual(1,meck:num_calls(kz_amqp_util,callmgr_publish,'_'))
    after meck:unload(kz_amqp_util) end.

native_federation_binding_and_reply_routing_test_() ->
    %% Native gen_listener/kz_amqp_util passthrough mock compilation can exceed
    %% EUnit's default5s under the guard's50%CPU limit. Protocol receive and
    %% production deadlines are unchanged; only this fixture setup allowance.
    {timeout,15,fun native_federation_binding_and_reply_routing/0}.
native_federation_binding_and_reply_routing() ->
    Parent=self(),
    meck:new(gen_listener,[non_strict,no_link]),
    meck:new(amqp,[non_strict,no_link]),
    meck:new(kz_amqp_util,[passthrough,no_link]),
    try
        meck:expect(amqp,debug,fun(_,_)->ok end),
        meck:expect(gen_listener,start_link,fun(acdc_stats,Params,[])->
            Bindings=props:get_value(bindings,Params),
            ?assertEqual([federate],props:get_value(acdc_dashboard,Bindings)),
            ?assertEqual([],props:get_value(acdc_stats,Bindings)),
            ?assertEqual([],props:get_value(self,Bindings)),
            Responders=props:get_value(responders,Params),
            ?assert(lists:member({{acdc_dashboard_snapshot,handle_req},[{<<"acdc_dashboard">>,<<"snapshot_req">>}]},Responders)),
            {ok,Parent}
        end),
        ?assertEqual({ok,Parent},acdc_stats:start_link()),
        meck:expect(kz_amqp_util,bind_q_to_callmgr,fun(<<"listener">>,<<"acdc.dashboard.snapshot.*">>)->ok end),
        meck:expect(kz_amqp_util,unbind_q_from_callmgr,fun(<<"listener">>,<<"acdc.dashboard.snapshot.*">>)->ok end),
        ?assertEqual(ok,kapi_acdc_dashboard:bind_q(<<"listener">>,[federate])),
        ?assertEqual(ok,kapi_acdc_dashboard:bind_q(<<"listener">>,props:delete(federate,[federate]))),
        ?assertEqual(ok,kapi_acdc_dashboard:unbind_q(<<"listener">>,[federate])),
        ?assertEqual({error,invalid_binding},kapi_acdc_dashboard:bind_q(<<"listener">>,[federate,{route,<<"#">>}])),
        meck:expect(gen_listener,federated_event,fun(Parent0,F,OriginalProps)->
            ?assertEqual(Parent,Parent0),?assertEqual([{deliver,fixture_delivery}],OriginalProps),
            Parent!{forwarded_dashboard,F},ok end),
        Reply=binary:copy(<<"q">>,255),
        Req=kz_json:set_value(<<"Server-ID">>,Reply,request()),
        %% Actual exported native forwarding callback; only its private state
        %% record is arranged here. No broker/connection/forwarder is started.
        NativeState={state,{Parent,make_ref()},<<"amqp://offline-fixture">>,
                     list_to_binary(pid_to_list(Parent)),<<"remote-zone">>},
        ?assertEqual(ignore,listener_federator:handle_event(Req,[{deliver,fixture_delivery}],NativeState)),
        receive {forwarded_dashboard,Federated}->
            Routed=kz_json:get_value(<<"Server-ID">>,Federated),
            ?assert(byte_size(Routed)>255),?assert(kapi_acdc_dashboard:snapshot_req_v(Federated)),
            %% Native parser recovers the originating broker's consumer and
            %% the original queue, rather than publishing locally by mistake.
            ?assertEqual({Parent,Reply},kz_amqp_util:split_routing_key(Routed)),
            ErrorProps=[{<<"Status">>,<<"error">>},{<<"Error-Code">>,<<"source_unavailable">>},
                {<<"Source-ID">>,binary:copy(<<"a">>,64)},{<<"Source-Incarnation">>,binary:copy(<<"b">>,64)},
                {<<"Event-Category">>,<<"acdc_dashboard">>},{<<"Event-Name">>,<<"snapshot_resp">>},
                {<<"App-Name">>,<<"test">>},{<<"App-Version">>,<<"1">>}|
                [{K,kz_json:get_value(K,Federated)} || K<-[<<"Account-ID">>,<<"Queue-IDs">>,<<"From">>,<<"To">>,<<"Msg-ID">>]]],
            meck:expect(kz_amqp_util,targeted_publish,fun(Target,Payload,<<"application/json">>)->
                ?assertEqual(Routed,Target),?assert(kapi_acdc_dashboard:snapshot_resp_v(kz_json:decode(iolist_to_binary(Payload)))),ok end),
            ?assertEqual(ok,kapi_acdc_dashboard:publish_snapshot_resp(Routed,ErrorProps)),
            [?assertNot(kapi_acdc_dashboard:snapshot_req_v(kz_json:set_value(<<"Server-ID">>,Bad,Federated))) ||
                Bad<-[<<"consumer://bad/reply">>,<<"consumer://<0.1.0>/">>,
                      <<"consumer://<0.1.0>/",Reply/binary,"x">>,<<"consumer://<0.1.0>/nested/reply">>]]
        after 1000->error(federation_not_forwarded) end
    after meck:unload(gen_listener),meck:unload(amqp),meck:unload(kz_amqp_util) end.

agent_collection_and_encoding_failure_response_test() -> with_source(fun(T)->
    ets:insert(T,waiting()),
    Req=kz_json:set_value(<<"Agent-IDs">>,[],detail_request()),
    meck:new(acdc_dashboard_agents,[non_strict,no_link]),
    try
        %% Both the provider exception and the real encoder's missing-field
        %% exception must become a bounded error response, not a responder exit.
        lists:foreach(fun(Result)->
            meck:expect(acdc_dashboard_agents,collect,fun(?A,?Q,[])->
                case Result of fail->error(private_agent_failure); _->Result end
            end),
            R=response(Req,self()),assert_agent_error(R,Req,<<"collection_failed">>),
            ?assertEqual(nomatch,binary:match(iolist_to_binary(kz_json:encode(R)),<<"private_agent_failure">>)),
            ?assertEqual(false,ets:info(T,safe_fixed))
        end,[fail,{ok,#{}}])
    after meck:unload(acdc_dashboard_agents) end
end).

agent_collection_stats_incarnation_change_test() -> with_source(fun(T)->
    Parent=self(),ets:insert(T,waiting()),
    Req=kz_json:set_value(<<"Agent-IDs">>,[],detail_request()),
    Other=spawn(fun()->receive stop->ok end end),
    meck:new(acdc_dashboard_agents,[non_strict,no_link]),
    try
        meck:expect(acdc_dashboard_agents,collect,fun(?A,?Q,[])->
            %% Source was valid for the call-table pass, but the stats child
            %% incarnation changed during the subsequent agent observation.
            meck:expect(acdc_stats_sup,stats_srv,fun()->{ok,Other} end),
            {ok,empty_agent_observation()}
        end),
        R=response(Req,Parent),assert_agent_error(R,Req,<<"source_changed">>),
        ?assertEqual(Parent,ets:info(T,owner)),?assertEqual(false,ets:info(T,safe_fixed))
    after
        meck:unload(acdc_dashboard_agents),
        Mon=monitor(process,Other),Other!stop,
        receive {'DOWN',Mon,process,Other,_}->ok after 1000->exit(Other,kill) end
    end
end).

agent_collection_logical_table_replacement_test() -> with_source(fun(T)->
    ets:insert(T,waiting()),OldTid=ets:whereis(T),
    Req=kz_json:set_value(<<"Agent-IDs">>,[],detail_request()),
    meck:new(acdc_dashboard_agents,[non_strict,no_link]),
    try
        meck:expect(acdc_dashboard_agents,collect,fun(?A,?Q,[])->
            %% Keeping the old tid alive with the same owner defeats a check
            %% of owner alone. The logical source must still resolve that tid.
            acdc_stats_call_before_agents=ets:rename(T,acdc_stats_call_before_agents),
            acdc_stats_call=ets:new(acdc_stats_call,[named_table,protected,{keypos,#call_stat.id}]),
            {ok,empty_agent_observation()}
        end),
        R=response(Req,self()),assert_agent_error(R,Req,<<"source_changed">>),
        ?assertEqual(self(),ets:info(OldTid,owner)),
        ?assertNotEqual(OldTid,ets:whereis(acdc_stats_call)),
        ?assertEqual(false,ets:info(OldTid,safe_fixed))
    after
        meck:unload(acdc_dashboard_agents),
        case ets:whereis(acdc_stats_call_before_agents) of
            undefined->ok; Renamed->ets:delete(Renamed)
        end
    end
end).

empty_agent_observation() ->
    #{account_id=>?A,queue_id=>?Q,observation_started=>now_s(),observation_finished=>now_s(),rows=>[]}.
assert_agent_error(R,Req,Code) ->
    ?assertEqual(<<"error">>,kz_json:get_value(<<"Status">>,R)),
    ?assertEqual(Code,kz_json:get_value(<<"Error-Code">>,R)),
    ?assertEqual(undefined,kz_json:get_value(<<"Snapshot">>,R)),
    [?assertEqual(kz_json:get_value(K,Req),kz_json:get_value(K,R)) ||
        K<-[<<"Account-ID">>,<<"Queue-IDs">>,<<"Agent-IDs">>,<<"Include-Calls">>,<<"Msg-ID">>,<<"From">>,<<"To">>]].
