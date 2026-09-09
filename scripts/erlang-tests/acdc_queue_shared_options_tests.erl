%%% SPDX-License-Identifier: MPL-2.0
-module(acdc_queue_shared_options_tests).
-include_lib("eunit/include/eunit.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

shutdown_requeues_unfinished_deliveries_test() ->
    Modules = [gen_listener, kz_log, kz_amqp_channel],
    lists:foreach(fun(M) -> meck:new(M, [non_strict, no_link]) end, Modules),
    try
        meck:expect(kz_log, put_callid, fun(_) -> ok end),
        meck:expect(gen_listener, cast, fun(_, _) -> ok end),
        meck:expect(kz_amqp_channel, command, fun(_) -> ok end),
        {ok, Initial} = acdc_queue_shared:init([self()]),
        D1 = #'basic.deliver'{delivery_tag=100},
        D2 = #'basic.deliver'{delivery_tag=101},
        D3 = #'basic.deliver'{delivery_tag=102},
        {noreply, S1} = acdc_queue_shared:handle_cast({delivery, D1}, Initial),
        {noreply, S2} = acdc_queue_shared:handle_cast({delivery, D2}, S1),
        {noreply, S3} = acdc_queue_shared:handle_cast({delivery, D3}, S2),
        {noreply, S4} = acdc_queue_shared:handle_cast({ack, D3}, S3),
        _ = acdc_queue_shared:terminate(shutdown, S4),
        Frames = [Frame || {_, {kz_amqp_channel, command, [Frame]}, _} <- meck:history(kz_amqp_channel)],
        ?assertEqual([#'basic.nack'{delivery_tag=101, requeue=true, multiple=false},
                      #'basic.nack'{delivery_tag=100, requeue=true, multiple=false}], Frames)
    after lists:foreach(fun meck:unload/1, Modules) end.

explicit_nack_and_ack_policy_preserved_test() ->
    meck:new(kz_amqp_channel, [non_strict, no_link]),
    try
        meck:expect(kz_amqp_channel, command, fun(Frame) -> Frame end),
        Delivery = #'basic.deliver'{delivery_tag=9},
        ?assertEqual(#'basic.nack'{delivery_tag=9, requeue=false, multiple=false},
                     kz_amqp_util:basic_nack(Delivery, false)),
        ?assertEqual(#'basic.nack'{delivery_tag=9, requeue=true, multiple=true},
                     kz_amqp_util:basic_nack(Delivery, true, true)),
        Explicit = #'basic.nack'{delivery_tag=9, requeue=false, multiple=true},
        ?assertEqual(Explicit, kz_amqp_util:basic_nack(Explicit)),
        ?assertEqual(#'basic.ack'{delivery_tag=9, multiple=false}, kz_amqp_util:basic_ack(Delivery))
    after meck:unload(kz_amqp_channel) end.

shared_work_survives_last_consumer_disconnect_test() ->
    Modules = [acdc_util, kzs_util, kapi_acdc_queue, gen_listener],
    lists:foreach(fun(M) -> meck:new(M, [non_strict, no_link]) end, Modules),
    try
        meck:expect(kzs_util, format_account_db, fun(<<"account">>) -> <<"account-db">> end),
        meck:expect(acdc_util, max_priority, fun(<<"account-db">>, <<"queue">>) -> 7 end),
        meck:expect(kapi_acdc_queue, shared_queue_name,
                    fun(<<"account">>, <<"queue">>) -> <<"acdc.queue.account.queue">> end),
        meck:expect(gen_listener, start_link, fun(acdc_queue_shared, Options, [Worker]) ->
            ?assertEqual(self(), Worker),
            ?assertEqual(<<"acdc.queue.account.queue">>, proplists:get_value(queue_name, Options)),
            QueueOptions = proplists:get_value(queue_options, Options),
            %% kz_amqp_util defaults auto_delete to true when omitted. All
            %% consumers exit together on a queue supervisor restart; deleting
            %% this queue would lose the unacked delivery needed for recovery.
            ?assertEqual(false, proplists:get_value(auto_delete, QueueOptions, true)),
            ?assertEqual(false, proplists:get_value(exclusive, QueueOptions)),
            ?assertEqual(1, proplists:get_value(basic_qos, Options)),
            ?assertEqual(false, proplists:get_value(no_ack, proplists:get_value(consume_options, Options))),
            Arguments = proplists:get_value(arguments, QueueOptions),
            ?assertEqual(7, proplists:get_value(<<"x-max-priority">>, Arguments)),
            ?assertEqual(1000, proplists:get_value(<<"x-max-length">>, Arguments)),
            ?assertEqual(86400000, proplists:get_value(<<"x-message-ttl">>, Arguments)),
            {ok, self()}
        end),
        ?assertEqual({ok, self()}, acdc_queue_shared:start_link(self(), self(), <<"account">>, <<"queue">>))
    after lists:foreach(fun meck:unload/1, Modules) end.
