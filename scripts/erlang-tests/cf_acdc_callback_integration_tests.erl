%%% SPDX-License-Identifier: MPL-2.0
-module(cf_acdc_callback_integration_tests).

-include_lib("eunit/include/eunit.hrl").

-define(ACCOUNT, <<"0123456789abcdef0123456789abcdef">>).
-define(QUEUE, <<"queue-1">>).
-define(CALL, <<"original-call-1">>).
-define(REQUEST, <<"fedcba9876543210fedcba9876543210">>).
-define(PAUSE, <<"0123456789abcdef0123456789abcdef0123456789abcdef">>).

register_request_is_minimal_and_protocol_valid_test() ->
    Context = context(),
    Request0 = cf_acdc_member:callback_test_request(
                 Context, <<"register">>
                ,[{<<"Pause-ID">>, ?PAUSE}, {<<"Number">>, <<"+12025550123">>}]),
    ?assertEqual('undefined', props:get_value(<<"Call">>, Request0)),
    ?assertEqual('undefined', props:get_value(<<"Outbound-Authority">>, Request0)),
    ?assertEqual(?PAUSE, props:get_value(<<"Pause-ID">>, Request0)),
    Request = [{<<"Server-ID">>, <<"original-controller-queue">>}
              ,{<<"Event-Category">>, <<"acdc_callback">>}
              ,{<<"Event-Name">>, <<"request">>}
              ,{<<"Msg-ID">>, ?REQUEST} | Request0],
    ?assert(kapi_acdc_callback:request_v(Request)).

response_requires_full_scope_and_valid_wire_shape_test() ->
    Response = response(<<"pause">>, <<"paused">>, [{<<"Pause-ID">>, ?PAUSE}]),
    ?assertEqual({ok, <<"pause">>, <<"paused">>, ?PAUSE, 'undefined'}
                ,cf_acdc_member:callback_test_response(Response, context())),
    StaleRequest = kz_json:set_value(<<"Request-ID">>, <<"00000000000000000000000000000000">>, Response),
    ?assertEqual(nomatch, cf_acdc_member:callback_test_response(StaleRequest, context())),
    Malformed = kz_json:delete_key(<<"Pause-ID">>, Response),
    ?assertEqual(nomatch, cf_acdc_member:callback_test_response(Malformed, context())).

english_defaults_and_foreign_language_fail_closed_test() ->
    Empty = kz_json:new(),
    {ok, Defaults} = cf_acdc_member:callback_test_media(Empty, <<"en-US">>),
    ?assertEqual(<<"acdc-callback-offer-6">>, maps:get(offer, Defaults)),
    ?assertEqual(<<"acdc-callback-menu-current">>, maps:get(menu, Defaults)),
    ?assertEqual(<<"acdc-callback-success">>, maps:get(success, Defaults)),
    ?assertMatch({error, {missing_media, offer}}
                ,cf_acdc_member:callback_test_media(Empty, <<"es-ES">>)),

    Configured = kz_json:set_values(
                   [{[<<"callback">>, <<"entry_key">>], <<"9">>}
                   ,{[<<"callback">>, <<"allow_alternate_number">>], true}
                    | [{[<<"callback">>, <<"media">>, Key], <<"account-media-", Key/binary>>}
                    || Key <- [<<"offer">>, <<"menu">>, <<"number_readback">>
                              ,<<"confirmation">>, <<"success">>]]], Empty),
    {ok, Spanish} = cf_acdc_member:callback_test_media(Configured, <<"es_ES">>),
    ?assertEqual(<<"account-media-menu">>, maps:get(menu, Spanish)),

    AlternateEnglish = kz_json:set_values([{[<<"callback">>, <<"entry_key">>], <<"3">>}
                                          ,{[<<"callback">>, <<"allow_alternate_number">>], true}], Empty),
    {ok, AlternateDefaults} = cf_acdc_member:callback_test_media(AlternateEnglish, <<"en-us">>),
    ?assertEqual(<<"acdc-callback-offer-3">>, maps:get(offer, AlternateDefaults)),
    ?assertEqual(<<"acdc-callback-menu-alternate">>, maps:get(menu, AlternateDefaults)).

context() ->
    #{account_id => ?ACCOUNT
     ,queue_id => ?QUEUE
     ,call_id => ?CALL
     ,request_id => ?REQUEST
     ,pause_id => ?PAUSE}.

response(Operation, Status, Extra) ->
    kz_json:from_list(
      [{<<"Event-Category">>, <<"acdc_callback">>}
      ,{<<"Event-Name">>, <<"response">>}
      ,{<<"Account-ID">>, ?ACCOUNT}
      ,{<<"Queue-ID">>, ?QUEUE}
      ,{<<"Call-ID">>, ?CALL}
      ,{<<"Request-ID">>, ?REQUEST}
      ,{<<"Operation">>, Operation}
      ,{<<"Status">>, Status}
      ,{<<"Msg-ID">>, ?REQUEST}
      ,{<<"App-Name">>, <<"callback-integration-test">>}
      ,{<<"App-Version">>, <<"1">>} | Extra]).
