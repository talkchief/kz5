%%% SPDX-License-Identifier: MPL-2.0
%%% Local, bounded ETS observation only. Caller authorizes account/queue scope.
%%% Fixing a table protects traversal, NOT an atomic snapshot or cluster view.
%%% Options: max_scan=1..10000, budget_ms=0..1000. Zero budget intentionally
%%% reads no source and returns incomplete/not_read, never complete zero metrics.
%%% Source diagnostics (including foreign-key scan counts and node identity) are
%%% INTERNAL. A future authorized public DTO must not expose them verbatim.
%%% Bounds are cooperative between ETS BIFs, not a hard scheduler/latency SLA.
%%% active_calls is a bounded INTERNAL observation, ordered by queue/entry/call,
%%% not queue position. Complete means this local traversal only, never atomic
%%% or cluster-complete. Its row cap does not truncate the overview projection.
-module(acdc_dashboard_collector).
-export([collect/6]).
-include("acdc_stats.hrl").
-define(MAX_SCAN, 10000).
-define(MAX_BUDGET_MS, 1000).
-define(MAX_TIMESTAMP, 999999999999).
-define(MAX_ACTIVE_CALLS, 200).

-spec collect(atom() | ets:tid(), binary(), [binary()], integer(), integer(), map()) ->
    {ok, map()} | {error, atom()}.
collect(Table, Account, Queues, From, To, Options) ->
    Start = gregorian_seconds(),
    %% Scope and options must be accepted before even resolving a table name.
    case {acdc_dashboard_projection:new(Account, Queues, From, To, Start), options(Options)} of
        {{ok, _}, {ok, Limit, Budget}} ->
            Deadline = erlang:monotonic_time(millisecond)+Budget,
            case expired(Deadline) of
                true -> project(Account, Queues, From, To, Start, [], 0, false,
                                deadline, not_read, Limit, Budget, Deadline);
                false -> collect_table(Table, Account, Queues, From, To, Start,
                                       Limit, Budget, Deadline)
            end;
        {{error, Why}, _} -> {error, Why};
        {_, {error, Why}} -> {error, Why}
    end.

options(Options) when is_map(Options), map_size(Options) =< 2 ->
    Limit = maps:get(max_scan, Options, ?MAX_SCAN),
    Budget = maps:get(budget_ms, Options, ?MAX_BUDGET_MS),
    case maps:keys(maps:without([max_scan, budget_ms], Options)) =:= [] andalso
         is_integer(Limit) andalso Limit > 0 andalso Limit =< ?MAX_SCAN andalso
         is_integer(Budget) andalso Budget >= 0 andalso Budget =< ?MAX_BUDGET_MS of
        true -> {ok, Limit, Budget};
        false -> {error, invalid_collector_options}
    end;
options(_) -> {error, invalid_collector_options}.

collect_table(Table, Account, Queues, From, To, Start, Limit, Budget, Deadline) ->
    Template = match_template(Account, Queues),
    try
        %% A named table may be deleted/recreated. Never re-resolve its name
        %% after this point: every read and cleanup addresses this exact tid.
        Tid = case is_atom(Table) of true -> ets:whereis(Table); false -> Table end,
        %% `undefined` is also a legal named-table atom. A failed resolution
        %% must not accidentally turn into a read of that unrelated table.
        case Tid of undefined -> throw({collector_error, source_unavailable}); _ -> ok end,
        case {ets:info(Tid, type), ets:info(Tid, keypos)} of
            {set, Pos} when Pos =:= #call_stat.id ->
                {Rows, Scanned, Exhausted, Reason} = fixed_scan(Tid, Template, Limit, Deadline),
                project(Account, Queues, From, To, Start, Rows, Scanned,
                        Exhausted, Reason, available, Limit, Budget, Deadline);
            {undefined, _} -> {error, source_unavailable};
            _ -> {error, unsupported_source_table}
        end
    catch
        error:badarg -> {error, source_unavailable};
        throw:{collector_error, Why} -> {error, Why}
    end.

fixed_scan(Tid, Template, Limit, Deadline) ->
    case expired(Deadline) of
        true -> {[], 0, false, deadline};
        false ->
            true = ets:safe_fixtable(Tid, true),
            try
                case expired(Deadline) of
                    true -> {[], 0, false, deadline};
                    false -> scan(Tid, ets:first(Tid), Template, Limit, Deadline, [], 0, false)
                end
            after
                %% Deletion destroys the fixation too; cleanup must not mask
                %% the original explicit source error. Release before folding.
                try ets:safe_fixtable(Tid, false) catch error:badarg -> ok end
            end
    end.

scan(_, '$end_of_table', _, _, Deadline, Rows, N, Changed) ->
    case {expired(Deadline), Changed} of
        {true, _} -> {Rows, N, false, deadline};
        {false, true} -> {Rows, N, false, concurrent_delete};
        {false, false} -> {Rows, N, true, exhausted}
    end;
scan(Tid, Key, Template, Limit, Deadline, Rows, N, Changed) ->
    case {expired(Deadline), N >= Limit} of
        {true, _} -> {Rows, N, false, deadline};
        {false, true} -> {Rows, N, false, scan_limit};
        {false, false} ->
            case small_binary(Key, 386) of
                false -> throw({collector_error, invalid_source_key});
                true ->
                    case select_row(Tid, Key, Template) of
                        skip -> scan_next(Tid, Key, Template, Limit, Deadline, Rows, N, Changed);
                        deleted -> scan_next(Tid, Key, Template, Limit, Deadline, Rows, N, true);
                        {row, Row} -> scan_next(Tid, Key, Template, Limit, Deadline, [Row|Rows], N, Changed)
                    end
            end
    end.

scan_next(Tid, Key, Template, Limit, Deadline, Rows, N, Changed) ->
    %% Every visited key counts, including foreign accounts and queues. The
    %% successor probe permits exact-limit exhaustion without selecting an
    %% extra record. No select continuation can scan hidden foreign rows.
    case expired(Deadline) of
        true -> {Rows, N+1, false, deadline};
        false -> scan(Tid, ets:next(Tid, Key), Template, Limit, Deadline, Rows, N+1, Changed)
    end.

match_template(Account, Queues) ->
    Head = #call_stat{id='_', account_id=Account, queue_id='$1', call_id='$2',
                      status='$3', entered_timestamp='$4', handled_timestamp='$5',
                      processed_timestamp='$6', abandoned_timestamp='$7', _='_'},
    QueueGuard = lists:foldl(fun(Q, Acc) -> {'orelse', {'=:=', '$1', {const, Q}}, Acc} end,
                            false, Queues),
    Small = [binary_guard('$2', 256), binary_guard('$3', 32),
             timestamp_guard('$4'), timestamp_guard('$5'), timestamp_guard('$6'), timestamp_guard('$7')],
    {Head, [QueueGuard|Small], QueueGuard}.

select_row(Tid, Key, {Template, Guards, QueueGuard}) ->
    Head = Template#call_stat{id=Key},
    %% The bound key is in the match head. Return only seven bounded scalar
    %% fields; never copy the whole record, caller PII, agent or misses list.
    Match = [{Head, Guards, [{{'$1', '$2', '$3', '$4', '$5', '$6', '$7'}}]},
             {Head, [QueueGuard], [invalid]},
             {#call_stat{id=Key, _='_'}, [], [skip]}],
    case ets:select(Tid, Match) of
        [{Queue, Call, Status, Entered, Handled, Processed, Abandoned}] ->
            {row, #call_stat{id=Key, account_id=Template#call_stat.account_id, queue_id=Queue, call_id=Call,
                             status=Status, entered_timestamp=Entered, handled_timestamp=Handled,
                             processed_timestamp=Processed, abandoned_timestamp=Abandoned}};
        [skip] -> skip;
        [invalid] -> throw({collector_error, invalid_source_record});
        [] ->
            case ets:member(Tid, Key) of
                false -> deleted;
                true -> throw({collector_error, invalid_source_record})
            end
    end.

binary_guard(Var, Max) -> {'andalso', {is_binary, Var},
                         {'andalso', {'>', {byte_size, Var}, 0}, {'=<', {byte_size, Var}, Max}}}.
timestamp_guard(Var) ->
    {'orelse', {'=:=', Var, undefined},
     {'andalso', {is_integer, Var}, {'andalso', {'>', Var, 0}, {'=<', Var, ?MAX_TIMESTAMP}}}}.
small_binary(Value, Max) -> is_binary(Value) andalso byte_size(Value) > 0 andalso byte_size(Value) =< Max.
expired(Deadline) -> erlang:monotonic_time(millisecond) >= Deadline.
gregorian_seconds() -> calendar:datetime_to_gregorian_seconds(calendar:universal_time()).

project(Account, Queues, From, To, Start, Rows, Scanned, Exhausted, Reason,
        Availability, Limit, Budget, Deadline) ->
    %% Capture as-of after scanning, not before: a valid transition inserted
    %% across a second boundary must not be rejected against the older start.
    %% Clock rollback/future source timestamps remain explicit projection errors.
    End = gregorian_seconds(),
    case acdc_dashboard_projection:new(Account, Queues, From, To, End) of
        {ok, P} ->
            case project_rows(P, Rows, Deadline, {0, gb_trees:empty()}) of
                {ok, Next, ProjectedAll, Active} ->
                    WithinBudget = not expired(Deadline),
                    Complete = Exhausted andalso ProjectedAll andalso WithinBudget,
                    FinalReason = case ProjectedAll andalso WithinBudget of
                                      true -> Reason; false -> deadline
                                  end,
                    case acdc_dashboard_projection:finish(Next, #{observation_started=>Start,
                             observation_finished=>End, exhausted=>Complete}) of
                        {ok, Result} ->
                            Source = maps:get(source, Result),
                            {ok, Result#{active_calls => active_calls(Active, Complete),
                                source := Source#{kind=>local_ets, node=>node(),
                                availability=>Availability, coverage=>local_table_only,
                                cluster_complete=>false, archive_coverage=>unknown,
                                scan_keys=>Scanned, scan_limit=>Limit, budget_ms=>Budget,
                                completion_reason=>FinalReason, projection_complete=>ProjectedAll}}};
                        Error -> Error
                    end;
                Error -> Error
            end;
        Error -> Error
    end.

project_rows(P, [], _, Active) -> {ok, P, true, Active};
project_rows(P, [Row|Rest], Deadline, Active) ->
    case expired(Deadline) of
        true -> {ok, P, false, Active};
        false ->
            case acdc_dashboard_projection:add(P, [Row]) of
                {ok, Next} -> project_rows(Next, Rest, Deadline, active_row(Row, Active));
                Error -> Error
            end
    end.

%% Only accumulate after the existing projection accepts identity and timeline.
%% This shares its fold, not another source scan. A bounded ordered tree keeps
%% the same first 200 identities regardless of ETS traversal order. The table
%% key and projection validation enforce one call/queue identity per record.
active_row(#call_stat{status=Status, queue_id=Queue, call_id=Call,
                      entered_timestamp=Entered, handled_timestamp=Handled}, {N, Tree})
  when Status =:= <<"waiting">>; Status =:= <<"handled">> ->
    Value = #{call_id=>Call, queue_id=>Queue, status=>Status,
              entered_timestamp=>Entered, handled_timestamp=>Handled},
    Added = gb_trees:insert({Queue, Entered, Call}, Value, Tree),
    Bounded = case gb_trees:size(Added) > ?MAX_ACTIVE_CALLS of
                  true -> {_, _, Smaller} = gb_trees:take_largest(Added), Smaller;
                  false -> Added
              end,
    {N+1, Bounded};
active_row(_, Active) -> Active.

active_calls({N, Tree}, SourceComplete) ->
    Truncated = N > ?MAX_ACTIVE_CALLS,
    #{rows=>gb_trees:values(Tree), limit=>?MAX_ACTIVE_CALLS, observed_count=>N,
      truncated=>Truncated, complete=>SourceComplete andalso not Truncated,
      order=>queue_id_entered_call_id, coverage=>local_table_only, atomic_snapshot=>false}.
