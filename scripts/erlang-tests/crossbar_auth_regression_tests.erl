%%% SPDX-License-Identifier: MPL-2.0
-module(crossbar_auth_regression_tests).
-include_lib("eunit/include/eunit.hrl").

validation_test_() ->
    {setup,
     fun() ->
         meck:new(kz_auth, [no_link]),
         meck:new(kz_datamgr, [no_link]),
         meck:expect(kz_auth, validate_token, fun(Result, []) -> Result end),
         meck:expect(kz_datamgr, open_cache_doc,
                     fun(<<"token_auth">>, _) -> {error, not_found} end)
     end,
     fun(_) -> meck:unload([kz_auth, kz_datamgr]) end,
     [?_assertEqual({error, Reason}, crossbar_auth:validate_auth_token({error, Reason}))
      || Reason <- [invalid_jwt, invalid_jwt_signature, token_expired,
                    algorithm_not_supported, forbidden, {403, <<"unmapped account">>}]]
     ++ [?_assertEqual({ok, Claims}, crossbar_auth:validate_auth_token({ok, Claims}))
         || Claims <- [kz_json:new(), kz_json:from_list([{<<"account_id">>, <<"test">>}])]]}.

legacy_token_fallback_test() ->
    meck:new(kz_auth, [no_link]),
    meck:new(kz_datamgr, [no_link]),
    try
        meck:expect(kz_auth, validate_token, fun(_, []) -> {error, no_jwt_signed_token} end),
        meck:expect(kz_datamgr, open_cache_doc,
                    fun(<<"token_auth">>, <<"legacy-token">>) -> {error, not_found} end),
        ?assertEqual({error, not_found}, crossbar_auth:validate_auth_token(<<"legacy-token">>)),
        ?assert(meck:validate(kz_datamgr))
    after
        meck:unload([kz_auth, kz_datamgr])
    end.

malformed_jwt_test_() ->
    [?_assertEqual(false, kz_auth_jwt:verify(Token))
     || Token <- [<<"not-a-jwt">>, <<"e30.e30.eA">>, <<"!.e30.eA">>,
                  <<"bnVsbA.e30.eA">>, <<"W10.e30.eA">>, <<"e30.W10.eA">>,
                  <<"eyJhbGciOiJub25lIn0.e30.eA">>]].
