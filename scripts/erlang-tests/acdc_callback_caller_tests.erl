%%% SPDX-License-Identifier: MPL-2.0
-module(acdc_callback_caller_tests).
-include_lib("eunit/include/eunit.hrl").

-define(ACCOUNT, <<"11111111111111111111111111111111">>).
-define(QUEUE, <<"callback-test-queue">>).
-define(CALLBACK_ID,
        <<"acdc-callback-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(ORIGINAL_CALL_ID, <<"22222222222222222222222222222222">>).
-define(CALLER_CALL_ID, <<"33333333333333333333333333333333">>).
-define(TOKEN, <<"44444444444444444444444444444444">>).

confirmation_deadline_starts_after_correlated_prompt_test_() ->
    {timeout, 30, fun confirmation_deadline_starts_after_correlated_prompt/0}.

confirmation_deadline_starts_after_correlated_prompt() ->
    meck:new(acdc_gemini_prompts, [no_link]),
    meck:new(kapps_call_command, [no_link]),
    put(confirmation_test_timers, []),
    try
        meck:expect(acdc_gemini_prompts, selection, fun(_, _) -> absent end),
        meck:expect(acdc_gemini_prompts, builtin, fun(_, _) -> {ok, <<"/installed/prompt.wav">>} end),
        meck:expect(kapps_call_command, play, fun(_, _) -> <<"prompt-completion">> end),
        meck:expect(kapps_call_command, hangup, fun(_) -> ok end),
        Queue = kz_json:set_value([<<"callback">>, <<"confirmation_timeout">>], 3, queue()),
        Call = kapps_call:set_language(<<"en-us">>, kapps_call:set_call_id(?CALLER_CALL_ID, kapps_call:new())),
        Initial = acdc_callback_caller:confirmation_test_state(Queue, Call),
        Playing = confirmation_event_state(<<"CHANNEL_ANSWER">>, [], Initial),
        PlaybackTimer = confirmation_timer(Playing),
        %% The installed EN prompt is longer than the legal three-second
        %% response timeout. Playback must have its own bounded watchdog.
        ?assert(erlang:read_timer(PlaybackTimer) > 3000),
        WrongCall = confirmation_event_state(<<"CHANNEL_EXECUTE_COMPLETE">>,
            [{<<"Call-ID">>, <<"foreign-call">>}, {<<"Application-Name">>, <<"noop">>},
             {<<"Application-Response">>, <<"prompt-completion">>}], Playing),
        ?assertEqual(Playing, WrongCall),
        WrongNoop = confirmation_event_state(<<"CHANNEL_EXECUTE_COMPLETE">>,
            [{<<"Application-Name">>, <<"noop">>}, {<<"Application-Response">>, <<"foreign-noop">>}], Playing),
        ?assertEqual(Playing, WrongNoop),
        PlayEvent = confirmation_event_state(<<"CHANNEL_EXECUTE_COMPLETE">>,
            [{<<"Application-Name">>, <<"play">>}, {<<"Application-Response">>, <<"prompt-completion">>}], Playing),
        ?assertEqual(Playing, PlayEvent),
        Completion = [{<<"Application-Name">>, <<"noop">>}, {<<"Application-Response">>, <<"prompt-completion">>}],
        Waiting = confirmation_event_state(<<"CHANNEL_EXECUTE_COMPLETE">>, Completion, Playing),
        ResponseTimer = confirmation_timer(Waiting),
        ?assertNotEqual(PlaybackTimer, ResponseTimer),
        ?assertEqual(false, erlang:read_timer(PlaybackTimer)),
        ?assert(erlang:read_timer(ResponseTimer) =< 3000),
        ?assert(erlang:read_timer(ResponseTimer) > 0),
        ?assertEqual(Waiting, confirmation_event_state(<<"CHANNEL_EXECUTE_COMPLETE">>, Completion, Waiting)),
        ?assertEqual({noreply, Waiting}, acdc_callback_caller:handle_info({timeout, PlaybackTimer, confirming}, Waiting)),
        ?assertEqual(Waiting, confirmation_event_state(<<"CHANNEL_ANSWER">>, [], Waiting)),
        Confirmed = confirmation_event_state(<<"DTMF">>, [{<<"DTMF-Digit">>, <<"1">>}], Waiting),
        ?assertEqual(waiting_handoff, maps:get(stage, acdc_callback_caller:confirmation_test_info(Confirmed))),
        receive {acdc_callback_caller_confirmed, <<"confirmation-test">>, <<"confirmation-token">>, Call} -> ok
        after 0 -> ?assert(false)
        end,
        ?assertEqual(Confirmed, confirmation_event_state(<<"CHANNEL_EXECUTE_COMPLETE">>, Completion, Confirmed)),
        ?assertEqual(Confirmed, confirmation_event_state(<<"CHANNEL_ANSWER">>, [], Confirmed)),
        %% Confirmation during the recording still works and cancels the
        %% playback watchdog; a late noop must not replace the handoff timer.
        Playing2 = confirmation_event_state(<<"CHANNEL_ANSWER">>, [], Initial),
        Early = confirmation_event_state(<<"DTMF">>, [{<<"DTMF-Digit">>, <<"1">>}], Playing2),
        ?assertEqual(false, erlang:read_timer(confirmation_timer(Playing2))),
        ?assertEqual(waiting_handoff, maps:get(stage, acdc_callback_caller:confirmation_test_info(Early))),
        ?assertEqual(Early, confirmation_event_state(<<"CHANNEL_EXECUTE_COMPLETE">>, Completion, Early)),
        receive {acdc_callback_caller_confirmed, <<"confirmation-test">>, <<"confirmation-token">>, Call} -> ok
        after 0 -> ?assert(false)
        end,
        Playing3 = confirmation_event_state(<<"CHANNEL_ANSWER">>, [], Initial),
        Ref3 = confirmation_timer(Playing3),
        _ = erlang:cancel_timer(Ref3),
        {noreply, Cleaning} = acdc_callback_caller:handle_info({timeout, Ref3, confirming}, Playing3),
        put(confirmation_test_timers, [confirmation_timer(Cleaning) | get(confirmation_test_timers)]),
        ?assertEqual(media_failed, maps:get(cause, acdc_callback_caller:confirmation_test_info(Cleaning))),
        ?assertEqual(cleaning, maps:get(stage, acdc_callback_caller:confirmation_test_info(Cleaning))),
        ?assertEqual(Cleaning, confirmation_event_state(<<"CHANNEL_EXECUTE_COMPLETE">>, Completion, Cleaning)),
        ?assertEqual(Cleaning, confirmation_event_state(<<"CHANNEL_ANSWER">>, [], Cleaning)),
        Playing4 = confirmation_event_state(<<"CHANNEL_ANSWER">>, [], Initial),
        Waiting4 = confirmation_event_state(<<"CHANNEL_EXECUTE_COMPLETE">>, Completion, Playing4),
        Ref4 = confirmation_timer(Waiting4),
        _ = erlang:cancel_timer(Ref4),
        {noreply, Expired} = acdc_callback_caller:handle_info({timeout, Ref4, confirming}, Waiting4),
        put(confirmation_test_timers, [confirmation_timer(Expired) | get(confirmation_test_timers)]),
        ?assertEqual(confirmation_timeout, maps:get(cause, acdc_callback_caller:confirmation_test_info(Expired))),
        ?assertEqual(Expired, confirmation_event_state(<<"DTMF">>, [{<<"DTMF-Digit">>, <<"1">>}], Expired)),
        ?assertEqual(Expired, confirmation_event_state(<<"CHANNEL_EXECUTE_COMPLETE">>, Completion, Expired)),
        meck:expect(kapps_call_command, play, fun(_, _) -> undefined end),
        InvalidPlay = confirmation_event_state(<<"CHANNEL_ANSWER">>, [], Initial),
        ?assertEqual(media_failed, maps:get(cause, acdc_callback_caller:confirmation_test_info(InvalidPlay)))
    after
        lists:foreach(fun erlang:cancel_timer/1, erase(confirmation_test_timers)),
        meck:unload(kapps_call_command), meck:unload(acdc_gemini_prompts)
    end.

confirmation_event_state(Name, Fields, State) ->
    Event = kz_json:from_list([{<<"Event-Category">>, <<"call_event">>}, {<<"Event-Name">>, Name}
                              | Fields ++ case proplists:is_defined(<<"Call-ID">>, Fields) of
                                              true -> []; false -> [{<<"Call-ID">>, ?CALLER_CALL_ID}]
                                          end]),
    {noreply, Next} = acdc_callback_caller:handle_cast({call_event, Event}, State),
    put(confirmation_test_timers, lists:usort([confirmation_timer(Next) | get(confirmation_test_timers)])),
    Next.

confirmation_timer(State) -> maps:get(timer, acdc_callback_caller:confirmation_test_info(State)).

cleanup_disposition_requires_positive_proof_test() ->
    ?assertEqual(settled, acdc_callback_caller:settlement(false, failed, false)),
    ?assertEqual(settled, acdc_callback_caller:settlement(false, success, true)),
    ?assertEqual(settled, acdc_callback_caller:settlement(true, success, true)),
    ?assertEqual(reconciliation_required,
                 acdc_callback_caller:settlement(true, failed, false)),
    ?assertEqual(reconciliation_required,
                 acdc_callback_caller:settlement(false, success, false)),
    ?assertEqual(reconciliation_required,
                 acdc_callback_caller:settlement(true, success, false)),
    ?assertEqual(reconciliation_required,
                 acdc_callback_caller:settlement(false, pending, true)).

owner_loss_retains_uncertain_attempt_listener_test() ->
    ?assertEqual(stop_settled, acdc_callback_caller:owner_loss_action(starting)),
    ?assertEqual(wait_ready, acdc_callback_caller:owner_loss_action(waiting_ready)),
    ?assertEqual(wait_cleanup, acdc_callback_caller:owner_loss_action(cleaning)),
    ?assertEqual(cleanup, acdc_callback_caller:owner_loss_action(awaiting_ready_ack)),
    ?assertEqual(cleanup, acdc_callback_caller:owner_loss_action(originating)),
    ?assertEqual(cleanup, acdc_callback_caller:owner_loss_action(confirming)),
    ?assertEqual(cleanup, acdc_callback_caller:owner_loss_action(waiting_handoff)).

owner_protocol_messages_keep_lease_and_private_handles_test() ->
    ?assertEqual({acdc_callback_caller_ready, <<"callback">>, <<"token">>,
                  <<"uuid">>, <<"resource-q">>, <<"resource-message">>},
                 acdc_callback_caller:ready_correlation_probe()),
    ?assertEqual({acdc_callback_caller_ready, ?CALLBACK_ID, ?TOKEN,
                  <<"originate-uuid">>, <<"originate-private-queue">>,
                  <<"originate-request">>},
                 acdc_callback_caller:ready_message(
                   ?CALLBACK_ID, ?TOKEN, <<"originate-uuid">>,
                   <<"originate-private-queue">>, <<"originate-request">>)),
    ?assertEqual({acdc_callback_caller_failed, ?CALLBACK_ID, ?TOKEN,
                  originate_timeout, reconciliation_required},
                 acdc_callback_caller:failure_message(
                   ?CALLBACK_ID, ?TOKEN, originate_timeout,
                   reconciliation_required)).

confirmation_events_are_fail_closed_test() ->
    ?assertEqual(confirmed,
                 acdc_callback_caller:confirmation_event(confirming, <<"DTMF">>, <<"1">>)),
    ?assertEqual({cleanup, wrong_digit},
                 acdc_callback_caller:confirmation_event(confirming, <<"DTMF">>, <<"2">>)),
    ?assertEqual({cleanup, wrong_digit},
                 acdc_callback_caller:confirmation_event(confirming, <<"DTMF">>, undefined)),
    ?assertEqual({cleanup, media_failed},
                 acdc_callback_caller:confirmation_event(
                   confirming, <<"CHANNEL_EXECUTE_ERROR">>, undefined)),
    ?assertEqual({cleanup, unexpected_bridge},
                 acdc_callback_caller:confirmation_event(
                   confirming, <<"CHANNEL_BRIDGE">>, undefined)),
    ?assertEqual({cleanup, unexpected_bridge},
                 acdc_callback_caller:confirmation_event(
                   waiting_handoff, <<"CHANNEL_BRIDGE">>, undefined)),
    ?assertEqual({cleanup, unexpected_bridge},
                 acdc_callback_caller:confirmation_event(
                   originating, <<"CHANNEL_BRIDGE">>, undefined)),
    ?assertEqual({cleanup, unexpected_bridge},
                 acdc_callback_caller:confirmation_event(
                   awaiting_answer, <<"CHANNEL_BRIDGE">>, undefined)),
    ?assertEqual(ignore,
                 acdc_callback_caller:confirmation_event(
                   cleaning, <<"CHANNEL_BRIDGE">>, undefined)),
    ?assertEqual(ignore,
                 acdc_callback_caller:confirmation_event(
                   waiting_ready, <<"DTMF">>, <<"1">>)),
    ?assertEqual(ignore,
                 acdc_callback_caller:confirmation_event(
                   confirming, <<"CHANNEL_EXECUTE_COMPLETE">>, undefined)).

returned_confirmation_media_is_language_safe_test_() ->
    %% Passthrough meck recompiles the large Gemini manifest and kapps_call
    %% modules. On the memory/CPU-capped validation host, mock construction can
    %% exceed EUnit's implicit five seconds before any assertion executes.
    %% Bound this fixture alone; this is not a callback/media latency allowance.
    {timeout, 30, fun returned_confirmation_media_is_language_safe_with_mocks/0}.

returned_confirmation_media_is_language_safe_with_mocks() ->
    ok = meck:new(acdc_gemini_prompts, [passthrough, no_link]),
    try
        ok = meck:new(kapps_call, [passthrough, no_link]),
        try
            meck:expect(acdc_gemini_prompts, builtin, fun(_, _) -> {error,gemini_media_unavailable} end),
            meck:expect(kapps_call,get_prompt,fun(_,<<"fr-callback-confirmation">>,<<"fr-fr">>) ->
                <<"prompt://legacy/fr-callback-confirmation/fr-fr">>
            end),
            returned_confirmation_media_is_language_safe()
        after meck:unload(kapps_call)
        end
    after meck:unload(acdc_gemini_prompts)
    end.

returned_confirmation_media_is_language_safe() ->
    English = kapps_call:set_language(<<"en_US">>, original_call()),
    ?assertEqual({error, missing_localized_media},
                 acdc_callback_caller:confirmation_prompt(queue(), English)),
    French = kapps_call:set_language(<<"fr-FR">>, original_call()),
    ?assertEqual({error, missing_localized_media},
                 acdc_callback_caller:confirmation_prompt(queue(), French)),
    LocalizedQueue = kz_json:set_value(
                       [<<"callback">>, <<"media">>, <<"returned_confirmation">>],
                       <<"fr-callback-confirmation">>, queue()),
    ?assertEqual({ok, <<"prompt://legacy/fr-callback-confirmation/fr-fr">>},
                 acdc_callback_caller:confirmation_prompt(LocalizedQueue, French)),
    InvalidQueue = kz_json:set_value(
                     [<<"callback">>, <<"media">>, <<"returned_confirmation">>],
                     <<"bad\nmedia">>, queue()),
    ?assertEqual({error, missing_localized_media},
                 acdc_callback_caller:confirmation_prompt(InvalidQueue, English)).

attempt_context_is_bound_to_original_member_test() ->
    Queue = queue(),
    Reservation = reservation(),
    OriginalCall = original_call(),
    ?assert(acdc_callback_caller:valid_start(self(), Queue, Reservation, ?TOKEN, OriginalCall)),
    WrongOriginal = kapps_call:set_call_id(<<"different">>, OriginalCall),
    ?assertNot(acdc_callback_caller:valid_start(
                 self(), Queue, Reservation, ?TOKEN, WrongOriginal)),
    WrongQueue = kz_json:set_value(<<"_id">>, <<"different">>, Queue),
    ?assertNot(acdc_callback_caller:valid_start(
                 self(), WrongQueue, Reservation, ?TOKEN, OriginalCall)),
    WrongPhysical = kz_json:set_value(<<"pvt_caller_call_id">>, <<"caller-controlled">>,
                                     Reservation),
    ?assertNot(acdc_callback_caller:valid_start(
                 self(), Queue, WrongPhysical, ?TOKEN, OriginalCall)),
    ?assertNot(acdc_callback_caller:valid_start(
                 self(), Queue, Reservation, <<>>, OriginalCall)).

queue() ->
    kz_json:from_list([{<<"_id">>, ?QUEUE}
                      ,{<<"pvt_account_id">>, ?ACCOUNT}
                      ,{<<"pvt_type">>, <<"queue">>}]).

reservation() ->
    kz_json:from_list([{<<"_id">>, ?CALLBACK_ID}
                      ,{<<"pvt_account_id">>, ?ACCOUNT}
                      ,{<<"pvt_type">>, <<"acdc_callback">>}
                      ,{<<"queue_id">>, ?QUEUE}
                      ,{<<"status">>, <<"dialing">>}
                      ,{<<"original_call_id">>, ?ORIGINAL_CALL_ID}
                      ,{<<"pvt_caller_call_id">>, ?CALLER_CALL_ID}]).

original_call() ->
    kapps_call:exec([{fun kapps_call:set_account_id/2, ?ACCOUNT}
                    ,{fun kapps_call:set_call_id/2, ?ORIGINAL_CALL_ID}
                    ], kapps_call:new()).
