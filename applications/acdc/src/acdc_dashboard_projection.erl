%%% SPDX-License-Identifier: MPL-2.0
%%% Bounded, pure projection of actual ACDC call_stat records. No database,
%%% AMQP, HTTP, authorization or runtime activation occurs in this module.
%%% Caller must authorize account/queue scope and provide a bounded collector.
%%% Legacy call_id::queue_id identity is NOT a distinct queue visit identity.
-module(acdc_dashboard_projection).
-export([new/5, add/2, finish/2]).
-include("acdc_stats.hrl").
-define(MAX_QUEUES, 100).
-define(MAX_ROWS, 10000).
-define(MAX_WINDOW, 86400).
-record(projection, {account, queues, from, to, now, rows=0, latest=0, seen=#{}, counts=#{}}).

-spec new(binary(), [binary()], integer(), integer(), integer()) ->
    {ok, term()} | {error, atom()}.
new(Account, Queues, From, To, Now)
  when is_binary(Account), byte_size(Account) > 0, byte_size(Account) =< 128,
       is_integer(From), From > 0, is_integer(To), To > From,
       To-From =< ?MAX_WINDOW, is_integer(Now), Now >= To ->
    case bounded_ids(Queues, ?MAX_QUEUES, #{}) of
        {ok, Ids} when map_size(Ids) > 0 ->
            {ok, #projection{account=Account, queues=Ids, from=From, to=To, now=Now,
                             counts=maps:map(fun(_, _) -> empty_counts() end, Ids)}};
        _ -> {error, invalid_queue_scope}
    end;
new(_, _, _, _, _) -> {error, invalid_projection_scope}.

bounded_ids([], _, Acc) -> {ok, Acc};
bounded_ids([Id|Rest], Left, Acc)
  when Left > 0, is_binary(Id), byte_size(Id) > 0, byte_size(Id) =< 128 ->
    case maps:is_key(Id, Acc) of
        true -> {error, duplicate_queue};
        false -> bounded_ids(Rest, Left-1, maps:put(Id, true, Acc))
    end;
bounded_ids(_, _, _) -> {error, invalid_queue_scope}.

empty_counts() ->
    #{current_waiting => 0, current_handled => 0, max_current_wait_seconds => undefined,
      records_entered => 0, waiting_in_cohort => 0, handled_in_cohort => 0,
      processed_in_cohort => 0, abandoned_in_cohort => 0,
      answered_wait_sum => 0, answered_wait_count => 0,
      processed_talk_sum => 0, processed_talk_count => 0}.

%% Count input rows before deduplication: repeated identities cannot bypass the
%% bound. On error no partial state is returned as an apparently valid snapshot.
-spec add(term(), [term()]) -> {ok, term()} | {error, atom()}.
add(#projection{}=P, Rows) -> add_rows(P, Rows);
add(_, _) -> {error, invalid_projection}.

add_rows(P, []) -> {ok, P};
add_rows(#projection{rows=N}, [_|_]) when N >= ?MAX_ROWS -> {error, row_limit_exceeded};
add_rows(#projection{rows=N}=P, [Row|Rest]) ->
    case normalized(Row, P) of
        {ok, Id, Value} ->
            case maps:find(Id, P#projection.seen) of
                {ok, Value} -> add_rows(P#projection{rows=N+1}, Rest);
                {ok, _} -> {error, conflicting_observation};
                error ->
                    Next = accumulate(Value, P#projection{rows=N+1,
                                            latest=erlang:max(P#projection.latest, latest_time(Value)),
                                            seen=maps:put(Id, Value, P#projection.seen)}),
                    add_rows(Next, Rest)
            end;
        Error -> Error
    end;
add_rows(_, _) -> {error, invalid_rows}.

normalized(#call_stat{id=Id, call_id=Call, account_id=Account, queue_id=Queue,
                      status=Status, entered_timestamp=Entered,
                      handled_timestamp=Handled, processed_timestamp=Processed,
                      abandoned_timestamp=Abandoned},
           #projection{account=Account, queues=Queues, now=Now})
  when is_binary(Call), byte_size(Call) > 0, byte_size(Call) =< 256,
       is_binary(Queue), byte_size(Queue) > 0, byte_size(Queue) =< 128,
       is_integer(Entered), Entered > 0, Entered =< Now ->
    case maps:is_key(Queue, Queues) andalso Id =:= <<Call/binary, "::", Queue/binary>> of
        false -> {error, invalid_record_scope};
        true ->
            case valid_timeline(Status, Entered, Handled, Processed, Abandoned, Now) of
                true -> {ok, Id, {Queue, Status, Entered, Handled, Processed, Abandoned}};
                false -> {error, invalid_record_timeline}
            end
    end;
normalized(_, _) -> {error, invalid_record_scope}.

valid_timeline(<<"waiting">>, _, undefined, undefined, undefined, _) -> true;
valid_timeline(<<"handled">>, E, H, undefined, undefined, N) -> time_between(H, E, N);
valid_timeline(<<"processed">>, E, H, P, undefined, N) ->
    time_between(H, E, N) andalso time_between(P, H, N);
valid_timeline(<<"abandoned">>, E, undefined, undefined, A, N) -> time_between(A, E, N);
valid_timeline(_, _, _, _, _, _) -> false.

time_between(T, From, To) -> is_integer(T) andalso T >= From andalso T =< To.

latest_time({_, _, E, H, P, A}) -> lists:max([T || T <- [E, H, P, A], is_integer(T)]).

accumulate({Queue, Status, Entered, Handled, Processed, _},
           #projection{counts=All, from=From, to=To, now=Now}=P) ->
    Before = maps:get(Queue, All),
    Live = case Status of
               <<"waiting">> ->
                   Max = maps:get(max_current_wait_seconds, Before),
                   Wait = Now-Entered,
                   (inc(current_waiting, Before))#{max_current_wait_seconds =>
                       case Max of undefined -> Wait; _ -> erlang:max(Max, Wait) end};
               <<"handled">> -> inc(current_handled, Before);
               _ -> Before
           end,
    Counts = case Entered >= From andalso Entered < To of
                 false -> Live;
                 true -> cohort(Status, Entered, Handled, Processed, inc(records_entered, Live))
             end,
    P#projection{counts=maps:put(Queue, Counts, All)}.

cohort(<<"waiting">>, _, _, _, C) -> inc(waiting_in_cohort, C);
cohort(<<"abandoned">>, _, _, _, C) -> inc(abandoned_in_cohort, C);
cohort(<<"handled">>, E, H, _, C) -> answered(E, H, inc(handled_in_cohort, C));
cohort(<<"processed">>, E, H, P, C) ->
    Next = answered(E, H, inc(processed_in_cohort, C)),
    (inc(processed_talk_count, Next))#{processed_talk_sum => maps:get(processed_talk_sum, Next)+P-H}.

answered(E, H, C) ->
    (inc(answered_wait_count, C))#{answered_wait_sum => maps:get(answered_wait_sum, C)+H-E}.
inc(Key, C) -> maps:update_with(Key, fun(N) -> N+1 end, C).

%% Source exhausted is a coverage statement from the collector, not proof of
%% atomicity or completeness of historical visits. Incomplete collections retain
%% observed counts explicitly; complete-looking KPI values are withheld.
-spec finish(term(), map()) -> {ok, map()} | {error, atom()}.
finish(#projection{now=Now}=P,
       #{observation_started:=Start, observation_finished:=End, exhausted:=Exhausted}=Source)
  when map_size(Source) =:= 3, is_integer(Start), Start > 0,
       is_integer(End), End >= Start, End =< Now, End >= P#projection.latest,
       is_boolean(Exhausted) ->
    Queues = [present(Id, maps:get(Id, P#projection.counts), Exhausted)
              || Id <- lists:sort(maps:keys(P#projection.queues))],
    {ok, #{version => 1, account_id => P#projection.account,
           as_of => Now, window => #{from => P#projection.from, to => P#projection.to,
                                     predicate => entered_from_inclusive_to_exclusive},
           timestamp_unit => kazoo_gregorian_seconds,
           source => Source#{atomic_snapshot => false, input_rows => P#projection.rows,
                            unique_records => map_size(P#projection.seen), row_limit => ?MAX_ROWS},
           identity_semantics => call_queue_pair, distinct_visit_metrics_available => false,
           agent_eligibility_available => false, workforce_metrics_available => false,
           queues => Queues}};
finish(_, _) -> {error, invalid_source_observation}.

present(Id, C, Exhausted) ->
    Values = maps:with([current_waiting, current_handled, max_current_wait_seconds,
                       records_entered, waiting_in_cohort, handled_in_cohort,
                       processed_in_cohort, abandoned_in_cohort], C),
    Counts = Values#{average_answered_wait_seconds => average(answered_wait_sum, answered_wait_count, C),
                     average_processed_talk_seconds => average(processed_talk_sum, processed_talk_count, C)},
    #{queue_id => Id, source_exhausted => Exhausted, observed => Counts,
      metrics => case Exhausted of true -> Counts; false -> undefined end}.

average(Sum, Count, C) ->
    case maps:get(Count, C) of 0 -> undefined; N -> maps:get(Sum, C)/N end.
