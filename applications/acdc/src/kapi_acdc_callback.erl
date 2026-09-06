%%% SPDX-License-Identifier: MPL-2.0
%%% Internal caller/queue handshake. This is not a public callback-creation API.
%%% Server-ID must also match the queued call's original controller queue at
%%% the listener; schema validation alone does not authorize registration.
-module(kapi_acdc_callback).

-export([request/1, request_v/1, response/1, response_v/1
        ,publish_request/1, publish_response/2
        ,bind_q/2, unbind_q/2, declare_exchanges/0, routing_key/3]).

-include("acdc.hrl").

-define(SCOPE, [<<"Account-ID">>, <<"Queue-ID">>, <<"Call-ID">>, <<"Request-ID">>, <<"Operation">>]).
-define(REQUEST_REQUIRED, [<<"Server-ID">> | ?SCOPE]).
-define(REQUEST_OPTIONAL, [<<"Pause-ID">>, <<"Number">>, <<"Callback-ID">>]).
-define(RESPONSE_REQUIRED, [<<"Status">> | ?SCOPE]).
-define(RESPONSE_OPTIONAL, [<<"Pause-ID">>, <<"Callback-ID">>, <<"Failure-Reason">>]).
-define(OPERATIONS, [<<"pause">>, <<"register">>, <<"resume">>, <<"abandon">>]).
-define(STATUSES, [<<"paused">>, <<"registered">>, <<"resumed">>, <<"abandoned">>, <<"rejected">>]).

-spec request(kz_term:api_terms()) -> {'ok', iolist()} | {'error', string()}.
request(API) ->
    case request_v(API) of
        'true' -> kz_api:build_message(to_props(API), ?REQUEST_REQUIRED, ?REQUEST_OPTIONAL);
        'false' -> {'error', "Invalid callback handshake request"}
    end.

-spec request_v(kz_term:api_terms()) -> boolean().
request_v(API) ->
    safe_validate(API, ?REQUEST_REQUIRED, <<"request">>)
        andalso valid_text(value(<<"Server-ID">>, API), 255)
        andalso request_fields(value(<<"Operation">>, API), API).

-spec response(kz_term:api_terms()) -> {'ok', iolist()} | {'error', string()}.
response(API) ->
    case response_v(API) of
        'true' -> kz_api:build_message(to_props(API), ?RESPONSE_REQUIRED, ?RESPONSE_OPTIONAL);
        'false' -> {'error', "Invalid callback handshake response"}
    end.

-spec response_v(kz_term:api_terms()) -> boolean().
response_v(API) ->
    safe_validate(API, ?RESPONSE_REQUIRED, <<"response">>)
        andalso lists:member(value(<<"Status">>, API), ?STATUSES)
        andalso response_fields(value(<<"Operation">>, API), value(<<"Status">>, API), API).

-spec publish_request(kz_term:api_terms()) -> 'ok' | {'error', any()}.
publish_request(API) ->
    case kz_api:prepare_api_payload(API, values(<<"request">>), fun request/1) of
        {'ok', Payload} ->
            Key = routing_key(value(<<"Account-ID">>, API), value(<<"Queue-ID">>, API), value(<<"Call-ID">>, API)),
            kz_amqp_util:callmgr_publish(Payload, ?DEFAULT_CONTENT_TYPE, Key);
        Error -> Error
    end.

-spec publish_response(kz_term:ne_binary(), kz_term:api_terms()) -> 'ok' | {'error', any()}.
publish_response(ReplyQueue, API) ->
    case valid_text(ReplyQueue, 255) of
        'false' -> {'error', 'invalid_reply_queue'};
        'true' ->
            case kz_api:prepare_api_payload(API, values(<<"response">>), fun response/1) of
                {'ok', Payload} -> kz_amqp_util:targeted_publish(ReplyQueue, Payload, ?DEFAULT_CONTENT_TYPE);
                Error -> Error
            end
    end.

-spec bind_q(kz_term:ne_binary(), kz_term:proplist()) -> 'ok' | {'error', any()}.
bind_q(Queue, Props) ->
    binding(Queue, Props, fun kz_amqp_util:bind_q_to_callmgr/2).

-spec unbind_q(kz_term:ne_binary(), kz_term:proplist()) -> 'ok' | {'error', any()}.
unbind_q(Queue, Props) ->
    binding(Queue, Props, fun kz_amqp_util:unbind_q_from_callmgr/2).

-spec declare_exchanges() -> 'ok'.
declare_exchanges() -> kz_amqp_util:callmgr_exchange().

%% Hash the original physical UUID rather than interpolating it: SIP Call-IDs
%% can contain dots, wildcard characters or addresses, which must not widen an
%% AMQP topic binding. Account and queue components are strictly bounded.
-spec routing_key(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> kz_term:ne_binary().
routing_key(AccountId, QueueId, CallId) ->
    'true' = valid_scope(AccountId, QueueId, CallId),
    Digest = kz_term:to_hex_binary(crypto:hash('sha256', CallId)),
    <<"acdc.callback.", AccountId/binary, ".", QueueId/binary, ".", Digest/binary>>.

binding(Queue, Props, Bind) ->
    AccountId = props:get_value('account_id', Props),
    QueueId = props:get_value('queue_id', Props),
    CallId = props:get_value('callid', Props),
    case valid_text(Queue, 255) andalso valid_scope(AccountId, QueueId, CallId) of
        'true' -> Bind(Queue, routing_key(AccountId, QueueId, CallId));
        'false' -> {'error', 'invalid_binding'}
    end.

safe_validate(API, Required, Name) ->
    try
        Props = to_props(API),
        kz_api:validate(Props, Required, values(Name), [])
            andalso valid_scope(value(<<"Account-ID">>, Props), value(<<"Queue-ID">>, Props), value(<<"Call-ID">>, Props))
            andalso matches(value(<<"Request-ID">>, Props), <<"^[0-9a-f]{32}$">>)
            andalso lists:member(value(<<"Operation">>, Props), ?OPERATIONS)
    catch _:_ -> 'false'
    end.

request_fields(<<"pause">>, API) ->
    absent([<<"Pause-ID">>, <<"Number">>, <<"Callback-ID">>], API);
request_fields(<<"register">>, API) ->
    valid_pause(API) andalso matches(value(<<"Number">>, API), <<"^\\+?[0-9]{1,15}$">>)
        andalso absent([<<"Callback-ID">>], API);
request_fields(Operation, API) when Operation =:= <<"resume">>; Operation =:= <<"abandon">> ->
    valid_pause(API) andalso absent([<<"Number">>], API)
        andalso optional_callback(API);
request_fields(_, _) -> 'false'.

response_fields(_, <<"rejected">>, API) ->
    lists:member(value(<<"Failure-Reason">>, API),
                 [<<"not_waiting">>, <<"disabled">>, <<"stale_request">>, <<"policy_denied">>
                 ,<<"storage_failed">>, <<"expired">>, <<"invalid_number">>, <<"busy">>])
        andalso absent([<<"Pause-ID">>, <<"Callback-ID">>], API);
response_fields(<<"pause">>, <<"paused">>, API) ->
    valid_pause(API) andalso absent([<<"Callback-ID">>, <<"Failure-Reason">>], API);
response_fields(<<"register">>, <<"registered">>, API) ->
    valid_pause(API) andalso valid_callback(value(<<"Callback-ID">>, API))
        andalso absent([<<"Failure-Reason">>], API);
response_fields(Operation, Status, API)
  when Operation =:= <<"resume">>, Status =:= <<"resumed">>;
       Operation =:= <<"abandon">>, Status =:= <<"abandoned">> ->
    valid_pause(API) andalso optional_callback(API) andalso absent([<<"Failure-Reason">>], API);
response_fields(_, _, _) -> 'false'.

values(Name) -> [{<<"Event-Category">>, <<"acdc_callback">>}, {<<"Event-Name">>, Name}].
to_props(API) when is_list(API) -> API;
to_props(API) -> kz_json:to_proplist(API).
value(Key, API) when is_list(API) -> props:get_value(Key, API);
value(Key, API) -> kz_json:get_value(Key, API).
absent(Keys, API) -> lists:all(fun(Key) -> value(Key, API) =:= 'undefined' end, Keys).
valid_pause(API) -> matches(value(<<"Pause-ID">>, API), <<"^[0-9a-f]{48}$">>).
valid_callback(Id) -> matches(Id, <<"^acdc-callback-[0-9a-f]{64}$">>).
optional_callback(API) ->
    value(<<"Callback-ID">>, API) =:= 'undefined' orelse valid_callback(value(<<"Callback-ID">>, API)).
valid_scope(AccountId, QueueId, CallId) ->
    matches(AccountId, <<"^[0-9a-f]{32}$">>)
        andalso matches(QueueId, <<"^[A-Za-z0-9_-]{1,128}$">>) andalso valid_text(CallId, 512).
matches(Value, Regex) when is_binary(Value), byte_size(Value) =< 512 ->
    valid_text(Value, 512) andalso re:run(Value, Regex, [{'capture', 'none'}]) =:= 'match';
matches(_, _) -> 'false'.
valid_text(Value, Max) when is_binary(Value), byte_size(Value) > 0, byte_size(Value) =< Max ->
    re:run(Value, <<"[\\x00-\\x1f\\x7f]">>, [{'capture', 'none'}]) =:= 'nomatch';
valid_text(_, _) -> 'false'.
