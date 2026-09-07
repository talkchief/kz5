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
doc({Language, Canonical, Prompt, Sha, Md5, Length, Transcript, Model, Kind}) ->
    Base = doc({Language, Canonical, Prompt, Sha, Md5, Length, Transcript}),
    Voice = set(<<"model">>, Model, get(<<"source_voice">>, Base)),
    Source = case Canonical of <<"acdc-cardinal-v1-number-4">> -> <<"acdc-number-4">>;
                              <<"acdc-cardinal-v1-number-9">> -> <<"acdc-number-9">>;
                              _ -> undefined end,
    Resolution = {[{<<"schema_version">>, 1}, {<<"owner">>, <<"kazoo5-acdc-cardinal-import">>},
      {<<"provider">>, <<"google-gemini">>}, {<<"model">>, Model}, {<<"voice">>, <<"Sulafat">>},
      {<<"source_kind">>, Kind}, {<<"transcript_sha256">>, Transcript}, {<<"telephony_sha256">>, Sha},
      {<<"source_locale">>, Language}, {<<"source_id">>, Source},
      {<<"runtime_ready">>, false}, {<<"listening_verified">>, false}, {<<"provider_provenance_authenticated">>, false}]},
    set(<<"source_cardinal_resolution">>, Resolution, set(<<"source_voice">>, Voice, Base));
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

get(K, {Props}) -> proplists:get_value(K, Props).
set(K, V, {Props}) -> {[{K,V} | proplists:delete(K, Props)]}.

resolved_row(Asset, Model, Kind) -> list_to_tuple(tuple_to_list(Asset) ++ [Model, Kind]).

resolved_fixture_assets(Language) ->
    [resolved_row(A, Model, Kind) || A <- fixture_assets(Language),
      {Model, Kind} <- [case {Language, element(2, A)} of
        {<<"es-es">>, <<"acdc-cardinal-v1-number-4">>} ->
          {<<"gemini-2.5-pro-preview-tts">>, <<"reused_supplemental_master">>};
        {<<"es-es">>, <<"acdc-cardinal-v1-number-9">>} ->
          {<<"gemini-2.5-pro-preview-tts">>, <<"reused_supplemental_master">>};
        _ -> {<<"gemini-3.1-flash-tts-preview">>, <<"separate_model_trial">>}
      end]].

cardinal_only_model_admission_and_legacy_contract_test() ->
    [Legacy | _] = assets(),
    ?assert(acdc_gemini_prompts:verified_asset(Legacy, {ok, doc(Legacy)})),
    ?assertNot(acdc_gemini_prompts:verified_cardinal_asset(Legacy, {ok, doc(Legacy)})),
    [Base | _] = fixture_assets(<<"he-il">>),
    lists:foreach(fun({Model, Kind}) ->
        Row = resolved_row(Base, Model, Kind), Doc = doc(Row),
        ?assert(acdc_gemini_prompts:verified_cardinal_asset(Row, {ok, Doc})),
        ?assertNot(acdc_gemini_prompts:verified_asset(Row, {ok, Doc})),
        case Model of <<"gemini-3.1-flash-tts-preview">> ->
            ?assertNot(acdc_gemini_prompts:verified_asset(Base, {ok, Doc}));
            _ -> ok end
    end, [{<<"gemini-2.5-pro-preview-tts">>, <<"generated_cardinal">>},
          {<<"gemini-3.1-flash-tts-preview">>, <<"separate_model_trial">>}]),
    lists:foreach(fun({Model, Kind}) ->
        Row = resolved_row(Base, Model, Kind),
        ?assertNot(acdc_gemini_prompts:verified_cardinal_asset(Row, {ok, doc(Row)}))
    end, [{<<"gemini-2.5-pro-preview-tts">>, <<"separate_model_trial">>},
          {<<"gemini-3.1-flash-tts-preview">>, <<"generated_cardinal">>},
          {<<"gemini-3.1-flash-tts-preview">>, <<"reused_supplemental_master">>},
          {<<"foreign-model">>, <<"separate_model_trial">>}]),
    Row = resolved_row(Base, <<"gemini-3.1-flash-tts-preview">>, <<"separate_model_trial">>),
    lists:foreach(fun(Bad) -> ?assertNot(acdc_gemini_prompts:verified_cardinal_asset(Bad, {ok, doc(Row)})) end,
      [setelement(1, Row, <<"en-us">>), setelement(2, Row, <<"acdc-fixed-prompt">>),
       setelement(2, Row, <<"acdc-cardinal-v1-">>), list_to_tuple(tuple_to_list(Row) ++ [unexpected])]).

cardinal_model_provenance_and_base_metadata_fail_closed_test() ->
    [Base | _] = fixture_assets(<<"he-il">>),
    Row = resolved_row(Base, <<"gemini-3.1-flash-tts-preview">>, <<"separate_model_trial">>), Doc = doc(Row),
    lists:foreach(fun({Object, Key, Value}) ->
        Modified = set(Object, set(Key, Value, get(Object, Doc)), Doc),
        ?assertNot(acdc_gemini_prompts:verified_cardinal_asset(Row, {ok, Modified}))
    end, [{<<"source_voice">>, <<"model">>, <<"gemini-2.5-pro-preview-tts">>},
          {<<"source_voice">>, <<"voice">>, <<"Kore">>},
          {<<"source_cardinal_resolution">>, <<"model">>, <<"gemini-2.5-pro-preview-tts">>},
          {<<"source_cardinal_resolution">>, <<"source_kind">>, <<"generated_cardinal">>},
          {<<"source_cardinal_resolution">>, <<"provider">>, <<"other">>},
          {<<"source_cardinal_resolution">>, <<"voice">>, <<"Kore">>},
          {<<"source_cardinal_resolution">>, <<"transcript_sha256">>, <<"wrong">>},
          {<<"source_cardinal_resolution">>, <<"telephony_sha256">>, <<"wrong">>},
          {<<"source_cardinal_resolution">>, <<"owner">>, <<"other">>},
          {<<"source_cardinal_resolution">>, <<"runtime_ready">>, true},
          {<<"source_cardinal_resolution">>, <<"listening_verified">>, true}]),
    lists:foreach(fun(Object) ->
        ?assertNot(acdc_gemini_prompts:verified_cardinal_asset(Row, {ok, set(Object, undefined, Doc)})),
        {Props} = get(Object, Doc),
        Duplicate = {[{<<"model">>, element(8, Row)} | Props]},
        ?assertNot(acdc_gemini_prompts:verified_cardinal_asset(Row, {ok, set(Object, Duplicate, Doc)}))
    end, [<<"source_voice">>, <<"source_cardinal_resolution">>]),
    lists:foreach(fun({Key, Value}) ->
        ?assertNot(acdc_gemini_prompts:verified_cardinal_asset(Row, {ok, set(Key, Value, Doc)}))
    end, [{<<"_rev">>, <<"bad">>}, {<<"_deleted">>, true}, {<<"pvt_deleted">>, true},
          {<<"source_type">>, <<"customer">>}, {<<"content_length">>, 1},
          {<<"streamable">>, false}, {<<"_attachments">>, {[]}}]),
    ?assertNot(acdc_gemini_prompts:verified_cardinal_asset(Row, {error, not_found})).

exact_spanish_alias_source_identity_test() ->
    lists:foreach(fun(Number) ->
        Canonical = <<"acdc-cardinal-v1-number-", Number/binary>>,
        [Base] = [A || A <- fixture_assets(<<"es-es">>), element(2, A) =:= Canonical],
        Row = resolved_row(Base, <<"gemini-2.5-pro-preview-tts">>, <<"reused_supplemental_master">>),
        Doc = doc(Row), Resolution = get(<<"source_cardinal_resolution">>, Doc),
        ?assert(acdc_gemini_prompts:verified_cardinal_asset(Row, {ok, Doc})),
        lists:foreach(fun({Key, Value}) ->
            ?assertNot(acdc_gemini_prompts:verified_cardinal_asset(Row,
                {ok, set(<<"source_cardinal_resolution">>, set(Key, Value, Resolution), Doc)}))
        end, [{<<"source_locale">>, <<"fr-fr">>}, {<<"source_id">>, <<"acdc-number-5">>}]),
        lists:foreach(fun(Changed) ->
            ?assertNot(acdc_gemini_prompts:verified_cardinal_asset(Changed, {ok, doc(Changed)}))
        end, [setelement(1, Row, <<"ar-sa">>), setelement(2, Row, <<"acdc-cardinal-v1-number-5">>)])
    end, [<<"4">>, <<"9">>]).

resolved_nine_field_locale_preflight_test() ->
    lists:foreach(fun(Language) ->
        [First | Rest] = Rows = resolved_fixture_assets(Language),
        {ok, Audio} = acdc_cardinal_media:prepare_with(Language, ?ACCOUNT, [], Rows,
            fixture_read(Rows), fun fixture_frame/3),
        ?assert(acdc_cardinal_media:playlist(999999999, Language, Audio) =/= []),
        lists:foreach(fun(BadRows) ->
            ?assertEqual({error, cardinal_media_unavailable}, acdc_cardinal_media:prepare_with(Language,
                ?ACCOUNT, [], BadRows, fixture_read(Rows), fun fixture_frame/3))
        end, [Rest, [First | Rows], [setelement(8, First, <<"foreign">>) | Rest],
              [list_to_tuple(lists:sublist(tuple_to_list(First), 8)) | Rest]]),
        ?assertEqual({error, cardinal_media_unavailable}, acdc_cardinal_media:prepare_with(Language,
            ?ACCOUNT, [], Rows, fun(Id) ->
                Read = fixture_read(Rows), {ok, D} = Read(Id),
                {ok, set(<<"source_cardinal_resolution">>, undefined, D)}
            end, fun fixture_frame/3))
    end, [<<"es-es">>, <<"fr-fr">>, <<"he-il">>, <<"ar-sa">>]).

uniform_schema_required_before_frame_or_document_reads_test() ->
    Language = <<"es-es">>, Rows = resolved_fixture_assets(Language),
    %% This alias is genuinely2.5, so dropping its two admission columns would
    %% have passed the old seven-tuple verifier. Mixed schema must reject first.
    [Alias] = [A || A <- Rows, element(2, A) =:= <<"acdc-cardinal-v1-number-4">>],
    Rest = [A || A <- Rows, A =/= Alias],
    LegacyAlias = list_to_tuple(lists:sublist(tuple_to_list(Alias), 7)),
    lists:foreach(fun(BadRows) ->
        Ref = make_ref(),
        ?assertEqual({error, cardinal_media_unavailable},
            acdc_cardinal_media:prepare_with(Language, ?ACCOUNT, [], BadRows,
                fun(_) -> self() ! {Ref, unexpected_read}, error(must_not_read) end,
                fun(_, _, _) -> self() ! {Ref, unexpected_frame}, error(must_not_frame) end)),
        receive {Ref, _} -> ?assert(false) after 0 -> ok end
    end, [[LegacyAlias | Rest], [Alias | fixture_assets(Language)],
          [list_to_tuple(lists:sublist(tuple_to_list(Alias), 8)) | Rest],
          [{Language} | Rest], [malformed_row | Rest], []]).

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
        acdc_cardinal_media:prepare_with(<<"de-de">>, ?ACCOUNT, [], assets(),
            fun(_) -> error(must_not_read) end, fun frame/3)).

%% These tuples/documents are synthetic test metadata, not new release maps or
%% audio. Inventory and intro pins come from the independent JS authoring source
%% exported by the focused test launcher into its retained private directory.
source_inventory() ->
    {ok, [Rows]} = file:consult(os:getenv("ACDC_CARDINAL_MEDIA_INVENTORY")),
    Rows.

fixture_assets(Language) ->
    {Language, Roles, _} = lists:keyfind(Language, 1, source_inventory()),
    [{Language, Role, <<Role/binary, "-synthetic-fixture">>, binary:copy(<<"0">>, 64),
      <<"md5-AAAAAAAAAAAAAAAAAAAAAA==">>, 16000, binary:copy(<<"1">>, 64)} || Role <- Roles].

fixture_intro(Language) ->
    {Language, _, {Canonical, Transcript, Sha}} = lists:keyfind(Language, 1, source_inventory()),
    Short = binary:part(Sha, 0, 16),
    {Language, Canonical, <<Canonical/binary, "-gemini-sulafat-", Short/binary>>,
     Sha, <<"md5-AAAAAAAAAAAAAAAAAAAAAA==">>, 16000, Transcript}.

fixture_read(Assets) ->
    fun(Id) ->
        [Asset] = [A || A <- Assets, id(A) =:= Id],
        {ok, doc(Asset)}
    end.

fixture_frame(Language, _, _) ->
    {ok, [{play, <<"/system_media/", Language/binary, "/synthetic-approved-intro">>}], []}.

five_locale_inventory_and_full_cardinal_playlists_test() ->
    lists:foreach(fun({Language, Count, Maximum}) ->
        Assets = fixture_assets(Language),
        {Language, AuthoringRoles, Intro} = lists:keyfind(Language, 1, source_inventory()),
        ?assertEqual(Count, length(Assets)),
        ?assertEqual(lists:sort(AuthoringRoles), acdc_cardinal_media:expected_roles(Language)),
        ?assertEqual(Intro, acdc_cardinal_media:intro(Language)),
        {ok, Audio} = acdc_cardinal_media:prepare_with(Language, ?ACCOUNT, [],
            Assets, fixture_read(Assets), fun fixture_frame/3),
        OtherLanguage = case Language of <<"en-us">> -> <<"he-il">>; _ -> <<"en-us">> end,
        ?assertMatch({ok, _}, acdc_cardinal_media:prepare_with(Language, ?ACCOUNT, [],
            Assets ++ fixture_assets(OtherLanguage), fixture_read(Assets), fun fixture_frame/3)),
        Paths = maps:from_list([{element(2, A), <<"/system_media/", Language/binary, "/", (element(3, A))/binary>>}
                               || A <- Assets]),
        {ok, Before, []} = fixture_frame(Language, ?ACCOUNT, []),
        lists:foreach(fun(Number) ->
            {ok, Roles} = acdc_cardinal_prompts:roles(Number, Language),
            ?assertEqual(Before ++ [{play, maps:get(Role, Paths)} || Role <- Roles],
                acdc_cardinal_media:playlist(Number, Language, Audio))
        end, [1, 11, 12, 21, 71, 80, 81, 101, 102, 120, 121, 1000, 2000, 12000,
              21000, 101000, 200356, 1001001, 1021000, 121121121, 999999999]),
        ?assertEqual(Maximum + 1, length(acdc_cardinal_media:playlist(999999999, Language, Audio))),
        ?assertEqual([], acdc_cardinal_media:playlist(1, <<"de-de">>, Audio)),
        {ok, [One]} = acdc_cardinal_prompts:roles(1, Language),
        ForeignPaths = Paths#{One => <<"/system_media/de-de/foreign-number">>},
        ?assertEqual([], acdc_cardinal_media:playlist(1, Language, Audio#{assets := ForeignPaths})),
        ?assertEqual([], acdc_cardinal_media:playlist(1, Language, Audio#{assets := invalid})),
        ?assertEqual([], acdc_cardinal_media:playlist(1, Language, Audio#{before_number := [{say, <<"1">>}]}))
    end, [{<<"en-us">>, 31, 14}, {<<"es-es">>, 53, 14}, {<<"fr-fr">>, 161, 8},
          {<<"he-il">>, 131, 11}, {<<"ar-sa">>, 208, 9}]).

five_locale_missing_extra_duplicate_wrong_locale_fail_before_reads_test() ->
    lists:foreach(fun({Language, _, _}) ->
        [First | Rest] = Assets = fixture_assets(Language),
        WrongLanguage = case Language of <<"en-us">> -> <<"he-il">>; _ -> <<"en-us">> end,
        Extra = setelement(2, First, <<"acdc-cardinal-v1-unapproved-extra">>),
        lists:foreach(fun(Items) ->
            Ref = make_ref(),
            ?assertEqual({error, cardinal_media_unavailable},
                acdc_cardinal_media:prepare_with(Language, ?ACCOUNT, [], Items,
                    fun(_) -> self() ! {Ref, unexpected}, error(must_not_read) end,
                    fun(_, _, _) -> self() ! {Ref, unexpected}, error(must_not_frame) end)),
            receive {Ref, unexpected} -> ?assert(false) after 0 -> ok end
        end, [Rest, [First | Assets], [Extra | Assets], [Extra | Rest],
              [setelement(1, First, WrongLanguage) | Rest]]),
        lists:foreach(fun(Read) ->
            ?assertEqual({error, cardinal_media_unavailable},
                acdc_cardinal_media:prepare_with(Language, ?ACCOUNT, [], Assets, Read, fun fixture_frame/3))
        end, [fun(_) -> {error, not_found} end,
              fun(_) -> {ok, doc(setelement(1, First, WrongLanguage))} end,
              fun(_) -> {ok, doc(setelement(7, First, <<"wrong-transcript">>))} end,
              fun(_) -> error(read_failed) end])
    end, source_inventory()),
    lists:foreach(fun(Language) ->
        ?assertEqual({error, unsupported_language},
            acdc_cardinal_media:prepare_with(Language, ?ACCOUNT, [], [],
                fun(_) -> error(must_not_read) end, fun(_, _, _) -> error(must_not_frame) end))
    end, [undefined, <<"EN_US">>, <<"he">>, <<"ar">>, <<"de-de">>, [<<"he-il">>]]).

english_map_alone_cannot_claim_other_locales_test() ->
    lists:foreach(fun(Language) ->
        Ref = make_ref(),
        ?assertEqual({error, cardinal_media_unavailable},
            acdc_cardinal_media:prepare_with(Language, ?ACCOUNT, [], assets(),
                fun(_) -> self() ! {Ref, unexpected}, error(must_not_read) end,
                fun(_, _, _) -> self() ! {Ref, unexpected}, error(must_not_frame) end)),
        receive {Ref, unexpected} -> ?assert(false) after 0 -> ok end
    end, [<<"es-es">>, <<"fr-fr">>, <<"he-il">>, <<"ar-sa">>]).

actual_compiled_five_locale_maps_and_cardinal_intros_test_() ->
    {timeout, 30, fun() ->
        Rows = acdc_cardinal_media:compiled_assets(),
        Intros = acdc_cardinal_media:intro_assets(),
        ?assertEqual(584, length(Rows)),
        ?assertEqual(212, length(Intros)),
        ?assertEqual(584, length(lists:usort([id(A) || A <- Rows]))),
        ?assertEqual(212, length(lists:usort([id(A) || A <- Intros]))),
        ?assertEqual(assets(), [A || A <- Rows, element(1, A) =:= ?LANG]),
        ok = meck:new(kz_datamgr, [passthrough, no_link]),
        ok = meck:new(acdc_gemini_prompts, [passthrough, no_link]),
        try
            meck:expect(kz_datamgr, open_cache_doc,
                fun(<<"system_media">>, Id) -> Read = fixture_read(Rows ++ Intros), Read(Id) end),
            meck:expect(acdc_gemini_prompts, default_alias,
                fun(_, Canonical, _, _, absent) -> {gemini, Canonical} end),
            meck:expect(acdc_gemini_prompts, default,
                fun(Canonical, Language, _, absent) ->
                    [Intro] = [A || A <- Intros, element(1, A) =:= Language, element(2, A) =:= Canonical],
                    case Language of
                        <<"he-il">> -> {error, unsupported_gemini_prompt};
                        <<"ar-sa">> -> {error, unsupported_gemini_prompt};
                        _ -> {gemini, element(3, Intro)}
                    end
                end),
            lists:foreach(fun({Language, Count}) ->
                Selected = [A || A <- Rows, element(1, A) =:= Language],
                ?assertEqual(Count, length(Selected)),
                Schema = case Language of ?LANG -> 7; _ -> 9 end,
                ?assert(lists:all(fun(A) -> tuple_size(A) =:= Schema end, Selected)),
                {Canonical, Transcript, Sha} = acdc_cardinal_media:intro(Language),
                [Intro] = [A || A <- Intros, element(1, A) =:= Language, element(2, A) =:= Canonical],
                ?assertEqual({Sha, Transcript}, {element(4, Intro), element(7, Intro)}),
                {ok, Audio} = acdc_cardinal_media:prepare(Language, ?ACCOUNT, []),
                Commands = acdc_cardinal_media:playlist(999999999, Language, Audio),
                ?assertEqual({play, <<"/system_media/", (id(Intro))/binary>>}, hd(Commands)),
                ?assert(lists:all(fun({play, _}) -> true; (_) -> false end, Commands))
            end, [{?LANG, 31}, {<<"he-il">>, 131}, {<<"fr-fr">>, 161},
                  {<<"es-es">>, 53}, {<<"ar-sa">>, 208}])
        after meck:unload(kz_datamgr), meck:unload(acdc_gemini_prompts) end
    end}.

malformed_or_foreign_frame_never_reaches_cardinal_reads_test() ->
    lists:foreach(fun({Before, After}) ->
        Ref = make_ref(),
        ?assertEqual({error, cardinal_media_unavailable},
            acdc_cardinal_media:prepare_with(?LANG, ?ACCOUNT, [], assets(),
                fun(_) -> self() ! {Ref, unexpected}, error(must_not_read) end,
                fun(_, _, _) -> {ok, Before, After} end)),
        receive {Ref, unexpected} -> ?assert(false) after 0 -> ok end
    end, [{[{say, <<"1">>, <<"number">>}], []},
          {[{play, <<"/system_media/he-il/foreign-intro">>}], []},
          {[{prompt, <<"custom">>, <<"he-il">>, <<"A">>}], []},
          {[{play, <<"/system_media/en-us/../foreign-intro">>}], []},
          {[], []}, {invalid, []}, {[{play, <<"/system_media/en-us/intro">>}], invalid}]).

five_locale_exact_intro_frame_verification_test_() ->
    {timeout, 30, fun() ->
        ok = meck:new(acdc_gemini_prompts, [passthrough, no_link]),
        try
            meck:expect(acdc_gemini_prompts, default_alias,
                fun(_, Canonical, _, _, absent) -> {gemini, Canonical};
                   (_, _, _, _, {configured, Value}) -> {custom, Value}
                end),
            meck:expect(acdc_gemini_prompts, default,
                fun(_, Language, _, absent) ->
                    case Language of
                        <<"he-il">> -> {error, unsupported_gemini_prompt};
                        <<"ar-sa">> -> {error, unsupported_gemini_prompt};
                        _ -> {gemini, element(3, fixture_intro(Language))}
                    end
                end),
            lists:foreach(fun({Language, _, _}) ->
                Intro = fixture_intro(Language), Read = fixture_read([Intro]),
                Expected = {ok, [{play, <<"/system_media/", Language/binary, "/", (element(3, Intro))/binary>>}], []},
                ?assertEqual(Expected, acdc_cardinal_media:frame_with(Language, ?ACCOUNT, [], [Intro], Read)),
                WrongLanguage = case Language of <<"en-us">> -> <<"he-il">>; _ -> <<"en-us">> end,
                BadSha = setelement(4, Intro, binary:copy(<<"f">>, 64)),
                lists:foreach(fun(Intros) ->
                    ?assertEqual({error, cardinal_media_unavailable},
                        acdc_cardinal_media:frame_with(Language, ?ACCOUNT, [], Intros, Read))
                end, [[], [Intro, Intro], [Intro, BadSha], [BadSha],
                      [setelement(1, Intro, WrongLanguage)],
                      [setelement(2, Intro, <<"acdc-queue-you_are_at_position">>)],
                      [setelement(7, Intro, <<"wrong-transcript">>)]]),
                lists:foreach(fun(BadRead) ->
                    ?assertEqual({error, cardinal_media_unavailable},
                        acdc_cardinal_media:frame_with(Language, ?ACCOUNT, [], [Intro], BadRead))
                end, [fun(_) -> {error, not_found} end, fun(_) -> {ok, {[]}} end,
                      fun(_) -> {ok, doc(setelement(4, Intro, <<"wrong-sha">>))} end,
                      fun(_) -> error(read_failed) end])
            end, source_inventory()),
            lists:foreach(fun(Decision) ->
                meck:expect(acdc_gemini_prompts, default, fun(_, _, _, absent) -> Decision end),
                lists:foreach(fun(Language) ->
                    Intro = fixture_intro(Language),
                    ?assertEqual({error, cardinal_media_unavailable},
                        acdc_cardinal_media:frame_with(Language, ?ACCOUNT, [], [Intro], fixture_read([Intro])))
                end, [<<"he-il">>, <<"ar-sa">>])
            end, [{error, account_override_unavailable}, {error, invalid_account},
                  {error, gemini_media_unavailable}, {gemini, <<"unapproved-version">>}]),
            meck:expect(acdc_gemini_prompts, default, fun(_, _, _, absent) -> {custom, <<"account-intro">>} end),
            lists:foreach(fun({Language, _, _}) ->
                Intro = fixture_intro(Language),
                ?assertEqual({ok, [{prompt, <<"account-intro">>, Language, <<"A">>}], []},
                    acdc_cardinal_media:frame_with(Language, ?ACCOUNT, [], [Intro], fun(_) -> error(must_not_read) end)),
                ?assertEqual({ok, [{prompt, <<"explicit-prefix">>, Language, <<"A">>}],
                                  [{prompt, <<"explicit-suffix">>, Language, <<"A">>}]},
                    acdc_cardinal_media:frame_with(Language, ?ACCOUNT,
                        [{<<"you_are_at_position">>, <<"explicit-prefix">>}, {<<"in_the_queue">>, <<"explicit-suffix">>}],
                        [], fun(_) -> error(must_not_read) end))
            end, source_inventory())
        after meck:unload(acdc_gemini_prompts) end
    end}.

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

five_locale_announcement_preflight_never_falls_back_test_() ->
    {timeout, 30, fun() ->
        ok = meck:new(acdc_cardinal_media, [passthrough, no_link]),
        try
            Media = [{<<"you_are_at_position">>, <<"account-prefix">>}],
            Config = acdc_announcements:get_config([
                {<<"position_announcements_enabled">>, true}, {<<"wait_time_announcements_enabled">>, true},
                {<<"interval">>, 60}, {<<"initial_delay">>, 12}, {<<"media">>, Media},
                {<<"callback">>, [{<<"enabled">>, true}, {<<"announcement">>,
                    [{<<"initial_delay">>, 30}, {<<"interval">>, 45}]}]}]),
            ?assertEqual(false, maps:get(position_announcements_enabled, acdc_announcements:get_config([]))),
            lists:foreach(fun({Language, _, _}) ->
                Call = kapps_call:set_language(Language, kapps_call:set_account_id(?ACCOUNT, kapps_call:new())),
                Rows = case Language of ?LANG -> fixture_assets(Language); _ -> resolved_fixture_assets(Language) end,
                {ok, Audio} = acdc_cardinal_media:prepare_with(Language, ?ACCOUNT, [], Rows,
                    fixture_read(Rows), fun fixture_frame/3),
                meck:expect(acdc_cardinal_media, prepare, fun(ActualLanguage, ?ACCOUNT, ActualMedia) ->
                    ?assertEqual(Language, ActualLanguage), ?assertEqual(Media, ActualMedia), {ok, Audio}
                end),
                Ready = acdc_announcements:resolve_position_audio(Config, Call),
                ?assertEqual(Config, maps:remove(position_audio, Ready)),
                ?assertEqual(#{position => 12100, callback => 30100}, acdc_announcements:schedule_init(Ready, 100)),
                lists:foreach(fun(Number) ->
                    Expected = acdc_cardinal_media:playlist(Number, Language, Audio),
                    ?assert(Expected =/= []),
                    ?assertEqual(Expected, acdc_announcements:position_prompts(Number, Language, Ready)),
                    ?assert(lists:all(fun({play, _}) -> true; (_) -> false end, Expected))
                end, [1, 21, 101, 12000, 999999999]),
                lists:foreach(fun(Result) ->
                    meck:expect(acdc_cardinal_media, prepare, fun(_, _, _) ->
                        case Result of exception -> error(unavailable); _ -> Result end
                    end),
                    Missing = acdc_announcements:resolve_position_audio(Config, Call),
                    ?assertEqual(Config#{position_announcements_enabled := false, position_audio => undefined}, Missing),
                    %% Wait-time announcements keep their shared position clock
                    %% even though the missing cardinal number is disabled.
                    ?assertEqual(#{position => 12100, callback => 30100}, acdc_announcements:schedule_init(Missing, 100)),
                    ?assertEqual([], acdc_announcements:position_prompts(21, Language, Missing))
                end, [{error, unavailable}, exception]),
                ?assertEqual([], acdc_announcements:position_prompts(21, Language, Config)),
                meck:expect(acdc_cardinal_media, prepare, fun(_, _, _) -> error(must_not_prepare_disabled) end),
                Disabled = Config#{position_announcements_enabled := false},
                ?assertEqual(Disabled, acdc_announcements:resolve_position_audio(Disabled, Call))
            end, source_inventory()),
            lists:foreach(fun(Language) ->
                Call = kapps_call:set_language(Language, kapps_call:new()),
                ?assertEqual(Config#{position_announcements_enabled := false, position_audio => undefined},
                    acdc_announcements:resolve_position_audio(Config, Call)),
                ?assertEqual([], acdc_announcements:position_prompts(21, Language, Config))
            end, [<<"de-de">>, <<"fr-ca">>, <<"es-us">>])
        after meck:unload(acdc_cardinal_media) end
    end}.
