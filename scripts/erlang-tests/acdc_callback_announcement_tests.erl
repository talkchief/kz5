%%% SPDX-License-Identifier: MPL-2.0
%%% Isolated scheduler/worker tests. No live queues, media imports, or AMQP.
-module(acdc_callback_announcement_tests).
-include_lib("eunit/include/eunit.hrl").
-define(BUILTIN_OFFER, <<"/system_media/en-us/acdc-callback-offer-6-gemini-sulafat-0123456789abcdef">>).

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
    Config = acdc_announcements:get_config(props(false, true, 1, 15)),
    ?assertEqual([], acdc_announcements:callback_offer_prompts(undefined, Config)),
    Ready = Config#{callback_audio => {<<"en-us">>,#{builtin_gemini=>true,media=>#{offer=>?BUILTIN_OFFER}}}},
    ?assertEqual([{play,?BUILTIN_OFFER}],acdc_announcements:callback_offer_prompts(undefined,Ready)),
    ?assertEqual([{play,?BUILTIN_OFFER}],acdc_announcements:callback_offer_prompts(<<"EN_US">>,Ready)),
    ?assertEqual([],acdc_announcements:callback_offer_prompts(<<"he-il">>,Ready)),
    Legacy = Config#{callback_audio => {<<"he-il">>,#{legacy_custom_media=>true,media=>#{offer=><<"custom-offer">>}}}},
    ?assertEqual([{prompt,<<"custom-offer">>,<<"he-il">>,<<"A">>}],
                 acdc_announcements:callback_offer_prompts(<<"he-il">>,Legacy)).

mock_callback_audio() ->
    ok=meck:new(acdc_gemini_prompts,[passthrough,no_link]),
    meck:expect(acdc_gemini_prompts,callback,fun(<<"6">>,_,_,<<"en-us">>,_) ->
        {ok,#{builtin_gemini=>true,media=>#{offer=>?BUILTIN_OFFER}}}
    end).

real_worker_timer_test_() -> {timeout, 45, fun real_worker_timer/0}.
real_worker_timer() ->
    Parent = self(),
    mock_callback_audio(),
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
            First = receive {played, At, [{play, ?BUILTIN_OFFER}]} -> At
                    after 1500 -> ?assert(false) end,
            ?assert(First - Started >= 1000),
            receive position_lookup -> ?assert(false) after 0 -> ok end,
            receive {played, _, _} -> ?assert(false) after 200 -> ok end,
            Second = receive {played, At2, [_]} -> At2 after 15500 -> ?assert(false) end,
            ?assert(Second - First >= 15000),
            stop(Pid, Ref),
            receive {played, _, _} -> ?assert(false) after 100 -> ok end
        after exit(Pid, kill) end,
        %% Slow media preflight does not shift the queue-worker deadline, and
        %% the manager monitor already exists while the lookup is suspended.
        meck:expect(acdc_gemini_prompts,callback,fun(_,_,_,_,_) ->
            Parent ! {preflight,self()},
            receive finish_preflight ->
                {ok,#{builtin_gemini=>true,media=>#{offer=>?BUILTIN_OFFER}}}
            after 5000 -> error(preflight_test_timeout) end
        end),
        {Slow,SlowRef}=spawn_monitor(fun() -> acdc_announcements:init(Parent,Call,props(false,true,1,15)) end),
        try
            receive {preflight,Slow} -> ok after 1000 -> ?assert(false) end,
            {monitors,Monitors}=process_info(Slow,monitors),
            ?assert(lists:member({process,Parent},Monitors)),
            receive {played,_,_} -> ?assert(false) after 1100 -> ok end,
            Slow ! finish_preflight,
            receive {played,_,[{play,?BUILTIN_OFFER}]} -> ok after 500 -> ?assert(false) end,
            stop(Slow,SlowRef)
        after exit(Slow,kill) end,
        meck:expect(acdc_gemini_prompts,callback,fun(_,_,_,_,_) ->
            {ok,#{builtin_gemini=>true,media=>#{offer=>?BUILTIN_OFFER}}}
        end),
        %% Equal deadlines produce one playlist, not two independent players.
        Combined = props(true, true, 2, 15),
        {Both, BothRef} = spawn_monitor(fun() -> acdc_announcements:init(Parent, Call, Combined) end),
        try
            receive {played, _, _} -> ?assert(false) after 300 -> ok end,
            receive {played, _, [{prompt, <<"acdc-queue-your-current-position-is">>, _, _}
                                ,{say, <<"1">>, <<"number">>}
                                ,{play, ?BUILTIN_OFFER}]} -> ok
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
    after meck:unload(gen_listener), meck:unload(kapps_call_command), meck:unload(kz_events), meck:unload(acdc_gemini_prompts) end.

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
    mock_callback_audio(),
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
        receive {pending, Waiting, [{play, ?BUILTIN_OFFER}]} -> ok after 1700 -> ?assert(false) end,
        Waiting ! event(Call, <<"play">>, <<"pending-noop">>),
        Waiting ! event(Call, <<"noop">>, <<"wrong-noop">>),
        receive {'DOWN', WaitingRef, process, Waiting, normal} -> ok after 1000 -> ?assert(false) end,
        receive {pending, Waiting, _} -> ?assert(false) after 0 -> ok end,
        ?assertEqual([], supervisor:which_children(Sup))
    after exit(Sup, shutdown), meck:unload(kz_events), meck:unload(gen_listener), meck:unload(kapps_call_command), meck:unload(acdc_gemini_prompts) end.

stop(Pid, Ref) ->
    exit(Pid, shutdown),
    receive {'DOWN', Ref, process, Pid, shutdown} -> ok after 500 -> ?assert(false) end.

expired_playback_does_not_drain_unrelated_backlog_test() ->
    Parent = self(), Tag = make_ref(),
    {Pid, Ref} = spawn_monitor(fun() ->
        [self() ! unrelated_event || _ <- lists:seq(1, 128)],
        State = #{manager_monitor => make_ref(),
                  pending_playback => {<<"expired">>, erlang:monotonic_time(millisecond) - 1}},
        try acdc_announcements:loop(State)
        catch exit:Reason ->
            Parent ! {Tag, Reason, process_info(self(), message_queue_len)}
        end
    end),
    receive
        {Tag, Reason, QueueLength} ->
            ?assertEqual(normal, Reason),
            ?assertEqual({message_queue_len, 128}, QueueLength)
    after 1000 -> exit(Pid, kill), ?assert(false)
    end,
    receive {'DOWN', Ref, process, Pid, normal} -> ok after 1000 -> ?assert(false) end.

pre_playback_event_drain_is_bounded_test() ->
    Parent = self(), Tag = make_ref(), Call = call(),
    {Pid, Ref} = spawn_monitor(fun() ->
        %% Correctly scoped, nonterminal events: processing all of these is
        %% unnecessary, and an endless producer must not trap the worker here.
        [self() ! event(Call, <<"play">>, <<"irrelevant">>) || _ <- lists:seq(1, 1024)],
        State = #{manager_monitor => make_ref(), call => Call, pending_playback => undefined},
        Result = try acdc_announcements:drain_announcement_events(State) of
                     _ -> returned
                 catch exit:Reason -> Reason
                 end,
        Parent ! {Tag, Result, process_info(self(), message_queue_len)}
    end),
    receive
        {Tag, Result, {message_queue_len, Remaining}} ->
            ?assertEqual(normal, Result),
            ?assert(Remaining >= 767)
    after 1000 -> exit(Pid, kill), ?assert(false)
    end,
    receive {'DOWN', Ref, process, Pid, normal} -> ok after 1000 -> ?assert(false) end.

pre_playback_event_drain_boundary_and_completion_test() ->
    Parent = self(), Tag = make_ref(), Call = call(),
    {Pid, Ref} = spawn_monitor(fun() ->
        %% Exactly the budget is allowed; a correlated completion is applied.
        [self() ! event(Call, <<"play">>, <<"irrelevant">>) || _ <- lists:seq(1, 255)],
        self() ! event(Call, <<"noop">>, <<"ours">>),
        State = #{manager_monitor => make_ref(), call => Call, pending_playback => {<<"ours">>, 42}},
        Result = acdc_announcements:drain_announcement_events(State),
        Parent ! {Tag, Result, process_info(self(), message_queue_len)}
    end),
    receive
        {Tag, Result, {message_queue_len, 0}} ->
            ?assertEqual(undefined, maps:get(pending_playback, Result))
    after 1000 -> exit(Pid, kill), ?assert(false)
    end,
    receive {'DOWN', Ref, process, Pid, normal} -> ok after 1000 -> ?assert(false) end.
