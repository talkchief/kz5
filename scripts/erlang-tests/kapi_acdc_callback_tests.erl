%%% SPDX-License-Identifier: MPL-2.0
-module(kapi_acdc_callback_tests).
-include_lib("eunit/include/eunit.hrl").

-define(ACCOUNT, <<"11111111111111111111111111111111">>).
-define(QUEUE, <<"queue-test">>).
-define(CALL, <<"sip.call#id@host.invalid">>).
-define(REQUEST, <<"22222222222222222222222222222222">>).
-define(PAUSE, <<"333333333333333333333333333333333333333333333333">>).
-define(CALLBACK, <<"acdc-callback-4444444444444444444444444444444444444444444444444444444444444444">>).

request_roundtrip_test() ->
    lists:foreach(fun(Operation) ->
        Req = request(Operation),
        ?assert(kapi_acdc_callback:request_v(Req)),
        {ok, Payload} = kapi_acdc_callback:request(kz_json:to_proplist(Req)),
        Decoded = kz_json:decode(iolist_to_binary(Payload)),
        ?assert(kapi_acdc_callback:request_v(Decoded)),
        ?assertEqual(Operation, kz_json:get_value(<<"Operation">>, Decoded)),
        ?assertEqual(?REQUEST, kz_json:get_value(<<"Request-ID">>, Decoded))
    end, [<<"pause">>, <<"register">>, <<"resume">>, <<"abandon">>]).

operation_fields_test() ->
    ?assertNot(kapi_acdc_callback:request_v(kz_json:set_value(<<"Number">>, <<"1001">>, request(<<"pause">>)))),
    ?assertNot(kapi_acdc_callback:request_v(kz_json:delete_key(<<"Pause-ID">>, request(<<"register">>)))),
    ?assertNot(kapi_acdc_callback:request_v(kz_json:set_value(<<"Number">>, <<"sofia/internal/1001">>, request(<<"register">>)))),
    ?assertNot(kapi_acdc_callback:request_v(kz_json:set_value(<<"Number">>, <<"123\n">>, request(<<"register">>)))),
    ?assertNot(kapi_acdc_callback:request_v(kz_json:set_value(<<"Number">>, <<"1001">>, request(<<"resume">>)))),
    ?assertNot(kapi_acdc_callback:request_v(kz_json:set_value(<<"Callback-ID">>, <<"bad-id">>, request(<<"abandon">>)))),
    ?assertNot(kapi_acdc_callback:request_v(kz_json:set_value(<<"Operation">>, <<"dial">>, request(<<"pause">>)))).

bounded_scope_test() ->
    lists:foreach(fun({Key, Value}) ->
        ?assertNot(kapi_acdc_callback:request_v(kz_json:set_value(Key, Value, request(<<"pause">>))))
    end, [{<<"Account-ID">>, <<"*">>}, {<<"Account-ID">>, <<?ACCOUNT/binary, "\n">>}
          ,{<<"Queue-ID">>, <<"queue.#">>}, {<<"Call-ID">>, binary:copy(<<"x">>, 513)}
          ,{<<"Request-ID">>, <<"not-a-random-id">>}, {<<"Server-ID">>, <<>>}
          ,{<<"Server-ID">>, <<"reply\r\nqueue">>}]),
    [?assertNot(kapi_acdc_callback:request_v(Value)) || Value <- [undefined, 42, <<"not-json">>, [bad]]],
    [?assertNot(kapi_acdc_callback:response_v(Value)) || Value <- [undefined, 42, <<"not-json">>, [bad]]].

response_operation_correlation_test() ->
    lists:foreach(fun({Operation, Status}) ->
        API = response(Operation, Status),
        ?assert(kapi_acdc_callback:response_v(API)),
        {ok, Encoded} = kapi_acdc_callback:response(API),
        ?assert(kapi_acdc_callback:response_v(kz_json:decode(iolist_to_binary(Encoded))))
    end, [{<<"pause">>, <<"paused">>}, {<<"register">>, <<"registered">>}
          ,{<<"resume">>, <<"resumed">>}, {<<"abandon">>, <<"abandoned">>}]),
    ?assertNot(kapi_acdc_callback:response_v(response(<<"pause">>, <<"registered">>))),
    ?assertNot(kapi_acdc_callback:response_v(kz_json:delete_key(<<"Callback-ID">>, response(<<"register">>, <<"registered">>)))),
    Rejected = kz_json:set_values([{<<"Status">>, <<"rejected">>}, {<<"Failure-Reason">>, <<"busy">>}]
                                  ,kz_json:delete_key(<<"Pause-ID">>, response(<<"pause">>, <<"paused">>))),
    ?assert(kapi_acdc_callback:response_v(Rejected)),
    ?assertNot(kapi_acdc_callback:response_v(kz_json:set_value(<<"Failure-Reason">>, <<"unbounded raw error">>, Rejected))).

payload_projection_test() ->
    API = kz_json:set_values([{<<"pvt_lease">>, <<"secret-attempt-token">>}
                             ,{<<"Authority-ID">>, <<"private-device">>}
                             ,{<<"Call">>, kz_json:from_list([{<<"Caller-ID-Number">>, <<"private">>}])}]
                             ,request(<<"register">>)),
    {ok, Encoded} = kapi_acdc_callback:request(API),
    Payload = iolist_to_binary(Encoded),
    ?assertEqual(nomatch, binary:match(Payload, <<"secret-attempt-token">>)),
    ?assertEqual(nomatch, binary:match(Payload, <<"private-device">>)),
    ?assertEqual(nomatch, binary:match(Payload, <<"Caller-ID-Number">>)).

exact_topic_binding_test() ->
    Key = kapi_acdc_callback:routing_key(?ACCOUNT, ?QUEUE, ?CALL),
    ?assertEqual(5, length(binary:split(Key, <<".">>, [global]))),
    ?assertEqual(nomatch, binary:match(Key, <<"#">>)),
    ?assertEqual(nomatch, binary:match(Key, <<"*">>)),
    ?assertNotEqual(Key, kapi_acdc_callback:routing_key(?ACCOUNT, ?QUEUE, <<?CALL/binary, "x">>)),
    meck:new(kz_amqp_util, [non_strict, no_link]),
    try
        meck:expect(kz_amqp_util, bind_q_to_callmgr, fun(<<"listener">>, Actual) -> ?assertEqual(Key, Actual), ok end),
        meck:expect(kz_amqp_util, unbind_q_from_callmgr, fun(<<"listener">>, Actual) -> ?assertEqual(Key, Actual), ok end),
        Props = [{account_id, ?ACCOUNT}, {queue_id, ?QUEUE}, {callid, ?CALL}],
        ?assertEqual(ok, kapi_acdc_callback:bind_q(<<"listener">>, Props)),
        ?assertEqual(ok, kapi_acdc_callback:unbind_q(<<"listener">>, Props)),
        ?assertEqual({error, invalid_binding}, kapi_acdc_callback:bind_q(<<"listener">>, [{account_id, <<"#">>}]))
    after meck:unload(kz_amqp_util) end.

publish_only_validated_messages_test() ->
    meck:new(kz_amqp_util, [non_strict, no_link]),
    try
        meck:expect(kz_amqp_util, callmgr_publish, fun(Payload, <<"application/json">>, Key) ->
            ?assert(kapi_acdc_callback:request_v(kz_json:decode(iolist_to_binary(Payload)))),
            ?assertEqual(kapi_acdc_callback:routing_key(?ACCOUNT, ?QUEUE, ?CALL), Key), ok
        end),
        meck:expect(kz_amqp_util, targeted_publish, fun(<<"reply">>, Payload, <<"application/json">>) ->
            ?assert(kapi_acdc_callback:response_v(kz_json:decode(iolist_to_binary(Payload)))), ok
        end),
        ?assertEqual(ok, kapi_acdc_callback:publish_request(request(<<"register">>))),
        ?assertEqual(ok, kapi_acdc_callback:publish_response(<<"reply">>, response(<<"pause">>, <<"paused">>))),
        ?assertMatch({error, _}, kapi_acdc_callback:publish_request(kz_json:delete_key(<<"Number">>, request(<<"register">>)))),
        ?assertEqual({error, invalid_reply_queue}, kapi_acdc_callback:publish_response(<<>>, response(<<"pause">>, <<"paused">>))),
        ?assertEqual(1, meck:num_calls(kz_amqp_util, callmgr_publish, '_')),
        ?assertEqual(1, meck:num_calls(kz_amqp_util, targeted_publish, '_'))
    after meck:unload(kz_amqp_util) end.

request(Operation) ->
    Extra = case Operation of
        <<"pause">> -> [];
        <<"register">> -> [{<<"Pause-ID">>, ?PAUSE}, {<<"Number">>, <<"+12025550123">>}];
        _ -> [{<<"Pause-ID">>, ?PAUSE}]
    end,
    kz_json:from_list(Extra ++ [{<<"Server-ID">>, <<"caller-controller">>}, {<<"Event-Name">>, <<"request">>}
                               | common(Operation)]).
response(Operation, Status) ->
    Extra = case Status of <<"registered">> -> [{<<"Callback-ID">>, ?CALLBACK}]; _ -> [] end,
    kz_json:from_list(Extra ++ [{<<"Pause-ID">>, ?PAUSE}, {<<"Status">>, Status}, {<<"Event-Name">>, <<"response">>}
                               | common(Operation)]).
common(Operation) ->
    [{<<"Account-ID">>, ?ACCOUNT}, {<<"Queue-ID">>, ?QUEUE}, {<<"Call-ID">>, ?CALL}
    ,{<<"Request-ID">>, ?REQUEST}, {<<"Operation">>, Operation}, {<<"Event-Category">>, <<"acdc_callback">>}
    ,{<<"Msg-ID">>, ?REQUEST}, {<<"App-Name">>, <<"callback-test">>}, {<<"App-Version">>, <<"1">>}].
