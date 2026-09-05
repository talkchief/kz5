%%% SPDX-License-Identifier: MPL-2.0
%%% Synthetic mailbox events only: no AMQP, database, live node or calls.
-module(cf_acdc_callback_control_tests).
-include_lib("eunit/include/eunit.hrl").
-define(ACCOUNT, <<"0123456789abcdef0123456789abcdef">>).
-define(QUEUE, <<"control-queue">>).
-define(CALL, <<"control-original-call">>).
-define(REQUEST, <<"fedcba9876543210fedcba9876543210">>).
-define(PAUSE, <<"0123456789abcdef0123456789abcdef0123456789abcdef">>).
-define(CALLBACK, <<"acdc-callback-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).

control_terminal_cases_test_() ->
    [{atom_to_list(Operation) ++ ":" ++ binary_to_list(Name), {timeout, 20, fun() -> with_mocks(fun() ->
        Ack = response(atom_to_binary(Operation), atom_to_binary(Status), []),
        deliver(event(Name, [])),
        deliver(Ack),
        ?assertEqual(finished, control(atom_to_binary(Operation), 200)),
        %% Prove ordering, not cold-module/scheduler latency: a terminal event
        %% must finish this wrapper without consuming the following ACK.
        assert_pending(Ack),
        case Name of
            <<"CHANNEL_DESTROY">> -> ?assertEqual([abandon, cancel_member, stop], actions());
            <<"CHANNEL_DISCONNECTED">> -> ?assertEqual([abandon, cancel_member, stop], actions());
            _ -> ?assertEqual([usurped], actions())
        end
    end) end}} || {Operation, Status} <- [{resume, resumed}, {abandon, abandoned}],
                Name <- [<<"CHANNEL_DESTROY">>, <<"CHANNEL_DISCONNECTED">>, <<"CHANNEL_BRIDGE">>]].

control_cases_test_() ->
    [{timeout, 20, Fun} || Fun <- [fun control_ignores_foreign_events_and_own_usurp_case/0,
        fun unexpected_correlated_pause_response_does_not_crash_registration_case/0,
        fun unexpected_correlated_register_response_does_not_crash_pause_case/0,
        fun registration_ignores_foreign_hangup_case/0,
        fun response_requires_current_pause_capability_case/0,
        fun late_registration_retries_resume_without_abandon_or_new_deadline_case/0,
        fun repeated_late_registration_does_not_extend_control_budget_case/0,
        fun repeated_unrelated_events_do_not_extend_control_budget_case/0]].

control_ignores_foreign_events_and_own_usurp_case() -> with_mocks(fun() ->
    lists:foreach(fun(Name) -> deliver(kz_json:set_value(<<"Call-ID">>, <<"other-call">>, event(Name, []))) end,
        [<<"CHANNEL_DESTROY">>, <<"CHANNEL_DISCONNECTED">>, <<"CHANNEL_BRIDGE">>, <<"usurp_control">>]),
    deliver(event(<<"usurp_control">>, [{<<"Fetch-ID">>, <<"original-fetch">>}])),
    deliver(kz_json:set_value(<<"Queue-ID">>, <<"other-queue">>, member_success())),
    later(30, response(<<"resume">>, <<"resumed">>, [])),
    Started = now_ms(), ?assertEqual(ok, control(<<"resume">>, 100)),
    ?assert(now_ms() - Started >= 25), ?assertEqual([], actions())
end).

control_foreign_usurp_and_member_success_test_() ->
    [{Name, {timeout, 20, fun() -> with_mocks(fun() -> deliver(Event),
        later(70, response(<<"resume">>, <<"resumed">>, [])),
        ?assertEqual(finished, control(<<"resume">>, 200)), ?assertEqual([usurped], actions())
    end) end}} || {Name, Event} <- [{"new owner", event(<<"usurp_control">>, [{<<"Fetch-ID">>, <<"different-fetch">>}])},
                                  {"queue success", member_success()}]].

control_rejects_mismatched_operation_status_test_() ->
    [{binary_to_list(Operation), {timeout, 20, fun() -> with_mocks(fun() ->
        Valid = response(Operation, Status, []),
        Invalid = kz_json:set_value(<<"Status">>, WrongStatus, Valid),
        %% Real wire validation already rejects crossed pairs; the receive
        %% guard independently documents and enforces the exact ACK contract.
        ?assertEqual(false, kapi_acdc_callback:response_v(Invalid)),
        ?assertEqual(nomatch, cf_acdc_member:callback_test_response(Invalid, context())),
        deliver(Invalid), later(25, Valid),
        Started = now_ms(), ?assertEqual(ok, control(Operation, 120)),
        ?assert(now_ms() - Started >= 20), ?assertEqual([], actions()),
        lists:foreach(fun(N) -> later(N, Invalid) end, [0,15,30,45]),
        DeadlineStarted = now_ms(),
        ?assertEqual({error, {Operation, timeout}}, control(Operation, 65)),
        ?assert(now_ms() - DeadlineStarted >= 60),
        ?assert(now_ms() - DeadlineStarted < 160)
    end) end}} || {Operation, Status, WrongStatus} <- [
        {<<"resume">>, <<"resumed">>, <<"abandoned">>},
        {<<"abandon">>, <<"abandoned">>, <<"resumed">>}]].

unexpected_correlated_pause_response_does_not_crash_registration_case() -> with_mocks(fun() ->
    deliver(response(<<"pause">>, <<"paused">>, [])),
    later(20, event(<<"CHANNEL_DESTROY">>, [])),
    ?assertEqual(finished, cf_acdc_member:callback_test_registration(fixture_call, context(), 150)),
    ?assertEqual([abandon, cancel_member, stop], actions())
end).

unexpected_correlated_register_response_does_not_crash_pause_case() -> with_mocks(fun() ->
    deliver(response(<<"register">>, <<"registered">>, [{<<"Callback-ID">>, ?CALLBACK}])),
    later(20, event(<<"CHANNEL_BRIDGE">>, [])),
    ?assertEqual(ok, cf_acdc_member:callback_test_pause(fixture_call, context(), 150)),
    ?assertEqual([usurped], actions())
end).

registration_ignores_foreign_hangup_case() -> with_mocks(fun() ->
    deliver(kz_json:set_value(<<"Call-ID">>, <<"other-call">>, event(<<"CHANNEL_DESTROY">>, []))),
    later(25, event(<<"CHANNEL_BRIDGE">>, [])),
    ?assertEqual(finished, cf_acdc_member:callback_test_registration(fixture_call, context(), 150)),
    ?assertEqual([usurped], actions())
end).

response_requires_current_pause_capability_case() -> with_mocks(fun() ->
    Wrong = kz_json:set_value(<<"Pause-ID">>, binary:copy(<<"b">>, 48), response(<<"resume">>, <<"resumed">>, [])),
    ?assertEqual(nomatch, cf_acdc_member:callback_test_response(Wrong, context())),
    deliver(Wrong), later(25, response(<<"resume">>, <<"resumed">>, [])),
    Started = now_ms(), ?assertEqual(ok, control(<<"resume">>, 120)), ?assert(now_ms() - Started >= 20)
end).

late_registration_retries_resume_without_abandon_or_new_deadline_case() -> with_mocks(fun() ->
    put(send_action, fun(Props) ->
        ?assertEqual(<<"resume">>, proplists:get_value(<<"Operation">>, Props)),
        ?assertEqual(?CALLBACK, proplists:get_value(<<"Callback-ID">>, Props)),
        later(15, response(<<"resume">>, <<"resumed">>, [])) end),
    deliver(response(<<"register">>, <<"registered">>, [{<<"Callback-ID">>, ?CALLBACK}])),
    Started = now_ms(), ?assertEqual(ok, control(<<"resume">>, 100)),
    ?assert(now_ms() - Started < 100), ?assertEqual([resume], actions())
end).

repeated_late_registration_does_not_extend_control_budget_case() -> with_mocks(fun() ->
    lists:foreach(fun(N) -> later(N, response(<<"register">>, <<"registered">>,
        [{<<"Callback-ID">>, ?CALLBACK}])) end, [0,15,30,45]),
    Started = now_ms(), ?assertEqual({error, {<<"resume">>, timeout}}, control(<<"resume">>, 65)),
    ?assert(now_ms() - Started >= 60), ?assert(now_ms() - Started < 160),
    ?assertEqual([resume, resume, resume, resume], actions())
end).

repeated_unrelated_events_do_not_extend_control_budget_case() -> with_mocks(fun() ->
    lists:foreach(fun(N) -> later(N, response(<<"pause">>, <<"paused">>, [])) end, [0,15,30,45]),
    Started = now_ms(), ?assertEqual({error, {<<"resume">>, timeout}}, control(<<"resume">>, 65)),
    ?assert(now_ms() - Started >= 60), ?assert(now_ms() - Started < 160)
end).

full_unavailable_wrapper_propagates_resume_terminal_test_() ->
    [{binary_to_list(Name), {timeout, 20, fun() -> with_mocks(fun() ->
        meck:new(kapps_call_command, [non_strict, no_link]),
        try
            meck:expect(kapps_call, caller_id_number, fun(fixture_call) -> <<"not-a-number">> end),
            meck:expect(kapps_call_command, flush_dtmf, fun(fixture_call) -> ok end),
            meck:expect(kapps_call, get_prompt, fun(fixture_call, <<"agent-invalid_choice">>) -> <<"test-prompt">> end),
            meck:expect(kapps_call_command, noop_id, fun() -> <<"test-noop">> end),
            meck:expect(kapps_call_command, play_command, fun(_, [], fixture_call) -> kz_json:new() end),
            meck:expect(kapps_call_command, send_command, fun(_, fixture_call) ->
                deliver(event(<<"CHANNEL_EXECUTE_COMPLETE">>, [{<<"Application-Name">>, <<"noop">>},
                    {<<"Application-Response">>, <<"test-noop">>}])), ok end),
            Ack = response(<<"resume">>, <<"resumed">>, []),
            put(send_action, fun(Props) ->
                case proplists:get_value(<<"Operation">>, Props) of
                    <<"resume">> -> deliver(event(Name, [])), deliver(Ack);
                    <<"abandon">> -> ok
                end
            end),
            Callback = #{allow_alternate_number => false, timeout_ms => 30000, success_timeout_ms => 10000},
            ?assertEqual(ok, cf_acdc_member:callback_test_paused(fixture_call, Callback, context())),
            assert_pending(Ack),
            ?assertEqual(Expected, actions())
        after meck:unload(kapps_call_command) end
    end) end}} || {Name, Expected} <- [{<<"CHANNEL_DESTROY">>, [resume, abandon, cancel_member, stop]},
                                     {<<"CHANNEL_BRIDGE">>, [resume, usurped]}]].

control(Operation, Timeout) -> cf_acdc_member:callback_test_control_ack(fixture_call, context(), Operation, Timeout).
context() -> #{account_id => ?ACCOUNT, queue_id => ?QUEUE, call_id => ?CALL, request_id => ?REQUEST, pause_id => ?PAUSE}.
now_ms() -> erlang:monotonic_time(millisecond).
deliver(Event) -> self() ! {amqp_msg, Event}, ok.
assert_pending(Event) -> receive {amqp_msg, Event} -> ok after 0 -> ?assert(false) end.
later(Ms, Event) -> Ref = erlang:send_after(Ms, self(), {amqp_msg, Event}), put(timers, [Ref|get(timers)]), ok.
event(Name, Extra) -> kz_json:from_list([{<<"Event-Category">>, <<"call_event">>}, {<<"Event-Name">>, Name}, {<<"Call-ID">>, ?CALL}|Extra]).
member_success() -> kz_json:from_list([{<<"Event-Category">>, <<"member">>}, {<<"Event-Name">>, <<"call_success">>},
    {<<"Account-ID">>, ?ACCOUNT}, {<<"Queue-ID">>, ?QUEUE}, {<<"Call-ID">>, ?CALL}]).
response(Operation, Status, Extra) ->
    Response = kz_json:from_list([{<<"Event-Category">>, <<"acdc_callback">>}, {<<"Event-Name">>, <<"response">>},
        {<<"Account-ID">>, ?ACCOUNT}, {<<"Queue-ID">>, ?QUEUE}, {<<"Call-ID">>, ?CALL}, {<<"Request-ID">>, ?REQUEST},
        {<<"Pause-ID">>, ?PAUSE}, {<<"Operation">>, Operation}, {<<"Status">>, Status}, {<<"Msg-ID">>, ?REQUEST},
        {<<"App-Name">>, <<"control-test">>}, {<<"App-Version">>, <<"1">>}|Extra]),
    ?assert(kapi_acdc_callback:response_v(Response)), Response.
record(Action) -> put(actions, [Action|get(actions)]), ok.
actions() -> lists:reverse(get(actions)).
with_mocks(Fun) ->
    put(actions, []), put(timers, []), put(send_action, fun(_) -> ok end),
    meck:new([kapps_call, cf_exe, kapi_acdc_queue, lager], [non_strict, no_link]),
    try
        lists:foreach(fun(Level) -> meck:expect(lager, Level, fun(_) -> ok end),
                                   meck:expect(lager, Level, fun(_, _) -> ok end) end,
                      [debug, info, warning, error]),
        meck:expect(kapps_call, call_id, fun(fixture_call) -> ?CALL end),
        meck:expect(kapps_call, account_id, fun(fixture_call) -> ?ACCOUNT end),
        meck:expect(kapps_call, kvs_find, fun(queue_id, fixture_call) -> {ok, ?QUEUE} end),
        meck:expect(kapps_call, custom_channel_var, fun(<<"Fetch-ID">>, fixture_call) -> <<"original-fetch">> end),
        meck:expect(cf_exe, amqp_send, fun(fixture_call, Props, _) ->
            record(binary_to_existing_atom(proplists:get_value(<<"Operation">>, Props))), (get(send_action))(Props) end),
        meck:expect(cf_exe, stop, fun(fixture_call) -> record(stop) end),
        meck:expect(cf_exe, control_usurped, fun(fixture_call) -> record(usurped) end),
        meck:expect(kapi_acdc_queue, publish_member_call_cancel, fun(_) -> record(cancel_member) end),
        Fun()
    after
        lists:foreach(fun erlang:cancel_timer/1, get(timers)),
        meck:unload([kapps_call, cf_exe, kapi_acdc_queue, lager]), flush_mailbox(),
        erase(actions), erase(timers), erase(send_action)
    end.
flush_mailbox() -> receive {amqp_msg, _} -> flush_mailbox() after 0 -> ok end.
