%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2026, Talkchief
%%% @doc Unit tests for queue announcement configuration and prompt building.
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%-----------------------------------------------------------------------------
-module(acdc_announcements_tests).

-include_lib("eunit/include/eunit.hrl").


english_position_is_a_complete_sentence_test() ->
    Audio = #{language => <<"en-us">>,
              before_number => [{play, <<"/system_media/en-us/approved-intro">>}],
              after_number => [],
              assets => #{<<"acdc-cardinal-v1-number-1">> => <<"/system_media/en-us/approved-one">>}},
    Config = (acdc_announcements:get_config([]))#{position_audio => Audio},
    ?assertEqual(
       [{play, <<"/system_media/en-us/approved-intro">>}
       ,{play, <<"/system_media/en-us/approved-one">>}
       ], acdc_announcements:position_prompts(1, <<"en-us">>, Config)),
    CustomAudio = Audio#{before_number := [{prompt, <<"custom-position">>, <<"en-us">>, <<"A">>}],
                         after_number := [{play, <<"/system_media/en-us/approved-suffix">>}]},
    Custom = Config#{position_audio := CustomAudio},
    ?assertEqual(
       [{'prompt', <<"custom-position">>, <<"en-us">>, <<"A">>}
       ,{play, <<"/system_media/en-us/approved-one">>}
       ,{play, <<"/system_media/en-us/approved-suffix">>}
       ], acdc_announcements:position_prompts(1, <<"en-us">>, Custom)).

initial_delay_runtime_test_() ->
    {timeout, 20, fun initial_delay_runtime/0}.

initial_delay_runtime() ->
    Parent = self(),
    ok = meck:new(gen_listener, [passthrough, no_link]),
    ok = meck:new(kapps_call_command, [passthrough, no_link]),
    ok = meck:new(kz_events, [passthrough, no_link]),
    ok = meck:new(acdc_cardinal_media, [passthrough, no_link]),
    meck:expect(kz_events, bind_call_id, fun(_) -> ok end),
    meck:expect(kz_events, unbind_call_id, fun(_) -> ok end),
    meck:expect(acdc_cardinal_media, prepare, fun(_, _, _) ->
        {ok, #{language => <<"en-us">>,
               before_number => [{play, <<"/system_media/en-us/approved-intro">>}],
               after_number => [],
               assets => #{<<"acdc-cardinal-v1-number-1">> => <<"/system_media/en-us/approved-one">>}}}
    end),
    meck:expect(gen_listener, call, fun(_, {queue_position, _}, 500) -> 1 end),
    meck:expect(kapps_call_command, audio_macro,
                fun(Prompts, _) -> Parent ! {announcement_played, Prompts}, ok end),
    Call = kapps_call:set_language(<<"en-us">>, kapps_call:new()),
    Props = [{<<"position_announcements_enabled">>, true}, {<<"initial_delay">>, 1}],
    Started = erlang:monotonic_time(millisecond),
    {Pid, Ref} = spawn_monitor(fun() -> acdc_announcements:init(Parent, Call, Props) end),
    try
        receive {announcement_played, _} -> ?assert(false) after 200 -> ok end,
        receive
            {announcement_played, [{play, _}, {play, <<"/system_media/en-us/approved-one">>}]} ->
                ?assert(erlang:monotonic_time(millisecond) - Started >= 1000)
        after 1500 -> ?assert(false)
        end,
        %% A queue leave/callback menu cancellation interrupts the sleeping
        %% process; it must not wake up and enqueue another announcement.
        exit(Pid, shutdown),
        receive {'DOWN', Ref, process, Pid, shutdown} -> ok after 500 -> ?assert(false) end,
        {Waiting, WaitingRef} = spawn_monitor(fun() -> acdc_announcements:init(Parent, Call, Props) end),
        exit(Waiting, shutdown),
        receive {'DOWN', WaitingRef, process, Waiting, shutdown} -> ok after 500 -> ?assert(false) end,
        receive {announcement_played, _} -> ?assert(false) after 1100 -> ok end
    after
        exit(Pid, kill),
        meck:unload(gen_listener), meck:unload(kapps_call_command),
        meck:unload(kz_events), meck:unload(acdc_cardinal_media)
    end.

initial_delay_is_separate_bounded_and_never_immediate_test() ->
    Default = acdc_announcements:get_config([]),
    ?assertEqual(30000, acdc_announcements:initial_delay_ms(Default)),
    Custom = acdc_announcements:get_config([{<<"interval">>, 60}, {<<"initial_delay">>, 30}]),
    ?assertEqual(60, maps:get(announcements_interval, Custom)),
    ?assertEqual(30000, acdc_announcements:initial_delay_ms(Custom)),
    ?assertEqual(1000, acdc_announcements:initial_delay_ms(
                         acdc_announcements:get_config([{<<"initial_delay">>, 0}]))),
    ?assertEqual(3600000, acdc_announcements:initial_delay_ms(
                            acdc_announcements:get_config([{<<"initial_delay">>, 99999}]))).

proplist_config_test() ->
    Config = acdc_announcements:get_config(
               [{<<"position_announcements_enabled">>, 'true'}
               ,{<<"wait_time_announcements_enabled">>, 'true'}
               ,{<<"interval">>, 10}
               ,{<<"language">>, <<"fr-ca">>}
               ,{<<"media">>, [{<<"you_are_at_position">>, <<"custom-position">>}]}]),
    ?assertEqual('true', maps:get(position_announcements_enabled, Config)),
    ?assertEqual('true', maps:get(wait_time_announcements_enabled, Config)),
    ?assertEqual(15, maps:get(announcements_interval, Config)),
    ?assertEqual(<<"fr-ca">>, maps:get(announcement_language, Config)),
    ?assertEqual([{<<"you_are_at_position">>, <<"custom-position">>}],
                 maps:get(announcements_media_selection, Config)),
    %% Unsupported regional variants never select another locale or native SAY.
    ?assertEqual([], acdc_announcements:position_prompts(2, <<"fr-ca">>, Config)),
    ?assertEqual([], acdc_announcements:position_prompts(2, <<"fr-fr">>, Config)).

json_config_and_partial_media_defaults_test() ->
    Config = acdc_announcements:get_config(
               kz_json:from_list(
                 [{<<"language">>, <<"es-us">>}
                 ,{<<"media">>, kz_json:from_list(
                                    [{<<"in_the_queue">>, <<"custom-in-queue">>}
                                    ,{<<"increase_in_call_volume">>, <<>>}
                                    ])}
                 ])),
    ?assertEqual(<<"custom-in-queue">>, proplists:get_value(<<"in_the_queue">>,
                 maps:get(announcements_media_selection, Config))),
    ?assertEqual([], acdc_announcements:position_prompts(4, <<"es-us">>, Config)),
    ?assertEqual([], acdc_announcements:position_prompts(4, <<"es-es">>, Config)),
    ?assertEqual({[], 120},
       acdc_announcements:wait_time_prompts(240, 120, <<"es-us">>, Config)).

non_english_custom_framing_preserves_prerecorded_number_test() ->
    lists:foreach(fun({Language, Number, Role}) ->
        Prefix = {prompt, <<"custom-position">>, Language, <<"A">>},
        Suffix = {prompt, <<"custom-in-queue">>, Language, <<"A">>},
        Path = <<"/system_media/", Language/binary, "/approved-number">>,
        Audio = #{language => Language, before_number => [Prefix], after_number => [Suffix],
                  assets => #{Role => Path}},
        Config = (acdc_announcements:get_config([]))#{position_audio => Audio},
        ?assertEqual([Prefix, {play, Path}, Suffix],
            acdc_announcements:position_prompts(Number, Language, Config)),
        ?assertEqual([], acdc_announcements:position_prompts(Number, Language,
            Config#{position_audio := Audio#{assets := #{}}}))
    end, [{<<"fr-fr">>, 2, <<"acdc-cardinal-v1-terminal-2">>},
          {<<"es-es">>, 4, <<"acdc-cardinal-v1-number-4">>}]).

language_override_test() ->
    Call = kapps_call:set_language(<<"en-us">>, kapps_call:new()),
    NoOverride = acdc_announcements:get_config([]),
    Override = acdc_announcements:get_config([{<<"language">>, <<"de-de">>}]),
    ?assertEqual(<<"en-us">>,
                 kapps_call:language(
                   acdc_announcements:maybe_set_announcement_language(Call, NoOverride))),
    ?assertEqual(<<"de-de">>,
                 kapps_call:language(
                   acdc_announcements:maybe_set_announcement_language(Call, Override))).

invalid_position_is_skipped_test() ->
    Config = acdc_announcements:get_config([]),
    ?assertEqual([], acdc_announcements:position_prompts('undefined', <<"en-us">>, Config)),
    ?assertEqual([], acdc_announcements:position_prompts(0, <<"en-us">>, Config)).

unknown_wait_time_is_skipped_test() ->
    Config = acdc_announcements:get_config([]),
    ?assertEqual({[], 'undefined'},
                 acdc_announcements:wait_time_prompts('undefined', 'undefined', <<"en-us">>, Config)),
    ?assertEqual({[], 75},
                 acdc_announcements:wait_time_prompts('undefined', 75, <<"en-us">>, Config)).

wait_time_boundaries_test() ->
    Keys = [<<"increase_in_call_volume">>, <<"the_estimated_wait_time_is">>, <<"less_than_1_minute">>,
            <<"about_5_minutes">>, <<"about_10_minutes">>, <<"about_15_minutes">>, <<"about_30_minutes">>,
            <<"about_45_minutes">>, <<"about_1_hour">>, <<"at_least_1_hour">>],
    Audio = #{language => <<"en-us">>, assets => maps:from_list([{Key,
        {play, <<"/system_media/en-us/acdc-queue-", Key/binary>>}} || Key <- Keys])},
    Config = (acdc_announcements:get_config([]))#{wait_time_audio => Audio},
    Cases = [{0, <<"queue-less_than_1_minute">>}
            ,{60, <<"queue-about_5_minutes">>}
            ,{300, <<"queue-about_5_minutes">>}
            ,{301, <<"queue-about_10_minutes">>}
            ,{3600, <<"queue-about_1_hour">>}
            ,{3601, <<"queue-at_least_1_hour">>}
            ],
    lists:foreach(
      fun({Seconds, Expected}) ->
              {Prompts, Seconds} =
                  acdc_announcements:wait_time_prompts(Seconds, 'undefined', <<"en-us">>, Config),
              ?assertEqual({play, <<"/system_media/en-us/acdc-", Expected/binary>>}, lists:last(Prompts))
      end,
      Cases).
