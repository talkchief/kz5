%%% SPDX-License-Identifier: MPL-2.0
%%% Builds, but never publishes, policy-checked ACDC callback originate requests.
%%% The queue coordinator owns reservation/lease state and supplies only a
%%% trusted, account-owned outbound authority from the current queue document.
-module(acdc_callback_policy).

-export([authorize_registration/3, build_request/4, parse_response/3]).

-ifdef(TEST).
-export([authorize_registration_with/8, build_request_with/9]).
-endif.

-include("acdc.hrl").

-define(AUTHORITY_PATH, [<<"callback">>, <<"outbound_authority">>]).
-define(CALLER_ID_PATH, [<<"callback">>, <<"outbound_caller_id">>]).
-define(B_LEG_EVENTS, [<<"CHANNEL_ANSWER">>, <<"DTMF">>, <<"CHANNEL_DESTROY">>
                      ,<<"CHANNEL_EXECUTE_COMPLETE">>, <<"CHANNEL_EXECUTE_ERROR">>
                      ,<<"CHANNEL_BRIDGE">>]).
-define(AUTHORITY_TYPES, [<<"device">>, <<"user">>]).

-type request_result() :: {'ok', kz_json:object()} | {'error', atom()}.
-type response_result() ::
        {'ok', #{'call_id' := kz_term:ne_binary()
                ,'originate_queue' := kz_term:ne_binary()
                ,'originate_uuid' := kz_term:ne_binary()
                ,'response' := 'ready'}} |
        {'ok', #{'call_id' := kz_term:ne_binary()
                ,'control_queue' := kz_term:ne_binary()
                ,'response' := 'success'}} |
        {'error', atom()}.

%% QueueDoc is trusted configuration loaded by the queue coordinator. The
%% reservation's private authority fields must match it exactly; caller input
%% and caller-ID headers are never accepted as authorization.
-spec authorize_registration(kz_term:ne_binary(), kz_json:object(), kz_term:ne_binary()) ->
          {'ok', kz_json:object()} | {'error', atom()}.
authorize_registration(AccountId, QueueDoc, Number) ->
    case valid_account_id(AccountId) andalso kz_json:is_json_object(QueueDoc) of
        'false' -> {'error', 'invalid_authority_context'};
        'true' ->
            {AccountResult, AuthorityResult} = fetch_authority(AccountId, QueueDoc),
            case acdc_callback_internal:resolve(AccountId, Number) of
                'not_internal' -> authorize_registration_with(AccountId, QueueDoc, Number
                                        ,AccountResult, AuthorityResult
                                        ,fun(Value) -> knm_converters:normalize(Value, AccountId) end
                                        ,fun knm_converters:classify/1
                                        ,fun knm_numbers:lookup_account/1);
                {'error', _}=Error -> Error;
                {'ok', Target} ->
                    case validate_authority_context(AccountId, QueueDoc, AccountResult, AuthorityResult) of
                        {'error', _}=Error -> Error;
                        {'ok', Context} ->
                            case restricted(<<"internal">>, maps:get('account', Context), maps:get('authority', Context)) of
                                'true' -> {'error', 'call_restricted'};
                                'false' -> {'ok', kz_json:set_value(<<"internal_target">>, Target, trusted_authority(Context))}
                            end
                    end
            end
    end.

-spec build_request(kz_term:ne_binary(), kz_json:object(), kz_json:object(), kz_term:ne_binary()) ->
          request_result().
build_request(AccountId, QueueDoc, Reservation, ReplyQueue) ->
    case valid_account_id(AccountId) andalso kz_json:is_json_object(QueueDoc)
        andalso kz_json:is_json_object(Reservation) andalso valid_text(ReplyQueue, 512) of
        'false' -> {'error', 'invalid_authority_context'};
        'true' ->
            {AccountResult, AuthorityResult} = fetch_authority(AccountId, QueueDoc),
            case kz_json:get_value(<<"pvt_internal_target">>, Reservation) of
                'undefined' -> build_request_with(AccountId, QueueDoc, Reservation, ReplyQueue
                              ,AccountResult, AuthorityResult
                              ,fun(Number) -> knm_converters:normalize(Number, AccountId) end
                              ,fun knm_converters:classify/1
                              ,fun knm_numbers:lookup_account/1);
                Target -> build_internal_request(AccountId, QueueDoc, Reservation, ReplyQueue,
                                                 AccountResult, AuthorityResult, Target)
            end
    end.

build_internal_request(AccountId, QueueDoc, Reservation, ReplyQueue, AccountResult, AuthorityResult, Target) ->
    case validate_authority_context(AccountId, QueueDoc, AccountResult, AuthorityResult) of
        {'error', _}=Error -> Error;
        {'ok', Context} ->
            case validate_reservation_context(AccountId, QueueDoc, Reservation, ReplyQueue, Context) of
                {'error', _}=Error -> Error;
                'ok' ->
                    case restricted(<<"internal">>, maps:get('account', Context), maps:get('authority', Context)) of
                        'true' -> {'error', 'call_restricted'};
                        'false' -> acdc_callback_internal:build_request(AccountId, QueueDoc, Reservation,
                                                                        ReplyQueue, Context, Target)
                    end
            end
    end.

fetch_authority(AccountId, QueueDoc) ->
    AccountDb = kzs_util:format_account_db(AccountId),
    AccountResult = kz_datamgr:open_doc(AccountDb, AccountId),
    AuthorityId = kz_json:get_ne_binary_value(?AUTHORITY_PATH ++ [<<"id">>], QueueDoc),
    AuthorityType = kz_json:get_ne_binary_value(?AUTHORITY_PATH ++ [<<"type">>], QueueDoc),
    AuthorityResult = case {valid_text(AuthorityId, 128), AuthorityType} of
                          {'true', <<"user">>} -> kz_datamgr:open_doc(AccountDb, AuthorityId);
                          {'true', <<"device">>} -> kz_endpoint:get(AuthorityId, AccountDb, [{'no_cache', 'true'}]);
                          _ -> {'error', 'invalid_authority'}
                      end,
    {AccountResult, AuthorityResult}.

%% The offnet response is deliberately reduced to the two control values the
%% callback FSM needs. It never returns the raw response, endpoint or headers.
-spec parse_response(kz_term:ne_binary(), kz_term:ne_binary(), kz_json:object()) -> response_result().
parse_response(ExpectedCallId, ExpectedMsgId, Response) ->
    case valid_text(ExpectedCallId, 512) andalso valid_text(ExpectedMsgId, 128)
        andalso kz_json:is_json_object(Response)
        andalso kapi_offnet_resource:resp_v(Response) of
        'false' -> {'error', 'invalid_response'};
        'true' -> parse_valid_response(ExpectedCallId, ExpectedMsgId, Response)
    end.

parse_valid_response(ExpectedCallId, ExpectedMsgId, Response) ->
    MsgId = kz_api:msg_id(Response),
    CallId = kz_json:get_ne_binary_value(<<"Call-ID">>, Response),
    ResponseMessage = kz_json:get_ne_binary_value(<<"Response-Message">>, Response),
    ResourceResponse = kz_json:get_json_value(<<"Resource-Response">>, Response, kz_json:new()),
    ControlQueue = kz_json:get_first_defined(
                     [<<"Control-Queue">>
                     ,[<<"Resource-Response">>, <<"Control-Queue">>]
                     ,[<<"Resource-Response">>, <<"Outbound-Call-Control-Queue">>]
                     ,[<<"Call">>, <<"Control-Queue">>]
                     ], Response),
    OriginateUUID = kz_json:get_ne_binary_value(<<"Originate-UUID">>, ResourceResponse),
    OriginateQueue = kz_json:get_ne_binary_value(<<"Originate-Queue">>, ResourceResponse),
    ResourceMsgId = kz_api:msg_id(ResourceResponse),
    case {MsgId =:= ExpectedMsgId, response_state(ResponseMessage)} of
        {'false', _} -> {'error', 'stale_response'};
        {'true', 'ready'} -> parse_ready_response(ExpectedCallId, OriginateUUID, OriginateQueue, ResourceMsgId);
        {'true', 'success'} when CallId =/= ExpectedCallId -> {'error', 'stale_response'};
        {'true', 'success'} -> parse_success_response(CallId, ControlQueue);
        {'true', 'failed'} -> {'error', 'routing_failed'}
    end.

parse_ready_response(CallId, OriginateUUID, OriginateQueue, ResourceMsgId) ->
    %% Stepswitch correlates its outer response with the offnet request, but
    %% creates a different Msg-ID for the inner resource originate transaction.
    %% FreeSWITCH stores the latter; persisting the outer ID makes later
    %% authoritative settlement checks fail with CORRELATION_MISMATCH.
    case valid_text(OriginateUUID, 128) andalso valid_text(OriginateQueue, 512)
        andalso matches(ResourceMsgId, <<"^[!-~]{1,512}$">>) of
        'true' -> {'ok', #{'call_id' => CallId
                          ,'originate_uuid' => OriginateUUID
                          ,'originate_queue' => OriginateQueue
                          ,'originate_msg_id' => ResourceMsgId
                          ,'response' => 'ready'}};
        'false' -> {'error', 'invalid_ready_response'}
    end.

parse_success_response(CallId, ControlQueue) ->
    case valid_text(ControlQueue, 512) of
        'true' -> {'ok', #{'call_id' => CallId
                          ,'control_queue' => ControlQueue
                          ,'response' => 'success'}};
        'false' -> {'error', 'missing_control_queue'}
    end.

response_state(<<"READY">>) -> 'ready';
response_state(<<"SUCCESS">>) -> 'success';
response_state(_) -> 'failed'.

-spec authorize_registration_with(kz_term:ne_binary(), kz_json:object(), kz_term:ne_binary()
                                  ,{'ok', kz_json:object()} | {'error', any()}
                                  ,{'ok', kz_json:object()} | {'error', any()}
                                  ,fun((kz_term:ne_binary()) -> any())
                                  ,fun((kz_term:ne_binary()) -> any())
                                  ,fun((kz_term:ne_binary()) -> any())) ->
          {'ok', kz_json:object()} | {'error', atom()}.
authorize_registration_with(AccountId, QueueDoc, Number, AccountResult, AuthorityResult
                            ,Normalize, Classify, LookupCallerId) ->
    case validate_authority_context(AccountId, QueueDoc, AccountResult, AuthorityResult) of
        {'error', _}=Error -> Error;
        {'ok', Context} ->
            case resolve_caller_id(Context, QueueDoc) of
                {'error', _}=Error -> Error;
                {'ok', EffectiveQueueDoc} ->
                    case authorize_number(Context, EffectiveQueueDoc, Number, Normalize, Classify, LookupCallerId) of
                        {'error', _}=Error -> Error;
                        {'ok', _, _} -> {'ok', trusted_authority(Context)}
                    end
            end
    end.

trusted_authority(Context) ->
    kz_json:from_list([{<<"id">>, maps:get('authority_id', Context)}
                      ,{<<"type">>, maps:get('authority_type', Context)}
                      ,{<<"account_realm">>, maps:get('realm', Context)}]).

-spec build_request_with(kz_term:ne_binary(), kz_json:object(), kz_json:object(), kz_term:ne_binary()
                        ,{'ok', kz_json:object()} | {'error', any()}
                        ,{'ok', kz_json:object()} | {'error', any()}
                        ,fun((kz_term:ne_binary()) -> any())
                        ,fun((kz_term:ne_binary()) -> any())
                        ,fun((kz_term:ne_binary()) -> any())) -> request_result().
build_request_with(AccountId, QueueDoc, Reservation, ReplyQueue
                  ,AccountResult, AuthorityResult, Normalize, Classify, LookupCallerId) ->
    case validate_authority_context(AccountId, QueueDoc, AccountResult, AuthorityResult) of
        {'error', _}=Error -> Error;
        {'ok', Context} ->
            case validate_reservation_context(AccountId, QueueDoc, Reservation, ReplyQueue, Context) of
                {'error', _}=Error -> Error;
                'ok' -> build_policy_checked_request(Context, QueueDoc, Reservation, ReplyQueue
                                                    ,Normalize, Classify, LookupCallerId)
            end
    end.

validate_authority_context(AccountId, QueueDoc, {'ok', AccountDoc}, {'ok', AuthorityDoc}) ->
    AuthorityId = kz_json:get_ne_binary_value(?AUTHORITY_PATH ++ [<<"id">>], QueueDoc),
    AuthorityType = kz_json:get_ne_binary_value(?AUTHORITY_PATH ++ [<<"type">>], QueueDoc),
    Realm = kzd_accounts:realm(AccountDoc),
    AuthorityDocType = kz_json:get_first_defined([<<"Endpoint-Type">>, <<"pvt_type">>], AuthorityDoc),
    Checks = [valid_account_id(AccountId)
             ,kz_json:is_json_object(QueueDoc)
             ,kz_doc:account_id(QueueDoc) =:= AccountId
             ,kz_doc:type(QueueDoc) =:= <<"queue">>
             ,lists:member(AuthorityType, ?AUTHORITY_TYPES)
             ,valid_text(Realm, 253)
             ,kz_doc:id(AccountDoc) =:= AccountId
             ,kz_doc:type(AccountDoc) =:= <<"account">>
             ,kzd_accounts:is_enabled(AccountDoc)
             ,kz_doc:id(AuthorityDoc) =:= AuthorityId
             ,kz_doc:account_id(AuthorityDoc) =:= AccountId
             ,AuthorityDocType =:= AuthorityType
             ,kz_json:is_true(<<"enabled">>, AuthorityDoc, 'true')
             ],
    case lists:all(fun(Check) -> Check =:= 'true' end, Checks) of
        'true' -> {'ok', #{'account' => AccountDoc, 'authority' => AuthorityDoc
                          ,'authority_id' => AuthorityId, 'authority_type' => AuthorityType
                          ,'realm' => Realm}};
        'false' -> {'error', 'invalid_authority_context'}
    end;
validate_authority_context(_, _, {'error', _}, _) -> {'error', 'account_unavailable'};
validate_authority_context(_, _, _, {'error', _}) -> {'error', 'authority_unavailable'}.

validate_reservation_context(AccountId, QueueDoc, Reservation, ReplyQueue, Context) ->
    QueueId = kz_doc:id(QueueDoc),
    Checks = [kz_json:is_json_object(Reservation)
             ,valid_text(ReplyQueue, 512)
             ,kz_doc:account_id(Reservation) =:= AccountId
             ,kz_doc:type(Reservation) =:= <<"acdc_callback">>
             ,QueueId =:= kz_json:get_ne_binary_value(<<"queue_id">>, Reservation)
             ,kz_json:get_ne_binary_value(<<"status">>, Reservation) =:= <<"dialing">>
             ,maps:get('authority_id', Context)
                  =:= kz_json:get_ne_binary_value(<<"pvt_authority_id">>, Reservation)
             ,maps:get('authority_type', Context)
                  =:= kz_json:get_ne_binary_value(<<"pvt_authority_type">>, Reservation)
             ,maps:get('realm', Context)
                  =:= kz_json:get_ne_binary_value(<<"pvt_account_realm">>, Reservation)
             ],
    case lists:all(fun(Check) -> Check =:= 'true' end, Checks) of
        'true' -> 'ok';
        'false' -> {'error', 'invalid_authority_context'}
    end.

build_policy_checked_request(Context, QueueDoc, Reservation, ReplyQueue
                            ,Normalize, Classify, LookupCallerId) ->
    case resolve_caller_id(Context, QueueDoc) of
        {'error', _}=Error -> Error;
        {'ok', EffectiveQueueDoc} ->
            build_resolved_request(Context, EffectiveQueueDoc, Reservation, ReplyQueue
                                   ,Normalize, Classify, LookupCallerId)
    end.

%% Resolve from the freshly loaded authority/account on registration AND each
%% attempt. Never persist copied user identity: later caller-ID/restriction
%% changes must take effect without editing every queue. Absence of the new
%% selector preserves legacy explicit caller identity.
resolve_caller_id(Context, QueueDoc) ->
    Source = kz_json:get_value([<<"callback">>, <<"caller_id_source">>], QueueDoc),
    Explicit = kz_json:get_value(?CALLER_ID_PATH, QueueDoc),
    case {Source, Explicit} of
        {<<"inherit">>, _} -> resolve_inherited_caller_id(Context, QueueDoc);
        {'undefined', 'undefined'} -> resolve_inherited_caller_id(Context, QueueDoc);
        {<<"custom">>, _} -> resolve_custom_caller_id(Context, QueueDoc);
        {'undefined', _} -> resolve_custom_caller_id(Context, QueueDoc);
        _ -> {'error', 'invalid_caller_id_source'}
    end.

resolve_inherited_caller_id(Context, QueueDoc) ->
    Number = inherited_caller_id_field(<<"number">>, Context),
    Name = inherited_caller_id_name(Context),
    case valid_number(Number) andalso valid_text(Name, 128) of
        'false' -> {'error', 'invalid_inherited_caller_id'};
        'true' -> {'ok', kz_json:set_value(?CALLER_ID_PATH,
                                          kz_json:from_list([{<<"number">>, Number}
                                                             ,{<<"name">>, Name}]), QueueDoc)}
    end.

resolve_custom_caller_id(Context, QueueDoc) ->
    Number = kz_json:get_value(?CALLER_ID_PATH ++ [<<"number">>], QueueDoc),
    Name = case kz_json:get_value(?CALLER_ID_PATH ++ [<<"name">>], QueueDoc) of
               'undefined' -> inherited_caller_id_name(Context);
               ConfiguredName -> ConfiguredName
           end,
    case valid_number(Number) andalso valid_text(Name, 128) of
        'false' -> {'error', 'invalid_outbound_caller_id'};
        'true' -> {'ok', kz_json:set_value(?CALLER_ID_PATH ++ [<<"name">>], Name, QueueDoc)}
    end.

inherited_caller_id_field(Field, Context) ->
    Path = [<<"caller_id">>, <<"external">>, Field],
    %% Only an absent field inherits. Empty, malformed or unowned configured
    %% identity is not permission to silently pick a different identity.
    case kz_json:get_value(Path, maps:get('authority', Context)) of
        'undefined' -> kz_json:get_value(Path, maps:get('account', Context));
        Configured -> Configured
    end.

inherited_caller_id_name(Context) ->
    case inherited_caller_id_field(<<"name">>, Context) of
        'undefined' ->
            case kz_json:get_value(<<"name">>, maps:get('authority', Context)) of
                'undefined' -> kzd_users:full_name(maps:get('authority', Context),
                                                  kz_json:get_value(<<"name">>, maps:get('account', Context)));
                AuthorityName -> AuthorityName
            end;
        CallerName -> CallerName
    end.

build_resolved_request(Context, QueueDoc, Reservation, ReplyQueue
                       ,Normalize, Classify, LookupCallerId) ->
    AccountId = kz_doc:id(maps:get('account', Context)),
    Number = kz_json:get_ne_binary_value(<<"number">>, Reservation),
    case authorize_number(Context, QueueDoc, Number, Normalize, Classify, LookupCallerId) of
        {'error', _}=Error -> Error;
        {'ok', Normalized, _Classification} ->
            build_request(AccountId, Context, QueueDoc, Reservation, ReplyQueue, Normalized)
    end.

authorize_number(Context, QueueDoc, Number, Normalize, Classify, LookupCallerId) ->
    AccountId = kz_doc:id(maps:get('account', Context)),
    case normalize_and_classify(Number, Normalize, Classify) of
        {'error', _}=Error -> Error;
        {'ok', _Normalized, Classification}=Result ->
            AccountDoc = maps:get('account', Context),
            AuthorityDoc = maps:get('authority', Context),
            case restricted(Classification, AccountDoc, AuthorityDoc) of
                'true' -> {'error', 'call_restricted'};
                'false' ->
                    case caller_id_owned_by_account(AccountId, QueueDoc, LookupCallerId) of
                        'true' -> Result;
                        'false' -> {'error', 'caller_id_not_owned'}
                    end
            end
    end.

caller_id_owned_by_account(AccountId, QueueDoc, LookupCallerId)
  when is_function(LookupCallerId, 1) ->
    CallerIdNumber = kz_json:get_ne_binary_value(?CALLER_ID_PATH ++ [<<"number">>], QueueDoc),
    case valid_number(CallerIdNumber) of
        'false' -> 'false';
        'true' ->
            try LookupCallerId(CallerIdNumber) of
                {'ok', AccountId, _} -> 'true';
                _ -> 'false'
            catch
                _:_ -> 'false'
            end
    end;
caller_id_owned_by_account(_, _, _) -> 'false'.

build_request(AccountId, Context, QueueDoc, Reservation, ReplyQueue, Number) ->
    CallerIdNumber = kz_json:get_ne_binary_value(?CALLER_ID_PATH ++ [<<"number">>], QueueDoc),
    CallerIdName = kz_json:get_ne_binary_value(?CALLER_ID_PATH ++ [<<"name">>], QueueDoc),
    CallerCallId = kz_json:get_ne_binary_value(<<"pvt_caller_call_id">>, Reservation),
    CallbackId = kz_doc:id(Reservation),
    Attempt = kz_json:get_integer_value(<<"attempts">>, Reservation),
    Timeout = kz_json:get_integer_value([<<"callback">>, <<"originate_timeout">>], QueueDoc, 60),
    LocalResourceProps =
        case kz_json:get_value([<<"callback">>, <<"use_local_resources">>], QueueDoc) of
            'true' -> [{<<"Hunt-Account-ID">>, AccountId}];
            _ -> []
        end,
    case valid_request_values(CallerIdNumber, CallerIdName, CallerCallId, CallbackId, Attempt, Timeout) of
        'false' -> {'error', 'invalid_request_context'};
        'true' ->
            AuthorityId = maps:get('authority_id', Context),
            AuthorityType = maps:get('authority_type', Context),
            CCVs = kz_json:from_list([{<<"Account-ID">>, AccountId}
                                    ,{<<"Authorizing-ID">>, AuthorityId}
                                    ,{<<"Authorizing-Type">>, AuthorityType}
                                    ,{<<"Callback-ID">>, CallbackId}
                                    ,{<<"Callback-Attempt">>, Attempt}
                                    ]),
            Denied = denied_restrictions(maps:get('account', Context), maps:get('authority', Context)),
            Request = kz_json:from_list(
                        [{<<"Account-ID">>, AccountId}
                        ,{<<"Account-Realm">>, maps:get('realm', Context)}
                        ,{<<"Application-Name">>, <<"park">>}
                        ,{<<"Resource-Type">>, <<"originate">>}
                        ,{<<"To-DID">>, Number}
                        ,{<<"Outbound-Call-ID">>, CallerCallId}
                        ,{<<"Outbound-Caller-ID-Name">>, CallerIdName}
                        ,{<<"Outbound-Caller-ID-Number">>, CallerIdNumber}
                        ,{<<"B-Leg-Events">>, ?B_LEG_EVENTS}
                        ,{<<"Custom-Channel-Vars">>, CCVs}
                        ,{<<"Denied-Call-Restrictions">>, Denied}
                        ,{<<"Ignore-Early-Media">>, 'true'}
                        ,{<<"Media">>, <<"process">>}
                        %% A READY barrier lets the worker retain a cancel handle
                        %% before ecallmgr starts the external call.
                        ,{<<"Originate-Immediate">>, 'false'}
                        ,{<<"Timeout">>, Timeout}
                        ,{<<"Msg-ID">>, kz_binary:rand_hex(12)}
                         | LocalResourceProps
                           ++ kz_api:default_headers(ReplyQueue, <<"resource">>, <<"offnet_req">>
                                                     ,?APP_NAME, ?APP_VERSION)
                        ]),
            case kapi_offnet_resource:req_v(Request) of
                'true' -> {'ok', Request};
                'false' -> {'error', 'invalid_request'}
            end
    end.

normalize_and_classify(Number, Normalize, Classify) when is_function(Normalize, 1), is_function(Classify, 1) ->
    try Normalize(Number) of
        Normalized ->
            case valid_number(Normalized) of
                'false' -> {'error', 'invalid_number'};
                'true' ->
                    case Classify(Normalized) of
                        Classification when is_binary(Classification), byte_size(Classification) > 0 ->
                            {'ok', Normalized, Classification};
                        _ -> {'error', 'unclassified_number'}
                    end
            end
    catch
        _:_ -> {'error', 'invalid_number'}
    end.

restricted(Classification, AccountDoc, AuthorityDoc) ->
    lists:any(fun(Doc) ->
                      kz_json:get_ne_binary_value([<<"call_restriction">>, Classification, <<"action">>], Doc)
                          =:= <<"deny">>
              end, [AccountDoc, AuthorityDoc]).

denied_restrictions(AccountDoc, AuthorityDoc) ->
    lists:foldl(fun collect_denied/2, kz_json:new(), [AccountDoc, AuthorityDoc]).

collect_denied(Doc, Acc) ->
    Restrictions = kz_json:get_json_value(<<"call_restriction">>, Doc, kz_json:new()),
    lists:foldl(fun({Classification, Rule}, Denied) ->
                        case kz_json:get_ne_binary_value(<<"action">>, Rule) of
                            <<"deny">> -> kz_json:set_value(Classification, Rule, Denied);
                            _ -> Denied
                        end
                end, Acc, kz_json:to_proplist(Restrictions)).

valid_request_values(CallerIdNumber, CallerIdName, CallerCallId, CallbackId, Attempt, Timeout) ->
    valid_number(CallerIdNumber)
        andalso valid_text(CallerIdName, 128)
        andalso matches(CallerCallId, <<"^[0-9a-f]{32}$">>)
        andalso valid_text(CallbackId, 128)
        andalso is_integer(Attempt) andalso Attempt >= 1 andalso Attempt =< 1000
        andalso is_integer(Timeout) andalso Timeout >= 5 andalso Timeout =< 300.

valid_account_id(AccountId) ->
    matches(AccountId, <<"^[0-9a-f]{32}$">>).

valid_number(Number) ->
    matches(Number, <<"^\\+?[0-9]{1,15}$">>).

valid_text(Value, Max) when is_binary(Value), byte_size(Value) > 0, byte_size(Value) =< Max ->
    re:run(Value, <<"[\\x00-\\x1f\\x7f]">>, [{'capture', 'none'}]) =:= 'nomatch';
valid_text(_, _) -> 'false'.

matches(Value, Regex) when is_binary(Value), byte_size(Value) =< 512 ->
    valid_text(Value, 512) andalso re:run(Value, Regex, [{'capture', 'none'}]) =:= 'match';
matches(_, _) -> 'false'.
