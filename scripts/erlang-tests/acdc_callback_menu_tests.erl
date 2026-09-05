%%% SPDX-License-Identifier: MPL-2.0
-module(acdc_callback_menu_tests).

-include_lib("eunit/include/eunit.hrl").

-define(QUEUE, <<"queue-1">>).
-define(CALL, <<"original-call-1">>).
-define(REQUEST, <<"0123456789abcdef0123456789abcdef">>).
-define(CALLBACK, <<"acdc-callback-0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef">>).

current_number_requires_correlated_trusted_ack_test() ->
    {ok, Initial, [{play_menu, <<"+12025550123">>, true}]} =
        acdc_callback_menu:new(config(), <<"+12025550123">>, 1000),
    {Waiting, [Register]} = acdc_callback_menu:event({dtmf, <<"1">>}, 1001, Initial),
    ?assertEqual(awaiting_ack, acdc_callback_menu:status(Waiting)),
    ?assertEqual({register_callback, ?QUEUE, ?CALL, ?REQUEST, <<"+12025550123">>}, Register),

    %% DTMF retransmission, untrusted events and every stale correlation axis
    %% are ignored and can never emit a second registration or a hangup.
    Ignored = [{dtmf, <<"1">>}
              ,{callback_registered, ?REQUEST, ?CALLBACK}
              ,{trusted_queue_ack, <<"other-queue">>, ?CALL, ?REQUEST, {ok, ?CALLBACK}}
              ,{trusted_queue_ack, ?QUEUE, <<"other-call">>, ?REQUEST, {ok, ?CALLBACK}}
              ,{trusted_queue_ack, ?QUEUE, ?CALL, <<"other-request">>, {ok, ?CALLBACK}}],
    lists:foldl(fun(Event, State) ->
        {Same, []} = acdc_callback_menu:event(Event, 1002, State),
        ?assertEqual(State, Same),
        Same
    end, Waiting, Ignored),

    Ack = {trusted_queue_ack, ?QUEUE, ?CALL, ?REQUEST, {ok, ?CALLBACK}},
    {Announcing, Actions} = acdc_callback_menu:event(Ack, 1003, Waiting),
    ?assertEqual(announcing_success, acdc_callback_menu:status(Announcing)),
    ?assertEqual([{handoff_to_callback, ?CALLBACK}, {play_success_announcement, ?CALLBACK}], Actions),
    ?assertEqual(false, lists:member(hangup, Actions)),
    ?assertEqual({Announcing, []}, acdc_callback_menu:event(Ack, 1004, Announcing)),
    ?assertEqual({Announcing, []}
                ,acdc_callback_menu:event(
                   {trusted_announcement_complete, ?QUEUE, <<"stale-call">>, ?CALLBACK}
                  ,1005, Announcing)),
    {Complete, [hangup]} = acdc_callback_menu:event(
                             {trusted_announcement_complete, ?QUEUE, ?CALL, ?CALLBACK}
                            ,1006, Announcing),
    ?assertEqual(complete, acdc_callback_menu:status(Complete)),
    ?assertEqual({Complete, []}, acdc_callback_menu:event(Ack, 1007, Complete)).

alternate_number_collection_test() ->
    {ok, Initial, _} = acdc_callback_menu:new(config(), <<"1000">>, 0),
    {Collecting, [collect_alternate]} = acdc_callback_menu:event({dtmf, <<"2">>}, 1, Initial),
    Fifteen = <<"123456789012345">>,
    Entered = lists:foldl(fun(Digit, State) ->
        {Next, []} = acdc_callback_menu:event({dtmf, <<Digit>>}, 2, State),
        Next
    end, Collecting, binary_to_list(Fifteen)),
    {Confirming, Readback} = acdc_callback_menu:event({dtmf, <<"#">>}, 3, Entered),
    ?assertEqual(confirming_alternate, acdc_callback_menu:status(Confirming)),
    ?assertEqual([{read_back_number, Fifteen}, {prompt_confirm_alternate, <<"1">>}], Readback),
    {Waiting, [Register]} = acdc_callback_menu:event({dtmf, <<"1">>}, 4, Confirming),
    ?assertEqual(awaiting_ack, acdc_callback_menu:status(Waiting)),
    ?assertEqual({register_callback, ?QUEUE, ?CALL, ?REQUEST, Fifteen}, Register).

alternate_number_is_bounded_and_star_cancels_test() ->
    {ok, Initial, _} = acdc_callback_menu:new(config(), <<"1000">>, 0),
    {Collecting, _} = acdc_callback_menu:event({dtmf, <<"2">>}, 1, Initial),
    Filled = lists:foldl(fun(_, State) ->
        {Next, []} = acdc_callback_menu:event({dtmf, <<"9">>}, 2, State), Next
    end, Collecting, lists:seq(1, 15)),
    {Retried, [{retry, 2}]} = acdc_callback_menu:event({dtmf, <<"9">>}, 3, Filled),
    ?assertEqual(<<>>, maps:get(digits, Retried)),
    {Aborted, [{resume_live_queue, caller_cancelled}]} =
        acdc_callback_menu:event({dtmf, <<"*">>}, 4, Retried),
    ?assertEqual(aborted, acdc_callback_menu:status(Aborted)).

unavailable_current_number_allows_only_opted_in_alternate_collection_test() ->
    lists:foreach(fun(Current) ->
        {ok, State, [collect_alternate]} = acdc_callback_menu:new(config(), Current, -5000),
        ?assertEqual(collecting, acdc_callback_menu:status(State)),
        ?assertEqual(undefined, maps:get(current_number, State)),
        ?assertEqual(<<>>, maps:get(digits, State)),
        ?assertEqual(false, maps:get(registration_emitted, State)),
        ?assertEqual(30000, acdc_callback_menu:remaining_ms(-5000, State))
    end, unavailable_numbers()).

unavailable_current_number_requires_explicit_alternate_permission_test() ->
    Configs = [(config())#{allow_alternate_number => false}
               ,maps:remove(allow_alternate_number, config())
               ,(config())#{allow_alternate_number => <<"true">>}],
    lists:foreach(fun(Config) ->
        lists:foreach(fun(Current) ->
            ?assertEqual({error, invalid_number}, acdc_callback_menu:new(Config, Current, 0))
        end, unavailable_numbers())
    end, Configs).

alternate_only_requires_entered_number_and_separate_confirmation_test() ->
    {ok, Initial, [collect_alternate]} = acdc_callback_menu:new(config(), <<"fixture-sip-user">>, 0),
    %% "1" is a digit of the new number here, never a request to dial the
    %% unavailable current caller ID. Registration requires # and confirmation.
    {First, []} = acdc_callback_menu:event({dtmf, <<"1">>}, 1, Initial),
    ?assertEqual(collecting, acdc_callback_menu:status(First)),
    ?assertEqual(<<"1">>, maps:get(digits, First)),
    Entered = lists:foldl(fun(Digit, State) ->
        {Next, []} = acdc_callback_menu:event({dtmf, <<Digit>>}, 2, State), Next
    end, First, "001"),
    {Confirming, [{read_back_number, <<"1001">>}, {prompt_confirm_alternate, <<"1">>}]} =
        acdc_callback_menu:event({dtmf, <<"#">>}, 3, Entered),
    {Retry, [{retry, 2}]} = acdc_callback_menu:event({dtmf, <<"9">>}, 4, Confirming),
    ?assertEqual(false, maps:get(registration_emitted, Retry)),
    {Waiting, [{register_callback, ?QUEUE, ?CALL, ?REQUEST, <<"1001">>}]} =
        acdc_callback_menu:event({dtmf, <<"1">>}, 5, Retry),
    ?assertEqual(awaiting_ack, acdc_callback_menu:status(Waiting)),
    ?assertEqual({Waiting, []}, acdc_callback_menu:event({dtmf, <<"1">>}, 6, Waiting)).

alternate_only_retains_validation_cancellation_and_absolute_deadline_test() ->
    {ok, Initial, [collect_alternate]} = acdc_callback_menu:new(config(), undefined, -5000),
    {Empty, [{retry, 2}]} = acdc_callback_menu:event({dtmf, <<"#">>}, -4999, Initial),
    ?assertEqual(collecting, acdc_callback_menu:status(Empty)),
    {Invalid, [{retry, 1}]} = acdc_callback_menu:event({dtmf, <<"sip:target">>}, -4998, Empty),
    ?assertEqual(<<>>, maps:get(digits, Invalid)),
    ?assertEqual(false, maps:get(registration_emitted, Invalid)),
    ?assertEqual(25000, maps:get(deadline_ms, Invalid)),
    {Aborted, [{resume_live_queue, caller_cancelled}]} =
        acdc_callback_menu:event({dtmf, <<"*">>}, -4997, Invalid),
    ?assertEqual(aborted, acdc_callback_menu:status(Aborted)),
    {Expired, [{resume_live_queue, deadline}]} = acdc_callback_menu:event(tick, 25000, Initial),
    ?assertEqual(aborted, acdc_callback_menu:status(Expired)),
    {Dead, [abandon_paused_queue]} = acdc_callback_menu:event(caller_hangup, 25000, Initial),
    ?assertEqual(aborted_dead, acdc_callback_menu:status(Dead)).

unavailable_numbers() -> [undefined, <<>>, <<"anonymous">>, <<"fixture-sip-user">>,
                         <<"12 34">>, <<"+">>, <<"1234567890123456">>, <<"sip:target@example.invalid">>].

retry_limit_and_absolute_deadline_preserve_queue_test() ->
    Config = (config())#{max_retries => 2, timeout_ms => 1000},
    {ok, Initial, _} = acdc_callback_menu:new(Config, <<"1000">>, 5000),
    {Once, [{retry, 1}]} = acdc_callback_menu:event({dtmf, <<"9">>}, 5500, Initial),
    {RetryAbort, RetryActions} = acdc_callback_menu:event({dtmf, <<"9">>}, 5501, Once),
    ?assertEqual(aborted, acdc_callback_menu:status(RetryAbort)),
    ?assertEqual([{resume_live_queue, retry_limit}], RetryActions),
    ?assertEqual(false, lists:member(hangup, RetryActions)),

    {ok, DeadlineInitial, _} = acdc_callback_menu:new(Config, <<"1000">>, 5000),
    {DeadlineAbort, DeadlineActions} = acdc_callback_menu:event(tick, 6000, DeadlineInitial),
    ?assertEqual(aborted, acdc_callback_menu:status(DeadlineAbort)),
    ?assertEqual([{resume_live_queue, deadline}], DeadlineActions),
    ?assertEqual(false, lists:member(hangup, DeadlineActions)).

negative_monotonic_origin_keeps_absolute_deadline_test() ->
    Config = (config())#{timeout_ms => 1000},
    {ok, Initial, _} = acdc_callback_menu:new(Config, <<"1000">>, -5000),
    {Same, []} = acdc_callback_menu:event(tick, -4001, Initial),
    ?assertEqual(menu, acdc_callback_menu:status(Same)),
    {Aborted, [{resume_live_queue, deadline}]} = acdc_callback_menu:event(tick, -4000, Same),
    ?assertEqual(aborted, acdc_callback_menu:status(Aborted)).

alternate_is_opt_in_and_main_star_cancels_test() ->
    DisabledConfig = maps:remove(allow_alternate_number, config()),
    {ok, Initial, [{play_menu, <<"1000">>, false}]} =
        acdc_callback_menu:new(DisabledConfig, <<"1000">>, 0),
    {Retried, [{retry, 2}]} = acdc_callback_menu:event({dtmf, <<"2">>}, 1, Initial),
    ?assertEqual(menu, acdc_callback_menu:status(Retried)),
    {Aborted, [{resume_live_queue, caller_cancelled}]} =
        acdc_callback_menu:event({dtmf, <<"*">>}, 2, Retried),
    ?assertEqual(aborted, acdc_callback_menu:status(Aborted)).

registration_failure_and_late_success_never_hang_up_live_call_test() ->
    {ok, Initial, _} = acdc_callback_menu:new(config(), <<"1000">>, 1000),
    {Waiting, [_]} = acdc_callback_menu:event({dtmf, <<"1">>}, 1001, Initial),
    Failure = {trusted_queue_ack, ?QUEUE, ?CALL, ?REQUEST, {error, datastore_unreachable}},
    {Failed, FailedActions} = acdc_callback_menu:event(Failure, 1002, Waiting),
    ?assertEqual(aborted, acdc_callback_menu:status(Failed)),
    ?assertEqual([{resume_live_queue, registration_failed}], FailedActions),
    ?assertEqual(false, lists:member(hangup, FailedActions)),

    {ok, Again, _} = acdc_callback_menu:new(config(), <<"1000">>, 2000),
    {Waiting2, [_]} = acdc_callback_menu:event({dtmf, <<"1">>}, 2001, Again),
    {TimedOut, [{resume_live_queue, deadline}]} = acdc_callback_menu:event(tick, 32000, Waiting2),
    Late = {trusted_queue_ack, ?QUEUE, ?CALL, ?REQUEST, {ok, ?CALLBACK}},
    {LateHandled, [{cancel_callback, ?CALLBACK}]} =
        acdc_callback_menu:event(Late, 32001, TimedOut),
    ?assertEqual({LateHandled, []}, acdc_callback_menu:event(Late, 32002, LateHandled)),
    ?assertEqual({TimedOut, []}
                ,acdc_callback_menu:event(
                   {trusted_queue_ack, ?QUEUE, <<"stale-call">>, ?REQUEST, {ok, ?CALLBACK}}
                  ,32001, TimedOut)),

    %% An acknowledgement delivered on the deadline boundary is consumed once:
    %% it cannot complete the menu, but its new durable callback is cancelled.
    {ok, BoundaryInitial, _} = acdc_callback_menu:new(config(), <<"1000">>, 40000),
    {BoundaryWaiting, [_]} = acdc_callback_menu:event({dtmf, <<"1">>}, 40001, BoundaryInitial),
    {BoundaryAbort, BoundaryActions} = acdc_callback_menu:event(Late, 70000, BoundaryWaiting),
    ?assertEqual(aborted, acdc_callback_menu:status(BoundaryAbort)),
    ?assertEqual([{resume_live_queue, deadline}, {cancel_callback, ?CALLBACK}], BoundaryActions),
    ?assertEqual(false, lists:member(hangup, BoundaryActions)).

caller_hangup_waiting_for_ack_never_resumes_dead_call_test() ->
    {ok, Initial, _} = acdc_callback_menu:new(config(), <<"1000">>, 0),
    {Waiting, [_]} = acdc_callback_menu:event({dtmf, <<"1">>}, 1, Initial),
    %% Hangup takes precedence even exactly on the initial menu deadline.
    {Dead, [abandon_paused_queue]} = acdc_callback_menu:event(caller_hangup, 30000, Waiting),
    ?assertEqual(aborted_dead, acdc_callback_menu:status(Dead)),
    Ack = {trusted_queue_ack, ?QUEUE, ?CALL, ?REQUEST, {ok, ?CALLBACK}},
    {LateHandled, [{cancel_callback, ?CALLBACK}]} = acdc_callback_menu:event(Ack, 3, Dead),
    ?assertEqual({LateHandled, []}, acdc_callback_menu:event(Ack, 4, LateHandled)).

success_playback_has_independent_bound_and_never_requeues_test() ->
    Config = (config())#{success_timeout_ms => 1000},
    {ok, Initial, _} = acdc_callback_menu:new(Config, <<"1000">>, 0),
    {Waiting, [_]} = acdc_callback_menu:event({dtmf, <<"1">>}, 1, Initial),
    Ack = {trusted_queue_ack, ?QUEUE, ?CALL, ?REQUEST, {ok, ?CALLBACK}},
    {Announcing, _} = acdc_callback_menu:event(Ack, 2, Waiting),
    {TimedOut, TimeoutActions} = acdc_callback_menu:event(tick, 1002, Announcing),
    ?assertEqual(complete, acdc_callback_menu:status(TimedOut)),
    ?assertEqual([{end_original_leg, ?CALLBACK, announcement_timeout}], TimeoutActions),
    ?assertEqual(false, lists:any(fun({resume_live_queue, _}) -> true; (_) -> false end, TimeoutActions)),
    ?assertEqual(false, lists:any(fun({cancel_callback, _}) -> true; (_) -> false end, TimeoutActions)),

    {ok, Initial2, _} = acdc_callback_menu:new(Config, <<"1000">>, 2000),
    {Waiting2, [_]} = acdc_callback_menu:event({dtmf, <<"1">>}, 2001, Initial2),
    {Announcing2, _} = acdc_callback_menu:event(Ack, 2002, Waiting2),
    StaleFailure = {trusted_announcement_failed, ?QUEUE, <<"stale-call">>, ?CALLBACK},
    ?assertEqual({Announcing2, []}, acdc_callback_menu:event(StaleFailure, 2003, Announcing2)),
    Failure = {trusted_announcement_failed, ?QUEUE, ?CALL, ?CALLBACK},
    {Failed, FailureActions} = acdc_callback_menu:event(Failure, 2004, Announcing2),
    ?assertEqual(complete, acdc_callback_menu:status(Failed)),
    ?assertEqual([{end_original_leg, ?CALLBACK, announcement_failed}], FailureActions).

invalid_inputs_test() ->
    Disabled = (config())#{allow_alternate_number => false},
    ?assertEqual({error, invalid_number}, acdc_callback_menu:new(Disabled, <<"12 34">>, 0)),
    ?assertEqual({error, invalid_number}, acdc_callback_menu:new(Disabled, <<"+">>, 0)),
    ?assertEqual({error, invalid_number}
                ,acdc_callback_menu:new(Disabled, <<"1234567890123456">>, 0)),
    ?assertEqual({error, invalid_config}
                ,acdc_callback_menu:new((config())#{confirm_key => <<"2">>}, <<"1000">>, 0)),
    ?assertEqual({error, invalid_config}
                ,acdc_callback_menu:new(maps:remove(queue_id, config()), <<"1000">>, 0)),
    ?assertEqual({error, invalid_config}
                ,acdc_callback_menu:new((config())#{request_id => <<"bad\nrequest">>}, <<"1000">>, 0)).

remaining_time_uses_menu_and_success_absolute_deadlines_test() ->
    {ok, Initial, _} = acdc_callback_menu:new(config(), <<"1000">>, -5000),
    ?assertEqual(30000, acdc_callback_menu:remaining_ms(-5000, Initial)),
    ?assertEqual(1, acdc_callback_menu:remaining_ms(24999, Initial)),
    ?assertEqual(0, acdc_callback_menu:remaining_ms(25000, Initial)),
    {Waiting, [_]} = acdc_callback_menu:event({dtmf, <<"1">>}, -4999, Initial),
    Ack = {trusted_queue_ack, ?QUEUE, ?CALL, ?REQUEST, {ok, ?CALLBACK}},
    {Announcing, _} = acdc_callback_menu:event(Ack, -4998, Waiting),
    ?assertEqual(10000, acdc_callback_menu:remaining_ms(-4998, Announcing)),
    ?assertEqual(0, acdc_callback_menu:remaining_ms(5002, Announcing)).

config() -> #{request_id => ?REQUEST
             ,queue_id => ?QUEUE
             ,original_call_id => ?CALL
             ,confirm_key => <<"1">>
             ,alternate_key => <<"2">>
             ,allow_alternate_number => true
             ,max_retries => 3
             ,timeout_ms => 30000}.
