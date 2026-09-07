%%% Synthetic document/evidence fixtures only; no audio/native-review claim.
-module(acdc_cardinal_capabilities_tests).
-include_lib("eunit/include/eunit.hrl").
-include("acdc_cardinal_map.hrl").
-include("acdc_gemini_map.hrl").
-include("cardinal_maps/acdc_cardinal_he-il.hrl").
-include("cardinal_maps/acdc_cardinal_fr-fr.hrl").
-include("cardinal_maps/acdc_cardinal_es-es.hrl").
-include("cardinal_maps/acdc_cardinal_ar-sa.hrl").

j(P) -> kz_json:from_list(P).
locales() -> [<<"en-us">>, <<"he-il">>, <<"fr-fr">>, <<"es-es">>, <<"ar-sa">>].
pin() -> binary:copy(<<"a">>, 64).
all_assets() -> ?GEMINI_ASSETS ++ ?CARDINAL_ASSETS ++ ?CARDINAL_HE_ASSETS ++ ?CARDINAL_FR_ASSETS
    ++ ?CARDINAL_ES_ASSETS ++ ?CARDINAL_AR_ASSETS ++ [?CARDINAL_HE_INTRO_ASSET, ?CARDINAL_AR_INTRO_ASSET].
id(A) -> <<(element(1, A))/binary, "/", (element(3, A))/binary>>.
map_pin(<<"en-us">>) -> ?CARDINAL_MAP_SHA256;
map_pin(<<"he-il">>) -> ?CARDINAL_HE_MAP_SHA256;
map_pin(<<"fr-fr">>) -> ?CARDINAL_FR_MAP_SHA256;
map_pin(<<"es-es">>) -> ?CARDINAL_ES_MAP_SHA256;
map_pin(<<"ar-sa">>) -> ?CARDINAL_AR_MAP_SHA256.
count(<<"en-us">>) -> 31;
count(<<"he-il">>) -> 131;
count(<<"fr-fr">>) -> 161;
count(<<"es-es">>) -> 53;
count(<<"ar-sa">>) -> 208.
entry(L, Stage) ->
    Installed = Stage =/= source, Runtime = Stage =:= runtime orelse Stage =:= reviewed, Reviewed = Stage =:= reviewed,
    j([{<<"ready">>, Runtime andalso Reviewed}, {<<"selection_ready">>, Runtime}, {<<"position">>, Runtime},
       {<<"callback">>, Runtime}, {<<"wait_time">>, Runtime}, {<<"native_speaker_review">>, Reviewed},
       {<<"position_installed_verified">>, Installed}, {<<"callback_installed_verified">>, Installed},
       {<<"position_runtime_verified">>, Runtime}, {<<"callback_runtime_verified">>, Runtime},
       {<<"wait_time_runtime_verified">>, Runtime}, {<<"numbers">>, <<"prerecorded-cardinal">>},
       {<<"number_range">>, [0, 999999999]}, {<<"numeric_prompt_count">>, count(L)}, {<<"callback_prompt_count">>, 42},
       {<<"source_catalog_sha256">>, ?CARDINAL_CATALOG_SHA256}, {<<"cardinal_map_sha256">>, map_pin(L)},
       {<<"fixed_map_sha256">>, ?GEMINI_MAP_SHA256},
       {<<"installed_media_sha256">>, case Installed of true -> pin(); false -> null end},
       {<<"runtime_evidence_sha256">>, case Runtime of true -> pin(); false -> null end},
       {<<"native_review_sha256">>, case Reviewed of true -> pin(); false -> null end}]).
manifest(Stage) -> j([{<<"schema_version">>, 2}, {<<"backend_mode">>, <<"prerecorded-cardinal-v1">>},
    {<<"generated_at">>, <<"2026-09-07T12:00:00Z">>}, {<<"languages">>, j([{L, entry(L, Stage)} || L <- locales()])}]).
catalog(M, Media) -> j([{<<"language_capabilities">>, M}, {<<"system_media">>, Media},
    {<<"catalogs">>, j([{<<"system_media">>, j([{<<"complete">>, true}])}])}]).

fixture_doc(A) when tuple_size(A) =:= 9 ->
    L = element(1, A), C = element(2, A), Model = element(8, A),
    Base = fixture_doc(list_to_tuple(lists:sublist(tuple_to_list(A), 7))),
    SourceId = case C of <<"acdc-cardinal-v1-number-4">> -> <<"acdc-number-4">>;
        <<"acdc-cardinal-v1-number-9">> -> <<"acdc-number-9">>; _ -> undefined end,
    kz_json:set_values([{[<<"source_voice">>, <<"model">>], Model},
        {<<"source_cardinal_resolution">>, j([{<<"schema_version">>, 1}, {<<"owner">>, <<"kazoo5-acdc-cardinal-import">>},
            {<<"provider">>, <<"google-gemini">>}, {<<"model">>, Model}, {<<"voice">>, <<"Sulafat">>},
            {<<"source_kind">>, element(9, A)}, {<<"transcript_sha256">>, element(7, A)},
            {<<"telephony_sha256">>, element(4, A)}, {<<"source_locale">>, L}, {<<"source_id">>, SourceId},
            {<<"runtime_ready">>, false}, {<<"listening_verified">>, false}, {<<"provider_provenance_authenticated">>, false}])}], Base);
fixture_doc({L,C,P,S,M,N,T} = A) ->
    j([{<<"_id">>, id(A)}, {<<"_rev">>, <<"1-abc">>}, {<<"pvt_type">>, <<"media">>},
       {<<"pvt_account_db">>, <<"system_media">>}, {<<"source_type">>, <<"kazoo5_acdc_gemini_voice_installer">>},
       {<<"prompt_id">>, P}, {<<"language">>, L}, {<<"content_type">>, <<"audio/wav">>},
       {<<"content_length">>, N}, {<<"streamable">>, true},
       {<<"source_voice">>, j([{<<"provider">>, <<"google-gemini">>}, {<<"model">>, <<"gemini-2.5-pro-preview-tts">>},
           {<<"voice">>, <<"Sulafat">>}, {<<"canonical_prompt_id">>, C}, {<<"sha256">>, S}, {<<"transcript_sha256">>, T}])},
       {<<"_attachments">>, j([{<<P/binary, ".wav">>, j([{<<"content_type">>, <<"audio/wav">>},
           {<<"length">>, N}, {<<"digest">>, M}])}])}]).

expect_bulk(Languages, Change) ->
    Assets = [A || A <- all_assets(), lists:member(element(1, A), Languages)],
    Expected = lists:sort([id(A) || A <- Assets]),
    meck:expect(kz_datamgr, open_docs, fun(<<"system_media">>, Ids) ->
        ?assertEqual(Expected, lists:sort(Ids)), ?assert(length(Ids) =< 796),
        {ok, [begin [A] = [X || X <- Assets, id(X) =:= Id],
                    case Change(A, fixture_doc(A)) of
                        missing -> j([{<<"key">>, Id}, {<<"error">>, <<"not_found">>}]);
                        Doc -> j([{<<"key">>, Id}, {<<"doc">>, Doc}])
                    end
              end || Id <- Ids]}
    end),
    meck:expect(kz_datamgr, open_doc, fun(_, _) -> error(no_per_document_reads) end),
    meck:expect(kz_datamgr, open_cache_doc, fun(_, _) -> error(no_per_document_reads) end).

strict_version_and_evidence_contract_test() ->
    lists:foreach(fun(Stage) -> ?assert(cb_acdc_queue_editor:valid_manifest(manifest(Stage))) end,
        [source, installed, runtime, reviewed]),
    M = manifest(runtime), E = kz_json:get_json_value([<<"languages">>, <<"en-us">>], M),
    lists:foreach(fun({Key, Value}) ->
        Bad = kz_json:set_value([<<"languages">>, <<"en-us">>, Key], Value, M),
        ?assertNot(cb_acdc_queue_editor:valid_manifest(Bad))
    end, [{<<"ready">>, true}, {<<"selection_ready">>, false}, {<<"native_speaker_review">>, true},
          {<<"native_review_sha256">>, pin()}, {<<"installed_media_sha256">>, null},
          {<<"runtime_evidence_sha256">>, null}, {<<"position_runtime_verified">>, <<"true">>},
          {<<"numbers">>, <<"native_say">>}, {<<"numeric_prompt_count">>, 2999}, {<<"callback_prompt_count">>, 32},
          {<<"cardinal_map_sha256">>, pin()}, {<<"fixed_map_sha256">>, pin()}, {<<"source_catalog_sha256">>, pin()},
          {<<"private_extra">>, true}]),
    lists:foreach(fun(Key) -> ?assertNot(cb_acdc_queue_editor:valid_manifest(
        kz_json:delete_key([<<"languages">>, <<"en-us">>, Key], M))) end, kz_json:get_keys(E)),
    {Props} = E,
    ?assertNot(cb_acdc_queue_editor:valid_manifest(kz_json:set_value([<<"languages">>, <<"en-us">>],
        {[{<<"ready">>, false} | Props]}, M))),
    ?assertNot(cb_acdc_queue_editor:valid_manifest(kz_json:set_value([<<"languages">>, <<"de-de">>], E, M))).

scoped_bulk_runtime_admission_and_fail_closed_test_() ->
    {timeout, 60, fun() ->
        ok = meck:new(kz_datamgr, [passthrough, no_link]),
        try
            meck:expect(kz_datamgr, open_docs, fun(_, _) -> error(no_source_or_install_only_reads) end),
            lists:foreach(fun(Stage) -> M = manifest(Stage),
                ?assertEqual({M, []}, cb_acdc_queue_editor:verified_manifest_media(M)),
                ?assertNot(cb_acdc_queue_editor:language_selection_ready(<<"en-us">>, catalog(M, [])))
            end, [source, installed]),
            ?assertEqual(0, meck:num_calls(kz_datamgr, open_docs, '_')),
            lists:foreach(fun(L) ->
                expect_bulk([L], fun(_, D) -> D end),
                M = kz_json:set_value([<<"languages">>, L], entry(L, runtime), manifest(installed)),
                Before = meck:num_calls(kz_datamgr, open_docs, '_'),
                {Verified, Media} = cb_acdc_queue_editor:verified_manifest_media(M),
                ?assertEqual(Before + 1, meck:num_calls(kz_datamgr, open_docs, '_')),
                ?assertEqual(M, Verified), ?assertEqual(42, length(Media)),
                ?assert(cb_acdc_queue_editor:language_selection_ready(L, catalog(Verified, Media))),
                ?assertEqual(false, kz_json:get_value([<<"languages">>, L, <<"ready">>], Verified)),
                ?assertEqual(null, kz_json:get_value([<<"languages">>, L, <<"native_review_sha256">>], Verified)),
                lists:foreach(fun(Other) -> ?assertNot(cb_acdc_queue_editor:language_selection_ready(Other,
                    catalog(Verified, Media))) end, locales() -- [L]),
                ?assertNot(cb_acdc_queue_editor:language_selection_ready(L, catalog(Verified, tl(Media)))),
                expect_bulk([L], fun(A, D) -> case element(2, A) of
                    <<"acdc-cardinal-v1-", _/binary>> -> missing; _ -> D end end),
                {Missing, Fixed} = cb_acdc_queue_editor:verified_manifest_media(M),
                ?assert(cb_acdc_queue_editor:valid_manifest(Missing)),
                ?assertEqual(42, length(Fixed)),
                ?assertEqual(false, kz_json:get_value([<<"languages">>, L, <<"position">>], Missing)),
                ?assertEqual(true, kz_json:get_value([<<"languages">>, L, <<"callback">>], Missing)),
                ?assertEqual(true, kz_json:get_value([<<"languages">>, L, <<"position_installed_verified">>], Missing)),
                ?assertNot(cb_acdc_queue_editor:language_selection_ready(L, catalog(Missing, Fixed)))
            end, locales()),
            expect_bulk(locales(), fun(_, D) -> D end),
            {All, Media} = cb_acdc_queue_editor:verified_manifest_media(manifest(runtime)),
            ?assertEqual(210, length(Media)),
            lists:foreach(fun(L) -> ?assert(cb_acdc_queue_editor:language_selection_ready(L, catalog(All, Media))) end, locales()),
            [Trial | _] = [A || A <- ?CARDINAL_HE_ASSETS, element(8, A) =:= <<"gemini-3.1-flash-tts-preview">>],
            lists:foreach(fun(Change) ->
                expect_bulk([<<"he-il">>], Change),
                M = kz_json:set_value([<<"languages">>, <<"he-il">>], entry(<<"he-il">>, runtime), manifest(installed)),
                {Bad, Remaining} = cb_acdc_queue_editor:verified_manifest_media(M),
                ?assertNot(cb_acdc_queue_editor:language_selection_ready(<<"he-il">>, catalog(Bad, Remaining)))
            end, [fun(A, D) -> case A =:= Trial of true -> kz_json:set_value([<<"source_voice">>, <<"model">>],
                        <<"gemini-2.5-pro-preview-tts">>, D); false -> D end end,
                  fun(A, D) -> case A =:= ?CARDINAL_HE_INTRO_ASSET of true -> missing; false -> D end end,
                  fun(A, D) -> case element(2, A) of <<"acdc-number-0">> -> missing; _ -> D end end]),
            meck:expect(kz_datamgr, open_docs, fun(_, _) -> {ok, []} end),
            ?assertError({badmatch, false}, cb_acdc_queue_editor:verified_manifest_media(manifest(runtime)))
        after meck:unload(kz_datamgr) end
    end}.
