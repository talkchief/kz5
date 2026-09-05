%%% SPDX-License-Identifier: MPL-2.0
-module(ecallmgr_prompt_media_tests).
-include_lib("eunit/include/eunit.hrl").

prompt_resolution_test_() ->
    {foreach, fun setup/0, fun cleanup/1,
     [fun system_prompt_uses_media_manager/0,
      fun callback_prompt_uses_media_manager/0,
      fun account_prompt_preserves_account_and_language/0,
      fun cached_prompt_still_uses_http_playback/0,
      fun native_streams_are_not_sent_to_media_manager/0]}.

setup() ->
    ok = meck:new(kz_cache, [passthrough, no_link]),
    ok = meck:new(kz_amqp_worker, [passthrough, no_link]),
    ok = meck:new(kapps_config, [passthrough, no_link]),
    meck:expect(kz_cache, fetch_local, fun(_, _) -> {error, not_found} end),
    meck:expect(kz_cache, store_local, fun(_, _, _, _) -> ok end),
    meck:expect(kapps_config, is_true, fun(_, _, Default) -> Default end),
    ok.

cleanup(_) ->
    meck:unload(kz_cache), meck:unload(kz_amqp_worker), meck:unload(kapps_config).

expect_media(Prompt) ->
    meck:expect(kz_amqp_worker, call_collect,
        fun(Request, _Publish, {media_mgr, _Validator}) ->
            ?assertEqual(Prompt, kz_json:get_value(<<"Media-Name">>, Request)),
            ?assertEqual(<<"probe-call">>, kz_json:get_value(<<"Call-ID">>, Request)),
            ?assertEqual(<<"extant">>, kz_json:get_value(<<"Stream-Type">>, Request)),
            ?assertEqual(true, kapi_media:req_v(Request)),
            {ok, [kz_json:from_list([{<<"Stream-URL">>, <<"http://127.0.0.1:24517/single/prompt.wav">>}])]}
        end).

system_prompt_uses_media_manager() ->
    Prompt = <<"prompt://system_media/queue-you_are_at_position/en-us">>,
    expect_media(Prompt),
    ?assertEqual(<<"http_cache://http://127.0.0.1:24517/single/prompt.wav">>,
                 ecallmgr_util:media_path(Prompt, extant, <<"probe-call">>, kz_json:new())),
    ?assertEqual(1, meck:num_calls(kz_amqp_worker, call_collect, '_')).

account_prompt_preserves_account_and_language() ->
    Prompt = <<"prompt://11111111111111111111111111111111/custom-position/fr-ca">>,
    expect_media(Prompt),
    ?assertEqual(<<"http_cache://http://127.0.0.1:24517/single/prompt.wav">>,
                 ecallmgr_util:media_path(Prompt, extant, <<"probe-call">>, kz_json:new())).

callback_prompt_uses_media_manager() ->
    Prompt = <<"prompt://system_media/acdc-callback-menu-current/en-us">>,
    expect_media(Prompt),
    ?assertEqual(<<"http_cache://http://127.0.0.1:24517/single/prompt.wav">>,
                 ecallmgr_util:media_path(Prompt, extant, <<"probe-call">>, kz_json:new())).

cached_prompt_still_uses_http_playback() ->
    meck:expect(kz_cache, fetch_local, fun(_, _) -> {ok, <<"https://media.example.invalid/prompt.wav">>} end),
    ?assertEqual(<<"http_cache://https://media.example.invalid/prompt.wav">>,
                 ecallmgr_util:media_path(<<"prompt://system_media/queue-in_the_queue/en-us">>,
                                          extant, <<"probe-call">>, kz_json:new())),
    ?assertEqual(0, meck:num_calls(kz_amqp_worker, call_collect, '_')).

native_streams_are_not_sent_to_media_manager() ->
    lists:foreach(fun(Stream) ->
        ?assertEqual(Stream, ecallmgr_util:media_path(Stream, extant, <<"probe-call">>, kz_json:new()))
    end, [<<"silence_stream://100">>, <<"tone_stream://%(100,0,440)">>]),
    ?assertEqual(0, meck:num_calls(kz_amqp_worker, call_collect, '_')).
