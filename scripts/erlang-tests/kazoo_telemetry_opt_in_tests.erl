-module(kazoo_telemetry_opt_in_tests).
-include_lib("eunit/include/eunit.hrl").

%% The leader's state is a record; responders is its third field after the tag.
responders(Enabled) ->
    meck:new(kapps_config, [no_link]),
    meck:new(kz_nodes_bindings, [no_link]),
    meck:new(kz_process, [no_link]),
    try
        meck:expect(kapps_config, get_boolean,
                    fun(<<"telemetry">>, <<"enabled">>, 'false', <<"default">>) -> Enabled end),
        meck:expect(kz_nodes_bindings, bind_info, fun(_, _) -> 'ok' end),
        meck:expect(kz_process, set_startup, fun() -> 'ok' end),
        meck:expect(kz_process, startup, fun() -> 0 end),
        {'ok', State} = kazoo_telemetry_leader:init([]),
        Timer = element(3, State),
        _ = erlang:cancel_timer(Timer),
        element(4, State)
    after
        meck:unload(kz_process), meck:unload(kz_nodes_bindings), meck:unload(kapps_config)
    end.

disabled_by_default_test() -> ?assertEqual([], responders('false')).
opt_in_test() -> ?assertEqual(['waveguide_responder'], responders('true')).
