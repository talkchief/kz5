%%% SPDX-License-Identifier: MPL-2.0
-module(kz_auth_identity_revocation_tests).
-include_lib("eunit/include/eunit.hrl").

-define(ACCOUNT, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(USER, <<"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb">>).
-define(DEVICE, <<"cccccccccccccccccccccccccccccccc">>).
-define(OLD, <<"old-test-signing-secret">>).
-define(NEW, <<"new-test-signing-secret">>).
-define(SERVER, <<"test-provider-secret">>).

identity_revocation_test_() ->
    {foreach, fun setup/0, fun(_) -> meck:unload(kz_datamgr) end,
     [?_test(revoked(#{<<"owner_id">> => ?USER}, ?USER)),
      ?_test(revoked(#{<<"device_id">> => ?DEVICE}, ?DEVICE)),
      ?_test(revoked(#{}, ?ACCOUNT)),
      ?_test(unavailable(timeout)),
      ?_test(unavailable(connection_refused)),
      ?_test(unavailable(not_found))]}.

setup() ->
    meck:new(kz_datamgr, [no_link]),
    %% A disconnected peer can retain this valid, but revoked, cached key.
    meck:expect(kz_datamgr, open_cache_doc, fun(_, _) -> {ok, doc(?OLD)} end).

doc(Secret) -> kz_json:from_list([{<<"pvt_signature_secret">>, Secret}]).

token(Extra, Identity) ->
    Sig = crypto:mac(hmac, sha256, <<?OLD/binary, ?SERVER/binary>>, Identity),
    #{auth_provider => #{name => <<"kazoo">>,
                         jwt_identity_signature_secret => ?SERVER,
                         jwt_user_id_signature_hash => <<"sha256">>},
      payload => maps:merge(#{<<"account_id">> => ?ACCOUNT,
                              <<"identity_sig">> => kz_base64url:encode(Sig)}, Extra)}.

revoked(Extra, Identity) ->
    T = token(Extra, Identity),
    meck:expect(kz_datamgr, open_doc, fun(_, Id) when Id =:= Identity -> {ok, doc(?OLD)} end),
    ?assertEqual(true, kz_auth_identity:verify(T)),
    meck:expect(kz_datamgr, open_doc, fun(_, Id) when Id =:= Identity -> {ok, doc(?NEW)} end),
    ?assertEqual(false, kz_auth_identity:verify(T)),
    ?assertEqual(false, meck:called(kz_datamgr, open_cache_doc, '_')),
    ?assertEqual(2, meck:num_calls(kz_datamgr, open_doc, '_')),
    ?assert(meck:validate(kz_datamgr)).

unavailable(Reason) ->
    meck:expect(kz_datamgr, open_doc, fun(_, _) -> {error, Reason} end),
    ?assertEqual(false, kz_auth_identity:verify(token(#{<<"owner_id">> => ?USER}, ?USER))),
    ?assertEqual(false, meck:called(kz_datamgr, open_cache_doc, '_')),
    ?assertEqual(1, meck:num_calls(kz_datamgr, open_doc, '_')).
