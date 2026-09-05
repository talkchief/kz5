%%% SPDX-License-Identifier: MPL-2.0
-module(acdc_callback_agent_probe_tests).

-include_lib("eunit/include/eunit.hrl").

-define(ACCOUNT, <<"11111111111111111111111111111111">>).
-define(CALL, <<"returned-caller">>).
-define(AGENT, <<"agent-one">>).
-define(AGENT_CALL, <<"agent-leg-one">>).
-define(PROCESS, <<"agent-process-one">>).
-define(MSG, <<"22222222222222222222222222222222">>).

strict_response_validation_test() ->
    Response = response(?ACCOUNT, ?CALL, ?AGENT, ?PROCESS, ?MSG, <<"answered">>),
    ?assert(acdc_callback_agent_probe:response_matches(
              Response, ?ACCOUNT, ?CALL, ?AGENT_CALL, {?AGENT, ?PROCESS}, ?MSG)),
    Mutations = [{<<"Account-ID">>, <<"other-account">>}
                ,{<<"Call-ID">>, <<"other-call">>}
                ,{<<"Agent-ID">>, <<"other-agent">>}
                ,{<<"Process-ID">>, <<"other-process">>}
                ,{<<"Agent-Call-ID">>, <<"other-agent-leg">>}
                ,{<<"Msg-ID">>, <<"other-message">>}
                ,{<<"Status">>, <<"ringing">>}],
    lists:foreach(
      fun({Key, Value}) ->
          ?assertNot(acdc_callback_agent_probe:response_matches(
                       kz_json:set_value(Key, Value, Response), ?ACCOUNT, ?CALL,
                       ?AGENT_CALL, {?AGENT, ?PROCESS}, ?MSG))
      end, Mutations),
    ?assertNot(acdc_callback_agent_probe:response_matches(
                 kz_json:delete_key(<<"Event-Name">>, Response), ?ACCOUNT, ?CALL,
                 ?AGENT_CALL, {?AGENT, ?PROCESS}, ?MSG)),
    ?assertNot(acdc_callback_agent_probe:response_matches(
                 kz_json:delete_key(<<"Agent-Call-ID">>, Response), ?ACCOUNT, ?CALL,
                 ?AGENT_CALL, {?AGENT, ?PROCESS}, ?MSG)).

agent_leg_is_preserved_by_protocol_builders_test() ->
    Sync = response(?ACCOUNT, ?CALL, ?AGENT, ?PROCESS, ?MSG, <<"answered">>),
    {ok, SyncPayload} = kapi_acdc_agent:sync_resp(Sync),
    ?assertEqual(?AGENT_CALL,
                 kz_json:get_value(<<"Agent-Call-ID">>,
                                   kz_json:decode(iolist_to_binary(SyncPayload)))),
    Accepted = kz_json:from_list(
                 [{<<"Call-ID">>, ?CALL}, {<<"Account-ID">>, ?ACCOUNT}
                 ,{<<"Agent-ID">>, ?AGENT}, {<<"Process-ID">>, ?PROCESS}
                 ,{<<"Agent-Call-ID">>, ?AGENT_CALL}
                 ,{<<"Msg-ID">>, ?MSG}
                 ,{<<"Event-Category">>, <<"member">>}
                 ,{<<"Event-Name">>, <<"connect_accepted">>}
                  | kz_api:default_headers(<<"test">>, <<"1">>)]),
    {ok, AcceptedPayload} = kapi_acdc_queue:member_connect_accepted(Accepted),
    ?assertEqual(?AGENT_CALL,
                 kz_json:get_value(<<"Agent-Call-ID">>,
                                   kz_json:decode(iolist_to_binary(AcceptedPayload)))),
    LegacyAccepted = kz_json:delete_key(<<"Agent-Call-ID">>, Accepted),
    ?assert(kapi_acdc_queue:member_connect_accepted_v(LegacyAccepted)),
    {ok, LegacyAcceptedPayload} = kapi_acdc_queue:member_connect_accepted(LegacyAccepted),
    ?assertEqual(undefined, kz_json:get_value(<<"Agent-Call-ID">>,
                      kz_json:decode(iolist_to_binary(LegacyAcceptedPayload)))),
    LegacySync = kz_json:delete_key(<<"Agent-Call-ID">>, Sync),
    ?assert(kapi_acdc_agent:sync_resp_v(LegacySync)),
    {ok, LegacySyncPayload} = kapi_acdc_agent:sync_resp(LegacySync),
    ?assertEqual(undefined, kz_json:get_value(<<"Agent-Call-ID">>,
                      kz_json:decode(iolist_to_binary(LegacySyncPayload)))),
    ?assertNot(acdc_callback_agent_probe:response_matches(
                 LegacySync, ?ACCOUNT, ?CALL, ?AGENT_CALL, {?AGENT, ?PROCESS}, ?MSG)).

first_exact_answered_winner_succeeds_test() -> with_worker(fun() ->
    Win1 = winner(<<"agent-slow">>, <<"process-slow">>),
    Win2 = winner(?AGENT, ?PROCESS),
    meck:expect(kz_amqp_worker, call,
                fun(Request, _Publish, Validator, _Timeout) ->
                    case proplists:get_value(<<"Agent-ID">>, Request) of
                        <<"agent-slow">> -> timer:sleep(100), {error, timeout};
                        ?AGENT ->
                            Msg = proplists:get_value(<<"Msg-ID">>, Request),
                            Candidate = response(?ACCOUNT, ?CALL, ?AGENT, ?PROCESS, Msg, <<"answered">>),
                            case Validator(Candidate) of true -> {ok, Candidate}; false -> {error, invalid} end
                    end
                end),
    {ok, Proof} = acdc_callback_agent_probe:probe_for_test(
                    ?ACCOUNT, ?CALL, [Win1, Win2], ?AGENT_CALL, 250),
    ?assertEqual(?AGENT, kz_json:get_value(<<"Agent-ID">>, Proof)),
    ?assertEqual(?PROCESS, kz_json:get_value(<<"Process-ID">>, Proof))
end).

wrong_process_or_call_never_proves_acceptance_test() -> with_worker(fun() ->
    meck:expect(kz_amqp_worker, call,
                fun(Request, _Publish, Validator, _Timeout) ->
                    Msg = proplists:get_value(<<"Msg-ID">>, Request),
                    Wrong = response(?ACCOUNT, <<"foreign-call">>, ?AGENT, <<"foreign-process">>, Msg, <<"answered">>),
                    case Validator(Wrong) of true -> {ok, Wrong}; false -> {error, timeout} end
                end),
    ?assertEqual({error, unknown},
                 acdc_callback_agent_probe:probe_for_test(
                   ?ACCOUNT, ?CALL, [winner(?AGENT, ?PROCESS)], ?AGENT_CALL, 100))
end).

one_global_deadline_bounds_all_winners_test() -> with_worker(fun() ->
    meck:expect(kz_amqp_worker, call,
                fun(_Request, _Publish, _Validator, _Timeout) -> timer:sleep(300), {error, timeout} end),
    Started = erlang:monotonic_time(millisecond),
    Wins = [winner(iolist_to_binary([<<"agent-">>, integer_to_binary(N)]),
                   iolist_to_binary([<<"process-">>, integer_to_binary(N)])) || N <- lists:seq(1, 8)],
    ?assertEqual({error, unknown},
                 acdc_callback_agent_probe:probe_for_test(
                   ?ACCOUNT, ?CALL, Wins, ?AGENT_CALL, 50)),
    Elapsed = erlang:monotonic_time(millisecond) - Started,
    ?assert(Elapsed < 250)
end).

invalid_or_excessive_winner_sets_are_rejected_without_publish_test() -> with_worker(fun() ->
    meck:expect(kz_amqp_worker, call, fun(_, _, _, _) -> error(unexpected_publish) end),
    ?assertEqual({error, unknown}, acdc_callback_agent_probe:probe_for_test(
                                      ?ACCOUNT, ?CALL, [], ?AGENT_CALL, 100)),
    ?assertEqual({error, unknown}, acdc_callback_agent_probe:probe_for_test(
                                      ?ACCOUNT, ?CALL, [winner(?AGENT, undefined)],
                                      ?AGENT_CALL, 100)),
    ?assertEqual({error, unknown}, acdc_callback_agent_probe:probe_for_test(
                                      ?ACCOUNT, ?CALL, [winner(?AGENT, ?PROCESS)],
                                      <<>>, 100)),
    TooMany = [winner(integer_to_binary(N), iolist_to_binary([<<"p">>, integer_to_binary(N)]))
               || N <- lists:seq(1, 33)],
    ?assertEqual({error, unknown},
                 acdc_callback_agent_probe:probe_for_test(
                   ?ACCOUNT, ?CALL, TooMany, ?AGENT_CALL, 100)),
    ?assertEqual(0, meck:num_calls(kz_amqp_worker, call, '_'))
end).

winner(Agent, Process) -> kz_json:from_list([{<<"Agent-ID">>, Agent}, {<<"Process-ID">>, Process}]).

response(Account, Call, Agent, Process, Msg, Status) ->
    kz_json:from_list([{<<"Account-ID">>, Account}, {<<"Call-ID">>, Call}
                      ,{<<"Agent-ID">>, Agent}, {<<"Process-ID">>, Process}
                      ,{<<"Agent-Call-ID">>, ?AGENT_CALL}
                      ,{<<"Msg-ID">>, Msg}, {<<"Status">>, Status}
                      ,{<<"Event-Category">>, <<"agent">>}, {<<"Event-Name">>, <<"sync_resp">>}
                      ,{<<"App-Name">>, <<"test">>}, {<<"App-Version">>, <<"1">>}]).

with_worker(Fun) ->
    meck:new(kz_amqp_worker, [non_strict, no_link]),
    try Fun() after meck:unload(kz_amqp_worker) end.
