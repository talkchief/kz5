%%% SPDX-License-Identifier: MPL-2.0
%%% Closed internal runtime observations and conservative cross-node projection.
-module(acdc_dashboard_agent_codec).
-export([encode/1, valid/5, combine/2, ids/1]).

-spec ids(term()) -> boolean().
ids(Ids) -> ids(Ids,200,undefined).
ids([],_,_) -> true;
ids([I|Rest],Left,Previous) when Left>0 ->
    hex(I,32) andalso (Previous=:=undefined orelse Previous<I) andalso ids(Rest,Left-1,I);
ids(_,_,_) -> false.

-spec encode(map()) -> kz_json:object().
encode(M) -> obj([{account_id,maps:get(account_id,M)},{queue_id,maps:get(queue_id,M)},
    {observation_started,maps:get(observation_started,M)},
    {observation_finished,maps:get(observation_finished,M)},
    {coverage,<<"local_process_observations">>},{atomic_snapshot,false},
    {endpoint_reachability_verified,false},{limit,200},
    {rows,[obj([{K,scalar(maps:get(K,R))} || K<-[agent_id,observed,member,state,reason,instance]])
        || R<-maps:get(rows,M)]}]).

-spec valid(term(),binary(),binary(),[binary()],integer()) -> boolean().
valid(J,A,Q,Ids,RequestTime) ->
    try
        Start=v(observation_started,J),End=v(observation_finished,J),
        exact(J,[account_id,queue_id,observation_started,observation_finished,coverage,
                 atomic_snapshot,endpoint_reachability_verified,limit,rows]) andalso
        v(account_id,J)=:=A andalso v(queue_id,J)=:=Q andalso ids(Ids) andalso
        is_integer(Start) andalso Start>=RequestTime andalso
        is_integer(End) andalso End>=Start andalso End-Start=<3 andalso
        End=<calendar:datetime_to_gregorian_seconds(calendar:universal_time()) andalso
        v(coverage,J)=:= <<"local_process_observations">> andalso v(atomic_snapshot,J)=:=false andalso
        v(endpoint_reachability_verified,J)=:=false andalso v(limit,J)=:=200 andalso
        rows(v(rows,J),Ids)
    catch _:_ -> false end.
rows([],[]) -> true;
rows([R|Rest],[Id|Ids]) ->
    exact(R,[agent_id,observed,member,state,reason,instance]) andalso
    v(agent_id,R)=:=Id andalso row(R) andalso rows(Rest,Ids);
rows(_,_) -> false.
row(R) ->
    case v(observed,R) of
        true -> is_boolean(v(member,R)) andalso v(reason,R)=:= <<"observed">> andalso
            hex(v(instance,R),64) andalso lists:member(v(state,R),
                [<<"wait">>,<<"sync">>,<<"ready">>,<<"ringing">>,<<"answered">>,
                 <<"wrapup">>,<<"paused">>,<<"outbound">>]);
        false -> v(member,R)=:=null andalso v(state,R)=:=null andalso v(instance,R)=:=null andalso
            lists:member(v(reason,R),[<<"not_observed">>,<<"changed">>,<<"timeout">>,
                <<"unavailable">>,<<"budget">>,<<"invalid_runtime">>]);
        _ -> false
    end.

%% Caller must validate every response and prove the expected source set before
%% combining. Local absence is not a negative membership or logout observation.
-spec combine([binary()],[kz_json:object()]) -> [kz_json:object()].
combine(Ids,Snapshots) ->
    Indexed=[maps:from_list([{v(agent_id,R),R} || R<-v(rows,S)]) || S<-Snapshots],
    [combine_row(Id,[maps:get(Id,I) || I<-Indexed]) || Id<-Ids].
combine_row(Id,Rows) ->
    Observed=[{v(member,R),v(state,R)} || R<-Rows,v(observed,R)=:=true],
    Errors=[R || R<-Rows,v(observed,R)=/=true,v(reason,R)=/= <<"not_observed">>],
    {Member,State,Reason}=case {Errors,lists:usort(Observed),Rows} of
        {[],[{M,S}],_} -> {M,S,<<"observed">>};
        {[],[],[_|_]} -> {null,null,<<"not_observed">>};
        {[],[_|_],_} -> {null,null,<<"inconsistent_sources">>};
        _ -> {null,null,<<"source_unavailable">>}
    end,
    obj([{agent_id,Id},{observed,Reason=:= <<"observed">>},
        {queue_member,Member},{state,State},{reason,Reason}]).

v(K,J) -> kz_json:get_value(atom_to_binary(K,utf8),J).
obj(Ps) -> kz_json:from_list([{atom_to_binary(K,utf8),V} || {K,V}<-Ps]).
scalar(null) -> null;
scalar(true) -> true;
scalar(false) -> false;
scalar(A) when is_atom(A) -> atom_to_binary(A,utf8);
scalar(V) -> V.
hex(B,N) when is_binary(B),byte_size(B)=:=N -> re:run(B,<<"^[0-9a-f]+$">>,[{capture,none}])=:=match;
hex(_,_) -> false.
exact(J,Keys) ->
    kz_json:is_json_object(J) andalso
    lists:sort([K || {K,_}<-kz_json:to_proplist(J)])=:=lists:sort([atom_to_binary(K,utf8)||K<-Keys]).
