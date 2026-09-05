-module(acdc_queue_strategy_tests).
-include_lib("eunit/include/eunit.hrl").
-include("acdc.hrl").
-include("acdc_queue_manager.hrl").

j(P) -> kz_json:from_list(P).
r(Id, P, Idle) -> j([{<<"Agent-ID">>, Id}, {<<"Process-ID">>, P}, {<<"Idle-Time">>, Idle}]).
r(Id) -> r(Id, <<Id/binary, "-process">>, 0).
ids(Rs) -> lists:usort([kz_json:get_value(<<"Agent-ID">>, R) || R <- Rs]).
qstate(Props) -> acdc_queue_fsm:callback_test_state(Props).
qfield(Name, S) -> acdc_queue_fsm:callback_test_field(Name, S).

round_robin_rotates_ready_fifo_test() ->
    Rs = [r(<<"a">>), r(<<"b">>), r(<<"c">>)],
    {W1, _, Ready1, []} = acdc_queue_strategy:select(rr, [<<"a">>, <<"b">>, <<"c">>], [], [], Rs),
    {W2, _, Ready2, []} = acdc_queue_strategy:select(rr, Ready1, [], [], Rs),
    {W3, _, _, []} = acdc_queue_strategy:select(rr, Ready2, [], [], Rs),
    ?assertEqual([[<<"a">>], [<<"b">>], [<<"c">>]], [ids(W1),ids(W2),ids(W3)]).

round_robin_skips_missing_and_busy_responders_test() ->
    {Wins, _, Ready, []} = acdc_queue_strategy:select(rr, [<<"a">>, <<"b">>, <<"c">>], [], [], [r(<<"busy">>),r(<<"b">>)]),
    ?assertEqual([<<"b">>], ids(Wins)), ?assertEqual([<<"c">>,<<"a">>,<<"b">>], Ready).

most_idle_is_one_agent_not_simultaneous_test() ->
    Rs = [r(<<"a">>,<<"a1">>,3), r(<<"b">>,<<"b1">>,20), r(<<"b">>,<<"b2">>,18)],
    {W, O, _, _} = acdc_queue_strategy:select(mi, [<<"a">>,<<"b">>], [], [], Rs),
    ?assertEqual([<<"b">>], ids(W)), ?assertEqual(2,length(W)), ?assertEqual([<<"a">>],ids(O)).

most_idle_ties_are_deterministic_test() ->
    {W, _, _, _} = acdc_queue_strategy:select(mi, [<<"b">>,<<"a">>], [], [], [r(<<"b">>),r(<<"a">>)]),
    ?assertEqual([<<"a">>],ids(W)).

ring_all_deduplicates_processes_and_excludes_unavailable_test() ->
    A = r(<<"a">>), B = r(<<"b">>),
    {W, [], _, []} = acdc_queue_strategy:select(all, [<<"a">>,<<"b">>], [], [], [A,A,B,r(<<"busy">>)]),
    ?assertEqual([<<"a">>,<<"b">>],ids(W)), ?assertEqual(2,length(W)).

empty_or_uncorrelatable_responses_are_bounded_test() ->
    ?assertEqual(undefined, acdc_queue_strategy:select(rr, [], [], [], [r(<<"a">>)])),
    ?assertEqual(undefined, acdc_queue_strategy:select(all, [<<"a">>], [], [], [j([{<<"Agent-ID">>,<<"a">>}])])).

ordered_priority_then_stable_unlisted_and_new_cycle_test() ->
    Ready = [<<"c">>,<<"a">>,<<"b">>], Rs = [r(I) || I <- Ready],
    {W1, _, _, A1} = acdc_queue_strategy:select(ord, Ready, [<<"b">>], [], Rs),
    {W2, _, _, A2} = acdc_queue_strategy:select(ord, Ready, [<<"b">>], A1, Rs),
    {W3, _, _, A3} = acdc_queue_strategy:select(ord, Ready, [<<"b">>], A2, Rs),
    {W4, _, _, A4} = acdc_queue_strategy:select(ord, Ready, [<<"b">>], A3, Rs),
    ?assertEqual([[<<"b">>],[<<"a">>],[<<"c">>],[<<"b">>]], [ids(W1),ids(W2),ids(W3),ids(W4)]),
    ?assertEqual([<<"b">>], A4).

ordered_skips_unavailable_and_separate_calls_start_at_top_test() ->
    Rs=[r(<<"a">>),r(<<"b">>)],
    {W,_,_,_}=acdc_queue_strategy:select(ord,[<<"b">>],[<<"a">>,<<"b">>],[],Rs),
    ?assertEqual([<<"b">>],ids(W)),
    {First,_,_,_}=acdc_queue_strategy:select(ord,[<<"a">>,<<"b">>],[<<"a">>,<<"b">>],[],Rs),
    ?assertEqual([<<"a">>],ids(First)).

configuration_refresh_preserves_membership_and_inflight_agents_test() ->
    SS=#strategy_state{agents=queue:from_list([<<"b">>,<<"a">>]),ringing_agents=[<<"r">>],busy_agents=[<<"x">>]},
    S=#state{strategy=rr,strategy_state=SS,known_agents=dict:store(<<"a">>,1,dict:new()),current_member_calls=[preserved]},
    M=acdc_queue_manager:update_properties(j([{<<"strategy">>,<<"most_idle">>}]),S),
    ?assertEqual([<<"b">>,<<"a">>], (M#state.strategy_state)#strategy_state.agents),
    O=acdc_queue_manager:update_properties(j([{<<"strategy">>,<<"in_order">>},{<<"agent_order">>,[<<"a">>]}]),M),
    ?assertEqual(ord,O#state.strategy), ?assertEqual([<<"a">>],O#state.agent_order),
    ?assertEqual(SS,O#state.strategy_state), ?assertEqual(S#state.known_agents,O#state.known_agents),
    ?assertEqual([preserved],O#state.current_member_calls),
    ?assertEqual(3,acdc_queue_manager:assignable_agent_count(O)).

manager_selection_is_atomic_test() ->
    S=#state{strategy=ord,agent_order=[<<"b">>,<<"a">>],strategy_state=#strategy_state{agents=queue:from_list([<<"a">>,<<"b">>])}},
    {reply,{W,_,[<<"b">>]},S1}=acdc_queue_manager:handle_call({pick_winner,[r(<<"a">>),r(<<"b">>)],[]},self(),S),
    ?assertEqual([<<"b">>],ids(W)), ?assertEqual(S,S1).

one_broadcast_per_agent_with_process_correlation_test() ->
    A=r(<<"a">>,<<"p1">>,0), A2=r(<<"a">>,<<"p2">>,0), B=r(<<"b">>),
    ?assertEqual([A,B],acdc_queue_strategy:unique_agents([A,A2,A,B])),
    ?assert(acdc_queue_strategy:process_matches(A,A)),
    ?assertNot(acdc_queue_strategy:process_matches(A,A2)),
    ?assertNot(acdc_queue_strategy:process_matches(j([]),j([]))).

with_mocks(Fun) ->
    Mods=[acdc_queue_listener,acdc_stats,acdc_agent_listener,acdc_agent_stats,webseq],
    [meck:new(M,[non_strict,no_link]) || M <- Mods],
    try
        meck:expect(acdc_queue_listener,timeout_agent,fun(_,_) -> ok end),
        meck:expect(acdc_queue_listener,member_connect_satisfied,fun(_,_,_) -> ok end),
        meck:expect(acdc_queue_listener,finish_member_call,fun(_) -> ok end),
        meck:expect(acdc_stats,call_handled,fun(_,_,_,_) -> ok end),
        meck:expect(acdc_stats,call_missed,fun(_,_,_,_,_) -> ok end),
        meck:expect(acdc_agent_listener,channel_hungup,fun(_,_) -> ok end),
        meck:expect(acdc_agent_listener,presence_update,fun(_,_) -> ok end),
        meck:expect(acdc_agent_listener,send_availability_update,fun(_,_) -> ok end),
        meck:expect(acdc_agent_stats,agent_ready,fun(_,_) -> ok end),
        meck:expect(acdc_agent_stats,agent_logged_out,fun(_,_) -> ok end),
        meck:expect(webseq,evt,fun(_,_,_,_) -> ok end),
        kz_log:put_callid(<<"strategy-test">>), Fun()
    after [meck:unload(M) || M <- Mods], drain() end.
drain() -> receive {timeout,_,_} -> drain(); {'$gen_cast',_} -> drain() after 0 -> ok end.

stale_ring_timer_cannot_change_selection_test() -> with_mocks(fun() ->
    S=qstate([{agent_ring_timer_ref,make_ref()},{member_call_winners,[r(<<"a">>),r(<<"b">>)]}]),
    ?assertEqual({next_state,connecting,S},acdc_queue_fsm:connecting(info,{timeout,make_ref(),agent_timer_expired},S)),
    ?assertEqual(0,meck:num_calls(acdc_queue_listener,timeout_agent,'_'))
end).

ring_all_timeout_cancels_every_selected_process_test() -> with_mocks(fun() ->
    Ref=make_ref(), W=[r(<<"a">>),r(<<"b">>)],
    S=qstate([{agent_ring_timer_ref,Ref},{member_call_winners,W},{connect_wins,W},{attempted_agents,[<<"a">>]}]),
    {next_state,connect_req,N}=acdc_queue_fsm:connecting(info,{timeout,Ref,agent_timer_expired},S),
    ?assertEqual(2,meck:num_calls(acdc_queue_listener,timeout_agent,'_')),
    ?assertEqual([],qfield(connect_wins,N)), ?assertEqual([],qfield(member_call_winners,N)),
    ?assertEqual([<<"a">>],qfield(attempted_agents,N))
end).

accept_requires_selected_process_and_cancels_losers_only_test() -> with_mocks(fun() ->
    Call=kapps_call:set_call_id(<<"caller">>,kapps_call:new()), A=r(<<"a">>), B=r(<<"b">>),
    S=qstate([{member_call,Call},{queue_id,<<"queue">>},{agent_ring_timer_ref,make_ref()},{member_call_winners,[A,B]},{connect_wins,[A,B]}]),
    Wrong=kz_json:set_value(<<"Call-ID">>,<<"caller">>,r(<<"outsider">>)),
    ?assertEqual({next_state,connecting,S},acdc_queue_fsm:connecting(cast,{accepted,Wrong},S)),
    Accept=kz_json:set_value(<<"Call-ID">>,<<"caller">>,A),
    {next_state,ready,_,hibernate}=acdc_queue_fsm:connecting(cast,{accepted,Accept},S),
    ?assertEqual(1,meck:num_calls(acdc_queue_listener,member_connect_satisfied,'_')),
    ?assert(meck:called(acdc_queue_listener,member_connect_satisfied,['_',B,[]]))
end).

late_accept_before_new_selection_is_ignored_test() ->
    S=qstate([]), ?assertEqual({next_state,connect_req,S},acdc_queue_fsm:connect_req(cast,{accepted,j([])},S)).

callback_completion_cancels_only_other_agents_test_() -> {timeout,30,fun() -> with_mocks(fun() ->
    meck:new(acdc_callback_store,[non_strict,no_link]),
    try
        A=r(<<"a">>), A2=r(<<"a">>,<<"other-process">>,0), B=r(<<"b">>),
        Saved=j([{<<"_id">>,<<"callback">>},{<<"status">>,<<"completed">>},
                 {<<"pvt_caller_call_id">>,<<"caller">>},{<<"pvt_agent_call_id">>,<<"agent-leg">>}]),
        meck:expect(acdc_callback_store,bind_leg,fun(_,_,_,_,agent,<<"agent-leg">>) -> {ok,Saved} end),
        meck:expect(acdc_callback_store,advance,fun(_,_,_,_,bridged,_) -> {ok,Saved} end),
        meck:expect(acdc_queue_listener,retire_callback_member,fun(_,<<"callback">>) -> ok end),
        Call=kapps_call:set_call_id(<<"caller">>,kapps_call:new()),
        S=qstate([{member_call,Call},{queue_id,<<"queue">>},{connect_wins,[A,A2,B]},
                  {callback_ctx,#{mode=>native,reservation=>Saved,token=><<"token">>}}]),
        {next_state,ready,_}=acdc_queue_fsm:callback_commit(<<"agent-leg">>,A,S),
        ?assertEqual(1,meck:num_calls(acdc_queue_listener,member_connect_satisfied,'_')),
        ?assert(meck:called(acdc_queue_listener,member_connect_satisfied,['_',B,[]]))
    after meck:unload(acdc_callback_store) end
end) end}.

ring_all_loser_is_not_failure_or_unsolicited_logout_test() -> with_mocks(fun() ->
    S=acdc_agent_fsm:strategy_test_state([{member_call_id,<<"caller">>},{statem_call_id,<<"test">>},{connect_failures,2},{max_connect_failures,3}]),
    E=j([{<<"Call">>,j([{<<"Call-ID">>,<<"caller">>}])}]),
    {next_state,ready,N}=acdc_agent_fsm:ringing(cast,{member_connect_satisfied,E},S),
    ?assertEqual(2,acdc_agent_fsm:strategy_test_field(connect_failures,N)),
    ?assertEqual(0,meck:num_calls(acdc_agent_stats,agent_logged_out,'_')),
    ?assertEqual(undefined,acdc_agent_fsm:strategy_test_field(member_call_id,N))
end).

ring_all_loser_preserves_explicit_logout_request_test() -> with_mocks(fun() ->
    S=acdc_agent_fsm:strategy_test_state([{member_call_id,<<"caller">>},{statem_call_id,<<"test">>},{agent_state_updates,[{agent_logout}]}]),
    E=j([{<<"Call">>,j([{<<"Call-ID">>,<<"caller">>}])}]),
    {stop,normal,_}=acdc_agent_fsm:ringing(cast,{member_connect_satisfied,E},S),
    ?assertEqual(1,meck:num_calls(acdc_agent_stats,agent_logged_out,'_'))
end).
