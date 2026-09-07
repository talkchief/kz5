%%% SPDX-License-Identifier: MPL-2.0
%%% Selected persisted roster + authorized names + bounded runtime observations.
%%% No global user list, agent command, endpoint probe, or readiness inference.
-module(cb_acdc_live_agents).
-export([prepare/2, public/2]).
-define(LIMIT,200).
-define(EPOCH,62167219200).

-spec prepare(cb_context:context(), binary() | undefined) -> undefined | map().
prepare(_,undefined) -> undefined;
prepare(C,Q) ->
    try
        A=cb_context:account_id(C),
        need(id(A) andalso id(Q) andalso cb_context:is_authenticated(C),403,<<"forbidden">>),
        need(cb_context:db_name(C)=:=kzs_util:format_account_db(A),403,<<"forbidden">>),
        ok=acdc_live_auth:permit(C,<<"queues">>,[Q,<<"roster">>]),
        Opts=[{startkey,[Q]},{endkey,[Q,kz_json:new()]},{reduce,false},include_docs,{limit,?LIMIT+1}],
        case kz_datamgr:get_results(cb_context:db_name(C),<<"queues/agents_listing">>,Opts) of
            {ok,Rows} ->
                Docs=roster(Rows,A,Q,?LIMIT+1,#{}),
                Sorted=lists:keysort(1,[{kz_doc:id(D),D} || D<-Docs]),
                %% Authorize all fetched identities, including the lookahead.
                %% A denied identity must not leak via names or truncation.
                [begin
                    ok=acdc_live_auth:permit(C,<<"agents">>,[I]),
                    ok=acdc_live_auth:permit(C,<<"agents">>,[I,<<"status">>])
                 end || {I,_}<-Sorted],
                Page=lists:sublist(Sorted,?LIMIT),
                #{ids=>[I || {I,_}<-Page],docs=>[D || {_,D}<-Page],truncated=>length(Sorted)>?LIMIT};
            _ -> fail(503,<<"agent_roster_unavailable">>)
        end
    catch
        throw:{live_error,_,_}=Error -> throw(Error);
        _:_ -> fail(503,<<"agent_roster_unavailable">>)
    end.

-spec roster(any(),binary(),binary(),non_neg_integer(),map()) -> [kz_json:object()].
roster([],_,_,_,_) -> [];
roster([R|Rest],A,Q,Left,Seen) when Left>0 ->
    D=val(<<"doc">>,R), I=kz_doc:id(D),
    need(kz_json:is_json_object(D) andalso id(I) andalso
        kz_doc:type(D)=:= <<"user">> andalso kz_doc:account_id(D)=:=A andalso
        not kz_doc:is_deleted(D) andalso not kz_doc:is_soft_deleted(D) andalso
        selected(val(<<"queues">>,D),Q) andalso
        val(<<"id">>,R)=:=I andalso val(<<"key">>,R)=:=[Q,I] andalso
        not maps:is_key(I,Seen),503,<<"invalid_agent_roster">>),
    [D|roster(Rest,A,Q,Left-1,maps:put(I,true,Seen))];
roster(_,_,_,_,_) -> fail(503,<<"invalid_agent_roster">>).

-spec selected(any(),binary()) -> boolean().
selected(Qs,Q) -> selected(Qs,Q,1024,false,#{}).
-spec selected(any(),binary(),non_neg_integer(),boolean(),map()) -> boolean().
selected([],_,_,Found,_) -> Found;
selected([I|Rest],Q,Left,Found,Seen) when Left>0 ->
    id(I) andalso not maps:is_key(I,Seen) andalso
        selected(Rest,Q,Left-1,Found orelse I=:=Q,maps:put(I,true,Seen));
selected(_,_,_,_,_) -> false.

-spec public(undefined | map(), null | map()) -> null | kz_json:object().
public(undefined,_) -> null;
public(Prepared,Runtime) ->
    try public_roster(Prepared,Runtime)
    catch
        throw:{live_error,_,_}=Error -> throw(Error);
        _:_ -> fail(503,<<"invalid_agent_runtime">>)
    end.

-spec public_roster(map(),null | map()) -> kz_json:object().
public_roster(#{ids:=Ids,docs:=Docs,truncated:=Truncated},Runtime) ->
    need(is_boolean(Truncated) andalso is_list(Ids) andalso length(Ids)=< ?LIMIT andalso
        (not Truncated orelse length(Ids)=:=?LIMIT) andalso
        Ids=:=lists:usort(Ids) andalso lists:all(fun id/1,Ids) andalso
        is_list(Docs) andalso length(Docs)=:=length(Ids) andalso
        [kz_doc:id(D) || D<-Docs]=:=Ids,503,<<"invalid_agent_roster">>),
    {ById,Start,Finish,Available}=runtime(Runtime,Ids),
    Rows=[public_agent(D,maps:get(I,ById,unknown(I,case Available of
        true -> <<"not_observed">>;false -> <<"source_unavailable">> end))) || {I,D}<-lists:zip(Ids,Docs)],
    Complete=Available andalso not Truncated andalso lists:all(fun(R)->val(<<"observed">>,R)=:=true end,Rows),
    obj([{<<"limit">>,?LIMIT},{<<"roster_complete">>,not Truncated},{<<"truncated">>,Truncated},
        {<<"runtime_complete">>,Complete},{<<"endpoint_reachability_verified">>,false},
        {<<"observation_started">>,Start},{<<"observation_finished">>,Finish},{<<"rows">>,Rows}]);
public_roster(_,_) -> fail(503,<<"invalid_agent_roster">>).

-spec runtime(null | map(),[binary()]) -> {map(),integer() | null,integer() | null,boolean()}.
runtime(null,_) -> {#{},null,null,false};
runtime(#{rows:=Rows,observation_started:=Start,observation_finished:=Finish},Ids) ->
    need(is_integer(Start) andalso Start>?EPOCH andalso is_integer(Finish) andalso Finish>=Start,
         503,<<"invalid_agent_runtime">>),
    {runtime_rows(Rows,Ids,?LIMIT,#{}),Start-?EPOCH,Finish-?EPOCH,true};
runtime(_,_) -> fail(503,<<"invalid_agent_runtime">>).

-spec runtime_rows(any(),[binary()],non_neg_integer(),map()) -> map().
runtime_rows([],_,_,Acc) -> Acc;
runtime_rows([R|Rest],Ids,Left,Acc) when Left>0 ->
    I=val(<<"agent_id">>,R),
    need(exact(R,[<<"agent_id">>,<<"observed">>,<<"queue_member">>,<<"state">>,<<"reason">>]) andalso
        lists:member(I,Ids) andalso not maps:is_key(I,Acc) andalso valid_runtime(R),
        503,<<"invalid_agent_runtime">>),
    runtime_rows(Rest,Ids,Left-1,maps:put(I,R,Acc));
runtime_rows(_,_,_,_) -> fail(503,<<"invalid_agent_runtime">>).

-spec valid_runtime(kz_json:object()) -> boolean().
valid_runtime(R) ->
    case {val(<<"observed">>,R),val(<<"queue_member">>,R),val(<<"state">>,R),val(<<"reason">>,R)} of
        {true,M,S,<<"observed">>} -> is_boolean(M) andalso
            lists:member(S,[<<"wait">>,<<"sync">>,<<"ready">>,<<"ringing">>,
                            <<"answered">>,<<"wrapup">>,<<"paused">>,<<"outbound">>]);
        {false,null,null,Why} -> lists:member(Why,[<<"not_observed">>,<<"inconsistent_sources">>,<<"source_unavailable">>]);
        _ -> false
    end.
-spec public_agent(kz_json:object(),kz_json:object()) -> kz_json:object().
public_agent(D,R) ->
    obj([{<<"agent_id">>,kz_doc:id(D)},{<<"name">>,name(D)} |
        [{K,val(K,R)} || K<-[<<"observed">>,<<"queue_member">>,<<"state">>,<<"reason">>]]]).
-spec unknown(binary(),binary()) -> kz_json:object().
unknown(I,Why) -> obj([{<<"agent_id">>,I},{<<"observed">>,false},{<<"queue_member">>,null},
    {<<"state">>,null},{<<"reason">>,Why}]).
-spec name(kz_json:object()) -> binary().
name(D) ->
    Parts=[V || K<-[<<"first_name">>,<<"last_name">>],V<-[val(K,D)],text(V,128)],
    Joined=iolist_to_binary(lists:join(<<" ">>,Parts)),
    case text(Joined,256) of true->Joined;false->kz_doc:id(D) end.
-spec text(any(),pos_integer()) -> boolean().
text(B,Max) when is_binary(B),byte_size(B)>0,byte_size(B)=<Max ->
    unicode:characters_to_binary(B,utf8,utf8)=:=B andalso
        re:run(B,<<"[\\x00-\\x1f\\x7f]">>,[{capture,none}])=:=nomatch;
text(_,_) -> false.
-spec exact(kz_json:object(),[binary()]) -> boolean().
exact(J,Keys) ->
    kz_json:is_json_object(J) andalso length(kz_json:to_proplist(J))=:=length(Keys) andalso
        lists:sort([K || {K,_}<-kz_json:to_proplist(J)])=:=lists:sort(Keys).
-spec id(any()) -> boolean().
id(B) when is_binary(B),byte_size(B)=:=32 -> re:run(B,<<"^[0-9a-f]{32}$">>,[{capture,none}])=:=match;
id(_) -> false.
-spec val(binary(),kz_json:object()) -> any().
val(K,J) -> kz_json:get_value(K,J).
-spec obj(kz_term:proplist()) -> kz_json:object().
obj(P) -> kz_json:from_list(P).
-spec need(boolean(),integer(),binary()) -> ok.
need(true,_,_) -> ok;
need(false,C,M) -> fail(C,M).
-spec fail(integer(),binary()) -> no_return().
fail(C,M) -> throw({live_error,C,M}).
