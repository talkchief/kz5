%%% SPDX-License-Identifier: MPL-2.0
-module(acdc_callback_reconcile_tests).

-include_lib("eunit/include/eunit.hrl").

-define(NOW, 63950000000).
-define(ACCOUNT, <<"11111111111111111111111111111111">>).
-define(ORIGINAL, <<"original-call">>).
-define(CALLER, <<"returned-caller">>).
-define(AGENT, <<"agent-leg">>).
-define(CALLBACK,
        <<"acdc-callback-5555555555555555555555555555555555555555555555555555555555555555">>).

complete_snapshot_requires_one_consistent_responder_set_test() ->
    Doc = active_doc(<<"dialing">>),
    Evidence = evidence([channel(?ORIGINAL, terminated, responder_nodes())
                        ,channel(?CALLER, terminated, [<<"one">>])], settled),
    assert_wait(inconsistent_channel_snapshot,
                acdc_callback_reconcile:plan(Doc, ?NOW, dead, Evidence)),
    Duplicate = evidence([channel(?ORIGINAL, terminated, responder_nodes())
                         ,channel(?ORIGINAL, terminated, responder_nodes())], settled),
    assert_wait(inconsistent_channel_snapshot,
                acdc_callback_reconcile:plan(Doc, ?NOW, dead, Duplicate)).

active_channel_requires_a_declared_responder_from_complete_set_test() ->
    Doc = active_doc(<<"connecting">>),
    Missing = evidence([channel(?ORIGINAL, terminated, responder_nodes())
                       ,channel(?CALLER, active, responder_nodes())
                       ,channel(?AGENT, terminated, responder_nodes())], settled),
    assert_wait(inconsistent_channel_snapshot,
                acdc_callback_reconcile:plan(Doc, ?NOW, dead, Missing)),
    Foreign = evidence([channel(?ORIGINAL, terminated, responder_nodes())
                       ,(channel(?CALLER, active, responder_nodes()))#{active_responder => <<"foreign">>}
                       ,channel(?AGENT, terminated, responder_nodes())], settled),
    assert_wait(inconsistent_channel_snapshot,
                acdc_callback_reconcile:plan(Doc, ?NOW, dead, Foreign)).

pending_or_unknown_originate_never_settles_attempt_test() ->
    Doc = active_doc(<<"dialing">>),
    Channels = [channel(?ORIGINAL, terminated, responder_nodes())
               ,channel(?CALLER, terminated, responder_nodes())
               ,channel(?AGENT, terminated, responder_nodes())],
    {ok, Pending, _} = acdc_callback_reconcile:plan(
                         Doc, ?NOW, dead, evidence(Channels, pending)),
    ?assertEqual(cancel_originate, maps:get(action, Pending)),
    ?assertNotEqual(settle_attempt, maps:get(action, Pending)),
    {ok, Unknown, _} = acdc_callback_reconcile:plan(
                         Doc, ?NOW, dead, evidence(Channels, unknown)),
    ?assertEqual(wait, maps:get(action, Unknown)),
    ?assertNotEqual(settle_attempt, maps:get(action, Unknown)).

bridge_is_only_a_request_for_native_agent_proof_test() ->
    Doc = active_doc(<<"connecting">>),
    Channels = [channel(?ORIGINAL, terminated, responder_nodes())
               ,active_channel(?CALLER, <<"one">>)
               ,active_channel(?AGENT, <<"one">>)],
    Evidence = (evidence(Channels, settled))#{
                 bridge => #{state => bridged, call_ids => [?CALLER, ?AGENT]}},
    {ok, Action, _} = acdc_callback_reconcile:plan(Doc, ?NOW, dead, Evidence),
    ?assertEqual(prove_bridge, maps:get(action, Action)),
    ?assertNotEqual(complete_bridge, maps:get(action, Action)),
    ?assertEqual(?CALLER, maps:get(caller_call_id, Action)),
    ?assertEqual(?AGENT, maps:get(agent_call_id, Action)),
    ConflictDoc = kz_json:set_value(<<"pvt_agent_call_id">>, <<"other-agent">>, Doc),
    assert_wait(conflicting_bridge_proof,
                acdc_callback_reconcile:plan(ConflictDoc, ?NOW, dead, Evidence)).

malformed_bridge_evidence_fails_closed_test() ->
    Doc = active_doc(<<"connecting">>),
    Evidence = (evidence([channel(?ORIGINAL, terminated, responder_nodes())
                         ,active_channel(?CALLER, <<"one">>)
                         ,active_channel(?AGENT, <<"one">>)], settled))#{
                 bridge => #{state => bridged, call_ids => <<"not-a-list">>}},
    assert_wait(conflicting_bridge_proof,
                acdc_callback_reconcile:plan(Doc, ?NOW, dead, Evidence)).

restore_call_rejects_account_or_original_identity_mixup_test() ->
    Original = original_call(),
    Doc = active_doc(<<"connecting">>),
    {ok, Returned} = acdc_callback_reconcile:restore_call(Doc, Original),
    ?assertEqual(?CALLER, kapps_call:call_id(Returned)),
    ?assertEqual(<<"caller-control">>, kapps_call:control_queue(Returned)),
    ?assertEqual({error, invalid_call},
                 acdc_callback_reconcile:restore_call(
                   kz_json:set_value(<<"pvt_account_id">>, <<"wrong-account">>, Doc), Original)),
    ?assertEqual({error, invalid_call},
                 acdc_callback_reconcile:restore_call(
                   kz_json:set_value(<<"original_call_id">>, <<"wrong-original">>, Doc), Original)),
    ?assertEqual({error, invalid_call},
                 acdc_callback_reconcile:restore_call(
                   kz_json:set_value(<<"pvt_type">>, <<"wrong-type">>, Doc), Original)),
    ?assertEqual({error, invalid_call},
                 acdc_callback_reconcile:restore_call(
                   kz_json:delete_key(<<"pvt_caller_control_queue">>, Doc), Original)).

self_owner_authority_requires_exact_durable_token_test() ->
    Owner = iolist_to_binary([atom_to_binary(node(), utf8), <<":">>, pid_to_list(self())]),
    Doc = kz_json:set_value(
            <<"pvt_lease">>,
            kz_json:from_list([{<<"owner">>, Owner}
                              ,{<<"token">>, <<"durable-token">>}
                              ,{<<"until">>, ?NOW + 30}]),
            active_doc(<<"dialing">>)),
    ?assertEqual(alive, acdc_callback_reconcile:owner(Doc)),
    ?assertEqual(alive, acdc_callback_reconcile:owner(Doc, <<"wrong-token">>)),
    ?assertEqual(alive, acdc_callback_reconcile:owner(Doc, undefined)),
    ?assertEqual(self, acdc_callback_reconcile:owner(Doc, <<"durable-token">>)).

incomplete_or_unknown_evidence_cannot_authorize_action_test() ->
    Doc = active_doc(<<"dialing">>),
    assert_wait(incomplete_channel_snapshot,
                acdc_callback_reconcile:plan(Doc, ?NOW, dead, #{})),
    UnknownChannel = evidence([#{call_id => ?ORIGINAL, state => unknown,
                                 responders => responder_nodes()}], settled),
    assert_wait(inconsistent_channel_snapshot,
                acdc_callback_reconcile:plan(Doc, ?NOW, dead, UnknownChannel)).

assert_wait(Reason, {ok, Action, _}) ->
    ?assertEqual(wait, maps:get(action, Action)),
    ?assertEqual(Reason, maps:get(reason, Action)).

active_doc(Status) ->
    kz_json:from_list([{<<"_id">>, ?CALLBACK}
                      ,{<<"pvt_type">>, <<"acdc_callback">>}
                      ,{<<"pvt_account_id">>, ?ACCOUNT}
                      ,{<<"queue_id">>, <<"queue-one">>}
                      ,{<<"original_call_id">>, ?ORIGINAL}
                      ,{<<"status">>, Status}
                      ,{<<"attempts">>, 2}
                      ,{<<"pvt_caller_call_id">>, ?CALLER}
                      ,{<<"pvt_caller_control_queue">>, <<"caller-control">>}
                      ,{<<"pvt_agent_call_id">>, ?AGENT}
                      ,{<<"pvt_originate_uuid">>, <<"originate-uuid">>}
                      ,{<<"pvt_originate_queue">>, <<"originate-queue">>}
                      ,{<<"pvt_lease">>, kz_json:from_list(
                                             [{<<"owner">>, <<"node:pid">>}
                                             ,{<<"token">>, <<"lease-token">>}
                                             ,{<<"until">>, ?NOW - 1}])}]).

evidence(Channels, Originate) ->
    #{complete => true, channels => Channels, originate => Originate,
      bridge => #{state => not_observed}}.

responder_nodes() -> [<<"one">>, <<"two">>].

channel(CallId, State, Responders) ->
    #{call_id => CallId, state => State, responders => Responders}.

active_channel(CallId, Responder) ->
    (channel(CallId, active, responder_nodes()))#{active_responder => Responder}.

original_call() ->
    kapps_call:set_account_id(
      ?ACCOUNT,
      kapps_call:set_language(
        <<"en-us">>,
        kapps_call:set_control_queue(
          <<"original-control">>, kapps_call:set_call_id(?ORIGINAL, kapps_call:new())))).
