%% Actual legacy/current production BEAM replacement, one fresh VM per case.
-module(acdc_agent_two_version_tests).
-include_lib("eunit/include/eunit.hrl").
-export([bootstrap/3]).
-define(TIMEOUT,2000).
-define(OLD_FIELDS,[account_id,account_db,agent_id,agent_listener,agent_listener_id,
                    agent_name,wrapup_timeout,wrapup_ref,sync_ref,pause_ref,member_call,
                    member_call_id,member_call_queue_id,member_call_start,queue_notifications,
                    agent_call_id,next_status,statem_call_id,endpoints,outbound_call_ids,
                    max_connect_failures,connect_failures,agent_state_updates,monitoring]).

two_version_test_() -> {timeout,15,fun run_case/0}.

run_case() ->
    ?assertEqual('nonode@nohost',node()), ?assertEqual([],nodes()),
    Case = case os:getenv("KAZOO_TWO_VERSION_CASE") of
        "ready" -> ready; "paused" -> paused;
        "unsafe_legacy" -> unsafe_legacy; "bad_legacy_tag" -> bad_legacy_tag
    end,
    Output = os:getenv("KAZOO_TWO_VERSION_OUTPUT"),
    Old = beam(filename:join([Output,"legacy","acdc_agent_fsm.beam"]),?OLD_FIELDS),
    New = beam(filename:join([Output,"current","acdc_agent_fsm.beam"]),
               ?OLD_FIELDS++[member_connect_id,call_check_ref,call_check]),
    ?assertNotEqual(maps:get(md5,Old),maps:get(md5,New)),
    ?assertEqual(false,code:is_loaded(acdc_agent_fsm)),
    ?assertEqual(false,erlang:check_old_code(acdc_agent_fsm)),
    ok = code:atomic_load([{acdc_agent_fsm,maps:get(path,Old),maps:get(bytes,Old)}]),
    version(Old), ?assertEqual(false,erlang:check_old_code(acdc_agent_fsm)),
    {Name,Initial,PauseTimer} = case Case of
        ready -> {ready,legacy(),false};
        paused -> {paused,legacy(),true};
        unsafe_legacy -> {ready,set(member_call_id,<<"residual-member">>,legacy()),false};
        bad_legacy_tag -> {ready,setelement(1,legacy(),not_state),false}
    end,
    ?assertEqual(1,erlang:trace_pattern({erlang,start_timer,3},true,[])),
    {ok,Pid} = proc_lib:start_link(?MODULE,bootstrap,[Name,Initial,PauseTimer],?TIMEOUT),
    try
        %% A real legacy state-function call proves old code ran before swap.
        ?assertEqual(atom_to_binary(Name),proplists:get_value(state,gen_statem:call(Pid,status,?TIMEOUT))),
        ok = sys:suspend(Pid,?TIMEOUT),
        Before = {Name,Legacy} = sys:get_state(Pid,?TIMEOUT),
        ?assertEqual(25,tuple_size(Legacy)), version(Old),
        ?assertEqual(false,erlang:check_old_code(acdc_agent_fsm)),
        ?assertEqual(1,erlang:trace(Pid,true,[call])),
        %% atomic_load has no purge path: an existing old-code slot blocks it.
        ok = code:atomic_load([{acdc_agent_fsm,maps:get(path,New),maps:get(bytes,New)}]),
        version(New), ?assertEqual(true,erlang:check_old_code(acdc_agent_fsm)),
        %% Loading code alone must NOT be mistaken for state conversion.
        ?assertEqual(Before,sys:get_state(Pid,?TIMEOUT)),
        case Case of
            ready -> convert(Pid,Name,Legacy,New);
            paused -> convert(Pid,Name,Legacy,New);
            unsafe_legacy -> deny(Pid,Before,agent_upgrade_requires_drain,New);
            bad_legacy_tag -> deny(Pid,Before,unsupported_agent_state_layout,New)
        end,
        io:format("PASS actual two-version ~p old_md5=~s new_md5=~s~n",
                  [Case,hex(maps:get(md5,Old)),hex(maps:get(md5,New))])
    after
        cleanup(Pid),erlang:trace_pattern({erlang,start_timer,3},false,[])
    end.

beam(Path,Fields) ->
    {ok,Bytes}=file:read_file(Path),
    {ok,{acdc_agent_fsm,Md5}}=beam_lib:md5(Bytes),
    {ok,{acdc_agent_fsm,Chunks}}=beam_lib:chunks(Bytes,[compile_info,exports,abstract_code]),
    Options=proplists:get_value(options,proplists:get_value(compile_info,Chunks),[]),
    ?assertNot(lists:any(fun({d,'TEST'})->true;({d,'TEST',_})->true;(_)->false end,Options)),
    Exports=proplists:get_value(exports,Chunks),
    ?assertNot(lists:member({strategy_test_state,1},Exports)),
    ?assertNot(lists:member({strategy_test_field,2},Exports)),
    {raw_abstract_v1,Forms}=proplists:get_value(abstract_code,Chunks),
    [Record]=[Fs || {attribute,_,record,{state,Fs}}<-Forms],
    ?assertEqual(Fields,[field(F)||F<-Record]),
    #{path=>Path,bytes=>Bytes,md5=>Md5}.
field({typed_record_field,F,_})->field(F);
field({record_field,_,{atom,_,Name}})->Name;
field({record_field,_,{atom,_,Name},_})->Name.
version(Beam)->
    ?assertEqual(maps:get(path,Beam),code:which(acdc_agent_fsm)),
    ?assertEqual(maps:get(md5,Beam),acdc_agent_fsm:module_info(md5)).
hex(B)->lists:flatten([io_lib:format("~2.16.0b",[X])||<<X>><=B]).

legacy()->
    V=#{account_id=><<"fixture-account">>,account_db=><<"fixture-db">>,agent_id=><<"fixture-agent">>,
        agent_listener=>self(),agent_listener_id=><<"fixture-listener">>,agent_name=><<"fixture-name">>,
        wrapup_timeout=>17,pause_ref=>infinity,queue_notifications=>{[{<<"fixture">>,true}]},
        next_status=><<"paused">>,statem_call_id=><<"fixture-state">>,
        endpoints=>[{[{<<"_id">>,<<"preserved-endpoint">>}]}],outbound_call_ids=>[],
        max_connect_failures=>5,connect_failures=>2,
        agent_state_updates=>[{fixture_pending,<<"preserved">>}],monitoring=>false},
    list_to_tuple([state|[maps:get(F,V,undefined)||F<-?OLD_FIELDS]]).
index(F)->index(F,?OLD_FIELDS,2).
index(F,[F|_],N)->N;
index(F,[_|Rest],N)->index(F,Rest,N+1).
set(F,V,S)->setelement(index(F),S,V).
bootstrap(Name,State,Pause)->
    Actual=case Pause of true->set(pause_ref,erlang:start_timer(60000,self(),pause_expired),State);false->State end,
    proc_lib:init_ack({ok,self()}),
    gen_statem:enter_loop(acdc_agent_fsm,[],Name,Actual).

convert(Pid,Name,Old,New)->
    ok=sys:change_code(Pid,acdc_agent_fsm,legacy_83194e7,[],?TIMEOUT),
    {Name,After}=sys:get_state(Pid,?TIMEOUT),
    ?assertEqual(28,tuple_size(After)),
    ?assertEqual(tuple_to_list(Old),lists:sublist(tuple_to_list(After),25)),
    ?assertEqual(undefined,element(26,After)),?assertEqual(undefined,element(28,After)),
    Ref=element(27,After),?assert(is_reference(Ref)),
    Remaining=erlang:read_timer(Ref),?assert(is_integer(Remaining) andalso Remaining>0),
    ?assertEqual([[30000,Pid,check_agent_calls]],timer_calls(Pid)),
    ok=sys:change_code(Pid,acdc_agent_fsm,current_source,[],?TIMEOUT),
    ?assertEqual({Name,After},sys:get_state(Pid,?TIMEOUT)),?assertEqual([],timer_calls(Pid)),
    version(New),ok=sys:resume(Pid,?TIMEOUT),
    ?assertEqual(atom_to_binary(Name),proplists:get_value(state,gen_statem:call(Pid,status,?TIMEOUT))),
    ok=sys:suspend(Pid,?TIMEOUT),
    ?assertEqual({Name,After},sys:get_state(Pid,?TIMEOUT)),version(New).

deny(Pid,Before,Reason,New)->
    ?assertEqual({error,{error,Reason}},sys:change_code(Pid,acdc_agent_fsm,legacy_83194e7,[],?TIMEOUT)),
    ?assertEqual(Before,sys:get_state(Pid,?TIMEOUT)),?assertEqual([],timer_calls(Pid)),
    ?assertEqual({error,{error,Reason}},sys:change_code(Pid,acdc_agent_fsm,legacy_83194e7,[],?TIMEOUT)),
    ?assertEqual(Before,sys:get_state(Pid,?TIMEOUT)),?assertEqual([],timer_calls(Pid)),
    version(New),?assert(is_process_alive(Pid)).
    %% Intentionally no resume/reverse-load after refusal. Cleanup kills only
    %% this private fixture process; this is not a production rollback claim.

timer_calls(Pid)->R=erlang:trace_delivered(Pid),timer_calls(Pid,R,[]).
timer_calls(Pid,R,Acc)->receive
    {trace,Pid,call,{erlang,start_timer,Args}}->timer_calls(Pid,R,[Args|Acc]);
    {trace_delivered,Pid,R}->lists:reverse(Acc)
    after ?TIMEOUT->error(timer_trace_timeout) end.
cleanup(Pid)->
    try
        case catch sys:get_state(Pid,?TIMEOUT) of
            {_,State} when is_tuple(State)->lists:foreach(fun(N)->
                case tuple_size(State)>=N andalso is_reference(element(N,State)) of
                    true->erlang:cancel_timer(element(N,State));false->ok end
                end,[index(pause_ref),27]);
            _->ok
        end
    after
        Ref=erlang:monitor(process,Pid),unlink(Pid),exit(Pid,kill),
        receive {'DOWN',Ref,process,Pid,_}->ok after ?TIMEOUT->error(cleanup_timeout) end
    end.
