%%% Actual kapi/kz_api/JSON, with only the final targeted broker sink replaced.
%%% Separate baseline/candidate VMs; not a live listener restart or AMQP proof.
-module(acdc_agent_sync_status_tests).
-include_lib("eunit/include/eunit.hrl").

sync_status_test_() ->
    Mode = os:getenv("KAZOO_SYNC_STATUS_MODE"),
    Tests = case Mode of
        "baseline" -> [{"actual pre-fix outbound prepare/publish failure", fun before_fix/0}];
        "candidate" -> [{binary_to_list(S), fun() -> roundtrip(S) end} || S <- allowed()]
    end,
    {setup, fun setup/0, fun cleanup/1,
     [{"bound to every current FSM send_sync_resp status", fun emitted_states/0},
      {"unknown statuses remain rejected without publishing", fun rejected_states/0} | Tests]}.

setup() ->
    %% Keep actual Lager metadata behavior, but do not start a logging service.
    ok = lager_config:new(), _ = lager_config:set(loglevel, {0, []}),
    ok = meck:new(kz_amqp_util, [no_link]),
    meck:expect(kz_amqp_util, targeted_publish,
        fun(<<"fixture-reply">>, Payload, <<"application/json">>) ->
            put(sync_status_payload, iolist_to_binary(Payload)), ok
        end).
cleanup(_) -> meck:unload(kz_amqp_util).

allowed() -> [<<"init">>, <<"sync">>, <<"ready">>, <<"waiting">>, <<"ringing">>,
              <<"answered">>, <<"wrapup">>, <<"paused">>, <<"outbound">>].
response(Status) ->
    [{<<"Account-ID">>, <<"11111111111111111111111111111111">>},
     {<<"Agent-ID">>, <<"22222222222222222222222222222222">>},
     {<<"Status">>, Status}, {<<"Process-ID">>, <<"fixture-process">>},
     {<<"Queues">>, [<<"33333333333333333333333333333333">>]},
     {<<"Msg-ID">>, <<"fixture-request">>},
     {<<"Event-Category">>, <<"agent">>}, {<<"Event-Name">>, <<"sync_resp">>}
     | kz_api:default_headers(<<"fixture-listener">>, <<"acdc">>, <<"4.0.0">>)].
prepare(Props) ->
    kz_api:prepare_api_payload(Props,
        [{<<"Event-Category">>, <<"agent">>}, {<<"Event-Name">>, <<"sync_resp">>}],
        fun kapi_acdc_agent:sync_resp/1).
publish_count() -> meck:num_calls(kz_amqp_util, targeted_publish, ['_', '_', '_']).

before_fix() ->
    Props = response(<<"outbound">>), Before = publish_count(),
    Normalized = kz_api:prepare_api_payload(Props, [{<<"Status">>, [<<"ready">>]}]),
    ?assertEqual(<<"outbound">>, props:get_value(<<"Status">>, Normalized)),
    ?assertNot(kapi_acdc_agent:sync_resp_v(Props)),
    ?assertEqual({error, "Proplist failed validation for sync_resp"}, prepare(Props)),
    ?assertError({badmatch, {error, "Proplist failed validation for sync_resp"}},
                 kapi_acdc_agent:publish_sync_resp(<<"fixture-reply">>, Props)),
    ?assertEqual(Before, publish_count()),
    %% A passing existing-state control prevents mistaking setup failure for the bug.
    roundtrip(<<"ready">>).

roundtrip(Status) ->
    Props = response(Status), Before = publish_count(),
    ?assert(kapi_acdc_agent:sync_resp_v(Props)),
    {ok, Prepared} = prepare(Props), assert_fields(Props, Prepared),
    erase(sync_status_payload),
    ?assertEqual(ok, kapi_acdc_agent:publish_sync_resp(<<"fixture-reply">>, Props)),
    ?assertEqual(Before + 1, publish_count()),
    assert_fields(Props, get(sync_status_payload)).
assert_fields(Props, Bytes) ->
    J = kz_json:decode(iolist_to_binary(Bytes)),
    ?assert(kapi_acdc_agent:sync_resp_v(J)),
    [?assertEqual(props:get_value(K, Props), kz_json:get_value(K, J)) || K <-
        [<<"Account-ID">>, <<"Agent-ID">>, <<"Status">>, <<"Process-ID">>,
         <<"Queues">>, <<"Msg-ID">>, <<"Server-ID">>, <<"Event-Category">>, <<"Event-Name">>]].

rejected_states() ->
    [?assertEqual(ok, rejected(S)) || S <-
        [<<"invented">>, <<"wait">>, <<"OUTBOUND">>, <<>>, outbound, null, undefined]].
rejected(Status) ->
    Props = response(Status), Before = publish_count(),
    ?assertNot(kapi_acdc_agent:sync_resp_v(Props)),
    ?assertEqual({error, "Proplist failed validation for sync_resp"}, prepare(Props)),
    ?assertError({badmatch, {error, "Proplist failed validation for sync_resp"}},
                 kapi_acdc_agent:publish_sync_resp(<<"fixture-reply">>, Props)),
    ?assertEqual(Before, publish_count()), ok.

emitted_states() ->
    {ok, Source} = file:read_file(filename:join(os:getenv("KAZOO_SYNC_STATUS_ROOT"),
        "applications/acdc/src/acdc_agent_fsm.erl")),
    {match, Matches} = re:run(Source,
        <<"acdc_agent_listener:send_sync_resp\\(\\s*AgentListener,\\s*'([a-z_]+)'">>,
        [global, {capture, [1], binary}]),
    Actual = lists:usort([S || [S] <- Matches]),
    ?assertEqual(lists:sort([<<"sync">>, <<"ready">>, <<"ringing">>, <<"answered">>,
                             <<"wrapup">>, <<"paused">>, <<"outbound">>]), Actual),
    ?assert(lists:all(fun(S) -> lists:member(S, allowed()) end, Actual)).
