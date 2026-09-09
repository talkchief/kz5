#!/usr/bin/env escript
%%! +S 1:1 +SDcpu 1 +SDio 1 +A 1 -setcookie unused_fixture_probe -start_epmd false -kernel logger_level none
%% Dev44-only fault injection. No production code loading or raw state output.
-mode(compile).
-compile(warnings_as_errors).
-include_lib("kernel/include/file.hrl").
-define(ACCOUNT, <<"8310dc3170a18de37f205d0da172df65">>).
-define(QUEUE, <<"67c5f3fb115bdd1dd574d6a604a7d29f">>).

main(["--self-test"]) ->
    Self = self(), Ticket = <<"acdc-callback-fixture">>, Call = <<"fixture-call">>,
    M = #{owner => Self, account_id => ?ACCOUNT, queue_id => ?QUEUE,
          callback_id => Ticket, caller_call_id => Call, stage => originating,
          executed => true, answered => false, destroyed => false},
    ok = target(M, Self, Ticket, Call),
    lists:foreach(fun({Key, Value}) ->
        refused = try target(M#{Key => Value}, Self, Ticket, Call), accepted catch _:_ -> refused end
    end, [{owner, undefined}, {account_id, <<"other">>}, {queue_id, <<"other">>},
          {callback_id, <<"other">>}, {caller_call_id, <<"other">>},
          {stage, confirming}, {executed, false}, {answered, true}, {destroyed, true}]),
    io:put_chars("PASS exact worker target and nine refusals; no cookie or connection\n");
main(["--kill-fixture-worker", Ticket0, Call0]) ->
    try
        true = os:getenv("USER") =:= "root",
        {ok, Ifs} = inet:getifaddrs(),
        true = lists:any(fun({_, Values}) -> lists:member({addr,{10,1,0,44}}, Values) end, Ifs),
        Ticket = list_to_binary(Ticket0), Call = list_to_binary(Call0),
        match = re:run(Ticket, <<"^acdc-callback-[a-f0-9]{64}$">>, [{capture,none}]),
        match = re:run(Call, <<"^[A-Za-z0-9@._:-]{1,128}$">>, [{capture,none}]),
        CookiePath = "/etc/kazoo/.erlang.cookie",
        {ok,#file_info{type=regular,uid=0,links=1,mode=Mode,size=Size}} = file:read_link_info(CookiePath),
        true = (Mode band 8#077) =:= 0 andalso Size >= 16 andalso Size =< 256,
        {ok, Cookie0} = file:read_file(CookiePath), Cookie = string:trim(Cookie0),
        match = re:run(Cookie, <<"^[A-Za-z0-9_@.-]+$">>, [{capture,none}]),
        {ok, Host} = inet:gethostname(), Node = list_to_atom("kazoo_apps@" ++ Host),
        ok = application:set_env(kernel, inet_dist_use_interface, {127,0,0,1}),
        {ok,_} = net_kernel:start([list_to_atom("callback_loss_" ++ os:getpid() ++ "@" ++ Host), shortnames]),
        true = erlang:set_cookie(node(), binary_to_atom(Cookie, utf8)),
        lists:foreach(fun(M) -> record_layout(Node, M) end,
                      [acdc_queue_fsm, gen_listener, acdc_callback_caller]),
        Sup = rpc(Node, acdc_queues_sup, find_queue_supervisor, [?ACCOUNT, ?QUEUE]),
        true = is_pid(Sup),
        WorkersSup = rpc(Node, acdc_queue_sup, workers_sup, [Sup]),
        Workers = rpc(Node, acdc_queue_workers_sup, workers, [WorkersSup]),
        true = is_list(Workers) andalso length(Workers) =< 100,
        Matches = lists:filtermap(fun(WorkerSup) ->
            Fsm = rpc(Node, acdc_queue_worker_sup, fsm, [WorkerSup]),
            case coordinator(Node, Fsm, Ticket, Call) of
                {ok, Worker} -> {true, {Fsm, Worker}};
                no -> false
            end
        end, Workers),
        [{Fsm, Worker}] = Matches,
        true = node(Worker) =:= Node andalso node(Fsm) =:= Node,
        Listener = record_map(gen_listener, rpc(Node, sys, get_state, [Worker, 2000])),
        acdc_callback_caller = maps:get(module, Listener),
        State = record_map(acdc_callback_caller, maps:get(module_state, Listener)),
        ok = target(State, Fsm, Ticket, Call),
        {ok, Worker} = coordinator(Node, Fsm, Ticket, Call),
        Ref = erlang:monitor(process, Worker),
        true = rpc(Node, erlang, exit, [Worker, kill]),
        receive {'DOWN',Ref,process,Worker,killed} -> ok after 3000 -> error(no_death_proof) end,
        io:format("{\"worker_loss\":true,\"callback_id\":\"~s\",\"caller_call_id\":\"~s\",\"epoch_ms\":~B}~n",
                  [Ticket, Call, erlang:system_time(millisecond)]),
        net_kernel:stop()
    catch _:_ -> io:put_chars("ERROR scoped worker loss refused or unverified; do not repeat blindly\n"), halt(1)
    end;
main(_) -> io:put_chars("Use --self-test or --kill-fixture-worker CALLBACK_ID CALL_ID\n"), halt(2).

rpc(Node, M, F, Args) -> rpc:call(Node, M, F, Args, 3000).

record_layout(Node, M) ->
    Path = rpc(Node, code, which, [M]),
    Md5 = rpc(Node, M, module_info, [md5]),
    {ok,{M,Md5}} = rpc(Node, beam_lib, md5, [Path]),
    {ok,{M,[{abstract_code,{raw_abstract_v1,Forms}}]}} = rpc(Node, beam_lib, chunks, [Path,[abstract_code]]),
    [Fields] = [Fs || {attribute,_,record,{state,Fs}} <- Forms],
    put({layout,M}, [field_name(F) || F <- Fields]).
field_name({typed_record_field, F, _}) -> field_name(F);
field_name({record_field,_,{atom,_,Name}}) -> Name;
field_name({record_field,_,{atom,_,Name},_}) -> Name.
record_map(M, Record) ->
    [state|Values] = tuple_to_list(Record), Names = get({layout,M}),
    true = length(Values) =:= length(Names), maps:from_list(lists:zip(Names, Values)).

coordinator(Node, Fsm, Ticket, Call) ->
    case rpc(Node, sys, get_state, [Fsm,2000]) of
        {callback_waiting, Record} ->
            State = record_map(acdc_queue_fsm, Record),
            ?ACCOUNT = maps:get(account_id, State), ?QUEUE = maps:get(queue_id, State),
            Context = maps:get(callback_ctx, State),
            case Context of
                #{mode := dialing, worker := Worker, reservation := Doc} when is_pid(Worker) ->
                    case {rpc(Node,kz_doc,id,[Doc]), rpc(Node,kz_json,get_value,[<<"pvt_caller_call_id">>,Doc])} of
                        {Ticket,Call} -> {ok,Worker}; _ -> no
                    end;
                _ -> no
            end;
        _ -> no
    end.
target(State, Owner, Ticket, Call) ->
    #{owner := Owner, account_id := ?ACCOUNT, queue_id := ?QUEUE,
      callback_id := Ticket, caller_call_id := Call, stage := originating,
      executed := true, answered := false, destroyed := false} = State,
    ok.
