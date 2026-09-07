%%% SPDX-License-Identifier: MPL-2.0
-module(acdc_cardinal_prompts_tests).
-include_lib("eunit/include/eunit.hrl").

english_golden_test() ->
    Cases = [{0, [<<"number-0">>]}
            ,{1, [<<"number-1">>]}
            ,{19, [<<"number-19">>]}
            ,{20, [<<"number-20">>]}
            ,{21, [<<"number-20">>, <<"number-1">>]}
            ,{100, [<<"number-1">>, <<"hundred">>]}
            ,{101, [<<"number-1">>, <<"hundred">>, <<"number-1">>]}
            ,{110, [<<"number-1">>, <<"hundred">>, <<"number-10">>]}
            ,{999, [<<"number-9">>, <<"hundred">>, <<"number-90">>, <<"number-9">>]}
            ,{1000, [<<"number-1">>, <<"thousand">>]}
            ,{1001, [<<"number-1">>, <<"thousand">>, <<"number-1">>]}
            ,{1010, [<<"number-1">>, <<"thousand">>, <<"number-10">>]}
            ,{101001, [<<"number-1">>, <<"hundred">>, <<"number-1">>, <<"thousand">>, <<"number-1">>]}
            ,{1000000, [<<"number-1">>, <<"million">>]}
            ,{1000001, [<<"number-1">>, <<"million">>, <<"number-1">>]}
            ,{1001001, [<<"number-1">>, <<"million">>, <<"number-1">>, <<"thousand">>, <<"number-1">>]}],
    lists:foreach(fun({Number, Expected}) ->
        ?assertEqual({'ok', [<<"acdc-cardinal-v1-", Role/binary>> || Role <- Expected]}
                    ,acdc_cardinal_prompts:roles(Number, <<"en-us">>))
    end, Cases).

maximum_role_count_test() ->
    {ok, Roles} = acdc_cardinal_prompts:roles(999999999, <<"en-us">>),
    ?assertEqual(14, length(Roles)),
    ?assertEqual(999999999, numeric_value(Roles)).

invalid_numbers_fail_closed_test() ->
    lists:foreach(fun(Number) ->
        ?assertEqual({error, invalid_number}, acdc_cardinal_prompts:roles(Number, <<"en-us">>))
    end, [-1, 1000000000, 1 bsl 100, 0.0, 1.5, <<"1">>, "1", undefined, true, [], #{}]).

other_locales_never_fall_back_test() ->
    lists:foreach(fun(Language) ->
        ?assertEqual({error, unsupported_language}, acdc_cardinal_prompts:roles(123, Language)),
        ?assertEqual({error, unsupported_language}, acdc_cardinal_prompts:roles(0, Language))
    end, [<<"en">>, <<"EN">>, <<"EN-US">>, <<"en_us">>, <<"en-gb">>, <<"fr-fr">>,
          <<"es-es">>, <<"he-il">>, <<"ar-sa">>, <<>>, undefined, null, 'en-us', "en-us", #{}]).

catalog_parity_test_() ->
    {timeout, 60, fun() ->
        {ok, Cases} = file:consult(os:getenv("KAZOO_CARDINAL_PARITY_FIXTURE")),
        %% 3000 exhaustive group/scale cases +22^3 boundary products +1000 mixed.
        ?assertEqual(14648, length(Cases)),
        lists:foreach(fun({Number, Expected}) ->
            {ok, Roles} = acdc_cardinal_prompts:roles(Number, <<"en-us">>),
            ?assertEqual(Expected, Roles),
            ?assert(length(Roles) >= 1 andalso length(Roles) =< 14),
            ?assert(lists:all(fun is_catalog_role/1, Roles)),
            ?assertEqual(Number, numeric_value(Roles))
        end, Cases)
    end}.

is_catalog_role(<<"acdc-cardinal-v1-number-", Digits/binary>>) ->
    Value = binary_to_integer(Digits),
    (Value >= 0 andalso Value =< 19)
        orelse (Value >= 20 andalso Value =< 90 andalso Value rem 10 =:= 0);
is_catalog_role(<<"acdc-cardinal-v1-hundred">>) -> true;
is_catalog_role(<<"acdc-cardinal-v1-thousand">>) -> true;
is_catalog_role(<<"acdc-cardinal-v1-million">>) -> true;
is_catalog_role(_) -> false.

%% Independent arithmetic interpretation of emitted roles, not decimal splitting.
numeric_value(Roles) -> numeric_value(Roles, 0, 0, 1000000000).
numeric_value([], Total, Group, _) -> Total + Group;
numeric_value([<<"acdc-cardinal-v1-number-", Digits/binary>> | Rest], Total, Group, PreviousScale) ->
    numeric_value(Rest, Total, Group + binary_to_integer(Digits), PreviousScale);
numeric_value([<<"acdc-cardinal-v1-hundred">> | Rest], Total, Group, PreviousScale) ->
    ?assert(Group >= 1 andalso Group =< 9),
    numeric_value(Rest, Total, Group * 100, PreviousScale);
numeric_value([Role | Rest], Total, Group, PreviousScale) ->
    Scale = case Role of
                <<"acdc-cardinal-v1-thousand">> -> 1000;
                <<"acdc-cardinal-v1-million">> -> 1000000
            end,
    ?assert(Scale < PreviousScale andalso Group > 0 andalso Group < 1000),
    numeric_value(Rest, Total + Group * Scale, 0, Scale).
