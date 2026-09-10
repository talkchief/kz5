-module(acdc_agent_status_strict_tests).
-include_lib("eunit/include/eunit.hrl").
-define(MOCKS,[kz_amqp_worker,kz_datamgr,acdc_stats_util,kazoo_modb_util,kz_api]).
strict_status_test_() ->
    [{Name,{setup,fun setup/0,fun cleanup/1,fun(_)->Test end}} || {Name,Test} <-
        [{"current database errors remain errors for startup",fun current_error/0}
        ,{"previous database errors remain errors for startup",fun previous_error/0}
        ,{"verified empty history remains legitimate unknown",fun empty_history/0}
        ,{"absent previous month remains legitimate unknown",fun absent_previous/0}
        ,{"current saved status remains authoritative",fun current_status/0}
        ,{"previous saved status remains usable",fun previous_status/0}
        ,{"malformed status cannot start an agent",fun malformed/0}]].
setup() ->
    [meck:new(M,[non_strict,no_link])||M<-?MOCKS],
    meck:expect(kz_amqp_worker,call_collect,fun(_,_,_,_)->{error,unavailable} end),
    meck:expect(kz_api,default_headers,fun(_,_)->[] end),
    meck:expect(acdc_stats_util,db_name,fun(_)-><<"current">> end),
    meck:expect(kazoo_modb_util,prev_year_month_mod,fun(_)-><<"previous">> end),ok.
cleanup(_) -> [meck:unload(M)||M<-?MOCKS],ok.
data(Current,Previous) ->
    meck:expect(kz_datamgr,get_results,
        fun(<<"current">>,<<"agent_stats/status_log">>,_)->Current;
           (<<"previous">>,<<"agent_stats/status_log">>,_)->Previous end).
strict() -> acdc_agent_util:most_recent_status_strict(<<"account">>,<<"agent">>).
legacy() -> acdc_agent_util:most_recent_status(<<"account">>,<<"agent">>).
current_error() ->
    data({error,timeout},{ok,[]}),?assertEqual({error,timeout},strict()),?assertEqual({ok,<<"unknown">>},legacy()).
previous_error() ->
    data({ok,[]},{error,gateway_timeout}),?assertEqual({error,gateway_timeout},strict()),?assertEqual({ok,<<"unknown">>},legacy()).
empty_history() -> data({ok,[]},{ok,[]}),?assertEqual({ok,<<"unknown">>},strict()).
absent_previous() -> data({ok,[]},{error,not_found}),?assertEqual({ok,<<"unknown">>},strict()).
current_status() ->
    data({ok,[kz_json:from_list([{<<"value">>,<<"ready">>}])]},{error,unused}),
    ?assertEqual({ok,<<"ready">>},strict()),?assertEqual({ok,<<"ready">>},legacy()).
previous_status() ->
    data({ok,[]},{ok,[kz_json:from_list([{<<"value">>,<<"paused">>}])]}),?assertEqual({ok,<<"paused">>},strict()).
malformed() -> data({ok,[kz_json:new()]},{ok,[]}),?assertEqual({error,invalid_agent_status},strict()).
