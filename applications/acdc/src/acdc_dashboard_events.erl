%%% SPDX-License-Identifier: MPL-2.0
%%% Bounded, memory-only invalidation hints. Never a delivery/consistency proof.
%%% Every client MUST reconcile snapshots at least every 15 seconds, including
%%% when no hint arrives. Hash collisions, bulk removals, publisher restarts,
%%% configuration-delivery gaps and native AMQP drops are intentionally lossy.
-module(acdc_dashboard_events).
-behaviour(gen_server).
-export([start_link/0, changed/2, bulk_removed/1, diagnostics/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-include("acdc.hrl").
-define(TABLE, acdc_dashboard_events_pending).
-define(SLOTS, 1024).
-define(TICK_MS, 100).
-define(ERROR_MS, 1000).
-define(MAX_COUNTER, 1000000000).
%% {diagnostics, admitted, coalesced, dropped, attempts, unconfirmed,
%%               local_errors, bulk_operations, bulk_rows}
-define(COUNTERS, {diagnostics,0,0,0,0,0,0,0,0}).

-spec start_link() -> kz_types:startlink_ret().
start_link() -> gen_server:start_link({local,?MODULE},?MODULE,[],[]).

%% Producer-side operations are bounded ETS only: no messages, locks waiting on
%% the publisher, broker checkout, database work, retries, or per-event process.
-spec changed(any(), any()) -> ok | {error,invalid_scope | unavailable | overloaded}.
changed(A,Q) ->
    case hex(A) andalso hex(Q) of
        false -> {error,invalid_scope};
        true ->
            try admit(erlang:phash2({A,Q},?SLOTS),A,Q)
            catch error:badarg -> {error,unavailable} end
    end.

-spec admit(non_neg_integer(), binary(), binary()) -> ok | {error,overloaded}.
admit(Slot,A,Q) ->
    New={Slot,make_ref(),A,Q},
    case ets:insert_new(?TABLE,New) of
        true -> count(2,1), ok;
        false ->
            case ets:lookup(?TABLE,Slot) of
                [{Slot,_,A,Q}=Old] ->
                    %% Refresh the token, even for a coalesced same-queue mark:
                    %% an in-flight publisher may only delete its exact token.
                    case ets:select_replace(?TABLE,[{Old,[],[{const,New}]}]) of
                        1 -> count(3,1), ok;
                        0 -> dropped()
                    end;
                _ -> dropped()
            end
    end.

-spec dropped() -> {error,overloaded}.
dropped() -> count(4,1), {error,overloaded}.

%% select_delete may remove arbitrary scopes, including a queue's last row.
%% Do not scan/copy those rows or invent a wildcard/cross-tenant event. This gap
%% is explicit and covered by mandatory snapshot reconciliation, not hints.
-spec bulk_removed(any()) -> ok | {error,unavailable}.
bulk_removed(N) when is_integer(N),N>0 ->
    try count(8,1), count(9,erlang:min(N,?MAX_COUNTER)), ok
    catch error:badarg -> {error,unavailable} end;
bulk_removed(_) -> ok.

-spec diagnostics() -> map().
diagnostics() ->
    Base=#{delivery_confirmed=>false,reconciliation_required=>true,
           reconciliation_interval_ms=>15000,capacity=>?SLOTS,memory_only=>true},
    try
        [{diagnostics,Admitted,Coalesced,Dropped,Attempts,Unconfirmed,Errors,Bulk,Rows}]
            =ets:lookup(?TABLE,diagnostics),
        Base#{available=>true,pending_slots=>erlang:max(0,ets:info(?TABLE,size)-1),
              admitted=>Admitted,coalesced=>Coalesced,dropped=>Dropped,
              attempts=>Attempts,unconfirmed=>Unconfirmed,local_errors=>Errors,
              bulk_operations=>Bulk,bulk_rows=>Rows}
    catch _:_ -> Base#{available=>false} end.

-spec init([]) -> {ok,map()}.
init([]) ->
    _=ets:new(?TABLE,[named_table,public,ordered_set,{write_concurrency,true}]),
    true=ets:insert(?TABLE,?COUNTERS),
    {ok,schedule(#{cursor=>-1},?TICK_MS)}.

-spec handle_call(any(), any(), map()) -> {reply,any(),map()}.
handle_call(_,_,State) -> {reply,{error,unsupported},State}.
-spec handle_cast(any(), map()) -> {noreply,map()}.
handle_cast(_,State) -> {noreply,State}.
-spec handle_info(any(), map()) -> {noreply,map()}.
handle_info({timeout,Ref,publish_tick},#{timer:=Ref,cursor:=Cursor}=State) ->
    {Next,Delay}=pump(Cursor),
    %% Exactly one timer, installed after the one synchronous native call has
    %% returned. Producers never send a cast, even while AMQP blocks/fails.
    {noreply,schedule(State#{cursor=>Next},Delay)};
handle_info(_,State) -> {noreply,State}.
-spec terminate(any(), map()) -> ok.
terminate(_,#{timer:=Ref}) -> _=erlang:cancel_timer(Ref), ok.
-spec code_change(any(), map(), any()) -> {ok,map()}.
code_change(_,State,_) -> {ok,State}.

-spec schedule(map(), pos_integer()) -> map().
schedule(State,Ms) -> State#{timer=>erlang:start_timer(Ms,self(),publish_tick)}.
-spec pump(integer()) -> {integer(),pos_integer()}.
pump(Cursor) ->
    Slot=case ets:next(?TABLE,Cursor) of
             N when is_integer(N) -> N;
             _ -> ets:first(?TABLE)
         end,
    case is_integer(Slot) andalso ets:lookup(?TABLE,Slot) of
        [{Slot,_,A,Q}=Entry] ->
            count(5,1),
            case attempt(A,Q) of
                ok ->
                    %% Native 'ok' is unconfirmed and may have dropped data.
                    %% A concurrent refreshed token must survive this cleanup.
                    true=ets:delete_object(?TABLE,Entry),
                    count(6,1), {Slot,?TICK_MS};
                error -> count(7,1), {Slot,?ERROR_MS}
            end;
        _ -> {-1,?TICK_MS}
    end.

-spec attempt(binary(), binary()) -> ok | error.
attempt(A,Q) ->
    Payload=[{<<"Version">>,1},{<<"Account-ID">>,A},{<<"Queue-ID">>,Q}
             |kz_api:default_headers(?APP_NAME,?APP_VERSION)],
    try kz_amqp_worker:cast(Payload,fun kapi_acdc_dashboard_events:publish_changed/1) of
        ok -> ok;
        _ -> error
    catch _:_ -> error end.

-spec count(pos_integer(), non_neg_integer()) -> integer().
count(Pos,N) -> ets:update_counter(?TABLE,diagnostics,{Pos,N,?MAX_COUNTER,?MAX_COUNTER}).
-spec hex(any()) -> boolean().
hex(B) when is_binary(B),byte_size(B)=:=32 -> hex_bytes(B);
hex(_) -> false.
-spec hex_bytes(binary()) -> boolean().
hex_bytes(<<>>) -> true;
hex_bytes(<<C,R/binary>>) when C>=$0,C=<$9; C>=$a,C=<$f -> hex_bytes(R);
hex_bytes(_) -> false.
