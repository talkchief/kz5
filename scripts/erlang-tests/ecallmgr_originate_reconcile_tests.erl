%%% SPDX-License-Identifier: MPL-2.0
-module(ecallmgr_originate_reconcile_tests).

-include_lib("eunit/include/eunit.hrl").

-define(UUID, <<"originate-uuid">>).
-define(REQUEST, <<"originate-request">>).
-define(CALLER, <<"caller-uuid">>).

api_contract_requires_exact_correlation_test() ->
    Request = reconcile_request(),
    ?assertEqual(true, kapi_call:originate_reconcile_req_v(Request)),
    ?assertEqual(false, kapi_call:originate_reconcile_req_v(
                          props:delete(<<"Originate-Request-ID">>, Request))),
    Response = reconcile_response(<<"pending">>,
                                  [{<<"Media-Node">>, <<"freeswitch@one">>}
                                  ,{<<"Module-Epoch">>, <<"epoch-one">>}]),
    ?assertEqual(true, kapi_call:originate_reconcile_resp_v(Response)),
    ?assertEqual(false, kapi_call:originate_reconcile_resp_v(
                          kz_json:set_value(<<"Status">>, <<"absent">>, Response))).

switch_response_parser_is_fail_closed_test() ->
    Pending = ecallmgr_fs_channels:parse_originate_reconcile(
                <<"freeswitch@one">>, {ok, <<"+OK PENDING epoch-one\n">>}),
    ?assertEqual(<<"pending">>, maps:get(status, Pending)),
    Settled = ecallmgr_fs_channels:parse_originate_reconcile(
                <<"freeswitch@one">>,
                {ok, <<"+OK SETTLED success epoch-one caller-uuid\n">>}),
    ?assertEqual(<<"settled">>, maps:get(status, Settled)),
    ?assertEqual(?CALLER, maps:get(result_call_id, Settled)),
    Unknown = ecallmgr_fs_channels:parse_originate_reconcile(
                <<"freeswitch@one">>, {ok, <<"-ERR UNKNOWN epoch-two\n">>}),
    ?assertEqual(<<"unknown">>, maps:get(status, Unknown)),
    lists:foreach(
      fun(Reply) ->
          Parsed = ecallmgr_fs_channels:parse_originate_reconcile(<<"freeswitch@one">>, Reply),
          ?assertEqual(<<"unknown">>, maps:get(status, Parsed))
      end, [{error, timeout}, {ok, <<>>}, {ok, <<"+OK SETTLED success missing-call-id">>}]).

only_one_media_node_may_be_authoritative_test() ->
    Pending = #{status => <<"pending">>, media_node => <<"freeswitch@one">>
               ,module_epoch => <<"epoch-one">>},
    Unknown = #{status => <<"unknown">>, media_node => <<"freeswitch@two">>},
    ?assertEqual(Pending, ecallmgr_fs_channels:aggregate_originate_reconcile([Pending, Unknown])),
    Conflict = ecallmgr_fs_channels:aggregate_originate_reconcile(
                 [Pending, Pending#{media_node => <<"freeswitch@two">>}]),
    ?assertEqual(<<"unknown">>, maps:get(status, Conflict)),
    ?assertEqual(<<"conflicting_media_nodes">>, maps:get(detail, Conflict)),
    None = ecallmgr_fs_channels:aggregate_originate_reconcile([Unknown]),
    ?assertEqual(<<"unknown">>, maps:get(status, None)).

originate_command_carries_original_ids_before_dial_test() ->
    Dial = <<"{ignore_early_media=true}sofia/test &park()">>,
    ?assertEqual(<<"v2 originate-uuid originate-request caller-uuid ", Dial/binary>>,
                 ecallmgr_originate:originate_api_command(?UUID, ?REQUEST, ?CALLER, Dial)),
    %% Unsafe or missing metadata keeps the legacy wire shape and therefore
    %% cannot be claimed as reconcilable by the new status API.
    ?assertEqual(<<?UUID/binary, " ", Dial/binary>>,
                 ecallmgr_originate:originate_api_command(?UUID, <<"bad request">>, ?CALLER, Dial)),
    ?assertEqual(<<?UUID/binary, " ", Dial/binary>>,
                 ecallmgr_originate:originate_api_command(?UUID, undefined, ?CALLER, Dial)).

reconcile_request() ->
    [{<<"Originate-UUID">>, ?UUID}
    ,{<<"Originate-Request-ID">>, ?REQUEST}
    ,{<<"Outbound-Call-ID">>, ?CALLER}
    ,{<<"Operation">>, <<"status">>}
    ,{<<"Msg-ID">>, <<"fresh-query">>}
     | kz_api:default_headers(<<"channel">>, <<"originate_reconcile_req">>
                             ,<<"test">>, <<"1">>)].

reconcile_response(Status, Extra) ->
    kz_json:from_list([{<<"Originate-UUID">>, ?UUID}
                      ,{<<"Originate-Request-ID">>, ?REQUEST}
                      ,{<<"Outbound-Call-ID">>, ?CALLER}
                      ,{<<"Operation">>, <<"status">>}
                      ,{<<"Status">>, Status}
                      ,{<<"Msg-ID">>, <<"fresh-query">>}
                       | Extra ++ kz_api:default_headers(<<"channel">>, <<"originate_reconcile_resp">>
                                                       ,<<"ecallmgr">>, <<"5">>)]).
