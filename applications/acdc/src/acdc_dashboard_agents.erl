%%% SPDX-License-Identifier: MPL-2.0
%%% Bounded local runtime observations, not endpoint reachability or eligibility.
%%% No datastore, broker, agent command, global supervisor scan or worker fanout.
-module(acdc_dashboard_agents).
-export([register_agent/2, collect/3]).
-define(MAX_AGENTS,200).
-define(BUDGET_MS,1000).
-define(CALL_MS,50).

-spec register_agent(term(),term()) -> ok.
register_agent(Account,Agent) ->
    case id(Account) andalso id(Agent) of
        true ->
            %% gproc removes the name when its owning supervisor dies.
            %% A failed registration means unobserved, never logged out.
            try gproc:reg(key(Account,Agent)) of _ -> ok catch _:_ -> ok end;
        false -> ok
    end.

-spec collect(binary(),binary(),[binary()]) -> {ok,map()} | {error,invalid_scope}.
collect(Account,Queue,Agents) ->
    case id(Account) andalso id(Queue) andalso is_list(Agents) andalso
        length(Agents)=< ?MAX_AGENTS andalso Agents=:=lists:usort(Agents) andalso
        lists:all(fun id/1,Agents) of
        false -> {error,invalid_scope};
        true ->
            Start=wall(),Deadline=erlang:monotonic_time(millisecond)+?BUDGET_MS,
            Rows=[observe(Account,Queue,Agent,Deadline) || Agent<-Agents],
            {ok,#{account_id=>Account,queue_id=>Queue,rows=>Rows,
                observation_started=>Start,observation_finished=>wall(),
                coverage=>local_process_observations,atomic_snapshot=>false,
                endpoint_reachability_verified=>false,limit=>?MAX_AGENTS}}
    end.

observe(Account,Queue,Agent,Deadline) ->
    try
        _=timeout(Deadline),
        Sup=gproc:where(key(Account,Agent)),
        need(is_pid(Sup) andalso node(Sup)=:=node(),not_observed),
        {Listener,Fsm}=children(Sup,Deadline),
        First=acdc_agent_fsm:dashboard_state(Fsm,timeout(Deadline)),
        need(valid_state(First,Account,Agent,Listener),invalid_runtime),
        Qs=gen_listener:call(Listener,queues,timeout(Deadline)),
        need(queues(Qs),invalid_runtime),
        Second=acdc_agent_fsm:dashboard_state(Fsm,timeout(Deadline)),
        QsAfter=gen_listener:call(Listener,queues,timeout(Deadline)),
        need(queues(QsAfter),invalid_runtime),
        need(First=:=Second andalso lists:member(Queue,Qs)=:=lists:member(Queue,QsAfter),changed),
        need(gproc:where(key(Account,Agent))=:=Sup andalso children(Sup,Deadline)=:={Listener,Fsm},changed),
        {_,_,State,_}=First,
        #{agent_id=>Agent,observed=>true,member=>lists:member(Queue,Qs),
            state=>atom_to_binary(State,utf8),reason=>observed,
            instance=>kz_binary:hexencode(crypto:hash(sha256,term_to_binary({node(),Sup,Listener,Fsm})))}
    catch
        throw:{agent_observation,Why} -> unknown(Agent,Why);
        exit:{timeout,_} -> unknown(Agent,timeout);
        _:_ -> unknown(Agent,unavailable)
    end.

children(Sup,Deadline) ->
    %% The registered per-agent OTP supervisor has exactly two fixed children.
    %% Explicit timeout avoids supervisor:which_children/1's infinite wait.
    Cs=gen_server:call(Sup,which_children,timeout(Deadline)),
    case Cs of
        [{acdc_agent_listener,L,worker,[acdc_agent_listener]},
         {acdc_agent_fsm,F,worker,[acdc_agent_fsm]}] when is_pid(L),is_pid(F) -> {L,F};
        [{acdc_agent_fsm,F,worker,[acdc_agent_fsm]},
         {acdc_agent_listener,L,worker,[acdc_agent_listener]}] when is_pid(L),is_pid(F) -> {L,F};
        _ -> throw({agent_observation,unavailable})
    end.
valid_state({Account,Agent,State,Listener},Account,Agent,Listener) ->
    lists:member(State,[wait,sync,ready,ringing,answered,wrapup,paused,outbound]);
valid_state(_,_,_,_) -> false.
queues(Qs) when is_list(Qs),length(Qs)=<1024 ->
    lists:all(fun id/1,Qs) andalso length(Qs)=:=length(lists:usort(Qs));
queues(_) -> false.
timeout(Deadline) ->
    Left=Deadline-erlang:monotonic_time(millisecond),
    need(Left>0,budget),erlang:min(Left,?CALL_MS).
unknown(Agent,Why) -> #{agent_id=>Agent,observed=>false,member=>null,state=>null,reason=>Why,instance=>null}.
need(true,_) -> ok;
need(false,Why) -> throw({agent_observation,Why}).
key(Account,Agent) -> {n,l,{acdc_dashboard_agent,Account,Agent}}.
id(B) when is_binary(B),byte_size(B)=:=32 -> re:run(B,<<"^[0-9a-f]{32}$">>,[{capture,none}])=:=match;
id(_) -> false.
wall() -> calendar:datetime_to_gregorian_seconds(calendar:universal_time()).
