%%% SPDX-License-Identifier: MPL-2.0
%%% Baseline installer contract: no staged acdc_language module on the code path.
-module(acdc_callback_announcement_baseline_tests).
-include_lib("eunit/include/eunit.hrl").

baseline_does_not_import_or_load_staged_language_test() ->
    ?assertEqual(non_existing, code:which(acdc_language)),
    lists:foreach(
      fun(Module) ->
              {ok, {Module, [{imports, Imports}]}} = beam_lib:chunks(code:which(Module), [imports]),
              ?assertEqual([], [Entry || {Dependency, _, _}=Entry <- Imports, Dependency =:= acdc_language])
      end, [acdc_announcements, acdc_announcements_sup, acdc_queue_manager]).

baseline_language_readiness_matches_callflow_test() ->
    Config = acdc_announcements:get_config(
               [{<<"callback">>, [{<<"enabled">>, true}, {<<"entry_key">>, <<"6">>}]}]),
    Expected = [{prompt, <<"acdc-callback-offer-6">>, <<"en-us">>, <<"A">>}],
    ?assertEqual(Expected, acdc_announcements:callback_offer_prompts(undefined, Config)),
    ?assertEqual(Expected, acdc_announcements:callback_offer_prompts(<<"EN_US">>, Config)),
    ?assertEqual(Expected, acdc_announcements:callback_offer_prompts(<<"en-us">>, Config)),
    lists:foreach(
      fun(Language) ->
              %% Merely choosing a supported future locale does not activate
              %% an uninstalled language implementation or English fallback.
              ?assertEqual([], acdc_announcements:callback_offer_prompts(Language, Config)),
              OfferOnly = Config#{callback_media := [{<<"offer">>, <<"custom-offer">>}]},
              ?assertEqual([], acdc_announcements:callback_offer_prompts(Language, OfferOnly)),
              Keys = [<<"offer">>, <<"menu">>, <<"number_readback">>, <<"confirmation">>, <<"success">>],
              AllMedia = [{Key, <<"custom-", Key/binary>>} || Key <- Keys],
              AllCustom = Config#{callback_media := AllMedia},
              ?assertEqual([{prompt, <<"custom-offer">>, Language, <<"A">>}],
                           acdc_announcements:callback_offer_prompts(Language, AllCustom)),
              lists:foreach(fun(Key) ->
                                    Incomplete = AllCustom#{callback_media := proplists:delete(Key, AllMedia)},
                                    ?assertEqual([], acdc_announcements:callback_offer_prompts(Language, Incomplete))
                            end, Keys)
      end, [<<"fr-fr">>, <<"he-il">>, <<"ar-sa">>, <<"es-es">>]),
    ?assertEqual([], acdc_announcements:callback_offer_prompts(<<"en-us">>, Config#{callback_entry_key := <<"66">>})),
    ?assertEqual(non_existing, code:which(acdc_language)).

baseline_shared_scheduler_and_worker_test_() ->
    %% Reuse the source-independent scheduler, real 1s/15s timers, combined
    %% playlist, and real supervisor lifecycle assertions. Do not invoke the
    %% staged-only readiness test that intentionally mocks acdc_language.
    [fun acdc_callback_announcement_tests:configuration_defaults_and_bounds_test/0
    ,fun acdc_callback_announcement_tests:offer_switch_and_callback_disabled_are_independent_test/0
    ,fun acdc_callback_announcement_tests:independent_deadlines_and_combined_due_test/0
    ,fun acdc_callback_announcement_tests:late_wakeup_never_replays_missed_intervals_test/0
    ,fun acdc_callback_announcement_tests:disabled_clocks_never_spin_and_resume_resets_delays_test/0
    ,acdc_callback_announcement_tests:real_worker_timer_test_()
    ,fun acdc_callback_announcement_tests:correlated_completion_and_terminal_events_test/0
    ,acdc_callback_announcement_tests:worker_failure_lifecycle_test_()
    ,fun() -> ?assertEqual(non_existing, code:which(acdc_language)) end
    ].
