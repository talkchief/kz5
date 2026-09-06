-module(acdc_gemini_prompts_tests).
-export([read/1,doc/1]).
-include_lib("eunit/include/eunit.hrl").
-include("acdc_gemini_map.hrl").
-define(ACCOUNT, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(PROMPT, <<"acdc-callback-success">>).

auxiliary_defaults_are_exact_system_documents_test() ->
    lists:foreach(fun(Language) ->
        lists:foreach(fun({Name,Canonical}) ->
            %% Synthetic supplemental entries exercise resolver plumbing only;
            %% they are not generated/imported assets or readiness evidence.
            Base = acdc_gemini_prompts:asset(Language, ?PROMPT),
            Id = <<Canonical/binary,"-gemini-sulafat-0123456789abcdef">>,
            Asset = setelement(3, setelement(2, Base, Canonical), Id),
            Lookup = fun(L,P) -> ?assertEqual(Language,L), ?assertEqual(Canonical,P), Asset end,
            Read = fun(MediaId) ->
                ?assertEqual(<<Language/binary,"/",Id/binary>>, MediaId), {ok,doc(Asset)}
            end,
            ?assertEqual({ok,<<"/system_media/",Language/binary,"/",Id/binary>>},
                acdc_gemini_prompts:auxiliary_with(Name,Language,Lookup,Read)),
            ?assertEqual({error,gemini_media_unavailable},
                acdc_gemini_prompts:auxiliary_with(Name,Language,Lookup,fun(_) -> {error,not_found} end)),
            Wrong = set(<<"language">>,<<"wrong">>,doc(Asset)),
            ?assertEqual({error,gemini_media_unavailable},
                acdc_gemini_prompts:auxiliary_with(Name,Language,Lookup,fun(_) -> {ok,Wrong} end))
        end, [{unavailable,<<"acdc-callback-unavailable">>},
              {invalid_entry,<<"acdc-callback-invalid-entry">>},
              {enter_number,<<"acdc-callback-enter-number">>}])
    end,[<<"en-us">>,<<"he-il">>,<<"fr-fr">>,<<"es-es">>,<<"ar-sa">>]).

auxiliary_missing_map_and_unsupported_inputs_never_fall_back_test() ->
    NoRead = fun(_) -> error(unexpected_media_read) end,
    NoLookup = fun(_,_) -> error(unexpected_lookup) end,
    ?assertEqual({error,unsupported_gemini_prompt},
        acdc_gemini_prompts:auxiliary_with(unavailable,<<"en-us">>,fun(_,_) -> undefined end,NoRead)),
    ?assertEqual({error,unsupported_gemini_auxiliary},
        acdc_gemini_prompts:auxiliary_with(unavailable,<<"fr-ca">>,NoLookup,NoRead)),
    ?assertEqual({error,unsupported_gemini_auxiliary},
        acdc_gemini_prompts:auxiliary_with(unknown,<<"en-us">>,NoLookup,NoRead)).

all_210_exact_assets_verify_test() ->
    ?assertEqual(210,length(?GEMINI_ASSETS)),
    lists:foreach(fun(A) ->
        ?assert(acdc_gemini_prompts:imported(A,{ok,doc(A)})),
        ?assertEqual(A,acdc_gemini_prompts:asset(element(1,A),element(2,A)))
    end,?GEMINI_ASSETS).

fixed_editor_projection_requires_expanded_inventory_test() ->
    lists:foreach(fun(Language) ->
        Ids = acdc_gemini_prompts:fixed_media_ids(Language),
        ?assertEqual(32, length(Ids)),
        Docs = [begin {ok,Doc}=read(Id), Doc end || Id <- Ids],
        Media = acdc_gemini_prompts:verified_fixed_media(Language, Docs),
        ?assertEqual(32, length(Media)),
        ?assert(acdc_gemini_prompts:fixed_media_complete(Language, Media)),
        ?assertNot(acdc_gemini_prompts:fixed_media_complete(Language, lists:sublist(Media,29))),
        lists:foreach(fun(Missing) ->
            ?assertNot(acdc_gemini_prompts:fixed_media_complete(Language, lists:delete(Missing,Media)))
        end,Media),
        [First|Rest] = Media,
        Tampered = set(<<"sha256">>, <<"wrong">>, First),
        ?assertNot(acdc_gemini_prompts:fixed_media_complete(Language,[Tampered|Rest]))
    end,[<<"en-us">>,<<"he-il">>,<<"fr-fr">>,<<"es-es">>,<<"ar-sa">>]),
    ?assertNot(acdc_gemini_prompts:fixed_media_complete(<<"unsupported">>, [])).

fixed_defaults_are_localized_and_immutable_test() ->
    lists:foreach(fun(L) ->
        A=acdc_gemini_prompts:asset(L,?PROMPT),
        ?assertEqual({gemini,element(3,A)}, resolve(L,absent,none,fun read/1))
    end,[<<"en-us">>,<<"ar-sa">>,<<"he-il">>,<<"fr-fr">>,<<"es-es">>]),
    ?assertEqual(resolve(<<"he-il">>,absent,none,fun read/1),resolve(<<"HE_IL">>,absent,none,fun read/1)),
    ?assertMatch({gemini,_},resolve(undefined,absent,none,fun read/1)),
    ?assertEqual({error,unsupported_gemini_prompt},resolve(<<"fr-ca">>,absent,none,fun read/1)),
    ?assertEqual({error,unsupported_gemini_prompt},
        acdc_gemini_prompts:default_with(<<"unknown">>,<<"en-us">>,?ACCOUNT,absent,fun(_,_) -> none end,fun read/1)).

callback_editor_projection_requires_every_digit_test() ->
    lists:foreach(fun(Language) ->
        Ids = acdc_gemini_prompts:callback_media_ids(Language),
        ?assertEqual(42,length(Ids)),
        Docs = [begin {ok,Doc}=read(Id), Doc end || Id <- Ids],
        Media = acdc_gemini_prompts:verified_callback_media(Language,Docs),
        ?assertEqual(42,length(Media)),
        ?assert(acdc_gemini_prompts:callback_media_complete(Language,Media)),
        Fixed = acdc_gemini_prompts:verified_fixed_media(Language,Docs),
        ?assert(acdc_gemini_prompts:fixed_media_complete(Language,Fixed)),
        ?assertNot(acdc_gemini_prompts:callback_media_complete(Language,Fixed)),
        lists:foreach(fun(Missing) ->
            ?assertNot(acdc_gemini_prompts:callback_media_complete(Language,lists:delete(Missing,Media)))
        end,Media)
    end,[<<"en-us">>,<<"he-il">>,<<"fr-fr">>,<<"es-es">>,<<"ar-sa">>]),
    ?assertNot(acdc_gemini_prompts:callback_media_complete(<<"unsupported">>,[])).

every_explicit_override_preserved_without_io_test() ->
    Fail=fun(_) -> error(unexpected_io) end,
    lists:foreach(fun(V) ->
        ?assertEqual({custom,V},acdc_gemini_prompts:default_with(?PROMPT,<<"xx">>,?ACCOUNT,{configured,V},Fail,Fail))
    end,[?PROMPT,<<"customer-media-id">>,<<"https://media.example/custom.wav">>,<<"prompt://custom/account">>]),
    lists:foreach(fun(V) ->
        ?assertEqual({error,invalid_explicit_media},resolve(<<"en-us">>,{configured,V},none,Fail))
    end,[undefined,null,<<>>,false,5,{[]}]).

account_overrides_preserved_and_unknown_fails_closed_test() ->
    Fail=fun(_) -> error(unexpected_io) end,
    ?assertEqual({custom,?PROMPT},resolve(<<"en-us">>,absent,custom,Fail)),
    lists:foreach(fun(State) ->
        ?assertEqual({error,account_override_unavailable},resolve(<<"en-us">>,absent,State,Fail))
    end,[unavailable,timeout,{error,not_found},undefined]),
    ?assertEqual({error,account_override_unavailable},acdc_gemini_prompts:default_with(?PROMPT,<<"en-us">>,?ACCOUNT,absent,fun(_,_) -> error(failure) end,Fail)),
    ?assertEqual({error,invalid_account},acdc_gemini_prompts:default_with(?PROMPT,<<"en-us">>,<<"wrong">>,absent,fun(_,_) -> none end,Fail)).

missing_or_unavailable_import_never_falls_back_test() ->
    lists:foreach(fun(Result) ->
        ?assertEqual({error,gemini_media_unavailable},resolve(<<"en-us">>,absent,none,fun(_) -> Result end))
    end,[{error,not_found},{error,timeout},{ok,{[]}},undefined]),
    ?assertEqual({error,gemini_media_unavailable},resolve(<<"en-us">>,absent,none,fun(_) -> error(db_down) end)).

foreign_or_mutated_metadata_rejected_test() ->
    A=acdc_gemini_prompts:asset(<<"en-us">>,?PROMPT),D=doc(A),
    lists:foreach(fun({K,V}) -> ?assertNot(acdc_gemini_prompts:imported(A,{ok,set(K,V,D)})) end,
        [{<<"_id">>,<<"wrong">>},{<<"_rev">>,<<"invalid">>},{<<"_deleted">>,true},{<<"pvt_deleted">>,true},
         {<<"pvt_type">>,<<"user">>},{<<"pvt_account_db">>,<<"account">>},{<<"source_type">>,<<"foreign">>},
         {<<"prompt_id">>,?PROMPT},{<<"language">>,<<"fr-fr">>},{<<"content_type">>,<<"audio/mp3">>},
         {<<"content_length">>,1},{<<"streamable">>,false}]),
    Voice=get(<<"source_voice">>,D),
    lists:foreach(fun(K) ->
        ?assertNot(acdc_gemini_prompts:imported(A,{ok,set(<<"source_voice">>,set(K,<<"wrong">>,Voice),D)}))
    end,[<<"provider">>,<<"model">>,<<"voice">>,<<"canonical_prompt_id">>,<<"sha256">>,<<"transcript_sha256">>]).

attachment_identity_and_digest_are_exact_test() ->
    A=acdc_gemini_prompts:asset(<<"ar-sa">>,?PROMPT),D=doc(A),
    {Attachments}=get(<<"_attachments">>,D),[{Name,Attachment}]=Attachments,
    lists:foreach(fun({K,V}) ->
        ?assertNot(acdc_gemini_prompts:imported(A,{ok,set(<<"_attachments">>,{[{Name,set(K,V,Attachment)}]},D)}))
    end,[{<<"content_type">>,<<"audio/mp3">>},{<<"length">>,0},{<<"digest">>,<<"md5-wrong">>}]),
    lists:foreach(fun(Att) -> ?assertNot(acdc_gemini_prompts:imported(A,{ok,set(<<"_attachments">>,Att,D)})) end,
        [{[]},{[{<<"wrong.wav">>,Attachment}]},{[{Name,Attachment},{<<"extra.wav">>,Attachment}]}]).

arabic_hebrew_digits_preserve_value_and_leading_zeroes_test() ->
    lists:foreach(fun(L) ->
        {ok,Prompts}=acdc_gemini_prompts:telephone_with(<<"0012080">>,L,?ACCOUNT,fun(_,_) -> none end,fun read/1),
        Expected=[element(3,acdc_gemini_prompts:asset(L,<<"acdc-number-",D>>)) || <<D>> <= <<"0012080">>],
        ?assertEqual(Expected,[P || {prompt,P,L0,<<"A">>} <- Prompts,L0=:=L]),
        ?assertEqual(7,length(Prompts)),
        {ok,Custom}=acdc_gemini_prompts:telephone_with(<<"10">>,L,?ACCOUNT,fun(_,<<"acdc-number-1">>) -> custom;(_,_) -> none end,fun read/1),
        ?assertMatch([{prompt,<<"acdc-number-1">>,_,_},{prompt,_,_,_}],Custom)
    end,[<<"ar-sa">>,<<"he-il">>]).

digit_missing_no_partial_audio_and_no_say_fallback_test() ->
    Read=fun(Id) -> case binary:match(Id,<<"acdc-number-2-">>) of nomatch -> read(Id); _ -> {error,not_found} end end,
    ?assertEqual({error,gemini_digits_unavailable},acdc_gemini_prompts:telephone_with(<<"120">>,<<"ar-sa">>,?ACCOUNT,fun(_,_) -> none end,Read)),
    lists:foreach(fun(L) -> ?assertEqual({error,unsupported_gemini_telephone},
        acdc_gemini_prompts:telephone_with(<<"123">>,L,?ACCOUNT,fun(_,_) -> none end,fun read/1))
    end,[<<"en-us">>,<<"fr-fr">>,<<"es-es">>,<<"de-de">>]),
    lists:foreach(fun(D) -> ?assertEqual({error,unsupported_gemini_telephone},
        acdc_gemini_prompts:telephone_with(D,<<"he-il">>,?ACCOUNT,fun(_,_) -> none end,fun read/1))
    end,[<<>>,<<"+123">>,<<"12;exec">>,<<"1234567890123456">>,undefined,123]).

capabilities_never_claim_full_language_or_position_readiness_test() ->
    lists:foreach(fun(L) ->
        C=acdc_gemini_prompts:capabilities_with(L,fun read/1),
        ?assertEqual(32,maps:get(source_fixed_count,C)),
        ?assert(maps:get(fixed_import_metadata_verified,C)),
        Recorded=lists:member(L,[<<"ar-sa">>,<<"he-il">>]),
        ?assert(maps:get(gemini_telephone_digits_import_metadata_verified,C)),
        ?assertEqual(not Recorded,maps:get(non_gemini_numeric_dependency,C)),
        lists:foreach(fun(K) -> ?assertNot(maps:get(K,C)) end,[position_available,callback_runtime_ready,full_language_ready,native_speaker_review]),
        Missing=acdc_gemini_prompts:capabilities_with(L,fun(_) -> {error,not_found} end),
        ?assertNot(maps:get(fixed_import_metadata_verified,Missing)),
        ?assertNot(maps:get(gemini_telephone_digits_import_metadata_verified,Missing))
    end,[<<"en-us">>,<<"ar-sa">>,<<"he-il">>,<<"fr-fr">>,<<"es-es">>]),
    ?assertEqual(0,maps:get(source_fixed_count,acdc_gemini_prompts:capabilities_with(<<"de-de">>,fun read/1))).

production_hooks_check_account_before_system_and_bound_view_test() ->
    Db = <<"account%2Faa%2Faa%2Faaaaaaaaaaaaaaaaaaaaaaaaaaaa">>,
    put({fake_datamgr,open},fun(<<"system_media">>,Id) -> read(Id);(D,?PROMPT) when D=:=Db -> {error,not_found} end),
    put({fake_datamgr,view},fun(D,<<"media/listing_by_prompt">>,Opts) ->
        ?assertEqual(Db,D),?assertEqual(1,proplists:get_value(limit,Opts)),
        ?assertEqual([?PROMPT],proplists:get_value(startkey,Opts)),
        ?assertEqual([?PROMPT,{[]}],proplists:get_value(endkey,Opts)),{ok,[]}
    end),
    ?assertMatch({gemini,_},acdc_gemini_prompts:default(?PROMPT,<<"en-us">>,?ACCOUNT,absent)),
    put({fake_datamgr,view},fun(_,_,_) -> {ok,[{[]}]} end),
    ?assertEqual({custom,?PROMPT},acdc_gemini_prompts:default(?PROMPT,<<"en-us">>,?ACCOUNT,absent)),
    put({fake_datamgr,view},fun(_,_,_) -> {error,timeout} end),
    ?assertEqual({error,account_override_unavailable},acdc_gemini_prompts:default(?PROMPT,<<"en-us">>,?ACCOUNT,absent)),
    put({fake_datamgr,open},fun(_,_) -> {ok,{[]}} end),
    put({fake_datamgr,view},fun(_,_,_) -> error(unexpected_view) end),
    ?assertEqual({custom,?PROMPT},acdc_gemini_prompts:default(?PROMPT,<<"en-us">>,?ACCOUNT,absent)),
    erase({fake_datamgr,open}),erase({fake_datamgr,view}).

resolve(L,Configured,State,Read) -> acdc_gemini_prompts:default_with(?PROMPT,L,?ACCOUNT,Configured,fun(_,_) -> State end,Read).
read(Id) -> case [A || A <- ?GEMINI_ASSETS, <<(element(1,A))/binary,"/",(element(3,A))/binary>> =:= Id] of [A] -> {ok,doc(A)};_ -> {error,not_found} end.
get(K,{P}) -> proplists:get_value(K,P).
set(K,V,{P}) -> {[{K,V}|proplists:delete(K,P)]}.
doc({L,C,P,S,M,N,T}) ->
    {[{<<"_id">>,<<L/binary,"/",P/binary>>},{<<"_rev">>,<<"1-0123456789abcdef">>},
      {<<"pvt_type">>,<<"media">>},{<<"pvt_account_db">>,<<"system_media">>},
      {<<"source_type">>,<<"kazoo5_acdc_gemini_voice_installer">>},{<<"prompt_id">>,P},{<<"language">>,L},
      {<<"content_type">>,<<"audio/wav">>},{<<"content_length">>,N},{<<"streamable">>,true},
      {<<"source_voice">>,{[{<<"provider">>,<<"google-gemini">>},{<<"model">>,<<"gemini-2.5-pro-preview-tts">>},
                           {<<"voice">>,<<"Sulafat">>},{<<"canonical_prompt_id">>,C},{<<"sha256">>,S},{<<"transcript_sha256">>,T}]}},
      {<<"_attachments">>,{[{<<P/binary,".wav">>,{[{<<"content_type">>,<<"audio/wav">>},{<<"length">>,N},{<<"digest">>,M}]}}]}}]}.
