%%% SPDX-License-Identifier: MPL-2.0
-module(acdc_callback_policy_tests).
-include_lib("eunit/include/eunit.hrl").

-define(ACCOUNT, <<"11111111111111111111111111111111">>).
-define(QUEUE, <<"callback-test-queue">>).
-define(AUTHORITY, <<"22222222222222222222222222222222">>).
-define(REALM, <<"callback.example.invalid">>).
-define(CALLBACK_ID,
        <<"acdc-callback-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(CALL_ID, <<"33333333333333333333333333333333">>).
-define(REPLY_QUEUE, <<"callback.reply.queue">>).

request_shape_test() ->
    {ok, Request} = build(queue(), reservation(), account(), authority(), identity_normalizer()),
    ?assert(kapi_offnet_resource:req_v(Request)),
    ?assertEqual(<<"originate">>, value(<<"Resource-Type">>, Request)),
    ?assertEqual(<<"park">>, value(<<"Application-Name">>, Request)),
    ?assertEqual(<<"+12025550123">>, value(<<"To-DID">>, Request)),
    ?assertEqual(?CALL_ID, value(<<"Outbound-Call-ID">>, Request)),
    ?assertEqual(?REALM, value(<<"Account-Realm">>, Request)),
    ?assertEqual([<<"CHANNEL_ANSWER">>, <<"DTMF">>, <<"CHANNEL_DESTROY">>
                 ,<<"CHANNEL_EXECUTE_COMPLETE">>, <<"CHANNEL_EXECUTE_ERROR">>
                 ,<<"CHANNEL_BRIDGE">>],
                 value(<<"B-Leg-Events">>, Request)),
    ?assertEqual(undefined, value(<<"Route">>, Request)),
    ?assertEqual(undefined, value(<<"Endpoints">>, Request)),
    ?assertEqual(undefined, value(<<"Channel-Authorized">>, Request)),
    ?assertEqual(undefined, value(<<"Hunt-Account-ID">>, Request)),
    ?assertEqual(false, value(<<"Originate-Immediate">>, Request)),
    CCVs = value(<<"Custom-Channel-Vars">>, Request),
    ?assertEqual(?AUTHORITY, value(<<"Authorizing-ID">>, CCVs)),
    ?assertEqual(<<"device">>, value(<<"Authorizing-Type">>, CCVs)),
    ?assertEqual(?CALLBACK_ID, value(<<"Callback-ID">>, CCVs)),
    ?assertEqual(undefined, value(<<"Channel-Authorized">>, CCVs)),
    Denied = value(<<"Denied-Call-Restrictions">>, Request),
    ?assertEqual(<<"deny">>, value([<<"international">>, <<"action">>], Denied)).

local_resource_scope_is_boolean_and_account_bound_test() ->
    Enabled = kz_json:set_values(
                [{[<<"callback">>, <<"use_local_resources">>], true}
                ,{[<<"callback">>, <<"hunt_account_id">>], <<"caller-selected">>}
                ,{<<"Hunt-Account-ID">>, <<"caller-selected">>}], queue()),
    {ok, EnabledRequest} = build(Enabled, reservation(), account(), authority(), identity_normalizer()),
    ?assertEqual(?ACCOUNT, value(<<"Hunt-Account-ID">>, EnabledRequest)),
    StringTrue = kz_json:set_value([<<"callback">>, <<"use_local_resources">>],
                                   <<"true">>, Enabled),
    {ok, StringRequest} = build(StringTrue, reservation(), account(), authority(), identity_normalizer()),
    ?assertEqual(undefined, value(<<"Hunt-Account-ID">>, StringRequest)),
    OtherAccount = kz_json:set_value([<<"callback">>, <<"use_local_resources">>],
                                     <<"33333333333333333333333333333333">>, Enabled),
    {ok, OtherRequest} = build(OtherAccount, reservation(), account(), authority(), identity_normalizer()),
    ?assertEqual(undefined, value(<<"Hunt-Account-ID">>, OtherRequest)).

registration_authority_is_minimal_and_policy_checked_test() ->
    {ok, Trusted} = authorize_registration(queue(), <<"+12025550123">>
                                               ,account(), authority(), identity_normalizer()
                                               ,owned_caller_id_lookup()),
    ?assertEqual(?AUTHORITY, value(<<"id">>, Trusted)),
    ?assertEqual(<<"device">>, value(<<"type">>, Trusted)),
    ?assertEqual(?REALM, value(<<"account_realm">>, Trusted)),
    ?assertEqual([<<"account_realm">>, <<"id">>, <<"type">>], lists:sort(kz_json:get_keys(Trusted))),
    ?assertEqual({error, call_restricted},
                 authorize_registration(queue(), <<"+442079460123">>
                                       ,account(), authority(), identity_normalizer()
                                       ,owned_caller_id_lookup())),
    ?assertEqual({error, caller_id_not_owned},
                 authorize_registration(queue(), <<"+12025550123">>
                                       ,account(), authority(), identity_normalizer()
                                       ,fun(_) -> {error, not_found} end)).

caller_headers_cannot_choose_authority_test() ->
    Hostile = kz_json:set_values([{<<"Authorizing-ID">>, <<"caller-selected">>}
                                 ,{<<"Authorizing-Type">>, <<"account">>}
                                 ,{<<"Channel-Authorized">>, true}], reservation()),
    {ok, Request} = build(queue(), Hostile, account(), authority(), identity_normalizer()),
    CCVs = value(<<"Custom-Channel-Vars">>, Request),
    ?assertEqual(?AUTHORITY, value(<<"Authorizing-ID">>, CCVs)),
    ?assertEqual(<<"device">>, value(<<"Authorizing-Type">>, CCVs)),
    ?assertEqual(undefined, value(<<"Channel-Authorized">>, CCVs)).

account_and_endpoint_denials_test() ->
    Deny = restriction(<<"domestic">>, <<"deny">>),
    AccountDenied = kz_json:set_value(<<"call_restriction">>, Deny, account()),
    ?assertEqual({error, call_restricted},
                 build(queue(), reservation(), AccountDenied, authority(), identity_normalizer())),
    AuthorityDenied = kz_json:set_value(<<"call_restriction">>, Deny, authority()),
    ?assertEqual({error, call_restricted},
                 build(queue(), reservation(), account(), AuthorityDenied, identity_normalizer())).

user_identity_is_inherited_at_registration_and_each_attempt_test() ->
    Queue = inherit_queue(),
    User = with_caller_id(<<"+12025550101">>, <<"Callback User">>, user()),
    {ok, Trusted} = authorize_registration(Queue, <<"+12025550123">>, account(), User,
                                           identity_normalizer(), owned_caller_id_lookup()),
    ?assertEqual(<<"user">>, value(<<"type">>, Trusted)),
    {ok, First} = build(Queue, user_reservation(), account(), User, identity_normalizer()),
    ?assertEqual(<<"+12025550101">>, value(<<"Outbound-Caller-ID-Number">>, First)),
    ?assertEqual(<<"Callback User">>, value(<<"Outbound-Caller-ID-Name">>, First)),
    ?assertEqual(<<"user">>, value([<<"Custom-Channel-Vars">>, <<"Authorizing-Type">>], First)),
    ChangedUser = with_caller_id(<<"+12025550102">>, <<"New Caller Name">>, User),
    {ok, Second} = build(Queue, user_reservation(), account(), ChangedUser, identity_normalizer()),
    ?assertEqual(<<"+12025550102">>, value(<<"Outbound-Caller-ID-Number">>, Second)),
    ?assertEqual(<<"New Caller Name">>, value(<<"Outbound-Caller-ID-Name">>, Second)),
    ?assertEqual(undefined, value([<<"callback">>, <<"outbound_caller_id">>], Queue)).

inherited_identity_uses_account_defaults_only_for_absent_fields_test() ->
    Account = with_caller_id(<<"+12025550103">>, <<"Account Name">>, account()),
    {ok, Request} = build(inherit_queue(), user_reservation(), Account, user(), identity_normalizer()),
    ?assertEqual(<<"+12025550103">>, value(<<"Outbound-Caller-ID-Number">>, Request)),
    ?assertEqual(<<"Account Name">>, value(<<"Outbound-Caller-ID-Name">>, Request)),
    lists:foreach(fun(BadNumber) ->
                          BadUser = with_caller_id(BadNumber, <<"User Name">>, user()),
                          ?assertEqual({error, invalid_inherited_caller_id},
                                       build(inherit_queue(), user_reservation(), Account,
                                             BadUser, identity_normalizer()))
                  end, [<<>>, null, <<"sofia/gateway/123">>, <<"+123\n">>]),
    ?assertEqual({error, invalid_inherited_caller_id},
                 build(inherit_queue(), user_reservation(), account(), user(), identity_normalizer())).

identity_source_preserves_legacy_override_and_explicitly_switches_to_inherit_test() ->
    Authority = with_caller_id(<<"+12025550104">>, <<"Device Identity">>, authority()),
    {ok, Legacy} = build(queue(), reservation(), account(), Authority, identity_normalizer()),
    ?assertEqual(<<"+12025550100">>, value(<<"Outbound-Caller-ID-Number">>, Legacy)),
    Inherit = kz_json:set_value([<<"callback">>, <<"caller_id_source">>], <<"inherit">>, queue()),
    {ok, Inherited} = build(Inherit, reservation(), account(), Authority, identity_normalizer()),
    ?assertEqual(<<"+12025550104">>, value(<<"Outbound-Caller-ID-Number">>, Inherited)),
    NoOverride = kz_json:delete_key([<<"callback">>, <<"outbound_caller_id">>], queue()),
    {ok, Defaulted} = build(NoOverride, reservation(), account(), Authority, identity_normalizer()),
    ?assertEqual(<<"+12025550104">>, value(<<"Outbound-Caller-ID-Number">>, Defaulted)),
    BadSource = kz_json:set_value([<<"callback">>, <<"caller_id_source">>], <<"guess">>, queue()),
    ?assertEqual({error, invalid_caller_id_source},
                 build(BadSource, reservation(), account(), Authority, identity_normalizer())).

custom_owned_number_inherits_name_without_text_entry_test() ->
    Queue = kz_json:set_values([{[<<"callback">>, <<"caller_id_source">>], <<"custom">>}
                                ,{[<<"callback">>, <<"outbound_caller_id">>, <<"number">>], <<"+12025550105">>}],
                               inherit_queue()),
    User = with_caller_id(<<"+12025550101">>, <<"User Name">>, user()),
    {ok, Request} = build(Queue, user_reservation(), account(), User, identity_normalizer()),
    ?assertEqual(<<"+12025550105">>, value(<<"Outbound-Caller-ID-Number">>, Request)),
    ?assertEqual(<<"User Name">>, value(<<"Outbound-Caller-ID-Name">>, Request)),
    ?assertEqual({error, invalid_outbound_caller_id},
                 build(kz_json:delete_key([<<"callback">>, <<"outbound_caller_id">>], Queue),
                       user_reservation(), account(), User, identity_normalizer())).

inherited_user_identity_still_requires_ownership_and_enabled_context_test() ->
    User = with_caller_id(<<"+12025550101">>, <<"User Name">>, user()),
    NotOwned = fun(_) -> {ok, <<"33333333333333333333333333333333">>, []} end,
    ?assertEqual({error, caller_id_not_owned},
                 authorize_registration(inherit_queue(), <<"+12025550123">>, account(), User,
                                        identity_normalizer(), NotOwned)),
    ?assertEqual({error, caller_id_not_owned},
                 build_with_lookup(inherit_queue(), user_reservation(), account(), User,
                                   identity_normalizer(), NotOwned)),
    DisabledUser = kz_json:set_value(<<"enabled">>, false, User),
    ?assertEqual({error, invalid_authority_context},
                 build(inherit_queue(), user_reservation(), account(), DisabledUser, identity_normalizer())),
    DeniedUser = kz_json:set_value(<<"call_restriction">>, restriction(<<"domestic">>, <<"deny">>), User),
    ?assertEqual({error, call_restricted},
                 build(inherit_queue(), user_reservation(), account(), DeniedUser, identity_normalizer())),
    ForeignUser = kz_json:set_value(<<"pvt_account_id">>, <<"33333333333333333333333333333333">>, User),
    ?assertEqual({error, invalid_authority_context},
                 build(inherit_queue(), user_reservation(), account(), ForeignUser, identity_normalizer())).

user_display_name_fallback_test() ->
    User = kz_json:set_values([{[<<"caller_id">>, <<"external">>, <<"number">>], <<"+12025550101">>}
                               ,{<<"first_name">>, <<"Callback">>}, {<<"last_name">>, <<"User">>}], user()),
    {ok, Request} = build(inherit_queue(), user_reservation(), account(), User, identity_normalizer()),
    ?assertEqual(<<"Callback User">>, value(<<"Outbound-Caller-ID-Name">>, Request)).

current_policy_change_is_rechecked_test() ->
    {ok, _} = build(queue(), reservation(), account(), authority(), identity_normalizer()),
    Changed = kz_json:set_value(<<"call_restriction">>, restriction(<<"domestic">>, <<"deny">>), authority()),
    ?assertEqual({error, call_restricted},
                 build(queue(), reservation(), account(), Changed, identity_normalizer())).

caller_id_ownership_is_rechecked_test() ->
    {ok, Request} = build(queue(), reservation(), account(), authority(), identity_normalizer()),
    ?assertEqual(<<"+12025550100">>, value(<<"Outbound-Caller-ID-Number">>, Request)),
    OtherAccount = <<"33333333333333333333333333333333">>,
    Unowned = fun(_) -> {ok, OtherAccount, []} end,
    ?assertEqual({error, caller_id_not_owned},
                 build_with_lookup(queue(), reservation(), account(), authority()
                                  ,identity_normalizer(), Unowned)),
    Missing = fun(_) -> {error, not_found} end,
    ?assertEqual({error, caller_id_not_owned},
                 build_with_lookup(queue(), reservation(), account(), authority()
                                  ,identity_normalizer(), Missing)),
    Broken = fun(_) -> error(number_store_unavailable) end,
    ?assertEqual({error, caller_id_not_owned},
                 build_with_lookup(queue(), reservation(), account(), authority()
                                  ,identity_normalizer(), Broken)).

missing_or_changed_authority_fails_closed_test() ->
    ?assertEqual({error, account_unavailable},
                 build_result(queue(), reservation(), {error, not_found}, {ok, authority()}, identity_normalizer())),
    ?assertEqual({error, authority_unavailable},
                 build_result(queue(), reservation(), {ok, account()}, {error, not_found}, identity_normalizer())),
    ChangedQueue = kz_json:set_value([<<"callback">>, <<"outbound_authority">>, <<"id">>]
                                    ,<<"33333333333333333333333333333333">>, queue()),
    ?assertEqual({error, invalid_authority_context},
                 build(ChangedQueue, reservation(), account(), authority(), identity_normalizer())),
    ChangedRealm = kz_json:set_value(<<"realm">>, <<"new.example.invalid">>, account()),
    ?assertEqual({error, invalid_authority_context},
                 build(queue(), reservation(), ChangedRealm, authority(), identity_normalizer())).

owned_and_external_numbers_use_same_safe_offnet_shape_test() ->
    Owned = kz_json:set_value(<<"number">>, <<"1001">>, reservation()),
    OwnedNormalize = fun(<<"1001">>) -> <<"+12025550101">> end,
    {ok, OwnedRequest} = build(queue(), Owned, account(), authority(), OwnedNormalize),
    External = kz_json:set_value(<<"number">>, <<"+442079460123">>, reservation()),
    AllowAccount = kz_json:delete_key(<<"call_restriction">>, account()),
    AllowAuthority = kz_json:delete_key(<<"call_restriction">>, authority()),
    {ok, ExternalRequest} = build(queue(), External, AllowAccount, AllowAuthority, identity_normalizer()),
    lists:foreach(fun(Request) ->
                          ?assertEqual(<<"originate">>, value(<<"Resource-Type">>, Request)),
                          ?assertEqual(<<"park">>, value(<<"Application-Name">>, Request)),
                          ?assertEqual(undefined, value(<<"Route">>, Request)),
                          ?assertEqual(undefined, value(<<"Channel-Authorized">>, Request))
                  end, [OwnedRequest, ExternalRequest]),
    ?assertEqual(<<"+12025550101">>, value(<<"To-DID">>, OwnedRequest)),
    ?assertEqual(<<"+442079460123">>, value(<<"To-DID">>, ExternalRequest)).

invalid_number_and_context_test() ->
    BadNormalizer = fun(_) -> <<"sofia/internal/1001">> end,
    ?assertEqual({error, invalid_number},
                 build(queue(), reservation(), account(), authority(), BadNormalizer)),
    WrongStatus = kz_json:set_value(<<"status">>, <<"queued">>, reservation()),
    ?assertEqual({error, invalid_authority_context},
                 build(queue(), WrongStatus, account(), authority(), identity_normalizer())).

response_control_values_test() ->
    ReadyResource = kz_json:from_list([{<<"Originate-UUID">>, <<"originate-uuid">>}
                                     ,{<<"Msg-ID">>, <<"inner-resource-message">>}
                                     ,{<<"Originate-Queue">>, <<"originate.control.queue">>}]),
    Ready = response(<<"READY">>, [{<<"Resource-Response">>, ReadyResource}]),
    ?assertEqual({ok, #{call_id => ?CALL_ID
                       ,originate_uuid => <<"originate-uuid">>
                       ,originate_queue => <<"originate.control.queue">>
                       ,originate_msg_id => <<"inner-resource-message">>
                       ,response => ready}},
                 acdc_callback_policy:parse_response(?CALL_ID, ?REPLY_QUEUE, Ready)),
    lists:foreach(fun(BadMsg) ->
                          Path = [<<"Resource-Response">>, <<"Msg-ID">>],
                          BadReady = kz_json:set_value(Path, BadMsg, kz_json:delete_key(Path, Ready)),
                          ?assertEqual({error, invalid_ready_response},
                                       acdc_callback_policy:parse_response(?CALL_ID, ?REPLY_QUEUE, BadReady))
                  end, [undefined, <<>>, <<"contains space">>, <<"bad\nmessage">>]),
    Nested = response(<<"SUCCESS">>,
                      [{<<"Resource-Response">>, kz_json:from_list([{<<"Control-Queue">>, <<"control.nested">>}])}]),
    ?assertEqual({ok, #{call_id => ?CALL_ID, control_queue => <<"control.nested">>, response => success}},
                 acdc_callback_policy:parse_response(?CALL_ID, ?REPLY_QUEUE, Nested)),
    ?assertEqual({error, stale_response},
                 acdc_callback_policy:parse_response(<<"another-call">>, ?REPLY_QUEUE, Nested)),
    WrongMsg = kz_json:set_value(<<"Msg-ID">>, <<"another-message">>, Nested),
    ?assertEqual({error, stale_response},
                 acdc_callback_policy:parse_response(?CALL_ID, ?REPLY_QUEUE, WrongMsg)),
    ?assertEqual({error, invalid_response},
                 acdc_callback_policy:parse_response(undefined, ?REPLY_QUEUE, Nested)),
    ?assertEqual({error, missing_control_queue},
                 acdc_callback_policy:parse_response(?CALL_ID, ?REPLY_QUEUE, response(<<"SUCCESS">>, []))),
    ?assertEqual({error, invalid_ready_response},
                 acdc_callback_policy:parse_response(?CALL_ID, ?REPLY_QUEUE, response(<<"READY">>, []))),
    ?assertEqual({error, routing_failed},
                 acdc_callback_policy:parse_response(?CALL_ID, ?REPLY_QUEUE
                                                    ,response(<<"NO_ROUTE_DESTINATION">>, []))).

build(Queue, Reservation, Account, Authority, Normalize) ->
    build_result(Queue, Reservation, {ok, Account}, {ok, Authority}, Normalize).

build_result(Queue, Reservation, AccountResult, AuthorityResult, Normalize) ->
    build_result_with_lookup(Queue, Reservation, AccountResult, AuthorityResult
                            ,Normalize, owned_caller_id_lookup()).

build_with_lookup(Queue, Reservation, Account, Authority, Normalize, LookupCallerId) ->
    build_result_with_lookup(Queue, Reservation, {ok, Account}, {ok, Authority}
                            ,Normalize, LookupCallerId).

build_result_with_lookup(Queue, Reservation, AccountResult, AuthorityResult
                        ,Normalize, LookupCallerId) ->
    Classify = fun(Number) ->
                       case Number of
                           <<"+44", _/binary>> -> <<"international">>;
                           _ -> <<"domestic">>
                       end
               end,
    acdc_callback_policy:build_request_with(?ACCOUNT, Queue, Reservation, ?REPLY_QUEUE
                                           ,AccountResult, AuthorityResult, Normalize, Classify
                                           ,LookupCallerId).

authorize_registration(Queue, Number, Account, Authority, Normalize, LookupCallerId) ->
    Classify = fun(Value) ->
                       case Value of
                           <<"+44", _/binary>> -> <<"international">>;
                           _ -> <<"domestic">>
                       end
               end,
    acdc_callback_policy:authorize_registration_with(?ACCOUNT, Queue, Number
                                                     ,{ok, Account}, {ok, Authority}
                                                     ,Normalize, Classify, LookupCallerId).

queue() ->
    kz_json:from_list([{<<"_id">>, ?QUEUE}
                      ,{<<"pvt_account_id">>, ?ACCOUNT}
                      ,{<<"pvt_type">>, <<"queue">>}
                      ,{<<"callback">>, kz_json:from_list(
                                           [{<<"outbound_authority">>, kz_json:from_list(
                                                                          [{<<"id">>, ?AUTHORITY}
                                                                          ,{<<"type">>, <<"device">>}])}
                                           ,{<<"outbound_caller_id">>, kz_json:from_list(
                                                                          [{<<"number">>, <<"+12025550100">>}
                                                                          ,{<<"name">>, <<"Callback Service">>}])}
                                           ,{<<"originate_timeout">>, 60}])}]).

reservation() ->
    kz_json:from_list([{<<"_id">>, ?CALLBACK_ID}
                      ,{<<"pvt_account_id">>, ?ACCOUNT}
                      ,{<<"pvt_type">>, <<"acdc_callback">>}
                      ,{<<"queue_id">>, ?QUEUE}
                      ,{<<"status">>, <<"dialing">>}
                      ,{<<"number">>, <<"+12025550123">>}
                      ,{<<"attempts">>, 1}
                      ,{<<"pvt_caller_call_id">>, ?CALL_ID}
                      ,{<<"pvt_authority_id">>, ?AUTHORITY}
                      ,{<<"pvt_authority_type">>, <<"device">>}
                      ,{<<"pvt_account_realm">>, ?REALM}]).

account() ->
    kz_json:from_list([{<<"_id">>, ?ACCOUNT}
                      ,{<<"pvt_account_id">>, ?ACCOUNT}
                      ,{<<"pvt_type">>, <<"account">>}
                      ,{<<"enabled">>, true}
                      ,{<<"realm">>, ?REALM}
                      ,{<<"call_restriction">>, restriction(<<"international">>, <<"deny">>)}]).

authority() ->
    kz_json:from_list([{<<"_id">>, ?AUTHORITY}
                      ,{<<"pvt_account_id">>, ?ACCOUNT}
                      ,{<<"pvt_type">>, <<"device">>}
                      ,{<<"Endpoint-Type">>, <<"device">>}
                      ,{<<"enabled">>, true}
                      ,{<<"call_restriction">>, restriction(<<"international">>, <<"deny">>)}]).

restriction(Classification, Action) ->
    kz_json:from_list([{Classification, kz_json:from_list([{<<"action">>, Action}])}]).

inherit_queue() ->
    kz_json:set_values([{[<<"callback">>, <<"caller_id_source">>], <<"inherit">>}
                        ,{[<<"callback">>, <<"outbound_authority">>, <<"type">>], <<"user">>}],
                       kz_json:delete_key([<<"callback">>, <<"outbound_caller_id">>], queue())).

user_reservation() ->
    kz_json:set_value(<<"pvt_authority_type">>, <<"user">>, reservation()).

user() ->
    kz_json:set_value(<<"pvt_type">>, <<"user">>, kz_json:delete_key(<<"Endpoint-Type">>, authority())).

with_caller_id(Number, Name, Doc) ->
    kz_json:set_value([<<"caller_id">>, <<"external">>, <<"number">>], Number,
                      kz_json:set_value([<<"caller_id">>, <<"external">>, <<"name">>], Name, Doc),
                      #{'keep_null' => true}).

identity_normalizer() -> fun(Number) -> Number end.

owned_caller_id_lookup() ->
    fun(_) -> {ok, ?ACCOUNT, []} end.

response(Message, Extra) ->
    kz_json:from_list([{<<"Response-Message">>, Message}
                      ,{<<"Call-ID">>, ?CALL_ID}
                      ,{<<"Msg-ID">>, ?REPLY_QUEUE}
                       | Extra ++ kz_api:default_headers(<<"resource">>, <<"offnet_resp">>
                                                        ,<<"callback-policy-test">>, <<"1">>)]).

value(Key, JObj) -> kz_json:get_value(Key, JObj).
