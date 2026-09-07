-module(acdc_wait_time_media_tests).
-include_lib("eunit/include/eunit.hrl").
-include("acdc_gemini_map.hrl").
-define(ACCOUNT, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).

keys() -> [<<"increase_in_call_volume">>, <<"the_estimated_wait_time_is">>, <<"less_than_1_minute">>,
    <<"about_5_minutes">>, <<"about_10_minutes">>, <<"about_15_minutes">>, <<"about_30_minutes">>,
    <<"about_45_minutes">>, <<"about_1_hour">>, <<"at_least_1_hour">>].
locales() -> [<<"en-us">>, <<"he-il">>, <<"fr-fr">>, <<"es-es">>, <<"ar-sa">>].
asset(L, K) -> [A] = [A || A <- ?GEMINI_ASSETS, element(1,A) =:= L, element(2,A) =:= <<"acdc-queue-", K/binary>>], A.
path(A) -> <<"/system_media/", (element(1,A))/binary, "/", (element(3,A))/binary>>.
doc({L,C,P,S,M,N,T}) ->
    kz_json:from_list([{<<"_id">>,<<L/binary,"/",P/binary>>},{<<"_rev">>,<<"1-abc">>},
        {<<"pvt_type">>,<<"media">>},{<<"pvt_account_db">>,<<"system_media">>},
        {<<"source_type">>,<<"kazoo5_acdc_gemini_voice_installer">>},{<<"prompt_id">>,P},
        {<<"language">>,L},{<<"content_type">>,<<"audio/wav">>},{<<"content_length">>,N},{<<"streamable">>,true},
        {<<"source_voice">>,kz_json:from_list([{<<"provider">>,<<"google-gemini">>},{<<"model">>,<<"gemini-2.5-pro-preview-tts">>},
            {<<"voice">>,<<"Sulafat">>},{<<"canonical_prompt_id">>,C},{<<"sha256">>,S},{<<"transcript_sha256">>,T}])},
        {<<"_attachments">>,kz_json:from_list([{<<P/binary,".wav">>,kz_json:from_list([
            {<<"content_type">>,<<"audio/wav">>},{<<"length">>,N},{<<"digest">>,M}])}])}]).
reader(Change) ->
    meck:expect(kz_datamgr, open_cache_doc, fun
        (<<"system_media">>, Id) ->
            [A] = [A || A <- ?GEMINI_ASSETS, <<(element(1,A))/binary,"/",(element(3,A))/binary>> =:= Id],
            Change(A, doc(A));
        (_, _) -> {error,not_found}
    end),
    meck:expect(kz_datamgr, get_results, fun(_, <<"media/listing_by_prompt">>, _) -> {ok,[]} end).

real_fixed_metadata_five_locale_prepare_and_pure_boundaries_test_() ->
    {timeout, 30, fun() ->
        ok = meck:new(kz_datamgr, [passthrough,no_link]),
        try
            lists:foreach(fun(L) ->
                reader(fun(_,D) -> {ok,D} end),
                {ok,Audio} = acdc_wait_time_media:prepare(L, ?ACCOUNT, []),
                ?assertEqual(lists:sort(keys()), lists:sort(maps:keys(maps:get(assets,Audio)))),
                meck:expect(kz_datamgr, open_cache_doc, fun(_,_) -> error(no_interval_reads) end),
                meck:expect(kz_datamgr, get_results, fun(_,_,_) -> error(no_interval_reads) end),
                Config = (acdc_announcements:get_config([]))#{wait_time_audio => Audio},
                lists:foreach(fun({N,K}) ->
                    Expected = {[{play,path(asset(L,<<"the_estimated_wait_time_is">>))},{play,path(asset(L,K))}],N},
                    ?assertEqual(Expected, acdc_wait_time_media:playlist(N,undefined,L,Audio)),
                    ?assertEqual(Expected, acdc_announcements:wait_time_prompts(N,undefined,L,Config)),
                    {Commands,N} = acdc_wait_time_media:playlist(N,-1,L,Audio),
                    ?assertEqual([{play,path(asset(L,<<"increase_in_call_volume">>))}|element(1,Expected)],Commands)
                end, [{0,<<"less_than_1_minute">>},{59,<<"less_than_1_minute">>},
                    {60,<<"about_5_minutes">>},{300,<<"about_5_minutes">>}, {301,<<"about_10_minutes">>},
                    {600,<<"about_10_minutes">>},{601,<<"about_15_minutes">>},{900,<<"about_15_minutes">>},
                    {901,<<"about_30_minutes">>},{1800,<<"about_30_minutes">>},{1801,<<"about_45_minutes">>},
                    {2700,<<"about_45_minutes">>},{2701,<<"about_1_hour">>},{3600,<<"about_1_hour">>},
                    {3601,<<"at_least_1_hour">>},{999999999,<<"at_least_1_hour">>}]),
                lists:foreach(fun(N) -> ?assertEqual({[],75},acdc_wait_time_media:playlist(N,75,L,Audio)) end,
                    [undefined,-1,1.0,<<"60">>]),
                ?assertEqual({[],75},acdc_wait_time_media:playlist(60,75,<<"de-de">>,Audio)),
                ?assertEqual({[],75},acdc_wait_time_media:playlist(60,75,L,Audio#{assets := #{}})),
                Bad = maps:put(<<"about_5_minutes">>,{say,<<"5">>,number},maps:get(assets,Audio)),
                ?assertEqual({[],75},acdc_wait_time_media:playlist(60,75,L,Audio#{assets := Bad}))
            end,locales())
        after meck:unload(kz_datamgr) end
    end}.

missing_wrong_metadata_and_account_overrides_test_() ->
    {timeout, 30, fun() ->
        ok = meck:new(kz_datamgr,[passthrough,no_link]),
        try
            L = <<"he-il">>,
            lists:foreach(fun(K) ->
                Missing = asset(L,K), reader(fun(A,D) -> case A =:= Missing of true -> {error,not_found}; false -> {ok,D} end end),
                ?assertEqual({error,wait_time_media_unavailable},acdc_wait_time_media:prepare(L,?ACCOUNT,[]))
            end,keys()),
            reader(fun(_,D) -> {ok,kz_json:set_value([<<"source_voice">>,<<"voice">>],<<"other">>,D)} end),
            ?assertEqual({error,wait_time_media_unavailable},acdc_wait_time_media:prepare(L,?ACCOUNT,[])),
            reader(fun(_,D) -> {ok,D} end),
            meck:expect(kz_datamgr,get_results,fun(_,_,_) -> {error,timeout} end),
            ?assertEqual({error,wait_time_media_unavailable},acdc_wait_time_media:prepare(L,?ACCOUNT,[])),
            reader(fun(_,D) -> {ok,D} end),
            meck:expect(kz_datamgr,get_results,fun(_,_,Options) ->
                case proplists:get_value(startkey,Options) of [<<"queue-about_5_minutes">>] -> {ok,[{[]} ]}; _ -> {ok,[]} end
            end),
            Media = [{<<"the_estimated_wait_time_is">>,<<"queue-the_estimated_wait_time_is">>},
                     {<<"increase_in_call_volume">>,<<"customer-increase">>}],
            {ok,Custom} = acdc_wait_time_media:prepare(L,?ACCOUNT,Media),
            ?assertEqual({[{prompt,<<"customer-increase">>,L,<<"A">>},
                          {prompt,<<"queue-the_estimated_wait_time_is">>,L,<<"A">>},
                          {prompt,<<"queue-about_5_minutes">>,L,<<"A">>}],60},
                acdc_wait_time_media:playlist(60,0,L,Custom)),
            ?assertEqual({error,wait_time_media_unavailable},acdc_wait_time_media:prepare(L,?ACCOUNT,
                [{<<"the_estimated_wait_time_is">>,<<>>}])),
            ?assertEqual({error,wait_time_media_unavailable},acdc_wait_time_media:prepare(L,<<"invalid">>,[])),
            ?assertEqual({error,unsupported_language},acdc_wait_time_media:prepare(<<"fr-ca">>,?ACCOUNT,[]))
        after meck:unload(kz_datamgr) end
    end}.

preflight_failure_preserves_other_clocks_test_() ->
    {timeout, 30, fun() ->
        ok = meck:new(acdc_wait_time_media,[passthrough,no_link]),
        try
            C = acdc_announcements:get_config([{<<"wait_time_announcements_enabled">>,true},
                {<<"position_announcements_enabled">>,true},{<<"initial_delay">>,12},
                {<<"callback">>,[{<<"enabled">>,true}]}]),
            Call = kapps_call:set_language(<<"en-us">>,kapps_call:set_account_id(?ACCOUNT,kapps_call:new())),
            lists:foreach(fun(Result) ->
                meck:expect(acdc_wait_time_media,prepare,fun(_,_,_) ->
                    case Result of exception -> error(failed); _ -> Result end end),
                Failed = acdc_announcements:resolve_wait_time_audio(C,Call),
                ?assertEqual(C#{wait_time_announcements_enabled := false,wait_time_audio => undefined},Failed),
                ?assertEqual(#{position => 12100,callback => 30100},acdc_announcements:schedule_init(Failed,100)),
                ?assertEqual({[],75},acdc_announcements:wait_time_prompts(60,75,<<"en-us">>,Failed))
            end,[{error,unavailable},exception]),
            meck:expect(acdc_wait_time_media,prepare,fun(_,_,_) -> error(disabled_must_not_prepare) end),
            Disabled = C#{wait_time_announcements_enabled := false},
            ?assertEqual(Disabled,acdc_announcements:resolve_wait_time_audio(Disabled,Call))
        after meck:unload(acdc_wait_time_media) end
    end}.
