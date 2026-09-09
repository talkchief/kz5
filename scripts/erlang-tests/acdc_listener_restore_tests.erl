%% Production callback with only external FSM/broker interactions mocked.
-module(acdc_listener_restore_tests).
-include_lib("eunit/include/eunit.hrl").

restore_test_() ->
    {foreach, fun setup/0, fun cleanup/1,
     [fun empty/0, fun replacement/0, fun retained_paused/0,
      fun invalid/0, fun active_listener/0, fun active_fsm/0,
      fun wrong_fsm_identity/0, fun unavailable_fsm/0,
      fun uncertain_binding/0, fun uncertain_publication/0]}.

setup() ->
    meck:new(acdc_agent_fsm,[passthrough,no_link]),
    meck:new(gen_listener,[passthrough,no_link]),
    meck:new(kapi_acdc_queue,[passthrough,no_link]),
    meck:new(kz_edr,[passthrough,no_link]),
    meck:expect(acdc_agent_fsm,maintenance_state,fun(_,_) -> observation(paused) end),
    meck:expect(acdc_agent_fsm,agent_logout,fun(_) -> error(unexpected_logout) end),
    meck:expect(gen_listener,add_binding,fun(_,_,_) -> ok end),
    meck:expect(gen_listener,rm_binding,fun(_,_,_) -> ok end),
    meck:expect(kapi_acdc_queue,publish_agent_change,fun(_) -> ok end),
    meck:expect(kz_edr,event,fun(_,_,_,_,_,_) -> error(unexpected_workforce_event) end),
    ok.
cleanup(_) ->
    ?assertEqual(0,meck:num_calls(acdc_agent_fsm,agent_logout,'_')),
    ?assertEqual(0,meck:num_calls(kz_edr,event,'_')),
    [meck:unload(M) || M <- [acdc_agent_fsm,gen_listener,kapi_acdc_queue,kz_edr]], ok.

observation(Mode) ->
    {ok,#{account_id=><<"account">>,agent_id=><<"agent">>,listener=>self(),state=>Mode}}.
checkpoint(Qs) -> #{account_id=><<"account">>,agent_id=><<"agent">>,queues=>Qs}.
state(Extra) -> acdc_listener_maintenance_tests:state(Extra).
restore(C,S) -> acdc_agent_listener:handle_call({maintenance_restore,C},{self(),make_ref()},S).
queues(S) -> {reply,{ok,M},S}=acdc_agent_listener:handle_call(maintenance_state,none,S),maps:get(queues,M).
changes() -> [proplists:get_value(<<"Change">>,P) ||
    {_,{kapi_acdc_queue,publish_agent_change,[P]},_} <- meck:history(kapi_acdc_queue)].
no_effects() ->
    ?assertEqual(0,meck:num_calls(gen_listener,add_binding,'_')),
    ?assertEqual(0,meck:num_calls(gen_listener,rm_binding,'_')),
    ?assertEqual([],changes()).

empty() ->
    S=state(#{agent_queues=>[<<"q">>]}),
    {reply,{ok,#{queues:=[],state:=paused,bindings_queued:=true}},After}=restore(checkpoint([]),S),
    ?assertEqual([],queues(After)),
    ?assertEqual(1,meck:num_calls(gen_listener,rm_binding,'_')),
    ?assertEqual([<<"unavailable">>],changes()).
replacement() ->
    meck:expect(acdc_agent_fsm,maintenance_state,fun(_,_) -> observation(ready) end),
    S=state(#{agent_queues=>[<<"old">>,<<"keep">>]}),
    Qs=[<<"new">>,<<"keep">>],
    {reply,{ok,#{state:=ready}},After}=restore(checkpoint(Qs),S),
    ?assertEqual(Qs,queues(After)),
    ?assertEqual(1,meck:num_calls(gen_listener,rm_binding,'_')),
    ?assertEqual(2,meck:num_calls(gen_listener,add_binding,'_')),
    ?assertEqual([<<"unavailable">>,<<"available">>,<<"available">>],changes()).
retained_paused() ->
    S=state(#{agent_queues=>[<<"q">>]}),
    {reply,{ok,_},S}=restore(checkpoint([<<"q">>]),S),
    ?assertEqual(0,meck:num_calls(gen_listener,rm_binding,'_')),
    ?assertEqual(1,meck:num_calls(gen_listener,add_binding,'_')),
    ?assertEqual([<<"busy">>],changes()).
invalid() ->
    S=state(#{}),
    [begin
        ?assertEqual({reply,{error,invalid_membership_checkpoint},S},restore(C,S))
     end || C <- [checkpoint([<<>>]),checkpoint([<<"q">>,<<"q">>]),checkpoint(undefined),
                   checkpoint([1]),(checkpoint([]))#{account_id=><<"other">>},
                   (checkpoint([]))#{agent_id=><<"other">>},
                   (checkpoint([]))#{state=>ready},#{},[]]],
    no_effects().
active_listener() ->
    S=state(#{call=>{live,call}}),
    ?assertEqual({reply,{error,agent_listener_not_drained},S},restore(checkpoint([]),S)),no_effects().
active_fsm() ->
    meck:expect(acdc_agent_fsm,maintenance_state,fun(_,_) -> {error,agent_not_drained} end),
    fsm_refused().
wrong_fsm_identity() ->
    meck:expect(acdc_agent_fsm,maintenance_state,fun(_,_) ->
        {ok,M}=observation(ready),{ok,M#{agent_id=><<"other">>}} end),
    fsm_refused().
unavailable_fsm() ->
    meck:expect(acdc_agent_fsm,maintenance_state,fun(_,_) -> exit(timeout) end),
    fsm_refused().
fsm_refused() ->
    S=state(#{}),
    ?assertEqual({reply,{error,agent_fsm_not_drained},S},restore(checkpoint([]),S)),no_effects().
uncertain_binding() ->
    meck:expect(gen_listener,add_binding,fun(_,_,_) -> error(binding_failure) end),
    uncertain().
uncertain_publication() ->
    meck:expect(kapi_acdc_queue,publish_agent_change,fun(_) -> error(broker_failure) end),
    uncertain().
uncertain() ->
    S=state(#{agent_queues=>[<<"old">>]}),
    ?assertEqual({reply,{error,membership_restore_uncertain},S},restore(checkpoint([<<"new">>]),S)).
