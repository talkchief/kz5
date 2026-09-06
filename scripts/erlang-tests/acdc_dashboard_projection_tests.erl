-module(acdc_dashboard_projection_tests).
-include_lib("eunit/include/eunit.hrl").
-include("acdc_stats.hrl").

new() -> {ok, P} = acdc_dashboard_projection:new(<<"a">>, [<<"q">>], 100, 200, 250), P.
source() -> #{observation_started => 240, observation_finished => 250, exhausted => true}.
row(Call, Status, E, H, P, A) ->
    #call_stat{id = <<Call/binary, "::q">>, call_id=Call, account_id = <<"a">>, queue_id = <<"q">>,
               status=Status, entered_timestamp=E, handled_timestamp=H,
               processed_timestamp=P, abandoned_timestamp=A}.
waiting(Call, E) -> row(Call, <<"waiting">>, E, undefined, undefined, undefined).
result(Rows) ->
    {ok, P} = acdc_dashboard_projection:add(new(), Rows),
    {ok, R} = acdc_dashboard_projection:finish(P, source()), R.
counts(R) -> [Q] = maps:get(queues, R), maps:get(metrics, Q).

empty_complete_not_missing_test() ->
    C = counts(result([])),
    ?assertEqual(0, maps:get(current_waiting, C)),
    ?assertEqual(undefined, maps:get(average_answered_wait_seconds, C)),
    ?assertEqual(undefined, maps:get(max_current_wait_seconds, C)).

older_active_call_survives_cohort_filter_test() ->
    C = counts(result([waiting(<<"old">>, 1), row(<<"busy">>, <<"handled">>, 50, 60, undefined, undefined)])),
    ?assertEqual(1, maps:get(current_waiting, C)),
    ?assertEqual(1, maps:get(current_handled, C)),
    ?assertEqual(249, maps:get(max_current_wait_seconds, C)),
    ?assertEqual(0, maps:get(records_entered, C)).

cohort_reconciles_and_uses_actual_timestamps_test() ->
    R = result([waiting(<<"w">>, 100), row(<<"h">>, <<"handled">>, 110, 120, undefined, undefined),
                row(<<"p">>, <<"processed">>, 120, 140, 190, undefined),
                row(<<"a">>, <<"abandoned">>, 130, undefined, undefined, 150)]),
    C = counts(R),
    ?assertEqual(4, maps:get(records_entered, C)),
    ?assertEqual(4, lists:sum([maps:get(K, C) || K <- [waiting_in_cohort, handled_in_cohort,
                                                    processed_in_cohort, abandoned_in_cohort]])),
    ?assertEqual(15.0, maps:get(average_answered_wait_seconds, C)),
    ?assertEqual(50.0, maps:get(average_processed_talk_seconds, C)),
    ?assertEqual(false, maps:get(distinct_visit_metrics_available, R)),
    ?assertEqual(false, maps:get(workforce_metrics_available, R)),
    ?assertEqual(false, maps:get(atomic_snapshot, maps:get(source, R))).

inclusive_start_exclusive_end_test() ->
    C = counts(result([waiting(<<"before">>, 99), waiting(<<"start">>, 100),
                       waiting(<<"end">>, 200), waiting(<<"after">>, 201)])),
    ?assertEqual(4, maps:get(current_waiting, C)), ?assertEqual(1, maps:get(records_entered, C)).

duplicate_observation_not_double_counted_test() ->
    W = waiting(<<"same">>, 110), R = result([W, W#call_stat{caller_id_name = <<"changed display name">>}]),
    ?assertEqual(1, maps:get(current_waiting, counts(R))),
    ?assertEqual(2, maps:get(input_rows, maps:get(source, R))),
    ?assertEqual(1, maps:get(unique_records, maps:get(source, R))).

conflicting_same_identity_requires_resnapshot_test() ->
    W = waiting(<<"same">>, 110),
    ?assertEqual({error, conflicting_observation}, acdc_dashboard_projection:add(new(), [W, W#call_stat{entered_timestamp=120}])),
    ?assertEqual({error, conflicting_observation}, acdc_dashboard_projection:add(new(),
                   [W, W#call_stat{status = <<"handled">>, handled_timestamp=140}])).

scope_rejection_test_() ->
    W = waiting(<<"one">>, 110),
    [?_assertMatch({error, _}, acdc_dashboard_projection:add(new(), [Bad])) ||
        Bad <- [W#call_stat{account_id = <<"other">>}, W#call_stat{queue_id = <<"other">>},
                W#call_stat{id = <<"forged">>}, W#call_stat{call_id = <<>>},
                W#call_stat{call_id=binary:copy(<<"x">>, 257)}, #{status => waiting}, undefined]].

invalid_timeline_test_() ->
    [?_assertMatch({error, _}, acdc_dashboard_projection:add(new(), [Bad])) ||
        Bad <- [waiting(<<"c">>, 0), waiting(<<"c">>, 251),
                row(<<"c">>, <<"handled">>, 100, undefined, undefined, undefined),
                row(<<"c">>, <<"handled">>, 100, 99, undefined, undefined),
                row(<<"c">>, <<"processed">>, 100, 110, 109, undefined),
                row(<<"c">>, <<"abandoned">>, 100, undefined, undefined, 251),
                row(<<"c">>, <<"waiting">>, 100, 110, undefined, undefined),
                row(<<"c">>, <<"processed">>, 100, 110, 120, 115),
                row(<<"c">>, <<"unknown">>, 100, undefined, undefined, undefined)]].

incomplete_source_withholds_metrics_test() ->
    {ok, P} = acdc_dashboard_projection:add(new(), [waiting(<<"c">>, 100)]),
    {ok, R} = acdc_dashboard_projection:finish(P, (source())#{exhausted => false}),
    [Q] = maps:get(queues, R),
    ?assertEqual(undefined, maps:get(metrics, Q)),
    ?assertEqual(1, maps:get(current_waiting, maps:get(observed, Q))).

source_time_cannot_precede_observed_transition_test() ->
    {ok, P} = acdc_dashboard_projection:add(new(),
        [row(<<"newer">>, <<"handled">>, 100, 245, undefined, undefined)]),
    ?assertEqual({error, invalid_source_observation},
        acdc_dashboard_projection:finish(P, (source())#{observation_finished=>244})),
    ?assertMatch({ok, _}, acdc_dashboard_projection:finish(P, (source())#{observation_finished=>245})).

bounded_rows_including_duplicates_test() ->
    W = waiting(<<"c">>, 100),
    {ok, P} = acdc_dashboard_projection:add(new(), lists:duplicate(10000, W)),
    ?assertEqual({error, row_limit_exceeded}, acdc_dashboard_projection:add(P, [W])),
    ?assertMatch({ok, _}, acdc_dashboard_projection:add(P, [])).

chunking_is_equivalent_test() ->
    A = waiting(<<"a">>, 100), B = waiting(<<"b">>, 150),
    {ok, P1} = acdc_dashboard_projection:add(new(), [A]),
    {ok, P2} = acdc_dashboard_projection:add(P1, [B, A]),
    ?assertEqual({ok, result([A, B, A])}, acdc_dashboard_projection:finish(P2, source())).

queue_order_and_isolation_test() ->
    {ok, P} = acdc_dashboard_projection:new(<<"a">>, [<<"z">>, <<"q">>], 100, 200, 250),
    {ok, P1} = acdc_dashboard_projection:add(P, [waiting(<<"c">>, 100)]),
    {ok, R} = acdc_dashboard_projection:finish(P1, source()),
    [Q, Z] = maps:get(queues, R),
    ?assertEqual(<<"q">>, maps:get(queue_id, Q)), ?assertEqual(<<"z">>, maps:get(queue_id, Z)),
    ?assertEqual(0, maps:get(current_waiting, maps:get(metrics, Z))).

invalid_arguments_test_() ->
    [?_assertMatch({error, _}, F()) || F <- [
        fun() -> acdc_dashboard_projection:new(<<"a">>, [], 100, 200, 250) end,
        fun() -> acdc_dashboard_projection:new(<<"a">>, [<<"q">>, <<"q">>], 100, 200, 250) end,
        fun() -> acdc_dashboard_projection:new(<<"a">>, [integer_to_binary(I) || I <- lists:seq(1, 101)], 100, 200, 250) end,
        fun() -> acdc_dashboard_projection:new(<<"a">>, [<<"q">>], 100, 200, 199) end,
        fun() -> acdc_dashboard_projection:new(<<"a">>, [<<"q">>], 100, 100, 250) end,
        fun() -> acdc_dashboard_projection:new(<<"a">>, [<<"q">>], 1, 86402, 86402) end,
        fun() -> acdc_dashboard_projection:add(new(), [waiting(<<"c">>, 100)|bad]) end,
        fun() -> acdc_dashboard_projection:finish(new(), (source())#{observation_finished=>251}) end,
        fun() -> acdc_dashboard_projection:finish(new(), (source())#{observation_started=>251}) end,
        fun() -> acdc_dashboard_projection:finish(new(), (source())#{exhausted=>unknown}) end,
        fun() -> acdc_dashboard_projection:finish(new(), (source())#{invented=>true}) end]].
