#!/usr/bin/env escript
%%! +S 1:1 +SDcpu 1 +SDio 1 +A 1 -setcookie unused_queue_probe -start_epmd false -kernel logger_level none
%% Read-only snapshots in the original lab's exact synthetic company.
-mode(compile).
-include_lib("kernel/include/file.hrl").
-define(ACCOUNT, <<"45e827067baf078029d0ca16a489fa8a">>).
main(Args) ->
    try
        [User0|Pinned]=Args,true=length(Pinned)=<1,
        {ok,H}=inet:gethostname(),
        Ip=case H of "kz5-stage-kazoo-apps"->{172,30,253,14}; "kz5-stage-kazoo-apps-peer"->{172,30,253,20} end,
        {ok,Ifs}=inet:getifaddrs(),true=lists:any(fun({_,V})->lists:member({addr,Ip},V) end,Ifs),
        {ok,#file_info{type=regular,uid=0,links=1,mode=M}}=file:read_link_info("/etc/kazoo/.erlang.cookie"),
        true=(M band 8#077)=:=0,{ok,C}=file:read_file("/etc/kazoo/.erlang.cookie"),
        ok=application:set_env(kernel,inet_dist_use_interface,Ip),
        {ok,_}=net_kernel:start([list_to_atom("queue_agent_probe_"++os:getpid()++"@"++H),shortnames]),
        true=erlang:set_cookie(node(),binary_to_atom(string:trim(C),utf8)),
        N=list_to_atom("kazoo_apps@"++H),U=list_to_binary(User0),
        match=re:run(U,<<"^[a-f0-9]{32}$">>,[{capture,none}]),
        Db=rpc(N,kzs_util,format_account_db,[?ACCOUNT]),
        {ok,A}=rpc(N,kz_datamgr,open_doc,[Db,?ACCOUNT]),
        <<"acceptance-724fa76c8821.invalid">>=rpc(N,kz_json,get_value,[<<"realm">>,A]),
        {ok,D}=rpc(N,kz_datamgr,open_doc,[Db,U]),
        ?ACCOUNT=rpc(N,kz_json,get_value,[<<"pvt_account_id">>,D]),
        <<"user">>=rpc(N,kz_doc,type,[D]),
        <<"user">>=rpc(N,kz_json,get_value,[<<"priv_level">>,D]),
        true=rpc(N,kz_json,is_true,[<<"enabled">>,D]),
        Found=case Pinned of
            [] -> case rpc(N,acdc_agents_sup,find_agent_supervisor,[?ACCOUNT,U]) of
                      undefined -> undefined;
                      S when is_pid(S) -> rpc(N,acdc_agent_sup,fsm,[S])
                  end;
            [Pid0] -> match=re:run(Pid0,"^<0\\.[0-9]+\\.[0-9]+>$",[{capture,none}]),
                      rpc(N,erlang,list_to_pid,[Pid0])
        end,
        case Found of
            undefined -> io:put_chars("{\"present\":false}\n");
            F when is_pid(F) ->
                {?ACCOUNT,U,_,_}=rpc(N,acdc_agent_fsm,dashboard_state,[F,2000]),
                Status=rpc(N,acdc_agent_fsm,status,[F]),true=is_list(Status),
                State=proplists:get_value(state,Status),true=is_binary(State),
                P=[{<<"present">>,true},{<<"state">>,State},
                   {<<"fsm">>,list_to_binary(rpc(N,erlang,pid_to_list,[F]))},
                   {<<"member_call_id">>,proplists:get_value(member_call_id,Status,<<>>)},
                   {<<"agent_call_id">>,proplists:get_value(agent_call_id,Status,<<>>)}],
                J=rpc(N,kz_json,from_list,[P]),io:format("~s~n",[rpc(N,kz_json,encode,[J])])
        end,net_kernel:stop()
    catch _:_ -> io:put_chars("QUEUE_SNAPSHOT_FAILED\n"),halt(1) end.
rpc(N,M,F,A)->rpc:call(N,M,F,A,5000).
