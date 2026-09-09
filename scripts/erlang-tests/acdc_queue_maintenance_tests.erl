%% Production queue observations: real gen_statem process and exact listener/
%% manager callbacks. No application startup, database, broker or call mutation.
-module(acdc_queue_maintenance_tests).
-include_lib("eunit/include/eunit.hrl").
-export([bootstrap/3]).

queue_maintenance_test_() ->
    [{"drained FSM yields identities only", fun() ->
         with_fsm(ready,#{},fun(P) ->
             ?assertEqual({ok,#{account_id=><<"account">>,queue_id=><<"queue">>,
                               state=>ready,listener=>self(),manager=>self()}},observe(P))
         end)
      end},
     {"ready/current_call is insufficient drain evidence", fun() ->
         with_fsm(ready,#{callback_ctx=>#{registration_job=>private}},fun(P) ->
             ?assertEqual(undefined,acdc_queue_fsm:current_call(P)),
             ?assertEqual({error,queue_worker_not_drained},observe(P))
         end)
      end}] ++
    [{"refuse queue state "++atom_to_list(Name),fun() ->
         with_fsm(Name,#{},fun(P) ->
             ?assertEqual({error,queue_worker_not_drained},observe(P))
         end)
      end} || Name <- [connect_req,connecting,callback_paused,callback_waiting]] ++
    [{"refuse ready queue residual "++atom_to_list(K),fun() ->
         with_fsm(ready,#{K=>V},fun(P) ->
             ?assertEqual({error,queue_worker_not_drained},observe(P))
         end)
      end} || {K,V} <-
          [{connect_resps,[private]}, {connect_wins,[private]}, {collect_ref,make_ref()}
          ,{timer_ref,make_ref()}, {connection_timer_ref,make_ref()}, {agent_ring_timer_ref,make_ref()}
          ,{member_call,{private,call}}, {member_call_start,1}, {member_call_winners,[private]}
          ,{announce_played,true}, {announce_id,<<"private">>}, {announce_timer_ref,make_ref()}
          ,{pending_queue_opts,[private]}, {callback_ctx,#{job=>private}}, {callback_ctx,undefined}
          ,{attempted_agents,[<<"private">>]}, {bridge_ctx,#{probe=>make_ref()}}, {bridge_ctx,[]}
          ,{account_id,undefined}, {queue_id,<<>>}, {listener_proc,undefined}, {manager_proc,undefined}]] ++
    [{"drained listener retains paired identities",fun() ->
         ?assertEqual({ok,#{account_id=><<"account">>,queue_id=><<"queue">>,
                           manager=>self(),fsm=>self(),shared_listener=>self(),
                           broker_queue=><<"owned-private-queue">>}}, listener(#{}))
      end}] ++
    [{"refuse listener residual "++atom_to_list(K),fun() ->
         ?assertEqual({error,queue_listener_not_drained},listener(#{K=>V}))
      end} || {K,V} <- [{call,{private,call}}, {agent_id,<<"private">>}, {delivery,{private,delivery}}
          ,{member_call_queue,<<"held-queue">>}, {account_id,undefined}, {queue_id,<<>>}
          ,{mgr_pid,undefined}, {fsm_pid,undefined}, {shared_pid,undefined}, {my_q,<<>>}]] ++
    [{"drained manager observes without changing strategy",fun() ->
         ?assertEqual({ok,#{account_id=><<"account">>,queue_id=><<"queue">>,
                           supervisor=>self(),busy_agents=>[]}},manager(#{}))
      end}] ++
    [{"refuse manager residual "++atom_to_list(K),fun() ->
         ?assertEqual({error,queue_manager_not_drained},manager(#{K=>V}))
      end} || {K,V} <- [{current_member_calls,[{private,call}]}
          ,{announcements_pids,#{private=>self()}}, {announcements_pids,undefined}
          ,{ignored_member_calls,dict:store(private,true,dict:new())}, {ignored_member_calls,undefined}
          ,{account_id,undefined}, {queue_id,<<>>}, {supervisor,undefined}]] ++
    [{"refuse manager outstanding "++atom_to_list(K),fun() ->
         SS=record(acdc_queue_manager,strategy_state,#{K=>[<<"private">>]}),
         ?assertEqual({error,queue_manager_not_drained},manager(#{strategy_state=>SS}))
      end} || K <- [ringing_agents]] ++
    [{"busy may mean paused; retain identities for complete agent correlation",fun() ->
         SS=record(acdc_queue_manager,strategy_state,#{busy_agents=>[<<"paused-agent">>]}),
         ?assertEqual({ok,#{account_id=><<"account">>,queue_id=><<"queue">>,
                           supervisor=>self(),busy_agents=>[<<"paused-agent">>]}},manager(#{strategy_state=>SS}))
      end}] ++
    [{"reject malformed busy-agent inventory",fun() ->
         SS=record(acdc_queue_manager,strategy_state,#{busy_agents=>Busy}),
         ?assertEqual({error,queue_manager_not_drained},manager(#{strategy_state=>SS}))
      end} || Busy <- [undefined,[<<>>],[42],[<<"duplicate">>,<<"duplicate">>]]] ++
    [{"drained shared listener exposes paired FSM only",fun() ->
         ?assertEqual({ok,#{fsm=>self()}},shared(#{}))
      end}] ++
    [{"refuse shared delivery ownership "++atom_to_list(K),fun() ->
         ?assertEqual({error,queue_shared_not_drained},shared(#{K=>V}))
      end} || {K,V} <- [{deliveries,[{private,delivery}]},{deliveries,undefined},{fsm_pid,undefined}]].

observe(P) ->
    Before=sys:get_state(P,2000),
    Result=acdc_queue_fsm:maintenance_state(P,2000),
    ?assertEqual(Before,sys:get_state(P,2000)),Result.
listener(Extra) ->
    State=record(acdc_queue_listener,state,maps:merge(
        #{account_id=><<"account">>,queue_id=><<"queue">>,mgr_pid=>self(),
          fsm_pid=>self(),shared_pid=>self(),my_q=><<"owned-private-queue">>},Extra)),
    {reply,Reply,State}=acdc_queue_listener:handle_call(maintenance_state,{self(),make_ref()},State),Reply.
manager(Extra) ->
    State=record(acdc_queue_manager,state,maps:merge(
        #{account_id=><<"account">>,queue_id=><<"queue">>,supervisor=>self()},Extra)),
    {reply,Reply,State}=acdc_queue_manager:handle_call(maintenance_state,{self(),make_ref()},State),Reply.
shared(Extra) ->
    State=record(acdc_queue_shared,state,maps:merge(#{fsm_pid=>self()},Extra)),
    {reply,Reply,State}=acdc_queue_shared:handle_call(maintenance_state,{self(),make_ref()},State),Reply.
with_fsm(Name,Extra,Test) ->
    ?assertEqual(nonode@nohost,node()),
    {ok,P}=proc_lib:start_link(?MODULE,bootstrap,[self(),Name,Extra]),
    unlink(P),Ref=monitor(process,P),
    try Test(P)
    after exit(P,kill),receive {'DOWN',Ref,process,P,_}->ok after 2000->error(cleanup_timeout) end end.
bootstrap(Parent,Name,Extra) ->
    State=record(acdc_queue_fsm,state,maps:merge(
        #{account_id=><<"account">>,queue_id=><<"queue">>,listener_proc=>Parent,
          manager_proc=>Parent,member_call_winners=>[]},Extra)),
    proc_lib:init_ack(Parent,{ok,self()}),
    gen_statem:enter_loop(acdc_queue_fsm,[],Name,State).

%% Derive the production record layout from the compiled production BEAM, not
%% copied tuple indexes or TEST-only source exports. Whitelist nonliteral defaults.
record(Module,Name,Extra) ->
    {ok,{Module,[{abstract_code,{raw_abstract_v1,Forms}}]}}=beam_lib:chunks(code:which(Module),[abstract_code]),
    [Fields]=[Fs || {attribute,_,record,{N,Fs}}<-Forms,N=:=Name],
    Defaults=[field(Module,F)||F<-Fields],
    true=lists:all(fun(K)->lists:keymember(K,1,Defaults) end,maps:keys(Extra)),
    list_to_tuple([Name|[maps:get(K,Extra,V)||{K,V}<-Defaults]]).
field(M,{typed_record_field,F,_})->field(M,F);
field(_,{record_field,_,{atom,_,Name}})->{Name,undefined};
field(M,{record_field,_,{atom,_,Name},Default})->{Name,value(M,Default)}.
value(_,{call,_,{remote,_,{atom,_,dict},{atom,_,new}},[]})->dict:new();
value(M,{record,_,Name,[]})->record(M,Name,#{});
value(_,Literal)->erl_parse:normalise(Literal).
