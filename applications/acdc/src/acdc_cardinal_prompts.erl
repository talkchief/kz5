%%% SPDX-License-Identifier: MPL-2.0
%%% Pure five-language cardinal composition for the prerecorded acdc-cardinal-v1
%%% catalog. This is grammar only, not an assertion of installed media.
%%% No datastore, provider, native SAY, digit spelling or locale fallback.
-module(acdc_cardinal_prompts).

-export([roles/2]).

-define(MAX_NUMBER, 999999999).
-define(MAX_ROLES, 14).

-spec roles(any(), any()) -> {'ok', [binary()]}
                          | {'error', 'invalid_number' | 'unsupported_language'}.
roles(Number, _Language)
  when not is_integer(Number); Number < 0; Number > ?MAX_NUMBER ->
    {'error', 'invalid_number'};
roles(0, <<"en-us">>) -> {'ok', [number_role(0)]};
roles(Number, <<"en-us">>) ->
    Roles = scaled_group(Number div 1000000, <<"acdc-cardinal-v1-million">>)
        ++ scaled_group((Number rem 1000000) div 1000, <<"acdc-cardinal-v1-thousand">>)
        ++ group(Number rem 1000),
    %% Each three-digit group needs at most four roles; two scales make14.
    true = length(Roles) >= 1 andalso length(Roles) =< ?MAX_ROLES,
    {'ok', Roles};
roles(Number, <<"es-es">>) -> canonical_roles(spanish(Number), 14);
roles(Number, <<"fr-fr">>) -> canonical_roles(french(Number), 8);
roles(Number, <<"he-il">>) -> canonical_roles(hebrew(Number), 11);
roles(Number, <<"ar-sa">>) -> canonical_roles(arabic(Number), 9);
roles(_, _) -> {'error', 'unsupported_language'}.

-spec scaled_group(non_neg_integer(), binary()) -> [binary()].
scaled_group(0, _) -> [];
scaled_group(Number, Scale) -> group(Number) ++ [Scale].

-spec group(non_neg_integer()) -> [binary()].
group(Number) when Number >= 100 ->
    [number_role(Number div 100), <<"acdc-cardinal-v1-hundred">> | group(Number rem 100)];
group(Number) when Number >= 20 ->
    [number_role((Number div 10) * 10) | group(Number rem 10)];
group(0) -> [];
group(Number) -> [number_role(Number)].

-spec number_role(non_neg_integer()) -> binary().
number_role(Number) -> <<"acdc-cardinal-v1-number-", (integer_to_binary(Number))/binary>>.

-spec canonical_roles([binary()], pos_integer()) -> {ok, [binary()]}.
canonical_roles(Roles, Maximum) ->
    true = length(Roles) >= 1 andalso length(Roles) =< Maximum,
    {ok, [<<"acdc-cardinal-v1-", Role/binary>> || Role <- Roles]}.

-spec role(binary(), non_neg_integer()) -> binary().
role(Prefix, Number) -> <<Prefix/binary, "-", (integer_to_binary(Number))/binary>>.

-spec scaled_groups(non_neg_integer()) -> [{pos_integer(), non_neg_integer()}].
scaled_groups(Number) ->
    [{Scale, (Number div Scale) rem 1000} || Scale <- [1000000, 1000, 1]].

%% Spanish apocope is applied only to coefficients preceding a scale. The
%% coefficient one is omitted for mil, but retained as un in un millon.
-spec spanish(non_neg_integer()) -> [binary()].
spanish(0) -> [<<"number-0">>];
spanish(Number) ->
    lists:append([spanish_scaled(Coefficient, Scale)
                  || {Scale, Coefficient} <- scaled_groups(Number), Coefficient > 0]).

-spec spanish_scaled(pos_integer(), pos_integer()) -> [binary()].
spanish_scaled(1, 1000) -> [<<"thousand">>];
spanish_scaled(Coefficient, Scale) ->
    spanish_group(Coefficient, Scale =/= 1) ++ scale_role(Coefficient, Scale).

-spec scale_role(pos_integer(), pos_integer()) -> [binary()].
scale_role(_, 1) -> [];
scale_role(_, 1000) -> [<<"thousand">>];
scale_role(1, 1000000) -> [<<"million">>];
scale_role(_, 1000000) -> [<<"millions">>].

-spec spanish_group(pos_integer(), boolean()) -> [binary()].
spanish_group(Number, BeforeScale) ->
    Hundreds = Number div 100,
    Rest = Number rem 100,
    Prefix = case {Hundreds, Rest} of
                 {0, _} -> [];
                 {1, Remainder} when Remainder > 0 -> [<<"hundred-continuation">>];
                 _ -> [role(<<"number">>, Hundreds * 100)]
             end,
    Prefix ++ case Rest of
                  N when N >= 30 ->
                      [role(<<"number">>, (N div 10) * 10)] ++
                          case N rem 10 of
                              0 -> [];
                              Unit -> [<<"and">>, spanish_small(Unit, BeforeScale)]
                          end;
                  0 -> [];
                  N -> [spanish_small(N, BeforeScale)]
              end.

-spec spanish_small(pos_integer(), boolean()) -> binary().
spanish_small(Number, true) when Number =:= 1; Number =:= 21 -> role(<<"before-scale">>, Number);
spanish_small(Number, _) -> role(<<"number">>, Number).

%% Context-sensitive French scaled tails are whole recordings, including the
%% scale. Do not append another scale or derive liaison by editing WAVs.
-spec french(non_neg_integer()) -> [binary()].
french(0) -> [<<"terminal-0">>];
french(Number) ->
    lists:append([french_group(Coefficient, Scale)
                  || {Scale, Coefficient} <- scaled_groups(Number), Coefficient > 0]).

-spec french_group(pos_integer(), pos_integer()) -> [binary()].
french_group(1, 1000) -> [<<"thousand">>];
french_group(Number, Scale) ->
    Hundreds = Number div 100,
    Rest = Number rem 100,
    case Hundreds > 0 andalso Rest =:= 1 of
        true -> [role(<<"hundred-one">>, Hundreds)] ++ scale_role(Number, Scale);
        false ->
            Prefix = case Hundreds of 0 -> []; _ -> [role(<<"hundreds">>, Hundreds)] end,
            case Scale =/= 1 andalso french_scaled_tail(Rest) of
                true -> Prefix ++ [role(role(<<"scaled-tail">>, Scale), Rest)];
                false ->
                    Prefix ++ case Rest of 0 -> []; _ -> [role(<<"terminal">>, Rest)] end
                        ++ scale_role(Number, Scale)
            end
    end.

-spec french_scaled_tail(non_neg_integer()) -> boolean().
french_scaled_tail(Number) ->
    lists:member(Number, [6, 8, 10, 18, 26, 28, 36, 38, 46, 48,
                         56, 58, 66, 68, 70, 78, 86, 88, 90, 98]).

%% Hebrew uses the reviewed abstract-number-label feminine context. Scale
%% coefficients are masculine and singular/dual scales are whole phrases.
%% Only the final additive atom receives its attached-conjunction recording.
-spec hebrew(non_neg_integer()) -> [binary()].
hebrew(0) -> [<<"number-0">>];
hebrew(Number) ->
    ScaleAtoms = [hebrew_scale(Coefficient, Scale)
                  || {Scale, Coefficient} <- scaled_groups(Number), Scale > 1, Coefficient > 0],
    hebrew_add(ScaleAtoms ++ hebrew_atoms(Number rem 1000, <<"feminine">>)).

-spec hebrew_atoms(non_neg_integer(), binary()) -> [[binary()]].
hebrew_atoms(Number, Gender) ->
    Hundreds = Number div 100,
    Rest = Number rem 100,
    Prefix = case Hundreds of 0 -> []; _ -> [[role(<<"hundreds">>, Hundreds * 100)]] end,
    Prefix ++ case Rest of
                  N when N >= 20 ->
                      [[role(<<"tens">>, (N div 10) * 10)]] ++
                          case N rem 10 of 0 -> []; Unit -> [[role(Gender, Unit)]] end;
                  0 -> [];
                  N -> [[role(Gender, N)]]
              end.

-spec hebrew_add([[binary()]]) -> [binary()].
hebrew_add([]) -> [];
hebrew_add([Only]) -> Only;
hebrew_add(Atoms) ->
    [Last | ReversedPrefix] = lists:reverse(Atoms),
    [First | Rest] = Last,
    lists:append(lists:reverse(ReversedPrefix)) ++ [<<"joined-", First/binary>> | Rest].

-spec hebrew_scale(pos_integer(), pos_integer()) -> [binary()].
hebrew_scale(Coefficient, 1000) when Coefficient =< 10 -> [role(<<"thousands">>, Coefficient)];
hebrew_scale(1, 1000000) -> [<<"million">>];
hebrew_scale(2, 1000000) -> [<<"two-million">>];
hebrew_scale(Coefficient, Scale) ->
    hebrew_add(hebrew_atoms(Coefficient, <<"masculine">>)) ++
        [case Scale of 1000 -> <<"thousands-1">>; 1000000 -> <<"million">> end].

%% Arabic uses whole pausal scale phrases in the reviewed masculine number
%% label context. Hundreds and remaining scaled groups are explicit sums;
%% units precede tens, and all but the first recording include the conjunction.
-spec arabic(non_neg_integer()) -> [binary()].
arabic(0) -> [<<"number-0">>];
arabic(Number) ->
    [First | Rest] = lists:append([arabic_group(Coefficient, Scale)
                                  || {Scale, Coefficient} <- scaled_groups(Number)]),
    [First | [<<"joined-", Role/binary>> || Role <- Rest]].

-spec arabic_group(non_neg_integer(), pos_integer()) -> [binary()].
arabic_group(Number, Scale) ->
    Hundreds = (Number div 100) * 100,
    Rest = Number rem 100,
    Prefix = case Hundreds of 0 -> []; _ -> [arabic_scaled(Hundreds, Scale, <<"hundred">>)] end,
    Prefix ++ case Rest of
                  N when N >= 20 ->
                      (case N rem 10 of 0 -> []; Unit -> [role(<<"number">>, Unit)] end)
                          ++ [arabic_scaled((N div 10) * 10, Scale, <<"decade">>)];
                  0 -> [];
                  N -> [arabic_scaled(N, Scale, <<"small">>)]
              end.

-spec arabic_scaled(pos_integer(), pos_integer(), binary()) -> binary().
arabic_scaled(Number, 1, _) -> role(<<"number">>, Number);
arabic_scaled(Number, Scale, Kind) ->
    role(<<(role(<<"scale">>, Scale))/binary, "-", Kind/binary>>, Number).
