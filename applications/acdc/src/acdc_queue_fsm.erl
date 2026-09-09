%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2012-2020, 2600Hz
%%% @doc Controls how a queue process progresses a member_call
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(acdc_queue_fsm).

-behaviour(gen_statem).

%% API
-export([start_link/4]).

%% Event injectors
-export([member_call/3
        ,member_call_cancel/2
        ,member_connect_resp/2
        ,member_accepted/2
        ,member_connect_retry/2
        ,call_event/4
        ,refresh/2
        ,current_call/1
        ,status/1
        ,maintenance_state/2

         %% Accessors
        ,cdr_url/1
        ]).

%% State handlers
-export([ready/3
        ,connect_req/3
        ,connecting/3
        ,callback_paused/3
        ,callback_waiting/3
        ]).

-ifdef(TEST).
-export([callback_commit/3, callback_observed_agent/3, registration_settings/3]).
-export([announcement_media/3
        ,announcement_event_id/1
        ,start_announcement/2
        ,callback_test_state/1
        ,callback_test_field/2
        ]).
-endif.

%% gen_statem callbacks
-export([init/1
        ,callback_mode/0
        ,terminate/3
        ,code_change/4
        ]).

-include("acdc.hrl").

-define(SERVER, ?MODULE).

%% How long should we wait for a response to our member_connect_req
-define(COLLECT_RESP_TIMEOUT, kapps_config:get_integer(?CONFIG_CAT, <<"queue_collect_resp_timeout">>, 2000)).
-define(COLLECT_RESP_MESSAGE, 'collect_timer_expired').

%% How long will the caller wait in the call queue before being bounced out
-define(CONNECTION_TIMEOUT, 1000 * ?SECONDS_IN_HOUR).
-define(CONNECTION_TIMEOUT_MESSAGE, 'connection_timer_expired').

%% How long to ring the agent before trying the next agent
-define(AGENT_RING_TIMEOUT, 5).
-define(AGENT_RING_TIMEOUT_MESSAGE, 'agent_timer_expired').

-define(ANNOUNCE_TIMEOUT, 120 * ?MILLISECONDS_IN_SECOND).
-define(ANNOUNCE_TIMEOUT_MESSAGE, 'announce_timer_expired').

-record(state, {listener_proc :: kz_term:api_pid()
               ,manager_proc :: pid()
               ,connect_resps = [] :: kz_json:objects()
               ,connect_wins = [] :: kz_json:objects()
               ,collect_ref :: kz_term:api_reference()
               ,account_id :: kz_term:ne_binary()
               ,account_db :: kz_term:ne_binary()
               ,queue_id :: kz_term:ne_binary()

               ,timer_ref :: kz_term:api_reference() % for tracking timers
               ,connection_timer_ref :: kz_term:api_reference() % how long can a caller wait in the queue
               ,agent_ring_timer_ref :: kz_term:api_reference() % how long to ring an agent before moving to the next

               ,member_call :: kapps_call:call() | 'undefined'
               ,member_call_start :: kz_time:start_time() | 'undefined'
               ,member_call_winners :: [kz_term:api_object()] %% who won the call

               ,announce_played = 'false' :: boolean()
               ,announce_id :: kz_term:api_ne_binary()
               ,announce_timer_ref :: kz_term:api_reference()
               ,pending_queue_opts = [] :: kz_term:proplist()

                                       %% Config options
               ,name :: kz_term:ne_binary()
               ,connection_timeout :: pos_integer()
               ,agent_ring_timeout = 10 :: pos_integer() % how long to ring an agent before giving up
               ,max_queue_size = 0 :: integer() % restrict the number of the queued callers
               ,ring_simultaneously = 1 :: integer() % how many agents to try ringing at a time (first one wins)
               ,enter_when_empty = true :: boolean() % if a queue is agent-less, can the caller enter?
               ,agent_wrapup_time = 0 :: integer() % forced wrapup time for an agent after a call

               ,announce :: kz_term:ne_binary() % media to play to customer when about to be connected to agent

               ,caller_exit_key :: kz_term:ne_binary() % DTMF a caller can press to leave the queue
               ,record_caller = 'false' :: boolean() % record the caller
               ,recording_url :: kz_term:api_binary() %% URL of where to POST recordings
               ,cdr_url :: kz_term:api_binary() % optional URL to request for extra CDR data

               ,notifications :: kz_term:api_object()
               %% Kept private to this worker; never serialized in Call JSON.
               ,callback_ctx = #{} :: map()
               ,callback_enabled = 'false' :: boolean()
               ,callback_menu_timeout = 30000 :: pos_integer()
               ,callback_success_timeout = 10000 :: pos_integer()
               ,attempted_agents = [] :: kz_term:ne_binaries()
               ,bridge_ctx = #{} :: map()
               }).
-type state() :: #state{}.

-define(WSD_ID, {'file', <<(get('callid'))/binary, "_queue_statem">>}).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Creates a gen_statem process which calls Module:init/1 to
%% initialize. To ensure a synchronized start-up procedure, this
%% function does not return until Module:init/1 has returned.
%% @end
%%------------------------------------------------------------------------------
-spec start_link(pid(), pid(), kz_term:ne_binary(), kz_term:ne_binary()) -> kz_types:startlink_ret().
start_link(WorkerSup, MgrPid, AccountId, QueueId) ->
    gen_statem:start_link(?SERVER, [WorkerSup, MgrPid, AccountId, QueueId], []).

-spec refresh(pid(), kz_json:object()) -> 'ok'.
refresh(ServerRef, QueueJObj) ->
    gen_statem:cast(ServerRef, {'refresh', QueueJObj}).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec member_call(pid(), kz_json:object(), gen_listener:basic_deliver()) -> 'ok'.
member_call(ServerRef, CallJObj, Delivery) ->
    gen_statem:cast(ServerRef, {'member_call', CallJObj, Delivery}).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec member_call_cancel(pid(), kz_json:object()) -> 'ok'.
member_call_cancel(ServerRef, JObj) ->
    gen_statem:cast(ServerRef, {'member_call_cancel', JObj}).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec member_connect_resp(pid(), kz_json:object()) -> 'ok'.
member_connect_resp(ServerRef, Resp) ->
    gen_statem:cast(ServerRef, {'agent_resp', Resp}).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec member_accepted(pid(), kz_json:object()) -> 'ok'.
member_accepted(ServerRef, AcceptJObj) ->
    gen_statem:cast(ServerRef, {'accepted', AcceptJObj}).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec member_connect_retry(pid(), kz_json:object()) -> 'ok'.
member_connect_retry(ServerRef, RetryJObj) ->
    gen_statem:cast(ServerRef, {'retry', RetryJObj}).

%%------------------------------------------------------------------------------
%% @doc When a queue is processing a call, it will receive call events.
%%   Pass the call event to the statem to see if action is needed (usually
%%   for hangup events).
%% @end
%%------------------------------------------------------------------------------
-spec call_event(pid(), kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> 'ok'.
call_event(ServerRef, <<"call_event">>, <<"CHANNEL_DESTROY">>, EvtJObj) ->
    gen_statem:cast(ServerRef, {'member_hungup', EvtJObj});
call_event(ServerRef, <<"call_event">>, <<"CHANNEL_BRIDGE">>, EvtJObj) ->
    gen_statem:cast(ServerRef, {'channel_bridged', EvtJObj});
call_event(ServerRef, <<"call_event">>, <<"CHANNEL_EXECUTE_COMPLETE">>, EvtJObj) ->
    case announcement_event_id(EvtJObj) of
        'undefined' -> 'ok';
        NoopId -> gen_statem:cast(ServerRef, {'announcement_complete', NoopId})
    end;
call_event(ServerRef, <<"error">>, _Name, EvtJObj) ->
    case announcement_error_id(EvtJObj) of
        'undefined' -> 'ok';
        NoopId -> gen_statem:cast(ServerRef, {'announcement_error', NoopId})
    end;
call_event(_, _E, _N, _J) -> 'ok'.

-spec current_call(pid()) -> kz_term:api_object().
current_call(ServerRef) ->
    gen_statem:call(ServerRef, 'current_call').

-spec status(pid()) -> kz_term:proplist().
status(ServerRef) ->
    gen_statem:call(ServerRef, 'status').

%% Internal read-only drain observation. A ready label/current_call response
%% alone does not exclude an outstanding callback write, bridge probe or timer.
%% This is not an admission fence, broker drain or durable callback inventory.
-spec maintenance_state(pid(), pos_integer()) -> {'ok', map()} | {'error', atom()}.
maintenance_state(ServerRef, Timeout) ->
    gen_statem:call(ServerRef, 'maintenance_state', Timeout).

-spec cdr_url(pid()) -> kz_term:api_binary().
cdr_url(ServerRef) ->
    gen_statem:call(ServerRef, 'cdr_url').

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
init([WorkerSup, MgrPid, AccountId, QueueId]) ->
    kz_log:put_callid(<<"statem_", QueueId/binary, "_", (kz_term:to_binary(self()))/binary>>),

    _ = webseq:start(?WSD_ID),
    webseq:reg_who(?WSD_ID, self(), iolist_to_binary([<<"qFSM">>, pid_to_list(self())])),

    AccountDb = kzs_util:format_account_db(AccountId),
    {'ok', QueueJObj} = kz_datamgr:open_cache_doc(AccountDb, QueueId),

    gen_statem:cast(self(), {'get_listener_proc', WorkerSup}),
    {'ok'
    ,'ready'
    ,#state{manager_proc = MgrPid
           ,account_id = AccountId
           ,account_db = AccountDb
           ,queue_id = QueueId

           ,name = kz_json:get_value(<<"name">>, QueueJObj)
           ,connection_timeout = connection_timeout(kz_json:get_integer_value(<<"connection_timeout">>, QueueJObj))
           ,agent_ring_timeout = agent_ring_timeout(kz_json:get_integer_value(<<"agent_ring_timeout">>, QueueJObj))
           ,max_queue_size = kz_json:get_integer_value(<<"max_queue_size">>, QueueJObj)
           ,ring_simultaneously = kz_json:get_value(<<"ring_simultaneously">>, QueueJObj)
           ,enter_when_empty = kz_json:is_true(<<"enter_when_empty">>, QueueJObj, 'true')
           ,agent_wrapup_time = kz_json:get_integer_value(<<"agent_wrapup_time">>, QueueJObj)
           ,announce = kz_json:get_value(<<"announce">>, QueueJObj)
           ,caller_exit_key = kz_json:get_value(<<"caller_exit_key">>, QueueJObj, <<"#">>)
           ,record_caller = kz_json:is_true(<<"record_caller">>, QueueJObj, 'false')
           ,recording_url = kz_json:get_ne_value(<<"call_recording_url">>, QueueJObj)
           ,cdr_url = kz_json:get_ne_value(<<"cdr_url">>, QueueJObj)
           ,member_call = 'undefined'
           ,member_call_winners = []

           ,notifications = kz_json:get_value(<<"notifications">>, QueueJObj)
           ,callback_enabled = kz_json:is_true([<<"callback">>, <<"enabled">>], QueueJObj, 'false')
           ,callback_menu_timeout = callback_timeout(QueueJObj, <<"menu_timeout_ms">>, 30000, 120000)
           ,callback_success_timeout = callback_timeout(QueueJObj, <<"success_timeout_ms">>, 10000, 30000)
           }
    }.

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
-spec ready(gen_statem:event_type(), any(), state()) -> kz_types:handle_fsm_ret(state()).
ready('cast', {'get_listener_proc', WorkerSup}, State) ->
    ListenerSrv = acdc_queue_worker_sup:listener(WorkerSup),
    lager:debug("got listener proc: ~p", [ListenerSrv]),
    {'next_state', 'ready', State#state{listener_proc=ListenerSrv}};
ready('cast', {'member_call', CallJObj, Delivery}, #state{listener_proc=ListenerSrv}=State) ->
    Call = kapps_call:from_json(kz_json:get_value(<<"Call">>, CallJObj)),
    CallId = kapps_call:call_id(Call),
    kz_log:put_callid(CallId),

    acdc_queue_listener:member_call(ListenerSrv, CallJObj, Delivery),

    callback_recover(CallJObj, Delivery, State#state{member_call=Call});
ready('cast', {'callback_recover', CallJObj, Delivery}, #state{member_call=Call}=State) ->
    IncomingId = kz_json:get_value([<<"Call">>, <<"Call-ID">>], CallJObj),
    case Call =/= 'undefined' andalso kapps_call:call_id(Call) =:= IncomingId of
        'true' -> callback_recover(CallJObj, Delivery, State);
        'false' -> {'keep_state', State}
    end;
ready('cast', {'check_if_next', CallJObj, Delivery}, #state{listener_proc=ListenerSrv
                                                           ,manager_proc=MgrSrv
                                                           ,member_call=Call
                                                           }=State) ->
    case acdc_queue_manager:should_ignore_member_call(MgrSrv, Call, CallJObj) of
        'false' ->
            maybe_abort_connect_req(fun maybe_delay_connect_req/3
                                   ,[CallJObj, Delivery]
                                   ,State
                                   );
        'true' ->
            lager:debug("queue mgr said to ignore this call: ~s", [kapps_call:call_id(Call)]),
            acdc_queue_listener:ignore_member_call(ListenerSrv, Call, Delivery),
            {'next_state', 'ready', clear_member_call(State)}
    end;
ready('cast', {'member_call_cancel', _}, State) ->
    %% Let check_if_next handle this call being cancelled
    {'next_state', 'ready', State};
ready('cast', {'callback_request', Request}, State) ->
    callback_request(Request, 'ready', State);
ready('cast', {'agent_resp', _Resp}, State) ->
    lager:debug("someone jumped the gun, or was slow on the draw"),
    {'next_state', 'ready', State};
ready('cast', {'accepted', _AcceptJObj}, State) ->
    lager:debug("weird to receive an acceptance"),
    {'next_state', 'ready', State};
ready('cast', {'retry', _RetryJObj}, State) ->
    lager:debug("weird to receive a retry when we're just hanging here"),
    {'next_state', 'ready', State};
ready('cast', {'member_hungup', _CallEvt}, State) ->
    {'next_state', 'ready', State};
ready('cast', Event, State) ->
    handle_event(Event, ready, State);
ready({'call', From}, 'status', #state{cdr_url=Url
                                      ,recording_url=RecordingUrl
                                      }=State) ->
    {'next_state', 'ready', State
    ,{'reply', From, [{'state', <<"ready">>}
                     ,{<<"cdr_url">>, Url}
                     ,{<<"recording_url">>, RecordingUrl}
                     ]}};
ready({'call', From}, 'current_call', State) ->
    {'next_state', 'ready', State, {'reply', From, 'undefined'}};
ready({'call', From}, Event, State) ->
    handle_sync_event(Event, From, ready, State);

ready('info', {'timeout', _, ?COLLECT_RESP_MESSAGE}, State) ->
    {'next_state', 'ready', State};
ready('info', {'timeout', _, ?ANNOUNCE_TIMEOUT_MESSAGE}, State) ->
    {'next_state', 'ready', State};
ready('info', Event, State) -> callback_native_info(Event, 'ready', State).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec connect_req(gen_statem:event_type(), any(), state()) -> kz_types:handle_fsm_ret(state()).
connect_req('cast', {'member_call', CallJObj, Delivery}, #state{listener_proc=ListenerSrv}=State) ->
    lager:debug("recv a member_call while processing a different member"),
    CallId = kz_json:get_value(<<"Call-ID">>, CallJObj),
    webseq:evt(?WSD_ID, CallId, self(), <<"member call recv while busy">>),
    acdc_queue_listener:cancel_member_call(ListenerSrv, CallJObj, Delivery),
    {'next_state', 'connect_req', State};

connect_req('cast', {'member_call_cancel', JObj}, State) ->
    handle_member_call_cancel(JObj, 'connect_req', State);
connect_req('cast', {'callback_request', Request}, State) ->
    callback_request(Request, 'connect_req', State);

connect_req('cast', {'agent_resp', Resp}, #state{connect_resps=CRs
                                                ,manager_proc=MgrSrv
                                                }=State) ->
    Agents = acdc_queue_manager:agents(MgrSrv),
    Resps = [Resp | CRs],
    State1 = State#state{connect_resps=Resps},
    case have_agents_responded(Resps, Agents) of
        'true' -> handle_agent_responses(State1);
        'false' -> {'next_state', 'connect_req', State1}
    end;

connect_req('cast', {'accepted', _}, #state{callback_ctx=#{'mode' := 'native'}}=State) ->
    %% No current winner has been dispatched. An acknowledgement from a
    %% previous selection cannot participate in the next bridge proof.
    {'next_state', 'connect_req', State};
connect_req('cast', {'accepted', _}, State) ->
    %% No selected agent is currently being rung. A late acceptance must not
    %% complete this or the next selection merely because the caller matches.
    {'next_state', 'connect_req', State};
connect_req('cast', {'retry', _RetryJObj}, State) ->
    lager:debug("recv retry response before win sent"),
    {'next_state', 'connect_req', State};

connect_req('cast', {'member_hungup', Event}, #state{callback_ctx=#{'mode' := 'native'}
                                                   ,member_call=Call}=State) ->
    case kz_json:get_value(<<"Call-ID">>, Event) =:= kapps_call:call_id(Call) of
        'true' -> callback_native_end('caller_hangup', State);
        'false' -> {'keep_state', State}
    end;
connect_req('cast', {'member_hungup', JObj}, #state{listener_proc=ListenerSrv
                                                   ,member_call=Call
                                                   ,account_id=AccountId
                                                   ,queue_id=QueueId
                                                   }=State) ->
    CallId = kapps_call:call_id(Call),
    case kz_json:get_value(<<"Call-ID">>, JObj) =:= CallId of
        'true' ->
            lager:debug("member hungup before we could assign an agent"),

            webseq:evt(?WSD_ID, self(), CallId, <<"member call finish - abandon">>),

            acdc_queue_listener:cancel_member_call(ListenerSrv, JObj),
            acdc_stats:call_abandoned(AccountId, QueueId, CallId, ?ABANDON_HANGUP),
            {'next_state', 'ready', clear_member_call(State), 'hibernate'};
        'false' ->
            lager:debug("hangup recv for ~s while processing ~s, ignoring", [kz_json:get_value(<<"Call-ID">>, JObj)
                                                                            ,CallId
                                                                            ]),
            {'next_state', 'connect_req', State}
    end;

connect_req('cast', Event, State) ->
    handle_event(Event, connect_req, State);

connect_req({'call', From}, 'status', #state{member_call=Call
                                            ,member_call_start=Start
                                            ,connection_timer_ref=ConnRef
                                            ,cdr_url=Url
                                            ,recording_url=RecordingUrl
                                            }=State) ->
    {'next_state', 'connect_req', State
    ,{'reply', From, [{<<"state">>, <<"connect_req">>}
                     ,{<<"call_id">>, kapps_call:call_id(Call)}
                     ,{<<"caller_id_name">>, kapps_call:caller_id_name(Call)}
                     ,{<<"caller_id_number">>, kapps_call:caller_id_name(Call)}
                     ,{<<"to">>, kapps_call:to_user(Call)}
                     ,{<<"from">>, kapps_call:from_user(Call)}
                     ,{<<"wait_left">>, elapsed(ConnRef)}
                     ,{<<"wait_time">>, elapsed(Start)}
                     ,{<<"cdr_url">>, Url}
                     ,{<<"recording_url">>, RecordingUrl}
                     ]}};
connect_req({'call', From}, 'current_call', #state{member_call=Call
                                                  ,member_call_start=Start
                                                  ,connection_timer_ref=ConnRef
                                                  }=State) ->
    {'next_state', 'connect_req', State
    ,{'reply', From, current_call(Call, ConnRef, Start)}
    };
connect_req({'call', From}, Event, State) ->
    handle_sync_event(Event, From, connect_req, State);

connect_req('info', {'timeout', Ref, ?COLLECT_RESP_MESSAGE}, #state{collect_ref=Ref
                                                                   ,connect_resps=[]
                                                                   ,manager_proc=MgrSrv
                                                                   ,member_call=Call
                                                                   ,listener_proc=ListenerSrv
                                                                   ,account_id=AccountId
                                                                   ,queue_id=QueueId
                                                                   }=State) ->
    maybe_stop_timer(Ref),
    case acdc_queue_manager:should_ignore_member_call(MgrSrv, Call, AccountId, QueueId) of
        'true' when is_map_key('reservation', State#state.callback_ctx) ->
            callback_native_end('caller_hangup', State);
        'true' ->
            lager:debug("queue mgr said to ignore this call: ~s, not retrying agents", [kapps_call:call_id(Call)]),
            acdc_queue_listener:finish_member_call(ListenerSrv),
            {'next_state', 'ready', clear_member_call(State), 'hibernate'};
        'false' ->
            maybe_abort_connect_req(fun maybe_delay_connect_re_req/1, [], State)
    end;
connect_req('info', {'timeout', Ref, ?COLLECT_RESP_MESSAGE}, #state{collect_ref=Ref}=State) ->
    handle_agent_responses(State);
connect_req('info', {'timeout', _, ?ANNOUNCE_TIMEOUT_MESSAGE}, State) ->
    {'next_state', 'connect_req', State};
connect_req('info', {'timeout', ConnRef, ?CONNECTION_TIMEOUT_MESSAGE}, State) ->
    handle_connection_timeout(ConnRef, State);
connect_req('info', Event, State) -> callback_native_info(Event, 'connect_req', State).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec connecting(gen_statem:event_type(), any(), state()) -> kz_types:handle_fsm_ret(state()).
connecting('cast', {'member_call', CallJObj, Delivery}, #state{listener_proc=ListenerSrv}=State) ->
    lager:debug("recv a member_call while connecting"),
    acdc_queue_listener:cancel_member_call(ListenerSrv, CallJObj, Delivery),
    {'next_state', 'connecting', State};

connecting('cast', {'member_call_cancel', JObj}, State) ->
    handle_member_call_cancel(JObj, 'connecting', State);
connecting('cast', {'callback_request', Request}, #state{callback_ctx=#{'mode' := 'resumed'}}=State) ->
    callback_request(Request, 'connecting', State);
connecting('cast', {'callback_request', Request}, State) ->
    %% An agent may already be ringing/bridging. Never acknowledge a menu
    %% pause after a connect win has crossed the worker boundary.
    callback_reject(Request, <<"busy">>),
    {'next_state', 'connecting', State};

connecting('cast', {'agent_resp', _Resp}, State) ->
    lager:debug("agent resp must have just missed cutoff"),
    {'next_state', 'connecting', State};

connecting('cast', {'announcement_complete', NoopId}, #state{announce_id=NoopId}=State) ->
    lager:debug("queue pre-connect announcement completed"),
    connect_pending_winners(State);
connecting('cast', {'announcement_complete', _OtherNoopId}, State) ->
    {'next_state', 'connecting', State};
connecting('cast', {'announcement_error', NoopId}, #state{announce_id=NoopId}=State) ->
    lager:warning("queue pre-connect announcement failed; continuing to the selected agent"),
    connect_pending_winners(State);
connecting('cast', {'announcement_error', _OtherNoopId}, State) ->
    {'next_state', 'connecting', State};

connecting('cast', {'accepted', AcceptJObj}, #state{callback_ctx=#{'mode' := 'native'}}=State) ->
    callback_accept(AcceptJObj, State);
connecting('cast', {'channel_bridged', Event}, #state{callback_ctx=#{'mode' := 'native'}}=State) ->
    callback_bridge(Event, State);

connecting('cast', {'accepted', AcceptJObj}, State) -> ordinary_accept(AcceptJObj, State);
connecting('cast', {'channel_bridged', Event}, State) -> ordinary_bridge(Event, State);

connecting('cast', {'retry', _}, #state{bridge_ctx=#{'leg' := _}}=State) -> {'keep_state', State};
connecting('cast', {'retry', _}, #state{bridge_ctx=#{'proof_status' := _}}=State) -> {'keep_state', State};
connecting('cast', {'retry', _RetryJObj}, #state{callback_ctx=#{'mode' := 'native', 'bridge_agent_leg' := _}}=State) ->
    %% A real bridge has crossed the ringing boundary. Late retry messages
    %% cannot start another agent while completion proofs are converging.
    {'keep_state', State};
connecting('cast', {'retry', RetryJObj}, #state{agent_ring_timer_ref=AgentRef
                                               ,collect_ref=CollectRef
                                               ,member_call_winners=[Winner|[]]
                                               }=State) ->
    RetryProcId = kz_json:get_value(<<"Process-ID">>, RetryJObj),
    RetryAgentId = kz_json:get_value(<<"Agent-ID">>, RetryJObj),

    case {kz_json:get_value(<<"Agent-ID">>, Winner), kz_json:get_value(<<"Process-ID">>, Winner)} of
        {RetryAgentId, RetryProcId} ->
            lager:debug("recv retry from our winning agent ~s(~s)", [RetryAgentId, RetryProcId]),

            erlang:send(self(), {'timeout', 'undefined', ?COLLECT_RESP_MESSAGE}),

            maybe_stop_timer(CollectRef),
            maybe_stop_timer(AgentRef),

            webseq:evt(?WSD_ID, webseq:process_pid(RetryJObj), self(), <<"member call - retry">>),

            {'next_state', 'connect_req', callback_reset_selection(State#state{agent_ring_timer_ref='undefined'
                                                     ,member_call_winners=[]
                                                     ,collect_ref='undefined'
                                                     })};
        {RetryAgentId, _OtherProcId} ->
            lager:debug("recv retry from monitoring proc ~s(~s)", [RetryAgentId, RetryProcId]),
            {'next_state', 'connecting', State};
        {_OtherAgentId, _OtherProcId} ->
            lager:debug("recv retry from unknown agent ~s(~s)", [RetryAgentId, RetryProcId]),
            {'next_state', 'connecting', State}
    end;
connecting('cast', {'retry', RetryJObj}, #state{member_call_winners=Winners}=State) ->
    RetryAgentId = kz_json:get_value(<<"Agent-ID">>, RetryJObj),
    RetryProcId = kz_json:get_value(<<"Process-ID">>, RetryJObj),
    lager:info("~p told to retry but we have other winners", [RetryAgentId]),
    {_Loser, Rest} = lists:partition(fun(Winner) -> {kz_json:get_value(<<"Agent-ID">>, Winner), kz_json:get_value(<<"Process-ID">>, Winner)} == {RetryAgentId, RetryProcId} end, Winners),
    {'next_state', 'connecting', callback_remove_winner(RetryAgentId, RetryProcId,
                                                        State#state{member_call_winners=Rest})};

connecting('cast', {'member_hungup', Event}, #state{callback_ctx=#{'mode' := 'native'}
                                                  ,member_call=Call}=State) ->
    case kz_json:get_value(<<"Call-ID">>, Event) =:= kapps_call:call_id(Call) of
        'true' -> callback_native_end('caller_hangup', State);
        'false' -> {'keep_state', State}
    end;
connecting('cast', {'member_hungup', CallEvt}, #state{listener_proc=ListenerSrv
                                                     ,account_id=AccountId
                                                     ,queue_id=QueueId
                                                     ,member_call=Call
                                                     }=State) ->
    case kz_json:get_value(<<"Call-ID">>, CallEvt) =:= kapps_call:call_id(Call) of
        'false' -> {'next_state', 'connecting', State};
        'true' ->
            lager:debug("caller hungup while we waited for the agent to connect"),
            acdc_queue_listener:cancel_member_call(ListenerSrv, CallEvt),
            CallId = acdc_queue_member:logical_id(Call),
            acdc_stats:call_abandoned(AccountId, QueueId, CallId, ?ABANDON_HANGUP),
            webseq:evt(?WSD_ID, self(), CallId, <<"member call - hungup">>),
            {'next_state', 'ready', clear_member_call(State), 'hibernate'}
    end;

connecting('cast', Event, State) ->
    handle_event(Event, connecting, State);

connecting({'call', From}, 'status', #state{member_call=Call
                                           ,member_call_start=Start
                                           ,connection_timer_ref=ConnRef
                                           ,agent_ring_timer_ref=AgentRef
                                           ,cdr_url=Url
                                           ,recording_url=RecordingUrl
                                           ,bridge_ctx=BridgeContext
                                           }=State) ->
    {'next_state', 'connecting', State
    ,{'reply', From, [{<<"state">>, <<"connecting">>}
                     ,{<<"call_id">>, kapps_call:call_id(Call)}
                     ,{<<"caller_id_name">>, kapps_call:caller_id_name(Call)}
                     ,{<<"caller_id_number">>, kapps_call:caller_id_name(Call)}
                     ,{<<"to">>, kapps_call:to_user(Call)}
                     ,{<<"from">>, kapps_call:from_user(Call)}
                     ,{<<"wait_left">>, elapsed(ConnRef)}
                     ,{<<"wait_time">>, elapsed(Start)}
                     ,{<<"agent_wait_left">>, elapsed(AgentRef)}
                     ,{<<"cdr_url">>, Url}
                     ,{<<"recording_url">>, RecordingUrl}
                     ,{<<"bridge_proof">>, maps:get('proof_status', BridgeContext, 'undefined')}
                     ]}};
connecting({'call', From}, 'current_call', #state{member_call=Call
                                                 ,member_call_start=Start
                                                 ,connection_timer_ref=ConnRef
                                                 }=State) ->
    {'next_state', 'connecting', State
    ,{'reply', From, current_call(Call, ConnRef, Start)}
    };
connecting({'call', From}, Event, State) ->
    handle_sync_event(Event, From, 'connecting', State);

connecting('info', {'timeout', _AgentRef, ?AGENT_RING_TIMEOUT_MESSAGE}
            ,#state{bridge_ctx=#{'leg' := _}}=State) -> {'keep_state', State};
connecting('info', {'timeout', _AgentRef, ?AGENT_RING_TIMEOUT_MESSAGE}
            ,#state{bridge_ctx=#{'proof_status' := _}}=State) -> {'keep_state', State};
connecting('info', {'timeout', _AgentRef, ?AGENT_RING_TIMEOUT_MESSAGE}
            ,#state{callback_ctx=#{'mode' := 'native', 'bridge_agent_leg' := _}}=State) -> {'keep_state', State};
connecting('info', {'timeout', AgentRef, ?AGENT_RING_TIMEOUT_MESSAGE}
            ,#state{callback_ctx=#{'mode' := 'native'}, agent_ring_timer_ref=AgentRef
                    ,listener_proc=Listener, member_call_winners=Winners}=State) ->
    lists:foreach(fun(Winner) -> acdc_queue_listener:timeout_agent(Listener, Winner) end, Winners),
    erlang:send(self(), {'timeout', 'undefined', ?COLLECT_RESP_MESSAGE}),
    maybe_stop_timer(State#state.collect_ref),
    {'next_state', 'connect_req', callback_reset_selection(State#state{agent_ring_timer_ref='undefined'
                                                                       ,collect_ref='undefined', member_call_winners=[]})};
connecting('info', {'timeout', _OtherRef, ?AGENT_RING_TIMEOUT_MESSAGE}
            ,#state{callback_ctx=#{'mode' := 'native'}}=State) -> {'keep_state', State};
connecting('info', {'timeout', AgentRef, ?AGENT_RING_TIMEOUT_MESSAGE}, #state{agent_ring_timer_ref=AgentRef
                                                                             ,member_call_winners=Winners
                                                                             ,listener_proc=ListenerSrv
                                                                             }=State) when is_reference(AgentRef) ->
    lager:debug("timed out waiting for selected agents to pick up"),
    erlang:send(self(), {'timeout', 'undefined', ?COLLECT_RESP_MESSAGE}),
    lists:foreach(fun(Winner) -> acdc_queue_listener:timeout_agent(ListenerSrv, Winner) end, Winners),
    maybe_stop_timer(State#state.collect_ref),
    {'next_state', 'connect_req', State#state{agent_ring_timer_ref='undefined'
                                             ,member_call_winners=[]
                                             ,connect_wins=[]
                                             ,bridge_ctx=#{}
                                             ,collect_ref='undefined'
                                             }};
connecting('info', {'timeout', _OtherAgentRef, ?AGENT_RING_TIMEOUT_MESSAGE}, #state{agent_ring_timer_ref=_AgentRef}=State) ->
    lager:debug("unknown agent ref: ~p known: ~p", [_OtherAgentRef, _AgentRef]),
    {'next_state', 'connecting', State};
connecting('info', {'timeout', Ref, ?ANNOUNCE_TIMEOUT_MESSAGE}, #state{announce_timer_ref=Ref
                                                                      ,member_call=Call
                                                                      }=State) ->
    lager:warning("queue pre-connect announcement timed out; flushing playback and continuing"),
    _ = kapps_call_command:flush(Call),
    connect_pending_winners(State);
connecting('info', {'timeout', _Ref, ?ANNOUNCE_TIMEOUT_MESSAGE}, State) ->
    %% cancel_timer/1 cannot retract an already-delivered timeout message.
    {'next_state', 'connecting', State};
connecting('info', {'timeout', ConnRef, ?CONNECTION_TIMEOUT_MESSAGE}, State) ->
    case State#state.bridge_ctx of
        #{'leg' := _} -> {'keep_state', State};
        #{'proof_status' := _} -> {'keep_state', State};
        _ -> handle_connection_timeout(ConnRef, State)
    end;
connecting('info', {'timeout', Ref, 'ordinary_bridge_snapshot_retry'}
            ,#state{bridge_ctx=#{'probe_retry_ref' := Ref}=Ctx}=State) ->
    ordinary_start_bridge_probe(State#state{bridge_ctx=maps:remove('probe_retry_ref', Ctx)});
connecting('info', {'timeout', _, 'ordinary_bridge_snapshot_retry'}, State) -> {'keep_state', State};
connecting('info', {'timeout', Ref, 'ordinary_bridge_proof_timeout'}, #state{bridge_ctx=#{'timer_ref' := Ref}=Ctx}=State) ->
    %% Preserve an actually bridged caller; do not claim handling, cancel its
    %% partner, or start a second originate because an AMQP proof was lost.
    lager:error("ACDC selected-agent/reciprocal-bridge proof unresolved; preserving caller without rerouting"),
    ordinary_stop_bridge_probe(Ctx),
    {'keep_state', State#state{bridge_ctx=(maps:without(['timer_ref', 'probe_ref', 'probe_pid', 'probe_retry_ref'], Ctx))#{'proof_status' => 'unresolved'}}};
connecting('info', {'timeout', _, 'ordinary_bridge_proof_timeout'}, State) -> {'keep_state', State};
connecting('info', {'timeout', Ref, 'callback_commit_retry'}
            ,#state{callback_ctx=#{'timer_ref' := Ref, 'mode' := 'native'}}=State) -> callback_complete(State);
connecting('info', Event, State) -> callback_native_info(Event, 'connecting', State).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec handle_event(any(), atom(), state()) -> kz_types:handle_fsm_ret(state()).
handle_event({'refresh', QueueJObj}, StateName, State) ->
    lager:debug("refreshing queue configs"),
    {'next_state', StateName, update_properties(QueueJObj, State), 'hibernate'};
handle_event({'ordinary_bridge_snapshot', Ref, Caller, Result}, 'connecting'
             ,#state{bridge_ctx=#{'probe_ref' := Ref}=Context, member_call=Call}=State) ->
    case Caller =:= kapps_call:call_id(Call) of
        'true' ->
            ordinary_bridge_snapshot(Result, State#state{bridge_ctx=maps:without(['probe_ref', 'probe_pid'], Context)});
        'false' -> {'keep_state', State}
    end;
handle_event({'ordinary_bridge_snapshot', _, _, _}, StateName, State) -> {'next_state', StateName, State};
handle_event({'channel_bridged', Event}, 'connecting', #state{callback_ctx=#{'mode' := 'native'}}=State) ->
    callback_bridge(Event, State);
handle_event({'channel_bridged', _}, StateName, #state{callback_ctx=#{'mode' := 'native'}}=State) ->
    {'next_state', StateName, State};
handle_event({'callback_bridge_snapshot', Ref, Result}, 'connecting'
             ,#state{callback_ctx=#{'mode' := 'native', 'bridge_probe_ref' := Ref}=Context}=State) ->
    callback_bridge_snapshot(Result, State#state{callback_ctx=maps:remove('bridge_probe_ref', Context)});
handle_event({'callback_bridge_snapshot', _, _}, StateName, State) -> {'next_state', StateName, State};
handle_event({'callback_accept_probe', Ref, Result}, _StateName
              ,#state{callback_ctx=#{'mode' := 'native', 'accept_probe_ref' := Ref}=Context}=State) ->
    Next = State#state{callback_ctx=maps:remove('accept_probe_ref', Context)},
    case Result of
        {'ok', Accepted} -> callback_accept(Accepted, Next);
        _ -> callback_native_end('agent_unavailable', Next)
    end;
handle_event({'callback_accept_probe', _, _}, StateName, State) -> {'next_state', StateName, State};
handle_event({'callback_registered', _Ref, {'ok', Doc}}, StateName, State) ->
    %% A menu may time out while an asynchronous storage write completes.
    %% A late job can only create REGISTERING, never activate/dial by itself.
    %% Cancel its deterministic record instead of logging its private payload.
    handle_event({'callback_cancel_registration', kz_doc:account_id(Doc)
                   ,kz_json:get_value(<<"queue_id">>, Doc), kz_doc:id(Doc)}, StateName, State);
handle_event({'callback_cancel_registration', AccountId, QueueId, Id}=Event, StateName, State) ->
    Result = case acdc_callback_store:get(AccountId, QueueId, Id) of
        {'ok', Current} ->
            case kz_json:get_value(<<"status">>, Current) of
                <<"registering">> -> acdc_callback_store:cancel(AccountId, QueueId, Id);
                _ -> 'ok'
            end;
        {'error', 'not_found'} -> 'ok';
        Error -> Error
    end,
    case Result of
        {'error', _} -> _ = timer:apply_after(2000, gen_statem, cast, [self(), Event]);
        _ -> 'ok'
    end,
    {'next_state', StateName, State};
handle_event({'callback_registered', _Ref, {'error', _}}, StateName, State) ->
    {'next_state', StateName, State};
handle_event(_Event, StateName, State) ->
    lager:debug("unhandled event in state ~s: ~p", [StateName, _Event]),
    {'next_state', StateName, State}.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec handle_sync_event(any(), From :: pid(), StateName :: atom(), state()) ->
          {'next_state', StateName :: atom(), state()
          ,{'reply', From :: pid(), any()}}.
handle_sync_event('maintenance_state', From, StateName, State) ->
    {'next_state', StateName, State,
     {'reply', From, maintenance_snapshot(StateName, State)}};
handle_sync_event('cdr_url', From, StateName, #state{cdr_url=Url}=State) ->
    {'next_state', StateName, State
    ,{'reply', From, Url}
    };
handle_sync_event(_Event, From, StateName, State) ->
    Reply = 'ok',
    lager:debug("unhandled sync event in ~s: ~p", [StateName, _Event]),
    {'next_state', StateName, State
    ,{'reply', From, Reply}
    }.

maintenance_snapshot('ready',
                     #state{account_id=AccountId, queue_id=QueueId,
                            listener_proc=Listener, manager_proc=Manager,
                            connect_resps=[], connect_wins=[], collect_ref='undefined',
                            timer_ref='undefined', connection_timer_ref='undefined',
                            agent_ring_timer_ref='undefined', member_call='undefined',
                            member_call_start='undefined', member_call_winners=[],
                            announce_played='false', announce_id='undefined',
                            announce_timer_ref='undefined', pending_queue_opts=[],
                            callback_ctx=Callback, attempted_agents=[], bridge_ctx=Bridge})
  when is_binary(AccountId), byte_size(AccountId)>0,
       is_binary(QueueId), byte_size(QueueId)>0,
       is_pid(Listener), is_pid(Manager),
       is_map(Callback), map_size(Callback)=:=0,
       is_map(Bridge), map_size(Bridge)=:=0 ->
    {'ok', #{account_id=>AccountId, queue_id=>QueueId, state=>'ready',
             listener=>Listener, manager=>Manager}};
maintenance_snapshot(_, _) -> {'error', 'queue_worker_not_drained'}.

%%------------------------------------------------------------------------------
%% @doc This function is called by a `gen_statem' when it is about to
%% terminate. It should be the opposite of `Module:init/1' and do any
%% necessary cleaning up. When it returns, the `gen_statem' terminates with
%% Reason. The return value is ignored.
%%
%% @end
%%------------------------------------------------------------------------------
-spec terminate(any(), atom(), state()) -> 'ok'.
terminate(_Reason, _StateName, State) ->
    maybe_stop_timer(maps:get('timer_ref', State#state.bridge_ctx, 'undefined')),
    ordinary_stop_bridge_probe(State#state.bridge_ctx),
    lager:debug("acdc queue statem terminating: ~p", [_Reason]).

%%------------------------------------------------------------------------------
%% @doc Convert process state when code is changed.
%% @end
%%------------------------------------------------------------------------------
-spec code_change(any(), atom(), state(), any()) -> {'ok', atom(), state()}.
code_change(_OldVsn, StateName, State, _Extra) ->
    {'ok', StateName, State}.

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Handle a member_call_cancel event.
%% @end
%%------------------------------------------------------------------------------
-spec handle_member_call_cancel(kz_json:object(), atom(), state()) -> kz_types:handle_fsm_ret(state()).
handle_member_call_cancel(JObj, StateName, State) ->
    case kz_json:get_ne_binary_value(<<"Reason">>, JObj) of
        <<"dtmf_exit">> -> handle_member_call_cancel_dtmf_exit(JObj, StateName, State);
        _ -> {'next_state', StateName, State}
    end.

%%------------------------------------------------------------------------------
%% @doc Handle a member_call_cancel event as a result of the caller pressing the
%% caller_exit_key.
%% @end
%%------------------------------------------------------------------------------
-spec handle_member_call_cancel_dtmf_exit(kz_json:object(), atom(), state()) -> kz_types:handle_fsm_ret(state()).
handle_member_call_cancel_dtmf_exit(JObj, StateName, #state{callback_ctx=#{'mode' := 'native'}
                                                           ,member_call=Call}=State) ->
    case kz_json:get_value(<<"Call-ID">>, JObj) =:= kapps_call:call_id(Call) of
        'true' -> callback_native_end('caller_hangup', State);
        'false' -> {'next_state', StateName, State}
    end;
handle_member_call_cancel_dtmf_exit(JObj, StateName, #state{listener_proc=ListenerSrv
                                                           ,account_id=AccountId
                                                           ,queue_id=QueueId
                                                           ,member_call=MemberCall
                                                           ,member_call_winners=Winners
                                                           ,caller_exit_key=DTMF
                                                           }=State) ->
    CallId = kz_json:get_ne_binary_value(<<"Call-ID">>, JObj),
    MemberCallId = kapps_call:call_id(MemberCall),
    case CallId of
        MemberCallId ->
            lager:debug("member pressed the exit key (~s)", [DTMF]),

            webseq:evt(?WSD_ID, self(), CallId, <<"member call finish - DTMF">>),

            acdc_queue_listener:exit_member_call(ListenerSrv, Winners),
            acdc_stats:call_abandoned(AccountId, QueueId, CallId, ?ABANDON_EXIT),
            {'next_state', 'ready', clear_member_call(State), 'hibernate'};
        _ -> {'next_state', StateName, State}
    end.

%%------------------------------------------------------------------------------
%% @doc Handle a connection timeout event as a result of the caller reaching the
%% max wait time in the queue.
%% @end
%%------------------------------------------------------------------------------
-spec handle_connection_timeout(reference(), state()) -> kz_types:handle_fsm_ret(state()).
handle_connection_timeout(Ref, #state{connection_timer_ref=Ref
                                      ,callback_ctx=#{'mode' := 'native'}}=State) ->
    callback_native_end('agent_unavailable', State);
handle_connection_timeout(ConnRef, #state{listener_proc=ListenerSrv
                                         ,connection_timer_ref=ConnRef
                                         ,account_id=AccountId
                                         ,queue_id=QueueId
                                         ,member_call=Call
                                         ,member_call_winners=Winners
                                         }=State) ->
    lager:debug("connection timeout occurred, bounce the caller out of the queue"),
    CallId = kapps_call:call_id(Call),
    webseq:evt(?WSD_ID, self(), CallId, <<"member call finish - timeout">>),

    acdc_queue_listener:timeout_member_call(ListenerSrv, Winners),
    acdc_stats:call_abandoned(AccountId, QueueId, CallId, ?ABANDON_TIMEOUT),
    {'next_state', 'ready', clear_member_call(State), 'hibernate'};
handle_connection_timeout(_StaleRef, State) -> {'keep_state', State}.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
start_collect_timer() ->
    erlang:start_timer(?COLLECT_RESP_TIMEOUT, self(), ?COLLECT_RESP_MESSAGE).

-spec connection_timeout(kz_term:api_integer()) -> pos_integer().
connection_timeout(N) when is_integer(N), N > 0 -> N * 1000;
connection_timeout(_) -> ?CONNECTION_TIMEOUT.

-spec start_connection_timer(pos_integer()) -> reference().
start_connection_timer(ConnTimeout) ->
    erlang:start_timer(ConnTimeout, self(), ?CONNECTION_TIMEOUT_MESSAGE).

-spec agent_ring_timeout(kz_term:api_integer()) -> pos_integer().
agent_ring_timeout(N) when is_integer(N), N > 0 -> N;
agent_ring_timeout(_) -> ?AGENT_RING_TIMEOUT.

-spec start_agent_ring_timer(pos_integer()) -> reference().
start_agent_ring_timer(AgentTimeout) ->
    erlang:start_timer(AgentTimeout * 1600, self(), ?AGENT_RING_TIMEOUT_MESSAGE).

-spec maybe_stop_timer(kz_term:api_reference()) -> 'ok'.
maybe_stop_timer('undefined') -> 'ok';
maybe_stop_timer(ConnRef) ->
    _ = erlang:cancel_timer(ConnRef),
    'ok'.

-spec clear_member_call(state()) -> state().
clear_member_call(#state{connection_timer_ref=ConnRef
                        ,agent_ring_timer_ref=AgentRef
                        ,announce_timer_ref=AnnounceRef
                        ,collect_ref=CollectRef
                        ,queue_id=QueueId
                        ,callback_ctx=Callback
                        }=State) ->
    kz_log:put_callid(QueueId),
    maybe_stop_timer(ConnRef),
    maybe_stop_timer(AgentRef),
    maybe_stop_timer(AnnounceRef),
    maybe_stop_timer(CollectRef),
    maybe_stop_timer(maps:get('timer_ref', Callback, 'undefined')),
    maybe_stop_timer(maps:get('lease_timer_ref', Callback, 'undefined')),
    maybe_stop_timer(maps:get('bridge_probe_ref', Callback, 'undefined')),
    maybe_stop_timer(maps:get('timer_ref', State#state.bridge_ctx, 'undefined')),
    ordinary_stop_bridge_probe(State#state.bridge_ctx),
    State#state{connect_resps=[]
               ,connect_wins=[]
               ,collect_ref='undefined'
               ,member_call='undefined'
               ,connection_timer_ref='undefined'
               ,agent_ring_timer_ref='undefined'
               ,member_call_start='undefined'
               ,member_call_winners=[]
               ,announce_played='false'
               ,announce_id='undefined'
               ,announce_timer_ref='undefined'
               ,pending_queue_opts=[]
               ,callback_ctx=#{}
               ,attempted_agents=[]
               ,bridge_ctx=#{}
               }.

update_properties(QueueJObj, State) ->
    State#state{name = kz_json:get_value(<<"name">>, QueueJObj)
               ,connection_timeout = connection_timeout(kz_json:get_integer_value(<<"connection_timeout">>, QueueJObj))
               ,agent_ring_timeout = agent_ring_timeout(kz_json:get_integer_value(<<"agent_ring_timeout">>, QueueJObj))
               ,max_queue_size = kz_json:get_integer_value(<<"max_queue_size">>, QueueJObj)
               ,ring_simultaneously = kz_json:get_value(<<"ring_simultaneously">>, QueueJObj)
               ,enter_when_empty = kz_json:is_true(<<"enter_when_empty">>, QueueJObj, 'true')
               ,agent_wrapup_time = kz_json:get_integer_value(<<"agent_wrapup_time">>, QueueJObj)
               ,announce = kz_json:get_value(<<"announce">>, QueueJObj)
               ,caller_exit_key = kz_json:get_value(<<"caller_exit_key">>, QueueJObj, <<"#">>)
               ,record_caller = kz_json:is_true(<<"record_caller">>, QueueJObj, 'false')
               ,recording_url = kz_json:get_ne_value(<<"call_recording_url">>, QueueJObj)
               ,cdr_url = kz_json:get_ne_value(<<"cdr_url">>, QueueJObj)
               ,notifications = kz_json:get_value(<<"notifications">>, QueueJObj)
               ,callback_enabled = kz_json:is_true([<<"callback">>, <<"enabled">>], QueueJObj, 'false')
               ,callback_menu_timeout = callback_timeout(QueueJObj, <<"menu_timeout_ms">>, 30000, 120000)
               ,callback_success_timeout = callback_timeout(QueueJObj, <<"success_timeout_ms">>, 10000, 30000)

                %% Changing queue strategy currently isn't feasible; definitely a TODO
                %%,strategy = get_strategy(kz_json:get_value(<<"strategy">>, QueueJObj))
               }.

-spec current_call('undefined' | kapps_call:call(), kz_term:api_reference() | timeout(), kz_time:start_time()) ->
          kz_term:api_object().
current_call('undefined', _, _) -> 'undefined';
current_call(Call, QueueTimeLeft, Start) ->
    kz_json:from_list([{<<"call_id">>, kapps_call:call_id(Call)}
                      ,{<<"caller_id_name">>, kapps_call:caller_id_name(Call)}
                      ,{<<"caller_id_number">>, kapps_call:caller_id_name(Call)}
                      ,{<<"to">>, kapps_call:to_user(Call)}
                      ,{<<"from">>, kapps_call:from_user(Call)}
                      ,{<<"wait_left">>, elapsed(QueueTimeLeft)}
                      ,{<<"wait_time">>, elapsed(Start)}
                      ]).

-spec elapsed(kz_term:api_reference() | kz_time:start_time()) -> kz_term:api_integer().
elapsed('undefined') -> 'undefined';
elapsed(Ref) when is_reference(Ref) ->
    case erlang:read_timer(Ref) of
        'false' -> 'undefined';
        Ms -> Ms div 1000
    end;
elapsed(Time) -> kz_time:elapsed_s(Time).

%%------------------------------------------------------------------------------
%% @doc Abort a queue call if agents have left the building
%% @end
%%------------------------------------------------------------------------------
-type on_continue_callback() :: fun((...) -> kz_types:handle_fsm_ret(state())).

-spec maybe_abort_connect_req(on_continue_callback(), [term()], state()) -> kz_types:handle_fsm_ret(state()).
maybe_abort_connect_req(OnContinue, CallbackArgs, #state{callback_ctx=#{'mode' := 'native'}
                                                        ,manager_proc=Manager}=State) ->
    case acdc_queue_manager:has_agents(Manager) of
        'true' -> apply(OnContinue, CallbackArgs ++ [State]);
        'false' -> callback_native_end('agent_unavailable', State)
    end;
maybe_abort_connect_req(OnContinue, CallbackArgs, #state{listener_proc=ListenerSrv
                                                        ,manager_proc=MgrSrv
                                                        ,account_id=AccountId
                                                        ,queue_id=QueueId
                                                        ,member_call=Call
                                                        }=State) ->
    case acdc_queue_manager:has_agents(MgrSrv) of
        'true' -> apply(OnContinue, CallbackArgs ++ [State]);
        'false' ->
            lager:debug("all agents have left the queue, failing call"),
            webseq:note(?WSD_ID, self(), 'right', <<"all agents have left the queue, failing call">>),
            acdc_queue_listener:exit_member_call_empty(ListenerSrv),
            acdc_stats:call_abandoned(AccountId, QueueId, kapps_call:call_id(Call), ?ABANDON_EMPTY),
            {'next_state', 'ready', clear_member_call(State), 'hibernate'}
    end.

%%------------------------------------------------------------------------------
%% @doc If some agents are busy, the manager will tell us to delay our
%% connect reqs
%%
%% @end
%%------------------------------------------------------------------------------
-spec maybe_delay_connect_req(kz_json:object(), gen_listener:basic_deliver(), state()) ->
          {'next_state', 'ready' | 'connect_req', state()}.
maybe_delay_connect_req(CallJObj, Delivery, #state{listener_proc=ListenerSrv
                                                  ,manager_proc=MgrSrv
                                                  ,connection_timeout=ConnTimeout
                                                  ,connection_timer_ref=ConnRef
                                                  ,member_call=Call
                                                  }=State) ->
    CallId = kapps_call:call_id(Call),
    case acdc_queue_manager:up_next(MgrSrv, acdc_queue_member:logical_id(Call)) of
        'true' ->
            lager:debug("member call received: ~s", [CallId]),

            webseq:note(?WSD_ID, self(), 'right', [CallId, <<": member call">>]),
            webseq:evt(?WSD_ID, CallId, self(), <<"member call received">>),

            acdc_queue_listener:member_connect_req(ListenerSrv),

            maybe_stop_timer(ConnRef), % stop the old one, maybe

            {'next_state', 'connect_req', State#state{collect_ref=start_collect_timer()
                                                     ,member_call_start=kz_time:start_time()
                                                     ,connection_timer_ref=start_connection_timer(ConnTimeout)
                                                     }};
        'false' ->
            lager:debug("connect_req delayed (not up next)"),
            _ = timer:apply_after(1000, 'gen_statem', 'cast', [self(), {'check_if_next', CallJObj, Delivery}]),
            {'next_state', 'ready', State}
    end.

-spec maybe_delay_connect_re_req(state()) -> {'next_state', 'connect_req', state()}.
maybe_delay_connect_re_req(#state{listener_proc=ListenerSrv
                                 ,manager_proc=MgrSrv
                                 ,member_call=Call
                                 }=State) ->
    case acdc_queue_manager:up_next(MgrSrv, acdc_queue_member:logical_id(Call)) of
        'true' ->
            lager:debug("done waiting, no agents responded, let's ask again"),
            webseq:note(?WSD_ID, self(), 'right', <<"no agents responded, trying again">>),
            acdc_queue_listener:member_connect_req(ListenerSrv),
            {'next_state', 'connect_req', State#state{collect_ref=start_collect_timer()}};
        'false' ->
            lager:debug("connect_re_req delayed (not up next)"),
            erlang:send_after(1000, self(), {'timeout', 'undefined', ?COLLECT_RESP_MESSAGE}),
            {'next_state', 'connect_req', State#state{collect_ref='undefined'}}
    end.

-spec accept_is_for_call(kz_json:object(), kapps_call:call()) -> boolean().
accept_is_for_call(AcceptJObj, Call) ->
    kz_json:get_value(<<"Call-ID">>, AcceptJObj) =:= kapps_call:call_id(Call).

-spec handle_agent_responses(state()) -> kz_types:handle_fsm_ret(state()).
handle_agent_responses(#state{collect_ref=Ref
                             ,manager_proc=MgrSrv
                             ,listener_proc=ListenerSrv
                             ,member_call=Call
                             ,account_id=AccountId
                             ,queue_id=QueueId
                             }=State) ->
    maybe_stop_timer(Ref),
    case acdc_queue_manager:should_ignore_member_call(MgrSrv, Call, AccountId, QueueId) of
        'true' when is_map_key('reservation', State#state.callback_ctx) ->
            callback_native_end('caller_hangup', State);
        'true' ->
            lager:debug("queue mgr said to ignore this call: ~s, not connecting to agents", [kapps_call:call_id(Call)]),
            acdc_queue_listener:finish_member_call(ListenerSrv),
            {'next_state', 'ready', clear_member_call(State)};
        'false' ->
            lager:debug("done waiting for agents to respond, picking a winner"),
            maybe_pick_winner(State)
    end.

-spec maybe_pick_winner(state()) -> kz_types:handle_fsm_ret(state()).
maybe_pick_winner(#state{connect_resps=CRs
                        ,manager_proc=Mgr
                        ,agent_ring_timeout=RingTimeout
                        ,agent_wrapup_time=AgentWrapup
                        ,cdr_url=CDRUrl
                        ,record_caller=ShouldRecord
                        ,recording_url=RecordUrl
                        ,notifications=Notifications
                        }=State) ->
    case acdc_queue_manager:pick_winner(Mgr, CRs, State#state.attempted_agents) of
        {Winners, _, Attempted} ->
            QueueOpts = props:filter_undefined(
                          [{<<"Ring-Timeout">>, RingTimeout}
                          ,{<<"Wrapup-Timeout">>, AgentWrapup}
                          ,{<<"CDR-Url">>, CDRUrl}
                          ,{<<"Record-Caller">>, ShouldRecord}
                          ,{<<"Recording-URL">>, RecordUrl}
                          ,{<<"Notifications">>, Notifications}
                          ]),

            ConnectWins = acdc_queue_strategy:offers(Winners),
            callback_prepare_winners(
              State#state{connect_resps=[]
                         ,connect_wins=ConnectWins
                         ,collect_ref='undefined'
                         ,member_call_winners=ConnectWins
                         ,pending_queue_opts=QueueOpts
                         ,attempted_agents=Attempted
                         });
        'undefined' ->
            lager:debug("no more responses to choose from"),
            maybe_abort_connect_req(fun maybe_delay_connect_re_req/1, [], State#state{connect_resps=[]})
    end.

callback_prepare_winners(#state{callback_ctx=#{'mode' := 'native'}=Context
                                ,account_id=AccountId, queue_id=QueueId, connect_wins=Wins}=State) ->
    Doc = maps:get('reservation', Context),
    case acdc_callback_store:bind_selection(AccountId, QueueId, kz_doc:id(Doc), maps:get('token', Context), Wins) of
        {'ok', Bound} ->
            Clean = callback_clear_proofs(Context),
            maybe_announce_before_connect(State#state{callback_ctx=Clean#{'reservation' => Bound}});
        _ -> callback_native_end('agent_unavailable', State)
    end;
callback_prepare_winners(State) -> maybe_announce_before_connect(State).

callback_clear_proofs(Context) ->
    maybe_stop_timer(maps:get('timer_ref', Context, 'undefined')),
    maybe_stop_timer(maps:get('bridge_probe_ref', Context, 'undefined')),
    maps:without(['accepted', 'accepted_candidates', 'bridge_agent_leg', 'accept_probe_ref', 'bridge_probe_ref', 'timer_ref'], Context).

callback_reset_selection(#state{callback_ctx=#{'mode' := 'native'}=Context}=State) ->
    State#state{callback_ctx=callback_clear_proofs(Context), connect_wins=[]};
callback_reset_selection(State) ->
    maybe_stop_timer(maps:get('timer_ref', State#state.bridge_ctx, 'undefined')),
    ordinary_stop_bridge_probe(State#state.bridge_ctx),
    State#state{connect_wins=[], bridge_ctx=#{}}.

callback_remove_winner(AgentId, ProcessId, #state{callback_ctx=#{'mode' := 'native'}=Context, connect_wins=Wins}=State) ->
    Matches = fun(Win) -> kz_json:get_value(<<"Agent-ID">>, Win) =:= AgentId
                          andalso kz_json:get_value(<<"Process-ID">>, Win) =:= ProcessId end,
    Clean = case maps:get('accepted', Context, 'undefined') of
        'undefined' -> Context;
        Accepted -> case Matches(Accepted) of 'true' -> callback_clear_proofs(Context); 'false' -> Context end
    end,
    State#state{callback_ctx=Clean, connect_wins=[Win || Win <- Wins, not Matches(Win)]};
callback_remove_winner(AgentId, ProcessId, #state{connect_wins=Wins}=State) ->
    State#state{connect_wins=[W || W <- Wins,
                                  {kz_json:get_value(<<"Agent-ID">>, W), kz_json:get_value(<<"Process-ID">>, W)}
                                      =/= {AgentId, ProcessId}]}.

%% Resolve both account media IDs and already-qualified media URIs through the
%% same path used by callflow playback. Once a call has crossed this barrier it
%% must not hear the announcement again when another agent is tried.
-spec announcement_media(boolean(), kz_term:api_binary(), kz_term:ne_binary()) ->
          'skip' | {'play', kz_term:ne_binary()}.
announcement_media('true', _Announce, _AccountId) -> 'skip';
announcement_media('false', Announce, AccountId) ->
    case kz_media_util:media_path(Announce, AccountId) of
        'undefined' -> 'skip';
        Media -> {'play', Media}
    end.

-spec maybe_announce_before_connect(state()) -> kz_types:handle_fsm_ret(state()).
maybe_announce_before_connect(#state{announce_played=Played
                                    ,announce=Announce
                                    ,account_id=AccountId
                                    ,manager_proc=Manager
                                    ,member_call=Call
                                    }=State) ->
    case announcement_media(Played, Announce, AccountId) of
        'skip' -> connect_pending_winners(State#state{announce_played='true'});
        {'play', Media} ->
            %% Stop the independent periodic producer before the flush/play
            %% pair so it cannot enqueue position media inside this barrier.
            'ok' = acdc_queue_manager:stop_announcements(
                     Manager, acdc_queue_member:logical_id(Call)),
            NoopId = start_announcement(Media, Call),
            lager:debug("waiting for queue pre-connect announcement ~s", [NoopId]),
            {'next_state', 'connecting'
            ,State#state{announce_played='true'
                        ,announce_id=NoopId
                        ,announce_timer_ref=erlang:start_timer(?ANNOUNCE_TIMEOUT
                                                              ,self()
                                                              ,?ANNOUNCE_TIMEOUT_MESSAGE)
                        }
            }
    end.

%% The queue manager puts the caller into endless hold playback before the FSM
%% starts selecting agents. Publish one atomic flush-and-play queue command so
%% the announcement cannot remain behind MOH or be reordered between separate
%% AMQP messages. The terminal noop is the asynchronous FSM barrier.
-spec start_announcement(kz_term:ne_binary(), kapps_call:call()) -> kz_term:ne_binary().
start_announcement(Media, Call) ->
    NoopId = kapps_call_command:noop_id(),
    Commands = [kz_json:from_list([{<<"Application-Name">>, <<"noop">>}
                                  ,{<<"Call-ID">>, kapps_call:call_id(Call)}
                                  ,{<<"Msg-ID">>, NoopId}
                                  ])
               ,kapps_call_command:play_command(Media, Call)
               ],
    Command = [{<<"Application-Name">>, <<"queue">>}
              ,{<<"Insert-At">>, <<"flush">>}
              ,{<<"Commands">>, Commands}
              ],
    'ok' = kapps_call_command:send_command(Command, Call),
    NoopId.

-spec connect_pending_winners(state()) -> kz_types:handle_fsm_ret(state()).
connect_pending_winners(#state{listener_proc=ListenerSrv
                              ,connect_wins=ConnectWins
                              ,pending_queue_opts=QueueOpts
                              ,agent_ring_timeout=RingTimeout
                              ,announce_timer_ref=AnnounceRef
                              }=State) ->
    maybe_stop_timer(AnnounceRef),
    lists:foreach(
      fun(Winner) ->
              lager:debug("sending win to ~s(~s)", [kz_json:get_value(<<"Agent-ID">>, Winner)
                                                   ,kz_json:get_value(<<"Process-ID">>, Winner)
                                                   ]),
              acdc_queue_listener:member_connect_win(ListenerSrv, Winner, QueueOpts)
      end,
      acdc_queue_strategy:unique_agents(ConnectWins)),
    {'next_state', 'connecting'
    ,State#state{agent_ring_timer_ref=start_agent_ring_timer(RingTimeout)
                ,announce_id='undefined'
                ,announce_timer_ref='undefined'
                ,pending_queue_opts=[]
                }
    }.

-spec announcement_event_id(kz_call_event:payload()) -> kz_term:api_ne_binary().
announcement_event_id(EvtJObj) ->
    case kz_call_event:application_name(EvtJObj) of
        <<"noop">> -> kz_call_event:application_response(EvtJObj);
        _ -> 'undefined'
    end.

-spec announcement_error_id(kz_call_event:payload()) -> kz_term:api_ne_binary().
announcement_error_id(EvtJObj) ->
    Request = kz_call_event:request(EvtJObj),
    case kz_call_event:application_name(Request) of
        <<"noop">> -> kz_api:msg_id(Request);
        _ -> 'undefined'
    end.

-spec have_agents_responded(kz_json:objects(), kz_term:ne_binaries()) -> boolean().
have_agents_responded(Resps, Agents) ->
    lists:foldl(fun filter_agents/2, Agents, Resps) =:= [].

-spec filter_agents(kz_json:object(), kz_term:ne_binaries()) -> kz_term:ne_binaries().
filter_agents(Resp, AgentsAcc) ->
    lists:delete(kz_json:get_value(<<"Agent-ID">>, Resp), AgentsAcc).

%% Callback menu ownership is serialized with agent selection in this FSM.
%% Reject once a win was sent: cancelling a ringing agent is not proof that a
%% bridge cannot already be completing on a remote media node.
callback_request(Request, StateName, #state{callback_ctx=#{'mode' := 'resumed'}=Context}=State) ->
    case kz_json:get_value(<<"Operation">>, Request) =:= <<"resume">> andalso callback_matches(Request, Context) of
        'true' ->
            callback_optional_reply(Request, <<"resumed">>, Context),
            {'next_state', StateName, State};
        'false' when StateName =:= 'connecting' ->
            callback_reject(Request, <<"busy">>), {'next_state', StateName, State};
        'false' -> callback_pause_request(Request, StateName, State)
    end;
callback_request(Request, StateName, State) -> callback_pause_request(Request, StateName, State).

callback_pause_request(Request, StateName, #state{member_call=Call, callback_enabled=Enabled
                                          ,connect_wins=Wins, member_call_winners=Winners
                                          ,manager_proc=Manager, collect_ref=CollectRef}=State) ->
    Scoped = Call =/= 'undefined' andalso kapi_acdc_callback:request_v(Request)
        andalso State#state.account_id =:= kz_json:get_value(<<"Account-ID">>, Request)
        andalso State#state.queue_id =:= kz_json:get_value(<<"Queue-ID">>, Request)
        andalso acdc_queue_member:logical_id(Call) =:= kz_json:get_value(<<"Call-ID">>, Request),
    case {kz_json:get_value(<<"Operation">>, Request), Enabled, Call =/= 'undefined'
         ,Wins =:= [] andalso Scoped, Winners =:= []} of
        {<<"pause">>, 'true', 'true', 'true', 'true'} ->
            PauseId = kz_binary:rand_hex(24),
            Timer = erlang:start_timer(State#state.callback_menu_timeout + 5000, self(), 'callback_menu_deadline'),
            Context = #{'request' => Request, 'pause_id' => PauseId, 'previous_state' => StateName
                       ,'timer_ref' => Timer, 'registration_ref' => 'undefined'
                       ,'mode' => 'menu'},
            maybe_stop_timer(CollectRef),
            acdc_queue_manager:stop_announcements(Manager, acdc_queue_member:logical_id(Call)),
            callback_reply(Request, <<"paused">>, [{<<"Pause-ID">>, PauseId}]),
            {'next_state', 'callback_paused', State#state{callback_ctx=Context
                                                       ,connect_resps=[], collect_ref='undefined'}};
        {_, 'false', _, _, _} ->
            callback_reject(Request, <<"disabled">>), {'next_state', StateName, State};
        _ -> callback_reject(Request, <<"busy">>), {'next_state', StateName, State}
    end.

-spec callback_paused(gen_statem:event_type(), any(), state()) -> kz_types:handle_fsm_ret(state()).
callback_paused('cast', {'callback_request', Request}, #state{callback_ctx=Context}=State) ->
    Operation = kz_json:get_value(<<"Operation">>, Request),
    case {Operation, callback_matches(Request, Context)} of
        {<<"pause">>, 'true'} ->
            callback_reply(Request, <<"paused">>, [{<<"Pause-ID">>, maps:get('pause_id', Context)}]),
            {'keep_state', State};
        {<<"register">>, 'true'} -> callback_register(Request, State);
        {<<"resume">>, 'true'} -> callback_resume(Request, State);
        {<<"abandon">>, 'true'} -> callback_abandon(Request, State);
        _ -> callback_reject(Request, <<"stale_request">>), {'keep_state', State}
    end;
callback_paused('cast', {'callback_registered', Ref, Result}
                ,#state{callback_ctx=#{'registration_ref' := Ref}}=State) ->
    callback_registration_result(Result, State);
callback_paused('cast', {'member_hungup', Event}, #state{member_call=Call}=State) ->
    case kz_json:get_value(<<"Call-ID">>, Event) =:= kapps_call:call_id(Call) of
        'true' -> callback_abandon('undefined', State);
        'false' -> {'keep_state', State}
    end;
callback_paused('cast', {'member_call_cancel', Event}, #state{member_call=Call}=State) ->
    case kz_json:get_value(<<"Call-ID">>, Event) =:= acdc_queue_member:logical_id(Call) of
        'true' -> callback_abandon('undefined', State);
        'false' -> {'keep_state', State}
    end;
callback_paused('cast', {'member_call', JObj, Delivery}, #state{listener_proc=Listener}=State) ->
    acdc_queue_listener:cancel_member_call(Listener, JObj, Delivery), {'keep_state', State};
callback_paused('cast', Event, State) -> handle_event(Event, 'callback_paused', State);
callback_paused('info', {'timeout', Ref, 'callback_menu_deadline'}
                ,#state{callback_ctx=#{'timer_ref' := Ref}}=State) -> callback_resume('undefined', State);
callback_paused('info', {'timeout', Ref, ?CONNECTION_TIMEOUT_MESSAGE}
                ,#state{connection_timer_ref=Ref}=State) -> callback_abandon('undefined', State);
callback_paused('info', _, State) -> {'keep_state', State};
callback_paused({'call', From}, 'status', State) -> callback_status(From, <<"callback_menu">>, State);
callback_paused({'call', From}, 'current_call', #state{member_call=Call}=State) ->
    {'keep_state', State, [{'reply', From, callback_current_call(Call, <<"callback_menu">>)}]};
callback_paused({'call', From}, Request, State) -> handle_sync_event(Request, From, 'callback_paused', State).

callback_register(Request, #state{callback_ctx=Context, member_call=Call
                                  ,account_id=AccountId, queue_id=QueueId}=State) ->
    case maps:get('registration_ref', Context) of
        'undefined' ->
            Owner = self(), Ref = make_ref(),
            Number = kz_json:get_value(<<"Number">>, Request),
            PauseId = maps:get('pause_id', Context),
            %% Storage/routing-policy work must not block hangup/menu timers.
            %% This job may CREATE but may never ACTIVATE the reservation.
            _ = spawn(fun() ->
                Result = try callback_create(AccountId, QueueId, Call, Number, Request, PauseId)
                         catch _:_ -> {'error', 'storage_failed'} end,
                gen_statem:cast(Owner, {'callback_registered', Ref, Result})
            end),
            {'keep_state', State#state{callback_ctx=Context#{'registration_ref' => Ref
                                                           ,'registration_request' => Request}}};
        _ ->
            %% Retransmission is acknowledged by the original write's result.
            {'keep_state', State}
    end.

callback_create(AccountId, QueueId, Call, Number, Request, PauseId) ->
    case kz_datamgr:open_doc(kzs_util:format_account_db(AccountId), QueueId) of
        {'ok', Queue} ->
            case kz_json:is_true([<<"callback">>, <<"enabled">>], Queue, 'false')
                andalso callback_number_allowed(AccountId, Queue, Call, Number) of
                'false' -> {'error', 'disabled'};
                'true' ->
                    case {acdc_callback_policy:authorize_registration(AccountId, Queue, Number)
                         ,acdc_queue_member:registration_metadata(Call)} of
                        {{'ok', Authority}, {'ok', Metadata}} ->
                            case acdc_callback_store:create(AccountId, QueueId, acdc_queue_member:logical_id(Call)
                                                            ,registration_settings(Queue, Number, Metadata), Authority) of
                                {'ok', Created} ->
                                    acdc_callback_store:bind_registration(AccountId, QueueId, kz_doc:id(Created)
                                                                          ,kz_json:get_value(<<"Request-ID">>, Request)
                                                                          ,PauseId, kz_json:get_value(<<"Server-ID">>, Request));
                                Error -> Error
                            end;
                        {{'error', _}, _} -> {'error', 'policy_denied'};
                        _ -> {'error', 'storage_failed'}
                    end
            end;
        _ -> {'error', 'storage_failed'}
    end.

%% Keep registration_metadata's admitted call language. Policy and retry limits
%% use current queue settings, but a queue edit must not relocalize this caller.
-spec registration_settings(kz_json:object(), binary(), kz_json:object()) -> kz_json:object().
registration_settings(Queue, Number, Metadata) ->
    kz_json:set_values([{<<"number">>, Number}
                       ,{<<"max_attempts">>, kz_json:get_value([<<"callback">>, <<"max_attempts">>], Queue, 3)}
                       ,{<<"retry_delay">>, kz_json:get_value([<<"callback">>, <<"retry_delay">>], Queue, 60)}
                       ,{<<"ttl">>, kz_json:get_value([<<"callback">>, <<"ttl">>], Queue, 3600)}], Metadata).

callback_number_allowed(AccountId, Queue, Call, Number) ->
    kz_json:is_true([<<"callback">>, <<"allow_alternate_number">>], Queue, 'false')
        orelse try
            CallerNumber = kapps_call:caller_id_number(Call),
            is_binary(CallerNumber) andalso byte_size(CallerNumber) > 0
                andalso knm_converters:normalize(Number, AccountId) =:= knm_converters:normalize(CallerNumber, AccountId)
        catch _:_ -> 'false' end.

callback_registration_result({'ok', Doc}, #state{account_id=AccountId, queue_id=QueueId
                                                ,callback_ctx=Context
                                                ,connection_timer_ref=ConnectionRef}=State) ->
    Request = maps:get('registration_request', Context),
    case acdc_callback_store:activate(AccountId, QueueId, kz_doc:id(Doc)) of
        {'ok', Active} ->
            maybe_stop_timer(maps:get('timer_ref', Context)),
            maybe_stop_timer(ConnectionRef),
            Timer = erlang:start_timer(State#state.callback_success_timeout + 5000, self(), 'callback_detach_deadline'),
            callback_reply(Request, <<"registered">>, [{<<"Pause-ID">>, maps:get('pause_id', Context)}
                                                       ,{<<"Callback-ID">>, kz_doc:id(Active)}]),
            {'next_state', 'callback_waiting'
            ,State#state{connection_timer_ref='undefined'
                        ,callback_ctx=Context#{'reservation' => Active, 'mode' => 'awaiting_destroy'
                                              ,'timer_ref' => Timer}}};
        _ -> callback_registration_result({'error', 'storage_failed'}, State)
    end;
callback_registration_result({'error', Reason}, #state{callback_ctx=Context}=State) ->
    WireReason = case Reason of 'policy_denied' -> <<"policy_denied">>;
                               'disabled' -> <<"disabled">>;
                               _ -> <<"storage_failed">> end,
    callback_reject(maps:get('registration_request', Context), WireReason),
    %% The caller owns the resume handshake after a rejection. Preserve this
    %% pause until its correlated resume arrives (or the existing menu timer
    %% expires), otherwise the required resumed acknowledgement can be lost.
    {'keep_state', State#state{callback_ctx=Context#{'registration_ref' => 'undefined'}}}.

callback_resume(Request, #state{callback_ctx=Context, member_call=Call
                               ,account_id=AccountId, queue_id=QueueId
                               ,manager_proc=Manager, listener_proc=Listener}=State) ->
    case callback_cancel_waiting(State) of
        'ok' ->
            maybe_stop_timer(maps:get('timer_ref', Context)),
            callback_optional_reply(Request, <<"resumed">>, Context),
            acdc_queue_manager:resume_announcements(Manager, acdc_queue_member:logical_id(Call)),
            Restored = State#state{callback_ctx=callback_resumed_context(Context)},
            case maps:get('previous_state', Context) of
                'ready' ->
                    %% The manager validates the outer member-message scope,
                    %% not only the account embedded in Call. Preserve it when
                    %% a cancelled or unavailable menu resumes the live queue.
                    JObj = kz_json:from_list([{<<"Account-ID">>, AccountId}
                                             ,{<<"Queue-ID">>, QueueId}
                                             ,{<<"Call">>, kapps_call:to_json(Call)}]),
                    Delivery = acdc_queue_listener:delivery(Listener),
                    gen_statem:cast(self(), {'check_if_next', JObj, Delivery}),
                    {'next_state', 'ready', Restored};
                'connect_req' ->
                    acdc_queue_listener:member_connect_req(Listener),
                    {'next_state', 'connect_req', Restored#state{collect_ref=start_collect_timer()}}
            end;
        {'error', _} ->
            %% Do not restore agent eligibility while durable cancellation is
            %% uncertain. A later timer retries, without creating a callback.
            Timer = erlang:start_timer(2000, self(), 'callback_menu_deadline'),
            {'next_state', 'callback_paused', State#state{callback_ctx=Context#{'timer_ref' => Timer}}}
    end.

callback_abandon(Request, #state{callback_ctx=Context, account_id=AccountId, queue_id=QueueId
                                ,member_call=Call, listener_proc=Listener}=State) ->
    callback_cancel_worker(Context),
    case acdc_callback_store:find(AccountId, QueueId, acdc_queue_member:logical_id(Call)) of
        {'error', 'not_found'} ->
            callback_optional_reply(Request, <<"abandoned">>, Context),
            acdc_queue_listener:exit_member_call(Listener, []),
            {'next_state', 'ready', clear_member_call(State)};
        {'ok', Doc} ->
            case lists:member(kz_json:get_value(<<"status">>, Doc),
                              [<<"completed">>, <<"cancelled">>, <<"expired">>, <<"failed">>]) of
                'true' -> callback_abandon_saved(Request, Doc, State);
                'false' ->
                    case acdc_callback_store:cancel(AccountId, QueueId, kz_doc:id(Doc)) of
                        {'ok', Saved} -> callback_abandon_saved(Request, Saved, State);
                        _ -> callback_abandon_later(State)
                    end
            end;
        _ -> callback_abandon_later(State)
    end.

callback_abandon_saved(Request, Doc, #state{callback_ctx=Context}=State) ->
    Next = State#state{callback_ctx=Context#{'reservation' => Doc, 'mode' => 'reconciliation'}},
    case lists:member(kz_json:get_value(<<"status">>, Doc),
                      [<<"completed">>, <<"cancelled">>, <<"expired">>, <<"failed">>]) of
        'true' ->
            callback_optional_reply(Request, <<"abandoned">>, Context),
            callback_finish_terminal(Next);
        'false' ->
            %% CANCELLING still owns the delivery. Run the normal channel and
            %% originate reconciler, including when its former worker died.
            callback_schedule(Next, 1000)
    end.

callback_abandon_later(#state{callback_ctx=Context}=State) ->
    maybe_stop_timer(maps:get('timer_ref', Context, 'undefined')),
    Timer = erlang:start_timer(2000, self(), 'callback_abandon_retry'),
    {'next_state', 'callback_waiting', State#state{callback_ctx=Context#{'mode' => 'abandoning'
                                                                      ,'timer_ref' => Timer}}}.

callback_cancel_waiting(#state{account_id=AccountId, queue_id=QueueId, member_call=Call}) ->
    case acdc_callback_store:find(AccountId, QueueId, acdc_queue_member:logical_id(Call)) of
        {'error', 'not_found'} -> 'ok';
        {'ok', Doc} ->
            case acdc_callback_store:cancel(AccountId, QueueId, kz_doc:id(Doc)) of
                {'ok', Cancelled} ->
                    case kz_json:get_value(<<"status">>, Cancelled) of
                        <<"cancelled">> -> 'ok';
                        _ -> {'error', 'reconciliation_required'}
                    end;
                Error -> Error
            end;
        Error -> Error
    end.

callback_matches(Request, Context) ->
    Original = maps:get('request', Context),
    lists:all(fun(Key) -> kz_json:get_value(Key, Request) =:= kz_json:get_value(Key, Original) end
              ,[<<"Account-ID">>, <<"Queue-ID">>, <<"Call-ID">>, <<"Request-ID">>, <<"Server-ID">>])
        andalso (kz_json:get_value(<<"Operation">>, Request) =:= <<"pause">>
                 orelse kz_json:get_value(<<"Pause-ID">>, Request) =:= maps:get('pause_id', Context))
        andalso callback_matches_ticket(Request, Context).

callback_matches_ticket(Request, Context) ->
    case kz_json:get_value(<<"Callback-ID">>, Request) of
        'undefined' -> 'true';
        Id ->
            case maps:get('reservation', Context, 'undefined') of
                'undefined' -> Id =:= maps:get('callback_id', Context, 'undefined');
                Doc -> Id =:= kz_doc:id(Doc)
            end
    end.

callback_resumed_context(Context) ->
    CallbackId = case maps:get('reservation', Context, 'undefined') of
        'undefined' -> maps:get('callback_id', Context, 'undefined');
        Doc -> kz_doc:id(Doc)
    end,
    (maps:with(['request', 'pause_id'], Context))#{'mode' => 'resumed', 'callback_id' => CallbackId}.

callback_reject(Request, Reason) -> callback_reply(Request, <<"rejected">>, [{<<"Failure-Reason">>, Reason}]).
callback_optional_reply('undefined', _, _) -> 'ok';
callback_optional_reply(Request, Status, Context) ->
    callback_reply(Request, Status, [{<<"Pause-ID">>, maps:get('pause_id', Context)}]).
callback_reply(Request, Status, Extra) ->
    Keys = [<<"Account-ID">>, <<"Queue-ID">>, <<"Call-ID">>, <<"Request-ID">>, <<"Operation">>],
    Headers = [{Key, kz_json:get_value(Key, Request)} || Key <- Keys],
    Payload = Extra ++ [{<<"Status">>, Status} | Headers] ++ kz_api:default_headers(?APP_NAME, ?APP_VERSION),
    kapi_acdc_callback:publish_response(kz_json:get_value(<<"Server-ID">>, Request), Payload).

callback_status(From, Phase, State) ->
    {'keep_state', State, [{'reply', From, [{<<"state">>, Phase}]}]}.
callback_current_call(Call, Phase) ->
    kz_json:from_list([{<<"call_id">>, acdc_queue_member:logical_id(Call)}
                      ,{<<"active_call_id">>, kapps_call:call_id(Call)}, {<<"state">>, Phase}]).

-spec callback_waiting(gen_statem:event_type(), any(), state()) -> kz_types:handle_fsm_ret(state()).
callback_waiting('cast', {'member_hungup', Event}, #state{member_call=Call, callback_ctx=Context}=State) ->
    case {kz_json:get_value(<<"Call-ID">>, Event) =:= acdc_queue_member:logical_id(Call)
         ,maps:get('mode', Context)} of
        {'true', 'awaiting_destroy'} ->
            maybe_stop_timer(maps:get('timer_ref', Context)),
            callback_schedule(State#state{callback_ctx=Context#{'mode' => 'virtual'}}, 0);
        _ -> {'keep_state', State}
    end;
callback_waiting('cast', {'member_call_cancel', _}, State) ->
    %% The original controller's hangup after a durable handoff is expected.
    %% Caller-requested resume/cancel uses the correlated callback protocol.
    {'keep_state', State};
callback_waiting('cast', {'callback_original_status', Ref, Result}
                 ,#state{callback_ctx=#{'status_ref' := Ref}}=State) -> callback_original_status(Result, State);
callback_waiting('cast', {'callback_original_status', _, _}, State) -> {'keep_state', State};
callback_waiting('cast', {'callback_reconciled', Ref, Result}
                 ,#state{callback_ctx=#{'reconcile_ref' := Ref}}=State) -> callback_reconcile_result(Result, State);
callback_waiting('cast', {'callback_reconciled', _, _}, State) -> {'keep_state', State};
callback_waiting('cast', {'callback_cleanup_finished', Ref}
                 ,#state{callback_ctx=#{'cleanup_ref' := Ref}}=State) -> callback_reconcile_later(State);
callback_waiting('cast', {'callback_cleanup_finished', _}, State) -> {'keep_state', State};
callback_waiting('cast', {'callback_recovered_accept', Ref, Result}
                 ,#state{callback_ctx=#{'recovered_accept_ref' := Ref}}=State) -> callback_recovered_accept(Result, State);
callback_waiting('cast', {'callback_recovered_accept', _, _}, State) -> {'keep_state', State};
callback_waiting('cast', {'callback_request', Request}, #state{callback_ctx=#{'mode' := 'recover_lookup'}}=State) ->
    callback_reject(Request, <<"busy">>), {'keep_state', State};
callback_waiting('cast', {'callback_request', Request}, #state{callback_ctx=Context}=State) ->
    case {callback_matches(Request, Context), kz_json:get_value(<<"Operation">>, Request)
         ,maps:get('mode', Context)} of
        {'true', <<"register">>, _} ->
            Doc = maps:get('reservation', Context),
            case kz_json:get_value(<<"Number">>, Request) =:= kz_json:get_value(<<"number">>, Doc) of
                'true' -> callback_reply(Request, <<"registered">>, [{<<"Pause-ID">>, maps:get('pause_id', Context)}
                                                                   ,{<<"Callback-ID">>, kz_doc:id(Doc)}]);
                'false' -> callback_reject(Request, <<"invalid_number">>)
            end,
            {'keep_state', State};
        {'true', <<"resume">>, 'awaiting_destroy'} -> callback_resume(Request, State);
        {'true', <<"abandon">>, _} -> callback_abandon(Request, State);
        _ -> callback_reject(Request, <<"stale_request">>), {'keep_state', State}
    end;
callback_waiting('cast', {'member_call', JObj, Delivery}, #state{listener_proc=Listener}=State) ->
    acdc_queue_listener:cancel_member_call(Listener, JObj, Delivery), {'keep_state', State};
callback_waiting('cast', Event, State) -> handle_event(Event, 'callback_waiting', State);
callback_waiting('info', {'timeout', Ref, 'callback_detach_deadline'}
                 ,#state{member_call=Call, callback_ctx=#{'timer_ref' := Ref, 'mode' := 'awaiting_destroy'}}=State) ->
    %% The caller explicitly confirmed and durable registration succeeded.
    %% A missing success-playback event cannot leave their old leg hanging.
    kapps_call_command:hangup(Call),
    callback_schedule(State, 1000);
callback_waiting('info', {'timeout', Ref, 'callback_abandon_retry'}
                 ,#state{callback_ctx=#{'timer_ref' := Ref}}=State) -> callback_abandon('undefined', State);
callback_waiting('info', {'timeout', Ref, 'callback_reconcile_deadline'}
                 ,#state{callback_ctx=#{'timer_ref' := Ref}=Context}=State) ->
    callback_schedule(State#state{callback_ctx=(maps:without(['reconcile_ref', 'recovered_accept_ref'], Context))#{'mode' => 'reconciliation'}}, 2000);
callback_waiting('info', {'timeout', Ref, 'callback_tick'}
                 ,#state{callback_ctx=#{'timer_ref' := Ref}}=State) -> callback_tick(State);
callback_waiting('info', {'acdc_callback_caller_ready', Id, Token, UUID, Queue, OriginalMsgId}
                 ,#state{callback_ctx=#{'reservation' := _}}=State) ->
    callback_caller_ready(Id, Token, UUID, Queue, OriginalMsgId, State);
callback_waiting('info', {'acdc_callback_caller_confirmed', Id, Token, ReturnedCall}
                 ,#state{callback_ctx=#{'reservation' := _}}=State) ->
    callback_caller_confirmed(Id, Token, ReturnedCall, State);
callback_waiting('info', {'acdc_callback_caller_failed', Id, Token, Cause, Disposition}
                 ,#state{callback_ctx=#{'reservation' := _}}=State) ->
    callback_caller_failed(Id, Token, Cause, Disposition, State);
callback_waiting('info', {'DOWN', Ref, 'process', _Pid, _Reason}
                 ,#state{callback_ctx=#{'worker_monitor' := Ref}=Context}=State) ->
    %% No proof of originate settlement comes from an Erlang worker exit.
    callback_schedule(State#state{callback_ctx=Context#{'mode' => 'reconciliation'}}, 2000);
callback_waiting('info', _, State) -> {'keep_state', State};
callback_waiting({'call', From}, 'status', State) -> callback_status(From, <<"callback_waiting">>, State);
callback_waiting({'call', From}, 'current_call', #state{member_call=Call}=State) ->
    {'keep_state', State, [{'reply', From, callback_current_call(Call, <<"callback_waiting">>)}]};
callback_waiting({'call', From}, Request, State) -> handle_sync_event(Request, From, 'callback_waiting', State).

callback_schedule(#state{callback_ctx=Context}=State, Delay) ->
    maybe_stop_timer(maps:get('timer_ref', Context, 'undefined')),
    Ref = erlang:start_timer(Delay, self(), 'callback_tick'),
    {'next_state', 'callback_waiting', State#state{callback_ctx=Context#{'timer_ref' => Ref}}}.

callback_tick(#state{callback_ctx=#{'mode' := 'awaiting_destroy'}}=State) ->
    %% Do not infer hangup from a missing response/channel lookup timeout.
    callback_schedule(State, 2000);
callback_tick(#state{callback_ctx=#{'mode' := 'recover_lookup', 'original_message' := JObj
                                   ,'original_delivery' := Delivery}}=State) -> callback_recover(JObj, Delivery, State);
callback_tick(#state{callback_ctx=#{'mode' := 'recover_original'}}=State) -> callback_probe_original(State);
callback_tick(#state{callback_ctx=#{'mode' := 'probing_original'}}=State) -> callback_schedule(State, 2000);
callback_tick(#state{callback_ctx=#{'mode' := 'probing_reconciliation'}}=State) -> {'keep_state', State};
callback_tick(#state{callback_ctx=#{'mode' := 'abandoning'}}=State) -> callback_abandon('undefined', State);
callback_tick(#state{callback_ctx=#{'mode' := 'native_ending', 'end_cause' := Cause}}=State) ->
    callback_native_end(Cause, State);
callback_tick(#state{callback_ctx=Context, account_id=AccountId, queue_id=QueueId}=State) ->
    Id = kz_doc:id(maps:get('reservation', Context)),
    case acdc_callback_store:get(AccountId, QueueId, Id) of
        {'ok', Doc} ->
            case kz_json:get_value(<<"status">>, Doc) of
                <<"cancelled">> -> callback_finish_terminal(State);
                <<"expired">> -> callback_finish_terminal(State);
                <<"failed">> -> callback_finish_terminal(State);
                <<"completed">> -> callback_finish_terminal(State);
                <<"cancelling">> ->
                    callback_cancel_worker(Context),
                    callback_probe_reconcile(Doc, State);
                Status when Status =:= <<"queued">>; Status =:= <<"retry_wait">> ->
                    callback_maybe_dial(Doc, State);
                _ when map_get('mode', Context) =:= 'dialing' ->
                    case callback_keep_lease(State#state{callback_ctx=Context#{'reservation' => Doc}}) of
                        {'ok', Next} -> callback_schedule(Next, 2000);
                        {'error', Next} ->
                            callback_cancel_worker(Context),
                            callback_schedule(Next#state{callback_ctx=(Next#state.callback_ctx)#{'mode' => 'reconciliation'}}, 2000)
                    end;
                _ ->
                    %% A lease timeout is never permission to redial. The
                    %% current worker or recovery reconciler owns cleanup.
                    callback_probe_reconcile(Doc, State)
            end;
        _ -> callback_schedule(State, 2000)
    end.

callback_maybe_dial(Doc, #state{account_id=AccountId, queue_id=QueueId
                               ,manager_proc=Manager, member_call=Call}=State) ->
    Now = kz_time:now_s(),
    case {kz_json:get_integer_value(<<"expires_at">>, Doc, 0) =< Now
         ,kz_json:get_integer_value(<<"next_attempt_at">>, Doc, 0) =< Now} of
        {'true', _} ->
            _ = acdc_callback_store:expire(AccountId, QueueId, kz_doc:id(Doc)),
            callback_schedule(State, 1000);
        {_, 'false'} -> callback_schedule(State, 1000);
        _ ->
            case acdc_queue_manager:up_next(Manager, acdc_queue_member:logical_id(Call))
                andalso acdc_queue_manager:ready_agent_count(Manager) > 0 of
                'false' -> callback_schedule(State, 1000);
                'true' ->
                    Owner = iolist_to_binary([atom_to_binary(node(), utf8), <<":">>, pid_to_list(self())]),
                    case acdc_callback_store:claim(AccountId, QueueId, kz_doc:id(Doc), Owner, 300) of
                        {'ok', Claimed} -> callback_start_caller(Claimed, State);
                        _ -> callback_schedule(State, 2000)
                    end
            end
    end.

callback_start_caller(Doc, #state{account_id=AccountId, queue_id=QueueId
                                 ,member_call=Call, callback_ctx=Context}=State) ->
    Token = kz_json:get_value([<<"pvt_lease">>, <<"token">>], Doc),
    NextContext = Context#{'reservation' => Doc, 'token' => Token, 'mode' => 'dialing', 'originate_settled' => 'false'},
    Next = State#state{callback_ctx=NextContext},
    case kz_datamgr:open_doc(kzs_util:format_account_db(AccountId), QueueId) of
        {'ok', Queue} ->
            Original = kapps_call:set_call_id(acdc_queue_member:logical_id(Call), Call),
            case acdc_callback_caller:start_link(self(), Queue, Doc, Token, Original) of
                {'ok', Worker} ->
                    unlink(Worker),
                    Monitor = erlang:monitor('process', Worker),
                    callback_schedule(Next#state{callback_ctx=NextContext#{'worker' => Worker
                                                                          ,'worker_monitor' => Monitor}}, 2000);
                _ -> callback_caller_failed(kz_doc:id(Doc), Token, 'routing_failed', 'settled', Next)
            end;
        _ -> callback_caller_failed(kz_doc:id(Doc), Token, 'routing_failed', 'settled', Next)
    end.

callback_caller_confirmed(Id, Token, ReturnedCall, #state{callback_ctx=Context
                                                        ,account_id=AccountId, queue_id=QueueId
                                                        ,member_call=OriginalCall}=State) ->
    Doc = maps:get('reservation', Context),
    CallerId = kz_json:get_value(<<"pvt_caller_call_id">>, Doc),
    case {Id =:= kz_doc:id(Doc), Token =:= maps:get('token', Context, 'undefined')
         ,kapps_call:call_id(ReturnedCall) =:= CallerId, maps:get('mode', Context)} of
        {'true', 'true', 'true', 'dialing'} ->
            Data = kz_json:from_list([{<<"caller_call_id">>, CallerId}]),
            Result = case acdc_callback_store:bind_control(AccountId, QueueId, Id, Token, CallerId
                                                          ,kapps_call:control_queue(ReturnedCall)) of
                {'ok', _} -> acdc_callback_store:advance(AccountId, QueueId, Id, Token, 'caller_answered', Data);
                Error -> Error
            end,
            case Result of
                {'ok', _} ->
                    case acdc_callback_store:advance(AccountId, QueueId, Id, Token, 'caller_confirmed', Data) of
                        {'ok', Confirmed} ->
                            callback_replace_live_call(Confirmed, OriginalCall, ReturnedCall, State);
                        _ -> callback_cancel_worker(Context), callback_schedule(State, 2000)
                    end;
                _ -> callback_cancel_worker(Context), callback_schedule(State, 2000)
            end;
        _ -> {'keep_state', State}
    end.

callback_caller_ready(Id, Token, UUID, OriginateQueue, OriginalMsgId
                      ,#state{account_id=AccountId, queue_id=QueueId, callback_ctx=Context}=State) ->
    Doc = maps:get('reservation', Context),
    case Id =:= kz_doc:id(Doc) andalso Token =:= maps:get('token', Context, 'undefined')
        andalso maps:get('mode', Context) =:= 'dialing' of
        'true' ->
            case acdc_callback_store:bind_originate(AccountId, QueueId, Id, Token, UUID, OriginateQueue, OriginalMsgId) of
                {'ok', Bound} ->
                    acdc_callback_caller:originate_ready_ack(maps:get('worker', Context), Token),
                    {'keep_state', State#state{callback_ctx=Context#{'reservation' => Bound}}};
                _ -> callback_cancel_worker(Context), callback_schedule(State, 2000)
            end;
        'false' -> {'keep_state', State}
    end.

callback_replace_live_call(Doc, OriginalCall, ReturnedCall
                           ,#state{manager_proc=Manager, listener_proc=Listener, callback_ctx=Context}=State) ->
    LogicalId = acdc_queue_member:logical_id(OriginalCall),
    Id = kz_doc:id(Doc),
    Attempt = kz_json:get_integer_value(<<"attempts">>, Doc),
    CallerId = kz_json:get_value(<<"pvt_caller_call_id">>, Doc),
    case acdc_queue_manager:replace_member_call(Manager, LogicalId, Id, Attempt, CallerId, ReturnedCall) of
        {'ok', _Position, CanonicalCall} ->
            case acdc_queue_listener:replace_callback_call(Listener, LogicalId, Id, CallerId, CanonicalCall) of
                'ok' ->
                    maybe_stop_timer(maps:get('timer_ref', Context)),
                    case maps:get('worker', Context, 'undefined') of
                        Worker when is_pid(Worker) ->
                            acdc_callback_caller:handoff_complete(Worker, maps:get('token', Context));
                        _ -> 'ok'
                    end,
                    acdc_queue_listener:member_connect_req(Listener),
                    LeaseRef = erlang:start_timer(30000, self(), 'callback_lease_tick'),
                    %% The returned caller has confirmed but may still wait
                    %% while native agent selection/ringing completes.
                    {'next_state', 'connect_req'
                    ,State#state{member_call=CanonicalCall, collect_ref=start_collect_timer()
                                ,connection_timer_ref=start_connection_timer(60000)
                                ,callback_ctx=Context#{'reservation' => Doc, 'mode' => 'native'
                                                      ,'timer_ref' => 'undefined', 'lease_timer_ref' => LeaseRef}}};
                _ -> callback_cancel_worker(Context), callback_schedule(State, 2000)
            end;
        _ -> callback_cancel_worker(Context), callback_schedule(State, 2000)
    end.

callback_caller_failed(Id, Token, Cause, Disposition, #state{callback_ctx=Context
                                                          ,account_id=AccountId, queue_id=QueueId}=State) ->
    Doc = maps:get('reservation', Context),
    case Id =:= kz_doc:id(Doc) andalso Token =:= maps:get('token', Context, 'undefined') of
        'false' -> {'keep_state', State};
        'true' ->
            case Disposition of
                'settled' ->
                    Data = kz_json:from_list([{<<"caller_call_id">>, kz_json:get_value(<<"pvt_caller_call_id">>, Doc)}
                                              ,{<<"originate_settled">>, 'true'}, {<<"channels_down">>, 'true'}
                                              ,{<<"cause">>, callback_cause(Cause)}]),
                    case acdc_callback_store:advance(AccountId, QueueId, Id, Token, 'attempt_settled', Data) of
                        {'ok', Settled} ->
                            callback_schedule(State#state{callback_ctx=Context#{'reservation' => Settled
                                                                                ,'mode' => 'virtual'}}, 1000);
                        _ -> callback_schedule(State#state{callback_ctx=Context#{'mode' => 'reconciliation'
                                                                                 ,'originate_settled' => 'true'}}, 2000)
                    end;
                _ -> callback_schedule(State#state{callback_ctx=Context#{'mode' => 'reconciliation'}}, 2000)
            end
    end.

callback_cause(Cause) ->
    case Cause of
        'busy' -> <<"busy">>;
        'no_answer' -> <<"no_answer">>;
        'wrong_digit' -> <<"wrong_digit">>;
        'confirmation_timeout' -> <<"confirmation_timeout">>;
        'caller_hangup' -> <<"caller_hangup">>;
        'media_failed' -> <<"media_failed">>;
        _ -> <<"routing_failed">>
    end.

callback_cancel_worker(Context) ->
    case maps:get('worker', Context, 'undefined') of
        Worker when is_pid(Worker) -> acdc_callback_caller:cancel(Worker, maps:get('token', Context));
        _ -> 'ok'
    end.

callback_finish_terminal(#state{listener_proc=Listener, callback_ctx=Context}=State) ->
    Id = kz_doc:id(maps:get('reservation', Context)),
    Result = try acdc_queue_listener:retire_callback_member(Listener, Id)
             catch _:_ -> {'error', 'retirement_failed'} end,
    case Result of
        'ok' -> {'next_state', 'ready', clear_member_call(State)};
        _ -> callback_schedule(State, 2000)
    end.

callback_recover(CallJObj, Delivery, #state{account_id=AccountId, queue_id=QueueId
                                          ,manager_proc=Manager, member_call=Call}=State) ->
    %% This uncached read is deliberately before channel-alive or normal
    %% agent selection logic. The dead original UUID may own a live ticket.
    case acdc_callback_store:find(AccountId, QueueId, acdc_queue_member:logical_id(Call)) of
        {'error', 'not_found'} ->
            case acdc_queue_manager:ensure_member(Manager, Call) of
                {'ok', _Position} -> ready('cast', {'check_if_next', CallJObj, Delivery}, State#state{callback_ctx=#{}});
                _ -> callback_recover_later(CallJObj, Delivery, State)
            end;
        {'ok', Doc} ->
            case kz_json:get_value(<<"status">>, Doc) of
                <<"completed">> -> callback_finish_terminal(State#state{callback_ctx=#{'reservation' => Doc, 'mode' => 'reconciliation'}});
                <<"registering">> ->
                    case acdc_callback_store:cancel(AccountId, QueueId, kz_doc:id(Doc)) of
                        {'ok', Cancelled} -> callback_restore(Cancelled, CallJObj, Delivery, State);
                        _ -> callback_recover_later(CallJObj, Delivery, State)
                    end;
                _ -> callback_restore(Doc, CallJObj, Delivery, State)
            end;
        _ -> callback_recover_later(CallJObj, Delivery, State)
    end.

callback_recover_later(CallJObj, Delivery, State) ->
    callback_schedule(State#state{callback_ctx=#{'mode' => 'recover_lookup'
                                                ,'original_message' => CallJObj, 'original_delivery' => Delivery}}, 1000).

callback_restore(Doc, CallJObj, Delivery, #state{manager_proc=Manager, member_call=Call
                                               }=State) ->
    case acdc_queue_manager:ensure_callback_member(Manager, Call, Doc) of
        {'ok', _Position, Canonical} ->
            callback_restore_context(Doc, CallJObj, Delivery, State#state{member_call=Canonical});
        _ -> callback_recover_later(CallJObj, Delivery, State)
    end.

callback_restore_context(Doc, CallJObj, Delivery, #state{member_call=Call
                                                       ,account_id=AccountId, queue_id=QueueId}=State) ->
    Request = kz_json:from_list([{<<"Account-ID">>, AccountId}, {<<"Queue-ID">>, QueueId}
                                 ,{<<"Call-ID">>, acdc_queue_member:logical_id(Call)}
                                 ,{<<"Request-ID">>, kz_json:get_value(<<"pvt_registration_request_id">>, Doc)}
                                 ,{<<"Server-ID">>, kz_json:get_value(<<"pvt_controller_queue">>, Doc)}
                                 ,{<<"Operation">>, <<"register">>}]),
    Context = #{'reservation' => Doc, 'request' => Request
               ,'registration_request' => Request, 'registration_ref' => 'undefined'
               ,'pause_id' => kz_json:get_value(<<"pvt_pause_id">>, Doc)
               ,'token' => kz_json:get_value([<<"pvt_lease">>, <<"token">>], Doc)
               ,'mode' => 'recover_original', 'previous_state' => 'ready'
               ,'original_message' => CallJObj, 'original_delivery' => Delivery},
    callback_probe_original(State#state{callback_ctx=Context}).

callback_probe_original(#state{member_call=Call, callback_ctx=Context}=State) ->
    Owner = self(), Ref = make_ref(), CallId = acdc_queue_member:logical_id(Call),
    _ = spawn(fun() ->
        Result = try callback_channel_status(CallId) catch _:_ -> 'unknown' end,
        gen_statem:cast(Owner, {'callback_original_status', Ref, Result})
    end),
    callback_schedule(State#state{callback_ctx=Context#{'mode' => 'probing_original', 'status_ref' => Ref}}, 2000).

callback_channel_status(CallId) ->
    Command = [{<<"Call-ID">>, CallId}, {<<"Active-Only">>, 'false'}
               | kz_api:default_headers(?APP_NAME, ?APP_VERSION)],
    %% b_channel_status/1 collapses partial/time-out responses to not_found;
    %% recovery must instead require a complete nonempty collection.
    case kz_amqp_worker:call_collect(Command, fun kapi_call:publish_channel_status_req/1, {'ecallmgr', 'true'}) of
        {'ok', [_ | _]=Responses} ->
            Valid = lists:all(fun(Response) -> kapi_call:channel_status_resp_v(Response)
                                               andalso kz_json:get_value(<<"Call-ID">>, Response) =:= CallId end, Responses),
            States = [kz_json:get_value(<<"Status">>, Response) || Response <- Responses],
            case {Valid, lists:member(<<"active">>, States), lists:usort(States)} of
                {'true', 'true', _} -> 'active';
                {'true', 'false', [<<"terminated">>]} -> 'terminated';
                _ -> 'unknown'
            end;
        _ -> 'unknown'
    end.

callback_original_status('unknown', #state{callback_ctx=Context}=State) ->
    callback_schedule(State#state{callback_ctx=Context#{'mode' => 'recover_original'}}, 2000);
callback_original_status(ChannelStatus, #state{callback_ctx=Context, manager_proc=Manager, member_call=Call}=State) ->
    Doc = maps:get('reservation', Context),
    Status = kz_json:get_value(<<"status">>, Doc),
    case {ChannelStatus, lists:member(Status, [<<"cancelled">>, <<"expired">>, <<"failed">>])} of
        {'terminated', 'true'} -> callback_finish_terminal(State);
        {'active', 'true'} ->
            _ = acdc_queue_manager:resume_announcements(Manager, acdc_queue_member:logical_id(Call)),
            ready('cast', {'check_if_next', maps:get('original_message', Context), maps:get('original_delivery', Context)}
                  ,State#state{callback_ctx=callback_resumed_context(Context)});
        {'active', 'false'} when Status =:= <<"queued">> ->
            Request = maps:get('registration_request', Context),
            _ = callback_reply(Request, <<"registered">>, [{<<"Pause-ID">>, maps:get('pause_id', Context)}
                                                            ,{<<"Callback-ID">>, kz_doc:id(Doc)}]),
            Timer = erlang:start_timer(State#state.callback_success_timeout + 5000, self(), 'callback_detach_deadline'),
            {'next_state', 'callback_waiting', State#state{callback_ctx=Context#{'mode' => 'awaiting_destroy', 'timer_ref' => Timer}}};
        {'terminated', 'false'} when Status =:= <<"queued">>; Status =:= <<"retry_wait">> ->
            callback_schedule(State#state{callback_ctx=Context#{'mode' => 'virtual'}}, 0);
        _ ->
            %% An interrupted active attempt is retained for explicit channel
            %% reconciliation; neither lease expiry nor redelivery redials it.
            callback_schedule(State#state{callback_ctx=Context#{'mode' => 'reconciliation'}}, 2000)
    end.

callback_probe_reconcile(Doc0, #state{account_id=AccountId, queue_id=QueueId, callback_ctx=Context}=State) ->
    Reason = case kz_json:get_value(<<"status">>, Doc0) of
        <<"cancelling">> -> <<"cleanup_pending">>;
        _ -> <<"channel_snapshot_incomplete">>
    end,
    Doc = case acdc_callback_store:mark_reconciliation(AccountId, QueueId, kz_doc:id(Doc0)
                                                       ,maps:get('token', Context, 'undefined'), Reason) of
        {'ok', Marked} -> Marked;
        _ -> Doc0
    end,
    Owner = self(), Ref = make_ref(),
    _ = spawn(fun() ->
        Result = try
            case acdc_callback_recovery_io:observe(Doc) of
                {'ok', Evidence} ->
                    Originate = case acdc_callback_recovery_io:reconcile_originate(Doc, 'status') of
                        {'ok', OriginateEvidence} -> maps:get('status', OriginateEvidence, 'unknown');
                        _ -> 'unknown'
                    end,
                    {'ok', Evidence#{'originate' => Originate}};
                Observation -> Observation
            end
                 catch _:_ -> {'error', 'observation_failed'} end,
        gen_statem:cast(Owner, {'callback_reconciled', Ref, Result})
    end),
    maybe_stop_timer(maps:get('timer_ref', Context, 'undefined')),
    Timer = erlang:start_timer(55000, self(), 'callback_reconcile_deadline'),
    {'next_state', 'callback_waiting', State#state{callback_ctx=Context#{'reservation' => Doc
                                                                      ,'mode' => 'probing_reconciliation'
                                                                      ,'reconcile_ref' => Ref, 'timer_ref' => Timer}}}.

callback_reconcile_result({'ok', Evidence0}, #state{account_id=AccountId, queue_id=QueueId
                                                    ,callback_ctx=Context}=State) ->
    ObservedDoc = maps:get('reservation', Context),
    case acdc_callback_store:get(AccountId, QueueId, kz_doc:id(ObservedDoc)) of
        {'ok', Fresh} ->
            case kz_doc:revision(Fresh) =:= kz_doc:revision(ObservedDoc) of
                'false' -> callback_reconcile_later(State);
                'true' ->
                    Owner0 = acdc_callback_reconcile:owner(Fresh, maps:get('token', Context, 'undefined')),
                    Owner = case Owner0 =:= 'self' andalso callback_worker_alive(Context) of
                        'true' -> 'alive'; 'false' -> Owner0
                    end,
                    Evidence = case maps:get('originate_settled', Context, 'false') of
                        'true' -> Evidence0#{'originate' => 'settled'};
                        'false' -> Evidence0
                    end,
                    case acdc_callback_reconcile:plan(Fresh, kz_time:now_s(), Owner, Evidence) of
                        {'ok', Action, _} -> callback_recovery_action(Action, State);
                        _ -> callback_reconcile_later(State)
                    end
            end;
        _ -> callback_reconcile_later(State)
    end;
callback_reconcile_result(_, State) -> callback_reconcile_later(State).

callback_reconcile_later(#state{callback_ctx=Context}=State) ->
    callback_schedule(State#state{callback_ctx=(maps:without(['reconcile_ref', 'recovered_accept_ref', 'cleanup_ref'], Context))#{'mode' => 'reconciliation'}}, 5000).

callback_worker_alive(Context) ->
    case maps:get('worker', Context, 'undefined') of
        Worker when is_pid(Worker) -> erlang:is_process_alive(Worker);
        _ -> 'false'
    end.

callback_recovery_action(#{'action' := 'retire'}, State) -> callback_finish_terminal(State);
callback_recovery_action(#{'action' := 'virtual_wait'}, #state{callback_ctx=Context}=State) ->
    callback_schedule(State#state{callback_ctx=Context#{'mode' => 'virtual'}}, 1000);
callback_recovery_action(#{'action' := 'rebind_confirmed'}, State) ->
    case callback_adopt_existing(State) of
        {'ok', Doc, ReturnedCall, #state{member_call=Original}=Adopted} ->
            callback_replace_live_call(Doc, Original, ReturnedCall, Adopted);
        _ -> callback_reconcile_later(State)
    end;
callback_recovery_action(#{'action' := 'prove_bridge', 'agent_call_id' := AgentLeg}
                         ,#state{account_id=AccountId, callback_ctx=Context}=State) ->
    %% An actual media bridge alone does not identify the selected ACDC agent.
    %% Obtain a fresh answer proof from the persisted winning agent processes.
    Doc = maps:get('reservation', Context), CallerId = kz_json:get_value(<<"pvt_caller_call_id">>, Doc),
    Wins = kz_json:get_list_value(<<"pvt_selected_agents">>, Doc, []),
    Owner = self(), Ref = make_ref(),
    _ = spawn(fun() ->
        Result = try acdc_callback_agent_probe:probe(AccountId, CallerId, Wins, AgentLeg)
                 catch _:_ -> {'error', 'unknown'} end,
        gen_statem:cast(Owner, {'callback_recovered_accept', Ref, Result})
    end),
    maybe_stop_timer(maps:get('timer_ref', Context, 'undefined')),
    Timer = erlang:start_timer(6000, self(), 'callback_reconcile_deadline'),
    {'keep_state', State#state{callback_ctx=Context#{'recovered_accept_ref' => Ref, 'recovered_agent_leg' => AgentLeg
                                                   ,'timer_ref' => Timer}}};
callback_recovery_action(#{'action' := Action}, #state{callback_ctx=Context}=State)
  when Action =:= 'cancel_originate'; Action =:= 'cancel_channels' ->
    Owner = self(), Ref = make_ref(), Doc = maps:get('reservation', Context),
    _ = spawn(fun() ->
        _ = try acdc_callback_recovery_io:request_cleanup(Doc) catch _:_ -> 'error' end,
        gen_statem:cast(Owner, {'callback_cleanup_finished', Ref})
    end),
    maybe_stop_timer(maps:get('timer_ref', Context, 'undefined')),
    Timer = erlang:start_timer(55000, self(), 'callback_reconcile_deadline'),
    {'keep_state', State#state{callback_ctx=Context#{'mode' => 'probing_cleanup', 'cleanup_ref' => Ref, 'timer_ref' => Timer}}};
callback_recovery_action(#{'action' := 'settle_attempt', 'caller_call_id' := CallerId}=Action
                         ,#state{account_id=AccountId, queue_id=QueueId, callback_ctx=Context}=State) ->
    Doc = maps:get('reservation', Context),
    Data = kz_json:from_list(props:filter_undefined(
                             [{<<"caller_call_id">>, CallerId}, {<<"agent_call_id">>, maps:get('agent_call_id', Action, 'undefined')}
                              ,{<<"originate_settled">>, 'true'}, {<<"channels_down">>, 'true'}
                              ,{<<"cause">>, <<"routing_failed">>}])),
    case acdc_callback_store:advance(AccountId, QueueId, kz_doc:id(Doc)
                                     ,kz_json:get_value([<<"pvt_lease">>, <<"token">>], Doc), 'attempt_settled', Data) of
        {'ok', Settled} -> callback_schedule(State#state{callback_ctx=Context#{'reservation' => Settled
                                                                             ,'mode' => 'virtual', 'originate_settled' => 'false'}}, 1000);
        _ -> callback_reconcile_later(State)
    end;
callback_recovery_action(_, State) -> callback_reconcile_later(State).

callback_adopt_existing(#state{account_id=AccountId, queue_id=QueueId, member_call=Original, callback_ctx=Context}=State) ->
    Doc = maps:get('reservation', Context),
    case callback_worker_alive(Context) of
        'true' -> {'error', 'live_worker'};
        'false' ->
            case acdc_callback_store:adopt(AccountId, QueueId, kz_doc:id(Doc)
                                           ,kz_json:get_value([<<"pvt_lease">>, <<"token">>], Doc), 300) of
                {'ok', Adopted} ->
                    case acdc_callback_reconcile:restore_call(Adopted, Original) of
                        {'ok', Returned} ->
                            Token = kz_json:get_value([<<"pvt_lease">>, <<"token">>], Adopted),
                            {'ok', Adopted, Returned, State#state{callback_ctx=Context#{'reservation' => Adopted, 'token' => Token}}};
                        Error -> Error
                    end;
                Error -> Error
            end
    end.

callback_recovered_accept({'ok', Accepted}, #state{callback_ctx=Context}=State) ->
    case kz_json:get_ne_binary_value(<<"Agent-Call-ID">>, Accepted) =:= maps:get('recovered_agent_leg', Context, 'undefined')
        andalso is_binary(maps:get('recovered_agent_leg', Context, 'undefined')) of
        'true' -> callback_recovered_accept_valid(Accepted, State);
        'false' -> callback_reconcile_later(State)
    end;
callback_recovered_accept(_, State) -> callback_reconcile_later(State).

callback_recovered_accept_valid(Accepted, #state{callback_ctx=Context, manager_proc=Manager, listener_proc=Listener}=State) ->
    case callback_adopt_existing(State) of
        {'ok', Doc, Returned, #state{callback_ctx=AdoptedContext}=Adopted} ->
            LogicalId = kz_json:get_value(<<"original_call_id">>, Doc), Id = kz_doc:id(Doc),
            CallerId = kapps_call:call_id(Returned), Attempt = kz_json:get_value(<<"attempts">>, Doc),
            case acdc_queue_manager:replace_member_call(Manager, LogicalId, Id, Attempt, CallerId, Returned) of
                {'ok', _, Canonical} ->
                    case acdc_queue_listener:replace_callback_call(Listener, LogicalId, Id, CallerId, Canonical) of
                        'ok' ->
                            Wins = kz_json:get_list_value(<<"pvt_selected_agents">>, Doc, []),
                            Next = Adopted#state{member_call=Canonical, connect_wins=Wins
                                                  ,callback_ctx=AdoptedContext#{'mode' => 'native', 'accepted' => Accepted
                                                                               ,'bridge_agent_leg' => maps:get('recovered_agent_leg', Context)}},
                            callback_complete(Next);
                        _ -> callback_reconcile_later(Adopted)
                    end;
                _ -> callback_reconcile_later(Adopted)
            end;
        _ -> callback_reconcile_later(State)
    end.

%% Originate success precedes media success. Join the selected process's
%% Agent-Call-ID with an actual same-account bridge, in either arrival order.
ordinary_accept(Accept, #state{member_call=Call, account_id=AccountId
                               ,connect_wins=Wins, bridge_ctx=Context}=State) ->
    Leg = kz_json:get_ne_binary_value(<<"Agent-Call-ID">>, Accept),
    case accept_is_for_call(Accept, Call)
        andalso kz_json:get_value(<<"Account-ID">>, Accept) =:= AccountId
        andalso is_binary(Leg) andalso Leg =/= kapps_call:call_id(Call)
        andalso (is_reference(State#state.agent_ring_timer_ref) orelse maps:is_key('leg', Context)
                 orelse maps:is_key('proof_status', Context))
        andalso lists:any(fun(W) -> acdc_queue_strategy:process_matches(Accept, W) end, Wins) of
        'true' ->
            Key = {kz_json:get_value(<<"Agent-ID">>, Accept), kz_json:get_value(<<"Process-ID">>, Accept)},
            Accepts = maps:get('accepts', Context, #{}),
            ordinary_complete(ordinary_proof_wait(State#state{bridge_ctx=Context#{'accepts' => Accepts#{Key => Accept}}}));
        'false' -> {'next_state', 'connecting', State}
    end.

ordinary_bridge(Event, #state{member_call=Call, account_id=AccountId
                               ,bridge_ctx=Context, connect_wins=Wins}=State) ->
    Leg = kz_call_event:other_leg_call_id(Event),
    case Call =/= 'undefined' andalso Wins =/= []
        andalso kz_call_event:call_id(Event) =:= kapps_call:call_id(Call)
        andalso kz_json:get_value([<<"Custom-Channel-Vars">>, <<"Account-ID">>], Event) =:= AccountId
        andalso is_binary(Leg) andalso byte_size(Leg) > 0 andalso Leg =/= kapps_call:call_id(Call)
        andalso maps:get('leg', Context, Leg) =:= Leg
        andalso (is_reference(State#state.agent_ring_timer_ref) orelse maps:is_key('leg', Context)
                 orelse maps:is_key('proof_status', Context)) of
        'true' ->
            ordinary_record_bridge(Leg, State);
        'false' -> {'next_state', 'connecting', State}
    end.

%% Native intercept emits the bridge on the AGENT leg, while this listener is
%% bound to the caller only. A selected acceptance therefore starts an existing
%% account-scoped channel-status proof, never a synthetic handled transition.
%% Freeze retry/connection timers before probing: the caller may already be
%% physically bridged. Unknown at the fixed deadline is explicitly unresolved,
%% not permission to originate again or hang up the caller/partner.
ordinary_proof_wait(#state{bridge_ctx=Context}=State) ->
    maybe_stop_timer(State#state.connection_timer_ref),
    maybe_stop_timer(State#state.agent_ring_timer_ref),
    Next = case maps:is_key('proof_status', Context) of
        'true' -> Context;
        'false' -> Context#{'proof_status' => 'pending',
                            'proof_deadline' => erlang:monotonic_time(millisecond) + 15000,
                            'timer_ref' => erlang:start_timer(15000, self(), 'ordinary_bridge_proof_timeout')}
    end,
    State#state{bridge_ctx=Next, connection_timer_ref='undefined', agent_ring_timer_ref='undefined'}.

ordinary_record_bridge(Leg, State) ->
    Next = ordinary_proof_wait(State),
    ordinary_stop_bridge_probe(Next#state.bridge_ctx),
    Context = maps:without(['probe_ref', 'probe_pid', 'probe_retry_ref'], Next#state.bridge_ctx),
    ordinary_complete(Next#state{bridge_ctx=Context#{'leg' => Leg}}).

ordinary_start_bridge_probe(#state{bridge_ctx=Context, member_call=Call, account_id=AccountId}=State) ->
    Deadline = maps:get('proof_deadline', Context, 0),
    Remaining = Deadline - erlang:monotonic_time(millisecond),
    case {maps:get('proof_status', Context, 'undefined'), maps:is_key('leg', Context),
          maps:is_key('probe_ref', Context) orelse maps:is_key('probe_retry_ref', Context), Remaining > 0} of
        {'pending', 'false', 'false', 'true'} ->
            Parent = self(), Ref = make_ref(), Caller = kapps_call:call_id(Call),
            Pid = spawn(fun() ->
                Result = case Deadline - erlang:monotonic_time(millisecond) of
                    Budget when Budget > 0 ->
                        {ok, Watchdog} = timer:kill_after(Budget, self()),
                        Observed = try acdc_callback_recovery_io:observe_channels(AccountId, [Caller])
                                   catch _:_ -> {'error', 'unknown'} end,
                        timer:cancel(Watchdog), Observed;
                    _ -> {'error', 'deadline'}
                end,
                gen_statem:cast(Parent, {'ordinary_bridge_snapshot', Ref, Caller, Result})
            end),
            {'next_state', 'connecting', State#state{bridge_ctx=Context#{'probe_ref' => Ref, 'probe_pid' => Pid}}};
        _ -> {'next_state', 'connecting', State}
    end.

ordinary_bridge_snapshot(Result, #state{bridge_ctx=Context, member_call=Call, connect_wins=Wins}=State) ->
    Fresh = maps:get('proof_status', Context, 'undefined') =:= 'pending'
        andalso erlang:monotonic_time(millisecond) < maps:get('proof_deadline', Context, 0),
    Accepts = maps:values(maps:get('accepts', Context, #{})),
    Candidates = lists:usort([kz_json:get_value(<<"Agent-Call-ID">>, A) || A <- Accepts,
                            lists:any(fun(W) -> acdc_queue_strategy:process_matches(A, W) end, Wins)]),
    case {Fresh, callback_observed_agent(Result, kapps_call:call_id(Call), Candidates)} of
        {'true', {'ok', Leg}} -> ordinary_record_bridge(Leg, State);
        {'true', 'unknown'} ->
            Ref = erlang:start_timer(250, self(), 'ordinary_bridge_snapshot_retry'),
            {'next_state', 'connecting', State#state{bridge_ctx=Context#{'probe_retry_ref' => Ref}}};
        _ -> {'next_state', 'connecting', State}
    end.

ordinary_stop_bridge_probe(Context) ->
    maybe_stop_timer(maps:get('probe_retry_ref', Context, 'undefined')),
    case maps:get('probe_pid', Context, 'undefined') of
        Pid when is_pid(Pid), Pid =/= self() -> exit(Pid, kill), 'ok';
        _ -> 'ok'
    end.

ordinary_complete(#state{bridge_ctx=Context, member_call=Call, listener_proc=Listener
                         ,connect_wins=Wins, account_id=AccountId, queue_id=QueueId}=State) ->
    Leg = maps:get('leg', Context, 'undefined'),
    Accepts = maps:values(maps:get('accepts', Context, #{})),
    Matching = [A || A <- Accepts, kz_json:get_value(<<"Agent-Call-ID">>, A) =:= Leg,
                     lists:any(fun(W) -> acdc_queue_strategy:process_matches(A, W) end, Wins)],
    case {Matching, lists:usort([kz_json:get_value(<<"Agent-ID">>, A) || A <- Matching])} of
        {[Accepted|_], [_]} when is_binary(Leg) ->
            Agent = kz_json:get_value(<<"Agent-ID">>, Accepted),
            Losers = [W || W <- Wins, kz_json:get_value(<<"Agent-ID">>, W) =/= Agent],
            lists:foreach(fun(W) -> acdc_queue_listener:member_connect_satisfied(Listener, W, []) end, Losers),
            acdc_queue_listener:finish_member_call(Listener),
            acdc_stats:call_handled(AccountId, QueueId, kapps_call:call_id(Call), Agent),
            {'next_state', 'ready', clear_member_call(State), 'hibernate'};
        _ -> ordinary_start_bridge_probe(State)
    end.

callback_accept(Accept, #state{member_call=Call, callback_ctx=Context
                              ,account_id=AccountId, connect_wins=Wins}=State) ->
    Agent = kz_json:get_ne_binary_value(<<"Agent-ID">>, Accept),
    Process = kz_json:get_ne_binary_value(<<"Process-ID">>, Accept),
    AgentLeg = kz_json:get_ne_binary_value(<<"Agent-Call-ID">>, Accept),
    case accept_is_for_call(Accept, Call)
        andalso kz_json:get_value(<<"Account-ID">>, Accept) =:= AccountId
        andalso is_binary(Agent) andalso is_binary(Process)
        andalso is_binary(AgentLeg) andalso AgentLeg =/= kapps_call:call_id(Call)
        andalso lists:any(fun(Win) -> kz_json:get_value(<<"Agent-ID">>, Win) =:= Agent
                                      andalso kz_json:get_value(<<"Process-ID">>, Win) =:= Process end, Wins) of
        'true' ->
            Candidates = maps:get('accepted_candidates', Context, #{}),
            callback_complete(State#state{callback_ctx=Context#{'accepted_candidates' => Candidates#{{Agent, Process} => Accept}}});
        'false' -> {'next_state', 'connecting', State}
    end.

callback_bridge(Event, #state{member_call=Call, callback_ctx=Context
                              ,account_id=AccountId}=State) ->
    AgentLeg = kz_call_event:other_leg_call_id(Event),
    case kz_call_event:call_id(Event) =:= kapps_call:call_id(Call)
        andalso kz_json:get_value([<<"Custom-Channel-Vars">>, <<"Account-ID">>], Event) =:= AccountId
        andalso is_binary(AgentLeg) andalso byte_size(AgentLeg) > 0
        andalso maps:get('bridge_agent_leg', Context, AgentLeg) =:= AgentLeg
        andalso AgentLeg =/= kapps_call:call_id(Call) of
        'true' -> callback_record_bridge(AgentLeg, State);
        'false' -> {'next_state', 'connecting', State}
    end.

callback_record_bridge(AgentLeg, #state{callback_ctx=Context, account_id=AccountId, queue_id=QueueId
                                        ,connection_timer_ref=ConnRef, agent_ring_timer_ref=AgentRef}=State) ->
    maybe_stop_timer(ConnRef), maybe_stop_timer(AgentRef),
    Next = State#state{callback_ctx=Context#{'bridge_agent_leg' => AgentLeg}
                        ,connection_timer_ref='undefined', agent_ring_timer_ref='undefined'},
    %% Persist a positively observed other leg before waiting for acceptance.
    Doc = maps:get('reservation', Context),
    case acdc_callback_store:bind_leg(AccountId, QueueId, kz_doc:id(Doc), maps:get('token', Context), 'agent', AgentLeg) of
        {'ok', Bound} -> callback_complete(Next#state{callback_ctx=(Next#state.callback_ctx)#{'reservation' => Bound}});
        _ -> callback_native_end('agent_unavailable', Next)
    end.

callback_complete(#state{callback_ctx=Context, connect_wins=Wins}=State) ->
    AgentLeg = maps:get('bridge_agent_leg', Context, 'undefined'),
    Candidates = case maps:get('accepted', Context, 'undefined') of
        'undefined' -> maps:values(maps:get('accepted_candidates', Context, #{}));
        Accepted -> [Accepted]
    end,
    Matching = [A || A <- Candidates, kz_json:get_value(<<"Agent-Call-ID">>, A) =:= AgentLeg,
                     lists:any(fun(W) -> acdc_queue_strategy:process_matches(A, W) end, Wins)],
    case {Matching, lists:usort([kz_json:get_value(<<"Agent-ID">>, A) || A <- Matching])} of
        {[Winner|_], [_]} when is_binary(AgentLeg) ->
            callback_commit(AgentLeg, Winner, State#state{callback_ctx=Context#{'accepted' => Winner}});
        _ -> callback_proof_deadline(State)
    end.

callback_proof_deadline(#state{callback_ctx=Context}=State) ->
    Next = case maps:get('timer_ref', Context, 'undefined') of
        'undefined' ->
            Ref = erlang:start_timer(15000, self(), 'callback_proof_deadline'),
            State#state{callback_ctx=Context#{'timer_ref' => Ref}};
        _ -> State
    end,
    callback_start_bridge_probe(Next).

%% Native intercept emits CHANNEL_BRIDGE on the initiating AGENT leg only.
%% The queue listens to the returned member, so selected-agent acceptance also
%% starts a fresh account-scoped reciprocal-channel proof. Acceptance alone
%% never completes a callback and the original 15-second deadline is unchanged.
callback_start_bridge_probe(#state{callback_ctx=Context}=State) ->
    case {maps:get('bridge_agent_leg', Context, 'undefined')
          ,maps:get('bridge_probe_ref', Context, 'undefined'), callback_candidate_legs(State)} of
        {'undefined', 'undefined', [_|_]} ->
            Owner = self(), Ref = make_ref(), Doc = maps:get('reservation', Context),
            _ = spawn(fun() ->
                Result = try acdc_callback_recovery_io:observe(Doc)
                         catch _:_ -> {'error', 'unknown'} end,
                gen_statem:cast(Owner, {'callback_bridge_snapshot', Ref, Result})
            end),
            {'next_state', 'connecting', State#state{callback_ctx=Context#{'bridge_probe_ref' => Ref}}};
        _ -> {'next_state', 'connecting', State}
    end.

callback_candidate_legs(#state{callback_ctx=Context, connect_wins=Wins}) ->
    Candidates = case maps:get('accepted', Context, 'undefined') of
        'undefined' -> maps:values(maps:get('accepted_candidates', Context, #{}));
        Accepted -> [Accepted]
    end,
    lists:usort([Leg || A <- Candidates, Leg <- [kz_json:get_ne_binary_value(<<"Agent-Call-ID">>, A)]
                       ,is_binary(Leg), lists:any(fun(W) -> acdc_queue_strategy:process_matches(A, W) end, Wins)]).

callback_bridge_snapshot(Result, #state{callback_ctx=Context, member_call=Call}=State) ->
    case callback_observed_agent(Result, kapps_call:call_id(Call), callback_candidate_legs(State)) of
        {'ok', Leg} ->
            case maps:get('bridge_agent_leg', Context, Leg) =:= Leg of
                'true' -> callback_record_bridge(Leg, State);
                'false' -> {'next_state', 'connecting', State}
            end;
        'unknown' ->
            Ref = erlang:start_timer(250, self(), 'callback_bridge_snapshot_retry'),
            {'next_state', 'connecting', State#state{callback_ctx=Context#{'bridge_probe_ref' => Ref}}}
    end.

-spec callback_observed_agent(any(), kz_term:ne_binary(), [kz_term:ne_binary()]) ->
          {'ok', kz_term:ne_binary()} | 'unknown'.
callback_observed_agent({'ok', #{'complete' := 'true', 'channels' := Channels
                               ,'bridge' := #{'state' := 'bridged', 'call_ids' := Pair}}}, Caller, Candidates)
  when is_list(Pair), length(Pair) =:= 2, is_list(Channels) ->
    try
        'true' = lists:member(Caller, Pair),
        [Agent] = Pair -- [Caller],
        'true' = Agent =/= Caller andalso lists:member(Agent, Candidates),
        [C] = [O || #{'call_id' := Id}=O <- Channels, Id =:= Caller],
        [A] = [O || #{'call_id' := Id}=O <- Channels, Id =:= Agent],
        #{'state' := 'active', 'answered' := 'true', 'other_leg_call_id' := Agent, 'switch_node' := Node} = C,
        #{'state' := 'active', 'answered' := 'true', 'other_leg_call_id' := Caller, 'switch_node' := Node} = A,
        'true' = is_binary(Node) andalso byte_size(Node) > 0,
        {'ok', Agent}
    catch _:_ -> 'unknown' end;
callback_observed_agent(_, _, _) -> 'unknown'.

-spec callback_commit(kz_term:ne_binary(), kz_json:object(), state()) -> kz_types:handle_fsm_ret(state()).
callback_commit(AgentLeg, Accepted, #state{callback_ctx=Context, account_id=AccountId, queue_id=QueueId
                                          ,member_call=Call, listener_proc=Listener, connect_wins=Wins}=State) ->
    Doc = maps:get('reservation', Context), Id = kz_doc:id(Doc), Token = maps:get('token', Context),
    Result = case acdc_callback_store:bind_leg(AccountId, QueueId, Id, Token, 'agent', AgentLeg) of
        {'ok', _} ->
            Data = kz_json:from_list([{<<"caller_call_id">>, kapps_call:call_id(Call)}
                                      ,{<<"agent_call_id">>, AgentLeg}]),
            acdc_callback_store:advance(AccountId, QueueId, Id, Token, 'bridged', Data);
        _ -> acdc_callback_store:get(AccountId, QueueId, Id)
    end,
    case Result of
        {'ok', Saved} ->
            case kz_json:get_value(<<"status">>, Saved) =:= <<"completed">>
                andalso kz_json:get_value(<<"pvt_caller_call_id">>, Saved) =:= kapps_call:call_id(Call)
                andalso kz_json:get_value(<<"pvt_agent_call_id">>, Saved) =:= AgentLeg of
                'true' ->
                    Losers = [W || W <- Wins, kz_json:get_value(<<"Agent-ID">>, W) =/= kz_json:get_value(<<"Agent-ID">>, Accepted)],
                    lists:foreach(fun(Win) -> acdc_queue_listener:member_connect_satisfied(Listener, Win, []) end, Losers),
                    %% Durable completion precedes the broker ACK; redelivery
                    %% can observe COMPLETED without originating a second call.
                    case callback_finish_terminal(State#state{callback_ctx=Context#{'reservation' => Saved}}) of
                        {'next_state', 'ready', Cleared} ->
                            acdc_stats:call_handled(AccountId, QueueId, acdc_queue_member:logical_id(Call)
                                                   ,kz_json:get_value(<<"Agent-ID">>, Accepted)),
                            {'next_state', 'ready', Cleared};
                        _ -> callback_commit_retry(State#state{callback_ctx=Context#{'reservation' => Saved}})
                    end;
                'false' -> callback_commit_retry(State)
            end;
        _ -> callback_commit_retry(State)
    end.

callback_commit_retry(#state{callback_ctx=Context}=State) ->
    maybe_stop_timer(maps:get('timer_ref', Context, 'undefined')),
    Ref = erlang:start_timer(1000, self(), 'callback_commit_retry'),
    {'next_state', 'connecting', State#state{callback_ctx=Context#{'timer_ref' => Ref}}}.

%% Worker replies and already-delivered cancelled timers can cross a completed
%% handoff. Never crash/log private token-bearing payloads for stale messages.
callback_native_info({'timeout', Ref, 'callback_bridge_snapshot_retry'}, 'connecting'
                      ,#state{callback_ctx=#{'mode' := 'native', 'bridge_probe_ref' := Ref}=Context}=State) ->
    callback_start_bridge_probe(State#state{callback_ctx=maps:remove('bridge_probe_ref', Context)});
callback_native_info({'timeout', Ref, 'callback_proof_deadline'}, _StateName
                      ,#state{callback_ctx=#{'mode' := 'native', 'timer_ref' := Ref}=Context
                              ,account_id=AccountId, member_call=Call, connect_wins=Wins}=State) ->
    case {maps:get('accepted', Context, 'undefined'), maps:get('bridge_agent_leg', Context, 'undefined')} of
        {'undefined', AgentLeg} when is_binary(AgentLeg) ->
            Owner = self(), ProbeRef = make_ref(), CallerId = kapps_call:call_id(Call),
            _ = spawn(fun() ->
                Result = try acdc_callback_agent_probe:probe(AccountId, CallerId, Wins, AgentLeg)
                         catch _:_ -> {'error', 'unknown'} end,
                gen_statem:cast(Owner, {'callback_accept_probe', ProbeRef, Result})
            end),
            Deadline = erlang:start_timer(6000, self(), 'callback_accept_probe_deadline'),
            {'next_state', 'connecting', State#state{callback_ctx=Context#{'accept_probe_ref' => ProbeRef
                                                                         ,'timer_ref' => Deadline}}};
        {Accepted, AgentLeg} when Accepted =/= 'undefined', is_binary(AgentLeg) -> callback_complete(State);
        _ -> callback_native_end('agent_unavailable', State)
    end;
callback_native_info({'timeout', Ref, 'callback_accept_probe_deadline'}, _StateName
                      ,#state{callback_ctx=#{'mode' := 'native', 'timer_ref' := Ref}}=State) ->
    callback_native_end('agent_unavailable', State);
callback_native_info({'timeout', Ref, 'callback_lease_tick'}, StateName
                      ,#state{callback_ctx=#{'mode' := 'native', 'lease_timer_ref' := Ref}}=State) ->
    case callback_keep_lease(State) of
        {'ok', #state{callback_ctx=Context}=Next} ->
            Timer = erlang:start_timer(5000, self(), 'callback_lease_tick'),
            {'next_state', StateName, Next#state{callback_ctx=Context#{'lease_timer_ref' => Timer}}};
        {'error', Next} -> callback_native_end('agent_unavailable', Next)
    end;
callback_native_info({'DOWN', _Ref, 'process', _Pid, _Reason}, StateName, State) ->
    {'next_state', StateName, State};
callback_native_info({'timeout', _Ref, _Tag}, StateName, State) ->
    {'next_state', StateName, State};
callback_native_info(Event, StateName, State) when is_tuple(Event), tuple_size(Event) >= 1 ->
    case element(1, Event) of
        'acdc_callback_caller_ready' -> {'next_state', StateName, State};
        'acdc_callback_caller_confirmed' -> {'next_state', StateName, State};
        'acdc_callback_caller_failed' -> {'next_state', StateName, State};
        _ -> {'next_state', StateName, State}
    end;
callback_native_info(_, StateName, State) -> {'next_state', StateName, State}.

callback_keep_lease(#state{account_id=AccountId, queue_id=QueueId, callback_ctx=Context}=State) ->
    Doc = maps:get('reservation', Context), Token = maps:get('token', Context),
    Remaining = kz_json:get_integer_value([<<"pvt_lease">>, <<"until">>], Doc, 0) - kz_time:now_s(),
    case Remaining > 60 of
        'true' -> {'ok', State};
        'false' ->
            case acdc_callback_store:renew(AccountId, QueueId, kz_doc:id(Doc), Token, 300) of
                {'ok', Renewed} -> {'ok', State#state{callback_ctx=Context#{'reservation' => Renewed}}};
                {'error', Reason} when (Reason =:= 'conflict' orelse Reason =:= 'timeout'), Remaining > 10 ->
                    {'ok', State};
                _ -> {'error', State}
            end
    end.

callback_native_end(Cause, #state{account_id=AccountId, queue_id=QueueId, callback_ctx=Context
                                 ,member_call=Call, listener_proc=Listener, connect_wins=Wins
                                 ,member_call_winners=Winners, collect_ref=CollectRef
                                 ,connection_timer_ref=ConnRef, agent_ring_timer_ref=AgentRef}=State) ->
    %% Native call completion/failure must not ACK the logical callback while
    %% its durable state still says CONNECTING. Keep its delivery for cleanup.
    maybe_stop_timer(CollectRef), maybe_stop_timer(ConnRef), maybe_stop_timer(AgentRef),
    Doc = maps:get('reservation', Context),
    Next = State#state{collect_ref='undefined', connection_timer_ref='undefined'
                       ,agent_ring_timer_ref='undefined'
                       ,callback_ctx=Context#{'mode' => 'native_ending', 'end_cause' => Cause}},
    case acdc_callback_store:cancel(AccountId, QueueId, kz_doc:id(Doc)) of
        {'ok', Cancelling} ->
            lists:foreach(fun(Winner) -> acdc_queue_listener:timeout_agent(Listener, Winner) end
                          ,lists:usort(Wins ++ Winners)),
            kapps_call_command:hangup(Call),
            callback_schedule(Next#state{callback_ctx=(Next#state.callback_ctx)#{'reservation' => Cancelling
                                                                               ,'mode' => 'reconciliation'}}, 1000);
        {'error', 'already_finished'} ->
            %% A completion CAS can have succeeded before its acknowledgement
            %% was lost. Re-read rather than treating that as cancellation.
            case acdc_callback_store:get(AccountId, QueueId, kz_doc:id(Doc)) of
                {'ok', Saved} ->
                    case kz_json:get_value(<<"status">>, Saved) of
                        <<"completed">> -> callback_finish_terminal(State);
                        _ -> callback_schedule(Next, 2000)
                    end;
                _ -> callback_schedule(Next, 2000)
            end;
        _ -> callback_schedule(Next, 2000)
    end.

callback_timeout(Queue, Key, Default, Maximum) ->
    case kz_json:get_value([<<"callback">>, Key], Queue, Default) of
        Milliseconds when is_integer(Milliseconds), Milliseconds >= 1000, Milliseconds =< Maximum -> Milliseconds;
        _ -> Default
    end.

-ifdef(TEST).
-spec callback_test_state(kz_term:proplist()) -> state().
callback_test_state(Values) ->
    Default = #state{},
    Fields = lists:zip(record_info(fields, state), lists:seq(2, record_info(size, state))),
    list_to_tuple(['state' | [props:get_value(Name, Values, element(Index, Default)) || {Name, Index} <- Fields]]).

-spec callback_test_field(atom(), state()) -> any().
callback_test_field(Name, State) ->
    Fields = lists:zip(record_info(fields, state), lists:seq(2, record_info(size, state))),
    element(props:get_value(Name, Fields), State).
-endif.
