#!/usr/bin/env escript
%%! +S 1:1 +SDcpu 1 +SDio 1 +A 2
%% Fixed-scope RPC helper; run inside the dedicated lab network namespace.
main(Args) ->
    try
        put(stage, namespace),
        {ok, Net} = file:read_link("/proc/self/ns/net"),
        {ok, HostNet} = file:read_link("/proc/1/ns/net"),
        true = Net =/= HostNet,
        Pid = string:trim(os:cmd("systemctl show kazoo-compat-couchdb.service -p MainPID --value")),
        true = list_to_integer(Pid) > 0,
        {ok, Net} = file:read_link("/proc/" ++ Pid ++ "/ns/net"),
        put(stage, distribution),
        {ok, _} = net_kernel:start(['compat_probe@127.0.0.1', longnames]),
        put(stage, cookie),
        {ok, Cookie} = file:read_file("/var/lib/kazoo-compat-runtime/apps/home/.erlang.cookie"),
        true = erlang:set_cookie(node(), binary_to_atom(string:trim(Cookie), utf8)),
        Node = 'kazoo_compat@127.0.0.1',
        put(stage, ping),
        pong = net_adm:ping(Node),
        put(stage, action),
        run(Args, Node)
    catch _:_ ->
        io:format(standard_error, "Isolated lab RPC failed at ~p; private error details withheld.~n", [get(stage)]),
        halt(1)
    end.

run(["status"], Node) ->
    Apps = rpc:call(Node, application, which_applications, [], 15000),
    true = is_list(Apps),
    io:format("applications=~p~n", [lists:sort([App || {App, _, _} <- Apps])]),
    io:format("bootstrap=~p~n", [rpc:call(Node, persistent_term, get, [kz_datamgr_bootstrap, false], 15000)]),
    io:format("otp=~p~n", [rpc:call(Node, erlang, system_info, [otp_release], 15000)]);
run(["refresh-account"], Node) ->
    %% No arbitrary modules/functions, broad migration or user-selected account.
    Result = rpc:call(Node, kapps_maintenance, refresh_account,
                      [<<"d8520ce3f29c5b6db692289e782c92af">>], 120000),
    case Result of
        ok -> io:format("account_refresh_returned_ok=true~n");
        _ -> io:format("account_refresh_returned_ok=false~n"), halt(1)
    end;
run(_, _) -> halt(2).
