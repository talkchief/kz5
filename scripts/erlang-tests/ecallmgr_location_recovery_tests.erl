%%% SPDX-License-Identifier: MPL-2.0
%%% Public production fetch entry point; providers substituted only in private VM.
-module(ecallmgr_location_recovery_tests).
-include_lib("eunit/include/eunit.hrl").

location_test_() ->
    {setup, fun setup/0, fun cleanup/1,
     [{"cold cache consults authoritative proxy", fun cold_cache/0},
      {"missing cached path consults proxy", fun missing_path/0},
      {"warm cache remains local", fun warm_cache/0},
      {"bounded timeout returns not found", fun timeout_response/0},
      {"malformed replies fail closed", fun malformed/0},
      {"explicit proxy mode and WebRTC flags survive", fun explicit_proxy/0}]}.

mocks() -> [ecallmgr_registrar, kz_amqp_worker, kz_app_config, kz_log,
            kzd_fetch, ecallmgr_fs_xml, freeswitch].
setup() ->
    lists:foreach(fun(M) -> meck:new(M, [no_link]) end, mocks()),
    meck:expect(kz_log, put_callid, fun(_) -> ok end),
    meck:expect(kzd_fetch, fetch_action, fun(_) -> <<"call">> end),
    meck:expect(kzd_fetch, fetch_key_value, fun(_) -> <<"device@account">> end),
    meck:expect(ecallmgr_fs_xml, not_found, fun(<<"location">>) -> {ok, <<"not-found">>} end),
    meck:expect(ecallmgr_fs_xml, directory_resp_location_xml,
        fun(Proxy, Props, _) -> put(location_props, {Proxy, Props}), {ok, <<"found">>} end),
    meck:expect(freeswitch, fetch_reply, fun(#{reply := Reply}) -> Reply end),
    ok.
cleanup(_) -> meck:unload(mocks()).

configure(Cached, Response, Direct) ->
    erase(location_props),
    lists:foreach(fun meck:reset/1, mocks()),
    meck:expect(kz_app_config, get_boolean,
        fun(ecallmgr, <<"use_proxy_contact_api">>, false) -> Direct end),
    meck:expect(ecallmgr_registrar, lookup_proxy_path,
        fun(<<"account">>, <<"device">>) -> Cached end),
    %% Keep the old arity available in baseline mode; only real behavior
    %% differences, not a missing substitute, should fail before the fix.
    meck:expect(kz_amqp_worker, call, fun(_, _) -> Response end),
    meck:expect(kz_amqp_worker, call, fun(Req, Publish, Validate, Deadline) ->
        ?assertEqual(2000, Deadline),
        ?assertEqual(<<"device@account">>, proplists:get_value(<<"Token-ID">>, Req)),
        ?assertEqual(<<"token">>, proplists:get_value(<<"Search-Type">>, Req)),
        ?assertEqual(fun kapi_registration:publish_search_req/1, Publish),
        ?assertEqual(fun kapi_registration:search_resp_v/1, Validate),
        Response
    end).

response() ->
    {ok, kz_json:from_list([{<<"AOR">>, kz_json:from_list([
        {<<"uri">>, <<"sip:proxy.invalid:7000">>},
        {<<"aor">>, <<"sip:device@fixture.invalid">>},
        {<<"Proxy-Protocol">>, <<"wss">>}])}])}.
fetch() -> ecallmgr_fs_fetch_location:fetch_location(
    #{node => 'fixture@invalid', fetch_id => <<"fixture-fetch">>, payload => kz_json:new()}).

cold_cache() ->
    configure({error, not_found}, response(), false),
    ?assertEqual(<<"found">>, fetch()),
    ?assertEqual(1, meck:num_calls(kz_amqp_worker, call, '_')).
missing_path() ->
    configure({ok, undefined, []}, response(), false),
    ?assertEqual(<<"found">>, fetch()).
warm_cache() ->
    configure({ok, <<"sip:warm.invalid">>, []}, {error, timeout}, false),
    ?assertEqual(<<"found">>, fetch()),
    ?assertEqual(0, meck:num_calls(kz_amqp_worker, call, '_')).
timeout_response() ->
    configure({error, not_found}, {error, timeout}, false),
    ?assertEqual(<<"not-found">>, fetch()).
malformed() ->
    lists:foreach(fun(JObj) ->
        configure({error, not_found}, {ok, JObj}, false),
        ?assertEqual(<<"not-found">>, fetch())
    end, [kz_json:new(), kz_json:from_list([{<<"AOR">>, kz_json:new()}]),
          kz_json:from_list([{<<"AOR">>, kz_json:from_list([{<<"uri">>, <<"sip:proxy.invalid">>}])}])]).
explicit_proxy() ->
    configure({error, not_found}, response(), true),
    ?assertEqual(<<"found">>, fetch()),
    ?assertEqual(0, meck:num_calls(ecallmgr_registrar, lookup_proxy_path, '_')),
    {_, Props} = get(location_props),
    ?assertEqual(true, proplists:get_value(<<"Media-Webrtc">>, Props)),
    ?assertEqual(<<"sip:device@fixture.invalid">>, proplists:get_value(<<"KAZOO-AOR">>, Props)).
