%%% SPDX-License-Identifier: MPL-2.0
-module(acdc_language_maintenance_tests).
-include_lib("eunit/include/eunit.hrl").
-define(DB, <<"system_media">>).
-define(REV, <<"1-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(PROMPT, <<"acdc-callback-offer-0">>).

j(P) -> kz_json:from_list(P).
info(Seq) -> {ok, j([{<<"db_name">>, ?DB}, {<<"update_seq">>, Seq}])}.
doc(Id) ->
    [Language, Prompt] = binary:split(Id, <<"/">>),
    j([{<<"_id">>, Id}, {<<"_rev">>, ?REV}, {<<"pvt_type">>, <<"media">>}
      ,{<<"language">>, Language}, {<<"prompt_id">>, Prompt}, {<<"pvt_account_db">>, ?DB}
      ,{<<"_attachments">>, j([{<<"custom-recording.wav">>, j([{<<"length">>, 128}, {<<"content_type">>, <<"audio/wav">>}
                                                           ,{<<"digest">>, <<"md5-AAAAAAAAAAAAAAAAAAAAAA==">>}])}])}]).
row(Id) -> j([{<<"key">>, Id}, {<<"id">>, Id}, {<<"value">>, j([{<<"rev">>, ?REV}])}, {<<"doc">>, doc(Id)}]).
path(Id) -> kz_media_util:prompt_path(?DB, kz_http_util:urlencode(Id)).

with_fixture(Test) ->
    meck:new(kz_datamgr, [non_strict, no_link]),
    meck:new(kz_media_util, [passthrough, no_link]),
    Parent = self(),
    Pid = spawn(fun() ->
        true = register(kz_media_map, self()),
        kz_media_map = ets:new(kz_media_map, kz_media_map:table_options()),
        Parent ! {map_ready, self()},
        map_loop({state})
    end),
    receive {map_ready, Pid} -> ok after 1000 -> error(map_fixture_not_ready) end,
    try
        meck:expect(kz_media_util, prompt_language, fun(_) -> <<"en-us">> end),
        meck:expect(kz_media_util, default_prompt_language, fun() -> <<"en-us">> end),
        meck:expect(kz_datamgr, db_info, fun(?DB) -> info(100) end),
        meck:expect(kz_datamgr, open_docs, fun(?DB, Ids, Options) ->
            ?assertEqual([{conflicts, true}, {max_bulk_read, 100}], Options),
            {ok, [row(Id) || Id <- Ids]}
        end),
        meck:expect(kz_datamgr, flush_cache_docs, fun(?DB, _) -> ok end),
        Test(Pid),
        ?assert(meck:validate(kz_datamgr))
    after
        Ref = monitor(process, Pid), exit(Pid, kill),
        receive {'DOWN', Ref, process, Pid, _} -> ok after 1000 -> error(map_fixture_not_stopped) end,
        meck:unload(kz_datamgr), meck:unload(kz_media_util)
    end.

map_loop(State) ->
    receive
        {'$gen_call', From, {'$client_call', Request}} ->
            {reply, Reply, Next} = kz_media_map:handle_call(Request, From, State),
            gen_server:reply(From, Reply), map_loop(Next)
    end.

insert_map(Account, Prompt, Languages) ->
    gen_listener:call(kz_media_map, {insert_map, {media_map, <<Account/binary, "/", Prompt/binary>>, Account, Prompt, j(Languages)}}).
snapshot() -> lists:sort(ets:tab2list(kz_media_map)).

catalog_exact_counts_and_canonical_only_test() ->
    Ids = acdc_language_maintenance:catalog(),
    ?assertEqual(6143, length(Ids)), ?assertEqual(6143, length(lists:usort(Ids))),
    lists:foreach(fun(L) -> ?assertEqual(29, length(acdc_language_maintenance:catalog(L))) end,
                  [<<"en-us">>, <<"es-es">>, <<"fr-fr">>]),
    lists:foreach(fun(L) -> ?assertEqual(3028, length(acdc_language_maintenance:catalog(L))) end,
                  [<<"ar-sa">>, <<"he-il">>]),
    lists:foreach(fun(L) -> ?assertEqual([], acdc_language_maintenance:catalog(L)),
        ?assertEqual({error, unsupported_locale}, acdc_language_maintenance:refresh(L)) end,
        [undefined, <<"all">>, <<"EN_US">>, <<"he">>, <<"../account">>]).

full_catalog_refresh_is_scoped_test_() ->
    {timeout, 30, fun() -> with_fixture(fun(_) ->
        Ids = acdc_language_maintenance:catalog(),
        {ok, Proof} = acdc_language_maintenance:refresh(),
        ?assertEqual(6143, kz_json:get_value(<<"document_count">>, Proof)),
        ?assertEqual(true, kz_json:get_value(<<"local_only">>, Proof)),
        ?assertEqual(false, kz_json:get_value(<<"runtime_ready">>, Proof)),
        ?assertEqual(atom_to_binary(node()), kz_json:get_value(<<"node">>, Proof)),
        ?assertEqual(1, meck:num_calls(kz_datamgr, flush_cache_docs, [?DB, Ids])),
        ?assertEqual(0, meck:num_calls(kz_datamgr, flush_cache_docs, [])),
        ?assertEqual(0, meck:num_calls(kz_datamgr, flush_cache_docs, [?DB])),
        ?assertEqual(3, meck:num_calls(kz_datamgr, db_info, [?DB])),
        lists:foreach(fun(Id) ->
            [Language, Prompt] = binary:split(Id, <<"/">>),
            ?assertEqual(path(Id), kz_media_map:prompt_path(?DB, Prompt, Language))
        end, Ids)
    end) end}.

refresh_preserves_unrelated_custom_and_other_locale_maps_test() ->
    with_fixture(fun(_) ->
        Account = <<"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb">>,
        insert_map(?DB, <<"unrelated-prompt">>, [{<<"en-us">>, <<"/system_media/custom-original">>}]),
        insert_map(Account, ?PROMPT, [{<<"es-es">>, <<"/account/custom-recording">>}]),
        insert_map(?DB, ?PROMPT, [{<<"en-us">>, path(<<"en-us/", ?PROMPT/binary>>)}
                                ,{<<"de-de">>, <<"/system_media/custom-german">>}]),
        [Unrelated] = ets:lookup(kz_media_map, <<"system_media/unrelated-prompt">>),
        [Custom] = ets:lookup(kz_media_map, <<Account/binary, "/", ?PROMPT/binary>>),
        ?assertMatch({ok, _}, acdc_language_maintenance:refresh(<<"es-es">>)),
        ?assertEqual([Unrelated], ets:lookup(kz_media_map, <<"system_media/unrelated-prompt">>)),
        ?assertEqual([Custom], ets:lookup(kz_media_map, <<Account/binary, "/", ?PROMPT/binary>>)),
        ?assertEqual(<<"/system_media/custom-german">>, kz_media_map:prompt_path(?DB, ?PROMPT, <<"de-de">>)),
        ?assertEqual(path(<<"en-us/", ?PROMPT/binary>>), kz_media_map:prompt_path(?DB, ?PROMPT, <<"en-us">>)),
        ?assertEqual(1, meck:num_calls(kz_datamgr, flush_cache_docs, [?DB, acdc_language_maintenance:catalog(<<"es-es">>)])),
        ?assertMatch({ok, _}, acdc_language_maintenance:verify(<<"es-es">>)),
        ?assertEqual(1, meck:num_calls(kz_datamgr, flush_cache_docs, ['_', '_']))
    end).

verify_rejects_english_fallback_and_wrong_exact_path_test() ->
    with_fixture(fun(_) ->
        insert_map(?DB, ?PROMPT, [{<<"en-us">>, path(<<"en-us/", ?PROMPT/binary>>)}]),
        Before = snapshot(),
        ?assertEqual({error, {wrong_language_resolution, <<"es-es/", ?PROMPT/binary>>}},
                     acdc_language_maintenance:verify(<<"es-es">>)),
        ?assertEqual(Before, snapshot()),
        insert_map(?DB, ?PROMPT, [{<<"es-es">>, <<"/system_media/es-es%2Fother-prompt">>}]),
        ?assertMatch({error, {wrong_language_resolution, _}}, acdc_language_maintenance:verify(<<"es-es">>)),
        ?assertEqual(0, meck:num_calls(kz_datamgr, flush_cache_docs, ['_', '_']))
    end).

media_identity_deletion_conflicts_and_audio_fail_closed_test() ->
    Id = <<"es-es/", ?PROMPT/binary>>, Good = doc(Id),
    ?assert(acdc_language_maintenance:validate_doc(<<"es-es">>, ?PROMPT, Good)),
    Mutations = [{<<"_id">>, <<"en-us/", ?PROMPT/binary>>}, {<<"_rev">>, <<"malformed">>}
        ,{<<"language">>, <<"en-us">>}, {<<"prompt_id">>, <<"other">>}, {<<"pvt_type">>, <<"user">>}
        ,{<<"pvt_account_id">>, <<"foreign-account">>}, {<<"pvt_account_db">>, <<"account%2Fforeign">>}
        ,{<<"_deleted">>, true}, {<<"pvt_deleted">>, true}, {<<"pvt_deleted">>, <<"false">>}
        ,{<<"_conflicts">>, [<<"2-conflict">>]}, {<<"_deleted_conflicts">>, [<<"2-conflict">>]}
        ,{<<"_attachments">>, j([])}
        ,{[<<"_attachments">>, <<"custom-recording.wav">>, <<"length">>], 0}
        ,{[<<"_attachments">>, <<"custom-recording.wav">>, <<"length">>], <<"128">>}
        ,{[<<"_attachments">>, <<"custom-recording.wav">>, <<"content_type">>], <<"text/plain">>}
        ,{[<<"_attachments">>, <<"custom-recording.wav">>, <<"digest">>], <<"unknown">>}],
    with_fixture(fun(_) -> lists:foreach(fun({Key, Value}) ->
        Bad = kz_json:set_value(Key, Value, Good),
        ?assertNot(acdc_language_maintenance:validate_doc(<<"es-es">>, ?PROMPT, Bad)),
        meck:expect(kz_datamgr, open_docs, fun(?DB, Ids, _) ->
            {ok, [case I of Id -> kz_json:set_value(<<"doc">>, Bad, row(I)); _ -> row(I) end || I <- Ids]}
        end),
        ?assertMatch({error, _}, acdc_language_maintenance:refresh(<<"es-es">>)),
        ?assertEqual([], snapshot()),
        ?assertEqual(0, meck:num_calls(kz_datamgr, flush_cache_docs, ['_', '_']))
    end, Mutations) end).

incomplete_duplicate_unknown_and_error_rows_are_rejected_test() ->
    with_fixture(fun(_) -> lists:foreach(fun(Change) ->
        meck:expect(kz_datamgr, open_docs, fun(?DB, Ids, _) -> {ok, Change([row(Id) || Id <- Ids])} end),
        ?assertMatch({error, _}, acdc_language_maintenance:refresh(<<"fr-fr">>)),
        ?assertEqual([], snapshot()),
        ?assertEqual(0, meck:num_calls(kz_datamgr, flush_cache_docs, ['_', '_']))
    end, [fun([_|Rest]) -> Rest end,
        fun([First,_|Rest]) -> [First,First|Rest] end,
        fun([First|Rest]) -> [kz_json:set_value(<<"key">>, <<"fr-fr/foreign-prompt">>, First)|Rest] end,
        fun([First|Rest]) -> [kz_json:set_value(<<"error">>, <<"not_found">>, First)|Rest] end,
        fun([First|Rest]) -> [kz_json:set_value([<<"value">>, <<"rev">>], <<"2-other">>, First)|Rest] end,
        fun([First|Rest]) -> [kz_json:set_value([<<"value">>, <<"deleted">>], true, First)|Rest] end]) end).

racing_database_sequence_never_proves_readiness_test() ->
    with_fixture(fun(_) -> lists:foreach(fun({Sequences, Expected, Entries}) ->
        meck:expect(kz_datamgr, db_info, 1, meck:seq([info(S) || S <- Sequences])),
        ?assertEqual({error, Expected}, acdc_language_maintenance:refresh(<<"en-us">>)),
        ?assertEqual(Entries, length(snapshot()))
    end, [{[100,101],media_changed_during_validation,0}, {[100,100,101],media_changed_during_mapping,29}]) end).

cache_transport_and_mapping_failure_never_prove_success_test() ->
    with_fixture(fun(_) ->
        meck:expect(kz_datamgr, flush_cache_docs, fun(_, _) -> {error, unavailable} end),
        ?assertEqual({error, doc_cache_flush_failed}, acdc_language_maintenance:refresh(<<"en-us">>)),
        ?assertEqual([], snapshot()),
        meck:expect(kz_datamgr, open_docs, fun(_, _, _) -> {error, timeout} end),
        ?assertEqual({error, incomplete_media_inventory}, acdc_language_maintenance:verify(<<"en-us">>))
    end),
    with_fixture(fun(Pid) ->
        Ref = monitor(process, Pid), exit(Pid, kill), receive {'DOWN',Ref,process,Pid,_} -> ok end,
        ?assertEqual({error, local_media_verification_unavailable}, acdc_language_maintenance:refresh(<<"en-us">>))
    end).
