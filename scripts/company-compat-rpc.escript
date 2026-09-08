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
run(["api-modules"], Node) ->
    print_api_modules(Node);
run(["prepare-api"], Node) ->
    %% Match the normal installer's explicitly registered API modules. Starting
    %% the ACDC application alone does not register its Crossbar endpoints.
    lists:foreach(fun(Module) ->
        ok = rpc:call(Node, crossbar_maintenance, start_module, [Module], 30000)
    end, api_modules()),
    print_api_modules(Node),
    Running = rpc:call(Node, crossbar_maintenance, running_modules, [], 15000),
    Autoload = rpc:call(Node, crossbar_config, autoload_modules, [], 15000),
    true = lists:all(fun(Module) ->
        lists:member(Module, Running) andalso lists:member(atom_to_binary(Module, utf8), Autoload)
    end, api_modules());
run(["migrate-company"], Node) ->
    %% Explicit seven-DB selection only. Never call migrate/0 or migrate/1:
    %% those enumerate globals and every baseline/working database in the lab.
    AccountDb = <<"account%2Fd8%2F52%2F0ce3f29c5b6db692289e782c92af">>,
    Monthly = [<<AccountDb/binary, "-2026", Month/binary>>
               || Month <- [<<"04">>, <<"05">>, <<"06">>, <<"07">>, <<"08">>, <<"09">>]],
    account = rpc:call(Node, kz_datamgr, db_classification, [AccountDb], 15000),
    true = lists:all(fun(Db) ->
        modb =:= rpc:call(Node, kz_datamgr, db_classification, [Db], 15000)
    end, Monthly),
    Databases = [AccountDb | Monthly],
    true = lists:all(fun(Db) -> rpc:call(Node, kz_datamgr, db_exists, [Db], 15000) =:= true end, Databases),
    %% migrate/2 is private, so invoke its exported native components directly.
    %% No selected DB is deprecated (classification checked above), therefore
    %% omit the deletion step entirely. Full global migrate/0 remains untested.
    lists:foreach(fun(Db) ->
        ok = rpc:call(Node, kapps_maintenance, refresh, [Db], 120000)
    end, Databases),
    io:format("selected_database_refreshes_returned_ok=7~n"),
    ok = rpc:call(Node, kapps_account_config, migrate, [AccountDb], 120000),
    io:format("account_config_migration_returned_ok=true~n"),
    ok = rpc:call(Node, kapps_maintenance, migrate_failover_from_forward, [[AccountDb]], 120000),
    io:format("account_failover_migration_returned_ok=true~n"),
    Results = rpc:call(Node, kazoo_bindings, map, [<<"maintenance.migrate">>, [[AccountDb]]], 120000),
    true = is_list(Results),
    %% Native components can log internally handled failures even when they
    %% return ok. Inspect captured logs and document changes independently.
    io:format("account_migration_hook_results=~p~n", [length(Results)]),
    io:format("selected_company_migration_steps_returned_normally=true~n");
run(["refresh-account"], Node) ->
    %% No arbitrary modules/functions, broad migration or user-selected account.
    Result = rpc:call(Node, kapps_maintenance, refresh_account,
                      [<<"d8520ce3f29c5b6db692289e782c92af">>], 120000),
    case Result of
        ok -> io:format("account_refresh_returned_ok=true~n");
        _ -> io:format("account_refresh_returned_ok=false~n"), halt(1)
    end;
run(_, _) -> halt(2).

api_modules() -> [cb_queues, cb_agents, cb_acdc_call_stats, cb_external_numbers, cb_members].

print_api_modules(Node) ->
    Running = rpc:call(Node, crossbar_maintenance, running_modules, [], 15000),
    Autoload = rpc:call(Node, crossbar_config, autoload_modules, [], 15000),
    true = is_list(Running),
    true = is_list(Autoload),
    lists:foreach(fun(Module) ->
        io:format("module=~p running=~p autoload=~p~n", [Module,
            lists:member(Module, Running), lists:member(atom_to_binary(Module, utf8), Autoload)])
    end, api_modules()).
