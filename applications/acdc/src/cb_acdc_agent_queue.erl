%%% SPDX-License-Identifier: MPL-2.0
%%% Opt-in queue login: never changes the saved agent roster. A command receipt
%%% is pending; only a fresh agent-listener snapshot confirms runtime membership.
-module(cb_acdc_agent_queue).
-export([requested/1, validate/2, read/2, post/2]).
-include_lib("crossbar/src/crossbar.hrl").
-include("acdc_config.hrl").

-spec requested(cb_context:context()) -> boolean().
requested(Context) -> cb_context:req_value(Context, <<"runtime_only">>) =/= 'undefined'.

-spec validate(kz_term:ne_binary(), cb_context:context()) -> cb_context:context().
validate(AgentId, Context) ->
    case cb_context:resp_status(Context) of
        'success' -> validate_request(AgentId, Context);
        _ -> Context
    end.

-spec validate_request(kz_term:ne_binary(), cb_context:context()) -> cb_context:context().
validate_request(AgentId, Context) ->
    Mode = cb_context:req_value(Context, <<"runtime_only">>),
    ModeValid = Mode =:= 'true' orelse
        (cb_context:req_verb(Context) =:= ?HTTP_GET andalso Mode =:= <<"true">>),
    QueueId = cb_context:req_value(Context, <<"queue_id">>),
    case ModeValid andalso cb_context:req_value(Context, <<"action">>) =:= <<"login">>
        andalso is_binary(QueueId) andalso byte_size(QueueId) > 0 andalso byte_size(QueueId) =< 128
    of
        'false' -> error_response(400, <<"runtime_only requires explicit login and queue_id">>, Context);
        'true' -> validate_membership(AgentId, QueueId, Context)
    end.

-spec validate_membership(kz_term:ne_binary(), kz_term:ne_binary(), cb_context:context()) -> cb_context:context().
validate_membership(AgentId, QueueId, Context) ->
    Doc = cb_context:doc(Context),
    AccountId = cb_context:account_id(Context),
    Queues = kz_json:get_value(<<"queues">>, Doc, []),
    case kz_doc:id(Doc) =:= AgentId andalso kz_doc:type(Doc) =:= <<"user">>
        andalso kz_doc:account_id(Doc) =:= AccountId andalso kzd_users:enabled(Doc)
        andalso not kz_doc:is_soft_deleted(Doc)
        andalso is_list(Queues) andalso lists:member(QueueId, Queues)
    of
        'false' -> error_response(403, <<"agent is not an enabled member of the selected queue">>, Context);
        'true' ->
            case kz_datamgr:open_doc(cb_context:db_name(Context), QueueId) of
                {'ok', Queue} ->
                    case kz_doc:type(Queue) =:= <<"queue">> andalso kz_doc:account_id(Queue) =:= AccountId
                        andalso not kz_doc:is_soft_deleted(Queue)
                    of
                        'true' -> Context;
                        'false' -> error_response(404, <<"selected queue not found">>, Context)
                    end;
                {'error', 'not_found'} -> error_response(404, <<"selected queue not found">>, Context);
                _ -> error_response(503, <<"selected queue could not be read">>, Context)
            end
    end.

-spec post(kz_term:ne_binary(), cb_context:context()) -> cb_context:context().
post(AgentId, Context) ->
    %% Re-read membership at execution, not only in the validation phase.
    Fresh = crossbar_doc:load(AgentId, Context, ?TYPE_CHECK_OPTION(kzd_users:type())),
    Checked = validate(AgentId, Fresh),
    case cb_context:resp_status(Checked) of
        'success' -> publish_login(AgentId, Checked);
        _ -> Checked
    end.

-spec publish_login(kz_term:ne_binary(), cb_context:context()) -> cb_context:context().
publish_login(AgentId, Context) ->
    QueueId = cb_context:req_value(Context, <<"queue_id">>),
    Props = [{<<"Account-ID">>, cb_context:account_id(Context)}
            ,{<<"Agent-ID">>, AgentId}, {<<"Queue-ID">>, QueueId}
            ,{<<"Runtime-Only">>, 'true'}
            | kz_api:default_headers(?APP_NAME, ?APP_VERSION)],
    case catch kz_amqp_worker:cast(Props, fun kapi_acdc_agent:publish_login_queue/1) of
        'ok' -> crossbar_util:response_202(<<"queue login requested; runtime confirmation pending">>
                                          ,snapshot(cb_context:account_id(Context), AgentId, QueueId, 'false', 'false', <<"unknown">>)
                                          ,no_cache(Context));
        _ -> error_response(503, <<"queue login could not be published">>, Context)
    end.

-spec read(kz_term:ne_binary(), cb_context:context()) -> cb_context:context().
read(AgentId, Context) ->
    Checked = validate(AgentId, Context),
    case cb_context:resp_status(Checked) of
        'success' -> read_runtime(AgentId, Checked);
        _ -> Checked
    end.

-spec read_runtime(kz_term:ne_binary(), cb_context:context()) -> cb_context:context().
read_runtime(AgentId, Context) ->
    AccountId = cb_context:account_id(Context),
    QueueId = cb_context:req_value(Context, <<"queue_id">>),
    MsgId = kz_binary:rand_hex(16),
    Request = [{<<"Account-ID">>, AccountId}, {<<"Agent-ID">>, AgentId}
              ,{<<"Msg-ID">>, MsgId}, {<<"Process-ID">>, <<"queue-status-", MsgId/binary>>}
              | kz_api:default_headers(?APP_NAME, ?APP_VERSION)],
    Validator = fun(Reply) -> valid_snapshot(Reply, AccountId, AgentId, MsgId) end,
    Data = case catch kz_amqp_worker:call(Request, fun kapi_acdc_agent:publish_sync_req/1, Validator, 2000) of
               {'ok', Reply} ->
                   %% Recheck even if an alternate worker/adapter skips its validator.
                   case Validator(Reply) of
                       'true' -> snapshot(AccountId, AgentId, QueueId, 'true'
                                          ,lists:member(QueueId, kz_json:get_value(<<"Queues">>, Reply))
                                          ,kz_json:get_value(<<"Status">>, Reply));
                       'false' -> snapshot(AccountId, AgentId, QueueId, 'false', 'false', <<"unknown">>)
                   end;
               _ -> snapshot(AccountId, AgentId, QueueId, 'false', 'false', <<"unknown">>)
           end,
    crossbar_util:response(Data, no_cache(Context)).

-spec valid_snapshot(kz_json:object(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> boolean().
valid_snapshot(Reply, AccountId, AgentId, MsgId) ->
    try valid_snapshot_fields(Reply, AccountId, AgentId, MsgId)
    catch _:_ -> 'false'
    end.

-spec valid_snapshot_fields(kz_json:object(), kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary()) -> boolean().
valid_snapshot_fields(Reply, AccountId, AgentId, MsgId) ->
    Queues = kz_json:get_value(<<"Queues">>, Reply),
    kapi_acdc_agent:sync_resp_v(Reply)
        andalso kz_json:get_value(<<"Account-ID">>, Reply) =:= AccountId
        andalso kz_json:get_value(<<"Agent-ID">>, Reply) =:= AgentId
        andalso kz_api:msg_id(Reply) =:= MsgId
        andalso is_list(Queues)
        andalso length(Queues) =< 1024
        andalso lists:all(fun(Q) -> is_binary(Q) andalso byte_size(Q) > 0 andalso byte_size(Q) =< 128 end, Queues)
        andalso length(Queues) =:= length(lists:usort(Queues)).

-spec snapshot(kz_term:ne_binary(), kz_term:ne_binary(), kz_term:ne_binary(), boolean(), boolean(), kz_term:ne_binary()) -> kz_json:object().
snapshot(AccountId, AgentId, QueueId, Observed, Member, Status) ->
    Confirmed = Observed andalso Member,
    State = case Confirmed of 'true' -> <<"confirmed">>; 'false' -> <<"pending">> end,
    kz_json:from_list([{<<"account_id">>, AccountId}, {<<"agent_id">>, AgentId}, {<<"queue_id">>, QueueId}
                     ,{<<"action">>, <<"login">>}, {<<"runtime_only">>, 'true'}
                     ,{<<"state">>, State}, {<<"confirmed">>, Confirmed}
                     ,{<<"runtime_member">>, Member}, {<<"runtime_observed">>, Observed}
                     ,{<<"agent_status">>, Status}]).

-spec no_cache(cb_context:context()) -> cb_context:context().
no_cache(Context) -> cb_context:set_resp_header(Context, <<"cache-control">>, <<"no-store">>).

-spec error_response(pos_integer(), kz_term:ne_binary(), cb_context:context()) -> cb_context:context().
error_response(Code, Message, Context) -> crossbar_util:response('error', Message, Code, no_cache(Context)).
