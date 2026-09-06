%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2017, Voxter Communications
%%% @doc
%%% @author Daniel Finke
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(acdc_announcements).

%% API
-export([start_link/3, announcements_enabled/1]).
-export([init/3]).

-ifdef(TEST).
-export([get_config/1
        ,maybe_set_announcement_language/2
        ,position_prompts/3
        ,wait_time_prompts/4
        ,initial_delay_ms/1
        ,callback_offer_prompts/2
        ,resolve_callback_audio/2
        ,schedule_init/2
        ,schedule_due/2
        ,schedule_wait_ms/2
        ,schedule_advance/4
        ,announcement_event/3
        ,loop/1
        ,drain_announcement_events/1
        ]).
-endif.

-include("acdc.hrl").

-define(POSITION_LOOKUP_TIMEOUT_MS, 500).
-define(MAX_PRE_PLAYBACK_EVENTS, 256).
-ifdef(TEST).
-define(PLAYBACK_WAIT_TIMEOUT_MS, 500).
-else.
-define(PLAYBACK_WAIT_TIMEOUT_MS, 120000).
-endif.

-define(DEFAULT_ANNOUNCEMENTS_MEDIA, [{<<"you_are_at_position">>, <<"queue-you_are_at_position">>}
                                     ,{<<"in_the_queue">>, <<"queue-in_the_queue">>}
                                     ,{<<"increase_in_call_volume">>, <<"queue-increase_in_call_volume">>}
                                     ,{<<"the_estimated_wait_time_is">>, <<"queue-the_estimated_wait_time_is">>}
                                     ]).

%%%=============================================================================
%%% API functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Starts the announcements process
%% @end
%%------------------------------------------------------------------------------
-spec start_link(pid(), kapps_call:call(), kz_term:proplist()) -> kz_types:startlink_ret().
start_link(Manager, Call, Props) ->
    {'ok', kz_process:spawn_link(fun ?MODULE:init/3, [Manager, Call, Props])}.

%%------------------------------------------------------------------------------
%% @doc Initializes the announcements process
%% @end
%%------------------------------------------------------------------------------
-spec init(pid(), kapps_call:call(), kz_term:proplist()) -> 'no_return'.
init(Manager, Call, Props) ->
    Config = get_config(Props),
    AnnouncementCall = maybe_set_announcement_language(Call, Config),
    kapps_call:put_callid(AnnouncementCall),
    Started = monotonic_ms(),
    State = init_state(Manager, AnnouncementCall, Config, Started),
    %% Pooled event delivery registers this process only; gproc removes the
    %% registration if the per-call worker is terminated by its supervisor.
    CallId = kapps_call:call_id(AnnouncementCall),
    'ok' = kz_events:bind_call_id(CallId),
    try
        ResolvedConfig = resolve_callback_audio(Config, AnnouncementCall),
        %% Media verification must not restart the first-offer clocks or leave
        %% manager death unmonitored while datastore reads are in progress.
        loop(State#{config := ResolvedConfig,
                    schedule := schedule_init(ResolvedConfig, Started)})
    after kz_events:unbind_call_id(CallId)
    end.

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Load config from props into map
%% @end
%%------------------------------------------------------------------------------
-spec get_config(kz_term:proplist() | kz_json:object()) -> map().
get_config(Props0) ->
    Props = normalize_announcements_props(Props0),
    Callback = normalize_announcements_props(props:get_value(<<"callback">>, Props, [])),
    Offer = normalize_announcements_props(props:get_value(<<"announcement">>, Callback, [])),
    #{position_announcements_enabled => props:get_is_true(<<"position_announcements_enabled">>, Props, 'false')
     ,wait_time_announcements_enabled => props:get_is_true(<<"wait_time_announcements_enabled">>, Props, 'false')
     ,announcements_interval => max(15, props:get_integer_value(<<"interval">>, Props, 30))
     ,initial_delay => max(1, min(3600, props:get_integer_value(<<"initial_delay">>, Props, 30)))
     ,announcement_language => props:get_ne_binary_value(<<"language">>, Props)
     ,announcements_media => announcements_media(Props)
     ,callback_announcements_enabled => props:get_is_true(<<"enabled">>, Callback, 'false')
         andalso props:get_is_true(<<"enabled">>, Offer, 'true')
     ,callback_initial_delay => bounded_seconds(<<"initial_delay">>, Offer, 30, 1)
     ,callback_interval => bounded_seconds(<<"interval">>, Offer, 60, 15)
     ,callback_entry_key => props:get_ne_binary_value(<<"entry_key">>, Callback, <<"6">>)
     ,callback_allow_alternate => props:get_is_true(<<"allow_alternate_number">>, Callback, 'false')
     ,callback_media => normalize_announcements_props(props:get_value(<<"media">>, Callback, []))
     }.

-spec bounded_seconds(binary(), kz_term:proplist(), pos_integer(), pos_integer()) -> pos_integer().
bounded_seconds(Key, Props, Default, Minimum) ->
    max(Minimum, min(3600, props:get_integer_value(Key, Props, Default))).

-spec announcements_enabled(kz_term:proplist() | kz_json:object()) -> boolean().
announcements_enabled(Props) ->
    Config = get_config(Props),
    maps:get(position_announcements_enabled, Config)
        orelse maps:get(wait_time_announcements_enabled, Config)
        orelse maps:get(callback_announcements_enabled, Config).

-spec initial_delay_ms(map()) -> pos_integer().
initial_delay_ms(#{initial_delay := Seconds}) -> Seconds * ?MILLISECONDS_IN_SECOND.

%%------------------------------------------------------------------------------
%% @doc Normalize either the queue manager's recursive proplist or a raw JSON
%% object. Treat malformed values as an empty configuration so defaults apply.
%% @end
%%------------------------------------------------------------------------------
-spec normalize_announcements_props(any()) -> kz_term:proplist().
normalize_announcements_props(Props) when is_list(Props) -> Props;
normalize_announcements_props(JObj) ->
    case kz_json:is_json_object(JObj) of
        'true' -> kz_json:recursive_to_proplist(JObj);
        'false' -> []
    end.

%%------------------------------------------------------------------------------
%% @doc Get media file configuration from props
%% @end
%%------------------------------------------------------------------------------
-spec announcements_media(kz_term:proplist()) -> kz_term:proplist().
announcements_media(Props) ->
    Media = normalize_announcements_props(props:get_value(<<"media">>, Props, [])),
    [{Name, props:get_ne_binary_value(Name, Media, Default)}
     || {Name, Default} <- ?DEFAULT_ANNOUNCEMENTS_MEDIA
    ].

%%------------------------------------------------------------------------------
%% @doc Apply an optional queue-specific language to the announcement call.
%% kapps_call_command uses the call language for say macros, so this keeps the
%% numeric queue position and prompt files in the same language.
%% @end
%%------------------------------------------------------------------------------
-spec maybe_set_announcement_language(kapps_call:call(), map()) -> kapps_call:call().
maybe_set_announcement_language(Call, #{announcement_language := 'undefined'}) -> Call;
maybe_set_announcement_language(Call, #{announcement_language := Language}) ->
    kapps_call:set_language(acdc_language:canonical(Language), Call).

%%------------------------------------------------------------------------------
%% @doc Initialize state for the announcements process
%% @end
%%------------------------------------------------------------------------------
-spec init_state(pid(), kapps_call:call(), map(), integer()) -> map().
init_state(Manager, Call, Config, Started) ->
    #{manager => Manager
     ,manager_monitor => erlang:monitor('process', Manager)
     ,call => Call
     ,config => Config
     ,last_average_wait_time => 'undefined'
     ,schedule => schedule_init(Config, Started)
     ,pending_playback => 'undefined'
     }.

%%------------------------------------------------------------------------------
%% @doc Loop entry point
%% @end
%%------------------------------------------------------------------------------
-spec loop(map()) -> 'no_return'.
loop(State) ->
    %% A receive with after 0 still consumes matching queued messages first.
    %% Service an elapsed deadline explicitly, even when call events continue
    %% arriving. In particular, stale events must not postpone fail-quiet
    %% cleanup after a lost playback completion.
    case next_wait_ms(State) of
        0 -> loop(emit_announcements(State));
        Wait -> wait_for_announcement_event(State, Wait)
    end.

-spec wait_for_announcement_event(map(), timeout()) -> 'no_return'.
wait_for_announcement_event(#{manager_monitor := Monitor}=State, Wait) ->
    receive
        {'DOWN', Monitor, 'process', _, _} -> exit('normal');
        {'kapi', {_, _, JObj}} -> loop(handle_announcement_event(JObj, State));
        _Other -> loop(State)
    after Wait ->
        loop(emit_announcements(State))
    end.

-spec next_wait_ms(map()) -> timeout().
next_wait_ms(#{pending_playback := {_, Deadline}}) -> max(0, Deadline - monotonic_ms());
next_wait_ms(#{schedule := Schedule}) -> schedule_wait_ms(Schedule, monotonic_ms()).

-spec emit_announcements(map()) -> map().
emit_announcements(#{pending_playback := {_, _}}) ->
    %% Never add another playlist if completion was lost or media is stalled.
    %% Fail quiet, without hanging up the caller or flushing a new owner's audio.
    lager:warning("queue announcements stopped after playback completion timeout"),
    exit('normal');
emit_announcements(#{schedule := Schedule}=State) ->
    State0 = drain_announcement_events(State),
    Due = schedule_due(Schedule, monotonic_ms()),
    {PositionPrompts, State1} = maybe_announce_position(Due, State0),
    %% Stats lookup may make the callback deadline due; combine it once.
    Due1 = lists:usort(Due ++ schedule_due(Schedule, monotonic_ms())),
    CallbackPrompts = maybe_announce_callback(Due1, State1),
    State2 = drain_announcement_events(State1),
    Playback = maybe_play_announcements(PositionPrompts ++ CallbackPrompts, maps:get(call, State2)),
    Pending = case Playback of
                  'ok' -> 'undefined';
                  Noop when is_binary(Noop), byte_size(Noop) > 0 ->
                      {Noop, monotonic_ms() + ?PLAYBACK_WAIT_TIMEOUT_MS};
                  _ -> exit('normal')
              end,
    EmittedDue = case lists:member('callback', Due1) of
                     'true' -> lists:usort(['callback' | Due]);
                     'false' -> Due
                 end,
    Next = schedule_advance(Schedule, EmittedDue, maps:get(config, State2), monotonic_ms()),
    State2#{schedule := Next, pending_playback := Pending}.

-spec drain_announcement_events(map()) -> map().
drain_announcement_events(State) ->
    drain_announcement_events(State, ?MAX_PRE_PLAYBACK_EVENTS).

-spec drain_announcement_events(map(), non_neg_integer()) -> map().
drain_announcement_events(#{manager_monitor := Monitor}=State, 0) ->
    receive
        {'DOWN', Monitor, 'process', _, _} -> exit('normal');
        {'kapi', {_, _, _}} ->
            %% Do not play past an unchecked bridge/usurp/hangup buried in a
            %% backlog. Stop only this temporary announcement worker, without
            %% flushing media, hanging up the caller or restarting the worker.
            lager:warning("queue announcements stopped after call event backlog limit"),
            exit('normal')
    after 0 -> State
    end;
drain_announcement_events(#{manager_monitor := Monitor}=State, Remaining) ->
    receive
        {'DOWN', Monitor, 'process', _, _} -> exit('normal');
        {'kapi', {_, _, JObj}} ->
            drain_announcement_events(handle_announcement_event(JObj, State), Remaining - 1)
    after 0 -> State
    end.

-spec handle_announcement_event(kz_json:object(), map()) -> map().
handle_announcement_event(JObj, #{call := Call, pending_playback := Pending}=State) ->
    case announcement_event(JObj, Call, Pending) of
        'stop' -> exit('normal');
        'complete' -> State#{pending_playback := 'undefined'};
        'ignore' -> State
    end.

-spec announcement_event(kz_json:object(), kapps_call:call(), any()) -> 'stop' | 'complete' | 'ignore'.
announcement_event(JObj, Call, Pending) ->
    Account = kz_json:get_ne_binary_value(<<"Account-ID">>, JObj,
                  kz_json:get_ne_binary_value([<<"Custom-Channel-Vars">>, <<"Account-ID">>], JObj)),
    %% Some noop events omit account metadata. The exact call binding and
    %% unpredictable command ID still correlate them; conflicting metadata fails.
    Scoped = kz_call_event:call_id(JObj) =:= kapps_call:call_id(Call)
        andalso (Account =:= 'undefined' orelse Account =:= kapps_call:account_id(Call)),
    case {Scoped, kz_api:event_type(JObj), Pending} of
        {'true', {<<"call_event">>, Name}, _}
          when Name =:= <<"CHANNEL_DESTROY">>; Name =:= <<"CHANNEL_DISCONNECTED">>;
               Name =:= <<"CHANNEL_BRIDGE">> -> 'stop';
        {'true', {<<"call_event">>, <<"usurp_control">>}, _} ->
            case kz_json:get_ne_binary_value(<<"Fetch-ID">>, JObj)
                =:= kapps_call:custom_channel_var(<<"Fetch-ID">>, Call) of
                'true' -> 'ignore'; 'false' -> 'stop'
            end;
        {'true', {<<"call_event">>, <<"CHANNEL_EXECUTE_COMPLETE">>}, {Noop, _}} ->
            case kz_call_event:application_name(JObj) =:= <<"noop">>
                andalso kz_call_event:application_response(JObj) =:= Noop of
                'true' -> 'complete'; 'false' -> 'ignore'
            end;
        _ -> 'ignore'
    end.

-spec monotonic_ms() -> integer().
monotonic_ms() -> erlang:monotonic_time('millisecond').

%% Pure monotonic scheduler. Disabled clocks use infinity. A delayed wakeup
%% emits once and schedules from completion, never replays missed intervals.
-spec schedule_init(map(), integer()) -> map().
schedule_init(Config, Now) ->
    PositionEnabled = maps:get(position_announcements_enabled, Config)
        orelse maps:get(wait_time_announcements_enabled, Config),
    #{position => first_deadline(PositionEnabled, Now, initial_delay_ms(Config))
     ,callback => first_deadline(maps:get(callback_announcements_enabled, Config), Now,
                                 maps:get(callback_initial_delay, Config) * ?MILLISECONDS_IN_SECOND)}.

-spec first_deadline(boolean(), integer(), pos_integer()) -> integer() | 'infinity'.
first_deadline('false', _, _) -> 'infinity';
first_deadline('true', Now, DelayMs) -> Now + DelayMs.

-spec schedule_due(map(), integer()) -> list().
schedule_due(Schedule, Now) ->
    [Kind || Kind <- ['position', 'callback'],
             is_integer(maps:get(Kind, Schedule)), maps:get(Kind, Schedule) =< Now].

-spec schedule_wait_ms(map(), integer()) -> non_neg_integer() | 'infinity'.
schedule_wait_ms(Schedule, Now) ->
    case [Deadline || Deadline <- maps:values(Schedule), is_integer(Deadline)] of
        [] -> 'infinity';
        Deadlines -> max(0, lists:min(Deadlines) - Now)
    end.

-spec schedule_advance(map(), list(), map(), integer()) -> map().
schedule_advance(Schedule, Due, Config, Now) ->
    lists:foldl(fun(Kind, Acc) ->
                        Interval = case Kind of
                                       'position' -> maps:get(announcements_interval, Config);
                                       'callback' -> maps:get(callback_interval, Config)
                                   end,
                        Acc#{Kind := Now + Interval * ?MILLISECONDS_IN_SECOND}
                end, Schedule, Due).

%%------------------------------------------------------------------------------
%% @doc Conditionally add position announcements prompts to playlist
%% @end
%%------------------------------------------------------------------------------
-spec maybe_announce_position(list(), map()) -> {list(), map()}.
maybe_announce_position(Due, State) ->
    case lists:member('position', Due) of
        'false' -> {[], State};
        'true' -> maybe_announce_position(State)
    end.

-spec maybe_announce_position(map()) -> {list(), map()}.
maybe_announce_position(#{config := #{position_announcements_enabled := 'false'}}=State) ->
    maybe_announce_wait_time([], State);
maybe_announce_position(#{manager := Manager
                         ,call := Call
                         ,config := Config
                         }=State) ->
    Language = kapps_call:language(Call),
    Position = try gen_listener:call(Manager, {'queue_position', kapps_call:call_id(Call)},
                                    ?POSITION_LOOKUP_TIMEOUT_MS)
               catch exit:_ -> 'undefined'
               end,
    Prompts = position_prompts(Position, Language, Config),
    maybe_announce_wait_time(Prompts, State).

%%------------------------------------------------------------------------------
%% @doc Build a position playlist only for a valid queue position. A call can
%% disappear from the manager between checks; never speak "undefined".
%% @end
%%------------------------------------------------------------------------------
-spec position_prompts(kz_term:api_pos_integer(), binary(), map()) ->
          kapps_call_command:audio_macro_prompts().
position_prompts(Position, Language, Config) when is_integer(Position), Position > 0 ->
    Prefix = announcements_media_file(<<"you_are_at_position">>, Config),
    Suffix = announcements_media_file(<<"in_the_queue">>, Config),
    Number = acdc_language:number_prompts(Position, Language),
    case {acdc_language:bundled(Language), Prefix, Suffix, Number} of
        {_, _, _, []} -> [];
        {'true', <<"queue-you_are_at_position">>, <<"queue-in_the_queue">>, _} ->
            %% A separate installed prompt avoids replacing existing system
            %% audio or changing explicitly customized/localized playlists.
            [{'prompt', <<"acdc-queue-your-current-position-is">>, acdc_language:canonical(Language), <<"A">>}
             | Number];
        _ ->
            [{'prompt', localized_default(Prefix, Language, Config), Language, <<"A">>}]
                ++ Number ++ [{'prompt', localized_default(Suffix, Language, Config), Language, <<"A">>}]
    end;
position_prompts(_, _, _) -> [].

%%------------------------------------------------------------------------------
%% @doc Conditionally add wait time announcements prompts to playlist
%% @end
%%------------------------------------------------------------------------------
-spec maybe_announce_wait_time(kapps_call_command:audio_macro_prompts(), map()) -> {list(), map()}.
maybe_announce_wait_time(PromptAcc, #{config := #{wait_time_announcements_enabled := 'false'}}=State) ->
    {PromptAcc, State};
maybe_announce_wait_time(PromptAcc, #{call := Call
                                     ,config := Config
                                     ,last_average_wait_time := LastAverageWaitTime
                                     }=State) ->
    Language = kapps_call:language(Call),
    AverageWaitTime = get_average_wait_time(Call),
    {WaitPrompts, NewLastAverageWaitTime} =
        wait_time_prompts(AverageWaitTime, LastAverageWaitTime, Language, Config),
    {PromptAcc ++ WaitPrompts, State#{last_average_wait_time := NewLastAverageWaitTime}}.

%%------------------------------------------------------------------------------
%% @doc Build wait-time prompts only when stats returned a non-negative number.
%% Erlang term ordering makes the atom 'undefined' greater than every number;
%% guarding here prevents an unavailable statistic from becoming "at least one
%% hour" and preserves the last valid sample.
%% @end
%%------------------------------------------------------------------------------
-spec wait_time_prompts(kz_term:api_non_neg_integer(), kz_term:api_non_neg_integer(),
                        binary(), map()) ->
          {kapps_call_command:audio_macro_prompts(), kz_term:api_non_neg_integer()}.
wait_time_prompts(AverageWaitTime, LastAverageWaitTime, Language, Config)
  when is_integer(AverageWaitTime), AverageWaitTime >= 0 ->
    IncreasePrompt =
        case is_integer(LastAverageWaitTime) andalso AverageWaitTime > LastAverageWaitTime of
            'true' ->
                [{'prompt', localized_default(announcements_media_file(<<"increase_in_call_volume">>, Config), Language, Config), Language, <<"A">>}];
            'false' ->
                []
        end,
    {IncreasePrompt ++
         [{'prompt', localized_default(announcements_media_file(<<"the_estimated_wait_time_is">>, Config), Language, Config), Language, <<"A">>}
         ,time_prompt(AverageWaitTime, Language)
         ],
     AverageWaitTime};
wait_time_prompts(_, LastAverageWaitTime, _, _) ->
    {[], LastAverageWaitTime}.

%%------------------------------------------------------------------------------
%% @doc Add the independently scheduled callback offer to the same playlist.
%% @end
%%------------------------------------------------------------------------------
-spec maybe_announce_callback(list(), map()) -> list().
maybe_announce_callback(Due, #{call := Call, config := Config}) ->
    case lists:member('callback', Due) of
        'false' -> [];
        'true' -> callback_offer_prompts(kapps_call:language(Call), Config)
    end.

-spec callback_offer_prompts(binary(), map()) -> list().
callback_offer_prompts(_, #{callback_announcements_enabled := 'false'}) -> [];
callback_offer_prompts(Language0, #{callback_audio := {Language,Audio}}) ->
    case acdc_gemini_prompts:canonical(Language0) =:= Language of
        false -> [];
        true ->
            Offer = maps:get(offer,maps:get(media,Audio)),
            case maps:get(builtin_gemini,Audio,false) of
                true -> [{play,Offer}];
                false -> [{prompt,Offer,Language,<<"A">>}]
            end
    end;
callback_offer_prompts(_, _) -> [].

%% Preflight once after binding call events, before scheduling the first offer.
%% No interval performs datastore work, and an incomplete menu/digit/auxiliary
%% pack can never advertise an otherwise playable callback offer.
-spec resolve_callback_audio(map(), kapps_call:call()) -> map().
resolve_callback_audio(#{callback_announcements_enabled := false}=Config, _) -> Config;
resolve_callback_audio(Config, Call) ->
    Language = acdc_gemini_prompts:canonical(kapps_call:language(Call)),
    Result = try acdc_gemini_prompts:callback(maps:get(callback_entry_key,Config),
                        maps:get(callback_allow_alternate,Config,false),maps:get(callback_media,Config),
                        Language,kapps_call:account_id(Call))
             catch _:_ -> {error,callback_media_unavailable}
             end,
    case Result of
        {ok,Audio} -> Config#{callback_audio => {Language,Audio}};
        _ -> Config#{callback_announcements_enabled := false,callback_audio => undefined}
    end.

-spec maybe_play_announcements(kapps_call_command:audio_macro_prompts(), kapps_call:call()) -> any().
maybe_play_announcements([], _) -> 'ok';
maybe_play_announcements(Prompts, Call) ->
    kapps_call_command:audio_macro(Prompts, Call).

%%------------------------------------------------------------------------------
%% @doc Get the average wait time from stats via AMQP.
%% @end
%%------------------------------------------------------------------------------
-spec get_average_wait_time(kapps_call:call()) -> kz_term:api_non_neg_integer().
get_average_wait_time(Call) ->
    QueueId = kapps_call:custom_channel_var(<<"Queue-ID">>, Call),
    Req = props:filter_undefined(
            [{<<"Account-ID">>, kapps_call:account_id(Call)}
            ,{<<"Queue-ID">>, QueueId}
             | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
            ]),
    case kz_amqp_worker:call(Req
                            ,fun kapi_acdc_stats:publish_average_wait_time_req/1
                            ,fun kapi_acdc_stats:average_wait_time_resp_v/1
                            )
    of
        {'error', E} ->
            lager:error("failed to receive current calls from AMQP: ~p", [E]),
            'undefined';
        {'ok', Resp} ->
            kz_json:get_integer_value(<<"Average-Wait-Time">>, Resp, 0)
    end.

%%------------------------------------------------------------------------------
%% @doc Structure for time prompt entries.
%% @end
%%------------------------------------------------------------------------------
-spec time_prompt(non_neg_integer(), binary()) -> {'prompt', kz_term:ne_binary(), binary(), kz_term:ne_binary()}.
time_prompt(Time, Language) ->
    {'prompt', acdc_language:default_prompt(time_prompt2(Time), Language), Language, <<"A">>}.

%% Only remap stock IDs. User-selected UUIDs, URLs and other prompt names keep
%% their existing account-scoped resolution behavior.
-spec localized_default(binary(), binary(), map()) -> binary().
localized_default(Prompt, Language, _Config) ->
    case lists:member(Prompt, [Value || {_, Value} <- ?DEFAULT_ANNOUNCEMENTS_MEDIA]) of
        'true' -> acdc_language:default_prompt(Prompt, Language);
        'false' -> Prompt
    end.

%%------------------------------------------------------------------------------
%% @doc Returns the appropriate prompt name for the given average wait time.
%% @end
%%------------------------------------------------------------------------------
-spec time_prompt2(non_neg_integer()) -> kz_term:ne_binary().
time_prompt2(Time) when Time < ?SECONDS_IN_MINUTE ->
    <<"queue-less_than_1_minute">>;
time_prompt2(Time) when Time =< 5 * ?SECONDS_IN_MINUTE ->
    <<"queue-about_5_minutes">>;
time_prompt2(Time) when Time =< 10 * ?SECONDS_IN_MINUTE ->
    <<"queue-about_10_minutes">>;
time_prompt2(Time) when Time =< 15 * ?SECONDS_IN_MINUTE ->
    <<"queue-about_15_minutes">>;
time_prompt2(Time) when Time =< 30 * ?SECONDS_IN_MINUTE ->
    <<"queue-about_30_minutes">>;
time_prompt2(Time) when Time =< 45 * ?SECONDS_IN_MINUTE ->
    <<"queue-about_45_minutes">>;
time_prompt2(Time) when Time =< 60 * ?SECONDS_IN_MINUTE ->
    <<"queue-about_1_hour">>;
time_prompt2(_) ->
    <<"queue-at_least_1_hour">>.

%%------------------------------------------------------------------------------
%% @doc Return the media file of a given name from the config.
%% @end
%%------------------------------------------------------------------------------
-spec announcements_media_file(kz_term:ne_binary(), map()) -> kz_term:api_ne_binary().
announcements_media_file(Name, #{announcements_media := Media}) ->
    props:get_binary_value(Name, Media).
