%%% Public Couch adapter contract, using real kz_couch_doc/kz_doc/kz_json.
%%% Only connection acquisition, retry scheduling and Couchbeam transport are
%%% controlled. retry504s invokes its function once: this does NOT test HTTP,
%%% retry timing, CouchDB CAS, kzs_doc hooks, secondary writes or other drivers.
-module(kz_couch_single_delete_result_tests).
-include_lib("eunit/include/eunit.hrl").
-include_lib("couchbeam/include/couchbeam.hrl").

-define(DB, <<"offline-single-delete">>).
-define(ID, <<"owned-document">>).
-define(REV, <<"2-deleted">>).

single_delete_result_test_() ->
    [{Name, {timeout, 30, Fun}} || {Name, Fun} <-
        [{"known per-document errors", fun known_errors/0},
         {"unknown and malformed error values", fun unknown_errors/0},
         {"current and legacy success shape", fun successful_rows/0},
         {"success requires exact protocol fields", fun invalid_success/0},
         {"singleton and object shape", fun malformed_responses/0},
         {"duplicate protocol keys rejected", fun duplicate_keys/0},
         {"error identity checked before mapping", fun identity_scope/0},
         {"transport errors unchanged", fun transport_errors/0},
         {"batch deletion remains unnormalized", fun batch_unchanged/0}]].

doc() -> kz_json:from_list([{<<"_id">>, ?ID}, {<<"_rev">>, <<"1-validated">>}]).
row(Extra) -> kz_json:from_list([{<<"id">>, ?ID} | Extra]).
success() -> row([{<<"ok">>, true}, {<<"rev">>, ?REV}]).

with_transport(Body) ->
    T = ets:new(single_delete_transport, [public, set]),
    Conn = #server{},
    Db = #db{},
    try
        meck:new(kz_couch_util, [non_strict, no_link]),
        meck:new(couchbeam, [non_strict, no_link]),
        meck:expect(kz_couch_util, get_db, fun(C, Name) ->
            ?assertEqual(Conn, C),
            ?assertEqual(?DB, Name),
            ets:update_counter(T, connection_calls, 1),
            Db
        end),
        meck:expect(kz_couch_util, retry504s, fun(F) ->
            ets:update_counter(T, retry_calls, 1),
            F()
        end),
        meck:expect(couchbeam, delete_doc, fun(D, Doc, Options) ->
            transport_result(T, single, D, Db, Doc, Options)
        end),
        meck:expect(couchbeam, delete_docs, fun(D, Docs, Options) ->
            transport_result(T, batch, D, Db, Docs, Options)
        end),
        Body(T, Conn)
    after
        catch meck:unload(couchbeam),
        catch meck:unload(kz_couch_util),
        ets:delete(T)
    end.

transport_result(T, Kind, ActualDb, Db, Docs, Options) ->
    ?assertEqual(Db, ActualDb),
    ets:insert(T, {calls, ets:lookup_element(T, calls, 2) ++ [{Kind, Docs, Options}]}),
    ets:lookup_element(T, response, 2).

check(T, Conn, Response, Expected) -> check(T, Conn, doc(), Response, Expected).
check(T, Conn, Doc, Response, Expected) ->
    Options = [{<<"fixture-option">>, <<"retained">>}],
    reset(T, Response),
    ?assertEqual(Expected, kz_couch_doc:del_doc(Conn, ?DB, Doc, Options)),
    assert_transport(T, single, Doc, Options).

reset(T, Response) ->
    ets:insert(T, [{response, Response}, {calls, []},
                  {connection_calls, 0}, {retry_calls, 0}]).

assert_transport(T, Kind, Docs, Options) ->
    ?assertEqual([{Kind, Docs, Options}], ets:lookup_element(T, calls, 2)),
    ?assertEqual(1, ets:lookup_element(T, connection_calls, 2)),
    ?assertEqual(1, ets:lookup_element(T, retry_calls, 2)).

known_errors() ->
    with_transport(fun(T, C) ->
        lists:foreach(fun({Error, Expected}) ->
            R = row([{<<"error">>, Error}, {<<"reason">>, <<"private-reason-not-returned">>}]),
            check(T, C, {ok, [R]}, {error, Expected}),
            %% Error takes priority even when a revision/positive flag is present.
            Both = kz_json:set_values([{<<"ok">>, true}, {<<"rev">>, ?REV}], R),
            check(T, C, {ok, [Both]}, {error, Expected})
        end, [{<<"conflict">>, conflict}, {<<"not_found">>, not_found}])
    end).

unknown_errors() ->
    with_transport(fun(T, C) ->
        lists:foreach(fun(Error) ->
            %% Preserve null as an actual protocol field; the ordinary setter
            %% would remove it and accidentally construct a successful row.
            R = kz_json:set_value(<<"error">>, Error, success(), #{keep_null => true}),
            check(T, C, {ok, [R]}, {error, failed})
        end, [<<"forbidden">>, <<"unauthorized">>, <<"unknown-private-error">>,
              <<>>, null, false, true, 42, [], kz_json:new()]),
        %% Raw malformed terms avoid kz_json sanitizing the invalid value away.
        R = {[{<<"id">>, ?ID}, {<<"rev">>, ?REV}, {<<"error">>, undefined}]},
        check(T, C, {ok, [R]}, {error, failed})
    end).

successful_rows() ->
    with_transport(fun(T, C) ->
        lists:foreach(fun(R) ->
            Result = {ok, [R]},
            check(T, C, Result, Result)
        end, [success(), row([{<<"rev">>, ?REV}]),
              row([{<<"rev">>, ?REV}, {<<"ok">>, true},
                   {<<"extension">>, <<"preserved-not-rebuilt">>}])])
    end).

invalid_success() ->
    with_transport(fun(T, C) ->
        lists:foreach(fun(Rev) ->
            check(T, C, {ok, [row([{<<"rev">>, Rev}])]}, {error, failed})
        end, [<<>>, null, false, 2, [], kz_json:new()]),
        check(T, C, {ok, [row([{<<"ok">>, true}])]}, {error, failed}),
        lists:foreach(fun(Ok) ->
            R = row([{<<"rev">>, ?REV}, {<<"ok">>, Ok}]),
            check(T, C, {ok, [R]}, {error, failed})
        end, [false, null, <<"true">>, 1, []]),
        check(T, C, {ok, [row([{<<"_rev">>, ?REV}])]}, {error, failed}),
        Alias = kz_json:from_list([{<<"_id">>, ?ID}, {<<"rev">>, ?REV}]),
        check(T, C, {ok, [Alias]}, {error, failed})
    end).

malformed_responses() ->
    with_transport(fun(T, C) ->
        lists:foreach(fun(Response) ->
            check(T, C, Response, {error, failed})
        end, [{ok, []}, {ok, [success(), success()]}, {ok, success()},
              {ok, [success() | bad_tail]}, {ok, [null]}, {ok, [42]},
              {ok, [<<"not-json-object">>]}, {ok, [[]]}, {ok, [#{}]},
              {ok, [{[bad_property]}]}, {ok, [{[{<<"id">>, ?ID} | bad_tail]}]},
              {ok, [{[{<<"id">>, ?ID}, {<<"rev">>, ?REV}, bad_property]}]},
              ok, undefined, {unexpected, response}])
    end).

duplicate_keys() ->
    with_transport(fun(T, C) ->
        Base = [{<<"id">>, ?ID}, {<<"rev">>, ?REV}, {<<"ok">>, true}],
        lists:foreach(fun(Props) ->
            %% Construct the decoded representation directly: no deduplication.
            check(T, C, {ok, [{Props}]}, {error, failed})
        end, [Base ++ [{<<"id">>, <<"different-document">>}],
              [{<<"id">>, <<"different-document">>} | Base],
              Base ++ [{<<"rev">>, <<"different-revision">>}],
              Base ++ [{<<"ok">>, false}],
              [{<<"ok">>, false} | Base],
              Base ++ [{<<"error">>, undefined}, {<<"error">>, <<"conflict">>}],
              Base ++ [{<<"error">>, <<"conflict">>}, {<<"error">>, <<"not_found">>}],
              Base ++ [{<<"error">>, <<"not_found">>}, {<<"error">>, <<"conflict">>}]])
    end).

identity_scope() ->
    with_transport(fun(T, C) ->
        lists:foreach(fun(Id) ->
            lists:foreach(fun(R) ->
                check(T, C, {ok, [kz_json:set_value(<<"id">>, Id, R, #{keep_null => true})]}, {error, failed})
            end, [success(), row([{<<"error">>, <<"conflict">>}]),
                  row([{<<"error">>, <<"not_found">>}])])
        end, [<<"other-document">>, <<>>, null, 7]),
        MissingId = kz_json:from_list([{<<"error">>, <<"not_found">>}]),
        check(T, C, {ok, [MissingId]}, {error, failed}),
        lists:foreach(fun(Doc) ->
            check(T, C, Doc, {ok, [success()]}, {error, failed})
        end, [kz_json:new(), kz_json:from_list([{<<"_id">>, <<>>}])])
    end).

transport_errors() ->
    with_transport(fun(T, C) ->
        lists:foreach(fun(Error) -> check(T, C, Error, Error) end,
            [{error, conflict}, {error, not_found}, {error, timeout},
             {error, db_not_reachable}, {error, {upstream, opaque}},
             {error, <<"existing-transport-error">>}])
    end).

batch_unchanged() ->
    with_transport(fun(T, C) ->
        Docs = [doc(), kz_doc:set_id(doc(), <<"other-document">>)],
        Options = [{<<"batch-option">>, true}],
        Mixed = {ok, [success(), row([{<<"error">>, <<"conflict">>}])]},
        lists:foreach(fun(Response) ->
            reset(T, Response),
            ?assertEqual(Response, kz_couch_doc:del_docs(C, ?DB, Docs, Options)),
            assert_transport(T, batch, Docs, Options)
        end, [Mixed, {ok, []}, {error, timeout}])
    end).
