%%% SPDX-License-Identifier: MPL-2.0
%%% Bounded, tenant-authorized live observations. Replicas are never summed.
%%% This is not an atomic cluster snapshot or a historical reporting API.
-module(cb_acdc_live).
-export([get/2]).
-ifdef(TEST).
-export([options/2, assess/4, correlated/2, normalized/1]).
-endif.
-include_lib("crossbar/src/crossbar.hrl").
-include_lib("kazoo_stdlib/include/kz_records.hrl").
-define(EPOCH, 62167219200).

-spec get(cb_context:context(), binary() | undefined) -> cb_context:context().
get(Context, QueueId) ->
    Safe = cb_context:set_resp_etag(cb_context:set_resp_header(Context, <<"cache-control">>, <<"no-store">>), undefined),
    try
        need(id(cb_context:account_id(Context)) andalso cb_context:is_authenticated(Context), 403, <<"forbidden">>),
        need(authorized(Context), 403, <<"forbidden">>),
        {Size, Cursor} = options(cb_context:query_string(Context), QueueId),
        permit(Context, [<<"stats">>]),
        permit(Context, case QueueId of undefined -> []; _ -> [QueueId] end),
        need(cb_context:db_name(Context) =:= kzs_util:format_account_db(cb_context:account_id(Context)),
             403, <<"forbidden">>),
        Docs = catalog(Context, QueueId, Size, Cursor),
        %% Check the lookahead too: a cursor must not disclose a forbidden ID.
        lists:foreach(fun(D) -> permit(Context, [kz_doc:id(D)]) end, Docs),
        Page = lists:sublist(Docs, Size),
        Next = case length(Docs) > Size of true -> kz_doc:id(lists:nth(Size+1, Docs)); false -> null end,
        Now = calendar:datetime_to_gregorian_seconds(calendar:universal_time()),
        Ids = [kz_doc:id(D) || D <- Page],
        IncludeCalls = QueueId =/= undefined,
        AgentScope = cb_acdc_live_agents:prepare(Context,QueueId),
        AgentIds = case AgentScope of undefined -> undefined; _ -> maps:get(ids,AgentScope) end,
        {Metrics, Source, ActiveCalls, RuntimeAgents} = snapshot(cb_context:account_id(Context), Ids, Now, IncludeCalls,AgentIds),
        ResponseTime = calendar:datetime_to_gregorian_seconds(calendar:universal_time()),
        Data = obj([{<<"version">>,1}, {<<"account_id">>,cb_context:account_id(Context)},
            {<<"generated_at">>,ResponseTime-?EPOCH},
            {<<"window">>,obj([{<<"from">>,Now-?EPOCH-3600},{<<"to">>,Now-?EPOCH},{<<"seconds">>,3600}])},
            {<<"queues">>,[public_queue(D, Metrics) || D <- Page]},
            {<<"calls">>,public_calls(IncludeCalls, ActiveCalls)},
            {<<"agents">>,cb_acdc_live_agents:public(AgentScope,RuntimeAgents)},
            {<<"pagination">>,obj([{<<"page_size">>,Size},{<<"next_start_queue_id">>,Next},{<<"has_more">>,Next=/=null}])},
            {<<"source">>,Source},
            {<<"capabilities">>,obj([{<<"live_call_details">>,IncludeCalls},
                {<<"agent_runtime">>,IncludeCalls},{<<"websocket_updates">>,websocket_updates()},{<<"historical_reporting">>,false}])}]),
        crossbar_util:response(Data, Safe)
    catch
        throw:{live_error, Code, Message} -> crossbar_util:response(error, Message, Code, Safe);
        _:_ -> crossbar_util:response(error, <<"queue_live_unavailable">>, 503, Safe)
    end.

%% Local protocol registration is a capability, not broker or browser health.
%% Separate Blackhole deployments need their own explicitly verified integration.
websocket_updates() ->
    try lists:member(bh_queue_live,blackhole_bindings:modules_loaded())
    catch _:_ -> false end.

options(Query, QueueId) ->
    Allowed = case QueueId of undefined -> [<<"page_size">>,<<"start_queue_id">>]; _ -> [] end,
    Props = kz_json:to_proplist(Query),
    need(length(Props)=:=length(lists:usort([K || {K,_} <- Props])) andalso
         lists:all(fun({K,_})->lists:member(K,Allowed) end,Props),400,<<"invalid_query">>),
    case QueueId of
        undefined ->
            Size = size_value(kz_json:get_value(<<"page_size">>,Query,50)),
            Cursor = kz_json:get_value(<<"start_queue_id">>,Query),
            need(Cursor=:=undefined orelse id(Cursor),400,<<"invalid_cursor">>), {Size,Cursor};
        _ -> need(id(QueueId),404,<<"queue_not_found">>), {1,undefined}
    end.
size_value(N) when is_integer(N),N>=1,N=<100 -> N;
size_value(B) when is_binary(B),byte_size(B)>0,byte_size(B)=<3 ->
    case re:run(B,<<"^[1-9][0-9]*$">>,[{capture,none}]) of
        match -> size_value(binary_to_integer(B)); _ -> fail(400,<<"invalid_page_size">>) end;
size_value(_) -> fail(400,<<"invalid_page_size">>).

catalog(C, undefined, Size, Cursor) ->
    Opts = [{limit,Size+1},include_docs,{reduce,false}] ++
        case Cursor of undefined -> []; _ -> [{startkey,Cursor}] end,
    case kz_datamgr:get_results(cb_context:db_name(C),<<"queues/crossbar_listing">>,Opts) of
        {ok,Rows} when is_list(Rows),length(Rows)=<Size+1 ->
            Docs=[kz_json:get_value(<<"doc">>,R) || R <- Rows],
            lists:foreach(fun(D)->check_doc(D,C,503) end,Docs),
            Ids=[kz_doc:id(D) || D <- Docs],
            need(Ids=:=lists:usort(Ids) andalso
                lists:all(fun(I)->Cursor=:=undefined orelse I>=Cursor end,Ids),503,<<"invalid_queue_catalog">>),Docs;
        _ -> fail(503,<<"queue_catalog_unavailable">>)
    end;
catalog(C, Q, _, _) ->
    case kz_datamgr:open_doc(cb_context:db_name(C),Q) of
        {ok,D} -> check_doc(D,C,404),need(kz_doc:id(D)=:=Q,404,<<"queue_not_found">>),[D];
        {error,not_found} -> fail(404,<<"queue_not_found">>);
        _ -> fail(503,<<"queue_unavailable">>)
    end.
check_doc(D,C,Code) ->
    need(id(kz_doc:id(D)) andalso kz_doc:type(D)=:= <<"queue">> andalso
        kz_doc:account_id(D)=:=cb_context:account_id(C) andalso
        not kz_doc:is_deleted(D) andalso not kz_doc:is_soft_deleted(D),Code,<<"invalid_queue_document">>).
public_queue(D, Metrics) ->
    Id=kz_doc:id(D), M=maps:get(Id,Metrics,null),
    obj([{<<"id">>,Id},{<<"name">>,safe_text(kz_json:get_value(<<"name">>,D),Id)},
        {<<"strategy">>,safe_text(kz_json:get_value(<<"strategy">>,D),null)},
        {<<"metrics_available">>,M=/=null},{<<"metrics">>,M}]).
safe_text(B,_) when is_binary(B),byte_size(B)>0,byte_size(B)=<256 -> B;
safe_text(_,Default) -> Default.

snapshot(_,[],_,_,_) -> {#{},source(<<"empty_scope">>,true,true,[]),null,null};
snapshot(Account,Ids,Now,IncludeCalls,AgentIds) ->
    Expected = sources(),
    Req = [{<<"Account-ID">>,Account},{<<"Queue-IDs">>,Ids},{<<"From">>,Now-3600},
        {<<"To">>,Now},{<<"Include-Calls">>,IncludeCalls},{<<"Msg-ID">>,kz_binary:rand_hex(16)} |
        kz_api:default_headers(<<"acdc">>,<<"1.0">>)] ++
        case AgentIds of undefined -> []; _ -> [{<<"Agent-IDs">>,AgentIds}] end,
    case Expected of
        [] -> {#{},source(<<"source_unavailable">>,false,false,[]),null,null};
        _ ->
            Until = fun(Rs) -> length(Rs)>=64 orelse
                lists:usort([val(<<"Source-ID">>,R) || R<-Rs,correlated(R,Req)])=:=Expected end,
            Result = kz_amqp_worker:call_collect(Req,fun kapi_acdc_dashboard:publish_snapshot_req/1,Until,3000),
            After=sources(),
            {M,S,C}=case IncludeCalls of
                true -> assess_full(Result,Req,Expected,After);
                false -> {OverviewM,OverviewS}=assess(Result,Req,Expected,After),{OverviewM,OverviewS,null}
            end,
            {M,S,C,agent_observations(Result,Req,Expected,After)}
    end.

agent_observations({ok,Rs},Req,Expected,Expected) when is_list(Rs),length(Rs)<64 ->
    Ids=props:get_value(<<"Agent-IDs">>,Req),
    case Ids=/=undefined andalso Expected=/=[] andalso
        lists:all(fun(R)->correlated(R,Req) andalso val(<<"Status">>,R)=:= <<"ok">> end,Rs) andalso
        lists:usort([val(<<"Source-ID">>,R)||R<-Rs])=:=Expected of
        false -> null;
        true ->
            %% Repeated replies from one incarnation must agree; observations
            %% from different nodes may legitimately contain local absence.
            PerSource=lists:usort([{val(<<"Source-ID">>,R),val(<<"Source-Incarnation">>,R),
                kz_json:get_value([<<"Snapshot">>,<<"agents">>],R)} || R<-Rs]),
            case length(PerSource)=:=length(Expected) of
                false -> null;
                true ->
                    Observations=[O||{_,_,O}<-PerSource],
                    #{rows=>acdc_dashboard_agent_codec:combine(Ids,Observations),
                      observation_started=>lists:min([val(<<"observation_started">>,O)||O<-Observations]),
                      observation_finished=>lists:max([val(<<"observation_finished">>,O)||O<-Observations])}
            end
    end;
agent_observations(_,_,_,_) -> null.

%% Discovery itself is the existing Kazoo inventory, not a topology guarantee.
sources() ->
    Nodes=kz_nodes:nodes(),
    need(is_list(Nodes) andalso length(Nodes)=<256,503,<<"source_inventory_unavailable">>),
    Ids=lists:usort([kz_binary:hexencode(crypto:hash(sha256,atom_to_binary(N,utf8))) ||
        #kz_node{node=N,kapps=Apps} <- Nodes, is_atom(N),is_list(Apps),proplists:is_defined(<<"acdc">>,Apps)]),
    need(length(Ids)=<32,503,<<"source_inventory_limit">>),Ids.

assess(Result,Req,Before,After) ->
    {M,S,_}=assess_full(Result,Req,Before,After),{M,S}.
assess_full(_,_,Before,After) when Before=/=After -> {#{},source(<<"source_set_changed">>,false,false,[]),null};
assess_full({ok,Rs},Req,Expected,_) when is_list(Rs),length(Rs)<64 -> assess_rows(Rs,Req,Expected,false);
assess_full({timeout,Rs},Req,Expected,_) when is_list(Rs),length(Rs)<64 -> assess_rows(Rs,Req,Expected,true);
assess_full({Tag,Rs},_,_,_) when (Tag=:=ok orelse Tag=:=timeout),is_list(Rs),length(Rs)>=64 ->
    {#{},source(<<"response_limit">>,false,false,[]),null};
assess_full(_,_,_,_) -> {#{},source(<<"source_unavailable">>,false,false,[]),null}.
assess_rows(Rs,Req,Expected,TimedOut) ->
    Valid=lists:all(fun(R)->correlated(R,Req) end,Rs),
    Seen=lists:usort([val(<<"Source-ID">>,R) || R<-Rs]),
    All=Valid andalso Seen=:=Expected andalso Expected=/=[],
    Reason = case {Valid,Seen--Expected,All,TimedOut} of
        {false,_,_,_} -> <<"invalid_response">>;
        {_,[_|_],_,_} -> <<"source_set_changed">>;
        {_,_,false,_} -> <<"source_timeout">>;
        {_,_,_,true} -> <<"source_timeout">>;
        _ -> agreement(Rs)
    end,
    case Reason of
        <<"consensus">> ->
            %% Choose one replica, never add replicated counts together.
            [Chosen|_]=lists:sort(fun(A,B)->val(<<"Source-ID">>,A)<val(<<"Source-ID">>,B) end,Rs),
            Queues=val(<<"queues">>,val(<<"Snapshot">>,Chosen)),
            Calls=kz_json:get_value([<<"Snapshot">>,<<"active_calls">>],Chosen,null),
            {maps:from_list([{val(<<"queue_id">>,Q),val(<<"metrics">>,Q)} || Q<-Queues]),source(Reason,true,true,Rs),Calls};
        _ -> {#{},source(Reason,All,false,case Valid of true -> Rs; false -> [] end),null}
    end.
correlated(R,Req) ->
    try kapi_acdc_dashboard:snapshot_resp_v(R) andalso
        (val(<<"Include-Calls">>,R)=:=true)=:=(props:get_value(<<"Include-Calls">>,Req)=:=true) andalso
        val(<<"Agent-IDs">>,R)=:=props:get_value(<<"Agent-IDs">>,Req) andalso
        lists:all(fun(K)->val(K,R)=:=props:get_value(K,Req) end,
            [<<"Account-ID">>,<<"Queue-IDs">>,<<"From">>,<<"To">>,<<"Msg-ID">>])
    catch _:_ -> false end.
agreement(Rs) ->
    case lists:all(fun(R)->val(<<"Status">>,R)=:= <<"ok">> end,Rs) of
        false -> <<"source_error">>;
        true ->
            Complete=lists:all(fun(R)->kz_json:get_value([<<"Snapshot">>,<<"source">>,<<"exhausted">>],R)=:=true end,Rs),
            PerSource=lists:usort([{val(<<"Source-ID">>,R),val(<<"Source-Incarnation">>,R),normalized(R)} || R<-Rs]),
            Unique=length(PerSource)=:=length(lists:usort([val(<<"Source-ID">>,R) || R<-Rs])),
            Same=length(lists:usort([normalized(R) || R<-Rs]))=:=1,
            case {Complete,Unique andalso Same} of
                {false,_} -> <<"incomplete_source">>;
                {_,false} -> <<"inconsistent_sources">>;
                _ -> <<"consensus">>
            end
    end.
normalized(R) ->
    S=val(<<"Snapshot">>,R),AsOf=val(<<"as_of">>,S),
    {lists:sort([{val(<<"queue_id">>,Q),normalize_metrics(val(<<"metrics">>,Q),AsOf)} || Q<-val(<<"queues">>,S)]),
     normalized_calls(kz_json:get_value(<<"active_calls">>,S,null))}.
normalized_calls(null) -> null;
normalized_calls(C) ->
    {[val(K,C) || K <- [<<"limit">>,<<"observed_count">>,<<"truncated">>,<<"complete">>,<<"order">>]],
     [[val(K,R) || K <- [<<"call_id">>,<<"queue_id">>,<<"status">>,<<"entered_timestamp">>,<<"handled_timestamp">>]]
      ++[caller(<<"caller_id_name">>,R),caller(<<"caller_id_number">>,R)]
      || R<-val(<<"rows">>,C)]}.
public_calls(false,_) -> null;
public_calls(true,null) ->
    obj([{<<"available">>,false},{<<"complete">>,false},{<<"truncated">>,false},
        {<<"limit">>,200},{<<"observed_count">>,null},{<<"order">>,<<"queue_id_entered_call_id">>},{<<"rows">>,[]}]);
public_calls(true,C) ->
    obj([{<<"available">>,true},{<<"complete">>,val(<<"complete">>,C)},
        {<<"truncated">>,val(<<"truncated">>,C)},{<<"limit">>,val(<<"limit">>,C)},
        {<<"observed_count">>,val(<<"observed_count">>,C)},{<<"order">>,val(<<"order">>,C)},
        {<<"rows">>,[public_call(R) || R<-val(<<"rows">>,C)]}]).
public_call(R) ->
    obj([{<<"call_id">>,val(<<"call_id">>,R)},{<<"queue_id">>,val(<<"queue_id">>,R)},
        {<<"status">>,val(<<"status">>,R)},
        {<<"entered_at">>,unix(val(<<"entered_timestamp">>,R))},
        {<<"handled_at">>,unix(val(<<"handled_timestamp">>,R))},
        {<<"caller_id_name">>,caller(<<"caller_id_name">>,R)},
        {<<"caller_id_number">>,caller(<<"caller_id_number">>,R)}]).
%% Only called after the native codec validates an exact 5- or 7-key row.
%% Legacy absence and explicit null agree; known versus unknown does not.
caller(Key,Row) -> kz_json:get_value(Key,Row,null).
unix(null) -> null;
unix(N) when is_integer(N) -> N-?EPOCH.
normalize_metrics(null,_) -> null;
normalize_metrics(M,AsOf) ->
    lists:sort([{K,case {K,V} of {<<"max_current_wait_seconds">>,N} when is_integer(N)->AsOf-N; _->V end}
        || {K,V}<-kz_json:to_proplist(M)]).
source(Reason,All,Consistent,Rs) ->
    Times=[{kz_json:get_value([<<"Snapshot">>,<<"source">>,<<"observation_started">>],R),
            kz_json:get_value([<<"Snapshot">>,<<"source">>,<<"observation_finished">>],R)} || R<-Rs,val(<<"Status">>,R)=:= <<"ok">>],
    {Start,End}=case Times of []->{null,null}; _->{lists:min([S || {S,_}<-Times])-?EPOCH,lists:max([E || {_,E}<-Times])-?EPOCH} end,
    Status=case Reason of <<"consensus">>-> <<"available">>; <<"empty_scope">>-> <<"available">>;
        <<"source_unavailable">>-> <<"unavailable">>; _-> <<"partial">> end,
    obj([{<<"coverage">>,<<"observed_replicas">>},{<<"all_known_sources_responded">>,All},
        {<<"consistent">>,Consistent},{<<"atomic_snapshot">>,false},{<<"status">>,Status},{<<"reason">>,Reason},
        {<<"observation_started_at">>,Start},{<<"observation_finished_at">>,End}]).

%% Match the queue editor's fail-closed authorization for embedded resources.
permit(C,Params) ->
    acdc_live_auth:permit(C,Params).
authorized(C) ->
    acdc_live_auth:authorize(C).
id(B) when is_binary(B),byte_size(B)=:=32 -> re:run(B,<<"^[0-9a-f]{32}$">>,[{capture,none}])=:=match;
id(_) -> false.
need(true,_,_) -> ok;
need(false,Code,Message) -> fail(Code,Message).
fail(Code,Message) -> throw({live_error,Code,Message}).
obj(P) -> kz_json:from_list(P).
val(K,J) -> kz_json:get_value(K,J).
