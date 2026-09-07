%%% Offline runtime protocol fixtures: actual collector/FSM/supervisor init,
%%% actual gproc and gen_listener call transport; no real agents or broker.
-module(acdc_dashboard_agents_tests).
-include_lib("eunit/include/eunit.hrl").

a() -> <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>.
q() -> <<"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb">>.
id(N) -> list_to_binary(io_lib:format("~32.16.0b",[N])).

runtime_test_() ->
    {setup,fun()->{ok,P}=gproc:start_link(),unlink(P),P end,
     fun(P)->gen_server:stop(P) end,
     [fun invalid_scope/0,fun empty_scope/0,fun missing_is_unknown/0,
      fun all_states/0,fun nonmember_ready/0,fun identity_mismatch/0,
      fun listener_mismatch/0,fun malformed_queues/0,fun membership_changes/0,
      fun state_changes/0,fun supervisor_timeout/0,fun fsm_timeout/0,
      fun listener_timeout/0,fun missing_child/0,fun bounded_total_budget/0,
      fun registration_cleanup/0,fun registration_failure_is_nonfatal/0]}.

invalid_scope() ->
    lists:foreach(fun({A,Q,Ids})->
        ?assertEqual({error,invalid_scope},acdc_dashboard_agents:collect(A,Q,Ids))
    end,[{<<>>,q(),[]},{a(),<<"Q">>,[]},{a(),q(),[id(2),id(1)]},
         {a(),q(),[id(1),id(1)]},{a(),q(),[<<"bad">>]},
         {a(),q(),lists:seq(1,201)},{a(),q(),not_a_list}]).
empty_scope() ->
    {ok,R}=acdc_dashboard_agents:collect(a(),q(),[]),
    ?assertEqual([],maps:get(rows,R)),
    ?assertEqual(false,maps:get(atomic_snapshot,R)),
    ?assertEqual(false,maps:get(endpoint_reachability_verified,R)),
    ?assertEqual(local_process_observations,maps:get(coverage,R)).
missing_is_unknown() -> unknown(row(id(1)),not_observed).
all_states() ->
    lists:foreach(fun(S)->with_agent(id(1),#{state=>S},fun(_)->
        R=row(id(1)),?assertEqual(atom_to_binary(S,utf8),maps:get(state,R)),
        ?assertEqual(true,maps:get(member,R)),?assertEqual(true,maps:get(observed,R)),
        ?assertEqual([agent_id,instance,member,observed,reason,state],lists:sort(maps:keys(R))),
        ?assertEqual(64,byte_size(maps:get(instance,R)))
    end) end,[wait,sync,ready,ringing,answered,wrapup,paused,outbound]).
nonmember_ready() -> with_agent(id(1),#{queues=>[]},fun(_)->
    R=row(id(1)),?assertEqual(<<"ready">>,maps:get(state,R)),
    ?assertEqual(false,maps:get(member,R)) end).
identity_mismatch() -> with_agent(id(1),#{account=>id(99)},fun(_)->unknown(row(id(1)),invalid_runtime) end).
listener_mismatch() -> with_agent(id(1),#{listener_identity=>undefined},fun(_)->unknown(row(id(1)),invalid_runtime) end).
malformed_queues() -> lists:foreach(fun(Qs)->with_agent(id(1),#{queues=>Qs},
    fun(_)->unknown(row(id(1)),invalid_runtime) end) end,
    [[q(),q()],[<<"bad">>],null,lists:duplicate(1025,q())]).
membership_changes() -> with_agent(id(1),#{queues_after=>[]},fun(_)->unknown(row(id(1)),changed) end).
state_changes() -> with_agent(id(1),#{state_after=>paused},fun(_)->unknown(row(id(1)),changed) end).
supervisor_timeout() -> with_agent(id(1),#{sup_timeout=>true},fun(_)->unknown(row(id(1)),timeout) end).
fsm_timeout() -> with_agent(id(1),#{fsm_timeout=>true},fun(_)->unknown(row(id(1)),timeout) end).
listener_timeout() -> with_agent(id(1),#{listener_timeout=>true},fun(_)->unknown(row(id(1)),timeout) end).
missing_child() -> with_agent(id(1),#{missing_child=>true},fun(_)->unknown(row(id(1)),unavailable) end).
bounded_total_budget() ->
    Ps=[start_agent(id(N),#{sup_timeout=>true}) || N<-lists:seq(1,30)],
    try
        Start=erlang:monotonic_time(millisecond),
        {ok,R}=acdc_dashboard_agents:collect(a(),q(),[id(N)||N<-lists:seq(1,30)]),
        Elapsed=erlang:monotonic_time(millisecond)-Start,
        ?assert(Elapsed<1800),Rows=maps:get(rows,R),?assertEqual(30,length(Rows)),
        ?assert(lists:any(fun(X)->maps:get(reason,X)=:=budget end,Rows)),
        ?assert(lists:all(fun(X)->maps:get(observed,X)=:=false end,Rows))
    after lists:foreach(fun stop_agent/1,Ps) end.
registration_cleanup() ->
    Ps={Sup,_,_}=start_agent(id(1),#{}),
    ?assertEqual(Sup,gproc:where({n,l,{acdc_dashboard_agent,a(),id(1)}})),
    stop_agent(Ps),
    %% gproc lookup tests owner liveness as well as asynchronously removing it.
    unknown(row(id(1)),not_observed).
registration_failure_is_nonfatal() ->
    with_agent(id(1),#{},fun(_)->
        ?assertEqual(ok,acdc_dashboard_agents:register_agent(a(),id(1))),
        ?assertEqual(ok,acdc_dashboard_agents:register_agent(<<>>,id(1))) end).

row(Id) -> {ok,R}=acdc_dashboard_agents:collect(a(),q(),[Id]),[X]=maps:get(rows,R),X.
unknown(R,Why) -> ?assertEqual(false,maps:get(observed,R)),?assertEqual(Why,maps:get(reason,R)),
    lists:foreach(fun(K)->?assertEqual(null,maps:get(K,R)) end,[member,state,instance]).
with_agent(Id,Opts,F) -> Ps=start_agent(Id,Opts),try F(Ps) after stop_agent(Ps) end.
start_agent(Id,Opts) ->
    L=spawn(fun()->listener_loop(Opts,0) end),
    State=production_state(#{account_id=>maps:get(account,Opts,a()),agent_id=>Id,
        agent_listener=>maps:get(listener_identity,Opts,L)}),
    F=spawn(fun()->fsm_loop(State,Opts,0) end),
    Parent=self(),Sup=spawn(fun()->
        %% Execute actual production init, but deliberately do not start its
        %% real child specs. The fixture provides their bounded call protocol.
        {ok,_}=acdc_agent_sup:init([a(),Id,undefined]),Parent!{registered,self()},
        supervisor_loop(L,F,Opts)
    end),
    receive {registered,Sup}->{Sup,L,F} after 1000->error(registration_timeout) end.
stop_agent({Sup,L,F}) -> lists:foreach(fun(P)->
    Ref=monitor(process,P),exit(P,kill),receive {'DOWN',Ref,process,P,_}->ok after 1000->error(stop_timeout) end
    end,[Sup,L,F]).
supervisor_loop(L,F,O) -> receive
    {'$gen_call',From,which_children}->
        case maps:get(sup_timeout,O,false) of true->ok;false->
            Cs=case maps:get(missing_child,O,false) of true->[];false->
                [{acdc_agent_listener,L,worker,[acdc_agent_listener]},
                 {acdc_agent_fsm,F,worker,[acdc_agent_fsm]}] end,
            gen_server:reply(From,Cs) end,
        supervisor_loop(L,F,O)
end.
listener_loop(O,N) -> receive
    {'$gen_call',From,{'$client_call',queues}} ->
        case maps:get(listener_timeout,O,false) of true->ok;false->
            Qs=maps:get(queues,O,[q()]),
            gen_server:reply(From,case N of 0->Qs;_->maps:get(queues_after,O,Qs) end) end,
        listener_loop(O,N+1)
end.
fsm_loop(State,O,N) -> receive
    {'$gen_call',From,dashboard_state}->
        case maps:get(fsm_timeout,O,false) of true->ok;false->
            S=maps:get(state,O,ready),Name=case N of 0->S;_->maps:get(state_after,O,S) end,
            {next_state,Name,State,{reply,From,Reply}}=apply(acdc_agent_fsm,Name,[{call,From},dashboard_state,State]),
            gen_server:reply(From,Reply) end,
        fsm_loop(State,O,N+1)
end.
production_state(Values) ->
    %% Derive the private record layout from the actual compiled production
    %% module, never copied offsets or TEST exports. Unused fields are poisoned
    %% so an observation cannot accidentally consume call or timer state.
    {ok,{acdc_agent_fsm,[{abstract_code,{raw_abstract_v1,Forms}}]}}=
        beam_lib:chunks(code:which(acdc_agent_fsm),[abstract_code]),
    [Fs]=[Fields || {attribute,_,record,{state,Fields}}<-Forms],
    Names=[field_name(X)||X<-Fs],
    list_to_tuple([state|[maps:get(K,Values,{poison,K})||K<-Names]]).
field_name({typed_record_field,F,_}) -> field_name(F);
field_name({record_field,_,{atom,_,N},_}) -> N;
field_name({record_field,_,{atom,_,N}}) -> N.
