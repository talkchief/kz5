%%% SPDX-License-Identifier: MPL-2.0
%%% Immutable prerecorded wait-time defaults; account overrides stay explicit.
-module(acdc_wait_time_media).
-export([prepare/3, playlist/4]).

-spec prepare(any(), binary(), any()) -> {ok, map()} | {error, atom()}.
prepare(Language, Account, Media)
  when Language =:= <<"en-us">>; Language =:= <<"he-il">>; Language =:= <<"fr-fr">>;
       Language =:= <<"es-es">>; Language =:= <<"ar-sa">> ->
    try
        Commands = maps:from_list([{Key, resolve(Key, Language, Account, Media)} || Key <- inventory()]),
        true = valid_commands(Language, Commands),
        {ok, #{language => Language, assets => Commands}}
    catch _:_ -> {error, wait_time_media_unavailable} end;
prepare(_, _, _) -> {error, unsupported_language}.

-spec inventory() -> [binary()].
inventory() ->
    [<<"increase_in_call_volume">>, <<"the_estimated_wait_time_is">>, <<"less_than_1_minute">>,
     <<"about_5_minutes">>, <<"about_10_minutes">>, <<"about_15_minutes">>, <<"about_30_minutes">>,
     <<"about_45_minutes">>, <<"about_1_hour">>, <<"at_least_1_hour">>].

-spec resolve(binary(), binary(), binary(), any()) -> tuple().
resolve(Key, Language, Account, Media) ->
    Selection = case Key of
        <<"increase_in_call_volume">> -> acdc_gemini_prompts:selection(Key, Media);
        <<"the_estimated_wait_time_is">> -> acdc_gemini_prompts:selection(Key, Media);
        _ -> absent
    end,
    Legacy = <<"queue-", Key/binary>>, Canonical = <<"acdc-", Legacy/binary>>,
    case acdc_gemini_prompts:default_alias(Legacy, Canonical, Language, Account, Selection) of
        {gemini, Id} -> {play, <<"/system_media/", Language/binary, "/", Id/binary>>};
        {custom, Id} -> {prompt, Id, Language, <<"A">>};
        _ -> error(wait_time_media_unavailable)
    end.

%% Pure interval expansion. Invalid or incomplete audio preserves the last
%% sample, never emits a partial sentence, and performs no datastore reads.
-spec playlist(any(), any(), any(), any()) -> {list(), any()}.
playlist(Average, Last, Language, #{language := Language, assets := Commands})
  when is_integer(Average), Average >= 0 ->
    case valid_commands(Language, Commands) of
        true ->
            Increase = case is_integer(Last) andalso Average > Last of
                true -> [maps:get(<<"increase_in_call_volume">>, Commands)]; false -> [] end,
            {Increase ++ [maps:get(<<"the_estimated_wait_time_is">>, Commands), maps:get(bucket(Average), Commands)], Average};
        false -> {[], Last}
    end;
playlist(_, Last, _, _) -> {[], Last}.

-spec valid_commands(any(), any()) -> boolean().
valid_commands(Language, Commands) when is_map(Commands) ->
    lists:member(Language, [<<"en-us">>, <<"he-il">>, <<"fr-fr">>, <<"es-es">>, <<"ar-sa">>])
        andalso lists:sort(maps:keys(Commands)) =:= lists:sort(inventory())
        andalso lists:all(fun(Command) -> valid_command(Language, Command) end, maps:values(Commands));
valid_commands(_, _) -> false.

-spec valid_command(binary(), any()) -> boolean().
valid_command(Language, {play, Path}) when is_binary(Path) ->
    Prefix = <<"/system_media/", Language/binary, "/">>, Size = byte_size(Prefix),
    case Path of <<Prefix:Size/binary, Id/binary>> when byte_size(Id) > 0 -> binary:match(Id, <<"/">>) =:= nomatch;
        _ -> false end;
valid_command(Language, {prompt, Id, Language, <<"A">>}) when is_binary(Id), byte_size(Id) > 0, byte_size(Id) =< 2048 -> true;
valid_command(_, _) -> false.

-spec bucket(non_neg_integer()) -> binary().
bucket(Time) when Time < 60 -> <<"less_than_1_minute">>;
bucket(Time) when Time =< 300 -> <<"about_5_minutes">>;
bucket(Time) when Time =< 600 -> <<"about_10_minutes">>;
bucket(Time) when Time =< 900 -> <<"about_15_minutes">>;
bucket(Time) when Time =< 1800 -> <<"about_30_minutes">>;
bucket(Time) when Time =< 2700 -> <<"about_45_minutes">>;
bucket(Time) when Time =< 3600 -> <<"about_1_hour">>;
bucket(_) -> <<"at_least_1_hour">>.
