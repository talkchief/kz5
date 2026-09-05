%%% SPDX-License-Identifier: MPL-2.0
-module(acdc_callback_recovery_tests).

-include_lib("eunit/include/eunit.hrl").

-define(NOW, 63950000000).
-define(ORIGINAL, <<"original-call">>).
-define(CALLER, <<"returned-caller">>).
-define(AGENT, <<"agent-leg">>).
-define(CALLBACK,
        <<"acdc-callback-4444444444444444444444444444444444444444444444444444444444444444">>).

complete_snapshot_requires_every_node_and_explicit_call_test() ->
    ?assertEqual({error, unknown}, acdc_callback_recovery:observe_channels([?ORIGINAL], #{})),
    Stale = (snapshot(#{?ORIGINAL => terminated}, #{?ORIGINAL => terminated}))#{fresh => false},
    ?assertEqual({error, unknown}, acdc_callback_recovery:observe_channels([?ORIGINAL], Stale)),
    ?assertEqual({error, unknown}, acdc_callback_recovery:observe_channels(
                                    [?ORIGINAL], snapshot_responses([response(<<"one">>, #{?ORIGINAL => terminated})]))),
    Partial = #{expected_nodes => [<<"one">>, <<"two">>]
               ,responses => [response(<<"one">>, #{?ORIGINAL => terminated})]},
    ?assertEqual({error, unknown}, acdc_callback_recovery:observe_channels([?ORIGINAL], Partial)),
    MissingCall = snapshot(#{?ORIGINAL => terminated}, #{}),
    ?assertEqual({error, unknown}, acdc_callback_recovery:observe_channels([?ORIGINAL], MissingCall)),
    Incomplete = snapshot_responses([response(<<"one">>, #{?ORIGINAL => terminated})
                                    ,#{node => <<"two">>, complete => false,
                                       channels => #{?ORIGINAL => terminated}}]),
    ?assertEqual({error, unknown}, acdc_callback_recovery:observe_channels([?ORIGINAL], Incomplete)).

complete_snapshot_aggregates_active_from_any_node_test() ->
    Snapshot = snapshot(#{?ORIGINAL => terminated}, #{?ORIGINAL => active}),
    ?assertEqual({ok, #{?ORIGINAL => active}},
                 acdc_callback_recovery:observe_channels([?ORIGINAL], Snapshot)).

queued_live_original_waits_for_detach_test() ->
    {ok, Action, Obs} = plan(doc(<<"queued">>, []), unknown,
                             snapshot(#{?ORIGINAL => active}, #{?ORIGINAL => terminated})),
    ?assertEqual(await_original_detach, maps:get(action, Action)),
    ?assertEqual(durable_queued_live_original, maps:get(reason, Action)),
    ?assertEqual(active, maps:get(original, Obs)).

queued_dead_original_keeps_virtual_position_test() ->
    {ok, Action, _} = plan(doc(<<"queued">>, []), unknown,
                           snapshot(#{?ORIGINAL => terminated}, #{?ORIGINAL => terminated})),
    ?assertEqual(virtual_wait, maps:get(action, Action)).

valid_lease_waits_for_owner_unless_proven_dead_test() ->
    Doc = doc(<<"dialing">>, active_values(?NOW + 30)),
    Snapshot = active_snapshot(terminated, terminated, terminated, settled),
    lists:foreach(
      fun(Owner) ->
          {ok, Action, _} = plan(Doc, Owner, Snapshot),
          ?assertEqual(wait, maps:get(action, Action)),
          ?assertEqual(live_owner_lease, maps:get(reason, Action))
      end, [alive, remote, unknown]),
    {ok, DeadAction, _} = plan(Doc, dead, Snapshot),
    ?assertEqual(settle_attempt, maps:get(action, DeadAction)),
    {ok, SelfAction, _} = plan(Doc, self, Snapshot),
    ?assertEqual(settle_attempt, maps:get(action, SelfAction)).

verified_current_owner_can_rebind_with_complete_snapshot_test() ->
    Doc = connecting_doc(),
    Snapshot = active_snapshot(terminated, active, terminated, settled),
    {ok, Action, _} = plan(Doc, self, Snapshot),
    ?assertEqual(rebind_confirmed, maps:get(action, Action)),
    ?assertEqual(?CALLER, maps:get(caller_call_id, Action)),
    lists:foreach(
      fun(Owner) ->
          {ok, Wait, _} = plan(Doc, Owner, Snapshot),
          ?assertEqual(wait, maps:get(action, Wait)),
          ?assertEqual(live_owner_lease, maps:get(reason, Wait))
      end, [alive, remote, unknown]).

expired_active_pending_originate_is_cancelled_never_redialed_test() ->
    Doc = doc(<<"dialing">>, active_values(?NOW - 1)),
    Snapshot = active_snapshot(terminated, terminated, terminated, pending),
    {ok, Action, _} = plan(Doc, unknown, Snapshot),
    ?assertEqual(cancel_originate, maps:get(action, Action)),
    ?assertEqual(<<"originate-uuid">>, maps:get(originate_uuid, Action)),
    ?assertEqual(<<"originate-queue">>, maps:get(originate_queue, Action)),
    ?assertNotEqual(redial, maps:get(action, Action)).

absence_or_timeout_never_authorizes_redial_test() ->
    Doc = doc(<<"dialing">>, active_values(?NOW - 1)),
    Empty = #{expected_nodes => [<<"one">>, <<"two">>], responses => [], originate => unknown},
    {ok, Action, Obs} = plan(Doc, unknown, Empty),
    ?assertEqual(wait, maps:get(action, Action)),
    ?assertEqual(incomplete_channel_snapshot, maps:get(reason, Action)),
    ?assertEqual(unknown, maps:get(snapshot, Obs)).

connecting_confirmed_caller_rebinds_idempotently_test() ->
    Values = [{<<"pvt_lease">>, lease(?NOW - 1)}
             ,{<<"pvt_caller_call_id">>, ?CALLER}
             ,{<<"pvt_caller_control_queue">>, <<"caller-control">>}
             ,{<<"attempts">>, 2}],
    Doc = doc(<<"connecting">>, Values),
    Snapshot = active_snapshot(terminated, active, terminated, settled),
    {ok, Action, _} = plan(Doc, unknown, Snapshot),
    ?assertEqual(rebind_confirmed, maps:get(action, Action)),
    ?assertEqual(?CALLER, maps:get(caller_call_id, Action)),
    ?assertEqual(<<"caller-control">>, maps:get(caller_control_queue, Action)),
    ?assertEqual(2, maps:get(attempt, Action)).

bridge_completion_requires_exact_owned_agent_and_active_legs_test() ->
    Doc = connecting_doc(),
    Matching = (active_snapshot(terminated, active, active, settled))#{
                  bridge => #{caller_call_id => ?CALLER, agent_call_id => ?AGENT}},
    {ok, Complete, _} = plan(Doc, dead, Matching),
    ?assertEqual(complete_bridge, maps:get(action, Complete)),
    Mismatch = Matching#{bridge => #{caller_call_id => ?CALLER, agent_call_id => <<"foreign-leg">>}},
    {ok, Wait, _} = plan(Doc, dead, Mismatch),
    ?assertEqual(wait, maps:get(action, Wait)),
    ?assertEqual(conflicting_bridge_proof, maps:get(reason, Wait)),
    Down = (active_snapshot(terminated, active, terminated, settled))#{
             bridge => #{caller_call_id => ?CALLER, agent_call_id => ?AGENT}},
    {ok, DownWait, _} = plan(Doc, dead, Down),
    ?assertEqual(wait, maps:get(action, DownWait)).

settled_all_down_attempt_can_advance_without_redial_test() ->
    Doc = connecting_doc(),
    {ok, Action, _} = plan(Doc, dead, active_snapshot(terminated, terminated, terminated, settled)),
    ?assertEqual(settle_attempt, maps:get(action, Action)),
    ?assertEqual(?CALLER, maps:get(caller_call_id, Action)),
    ?assertEqual(?AGENT, maps:get(agent_call_id, Action)).

terminal_callback_resumes_only_a_live_original_test() ->
    Doc = doc(<<"cancelled">>, []),
    {ok, Resume, _} = plan(Doc, unknown, snapshot(#{?ORIGINAL => active}, #{?ORIGINAL => terminated})),
    ?assertEqual(resume_original, maps:get(action, Resume)),
    {ok, Retire, _} = plan(Doc, unknown, snapshot(#{?ORIGINAL => terminated}, #{?ORIGINAL => terminated})),
    ?assertEqual(retire, maps:get(action, Retire)).

malformed_documents_are_rejected_test() ->
    ?assertEqual({error, invalid_input}, acdc_callback_recovery:plan(kz_json:new(), ?NOW, unknown, #{})),
    ?assertEqual({error, invalid_input}, acdc_callback_recovery:plan(doc(<<"bogus">>, []), ?NOW, unknown, #{})).

plan(Doc, Owner, Snapshot) -> acdc_callback_recovery:plan(Doc, ?NOW, Owner, Snapshot).

doc(Status, Values) ->
    kz_json:set_values(
      Values,
      kz_json:from_list([{<<"_id">>, ?CALLBACK}, {<<"status">>, Status}
                        ,{<<"original_call_id">>, ?ORIGINAL}, {<<"attempts">>, 0}])).

connecting_doc() ->
    doc(<<"connecting">>, [{<<"pvt_lease">>, lease(?NOW + 30)}
                           ,{<<"pvt_caller_call_id">>, ?CALLER}
                           ,{<<"pvt_caller_control_queue">>, <<"caller-control">>}
                           ,{<<"pvt_agent_call_id">>, ?AGENT}
                           ,{<<"attempts">>, 1}]).

active_values(Until) ->
    [{<<"attempts">>, 1}
    ,{<<"pvt_lease">>, lease(Until)}
    ,{<<"pvt_caller_call_id">>, ?CALLER}
    ,{<<"pvt_originate_uuid">>, <<"originate-uuid">>}
    ,{<<"pvt_originate_queue">>, <<"originate-queue">>}].

lease(Until) -> kz_json:from_list([{<<"owner">>, <<"node:pid">>}, {<<"token">>, <<"lease-token">>}
                                        ,{<<"until">>, Until}]).

active_snapshot(Original, Caller, Agent, Originate) ->
    One = #{?ORIGINAL => Original, ?CALLER => Caller, ?AGENT => Agent},
    (snapshot(One, One))#{originate => Originate}.

snapshot(OneChannels, TwoChannels) ->
    snapshot_responses([response(<<"one">>, OneChannels), response(<<"two">>, TwoChannels)]).

snapshot_responses(Responses) ->
    #{expected_nodes => [<<"one">>, <<"two">>], responses => Responses
     ,fresh => true, originate => unknown, bridge => none}.

response(Node, Channels) -> #{node => Node, complete => true, channels => Channels}.
