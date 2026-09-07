%%% SPDX-License-Identifier: MPL-2.0
%%% REJECTED EXPERIMENT: initial_call does not identify kz_process fun wrappers.
%%% Root regression da512e/184d65 missed live paused workers. DO NOT compile
%%% into the application or use for rollout. Retained only as a reproducer.
%%% First-upgrade observation only: old listener must already be dead, its
%%% audited reader-producing spawn graph closed, and direct entry gated.
%%% This is NOT a generic VM quiescence proof. It never stops a process or
%%% changes a table/code. A conservative unrelated worker can cause refusal.
-module(acdc_stats_upgrade_drain).
-export([start/4,step/1,cancel/1]).

-spec start(pid(), {ets:tid(),pid()}, {ets:tid(),pid()}, map()) -> {ok,map()} | {error,atom()}.
start(Old,Call,Status,Options) ->
    case options(Options) of
        {error,_}=Error -> Error;
        {ok,Batch,Milliseconds,ProcessCap,CohortCap} ->
            State=#{owner=>self(),old=>Old,call=>Call,status=>Status,monitors=>#{},
                    supervisor=>whereis(acdc_stats_sup),
                    batch=>Batch,cohort_cap=>CohortCap,scanned=>0,captured=>0,down=>0,
                    deadline=>erlang:monotonic_time(millisecond)+Milliseconds},
            case sources(State) of
                ok ->
                    %% Snapshot AFTER the old producer is dead. The audited
                    %% workers do not spawn further retained-table readers.
                    Pids=processes(),
                    case length(Pids)=<ProcessCap of
                        true -> {ok,remember(State#{token=>make_ref(),phase=>scan,remaining=>Pids})};
                        false -> {error,process_limit}
                    end;
                Error -> Error
            end
    end.

-spec step(map()) -> {continue,map()} | {done,map()} | {error,atom()}.
step(#{owner:=Owner,token:=Token}=State) when Owner=:=self(),is_reference(Token) ->
    %% Only the exact last issued continuation is admitted. Caller maps are
    %% not authority for monitor references or completion counters.
    case get({?MODULE,Token}) of
        State ->
            case check(State) of
                ok -> work(State,maps:get(batch,State));
                {error,Code} -> fail(Code,State)
            end;
        _ -> _=cancel(State),{error,invalid_state}
    end;
step(#{owner:=Owner}) when Owner=:=self() -> {error,invalid_state};
step(_) -> {error,invalid_owner_state}.

-spec cancel(map()) -> ok | {error,atom()}.
cancel(#{owner:=Owner,token:=Token}) when Owner=:=self(),is_reference(Token) ->
    case erase({?MODULE,Token}) of
        #{monitors:=Monitors} -> maps:foreach(fun(Ref,_) -> erlang:demonitor(Ref,[flush]) end,Monitors);
        _ -> ok
    end,
    ok;
cancel(#{owner:=Owner}) when Owner=:=self() -> {error,invalid_state};
cancel(_) -> {error,invalid_owner_state}.

%% Continuations are process-local, single-use state, not serializable jobs.
%% Retain the token on cancellation; if a caller loses it, it must cancel the
%% original handle. Owner death automatically removes its Erlang monitors.
remember(#{token:=Token}=State) -> put({?MODULE,Token},State),State.
continued(State) -> {continue,remember(State)}.

options(O) when is_map(O),map_size(O)=<4 ->
    B=maps:get(batch_size,O,100),D=maps:get(deadline_ms,O,30000),
    P=maps:get(max_processes,O,10000),C=maps:get(max_cohort,O,1000),
    case maps:without([batch_size,deadline_ms,max_processes,max_cohort],O)=:=#{} andalso
         bounded(B,256) andalso bounded(D,60000) andalso bounded(P,10000) andalso bounded(C,1000) of
        true -> {ok,B,D,P,C}; false -> {error,invalid_options}
    end;
options(_) -> {error,invalid_options}.
bounded(N,Max) -> is_integer(N) andalso N>=1 andalso N=<Max.

sources(#{old:=Old,call:={Call,CPid},status:={Status,SPid}}=State)
  when is_pid(Old),node(Old)=:=node(),is_reference(Call),is_reference(Status),
       Call=/=Status,is_pid(CPid),is_pid(SPid),CPid=/=SPid,
       node(CPid)=:=node(),node(SPid)=:=node(),Old=/=CPid,Old=/=SPid ->
    case is_process_alive(Old) of
        true -> {error,old_worker_alive};
        false ->
            case keeper_children(State,CPid,SPid) andalso
                 retained(Call,CPid,acdc_stats_call,set) andalso
                 retained(Status,SPid,acdc_stats_status,ordered_set) of
                true -> ok;
                false -> {error,retained_source_changed}
            end
    end;
sources(_) -> {error,invalid_sources}.
keeper_children(#{supervisor:=Sup,deadline:=Deadline},CPid,SPid) when is_pid(Sup) ->
    try
        Remaining=Deadline-erlang:monotonic_time(millisecond),
        true=Remaining>0,
        true=whereis(acdc_stats_sup)=:=Sup,
        %% supervisor:which_children/1 uses this native request but has an
        %% unbounded call timeout. Keep this observation within our deadline.
        Children=gen_server:call(Sup,which_children,min(1000,Remaining)),
        Call=[P || {acdc_stats_call,P,worker,_}<-Children],
        Status=[P || {acdc_stats_status,P,worker,_}<-Children],
        Stats=[P || {acdc_stats,P,worker,_}<-Children],
        %% A permanent child's automatic restart would reopen the spawn
        %% graph before table handoff. Only an explicitly stopped, retained
        %% child specification is admissible; absent/restarting/live refuse.
        Call=:=[CPid] andalso Status=:=[SPid] andalso Stats=:=[undefined]
            andalso whereis(acdc_stats_sup)=:=Sup
    catch _:_ -> false end;
keeper_children(_,_,_) -> false.
retained(Tid,Pid,Name,Type) ->
    try
        is_process_alive(Pid) andalso ets:whereis(Name)=:=Tid andalso
        ets:info(Tid,owner)=:=Pid andalso ets:info(Tid,type)=:=Type andalso
        ets:info(Tid,keypos)=:=2 andalso ets:info(Tid,protection)=:=protected
    catch error:badarg -> false end.
check(State) ->
    case erlang:monotonic_time(millisecond)<maps:get(deadline,State) of
        false -> {error,deadline};
        true -> sources(State)
    end.

work(State,0) -> continued(State);
work(#{phase:=scan,remaining:=[]}=State,_) ->
    continued(State#{phase:=wait,pending=>maps:to_list(maps:get(monitors,State))});
work(#{phase:=scan,remaining:=[Pid|Rest],scanned:=N}=State,Budget) ->
    case check(State) of
        {error,Code} -> fail(Code,State);
        ok ->
            Next=State#{remaining:=Rest,scanned:=N+1},
            case process_info(Pid,initial_call) of
                {initial_call,{Module,_,_}} when Module=:=kz_process;Module=:=acdc_stats ->
                    capture(Pid,Next,Budget);
                _ -> work(Next,Budget-1)
            end
    end;
work(#{phase:=wait,pending:=[]}=State,_) ->
    case check(State) of
        ok ->
            ok=cancel(State),
            {done,#{version=>1,scope=>audited_old_stats_spawn_graph,
                    scanned=>maps:get(scanned,State),captured=>maps:get(captured,State),
                    down=>maps:get(down,State),verified=>true}};
        {error,Code} -> fail(Code,State)
    end;
work(#{phase:=wait,pending:=[{Ref,Pid}|Rest],monitors:=Monitors,down:=Down}=State,Budget) ->
    case check(State) of
        {error,Code} -> fail(Code,State);
        ok ->
            %% Consume only this helper's exact monitor reference and PID.
            %% No metadata, process scan or purge can substitute for DOWN.
            receive
                {'DOWN',Ref,process,Pid,_Reason} ->
                    work(State#{pending:=Rest,monitors:=maps:remove(Ref,Monitors),down:=Down+1},Budget-1)
            after 0 ->
                %% One pass per step: don't busy-spin on a surviving worker.
                continued(State#{pending:=Rest++[{Ref,Pid}]})
            end
    end.
capture(Pid,State,_) when Pid=:=self() -> fail(caller_in_cohort,State);
capture(Pid,#{captured:=N,cohort_cap:=Cap,monitors:=Monitors}=State,Budget) ->
    case N<Cap of
        false -> fail(cohort_limit,State);
        true ->
            Ref=monitor(process,Pid),
            work(remember(State#{captured:=N+1,monitors:=Monitors#{Ref=>Pid}}),Budget-1)
    end.
fail(Code,State) -> ok=cancel(State),{error,Code}.
