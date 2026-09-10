#!/usr/bin/env escript
%%! +S 1:1 +SDcpu 1 +SDio 1 +A 1 -setcookie unused_maintenance_restore -start_epmd false -kernel logger_level none
%% Local executor for a coordinator-owned, protected agent checkpoint.
%% The coordinator must authorize its journal phase and prove complete cluster
%% drain separately. This tool NEVER closes/releases a fence or retries writes.
-mode(compile).
-include_lib("kernel/include/file.hrl").
main(Args) ->
    try
        [Mode,Bind0,File]=Args,true=lists:member(Mode,["--validate","--restore"]),
        true=filename:pathtype(File)=:=absolute,private_parent(filename:dirname(File)),
        Bytes=private_file(File,8#600,4*1024*1024),
        {ok,Bind}=inet:parse_ipv4_address(Bind0),{ok,Ifs}=inet:getifaddrs(),true=has_ip(Ifs,Bind),
        {ok,Host}=inet:gethostname(),match=re:run(Host,"^[a-zA-Z0-9-]{1,63}$",[{capture,none}]),
        Cookie=private_file("/etc/kazoo/.erlang.cookie",8#400,1024),
        ok=application:set_env(kernel,inet_dist_use_interface,Bind),
        {ok,_}=net_kernel:start([list_to_atom("maintenance_restore_"++os:getpid()++"@"++Host),shortnames]),
        true=erlang:set_cookie(node(),binary_to_atom(string:trim(Cookie),utf8)),
        N=list_to_atom("kazoo_apps@"++Host),put(deadline,erlang:monotonic_time(millisecond)+120000),
        {ok,RemoteIfs}=rpc(N,inet,getifaddrs,[]),true=has_ip(RemoteIfs,Bind),
        Request=decode(N,Bytes),exact(Request,[<<"schema_version">>,<<"generation">>,<<"node">>,<<"expected_epoch">>,<<"agents">>]),
        1=maps:get(<<"schema_version">>,Request),Generation=maps:get(<<"generation">>,Request),hex(Generation,32),
        NodeName=atom_to_binary(N,utf8),NodeName=maps:get(<<"node">>,Request),
        Epoch=epoch(N),Epoch=maps:get(<<"expected_epoch">>,Request),Startup=startup(N),
        Agents=maps:get(<<"agents">>,Request),true=is_list(Agents),true=length(Agents)=<5000,
        lists:foreach(fun validate_agent/1,Agents),
        Ids=lists:sort([identity(A)||A<-Agents]),true=length(Ids)=:=length(lists:usort(Ids)),
        Workers=workers(N),Pairs=[observe(N,S)||S<-Workers],
        Ids=lists:sort([Id||{Id,_,_,_}<-Pairs]),
        %% Validate the entire target cohort and every uncached document before
        %% changing even one agent. Never filter out missing/restarting workers.
        lists:foreach(fun(A)->validate_revision(N,A) end,Agents),
        check_fence(N,Generation),Epoch=epoch(N),Startup=startup(N),Workers=workers(N),
        put(restored,0),put(step,preflight),
        case Mode of
            "--validate"->ok;
            "--restore"->lists:foreach(fun(A)->
                check_fence(N,Generation),Epoch=epoch(N),Startup=startup(N),
                Bytes=private_file(File,8#600,4*1024*1024),
                restore(N,A,Pairs),put(restored,get(restored)+1)
            end,Agents)
        end,
        check_fence(N,Generation),Epoch=epoch(N),Startup=startup(N),Workers=workers(N),
        Bytes=private_file(File,8#600,4*1024*1024),
        emit(N,#{<<"status">>=><<"PASS">>,<<"operation">>=>list_to_binary(Mode),
            <<"node">>=>NodeName,<<"epoch">>=>Epoch,<<"generation">>=>Generation,
            <<"agents_validated">>=>length(Agents),<<"agents_restored">>=>get(restored),
            <<"checkpoint_sha256">>=>digest(Bytes),<<"local_fence_verified">>=>true,
            <<"complete_cluster_restore_proven">>=>false}),net_kernel:stop()
    catch _:_ ->
        Count=case get(restored) of V when is_integer(V)->V;_->0 end,
        io:format("MAINTENANCE_RESTORE_REFUSED_OR_FAILED step=~p restored=~p; retain fence and checkpoint~n",[get(step),Count]),halt(1)
    end.
private_parent(Dir) ->
    {ok,#file_info{type=directory,uid=0,mode=M}}=file:read_link_info(Dir),true=(M band 8#777)=:=8#700,
    no_links(filename:split(Dir),"").
no_links([],_) -> ok;
no_links([Part|Rest],Prefix) ->
    P=filename:join(Prefix,Part),{ok,#file_info{type=directory}}=file:read_link_info(P),no_links(Rest,P).
private_file(File,Mode,Max) ->
    {ok,#file_info{type=regular,uid=0,links=1,mode=M,size=S}}=file:read_link_info(File),
    %% Existing installer cookies may be0400 or0600, never group/world-readable.
    true=case Mode of 8#400->lists:member(M band 8#777,[8#400,8#600]);_->(M band 8#777)=:=Mode end,
    true=S>0 andalso S=<Max,{ok,B}=file:read_file(File),true=byte_size(B)=:=S,B.
exact(M,Keys)->true=is_map(M),true=lists:sort(maps:keys(M))=:=lists:sort(Keys).
hex(V,Size)->true=is_binary(V),true=byte_size(V)=:=Size,match=re:run(V,<<"^[a-f0-9]+$">>,[{capture,none}]).
identity(A)->{maps:get(<<"account_id">>,A),maps:get(<<"agent_id">>,A)}.
validate_agent(A)->
    exact(A,[<<"account_id">>,<<"agent_id">>,<<"state">>,<<"pause_until_unix_ms">>,<<"queues">>,<<"document_revision">>]),
    {Account,User}=identity(A),hex(Account,32),hex(User,32),
    Qs=maps:get(<<"queues">>,A),true=is_list(Qs),true=length(Qs)=<10000,
    lists:foreach(fun(Q)->hex(Q,32) end,Qs),true=length(Qs)=:=length(lists:usort(Qs)),
    Revision=maps:get(<<"document_revision">>,A),true=is_binary(Revision),
    match=re:run(Revision,<<"^[1-9][0-9]*-[a-f0-9]{32}$">>,[{capture,none}]),
    case {maps:get(<<"state">>,A),maps:get(<<"pause_until_unix_ms">>,A)} of
        {<<"ready">>,0}->ok;{<<"paused">>,<<"infinity">>}->ok;
        {<<"paused">>,D} when is_integer(D),D>0->ok
    end.
validate_revision(N,A)->
    {Account,User}=identity(A),Db=rpc(N,kzs_util,format_account_db,[Account]),
    {ok,D}=rpc(N,kz_datamgr,open_doc,[Db,User]),<<"user">>=rpc(N,kz_doc,type,[D]),
    Account=rpc(N,kz_doc,account_id,[D]),Revision=maps:get(<<"document_revision">>,A),
    Revision=rpc(N,kz_json,get_ne_binary_value,[<<"_rev">>,D]).
workers(N)->Ws=rpc(N,acdc_agents_sup,workers,[]),true=is_list(Ws),true=length(Ws)=<5000,
    true=lists:all(fun is_pid/1,Ws),lists:sort(Ws).
observe(N,Sup)->
    F=rpc(N,acdc_agent_sup,fsm,[Sup]),L=rpc(N,acdc_agent_sup,listener,[Sup]),true=is_pid(F),true=is_pid(L),
    dispatch_drained(N,L),
    {ok,#{account_id:=A,agent_id:=U,listener:=L,state:=State}}=rpc(N,acdc_agent_fsm,maintenance_state,[F,2000]),
    true=State=:=ready orelse State=:=paused,
    {ok,#{account_id:=A,agent_id:=U,fsm:=F,queues:=Qs}}=rpc(N,acdc_agent_listener,maintenance_state,[L,2000]),
    bindings(N,L,A,Qs),dispatch_drained(N,L),{{A,U},Sup,F,L}.
bindings(N,L,A,Qs)->
    true=rpc(N,gen_listener,is_consuming,[L]),Bs=rpc(N,gen_listener,bindings,[L]),true=is_list(Bs),
    Bound=lists:usort([proplists:get_value(queue_id,P)||{<<"acdc_queue">>,P}<-Bs,
        proplists:get_value(account_id,P)=:=A,lists:member(member_connect_req,proplists:get_value(restrict_to,P,[]))]),
    true=Bound=:=lists:usort(Qs).
restore(N,A,Pairs)->
    Id={Account,User}=identity(A),{Id,Sup,F,L}=lists:keyfind(Id,1,Pairs),
    {Id,Sup,F,L}=observe(N,Sup),validate_revision(N,A),put(step,fsm_restore),
    Base=#{account_id=>Account,agent_id=>User},
    Cp=case {maps:get(<<"state">>,A),maps:get(<<"pause_until_unix_ms">>,A)} of
        {<<"ready">>,0}->Base#{state=>ready};
        {<<"paused">>,<<"infinity">>}->Base#{state=>paused,pause_until_unix_ms=>infinity};
        {<<"paused">>,D}->Base#{state=>paused,pause_until_unix_ms=>D}
    end,
    {ok,#{notifications_queued:=true}}=rpc(N,acdc_agent_fsm,maintenance_restore,[F,Cp,2000]),
    put(step,listener_restore),Qs=maps:get(<<"queues">>,A),
    {ok,#{queues:=Qs,bindings_queued:=true}}=rpc(N,acdc_agent_listener,maintenance_restore,[L,Base#{queues=>Qs},3000]),
    put(step,verify_restored),bindings(N,L,Account,Qs),{Id,Sup,F,L}=observe(N,Sup),
    {ok,Observed}=rpc(N,acdc_agent_fsm,maintenance_state,[F,2000]),
    case Cp of
        #{state:=ready}->ready=maps:get(state,Observed);
        #{pause_until_unix_ms:=infinity}->paused=maps:get(state,Observed),infinity=maps:get(pause_remaining_ms,Observed);
        #{pause_until_unix_ms:=Deadline}->
            case maps:get(state,Observed) of
                ready->true=Deadline=<erlang:system_time(millisecond);
                paused->Until=maps:get(pause_until_unix_ms,Observed),true=Until=<Deadline,true=Until>=Deadline-20
            end
    end,
    {ok,#{queues:=Qs}}=rpc(N,acdc_agent_listener,maintenance_state,[L,2000]),validate_revision(N,A).
check_fence(N,G)->
    Intent=decode(N,private_file("/var/lib/kazoo5-maintenance/fence/active.json",8#600,4096)),
    G=maps:get(<<"generation">>,Intent),true=lists:member(<<"kazoo-apps">>,maps:get(<<"roles">>,Intent)),
    P=open_port({spawn_executable,"/usr/bin/node"},[binary,exit_status,use_stdio,stderr_to_stdout,
        {args,["/usr/local/libexec/kazoo5-maintenance-fence","--verify",binary_to_list(G)]}]),
    R=decode(N,port_output(P,<<>>,erlang:monotonic_time(millisecond)+20000)),
    <<"closed">>=maps:get(<<"state">>,R),G=maps:get(<<"generation">>,R).
port_output(P,B,End)->
    Left=End-erlang:monotonic_time(millisecond),true=Left>0,
    receive
        {P,{data,D}}->true=byte_size(B)+byte_size(D)=<16384,port_output(P,<<B/binary,D/binary>>,End);
        {P,{exit_status,0}}->B;
        {P,{exit_status,_}}->error(fence_refused)
    after Left->port_close(P),error(fence_timeout) end.
startup(N)->{ok,#{initializer:=P,epoch:=E,revision:=R}=S}=rpc(N,acdc_init,maintenance_state,[2000]),
    true=is_pid(P),true=is_reference(E),true=is_integer(R) andalso R>=2,S.
epoch(N)->Pid=rpc(N,os,getpid,[]),Creation=rpc(N,erlang,system_info,[creation]),
    true=is_list(Pid),true=is_integer(Creation),list_to_binary(Pid++"-"++integer_to_list(Creation)).
decode(N,B)->rpc(N,kz_json,to_map,[rpc(N,kz_json,decode,[B])]).
emit(N,M)->J=rpc(N,kz_json,from_map,[M]),io:format("~s~n",[rpc(N,kz_json,encode,[J])]).
digest(B)->iolist_to_binary([io_lib:format("~2.16.0b",[X])||<<X>><=crypto:hash(sha256,B)]).
has_ip(Ifs,Ip)->lists:any(fun({_,V})->lists:member({addr,Ip},V) end,Ifs).
dispatch_drained(N,P) -> validate_dispatch(rpc(N,gen_server,call,[P,maintenance_dispatch_state,2000])).
validate_dispatch(#{pending_dispatches:=0,failed_dispatches:=0,
                    admission_fence_proven:=false,complete_cluster_drain_proven:=false}=S) when map_size(S)=:=4 -> ok.
rpc(N,M,F,A)->End=get(deadline),Left=End-erlang:monotonic_time(millisecond),true=Left>0,
    rpc:call(N,M,F,A,min(5000,Left)).
