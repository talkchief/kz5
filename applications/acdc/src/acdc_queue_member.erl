%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2026 Talkchief
%%% @doc Stable logical identity and ordering for ACDC queue members.
%%%
%%% The queue manager deliberately continues to store a list of kapps_call
%%% records.  These helpers keep the identity of a virtual callback member
%%% independent of the physical channel that currently represents it.
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%% @end
%%%-----------------------------------------------------------------------------
-module(acdc_queue_member).

-export([stamp/4
        ,restore/5
        ,restore_callback/8
        ,logical_id/1
        ,logical_member_id/1
        ,physical_id/1
        ,member_order_key/1
        ,registration_metadata/1
        ,ensure/2
        ,replace/6
        ,lookup/2
        ,position/2
        ,remove/2
        ]).

-include("acdc.hrl").

-define(LOGICAL_ID, <<"acdc_logical_member_id">>).
-define(ENQUEUED_AT, <<"acdc_enqueued_at">>).
-define(ENQUEUE_SEQUENCE, <<"acdc_enqueue_sequence">>).
-define(PRIORITY, <<"acdc_member_priority">>).
-define(CALLBACK_ID, <<"acdc_callback_id">>).
-define(CALLBACK_ATTEMPT, <<"acdc_callback_attempt">>).
-define(CALLBACK_ATTEMPT_ID, <<"acdc_callback_attempt_id">>).
-define(CALLBACK_LEASE_TOKEN, <<"acdc_callback_lease_token">>).

-define(MAX_SAFE_INTEGER, 16#1fffffffffffff).

-type member_calls() :: [kapps_call:call()].
-type order_key() :: {integer(), pos_integer(), non_neg_integer(), kz_term:ne_binary()}.
-type ensure_result() :: {'ok', member_calls(), pos_integer(), 'inserted' | 'existing'} |
                         {'error', 'missing_metadata' | 'identity_conflict'}.
-type replace_result() :: {'ok', member_calls(), pos_integer(), 'replaced' | 'duplicate'} |
                          {'error', 'not_found' | 'invalid_replacement' |
                                    'callback_conflict' | 'stale_attempt' |
                                    'attempt_conflict' | 'identity_conflict'}.

%% Incoming call JSON is not trusted to assign queue identity or order.  The
%% manager overwrites every field before the member is published to the shared
%% queue, making redelivery self-contained.
-spec stamp(kapps_call:call(), pos_integer(), non_neg_integer(), 0..255) ->
          kapps_call:call().
stamp(Call, EnqueuedAt, Sequence, Priority)
  when is_integer(EnqueuedAt), EnqueuedAt > 0,
       is_integer(Sequence), Sequence >= 0, Sequence =< ?MAX_SAFE_INTEGER,
       is_integer(Priority), Priority >= 0, Priority =< 255 ->
    CallId = physical_id(Call),
    Clean = kapps_call:kvs_erase([?LOGICAL_ID, ?ENQUEUED_AT, ?ENQUEUE_SEQUENCE,
                                  ?PRIORITY, ?CALLBACK_ID, ?CALLBACK_ATTEMPT,
                                  ?CALLBACK_ATTEMPT_ID, ?CALLBACK_LEASE_TOKEN], Call),
    kapps_call:kvs_store_proplist([{?LOGICAL_ID, CallId}
                                  ,{?ENQUEUED_AT, EnqueuedAt}
                                  ,{?ENQUEUE_SEQUENCE, Sequence}
                                  ,{?PRIORITY, Priority}
                                  ], Clean).

%% Restore identity/order only from a coordinator-validated durable callback
%% document. Unlike stamp/4, the logical ID may differ from the physical leg.
-spec restore(kapps_call:call(), kz_term:ne_binary(), pos_integer(), non_neg_integer(), 0..255) ->
          {'ok', kapps_call:call()} | {'error', 'invalid_metadata'}.
restore(Call, LogicalId, EnqueuedAt, Sequence, Priority)
  when is_binary(LogicalId), byte_size(LogicalId) > 0,
       is_integer(EnqueuedAt), EnqueuedAt > 0,
       is_integer(Sequence), Sequence >= 0, Sequence =< ?MAX_SAFE_INTEGER,
       is_integer(Priority), Priority >= 0, Priority =< 255 ->
    Clean = kapps_call:kvs_erase([?LOGICAL_ID, ?ENQUEUED_AT, ?ENQUEUE_SEQUENCE,
                                  ?PRIORITY, ?CALLBACK_ID, ?CALLBACK_ATTEMPT,
                                  ?CALLBACK_ATTEMPT_ID, ?CALLBACK_LEASE_TOKEN], Call),
    {'ok', kapps_call:kvs_store_proplist([{?LOGICAL_ID, LogicalId}
                                         ,{?ENQUEUED_AT, EnqueuedAt}
                                         ,{?ENQUEUE_SEQUENCE, Sequence}
                                         ,{?PRIORITY, Priority}], Clean)};
restore(_, _, _, _, _) -> {'error', 'invalid_metadata'}.

%% Reconstitute a persisted returned caller leg. Callback identity is accepted
%% only when the durable attempt ID is the physical call UUID.
-spec restore_callback(kapps_call:call(), kz_term:ne_binary(), pos_integer(),
                       non_neg_integer(), 0..255, kz_term:ne_binary(),
                       pos_integer(), kz_term:ne_binary()) ->
          {'ok', kapps_call:call()} | {'error', 'invalid_metadata'}.
restore_callback(Call, LogicalId, EnqueuedAt, Sequence, Priority,
                 CallbackId, Attempt, AttemptId)
  when is_integer(Attempt), Attempt > 0,
       is_binary(AttemptId), byte_size(AttemptId) > 0 ->
    case valid_callback_id(CallbackId)
        andalso physical_id(Call) =:= AttemptId
        andalso restore(Call, LogicalId, EnqueuedAt, Sequence, Priority) of
        {'ok', Restored} ->
            {'ok', kapps_call:kvs_store_proplist(
                     [{?CALLBACK_ID, CallbackId}
                     ,{?CALLBACK_ATTEMPT, Attempt}
                     ,{?CALLBACK_ATTEMPT_ID, AttemptId}
                     ], Restored)};
        _ -> {'error', 'invalid_metadata'}
    end;
restore_callback(_, _, _, _, _, _, _, _) -> {'error', 'invalid_metadata'}.

-spec logical_id(kapps_call:call()) -> kz_term:ne_binary().
logical_id(Call) ->
    kapps_call:kvs_fetch(?LOGICAL_ID, physical_id(Call), Call).

-spec logical_member_id(kapps_call:call()) -> kz_term:ne_binary().
logical_member_id(Call) -> logical_id(Call).

-spec physical_id(kapps_call:call()) -> kz_term:ne_binary().
physical_id(Call) -> kapps_call:call_id(Call).

%% This key is in service order: higher priority first, then the immutable
%% original enqueue time and sequence.  Logical ID is the deterministic final
%% tie-breaker across nodes.
-spec member_order_key(kapps_call:call()) -> order_key().
member_order_key(Call) ->
    {-kapps_call:kvs_fetch(?PRIORITY, 0, Call)
    ,kapps_call:kvs_fetch(?ENQUEUED_AT, 0, Call)
    ,kapps_call:kvs_fetch(?ENQUEUE_SEQUENCE, 0, Call)
    ,logical_id(Call)
    }.

-spec registration_metadata(kapps_call:call()) ->
          {'ok', kz_json:object()} | {'error', 'missing_metadata'}.
registration_metadata(Call) ->
    case metadata(Call) of
        {'ok', {EnqueuedAt, Sequence, Priority}} ->
            {'ok', kz_json:from_list([{<<"enqueued_at">>, EnqueuedAt}
                                    ,{<<"enqueue_sequence">>, Sequence}
                                    ,{<<"priority">>, Priority}
                                    ,{<<"language">>, callback_language(Call)}
                                    ])};
        'error' -> {'error', 'missing_metadata'}
    end.

%% Ensure is used after a shared-delivery redelivery or manager recovery.  It
%% never replaces a physical channel and never silently changes immutable
%% ordering metadata.
-spec ensure(kapps_call:call(), member_calls()) -> ensure_result().
ensure(Call, Calls) ->
    case metadata(Call) of
        'error' -> {'error', 'missing_metadata'};
        {'ok', _} -> ensure_valid(Call, Calls)
    end.

ensure_valid(Call, Calls) ->
    LogicalId = logical_id(Call),
    PhysicalId = physical_id(Call),
    case {lookup(LogicalId, Calls), physical_owner(PhysicalId, Calls)} of
        {'undefined', 'undefined'} ->
            Calls1 = sort_for_storage([Call | Calls]),
            {'ok', Calls1, position(LogicalId, Calls1), 'inserted'};
        {{Existing, Position}, LogicalId} ->
            case same_immutable_metadata(Call, Existing)
                andalso physical_id(Existing) =:= PhysicalId of
                'true' -> {'ok', Calls, Position, 'existing'};
                'false' -> {'error', 'identity_conflict'}
            end;
        _ -> {'error', 'identity_conflict'}
    end.

%% Replacement changes only the physical call and callback-attempt metadata.
%% The original logical identity and order are copied from the existing member.
%% AttemptId is the already-persisted caller-leg UUID, never a private lease.
-spec replace(kz_term:ne_binary(), kz_term:ne_binary(), pos_integer(),
              kz_term:ne_binary(), kapps_call:call(), member_calls()) -> replace_result().
replace(LogicalId, CallbackId, Attempt, AttemptId, NewCall, Calls)
  when is_binary(LogicalId), byte_size(LogicalId) > 0,
       is_binary(CallbackId), byte_size(CallbackId) > 0,
       is_integer(Attempt), Attempt > 0,
       is_binary(AttemptId), byte_size(AttemptId) > 0 ->
    case valid_callback_id(CallbackId)
        andalso physical_id(NewCall) =:= AttemptId of
        'false' -> {'error', 'invalid_replacement'};
        'true' -> replace_valid(LogicalId, CallbackId, Attempt, AttemptId, NewCall, Calls)
    end;
replace(_, _, _, _, _, _) -> {'error', 'invalid_replacement'}.

replace_valid(LogicalId, CallbackId, Attempt, AttemptId, NewCall, Calls) ->
    case lookup(LogicalId, Calls) of
        'undefined' -> {'error', 'not_found'};
        {Existing, Position} ->
            replace_existing(LogicalId, CallbackId, Attempt, AttemptId,
                             NewCall, Existing, Position, Calls)
    end.

replace_existing(LogicalId, CallbackId, Attempt, AttemptId,
                 NewCall, Existing, Position, Calls) ->
    ExistingCallback = kapps_call:kvs_fetch(?CALLBACK_ID, Existing),
    ExistingAttempt = kapps_call:kvs_fetch(?CALLBACK_ATTEMPT, 0, Existing),
    ExistingAttemptId = kapps_call:kvs_fetch(?CALLBACK_ATTEMPT_ID, Existing),
    case replacement_decision(CallbackId, Attempt, AttemptId,
                              physical_id(NewCall), ExistingCallback,
                              ExistingAttempt, ExistingAttemptId,
                              physical_id(Existing)) of
        'duplicate' -> {'ok', Calls, Position, 'duplicate'};
        'replace' ->
            case physical_owner(physical_id(NewCall), Calls) of
                'undefined' -> replace_at(LogicalId, CallbackId, Attempt, AttemptId,
                                          NewCall, Existing, Position, Calls);
                LogicalId -> replace_at(LogicalId, CallbackId, Attempt, AttemptId,
                                        NewCall, Existing, Position, Calls);
                _ -> {'error', 'identity_conflict'}
            end;
        Error -> {'error', Error}
    end.

replacement_decision(_CallbackId, _Attempt, AttemptId, PhysicalId,
                     'undefined', 0, 'undefined', _OldPhysicalId) ->
    case AttemptId =:= PhysicalId of
        'true' -> 'replace';
        'false' -> 'invalid_replacement'
    end;
replacement_decision(CallbackId, Attempt, AttemptId, PhysicalId,
                     CallbackId, Attempt, AttemptId, PhysicalId) -> 'duplicate';
replacement_decision(CallbackId, Attempt, _AttemptId, _PhysicalId,
                     CallbackId, ExistingAttempt, _ExistingAttemptId, _OldPhysicalId)
  when Attempt < ExistingAttempt -> 'stale_attempt';
replacement_decision(CallbackId, Attempt, _AttemptId, _PhysicalId,
                     CallbackId, ExistingAttempt, _ExistingAttemptId, _OldPhysicalId)
  when Attempt =:= ExistingAttempt -> 'attempt_conflict';
replacement_decision(CallbackId, Attempt, AttemptId, PhysicalId,
                     CallbackId, ExistingAttempt, _ExistingAttemptId, _OldPhysicalId)
  when Attempt > ExistingAttempt ->
    case AttemptId =:= PhysicalId of
        'true' -> 'replace';
        'false' -> 'invalid_replacement'
    end;
replacement_decision(_CallbackId, _Attempt, _AttemptId, _PhysicalId,
                     _ExistingCallback, _ExistingAttempt, _ExistingAttemptId,
                     _OldPhysicalId) -> 'callback_conflict'.

replace_at(LogicalId, CallbackId, Attempt, AttemptId,
           NewCall, Existing, Position, Calls) ->
    {EnqueuedAt, Sequence, Priority} = metadata_value(Existing),
    Replacement0 = kapps_call:kvs_erase([?LOGICAL_ID, ?ENQUEUED_AT,
                                          ?ENQUEUE_SEQUENCE, ?PRIORITY,
                                          ?CALLBACK_ID, ?CALLBACK_ATTEMPT,
                                          ?CALLBACK_ATTEMPT_ID,
                                          ?CALLBACK_LEASE_TOKEN], NewCall),
    Replacement = kapps_call:kvs_store_proplist(
                    [{?LOGICAL_ID, LogicalId}
                    ,{?ENQUEUED_AT, EnqueuedAt}
                    ,{?ENQUEUE_SEQUENCE, Sequence}
                    ,{?PRIORITY, Priority}
                    ,{?CALLBACK_ID, CallbackId}
                    ,{?CALLBACK_ATTEMPT, Attempt}
                    ,{?CALLBACK_ATTEMPT_ID, AttemptId}
                    ], Replacement0),
    Calls1 = [case logical_id(Call) of
                  LogicalId -> Replacement;
                  _ -> Call
              end || Call <- Calls],
    {'ok', Calls1, Position, 'replaced'}.

-spec lookup(kz_term:ne_binary(), member_calls()) ->
          'undefined' | {kapps_call:call(), pos_integer()}.
lookup(LogicalId, Calls) -> lookup(LogicalId, lists:reverse(Calls), 1).

lookup(_, [], _) -> 'undefined';
lookup(LogicalId, [Call | Calls], Position) ->
    case logical_id(Call) of
        LogicalId -> {Call, Position};
        _ -> lookup(LogicalId, Calls, Position + 1)
    end.

-spec position(kz_term:ne_binary(), member_calls()) -> kz_term:api_pos_integer().
position(LogicalId, Calls) ->
    case lookup(LogicalId, Calls) of
        'undefined' -> 'undefined';
        {_, Position} -> Position
    end.

-spec remove(kz_term:ne_binary(), member_calls()) -> member_calls().
remove(LogicalId, Calls) ->
    [Call || Call <- Calls, logical_id(Call) =/= LogicalId].

metadata(Call) ->
    EnqueuedAt = kapps_call:kvs_fetch(?ENQUEUED_AT, Call),
    Sequence = kapps_call:kvs_fetch(?ENQUEUE_SEQUENCE, Call),
    Priority = kapps_call:kvs_fetch(?PRIORITY, Call),
    case is_integer(EnqueuedAt) andalso EnqueuedAt > 0
        andalso is_integer(Sequence) andalso Sequence >= 0
        andalso Sequence =< ?MAX_SAFE_INTEGER
        andalso is_integer(Priority) andalso Priority >= 0 andalso Priority =< 255 of
        'true' -> {'ok', {EnqueuedAt, Sequence, Priority}};
        'false' -> 'error'
    end.

metadata_value(Call) ->
    {'ok', Value} = metadata(Call),
    Value.

same_immutable_metadata(Left, Right) ->
    logical_id(Left) =:= logical_id(Right)
        andalso metadata(Left) =:= metadata(Right).

physical_owner(PhysicalId, Calls) ->
    case [logical_id(Call) || Call <- Calls, physical_id(Call) =:= PhysicalId] of
        [] -> 'undefined';
        [LogicalId | _] -> LogicalId
    end.

sort_for_storage(Calls) ->
    %% current_member_calls is historically newest-last-in-service first;
    %% queue positions are calculated over lists:reverse/1.
    lists:reverse(lists:sort(fun(A, B) -> member_order_key(A) < member_order_key(B) end,
                             Calls)).

valid_callback_id(<<"acdc-callback-", Digest:64/binary>>) ->
    re:run(Digest, <<"^[0-9a-f]{64}$">>, [{'capture', 'none'}]) =:= 'match';
valid_callback_id(_) -> 'false'.

callback_language(Call) ->
    case kapps_call:language(Call) of
        Language when is_binary(Language), byte_size(Language) > 0 ->
            acdc_language:canonical(Language);
        _ -> <<"en-us">>
    end.
