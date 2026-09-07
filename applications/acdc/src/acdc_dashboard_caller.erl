%%% SPDX-License-Identifier: MPL-2.0
%%% Explicit privacy-filtered dashboard identity. Never fall back to legacy
%%% caller_id_name/number: absence of this marker means unknown provenance.
%%% No datastore, logging, ETS mutation, provider or call-control operations.
-module(acdc_dashboard_caller).
-export([from_call/3, from_call/4, from_privacy/3, valid/1, normalize/1, from_event/1, upgrade_legacy/1]).
-include("acdc_stats.hrl").
-define(HEADER, <<"Dashboard-Caller-ID">>).
-define(LEGACY_CALL_STAT_SIZE, 18).

-spec from_call(kapps_call:call(), term(), term()) -> kz_json:object().
from_call(Call, Name, Number) ->
    try
        true = initialized(Call),
        from_privacy(kapps_call:custom_channel_vars(Call), Name, Number)
    catch _:_ -> unavailable() end.

-spec from_call(kapps_call:call(), kz_json:object(), term(), term()) -> kz_json:object().
from_call(Call, Original, Name, Number) ->
    try
        true = initialized(Call),
        true = container(Original),
        true = kz_json:get_value(<<"Call-ID">>,Original)=:=kapps_call:call_id_direct(Call),
        true = kz_json:get_value(<<"Account-ID">>,Original)=:=kapps_call:account_id(Call),
        CCVs = kapps_call:custom_channel_vars(Call),
        true = privacy_containers(CCVs), true = privacy_containers(Original),
        identity(Name,Number,[Original,CCVs])
    catch _:_ -> unavailable() end.

initialized(Call) ->
    kapps_call:is_call(Call) andalso
        is_binary(kapps_call:call_id_direct(Call)) andalso
        byte_size(kapps_call:call_id_direct(Call))>0 andalso
        byte_size(kapps_call:call_id_direct(Call))=<256 andalso
        is_binary(kapps_call:account_id(Call)) andalso byte_size(kapps_call:account_id(Call))=:=32.

-spec from_privacy(kz_json:object(), term(), term()) -> kz_json:object().
from_privacy(Privacy, Name, Number) ->
    try
        true = privacy_containers(Privacy),
        identity(Name,Number,[Privacy])
    catch _:_ -> unavailable() end.

identity(Name,Number,Sources) ->
    {SafeName, NameStatus} = field(Name,256,privacy(name,Sources)),
    {SafeNumber, NumberStatus} = field(Number,64,privacy(number,Sources)),
    object(SafeName,SafeNumber,NameStatus,NumberStatus).

%% kz_privacy itself uses first-defined precedence. Evaluate each recognized
%% representation separately so a false value cannot mask another hide flag.
%% No explicit evidence, duplicate containers or malformed flags fail closed.
privacy(Kind,Sources) ->
    Values=[V || J<-Sources, P<-paths(Kind), V<-[kz_json:get_value(P,J)], V=/=undefined],
    Decisions=[decision(Kind,V) || V<-Values],
    case {lists:member(true,Decisions),lists:member(unknown,Decisions),Decisions} of
        {true,_,_} -> true;
        {_,true,_} -> unknown;
        {_,_,[]} -> unknown;
        _ -> false
    end.
paths(Kind) ->
    {Short,Flag,Caller}=case Kind of
        name -> {<<"hide_name">>,<<"Privacy-Hide-Name">>,<<"Caller-Privacy-Hide-Name">>};
        number -> {<<"hide_number">>,<<"Privacy-Hide-Number">>,<<"Caller-Privacy-Hide-Number">>}
    end,
    Base=[[<<"caller_id_options">>,<<"outbound_privacy">>],[<<"privacy">>,Short],Flag,Caller,<<"privacy_mode">>],
    Base ++ [[<<"Custom-Channel-Vars">>|case P of B when is_binary(B)->[B]; _->P end] || P<-Base].
decision(Kind,V) ->
    case lists:member(V,[true,false,<<"true">>,<<"false">>,<<"yes">>,<<"no">>,<<"none">>,<<"sip">>,
                        <<"full">>,<<"kazoo">>,<<"name">>,<<"number">>,<<"hide_name">>,<<"hide_number">>]) of
        false -> unknown;
        true ->
            J=kz_json:from_list([{<<"privacy_mode">>,V}]),
            case Kind of name -> kz_privacy:should_hide_name(J); number -> kz_privacy:should_hide_number(J) end
    end.
privacy_containers(J) ->
    container(J) andalso lists:all(fun(P) ->
        case kz_json:get_value(P,J) of undefined -> true; Child -> container(Child) end
    end,[<<"privacy">>,<<"caller_id_options">>,<<"Custom-Channel-Vars">>,
         [<<"Custom-Channel-Vars">>,<<"privacy">>],[<<"Custom-Channel-Vars">>,<<"caller_id_options">>]]).
container({Props}) when is_list(Props), length(Props)=<256 ->
    Keys=[K || {K,_}<-Props,is_binary(K)],
    length(Keys)=:=length(Props) andalso length(lists:usort(Keys))=:=length(Keys);
container(_) -> false.

field(_, _, true) -> {null, <<"withheld">>};
field(_, _, unknown) -> {null, <<"unavailable">>};
field(Value, Max, false) ->
    case text(Value, Max) of
        true -> {Value, <<"available">>};
        false -> {null, <<"unavailable">>}
    end.

unavailable() -> object(null, null, <<"unavailable">>, <<"unavailable">>).
object(Name, Number, NameStatus, NumberStatus) ->
    kz_json:from_list([{<<"version">>,1},{<<"name">>,Name},{<<"number">>,Number},
        {<<"name_status">>,NameStatus},{<<"number_status">>,NumberStatus}]).

-spec valid(term()) -> boolean().
valid({[_,_,_,_,_]=Props}=J) ->
    try
        [<<"name">>,<<"name_status">>,<<"number">>,<<"number_status">>,<<"version">>] =
            lists:sort([K || {K,_} <- Props]),
        kz_json:get_value(<<"version">>,J)=:=1 andalso
            pair(kz_json:get_value(<<"name">>,J),kz_json:get_value(<<"name_status">>,J),256) andalso
            pair(kz_json:get_value(<<"number">>,J),kz_json:get_value(<<"number_status">>,J),64)
    catch _:_ -> false end;
valid(_) -> false.

pair(Value, <<"available">>, Max) -> text(Value, Max);
pair(null, <<"withheld">>, _) -> true;
pair(null, <<"unavailable">>, _) -> true;
pair(_,_,_) -> false.

text(B, Max) when is_binary(B), byte_size(B)>0, byte_size(B)=<Max ->
    try
        B = unicode:characters_to_binary(B, utf8, utf8),
        re:run(B, <<"[\\x00-\\x1f\\x7f-\\x9f\\x{202a}-\\x{202e}\\x{2066}-\\x{2069}]">>,
            [unicode,{capture,none}])=:=nomatch andalso
        re:run(B, <<"^\\s*$">>, [unicode,{capture,none}])=:=nomatch
    catch _:_ -> false end;
text(_,_) -> false.

-spec normalize(term()) -> tuple() | undefined.
normalize({1,Name,Number,NameStatus,NumberStatus}=Value) ->
    case stored_pair(Name,NameStatus,256) andalso stored_pair(Number,NumberStatus,64) of
        true -> Value;
        false -> undefined
    end;
normalize(Value) ->
    case valid(Value) of
        true -> {1,optional(kz_json:get_value(<<"name">>,Value)),
                   optional(kz_json:get_value(<<"number">>,Value)),
                   kz_json:get_value(<<"name_status">>,Value),kz_json:get_value(<<"number_status">>,Value)};
        false -> undefined
    end.
optional(null) -> undefined;
optional(Value) -> Value.
stored_pair(undefined, <<"withheld">>, _) -> true;
stored_pair(undefined, <<"unavailable">>, _) -> true;
stored_pair(Value, <<"available">>, Max) -> text(Value, Max);
stored_pair(_,_,_) -> false.

-spec from_event(kz_json:object()) -> tuple() | undefined.
from_event(Event) ->
    try
        Value = kz_json:get_value(?HEADER, Event),
        %% Only the JSON wire shape is accepted from broker input, not an
        %% internal tuple supplied through an unrelated Erlang call site.
        case valid(Value) of true -> normalize(Value); false -> undefined end
    catch _:_ -> undefined end.

%% Pure conversion only. Deployment must quiesce all old/new record readers
%% and writers and invoke this while holding actual ETS ownership. A worker
%% restart alone retains the old table via kazoo_etsmgr; no automatic hotload
%% or ETS-TRANSFER migration is claimed by this helper.
-spec upgrade_legacy(tuple()) -> {ok, tuple()} | {error, unsupported_call_stat_layout}.
upgrade_legacy(#call_stat{}=Stat) -> {ok,Stat};
upgrade_legacy(Stat) when is_tuple(Stat), tuple_size(Stat)=:=?LEGACY_CALL_STAT_SIZE,
                          element(1,Stat)=:=call_stat ->
    case record_info(size,call_stat) of
        19 -> {ok,erlang:append_element(Stat,undefined)};
        _ -> {error,unsupported_call_stat_layout}
    end;
upgrade_legacy(_) -> {error,unsupported_call_stat_layout}.
