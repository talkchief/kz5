%%% SPDX-License-Identifier: MPL-2.0
%%% Internal invalidation hints, not authorization or delivery receipts.
-module(kapi_acdc_dashboard_events).
-export([changed/1, changed_v/1, publish_changed/1,
         bind_q/2, unbind_q/2, declare_exchanges/0]).
-include("acdc.hrl").

-define(BODY, [<<"Version">>, <<"Account-ID">>, <<"Queue-ID">>]).
-define(REQUIRED, [<<"App-Name">>, <<"App-Version">>, <<"Event-Category">>,
                   <<"Event-Name">>, <<"Msg-ID">>]).
%% The federator adds these transport fields. They never become browser data.
-define(TRANSPORT, [<<"Node">>, <<"Server-ID">>, <<"Server-Queue-ID">>,
                    <<"AMQP-Broker">>, <<"AMQP-Broker-Zone">>, <<"AMQP-Zone">>]).

-spec changed(kz_term:api_terms()) -> {ok, iolist()} | {error, string()}.
changed(API) ->
    case changed_v(API) of
        true -> kz_api:build_message(to_props(API), ?BODY, []);
        false -> {error, "Invalid dashboard changed hint"}
    end.

-spec changed_v(kz_term:api_terms()) -> boolean().
changed_v(API) ->
    try
        P = to_props(API),
        P =/= [] andalso closed(P, ?BODY ++ ?REQUIRED ++ ?TRANSPORT, #{}) andalso
            kz_api:validate(P, ?BODY, values(), []) andalso
            value(<<"Version">>, P) =:= 1 andalso
            hex(value(<<"Account-ID">>, P)) andalso hex(value(<<"Queue-ID">>, P)) andalso
            lists:all(fun(K) -> text(value(K,P),128) end, ?REQUIRED) andalso
            lists:all(fun(K) -> transport(K,value(K,P)) end, ?TRANSPORT)
    catch _:_ -> false end.

-spec publish_changed(kz_term:api_terms()) -> ok | {error, any()}.
publish_changed(API) ->
    try
        P = to_props(API),
        case closed(P, ?BODY ++ ?REQUIRED ++ ?TRANSPORT, #{}) andalso
            value(<<"Version">>,P) =:= 1 andalso
            hex(value(<<"Account-ID">>,P)) andalso hex(value(<<"Queue-ID">>,P)) of
            false -> {error, invalid_changed_hint};
            true ->
                case kz_api:prepare_api_payload(P,values(),fun changed/1) of
                    {ok,Payload} ->
                        kz_amqp_util:callmgr_publish(Payload,?DEFAULT_CONTENT_TYPE,
                            routing_key(value(<<"Account-ID">>,P),value(<<"Queue-ID">>,P)));
                    Error -> Error
                end
        end
    catch _:_ -> {error, invalid_changed_hint} end.

-spec bind_q(binary(), kz_term:proplist()) -> ok | {error, any()}.
bind_q(Queue,Props) -> binding(Queue,Props,fun kz_amqp_util:bind_q_to_callmgr/2).
-spec unbind_q(binary(), kz_term:proplist()) -> ok | {error, any()}.
unbind_q(Queue,Props) -> binding(Queue,Props,fun kz_amqp_util:unbind_q_from_callmgr/2).
-spec declare_exchanges() -> ok.
declare_exchanges() -> kz_amqp_util:callmgr_exchange().

-spec binding(binary(), any(), fun((binary(),binary()) -> any())) -> any().
binding(Queue,Props,Fun) ->
    case scope(Props,#{}) of
        {ok,Account,Id} ->
            case text(Queue,255) of
                true -> Fun(Queue,routing_key(Account,Id));
                false -> {error,invalid_broker_queue}
            end;
        error -> {error,invalid_binding_scope}
    end.

-spec scope(any(), map()) -> {ok,binary(),binary()} | error.
scope([],Seen) ->
    A=maps:get(account_id,Seen,undefined), Q=maps:get(queue_id,Seen,undefined),
    case hex(A) andalso hex(Q) of true -> {ok,A,Q}; false -> error end;
scope([federate|Rest],Seen) -> scope([{federate,true}|Rest],Seen);
scope([{K,V}|Rest],Seen) when K=:=account_id; K=:=queue_id; K=:=federate ->
    case maps:is_key(K,Seen) orelse (K=:=federate andalso V=/=true) of
        true -> error;
        false -> scope(Rest,maps:put(K,V,Seen))
    end;
scope(_,_) -> error.

-spec routing_key(binary(),binary()) -> binary().
routing_key(A,Q) -> <<"acdc.dashboard.changed.",A/binary,".",Q/binary>>.
-spec values() -> kz_term:proplist().
values() -> [{<<"Event-Category">>,<<"acdc_dashboard">>},{<<"Event-Name">>,<<"changed">>}].
-spec closed(any(), [binary()], map()) -> boolean().
closed([],_,_) -> true;
closed([{K,_}|Rest],Allowed,Seen) ->
    lists:member(K,Allowed) andalso not maps:is_key(K,Seen) andalso
        closed(Rest,Allowed,maps:put(K,true,Seen));
closed(_,_,_) -> false.
-spec transport(binary(), any()) -> boolean().
transport(_,undefined) -> true;
transport(<<"Server-Queue-ID">>,null) -> true;
transport(_,V) -> text(V,1024).
-spec text(any(), pos_integer()) -> boolean().
text(V,Max) when is_binary(V), byte_size(V)>0, byte_size(V)=<Max ->
    lists:all(fun(C) -> C>=32 andalso C=/=127 end,binary_to_list(V));
text(_,_) -> false.
-spec hex(any()) -> boolean().
hex(V) when is_binary(V), byte_size(V)=:=32 -> hex_bytes(V);
hex(_) -> false.
-spec hex_bytes(binary()) -> boolean().
hex_bytes(<<>>) -> true;
hex_bytes(<<C,R/binary>>) when C>=$0,C=<$9; C>=$a,C=<$f -> hex_bytes(R);
hex_bytes(_) -> false.
-spec to_props(kz_term:api_terms()) -> kz_term:proplist().
to_props(P) when is_list(P) -> P;
to_props(J) -> kz_json:to_proplist(J).
-spec value(binary(), kz_term:proplist()) -> any().
value(K,P) -> proplists:get_value(K,P).
