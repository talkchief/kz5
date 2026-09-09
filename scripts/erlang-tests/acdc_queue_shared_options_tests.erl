%%% SPDX-License-Identifier: MPL-2.0
-module(acdc_queue_shared_options_tests).
-include_lib("eunit/include/eunit.hrl").

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
