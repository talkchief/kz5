%%% SPDX-License-Identifier: MPL-2.0
-module(acdc_callback_bridge_snapshot_tests).
-include_lib("eunit/include/eunit.hrl").

-define(CALLER, <<"returned-caller">>).
-define(AGENT, <<"agent-leg">>).
-define(ACCOUNT, <<"11111111111111111111111111111111">>).

reciprocal_answered_selected_pair_test() ->
    ?assertEqual({ok, ?AGENT}, prove(evidence())),
    E = evidence(), B = maps:get(bridge, E),
    ?assertEqual({ok, ?AGENT}, prove(E#{bridge => B#{call_ids => [?AGENT, ?CALLER]}})).

incomplete_conflicting_or_unselected_snapshot_test() ->
    E = evidence(),
    lists:foreach(fun(Bad) -> ?assertEqual(unknown, prove(Bad)) end,
                  [E#{complete => false}, E#{bridge => #{state => unknown}},
                   E#{bridge => #{state => bridged, call_ids => [?CALLER, <<"other">>]}},
                   E#{bridge => #{state => bridged, call_ids => [?AGENT, <<"other">>]}},
                   E#{bridge => #{state => bridged, call_ids => [?CALLER, ?CALLER]}}]),
    ?assertEqual(unknown, acdc_queue_fsm:callback_observed_agent({unknown, E}, ?CALLER, [?AGENT])),
    ?assertEqual(unknown, acdc_queue_fsm:callback_observed_agent({ok, E}, ?CALLER, [])),
    ?assertEqual(unknown, acdc_queue_fsm:callback_observed_agent(timeout, ?CALLER, [?AGENT])).

both_live_answered_same_node_reciprocal_channels_required_test() ->
    E = evidence(), [C, A] = maps:get(channels, E),
    BadPairs = [[C#{state => terminated}, A], [C, A#{state => terminated}],
                [C#{answered => false}, A], [C, A#{answered => false}],
                [C#{other_leg_call_id => <<"other">>}, A], [C, A#{other_leg_call_id => <<"other">>}],
                [C, A#{switch_node => <<"other-node">>}],
                [C#{switch_node => <<>>}, A#{switch_node => <<>>}],
                [C], [C, C, A]],
    lists:foreach(fun(Pair) -> ?assertEqual(unknown, prove(E#{channels => Pair})) end, BadPairs).

stale_probe_cannot_mutate_a_different_generation_test() ->
    Ref = make_ref(), State = state(#{bridge_probe_ref => Ref}),
    ?assertEqual({next_state, connecting, State},
                 acdc_queue_fsm:connecting(cast, {callback_bridge_snapshot, make_ref(), {ok, evidence()}}, State)),
    ?assertEqual({next_state, ready, State},
                 acdc_queue_fsm:ready(cast, {callback_bridge_snapshot, Ref, {ok, evidence()}}, State)),
    ?assertEqual({next_state, connecting, State},
                 acdc_queue_fsm:connecting(info, {timeout, make_ref(), callback_bridge_snapshot_retry}, State)).

bounded_async_probe_and_real_snapshot_transition_test_() ->
    {timeout, 30, fun bounded_async_probe_and_real_snapshot_transition/0}.

bounded_async_probe_and_real_snapshot_transition() ->
    Parent = self(), Modules = [acdc_callback_recovery_io, acdc_callback_store, acdc_queue_listener, acdc_stats],
    put(callback_snapshot_test_timers, []),
    erase(callback_snapshot_durable), erase(callback_snapshot_retired),
    ok = meck:new(Modules, [non_strict, no_link]),
    meck:expect(acdc_callback_recovery_io, observe, fun(Doc) ->
        Parent ! {queried_callback, Doc}, {unknown, #{complete => false}}
    end),
    meck:expect(acdc_callback_store, bind_leg, fun(_, _, _, _, agent, Leg) ->
        {ok, kz_json:set_value(<<"pvt_agent_call_id">>, Leg, reservation())}
    end),
    meck:expect(acdc_callback_store, advance, fun(_, _, _, _, bridged, _) -> {error, unavailable} end),
    meck:expect(acdc_queue_listener, retire_callback_member, fun(_, <<"fixture-callback">>) ->
        ?assertEqual(true, get(callback_snapshot_durable)), put(callback_snapshot_retired, true),
        Parent ! retired_callback, ok
    end),
    meck:expect(acdc_queue_listener, member_connect_satisfied, fun(_, _, _) -> ok end),
    meck:expect(acdc_stats, call_handled, fun(_, _, _, _) ->
        ?assertEqual(true, get(callback_snapshot_retired)), Parent ! handled_callback, ok
    end),
    try
        Initial = state(#{}), Accept = accepted(),
        {next_state, connecting, Waiting} = acdc_queue_fsm:connecting(cast, {accepted, Accept}, Initial),
        Context = context(Waiting), Ref = maps:get(bridge_probe_ref, Context), Deadline = track_timer(maps:get(timer_ref, Context)),
        receive {queried_callback, _} -> ok after 1000 -> error(no_probe) end,
        ?assertEqual(0, meck:num_calls(acdc_callback_store, bind_leg, '_')),
        ?assertEqual({next_state, connecting, Waiting}, acdc_queue_fsm:connecting(cast, {accepted, Accept}, Waiting)),
        ?assertEqual(1, meck:num_calls(acdc_callback_recovery_io, observe, '_')),
        Result = receive {'$gen_cast', {callback_bridge_snapshot, Ref, R}} -> R after 1000 -> error(no_result) end,
        {next_state, connecting, Retry} = acdc_queue_fsm:connecting(cast, {callback_bridge_snapshot, Ref, Result}, Waiting),
        ?assertEqual(Deadline, maps:get(timer_ref, context(Retry))),
        RetryRef = track_timer(maps:get(bridge_probe_ref, context(Retry))),
        ?assertEqual({next_state, connecting, Retry},
                     acdc_queue_fsm:connecting(cast, {callback_bridge_snapshot, Ref, {ok, evidence()}}, Retry)),
        _ = erlang:cancel_timer(RetryRef),
        meck:expect(acdc_callback_recovery_io, observe, fun(Doc) ->
            Parent ! {queried_callback, Doc}, {ok, evidence()}
        end),
        {next_state, connecting, Again} = acdc_queue_fsm:connecting(info, {timeout, RetryRef, callback_bridge_snapshot_retry}, Retry),
        NextRef = maps:get(bridge_probe_ref, context(Again)),
        ?assert(NextRef =/= Ref),
        ?assertEqual(Deadline, maps:get(timer_ref, context(Again))),
        receive {queried_callback, _} -> ok after 1000 -> error(no_second_probe) end,
        FreshResult = receive {'$gen_cast', {callback_bridge_snapshot, NextRef, R2}} -> R2 after 1000 -> error(no_second_result) end,
        {next_state, connecting, Proven} = acdc_queue_fsm:connecting(cast, {callback_bridge_snapshot, NextRef, FreshResult}, Again),
        ?assertEqual(?AGENT, maps:get(bridge_agent_leg, context(Proven))),
        ?assert(meck:num_calls(acdc_callback_store, bind_leg, '_') >= 1),
        ?assertEqual(1, meck:num_calls(acdc_callback_store, advance, '_')),
        ?assertEqual(false, erlang:read_timer(Deadline)),
        ?assertEqual(0, meck:num_calls(acdc_queue_listener, retire_callback_member, '_')),
        ?assertEqual(0, meck:num_calls(acdc_stats, call_handled, '_')),
        %% Neither a CAS conflict, terminal cancellation nor a completed row
        %% for different legs can retire this delivery or emit handled stats.
        Saved = kz_json:set_values([{<<"status">>, <<"completed">>}, {<<"pvt_agent_call_id">>, ?AGENT}], reservation()),
        Invalid = [{error, conflict},
                   {ok, kz_json:set_value(<<"status">>, <<"cancelled">>, Saved)},
                   {ok, kz_json:set_value(<<"pvt_caller_call_id">>, <<"other-caller">>, Saved)},
                   {ok, kz_json:set_value(<<"pvt_agent_call_id">>, <<"other-agent-leg">>, Saved)}],
        StillWaiting = lists:foldl(fun(Bad, S) ->
            meck:expect(acdc_callback_store, advance, fun(_, _, _, _, bridged, _) -> Bad end),
            {next_state, connecting, Next} = retry_commit(S),
            ?assertEqual(0, meck:num_calls(acdc_queue_listener, retire_callback_member, '_')),
            ?assertEqual(0, meck:num_calls(acdc_stats, call_handled, '_')),
            Next
        end, Proven, Invalid),
        meck:expect(acdc_callback_store, advance, fun(?ACCOUNT, <<"fixture-queue">>, <<"fixture-callback">>, <<"fixture-token">>, bridged, Data) ->
            ?assertEqual(?CALLER, kz_json:get_value(<<"caller_call_id">>, Data)),
            ?assertEqual(?AGENT, kz_json:get_value(<<"agent_call_id">>, Data)),
            put(callback_snapshot_durable, true), Parent ! durable_completed, {ok, Saved}
        end),
        {next_state, ready, Cleared} = retry_commit(StillWaiting),
        ?assertEqual(#{}, context(Cleared)),
        ?assertEqual(1, meck:num_calls(acdc_queue_listener, retire_callback_member, '_')),
        ?assertEqual(1, meck:num_calls(acdc_stats, call_handled, '_')),
        ?assertEqual(0, meck:num_calls(acdc_queue_listener, member_connect_satisfied, '_')),
        receive durable_completed -> ok after 0 -> error(completion_not_durable) end,
        receive retired_callback -> ok after 0 -> error(not_retired) end,
        receive handled_callback -> ok after 0 -> error(not_handled) end,
        ?assertEqual({next_state, ready, Cleared},
                     acdc_queue_fsm:ready(cast, {callback_bridge_snapshot, NextRef, FreshResult}, Cleared))
    after
        lists:foreach(fun erlang:cancel_timer/1, erase(callback_snapshot_test_timers)),
        erase(callback_snapshot_durable), erase(callback_snapshot_retired),
        meck:unload(Modules)
    end.

retry_commit(State) ->
    Ref = track_timer(maps:get(timer_ref, context(State))),
    _ = erlang:cancel_timer(Ref),
    acdc_queue_fsm:connecting(info, {timeout, Ref, callback_commit_retry}, State).

track_timer(Ref) ->
    put(callback_snapshot_test_timers, [Ref | get(callback_snapshot_test_timers)]), Ref.

prove(Evidence) -> acdc_queue_fsm:callback_observed_agent({ok, Evidence}, ?CALLER, [?AGENT]).
evidence() ->
    #{complete => true, bridge => #{state => bridged, call_ids => [?CALLER, ?AGENT]},
      channels => [#{call_id => ?CALLER, state => active, answered => true, other_leg_call_id => ?AGENT, switch_node => <<"fs@fixture">>},
                   #{call_id => ?AGENT, state => active, answered => true, other_leg_call_id => ?CALLER, switch_node => <<"fs@fixture">>}]}.
state(Extra) ->
    Call = kapps_call:set_call_id(?CALLER, kapps_call:new()),
    Context = maps:merge(#{mode => native, reservation => reservation(), token => <<"fixture-token">>}, Extra),
    acdc_queue_fsm:callback_test_state([{member_call, Call}, {account_id, ?ACCOUNT}, {queue_id, <<"fixture-queue">>},
                                       {callback_ctx, Context}, {connect_wins, [winner()]}]).
context(State) -> acdc_queue_fsm:callback_test_field(callback_ctx, State).
reservation() ->
    kz_json:from_list([{<<"_id">>, <<"fixture-callback">>}, {<<"pvt_account_id">>, ?ACCOUNT},
                      {<<"pvt_caller_call_id">>, ?CALLER}, {<<"original_call_id">>, <<"original">>}]).
winner() -> kz_json:from_list([{<<"Agent-ID">>, <<"selected-agent">>}, {<<"Process-ID">>, <<"selected-process">>}]).
accepted() -> kz_json:set_values([{<<"Account-ID">>, ?ACCOUNT}, {<<"Call-ID">>, ?CALLER}, {<<"Agent-Call-ID">>, ?AGENT}], winner()).
