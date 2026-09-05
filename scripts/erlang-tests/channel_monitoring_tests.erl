-module(channel_monitoring_tests).
-include_lib("eunit/include/eunit.hrl").
-define(ACCOUNT, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(DEVICE, <<"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb">>).
-define(REQUEST, <<"cccccccccccccccccccccccccccccccc">>).
-define(SUPERVISOR, <<"dddddddddddddddddddddddddddddddd">>).
-define(TARGET, <<"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee">>).
-define(NODE, 'fs@test.invalid').

j(P) -> kz_json:from_list(P).
data(Action) -> j([{<<"action">>, Action}, {<<"device_id">>, ?DEVICE}]).
channel(Account, Node) -> j([{<<"Account-ID">>, Account}, {<<"Media-Node">>, Node}, {<<"Call-ID">>, ?TARGET}]).
reply(Account, Node) -> j([{<<"Channels">>, j([{?TARGET, channel(Account, Node)}])}]).
device() -> j([{<<"_id">>, ?DEVICE}, {<<"pvt_type">>, <<"device">>}, {<<"pvt_account_id">>, ?ACCOUNT}
             ,{<<"device_type">>, <<"softphone">>}, {<<"sip">>, j([{<<"username">>, <<"supervisor">>}])}]).
request(Action) ->
    {ok, Endpoint} = cb_channel_monitor:endpoint(?ACCOUNT, <<"test.invalid">>, device()),
    j(cb_channel_monitor:request(?ACCOUNT, data(Action), channel(?ACCOUNT, atom_to_binary(?NODE)), Endpoint, ?REQUEST, ?SUPERVISOR)).
props(Id, Account) -> [{<<"Unique-ID">>, Id}, {<<"variable_ecallmgr_Account-ID">>, Account}, {<<"Channel-State">>, <<"CS_EXECUTE">>}].

all_modes_bounded_contract_test() ->
    [?assert(cb_channel_monitor:valid_data(data(A), ?TARGET)) || A <- [<<"eavesdrop">>, <<"whisper">>, <<"barge">>, <<"join">>]],
    [?assertNot(cb_channel_monitor:valid_data(kz_json:set_value(<<"timeout">>, N, data(<<"whisper">>)), ?TARGET)) || N <- [0, 4, 61, <<"20">>, 5.1]],
    [?assertNot(cb_channel_monitor:valid_data(kz_json:set_value(K, <<"unsafe">>, data(<<"whisper">>)), ?TARGET)) || K <- [<<"node">>, <<"endpoint">>, <<"route">>, <<"call_id">>, <<"mode">>, <<"request_id">>]],
    ?assertNot(cb_channel_monitor:valid_data(data(<<"whisper">>), <<"uuid,bridge:sofia/foo">>)),
    ?assertNot(cb_channel_monitor:valid_data(data(<<"takeover">>), ?TARGET)).

stop_requires_exact_correlation_test() ->
    ?assert(cb_channel_monitor:valid_data(j([{<<"action">>, <<"stop_monitoring">>}, {<<"request_id">>, ?REQUEST}]), ?SUPERVISOR)),
    ?assertNot(cb_channel_monitor:valid_data(j([{<<"action">>, <<"stop_monitoring">>}]), ?SUPERVISOR)).

device_ownership_and_routing_test() ->
    {ok, E} = cb_channel_monitor:endpoint(?ACCOUNT, <<"test.invalid">>, device()),
    ?assertEqual(<<"username">>, kz_json:get_value(<<"Invite-Format">>, E)),
    ?assertEqual(undefined, kz_json:get_value(<<"Route">>, E)),
    D = kz_json:set_values([{<<"call_forward">>, j([{<<"enabled">>, true}, {<<"number">>, <<"+19005550100">>}])}
                           ,{[<<"sip">>, <<"route">>], <<"sofia/unsafe">>}], device()),
    ?assertEqual({ok, E}, cb_channel_monitor:endpoint(?ACCOUNT, <<"test.invalid">>, D)),
    [?assertMatch({error, _}, cb_channel_monitor:endpoint(?ACCOUNT, <<"test.invalid">>, kz_json:set_value(K, V, device())))
     || {K,V} <- [{<<"pvt_account_id">>, <<"other">>}, {<<"enabled">>, false}, {<<"device_type">>, <<"mobile">>}
                 ,{[<<"sip">>, <<"realm">>], <<"other.invalid">>}, {[<<"sip">>, <<"username">>], <<"foo@evil.invalid">>}]].

multi_node_and_account_conflict_fail_closed_test() ->
    A = reply(?ACCOUNT, <<"fs@one">>),
    ?assertMatch({ok, _}, cb_channel_monitor:choose_channel(?ACCOUNT, ?TARGET, [A,A])),
    ?assertEqual({error, conflict}, cb_channel_monitor:choose_channel(?ACCOUNT, ?TARGET, [A,reply(?ACCOUNT, <<"fs@two">>)])),
    ?assertEqual({error, conflict}, cb_channel_monitor:choose_channel(?ACCOUNT, ?TARGET, [A,reply(<<"other">>, <<"fs@one">>)])),
    ?assertEqual({error, not_found}, cb_channel_monitor:choose_channel(?ACCOUNT, ?TARGET, [reply(<<"other">>, <<"fs@one">>)])),
    ?assertEqual({error, not_found}, cb_channel_monitor:choose_channel(?ACCOUNT, ?TARGET, [])).

collection_deduplicates_workers_and_correlates_test() ->
    Base = [{<<"Msg-ID">>, ?REQUEST}, {<<"Channels">>, j([])} | kz_api:default_headers(<<"ecallmgr">>, <<"5">>)],
    A = kz_json:set_values([{<<"Node">>, <<"ecallmgr@one">>}, {<<"Event-Category">>, <<"channel">>}, {<<"Event-Name">>, <<"query_channels_resp">>}], j(Base)),
    B = kz_json:set_value(<<"Node">>, <<"ecallmgr@two">>, A),
    ?assertNot(cb_channel_monitor:complete([A,A], 2, ?REQUEST)),
    ?assert(cb_channel_monitor:complete([A,B], 2, ?REQUEST)),
    ?assertNot(cb_channel_monitor:complete([A,B], 0, ?REQUEST)),
    ?assertNot(cb_channel_monitor:complete([A,B], 2, <<"other">>)).

fixed_modes_prevent_whisper_escalation_test() ->
    Whisper = ecallmgr_call_monitor:action(request(<<"whisper">>)),
    ?assertNotEqual(nomatch, binary:match(Whisper, <<"eavesdrop_enable_dtmf=false">>)),
    ?assertNotEqual(nomatch, binary:match(Whisper, <<"eavesdrop_whisper_aleg=false">>)),
    ?assertNotEqual(nomatch, binary:match(Whisper, <<"eavesdrop_whisper_bleg=true">>)),
    ?assertEqual(nomatch, binary:match(Whisper, <<"queue_dtmf">>)),
    ?assertEqual(ecallmgr_call_monitor:action(request(<<"barge">>)), ecallmgr_call_monitor:action(request(<<"join">>))),
    ?assertNotEqual(nomatch, binary:match(ecallmgr_call_monitor:action(request(<<"eavesdrop">>)), <<"eavesdrop_whisper_bleg=false">>)).

consumer_request_cannot_change_node_or_route_test() ->
    J = request(<<"whisper">>),
    ?assert(ecallmgr_call_monitor:valid_request(?NODE, J)),
    ?assertNot(ecallmgr_call_monitor:valid_request('fs@other', J)),
    [?assertNot(ecallmgr_call_monitor:valid_request(?NODE, kz_json:set_value(K,V,J)))
     || {K,V} <- [{<<"Eavesdrop-Group-ID">>, <<"all">>}, {<<"Existing-Call-ID">>, ?TARGET}
                 ,{<<"Originate-Immediate">>, true}, {<<"Msg-ID">>, <<"other">>}
                 ,{<<"Endpoints">>, [j([{<<"Invite-Format">>, <<"route">>}, {<<"Route">>, <<"loopback/911">>}])]}]].

live_owner_and_exact_supervisor_guard_test() ->
    J = request(<<"whisper">>),
    ?assert(ecallmgr_call_monitor:matches_channel(J, target, props(?TARGET, ?ACCOUNT))),
    ?assertNot(ecallmgr_call_monitor:matches_channel(J, target, props(?TARGET, <<"other">>))),
    ?assertNot(ecallmgr_call_monitor:matches_channel(J, target, props(?SUPERVISOR, ?ACCOUNT))),
    ?assertNot(ecallmgr_call_monitor:matches_channel(J, supervisor, props(?TARGET, ?ACCOUNT))),
    Stop = kz_json:set_values([{<<"Monitor-Operation">>, <<"stop">>}, {<<"Eavesdrop-Call-ID">>, ?SUPERVISOR}], J),
    P = props(?SUPERVISOR, ?ACCOUNT) ++ [{<<"variable_ecallmgr_Monitor-Request-ID">>, ?REQUEST}
                                      ,{<<"variable_ecallmgr_Monitor-Target-ID">>, ?TARGET}
                                      ,{<<"variable_ecallmgr_Monitor-Mode">>, <<"whisper">>}],
    ?assert(ecallmgr_call_monitor:valid_request(?NODE, Stop)),
    ?assert(ecallmgr_call_monitor:matches_channel(Stop, supervisor, P)),
    ?assertNot(ecallmgr_call_monitor:matches_channel(kz_json:set_value(<<"Monitor-Request-ID">>, ?DEVICE, Stop), supervisor, P)).

fresh_fs_recheck_denies_stale_cache_and_unknown_test() ->
    meck:new(freeswitch, [non_strict, no_link]),
    try
        meck:expect(freeswitch, api, fun(?NODE, uuid_dump, ?TARGET) ->
            {ok, <<"Unique-ID: ", ?TARGET/binary, "\nvariable_ecallmgr_Account-ID: ", ?ACCOUNT/binary, "\nChannel-State: CS_EXECUTE\nOptional-Header: \nOther: sip:user@host\n">>}
        end),
        ?assert(ecallmgr_call_monitor:guard(?NODE, request(<<"whisper">>))),
        meck:expect(freeswitch, api, fun(_, _, _) -> {error, timeout} end),
        ?assertNot(ecallmgr_call_monitor:guard(?NODE, request(<<"whisper">>))),
        ?assert(ecallmgr_call_monitor:guard(?NODE, j([])))
    after meck:unload(freeswitch) end.

ready_requires_new_worker_verified_correlation_test() ->
    R = j([{<<"Originate-UUID">>, ?SUPERVISOR}, {<<"Originate-Queue">>, <<"worker">>}
           ,{<<"Msg-ID">>, ?REQUEST}, {<<"Event-Category">>, <<"dialplan">>}, {<<"Event-Name">>, <<"originate_ready">>}
           | ecallmgr_call_monitor:ready_headers(request(<<"whisper">>)) ++ kz_api:default_headers(<<"ecallmgr">>, <<"5">>)]),
    ?assert(cb_channel_monitor:ready(R, ?REQUEST, ?SUPERVISOR)),
    ?assertNot(cb_channel_monitor:ready(kz_json:delete_key(<<"Monitor-Verified">>, R), ?REQUEST, ?SUPERVISOR)),
    ?assertNot(cb_channel_monitor:ready(R, ?REQUEST, ?TARGET)),
    ?assertNot(ecallmgr_call_monitor:execute_matches(request(<<"whisper">>), j([{<<"Originate-UUID">>, ?SUPERVISOR}]))),
    ?assert(ecallmgr_call_monitor:execute_matches(request(<<"whisper">>), j([{<<"Originate-UUID">>, ?SUPERVISOR}, {<<"Msg-ID">>, ?REQUEST}]))).

protocol_builders_preserve_monitor_security_metadata_test() ->
    Props = [{<<"Event-Category">>, <<"resource">>}, {<<"Event-Name">>, <<"originate_req">>} | kz_json:to_proplist(request(<<"whisper">>))],
    {ok, Payload} = kapi_resource:originate_req(Props),
    J = kz_json:decode(iolist_to_binary(Payload)),
    ?assertEqual(?REQUEST, kz_json:get_value(<<"Monitor-Request-ID">>, J)),
    ?assertEqual(?ACCOUNT, kz_json:get_value(<<"Monitor-Account-ID">>, J)),
    ?assertEqual(<<"start">>, kz_json:get_value(<<"Monitor-Operation">>, J)),
    ?assert(ecallmgr_call_monitor:valid_request(?NODE, J)).

unregistered_endpoint_cannot_produce_ready_dialstring_test() ->
    meck:new(ecallmgr_util, [non_strict, no_link]),
    try
        meck:expect(ecallmgr_util, get_dial_separator, fun(_, _) -> <<",">> end),
        meck:expect(ecallmgr_util, build_bridge_string, fun(_, _) -> <<>> end),
        ?assertEqual(undefined, ecallmgr_originate:build_originate(<<"eavesdrop:uuid inline">>, [j([])], j([])))
    after meck:unload(ecallmgr_util) end.

non_admin_and_cross_account_never_reach_lookup_test() ->
    C = cb_context:setters(cb_context:new(), [{fun cb_context:set_account_id/2, ?ACCOUNT}
        ,{fun cb_context:set_auth_account_id/2, ?ACCOUNT}, {fun cb_context:set_is_account_admin/2, false}
        ,{fun cb_context:set_req_data/2, data(<<"whisper">>)}]),
    ?assertEqual(403, cb_context:resp_error_code(cb_channel_monitor:validate(C, ?TARGET))),
    C2 = cb_context:set_auth_account_id(cb_context:set_is_account_admin(C, true), ?DEVICE),
    ?assertEqual(403, cb_context:resp_error_code(cb_channel_monitor:validate(C2, ?TARGET))).

stop_kills_only_fresh_correlated_supervisor_test() ->
    meck:new(freeswitch, [non_strict, no_link]),
    meck:new(kapi_resource, [non_strict, no_link]),
    try
        meck:expect(kapi_resource, publish_originate_resp, fun(_, _) -> ok end),
        meck:expect(freeswitch, api, fun(?NODE, uuid_dump, ?SUPERVISOR) ->
            {ok, <<"Unique-ID: ", ?SUPERVISOR/binary, "\nvariable_ecallmgr_Account-ID: ", ?ACCOUNT/binary,
                   "\nChannel-State: CS_EXECUTE\nvariable_ecallmgr_Monitor-Request-ID: ", ?REQUEST/binary,
                   "\nvariable_ecallmgr_Monitor-Target-ID: ", ?TARGET/binary,
                   "\nvariable_ecallmgr_Monitor-Mode: whisper\n">>};
            (?NODE, uuid_kill, Kill) ->
                ?assertEqual(<<?SUPERVISOR/binary, " NORMAL_CLEARING">>, Kill),
                {ok, <<"+OK\n">>}
        end),
        Stop = kz_json:set_values([{<<"Monitor-Operation">>, <<"stop">>}, {<<"Eavesdrop-Call-ID">>, ?SUPERVISOR}], request(<<"whisper">>)),
        ?assertEqual(ok, ecallmgr_call_monitor:stop(?NODE, Stop)),
        ?assertEqual(1, meck:num_calls(freeswitch, api, [?NODE, uuid_kill, '_'])),
        ?assertEqual(0, meck:num_calls(freeswitch, api, [?NODE, uuid_kill, <<?TARGET/binary, " NORMAL_CLEARING">>])),
        meck:expect(freeswitch, api, fun(_, uuid_dump, _) -> {ok, <<"-ERR No such channel!">>} end),
        ?assertEqual(ok, ecallmgr_call_monitor:stop(?NODE, Stop)),
        ?assertEqual(1, meck:num_calls(freeswitch, api, [?NODE, uuid_kill, '_']))
    after meck:unload(freeswitch), meck:unload(kapi_resource) end.

duplicate_execute_does_not_originate_again_test() ->
    State = {state, ?NODE, undefined, undefined, request(<<"whisper">>), undefined, undefined,
             <<"dial">>, undefined, undefined, ?SUPERVISOR, undefined, undefined, true, {self(), make_ref()}},
    ?assertEqual({noreply, State}, ecallmgr_originate:handle_cast(originate_execute, State)).

legacy_queue_monitoring_is_explicitly_unavailable_test() ->
    C = cb_context:set_req_verb(cb_context:new(), <<"PUT">>),
    [?assertEqual(503, cb_context:resp_error_code(Result)) || Result <-
        [cb_queues:validate(C, <<"eavesdrop">>), cb_queues:validate(C, <<"queue">>, <<"eavesdrop">>)
        ,cb_queues:put(C, <<"eavesdrop">>), cb_queues:put(C, <<"queue">>, <<"eavesdrop">>)]].
