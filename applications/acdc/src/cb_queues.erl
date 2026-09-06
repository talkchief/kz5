%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2011-2020, 2600Hz
%%% @doc CRUD for call queues
%%% /queues
%%%   GET: list all known queues
%%%   PUT: create a new queue
%%%
%%% /queues/stats
%%%   GET: retrieve stats across all queues for the last hour
%%%
%%% /queues/QID
%%%   GET: queue details
%%%   POST: replace queue details
%%%   PATCH: patch queue details
%%%   DELETE: delete a queue
%%%
%%% /queues/QID/stats
%%%   GET: retrieve stats for this queue
%%% /queues/QID/stats/realtime
%%%   GET: retrieve realtime stats for the queues
%%%
%%% /queues/QID/roster
%%%   GET: get list of agent_ids
%%%   POST: add a list of agent_ids
%%%   DELETE: rm a list of agent_ids
%%%
%%% /queues/eavesdrop
%%%   PUT: unavailable (503); use account-scoped channels monitoring actions
%%% /queues/QID/eavesdrop
%%%   PUT: unavailable (503); use account-scoped channels monitoring actions
%%%
%%%
%%% @author James Aimonetti
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(cb_queues).

-export([init/0
        ,allowed_methods/0, allowed_methods/1, allowed_methods/2, allowed_methods/3
        ,resource_exists/0, resource_exists/1, resource_exists/2, resource_exists/3
        ,content_types_provided/1, content_types_provided/2
        ,validate/1, validate/2, validate/3, validate/4
        ,put/1, put/2, put/3
        ,post/2, post/3
        ,patch/2, patch/3
        ,delete/2, delete/3, delete/4
        ,delete_account/2
        ]).

-ifdef(TEST).
-export([callback_public/1
        ,decode_callback_cursor/2
        ,encode_callback_cursor/1
        ,validate_callback_list/2
        ,validate_callback/4
        ,cancel_callback/3
        ]).
-endif.

-include_lib("crossbar/src/crossbar.hrl").
-include("acdc_config.hrl").

-define(MOD_CONFIG_CAT, <<(?CONFIG_CAT)/binary, ".queues">>).

-define(CB_LIST, <<"queues/crossbar_listing">>).
-define(CB_AGENTS_LIST, <<"queues/agents_listing">>). %{agent_id, queue_id}

-define(STATS_PATH_TOKEN, <<"stats">>).
-define(ROSTER_PATH_TOKEN, <<"roster">>).
-define(EAVESDROP_PATH_TOKEN, <<"eavesdrop">>).
-define(CALLBACKS_PATH_TOKEN, <<"callbacks">>).
-define(EDITOR_PATH_TOKEN, <<"editor">>).
-define(MAX_CALLBACK_PAGE_SIZE, 100).

-define(STAT_TIMESTAMP_PROCESSED, <<"finished_with_agent">>).
-define(STAT_TIMESTAMP_HANDLING, <<"connected_with_agent">>).
-define(STAT_TIMESTAMP_ABANDONED, <<"caller_abandoned_queue">>).
-define(STAT_TIMESTAMP_WAITING, <<"caller_entered_queue">>).
-define(STAT_AGENTS_MISSED, <<"missed">>).

-define(STATUS_PROCESSED, <<"processed">>).
-define(STATUS_HANDLING, <<"handling">>).
-define(STATUS_ABANDONED, <<"abandoned">>).
-define(STATUS_WAITING, <<"waiting">>).

-define(STAT_TIMESTAMP_KEYS, [?STAT_TIMESTAMP_PROCESSED
                             ,?STAT_TIMESTAMP_HANDLING
                             ,?STAT_TIMESTAMP_ABANDONED
                             ,?STAT_TIMESTAMP_WAITING
                             ]).

-define(FORMAT_COMPRESSED, <<"compressed">>).
-define(FORMAT_VERBOSE, <<"verbose">>).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Initializes the bindings this module will respond to.
%% @end
%%------------------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    _ = kapi_acdc_agent:declare_exchanges(),
    _ = kapi_acdc_stats:declare_exchanges(),

    _ = crossbar_bindings:bind(<<"*.allowed_methods.queues">>, ?MODULE, 'allowed_methods'),
    _ = crossbar_bindings:bind(<<"*.resource_exists.queues">>, ?MODULE, 'resource_exists'),
    _ = crossbar_bindings:bind(<<"*.content_types_provided.queues">>, ?MODULE, 'content_types_provided'),
    _ = crossbar_bindings:bind(<<"*.validate.queues">>, ?MODULE, 'validate'),
    _ = crossbar_bindings:bind(<<"*.execute.put.queues">>, ?MODULE, 'put'),
    _ = crossbar_bindings:bind(<<"*.execute.post.queues">>, ?MODULE, 'post'),
    _ = crossbar_bindings:bind(<<"*.execute.patch.queues">>, ?MODULE, 'patch'),

    _ = crossbar_bindings:bind(<<"*.execute.delete.accounts">>, ?MODULE, 'delete_account'),

    _ = crossbar_bindings:bind(<<"*.execute.delete.queues">>, ?MODULE, 'delete').

%%------------------------------------------------------------------------------
%% @doc Given the path tokens related to this module, what HTTP methods are
%% going to be responded to.
%% @end
%%------------------------------------------------------------------------------

-spec allowed_methods() -> http_methods().
allowed_methods() ->
    [?HTTP_GET, ?HTTP_PUT].

-spec allowed_methods(path_token()) -> http_methods().
allowed_methods(?STATS_PATH_TOKEN) ->
    [?HTTP_GET];
allowed_methods(?EDITOR_PATH_TOKEN) ->
    [?HTTP_GET, ?HTTP_PUT];
allowed_methods(?EAVESDROP_PATH_TOKEN) ->
    [?HTTP_PUT];
allowed_methods(_QueueId) ->
    [?HTTP_GET, ?HTTP_POST, ?HTTP_PATCH, ?HTTP_DELETE].

-spec allowed_methods(path_token(), path_token()) -> http_methods().
allowed_methods(_QueueId, ?ROSTER_PATH_TOKEN) ->
    [?HTTP_GET, ?HTTP_POST, ?HTTP_DELETE];
allowed_methods(_QueueId, ?EDITOR_PATH_TOKEN) ->
    [?HTTP_GET, ?HTTP_PATCH];
allowed_methods(_QueueId, ?CALLBACKS_PATH_TOKEN) ->
    [?HTTP_GET];
allowed_methods(_QueueId, ?EAVESDROP_PATH_TOKEN) ->
    [?HTTP_PUT].

-spec allowed_methods(path_token(), path_token(), path_token()) -> http_methods().
allowed_methods(_QueueId, ?CALLBACKS_PATH_TOKEN, _CallbackId) ->
    [?HTTP_GET, ?HTTP_DELETE];
allowed_methods(_, _, _) -> [].

%%------------------------------------------------------------------------------
%% @doc Does the path point to a valid resource.
%% For example:
%% ```
%%    /queues => []
%%    /queues/foo => [<<"foo">>]
%%    /queues/foo/bar => [<<"foo">>, <<"bar">>]
%% '''
%% @end
%%------------------------------------------------------------------------------

-spec resource_exists() -> 'true'.
resource_exists() -> 'true'.

-spec resource_exists(path_token()) -> 'true'.
resource_exists(_) -> 'true'.

-spec resource_exists(path_token(), path_token()) -> 'true'.
resource_exists(_, ?ROSTER_PATH_TOKEN) -> 'true';
resource_exists(_, ?EDITOR_PATH_TOKEN) -> 'true';
resource_exists(_, ?CALLBACKS_PATH_TOKEN) -> 'true';
resource_exists(_, ?EAVESDROP_PATH_TOKEN) -> 'true'.

-spec resource_exists(path_token(), path_token(), path_token()) -> boolean().
resource_exists(_, ?CALLBACKS_PATH_TOKEN, _) -> 'true';
resource_exists(_, _, _) -> 'false'.

%%------------------------------------------------------------------------------
%% @doc Add content types accepted and provided by this module
%% @end
%%------------------------------------------------------------------------------

-spec content_types_provided(cb_context:context()) ->
          cb_context:context().
content_types_provided(Context) -> Context.

-spec content_types_provided(cb_context:context(), path_token()) ->
          cb_context:context().
content_types_provided(Context, ?STATS_PATH_TOKEN) ->
    cb_context:add_content_types_provided(Context
                                         ,[{'to_json', ?JSON_CONTENT_TYPES}
                                          ,{'to_csv', ?CSV_CONTENT_TYPES}
                                          ]).

%%------------------------------------------------------------------------------
%% @doc Check the request (request body, query string params, path tokens, etc)
%% and load necessary information.
%% /queues mights load a list of queue objects
%% /queues/123 might load the queue object 123
%% Generally, use crossbar_doc to manipulate the cb_context{} record
%% @end
%%------------------------------------------------------------------------------

-spec validate(cb_context:context()) ->
          cb_context:context().
validate(Context) ->
    validate_queues(Context, cb_context:req_verb(Context)).

validate_queues(Context, ?HTTP_GET) -> summary(Context);
validate_queues(Context, ?HTTP_PUT) -> validate_request('undefined', Context).

-spec validate(cb_context:context(), path_token()) ->
          cb_context:context().
validate(Context, PathToken) ->
    validate_queue(Context, PathToken, cb_context:req_verb(Context)).

validate_queue(Context, ?STATS_PATH_TOKEN, ?HTTP_GET) ->
    fetch_all_queue_stats(Context);
validate_queue(Context, ?EDITOR_PATH_TOKEN, ?HTTP_GET) ->
    cb_acdc_queue_editor:get(Context, 'undefined');
validate_queue(Context, ?EDITOR_PATH_TOKEN, ?HTTP_PUT) ->
    cb_acdc_queue_editor:validate_write(Context, 'undefined');
validate_queue(Context, ?EAVESDROP_PATH_TOKEN, ?HTTP_PUT) ->
    validate_eavesdrop_on_call(Context);
validate_queue(Context, Id, ?HTTP_GET) ->
    read(Id, Context);
validate_queue(Context, Id, ?HTTP_POST) ->
    validate_request(Id, Context);
validate_queue(Context, Id, ?HTTP_PATCH) ->
    validate_patch(Id, Context);
validate_queue(Context, Id, ?HTTP_DELETE) ->
    read(Id, Context).

-spec validate(cb_context:context(), path_token(), path_token()) ->
          cb_context:context().
validate(Context, Id, Token) ->
    validate_queue_operation(Context, Id, Token, cb_context:req_verb(Context)).

validate_queue_operation(Context, Id, ?ROSTER_PATH_TOKEN, ?HTTP_GET) ->
    load_agent_roster(Id, Context);
validate_queue_operation(Context, Id, ?EDITOR_PATH_TOKEN, ?HTTP_GET) ->
    cb_acdc_queue_editor:get(Context, Id);
validate_queue_operation(Context, Id, ?EDITOR_PATH_TOKEN, ?HTTP_PATCH) ->
    cb_acdc_queue_editor:validate_write(Context, Id);
validate_queue_operation(Context, Id, ?ROSTER_PATH_TOKEN, ?HTTP_POST) ->
    add_queue_to_agents(Id, Context);
validate_queue_operation(Context, Id, ?ROSTER_PATH_TOKEN, ?HTTP_DELETE) ->
    rm_queue_from_agents(Id, Context);
validate_queue_operation(Context, Id, ?CALLBACKS_PATH_TOKEN, ?HTTP_GET) ->
    validate_callback_list(Context, Id);
validate_queue_operation(Context, Id, ?EAVESDROP_PATH_TOKEN, ?HTTP_PUT) ->
    validate_eavesdrop_on_queue(Context, Id).

-spec validate(cb_context:context(), path_token(), path_token(), path_token()) ->
          cb_context:context().
validate(Context, QueueId, ?CALLBACKS_PATH_TOKEN, CallbackId) ->
    validate_callback(Context, QueueId, CallbackId, cb_context:req_verb(Context));
validate(Context, _, _, _) ->
    cb_context:add_system_error('faulty_request', Context).

-spec validate_eavesdrop_on_call(cb_context:context()) -> cb_context:context().
validate_eavesdrop_on_call(Context) -> legacy_monitoring_unavailable(Context).

-spec validate_eavesdrop_on_queue(cb_context:context(), binary()) -> cb_context:context().
validate_eavesdrop_on_queue(Context, _QueueId) -> legacy_monitoring_unavailable(Context).

-spec legacy_monitoring_unavailable(cb_context:context()) -> cb_context:context().
legacy_monitoring_unavailable(Context) ->
    crossbar_util:response('error'
                          ,<<"legacy queue monitoring is unavailable; use POST /accounts/{account_id}/channels/{call_id} with action eavesdrop, whisper, barge or join">>
                          ,503, Context).

%%------------------------------------------------------------------------------
%% @doc If the HTTP verb is PUT, execute the actual action, usually a db save.
%% @end
%%------------------------------------------------------------------------------

-spec put(cb_context:context()) ->
          cb_context:context().
put(Context) ->
    activate_account_for_acdc(Context),
    crossbar_doc:save(Context).

-spec put(cb_context:context(), path_token()) -> cb_context:context().
put(Context, ?EAVESDROP_PATH_TOKEN) ->
    legacy_monitoring_unavailable(Context);
put(Context, ?EDITOR_PATH_TOKEN) ->
    cb_acdc_queue_editor:execute(Context).

-spec put(cb_context:context(), path_token(), path_token()) -> cb_context:context().
put(Context, _QID, ?EAVESDROP_PATH_TOKEN) ->
    legacy_monitoring_unavailable(Context).

%%------------------------------------------------------------------------------
%% @doc If the HTTP verb is POST, execute the actual action, usually a db save
%% (after a merge perhaps).
%% @end
%%------------------------------------------------------------------------------

-spec post(cb_context:context(), path_token()) -> cb_context:context().
post(Context, _) ->
    activate_account_for_acdc(Context),
    crossbar_doc:save(Context).

-spec post(cb_context:context(), path_token(), path_token()) -> cb_context:context().
post(Context, Id, ?ROSTER_PATH_TOKEN) ->
    activate_account_for_acdc(Context),
    read(Id, crossbar_doc:save(Context)).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec patch(cb_context:context(), path_token()) -> cb_context:context().
patch(Context, Id) ->
    post(Context, Id).

-spec patch(cb_context:context(), path_token(), path_token()) -> cb_context:context().
patch(Context, _Id, ?EDITOR_PATH_TOKEN) ->
    cb_acdc_queue_editor:execute(Context).
%%------------------------------------------------------------------------------
%% @doc If the HTTP verb is DELETE, execute the actual action, usually a db delete
%% @end
%%------------------------------------------------------------------------------

-spec delete(cb_context:context(), path_token()) -> cb_context:context().
delete(Context, _) ->
    activate_account_for_acdc(Context),
    crossbar_doc:delete(Context).

-spec delete(cb_context:context(), path_token(), path_token()) -> cb_context:context().
delete(Context, Id, ?ROSTER_PATH_TOKEN) ->
    activate_account_for_acdc(Context),
    read(Id, crossbar_doc:save(Context)).

-spec delete(cb_context:context(), path_token(), path_token(), path_token()) ->
          cb_context:context().
delete(Context, QueueId, ?CALLBACKS_PATH_TOKEN, CallbackId) ->
    cancel_callback(Context, QueueId, CallbackId);
delete(Context, _, _, _) ->
    cb_context:add_system_error('faulty_request', Context).

-spec delete_account(cb_context:context(), path_token()) -> cb_context:context().
delete_account(Context, AccountId) ->
    lager:debug("account ~s is being deleted, cleaning up ~s", [AccountId, ?KZ_ACDC_DB]),
    deactivate_account_for_acdc(AccountId),
    Context.

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Load an instance from the database
%% @end
%%------------------------------------------------------------------------------
-spec read(kz_term:ne_binary(), cb_context:context()) -> cb_context:context().
read(Id, Context) ->
    Context1 = crossbar_doc:load(Id, Context, ?TYPE_CHECK_OPTION(<<"queue">>)),
    case cb_context:resp_status(Context1) of
        'success' -> load_queue_agents(Id, Context1);
        _Status -> Context1
    end.

%% Callback registrations are created only by the queue coordinator. The HTTP
%% surface intentionally provides bounded read and cancellation operations.
%% Loading the parent queue first preserves the existing account/queue scope
%% and never lets a callback ID act as an account-wide lookup oracle.
-spec validate_callback_list(cb_context:context(), kz_term:ne_binary()) ->
          cb_context:context().
validate_callback_list(Context, QueueId) ->
    case load_callback_queue(Context, QueueId) of
        {'ok', Context1} ->
            case decode_callback_cursor(QueueId, cb_context:req_value(Context1, <<"cursor">>)) of
                {'ok', Cursor} ->
                    PageSize = min(?MAX_CALLBACK_PAGE_SIZE, cb_context:pagination_page_size(Context1)),
                    list_callbacks(Context1, QueueId, Cursor, PageSize);
                {'error', 'invalid_cursor'} -> callback_error('invalid_cursor', <<"cursor">>, Context1)
            end;
        {'error', Context1} -> Context1
    end.

-spec validate_callback(cb_context:context(), kz_term:ne_binary(), kz_term:ne_binary(), http_method()) ->
          cb_context:context().
validate_callback(Context, QueueId, CallbackId, Verb)
  when Verb =:= ?HTTP_GET; Verb =:= ?HTTP_DELETE ->
    case load_callback_queue(Context, QueueId) of
        {'ok', Context1} ->
            case acdc_callback_store:get(cb_context:account_id(Context1), QueueId, CallbackId) of
                {'ok', Doc} -> callback_success(callback_public(Doc), Doc, Context1);
                {'error', Reason} -> callback_error(Reason, CallbackId, Context1)
            end;
        {'error', Context1} -> Context1
    end.

-spec load_callback_queue(cb_context:context(), kz_term:ne_binary()) ->
          {'ok', cb_context:context()} | {'error', cb_context:context()}.
load_callback_queue(Context, QueueId) ->
    Context1 = crossbar_doc:load(QueueId, Context, ?TYPE_CHECK_OPTION(<<"queue">>)),
    case cb_context:resp_status(Context1) of
        'success' -> {'ok', Context1};
        _ -> {'error', Context1}
    end.

-spec list_callbacks(cb_context:context(), kz_term:ne_binary(), 'undefined' | list(), pos_integer()) ->
          cb_context:context().
list_callbacks(Context, QueueId, Cursor, PageSize) ->
    case acdc_callback_store:list(cb_context:account_id(Context), QueueId, Cursor, PageSize) of
        {'ok', Docs, NextCursor} ->
            Public = [callback_public(Doc) || Doc <- Docs],
            Envelope = kz_json:set_values(
                         props:filter_undefined(
                           [{<<"page_size">>, length(Public)}
                           ,{<<"next_cursor">>, encode_callback_cursor(NextCursor)}
                           ]), cb_context:resp_envelope(Context)),
            cb_context:setters(Context
                              ,[{fun cb_context:set_doc/2, Docs}
                               ,{fun cb_context:set_resp_status/2, 'success'}
                               ,{fun cb_context:set_resp_data/2, Public}
                               ,{fun cb_context:set_resp_etag/2, 'automatic'}
                               ,{fun cb_context:set_resp_envelope/2, Envelope}
                               ]);
        {'error', Reason} -> callback_error(Reason, QueueId, Context)
    end.

-spec cancel_callback(cb_context:context(), kz_term:ne_binary(), kz_term:ne_binary()) ->
          cb_context:context().
cancel_callback(Context, QueueId, CallbackId) ->
    case acdc_callback_store:cancel(cb_context:account_id(Context), QueueId, CallbackId) of
        {'ok', Doc} -> callback_success(callback_public(Doc), Doc, Context);
        {'error', Reason} -> callback_error(Reason, CallbackId, Context)
    end.

-spec callback_success(kz_json:object(), kz_json:object(), cb_context:context()) ->
          cb_context:context().
callback_success(Public, Doc, Context) ->
    cb_context:setters(Context
                      ,[{fun cb_context:set_doc/2, Doc}
                       ,{fun cb_context:set_resp_status/2, 'success'}
                       ,{fun cb_context:set_resp_data/2, Public}
                       ,{fun cb_context:set_resp_etag/2, crossbar_doc:rev_to_etag(Doc)}
                       ]).

%% This projection is deliberately narrower than acdc_callback_store:public/1.
%% Caller numbers, original call IDs, leases and live leg IDs must never cross
%% the HTTP boundary.
-spec callback_public(kz_json:object()) -> kz_json:object().
callback_public(Doc) ->
    Keys = [<<"queue_id">>, <<"status">>, <<"attempts">>, <<"enqueued_at">>
           ,<<"enqueue_sequence">>, <<"priority">>, <<"language">>
           ,<<"next_attempt_at">>, <<"expires_at">>, <<"last_cause">>],
    Values = [{Key, Value} || Key <- Keys,
                              (Value = kz_json:get_value(Key, Doc)) =/= 'undefined'],
    kz_json:from_list(props:filter_undefined(
                        [{<<"id">>, kz_doc:id(Doc)}
                        ,{<<"created">>, kz_doc:created(Doc)}
                        ,{<<"modified">>, kz_doc:modified(Doc)}
                        | Values ++ callback_reconciliation_public(Doc)])).

-spec callback_reconciliation_public(kz_json:object()) -> kz_term:proplist().
callback_reconciliation_public(Doc) ->
    case kz_json:is_true(<<"reconciliation_required">>, Doc, 'false') of
        'false' -> [];
        'true' ->
            Reason = kz_json:get_ne_binary_value(<<"reconciliation_reason">>, Doc),
            Allowed = [<<"engine_restart">>, <<"owner_lost">>
                      ,<<"channel_snapshot_incomplete">>, <<"originate_pending">>
                      ,<<"cleanup_pending">>, <<"bridge_proof_pending">>],
            [{<<"reconciliation_required">>, 'true'}
            ,{<<"reconciliation_reason">>,
              case lists:member(Reason, Allowed) of 'true' -> Reason; 'false' -> 'undefined' end}]
    end.

-spec encode_callback_cursor('undefined' | list()) -> kz_term:api_binary().
encode_callback_cursor('undefined') -> 'undefined';
encode_callback_cursor(Cursor) -> kz_base64url:encode(kz_json:encode(Cursor)).

-spec decode_callback_cursor(kz_term:ne_binary(), kz_term:api_binary()) ->
          {'ok', 'undefined' | list()} | {'error', 'invalid_cursor'}.
decode_callback_cursor(_QueueId, 'undefined') -> {'ok', 'undefined'};
decode_callback_cursor(_QueueId, <<>>) -> {'ok', 'undefined'};
decode_callback_cursor(QueueId, Encoded) when is_binary(Encoded), byte_size(Encoded) =< 2048 ->
    try kz_json:decode(kz_base64url:decode(Encoded)) of
        [QueueId, Timestamp, Sequence, Id]=Cursor
          when is_integer(Timestamp), Timestamp >= 1, Timestamp =< 16#1fffffffffffff,
               is_integer(Sequence), Sequence >= 0, Sequence =< 16#1fffffffffffff ->
            case valid_callback_id(Id) of
                'true' -> {'ok', Cursor};
                'false' -> {'error', 'invalid_cursor'}
            end;
        _ -> {'error', 'invalid_cursor'}
    catch
        _:_ -> {'error', 'invalid_cursor'}
    end;
decode_callback_cursor(_, _) -> {'error', 'invalid_cursor'}.

valid_callback_id(<<"acdc-callback-", Hex:64/binary>>) -> all_lower_hex(Hex);
valid_callback_id(_) -> 'false'.

all_lower_hex(<<>>) -> 'true';
all_lower_hex(<<C, Rest/binary>>)
  when (C >= $0 andalso C =< $9) orelse (C >= $a andalso C =< $f) ->
    all_lower_hex(Rest);
all_lower_hex(_) -> 'false'.

-spec callback_error(atom(), kz_term:api_ne_binary(), cb_context:context()) ->
          cb_context:context().
callback_error('invalid_cursor', _, Context) ->
    cb_context:add_validation_error(<<"cursor">>, <<"invalid">>
                                   ,kz_json:from_list([{<<"message">>, <<"Invalid callback page cursor">>}])
                                   ,Context);
callback_error('already_finished', CallbackId, Context) ->
    cb_context:add_system_error(409, <<"callback_already_finished">>
                                ,kz_json:from_list([{<<"message">>, <<"Finished callbacks cannot be cancelled">>}
                                                  ,{<<"cause">>, CallbackId}])
                                ,Context);
callback_error('not_found', CallbackId, Context) ->
    crossbar_doc:handle_datamgr_errors('not_found', CallbackId, Context);
callback_error('conflict', CallbackId, Context) ->
    crossbar_doc:handle_datamgr_errors('conflict', CallbackId, Context);
callback_error(Reason, Id, Context)
  when Reason =:= 'invalid_db_name'; Reason =:= 'db_not_reachable';
       Reason =:= 'invalid_view_name'; Reason =:= 'memory_exceeded' ->
    crossbar_doc:handle_datamgr_errors(Reason, Id, Context);
callback_error(_Reason, _Id, Context) ->
    cb_context:add_system_error('datastore_fault', Context).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec validate_request(kz_term:api_binary(), cb_context:context()) -> cb_context:context().
validate_request(QueueId, Context) ->
    check_queue_schema(QueueId, Context).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec validate_patch(kz_term:api_binary(), cb_context:context()) -> cb_context:context().
validate_patch(QueueId, Context) ->
    crossbar_doc:patch_and_validate(QueueId, Context, fun validate_request/2).

check_queue_schema(QueueId, Context) ->
    OnSuccess = fun(C) -> on_successful_validation(QueueId, C) end,
    cb_context:validate_request_data(<<"queues">>, Context, OnSuccess).

on_successful_validation('undefined', Context) ->
    Props = [{<<"pvt_type">>, <<"queue">>}],
    cb_context:set_doc(Context, kz_json:set_values(Props, cb_context:doc(Context)));
on_successful_validation(QueueId, Context) ->
    crossbar_doc:load_merge(QueueId, Context, ?TYPE_CHECK_OPTION(<<"queue">>)).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
load_queue_agents(Id, Context) ->
    Context1 = load_agent_roster(Id, Context),
    case cb_context:resp_status(Context1) of
        'success' ->
            Agents = kz_json:set_value(<<"agents">>
                                      ,cb_context:resp_data(Context1)
                                      ,cb_context:resp_data(Context)
                                      ),
            cb_context:setters(Context, [{fun cb_context:set_resp_data/2, Agents}
                                         %% Because the response can be dynamic depending on the results of Context1, the
                                         %% etag of Context cannot be trusted as a strong cache validator
                                        ,{fun cb_context:set_resp_etag/2, 'undefined'}
                                        ]);
        _Status -> Context1
    end.

load_agent_roster(Id, Context) ->
    Options = [{'startkey', [Id]}
              ,{'endkey', [Id, kz_json:new()]}
              ,{'mapper', crossbar_view:get_id_fun()}
              ,{'reduce', 'false'}
              ],
    crossbar_view:load(Context, ?CB_AGENTS_LIST, Options).

%% Membership replacement/removal must inspect every current member, regardless
%% of the client's list pagination parameters. Keep normal GET pagination intact.
-spec load_full_agent_roster(kz_term:ne_binary(), cb_context:context()) -> cb_context:context().
load_full_agent_roster(Id, Context) ->
    %% Cursor, start-key, fields and filter query options are presentation
    %% controls, never authority for a membership replacement/removal.
    Query = cb_context:query_string(Context),
    Internal = cb_context:set_query_string(cb_context:set_should_paginate(Context, 'false'), kz_json:new()),
    Result = load_agent_roster(Id, Internal),
    cb_context:set_query_string(Result, Query).

add_queue_to_agents(Id, Context) ->
    add_queue_to_agents(Id, Context, cb_context:req_data(Context)).

add_queue_to_agents(Id, Context, []) ->
    lager:debug("no agents listed, removing all agents from ~s", [Id]),

    Context1 = load_full_agent_roster(Id, Context),
    CurrAgentIds = cb_context:resp_data(Context1),

    rm_queue_from_agents(Id, Context1, CurrAgentIds);
add_queue_to_agents(Id, Context, AgentIds) ->
    %% We need to figure out what agents are on the queue already, and remove those not
    %% in the AgentIds list
    Context1 = load_full_agent_roster(Id, Context),
    CurrAgentIds = cb_context:resp_data(Context1),

    {InQueueAgents, RmAgentIds} = lists:partition(fun(A) -> lists:member(A, AgentIds) end, CurrAgentIds),
    AddAgentIds = [A || A <- AgentIds, (not lists:member(A, InQueueAgents))],

    _ = maybe_rm_agents(Id, Context, RmAgentIds),
    add_queue_to_agents_diff(Id, Context, AddAgentIds).

add_queue_to_agents_diff(_Id, Context, []) ->
    lager:debug("no more agent ids to add to queue"),
    cb_context:set_doc(cb_context:set_resp_status(Context, 'success'), []);
add_queue_to_agents_diff(Id, Context, AgentIds) ->
    Context1 = crossbar_doc:load(AgentIds, Context, ?TYPE_CHECK_OPTION(<<"user">>)),
    case cb_context:resp_status(Context1) of
        'success' ->
            cb_context:set_doc(Context1
                              ,[maybe_add_queue_to_agent(Id, A) || A <- cb_context:doc(Context1)]
                              );
        _Status -> Context1
    end.

-spec maybe_add_queue_to_agent(kz_term:ne_binary(), kz_json:object()) -> kz_json:object().
maybe_add_queue_to_agent(Id, A) ->
    Qs = case kz_json:get_value(<<"queues">>, A) of
             L when is_list(L) ->
                 case lists:member(Id, L) of
                     'true' -> L;
                     'false' -> [Id | L]
                 end;
             _ -> [Id]
         end,
    lager:debug("agent ~s adding queues: ~p", [kz_doc:id(A), Qs]),
    kz_json:set_value(<<"queues">>, Qs, A).

-spec maybe_rm_agents(kz_term:ne_binary(), cb_context:context(), kz_json:path()) -> cb_context:context().
maybe_rm_agents(_Id, Context, []) ->
    lager:debug("no agents to remove from the queue ~s", [_Id]),
    cb_context:set_resp_status(Context, 'success');
maybe_rm_agents(Id, Context, AgentIds) ->
    RMContext = rm_queue_from_agents(Id, Context, AgentIds),
    RMContext1 = crossbar_doc:save(RMContext),
    lager:debug("rm resulted in ~s", [cb_context:resp_status(RMContext1)]),
    RMContext1.

-spec rm_queue_from_agents(kz_term:ne_binary(), cb_context:context()) ->
          cb_context:context().
rm_queue_from_agents(Id, Context) ->
    Context1 = load_full_agent_roster(Id, Context),
    rm_queue_from_agents(Id, Context, cb_context:doc(Context1)).

-spec rm_queue_from_agents(kz_term:ne_binary(), cb_context:context(), kz_json:path()) ->
          cb_context:context().
rm_queue_from_agents(_Id, Context, []) ->
    cb_context:set_resp_status(Context, 'success');
rm_queue_from_agents(Id, Context, [_|_]=AgentIds) ->
    lager:debug("remove agents: ~p", [AgentIds]),
    Context1 = crossbar_doc:load(AgentIds, Context, ?TYPE_CHECK_OPTION(<<"user">>)),
    case cb_context:resp_status(Context1) of
        'success' ->
            lager:debug("removed agents successfully"),
            cb_context:set_doc(Context1
                              ,[maybe_rm_queue_from_agent(Id, A) || A <- cb_context:doc(Context1)]
                              );
        _Status -> Context1
    end;
rm_queue_from_agents(_Id, Context, _Data) ->
    cb_context:setters(Context
                      ,[{fun cb_context:set_resp_status/2, 'success'}
                       ,{fun cb_context:set_doc/2, 'undefined'}
                       ]).

-spec maybe_rm_queue_from_agent(kz_term:ne_binary(), kz_json:object()) -> kz_json:object().
maybe_rm_queue_from_agent(Id, A) ->
    Qs = kz_json:get_value(<<"queues">>, A, []),
    kz_json:set_value(<<"queues">>, lists:delete(Id, Qs), A).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec fetch_all_queue_stats(cb_context:context()) -> cb_context:context().
fetch_all_queue_stats(Context) ->
    case cb_context:req_value(Context, <<"start_range">>) of
        'undefined' -> fetch_all_current_queue_stats(Context);
        StartRange -> fetch_ranged_queue_stats(Context, StartRange)
    end.

-spec fetch_all_current_queue_stats(cb_context:context()) -> cb_context:context().
fetch_all_current_queue_stats(Context) ->
    lager:debug("querying for all recent stats"),
    Now = kz_time:now_s(),
    From = Now - ?ACDC_CLEANUP_WINDOW,

    Req = props:filter_undefined(
            [{<<"Account-ID">>, cb_context:account_id(Context)}
            ,{<<"Status">>, cb_context:req_value(Context, <<"status">>)}
            ,{<<"Agent-ID">>, cb_context:req_value(Context, <<"agent_id">>)}
            ,{<<"Start-Range">>, From}
            ,{<<"End-Range">>, Now}
             | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
            ]),
    fetch_from_amqp(Context, Req).

format_stats(Context, Resp) ->
    Stats = kz_json:from_list([{<<"current_timestamp">>, kz_time:now_s()}
                              ,{<<"stats">>,
                                kz_doc:public_fields(
                                  kz_json:get_value(<<"Handled">>, Resp, []) ++
                                      kz_json:get_value(<<"Abandoned">>, Resp, []) ++
                                      kz_json:get_value(<<"Waiting">>, Resp, []) ++
                                      kz_json:get_value(<<"Processed">>, Resp, [])
                                 )}
                              ]),
    cb_context:set_resp_status(cb_context:set_resp_data(Context, Stats)
                              ,'success'
                              ).

fetch_ranged_queue_stats(Context, StartRange) ->
    MaxRange = ?ACDC_CLEANUP_WINDOW,

    Now = kz_time:now_s(),
    Past = Now - MaxRange,

    To = kz_term:to_integer(cb_context:req_value(Context, <<"end_range">>, Now)),

    case kz_term:to_integer(StartRange) of
        F when F > To ->
            %% start_range is larger than end_range
            Msg = kz_json:from_list([{<<"message">>, <<"value is greater than start_range">>}
                                    ,{<<"cause">>, StartRange}
                                    ]),
            cb_context:add_validation_error(<<"end_range">>, <<"maximum">>, Msg, Context);
        F when F < Past, To > Past ->
            %% range overlaps archived/real data, use real
            fetch_ranged_queue_stats(Context, Past, To, 'true');
        F ->
            fetch_ranged_queue_stats(Context, F, To, F >= Past)
    end.

fetch_ranged_queue_stats(Context, From, To, 'true') ->
    lager:debug("ranged query from ~b to ~b(~b) of current stats (now ~b)", [From, To, To-From, kz_time:now_s()]),
    Req = props:filter_undefined(
            [{<<"Account-ID">>, cb_context:account_id(Context)}
            ,{<<"Status">>, cb_context:req_value(Context, <<"status">>)}
            ,{<<"Agent-ID">>, cb_context:req_value(Context, <<"agent_id">>)}
            ,{<<"Start-Range">>, From}
            ,{<<"End-Range">>, To}
             | kz_api:default_headers(?APP_NAME, ?APP_VERSION)
            ]),
    fetch_from_amqp(Context, Req);
fetch_ranged_queue_stats(Context, From, To, 'false') ->
    lager:debug("ranged query from ~b to ~b of archived stats", [From, To]),
    Context.

-spec fetch_from_amqp(cb_context:context(), kz_term:proplist()) -> cb_context:context().
fetch_from_amqp(Context, Req) ->
    case kz_amqp_worker:call(Req
                            ,fun kapi_acdc_stats:publish_current_calls_req/1
                            ,fun kapi_acdc_stats:current_calls_resp_v/1
                            )
    of
        {'error', _E} ->
            lager:debug("failed to recv resp from AMQP: ~p", [_E]),
            cb_context:add_system_error('datastore_unreachable', Context);
        {'ok', Resp} -> format_stats(Context, Resp)
    end.

%%------------------------------------------------------------------------------
%% @doc Attempt to load a summarized listing of all instances of this
%% resource.
%% @end
%%------------------------------------------------------------------------------
-spec summary(cb_context:context()) -> cb_context:context().
summary(Context) ->
    crossbar_view:load(Context, ?CB_LIST, [{'mapper', crossbar_view:get_value_fun()}]).

%%------------------------------------------------------------------------------
%% @doc Creates an entry in the acdc db of the account's participation in acdc
%% @end
%%------------------------------------------------------------------------------
-spec activate_account_for_acdc(cb_context:context()) -> 'ok'.
activate_account_for_acdc(Context) ->
    case kz_datamgr:open_cache_doc(?KZ_ACDC_DB, cb_context:account_id(Context)) of
        {'ok', _} -> 'ok';
        {'error', 'not_found'} ->
            lager:debug("creating account doc ~s in acdc db", [cb_context:account_id(Context)]),
            Doc = kz_doc:update_pvt_parameters(kz_json:from_list([{<<"_id">>, cb_context:account_id(Context)}])
                                              ,?KZ_ACDC_DB
                                              ,[{'account_id', cb_context:account_id(Context)}
                                               ,{'type', <<"acdc_activation">>}
                                               ]),
            {'ok', _} = kz_datamgr:ensure_saved(?KZ_ACDC_DB, Doc),
            'ok';
        {'error', _E} ->
            lager:debug("failed to check acdc activation doc: ~p", [_E])
    end.

-spec deactivate_account_for_acdc(kz_term:ne_binary()) -> 'ok'.
deactivate_account_for_acdc(AccountId) ->
    case kz_datamgr:open_doc(?KZ_ACDC_DB, AccountId) of
        {'error', _} -> 'ok';
        {'ok', JObj} ->
            case kz_datamgr:del_doc(?KZ_ACDC_DB, JObj) of
                {'ok', _} ->
                    lager:debug("removed ~s from ~s", [AccountId, ?KZ_ACDC_DB]);
                {'error', _E} ->
                    lager:debug("failed to remove ~s: ~p", [AccountId, _E])
            end
    end.
