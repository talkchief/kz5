#!/usr/bin/env escript
%%! +S 1:1 +SDcpu 1 +SDio 1 +A 1 -setcookie unused_maintenance_probe -start_epmd false -kernel logger_level none
%% Read-only, exact private lab/tenant admission. Does not establish a fence.
-mode(compile).
-include_lib("kernel/include/file.hrl").
-define(ACCOUNT, <<"45e827067baf078029d0ca16a489fa8a">>).
main(Args) ->
    try
        [User0]=Args,U=list_to_binary(User0),
        match=re:run(U,<<"^[a-f0-9]{32}$">>,[{capture,none}]),
        {ok,H}=inet:gethostname(),
        Ip=case H of "kz5-stage-kazoo-apps"->{172,30,253,14};
                     "kz5-stage-kazoo-apps-peer"->{172,30,253,20} end,
        {ok,Ifs}=inet:getifaddrs(),
        true=lists:any(fun({_,V})->lists:member({addr,Ip},V) end,Ifs),
        {ok,#file_info{type=regular,uid=0,links=1,mode=M}}=
            file:read_link_info("/etc/kazoo/.erlang.cookie"),
        true=(M band 8#077)=:=0,
        {ok,C}=file:read_file("/etc/kazoo/.erlang.cookie"),
        ok=application:set_env(kernel,inet_dist_use_interface,Ip),
        {ok,_}=net_kernel:start([list_to_atom("maintenance_probe_"++os:getpid()++"@"++H),shortnames]),
        true=erlang:set_cookie(node(),binary_to_atom(string:trim(C),utf8)),
        N=list_to_atom("kazoo_apps@"++H),
        Db=rpc(N,kzs_util,format_account_db,[?ACCOUNT]),
        {ok,A}=rpc(N,kz_datamgr,open_doc,[Db,?ACCOUNT]),
        <<"acceptance-724fa76c8821.invalid">>=rpc(N,kz_json,get_value,[<<"realm">>,A]),
        {ok,D}=rpc(N,kz_datamgr,open_doc,[Db,U]),
        ?ACCOUNT=rpc(N,kz_json,get_value,[<<"pvt_account_id">>,D]),
        <<"user">>=rpc(N,kz_doc,type,[D]),
        <<"user">>=rpc(N,kz_json,get_value,[<<"priv_level">>,D]),
        true=rpc(N,kz_json,is_true,[<<"enabled">>,D]),
        Sup=rpc(N,acdc_agents_sup,find_agent_supervisor,[?ACCOUNT,U]),true=is_pid(Sup),
        Fsm=rpc(N,acdc_agent_sup,fsm,[Sup]),true=is_pid(Fsm),
        Listener=rpc(N,acdc_agent_sup,listener,[Sup]),true=is_pid(Listener),
        {ok,#{account_id:=?ACCOUNT,agent_id:=U,listener:=Listener,state:=State}=F}=
            rpc(N,acdc_agent_fsm,maintenance_state,[Fsm,2000]),
        {ok,#{account_id:=?ACCOUNT,agent_id:=U,fsm:=Fsm,queues:=Queues}}=
            rpc(N,acdc_agent_listener,maintenance_state,[Listener,2000]),
        %% Detect supervisor/child replacement during this observation. A
        %% caller still needs admission fencing to exclude intervening work.
        Sup=rpc(N,acdc_agents_sup,find_agent_supervisor,[?ACCOUNT,U]),
        Fsm=rpc(N,acdc_agent_sup,fsm,[Sup]),Listener=rpc(N,acdc_agent_sup,listener,[Sup]),
        true=rpc(N,gen_listener,is_consuming,[Listener]),
        Pause=case maps:get(pause_remaining_ms,F) of infinity-><<"infinity">>;V when is_integer(V),V>=0->V end,
        Props=[{<<"account_id">>,?ACCOUNT},{<<"agent_id">>,U},
               {<<"fsm">>,list_to_binary(rpc(N,erlang,pid_to_list,[Fsm]))},
               {<<"listener">>,list_to_binary(rpc(N,erlang,pid_to_list,[Listener]))},
               {<<"state">>,atom_to_binary(State,utf8)},{<<"queues">>,Queues},
               {<<"pause_remaining_ms">>,Pause},
               {<<"pause_until_unix_ms">>,maps:get(pause_until_unix_ms,F,0)},
               {<<"listener_consuming">>,true},{<<"admission_fence_proven">>,false}],
        J=rpc(N,kz_json,from_list,[Props]),io:format("~s~n",[rpc(N,kz_json,encode,[J])]),
        net_kernel:stop()
    catch _:_ -> io:put_chars("MAINTENANCE_SNAPSHOT_REFUSED\n"),halt(1) end.
rpc(N,M,F,A)->rpc:call(N,M,F,A,5000).
