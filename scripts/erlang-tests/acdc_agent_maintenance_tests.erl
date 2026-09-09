%% Real gen_statem observation tests; no production init, network, or broker.
-module(acdc_agent_maintenance_tests).
-include_lib("eunit/include/eunit.hrl").
-export([bootstrap/3]).

maintenance_test_() ->
    [{"ready observation is read-only", fun ready_snapshot/0}
    ,{"infinite pause is retained", fun infinite_pause/0}
    ,{"finite pause retains timer and deadline", fun finite_pause/0}
    ,{"expired pause is not ready", fun expired_pause/0}
    ,{"ready with a pause is inconsistent", fun inconsistent_ready/0}
    ,{"paused without timer is inconsistent", fun inconsistent_paused/0}
    ] ++
    [{"refuse state " ++ atom_to_list(Name), fun() ->
          with_fsm(Name, #{}, fun(Pid) ->
              ?assertEqual({error, agent_not_drained}, snapshot(Pid))
          end)
      end} || Name <- [wait,sync,ringing,answered,wrapup,outbound]] ++
    [{"refuse residual " ++ atom_to_list(Key), fun() ->
          with_fsm(ready, #{Key => Value}, fun(Pid) ->
              ?assertEqual({error, agent_not_drained}, snapshot(Pid))
          end)
      end} || {Key,Value} <-
        [{member_call, {call,private}}, {member_call_id, <<"call">>}
        ,{member_call_queue_id, <<"queue">>}, {member_call_start, 1}
        ,{agent_call_id, <<"agent-call">>}, {outbound_call_ids, [<<"outbound">>]}
        ,{member_connect_id, <<"offer">>}, {monitoring, true}
        ,{agent_state_updates, [{agent_logout}]}, {call_check, {pending,probe}}
        ,{sync_ref, make_ref()}, {wrapup_ref, make_ref()}
        ,{account_id, undefined}, {agent_id, <<>>}, {agent_listener, undefined}]].

ready_snapshot() ->
    with_fsm(ready, #{}, fun(Pid) ->
        {ok, S} = snapshot(Pid),
        ?assertEqual(#{account_id => <<"fixture-account">>, agent_id => <<"fixture-agent">>
                      ,listener => self(), state => ready, pause_remaining_ms => 0}, S)
    end).

infinite_pause() ->
    with_fsm(paused, #{pause_ref => infinity}, fun(Pid) ->
        {ok, S} = snapshot(Pid),
        ?assertEqual(infinity, maps:get(pause_remaining_ms,S)),
        ?assertNot(maps:is_key(pause_until_unix_ms,S))
    end).

finite_pause() ->
    Start = erlang:system_time(millisecond),
    with_fsm(paused, #{pause_ref => finite_fixture_timer}, fun(Pid) ->
        {ok, S} = snapshot(Pid),
        Left = maps:get(pause_remaining_ms,S),
        Until = maps:get(pause_until_unix_ms,S),
        ?assert(Left > 0 andalso Left =< 60000),
        ?assert(Until >= Start + 59000),
        ?assert(Until =< erlang:system_time(millisecond) + 60000)
    end).

expired_pause() ->
    with_fsm(paused, #{pause_ref => make_ref()}, fun(Pid) ->
        ?assertEqual({error,agent_pause_transition_pending}, snapshot(Pid))
    end).
inconsistent_ready() ->
    with_fsm(ready, #{pause_ref => infinity}, fun(Pid) ->
        ?assertEqual({error,agent_pause_state_inconsistent}, snapshot(Pid))
    end).
inconsistent_paused() ->
    with_fsm(paused, #{}, fun(Pid) ->
        ?assertEqual({error,agent_pause_state_inconsistent}, snapshot(Pid))
    end).

snapshot(Pid) ->
    Before = sys:get_state(Pid,2000),
    Result = acdc_agent_fsm:maintenance_state(Pid,2000),
    ?assertEqual(Before, sys:get_state(Pid,2000)),
    Result.

with_fsm(Name, Extra, Test) ->
    ?assertEqual(nonode@nohost, node()),
    {ok,Pid} = proc_lib:start_link(?MODULE,bootstrap,[self(),Name,Extra]),
    unlink(Pid),
    Ref = monitor(process,Pid),
    try Test(Pid)
    after
        exit(Pid,kill),
        receive {'DOWN',Ref,process,Pid,_} -> ok after 2000 -> error(cleanup_timeout) end
    end.

bootstrap(Parent, Name, Extra0) ->
    {ok,{acdc_agent_fsm,[{abstract_code,{raw_abstract_v1,Forms}}]}} =
        beam_lib:chunks(code:which(acdc_agent_fsm),[abstract_code]),
    [Fields] = [Fs || {attribute,_,record,{state,Fs}} <- Forms],
    Defaults = [field(F) || F <- Fields],
    Extra = case maps:get(pause_ref, Extra0, undefined) of
        finite_fixture_timer -> Extra0#{pause_ref => erlang:start_timer(60000,self(),pause_expired)};
        _ -> Extra0
    end,
    Base = maps:merge(#{account_id => <<"fixture-account">>,agent_id => <<"fixture-agent">>
                       ,agent_listener => Parent}, Extra),
    true = lists:all(fun(K) -> lists:keymember(K,1,Defaults) end,maps:keys(Base)),
    State = list_to_tuple([state|[maps:get(K,Base,V) || {K,V} <- Defaults]]),
    proc_lib:init_ack(Parent,{ok,self()}),
    gen_statem:enter_loop(acdc_agent_fsm,[],Name,State).

field({typed_record_field,F,_}) -> field(F);
field({record_field,_,{atom,_,Name}}) -> {Name,undefined};
field({record_field,_,{atom,_,Name},Default}) -> {Name,erl_parse:normalise(Default)}.
