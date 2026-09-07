-module(acdc_cardinal_media_tests).
-include_lib("eunit/include/eunit.hrl").
-include("acdc_cardinal_map.hrl").

-define(LANG, <<"en-us">>).
-define(ACCOUNT, <<"302ae5a70c403124f764cbc54229cfcd">>).

assets() -> ?CARDINAL_ASSETS.
frame(_, _, _) -> {ok, [{play, <<"/system_media/en-us/approved-intro">>}], []}.
read(Id) ->
    [A] = [A || A <- assets(), id(A) =:= Id],
    {ok, doc(A)}.
id(A) -> <<(element(1, A))/binary, "/", (element(3, A))/binary>>.
doc({Language, Canonical, Prompt, Sha, Md5, Length, Transcript} = A) ->
    {[{<<"_id">>, id(A)}, {<<"_rev">>, <<"1-abc">>},
      {<<"pvt_type">>, <<"media">>}, {<<"pvt_account_db">>, <<"system_media">>},
      {<<"source_type">>, <<"kazoo5_acdc_gemini_voice_installer">>},
      {<<"prompt_id">>, Prompt}, {<<"language">>, Language},
      {<<"content_type">>, <<"audio/wav">>}, {<<"content_length">>, Length},
      {<<"streamable">>, true},
      {<<"source_voice">>, {[{<<"provider">>, <<"google-gemini">>},
          {<<"model">>, <<"gemini-2.5-pro-preview-tts">>}, {<<"voice">>, <<"Sulafat">>},
          {<<"canonical_prompt_id">>, Canonical}, {<<"sha256">>, Sha},
          {<<"transcript_sha256">>, Transcript}]}},
      {<<"_attachments">>, {[{<<Prompt/binary, ".wav">>,
          {[{<<"content_type">>, <<"audio/wav">>}, {<<"length">>, Length},
            {<<"digest">>, Md5}]}}]}}]}.

prepare(Assets, Read) ->
    acdc_cardinal_media:prepare_with(?LANG, ?ACCOUNT, [], Assets, Read, fun frame/3).

complete_pack_play_only_test() ->
    {ok, Audio} = prepare(assets(), fun read/1),
    Prompts = acdc_cardinal_media:playlist(999999999, ?LANG, Audio),
    ?assertEqual(15, length(Prompts)),
    ?assert(lists:all(fun({play, <<"/system_media/en-us/", _/binary>>}) -> true;
                        (_) -> false end, Prompts)),
    ?assertEqual([], acdc_cardinal_media:playlist(1, <<"fr-fr">>, Audio)),
    lists:foreach(fun(N) -> ?assertEqual([], acdc_cardinal_media:playlist(N, ?LANG, Audio)) end,
                  [0, -1, 1000000000, undefined, 1.0, <<"1">>]),
    ?assertEqual([], acdc_cardinal_media:playlist(1, ?LANG, Audio#{assets := #{}})).

missing_duplicate_wrong_role_fail_closed_test() ->
    [First | Rest] = assets(),
    Bad = setelement(2, First, <<"unapproved-role">>),
    lists:foreach(fun(Items) -> ?assertEqual({error, cardinal_media_unavailable},
                                            prepare(Items, fun read/1)) end,
                  [Rest, [First | assets()], [Bad | Rest]]).

missing_wrong_metadata_and_exception_fail_closed_test() ->
    lists:foreach(fun(Read) ->
        ?assertEqual({error, cardinal_media_unavailable}, prepare(assets(), Read))
    end, [fun(_) -> {error, not_found} end,
          fun(_) -> {ok, {[]}} end,
          fun(_) -> error(test_failure) end]),
    ?assertEqual({error, unsupported_language},
        acdc_cardinal_media:prepare_with(<<"fr-fr">>, ?ACCOUNT, [], assets(),
            fun(_) -> error(must_not_read) end, fun frame/3)).

frame_failure_reads_no_cardinals_test() ->
    Ref = make_ref(),
    ?assertEqual({error, cardinal_media_unavailable},
        acdc_cardinal_media:prepare_with(?LANG, ?ACCOUNT, [], assets(),
            fun(_) -> self() ! {Ref, unexpected_read}, error(must_not_read) end,
            fun(_, _, _) -> {error, unavailable} end)),
    receive {Ref, unexpected_read} -> ?assert(false) after 0 -> ok end.

custom_framing_does_not_change_number_test() ->
    {ok, Audio} = acdc_cardinal_media:prepare_with(?LANG, ?ACCOUNT, [], assets(),
        fun read/1, fun(_, _, _) -> {ok, [{prompt, <<"my-prefix">>, ?LANG, <<"A">>}],
                                       [{prompt, <<"my-suffix">>, ?LANG, <<"A">>}]} end),
    [Prefix, {play, _}, {play, _}, Suffix] = acdc_cardinal_media:playlist(21, ?LANG, Audio),
    ?assertEqual({prompt, <<"my-prefix">>, ?LANG, <<"A">>}, Prefix),
    ?assertEqual({prompt, <<"my-suffix">>, ?LANG, <<"A">>}, Suffix).

actual_frame_preserves_explicit_and_account_overrides_test_() ->
    {timeout, 30, fun() ->
        ok = meck:new(acdc_gemini_prompts, [passthrough, no_link]),
        try
            meck:expect(acdc_gemini_prompts, default_alias,
                fun(_Legacy, Canonical, _, _, absent) -> {gemini, Canonical};
                   (_, _, _, _, {configured, Value}) -> {custom, Value}
                end),
            meck:expect(acdc_gemini_prompts, default,
                fun(_, _, _, absent) -> {custom, <<"account-combined-intro">>} end),
            ?assertEqual({ok, [{prompt, <<"account-combined-intro">>, ?LANG, <<"A">>}], []},
                         acdc_cardinal_media:frame(?LANG, ?ACCOUNT, [])),
            ?assertEqual({ok, [{prompt, <<"queue-you_are_at_position">>, ?LANG, <<"A">>}],
                             [{play, <<"/system_media/en-us/acdc-queue-in_the_queue">>}]},
                acdc_cardinal_media:frame(?LANG, ?ACCOUNT,
                    [{<<"you_are_at_position">>, <<"queue-you_are_at_position">>}]))
        after meck:unload(acdc_gemini_prompts) end
    end}.

announcement_preflight_and_independent_clocks_test_() ->
    {timeout, 30, fun() ->
        ok = meck:new(acdc_cardinal_media, [passthrough, no_link]),
        try
            Media = [{<<"you_are_at_position">>, <<"queue-you_are_at_position">>}],
            Config = acdc_announcements:get_config([
                {<<"position_announcements_enabled">>, true}, {<<"media">>, Media},
                {<<"callback">>, [{<<"enabled">>, true}, {<<"announcement">>,
                    [{<<"initial_delay">>, 30}, {<<"interval">>, 45}]}]}]),
            ?assertEqual(Media, maps:get(announcements_media_selection, Config)),
            Call = kapps_call:set_language(?LANG, kapps_call:set_account_id(?ACCOUNT, kapps_call:new())),
            meck:expect(acdc_cardinal_media, prepare, fun(?LANG, ?ACCOUNT, Actual) ->
                ?assertEqual(Media, Actual), {error, unavailable}
            end),
            Missing = acdc_announcements:resolve_position_audio(Config, Call),
            ?assertEqual(false, maps:get(position_announcements_enabled, Missing)),
            ?assertEqual(true, maps:get(callback_announcements_enabled, Missing)),
            ?assertEqual(#{position => infinity, callback => 30100},
                acdc_announcements:schedule_init(Missing, 100)),
            ?assertEqual(45, maps:get(callback_interval, Missing)),
            ?assertEqual([], acdc_announcements:position_prompts(1, ?LANG, Missing)),
            {ok, Audio} = prepare(assets(), fun read/1),
            meck:expect(acdc_cardinal_media, prepare, fun(_, _, _) -> {ok, Audio} end),
            Ready = acdc_announcements:resolve_position_audio(Config, Call),
            ?assertEqual(acdc_cardinal_media:playlist(21, ?LANG, Audio),
                acdc_announcements:position_prompts(21, <<"EN_US">>, Ready)),
            ?assertEqual(#{position => 30100, callback => 30100},
                acdc_announcements:schedule_init(Ready, 100))
        after meck:unload(acdc_cardinal_media) end
    end}.
