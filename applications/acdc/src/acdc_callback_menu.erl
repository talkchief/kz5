%%% SPDX-License-Identifier: MPL-2.0
%%% Pure callback-menu state reducer. It has no telephony, AMQP or datastore
%%% side effects; the caller executes returned actions and feeds correlated
%%% durable registration results back into event/3.
-module(acdc_callback_menu).

-export([new/3, event/3, status/1, remaining_ms/2]).

-type state() :: map().
-type action() :: term().

-define(DEFAULT_MAX_RETRIES, 3).
-define(DEFAULT_TIMEOUT_MS, 30000).
-define(MAX_TIMEOUT_MS, 120000).
-define(DEFAULT_SUCCESS_TIMEOUT_MS, 10000).
-define(MAX_SUCCESS_TIMEOUT_MS, 30000).
-define(MAX_DIGITS, 15).

-spec new(map(), binary() | 'undefined', integer()) ->
          {'ok', state(), [action()]} | {'error', 'invalid_config' | 'invalid_number'}.
new(Config, CurrentNumber, NowMs) when is_map(Config), is_integer(NowMs) ->
    case {normalize_number(CurrentNumber), config(Config)} of
        {{'ok', Number}, {'ok', Settings}} ->
            State = Settings#{phase => 'menu'
                             ,current_number => Number
                             ,digits => <<>>
                             ,retries => 0
                             ,deadline_ms => NowMs + maps:get(timeout_ms, Settings)
                             ,registration_emitted => 'false'
                             },
            case maps:get(allow_alternate_number, Settings) of
                'false' ->
                    %% The caller already selected callback with the queue's
                    %% entry key and the wrapper obtained a correlated pause.
                    %% With no destination choice, do not ask for a second key.
                    %% This is only a registration request: the queue still
                    %% authorizes/persists it before success audio or hangup.
                    {Waiting, Actions} = request_registration(State, Number),
                    {'ok', Waiting, Actions};
                'true' -> {'ok', State, [{'play_menu', Number, 'true'}]}
            end;
        {{'error', _}, {'ok', #{allow_alternate_number := 'true'}=Settings}} ->
            %% An unavailable caller ID is not a callback target. When the
            %% queue explicitly permits alternatives, collect a new number
            %% and retain the existing readback/confirmation/authorization
            %% barriers. Never offer confirmation of the invalid caller ID.
            State = Settings#{phase => 'collecting'
                             ,current_number => 'undefined'
                             ,digits => <<>>
                             ,retries => 0
                             ,deadline_ms => NowMs + maps:get(timeout_ms, Settings)
                             ,registration_emitted => 'false'
                             },
            {'ok', State, ['collect_alternate']};
        {{'error', _}, _} -> {'error', 'invalid_number'};
        {_, {'error', _}} -> {'error', 'invalid_config'}
    end;
new(_, _, _) -> {'error', 'invalid_config'}.

-spec event(term(), integer(), state()) -> {state(), [action()]}.
event(Event, NowMs, State) when is_integer(NowMs), is_map(State) ->
    Phase = maps:get(phase, State),
    case {terminal(Phase), Event, Phase} of
        {'true', _, _} -> terminal_event(Event, State);
        {'false', 'caller_hangup', _} -> reduce(Event, NowMs, State);
        {'false', _, 'announcing_success'} ->
            case NowMs >= maps:get(success_deadline_ms, State) of
                'true' -> finish_accepted(State, 'announcement_timeout');
                'false' -> reduce(Event, NowMs, State)
            end;
        {'false', _, _} ->
            case NowMs >= maps:get(deadline_ms, State) of
                'true' -> deadline_event(Event, State);
                'false' -> reduce(Event, NowMs, State)
            end
    end.

-spec status(state()) -> atom().
status(State) -> maps:get(phase, State).

%% The effectful callflow wrapper uses the reducer's absolute monotonic
%% deadline for every receive.  This prevents prompt retries or unrelated
%% call events from extending the configured menu window.
-spec remaining_ms(integer(), state()) -> non_neg_integer().
remaining_ms(NowMs, State=#{phase := 'announcing_success'}) when is_integer(NowMs) ->
    max(0, maps:get(success_deadline_ms, State) - NowMs);
remaining_ms(NowMs, State) when is_integer(NowMs) ->
    max(0, maps:get(deadline_ms, State) - NowMs).

reduce({'dtmf', Digit}, _NowMs, State=#{phase := 'menu'}) ->
    ConfirmKey = maps:get(confirm_key, State),
    AlternateKey = maps:get(alternate_key, State),
    AllowAlternate = maps:get(allow_alternate_number, State),
    case Digit of
        ConfirmKey ->
            request_registration(State, maps:get(current_number, State));
        AlternateKey when AllowAlternate =:= 'true' ->
            {State#{phase => 'collecting', digits => <<>>}, ['collect_alternate']};
        <<"*">> -> abort(State, 'caller_cancelled');
        _ -> retry(State, 'menu')
    end;
reduce({'dtmf', <<"#">>}, _NowMs, State=#{phase := 'collecting', digits := <<>>}) ->
    retry(State, 'collecting');
reduce({'dtmf', <<"#">>}, _NowMs, State=#{phase := 'collecting', digits := Digits}) ->
    {State#{phase => 'confirming_alternate'}
    ,[{'read_back_number', Digits}, {'prompt_confirm_alternate', maps:get(confirm_key, State)}]};
reduce({'dtmf', <<"*">>}, _NowMs, State=#{phase := 'collecting'}) ->
    abort(State, 'caller_cancelled');
reduce({'dtmf', <<Digit>>}, _NowMs, State=#{phase := 'collecting', digits := Digits})
  when Digit >= $0, Digit =< $9, byte_size(Digits) < ?MAX_DIGITS ->
    {State#{digits => <<Digits/binary, Digit>>}, []};
reduce({'dtmf', <<Digit>>}, _NowMs, State=#{phase := 'collecting', digits := Digits})
  when Digit >= $0, Digit =< $9, byte_size(Digits) >= ?MAX_DIGITS ->
    retry(State#{digits => <<>>}, 'collecting');
reduce({'dtmf', _}, _NowMs, State=#{phase := 'collecting'}) ->
    retry(State#{digits => <<>>}, 'collecting');
reduce({'dtmf', Digit}, _NowMs, State=#{phase := 'confirming_alternate', digits := Digits}) ->
    ConfirmKey = maps:get(confirm_key, State),
    case Digit of
        ConfirmKey -> request_registration(State, Digits);
        <<"*">> -> abort(State, 'caller_cancelled');
        _ -> retry(State, 'confirming_alternate')
    end;
reduce({'trusted_queue_ack', QueueId, CallId, RequestId, {'ok', CallbackId}}
      ,NowMs, State=#{phase := 'awaiting_ack', queue_id := QueueId
              ,original_call_id := CallId, request_id := RequestId})
  when is_binary(CallbackId) ->
    case valid_callback_id(CallbackId) of
        'true' ->
            {State#{phase => 'announcing_success', callback_id => CallbackId
                   ,success_deadline_ms => NowMs + maps:get(success_timeout_ms, State)}
            ,[{'handoff_to_callback', CallbackId}, {'play_success_announcement', CallbackId}]};
        'false' -> {State, []}
    end;
reduce({'trusted_queue_ack', QueueId, CallId, RequestId, {'error', _Reason}}
      ,_NowMs, State=#{phase := 'awaiting_ack', queue_id := QueueId
              ,original_call_id := CallId, request_id := RequestId}) ->
    abort(State, 'registration_failed');
reduce({'trusted_announcement_complete', QueueId, CallId, CallbackId}
      ,_NowMs, State=#{phase := 'announcing_success', queue_id := QueueId
              ,original_call_id := CallId, callback_id := CallbackId}) ->
    {State#{phase => 'complete'}, ['hangup']};
reduce({'trusted_announcement_failed', QueueId, CallId, CallbackId}
      ,_NowMs, State=#{phase := 'announcing_success', queue_id := QueueId
                     ,original_call_id := CallId, callback_id := CallbackId}) ->
    finish_accepted(State, 'announcement_failed');
reduce('caller_hangup', _NowMs, State=#{phase := 'awaiting_ack'}) ->
    abandon_dead(State, 'caller_hangup');
reduce('caller_hangup', _NowMs, State=#{phase := 'announcing_success'}) ->
    {State#{phase => 'complete'}, []};
reduce('caller_hangup', _NowMs, State) -> abandon_dead(State, 'caller_hangup');
reduce(_Event, _NowMs, State) -> {State, []}.

%% A late successful acknowledgement can arrive after the local deadline. The
%% original call remains in its live queue, and the newly materialized callback
%% is explicitly cancelled so one caller cannot occupy both paths.
terminal_event({'trusted_queue_ack', QueueId, CallId, RequestId, {'ok', CallbackId}}
              ,State=#{phase := Phase, queue_id := QueueId
                      ,original_call_id := CallId, request_id := RequestId
                      ,registration_emitted := 'true'})
  when Phase =:= 'aborted'; Phase =:= 'aborted_dead' ->
    case valid_callback_id(CallbackId) of
        'false' -> {State, []};
        'true' ->
            case maps:get(late_cancelled_callback_id, State, 'undefined') of
                CallbackId -> {State, []};
                _ -> {State#{late_cancelled_callback_id => CallbackId}, [{'cancel_callback', CallbackId}]}
            end
    end;
terminal_event(_, State) -> {State, []}.

deadline_event({'trusted_queue_ack', QueueId, CallId, RequestId, {'ok', CallbackId}}
              ,State=#{phase := 'awaiting_ack', queue_id := QueueId
                      ,original_call_id := CallId, request_id := RequestId})
  when is_binary(CallbackId) ->
    case valid_callback_id(CallbackId) of
        'false' -> abort(State, 'deadline');
        'true' ->
            {Aborted, Resume} = abort(State, 'deadline'),
            {Aborted#{late_cancelled_callback_id => CallbackId}
            ,Resume ++ [{'cancel_callback', CallbackId}]}
    end;
deadline_event(_Event, State) -> abort(State, 'deadline').

request_registration(State=#{registration_emitted := 'false', request_id := RequestId
                            ,queue_id := QueueId, original_call_id := CallId}, Number) ->
    {State#{phase => 'awaiting_ack', selected_number => Number
           ,registration_emitted => 'true'}
    ,[{'register_callback', QueueId, CallId, RequestId, Number}]}.

retry(State, ReturnPhase) ->
    Retries = maps:get(retries, State) + 1,
    case Retries >= maps:get(max_retries, State) of
        'true' -> abort(State#{retries => Retries}, 'retry_limit');
        'false' ->
            Remaining = maps:get(max_retries, State) - Retries,
            {State#{phase => ReturnPhase, retries => Retries}, [{'retry', Remaining}]}
    end.

abort(State, Reason) ->
    {State#{phase => 'aborted', abort_reason => Reason}
    ,[{'resume_live_queue', Reason}]}.

abandon_dead(State, Reason) ->
    {State#{phase => 'aborted_dead', abort_reason => Reason}, ['abandon_paused_queue']}.

finish_accepted(State=#{callback_id := CallbackId}, Reason) ->
    {State#{phase => 'complete', announcement_result => Reason}
    ,[{'end_original_leg', CallbackId, Reason}]}.

terminal('complete') -> 'true';
terminal('aborted') -> 'true';
terminal('aborted_dead') -> 'true';
terminal(_) -> 'false'.

config(Config) ->
    RequestId = maps:get(request_id, Config, 'undefined'),
    QueueId = maps:get(queue_id, Config, 'undefined'),
    CallId = maps:get(original_call_id, Config, 'undefined'),
    Confirm = maps:get(confirm_key, Config, <<"1">>),
    Alternate = maps:get(alternate_key, Config, <<"2">>),
    AllowAlternate = maps:get(allow_alternate_number, Config, 'false'),
    Retries = maps:get(max_retries, Config, ?DEFAULT_MAX_RETRIES),
    Timeout = maps:get(timeout_ms, Config, ?DEFAULT_TIMEOUT_MS),
    SuccessTimeout = maps:get(success_timeout_ms, Config, ?DEFAULT_SUCCESS_TIMEOUT_MS),
    case valid_identifier(RequestId, 512) andalso valid_identifier(QueueId, 128)
        andalso valid_identifier(CallId, 512) andalso valid_menu_key(Confirm)
        andalso valid_menu_key(Alternate) andalso Confirm =/= Alternate
        andalso is_boolean(AllowAlternate)
        andalso is_integer(Retries) andalso Retries >= 1 andalso Retries =< 5
        andalso is_integer(Timeout) andalso Timeout >= 1000 andalso Timeout =< ?MAX_TIMEOUT_MS
        andalso is_integer(SuccessTimeout) andalso SuccessTimeout >= 1000
        andalso SuccessTimeout =< ?MAX_SUCCESS_TIMEOUT_MS of
        'true' -> {'ok', #{request_id => RequestId
                          ,queue_id => QueueId
                          ,original_call_id => CallId
                          ,confirm_key => Confirm
                          ,alternate_key => Alternate
                          ,allow_alternate_number => AllowAlternate
                          ,max_retries => Retries
                          ,timeout_ms => Timeout
                          ,success_timeout_ms => SuccessTimeout}};
        'false' -> {'error', 'invalid_config'}
    end.

valid_identifier(Id, Max) when is_binary(Id), byte_size(Id) > 0, byte_size(Id) =< Max ->
    not has_control(Id);
valid_identifier(_, _) -> 'false'.

valid_menu_key(<<Digit>>) when Digit >= $0, Digit =< $9 -> 'true';
valid_menu_key(_) -> 'false'.

normalize_number(Number) when is_binary(Number), byte_size(Number) > 0 ->
    case Number of
        <<"+", Digits/binary>> -> normalize_digits(Digits, <<"+">>);
        Digits -> normalize_digits(Digits, <<>>)
    end;
normalize_number(_) -> {'error', 'invalid_number'}.

normalize_digits(Digits, Prefix)
  when byte_size(Digits) >= 1, byte_size(Digits) =< ?MAX_DIGITS ->
    case all_digits(Digits) of
        'true' -> {'ok', <<Prefix/binary, Digits/binary>>};
        'false' -> {'error', 'invalid_number'}
    end;
normalize_digits(_, _) -> {'error', 'invalid_number'}.

all_digits(<<>>) -> 'true';
all_digits(<<Digit, Rest/binary>>) when Digit >= $0, Digit =< $9 -> all_digits(Rest);
all_digits(_) -> 'false'.

valid_callback_id(<<"acdc-callback-", Hex:64/binary>>) -> all_lower_hex(Hex);
valid_callback_id(_) -> 'false'.

all_lower_hex(<<>>) -> 'true';
all_lower_hex(<<C, Rest/binary>>)
  when (C >= $0 andalso C =< $9) orelse (C >= $a andalso C =< $f) ->
    all_lower_hex(Rest);
all_lower_hex(_) -> 'false'.

has_control(<<>>) -> 'false';
has_control(<<Char, _/binary>>) when Char < 32; Char =:= 127 -> 'true';
has_control(<<_, Rest/binary>>) -> has_control(Rest).
