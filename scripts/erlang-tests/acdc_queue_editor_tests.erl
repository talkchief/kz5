%%% SPDX-License-Identifier: MPL-2.0
%%% In-memory database and auth bindings only. No server/API/filesystem writes.
-module(acdc_queue_editor_tests).
-include_lib("eunit/include/eunit.hrl").
-include_lib("couchbeam/include/couchbeam.hrl").
-include("acdc_gemini_map.hrl").
-define(A, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(Q, <<"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb">>).
-define(U, <<"cccccccccccccccccccccccccccccccc">>).
-define(V, <<"dddddddddddddddddddddddddddddddd">>).
-define(R, <<"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee">>).
-define(REV, <<"1-11111111111111111111111111111111">>).
j(P) -> kz_json:from_list(P).
doc(Id, Type, Values) -> j([{<<"_id">>, Id}, {<<"_rev">>, ?REV},
                          {<<"pvt_type">>, Type}, {<<"pvt_account_id">>, ?A}|Values]).
user(Id, Queues) -> doc(Id, <<"user">>, [{<<"queues">>, Queues}, {<<"enabled">>, true},
                        {<<"first_name">>, <<"Fixture">>}, {<<"password">>, <<"MUST_NOT_LEAK">>}]).
queue() -> doc(?Q, <<"queue">>, [{<<"name">>, <<"Support">>}, {<<"future_field">>, j([{<<"keep">>, true}])}]).
route() -> doc(?R, <<"callflow">>, [{<<"numbers">>, [<<"2099">>]},
    {<<"flags">>, [<<"talkchief-acdc-managed">>, <<"talkchief-acdc-queue:", ?Q/binary>>]},
    {<<"patterns">>, []}, {<<"flow">>, j([{<<"module">>, <<"acdc_member">>},
        {<<"data">>, j([{<<"id">>, ?Q}])}, {<<"children">>, j([])}])}]).
context() -> cb_context:setters(cb_context:new(), [
    {fun cb_context:set_account_id/2, ?A}, {fun cb_context:set_auth_account_id/2, ?A},
    {fun cb_context:set_auth_doc/2, j([{<<"owner_id">>, ?U}])},
    {fun cb_context:set_auth_token_type/2, 'x-auth-token'},
    {fun cb_context:set_api_version/2, <<"v2">>}, {fun cb_context:set_req_verb/2, <<"PATCH">>},
    {fun cb_context:set_req_nouns/2, [{<<"queues">>, [?Q, <<"editor">>]}, {<<"accounts">>, [?A]}]},
    {fun cb_context:set_db_name/2, <<"account/editor-fixture">>}]).

hash_identity_test() ->
    ?assertEqual(cb_acdc_queue_editor:digest(j([{<<"b">>, 2}, {<<"a">>, j([{<<"z">>, 1}, {<<"x">>, 2}])}])),
                 cb_acdc_queue_editor:digest(j([{<<"a">>, j([{<<"x">>, 2}, {<<"z">>, 1}])}, {<<"b">>, 2}]))),
    ?assertNotEqual(cb_acdc_queue_editor:digest(<<"true">>), cb_acdc_queue_editor:digest(true)),
    ?assertNotEqual(cb_acdc_queue_editor:operation_id(?A, ?U, ?Q), cb_acdc_queue_editor:operation_id(?A, ?V, ?Q)),
    ?assertNotEqual(cb_acdc_queue_editor:operation_id(?A, ?U, ?Q), cb_acdc_queue_editor:operation_id(?V, ?U, ?Q)).

legacy_patch_preservation_test() ->
    Original = j([{<<"callback">>, j([{<<"media">>, j([{<<"offer">>, <<"custom">>}])},
                     {<<"announcement">>, j([{<<"initial_delay">>, 30}, {<<"interval">>, 60}])}])},
                 {<<"unknown">>, 123}, {<<"remove">>, true}]),
    Patch = j([{<<"callback">>, j([{<<"announcement">>, j([{<<"enabled">>, false}])}])}, {<<"remove">>, null}]),
    Merged = cb_acdc_queue_editor:merge_patch(Original, Patch),
    ?assertEqual(<<"custom">>, kz_json:get_value([<<"callback">>, <<"media">>, <<"offer">>], Merged)),
    ?assertEqual(60, kz_json:get_value([<<"callback">>, <<"announcement">>, <<"interval">>], Merged)),
    ?assertEqual(123, kz_json:get_value(<<"unknown">>, Merged)),
    ?assertEqual(undefined, kz_json:get_value(<<"remove">>, Merged)).

roster_plan_preserves_other_queues_test() ->
    [Removed, Added] = cb_acdc_queue_editor:roster_plan(?Q, [user(?U, [?Q, ?R]), user(?V, [?R])], [?V]),
    ?assertEqual([?R], kz_json:get_value(<<"queues">>, Removed)),
    ?assertEqual([?Q, ?R], kz_json:get_value(<<"queues">>, Added)),
    ?assertEqual(?REV, kz_doc:revision(Removed)),
    ?assertEqual([], cb_acdc_queue_editor:roster_plan(?Q, [user(?U, [?Q])], [?U])),
    ?assertThrow({editor_error,400,_,_}, cb_acdc_queue_editor:roster_plan(?Q, [user(?U, [])], [?V])),
    ?assertThrow({editor_error,400,_,_}, cb_acdc_queue_editor:roster_plan(?Q, [user(?U, [])], [?U, ?U])),
    Disabled = kz_json:set_value(<<"enabled">>, false, user(?U, [])),
    ?assertThrow({editor_error,400,_,_}, cb_acdc_queue_editor:roster_plan(?Q, [Disabled], [?U])),
    ?assertEqual([], cb_acdc_queue_editor:roster_plan(?Q, [kz_json:set_value(<<"queues">>, [?Q], Disabled)], [?U])).

managed_route_exact_identity_test() ->
    R = route(), ?assert(cb_acdc_queue_editor:strict_route(R, ?Q)),
    lists:foreach(fun(Bad) -> ?assertNot(cb_acdc_queue_editor:strict_route(Bad, ?Q)) end,
        [kz_json:set_value(<<"flags">>, [<<"talkchief-acdc-managed">>], R),
         kz_json:set_value(<<"numbers">>, [<<"2099">>, <<"2098">>], R),
         kz_json:set_value([<<"flow">>, <<"data">>, <<"id">>], ?U, R),
         kz_json:set_value([<<"flow">>, <<"data">>, <<"extra">>], true, R),
         kz_json:set_value([<<"flow">>, <<"children">>, <<"_">>], j([]), R),
         kz_json:set_value(<<"patterns">>, [<<".*">>], R)]).

catalog_projection_test() ->
    [User] = cb_acdc_queue_editor:public_catalog(<<"user">>, [user(?U, [?Q])]),
    ?assertEqual(undefined, kz_json:get_value(<<"password">>, User)),
    ?assertEqual(undefined, kz_json:get_value(<<"queues">>, User)),
    ?assertEqual(undefined, kz_json:get_value(<<"pvt_account_id">>, User)),
    ?assertEqual(?U, kz_json:get_value(<<"id">>, User)).

pipeline_test_() -> {foreach, fun setup/0, fun teardown/1,
    [fun(_T) -> fun authorization_gate/0 end,
     fun(_T) -> fun bounded_get/0 end,
     fun(_T) -> fun no_validation_side_effects/0 end,
     fun(_T) -> fun successful_single_request_and_replay/0 end,
     fun(_T) -> fun builtin_language_tombstones_remove_references_only/0 end,
     fun(_T) -> fun receipt_race/0 end,
     fun(_T) -> fun partial_bulk_and_safe_retry/0 end,
     fun(_T) -> fun lost_queue_reply/0 end,
     fun(_T) -> fun create_idempotency/0 end,
     fun(_T) -> fun route_update_and_delete/0 end,
     fun(_T) -> fun route_cas_conflict_after_queue_save/0 end,
     fun(_T) -> fun route_delete_cas_conflict/0 end,
     fun(_T) -> fun aggregate_extension_phantom_race/0 end,
     fun(_T) -> fun existing_queues_same_extension_race/0 end,
     fun(_T) -> fun extension_claim_lost_reply/0 end,
     fun(_T) -> fun extension_second_claim_failure/0 end,
     fun(_T) -> fun extension_finalization_lost_reply/0 end,
     fun(_T) -> fun extension_same_value_and_reuse/0 end,
     fun(_T) -> fun extension_recreate_after_soft_delete/0 end,
     fun(_T) -> fun foreign_routes_preserved/0 end,
     fun(_T) -> fun language_readiness_batch/0 end,
     fun(_T) -> fun legacy_language_readiness_batch/0 end]}.

%% One setup for this bounded failure matrix. Each case resets the in-memory
%% documents/counters; no production node or token participates.
bulk_outcomes_test_() -> {setup, fun setup/0, fun teardown/1, fun(_T) ->
    [{"bulk acknowledgement: malformed extra row", fun() -> bulk_ack_case(malformed_extra) end},
     {"bulk acknowledgement: foreign error row", fun() -> bulk_ack_case(foreign_extra) end},
     {"bulk acknowledgement: duplicate selected row", fun() -> bulk_ack_case(duplicate_ack) end},
     {"bulk acknowledgement: missing selected row", fun() -> bulk_ack_case(missing_ack) end},
     {"bulk acknowledgement: empty revision", fun() -> bulk_ack_case(empty_revision) end},
     {"lost bulk reply after actual roster commits", fun lost_bulk_reply_after_commit/0},
     {"bulk error before any roster commits", fun bulk_error_before_commit/0},
     {"partial roster commits then receipt persistence failure", fun partial_receipt_failure/0},
     {"all roster commits then receipt persistence failure", fun completed_roster_receipt_failure/0},
     {"partial receipt persisted but its reply was lost", fun partial_receipt_lost_reply/0}]
end}.

reset_documents(T) ->
    ets:delete_all_objects(T),
    ets:insert(T, [{kz_doc:id(D), D} || D <- [queue(), user(?U, [?Q, ?R]), user(?V, [?R]), route()]]),
    ets:insert(T, [{writes, []}, {bulk_mode, success}, {auth_mode, allow}, {limit_mode, false}, {save_mode, success}]).

setup() ->
    T = ets:new(editor_test, [named_table, public]),
    lists:foreach(fun(M) -> ok = meck:new(M, [no_link]) end,
                  [kz_datamgr, crossbar_bindings, kz_auth_scope, kapps_config, cb_queues, cb_callflows,
                   crossbar_doc, knm_converters, cb_modules_util]),
    reset_documents(T),
    meck:expect(crossbar_bindings, pmap, fun(Event, Payload) ->
        case {binary:match(Event, <<"allowed_scopes">>), binary:match(Event, <<"authorize.">>)} of
            {{_, _}, _} -> [[<<"editor-test-scope">>]];
            {_, {_, _}} ->
                [C|_] = Payload,
                case {lookup(auth_mode), cb_context:req_nouns(C)} of
                    {deny_users, [{<<"users">>, _}|_]} -> [{stop, C}];
                    {crash_users, [{<<"users">>, _}|_]} -> [{'EXIT', bad_auth}];
                    _ -> []
                end;
            _ -> [true]
        end
    end),
    meck:expect(kz_auth_scope, all, fun(_, _) -> lookup(auth_mode) =/= deny_scopes end),
    meck:expect(kapps_config, get_ne_binary, fun(_, _, _) -> <<"/not-present/editor-manifest.json">> end),
    meck:expect(kz_datamgr, open_doc, fun(_, Id) -> case ets:lookup(T, Id) of [{_, D}] -> {ok, D}; [] -> {error, not_found} end end),
    meck:expect(kz_datamgr, get_results, fun(_, View, Options) ->
        case View of
            <<"phone_numbers/crossbar_listing">> -> {ok, []};
            <<"crossbar_listings/by_type_id">> ->
                ?assertEqual(501, proplists:get_value(limit, Options)),
                %% couchbeam_view accepts the atom, NOT {include_docs, true}.
                %% The tuple silently drops documents in the production query.
                ?assert(lists:member(include_docs, Options)),
                ?assertNot(lists:member({include_docs, true}, Options)),
                Parsed = couchbeam_view:parse_view_options(Options),
                ?assertEqual("true", proplists:get_value(include_docs, Parsed#view_query_args.options)),
                [Type] = proplists:get_value(startkey, Options),
                Docs = [D || {Id, D} <- ets:tab2list(T), is_binary(Id), kz_json:is_json_object(D), kz_doc:type(D) =:= Type,
                             not kz_doc:is_soft_deleted(D)],
                case lookup(limit_mode) of true -> {ok, lists:duplicate(501, j([]))}; false -> {ok, [j([{<<"doc">>, D}]) || D <- Docs]} end
        end
    end),
    meck:expect(kz_datamgr, save_doc, fun(_, D) -> save(D) end),
    meck:expect(kz_datamgr, save_docs, fun bulk_save/2),
    meck:expect(cb_queues, validate, fun(C) -> validate_queue(C, undefined) end),
    meck:expect(cb_queues, validate, fun(C, Id) -> validate_queue(C, Id) end),
    meck:expect(cb_queues, put, fun save_context/1),
    meck:expect(cb_queues, post, fun(C, _) -> save_context(C) end),
    meck:expect(cb_callflows, validate, fun(C) -> validate_route(C, undefined) end),
    meck:expect(cb_callflows, validate, fun(C, Id) -> validate_route(C, Id) end),
    meck:expect(cb_callflows, put, fun save_context/1),
    meck:expect(cb_callflows, post, fun(C, _) -> save_context(C) end),
    meck:expect(crossbar_doc, save, fun save_context/1),
    meck:expect(knm_converters, is_reconcilable, fun(_, _) -> false end),
    meck:expect(cb_modules_util, apply_assignment_updates, fun([], _) -> [] end),
    meck:expect(cb_modules_util, log_assignment_updates, fun([]) -> ok end),
    meck:expect(cb_callflows, delete, fun(C, Id) ->
        Current = lookup(Id), ?assertEqual(kz_doc:revision(Current), kz_doc:revision(cb_context:doc(C))),
        ets:delete(editor_test, Id), ets:insert(editor_test, {writes, lookup(writes) ++ [Id]}),
        cb_context:set_resp_status(C, success)
    end),
    T.
teardown(T) -> lists:foreach(fun meck:unload/1, [kz_datamgr, crossbar_bindings, kz_auth_scope, kapps_config, cb_queues, cb_callflows,
                                               crossbar_doc, knm_converters, cb_modules_util]), ets:delete(T).
lookup(K) -> [{_, V}] = ets:lookup(editor_test, K), V.
bulk_save(_, Docs) ->
    case lookup(bulk_mode) of
        error_before_commit -> {error, timeout};
        Mode ->
            Results = lists:map(fun(D) ->
                case Mode =:= partial andalso kz_doc:id(D) =:= ?V of
                    true -> j([{<<"id">>, ?V}, {<<"error">>, <<"conflict">>}]);
                    false ->
                        {ok, Saved} = save(D),
                        j([{<<"id">>, kz_doc:id(Saved)}, {<<"rev">>, kz_doc:revision(Saved)}])
                end
            end, Docs),
            case Mode of
                lost_after_commit -> {error, timeout};
                malformed_extra -> {ok, Results ++ [j([{<<"unexpected">>, true}])]};
                foreign_extra -> {ok, Results ++ [j([{<<"id">>, ?R}, {<<"error">>, <<"conflict">>}])]};
                duplicate_ack -> {ok, Results ++ [hd(Results)]};
                missing_ack -> {ok, [R || R <- Results, kz_doc:id(R) =/= ?V]};
                empty_revision -> {ok, [case kz_doc:id(R) of ?V -> kz_json:set_value(<<"rev">>, <<>>, R); _ -> R end || R <- Results]};
                _ -> {ok, Results}
            end
    end.
save(D) ->
    Id = kz_doc:id(D), Existing = case ets:lookup(editor_test, Id) of [] -> undefined; [{_, X}] -> X end,
    case Existing =:= undefined orelse kz_doc:revision(Existing) =:= kz_doc:revision(D) of
        false -> {error, conflict};
        true ->
            Rev = integer_to_binary(1 + length(lookup(writes))), Saved = kz_doc:set_revision(D, <<Rev/binary, "-11111111111111111111111111111111">>),
            ets:insert(editor_test, [{Id, Saved}, {writes, lookup(writes) ++ [Id]}]),
            case lookup(save_mode) =:= lost_queue andalso kz_doc:type(D) =:= <<"queue">> of true -> {error, timeout}; false -> {ok, Saved} end
    end.
save_context(C) ->
    case save(cb_context:doc(C)) of
        {ok, D} -> cb_context:setters(C, [{fun cb_context:set_doc/2, D}, {fun cb_context:set_resp_status/2, success}]);
        _ -> cb_context:add_system_error(datastore_fault, C)
    end.
validate_queue(C, QueueId) ->
    Body = cb_context:req_data(C),
    Original = case QueueId of undefined -> j([{<<"pvt_type">>, <<"queue">>}, {<<"pvt_account_id">>, ?A}]); _ -> lookup(QueueId) end,
    cb_context:setters(C, [{fun cb_context:set_doc/2, cb_acdc_queue_editor:merge_patch(Original, Body)}, {fun cb_context:set_resp_status/2, success}]).
validate_route(C, RouteId) ->
    Original = case RouteId of undefined -> j([{<<"pvt_type">>, <<"callflow">>}, {<<"pvt_account_id">>, ?A}]); _ -> lookup(RouteId) end,
    cb_context:setters(C, [{fun cb_context:set_doc/2, cb_acdc_queue_editor:merge_patch(Original, cb_context:req_data(C))},
                          {fun cb_context:set_resp_status/2, success}]).
body(QueueId) ->
    Get = cb_acdc_queue_editor:get(context(), QueueId), ?assertEqual(success, cb_context:resp_status(Get)),
    j([{<<"queue">>, j([{<<"name">>, <<"Edited">>}])}, {<<"roster">>, [?V]}, {<<"route">>, null},
      {<<"request_id">>, <<"11111111111111111111111111111111">>},
      {<<"revisions">>, kz_json:get_json_value(<<"revisions">>, cb_context:resp_data(Get))}]).
prepared(Body, Id) -> cb_acdc_queue_editor:validate_write(cb_context:set_req_data(context(), Body), Id).

authorization_gate() ->
    Sub = cb_acdc_queue_editor:scoped(context(), <<"users">>, [], <<"GET">>),
    ?assertEqual(<<"/v2/accounts/", ?A/binary, "/users">>, cb_context:raw_path(Sub)),
    ?assert(cb_acdc_queue_editor:authorized(Sub)),
    ets:insert(editor_test, {auth_mode, deny_users}), ?assertNot(cb_acdc_queue_editor:authorized(Sub)),
    ets:insert(editor_test, {auth_mode, crash_users}), ?assertNot(cb_acdc_queue_editor:authorized(Sub)),
    ets:insert(editor_test, {auth_mode, deny_scopes}),
    WithMethod = cb_context:set_auth_doc(Sub, j([{<<"method">>, <<"cb_user_auth">>}])),
    ?assertNot(cb_acdc_queue_editor:authorized(WithMethod)).

bounded_get() ->
    Result = cb_context:resp_data(cb_acdc_queue_editor:get(context(), ?Q)),
    ?assertEqual([?U], kz_json:get_value(<<"roster">>, Result)),
    ?assertEqual(undefined, kz_json:get_value([<<"users">>, 1, <<"password">>], Result)),
    ?assertEqual([], lookup(writes)),
    ets:insert(editor_test, {limit_mode, true}),
    Limited = cb_context:resp_data(cb_acdc_queue_editor:get(context(), ?Q)),
    ?assertEqual([], kz_json:get_value(<<"users">>, Limited)),
    ?assertEqual(false, kz_json:get_value([<<"catalogs">>, <<"users">>, <<"complete">>], Limited)).

no_validation_side_effects() ->
    B = body(?Q), Good = prepared(B, ?Q), ?assertEqual(success, cb_context:resp_status(Good)),
    ?assertEqual([], lookup(writes)),
    Conflict = prepared(kz_json:set_value([<<"revisions">>, <<"queue">>], <<"stale">>, B), ?Q),
    ?assertEqual(409, cb_context:resp_error_code(Conflict)),
    Unknown = prepared(kz_json:set_value(<<"roster">>, [?R], B), ?Q),
    ?assertEqual(400, cb_context:resp_error_code(Unknown)),
    ForbiddenBody = prepared(kz_json:set_value([<<"queue">>, <<"_id">>], ?R, B), ?Q),
    ?assertEqual(400, cb_context:resp_error_code(ForbiddenBody)),
    ?assertEqual([], lookup(writes)).

builtin_language_tombstones_remove_references_only() ->
    MediaId = <<"customer-recording">>,
    Media = doc(MediaId, <<"media">>, [{<<"_attachments">>,j([{<<"voice.wav">>,j([{<<"length">>,16000}])}])}]),
    Original = kz_json:set_values([
        {[<<"announcements">>,<<"language">>],<<"en-us">>},
        {[<<"announcements">>,<<"media">>],j([{<<"you_are_at_position">>,MediaId}])},
        {[<<"callback">>,<<"media">>],j([{<<"offer">>,MediaId},{<<"returned_confirmation">>,MediaId}])},
        {[<<"callback">>,<<"return_confirmation_prompt">>],MediaId}],queue()),
    ets:insert(editor_test,[{?Q,Original},{MediaId,Media}]),
    Patch = j([{<<"announcements">>,j([{<<"language">>,<<"en-us">>},{<<"media">>,null}])},
              {<<"callback">>,j([{<<"media">>,null},{<<"return_confirmation_prompt">>,null}])}]),
    %% Check both the editor validation merge and Crossbar's actual PATCH
    %% merge primitive. Null is consumed, never persisted as prompt media.
    ?assertEqual(cb_acdc_queue_editor:digest(cb_acdc_queue_editor:merge_patch(Original,Patch)),
                 cb_acdc_queue_editor:digest(kz_json:merge(fun kz_json:merge_left/2,Patch,Original))),
    B = kz_json:set_value(<<"queue">>,Patch,body(?Q)),
    Result = cb_acdc_queue_editor:execute(prepared(B,?Q)),
    ?assertEqual(success,cb_context:resp_status(Result)),
    Stored = lookup(?Q),
    lists:foreach(fun(Key) -> ?assertEqual(undefined,kz_json:get_value(Key,Stored)) end,
        [[<<"announcements">>,<<"media">>],[<<"callback">>,<<"media">>],
         [<<"callback">>,<<"return_confirmation_prompt">>]]),
    ?assertEqual(<<"en-us">>,kz_json:get_value([<<"announcements">>,<<"language">>],Stored)),
    ?assertEqual(Media,lookup(MediaId)),
    ?assertNot(lists:member(MediaId,lookup(writes))).

successful_single_request_and_replay() ->
    B = body(?Q), Result = cb_acdc_queue_editor:execute(prepared(B, ?Q)),
    ?assertEqual(success, cb_context:resp_status(Result)),
    ?assertEqual(<<"complete">>, kz_json:get_value(<<"state">>, cb_context:resp_data(Result))),
    ?assertEqual([?R], kz_json:get_value(<<"queues">>, lookup(?U))),
    ?assertEqual([?Q, ?R], kz_json:get_value(<<"queues">>, lookup(?V))),
    ?assertEqual(j([{<<"keep">>, true}]), kz_json:get_value(<<"future_field">>, lookup(?Q))),
    Writes = lookup(writes), Replay = cb_acdc_queue_editor:execute(prepared(B, ?Q)),
    ?assertEqual(cb_context:resp_data(Result), cb_context:resp_data(Replay)), ?assertEqual(Writes, lookup(writes)),
    Changed = prepared(kz_json:set_value([<<"queue">>, <<"name">>], <<"Changed">>, B), ?Q),
    ?assertEqual(409, cb_context:resp_error_code(Changed)), ?assertEqual(Writes, lookup(writes)).

receipt_race() ->
    B = body(?Q), P1 = prepared(B, ?Q), P2 = prepared(B, ?Q),
    ?assertEqual(success, cb_context:resp_status(cb_acdc_queue_editor:execute(P1))),
    Writes = lookup(writes), Result = cb_acdc_queue_editor:execute(P2),
    ?assertEqual(409, cb_context:resp_error_code(Result)), ?assertEqual(Writes, lookup(writes)).

partial_bulk_and_safe_retry() ->
    B = body(?Q), ets:insert(editor_test, {bulk_mode, partial}), Result = cb_acdc_queue_editor:execute(prepared(B, ?Q)),
    ?assertEqual(409, cb_context:resp_error_code(Result)),
    Data = cb_context:resp_data(Result), ?assertEqual(<<"roster">>, kz_json:get_value(<<"phase">>, Data)),
    ?assertEqual(true, kz_json:get_value(<<"reload_required">>, Data)),
    ?assertEqual([?R], kz_json:get_value(<<"queues">>, lookup(?U))),
    ?assertEqual([?R], kz_json:get_value(<<"queues">>, lookup(?V))),
    Writes = lookup(writes), Retry = prepared(B, ?Q),
    ?assertEqual(409, cb_context:resp_error_code(Retry)), ?assertEqual(Writes, lookup(writes)).

reset_bulk_case() ->
    reset_documents(editor_test),
    meck:reset(kz_datamgr), meck:reset(cb_callflows),
    meck:expect(kz_datamgr, save_doc, fun(_, D) -> save(D) end).

%% These cases deliberately assert rejection against the production public
%% execute path. A malformed success acknowledgement must not reach the route
%% write, even when the fixture datastore already committed both user docs.
bulk_ack_case(Mode) ->
    reset_bulk_case(),
    B = kz_json:set_value(<<"route">>, j([{<<"extension">>, <<"2098">>}]), body(?Q)),
    P = prepared(B, ?Q), ?assertEqual(success, cb_context:resp_status(P)),
    ets:insert(editor_test, {bulk_mode, Mode}),
    Result = cb_acdc_queue_editor:execute(P),
    ?assertEqual(409, cb_context:resp_error_code(Result)),
    Data = cb_context:resp_data(Result),
    ?assertEqual(<<"roster">>, kz_json:get_value(<<"phase">>, Data)),
    ?assertEqual(false, kz_json:get_value(<<"atomic">>, Data)),
    ?assertEqual(true, kz_json:get_value(<<"reload_required">>, Data)),
    ?assertEqual([?U, ?V], lists:sort(kz_json:get_list_value(<<"in_flight">>, Data))),
    ?assertEqual([<<"roster">>, <<"route">>, <<"finalize_extensions">>], kz_json:get_value(<<"remaining">>, Data)),
    ?assertNot(lists:any(fun(E) -> lists:member(kz_json:get_value(<<"phase">>, E), [<<"roster">>, <<"route">>]) end,
                        kz_json:get_list_value(<<"committed">>, Data))),
    ?assertEqual(route(), lookup(?R)),
    ?assertEqual(2, length(extension_docs())),
    ?assert(lists:all(fun(D) -> kz_json:get_value(<<"state">>, D) =:= <<"reserved">> end, extension_docs())),
    assert_actual_roster_and_fresh_get([?V], [?U, ?V]),
    assert_retry_read_only(B).

lost_bulk_reply_after_commit() ->
    reset_bulk_case(), B = body(?Q), ets:insert(editor_test, {bulk_mode, lost_after_commit}),
    Result = cb_acdc_queue_editor:execute(prepared(B, ?Q)),
    assert_roster_receipt(Result, <<"running">>, []),
    assert_actual_roster_and_fresh_get([?V], [?U, ?V]), assert_retry_read_only(B).

bulk_error_before_commit() ->
    reset_bulk_case(), B = body(?Q), ets:insert(editor_test, {bulk_mode, error_before_commit}),
    Result = cb_acdc_queue_editor:execute(prepared(B, ?Q)),
    assert_roster_receipt(Result, <<"running">>, []),
    assert_actual_roster_and_fresh_get([?U], []), assert_retry_read_only(B).

partial_receipt_failure() ->
    reset_bulk_case(), B = body(?Q), ets:insert(editor_test, {bulk_mode, partial}),
    meck:expect(kz_datamgr, save_doc, fun(_, D) ->
        case {kz_doc:type(D), kz_json:get_value(<<"state">>, D)} of
            {<<"acdc_queue_editor_operation">>, <<"partial">>} -> {error, timeout};
            _ -> save(D)
        end
    end),
    Result = cb_acdc_queue_editor:execute(prepared(B, ?Q)),
    assert_roster_receipt(Result, <<"running">>, []),
    assert_actual_roster_and_fresh_get([], [?U]), assert_retry_read_only(B).

completed_roster_receipt_failure() ->
    reset_bulk_case(), B = body(?Q),
    meck:expect(kz_datamgr, save_doc, fun(_, D) ->
        case {kz_doc:type(D), kz_json:get_value(<<"phase">>, D), kz_json:get_value(<<"in_flight">>, D)} of
            {<<"acdc_queue_editor_operation">>, <<"roster">>, []} -> {error, timeout};
            _ -> save(D)
        end
    end),
    Result = cb_acdc_queue_editor:execute(prepared(B, ?Q)),
    assert_roster_receipt(Result, <<"running">>, []),
    assert_actual_roster_and_fresh_get([?V], [?U, ?V]), assert_retry_read_only(B).

partial_receipt_lost_reply() ->
    reset_bulk_case(), B = body(?Q), ets:insert(editor_test, {bulk_mode, partial}),
    meck:expect(kz_datamgr, save_doc, fun(_, D) ->
        Saved = save(D),
        case {kz_doc:type(D), kz_json:get_value(<<"state">>, D)} of
            {<<"acdc_queue_editor_operation">>, <<"partial">>} -> {error, timeout};
            _ -> Saved
        end
    end),
    Result = cb_acdc_queue_editor:execute(prepared(B, ?Q)),
    assert_roster_receipt(Result, <<"partial">>, [?U]),
    assert_actual_roster_and_fresh_get([], [?U]), assert_retry_read_only(B).

assert_roster_receipt(Result, State, PartialIds) ->
    ?assertEqual(409, cb_context:resp_error_code(Result)), Data = cb_context:resp_data(Result),
    ?assertEqual(<<"roster">>, kz_json:get_value(<<"phase">>, Data)),
    ?assertEqual(State, kz_json:get_value(<<"state">>, Data)),
    ?assertEqual(?Q, kz_json:get_value(<<"queue_id">>, Data)),
    ?assertEqual(false, kz_json:get_value(<<"atomic">>, Data)),
    ?assertEqual(true, kz_json:get_value(<<"reload_required">>, Data)),
    ?assertEqual([?U, ?V], lists:sort(kz_json:get_list_value(<<"in_flight">>, Data))),
    ?assertEqual([<<"roster">>, <<"route">>], kz_json:get_value(<<"remaining">>, Data)),
    QueueCommit = j([{<<"phase">>, <<"queue">>}, {<<"ids">>, [?Q]}]),
    Expected = case State of
        <<"partial">> -> [QueueCommit, j([{<<"phase">>, <<"roster_partial">>}, {<<"ids">>, PartialIds}])];
        <<"running">> -> [QueueCommit]
    end,
    ?assertEqual(Expected, kz_json:get_value(<<"committed">>, Data)),
    Receipt = lookup(kz_json:get_value(<<"operation_id">>, Data)),
    lists:foreach(fun(Key) -> ?assertEqual(kz_json:get_value(Key, Receipt), kz_json:get_value(Key, Data)) end,
        [<<"queue_id">>, <<"state">>, <<"phase">>, <<"committed">>, <<"in_flight">>, <<"remaining">>]),
    ?assertEqual(route(), lookup(?R)).

assert_actual_roster_and_fresh_get(ExpectedRoster, ChangedUsers) ->
    ?assertEqual(<<"Edited">>, kz_json:get_value(<<"name">>, lookup(?Q))),
    ?assertNotEqual(?REV, kz_doc:revision(lookup(?Q))),
    lists:foreach(fun(Id) ->
        ExpectedQueues = case lists:member(Id, ExpectedRoster) of true -> [?Q, ?R]; false -> [?R] end,
        ?assertEqual(ExpectedQueues, kz_json:get_value(<<"queues">>, lookup(Id))),
        ?assertEqual(lists:member(Id, ChangedUsers), kz_doc:revision(lookup(Id)) =/= ?REV)
    end, [?U, ?V]),
    Writes = lookup(writes),
    Fresh = cb_acdc_queue_editor:get(cb_context:set_req_verb(context(), <<"GET">>), ?Q),
    ?assertEqual(success, cb_context:resp_status(Fresh)), Data = cb_context:resp_data(Fresh),
    ?assertEqual(lists:sort(ExpectedRoster), lists:sort(kz_json:get_value(<<"roster">>, Data))),
    ?assertEqual(kz_doc:revision(lookup(?Q)), kz_json:get_value([<<"revisions">>, <<"queue">>], Data)),
    lists:foreach(fun(Id) ->
        ?assertEqual(kz_doc:revision(lookup(Id)), kz_json:get_value([<<"revisions">>, <<"users">>, Id], Data))
    end, [?U, ?V]),
    ?assertEqual(kz_doc:revision(lookup(?R)), kz_json:get_value([<<"revisions">>, <<"callflows">>, ?R], Data)),
    ?assertEqual(Writes, lookup(writes)),
    ?assertNot(meck:called(cb_callflows, put, '_')), ?assertNot(meck:called(cb_callflows, post, '_')).

assert_retry_read_only(B) ->
    Writes = lookup(writes), BulkCalls = meck:num_calls(kz_datamgr, save_docs, '_'),
    ?assertEqual(1, BulkCalls), Retry = prepared(B, ?Q),
    ?assertEqual(409, cb_context:resp_error_code(Retry)),
    ?assertEqual(Writes, lookup(writes)), ?assertEqual(BulkCalls, meck:num_calls(kz_datamgr, save_docs, '_')).

lost_queue_reply() ->
    B = body(?Q), ets:insert(editor_test, {save_mode, lost_queue}), Result = cb_acdc_queue_editor:execute(prepared(B, ?Q)),
    ?assertEqual(409, cb_context:resp_error_code(Result)),
    ?assertEqual([?Q], kz_json:get_value(<<"in_flight">>, cb_context:resp_data(Result))),
    ?assertEqual([?Q, ?R], kz_json:get_value(<<"queues">>, lookup(?U))),
    ?assertEqual(<<"Edited">>, kz_json:get_value(<<"name">>, lookup(?Q))).

create_idempotency() ->
    B = body(undefined), C = cb_context:set_req_verb(cb_context:set_req_data(context(), B), <<"PUT">>),
    P = cb_acdc_queue_editor:validate_write(C, undefined), ?assertEqual([], lookup(writes)),
    Result = cb_acdc_queue_editor:execute(P), ?assertEqual(success, cb_context:resp_status(Result)),
    Qid = kz_json:get_value(<<"queue_id">>, cb_context:resp_data(Result)), ?assertNotEqual(?Q, Qid),
    Writes = lookup(writes), Again = cb_acdc_queue_editor:execute(cb_acdc_queue_editor:validate_write(C, undefined)),
    ?assertEqual(Qid, kz_json:get_value(<<"queue_id">>, cb_context:resp_data(Again))), ?assertEqual(Writes, lookup(writes)).

route_update_and_delete() ->
    B = kz_json:set_value(<<"route">>, j([{<<"extension">>, <<"2098">>}]), body(?Q)),
    P = prepared(B, ?Q), ?assertEqual([], lookup(writes)),
    ?assertEqual(success, cb_context:resp_status(cb_acdc_queue_editor:execute(P))),
    ?assertEqual([<<"2098">>], kz_json:get_value(<<"numbers">>, lookup(?R))),
    Delete = kz_json:set_values([{<<"route">>, j([{<<"extension">>, <<>>}])},
        {<<"request_id">>, <<"22222222222222222222222222222222">>}], body(?Q)),
    ?assertEqual(success, cb_context:resp_status(cb_acdc_queue_editor:execute(prepared(Delete, ?Q)))),
    ?assert(kz_doc:is_soft_deleted(lookup(?R))),
    ?assertEqual([<<"2098">>], kz_json:get_value(<<"numbers">>, lookup(?R))).

route_cas_conflict_after_queue_save() ->
    B = kz_json:set_value(<<"route">>, j([{<<"extension">>, <<"2098">>}]), body(?Q)),
    P = prepared(B, ?Q),
    Changed = kz_doc:set_revision(kz_json:set_value(<<"name">>, <<"Changed concurrently">>, lookup(?R)), <<"9-11111111111111111111111111111111">>),
    ets:insert(editor_test, {?R, Changed}),
    Result = cb_acdc_queue_editor:execute(P), ?assertEqual(409, cb_context:resp_error_code(Result)),
    ?assertEqual(<<"route">>, kz_json:get_value(<<"phase">>, cb_context:resp_data(Result))),
    ?assertEqual(Changed, lookup(?R)), ?assertEqual(<<"Edited">>, kz_json:get_value(<<"name">>, lookup(?Q))),
    ?assert(lists:all(fun(D) -> kz_json:get_value(<<"state">>, D) =:= <<"reserved">> end, extension_docs())),
    Retry = kz_json:set_values([{<<"request_id">>, ?V}, {<<"route">>, j([{<<"extension">>, <<"2098">>}])}], body(?Q)),
    ?assertEqual(409, cb_context:resp_error_code(prepared(Retry, ?Q))).

route_delete_cas_conflict() ->
    Delete = kz_json:set_values([{<<"route">>, j([{<<"extension">>, <<>>}])},
         {<<"request_id">>, <<"22222222222222222222222222222222">>}], body(?Q)),
    DeletePlan = prepared(Delete, ?Q),
    ChangedAgain = kz_doc:set_revision(route(), <<"10-11111111111111111111111111111111">>),
    ets:insert(editor_test, {?R, ChangedAgain}),
    DeleteResult = cb_acdc_queue_editor:execute(DeletePlan),
    ?assertEqual(409, cb_context:resp_error_code(DeleteResult)),
    ?assertEqual(ChangedAgain, lookup(?R)), ?assertNot(kz_doc:is_soft_deleted(lookup(?R))).

extension_docs() -> [D || {Id, D} <- ets:tab2list(editor_test), is_binary(Id), kz_json:is_json_object(D),
                        kz_doc:type(D) =:= <<"acdc_queue_extension">>].
extension_doc(Extension) -> [D] = [D || D <- extension_docs(), kz_json:get_value(<<"extension">>, D) =:= Extension], D.
new_route_plan(Extension, RequestId) ->
    B = kz_json:set_values([{<<"route">>, j([{<<"extension">>, Extension}])},
        {<<"roster">>, null}, {<<"request_id">>, RequestId}], body(undefined), #{keep_null => true}),
    C = cb_context:set_req_verb(cb_context:set_req_data(context(), B), <<"PUT">>),
    Plan = cb_acdc_queue_editor:validate_write(C, undefined),
    ?assertEqual({undefined, undefined}, {cb_context:resp_error_code(Plan), cb_context:resp_error_msg(Plan)}),
    ?assertEqual(success, cb_context:resp_status(Plan)), Plan.

aggregate_extension_phantom_race() ->
    P1 = new_route_plan(<<"2098">>, ?U), P2 = new_route_plan(<<"2098">>, ?V),
    ?assertEqual([], lookup(writes)),
    First = cb_acdc_queue_editor:execute(P1), ?assertEqual(success, cb_context:resp_status(First)),
    Winning = extension_doc(<<"2098">>),
    Second = cb_acdc_queue_editor:execute(P2), ?assertEqual(409, cb_context:resp_error_code(Second)),
    ?assertEqual(<<"reserve_extensions">>, kz_json:get_value(<<"phase">>, cb_context:resp_data(Second))),
    ?assertEqual([], kz_json:get_value(<<"committed">>, cb_context:resp_data(Second))),
    ?assertEqual(Winning, extension_doc(<<"2098">>)),
    ?assertEqual(<<"assigned">>, kz_json:get_value(<<"state">>, Winning)),
    RouteId = kz_json:get_value(<<"route_id">>, Winning),
    ?assertEqual(kz_doc:revision(lookup(RouteId)), kz_json:get_value(<<"route_revision">>, Winning)),
    LoserId = kz_json:get_value(<<"queue_id">>, cb_context:resp_data(Second)),
    ?assertEqual([], ets:lookup(editor_test, LoserId)),
    Matches = [D || {Id,D} <- ets:tab2list(editor_test), is_binary(Id), kz_json:is_json_object(D),
                    kz_doc:type(D) =:= <<"callflow">>, kz_json:get_value(<<"numbers">>, D) =:= [<<"2098">>]],
    ?assertEqual(1, length(Matches)).

existing_queues_same_extension_race() ->
    OtherId = <<"ffffffffffffffffffffffffffffffff">>, OtherQueue = kz_doc:set_id(queue(), OtherId),
    OtherRouteId = <<"99999999999999999999999999999999">>,
    OtherRoute = kz_json:set_values([{<<"_id">>, OtherRouteId}, {<<"numbers">>, [<<"2097">>]},
        {<<"flags">>, [<<"talkchief-acdc-managed">>, <<"talkchief-acdc-queue:", OtherId/binary>>]},
        {[<<"flow">>, <<"data">>, <<"id">>], OtherId}], route()),
    ets:insert(editor_test, [{OtherId, OtherQueue}, {OtherRouteId, OtherRoute}]),
    B1 = kz_json:set_values([{<<"roster">>, null}, {<<"route">>, j([{<<"extension">>, <<"2098">>}])}], body(?Q), #{keep_null => true}),
    B2 = kz_json:set_values([{<<"roster">>, null}, {<<"route">>, j([{<<"extension">>, <<"2098">>}])}, {<<"request_id">>, ?V}], body(OtherId), #{keep_null => true}),
    P1 = prepared(B1, ?Q), P2 = prepared(B2, OtherId),
    ?assertEqual({success, success}, {cb_context:resp_status(P1), cb_context:resp_status(P2)}),
    ?assertEqual(success, cb_context:resp_status(cb_acdc_queue_editor:execute(P1))),
    Result = cb_acdc_queue_editor:execute(P2), ?assertEqual(409, cb_context:resp_error_code(Result)),
    ?assertEqual(OtherQueue, lookup(OtherId)), ?assertEqual(OtherRoute, lookup(OtherRouteId)),
    ?assertEqual(<<"assigned">>, kz_json:get_value(<<"state">>, extension_doc(<<"2098">>))),
    ?assertEqual(<<"reserved">>, kz_json:get_value(<<"state">>, extension_doc(<<"2097">>))).

extension_claim_lost_reply() ->
    P = new_route_plan(<<"2098">>, ?U),
    meck:expect(kz_datamgr, save_doc, fun(_, D) ->
        Saved = save(D), case kz_doc:type(D) =:= <<"acdc_queue_extension">> of true -> {error, timeout}; false -> Saved end end),
    Result = cb_acdc_queue_editor:execute(P), Data = cb_context:resp_data(Result),
    ?assertEqual(409, cb_context:resp_error_code(Result)),
    ?assertEqual(<<"reserve_extensions">>, kz_json:get_value(<<"phase">>, Data)),
    ?assertEqual([], kz_json:get_value(<<"extension_claims">>, Data)),
    ?assertEqual([kz_doc:id(extension_doc(<<"2098">>))], kz_json:get_value(<<"in_flight">>, Data)),
    ?assertEqual([], ets:lookup(editor_test, kz_json:get_value(<<"queue_id">>, Data))),
    ?assertEqual(<<"reserved">>, kz_json:get_value(<<"state">>, extension_doc(<<"2098">>))),
    ?assertEqual(kz_json:get_value(<<"operation_id">>, Data), kz_json:get_value(<<"operation_id">>, extension_doc(<<"2098">>))).

extension_second_claim_failure() ->
    Original = lookup(?Q),
    B = kz_json:set_value(<<"route">>, j([{<<"extension">>, <<"2098">>}]), body(?Q)), P = prepared(B, ?Q),
    meck:expect(kz_datamgr, save_doc, fun(_, D) ->
        case {kz_doc:type(D), kz_json:get_value(<<"extension">>, D)} of
            {<<"acdc_queue_extension">>, <<"2099">>} -> {error, timeout}; _ -> save(D) end end),
    Result = cb_acdc_queue_editor:execute(P), Data = cb_context:resp_data(Result),
    ?assertEqual(409, cb_context:resp_error_code(Result)), ?assertEqual(Original, lookup(?Q)),
    ?assertEqual(route(), lookup(?R)), ?assertEqual(1, length(kz_json:get_value(<<"extension_claims">>, Data))),
    ?assertEqual(2, length(kz_json:get_value(<<"in_flight">>, Data))),
    ?assertEqual(<<"reserved">>, kz_json:get_value(<<"state">>, extension_doc(<<"2098">>))).

extension_finalization_lost_reply() ->
    P = new_route_plan(<<"2098">>, ?U),
    meck:expect(kz_datamgr, save_doc, fun(_, D) ->
        Saved = save(D), case {kz_doc:type(D), kz_json:get_value(<<"state">>, D)} of
            {<<"acdc_queue_extension">>, <<"assigned">>} -> {error, timeout}; _ -> Saved end end),
    Result = cb_acdc_queue_editor:execute(P), Data = cb_context:resp_data(Result),
    ?assertEqual(409, cb_context:resp_error_code(Result)),
    ?assertEqual(<<"finalize_extensions">>, kz_json:get_value(<<"phase">>, Data)),
    ?assertEqual([<<"finalize_extensions">>], kz_json:get_value(<<"remaining">>, Data)),
    Assigned = extension_doc(<<"2098">>), ?assertEqual(<<"assigned">>, kz_json:get_value(<<"state">>, Assigned)),
    ?assertEqual(kz_doc:revision(lookup(kz_json:get_value(<<"route_id">>, Assigned))), kz_json:get_value(<<"route_revision">>, Assigned)).

extension_same_value_and_reuse() ->
    B = kz_json:set_value(<<"route">>, j([{<<"extension">>, <<"2099">>}]), body(?Q)),
    ?assertEqual(success, cb_context:resp_status(cb_acdc_queue_editor:execute(prepared(B, ?Q)))),
    ?assertEqual(1, length(extension_docs())),
    B2 = kz_json:set_values([{<<"route">>, j([{<<"extension">>, <<"2099">>}])}, {<<"request_id">>, ?V}], body(?Q)),
    ?assertEqual(success, cb_context:resp_status(cb_acdc_queue_editor:execute(prepared(B2, ?Q)))),
    ?assertEqual(1, length(extension_docs())),
    Delete = kz_json:set_values([{<<"route">>, j([{<<"extension">>, <<>>}])}, {<<"request_id">>, ?R}], body(?Q)),
    ?assertEqual(success, cb_context:resp_status(cb_acdc_queue_editor:execute(prepared(Delete, ?Q)))),
    ?assertEqual(<<"released">>, kz_json:get_value(<<"state">>, extension_doc(<<"2099">>))),
    Result = cb_acdc_queue_editor:execute(new_route_plan(<<"2099">>, ?U)), ?assertEqual(success, cb_context:resp_status(Result)),
    ?assertEqual(kz_json:get_value(<<"queue_id">>, cb_context:resp_data(Result)), kz_json:get_value(<<"queue_id">>, extension_doc(<<"2099">>))).

extension_recreate_after_soft_delete() ->
    Delete = kz_json:set_value(<<"route">>, j([{<<"extension">>, <<>>}]), body(?Q)),
    ?assertEqual(success, cb_context:resp_status(cb_acdc_queue_editor:execute(prepared(Delete, ?Q)))),
    Tombstone = lookup(?R), ?assert(kz_doc:is_soft_deleted(Tombstone)),
    Recreate = kz_json:set_values([{<<"route">>, j([{<<"extension">>, <<"2099">>}])}, {<<"request_id">>, ?V}], body(?Q)),
    ?assertEqual(success, cb_context:resp_status(cb_acdc_queue_editor:execute(prepared(Recreate, ?Q)))),
    ?assertEqual(Tombstone, lookup(?R)),
    Assigned = extension_doc(<<"2099">>), ?assertEqual(?Q, kz_json:get_value(<<"queue_id">>, Assigned)),
    ?assertNotEqual(?R, kz_json:get_value(<<"route_id">>, Assigned)).

foreign_routes_preserved() ->
    Foreign = kz_json:set_value(<<"flags">>, [<<"operator-owned">>], route()), ets:insert(editor_test, {?R, Foreign}),
    B = kz_json:set_value(<<"route">>, j([{<<"extension">>, <<>>}]), body(?Q)),
    ?assertEqual(success, cb_context:resp_status(cb_acdc_queue_editor:execute(prepared(B, ?Q)))),
    ?assertEqual(Foreign, lookup(?R)),
    Collision = kz_json:set_values([{<<"route">>, j([{<<"extension">>, <<"2099">>}])},
         {<<"request_id">>, <<"22222222222222222222222222222222">>}], body(?Q)),
    Writes = lookup(writes), Failed = prepared(Collision, ?Q),
    ?assertEqual(409, cb_context:resp_error_code(Failed)), ?assertEqual(Writes, lookup(writes)).

manifest() ->
    Langs = [<<"en-us">>, <<"ar-sa">>, <<"he-il">>, <<"es-es">>, <<"fr-fr">>],
    Entries = [{L, j([{<<"ready">>, L =:= <<"en-us">>}, {<<"position">>, L =:= <<"en-us">>},
        {<<"wait_time">>, L =:= <<"en-us">>}, {<<"callback">>, L =:= <<"en-us">>},
        {<<"native_speaker_review">>, false}, {<<"numbers">>, <<"native_say">>},
        {<<"number_range">>, [0, 999999999]}, {<<"numeric_prompt_count">>, 0},
        {<<"required_prompt_ids">>, cb_acdc_queue_editor:required_prompts()},
        {<<"source_catalog_sha256">>, binary:copy(<<"a">>, 64)},
        {<<"installed_media_sha256">>, binary:copy(<<"b">>, 64)}, {<<"private_extra">>, <<"MUST_NOT_LEAK">>}])} || L <- Langs],
    j([{<<"schema_version">>, 1}, {<<"generated_at">>, <<"2026-09-05T19:00:00Z">>},
       {<<"private_extra">>, <<"MUST_NOT_LEAK">>}, {<<"languages">>, j(Entries)}]).

language_readiness_batch() ->
    M = manifest(), ?assert(cb_acdc_queue_editor:valid_manifest(M)),
    ?assertNot(cb_acdc_queue_editor:valid_manifest(kz_json:set_value(<<"generated_at">>, <<"invalid">>, M))),
    ?assertNot(cb_acdc_queue_editor:valid_manifest(kz_json:set_value([<<"languages">>, <<"en-us">>, <<"installed_media_sha256">>], <<"invalid">>, M))),
    meck:expect(kz_datamgr, open_docs, fun(<<"system_media">>, Ids) ->
        ?assertEqual(145, length(Ids)),
        ?assertNot(lists:any(fun(Id) -> binary:match(Id, <<"acdc-number-">>) =/= nomatch end, Ids)),
        {ok, [case Id of <<"en-us/", _/binary>> ->
                D = doc(Id, <<"media">>, [{<<"_attachments">>, j([{<<"prompt.wav">>, j([{<<"length">>, 16000}])}])}]),
                j([{<<"id">>, Id}, {<<"key">>, Id}, {<<"doc">>, D}]);
            _ -> j([{<<"key">>, Id}, {<<"error">>, <<"not_found">>}]) end || Id <- Ids]}
    end),
    {Verified, Media} = cb_acdc_queue_editor:verified_manifest_media(M),
    ?assertEqual(29, length(Media)), ?assertEqual(1, meck:num_calls(kz_datamgr, open_docs, '_')),
    ReadyCatalog = j([{<<"language_capabilities">>, Verified}, {<<"system_media">>, Media},
                     {<<"catalogs">>, j([{<<"system_media">>, j([{<<"complete">>, true}])}])}]),
    ?assert(cb_acdc_queue_editor:language_selection_ready(<<"en-us">>, ReadyCatalog)),
    ?assertNot(cb_acdc_queue_editor:language_selection_ready(<<"he-il">>, ReadyCatalog)),
    ?assertNot(cb_acdc_queue_editor:language_selection_ready(<<"unknown">>, ReadyCatalog)),
    ?assertEqual(true, kz_json:get_value([<<"languages">>, <<"en-us">>, <<"ready">>], Verified)),
    ?assertEqual(false, kz_json:get_value([<<"languages">>, <<"he-il">>, <<"ready">>], Verified)),
    ?assertEqual(undefined, kz_json:get_value(<<"private_extra">>, Verified)),
    ?assertEqual(undefined, kz_json:get_value([<<"languages">>, <<"en-us">>, <<"private_extra">>], Verified)),
    meck:expect(kz_datamgr, open_docs, fun(_, Ids) -> {ok, [j([{<<"key">>, Id}, {<<"error">>, <<"not_found">>}]) || Id <- Ids]} end),
    {Missing, []} = cb_acdc_queue_editor:verified_manifest_media(M),
    ?assertEqual(false, kz_json:get_value([<<"languages">>, <<"en-us">>, <<"ready">>], Missing)),
    ?assertEqual(false, kz_json:get_value([<<"languages">>, <<"en-us">>, <<"callback">>], Missing)),
    meck:expect(kz_datamgr, open_docs, fun(_, _) -> {ok, []} end),
    ?assertError({badmatch,false}, cb_acdc_queue_editor:verified_manifest_media(M)).

legacy_language_readiness_batch() ->
    Flags = [<<"ready">>, <<"position">>, <<"wait_time">>, <<"callback">>, <<"native_speaker_review">>],
    M = j([{<<"schema_version">>, 1}, {<<"backend_mode">>, <<"legacy">>},
           {<<"generated_at">>, <<"2026-09-05T19:00:00Z">>},
           {<<"languages">>, j([{L, j([{F, false} || F <- Flags])} ||
               L <- [<<"en-us">>, <<"ar-sa">>, <<"he-il">>, <<"es-es">>, <<"fr-fr">>]])}]),
    ?assert(cb_acdc_queue_editor:valid_manifest(M)),
    lists:foreach(fun(Bad) -> ?assertNot(cb_acdc_queue_editor:valid_manifest(Bad)) end,
        [kz_json:set_value([<<"languages">>, <<"en-us">>, <<"ready">>], true, M),
         kz_json:set_value([<<"languages">>, <<"ar-sa">>, <<"callback">>], true, M),
         kz_json:set_value([<<"languages">>, <<"he-il">>, <<"extra">>], true, M),
         kz_json:set_value(<<"private_extra">>, <<"must_not_leak">>, M),
         kz_json:set_value(<<"backend_mode">>, <<"unknown">>, M)]),
    meck:expect(kz_datamgr, open_docs, fun(<<"system_media">>, Ids) ->
        ?assertEqual(57, length(Ids)),
        ?assert(lists:member(<<"en-us/queue-about_5_minutes">>, Ids)),
        ?assertNot(lists:member(<<"en-us/acdc-queue-your-current-position-is">>, Ids)),
        ?assertNot(lists:member(<<"en-us/acdc-callback-success">>, Ids)),
        ?assert(lists:member(<<"en-us/agent-invalid_choice">>, Ids)),
        ?assertEqual(32, length(acdc_gemini_prompts:fixed_media_ids(<<"en-us">>))),
        ?assertEqual(42, length(acdc_gemini_prompts:callback_media_ids(<<"en-us">>))),
        ?assertEqual(10,length([Id || Id <- Ids, binary:match(Id,<<"/acdc-number-">>) =/= nomatch])),
        ?assert(lists:all(fun(<<"en-us/", _/binary>>) -> true; (_) -> false end, Ids)),
        {ok, [j([{<<"key">>, Id}, {<<"doc">>, english_media_doc(Id)}]) || Id <- Ids]}
    end),
    {Verified, Media} = cb_acdc_queue_editor:verified_manifest_media(M),
    ?assertEqual(M, Verified), ?assertEqual(57, length(Media)),
    ?assertEqual(1, meck:num_calls(kz_datamgr, open_docs, '_')),
    Catalog = j([{<<"language_capabilities">>, Verified}, {<<"system_media">>, Media},
                 {<<"catalogs">>, j([{<<"system_media">>, j([{<<"complete">>, true}])}])}]),
    ?assert(cb_acdc_queue_editor:language_selection_ready(<<"en-us">>, Catalog)),
    lists:foreach(fun(Language) ->
        ?assertNot(cb_acdc_queue_editor:language_selection_ready(Language, Catalog))
    end, [<<"ar-sa">>, <<"he-il">>, <<"fr-fr">>, <<"es-es">>, <<"unknown">>, undefined]),
    lists:foreach(fun(Bad) ->
        ?assertNot(cb_acdc_queue_editor:language_selection_ready(<<"en-us">>, Bad))
    end, [kz_json:set_value([<<"catalogs">>, <<"system_media">>, <<"complete">>], false, Catalog),
          kz_json:delete_key(<<"catalogs">>, Catalog),
          kz_json:delete_key(<<"language_capabilities">>, Catalog),
          kz_json:set_value(<<"system_media">>, tl(Media), Catalog),
          kz_json:set_value(<<"system_media">>, [kz_json:delete_key(<<"has_attachments">>, X) || X <- Media], Catalog),
          kz_json:set_value(<<"system_media">>, [kz_json:set_value(<<"language">>, <<"he-il">>, X) || X <- Media], Catalog),
          kz_json:set_value([<<"language_capabilities">>, <<"languages">>, <<"en-us">>, <<"ready">>], true, Catalog)]),
    ?assertEqual(false, kz_json:get_value([<<"language_capabilities">>, <<"languages">>, <<"en-us">>, <<"ready">>], Catalog)),
    ?assert(kz_json:is_true(<<"complete">>, cb_acdc_queue_editor:system_media_state(M, Media))),
    %% Every fresh-install prerequisite is necessary, including all 32 fixed
    %% recordings and each of the ten telephone digits. No native SAY fallback.
    DigitMedia = [D || D <- Media, binary:match(kz_json:get_value(<<"id">>,D),<<"/acdc-number-">>) =/= nomatch],
    ?assertEqual(10,length(DigitMedia)),
    lists:foreach(fun(Entry) ->
        Id = kz_json:get_value(<<"id">>, Entry),
        Partial = lists:delete(Entry, Media),
        ?assertEqual(56,length(Partial)),
        ?assertNot(cb_acdc_queue_editor:language_selection_ready(<<"en-us">>,
            kz_json:set_value(<<"system_media">>, Partial, Catalog))),
        State = cb_acdc_queue_editor:system_media_state(M, Partial),
        ?assertEqual(false, kz_json:get_value(<<"complete">>, State)),
        ?assertEqual(<<"english_media_prerequisites_incomplete">>, kz_json:get_value(<<"reason">>, State)),
        ?assertEqual([Id], kz_json:get_value(<<"missing_prompt_ids">>, State))
    end, Media),
    [Gemini|_] = [D || D <- Media, kz_json:is_true(<<"import_metadata_verified">>, D)],
    lists:foreach(fun({Key, Value}) ->
        Tampered = [kz_json:set_value(Key, Value, Gemini)|lists:delete(Gemini, Media)],
        ?assertNot(cb_acdc_queue_editor:language_selection_ready(<<"en-us">>,
            kz_json:set_value(<<"system_media">>, Tampered, Catalog)))
    end, [{<<"source_type">>, <<"customer">>}, {<<"sha256">>, binary:copy(<<"0">>,64)},
          {<<"source_map_sha256">>, binary:copy(<<"0">>,64)}, {<<"import_metadata_verified">>, false},
          {<<"canonical_prompt_id">>, <<"acdc-callback-offer-unknown">>}]),
    [GeminiId|_] = acdc_gemini_prompts:fixed_media_ids(<<"en-us">>),
    ValidDoc = english_media_doc(GeminiId),
    lists:foreach(fun(BadDoc) ->
        meck:expect(kz_datamgr, open_docs, fun(_, Ids) ->
            {ok, [j([{<<"key">>, Id}, {<<"doc">>, case Id of GeminiId -> BadDoc; _ -> english_media_doc(Id) end}]) || Id <- Ids]}
        end),
        {M, Partial} = cb_acdc_queue_editor:verified_manifest_media(M),
        ?assertEqual(56, length(Partial)),
        ?assertNot(cb_acdc_queue_editor:language_selection_ready(<<"en-us">>,
            kz_json:set_value(<<"system_media">>, Partial, Catalog)))
    end, [kz_json:set_value(<<"source_type">>, <<"customer">>, ValidDoc),
          kz_json:set_value([<<"source_voice">>, <<"sha256">>], binary:copy(<<"0">>,64), ValidDoc),
          kz_json:set_value(<<"pvt_deleted">>, true, ValidDoc),
          kz_json:set_value(<<"_attachments">>, j([]), ValidDoc),
          kz_json:set_value(<<"pvt_account_db">>, <<"other_account">>, ValidDoc)]),
    meck:expect(kz_datamgr, open_docs, fun(_, Ids) ->
        {ok, [j([{<<"key">>, Id}, {<<"error">>, <<"not_found">>}]) || Id <- Ids]} end),
    ?assertEqual({M, []}, cb_acdc_queue_editor:verified_manifest_media(M)),
    meck:expect(kz_datamgr, open_docs, fun(_, _) -> {ok, []} end),
    ?assertError({badmatch,false}, cb_acdc_queue_editor:verified_manifest_media(M)).

english_media_doc(Id) ->
    case [A || A <- ?GEMINI_ASSETS, <<(element(1,A))/binary,"/",(element(3,A))/binary>> =:= Id] of
        [{L,C,P,S,M,N,T}] ->
            j([{<<"_id">>,Id},{<<"_rev">>,?REV},{<<"pvt_type">>,<<"media">>},
              {<<"pvt_account_db">>,<<"system_media">>},{<<"source_type">>,<<"kazoo5_acdc_gemini_voice_installer">>},
              {<<"prompt_id">>,P},{<<"language">>,L},{<<"content_type">>,<<"audio/wav">>},
              {<<"content_length">>,N},{<<"streamable">>,true},
              {<<"source_voice">>,j([{<<"provider">>,<<"google-gemini">>},{<<"model">>,<<"gemini-2.5-pro-preview-tts">>},
                  {<<"voice">>,<<"Sulafat">>},{<<"canonical_prompt_id">>,C},{<<"sha256">>,S},{<<"transcript_sha256">>,T}])},
              {<<"_attachments">>,j([{<<P/binary,".wav">>,j([{<<"content_type">>,<<"audio/wav">>},
                  {<<"length">>,N},{<<"digest">>,M}])}])}]);
        [] -> doc(Id, <<"media">>, [{<<"_attachments">>,j([{<<"prompt.wav">>,j([{<<"length">>,16000}])}])}])
    end.
