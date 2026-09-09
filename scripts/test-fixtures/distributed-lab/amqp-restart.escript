#!/usr/bin/env escript
%%! +S 1:1 +SDcpu 1 +SDio 1 +A 1 -setcookie unused_probe -start_epmd false -kernel logger_level none
%% Only the original private lab controller16; no credential output.
-mode(compile).
-include_lib("kernel/include/file.hrl").
main([]) ->
    try
        {ok,"kz5-stage-ecallmgr"}=inet:gethostname(),
        {ok,Ifs}=inet:getifaddrs(),
        true=lists:any(fun({_,V})->lists:member({addr,{172,30,253,16}},V) end,Ifs),
        {ok,#file_info{type=regular,uid=0,links=1,mode=M}}=file:read_link_info("/etc/kazoo/.erlang.cookie"),
        true=(M band 8#077)=:=0,
        {ok,C}=file:read_file("/etc/kazoo/.erlang.cookie"),
        ok=application:set_env(kernel,inet_dist_use_interface,{172,30,253,16}),
        {ok,_}=net_kernel:start([list_to_atom("amqp_restart_probe_"++os:getpid()++"@kz5-stage-ecallmgr"),shortnames]),
        true=erlang:set_cookie(node(),binary_to_atom(string:trim(C),utf8)),
        run('ecallmgr@kz5-stage-ecallmgr'),net_kernel:stop()
    catch _:_ -> io:put_chars("FAIL isolated supervised AMQP replacement\n"),halt(1) end.
rpc(N,M,F,A) -> rpc:call(N,M,F,A,5000).
run(N) ->
    true=rpc(N,erlang,function_exported,[kz_amqp_connection,start_link,2]),
    {ok,A}=rpc(N,kapps_util,get_master_account_id,[]),
    Db=rpc(N,kzs_util,format_account_db,[A]),
    {ok,D}=rpc(N,kz_datamgr,open_doc,[Db,A]),
    <<"installer-stage.invalid">>=rpc(N,kz_json,get_ne_binary_value,[<<"realm">>,D]),
    OS=rpc(N,os,getpid,[]),
    {P,Zone,Tags,Hidden}=snapshot(N),
    true=rpc(N,kz_amqp_connections,is_available,[]),
    true=rpc(N,erlang,exit,[P,kill]),
    New=wait(N,P,Zone,Tags,Hidden,100),
    OS=rpc(N,os,getpid,[]),
    io:format("PASS supervised replacement old=~p new=~p same_vm=true zone_preserved=true broker_available=true~n",[P,New]).
snapshot(N) ->
    [R]=rpc(N,kz_amqp_connections,connections,[]),
    10=tuple_size(R),kz_amqp_connections=element(1,R),
    true=element(5,R),local=element(7,R),false=element(10,R),
    #{host:=<<"172.30.253.12">>}=uri_string:parse(element(4,R)),
    {element(2,R),element(7,R),element(9,R),element(10,R)}.
wait(_,_,_,_,_,0) -> error(replacement_not_ready);
wait(N,Old,Z,T,H,Count) ->
    Result=try snapshot(N) catch _:_ -> unavailable end,
    case Result of
        {P,Z,T,H} when P =/= Old ->
            true=rpc(N,kz_amqp_connections,is_available,[]),P;
        _ -> timer:sleep(200),wait(N,Old,Z,T,H,Count-1)
    end.
