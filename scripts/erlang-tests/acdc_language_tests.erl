%%% SPDX-License-Identifier: MPL-2.0
-module(acdc_language_tests).
-include_lib("eunit/include/eunit.hrl").

canonical_locales_are_exact_test() ->
    ?assertEqual(<<"en-us">>, acdc_language:canonical(undefined)),
    ?assertEqual(<<"he-il">>, acdc_language:canonical(<<"HE_IL">>)),
    lists:foreach(fun(L) -> ?assert(acdc_language:bundled(L)) end,
                  [<<"en-us">>, <<"ar-sa">>, <<"he-il">>, <<"es-es">>, <<"fr-fr">>]),
    lists:foreach(fun(L) -> ?assertNot(acdc_language:bundled(L)) end,
                  [<<"he">>, <<"ar">>, <<"fr-ca">>, <<"de-de">>, <<>>, 123]).

recorded_number_groups_preserve_value_and_order_test() ->
    Numbers = lists:seq(0, 10000) ++ [101001, 1001001, 21000021, 999999999],
    lists:foreach(
      fun(Language) ->
              lists:foreach(
                fun(Number) ->
                        Prompts = acdc_language:number_prompts(Number, Language),
                        Values = [binary_to_integer(binary:part(Id, 12, byte_size(Id) - 12))
                                  || {prompt, Id, L, <<"A">>} <- Prompts
                                         ,L =:= Language, Id =/= <<"acdc-number-and">>],
                        ?assertEqual(Number, lists:sum(Values)),
                        ?assertEqual(lists:reverse(lists:sort(Values)), Values),
                        ?assert(lists:all(fun valid_chunk/1, Values)),
                        ?assertEqual(max(0, length(Values) - 1),
                                     length([and_marker || {prompt, <<"acdc-number-and">>, _, _} <- Prompts]))
                end, Numbers)
      end, [<<"ar-sa">>, <<"he-il">>]).

valid_chunk(N) ->
    (N >= 0 andalso N =< 999)
        orelse (N rem 1000 =:= 0 andalso N >= 1000 andalso N =< 999000)
        orelse (N rem 1000000 =:= 0 andalso N >= 1000000 andalso N =< 999000000).

recorded_zero_and_boundaries_test() ->
    ?assertEqual([{prompt, <<"acdc-number-0">>, <<"ar-sa">>, <<"A">>}],
                 acdc_language:number_prompts(0, <<"ar-sa">>)),
    ?assertEqual([{prompt, <<"acdc-number-2000">>, <<"he-il">>, <<"A">>}],
                 acdc_language:number_prompts(2000, <<"he-il">>)),
    lists:foreach(fun(N) -> ?assertEqual([], acdc_language:number_prompts(N, <<"ar-sa">>)) end,
                  [-1, 1000000000, undefined, <<"1">>]),
    lists:foreach(fun(L) -> ?assertEqual([{say, <<"80">>, <<"number">>}],
                                        acdc_language:number_prompts(80, L)) end,
                  [<<"en-us">>, <<"es-es">>, <<"fr-fr">>]).

telephone_readback_preserves_every_digit_test() ->
    lists:foreach(
      fun(Language) ->
              Prompts = acdc_language:telephone_prompts(<<"0012080">>, Language),
              ?assertEqual([<<"acdc-number-0">>, <<"acdc-number-0">>, <<"acdc-number-1">>
                           ,<<"acdc-number-2">>, <<"acdc-number-0">>, <<"acdc-number-8">>, <<"acdc-number-0">>],
                           [Id || {prompt, Id, _, _} <- Prompts])
      end, [<<"ar-sa">>, <<"he-il">>]),
    ?assertEqual([{say, <<"0012080">>, <<"telephone_number">>}],
                 acdc_language:telephone_prompts(<<"0012080">>, <<"fr-fr">>)),
    lists:foreach(fun(D) -> ?assertEqual([], acdc_language:telephone_prompts(D, <<"he-il">>)) end,
                  [<<>>, <<"12a3">>, <<"12;system">>, <<"+123">>, 123]).

installed_media_is_exact_and_fail_closed_test() ->
    meck:new(kz_datamgr, [passthrough, no_link]),
    try
        meck:expect(kz_datamgr, open_cache_doc, fun(<<"system_media">>, Id) -> {ok, doc(Id, 32)} end),
        ?assert(acdc_language:callback_available(<<"ar-sa">>)),
        ?assert(acdc_language:callback_available(<<"he-il">>)),
        ?assert(acdc_language:media_available(<<"FR_FR">>, [<<"acdc-callback-returned-confirmation">>])),
        ?assertNot(acdc_language:media_available(<<"fr-ca">>, [<<"acdc-callback-returned-confirmation">>])),
        meck:expect(kz_datamgr, open_cache_doc,
                    fun(_, <<"ar-sa/acdc-number-8">>) -> {error, not_found};
                       (_, Id) -> {ok, doc(Id, 32)}
                    end),
        ?assertNot(acdc_language:callback_available(<<"ar-sa">>)),
        meck:expect(kz_datamgr, open_cache_doc, fun(_, _) -> {ok, doc(<<"en-us/wrong">>, 32)} end),
        ?assertNot(acdc_language:media_available(<<"he-il">>, [<<"acdc-number-1">>])),
        meck:expect(kz_datamgr, open_cache_doc, fun(_, Id) -> {ok, doc(Id, 0)} end),
        ?assertNot(acdc_language:callback_available(<<"es-es">>)),
        meck:expect(kz_datamgr, open_cache_doc, fun(_, Id) -> {ok, kz_doc:set_soft_deleted(doc(Id, 32), true)} end),
        ?assertNot(acdc_language:callback_available(<<"he-il">>)),
        meck:expect(kz_datamgr, open_cache_doc, fun(_, Id) -> {ok, kz_doc:set_deleted(doc(Id, 32), true)} end),
        ?assertNot(acdc_language:callback_available(<<"ar-sa">>)),
        meck:expect(kz_datamgr, open_cache_doc, fun(_, _) -> exit(database_unavailable) end),
        ?assertNot(acdc_language:callback_available(<<"fr-fr">>))
    after meck:unload(kz_datamgr)
    end.

localized_backend_playlists_test() ->
    Config = acdc_announcements:get_config([]),
    lists:foreach(
      fun(Language) ->
              Position = acdc_announcements:position_prompts(21, Language, Config),
              ?assertEqual({prompt, <<"acdc-queue-your-current-position-is">>, Language, <<"A">>}, hd(Position)),
              ?assertEqual(acdc_language:number_prompts(21, Language), tl(Position)),
              {Wait, 4000} = acdc_announcements:wait_time_prompts(4000, 60, Language, Config),
              ?assertEqual([<<"acdc-queue-increase_in_call_volume">>, <<"acdc-queue-the_estimated_wait_time_is">>
                           ,<<"acdc-queue-at_least_1_hour">>], [Id || {prompt, Id, _, _} <- Wait])
      end, [<<"en-us">>, <<"ar-sa">>, <<"he-il">>, <<"es-es">>, <<"fr-fr">>]),
    Custom = acdc_announcements:get_config([{<<"media">>, [{<<"you_are_at_position">>, <<"customer-prefix">>}
                                                          ,{<<"in_the_queue">>, <<"customer-suffix">>}]}]),
    ?assertEqual([{prompt, <<"customer-prefix">>, <<"ar-sa">>, <<"A">>}
                 ,{prompt, <<"acdc-number-80">>, <<"ar-sa">>, <<"A">>}
                 ,{prompt, <<"customer-suffix">>, <<"ar-sa">>, <<"A">>}],
                 acdc_announcements:position_prompts(80, <<"ar-sa">>, Custom)).

callback_language_inherits_queue_and_preserves_custom_media_test() ->
    Call = kapps_call:set_language(<<"en-us">>, kapps_call:new()),
    Queue = kz_json:set_value([<<"announcements">>, <<"language">>], <<"HE_IL">>, kz_json:new()),
    ?assertEqual(<<"he-il">>, kapps_call:language(cf_acdc_member:queue_announcement_call(Queue, Call))),
    ?assertEqual(<<"en-us">>, kapps_call:language(cf_acdc_member:queue_announcement_call(kz_json:new(), Call))),
    meck:new(kz_datamgr, [passthrough, no_link]),
    try
        meck:expect(kz_datamgr, open_cache_doc, fun(_, Id) -> {ok, doc(Id, 32)} end),
        ?assertMatch({ok, _}, cf_acdc_member:callback_test_media(kz_json:new(), <<"ar-sa">>)),
        ?assertEqual({ok, <<"acdc-callback-returned-confirmation">>},
                     acdc_callback_caller:confirmation_prompt(Queue, kapps_call:set_language(<<"he-il">>, Call))),
        meck:expect(kz_datamgr, open_cache_doc, fun(_, _) -> {error, not_found} end),
        ?assertMatch({error, _}, cf_acdc_member:callback_test_media(kz_json:new(), <<"ar-sa">>)),
        ?assertEqual({error, missing_localized_media},
                     acdc_callback_caller:confirmation_prompt(Queue, kapps_call:set_language(<<"he-il">>, Call))),
        Custom = kz_json:set_value([<<"callback">>, <<"media">>, <<"returned_confirmation">>],
                                   <<"account-custom-media">>, Queue),
        ?assertEqual({ok, <<"account-custom-media">>},
                     acdc_callback_caller:confirmation_prompt(Custom, kapps_call:set_language(<<"he-il">>, Call)))
    after meck:unload(kz_datamgr)
    end.

doc(Id, Length) ->
    kz_json:from_list([{<<"_id">>, Id}, {<<"_attachments">>, kz_json:from_list(
                       [{<<"prompt.wav">>, kz_json:from_list([{<<"length">>, Length}, {<<"content_type">>, <<"audio/wav">>}])}])}]).
