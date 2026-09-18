%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2016, Voxter Communications Inc.
%%% @doc
%%% @author Daniel Finke
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(acdc_queue_manager_tests).

-include_lib("eunit/include/eunit.hrl").

-include("../src/acdc.hrl").
-include("../src/acdc_queue_manager.hrl").

-define(AGENT_ID, <<"agent_id">>).

%%% =====
%%% TESTS
%%% =====

%%------------------------------------------------------------------------------
%% @doc Test the reported count of agents when the "most idle" strategy state is
%% empty.
%% @end
%%------------------------------------------------------------------------------
agent_count_0_agents_test_() ->
    State = #state{strategy='mi'
                  ,strategy_state=#strategy_state{agents=[]}
                  },
    [?_assertEqual(0, acdc_queue_manager:assignable_agent_count(State))
    ,?_assertEqual(0, acdc_queue_manager:agent_count(State))].

%%------------------------------------------------------------------------------
%% @doc Test the reported count of agents when the "most idle" strategy state
%% has an agent added and then flagged as busy.
%% @end
%%------------------------------------------------------------------------------
agent_count_1_busy_agent_test_() ->
    State = #state{strategy='mi'
                  ,strategy_state=#strategy_state{agents=[]}
                  },
    SS1 = acdc_queue_manager:update_strategy_with_agent(State, ?AGENT_ID, 'available'),
    State1 = State#state{strategy_state=SS1},
    SS2 = acdc_queue_manager:update_strategy_with_agent(State1, ?AGENT_ID, 'busy'),
    State2 = State1#state{strategy_state=SS2},
    [?_assertEqual(0, acdc_queue_manager:assignable_agent_count(State2))
    ,?_assertEqual(1, acdc_queue_manager:agent_count(State2))].

take_position_announcement_test() ->
    CallId = <<"member-call">>,
    OtherCallId = <<"other-call">>,
    AnnouncementPid = self(),
    Pids = #{CallId => AnnouncementPid, OtherCallId => AnnouncementPid},
    ?assertEqual({AnnouncementPid, #{OtherCallId => AnnouncementPid}},
                 acdc_queue_manager:take_position_announcement(CallId, Pids)),
    ?assertEqual({'undefined', Pids},
                 acdc_queue_manager:take_position_announcement(<<"missing">>, Pids)).

logical_member_redelivery_does_not_restamp_test() ->
    with_config_defaults(fun() ->
        Original = acdc_queue_member:stamp(call(<<"original-call">>), 100, 7, 0),
        CallbackId = <<"acdc-callback-0000000000000000000000000000000000000000000000000000000000000000">>,
        {'ok', [Returned], 1, 'replaced'} =
            acdc_queue_member:replace(<<"original-call">>, CallbackId, 1,
                                      <<"returned-call">>, call(<<"returned-call">>), [Original]),
        State = #state{current_member_calls=[Returned]},
        Redelivery = kz_json:from_list([{<<"Call">>, kapps_call:to_json(call(<<"original-call">>))}]),
        ?assertEqual({'noreply', State},
                     acdc_queue_manager:handle_cast({'add_queue_member', Redelivery}, State))
    end).

resume_announcements_is_idempotent_or_skips_callback_leg_test() ->
    LogicalId = <<"original-call">>,
    Original = acdc_queue_member:stamp(call(LogicalId), 100, 7, 0),
    Existing = #state{current_member_calls=[Original]
                     ,announcements_pids=#{LogicalId => self()}},
    ?assertEqual({'reply', 'ok', Existing},
                 acdc_queue_manager:handle_call({'resume_announcements', LogicalId}, self(), Existing)),
    CallbackId = <<"acdc-callback-0000000000000000000000000000000000000000000000000000000000000000">>,
    {'ok', [Returned], 1, 'replaced'} =
        acdc_queue_member:replace(LogicalId, CallbackId, 1,
                                  <<"returned-call">>, call(<<"returned-call">>), [Original]),
    CallbackState = #state{current_member_calls=[Returned]},
    ?assertEqual({'reply', 'ok', CallbackState},
                 acdc_queue_manager:handle_call({'resume_announcements', LogicalId}, self(), CallbackState)),
    Missing = #state{},
    ?assertEqual({'reply', 'ok', Missing},
                 acdc_queue_manager:handle_call({'resume_announcements', LogicalId}, self(), Missing)).

legacy_recovery_preserves_existing_service_order_test() ->
    %% current_member_calls is reverse service order: first -> second -> third.
    Legacy = [account_call(<<"third">>), account_call(<<"second">>),
              account_call(<<"first">>)],
    {'ok', Migrated, 2, Existing} =
        acdc_queue_manager:ensure_legacy_member(account_call(<<"second">>), Legacy),
    ?assertEqual([<<"first">>, <<"second">>, <<"third">>],
                 [acdc_queue_member:logical_id(Call)
                  || Call <- lists:reverse(Migrated)]),
    ?assertEqual({0, 1, 1, <<"second">>},
                 acdc_queue_member:member_order_key(Existing)).

lost_legacy_recovery_appends_without_current_time_restamp_test() ->
    Legacy = [account_call(<<"second">>), account_call(<<"first">>)],
    {'ok', Migrated, 3, Canonical} =
        acdc_queue_manager:ensure_legacy_member(account_call(<<"lost">>), Legacy),
    ?assertEqual([<<"first">>, <<"second">>, <<"lost">>],
                 [acdc_queue_member:logical_id(Call)
                  || Call <- lists:reverse(Migrated)]),
    ?assertEqual({0, 1, 2, <<"lost">>},
                 acdc_queue_member:member_order_key(Canonical)).

mixed_legacy_and_modern_metadata_fails_closed_test() ->
    Modern = acdc_queue_member:stamp(account_call(<<"modern">>), 100, 1, 0),
    ?assertEqual({'error', 'legacy_mixed_metadata'},
                 acdc_queue_manager:ensure_legacy_member(
                   account_call(<<"lost">>), [Modern, account_call(<<"legacy">>)])).

callback_recovery_validates_scope_identity_and_immutable_metadata_test() ->
    Doc = callback_doc(<<"queued">>),
    Original = account_call(<<"original-call">>),
    {'ok', <<"original-call">>, CallbackId, 0, 'undefined', Restored} =
        acdc_queue_manager:callback_recovery_call(
          account_id(), queue_id(), Original, Doc),
    ?assertEqual(callback_id(), CallbackId),
    ?assertEqual({-3, 100, 7, <<"original-call">>},
                 acdc_queue_member:member_order_key(Restored)),
    InvalidDocs = [kz_json:set_value(<<"pvt_account_id">>, <<"wrong-account">>, Doc)
                  ,kz_json:set_value(<<"queue_id">>, <<"wrong-queue">>, Doc)
                  ,kz_json:set_value(<<"original_call_id">>, <<"wrong-call">>, Doc)
                  ,kz_json:set_value(<<"pvt_type">>, <<"wrong-type">>, Doc)
                  ,kz_json:set_value(<<"_id">>, <<"bad-id">>, Doc)],
    lists:foreach(
      fun(InvalidDoc) ->
          ?assertEqual({'error', 'invalid_callback_proof'},
                       acdc_queue_manager:callback_recovery_call(
                         account_id(), queue_id(), Original, InvalidDoc))
      end, InvalidDocs),
    MissingMetadata = [kz_json:delete_key(Key, Doc)
                       || Key <- [<<"enqueued_at">>, <<"enqueue_sequence">>, <<"priority">>]],
    lists:foreach(
      fun(InvalidDoc) ->
          ?assertEqual({'error', 'invalid_callback_metadata'},
                       acdc_queue_manager:callback_recovery_call(
                         account_id(), queue_id(), Original, InvalidDoc))
      end, MissingMetadata).

callback_recovery_restores_returned_leg_identity_test() ->
    Doc = kz_json:set_values([{<<"status">>, <<"connecting">>}
                             ,{<<"attempts">>, 2}
                             ,{<<"pvt_caller_call_id">>, <<"returned-leg">>}],
                            callback_doc(<<"queued">>)),
    {'ok', <<"original-call">>, CallbackId, 2, <<"returned-leg">>, Restored} =
        acdc_queue_manager:callback_recovery_call(
          account_id(), queue_id(), account_call(<<"returned-leg">>), Doc),
    ?assertEqual(callback_id(), CallbackId),
    ?assertEqual(<<"original-call">>, acdc_queue_member:logical_id(Restored)),
    ?assertEqual(<<"returned-leg">>, acdc_queue_member:physical_id(Restored)),
    ?assert(acdc_queue_manager:valid_recovered_existing(
              Restored, Doc, CallbackId, 2, <<"returned-leg">>)),
    ?assertNot(acdc_queue_manager:valid_recovered_existing(
                 Restored, kz_json:set_value(<<"enqueue_sequence">>, 8, Doc),
                 CallbackId, 2, <<"returned-leg">>)).

ensure_callback_member_inserts_canonical_returned_leg_test() ->
    with_queue_api(fun() ->
        meck:expect(kapi_acdc_queue, publish_queue_member_add, fun(_) -> 'ok' end),
        Doc = kz_json:set_values([{<<"status">>, <<"connecting">>}
                                ,{<<"attempts">>, 2}
                                ,{<<"pvt_caller_call_id">>, <<"returned-leg">>}],
                               callback_doc(<<"queued">>)),
        State = #state{account_id=account_id(), queue_id=queue_id()},
        {'reply', {'ok', 1, Canonical}, State1} =
            acdc_queue_manager:handle_call(
              {'ensure_callback_member', account_call(<<"returned-leg">>), Doc}, self(), State),
        ?assertEqual([Canonical], State1#state.current_member_calls),
        ?assertEqual(<<"original-call">>, acdc_queue_member:logical_id(Canonical)),
        ?assertEqual(callback_id(),
                     kapps_call:kvs_fetch(<<"acdc_callback_id">>, Canonical)),
        ?assertEqual(1, meck:num_calls(kapi_acdc_queue, publish_queue_member_add, '_'))
    end).

terminal_retirement_publication_failure_preserves_member_test() ->
    with_retirement_mocks(
      fun() ->
          meck:expect(kz_amqp_worker, cast, fun(_, _) -> {'error', 'unavailable'} end),
          State = terminal_state(),
          ?assertEqual({'reply', {'error', 'publish_failed'}, State},
                       acdc_queue_manager:handle_call(
                         {'retire_callback_member', <<"original-call">>, callback_id()},
                         self(), State))
      end).

terminal_retirement_rejects_wrong_document_scope_test() ->
    with_retirement_mocks(
      fun() ->
          meck:expect(acdc_callback_store, get,
                      fun(_, _, _) ->
                          {'ok', kz_json:set_value(<<"queue_id">>, <<"wrong-queue">>,
                                                   callback_doc(<<"completed">>))}
                      end),
          meck:expect(kz_amqp_worker, cast, fun(_, _) -> error(unexpected_publish) end),
          State = terminal_state(),
          ?assertEqual({'reply', {'error', 'not_terminal'}, State},
                       acdc_queue_manager:handle_call(
                         {'retire_callback_member', <<"original-call">>, callback_id()},
                         self(), State)),
          ?assertEqual(0, meck:num_calls(kz_amqp_worker, cast, '_'))
      end).

repeated_completed_member_retirement_is_idempotent_test() ->
    with_retirement_mocks(
      fun() ->
          meck:expect(kz_amqp_worker, cast, fun(_, _) -> 'ok' end),
          State0 = terminal_state(),
          {'reply', 'ok', State1} = acdc_queue_manager:handle_call(
                                      {'retire_callback_member', <<"original-call">>, callback_id()},
                                      self(), State0),
          ?assertEqual([], State1#state.current_member_calls),
          {'reply', 'ok', State2} = acdc_queue_manager:handle_call(
                                      {'retire_callback_member', <<"original-call">>, callback_id()},
                                      self(), State1),
          ?assertEqual([], State2#state.current_member_calls),
          ?assertEqual(2, meck:num_calls(kz_amqp_worker, cast, '_'))
      end).

terminal_state() ->
    Member = acdc_queue_member:stamp(account_call(<<"original-call">>), 100, 7, 3),
    #state{account_id=account_id(), queue_id=queue_id(), current_member_calls=[Member]}.

with_queue_api(Fun) ->
    meck:new(kapi_acdc_queue, [non_strict, no_link]),
    meck:new(kapps_call, [passthrough, no_link]),
    meck:expect(kapps_call, set_custom_channel_var,
                fun(Key, Value, Call) ->
                    kapps_call:insert_custom_channel_var(Key, Value, Call)
                end),
    try Fun()
    after
        meck:unload(kapps_call),
        meck:unload(kapi_acdc_queue)
    end.

with_retirement_mocks(Fun) ->
    meck:new(acdc_callback_store, [non_strict, no_link]),
    meck:new(kz_amqp_worker, [non_strict, no_link]),
    meck:expect(acdc_callback_store, get,
                fun(_, _, _) -> {'ok', callback_doc(<<"completed">>)} end),
    try Fun()
    after
        meck:unload(kz_amqp_worker),
        meck:unload(acdc_callback_store)
    end.

callback_doc(Status) ->
    kz_json:from_list([{<<"_id">>, callback_id()}
                      ,{<<"pvt_type">>, <<"acdc_callback">>}
                      ,{<<"pvt_account_id">>, account_id()}
                      ,{<<"queue_id">>, queue_id()}
                      ,{<<"original_call_id">>, <<"original-call">>}
                      ,{<<"enqueued_at">>, 100}
                      ,{<<"enqueue_sequence">>, 7}
                      ,{<<"priority">>, 3}
                      ,{<<"attempts">>, 0}
                      ,{<<"status">>, Status}]).

callback_id() ->
    <<"acdc-callback-0000000000000000000000000000000000000000000000000000000000000000">>.

account_id() -> <<"11111111111111111111111111111111">>.
queue_id() -> <<"queue-one">>.

account_call(Id) ->
    %% from_json/1 is command-free. Its production caller-ID defaults consult
    %% kapps_config eagerly, so keep those reads local to this isolated fixture.
    with_config_defaults(
      fun() ->
          kapps_call:from_json(
            kz_json:from_list([{<<"Call-ID">>, Id}
                              ,{<<"Account-ID">>, account_id()}
                              ,{<<"Caller-ID-Name">>, <<"caller">>}
                              ,{<<"Caller-ID-Number">>, <<"1000">>}
                              ,{<<"Language">>, <<"en-us">>}
                              ,{<<"Controller-Queue">>, <<"controller">>}
                              ,{<<"Control-Queue">>, <<"control">>}]))
      end).

call(Id) ->
    kapps_call:set_language(
      <<"en-us">>,
      kapps_call:set_controller_queue(
        <<"controller">>,
        kapps_call:set_control_queue(
          <<"control">>, kapps_call:set_call_id(Id, kapps_call:new())))).

with_config_defaults(Fun) ->
    %% This fixture needs only the four explicit default readers below. Avoid
    %% recompiling the entire configuration module for every synthetic call;
    %% an unexpected reader must fail instead of reaching real configuration.
    meck:new(kapps_config, [non_strict, no_link]),
    meck:expect(kapps_config, get_ne_binary, fun(_, _, Default) -> Default end),
    meck:expect(kapps_config, get_ne_binary, fun(_, _, Default, _) -> Default end),
    meck:expect(kapps_config, get_binary, fun(_, _, Default) -> Default end),
    meck:expect(kapps_config, get_binary, fun(_, _, Default, _) -> Default end),
    try Fun() after meck:unload(kapps_config) end.

%%% Member liveness reconciliation: a manager that missed member_remove or
%%% call_success (broker outage) kept a finished caller as a waiting member
%%% forever (kz5-stage-queue-partition-10).
reconcile_member(Id) -> kapps_call:set_call_id(Id, kapps_call:new()).
reconcile_callback_member(Id) ->
    kapps_call:kvs_store(<<"acdc_callback_id">>, <<"callback-1">>, reconcile_member(Id)).
reconcile_state(Calls, Seen) ->
    Ref = make_ref(),
    {Ref, #state{account_id = <<"account">>, queue_id = <<"queue">>, current_member_calls = Calls
                ,member_reconcile = #{'timer' => Ref, 'seen' => Seen}}}.
observation(Id, Fields) ->
    {'ok', #{'complete' => 'true', 'bridge' => #{}, 'reasons' => []
            ,'channels' => [maps:merge(#{'call_id' => Id, 'responders' => [<<"ecallmgr@a">>]}, Fields)]}}.
long_ago() -> erlang:monotonic_time('millisecond') - 120000.
tick(Ref, State) ->
    {'noreply', Next} = acdc_queue_manager:handle_info({'timeout', Ref, 'member_reconcile'}, State),
    Next.
member_ids(#state{current_member_calls=Calls}) -> [kapps_call:call_id(C) || C <- Calls].
liveness(State) ->
    Ref = maps:get('probe_ref', State#state.member_reconcile),
    receive {'member_liveness', Ref, _}=Msg -> Msg after 3000 -> error('no_liveness_result') end.

with_observations(Fun) ->
    meck:new('acdc_callback_recovery_io', ['non_strict', 'no_link']),
    try Fun() after meck:unload('acdc_callback_recovery_io') end.

stale_members_are_removed_only_on_complete_evidence_test() ->
    with_observations(
      fun() ->
          Answers = #{<<"ended">> => observation(<<"ended">>, #{'state' => 'terminated'})
                     ,<<"talking">> => observation(<<"talking">>, #{'state' => 'active', 'answered' => 'true'
                                                                     ,'other_leg_call_id' => <<"agent-leg">>})
                     ,<<"waiting">> => observation(<<"waiting">>, #{'state' => 'active', 'answered' => 'true'})
                     ,<<"unknown">> => {'unknown', #{'complete' => 'false'}}
                     ,<<"no-responders">> => observation(<<"no-responders">>, #{'state' => 'terminated', 'responders' => []})
                     },
          meck:expect('acdc_callback_recovery_io', 'observe_channels'
                     ,fun(<<"account">>, [Id]) -> maps:get(Id, Answers) end),
          Ids = maps:keys(Answers),
          {Ref, State} = reconcile_state([reconcile_member(Id) || Id <- Ids]
                                        ,maps:from_list([{Id, long_ago()} || Id <- Ids])),
          Probing = tick(Ref, State),
          ?assertEqual(lists:sort(Ids), lists:sort(member_ids(Probing))),
          {'noreply', Done} = acdc_queue_manager:handle_info(liveness(Probing), Probing),
          ?assertEqual([<<"no-responders">>, <<"unknown">>, <<"waiting">>], lists:sort(member_ids(Done))),
          ?assertNot(maps:is_key('probe_ref', Done#state.member_reconcile)),
          %% The timer is re-armed on every tick and a stale result changes nothing.
          ?assertNotEqual(Ref, maps:get('timer', Probing#state.member_reconcile)),
          ?assert(is_integer(erlang:read_timer(maps:get('timer', Probing#state.member_reconcile)))),
          Stale = {'member_liveness', make_ref(), [{<<"waiting">>, maps:get(<<"ended">>, Answers)}]},
          ?assertEqual({'noreply', Done}, acdc_queue_manager:handle_info(Stale, Done)),
          ?assertEqual({'noreply', Done}, acdc_queue_manager:handle_info({'timeout', make_ref(), 'member_reconcile'}, Done))
      end).

new_and_callback_members_are_never_examined_test() ->
    with_observations(
      fun() ->
          meck:expect('acdc_callback_recovery_io', 'observe_channels'
                     ,fun(_, [Id]) -> observation(Id, #{'state' => 'terminated'}) end),
          %% A callback member has no caller channel by design; a new caller may be answered any moment.
          Calls = [reconcile_callback_member(<<"callback-wait">>), reconcile_member(<<"just-arrived">>)],
          {Ref, State} = reconcile_state(Calls, #{<<"callback-wait">> => long_ago()}),
          First = tick(Ref, State),
          ?assertNot(maps:is_key('probe_ref', First#state.member_reconcile)),
          ?assertEqual(0, meck:num_calls('acdc_callback_recovery_io', 'observe_channels', '_')),
          ?assertEqual([<<"just-arrived">>], maps:keys(maps:get('seen', First#state.member_reconcile))),
          ?assertEqual([<<"callback-wait">>, <<"just-arrived">>], lists:sort(member_ids(First))),
          %% A forged result for the callback member is ignored as well.
          Forged = First#state{member_reconcile=(First#state.member_reconcile)#{'probe_ref' => Ref}},
          {'noreply', Kept} = acdc_queue_manager:handle_info(
                                {'member_liveness', Ref, [{<<"callback-wait">>, observation(<<"callback-wait">>, #{'state' => 'terminated'})}]}
                               ,Forged),
          ?assertEqual([<<"callback-wait">>, <<"just-arrived">>], lists:sort(member_ids(Kept)))
      end).

reconciliation_is_bounded_and_replaces_a_hung_probe_test() ->
    with_observations(
      fun() ->
          Parent = self(),
          meck:expect('acdc_callback_recovery_io', 'observe_channels'
                     ,fun(_, [Id]) -> Parent ! {'probed', Id}, receive 'never' -> 'ok' end end),
          Ids = [<<"m", (integer_to_binary(N))/binary>> || N <- lists:seq(1, 9)],
          {Ref, State} = reconcile_state([reconcile_member(Id) || Id <- Ids]
                                        ,maps:from_list([{Id, long_ago()} || Id <- Ids])),
          Hung = tick(Ref, State),
          HungPid = maps:get('probe_pid', Hung#state.member_reconcile),
          receive {'probed', <<"m1">>} -> 'ok' after 2000 -> error('probe_not_started') end,
          Monitor = erlang:monitor('process', HungPid),
          Next = tick(maps:get('timer', Hung#state.member_reconcile), Hung),
          receive {'DOWN', Monitor, 'process', HungPid, 'killed'} -> 'ok' after 2000 -> error('hung_probe_survived') end,
          ?assertNotEqual(HungPid, maps:get('probe_pid', Next#state.member_reconcile)),
          exit(maps:get('probe_pid', Next#state.member_reconcile), 'kill'),
          ?assertEqual(9, length(member_ids(Next)))
      end).

reconciliation_examines_at_most_five_members_per_tick_test() ->
    with_observations(
      fun() ->
          meck:expect('acdc_callback_recovery_io', 'observe_channels'
                     ,fun(_, [Id]) -> observation(Id, #{'state' => 'terminated'}) end),
          Ids = [<<"m", (integer_to_binary(N))/binary>> || N <- lists:seq(1, 9)],
          {Ref, State} = reconcile_state([reconcile_member(Id) || Id <- Ids]
                                        ,maps:from_list([{Id, long_ago()} || Id <- Ids])),
          Probing = tick(Ref, State),
          {'noreply', Done} = acdc_queue_manager:handle_info(liveness(Probing), Probing),
          ?assertEqual(5, meck:num_calls('acdc_callback_recovery_io', 'observe_channels', '_')),
          ?assertEqual(4, length(member_ids(Done)))
      end).
