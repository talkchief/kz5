%% Exact production listener callback, no broker operations or test exports.
-module(acdc_listener_maintenance_tests).
-export([state/1]).
-include_lib("eunit/include/eunit.hrl").

listener_maintenance_test_() ->
    [{"runtime membership, not saved roster", fun() ->
        S = state(#{agent_queues => [<<"runtime-b">>,<<"runtime-a">>]}),
        {reply,{ok,M},S} = acdc_agent_listener:handle_call(maintenance_state,{self(),make_ref()},S),
        ?assertEqual(#{account_id => <<"account">>,agent_id => <<"agent">>
                       ,fsm => self(),queues => [<<"runtime-b">>,<<"runtime-a">>]},M)
      end},
     {"empty runtime membership is valid", fun() ->
        {ok,M} = observe(#{}), ?assertEqual([],maps:get(queues,M))
      end}] ++
    [{"refuse listener residual " ++ atom_to_list(Key), fun() ->
          ?assertEqual({error,agent_listener_not_drained},observe(#{Key => Value}))
      end} || {Key,Value} <- [{call,{private,call}}, {acdc_queue_id,<<"queue">>}
         ,{msg_queue_id,<<"broker-queue">>}, {agent_call_ids,[<<"leg">>]}
         ,{timer_ref,make_ref()}, {sync_resp,{pending,sync}}, {is_thief,true}
         ,{acct_id,undefined}, {agent_id,<<>>}, {fsm_pid,undefined}
         ,{agent_queues,undefined}]] ++
    [{"refuse invalid runtime membership", fun() ->
          ?assertEqual({error,agent_membership_inconsistent},observe(#{agent_queues => Qs}))
      end} || Qs <- [[<<>>],[undefined],[<<"q">>,<<"q">>]]].

observe(Extra) ->
    S = state(Extra),
    {reply,Result,S} = acdc_agent_listener:handle_call(maintenance_state,{self(),make_ref()},S),
    Result.

state(Extra) ->
    {ok,{acdc_agent_listener,[{abstract_code,{raw_abstract_v1,Forms}}]}} =
        beam_lib:chunks(code:which(acdc_agent_listener),[abstract_code]),
    [Fields] = [Fs || {attribute,_,record,{state,Fs}} <- Forms],
    Defaults = [field(F) || F <- Fields],
    Values = maps:merge(#{acct_id => <<"account">>,agent_id => <<"agent">>
                         ,fsm_pid => self(),agent => {saved_document,[<<"not-runtime">>]}},Extra),
    true = lists:all(fun(K) -> lists:keymember(K,1,Defaults) end,maps:keys(Values)),
    list_to_tuple([state|[maps:get(K,Values,V) || {K,V} <- Defaults]]).
field({typed_record_field,F,_}) -> field(F);
field({record_field,_,{atom,_,Name}}) -> {Name,undefined};
field({record_field,_,{atom,_,cdr_urls},_}) -> {cdr_urls,dict:new()};
field({record_field,_,{atom,_,Name},Default}) -> {Name,erl_parse:normalise(Default)}.
