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
        {Metrics, Source} = snapshot(cb_context:account_id(Context), Ids, Now),
        ResponseTime = calendar:datetime_to_gregorian_seconds(calendar:universal_time()),
        Data = obj([{<<"version">>,1}, {<<"account_id">>,cb_context:account_id(Context)},
            {<<"generated_at">>,ResponseTime-?EPOCH},
            {<<"window">>,obj([{<<"from">>,Now-?EPOCH-3600},{<<"to">>,Now-?EPOCH},{<<"seconds">>,3600}])},
            {<<"queues">>,[public_queue(D, Metrics) || D <- Page]},
            {<<"pagination">>,obj([{<<"page_size">>,Size},{<<"next_start_queue_id">>,Next},{<<"has_more">>,Next=/=null}])},
            {<<"source">>,Source},
            {<<"capabilities">>,obj([{K,false} || K <- [<<"live_call_details">>,<<"agent_runtime">>,
                <<"websocket_updates">>,<<"historical_reporting">>]])}]),
        crossbar_util:response(Data, Safe)
    catch
        throw:{live_error, Code, Message} -> crossbar_util:response(error, Message, Code, Safe);
        _:_ -> crossbar_util:response(error, <<"queue_live_unavailable">>, 503, Safe)
    end.

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

snapshot(_,[],_) -> {#{},source(<<"empty_scope">>,true,true,[])};
snapshot(Account,Ids,Now) ->
    Expected = sources(),
    Req = [{<<"Account-ID">>,Account},{<<"Queue-IDs">>,Ids},{<<"From">>,Now-3600},
        {<<"To">>,Now},{<<"Msg-ID">>,kz_binary:rand_hex(16)} | kz_api:default_headers(<<"acdc">>,<<"1.0">>)],
    case Expected of
        [] -> {#{},source(<<"source_unavailable">>,false,false,[])};
        _ ->
            Until = fun(Rs) -> length(Rs)>=64 orelse
                lists:usort([val(<<"Source-ID">>,R) || R<-Rs,correlated(R,Req)])=:=Expected end,
            Result = kz_amqp_worker:call_collect(Req,fun kapi_acdc_dashboard:publish_snapshot_req/1,Until,3000),
            assess(Result,Req,Expected,sources())
    end.

%% Discovery itself is the existing Kazoo inventory, not a topology guarantee.
sources() ->
    Nodes=kz_nodes:nodes(),
    need(is_list(Nodes) andalso length(Nodes)=<256,503,<<"source_inventory_unavailable">>),
    Ids=lists:usort([kz_binary:hexencode(crypto:hash(sha256,atom_to_binary(N,utf8))) ||
        #kz_node{node=N,kapps=Apps} <- Nodes, is_atom(N),is_list(Apps),proplists:is_defined(<<"acdc">>,Apps)]),
    need(length(Ids)=<32,503,<<"source_inventory_limit">>),Ids.

assess(_,_,Before,After) when Before=/=After -> {#{},source(<<"source_set_changed">>,false,false,[])};
assess({ok,Rs},Req,Expected,_) when is_list(Rs),length(Rs)<64 -> assess_rows(Rs,Req,Expected,false);
assess({timeout,Rs},Req,Expected,_) when is_list(Rs),length(Rs)<64 -> assess_rows(Rs,Req,Expected,true);
assess({Tag,Rs},_,_,_) when (Tag=:=ok orelse Tag=:=timeout),is_list(Rs),length(Rs)>=64 ->
    {#{},source(<<"response_limit">>,false,false,[])};
assess(_,_,_,_) -> {#{},source(<<"source_unavailable">>,false,false,[])}.
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
            {maps:from_list([{val(<<"queue_id">>,Q),val(<<"metrics">>,Q)} || Q<-Queues]),source(Reason,true,true,Rs)};
        _ -> {#{},source(Reason,All,false,case Valid of true -> Rs; false -> [] end)}
    end.
correlated(R,Req) ->
    try kapi_acdc_dashboard:snapshot_resp_v(R) andalso
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
    lists:sort([{val(<<"queue_id">>,Q),normalize_metrics(val(<<"metrics">>,Q),AsOf)} || Q<-val(<<"queues">>,S)]).
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
    Account=cb_context:account_id(C),
    Sub=cb_context:setters(C,[{fun cb_context:set_req_nouns/2,[{<<"queues">>,Params},{<<"accounts">>,[Account]}]},
        {fun cb_context:set_raw_path/2,iolist_to_binary([<<"/">>,cb_context:api_version(C),<<"/accounts/">>,Account,<<"/queues">>,[[<<"/">>,P] || P<-Params]])},
        {fun cb_context:set_req_verb/2,?HTTP_GET},{fun cb_context:set_query_string/2,kz_json:new()},
        {fun cb_context:set_resp_status/2,success},{fun cb_context:set_doc/2,kz_json:new()},
        {fun cb_context:set_req_data/2,kz_json:new()}]),
    need(authorized(Sub),403,<<"queue_live_resource_forbidden">>).
authorized(C) ->
    [{Resource,Params}|_]=cb_context:req_nouns(C),
    Results=crossbar_bindings:pmap(api_util:create_event_name(C,<<"authorize">>),C) ++
        crossbar_bindings:pmap(api_util:create_event_name(C,<<"authorize.",Resource/binary>>),[C|Params]),
    lists:all(fun(true)->true;(false)->true;({true,_})->true;({false,_})->true;(_)->false end,Results) andalso
        lists:any(fun(true)->true;({true,_})->true;(_)->false end,Results) andalso scopes(C,Resource).
scopes(C,Resource) ->
    case {cb_context:auth_token_type(C),kz_json:get_ne_binary_value(<<"method">>,cb_context:auth_doc(C))} of
        {'x-auth-token',Method} when is_binary(Method) ->
            lists:all(fun(Required) when is_list(Required)->kz_auth_scope:all(cb_context:auth_token(C),Required);(_)->false end,
                crossbar_bindings:pmap(api_util:create_event_name(C,<<"allowed_scopes.",Resource/binary>>),Method));
        _ -> true
    end.
id(B) when is_binary(B),byte_size(B)=:=32 -> re:run(B,<<"^[0-9a-f]{32}$">>,[{capture,none}])=:=match;
id(_) -> false.
need(true,_,_) -> ok;
need(false,Code,Message) -> fail(Code,Message).
fail(Code,Message) -> throw({live_error,Code,Message}).
obj(P) -> kz_json:from_list(P).
val(K,J) -> kz_json:get_value(K,J).
