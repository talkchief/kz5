%%% SPDX-License-Identifier: MPL-2.0
%%% Shared live-queue permission checks. No snapshots, subscriptions or events.
%%% fresh_token/3 starts from a NEW context and reruns native token validation;
%%% it never accepts a retained Blackhole authenticated account as authority.
%%% Native JWT/identity and legacy token-document caches remain native policy:
%%% this is not uncached validation or an instant global revocation guarantee.
%%% Requires Crossbar token/queue bindings active LOCALLY. Standalone Blackhole
%%% without that authority fails closed; remote authorization is not implemented.
%%% Provider calls are synchronous. Callers must impose their own worker/time
%%% budget; do not invoke this inside a latency-sensitive mutation mailbox.
-module(acdc_live_auth).
-export([authorize/1, permit/2, permit/3, fresh_token/3]).
-include_lib("crossbar/src/crossbar.hrl").

%% Preserve the existing public route's global-or-resource authorization and
%% scope semantics, including valid empty resource-specific callback lists.
-spec authorize(cb_context:context()) -> boolean().
authorize(C) ->
    [{Resource,Params}|_]=cb_context:req_nouns(C),
    Results=crossbar_bindings:pmap(api_util:create_event_name(C,<<"authorize">>),C) ++
        crossbar_bindings:pmap(api_util:create_event_name(C,<<"authorize.",Resource/binary>>),[C|Params]),
    lists:all(fun(true)->true;(false)->true;({true,_})->true;({false,_})->true;(_)->false end,Results) andalso
        lists:any(fun(true)->true;({true,_})->true;(_)->false end,Results) andalso scopes(C,Resource).

-spec permit(cb_context:context(), [binary()]) -> ok.
permit(C,Params) ->
    permit(C,<<"queues">>,Params).

-spec permit(cb_context:context(), binary(), [binary()]) -> ok.
permit(C,Resource,Params) ->
    Account=cb_context:account_id(C),
    Path=iolist_to_binary([<<"/">>,cb_context:api_version(C),<<"/accounts/">>,Account,
        <<"/">>,Resource,[[<<"/">>,P]||P<-Params]]),
    Sub=cb_context:setters(C,[{fun cb_context:set_req_nouns/2,[{Resource,Params},{<<"accounts">>,[Account]}]},
        {fun cb_context:set_raw_path/2,Path},
        {fun cb_context:set_req_verb/2,?HTTP_GET},{fun cb_context:set_query_string/2,kz_json:new()},
        {fun cb_context:set_resp_status/2,success},{fun cb_context:set_doc/2,kz_json:new()},
        {fun cb_context:set_req_data/2,kz_json:new()}]),
    case authorize(Sub) of
        true -> ok;
        false -> throw({live_error,403,<<"queue_live_resource_forbidden">>})
    end.

scopes(C,Resource) ->
    case {cb_context:auth_token_type(C),kz_json:get_ne_binary_value(<<"method">>,cb_context:auth_doc(C))} of
        {'x-auth-token',Method} when is_binary(Method) ->
            lists:all(fun(Required) when is_list(Required)->kz_auth_scope:all(cb_context:auth_token(C),Required);(_)->false end,
                crossbar_bindings:pmap(api_util:create_event_name(C,<<"allowed_scopes.",Resource/binary>>),Method));
        _ -> true
    end.

-spec fresh_token(binary(), binary(), binary()) ->
    {ok, cb_context:context()} | {error, invalid_scope | invalid_token | authentication_failed |
        forbidden | queue_unavailable | local_authorization_unavailable | authorization_unavailable}.
fresh_token(Token,Account,Queue) ->
    %% Reject untrusted scope/shape before binding discovery, token or DB reads.
    case {id(Account) andalso id(Queue), token(Token)} of
        {false,_} -> {error,invalid_scope};
        {_,false} -> {error,invalid_token};
        {true,true} -> fresh(Token,Account,Queue)
    end.

fresh(Token,Account,Queue) ->
    try
        require(local_ready(),local_authorization_unavailable),
        C=cb_context:setters(cb_context:new(),[
            {fun cb_context:set_account_id/2,Account},
            {fun cb_context:set_db_name/2,kzs_util:format_account_db(Account)},
            {fun cb_context:set_auth_token/2,Token},
            {fun cb_context:set_auth_token_type/2,'x-auth-token'},
            {fun cb_context:set_api_version/2,<<"v2">>},
            {fun cb_context:set_req_verb/2,?HTTP_GET},
            {fun cb_context:set_req_nouns/2,[{<<"queues">>,[Queue,<<"live">>]},{<<"accounts">>,[Account]}]},
            {fun cb_context:set_raw_path/2,queue_path(<<"v2">>,Account,[Queue,<<"live">>])},
            %% No claimed proxy origin is available from this token-only API.
            %% Native origin-restricted tokens must not inherit a fake proxy.
            {fun cb_context:set_proxy_ips/2,[]}]),
        case cb_token_auth:early_authenticate(C) of
            {true,Authenticated} -> authorized_queue(Authenticated,Token,Account,Queue);
            _ -> {error,authentication_failed}
        end
    catch
        throw:{live_auth_error,Why} -> {error,Why};
        throw:{live_error,_,_} -> {error,forbidden};
        _:_ -> {error,authorization_unavailable}
    end.

authorized_queue(C,Token,Account,Queue) ->
    ClaimsAccount=kz_json:get_value(<<"account_id">>,cb_context:auth_doc(C)),
    require(cb_context:is_authenticated(C) andalso id(ClaimsAccount) andalso
        cb_context:auth_account_id(C)=:=ClaimsAccount andalso cb_context:auth_token(C)=:=Token andalso
        cb_context:account_id(C)=:=Account andalso
        cb_context:db_name(C)=:=kzs_util:format_account_db(Account),authentication_failed),
    require(authorize(C),forbidden),
    permit(C,[<<"stats">>]),
    permit(C,[Queue]),
    case kz_datamgr:open_doc(cb_context:db_name(C),Queue) of
        {ok,D} ->
            require(kz_doc:id(D)=:=Queue andalso kz_doc:type(D)=:= <<"queue">> andalso
                kz_doc:account_id(D)=:=Account andalso not kz_doc:is_deleted(D) andalso
                not kz_doc:is_soft_deleted(D),forbidden),
            require(local_ready(),local_authorization_unavailable),
            {ok,C};
        {error,not_found} -> {error,forbidden};
        _ -> {error,queue_unavailable}
    end.

local_ready() ->
    try
        Modules=crossbar_bindings:modules_loaded(),
        lists:member(cb_token_auth,Modules) andalso lists:member(cb_queues,Modules)
    catch _:_ -> false end.
queue_path(Version,Account,Params) ->
    iolist_to_binary([<<"/">>,Version,<<"/accounts/">>,Account,<<"/queues">>,[[<<"/">>,P] || P<-Params]]).
id(B) when is_binary(B),byte_size(B)=:=32 -> re:run(B,<<"^[0-9a-f]{32}$">>,[{capture,none}])=:=match;
id(_) -> false.
token(B) when is_binary(B),byte_size(B)>0,byte_size(B)=<16384 ->
    re:run(B,<<"[\\x00-\\x20\\x7f]">>,[{capture,none}])=:=nomatch;
token(_) -> false.
require(true,_) -> ok;
require(false,Why) -> throw({live_auth_error,Why}).
