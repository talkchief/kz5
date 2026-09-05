%%% SPDX-License-Identifier: MPL-2.0
%%% Isolated scheduler/worker tests. No live queues, media imports, or AMQP.
-module(acdc_callback_announcement_tests).
-include_lib("eunit/include/eunit.hrl").

props(Position, Callback, Delay, Interval) ->
    [{<<"position_announcements_enabled">>, Position}
    ,{<<"initial_delay">>, 2}, {<<"interval">>, 30}
    ,{<<"callback">>, [{<<"enabled">>, Callback}, {<<"entry_key">>, <<"6">>}
                       ,{<<"announcement">>, [{<<"enabled">>, true}
                                               ,{<<"initial_delay">>, Delay}, {<<"interval">>, Interval}]}]}].

configuration_defaults_and_bounds_test() ->
    Default = acdc_announcements:get_config([{<<"callback">>, [{<<"enabled">>, true}]}]),
    ?assertEqual(true, maps:get(callback_announcements_enabled, Default)),
    ?assertEqual(30, maps:get(callback_initial_delay, Default)),
    ?assertEqual(60, maps:get(callback_interval, Default)),
    ?assertEqual(false, acdc_announcements:announcements_enabled([])),
    ?assertEqual(true, acdc_announcements:announcements_enabled(props(false, true, 1, 15))),
    WaitOnly = acdc_announcements:get_config([{<<"wait_time_announcements_enabled">>, true}]),
    ?assertEqual(#{position => 30000, callback => infinity}, acdc_announcements:schedule_init(WaitOnly, 0)),
    Low = acdc_announcements:get_config(props(false, true, 0, 0)),
    ?assertEqual(1, maps:get(callback_initial_delay, Low)),
    ?assertEqual(15, maps:get(callback_interval, Low)),
    High = acdc_announcements:get_config(props(false, true, 99999, 99999)),
    ?assertEqual(3600, maps:get(callback_initial_delay, High)),
    ?assertEqual(3600, maps:get(callback_interval, High)).

offer_switch_and_callback_disabled_are_independent_test() ->
    Disabled = acdc_announcements:get_config(props(false, false, 1, 15)),
    ?assertEqual(false, maps:get(callback_announcements_enabled, Disabled)),
    ?assertEqual([], acdc_announcements:callback_offer_prompts(<<"en-us">>, Disabled)),
    Off = [{<<"callback">>, [{<<"enabled">>, true}, {<<"entry_key">>, <<"6">>}
                            ,{<<"announcement">>, [{<<"enabled">>, false}]}]}],
    Config = acdc_announcements:get_config(Off),
    ?assertEqual(false, maps:get(callback_announcements_enabled, Config)),
    ?assertEqual(<<"6">>, maps:get(callback_entry_key, Config)),
    ?assertEqual(false, acdc_announcements:announcements_enabled(Off)),
    ?assertEqual([{<<"enabled">>, true}, {<<"entry_key">>, <<"6">>}
                 ,{<<"announcement">>, [{<<"enabled">>, false}]}], proplists:get_value(<<"callback">>, Off)).

independent_deadlines_and_combined_due_test() ->
    Config = acdc_announcements:get_config(props(true, true, 1, 15)),
    Schedule = acdc_announcements:schedule_init(Config, -10000),
    ?assertEqual(#{position => -8000, callback => -9000}, Schedule),
    ?assertEqual(1000, acdc_announcements:schedule_wait_ms(Schedule, -10000)),
    ?assertEqual([], acdc_announcements:schedule_due(Schedule, -9001)),
    ?assertEqual([callback], acdc_announcements:schedule_due(Schedule, -9000)),
    ?assertEqual([position, callback], acdc_announcements:schedule_due(Schedule, -8000)),
    Next = acdc_announcements:schedule_advance(Schedule, [callback], Config, -9000),
    ?assertEqual(#{position => -8000, callback => 6000}, Next),
    ?assertEqual(1000, acdc_announcements:schedule_wait_ms(Next, -9000)).

late_wakeup_never_replays_missed_intervals_test() ->
    Config = acdc_announcements:get_config(props(true, true, 1, 15)),
    Schedule = acdc_announcements:schedule_init(Config, 0),
    ?assertEqual(0, acdc_announcements:schedule_wait_ms(Schedule, 900000)),
    Due = acdc_announcements:schedule_due(Schedule, 900000),
    Next = acdc_announcements:schedule_advance(Schedule, Due, Config, 900050),
    ?assertEqual(#{position => 930050, callback => 915050}, Next),
    ?assertEqual([], acdc_announcements:schedule_due(Next, 900050)),
    ?assertEqual(15000, acdc_announcements:schedule_wait_ms(Next, 900050)).

disabled_clocks_never_spin_and_resume_resets_delays_test() ->
    None = acdc_announcements:get_config([]),
    ?assertEqual(#{position => infinity, callback => infinity}, acdc_announcements:schedule_init(None, 100)),
    ?assertEqual(infinity, acdc_announcements:schedule_wait_ms(acdc_announcements:schedule_init(None, 100), 999999)),
    Callback = acdc_announcements:get_config(props(false, true, 1, 15)),
    ?assertEqual(#{position => infinity, callback => 501000}, acdc_announcements:schedule_init(Callback, 500000)).

callback_offer_media_readiness_and_locale_test() ->
    ok = meck:new(acdc_language, [passthrough, no_link]),
    meck:expect(acdc_language, callback_available, fun(<<"fr-fr">>) -> true; (_) -> false end),
    try
        Config = acdc_announcements:get_config(props(false, true, 1, 15)),
        ?assertEqual([{prompt, <<"acdc-callback-offer-6">>, <<"en-us">>, <<"A">>}],
                     acdc_announcements:callback_offer_prompts(undefined, Config)),
        ?assertEqual([{prompt, <<"acdc-callback-offer-6">>, <<"fr-fr">>, <<"A">>}],
                     acdc_announcements:callback_offer_prompts(<<"FR_FR">>, Config)),
        ?assertEqual([], acdc_announcements:callback_offer_prompts(<<"he-il">>, Config)),
        OnlyOffer = Config#{callback_media := [{<<"offer">>, <<"custom-offer">>}]},
        ?assertEqual([], acdc_announcements:callback_offer_prompts(<<"he-il">>, OnlyOffer)),
        FullCustom = Config#{callback_media := [{Key, <<"custom-", Key/binary>>} || Key <-
                   [<<"offer">>, <<"menu">>, <<"number_readback">>, <<"confirmation">>, <<"success">>]]},
        ?assertEqual([{prompt, <<"custom-offer">>, <<"he-il">>, <<"A">>}],
                     acdc_announcements:callback_offer_prompts(<<"he-il">>, FullCustom)),
        ?assertEqual([], acdc_announcements:callback_offer_prompts(<<"en-us">>, Config#{callback_entry_key := <<"66">>}))
    after meck:unload(acdc_language) end.

real_worker_timer_test_() -> {timeout, 45, fun real_worker_timer/0}.
real_worker_timer() ->
    Parent = self(),
    ok = meck:new(gen_listener, [passthrough, no_link]),
    ok = meck:new(kapps_call_command, [passthrough, no_link]),
    ok = meck:new(kz_events, [passthrough, no_link]),
    meck:expect(kz_events, bind_call_id, fun(_) -> ok end),
    meck:expect(kz_events, unbind_call_id, fun(_) -> ok end),
    meck:expect(gen_listener, call, fun(_, {queue_position, _}, 500) -> Parent ! position_lookup, 1 end),
    meck:expect(kapps_call_command, audio_macro,
                fun(Prompts, Call0) ->
                        Parent ! {played, erlang:monotonic_time(millisecond), Prompts},
                        self() ! event(Call0, <<"noop">>, <<"test-noop">>),
                        <<"test-noop">>
                end),
    Call = call(),
    try
        %% Callback-only worker: no position lookup, no queue-entry playback,
        %% then exactly one repeated offer at the separate minimum interval.
        Started = erlang:monotonic_time(millisecond),
        {Pid, Ref} = spawn_monitor(fun() -> acdc_announcements:init(Parent, Call, props(false, true, 1, 15)) end),
        try
            receive {played, _, _} -> ?assert(false) after 200 -> ok end,
            First = receive {played, At, [{prompt, <<"acdc-callback-offer-6">>, <<"en-us">>, <<"A">>}]} -> At
                    after 1500 -> ?assert(false) end,
            ?assert(First - Started >= 1000),
            receive position_lookup -> ?assert(false) after 0 -> ok end,
            receive {played, _, _} -> ?assert(false) after 200 -> ok end,
            Second = receive {played, At2, [_]} -> At2 after 15500 -> ?assert(false) end,
            ?assert(Second - First >= 15000),
            stop(Pid, Ref),
            receive {played, _, _} -> ?assert(false) after 100 -> ok end
        after exit(Pid, kill) end,
        %% Equal deadlines produce one playlist, not two independent players.
        Combined = props(true, true, 2, 15),
        {Both, BothRef} = spawn_monitor(fun() -> acdc_announcements:init(Parent, Call, Combined) end),
        try
            receive {played, _, _} -> ?assert(false) after 300 -> ok end,
            receive {played, _, [{prompt, <<"acdc-queue-your-current-position-is">>, _, _}
                                ,{say, <<"1">>, <<"number">>}
                                ,{prompt, <<"acdc-callback-offer-6">>, _, _}]} -> ok
            after 2200 -> ?assert(false) end,
            stop(Both, BothRef),
            receive {played, _, _} -> ?assert(false) after 100 -> ok end
        after exit(Both, kill) end,
        %% Menu/bridge/leave use supervisor termination. Killing the worker
        %% during its initial sleep cancels both future announcement clocks.
        {Cancelled, CancelRef} = spawn_monitor(fun() -> acdc_announcements:init(Parent, Call, Combined) end),
        stop(Cancelled, CancelRef),
        receive {played, _, _} -> ?assert(false) after 2100 -> ok end,
        %% Exercise the real supervisor boundary used by menu/bridge/hangup,
        %% including callback-only startup and explicit termination (no restart).
        {ok, Supervisor} = acdc_announcements_sup:start_link(),
        unlink(Supervisor),
        try
            ?assertEqual(false, acdc_announcements_sup:maybe_start_announcements(Parent, Call, [])),
            {ok, Supervised} = acdc_announcements_sup:maybe_start_announcements(Parent, Call, props(false, true, 1, 15)),
            SupervisedRef = monitor(process, Supervised),
            ?assertEqual(ok, acdc_announcements_sup:stop_announcements(Supervised)),
            receive {'DOWN', SupervisedRef, process, Supervised, shutdown} -> ok after 500 -> ?assert(false) end,
            ?assertEqual([], supervisor:which_children(Supervisor)),
            receive {played, _, _} -> ?assert(false) after 1100 -> ok end
        after exit(Supervisor, shutdown) end
    after meck:unload(gen_listener), meck:unload(kapps_call_command), meck:unload(kz_events) end.

call() ->
    kapps_call:set_account_id(<<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>,
      kapps_call:set_call_id(<<"test-call">>, kapps_call:set_language(<<"en-us">>, kapps_call:new()))).

event(Call, App, Noop) ->
    {kapi, {undefined, undefined, kz_json:from_list(
      [{<<"Event-Category">>, <<"call_event">>}, {<<"Event-Name">>, <<"CHANNEL_EXECUTE_COMPLETE">>}
      ,{<<"Call-ID">>, kapps_call:call_id(Call)}, {<<"Account-ID">>, kapps_call:account_id(Call)}
      ,{<<"Application-Name">>, App}, {<<"Application-Response">>, Noop}])}}.

correlated_completion_and_terminal_events_test() ->
    Call = call(), Pending = {<<"ours">>, 42},
    {kapi, {_, _, Complete}} = event(Call, <<"noop">>, <<"ours">>),
    ?assertEqual(complete, acdc_announcements:announcement_event(Complete, Call, Pending)),
    lists:foreach(fun({Key, Value}) ->
        ?assertEqual(ignore, acdc_announcements:announcement_event(kz_json:set_value(Key, Value, Complete), Call, Pending))
    end, [{<<"Call-ID">>, <<"foreign-call">>}, {<<"Account-ID">>, <<"foreign-account">>}
         ,{<<"Application-Name">>, <<"play">>}, {<<"Application-Response">>, <<"stale">>}]),
    ?assertEqual(ignore, acdc_announcements:announcement_event(Complete, Call, undefined)),
    lists:foreach(fun(Name) ->
        Terminal = kz_json:set_value(<<"Event-Name">>, Name, Complete),
        ?assertEqual(stop, acdc_announcements:announcement_event(Terminal, Call, Pending))
    end, [<<"CHANNEL_BRIDGE">>, <<"CHANNEL_DESTROY">>, <<"CHANNEL_DISCONNECTED">>]).

worker_failure_lifecycle_test_() -> {timeout, 30, fun worker_failure_lifecycle/0}.
worker_failure_lifecycle() ->
    Parent = self(), Call = call(),
    ok = meck:new(kz_events, [passthrough, no_link]),
    ok = meck:new(gen_listener, [passthrough, no_link]),
    ok = meck:new(kapps_call_command, [passthrough, no_link]),
    meck:expect(kz_events, bind_call_id, fun(_) -> Parent ! {bound, self()}, ok end),
    meck:expect(kz_events, unbind_call_id, fun(_) -> ok end),
    meck:expect(gen_listener, call, fun(_, {queue_position, _}, 500) -> exit(timeout) end),
    meck:expect(kapps_call_command, audio_macro, fun(Prompts, _) -> Parent ! {pending, self(), Prompts}, <<"pending-noop">> end),
    {ok, Sup} = acdc_announcements_sup:start_link(), unlink(Sup),
    try
        Manager = spawn(fun() -> receive stop -> ok end end),
        {ok, Child} = acdc_announcements_sup:maybe_start_announcements(Manager, Call, props(false, true, 1, 15)),
        ChildRef = monitor(process, Child),
        receive {bound, Child} -> ok after 1000 -> ?assert(false) end,
        exit(Manager, kill),
        receive {'DOWN', ChildRef, process, Child, normal} -> ok after 500 -> ?assert(false) end,
        ?assertEqual([], supervisor:which_children(Sup)),
        %% Unexpected exits cannot produce untracked replacement PIDs or
        %% exhaust this supervisor's restart intensity.
        lists:foreach(fun(_) ->
            {ok, Crash} = acdc_announcements_sup:maybe_start_announcements(Parent, Call, props(false, true, 1, 15)),
            CrashRef = monitor(process, Crash), exit(Crash, kill),
            receive {'DOWN', CrashRef, process, Crash, killed} -> ok after 500 -> ?assert(false) end,
            ?assertEqual([], supervisor:which_children(Sup)),
            ?assertEqual(ok, acdc_announcements_sup:stop_announcements(Crash)),
            ?assert(is_process_alive(Sup))
        end, [1, 2]),
        %% Position failure skips its audio but still allows the independent
        %% callback offer. Missing or wrong noop completion emits no replacement.
        BothProps = [{<<"initial_delay">>, 1} | proplists:delete(<<"initial_delay">>, props(true, true, 1, 15))],
        {ok, Waiting} = acdc_announcements_sup:maybe_start_announcements(Parent, Call, BothProps),
        WaitingRef = monitor(process, Waiting),
        receive {pending, Waiting, [{prompt, <<"acdc-callback-offer-6">>, _, _}]} -> ok after 1700 -> ?assert(false) end,
        Waiting ! event(Call, <<"play">>, <<"pending-noop">>),
        Waiting ! event(Call, <<"noop">>, <<"wrong-noop">>),
        receive {'DOWN', WaitingRef, process, Waiting, normal} -> ok after 1000 -> ?assert(false) end,
        receive {pending, Waiting, _} -> ?assert(false) after 0 -> ok end,
        ?assertEqual([], supervisor:which_children(Sup))
    after exit(Sup, shutdown), meck:unload(kz_events), meck:unload(gen_listener), meck:unload(kapps_call_command) end.

stop(Pid, Ref) ->
    exit(Pid, shutdown),
    receive {'DOWN', Ref, process, Pid, shutdown} -> ok after 500 -> ?assert(false) end.
