%%% SPDX-License-Identifier: MPL-2.0
-module(acdc_callback_internal_tests).
-include_lib("eunit/include/eunit.hrl").
-define(A, <<"11111111111111111111111111111111">>).
-define(U, <<"22222222222222222222222222222222">>).
-define(D, <<"33333333333333333333333333333333">>).
-define(C, <<"44444444444444444444444444444444">>).
-define(R, <<"internal.example.invalid">>).

external_does_not_query_directory_test() ->
    lists:foreach(fun(N) ->
        ?assertEqual(not_internal, acdc_callback_internal:resolve_with(?A, N,
                         fun() -> error(unexpected_directory_query) end, fun(_) -> error(unexpected_fetch) end))
    end, [<<"+12025550100">>, <<"12025550100">>, <<"kz5_test">>, <<"1000;route=x">>, undefined]).

exact_user_extension_test() ->
    {ok, Target} = resolve(flow(), user()),
    ?assertEqual(target(), Target).

exact_device_extension_test() ->
    F = kz_json:set_values([{[<<"flow">>, <<"module">>], <<"device">>}
                            ,{[<<"flow">>, <<"data">>, <<"id">>], ?D}], flow()),
    {ok, Target} = resolve(F, device()),
    ?assertEqual(?D, value(<<"id">>, Target)).

directory_failure_never_falls_back_to_carrier_test() ->
    lists:foreach(fun({Rows, Expected}) ->
        ?assertEqual(Expected, acdc_callback_internal:resolve_with(?A, <<"1000">>, fun() -> Rows end, fun(_) -> {ok, user()} end))
    end, [{{error, timeout}, {error, internal_directory_unavailable}}
          ,{{ok, [obj([]), obj([])]}, {error, ambiguous_internal_extension}}
          ,{{ok, []}, not_internal}]).

complex_or_cross_account_callflow_rejected_test() ->
    lists:foreach(fun(F) -> ?assertEqual({error, unsupported_internal_callflow}, resolve(F, user())) end,
      [kz_json:set_value(<<"pvt_account_id">>, ?D, flow())
       ,kz_json:set_value(<<"pvt_deleted">>, true, flow())
       ,kz_json:set_value(<<"numbers">>, [<<"1001">>], flow())
       ,kz_json:set_value([<<"flow">>, <<"module">>], <<"resources">>, flow())
       ,kz_json:set_value([<<"flow">>, <<"data">>, <<"skip_module">>], true, flow())
       ,kz_json:set_value([<<"flow">>, <<"children">>, <<"_">>], obj([{<<"module">>, <<"voicemail">>}]), flow())]).

disabled_or_cross_account_target_rejected_test() ->
    lists:foreach(fun(U) -> ?assertEqual({error, internal_target_unavailable}, resolve(flow(), U)) end,
      [kz_json:set_value(<<"pvt_account_id">>, ?D, user())
       ,kz_json:set_value(<<"enabled">>, false, user())
       ,kz_json:set_value([<<"do_not_disturb">>, <<"enabled">>], true, user())
       ,kz_json:set_value(<<"pvt_deleted">>, true, user())]).

reservation_target_pinning_test() ->
    ?assert(acdc_callback_internal:same_target(target(), target())),
    lists:foreach(fun(Key) ->
        ?assertNot(acdc_callback_internal:same_target(target(), kz_json:set_value(Key, <<"changed">>, target())))
    end, [<<"number">>, <<"flow_id">>, <<"type">>, <<"id">>]),
    ?assertNot(acdc_callback_internal:same_target(obj([]), obj([]))).

only_local_native_device_endpoints_allowed_test() ->
    ?assert(acdc_callback_internal:safe_device(device(), ?A, ?R)),
    lists:foreach(fun(D) -> ?assertNot(acdc_callback_internal:safe_device(D, ?A, ?R)) end,
        [kz_json:set_value([<<"sip">>, <<"route">>], <<"sip:outside.example">>, device())
         ,kz_json:set_value([<<"sip">>, <<"realm">>], <<"outside.example">>, device())
         ,kz_json:set_value([<<"call_forward">>, <<"enabled">>], true, device())
         ,kz_json:set_value(<<"device_type">>, <<"mobile">>, device())
         ,kz_json:set_value(<<"enabled">>, false, device())]),
    ?assert(acdc_callback_internal:safe_endpoint(endpoint(), ?A, ?D)),
    lists:foreach(fun(E) -> ?assertNot(acdc_callback_internal:safe_endpoint(E, ?A, ?D)) end,
        [kz_json:set_value(<<"Invite-Format">>, <<"loopback">>, endpoint())
         ,kz_json:set_value(<<"Route">>, <<"+12025550100">>, endpoint())
         ,kz_json:set_value(<<"Account-ID">>, ?U, endpoint())
         ,kz_json:set_value(<<"Endpoint-ID">>, ?U, endpoint())
         ,kz_json:set_value(<<"Endpoint-URI">>, <<"evil@elsewhere">>, endpoint())]).

resource_ready_preserves_exact_correlation_test() ->
    Ready = event(<<"dialplan">>, <<"originate_ready">>,
                  [{<<"Originate-UUID">>, <<"originate-uuid">>}, {<<"Originate-Queue">>, <<"originate.queue">>}]),
    {ok, Outer} = acdc_callback_internal:resource_response(?C, <<"msg-id">>, Ready),
    {ok, Parsed} = acdc_callback_policy:parse_response(?C, <<"msg-id">>, Outer),
    ?assertEqual(ready, maps:get(response, Parsed)),
    ?assertEqual(<<"msg-id">>, maps:get(originate_msg_id, Parsed)),
    ?assertEqual(<<"originate.queue">>, maps:get(originate_queue, Parsed)),
    ?assertEqual({error, stale_response}, acdc_callback_internal:resource_response(?C, <<"other">>, Ready)).

malformed_resource_response_does_not_crash_test() ->
    lists:foreach(fun(Value) ->
        ?assertEqual({error, invalid_response},
            acdc_callback_internal:resource_response(?C, <<"msg-id">>, Value))
    end, [undefined, <<"invalid">>, 123, [], #{}, obj([{<<"Msg-ID">>, <<"msg-id">>}])]).

resource_success_requires_exact_call_and_control_queue_test_() ->
    {timeout, 30, fun() -> with_language_defaults(fun resource_success_checks/0) end}.

resource_success_checks() ->
    Success = event(<<"resource">>, <<"originate_resp">>,
                    [{<<"Call-ID">>, ?C}, {<<"Control-Queue">>, <<"control.queue">>}
                     ,{<<"Application-Response">>, <<"SUCCESS">>}]),
    {ok, Outer} = acdc_callback_internal:resource_response(?C, <<"msg-id">>, Success),
    ?assertMatch({ok, #{response := success, control_queue := <<"control.queue">>}},
                 acdc_callback_policy:parse_response(?C, <<"msg-id">>, Outer)),
    ?assertEqual({error, stale_response}, acdc_callback_internal:resource_response(?D, <<"msg-id">>, Success)),
    {ok, Missing} = acdc_callback_internal:resource_response(?C, <<"msg-id">>, kz_json:delete_key(<<"Control-Queue">>, Success)),
    ?assertEqual({error, missing_control_queue}, acdc_callback_policy:parse_response(?C, <<"msg-id">>, Missing)).

request_build_test_() ->
    {timeout, 30, fun() -> with_language_defaults(fun() ->
        meck:new(kz_datamgr, [passthrough, no_link]),
        meck:new(kz_endpoint, [passthrough, no_link]),
        try
            meck:expect(kz_datamgr, get_results, fun(_, <<"callflows/listing_by_number">>, _) ->
                                                       {ok, [obj([{<<"doc">>, flow()}])]};
                                                  (_, <<"attributes/owned">>, _) ->
                                                       {ok, [obj([{<<"value">>, ?D}])]} end),
            meck:expect(kz_datamgr, open_doc, fun(_, ?U) -> {ok, user()} end),
            meck:expect(kz_endpoint, get, fun(?D, _, _) -> {ok, device()} end),
            meck:expect(kz_endpoint, build, fun(_, _, _) -> {ok, [endpoint()]} end),
            {ok, Request} = build(target()),
            ?assert(kapi_resource:originate_req_v(Request)),
            ?assertEqual({<<"resource">>, <<"originate_req">>}, kz_api:event_type(Request)),
            ?assertEqual(?C, value(<<"Outbound-Call-ID">>, Request)),
            ?assertEqual(false, value(<<"Originate-Immediate">>, Request)),
            ?assertEqual(<<"park">>, value(<<"Application-Name">>, Request)),
            ?assertEqual(undefined, value(<<"To-DID">>, Request)),
            ?assertEqual(undefined, value(<<"Hunt-Account-ID">>, Request)),
            ?assertEqual([endpoint()], value(<<"Endpoints">>, Request)),
            ?assertEqual(?A, value([<<"Custom-Channel-Vars">>, <<"Account-ID">>], Request)),
            ?assertEqual(undefined, value([<<"Custom-Channel-Vars">>, <<"Channel-Authorized">>], Request)),
            ?assertEqual({error, internal_target_changed}, build(kz_json:set_value(<<"id">>, ?D, target()))),
            meck:expect(kz_endpoint, build, fun(_, _, _) ->
                                                {ok, [kz_json:set_value(<<"Invite-Format">>, <<"loopback">>, endpoint())]} end),
            ?assertEqual({error, internal_endpoints_unavailable}, build(target()))
        after meck:unload(kz_endpoint), meck:unload(kz_datamgr) end
    end) end}.

with_language_defaults(Test) ->
    meck:new(kz_media_util, [passthrough, no_link]),
    meck:new(kapps_config, [passthrough, no_link]),
    try
        meck:expect(kapps_config, get_ne_binary, fun(_, _, Default) -> Default end),
        meck:expect(kapps_config, get_ne_binary, fun(_, _, Default, _) -> Default end),
        meck:expect(kapps_config, get_binary, fun(_, _, Default) -> Default end),
        meck:expect(kz_media_util, prompt_language, fun(_) -> <<"en-us">> end),
        meck:expect(kz_media_util, prompt_language, fun(_, _) -> <<"en-us">> end),
        Test()
    after meck:unload(kapps_config), meck:unload(kz_media_util) end.

build(Target) ->
    acdc_callback_internal:build_request(?A, obj([{<<"name">>, <<"Support callback">>}]),
      obj([{<<"number">>, <<"1000">>}, {<<"pvt_caller_call_id">>, ?C}, {<<"attempts">>, 1}
           ,{<<"_id">>, <<"acdc-callback-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>}]),
      <<"callback.reply">>, #{realm => ?R, authority_id => ?U, authority_type => <<"user">>}, Target).
resolve(F, D) ->
    acdc_callback_internal:resolve_with(?A, <<"1000">>, fun() -> {ok, [obj([{<<"doc">>, F}])]} end,
                                       fun(_) -> {ok, D} end).
target() -> obj([{<<"number">>, <<"1000">>}, {<<"flow_id">>, <<"flow-id">>}, {<<"type">>, <<"user">>}, {<<"id">>, ?U}]).
flow() -> obj([{<<"_id">>, <<"flow-id">>}, {<<"pvt_type">>, <<"callflow">>}, {<<"pvt_account_id">>, ?A}
               ,{<<"numbers">>, [<<"1000">>]}, {<<"flow">>, obj([{<<"module">>, <<"user">>}
                 ,{<<"data">>, obj([{<<"id">>, ?U}])}, {<<"children">>, obj([])}])}]).
user() -> obj([{<<"_id">>, ?U}, {<<"pvt_type">>, <<"user">>}, {<<"pvt_account_id">>, ?A}, {<<"enabled">>, true}]).
device() -> obj([{<<"_id">>, ?D}, {<<"pvt_type">>, <<"device">>}, {<<"pvt_account_id">>, ?A}
                 ,{<<"owner_id">>, ?U}, {<<"Endpoint-ID">>, ?D}, {<<"Endpoint-Type">>, <<"device">>}
                 ,{<<"sip">>, obj([{<<"username">>, <<"kz5_test">>}, {<<"realm">>, ?R}])}]).
endpoint() -> obj([{<<"Invite-Format">>, <<"endpoint">>}, {<<"Account-ID">>, ?A}, {<<"Endpoint-ID">>, ?D}
                   ,{<<"Endpoint-URI">>, <<?D/binary, "@", ?A/binary>>}]).
event(Category, Name, Props) -> obj([{<<"Msg-ID">>, <<"msg-id">>} | Props ++ kz_api:default_headers(Category, Name, <<"test">>, <<"1">>)]).
value(Key, JObj) -> kz_json:get_value(Key, JObj).
obj(Props) -> kz_json:from_list(Props).
