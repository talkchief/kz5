%%% SPDX-License-Identifier: MPL-2.0
%%% Pure contract tests for the callback HTTP adapter. These tests deliberately
%%% avoid CouchDB and do not create, cancel, or otherwise mutate reservations.
-module(cb_queues_callback_api_tests).

-include_lib("eunit/include/eunit.hrl").

-define(QUEUE, <<"callback-test-queue">>).
-define(CALLBACK, <<"acdc-callback-0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef">>).

method_surface_is_read_cancel_only_test() ->
    ?assertEqual([<<"GET">>], cb_queues:allowed_methods(?QUEUE, <<"callbacks">>)),
    ?assertEqual([<<"GET">>, <<"DELETE">>]
                ,cb_queues:allowed_methods(?QUEUE, <<"callbacks">>, ?CALLBACK)),
    ?assertEqual(true, cb_queues:resource_exists(?QUEUE, <<"callbacks">>)),
    ?assertEqual(true, cb_queues:resource_exists(?QUEUE, <<"callbacks">>, ?CALLBACK)),
    ?assertEqual([], cb_queues:allowed_methods(?QUEUE, <<"unknown">>, ?CALLBACK)),
    ?assertEqual(false, cb_queues:resource_exists(?QUEUE, <<"unknown">>, ?CALLBACK)).

cursor_round_trip_and_scope_test() ->
    Cursor = [?QUEUE, 63950000000, 17, ?CALLBACK],
    Encoded = cb_queues:encode_callback_cursor(Cursor),
    ?assert(is_binary(Encoded)),
    ?assertEqual({ok, Cursor}, cb_queues:decode_callback_cursor(?QUEUE, Encoded)),
    ?assertEqual({error, invalid_cursor}
                ,cb_queues:decode_callback_cursor(<<"other-queue">>, Encoded)),
    ?assertEqual({ok, undefined}, cb_queues:decode_callback_cursor(?QUEUE, undefined)),
    ?assertEqual({ok, undefined}, cb_queues:decode_callback_cursor(?QUEUE, <<>>)).

malformed_cursor_rejected_test() ->
    BadShapes = [kz_json:encode([?QUEUE, -1, 17, ?CALLBACK])
                ,kz_json:encode([?QUEUE, 0, 17, ?CALLBACK])
                ,kz_json:encode([?QUEUE, 16#20000000000000, 17, ?CALLBACK])
                ,kz_json:encode([?QUEUE, 63950000000, -1, ?CALLBACK])
                ,kz_json:encode([?QUEUE, 63950000000, 16#20000000000000, ?CALLBACK])
                ,kz_json:encode([?QUEUE, 63950000000, 17])
                ,kz_json:encode([?QUEUE, 63950000000, 17, <<>>])
                ,kz_json:encode([?QUEUE, 63950000000, 17, <<"acdc-callback-deadbeef">>])
                ,kz_json:encode([?QUEUE, 63950000000, 17
                               ,<<"acdc-callback-ABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD">>])
                ,kz_json:encode(kz_json:from_list([{<<"queue_id">>, ?QUEUE}]))
                ],
    [?assertEqual({error, invalid_cursor}
                 ,cb_queues:decode_callback_cursor(?QUEUE, kz_base64url:encode(Bad)))
     || Bad <- BadShapes],
    ?assertEqual({error, invalid_cursor}, cb_queues:decode_callback_cursor(?QUEUE, <<"not+base64">>)),
    ?assertEqual({error, invalid_cursor}
                ,cb_queues:decode_callback_cursor(?QUEUE, binary:copy(<<"a">>, 2049))).

http_projection_is_strictly_allowlisted_test() ->
    Doc = kz_json:from_list(
            [{<<"_id">>, ?CALLBACK}
            ,{<<"_rev">>, <<"1-secret">>}
            ,{<<"pvt_created">>, 63950000001}
            ,{<<"pvt_modified">>, 63950000002}
            ,{<<"pvt_account_id">>, <<"account-secret">>}
            ,{<<"pvt_account_db">>, <<"account-db-secret">>}
            ,{<<"pvt_lease">>, kz_json:from_list([{<<"token">>, <<"lease-secret">>}])}
            ,{<<"pvt_caller_call_id">>, <<"caller-leg-secret">>}
            ,{<<"pvt_agent_call_id">>, <<"agent-leg-secret">>}
            ,{<<"queue_id">>, ?QUEUE}
            ,{<<"original_call_id">>, <<"original-call-secret">>}
            ,{<<"number">>, <<"+12025550123">>}
            ,{<<"status">>, <<"queued">>}
            ,{<<"attempts">>, 1}
            ,{<<"enqueued_at">>, 63950000000}
            ,{<<"enqueue_sequence">>, 17}
            ,{<<"priority">>, 3}
            ,{<<"language">>, <<"en-us">>}
            ,{<<"next_attempt_at">>, 63950000003}
            ,{<<"expires_at">>, 63950003600}
            ,{<<"last_cause">>, <<"no_answer">>}
            ,{<<"reconciliation_required">>, true}
            ,{<<"reconciliation_reason">>, <<"channel_snapshot_incomplete">>}
            ,{<<"future_private_field">>, <<"must-not-leak">>}
            ]),
    meck:new(kz_doc, [non_strict, no_link]),
    try
        meck:expect(kz_doc, id, fun(JObj) -> kz_json:get_value(<<"_id">>, JObj) end),
        meck:expect(kz_doc, created, fun(JObj) -> kz_json:get_value(<<"pvt_created">>, JObj) end),
        meck:expect(kz_doc, modified, fun(JObj) -> kz_json:get_value(<<"pvt_modified">>, JObj) end),
        Public = cb_queues:callback_public(Doc),
        ?assertEqual(?CALLBACK, kz_json:get_value(<<"id">>, Public)),
        ?assertEqual(?QUEUE, kz_json:get_value(<<"queue_id">>, Public)),
        ?assertEqual(63950000001, kz_json:get_value(<<"created">>, Public)),
        ?assertEqual(63950000002, kz_json:get_value(<<"modified">>, Public)),
        ?assertEqual(true, kz_json:is_true(<<"reconciliation_required">>, Public)),
        ?assertEqual(<<"channel_snapshot_incomplete">>,
                     kz_json:get_value(<<"reconciliation_reason">>, Public)),
        ?assertEqual(undefined, kz_json:get_value(<<"position">>, Public)),
        Sensitive = [<<"number">>, <<"original_call_id">>, <<"_rev">>, <<"pvt_created">>
                    ,<<"pvt_modified">>, <<"pvt_account_id">>, <<"pvt_account_db">>
                    ,<<"pvt_lease">>, <<"pvt_caller_call_id">>, <<"pvt_agent_call_id">>
                    ,<<"future_private_field">>],
        [?assertEqual(undefined, kz_json:get_value(Key, Public)) || Key <- Sensitive],
        Encoded = kz_json:encode(Public),
        [?assertEqual(nomatch, binary:match(Encoded, Secret))
         || Secret <- [<<"lease-secret">>, <<"caller-leg-secret">>, <<"agent-leg-secret">>
                      ,<<"original-call-secret">>, <<"+12025550123">>, <<"account-secret">>]]
    after
        meck:unload(kz_doc)
    end.

reconciliation_projection_is_fail_closed_and_omits_false_marker_test() ->
    meck:new(kz_doc, [non_strict, no_link]),
    try
        meck:expect(kz_doc, id, fun(JObj) -> kz_json:get_value(<<"_id">>, JObj) end),
        meck:expect(kz_doc, created, fun(_) -> undefined end),
        meck:expect(kz_doc, modified, fun(_) -> undefined end),
        Base = kz_json:from_list([{<<"_id">>, ?CALLBACK}, {<<"queue_id">>, ?QUEUE}
                                ,{<<"status">>, <<"dialing">>}]),
        FalseDoc = kz_json:set_values([{<<"reconciliation_required">>, false}
                                      ,{<<"reconciliation_reason">>, <<"engine_restart">>}], Base),
        FalsePublic = cb_queues:callback_public(FalseDoc),
        ?assertEqual(undefined, kz_json:get_value(<<"reconciliation_required">>, FalsePublic)),
        ?assertEqual(undefined, kz_json:get_value(<<"reconciliation_reason">>, FalsePublic)),
        UnknownDoc = kz_json:set_values([{<<"reconciliation_required">>, true}
                                        ,{<<"reconciliation_reason">>, <<"private_internal_error">>}], Base),
        UnknownPublic = cb_queues:callback_public(UnknownDoc),
        ?assertEqual(true, kz_json:is_true(<<"reconciliation_required">>, UnknownPublic)),
        ?assertEqual(undefined, kz_json:get_value(<<"reconciliation_reason">>, UnknownPublic))
    after
        meck:unload(kz_doc)
    end.

parent_queue_failure_never_queries_store_test() -> with_http_mocks(fun() ->
    meck:expect(crossbar_doc, load, fun(?QUEUE, context, _Options) -> parent_error end),
    meck:expect(cb_context, resp_status, fun(parent_error) -> error end),
    ?assertEqual(parent_error, cb_queues:validate_callback_list(context, ?QUEUE)),
    ?assertEqual(0, meck:num_calls(acdc_callback_store, list, '_')),
    ?assertEqual(0, meck:num_calls(acdc_callback_store, get, '_'))
end).

malformed_detail_path_fails_closed_test() -> with_http_mocks(fun() ->
    meck:expect(cb_context, add_system_error
               ,fun(faulty_request, context) -> malformed_path end),
    ?assertEqual(malformed_path
                ,cb_queues:validate(context, ?QUEUE, <<"unknown">>, ?CALLBACK)),
    ?assertEqual(malformed_path
                ,cb_queues:delete(context, ?QUEUE, <<"unknown">>, ?CALLBACK)),
    ?assertEqual(0, meck:num_calls(acdc_callback_store, get, '_')),
    ?assertEqual(0, meck:num_calls(acdc_callback_store, cancel, '_'))
end).

list_page_is_capped_and_clears_parent_etag_test() -> with_http_mocks(fun() ->
    meck:expect(crossbar_doc, load, fun(?QUEUE, context, _Options) -> loaded end),
    meck:expect(cb_context, resp_status, fun(loaded) -> success end),
    meck:expect(cb_context, req_value, fun(loaded, <<"cursor">>) -> undefined end),
    meck:expect(cb_context, pagination_page_size, fun(loaded) -> 1000 end),
    meck:expect(cb_context, account_id, fun(loaded) -> <<"account">> end),
    meck:expect(cb_context, resp_envelope, fun(loaded) -> kz_json:new() end),
    meck:expect(acdc_callback_store, list
               ,fun(<<"account">>, ?QUEUE, undefined, Limit) ->
                    ?assertEqual(100, Limit),
                    {ok, [], undefined}
                end),
    expect_context_setters(),
    Result = cb_queues:validate_callback_list(context, ?QUEUE),
    ?assertEqual(automatic, maps:get(etag, Result)),
    ?assertEqual([], maps:get(data, Result)),
    ?assertEqual(1, meck:num_calls(acdc_callback_store, list, '_'))
end).

cancel_sets_callback_etag_and_maps_terminal_conflict_test() -> with_http_mocks(fun() ->
    Doc = kz_json:from_list([{<<"_id">>, ?CALLBACK}, {<<"_rev">>, <<"7-revision">>}
                            ,{<<"queue_id">>, ?QUEUE}, {<<"status">>, <<"cancelled">>}]),
    meck:expect(cb_context, account_id, fun(_) -> <<"account">> end),
    meck:expect(acdc_callback_store, cancel, fun(_, _, _) -> {ok, Doc} end),
    meck:expect(crossbar_doc, rev_to_etag, fun(Arg) -> ?assertEqual(Doc, Arg), <<"7-revision">> end),
    meck:expect(kz_doc, id, fun(JObj) -> kz_json:get_value(<<"_id">>, JObj) end),
    meck:expect(kz_doc, created, fun(_) -> undefined end),
    meck:expect(kz_doc, modified, fun(_) -> undefined end),
    expect_context_setters(),
    Result = cb_queues:cancel_callback(#{}, ?QUEUE, ?CALLBACK),
    ?assertEqual(<<"7-revision">>, maps:get(etag, Result)),

    meck:expect(acdc_callback_store, cancel, fun(_, _, _) -> {error, already_finished} end),
    meck:expect(cb_context, add_system_error
               ,fun(409, <<"callback_already_finished">>, _Body, _) -> terminal_conflict end),
    ?assertEqual(terminal_conflict, cb_queues:cancel_callback(context, ?QUEUE, ?CALLBACK)),

    meck:expect(acdc_callback_store, cancel, fun(_, _, _) -> {error, conflict} end),
    meck:expect(crossbar_doc, handle_datamgr_errors
               ,fun(conflict, ?CALLBACK, context) -> revision_conflict end),
    ?assertEqual(revision_conflict, cb_queues:cancel_callback(context, ?QUEUE, ?CALLBACK))
end).

expect_context_setters() ->
    meck:expect(cb_context, setters, fun(Context, Setters) ->
        lists:foldl(fun({Setter, Value}, Acc) -> Setter(Acc, Value) end, Context, Setters)
    end),
    meck:expect(cb_context, set_doc, fun(Context, Value) -> maps:put(doc, Value, ensure_map(Context)) end),
    meck:expect(cb_context, set_resp_status, fun(Context, Value) -> maps:put(status, Value, ensure_map(Context)) end),
    meck:expect(cb_context, set_resp_data, fun(Context, Value) -> maps:put(data, Value, ensure_map(Context)) end),
    meck:expect(cb_context, set_resp_etag, fun(Context, Value) -> maps:put(etag, Value, ensure_map(Context)) end),
    meck:expect(cb_context, set_resp_envelope, fun(Context, Value) -> maps:put(envelope, Value, ensure_map(Context)) end).

ensure_map(Context) when is_map(Context) -> Context;
ensure_map(_) -> #{}.

with_http_mocks(Fun) ->
    meck:new([crossbar_doc, cb_context, acdc_callback_store, kz_doc], [non_strict, no_link]),
    try Fun()
    after meck:unload([crossbar_doc, cb_context, acdc_callback_store, kz_doc])
    end.
