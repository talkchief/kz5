%%% Pure, bounded queue selection. The manager supplies one atomic ready snapshot.
-module(acdc_queue_strategy).
-export([select/5, unique_agents/1, process_matches/2]).

-spec select(atom(), [binary()], [binary()], [binary()], kz_json:objects()) ->
          'undefined' | {kz_json:objects(), kz_json:objects(), [binary()], [binary()]}.
select(Strategy, Ready, Order, Attempted, Responses) ->
    Eligible = responses(Responses, Ready, #{}),
    Ids = lists:usort([agent(R) || R <- Eligible]),
    case choose(Strategy, Ready, Order, Attempted, Ids, Eligible) of
        [] -> 'undefined';
        Selected ->
            {Wins, Others} = lists:partition(fun(R) -> lists:member(agent(R), Selected) end, Eligible),
            NextReady = case Strategy of 'rr' -> rotate(Ready, hd(Selected)); _ -> Ready end,
            NextAttempts = case Strategy of
                               'ord' -> case Ids -- Attempted of
                                            [] -> Selected;
                                            _ -> lists:usort(Attempted ++ Selected)
                                        end;
                               _ -> []
                           end,
            {Wins, Others, NextReady, NextAttempts}
    end.

choose(_, _, _, _, [], _) -> [];
choose('all', _, _, _, Ids, _) -> Ids;
choose('rr', Ready, _, _, Ids, _) -> [hd([I || I <- Ready, lists:member(I, Ids)])];
choose('mi', _, _, _, _, Responses) ->
    %% Stable ID tie-break; all responding processes of the winning user remain.
    [{_, Id}|_] = lists:sort([{-kz_json:get_integer_value(<<"Idle-Time">>, R, 0), agent(R)} || R <- Responses]),
    [Id];
choose('ord', _, Order, Attempted, Ids, _) ->
    Priority = unique(Order ++ Ids, #{}),
    Eligible = [I || I <- Priority, lists:member(I, Ids)],
    case Eligible -- Attempted of [] -> [hd(Eligible)]; Remaining -> [hd(Remaining)] end.

responses([], _, _) -> [];
responses([R|Rest], Ready, Seen) ->
    Id = agent(R), Process = kz_json:get_ne_binary_value(<<"Process-ID">>, R),
    Key = {Id, Process},
    case lists:member(Id, Ready) andalso Process =/= 'undefined' andalso not maps:is_key(Key, Seen) of
        'true' -> [R | responses(Rest, Ready, Seen#{Key => 'true'})];
        'false' -> responses(Rest, Ready, Seen)
    end.

rotate(Ready, Winner) ->
    {Before, [Winner|After]} = lists:splitwith(fun(I) -> I =/= Winner end, Ready),
    After ++ Before ++ [Winner].

unique([], _) -> [];
unique([I|Rest], Seen) when is_binary(I), byte_size(I) > 0 ->
    case maps:is_key(I, Seen) of
        'true' -> unique(Rest, Seen);
        'false' -> [I | unique(Rest, Seen#{I => 'true'})]
    end;
unique([_|Rest], Seen) -> unique(Rest, Seen).

%% Publish one win per agent, not one broadcast per responding agent process.
-spec unique_agents(kz_json:objects()) -> kz_json:objects().
unique_agents(Responses) -> unique_agents(Responses, #{}).
unique_agents([], _) -> [];
unique_agents([R|Rest], Seen) ->
    Id = agent(R),
    case maps:is_key(Id, Seen) of
        'true' -> unique_agents(Rest, Seen);
        'false' -> [R | unique_agents(Rest, Seen#{Id => 'true'})]
    end.

-spec process_matches(kz_json:object(), kz_json:object()) -> boolean().
process_matches(A, B) ->
    agent(A) =/= 'undefined' andalso agent(A) =:= agent(B)
        andalso kz_json:get_ne_binary_value(<<"Process-ID">>, A) =/= 'undefined'
        andalso kz_json:get_value(<<"Process-ID">>, A) =:= kz_json:get_value(<<"Process-ID">>, B).

agent(R) -> kz_json:get_ne_binary_value(<<"Agent-ID">>, R).
