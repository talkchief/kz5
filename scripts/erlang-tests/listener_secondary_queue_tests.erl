-module(listener_secondary_queue_tests).
-include_lib("eunit/include/eunit.hrl").
-include("state.hrl").

secondary_queue_recovery_test() ->
    meck:new(kz_amqp_util,[non_strict,no_link]),
    meck:new(kapi_resource,[non_strict,no_link]),
    meck:expect(kz_amqp_util,new_queue,fun(Q,_) -> Q end),
    meck:expect(kz_amqp_util,basic_consume,fun(_,_) -> ok end),
    meck:expect(kapi_resource,bind_q,fun(_,_) -> ok end),
    meck:expect(kapi_resource,unbind_q,fun(_,_) -> ok end),
    try
        Q = <<"isolated-resource-queue">>,
        P = [{queue_options,[{exclusive,false}]},{consume_options,[{exclusive,false}]}],
        B = [{resource,[{restrict_to,[originate]}]}],
        S0 = #state{consumer_key=self()},
        {noreply,S1} = gen_listener:handle_cast({add_queue,Q,P,B},S0),
        ?assertEqual([{Q,{B,P}}],S1#state.other_queues),
        ?assertEqual(1,meck:num_calls(kz_amqp_util,basic_consume,'_')),
        S2=lists:foldl(fun(_,S) ->
            {noreply,N}=gen_listener:handle_cast({add_queue,Q,P,B},S),N
        end,S1,lists:seq(1,20)),
        ?assertEqual(S1#state.other_queues,S2#state.other_queues),
        ?assertEqual(1,meck:num_calls(kz_amqp_util,basic_consume,'_')),
        ?assertEqual(1,meck:num_calls(kapi_resource,bind_q,'_')),
        S3=gen_listener:maybe_start_other_queues(S2),
        ?assertEqual(S2#state.other_queues,S3#state.other_queues),
        ?assertEqual(2,meck:num_calls(kz_amqp_util,basic_consume,'_')),
        {noreply,S4}=gen_listener:handle_cast({add_queue,Q,P,B},S3),
        ?assertEqual(2,meck:num_calls(kz_amqp_util,basic_consume,'_')),
        Extra={resource,[{restrict_to,[reconcile]}]},
        {noreply,S5}=gen_listener:handle_cast({add_queue,Q,P,[Extra]},S4),
        ?assertEqual([{Q,{[Extra|B],P}}],S5#state.other_queues),
        ?assertEqual(2,meck:num_calls(kz_amqp_util,basic_consume,'_')),
        {noreply,S6}=gen_listener:handle_cast({rm_queue,Q},S5),
        ?assertEqual([],S6#state.other_queues),
        ?assertEqual(2,meck:num_calls(kapi_resource,unbind_q,'_')),
        {noreply,S6}=gen_listener:handle_cast({rm_queue,Q},S6)
    after
        meck:unload(kz_amqp_util), meck:unload(kapi_resource)
    end.
