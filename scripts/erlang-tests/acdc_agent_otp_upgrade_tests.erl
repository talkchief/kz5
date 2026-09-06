%% Private real-OTP lifecycle proof. No production init, live node or I/O.
-module(acdc_agent_otp_upgrade_tests).
-include_lib("eunit/include/eunit.hrl").
-export([bootstrap/3]).

-define(TIMEOUT, 2000).
-define(FIELDS, [account_id,account_db,agent_id,agent_listener,agent_listener_id,
                 agent_name,wrapup_timeout,wrapup_ref,sync_ref,pause_ref,
                 member_call,member_call_id,member_call_queue_id,member_call_start,
                 queue_notifications,agent_call_id,next_status,statem_call_id,
                 endpoints,outbound_call_ids,max_connect_failures,connect_failures,
                 agent_state_updates,monitoring,member_connect_id,call_check_ref,call_check]).

otp_upgrade_test_() ->
    {setup, fun setup/0, fun teardown/1, fun(_) -> cases() end}.

setup() ->
    ?assertEqual('nonode@nohost', node()),
    ?assertEqual([], nodes()),
    {module, acdc_agent_fsm} = code:ensure_loaded(acdc_agent_fsm),
    {ok,{acdc_agent_fsm,[{abstract_code,{raw_abstract_v1,Forms}}]}} =
        beam_lib:chunks(code:which(acdc_agent_fsm), [abstract_code]),
    [Fields] = [Fs || {attribute,_,record,{state,Fs}} <- Forms],
    ?assertEqual(?FIELDS, [field_name(F) || F <- Fields]),
    %% Real trace events from the target process prove timer destination and
    %% absence of timer allocation on rejected/current-layout changes.
    ?assertEqual(1, erlang:trace_pattern({erlang,start_timer,3}, true, [])),
    ok.

teardown(_) ->
    erlang:trace_pattern({erlang,start_timer,3}, false, []),
    ok.

field_name({typed_record_field,Field,_}) -> field_name(Field);
field_name({record_field,_,{atom,_,Name}}) -> Name;
field_name({record_field,_,{atom,_,Name},_}) -> Name.

cases() ->
    Positive =
        [{"legacy ready real OTP conversion", fun() -> accepted(ready, legacy(base()), [], legacy) end}
        ,{"legacy paused infinite pause preserved", fun() -> accepted(paused, legacy(set(pause_ref,infinity,base())), [], legacy) end}
        ,{"legacy paused process-owned finite timer preserved", fun() -> accepted(paused,legacy(base()),[pause_ref],legacy) end}
        ,{"current ready repeated conversion keeps exact timer", fun() -> accepted(ready,base(),[call_check_ref],current) end}
        ,{"current paused keeps both process-owned timers", fun() -> accepted(paused,base(),[pause_ref,call_check_ref],current) end}
        ,{"current ringing is unchanged without dispatching call events", fun() -> accepted(ringing,base(),[call_check_ref],current) end}],
    UnsafeNames = [wait,sync,ringing,answered,wrapup,outbound],
    Unsafe = [{"reject legacy " ++ atom_to_list(Name), fun() ->
                    rejected(Name,legacy(base()),agent_upgrade_requires_drain)
                end} || Name <- UnsafeNames],
    Residual = [{member_call,{fixture_call,[]}}, {member_call_id,<<"member">>},
                {member_call_queue_id,<<"queue">>}, {member_call_start,1},
                {agent_call_id,<<"agent-leg">>}, {outbound_call_ids,[<<"direct">>]},
                {monitoring,true}],
    Dirty = [{"reject legacy residual " ++ atom_to_list(Field), fun() ->
                  rejected(ready,legacy(set(Field,Value,base())),agent_upgrade_requires_drain)
              end} || {Field,Value} <- Residual],
    Layouts = [{legacy_wrong_tag,setelement(1,legacy(base()),not_state)},
               {current_wrong_tag,setelement(1,base(),not_state)},
               {short_tuple,list_to_tuple(lists:sublist(tuple_to_list(base()),24))},
               {intermediate_tuple,list_to_tuple(lists:sublist(tuple_to_list(base()),26))},
               {long_tuple,list_to_tuple(tuple_to_list(base()) ++ [unexpected])},
               {non_tuple,undefined}],
    BadLayouts = [{"reject " ++ atom_to_list(Label), fun() ->
                       rejected(ready,Value,unsupported_agent_state_layout)
                   end} || {Label,Value} <- Layouts],
    Unknown = [{"reject unknown name with legacy tuple", fun() -> rejected(unknown,legacy(base()),unsupported_agent_state) end},
               {"reject unknown name with current tuple", fun() -> rejected(unknown,base(),unsupported_agent_state) end}],
    [{Label,{timeout,10,Test}} || {Label,Test} <- Positive ++ Unsafe ++ Dirty ++ BadLayouts ++ Unknown].

base() ->
    Values = #{account_id=><<"fixture-account">>,account_db=><<"fixture-db">>,
               agent_id=><<"fixture-agent">>,agent_listener=>self(),
               agent_listener_id=><<"fixture-listener">>,agent_name=><<"fixture-name">>,
               wrapup_timeout=>17,queue_notifications=>{[{<<"fixture">>,true}]},
               next_status=><<"paused">>,statem_call_id=><<"fixture-state">>,
               endpoints=>[{[{<<"_id">>,<<"fixture-endpoint">>}]}],
               outbound_call_ids=>[],max_connect_failures=>5,connect_failures=>2,
               agent_state_updates=>[{fixture_pending,<<"preserve">>}],monitoring=>false},
    list_to_tuple([state | [maps:get(F,Values,undefined) || F <- ?FIELDS]]).

index(Field) -> index(Field,?FIELDS,2).
index(Field,[Field|_],N) -> N;
index(Field,[_|Rest],N) -> index(Field,Rest,N+1).
get(Field,State) -> element(index(Field),State).
set(Field,Value,State) -> setelement(index(Field),State,Value).
legacy(State) -> list_to_tuple(lists:sublist(tuple_to_list(State),25)).

bootstrap(StateName,State,TimerFields) ->
    WithTimers = lists:foldl(fun(Field,Acc) ->
        Message = case Field of pause_ref -> pause_expired; call_check_ref -> check_agent_calls end,
        set(Field,erlang:start_timer(60000,self(),Message),Acc)
    end,State,TimerFields),
    proc_lib:init_ack({ok,self()}),
    %% This bypasses init/1 only. OTP dispatches the actual compiled production
    %% callback_mode/0, code_change/4 and safe-state status handlers.
    gen_statem:enter_loop(acdc_agent_fsm,[],StateName,WithTimers).

start(StateName,State,TimerFields) ->
    {ok,Pid} = proc_lib:start_link(?MODULE,bootstrap,[StateName,State,TimerFields],?TIMEOUT),
    try
        ok = sys:suspend(Pid,?TIMEOUT),
        {StateName,_} = sys:get_state(Pid,?TIMEOUT),
        ?assertEqual(1,erlang:trace(Pid,true,[call])),
        Pid
    catch Class:Reason:Stack ->
        cleanup(Pid),erlang:raise(Class,Reason,Stack)
    end.

accepted(Name,State,TimerFields,Kind) ->
    Pid = start(Name,State,TimerFields),
    try
        {Name,Before} = sys:get_state(Pid,?TIMEOUT),
        ok = sys:change_code(Pid,acdc_agent_fsm,preceding,[],?TIMEOUT),
        {Name,After} = sys:get_state(Pid,?TIMEOUT),
        TimerCalls = timer_calls(Pid),
        case Kind of
            legacy ->
                ?assertEqual(25,tuple_size(Before)),
                ?assertEqual(28,tuple_size(After)),
                ?assertEqual(tuple_to_list(Before),lists:sublist(tuple_to_list(After),25)),
                ?assertEqual(undefined,get(member_connect_id,After)),
                ?assertEqual(undefined,get(call_check,After)),
                ?assertEqual([[30000,Pid,check_agent_calls]],TimerCalls),
                NewRef = get(call_check_ref,After),
                ?assert(is_reference(NewRef)),
                Remaining = erlang:read_timer(NewRef),
                ?assert(is_integer(Remaining) andalso Remaining > 0 andalso Remaining =< 30000);
            current ->
                ?assertEqual(Before,After),
                ?assertEqual([],TimerCalls)
        end,
        %% Repeated real OTP conversion must preserve every field and ref.
        ok = sys:change_code(Pid,acdc_agent_fsm,current,[],?TIMEOUT),
        ?assertEqual({Name,After},sys:get_state(Pid,?TIMEOUT)),
        ?assertEqual([],timer_calls(Pid)),
        ok = sys:resume(Pid,?TIMEOUT),
        case Name of
            ready -> ?assertEqual(<<"ready">>,proplists:get_value(state,gen_statem:call(Pid,status,?TIMEOUT)));
            paused -> ?assertEqual(<<"paused">>,proplists:get_value(state,gen_statem:call(Pid,status,?TIMEOUT)));
            ringing -> ok
        end,
        ok = sys:suspend(Pid,?TIMEOUT),
        ?assertEqual({Name,After},sys:get_state(Pid,?TIMEOUT)),
        ?assert(is_process_alive(Pid))
    after cleanup(Pid)
    end.

rejected(Name,State,Reason) ->
    Pid = start(Name,State,[]),
    try
        Before = sys:get_state(Pid,?TIMEOUT),
        ?assertEqual({error,{error,Reason}},sys:change_code(Pid,acdc_agent_fsm,preceding,[],?TIMEOUT)),
        ?assertEqual(Before,sys:get_state(Pid,?TIMEOUT)),
        ?assertEqual([],timer_calls(Pid)),
        %% Repeat while still suspended: refusal neither changes the stored
        %% state nor exits the OTP system loop or starts the periodic timer.
        ?assertEqual({error,{error,Reason}},sys:change_code(Pid,acdc_agent_fsm,preceding,[],?TIMEOUT)),
        ?assertEqual(Before,sys:get_state(Pid,?TIMEOUT)),
        ?assertEqual([],timer_calls(Pid)),
        %% Test-only controlled repair before resume. Never dispatch old or
        %% malformed record data through the newly compiled application code.
        Repaired = {ready,base()},
        ?assertEqual(Repaired,sys:replace_state(Pid,fun(_) -> Repaired end,?TIMEOUT)),
        ok = sys:resume(Pid,?TIMEOUT),
        ?assertEqual(<<"ready">>,proplists:get_value(state,gen_statem:call(Pid,status,?TIMEOUT))),
        ok = sys:suspend(Pid,?TIMEOUT),
        ?assertEqual(Repaired,sys:get_state(Pid,?TIMEOUT)),
        ?assert(is_process_alive(Pid))
    after cleanup(Pid)
    end.

timer_calls(Pid) ->
    Ref = erlang:trace_delivered(Pid),
    timer_calls(Pid,Ref,[]).
timer_calls(Pid,Ref,Acc) ->
    receive
        {trace,Pid,call,{erlang,start_timer,Args}} -> timer_calls(Pid,Ref,[Args|Acc]);
        {trace_delivered,Pid,Ref} -> lists:reverse(Acc)
    after ?TIMEOUT -> error(timer_trace_barrier_timeout)
    end.

cleanup(Pid) ->
    try
        case catch sys:get_state(Pid,?TIMEOUT) of
            {_,State} when is_tuple(State) ->
                lists:foreach(fun(Field) ->
                    Pos = index(Field),
                    case tuple_size(State) >= Pos andalso is_reference(element(Pos,State)) of
                        true -> erlang:cancel_timer(element(Pos,State));
                        false -> ok
                    end
                end,[pause_ref,call_check_ref]);
            _ -> ok
        end
    after
        Monitor = erlang:monitor(process,Pid),
        unlink(Pid),
        exit(Pid,kill),
        receive {'DOWN',Monitor,process,Pid,_} -> ok
        after ?TIMEOUT -> error(fixture_process_cleanup_timeout)
        end
    end.
