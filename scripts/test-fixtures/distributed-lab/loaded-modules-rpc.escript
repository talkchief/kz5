#!/usr/bin/env escript
%%! +S 1:1 +SDcpu 1 +SDio 1 +A 1 -setcookie unused_module_probe -start_epmd false -kernel logger_level none
%% Read-only: does the running lab apps VM execute the BEAMs that are on disk,
%% and do those BEAMs contain the expected exports? A passed build alone does
%% not prove the restarted VM loaded it. No application state is read.
-mode(compile).
-include_lib("kernel/include/file.hrl").
-define(CHECKS, [{acdc_queue_fsm, []}
                ,{acdc_queue_manager, []}
                ,{acdc_queue_listener, []}
                ,{kapi_acdc_queue, []}
                ]).
main([]) ->
    try
        {ok,H}=inet:gethostname(),
        Ip=case H of "kz5-stage-kazoo-apps"->{172,30,253,14}; "kz5-stage-kazoo-apps-peer"->{172,30,253,20} end,
        {ok,#file_info{type=regular,uid=0,links=1,mode=M}}=file:read_link_info("/etc/kazoo/.erlang.cookie"),
        true=(M band 8#077)=:=0,{ok,C}=file:read_file("/etc/kazoo/.erlang.cookie"),
        ok=application:set_env(kernel,inet_dist_use_interface,Ip),
        {ok,_}=net_kernel:start([list_to_atom("module_probe_"++os:getpid()++"@"++H),shortnames]),
        true=erlang:set_cookie(node(),binary_to_atom(string:trim(C),utf8)),
        N=list_to_atom("kazoo_apps@"++H),
        Rows=[row(N,Mod) || {Mod,_} <- ?CHECKS],
        Settled=lists:member(<<"Settled-Call-ID">>,
                             strings(rpc(N,kapi_acdc_queue,module_info,[attributes]),N)),
        io:format("~s~n",[json(H,Rows,Settled)]),
        net_kernel:stop(),
        case lists:all(fun({_,_,_,Same}) -> Same end,Rows) of true->halt(0); false->halt(2) end
    catch _:_ -> io:put_chars("MODULE_PROBE_FAILED\n"),halt(1) end.

row(N,Mod) ->
    Path=rpc(N,code,which,[Mod]),true=is_list(Path),
    {ok,Bin}=rpc(N,file,read_file,[Path]),
    {ok,{Mod,Disk}}=rpc(N,beam_lib,md5,[Bin]),
    Loaded=rpc(N,Mod,module_info,[md5]),
    {Mod,Path,hex(Loaded),Loaded=:=Disk}.

%% The optional header list is a macro, not an attribute; ask the validator.
strings(_,N) ->
    Base=[{<<"Account-ID">>,<<"a">>},{<<"Queue-ID">>,<<"q">>},{<<"Call-ID">>,<<"c">>},{<<"Msg-ID">>,<<"m">>}
          |rpc(N,kz_api,default_headers,[<<"probe">>,<<"queue">>,<<"member_remove">>,<<"acdc">>,<<"1">>])],
    case {rpc(N,kapi_acdc_queue,queue_member_remove_v,[[{<<"Settled-Call-ID">>,<<"c">>}|Base]]),
          rpc(N,kapi_acdc_queue,queue_member_remove_v,[[{<<"Settled-Call-ID">>,true}|Base]])} of
        {true,false} -> [<<"Settled-Call-ID">>];
        _ -> []
    end.

hex(B) -> lists:flatten([io_lib:format("~2.16.0b",[X]) || <<X>> <= B]).
json(H,Rows,Settled) ->
    Mods=string:join([io_lib:format("{\"module\":\"~s\",\"path\":\"~s\",\"loaded_md5\":\"~s\",\"matches_disk\":~s}",
                                    [M,P,X,S]) || {M,P,X,S} <- Rows],","),
    io_lib:format("{\"host\":\"~s\",\"settled_header_enforced\":~s,\"modules\":[~s]}",[H,Settled,Mods]).
rpc(N,M,F,A)->rpc:call(N,M,F,A,8000).
