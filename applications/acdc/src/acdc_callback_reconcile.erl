%%% SPDX-License-Identifier: MPL-2.0
%%% Adapter from fresh channel observations to inert callback recovery plans.
%%% This module never originates, bridges, acknowledges or mutates a record.
-module(acdc_callback_reconcile).

-export([plan/4, owner/1, owner/2, restore_call/2]).

-include("acdc.hrl").

-spec plan(kz_json:object(), non_neg_integer(), atom(), map()) ->
          {'ok', map(), map()} | {'error', 'invalid_input'}.
plan(Doc, Now, Owner, #{'complete' := 'true', 'channels' := Channels}=Evidence) ->
    case snapshot(Channels, Evidence) of
        {'error', _} -> wait('inconsistent_channel_snapshot');
        Snapshot ->
            %% The bridge shortcut must pass the same durable-document and
            %% owner validation as every ordinary recovery plan.
            case acdc_callback_recovery:plan(Doc, Now, Owner, Snapshot) of
                {'error', _}=Error -> Error;
                Fallback -> bridge_or_fallback(Doc, Now, Owner, Evidence, Fallback)
            end
    end;
plan(_Doc, _Now, _Owner, _Evidence) -> wait('incomplete_channel_snapshot').

bridge_or_fallback(Doc, Now, Owner, Evidence, Fallback) ->
    case recoverable_bridge(Doc, Evidence) of
        {'ok', Caller, Agent} ->
            Until = kz_json:get_integer_value([<<"pvt_lease">>, <<"until">>], Doc, 0),
            case Until =< Now orelse Owner =:= 'dead' orelse Owner =:= 'self' of
                'true' -> {'ok', #{'action' => 'prove_bridge', 'caller_call_id' => Caller
                                  ,'agent_call_id' => Agent}, #{'snapshot' => 'complete'}};
                'false' -> wait('live_owner_lease')
            end;
        'conflict' -> wait('conflicting_bridge_proof');
        'none' -> Fallback
    end.

snapshot([], _) -> {'error', 'empty_snapshot'};
snapshot(Channels, Evidence) when is_list(Channels) ->
    try
        Nodes = lists:usort(lists:append([maps:get('responders', C) || C <- Channels])),
        Ids = [maps:get('call_id', C) || C <- Channels],
        Valid = Nodes =/= [] andalso length(Ids) =:= length(lists:usort(Ids))
            andalso lists:all(fun(C) -> lists:sort(maps:get('responders', C)) =:= Nodes
                                        andalso lists:member(maps:get('state', C), ['active', 'terminated'])
                                        andalso (maps:get('state', C) =:= 'terminated'
                                                 orelse lists:member(maps:get('active_responder', C, 'undefined'), Nodes)) end, Channels),
        case Valid of
            'false' -> {'error', 'incomplete_snapshot'};
            'true' ->
                Responses = [#{'node' => Node, 'complete' => 'true'
                               ,'channels' => maps:from_list([{maps:get('call_id', C), node_state(Node, C)} || C <- Channels])}
                             || Node <- Nodes],
                #{'fresh' => 'true', 'expected_nodes' => Nodes, 'responses' => Responses
                 ,'originate' => maps:get('originate', Evidence, 'unknown'), 'bridge' => 'none'}
        end
    catch _:_ -> {'error', 'invalid_snapshot'} end;
snapshot(_, _) -> {'error', 'invalid_snapshot'}.

node_state(Node, #{'state' := 'active', 'active_responder' := Node}) -> 'active';
node_state(_, _) -> 'terminated'.

recoverable_bridge(Doc, #{'bridge' := #{'state' := 'bridged', 'call_ids' := Pair}})
  when is_list(Pair) ->
    Caller = kz_json:get_ne_binary_value(<<"pvt_caller_call_id">>, Doc),
    Agent = kz_json:get_ne_binary_value(<<"pvt_agent_call_id">>, Doc),
    case {kz_json:get_value(<<"status">>, Doc), length(Pair) =:= 2 andalso lists:member(Caller, Pair)} of
        {<<"connecting">>, 'false'} -> 'conflict';
        {<<"connecting">>, 'true'} ->
            [ObservedAgent] = Pair -- [Caller],
            case Agent =:= 'undefined' orelse Agent =:= ObservedAgent of
                'true' -> {'ok', Caller, ObservedAgent};
                'false' -> 'conflict'
            end;
        _ -> 'none'
    end;
recoverable_bridge(_, #{'bridge' := #{'state' := 'bridged'}}) -> 'conflict';
recoverable_bridge(_, #{'bridge' := #{'state' := 'unknown'}}) -> 'conflict';
recoverable_bridge(_, _) -> 'none'.

%% Only local liveness can be established without guessing about a partition.
%% PID parsing creates no atoms and cannot turn an unknown remote owner dead.
-spec owner(kz_json:object()) -> 'alive' | 'dead' | 'remote' | 'unknown'.
owner(Doc) -> owner(Doc, 'undefined').

%% `self' is recovery authority, not merely a liveness classification. Grant
%% it only when the coordinator proves possession of the exact durable token.
-spec owner(kz_json:object(), kz_term:api_ne_binary()) ->
          'self' | 'alive' | 'dead' | 'remote' | 'unknown'.
owner(Doc, ExpectedToken) ->
    Value = kz_json:get_ne_binary_value([<<"pvt_lease">>, <<"owner">>], Doc),
    StoredToken = kz_json:get_ne_binary_value([<<"pvt_lease">>, <<"token">>], Doc),
    Prefix = <<(atom_to_binary(node(), utf8))/binary, ":">>, Size = byte_size(Prefix),
    case Value of
        <<Prefix:Size/binary, PidText/binary>> ->
            try list_to_pid(binary_to_list(PidText)) of
                Pid when Pid =:= self(), is_binary(ExpectedToken),
                         byte_size(ExpectedToken) > 0, ExpectedToken =:= StoredToken -> 'self';
                Pid when Pid =:= self() -> 'alive';
                Pid -> case erlang:is_process_alive(Pid) of 'true' -> 'alive'; 'false' -> 'dead' end
            catch _:_ -> 'unknown' end;
        B when is_binary(B), byte_size(B) > 0 -> 'remote';
        _ -> 'unknown'
    end.

%% Rebuild a confirmed, already-existing caller. The persisted control queue
%% is never caller/HTTP input, and this function emits no channel commands.
-spec restore_call(kz_json:object(), kapps_call:call()) -> {'ok', kapps_call:call()} | {'error', 'invalid_call'}.
restore_call(Doc, OriginalCall) ->
    Caller = kz_json:get_ne_binary_value(<<"pvt_caller_call_id">>, Doc),
    Control = kz_json:get_ne_binary_value(<<"pvt_caller_control_queue">>, Doc),
    case kz_json:get_value(<<"pvt_type">>, Doc) =:= <<"acdc_callback">>
        andalso kz_doc:account_id(Doc) =:= kapps_call:account_id(OriginalCall)
        andalso kz_json:get_value(<<"original_call_id">>, Doc) =:= acdc_queue_member:logical_id(OriginalCall)
        andalso is_binary(Caller) andalso byte_size(Caller) > 0
        andalso is_binary(Control) andalso byte_size(Control) > 0 of
        'false' -> {'error', 'invalid_call'};
        'true' -> {'ok', kapps_call:set_control_queue(Control, kapps_call:set_call_id(Caller, OriginalCall))}
    end.

wait(Reason) -> {'ok', #{'action' => 'wait', 'reason' => Reason}, #{'snapshot' => 'unknown'}}.
