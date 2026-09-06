%%% SPDX-License-Identifier: MPL-2.0
%%% Explicit, local-node-only cache maintenance for the fixed ACDC catalog.
%%% No customer documents, account mappings, database writes or full flushes.
-module(acdc_language_maintenance).

-export([refresh/0, refresh/1, verify/0, verify/1, catalog/0, catalog/1]).
-ifdef(TEST).
-export([validate_doc/3]).
-endif.

-define(DB, <<"system_media">>).
-define(MAP_TIMEOUT, 5000).

-spec refresh() -> {'ok', kz_json:object()} | {'error', any()}.
refresh() -> run('refresh', locales()).
-spec refresh(binary()) -> {'ok', kz_json:object()} | {'error', any()}.
refresh(Language) -> run('refresh', [Language]).
-spec verify() -> {'ok', kz_json:object()} | {'error', any()}.
verify() -> run('verify', locales()).
-spec verify(binary()) -> {'ok', kz_json:object()} | {'error', any()}.
verify(Language) -> run('verify', [Language]).

-spec locales() -> [binary()].
locales() -> [<<"en-us">>, <<"es-es">>, <<"fr-fr">>, <<"ar-sa">>, <<"he-il">>].

-spec catalog() -> [binary()].
catalog() -> lists:append([catalog(Language) || Language <- locales()]).
-spec catalog(binary()) -> [binary()].
catalog(Language) ->
    case lists:member(Language, locales()) of
        'false' -> [];
        'true' -> [<<Language/binary, "/", Prompt/binary>> || Prompt <- prompts(Language)]
    end.

-spec prompts(binary()) -> [binary()].
prompts(Language) ->
    Fixed = [<<"acdc-callback-offer-", (integer_to_binary(N))/binary>> || N <- lists:seq(0, 9)]
        ++ [<<"acdc-callback-", Name/binary>> || Name <- [<<"menu-current">>, <<"menu-alternate">>
              ,<<"number-readback">>, <<"confirmation">>, <<"success">>, <<"returned-confirmation">>]]
        ++ [<<"acdc-queue-", Name/binary>> || Name <- [<<"your-current-position-is">>, <<"you_are_at_position">>
              ,<<"in_the_queue">>, <<"increase_in_call_volume">>, <<"the_estimated_wait_time_is">>
              ,<<"less_than_1_minute">>, <<"about_5_minutes">>, <<"about_10_minutes">>
              ,<<"about_15_minutes">>, <<"about_30_minutes">>, <<"about_45_minutes">>
              ,<<"about_1_hour">>, <<"at_least_1_hour">>]],
    case Language =:= <<"ar-sa">> orelse Language =:= <<"he-il">> of
        'false' -> Fixed;
        'true' -> Fixed ++ [<<"acdc-number-and">>, <<"acdc-number-0">>]
            ++ [<<"acdc-number-", (integer_to_binary(N * Scale))/binary>>
                || Scale <- [1, 1000, 1000000], N <- lists:seq(1, 999)]
    end.

-spec run(atom(), [binary()]) -> {'ok', kz_json:object()} | {'error', any()}.
run(Operation, Languages) ->
    try
        require(lists:all(fun(L) -> lists:member(L, locales()) end, Languages), 'unsupported_locale'),
        Ids = lists:append([catalog(L) || L <- Languages]),
        Before = database_sequence(),
        Docs = read_catalog(Ids),
        require(database_sequence() =:= Before, 'media_changed_during_validation'),
        case Operation of
            'refresh' ->
                %% The explicit ID overload erases only these local doc-cache
                %% keys. Never use flush_cache_docs/0 or /1, or media_map:flush.
                require(kz_datamgr:flush_cache_docs(?DB, Ids) =:= 'ok', 'doc_cache_flush_failed'),
                lists:foreach(fun install_mapping/1, Docs);
            'verify' -> 'ok'
        end,
        lists:foreach(fun verify_mapping/1, Ids),
        %% A concurrent import/change invalidates this entire local proof.
        require(database_sequence() =:= Before, 'media_changed_during_mapping'),
        {'ok', kz_json:from_list([{<<"status">>, <<"verified">>}, {<<"operation">>, kz_term:to_binary(Operation)}
            ,{<<"node">>, kz_term:to_binary(node())}, {<<"local_only">>, 'true'}
            ,{<<"document_count">>, length(Ids)}, {<<"languages">>, Languages}
            ,{<<"database_update_seq">>, Before}, {<<"exact_language_resolution">>, 'true'}
            ,{<<"audio_metadata_verified">>, 'true'}, {<<"runtime_ready">>, 'false'}])}
    catch
        'throw':{'language_media', Reason} -> {'error', Reason};
        _:_ -> {'error', 'local_media_verification_unavailable'}
    end.

-spec database_sequence() -> non_neg_integer() | binary().
database_sequence() ->
    case kz_datamgr:db_info(?DB) of
        {'ok', Info} ->
            require(kz_json:get_value(<<"db_name">>, Info) =:= ?DB, 'wrong_media_database'),
            Seq = kz_json:get_value(<<"update_seq">>, Info),
            require((is_integer(Seq) andalso Seq >= 0)
                    orelse (is_binary(Seq) andalso byte_size(Seq) > 0 andalso byte_size(Seq) =< 16384)
                    ,'invalid_database_sequence'),
            Seq;
        _ -> fail('media_database_unavailable')
    end.

-spec read_catalog([binary()]) -> [kz_json:object()].
read_catalog(Ids) ->
    %% open_docs is a direct keyed _all_docs read, not open_cache_docs. Its
    %% chunked reader may return per-row errors; require a complete bijection.
    case kz_datamgr:open_docs(?DB, Ids, [{'conflicts', 'true'}, {'max_bulk_read', 100}]) of
        {'ok', Rows} when is_list(Rows), length(Rows) =:= length(Ids) ->
            Keys = [kz_json:get_value(<<"key">>, Row) || Row <- Rows],
            require(lists:sort(Keys) =:= lists:sort(Ids), 'incomplete_or_duplicate_media_rows'),
            [validated_row(Row) || Row <- Rows];
        _ -> fail('incomplete_media_inventory')
    end.

-spec validated_row(kz_json:object()) -> kz_json:object().
validated_row(Row) ->
    Id = kz_json:get_value(<<"key">>, Row),
    [Language, Prompt] = binary:split(Id, <<"/">>),
    Doc = kz_json:get_value(<<"doc">>, Row),
    require(kz_json:get_value(<<"error">>, Row) =:= 'undefined'
            andalso kz_json:get_value(<<"id">>, Row) =:= Id
            andalso kz_json:get_value([<<"value">>, <<"rev">>], Row) =:= kz_doc:revision(Doc)
            andalso lists:member(kz_json:get_value([<<"value">>, <<"deleted">>], Row), ['undefined', 'false'])
            andalso validate_doc(Language, Prompt, Doc), {'invalid_media_document', Id}),
    Doc.

-spec validate_doc(binary(), binary(), kz_json:object()) -> boolean().
validate_doc(Language, Prompt, Doc) ->
    try
        Id = <<Language/binary, "/", Prompt/binary>>,
        kz_doc:id(Doc) =:= Id andalso kz_doc:type(Doc) =:= <<"media">>
            andalso matches(kz_doc:revision(Doc), <<"^[1-9][0-9]*-[a-f0-9]{32}$">>)
            andalso kz_json:get_value(<<"language">>, Doc) =:= Language
            andalso kz_json:get_value(<<"prompt_id">>, Doc) =:= Prompt
            andalso lists:member(kz_doc:account_id(Doc), ['undefined', ?DB])
            andalso lists:member(kz_doc:account_db(Doc), ['undefined', ?DB])
            andalso lists:all(fun(Key) -> lists:member(kz_json:get_value(Key, Doc), ['undefined', 'false']) end
                              ,[<<"_deleted">>, <<"pvt_deleted">>])
            andalso kz_json:get_value(<<"_conflicts">>, Doc, []) =:= []
            andalso kz_json:get_value(<<"_deleted_conflicts">>, Doc, []) =:= []
            andalso usable_attachments(Doc)
    catch _:_ -> 'false'
    end.

-spec usable_attachments(kz_json:object()) -> boolean().
usable_attachments(Doc) ->
    Names = kz_doc:attachment_names(Doc),
    Names =/= [] andalso lists:all(fun(Name) ->
        Length = kz_json:get_value([<<"_attachments">>, Name, <<"length">>], Doc),
        is_binary(Name) andalso byte_size(Name) > 0 andalso byte_size(Name) =< 255
            andalso re:run(Name, <<"[\\x00-\\x1f]">>, [{'capture', 'none'}]) =:= 'nomatch'
            andalso is_integer(Length) andalso Length > 0
            andalso matches(kz_doc:attachment_content_type(Doc, Name), <<"^audio/[A-Za-z0-9.+-]+$">>)
            andalso matches(kz_json:get_value([<<"_attachments">>, Name, <<"digest">>], Doc)
                            ,<<"^md5-[A-Za-z0-9+/]{22}==$">>)
    end, Names).

-spec install_mapping(kz_json:object()) -> 'ok'.
install_mapping(Doc) ->
    %% Existing synchronous mapping operation merges just this locale into
    %% its system prompt. Other locales and every account map remain intact.
    case gen_listener:call('kz_media_map', {'add_mapping', ?DB, Doc}, ?MAP_TIMEOUT) of
        'ok' -> 'ok';
        _ -> fail({'mapping_update_failed', kz_doc:id(Doc)})
    end.

-spec verify_mapping(binary()) -> 'ok'.
verify_mapping(Id) ->
    [Language, Prompt] = binary:split(Id, <<"/">>),
    Expected = kz_media_util:prompt_path(?DB, kz_http_util:urlencode(Id)),
    require(kz_media_map:prompt_path(?DB, Prompt, Language) =:= Expected
            ,{'wrong_language_resolution', Id}).

-spec matches(any(), binary()) -> boolean().
matches(Value, Pattern) when is_binary(Value) -> re:run(Value, Pattern, [{'capture', 'none'}]) =:= 'match';
matches(_, _) -> 'false'.
-spec require(boolean(), any()) -> 'ok'.
require('true', _) -> 'ok';
require('false', Reason) -> fail(Reason).
-spec fail(any()) -> no_return().
fail(Reason) -> throw({'language_media', Reason}).
