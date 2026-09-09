#!/usr/bin/env escript
%%! +S 1:1 +SDcpu 1 +SDio 1 +A 1 -setcookie unused_stream_probe -start_epmd false -kernel logger_level none
%% Dev44 fixture-only WSS transport proof. Token stdout is private protocol.
-mode(compile).
-compile(warnings_as_errors).
-include_lib("kernel/include/file.hrl").
-define(ACCOUNT, <<"8310dc3170a18de37f205d0da172df65">>).
main(Args) ->
    try
        true = Args =:= ["issue"] orelse (length(Args) =:= 3 andalso
            lists:member(hd(Args), ["emit", "overflow"])),
        {ok, Status} = file:read_file("/proc/self/status"),
        match = re:run(Status, <<"^Uid:[ \\t]+0[ \\t]+0[ \\t]+0[ \\t]+0$">>, [multiline,{capture,none}]),
        {ok, Ifs} = inet:getifaddrs(),
        true = lists:any(fun({_, V}) -> lists:member({addr,{10,1,0,44}},V) end, Ifs),
        CookiePath = "/etc/kazoo/.erlang.cookie",
        {ok,#file_info{type=regular,uid=0,links=1,mode=Mode,size=Size}} = file:read_link_info(CookiePath),
        true = (Mode band 8#077) =:= 0 andalso Size >= 16 andalso Size =< 256,
        {ok, Cookie0} = file:read_file(CookiePath), Cookie = string:trim(Cookie0),
        match = re:run(Cookie, <<"^[A-Za-z0-9_@.-]+$">>, [{capture,none}]),
        {ok, Host} = inet:gethostname(), Node = list_to_atom("kazoo_apps@" ++ Host),
        ok = application:set_env(kernel, inet_dist_use_interface, {127,0,0,1}),
        {ok,_} = net_kernel:start([list_to_atom("stream_probe_" ++ os:getpid() ++ "@" ++ Host),shortnames]),
        true = erlang:set_cookie(node(), binary_to_atom(Cookie,utf8)),
        execute(Node, Args), net_kernel:stop()
    catch _:_ -> io:put_chars("ERROR scoped stream probe refused or unverified\n"), halt(1)
    end.
rpc(Node,M,F,A) -> rpc:call(Node,M,F,A,3000).
execute(Node,["issue"]) ->
    Db = rpc(Node,kzs_util,format_account_db,[?ACCOUNT]),
    {ok,AccountDoc} = rpc(Node,kz_datamgr,open_doc,[Db,?ACCOUNT]),
    true = rpc(Node,kz_auth_identity,has_doc_secret,[AccountDoc]),
    Expiry = rpc(Node,erlang,system_time,[second]) + 15,
    {ok,Token} = rpc(Node,kz_auth,create_token,[[{<<"account_id">>,?ACCOUNT},{<<"exp">>,Expiry}]]),
    {ok,_} = rpc(Node,kz_auth,validate_token,[Token]),
    %% Never run this mode uncaptured in a terminal or log.
    io:format("{\"token\":\"~s\",\"expires\":~B}~n",[Token,Expiry]);
execute(Node,[Operation,Tag0,Marker0]) ->
    Tag = list_to_binary(Tag0), Marker = list_to_binary(Marker0),
    match = re:run(Tag, <<"^streamguard-[a-f0-9]{32}$">>, [{capture,none}]),
    true = lists:member(Marker,[<<"before-expiry">>,<<"after-expiry">>,<<"overflow">>]),
    Contexts = rpc(Node,blackhole_tracking,get_contexts_by_account_id,[?ACCOUNT]),
    true = is_list(Contexts) andalso length(Contexts) =< 100,
    [Context] = [C || C <- Contexts, rpc(Node,bh_context,req_id,[C]) =:= Tag],
    Pid = rpc(Node,bh_context,websocket_pid,[Context]),
    true = is_pid(Pid) andalso node(Pid) =:= Node,
    Data = rpc(Node,kz_json,from_list,[[{<<"action">>,<<"event">>},{<<"name">>,<<"fixture">>},
        {<<"data">>,Marker}]]),
    case Operation of
        "emit" -> ok = rpc(Node,blackhole_data_emitter,send,[Pid,Data]);
        "overflow" ->
            <<"overflow">> = Marker,
            %% Bounded mailbox surge for this exact owned socket only.
            lists:foreach(fun(_) -> Pid ! {send_data,Data} end, lists:seq(1,100))
    end,
    io:put_chars("PASS exact owned socket injected\n").
