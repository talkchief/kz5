%%% SPDX-License-Identifier: MPL-2.0
-module(acdc_callback_store_tests).
-include_lib("eunit/include/eunit.hrl").

-define(ACCOUNT, <<"11111111111111111111111111111111">>).
-define(OTHER_ACCOUNT, <<"22222222222222222222222222222222">>).
-define(QUEUE, <<"callback-test-queue">>).
-define(NOW, 63950000000).

idempotent_registration_test() -> with_store(fun(Store) ->
    Registration = registration(),
    {ok, First} = create(Registration),
    clock(Store, ?NOW + 30),
    {ok, Again} = create(Registration),
    ?assertEqual(First, Again),
    ?assertEqual({error, registration_conflict}, create(kz_json:set_value(<<"number">>, <<"1002">>, Registration))),
    ?assertEqual(1, store_call(Store, count))
end).

hostile_registration_test() -> with_store(fun(Store) ->
    lists:foreach(fun(Number) ->
        ?assertEqual({error, invalid_registration}, create(kz_json:set_value(<<"number">>, Number, registration())))
    end, [<<"sofia/internal/1001">>, <<"1001,1002">>, <<"{ignore_early_media=true}1001">>
          ,<<"1001\n">>, <<"+12025550123\r\n">>, <<>>, <<"1234567890123456">>, 1001]),
    lists:foreach(fun({Key, Value}) ->
        ?assertEqual({error, invalid_registration}, create(kz_json:set_value(Key, Value, registration())))
    end, [{<<"max_attempts">>, 11}, {<<"retry_delay">>, 0}, {<<"ttl">>, 86401}
          ,{<<"enqueue_sequence">>, -1}, {<<"enqueued_at">>, ?NOW + 1}, {<<"priority">>, -1}
          ,{<<"language">>, <<"EN-US">>}]),
    ?assertEqual({error, invalid_registration}, acdc_callback_store:create(<<?ACCOUNT/binary, "\n">>, ?QUEUE, <<"call">>, registration(), authority())),
    ?assertEqual(0, store_call(Store, count))
end).

registration_allowlist_test() -> with_store(fun(_) ->
    Extra = kz_json:set_values([{<<"pvt_lease">>, <<"injected">>}, {<<"status">>, <<"completed">>}
                                ,{<<"dialstring">>, <<"unsafe">>}
                                ,{<<"pvt_authority_id">>, <<"injected">>}
                                ,{<<"pvt_authority_type">>, <<"resource">>}
                                ,{<<"pvt_account_realm">>, <<"attacker.invalid">>}
                                ,{<<"pvt_originate_success">>, kz_json:from_list([{<<"version">>, 1}])}], registration()),
    {ok, Doc} = create(Extra),
    ?assertEqual(<<"registering">>, value(<<"status">>, Doc)),
    ?assertEqual(undefined, value(<<"pvt_lease">>, Doc)),
    ?assertEqual(undefined, value(<<"dialstring">>, Doc)),
    ?assertEqual(undefined, value(<<"pvt_originate_success">>, Doc)),
    ?assertEqual(<<"callback-service-device">>, value(<<"pvt_authority_id">>, Doc)),
    ?assertEqual(<<"device">>, value(<<"pvt_authority_type">>, Doc)),
    ?assertEqual(<<"callback-test.invalid">>, value(<<"pvt_account_realm">>, Doc))
end).

authority_snapshot_is_required_and_immutable_test() -> with_store(fun(Store) ->
    lists:foreach(fun(Authority) ->
        ?assertEqual({error, invalid_registration},
                     acdc_callback_store:create(?ACCOUNT, ?QUEUE, <<"original-caller-id">>, registration(), Authority))
    end, [undefined, kz_json:new()
          ,kz_json:set_value(<<"type">>, <<"resource">>, authority())
          ,kz_json:set_value(<<"id">>, <<"../other-account">>, authority())
          ,kz_json:set_value(<<"account_realm">>, <<"host.invalid\r\nRoute: injected">>, authority())]),
    ?assertEqual(0, store_call(Store, count)),
    {ok, _} = create(registration()),
    lists:foreach(fun({Key, Changed}) ->
        ?assertEqual({error, registration_conflict},
                     acdc_callback_store:create(?ACCOUNT, ?QUEUE, <<"original-caller-id">>, registration()
                                                ,kz_json:set_value(Key, Changed, authority())))
    end, [{<<"id">>, <<"another-device">>}, {<<"type">>, <<"user">>}
          ,{<<"account_realm">>, <<"changed.invalid">>}])
end).

account_queue_scope_test() -> with_store(fun(Store) ->
    {ok, Doc} = create(registration()),
    Id = kz_doc:id(Doc),
    ?assertEqual({error, not_found}, acdc_callback_store:get(?OTHER_ACCOUNT, ?QUEUE, Id)),
    ?assertEqual({error, not_found}, acdc_callback_store:get(?ACCOUNT, <<"other-queue">>, Id)),
    Spoofed = kz_json:set_value(<<"pvt_account_id">>, ?OTHER_ACCOUNT, Doc),
    store_call(Store, {put, db(), Spoofed}),
    ?assertEqual({error, not_found}, get_doc(Id)),
    store_call(Store, {put, db(), kz_json:set_value(<<"pvt_type">>, <<"user">>, Doc)}),
    ?assertEqual({error, not_found}, get_doc(Id)),
    store_call(Store, {put, db(), kz_json:set_value(<<"pvt_deleted">>, true, Doc)}),
    ?assertEqual({error, not_found}, get_doc(Id))
end).

activation_barrier_test() -> with_store(fun(_) ->
    {ok, Doc} = create(registration()),
    Id = kz_doc:id(Doc),
    ?assertEqual({error, invalid_state}, claim(Id)),
    {ok, Queued} = activate(Id),
    ?assertEqual(<<"queued">>, value(<<"status">>, Queued)),
    ?assertEqual({ok, Queued}, activate(Id)),
    {ok, Dialing} = claim(Id),
    ?assertEqual(1, value(<<"attempts">>, Dialing)),
    ?assert(is_binary(value(<<"pvt_caller_call_id">>, Dialing))),
    ?assertEqual({error, busy}, claim(Id))
end).

concurrent_claim_cas_test() -> with_store(fun(Store) ->
    Id = queued(),
    Parent = self(),
    meck:expect(kz_datamgr, open_doc, fun(Db, DocId) ->
        Reply = store_call(Store, {open, Db, DocId}),
        Parent ! {read_revision, self()},
        receive continue -> Reply after 3000 -> error(read_barrier_timeout) end
    end),
    Workers = [spawn(fun() -> Parent ! {claimed, self(), claim(Id)} end) || _ <- [1,2]],
    Readers = [receive {read_revision, Pid} -> Pid after 3000 -> error(missing_reader) end || _ <- [1,2]],
    [Pid ! continue || Pid <- Readers],
    Results = [receive {claimed, Pid, Result} -> Result after 3000 -> error(missing_claim) end || Pid <- Workers],
    ?assertEqual(1, length([ok || {ok, _} <- Results])),
    ?assertEqual(1, length([conflict || {error, conflict} <- Results])),
    {ok, Saved} = store_call(Store, {open, db(), Id}),
    ?assertEqual(1, value(<<"attempts">>, Saved))
end).

human_confirmation_state_machine_test() -> with_store(fun(_) ->
    Id = queued(),
    {ok, Dialing} = claim(Id),
    Token = token(Dialing),
    Caller = value(<<"pvt_caller_call_id">>, Dialing),
    CallerData = kz_json:from_list([{<<"caller_call_id">>, Caller}]),
    ?assertEqual({error, invalid_transition}, advance(Id, Token, caller_confirmed, CallerData)),
    ?assertEqual({error, invalid_transition}, advance(Id, Token, caller_answered, kz_json:from_list([{<<"caller_call_id">>, <<"other-leg">>}]))),
    {ok, Confirming} = advance(Id, Token, caller_answered, CallerData),
    ?assertEqual(<<"confirming">>, value(<<"status">>, Confirming)),
    ?assertEqual({error, invalid_transition}, advance(Id, Token, caller_confirmed, kz_json:from_list([{<<"caller_call_id">>, <<"agent-leg">>}]))),
    {ok, Connecting} = advance(Id, Token, caller_confirmed, CallerData),
    ?assertEqual(<<"connecting">>, value(<<"status">>, Connecting)),
    {ok, Bound} = acdc_callback_store:bind_leg(?ACCOUNT, ?QUEUE, Id, Token, agent, <<"agent-leg">>),
    ?assertEqual({ok, Bound}, acdc_callback_store:bind_leg(?ACCOUNT, ?QUEUE, Id, Token, agent, <<"agent-leg">>)),
    ?assertEqual({error, leg_conflict}, acdc_callback_store:bind_leg(?ACCOUNT, ?QUEUE, Id, Token, agent, <<"different-agent">>)),
    BridgeData = kz_json:set_value(<<"agent_call_id">>, <<"agent-leg">>, CallerData),
    {ok, Complete} = advance(Id, Token, bridged, BridgeData),
    ?assertEqual(<<"completed">>, value(<<"status">>, Complete)),
    ?assertEqual(undefined, value(<<"pvt_lease">>, Complete)),
    ?assertEqual({error, invalid_state}, claim(Id)),
    ?assertEqual({error, already_finished}, cancel(Id))
end).

lease_expiry_never_redials_test() -> with_store(fun(Store) ->
    Id = queued(),
    {ok, Doc} = claim(Id),
    ?assertEqual({error, stale_lease}, acdc_callback_store:renew(?ACCOUNT, ?QUEUE, Id, <<"wrong-token">>, 30)),
    clock(Store, ?NOW + 30),
    ?assertEqual({error, reconciliation_required}, claim(Id)),
    ?assertEqual({error, reconciliation_required}, acdc_callback_store:renew(?ACCOUNT, ?QUEUE, Id, token(Doc), 30)),
    ?assertEqual({error, reconciliation_required}, advance(Id, token(Doc), attempt_ended, cause())),
    ?assertEqual({ok, Doc}, get_doc(Id))
end).

adoption_keeps_same_attempt_and_fences_old_token_test() -> with_store(fun(_) ->
    Id = queued(),
    {ok, Claimed} = acdc_callback_store:claim(?ACCOUNT, ?QUEUE, Id, owner_id(self()), 30),
    OldToken = token(Claimed), CallerId = value(<<"pvt_caller_call_id">>, Claimed),
    Data = kz_json:from_list([{<<"caller_call_id">>, CallerId}]),
    {ok, _} = advance(Id, OldToken, caller_answered, Data),
    {ok, _} = advance(Id, OldToken, caller_confirmed, Data),
    {ok, Adopted} = acdc_callback_store:adopt(?ACCOUNT, ?QUEUE, Id, OldToken, 30),
    ?assertNotEqual(OldToken, token(Adopted)),
    ?assertEqual(CallerId, value(<<"pvt_caller_call_id">>, Adopted)),
    ?assertEqual(1, value(<<"attempts">>, Adopted)),
    ?assertEqual(<<"connecting">>, value(<<"status">>, Adopted)),
    ?assertEqual({error, stale_lease}, acdc_callback_store:bind_leg(?ACCOUNT, ?QUEUE, Id, OldToken, agent, <<"agent-leg">>)),
    ?assertMatch({ok, _}, acdc_callback_store:bind_leg(?ACCOUNT, ?QUEUE, Id, token(Adopted), agent, <<"agent-leg">>))
end).

adoption_requires_positive_local_owner_death_test() -> with_store(fun(_) ->
    Owner = spawn(fun() -> receive stop -> ok end end), Monitor = monitor(process, Owner),
    try
        Id = queued(), {ok, Claimed} = acdc_callback_store:claim(?ACCOUNT, ?QUEUE, Id, owner_id(Owner), 30),
        Token = token(Claimed), Data = kz_json:from_list([{<<"caller_call_id">>, value(<<"pvt_caller_call_id">>, Claimed)}]),
        {ok, _} = advance(Id, Token, caller_answered, Data),
        {ok, _} = advance(Id, Token, caller_confirmed, Data),
        ?assertEqual({error, reconciliation_required}, acdc_callback_store:adopt(?ACCOUNT, ?QUEUE, Id, Token, 30)),
        Owner ! stop,
        receive {'DOWN', Monitor, process, Owner, normal} -> ok after 1000 -> error(owner_not_stopped) end,
        ?assertMatch({ok, _}, acdc_callback_store:adopt(?ACCOUNT, ?QUEUE, Id, Token, 30))
    after Owner ! stop, demonitor(Monitor, [flush]) end
end).

owner_id(Pid) -> iolist_to_binary([atom_to_binary(node(), utf8), <<":">>, pid_to_list(Pid)]).

reconciliation_marker_is_allowlisted_and_cleared_only_when_settled_test() -> with_store(fun(_) ->
    Id = queued(), {ok, Doc} = claim(Id), Token = token(Doc),
    ?assertEqual({error, invalid_reconciliation_reason}, acdc_callback_store:mark_reconciliation(?ACCOUNT, ?QUEUE, Id, Token, <<"raw private exception">>)),
    ?assertEqual({error, stale_lease}, acdc_callback_store:mark_reconciliation(?ACCOUNT, ?QUEUE, Id, <<"stale">>, <<"cleanup_pending">>)),
    {ok, Marked} = acdc_callback_store:mark_reconciliation(?ACCOUNT, ?QUEUE, Id, Token, <<"cleanup_pending">>),
    ?assertEqual({ok, Marked}, acdc_callback_store:mark_reconciliation(?ACCOUNT, ?QUEUE, Id, Token, <<"cleanup_pending">>)),
    ?assertEqual(true, value(<<"reconciliation_required">>, acdc_callback_store:public(Marked))),
    {ok, Cancelling} = cancel(Id),
    ?assertEqual(true, value(<<"reconciliation_required">>, Cancelling)),
    Proof = kz_json:set_values([{<<"caller_call_id">>, value(<<"pvt_caller_call_id">>, Doc)}
                                ,{<<"originate_settled">>, true}, {<<"channels_down">>, true}], cause()),
    {ok, Cancelled} = advance(Id, Token, attempt_settled, Proof),
    ?assertEqual(undefined, value(<<"reconciliation_required">>, Cancelled)),
    ?assertEqual(undefined, value(<<"reconciliation_reason">>, Cancelled))
end).

registration_handshake_is_immutable_and_private_test() -> with_store(fun(_) ->
    {ok, Doc} = create(registration()), Id = kz_doc:id(Doc),
    Request = <<"11111111111111111111111111111111">>, Pause = <<"222222222222222222222222222222222222222222222222">>,
    ?assertEqual({error, invalid_registration}, acdc_callback_store:bind_registration(?ACCOUNT, ?QUEUE, Id, <<"short">>, Pause, <<"controller">>)),
    {ok, Bound} = acdc_callback_store:bind_registration(?ACCOUNT, ?QUEUE, Id, Request, Pause, <<"controller">>),
    ?assertEqual({ok, Bound}, acdc_callback_store:bind_registration(?ACCOUNT, ?QUEUE, Id, Request, Pause, <<"controller">>)),
    ?assertEqual({error, registration_conflict}, acdc_callback_store:bind_registration(?ACCOUNT, ?QUEUE, Id, Request, Pause, <<"other">>)),
    {ok, _} = activate(Id),
    {ok, Active} = acdc_callback_store:bind_registration(?ACCOUNT, ?QUEUE, Id, Request, Pause, <<"controller">>),
    ?assertEqual(<<"queued">>, value(<<"status">>, Active)),
    Public = acdc_callback_store:public(Active),
    [?assertEqual(undefined, value(Key, Public)) || Key <- [<<"pvt_registration_request_id">>, <<"pvt_pause_id">>, <<"pvt_controller_queue">>]]
end).

native_agent_selection_is_scoped_bounded_and_private_test() -> with_store(fun(_) ->
    Id = queued(), {ok, Doc} = claim(Id), Token = token(Doc),
    Win = kz_json:from_list([{<<"Agent-ID">>, <<"agent-1">>}, {<<"Process-ID">>, <<"process-1">>}
                            ,{<<"Route">>, <<"must-not-persist">>}]),
    ?assertEqual({error, invalid_state}, acdc_callback_store:bind_selection(?ACCOUNT, ?QUEUE, Id, Token, [Win])),
    Data = kz_json:from_list([{<<"caller_call_id">>, value(<<"pvt_caller_call_id">>, Doc)}]),
    {ok, _} = advance(Id, Token, caller_answered, Data),
    {ok, _} = advance(Id, Token, caller_confirmed, Data),
    ?assertEqual({error, stale_lease}, acdc_callback_store:bind_selection(?ACCOUNT, ?QUEUE, Id, <<"stale">>, [Win])),
    ?assertEqual({error, invalid_selection}, acdc_callback_store:bind_selection(?ACCOUNT, ?QUEUE, Id, Token, lists:duplicate(33, Win))),
    {ok, Bound} = acdc_callback_store:bind_selection(?ACCOUNT, ?QUEUE, Id, Token, [Win]),
    [Selected] = value(<<"pvt_selected_agents">>, Bound),
    ?assertEqual([<<"Agent-ID">>, <<"Process-ID">>], lists:sort(kz_json:get_keys(Selected))),
    ?assertEqual(undefined, value(<<"pvt_selected_agents">>, acdc_callback_store:public(Bound)))
end).

originate_handles_are_durable_and_immutable_test() -> with_store(fun(_) ->
    Id = queued(), {ok, Doc} = claim(Id), Token = token(Doc),
    ?assertEqual({error, stale_lease}, acdc_callback_store:bind_originate(?ACCOUNT, ?QUEUE, Id, <<"old">>, <<"uuid">>, <<"queue">>, <<"originate-request">>)),
    {ok, Bound} = acdc_callback_store:bind_originate(?ACCOUNT, ?QUEUE, Id, Token, <<"uuid">>, <<"queue">>, <<"originate-request">>),
    ?assertEqual({ok, Bound}, acdc_callback_store:bind_originate(?ACCOUNT, ?QUEUE, Id, Token, <<"uuid">>, <<"queue">>, <<"originate-request">>)),
    ?assertEqual({error, leg_conflict}, acdc_callback_store:bind_originate(?ACCOUNT, ?QUEUE, Id, Token, <<"other">>, <<"queue">>, <<"originate-request">>)),
    ?assertEqual({error, leg_conflict}, acdc_callback_store:bind_originate(?ACCOUNT, ?QUEUE, Id, Token, <<"uuid">>, <<"queue">>, <<"different-request">>)),
    ?assertEqual({error, leg_conflict}, acdc_callback_store:bind_control(?ACCOUNT, ?QUEUE, Id, Token, <<"other-caller">>, <<"control">>)),
    {ok, WithControl} = acdc_callback_store:bind_control(?ACCOUNT, ?QUEUE, Id, Token, value(<<"pvt_caller_call_id">>, Doc), <<"control">>),
    ?assertEqual(<<"control">>, value(<<"pvt_caller_control_queue">>, WithControl)),
    Public = acdc_callback_store:public(WithControl),
    [?assertEqual(undefined, value(Key, Public)) || Key <- [<<"pvt_originate_uuid">>, <<"pvt_originate_queue">>, <<"pvt_caller_control_queue">>, <<"pvt_originate_msg_id">>]],
    {ok, Found} = acdc_callback_store:find(?ACCOUNT, ?QUEUE, <<"original-caller-id">>),
    ?assertEqual(Id, kz_doc:id(Found))
end).

originate_success_receipt_is_durable_scoped_and_private_test() -> with_store(fun(Store) ->
    Id = queued(), {ok, Doc} = claim(Id), Token = token(Doc),
    {ok, _} = acdc_callback_store:bind_originate(?ACCOUNT, ?QUEUE, Id, Token, <<"uuid">>, <<"queue">>, <<"request">>),
    Data = success_data(Doc),
    ?assertEqual({error, reconciliation_required}, advance(Id, <<"old">>, originate_succeeded, Data)),
    lists:foreach(fun(Key) ->
        ?assertEqual({error, reconciliation_required},
                     advance(Id, Token, originate_succeeded, kz_json:set_value(Key, <<"other">>, Data)))
    end, [<<"caller_call_id">>, <<"originate_uuid">>, <<"originate_msg_id">>]),
    {ok, Saved} = advance(Id, Token, originate_succeeded, Data),
    ?assert(acdc_callback_store:originate_succeeded(Saved)),
    ?assertEqual(<<"dialing">>, value(<<"status">>, Saved)),
    ?assertEqual({ok, Saved}, advance(Id, Token, originate_succeeded, Data)),
    ?assertEqual(undefined, value(<<"pvt_originate_success">>, acdc_callback_store:public(Saved))),
    lists:foreach(fun({Key, Changed}) ->
        ?assertNot(acdc_callback_store:originate_succeeded(kz_json:set_value(Key, Changed, Saved)))
    end, [{<<"_id">>, <<"other">>}, {<<"pvt_account_id">>, ?OTHER_ACCOUNT}
          ,{<<"queue_id">>, <<"other">>}, {<<"attempts">>, 2}
          ,{<<"pvt_caller_call_id">>, <<"other">>}, {<<"pvt_originate_uuid">>, <<"other">>}
          ,{<<"pvt_originate_msg_id">>, <<"other">>}]),
    clock(Store, ?NOW + 60),
    ?assertEqual({error, reconciliation_required}, advance(Id, Token, attempt_settled, cause())),
    {ok, _} = cancel(Id),
    {ok, CancelPending} = get_doc(Id),
    ?assert(acdc_callback_store:originate_succeeded(CancelPending)),
    ?assertEqual(<<"cancelling">>, value(<<"status">>, CancelPending))
end).

originate_success_receipt_can_arrive_after_expiry_but_not_next_attempt_test() -> with_store(fun(Store) ->
    Id = queued(), {ok, Doc} = claim(Id), Token = token(Doc),
    {ok, _} = acdc_callback_store:bind_originate(?ACCOUNT, ?QUEUE, Id, Token, <<"uuid">>, <<"queue">>, <<"request">>),
    clock(Store, ?NOW + 31),
    {ok, Saved} = advance(Id, Token, originate_succeeded, success_data(Doc)),
    ?assert(acdc_callback_store:originate_succeeded(Saved)),
    Proof = kz_json:set_values([{<<"caller_call_id">>, value(<<"pvt_caller_call_id">>, Doc)}
                               ,{<<"originate_settled">>, true}, {<<"channels_down">>, true}], cause()),
    {ok, Retry} = advance(Id, Token, attempt_settled, Proof),
    ?assertEqual(undefined, value(<<"pvt_originate_success">>, Retry)),
    clock(Store, value(<<"next_attempt_at">>, Retry)),
    {ok, Next} = claim(Id),
    ?assertNot(acdc_callback_store:originate_succeeded(Next)),
    ?assertEqual({error, reconciliation_required}, advance(Id, Token, originate_succeeded, success_data(Doc)))
end).

originate_success_after_cancellation_is_evidence_not_completion_test() -> with_store(fun(Store) ->
    Id = queued(), {ok, Doc} = claim(Id), Token = token(Doc),
    {ok, _} = acdc_callback_store:bind_originate(?ACCOUNT, ?QUEUE, Id, Token, <<"uuid">>, <<"queue">>, <<"request">>),
    {ok, _} = cancel(Id), clock(Store, ?NOW + 31),
    {ok, Saved} = advance(Id, Token, originate_succeeded, success_data(Doc)),
    ?assertEqual(<<"cancelling">>, value(<<"status">>, Saved)),
    ?assert(acdc_callback_store:originate_succeeded(Saved)),
    ?assertEqual({error, reconciliation_required}, advance(Id, Token, attempt_settled, cause()))
end).

originate_success_write_failure_never_creates_proof_test() -> with_store(fun(_) ->
    Id = queued(), {ok, Doc} = claim(Id), Token = token(Doc),
    ?assertEqual({error, reconciliation_required}, advance(Id, Token, originate_succeeded, success_data(Doc))),
    {ok, _} = acdc_callback_store:bind_originate(?ACCOUNT, ?QUEUE, Id, Token, <<"uuid">>, <<"queue">>, <<"request">>),
    lists:foreach(fun(Reason) ->
        meck:expect(kz_datamgr, save_doc, fun(_, _) -> {error, Reason} end),
        ?assertEqual({error, Reason}, advance(Id, Token, originate_succeeded, success_data(Doc))),
        {ok, Fresh} = get_doc(Id),
        ?assertNot(acdc_callback_store:originate_succeeded(Fresh))
    end, [conflict, timeout])
end).

success_data(Doc) ->
    kz_json:from_list([{<<"caller_call_id">>, value(<<"pvt_caller_call_id">>, Doc)}
                      ,{<<"originate_uuid">>, <<"uuid">>}, {<<"originate_msg_id">>, <<"request">>}]).

settled_cleanup_requires_exact_attempt_evidence_test() -> with_store(fun(Store) ->
    Id = queued(), {ok, Doc} = claim(Id), Token = token(Doc),
    Proof = kz_json:set_values([{<<"caller_call_id">>, value(<<"pvt_caller_call_id">>, Doc)}
                               ,{<<"originate_settled">>, true}, {<<"channels_down">>, true}], cause()),
    clock(Store, ?NOW + 30),
    ?assertEqual({error, reconciliation_required}, advance(Id, Token, attempt_settled, cause())),
    ?assertEqual({error, reconciliation_required}, advance(Id, <<"old-token">>, attempt_settled, Proof)),
    ?assertEqual({error, reconciliation_required}, advance(Id, Token, attempt_settled, kz_json:set_value(<<"caller_call_id">>, <<"another-leg">>, Proof))),
    ?assertEqual({error, reconciliation_required}, advance(Id, Token, attempt_settled, kz_json:set_value(<<"originate_settled">>, false, Proof))),
    {ok, Retry} = advance(Id, Token, attempt_settled, Proof),
    ?assertEqual(<<"retry_wait">>, value(<<"status">>, Retry)),
    ?assertEqual({error, reconciliation_required}, advance(Id, Token, attempt_settled, Proof))
end).

cancelled_attempt_can_finish_after_lease_expiry_test() -> with_store(fun(Store) ->
    Id = queued(), {ok, Doc} = claim(Id), Token = token(Doc),
    {ok, _} = acdc_callback_store:bind_leg(?ACCOUNT, ?QUEUE, Id, Token, agent, <<"agent-leg">>),
    {ok, _} = cancel(Id), clock(Store, ?NOW + 30),
    Proof = kz_json:set_values([{<<"caller_call_id">>, value(<<"pvt_caller_call_id">>, Doc)}
                               ,{<<"originate_settled">>, true}, {<<"channels_down">>, true}], cause()),
    ?assertEqual({error, reconciliation_required}, advance(Id, Token, attempt_settled, Proof)),
    {ok, Cancelled} = advance(Id, Token, attempt_settled, kz_json:set_value(<<"agent_call_id">>, <<"agent-leg">>, Proof)),
    ?assertEqual(<<"cancelled">>, value(<<"status">>, Cancelled)),
    ?assertEqual(undefined, value(<<"pvt_lease">>, Cancelled)),
    ?assertEqual({error, invalid_state}, claim(Id))
end).

cancel_waiting_and_inflight_test() -> with_store(fun(_) ->
    Id = queued(),
    {ok, Cancelled} = cancel(Id),
    ?assertEqual(<<"cancelled">>, value(<<"status">>, Cancelled)),
    ?assertEqual({ok, Cancelled}, cancel(Id)),
    ?assertEqual({error, invalid_state}, claim(Id)),
    ?assertEqual({ok, Cancelled}, create(registration())),
    {ok, Second} = acdc_callback_store:create(?ACCOUNT, ?QUEUE, <<"second-original-call">>, registration(), authority()),
    SecondId = kz_doc:id(Second),
    {ok, _} = activate(SecondId),
    {ok, Active} = claim(SecondId),
    {ok, Cancelling} = cancel(SecondId),
    ?assertEqual(<<"cancelling">>, value(<<"status">>, Cancelling)),
    ?assertEqual(value(<<"pvt_lease">>, Active), value(<<"pvt_lease">>, Cancelling)),
    ?assertEqual(value(<<"pvt_caller_call_id">>, Active), value(<<"pvt_caller_call_id">>, Cancelling)),
    ?assertEqual({error, invalid_state}, advance(SecondId, token(Active), attempt_ended, cause()))
end).

bounded_retry_preserves_order_test() -> with_store(fun(Store) ->
    Registration = kz_json:set_values([{<<"max_attempts">>, 2}, {<<"retry_delay">>, 15}], registration()),
    {ok, Initial} = create(Registration),
    Id = kz_doc:id(Initial),
    {ok, _} = activate(Id),
    {ok, First} = claim(Id),
    {ok, Retry} = advance(Id, token(First), attempt_ended, cause()),
    ?assertEqual(<<"retry_wait">>, value(<<"status">>, Retry)),
    ?assertEqual({error, not_due}, claim(Id)),
    clock(Store, ?NOW + 15),
    {ok, Second} = claim(Id),
    ?assertNotEqual(value(<<"pvt_caller_call_id">>, First), value(<<"pvt_caller_call_id">>, Second)),
    ?assertEqual({error, stale_lease}, advance(Id, token(First), attempt_ended, cause())),
    {ok, Failed} = advance(Id, token(Second), attempt_ended, cause()),
    ?assertEqual(<<"failed">>, value(<<"status">>, Failed)),
    [?assertEqual(value(Key, Initial), value(Key, Failed)) || Key <- [<<"enqueued_at">>, <<"enqueue_sequence">>, <<"priority">>]],
    ?assertEqual({ok, Failed}, create(Registration)),
    ?assertEqual({error, invalid_state}, claim(Id))
end).

expiry_boundaries_test() -> with_store(fun(Store) ->
    Registration = kz_json:set_value(<<"ttl">>, 60, registration()),
    {ok, Doc} = create(Registration),
    Id = kz_doc:id(Doc),
    {ok, _} = activate(Id),
    ?assertEqual({error, not_expired}, acdc_callback_store:expire(?ACCOUNT, ?QUEUE, Id)),
    clock(Store, ?NOW + 60),
    ?assertEqual({error, expired}, claim(Id)),
    {ok, Expired} = acdc_callback_store:expire(?ACCOUNT, ?QUEUE, Id),
    ?assertEqual(<<"expired">>, value(<<"status">>, Expired)),
    ?assertEqual({ok, Expired}, acdc_callback_store:expire(?ACCOUNT, ?QUEUE, Id))
end).

private_fields_not_exposed_test() -> with_store(fun(_) ->
    Id = queued(),
    {ok, Doc} = claim(Id),
    Public = acdc_callback_store:public(Doc),
    ?assertEqual(Id, value(<<"id">>, Public)),
    ?assertEqual(<<"1001">>, value(<<"number">>, Public)),
    [?assertEqual(undefined, value(Key, Public)) || Key <- [<<"_rev">>, <<"pvt_lease">>, <<"pvt_caller_call_id">>, <<"pvt_account_db">>
                                                          ,<<"pvt_authority_id">>, <<"pvt_authority_type">>, <<"pvt_account_realm">>]],
    ?assertEqual(nomatch, binary:match(kz_json:encode(Public), token(Doc)))
end).

paginated_listing_scope_test() -> with_store(fun(_) ->
    {ok, First} = create(registration()),
    {ok, Second} = acdc_callback_store:create(?ACCOUNT, ?QUEUE, <<"second-call">>
                                            ,kz_json:set_value(<<"enqueue_sequence">>, 18, registration()), authority()),
    Key = [?QUEUE, ?NOW - 60, 17, kz_doc:id(First)],
    Rows = [kz_json:from_list([{<<"doc">>, First}, {<<"key">>, Key}])
            ,kz_json:from_list([{<<"doc">>, Second}, {<<"key">>, [?QUEUE, ?NOW - 60, 18, kz_doc:id(Second)]}])],
    meck:expect(kz_datamgr, get_results, fun(Db, <<"acdc_callbacks/by_queue">>, Options) ->
        ?assertEqual(db(), Db),
        ?assert(lists:member(include_docs, Options)),
        ?assertNot(lists:member({include_docs, true}, Options)),
        ?assertEqual([?QUEUE], proplists:get_value(startkey, Options)),
        ?assertEqual(2, proplists:get_value(limit, Options)),
        {ok, Rows}
    end),
    ?assertEqual({ok, [First], Key}, acdc_callback_store:list(?ACCOUNT, ?QUEUE, undefined, 1)),
    ?assertEqual({error, invalid_cursor}, acdc_callback_store:list(?ACCOUNT, ?QUEUE, [<<"other">>, ?NOW, 0, kz_doc:id(First)], 1)),
    ?assertEqual({error, invalid_limit}, acdc_callback_store:list(?ACCOUNT, ?QUEUE, undefined, 101)),
    meck:expect(kz_datamgr, get_results, fun(_, _, Options) ->
        ?assertEqual(Key ++ [kz_json:new()], proplists:get_value(startkey, Options)),
        ?assertEqual(undefined, proplists:get_value(skip, Options)),
        {ok, [lists:last(Rows)]}
    end),
    ?assertEqual({ok, [Second], undefined}, acdc_callback_store:list(?ACCOUNT, ?QUEUE, Key, 1))
end).

storage_errors_not_acknowledged_test() -> with_store(fun(_) ->
    meck:expect(kz_datamgr, save_doc, fun(_, _) -> {error, timeout} end),
    ?assertEqual({error, timeout}, create(registration())),
    meck:expect(kz_datamgr, open_doc, fun(_, _) -> {error, gateway_timeout} end),
    Id = <<"acdc-callback-", (binary:copy(<<"1">>, 64))/binary>>,
    ?assertEqual({error, gateway_timeout}, activate(Id)),
    ?assertEqual({error, gateway_timeout}, cancel(Id))
end).

registration() -> kz_json:from_list([{<<"number">>, <<"1001">>}, {<<"enqueued_at">>, ?NOW - 60}
                                    ,{<<"enqueue_sequence">>, 17}, {<<"priority">>, 3}]).
authority() -> kz_json:from_list([{<<"id">>, <<"callback-service-device">>}, {<<"type">>, <<"device">>}
                                 ,{<<"account_realm">>, <<"callback-test.invalid">>}]).
create(R) -> acdc_callback_store:create(?ACCOUNT, ?QUEUE, <<"original-caller-id">>, R, authority()).
queued() -> {ok, Doc} = create(registration()), {ok, _} = activate(kz_doc:id(Doc)), kz_doc:id(Doc).
activate(Id) -> acdc_callback_store:activate(?ACCOUNT, ?QUEUE, Id).
claim(Id) -> acdc_callback_store:claim(?ACCOUNT, ?QUEUE, Id, <<"worker-1">>, 30).
advance(Id, Token, Action, Data) -> acdc_callback_store:advance(?ACCOUNT, ?QUEUE, Id, Token, Action, Data).
get_doc(Id) -> acdc_callback_store:get(?ACCOUNT, ?QUEUE, Id).
cancel(Id) -> acdc_callback_store:cancel(?ACCOUNT, ?QUEUE, Id).
token(Doc) -> kz_json:get_value([<<"pvt_lease">>, <<"token">>], Doc).
value(Key, Doc) -> kz_json:get_value(Key, Doc).
cause() -> kz_json:from_list([{<<"cause">>, <<"no_answer">>}]).
db() -> kzs_util:format_account_db(?ACCOUNT).
clock(Store, Now) -> store_call(Store, {clock, Now}).

with_store(Fun) ->
    Store = spawn_link(fun() -> store_loop(#{}, ?NOW) end),
    meck:new([kz_datamgr, kz_time], [non_strict, no_link]),
    try
        meck:expect(kz_time, now_s, fun() -> store_call(Store, time) end),
        meck:expect(kz_datamgr, open_doc, fun(Db, Id) -> store_call(Store, {open, Db, Id}) end),
        meck:expect(kz_datamgr, save_doc, fun(Db, Doc) -> store_call(Store, {save, Db, Doc}) end),
        Fun(Store)
    after
        meck:unload([kz_datamgr, kz_time]),
        Store ! stop
    end.

store_call(Store, Message) ->
    Ref = make_ref(), Store ! {self(), Ref, Message},
    receive {Ref, Reply} -> Reply after 3000 -> error(store_timeout) end.
store_loop(Docs, Now) ->
    receive
        stop -> ok;
        {From, Ref, Message} ->
            {Reply, Next, Time} = store_reply(Message, Docs, Now),
            From ! {Ref, Reply}, store_loop(Next, Time)
    end.
store_reply(time, Docs, Now) -> {Now, Docs, Now};
store_reply({clock, Time}, Docs, _) -> {ok, Docs, Time};
store_reply(count, Docs, Now) -> {map_size(Docs), Docs, Now};
store_reply({open, Db, Id}, Docs, Now) ->
    Reply = case maps:find({Db, Id}, Docs) of {ok, D} -> {ok, D}; error -> {error, not_found} end,
    {Reply, Docs, Now};
store_reply({put, Db, Doc}, Docs, Now) -> {ok, Docs#{{Db, kz_doc:id(Doc)} => Doc}, Now};
store_reply({save, Db, Doc}, Docs, Now) ->
    Key = {Db, kz_doc:id(Doc)},
    Existing = maps:get(Key, Docs, kz_json:new()),
    case kz_doc:revision(Doc) =:= kz_doc:revision(Existing) of
        false -> {{error, conflict}, Docs, Now};
        true ->
            N = case kz_doc:revision(Existing) of undefined -> 1; Rev -> binary_to_integer(Rev) + 1 end,
            Saved = kz_doc:set_revision(Doc, integer_to_binary(N)),
            {{ok, Saved}, Docs#{Key => Saved}, Now}
    end.
