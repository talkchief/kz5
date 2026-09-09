#!/usr/bin/env escript
%%! +S 1:1 +SDcpu 1 +SDio 1 +A 1 -setcookie unused_maintenance_snapshot -start_epmd false -kernel logger_level none
%% Local-node read-only agent inventory for the maintenance coordinator.
%% It is NOT a complete cluster drain or an admission fence. Output contains
%% account/agent identifiers and must be stored only in the private journal.
-mode(compile).
-include_lib("kernel/include/file.hrl").

main(Args) ->
    try
        ["--snapshot", Bind0]=Args,
        {ok,Bind}=inet:parse_ipv4_address(Bind0),
        {ok,Ifs}=inet:getifaddrs(),
        true=lists:any(fun({_,V})->lists:member({addr,Bind},V) end,Ifs),
        {ok,Host}=inet:gethostname(),
        match=re:run(Host,"^[a-zA-Z0-9-]{1,63}$",[{capture,none}]),
        {ok,#file_info{type=regular,uid=0,links=1,mode=M,size=Size}}=
            file:read_link_info("/etc/kazoo/.erlang.cookie"),
        true=(M band 8#077)=:=0,true=Size>0 andalso Size=<1024,
        {ok,Cookie}=file:read_file("/etc/kazoo/.erlang.cookie"),
        ok=application:set_env(kernel,inet_dist_use_interface,Bind),
        {ok,_}=net_kernel:start([list_to_atom("maintenance_snapshot_"++os:getpid()++"@"++Host),shortnames]),
        true=erlang:set_cookie(node(),binary_to_atom(string:trim(Cookie),utf8)),
        N=list_to_atom("kazoo_apps@"++Host),
        {ok,RemoteIfs}=rpc(N,inet,getifaddrs,[]),
        true=lists:any(fun({_,V})->lists:member({addr,Bind},V) end,RemoteIfs),
        Epoch=epoch(N),Workers=workers(N),
        put(snapshot_deadline,erlang:monotonic_time(millisecond)+120000),
        Pairs=[snapshot(N,S) || S<-Workers],
        Workers=workers(N),Epoch=epoch(N),
        Ids=[{maps:get(account_id,A),maps:get(agent_id,A)} || {A,_}<-Pairs],
        true=length(Ids)=:=length(lists:usort(Ids)),
        Data=[{<<"schema_version">>,1},{<<"node">>,atom_to_binary(N,utf8)},
              {<<"epoch">>,Epoch},{<<"captured_at_unix_ms">>,erlang:system_time(millisecond)},
              {<<"agents">>,[json_agent(N,A) || {A,_}<-Pairs]},
              {<<"document_revisions">>,[J || {_,J}<-Pairs]},
              {<<"all_agent_workers_observed">>,true},
              {<<"complete_cluster_drain_proven">>,false},
              {<<"admission_fence_proven">>,false}],
        Json=rpc(N,kz_json,from_list,[Data]),
        io:format("~s~n",[rpc(N,kz_json,encode,[Json])]),net_kernel:stop()
    catch _:_ -> io:put_chars("MAINTENANCE_INVENTORY_REFUSED\n"),halt(1) end.

workers(N) ->
    Ws=rpc(N,acdc_agents_sup,workers,[]),true=is_list(Ws),true=length(Ws)=<5000,
    true=lists:all(fun is_pid/1,Ws),lists:sort(Ws).
epoch(N) ->
    Pid=rpc(N,os,getpid,[]),Creation=rpc(N,erlang,system_info,[creation]),
    match=re:run(Pid,"^[0-9]+$",[{capture,none}]),true=is_integer(Creation),
    list_to_binary(Pid++"-"++integer_to_list(Creation)).
snapshot(N,Sup) ->
    true=erlang:monotonic_time(millisecond)<get(snapshot_deadline),
    Fsm=rpc(N,acdc_agent_sup,fsm,[Sup]),Listener=rpc(N,acdc_agent_sup,listener,[Sup]),
    true=is_pid(Fsm),true=is_pid(Listener),
    {ok,#{account_id:=AccountId,agent_id:=AgentId,listener:=Listener,state:=State}=F}=
        rpc(N,acdc_agent_fsm,maintenance_state,[Fsm,2000]),
    true=State=:=ready orelse State=:=paused,hex_id(AccountId),hex_id(AgentId),
    {ok,#{account_id:=AccountId,agent_id:=AgentId,fsm:=Fsm,queues:=Queues}}=
        rpc(N,acdc_agent_listener,maintenance_state,[Listener,2000]),
    lists:foreach(fun hex_id/1,Queues),
    true=rpc(N,gen_listener,is_consuming,[Listener]),
    Bindings=rpc(N,gen_listener,bindings,[Listener]),true=is_list(Bindings),
    Bound=lists:usort([proplists:get_value(queue_id,P) || {<<"acdc_queue">>,P}<-Bindings,
        proplists:get_value(account_id,P)=:=AccountId,
        lists:member(member_connect_req,proplists:get_value(restrict_to,P,[]))]),
    Bound=lists:usort(Queues),
    %% Read the document revision, not its saved queue roster as runtime truth.
    Db=rpc(N,kzs_util,format_account_db,[AccountId]),
    {ok,User}=rpc(N,kz_datamgr,open_doc,[Db,AgentId]),
    <<"user">>=rpc(N,kz_doc,type,[User]),AccountId=rpc(N,kz_doc,account_id,[User]),
    Revision=rpc(N,kz_json,get_ne_binary_value,[<<"_rev">>,User]),
    true=is_binary(Revision) andalso byte_size(Revision)>0,
    Sup=rpc(N,acdc_agents_sup,find_agent_supervisor,[AccountId,AgentId]),
    Fsm=rpc(N,acdc_agent_sup,fsm,[Sup]),Listener=rpc(N,acdc_agent_sup,listener,[Sup]),
    RevisionJson=rpc(N,kz_json,from_list,[[{<<"account_id">>,AccountId},
        {<<"agent_id">>,AgentId},{<<"revision">>,Revision}]]),
    {F#{queues=>Queues},RevisionJson}.
json_agent(N,#{account_id:=AccountId,agent_id:=AgentId,state:=State,queues:=Queues}=F) ->
    Until=case maps:get(pause_remaining_ms,F) of
        infinity-><<"infinity">>;
        0 when State=:=ready->0;
        Left when is_integer(Left),Left>0,State=:=paused->maps:get(pause_until_unix_ms,F)
    end,
    rpc(N,kz_json,from_list,[[{<<"node">>,atom_to_binary(N,utf8)},
        {<<"account_id">>,AccountId},{<<"agent_id">>,AgentId},
        {<<"state">>,atom_to_binary(State,utf8)},{<<"queues">>,Queues},
        {<<"pause_until_unix_ms">>,Until}]]).
hex_id(Id) -> match=re:run(Id,<<"^[a-f0-9]{32}$">>,[{capture,none}]),ok.
rpc(N,M,F,A) ->
    Timeout=case get(snapshot_deadline) of
        undefined->5000;
        End->Left=End-erlang:monotonic_time(millisecond),true=Left>0,min(5000,Left)
    end,
    rpc:call(N,M,F,A,Timeout).
