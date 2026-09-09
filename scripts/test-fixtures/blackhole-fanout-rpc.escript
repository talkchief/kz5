#!/usr/bin/env escript
%%! +S 1:1 +SDcpu 1 +SDio 1 +A 1 -setcookie unused_fanout_probe -start_epmd false -kernel logger_level none
%% Fixed development fixture only. Real AMQP publication, no socket injection.
-mode(compile).
-compile(warnings_as_errors).
-include_lib("kernel/include/file.hrl").
-define(ACCOUNT, <<"8310dc3170a18de37f205d0da172df65">>).
main(Args) ->
    try
        put(phase,admission),
        {ok,Status}=file:read_file("/proc/self/status"),
        match=re:run(Status,<<"^Uid:[ \\t]+0[ \\t]+0[ \\t]+0[ \\t]+0$">>,[multiline,{capture,none}]),
        {ok,Ifs}=inet:getifaddrs(),true=lists:any(fun({_,V})->lists:member({addr,{10,1,0,44}},V) end,Ifs),
        {ok,#file_info{type=regular,uid=0,links=1,mode=M}}=file:read_link_info("/etc/kazoo/.erlang.cookie"),
        true=(M band 8#077)=:=0,{ok,C}=file:read_file("/etc/kazoo/.erlang.cookie"),
        {ok,H}=inet:gethostname(),N=list_to_atom("kazoo_apps@"++H),
        ok=application:set_env(kernel,inet_dist_use_interface,{127,0,0,1}),
        {ok,_}=net_kernel:start([list_to_atom("fanout_probe_"++os:getpid()++"@"++H),shortnames]),
        true=erlang:set_cookie(node(),binary_to_atom(string:trim(C),utf8)),
        put(phase,fixture_identity),
        Db=rpc(N,kzs_util,format_account_db,[?ACCOUNT]),{ok,D}=rpc(N,kz_datamgr,open_doc,[Db,?ACCOUNT]),
        Realm=rpc(N,kz_json,get_ne_binary_value,[<<"realm">>,D]),
        match=re:run(Realm,<<"^acceptance-[a-f0-9]{12}\\.invalid$">>,[{capture,none}]),
        execute(N,Args),net_kernel:stop()
    catch _:_ -> io:format("Scoped fanout helper refused: ~p~n",[get(phase)]),halt(1) end.
rpc(N,M,F,A)->rpc:call(N,M,F,A,5000).
execute(N,["issue"]) ->
    %% One bounded fixture token keeps the same sockets alive for the soak.
    %% Native Blackhole intentionally requires reconnect to change a token.
    put(phase,issue),Expiry=rpc(N,erlang,system_time,[second])+2700,
    {ok,Token}=rpc(N,kz_auth,create_token,[[{<<"account_id">>,?ACCOUNT},{<<"exp">>,Expiry}]]),
    {ok,_}=rpc(N,kz_auth,validate_token,[Token]),
    io:format("{\"token\":\"~s\",\"expires\":~B}~n",[Token,Expiry]);
execute(N,["sample"]) ->
    put(phase,sample),
    Memory=rpc(N,erlang,memory,[total]),Processes=rpc(N,erlang,system_info,[process_count]),
    io:format("{\"vm_bytes\":~B,\"processes\":~B}~n",[Memory,Processes]);
execute(N,["publish",Tag0,First0,Count0]) ->
    put(phase,publish_admission),
    Tag=list_to_binary(Tag0),match=re:run(Tag,<<"^[a-f0-9]{32}$">>,[{capture,none}]),
    First=list_to_integer(First0),Count=list_to_integer(Count0),
    true=First>=1 andalso Count>=1 andalso Count=<60 andalso First+Count-1=<3600,
    CallId = <<"fanout-",Tag/binary>>,
    lists:foreach(fun(I)->
        CCV=rpc(N,kz_json,from_list,[[{<<"Account-ID">>,?ACCOUNT},
            {<<"KZ5-Fixture-Sequence">>,I},{<<"KZ5-Fixture-Sent-Ms">>,erlang:system_time(millisecond)}]]),
        Headers=rpc(N,kz_api,default_headers,[<<"call_event">>,<<"CHANNEL_HOLD">>,
            <<"kz5-fanout-acceptance">>,<<"1">>]),
        Props=[{<<"Call-ID">>,CallId},{<<"Custom-Channel-Vars">>,CCV},
            {<<"Msg-ID">>,rpc(N,kz_binary,rand_hex,[16])}|Headers],
        put(phase,event_validation),true=rpc(N,kapi_call,event_v,[Props]),
        put(phase,broker_publication),
        ok=rpc(N,kz_amqp_worker,cast,[Props,fun kapi_call:publish_event/1]),
        timer:sleep(500)
    end,lists:seq(First,First+Count-1)),
    io:format("{\"published\":~B,\"first\":~B}~n",[Count,First]).
