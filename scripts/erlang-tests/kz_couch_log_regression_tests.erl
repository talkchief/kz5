%%% SPDX-License-Identifier: MPL-2.0
-module(kz_couch_log_regression_tests).
-include_lib("eunit/include/eunit.hrl").
-include("kz_couch.hrl").

connection_credentials_not_logged_test() ->
    Secret = <<"REGRESSION_ONLY_COUCH_SECRET">>,
    Server = #server{url = <<"http://fixture:", Secret/binary, "@db.invalid">>,
                     options=[{connection_map, #{password => Secret}}]},
    meck:new(lager, [non_strict, no_link]),
    meck:new(couchbeam, [non_strict, no_link]),
    try
        lists:foreach(fun(Level) ->
                              meck:expect(lager, Level, fun(_) -> ok end),
                              meck:expect(lager, Level, fun(_, _) -> ok end)
                      end, [debug, info, warning]),
        meck:expect(couchbeam, server_connection, fun(_, _, _, _) -> Server end),
        meck:expect(couchbeam, server_info,
                    fun(_) -> {ok, kz_json:from_list([{<<"version">>, <<"3.5.2">>}])} end),
        {ok, Connected} = kz_couch_util:new_connection(#{host => "db.invalid", port => 5984,
                                                        username => "fixture", password => Secret}),
        ?assertEqual(Server#server.url, Connected#server.url),
        lists:foreach(fun({Result, Expected}) ->
                              meck:expect(couchbeam, server_info, fun(_) -> Result end),
                              ?assertEqual(Expected, kz_couch_util:connection_info(Server))
                      end,
                      [{{error, {conn_failed, {error, timeout}}}, {error, timeout}},
                       {{error, {conn_failed, {error, ehostunreach}}}, {error, ehostunreach}},
                       {{error, {request_failed, Secret}}, {error, {request_failed, Secret}}}]),
        Logged = iolist_to_binary(io_lib:format("~p", [meck:history(lager)])),
        ?assertEqual(nomatch, binary:match(Logged, Secret)),
        ?assertEqual(nomatch, binary:match(Logged, <<"http://fixture:">>))
    after
        meck:unload([lager, couchbeam])
    end.
