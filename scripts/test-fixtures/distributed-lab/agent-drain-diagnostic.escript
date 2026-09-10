#!/usr/bin/env escript
%%! +S 1:1 +SDcpu 1 +SDio 1 +A 1 -setcookie unused_drain_diagnostic -start_epmd false -kernel logger_level none
%% Read-only exact private fixture. Never emit call IDs, records or credentials.
-mode(compile).
-include_lib("kernel/include/file.hrl").
-define(A, <<"45e827067baf078029d0ca16a489fa8a">>).
main(Args)->try
    [U0]=Args,U=list_to_binary(U0),match=re:run(U,<<"^[a-f0-9]{32}$">>,[{capture,none}]),
    {ok,H}=inet:gethostname(),Ip=case H of "kz5-stage-kazoo-apps"->{172,30,253,14};"kz5-stage-kazoo-apps-peer"->{172,30,253,20} end,
    {ok,Ifs}=inet:getifaddrs(),true=lists:any(fun({_,V})->lists:member({addr,Ip},V) end,Ifs),
    {ok,#file_info{type=regular,uid=0,links=1,mode=M}}=file:read_link_info("/etc/kazoo/.erlang.cookie"),
    true=(M band 8#077)=:=0,{ok,C}=file:read_file("/etc/kazoo/.erlang.cookie"),
    ok=application:set_env(kernel,inet_dist_use_interface,Ip),
    {ok,_}=net_kernel:start([list_to_atom("drain_diagnostic_"++os:getpid()++"@"++H),shortnames]),
    true=erlang:set_cookie(node(),binary_to_atom(string:trim(C),utf8)),N=list_to_atom("kazoo_apps@"++H),
    Db=rpc(N,kzs_util,format_account_db,[?A]),{ok,A}=rpc(N,kz_datamgr,open_doc,[Db,?A]),
    <<"acceptance-724fa76c8821.invalid">>=rpc(N,kz_json,get_value,[<<"realm">>,A]),
    {ok,D}=rpc(N,kz_datamgr,open_doc,[Db,U]),?A=rpc(N,kz_doc,account_id,[D]),<<"user">>=rpc(N,kz_doc,type,[D]),
    Sup=rpc(N,acdc_agents_sup,find_agent_supervisor,[?A,U]),true=is_pid(Sup),
    F=rpc(N,acdc_agent_sup,fsm,[Sup]),L=rpc(N,acdc_agent_sup,listener,[Sup]),
    FStatus=rpc(N,acdc_agent_fsm,maintenance_state,[F,2000]),LStatus=rpc(N,acdc_agent_listener,maintenance_state,[L,2000]),
    {State,FRecord}=rpc(N,sys,get_state,[F,2000]),LWrapper=rpc(N,sys,get_state,[L,2000]),
    Wrapper=record_map(N,gen_listener,LWrapper),
    acdc_agent_listener=maps:get(module,Wrapper),LRecord=maps:get(module_state,Wrapper),
    FFields=[member_call,member_call_id,member_call_queue_id,member_call_start,agent_call_id,outbound_call_ids,
        member_connect_id,monitoring,agent_state_updates,call_check,sync_ref,wrapup_ref,pause_ref],
    LFields=[call,acdc_queue_id,msg_queue_id,agent_call_ids,timer_ref,sync_resp,is_thief],
    Legs=maps:get(agent_call_ids,record_map(N,acdc_agent_listener,LRecord)),
    Data=#{<<"state">>=>atom_to_binary(State,utf8),<<"fsm_status">>=>status(FStatus),<<"listener_status">>=>status(LStatus),
        <<"listener_leg_shapes">>=>[leg_shape(V)||V<-Legs],
        <<"fsm_fields">>=>fields(N,acdc_agent_fsm,FRecord,FFields),<<"listener_fields">>=>fields(N,acdc_agent_listener,LRecord,LFields)},
    J=rpc(N,kz_json,from_map,[Data]),io:format("~s~n",[rpc(N,kz_json,encode,[J])]),net_kernel:stop()
catch _:_ ->io:put_chars("SCOPED_DRAIN_DIAGNOSTIC_REFUSED\n"),halt(1) end.
status({ok,_})-><<"drained">>;
status({error,E}) when is_atom(E)->atom_to_binary(E,utf8);
status(_)-><<"unavailable">>.
fields(N,Module,Record,Selected)->
    Map=record_map(N,Module,Record),
    maps:from_list([{atom_to_binary(K,utf8),summary(maps:get(K,Map))}||K<-Selected]).
record_map(N,Module,Record)->
    File=rpc(N,code,which,[Module]),
    {ok,{Module,[{abstract_code,{raw_abstract_v1,Forms}}]}}=rpc(N,beam_lib,chunks,[File,[abstract_code]]),
    [Definitions]=[Ds||{attribute,_,record,{state,Ds}}<-Forms],Names=[name(D)||D<-Definitions],
    [state|Values]=tuple_to_list(Record),true=length(Names)=:=length(Values),
    maps:from_list(lists:zip(Names,Values)).
name({typed_record_field,F,_})->name(F);
name({record_field,_,{atom,_,Name},_})->Name;
name({record_field,_,{atom,_,Name}})->Name.
summary(undefined)->#{<<"populated">>=>false};
summary(false)->#{<<"populated">>=>false};
summary([])->#{<<"populated">>=>false,<<"count">>=>0};
summary(V) when is_list(V)->#{<<"populated">>=>true,<<"count">>=>length(V)};
summary(_)->#{<<"populated">>=>true}.
leg_shape(V) when is_binary(V)-><<"passive_binary">>;
leg_shape({_,undefined})-><<"pending_control_queue">>;
leg_shape({_,Q}) when is_binary(Q)-><<"control_queue">>;
leg_shape(_)-><<"other">>.
rpc(N,M,F,A)->rpc:call(N,M,F,A,5000).
