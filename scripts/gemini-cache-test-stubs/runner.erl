-module(runner).
-export([run/1]).
run(Directory) ->
    true = string:prefix(code:which(kz_datamgr), Directory) =/= nomatch,
    {ok, Bytes} = file:read_file(filename:join(Directory, "expectations.json")),
    Expected = kz_json:decode(Bytes),
    [register(M, spawn(fun() -> receive stop -> ok end end)) || M <- [media_map, kz_media_map]],
    [ets:new(M, [named_table, set, protected, {keypos, 2}]) || M <- [media_map, kz_media_map]],
    Documents = maps:from_list([{kz_json:get_value(<<"id">>, E), document(E)} || E <- Expected]),
    Probe = filename:join(Directory, "probe.erl"), Refresh = filename:join(Directory, "refresh.erl"),
    reset(Documents),
    {ok, {ok, {gemini_mapping_preflight, 165, 0, 330, no_mutations}}} = file:script(Probe),
    undefined = get(writes),
    reset(Documents),
    {ok, {ok, {gemini_mapping_refreshed, 165, 330, true, no_database_writes}}} = file:script(Refresh),
    330 = get(writes),
    {ok, {ok, {gemini_mapping_preflight, 165, 330, 0, no_mutations}}} = file:script(Probe),
    {ok, {ok, {gemini_mapping_refreshed, 165, 330, false, no_database_writes}}} = file:script(Refresh),
    io:format("PASS probe, 165x2 refresh, exact mapping paths, idempotent replay~n"),
    [First | _] = Expected, Id = kz_json:get_value(<<"id">>, First), Doc = maps:get(Id, Documents),
    lists:foreach(fun({Key, BadValue}) ->
        reset(maps:put(Id, kz_json:set_value(Key, BadValue, Doc), Documents)),
        {ok, {error, gemini_mapping_refresh_failed_safely}} = file:script(Refresh),
        undefined = get(writes)
    end, [{<<"source_type">>, <<"custom">>}, {<<"pvt_account_id">>, <<"other">>},
          {<<"pvt_deleted">>, true}, {<<"content_length">>, -1},
          {[<<"source_voice">>, <<"sha256">>], <<"unreviewed">>},
          {[<<"_attachments">>, kz_json:get_value(<<"attachment">>, First), <<"digest">>], <<"wrong">>}]),
    io:format("PASS six provenance/ownership/deletion/attachment failures before cache writes~n"),
    reset(Documents), put(race, {Id, 2}),
    {ok, {error, gemini_mapping_refresh_failed_safely}} = file:script(Refresh), undefined = get(writes),
    reset(Documents), put(race, {Id, 3}),
    {ok, {error, gemini_mapping_refresh_failed_safely}} = file:script(Refresh), 330 = get(writes),
    io:format("PASS pre-write and final revision races fail closed~n"),
    reset(Documents),
    Prompt = kz_json:get_value(<<"prompt_id">>, First), Language = kz_json:get_value(<<"language">>, First),
    ets:insert(media_map, {media_map, <<"system_media/", Prompt/binary>>, <<"system_media">>, Prompt,
                          kz_json:from_list([{Language, <<"/unrelated/custom-recording">>}])}),
    {ok, {error, gemini_mapping_refresh_failed_safely}} = file:script(Refresh), undefined = get(writes),
    io:format("PASS conflicting existing mapping is not overwritten~n"),
    halt(0).
reset(Docs) ->
    erase(), put(docs, Docs), [ets:delete_all_objects(M) || M <- [media_map, kz_media_map]], ok.
document(E) ->
    Get = fun(Key) -> kz_json:get_value(Key, E) end,
    kz_json:from_list([{<<"_id">>, Get(<<"id">>)}, {<<"_rev">>, <<"1-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>},
      {<<"pvt_type">>, <<"media">>}, {<<"pvt_account_db">>, <<"system_media">>},
      {<<"prompt_id">>, Get(<<"prompt_id">>)}, {<<"language">>, Get(<<"language">>)},
      {<<"source_type">>, Get(<<"source_type">>)}, {<<"content_length">>, Get(<<"content_length">>)},
      {<<"content_type">>, <<"audio/wav">>}, {<<"streamable">>, true}, {<<"source_voice">>, Get(<<"source_voice">>)},
      {<<"_attachments">>, kz_json:from_list([{Get(<<"attachment">>), kz_json:from_list([
        {<<"content_type">>, <<"audio/wav">>}, {<<"length">>, Get(<<"content_length">>)}, {<<"digest">>, Get(<<"digest">>)}])}])}]).
