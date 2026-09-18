#!/usr/bin/env escript
%%! +S 1:1 +SDcpu 1 +SDio 1 +A 1 -setcookie unused_callback_probe -start_epmd false -kernel logger_level none
%% Injected duplicate callback registration against the lab's real datastore, in
%% the original lab's exact synthetic company. The ticket is never activated, so
%% no call is placed, and "cleanup" cancels and removes it.
%%   create CALLID AT COUNT   COUNT concurrent identical registrations enqueued at AT
%%   conflict CALLID AT       the same caller identity with another number
%%   cleanup CALLID AT        cancel and delete the probe ticket
-mode(compile).
-include_lib("kernel/include/file.hrl").
-define(ACCOUNT, <<"45e827067baf078029d0ca16a489fa8a">>).
-define(REALM, <<"acceptance-724fa76c8821.invalid">>).
main(Args) ->
    try
        [Mode,CallId0,At0|Rest]=Args,
        {ok,H}=inet:gethostname(),
        Ip=case H of "kz5-stage-kazoo-apps"->{172,30,253,14}; "kz5-stage-kazoo-apps-peer"->{172,30,253,20} end,
        {ok,Ifs}=inet:getifaddrs(),true=lists:any(fun({_,V})->lists:member({addr,Ip},V) end,Ifs),
        {ok,#file_info{type=regular,uid=0,links=1,mode=M}}=file:read_link_info("/etc/kazoo/.erlang.cookie"),
        true=(M band 8#077)=:=0,{ok,C}=file:read_file("/etc/kazoo/.erlang.cookie"),
        ok=application:set_env(kernel,inet_dist_use_interface,Ip),
        {ok,_}=net_kernel:start([list_to_atom("callback_duplicate_probe_"++os:getpid()++"@"++H),shortnames]),
        true=erlang:set_cookie(node(),binary_to_atom(string:trim(C),utf8)),
        N=list_to_atom("kazoo_apps@"++H),CallId=list_to_binary(CallId0),
        match=re:run(CallId,<<"^duplicate-probe-[a-f0-9]{16}$">>,[{capture,none}]),
        Db=rpc(N,kzs_util,format_account_db,[?ACCOUNT]),
        {ok,A}=rpc(N,kz_datamgr,open_doc,[Db,?ACCOUNT]),
        ?REALM=rpc(N,kz_json,get_value,[<<"realm">>,A]),
        {ok,[First|_]}=rpc(N,kz_datamgr,get_results,[Db,<<"queues/crossbar_listing">>,[]]),
        Queue=rpc(N,kz_doc,id,[First]),
        match=re:run(Queue,<<"^[a-f0-9]{32}$">>,[{capture,none}]),
        %% The driver supplies one enqueue time (Unix seconds) for every node: it is part of the caller's identity.
        At=list_to_integer(At0)+62167219200,Now=rpc(N,kz_time,now_s,[]),true=At=<Now andalso At>Now-600,
        Out=case {Mode,Rest} of
            {"create",[Count0]} ->
                Count=list_to_integer(Count0),true=Count>=2 andalso Count=<64,
                Keys=[rpc:async_call(N,acdc_callback_store,create,[?ACCOUNT,Queue,CallId,registration(N,At,<<"1001">>),authority(N)])
                      || _ <- lists:seq(1,Count)],
                Results=[rpc:yield(K) || K <- Keys],
                Docs=[D || {ok,D} <- Results],
                [{<<"requested">>,Count},{<<"accepted">>,length(Docs)},
                 {<<"ids">>,lists:usort([rpc(N,kz_doc,id,[D]) || D <- Docs])},
                 {<<"created">>,lists:usort([rpc(N,kz_json,get_value,[<<"pvt_created">>,D]) || D <- Docs])},
                 {<<"other">>,[list_to_binary(io_lib:format("~p",[R])) || R <- Results, not is_ok(R)]}
                 |stored(N,Queue,CallId)];
            {"conflict",[]} ->
                R=rpc(N,acdc_callback_store,create,[?ACCOUNT,Queue,CallId,registration(N,At,<<"1002">>),authority(N)]),
                [{<<"answer">>,list_to_binary(io_lib:format("~p",[R]))}|stored(N,Queue,CallId)];
            {"cleanup",[]} ->
                {ok,Doc}=rpc(N,acdc_callback_store,find,[?ACCOUNT,Queue,CallId]),
                Id=rpc(N,kz_doc,id,[Doc]),
                {ok,Cancelled}=rpc(N,acdc_callback_store,cancel,[?ACCOUNT,Queue,Id]),
                <<"cancelled">>=rpc(N,kz_json,get_value,[<<"status">>,Cancelled]),
                {ok,_}=rpc(N,kz_datamgr,del_doc,[Db,Cancelled]),
                {error,not_found}=rpc(N,kz_datamgr,open_doc,[Db,Id]),
                [{<<"removed">>,Id}]
        end,
        J=rpc(N,kz_json,from_list,[[{<<"queue">>,Queue}|Out]]),
        io:format("~s~n",[rpc(N,kz_json,encode,[J])]),net_kernel:stop()
    catch _:Reason ->
        %% The reason can name documents, so it is shown only on request.
        _=[io:format(standard_error,"~P~n",[Reason,12]) || os:getenv("KZ5_PROBE_DEBUG")=:="1"],
        io:put_chars("CALLBACK_DUPLICATE_PROBE_FAILED\n"),halt(1) end.
is_ok({ok,_})->true; is_ok(_)->false.
%% What the datastore holds afterwards: a first revision means nothing overwrote it.
stored(N,Queue,CallId) ->
    {ok,Doc}=rpc(N,acdc_callback_store,find,[?ACCOUNT,Queue,CallId]),
    [{<<"stored_id">>,rpc(N,kz_doc,id,[Doc])},{<<"stored_revision">>,rpc(N,kz_doc,revision,[Doc])},
     {<<"stored_status">>,rpc(N,kz_json,get_value,[<<"status">>,Doc])},
     {<<"stored_number">>,rpc(N,kz_json,get_value,[<<"number">>,Doc])}].
registration(N,At,Number) ->
    rpc(N,kz_json,from_list,[[{<<"number">>,Number},{<<"enqueued_at">>,At},
                              {<<"enqueue_sequence">>,1},{<<"priority">>,0},{<<"language">>,<<"en-us">>},
                              {<<"max_attempts">>,1},{<<"retry_delay">>,15},{<<"ttl">>,60}]]).
authority(N) ->
    rpc(N,kz_json,from_list,[[{<<"id">>,<<"duplicate-probe-device">>},{<<"type">>,<<"device">>},
                              {<<"account_realm">>,?REALM}]]).
rpc(N,M,F,A)->rpc:call(N,M,F,A,8000).
