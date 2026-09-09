%% Real production FSM/timers; mock only external notifications.
-module(acdc_agent_restore_tests).
-include_lib("eunit/include/eunit.hrl").

restore_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        [{"restore infinite pause", fun infinite/0}
        ,{"restore finite absolute deadline, not original duration", fun finite/0}
        ,{"expired checkpoint restores ready", fun expired/0}
        ,{"ready checkpoint cancels existing finite timer", fun resume/0}
        ,{"notification failure preserves local pause", fun notification_failure/0}
        ,{"restored timer expires in real FSM", fun timer_expiry/0}
        ,{"repeated native deadline sampling cannot extend pause", fun deadline_sampling/0}
        ] ++
        [{"reject active "++atom_to_list(Name),fun() ->
             with_fsm(Name,#{},fun(Pid) -> refused(Pid,infinite_checkpoint(),agent_not_drained) end)
          end} || Name <- [wait,sync,ringing,answered,wrapup,outbound]] ++
        [{"reject checkpoint "++atom_to_list(Label),fun() ->
             with_fsm(paused,#{pause_ref=>finite_fixture_timer},fun(Pid) ->
                 refused(Pid,Invalid,invalid_agent_checkpoint)
             end)
          end} || {Label,Invalid} <-
            [{wrong_account,(infinite_checkpoint())#{account_id=><<"other">>}}
            ,{wrong_agent,(infinite_checkpoint())#{agent_id=><<"other">>}}
            ,{extra_field,(infinite_checkpoint())#{call_id=><<"injected">>}}
            ,{relative_duration,(base(paused))#{pause_remaining_ms=>5000}}
            ,{missing_deadline,base(paused)}
            ,{wrong_deadline_type,(base(paused))#{pause_until_unix_ms=><<"infinity">>}}
            ,{nonpositive_deadline,(base(paused))#{pause_until_unix_ms=>0}}
            ,{unknown_state,base(answered)}
            ,{ready_with_deadline,(base(ready))#{pause_until_unix_ms=>infinity}}
            ,{non_map,[]}
            ]] ++
        [{"reject residual "++atom_to_list(K),fun() ->
            with_fsm(ready,#{K=>V},fun(Pid) -> refused(Pid,infinite_checkpoint(),agent_not_drained) end)
          end} || {K,V} <- [{member_call_id,<<"live">>},{outbound_call_ids,[<<"direct">>]}
                          ,{agent_state_updates,[{agent_logout}]},{call_check,{pending,probe}}]]
    end}.

setup() ->
    meck:new(acdc_agent_listener,[passthrough,no_link]),
    meck:new(acdc_agent_stats,[non_strict,no_link]),
    [meck:expect(acdc_agent_listener,F,fun(_,_) -> ok end)
       || F <- [presence_update,send_availability_update,update_agent_status]],
    meck:expect(acdc_agent_listener,send_status_resume,fun(_) -> ok end),
    meck:expect(acdc_agent_stats,agent_ready,fun(_,_) -> ok end),
    meck:expect(acdc_agent_stats,agent_paused,fun(_,_,_) -> ok end),
    ok.
cleanup(_) -> meck:unload(acdc_agent_listener),meck:unload(acdc_agent_stats).

base(State) -> #{account_id=><<"fixture-account">>,agent_id=><<"fixture-agent">>,state=>State}.
infinite_checkpoint() -> (base(paused))#{pause_until_unix_ms=>infinity}.
restore(Pid,C) -> acdc_agent_fsm:maintenance_restore(Pid,C,2000).
observe(Pid) -> {ok,S}=acdc_agent_fsm:maintenance_state(Pid,2000),S.

infinite() ->
    with_fsm(ready,#{},fun(Pid) ->
        ?assertEqual({ok,#{state=>paused,notifications_queued=>true}},restore(Pid,infinite_checkpoint())),
        S=observe(Pid),?assertEqual(paused,maps:get(state,S)),
        ?assertEqual(infinity,maps:get(pause_remaining_ms,S))
    end).
finite() ->
    Until=erlang:system_time(millisecond)+5000,
    C=(base(paused))#{pause_until_unix_ms=>Until},
    with_fsm(ready,#{},fun(Pid) ->
        {ok,_}=restore(Pid,C),A=observe(Pid),
        timer:sleep(50),
        {ok,_}=restore(Pid,C),B=observe(Pid),
        ?assert(maps:get(pause_remaining_ms,B)<maps:get(pause_remaining_ms,A)),
        ?assert(maps:get(pause_until_unix_ms,B)=<Until),
        ?assert(maps:get(pause_until_unix_ms,B)>=Until-20)
    end).
expired() ->
    with_fsm(ready,#{},fun(Pid) ->
        C=(base(paused))#{pause_until_unix_ms=>erlang:system_time(millisecond)-1},
        ?assertEqual({ok,#{state=>ready,notifications_queued=>true}},restore(Pid,C)),
        ?assertEqual(0,maps:get(pause_remaining_ms,observe(Pid)))
    end).
resume() ->
    with_fsm(paused,#{pause_ref=>finite_fixture_timer},fun(Pid) ->
        {paused,Before}=sys:get_state(Pid),OldTimer=timer_ref(Before),
        ?assert(is_integer(erlang:read_timer(OldTimer))),
        ?assertEqual({ok,#{state=>ready,notifications_queued=>true}},restore(Pid,base(ready))),
        ?assertEqual(false,erlang:read_timer(OldTimer)),
        ?assertEqual(0,maps:get(pause_remaining_ms,observe(Pid)))
    end).
notification_failure() ->
    meck:expect(acdc_agent_stats,agent_paused,fun(_,_,_) -> error(broker_unavailable) end),
    try with_fsm(ready,#{},fun(Pid) ->
        ?assertEqual({ok,#{state=>paused,notifications_queued=>false}},restore(Pid,infinite_checkpoint())),
        ?assertEqual(infinity,maps:get(pause_remaining_ms,observe(Pid))),
        ?assert(is_process_alive(Pid))
    end)
    after meck:expect(acdc_agent_stats,agent_paused,fun(_,_,_) -> ok end) end.
timer_expiry() ->
    with_fsm(ready,#{statem_call_id=><<"maintenance-timer-test">>},fun(Pid) ->
        Until=erlang:system_time(millisecond)+250,
        {ok,#{state:=paused}}=restore(Pid,(base(paused))#{pause_until_unix_ms=>Until}),
        timer:sleep(400),
        ?assertEqual(ready,maps:get(state,observe(Pid)))
    end).
deadline_sampling() ->
    with_fsm(ready,#{},fun(Pid) ->
        Until=erlang:system_time(millisecond)+10000,
        C=(base(paused))#{pause_until_unix_ms=>Until},
        lists:foreach(fun(_) ->
            {ok,_}=restore(Pid,C),
            Observed=maps:get(pause_until_unix_ms,observe(Pid)),
            ?assert(Observed=<Until)
        end,lists:seq(1,500))
    end).

refused(Pid,C,Reason) ->
    Before=sys:get_state(Pid),
    ?assertEqual({error,Reason},restore(Pid,C)),
    ?assertEqual(Before,sys:get_state(Pid)).

timer_ref(State) ->
    {ok,{acdc_agent_fsm,[{abstract_code,{raw_abstract_v1,Forms}}]}}=
        beam_lib:chunks(code:which(acdc_agent_fsm),[abstract_code]),
    [Fields]=[Fs || {attribute,_,record,{state,Fs}}<-Forms],
    Indices=lists:zip([field_name(F)||F<-Fields],lists:seq(2,length(Fields)+1)),
    element(proplists:get_value(pause_ref,Indices),State).
field_name({typed_record_field,F,_})->field_name(F);
field_name({record_field,_,{atom,_,N}})->N;
field_name({record_field,_,{atom,_,N},_})->N.
with_fsm(Name,Extra,Test) ->
    {ok,P}=proc_lib:start_link(acdc_agent_maintenance_tests,bootstrap,[self(),Name,Extra]),
    unlink(P),Ref=monitor(process,P),
    try Test(P)
    after exit(P,kill),receive {'DOWN',Ref,process,P,_}->ok after 2000->error(cleanup_timeout) end end.
