%%% SPDX-License-Identifier: MPL-2.0
-module(acdc_callback_returned_call_tests).
-include_lib("eunit/include/eunit.hrl").

-define(ACCOUNT, <<"11111111111111111111111111111111">>).
-define(CALL, <<"22222222222222222222222222222222">>).
-define(AUTH, <<"33333333333333333333333333333333">>).

returned_call_test_() ->
    {'setup', fun() ->
                      'ok' = meck:new(kapps_config, ['passthrough', 'no_link']),
                      'ok' = meck:new(kapps_call_command, ['passthrough', 'no_link']),
                      meck:expect(kapps_call_command, set, fun(_, _, _) -> 'ok' end),
                      meck:expect(kapps_config, get_ne_binary, fun(_, _, Default) -> Default end),
                      meck:expect(kapps_config, get_binary, fun(_, _, Default) -> Default end),
                      meck:expect(kapps_config, get_ne_binaries, fun(_, _, Default) -> Default end)
              end,
     fun(_) -> meck:unload(kapps_call_command), meck:unload(kapps_config) end,
     [fun returned_audio_preserves_carrier_authorization_and_correlation/0
      ,fun returned_call_overrides_untrusted_scope_but_keeps_private_handles/0
      ,fun missing_or_audio_media_type_still_returns_audio/0
      ,fun actual_endpoint_policy_accepts_audio_and_retains_disabled_device_denial/0]}.

returned_audio_preserves_carrier_authorization_and_correlation() ->
    Call = returned(response()),
    ?assertEqual(<<"audio">>, kapps_call:resource_type(Call)),
    ?assertEqual(?ACCOUNT, kapps_call:account_id(Call)),
    ?assertEqual(kzs_util:format_account_db(?ACCOUNT), kapps_call:account_db(Call)),
    ?assertEqual(?CALL, kapps_call:call_id(Call)),
    ?assertEqual(<<"exact-control">>, kapps_call:control_queue(Call)),
    ?assertEqual(?AUTH, kapps_call:authorizing_id(Call)),
    ?assertEqual(<<"device">>, kapps_call:authorizing_type(Call)),
    ?assertEqual(<<"freeswitch@fixture">>, kapps_call:switch_nodename(Call)),
    ?assertEqual(<<"en-us">>, kapps_call:language(Call)),
    ?assertEqual(lists:sort(kz_json:to_proplist(ccvs())),
                 lists:sort(kz_json:to_proplist(kapps_call:custom_channel_vars(Call)))).

returned_call_overrides_untrusted_scope_but_keeps_private_handles() ->
    Response = kz_json:set_values([{[<<"Call">>, <<"Account-ID">>], <<"wrong-account">>}
                                  ,{[<<"Call">>, <<"Account-DB">>], <<"wrong-db">>}
                                  ,{[<<"Call">>, <<"Call-ID">>], <<"wrong-call">>}
                                  ,{[<<"Call">>, <<"Control-Queue">>], <<"wrong-control">>}], response()),
    Call = returned(Response),
    ?assertEqual(?ACCOUNT, kapps_call:account_id(Call)),
    ?assertEqual(?CALL, kapps_call:call_id(Call)),
    ?assertEqual(<<"exact-control">>, kapps_call:control_queue(Call)),
    ?assertEqual(?AUTH, kapps_call:authorizing_id(Call)).

missing_or_audio_media_type_still_returns_audio() ->
    Missing = kz_json:delete_key([<<"Call">>, <<"Resource-Type">>], response()),
    Audio = kz_json:set_value([<<"Call">>, <<"Resource-Type">>], <<"audio">>, response()),
    ?assertEqual(<<"audio">>, kapps_call:resource_type(returned(Missing))),
    ?assertEqual(<<"audio">>, kapps_call:resource_type(returned(Audio))),
    ?assertEqual(<<"audio">>, kapps_call:resource_type(returned(kz_json:new()))).

actual_endpoint_policy_accepts_audio_and_retains_disabled_device_denial() ->
    %% Run the real endpoint policy path that raised function_clause on the
    %% live carrier response. A disabled fixture stops before network/DB work;
    %% reaching this specific denial proves owner/self-call checks succeeded.
    Endpoint = kz_json:from_list([{<<"_id">>, <<"44444444444444444444444444444444">>}
                                 ,{<<"owner_id">>, <<"55555555555555555555555555555555">>}
                                 ,{<<"enabled">>, 'false'}]),
    ?assertEqual({'error', 'endpoint_disabled'},
                 kz_endpoint_v5:build(Endpoint, kz_json:new(), returned(response()))).

returned(Response) ->
    Original = kapps_call:from_json(kz_json:from_list([{<<"Language">>, <<"en-us">>}])),
    acdc_callback_caller:returned_call_probe(Response, <<"exact-control">>, ?ACCOUNT, ?CALL, Original).

response() ->
    kz_json:from_list([{<<"Call">>, kz_json:from_list(
                        [{<<"Resource-Type">>, <<"offnet-termination">>}
                         ,{<<"Account-ID">>, ?ACCOUNT}
                         ,{<<"Call-ID">>, ?CALL}
                         ,{<<"Authorizing-ID">>, ?AUTH}
                         ,{<<"Authorizing-Type">>, <<"device">>}
                         ,{<<"Switch-Nodename">>, <<"freeswitch@fixture">>}
                         ,{<<"Custom-Channel-Vars">>, ccvs()}])}]).

ccvs() ->
    kz_json:from_list([{<<"Account-ID">>, ?ACCOUNT}
                      ,{<<"Authorizing-ID">>, ?AUTH}
                      ,{<<"Authorizing-Type">>, <<"device">>}
                      ,{<<"Resource-Type">>, <<"offnet-termination">>}
                      ,{<<"Resource-ID">>, <<"fixture-carrier">>}
                      ,{<<"Callback-ID">>, <<"fixture-callback">>}
                      ,{<<"Callback-Attempt">>, <<"1">>}
                      ,{<<"Call-Interaction-ID">>, <<"fixture-interaction">>}]).
