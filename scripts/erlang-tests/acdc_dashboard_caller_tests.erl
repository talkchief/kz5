-module(acdc_dashboard_caller_tests).
-include_lib("eunit/include/eunit.hrl").
-include("acdc_stats.hrl").
-define(A, <<"11111111111111111111111111111111">>).
-define(Q, <<"22222222222222222222222222222222">>).
-define(NAME, <<"Synthetic caller">>).
-define(NUMBER, <<"+15550000100">>).

clear_privacy() -> kz_json:from_list([{<<"Caller-Privacy-Hide-Name">>,false},
                                     {<<"Caller-Privacy-Hide-Number">>,false}]).
marker() -> acdc_dashboard_caller:from_privacy(clear_privacy(),?NAME,?NUMBER).
event(Marker) ->
    kz_json:from_list(props:filter_undefined([{<<"Account-ID">>,?A},{<<"Queue-ID">>,?Q},
        {<<"Call-ID">>,<<"test-call">>},{<<"Caller-ID-Name">>,<<"LEGACY-RAW-NAME">>},
        {<<"Caller-ID-Number">>,<<"LEGACY-RAW-NUMBER">>},{<<"Entered-Timestamp">>,63800000000},
        {<<"Dashboard-Caller-ID">>,Marker},{<<"Event-Category">>,<<"acdc_call_stat">>},
        {<<"Event-Name">>,<<"waiting">>},{<<"App-Name">>,<<"test">>},{<<"App-Version">>,<<"1">>},
        {<<"Msg-ID">>,<<"test-request">>}])).

independent_native_privacy_flags_test() ->
    ?assertEqual({1,?NAME,?NUMBER,<<"available">>,<<"available">>},acdc_dashboard_caller:normalize(marker())),
    [begin
         P=kz_json:set_values(Flags,clear_privacy()),
         Value=acdc_dashboard_caller:from_privacy(P,?NAME,?NUMBER),
         ?assert(acdc_dashboard_caller:valid(Value)),
         ?assertEqual(Expected,acdc_dashboard_caller:normalize(Value))
     end || {Flags,Expected} <- [
        {[{<<"Privacy-Hide-Name">>,true}],{1,undefined,?NUMBER,<<"withheld">>,<<"available">>}},
        {[{<<"Privacy-Hide-Number">>,true}],{1,?NAME,undefined,<<"available">>,<<"withheld">>}},
        {[{<<"privacy_mode">>,<<"full">>}],{1,undefined,undefined,<<"withheld">>,<<"withheld">>}},
        {[{<<"Custom-Channel-Vars">>,kz_json:from_list([{<<"Privacy-Hide-Name">>,true},
             {<<"Privacy-Hide-Number">>,true}])}],{1,undefined,undefined,<<"withheld">>,<<"withheld">>}}
     ]].

conflicting_and_unknown_privacy_representations_test() ->
    P=kz_json:set_values([{<<"Privacy-Hide-Name">>,false},
         {<<"Custom-Channel-Vars">>,kz_json:from_list([{<<"Caller-Privacy-Hide-Name">>,true}])}],clear_privacy()),
    ?assertEqual({1,undefined,?NUMBER,<<"withheld">>,<<"available">>},
        acdc_dashboard_caller:normalize(acdc_dashboard_caller:from_privacy(P,?NAME,?NUMBER))),
    [begin
        Bad=kz_json:set_value(<<"Privacy-Hide-Number">>,V,clear_privacy(),#{keep_null=>true}),
        ?assertEqual({1,?NAME,undefined,<<"available">>,<<"unavailable">>},
            acdc_dashboard_caller:normalize(acdc_dashboard_caller:from_privacy(Bad,?NAME,?NUMBER)))
     end || V<-[null,0,1,<<"unknown">>,[],kz_json:new()]],
    ?assertEqual({1,undefined,undefined,<<"unavailable">>,<<"unavailable">>},
        acdc_dashboard_caller:normalize(acdc_dashboard_caller:from_privacy(kz_json:new(),?NAME,?NUMBER))).

real_initialized_call_serialization_preserves_privacy_test() ->
    Modules=[kapps_config,kapps_account_config],
    [meck:new(M,[non_strict,no_link]) || M<-Modules],
    try
        meck:expect(kapps_config,get_ne_binary,fun(_,_,Default) -> Default end),
        meck:expect(kapps_config,get_binary,fun(_,_,Default) -> Default end),
        meck:expect(kapps_account_config,get_global,fun(_,_,_,Default) -> Default end),
        J=kz_json:from_list([{<<"Call-ID">>,<<"test-call">>},{<<"Account-ID">>,?A},
            {<<"Caller-ID-Name">>,?NAME},{<<"Caller-ID-Number">>,?NUMBER},
            {<<"Custom-Channel-Vars">>,clear_privacy()}]),
        Call=kapps_call:from_json(J),
        ?assertEqual(false,kapps_call:custom_channel_var(<<"Caller-Privacy-Hide-Name">>,Call)),
        ?assertEqual({1,?NAME,?NUMBER,<<"available">>,<<"available">>},
            acdc_dashboard_caller:normalize(acdc_dashboard_caller:from_call(Call,J,?NAME,?NUMBER))),
        Hidden=kz_json:set_value(<<"Caller-Privacy-Hide-Name">>,true,J),
        HiddenCall=kapps_call:from_json(Hidden),
        %% Actual kapps_call serialization drops this top-level flag; the
        %% manager must pass its original Call JSON as well as the record.
        ?assertEqual(undefined,kz_json:get_value(<<"Caller-Privacy-Hide-Name">>,kapps_call:to_json(HiddenCall))),
        ?assertEqual({1,undefined,?NUMBER,<<"withheld">>,<<"available">>},
            acdc_dashboard_caller:normalize(acdc_dashboard_caller:from_call(HiddenCall,Hidden,?NAME,?NUMBER))),
        Options=kz_json:set_value([<<"privacy">>,<<"hide_number">>],true,J),
        ?assertEqual({1,?NAME,undefined,<<"available">>,<<"withheld">>},
            acdc_dashboard_caller:normalize(acdc_dashboard_caller:from_call(Call,Options,?NAME,?NUMBER))),
        ?assertEqual({1,undefined,undefined,<<"unavailable">>,<<"unavailable">>},
            acdc_dashboard_caller:normalize(acdc_dashboard_caller:from_call(kapps_call:new(),J,?NAME,?NUMBER)))
    after [meck:unload(M) || M<-Modules] end.

privacy_failure_and_missing_values_never_use_raw_fallback_test() ->
    ?assertEqual({1,undefined,undefined,<<"unavailable">>,<<"unavailable">>},
        acdc_dashboard_caller:normalize(acdc_dashboard_caller:from_privacy(not_json,?NAME,?NUMBER))),
    ?assertEqual({1,undefined,undefined,<<"unavailable">>,<<"unavailable">>},
        acdc_dashboard_caller:normalize(acdc_dashboard_caller:from_call(not_a_call,?NAME,?NUMBER))),
    ?assertEqual(undefined,acdc_dashboard_caller:from_event(event(undefined))),
    ?assertEqual({1,undefined,undefined,<<"unavailable">>,<<"unavailable">>},
        acdc_dashboard_caller:normalize(acdc_dashboard_caller:from_privacy(kz_json:new(),undefined,undefined))).

utf8_control_and_size_bounds_test() ->
    Hebrew=binary:copy(<<215,144>>,128), Number=binary:copy(<<"1">>,64),
    ?assertEqual({1,Hebrew,Number,<<"available">>,<<"available">>},acdc_dashboard_caller:normalize(
        acdc_dashboard_caller:from_privacy(clear_privacy(),Hebrew,Number))),
    BadNames=[<<>>,<<" ">>,<<"\n">>,<<"x",0>>,<<127>>,<<194,128>>,<<255>>,<<215>>,
              <<"x",226,128,174>>,<<"x",226,129,166>>,binary:copy(<<"x">>,257),[?NAME],42,kz_json:new()],
    [begin
        ?assertEqual({1,undefined,?NUMBER,<<"unavailable">>,<<"available">>},
            acdc_dashboard_caller:normalize(acdc_dashboard_caller:from_privacy(clear_privacy(),Bad,?NUMBER)))
     end || Bad<-BadNames],
    ?assertEqual({1,?NAME,undefined,<<"available">>,<<"unavailable">>},acdc_dashboard_caller:normalize(
        acdc_dashboard_caller:from_privacy(clear_privacy(),?NAME,binary:copy(<<"1">>,65)))),
    %% This is text, not HTML: downstream must escape, never execute or strip it.
    Html= <<"<img src=x onerror=alert(1)>">>,
    ?assertEqual(Html,kz_json:get_value(<<"name">>,acdc_dashboard_caller:from_privacy(clear_privacy(),Html,?NUMBER))).

closed_marker_and_crossfield_contract_test() ->
    Good=marker(), {Props}=Good,
    Bad=[{[{<<"version">>,1}|Props]},kz_json:set_value(<<"extra">>,<<"PRIVATE-SENTINEL">>,Good),
         kz_json:set_value(<<"version">>,2,Good),kz_json:set_value(<<"name_status">>,<<"withheld">>,Good),
         kz_json:set_value(<<"number_status">>,<<"unknown">>,Good),kz_json:new(),[],null,
         {1,?NAME,?NUMBER,<<"available">>,<<"available">>}],
    [?assertNot(acdc_dashboard_caller:valid(Value)) || Value<-Bad],
    ?assertEqual(undefined,acdc_dashboard_caller:normalize({1,?NAME,undefined,<<"withheld">>,<<"unavailable">>})),
    ?assertEqual(undefined,acdc_dashboard_caller:normalize({1,null,undefined,<<"withheld">>,<<"unavailable">>})),
    ?assertEqual(acdc_dashboard_caller:normalize(Good),
        acdc_dashboard_caller:normalize(acdc_dashboard_caller:normalize(Good))).

native_waiting_wire_roundtrip_and_legacy_test() ->
    [?assert(kapi_acdc_stats:call_waiting_v(event(M))) || M<-[undefined,marker()]],
    {ok,Wire}=kapi_acdc_stats:call_waiting(event(marker())),
    Decoded=kz_json:decode(iolist_to_binary(Wire)),
    ?assertEqual(acdc_dashboard_caller:normalize(marker()),acdc_dashboard_caller:from_event(Decoded)),
    {ok,Legacy}=kapi_acdc_stats:call_waiting(event(undefined)),
    ?assertEqual(undefined,acdc_dashboard_caller:from_event(kz_json:decode(iolist_to_binary(Legacy)))),
    ?assert(kapi_acdc_stats:call_waiting_v(event(kz_json:new()))),
    {ok,Malformed}=kapi_acdc_stats:call_waiting(event(kz_json:new())),
    ?assertEqual(undefined,acdc_dashboard_caller:from_event(kz_json:decode(iolist_to_binary(Malformed)))),
    ?assertNot(kapi_acdc_stats:call_waiting_v(kz_json:delete_key(<<"Call-ID">>,event(marker())))),
    ?assertEqual(undefined,acdc_dashboard_caller:from_event(event(kz_json:new()))).

%% Meck compiles the production listener mocks under the half-CPU validation
%% quota. This bound includes fixture setup; message acceptance stays at1s.
stats_storage_and_legacy_update_revoke_test_() ->
    {timeout, 20, fun stats_storage_and_legacy_update_revoke/0}.
stats_storage_and_legacy_update_revoke() ->
    with_stats_mocks(fun() ->
        Table=ets:new(acdc_stats:call_table_id(),[named_table,set,public,{keypos,#call_stat.id}]),
        try
            acdc_stats:handle_call_stat(event(marker()),[{server,self()}]),
            Created=receive {listener,{create_call,Stat}} -> Stat after 1000 -> error(no_create) end,
            ?assertEqual(acdc_dashboard_caller:normalize(marker()),Created#call_stat.dashboard_caller_id),
            ?assertEqual(<<"LEGACY-RAW-NAME">>,Created#call_stat.caller_id_name),
            {noreply,test_state}=acdc_stats:handle_cast({create_call,Created},test_state),
            acdc_stats:handle_call_stat(event(undefined),[{server,self()}]),
            Updates=receive {listener,{update_call,_,U}} -> U after 1000 -> error(no_update) end,
            ?assertEqual({#call_stat.dashboard_caller_id,undefined},lists:keyfind(#call_stat.dashboard_caller_id,1,Updates)),
            {noreply,test_state}=acdc_stats:handle_cast({update_call,Created#call_stat.id,Updates},test_state),
            [After]=ets:lookup(Table,Created#call_stat.id),
            ?assertEqual(undefined,After#call_stat.dashboard_caller_id),
            ?assertEqual(Created#call_stat.caller_id_number,After#call_stat.caller_id_number),
            %% Malformed optional display metadata must not drop occupancy or
            %% preserve an earlier trusted identity.
            true=ets:insert(Table,Created),
            acdc_stats:handle_call_stat(event(kz_json:new()),[{server,self()}]),
            BadUpdates=receive {listener,{update_call,_,BU}} -> BU after 1000 -> error(no_malformed_update) end,
            {noreply,test_state}=acdc_stats:handle_cast({update_call,Created#call_stat.id,BadUpdates},test_state),
            [BadAfter]=ets:lookup(Table,Created#call_stat.id),
            ?assertEqual(undefined,BadAfter#call_stat.dashboard_caller_id),
            ?assertEqual(<<"waiting">>,BadAfter#call_stat.status),
            ?assertEqual(Created#call_stat.entered_timestamp,BadAfter#call_stat.entered_timestamp)
        after ets:delete(Table) end
    end).

public_publish_legacy_arity_and_marked_arity_test_() ->
    {timeout, 20, fun public_publish_legacy_arity_and_marked_arity/0}.
public_publish_legacy_arity_and_marked_arity() ->
    with_stats_mocks(fun() ->
        ok=acdc_stats:call_waiting(?A,?Q,<<"test-call">>,?NAME,?NUMBER,undefined),
        Legacy=receive {publish,P1} -> P1 after 1000 -> error(no_publish) end,
        ?assertEqual(undefined,props:get_value(<<"Dashboard-Caller-ID">>,Legacy)),
        ok=acdc_stats:call_waiting(?A,?Q,<<"test-call">>,?NAME,?NUMBER,undefined,marker()),
        Marked=receive {publish,P2} -> P2 after 1000 -> error(no_publish) end,
        ?assertEqual(marker(),props:get_value(<<"Dashboard-Caller-ID">>,Marked)),
        ok=acdc_stats:call_waiting(?A,?Q,<<"test-call">>,?NAME,?NUMBER,undefined,kz_json:new()),
        Malformed=receive {publish,P3} -> P3 after 1000 -> error(no_publish) end,
        ?assertEqual(undefined,props:get_value(<<"Dashboard-Caller-ID">>,Malformed)),
        ?assertEqual(?NAME,props:get_value(<<"Caller-ID-Name">>,Malformed))
    end).

exact_legacy_layout_conversion_is_pure_test() ->
    Current=#call_stat{id= <<"test-call::",?Q/binary>>,call_id= <<"test-call">>,account_id=?A,queue_id=?Q,
        caller_id_name= <<"RAW-LEGACY-NAME">>,caller_id_number= <<"RAW-LEGACY-NUMBER">>,status= <<"waiting">>,
        is_archived=true},
    ?assertEqual(19,tuple_size(Current)),
    Legacy=list_to_tuple(lists:sublist(tuple_to_list(Current),18)),
    ?assertEqual({ok,Current},acdc_dashboard_caller:upgrade_legacy(Legacy)),
    ?assertEqual({ok,Current},acdc_dashboard_caller:upgrade_legacy(Current)),
    [?assertEqual({error,unsupported_call_stat_layout},acdc_dashboard_caller:upgrade_legacy(Bad)) ||
        Bad<-[{},setelement(1,Legacy,other),erlang:append_element(Current,unexpected),undefined]],
    %% Conversion does not promote legacy raw caller values to trusted display.
    {ok,Upgraded}=acdc_dashboard_caller:upgrade_legacy(Legacy),
    ?assertEqual(undefined,Upgraded#call_stat.dashboard_caller_id).

with_stats_mocks(Fun) ->
    Modules=[gen_listener,kz_amqp_worker,kz_edr,acdc_dashboard_events],
    [meck:new(M,[non_strict,no_link]) || M<-Modules],
    try
        meck:expect(gen_listener,cast,fun(Pid,Message) -> Pid ! {listener,Message},ok end),
        Parent=self(),
        meck:expect(kz_amqp_worker,cast,fun(Props,_) -> Parent ! {publish,Props},ok end),
        meck:expect(kz_edr,event,fun(_,_,_,_,_,_) -> ok end),
        meck:expect(acdc_dashboard_events,changed,fun(_,_) -> ok end),
        Fun()
    after [meck:unload(M) || M<-Modules] end.
