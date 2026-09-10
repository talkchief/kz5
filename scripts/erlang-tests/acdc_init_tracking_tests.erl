%% Real initializer owner/worker processes with controlled datastore/supervisor
%% dependencies. This does not simulate broker drain or real call acceptance.
-module(acdc_init_tracking_tests).
-include_lib("eunit/include/eunit.hrl").
-define(MOCKS, [kz_datamgr,kz_json,kz_doc,kzs_util,kapps_maintenance,acdc_stats,acdc_agent_util,acdc_agents_sup,acdc_queues_sup]).

initialization_tracking_test_() ->
    [{Name, {timeout, 10, {setup, fun setup/0, fun cleanup/1, fun(_) -> Test end}}}
     || {Name,Test} <- [{"empty successful inventory is ready",fun empty/0}
                      ,{"child agent initialization blocks readiness",fun delayed_agent/0}
                      ,{"scheduled account retry remains pending",fun delayed_retry/0}
                      ,{"account discovery failure is retried, never empty-ready",fun discovery_retry/0}
                      ,{"fresh database setup is followed by verified discovery",fun fresh_database/0}
                      ,{"failed agent lookup is not ready",fun failed_agent/0}
                      ,{"failed supervisor creation is not ready",fun failed_start/0}
                      ,{"missing queue view is not empty-ready",fun missing_view/0}
                      ,{"new public initialization invalidates the token",fun new_job/0}
                      ,{"normal owner stop terminates its pending jobs",fun stop_owner/0}
                      ,{"abnormal owner death cannot leave retry jobs alive",fun kill_owner/0}]].

setup() ->
    [meck:new(M,[non_strict,no_link]) || M <- ?MOCKS],
    meck:expect(kz_datamgr,get_all_results,fun(_,_) -> {ok,[]} end),
    meck:expect(kz_datamgr,get_results,fun(_,_,_) -> {ok,[]} end),
    meck:expect(kz_datamgr,db_create,fun(_) -> true end),
    meck:expect(kapps_maintenance,refresh,fun(_) -> ok end),
    meck:expect(kz_json,get_value,fun(K,J) -> maps:get(K,J) end),
    meck:expect(kz_doc,id,fun(J) -> maps:get(id,J) end),
    meck:expect(kzs_util,format_account_db,fun(A) -> A end),
    meck:expect(kzs_util,format_account_id,fun(A) -> A end),
    meck:expect(acdc_stats,init_db,fun(_) -> ok end),
    meck:expect(acdc_agent_util,most_recent_status_strict,fun(_,_) -> {ok,ready} end),
    meck:expect(acdc_agent_util,status_should_auto_start,fun(_) -> true end),
    meck:expect(acdc_agents_sup,new,fun(_,_) -> {ok,self()} end),
    meck:expect(acdc_queues_sup,new,fun(_,_) -> {ok,self()} end),ok.
cleanup(_) ->
    case whereis(acdc_init) of undefined -> ok; Pid -> gen_server:stop(Pid,normal,2000) end,
    [meck:unload(M) || M <- ?MOCKS],ok.
start() -> {ok,Pid}=gen_server:start_link({local,acdc_init},acdc_init,[],[]),Pid.
ready() -> until(fun() -> case acdc_init:maintenance_state(500) of {ok,T}->{true,T};_->false end end).
failed() -> until(fun() -> case acdc_init:maintenance_state(500) of {error,initialization_failed}->{true,ok};_->false end end).
until(F) -> until(F,300).
until(_,0) -> error(observation_timeout);
until(F,N) -> case F() of {true,V}->V;false->timer:sleep(10),until(F,N-1) end.
account() -> meck:expect(kz_datamgr,get_all_results,fun(_,_) -> {ok,[#{<<"key">>=><<"account">>}]} end).
agents() ->
    account(),meck:expect(kz_datamgr,get_results,
        fun(_,<<"queues/agents_listing">>,_) -> {ok,[#{id=><<"agent">>}]};(_,_,_) -> {ok,[]} end).
blocked_agent() ->
    agents(),Parent=self(),
    meck:expect(acdc_agent_util,most_recent_status_strict,fun(_,_) ->
        Parent!{agent_job,self()},receive continue -> {ok,ready} end end),
    Owner=start(),Worker=receive {agent_job,P}->P after 2000->error(no_job) end,
    {Owner,Worker}.
empty() ->
    ?assertEqual(unavailable,acdc_init:startup_status()),
    Pid=start(),Token=ready(),?assertEqual(Pid,maps:get(initializer,Token)),?assertEqual(Token,ready()),
    ?assertEqual(ready,acdc_init:startup_status()).
delayed_agent() ->
    {_,Worker}=blocked_agent(),?assertEqual({error,initialization_pending},acdc_init:maintenance_state(500)),
    ?assertEqual(pending,acdc_init:startup_status()),
    Worker!continue,_=ready(),ok.
delayed_retry() ->
    account(),Parent=self(),Tab=ets:new(retry,[public]),ets:insert(Tab,{count,0}),
    meck:expect(kz_datamgr,get_results,fun(_,<<"queues/crossbar_listing">>,_) ->
        case ets:update_counter(Tab,count,1) of
            1 -> Parent!first_failure,{error,gateway_timeout};
            _ -> Parent!{retry_job,self()},receive continue -> {ok,[]} end
        end;(_,_,_)->{ok,[]} end),
    _=start(),receive first_failure->ok after 2000->error(no_failure) end,
    ?assertEqual({error,initialization_pending},acdc_init:maintenance_state(500)),
    Worker=receive {retry_job,P}->P after 2500->error(no_retry) end,
    ?assertEqual({error,initialization_pending},acdc_init:maintenance_state(500)),
    Worker!continue,_=ready(),ets:delete(Tab),ok.
discovery_retry() ->
    Parent=self(),Tab=ets:new(discovery,[public]),ets:insert(Tab,{count,0}),
    meck:expect(kz_datamgr,get_all_results,fun(_,_) ->
        case ets:update_counter(Tab,count,1) of 1->Parent!first_failure,{error,gateway_timeout};_->{ok,[]} end end),
    _=start(),receive first_failure->ok after 2000->error(no_failure) end,
    ?assertEqual({error,initialization_pending},acdc_init:maintenance_state(500)),
    _=ready(),?assert(ets:lookup_element(Tab,count,2)>=2),ets:delete(Tab),ok.
failed_agent() ->
    agents(),meck:expect(acdc_agent_util,most_recent_status_strict,fun(_,_) -> {error,timeout} end),_=start(),failed(),
    ?assertEqual(failed,acdc_init:startup_status()).
fresh_database() ->
    Parent=self(),Tab=ets:new(fresh,[public]),ets:insert(Tab,{count,0}),
    meck:expect(kz_datamgr,get_all_results,fun(_,_) ->
        case ets:update_counter(Tab,count,1) of 1->{error,not_found};_->{ok,[]} end end),
    meck:expect(kapps_maintenance,refresh,fun(_) -> Parent!refreshed,ok end),
    _=start(),receive refreshed->ok after 2000->error(no_refresh) end,
    ?assertEqual(pending,acdc_init:startup_status()),_=ready(),
    ?assert(ets:lookup_element(Tab,count,2)>=2),ets:delete(Tab),ok.
failed_start() ->
    agents(),meck:expect(acdc_agents_sup,new,fun(_,_) -> {error,already_present} end),_=start(),failed().
missing_view() ->
    account(),meck:expect(kz_datamgr,get_results,fun(_,_,_) -> {error,not_found} end),_=start(),failed().
new_job() ->
    _=start(),Before=ready(),ok=acdc_init:init_acct_queues(<<"account">>),After=ready(),
    ?assertEqual(maps:get(epoch,Before),maps:get(epoch,After)),
    ?assert(maps:get(revision,After)>maps:get(revision,Before)).
stop_owner() ->
    {Owner,Worker}=blocked_agent(),Ref=monitor(process,Worker),gen_server:stop(Owner,normal,2000),
    receive {'DOWN',Ref,process,Worker,shutdown}->ok after 2000->error(orphaned_job) end.
kill_owner() ->
    {Owner,Worker}=blocked_agent(),unlink(Owner),Ref=monitor(process,Worker),exit(Owner,kill),
    receive {'DOWN',Ref,process,Worker,killed}->ok after 2000->error(orphaned_job) end.
