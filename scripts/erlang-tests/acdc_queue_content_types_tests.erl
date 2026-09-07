%%% Real production content negotiation callbacks; no request/store mocks.
-module(acdc_queue_content_types_tests).
-include_lib("eunit/include/eunit.hrl").
-include_lib("crossbar/src/crossbar.hrl").

context() ->
    cb_context:add_content_types_provided(cb_context:new(),
        [{existing_handler,[{<<"application">>,<<"custom">>,[]}]}]).

routes_test_() ->
    Q = <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>,
    [{"collection retains context", fun() ->
        C=context(), ?assertEqual(C,cb_queues:content_types_provided(C)) end},
     {"single-token routes retain context", fun() ->
        C=context(),
        [?assertEqual(C,apply(cb_queues,content_types_provided,[C,P]))
         || P<-[Q,<<"live">>,<<"editor">>,<<"eavesdrop">>]] end},
     {"queue subresources retain context", fun() ->
        C=context(),
        [?assertEqual(C,apply(cb_queues,content_types_provided,[C,Q,P]))
         || P<-[<<"live">>,<<"editor">>,<<"roster">>,<<"stats">>,<<"callbacks">>,<<"eavesdrop">>]] end},
     {"individual callback retains context", fun() ->
        C=context(),
        ?assertEqual(C,apply(cb_queues,content_types_provided,[C,Q,<<"callbacks">>,<<"callback-id">>])) end},
     {"stats retains JSON CSV and existing handlers", fun() ->
        C=context(),
        ?assertEqual([{'to_json',?JSON_CONTENT_TYPES},{'to_csv',?CSV_CONTENT_TYPES}]
                     ++cb_context:content_types_provided(C),
                     cb_context:content_types_provided(cb_queues:content_types_provided(C,<<"stats">>))) end},
     {"unknown nested routes remain unavailable", fun() ->
        ?assertEqual(false,cb_queues:resource_exists(Q,<<"unknown">>,<<"unknown">>)) end}].
