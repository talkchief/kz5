%%% Real public crossbar_doc delete/1,2, cb_context and JSON/revision transforms.
%%% Only datastore and asynchronous side-effect admission are controlled.
%%% This is NOT Cowboy If-Match parsing, real CouchDB CAS/transport retry,
%%% resource-specific cascade/queue activation, or external hook execution proof.
-module(crossbar_soft_delete_revision_tests).
-include_lib("eunit/include/eunit.hrl").

-define(ACCOUNT, <<"11111111111111111111111111111111">>).
-define(DB, <<"account%2F11%2F11%2F1111111111111111111111111111">>).
-define(ID, <<"22222222222222222222222222222222">>).
-define(R1, <<"1-validated">>).
-define(R2, <<"2-concurrent">>).

revision_safety_test_() ->
    %% Meck recompilation is intentionally serial under a 50% CPU guard.
    %% Multi-case groups need more than EUnit's default five seconds.
    [{Name, {timeout, 30, Fun}} || {Name, Fun} <-
        [{"saved body and revision", fun saved_revision_soft_delete_preserves_validated_body/0},
         {"concurrent body preserved with/without header", fun concurrent_update_preserved_with_and_without_if_match/0},
         {"default delete never refreshes", fun public_default_soft_delete_never_refreshes_revision/0},
         {"missing/empty/invalid revision no writes", fun missing_empty_and_invalid_revisions_fail_before_any_write/0},
         {"hard delete retains revision", fun hard_delete_keeps_validated_revision_and_hard_marker/0},
         {"hard delete concurrent conflict", fun hard_delete_concurrent_revision_conflicts_without_refresh/0},
         {"datastore errors retain codes/no hooks", fun datastore_errors_keep_codes_and_do_not_schedule_success_hooks/0},
         {"not found retains prior semantics", fun not_found_retains_success_without_success_hooks/0},
         {"successful delete admits existing hooks", fun successful_nonaccount_delete_schedules_only_existing_hooks/0}]].

doc() ->
    kz_json:from_list([{<<"_id">>, ?ID}, {<<"_rev">>, ?R1},
                      {<<"pvt_type">>, <<"account">>},
                      {<<"pvt_account_id">>, ?ACCOUNT}, {<<"pvt_account_db">>, ?DB},
                      {<<"pvt_created">>, 100}, {<<"pvt_modified">>, 101},
                      {<<"pvt_fixture_marker">>, <<"private-original">>},
                      {<<"fixture_marker">>, <<"validated-body">>}]).

context(Doc) ->
    cb_context:setters(cb_context:new(),
        [{fun cb_context:set_doc/2, Doc},
         {fun cb_context:set_db_name/2, ?DB},
         {fun cb_context:set_account_id/2, ?ACCOUNT},
         {fun cb_context:set_api_version/2, <<"v2">>},
         {fun cb_context:set_req_id/2, <<"offline-revision-fixture">>},
         {fun cb_context:set_req_verb/2, <<"DELETE">>},
         {fun cb_context:set_resp_status/2, success}]).

with_store(Current, Body) ->
    T = ets:new(soft_delete_fixture, [public, set]),
    ets:insert(T, [{current, Current}, {attempts, []}, {hooks, []}]),
    Modules = [kz_datamgr, kz_process],
    try
        lists:foreach(fun(M) -> meck:new(M, [non_strict, no_link]) end, Modules),
        meck:expect(kz_datamgr, lookup_doc_rev,
            fun(_, _) -> error(unexpected_revision_refresh) end),
        meck:expect(kz_datamgr, ensure_saved,
            fun(_, _) -> error(unexpected_conflict_retry) end),
        meck:expect(kz_datamgr, save_doc,
            fun(Db, Written) -> record_write(T, save, Db, Written) end),
        meck:expect(kz_datamgr, del_doc,
            fun(Db, Written) -> record_write(T, delete, Db, Written) end),
        %% Capture admission, do not spawn workers or execute provisioner/services.
        meck:expect(kz_process, spawn, fun(Fun, Args) ->
            {module, Module} = erlang:fun_info(Fun, module),
            {name, Name} = erlang:fun_info(Fun, name),
            {arity, Arity} = erlang:fun_info(Fun, arity),
            ets:insert(T, {hooks, value(T, hooks) ++ [{Module, Name, Arity, length(Args)}]}),
            self()
        end),
        Body(T)
    after
        lists:foreach(fun(M) -> catch meck:unload(M) end, lists:reverse(Modules)),
        ets:delete(T)
    end.

value(T, Key) -> ets:lookup_element(T, Key, 2).

record_write(T, Kind, Db, Written) ->
    ?assertEqual(?DB, Db),
    ?assertEqual(?ID, kz_doc:id(Written)),
    ets:insert(T, {attempts, value(T, attempts) ++ [{Kind, Written}]}),
    case ets:lookup(T, result) of
        [{result, Result}] -> Result;
        [] ->
            case kz_doc:revision(Written) =:= kz_doc:revision(value(T, current)) of
                true ->
                    Saved = kz_doc:set_revision(Written, <<"3-fixture-saved">>),
                    ets:insert(T, {current, Saved}),
                    {ok, Saved};
                false -> {error, conflict}
            end
    end.

assert_conflict(Context) ->
    ?assertEqual(error, cb_context:resp_status(Context)),
    ?assertEqual(409, cb_context:resp_error_code(Context)),
    ?assertEqual(<<"datastore_conflict">>, cb_context:resp_error_msg(Context)).

assert_no_refresh() ->
    ?assertEqual(0, meck:num_calls(kz_datamgr, lookup_doc_rev, '_')),
    ?assertEqual(0, meck:num_calls(kz_datamgr, ensure_saved, '_')).

saved_revision_soft_delete_preserves_validated_body() ->
    Doc = doc(),
    with_store(Doc, fun(T) ->
        Result = crossbar_doc:delete(context(Doc), true),
        ?assertEqual(success, cb_context:resp_status(Result)),
        [{save, Written}] = value(T, attempts),
        ?assertEqual(?R1, kz_doc:revision(Written)),
        ?assert(kz_doc:is_soft_deleted(Written)),
        ?assertNot(kz_json:is_true(<<"_deleted">>, Written)),
        lists:foreach(fun(Key) ->
            ?assertEqual(kz_json:get_value(Key, Doc), kz_json:get_value(Key, Written))
        end, [<<"_id">>, <<"pvt_type">>, <<"pvt_account_id">>, <<"pvt_account_db">>,
              <<"pvt_created">>, <<"pvt_fixture_marker">>, <<"fixture_marker">>]),
        ?assert(is_integer(kz_json:get_value(<<"pvt_modified">>, Written))),
        ?assertEqual(<<"offline-revision-fixture">>, kz_json:get_value(<<"pvt_request_id">>, Written)),
        ?assertEqual(false, kz_json:get_value(<<"pvt_is_authenticated">>, Written)),
        ?assertEqual(Written, cb_context:doc(Result)),
        ?assertEqual(<<"validated-body">>, kz_json:get_value(<<"fixture_marker">>, cb_context:resp_data(Result))),
        ?assertEqual(undefined, kz_json:get_value(<<"pvt_fixture_marker">>, cb_context:resp_data(Result))),
        ?assert(kz_doc:is_soft_deleted(value(T, current))),
        ?assertEqual([], value(T, hooks)),
        ?assertNot(kz_doc:is_soft_deleted(Doc)),
        assert_no_refresh()
    end).

concurrent_update_preserved_with_and_without_if_match() ->
    %% Header construction does not simulate Cowboy precondition evaluation.
    %% It represents a validated r1 context reaching DELETE after matching, or
    %% an ordinary headerless DELETE, with r2 now present in the datastore.
    lists:foreach(fun(Header) ->
        Original = doc(),
        Current = kz_json:set_values([{<<"_rev">>, ?R2},
                                     {<<"fixture_marker">>, <<"concurrent-body">>},
                                     {<<"pvt_fixture_marker">>, <<"concurrent-private">>}], Original),
        with_store(Current, fun(T) ->
            %% Old source takes r2 here and wrongly writes the stale r1 body.
            meck:expect(kz_datamgr, lookup_doc_rev, fun(?DB, ?ID) -> {ok, ?R2} end),
            Context0 = context(Original),
            Context = case Header of
                          undefined -> Context0;
                          _ -> cb_context:set_req_header(Context0, <<"if-match">>, Header)
                      end,
            Result = crossbar_doc:delete(Context, true),
            assert_conflict(Result),
            [{save, Written}] = value(T, attempts),
            ?assertEqual(?R1, kz_doc:revision(Written)),
            ?assertEqual(<<"validated-body">>, kz_json:get_value(<<"fixture_marker">>, Written)),
            ?assertEqual(Current, value(T, current)),
            ?assertEqual(Original, cb_context:doc(Result)),
            ?assertEqual([], value(T, hooks)),
            assert_no_refresh()
        end)
    end, [undefined, <<"\"1-validated\"">>]).

public_default_soft_delete_never_refreshes_revision() ->
    Doc = doc(),
    with_store(Doc, fun(T) ->
        %% The default poison expectation makes a lookup fail this test even
        %% if production tries to catch the error and continue to a save.
        Result = crossbar_doc:delete(context(Doc)),
        ?assertEqual(success, cb_context:resp_status(Result)),
        ?assertEqual(1, length(value(T, attempts))),
        assert_no_refresh()
    end).

missing_empty_and_invalid_revisions_fail_before_any_write() ->
    lists:foreach(fun(Revision) ->
        Original = doc(),
        Doc = case Revision of
                  undefined -> kz_json:delete_key(<<"_rev">>, Original);
                  _ -> kz_json:set_value(<<"_rev">>, Revision, Original, #{keep_null => true})
              end,
        ?assertEqual(Revision, kz_doc:revision(Doc)),
        with_store(Original, fun(T) ->
            Result = crossbar_doc:delete(context(Doc), true),
            assert_conflict(Result),
            ?assertEqual([], value(T, attempts)),
            ?assertEqual([], value(T, hooks)),
            ?assertEqual(Original, value(T, current)),
            ?assertEqual(Doc, cb_context:doc(Result)),
            assert_no_refresh()
        end)
    end, [undefined, <<>>, 7, null, []]).

hard_delete_keeps_validated_revision_and_hard_marker() ->
    Doc = doc(),
    with_store(Doc, fun(T) ->
        Result = crossbar_doc:delete(context(Doc), false),
        ?assertEqual(success, cb_context:resp_status(Result)),
        [{delete, Written}] = value(T, attempts),
        ?assertEqual(?R1, kz_doc:revision(Written)),
        ?assert(kz_json:is_true(<<"_deleted">>, Written)),
        ?assertNot(kz_doc:is_soft_deleted(Written)),
        ?assertEqual(kz_json:set_value(<<"_deleted">>, true, Doc), Written),
        ?assertEqual([], value(T, hooks)),
        assert_no_refresh()
    end).

hard_delete_concurrent_revision_conflicts_without_refresh() ->
    Doc = doc(), Current = kz_doc:set_revision(Doc, ?R2),
    with_store(Current, fun(T) ->
        assert_conflict(crossbar_doc:delete(context(Doc), false)),
        [{delete, Written}] = value(T, attempts),
        ?assertEqual(?R1, kz_doc:revision(Written)),
        ?assertEqual(Current, value(T, current)),
        ?assertEqual([], value(T, hooks)),
        assert_no_refresh()
    end).

datastore_errors_keep_codes_and_do_not_schedule_success_hooks() ->
    %% User type reaches the hook decision on success; no name normalization
    %% seam is needed because this synthetic document has no name fields.
    Doc = kz_json:set_value(<<"pvt_type">>, <<"user">>, doc()),
    lists:foreach(fun({Reason, Code, Message}) ->
        with_store(Doc, fun(T) ->
            ets:insert(T, {result, {error, Reason}}),
            Result = crossbar_doc:delete(context(Doc), true),
            ?assertEqual(error, cb_context:resp_status(Result)),
            ?assertEqual(Code, cb_context:resp_error_code(Result)),
            ?assertEqual(Message, cb_context:resp_error_msg(Result)),
            ?assertEqual(1, length(value(T, attempts))),
            ?assertEqual(Doc, value(T, current)),
            ?assertEqual([], value(T, hooks)),
            assert_no_refresh()
        end)
    end, [{conflict, 409, <<"datastore_conflict">>},
          {db_not_reachable, 503, <<"datastore_unreachable">>},
          %% Generic failures use add_system_error/3 (500), unlike the
          %% dedicated unreachable branch using add_system_error/2 (503).
          {failed, 500, <<"datastore_fault">>}]).

not_found_retains_success_without_success_hooks() ->
    Doc = kz_json:set_value(<<"pvt_type">>, <<"user">>, doc()),
    with_store(Doc, fun(T) ->
        ets:insert(T, {result, {error, not_found}}),
        Result = crossbar_doc:delete(context(Doc), true),
        ?assertEqual(success, cb_context:resp_status(Result)),
        ?assertEqual(1, length(value(T, attempts))),
        ?assert(kz_doc:is_soft_deleted(cb_context:doc(Result))),
        ?assertEqual(Doc, value(T, current)),
        ?assertEqual([], value(T, hooks)),
        assert_no_refresh()
    end).

successful_nonaccount_delete_schedules_only_existing_hooks() ->
    Doc = kz_json:set_value(<<"pvt_type">>, <<"user">>, doc()),
    with_store(Doc, fun(T) ->
        Result = crossbar_doc:delete(context(Doc), true),
        ?assertEqual(success, cb_context:resp_status(Result)),
        ?assertEqual([{provisioner_util, maybe_send_contact_list, 4, 4},
                      {crossbar_services, update_subscriptions, 2, 2}], value(T, hooks)),
        ?assertEqual(1, length(value(T, attempts))),
        assert_no_refresh()
    end).
