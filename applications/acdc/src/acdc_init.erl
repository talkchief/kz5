%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2012-2020, 2600Hz
%%% @doc Iterate over each account, find configured queues and configured
%%% agents, and start the attendant processes
%%%
%%% @author James Aimonetti
%%% @author Daniel Finke
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(acdc_init).
-behaviour(gen_server).

-export([start_link/0
        ,init_db/0
        ,init_acdc/0
        ,init_acct/1
        ,init_acct_queues/1
        ,init_acct_agents/1
        ,maintenance_state/1
        ,startup_status/0
        ]).
-export([init/1,handle_call/3,handle_cast/2,handle_info/2,terminate/2,code_change/3]).

-include("acdc.hrl").

-record(state, {jobs = #{} :: map(), failed = 0 :: non_neg_integer()
               ,revision = 0 :: non_neg_integer(), epoch :: reference()}).

-spec start_link() -> kz_types:startlink_ret().
start_link() ->
    _ = declare_exchanges(),
    gen_server:start_link({'local', ?MODULE}, ?MODULE, [], []).

%% Ready means every initializer-owned job (including retries and previously
%% logged-in agents) has finished. It is not a broker/media admission fence.
-spec maintenance_state(timeout()) -> {'ok', map()} | {'error', atom()}.
maintenance_state(Timeout) -> gen_server:call(?MODULE, 'maintenance_state', Timeout).

-spec startup_status() -> 'ready' | 'pending' | 'failed' | 'unavailable'.
startup_status() ->
    case catch maintenance_state(2000) of
        {'ok', _} -> 'ready';
        {'error','initialization_pending'} -> 'pending';
        {'error','initialization_failed'} -> 'failed';
        _ -> 'unavailable'
    end.

-spec init([]) -> {'ok', #state{}}.
init([]) ->
    process_flag('trap_exit', 'true'),
    {_, State} = start_job(fun init_acdc/0, 'none', #state{epoch=make_ref()}),
    {'ok', State}.

-spec handle_call(term(), {pid(), term()}, #state{}) -> {'reply', term(), #state{}}.
handle_call('maintenance_state', _, #state{jobs=Jobs,failed=0,epoch=Epoch,revision=Revision}=State)
  when map_size(Jobs) =:= 0 ->
    {'reply', {'ok', #{initializer=>self(),epoch=>Epoch,revision=>Revision}}, State};
handle_call('maintenance_state', _, #state{failed=Failed}=State) when Failed > 0 ->
    {'reply', {'error','initialization_failed'}, State};
handle_call('maintenance_state', _, State) ->
    {'reply', {'error','initialization_pending'}, State};
handle_call({'run', Fun, Recipient}, _, State) when is_function(Fun, 0) ->
    {Pid, Next} = start_job(Fun, Recipient, State),
    {'reply', Pid, Next};
handle_call(_, _, State) -> {'reply', {'error','unsupported'}, State}.
-spec handle_cast(term(), #state{}) -> {'noreply', #state{}}.
handle_cast(_, State) -> {'noreply', State}.
-spec handle_info(term(), #state{}) -> {'noreply', #state{}}.
handle_info({'DOWN', Ref, 'process', Pid, Reason}, #state{jobs=Jobs,failed=Failed,revision=Revision}=State) ->
    case maps:find(Ref, Jobs) of
        {'ok', Pid} ->
            Error = case Reason of 'normal' -> 0; _ -> 1 end,
            {'noreply', State#state{jobs=maps:remove(Ref, Jobs),failed=Failed+Error,revision=Revision+1}};
        _ -> {'noreply', State}
    end;
handle_info(_, State) -> {'noreply', State}.
-spec terminate(term(), #state{}) -> 'ok'.
terminate(_, #state{jobs=Jobs}) ->
    %% No retry/agent initializer may outlive a normally stopped owner either.
    maps:foreach(fun(_, Pid) -> exit(Pid, 'shutdown') end, Jobs), 'ok'.
-spec code_change(term(), #state{}, term()) -> {'ok', #state{}}.
code_change(_, State, _) -> {'ok', State}.

start_job(Fun, Recipient, #state{jobs=Jobs,revision=Revision}=State) ->
    Owner = self(),
    {Pid, Ref} = spawn_opt(fun() ->
        put({?MODULE, 'owner'}, Owner),
        try
            %% Preserve Kazoo's application/logging context while obtaining
            %% the link and monitor atomically (no already-finished PID race).
            _ = kz_process:put_application('acdc'),
            _ = kz_log:put_callid(?MODULE),
            Fun()
        of
            Value -> job_reply(Recipient, {'ok', Value})
        catch _:_ ->
            job_reply(Recipient, {'error','initialization_failed'}),
            lager:error("acdc initialization job failed; maintenance readiness remains unavailable"),
            exit('acdc_initialization_failed')
        end
    end, ['link','monitor']),
    {Pid, State#state{jobs=maps:put(Ref, Pid, Jobs),revision=Revision+1}}.
job_reply('none', _) -> 'ok';
job_reply({Pid, Tag}, Result) -> Pid ! {Tag, Result}, 'ok'.

tracked_spawn(Fun) -> gen_server:call(?MODULE, {'run', Fun, 'none'}).
tracked_call(Fun) ->
    case get({?MODULE, 'owner'}) of
        Owner when is_pid(Owner) ->
            %% Only the current owner can attest these side effects.
            Owner = whereis(?MODULE), Fun();
        _ ->
            Tag = make_ref(),
            Pid = gen_server:call(?MODULE, {'run', Fun, {self(), Tag}}),
            Ref = monitor('process', Pid),
            receive
                {Tag, {'ok', Value}} -> demonitor(Ref, ['flush']), Value;
                {Tag, {'error', Reason}} -> demonitor(Ref, ['flush']), error(Reason);
                {'DOWN', Ref, 'process', Pid, _} -> error('initialization_failed')
            end
    end.

-spec init_acdc() -> 'ok'.
init_acdc() ->
    tracked_call(fun init_acdc_tracked/0).
init_acdc_tracked() ->
    kz_log:put_callid(?MODULE),
    case kz_datamgr:get_all_results(?KZ_ACDC_DB, <<"acdc/accounts_listing">>) of
        {'ok', []} ->
            lager:debug("no accounts configured for acdc");
        {'ok', Accounts} ->
            _ = [init_acct(kz_json:get_value(<<"key">>, Account)) || Account <- Accounts],
            'ok';
        {'error', 'not_found'} ->
            lager:debug("acdc db not found, initializing"),
            _ = init_db(),
            lager:debug("consider running acdc_maintenance:migrate() to enable acdc for already-configured accounts"),
            retry_acdc();
        {'error', _E} ->
            lager:debug("failed to query acdc db: ~p", [_E]),
            retry_acdc()
    end.

retry_acdc() ->
    _ = tracked_spawn(fun() -> wait_a_bit(), init_acdc() end), 'ok'.

-spec init_db() -> any().
init_db() ->
    _ = kz_datamgr:db_create(?KZ_ACDC_DB),
    _ = kapps_maintenance:refresh(?KZ_ACDC_DB),
    'ok'.

-spec init_acct(kz_term:ne_binary()) -> 'ok'.
init_acct(Account) ->
    tracked_call(fun() -> init_acct_tracked(Account) end).
init_acct_tracked(Account) ->
    AccountDb = kzs_util:format_account_db(Account),
    AccountId = kzs_util:format_account_id(Account),

    lager:debug("init acdc account: ~s", [AccountId]),

    acdc_stats:init_db(AccountId),

    _ = init_acct_queues(AccountDb, AccountId),
    init_acct_agents(AccountDb, AccountId).

-spec init_acct_queues(kz_term:ne_binary()) -> 'ok'.
init_acct_queues(Account) ->
    tracked_call(fun() -> init_acct_queues_tracked(Account) end).
init_acct_queues_tracked(Account) ->
    AccountDb = kzs_util:format_account_db(Account),
    AccountId = kzs_util:format_account_id(Account),

    lager:debug("init acdc account queues: ~s", [AccountId]),
    init_acct_queues(AccountDb, AccountId).

-spec init_acct_agents(kz_term:ne_binary()) -> 'ok'.
init_acct_agents(Account) ->
    tracked_call(fun() -> init_acct_agents_tracked(Account) end).
init_acct_agents_tracked(Account) ->
    AccountDb = kzs_util:format_account_db(Account),
    AccountId = kzs_util:format_account_id(Account),

    lager:debug("init acdc account agents: ~s", [AccountId]),
    init_acct_agents(AccountDb, AccountId).

-spec init_acct_queues(kz_term:ne_binary(), kz_term:ne_binary()) -> 'ok'.
init_acct_queues(AccountDb, AccountId) ->
    init_queues(AccountId
               ,kz_datamgr:get_results(AccountDb, <<"queues/crossbar_listing">>, [])
               ).

-spec init_acct_agents(kz_term:ne_binary(), kz_term:ne_binary()) -> 'ok'.
init_acct_agents(AccountDb, AccountId) ->
    init_agents(AccountId
               ,kz_datamgr:get_results(AccountDb, <<"queues/agents_listing">>
                                      ,[{'reduce', 'false'}])
               ).

-spec init_queues(kz_term:ne_binary(), kazoo_data:get_results_return()) -> 'ok'.
init_queues(_, {'ok', []}) -> 'ok';
init_queues(AccountId, {'error', 'gateway_timeout'}) ->
    lager:debug("gateway timed out loading queues in account ~s, trying again in a moment", [AccountId]),
    try_queues_again(AccountId),
    wait_a_bit(),
    'ok';
init_queues(AccountId, {'error', 'not_found'}) ->
    lager:error("the queues view for ~s appears to be missing; you should probably fix that", [AccountId]),
    error('queue_view_not_found');
init_queues(AccountId, {'error', _E}) ->
    lager:debug("error fetching queues: ~p", [_E]),
    try_queues_again(AccountId),
    wait_a_bit(),
    'ok';
init_queues(AccountId, {'ok', Qs}) ->
    acdc_stats:init_db(AccountId),
    _ = [ensure_started(acdc_queues_sup:new(AccountId, kz_doc:id(Q))) || Q <- Qs],
    'ok'.

-spec init_agents(kz_term:ne_binary(), kazoo_data:get_results_return()) -> 'ok'.
init_agents(_, {'ok', []}) -> 'ok';
init_agents(AccountId, {'error', 'gateway_timeout'}) ->
    lager:debug("gateway timed out loading agents in account ~s, trying again in a moment", [AccountId]),
    try_agents_again(AccountId),
    wait_a_bit(),
    'ok';
init_agents(AccountId, {'error', 'not_found'}) ->
    lager:error("the agents view for ~s appears to be missing; you should probably fix that", [AccountId]),
    error('agent_view_not_found');
init_agents(AccountId, {'error', _E}) ->
    lager:debug("error fetching agents: ~p", [_E]),
    try_agents_again(AccountId),
    wait_a_bit(),
    'ok';
init_agents(AccountId, {'ok', As}) ->
    _ = [spawn_previously_logged_in_agent(AccountId, kz_doc:id(A)) || A <- As],
    'ok'.

wait_a_bit() -> timer:sleep(1000 + rand:uniform(500)).

try_queues_again(AccountId) ->
    try_again(AccountId, fun init_acct_queues/2).
try_agents_again(AccountId) ->
    try_again(AccountId, fun init_acct_agents/2).

try_again(AccountId, F) ->
    tracked_spawn(
      fun() ->
              wait_a_bit(),
              AccountDb = kzs_util:format_account_db(AccountId),
              F(AccountDb, AccountId)
      end).

-spec spawn_previously_logged_in_agent(kz_term:ne_binary(), kz_term:ne_binary()) -> any().
spawn_previously_logged_in_agent(AccountId, AgentId) ->
    tracked_spawn(
      fun() ->
              {'ok', Status} = acdc_agent_util:most_recent_status_strict(AccountId, AgentId),
              case acdc_agent_util:status_should_auto_start(Status) of
                  'false' -> lager:debug("agent ~s in ~s is ~s, not starting", [AgentId, AccountId, Status]);
                  'true' -> ensure_started(acdc_agents_sup:new(AccountId, AgentId))
              end
      end).

ensure_started({'ok', Pid}) when is_pid(Pid) -> 'ok';
ensure_started({'ok', Pid, _}) when is_pid(Pid) -> 'ok';
ensure_started({'error', {'already_started', Pid}}) when is_pid(Pid) -> 'ok';
ensure_started(_) -> error('worker_start_failed').

-spec declare_exchanges() -> 'ok'.
declare_exchanges() ->
    _ = kapi_acdc_agent:declare_exchanges(),
    _ = kapi_acdc_queue:declare_exchanges(),
    _ = kapi_acdc_stats:declare_exchanges(),
    _ = kapi_call:declare_exchanges(),
    _ = kapi_conf:declare_exchanges(),
    _ = kapi_dialplan:declare_exchanges(),
    _ = kapi_notifications:declare_exchanges(),
    _ = kapi_resource:declare_exchanges(),
    _ = kapi_route:declare_exchanges(),
    _ = kapi_presence:declare_exchanges(),
    kapi_self:declare_exchanges().
