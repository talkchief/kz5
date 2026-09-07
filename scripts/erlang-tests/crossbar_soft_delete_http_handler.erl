%%% Offline REST adapter only: no Crossbar authentication, routing or bindings.
%%% The ETag adapter matches api_resource's quoted document-revision form but
%%% deliberately does not execute its custom crossbar_bindings etag callbacks.
-module(crossbar_soft_delete_http_handler).
-export([init/2, allowed_methods/2, content_types_provided/2, resource_exists/2,
         generate_etag/2, delete_resource/2, terminate/3, representation/2]).

init(Req, Table) ->
    ets:insert(Table, {request_pid, self()}),
    {cowboy_rest, Req, #{table => Table}}.
allowed_methods(Req, State) -> {[<<"DELETE">>], Req, State}.
content_types_provided(Req, State) ->
    {[{<<"application/json">>, representation}], Req, State}.
representation(Req, State) -> {<<"{}">>, Req, State}.

resource_exists(Req, #{table := T}=State) ->
    Doc = ets:lookup_element(T, current, 2),
    Context0 = cb_context:setters(cb_context:new(),
        [{fun cb_context:set_doc/2, Doc},
         {fun cb_context:set_db_name/2, ets:lookup_element(T, db, 2)},
         {fun cb_context:set_account_id/2, kz_doc:account_id(Doc)},
         {fun cb_context:set_api_version/2, <<"v2">>},
         {fun cb_context:set_req_id/2, <<"offline-http-revision">>},
         {fun cb_context:set_req_verb/2, <<"DELETE">>},
         {fun cb_context:set_resp_status/2, success}]),
    Context = cb_context:set_req_headers(Context0, cowboy_req:headers(Req)),
    ets:insert(T, {validated_revision, kz_doc:revision(Doc)}),
    %% A deterministic competing write after validation, without altering the
    %% captured context or the ETag Cowboy subsequently evaluates.
    case ets:lookup_element(T, race, 2) of
        true -> ets:insert(T, {current, kz_json:set_values([
                    {<<"_rev">>, <<"2-concurrent">>},
                    {<<"fixture_marker">>, <<"concurrent-body">>}], Doc)});
        false -> ok
    end,
    {true, Req, State#{context => Context}}.

generate_etag(Req, #{context := Context}=State) ->
    Rev = crossbar_doc:rev_to_etag(cb_context:doc(Context)),
    {<<$", Rev/binary, $">>, Req, State}.

delete_resource(Req, #{table := T, context := Context}=State) ->
    ets:update_counter(T, delete_calls, 1),
    Result = crossbar_doc:delete(Context, true),
    ets:insert(T, {delete_status, cb_context:resp_status(Result)}),
    case cb_context:resp_status(Result) of
        success -> {true, Req, State};
        error ->
            %% Explicit adapter for Crossbar error context -> HTTP status.
            %% This does not test api_util:execute_request response handling.
            Code = cb_context:resp_error_code(Result),
            Req1 = cowboy_req:reply(Code, #{<<"content-length">> => <<"0">>}, <<>>, Req),
            {stop, Req1, State}
    end.

terminate(_Reason, _Req, #{table := T}) ->
    case ets:info(T) of
        undefined -> ok;
        _ ->
            ets:lookup_element(T, owner, 2) ! {soft_delete_http_done, ets:lookup_element(T, request_ref, 2)},
            ok
    end.
