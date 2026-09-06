%%% SPDX-License-Identifier: MPL-2.0
%%% Fixed ACDC language-pack helpers. Arabic and Hebrew have no usable bundled
%%% FreeSWITCH say/audio combination, so numeric playback uses verified prompt
%%% chunks rather than falling back to English or an unrelated say module.
-module(acdc_language).

-export([canonical/1, bundled/1, default_prompt/2, number_prompts/2
        ,telephone_prompts/2, media_available/2, callback_available/1]).

-spec canonical(any()) -> binary().
canonical('undefined') -> <<"en-us">>;
canonical(Language) when is_binary(Language) ->
    binary:replace(kz_term:to_lower_binary(Language), <<"_">>, <<"-">>, ['global']);
canonical(_) -> <<>>.

-spec bundled(any()) -> boolean().
bundled(Language) ->
    lists:member(canonical(Language), [<<"en-us">>, <<"ar-sa">>, <<"he-il">>
                                      ,<<"es-es">>, <<"fr-fr">>]).

-spec default_prompt(binary(), any()) -> binary().
default_prompt(<<"queue-", _/binary>>=Prompt, Language) ->
    case bundled(Language) of
        'true' -> <<"acdc-", Prompt/binary>>;
        'false' -> Prompt
    end;
default_prompt(Prompt, _) -> Prompt.

-spec recorded_numbers(binary()) -> boolean().
recorded_numbers(<<"ar-sa">>) -> 'true';
recorded_numbers(<<"he-il">>) -> 'true';
recorded_numbers(_) -> 'false'.

-spec number_prompts(non_neg_integer(), any()) -> list().
number_prompts(Number, Language0)
  when is_integer(Number), Number >= 0, Number =< 999999999 ->
    Language = canonical(Language0),
    case recorded_numbers(Language) of
        'false' -> [{'say', integer_to_binary(Number), <<"number">>}];
        'true' -> [number_prompt(Value, Language) || Value <- number_groups(Number)]
    end;
number_prompts(_, _) -> [].

-spec number_groups(non_neg_integer()) -> list().
number_groups(0) -> [0];
number_groups(Number) ->
    Groups = [Value || Value <- [(Number div 1000000) * 1000000
                                ,((Number rem 1000000) div 1000) * 1000
                                ,Number rem 1000], Value > 0],
    lists:join('and', Groups).

-spec number_prompt(non_neg_integer() | 'and', binary()) -> tuple().
number_prompt('and', Language) ->
    {'prompt', <<"acdc-number-and">>, Language, <<"A">>};
number_prompt(Number, Language) ->
    {'prompt', <<"acdc-number-", (integer_to_binary(Number))/binary>>, Language, <<"A">>}.

-spec telephone_prompts(binary(), any()) -> list().
telephone_prompts(Digits, Language0) when is_binary(Digits), byte_size(Digits) > 0 ->
    Language = canonical(Language0),
    case valid_digits(Digits) of
        'false' -> [];
        'true' ->
            case recorded_numbers(Language) of
                'false' -> [{'say', Digits, <<"telephone_number">>}];
                'true' -> [number_prompt(Digit - $0, Language) || <<Digit>> <= Digits]
            end
    end;
telephone_prompts(_, _) -> [].

-spec valid_digits(binary()) -> boolean().
valid_digits(<<>>) -> 'true';
valid_digits(<<Digit, Rest/binary>>) when Digit >= $0, Digit =< $9 -> valid_digits(Rest);
valid_digits(_) -> 'false'.

%% The installer verifies complete packs before publishing UI capability data.
%% Callback defaults additionally require their actual localized documents at
%% use time. Custom media IDs are still handled by the account's normal lookup.
-spec callback_available(any()) -> boolean().
callback_available(Language0) ->
    Language = canonical(Language0),
    Fixed = [<<"acdc-callback-offer-", (integer_to_binary(Key))/binary>> || Key <- lists:seq(0, 9)]
        ++ [<<"acdc-callback-menu-current">>, <<"acdc-callback-menu-alternate">>
           ,<<"acdc-callback-number-readback">>, <<"acdc-callback-confirmation">>
           ,<<"acdc-callback-success">>, <<"acdc-callback-returned-confirmation">>],
    Digits = case recorded_numbers(Language) of
                 'true' -> [<<"acdc-number-", (integer_to_binary(N))/binary>> || N <- lists:seq(0, 9)];
                 'false' -> []
             end,
    bundled(Language) andalso media_available(Language, Fixed ++ Digits).

-spec media_available(any(), [binary()]) -> boolean().
media_available(Language0, Prompts) ->
    Language = canonical(Language0),
    bundled(Language) andalso lists:all(fun(Prompt) -> installed_prompt(Language, Prompt) end, Prompts).

-spec installed_prompt(binary(), binary()) -> boolean().
installed_prompt(Language, Prompt) ->
    Id = <<Language/binary, "/", Prompt/binary>>,
    try kz_datamgr:open_cache_doc(<<"system_media">>, Id) of
        {'ok', Doc} ->
            kz_doc:id(Doc) =:= Id
                andalso not kz_doc:is_deleted(Doc)
                andalso not kz_doc:is_soft_deleted(Doc)
                andalso lists:any(fun(Name) -> kz_doc:attachment_length(Doc, Name, 0) > 0 end
                                  ,kz_doc:attachment_names(Doc));
        _ -> 'false'
    catch
        _:_ -> 'false'
    end.
