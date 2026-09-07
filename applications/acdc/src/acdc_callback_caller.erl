%%% SPDX-License-Identifier: MPL-2.0
%%% Owns one returned-caller originate/confirmation attempt. This worker does
%%% not claim, retry, mutate the durable reservation, select an agent or bridge.
-module(acdc_callback_caller).
-behaviour(gen_listener).

-export([start_link/5, originate_ready_ack/2, cancel/2, handoff_complete/2]).
-export([handle_offnet_response/2, handle_resource_response/2, handle_call_event/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, handle_event/2
        ,terminate/2, code_change/3]).

-ifdef(TEST).
-export([confirmation_event/3, failure_message/4, owner_loss_action/1
        ,confirmation_prompt/2, ready_message/5, settlement/3, valid_start/5
        ,ready_correlation_probe/0, returned_call_probe/5]).
-endif.

-include("acdc.hrl").

-define(EVENTS, [<<"CHANNEL_ANSWER">>, <<"DTMF">>, <<"CHANNEL_DESTROY">>
                ,<<"CHANNEL_EXECUTE_COMPLETE">>, <<"CHANNEL_EXECUTE_ERROR">>
                ,<<"CHANNEL_BRIDGE">>]).
-define(RESPONDERS, [{{?MODULE, 'handle_offnet_response'}, [{<<"resource">>, <<"offnet_resp">>}]}
                    ,{{?MODULE, 'handle_resource_response'}, [{<<"resource">>, <<"originate_resp">>}
                                                             ,{<<"error">>, <<"originate_resp">>}
                                                             ,{<<"dialplan">>, <<"originate_ready">>}]}
                    ,{{?MODULE, 'handle_call_event'}, [{<<"call_event">>, <<"*">>}]}
                    ]).
-define(DEFAULT_CONFIRM_PROMPT, <<"acdc-callback-returned-confirmation">>).
-define(DEFAULT_CONFIRM_TIMEOUT, 10).
-define(DEFAULT_HANDOFF_TIMEOUT, 5).
-define(DEFAULT_READY_ACK_TIMEOUT, 5).
-define(CLEANUP_TIMEOUT, 5000).
-define(ORPHAN_READY_TIMEOUT, 30000).

-record(state, {owner :: pid()
               ,owner_ref :: kz_term:api_reference()
               ,owner_alive = 'true' :: boolean()
               ,queue_doc :: kz_json:object()
               ,reservation :: kz_json:object()
               ,lease_token :: kz_term:ne_binary()
               ,original_call :: kapps_call:call()
               ,account_id :: kz_term:ne_binary()
               ,queue_id :: kz_term:ne_binary()
               ,callback_id :: kz_term:ne_binary()
               ,caller_call_id :: kz_term:ne_binary()
               ,listener_queue = 'undefined' :: kz_term:api_binary()
               ,msg_id = 'undefined' :: kz_term:api_binary()
               ,originate_uuid = 'undefined' :: kz_term:api_binary()
               ,originate_queue = 'undefined' :: kz_term:api_binary()
               ,originate_msg_id = 'undefined' :: kz_term:api_binary()
               ,returned_call = 'undefined' :: kapps_call:call() | 'undefined'
               ,stage = 'starting' :: atom()
               ,timer = 'undefined' :: reference() | 'undefined'
               ,executed = 'false' :: boolean()
               ,offnet_settled = 'false' :: boolean()
               ,answered = 'false' :: boolean()
               ,destroyed = 'false' :: boolean()
               ,cancel_pending = 'false' :: boolean()
               ,pending_cause = 'undefined' :: atom()
               }).
-type state() :: #state{}.
-type disposition() :: 'settled' | 'reconciliation_required'.

%%%=============================================================================
%%% API
%%%=============================================================================

-spec start_link(pid(), kz_json:object(), kz_json:object(), kz_term:ne_binary(),
                 kapps_call:call()) -> kz_types:startlink_ret().
start_link(Owner, QueueDoc, Reservation, LeaseToken, OriginalCall) ->
    case valid_start(Owner, QueueDoc, Reservation, LeaseToken, OriginalCall) of
        'false' -> {'error', 'invalid_callback_attempt'};
        'true' ->
            CallerCallId = kz_json:get_ne_binary_value(<<"pvt_caller_call_id">>, Reservation),
            Bindings = [{'self', []}
                       ,{'call', [{'callid', CallerCallId}
                                 ,{'restrict_to', ?EVENTS}
                                 ]}
                       ],
            gen_listener:start_link(?MODULE
                                   ,[{'bindings', Bindings}
                                    ,{'responders', ?RESPONDERS}
                                    ,{'queue_name', <<>>}
                                    ,{'queue_options', []}
                                    ,{'consume_options', []}
                                    ]
                                   ,[Owner, QueueDoc, Reservation, LeaseToken, OriginalCall])
    end.

-spec cancel(pid(), kz_term:ne_binary()) -> 'ok'.
cancel(Pid, LeaseToken) ->
    gen_listener:cast(Pid, {'cancel', LeaseToken}).

-spec originate_ready_ack(pid(), kz_term:ne_binary()) -> 'ok'.
originate_ready_ack(Pid, LeaseToken) ->
    gen_listener:cast(Pid, {'originate_ready_ack', LeaseToken}).

-spec handoff_complete(pid(), kz_term:ne_binary()) -> 'ok'.
handoff_complete(Pid, LeaseToken) ->
    gen_listener:cast(Pid, {'handoff_complete', LeaseToken}).

-spec handle_offnet_response(kz_json:object(), kz_term:proplist()) -> 'ok'.
handle_offnet_response(JObj, Props) ->
    gen_listener:cast(props:get_value('server', Props), {'offnet_response', JObj}).

-spec handle_resource_response(kz_json:object(), kz_term:proplist()) -> 'ok'.
handle_resource_response(JObj, Props) ->
    gen_listener:cast(props:get_value('server', Props), {'resource_response', JObj}).

-spec handle_call_event(kz_json:object(), kz_term:proplist()) -> 'ok'.
handle_call_event(JObj, Props) ->
    gen_listener:cast(props:get_value('server', Props), {'call_event', JObj}).

%%%=============================================================================
%%% gen_listener callbacks
%%%=============================================================================

-spec init([term()]) -> {'ok', state()}.
init([Owner, QueueDoc, Reservation, LeaseToken, OriginalCall]) ->
    _ = erlang:process_flag('trap_exit', 'true'),
    CallbackId = kz_doc:id(Reservation),
    kz_log:put_callid(CallbackId),
    {'ok', #state{owner=Owner
                 ,owner_ref=erlang:monitor('process', Owner)
                 ,queue_doc=QueueDoc
                 ,reservation=Reservation
                 ,lease_token=LeaseToken
                 ,original_call=OriginalCall
                 ,account_id=kz_doc:account_id(Reservation)
                 ,queue_id=kz_json:get_ne_binary_value(<<"queue_id">>, Reservation)
                 ,callback_id=CallbackId
                 ,caller_call_id=kz_json:get_ne_binary_value(<<"pvt_caller_call_id">>, Reservation)
                 }}.

-spec handle_call(term(), kz_term:pid_ref(), state()) -> kz_types:handle_call_ret_state(state()).
handle_call(_Request, _From, State) ->
    {'reply', {'error', 'not_implemented'}, State}.

-spec handle_cast(term(), state()) -> kz_types:handle_cast_ret_state(state()).
handle_cast({'gen_listener', {'created_queue', Queue}}, State) ->
    {'noreply', State#state{listener_queue=Queue}};
handle_cast({'gen_listener', {'is_consuming', 'true'}}, #state{stage='starting'}=State) ->
    start_attempt(State);
handle_cast({'offnet_response', JObj}, State) ->
    handle_offnet(JObj, State);
handle_cast({'resource_response', JObj}, #state{reservation=Reservation, caller_call_id=CallId, msg_id=MsgId}=State) ->
    case kz_json:get_value(<<"pvt_internal_target">>, Reservation) of
        'undefined' -> {'noreply', State};
        _ ->
            case acdc_callback_internal:resource_response(CallId, MsgId, JObj) of
                {'ok', Response} -> handle_offnet(Response, State);
                {'error', _} -> {'noreply', State}
            end
    end;
handle_cast({'call_event', JObj}, State) ->
    handle_returned_event(JObj, State);
handle_cast({'cancel', Token}, #state{lease_token=Token}=State) ->
    request_cancel(State);
handle_cast({'cancel', _WrongToken}, State) ->
    {'noreply', State};
handle_cast({'originate_ready_ack', Token}
           ,#state{lease_token=Token, stage='awaiting_ready_ack', owner_alive='true'}=State) ->
    execute_after_ready_ack(State);
handle_cast({'originate_ready_ack', _Token}, State) ->
    {'noreply', State};
handle_cast({'handoff_complete', Token}, #state{lease_token=Token, stage='waiting_handoff'}=State) ->
    {'stop', 'normal', cancel_timer(State)};
handle_cast({'handoff_complete', _Token}, State) ->
    {'noreply', State};
handle_cast({'kz_amqp_channel', _}, State) ->
    {'noreply', State};
handle_cast(_Message, State) ->
    {'noreply', State}.

-spec handle_info(term(), state()) -> kz_types:handle_info_ret_state(state()).
handle_info({'timeout', Ref, Stage}, #state{timer=Ref, stage=Stage}=State) ->
    handle_stage_timeout(State#state{timer='undefined'});
handle_info({'timeout', _OldRef, _OldStage}, State) ->
    {'noreply', State};
handle_info({'DOWN', Ref, 'process', _Owner, _Reason}, #state{owner_ref=Ref}=State) ->
    owner_gone(State);
handle_info({'EXIT', Owner, _Reason}, #state{owner=Owner, owner_alive='true'}=State) ->
    owner_gone(State);
handle_info({'EXIT', Owner, _Reason}, #state{owner=Owner}=State) ->
    {'noreply', State};
handle_info(_Info, State) ->
    {'noreply', State}.

-spec handle_event(kz_json:object(), state()) -> gen_listener:handle_event_return().
handle_event(_JObj, _State) ->
    {'reply', [{'server', self()}]}.

-spec terminate(term(), state()) -> 'ok'.
terminate(_Reason, #state{owner_ref=OwnerRef, timer=Timer}) ->
    _ = maybe_demonitor(OwnerRef),
    _ = maybe_cancel_timer(Timer),
    'ok'.

-spec code_change(term(), state(), term()) -> {'ok', state()}.
code_change(_OldVersion, State, _Extra) -> {'ok', State}.

%%%=============================================================================
%%% Attempt lifecycle
%%%=============================================================================

start_attempt(#state{listener_queue='undefined'}=State) ->
    terminal('listener_unavailable', 'settled', State);
start_attempt(#state{account_id=AccountId, queue_doc=QueueDoc
                    ,reservation=Reservation, listener_queue=ReplyQueue}=State) ->
    case acdc_callback_policy:build_request(AccountId, QueueDoc, Reservation, ReplyQueue) of
        {'error', Reason} -> terminal(Reason, 'settled', State);
        {'ok', Request} ->
            MsgId = kz_api:msg_id(Request),
            try publish_request(Request) of
                'ok' ->
                    {'noreply', set_timer(attempt_timeout_ms(State), 'waiting_ready'
                                         ,State#state{stage='waiting_ready', msg_id=MsgId})}
            catch
                _:_ -> terminal('publish_uncertain', 'reconciliation_required', State)
            end
    end.

publish_request(Request) ->
    case kz_api:event_type(Request) of
        {<<"resource">>, <<"originate_req">>} -> kapi_resource:publish_originate_req(Request);
        {<<"resource">>, <<"offnet_req">>} -> kapi_offnet_resource:publish_req(Request)
    end.

handle_offnet(_JObj, #state{msg_id='undefined'}=State) ->
    {'noreply', State};
handle_offnet(JObj, #state{caller_call_id=CallId, msg_id=MsgId}=State) ->
    case acdc_callback_policy:parse_response(CallId, MsgId, JObj) of
        {'error', 'stale_response'} -> {'noreply', State};
        {'error', 'invalid_response'} -> {'noreply', State};
        {'error', Reason} -> handle_offnet_failure(Reason, State);
        {'ok', #{'response' := 'ready'}=Ready} -> handle_ready(Ready, State);
        {'ok', #{'response' := 'success'}=Success} -> handle_success(Success, JObj, State)
    end.

handle_ready(Ready, #state{originate_uuid='undefined', originate_queue='undefined'}=State) ->
    UUID = maps:get('originate_uuid', Ready),
    Queue = maps:get('originate_queue', Ready),
    ResourceMsgId = maps:get('originate_msg_id', Ready),
    State1 = State#state{originate_uuid=UUID, originate_queue=Queue, originate_msg_id=ResourceMsgId},
    case State#state.cancel_pending of
        'true' ->
            _ = publish_cancel(UUID, Queue),
            {'noreply', set_timer(?CLEANUP_TIMEOUT, 'cleaning'
                                 ,State1#state{stage='cleaning', pending_cause='cancelled'})};
        'false' ->
            notify_ready(State1)
    end;
handle_ready(Ready, #state{originate_uuid=UUID, originate_queue=Queue, originate_msg_id=MsgId}=State) ->
    case {maps:get('originate_uuid', Ready), maps:get('originate_queue', Ready)
          ,maps:get('originate_msg_id', Ready)} of
        {UUID, Queue, MsgId} -> {'noreply', State};
        {OtherUUID, OtherQueue, _OtherMsgId} ->
            _ = publish_cancel(OtherUUID, OtherQueue),
            begin_cleanup('conflicting_ready_response'
                         ,State#state{cancel_pending='true'
                                     ,pending_cause='conflicting_ready_response'})
    end.

notify_ready(#state{owner=Owner, callback_id=CallbackId, lease_token=Token
                   ,originate_uuid=UUID, originate_queue=Queue
                   ,originate_msg_id=OriginateMsgId
                   ,queue_doc=QueueDoc}=State) ->
    Owner ! ready_message(CallbackId, Token, UUID, Queue, OriginateMsgId),
    Timeout = kz_json:get_integer_value([<<"callback">>, <<"ready_ack_timeout">>]
                                      ,QueueDoc, ?DEFAULT_READY_ACK_TIMEOUT),
    SafeTimeout = case bounded(Timeout, 1, 10) of
                      'true' -> Timeout;
                      'false' -> ?DEFAULT_READY_ACK_TIMEOUT
                  end,
    {'noreply', set_timer(SafeTimeout * 1000, 'awaiting_ready_ack'
                         ,State#state{stage='awaiting_ready_ack'})}.

execute_after_ready_ack(#state{originate_uuid=UUID, originate_queue=Queue}=State) ->
    case publish_execute(UUID, Queue) of
        'ok' ->
            {'noreply', set_timer(attempt_timeout_ms(State), 'originating'
                                 ,State#state{stage='originating', executed='true'})};
        {'error', _} -> terminal('execute_uncertain', 'reconciliation_required', State)
    end.

handle_success(#{'control_queue' := ControlQueue}, JObj, State) ->
    ReturnedCall = returned_call(JObj, ControlQueue, State),
    State1 = State#state{returned_call=ReturnedCall, offnet_settled='true'},
    case State1#state.destroyed of
        'true' -> terminal(destroy_cause(State1)
                          ,settlement(State#state.executed, 'success', 'true'), State1);
        'false' when State#state.executed =:= 'false' ->
            begin_cleanup('success_before_execute', State1);
        'false' -> maybe_confirm_or_cleanup(State1)
    end.

maybe_confirm_or_cleanup(#state{cancel_pending='true'}=State) ->
    begin_cleanup('cancelled', State);
maybe_confirm_or_cleanup(#state{pending_cause=Cause}=State) when Cause =/= 'undefined' ->
    begin_cleanup(Cause, State);
maybe_confirm_or_cleanup(#state{answered='true'}=State) ->
    begin_confirmation(State);
maybe_confirm_or_cleanup(State) ->
    {'noreply', set_timer(5000, 'awaiting_answer', State#state{stage='awaiting_answer'})}.

handle_offnet_failure(Reason, #state{pending_cause='conflicting_ready_response'}=State) ->
    terminal(Reason, 'reconciliation_required', State);
handle_offnet_failure(Reason, #state{executed=Executed, destroyed=Destroyed}=State) ->
    terminal(Reason, settlement(Executed, 'failed', Destroyed), State).

handle_returned_event(JObj, #state{caller_call_id=CallId}=State) ->
    case kz_call_event:call_id(JObj) =:= CallId of
        'false' -> {'noreply', State};
        'true' -> handle_exact_event(kz_api:event_name(JObj), JObj, State)
    end.

handle_exact_event(<<"CHANNEL_ANSWER">>, _JObj, #state{returned_call='undefined'}=State) ->
    {'noreply', State#state{answered='true'}};
handle_exact_event(<<"CHANNEL_ANSWER">>, _JObj, State) ->
    begin_confirmation(State#state{answered='true'});
handle_exact_event(<<"DTMF">>, JObj, #state{stage='confirming'}=State) ->
    handle_confirmation_action(confirmation_event('confirming', <<"DTMF">>
                                                  ,kz_call_event:dtmf_digit(JObj)), State);
handle_exact_event(Event, _JObj, #state{stage=Stage}=State)
  when Event =:= <<"CHANNEL_EXECUTE_ERROR">>; Event =:= <<"CHANNEL_BRIDGE">> ->
    handle_confirmation_action(confirmation_event(Stage, Event, 'undefined'), State);
handle_exact_event(<<"CHANNEL_DESTROY">>, _JObj
                  ,#state{offnet_settled='true', executed=Executed}=State) ->
    terminal(destroy_cause(State), settlement(Executed, 'success', 'true')
            ,State#state{destroyed='true'});
handle_exact_event(<<"CHANNEL_DESTROY">>, _JObj, State) ->
    {'noreply', State#state{destroyed='true'}};
handle_exact_event(_Event, _JObj, State) ->
    {'noreply', State}.

handle_confirmation_action('confirmed', State) -> confirmed(State);
handle_confirmation_action({'cleanup', Cause}, State) -> begin_cleanup(Cause, State);
handle_confirmation_action('ignore', State) -> {'noreply', State}.

begin_confirmation(#state{stage='confirming'}=State) ->
    {'noreply', State};
begin_confirmation(#state{returned_call='undefined'}=State) ->
    {'noreply', State};
begin_confirmation(#state{returned_call=Call, queue_doc=QueueDoc}=State) ->
    Timeout = kz_json:get_integer_value([<<"callback">>, <<"confirmation_timeout">>]
                                      ,QueueDoc, ?DEFAULT_CONFIRM_TIMEOUT),
    case {confirmation_prompt(QueueDoc, Call), bounded(Timeout, 3, 30)} of
        {{'ok', Prompt}, 'true'} ->
            try kapps_call_command:play(Prompt, Call) of
                _NoopId -> {'noreply', set_timer(Timeout * 1000, 'confirming'
                                                ,State#state{stage='confirming'})}
            catch
                _:_ -> begin_cleanup('media_failed', State)
            end;
        _ -> begin_cleanup('invalid_confirmation_config', State)
    end.

-spec confirmation_prompt(kz_json:object(), kapps_call:call()) ->
          {'ok', kz_term:ne_binary()} | {'error', 'missing_localized_media'}.
confirmation_prompt(QueueDoc, Call) ->
    Media = kz_json:get_json_value([<<"callback">>,<<"media">>], QueueDoc, kz_json:new()),
    Configured = case acdc_gemini_prompts:selection(<<"returned_confirmation">>,Media) of
                     absent -> acdc_gemini_prompts:selection(<<"return_confirmation_prompt">>,
                                   kz_json:get_json_value(<<"callback">>,QueueDoc,kz_json:new()));
                     Selection -> Selection
                 end,
    Language = kz_json:get_ne_binary_value([<<"announcements">>,<<"language">>], QueueDoc,
                                           kapps_call:language(Call)),
    case Configured of
        {configured,Prompt} when is_binary(Prompt) ->
            %% Explicit legacy customer media is resolved separately. Built-in
            %% queue language adoption removes this override in the editor.
            case valid_text(Prompt, 256) of
                'true' -> {'ok', kapps_call:get_prompt(Call,Prompt,Language)};
                'false' -> {'error', 'missing_localized_media'}
            end;
        absent ->
            case acdc_gemini_prompts:builtin(?DEFAULT_CONFIRM_PROMPT,Language) of
                {ok,Path} -> {ok,Path};
                _ -> {'error','missing_localized_media'}
            end;
        _ -> {'error','missing_localized_media'}
    end.

confirmed(#state{owner=Owner, callback_id=CallbackId, lease_token=Token
                ,returned_call=ReturnedCall, queue_doc=QueueDoc}=State) ->
    Owner ! {'acdc_callback_caller_confirmed', CallbackId, Token, ReturnedCall},
    Timeout = kz_json:get_integer_value([<<"callback">>, <<"handoff_timeout">>]
                                      ,QueueDoc, ?DEFAULT_HANDOFF_TIMEOUT),
    SafeTimeout = case bounded(Timeout, 1, 10) of 'true' -> Timeout; 'false' -> ?DEFAULT_HANDOFF_TIMEOUT end,
    {'noreply', set_timer(SafeTimeout * 1000, 'waiting_handoff'
                         ,State#state{stage='waiting_handoff'})}.

request_cancel(#state{stage='starting'}=State) ->
    terminal('cancelled', 'settled', State);
request_cancel(#state{stage='waiting_ready'}=State) ->
    {'noreply', State#state{cancel_pending='true'}};
request_cancel(#state{stage='cleaning'}=State) ->
    {'noreply', State};
request_cancel(State) ->
    begin_cleanup('cancelled', State#state{cancel_pending='true'}).

%% Once the owner is gone this worker becomes the sole holder of the private
%% reply queue.  Keep it alive long enough to turn a late READY into cancel or
%% a late SUCCESS into an exact-leg hangup; abandoning the queue here would
%% make it impossible to prove whether the persisted attempt created a leg.
owner_gone(#state{stage=Stage}=State) ->
    case owner_loss_action(Stage) of
        'stop_settled' -> terminal('owner_down', 'settled', mark_owner_down(State));
        'wait_ready' ->
            State1 = mark_owner_down(State),
            {'noreply', set_timer(?ORPHAN_READY_TIMEOUT, 'waiting_ready'
                                 ,State1#state{cancel_pending='true', pending_cause='owner_down'})};
        'wait_cleanup' -> {'noreply', mark_owner_down(State)};
        'cleanup' ->
            begin_cleanup('owner_down', mark_owner_down(State#state{cancel_pending='true'}))
    end.

-spec owner_loss_action(atom()) -> 'stop_settled' | 'wait_ready' | 'wait_cleanup' | 'cleanup'.
owner_loss_action('starting') -> 'stop_settled';
owner_loss_action('waiting_ready') -> 'wait_ready';
owner_loss_action('cleaning') -> 'wait_cleanup';
owner_loss_action(_) -> 'cleanup'.

mark_owner_down(#state{owner_ref=OwnerRef}=State) ->
    _ = maybe_demonitor(OwnerRef),
    State#state{owner_ref='undefined', owner_alive='false'}.

begin_cleanup(Cause, #state{returned_call=Call}=State) when Call =/= 'undefined' ->
    _ = catch kapps_call_command:hangup(Call),
    {'noreply', set_timer(?CLEANUP_TIMEOUT, 'cleaning'
                         ,State#state{stage='cleaning', pending_cause=Cause})};
begin_cleanup(Cause, #state{originate_uuid=UUID, originate_queue=Queue}=State)
  when UUID =/= 'undefined', Queue =/= 'undefined' ->
    _ = publish_cancel(UUID, Queue),
    {'noreply', set_timer(?CLEANUP_TIMEOUT, 'cleaning'
                         ,State#state{stage='cleaning', pending_cause=Cause})};
begin_cleanup(Cause, State) ->
    terminal(Cause, 'reconciliation_required', State).

handle_stage_timeout(#state{stage='waiting_handoff'}=State) ->
    begin_cleanup('handoff_timeout', State);
handle_stage_timeout(#state{stage='awaiting_answer'}=State) ->
    begin_cleanup('no_answer', State);
handle_stage_timeout(#state{stage='confirming'}=State) ->
    begin_cleanup('confirmation_timeout', State);
handle_stage_timeout(#state{stage='awaiting_ready_ack'}=State) ->
    begin_cleanup('ready_ack_timeout', State);
handle_stage_timeout(#state{stage='cleaning'}=State) ->
    terminal(pending_cause(State), 'reconciliation_required', State);
handle_stage_timeout(State) ->
    _ = best_effort_cleanup(State),
    terminal('originate_timeout', 'reconciliation_required', State).

terminal(Cause, Disposition, #state{owner=Owner, callback_id=CallbackId
                                   ,lease_token=Token, owner_alive=OwnerAlive}=State) ->
    case OwnerAlive of
        'true' -> Owner ! failure_message(CallbackId, Token, Cause, Disposition);
        'false' -> 'ok'
    end,
    {'stop', 'normal', cancel_timer(State)}.

%%%=============================================================================
%%% Helpers
%%%=============================================================================

returned_call(JObj, ControlQueue, #state{account_id=AccountId
                                       ,caller_call_id=CallId
                                       ,original_call=OriginalCall}) ->
    CallJObj = kz_json:get_json_value(<<"Call">>, JObj, kz_json:new()),
    %% Offnet responses label the carrier route "offnet-termination". This
    %% worker returns an AUDIO member to ACDC, whose endpoint policy accepts
    %% media types, not route classifications. Normalize only the Call field;
    %% preserve transport CCVs, authorization and callback correlation intact.
    Call0 = case kz_json:is_json_object(CallJObj) of
                'true' -> kapps_call:from_json(kz_json:set_value(<<"Resource-Type">>, <<"audio">>, CallJObj));
                'false' -> kapps_call:from_json(kz_json:from_list([{<<"Resource-Type">>, <<"audio">>}]))
            end,
    Call1 = kapps_call:exec([{fun kapps_call:set_account_id/2, AccountId}
                            ,{fun kapps_call:set_account_db/2, kzs_util:format_account_db(AccountId)}
                            ,{fun kapps_call:set_call_id/2, CallId}
                            ,{fun kapps_call:set_control_queue/2, ControlQueue}
                            ], Call0),
    maybe_set_language(kapps_call:language(OriginalCall), Call1).

maybe_set_language(Language, Call) when is_binary(Language), byte_size(Language) > 0 ->
    kapps_call:set_language(Language, Call);
maybe_set_language(_, Call) -> Call.

publish_execute(UUID, Queue) ->
    publish_originate(fun kapi_dialplan:publish_originate_execute/2, UUID, Queue).

publish_cancel(UUID, Queue) ->
    publish_originate(fun kapi_dialplan:publish_originate_cancel/2, UUID, Queue).

publish_originate(Publisher, UUID, Queue) ->
    Request = [{<<"Originate-UUID">>, UUID}
              | kz_api:default_headers(Queue, ?APP_NAME, ?APP_VERSION)],
    try Publisher(Queue, Request) of
        'ok' -> 'ok'
    catch
        _:_ -> {'error', 'publish_failed'}
    end.

best_effort_cleanup(#state{returned_call=Call}) when Call =/= 'undefined' ->
    catch kapps_call_command:hangup(Call);
best_effort_cleanup(#state{originate_uuid=UUID, originate_queue=Queue})
  when UUID =/= 'undefined', Queue =/= 'undefined' ->
    publish_cancel(UUID, Queue);
best_effort_cleanup(_) -> 'ok'.

set_timer(Milliseconds, Stage, State) ->
    State1 = cancel_timer(State),
    Ref = erlang:start_timer(Milliseconds, self(), Stage),
    State1#state{timer=Ref}.

cancel_timer(#state{timer=Timer}=State) ->
    _ = maybe_cancel_timer(Timer),
    State#state{timer='undefined'}.

maybe_cancel_timer('undefined') -> 'ok';
maybe_cancel_timer(Timer) ->
    _ = erlang:cancel_timer(Timer),
    'ok'.

maybe_demonitor('undefined') -> 'ok';
maybe_demonitor(Ref) ->
    _ = erlang:demonitor(Ref, ['flush']),
    'ok'.

attempt_timeout_ms(#state{queue_doc=QueueDoc}) ->
    (kz_json:get_integer_value([<<"callback">>, <<"originate_timeout">>], QueueDoc, 60) + 10)
        * 1000.

pending_cause(#state{pending_cause='undefined'}) -> 'cleanup_timeout';
pending_cause(#state{pending_cause=Cause}) -> Cause.

destroy_cause(#state{pending_cause='undefined'}) -> 'caller_hangup';
destroy_cause(#state{pending_cause=Cause}) -> Cause.

-spec settlement(boolean(), 'failed' | 'success' | 'pending', boolean()) -> disposition().
settlement('false', 'failed', _Destroyed) -> 'settled';
settlement(_Executed, 'success', 'true') -> 'settled';
settlement(_, _, _) -> 'reconciliation_required'.

-spec ready_message(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(),
                    kz_term:ne_binary(), kz_term:ne_binary()) ->
          {'acdc_callback_caller_ready', kz_term:ne_binary(), kz_term:ne_binary(),
           kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()}.
ready_message(CallbackId, Token, UUID, Queue, OriginateMsgId) ->
    {'acdc_callback_caller_ready', CallbackId, Token, UUID, Queue, OriginateMsgId}.

-spec failure_message(kz_term:ne_binary(), kz_term:ne_binary(), atom(), disposition()) ->
          {'acdc_callback_caller_failed', kz_term:ne_binary(), kz_term:ne_binary(),
           atom(), disposition()}.
failure_message(CallbackId, Token, Cause, Disposition) ->
    {'acdc_callback_caller_failed', CallbackId, Token, Cause, Disposition}.

-spec confirmation_event(atom(), kz_term:ne_binary(), kz_term:api_binary()) ->
          'confirmed' | {'cleanup', atom()} | 'ignore'.
confirmation_event('confirming', <<"DTMF">>, <<"1">>) -> 'confirmed';
confirmation_event('confirming', <<"DTMF">>, _) -> {'cleanup', 'wrong_digit'};
confirmation_event('confirming', <<"CHANNEL_EXECUTE_ERROR">>, _) ->
    {'cleanup', 'media_failed'};
confirmation_event('cleaning', <<"CHANNEL_BRIDGE">>, _) -> 'ignore';
confirmation_event(_Stage, <<"CHANNEL_BRIDGE">>, _) ->
    {'cleanup', 'unexpected_bridge'};
confirmation_event(_, _, _) -> 'ignore'.

-spec valid_start(pid(), kz_json:object(), kz_json:object(), kz_term:ne_binary(),
                  kapps_call:call()) -> boolean().
valid_start(Owner, QueueDoc, Reservation, LeaseToken, OriginalCall) ->
    AccountId = kz_doc:account_id(Reservation),
    QueueId = kz_json:get_ne_binary_value(<<"queue_id">>, Reservation),
    CallerCallId = kz_json:get_ne_binary_value(<<"pvt_caller_call_id">>, Reservation),
    is_pid(Owner)
        andalso kz_json:is_json_object(QueueDoc)
        andalso kz_json:is_json_object(Reservation)
        andalso kapps_call:is_call(OriginalCall)
        andalso valid_text(LeaseToken, 128)
        andalso valid_text(AccountId, 64)
        andalso kz_doc:account_id(QueueDoc) =:= AccountId
        andalso kz_doc:id(QueueDoc) =:= QueueId
        andalso kz_doc:type(QueueDoc) =:= <<"queue">>
        andalso kz_doc:type(Reservation) =:= <<"acdc_callback">>
        andalso kz_json:get_ne_binary_value(<<"status">>, Reservation) =:= <<"dialing">>
        andalso matches(CallerCallId, <<"^[0-9a-f]{32}$">>)
        andalso kapps_call:account_id(OriginalCall) =:= AccountId
        andalso kapps_call:call_id(OriginalCall)
             =:= kz_json:get_ne_binary_value(<<"original_call_id">>, Reservation).

bounded(Value, Min, Max) -> is_integer(Value) andalso Value >= Min andalso Value =< Max.

valid_text(Value, Max) when is_binary(Value), byte_size(Value) > 0, byte_size(Value) =< Max ->
    re:run(Value, <<"[\\x00-\\x1f\\x7f]">>, [{'capture', 'none'}]) =:= 'nomatch';
valid_text(_, _) -> 'false'.

matches(Value, Regex) when is_binary(Value), byte_size(Value) =< 512 ->
    valid_text(Value, 512) andalso re:run(Value, Regex, [{'capture', 'none'}]) =:= 'match';
matches(_, _) -> 'false'.

-ifdef(TEST).
-spec returned_call_probe(kz_json:object(), kz_term:ne_binary(), kz_term:ne_binary(),
                          kz_term:ne_binary(), kapps_call:call()) -> kapps_call:call().
returned_call_probe(JObj, ControlQueue, AccountId, CallId, OriginalCall) ->
    returned_call(JObj, ControlQueue, #state{account_id=AccountId, caller_call_id=CallId
                                           ,original_call=OriginalCall}).

%% Exercise the actual worker transition, not only the message constructor.
-spec ready_correlation_probe() -> tuple().
ready_correlation_probe() ->
    Ready = #{'originate_uuid' => <<"uuid">>, 'originate_queue' => <<"resource-q">>
              ,'originate_msg_id' => <<"resource-message">>},
    State = #state{owner=self(), callback_id= <<"callback">>, lease_token= <<"token">>
                   ,msg_id= <<"offnet-message">>, queue_doc=kz_json:new()},
    {'noreply', State1} = handle_ready(Ready, State),
    _ = erlang:cancel_timer(State1#state.timer),
    {'noreply', State1} = handle_ready(Ready, State1),
    receive Message={acdc_callback_caller_ready, <<"callback">>, <<"token">>, _, _, _} -> Message
    after 0 -> 'missing_ready_message'
    end.
-endif.
