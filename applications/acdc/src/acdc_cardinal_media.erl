%%% SPDX-License-Identifier: MPL-2.0
%%% Immutable prerecorded cardinal playback. No provider, SAY or locale fallback.
-module(acdc_cardinal_media).
-export([prepare/3, playlist/3]).
-ifdef(TEST).
-export([prepare_with/6, frame/3, frame_with/5, expected_roles/1, intro/1]).
-endif.
-include("acdc_cardinal_map.hrl").
-include("acdc_gemini_map.hrl").

-spec prepare(any(), binary(), any()) -> {ok, map()} | {error, atom()}.
prepare(Language, Account, Media) ->
    prepare_with(Language, Account, Media, ?CARDINAL_ASSETS,
                 fun(Id) -> kz_datamgr:open_cache_doc(<<"system_media">>, Id) end,
                 fun frame/3).

%% Resolve once when the announcement worker starts, never at each interval.
%% A missing document cannot produce a partial number or native speech fallback.
-spec prepare_with(any(), binary(), any(), list(), function(), function()) -> tuple().
prepare_with(Language, Account, Media, Assets, Read, Frame)
  when Language =:= <<"en-us">>; Language =:= <<"es-es">>; Language =:= <<"fr-fr">>;
       Language =:= <<"he-il">>; Language =:= <<"ar-sa">> ->
    try
        Expected = expected_roles(Language),
        Selected = [A || A <- Assets, element(1, A) =:= Language],
        true = lists:sort([element(2, A) || A <- Selected]) =:= Expected,
        {ok, Before, After} = Frame(Language, Account, Media),
        true = valid_frame(Before, After, Language),
        true = lists:all(fun(A) ->
            acdc_gemini_prompts:verified_asset(A, Read(document_id(A)))
        end, Selected),
        Paths = maps:from_list([{element(2, A), path(Language, element(3, A))}
                               || A <- Selected]),
        {ok, #{language => Language, assets => Paths,
               before_number => Before, after_number => After}}
    catch _:_ -> {error, cardinal_media_unavailable}
    end;
prepare_with(_, _, _, _, _, _) -> {error, unsupported_language}.

-spec expected_roles(binary()) -> [binary()].
expected_roles(Language) ->
    lists:sort([<<"acdc-cardinal-v1-", Role/binary>> || Role <- inventory(Language)]).

%% Finite catalog inventory, independently listed rather than inferred from
%% whichever media happens to be installed. No runtime synthesis or enumeration
%% of the full numeric range is needed for preflight.
-spec inventory(binary()) -> [binary()].
inventory(<<"en-us">>) ->
    series(<<"number">>, lists:seq(0, 19) ++ lists:seq(20, 90, 10))
        ++ [<<"hundred">>, <<"thousand">>, <<"million">>];
inventory(<<"es-es">>) ->
    series(<<"number">>, lists:seq(0, 29) ++ lists:seq(30, 90, 10) ++ lists:seq(100, 900, 100))
        ++ [<<"hundred-continuation">>, <<"before-scale-1">>, <<"before-scale-21">>,
            <<"and">>, <<"thousand">>, <<"million">>, <<"millions">>];
inventory(<<"fr-fr">>) ->
    series(<<"terminal">>, lists:seq(0, 99))
        ++ series(<<"hundreds">>, lists:seq(1, 9))
        ++ series(<<"hundred-one">>, lists:seq(1, 9))
        ++ lists:append([series(<<"scaled-tail-", (integer_to_binary(S))/binary>>,
            [6, 8, 10, 18, 26, 28, 36, 38, 46, 48, 56, 58, 66, 68, 70, 78, 86, 88, 90, 98])
            || S <- [1000, 1000000]])
        ++ [<<"thousand">>, <<"million">>, <<"millions">>];
inventory(<<"he-il">>) ->
    [<<"number-0">>, <<"million">>, <<"two-million">>]
        ++ series(<<"masculine">>, lists:seq(3, 19))
        ++ series(<<"joined-masculine">>, lists:seq(1, 19))
        ++ pairs(series(<<"feminine">>, lists:seq(1, 19))
                 ++ series(<<"tens">>, lists:seq(20, 90, 10))
                 ++ series(<<"hundreds">>, lists:seq(100, 900, 100))
                 ++ series(<<"thousands">>, lists:seq(1, 10)));
inventory(<<"ar-sa">>) ->
    [<<"number-0">>] ++ pairs(series(<<"number">>,
        lists:seq(1, 19) ++ lists:seq(20, 90, 10) ++ lists:seq(100, 900, 100)))
        ++ lists:append([pairs(series(<<"scale-", (integer_to_binary(S))/binary, "-small">>, lists:seq(1, 19))
                              ++ series(<<"scale-", (integer_to_binary(S))/binary, "-decade">>, lists:seq(20, 90, 10)))
                         || S <- [1000, 1000000]])
        ++ pairs(series(<<"scale-1000-hundred">>, lists:seq(100, 900, 100)))
        ++ series(<<"scale-1000000-hundred">>, lists:seq(100, 900, 100));
inventory(_) -> [].

-spec series(binary(), [non_neg_integer()]) -> [binary()].
series(Prefix, Numbers) -> [<<Prefix/binary, "-", (integer_to_binary(N))/binary>> || N <- Numbers].

-spec pairs([binary()]) -> [binary()].
pairs(Roles) -> Roles ++ [<<"joined-", Role/binary>> || Role <- Roles].

-spec frame(binary(), binary(), any()) -> tuple().
frame(Language, Account, Media) ->
    %% The current compiled cardinal map remains EN-only. New intro tuples must
    %% be deliberately added to this inventory when complete maps are admitted;
    %% they never replace or extend the fixed210 map by implication.
    frame_with(Language, Account, Media, ?GEMINI_ASSETS,
        fun(Id) -> kz_datamgr:open_cache_doc(<<"system_media">>, Id) end).

-spec frame_with(binary(), binary(), any(), list(), function()) -> tuple().
frame_with(Language, Account, Media, IntroAssets, Read)
  when Language =:= <<"en-us">>; Language =:= <<"es-es">>; Language =:= <<"fr-fr">>;
       Language =:= <<"he-il">>; Language =:= <<"ar-sa">> ->
    try
        {ok, Before, After} = frame_verified(Language, Account, Media, IntroAssets, Read),
        true = valid_frame(Before, After, Language),
        {ok, Before, After}
    catch _:_ -> {error, cardinal_media_unavailable}
    end;
frame_with(_, _, _, _, _) -> {error, unsupported_language}.

-spec frame_verified(binary(), binary(), any(), list(), function()) -> tuple().
frame_verified(Language, Account, Media, IntroAssets, Read) ->
    Prefix = acdc_gemini_prompts:default_alias(<<"queue-you_are_at_position">>,
                 <<"acdc-queue-you_are_at_position">>, Language, Account,
                 acdc_gemini_prompts:selection(<<"you_are_at_position">>, Media)),
    Suffix = acdc_gemini_prompts:default_alias(<<"queue-in_the_queue">>,
                 <<"acdc-queue-in_the_queue">>, Language, Account,
                 acdc_gemini_prompts:selection(<<"in_the_queue">>, Media)),
    case {Prefix, Suffix} of
        {{gemini, _}, {gemini, _}} ->
            %% The approved combined intro can itself have an account override.
            {Intro, TranscriptSha, WavSha} = intro(Language),
            %% Select identity before checking pins: an extra conflicting tuple
            %% cannot hide merely because it has the wrong bytes or transcript.
            [IntroAsset] = [A || A <- IntroAssets, element(1, A) =:= Language,
                               element(2, A) =:= Intro],
            WavSha = element(4, IntroAsset),
            TranscriptSha = element(7, IntroAsset),
            IntroResult = acdc_gemini_prompts:default(Intro, Language, Account, absent),
            Resolved = case IntroResult of
                {custom, _} -> resolved(IntroResult, Language);
                _ ->
                    true = acdc_gemini_prompts:verified_asset(IntroAsset, Read(document_id(IntroAsset))),
                    verified_intro(IntroResult, IntroAsset, Language)
            end,
            {ok, [Resolved], []};
        _ -> {ok, [resolved(Prefix, Language)], [resolved(Suffix, Language)]}
    end.

%% default/4 checks the account override before its fixed-map lookup. Only the
%% precise unsupported-prompt result means a successful no-override lookup for
%% the newly versioned HE/AR intro absent from fixed210. All other errors fail.
-spec verified_intro(tuple(), tuple(), binary()) -> tuple().
verified_intro({gemini, Id}, Asset, Language) when Id =:= element(3, Asset) ->
    {play, path(Language, Id)};
verified_intro({error, unsupported_gemini_prompt}, Asset, Language)
  when Language =:= <<"he-il">>; Language =:= <<"ar-sa">> ->
    {play, path(Language, element(3, Asset))}.

-spec intro(binary()) -> {binary(), binary(), binary()}.
intro(<<"en-us">>) -> ?CARDINAL_EN_INTRO;
intro(<<"es-es">>) ->
    {<<"acdc-queue-your-current-position-is">>,
     <<"a3c7ef71bec8c1c0db48b96ebbf59f4733cce242df4c30384b216b8fcf831bd9">>,
     <<"4753cdfe28956fa8ea620508984041b30ab7fb781845c9f80b565e2662f216d4">>};
intro(<<"fr-fr">>) ->
    {<<"acdc-queue-your-current-position-is">>,
     <<"e5613b3e9cb8b84efc9081c6876fe28815eec069d9b27866d96c25503b09cca0">>,
     <<"7ed7292b5feac6a03881c958532d2f9150d39ea4ca7ecf9d1d11385f10be6b2c">>};
intro(<<"he-il">>) ->
    {<<"acdc-cardinal-intro-v1-current-position-number">>,
     <<"3546259e51a69a94ea84d3c3ba28d8b9105397ae0830599cc2b7301a0fb7a2d1">>,
     <<"e688f91fc0e23f4926a9be5d87ecc993042389eb895e7f10a602137d4e8ad944">>};
intro(<<"ar-sa">>) ->
    {<<"acdc-cardinal-intro-v1-current-position-number">>,
     <<"a90d20b338dcafa924d45f03364399aca462df3fce7de1924397097ee0e2166f">>,
     <<"312fb7ff3cc60bd2a378027978679302716136504f5ddaf8a3220f6fca2b8598">>}.

-spec valid_frame(any(), any(), binary()) -> boolean().
valid_frame(Before, After, Language) when is_list(Before), is_list(After), Before =/= [] ->
    lists:all(fun(Command) -> valid_command(Command, Language) end, Before ++ After);
valid_frame(_, _, _) -> false.

-spec valid_command(any(), binary()) -> boolean().
valid_command({play, Path}, Language) when is_binary(Path) ->
    Prefix = <<"/system_media/", Language/binary, "/">>,
    Size = byte_size(Prefix),
    case Path of
        <<Prefix:Size/binary, Id/binary>> when byte_size(Id) > 0 -> binary:match(Id, <<"/">>) =:= nomatch;
        _ -> false
    end;
valid_command({prompt, Id, Language, <<"A">>}, Language) when is_binary(Id), byte_size(Id) > 0 -> true;
valid_command(_, _) -> false.

-spec resolved(tuple(), binary()) -> tuple().
resolved({gemini, Id}, Language) -> {play, path(Language, Id)};
resolved({custom, Id}, Language) -> {prompt, Id, Language, <<"A">>}.

-spec document_id(tuple()) -> binary().
document_id(A) -> <<(element(1, A))/binary, "/", (element(3, A))/binary>>.

-spec path(binary(), binary()) -> binary().
path(Language, Id) -> <<"/system_media/", Language/binary, "/", Id/binary>>.

-spec playlist(any(), any(), any()) -> list().
playlist(Position, Language, #{language := Language, assets := Paths,
                              before_number := Before, after_number := After})
  when is_integer(Position), Position > 0, is_map(Paths), is_list(Before), is_list(After) ->
    case acdc_cardinal_prompts:roles(Position, Language) of
        {ok, Roles} ->
            case lists:all(fun(Role) -> maps:is_key(Role, Paths) end, Roles) of
                true ->
                    Numbers = [{play, maps:get(Role, Paths)} || Role <- Roles],
                    case valid_frame(Before, After, Language) andalso
                        lists:all(fun(Command) -> valid_command(Command, Language) end, Numbers) of
                        true -> Before ++ Numbers ++ After;
                        false -> []
                    end;
                false -> []
            end;
        _ -> []
    end;
playlist(_, _, _) -> [].
