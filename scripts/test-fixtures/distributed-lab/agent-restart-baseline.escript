#!/usr/bin/env escript
%%! +S 1:1 +SDcpu 1 +SDio 1 +A 1 -setcookie unused_restart_fixture -start_epmd false -kernel logger_level none
%% Explicit baseline reproduction/restore regression, not an upgrader. Run under the host's
%% acceptance lock, after zero-media/zero-callback admission. Fixed lab agent
%% only; finite pauses expire even if the fixture is interrupted.
-mode(compile).
-include_lib("kernel/include/file.hrl").
-define(A, <<"45e827067baf078029d0ca16a489fa8a">>).
-define(U, <<"d757645c21f28890684a5b91fe83722d">>).
-define(Q, <<"cabcfb72812b530ccc32ffba30ef680d">>).
main(Args) ->
    Code=try
        Restore=case Args of ["--live"]->false;["--live","--restore"]->true end,
        {ok,"kz5-stage-kazoo-apps"}=inet:gethostname(),
        {ok,Ifs}=inet:getifaddrs(),true=has_ip(Ifs,{172,30,253,14}),
        {ok,#file_info{type=regular,uid=0,links=1,mode=M}}=
            file:read_link_info("/etc/kazoo/.erlang.cookie"),
        true=(M band 8#077)=:=0,{ok,C}=file:read_file("/etc/kazoo/.erlang.cookie"),
        ok=application:set_env(kernel,inet_dist_use_interface,{172,30,253,14}),
        {ok,_}=net_kernel:start([list_to_atom("restart_baseline_"++os:getpid()++"@kz5-stage-kazoo-apps"),shortnames]),
        true=erlang:set_cookie(node(),binary_to_atom(string:trim(C),utf8)),
        Ns=['kazoo_apps@kz5-stage-kazoo-apps','kazoo_apps@kz5-stage-kazoo-apps-peer'],
        lists:foreach(fun({N,Ip}) -> admit(N,Ip) end,
                      lists:zip(Ns,[{172,30,253,14},{172,30,253,20}])),
        case Restore of
            true -> lists:foreach(fun(N) ->
                true=rpc(N,erlang,function_exported,[acdc_agent_fsm,maintenance_restore,3]),
                true=rpc(N,erlang,function_exported,[acdc_agent_listener,maintenance_restore,3])
            end,Ns);
            false -> ok
        end,
        Before=[snapshot(N) || N<-Ns],
        true=lists:all(fun({_,ready,0})->true;(_)->false end,Before),
        lists:foreach(fun({N,{F,_,_}}) ->
            put({owned_fsm,N},F),ok=rpc(N,acdc_agent_fsm,pause,[F,45])
        end,lists:zip(Ns,Before)),
        Paused=until(fun() -> Vs=[snapshot(N)||N<-Ns],
            case lists:all(fun({_,paused,T})->is_integer(T) andalso T>30000;(_)->false end,Vs) of
                true->{ok,Vs};false->retry
            end end,10),
        Started=erlang:monotonic_time(millisecond),
        %% Memory-only regression checkpoints, captured from actual runtime.
        %% The production maintenance coordinator still needs a protected
        %% durable generation and a complete cluster fence/drain.
        Checkpoints=case Restore of
            true -> [{N,checkpoint(N)} || N<-Ns]; false -> [] end,
        io:put_chars("{\"phase\":\"paused_before_restart\",\"replicas\":2}\n"),
        lists:foreach(fun({N,{Old,paused,_}}) ->
            {Old,paused,Left}=snapshot(N),true=Left>20000,
            {ok,Sup}=rpc(N,acdc_agents_sup,restart_agent,[?A,?U]),true=is_pid(Sup),
            New=until(fun() -> case rpc(N,acdc_agent_sup,fsm,[Sup]) of
                F when is_pid(F),F=/=Old -> {ok,F};_ -> retry end end,5),
            put({owned_fsm,N},New)
        end,lists:zip(Ns,Paused)),
        After=until(fun() -> Vs=[state_only(N)||N<-Ns],
            case lists:all(fun({_,S})->S=:=ready orelse S=:=paused end,Vs) of
                true->{ok,Vs};false->retry end end,15),
        Final=case Restore of
            true ->
                lists:foreach(fun({N,Cp}) -> restore_checkpoint(N,Cp) end,Checkpoints),
                [{F,S} || N<-Ns, {F,S,_}<-[snapshot(N)]];
            false -> After
        end,
        Pass=lists:all(fun({_,S})->S=:=paused end,Final),
        States=[atom_to_list(S)||{_,S}<-Final],
        Elapsed=erlang:monotonic_time(millisecond)-Started,
        true=Elapsed<20000,
        io:format("{\"phase\":\"after_restart\",\"states\":[\"~s\",\"~s\"],\"pause_preserved\":~s,\"restart_elapsed_ms\":~p,\"restore_executed\":~s}~n",
                  States++[atom_to_list(Pass),Elapsed,atom_to_list(Restore)]),
        case Pass of true->0;false->1 end
    catch Class:Reason ->
        %% Phase labels are fixed atoms, not call data or raw RPC results.
        Failure=case Reason of {badmatch,{error,E}} when is_atom(E)->E;
                               {badmatch,_}->unexpected_result;
                               E when is_atom(E)->E;_->unclassified end,
        io:format("{\"phase\":\"failure\",\"step\":\"~p\",\"node_scope\":\"~p\",\"class\":\"~p\",\"reason\":\"~p\"}~n",
                  [get(restore_step),get(restore_node),Class,Failure]),
        io:put_chars("RESTART_BASELINE_REFUSED_OR_FAILED\n"),1
    after
        %% Never stop calls, re-login, or change an unknown replacement FSM.
        %% Only resume the exact finite pause introduced into this ready agent.
        lists:foreach(fun cleanup/1,
            ['kazoo_apps@kz5-stage-kazoo-apps','kazoo_apps@kz5-stage-kazoo-apps-peer'])
    end,
    case get(cleanup_failed) of true->halt(1);_->halt(Code) end.

admit(N,Ip) ->
    {ok,Ifs}=rpc(N,inet,getifaddrs,[]),true=has_ip(Ifs,Ip),
    true=rpc(N,erlang,function_exported,[acdc_agent_fsm,maintenance_state,2]),
    true=rpc(N,erlang,function_exported,[acdc_agent_listener,maintenance_state,2]),
    Db=rpc(N,kzs_util,format_account_db,[?A]),
    {ok,A}=rpc(N,kz_datamgr,open_doc,[Db,?A]),
    <<"acceptance-724fa76c8821.invalid">>=rpc(N,kz_json,get_value,[<<"realm">>,A]),
    {ok,U}=rpc(N,kz_datamgr,open_doc,[Db,?U]),
    ?A=rpc(N,kz_json,get_value,[<<"pvt_account_id">>,U]),
    <<"user">>=rpc(N,kz_doc,type,[U]),
    <<"user">>=rpc(N,kz_json,get_value,[<<"priv_level">>,U]),
    true=rpc(N,kz_json,is_true,[<<"enabled">>,U]).

snapshot(N) ->
    S=rpc(N,acdc_agents_sup,find_agent_supervisor,[?A,?U]),true=is_pid(S),
    F=rpc(N,acdc_agent_sup,fsm,[S]),L=rpc(N,acdc_agent_sup,listener,[S]),
    {ok,#{account_id:=?A,agent_id:=?U,listener:=L,state:=State,pause_remaining_ms:=Time}}=
        rpc(N,acdc_agent_fsm,maintenance_state,[F,2000]),
    {ok,#{account_id:=?A,agent_id:=?U,fsm:=F,queues:=[?Q]}}=
        rpc(N,acdc_agent_listener,maintenance_state,[L,2000]),
    {F,State,Time}.
state_only(N) ->
    F=get({owned_fsm,N}),true=is_pid(F),
    {?A,?U,S,_}=rpc(N,acdc_agent_fsm,dashboard_state,[F,2000]),{F,S}.
checkpoint(N) ->
    F=get({owned_fsm,N}),true=is_pid(F),
    {ok,#{account_id:=?A,agent_id:=?U,listener:=L,state:=paused,
          pause_until_unix_ms:=Until}}=rpc(N,acdc_agent_fsm,maintenance_state,[F,2000]),
    {ok,#{account_id:=?A,agent_id:=?U,fsm:=F,queues:=[?Q]}}=
        rpc(N,acdc_agent_listener,maintenance_state,[L,2000]),
    {#{account_id=>?A,agent_id=>?U,state=>paused,pause_until_unix_ms=>Until},
     #{account_id=>?A,agent_id=>?U,queues=>[?Q]}}.
restore_checkpoint(N,{FsmCheckpoint,ListenerCheckpoint}) ->
    put(restore_node,case N of 'kazoo_apps@kz5-stage-kazoo-apps'->primary;_->peer end),
    put(restore_step,pre_restore_snapshot),
    Owned=get({owned_fsm,N}),
    {Owned,_,_}=snapshot(N),
    Sup=rpc(N,acdc_agents_sup,find_agent_supervisor,[?A,?U]),
    Owned=rpc(N,acdc_agent_sup,fsm,[Sup]),L=rpc(N,acdc_agent_sup,listener,[Sup]),
    put(restore_step,fsm_restore),
    {ok,#{state:=paused,notifications_queued:=true}}=
        rpc(N,acdc_agent_fsm,maintenance_restore,[Owned,FsmCheckpoint,2000]),
    put(restore_step,listener_restore),
    {ok,#{queues:=[?Q],state:=paused,bindings_queued:=true}}=
        rpc(N,acdc_agent_listener,maintenance_restore,[L,ListenerCheckpoint,3000]),
    %% Queued bindings are not sufficient. Inspect the native consumer's
    %% actual binding registry after its mailbox barrier.
    put(restore_step,consumer_binding_check),
    true=rpc(N,gen_listener,is_consuming,[L]),
    Bindings=rpc(N,gen_listener,bindings,[L]),true=is_list(Bindings),
    [?Q]=lists:usort([proplists:get_value(queue_id,P) || {<<"acdc_queue">>,P}<-Bindings,
        proplists:get_value(account_id,P)=:=?A,
        lists:member(member_connect_req,proplists:get_value(restrict_to,P,[]))]),
    put(restore_step,restored_snapshot),
    {Owned,paused,Remaining}=snapshot(N),true=Remaining>10000,
    {ok,#{pause_until_unix_ms:=ObservedUntil}}=
        rpc(N,acdc_agent_fsm,maintenance_state,[Owned,2000]),
    OriginalUntil=maps:get(pause_until_unix_ms,FsmCheckpoint),
    put(restore_step,deadline_check),
    true=ObservedUntil=<OriginalUntil,true=ObservedUntil>=OriginalUntil-20,
    io:put_chars("{\"phase\":\"restore_verified\",\"deadline_not_extended\":true,\"runtime_membership_retained\":true}\n").
cleanup(N) ->
    case get({owned_fsm,N}) of
        undefined -> ok;
        Owned ->
            try case snapshot(N) of
                {Owned,ready,0}->ok;
                {Owned,paused,T} when is_integer(T),T>0,T=<45000 ->
                    ok=rpc(N,acdc_agent_fsm,resume,[Owned]);
                _->error(ownership_or_state_changed)
            end
            catch _:_ -> put(cleanup_failed,true),io:put_chars("FINITE_PAUSE_CLEANUP_UNVERIFIED\n") end
    end.
until(F,Seconds) -> until_deadline(F,erlang:monotonic_time(millisecond)+Seconds*1000).
until_deadline(F,End) ->
    case F() of
        {ok,V}->V;
        retry->true=erlang:monotonic_time(millisecond)<End,
               timer:sleep(100),until_deadline(F,End)
    end.
has_ip(Ifs,Ip)->lists:any(fun({_,V})->lists:member({addr,Ip},V) end,Ifs).
rpc(N,M,F,A)->rpc:call(N,M,F,A,5000).
