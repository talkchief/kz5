#!/usr/bin/env escript
%%! +S 1:1 +SDcpu 1 +SDio 1 +A 2
%% Fixed-scope RPC helper; run inside the dedicated lab network namespace.
main(["self-test"]) ->
    %% Pure return-shape tests: no namespace, credentials or network access.
    ok = hook_status(ok),
    ok = hook_status({ok, <<"private fixture">>}),
    error = hook_status({error, <<"private fixture">>}),
    error = hook_status({'EXIT', {private_fixture, []}}),
    error = hook_status({badrpc, timeout}),
    unknown = hook_status({unrecognized, <<"private fixture">>}),
    true = number_view_return_ok(ok),
    true = number_view_return_ok(no_return),
    false = number_view_return_ok({badrpc, timeout}),
    false = number_view_return_ok({error, conflict}),
    false = number_view_return_ok(true),
    false = number_view_return_ok({ok, private_fixture}),
    io:format("hook_return_shape_tests=6 number_view_return_tests=6 passed=true~n");
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
run(["audit-refresh-writes"], Node) ->
    %% MUTATING diagnostic, restricted to the existing isolated working copy.
    %% Decompose the native refresh, restoring the generated number-service
    %% view in an after block even when inspection fails. No raw documents,
    %% caller data, credentials or revision hashes are printed.
    AccountId = <<"d8520ce3f29c5b6db692289e782c92af">>,
    AccountDb = <<"account%2Fd8%2F52%2F0ce3f29c5b6db692289e782c92af">>,
    ViewId = <<"_design/numbers">>,
    account = rpc:call(Node, kz_datamgr, db_classification, [AccountDb], 15000),
    Before = read_document(Node, AccountDb, ViewId),
    AggregateBefore = read_document(Node, <<"accounts">>, AccountId),
    true = has_reconcile_view(Node, Before),
    try
        Updated = rpc:call(Node, kz_datamgr, refresh_views, [AccountDb], 120000),
        true = is_boolean(Updated),
        Static = read_document(Node, AccountDb, ViewId),
        io:format("static_phase_reconcile_present=~p~n", [has_reconcile_view(Node, Static)]),
        print_document_delta(Node, static_phase, Before, Static)
    after
        %% This is the same responder as maintenance.refresh.account.*.
        %% Do not let an unexpected result silently count as recovery.
        RestoreResult = rpc:call(Node, kazoo_numbers_maintenance,
                                  update_number_services_view, [AccountId], 120000),
        %% The unchanged branch returns no_return; the updating branch ends
        %% in io:format/2 and returns ok despite its narrower source spec.
        %% Neither result establishes success without the readback below.
        true = number_view_return_ok(RestoreResult)
    end,
    Final = read_document(Node, AccountDb, ViewId),
    true = has_reconcile_view(Node, Final),
    true = same_document_content(Node, Before, Final),
    print_document_delta(Node, restored_number_view, Before, Final),
    ok = rpc:call(Node, kapps_maintenance, ensure_aggregate_account, [AccountId], 120000),
    AggregateAfter = read_document(Node, <<"accounts">>, AccountId),
    print_document_delta(Node, aggregate_account, AggregateBefore, AggregateAfter),
    io:format("refresh_write_audit_completed=true generated_view_restored=true~n");
run(["verify-media-fix"], Node) ->
    Path = "/var/lib/kazoo-compat-runtime/apps/overrides/kazoo_media_maintenance.beam",
    Path = rpc:call(Node, code, which, [kazoo_media_maintenance], 15000),
    {ok, {kazoo_media_maintenance, Md5}} = beam_lib:md5(Path),
    Md5 = rpc:call(Node, kazoo_media_maintenance, module_info, [md5], 15000),
    Compile = rpc:call(Node, kazoo_media_maintenance, module_info, [compile], 15000),
    Options = proplists:get_value(options, Compile, []),
    true = lists:member({parse_transform, lager_transform}, Options),
    false = lists:member(export_all, Options),
    true = rpc:call(Node, erlang, function_exported, [kazoo_media_maintenance, migrate, 0], 15000),
    true = rpc:call(Node, erlang, function_exported, [kazoo_media_maintenance, migrate, 1], 15000),
    Apps = rpc:call(Node, application, which_applications, [], 15000),
    true = is_list(Apps),
    true = lists:all(fun(App) -> lists:keymember(App, 1, Apps) end,
                     [kazoo_media, crossbar, acdc, callflow, blackhole]),
    io:format("media_fix_origin_verified=true runtime_md5_matches=true production_transform=true required_apps_running=true~n");
run(["migration-hooks"], Node) ->
    %% Inspect responder MFAs and accepted arities without invoking a hook or
    %% printing bound payloads (which may contain customer data).
    Bindings = rpc:call(Node, kazoo_bindings, bindings, [<<"maintenance.migrate">>], 15000),
    true = is_list(Bindings),
    lists:foreach(fun({kz_binding, _, _, Responders, _}) ->
        lists:foreach(fun({kz_responder, M, F, Payload}) when is_atom(M), is_atom(F) ->
            io:format("hook_module=~p function=~p bound_payload=~p arity0=~p arity1=~p~n", [M, F,
                Payload =/= undefined,
                rpc:call(Node, erlang, function_exported, [M, F, 0], 15000),
                rpc:call(Node, erlang, function_exported, [M, F, 1], 15000)]);
            (_) -> io:format("hook_shape=unsupported~n")
        end, queue:to_list(Responders))
    end, Bindings);
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
    Statuses = [hook_status(Result) || Result <- Results],
    io:format("account_migration_hook_statuses=~p~n", [Statuses]),
    true = not lists:member(error, Statuses),
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

number_view_return_ok(ok) -> true;
number_view_return_ok(no_return) -> true;
number_view_return_ok(_) -> false.

read_document(Node, Db, Id) ->
    {ok, Doc} = rpc:call(Node, kz_datamgr, open_doc, [Db, Id], 15000),
    Doc.

has_reconcile_view(Node, Doc) ->
    Map = rpc:call(Node, kz_json, get_ne_binary_value,
                   [[<<"views">>, <<"reconcile_services">>, <<"map">>], Doc], 15000),
    Reduce = rpc:call(Node, kz_json, get_ne_binary_value,
                      [[<<"views">>, <<"reconcile_services">>, <<"reduce">>], Doc], 15000),
    is_binary(Map) andalso is_binary(Reduce).

same_document_content(Node, Before, After) ->
    CleanBefore = rpc:call(Node, kz_doc, delete_revision, [Before], 15000),
    CleanAfter = rpc:call(Node, kz_doc, delete_revision, [After], 15000),
    Equal = rpc:call(Node, kz_json, are_equal, [CleanBefore, CleanAfter], 15000),
    true = is_boolean(Equal),
    Equal.

print_document_delta(Node, Phase, Before, After) ->
    RevBefore = rpc:call(Node, kz_doc, revision, [Before], 15000),
    RevAfter = rpc:call(Node, kz_doc, revision, [After], 15000),
    true = is_binary(RevBefore) andalso is_binary(RevAfter),
    io:format("phase=~p content_unchanged=~p revision_changed=~p~n",
              [Phase, same_document_content(Node, Before, After), RevBefore =/= RevAfter]).

hook_status(ok) -> ok;
hook_status(no_return) -> no_return;
hook_status(true) -> true;
hook_status(false) -> false;
hook_status({ok, _}) -> ok;
hook_status({error, _}) -> error;
hook_status({'EXIT', _}) -> error;
hook_status({badrpc, _}) -> error;
hook_status(_) -> unknown.

print_api_modules(Node) ->
    Running = rpc:call(Node, crossbar_maintenance, running_modules, [], 15000),
    Autoload = rpc:call(Node, crossbar_config, autoload_modules, [], 15000),
    true = is_list(Running),
    true = is_list(Autoload),
    lists:foreach(fun(Module) ->
        io:format("module=~p running=~p autoload=~p~n", [Module,
            lists:member(Module, Running), lists:member(atom_to_binary(Module, utf8), Autoload)])
    end, api_modules()).
