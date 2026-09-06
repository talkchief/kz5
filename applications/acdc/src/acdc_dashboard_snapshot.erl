%%% SPDX-License-Identifier: MPL-2.0
%%% Runs in a gen_listener responder, never in the stats server mailbox.
%%% One response is one local cache observation. Independent caches must not
%%% be added together. HTTP authorization/source selection is a separate layer.
-module(acdc_dashboard_snapshot).
-export([handle_req/2]).
-include("acdc.hrl").

-spec handle_req(kz_json:object(), kz_term:proplist()) -> ok | {error, any()}.
handle_req(Request,Props) ->
    case kapi_acdc_dashboard:snapshot_req_v(Request) of
        false -> {error,invalid_request};
        true ->
            Server=props:get_value(server,Props),
            case is_pid(Server) andalso node(Server)=:=node() of
                false -> {error,invalid_listener};
                true -> respond(Request,Server)
            end
    end.

respond(Request,Server) ->
    Correlation=[{K,kz_json:get_value(K,Request)} || K<-[<<"Account-ID">>,<<"Queue-IDs">>,<<"From">>,<<"To">>,<<"Msg-ID">>]],
    %% Full PID serialization includes the Erlang node creation/incarnation;
    %% pid_to_list alone would collide across VM restarts. Raw names/PIDs never
    %% enter Snapshot. Broker headers/opaque IDs are not public DTO fields.
    Identity=[{<<"Source-ID">>,kz_term:to_hex_binary(crypto:hash(sha256,atom_to_binary(node(),utf8)))},
              {<<"Source-Incarnation">>,digest({acdc_dashboard,node(),Server})}],
    Body=case collect(Request,Server) of
             {ok,Projection} -> [{<<"Status">>,<<"ok">>},{<<"Snapshot">>,snapshot(Projection)}];
             {error,Code} -> [{<<"Status">>,<<"error">>},{<<"Error-Code">>,Code}]
         end,
    kapi_acdc_dashboard:publish_snapshot_resp(kz_json:get_value(<<"Server-ID">>,Request),
        Body++Identity++Correlation++kz_api:default_headers(?APP_NAME,?APP_VERSION)).

collect(Request,Server) ->
    try
        Tid=ets:whereis(acdc_stats:call_table_id()),
        case current_source(Tid,Server) of
            false -> {error,<<"source_unavailable">>};
            true ->
                Result=acdc_dashboard_collector:collect(Tid,kz_json:get_value(<<"Account-ID">>,Request),
                    kz_json:get_value(<<"Queue-IDs">>,Request),kz_json:get_value(<<"From">>,Request),
                    kz_json:get_value(<<"To">>,Request),#{max_scan=>10000,budget_ms=>1000}),
                case current_source(Tid,Server) of
                    false -> {error,<<"source_changed">>};
                    true -> collection_result(Result)
                end
        end
    catch _:_ -> {error,<<"collection_failed">>} end.

current_source(undefined,_) -> false;
current_source(Tid,Server) ->
    acdc_stats_sup:stats_srv()=:={ok,Server} andalso is_process_alive(Server) andalso ets:info(Tid,owner)=:=Server.
collection_result({ok,P}) -> {ok,P};
collection_result({error,source_unavailable}) -> {error,<<"source_unavailable">>};
collection_result({error,_}) -> {error,<<"invalid_source">>}.
digest(Term) -> kz_term:to_hex_binary(crypto:hash(sha256,term_to_binary(Term))).

%% Whitelist every object level. In particular never serialize collector node,
%% foreign-key scan counts, key identities, caller fields, or arbitrary errors.
snapshot(P) ->
    S=maps:get(source,P), W=maps:get(window,P),
    kz_json:from_list(fields(P,[version,account_id,as_of,timestamp_unit,identity_semantics,
                              distinct_visit_metrics_available,agent_eligibility_available,workforce_metrics_available])++
        [{<<"window">>,kz_json:from_list(fields(W,[from,to,predicate]))},
         {<<"source">>,kz_json:from_list(fields(S,[availability,coverage,atomic_snapshot,exhausted,
             completion_reason,projection_complete,cluster_complete,archive_coverage,
             observation_started,observation_finished]))},
         {<<"queues">>,[queue(Q) || Q<-maps:get(queues,P)]}]).
queue(Q) ->
    kz_json:from_list(fields(Q,[queue_id,source_exhausted])++
        [{<<"observed">>,counts(maps:get(observed,Q))},
         {<<"metrics">>,case maps:get(metrics,Q) of undefined -> null; M -> counts(M) end}]).
counts(C) -> kz_json:from_list(fields(C,[current_waiting,current_handled,max_current_wait_seconds,
    records_entered,waiting_in_cohort,handled_in_cohort,processed_in_cohort,abandoned_in_cohort,
    average_answered_wait_seconds,average_processed_talk_seconds])).
fields(M,Keys) -> [{atom_to_binary(K,utf8),scalar(maps:get(K,M))} || K<-Keys].
scalar(undefined) -> null;
scalar(true) -> true;
scalar(false) -> false;
scalar(A) when is_atom(A) -> atom_to_binary(A,utf8);
scalar(V) when is_binary(V); is_integer(V); is_float(V) -> V.
