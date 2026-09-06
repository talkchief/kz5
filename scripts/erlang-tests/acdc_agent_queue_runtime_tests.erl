%%% SPDX-License-Identifier: MPL-2.0
%%% Real request handlers/protocol; all DB, AMQP and process control are doubles.
-module(acdc_agent_queue_runtime_tests).
-compile({no_auto_import,[get/1,put/2]}).
-include_lib("eunit/include/eunit.hrl").
-define(A, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(U, <<"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb">>).
-define(Q, <<"cccccccccccccccccccccccccccccccc">>).
-define(R, <<"dddddddddddddddddddddddddddddddd">>).

j(P) -> kz_json:from_list(P).
doc(Id, Type, Extra) -> j([{<<"_id">>, Id}, {<<"pvt_type">>, Type}, {<<"pvt_account_id">>, ?A} | Extra]).
user(Queues) -> doc(?U, <<"user">>, [{<<"queues">>, Queues}, {<<"enabled">>, true}]).
queue() -> doc(?Q, <<"queue">>, []).
get(Key) -> [{_, Value}] = ets:lookup(queue_runtime_test, Key), Value.
put(Key, Value) -> ets:insert(queue_runtime_test, {Key, Value}), ok.
request() -> j([{<<"runtime_only">>, true}, {<<"action">>, <<"login">>}, {<<"queue_id">>, ?Q}]).
context(Verb) -> cb_context:setters(cb_context:new(), [
    {fun cb_context:set_account_id/2, ?A}, {fun cb_context:set_auth_account_id/2, ?A},
    {fun cb_context:set_api_version/2, <<"v2">>}, {fun cb_context:set_req_verb/2, Verb},
    {fun cb_context:set_req_nouns/2, [{<<"agents">>, [?U, <<"queue_status">>]}, {<<"accounts">>, [?A]}]},
    {fun cb_context:set_db_name/2, <<"account/runtime-fixture">>},
    {fun cb_context:set_req_data/2, request()}, {fun cb_context:set_doc/2, get(user)},
    {fun cb_context:set_resp_status/2, success}]).
data(Context) -> cb_context:resp_data(Context).
reply(Req, Queues, Status) -> j([{<<"Account-ID">>, ?A}, {<<"Agent-ID">>, ?U}
    ,{<<"Msg-ID">>, props:get_value(<<"Msg-ID">>, Req)}, {<<"Queues">>, Queues}, {<<"Status">>, Status}
    ,{<<"Event-Category">>, <<"agent">>}, {<<"Event-Name">>, <<"sync_resp">>}
    | kz_api:default_headers(<<"acdc">>, <<"test">>)]).

runtime_test_() -> {setup, fun setup/0, fun cleanup/1, fun(_) ->
    [{Name,fun()->reset(),F() end} || {Name,F} <-
      [{"explicit request and enrollment",fun explicit_request_and_enrollment/0},
       {"pending receipt without roster writes",fun post_pending_without_roster_write/0},
       {"POST revalidates enrollment",fun post_revalidates_membership/0},
       {"publish failure is not accepted",fun publish_failure_is_not_accepted/0},
       {"fresh runtime confirmation",fun fresh_runtime_confirmation/0},
       {"malformed legacy foreign stale snapshots",fun malformed_old_foreign_and_stale_snapshots/0},
       {"legacy and runtime route dispatch",fun legacy_get_and_runtime_dispatch/0},
       {"consumer revalidates enrollment",fun runtime_consumer_rechecks_membership/0},
       {"new agent starts only selected queue",fun new_agent_only_selected_queue/0},
       {"existing agent preserved",fun existing_agent_preserved/0},
       {"concurrent login reuses winning supervisor",fun concurrent_start_preserves_selected_queue/0},
       {"actual listener snapshot wire payload",fun actual_listener_queues_in_sync_reply/0}]] end}.

setup() ->
    T = ets:new(queue_runtime_test, [named_table, public]),
    lists:foreach(fun(M) -> ok = meck:new(M, [no_link]) end,
        [kz_datamgr, crossbar_doc, kz_amqp_worker, acdc_agents_sup, acdc_agent_sup,
         acdc_agent_fsm, acdc_agent_stats, kz_log, kz_amqp_util, gen_listener]),
    reset(),
    meck:expect(kz_log, put_callid, fun(_) -> ok end),
    meck:expect(kz_log, kz_log_md_put, fun(_,_) -> ok end),
    meck:expect(kz_datamgr, open_doc, fun(_, Id) ->
        case Id of ?U -> {ok, get(user)}; ?Q -> {ok, get(queue)}; _ -> {error, not_found} end end),
    meck:expect(crossbar_doc, load, fun(?U, C, _) -> cb_context:set_doc(C, get(user)) end),
    meck:expect(acdc_agents_sup, find_agent_supervisor, fun(?A, ?U) -> get(runtime) end),
    meck:expect(acdc_agents_sup, new, fun(D) -> put(started, [D | get(started)]), {ok, self()} end),
    meck:expect(acdc_agent_sup, fsm, fun(P) when is_pid(P) -> P end),
    meck:expect(acdc_agent_sup, listener, fun(P) when is_pid(P) -> P end),
    meck:expect(gen_listener, cast, fun(_,_) -> ok end),
    meck:expect(acdc_agent_fsm, update_presence, fun(_, _, _) -> ok end),
    meck:expect(acdc_agent_fsm, add_acdc_queue, fun(P, Q) -> put(added, [{P,Q} | get(added)]) end),
    meck:expect(acdc_agent_stats, agent_logged_in, fun(?A, ?U) -> ok end),
    meck:expect(acdc_agent_stats, agent_logged_out, fun(A,U) -> put(logged_out, [{A,U} | get(logged_out)]) end),
    T.
reset() ->
    put(user, user([?Q, ?R])), put(queue, queue()), put(published, []), put(runtime, undefined),
    put(started, []), put(added, []), put(logged_out, []), put(query_count, 0),
    meck:expect(kz_amqp_worker, cast, fun(P, F) ->
        ?assertEqual({module, kapi_acdc_agent}, erlang:fun_info(F, module)),
        ?assertEqual({name, publish_login_queue}, erlang:fun_info(F, name)),
        put(published, [P | get(published)]), ok end),
    meck:expect(kz_amqp_worker, call, fun(Req, Pub, Validator, 2000) ->
        ?assertEqual({name, publish_sync_req}, erlang:fun_info(Pub, name)),
        put(query_count, get(query_count) + 1),
        Resp = reply(Req, [?Q, ?R], <<"ready">>), ?assert(Validator(Resp)), {ok, Resp} end).
cleanup(T) ->
    lists:foreach(fun(M) -> meck:unload(M) end,
        [kz_datamgr, crossbar_doc, kz_amqp_worker, acdc_agents_sup, acdc_agent_sup,
         acdc_agent_fsm, acdc_agent_stats, kz_log, kz_amqp_util, gen_listener]), ets:delete(T).

explicit_request_and_enrollment() ->
    C = context(<<"POST">>), ?assertEqual(success, cb_context:resp_status(cb_acdc_agent_queue:validate(?U,C))),
    lists:foreach(fun(Pair) ->
        Bad = cb_context:set_req_data(C, kz_json:set_value(element(1,Pair), element(2,Pair), request())),
        ?assertEqual(400, cb_context:resp_error_code(cb_acdc_agent_queue:validate(?U,Bad)))
    end, [{<<"runtime_only">>, false}, {<<"runtime_only">>, <<"true">>}, {<<"runtime_only">>, null},
          {<<"action">>, <<"logout">>}, {<<"action">>, null}, {<<"queue_id">>, <<>>}, {<<"queue_id">>, 3}]),
    lists:foreach(fun(D) ->
        Bad = cb_context:set_doc(C,D),
        ?assertEqual(403, cb_context:resp_error_code(cb_acdc_agent_queue:validate(?U,Bad)))
    end, [user([?R]), kz_json:set_value(<<"enabled">>,false,get(user)),
          kz_json:set_value(<<"pvt_account_id">>,?R,get(user)), kz_json:set_value(<<"pvt_deleted">>,true,get(user))]),
    put(queue, doc(?Q, <<"user">>, [])),
    ?assertEqual(404, cb_context:resp_error_code(cb_acdc_agent_queue:validate(?U,C))),
    ?assertEqual([],get(published)).

post_pending_without_roster_write() ->
    Before = get(user), C = cb_agents:post(context(<<"POST">>),?U,<<"queue_status">>),
    ?assertEqual(202, cb_context:resp_error_code(C)),
    ?assertEqual(<<"pending">>,kz_json:get_value(<<"state">>,data(C))),
    ?assertEqual(false,kz_json:get_value(<<"confirmed">>,data(C))),
    ?assertEqual(?A,kz_json:get_value(<<"account_id">>,data(C))),
    ?assertEqual(Before,get(user)),
    [P] = get(published), ?assertEqual(?Q,props:get_value(<<"Queue-ID">>,P)),
    ?assertEqual(?U,props:get_value(<<"Agent-ID">>,P)),
    ?assertEqual(true,props:get_value(<<"Runtime-Only">>,P)),
    ?assertNot(meck:called(crossbar_doc,save,'_')),
    ?assertNot(meck:called(kz_datamgr,save_doc,'_')).

post_revalidates_membership() ->
    C = context(<<"POST">>), put(user,user([?R])),
    ?assertEqual(403,cb_context:resp_error_code(cb_acdc_agent_queue:post(?U,C))),
    ?assertEqual([],get(published)).

publish_failure_is_not_accepted() ->
    meck:expect(kz_amqp_worker,cast,fun(_,_) -> {error, unavailable} end),
    ?assertEqual(503,cb_context:resp_error_code(cb_acdc_agent_queue:post(?U,context(<<"POST">>)))).

fresh_runtime_confirmation() ->
    C = cb_agents:validate(context(<<"GET">>),?U,<<"queue_status">>), D=data(C),
    ?assertEqual(true,kz_json:get_value(<<"confirmed">>,D)),
    ?assertEqual(true,kz_json:get_value(<<"runtime_observed">>,D)),
    ?assertEqual(true,kz_json:get_value(<<"runtime_member">>,D)),
    ?assertEqual(<<"confirmed">>,kz_json:get_value(<<"state">>,D)),
    ?assertEqual(<<"ready">>,kz_json:get_value(<<"agent_status">>,D)),
    ?assertEqual(<<"no-store">>,maps:get(<<"cache-control">>,cb_context:resp_headers(C))),
    meck:expect(kz_amqp_worker,call,fun(Req,_,_,2000) -> {ok,reply(Req,[?Q],<<"paused">>)} end),
    Paused=data(cb_acdc_agent_queue:read(?U,context(<<"GET">>))),
    ?assertEqual(true,kz_json:get_value(<<"confirmed">>,Paused)),
    ?assertEqual(<<"paused">>,kz_json:get_value(<<"agent_status">>,Paused)),
    ?assertEqual([],get(published)).

malformed_old_foreign_and_stale_snapshots() ->
    Mutations=[fun(R)->kz_json:delete_key(<<"Queues">>,R) end,
        fun(R)->kz_json:set_value(<<"Queues">>,[?Q,?Q],R) end,
        fun(R)->kz_json:set_value(<<"Queues">>,[?Q,1],R) end,
        fun(R)->kz_json:set_value(<<"Queues">>,?Q,R) end,
        fun(R)->kz_json:set_value(<<"Queues">>,[integer_to_binary(N)||N<-lists:seq(1,1025)],R) end,
        fun(R)->kz_json:set_value(<<"Account-ID">>,?R,R) end,
        fun(R)->kz_json:set_value(<<"Agent-ID">>,?R,R) end,
        fun(R)->kz_json:set_value(<<"Msg-ID">>,<<"old-request">>,R) end,
        fun(R)->kz_json:set_value(<<"Status">>,<<"bogus">>,R) end],
    lists:foreach(fun(Mutate)->
        meck:expect(kz_amqp_worker,call,fun(Req,_,V,2000)->
            Bad=Mutate(reply(Req,[?Q],<<"ready">>)),?assertNot(V(Bad)),{ok,Bad} end),
        D=data(cb_acdc_agent_queue:read(?U,context(<<"GET">>))),
        ?assertEqual(false,kz_json:get_value(<<"confirmed">>,D)),
        ?assertEqual(false,kz_json:get_value(<<"runtime_observed">>,D))
    end,Mutations),
    meck:expect(kz_amqp_worker,call,fun(_,_,_,2000)->{error,timeout} end),
    ?assertEqual(false,kz_json:get_value(<<"confirmed">>,data(cb_acdc_agent_queue:read(?U,context(<<"GET">>))))),
    meck:expect(kz_amqp_worker,call,fun(Req,_,_,2000)->{ok,reply(Req,[?R],<<"ready">>)} end),
    NotMember=data(cb_acdc_agent_queue:read(?U,context(<<"GET">>))),
    ?assertEqual(true,kz_json:get_value(<<"runtime_observed">>,NotMember)),
    ?assertEqual(false,kz_json:get_value(<<"confirmed">>,NotMember)).

legacy_get_and_runtime_dispatch() ->
    C=cb_context:set_req_data(context(<<"GET">>),kz_json:new()),
    ?assertNot(cb_acdc_agent_queue:requested(C)),
    ?assertEqual([?Q,?R],data(cb_agents:validate(C,?U,<<"queue_status">>))),
    ?assertEqual(0,get(query_count)),
    Qs=j([{<<"runtime_only">>,<<"true">>},{<<"queue_id">>,?Q},{<<"action">>,<<"login">>}]),
    C1=cb_context:set_query_string(C,Qs),
    ?assertEqual(true,kz_json:get_value(<<"confirmed">>,data(cb_agents:validate(C1,?U,<<"queue_status">>)))).

login_event() ->
    P=[{<<"Account-ID">>,?A},{<<"Agent-ID">>,?U},{<<"Queue-ID">>,?Q},{<<"Runtime-Only">>,true}
       ,{<<"Event-Category">>,<<"agent">>},{<<"Event-Name">>,<<"login_queue">>}
       |kz_api:default_headers(<<"crossbar">>,<<"test">>)],
    meck:expect(kz_amqp_util,kapps_publish,fun(_,Json,_)->put(login_payload,kz_json:decode(Json)),ok end),
    ok=kapi_acdc_agent:publish_login_queue(P), Event=get(login_payload),
    ?assertEqual(true,kz_json:get_value(<<"Runtime-Only">>,Event)),Event.

runtime_consumer_rechecks_membership() ->
    lists:foreach(fun(User)->
        put(user,User), acdc_agent_handler:handle_status_update(login_event(),[]),
        ?assertEqual([],get(started)),?assertEqual([],get(added)),?assertEqual([],get(logged_out))
    end,[user([?R]),kz_json:set_value(<<"enabled">>,false,user([?Q])),
          kz_json:set_value(<<"pvt_account_id">>,?R,user([?Q])),
          kz_json:set_value(<<"pvt_deleted">>,true,user([?Q]))]),
    put(user,user([?Q])),put(queue,kz_json:set_value(<<"pvt_deleted">>,true,queue())),
    acdc_agent_handler:handle_status_update(login_event(),[]),
    ?assertEqual([],get(added)),?assertEqual([],get(logged_out)).

new_agent_only_selected_queue() ->
    Before=get(user),acdc_agent_handler:handle_status_update(login_event(),[]),
    [Started]=get(started),?assertEqual([?Q],kz_json:get_value(<<"queues">>,Started)),
    ?assertEqual(Before,get(user)),?assertEqual(1,length(get(added))),
    ?assertNot(meck:called(kz_datamgr,save_doc,'_')).

existing_agent_preserved() ->
    put(runtime,self()),acdc_agent_handler:handle_status_update(login_event(),[]),
    ?assertEqual([],get(started)),?assertEqual([{self(),?Q}],get(added)),
    ?assertEqual([],get(logged_out)),
    ?assertNot(meck:called(acdc_agent_fsm,rm_acdc_queue,'_')),
    ?assertNot(meck:called(acdc_agent_fsm,agent_logout,'_')).

concurrent_start_preserves_selected_queue() ->
    meck:expect(acdc_agents_sup,new,fun(_)->{error,{already_started,self()}} end),
    acdc_agent_handler:handle_status_update(login_event(),[]),
    ?assertEqual([{self(),?Q}],get(added)),
    ?assertEqual([],get(logged_out)),
    ?assertNot(meck:called(acdc_agent_fsm,rm_acdc_queue,'_')),
    ?assertNot(meck:called(acdc_agent_fsm,agent_logout,'_')).

actual_listener_queues_in_sync_reply() ->
    meck:expect(kz_amqp_util,targeted_publish,fun(_Q,Json,_ContentType)->put(sync_payload,kz_json:decode(Json)),ok end),
    {ok,S}=acdc_agent_listener:init([self(),get(user),[?Q,?R]]),
    Req=j([{<<"Server-ID">>,<<"reply-queue">>},{<<"Msg-ID">>,<<"fresh-correlation">>}]),
    {noreply,S}=acdc_agent_listener:handle_cast({send_sync_resp,ready,Req,[]},S),
    Resp=get(sync_payload),?assertEqual([?Q,?R],kz_json:get_value(<<"Queues">>,Resp)),
    ?assertEqual(<<"fresh-correlation">>,kz_api:msg_id(Resp)),
    ?assertEqual(?A,kz_json:get_value(<<"Account-ID">>,Resp)),
    ?assertEqual(?U,kz_json:get_value(<<"Agent-ID">>,Resp)).
