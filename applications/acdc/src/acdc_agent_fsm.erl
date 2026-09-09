%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2012-2020, 2600Hz
%%% @doc Tracks the agent's state, responds to messages from the corresponding
%%% acdc_agent gen_listener process.
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
-module(acdc_agent_fsm).

-behaviour(gen_statem).

%% API
-export([start_link/3, start_link/4, start_link/5
        ,call_event/4
        ,member_connect_req/2
        ,member_connect_win/3
        ,member_connect_satisfied/2
        ,agent_timeout/2
        ,shared_failure/2
        ,shared_call_id/2
        ,originate_ready/2
        ,originate_resp/2, originate_started/2, originate_uuid/2
        ,originate_failed/2
        ,sync_req/2, sync_resp/2
        ,pause/2
        ,resume/1
        ,end_wrapup/1

        ,add_acdc_queue/2, rm_acdc_queue/2
        ,send_availability_update/2
        ,update_presence/3
        ,agent_logout/1
        ,refresh/2
        ,current_call/1
        ,status/1
        ,dashboard_state/2
        ,maintenance_state/2
        ,maintenance_restore/3

        ,new_endpoint/2
        ,edited_endpoint/2
        ,deleted_endpoint/2
        ]).

-export([wait_for_listener/4]).

%% gen_statem callbacks
-export([init/1
        ,callback_mode/0
        ,terminate/3
        ,code_change/4
        ]).

%% Agent states
-export([wait/3
        ,sync/3
        ,ready/3
        ,ringing/3
        ,answered/3
        ,wrapup/3
        ,paused/3
        ,outbound/3
        ]).

-ifdef(TEST).
-export([changed_endpoints/2, strategy_test_state/1, strategy_test_field/2]).
-endif.

-include("acdc.hrl").

-define(SERVER, ?MODULE).

%% When an agent starts up, how long do we wait for other agents to respond with their status?
-define(SYNC_RESPONSE_TIMEOUT, 5000).
-define(SYNC_RESPONSE_MESSAGE, 'sync_response_timeout').

%% We weren't able to join our brethren, how long to wait to check again
-define(RESYNC_RESPONSE_TIMEOUT, 15000).
-define(RESYNC_RESPONSE_MESSAGE, 'resync_response_timeout').

-define(PAUSE_MESSAGE, 'pause_expired').

-define(WRAPUP_FINISHED, 'wrapup_finished').

-define(CALL_CHECK_INTERVAL, 30000).
-define(CALL_CHECK_MESSAGE, 'check_agent_calls').

-define(MAX_CONNECT_FAILURES, <<"max_connect_failures">>).
-define(MAX_FAILURES, kapps_config:get_integer(?CONFIG_CAT, ?MAX_CONNECT_FAILURES, 3)).

-define(NOTIFY_PICKUP, <<"pickup">>).
-define(NOTIFY_HANGUP, <<"hangup">>).
-define(NOTIFY_CDR, <<"cdr">>).
-define(NOTIFY_RECORDING, <<"recording">>).
-define(NOTIFY_ALL, <<"all">>).

-define(RESOURCE_TYPE_AUDIO, <<"audio">>).

-record(state, {account_id :: kz_term:ne_binary()
               ,account_db :: kz_term:ne_binary()
               ,agent_id :: kz_term:ne_binary()
               ,agent_listener :: kz_types:server_ref()
               ,agent_listener_id :: kz_term:api_ne_binary()
               ,agent_name :: kz_term:api_binary()

               ,wrapup_timeout = 0 :: integer() % optionally set on win
               ,wrapup_ref :: kz_term:api_reference()

               ,sync_ref :: kz_term:api_reference()
               ,pause_ref :: kz_term:api_reference() | 'infinity'

               ,member_call :: kapps_call:call() | 'undefined'
               ,member_call_id :: kz_term:api_binary()
               ,member_call_queue_id :: kz_term:api_binary()
               ,member_call_start :: kz_time:start_time() | 'undefined'
               ,queue_notifications :: kz_term:api_object()

               ,agent_call_id :: kz_term:api_binary()
               ,next_status :: kz_term:api_binary()
               ,statem_call_id :: kz_term:api_binary() % used when no call-ids are available
               ,endpoints = [] :: kz_json:objects()
               ,outbound_call_ids = [] :: kz_term:ne_binaries()
               ,max_connect_failures :: timeout()
               ,connect_failures = 0 :: non_neg_integer()
               ,agent_state_updates = [] :: list()
               ,monitoring = 'false' :: boolean() % process is not handling call, but following state transitions
               ,member_connect_id :: kz_term:api_binary()
               ,call_check_ref :: kz_term:api_reference()
               ,call_check :: 'undefined' | {reference(), pid(), reference(), tuple()}
               }).
-type state() :: #state{}.

-ifdef(TEST).
-spec strategy_test_state(kz_term:proplist()) -> state().
strategy_test_state(Values) ->
    Default = #state{},
    Fields = lists:zip(record_info(fields, state), lists:seq(2, record_info(size, state))),
    list_to_tuple(['state' | [props:get_value(Name, Values, element(Index, Default)) || {Name, Index} <- Fields]]).

-spec strategy_test_field(atom(), state()) -> any().
strategy_test_field(Name, State) ->
    Fields = lists:zip(record_info(fields, state), lists:seq(2, record_info(size, state))),
    element(props:get_value(Name, Fields), State).
-endif.

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc When a queue receives a call and needs an agent, it will send a
%% `member_connect_req'. The agent will respond (if possible) with a
%% `member_connect_resp' payload or ignore the request
%% @end
%%------------------------------------------------------------------------------
-spec member_connect_req(pid(), kz_json:object()) -> 'ok'.
member_connect_req(ServerRef, JObj) ->
    gen_statem:cast(ServerRef, {'member_connect_req', JObj}).

%%------------------------------------------------------------------------------
%% @doc When an agent has been selected to handle the queue call, each process
%% for the agent will receive a `member_connect_win' event. The event will
%% include a flag of whether the winner is on the current node - if true, the
%% agent process will handle call control. Otherwise, the agent process will
%% just follow along through state transitions.
%% @end
%%------------------------------------------------------------------------------
-type member_connect_win_node() :: 'same_node' | 'different_node'.
-spec member_connect_win(pid(), kz_json:object(), member_connect_win_node()) -> 'ok'.
member_connect_win(ServerRef, JObj, Node) ->
    gen_statem:cast(ServerRef, {'member_connect_win', JObj, Node}).

-spec member_connect_satisfied(pid(), kz_json:object()) -> 'ok'.
member_connect_satisfied(ServerRef, JObj) ->
    gen_statem:cast(ServerRef, {'member_connect_satisfied', JObj}).

-spec agent_timeout(pid(), kz_json:object()) -> 'ok'.
agent_timeout(ServerRef, JObj) ->
    gen_statem:cast(ServerRef, {'agent_timeout', JObj}).

-spec shared_failure(pid(), kz_json:object()) -> 'ok'.
shared_failure(ServerRef, JObj) ->
    gen_statem:cast(ServerRef, {'shared_failure', JObj}).

-spec shared_call_id(pid(), kz_json:object()) -> 'ok'.
shared_call_id(ServerRef, JObj) ->
    gen_statem:cast(ServerRef, {'shared_call_id', JObj}).

%%------------------------------------------------------------------------------
%% @doc When an agent is involved in a call, it will receive call events.
%% Pass the call event to the `statem' to see if action is needed (usually
%% for bridge and hangup events).
%% @end
%%------------------------------------------------------------------------------
-spec call_event(pid(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> 'ok'.
call_event(ServerRef, <<"call_event">>, <<"CHANNEL_BRIDGE">>, JObj) ->
    gen_statem:cast(ServerRef, {'channel_bridge_event', JObj});
call_event(ServerRef, <<"call_event">>, <<"CHANNEL_UNBRIDGE">>, JObj) ->
    gen_statem:cast(ServerRef, {'channel_unbridged', call_id(JObj)});
call_event(ServerRef, <<"call_event">>, <<"usurp_control">>, JObj) ->
    gen_statem:cast(ServerRef, {'usurp_control', call_id(JObj)});
call_event(ServerRef, <<"call_event">>, <<"CHANNEL_DESTROY">>, JObj) ->
    ServerRef ! ?DESTROYED_CHANNEL(call_id(JObj), acdc_util:hangup_cause(JObj));
call_event(ServerRef, <<"call_event">>, <<"CHANNEL_DISCONNECTED">>, JObj) ->
    ServerRef ! ?DESTROYED_CHANNEL(call_id(JObj), <<"MEDIA_SERVER_UNREACHABLE">>);
call_event(ServerRef, <<"call_event">>, <<"LEG_CREATED">>, JObj) ->
    gen_statem:cast(ServerRef, {'leg_created', call_id(JObj)});
call_event(ServerRef, <<"call_event">>, <<"LEG_DESTROYED">>, JObj) ->
    gen_statem:cast(ServerRef, {'leg_destroyed', call_id(JObj)});
call_event(ServerRef, <<"call_event">>, <<"CHANNEL_ANSWER">>, JObj) ->
    gen_statem:cast(ServerRef, {'channel_answered', JObj});
call_event(ServerRef, <<"call_event">>, <<"CHANNEL_EXECUTE_COMPLETE">>, JObj) ->
    maybe_send_execute_complete(ServerRef, kz_json:get_value(<<"Application-Name">>, JObj), JObj);
call_event(ServerRef, <<"error">>, <<"dialplan">>, JObj) ->
    _ = kz_log:put_callid(JObj),
    lager:debug("error event: ~s", [kz_json:get_value(<<"Error-Message">>, JObj)]),

    Req = kz_json:get_value(<<"Request">>, JObj),

    gen_statem:cast(ServerRef, {'dialplan_error', kz_json:get_value(<<"Application-Name">>, Req)});
call_event(ServerRef, <<"call_event">>, <<"CHANNEL_REPLACED">>, JObj) ->
    gen_statem:cast(ServerRef, {'channel_replaced', JObj});
call_event(ServerRef, <<"call_event">>, <<"CHANNEL_TRANSFEREE">>, JObj) ->
    Transferor = kz_call_event:other_leg_call_id(JObj),
    Transferee = kz_call_event:call_id(JObj),
    gen_statem:cast(ServerRef, {'channel_transferee', Transferor, Transferee});
call_event(_, <<"call_event">>, <<"DTMF">>, _) -> 'ok';
call_event(_, _C, _E, _) ->
    lager:info("unhandled combo: ~s/~s", [_C, _E]).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec maybe_send_execute_complete(pid(), kz_term:ne_binary(), kz_json:object()) -> 'ok'.
maybe_send_execute_complete(ServerRef, <<"bridge">>, JObj) ->
    lager:info("send EXECUTE_COMPLETE,bridge to ~p with ci: ~s, olci: ~s",
               [ServerRef
               ,call_id(JObj)
               ,kz_call_event:other_leg_call_id(JObj)
               ]),
    gen_statem:cast(ServerRef, {'channel_unbridged', call_id(JObj)});
maybe_send_execute_complete(ServerRef, <<"call_pickup">>, JObj) ->
    gen_statem:cast(ServerRef, {'channel_bridged', call_id(JObj)});
maybe_send_execute_complete(_, _, _) -> 'ok'.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec originate_ready(kz_types:server_ref(), kz_json:object()) -> 'ok'.
originate_ready(ServerRef, JObj) ->
    gen_statem:cast(ServerRef, {'originate_ready', JObj}).

-spec originate_resp(kz_types:server_ref(), kz_json:object()) -> 'ok'.
originate_resp(ServerRef, JObj) ->
    gen_statem:cast(ServerRef, {'originate_resp', JObj}).

-spec originate_started(kz_types:server_ref(), kz_json:object()) -> 'ok'.
originate_started(ServerRef, JObj) ->
    gen_statem:cast(ServerRef, {'originate_started', JObj}).

-spec originate_uuid(kz_types:server_ref(), kz_json:object()) -> 'ok'.
originate_uuid(ServerRef, JObj) ->
    gen_statem:cast(ServerRef, {'originate_uuid'
                               ,kz_json:get_value(<<"Outbound-Call-ID">>, JObj)
                               ,kz_json:get_value(<<"Outbound-Call-Control-Queue">>, JObj)
                               }).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec originate_failed(kz_types:server_ref(), kz_json:object()) -> 'ok'.
originate_failed(ServerRef, JObj) ->
    gen_statem:cast(ServerRef, {'originate_failed', JObj}).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec sync_req(kz_types:server_ref(), kz_json:object()) -> 'ok'.
sync_req(ServerRef, JObj) ->
    gen_statem:cast(ServerRef, {'sync_req', JObj}).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec sync_resp(kz_types:server_ref(), kz_json:object()) -> 'ok'.
sync_resp(ServerRef, JObj) ->
    gen_statem:cast(ServerRef, {'sync_resp', JObj}).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec pause(kz_types:server_ref(), timeout()) -> 'ok'.
pause(ServerRef, Timeout) ->
    gen_statem:cast(ServerRef, {'pause', Timeout}).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec resume(kz_types:server_ref()) -> 'ok'.
resume(ServerRef) ->
    gen_statem:cast(ServerRef, {'resume'}).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec end_wrapup(kz_types:server_ref()) -> 'ok'.
end_wrapup(ServerRef) ->
    gen_statem:cast(ServerRef, {'end_wrapup'}).

%%------------------------------------------------------------------------------
%% @doc Request the agent listener bind to queue and conditionally send an
%% availability update depending on agent state
%% @end
%%------------------------------------------------------------------------------
-spec add_acdc_queue(kz_types:server_ref(), kz_term:ne_binary()) -> 'ok'.
add_acdc_queue(ServerRef, QueueId) ->
    gen_statem:cast(ServerRef, {'add_acdc_queue', QueueId}).

%%------------------------------------------------------------------------------
%% @doc Request the agent listener unbind from queue and send an
%% unavailability update
%% @end
%%------------------------------------------------------------------------------
-spec rm_acdc_queue(kz_types:server_ref(), kz_term:ne_binary()) -> 'ok'.
rm_acdc_queue(ServerRef, QueueId) ->
    gen_statem:cast(ServerRef, {'rm_acdc_queue', QueueId}).

%%------------------------------------------------------------------------------
%% @doc Send an availability update
%% @end
%%------------------------------------------------------------------------------
-spec send_availability_update(kz_types:server_ref(), kz_term:ne_binary()) -> 'ok'.
send_availability_update(ServerRef, QueueId) ->
    gen_statem:cast(ServerRef, {'send_availability_update', QueueId}).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec update_presence(kz_types:server_ref(), kz_term:ne_binary(), kz_term:ne_binary()) -> 'ok'.
update_presence(ServerRef, PresenceId, PresenceState) ->
    gen_statem:cast(ServerRef, {'update_presence', PresenceId, PresenceState}).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec agent_logout(kz_types:server_ref()) -> 'ok'.
agent_logout(ServerRef) ->
    gen_statem:cast(ServerRef, {'agent_logout'}).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec refresh(pid(), kz_json:object()) -> 'ok'.
refresh(ServerRef, AgentJObj) -> gen_statem:cast(ServerRef, {'refresh', AgentJObj}).

-spec current_call(pid()) -> kz_term:api_object().
current_call(ServerRef) -> gen_statem:call(ServerRef, 'current_call').

-spec status(pid()) -> kz_term:proplist().
status(ServerRef) -> gen_statem:call(ServerRef, 'status').

%% Closed, constant-size runtime observation; unlike status/1 it never copies
%% call identifiers, caller data, endpoints, timers or queued state updates.
-spec dashboard_state(pid(), pos_integer()) -> {binary(), binary(), atom(), pid() | undefined}.
dashboard_state(ServerRef, Timeout) -> gen_statem:call(ServerRef, 'dashboard_state', Timeout).

%% Native maintenance observation only: NOT an admission fence or permission
%% to restart. Read membership separately from the listener, under a cluster
%% fence, and require both identities/observations to remain stable.
-spec maintenance_state(pid(), pos_integer()) -> {'ok', map()} | {'error', atom()}.
maintenance_state(ServerRef, Timeout) -> gen_statem:call(ServerRef, 'maintenance_state', Timeout).

%% Internal planned-maintenance primitive. The coordinator MUST keep cluster
%% admission fenced and own the current checkpoint generation until after
%% verification. This is not a public API or authorization to replay old state.
-spec maintenance_restore(pid(), map(), pos_integer()) -> {'ok', map()} | {'error', atom()}.
maintenance_restore(ServerRef, Checkpoint, Timeout) ->
    gen_statem:call(ServerRef, {'maintenance_restore', Checkpoint}, Timeout).

maintenance_restore_reply(From, Checkpoint, StateName, State) ->
    case maintenance_snapshot(StateName, State) of
        {'error', _}=Error -> {'keep_state', State, [{'reply', From, Error}]};
        {'ok', #{account_id := AccountId, agent_id := AgentId}} ->
            case maintenance_restore_plan(Checkpoint, AccountId, AgentId) of
                {'error', _}=Error -> {'keep_state', State, [{'reply', From, Error}]};
                {'ok', Target, PauseRef} ->
                    %% Allocate/validate the new timer before cancelling the
                    %% old one. Neither an invalid checkpoint nor a rejected
                    %% timer can remove an existing pause.
                    maybe_stop_timer(State#state.pause_ref),
                    NewState = State#state{pause_ref=PauseRef},
                    Queued = maintenance_restore_notify(Target, NewState),
                    {'next_state', Target, NewState,
                     [{'reply', From, {'ok', #{state => Target, notifications_queued => Queued}}}]}
            end
    end.

maintenance_restore_plan(#{account_id := AccountId, agent_id := AgentId,
                           state := 'ready'}=Checkpoint, AccountId, AgentId)
  when map_size(Checkpoint) =:= 3 -> {'ok', 'ready', 'undefined'};
maintenance_restore_plan(#{account_id := AccountId, agent_id := AgentId,
                           state := 'paused', pause_until_unix_ms := 'infinity'}=Checkpoint,
                         AccountId, AgentId)
  when map_size(Checkpoint) =:= 4 -> {'ok', 'paused', 'infinity'};
maintenance_restore_plan(#{account_id := AccountId, agent_id := AgentId,
                           state := 'paused', pause_until_unix_ms := Deadline}=Checkpoint,
                         AccountId, AgentId)
  when map_size(Checkpoint) =:= 4, is_integer(Deadline), Deadline > 0 ->
    case Deadline - erlang:system_time('millisecond') of
        Left when Left =< 0 -> {'ok', 'ready', 'undefined'};
        Left ->
            try erlang:start_timer(Left, self(), ?PAUSE_MESSAGE) of
                Ref -> {'ok', 'paused', Ref}
            catch error:badarg -> {'error', 'invalid_pause_deadline'} end
    end;
maintenance_restore_plan(_, _, _) -> {'error', 'invalid_agent_checkpoint'}.

maintenance_restore_notify(Target, #state{account_id=AccountId, agent_id=AgentId
                                          ,agent_listener=Listener, pause_ref=PauseRef}) ->
    %% Notifications are asynchronous, as with normal pause/resume. A delivery
    %% failure must not crash the FSM or discard the restored local pause.
    %% The coordinator must verify consumers/availability before unfencing.
    try
        acdc_agent_listener:presence_update(Listener,
            case Target of 'ready' -> ?PRESENCE_GREEN; 'paused' -> ?PRESENCE_RED_FLASH end),
        acdc_agent_listener:send_availability_update(Listener, Target),
        case Target of
            'ready' -> acdc_agent_stats:agent_ready(AccountId, AgentId);
            'paused' -> acdc_agent_stats:agent_paused(AccountId, AgentId, time_left(PauseRef))
        end,
        'true'
    catch _:_ -> 'false' end.

maintenance_reply(From, StateName, State) ->
    {'keep_state', State, [{'reply', From, maintenance_snapshot(StateName, State)}]}.

maintenance_snapshot(StateName, #state{account_id=AccountId, agent_id=AgentId
                                      ,agent_listener=Listener
                                      ,member_call='undefined', member_call_id='undefined'
                                      ,member_call_queue_id='undefined', member_call_start='undefined'
                                      ,agent_call_id='undefined', outbound_call_ids=[]
                                      ,member_connect_id='undefined', monitoring='false'
                                      ,agent_state_updates=[], call_check='undefined'
                                      ,sync_ref='undefined', wrapup_ref='undefined'
                                      ,pause_ref=PauseRef})
  when (StateName =:= 'ready' orelse StateName =:= 'paused'),
       is_binary(AccountId), byte_size(AccountId) > 0,
       is_binary(AgentId), byte_size(AgentId) > 0, is_pid(Listener) ->
    case maintenance_pause(StateName, PauseRef) of
        {'ok', Pause} ->
            {'ok', Pause#{account_id => AccountId, agent_id => AgentId
                         ,listener => Listener, state => StateName}};
        Error -> Error
    end;
maintenance_snapshot(_, _) -> {'error', 'agent_not_drained'}.

maintenance_pause('ready', 'undefined') -> {'ok', #{pause_remaining_ms => 0}};
maintenance_pause('paused', 'infinity') -> {'ok', #{pause_remaining_ms => 'infinity'}};
maintenance_pause('paused', Ref) when is_reference(Ref) ->
    %% Sample wall time first so this cannot extend a finite pause. Expired
    %% timers are pending transitions, not permission to restore an agent as
    %% ready. Retry observation after the FSM processes its timer message.
    Now = erlang:system_time('millisecond'),
    case erlang:read_timer(Ref) of
        Left when is_integer(Left), Left > 0 ->
            {'ok', #{pause_remaining_ms => Left, pause_until_unix_ms => Now + Left}};
        _ -> {'error', 'agent_pause_transition_pending'}
    end;
maintenance_pause(_, _) -> {'error', 'agent_pause_state_inconsistent'}.

-spec dashboard_reply(gen_statem:from(), atom(), state()) -> kz_types:handle_fsm_ret(state()).
dashboard_reply(From, StateName, #state{account_id=AccountId,agent_id=AgentId,agent_listener=Listener}=State) ->
    {'next_state',StateName,State,{'reply',From,{AccountId,AgentId,StateName,Listener}}}.

%%------------------------------------------------------------------------------
%% @doc Creates a gen_statem process which calls Module:init/1 to
%% initialize. To ensure a synchronized start-up procedure, this
%% function does not return until Module:init/1 has returned.
%% @end
%%------------------------------------------------------------------------------
-spec start_link(pid(), kapps_call:call(), kz_term:ne_binary()) -> kz_types:startlink_ret().
start_link(Supervisor, ThiefCall, _QueueId) ->
    pvt_start_link(kapps_call:account_id(ThiefCall)
                  ,kapps_call:owner_id(ThiefCall)
                  ,Supervisor
                  ,[]
                  ,'true'
                  ).

-spec start_link(pid(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> kz_types:startlink_ret().
start_link(Supervisor, AccountId, AgentId, AgentJObj) ->
    start_link(Supervisor, AccountId, AgentId, AgentJObj, []).

-spec start_link(pid(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object(), kz_term:ne_binaries()) -> kz_types:startlink_ret().
start_link(Supervisor, AccountId, AgentId, _AgentJObj, _Queues) ->
    pvt_start_link(AccountId, AgentId, Supervisor, [], 'false').

pvt_start_link(AccountId, AgentId, Supervisor, Props, IsThief) ->
    gen_statem:start_link(?SERVER, [AccountId, AgentId, Supervisor, Props, IsThief], []).

-spec new_endpoint(pid(), kz_json:object()) -> 'ok'.
new_endpoint(ServerRef, EP) ->
    lager:debug("sending EP to ~p: ~p", [ServerRef, EP]).

-spec edited_endpoint(pid(), kz_json:object()) -> 'ok'.
edited_endpoint(ServerRef, EP) ->
    lager:debug("sending EP to ~p: ~p", [ServerRef, EP]),
    gen_statem:cast(ServerRef, {'edited_endpoint', kz_doc:id(EP), EP}).

-spec deleted_endpoint(pid(), kz_json:object()) -> 'ok'.
deleted_endpoint(ServerRef, EP) ->
    lager:debug("sending EP to ~p: ~p", [ServerRef, EP]).

%%%=============================================================================
%%% gen_statem callbacks
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Whenever a gen_statem is started using
%% gen_statem:start_link/[3,4], this function is called by the new
%% process to initialize.
%%
%% @end
%%------------------------------------------------------------------------------
-spec init(list()) -> {'ok', atom(), state()}.
init([AccountId, AgentId, Supervisor, Props, IsThief]) ->
    StateMCallId = <<"statem_", AccountId/binary, "_", AgentId/binary>>,
    kz_log:put_callid(StateMCallId),
    lager:debug("started acdc agent statem"),

    _P = kz_process:spawn(fun wait_for_listener/4, [Supervisor, self(), Props, IsThief]),
    lager:debug("waiting for listener in ~p", [_P]),

    {'ok'
    ,'wait'
    ,#state{account_id = AccountId
           ,account_db = kzs_util:format_account_db(AccountId)
           ,agent_id = AgentId
           ,statem_call_id = StateMCallId
           ,max_connect_failures = max_failures(AccountId)
           ,call_check_ref = start_call_check_timer()
           }
    }.

-spec max_failures(kz_term:ne_binary() | kz_json:object()) -> non_neg_integer().
max_failures(Account) when is_binary(Account) ->
    case kzd_accounts:fetch(Account) of
        {'ok', AccountJObj} -> max_failures(AccountJObj);
        {'error', _} -> ?MAX_FAILURES
    end;
max_failures(JObj) ->
    kz_json:get_integer_value(?MAX_CONNECT_FAILURES, JObj, ?MAX_FAILURES).

-spec wait_for_listener(pid(), pid(), kz_term:proplist(), boolean()) -> 'ok'.
wait_for_listener(Supervisor, ServerRef, Props, IsThief) ->
    case acdc_agent_sup:listener(Supervisor) of
        'undefined' ->
            lager:debug("listener not ready yet, waiting"),
            timer:sleep(100),
            wait_for_listener(Supervisor, ServerRef, Props, IsThief);
        P when is_pid(P) ->
            lager:debug("listener retrieved: ~p", [P]),

            {NextState, SyncRef} =
                case props:get_value('skip_sync', Props) =:= 'true'
                    orelse IsThief
                of
                    'true' -> {'ready', 'undefined'};
                    _ ->
                        gen_statem:cast(ServerRef, 'send_sync_event'),
                        gen_statem:cast(ServerRef, 'load_endpoints'),
                        {'sync', start_sync_timer(ServerRef)}
                end,

            gen_statem:cast(ServerRef, {'listener', P, NextState, SyncRef})
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec callback_mode() -> 'state_functions'.
callback_mode() ->
    'state_functions'.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec wait(gen_statem:event_type(), any(), state()) -> kz_types:handle_fsm_ret(state()).
wait('cast', {'listener', AgentListener, NextState, SyncRef}, State) ->
    lager:debug("setting agent proc to ~p", [AgentListener]),
    acdc_agent_listener:fsm_started(AgentListener, self()),
    {'next_state', NextState, State#state{agent_listener=AgentListener
                                         ,sync_ref=SyncRef
                                         ,agent_listener_id=acdc_util:proc_id()
                                         }};
wait('cast', 'send_sync_event', State) ->
    gen_statem:cast(self(), 'send_sync_event'),
    {'next_state', 'wait', State};
wait('cast', Evt, State) ->
    handle_event(Evt, 'wait', State);
wait({'call', From}, 'dashboard_state', State) -> dashboard_reply(From,wait,State);
wait({'call', From}, 'maintenance_state', State) -> maintenance_reply(From,wait,State);
wait({'call', From}, {'maintenance_restore', Checkpoint}, State) ->
    maintenance_restore_reply(From,Checkpoint,wait,State);
wait({'call', From}, 'status', State) ->
    {'next_state', 'wait', State, {'reply', From, [{'state', <<"wait">>}]}};
wait({'call', From}, 'current_call', State) ->
    {'next_state', 'wait', State, {'reply', From, 'undefined'}};
wait('info', Evt, State) ->
    handle_info(Evt, 'wait', State).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec sync(gen_statem:event_type(), any(), state()) -> kz_types:handle_fsm_ret(state()).
sync('cast', 'send_sync_event', #state{agent_listener=AgentListener
                                      ,agent_listener_id=_AProcId
                                      }=State) ->
    lager:debug("sending sync_req event to other agent processes: ~s", [_AProcId]),
    acdc_agent_listener:send_sync_req(AgentListener),
    {'next_state', 'sync', State};
sync('cast', {'sync_req', JObj}, #state{agent_listener=AgentListener
                                       ,agent_listener_id=AProcId
                                       }=State) ->
    case kz_json:get_value(<<"Process-ID">>, JObj) of
        AProcId ->
            lager:debug("recv sync req from ourselves"),
            {'next_state', 'sync', State};
        _OtherProcId ->
            lager:debug("recv sync_req from ~s (we are ~s)", [_OtherProcId, AProcId]),
            acdc_agent_listener:send_sync_resp(AgentListener, 'sync', JObj),
            {'next_state', 'sync', State}
    end;
sync('cast', {'sync_resp', JObj}, #state{sync_ref=Ref
                                        ,agent_listener=AgentListener
                                        }=State) ->
    case catch kz_term:to_atom(kz_json:get_value(<<"Status">>, JObj)) of
        'sync' ->
            lager:debug("other agent is in sync too"),
            {'next_state', 'sync', State};
        'ready' ->
            lager:debug("other agent is in ready state, joining"),
            _ = erlang:cancel_timer(Ref),
            acdc_agent_listener:presence_update(AgentListener, ?PRESENCE_GREEN),
            {Next, SwitchTo, State1} =
                apply_state_updates(State#state{sync_ref='undefined'}),
            {Next, SwitchTo, State1, 'hibernate'};
        {'EXIT', _} ->
            lager:debug("other agent sent unusable state, ignoring"),
            {'next_state', 'sync', State};
        Status ->
            lager:debug("other agent is in ~s, delaying", [Status]),
            _ = erlang:cancel_timer(Ref),
            {'next_state', 'sync', State#state{sync_ref=start_resync_timer()}}
    end;
sync('cast', {'member_connect_req', _}, State) ->
    lager:debug("member_connect_req recv, not ready"),
    {'next_state', 'sync', State};
sync('cast', Evt, State) ->
    handle_event(Evt, 'sync', State);
sync({'call', From}, 'dashboard_state', State) -> dashboard_reply(From,sync,State);
sync({'call', From}, 'maintenance_state', State) -> maintenance_reply(From,sync,State);
sync({'call', From}, {'maintenance_restore', Checkpoint}, State) ->
    maintenance_restore_reply(From,Checkpoint,sync,State);
sync({'call', From}, 'status', State) ->
    {'next_state', 'sync', State, {'reply', From, [{'state', <<"sync">>}]}};
sync({'call', From}, 'current_call', State) ->
    {'next_state', 'sync', State, {'reply', From, 'undefined'}};
sync('info', ?NEW_CHANNEL_FROM(CallId), State) ->
    lager:debug("sync call_from outbound: ~s", [CallId]),
    {'next_state', 'outbound', start_outbound_call_handling(CallId, State), 'hibernate'};
sync('info', ?NEW_CHANNEL_TO(CallId, _), State) ->
    lager:debug("sync call_to outbound: ~s", [CallId]),
    {'next_state', 'outbound', start_outbound_call_handling(CallId, State), 'hibernate'};
sync('info', {'timeout', Ref, ?SYNC_RESPONSE_MESSAGE}, #state{sync_ref=Ref
                                                             ,agent_listener=AgentListener
                                                             }=State) when is_reference(Ref) ->
    lager:debug("done waiting for sync responses"),
    acdc_agent_listener:presence_update(AgentListener, ?PRESENCE_GREEN),

    %% This timeout has been consumed. Keeping its reference in ready/paused
    %% makes a completed sync look like pending work during maintenance.
    apply_state_updates(State#state{sync_ref='undefined'});
sync('info', {'timeout', Ref, ?RESYNC_RESPONSE_MESSAGE}, #state{sync_ref=Ref}=State) when is_reference(Ref) ->
    lager:debug("resync timer expired, lets check with the others again"),
    SyncRef = start_sync_timer(),
    gen_statem:cast(self(), 'send_sync_event'),
    {'next_state', 'sync', State#state{sync_ref=SyncRef}};
sync('info', Evt, State) ->
    handle_info(Evt, 'sync', State).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec ready(gen_statem:event_type(), any(), state()) -> kz_types:handle_fsm_ret(state()).
ready('cast', {'sync_req', JObj}, #state{agent_listener=AgentListener}=State) ->
    lager:debug("recv sync_req from ~s", [kz_json:get_value(<<"Server-ID">>, JObj)]),
    acdc_agent_listener:send_sync_resp(AgentListener, 'ready', JObj),
    {'next_state', 'ready', State};
ready('cast', {'sync_resp', _}, State) ->
    {'next_state', 'ready', State};
ready('cast', {'member_connect_win', JObj, 'same_node'}, #state{agent_listener=AgentListener
                                                               ,endpoints=OrigEPs
                                                               ,account_id=AccountId
                                                               ,agent_id=AgentId
                                                               ,connect_failures=CF
                                                               }=State) ->
    Call = kapps_call:from_json(kz_json:get_value(<<"Call">>, JObj)),
    CallId = kapps_call:call_id(Call),

    kz_log:put_callid(CallId),

    WrapupTimer = kz_json:get_integer_value(<<"Wrapup-Timeout">>, JObj, 0),
    QueueId = kz_json:get_value(<<"Queue-ID">>, JObj),

    CDRUrl = cdr_url(JObj),
    RecordingUrl = recording_url(JObj),

    lager:debug("trying to ring agent ~s to connect to caller in queue ~s", [AgentId, QueueId]),

    case get_endpoints(OrigEPs, Call, AgentId, QueueId) of
        {'error', 'no_endpoints'} ->
            lager:info("agent ~s has no endpoints assigned; logging agent out", [AgentId]),
            acdc_agent_stats:agent_logged_out(AccountId, AgentId),
            agent_logout(self()),
            acdc_agent_listener:member_connect_retry(AgentListener, JObj),
            {'next_state', 'paused', State};
        {'error', _E} ->
            lager:debug("can't take the call, skip me: ~p", [_E]),
            acdc_agent_listener:member_connect_retry(AgentListener, JObj),
            {'next_state', 'ready', State#state{connect_failures=CF+1}};
        {'ok', UpdatedEPs} ->
            acdc_util:bind_to_call_events(Call, AgentListener),

            ConnectId = kz_api:msg_id(JObj, kz_binary:rand_hex(16)),
            Win = kz_json:set_value(<<"Msg-ID">>, ConnectId, JObj),
            acdc_agent_listener:bridge_to_member(AgentListener, Call, Win, UpdatedEPs, CDRUrl, RecordingUrl),

            {CIDNumber, CIDName} = acdc_util:caller_id(Call),

            acdc_agent_stats:agent_connecting(AccountId, AgentId, CallId, CIDName, CIDNumber, QueueId),
            lager:info("trying to ring agent endpoints(~p)", [length(UpdatedEPs)]),
            lager:debug("notifications for the queue: ~p", [kz_json:get_value(<<"Notifications">>, JObj)]),
            {'next_state', 'ringing', State#state{wrapup_timeout=WrapupTimer
                                                 ,member_call=Call
                                                 ,member_call_id=CallId
                                                 ,member_connect_id=ConnectId
                                                 ,member_call_start=kz_time:start_time()
                                                 ,member_call_queue_id=QueueId
                                                 ,endpoints=UpdatedEPs
                                                 ,queue_notifications=kz_json:get_value(<<"Notifications">>, JObj)
                                                 }}
    end;
ready('cast', {'member_connect_win', JObj, 'different_node'}, #state{agent_listener=AgentListener
                                                                    ,endpoints=OrigEPs
                                                                    ,agent_id=AgentId
                                                                    ,connect_failures=CF
                                                                    }=State) ->
    Call = kapps_call:from_json(kz_json:get_value(<<"Call">>, JObj)),
    CallId = kapps_call:call_id(Call),

    kz_log:put_callid(CallId),

    WrapupTimer = kz_json:get_integer_value(<<"Wrapup-Timeout">>, JObj, 0),
    QueueId = kz_json:get_value(<<"Queue-ID">>, JObj),

    RecordingUrl = recording_url(JObj),

    %% Only start monitoring if the agent can actually take the call
    case get_endpoints(OrigEPs, Call, AgentId, QueueId) of
        {'error', 'no_endpoints'} ->
            lager:info("agent ~s has no endpoints assigned; logging agent out", [AgentId]),
            {'next_state', 'paused', State};
        {'error', _E} ->
            lager:debug("can't take the call, skip me: ~p", [_E]),
            {'next_state', 'ready', State#state{connect_failures=CF+1}};
        {'ok', UpdatedEPs} ->
            acdc_util:bind_to_call_events(Call, AgentListener),

            acdc_agent_listener:monitor_call(AgentListener, Call, JObj, RecordingUrl),
            NextState = 'ringing',

            lager:debug("monitoring agent ~s to connect to caller in queue ~s", [AgentId, QueueId]),
            {'next_state', NextState, State#state{wrapup_timeout=WrapupTimer
                                                 ,member_call=Call
                                                 ,member_call_id=CallId
                                                 ,member_call_start=kz_time:start_time()
                                                 ,member_call_queue_id=QueueId
                                                 ,endpoints=UpdatedEPs
                                                 ,queue_notifications=kz_json:get_value(<<"Notifications">>, JObj)
                                                 ,monitoring='true'
                                                 ,member_connect_id=kz_api:msg_id(JObj)
                                                 }}
    end;
ready('cast', {'member_connect_satisfied', _}, State) ->
    lager:info("unexpected connect_satisfied"),
    {'next_state', 'ready', State};
ready('cast', {'member_connect_req', _}, #state{max_connect_failures=Max
                                               ,connect_failures=Fails
                                               ,account_id=AccountId
                                               ,agent_id=AgentId
                                               }=State) when is_integer(Max), Fails >= Max ->
    lager:info("agent has failed to connect ~b times, logging out", [Fails]),
    acdc_agent_stats:agent_logged_out(AccountId, AgentId),
    agent_logout(self()),
    {'next_state', 'paused', State};
ready('cast', {'member_connect_req', JObj}, #state{agent_listener=AgentListener}=State) ->
    acdc_agent_listener:member_connect_resp(AgentListener, JObj),
    {'next_state', 'ready', State};
ready('cast', {'originate_uuid', ACallId, ACtrlQ}, #state{agent_listener=AgentListener}=State) ->
    acdc_agent_listener:originate_uuid(AgentListener, ACallId, ACtrlQ),
    {'next_state', 'ready', State};
ready('cast', {'channel_answered', JObj}, #state{outbound_call_ids=OutboundCallIds}=State) ->
    CallId = call_id(JObj),
    case lists:member(CallId, OutboundCallIds) of
        'true' ->
            lager:debug("agent picked up outbound call ~s", [CallId]),
            {'next_state', 'outbound', start_outbound_call_handling(CallId, clear_call(State, 'ready')), 'hibernate'};
        'false' ->
            lager:debug("unexpected answer of ~s while in ready", [CallId]),
            {'next_state', 'ready', State}
    end;
ready('cast', {'channel_unbridged', CallId}, #state{agent_listener=_AgentListener}=State) ->
    lager:debug("channel unbridged: ~s", [CallId]),
    {'next_state', 'ready', State};
ready('cast', {'leg_destroyed', CallId}, #state{agent_listener=_AgentListener}=State) ->
    lager:debug("channel unbridged: ~s", [CallId]),
    {'next_state', 'ready', State};
ready('cast', {'originate_failed', _E}, State) ->
    {'next_state', 'ready', State};
ready('cast', Evt, State) ->
    handle_event(Evt, 'ready', State);
ready({'call', From}, 'dashboard_state', State) -> dashboard_reply(From,ready,State);
ready({'call', From}, 'maintenance_state', State) -> maintenance_reply(From,ready,State);
ready({'call', From}, {'maintenance_restore', Checkpoint}, State) ->
    maintenance_restore_reply(From,Checkpoint,ready,State);
ready({'call', From}, 'status', State) ->
    {'next_state', 'ready', State, {'reply', From, [{'state', <<"ready">>}]}};
ready({'call', From}, 'current_call', State) ->
    {'next_state', 'ready', State, {'reply', From, 'undefined'}};
ready('info', ?NEW_CHANNEL_FROM(CallId), State) ->
    lager:debug("ready call_from outbound: ~s", [CallId]),
    {'next_state', 'outbound', start_outbound_call_handling(CallId, State), 'hibernate'};
ready('info', ?NEW_CHANNEL_TO(CallId, 'undefined'), State) ->
    lager:debug("ready call_to outbound: ~s", [CallId]),
    {'next_state', 'outbound', start_outbound_call_handling(CallId, State), 'hibernate'};
ready('info', ?NEW_CHANNEL_TO(CallId, MemberCallId), State) ->
    cancel_if_failed_originate(CallId, MemberCallId, 'ready', State);
ready('info', ?DESTROYED_CHANNEL(CallId, _Cause), #state{agent_listener=AgentListener
                                                        ,outbound_call_ids=OutboundCallIds
                                                        }=State) ->
    case lists:member(CallId, OutboundCallIds) of
        'true' ->
            lager:debug("agent outbound channel ~s down", [CallId]),
            acdc_util:unbind_from_call_events(CallId, AgentListener),
            {'next_state', 'ready', State#state{outbound_call_ids=lists:delete(CallId, OutboundCallIds)}};
        'false' ->
            lager:debug("unexpected channel ~s down", [CallId]),
            acdc_agent_listener:channel_hungup(AgentListener, CallId),
            {'next_state', 'ready', State}
    end;
ready('info', Evt, State) ->
    handle_info(Evt, 'ready', State).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec ringing(gen_statem:event_type(), any(), state()) -> kz_types:handle_fsm_ret(state()).
ringing('cast', {'member_connect_req', _}, State) ->
    {'next_state', 'ringing', State};
ringing('cast', {'member_connect_win', JObj, 'same_node'}, #state{agent_listener=AgentListener}=State) ->
    lager:debug("agent won, but can't process this right now (already ringing)"),
    acdc_agent_listener:member_connect_retry(AgentListener, JObj),

    {'next_state', 'ringing', State};
ringing('cast', {'member_connect_satisfied', JObj}, #state{agent_listener=AgentListener
                                                          ,member_call_id=MemberCallId
                                                          ,member_connect_id=ConnectId
                                                          ,account_id=AccountId
                                                          ,member_call_queue_id=QueueId
                                                          ,agent_id=AgentId
                                                          }=State) ->
    lager:info("received connect_satisfied: check if I should hangup: ~p", [JObj]),
    CallId = kz_json:get_ne_binary_value([<<"Call">>, <<"Call-ID">>], JObj, []),
    case CallId =:= MemberCallId andalso is_binary(ConnectId)
        andalso kz_json:get_value(<<"Connect-ID">>, JObj) =:= ConnectId of
        true ->
            lager:info("hanging up: someother agent replies"),
            acdc_agent_listener:channel_hungup(AgentListener, MemberCallId),
            acdc_stats:call_missed(AccountId, QueueId, AgentId, MemberCallId, <<"LOSE_RACE">>),
            acdc_agent_listener:presence_update(AgentListener, ?PRESENCE_GREEN),

            %% Losing a normal simultaneous-ring race is not a failed agent
            %% connection. Preserve failure count and explicit pending status
            %% changes; never auto-log out the agents who did not answer first.
            apply_state_updates(clear_call(State, 'ready'));
        _ -> {'next_state', 'ringing', State}
    end;
ringing('cast', {'originate_ready', JObj}, #state{agent_listener=AgentListener}=State) ->
    case current_originate(JObj, State) of
        'true' -> acdc_agent_listener:originate_execute(AgentListener, JObj);
        'false' -> lager:debug("ignoring originate_ready for another offer")
    end,
    {'next_state', 'ringing', State};
ringing('cast', {'originate_uuid', ACallId, ACtrlQ}, #state{agent_listener=AgentListener}=State) ->
    lager:debug("recv originate_uuid for agent call ~s(~s)", [ACallId, ACtrlQ]),
    acdc_agent_listener:originate_uuid(AgentListener, ACallId, ACtrlQ),
    {'next_state', 'ringing', State};
ringing('cast', {'originate_started', JObj}, State) ->
    ringing('cast', {'originate_resp', JObj}, State);
ringing('cast', {'originate_failed', E}, State) ->
    case current_originate(E, State) of
        'true' -> ringing_failed(missed_reason(kz_json:get_value(<<"Error-Message">>, E)), State);
        'false' -> {'next_state', 'ringing', State}
    end;
ringing('cast', {'agent_timeout', JObj}, #state{member_call_id=CallId
                                             ,member_connect_id=ConnectId}=State) ->
    case is_binary(CallId) andalso call_id(JObj) =:= CallId andalso is_binary(ConnectId)
        andalso kz_json:get_value(<<"Connect-ID">>, JObj) =:= ConnectId of
        'true' -> ringing_failed(<<"timeout">>, State);
        'false' -> {'next_state', 'ringing', State}
    end;
ringing('cast', {'channel_bridge_event', Event}, State) ->
    case agent_bridge_leg(Event, State) of
        'undefined' -> {'next_state', 'ringing', State};
        AgentCallId -> agent_bridge_connected(State#state{agent_call_id=AgentCallId})
    end;
ringing('cast', {'channel_bridged', _CallId}, State) ->
    {'next_state', 'ringing', State};
ringing('cast', {'channel_answered', JObj}, #state{member_call_id=MemberCallId
                                                  ,agent_listener=AgentListener
                                                  ,outbound_call_ids=OutboundCallIds
                                                  }=State) ->
    case call_id(JObj) of
        MemberCallId ->
            lager:debug("caller's channel answered"),
            {'next_state', 'ringing', State};
        OtherCallId ->
            case lists:member(OtherCallId, OutboundCallIds) of
                'true' ->
                    lager:debug("agent picked up outbound call ~s instead of the queue call ~s", [OtherCallId, MemberCallId]),
                    acdc_agent_listener:hangup_call(AgentListener),
                    {'next_state', 'outbound', start_outbound_call_handling(OtherCallId, clear_call(State, 'ready')), 'hibernate'};
                'false' ->
                    case current_agent_leg(JObj, State) of
                        'true' -> {'next_state', 'ringing', State#state{agent_call_id=OtherCallId}};
                        'false' -> {'next_state', 'ringing', State}
                    end
            end
    end;
ringing('cast', {'sync_req', JObj}, #state{agent_listener=AgentListener}=State) ->
    lager:debug("recv sync_req from ~s", [kz_json:get_value(<<"Process-ID">>, JObj)]),
    acdc_agent_listener:send_sync_resp(AgentListener, 'ringing', JObj),
    {'next_state', 'ringing', State};
ringing('cast', {'sync_resp', _}, State) ->
    {'next_state', 'ringing', State};
ringing('cast', {'originate_resp', JObj}, State) ->
    case current_originate(JObj, State) of
        'false' -> {'next_state', 'ringing', State};
        'true' ->
            ACallId = call_id(JObj),
            agent_bridge_connected(State#state{agent_call_id=ACallId})
    end;
ringing('cast', {'shared_failure', JObj}, #state{monitoring=Monitoring
                                              ,agent_listener=Listener
                                              ,member_call_id=Member}=State) ->
    case Monitoring andalso current_shared_event(JObj, State) of
        'true' ->
            acdc_agent_listener:channel_hungup(Listener, Member),
            acdc_agent_listener:presence_update(Listener, ?PRESENCE_GREEN),
            case kz_json:get_value(<<"Blame">>, JObj) of
                <<"member">> -> apply_state_updates(clear_call(State, 'ready'));
                _ -> finish_ringing_failure(State)
            end;
        'false' -> {'next_state', 'ringing', State}
    end;
ringing('cast', {'shared_call_id', JObj}, #state{agent_listener=AgentListener}=State) ->
    ACallId = kz_json:get_ne_binary_value(<<"Agent-Call-ID">>, JObj),
    case is_binary(ACallId) andalso current_shared_event(JObj, State) of
        'false' -> {'next_state', 'ringing', State};
        'true' ->
            acdc_util:bind_to_call_events(ACallId, AgentListener),
            acdc_agent_listener:monitor_connect_accepted(AgentListener, ACallId),
            {'next_state', 'answered', State#state{agent_call_id=ACallId
                                                ,connect_failures=0}}
    end;
ringing('cast', {'leg_created', _CallId}, State) ->
    {'next_state', 'ringing', State};
ringing('cast', {'leg_destroyed', _CallId}, State) ->
    {'next_state', 'ringing', State};
ringing('cast', {'usurp_control', _CallId}, State) ->
    {'next_state', 'ringing', State};
ringing('cast', Evt, State) ->
    handle_event(Evt, 'ringing', State);
ringing({'call', From}, 'dashboard_state', State) -> dashboard_reply(From,ringing,State);
ringing({'call', From}, 'maintenance_state', State) -> maintenance_reply(From,ringing,State);
ringing({'call', From}, {'maintenance_restore', Checkpoint}, State) ->
    maintenance_restore_reply(From,Checkpoint,ringing,State);
ringing({'call', From}, 'status', #state{member_call_id=MemberCallId
                                        ,agent_call_id=ACallId
                                        }=State) ->
    {'next_state', 'ringing', State
    ,{'reply', From, [{'state', <<"ringing">>}
                     ,{'member_call_id', MemberCallId}
                     ,{'agent_call_id', ACallId}
                     ]}};
ringing({'call', From}, 'current_call', #state{member_call=Call
                                              ,member_call_queue_id=QueueId
                                              }=State) ->
    {'next_state', 'ringing', State
    ,{'reply', From, current_call(Call, 'ringing', QueueId, 'undefined')}
    };
ringing('info', ?NEW_CHANNEL_FROM(CallId), #state{agent_listener=AgentListener}=State) ->
    lager:debug("ringing call_from outbound: ~s", [CallId]),
    acdc_agent_listener:hangup_call(AgentListener),
    {'next_state', 'outbound', start_outbound_call_handling(CallId, clear_call(State, 'ready')), 'hibernate'};
ringing('info', ?NEW_CHANNEL_TO(CallId, 'undefined'), #state{agent_listener=AgentListener
                                                            ,outbound_call_ids=OutboundCallIds
                                                            }=State) ->
    lager:debug("ringing call_to outbound: ~s", [CallId]),
    acdc_util:bind_to_call_events(CallId, AgentListener),
    {'next_state', 'ringing', State#state{outbound_call_ids=[CallId | lists:delete(CallId, OutboundCallIds)]}};
ringing('info', ?NEW_CHANNEL_TO(CallId, MemberCallId), #state{member_call_id=MemberCallId}=State) ->
    lager:debug("new channel ~s for agent", [CallId]),
    {'next_state', 'ringing', State};
ringing('info', ?NEW_CHANNEL_TO(CallId, MemberCallId), State) ->
    cancel_if_failed_originate(CallId, MemberCallId, 'ringing', State);
ringing('info', ?DESTROYED_CHANNEL(AgentCallId, <<"LOSE_RACE">>), #state{agent_call_id=AgentCallId}=State)
  when is_binary(AgentCallId) ->
    agent_lost_race(State);
ringing('info', ?DESTROYED_CHANNEL(AgentCallId, Cause), #state{agent_listener=AgentListener
                                                              ,agent_call_id=AgentCallId
                                                              ,account_id=AccountId
                                                              ,agent_id=AgentId
                                                              ,member_call_queue_id=QueueId
                                                              ,member_call_id=MemberCallId
                                                              ,connect_failures=Fails
                                                              ,max_connect_failures=MaxFails
                                                              }=State) ->
    lager:debug("ringing agent failed: timeout on ~s ~s", [AgentCallId, Cause]),

    acdc_agent_listener:member_connect_retry(AgentListener, MemberCallId),
    acdc_agent_listener:channel_hungup(AgentListener, MemberCallId),

    acdc_stats:call_missed(AccountId, QueueId, AgentId, MemberCallId, Cause),

    acdc_agent_listener:presence_update(AgentListener, ?PRESENCE_GREEN),

    State1 = clear_call(State, 'failed'),
    StateName1 = return_to_state(Fails+1, MaxFails),
    case StateName1 of
        'paused' -> {'next_state', 'paused', State1};
        'ready' -> apply_state_updates(State1)
    end;
ringing('info', ?DESTROYED_CHANNEL(MemberCallId, _Cause), #state{agent_listener=AgentListener
                                                                ,member_call_id=MemberCallId
                                                                }=State) ->
    lager:debug("caller's channel (~s) has gone down, stop agent's call: ~s", [MemberCallId, _Cause]),
    acdc_agent_listener:channel_hungup(AgentListener, MemberCallId),

    acdc_agent_listener:presence_update(AgentListener, ?PRESENCE_GREEN),
    apply_state_updates(clear_call(State, 'ready'));
ringing('info', ?DESTROYED_CHANNEL(CallId, _Cause), #state{agent_listener=AgentListener
                                                          ,outbound_call_ids=OutboundCallIds
                                                          }=State) ->
    case lists:member(CallId, OutboundCallIds) of
        'true' ->
            lager:debug("agent outbound channel ~s down", [CallId]),
            acdc_util:unbind_from_call_events(CallId, AgentListener),
            {'next_state', 'ringing', State#state{outbound_call_ids=lists:delete(CallId, OutboundCallIds)}};
        'false' ->
            lager:debug("unexpected channel ~s down", [CallId]),
            {'next_state', 'ringing', State}
    end;
ringing('info', Evt, State) ->
    handle_info(Evt, 'ringing', State).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
%% The win's message ID identifies this offer, including retries of the same
%% member call. The listener uses it as the originate request's message ID.
-spec current_originate(kz_json:object(), state()) -> boolean().
current_originate(JObj, #state{member_connect_id=ConnectId}) ->
    is_binary(ConnectId) andalso kz_json:is_json_object(JObj)
        andalso kz_api:msg_id(JObj) =:= ConnectId.

-spec current_shared_event(kz_json:object(), state()) -> boolean().
current_shared_event(JObj, #state{account_id=AccountId, agent_id=AgentId
                                 ,member_call_id=Member, member_connect_id=ConnectId}) ->
    is_binary(Member) andalso is_binary(ConnectId)
        andalso kz_json:get_value(<<"Account-ID">>, JObj) =:= AccountId
        andalso kz_json:get_value(<<"Agent-ID">>, JObj) =:= AgentId
        andalso kz_json:get_value(<<"Member-Call-ID">>, JObj) =:= Member
        andalso kz_json:get_value(<<"Connect-ID">>, JObj) =:= ConnectId.

-spec current_agent_leg(kz_json:object(), state()) -> boolean().
current_agent_leg(Event, #state{account_id=AccountId, agent_id=AgentId
                               ,member_call_id=Member, member_connect_id=ConnectId
                               ,agent_call_id=KnownLeg}) ->
    CallId = call_id(Event),
    CCVs = kz_json:get_json_value(<<"Custom-Channel-Vars">>, Event, kz_json:new()),
    is_binary(CallId) andalso CallId =/= <<>>
        andalso (CallId =:= KnownLeg
                 orelse (is_binary(ConnectId)
                         andalso kz_json:get_value(<<"Account-ID">>, CCVs) =:= AccountId
                         andalso kz_json:get_value(<<"Agent-ID">>, CCVs) =:= AgentId
                         andalso kz_json:get_value(<<"Member-Call-ID">>, CCVs) =:= Member
                         andalso kz_json:get_value(<<"Request-ID">>, CCVs) =:= ConnectId)).

-spec shared_headers(state()) -> kz_term:proplist().
shared_headers(#state{account_id=AccountId, agent_id=AgentId
                      ,member_call_id=Member, member_connect_id=ConnectId}) ->
    [{<<"Account-ID">>, AccountId}, {<<"Agent-ID">>, AgentId}
    ,{<<"Member-Call-ID">>, Member}, {<<"Connect-ID">>, ConnectId}
     | kz_api:default_headers(?APP_NAME, ?APP_VERSION)].

-spec publish_shared_call_id(kz_term:ne_binary(), state()) -> any().
publish_shared_call_id(ACallId, State) ->
    try kapi_acdc_agent:publish_shared_call_id([{<<"Agent-Call-ID">>, ACallId} | shared_headers(State)])
    catch _:_ -> lager:warning("could not publish agent call ID; completing locally")
    end.

-spec ringing_failed(kz_term:ne_binary(), state()) -> kz_types:handle_fsm_ret(state()).
ringing_failed(<<"LOSE_RACE">>, State) ->
    publish_shared_failure([{<<"Blame">>, <<"member">>} | shared_headers(State)]),
    agent_lost_race(State);
ringing_failed(Reason, #state{agent_listener=Listener, account_id=AccountId
                            ,agent_id=AgentId, member_call_queue_id=QueueId
                            ,member_call_id=Member}=State) ->
    %% Retry also stops this attempt's agent legs and removes the call binding.
    %% Send it before advertising readiness, in order to the same listener.
    acdc_agent_listener:member_connect_retry(Listener, Member),
    acdc_stats:call_missed(AccountId, QueueId, AgentId, Member, Reason),
    acdc_agent_listener:presence_update(Listener, ?PRESENCE_GREEN),
    publish_shared_failure(shared_headers(State)),
    finish_ringing_failure(State).

-spec publish_shared_failure(kz_term:proplist()) -> any().
publish_shared_failure(Headers) ->
    try kapi_acdc_agent:publish_shared_originate_failure(Headers)
    catch _:_ -> lager:warning("could not publish agent failure; recovering locally")
    end.

-spec finish_ringing_failure(state()) -> kz_types:handle_fsm_ret(state()).
finish_ringing_failure(#state{connect_failures=Fails, max_connect_failures=Max}=State) ->
    Cleared = clear_call(State, 'failed'),
    case return_to_state(Fails + 1, Max) of
        'paused' -> {'next_state', 'paused', Cleared};
        'ready' -> apply_state_updates(Cleared)
    end.

agent_bridge_leg(Event, #state{account_id=AccountId
                               ,member_call_id=Member, agent_call_id=KnownLeg}=State) ->
    CallId = kz_call_event:call_id(Event), Other = kz_call_event:other_leg_call_id(Event),
    CCVs = kz_json:get_json_value(<<"Custom-Channel-Vars">>, Event, kz_json:new()),
    case kz_json:get_value(<<"Account-ID">>, CCVs) =:= AccountId andalso is_binary(Member) of
        'false' -> 'undefined';
        'true' when is_binary(KnownLeg), CallId =:= Member, Other =:= KnownLeg -> KnownLeg;
        'true' when is_binary(KnownLeg), CallId =:= KnownLeg, Other =:= Member -> KnownLeg;
        'true' when Other =:= Member, is_binary(CallId), CallId =/= Member ->
            %% The own agent-leg event can beat originate/shared-call-id.
            %% A caller-side event for somebody else's leg cannot establish
            %% this agent's identity merely because both heard the same caller.
            case current_agent_leg(Event, State) of
                'true' -> CallId;
                'false' -> 'undefined'
            end;
        _ -> 'undefined'
    end.

agent_bridge_connected(#state{monitoring='true', agent_listener=Listener, agent_call_id=AgentCallId}=State) ->
    %% A monitoring replica must not submit a second queue acceptance or
    %% duplicate connection statistics when its bridge event arrives first.
    acdc_agent_listener:monitor_connect_accepted(Listener, AgentCallId),
    {'next_state', 'answered', State#state{connect_failures=0}};
agent_bridge_connected(#state{member_call_id=MemberCallId, agent_call_id=AgentCallId
                               ,member_call=MemberCall, agent_listener=AgentListener
                               ,account_id=AccountId, agent_id=AgentId, queue_notifications=Ns
                               ,member_call_queue_id=QueueId}=State) ->
    %% Either originate response or the correlated native bridge can arrive
    %% first. Publish exactly at the local transition so replicas learn the leg
    %% even when the later originate response is ignored in answered state.
    publish_shared_call_id(AgentCallId, State),
    acdc_agent_listener:member_connect_accepted(AgentListener, AgentCallId),
    maybe_notify(Ns, ?NOTIFY_PICKUP, State),
    {CIDNumber, CIDName} = acdc_util:caller_id(MemberCall),
    acdc_agent_stats:agent_connected(AccountId, AgentId, MemberCallId, CIDName, CIDNumber, QueueId),
    {'next_state', 'answered', State#state{connect_failures=0}}.

agent_lost_race(#state{agent_listener=Listener, account_id=AccountId
                      ,member_call_id=Member, member_call_queue_id=QueueId, agent_id=AgentId}=State) ->
    %% A losing claim is not a no-answer or completed customer call.
    acdc_agent_listener:member_connect_retry(Listener, Member),
    acdc_agent_listener:channel_hungup(Listener, Member),
    acdc_stats:call_missed(AccountId, QueueId, AgentId, Member, <<"LOSE_RACE">>),
    acdc_agent_listener:presence_update(Listener, ?PRESENCE_GREEN),
    apply_state_updates(clear_call(State, 'ready')).

-spec answered(gen_statem:event_type(), any(), state()) -> kz_types:handle_fsm_ret(state()).
answered('cast', {'member_connect_req', _}, State) ->
    {'next_state', 'answered', State};
answered('cast', {'member_connect_win', JObj, 'same_node'}, #state{agent_listener=AgentListener}=State) ->
    lager:debug("agent won, but can't process this right now (on the phone with someone)"),
    acdc_agent_listener:member_connect_retry(AgentListener, JObj),

    {'next_state', 'answered', State};
answered('cast', {'member_connect_satisfied', _}, State) ->
    lager:info("unexpected connect_satisfied"),
    {'next_state', 'answered', State};
answered('cast', {'dialplan_error', _App}, #state{agent_listener=AgentListener
                                                 ,account_id=AccountId
                                                 ,agent_id=AgentId
                                                 ,member_call_queue_id=QueueId
                                                 ,member_call_id=CallId
                                                 ,agent_call_id=ACallId
                                                 }=State) ->
    lager:debug("connecting agent to caller failed(~p), clearing call", [_App]),
    acdc_agent_listener:channel_hungup(AgentListener, ACallId),
    acdc_agent_listener:member_connect_retry(AgentListener, CallId),

    acdc_stats:call_missed(AccountId, QueueId, AgentId, CallId, <<"dialplan_error">>),

    acdc_agent_listener:presence_update(AgentListener, ?PRESENCE_GREEN),
    apply_state_updates(clear_call(State, 'ready'));
answered('cast', {'sync_req', JObj}, #state{agent_listener=AgentListener
                                           ,member_call_id=CallId
                                           ,agent_call_id=AgentCallId
                                           }=State) ->
    lager:debug("recv sync_req from ~s", [kz_json:get_value(<<"Process-ID">>, JObj)]),
    acdc_agent_listener:send_sync_resp(AgentListener, 'answered', JObj
                                     ,props:filter_undefined([{<<"Call-ID">>, CallId}
                                                            ,{<<"Agent-Call-ID">>, AgentCallId}])),
    {'next_state', 'answered', State};
answered('cast', {'sync_resp', _}, State) ->
    {'next_state', 'answered', State};
answered('cast', {'channel_unbridged', CallId}, #state{member_call_id=CallId}=State) ->
    lager:info("caller channel ~s unbridged", [CallId]),
    {'next_state', 'answered', State};
answered('cast', {'channel_unbridged', CallId}, #state{agent_call_id=CallId}=State) ->
    lager:info("agent channel unbridged"),
    {'next_state', 'answered', State};
answered('cast', {'channel_answered', JObj}=Evt, #state{agent_call_id=AgentCallId
                                                       ,member_call_id=MemberCallId
                                                       ,outbound_call_ids=OutboundCallIds
                                                       }=State) ->
    case call_id(JObj) of
        AgentCallId ->
            lager:debug("agent's channel ~s has answered", [AgentCallId]),
            {'next_state', 'answered', State};
        MemberCallId ->
            lager:debug("member's channel has answered"),
            {'next_state', 'answered', State};
        OtherCallId ->
            case lists:member(OtherCallId, OutboundCallIds) of
                'true' ->
                    lager:debug("agent answered outbound call ~s", [OtherCallId]),
                    {'next_state', 'answered', State};
                'false' ->
                    lager:debug("unexpected event while answered: ~p", [Evt]),
                    {'next_state', 'answered', State}
            end
    end;
answered('cast', {'channel_bridged', _}, State) ->
    {'next_state', 'answered', State};
answered('cast', {'channel_unbridged', _}, State) ->
    {'next_state', 'answered', State};
answered('cast', {'channel_transferee', Transferor, Transferee}, #state{account_id=AccountId
                                                                       ,agent_id=AgentId
                                                                       ,member_call_id=Transferor
                                                                       ,member_call_queue_id=QueueId
                                                                       ,queue_notifications=Ns
                                                                       ,agent_call_id=Transferee
                                                                       }=State) ->
    lager:info("caller transferred the agent"),
    acdc_stats:call_processed(AccountId, QueueId, AgentId, Transferor, 'member'),
    maybe_notify(Ns, ?NOTIFY_HANGUP, State),
    {'next_state', 'outbound', start_outbound_call_handling(Transferee, clear_call(State, 'ready'))};
answered('cast', {'channel_transferee', _, _}, State) ->
    {'next_state', 'answered', State};
answered('cast', {'channel_replaced', _}, State) ->
    {'next_state', 'answered', State};
answered('cast', {'originate_started', _CallId}, State) ->
    {'next_state', 'answered', State};
answered('cast', {'leg_created', _CallId}, State) ->
    {'next_state', 'answered', State};
answered('cast', {'usurp_control', _CallId}, State) ->
    {'next_state', 'answered', State};
answered('cast', Evt, State) ->
    handle_event(Evt, 'answered', State);
answered({'call', From}, 'dashboard_state', State) -> dashboard_reply(From,answered,State);
answered({'call', From}, 'maintenance_state', State) -> maintenance_reply(From,answered,State);
answered({'call', From}, {'maintenance_restore', Checkpoint}, State) ->
    maintenance_restore_reply(From,Checkpoint,answered,State);
answered({'call', From}, 'status', #state{member_call_id=MemberCallId
                                         ,agent_call_id=ACallId
                                         }=State) ->
    {'next_state', 'answered', State
    ,{'reply', From, [{'state', <<"answered">>}
                     ,{'member_call_id', MemberCallId}
                     ,{'agent_call_id', ACallId}
                     ]}};
answered({'call', From}, 'current_call', #state{member_call=Call
                                               ,member_call_start=Start
                                               ,member_call_queue_id=QueueId
                                               }=State) ->
    {'next_state', 'answered', State
    ,{'reply', From, current_call(Call, 'answered', QueueId, Start)}
    };
answered('info', ?NEW_CHANNEL_FROM(CallId), #state{agent_listener=AgentListener
                                                  ,outbound_call_ids=OutboundCallIds
                                                  }=State) ->
    lager:debug("answered call_from outbound: ~s", [CallId]),
    acdc_util:bind_to_call_events(CallId, AgentListener),
    {'next_state', 'answered', State#state{outbound_call_ids=[CallId | lists:delete(CallId, OutboundCallIds)]}};
answered('info', ?NEW_CHANNEL_TO(CallId, 'undefined'), #state{agent_listener=AgentListener
                                                             ,outbound_call_ids=OutboundCallIds
                                                             }=State) ->
    lager:debug("answered call_to outbound: ~s", [CallId]),
    acdc_util:bind_to_call_events(CallId, AgentListener),
    {'next_state', 'answered', State#state{outbound_call_ids=[CallId | lists:delete(CallId, OutboundCallIds)]}};
answered('info', ?NEW_CHANNEL_TO(CallId, MemberCallId), #state{member_call_id=MemberCallId}=State) ->
    lager:debug("new channel ~s for agent", [CallId]),
    {'next_state', 'answered', State};
answered('info', ?DESTROYED_CHANNEL(CallId, Cause), #state{member_call_id=CallId
                                                          ,outbound_call_ids=[]
                                                          }=State) ->
    lager:debug("caller's channel hung up: ~s", [Cause]),
    {'next_state', 'wrapup', State#state{wrapup_ref=hangup_call(State, 'member')}};
answered('info', ?DESTROYED_CHANNEL(CallId, _Cause), #state{account_id=AccountId
                                                           ,agent_id=AgentId
                                                           ,agent_listener=AgentListener
                                                           ,member_call_id=CallId
                                                           ,member_call_queue_id=QueueId
                                                           ,queue_notifications=Ns
                                                           ,outbound_call_ids=[OutboundCallId|_]
                                                           }=State) ->
    lager:debug("caller's channel hung up, but there are still some outbounds"),
    acdc_stats:call_processed(AccountId, QueueId, AgentId, CallId, 'member'),
    acdc_agent_listener:channel_hungup(AgentListener, CallId),
    maybe_notify(Ns, ?NOTIFY_HANGUP, State),
    {'next_state', 'outbound', start_outbound_call_handling(OutboundCallId, clear_call(State, 'ready')), 'hibernate'};
answered('info', ?DESTROYED_CHANNEL(CallId, <<"LOSE_RACE">>), #state{agent_call_id=CallId}=State)
  when is_binary(CallId) ->
    agent_lost_race(State);
answered('info', ?DESTROYED_CHANNEL(CallId, Cause), #state{agent_call_id=CallId
                                                          ,outbound_call_ids=[]
                                                          }=State) ->
    lager:debug("agent's channel has hung up: ~s", [Cause]),
    {'next_state', 'wrapup', State#state{wrapup_ref=hangup_call(State, 'agent')}};
answered('info', ?DESTROYED_CHANNEL(CallId, _Cause), #state{account_id=AccountId
                                                           ,agent_id=AgentId
                                                           ,agent_listener=AgentListener
                                                           ,member_call_id=MemberCallId
                                                           ,member_call_queue_id=QueueId
                                                           ,queue_notifications=Ns
                                                           ,agent_call_id=CallId
                                                           ,outbound_call_ids=[OutboundCallId|_]
                                                           }=State) ->
    lager:debug("agent's channel hung up, but there are still some outbounds"),
    acdc_stats:call_processed(AccountId, QueueId, AgentId, CallId, 'agent'),
    acdc_agent_listener:channel_hungup(AgentListener, MemberCallId),
    maybe_notify(Ns, ?NOTIFY_HANGUP, State),
    {'next_state', 'outbound', start_outbound_call_handling(OutboundCallId, clear_call(State, 'ready')), 'hibernate'};
answered('info', ?DESTROYED_CHANNEL(CallId, _Cause), #state{agent_listener=AgentListener
                                                           ,outbound_call_ids=OutboundCallIds
                                                           }=State) ->
    case lists:member(CallId, OutboundCallIds) of
        'true' ->
            lager:debug("agent outbound channel ~s down", [CallId]),
            acdc_util:unbind_from_call_events(CallId, AgentListener),
            {'next_state', 'answered', State#state{outbound_call_ids=lists:delete(CallId, OutboundCallIds)}};
        'false' ->
            lager:debug("unexpected channel ~s down", [CallId]),
            {'next_state', 'answered', State}
    end;
answered('info', Evt, State) ->
    handle_info(Evt, 'answered', State).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec wrapup(gen_statem:event_type(), any(), state()) -> kz_types:handle_fsm_ret(state()).
wrapup('cast', {'member_connect_req', _}, State) ->
    {'next_state', 'wrapup', State#state{wrapup_timeout=0}};
wrapup('cast', {'member_connect_win', JObj, 'same_node'}, #state{agent_listener=AgentListener}=State) ->
    lager:debug("agent won, but can't process this right now (in wrapup)"),
    acdc_agent_listener:member_connect_retry(AgentListener, JObj),

    {'next_state', 'wrapup', State#state{wrapup_timeout=0}};
wrapup('cast', {'member_connect_win', _, 'different_node'}, State) ->
    lager:debug("received member_connect_win for different node (wrapup)"),
    {'next_state', 'wrapup', State#state{wrapup_timeout=0}};
wrapup('cast', {'member_connect_satisfied', _}, State) ->
    lager:info("unexpected connect_satisfied"),
    {'next_state', 'wrapup', State};
wrapup('cast', {'sync_req', JObj}, #state{agent_listener=AgentListener
                                         ,wrapup_ref=Ref
                                         }=State) ->
    lager:debug("recv sync_req from ~s", [kz_json:get_value(<<"Process-ID">>, JObj)]),
    acdc_agent_listener:send_sync_resp(AgentListener, 'wrapup', JObj, [{<<"Time-Left">>, time_left(Ref)}]),
    {'next_state', 'wrapup', State};
wrapup('cast', {'sync_resp', _}, State) ->
    {'next_state', 'wrapup', State};
wrapup('cast', {'channel_bridged', _}, State) ->
    {'next_state', 'wrapup', State};
wrapup('cast', {'channel_unbridged', _}, State) ->
    {'next_state', 'wrapup', State};
wrapup('cast', {'channel_transferee', _, _}, State) ->
    {'next_state', 'wrapup', State};
wrapup('cast', {'channel_hungup', _, _}, State) ->
    {'next_state', 'wrapup', State};
wrapup('cast', {'leg_destroyed', CallId}, #state{agent_listener=AgentListener}=State) ->
    lager:debug("leg ~s destroyed", [CallId]),
    acdc_agent_listener:channel_hungup(AgentListener, CallId),
    {'next_state', 'wrapup', State};
wrapup('cast', {'originate_resp', _}, State) ->
    {'next_state', 'wrapup', State};
wrapup('cast', Evt, State) ->
    handle_event(Evt, 'wrapup', State);
wrapup({'call', From}, 'dashboard_state', State) -> dashboard_reply(From,wrapup,State);
wrapup({'call', From}, 'maintenance_state', State) -> maintenance_reply(From,wrapup,State);
wrapup({'call', From}, {'maintenance_restore', Checkpoint}, State) ->
    maintenance_restore_reply(From,Checkpoint,wrapup,State);
wrapup({'call', From}, 'status', #state{wrapup_ref=Ref}=State) ->
    {'next_state', 'wrapup', State
    ,{'reply', From, [{'state', <<"wrapup">>}
                     ,{'wrapup_left', time_left(Ref)}
                     ]}};
wrapup({'call', From}, 'current_call', #state{member_call=Call
                                             ,member_call_start=Start
                                             ,member_call_queue_id=QueueId
                                             }=State) ->
    {'next_state', 'wrapup', State
    ,{'reply', From, current_call(Call, 'wrapup', QueueId, Start)}
    };
wrapup('info', ?NEW_CHANNEL_FROM(CallId), State) ->
    lager:debug("wrapup call_from outbound: ~s", [CallId]),
    {'next_state', 'outbound', start_outbound_call_handling(CallId, State), 'hibernate'};
wrapup('info', ?NEW_CHANNEL_TO(CallId, _), State) ->
    lager:debug("wrapup call_to outbound: ~s", [CallId]),
    {'next_state', 'outbound', start_outbound_call_handling(CallId, State), 'hibernate'};
wrapup('info', {'timeout', Ref, ?WRAPUP_FINISHED}, #state{wrapup_ref=Ref
                                                         ,agent_listener=AgentListener
                                                         }=State) ->
    lager:debug("wrapup timer expired, ready for action!"),
    acdc_agent_listener:presence_update(AgentListener, ?PRESENCE_GREEN),

    apply_state_updates(clear_call(State, 'ready'));
wrapup('info', Evt, State) ->
    handle_info(Evt, 'wrapup', State).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec paused(gen_statem:event_type(), any(), state()) -> kz_types:handle_fsm_ret(state()).
paused('cast', {'sync_req', JObj}, #state{agent_listener=AgentListener
                                         ,pause_ref=Ref
                                         }=State) ->
    lager:debug("recv sync_req from ~s", [kz_json:get_value(<<"Process-ID">>, JObj)]),
    acdc_agent_listener:send_sync_resp(AgentListener, 'paused', JObj, [{<<"Time-Left">>, time_left(Ref)}]),
    {'next_state', 'paused', State};
paused('cast', {'sync_resp', _}, State) ->
    {'next_state', 'paused', State};
paused('cast', {'member_connect_req', _}, State) ->
    {'next_state', 'paused', State};
paused('cast', {'member_connect_win', JObj, 'same_node'}, #state{agent_listener=AgentListener}=State) ->
    lager:debug("agent won, but can't process this right now"),
    acdc_agent_listener:member_connect_retry(AgentListener, JObj),

    {'next_state', 'paused', State};
paused('cast', {'member_connect_satisfied', _}, State) ->
    lager:info("unexpected connect_satisfied"),
    {'next_state', 'paused', State};
paused('cast', {'originate_uuid', ACallId, ACtrlQ}, #state{agent_listener=AgentListener}=State) ->
    acdc_agent_listener:originate_uuid(AgentListener, ACallId, ACtrlQ),
    {'next_state', 'paused', State};
paused('cast', {'originate_failed', _E}, State) ->
    {'next_state', 'paused', State};
paused('cast', Evt, State) ->
    handle_event(Evt, 'paused', State);
paused({'call', From}, 'dashboard_state', State) -> dashboard_reply(From,paused,State);
paused({'call', From}, 'maintenance_state', State) -> maintenance_reply(From,paused,State);
paused({'call', From}, {'maintenance_restore', Checkpoint}, State) ->
    maintenance_restore_reply(From,Checkpoint,paused,State);
paused({'call', From}, 'status', #state{pause_ref=Ref}=State) ->
    {'next_state', 'paused', State
    ,{'reply', From, [{'state', <<"paused">>}
                     ,{'pause_left', time_left(Ref)}
                     ]}};
paused({'call', From}, 'current_call', State) ->
    {'next_state', 'paused', State, {'reply', From, 'undefined'}};
paused('info', ?NEW_CHANNEL_FROM(CallId), State) ->
    lager:debug("paused call_from outbound: ~s", [CallId]),
    {'next_state', 'outbound', start_outbound_call_handling(CallId, State), 'hibernate'};
paused('info', ?NEW_CHANNEL_TO(CallId, 'undefined'), State) ->
    lager:debug("paused call_to outbound: ~s", [CallId]),
    {'next_state', 'outbound', start_outbound_call_handling(CallId, State), 'hibernate'};
paused('info', ?NEW_CHANNEL_TO(CallId, MemberCallId), State) ->
    cancel_if_failed_originate(CallId, MemberCallId, 'paused', State);
paused('info', {'timeout', Ref, ?PAUSE_MESSAGE}, #state{pause_ref=Ref
                                                       ,agent_listener=AgentListener
                                                       }=State) when is_reference(Ref) ->
    lager:debug("pause timer expired, putting agent back into action"),

    acdc_agent_listener:update_agent_status(AgentListener, <<"resume">>),

    acdc_agent_listener:send_status_resume(AgentListener),

    acdc_agent_listener:presence_update(AgentListener, ?PRESENCE_GREEN),

    apply_state_updates(clear_call(State#state{sync_ref='undefined'}, 'ready'));
paused('info', Evt, State) ->
    handle_info(Evt, 'paused', State).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec outbound(gen_statem:event_type(), any(), state()) -> kz_types:handle_fsm_ret(state()).
outbound('cast', {'member_connect_win', JObj, 'same_node'}, #state{agent_listener=AgentListener}=State) ->
    lager:debug("agent won, but can't process this right now (on outbound call)"),
    acdc_agent_listener:member_connect_retry(AgentListener, JObj),
    {'next_state', 'outbound', State};
outbound('cast', {'member_connect_satisfied', _}, State) ->
    %% A queue offer can finish after the agent switched to a direct call.
    %% Keep tracking that call until hangup; entering wrapup here would leave
    %% no wrapup timer to restore availability or apply pending status updates.
    lager:debug("ignoring connect_satisfied while on outbound call"),
    {'next_state', 'outbound', State};
outbound('cast', {'originate_uuid', ACallId, ACtrlQ}, #state{agent_listener=AgentListener}=State) ->
    acdc_agent_listener:originate_uuid(AgentListener, ACallId, ACtrlQ),
    {'next_state', 'outbound', State};
outbound('cast', {'originate_failed', _E}, State) ->
    {'next_state', 'outbound', State};
outbound('cast', {'member_connect_req', _}, State) ->
    {'next_state', 'outbound', State};
outbound('cast', {'sync_req', JObj}, #state{agent_listener=AgentListener}=State) ->
    lager:debug("recv sync_req from ~s", [kz_json:get_value(<<"Process-ID">>, JObj)]),
    acdc_agent_listener:send_sync_resp(AgentListener, 'outbound', JObj),
    {'next_state', 'outbound', State};
outbound('cast', {'sync_resp', _}, State) ->
    {'next_state', 'outbound', State};
outbound('cast', {'leg_created', _}, State) ->
    {'next_state', 'outbound', State};
outbound('cast', {'channel_answered', _}, State) ->
    {'next_state', 'outbound', State};
outbound('cast', {'channel_replaced', _}, State) ->
    {'next_state', 'outbound', State};
outbound('cast', {'channel_bridged', _}, State) ->
    {'next_state', 'outbound', State};
outbound('cast', {'channel_unbridged', _}, State) ->
    {'next_state', 'outbound', State};
outbound('cast', {'leg_destroyed', _CallId}, State) ->
    {'next_state', 'outbound', State};
outbound('cast', {'usurp_control', _CallId}, State) ->
    {'next_state', 'outbound', State};
outbound('cast', Evt, State) ->
    handle_event(Evt, 'outbound', State);
outbound({'call', From}, 'dashboard_state', State) -> dashboard_reply(From,outbound,State);
outbound({'call', From}, 'maintenance_state', State) -> maintenance_reply(From,outbound,State);
outbound({'call', From}, {'maintenance_restore', Checkpoint}, State) ->
    maintenance_restore_reply(From,Checkpoint,outbound,State);
outbound({'call', From}, 'status', #state{wrapup_ref=Ref
                                         ,outbound_call_ids=OutboundCallIds
                                         }=State) ->
    {'next_state', 'outbound', State
    ,{'reply', From, [{'state', <<"outbound">>}
                     ,{'wrapup_left', time_left(Ref)}
                     ,{'outbound_call_id', hd(OutboundCallIds)}
                     ]}};
outbound({'call', From}, 'current_call', State) ->
    {'next_state', 'outbound', State, {'reply', From, 'undefined'}};
outbound('info', ?NEW_CHANNEL_FROM(CallId), #state{agent_listener=AgentListener
                                                  ,outbound_call_ids=OutboundCallIds
                                                  }=State) ->
    lager:debug("outbound call_from outbound: ~s", [CallId]),
    acdc_util:bind_to_call_events(CallId, AgentListener),
    {'next_state', 'outbound', State#state{outbound_call_ids=[CallId | lists:delete(CallId, OutboundCallIds)]}};
outbound('info', ?NEW_CHANNEL_TO(CallId, _), #state{outbound_call_ids=[CallId]}=State) ->
    {'next_state', 'outbound', State};
outbound('info', ?NEW_CHANNEL_TO(CallId, 'undefined'), #state{agent_listener=AgentListener
                                                             ,outbound_call_ids=OutboundCallIds
                                                             }=State) ->
    lager:debug("outbound call_to outbound: ~s", [CallId]),
    acdc_util:bind_to_call_events(CallId, AgentListener),
    {'next_state', 'outbound', State#state{outbound_call_ids=[CallId | lists:delete(CallId, OutboundCallIds)]}};
outbound('info', ?NEW_CHANNEL_TO(CallId, MemberCallId), State) ->
    cancel_if_failed_originate(CallId, MemberCallId, 'outbound', State);
outbound('info', ?DESTROYED_CHANNEL(CallId, Cause), #state{agent_listener=AgentListener
                                                          ,outbound_call_ids=OutboundCallIds
                                                          }=State) ->
    acdc_agent_listener:channel_hungup(AgentListener, CallId),
    case lists:member(CallId, OutboundCallIds) of
        'true' ->
            lager:debug("agent outbound channel ~s down: ~s", [CallId, Cause]),
            outbound_hungup(State#state{outbound_call_ids=lists:delete(CallId, OutboundCallIds)});
        'false' ->
            lager:debug("unexpected channel ~s down", [CallId]),
            {'next_state', 'outbound', State}
    end;
outbound('info', {'timeout', Ref, ?PAUSE_MESSAGE}, #state{pause_ref=Ref}=State) ->
    lager:debug("pause timer expired while outbound"),
    {'next_state', 'outbound', State#state{pause_ref='undefined'}};
outbound('info', {'timeout', WRef, ?WRAPUP_FINISHED}, #state{wrapup_ref=WRef}=State) ->
    lager:debug("wrapup timer ended while on outbound call"),
    {'next_state', 'outbound', State#state{wrapup_ref='undefined'}, 'hibernate'};
outbound('info', Evt, State) ->
    handle_info(Evt, 'outbound', State).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec handle_event(any(), atom(), state()) -> kz_types:handle_fsm_ret(state()).
handle_event({'agent_logout'}=Event, StateName, #state{agent_state_updates=Queue}=State) ->
    case valid_state_for_logout(StateName) of
        'true' -> handle_agent_logout(State);
        'false' ->
            NewQueue = [Event | Queue],
            {'next_state', StateName, State#state{agent_state_updates=NewQueue}}
    end;
handle_event({'resume'}, 'ready', State) ->
    {'next_state', 'ready', State};
handle_event({'resume'}=Event, 'paused', #state{agent_state_updates=Queue}=State) ->
    NewQueue = [Event | Queue],
    apply_state_updates(State#state{agent_state_updates=NewQueue});
handle_event({'resume'}=Event, StateName, #state{agent_state_updates=Queue}=State) ->
    lager:debug("recv resume during ~p, delaying", [StateName]),
    NewQueue = [Event | Queue],
    {'next_state', StateName, State#state{agent_state_updates=NewQueue}};
handle_event({'pause', Timeout}, 'ringing', #state{agent_listener=AgentListener
                                                  ,account_id=AccountId
                                                  ,agent_id=AgentId
                                                  ,member_call_id=CallId
                                                  ,member_call_queue_id=QueueId
                                                  }=State) ->
    %% Give up the current ringing call
    acdc_agent_listener:hangup_call(AgentListener),
    lager:debug("stopping ringing agent in order to move to pause"),
    acdc_stats:call_missed(AccountId, QueueId, AgentId, CallId, <<"agent pausing">>),
    NewFSMState = clear_call(State, 'failed'),
    %% After clearing we are basically 'ready' state, pause from that state
    handle_event({'pause', Timeout}, 'ready', NewFSMState);
handle_event({'pause', Timeout}=Event, 'ready', #state{agent_state_updates=Queue}=State) ->
    lager:debug("recv status update: pausing for up to ~b s", [Timeout]),
    NewQueue = [Event | Queue],
    apply_state_updates(State#state{agent_state_updates=NewQueue});
handle_event({'pause', Timeout}, 'paused', State) ->
    handle_event({'pause', Timeout}, 'ready', State);
handle_event({'pause', _}=Event, StateName, #state{agent_state_updates=Queue}=State) ->
    lager:debug("recv pause during ~p, delaying", [StateName]),
    NewQueue = [Event | Queue],
    {'next_state', StateName, State#state{agent_state_updates=NewQueue}};
handle_event({'end_wrapup'}=Event, 'wrapup', #state{agent_state_updates=Queue}=State) ->
    NewQueue = [Event | Queue],
    apply_state_updates(State#state{agent_state_updates=NewQueue});
handle_event({'end_wrapup'}, StateName, State) ->
    {'next_state', StateName, State};
handle_event({'add_acdc_queue', QueueId}, StateName, #state{agent_listener=AgentListener}=State) ->
    acdc_agent_listener:add_acdc_queue(AgentListener, QueueId, StateName),
    {'next_state', StateName, State};
handle_event({'rm_acdc_queue', QueueId}, StateName, #state{agent_listener=AgentListener}=State) ->
    acdc_agent_listener:rm_acdc_queue(AgentListener, QueueId),
    {'next_state', StateName, State};
handle_event({'send_availability_update', QueueId}, StateName, #state{agent_listener=AgentListener}=State) ->
    acdc_agent_listener:send_availability_update(AgentListener, StateName, QueueId),
    {'next_state', StateName, State};
handle_event({'update_presence', PresenceId, PresenceState}, 'ready', State) ->
    handle_presence_update(PresenceId, PresenceState, State),
    {'next_state', 'ready', State};
handle_event({'update_presence', _, _}=Event, StateName, #state{agent_state_updates=Queue}=State) ->
    NewQueue = [Event | Queue],
    {'next_state', StateName, State#state{agent_state_updates=NewQueue}};
handle_event({'refresh', AgentJObj}, StateName, #state{agent_listener=AgentListener}=State) ->
    acdc_agent_listener:refresh_config(AgentListener, kz_json:get_value(<<"queues">>, AgentJObj), StateName),
    {'next_state', StateName, State};
handle_event('load_endpoints', StateName, #state{agent_listener='undefined'}=State) ->
    lager:debug("agent proc not ready, not loading endpoints yet"),
    gen_statem:cast(self(), 'load_endpoints'),
    {'next_state', StateName, State};
handle_event('load_endpoints', StateName, #state{agent_id=AgentId
                                                ,account_id=AccountId
                                                ,account_db=AccountDb
                                                }=State) ->
    Setters = [{fun kapps_call:set_account_id/2, AccountId}
              ,{fun kapps_call:set_account_db/2, AccountDb}
              ,{fun kapps_call:set_resource_type/2, ?RESOURCE_TYPE_AUDIO}
              ],

    Call = kapps_call:exec(Setters, kapps_call:new()),

    %% Inform us of things with us as owner
    catch gproc:reg(?OWNER_UPDATE_REG(AccountId, AgentId)),

    case get_endpoints([], Call, AgentId, 'undefined') of
        {'error', 'no_endpoints'} -> {'next_state', StateName, State};
        {'ok', EPs} -> {'next_state', StateName, State#state{endpoints=EPs}};
        {'error', E} -> {'stop', E, State}
    end;
handle_event(Event, StateName, State) ->
    lager:debug("unhandled message in state ~s: ~p", [StateName, Event]),
    {'next_state', StateName, State}.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec handle_info(any(), atom(), state()) -> kz_types:handle_fsm_ret(state()).
handle_info({'timeout', Ref, ?CALL_CHECK_MESSAGE}, StateName, #state{call_check_ref=Ref}=State)
  when is_reference(Ref) ->
    %% A slow/broken query cannot create an unbounded number of workers. A
    %% check has one interval to finish; its late result is then discarded.
    stop_call_check(State#state.call_check),
    Next = State#state{call_check='undefined', call_check_ref=start_call_check_timer()},
    {'next_state', StateName, start_call_check(StateName, Next)};
handle_info({'agent_calls_checked', Ref, Result}, StateName,
            #state{call_check={Ref, _Pid, Monitor, Snapshot}}=State) ->
    erlang:demonitor(Monitor, ['flush']),
    Next = State#state{call_check='undefined'},
    case call_check_snapshot(StateName, Next) =:= Snapshot of
        'true' -> recover_ended_calls(Result, StateName, Next);
        'false' -> {'next_state', StateName, Next}
    end;
handle_info({'DOWN', Monitor, 'process', _Pid, _Reason}, StateName,
            #state{call_check={_Ref, _Worker, Monitor, _Snapshot}}=State) ->
    {'next_state', StateName, State#state{call_check='undefined'}};
handle_info({'agent_calls_checked', _Ref, _Result}, StateName, State) ->
    {'next_state', StateName, State};
handle_info({'timeout', _Ref, ?CALL_CHECK_MESSAGE}, StateName, State) ->
    {'next_state', StateName, State};
handle_info({'timeout', _Ref, ?SYNC_RESPONSE_MESSAGE}, StateName, State) ->
    {'next_state', StateName, State};
handle_info({'member_connect_win', _, 'different_node'}, StateName, State) ->
    lager:debug("received member_connect_win for different node (~s)", [StateName]),
    {'next_state', StateName, State};
handle_info({'endpoint_edited', EP}, StateName, #state{endpoints=EPs
                                                      ,account_id=AccountId
                                                      ,agent_id=AgentId
                                                      }=State) ->
    EPId = kz_doc:id(EP),
    case kz_json:get_value(<<"owner_id">>, EP) of
        AgentId ->
            lager:debug("device ~s edited, we're the owner, maybe adding it", [EPId]),
            {'next_state', StateName, State#state{endpoints=maybe_add_endpoint(EPId, EP, EPs, AccountId)}, 'hibernate'};
        _OwnerId ->
            lager:debug("device ~s edited, owner now ~s, maybe removing it", [EPId, _OwnerId]),
            {'next_state', StateName, State#state{endpoints=maybe_remove_endpoint(EPId, EPs, AccountId)}, 'hibernate'}
    end;
handle_info({'endpoint_deleted', EP}, StateName, #state{endpoints=EPs
                                                       ,account_id=AccountId
                                                       }=State) ->
    EPId = kz_doc:id(EP),
    lager:debug("device ~s deleted, maybe removing it", [EPId]),
    {'next_state', StateName, State#state{endpoints=maybe_remove_endpoint(EPId, EPs, AccountId)}, 'hibernate'};
handle_info({'endpoint_created', EP}, StateName, #state{endpoints=EPs
                                                       ,account_id=AccountId
                                                       ,agent_id=AgentId
                                                       }=State) ->
    EPId = kz_doc:id(EP),
    case kz_json:get_value(<<"owner_id">>, EP) of
        AgentId ->
            lager:debug("device ~s created, we're the owner, maybe adding it", [EPId]),
            {'next_state', StateName, State#state{endpoints=maybe_add_endpoint(EPId, EP, EPs, AccountId)}, 'hibernate'};
        _OwnerId ->
            lager:debug("device ~s created, owner is ~s, maybe ignoring", [EPId, _OwnerId]),

            case kz_json:get_value([<<"hotdesk">>, <<"users">>, AgentId], EP) of
                'undefined' -> {'next_state', StateName, State};
                _ ->
                    lager:debug("device ~s created, we're a hotdesk user, maybe adding it", [EPId]),
                    {'next_state', StateName, State#state{endpoints=maybe_add_endpoint(EPId, EP, EPs, AccountId)}, 'hibernate'}
            end
    end;
handle_info(?NEW_CHANNEL_FROM(_CallId), StateName, State) ->
    {'next_state', StateName, State};
handle_info(?NEW_CHANNEL_TO(_CallId, _), StateName, State) ->
    {'next_state', StateName, State};
handle_info(?DESTROYED_CHANNEL(_, _), StateName, State) ->
    {'next_state', StateName, State};
handle_info(_Info, StateName, State) ->
    lager:debug("unhandled message in state ~s: ~p", [StateName, _Info]),
    {'next_state', StateName, State}.

%%------------------------------------------------------------------------------
%% @doc This function is called by a `gen_statem' when it is about to
%% terminate. It should be the opposite of `Module:init/1' and do any
%% necessary cleaning up. When it returns, the `gen_statem' terminates with
%% Reason. The return value is ignored.
%%
%% @end
%%------------------------------------------------------------------------------
-spec terminate(any(), atom(), state()) -> 'ok'.
terminate(Reason, _StateName, #state{account_id=AccountId
                                    ,agent_id=AgentId
                                    ,agent_listener=AgentListener
                                    ,call_check_ref=CheckRef
                                    ,call_check=Check
                                    }) ->
    maybe_stop_timer(CheckRef),
    stop_call_check(Check),
    lager:debug("acdc agent statem terminating while in ~s: ~p", [_StateName, Reason]),
    maybe_stop_agent(Reason, AccountId, AgentId),
    acdc_agent_listener:presence_update(AgentListener, ?PRESENCE_RED_SOLID).

maybe_stop_agent('normal', AccountId, AgentId) ->
    stop_agent(AccountId, AgentId);
maybe_stop_agent(_Reason, _AccountId, _AgentId) ->
    'ok'.

stop_agent(AccountId, AgentId) ->
    kz_process:spawn(fun acdc_agents_sup:stop_agent/2, [AccountId, AgentId]),
    'ok'.

%%------------------------------------------------------------------------------
%% @doc Convert process state when code is changed.
%% @end
%%------------------------------------------------------------------------------
-spec code_change(any(), atom(), any(), any()) ->
          {'ok', atom(), state()} | {'error', atom()}.
code_change(_OldVsn, StateName, State, _Extra)
  when StateName =:= 'wait'; StateName =:= 'sync'; StateName =:= 'ready';
       StateName =:= 'ringing'; StateName =:= 'answered'; StateName =:= 'wrapup';
       StateName =:= 'paused'; StateName =:= 'outbound' ->
    upgrade_state(StateName, State);
code_change(_OldVsn, _StateName, _State, _Extra) ->
    {'error', 'unsupported_agent_state'}.

-spec upgrade_state(atom(), any()) -> {'ok', atom(), state()} | {'error', atom()}.
upgrade_state(StateName, #state{}=State) ->
    %% Repeating a current-layout change must not replace a timer or a probe.
    {'ok', StateName, State};
upgrade_state(StateName, State)
  when is_tuple(State), tuple_size(State) =:= #state.member_connect_id - 1,
       element(1, State) =:= 'state' ->
    %% Legacy in-flight offers have no Connect-ID. Appending an undefined ID
    %% cannot preserve their correlation; do not accept such a migration.
    %% This local check is NOT an admission fence: the deployment must also
    %% drain all nodes and prevent new work while their state is suspended.
    Candidate = list_to_tuple(tuple_to_list(State) ++ ['undefined', 'undefined', 'undefined']),
    upgrade_drained_state(StateName, Candidate);
upgrade_state(_StateName, _State) ->
    {'error', 'unsupported_agent_state_layout'}.

-spec upgrade_drained_state(atom(), state()) -> {'ok', atom(), state()} | {'error', atom()}.
upgrade_drained_state(StateName, #state{member_call='undefined'
                                       ,member_call_id='undefined'
                                       ,member_call_queue_id='undefined'
                                       ,member_call_start='undefined'
                                       ,agent_call_id='undefined'
                                       ,outbound_call_ids=[]
                                       ,monitoring='false'
                                       }=State)
  when StateName =:= 'ready'; StateName =:= 'paused' ->
    %% Preserve the complete old prefix, including pause and pending updates.
    %% Create the new timer only once conversion has been accepted.
    {'ok', StateName, State#state{call_check_ref=start_call_check_timer()}};
upgrade_drained_state(_StateName, _State) ->
    {'error', 'agent_upgrade_requires_drain'}.

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

-spec start_call_check_timer() -> reference().
start_call_check_timer() ->
    erlang:start_timer(?CALL_CHECK_INTERVAL, self(), ?CALL_CHECK_MESSAGE).

-spec call_check_snapshot(atom(), state()) -> tuple().
call_check_snapshot(StateName, #state{member_call_id=Member, member_call_start=Started
                                     ,member_connect_id=ConnectId, agent_call_id=Agent
                                     ,outbound_call_ids=Outbound}) ->
    {StateName, Member, Started, ConnectId, Agent, lists:usort(Outbound)}.

-spec checked_call_ids(atom(), state()) -> kz_term:ne_binaries().
checked_call_ids('outbound', #state{outbound_call_ids=Calls}) -> lists:usort(Calls);
checked_call_ids('answered', #state{member_call_id=Member, agent_call_id=Agent
                                   ,outbound_call_ids=Outbound}) ->
    lists:usort([C || C <- [Member, Agent | Outbound], is_binary(C), C =/= <<>>]);
checked_call_ids('ringing', #state{member_call_id=Member}) when is_binary(Member) -> [Member];
checked_call_ids(_, _) -> [].

-spec start_call_check(atom(), state()) -> state().
start_call_check(StateName, #state{account_id=AccountId}=State) ->
    case checked_call_ids(StateName, State) of
        [] -> State;
        CallIds ->
            Server = self(),
            Ref = make_ref(),
            {Pid, Monitor} = spawn_monitor(
                               fun() ->
                                   Result = acdc_callback_recovery_io:observe_channels(AccountId, CallIds),
                                   Server ! {'agent_calls_checked', Ref, Result}
                               end),
            State#state{call_check={Ref, Pid, Monitor, call_check_snapshot(StateName, State)}}
    end.

-spec stop_call_check('undefined' | tuple()) -> 'ok'.
stop_call_check('undefined') -> 'ok';
stop_call_check({_Ref, Pid, Monitor, _Snapshot}) ->
    erlang:demonitor(Monitor, ['flush']),
    exit(Pid, 'kill'),
    'ok'.

-spec recover_ended_calls(any(), atom(), state()) -> kz_types:handle_fsm_ret(state()).
recover_ended_calls({'ok', #{'complete' := 'true', 'channels' := Channels}}, StateName, State) ->
    Ended = [Id || #{'call_id' := Id, 'state' := 'terminated'} <- Channels],
    recover_ended_calls(Ended, StateName, State);
recover_ended_calls(Ended, 'outbound', #state{outbound_call_ids=Calls
                                            ,agent_listener=Listener}=State) when is_list(Ended) ->
    Removed = [C || C <- Calls, lists:member(C, Ended)],
    [acdc_agent_listener:channel_hungup(Listener, C) || C <- Removed],
    outbound_hungup(State#state{outbound_call_ids=Calls -- Removed});
recover_ended_calls(Ended, 'answered', #state{member_call_id=Member, agent_call_id=Agent
                                            ,outbound_call_ids=Outbound
                                            ,agent_listener=Listener}=State) when is_list(Ended) ->
    Removed = [C || C <- Outbound, lists:member(C, Ended)],
    [acdc_util:unbind_from_call_events(C, Listener) || C <- Removed],
    Next = State#state{outbound_call_ids=Outbound -- Removed},
    %% A transferred/held call may still have a live agent leg. Require all
    %% known queue legs to have ended before running normal hangup handling.
    QueueLegs = [C || C <- [Member, Agent], is_binary(C)],
    case QueueLegs =/= [] andalso lists:all(fun(C) -> lists:member(C, Ended) end, QueueLegs) of
        'true' -> answered('info', ?DESTROYED_CHANNEL(hd(QueueLegs), <<"NORMAL_CLEARING">>), Next);
        'false' -> {'next_state', 'answered', Next}
    end;
recover_ended_calls(Ended, 'ringing', #state{member_call_id=Member}=State) when is_list(Ended) ->
    case lists:member(Member, Ended) of
        'true' -> ringing('info', ?DESTROYED_CHANNEL(Member, <<"NORMAL_CLEARING">>), State);
        'false' -> {'next_state', 'ringing', State}
    end;
recover_ended_calls(_, StateName, State) ->
    %% Empty, partial, stale, tmpdown and failed collections never prove that
    %% a call ended. The timer will retry after connectivity is restored.
    {'next_state', StateName, State}.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec cancel_if_failed_originate(kz_term:ne_binary(), kz_term:ne_binary(), atom(), state()) ->
          {'next_state', atom(), state()}.
cancel_if_failed_originate(CallId, MemberCallId, StateName, #state{agent_listener=AgentListener
                                                                  ,member_call_id=MemberCallId1
                                                                  }=State) when MemberCallId =/= MemberCallId1 ->
    lager:debug("cancelling ~s (failed originate from queue call ~s"
               ,[CallId, MemberCallId]),
    acdc_agent_listener:channel_hungup(AgentListener, CallId),
    {'next_state', StateName, State};
cancel_if_failed_originate(_, _, StateName, State) ->
    {'next_state', StateName, State}.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec start_wrapup_timer(integer()) -> reference().
start_wrapup_timer(Timeout) when Timeout =< 0 -> start_wrapup_timer(1); % send immediately
start_wrapup_timer(Timeout) -> erlang:start_timer(Timeout*1000, self(), ?WRAPUP_FINISHED).

-spec start_sync_timer() -> reference().
start_sync_timer() ->
    erlang:start_timer(?SYNC_RESPONSE_TIMEOUT, self(), ?SYNC_RESPONSE_MESSAGE).

-spec start_sync_timer(pid()) -> reference().
start_sync_timer(P) ->
    erlang:start_timer(?SYNC_RESPONSE_TIMEOUT, P, ?SYNC_RESPONSE_MESSAGE).

-spec start_resync_timer() -> reference().
start_resync_timer() ->
    erlang:start_timer(?RESYNC_RESPONSE_TIMEOUT, self(), ?RESYNC_RESPONSE_MESSAGE).

-spec start_pause_timer(pos_integer()) -> kz_term:api_reference().
start_pause_timer('undefined') -> start_pause_timer(1);
start_pause_timer(0) -> 'undefined';
start_pause_timer(Timeout) ->
    erlang:start_timer(Timeout * 1000, self(), ?PAUSE_MESSAGE).

-spec call_id(kz_json:object()) -> kz_term:api_binary().
call_id(JObj) ->
    case kz_json:get_value(<<"Call-ID">>, JObj) of
        'undefined' -> kz_json:get_value([<<"Call">>, <<"Call-ID">>], JObj);
        CallId -> CallId
    end.

%% returns time left in seconds
-spec time_left(kz_term:api_reference() | 'false' | timeout()) -> timeout() | 'undefined'.
time_left(Ref) when is_reference(Ref) ->
    time_left(erlang:read_timer(Ref));
time_left('false') -> 'undefined';
time_left('undefined') -> 'undefined';
time_left('infinity') -> 'infinity';
time_left(Ms) when is_integer(Ms) -> Ms div 1000.

-spec clear_call(state(), atom()) -> state().
clear_call(#state{connect_failures=Fails
                 ,max_connect_failures=Max
                 ,account_id=AccountId
                 ,agent_id=AgentId
                 }=State, 'failed') when is_integer(Max), (Max - Fails) =< 1 ->
    acdc_agent_stats:agent_logged_out(AccountId, AgentId),
    agent_logout(self()),
    lager:debug("agent has failed to connect ~b times, logging out", [Fails+1]),
    clear_call(State#state{connect_failures=Fails+1}, 'paused');
clear_call(#state{connect_failures=Fails
                 ,max_connect_failures=_MaxFails
                 }=State, 'failed') ->
    lager:debug("agent has failed to connect ~b times(~b)", [Fails+1, _MaxFails]),
    clear_call(State#state{connect_failures=Fails+1}, 'ready');
clear_call(#state{statem_call_id=StateMCallId
                 ,wrapup_ref=WRef
                 ,pause_ref=PRef
                 }=State, NextState)->
    kz_log:put_callid(StateMCallId),

    ReadyForAction = NextState =/= 'wrapup'
        andalso NextState =/= 'paused',
    lager:debug("ready for action: ~s: ~s", [NextState, ReadyForAction]),

    _ = maybe_stop_timer(WRef, ReadyForAction),
    _ = maybe_stop_timer(PRef, ReadyForAction),

    State#state{wrapup_timeout = 0
               ,wrapup_ref = case ReadyForAction of 'true' -> 'undefined'; 'false' -> WRef end
               ,pause_ref = case ReadyForAction of 'true' -> 'undefined'; 'false' -> PRef end
               ,member_call = 'undefined'
               ,member_call_id = 'undefined'
               ,member_connect_id = 'undefined'
               ,member_call_start = 'undefined'
               ,member_call_queue_id = 'undefined'
               ,agent_call_id = 'undefined'
               ,queue_notifications = 'undefined'
               ,monitoring = 'false'
               }.

-spec current_call(kapps_call:call() | 'undefined', atom(), kz_term:ne_binary(), 'undefined' | kz_time:start_time()) ->
          kz_term:api_object().
current_call('undefined', _, _, _) -> 'undefined';
current_call(Call, AgentState, QueueId, Start) ->
    {CIDNumber, CIDName} = acdc_util:caller_id(Call),

    kz_json:from_list([{<<"call_id">>, kapps_call:call_id(Call)}
                      ,{<<"caller_id_name">>, CIDName}
                      ,{<<"caller_id_number">>, CIDNumber}
                      ,{<<"to">>, kapps_call:to_user(Call)}
                      ,{<<"from">>, kapps_call:from_user(Call)}
                      ,{<<"agent_state">>, kz_term:to_binary(AgentState)}
                      ,{<<"duration">>, elapsed(Start)}
                      ,{<<"queue_id">>, QueueId}
                      ]).

-spec elapsed('undefined' | kz_time:start_time()) -> kz_term:api_integer().
elapsed('undefined') -> 'undefined';
elapsed(Start) -> kz_time:elapsed_s(Start).

-spec wrapup_timer(state()) -> reference().
wrapup_timer(#state{agent_listener=AgentListener
                   ,wrapup_timeout = WrapupTimeout
                   ,account_id = AccountId
                   ,agent_id = AgentId
                   ,member_call_id = CallId
                   ,member_call_start=_Started
                   }) ->
    acdc_agent_listener:unbind_from_events(AgentListener, CallId),
    lager:info("call lasted ~b s", [elapsed(_Started)]),
    lager:info("going into a wrapup period ~p: ~s", [WrapupTimeout, CallId]),
    acdc_agent_stats:agent_wrapup(AccountId, AgentId, WrapupTimeout),
    start_wrapup_timer(WrapupTimeout).

-spec hangup_call(state(), 'member' | 'agent') -> reference().
hangup_call(#state{agent_listener=AgentListener
                  ,member_call_id=CallId
                  ,member_call_queue_id=QueueId
                  ,account_id=AccountId
                  ,agent_id=AgentId
                  ,queue_notifications=Ns
                  }=State, Initiator) ->
    acdc_stats:call_processed(AccountId, QueueId, AgentId, CallId, Initiator),

    acdc_agent_listener:channel_hungup(AgentListener, CallId),
    maybe_notify(Ns, ?NOTIFY_HANGUP, State),
    wrapup_timer(State).

-spec maybe_stop_timer(kz_term:api_reference() | 'infinity') -> 'ok'.
maybe_stop_timer('undefined') -> 'ok';
maybe_stop_timer('infinity') -> 'ok';
maybe_stop_timer(ConnRef) when is_reference(ConnRef) ->
    _ = erlang:cancel_timer(ConnRef),
    'ok'.

-spec maybe_stop_timer(kz_term:api_reference() | 'infinity', boolean()) -> 'ok'.
maybe_stop_timer(TimerRef, 'true') -> maybe_stop_timer(TimerRef);
maybe_stop_timer(_, 'false') -> 'ok'.

-spec start_outbound_call_handling(kz_term:ne_binary() | kapps_call:call(), state()) -> state().
start_outbound_call_handling(CallId, #state{agent_listener=AgentListener
                                           ,account_id=AccountId
                                           ,agent_id=AgentId
                                           ,outbound_call_ids=OutboundCallIds
                                           }=State) when is_binary(CallId) ->
    kz_log:put_callid(CallId),
    lager:debug("agent making outbound call, not receiving ACDc calls"),
    acdc_agent_listener:outbound_call(AgentListener, CallId),
    acdc_agent_stats:agent_outbound(AccountId, AgentId, CallId),
    State#state{outbound_call_ids=[CallId | lists:delete(CallId, OutboundCallIds)]};
start_outbound_call_handling(Call, State) ->
    start_outbound_call_handling(kapps_call:call_id(Call), State).

-spec outbound_hungup(state()) -> kz_types:handle_fsm_ret(state()).
outbound_hungup(#state{agent_listener=AgentListener
                      ,wrapup_ref=WRef
                      ,pause_ref=PRef
                      ,outbound_call_ids=[]
                      }=State) ->
    case time_left(WRef) of
        N when is_integer(N), N > 0 -> apply_state_updates(clear_call(State, 'wrapup'));
        _W ->
            case time_left(PRef) of
                N when is_integer(N), N > 0 -> apply_state_updates(clear_call(State, 'paused'));
                'infinity' -> apply_state_updates(clear_call(State, 'paused'));
                _P ->
                    lager:debug("wrapup left: ~p pause left: ~p", [_W, _P]),
                    acdc_agent_listener:presence_update(AgentListener, ?PRESENCE_GREEN),
                    apply_state_updates(clear_call(State, 'ready'))
            end
    end;
outbound_hungup(State) ->
    lager:debug("agent still has some outbound calls active"),
    {'next_state', 'outbound', State}.

-spec missed_reason(kz_term:ne_binary()) -> kz_term:ne_binary().
missed_reason(<<"-ERR ", Reason/binary>>) ->
    missed_reason(binary:replace(Reason, <<"\n">>, <<>>, ['global']));
missed_reason(<<"ALLOTTED_TIMEOUT">>) -> <<"timeout">>;
missed_reason(<<"NO_USER_RESPONSE">>) -> <<"rejected">>;
missed_reason(<<"CALL_REJECTED">>) -> <<"rejected">>;
missed_reason(<<"USER_BUSY">>) -> <<"rejected">>;
missed_reason(Reason) -> Reason.

-spec find_username(kz_json:object()) -> kz_term:api_binary().
find_username(EP) ->
    find_sip_username(EP, kzd_devices:sip_username(EP)).

-spec find_sip_username(kz_json:object(), kz_term:api_binary()) -> kz_term:api_binary().
find_sip_username(EP, 'undefined') -> kz_json:get_value(<<"To-User">>, EP);
find_sip_username(_EP, Username) -> Username.

-spec find_endpoint_id(kz_json:object()) -> kz_term:api_binary().
find_endpoint_id(EP) ->
    find_endpoint_id(EP, kz_doc:id(EP)).

-spec find_endpoint_id(kz_json:object(), kz_term:api_binary()) -> kz_term:api_binary().
find_endpoint_id(EP, 'undefined') -> kz_json:get_value(<<"Endpoint-ID">>, EP);
find_endpoint_id(_EP, EPId) -> EPId.

-spec monitor_endpoint(kz_json:api_object(), kz_term:ne_binary()) -> any().
monitor_endpoint('undefined', _) -> 'ok';
monitor_endpoint(EP, AccountId) ->
    Username = find_username(EP),
    %% Inform us of device changes
    catch gproc:reg(?ENDPOINT_UPDATE_REG(AccountId, find_endpoint_id(EP))),
    catch gproc:reg(?NEW_CHANNEL_REG(AccountId, Username)),
    catch gproc:reg(?DESTROYED_CHANNEL_REG(AccountId, Username)).

-spec unmonitor_endpoint(kz_json:object(), kz_term:ne_binary()) -> any().
unmonitor_endpoint(EP, AccountId) ->
    Username = find_username(EP),
    %% Inform us of device changes
    catch gproc:unreg(?ENDPOINT_UPDATE_REG(AccountId, find_endpoint_id(EP))),
    catch gproc:unreg(?NEW_CHANNEL_REG(AccountId, Username)),
    catch gproc:unreg(?DESTROYED_CHANNEL_REG(AccountId, Username)).

-spec maybe_add_endpoint(kz_term:ne_binary(), kz_json:object(), kz_json:objects(), kz_term:ne_binary()) -> any().
maybe_add_endpoint(EPId, EP, EPs, AccountId) ->
    case lists:partition(fun(E) -> find_endpoint_id(E) =:= EPId end, EPs) of
        {[], _} ->
            lager:debug("endpoint ~s not in our list, adding it", [EPId]),
            [begin monitor_endpoint(convert_to_endpoint(EP), AccountId), EP end | EPs];
        {_, _} -> EPs
    end.

-spec maybe_remove_endpoint(kz_term:ne_binary(), kz_json:objects(), kz_term:ne_binary()) -> kz_json:objects().
maybe_remove_endpoint(EPId, EPs, AccountId) ->
    case lists:partition(fun(EP) -> find_endpoint_id(EP) =:= EPId end, EPs) of
        {[], _} -> EPs; %% unknown endpoint
        {[RemoveEP], EPs1} ->
            lager:debug("endpoint ~s in our list, removing it", [EPId]),
            _ = unmonitor_endpoint(RemoveEP, AccountId),
            EPs1
    end.

-spec convert_to_endpoint(kz_json:object()) -> kz_term:api_object().
convert_to_endpoint(EPDoc) ->
    Setters = [{fun kapps_call:set_account_id/2, kz_doc:account_id(EPDoc)}
              ,{fun kapps_call:set_account_db/2, kz_doc:account_db(EPDoc)}
              ,{fun kapps_call:set_resource_type/2, ?RESOURCE_TYPE_AUDIO}
              ],

    Call = kapps_call:exec(Setters, kapps_call:new()),
    case kz_endpoint:build(kz_doc:id(EPDoc), kz_json:new(), Call) of
        {'ok', [EP|_]} -> EP;
        {'error', _} -> 'undefined'
    end.

-spec get_endpoints(kz_json:objects(), kapps_call:call(), kz_term:api_binary(), kz_term:api_binary()) ->
          {'ok', kz_json:objects()} |
          {'error', any()}.
get_endpoints(OrigEPs, Call, AgentId, QueueId) ->
    case catch acdc_util:get_endpoints(Call, AgentId) of
        [] ->
            {'error', 'no_endpoints'};
        [_|_]=EPs ->
            AccountId = kapps_call:account_id(Call),

            {Add, Rm} = changed_endpoints(OrigEPs, EPs),
            _ = [monitor_endpoint(EP, AccountId) || EP <- Add],
            _ = [unmonitor_endpoint(EP, AccountId) || EP <- Rm],

            {'ok', [kz_json:set_value([<<"Custom-Channel-Vars">>, <<"Queue-ID">>], QueueId, EP) || EP <- EPs]};
        {'EXIT', E} ->
            lager:debug("failed to load endpoints: ~p", [E]),
            {'error', E}
    end.

-spec return_to_state(non_neg_integer(), pos_integer()) -> 'paused' | 'ready'.
return_to_state(Fails, MaxFails) ->
    lager:debug("fails ~b max ~b going to pause", [Fails, MaxFails]),
    case is_integer(MaxFails)
        andalso Fails >= MaxFails of
        'true' -> 'paused';
        'false' -> 'ready'
    end.

%% {Add, Rm}
%% Orig [] Curr [] => {[], []}
%% Orig [X] Curr [X] => {[], []}
%% Orig [X] Curr [Y] => {[Y], [X]}
%% Orig [X, Y] Curr [Y] => {[], [X]}
%% Orig [X] Curr [X, Y] => {[Y], []}
changed_endpoints([], EPs) -> {EPs, []};
changed_endpoints(OrigEPs, EPs) ->
    changed_endpoints(OrigEPs, EPs, []).

changed_endpoints([], [], Add) -> {Add, []};
changed_endpoints(OrigEPs, [], Add) -> {Add, OrigEPs};
changed_endpoints(OrigEPs, [EP|EPs], Add) ->
    EPId = find_endpoint_id(EP),
    case lists:partition(fun(OEP) ->
                                 find_endpoint_id(OEP) =:= EPId
                         end, OrigEPs)
    of
        {[], _} -> changed_endpoints(OrigEPs, EPs, [EP|Add]);
        {_, RestOrigEPs} -> changed_endpoints(RestOrigEPs, EPs, Add)
    end.

maybe_notify('undefined', _, _) -> 'ok';
maybe_notify(Ns, Key, State) ->
    case kz_json:get_value(Key, Ns) of
        'undefined' ->
            case kz_json:get_value(?NOTIFY_ALL, Ns) of
                'undefined' -> 'ok';
                Url ->
                    lager:debug("send update for ~s to ~s", [?NOTIFY_ALL, Url]),
                    _ = kz_process:spawn(fun notify/4, [Url, get_method(Ns), Key, State]),
                    'ok'
            end;
        Url ->
            lager:debug("send update for ~s to ~s", [Key, Url]),
            _ = kz_process:spawn(fun notify/4, [Url, get_method(Ns), Key, State]),
            'ok'
    end.

-spec get_method(kz_json:object()) -> 'get' | 'post'.
get_method(Ns) ->
    case kz_json:get_value(<<"method">>, Ns) of
        'undefined' -> 'get';
        M -> standardize_method(kz_term:to_lower_binary(M))
    end.

-spec standardize_method(kz_term:ne_binary()) -> 'get' | 'post'.
standardize_method(<<"post">>) -> 'post';
standardize_method(_) -> 'get'.

-spec notify(kz_term:ne_binary(), 'get' | 'post', kz_term:ne_binary(), state()) -> 'ok'.
notify(Url, Method, Key, #state{account_id=AccountId
                               ,agent_id=AgentId
                               ,member_call=MemberCall
                               ,agent_call_id=AgentCallId
                               ,member_call_queue_id=QueueId
                               }) ->
    kz_log:put_callid(kapps_call:call_id(MemberCall)),
    {CIDNumber, CIDName} = acdc_util:caller_id(MemberCall),
    Data = kz_json:from_list(
             [{<<"account_id">>, AccountId}
             ,{<<"agent_id">>, AgentId}
             ,{<<"agent_call_id">>, AgentCallId}
             ,{<<"queue_id">>, QueueId}
             ,{<<"member_call_id">>, kapps_call:call_id(MemberCall)}
             ,{<<"caller_id_name">>, CIDName}
             ,{<<"caller_id_number">>, CIDNumber}
             ,{<<"call_state">>, Key}
             ,{<<"now">>, kz_time:now_s()}
             ]),
    notify(Url, Method, Data).

-spec notify(kz_term:ne_binary(), 'get' | 'post', kz_json:object()) -> 'ok'.
notify(Url, 'post', Data) ->
    notify(Url, [{"Content-Type", "application/json"}]
          ,'post', kz_json:encode(Data), []
          );
notify(Url, 'get', Data) ->
    notify(uri(Url, kz_http_util:json_to_querystring(Data))
          ,[], 'get', <<>>, []
          ).

-spec notify(kz_term:ne_binary(), kz_term:proplist(), 'get' | 'post', binary(), kz_term:proplist()) -> 'ok'.
notify(Uri, Headers, Method, Body, Opts) ->
    Options = [{'connect_timeout', 200}
              ,{'timeout', 1000}
               | Opts
              ],
    URI = kz_term:to_list(Uri),
    case kz_http:req(Method, URI, Headers, Body, Options) of
        {'ok', _Status, _ResponseHeaders, _ResponseBody} ->
            lager:debug("~s req to ~s: ~p", [Method, Uri, _Status]);
        {'error', _E} ->
            lager:debug("failed to send request to ~s: ~p", [Uri, _E])
    end.

-spec cdr_url(kz_json:object()) -> kz_term:api_binary().
cdr_url(JObj) ->
    case kz_json:get_value([<<"Notifications">>, ?NOTIFY_CDR], JObj) of
        'undefined' -> kz_json:get_ne_value(<<"CDR-Url">>, JObj);
        Url -> Url
    end.

-spec recording_url(kz_json:object()) -> kz_term:api_binary().
recording_url(JObj) ->
    case kz_json:get_value([<<"Notifications">>, ?NOTIFY_RECORDING], JObj) of
        'undefined' -> kz_json:get_ne_value(<<"Recording-URL">>, JObj);
        Url -> Url
    end.

-spec uri(kz_term:ne_binary(), iodata()) -> kz_term:ne_binary().
uri(URI, QueryString) ->
    QueryBinary = kz_term:to_binary(QueryString),
    case kz_http_util:urlsplit(URI) of
        {Scheme, Host, Path, <<>>, Fragment} ->
        kz_http_util:urlunsplit({Scheme, Host, Path, QueryBinary, Fragment});
        {Scheme, Host, Path, QS, Fragment} ->
            kz_http_util:urlunsplit({Scheme, Host, Path, <<QS/binary, "&", QueryBinary/binary>>, Fragment})
    end.

-spec apply_state_updates(state()) -> kz_types:handle_fsm_ret(state()).
apply_state_updates(#state{agent_state_updates=Q
                          ,wrapup_ref=WRef
                          ,pause_ref=PRef
                          }=State) ->
    FoldDefaultState = case time_left(WRef) of
                           N when is_integer(N), N > 0 -> 'wrapup';
                           _W ->
                               case time_left(PRef) of
                                   N when is_integer(N), N > 0 -> 'paused';
                                   'infinity' -> 'paused';
                                   _P -> 'ready'
                               end
                       end,
    lager:debug("default state for applying state updates ~s", [FoldDefaultState]),
    apply_state_updates_fold({'next_state', FoldDefaultState, State#state{agent_state_updates=[]}}, lists:reverse(Q)).

-spec apply_state_updates_fold({'next_state', atom(), state()}, list()) -> kz_types:handle_fsm_ret(state()).
apply_state_updates_fold({_, StateName, #state{account_id=AccountId
                                              ,agent_id=AgentId
                                              ,agent_listener=AgentListener
                                              ,wrapup_ref=WRef
                                              ,pause_ref=PRef
                                              }}=Acc, []) ->
    lager:debug("resulting agent state ~s", [StateName]),
    acdc_agent_listener:send_availability_update(AgentListener, StateName),
    case StateName of
        'ready' -> acdc_agent_stats:agent_ready(AccountId, AgentId);
        'wrapup' -> acdc_agent_stats:agent_wrapup(AccountId, AgentId, time_left(WRef));
        'paused' -> acdc_agent_stats:agent_paused(AccountId, AgentId, time_left(PRef))
    end,
    Acc;
apply_state_updates_fold({_, _, State}, [{'pause', Timeout}|Updates]) ->
    apply_state_updates_fold(handle_pause(Timeout, State), Updates);
apply_state_updates_fold({_, _, State}, [{'resume'}|Updates]) ->
    apply_state_updates_fold(handle_resume(State), Updates);
apply_state_updates_fold({_, 'wrapup', State}, [{'end_wrapup'}|Updates]) ->
    apply_state_updates_fold(handle_end_wrapup('ready', State), Updates);
apply_state_updates_fold({_, StateName, State}, [{'end_wrapup'}|Updates]) ->
    apply_state_updates_fold(handle_end_wrapup(StateName, State), Updates);
apply_state_updates_fold({_, _, State}, [{'agent_logout'}|_]) ->
    lager:debug("agent logging out"),
    %% Do not continue fold, stop statem
    handle_agent_logout(State);
apply_state_updates_fold({_, _, State}=Acc, [{'update_presence', PresenceId, PresenceState}|Updates]) ->
    handle_presence_update(PresenceId, PresenceState, State),
    apply_state_updates_fold(Acc, Updates).

-spec valid_state_for_logout(atom()) -> boolean().
valid_state_for_logout('ready') -> 'true';
valid_state_for_logout('wrapup') -> 'true';
valid_state_for_logout('paused') -> 'true';
valid_state_for_logout(_) -> 'false'.

-spec handle_agent_logout(state()) -> kz_types:handle_fsm_ret(state()).
handle_agent_logout(#state{account_id = AccountId
                          ,agent_id = AgentId
                          }=State) ->
    acdc_agent_stats:agent_logged_out(AccountId, AgentId),
    {'stop', 'normal', State}.

-spec handle_presence_update(kz_term:ne_binary(), kz_term:ne_binary(), state()) -> 'ok'.
handle_presence_update(PresenceId, PresenceState, #state{agent_id = AgentId
                                                        ,account_id = AccountId
                                                        }) ->
    Super = acdc_agents_sup:find_agent_supervisor(AccountId, AgentId),
    Listener = acdc_agent_sup:listener(Super),
    acdc_agent_listener:maybe_update_presence_id(Listener, PresenceId),
    acdc_agent_listener:presence_update(Listener, PresenceState).

-spec handle_resume(state()) -> kz_types:handle_fsm_ret(state()).
handle_resume(#state{agent_listener=AgentListener
                    ,pause_ref=Ref
                    }=State) ->
    lager:debug("resume received, putting agent back into action"),
    maybe_stop_timer(Ref),

    acdc_agent_listener:update_agent_status(AgentListener, <<"resume">>),

    acdc_agent_listener:send_status_resume(AgentListener),
    acdc_agent_listener:presence_update(AgentListener, ?PRESENCE_GREEN),
    {'next_state', 'ready', State#state{pause_ref='undefined'}}.

-spec handle_pause(timeout(), state()) -> kz_types:handle_fsm_ret(state()).
handle_pause(Timeout, #state{agent_listener=AgentListener}=State) ->
    acdc_agent_listener:presence_update(AgentListener, ?PRESENCE_RED_FLASH),
    State1 = case Timeout of
                 'infinity' ->
                     State#state{pause_ref='infinity'};
                 _ ->
                     Ref = start_pause_timer(Timeout),
                     State#state{pause_ref=Ref}
             end,
    {'next_state', 'paused', State1}.

-spec handle_end_wrapup(atom(), state()) -> kz_types:handle_fsm_ret(state()).
handle_end_wrapup(NextState, #state{agent_listener=AgentListener
                                   ,wrapup_ref=Ref
                                   }=State) ->
    lager:debug("end_wrapup received, cancelling wrapup timers"),
    maybe_stop_timer(Ref),
    acdc_agent_listener:presence_update(AgentListener, ?PRESENCE_GREEN),
    %% Full clear of call here to make up for missing wrapup state timeout event
    {'next_state', NextState, clear_call(State#state{wrapup_ref='undefined'}, NextState)}.
