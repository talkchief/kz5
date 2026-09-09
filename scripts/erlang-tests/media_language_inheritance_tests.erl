%%% Public production language resolver; document/config lookups are controlled.
%%% No database writes, media generation, provider requests or native calls.
-module(media_language_inheritance_tests).
-include_lib("eunit/include/eunit.hrl").

language_inheritance_test_() ->
    [{Name, {timeout, 30, fun() -> run(Options, Expected) end}} || {Name, Options, Expected} <-
        [{"child inherits reseller account language", #{reseller_language => <<"HE-IL">>}, <<"he-il">>},
         {"child inherits reseller media override", #{reseller_config => <<"FR-FR">>}, <<"fr-fr">>},
         {"reseller media overrides reseller account language", #{reseller_language => <<"he-il">>, reseller_config => <<"AR-SA">>}, <<"ar-sa">>},
         {"account language wins without reseller lookup", #{account_language => <<"ES-ES">>, reseller_config => <<"he-il">>, no_reseller_lookup => true}, <<"es-es">>},
         {"account media override wins without reseller lookup", #{account_language => <<"es-es">>, account_config => <<"FR-FR">>, no_reseller_lookup => true}, <<"fr-fr">>},
         {"empty account media setting inherits reseller", #{account_config => <<>>, reseller_language => <<"he-il">>}, <<"he-il">>},
         {"missing reseller keeps supplied fallback", #{reseller_id => undefined}, <<"en-us">>},
         {"self reseller cannot recurse", #{reseller_id => self}, <<"en-us">>},
         {"missing reseller document keeps supplied fallback", #{reseller_fetch => {error, not_found}}, <<"en-us">>},
         {"failed reseller discovery keeps supplied fallback", #{reseller_id => failure}, <<"en-us">>},
         {"failed reseller config read keeps supplied fallback", #{reseller_config => failure}, <<"en-us">>},
         {"failed reseller account read keeps supplied fallback", #{reseller_fetch => failure}, <<"en-us">>},
         {"reseller without settings keeps caller fallback", #{default => <<"FR-FR">>}, <<"fr-fr">>},
         {"disabled account overrides use system language", #{overrides => false, account_language => <<"he-il">>, system => <<"ES-ES">>, no_reseller_lookup => true}, <<"es-es">>},
         {"accountless call uses system language", #{accountless => true, system => <<"AR-SA">>, no_reseller_lookup => true}, <<"ar-sa">>},
         {"undefined fallback retains global default resolution", #{default => undefined, system => <<"FR-FR">>, reseller_id => undefined}, <<"fr-fr">>}]].

run(Options, Expected) ->
    Account = <<"11111111111111111111111111111111">>,
    Reseller = <<"22222222222222222222222222222222">>,
    Modules = [kapps_config, kapps_account_config, kz_services_reseller, kzd_accounts],
    try
        lists:foreach(fun(M) -> meck:new(M, [non_strict, no_link]) end, Modules),
        meck:expect(kapps_config, get_is_true, fun(<<"media">>, <<"support_account_overrides">>, true) ->
            maps:get(overrides, Options, true)
        end),
        meck:expect(kapps_config, get_ne_binary, fun(<<"media">>, <<"default_language">>, Default) ->
            maps:get(system, Options, Default)
        end),
        meck:expect(kzd_accounts, fetch, fun(Id) when Id =:= Account -> {ok, doc(maps:get(account_language, Options, undefined))};
            (Id) when Id =:= Reseller -> case maps:get(reseller_fetch, Options, {ok, doc(maps:get(reseller_language, Options, undefined))}) of
                failure -> meck:exception(error, unavailable); Result -> Result end end),
        meck:expect(kzd_accounts, language, fun(Doc) -> kz_json:get_ne_binary_value(<<"language">>, Doc) end),
        meck:expect(kzd_accounts, language, fun(Doc, Default) -> kz_json:get_ne_binary_value(<<"language">>, Doc, Default) end),
        meck:expect(kapps_account_config, get_ne_binary, fun(Id, <<"media">>, <<"default_language">>, Default) ->
            Key = case Id of Account -> account_config; Reseller -> reseller_config end,
            case maps:get(Key, Options, undefined) of undefined -> Default; <<>> -> Default;
                failure -> meck:exception(error, unavailable); Value -> Value end
        end),
        meck:expect(kz_services_reseller, get_id, fun(Id) when Id =:= Account ->
            case maps:get(reseller_id, Options, Reseller) of self -> Account; failure -> meck:exception(error, unavailable); Value -> Value end
        end),
        Id = case maps:get(accountless, Options, false) of true -> undefined; false -> Account end,
        ?assertEqual(Expected, kz_media_util:prompt_language(Id, maps:get(default, Options, <<"en-us">>))),
        case maps:get(no_reseller_lookup, Options, false) of
            true -> ?assertEqual(0, meck:num_calls(kz_services_reseller, get_id, '_'));
            false -> ok
        end,
        ?assert(lists:all(fun meck:validate/1, Modules))
    after
        lists:foreach(fun(M) -> catch meck:unload(M) end, Modules)
    end.

doc(undefined) -> kz_json:new();
doc(Language) -> kz_json:from_list([{<<"language">>, Language}]).
