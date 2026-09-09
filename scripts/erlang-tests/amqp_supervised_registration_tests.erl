-module(amqp_supervised_registration_tests).
-include_lib("eunit/include/eunit.hrl").
-include("kz_amqp.hrl").

supervised_restart_test_() ->
    [{atom_to_list(Zone) ++ " registration survives replacement",
      fun() -> replacement(Zone, Tags) end}
     || {Zone, Tags} <- [{local, []}, {remote_fixture, []}, {remote_fixture, [<<"hidden">>]}]].

replacement(Zone, Tags) ->
    process_flag(trap_exit, true),
    meck:new(lager, [non_strict, no_link]),
    meck:new(kz_log, [non_strict, no_link]),
    meck:expect(kz_log, put_callid, fun(_) -> ok end),
    [meck:expect(lager, L, fun(_, _) -> ok end) || L <- [debug, info, warning]],
    {ok, Registry} = kz_amqp_connections:start_link(),
    {ok, Sup} = kz_amqp_connection_sup:start_link(),
    try
        Conn = #kz_amqp_connection{broker = <<"amqp://fixture.invalid">>, tags=Tags},
        Conn = kz_amqp_connections:add(Conn, Zone),
        [Before] = wait_records(Zone, Tags, undefined, 60),
        Old = Before#kz_amqp_connections.connection,
        kz_amqp_connections:available(Old),
        wait_available(Old, 60),
        exit(Old, kill),
        [After] = wait_records(Zone, Tags, Old, 60),
        New = After#kz_amqp_connections.connection,
        ?assertNotEqual(Old, New),
        ?assert(is_process_alive(New)),
        ?assertEqual(false, After#kz_amqp_connections.available),
        ?assertEqual(lists:member(<<"hidden">>, Tags), After#kz_amqp_connections.hidden),
        kz_amqp_connections:available(New),
        wait_available(New, 60)
    after
        gen_server:stop(Sup), gen_server:stop(Registry),
        meck:unload(kz_log), meck:unload(lager)
    end.

wait_records(_, _, _, 0) -> error(replacement_registration_missing);
wait_records(Zone, Tags, Old, N) ->
    case kz_amqp_connections:connections() of
        [#kz_amqp_connections{connection=P, zone=Zone, tags=Tags}]=Rows when P =/= Old -> Rows;
        _ -> timer:sleep(5), wait_records(Zone, Tags, Old, N-1)
    end.
wait_available(_, 0) -> error(replacement_availability_missing);
wait_available(P, N) ->
    case kz_amqp_connections:connections() of
        [#kz_amqp_connections{connection=P, available=true}] -> ok;
        _ -> timer:sleep(5), wait_available(P, N-1)
    end.
