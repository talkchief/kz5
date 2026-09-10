#!/usr/bin/env escript
%%! +S 1:1 +SDcpu 1 +SDio 1 +A 1 -setcookie unused_queue_snapshot -start_epmd false -kernel logger_level none
%% Local-node read-only current queue worker inventory. Not a fence: the
%% coordinator must independently drain broker deliveries, durable callbacks,
%% media and producers and keep admission closed throughout collection.
-mode(compile).
-include_lib("kernel/include/file.hrl").

main(Args) ->
    try
        ["--snapshot",Bind0]=Args,
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
        {ok,_}=net_kernel:start([list_to_atom("queue_snapshot_"++os:getpid()++"@"++Host),shortnames]),
        true=erlang:set_cookie(node(),binary_to_atom(string:trim(Cookie),utf8)),
        N=list_to_atom("kazoo_apps@"++Host),
        put(snapshot_deadline,erlang:monotonic_time(millisecond)+120000),
        put(worker_budget,5000),
        {ok,RemoteIfs}=rpc(N,inet,getifaddrs,[]),
        true=lists:any(fun({_,V})->lists:member({addr,Bind},V) end,RemoteIfs),
        Epoch=epoch(N),Startup=startup(N),Queues=children(N,acdc_queues_sup,acdc_queue_sup),
        []=rpc(N,supervisor,which_children,[acdc_announcements_sup]),
        Rows=[queue(N,Sup)||Sup<-Queues],
        Queues=children(N,acdc_queues_sup,acdc_queue_sup),Epoch=epoch(N),Startup=startup(N),
        []=rpc(N,supervisor,which_children,[acdc_announcements_sup]),
        Ids=[{proplists:get_value(<<"account_id">>,R),proplists:get_value(<<"queue_id">>,R)}||R<-Rows],
        true=length(Ids)=:=length(lists:usort(Ids)),
        Json=object(N,[{<<"schema_version">>,2},{<<"node">>,atom_to_binary(N,utf8)},
                       {<<"startup_token">>,startup_token(Startup)},
                       {<<"epoch">>,Epoch},{<<"captured_at_unix_ms">>,erlang:system_time(millisecond)},
                       {<<"queues">>,[object(N,R)||R<-Rows]},
                       {<<"all_queue_workers_observed">>,true},
                       {<<"complete_cluster_drain_proven">>,false},{<<"admission_fence_proven">>,false}]),
        io:format("~s~n",[rpc(N,kz_json,encode,[Json])]),net_kernel:stop()
    catch _:_ -> io:put_chars("MAINTENANCE_QUEUE_INVENTORY_REFUSED\n"),halt(1) end.

%% Unlike workers/0 helpers, never silently omit restarting/undefined children.
startup(N) ->
    {ok,#{initializer:=Pid,epoch:=Ref,revision:=Revision}=S}=rpc(N,acdc_init,maintenance_state,[2000]),
    true=is_pid(Pid),true=is_reference(Ref),true=is_integer(Revision) andalso Revision>=2,S.
startup_token(S) ->
    iolist_to_binary([io_lib:format("~2.16.0b",[B]) || <<B>> <= crypto:hash(sha256,term_to_binary(S))]).
children(N,Sup,Module) ->
    Cs=rpc(N,supervisor,which_children,[Sup]),true=is_list(Cs),true=length(Cs)=<5000,
    Ps=[begin {_,P,supervisor,[Module]}=C,true=is_pid(P),P end||C<-Cs],
    true=length(Ps)=:=length(lists:usort(Ps)),lists:sort(Ps).
queue(N,Sup) ->
    Original=rpc(N,supervisor,which_children,[Sup]),true=is_list(Original),
    2=length(Original),
    Manager=rpc(N,acdc_queue_sup,manager,[Sup]),true=is_pid(Manager),
    WorkerSup=rpc(N,acdc_queue_sup,workers_sup,[Sup]),true=is_pid(WorkerSup),
    {ok,#{account_id:=A,queue_id:=Q,supervisor:=Sup,busy_agents:=Busy0}}=
        rpc(N,acdc_queue_manager,maintenance_state,[Manager,2000]),hex_id(A),hex_id(Q),
    lists:foreach(fun hex_id/1,Busy0),Busy=lists:sort(Busy0),
    Workers=children(N,WorkerSup,acdc_queue_worker_sup),
    true=length(Workers)>0,
    ManagerQueues=listener_queues(N,Manager),
    %% Secondary queue declaration is asynchronous: primary consumption alone
    %% must not let its still-pending creation escape the broker inventory.
    true=lists:member(<<"acdc.queue.manager.",Q/binary>>,ManagerQueues),
    BrokerQueues=lists:usort(ManagerQueues++lists:append([worker(N,W,Manager,A,Q)||W<-Workers])),
    Db=rpc(N,kzs_util,format_account_db,[A]),
    {ok,Doc}=rpc(N,kz_datamgr,open_doc,[Db,Q]),
    <<"queue">>=rpc(N,kz_doc,type,[Doc]),A=rpc(N,kz_doc,account_id,[Doc]),Q=rpc(N,kz_doc,id,[Doc]),
    Revision=rpc(N,kz_json,get_ne_binary_value,[<<"_rev">>,Doc]),
    match=re:run(Revision,<<"^[1-9][0-9]*-[a-f0-9]{32}$">>,[{capture,none}]),
    Workers=children(N,WorkerSup,acdc_queue_worker_sup),
    Original=rpc(N,supervisor,which_children,[Sup]),
    {ok,#{account_id:=A,queue_id:=Q,supervisor:=Sup,busy_agents:=Busy1}}=
        rpc(N,acdc_queue_manager,maintenance_state,[Manager,2000]),
    Busy=lists:sort(Busy1),
    [{<<"account_id">>,A},{<<"queue_id">>,Q},{<<"document_revision">>,Revision},
     {<<"worker_count">>,length(Workers)},{<<"broker_queues">>,BrokerQueues},
     {<<"busy_agents">>,Busy}].
worker(N,W,Manager,A,Q) ->
    Budget=get(worker_budget),true=Budget>0,put(worker_budget,Budget-1),
    Original=rpc(N,supervisor,which_children,[W]),true=is_list(Original),3=length(Original),
    F=rpc(N,acdc_queue_worker_sup,fsm,[W]),L=rpc(N,acdc_queue_worker_sup,listener,[W]),
    Shared=rpc(N,acdc_queue_worker_sup,shared_queue,[W]),
    true=is_pid(F),true=is_pid(L),true=is_pid(Shared),
    {ok,#{account_id:=A,queue_id:=Q,state:=ready,listener:=L,manager:=Manager}}=
        rpc(N,acdc_queue_fsm,maintenance_state,[F,2000]),
    {ok,#{account_id:=A,queue_id:=Q,fsm:=F,manager:=Manager,shared_listener:=Shared,broker_queue:=Private}}=
        rpc(N,acdc_queue_listener,maintenance_state,[L,2000]),
    {ok,#{fsm:=F}}=rpc(N,acdc_queue_shared,maintenance_state,[Shared,2000]),
    Private=rpc(N,gen_listener,queue_name,[L]),
    SharedName=rpc(N,kapi_acdc_queue,shared_queue_name,[A,Q]),
    SharedName=rpc(N,gen_listener,queue_name,[Shared]),
    Names=listener_queues(N,L)++listener_queues(N,Shared),
    Original=rpc(N,supervisor,which_children,[W]),Names.
listener_queues(N,P) ->
    true=rpc(N,gen_listener,is_consuming,[P]),
    Q=rpc(N,gen_listener,queue_name,[P]),Other=rpc(N,gen_listener,other_queues,[P]),
    true=is_list(Other),true=length(Other)=<1000,
    true=lists:all(fun(B)->is_binary(B) andalso byte_size(B)>0 andalso byte_size(B)=<255 end,[Q|Other]),
    [Q|Other].
epoch(N) ->
    Pid=rpc(N,os,getpid,[]),Creation=rpc(N,erlang,system_info,[creation]),
    match=re:run(Pid,"^[0-9]+$",[{capture,none}]),true=is_integer(Creation),
    list_to_binary(Pid++"-"++integer_to_list(Creation)).
object(N,Pairs)->rpc(N,kz_json,from_list,[Pairs]).
hex_id(Id)->match=re:run(Id,<<"^[a-f0-9]{32}$">>,[{capture,none}]),ok.
rpc(N,M,F,A) ->
    Left=get(snapshot_deadline)-erlang:monotonic_time(millisecond),true=Left>0,
    rpc:call(N,M,F,A,min(5000,Left)).
