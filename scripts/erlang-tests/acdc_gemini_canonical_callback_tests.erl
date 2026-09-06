%%% Current-source callback contract. Synthetic imported documents only; no IO.
-module(acdc_gemini_canonical_callback_tests).
-include_lib("eunit/include/eunit.hrl").
-include("acdc_gemini_map.hrl").
-define(ACCOUNT, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).

all_five_callback_contracts_have_exact_fixed_and_digit_paths_test() -> with_store(fun() ->
    lists:foreach(fun(Language) ->
        Call=call(Language),
        Config=cf_acdc_member:callback_config(queue(),Call),
        ?assert(maps:get(builtin_gemini,Config)),
        ?assertNot(maps:get(non_gemini_numeric_dependency,Config)),
        ?assertEqual(6,map_size(maps:get(media,Config))),
        ?assertEqual(10,map_size(maps:get(readback,Config))),
        ?assertEqual(path(Language,<<"acdc-callback-offer-6">>),maps:get(offer,maps:get(media,Config))),
        Reads=get(reads),
        {ok,Prompts}=cf_acdc_member:callback_confirmation_prompts(Config,Call,<<"00129">>),
        ?assertEqual(Reads,get(reads)),
        ?assertEqual([{play,path(Language,<<"acdc-callback-number-readback">>)}]
                     ++ [{play,path(Language,<<"acdc-number-",D>>)} || <<D>> <= <<"00129">>]
                     ++ [{play,path(Language,<<"acdc-callback-confirmation">>)}],Prompts),
        ?assertEqual([], [P || {say,_,_}=P <- Prompts]),
        ?assertEqual({error,invalid_readback},cf_acdc_member:callback_confirmation_prompts(Config,Call,<<"+12">>)),
        ?assertEqual(Reads,get(reads))
    end,locales())
end).

every_missing_asset_blocks_callback_and_offer_test() -> with_store(fun() ->
    %% Includes all offers, both menus, return confirmation, auxiliary paths,
    %% and digits; no partially verified callback contract can escape.
    lists:foreach(fun(Asset) ->
        Missing=media_id(Asset),
        put({fake_datamgr,open},fun(<<"system_media">>,Id) ->
            case Id=:=Missing of true -> {error,not_found}; false -> acdc_gemini_prompts_tests:read(Id) end;
            (_,_) -> error(unexpected_account_lookup)
        end),
        ?assertEqual(undefined,cf_acdc_member:callback_config(queue(),call(<<"en-us">>))),
        Resolved=acdc_announcements:resolve_callback_audio(announcement_config(),call(<<"en-us">>)),
        ?assertEqual([],acdc_announcements:callback_offer_prompts(<<"en-us">>,Resolved)),
        ?assert(maps:get(position_announcements_enabled,Resolved))
    end,[A || A <- ?GEMINI_ASSETS,element(1,A)=:= <<"en-us">>])
end).

callback_offer_is_cached_and_localized_test() -> with_store(fun() ->
    lists:foreach(fun(Language) ->
        Config=acdc_announcements:resolve_callback_audio(announcement_config(),call(Language)),
        Reads=get(reads),
        lists:foreach(fun(_) ->
            ?assertEqual([{play,path(Language,<<"acdc-callback-offer-6">>)}],
                         acdc_announcements:callback_offer_prompts(Language,Config))
        end,lists:seq(1,10)),
        ?assertEqual(Reads,get(reads)),
        ?assertEqual([],acdc_announcements:callback_offer_prompts(<<"unsupported">>,Config))
    end,locales())
end).

returned_confirmation_prefers_queue_language_without_alias_lookup_test() -> with_store(fun() ->
    lists:foreach(fun(Language) ->
        Queue=kz_json:set_value([<<"announcements">>,<<"language">>],Language,queue()),
        ?assertEqual({ok,path(Language,<<"acdc-callback-returned-confirmation">>)},
                     acdc_callback_caller:confirmation_prompt(Queue,call(<<"en-us">>)))
    end,locales()),
    put({fake_datamgr,open},fun(_,_) -> {error,not_found} end),
    ?assertEqual({error,missing_localized_media},acdc_callback_caller:confirmation_prompt(queue(),call(<<"en-us">>)))
end).

legacy_custom_contract_is_separate_and_partial_custom_fails_test() -> with_store(fun() ->
    Media=kz_json:from_list([{K,<<"prompt://customer/",K/binary,"/fr-fr">>} || K <-
          [<<"offer">>,<<"menu">>,<<"number_readback">>,<<"confirmation">>,<<"success">>]]),
    Queue=kz_json:set_value([<<"callback">>,<<"media">>],Media,queue()),
    put({fake_datamgr,open},fun(_,_) -> error(unexpected_lookup) end),
    Config=cf_acdc_member:callback_config(Queue,call(<<"fr-fr">>)),
    ?assert(maps:get(legacy_custom_media,Config)),
    ?assertNot(maps:get(builtin_gemini,Config,false)),
    ?assertEqual({ok,[{say,<<"0012">>,<<"telephone_number">>}]},
                 acdc_gemini_prompts:callback_readback(<<"0012">>,Config)),
    Partial=kz_json:set_value([<<"callback">>,<<"media">>],
                kz_json:from_list([{<<"offer">>,<<"custom-offer">>}]),queue()),
    ?assertEqual(undefined,cf_acdc_member:callback_config(Partial,call(<<"en-us">>))),
    Returned= <<"prompt://customer/return-confirmation/fr-fr">>,
    LegacyReturn=kz_json:set_value([<<"callback">>,<<"return_confirmation_prompt">>],Returned,queue()),
    ?assertEqual({ok,Returned},acdc_callback_caller:confirmation_prompt(LegacyReturn,call(<<"fr-fr">>)))
end).

unsupported_locale_never_borrows_english_test() -> with_store(fun() ->
    ?assertEqual(undefined,cf_acdc_member:callback_config(queue(),call(<<"fr-ca">>))),
    ?assertEqual({error,missing_localized_media},acdc_callback_caller:confirmation_prompt(queue(),call(<<"fr-ca">>))),
    ?assertEqual(0,get(reads))
end).

with_store(Fun) ->
    put(reads,0),
    put({fake_datamgr,open},fun(<<"system_media">>,Id) ->
        put(reads,get(reads)+1),acdc_gemini_prompts_tests:read(Id);
        (_,_) -> error(unexpected_account_lookup)
    end),
    put({fake_datamgr,view},fun(_,_,_) -> error(unexpected_alias_lookup) end),
    try Fun()
    after erase(reads),erase({fake_datamgr,open}),erase({fake_datamgr,view})
    end.

locales() -> [<<"en-us">>,<<"he-il">>,<<"fr-fr">>,<<"es-es">>,<<"ar-sa">>].
call(Language) -> kapps_call:set_language(Language,kapps_call:set_account_id(?ACCOUNT,
                    kapps_call:set_call_id(<<"canonical-callback-test">>,kapps_call:new()))).
queue() -> kz_json:from_list([{<<"callback">>,kz_json:from_list([{<<"enabled">>,true}])}]).
announcement_config() -> acdc_announcements:get_config([{<<"position_announcements_enabled">>,true},
                            {<<"callback">>,[{<<"enabled">>,true}]}]).
media_id(Asset) -> <<(element(1,Asset))/binary,"/",(element(3,Asset))/binary>>.
path(Language,Canonical) ->
    Asset=acdc_gemini_prompts:asset(Language,Canonical),
    <<"/system_media/",(media_id(Asset))/binary>>.
