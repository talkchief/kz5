-module(kapi_registration_collection_tests).
-include_lib("eunit/include/eunit.hrl").

part(Node, Sequence, Regs) ->
    frame(<<"search_partial_resp">>, Node, [{<<"Registrar-Sequence">>, Sequence}
                                          ,{<<"Registrations">>, Regs}]).
done(Node, Count) ->
    frame(<<"search_resp">>, Node, [{<<"Registrar-Parts">>, Count}, {<<"Registrations">>, []}]).
frame(Event, Node, Fields) ->
    kz_json:from_list([{<<"Event-Category">>, <<"registration">>}, {<<"Event-Name">>, Event}
                     ,{<<"Registrar-Node">>, Node}, {<<"Msg-ID">>, <<"registration-test-query">>}
                     | Fields]).
complete(Rs, Count) -> kapi_registration:collect_results(Rs, {0, Count}).

final_before_partial_is_not_empty_registry_test() ->
    Final = done(<<"one">>, 1),
    ?assertNot(complete([Final], 1)),
    ?assert(complete([part(<<"one">>, 1, [<<"phone@example.invalid">>]), Final], 1)).

out_of_order_multiple_parts_test() ->
    Final = done(<<"one">>, 3),
    P1 = part(<<"one">>, 1, [<<"one">>]), P2 = part(<<"one">>, 2, [<<"two">>]),
    P3 = part(<<"one">>, 3, [<<"three">>]),
    ?assertNot(complete([P3, Final, P1], 1)),
    ?assert(complete([P2, P3, Final, P1], 1)).

duplicate_parts_and_finals_are_idempotent_test() ->
    P = part(<<"one">>, 1, [<<"phone">>]), F = done(<<"one">>, 1),
    ?assert(complete([P, P, F, F], 1)),
    ?assertNot(complete([P, P, F, F], 2)).

multiple_registrars_must_each_be_complete_test() ->
    A = [part(<<"one">>, 1, [<<"a">>]), done(<<"one">>, 1)],
    B = [part(<<"two">>, 1, [<<"b">>]), done(<<"two">>, 1)],
    ?assertNot(complete(A ++ [done(<<"two">>, 1)], 2)),
    ?assert(complete(B ++ A, 2)).

explicit_zero_parts_proves_empty_registry_test() ->
    ?assert(complete([done(<<"one">>, 0)], 1)),
    ?assertEqual([], kapi_registration:finish_search({ok, [done(<<"one">>, 0)]}, 1)).

missing_part_timeout_is_unavailable_not_offline_test() ->
    ?assertEqual({error, incomplete_registration_response},
                 kapi_registration:finish_search({timeout, [done(<<"one">>, 1)]}, 1)).

legacy_frames_wait_until_bounded_timeout_then_remain_unknown_test() ->
    LegacyFinal = kz_json:delete_keys([<<"Registrar-Node">>, <<"Registrar-Parts">>], done(<<"one">>, 0)),
    LegacyPart = kz_json:delete_keys([<<"Registrar-Node">>, <<"Registrar-Sequence">>], part(<<"one">>, 1, [<<"phone">>])),
    ?assertNot(complete([LegacyFinal], 1)),
    ?assertNot(complete([LegacyPart, LegacyFinal], 1)),
    ?assertEqual({error, incomplete_registration_response},
                 kapi_registration:finish_search({timeout, [LegacyPart, LegacyFinal]}, 1)).

missing_registrar_discovery_is_not_empty_test() ->
    ?assertNot(complete([done(<<"one">>, 0)], 0)),
    ?assertEqual({error, incomplete_registration_response}, kapi_registration:finish_search({timeout, []}, 0)).

conflicting_duplicate_part_is_rejected_test() ->
    ?assertNot(complete([part(<<"one">>, 1, [<<"a">>]), part(<<"one">>, 1, [<<"b">>]), done(<<"one">>, 1)], 1)).

conflicting_final_counts_are_rejected_test() ->
    ?assertNot(complete([done(<<"one">>, 0), done(<<"one">>, 1)], 1)).

sequence_bounds_and_gap_are_rejected_test() ->
    [?assertNot(complete([part(<<"one">>, N, []), done(<<"one">>, 1)], 1)) || N <- [0, -1, 1000001, <<"1">>, 2]],
    [?assertNot(complete([done(<<"one">>, N)], 1)) || N <- [-1, 1000001, <<"0">>]].

cross_request_frames_cannot_complete_test() ->
    Other = kz_json:set_value(<<"Msg-ID">>, <<"other-request">>, part(<<"one">>, 1, [])),
    ?assertNot(complete([Other, done(<<"one">>, 1)], 1)).

complete_result_preserves_public_list_and_deduplicates_test() ->
    Rs = [part(<<"one">>, 1, [<<"b">>, <<"a">>]), part(<<"two">>, 1, [<<"a">>]),
          done(<<"one">>, 1), done(<<"two">>, 1)],
    ?assertEqual([<<"a">>, <<"b">>], kapi_registration:finish_search({ok, Rs}, 2)),
    ?assertEqual([<<"a">>, <<"b">>], kapi_registration:finish_search({timeout, Rs}, 2)),
    ?assertEqual({error, offline}, kapi_registration:finish_search({error, offline}, 2)).

amqp_builders_preserve_sequence_metadata_test() ->
    Default = kz_api:default_headers(<<"registration-test">>, <<"1">>),
    P = kz_json:set_values(Default, part(<<"one">>, 1, [<<"phone">>])),
    F = kz_json:set_values(Default, done(<<"one">>, 1)),
    {ok, PBin} = kapi_registration:search_partial_resp(P),
    {ok, FBin} = kapi_registration:search_resp(F),
    ?assertEqual(1, kz_json:get_value(<<"Registrar-Sequence">>, kz_json:decode(PBin))),
    ?assertEqual(1, kz_json:get_value(<<"Registrar-Parts">>, kz_json:decode(FBin))),
    ?assertEqual(<<"one">>, kz_json:get_value(<<"Registrar-Node">>, kz_json:decode(FBin))).

crossbar_returns_503_without_claiming_offline_test() ->
    mock_crossbar(fun() ->
        meck:expect(kapi_registration, search_realm_regs, fun(_, _) -> {error, incomplete_registration_response} end),
        C = cb_context:setters(cb_context:new(), [{fun cb_context:set_account_id/2, <<"account">>}
                                               ,{fun cb_context:set_req_verb/2, <<"GET">>}]),
        Result = cb_devices:validate(C, <<"status">>),
        ?assertEqual(503, cb_context:resp_error_code(Result)),
        ?assertEqual(error, cb_context:resp_status(Result)),
        ?assertNot(meck:called(crossbar_view, find, '_'))
    end).

crossbar_complete_snapshot_maps_true_and_false_correctly_test() ->
    mock_crossbar(fun() ->
        meck:expect(kapi_registration, search_realm_regs, fun(_, _) -> [<<"PHONE@example.invalid">>] end),
        meck:expect(crossbar_view, find, fun(C, _, _, Options) ->
            Mapper = props:get_value(mapper, Options),
            Row = fun(U, I) -> kz_json:from_list([{<<"id">>, I}, {<<"value">>, kz_json:from_list(
                [{<<"username">>, U}, {<<"device_type">>, <<"softphone">>}])}]) end,
            cb_context:set_resp_data(C, Mapper(Row(<<"phone">>, <<"registered">>),
                Mapper(Row(<<"other">>, <<"offline">>), []))) end),
        C = cb_context:setters(cb_context:new(), [{fun cb_context:set_account_id/2, <<"account">>}
                                               ,{fun cb_context:set_req_verb/2, <<"GET">>}]),
        [Online, Offline] = cb_context:resp_data(cb_devices:validate(C, <<"status">>)),
        ?assertEqual(true, kz_json:get_value(<<"registered">>, Online)),
        ?assertEqual(false, kz_json:get_value(<<"registered">>, Offline))
    end).

mock_crossbar(Test) ->
    Mods = [kapi_registration, kapps_config, kzd_accounts, crossbar_view],
    [meck:new(M, [non_strict, no_link]) || M <- Mods],
    try
        meck:expect(kapps_config, get_ne_binaries, fun(_, _, Default) -> Default end),
        meck:expect(kzd_accounts, fetch_realm, fun(_) -> <<"example.invalid">> end),
        Test()
    after [meck:unload(M) || M <- Mods] end.
