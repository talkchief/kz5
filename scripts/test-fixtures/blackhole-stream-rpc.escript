#!/usr/bin/env escript
%%! +S 1:1 +SDcpu 1 +SDio 1 +A 1 -setcookie unused_stream_probe -start_epmd false -kernel logger_level none
%% Dev44 fixture-only WSS transport proof. Token stdout is private protocol.
-mode(compile).
-compile(warnings_as_errors).
-include_lib("kernel/include/file.hrl").
-define(ACCOUNT, <<"8310dc3170a18de37f205d0da172df65">>).
-define(USER, <<"10cbff5eb98c9c7e4231b7156b15a3fd">>).
main(Args) ->
    try
        put(phase, local_scope),
        true = Args =:= ["issue"] orelse Args =:= ["issue-load"] orelse Args =:= ["issue-user"] orelse (length(Args) =:= 3 andalso
            lists:member(hd(Args), ["emit", "overflow", "revoke-user", "transport-load"])),
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
        put(phase, connected), execute(Node, Args), net_kernel:stop()
    catch _:_ -> io:format("ERROR scoped stream probe refused: ~p~n",[get(phase)]), halt(1)
    end.
rpc(Node,M,F,A) -> rpc:call(Node,M,F,A,3000).
execute(Node,["issue-user"]) ->
    put(phase, fixture_user),
    Db = rpc(Node,kzs_util,format_account_db,[?ACCOUNT]),
    {ok,Doc} = rpc(Node,kz_datamgr,open_doc,[Db,?USER]),
    <<"user">> = rpc(Node,kz_json,get_ne_binary_value,[<<"pvt_type">>,Doc]),
    <<"user">> = rpc(Node,kz_json,get_ne_binary_value,[<<"priv_level">>,Doc,<<"user">>]),
    true = rpc(Node,kz_json,is_true,[<<"enabled">>,Doc,true]),
    Expiry = rpc(Node,erlang,system_time,[second]) + 60,
    {ok,Token} = rpc(Node,kz_auth,create_token,[[{<<"account_id">>,?ACCOUNT},
        {<<"owner_id">>,?USER},{<<"method">>,<<"cb_user_auth">>},{<<"exp">>,Expiry}]]),
    {ok,_} = rpc(Node,kz_auth,validate_token,[Token]),
    {ok,Current} = rpc(Node,kz_datamgr,open_doc,[Db,?USER]),
    Revision = rpc(Node,kz_doc,revision,[Current]),
    io:format("{\"token\":\"~s\",\"expires\":~B,\"user_revision\":\"~s\"}~n",[Token,Expiry,Revision]);
execute(Node,["revoke-user",Tag0,Revision0]) ->
    put(phase, exact_fixture_revocation),
    Tag = list_to_binary(Tag0), Revision = list_to_binary(Revision0),
    match = re:run(Tag, <<"^streamguard-[a-f0-9]{32}$">>, [{capture,none}]),
    match = re:run(Revision, <<"^[1-9][0-9]*-[a-f0-9]{32}$">>, [{capture,none}]),
    Contexts = rpc(Node,blackhole_tracking,get_contexts_by_account_id,[?ACCOUNT]),
    true = is_list(Contexts) andalso length(Contexts) =< 100,
    [Context] = [C || C <- Contexts, rpc(Node,bh_context,req_id,[C]) =:= Tag],
    Token = rpc(Node,bh_context,auth_token,[Context]),
    {ok,Claims} = rpc(Node,kz_auth,validate_token,[Token]),
    ?ACCOUNT = rpc(Node,kz_json,get_ne_binary_value,[<<"account_id">>,Claims]),
    ?USER = rpc(Node,kz_json,get_ne_binary_value,[<<"owner_id">>,Claims]),
    Db = rpc(Node,kzs_util,format_account_db,[?ACCOUNT]),
    {ok,Doc} = rpc(Node,kz_datamgr,open_doc,[Db,?USER]),
    Revision = rpc(Node,kz_doc,revision,[Doc]),
    <<"user">> = rpc(Node,kz_json,get_ne_binary_value,[<<"pvt_type">>,Doc]),
    <<"user">> = rpc(Node,kz_json,get_ne_binary_value,[<<"priv_level">>,Doc,<<"user">>]),
    Updated = rpc(Node,kz_auth_identity,reset_doc_secret,[Doc]),
    {ok,Saved} = rpc(Node,kz_datamgr,save_doc,[Db,Updated]),
    PublicBefore = rpc(Node,kz_json,delete_keys,[[<<"_rev">>,<<"pvt_signature_secret">>],Doc]),
    PublicBefore = rpc(Node,kz_json,delete_keys,[[<<"_rev">>,<<"pvt_signature_secret">>],Saved]),
    io:put_chars("PASS exact fixture user signature rotated by revision CAS; other fields unchanged\n");
execute(Node,[Issue]) when Issue =:= "issue"; Issue =:= "issue-load" ->
    put(phase, fixture_document),
    Db = rpc(Node,kzs_util,format_account_db,[?ACCOUNT]),
    {ok,_AccountDoc} = rpc(Node,kz_datamgr,open_doc,[Db,?ACCOUNT]),
    %% Normal signing may initialize only this fixed acceptance account's
    %% identity secret. Never reset an existing secret or touch another account.
    put(phase, issue_token),
    TTL = case Issue of "issue-load" -> 120; "issue" -> 15 end,
    Expiry = rpc(Node,erlang,system_time,[second]) + TTL,
    {ok,Token} = rpc(Node,kz_auth,create_token,[[{<<"account_id">>,?ACCOUNT},{<<"exp">>,Expiry}]]),
    put(phase, validate_token), {ok,_} = rpc(Node,kz_auth,validate_token,[Token]),
    %% Never run this mode uncaptured in a terminal or log.
    io:format("{\"token\":\"~s\",\"expires\":~B}~n",[Token,Expiry]);
execute(Node,["transport-load",Tag0,"bounded"]) ->
    put(phase, exact_slow_socket),
    Tag = list_to_binary(Tag0),
    match = re:run(Tag, <<"^streamguard-[a-f0-9]{32}$">>, [{capture,none}]),
    Contexts = rpc(Node,blackhole_tracking,get_contexts_by_account_id,[?ACCOUNT]),
    true = is_list(Contexts) andalso length(Contexts) =< 100,
    [Context] = [C || C <- Contexts, rpc(Node,bh_context,req_id,[C]) =:= Tag],
    Pid = rpc(Node,bh_context,websocket_pid,[Context]),
    true = is_pid(Pid) andalso node(Pid) =:= Node,
    Token = rpc(Node,bh_context,auth_token,[Context]),
    {ok,Claims} = rpc(Node,kz_auth,validate_token,[Token]),
    ?ACCOUNT = rpc(Node,kz_json,get_ne_binary_value,[<<"account_id">>,Claims]),
    %% Pace through the real emitter: never suspend a process or inject a
    %% mailbox burst. Network receive starvation is imposed by the client.
    Data = rpc(Node,kz_json,from_list,[[{<<"action">>,<<"event">>},
        {<<"name">>,<<"transport-fixture">>},{<<"data">>,binary:copy(<<"s">>,262144)}]]),
    Start = erlang:monotonic_time(millisecond),
    {Sent,Memory,Queue} = transport_load(Node,Pid,Data,0,0,0),
    Gone = await_gone(Node,Pid,100),
    io:format("{\"sent\":~B,\"payload_bytes\":262144,\"peak_process_bytes\":~B,"
              "\"peak_mailbox\":~B,\"socket_process_gone\":~s,\"elapsed_ms\":~B}~n",
              [Sent,Memory,Queue,atom_to_list(Gone),erlang:monotonic_time(millisecond)-Start]);
execute(Node,[Operation,Tag0,Marker0]) ->
    Tag = list_to_binary(Tag0), Marker = list_to_binary(Marker0),
    match = re:run(Tag, <<"^streamguard-[a-f0-9]{32}$">>, [{capture,none}]),
    true = lists:member(Marker,[<<"before-expiry">>,<<"after-expiry">>,<<"overflow">>,<<"after-revocation">>]),
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

transport_load(_Node,_Pid,_Data,128,Memory,Queue) -> {128,Memory,Queue};
transport_load(Node,Pid,Data,Count,Memory,Queue) ->
    case rpc(Node,erlang,process_info,[Pid,[memory,message_queue_len]]) of
        undefined -> {Count,Memory,Queue};
        [{memory,M},{message_queue_len,Q}] ->
            ok = rpc(Node,blackhole_data_emitter,send,[Pid,Data]),
            timer:sleep(50),
            transport_load(Node,Pid,Data,Count+1,max(Memory,M),max(Queue,Q))
    end.
await_gone(_Node,_Pid,0) -> false;
await_gone(Node,Pid,Left) ->
    case rpc(Node,erlang,is_process_alive,[Pid]) of
        false -> true;
        true -> timer:sleep(100), await_gone(Node,Pid,Left-1)
    end.
