#!/usr/bin/env escript
%%! +S 1:1 +SDcpu 1 +SDio 1 +A 1 -setcookie unused_queue_owner -start_epmd false -kernel logger_level none
%% Read-only: does a queue worker on THIS applications node currently hold the
%% given caller's member call (and therefore its unacknowledged broker
%% delivery)? RabbitMQ gives each queued call to a worker on either node; a
%% partition only strands, and later redelivers, a call owned by the partitioned
%% node. Fixed synthetic company and queue only. No state is changed.
-mode(compile).
-include_lib("kernel/include/file.hrl").
-define(ACCOUNT, <<"45e827067baf078029d0ca16a489fa8a">>).
main([Queue0, Caller0]) ->
    try
        {ok,H}=inet:gethostname(),
        Ip=case H of "kz5-stage-kazoo-apps"->{172,30,253,14}; "kz5-stage-kazoo-apps-peer"->{172,30,253,20} end,
        {ok,Ifs}=inet:getifaddrs(),true=lists:any(fun({_,V})->lists:member({addr,Ip},V) end,Ifs),
        {ok,#file_info{type=regular,uid=0,links=1,mode=M}}=file:read_link_info("/etc/kazoo/.erlang.cookie"),
        true=(M band 8#077)=:=0,{ok,C}=file:read_file("/etc/kazoo/.erlang.cookie"),
        ok=application:set_env(kernel,inet_dist_use_interface,Ip),
        {ok,_}=net_kernel:start([list_to_atom("queue_owner_probe_"++os:getpid()++"@"++H),shortnames]),
        true=erlang:set_cookie(node(),binary_to_atom(string:trim(C),utf8)),
        N=list_to_atom("kazoo_apps@"++H),
        Queue=list_to_binary(Queue0),Caller=list_to_binary(Caller0),
        match=re:run(Queue,<<"^[a-f0-9]{32}$">>,[{capture,none}]),
        match=re:run(Caller,<<"^[A-Za-z0-9@.:_-]{1,128}$">>,[{capture,none}]),
        Sup=rpc(N,acdc_queues_sup,find_queue_supervisor,[?ACCOUNT,Queue]),true=is_pid(Sup),
        Workers=rpc(N,acdc_queue_workers_sup,workers,[rpc(N,acdc_queue_sup,workers_sup,[Sup])]),
        true=is_list(Workers),
        States=[worker(N,W) || W <- Workers],
        Owns=[S || {S,Id} <- States, Id=:=Caller],
        io:format("{\"workers\":~b,\"owns\":~s,\"state\":\"~s\"}~n",
                  [length(States),atom_to_list(Owns=/=[]),case Owns of [S|_]->S; []-><<>> end]),
        net_kernel:stop()
    catch _:_ -> io:put_chars("QUEUE_OWNER_PROBE_FAILED\n"),halt(1) end.

worker(N,W) ->
    Status=rpc(N,acdc_queue_fsm,status,[rpc(N,acdc_queue_worker_sup,fsm,[W])]),true=is_list(Status),
    State=first([<<"state">>,state],Status),Id=first([<<"call_id">>,call_id],Status),
    {case is_binary(State) of true->State; false-><<"unknown">> end,Id}.
first([K|Ks],P) -> case proplists:get_value(K,P) of undefined->first(Ks,P); V->V end;
first([],_) -> undefined.
rpc(N,M,F,A)->rpc:call(N,M,F,A,5000).
