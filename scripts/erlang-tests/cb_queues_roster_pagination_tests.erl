%%% SPDX-License-Identifier: MPL-2.0
%%% Exercise the real public roster validation paths with 120 members. Only the
%%% database boundaries are mocked; the Crossbar context pagination API is real.
-module(cb_queues_roster_pagination_tests).
-include_lib("eunit/include/eunit.hrl").
-define(QUEUE, <<"test-roster-queue">>).

roster_pagination_test_() ->
    [{timeout, 30, fun() -> with_store(fun replacement_ignores_client_page/1) end}
    ,{timeout, 30, fun() -> with_store(fun replacement_ignores_default_page/1) end}
    ,{timeout, 30, fun() -> with_store(fun replacement_ignores_bookmarks_and_filters/1) end}
    ,{timeout, 30, fun() -> with_store(fun empty_replacement_removes_all/1) end}
    ,{timeout, 30, fun() -> with_store(fun delete_removes_all/1) end}
    ,{timeout, 30, fun() -> with_store(fun get_keeps_client_pagination/1) end}
    ].

replacement_ignores_client_page(Store) ->
    replacement(Store, kz_json:from_list([{<<"page_size">>, 1}, {<<"paginate">>, true}])).

replacement_ignores_default_page(Store) -> replacement(Store, kz_json:new()).

replacement_ignores_bookmarks_and_filters(Store) ->
    Query = kz_json:from_list([{<<"page_size">>, 1}, {<<"start_key">>, <<"partial-start">>}
                              ,{<<"cursor">>, <<"opaque-partial-cursor">>}
                              ,{<<"filter_enabled">>, true}, {<<"fields">>, [<<"id">>]}]),
    replacement(Store, Query).

replacement(Store, Query) ->
    Keep = lists:sublist(ids(), 30),
    Context = context(<<"POST">>, Keep, Query),
    Result = cb_queues:validate(Context, ?QUEUE, <<"roster">>),
    ?assertEqual(success, cb_context:resp_status(Result)),
    ?assertEqual(Query, cb_context:query_string(Result)),
    ?assertEqual(ids(), observed(Store, loaded)),
    RemovedDocs = observed(Store, saved),
    ?assertEqual(lists:nthtail(30, ids()), [kz_doc:id(D) || D <- RemovedDocs]),
    [?assertEqual([<<"other-queue">>], kz_json:get_value(<<"queues">>, D)) || D <- RemovedDocs].

empty_replacement_removes_all(Store) ->
    Context = context(<<"POST">>, [], kz_json:from_list([{<<"page_size">>, 2}])),
    Result = cb_queues:validate(Context, ?QUEUE, <<"roster">>),
    assert_all_removed(Store, Result).

delete_removes_all(Store) ->
    %% DELETE ignores an apparent selective body and clears current membership.
    Context = context(<<"DELETE">>, [hd(ids())], kz_json:from_list([{<<"page_size">>, 1}])),
    Result = cb_queues:validate(Context, ?QUEUE, <<"roster">>),
    assert_all_removed(Store, Result).

assert_all_removed(Store, Result) ->
    ?assertEqual(success, cb_context:resp_status(Result)),
    ?assertEqual(ids(), observed(Store, loaded)),
    Docs = cb_context:doc(Result),
    ?assertEqual(ids(), [kz_doc:id(D) || D <- Docs]),
    [?assertEqual([<<"other-queue">>], kz_json:get_value(<<"queues">>, D)) || D <- Docs].

get_keeps_client_pagination(Store) ->
    Context = context(<<"GET">>, [], kz_json:from_list([{<<"page_size">>, 2}, {<<"paginate">>, true}])),
    Result = cb_queues:validate(Context, ?QUEUE, <<"roster">>),
    ?assertEqual(lists:sublist(ids(), 2), cb_context:resp_data(Result)),
    ?assertEqual(lists:sublist(ids(), 2), observed(Store, loaded)),
    ?assertEqual(true, cb_context:should_paginate(Result)),
    ?assertEqual([], ets:lookup(Store, saved)).

context(Verb, Data, Query) ->
    cb_context:setters(cb_context:new(),
                      [{fun cb_context:set_req_verb/2, Verb}
                      ,{fun cb_context:set_req_data/2, Data}
                      ,{fun cb_context:set_query_string/2, Query}
                      ,{fun cb_context:set_should_paginate/2, true}]).

ids() -> [list_to_binary(io_lib:format("agent-~3..0B", [N])) || N <- lists:seq(1, 120)].
observed(Store, Key) -> [{Key, Value}] = ets:lookup(Store, Key), Value.

with_store(Test) ->
    Store = ets:new(roster_pagination_observations, [set, public]),
    meck:new([crossbar_view, crossbar_doc, lager], [non_strict, no_link]),
    try
        meck:expect(lager, debug, fun(_) -> ok end),
        meck:expect(lager, debug, fun(_, _) -> ok end),
        meck:expect(crossbar_view, get_id_fun, fun() -> fun(Doc, Acc) -> [kz_doc:id(Doc) | Acc] end end),
        meck:expect(crossbar_view, load, fun(Context, <<"queues/agents_listing">>, _Options) ->
            Members = case cb_context:should_paginate(Context) of
                          false ->
                              ?assertEqual([], kz_json:get_keys(cb_context:query_string(Context))),
                              ids();
                          true -> lists:sublist(ids(), kz_json:get_integer_value(<<"page_size">>, cb_context:query_string(Context), 50))
                      end,
            ets:insert(Store, {loaded, Members}),
            cb_context:setters(Context, [{fun cb_context:set_doc/2, Members}
                                       ,{fun cb_context:set_resp_data/2, Members}
                                       ,{fun cb_context:set_resp_status/2, success}])
        end),
        meck:expect(crossbar_doc, load, fun(Members, Context, _Options) ->
            Docs = [kz_json:from_list([{<<"_id">>, Id}, {<<"queues">>, [?QUEUE, <<"other-queue">>]}]) || Id <- Members],
            cb_context:set_doc(cb_context:set_resp_status(Context, success), Docs)
        end),
        meck:expect(crossbar_doc, save, fun(Context) ->
            ets:insert(Store, {saved, cb_context:doc(Context)}),
            cb_context:set_resp_status(Context, success)
        end),
        Test(Store)
    after
        meck:unload([crossbar_view, crossbar_doc, lager]),
        ets:delete(Store)
    end.
