%%% SPDX-License-Identifier: MPL-2.0
%%% Isolated wrapper tests: no AMQP, database, service, or telephone traffic.
-module(cf_acdc_callback_feedback_tests).
-include_lib("eunit/include/eunit.hrl").

-define(ACCOUNT, <<"0123456789abcdef0123456789abcdef">>).
-define(QUEUE, <<"feedback-queue">>).
-define(CALL, <<"feedback-original-call">>).
-define(REQUEST, <<"fedcba9876543210fedcba9876543210">>).
-define(PAUSE, <<"0123456789abcdef0123456789abcdef0123456789abcdef">>).
-define(NOOP, <<"feedback-noop">>).

feedback_cases_test_() ->
    [{timeout, 20, Fun} || Fun <- [fun hangup_case/0, fun disconnect_case/0, fun bridge_case/0,
        fun foreign_usurp_case/0, fun own_usurp_case/0, fun member_success_case/0,
        fun deadline_case/0, fun media_error_case/0, fun request_error_case/0,
        fun lookup_failure_case/0, fun late_completion_case/0,
        fun bounded_command_preserves_prompt_provenance_case/0]].

request_metadata_regression_test_() ->
    [{timeout, 30, Fun} || Fun <- [fun sip_request_feedback_case/0,
                                  fun non_object_request_metadata_case/0,
                                  fun request_call_identity_precedence_case/0]].

sip_request_feedback_case() ->
    with_mocks(fun() ->
        %% Ordinary call-event Request is a SIP URI, not a nested error object.
        put(play_action, fun() ->
            deliver(kz_json:set_value(<<"Request">>, <<"sip:queue@example.invalid">>, complete(?NOOP)))
        end),
        ?assertEqual(resume, feedback(200)),
        ?assertEqual([play], actions())
    end).

non_object_request_metadata_case() ->
    with_mocks(fun() ->
        lists:foreach(fun(RequestValue) ->
            put(actions, []),
            put(play_action, fun() ->
                %% Neither missing call IDs nor stale media errors may crash
                %% or complete feedback because Request has another JSON type.
                Unknown = kz_json:delete_key(<<"Call-ID">>,
                    kz_json:set_value(<<"Request">>, RequestValue, complete(?NOOP))),
                Stale = kz_json:set_value(<<"Request">>, RequestValue,
                    event(<<"CHANNEL_EXECUTE_ERROR">>, [{<<"Msg-ID">>, <<"stale">>}])),
                deliver(Unknown), deliver(Stale),
                later(30, complete(?NOOP))
            end),
            Started = now_ms(),
            ?assertEqual(resume, feedback(200)),
            ?assert(now_ms() - Started >= 25),
            ?assertEqual([play], actions())
        end, [<<"sip:queue@example.invalid">>, <<>>, null, true, 42, [<<"not-an-object">>]])
    end).

request_call_identity_precedence_case() ->
    with_mocks(fun() ->
        put(play_action, fun() ->
            Nested = kz_json:from_list([{<<"Call-ID">>, ?CALL}, {<<"Msg-ID">>, ?NOOP}]),
            Foreign = kz_json:set_values([{<<"Call-ID">>, <<"another-call">>},
                {<<"Request">>, Nested}], event(<<"CHANNEL_EXECUTE_ERROR">>, [])),
            deliver(Foreign),
            %% A genuine nested error envelope still completes the matching
            %% feedback when there is no authoritative top-level Call-ID.
            later(30, error_event(?NOOP))
        end),
        Started = now_ms(),
        ?assertEqual(resume, feedback(200)),
        ?assert(now_ms() - Started >= 25),
        ?assertEqual([play], actions())
    end).

invalid_number_plays_truthful_feedback_then_resumes_same_member_test_() ->
    %% The outer budget includes meck's compilation of the real command module.
    %% Under the validation guard's half-core quota, that setup takes about
    %% 12 seconds; it is not callback playback time. Keep all inner timing and
    %% ownership assertions unchanged, but do not cancel during mock setup.
    {timeout, 30, fun() -> with_mocks(fun() ->
        Started = now_ms(),
        put(play_action, fun() -> later(40, kz_json:set_value(<<"Request">>,
            <<"sip:queue@example.invalid">>, complete(?NOOP))) end),
        put(resume_action, fun(Props) ->
            ?assert(now_ms() - Started >= 35),
            ?assertEqual(?ACCOUNT, proplists:get_value(<<"Account-ID">>, Props)),
            ?assertEqual(?QUEUE, proplists:get_value(<<"Queue-ID">>, Props)),
            ?assertEqual(?CALL, proplists:get_value(<<"Call-ID">>, Props)),
            ?assertEqual(?REQUEST, proplists:get_value(<<"Request-ID">>, Props)),
            ?assertEqual(?PAUSE, proplists:get_value(<<"Pause-ID">>, Props)),
            ?assertEqual(undefined, proplists:get_value(<<"Callback-ID">>, Props)),
            ?assert(kapi_acdc_callback:response_v(response())),
            deliver(response()),
            deliver(event(<<"CHANNEL_BRIDGE">>, []))
        end),
        ?assertEqual(ok, cf_acdc_member:callback_test_paused(fixture_call, callback(), context())),
        ?assertEqual([play, resume, usurped], actions()),
        ?assertEqual(0, meck:num_calls(kapi_acdc_queue, publish_member_call_cancel, '_')),
        ?assertEqual(0, meck:num_calls(cf_exe, stop, '_'))
    end) end}.

hangup_case() ->
    with_mocks(fun() ->
        put(play_action, fun() -> deliver(event(<<"CHANNEL_DESTROY">>, [])) end),
        ?assertEqual(ok, cf_acdc_member:callback_test_paused(fixture_call, callback(), context())),
        ?assertEqual([play, abandon, cancel_member, stop], actions())
    end).

disconnect_case() ->
    with_mocks(fun() ->
        put(play_action, fun() -> deliver(event(<<"CHANNEL_DISCONNECTED">>, [])) end),
        ?assertEqual(finished, feedback(100)),
        ?assertEqual([play, abandon, cancel_member, stop], actions())
    end).

bridge_case() ->
    with_mocks(fun() ->
        put(play_action, fun() -> deliver(event(<<"CHANNEL_BRIDGE">>, [])) end),
        ?assertEqual(ok, cf_acdc_member:callback_test_paused(fixture_call, callback(), context())),
        ?assertEqual([play, usurped], actions())
    end).

foreign_usurp_case() ->
    with_mocks(fun() ->
        put(play_action, fun() -> deliver(event(<<"usurp_control">>, [{<<"Fetch-ID">>, <<"new-fetch">>}])) end),
        ?assertEqual(finished, feedback(100)),
        ?assertEqual([play, usurped], actions())
    end).

own_usurp_case() ->
    with_mocks(fun() ->
        put(play_action, fun() ->
            deliver(event(<<"usurp_control">>, [{<<"Fetch-ID">>, <<"original-fetch">>}])),
            deliver(kz_json:set_value(<<"Call-ID">>, <<"another-call">>, event(<<"CHANNEL_DESTROY">>, []))),
            deliver(kz_json:set_value(<<"Call-ID">>, <<"another-call">>, complete(?NOOP))),
            deliver(complete(<<"stale-noop">>)),
            deliver(kz_json:set_value(<<"Application-Name">>, <<"play">>, complete(?NOOP))),
            deliver(kz_json:delete_key(<<"Application-Name">>, complete(?NOOP))),
            later(30, complete(?NOOP))
        end),
        Started = now_ms(),
        ?assertEqual(resume, feedback(200)),
        ?assert(now_ms() - Started >= 25),
        ?assertEqual([play], actions())
    end).

member_success_case() ->
    with_mocks(fun() ->
        put(play_action, fun() ->
            deliver(kz_json:set_value(<<"Queue-ID">>, <<"another-queue">>, member_success())),
            deliver(kz_json:set_value(<<"Account-ID">>, <<"another-account">>, member_success())),
            deliver(member_success())
        end),
        ?assertEqual(finished, feedback(100)),
        ?assertEqual([play, usurped], actions())
    end).

deadline_case() ->
    with_mocks(fun() ->
        put(play_action, fun() ->
            lists:foreach(fun(Ms) -> later(Ms, complete(<<"stale-noop">>)) end, [0, 20, 40, 60])
        end),
        Started = now_ms(),
        ?assertEqual(resume, feedback(80)),
        Elapsed = now_ms() - Started,
        ?assert(Elapsed >= 75),
        ?assert(Elapsed < 180),
        ?assertEqual([play], actions())
    end).

feedback_timeout_is_capped_at_twenty_one_seconds_test_() ->
    %% Mock compilation is outside the measured playback budget, but counts
    %% towards EUnit's outer timeout on low-core production-sized hosts.
    {timeout, 60, fun() -> with_mocks(fun() ->
        Started = now_ms(),
        ?assertEqual(resume, feedback(30000)),
        Elapsed = now_ms() - Started,
        ?assert(Elapsed >= 20950),
        ?assert(Elapsed < 21500)
    end) end}.

media_error_case() ->
    with_mocks(fun() ->
        put(play_action, fun() -> deliver(event(<<"CHANNEL_EXECUTE_ERROR">>, [{<<"Msg-ID">>, ?NOOP}])) end),
        ?assertEqual(resume, feedback(200)),
        ?assertEqual([play], actions())
    end).

request_error_case() ->
    with_mocks(fun() ->
        put(play_action, fun() ->
            deliver(error_event(<<"old-noop">>)),
            later(30, error_event(?NOOP))
        end),
        Started = now_ms(),
        ?assertEqual(resume, feedback(200)),
        ?assert(now_ms() - Started >= 25),
        ?assertEqual([play], actions())
    end).

lookup_failure_case() ->
    with_mocks(fun() ->
        put(cached_auxiliary,#{}),
        ?assertEqual(resume, feedback(100)),
        ?assertEqual([], actions())
    end).

retry_auxiliary_observes_completion_and_ownership_test_() ->
    {timeout,30,fun() -> with_mocks(fun() ->
        State=#{phase=>complete,deadline_ms=>now_ms()+1000},
        put(play_action,fun() ->
            deliver(complete(<<"stale">>)),
            deliver(kz_json:set_value(<<"Application-Name">>,<<"play">>,complete(?NOOP))),
            later(30,complete(?NOOP))
        end),
        Started=now_ms(),
        ?assertEqual(finished,cf_acdc_member:callback_test_retry(fixture_call,callback(),context(),State)),
        ?assert(now_ms()-Started>=25),
        ?assertEqual([play],actions()),
        put(actions,[]),
        put(play_action,fun() -> deliver(event(<<"CHANNEL_BRIDGE">>,[])) end),
        ?assertEqual(finished,cf_acdc_member:callback_test_retry(fixture_call,callback(),context(),State)),
        ?assertEqual([play,usurped],actions()),
        ?assertEqual(0,meck:num_calls(kapps_call_command,b_prompt,'_'))
    end) end}.

retry_auxiliary_failure_resumes_original_queue_test_() ->
    {timeout,30,fun() -> with_mocks(fun() ->
        put(cached_auxiliary,#{}),
        put(resume_action,fun(_) -> deliver(response()) end),
        State=#{phase=>menu,deadline_ms=>now_ms()+1000},
        ?assertEqual(resume,cf_acdc_member:callback_test_retry(fixture_call,callback(),context(),State)),
        ?assertEqual([resume],actions()),
        ?assertEqual(0,meck:num_calls(kapps_call_command,send_command,'_')),
        ?assertEqual(0,meck:num_calls(kapps_call_command,b_prompt,'_')),
        ?assertEqual(0,meck:num_calls(kapi_acdc_queue,publish_member_call_cancel,'_'))
    end) end}.

expired_auxiliary_deadline_never_starts_media_test_() ->
    {timeout,30,fun() -> with_mocks(fun() ->
        ?assertEqual(resume,feedback(0)),
        ?assertEqual([],actions()),
        ?assertEqual(0,meck:num_calls(acdc_gemini_prompts,auxiliary,'_'))
    end) end}.

cached_feedback_budget_and_legacy_ownership_with_poisoned_resolver_test_() ->
    {timeout,30,fun() -> with_mocks(fun() ->
        meck:expect(acdc_gemini_prompts,auxiliary,fun(_,_) -> timer:sleep(300),error(forbidden_lookup) end),
        Legacy=(maps:remove(builtin_gemini,callback()))#{legacy_custom_media=>true},
        lists:foreach(fun(Config) ->
            put(actions,[]), Started=now_ms(),
            ?assertEqual(resume,cf_acdc_member:callback_test_unavailable(fixture_call,Config,context(),30)),
            ?assert(now_ms()-Started>=25), ?assert(now_ms()-Started<150),
            ?assertEqual([play],actions()),
            put(actions,[]), put(resume_action,fun(_) -> deliver(response()) end),
            RetryStarted=now_ms(), ShortState=#{phase=>menu,deadline_ms=>RetryStarted+30},
            ?assertEqual(resume,cf_acdc_member:callback_test_retry(fixture_call,Config,context(),ShortState)),
            ?assert(now_ms()-RetryStarted>=25), ?assert(now_ms()-RetryStarted<150),
            ?assertEqual([play,resume],actions()),
            put(actions,[]),
            put(play_action,fun() -> deliver(event(<<"CHANNEL_BRIDGE">>,[])) end),
            State=#{phase=>complete,deadline_ms=>now_ms()+1000},
            ?assertEqual(finished,cf_acdc_member:callback_test_retry(fixture_call,Config,context(),State)),
            ?assertEqual([play,usurped],actions()),
            put(play_action,fun() -> ok end)
        end,[callback(),Legacy])
    end) end}.

missing_cached_feedback_never_resolves_or_changes_ownership_test_() ->
    {timeout,30,fun() -> with_mocks(fun() ->
        lists:foreach(fun(Config) ->
            put(actions,[]), Started=now_ms(),
            ?assertEqual(resume,cf_acdc_member:callback_test_unavailable(fixture_call,Config,context(),30)),
            ?assert(now_ms()-Started<100), ?assertEqual([],actions()),
            put(resume_action,fun(_) -> deliver(response()) end),
            State=#{phase=>menu,deadline_ms=>now_ms()+1000},
            ?assertEqual(resume,cf_acdc_member:callback_test_retry(fixture_call,Config,context(),State)),
            ?assertEqual([resume],actions())
        end,[#{},#{auxiliary=>#{}},#{auxiliary=>undefined},
              #{auxiliary=>#{unavailable=>undefined,invalid_entry=>null}},
              #{legacy_custom_media=>true},#{builtin_gemini=>true}]),
        ?assertEqual(0,meck:num_calls(kapps_call_command,send_command,'_')),
        ?assertEqual(0,meck:num_calls(kapi_acdc_queue,publish_member_call_cancel,'_'))
    end) end}.

late_completion_case() ->
    with_mocks(fun() ->
        ?assertEqual(resume, feedback(10)),
        meck:expect(kapps_call_command, noop_id, fun() -> <<"next-noop">> end),
        meck:expect(kapps_call_command, send_command, fun(_, fixture_call) ->
            record(play), deliver(complete(?NOOP)), later(30, complete(<<"next-noop">>)), ok
        end),
        Started = now_ms(),
        ?assertEqual(resume, feedback(200)),
        ?assert(now_ms() - Started >= 25),
        ?assertEqual([play, play], actions())
    end).

bounded_command_preserves_prompt_provenance_case() ->
    with_mocks(fun() ->
        %% Use the real play command builder and intercept only its custom
        %% publisher. Exact localized system-document identity bypasses tenant
        %% aliases; no global English or account recording fallback is used.
        CustomMedia = <<"/system_media/fr-fr/acdc-callback-unavailable-gemini-sulafat-0123456789abcdef">>,
        meck:expect(kapps_call, language, fun(fixture_call) -> <<"fr-fr">> end),
        put(cached_auxiliary,#{unavailable=>CustomMedia}),
        meck:expect(kapps_call, is_call, fun(fixture_call) -> true end),
        meck:expect(kapps_call, control_queue, fun(fixture_call) -> undefined end),
        meck:expect(kapps_call, custom_publish_function, fun(fixture_call) ->
            fun(Command, fixture_call) ->
                record(play),
                ?assertEqual(<<"queue">>, proplists:get_value(<<"Application-Name">>, Command)),
                [Noop, Play] = proplists:get_value(<<"Commands">>, Command),
                ?assertEqual(<<"noop">>, kz_json:get_value(<<"Application-Name">>, Noop)),
                ?assertEqual(?CALL, kz_json:get_value(<<"Call-ID">>, Noop)),
                NoopId = kz_json:get_ne_binary_value(<<"Msg-ID">>, Noop),
                ?assert(is_binary(NoopId)),
                ?assertEqual(<<"play">>, kz_json:get_value(<<"Application-Name">>, Play)),
                ?assertEqual(?CALL, kz_json:get_value(<<"Call-ID">>, Play)),
                ?assertEqual(CustomMedia, kz_json:get_value(<<"Media-Name">>, Play)),
                ?assertEqual(20000, kz_json:get_integer_value(<<"Playback-Timeout-Ms">>, Play)),
                ?assertEqual(undefined, kz_json:get_value(<<"Playback-Timeout">>, Play)),
                ?assertEqual(false, kz_json:get_value(<<"Endless-Playback">>, Play)),
                ?assertEqual(NoopId, kz_json:get_value(<<"Msg-ID">>, Play)),
                ?assertEqual([], kz_json:get_value(<<"Terminators">>, Play)),
                ?assert(kapi_dialplan:play_v(kz_json:set_values(
                    kz_api:default_headers(<<"call">>, <<"command">>, <<"feedback-test">>, <<"1">>), Play))),
                deliver(kz_json:set_value(<<"Application-Name">>, <<"play">>, complete(NoopId))),
                later(30, complete(NoopId))
            end
        end),
        meck:expect(kapps_call_command, send_command, fun(Command, Call) ->
            meck:passthrough([Command, Call]) end),
        Started = now_ms(),
        ?assertEqual(resume, feedback(30000)),
        ?assert(now_ms() - Started >= 25),
        ?assertEqual([play], actions())
    end).

feedback(Timeout) -> cf_acdc_member:callback_test_unavailable(fixture_call, callback(), context(), Timeout).
now_ms() -> erlang:monotonic_time(millisecond).
deliver(Event) -> self() ! {amqp_msg, Event}, ok.
later(Ms, Event) -> erlang:send_after(Ms, self(), {amqp_msg, Event}), ok.
record(Action) -> put(actions, [Action | get(actions)]), ok.
actions() -> lists:reverse(get(actions)).

callback() -> #{allow_alternate_number => false, timeout_ms => 30000, success_timeout_ms => 10000,
                builtin_gemini=>true, auxiliary=>get(cached_auxiliary)}.
context() -> #{account_id => ?ACCOUNT, queue_id => ?QUEUE, call_id => ?CALL,
               request_id => ?REQUEST, pause_id => ?PAUSE}.
event(Name, Extra) -> kz_json:from_list([{<<"Event-Category">>, <<"call_event">>},
    {<<"Event-Name">>, Name}, {<<"Call-ID">>, ?CALL} | Extra]).
complete(Noop) -> event(<<"CHANNEL_EXECUTE_COMPLETE">>, [{<<"Application-Name">>, <<"noop">>},
    {<<"Application-Response">>, Noop}]).
member_success() -> kz_json:from_list([{<<"Event-Category">>, <<"member">>}, {<<"Event-Name">>, <<"call_success">>},
    {<<"Account-ID">>, ?ACCOUNT}, {<<"Queue-ID">>, ?QUEUE}, {<<"Call-ID">>, ?CALL}]).
error_event(Noop) -> kz_json:from_list([{<<"Event-Category">>, <<"error">>}, {<<"Event-Name">>, <<"dialplan">>},
    {<<"Request">>, kz_json:from_list([{<<"Call-ID">>, ?CALL}, {<<"Msg-ID">>, Noop}])}]).
response() -> kz_json:from_list([{<<"Event-Category">>, <<"acdc_callback">>}, {<<"Event-Name">>, <<"response">>},
    {<<"Account-ID">>, ?ACCOUNT}, {<<"Queue-ID">>, ?QUEUE}, {<<"Call-ID">>, ?CALL},
    {<<"Request-ID">>, ?REQUEST}, {<<"Pause-ID">>, ?PAUSE}, {<<"Operation">>, <<"resume">>},
    {<<"Status">>, <<"resumed">>}, {<<"Msg-ID">>, ?REQUEST}, {<<"App-Name">>, <<"feedback-test">>},
    {<<"App-Version">>, <<"1">>}]).

with_mocks(Fun) ->
    put(actions, []), put(play_action, fun() -> ok end),
    put(cached_auxiliary,#{unavailable=><<"/system_media/en-us/acdc-callback-unavailable-gemini-sulafat-0123456789abcdef">>,
                           invalid_entry=><<"/system_media/en-us/acdc-callback-invalid-entry-gemini-sulafat-0123456789abcdef">>}),
    put(resume_action, fun(_) -> error(unexpected_resume) end),
    meck:new([kapps_call, cf_exe, kapi_acdc_queue, acdc_gemini_prompts, kz_datamgr], [non_strict, no_link]),
    meck:new(kapps_call_command, [passthrough, non_strict, no_link]),
    try
        meck:expect(kapps_call, call_id, fun(fixture_call) -> ?CALL end),
        meck:expect(kapps_call, caller_id_number, fun(fixture_call) -> <<"kz5_test">> end),
        meck:expect(kapps_call, account_id, fun(fixture_call) -> ?ACCOUNT end),
        meck:expect(kapps_call, language, fun(fixture_call) -> <<"en-us">> end),
        meck:expect(kapps_call, kvs_find, fun(queue_id, fixture_call) -> {ok, ?QUEUE} end),
        meck:expect(kapps_call, custom_channel_var, fun(<<"Fetch-ID">>, fixture_call) -> <<"original-fetch">> end),
        meck:expect(acdc_gemini_prompts, auxiliary, fun(_,_) -> error(timed_auxiliary_lookup_forbidden) end),
        lists:foreach(fun(Function) ->
            meck:expect(kz_datamgr,Function,fun(_,_) -> error(timed_datastore_call_forbidden) end),
            meck:expect(kz_datamgr,Function,fun(_,_,_) -> error(timed_datastore_call_forbidden) end)
        end,[open_cache_doc,open_doc]),
        meck:expect(kapps_call_command, noop_id, fun() -> ?NOOP end),
        meck:expect(kapps_call_command, send_command, fun(_, fixture_call) ->
            record(play), (get(play_action))(), ok end),
        meck:expect(kapps_call_command, flush_dtmf, fun(fixture_call) -> ok end),
        meck:expect(cf_exe, amqp_send, fun(fixture_call, Props, _) ->
            case proplists:get_value(<<"Operation">>, Props) of
                <<"resume">> -> record(resume), (get(resume_action))(Props);
                <<"abandon">> -> record(abandon);
                _ -> error(unexpected_callback_operation)
            end
        end),
        meck:expect(cf_exe, control_usurped, fun(fixture_call) -> record(usurped) end),
        meck:expect(cf_exe, stop, fun(fixture_call) -> record(stop) end),
        meck:expect(kapi_acdc_queue, publish_member_call_cancel, fun(Props) ->
            ?assertEqual(?CALL, proplists:get_value(<<"Call-ID">>, Props)), record(cancel_member) end),
        Fun(),
        ?assertEqual(0,meck:num_calls(acdc_gemini_prompts,auxiliary,'_')),
        ?assertEqual([],meck:history(kz_datamgr))
    after
        meck:unload([kapps_call, cf_exe, kapi_acdc_queue, kapps_call_command, acdc_gemini_prompts, kz_datamgr]),
        erase(actions), erase(play_action), erase(resume_action), erase(cached_auxiliary), flush_mailbox()
    end.

flush_mailbox() -> receive {amqp_msg, _} -> flush_mailbox() after 0 -> ok end.
