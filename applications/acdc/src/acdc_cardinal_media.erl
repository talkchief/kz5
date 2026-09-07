%%% SPDX-License-Identifier: MPL-2.0
%%% Immutable prerecorded cardinal playback. No provider, SAY or locale fallback.
-module(acdc_cardinal_media).
-export([prepare/3, playlist/3]).
-ifdef(TEST).
-export([prepare_with/6, frame/3]).
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
prepare_with(<<"en-us">> = Language, Account, Media, Assets, Read, Frame) ->
    try
        Expected = expected_roles(),
        Selected = [A || A <- Assets, element(1, A) =:= Language],
        true = lists:sort([element(2, A) || A <- Selected]) =:= Expected,
        {ok, Before, After} = Frame(Language, Account, Media),
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

-spec expected_roles() -> [binary()].
expected_roles() ->
    lists:sort([<<"acdc-cardinal-v1-number-", (integer_to_binary(N))/binary>>
                || N <- lists:seq(0, 19) ++ lists:seq(20, 90, 10)]
               ++ [<<"acdc-cardinal-v1-hundred">>, <<"acdc-cardinal-v1-thousand">>,
                   <<"acdc-cardinal-v1-million">>]).

-spec frame(binary(), binary(), any()) -> tuple().
frame(Language, Account, Media) ->
    Prefix = acdc_gemini_prompts:default_alias(<<"queue-you_are_at_position">>,
                 <<"acdc-queue-you_are_at_position">>, Language, Account,
                 acdc_gemini_prompts:selection(<<"you_are_at_position">>, Media)),
    Suffix = acdc_gemini_prompts:default_alias(<<"queue-in_the_queue">>,
                 <<"acdc-queue-in_the_queue">>, Language, Account,
                 acdc_gemini_prompts:selection(<<"in_the_queue">>, Media)),
    case {Prefix, Suffix} of
        {{gemini, _}, {gemini, _}} ->
            %% The approved combined intro can itself have an account override.
            {Intro, TranscriptSha, WavSha} = ?CARDINAL_EN_INTRO,
            [_] = [A || A <- ?GEMINI_ASSETS, element(1, A) =:= Language,
                       element(2, A) =:= Intro, element(4, A) =:= WavSha,
                       element(7, A) =:= TranscriptSha],
            IntroResult = acdc_gemini_prompts:default(Intro, Language, Account, absent),
            {ok, [resolved(IntroResult, Language)], []};
        _ -> {ok, [resolved(Prefix, Language)], [resolved(Suffix, Language)]}
    end.

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
  when is_integer(Position), Position > 0 ->
    case acdc_cardinal_prompts:roles(Position, Language) of
        {ok, Roles} ->
            case lists:all(fun(Role) -> maps:is_key(Role, Paths) end, Roles) of
                true -> Before ++ [{play, maps:get(Role, Paths)} || Role <- Roles] ++ After;
                false -> []
            end;
        _ -> []
    end;
playlist(_, _, _) -> [].
