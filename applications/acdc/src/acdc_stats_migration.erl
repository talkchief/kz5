%%% SPDX-License-Identifier: MPL-2.0
%%% Owner-local retained ETS migration. This is NOT a reader/writer admission
%%% lock: the caller must exclude all other table operations until completion.
%%% No archive, deletion, broker, logging or service operations are performed.
%%% Bounds are cooperative between ETS/hash BIFs, not a scheduler latency SLA;
%%% an existing record (including its misses list) is preserved in full.
-module(acdc_stats_migration).
-export([start/2, step/1]).
-include("acdc_stats.hrl").

-spec start(ets:tid(), map()) -> {ok,map()} | {error,atom()}.
start(Tid, Options) ->
    case options(Options) of
        {error,_}=Error -> Error;
        {ok,Batch,Milliseconds,Maximum} ->
            case source(Tid) of
                ok ->
                    try
                        case ets:info(Tid,size) =< Maximum of
                            false -> {error,record_limit};
                            true -> {ok,#{tid=>Tid,owner=>self(),phase=>preflight,key=>ets:first(Tid),
                                batch=>Batch,maximum=>Maximum,
                                deadline=>erlang:monotonic_time(millisecond)+Milliseconds,
                                count=>0,digest=>0,converted=>0,current=>0}}
                        end
                    catch error:badarg -> {error,source_changed} end;
                Error -> Error
            end
    end.

-spec step(map()) -> {continue,map()} | {done,map()} | {error,atom()}.
step(#{tid:=Tid,owner:=Owner}=State) when Owner=:=self() ->
    case source(Tid) of
        ok ->
            try batch(State,maps:get(batch,State))
            catch
                throw:{migration_error,Why} -> {error,Why};
                error:badarg -> {error,source_changed};
                error:{badkey,_} -> {error,invalid_state}
            end;
        Error -> Error
    end;
step(#{owner:=_}) -> {error,wrong_owner};
step(_) -> {error,invalid_state}.

options(Options) when is_map(Options), map_size(Options)=<3 ->
    Batch=maps:get(batch_size,Options,100),
    Deadline=maps:get(deadline_ms,Options,30000),
    Maximum=maps:get(max_records,Options,100000),
    case maps:without([batch_size,deadline_ms,max_records],Options)=:=#{} andalso
         is_integer(Batch) andalso Batch>=1 andalso Batch=<256 andalso
         is_integer(Deadline) andalso Deadline>=1 andalso Deadline=<60000 andalso
         is_integer(Maximum) andalso Maximum>=1 andalso Maximum=<100000 of
        true -> {ok,Batch,Deadline,Maximum};
        false -> {error,invalid_options}
    end;
options(_) -> {error,invalid_options}.

source(Tid) when is_reference(Tid) ->
    try
        case {ets:info(Tid,owner),ets:info(Tid,type),ets:info(Tid,protection),ets:info(Tid,keypos)} of
            {undefined,_,_,_} -> {error,source_changed};
            {Owner,_,_,_} when Owner=/=self() -> {error,wrong_owner};
            {_,set,protected,Position} when Position=:=#call_stat.id -> ok;
            _ -> {error,unsupported_table}
        end
    catch error:badarg -> {error,source_changed} end;
source(_) -> {error,invalid_tid}.

batch(State, Remaining) ->
    check_deadline(State),
    case {maps:get(key,State),Remaining} of
        {'$end_of_table',_} -> finish_phase(State);
        {_,0} -> {continue,State};
        {Key,_} ->
            Count=maps:get(count,State),
            require(Count<maps:get(maximum,State),record_limit),
            Tid=maps:get(tid,State),
            Record=case ets:lookup(Tid,Key) of
                       [Value] -> Value;
                       _ -> throw({migration_error,source_changed})
                   end,
            Upgraded=case acdc_dashboard_caller:upgrade_legacy(Record) of
                         {ok,Value1} -> Value1;
                         {error,_} -> throw({migration_error,unsupported_layout})
                     end,
            %% Shape conversion must never change the ETS key.
            require(element(#call_stat.id,Upgraded)=:=Key,source_changed),
            Next=visit(maps:get(phase,State),Record,Upgraded,State),
            check_deadline(Next),
            batch(Next#{count:=Count+1,key:=ets:next(Tid,Key)},Remaining-1)
    end.

visit(preflight,_Record,Upgraded,State) -> hash(Upgraded,State);
visit(convert,Record,Upgraded,#{tid:=Tid,converted:=Converted,current:=Current}=State) ->
    check_deadline(State),
    case Record=:=Upgraded of
        true -> State#{current:=Current+1};
        false ->
            true=ets:insert(Tid,Upgraded),
            State#{converted:=Converted+1}
    end;
visit(verify,Record,Upgraded,State) ->
    require(Record=:=Upgraded,legacy_remaining),
    hash(Record,State).

hash(Record,#{digest:=Digest}=State) ->
    %% Order-independent, fixed-size commitment plus exact count. No caller
    %% data or per-record hashes are returned in the receipt or logged.
    <<Value:256>>=crypto:hash(sha256,term_to_binary(Record)),
    State#{digest:=Digest bxor Value}.

finish_phase(#{phase:=preflight,tid:=Tid,count:=Count,digest:=Digest}=State) ->
    require(ets:info(Tid,size)=:=Count,source_changed),
    {continue,State#{phase:=convert,key:=ets:first(Tid),count:=0,digest:=0,
                    expected_count=>Count,expected_digest=>Digest}};
finish_phase(#{phase:=convert,tid:=Tid,count:=Count,expected_count:=Expected}=State) ->
    require(Count=:=Expected andalso ets:info(Tid,size)=:=Expected,source_changed),
    {continue,State#{phase:=verify,key:=ets:first(Tid),count:=0,digest:=0}};
finish_phase(#{phase:=verify,tid:=Tid,count:=Count,expected_count:=Expected,
               digest:=Digest,expected_digest:=ExpectedDigest,
               converted:=Converted,current:=Current}) ->
    require(Count=:=Expected andalso ets:info(Tid,size)=:=Expected,source_changed),
    require(Digest=:=ExpectedDigest,content_changed),
    {done,#{version=>1,layout=>record_info(size,call_stat),records=>Count,
            converted=>Converted,already_current=>Current,verified=>true}}.

check_deadline(#{deadline:=Deadline}) ->
    require(erlang:monotonic_time(millisecond)<Deadline,deadline).
require(true,_) -> ok;
require(false,Why) -> throw({migration_error,Why}).
