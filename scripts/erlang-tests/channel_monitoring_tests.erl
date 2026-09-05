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

stop_request() ->
    kz_json:set_values([{<<"Monitor-Operation">>, <<"stop">>}, {<<"Eavesdrop-Call-ID">>, ?SUPERVISOR}], request(<<"whisper">>)).

supervisor_props() ->
    props(?SUPERVISOR, ?ACCOUNT) ++ [{<<"variable_ecallmgr_Monitor-Request-ID">>, ?REQUEST}
        ,{<<"variable_ecallmgr_Monitor-Target-ID">>, ?TARGET}, {<<"variable_ecallmgr_Monitor-Mode">>, <<"whisper">>}].

dump(P) -> {ok, iolist_to_binary([[K, <<": ">>, V, <<"\n">>] || {K,V} <- P])}.

with_stop_mocks(Responses, Test) ->
    meck:new(freeswitch, [non_strict, no_link]),
    meck:new(kapi_resource, [non_strict, no_link]),
    try
        meck:expect(kapi_resource, publish_originate_resp, fun(_, _) -> ok end),
        meck:expect(freeswitch, api, 4, meck:seq(Responses)),
        Test(),
        ?assert(meck:validate(freeswitch))
    after meck:unload(freeswitch), meck:unload(kapi_resource) end.

assert_stop_calls(Commands) ->
    Calls = [Args || Entry <- meck:history(freeswitch), {freeswitch, api, Args} <- [element(2, Entry)]],
    ?assertEqual(Commands, [Command || [_, Command, _, _] <- Calls]),
    lists:foreach(fun([Node, Command, Args, Timeout]) ->
        ?assertEqual(?NODE, Node),
        ?assertEqual(case Command of uuid_kill -> <<?SUPERVISOR/binary, " NORMAL_CLEARING">>; _ -> ?SUPERVISOR end, Args),
        ?assert(is_integer(Timeout) andalso Timeout > 0 andalso Timeout =< 750)
    end, Calls).

assert_stop_response(Expected) ->
    [{_, {kapi_resource, publish_originate_resp, [_, Reply]}, ok}] = meck:history(kapi_resource),
    ?assertEqual(Expected, proplists:get_value(<<"Application-Response">>, Reply)),
    ?assertEqual(?SUPERVISOR, proplists:get_value(<<"Call-ID">>, Reply)),
    ?assertEqual(?REQUEST, proplists:get_value(<<"Msg-ID">>, Reply)),
    ?assertEqual(?REQUEST, proplists:get_value(<<"Monitor-Request-ID">>, Reply)).

stop_normalized_empty_success_requires_fresh_absence_test() ->
    lists:foreach(fun(Kill) ->
        with_stop_mocks([dump(supervisor_props()), Kill, {ok, false}], fun() ->
            ?assertEqual(ok, ecallmgr_call_monitor:stop(?NODE, stop_request())),
            assert_stop_response(<<"MONITOR_STOPPED">>),
            assert_stop_calls([uuid_dump, uuid_kill, uuid_exists])
        end)
    end, [ok, {ok, <<>>}]).

stop_real_mod_kazoo_wire_normalization_test() ->
    %% This is the actual transport adapter, not the old impossible mock that
    %% returned raw '+OK'. Only a local process exists in this isolated VM.
    Parent = self(),
    Replies = [dump(supervisor_props()), {ok, <<"+OK\n">>}, {ok, <<"false">>}],
    Pid = spawn(fun() -> wire_fixture(Parent, Replies) end),
    true = register(mod_kazoo, Pid),
    meck:new(kapi_resource, [non_strict, no_link]),
    try
        meck:expect(kapi_resource, publish_originate_resp, fun(_, _) -> ok end),
        Stop = kz_json:set_value(<<"Switch-Nodename">>, atom_to_binary(node()), stop_request()),
        ?assertEqual(ok, ecallmgr_call_monitor:stop(node(), Stop)),
        assert_stop_response(<<"MONITOR_STOPPED">>),
        Requests = [receive {wire_request, Pid, R} -> R after 1000 -> timeout end || _ <- Replies],
        ?assertEqual([{api, uuid_dump, ?SUPERVISOR}, {api, uuid_kill, <<?SUPERVISOR/binary, " NORMAL_CLEARING">>}
                     ,{api, uuid_exists, ?SUPERVISOR}], Requests)
    after exit(Pid, kill), meck:unload(kapi_resource) end.

wire_fixture(_, []) -> ok;
wire_fixture(Parent, [Reply|Rest]) ->
    receive {'$gen_call', {From, Tag}, Request} ->
        Parent ! {wire_request, self(), Request},
        From ! {Tag, Reply},
        wire_fixture(Parent, Rest)
    after 5000 -> exit(fixture_timeout)
    end.

stop_waits_for_terminal_channel_to_disappear_test() ->
    Terminal = lists:keyreplace(<<"Channel-State">>, 1, supervisor_props(), {<<"Channel-State">>, <<"CS_HANGUP">>}),
    with_stop_mocks([dump(supervisor_props()), ok, {ok, true}, dump(Terminal), {ok, false}], fun() ->
        ?assertEqual(<<"MONITOR_STOPPED">>, ecallmgr_call_monitor:stop_result(?NODE, stop_request(), 500)),
        assert_stop_calls([uuid_dump, uuid_kill, uuid_exists, uuid_dump, uuid_exists])
    end).

stop_handles_dump_disappearance_race_only_with_new_exists_proof_test() ->
    lists:foreach(fun({Last, Expected}) ->
        with_stop_mocks([dump(supervisor_props()), ok, {ok, true}, {error, <<"No such channel!">>}, Last], fun() ->
            ?assertEqual(Expected, ecallmgr_call_monitor:stop_result(?NODE, stop_request(), 500)),
            assert_stop_calls([uuid_dump, uuid_kill, uuid_exists, uuid_dump, uuid_exists])
        end)
    end, [{{ok, false}, <<"MONITOR_STOPPED">>}, {{error, timeout}, <<"MONITOR_STOP_FAILED">>}]).

stop_still_live_times_out_without_repeated_kill_test() ->
    with_stop_mocks([ok], fun() ->
        meck:expect(freeswitch, api, fun(_, uuid_dump, _, _) -> dump(supervisor_props());
            (_, uuid_exists, _, _) -> {ok, true}; (_, uuid_kill, _, _) -> ok end),
        Started = erlang:monotonic_time(millisecond),
        ?assertEqual(<<"MONITOR_STOP_FAILED">>, ecallmgr_call_monitor:stop_result(?NODE, stop_request(), 80)),
        Elapsed = erlang:monotonic_time(millisecond) - Started,
        ?assert(Elapsed >= 80 andalso Elapsed < 500),
        ?assertEqual(1, meck:num_calls(freeswitch, api, [?NODE, uuid_kill, '_', '_'])),
        ?assertEqual(0, meck:num_calls(freeswitch, api, [?NODE, uuid_kill, <<?TARGET/binary, " NORMAL_CLEARING">>, '_']))
    end).

stop_transport_errors_unknown_and_arbitrary_ok_fail_closed_test() ->
    lists:foreach(fun(Observation) ->
        with_stop_mocks([dump(supervisor_props()), ok, Observation], fun() ->
            ?assertEqual(<<"MONITOR_STOP_FAILED">>, ecallmgr_call_monitor:stop_result(?NODE, stop_request(), 500)),
            assert_stop_calls([uuid_dump, uuid_kill, uuid_exists])
        end)
    end, [{error, timeout}, {error, nodedown}, meck:raise(exit, nodedown)
          ,ok, {ok, <<>>}, {ok, <<"false">>}, {ok, <<"+OK false">>}]),
    lists:foreach(fun(Kill) ->
        with_stop_mocks([dump(supervisor_props()), Kill, {ok, false}], fun() ->
            ?assertEqual(<<"MONITOR_STOP_FAILED">>, ecallmgr_call_monitor:stop_result(?NODE, stop_request(), 500)),
            assert_stop_calls([uuid_dump, uuid_kill])
        end)
    end, [{error, timeout}, {ok, <<"+OK but not terminated">>}, {ok, <<"+OK\n">>}, {ok, true}]),
    with_stop_mocks([dump(supervisor_props()), ok, {ok, true}, {error, timeout}], fun() ->
        ?assertEqual(<<"MONITOR_STOP_FAILED">>, ecallmgr_call_monitor:stop_result(?NODE, stop_request(), 500)),
        assert_stop_calls([uuid_dump, uuid_kill, uuid_exists, uuid_dump])
    end).

stop_reused_or_mutated_uuid_never_rekilled_or_reported_stopped_test() ->
    Changes = [{<<"Unique-ID">>, ?TARGET}, {<<"variable_ecallmgr_Account-ID">>, ?DEVICE}
        ,{<<"variable_ecallmgr_Monitor-Request-ID">>, ?DEVICE}, {<<"variable_ecallmgr_Monitor-Target-ID">>, ?DEVICE}
        ,{<<"variable_ecallmgr_Monitor-Mode">>, <<"full">>}, {<<"Channel-State">>, <<"unknown">>}],
    lists:foreach(fun({Key, Value}) ->
        Changed = lists:keyreplace(Key, 1, supervisor_props(), {Key, Value}),
        with_stop_mocks([dump(supervisor_props()), ok, {ok, true}, dump(Changed), {ok, false}], fun() ->
            ?assertEqual(<<"MONITOR_STOP_FAILED">>, ecallmgr_call_monitor:stop_result(?NODE, stop_request(), 500)),
            assert_stop_calls([uuid_dump, uuid_kill, uuid_exists, uuid_dump])
        end)
    end, Changes).

stop_original_call_or_bad_authorization_never_killed_test() ->
    Dumps = [dump(props(?SUPERVISOR, ?ACCOUNT)), dump(supervisor_props() ++ [{<<"variable_ecallmgr_Account-ID">>, ?DEVICE}])
             ,{error, <<"No such channel!">>}, {error, timeout}],
    lists:foreach(fun(Dump) ->
        with_stop_mocks([Dump], fun() ->
            ?assertEqual(<<"MONITOR_STOP_DENIED">>, ecallmgr_call_monitor:stop_result(?NODE, stop_request(), 500)),
            assert_stop_calls([uuid_dump])
        end)
    end, Dumps),
    lists:foreach(fun({Node, Stop}) ->
        with_stop_mocks([dump(supervisor_props())], fun() ->
            ?assertEqual(<<"MONITOR_STOP_DENIED">>, ecallmgr_call_monitor:stop_result(Node, Stop, 500)),
            assert_stop_calls([])
        end)
    end, [{'fs@other', stop_request()}, {?NODE, request(<<"whisper">>)}
          ,{?NODE, kz_json:set_value(<<"Msg-ID">>, ?DEVICE, stop_request())}]),
    Original = kz_json:set_values([{<<"Outbound-Call-ID">>, ?TARGET}, {<<"Originate-UUID">>, ?TARGET}
                                  ,{<<"Eavesdrop-Call-ID">>, ?TARGET}], stop_request()),
    with_stop_mocks([dump(props(?TARGET, ?ACCOUNT))], fun() ->
        ?assertEqual(<<"MONITOR_STOP_DENIED">>, ecallmgr_call_monitor:stop_result(?NODE, Original, 500)),
        ?assertEqual(1, meck:num_calls(freeswitch, api, [?NODE, uuid_dump, ?TARGET, '_'])),
        ?assertEqual(0, meck:num_calls(freeswitch, api, [?NODE, uuid_kill, '_', '_']))
    end).

stop_late_response_cannot_escape_total_deadline_test() ->
    with_stop_mocks([ok], fun() ->
        meck:expect(freeswitch, api, fun(_, uuid_dump, _, _) -> dump(supervisor_props());
            (_, uuid_kill, _, _) -> ok;
            (_, uuid_exists, _, Timeout) -> receive after Timeout + 5 -> {ok, false} end
        end),
        ?assertEqual(<<"MONITOR_STOP_FAILED">>, ecallmgr_call_monitor:stop_result(?NODE, stop_request(), 30)),
        assert_stop_calls([uuid_dump, uuid_kill, uuid_exists])
    end).

duplicate_execute_does_not_originate_again_test() ->
    State = {state, ?NODE, undefined, undefined, request(<<"whisper">>), undefined, undefined,
             <<"dial">>, undefined, undefined, ?SUPERVISOR, undefined, undefined, true, {self(), make_ref()}},
    ?assertEqual({noreply, State}, ecallmgr_originate:handle_cast(originate_execute, State)).

legacy_queue_monitoring_is_explicitly_unavailable_test() ->
    C = cb_context:set_req_verb(cb_context:new(), <<"PUT">>),
    [?assertEqual(503, cb_context:resp_error_code(Result)) || Result <-
        [cb_queues:validate(C, <<"eavesdrop">>), cb_queues:validate(C, <<"queue">>, <<"eavesdrop">>)
        ,cb_queues:put(C, <<"eavesdrop">>), cb_queues:put(C, <<"queue">>, <<"eavesdrop">>)]].
