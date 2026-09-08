%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2012-2020, 2600Hz
%%% @doc Data: {
%%%   "id":"queue id"
%%% }
%%%
%%%
%%% @author James Aimonetti
%%% @author Sponsored by GTNetwork LLC, Implemented by SIPLABS LLC
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cf_acdc_member).

-export([handle/2]).

-ifdef(TEST).
-export([remaining_wait_ms/3
        ,callback_config/2
        ,callback_confirmation_prompts/3
        ,queue_announcement_call/2
        ,callback_test_media/2
        ,callback_test_request/3
        ,callback_test_response/2
        ,callback_test_collect_alternate/3
        ,callback_test_paused/3
        ,callback_test_unavailable/4
        ,callback_test_retry/4
        ,callback_test_control_ack/4
        ,callback_test_pause/3
        ,callback_test_registration/3
        ,callback_test_success/4
        ]).
-endif.

-include_lib("callflow/src/callflow.hrl").

-type max_wait() :: pos_integer() | 'infinity'.

-define(MEMBER_TIMEOUT, <<"member_timeout">>).
-define(MEMBER_HANGUP, <<"member_hangup">>).
-define(CALLBACK_PAUSE_ACK_TIMEOUT_MS, 5000).
-define(CALLBACK_RESUME_ACK_TIMEOUT_MS, 10000).
-define(CALLBACK_DEFAULT_NUMBER_READBACK, <<"acdc-callback-number-readback">>).
-define(CALLBACK_DEFAULT_CONFIRMATION, <<"acdc-callback-confirmation">>).
-define(CALLBACK_DEFAULT_SUCCESS, <<"acdc-callback-success">>).
-define(CALLBACK_UNAVAILABLE_TIMEOUT_MS, 21000).
-define(CALLBACK_AUXILIARY_PLAYBACK_TIMEOUT_MS, 20000).

-record(member_call, {call             :: kapps_call:call()
                     ,queue_id         :: kz_term:api_binary()
                     ,config_data = [] :: kz_term:proplist()
                     ,max_wait = 60 :: max_wait()
                     ,callback = 'undefined' :: 'undefined' | map()
                     ,callback_pending = 'undefined' :: 'undefined' | map()
                     }).
-type member_call() :: #member_call{}.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec handle(kz_json:object(), kapps_call:call()) -> 'ok'.
handle(Data, Call) ->
    QueueId = kz_json:get_ne_binary_value(<<"id">>, Data),
    lager:info("sending call to queue ~s", [QueueId]),

    Priority = lookup_priority(Data, Call),

    MemberCall = props:filter_undefined(
                   [{<<"Account-ID">>, kapps_call:account_id(Call)}
                   ,{<<"Queue-ID">>, QueueId}
                   ,{<<"Call">>, kapps_call:to_json(Call)}
                   ,{<<"Member-Priority">>, Priority}
                    | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
                   ]),

    lager:info("loading ACDc queue: ~s", [QueueId]),
    {'ok', QueueJObj} = kz_datamgr:open_cache_doc(kapps_call:account_db(Call), QueueId),

    MaxWait = max_wait(kz_json:get_integer_value(<<"connection_timeout">>, QueueJObj, 3600)),
    MaxQueueSize = max_queue_size(kz_json:get_integer_value(<<"max_queue_size">>, QueueJObj, 0)),

    QueueCall = queue_announcement_call(QueueJObj, Call),
    Call1 = kapps_call:kvs_store('caller_exit_key', kz_json:get_value(<<"caller_exit_key">>, QueueJObj, <<"#">>), QueueCall),
    LocalizedMemberCall = [{<<"Call">>, kapps_call:to_json(Call1)} | proplists:delete(<<"Call">>, MemberCall)],

    CurrQueueSize = kapi_acdc_queue:queue_size(kapps_call:account_id(Call1), QueueId),

    lager:info("max size: ~p curr size: ~p", [MaxQueueSize, CurrQueueSize]),

    maybe_enter_queue(#member_call{call=Call1
                                  ,config_data=LocalizedMemberCall
                                  ,queue_id=QueueId
                                  ,max_wait=MaxWait
                                  ,callback=callback_config(QueueJObj, Call1)
                                  }
                     ,is_queue_full(MaxQueueSize, CurrQueueSize)
                     ).

%% The queue's selected language applies to its callback offer/menu and the
%% saved original call used by the returned caller, not only position prompts.
-spec queue_announcement_call(kz_json:object(), kapps_call:call()) -> kapps_call:call().
queue_announcement_call(QueueJObj, Call) ->
    Selected = case kz_json:get_ne_binary_value([<<"announcements">>, <<"language">>], QueueJObj) of
                   'undefined' -> kapps_call:language(Call);
                   Override -> Override
               end,
    Language = acdc_language:canonical(Selected),
    %% A resumed announcement worker receives the manager's latest settings.
    %% Pin admission language in serialized call state so periodic prompts and
    %% callback responses cannot diverge after an intervening queue edit.
    %% Admission to a subsequent queue deliberately replaces this snapshot.
    kapps_call:kvs_store(<<"acdc_admitted_queue_language">>, Language,
                        kapps_call:set_language(Language, Call)).

-spec lookup_priority(kz_json:object(), kapps_call:call()) -> kz_term:api_binary().
lookup_priority(Data, Call) ->
    FromData = kz_json:get_integer_value(<<"priority">>, Data),
    FromCall = kapps_call:custom_channel_var(<<"Call-Priority">>, Call),
    case {FromData, FromCall} of
        {FromData, _} when is_integer(FromData) -> FromData;
        {_, FromCall} when is_binary(FromCall) -> kz_term:to_integer(FromCall);
        _ -> 'undefined'
    end.

-spec maybe_enter_queue(member_call(), boolean()) -> any().
maybe_enter_queue(#member_call{call=Call}, 'true') ->
    lager:info("queue has reached max size"),
    cf_exe:continue(Call);
maybe_enter_queue(#member_call{call=Call
                              ,config_data=MemberCall
                              ,queue_id=QueueId
                              ,max_wait=MaxWait
                              }=MC
                 ,'false') ->
    lager:info("asking for an agent, waiting up to ~p seconds", [MaxWait]),

    cf_exe:amqp_send(Call, MemberCall, fun kapi_acdc_queue:publish_member_call/1),
    _ = kapps_call_command:flush_dtmf(Call),
    Ready = MC#member_call{call=kapps_call:kvs_store('queue_id', QueueId, Call)},
    wait_for_bridge(Ready
                   ,MaxWait
                   ).

-spec wait_for_bridge(member_call(), max_wait()) -> 'ok'.
wait_for_bridge(MC, Timeout) ->
    wait_for_bridge(MC, Timeout, kz_time:start_time()).

-spec wait_for_bridge(member_call(), max_wait(), kz_time:start_time()) -> 'ok'.
wait_for_bridge(#member_call{call=Call}, Timeout, _Start) when Timeout < 0 ->
    lager:debug("timeout is less than 0: ~p", [Timeout]),
    end_member_call(Call);
wait_for_bridge(#member_call{call=Call, max_wait=MaxWait}=MC, Timeout, Start) ->
    Wait = kz_time:start_time(),
    %% A per-message decrement rounds each elapsed interval down to seconds.
    %% Frequent events can then extend a caller's wait indefinitely. Derive
    %% every receive timeout from the original monotonic entry time instead.
    case remaining_wait_ms(MaxWait, Start, Wait) of
        0 ->
            lager:info("failed to handle the call in time, proceeding"),
            end_member_call(Call);
        TimeoutMs ->
            receive
                {'amqp_msg', JObj} ->
                    process_message(MC, Timeout, Start, Wait, JObj, kz_api:event_type(JObj))
            after TimeoutMs ->
                    wait_for_bridge(MC, Timeout, Start)
            end
    end.

-spec remaining_wait_ms(max_wait(), kz_time:start_time(), kz_time:start_time()) -> timeout().
remaining_wait_ms('infinity', _Start, _Now) -> 'infinity';
remaining_wait_ms(MaxWait, Start, Now) ->
    Remaining = max(0, MaxWait * ?MILLISECONDS_IN_SECOND - kz_time:elapsed_ms(Start, Now)),
    %% Bound each receive to OTP's timer range; longer configured waits are
    %% rechecked against the same deadline when this bounded chunk expires.
    min(Remaining, 16#ffffffff).

end_member_call(Call) ->
    cancel_member_call(Call, ?MEMBER_TIMEOUT),
    stop_hold_music(Call),
    cf_exe:continue(Call).

-spec process_message(member_call(), max_wait(), kz_time:start_time()
                     ,kz_time:start_time(), kz_json:object()
                     ,{kz_term:ne_binary(), kz_term:ne_binary()}
                     ) -> 'ok'.
process_message(#member_call{call=Call}, _, Start, _Wait, _JObj, {<<"call_event">>,<<"CHANNEL_BRIDGE">>}) ->
    lager:info("member was bridged to agent, yay! took ~b s", [kz_time:elapsed_s(Start)]),
    cf_exe:control_usurped(Call);
process_message(#member_call{call=Call}, _, Start, _Wait, _JObj, {<<"call_event">>,<<"CHANNEL_DESTROY">>}) ->
    lager:info("member hungup while waiting in the queue (was there ~b s)", [kz_time:elapsed_s(Start)]),
    cancel_member_call(Call, ?MEMBER_HANGUP),
    cf_exe:stop(Call);
process_message(#member_call{call=Call
                            ,queue_id=QueueId
                            }=MC, Timeout, Start, Wait, JObj, {<<"member">>, <<"call_fail">>}) ->
    case QueueId =:= kz_json:get_value(<<"Queue-ID">>, JObj) of
        'true' ->
            Failure = kz_json:get_value(<<"Failure-Reason">>, JObj),
            lager:info("call failed to be processed: ~s (took ~b s)"
                      ,[Failure, kz_time:elapsed_s(Start)]
                      ),
            stop_hold_music(Call),
            cf_exe:continue(Call);
        'false' ->
            lager:info("failure json was for a different queue, ignoring"),
            wait_for_bridge(MC, kz_time:decr_timeout(Timeout, Wait), Start)
    end;
process_message(#member_call{callback_pending=Pending}=MC, Timeout, Start, _Wait, JObj
               ,{<<"acdc_callback">>, <<"response">>}) when is_map(Pending) ->
    handle_late_pause_response(MC, Timeout, Start, JObj);
process_message(#member_call{call=Call, callback=Callback}=MC, Timeout, Start, Wait, JObj
               ,{<<"call_event">>, <<"DTMF">>}) ->
    DigitPressed = kz_json:get_value(<<"DTMF-Digit">>, JObj),
    case {DigitPressed =:= kapps_call:kvs_fetch('caller_exit_key', Call)
         ,callback_entry(DigitPressed, Callback, MC#member_call.callback_pending)} of
        {'true', _} ->
            lager:info("caller pressed the exit key(~s), moving to next callflow action", [DigitPressed]),
            cancel_member_call(Call, <<"dtmf_exit">>),
            _ = kapps_call_command:flush_dtmf(Call),
            timer:sleep(?MILLISECONDS_IN_SECOND),
            cf_exe:continue(Call);
        {'false', 'true'} ->
            begin_callback_menu(MC, Timeout, Start);
        {'false', 'false'} ->
            lager:info("caller pressed ~s, ignoring", [DigitPressed]),
            wait_for_bridge(MC, kz_time:decr_timeout(Timeout, Wait), Start)
    end;
process_message(#member_call{call=Call}, _, Start, _Wait, _JObj, {<<"member">>, <<"call_success">>}) ->
    lager:info("call was processed by queue (took ~b s)", [kz_time:elapsed_s(Start)]),
    cf_exe:control_usurped(Call);
process_message(MC, Timeout, Start, Wait, _JObj, _Type) ->
    wait_for_bridge(MC, kz_time:decr_timeout(Timeout, Wait), Start).

-spec callback_config(kz_json:object(), kapps_call:call()) -> 'undefined' | map().
callback_config(QueueJObj, Call) ->
    case kz_json:is_true([<<"callback">>, <<"enabled">>], QueueJObj, 'false') of
        'false' -> 'undefined';
        'true' ->
            Language = acdc_gemini_prompts:canonical(kapps_call:language(Call)),
            Entry = kz_json:get_ne_binary_value([<<"callback">>, <<"entry_key">>]
                                               ,QueueJObj, <<"6">>),
            AllowAlternate = kz_json:is_true([<<"callback">>, <<"allow_alternate_number">>]
                                                ,QueueJObj, 'false'),
            Media = kz_json:get_json_value([<<"callback">>,<<"media">>], QueueJObj, kz_json:new()),
            case acdc_gemini_prompts:callback(Entry, AllowAlternate, Media, Language, kapps_call:account_id(Call)) of
                {'error', _} ->
                    lager:warning("callback menu disabled: language ~p requires all callback media", [Language]),
                    'undefined';
                {'ok', Resolved} ->
                    Prepared = preflight_callback_auxiliary(Resolved, Language),
                    Prepared#{entry_key => Entry
                     ,allow_alternate_number => AllowAlternate
                     ,timeout_ms => kz_json:get_integer_value([<<"callback">>, <<"menu_timeout_ms">>]
                                                                  ,QueueJObj, 30000)
                     ,success_timeout_ms => kz_json:get_integer_value([<<"callback">>, <<"success_timeout_ms">>]
                                                                          ,QueueJObj, 10000)}
            end
    end.

-spec preflight_callback_auxiliary(map(), binary()) -> map().
preflight_callback_auxiliary(#{builtin_gemini := true}=Callback, _Language) -> Callback;
preflight_callback_auxiliary(#{legacy_custom_media := true}=Callback, Language) ->
    %% Legacy custom menus do not require the generated pack. Resolve optional
    %% exact built-in feedback once, before queue entry/pause, and retain only
    %% available paths. Missing auxiliary audio never disables custom menus.
    Auxiliary = lists:foldl(fun(Name, Acc) ->
        try acdc_gemini_prompts:auxiliary(Name, Language) of
            {ok, Path} when is_binary(Path), byte_size(Path) > 0 -> maps:put(Name, Path, Acc);
            _ -> Acc
        catch _:_ -> Acc
        end
    end, #{}, [unavailable, invalid_entry, enter_number]),
    Callback#{auxiliary => Auxiliary}.

-spec cached_callback_auxiliary(atom(), any()) -> binary().
cached_callback_auxiliary(Name, #{auxiliary := Auxiliary}) when is_map(Auxiliary) ->
    case maps:get(Name, Auxiliary, undefined) of
        Path when is_binary(Path), byte_size(Path) > 0 -> Path;
        _ -> error(missing_cached_callback_auxiliary)
    end;
cached_callback_auxiliary(_, _) -> error(missing_cached_callback_auxiliary).

callback_entry(_Digit, 'undefined', _Pending) -> 'false';
callback_entry(_Digit, _Callback, Pending) when is_map(Pending) -> 'false';
callback_entry(Digit, Callback, 'undefined') -> Digit =:= maps:get(entry_key, Callback).

callback_media_path(Name, #{builtin_gemini := true, media := Media}, _Call) ->
    maps:get(Name, Media);
callback_media_path(Name, Callback, Call) ->
    kapps_call:get_prompt(Call, maps:get(Name, maps:get(media, Callback))).

begin_callback_menu(#member_call{callback=Callback}=MC, Timeout, Start) ->
    RequestId = kz_binary:rand_hex(16),
    Context = callback_context(MC, RequestId, 'undefined'),
    send_callback_request(MC, Context, <<"pause">>, []),
    Deadline = monotonic_ms() + min(?CALLBACK_PAUSE_ACK_TIMEOUT_MS, maps:get(timeout_ms, Callback)),
    Pending = MC#member_call{callback_pending=Context},
    wait_for_pause(Pending, Timeout, Start, Deadline).

callback_context(#member_call{call=Call, queue_id=QueueId}, RequestId, PauseId) ->
    #{account_id => kapps_call:account_id(Call)
     ,queue_id => QueueId
     ,call_id => kapps_call:call_id(Call)
     ,request_id => RequestId
     ,pause_id => PauseId}.

send_callback_request(#member_call{call=Call}, Context, Operation, Extra) ->
    Request = callback_request_props(Context, Operation, Extra),
    cf_exe:amqp_send(Call, Request, fun kapi_acdc_callback:publish_request/1).

callback_request_props(Context, Operation, Extra) ->
    props:filter_undefined(
      [{<<"Account-ID">>, maps:get(account_id, Context)}
      ,{<<"Queue-ID">>, maps:get(queue_id, Context)}
      ,{<<"Call-ID">>, maps:get(call_id, Context)}
      ,{<<"Request-ID">>, maps:get(request_id, Context)}
      ,{<<"Operation">>, Operation}
       | Extra ++ kz_api:default_headers(?APP_NAME, ?APP_VERSION)]).

wait_for_pause(#member_call{max_wait=MaxWait}=MC, Timeout, Start, Deadline) ->
    QueueRemaining = remaining_wait_ms(MaxWait, Start, kz_time:start_time()),
    Wait = min(QueueRemaining, max(0, Deadline - monotonic_ms())),
    case Wait of
        0 -> wait_for_bridge(MC, Timeout, Start);
        _ ->
            receive
                {'amqp_msg', JObj} -> handle_pause_message(MC, Timeout, Start, Deadline, JObj)
            after Wait ->
                    wait_for_bridge(MC, Timeout, Start)
            end
    end.

handle_pause_message(#member_call{callback_pending=Context}=MC, Timeout, Start, Deadline, JObj) ->
    case callback_response(JObj, Context) of
        {'ok', <<"pause">>, <<"paused">>, PauseId, _} ->
            callback_paused(MC#member_call{callback_pending='undefined'}
                           ,Context#{pause_id => PauseId}, Timeout, Start);
        {'ok', <<"pause">>, <<"rejected">>, _, _} ->
            lager:info("callback pause rejected; caller remains in the live queue"),
            wait_for_bridge(MC#member_call{callback_pending='undefined'}, Timeout, Start);
        _ ->
            case callback_pause_call_event(MC, JObj, kz_api:event_type(JObj), Start) of
                'continue' -> wait_for_pause(MC, Timeout, Start, Deadline);
                'finished' -> 'ok'
            end
    end.

callback_pause_call_event(#member_call{callback_pending=Context}=MC, JObj, _Type, _Start) ->
    finish_callback_event(MC, Context, callback_call_event(MC, Context, JObj)).

%% Callback receives share a mailbox with channel/ownership events. Never
%% consume a terminal event as unrelated ACK noise, or react to another leg.
callback_call_event(#member_call{call=Call}, Context, JObj) ->
    case {kz_json:get_ne_binary_value(<<"Call-ID">>, JObj) =:= kapps_call:call_id(Call), kz_api:event_type(JObj)} of
        {'true', {<<"call_event">>, Name}}
          when Name =:= <<"CHANNEL_DESTROY">>; Name =:= <<"CHANNEL_DISCONNECTED">> -> 'hangup';
        {'true', {<<"call_event">>, <<"CHANNEL_BRIDGE">>}} -> 'usurped';
        {'true', {<<"call_event">>, <<"usurp_control">>}} ->
            case kz_json:get_ne_binary_value(<<"Fetch-ID">>, JObj) =:= kapps_call:custom_channel_var(<<"Fetch-ID">>, Call) of
                'true' -> 'continue';
                'false' -> 'usurped'
            end;
        {'true', {<<"member">>, <<"call_success">>}} ->
            case kz_json:get_ne_binary_value(<<"Account-ID">>, JObj) =:= maps:get(account_id, Context)
                andalso kz_json:get_ne_binary_value(<<"Queue-ID">>, JObj) =:= maps:get(queue_id, Context) of
                'true' -> 'usurped';
                'false' -> 'continue'
            end;
        _ -> 'continue'
    end.

finish_callback_event(_MC, _Context, 'continue') -> 'continue';
finish_callback_event(#member_call{call=Call}=MC, Context, 'hangup') ->
    case maps:get(pause_id, Context, 'undefined') of
        PauseId when is_binary(PauseId) -> abandon_callback_queue_nowait(MC, Context, 'undefined');
        _ -> 'ok'
    end,
    cancel_member_call(Call, ?MEMBER_HANGUP),
    cf_exe:stop(Call),
    'finished';
finish_callback_event(#member_call{call=Call}, _Context, 'usurped') ->
    cf_exe:control_usurped(Call),
    'finished'.

handle_late_pause_response(#member_call{callback_pending=Context}=MC, Timeout, Start, JObj) ->
    case callback_response(JObj, Context) of
        {'ok', <<"pause">>, <<"paused">>, PauseId, _} ->
            lager:warning("late callback pause acknowledgement; resuming the live queue"),
            ResumeContext = Context#{pause_id => PauseId},
            case resume_callback_live_queue(MC, ResumeContext, 'undefined') of
                'finished' -> 'ok';
                'resume' -> wait_for_bridge(MC#member_call{callback_pending='undefined'}, Timeout, Start)
            end;
        {'ok', <<"pause">>, <<"rejected">>, _, _} ->
            wait_for_bridge(MC#member_call{callback_pending='undefined'}, Timeout, Start);
        _ -> wait_for_bridge(MC, Timeout, Start)
    end.

callback_paused(#member_call{callback=Callback, call=Call}=MC, Context, Timeout, Start) ->
    _ = kapps_call_command:flush_dtmf(Call),
    Config = #{request_id => maps:get(request_id, Context)
              ,queue_id => maps:get(queue_id, Context)
              ,original_call_id => maps:get(call_id, Context)
              ,confirm_key => <<"1">>
              ,alternate_key => <<"2">>
              ,allow_alternate_number => maps:get(allow_alternate_number, Callback)
              ,max_retries => 3
              ,timeout_ms => maps:get(timeout_ms, Callback)
              ,success_timeout_ms => maps:get(success_timeout_ms, Callback)},
    case acdc_callback_menu:new(Config, kapps_call:caller_id_number(Call), monotonic_ms()) of
        {'ok', State, Actions} ->
            case run_callback_actions(MC, Context, State, Actions) of
                'resume' -> wait_for_bridge(MC, Timeout, Start);
                'finished' -> 'ok'
            end;
        {'error', Reason} ->
            lager:warning("callback menu unavailable: ~p; resuming live queue", [Reason]),
            case callback_unavailable(MC, Context, ?CALLBACK_UNAVAILABLE_TIMEOUT_MS) of
                'resume' ->
                    case resume_callback_live_queue(MC, Context, 'undefined') of
                        'finished' -> 'ok';
                        %% Keep the original queue entry and absolute wait budget.
                        'resume' -> wait_for_bridge(MC, Timeout, Start)
                    end;
                'finished' -> 'ok'
            end
    end.

%% An unusable caller ID is not a registered callback. Give truthful feedback
%% while the original member is paused, without silently enabling alternatives
%% or playing the callback-success announcement. Only the exact built-in
%% localized auxiliary is eligible; missing assets resume without a fallback.
callback_unavailable(MC, Context, TimeoutMs) ->
    case callback_auxiliary_feedback(unavailable, MC, Context, TimeoutMs) of
        'finished' -> 'finished';
        _ -> 'resume'
    end.

callback_auxiliary_feedback(Name, #member_call{call=Call, callback=Callback}=MC, Context, TimeoutMs) ->
    Deadline = monotonic_ms() + min(?CALLBACK_UNAVAILABLE_TIMEOUT_MS, max(0, TimeoutMs)),
    %% The generated message may last twenty seconds. Bound this file handle and
    %% retain an absolute wrapper deadline; no inherited channel timeout changes.
    PromptResult = try
                       true = Deadline > monotonic_ms(),
                       %% This paused/timed branch must never fetch metadata.
                       Media = cached_callback_auxiliary(Name, Callback),
                       Remaining = Deadline - monotonic_ms(),
                       true = Remaining > 0,
                       Noop = kapps_call_command:noop_id(),
                       PlaybackTimeout = min(?CALLBACK_AUXILIARY_PLAYBACK_TIMEOUT_MS, Remaining),
                       Play = kz_json:set_values([{<<"Playback-Timeout-Ms">>, PlaybackTimeout}, {<<"Msg-ID">>, Noop}],
                                  kapps_call_command:play_command(Media, [], Call)),
                       Done = kz_json:from_list([{<<"Application-Name">>, <<"noop">>}, {<<"Msg-ID">>, Noop}
                                                ,{<<"Call-ID">>, kapps_call:call_id(Call)}]),
                       kapps_call_command:send_command([{<<"Application-Name">>, <<"queue">>}
                                                       ,{<<"Commands">>, [Done, Play]}], Call),
                       Noop
                   catch _:_ -> 'undefined'
                   end,
    case PromptResult of
        NoopId when is_binary(NoopId), byte_size(NoopId) > 0 ->
            wait_callback_unavailable(MC, Context, NoopId, Deadline);
        _ -> 'failed'
    end.

wait_callback_unavailable(MC, Context, NoopId, Deadline) ->
    case max(0, Deadline - monotonic_ms()) of
        0 -> 'failed';
        Remaining ->
            receive
                {'amqp_msg', JObj} ->
                    case callback_unavailable_event(MC, Context, NoopId, JObj) of
                        'continue' -> wait_callback_unavailable(MC, Context, NoopId, Deadline);
                        Result -> Result
                    end
            after Remaining -> 'failed'
            end
    end.

callback_unavailable_event(#member_call{call=Call}=MC, Context, NoopId, JObj) ->
    CallId = kapps_call:call_id(Call),
    EventCallId = case kz_json:get_ne_binary_value(<<"Call-ID">>, JObj) of
                      'undefined' -> callback_error_request_value(<<"Call-ID">>, JObj);
                      Id -> Id
                  end,
    case {EventCallId =:= CallId, kz_api:event_type(JObj)} of
        {'true', {<<"call_event">>, Name}}
          when Name =:= <<"CHANNEL_DESTROY">>; Name =:= <<"CHANNEL_DISCONNECTED">> ->
            abandon_callback_queue_nowait(MC, Context, 'undefined'),
            cancel_member_call(Call, ?MEMBER_HANGUP),
            cf_exe:stop(Call),
            'finished';
        {'true', {<<"call_event">>, <<"CHANNEL_BRIDGE">>}} ->
            cf_exe:control_usurped(Call),
            'finished';
        {'true', {<<"call_event">>, <<"usurp_control">>}} ->
            case kz_json:get_ne_binary_value(<<"Fetch-ID">>, JObj)
                    =:= kapps_call:custom_channel_var(<<"Fetch-ID">>, Call) of
                'true' -> 'continue';
                'false' -> cf_exe:control_usurped(Call), 'finished'
            end;
        {'true', {<<"member">>, <<"call_success">>}} ->
            case kz_json:get_ne_binary_value(<<"Account-ID">>, JObj) =:= maps:get(account_id, Context)
                andalso kz_json:get_ne_binary_value(<<"Queue-ID">>, JObj) =:= maps:get(queue_id, Context) of
                'true' -> cf_exe:control_usurped(Call), 'finished';
                'false' -> 'continue'
            end;
        {'true', {<<"call_event">>, <<"CHANNEL_EXECUTE_COMPLETE">>}} ->
            case kz_call_event:application_name(JObj) =:= <<"noop">>
                andalso kz_call_event:application_response(JObj) =:= NoopId of
                'true' -> 'complete';
                'false' -> 'continue'
            end;
        {'true', {<<"error">>, _}} -> callback_unavailable_media_error(NoopId, JObj);
        {'true', {<<"call_event">>, <<"CHANNEL_EXECUTE_ERROR">>}} ->
            callback_unavailable_media_error(NoopId, JObj);
        _ -> 'continue'
    end.

callback_unavailable_media_error(NoopId, JObj) ->
    case kz_call_event:application_response(JObj) =:= NoopId
        orelse kz_json:get_ne_binary_value(<<"Msg-ID">>, JObj) =:= NoopId
        orelse callback_error_request_value(<<"Msg-ID">>, JObj) =:= NoopId of
        'true' -> 'failed';
        'false' -> 'continue'
    end.

%% Call events use Request for a SIP URI; dialplan errors may instead carry
%% the original command object there. Never traverse the URI (or other JSON
%% scalar) as an object, including while evaluating an unused default value.
-spec callback_error_request_value(kz_term:ne_binary(), kz_json:object()) -> kz_term:api_ne_binary().
callback_error_request_value(Key, JObj) ->
    Request = kz_json:get_value(<<"Request">>, JObj),
    case kz_json:is_json_object(Request) of
        'true' -> kz_json:get_ne_binary_value(Key, Request);
        'false' -> 'undefined'
    end.

run_callback_actions(MC, Context, State, []) ->
    case acdc_callback_menu:status(State) of
        'menu' -> run_callback_actions(MC, Context, State, [{'play_menu', <<>>, 'false'}]);
        'collecting' -> run_callback_actions(MC, Context, State, ['collect_alternate']);
        'confirming_alternate' ->
            run_callback_actions(MC, Context, State
                                ,[{'read_back_number', maps:get(digits, State)}
                                 ,{'prompt_confirm_alternate', <<"1">>}]);
        'complete' -> 'finished';
        'aborted' -> 'resume';
        'aborted_dead' -> 'finished';
        _ ->
            lager:error("callback menu produced no action in phase ~p", [acdc_callback_menu:status(State)]),
            resume_callback_live_queue(MC, Context, 'undefined')
    end;
run_callback_actions(MC, Context, State
                    ,[{'resume_live_queue', _}, {'cancel_callback', CallbackId} | Rest]) ->
    case resume_callback_live_queue(MC, Context, CallbackId) of
        'finished' -> 'finished';
        'resume' -> run_callback_actions(MC, Context, State, Rest)
    end;
run_callback_actions(MC, Context, State, [{'play_menu', _, _} | Rest]) ->
    case collect_callback_digit(menu, MC, State) of
        {'ok', Digit} -> reduce_callback_event(MC, Context, State, {'dtmf', Digit}, Rest);
        'timeout' -> reduce_callback_event(MC, Context, State, 'tick', Rest);
        'hangup' -> reduce_callback_event(MC, Context, State, 'caller_hangup', Rest)
    end;
run_callback_actions(MC, Context, State, ['collect_alternate' | Rest]) ->
    case collect_callback_alternate(MC, State) of
        {'ok', Digit} -> reduce_callback_event(MC, Context, State, {'dtmf', Digit}, Rest);
        'timeout' -> reduce_callback_event(MC, Context, State, 'tick', Rest);
        'media_failed' -> resume_callback_live_queue(MC, Context, 'undefined');
        'hangup' -> reduce_callback_event(MC, Context, State, 'caller_hangup', Rest)
    end;
run_callback_actions(MC, Context, State, [{'read_back_number', _} | Rest]) ->
    run_callback_actions(MC, Context, State, Rest);
run_callback_actions(MC, Context, State, [{'prompt_confirm_alternate', _} | Rest]) ->
    case collect_callback_confirmation(MC, State) of
        {'ok', Digit} -> reduce_callback_event(MC, Context, State, {'dtmf', Digit}, Rest);
        'timeout' -> reduce_callback_event(MC, Context, State, 'tick', Rest);
        'media_failed' -> resume_callback_live_queue(MC, Context, 'undefined');
        'hangup' -> reduce_callback_event(MC, Context, State, 'caller_hangup', Rest)
    end;
run_callback_actions(MC, Context, State
                    ,[{'register_callback', _, _, _, Number} | Rest]) ->
    send_callback_request(MC, Context, <<"register">>
                         ,[{<<"Pause-ID">>, maps:get(pause_id, Context)}, {<<"Number">>, Number}]),
    wait_callback_registration(MC, Context, State, Rest);
run_callback_actions(MC, Context, _State, [{'resume_live_queue', _} | _Rest]) ->
    resume_callback_live_queue(MC, Context, 'undefined');
run_callback_actions(MC, Context, _State, ['abandon_paused_queue' | _Rest]) ->
    %% CHANNEL_DESTROY may reach the queue listener before this request and
    %% clear its callback binding. Publish the explicit abandon required by
    %% the protocol, but never delay teardown waiting for an acknowledgement
    %% that can no longer be routed to this dead leg.
    abandon_callback_queue_nowait(MC, Context, 'undefined'),
    'finished';
run_callback_actions(MC, Context, State, [{'cancel_callback', CallbackId} | Rest]) ->
    case abandon_callback_queue(MC, Context, CallbackId) of
        'finished' -> 'finished';
        _ -> run_callback_actions(MC, Context, State, Rest)
    end;
run_callback_actions(MC, Context, State, [{'handoff_to_callback', _} | Rest]) ->
    run_callback_actions(MC, Context, State, Rest);
run_callback_actions(#member_call{call=Call}=MC, Context, State
                    ,[{'play_success_announcement', CallbackId} | Rest]) ->
    case wait_callback_success(MC, Context, State) of
        'hangup' ->
            %% Registration is durable now: stop only this dead executor.
            %% Do not send the pre-registration abandon/cancel protocol.
            cf_exe:stop(Call),
            'finished';
        'usurped' ->
            %% Another owner/bridge must not receive our delayed hangup.
            %% Durable-ticket reconciliation belongs to the queue worker.
            cf_exe:control_usurped(Call),
            'finished';
        Result ->
            Event = case Result of
                        'complete' -> {trusted_announcement_complete, maps:get(queue_id, Context)
                                      ,maps:get(call_id, Context), CallbackId};
                        'failed' -> {trusted_announcement_failed, maps:get(queue_id, Context)
                                    ,maps:get(call_id, Context), CallbackId}
                    end,
            reduce_callback_event(MC, Context, State, Event, Rest)
    end;
run_callback_actions(#member_call{call=Call}, _Context, _State, ['hangup' | _]) ->
    _ = kapps_call_command:hangup(Call),
    cf_exe:stop(Call),
    'finished';
run_callback_actions(#member_call{call=Call}, _Context, _State, [{'end_original_leg', _, _} | _]) ->
    _ = kapps_call_command:hangup(Call),
    cf_exe:stop(Call),
    'finished';
run_callback_actions(MC, Context, State, [{'retry', _} | Rest]) ->
    Remaining = acdc_callback_menu:remaining_ms(monotonic_ms(), State),
    case callback_auxiliary_feedback(invalid_entry, MC, Context, Remaining) of
        'complete' -> run_callback_actions(MC, Context, State, Rest);
        'finished' -> 'finished';
        'failed' -> resume_callback_live_queue(MC, Context, 'undefined')
    end.

reduce_callback_event(MC, Context, State, Event, Prefix) ->
    {Next, Actions} = acdc_callback_menu:event(Event, monotonic_ms(), State),
    run_callback_actions(MC, Context, Next, Prefix ++ Actions).

collect_callback_alternate(MC, State) ->
    case acdc_callback_menu:remaining_ms(monotonic_ms(), State) of
        0 -> 'timeout';
        _ ->
            %% Entering directly without usable caller ID and pressing the
            %% alternate key must both be audible. Re-prompt after invalid
            %% input clears the buffer, but never between valid digits.
            case callback_enter_number(MC, State) of
                'error' -> 'media_failed';
                'ok' -> wait_callback_alternate(State)
            end
    end.

callback_enter_number(#member_call{call=Call, callback=Callback}, State) ->
    case maps:get(digits, State) of
        <<>> ->
            try
                Media = cached_callback_auxiliary(enter_number, Callback),
                Remaining = acdc_callback_menu:remaining_ms(monotonic_ms(), State),
                true = Remaining > 0,
                Play = kz_json:set_value(<<"Playback-Timeout-Ms">>,
                            min(?CALLBACK_AUXILIARY_PLAYBACK_TIMEOUT_MS, Remaining),
                            kapps_call_command:play_command(Media, [], Call)),
                _ = kapps_call_command:send_command(Play, Call),
                'ok'
            catch _:_ -> 'error'
            end;
        _ -> 'ok'
    end.

wait_callback_alternate(State) ->
    %% Unlike collect_digits with a playback noop, this helper keeps
    %% decrementing the receive timeout while playback events arrive.
    %% Do not consume # or * here: the reducer validates both keys.
    Remaining = acdc_callback_menu:remaining_ms(monotonic_ms(), State),
    case kapps_call_command:wait_for_dtmf(Remaining) of
        {'ok', <<>>} -> 'timeout';
        {'ok', Digit} -> {'ok', Digit};
        {'error', 'timeout'} -> 'timeout';
        {'error', _} -> 'hangup'
    end.

collect_callback_digit(MediaName, #member_call{call=Call, callback=Callback}, State) ->
    Remaining = acdc_callback_menu:remaining_ms(monotonic_ms(), State),
    case Remaining of
        0 -> 'timeout';
        _ ->
            Collect = case MediaName of
                          'undefined' ->
                              %% The 6-arity form starts its receive deadline
                              %% immediately. The 7-arity form intentionally
                              %% waits for a playback noop, which does not exist
                              %% while collecting the alternate number.
                              kapps_call_command:collect_digits(
                                1, Remaining, kapps_call_command:default_interdigit_timeout()
                               ,'undefined', [], Call);
                          _ ->
                              NoopId = kapps_call_command:play(
                                         callback_media_path(MediaName, Callback, Call), Call),
                              kapps_call_command:collect_digits(
                                1, Remaining, kapps_call_command:default_interdigit_timeout()
                               ,NoopId, [], 'false', Call)
                      end,
            case Collect of
                {'ok', <<>>} -> 'timeout';
                {'ok', Digit} -> {'ok', Digit};
                {'error', 'channel_hungup'} -> 'hangup';
                {'error', _} -> 'hangup'
            end
    end.

collect_callback_confirmation(#member_call{call=Call, callback=Callback}=MC, State) ->
    Digits = maps:get(digits, State),
    Remaining = acdc_callback_menu:remaining_ms(monotonic_ms(), State),
    case Remaining of
        0 -> 'timeout';
        _ ->
            case callback_confirmation_prompts(Callback, Call, Digits) of
                {error,_} -> 'media_failed';
                {ok,Prompts} ->
                    NoopId = kapps_call_command:audio_macro(Prompts, Call),
                    collect_callback_confirmation_digit(MC, State, NoopId)
            end
    end.

-spec callback_confirmation_prompts(map(), kapps_call:call(), binary()) -> tuple().
callback_confirmation_prompts(Callback, Call, Digits) ->
    case acdc_gemini_prompts:callback_readback(Digits, Callback) of
        {ok,NumberPrompts} ->
            {ok,[{play,callback_media_path(number_readback,Callback,Call)}] ++ NumberPrompts
                ++ [{play,callback_media_path(confirmation,Callback,Call)}]};
        Error -> Error
    end.

collect_callback_confirmation_digit(MC, State, NoopId) ->
    Remaining = acdc_callback_menu:remaining_ms(monotonic_ms(), State),
    case Remaining of
        0 -> 'timeout';
        _ ->
            case kapps_call_command:collect_digits(1, Remaining
                                                  ,kapps_call_command:default_interdigit_timeout()
                                                  ,NoopId, [], 'false', MC#member_call.call) of
                {'ok', <<>>} -> 'timeout';
                {'ok', Digit} -> {'ok', Digit};
                {'error', _} -> 'hangup'
            end
    end.

wait_callback_registration(MC, Context, State, Rest) ->
    Remaining = acdc_callback_menu:remaining_ms(monotonic_ms(), State),
    case Remaining of
        0 -> reduce_callback_event(MC, Context, State, 'tick', Rest);
        _ ->
            receive
                {'amqp_msg', JObj} ->
                    case callback_response(JObj, Context) of
                        {'ok', <<"register">>, <<"registered">>, _, CallbackId} ->
                            Event = {trusted_queue_ack, maps:get(queue_id, Context)
                                    ,maps:get(call_id, Context), maps:get(request_id, Context)
                                    ,{'ok', CallbackId}},
                            reduce_callback_event(MC, Context, State, Event, Rest);
                        {'ok', <<"register">>, <<"rejected">>, _, _} ->
                            Event = {trusted_queue_ack, maps:get(queue_id, Context)
                                    ,maps:get(call_id, Context), maps:get(request_id, Context)
                                    ,{'error', 'rejected'}},
                            reduce_callback_event(MC, Context, State, Event, Rest);
                        _ ->
                            case finish_callback_event(MC, Context, callback_call_event(MC, Context, JObj)) of
                                'finished' -> 'finished';
                                'continue' -> wait_callback_registration(MC, Context, State, Rest)
                            end
                    end
            after Remaining ->
                    reduce_callback_event(MC, Context, State, 'tick', Rest)
            end
    end.

wait_callback_success(#member_call{call=Call, callback=Callback}=MC, Context, State) ->
    NoopId = kapps_call_command:play(callback_media_path(success, Callback, Call), Call),
    wait_callback_success_event(MC, Context, NoopId, maps:get(success_deadline_ms, State)).

wait_callback_success_event(MC, Context, NoopId, Deadline) ->
    case max(0, Deadline - monotonic_ms()) of
        0 -> 'failed';
        Remaining ->
            receive
                {'amqp_msg', JObj} ->
                    case callback_success_event(MC, Context, NoopId, JObj) of
                        'continue' -> wait_callback_success_event(MC, Context, NoopId, Deadline);
                        Result -> Result
                    end
            after Remaining -> 'failed'
            end
    end.

callback_success_event(#member_call{call=Call}, Context, NoopId, JObj) ->
    %% The accepted context names the original leg, even if call helpers have
    %% since been updated by a transfer. Completion also needs this play's noop.
    case {kz_json:get_ne_binary_value(<<"Call-ID">>, JObj) =:= maps:get(call_id, Context)
         ,kz_api:event_type(JObj)} of
        {'true', {<<"call_event">>, Name}}
          when Name =:= <<"CHANNEL_DESTROY">>; Name =:= <<"CHANNEL_DISCONNECTED">> -> 'hangup';
        {'true', {<<"call_event">>, <<"CHANNEL_BRIDGE">>}} -> 'usurped';
        {'true', {<<"call_event">>, <<"usurp_control">>}} ->
            case kz_json:get_ne_binary_value(<<"Fetch-ID">>, JObj) =:= kapps_call:custom_channel_var(<<"Fetch-ID">>, Call) of
                'true' -> 'continue';
                'false' -> 'usurped'
            end;
        {'true', {<<"member">>, <<"call_success">>}} ->
            case kz_json:get_ne_binary_value(<<"Account-ID">>, JObj) =:= maps:get(account_id, Context)
                andalso kz_json:get_ne_binary_value(<<"Queue-ID">>, JObj) =:= maps:get(queue_id, Context) of
                'true' -> 'usurped';
                'false' -> 'continue'
            end;
        {'true', {<<"call_event">>, <<"CHANNEL_EXECUTE_COMPLETE">>}} ->
            case kz_call_event:application_name(JObj) =:= <<"noop">>
                andalso kz_call_event:application_response(JObj) =:= NoopId of
                'true' -> 'complete';
                'false' -> 'continue'
            end;
        _ -> 'continue'
    end.

resume_callback_queue(MC, Context, CallbackId) ->
    Extra = [{<<"Pause-ID">>, maps:get(pause_id, Context)}, {<<"Callback-ID">>, CallbackId}],
    send_callback_request(MC, Context, <<"resume">>, Extra),
    wait_callback_control_ack(MC, Context, <<"resume">>, ?CALLBACK_RESUME_ACK_TIMEOUT_MS).

resume_callback_live_queue(MC, Context, CallbackId) ->
    case resume_callback_queue(MC, Context, CallbackId) of
        'finished' -> 'finished';
        _ -> 'resume'
    end.

abandon_callback_queue(MC, Context, CallbackId) ->
    Extra = [{<<"Pause-ID">>, maps:get(pause_id, Context)}, {<<"Callback-ID">>, CallbackId}],
    send_callback_request(MC, Context, <<"abandon">>, Extra),
    wait_callback_control_ack(MC, Context, <<"abandon">>, ?CALLBACK_RESUME_ACK_TIMEOUT_MS).

abandon_callback_queue_nowait(MC, Context, CallbackId) ->
    Extra = [{<<"Pause-ID">>, maps:get(pause_id, Context)}, {<<"Callback-ID">>, CallbackId}],
    send_callback_request(MC, Context, <<"abandon">>, Extra).

wait_callback_control_ack(_MC, _Context, Operation, 0) -> {'error', {Operation, 'timeout'}};
wait_callback_control_ack(MC, Context, Operation, Remaining) ->
    Start = monotonic_ms(),
    receive
        {'amqp_msg', JObj} ->
            case callback_response(JObj, Context) of
                {'ok', Operation, Status, _, _}
                  when Operation =:= <<"resume">>, Status =:= <<"resumed">>;
                       Operation =:= <<"abandon">>, Status =:= <<"abandoned">> -> 'ok';
                {'ok', <<"register">>, <<"registered">>, _, CallbackId}
                  when Operation =:= <<"resume">> ->
                    %% Resume cancels durable registration AND restores the
                    %% original live member. Abandon would remove that member.
                    %% Keep this receive's original deadline, never start a
                    %% fresh ten-second ACK loop on a duplicate/late result.
                    send_callback_request(MC, Context, <<"resume">>,
                        [{<<"Pause-ID">>, maps:get(pause_id, Context)}, {<<"Callback-ID">>, CallbackId}]),
                    wait_callback_control_ack(MC, Context, Operation,
                        max(0, Remaining - (monotonic_ms() - Start)));
                {'ok', Operation, <<"rejected">>, _, _} -> {'error', {Operation, 'rejected'}};
                _ ->
                    case finish_callback_event(MC, Context, callback_call_event(MC, Context, JObj)) of
                        'finished' -> 'finished';
                        'continue' -> wait_callback_control_ack(MC, Context, Operation,
                            max(0, Remaining - (monotonic_ms() - Start)))
                    end
            end
    after Remaining -> {'error', {Operation, 'timeout'}}
    end.

callback_response(JObj, Context) ->
    case kapi_acdc_callback:response_v(JObj)
        andalso maps:get(account_id, Context) =:= kz_json:get_value(<<"Account-ID">>, JObj)
        andalso maps:get(queue_id, Context) =:= kz_json:get_value(<<"Queue-ID">>, JObj)
        andalso maps:get(call_id, Context) =:= kz_json:get_value(<<"Call-ID">>, JObj)
        andalso maps:get(request_id, Context) =:= kz_json:get_value(<<"Request-ID">>, JObj)
        andalso (maps:get(pause_id, Context, 'undefined') =:= 'undefined'
                 orelse kz_json:get_value(<<"Status">>, JObj) =:= <<"rejected">>
                 orelse maps:get(pause_id, Context) =:= kz_json:get_value(<<"Pause-ID">>, JObj)) of
        'false' -> 'nomatch';
        'true' ->
            {'ok', kz_json:get_value(<<"Operation">>, JObj)
             ,kz_json:get_value(<<"Status">>, JObj)
             ,kz_json:get_value(<<"Pause-ID">>, JObj)
             ,kz_json:get_value(<<"Callback-ID">>, JObj)}
    end.

-ifdef(TEST).
-spec callback_test_media(kz_json:object(), kz_term:api_binary()) -> {'ok', map()} | {'error', any()}.
callback_test_media(QueueJObj, Language) ->
    Entry = kz_json:get_ne_binary_value([<<"callback">>, <<"entry_key">>], QueueJObj, <<"6">>),
    AllowAlternate = kz_json:is_true([<<"callback">>, <<"allow_alternate_number">>], QueueJObj, 'false'),
    Media = kz_json:get_json_value([<<"callback">>,<<"media">>], QueueJObj, kz_json:new()),
    case acdc_gemini_prompts:callback(Entry, AllowAlternate, Media, Language,
                                    <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>) of
        {ok,Resolved} -> {ok,maps:get(media,Resolved)};
        Error -> Error
    end.

-spec callback_test_request(map(), kz_term:ne_binary(), kz_term:proplist()) -> kz_term:proplist().
callback_test_request(Context, Operation, Extra) ->
    callback_request_props(Context, Operation, Extra).

-spec callback_test_response(kz_json:object(), map()) -> tuple() | 'nomatch'.
callback_test_response(JObj, Context) -> callback_response(JObj, Context).

-spec callback_test_collect_alternate(kapps_call:call(), map(), map()) ->
          {'ok', binary()} | 'timeout' | 'hangup' | 'media_failed'.
callback_test_collect_alternate(Call, Callback, State) ->
    collect_callback_alternate(#member_call{call=Call, callback=Callback}, State).

-spec callback_test_paused(kapps_call:call(), map(), map()) -> 'ok'.
callback_test_paused(Call, Callback, Context) ->
    MC = #member_call{call=Call, queue_id=maps:get(queue_id, Context), callback=Callback},
    callback_paused(MC, Context, 60, kz_time:start_time()).

-spec callback_test_unavailable(kapps_call:call(), map(), map(), non_neg_integer()) -> 'resume' | 'finished'.
callback_test_unavailable(Call, Callback, Context, TimeoutMs) ->
    MC = #member_call{call=Call, queue_id=maps:get(queue_id, Context), callback=Callback},
    callback_unavailable(MC, Context, TimeoutMs).

-spec callback_test_retry(kapps_call:call(), map(), map(), map()) -> term().
callback_test_retry(Call, Callback, Context, State) ->
    MC = #member_call{call=Call, queue_id=maps:get(queue_id, Context), callback=Callback},
    run_callback_actions(MC, Context, State, [{retry, 1}]).

-spec callback_test_control_ack(kapps_call:call(), map(), binary(), non_neg_integer()) -> term().
callback_test_control_ack(Call, Context, Operation, TimeoutMs) ->
    MC = #member_call{call=Call, queue_id=maps:get(queue_id, Context)},
    wait_callback_control_ack(MC, Context, Operation, TimeoutMs).

-spec callback_test_pause(kapps_call:call(), map(), non_neg_integer()) -> term().
callback_test_pause(Call, Context, TimeoutMs) ->
    MC = #member_call{call=Call, queue_id=maps:get(queue_id, Context), callback_pending=Context},
    wait_for_pause(MC, 60, kz_time:start_time(), monotonic_ms() + TimeoutMs).

-spec callback_test_registration(kapps_call:call(), map(), non_neg_integer()) -> term().
callback_test_registration(Call, Context, TimeoutMs) ->
    Now = monotonic_ms(),
    Config = #{request_id => maps:get(request_id, Context), queue_id => maps:get(queue_id, Context),
               original_call_id => maps:get(call_id, Context)},
    {ok, Awaiting, [{register_callback, _, _, _, <<"1001">>}]} =
        acdc_callback_menu:new(Config, <<"1001">>, Now),
    MC = #member_call{call=Call, queue_id=maps:get(queue_id, Context)},
    wait_callback_registration(MC, Context, Awaiting#{deadline_ms => Now + TimeoutMs}, []).

-spec callback_test_success(kapps_call:call(), map(), map(), non_neg_integer()) -> term().
callback_test_success(Call, Callback, Context, TimeoutMs) ->
    Now = monotonic_ms(),
    Config = #{request_id => maps:get(request_id, Context), queue_id => maps:get(queue_id, Context),
               original_call_id => maps:get(call_id, Context)},
    {ok, Awaiting, [{register_callback, _, _, _, <<"1001">>}]} =
        acdc_callback_menu:new(Config, <<"1001">>, Now),
    CallbackId = <<"acdc-callback-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>,
    Ack = {trusted_queue_ack, maps:get(queue_id, Context), maps:get(call_id, Context),
           maps:get(request_id, Context), {ok, CallbackId}},
    {Accepted, Actions} = acdc_callback_menu:event(Ack, Now, Awaiting),
    MC = #member_call{call=Call, queue_id=maps:get(queue_id, Context), callback=Callback},
    run_callback_actions(MC, Context, Accepted#{success_deadline_ms => Now + TimeoutMs}, Actions).
-endif.

monotonic_ms() -> erlang:monotonic_time('millisecond').

-spec max_wait(integer()) -> max_wait().
max_wait(N) when N < 1 -> 'infinity';
max_wait(N) -> N.

max_queue_size(N) when is_integer(N), N > 0 -> N;
max_queue_size(_) -> 0.

-spec is_queue_full(non_neg_integer(), non_neg_integer()) -> boolean().
is_queue_full(0, _) -> 'false';
is_queue_full(MaxQueueSize, CurrQueueSize) -> CurrQueueSize >= MaxQueueSize.

-spec cancel_member_call(kapps_call:call(), kz_term:ne_binary()) -> 'ok'.
cancel_member_call(Call, <<"timeout">>) ->
    lager:info("update reason from `timeout` to `member_timeout`"),
    cancel_member_call(Call, ?MEMBER_TIMEOUT);
cancel_member_call(Call, Reason) ->
    AcctId = kapps_call:account_id(Call),
    {'ok', QueueId} = kapps_call:kvs_find('queue_id', Call),
    CallId = kapps_call:call_id(Call),

    Req = props:filter_undefined(
            [{<<"Account-ID">>, AcctId}
            ,{<<"Queue-ID">>, QueueId}
            ,{<<"Call-ID">>, CallId}
            ,{<<"Reason">>, Reason}
             | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
            ]),
    kapi_acdc_queue:publish_member_call_cancel(Req).

stop_hold_music(Call) ->
    Cmd = [{<<"Application-Name">>, <<"play">>}
          ,{<<"Call-ID">>, kapps_call:call_id(Call)}
          ,{<<"Media-Name">>, <<"silence_stream://50">>}
          ,{<<"Insert-At">>, <<"now">>}
          ],
    kapps_call_command:send_command(Cmd, Call).
