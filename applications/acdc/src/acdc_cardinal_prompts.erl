%%% SPDX-License-Identifier: MPL-2.0
%%% Pure English cardinal composition for the prerecorded acdc-cardinal-v1
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
