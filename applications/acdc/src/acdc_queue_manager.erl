%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2012-2020, 2600Hz
%%% @doc Manages queue processes:
%%%   starting when a queue is created
%%%   stopping when a queue is deleted
%%%   collecting stats from queues
%%%   and more!!!
%%%
%%% @author Sponsored by GTNetwork LLC, Implemented by SIPLABS LLC
%%% @author Daniel Finke
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(acdc_queue_manager).
-behaviour(gen_listener).

%% API
-export([start_link/3
        ,handle_member_call/2
        ,handle_member_call_success/2
        ,handle_member_call_cancel/2
        ,handle_agent_change/2
        ,handle_queue_member_add/2
        ,handle_queue_member_replace/2
        ,handle_queue_member_remove/2
        ,has_agents/1
        ,handle_config_change/2
        ,queue_size/1
        ,maintenance_state/2
        ,should_ignore_member_call/3, should_ignore_member_call/4
        ,up_next/2
        ,ensure_member/2
        ,ensure_callback_member/3
        ,replace_member_call/6
        ,retire_callback_member/3
        ,ready_agent_count/1
        ,logical_member_id/1
        ,member_order_key/1
        ,member_registration_metadata/1
        ,stop_announcements/2
        ,resume_announcements/2
        ,config/1
        ,status/1
        ,agents/1
        ,refresh/2
        ,add_diagnostics_receiver/2
        ,remove_diagnostics_receiver/2
        ]).

%% FSM helpers
-export([pick_winner/2, pick_winner/3]).

%% gen_server callbacks
-export([init/1
        ,handle_call/3
        ,handle_cast/2
        ,handle_info/2
        ,handle_event/2
        ,terminate/2
        ,code_change/3
        ]).

-ifdef(TEST).
-export([update_strategy_with_agent/3

        ,assignable_agent_count/1
        ,agent_count/1
        ,take_position_announcement/2
        ,ensure_legacy_member/2
        ,callback_recovery_call/4
        ,valid_recovered_existing/5
        ,retire_member_matches/3
        ,update_properties/2
        ]).
-endif.

-include("acdc.hrl").
-include("acdc_queue_manager.hrl").

-define(SERVER, ?MODULE).

-define(BINDINGS(A, Q), [{'conf', [{'type', <<"queue">>}
                                  ,{'db', kzs_util:format_account_db(A)}
                                  ,{'id', Q}
                                  ,'federate'
                                  ]}
                        ,{'acdc_queue', [{'restrict_to', ['stats_req', 'agent_change'
                                                         ,'member_addremove', 'member_call_result'
                                                         ]}
                                        ,{'account_id', A}
                                        ,{'queue_id', Q}
                                        ]}
                        ,{'presence', [{'restrict_to', ['probe']}]}
                        ]).

-define(RESPONDERS, [{{'acdc_queue_handler', 'handle_config_change'}
                     ,[{<<"configuration">>, <<"*">>}]
                     }
                    ,{{'acdc_queue_handler', 'handle_stats_req'}
                     ,[{<<"queue">>, <<"stats_req">>}]
                     }
                    ,{{'acdc_queue_handler', 'handle_presence_probe'}
                     ,[{<<"presence">>, <<"probe">>}]
                     }
                    ,{{?MODULE, 'handle_member_call'}
                     ,[{<<"member">>, <<"call">>}]
                     }
                    ,{{?MODULE, 'handle_member_call_success'}
                     ,[{<<"member">>, <<"call_success">>}]
                     }
                    ,{{?MODULE, 'handle_member_call_cancel'}
                     ,[{<<"member">>, <<"call_cancel">>}]
                     }
                    ,{{?MODULE, 'handle_agent_change'}
                     ,[{<<"queue">>, <<"agent_change">>}]
                     }
                    ,{{?MODULE, 'handle_queue_member_add'}
                     ,[{<<"queue">>, <<"member_add">>}]
                     }
                    ,{{?MODULE, 'handle_queue_member_replace'}
                     ,[{<<"queue">>, <<"member_replace">>}]
                     }
                    ,{{?MODULE, 'handle_queue_member_remove'}
                     ,[{<<"queue">>, <<"member_remove">>}]
                     }
                    ]).

-define(SECONDARY_BINDINGS(AccountId, QueueId)
       ,[{'acdc_queue', [{'restrict_to', ['member_call']}
                        ,{'account_id', AccountId}
                        ,{'queue_id', QueueId}
                        ]}
        ]).
-define(SECONDARY_QUEUE_NAME(QueueId), <<"acdc.queue.manager.", QueueId/binary>>).
-define(SECONDARY_QUEUE_OPTIONS(MaxPriority), [{'exclusive', 'false'}
                                              ,{'arguments',[{<<"x-max-priority">>, MaxPriority}]}
                                              ]).
-define(SECONDARY_CONSUME_OPTIONS, [{'exclusive', 'false'}]).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Starts the server.
%% @end
%%------------------------------------------------------------------------------
-spec start_link(pid(), kz_term:ne_binary(), kz_term:ne_binary()) -> kz_types:startlink_ret().
start_link(Super, AccountId, QueueId) ->
    gen_listener:start_link(?SERVER
                           ,[{'bindings', ?BINDINGS(AccountId, QueueId)}
                            ,{'responders', ?RESPONDERS}
                            ]
                           ,[Super, AccountId, QueueId]
                           ).

-spec handle_member_call(kz_json:object(), kz_term:proplist()) -> 'ok'.
handle_member_call(JObj, Props) ->
    'true' = kapi_acdc_queue:member_call_v(JObj),
    _ = kz_log:put_callid(JObj),

    Call = kapps_call:from_json(kz_json:get_value(<<"Call">>, JObj)),
    Srv = props:get_value('server', Props),

    case has_agents(Srv, props:get_value('enter_when_empty', Props)) of
        'false' ->
            lager:info("no agents are available to take the call, cancel queueing"),
            gen_listener:cast(props:get_value('server', Props)
                             ,{'reject_member_call', Call, JObj}
                             );
        'true' ->
            start_queue_call(JObj, Props, Call)
    end.

%%------------------------------------------------------------------------------
%% @doc Return true if the queue operated by `Srv' has at least 1 agent or
%% should behave as if it does (`enter_when_empty' is enabled).
%% @end
%%------------------------------------------------------------------------------
-spec has_agents(kz_types:server_ref()) -> boolean().
has_agents(Srv) ->
    has_agents(Srv, gen_listener:call(Srv, 'enter_when_empty')).

%%------------------------------------------------------------------------------
%% @doc Return true if `EnterWhenEmpty' is true, otherwise return true if the
%% queue operated by `Srv' has at least 1 agent.
%% @end
%%------------------------------------------------------------------------------
-spec has_agents(kz_types:server_ref(), boolean()) -> boolean().
has_agents(Srv, EnterWhenEmpty) ->
    EnterWhenEmpty
        orelse gen_listener:call(Srv, 'get_has_agents').

start_queue_call(JObj, Props, Call) ->
    _ = kapps_call:put_callid(Call),
    QueueId = kz_json:get_value(<<"Queue-ID">>, JObj),

    lager:info("member call for queue ~s recv", [QueueId]),
    lager:debug("answering call"),
    kapps_call_command:answer_now(Call),

    case kz_media_util:media_path(props:get_value('moh', Props)
                                 ,kapps_call:account_id(Call)
                                 )
    of
        'undefined' ->
            lager:debug("using default moh"),
            kapps_call_command:hold(Call);
        MOH ->
            lager:debug("using MOH ~s (~p)", [MOH, Props]),
            kapps_call_command:hold(MOH, Call)
    end,

    JObj2 = kz_json:set_value([<<"Call">>, <<"Custom-Channel-Vars">>, <<"Queue-ID">>], QueueId, JObj),

    _ = kapps_call_command:set('undefined'
                              ,kz_json:from_list([{<<"Eavesdrop-Group-ID">>, QueueId}
                                                 ,{<<"Queue-ID">>, QueueId}
                                                 ])
                              ,Call
                              ),

    %% Add member to queue for tracking position
    gen_listener:cast(props:get_value('server', Props), {'add_queue_member', JObj2}).

-spec handle_member_call_success(kz_json:object(), kz_term:proplist()) -> 'ok'.
handle_member_call_success(JObj, Prop) ->
    gen_listener:cast(props:get_value('server', Prop), {'handle_queue_member_remove', kz_json:get_value(<<"Call-ID">>, JObj)}).

-spec handle_member_call_cancel(kz_json:object(), kz_term:proplist()) -> 'ok'.
handle_member_call_cancel(JObj, Props) ->
    'true' = kapi_acdc_queue:member_call_cancel_v(JObj),
    _ = kz_log:put_callid(JObj),
    K = make_ignore_key(kz_json:get_value(<<"Account-ID">>, JObj)
                       ,kz_json:get_value(<<"Queue-ID">>, JObj)
                       ,kz_json:get_value(<<"Call-ID">>, JObj)
                       ),
    gen_listener:cast(props:get_value('server', Props), {'member_call_cancel', K, JObj}).

-spec handle_agent_change(kz_json:object(), kz_term:proplist()) -> 'ok'.
handle_agent_change(JObj, Prop) ->
    'true' = kapi_acdc_queue:agent_change_v(JObj),
    Server = props:get_value('server', Prop),
    case kz_json:get_value(<<"Change">>, JObj) of
        <<"available">> ->
            gen_listener:cast(Server, {'agent_available', JObj});
        <<"ringing">> ->
            gen_listener:cast(Server, {'agent_ringing', JObj});
        <<"busy">> ->
            gen_listener:cast(Server, {'agent_busy', JObj});
        <<"unavailable">> ->
            gen_listener:cast(Server, {'agent_unavailable', JObj})
    end.

-spec handle_queue_member_add(kz_json:object(), kz_term:proplist()) -> 'ok'.
handle_queue_member_add(JObj, Prop) ->
    gen_listener:cast(props:get_value('server', Prop), {'handle_queue_member_add', JObj}).

-spec handle_queue_member_replace(kz_json:object(), kz_term:proplist()) -> 'ok'.
handle_queue_member_replace(JObj, Prop) ->
    'true' = kapi_acdc_queue:queue_member_replace_v(JObj),
    gen_listener:cast(props:get_value('server', Prop), {'handle_queue_member_replace', JObj}).

-spec handle_queue_member_remove(kz_json:object(), kz_term:proplist()) -> 'ok'.
handle_queue_member_remove(JObj, Prop) ->
    gen_listener:cast(props:get_value('server', Prop), {'handle_queue_member_remove', kz_json:get_value(<<"Call-ID">>, JObj)}).

-spec handle_config_change(kz_types:server_ref(), kz_json:object()) -> 'ok'.
handle_config_change(Srv, JObj) ->
    gen_listener:cast(Srv, {'update_queue_config', JObj}).

-spec queue_size(kz_types:server_ref()) -> kz_term:non_neg_integer().
queue_size(Srv) ->
    gen_listener:call(Srv, 'queue_size').

%% Queue size alone excludes neither announcement jobs nor pending cancellation
%% ownership. This local observation never asserts a cluster/broker fence.
-spec maintenance_state(pid(), pos_integer()) -> {'ok', map()} | {'error', atom()}.
maintenance_state(Srv, Timeout) -> gen_listener:call(Srv, 'maintenance_state', Timeout).

-spec should_ignore_member_call(kz_types:server_ref(), kapps_call:call(), kz_json:object()) -> boolean().
should_ignore_member_call(Srv, Call, CallJObj) ->
    should_ignore_member_call(Srv
                             ,Call
                             ,kz_json:get_value(<<"Account-ID">>, CallJObj)
                             ,kz_json:get_value(<<"Queue-ID">>, CallJObj)
                             ).

-spec should_ignore_member_call(kz_types:server_ref(), kapps_call:call(), kz_term:ne_binary(), kz_term:ne_binary()) -> boolean().
should_ignore_member_call(Srv, Call, AccountId, QueueId) ->
    K = make_ignore_key(AccountId, QueueId, kapps_call:call_id(Call)),
    gen_listener:call(Srv, {'should_ignore_member_call', K}).

-spec up_next(pid(), kz_term:ne_binary()) -> boolean().
up_next(Srv, CallId) ->
    gen_listener:call(Srv, {'up_next', CallId}).

%% Recover a stamped logical member without producing duplicate waiting stats.
-spec ensure_member(kz_types:server_ref(), kapps_call:call()) ->
          {'ok', pos_integer()} | {'error', any()}.
ensure_member(Srv, Call) ->
    gen_listener:call(Srv, {'ensure_member', Call}).

%% Recreate or locate a logical member only from the fresh, account-scoped
%% durable callback document supplied by the coordinator.
-spec ensure_callback_member(kz_types:server_ref(), kapps_call:call(), kz_json:object()) ->
          {'ok', pos_integer(), kapps_call:call()} | {'error', atom()}.
ensure_callback_member(Srv, Call, Doc) ->
    gen_listener:call(Srv, {'ensure_callback_member', Call, Doc}).

%% Replace only the physical channel. AttemptId is the public caller-leg UUID,
%% not the callback store lease token.
-spec replace_member_call(kz_types:server_ref(), kz_term:ne_binary(),
                          kz_term:ne_binary(), pos_integer(), kz_term:ne_binary(),
                          kapps_call:call()) ->
          {'ok', pos_integer(), kapps_call:call()} | {'error', any()}.
replace_member_call(Srv, LogicalId, CallbackId, Attempt, AttemptId, NewCall) ->
    gen_listener:call(Srv, {'replace_member_call', LogicalId, CallbackId,
                            Attempt, AttemptId, NewCall}).

%% Terminal retirement is synchronous so a listener never ACKs the shared
%% delivery before the manager has removed the logical slot.
-spec retire_callback_member(kz_types:server_ref(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          'ok' | {'error', atom()}.
retire_callback_member(Srv, LogicalId, CallbackId) ->
    gen_listener:call(Srv, {'retire_callback_member', LogicalId, CallbackId}).

-spec ready_agent_count(kz_types:server_ref()) -> non_neg_integer().
ready_agent_count(Srv) -> gen_listener:call(Srv, 'ready_agent_count').

-spec logical_member_id(kapps_call:call()) -> kz_term:ne_binary().
logical_member_id(Call) -> acdc_queue_member:logical_id(Call).

-spec member_order_key(kapps_call:call()) -> tuple().
member_order_key(Call) -> acdc_queue_member:member_order_key(Call).

-spec member_registration_metadata(kapps_call:call()) ->
          {'ok', kz_json:object()} | {'error', 'missing_metadata'}.
member_registration_metadata(Call) -> acdc_queue_member:registration_metadata(Call).

%% Stop only the periodic position/wait announcement producer. The member
%% remains in current_member_calls, so queue position and waiting stats are
%% unchanged while its one-time pre-connect announcement is played.
-spec stop_announcements(pid(), kz_term:ne_binary()) -> 'ok'.
stop_announcements(Srv, CallId) ->
    gen_listener:call(Srv, {'stop_announcements', CallId}).

%% Resume periodic position/wait announcements after a callback menu is
%% cancelled. This is idempotent and only applies while the original live
%% channel still represents the member.
-spec resume_announcements(pid(), kz_term:ne_binary()) -> 'ok'.
resume_announcements(Srv, LogicalId) ->
    gen_listener:call(Srv, {'resume_announcements', LogicalId}).

-spec config(pid()) -> {kz_term:ne_binary(), kz_term:ne_binary()}.
config(Srv) -> gen_listener:call(Srv, 'config').

%%------------------------------------------------------------------------------
%% @doc Return the IDs of the agents in the queue operated by `Srv'.
%% @end
%%------------------------------------------------------------------------------
-spec agents(kz_types:server_ref()) -> kz_term:ne_binaries().
agents(Srv) -> gen_listener:call(Srv, 'get_agents').

-spec status(pid()) -> kz_term:ne_binaries().
status(Srv) -> gen_listener:call(Srv, 'status').

-spec refresh(pid(), kz_json:object()) -> 'ok'.
refresh(Mgr, QueueJObj) -> gen_listener:cast(Mgr, {'refresh', QueueJObj}).

-spec pick_winner(pid(), kz_json:objects()) ->
          'undefined' |
          {kz_json:objects(), kz_json:objects()}.
pick_winner(Srv, Resps) ->
    case pick_winner(Srv, Resps, []) of
        'undefined' -> 'undefined';
        {Winners, Others, _} -> {Winners, Others}
    end.

-spec pick_winner(pid(), kz_json:objects(), kz_term:ne_binaries()) ->
          'undefined' | {kz_json:objects(), kz_json:objects(), kz_term:ne_binaries()}.
pick_winner(Srv, Resps, Attempted) ->
    gen_listener:call(Srv, {'pick_winner', Resps, Attempted}).

%%------------------------------------------------------------------------------
%% @doc Add a diagnostics receiver to the queue manager as a recipient of
%% strategy state diagnostic messages.
%% @end
%%------------------------------------------------------------------------------
-spec add_diagnostics_receiver(kz_types:server_ref(), pid()) -> any().
add_diagnostics_receiver(Srv, Receiver) ->
    gen_listener:call(Srv, {'add_diagnostics_receiver', Receiver}).

%%------------------------------------------------------------------------------
%% @doc Remove a previously-added diagnostics receiver from the queue manager.
%% @end
%%------------------------------------------------------------------------------
-spec remove_diagnostics_receiver(kz_types:server_ref(), pid()) -> any().
remove_diagnostics_receiver(Srv, Receiver) ->
    gen_listener:call(Srv, {'remove_diagnostics_receiver', Receiver}).

%%%=============================================================================
%%% gen_server callbacks
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Initializes the server.
%% @end
%%------------------------------------------------------------------------------
-spec init([pid() | kz_json:object() | kz_term:ne_binary()]) -> {'ok', mgr_state()}.
init([Super, AccountId, QueueId]) ->
    kz_log:put_callid(<<"mgr_", QueueId/binary>>),
    put(?KEY_DIAGNOSTICS_PIDS, []),

    AcctDb = kzs_util:format_account_db(AccountId),
    {'ok', QueueJObj} = kz_datamgr:open_cache_doc(AcctDb, QueueId),

    _ = start_secondary_queue(AccountId, QueueId),

    gen_listener:cast(self(), {'start_workers'}),
    Strategy = get_strategy(kz_json:get_value(<<"strategy">>, QueueJObj)),
    StrategyState = create_strategy_state(Strategy),

    lager:debug("queue mgr started for ~s", [QueueId]),
    {'ok', update_properties(QueueJObj, #state{account_id=AccountId
                                              ,queue_id=QueueId
                                              ,supervisor=Super
                                              ,strategy=Strategy
                                              ,strategy_state=StrategyState
                                              })}.

%%------------------------------------------------------------------------------
%% @doc Handling call messages.
%% @end
%%------------------------------------------------------------------------------
-spec handle_call(any(), kz_term:pid_ref(), mgr_state()) -> kz_types:handle_call_ret_state(mgr_state()).
handle_call('maintenance_state', _, State) ->
    {'reply', maintenance_snapshot(State), State};
handle_call('queue_size', _, #state{current_member_calls=Calls}=State) ->
    {'reply', length(Calls), State};
handle_call('ready_agent_count', _, State) ->
    {'reply', ready_agent_count_state(State), State};
handle_call({'ensure_member', Call}, _, #state{account_id=AccountId
                                              ,queue_id=QueueId
                                              ,current_member_calls=Calls
                                              }=State) ->
    case acdc_queue_member:ensure(Call, Calls) of
        {'ok', Calls0, Position, 'inserted'} ->
            Call1 = kapps_call:set_custom_channel_var(<<"Queue-Position">>, Position, Call),
            Calls1 = replace_logical_call(Call1, Calls0),
            publish_queue_member_add(AccountId, QueueId, Call1),
            {'reply', {'ok', Position}, State#state{current_member_calls=Calls1}};
        {'ok', _Calls0, Position, 'existing'} ->
            {'reply', {'ok', Position}, State};
        {'error', 'missing_metadata'} ->
            case ensure_legacy_member(Call, Calls) of
                {'ok', Calls1, Position, Canonical} ->
                    publish_queue_member_add(AccountId, QueueId, Canonical),
                    {'reply', {'ok', Position}, State#state{current_member_calls=Calls1}};
                {'error', _}=Error -> {'reply', Error, State}
            end;
        {'error', _}=Error -> {'reply', Error, State}
    end;
handle_call({'ensure_callback_member', Call, Doc}, _,
            #state{account_id=AccountId, queue_id=QueueId,
                   current_member_calls=Calls}=State) ->
    case callback_recovery_call(AccountId, QueueId, Call, Doc) of
        {'error', _}=Error -> {'reply', Error, State};
        {'ok', LogicalId, CallbackId, Attempt, CallerId, Restored} ->
            case acdc_queue_member:lookup(LogicalId, Calls) of
                {Existing, Position} ->
                    case valid_recovered_existing(Existing, Doc, CallbackId, Attempt, CallerId) of
                        'true' -> {'reply', {'ok', Position, Existing}, State};
                        'false' -> {'reply', {'error', 'identity_conflict'}, State}
                    end;
                'undefined' ->
                    case acdc_queue_member:ensure(Restored, Calls) of
                        {'ok', Calls0, Position, 'inserted'} ->
                            Canonical = kapps_call:set_custom_channel_var(<<"Queue-Position">>, Position, Restored),
                            Calls1 = replace_logical_call(Canonical, Calls0),
                            publish_queue_member_add(AccountId, QueueId, Canonical),
                            {'reply', {'ok', Position, Canonical},
                             State#state{current_member_calls=Calls1}};
                        {'ok', _Calls0, Position, 'existing'} ->
                            {Canonical, Position} = acdc_queue_member:lookup(LogicalId, Calls),
                            {'reply', {'ok', Position, Canonical}, State};
                        {'error', _}=Error -> {'reply', Error, State}
                    end
            end
    end;
handle_call({'retire_callback_member', LogicalId, CallbackId}, _,
            #state{account_id=AccountId, queue_id=QueueId,
                   current_member_calls=Calls}=State) ->
    case terminal_callback_proof(AccountId, QueueId, LogicalId, CallbackId) of
        {'error', _}=Error -> {'reply', Error, State};
        'ok' ->
            case retire_member_matches(LogicalId, CallbackId, Calls) of
                'false' -> {'reply', {'error', 'identity_conflict'}, State};
                'true' ->
                    case safe_publish_queue_member_remove(AccountId, QueueId, LogicalId) of
                        'ok' -> {'reply', 'ok', remove_queue_member(LogicalId, State)};
                        {'error', _}=Error -> {'reply', Error, State}
                    end
            end
    end;
handle_call({'replace_member_call', LogicalId, CallbackId, Attempt, AttemptId, NewCall0}, _,
            #state{account_id=AccountId
                  ,queue_id=QueueId
                  ,current_member_calls=Calls
                  }=State) ->
    NewCall = case acdc_queue_member:position(LogicalId, Calls) of
                  ExistingPosition when is_integer(ExistingPosition) ->
                      kapps_call:set_custom_channel_var(<<"Queue-Position">>, ExistingPosition, NewCall0);
                  _ -> NewCall0
              end,
    case acdc_queue_member:replace(LogicalId, CallbackId, Attempt, AttemptId, NewCall, Calls) of
        {'ok', Calls1, Position, 'duplicate'} ->
            {CanonicalCall, Position} = acdc_queue_member:lookup(LogicalId, Calls1),
            {'reply', {'ok', Position, CanonicalCall},
             State#state{current_member_calls=Calls1}};
        {'ok', Calls1, Position, 'replaced'} ->
            {Replacement, Position} = acdc_queue_member:lookup(LogicalId, Calls1),
            publish_queue_member_replace(AccountId, QueueId, LogicalId, CallbackId,
                                         Attempt, AttemptId, Replacement),
            {'reply', {'ok', Position, Replacement},
             State#state{current_member_calls=Calls1}};
        {'error', _}=Error -> {'reply', Error, State}
    end;
handle_call({'should_ignore_member_call', {AccountId, QueueId, CallId}=K}, _, #state{ignored_member_calls=Dict
                                                                                    ,account_id=AccountId
                                                                                    ,queue_id=QueueId
                                                                                    }=State) ->
    case catch dict:fetch(K, Dict) of
        {'EXIT', _} -> {'reply', 'false', State};
        _Res ->
            publish_queue_member_remove(AccountId, QueueId, CallId),
            {'reply', 'true', State#state{ignored_member_calls=dict:erase(K, Dict)}}
    end;

handle_call({'up_next', CallId}, _, #state{current_member_calls=Calls}=State) ->
    Position = queue_member_position(CallId, Calls),
    {'reply', is_integer(Position) andalso assignable_agent_count(State) >= Position, State};

handle_call('config', _, #state{account_id=AccountId
                               ,queue_id=QueueId
                               }=State) ->
    {'reply', {AccountId, QueueId}, State};

handle_call('strategy', _, #state{strategy=Strategy}=State) ->
    {'reply', Strategy, State, 'hibernate'};

handle_call({'pick_winner', Responses, Attempted}, _,
            #state{strategy=Strategy, strategy_state=SS, agent_order=Order}=State) ->
    case acdc_queue_strategy:select(Strategy, ready_agents(State), Order, Attempted, Responses) of
        'undefined' -> {'reply', 'undefined', State};
        {Winners, Others, Ready, NextAttempted} ->
            Agents = strategy_agents(Strategy, Ready),
            {'reply', {Winners, Others, NextAttempted}, State#state{strategy_state=SS#strategy_state{agents=Agents}}}
    end;

handle_call('enter_when_empty', _, #state{enter_when_empty=EnterWhenEmpty}=State) ->
    {'reply', EnterWhenEmpty, State};

handle_call('next_winner', _, #state{strategy='mi'}=State) ->
    {'reply', 'undefined', State};
handle_call('next_winner', _, #state{strategy='rr'
                                    ,strategy_state=#strategy_state{agents=Agents}=SS
                                    }=State) ->
    case queue:out(Agents) of
        {{'value', Winner}, Agents1} ->
            ?DIAG("got next winner from ~p", [queue:to_list(Agents)]),
            {'reply', Winner, State#state{strategy_state=SS#strategy_state{agents=queue:in(Winner, Agents1)}}, 'hibernate'};
        {'empty', _} ->
            {'reply', 'undefined', State}
    end;
handle_call('next_winner', _, #state{strategy=Strategy}=State) when Strategy =:= 'all'; Strategy =:= 'ord' ->
    {'reply', 'undefined', State};

handle_call('get_agents', _, State) ->
    {'reply', agents_(State), State};

handle_call('get_has_agents', _, State) ->
    {'reply', agent_count(State) > 0, State};

handle_call({'queue_position', CallId}, _, #state{current_member_calls=Calls}=State) ->
    Position = queue_member_position(CallId, Calls),
    {'reply', Position, State};

handle_call({'stop_announcements', CallId}, _, #state{announcements_pids=Pids}=State) ->
    Pids1 = stop_position_announcements(CallId, Pids),
    {'reply', 'ok', State#state{announcements_pids=Pids1}};
handle_call({'resume_announcements', LogicalId}, _,
            #state{current_member_calls=Calls
                  ,announcements_config=Config
                  ,announcements_pids=Pids
                  }=State) ->
    case maps:is_key(LogicalId, Pids) of
        'true' -> {'reply', 'ok', State};
        'false' ->
            case queue_member(LogicalId, Calls) of
                'undefined' -> {'reply', 'ok', State};
                Call -> resume_position_announcements(LogicalId, Call, Config, Pids, State)
            end
    end;

handle_call({'add_diagnostics_receiver', Receiver}, _, State) ->
    DiagnosticsPids = get(?KEY_DIAGNOSTICS_PIDS),
    put(?KEY_DIAGNOSTICS_PIDS, [Receiver | DiagnosticsPids]),
    lager:debug("added ~p to diagnostics receivers", [Receiver]),
    {'reply', 'ok', State};

handle_call({'remove_diagnostics_receiver', Receiver}, _, State) ->
    DiagnosticsPids = get(?KEY_DIAGNOSTICS_PIDS),
    put(?KEY_DIAGNOSTICS_PIDS, lists:delete(Receiver, DiagnosticsPids)),
    lager:debug("removed ~p from diagnostics receivers", [Receiver]),
    {'reply', 'ok', State};

handle_call(_Request, _From, State) ->
    {'reply', 'ok', State}.

maintenance_snapshot(#state{account_id=AccountId, queue_id=QueueId,
                            supervisor=Supervisor, current_member_calls=[],
                            announcements_pids=Announcements,
                            ignored_member_calls=Ignored,
                            strategy_state=#strategy_state{ringing_agents=[], busy_agents=[]}})
  when is_binary(AccountId), byte_size(AccountId)>0,
       is_binary(QueueId), byte_size(QueueId)>0, is_pid(Supervisor),
       is_map(Announcements), map_size(Announcements)=:=0 ->
    %% A leftover cancellation may still suppress a queued broker delivery.
    %% Do not discard it or expose its call identifiers just to pass the gate.
    case catch dict:size(Ignored) of
        0 -> {'ok', #{account_id=>AccountId, queue_id=>QueueId, supervisor=>Supervisor}};
        _ -> {'error', 'queue_manager_not_drained'}
    end;
maintenance_snapshot(_) -> {'error', 'queue_manager_not_drained'}.

%%------------------------------------------------------------------------------
%% @doc Handling cast messages.
%% @end
%%------------------------------------------------------------------------------
-spec handle_cast(any(), mgr_state()) -> kz_types:handle_cast_ret_state(mgr_state()).
handle_cast({'update_strategy', StrategyState}, State) ->
    {'noreply', State#state{strategy_state=StrategyState}, 'hibernate'};

handle_cast({'update_queue_config', JObj}, #state{enter_when_empty=_EnterWhenEmpty}=State) ->
    EWE = kz_json:is_true([<<"Doc">>, <<"enter_when_empty">>], JObj, 'true'),
    lager:debug("maybe changing ewe from ~s to ~s", [_EnterWhenEmpty, EWE]),
    {'noreply', State#state{enter_when_empty=EWE}, 'hibernate'};

handle_cast({'member_call_cancel', K, JObj}, #state{ignored_member_calls=Dict
                                                   ,current_member_calls=Calls
                                                   }=State) ->
    AccountId = kz_json:get_value(<<"Account-ID">>, JObj),
    QueueId = kz_json:get_value(<<"Queue-ID">>, JObj),
    CallId = kz_json:get_value(<<"Call-ID">>, JObj),
    Reason = kz_json:get_value(<<"Reason">>, JObj),

    'ok' = acdc_stats:call_abandoned(AccountId, QueueId, CallId, Reason),

    %% For cancels triggered outside of cf_acdc_member, inform cf_acdc_member
    %% proc to continue
    case queue_member(CallId, Calls) of
        'undefined' -> 'ok';
        Call ->
            Q = kapps_call:controller_queue(Call),
            publish_member_call_failure(Q, AccountId, QueueId, CallId, Reason)
    end,

    {'noreply', State#state{ignored_member_calls=dict:store(K, 'true', Dict)}};

handle_cast({'start_workers'}, #state{account_id=AccountId
                                     ,queue_id=QueueId
                                     ,supervisor=QueueSup
                                     }=State) ->
    WorkersSup = acdc_queue_sup:workers_sup(QueueSup),
    case kz_datamgr:get_results(kzs_util:format_account_db(AccountId)
                               ,<<"queues/agents_listing">>
                               ,[{'startkey', [QueueId]}
                                ,{'endkey', [QueueId, kz_json:new()]}
                                ,{'group', 'true'}
                                ,{'group_level', 1}
                                ])
    of
        {'ok', []} ->
            lager:debug("no agents yet, but create a worker anyway"),
            acdc_queue_workers_sup:new_worker(WorkersSup, AccountId, QueueId);
        {'ok', [Result]} ->
            QWC = kz_json:get_integer_value(<<"value">>, Result),
            acdc_queue_workers_sup:new_workers(WorkersSup, AccountId, QueueId, QWC),
            'ok';
        {'error', _E} ->
            lager:debug("failed to find agent count: ~p", [_E]),
            QWC = kapps_config:get_integer(?CONFIG_CAT, <<"queue_worker_count">>, 5),
            acdc_queue_workers_sup:new_workers(WorkersSup, AccountId, QueueId, QWC)
    end,
    {'noreply', State};

handle_cast({'start_worker'}, State) ->
    handle_cast({'start_worker', 1}, State);
handle_cast({'start_worker', N}, #state{account_id=AccountId
                                       ,queue_id=QueueId
                                       ,supervisor=QueueSup
                                       }=State) ->
    WorkersSup = acdc_queue_sup:workers_sup(QueueSup),
    acdc_queue_workers_sup:new_workers(WorkersSup, AccountId, QueueId, N),
    {'noreply', State};

handle_cast({'agent_available', AgentId}, #state{supervisor=QueueSup}=State) when is_binary(AgentId) ->
    Data = #{},
    StrategyState1 = update_strategy_with_agent(State, AgentId, 'available', Data),
    State1 = State#state{strategy_state=StrategyState1},
    maybe_start_queue_workers(QueueSup, agent_count(State1)),
    {'noreply', State1, 'hibernate'};
handle_cast({'agent_available', JObj}, State) ->
    handle_cast({'agent_available', kz_json:get_ne_binary_value(<<"Agent-ID">>, JObj)}, State);

handle_cast({'agent_ringing', AgentId}, #state{strategy=Strategy}=State) when is_binary(AgentId) ->
    lager:info("agent ~s ringing, maybe updating strategy ~s", [AgentId, Strategy]),

    StrategyState1 = update_strategy_with_agent(State, AgentId, 'ringing'),
    State1 = State#state{strategy_state=StrategyState1},
    {'noreply', State1, 'hibernate'};
handle_cast({'agent_ringing', JObj}, State) ->
    handle_cast({'agent_ringing', kz_json:get_ne_binary_value(<<"Agent-ID">>, JObj)}, State);

handle_cast({'agent_busy', AgentId}, #state{strategy=Strategy}=State) when is_binary(AgentId) ->
    lager:info("agent ~s busy, maybe updating strategy ~s", [AgentId, Strategy]),

    StrategyState1 = update_strategy_with_agent(State, AgentId, 'busy'),
    State1 = State#state{strategy_state=StrategyState1},
    {'noreply', State1, 'hibernate'};
handle_cast({'agent_busy', JObj}, State) ->
    handle_cast({'agent_busy', kz_json:get_ne_binary_value(<<"Agent-ID">>, JObj)}, State);

handle_cast({'agent_unavailable', AgentId}, #state{strategy=Strategy}=State) when is_binary(AgentId) ->
    lager:info("agent ~s unavailable, maybe updating strategy ~s", [AgentId, Strategy]),

    StrategyState1 = update_strategy_with_agent(State, AgentId, 'unavailable'),
    State1 = State#state{strategy_state=StrategyState1},
    {'noreply', State1, 'hibernate'};
handle_cast({'agent_unavailable', JObj}, State) ->
    handle_cast({'agent_unavailable', kz_json:get_ne_binary_value(<<"Agent-ID">>, JObj)}, State);

handle_cast({'reject_member_call', Call, JObj}, #state{account_id=AccountId
                                                      ,queue_id=QueueId
                                                      }=State) ->
    Q = kz_json:get_value(<<"Server-ID">>, JObj),
    publish_member_call_failure(Q, AccountId, QueueId, kapps_call:call_id(Call), <<"no agents">>),
    {'noreply', State};

handle_cast({'gen_listener', {'created_queue', ?SECONDARY_QUEUE_NAME(QueueId)}}, #state{queue_id=QueueId}=State) ->
    {'noreply', State};

handle_cast({'gen_listener', {'created_queue', _}}, #state{account_id=AccountId
                                                          ,queue_id=QueueId
                                                          }=State) ->
    kapi_acdc_queue:publish_started_notif(
      kz_json:from_list([{<<"Account-ID">>, AccountId}
                        ,{<<"Queue-ID">>, QueueId}
                         | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
                        ])
     ),
    {'noreply', State};

handle_cast({'refresh', QueueJObj}, State) ->
    lager:debug("refreshing queue configs"),
    {'noreply', update_properties(QueueJObj, State), 'hibernate'};

handle_cast({'gen_listener',{'is_consuming',_IsConsuming}}, State) ->
    {'noreply', State};

handle_cast({'add_queue_member', JObj}, #state{current_member_calls=Calls
                                              }=State) ->
    Priority0 = kz_json:get_integer_value(<<"Member-Priority">>, JObj),
    Priority = callback_priority(Priority0),
    RawCall = kapps_call:from_json(kz_json:get_value(<<"Call">>, JObj)),
    case acdc_queue_member:physical_id(RawCall) of
        CallId when is_binary(CallId), byte_size(CallId) > 0 ->
            add_queue_member_once(JObj, Priority0, Priority, RawCall, CallId,
                                  Calls, State);
        _ ->
            lager:warning("refusing queue entry without a call id"),
            {'noreply', State}
    end;

handle_cast({'handle_queue_member_add', JObj}, #state{current_member_calls=CurrentCalls}=State) ->
    Call = kapps_call:from_json(kz_json:get_value(<<"Call">>, JObj)),
    CallId = acdc_queue_member:logical_member_id(Call),
    lager:debug("received notification of new queue member ~s", [CallId]),

    case acdc_queue_member:ensure(Call, CurrentCalls) of
        {'ok', Calls, _Position, _Status} ->
            {'noreply', State#state{current_member_calls=Calls}};
        {'error', Reason} ->
            lager:warning("refusing conflicting queue member ~s: ~p", [CallId, Reason]),
            {'noreply', State}
    end;

handle_cast({'handle_queue_member_replace', JObj}, #state{current_member_calls=Calls}=State) ->
    LogicalId = kz_json:get_ne_binary_value(<<"Logical-Call-ID">>, JObj),
    CallbackId = kz_json:get_ne_binary_value(<<"Callback-ID">>, JObj),
    Attempt = kz_json:get_integer_value(<<"Attempt">>, JObj),
    AttemptId = kz_json:get_ne_binary_value(<<"Attempt-ID">>, JObj),
    Call = kapps_call:from_json(kz_json:get_json_value(<<"Call">>, JObj)),
    case acdc_queue_member:replace(LogicalId, CallbackId, Attempt, AttemptId, Call, Calls) of
        {'ok', Calls1, _Position, _Status} ->
            {'noreply', State#state{current_member_calls=Calls1}};
        {'error', Reason} ->
            lager:warning("refusing queue member replacement ~s attempt ~p: ~p",
                          [LogicalId, Attempt, Reason]),
            {'noreply', State}
    end;

handle_cast({'handle_queue_member_remove', CallId}, State) ->
    State1 = remove_queue_member(CallId, State),
    {'noreply', State1};

handle_cast(_Msg, State) ->
    lager:debug("unhandled cast: ~p", [_Msg]),
    {'noreply', State}.

-spec add_queue_member_once(kz_json:object(), kz_term:api_integer(), 0..255,
                            kapps_call:call(), kz_term:ne_binary(),
                            [kapps_call:call()], mgr_state()) ->
          kz_types:handle_cast_ret_state(mgr_state()).
add_queue_member_once(JObj, Priority0, Priority, RawCall, CallId, Calls, State) ->
    %% A direct member-call delivery can be retried after the trusted manager
    %% has stamped it, or even after the logical member has moved to a callback
    %% channel. Never overwrite the immutable ordering metadata in either case.
    case acdc_queue_member:lookup(CallId, Calls) of
        {_Existing, _Position} ->
            lager:warning("ignoring duplicate queue entry for ~s", [CallId]),
            {'noreply', State};
        'undefined' ->
            add_trusted_queue_member(JObj, Priority0, Priority, RawCall, Calls, State)
    end.

-spec add_trusted_queue_member(kz_json:object(), kz_term:api_integer(), 0..255,
                               kapps_call:call(), [kapps_call:call()], mgr_state()) ->
          kz_types:handle_cast_ret_state(mgr_state()).
add_trusted_queue_member(JObj, Priority0, Priority, RawCall, Calls, State) ->
    StampedCall = acdc_queue_member:stamp(RawCall, kz_time:now_s(),
                                          next_enqueue_sequence(), Priority),
    case acdc_queue_member:ensure(StampedCall, Calls) of
        {'ok', StampedCalls, Position, 'inserted'} ->
            add_new_queue_member(JObj, Priority0, StampedCall,
                                 StampedCalls, Position, State);
        {'ok', _Calls1, _Position, 'existing'} ->
            lager:warning("ignoring duplicate queue entry for ~s",
                          [acdc_queue_member:logical_id(StampedCall)]),
            {'noreply', State};
        {'error', Reason} ->
            lager:warning("refusing queue entry for ~s: ~p",
                          [kapps_call:call_id(RawCall), Reason]),
            {'noreply', State}
    end.

-spec add_new_queue_member(kz_json:object(), kz_term:api_integer(), kapps_call:call(),
                           [kapps_call:call()], pos_integer(), mgr_state()) ->
          kz_types:handle_cast_ret_state(mgr_state()).
add_new_queue_member(JObj, Priority, StampedCall, StampedCalls, Position,
                     #state{account_id=AccountId
                           ,queue_id=QueueId
                           ,announcements_config=AnnouncementsConfig
                           ,announcements_pids=AnnouncementsPids
                           }=State) ->
    Call = kapps_call:set_custom_channel_var(<<"Queue-Position">>, Position, StampedCall),
    Calls = replace_logical_call(Call, StampedCalls),
    JObj1 = kz_json:set_value(<<"Call">>, kapps_call:to_json(Call), JObj),

    {CIDNumber, CIDName} = acdc_util:caller_id(Call),
    'ok' = acdc_stats:call_waiting(AccountId, QueueId
                                  ,acdc_queue_member:logical_id(Call)
                                  ,CIDName
                                  ,CIDNumber
                                  ,Priority
                                  ,acdc_dashboard_caller:from_call(Call, kz_json:get_value(<<"Call">>,JObj), CIDName, CIDNumber)
                                  ),

    publish_queue_member_add(AccountId, QueueId, Call),

    %% The stamped Call must be in the durable shared payload. A recovering
    %% worker can then reconstruct identity and order without trusting caller
    %% supplied KVS data or RabbitMQ redelivery order.
    kapi_acdc_queue:publish_shared_member_call(AccountId, QueueId, JObj1),
    lager:debug("put call into shared messaging queue"),

    acdc_util:presence_update(AccountId, QueueId, ?PRESENCE_RED_FLASH),

    AnnouncementsPids1 =
        case acdc_announcements_sup:maybe_start_announcements(self(), Call,
                                                              AnnouncementsConfig) of
            'false' -> AnnouncementsPids;
            {'ok', Pid} ->
                AnnouncementsPids#{acdc_queue_member:logical_id(Call) => Pid}
        end,

    {'noreply', State#state{current_member_calls=Calls
                           ,announcements_pids=AnnouncementsPids1
                           }}.

%%------------------------------------------------------------------------------
%% @doc Handling all non call/cast messages.
%% @end
%%------------------------------------------------------------------------------
-spec handle_info(any(), mgr_state()) -> kz_types:handle_info_ret_state(mgr_state()).
handle_info(_Info, State) ->
    lager:debug("unhandled message: ~p", [_Info]),
    {'noreply', State}.

-spec handle_event(kz_json:object(), mgr_state()) -> gen_listener:handle_event_return().
handle_event(_JObj, #state{enter_when_empty=EnterWhenEmpty
                          ,moh=MOH
                          }) ->
    {'reply', [{'enter_when_empty', EnterWhenEmpty}
              ,{'moh', MOH}
              ]}.

%%------------------------------------------------------------------------------
%% @doc This function is called by a `gen_server' when it is about to
%% terminate. It should be the opposite of `Module:init/1' and do any
%% necessary cleaning up. When it returns, the `gen_server' terminates
%% with Reason. The return value is ignored.
%%
%% @end
%%------------------------------------------------------------------------------
-spec terminate(any(), mgr_state()) -> 'ok'.
terminate(_Reason, _State) ->
    lager:debug("queue manager terminating: ~p", [_Reason]).

%%------------------------------------------------------------------------------
%% @doc Convert process state when code is changed.
%% @end
%%------------------------------------------------------------------------------
-spec code_change(any(), mgr_state(), any()) -> {'ok', mgr_state()}.
code_change(_OldVsn, State, _Extra) ->
    {'ok', State}.

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
start_secondary_queue(AccountId, QueueId) ->
    AccountDb = kzs_util:format_account_db(AccountId),
    Priority = acdc_util:max_priority(AccountDb, QueueId),
    kz_process:spawn(fun gen_listener:add_queue/4
                    ,[self()
                     ,?SECONDARY_QUEUE_NAME(QueueId)
                     ,[{'queue_options', ?SECONDARY_QUEUE_OPTIONS(Priority)}
                      ,{'consume_options', ?SECONDARY_CONSUME_OPTIONS}
                      ]
                     ,?SECONDARY_BINDINGS(AccountId, QueueId)
                     ]).

make_ignore_key(AccountId, QueueId, CallId) ->
    {AccountId, QueueId, CallId}.

-spec queue_member(kz_term:ne_binary(), [kapps_call:call()]) -> kapps_call:call() | 'undefined'.
queue_member(LogicalId, Calls) ->
    case queue_member_lookup(LogicalId, Calls) of
        'undefined' -> 'undefined';
        {Call, _} -> Call
    end.

-spec queue_member_position(kz_term:ne_binary(), [kapps_call:call()]) -> kz_term:api_pos_integer().
queue_member_position(LogicalId, Calls) ->
    case queue_member_lookup(LogicalId, Calls) of
        'undefined' -> 'undefined';
        {_, Position} -> Position
    end.

-spec queue_member_lookup(kz_term:ne_binary(), [kapps_call:call()]) ->
          {kapps_call:call(), pos_integer()} | 'undefined'.
queue_member_lookup(LogicalId, Calls) ->
    acdc_queue_member:lookup(LogicalId, Calls).

-spec publish_queue_member_add(kz_term:ne_binary(), kz_term:ne_binary(), kapps_call:call()) -> 'ok'.
publish_queue_member_add(AccountId, QueueId, Call) ->
    Prop = [{<<"Account-ID">>, AccountId}
           ,{<<"Queue-ID">>, QueueId}
           ,{<<"Call">>, kapps_call:to_json(Call)}
            | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
           ],
    kapi_acdc_queue:publish_queue_member_add(Prop).

-spec publish_queue_member_replace(kz_term:ne_binary(), kz_term:ne_binary(),
                                   kz_term:ne_binary(), kz_term:ne_binary(),
                                   pos_integer(), kz_term:ne_binary(),
                                   kapps_call:call()) -> 'ok'.
publish_queue_member_replace(AccountId, QueueId, LogicalId, CallbackId,
                             Attempt, AttemptId, Call) ->
    Prop = [{<<"Account-ID">>, AccountId}
           ,{<<"Queue-ID">>, QueueId}
           ,{<<"Logical-Call-ID">>, LogicalId}
           ,{<<"Callback-ID">>, CallbackId}
           ,{<<"Attempt">>, Attempt}
           ,{<<"Attempt-ID">>, AttemptId}
           ,{<<"Call">>, kapps_call:to_json(Call)}
            | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
           ],
    kapi_acdc_queue:publish_queue_member_replace(Prop).

-spec publish_queue_member_remove(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> 'ok'.
publish_queue_member_remove(AccountId, QueueId, CallId) ->
    Prop = [{<<"Account-ID">>, AccountId}
           ,{<<"Queue-ID">>, QueueId}
           ,{<<"Call-ID">>, CallId}
            | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
           ],
    kapi_acdc_queue:publish_queue_member_remove(Prop).

-spec publish_member_call_failure(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> 'ok'.
publish_member_call_failure(Q, AccountId, QueueId, CallId, Reason) ->
    Prop = [{<<"Account-ID">>, AccountId}
           ,{<<"Call-ID">>, CallId}
           ,{<<"Failure-Reason">>, Reason}
           ,{<<"Queue-ID">>, QueueId}
            | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
           ],
    catch kapi_acdc_queue:publish_member_call_failure(Q, Prop).

%%------------------------------------------------------------------------------
%% @doc Return the IDs of the agents that are ready to take calls.
%% @end
%%------------------------------------------------------------------------------
-spec ready_agents(mgr_state()) -> kz_term:ne_binaries().
ready_agents(#state{strategy=Strategy
                   ,strategy_state=#strategy_state{agents=Agents}
                   }) ->
    ready_agents(Strategy, Agents).

%%------------------------------------------------------------------------------
%% @doc Return the IDs of the agents that are ready to take calls, based on the
%% queue strategy.
%% @end
%%------------------------------------------------------------------------------
-spec ready_agents(queue_strategy(), queue_strategy_state()) -> kz_term:ne_binaries().
ready_agents('rr', AgentQueue) -> queue:to_list(AgentQueue);
ready_agents('mi', AgentL) -> AgentL;
ready_agents('ord', AgentQueue) -> queue:to_list(AgentQueue);
ready_agents('all', AgentQueue) -> queue:to_list(AgentQueue).

%%------------------------------------------------------------------------------
%% @doc Return the count of agents that are ready to take calls.
%% @end
%%------------------------------------------------------------------------------
-spec ready_agent_count_state(mgr_state()) -> non_neg_integer().
ready_agent_count_state(#state{strategy=Strategy
                              ,strategy_state=#strategy_state{agents=Agents}
                              }) ->
    ready_agent_count_strategy(Strategy, Agents).

%%------------------------------------------------------------------------------
%% @doc Return the count of agents that are ready to take calls, based on the
%% queue strategy.
%% @end
%%------------------------------------------------------------------------------
-spec ready_agent_count_strategy(queue_strategy(), queue_strategy_state()) -> non_neg_integer().
ready_agent_count_strategy('rr', AgentQueue) -> queue:len(AgentQueue);
ready_agent_count_strategy('mi', AgentL) -> length(AgentL);
ready_agent_count_strategy('ord', AgentQueue) -> queue:len(AgentQueue);
ready_agent_count_strategy('all', AgentQueue) -> queue:len(AgentQueue).

%%------------------------------------------------------------------------------
%% @doc Return the count of agents that are eligible to be assigned to a waiting
%% call.
%% @end
%%------------------------------------------------------------------------------
-spec assignable_agent_count(mgr_state()) -> non_neg_integer().
assignable_agent_count(#state{strategy=Strategy
                             ,strategy_state=#strategy_state{agents=Agents
                                                            ,ringing_agents=RingingAgents
                                                            }
                             }) ->
    assignable_agent_count(Strategy, Agents, RingingAgents).

%%------------------------------------------------------------------------------
%% @doc Return the count of agents that are eligible to be assigned to a waiting
%% call, based on the queue strategy. Round Robin, Most Idle, and Ring All
%% strategies must include ringing agents in the count to ensure maximal
%% simultaneous ringing.
%% @end
%%------------------------------------------------------------------------------
-spec assignable_agent_count(queue_strategy(), queue_strategy_state(), kz_term:ne_binaries()) ->
          non_neg_integer().
assignable_agent_count('rr', AgentQueue, RingingAgents) ->
    ready_agent_count_strategy('rr', AgentQueue) + length(RingingAgents);
assignable_agent_count('mi', AgentL, RingingAgents) ->
    ready_agent_count_strategy('mi', AgentL) + length(RingingAgents);
assignable_agent_count('ord', AgentQueue, RingingAgents) ->
    ready_agent_count_strategy('ord', AgentQueue) + length(RingingAgents);
assignable_agent_count('all', AgentQueue, RingingAgents) ->
    ready_agent_count_strategy('all', AgentQueue) + length(RingingAgents).

%%------------------------------------------------------------------------------
%% @doc Return the IDs of all agents.
%% @end
%%------------------------------------------------------------------------------
-spec agents_(mgr_state()) -> kz_term:ne_binaries().
agents_(#state{strategy_state=#strategy_state{ringing_agents=RingingAgents
                                             ,busy_agents=BusyAgents
                                             }
              }=State) ->
    ready_agents(State) ++ RingingAgents ++ BusyAgents.

%%------------------------------------------------------------------------------
%% @doc Return the count of all agents.
%% @end
%%------------------------------------------------------------------------------
-spec agent_count(mgr_state()) -> non_neg_integer().
agent_count(#state{strategy_state=#strategy_state{ringing_agents=RingingAgents
                                                 ,busy_agents=BusyAgents
                                                 }
                  }=State) ->
    ready_agent_count_state(State) + length(RingingAgents) + length(BusyAgents).

%%------------------------------------------------------------------------------
%% @doc Update the strategy state with the change of availability for `AgentId'.
%% @end
%%------------------------------------------------------------------------------
-spec update_strategy_with_agent(mgr_state(), kz_term:ne_binary(), agent_change()) -> strategy_state().
update_strategy_with_agent(State, AgentId, Change) ->
    update_strategy_with_agent(State, AgentId, Change, #{}).

%%------------------------------------------------------------------------------
%% @doc Update the strategy state with the change of availability for `AgentId'.
%% If diagnostics are enabled, the strategy state changes will be forwarded to
%% the diagnostics receivers.
%% @end
%%------------------------------------------------------------------------------
-spec update_strategy_with_agent(mgr_state(), kz_term:ne_binary(), agent_change(), agent_change_data()) ->
          strategy_state().
update_strategy_with_agent(#state{strategy=Strategy
                                 ,strategy_state=SS
                                 }=State, AgentId, Change, Data) ->
    SS1 = set_flag(AgentId, Change, SS),
    State1 = State#state{strategy_state=SS1},
    SS2 = do_update_strategy_with_agent(State1, AgentId, Change, Data),
    #strategy_state{agents=Agents
                   ,ringing_agents=RingingAgents
                   ,busy_agents=BusyAgents
                   } = SS2,
    maybe_send_diagnostics_for_strategy_update(Strategy, Agents, AgentId, RingingAgents, BusyAgents),
    SS2.

%%------------------------------------------------------------------------------
%% @doc Update the strategy state with the change of availability for `AgentId',
%% based on the queue strategy.
%% @end
%%------------------------------------------------------------------------------
-spec do_update_strategy_with_agent(mgr_state(), kz_term:ne_binary(), agent_change(), agent_change_data()) ->
          strategy_state().
do_update_strategy_with_agent(#state{strategy='rr'
                                    ,strategy_state=SS
                                    }, AgentId, Change, Data) ->
    update_rr_strategy_with_agent(SS, AgentId, Change, Data);
do_update_strategy_with_agent(#state{strategy='mi'
                                    ,strategy_state=SS
                                    }, AgentId, Change, _) ->
    update_mi_strategy_with_agent(SS, AgentId, Change);
do_update_strategy_with_agent(#state{strategy='ord', strategy_state=SS}, AgentId, Change, Data) ->
    update_rr_strategy_with_agent(SS, AgentId, Change, Data);
do_update_strategy_with_agent(#state{strategy='all'
                                    ,strategy_state=SS
                                    }, AgentId, Change, _) ->
    update_all_strategy_with_agent(SS, AgentId, Change).

%%------------------------------------------------------------------------------
%% @doc Update the Round Robin strategy state with the change of availability
%% for `AgentId'.
%% @end
%%------------------------------------------------------------------------------
-spec update_rr_strategy_with_agent(strategy_state(), kz_term:ne_binary(), agent_change(), agent_change_data()) ->
          strategy_state().
update_rr_strategy_with_agent(#strategy_state{agents=AgentQueue}=SS
                             ,AgentId, 'available', _
                             ) ->
    Msg = io_lib:format("adding agent ~s to strategy rr", [AgentId]),
    {IsReAdd, AgentQueue1} = acdc_util:queue_remove(AgentId, AgentQueue),
    Msg1 = case IsReAdd of
               'true' -> ["re-", Msg];
               'false' -> Msg
           end,
    lager:info(Msg1),
    SS#strategy_state{agents=queue:in(AgentId, AgentQueue1)};
update_rr_strategy_with_agent(#strategy_state{agents=AgentQueue}=SS, AgentId, _, _) ->
    {Removed, AgentQueue1} = acdc_util:queue_remove(AgentId, AgentQueue),
    Removed
        andalso lager:info("removing agent ~s from strategy rr", [AgentId]),
    SS#strategy_state{agents=AgentQueue1}.

%%------------------------------------------------------------------------------
%% @doc Update the Most Idle strategy state with the change of availability for
%% `AgentId'.
%% @end
%%------------------------------------------------------------------------------
-spec update_mi_strategy_with_agent(strategy_state(), kz_term:ne_binary(), agent_change()) ->
          strategy_state().
update_mi_strategy_with_agent(#strategy_state{agents=AgentL}=SS, AgentId, 'available') ->
    lists:member(AgentId, AgentL)
        orelse lager:info("adding agent ~s to strategy mi", [AgentId]),
    AgentL1 = [AgentId | lists:delete(AgentId, AgentL)],
    SS#strategy_state{agents=AgentL1};
update_mi_strategy_with_agent(#strategy_state{agents=AgentL}=SS, AgentId, _) ->
    lists:member(AgentId, AgentL)
        andalso lager:info("removing agent ~s from strategy mi", [AgentId]),
    AgentL1 = lists:delete(AgentId, AgentL),
    SS#strategy_state{agents=AgentL1}.

%%------------------------------------------------------------------------------
%% @doc Update the Ring All strategy state with the change of availability for
%% `AgentId'.
%% @end
%%------------------------------------------------------------------------------
-spec update_all_strategy_with_agent(strategy_state(), kz_term:ne_binary(), agent_change()) ->
          strategy_state().
update_all_strategy_with_agent(#strategy_state{agents=AgentQueue}=SS, AgentId, 'available') ->
    Msg = io_lib:format("adding agent ~s to strategy all", [AgentId]),
    {IsReAdd, AgentQueue1} = acdc_util:queue_remove(AgentId, AgentQueue),
    Msg1 = case IsReAdd of
               'true' -> ["re-", Msg];
               'false' -> Msg
           end,
    lager:info(Msg1),
    SS#strategy_state{agents=queue:in(AgentId, AgentQueue1)};
update_all_strategy_with_agent(#strategy_state{agents=AgentQueue}=SS, AgentId, _) ->
    {Removed, AgentQueue1} = acdc_util:queue_remove(AgentId, AgentQueue),
    Removed
        andalso lager:info("removing agent ~s from strategy all", [AgentId]),
    SS#strategy_state{agents=AgentQueue1}.

%%------------------------------------------------------------------------------
%% @doc Apply strategy state changes based on the agent change flag (ringing/
%% busy).
%% @end
%%------------------------------------------------------------------------------
-spec set_flag(kz_term:ne_binary(), agent_change(), strategy_state()) -> strategy_state().
set_flag(AgentId, Flag, #strategy_state{ringing_agents=RingingAgents
                                       ,busy_agents=BusyAgents
                                       }=SS) ->
    RingingAgents1 = lists:delete(AgentId, RingingAgents),
    BusyAgents1 = lists:delete(AgentId, BusyAgents),
    SS1 = SS#strategy_state{ringing_agents=RingingAgents1
                           ,busy_agents=BusyAgents1
                           },

    case Flag of
        'ringing' -> SS1#strategy_state{ringing_agents=[AgentId | RingingAgents1]};
        'busy' -> SS1#strategy_state{busy_agents=[AgentId | BusyAgents1]};
        _ -> SS1
    end.

-spec get_strategy(kz_term:api_binary()) -> queue_strategy().
get_strategy(<<"round_robin">>) -> 'rr';
get_strategy(<<"most_idle">>) -> 'mi';
get_strategy(<<"ring_all">>) -> 'all';
get_strategy(<<"in_order">>) -> 'ord';
get_strategy(_) -> 'rr'.

-spec create_strategy_state(queue_strategy()) -> strategy_state().
create_strategy_state(Strategy) ->
    Agents = create_ss_agents(Strategy),
    #strategy_state{agents=Agents}.

-spec create_ss_agents(queue_strategy()) -> queue_strategy_state().
create_ss_agents('rr') -> queue:new();
create_ss_agents('mi') -> [];
create_ss_agents('ord') -> queue:new();
create_ss_agents('all') -> queue:new().

maybe_start_queue_workers(QueueSup, Count) ->
    WSup = acdc_queue_sup:workers_sup(QueueSup),
    case acdc_queue_workers_sup:worker_count(WSup) of
        N when N >= Count -> 'ok';
        N when N < Count -> gen_listener:cast(self(), {'start_worker', Count - N})
    end.

-spec update_properties(kz_json:object(), mgr_state()) -> mgr_state().
update_properties(QueueJObj, #state{strategy_state=SS}=State) ->
    Strategy = get_strategy(kz_json:get_value(<<"strategy">>, QueueJObj)),
    %% A configuration refresh changes only the ready representation. It must
    %% not discard membership, ringing/busy flags or any waiting callers.
    State#state{strategy=Strategy
               ,strategy_state=SS#strategy_state{agents=strategy_agents(Strategy, ready_agents(State))}
               ,agent_order=kz_json:get_list_value(<<"agent_order">>, QueueJObj, [])
               ,enter_when_empty=kz_json:is_true(<<"enter_when_empty">>, QueueJObj, 'true')
               ,moh=kz_json:get_ne_value(<<"moh">>, QueueJObj)
               ,announcements_config=announcements_config(QueueJObj)
               }.

-spec strategy_agents(queue_strategy(), kz_term:ne_binaries()) -> queue_strategy_state().
strategy_agents('mi', Ready) -> Ready;
strategy_agents(_, Ready) -> queue:from_list(Ready).

-spec announcements_config(kz_json:object()) -> kz_term:proplist().
announcements_config(Config) ->
    Announcements = kz_json:recursive_to_proplist(
                      kz_json:get_json_value(<<"announcements">>, Config, kz_json:new())),
    %% Keep the independent callback-offer clock in the same cancellable
    %% worker. Its enable switch affects spoken offers only, never menu DTMF.
    Callback = kz_json:recursive_to_proplist(
                 kz_json:get_json_value(<<"callback">>, Config, kz_json:new())),
    [{<<"callback">>, Callback} | proplists:delete(<<"callback">>, Announcements)].

-spec cancel_position_announcements(kapps_call:call() | 'false' | 'undefined', map()) ->
          map().
cancel_position_announcements('false', Pids) -> Pids;
cancel_position_announcements('undefined', Pids) -> Pids;
cancel_position_announcements(Call, Pids) ->
    CallId = acdc_queue_member:logical_id(Call),
    case take_position_announcement(CallId, Pids) of
        {'undefined', _} ->
            lager:debug("did not have the announcements for call ~s", [CallId]),
            Pids;
        {Pid, Pids1} ->
            lager:debug("cancelling announcements for ~s", [CallId]),
            _ = acdc_announcements_sup:stop_announcements(Pid),

            %% Attempt to skip remaining announcement media, but don't flush hangups
            NoopId = kz_datamgr:get_uuid(),
            Command = [{<<"Application-Name">>, <<"noop">>}
                      ,{<<"Msg-ID">>, NoopId}
                      ,{<<"Insert-At">>, <<"now">>}
                      ,{<<"Filter-Applications">>, [<<"play">>, <<"say">>, <<"play">>]}
                      ],
            kapps_call_command:send_command(Command, Call),
            Pids1
    end.

-spec stop_position_announcements(kz_term:ne_binary(), map()) -> map().
stop_position_announcements(CallId, Pids) ->
    case take_position_announcement(CallId, Pids) of
        {'undefined', Pids} -> Pids;
        {Pid, Pids1} ->
            lager:debug("stopping periodic announcements before connecting call ~s", [CallId]),
            _ = acdc_announcements_sup:stop_announcements(Pid),
            Pids1
    end.

-spec resume_position_announcements(kz_term:ne_binary(), kapps_call:call(),
                                    kz_term:proplist(), map(), mgr_state()) ->
          {'reply', 'ok', mgr_state()}.
resume_position_announcements(LogicalId, Call, Config, Pids, State) ->
    %% A replacement callback leg has a different physical ID. Never restart
    %% periodic queue audio on that channel; callback retry/recovery is owned by
    %% the callback coordinator.
    case acdc_queue_member:physical_id(Call) =:= LogicalId
        andalso is_call_alive(Call) of
        'false' -> {'reply', 'ok', State};
        'true' ->
            case acdc_announcements_sup:maybe_start_announcements(self(), Call, Config) of
                'false' -> {'reply', 'ok', State};
                {'ok', Pid} ->
                    {'reply', 'ok', State#state{announcements_pids=Pids#{LogicalId => Pid}}}
            end
    end.

-spec is_call_alive(kapps_call:call()) -> boolean().
is_call_alive(Call) ->
    case kapps_call_command:b_channel_status(Call) of
        {'ok', _} -> 'true';
        {'error', _} -> 'false'
    end.

-spec take_position_announcement(kz_term:ne_binary(), map()) ->
          {'undefined', map()} | {pid(), map()}.
take_position_announcement(CallId, Pids) ->
    case maps:take(CallId, Pids) of
        'error' -> {'undefined', Pids};
        {Pid, Pids1} -> {Pid, Pids1}
    end.

-spec remove_queue_member(kz_term:api_binary(), mgr_state()) -> mgr_state().
remove_queue_member(LogicalId, #state{current_member_calls=CurrentCalls
                                     ,announcements_pids=AnnouncementsPids
                                     }=State) ->
    lager:debug("removing logical call id ~s", [LogicalId]),

    Member = queue_member(LogicalId, CurrentCalls),
    AnnouncementsPids1 = cancel_position_announcements(Member, AnnouncementsPids),

    State#state{current_member_calls=acdc_queue_member:remove(LogicalId, CurrentCalls)
               ,announcements_pids=AnnouncementsPids1
               }.

%% A pre-upgrade shared delivery may have no logical/order KVS. Migrate a
%% wholly legacy in-memory list by assigning ranks in its existing service
%% order. Mixed metadata cannot be reconstructed without changing order and is
%% rejected. If every existing member is modern, append an otherwise-lost
%% legacy delivery behind it rather than assigning a misleading current time.
ensure_legacy_member(Call, Calls) ->
    case legacy_metadata_shape(Calls) of
        'mixed' -> {'error', 'legacy_mixed_metadata'};
        'legacy' -> ensure_in_migrated_legacy(Call, migrate_legacy_calls(Calls));
        'modern' -> ensure_after_modern_calls(Call, Calls)
    end.

legacy_metadata_shape(Calls) ->
    Shapes = lists:usort([case acdc_queue_member:registration_metadata(Call) of
                              {'ok', _} -> 'modern';
                              {'error', _} -> 'legacy'
                          end || Call <- Calls]),
    case Shapes of
        [] -> 'modern';
        ['legacy'] -> 'legacy';
        ['modern'] -> 'modern';
        _ -> 'mixed'
    end.

migrate_legacy_calls(Calls) ->
    Service = lists:reverse(Calls),
    Ranked = [begin
                  {'ok', Restored} = acdc_queue_member:restore(
                                       Call, acdc_queue_member:logical_id(Call), 1, Rank, 0),
                  Restored
              end || {Call, Rank} <- lists:zip(Service, lists:seq(0, length(Service) - 1))],
    lists:reverse(Ranked).

ensure_in_migrated_legacy(Call, Calls) ->
    LogicalId = acdc_queue_member:logical_id(Call),
    case acdc_queue_member:lookup(LogicalId, Calls) of
        {Existing, Position} ->
            case acdc_queue_member:physical_id(Existing) =:= acdc_queue_member:physical_id(Call) of
                'true' -> {'ok', Calls, Position, Existing};
                'false' -> {'error', 'identity_conflict'}
            end;
        'undefined' ->
            Sequence = length(Calls),
            {'ok', Restored} = acdc_queue_member:restore(Call, LogicalId, 1, Sequence, 0),
            %% current_member_calls is reverse service order, so a conservative
            %% tail-of-service insertion is the list head.
            Calls1 = [Restored | Calls],
            {'ok', Calls1, length(Calls1), Restored}
    end.

ensure_after_modern_calls(Call, Calls) ->
    LogicalId = acdc_queue_member:logical_id(Call),
    case acdc_queue_member:lookup(LogicalId, Calls) of
        {Existing, Position} ->
            case acdc_queue_member:physical_id(Existing) =:= acdc_queue_member:physical_id(Call) of
                'true' -> {'ok', Calls, Position, Existing};
                'false' -> {'error', 'identity_conflict'}
            end;
        'undefined' ->
            Latest = lists:max([metadata_enqueued_at(Existing) || Existing <- Calls] ++ [1]),
            {'ok', Restored} = acdc_queue_member:restore(Call, LogicalId, Latest + 1, 0, 0),
            {'ok', [Restored | Calls], length(Calls) + 1, Restored}
    end.

metadata_enqueued_at(Call) ->
    {'ok', Metadata} = acdc_queue_member:registration_metadata(Call),
    kz_json:get_integer_value(<<"enqueued_at">>, Metadata).

callback_recovery_call(AccountId, QueueId, Call, Doc) ->
    LogicalId = kz_json:get_ne_binary_value(<<"original_call_id">>, Doc),
    CallbackId = kz_doc:id(Doc),
    EnqueuedAt = kz_json:get_integer_value(<<"enqueued_at">>, Doc, 0),
    Sequence = kz_json:get_integer_value(<<"enqueue_sequence">>, Doc, -1),
    Priority = kz_json:get_integer_value(<<"priority">>, Doc, -1),
    Attempt = kz_json:get_integer_value(<<"attempts">>, Doc, 0),
    CallerId = kz_json:get_ne_binary_value(<<"pvt_caller_call_id">>, Doc),
    PhysicalId = acdc_queue_member:physical_id(Call),
    CallMatches = PhysicalId =:= LogicalId
        orelse (is_binary(CallerId) andalso byte_size(CallerId) > 0
                andalso Attempt > 0 andalso PhysicalId =:= CallerId),
    Valid = kz_doc:account_id(Doc) =:= AccountId
        andalso kz_json:get_value(<<"queue_id">>, Doc) =:= QueueId
        andalso kz_json:get_value(<<"pvt_type">>, Doc) =:= <<"acdc_callback">>
        andalso valid_callback_id(CallbackId)
        andalso CallMatches
        andalso kapps_call:account_id(Call) =:= AccountId,
    case Valid of
        'false' -> {'error', 'invalid_callback_proof'};
        'true' ->
            Restore = case PhysicalId of
                          LogicalId ->
                              acdc_queue_member:restore(
                                Call, LogicalId, EnqueuedAt, Sequence, Priority);
                          CallerId ->
                              acdc_queue_member:restore_callback(
                                Call, LogicalId, EnqueuedAt, Sequence, Priority,
                                CallbackId, Attempt, CallerId)
                      end,
            case Restore of
                {'ok', Restored} -> {'ok', LogicalId, CallbackId, Attempt, CallerId, Restored};
                {'error', _} -> {'error', 'invalid_callback_metadata'}
            end
    end.

valid_recovered_existing(Existing, Doc, CallbackId, Attempt, CallerId) ->
    MetadataMatches = case acdc_queue_member:registration_metadata(Existing) of
                          {'ok', Metadata} ->
                              kz_json:get_integer_value(<<"enqueued_at">>, Metadata) =:=
                                  kz_json:get_integer_value(<<"enqueued_at">>, Doc)
                                  andalso kz_json:get_integer_value(<<"enqueue_sequence">>, Metadata) =:=
                                      kz_json:get_integer_value(<<"enqueue_sequence">>, Doc)
                                  andalso kz_json:get_integer_value(<<"priority">>, Metadata) =:=
                                      kz_json:get_integer_value(<<"priority">>, Doc);
                          _ -> 'false'
                      end,
    LogicalId = kz_json:get_ne_binary_value(<<"original_call_id">>, Doc),
    ExistingCallback = kapps_call:kvs_fetch(<<"acdc_callback_id">>, Existing),
    ExistingAttempt = kapps_call:kvs_fetch(<<"acdc_callback_attempt">>, 0, Existing),
    ExistingAttemptId = kapps_call:kvs_fetch(<<"acdc_callback_attempt_id">>, Existing),
    IdentityMatches = case acdc_queue_member:physical_id(Existing) of
                          LogicalId -> ExistingCallback =:= 'undefined';
                          CallerId when is_binary(CallerId), byte_size(CallerId) > 0 ->
                              ExistingCallback =:= CallbackId
                                  andalso ExistingAttempt =:= Attempt
                                  andalso ExistingAttemptId =:= CallerId;
                          _ -> 'false'
                      end,
    MetadataMatches andalso IdentityMatches.

terminal_callback_proof(AccountId, QueueId, LogicalId, CallbackId) ->
    case acdc_callback_store:get(AccountId, QueueId, CallbackId) of
        {'ok', Doc} ->
            Status = kz_json:get_value(<<"status">>, Doc),
            case kz_doc:account_id(Doc) =:= AccountId
                andalso kz_json:get_value(<<"queue_id">>, Doc) =:= QueueId
                andalso kz_doc:id(Doc) =:= CallbackId
                andalso kz_json:get_value(<<"original_call_id">>, Doc) =:= LogicalId
                andalso lists:member(Status, [<<"completed">>, <<"cancelled">>,
                                                 <<"failed">>, <<"expired">>]) of
                'true' -> 'ok';
                'false' -> {'error', 'not_terminal'}
            end;
        _ -> {'error', 'callback_proof_unavailable'}
    end.

retire_member_matches(LogicalId, CallbackId, Calls) ->
    case acdc_queue_member:lookup(LogicalId, Calls) of
        'undefined' -> 'true';
        {Call, _} ->
            case kapps_call:kvs_fetch(<<"acdc_callback_id">>, Call) of
                CallbackId -> 'true';
                'undefined' -> acdc_queue_member:physical_id(Call) =:= LogicalId;
                _ -> 'false'
            end
    end.

safe_publish_queue_member_remove(AccountId, QueueId, LogicalId) ->
    Prop = [{<<"Account-ID">>, AccountId}
           ,{<<"Queue-ID">>, QueueId}
           ,{<<"Call-ID">>, LogicalId}
            | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
           ],
    %% The shared AMQP worker call is synchronous. When the deployment enables
    %% pool_server_confirms it returns only after RabbitMQ confirms the publish;
    %% otherwise it still propagates immediate serialization/channel failures.
    try kz_amqp_worker:cast(Prop, fun kapi_acdc_queue:publish_queue_member_remove/1) of
        'ok' -> 'ok';
        _ -> {'error', 'publish_failed'}
    catch
        _:_ -> {'error', 'publish_failed'}
    end.

valid_callback_id(<<"acdc-callback-", Digest:64/binary>>) ->
    re:run(Digest, <<"^[0-9a-f]{64}$">>, [{'capture', 'none'}]) =:= 'match';
valid_callback_id(_) -> 'false'.

-spec replace_logical_call(kapps_call:call(), [kapps_call:call()]) -> [kapps_call:call()].
replace_logical_call(NewCall, Calls) ->
    LogicalId = acdc_queue_member:logical_id(NewCall),
    [case acdc_queue_member:logical_id(Call) of
         LogicalId -> NewCall;
         _ -> Call
     end || Call <- Calls].

-spec callback_priority(kz_term:api_integer()) -> 0..255.
callback_priority(Priority) when is_integer(Priority), Priority < 0 -> 0;
callback_priority(Priority) when is_integer(Priority), Priority > 255 -> 255;
callback_priority(Priority) when is_integer(Priority) -> Priority;
callback_priority(_) -> 0.

-spec next_enqueue_sequence() -> non_neg_integer().
next_enqueue_sequence() ->
    %% Unix microseconds fit in JSON's exact 53-bit integer range through the
    %% lifetime of this release and remain sortable across Erlang node restarts.
    erlang:system_time('microsecond').

%%------------------------------------------------------------------------------
%% @doc If there is at least one diagnostics receiver attached to the queue
%% manager, send the diagnostics message returned by `GetDiagnosticsMessage' to
%% all the diagnostics receivers. `GetDiagnosticsMessage' is a factory function
%% so that the diagnostics message generation is a noop when diagnostics are
%% disabled for the queue.
%% @end
%%------------------------------------------------------------------------------
-spec maybe_send_diagnostics(fun(() -> iolist())) -> 'ok'.
maybe_send_diagnostics(GetDiagnosticsMessage) ->
    case get(?KEY_DIAGNOSTICS_PIDS) of
        'undefined' -> 'ok';
        [] -> 'ok';
        Pids ->
            Message = GetDiagnosticsMessage(),
            acdc_queue_manager_diag_sup:send_diagnostics(Pids, Message)
    end.

%%------------------------------------------------------------------------------
%% @doc Prepare a diagnostics payload for an update of the strategy state due to
%% an agent state change (e.g. ringing/busy). The diagnostics will only be
%% prepared if there is at least one diagnostics receiver attached to the queue
%% manager.
%% @end
%%------------------------------------------------------------------------------
-spec maybe_send_diagnostics_for_strategy_update(queue_strategy()
                                                ,queue_strategy_state()
                                                ,kz_term:ne_binary()
                                                ,kz_term:ne_binaries()
                                                ,kz_term:ne_binaries()
                                                ) -> 'ok'.
maybe_send_diagnostics_for_strategy_update(Strategy
                                          ,AgentQueue
                                          ,AgentId
                                          ,RingingAgents
                                          ,BusyAgents
                                          ) when Strategy =:= 'rr'; Strategy =:= 'all'; Strategy =:= 'ord' ->
    Message = "agent ~s updated in SS~n~n"
        ++ "ringing agents: ~p~n~n"
        ++ "busy agents: ~p~n~n"
        ++ "agent queue: ~p",
    ?DIAG(Message
         ,[AgentId
          ,RingingAgents
          ,BusyAgents
          ,queue:to_list(AgentQueue)
          ]);
maybe_send_diagnostics_for_strategy_update('mi', AgentL, AgentId, RingingAgents, BusyAgents) ->
    Message = "agent ~s updated in SS~n~n"
        ++ "ringing agents: ~p~n~n"
        ++ "busy agents: ~p~n~n"
        ++ "agent list: ~p",
    ?DIAG(Message
         ,[AgentId, RingingAgents, BusyAgents, AgentL]
         ).
