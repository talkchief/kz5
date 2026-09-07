%%% Actual Cowboy REST preconditions and TCP HTTP/1.1 wire; private netns only.
%%% Real public crossbar_doc/context/revision transforms, controlled datastore.
%%% NOT full Crossbar routing/auth/etag bindings, CouchDB, service or live proof.
-module(crossbar_soft_delete_http_tests).
-include_lib("eunit/include/eunit.hrl").
-define(A, <<"11111111111111111111111111111111">>).
-define(ID, <<"22222222222222222222222222222222">>).
-define(DB, <<"account%2F11%2F11%2F1111111111111111111111111111">>).
-define(R1, <<"1-validated">>).

http_preconditions_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(S) ->
        [{Name, {timeout, 10, fun() -> run_case(S, Header, Race, Code, Deletes) end}} ||
         {Name, Header, Race, Code, Deletes} <-
             [{"stale strong tag returns412 before delete", <<"\"0-stale\"">>, false, 412, 0},
              {"weak matching tag returns412 before delete", <<"W/\"1-validated\"">>, false, 412, 0},
              {"matching strong tag deletes validated revision", <<"\"1-validated\"">>, false, 204, 1},
              {"strong tag list accepts its exact matching member", <<"\"0-stale\", \"1-validated\"">>, false, 204, 1},
              {"nonmatching tag list returns412", <<"\"0-stale\", \"4-other\"">>, false, 412, 0},
              {"wildcard uses normal existing-resource semantics", <<"*">>, false, 204, 1},
              {"absent header still deletes the validated revision", undefined, false, 204, 1},
              {"malformed tag returns400 without delete", <<"not-a-quoted-tag">>, false, 400, 0},
              {"matching validation then competing r2 gives409", <<"\"1-validated\"">>, true, 409, 1},
              {"headerless validation then competing r2 gives409", undefined, true, 409, 1}]]
    end}.

setup() ->
    %% This fixture never opens a listener in the host network namespace.
    {ok, SelfNet} = file:read_link("/proc/self/ns/net"),
    {ok, InitNet} = file:read_link("/proc/1/ns/net"),
    ?assertNotEqual(InitNet, SelfNet),
    T = ets:new(soft_delete_http_fixture, [public, set]),
    Listener = make_ref(),
    try
        {ok, Started} = application:ensure_all_started(cowboy),
        put(soft_delete_http_started, Started),
        ok = meck:new(kz_datamgr, [non_strict, no_link]),
        ok = meck:new(kz_process, [non_strict, no_link]),
        meck:expect(kz_process, spawn, fun(_, _) -> error(unexpected_external_hook) end),
        meck:expect(kz_datamgr, ensure_saved, fun(_, _) -> error(unexpected_conflict_retry) end),
        meck:expect(kz_datamgr, lookup_doc_rev, fun(?DB, ?ID) ->
            ets:update_counter(T, lookup_calls, 1),
            {ok, kz_doc:revision(ets:lookup_element(T, current, 2))}
        end),
        meck:expect(kz_datamgr, save_doc, fun(?DB, Written) ->
            ?assertEqual(?ID, kz_doc:id(Written)),
            ets:update_counter(T, save_calls, 1),
            ets:insert(T, {written, Written}),
            Current = ets:lookup_element(T, current, 2),
            case kz_doc:revision(Written) =:= kz_doc:revision(Current) of
                true ->
                    Saved = kz_doc:set_revision(Written, <<"3-saved">>),
                    ets:insert(T, {current, Saved}), {ok, Saved};
                false -> {error, conflict}
            end
        end),
        Dispatch = cowboy_router:compile([{'_', [{"/fixture", crossbar_soft_delete_http_handler, T}]}]),
        {ok, Pid} = cowboy:start_clear(Listener,
            #{socket_opts => [{ip, {127,0,0,1}}, {port, 0}], num_acceptors => 1,
              max_connections => 2, shutdown => 1000},
            #{env => #{dispatch => Dispatch}, protocols => [http],
              request_timeout => 3000, idle_timeout => 3000, inactivity_timeout => 3000}),
        put(soft_delete_http_listener, {Listener, Pid}),
        Port = ranch:get_port(Listener),
        ?assert(is_integer(Port) andalso Port > 0 andalso Port < 65536),
        #{table => T, listener => Listener, listener_pid => Pid, apps => Started, port => Port}
    catch Class:Reason:Stack ->
        try stop_owned_listener(get(soft_delete_http_listener))
        after
            unload_mocks(),
            try stop_apps(get(soft_delete_http_started))
            after
                erase(soft_delete_http_started), erase(soft_delete_http_listener),
                ets:delete(T)
            end
        end,
        erlang:raise(Class, Reason, Stack)
    end.

cleanup(#{table := T, listener := Listener, listener_pid := Pid, apps := Apps}) ->
    try stop_owned_listener({Listener, Pid})
    after
        unload_mocks(),
        try stop_apps(Apps)
        after
            ets:delete(T), erase(soft_delete_http_started), erase(soft_delete_http_listener)
        end
    end.

unload_mocks() ->
    lists:foreach(fun(M) -> catch meck:unload(M) end, [kz_process, kz_datamgr]).

stop_owned_listener(undefined) -> ok;
stop_owned_listener({Listener, Pid}) ->
    case bounded(fun() -> cowboy:stop_listener(Listener) end) of
        ok -> ok;
        Failure ->
            %% Only this fixture's recorded listener can be killed on timeout;
            %% fail the test rather than leave an apparently successful receipt.
            exit(Pid, kill), error({listener_cleanup_failed, Failure})
    end.

stop_apps(undefined) -> ok;
stop_apps(Apps) ->
    lists:foreach(fun(App) ->
        case bounded(fun() -> application:stop(App) end) of
            ok -> ok;
            {error, {not_started, App}} -> ok;
            Other -> error({application_cleanup_failed, App, Other})
        end
    end, lists:reverse(Apps)).

bounded(Fun) ->
    {Pid, Ref} = spawn_monitor(fun() -> exit({fixture_result, Fun()}) end),
    receive
        {'DOWN', Ref, process, Pid, {fixture_result, Result}} -> Result;
        {'DOWN', Ref, process, Pid, Reason} -> {error, Reason}
    after 5000 ->
        exit(Pid, kill),
        receive {'DOWN', Ref, process, Pid, _} -> ok after 1000 -> ok end,
        timeout
    end.

doc() -> kz_json:from_list([{<<"_id">>, ?ID}, {<<"_rev">>, ?R1},
    {<<"pvt_type">>, <<"account">>}, {<<"pvt_account_id">>, ?A},
    {<<"pvt_account_db">>, ?DB}, {<<"pvt_created">>, 100},
    {<<"fixture_marker">>, <<"validated-body">>}]).

run_case(#{table := T, port := Port}, Header, Race, Expected, Deletes) ->
    Ref = make_ref(), Doc = doc(),
    ets:insert(T, [{owner, self()}, {request_ref, Ref}, {current, Doc}, {race, Race},
                  {db, ?DB}, {delete_calls, 0}, {save_calls, 0}, {lookup_calls, 0},
                  {written, undefined}, {validated_revision, undefined}, {delete_status, undefined}]),
    ?assertEqual(Expected, request(Port, Header)),
    %% A malformed header exits the Cowboy request process without calling the
    %% REST terminate callback. Observe the actual process death before reuse.
    RequestPid = ets:lookup_element(T, request_pid, 2),
    Monitor = erlang:monitor(process, RequestPid),
    receive {'DOWN', Monitor, process, RequestPid, _} -> ok
    after 3000 -> erlang:demonitor(Monitor, [flush]), error(request_process_still_alive)
    end,
    case Expected of
        400 -> ok;
        _ -> receive {soft_delete_http_done, Ref} -> ok after 3000 -> error(handler_did_not_terminate) end
    end,
    ?assertEqual(Deletes, ets:lookup_element(T, delete_calls, 2)),
    ?assertEqual(Deletes, ets:lookup_element(T, save_calls, 2)),
    ?assertEqual(0, ets:lookup_element(T, lookup_calls, 2)),
    Current = ets:lookup_element(T, current, 2),
    case {Expected, Race} of
        {409, true} ->
            ?assertEqual(?R1, ets:lookup_element(T, validated_revision, 2)),
            ?assertEqual(<<"2-concurrent">>, kz_doc:revision(Current)),
            ?assertEqual(<<"concurrent-body">>, kz_json:get_value(<<"fixture_marker">>, Current)),
            ?assertNot(kz_doc:is_soft_deleted(Current));
        {204, false} ->
            ?assert(kz_doc:is_soft_deleted(Current)),
            ?assertEqual(<<"validated-body">>, kz_json:get_value(<<"fixture_marker">>, Current));
        _ -> ?assertEqual(Doc, Current)
    end,
    case Deletes of
        0 -> ?assertEqual(undefined, ets:lookup_element(T, written, 2));
        1 -> ?assertEqual(?R1, kz_doc:revision(ets:lookup_element(T, written, 2)))
    end.

request(Port, Header) ->
    {ok, Socket} = gen_tcp:connect({127,0,0,1}, Port,
        [binary, {active, false}, {packet, raw}, {send_timeout, 3000}, {send_timeout_close, true}], 3000),
    try
        Headers = case Header of undefined -> []; _ -> [<<"If-Match: ">>, Header, <<"\r\n">>] end,
        ok = gen_tcp:send(Socket, [<<"DELETE /fixture HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n">>, Headers, <<"\r\n">>]),
        Response = read_response(Socket, erlang:monotonic_time(millisecond) + 3000, <<>>),
        [Line | _] = binary:split(Response, <<"\r\n">>, [global]),
        <<"HTTP/1.1 ", Code:3/binary, " ", _/binary>> = Line,
        ?assertNotEqual(nomatch, binary:match(Response, <<"\r\n\r\n">>)),
        binary_to_integer(Code)
    after gen_tcp:close(Socket)
    end.

read_response(Socket, Deadline, Acc) ->
    Remaining = Deadline - erlang:monotonic_time(millisecond),
    ?assert(Remaining > 0),
    case gen_tcp:recv(Socket, 0, Remaining) of
        {ok, Bytes} when byte_size(Acc) + byte_size(Bytes) =< 16384 ->
            read_response(Socket, Deadline, <<Acc/binary, Bytes/binary>>);
        {ok, _} -> error(http_response_too_large);
        {error, closed} -> Acc;
        {error, Reason} -> error({http_receive_failed, Reason})
    end.
