%%% Private synthetic accepted-callback mailbox tests. No live traffic.
-module(cf_acdc_callback_success_tests).
-include_lib("eunit/include/eunit.hrl").
-define(ACCOUNT, <<"0123456789abcdef0123456789abcdef">>).
-define(QUEUE, <<"success-queue">>).
-define(CALL, <<"accepted-original-call">>).
-define(NOOP, <<"accepted-success-noop">>).

accepted_success_cases_test_() ->
    {setup, fun setup/0, fun teardown/1, [
        {Name, fun() -> isolated(fun() -> ignores_until_completion(Event) end) end}
        || {Name, Event} <- [
            {"foreign hangup", foreign(event(<<"CHANNEL_DESTROY">>, []))},
            {"foreign completion", foreign(complete())},
            {"missing completion call ID", kz_json:delete_key(<<"Call-ID">>, complete())},
            {"wrong completion application", kz_json:set_value(<<"Application-Name">>, <<"play">>, complete())},
            {"missing completion application", kz_json:delete_key(<<"Application-Name">>, complete())},
            {"stale completion noop", kz_json:set_value(<<"Application-Response">>, <<"old-noop">>, complete())},
            {"own usurp", event(<<"usurp_control">>, [{<<"Fetch-ID">>, <<"our-fetch">>}])},
            {"foreign bridge", foreign(event(<<"CHANNEL_BRIDGE">>, []))},
            {"foreign member success", kz_json:set_value(<<"Queue-ID">>, <<"other-queue">>, member_success())}
        ]] ++ [
        {Name, fun() -> isolated(fun() ->
            deliver(Event), Started = now_ms(), ?assertEqual(finished, run(150)),
            ?assert(now_ms() - Started < 100), ?assertEqual([play, Expected], actions())
        end) end} || {Name, Event, Expected} <- [
            {"accepted hangup keeps ticket and stops executor", event(<<"CHANNEL_DESTROY">>, []), stop},
            {"accepted disconnect keeps ticket and stops executor", event(<<"CHANNEL_DISCONNECTED">>, []), stop},
            {"bridge does not hang up new owner", event(<<"CHANNEL_BRIDGE">>, []), usurped},
            {"new owner usurp", event(<<"usurp_control">>, [{<<"Fetch-ID">>, <<"new-fetch">>}]), usurped},
            {"scoped queue success", member_success(), usurped}
        ]] ++ [
        {"matching completion ends only original leg", fun() -> isolated(fun() ->
            deliver(complete()), ?assertEqual(finished, run(150)),
            ?assertEqual([play, hangup_original, stop], actions())
        end) end},
        {"built-in success uses exact media without alias lookup", fun() -> isolated(fun() ->
            put(builtin_success,true), deliver(complete()),
            ?assertEqual(finished,run(150)),
            ?assertEqual([play,hangup_original,stop],actions())
        end) end},
        {"timeout preserves accepted callback and ends original leg", fun() -> isolated(fun() ->
            lists:foreach(fun(Ms) -> later(Ms, foreign(event(<<"CHANNEL_DISCONNECTED">>, []))) end, [0,15,30,45]),
            Started = now_ms(), ?assertEqual(finished, run(65)),
            ?assert(now_ms() - Started >= 60), ?assert(now_ms() - Started < 160),
            ?assertEqual([play, hangup_original, stop], actions())
        end) end}
    ]}.

ignores_until_completion(Event) ->
    deliver(Event), later(30, complete()), Started = now_ms(),
    ?assertEqual(finished, run(150)), ?assert(now_ms() - Started >= 25),
    ?assertEqual([play, hangup_original, stop], actions()).
run(Timeout) ->
    Callback = case get(builtin_success) of
        true -> #{builtin_gemini => true, media => #{success => <<"private-prompt">>}};
        _ -> #{media => #{success => <<"accepted-success-prompt">>}}
    end,
    cf_acdc_member:callback_test_success(fixture_call,Callback,context(),Timeout).
context() -> #{account_id => ?ACCOUNT, queue_id => ?QUEUE, call_id => ?CALL,
    request_id => <<"fedcba9876543210fedcba9876543210">>,
    pause_id => <<"0123456789abcdef0123456789abcdef0123456789abcdef">>}.
event(Name, Extra) -> kz_json:from_list([{<<"Event-Category">>, <<"call_event">>},
    {<<"Event-Name">>, Name}, {<<"Call-ID">>, ?CALL}|Extra]).
foreign(Event) -> kz_json:set_value(<<"Call-ID">>, <<"other-call">>, Event).
complete() -> event(<<"CHANNEL_EXECUTE_COMPLETE">>, [{<<"Application-Name">>, <<"noop">>},
    {<<"Application-Response">>, ?NOOP}]).
member_success() -> kz_json:from_list([{<<"Event-Category">>, <<"member">>}, {<<"Event-Name">>, <<"call_success">>},
    {<<"Account-ID">>, ?ACCOUNT}, {<<"Queue-ID">>, ?QUEUE}, {<<"Call-ID">>, ?CALL}]).
now_ms() -> erlang:monotonic_time(millisecond).
deliver(Event) -> self() ! {amqp_msg, Event}, ok.
later(Ms, Event) -> Ref=erlang:send_after(Ms,self(),{amqp_msg,Event}),put(timers,[Ref|get(timers)]),ok.
record(Action) -> put(actions,[Action|get(actions)]),ok.
actions() -> lists:reverse(get(actions)).
isolated(Fun) ->
    put(actions, []), put(timers, []),
    try Fun()
    after lists:foreach(fun erlang:cancel_timer/1,get(timers)), flush(), erase(actions), erase(timers), erase(builtin_success) end.
flush() -> receive {amqp_msg,_} -> flush() after 0 -> ok end.
setup() ->
    meck:new([kapps_call,kapps_call_command,cf_exe], [non_strict,no_link]),
    meck:expect(kapps_call,call_id,fun(fixture_call)->?CALL end),
    meck:expect(kapps_call,account_id,fun(fixture_call)->?ACCOUNT end),
    meck:expect(kapps_call,custom_channel_var,fun(<<"Fetch-ID">>,fixture_call)-><<"our-fetch">> end),
    meck:expect(kapps_call,language,fun(fixture_call)-><<"en-us">> end),
    meck:expect(kapps_call,get_prompt,fun(fixture_call,<<"accepted-success-prompt">>)-><<"private-prompt">> end),
    meck:expect(kapps_call_command,play,fun(<<"private-prompt">>,fixture_call)->record(play),?NOOP end),
    meck:expect(kapps_call_command,hangup,fun(fixture_call)->record(hangup_original) end),
    meck:expect(cf_exe,stop,fun(fixture_call)->record(stop) end),
    meck:expect(cf_exe,control_usurped,fun(fixture_call)->record(usurped) end),
    %% Accepted tickets must not be resumed, abandoned, cancelled or recreated.
    meck:expect(cf_exe,amqp_send,fun(_,_,_)->error(accepted_callback_must_not_be_mutated) end),
    ok.
teardown(_) -> meck:unload([kapps_call,kapps_call_command,cf_exe]).
