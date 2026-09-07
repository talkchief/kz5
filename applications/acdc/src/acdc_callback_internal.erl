%%% SPDX-License-Identifier: MPL-2.0
%%% Account-local callbacks never enter the carrier/resource hunting path.
%%% Resolve only exact short extensions whose entire callflow is one user or
%%% device. Pin that identity in the reservation and revalidate on every retry.
-module(acdc_callback_internal).
-export([resolve/2, build_request/6, resource_response/3]).
-ifdef(TEST).
-export([resolve_with/4, safe_device/3, safe_endpoint/3, same_target/2]).
-endif.
-include("acdc.hrl").

-spec resolve(kz_term:ne_binary(), kz_term:ne_binary()) -> 'not_internal' | {'ok', kz_json:object()} | {'error', atom()}.
resolve(AccountId, Number) ->
    Db = kzs_util:format_account_db(AccountId),
    resolve_with(AccountId, Number,
                 fun() -> kz_datamgr:get_results(Db, <<"callflows/listing_by_number">>,
                                                [{'key', Number}, {'limit', 2}, 'include_docs']) end,
                 fun(Id) -> kz_datamgr:open_doc(Db, Id) end).

-spec resolve_with(binary(), term(), fun(() -> term()), fun((binary()) -> term())) -> term().
resolve_with(AccountId, Number, Query, Fetch) ->
    case short_extension(Number) of
        'false' -> 'not_internal';
        'true' ->
            try Query() of
                {'ok', []} -> 'not_internal';
                {'ok', [Row]} -> resolve_flow(AccountId, Number, kz_json:get_json_value(<<"doc">>, Row), Fetch);
                {'ok', _} -> {'error', 'ambiguous_internal_extension'};
                _ -> {'error', 'internal_directory_unavailable'}
            catch _:_ -> {'error', 'internal_directory_unavailable'} end
    end.

resolve_flow(AccountId, Number, FlowDoc, Fetch) ->
    Flow = kz_json:get_json_value(<<"flow">>, FlowDoc, kz_json:new()),
    Type = kz_json:get_ne_binary_value(<<"module">>, Flow),
    Id = kz_json:get_ne_binary_value([<<"data">>, <<"id">>], Flow),
    Checks = [owned(FlowDoc, AccountId, <<"callflow">>)
             ,lists:member(Number, kz_json:get_list_value(<<"numbers">>, FlowDoc, []))
             ,lists:member(Type, [<<"user">>, <<"device">>])
             ,kz_json:is_empty(kz_json:get_json_value(<<"children">>, Flow, kz_json:new()))
             ,not kz_json:is_true([<<"data">>, <<"skip_module">>], Flow)
             ,is_binary(Id) andalso byte_size(Id) > 0],
    case lists:all(fun(X) -> X =:= 'true' end, Checks) of
        'false' -> {'error', 'unsupported_internal_callflow'};
        'true' ->
            case Fetch(Id) of
                {'ok', TargetDoc} ->
                    case owned(TargetDoc, AccountId, Type) andalso available(TargetDoc) of
                        'false' -> {'error', 'internal_target_unavailable'};
                        'true' -> {'ok', kz_json:from_list([{<<"number">>, Number}
                                                          ,{<<"flow_id">>, kz_doc:id(FlowDoc)}
                                                          ,{<<"type">>, Type}, {<<"id">>, Id}])}
                    end;
                _ -> {'error', 'internal_target_unavailable'}
            end
    end.

-spec build_request(binary(), kz_json:object(), kz_json:object(), binary(), map(), kz_json:object()) ->
          {'ok', kz_json:object()} | {'error', atom()}.
build_request(AccountId, Queue, Reservation, ReplyQueue, Context, Target) ->
    Number = kz_json:get_ne_binary_value(<<"number">>, Reservation),
    case resolve(AccountId, Number) of
        {'ok', Current} ->
            case same_target(Current, Target) of
                'false' -> {'error', 'internal_target_changed'};
                'true' -> build_current(AccountId, Queue, Reservation, ReplyQueue, Context, Current)
            end;
        _ -> {'error', 'internal_target_unavailable'}
    end.

-spec same_target(term(), term()) -> boolean().
same_target(A, B) ->
    kz_json:is_json_object(A) andalso kz_json:is_json_object(B)
        andalso lists:all(fun(Key) -> kz_json:get_value(Key, A) =/= 'undefined'
                             andalso kz_json:get_value(Key, A) =:= kz_json:get_value(Key, B) end,
                         [<<"number">>, <<"flow_id">>, <<"type">>, <<"id">>]).

build_current(AccountId, Queue, Reservation, ReplyQueue, Context, Target) ->
    try
        Db = kzs_util:format_account_db(AccountId),
        Realm = maps:get('realm', Context),
        Number = kz_json:get_ne_binary_value(<<"number">>, Target),
        CallId = kz_json:get_ne_binary_value(<<"pvt_caller_call_id">>, Reservation),
        Timeout = kz_json:get_integer_value([<<"callback">>, <<"originate_timeout">>], Queue, 60),
        Attempt = kz_json:get_integer_value(<<"attempts">>, Reservation),
        'true' = is_integer(Timeout) andalso Timeout >= 5 andalso Timeout =< 300,
        'true' = is_integer(Attempt) andalso Attempt >= 1 andalso Attempt =< 1000,
        'true' = is_binary(CallId) andalso byte_size(CallId) =:= 32,
        Name = kz_json:get_ne_binary_value(<<"name">>, Queue, <<"Queue callback">>),
        CCVs = kz_json:from_list([{<<"Account-ID">>, AccountId}
                                 ,{<<"Authorizing-ID">>, maps:get('authority_id', Context)}
                                 ,{<<"Authorizing-Type">>, maps:get('authority_type', Context)}
                                 ,{<<"Realm">>, Realm}
                                 ,{<<"Callback-ID">>, kz_doc:id(Reservation)}
                                 ,{<<"Callback-Attempt">>, Attempt}]),
        Call = kapps_call:from_json(kz_json:from_list(
                 [{<<"Account-ID">>, AccountId}, {<<"Account-DB">>, Db}
                  ,{<<"Call-ID">>, CallId}, {<<"Resource-Type">>, <<"audio">>}
                  ,{<<"Request">>, <<Number/binary, "@", Realm/binary>>}
                  ,{<<"To">>, <<Number/binary, "@", Realm/binary>>}
                  ,{<<"Caller-ID-Number">>, Number}, {<<"Caller-ID-Name">>, Name}
                  ,{<<"Custom-Channel-Vars">>, CCVs}])),
        {'ok', Ids} = device_ids(Db, Target),
        Endpoints = lists:append([build_device(Id, AccountId, Realm, Target, Call, Timeout) || Id <- Ids]),
        'true' = Endpoints =/= [],
        Request = kz_json:from_list(
                    [{<<"Account-ID">>, AccountId}
                     ,{<<"Application-Name">>, <<"park">>}
                     ,{<<"Call-ID">>, CallId}, {<<"Outbound-Call-ID">>, CallId}
                     ,{<<"Caller-ID-Name">>, Name}, {<<"Caller-ID-Number">>, Number}
                     ,{<<"Outbound-Caller-ID-Name">>, Name}, {<<"Outbound-Caller-ID-Number">>, Number}
                     ,{<<"Custom-Channel-Vars">>, CCVs}, {<<"Endpoints">>, Endpoints}
                     ,{<<"B-Leg-Events">>, [<<"CHANNEL_ANSWER">>, <<"DTMF">>, <<"CHANNEL_DESTROY">>
                                             ,<<"CHANNEL_EXECUTE_COMPLETE">>, <<"CHANNEL_EXECUTE_ERROR">>
                                             ,<<"CHANNEL_BRIDGE">>]}
                     ,{<<"Dial-Endpoint-Method">>, <<"simultaneous">>}
                     ,{<<"Ignore-Early-Media">>, 'true'}, {<<"Media">>, <<"process">>}
                     ,{<<"Originate-Immediate">>, 'false'}, {<<"Timeout">>, Timeout}
                     ,{<<"Msg-ID">>, kz_binary:rand_hex(12)}
                     | kz_api:default_headers(ReplyQueue, <<"resource">>, <<"originate_req">>, ?APP_NAME, ?APP_VERSION)]),
        case kapi_resource:originate_req_v(Request) of
            'true' -> {'ok', Request};
            'false' -> {'error', 'invalid_internal_request'}
        end
    catch _:_ -> {'error', 'internal_endpoints_unavailable'} end.

device_ids(Db, Target) ->
    Id = kz_json:get_ne_binary_value(<<"id">>, Target),
    case kz_json:get_value(<<"type">>, Target) of
        <<"device">> -> {'ok', [Id]};
        <<"user">> ->
            case kz_datamgr:get_results(Db, <<"attributes/owned">>, [{'key', [Id, <<"device">>]}, {'limit', 33}]) of
                {'ok', Rows} when length(Rows) =< 32 ->
                    {'ok', lists:usort([kz_json:get_ne_binary_value(<<"value">>, Row) || Row <- Rows])};
                _ -> {'error', 'internal_endpoints_unavailable'}
            end
    end.

build_device(Id, AccountId, Realm, Target, Call, Timeout) ->
    Db = kzs_util:format_account_db(AccountId),
    case kz_endpoint:get(Id, Db, [{'no_cache', 'true'}]) of
        {'ok', Device} ->
            OwnerOk = kz_json:get_value(<<"type">>, Target) =:= <<"device">>
                orelse kz_json:get_value(<<"owner_id">>, Device) =:= kz_json:get_value(<<"id">>, Target),
            case OwnerOk andalso safe_device(Device, AccountId, Realm) of
                'false' -> [];
                'true' ->
                    Properties = kz_json:from_list([{<<"can_call_self">>, 'true'}
                                                    ,{<<"source">>, <<"acdc_callback_internal">>}
                                                    ,{<<"timeout">>, Timeout}]),
                    case kz_endpoint:build(Device, Properties, Call) of
                        {'ok', Built} -> [EP || EP <- Built, safe_endpoint(EP, AccountId, Id)];
                        _ -> []
                    end
            end;
        _ -> []
    end.

-spec safe_device(kz_json:object(), binary(), binary()) -> boolean().
safe_device(Device, AccountId, Realm) ->
    Type = kz_json:get_first_defined([<<"Endpoint-Type">>, <<"pvt_type">>], Device),
    Type =:= <<"device">> andalso kz_doc:account_id(Device) =:= AccountId
        andalso available(Device)
        andalso not kz_json:is_true([<<"call_forward">>, <<"enabled">>], Device)
        andalso kz_json:get_value([<<"sip">>, <<"route">>], Device) =:= 'undefined'
        andalso kz_json:get_value([<<"sip">>, <<"realm">>], Device, Realm) =:= Realm
        andalso lists:member(kz_json:get_value(<<"device_type">>, Device, <<"sip_device">>),
                            [<<"sip_device">>, <<"softphone">>, <<"smartphone">>]).

%% Only the native account+device endpoint representation may leave this module.
%% Endpoint builders can also emit call-forward loopbacks: never pass those on.
-spec safe_endpoint(kz_json:object(), binary(), binary()) -> boolean().
safe_endpoint(EP, AccountId, DeviceId) ->
    kz_json:get_value(<<"Invite-Format">>, EP) =:= <<"endpoint">>
        andalso kz_json:get_value(<<"Account-ID">>, EP) =:= AccountId
        andalso kz_json:get_value(<<"Endpoint-ID">>, EP) =:= DeviceId
        andalso kz_json:get_value(<<"Endpoint-URI">>, EP) =:= <<DeviceId/binary, "@", AccountId/binary>>
        andalso kz_json:get_value(<<"Route">>, EP) =:= 'undefined'.

owned(Doc, AccountId, Type) ->
    kz_json:is_json_object(Doc) andalso kz_doc:account_id(Doc) =:= AccountId
        andalso kz_doc:type(Doc) =:= Type andalso not kz_json:is_true(<<"pvt_deleted">>, Doc).

available(Doc) ->
    kz_json:is_true(<<"enabled">>, Doc, 'true')
        andalso not kz_json:is_true([<<"do_not_disturb">>, <<"enabled">>], Doc).

short_extension(Number) when is_binary(Number), byte_size(Number) > 0, byte_size(Number) =< 6 ->
    re:run(Number, <<"^[0-9]+$">>, [{'capture', 'none'}]) =:= 'match';
short_extension(_) -> 'false'.

%% Adapt validated direct resource responses to the existing callback lifecycle.
%% Correlation is checked BEFORE adding the trusted outer callback call-ID.
-spec resource_response(binary(), term(), kz_json:object()) -> {'ok', kz_json:object()} | {'error', atom()}.
resource_response(CallId, MsgId, JObj) ->
    try
        'true' = kz_json:is_json_object(JObj),
        case kz_api:msg_id(JObj) =:= MsgId andalso is_binary(MsgId) of
            'false' -> {'error', 'stale_response'};
            'true' -> resource_event(CallId, MsgId, kz_api:event_type(JObj), JObj)
        end
    catch _:_ -> {'error', 'invalid_response'} end.

resource_event(CallId, MsgId, {<<"dialplan">>, <<"originate_ready">>}, JObj) ->
    case kapi_resource:originate_ready_v(JObj) of
        'true' -> {'ok', response(CallId, MsgId, <<"READY">>, JObj, [])};
        'false' -> {'error', 'invalid_response'}
    end;
resource_event(CallId, MsgId, {<<"resource">>, <<"originate_resp">>}, JObj) ->
    case kapi_resource:originate_resp_v(JObj) andalso kz_json:get_value(<<"Call-ID">>, JObj) =:= CallId of
        'false' -> {'error', 'stale_response'};
        'true' ->
            Status = kz_json:get_value(<<"Application-Response">>, JObj),
            Extra = case Status of
                        <<"SUCCESS">> -> [{<<"Call">>, kapps_call:to_json(kapps_call:from_originate_resp(JObj))}];
                        _ -> []
                    end,
            {'ok', response(CallId, MsgId, Status, JObj, Extra)}
    end;
resource_event(CallId, MsgId, {<<"error">>, <<"originate_resp">>}, JObj) ->
    Request = kz_json:get_json_value(<<"Request">>, JObj, kz_json:new()),
    case kapi_resource:originate_req_v(Request)
        andalso kz_api:msg_id(Request) =:= MsgId
        andalso kz_json:get_value(<<"Outbound-Call-ID">>, Request) =:= CallId of
        'true' -> {'ok', response(CallId, MsgId, <<"FAILED">>, JObj, [])};
        'false' -> {'error', 'invalid_response'}
    end;
resource_event(_CallId, _MsgId, _Type, _JObj) -> {'error', 'invalid_response'}.

response(CallId, MsgId, Status, Resource, Extra) ->
    kz_json:from_list([{<<"Call-ID">>, CallId}, {<<"Msg-ID">>, MsgId}
                      ,{<<"Response-Message">>, Status}, {<<"Resource-Response">>, Resource}
                      | Extra ++ kz_api:default_headers(<<"resource">>, <<"offnet_resp">>, ?APP_NAME, ?APP_VERSION)]).
