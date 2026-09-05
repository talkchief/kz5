%%% SPDX-License-Identifier: MPL-2.0
-module(acdc_callback_queue_fsm_tests).
-include_lib("eunit/include/eunit.hrl").

%% Mock compilation is CPU-bound on the two-vCPU acceptance host. Give each
%% unchanged behavioral assertion its own bounded 30-second setup/run window.
callback_queue_test_() ->
    [
     {"pause_is_acknowledged_before_menu", {timeout, 30, fun pause_is_acknowledged_before_menu_case/0}}
    ,     {"stale_member_cannot_pause_new_member", {timeout, 30, fun stale_member_cannot_pause_new_member_case/0}}
    ,     {"agent_win_closes_menu_pause_window", {timeout, 30, fun agent_win_closes_menu_pause_window_case/0}}
    ,     {"duplicate_pause_does_not_extend_deadline", {timeout, 30, fun duplicate_pause_does_not_extend_deadline_case/0}}
    ,     {"stale_pause_and_wrong_ticket_are_rejected", {timeout, 30, fun stale_pause_and_wrong_ticket_are_rejected_case/0}}
    ,     {"expected_original_hangup_keeps_virtual_slot", {timeout, 30, fun expected_original_hangup_keeps_virtual_slot_case/0}}
    ,     {"unrelated_original_hangup_cannot_release_slot", {timeout, 30, fun unrelated_original_hangup_cannot_release_slot_case/0}}
    ,     {"ready_is_persisted_before_execute_ack", {timeout, 30, fun ready_is_persisted_before_execute_ack_case/0}}
    ,     {"failed_ready_commit_cancels_without_execute", {timeout, 30, fun failed_ready_commit_cancels_without_execute_case/0}}
    ,     {"stale_worker_events_and_timers_do_not_crash_native_state", {timeout, 30, fun stale_worker_events_and_timers_do_not_crash_native_state_case/0}}
    ,     {"stale_cancel_cannot_abandon_another_paused_call", {timeout, 30, fun stale_cancel_cannot_abandon_another_paused_call_case/0}}
    ,     {"native_hangup_does_not_ack_before_durable_cleanup", {timeout, 30, fun native_hangup_does_not_ack_before_durable_cleanup_case/0}}
    ,     {"native_cancellation_retains_delivery_until_channels_settle", {timeout, 30, fun native_cancellation_retains_delivery_until_channels_settle_case/0}}
    ,     {"bridge_without_acceptance_has_bounded_proof_deadline", {timeout, 30, fun bridge_without_acceptance_has_bounded_proof_deadline_case/0}}
    ,     {"accepted_snapshot_probe_deadline_retains_delivery", {timeout, 30, fun accepted_snapshot_probe_deadline_retains_delivery_case/0}}
    ,     {"acceptance_from_unselected_agent_is_ignored", {timeout, 30, fun acceptance_from_unselected_agent_is_ignored_case/0}}
    ,     {"native_retry_clears_old_agent_proof", {timeout, 30, fun native_retry_clears_old_agent_proof_case/0}}
    ,     {"native_acceptance_requires_exact_agent_leg", {timeout, 30, fun native_acceptance_requires_exact_agent_leg_case/0}}
    ,     {"native_conflicting_proofs_do_not_overwrite_first_identity", {timeout, 30, fun native_conflicting_proofs_do_not_overwrite_first_identity_case/0}}
    ,     {"abandon_active_attempt_enters_reconciliation_not_cancel_poll", {timeout, 30, fun abandon_active_attempt_enters_reconciliation_not_cancel_poll_case/0}}
    ,     {"lookup_outage_cannot_open_a_second_callback_menu", {timeout, 30, fun lookup_outage_cannot_open_a_second_callback_menu_case/0}}
    ,     {"registration_rejection_preserves_pause_for_explicit_resume", {timeout, 30, fun registration_rejection_preserves_pause_for_explicit_resume_case/0}}
    ,     {"delayed_resume_ack_is_replayed_without_restarting_menu", {timeout, 30, fun delayed_resume_ack_is_replayed_without_restarting_menu_case/0}}
    ,     {"incomplete_recovery_evidence_never_releases_or_redials", {timeout, 30, fun incomplete_recovery_evidence_never_releases_or_redials_case/0}}
    ,     {"stale_recovery_generation_is_ignored", {timeout, 30, fun stale_recovery_generation_is_ignored_case/0}}
    ,     {"listener_retirement_failure_keeps_delivery_unacknowledged", {timeout, 30, fun listener_retirement_failure_keeps_delivery_unacknowledged_case/0}}
    ,     {"listener_retires_manager_slot_before_ack", {timeout, 30, fun listener_retires_manager_slot_before_ack_case/0}}
    ].

-define(ACCOUNT, <<"11111111111111111111111111111111">>).
-define(QUEUE, <<"callback-test">>).
-define(CALL, <<"original-call">>).
-define(REQUEST, <<"22222222222222222222222222222222">>).
-define(TOKEN, <<"333333333333333333333333333333333333333333333333">>).
-define(CALLBACK, <<"acdc-callback-4444444444444444444444444444444444444444444444444444444444444444">>).

pause_is_acknowledged_before_menu_case() -> with_mocks(fun() ->
    Initial = state([]),
    {next_state, callback_paused, Paused} = acdc_queue_fsm:ready(cast, {callback_request, request(<<"pause">>)}, Initial),
    Context = field(callback_ctx, Paused),
    ?assertEqual(field(member_call, Initial), field(member_call, Paused)),
    ?assertEqual(48, byte_size(maps:get(pause_id, Context))),
    ?assertEqual(<<"paused">>, kz_json:get_value(<<"Status">>, get(response))),
    ?assertEqual(1, meck:num_calls(acdc_queue_manager, stop_announcements, [self(), ?CALL])),
    ?assertEqual(0, meck:num_calls(acdc_queue_listener, member_connect_req, '_')),
    cancel_timer(Paused)
end).

stale_member_cannot_pause_new_member_case() -> with_mocks(fun() ->
    Request = kz_json:set_value(<<"Call-ID">>, <<"old-call">>, request(<<"pause">>)),
    Initial = state([]),
    ?assertEqual({next_state, ready, Initial}, acdc_queue_fsm:ready(cast, {callback_request, Request}, Initial)),
    ?assertEqual(<<"rejected">>, kz_json:get_value(<<"Status">>, get(response))),
    ?assertEqual(0, meck:num_calls(acdc_queue_manager, stop_announcements, '_'))
end).

agent_win_closes_menu_pause_window_case() -> with_mocks(fun() ->
    Initial = state([{connect_wins, [kz_json:new()]}]),
    ?assertEqual({next_state, connect_req, Initial},
                 acdc_queue_fsm:connect_req(cast, {callback_request, request(<<"pause">>)}, Initial)),
    ?assertEqual(<<"busy">>, kz_json:get_value(<<"Failure-Reason">>, get(response))),
    Connecting = state([]),
    ?assertEqual({next_state, connecting, Connecting},
                 acdc_queue_fsm:connecting(cast, {callback_request, request(<<"pause">>)}, Connecting)),
    ?assertEqual(0, meck:num_calls(acdc_queue_manager, stop_announcements, '_'))
end).

duplicate_pause_does_not_extend_deadline_case() -> with_mocks(fun() ->
    {next_state, callback_paused, Paused} = acdc_queue_fsm:ready(cast, {callback_request, request(<<"pause">>)}, state([])),
    Context = field(callback_ctx, Paused),
    {keep_state, Again} = acdc_queue_fsm:callback_paused(cast, {callback_request, request(<<"pause">>)}, Paused),
    ?assertEqual(Context, field(callback_ctx, Again)),
    ?assertEqual(1, meck:num_calls(acdc_queue_manager, stop_announcements, '_')),
    cancel_timer(Paused)
end).

stale_pause_and_wrong_ticket_are_rejected_case() -> with_mocks(fun() ->
    {next_state, callback_paused, Paused} = acdc_queue_fsm:ready(cast, {callback_request, request(<<"pause">>)}, state([])),
    WrongPause = kz_json:set_value(<<"Pause-ID">>, ?TOKEN, request(<<"resume">>)),
    ?assertEqual({keep_state, Paused}, acdc_queue_fsm:callback_paused(cast, {callback_request, WrongPause}, Paused)),
    Context = field(callback_ctx, Paused),
    WrongTicket = kz_json:set_values([{<<"Pause-ID">>, maps:get(pause_id, Context)}, {<<"Callback-ID">>, ?CALLBACK}], request(<<"resume">>)),
    ?assertEqual({keep_state, Paused}, acdc_queue_fsm:callback_paused(cast, {callback_request, WrongTicket}, Paused)),
    ?assertEqual(0, meck:num_calls(acdc_callback_store, cancel, '_')),
    cancel_timer(Paused)
end).

expected_original_hangup_keeps_virtual_slot_case() -> with_mocks(fun() ->
    Context = context(awaiting_destroy),
    Initial = state([{callback_ctx, Context}]),
    Event = kz_json:from_list([{<<"Call-ID">>, ?CALL}]),
    {next_state, callback_waiting, Waiting} = acdc_queue_fsm:callback_waiting(cast, {member_hungup, Event}, Initial),
    ?assertEqual(virtual, maps:get(mode, field(callback_ctx, Waiting))),
    ?assertEqual(field(member_call, Initial), field(member_call, Waiting)),
    ?assertEqual(0, meck:num_calls(acdc_queue_listener, cancel_member_call, '_')),
    ?assertEqual(0, meck:num_calls(acdc_queue_listener, retire_callback_member, '_')),
    cancel_timer(Waiting)
end).

unrelated_original_hangup_cannot_release_slot_case() -> with_mocks(fun() ->
    Initial = state([{callback_ctx, context(awaiting_destroy)}]),
    Event = kz_json:from_list([{<<"Call-ID">>, <<"other-call">>}]),
    ?assertEqual({keep_state, Initial}, acdc_queue_fsm:callback_waiting(cast, {member_hungup, Event}, Initial))
end).

ready_is_persisted_before_execute_ack_case() -> with_mocks(fun() ->
    Initial = state([{callback_ctx, context(dialing)}]),
    meck:expect(acdc_callback_store, bind_originate, fun(?ACCOUNT, ?QUEUE, ?CALLBACK, ?TOKEN, <<"uuid">>, <<"originate-q">>, <<"originate-request">>) ->
        put(persisted_ready, true), {ok, reservation()}
    end),
    meck:expect(acdc_callback_caller, originate_ready_ack, fun(Worker, ?TOKEN) ->
        ?assertEqual(self(), Worker), ?assertEqual(true, get(persisted_ready)), ok
    end),
    {keep_state, _} = acdc_queue_fsm:callback_waiting(info, {acdc_callback_caller_ready, ?CALLBACK, ?TOKEN, <<"uuid">>, <<"originate-q">>, <<"originate-request">>}, Initial),
    ?assertEqual(1, meck:num_calls(acdc_callback_caller, originate_ready_ack, '_')),
    ?assertEqual(0, meck:num_calls(acdc_callback_caller, cancel, '_'))
end).

failed_ready_commit_cancels_without_execute_case() -> with_mocks(fun() ->
    meck:expect(acdc_callback_store, bind_originate, fun(_, _, _, _, _, _, _) -> {error, conflict} end),
    {next_state, callback_waiting, Waiting} = acdc_queue_fsm:callback_waiting(info,
        {acdc_callback_caller_ready, ?CALLBACK, ?TOKEN, <<"uuid">>, <<"originate-q">>, <<"originate-request">>},
        state([{callback_ctx, context(dialing)}])),
    ?assertEqual(0, meck:num_calls(acdc_callback_caller, originate_ready_ack, '_')),
    ?assertEqual(1, meck:num_calls(acdc_callback_caller, cancel, '_')),
    cancel_timer(Waiting)
end).

stale_worker_events_and_timers_do_not_crash_native_state_case() -> with_mocks(fun() ->
    Initial = state([]),
    Events = [{acdc_callback_caller_failed, ?CALLBACK, ?TOKEN, timeout, reconciliation_required}
             ,{acdc_callback_caller_ready, ?CALLBACK, ?TOKEN, <<"uuid">>, <<"queue">>, <<"originate-request">>}
             ,{timeout, make_ref(), callback_menu_deadline}],
    lists:foreach(fun(Event) ->
        ?assertEqual({next_state, ready, Initial}, acdc_queue_fsm:ready(info, Event, Initial)),
        ?assertEqual({next_state, connect_req, Initial}, acdc_queue_fsm:connect_req(info, Event, Initial)),
        ?assertEqual({next_state, connecting, Initial}, acdc_queue_fsm:connecting(info, Event, Initial))
    end, Events)
end).

stale_cancel_cannot_abandon_another_paused_call_case() -> with_mocks(fun() ->
    Initial = state([{callback_ctx, context(paused)}]),
    Event = kz_json:from_list([{<<"Call-ID">>, <<"other-call">>}]),
    ?assertEqual({keep_state, Initial}, acdc_queue_fsm:callback_paused(cast, {member_call_cancel, Event}, Initial)),
    ?assertEqual(0, meck:num_calls(acdc_callback_store, cancel, '_'))
end).

native_hangup_does_not_ack_before_durable_cleanup_case() -> with_mocks(fun() ->
    Initial = native_state(), Event = kz_json:from_list([{<<"Call-ID">>, <<"returned-caller">>}]),
    {next_state, callback_waiting, Waiting} = acdc_queue_fsm:connecting(cast, {member_hungup, Event}, Initial),
    ?assertEqual(native_ending, maps:get(mode, field(callback_ctx, Waiting))),
    ?assertEqual(0, meck:num_calls(acdc_queue_listener, retire_callback_member, '_')),
    ?assertEqual(0, meck:num_calls(acdc_queue_listener, finish_member_call, '_')),
    ?assertEqual(0, meck:num_calls(kapps_call_command, hangup, '_')),
    ?assertEqual(field(member_call, Initial), field(member_call, Waiting)),
    cancel_timer(Waiting)
end).

native_cancellation_retains_delivery_until_channels_settle_case() -> with_mocks(fun() ->
    meck:expect(acdc_callback_store, cancel, fun(_, _, _) -> {ok, kz_json:set_value(<<"status">>, <<"cancelling">>, reservation())} end),
    {next_state, callback_waiting, Waiting} = acdc_queue_fsm:connecting(cast,
        {member_hungup, kz_json:from_list([{<<"Call-ID">>, <<"returned-caller">>}])}, native_state()),
    ?assertEqual(reconciliation, maps:get(mode, field(callback_ctx, Waiting))),
    ?assertEqual(1, meck:num_calls(kapps_call_command, hangup, '_')),
    ?assertEqual(0, meck:num_calls(acdc_queue_listener, retire_callback_member, '_')),
    cancel_timer(Waiting)
end).

bridge_without_acceptance_has_bounded_proof_deadline_case() -> with_mocks(fun() ->
    Event = bridge(<<"agent-leg">>),
    {next_state, connecting, Connecting} = acdc_queue_fsm:connecting(cast, {channel_bridged, Event}, native_state()),
    Context = field(callback_ctx, Connecting),
    ?assert(is_reference(maps:get(timer_ref, Context))),
    ?assertEqual(<<"agent-leg">>, maps:get(bridge_agent_leg, Context)),
    ?assertEqual({keep_state, Connecting}, acdc_queue_fsm:connecting(cast, {retry, kz_json:new()}, Connecting)),
    ?assertEqual({keep_state, Connecting}, acdc_queue_fsm:connecting(info, {timeout, make_ref(), agent_timer_expired}, Connecting)),
    ?assertEqual(0, meck:num_calls(acdc_queue_listener, finish_member_call, '_')),
    cancel_timer(Connecting)
end).

acceptance_from_unselected_agent_is_ignored_case() -> with_mocks(fun() ->
    Accept = kz_json:from_list([{<<"Call-ID">>, <<"returned-caller">>}, {<<"Account-ID">>, ?ACCOUNT}
                               ,{<<"Agent-ID">>, <<"other-agent">>}, {<<"Process-ID">>, <<"other-process">>}]),
    Initial = native_state(),
    ?assertEqual({next_state, connecting, Initial}, acdc_queue_fsm:connecting(cast, {accepted, Accept}, Initial))
end).

accepted_snapshot_probe_deadline_retains_delivery_case() -> with_mocks(fun() ->
    Winner = winner(<<"agent-a">>, <<"process-a">>),
    Initial = native_state([{connect_wins, [Winner]}, {member_call_winners, [Winner]}]),
    {next_state, connecting, Waiting} = acdc_queue_fsm:connecting(cast,
        {accepted, acceptance(Winner, <<"leg-a">>)}, Initial),
    Context = field(callback_ctx, Waiting), Deadline = maps:get(timer_ref, Context),
    Probe = maps:get(bridge_probe_ref, Context),
    _ = erlang:cancel_timer(Deadline),
    {next_state, callback_waiting, Ending} = acdc_queue_fsm:connecting(info,
        {timeout, Deadline, callback_proof_deadline}, Waiting),
    ?assertEqual(native_ending, maps:get(mode, field(callback_ctx, Ending))),
    ?assertEqual(1, meck:num_calls(acdc_callback_store, cancel, '_')),
    ?assertEqual(0, meck:num_calls(acdc_queue_listener, retire_callback_member, '_')),
    ?assertEqual({next_state, callback_waiting, Ending}, acdc_queue_fsm:callback_waiting(cast,
        {callback_bridge_snapshot, Probe, {ok, #{complete => true}}}, Ending)),
    cancel_timer(Ending)
end).

native_retry_clears_old_agent_proof_case() -> with_mocks(fun() ->
    Winner = winner(<<"agent-a">>, <<"process-a">>), Accept = acceptance(Winner, <<"leg-a">>),
    Initial = native_state([{connect_wins, [Winner]}, {member_call_winners, [Winner]}]),
    {next_state, connecting, Accepted} = acdc_queue_fsm:connecting(cast, {accepted, Accept}, Initial),
    OldTimer = maps:get(timer_ref, field(callback_ctx, Accepted)),
    {next_state, connect_req, Retried} = acdc_queue_fsm:connecting(cast, {retry, Winner}, Accepted),
    ?assertEqual(false, erlang:read_timer(OldTimer)),
    ?assertEqual(undefined, maps:get(accepted, field(callback_ctx, Retried), undefined)),
    ?assertEqual(undefined, maps:get(bridge_probe_ref, field(callback_ctx, Retried), undefined)),
    ?assertEqual([], field(connect_wins, Retried)),
    ?assertEqual({next_state, connect_req, Retried}, acdc_queue_fsm:connect_req(cast, {accepted, Accept}, Retried)),
    WinnerB = winner(<<"agent-b">>, <<"process-b">>),
    SelectedB = native_state([{connect_wins, [WinnerB]}, {member_call_winners, [WinnerB]},
                             {callback_ctx, field(callback_ctx, Retried)}]),
    {next_state, connecting, BridgedB} = acdc_queue_fsm:connecting(cast, {channel_bridged, bridge(<<"leg-b">>)}, SelectedB),
    ?assertEqual(undefined, maps:get(accepted, field(callback_ctx, BridgedB), undefined)),
    ?assertEqual({next_state, connecting, BridgedB}, acdc_queue_fsm:connecting(cast, {accepted, Accept}, BridgedB)),
    ?assertEqual(0, meck:num_calls(acdc_callback_store, advance, '_')),
    ?assertEqual(0, meck:num_calls(acdc_queue_listener, retire_callback_member, '_')),
    cancel_timer(BridgedB),
    receive {timeout, undefined, collect_timer_expired} -> ok after 0 -> ok end
end).

native_acceptance_requires_exact_agent_leg_case() -> with_mocks(fun() ->
    Winner = winner(<<"agent-a">>, <<"process-a">>), Initial = native_state([{connect_wins, [Winner]}]),
    Missing = kz_json:delete_key(<<"Agent-Call-ID">>, acceptance(Winner, <<"leg-a">>)),
    ?assertEqual({next_state, connecting, Initial}, acdc_queue_fsm:connecting(cast, {accepted, Missing}, Initial)),
    {next_state, connecting, Accepted} = acdc_queue_fsm:connecting(cast, {accepted, acceptance(Winner, <<"leg-a">>)}, Initial),
    {next_state, connecting, Waiting} = acdc_queue_fsm:connecting(cast, {channel_bridged, bridge(<<"unrelated-leg">>)}, Accepted),
    ?assertEqual(native, maps:get(mode, field(callback_ctx, Waiting))),
    ?assertEqual(0, meck:num_calls(acdc_callback_store, advance, '_')),
    ?assertEqual(0, meck:num_calls(acdc_queue_listener, retire_callback_member, '_')),
    cancel_timer(Waiting)
end).

native_conflicting_proofs_do_not_overwrite_first_identity_case() -> with_mocks(fun() ->
    A = winner(<<"agent-a">>, <<"process-a">>), B = winner(<<"agent-b">>, <<"process-b">>),
    Initial = native_state([{connect_wins, [A, B]}]),
    {next_state, connecting, Accepted} = acdc_queue_fsm:connecting(cast, {accepted, acceptance(A, <<"leg-a">>)}, Initial),
    {next_state, connecting, Candidates} = acdc_queue_fsm:connecting(cast, {accepted, acceptance(B, <<"leg-b">>)}, Accepted),
    ?assertEqual(2, maps:size(maps:get(accepted_candidates, field(callback_ctx, Candidates)))),
    ?assertEqual(undefined, maps:get(accepted, field(callback_ctx, Candidates), undefined)),
    cancel_timer(Candidates),
    {next_state, connecting, Bridged} = acdc_queue_fsm:connecting(cast, {channel_bridged, bridge(<<"leg-a">>)}, Initial),
    ?assertEqual({next_state, connecting, Bridged}, acdc_queue_fsm:connecting(cast, {channel_bridged, bridge(<<"leg-b">>)}, Bridged)),
    cancel_timer(Bridged)
end).

abandon_active_attempt_enters_reconciliation_not_cancel_poll_case() -> with_mocks(fun() ->
    meck:expect(acdc_callback_store, find, fun(_, _, _) -> {ok, reservation()} end),
    meck:expect(acdc_callback_store, cancel, fun(_, _, _) -> {ok, kz_json:set_value(<<"status">>, <<"cancelling">>, reservation())} end),
    Request = kz_json:set_value(<<"Pause-ID">>, ?TOKEN, request(<<"abandon">>)),
    {next_state, callback_waiting, Waiting} = acdc_queue_fsm:callback_waiting(cast, {callback_request, Request}, state([{callback_ctx, context(dialing)}])),
    ?assertEqual(reconciliation, maps:get(mode, field(callback_ctx, Waiting))),
    ?assertEqual(0, meck:num_calls(acdc_queue_listener, retire_callback_member, '_')),
    ?assertEqual(0, meck:num_calls(acdc_queue_listener, exit_member_call, '_')),
    cancel_timer(Waiting)
end).

winner(Agent, Process) -> kz_json:from_list([{<<"Agent-ID">>, Agent}, {<<"Process-ID">>, Process}]).
acceptance(Winner, AgentLeg) -> kz_json:set_values([{<<"Call-ID">>, <<"returned-caller">>}, {<<"Account-ID">>, ?ACCOUNT}
                                                   ,{<<"Agent-Call-ID">>, AgentLeg}], Winner).
bridge(AgentLeg) -> kz_json:from_list([{<<"Call-ID">>, <<"returned-caller">>}, {<<"Other-Leg-Call-ID">>, AgentLeg},
                                    {<<"Custom-Channel-Vars">>, kz_json:from_list([{<<"Account-ID">>, ?ACCOUNT}])}]).

lookup_outage_cannot_open_a_second_callback_menu_case() -> with_mocks(fun() ->
    Initial = state([{callback_ctx, #{mode => recover_lookup}}]),
    ?assertEqual({keep_state, Initial}, acdc_queue_fsm:callback_waiting(cast, {callback_request, request(<<"pause">>)}, Initial)),
    ?assertEqual(<<"busy">>, kz_json:get_value(<<"Failure-Reason">>, get(response))),
    ?assertEqual(0, meck:num_calls(acdc_queue_manager, stop_announcements, '_'))
end).

registration_rejection_preserves_pause_for_explicit_resume_case() -> with_mocks(fun() ->
    Ref = make_ref(), Context = (context(paused))#{registration_ref => Ref, registration_request => request(<<"register">>)},
    {keep_state, Paused} = acdc_queue_fsm:callback_paused(cast,
        {callback_registered, Ref, {error, policy_denied}}, state([{callback_ctx, Context}])),
    ?assertEqual(paused, maps:get(mode, field(callback_ctx, Paused))),
    ?assertEqual(undefined, maps:get(registration_ref, field(callback_ctx, Paused))),
    ?assertEqual(<<"rejected">>, kz_json:get_value(<<"Status">>, get(response))),
    ?assertEqual(0, meck:num_calls(acdc_queue_manager, resume_announcements, '_')),
    ?assertEqual(0, meck:num_calls(acdc_queue_listener, member_connect_req, '_'))
end).

delayed_resume_ack_is_replayed_without_restarting_menu_case() -> with_mocks(fun() ->
    Context = #{mode => resumed, request => request(<<"pause">>), pause_id => ?TOKEN, callback_id => ?CALLBACK},
    Initial = state([{callback_ctx, Context}]),
    Request = kz_json:set_values([{<<"Pause-ID">>, ?TOKEN}, {<<"Callback-ID">>, ?CALLBACK}], request(<<"resume">>)),
    lists:foreach(fun(StateName) ->
        ?assertEqual({next_state, StateName, Initial}, acdc_queue_fsm:StateName(cast, {callback_request, Request}, Initial)),
        ?assertEqual(<<"resumed">>, kz_json:get_value(<<"Status">>, get(response)))
    end, [ready, connect_req, connecting]),
    ?assertEqual(0, meck:num_calls(acdc_callback_store, cancel, '_')),
    ?assertEqual(0, meck:num_calls(acdc_queue_manager, stop_announcements, '_'))
end).

incomplete_recovery_evidence_never_releases_or_redials_case() -> with_mocks(fun() ->
    Ref = make_ref(), Context = (context(probing_reconciliation))#{reconcile_ref => Ref},
    Initial = state([{callback_ctx, Context}]),
    {next_state, callback_waiting, Waiting} = acdc_queue_fsm:callback_waiting(cast,
        {callback_reconciled, Ref, {unknown, #{complete => false}}}, Initial),
    ?assertEqual(reconciliation, maps:get(mode, field(callback_ctx, Waiting))),
    ?assertEqual(?TOKEN, maps:get(token, field(callback_ctx, Waiting))),
    ?assertEqual(0, meck:num_calls(acdc_callback_caller, start_link, '_')),
    ?assertEqual(0, meck:num_calls(acdc_queue_listener, retire_callback_member, '_')),
    ?assertEqual(0, meck:num_calls(acdc_callback_store, claim, '_')),
    cancel_timer(Waiting)
end).

stale_recovery_generation_is_ignored_case() -> with_mocks(fun() ->
    Initial = state([{callback_ctx, (context(probing_reconciliation))#{reconcile_ref => make_ref()}}]),
    ?assertEqual({keep_state, Initial}, acdc_queue_fsm:callback_waiting(cast,
        {callback_reconciled, make_ref(), {ok, #{complete => true}}}, Initial)),
    ?assertEqual(0, meck:num_calls(acdc_callback_store, get, '_'))
end).

listener_retirement_failure_keeps_delivery_unacknowledged_case() ->
    with_listener_mocks(fun() ->
        Initial = listener_state(),
        meck:expect(acdc_queue_manager, retire_callback_member, fun(_, ?CALL, ?CALLBACK) -> {error, publish_failed} end),
        ?assertEqual({reply, {error, retirement_failed}, Initial},
                     acdc_queue_listener:handle_call({retire_callback_member, ?CALLBACK}, self(), Initial)),
        ?assertEqual(0, meck:num_calls(acdc_queue_shared, ack, '_')),
        ?assertEqual(0, meck:num_calls(acdc_util, unbind_from_call_events, '_'))
    end).

listener_retires_manager_slot_before_ack_case() ->
    with_listener_mocks(fun() ->
        meck:expect(acdc_queue_manager, retire_callback_member, fun(_, ?CALL, ?CALLBACK) -> put(retired, true), ok end),
        meck:expect(acdc_queue_shared, ack, fun(_, delivery) -> ?assertEqual(true, get(retired)), ok end),
        {reply, ok, _} = acdc_queue_listener:handle_call({retire_callback_member, ?CALLBACK}, self(), listener_state()),
        ?assertEqual(1, meck:num_calls(acdc_queue_shared, ack, '_'))
    end).

listener_state() ->
    acdc_queue_listener:callback_test_state([{call, field(member_call, state([]))}, {mgr_pid, self()}
                                            ,{shared_pid, self()}, {delivery, delivery}
                                            ,{account_id, ?ACCOUNT}, {queue_id, ?QUEUE}]).

with_listener_mocks(Fun) ->
    erase(retired), put(callid, <<"callback-listener-test">>),
    Modules = [acdc_queue_manager, acdc_queue_shared, acdc_util, gen_listener],
    meck:new(Modules, [non_strict, no_link]),
    try
        meck:expect(acdc_queue_shared, ack, fun(_, _) -> ok end),
        meck:expect(acdc_util, unbind_from_call_events, fun(_) -> ok end),
        meck:expect(acdc_util, queue_presence_update, fun(_, _) -> ok end),
        meck:expect(gen_listener, rm_binding, fun(_, _, _) -> ok end),
        Fun()
    after meck:unload(Modules) end.

native_state() -> native_state([]).
native_state(Overrides) ->
    Initial = state([]),
    Call = kapps_call:set_call_id(<<"returned-caller">>, field(member_call, Initial)),
    state(Overrides ++ [{member_call, Call}, {callback_ctx, context(native)}]).

state(Overrides) ->
    Call0 = kapps_call:set_account_id(?ACCOUNT, kapps_call:set_call_id(?CALL, kapps_call:new())),
    Call = acdc_queue_member:stamp(Call0, 63950000000, 1, 0),
    acdc_queue_fsm:callback_test_state(Overrides ++ [{member_call, Call}, {member_call_winners, []}
                                                   ,{manager_proc, self()}, {listener_proc, self()}
                                                   ,{account_id, ?ACCOUNT}, {queue_id, ?QUEUE}
                                                   ,{account_db, kzs_util:format_account_db(?ACCOUNT)}
                                                   ,{callback_enabled, true}]).
field(Name, State) -> acdc_queue_fsm:callback_test_field(Name, State).
context(Mode) -> #{mode => Mode, request => request(<<"pause">>), pause_id => ?TOKEN
                 ,reservation => reservation(), token => ?TOKEN, worker => self()
                 ,timer_ref => undefined, previous_state => ready, registration_ref => undefined}.
reservation() -> kz_json:from_list([{<<"_id">>, ?CALLBACK}, {<<"queue_id">>, ?QUEUE}
                                  ,{<<"pvt_account_id">>, ?ACCOUNT}, {<<"status">>, <<"dialing">>}
                                  ,{<<"pvt_caller_call_id">>, <<"returned-caller">>}]).
request(Operation) -> kz_json:from_list([{<<"Account-ID">>, ?ACCOUNT}, {<<"Queue-ID">>, ?QUEUE}
                                       ,{<<"Call-ID">>, ?CALL}, {<<"Request-ID">>, ?REQUEST}
                                       ,{<<"Server-ID">>, <<"controller">>}, {<<"Operation">>, Operation}
                                       ,{<<"Event-Category">>, <<"acdc_callback">>}, {<<"Event-Name">>, <<"request">>}
                                       ,{<<"Msg-ID">>, ?REQUEST}, {<<"App-Name">>, <<"test">>}, {<<"App-Version">>, <<"1">>}]).
cancel_timer(State) ->
    case maps:get(timer_ref, field(callback_ctx, State), undefined) of
        undefined -> ok;
        Ref -> erlang:cancel_timer(Ref), receive {timeout, Ref, _} -> ok after 0 -> ok end
    end.

with_mocks(Fun) ->
    put(callid, <<"callback-fsm-test">>), erase(response), erase(persisted_ready),
    Modules = [acdc_queue_manager, acdc_queue_listener, acdc_callback_store, acdc_callback_caller, acdc_callback_recovery_io, kz_amqp_util, kapps_call_command],
    meck:new(Modules, [non_strict, no_link]),
    try
        meck:expect(acdc_queue_manager, stop_announcements, fun(_, _) -> ok end),
        meck:expect(acdc_callback_recovery_io, observe, fun(_) -> {'unknown', #{'complete' => 'false'}} end),
        meck:expect(acdc_queue_listener, member_connect_req, fun(_) -> ok end),
        meck:expect(acdc_queue_listener, cancel_member_call, fun(_, _) -> ok end),
        meck:expect(acdc_queue_listener, retire_callback_member, fun(_, _) -> ok end),
        meck:expect(acdc_queue_listener, finish_member_call, fun(_) -> ok end),
        meck:expect(acdc_queue_listener, timeout_agent, fun(_, _) -> ok end),
        meck:expect(kapps_call_command, hangup, fun(_) -> ok end),
        meck:expect(kapps_call_command, set, fun(_, _, _) -> ok end),
        meck:expect(acdc_callback_store, cancel, fun(_, _, _) -> {error, unexpected_cancel} end),
        meck:expect(acdc_callback_store, bind_leg, fun(?ACCOUNT, ?QUEUE, ?CALLBACK, ?TOKEN, agent, AgentLeg) ->
            {ok, kz_json:set_value(<<"pvt_agent_call_id">>, AgentLeg, reservation())}
        end),
        meck:expect(acdc_callback_caller, cancel, fun(_, _) -> ok end),
        meck:expect(acdc_callback_caller, originate_ready_ack, fun(_, _) -> ok end),
        meck:expect(kz_amqp_util, targeted_publish, fun(<<"controller">>, Payload, <<"application/json">>) ->
            Response = kz_json:decode(iolist_to_binary(Payload)),
            ?assert(kapi_acdc_callback:response_v(Response)), put(response, Response), ok
        end),
        Fun()
    after meck:unload(Modules) end.
