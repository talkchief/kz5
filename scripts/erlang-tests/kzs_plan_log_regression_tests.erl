%%% SPDX-License-Identifier: MPL-2.0
-module(kzs_plan_log_regression_tests).
-include_lib("eunit/include/eunit.hrl").
-include("kz_data.hrl").

connection_reconnect_logs_test() ->
    Secret = <<"REGRESSION_ONLY_RECONNECT_SECRET">>,
    Connection = #data_connection{id=fixture, app=kazoo_couch, tag = <<"replica">>,
                                  props=#{password => Secret}, server={url, Secret}},
    meck:new(lager, [non_strict, no_link]),
    meck:new(kz_dataconnections, [non_strict, no_link]),
    try
        meck:expect(lager, info, fun(_, _) -> ok end),
        meck:expect(lager, warning, fun(_, _) -> ok end),
        meck:expect(kz_dataconnections, update, fun(_) -> ok end),
        Ready = kz_dataconnection:connection_ready(Connection),
        ?assertEqual(true, Ready#data_connection.ready),
        ?assertEqual(Connection#data_connection.server, Ready#data_connection.server),
        Error = {request_failed, #{authorization => Secret}},
        ?assertEqual({error, Error}, kz_dataconnection:handle_error(Connection, Error)),
        Logged = iolist_to_binary(io_lib:format("~p", [meck:history(lager)])),
        ?assertEqual(nomatch, binary:match(Logged, Secret)),
        ?assertNotEqual(nomatch, binary:match(Logged, <<"replica">>))
    after
        meck:unload([lager, kz_dataconnections])
    end.

connection_secrets_not_logged_test() ->
    Secret = <<"REGRESSION_ONLY_DATABASE_SECRET">>,
    Server = {kazoo_couch, #{password => Secret, url => <<"https://user:", Secret/binary, "@db.invalid">>}},
    Connections = #{<<"local">> => Server, <<"replica">> => Server},
    meck:new(kz_cache, [no_link]),
    meck:new(lager, [non_strict, no_link]),
    try
        meck:expect(kz_cache, fetch_local,
                    fun(kazoo_data_plan_cache, {plan, <<"system">>}) ->
                            {ok, #{<<"connections_map">> => Connections}}
                    end),
        meck:expect(lager, info, fun(_, _) -> ok end),
        meck:expect(lager, debug, fun(_, _) -> ok end),
        ?assertEqual(#{tag => <<"local">>, server => Server,
                       others => [{<<"replica">>, #{server => Server}}]}, kzs_plan:plan()),
        Logged = iolist_to_binary(io_lib:format("~p", [meck:history(lager)])),
        ?assertEqual(nomatch, binary:match(Logged, Secret)),
        ?assertNotEqual(nomatch, binary:match(Logged, <<"replica">>)),
        ?assert(meck:validate(kz_cache))
    after
        meck:unload([kz_cache, lager])
    end.
