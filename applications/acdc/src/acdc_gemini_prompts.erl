%%% Immutable fixed Gemini defaults, never global aliases for customer media.
-module(acdc_gemini_prompts).
-export([canonical/1, default/4, default_alias/5, selection/2,
         callback/5, callback_readback/2, telephone/3, capabilities/1,
         fixed_media_ids/1, verified_fixed_media/2, fixed_media_complete/2]).
-ifdef(TEST).
-export([default_with/6, telephone_with/5, capabilities_with/2, asset/2, imported/2]).
-endif.
-include("acdc_gemini_map.hrl").
-define(OWNER, <<"kazoo5_acdc_gemini_voice_installer">>).
-define(MODEL, <<"gemini-2.5-pro-preview-tts">>).
-define(VOICE, <<"Sulafat">>).

-spec canonical(any()) -> binary().
canonical(undefined) -> <<"en-us">>;
canonical(L) when is_binary(L) ->
    binary:replace(list_to_binary(string:lowercase(binary_to_list(L))), <<"_">>, <<"-">>, [global]);
canonical(_) -> <<>>.

%% The caller must pass presence, NOT an already-defaulted/merged media value.
%% Every explicit override (including a stock-looking prompt ID) is preserved.
-spec default(binary(), any(), binary(), absent | {configured, any()}) -> tuple().
default(Prompt, Language, Account, Configured) ->
    default_with(Prompt, Language, Account, Configured, fun account_override/2, fun read_media/1).

%% Legacy queue-* account recordings must be checked before the new acdc-queue-*
%% system default. A configured value is never reinterpreted as an absent field.
-spec default_alias(binary(), binary(), any(), binary(), any()) -> tuple().
default_alias(Legacy, Canonical, Language, Account, absent) when Legacy =/= Canonical ->
    case default_with(Legacy, Language, Account, absent,
                      fun account_override/2, fun read_media/1) of
        {error, unsupported_gemini_prompt} -> default(Canonical, Language, Account, absent);
        Result -> Result
    end;
default_alias(_Legacy, Canonical, Language, Account, Configured) ->
    default(Canonical, Language, Account, Configured).

-spec selection(binary(), any()) -> absent | {configured, any()}.
selection(Key, {Props}) when is_list(Props) -> selection(Key, Props);
selection(Key, Props) when is_list(Props) ->
    case lists:keyfind(Key, 1, Props) of false -> absent; {Key,Value} -> {configured,Value} end;
selection(_, _) -> absent.

%% Resolve the complete callback media and numeric readback contract once.
%% EN remains an explicitly incremental native-say dependency. FR/ES do not
%% silently borrow it; their numeric verification/recording gate is outstanding.
-spec callback(any(), any(), any(), any(), binary()) -> tuple().
callback(<<Digit>>=Entry, Alternate, Media, Language0, Account) when Digit >= $0, Digit =< $9 ->
    Language = canonical(Language0),
    case legacy_custom_callback(Media) of
        {ok, Legacy} -> {ok, Legacy};
        incomplete -> callback_defaults(Entry, Alternate, Media, Language, Account)
    end;
callback(_, _, _, _, _) -> {error, invalid_entry_key}.

%% Preserve the pre-existing explicitly customized path, even for locales not
%% covered by this generated pack. This is not evidence of Gemini readiness.
-spec legacy_custom_callback(any()) -> tuple() | incomplete.
legacy_custom_callback(Media) ->
    Fields=[{offer,<<"offer">>},{menu,<<"menu">>},{number_readback,<<"number_readback">>},
            {confirmation,<<"confirmation">>},{success,<<"success">>}],
    Values=[{Name,selection(Key,Media)} || {Name,Key} <- Fields],
    case lists:all(fun({_,{configured,V}}) when is_binary(V),byte_size(V)>0,byte_size(V)=<2048 -> true;
                     (_) -> false end,Values) of
        true -> {ok,#{media=>maps:from_list([{Name,V} || {Name,{configured,V}} <- Values]),
                      readback=>native_say,non_gemini_numeric_dependency=>true,
                      legacy_custom_media=>true}};
        false -> incomplete
    end.

-spec callback_defaults(binary(), any(), any(), binary(), binary()) -> tuple().
callback_defaults(Entry, Alternate, Media, Language, Account) ->
    case lists:member(Language, [<<"en-us">>, <<"ar-sa">>, <<"he-il">>]) of
        false -> {error, numeric_readback_unverified};
        true when Language =/= <<"en-us">> ->
            %% Fixed messages + telephone digits are insufficient: the legacy
            %% unavailable/invalid-entry/enter-number branches still need an
            %% imported localized Gemini supplemental pack and integration.
            {error, auxiliary_callback_media_unverified};
        true ->
            Menu = case Alternate of true -> <<"acdc-callback-menu-alternate">>; _ -> <<"acdc-callback-menu-current">> end,
            Defaults = [{offer, <<"offer">>, <<"acdc-callback-offer-",Entry/binary>>},
                        {menu, <<"menu">>, Menu},
                        {number_readback, <<"number_readback">>, <<"acdc-callback-number-readback">>},
                        {confirmation, <<"confirmation">>, <<"acdc-callback-confirmation">>},
                        {success, <<"success">>, <<"acdc-callback-success">>},
                        {returned_confirmation, <<"returned_confirmation">>, <<"acdc-callback-returned-confirmation">>}],
            case callback_media(Defaults, Media, Language, Account, #{}) of
                {ok, Resolved} -> callback_numbers(Language, Account, Resolved);
                Error -> Error
            end
    end.

-spec callback_media(list(), any(), binary(), binary(), map()) -> tuple().
callback_media([], _, _, _, Acc) -> {ok, Acc};
callback_media([{Name,Key,Prompt}|Rest], Media, Language, Account, Acc) ->
    case default(Prompt, Language, Account, selection(Key,Media)) of
        {Kind,Value} when Kind =:= gemini; Kind =:= custom ->
            case Name =:= returned_confirmation andalso byte_size(Value) > 256 of
                true -> {error, invalid_returned_confirmation};
                false -> callback_media(Rest,Media,Language,Account,Acc#{Name => Value})
            end;
        Error -> Error
    end.

-spec callback_numbers(binary(), binary(), map()) -> tuple().
callback_numbers(<<"en-us">>, _, Media) ->
    {ok, #{media => Media, readback => native_say, non_gemini_numeric_dependency => true}};
callback_numbers(Language, Account, Media) ->
    case telephone(<<"0123456789">>, Language, Account) of
        {ok, Prompts} ->
            {ok, #{media => Media, readback => maps:from_list(lists:zip("0123456789",Prompts)),
                   non_gemini_numeric_dependency => false}};
        Error -> Error
    end.

%% Pure playback expansion: no datastore calls or partial numeric playlists.
-spec callback_readback(any(), map()) -> {ok,list()} | {error,invalid_readback}.
callback_readback(Digits, #{readback := native_say}) ->
    case valid_digits(Digits) of
        true -> {ok,[{say,Digits,<<"telephone_number">>}]};
        false -> {error,invalid_readback}
    end;
callback_readback(Digits, #{readback := Prompts}) when is_map(Prompts) ->
    case valid_digits(Digits) andalso lists:all(fun(D) -> maps:is_key(D,Prompts) end,binary_to_list(Digits)) of
        true -> {ok,[maps:get(D,Prompts) || <<D>> <= Digits]};
        false -> {error,invalid_readback}
    end;
callback_readback(_, _) -> {error,invalid_readback}.

-spec default_with(binary(), any(), binary(), any(), function(), function()) -> tuple().
default_with(_Prompt, _Language, _Account, {configured, Value}, _Override, _Read)
  when is_binary(Value), byte_size(Value) > 0, byte_size(Value) =< 2048 -> {custom, Value};
default_with(Prompt, Language, Account, absent, Override, Read) ->
    case valid_account(Account) of
        false -> {error, invalid_account};
        true ->
            %% The caller's account override takes precedence over a new system
            %% default. Unknown view/cache responses do NOT mean no override.
            case safe(fun() -> Override(Account, Prompt) end) of
                custom -> {custom, Prompt};
                none -> mapped(Prompt, canonical(Language), Read);
                _ -> {error, account_override_unavailable}
            end
    end;
default_with(_, _, _, _, _, _) -> {error, invalid_explicit_media}.

-spec mapped(binary(), binary(), function()) -> tuple().
mapped(Prompt, Language, Read) ->
    case asset(Language, Prompt) of
        undefined -> {error, unsupported_gemini_prompt};
        Asset ->
            case safe(fun() -> imported(Asset, Read(media_id(Asset))) end) of
                true -> {gemini, element(3, Asset)};
                _ -> {error, gemini_media_unavailable}
            end
    end.

-spec telephone(binary(), any(), binary()) -> tuple().
telephone(Digits, Language, Account) ->
    telephone_with(Digits, Language, Account, fun account_override/2, fun read_media/1).

-spec telephone_with(any(), any(), binary(), function(), function()) -> tuple().
telephone_with(Digits, Language0, Account, Override, Read) ->
    Language = canonical(Language0),
    case lists:member(Language, [<<"ar-sa">>, <<"he-il">>]) andalso valid_digits(Digits) of
        false -> {error, unsupported_gemini_telephone};
        true ->
            %% Validate each distinct digit once, then preserve repeats/leading
            %% zeroes. No partial playlist and no say/eSpeak/English fallback.
            Unique = lists:usort(binary_to_list(Digits)),
            Resolved = [{D, default_with(<<"acdc-number-",D>>, Language, Account, absent, Override, Read)} || D <- Unique],
            case lists:all(fun({_,{Kind,P}}) -> (Kind =:= custom orelse Kind =:= gemini) andalso is_binary(P) end, Resolved) of
                false -> {error, gemini_digits_unavailable};
                true ->
                    {ok, [{prompt, element(2,proplists:get_value(D,Resolved)), Language, <<"A">>} || <<D>> <= Digits]}
            end
    end.

-spec capabilities(any()) -> map().
capabilities(Language) -> capabilities_with(Language, fun read_media/1).

-spec capabilities_with(any(), function()) -> map().
capabilities_with(Language0, Read) ->
    Language = canonical(Language0),
    All = [A || A <- ?GEMINI_ASSETS, element(1,A) =:= Language],
    Fixed = [A || A <- All, not digit_asset(A)],
    Digits = [A || A <- All, digit_asset(A)],
    Available = fun(Assets, Count) -> length(Assets) =:= Count andalso
        lists:all(fun(A) -> safe(fun() -> imported(A,Read(media_id(A))) end) =:= true end, Assets) end,
    #{schema_version => 1, map_sha256 => ?GEMINI_MAP_SHA256, locale => Language,
      source_fixed_count => length(Fixed), source_digit_count => length(Digits),
      fixed_import_metadata_verified => Available(Fixed,29),
      gemini_telephone_digits_import_metadata_verified => Available(Digits,10),
      non_gemini_numeric_dependency => lists:member(Language,[<<"en-us">>,<<"fr-fr">>,<<"es-es">>]),
      imported_audio_sha256_requires_importer_verification => true,
      position_available => false, callback_runtime_ready => false,
      full_language_ready => false, native_speaker_review => false}.

%% Bounded editor projection of actual immutable identities. This checks fresh
%% document metadata supplied by the caller; it does not verify audio bytes,
%% resolver caches, native number speech, or whole-language runtime readiness.
-spec fixed_media_ids(binary()) -> list().
fixed_media_ids(Language) -> [media_id(A) || A <- fixed_assets(Language)].

-spec verified_fixed_media(binary(), list()) -> list().
verified_fixed_media(Language, Docs) ->
    [fixed_projection(A) || A <- fixed_assets(Language),
        lists:any(fun(Doc) -> safe(fun() -> imported(A, {ok, Doc}) end) =:= true end, Docs)].

-spec fixed_media_complete(binary(), list()) -> boolean().
fixed_media_complete(Language, Media) ->
    Assets = fixed_assets(Language),
    length(Assets) =:= 29 andalso
        lists:all(fun(A) -> lists:any(fun(M) ->
            lists:all(fun({K,V}) -> get(K,M) =:= V end, element(1, fixed_projection(A)))
        end, Media) end, Assets).

-spec fixed_assets(binary()) -> list().
fixed_assets(Language) -> [A || A <- ?GEMINI_ASSETS, element(1,A) =:= Language, not digit_asset(A)].

-spec fixed_projection(tuple()) -> tuple().
fixed_projection({Language,Canonical,Prompt,Sha,_Md5,_Length,_Transcript}=A) ->
    {[{<<"id">>,media_id(A)}, {<<"name">>,Canonical}, {<<"language">>,Language},
      {<<"has_attachments">>,true}, {<<"prompt_id">>,Prompt},
      {<<"canonical_prompt_id">>,Canonical}, {<<"source_type">>,?OWNER},
      {<<"source_map_sha256">>,?GEMINI_MAP_SHA256}, {<<"sha256">>,Sha},
      {<<"import_metadata_verified">>,true}]}.

-spec asset(binary(), binary()) -> tuple() | undefined.
asset(Language, Prompt) ->
    case [A || A <- ?GEMINI_ASSETS, element(1,A) =:= Language, element(2,A) =:= Prompt] of
        [A] -> A;
        _ -> undefined
    end.

-spec media_id(tuple()) -> binary().
media_id(A) -> <<(element(1,A))/binary,"/",(element(3,A))/binary>>.

-spec imported(tuple(), any()) -> boolean().
imported({Language,Canonical,Prompt,Sha,Md5,Length,Transcript}=A, {ok,Doc}) ->
    Voice = get(<<"source_voice">>,Doc), Attachments = get(<<"_attachments">>,Doc),
    AttachmentName = <<Prompt/binary,".wav">>, Attachment = get(AttachmentName,Attachments),
    get(<<"_id">>,Doc) =:= media_id(A) andalso valid_revision(get(<<"_rev">>,Doc))
      andalso lists:member(get(<<"_deleted">>,Doc),[undefined,false])
      andalso lists:member(get(<<"pvt_deleted">>,Doc),[undefined,false])
      andalso get(<<"pvt_type">>,Doc) =:= <<"media">>
      andalso get(<<"pvt_account_db">>,Doc) =:= <<"system_media">>
      andalso get(<<"source_type">>,Doc) =:= ?OWNER
      andalso get(<<"prompt_id">>,Doc) =:= Prompt andalso get(<<"language">>,Doc) =:= Language
      andalso get(<<"content_type">>,Doc) =:= <<"audio/wav">>
      andalso get(<<"content_length">>,Doc) =:= Length andalso get(<<"streamable">>,Doc) =:= true
      andalso get(<<"provider">>,Voice) =:= <<"google-gemini">>
      andalso get(<<"model">>,Voice) =:= ?MODEL andalso get(<<"voice">>,Voice) =:= ?VOICE
      andalso get(<<"canonical_prompt_id">>,Voice) =:= Canonical
      andalso get(<<"sha256">>,Voice) =:= Sha andalso get(<<"transcript_sha256">>,Voice) =:= Transcript
      andalso keys(Attachments) =:= [AttachmentName]
      andalso get(<<"content_type">>,Attachment) =:= <<"audio/wav">>
      andalso get(<<"length">>,Attachment) =:= Length andalso get(<<"digest">>,Attachment) =:= Md5;
imported(_,_) -> false.

-spec account_override(binary(), binary()) -> custom | none | unavailable.
account_override(Account, Prompt) ->
    <<A:2/binary,B:2/binary,C/binary>> = Account,
    Db = <<"account%2F",A/binary,"%2F",B/binary,"%2F",C/binary>>,
    case kz_datamgr:open_cache_doc(Db,Prompt) of
        {ok,Doc} -> case lists:member(get(<<"pvt_deleted">>,Doc),[undefined,false]) of true -> custom; false -> account_prompt_view(Db,Prompt) end;
        {error,not_found} -> account_prompt_view(Db,Prompt);
        _ -> unavailable
    end.

-spec account_prompt_view(binary(), binary()) -> custom | none | unavailable.
account_prompt_view(Db,Prompt) ->
    %% Covers account-local localized prompt documents whose IDs differ from
    %% the canonical name. One row is enough to preserve existing resolution.
    case kz_datamgr:get_results(Db,<<"media/listing_by_prompt">>,
          [{startkey,[Prompt]},{endkey,[Prompt,{[]}]},{reduce,false},{limit,1}]) of
        {ok,[]} -> none;
        {ok,[_]} -> custom;
        _ -> unavailable
    end.

-spec read_media(binary()) -> any().
read_media(Id) -> kz_datamgr:open_cache_doc(<<"system_media">>,Id).
-spec get(binary(), any()) -> any().
get(Key,{Props}) when is_list(Props) -> proplists:get_value(Key,Props);
get(_,_) -> undefined.
-spec keys(any()) -> list().
keys({Props}) when is_list(Props) -> lists:sort([K || {K,_} <- Props]);
keys(_) -> [].
-spec safe(function()) -> any().
safe(F) -> try F() catch _:_ -> unavailable end.
-spec valid_account(any()) -> boolean().
valid_account(A) when is_binary(A) -> re:run(A,<<"^[a-f0-9]{32}$">>,[{capture,none}]) =:= match;
valid_account(_) -> false.
-spec valid_revision(any()) -> boolean().
valid_revision(R) when is_binary(R) -> re:run(R,<<"^[1-9][0-9]*-[a-f0-9]+$">>,[{capture,none}]) =:= match;
valid_revision(_) -> false.
-spec valid_digits(any()) -> boolean().
valid_digits(D) when is_binary(D),byte_size(D)>0,byte_size(D)=<15 -> re:run(D,<<"^[0-9]+$">>,[{capture,none}]) =:= match;
valid_digits(_) -> false.
-spec digit_asset(tuple()) -> boolean().
digit_asset(A) -> case element(2,A) of <<"acdc-number-",_>> -> true; _ -> false end.
