#!/usr/bin/env escript
%%! +S 1:1 +SDcpu 1 +SDio 1 +A 1 -setcookie unused_cluster_probe -start_epmd false -kernel logger_level none
%% Private stdout protocol: token mode MUST be captured, never printed/logged.
-mode(compile).
-compile(warnings_as_errors).
-include_lib("kernel/include/file.hrl").
-define(USER, <<"ef64a90c34d5491881a48c58f0d63271">>).
main(Args) ->
    try
        {ok,Host}=inet:gethostname(),
        true=lists:member(Host,["kz5-stage-kazoo-apps","kz5-stage-kazoo-apps-peer"]),
        {ok,Ifs}=inet:getifaddrs(),
        Ip=case Host of "kz5-stage-kazoo-apps"->{172,30,253,14}; _->{172,30,253,20} end,
        true=lists:any(fun({_,V})->lists:member({addr,Ip},V) end,Ifs),
        CookiePath="/etc/kazoo/.erlang.cookie",
        {ok,#file_info{type=regular,uid=0,links=1,mode=Mode}}=file:read_link_info(CookiePath),
        true=(Mode band 8#077)=:=0,
        {ok,C0}=file:read_file(CookiePath), C=string:trim(C0),
        match=re:run(C,<<"^[A-Za-z0-9_@.-]{16,256}$">>,[{capture,none}]),
        ok=application:set_env(kernel,inet_dist_use_interface,Ip),
        {ok,_}=net_kernel:start([list_to_atom("cluster_auth_probe_"++os:getpid()++"@"++Host),shortnames]),
        true=erlang:set_cookie(node(),binary_to_atom(C,utf8)),
        Node=list_to_atom("kazoo_apps@"++Host),
        {ok,Account}=rpc(Node,kapps_util,get_master_account_id,[]),
        Db=rpc(Node,kzs_util,format_account_db,[Account]),
        {ok,AccountDoc}=rpc(Node,kz_datamgr,open_doc,[Db,Account]),
        <<"installer-stage.invalid">>=rpc(Node,kz_json,get_ne_binary_value,[<<"realm">>,AccountDoc]),
        execute(Node,Account,Db,Args),net_kernel:stop()
    catch _:_ -> io:put_chars("ERROR isolated cluster auth probe refused\n"),halt(1)
    end.
rpc(N,M,F,A)->rpc:call(N,M,F,A,5000).
fixture(N,A,D)->
    Doc=case rpc(N,kz_datamgr,open_doc,[D,?USER]) of
        {ok,Existing}->Existing;
        {error,not_found}->
            New=rpc(N,kz_json,from_list,[[{<<"_id">>,?USER},{<<"pvt_type">>,<<"user">>},
                {<<"pvt_account_id">>,A},{<<"pvt_account_db">>,D},{<<"priv_level">>,<<"user">>},
                {<<"enabled">>,true},{<<"username">>,<<"kz5_cluster_auth_probe">>},
                {<<"first_name">>,<<"Cluster">>},{<<"last_name">>,<<"Acceptance">>},
                {<<"pvt_kz5_cluster_acceptance">>,true}]]),
            {ok,Saved}=rpc(N,kz_datamgr,save_doc,[D,New]),Saved
    end,
    true=rpc(N,kz_json,is_true,[<<"pvt_kz5_cluster_acceptance">>,Doc]),
    A=rpc(N,kz_json,get_ne_binary_value,[<<"pvt_account_id">>,Doc]),
    <<"user">>=rpc(N,kz_json,get_ne_binary_value,[<<"pvt_type">>,Doc]),
    <<"user">>=rpc(N,kz_json,get_ne_binary_value,[<<"priv_level">>,Doc]),Doc.
execute(N,A,D,["issue"])->
    _=fixture(N,A,D), Exp=rpc(N,erlang,system_time,[second])+300,
    {ok,Token}=rpc(N,kz_auth,create_token,[[{<<"account_id">>,A},{<<"owner_id">>,?USER},
        {<<"method">>,<<"cb_user_auth">>},{<<"exp">>,Exp}]]),
    {ok,_}=rpc(N,kz_auth,validate_token,[Token]),
    Doc=fixture(N,A,D),Rev=rpc(N,kz_doc,revision,[Doc]),
    io:format("{\"token\":\"~s\",\"account\":\"~s\",\"user\":\"~s\",\"revision\":\"~s\",\"expires\":~B}~n",
        [Token,A,?USER,Rev,Exp]);
execute(N,A,D,["revoke",Revision0])->
    Revision=list_to_binary(Revision0),match=re:run(Revision,<<"^[1-9][0-9]*-[a-f0-9]{32}$">>,[{capture,none}]),
    Doc=fixture(N,A,D),Revision=rpc(N,kz_doc,revision,[Doc]),
    Updated=rpc(N,kz_auth_identity,reset_doc_secret,[Doc]),
    {ok,Saved}=rpc(N,kz_datamgr,save_doc,[D,Updated]),
    Keys=[<<"_rev">>,<<"pvt_signature_secret">>],
    Before=rpc(N,kz_json,delete_keys,[Keys,Doc]),Before=rpc(N,kz_json,delete_keys,[Keys,Saved]),
    io:put_chars("PASS exact isolated user signature revoked; other fields unchanged\n");
execute(N,A,_D,["emit",Tag0,Marker0])->
    Tag=list_to_binary(Tag0),Marker=list_to_binary(Marker0),
    match=re:run(Tag,<<"^cluster-auth-[a-f0-9]{32}$">>,[{capture,none}]),
    true=lists:member(Marker,[<<"before-revocation">>,<<"after-revocation">>]),
    Contexts=rpc(N,blackhole_tracking,get_contexts_by_account_id,[A]),
    true=is_list(Contexts) andalso length(Contexts)=<100,
    [Ctx]=[X||X<-Contexts,rpc(N,bh_context,req_id,[X])=:=Tag],
    Pid=rpc(N,bh_context,websocket_pid,[Ctx]),true=is_pid(Pid) andalso node(Pid)=:=N,
    Data=rpc(N,kz_json,from_list,[[{<<"action">>,<<"event">>},{<<"name">>,<<"cluster-fixture">>},{<<"data">>,Marker}]]),
    ok=rpc(N,blackhole_data_emitter,send,[Pid,Data]),io:put_chars("PASS exact owned marker emitted\n").
