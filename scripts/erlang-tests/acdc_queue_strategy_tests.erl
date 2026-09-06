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
        meck:expect(acdc_agent_listener,member_connect_retry,fun(_,_) -> ok end),
        meck:expect(acdc_agent_listener,member_connect_accepted,fun(_,_) -> ok end),
        meck:expect(acdc_agent_listener,presence_update,fun(_,_) -> ok end),
        meck:expect(acdc_agent_listener,send_availability_update,fun(_,_) -> ok end),
        meck:expect(acdc_agent_stats,agent_ready,fun(_,_) -> ok end),
        meck:expect(acdc_agent_stats,agent_logged_out,fun(_,_) -> ok end),
        meck:expect(acdc_agent_stats,agent_connected,fun(_,_,_,_,_,_) -> ok end),
        meck:expect(webseq,evt,fun(_,_,_,_) -> ok end),
        kz_log:put_callid(<<"strategy-test">>), Fun()
    after [meck:unload(M) || M <- Mods], drain() end.
drain() -> receive {timeout,_,_} -> drain(); {'$gen_cast',_} -> drain() after 0 -> ok end.

callback_resume_preserves_scope_through_real_manager_test_() ->
    {timeout,30,fun() -> callback_resume_scope_case(explicit) end}.

callback_menu_deadline_preserves_scope_through_real_manager_test_() ->
    {timeout,30,fun() -> callback_resume_scope_case(deadline) end}.

callback_resume_scope_case(Trigger) -> with_mocks(fun() ->
    Mods=[gen_listener,acdc_callback_store,kapi_acdc_callback,kapps_call_command,kapps_config],
    meck:new(Mods,[non_strict,no_link]),
    try
        Account = <<"11111111111111111111111111111111">>, Queue = <<"resume-queue">>,
        CallId = <<"resume-caller">>, PauseId = <<"resume-pause">>, Timer=make_ref(),
        meck:expect(kapps_call_command,set,fun(_,_,_) -> ok end),
        meck:expect(kapps_config,get_integer,fun(_,_,Default) -> Default end),
        Call=kapps_call:set_language(<<"en-us">>,kapps_call:set_caller_id_number(<<"fixture-sip-user">>,
               kapps_call:set_caller_id_name(<<"Resume fixture">>,
                 kapps_call:set_account_id(Account,kapps_call:set_call_id(CallId,kapps_call:new()))))),
        Manager=#state{account_id=Account,queue_id=Queue,current_member_calls=[Call]
                       ,strategy_state=#strategy_state{agents=queue:from_list([<<"agent">>])}
                       ,announcements_pids=#{CallId => self()}},
        meck:expect(gen_listener,call,fun(_, Request) ->
            {reply,Reply,_}=acdc_queue_manager:handle_call(Request,self(),Manager), Reply
        end),
        meck:expect(acdc_callback_store,find,fun(A,Q,C) ->
            ?assertEqual({Account,Queue,CallId},{A,Q,C}), {error,not_found}
        end),
        meck:expect(kapi_acdc_callback,publish_response,fun(_,_) -> ok end),
        meck:expect(acdc_queue_listener,delivery,fun(_) -> fixture_delivery end),
        meck:expect(acdc_queue_listener,member_connect_req,fun(_) -> ok end),
        meck:expect(webseq,note,fun(_,_,_,_) -> ok end),
        Request=j([{<<"Account-ID">>,Account},{<<"Queue-ID">>,Queue},{<<"Call-ID">>,CallId}
                   ,{<<"Request-ID">>,<<"resume-request">>},{<<"Server-ID">>,<<"resume-controller">>}
                   ,{<<"Operation">>,<<"pause">>}]),
        Context=#{request => Request,pause_id => PauseId,timer_ref => Timer,previous_state => ready},
        Initial=qstate([{member_call,Call},{account_id,Account},{queue_id,Queue}
                        ,{manager_proc,self()},{listener_proc,self()},{callback_ctx,Context}
                        ,{connection_timeout,30000}]),
        %% This is the real manager fallback that caused case_clause=ok in
        %% ready/3 when the old resume envelope contained only Call.
        ?assertEqual(ok,acdc_queue_manager:should_ignore_member_call(self(),Call,j([{<<"Call">>,kapps_call:to_json(Call)}]))),
        {next_state,ready,Resumed}=case Trigger of
            explicit ->
                Resume=kz_json:set_values([{<<"Operation">>,<<"resume">>},{<<"Pause-ID">>,PauseId}],Request),
                acdc_queue_fsm:callback_paused(cast,{callback_request,Resume},Initial);
            deadline -> acdc_queue_fsm:callback_paused(info,{timeout,Timer,callback_menu_deadline},Initial)
        end,
        receive
            {'$gen_cast',{check_if_next,Envelope,fixture_delivery}=Check} ->
                ?assertEqual(Account,kz_json:get_value(<<"Account-ID">>,Envelope)),
                ?assertEqual(Queue,kz_json:get_value(<<"Queue-ID">>,Envelope)),
                ?assertEqual(CallId,kz_json:get_value([<<"Call">>,<<"Call-ID">>],Envelope)),
                {next_state,connect_req,Connecting}=acdc_queue_fsm:ready(cast,Check,Resumed),
                ?assert(meck:called(gen_listener,call,['_',{should_ignore_member_call,{Account,Queue,CallId}}])),
                ?assertEqual(1,meck:num_calls(acdc_queue_listener,member_connect_req,'_')),
                [erlang:cancel_timer(qfield(Field,Connecting)) || Field <- [collect_ref,connection_timer_ref]]
        after 100 -> ?assert(false)
        end
    after meck:unload(Mods) end
end).

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
    S=qstate([{member_call,Call},{account_id,<<"account">>},{queue_id,<<"queue">>},{agent_ring_timer_ref,make_ref()},{member_call_winners,[A,B]},{connect_wins,[A,B]}]),
    Wrong=kz_json:set_value(<<"Call-ID">>,<<"caller">>,r(<<"outsider">>)),
    ?assertEqual({next_state,connecting,S},acdc_queue_fsm:connecting(cast,{accepted,Wrong},S)),
    Accept=accepted(A,<<"a-leg">>),
    {next_state,connecting,Pending}=acdc_queue_fsm:connecting(cast,{accepted,Accept},S),
    ?assertEqual(0,meck:num_calls(acdc_queue_listener,finish_member_call,'_')),
    {next_state,ready,_,hibernate}=acdc_queue_fsm:connecting(cast,{channel_bridged,bridge(<<"a-leg">>)},Pending),
    ?assertEqual(1,meck:num_calls(acdc_queue_listener,member_connect_satisfied,'_')),
    ?assert(meck:called(acdc_queue_listener,member_connect_satisfied,['_',B,[]]))
end).

accepted(A, Leg) -> kz_json:set_values([{<<"Call-ID">>,<<"caller">>},{<<"Account-ID">>,<<"account">>},{<<"Agent-Call-ID">>,Leg}], A).
bridge(Leg) -> j([{<<"Call-ID">>,<<"caller">>},{<<"Other-Leg-Call-ID">>,Leg},{<<"Custom-Channel-Vars">>,j([{<<"Account-ID">>,<<"account">>}])}]).
bridge_state() -> qstate([{member_call,kapps_call:set_call_id(<<"caller">>,kapps_call:new())},{account_id,<<"account">>},{queue_id,<<"queue">>},
                         {agent_ring_timer_ref,make_ref()},{member_call_winners,[r(<<"a">>),r(<<"b">>)]},{connect_wins,[r(<<"a">>),r(<<"b">>)]}]).

bridge_before_accept_and_losing_accept_first_test() -> with_mocks(fun() ->
    S=bridge_state(),
    {next_state,connecting,S1}=acdc_queue_fsm:connecting(cast,{accepted,accepted(r(<<"a">>),<<"losing-leg">>)},S),
    {next_state,connecting,S2}=acdc_queue_fsm:connecting(cast,{channel_bridged,bridge(<<"winning-leg">>)},S1),
    ?assertEqual(0,meck:num_calls(acdc_queue_listener,finish_member_call,'_')),
    ?assertEqual({keep_state,S2},acdc_queue_fsm:connecting(cast,{retry,r(<<"b">>)},S2)),
    ?assertEqual({keep_state,S2},acdc_queue_fsm:connecting(info,{timeout,make_ref(),agent_timer_expired},S2)),
    ?assertEqual({keep_state,S2},acdc_queue_fsm:connecting(info,{timeout,make_ref(),connection_timer_expired},S2)),
    {next_state,ready,_,hibernate}=acdc_queue_fsm:connecting(cast,{accepted,accepted(r(<<"b">>),<<"winning-leg">>)},S2),
    ?assertEqual(1,meck:num_calls(acdc_queue_listener,finish_member_call,'_')),
    ?assert(meck:called(acdc_queue_listener,member_connect_satisfied,['_',r(<<"a">>),[]]))
end).

bridge_wrong_account_call_empty_leg_and_duplicate_accept_test() -> with_mocks(fun() ->
    S=bridge_state(), A=accepted(r(<<"a">>),<<"a-leg">>),
    Bad=[kz_json:set_value(<<"Call-ID">>,<<"other">>,bridge(<<"a-leg">>)),
         kz_json:set_value([<<"Custom-Channel-Vars">>,<<"Account-ID">>],<<"other">>,bridge(<<"a-leg">>)),bridge(<<>>)],
    [?assertEqual({next_state,connecting,S},acdc_queue_fsm:connecting(cast,{channel_bridged,E},S)) || E <- Bad],
    {next_state,connecting,S1}=acdc_queue_fsm:connecting(cast,{accepted,A},S),
    ?assertEqual({next_state,connecting,S1},acdc_queue_fsm:connecting(cast,{accepted,A},S1)),
    ?assertEqual(1,maps:size(maps:get(accepts,qfield(bridge_ctx,S1)))),
    {next_state,ready,_,hibernate}=acdc_queue_fsm:connecting(cast,{channel_bridged,bridge(<<"a-leg">>)},S1)
end).

lost_acceptance_deadline_never_cancels_actual_bridge_test() -> with_mocks(fun() ->
    {next_state,connecting,S}=acdc_queue_fsm:connecting(cast,{channel_bridged,bridge(<<"a-leg">>)},bridge_state()),
    Ref=maps:get(timer_ref,qfield(bridge_ctx,S)),
    {keep_state,N}=acdc_queue_fsm:connecting(info,{timeout,Ref,ordinary_bridge_proof_timeout},S),
    erlang:cancel_timer(Ref),
    ?assertEqual(<<"a-leg">>,maps:get(leg,qfield(bridge_ctx,N))),
    ?assertEqual(0,meck:num_calls(acdc_queue_listener,finish_member_call,'_')),
    ?assertEqual(0,meck:num_calls(acdc_queue_listener,timeout_agent,'_'))
end).

media_loser_ringing_and_answered_never_logout_or_wrapup_test() -> with_mocks(fun() ->
    S=acdc_agent_fsm:strategy_test_state([{member_call_id,<<"caller">>},{agent_call_id,<<"a-leg">>},{statem_call_id,<<"test">>},{connect_failures,2},{max_connect_failures,3}]),
    lists:foreach(fun(F) ->
        {next_state,ready,N}=F(info,{call_down,<<"a-leg">>,<<"LOSE_RACE">>},S),
        ?assertEqual(2,acdc_agent_fsm:strategy_test_field(connect_failures,N))
    end,[fun acdc_agent_fsm:ringing/3,fun acdc_agent_fsm:answered/3]),
    ?assertEqual(0,meck:num_calls(acdc_agent_stats,agent_logged_out,'_'))
end).

agent_bridge_requires_own_actual_leg_not_shared_caller_test() -> with_mocks(fun() ->
    meck:new(acdc_util,[non_strict,no_link]),
    try
    meck:expect(acdc_util,caller_id,fun(_) -> {<<"1001">>,<<"Fixture">>} end),
    Call=kapps_call:set_call_id(<<"caller">>,kapps_call:new()),
    Props=[{member_call_id,<<"caller">>},{member_connect_id,<<"offer">>},{member_call,Call},{account_id,<<"account">>},{agent_id,<<"a">>}],
    S=acdc_agent_fsm:strategy_test_state(Props),
    Known=acdc_agent_fsm:strategy_test_state([{agent_call_id,<<"a-leg">>}|Props]),
    ?assertEqual({next_state,ringing,S},acdc_agent_fsm:ringing(cast,{channel_bridge_event,bridge(<<"b-leg">>)},S)),
    ?assertEqual({next_state,ringing,Known},acdc_agent_fsm:ringing(cast,{channel_bridge_event,bridge(<<"b-leg">>)},Known)),
    ?assertEqual({next_state,ringing,S},acdc_agent_fsm:ringing(cast,{channel_bridged,<<"caller">>},S)),
    Own=j([{<<"Call-ID">>,<<"a-leg">>},{<<"Other-Leg-Call-ID">>,<<"caller">>},
           {<<"Custom-Channel-Vars">>,j([{<<"Account-ID">>,<<"account">>},{<<"Agent-ID">>,<<"a">>},{<<"Member-Call-ID">>,<<"caller">>},{<<"Request-ID">>,<<"offer">>}])}]),
    Other=kz_json:set_value([<<"Custom-Channel-Vars">>,<<"Account-ID">>],<<"other">>,Own),
    ?assertEqual({next_state,ringing,S},acdc_agent_fsm:ringing(cast,{channel_bridge_event,Other},S)),
    {next_state,answered,Answered}=acdc_agent_fsm:ringing(cast,{channel_bridge_event,Own},S),
    ?assertEqual(<<"a-leg">>,acdc_agent_fsm:strategy_test_field(agent_call_id,Answered)),
    ?assertEqual(1,meck:num_calls(acdc_agent_stats,agent_connected,'_')),
    acdc_agent_fsm:call_event(self(),<<"call_event">>,<<"CHANNEL_BRIDGE">>,Own),
    receive {'$gen_cast',{channel_bridge_event,Own}} -> ok after 100 -> ?assert(false) end
    after meck:unload(acdc_util) end
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
    S=acdc_agent_fsm:strategy_test_state([{member_call_id,<<"caller">>},{member_connect_id,<<"offer">>},{statem_call_id,<<"test">>},{connect_failures,2},{max_connect_failures,3}]),
    E=j([{<<"Connect-ID">>,<<"offer">>},{<<"Call">>,j([{<<"Call-ID">>,<<"caller">>}])}]),
    {next_state,ready,N}=acdc_agent_fsm:ringing(cast,{member_connect_satisfied,E},S),
    ?assertEqual(2,acdc_agent_fsm:strategy_test_field(connect_failures,N)),
    ?assertEqual(0,meck:num_calls(acdc_agent_stats,agent_logged_out,'_')),
    ?assertEqual(undefined,acdc_agent_fsm:strategy_test_field(member_call_id,N))
end).

native_callback_losing_acceptance_does_not_preempt_media_winner_test_() -> {timeout,30,fun() -> with_mocks(fun() ->
    meck:new(acdc_callback_store,[non_strict,no_link]),
    try
        A=r(<<"a">>), B=r(<<"b">>),
        Saved=j([{<<"_id">>,<<"callback">>},{<<"status">>,<<"completed">>},
                 {<<"pvt_caller_call_id">>,<<"caller">>},{<<"pvt_agent_call_id">>,<<"b-leg">>}]),
        meck:expect(acdc_callback_store,bind_leg,fun(_,_,_,_,agent,<<"b-leg">>) -> {ok,Saved} end),
        meck:expect(acdc_callback_store,advance,fun(_,_,_,_,bridged,_) -> {ok,Saved} end),
        meck:expect(acdc_queue_listener,retire_callback_member,fun(_,<<"callback">>) -> ok end),
        Call=kapps_call:set_call_id(<<"caller">>,kapps_call:new()),
        S=qstate([{member_call,Call},{account_id,<<"account">>},{queue_id,<<"queue">>},{connect_wins,[A,B]},
                  {callback_ctx,#{mode=>native,reservation=>Saved,token=><<"token">>}}]),
        {next_state,connecting,S1}=acdc_queue_fsm:connecting(cast,{accepted,accepted(A,<<"a-leg">>)},S),
        {next_state,connecting,S2}=acdc_queue_fsm:connecting(cast,{channel_bridged,bridge(<<"b-leg">>)},S1),
        ?assertEqual(0,meck:num_calls(acdc_queue_listener,retire_callback_member,'_')),
        {next_state,ready,_}=acdc_queue_fsm:connecting(cast,{accepted,accepted(B,<<"b-leg">>)},S2),
        ?assertEqual(1,meck:num_calls(acdc_queue_listener,retire_callback_member,'_')),
        ?assert(meck:called(acdc_queue_listener,member_connect_satisfied,['_',A,[]]))
    after meck:unload(acdc_callback_store) end
end) end}.

ring_all_loser_preserves_explicit_logout_request_test() -> with_mocks(fun() ->
    S=acdc_agent_fsm:strategy_test_state([{member_call_id,<<"caller">>},{member_connect_id,<<"offer">>},{statem_call_id,<<"test">>},{agent_state_updates,[{agent_logout}]}]),
    E=j([{<<"Connect-ID">>,<<"offer">>},{<<"Call">>,j([{<<"Call-ID">>,<<"caller">>}])}]),
    {stop,normal,_}=acdc_agent_fsm:ringing(cast,{member_connect_satisfied,E},S),
    ?assertEqual(1,meck:num_calls(acdc_agent_stats,agent_logged_out,'_'))
end).
