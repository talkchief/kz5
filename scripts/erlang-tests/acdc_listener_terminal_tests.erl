%% Production callbacks; only external event/broker I/O is mocked.
-module(acdc_listener_terminal_tests).
-include_lib("eunit/include/eunit.hrl").

terminal_test_() ->
    {foreach, fun setup/0, fun cleanup/1,
     [fun pending_destroy/0, fun late_control/0, fun known_control/0,
      fun unknown_destroy/0, fun duplicate_destroy/0, fun handler_delivery/0,
      fun answered_control/0, fun wrapup_control/0]}.
setup() ->
    meck:new(acdc_util,[passthrough,no_link]),
    meck:new(gen_listener,[passthrough,no_link]),
    meck:new(kapi_dialplan,[passthrough,no_link]),
    meck:expect(acdc_util,unbind_from_call_events,fun(_) -> ok end),
    meck:expect(acdc_util,unbind_from_call_events,fun(_,_) -> ok end),
    meck:expect(gen_listener,cast,fun(_,_) -> ok end),
    meck:expect(kapi_dialplan,publish_command,fun(_,_) -> error(unexpected_hangup) end),
    ok.
cleanup(_) ->
    [meck:unload(M) || M <- [acdc_util,gen_listener,kapi_dialplan]],
    flush().
flush() -> receive _ -> flush() after 0 -> ok end.
state(Extra) -> acdc_listener_maintenance_tests:state(Extra).
cast(E,S) -> case acdc_agent_listener:handle_cast(E,S) of
                {noreply,N} -> N; {noreply,N,hibernate} -> N
            end.
drained(S) ->
    {reply,{ok,_},S}=acdc_agent_listener:handle_call(maintenance_state,none,S),ok.

pending_destroy() ->
    S=state(#{agent_call_ids=>[{<<"ended">>,undefined}]}),
    drained(cast({channel_destroyed,<<"ended">>},S)).
late_control() ->
    S=state(#{}),
    ?assertEqual(S,cast({originate_uuid,<<"ended">>,<<"late-control">>},S)),
    drained(S).
known_control() ->
    S=state(#{agent_call_ids=>[{<<"live">>,undefined}]}),
    After=cast({originate_uuid,<<"live">>,<<"control">>},S),
    Expected=state(#{agent_call_ids=>[{<<"live">>,<<"control">>}]}),
    ?assertEqual(Expected,After).
unknown_destroy() ->
    S=state(#{agent_call_ids=>[{<<"live">>,undefined},<<"passive">>]}),
    ?assertEqual(S,cast({channel_destroyed,<<"foreign">>},S)).
duplicate_destroy() ->
    S=state(#{agent_call_ids=>[{<<"ended">>,undefined},<<"ended">>,<<"other">>]}),
    N=cast({channel_destroyed,<<"ended">>},S),
    ?assertEqual(state(#{agent_call_ids=>[<<"other">>]}),N),
    ?assertEqual(N,cast({channel_destroyed,<<"ended">>},N)).
handler_delivery() ->
    E=kz_json:from_list([{<<"Call-ID">>,<<"ended">>},
        {<<"Msg-ID">>,<<"fixture-event">>},{<<"Call-Direction">>,<<"outbound">>},
        {<<"Event-Category">>,<<"call_event">>},{<<"Event-Name">>,<<"CHANNEL_DESTROY">>}
        | kz_api:default_headers(<<"fixture">>,<<"1">>)]),
    ?assert(kapi_call:event_v(E)),
    acdc_agent_handler:handle_call_event(E,[{fsm_pid,self()},{server,self()},{cdr_urls,dict:new()}]),
    ?assertEqual(1,meck:num_calls(gen_listener,cast,[self(),{channel_destroyed,<<"ended">>}])),
    ?assertEqual(1,meck:num_calls(acdc_util,unbind_from_call_events,[<<"ended">>,self()])).
answered_control() -> forwarded(answered).
wrapup_control() -> forwarded(wrapup).
forwarded(Name) ->
    {ok,{acdc_agent_fsm,[{abstract_code,{raw_abstract_v1,Forms}}]}}=
        beam_lib:chunks(code:which(acdc_agent_fsm),[abstract_code]),
    [Fields]=[Fs || {attribute,_,record,{state,Fs}}<-Forms],
    Defaults=[field(F)||F<-Fields],
    S=list_to_tuple([state|[case K of agent_listener->self();_->V end||{K,V}<-Defaults]]),
    ?assertEqual({next_state,Name,S},apply(acdc_agent_fsm,Name,[cast,{originate_uuid,<<"leg">>,<<"control">>},S])),
    ?assertEqual(1,meck:num_calls(gen_listener,cast,[self(),{originate_uuid,<<"leg">>,<<"control">>}])).
field({typed_record_field,F,_}) -> field(F);
field({record_field,_,{atom,_,K}}) -> {K,undefined};
field({record_field,_,{atom,_,K},V}) -> {K,erl_parse:normalise(V)}.
