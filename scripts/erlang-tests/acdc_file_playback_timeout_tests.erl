%%% SPDX-License-Identifier: MPL-2.0
-module(acdc_file_playback_timeout_tests).
-include_lib("eunit/include/eunit.hrl").

request(Props) -> kz_json:from_list(Props ++
    [{<<"Application-Name">>, <<"play">>}, {<<"Call-ID">>, <<"bounded-test">>}
    ,{<<"Media-Name">>, <<"/tmp/bounded-test.wav">>}, {<<"Msg-ID">>, <<"bounded-request">>} |
     kz_api:default_headers(<<"call">>, <<"command">>, <<"bounded-test">>, <<"1">>)]).

strict_timeout_validation_test() ->
    lists:foreach(fun(V) ->
        J = request([{<<"Playback-Timeout-Ms">>, V}]),
        ?assertEqual({V, true, true}, {V, kapi_definition:validate(J, kapi_dialplan:api_definition(<<"play">>)), kapi_dialplan:play_v(J)}),
        ?assert(kapi_dialplan:play_v(kz_json:to_proplist(J))),
        ?assertMatch({ok, _}, kapi_dialplan:play(J))
    end, [1, 2000, 60000]),
    lists:foreach(fun(V) ->
        J = request([{<<"Playback-Timeout-Ms">>, V}]),
        ?assertNot(kapi_dialplan:play_v(J)),
        ?assertMatch({error, _}, kapi_dialplan:play(J))
    end, [0, -1, 60001, 2.5, <<"2000">>, true, null]),
    lists:foreach(fun(Pair) ->
        ?assertNot(kapi_dialplan:play_v(request([{<<"Playback-Timeout-Ms">>, 2000}, Pair])))
    end, [{<<"Playback-Timeout">>, 2}, {<<"Endless-Playback">>, true}, {<<"Loop-Count">>, 2}]),
    ?assert(kapi_dialplan:play_v(request([]))),
    ?assert(kapi_dialplan:play_v(request([{<<"Playback-Timeout">>, 2}]))).

per_file_path_and_legacy_unchanged_test() ->
    Paths = [<<"/tmp/bounded-test.wav">>, <<"http_cache://http://127.0.0.1:24517/media/file.wav">>],
    lists:foreach(fun(P) ->
        ?assertEqual(P, ecallmgr_call_command:file_playback_timeout(P, request([]))),
        ?assertEqual(<<"{timeout=2000}", P/binary>>,
          ecallmgr_call_command:file_playback_timeout(P, request([{<<"Playback-Timeout-Ms">>, 2000}])) )
    end, Paths),
    Existing = <<"{timeout=999999}/tmp/file.wav">>,
    ?assertEqual(Existing, ecallmgr_call_command:file_playback_timeout(Existing, request([]))),
    ?assertThrow({msg, _}, ecallmgr_call_command:file_playback_timeout(Existing, request([{<<"Playback-Timeout-Ms">>, 2000}]))).

rendering_does_not_set_channel_timeout_test_() -> {timeout, 15, fun() ->
    ok = meck:new(ecallmgr_util, [non_strict, no_link]),
    ok = meck:new(ecallmgr_fs_channel, [non_strict, no_link]),
    meck:expect(ecallmgr_util, media_path, fun(_, new, _, _) -> <<"/tmp/resolved.wav">> end),
    meck:expect(ecallmgr_fs_channel, is_bridged, fun(_) -> false end),
    meck:expect(ecallmgr_util, process_fs_kv, fun(_, Props, set) ->
        ?assertEqual(undefined, proplists:get_value(<<"playback_timeout_sec">>, Props)),
        ?assertEqual(undefined, proplists:get_value(<<"playback_timeout_as_success">>, Props)), [] end),
    meck:expect(ecallmgr_util, fs_args_to_binary, fun([]) -> <<>> end),
    try
        Apps = ecallmgr_call_command:fetch_dialplan(testnode, <<"bounded-test">>,
                    request([{<<"Playback-Timeout-Ms">>, 2000}])),
        ?assert(lists:member({<<"playback">>, <<"{timeout=2000}/tmp/resolved.wav">>}, Apps)),
        Legacy = ecallmgr_call_command:fetch_dialplan(testnode, <<"bounded-test">>, request([])),
        ?assert(lists:member({<<"playback">>, <<"/tmp/resolved.wav">>}, Legacy))
    after meck:unload(ecallmgr_util), meck:unload(ecallmgr_fs_channel) end
end}.
