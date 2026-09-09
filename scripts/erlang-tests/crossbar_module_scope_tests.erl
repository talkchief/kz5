%%% Public production maintenance calls; configuration and module-start seams
%%% are controlled. Does not claim native multi-node/CouchDB conflict acceptance.
-module(crossbar_module_scope_tests).
-include_lib("eunit/include/eunit.hrl").

module_scope_test_() ->
    [{Name, {timeout, 30, fun() -> run(Case) end}} || {Name, Case} <-
        [{"node override start preserves cluster and zone defaults", node_start},
         {"zone override start preserves cluster defaults", zone_start},
         {"default start preserves other nodes", default_start},
         {"empty node override remains node scoped", empty_node},
         {"node stop preserves cluster and zone defaults", node_stop},
         {"zone stop preserves cluster defaults", zone_stop},
         {"already enabled module does not persist", already_enabled},
         {"configuration read failure does not persist", read_failure},
         {"missing category can initialize default", missing_category}]].

run(Case) ->
    Node = kz_term:to_binary(node()), Zone = <<"fixture-zone">>, Other = <<"other@fixture">>,
    Base = kz_json:from_list([{<<"default">>, config([<<"cb_accounts">>, <<"cb_users">>])},
                             {Other, config([<<"cb_devices">>])}]),
    {Scope, Effective, Doc} = case Case of
        C when C =:= node_start; C =:= node_stop; C =:= read_failure ->
            node_case(C, Node, Zone, Base);
        C when C =:= zone_start; C =:= zone_stop ->
            List = case C of zone_stop -> [<<"cb_storage">>, <<"cb_cdrs">>]; _ -> [<<"cb_cdrs">>] end,
            {Zone, List, kz_json:set_value(Zone, config(List), Base)};
        empty_node -> {Node, [], kz_json:set_value(Node, config([]), Base)};
        already_enabled -> {Node, [<<"cb_storage">>], kz_json:set_value(Node, config([<<"cb_storage">>]), Base)};
        missing_category -> {<<"default">>, [<<"cb_accounts">>], kz_json:new()};
        default_start -> {<<"default">>, [<<"cb_accounts">>, <<"cb_users">>], Base}
    end,
    T = ets:new(module_scope_fixture, [public, set]),
    ets:insert(T, [{doc, Doc}, {writes, []}]),
    Modules = [crossbar_init, crossbar_config, kapps_config, kz_config, kz_datamgr],
    try
        %% Strict mocks reject expectations for APIs the real module does not
        %% export; otherwise a private-function typo can pass every unit test.
        lists:foreach(fun(M) -> meck:new(M, [no_link]) end, Modules),
        meck:expect(crossbar_init, start_mod, fun(_) -> ok end),
        meck:expect(crossbar_init, stop_mod, fun(_) -> ok end),
        meck:expect(crossbar_config, autoload_modules, fun() -> Effective end),
        meck:expect(crossbar_config, set_default_autoload_modules,
                    fun(Value) -> save(T, <<"default">>, Value) end),
        meck:expect(kz_config, zone, fun() -> Zone end),
        %% Mock the public uncached read, not a fabricated private config export.
        %% The previous get_category/2 expectation hid an undef in real installs.
        meck:expect(kz_datamgr, open_doc, fun(<<"system_config">>, <<"crossbar">>) ->
            case Case of read_failure -> {error, timeout}; missing_category -> {error, not_found}; _ -> {ok, Doc} end
        end),
        meck:expect(kapps_config, set_node, fun(<<"crossbar">>, <<"autoload_modules">>, Value, Owner) ->
            save(T, Owner, Value)
        end),
        Result = catch case Case of
            C1 when C1 =:= node_stop; C1 =:= zone_stop -> crossbar_maintenance:stop_module(<<"cb_storage">>);
            _ -> crossbar_maintenance:start_module(<<"cb_storage">>)
        end,
        case Case of
            read_failure -> ?assertMatch({'EXIT', _}, Result), ?assertEqual([], ets:lookup_element(T, writes, 2));
            already_enabled -> ?assertEqual(ok, Result), ?assertEqual([], ets:lookup_element(T, writes, 2));
            _ ->
                ?assertEqual(ok, Result),
                Expected = case Case of
                    C2 when C2 =:= node_stop; C2 =:= zone_stop -> lists:delete(<<"cb_storage">>, Effective);
                    _ -> [<<"cb_storage">> | Effective]
                end,
                ?assertEqual([{Scope, Expected}], ets:lookup_element(T, writes, 2)),
                ?assertEqual(kz_json:set_value([Scope, <<"autoload_modules">>], Expected, Doc), ets:lookup_element(T, doc, 2))
        end
    after
        lists:foreach(fun(M) -> catch meck:unload(M) end, Modules), ets:delete(T)
    end.

node_case(Case, Node, Zone, Base) ->
    List = case Case of node_stop -> [<<"cb_storage">>, <<"cb_cdrs">>]; _ -> [<<"cb_cdrs">>] end,
    {Node, List, kz_json:set_values([{Node, config(List)}, {Zone, config([<<"cb_tokens">>])}], Base)}.

config(List) -> kz_json:from_list([{<<"autoload_modules">>, List}, {<<"unrelated">>, true}]).
save(T, Scope, Value) ->
    Doc = kz_json:set_value([Scope, <<"autoload_modules">>], Value, ets:lookup_element(T, doc, 2)),
    ets:insert(T, [{doc, Doc}, {writes, ets:lookup_element(T, writes, 2) ++ [{Scope, Value}]}]),
    {ok, Doc}.
