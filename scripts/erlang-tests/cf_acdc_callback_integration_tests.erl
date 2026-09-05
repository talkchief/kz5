%%% SPDX-License-Identifier: MPL-2.0
-module(cf_acdc_callback_integration_tests).

-include_lib("eunit/include/eunit.hrl").

-define(ACCOUNT, <<"0123456789abcdef0123456789abcdef">>).
-define(QUEUE, <<"queue-1">>).
-define(CALL, <<"original-call-1">>).
-define(REQUEST, <<"fedcba9876543210fedcba9876543210">>).
-define(PAUSE, <<"0123456789abcdef0123456789abcdef0123456789abcdef">>).

register_request_is_minimal_and_protocol_valid_test() ->
    Context = context(),
    Request0 = cf_acdc_member:callback_test_request(
                 Context, <<"register">>
                ,[{<<"Pause-ID">>, ?PAUSE}, {<<"Number">>, <<"+12025550123">>}]),
    ?assertEqual('undefined', props:get_value(<<"Call">>, Request0)),
    ?assertEqual('undefined', props:get_value(<<"Outbound-Authority">>, Request0)),
    ?assertEqual(?PAUSE, props:get_value(<<"Pause-ID">>, Request0)),
    Request = [{<<"Server-ID">>, <<"original-controller-queue">>}
              ,{<<"Event-Category">>, <<"acdc_callback">>}
              ,{<<"Event-Name">>, <<"request">>}
              ,{<<"Msg-ID">>, ?REQUEST} | Request0],
    ?assert(kapi_acdc_callback:request_v(Request)).

response_requires_full_scope_and_valid_wire_shape_test() ->
    Response = response(<<"pause">>, <<"paused">>, [{<<"Pause-ID">>, ?PAUSE}]),
    ?assertEqual({ok, <<"pause">>, <<"paused">>, ?PAUSE, 'undefined'}
                ,cf_acdc_member:callback_test_response(Response, context())),
    StaleRequest = kz_json:set_value(<<"Request-ID">>, <<"00000000000000000000000000000000">>, Response),
    ?assertEqual(nomatch, cf_acdc_member:callback_test_response(StaleRequest, context())),
    Malformed = kz_json:delete_key(<<"Pause-ID">>, Response),
    ?assertEqual(nomatch, cf_acdc_member:callback_test_response(Malformed, context())).

english_defaults_and_foreign_language_fail_closed_test() ->
    Empty = kz_json:new(),
    {ok, Defaults} = cf_acdc_member:callback_test_media(Empty, <<"en-US">>),
    ?assertEqual(<<"acdc-callback-offer-6">>, maps:get(offer, Defaults)),
    ?assertEqual(<<"acdc-callback-menu-current">>, maps:get(menu, Defaults)),
    ?assertEqual(<<"acdc-callback-success">>, maps:get(success, Defaults)),
    ?assertMatch({error, {missing_media, offer}}
                ,cf_acdc_member:callback_test_media(Empty, <<"es-ES">>)),

    Configured = kz_json:set_values(
                   [{[<<"callback">>, <<"entry_key">>], <<"9">>}
                   ,{[<<"callback">>, <<"allow_alternate_number">>], true}
                    | [{[<<"callback">>, <<"media">>, Key], <<"account-media-", Key/binary>>}
                    || Key <- [<<"offer">>, <<"menu">>, <<"number_readback">>
                              ,<<"confirmation">>, <<"success">>]]], Empty),
    {ok, Spanish} = cf_acdc_member:callback_test_media(Configured, <<"es_ES">>),
    ?assertEqual(<<"account-media-menu">>, maps:get(menu, Spanish)),

    AlternateEnglish = kz_json:set_values([{[<<"callback">>, <<"entry_key">>], <<"3">>}
                                          ,{[<<"callback">>, <<"allow_alternate_number">>], true}], Empty),
    {ok, AlternateDefaults} = cf_acdc_member:callback_test_media(AlternateEnglish, <<"en-us">>),
    ?assertEqual(<<"acdc-callback-offer-3">>, maps:get(offer, AlternateDefaults)),
    ?assertEqual(<<"acdc-callback-menu-alternate">>, maps:get(menu, AlternateDefaults)).

alternate_entry_is_audible_without_replaying_between_digits_test_() ->
    {timeout, 30, fun() -> with_callback_commands(fun() ->
        lists:foreach(fun(Current) ->
            Now = erlang:monotonic_time(millisecond),
            {ok, Initial, _} = acdc_callback_menu:new(menu_config(), Current, Now),
            Collecting = case acdc_callback_menu:status(Initial) of
                menu ->
                    {Selected, [collect_alternate]} = acdc_callback_menu:event({dtmf, <<"2">>}, Now, Initial),
                    Selected;
                collecting -> Initial
            end,
            Before = meck:num_calls(kapps_call_command, prompt, '_'),
            {First, []} = collect_and_reduce(<<"1">>, Collecting),
            ?assertEqual(Before + 1, meck:num_calls(kapps_call_command, prompt, '_')),
            {Second, []} = collect_and_reduce(<<"0">>, First),
            ?assertEqual(Before + 1, meck:num_calls(kapps_call_command, prompt, '_')),
            {Confirming, [{read_back_number, <<"10">>}, {prompt_confirm_alternate, <<"1">>}]} =
                collect_and_reduce(<<"#">>, Second),
            ?assertEqual(false, maps:get(registration_emitted, Confirming)),
            ?assertEqual(confirming_alternate, acdc_callback_menu:status(Confirming))
        end, [<<"anonymous">>, <<"1000">>]),
        ?assert(meck:validate(kapps_call_command))
    end) end}.

alternate_wrapper_preserves_invalid_digits_and_cancellation_test_() ->
    {timeout, 30, fun() -> with_callback_commands(fun() ->
        {ok, Initial, _} = acdc_callback_menu:new(menu_config(), undefined, erlang:monotonic_time(millisecond)),
        {Empty, [{retry, 2}]} = collect_and_reduce(<<"#">>, Initial),
        {Invalid, [{retry, 1}]} = collect_and_reduce(<<"A">>, Empty),
        ?assertEqual(<<>>, maps:get(digits, Invalid)),
        ?assertEqual(false, maps:get(registration_emitted, Invalid)),
        {Cancelled, [{resume_live_queue, caller_cancelled}]} = collect_and_reduce(<<"*">>, Invalid),
        ?assertEqual(aborted, acdc_callback_menu:status(Cancelled)),
        ?assertEqual(3, meck:num_calls(kapps_call_command, prompt, '_'))
    end) end}.

alternate_wrapper_bounds_prompt_wait_and_observes_hangup_test_() ->
    {timeout, 30, fun() -> with_callback_commands(fun() ->
        {ok, Initial, _} = acdc_callback_menu:new(menu_config(), undefined, erlang:monotonic_time(millisecond)),
        Expired = Initial#{deadline_ms => erlang:monotonic_time(millisecond) - 1},
        ?assertEqual(timeout, cf_acdc_member:callback_test_collect_alternate(fixture_call, Expired)),
        ?assertEqual(0, meck:num_calls(kapps_call_command, prompt, '_')),
        %% Use the real wait_for_dtmf/1 and real mailbox. A missing playback
        %% noop is bounded, and unrelated/noop events cannot renew the budget.
        Deadline = erlang:monotonic_time(millisecond) + 100,
        Waiting = Initial#{deadline_ms => Deadline},
        Noop = call_event(<<"CHANNEL_EXECUTE_COMPLETE">>, [{<<"Application-Name">>, <<"noop">>}]),
        self() ! {amqp_msg, Noop},
        _ = erlang:send_after(30, self(), {amqp_msg, Noop}),
        _ = erlang:send_after(60, self(), {amqp_msg, Noop}),
        ?assertEqual(timeout, cf_acdc_member:callback_test_collect_alternate(fixture_call, Waiting)),
        ?assert(erlang:monotonic_time(millisecond) >= Deadline),
        ?assert(erlang:monotonic_time(millisecond) < Deadline + 200),
        {Aborted, [{resume_live_queue, deadline}]} =
            acdc_callback_menu:event(tick, erlang:monotonic_time(millisecond), Waiting),
        ?assertEqual(aborted, acdc_callback_menu:status(Aborted)),
        self() ! {amqp_msg, call_event(<<"CHANNEL_DESTROY">>, [])},
        ?assertEqual(hangup, cf_acdc_member:callback_test_collect_alternate(fixture_call, Initial)),
        ?assertEqual(2, meck:num_calls(kapps_call_command, prompt, '_'))
    end) end}.

with_callback_commands(Fun) ->
    meck:new(kapps_call_command, [passthrough, no_link]),
    try
        meck:expect(kapps_call_command, prompt,
                    fun(<<"cf-enter_number">>, fixture_call) -> <<"fixture-prompt-noop">> end),
        Fun()
    after meck:unload(kapps_call_command) end.

collect_and_reduce(Digit, State) ->
    self() ! {amqp_msg, call_event(<<"DTMF">>, [{<<"DTMF-Digit">>, Digit}])},
    {ok, Received} = cf_acdc_member:callback_test_collect_alternate(fixture_call, State),
    acdc_callback_menu:event({dtmf, Received}, erlang:monotonic_time(millisecond), State).

call_event(Name, Extra) ->
    kz_json:from_list([{<<"Event-Category">>, <<"call_event">>}, {<<"Event-Name">>, Name} | Extra]).

menu_config() ->
    #{request_id => ?REQUEST, queue_id => ?QUEUE, original_call_id => ?CALL
     ,allow_alternate_number => true, max_retries => 3, timeout_ms => 30000}.

context() ->
    #{account_id => ?ACCOUNT
     ,queue_id => ?QUEUE
     ,call_id => ?CALL
     ,request_id => ?REQUEST
     ,pause_id => ?PAUSE}.

response(Operation, Status, Extra) ->
    kz_json:from_list(
      [{<<"Event-Category">>, <<"acdc_callback">>}
      ,{<<"Event-Name">>, <<"response">>}
      ,{<<"Account-ID">>, ?ACCOUNT}
      ,{<<"Queue-ID">>, ?QUEUE}
      ,{<<"Call-ID">>, ?CALL}
      ,{<<"Request-ID">>, ?REQUEST}
      ,{<<"Operation">>, Operation}
      ,{<<"Status">>, Status}
      ,{<<"Msg-ID">>, ?REQUEST}
      ,{<<"App-Name">>, <<"callback-integration-test">>}
      ,{<<"App-Version">>, <<"1">>} | Extra]).
