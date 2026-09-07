%%% SPDX-License-Identifier: MPL-2.0
%%% Internal authenticated-broker contract, not tenant authorization.
-module(kapi_acdc_dashboard).
-export([snapshot_req/1, snapshot_req_v/1, snapshot_resp/1, snapshot_resp_v/1,
         publish_snapshot_req/1, publish_snapshot_resp/2,
         bind_q/2, unbind_q/2, declare_exchanges/0, routing_key/1]).
-include("acdc.hrl").
-define(SCOPE, [<<"Account-ID">>, <<"Queue-IDs">>, <<"From">>, <<"To">>, <<"Msg-ID">>]).
-define(REQ, [<<"Server-ID">>|?SCOPE]).
-define(RESP, [<<"Status">>, <<"Source-ID">>, <<"Source-Incarnation">>|?SCOPE]).
-define(ERRORS, [<<"source_unavailable">>, <<"source_changed">>, <<"invalid_source">>, <<"collection_failed">>]).

-spec snapshot_req(kz_term:api_terms()) -> {ok, iolist()} | {error, string()}.
snapshot_req(API) ->
    case snapshot_req_v(API) of
        true -> kz_api:build_message(to_props(API), ?REQ, [<<"Include-Calls">>,<<"Agent-IDs">>]);
        false -> {error, "Invalid dashboard snapshot request"}
    end.
-spec snapshot_req_v(kz_term:api_terms()) -> boolean().
snapshot_req_v(API) ->
    validate(API, ?REQ, <<"snapshot_req">>) andalso reply_id(value(<<"Server-ID">>, API)).

-spec snapshot_resp(kz_term:api_terms()) -> {ok, iolist()} | {error, string()}.
snapshot_resp(API) ->
    case snapshot_resp_v(API) of
        true -> kz_api:build_message(to_props(API), ?RESP, [<<"Snapshot">>, <<"Error-Code">>, <<"Include-Calls">>,<<"Agent-IDs">>]);
        false -> {error, "Invalid dashboard snapshot response"}
    end.
-spec snapshot_resp_v(kz_term:api_terms()) -> boolean().
snapshot_resp_v(API) ->
    validate(API, ?RESP, <<"snapshot_resp">>) andalso
        hex(value(<<"Source-ID">>, API), 64) andalso
        hex(value(<<"Source-Incarnation">>, API), 64) andalso response_body(API).

validate(API, Required, Name) ->
    try
        Props=to_props(API),
        Props=/=[] andalso kz_api:validate(Props, Required, values(Name), []) andalso
            hex(value(<<"Account-ID">>, Props), 32) andalso
            queue_ids(value(<<"Queue-IDs">>, Props), 100, #{}) andalso
            calls_scope(value(<<"Include-Calls">>, Props), value(<<"Queue-IDs">>, Props)) andalso
            agents_scope(value(<<"Agent-IDs">>,Props),value(<<"Queue-IDs">>,Props)) andalso
            text(value(<<"Msg-ID">>, Props), 128) andalso
            window(value(<<"From">>, Props), value(<<"To">>, Props))
    catch _:_ -> false end.

window(From, To) when is_integer(From), From > 0, is_integer(To), To > From, To-From =< 86400 ->
    To =< calendar:datetime_to_gregorian_seconds(calendar:universal_time());
window(_, _) -> false.
queue_ids([], _, Seen) -> map_size(Seen)>0;
queue_ids([Q|Rest], Left, Seen) when Left>0 ->
    hex(Q,32) andalso not maps:is_key(Q,Seen) andalso queue_ids(Rest,Left-1,maps:put(Q,true,Seen));
queue_ids(_, _, _) -> false.
%% Absent is the legacy metrics-only wire contract. Explicit false is echoed.
calls_scope(undefined, _) -> true;
calls_scope(false, _) -> true;
calls_scope(true, [_]) -> true;
calls_scope(_, _) -> false.
agents_scope(undefined,_) -> true;
agents_scope(Ids,[_]) -> acdc_dashboard_agent_codec:ids(Ids);
agents_scope(_,_) -> false.
response_body(API) ->
    case value(<<"Status">>, API) of
        <<"ok">> -> valid_snapshot(value(<<"Snapshot">>,API),API) andalso value(<<"Error-Code">>,API)=:=undefined;
        <<"error">> -> lists:member(value(<<"Error-Code">>,API),?ERRORS) andalso value(<<"Snapshot">>,API)=:=undefined;
        _ -> false
    end.

valid_snapshot(S,API) ->
    try
        exact_object(S,[<<"version">>,<<"account_id">>,<<"as_of">>,<<"timestamp_unit">>,<<"identity_semantics">>,
            <<"distinct_visit_metrics_available">>,<<"agent_eligibility_available">>,<<"workforce_metrics_available">>,
            <<"window">>,<<"source">>,<<"queues">>]++calls_keys(API)++agents_keys(API)) andalso
        value(<<"version">>,S)=:=1 andalso value(<<"account_id">>,S)=:=value(<<"Account-ID">>,API) andalso
        value(<<"timestamp_unit">>,S)=:= <<"kazoo_gregorian_seconds">> andalso
        value(<<"identity_semantics">>,S)=:= <<"call_queue_pair">> andalso
        lists:all(fun(K)->value(K,S)=:=false end,[<<"distinct_visit_metrics_available">>,
            <<"agent_eligibility_available">>,<<"workforce_metrics_available">>]) andalso
        valid_asof(value(<<"as_of">>,S),value(<<"To">>,API)) andalso
        valid_window_object(value(<<"window">>,S),API) andalso
        valid_source(value(<<"source">>,S),value(<<"as_of">>,S),value(<<"To">>,API)) andalso
        valid_queues(value(<<"queues">>,S),value(<<"Queue-IDs">>,API),
                     value(<<"exhausted">>,value(<<"source">>,S))) andalso valid_calls(S,API) andalso valid_agents(S,API)
    catch _:_ -> false end.
calls_keys(API) ->
    case value(<<"Include-Calls">>,API) of true -> [<<"active_calls">>]; _ -> [] end.
agents_keys(API) ->
    case value(<<"Agent-IDs">>,API) of undefined -> []; _ -> [<<"agents">>] end.
valid_agents(S,API) ->
    case value(<<"Agent-IDs">>,API) of
        undefined -> true;
        Ids -> [Q]=value(<<"Queue-IDs">>,API),
            acdc_dashboard_agent_codec:valid(value(<<"agents">>,S),value(<<"Account-ID">>,API),
                Q,Ids,value(<<"To">>,API))
    end.

valid_calls(S,API) ->
    case value(<<"Include-Calls">>,API) of
        true ->
            [Selected]=value(<<"Queue-IDs">>,API),
            A=value(<<"active_calls">>,S),
            N=value(<<"observed_count">>,A),
            Exhausted=value(<<"exhausted">>,value(<<"source">>,S)),
            exact_object(A,[<<"rows">>,<<"limit">>,<<"observed_count">>,<<"truncated">>,
                <<"complete">>,<<"order">>,<<"coverage">>,<<"atomic_snapshot">>]) andalso
            bounded_integer(N,10000) andalso value(<<"limit">>,A)=:=200 andalso
            value(<<"truncated">>,A)=:=(N>200) andalso
            value(<<"complete">>,A)=:=(Exhausted andalso N=<200) andalso
            value(<<"order">>,A)=:= <<"queue_id_entered_call_id">> andalso
            value(<<"coverage">>,A)=:= <<"local_table_only">> andalso
            value(<<"atomic_snapshot">>,A)=:=false andalso
            active_rows(value(<<"rows">>,A),Selected,value(<<"as_of">>,S),
                        erlang:min(N,200),undefined,#{}) andalso
            active_count_matches(Exhausted,N,value(<<"queues">>,S));
        _ -> true
    end.
active_count_matches(false,_,_) -> true;
active_count_matches(true,N,[Queue]) ->
    C=value(<<"observed">>,Queue),
    N=:=value(<<"current_waiting">>,C)+value(<<"current_handled">>,C).

%% Recursion is bounded before inspecting the next row. Identity uniqueness is
%% independent of the entry timestamp: changing entry time cannot hide a dup.
active_rows([],_,_,0,_,_) -> true;
active_rows([Row|Rest],Selected,AsOf,Left,Previous,Seen) when Left>0 ->
    Call=value(<<"call_id">>,Row), Queue=value(<<"queue_id">>,Row),
    Entered=value(<<"entered_timestamp">>,Row),
    Key={Queue,Entered,Call}, Identity={Queue,Call},
    active_row_shape(Row) andalso
    text(Call,256) andalso Queue=:=Selected andalso
    is_integer(Entered) andalso Entered>0 andalso Entered=<AsOf andalso
    active_timeline(value(<<"status">>,Row),Entered,value(<<"handled_timestamp">>,Row),AsOf) andalso
    (Previous=:=undefined orelse Previous<Key) andalso not maps:is_key(Identity,Seen) andalso
    active_rows(Rest,Selected,AsOf,Left-1,Key,maps:put(Identity,true,Seen));
active_rows(_,_,_,_,_,_) -> false.
%% Rolling upgrades accept only the complete legacy or complete new shape.
%% Missing legacy identity is unknown, never permission to use raw call fields.
active_row_shape(Row) ->
    Base=[<<"call_id">>,<<"queue_id">>,<<"status">>,<<"entered_timestamp">>,<<"handled_timestamp">>],
    exact_object(Row,Base) orelse
        (exact_object(Row,Base++[<<"caller_id_name">>,<<"caller_id_number">>]) andalso
         caller_identity(Row)).
caller_identity(Row) ->
    Name=value(<<"caller_id_name">>,Row), Number=value(<<"caller_id_number">>,Row),
    %% Reuse the upstream privacy marker's exact byte/UTF-8/control validation.
    %% This validates transported text only; it does not manufacture provenance.
    %% Do not use from_list here: its utf8_binary coercion repairs malformed
    %% bytes before validation and would turn an invalid wire value into text.
    acdc_dashboard_caller:valid({[{<<"version">>,1},
        {<<"name">>,Name},{<<"number">>,Number},
        {<<"name_status">>,caller_status(Name)},{<<"number_status">>,caller_status(Number)}]}).
caller_status(null) -> <<"unavailable">>;
caller_status(_) -> <<"available">>.
active_timeline(<<"waiting">>,_,null,_) -> true;
active_timeline(<<"handled">>,E,H,AsOf) -> is_integer(H) andalso H>=E andalso H=<AsOf;
active_timeline(_,_,_,_) -> false.
valid_asof(N,To) when is_integer(N), N>=To ->
    N=<calendar:datetime_to_gregorian_seconds(calendar:universal_time());
valid_asof(_,_) -> false.
valid_window_object(W,API) ->
    exact_object(W,[<<"from">>,<<"to">>,<<"predicate">>]) andalso
    value(<<"from">>,W)=:=value(<<"From">>,API) andalso value(<<"to">>,W)=:=value(<<"To">>,API) andalso
    value(<<"predicate">>,W)=:= <<"entered_from_inclusive_to_exclusive">>.
valid_source(S,AsOf,RequestTo) ->
    exact_object(S,[<<"availability">>,<<"coverage">>,<<"atomic_snapshot">>,<<"exhausted">>,
        <<"completion_reason">>,<<"projection_complete">>,<<"cluster_complete">>,<<"archive_coverage">>,
        <<"observation_started">>,<<"observation_finished">>]) andalso
    lists:member(value(<<"availability">>,S),[<<"available">>,<<"not_read">>]) andalso
    value(<<"coverage">>,S)=:= <<"local_table_only">> andalso value(<<"atomic_snapshot">>,S)=:=false andalso
    value(<<"cluster_complete">>,S)=:=false andalso value(<<"archive_coverage">>,S)=:= <<"unknown">> andalso
    is_boolean(value(<<"projection_complete">>,S)) andalso
    observation(value(<<"observation_started">>,S),value(<<"observation_finished">>,S),AsOf,RequestTo) andalso
    source_state(value(<<"exhausted">>,S),S).
%% Collection begins after request formation. Clock rollback/skew is unknown
%% data, not permission to expose a negative or pre-request public timestamp.
observation(Start,End,AsOf,RequestTo) -> is_integer(Start) andalso Start>=RequestTo andalso
    is_integer(End) andalso End>=Start andalso End=:=AsOf.
source_state(true,S) -> value(<<"completion_reason">>,S)=:= <<"exhausted">> andalso
    value(<<"projection_complete">>,S)=:=true andalso value(<<"availability">>,S)=:= <<"available">>;
source_state(false,S) -> lists:member(value(<<"completion_reason">>,S),[<<"deadline">>,<<"scan_limit">>,<<"concurrent_delete">>]);
source_state(_,_) -> false.
valid_queues(Queues,Selected,Complete) ->
    case queue_objects(Queues,100,Complete,#{}) of
        {ok,Seen} -> lists:sort(maps:keys(Seen))=:=lists:sort(Selected);
        error -> false
    end.
queue_objects([],_,_,Seen) -> {ok,Seen};
queue_objects([Q|Rest],Left,Complete,Seen) when Left>0 ->
    Id=value(<<"queue_id">>,Q), Observed=value(<<"observed">>,Q), Metrics=value(<<"metrics">>,Q),
    case exact_object(Q,[<<"queue_id">>,<<"source_exhausted">>,<<"observed">>,<<"metrics">>]) andalso
         hex(Id,32) andalso not maps:is_key(Id,Seen) andalso value(<<"source_exhausted">>,Q)=:=Complete andalso
         valid_counts(Observed) andalso metrics_match(Complete,Observed,Metrics) of
        true -> queue_objects(Rest,Left-1,Complete,maps:put(Id,true,Seen));
        false -> error
    end;
queue_objects(_,_,_,_) -> error.
metrics_match(false,_,null) -> true;
metrics_match(true,Observed,Metrics) -> valid_counts(Metrics) andalso
    lists:all(fun(K)->value(K,Observed)=:=value(K,Metrics) end,count_keys());
metrics_match(_,_,_) -> false.
count_keys() -> [<<"current_waiting">>,<<"current_handled">>,<<"max_current_wait_seconds">>,
    <<"records_entered">>,<<"waiting_in_cohort">>,<<"handled_in_cohort">>,<<"processed_in_cohort">>,
    <<"abandoned_in_cohort">>,<<"average_answered_wait_seconds">>,<<"average_processed_talk_seconds">>].
valid_counts(C) ->
    exact_object(C,count_keys()) andalso
    lists:all(fun(K)->bounded_integer(value(K,C),10000) end,
        [<<"current_waiting">>,<<"current_handled">>,<<"records_entered">>,<<"waiting_in_cohort">>,
         <<"handled_in_cohort">>,<<"processed_in_cohort">>,<<"abandoned_in_cohort">>]) andalso
    nullable_number(value(<<"max_current_wait_seconds">>,C),integer) andalso
    nullable_number(value(<<"average_answered_wait_seconds">>,C),number) andalso
    nullable_number(value(<<"average_processed_talk_seconds">>,C),number).
bounded_integer(N,Max) -> is_integer(N) andalso N>=0 andalso N=<Max.
nullable_number(null,_) -> true;
nullable_number(N,integer) -> bounded_integer(N,999999999999);
nullable_number(N,number) -> is_number(N) andalso N>=0 andalso N=<999999999999.
exact_object(J,Keys) ->
    kz_json:is_json_object(J) andalso exact_keys(kz_json:to_proplist(J),maps:from_list([{K,true} || K<-Keys])).
exact_keys([],Remaining) -> map_size(Remaining)=:=0;
exact_keys([{K,_}|Rest],Remaining) -> maps:is_key(K,Remaining) andalso exact_keys(Rest,maps:remove(K,Remaining));
exact_keys(_,_) -> false.

-spec publish_snapshot_req(kz_term:api_terms()) -> ok | {error, any()}.
publish_snapshot_req(API) ->
    case kz_api:prepare_api_payload(API,values(<<"snapshot_req">>),fun snapshot_req/1) of
        {ok,Payload} -> kz_amqp_util:callmgr_publish(Payload,?DEFAULT_CONTENT_TYPE,routing_key(value(<<"Account-ID">>,API)));
        Error -> Error
    end.
-spec publish_snapshot_resp(kz_term:ne_binary(), kz_term:api_terms()) -> ok | {error, any()}.
publish_snapshot_resp(Reply,API) ->
    case reply_id(Reply) of
        false -> {error,invalid_reply_queue};
        true ->
            case kz_api:prepare_api_payload(API,values(<<"snapshot_resp">>),fun snapshot_resp/1) of
                {ok,Payload} -> kz_amqp_util:targeted_publish(Reply,Payload,?DEFAULT_CONTENT_TYPE);
                Error -> Error
            end
    end.
-spec routing_key(binary()) -> binary().
routing_key(Account) -> true=hex(Account,32), <<"acdc.dashboard.snapshot.",Account/binary>>.
-spec bind_q(binary(), kz_term:proplist()) -> ok | {error,any()}.
bind_q(Queue,Props) -> binding(Queue,Props,fun kz_amqp_util:bind_q_to_callmgr/2).
-spec unbind_q(binary(), kz_term:proplist()) -> ok | {error,any()}.
unbind_q(Queue,Props) -> binding(Queue,Props,fun kz_amqp_util:unbind_q_from_callmgr/2).
binding(Queue,[],Fun) ->
    case text(Queue,255) of
        true -> Fun(Queue,<<"acdc.dashboard.snapshot.*">>);
        false -> {error,invalid_binding}
    end;
%% Native gen_listener passes this local flag to bind_q unchanged and removes
%% it only for remote federator bindings. Both bind the same closed topic.
binding(Queue,[federate],Fun) -> binding(Queue,[],Fun);
binding(Queue,[{federate,true}],Fun) -> binding(Queue,[],Fun);
binding(_,_,_) -> {error,invalid_binding}.
-spec declare_exchanges() -> ok.
declare_exchanges() -> kz_amqp_util:callmgr_exchange().

values(Name) -> [{<<"Event-Category">>,<<"acdc_dashboard">>},{<<"Event-Name">>,Name}].
to_props(API) when is_list(API) -> API;
to_props(API) -> kz_json:to_proplist(API).
value(Key,API) when is_list(API) -> props:get_value(Key,API);
value(Key,API) -> kz_json:get_value(Key,API).
hex(B,N) when is_binary(B), byte_size(B)=:=N -> hex_bytes(B);
hex(_,_) -> false.
hex_bytes(<<>>) -> true;
hex_bytes(<<C,Rest/binary>>) when C>=$0,C=<$9; C>=$a,C=<$f -> hex_bytes(Rest);
hex_bytes(_) -> false.
text(B,Max) when is_binary(B), byte_size(B)>0, byte_size(B)=<Max ->
    re:run(B,<<"[\\x00-\\x1f\\x7f]">>,[{capture,none}])=:=nomatch;
text(_,_) -> false.

%% listener_federator prefixes the original broker queue with its local
%% consumer PID; targeted_publish uses that assignment to reply on the origin
%% broker. The prefix is not part of the broker's255-byte queue-name limit.
reply_id(<<"consumer://",Rest/binary>>) when byte_size(Rest)=<292 ->
    case binary:split(Rest,<<"/">>) of
        [Pid,Queue] -> text(Queue,255) andalso binary:match(Queue,<<"/">>)=:=nomatch andalso
            byte_size(Pid)=<35 andalso re:run(Pid,<<"^<[0-9]{1,10}\\.[0-9]{1,10}\\.[0-9]{1,10}>$">>,[{capture,none}])=:=match;
        _ -> false
    end;
reply_id(B) -> text(B,255).
