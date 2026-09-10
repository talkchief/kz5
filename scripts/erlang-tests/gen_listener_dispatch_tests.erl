%% Production gen_listener callbacks in real OTP processes. Only AMQP transport
%% is replaced; responders, dispatch groups and monitor delivery are real.
-module(gen_listener_dispatch_tests).
-behaviour(gen_server).
-export([init/1,handle_call/3,handle_cast/2,handle_info/2,terminate/2,code_change/3]).
-include_lib("eunit/include/eunit.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

dispatch_test_() ->
    {foreach, fun setup/0, fun cleanup/1,
     [fun(_) -> {"ack precedes blocking synchronous-dispatch responder", fun() -> busy(false,delivery) end} end,
      fun(_) -> {"ack precedes blocking asynchronous-dispatch responder", fun() -> busy(true,delivery) end} end,
      fun(_) -> {"federated synchronous dispatch tracked", fun() -> busy(false,federated) end} end,
      fun(_) -> {"federated asynchronous child group tracked", fun() -> busy(true,federated) end} end,
      fun(_) -> {"all synchronous responders must complete", fun() -> siblings(false) end} end,
      fun(_) -> {"all asynchronous responders must complete", fun() -> siblings(true) end} end,
      fun(_) -> {"failed synchronous responder remains visible", fun() -> failure(false) end} end,
      fun(_) -> {"failed asynchronous responder remains visible", fun() -> failure(true) end} end,
      fun(_) -> {"separate dispatch groups do not inherit earlier monitors", fun independent/0} end,
      fun(_) -> {"killed dispatcher cannot hide its surviving responder", fun killed_dispatcher/0} end,
      fun(_) -> {"unmatched asynchronous event completes cleanly", fun unmatched/0} end,
      fun(_) -> {"foreign DOWN still reaches callback", fun foreign_down/0} end]}.

setup() ->
    meck:new(kz_amqp_channel,[passthrough,no_link]),
    meck:expect(kz_amqp_channel,consumer_channel,fun() -> self() end),
    meck:new(kz_amqp_util,[passthrough,no_link]),
    ok.
cleanup(_) -> meck:unload(kz_amqp_util),meck:unload(kz_amqp_channel).

start(Async,Count) ->
    Parent=self(),
    meck:expect(kz_amqp_util,basic_ack,fun(BD) -> Parent ! {ack,BD#'basic.deliver'.delivery_tag},ok end),
    Callback=fun(_J,_P) ->
                     Ref=monitor(process,Parent),Parent ! {responder,self()},
                     receive
                         finish -> demonitor(Ref,[flush]),ok;
                         fail -> exit(probe_failed);
                         {'DOWN',Ref,process,Parent,_} -> exit(test_owner_down)
                     end
             end,
    Responders=lists:duplicate(Count,{{<<"probe">>,<<"work">>},{Callback,2}}),
    {ok,Pid}=gen_server:start(?MODULE,{Async,Responders,Parent},[]),Pid.
stop(Pid) -> gen_server:stop(Pid).
event(Pid,delivery) ->
    Pid ! {#'basic.deliver'{delivery_tag=42},#amqp_msg{props=#'P_basic'{content_type = <<"application/erlang">>},payload=term_to_binary(job())}};
event(Pid,federated) ->
    gen_server:cast(Pid,{federated_event,job(),[{deliver,#'basic.deliver'{}},{basic,#'P_basic'{}}]}).
job() -> kz_json:from_list([{<<"Event-Category">>,<<"probe">>},{<<"Event-Name">>,<<"work">>}]).
responder() -> receive {responder,Pid} -> Pid after 2000 -> error(no_responder) end.
status(Pid) -> gen_server:call(Pid,maintenance_dispatch_state).
pending(Pid) -> maps:get(pending_dispatches,status(Pid)).
settle(Pid) -> settle(Pid,erlang:monotonic_time(millisecond)+2000).
settle(Pid,Deadline) ->
    case pending(Pid) of
        0 -> status(Pid);
        _ -> true=erlang:monotonic_time(millisecond)<Deadline,receive after 5 -> settle(Pid,Deadline) end
    end.
busy(Async,Path) ->
    P=start(Async,1),
    try
        event(P,Path),R=responder(),
        case Path of delivery -> receive {ack,42} -> ok after 2000 -> error(not_acknowledged) end; _ -> ok end,
        ?assert(pending(P)>0),?assertEqual(false,maps:get(complete_cluster_drain_proven,status(P))),
        ?assertEqual(false,maps:get(admission_fence_proven,status(P))),
        R ! finish,?assertEqual(0,maps:get(failed_dispatches,settle(P)))
    after stop(P) end.
siblings(Async) ->
    P=start(Async,2),
    try
        event(P,delivery),A=responder(),B=responder(),A ! finish,
        %% Confirm A really terminated before querying the remaining group.
        Ref=monitor(process,A),receive {'DOWN',Ref,process,A,_}->ok after 2000->error(still_alive) end,
        ?assert(pending(P)>0),B ! finish,?assertEqual(0,maps:get(failed_dispatches,settle(P)))
    after stop(P) end.
failure(Async) ->
    P=start(Async,2),
    try
        event(P,delivery),A=responder(),B=responder(),A ! fail,
        Ref=monitor(process,A),receive {'DOWN',Ref,process,A,_}->ok after 2000->error(still_alive) end,
        ?assert(pending(P)>0),B ! finish,?assert(maps:get(failed_dispatches,settle(P))>0)
    after stop(P) end.
independent() ->
    P=start(true,1),
    try
        event(P,delivery),A=responder(),event(P,delivery),B=responder(),?assertEqual(2,pending(P)),
        B ! finish,await_pending(P,1,200),A ! finish,?assertEqual(0,maps:get(failed_dispatches,settle(P)))
    after stop(P) end.
await_pending(_P,_N,0) -> error(dispatch_group_not_completed);
await_pending(P,N,Left) -> case pending(P) of N->ok; _->receive after 5->await_pending(P,N,Left-1) end end.
unmatched() ->
    P=start(true,0),try event(P,delivery),?assertEqual(0,maps:get(failed_dispatches,settle(P))) after stop(P) end.
killed_dispatcher() ->
    P=start(true,1),
    try
        event(P,delivery),R=responder(),
        {monitored_by,[Group]}=process_info(R,monitored_by),?assertNotEqual(P,Group),
        exit(Group,kill),?assert(maps:get(failed_dispatches,settle(P))>0),
        ?assert(is_process_alive(R)),R ! finish
    after stop(P) end.
foreign_down() ->
    P=start(false,0),Ref=make_ref(),Msg={'DOWN',Ref,process,self(),normal},
    try P ! Msg,receive {callback_info,Msg}->ok after 2000->error(down_lost) end,?assertEqual(0,pending(P)) after stop(P) end.

init({Async,Responders,Parent}) ->
    {ok,state(#{self=>self(),consumer_key=>self(),module=>?MODULE,module_state=>Parent,
                queue=><<"synthetic-probe">>,responders=>Responders,
                auto_ack=>true,params=>[{spawn_handle_event,Async}]})}.
handle_call(_Msg,_From,Parent) when is_pid(Parent) -> {reply,{error,unsupported},Parent};
handle_call(Msg,From,S) -> gen_listener:handle_call(Msg,From,S).
handle_cast(Msg,S) -> gen_listener:handle_cast(Msg,S).
handle_info(Msg,Parent) when is_pid(Parent) -> Parent ! {callback_info,Msg},{noreply,Parent};
handle_info(Msg,S) -> gen_listener:handle_info(Msg,S).
terminate(_,_) -> ok.
code_change(_,S,_) -> {ok,S}.

state(Values) ->
    {ok,{gen_listener,[{abstract_code,{raw_abstract_v1,Forms}}]}}=beam_lib:chunks(code:which(gen_listener),[abstract_code]),
    [Fields]=[Fs || {attribute,_,record,{state,Fs}}<-Forms],
    Defaults=[field(F)||F<-Fields],
    true=lists:all(fun(K)->lists:keymember(K,1,Defaults) end,maps:keys(Values)),
    list_to_tuple([state|[maps:get(K,Values,V)||{K,V}<-Defaults]]).
field({typed_record_field,F,_}) -> field(F);
field({record_field,_,{atom,_,Name}}) -> {Name,undefined};
field({record_field,_,{atom,_,Name},_}) when Name=:=self;Name=:=consumer_key -> {Name,self()};
field({record_field,_,{atom,_,Name},Default}) -> {Name,erl_parse:normalise(Default)}.
