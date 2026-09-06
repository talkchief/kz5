%%% SPDX-License-Identifier: MPL-2.0
%%% Public Blackhole entry points with in-memory auth/provider substitutes.
%%% This is a redaction/dispatch regression, not a JWT or live WebSocket proof.
-module(blackhole_auth_redaction_tests).
-include_lib("eunit/include/eunit.hrl").

-define(SECRET, <<"BLACKHOLE_FIXTURE_SECRET">>).
-define(ACCOUNT, <<"fixture-account">>).
-define(REQUEST, <<"fixture-request">>).
-define(ACTION, <<"fixture">>).

redaction_test_() ->
    {setup, fun setup/0, fun cleanup/1,
     [{"valid token is retained but never logged", fun successful_auth/0},
      {"already authorized context bypass is unchanged", fun authorized_bypass/0},
      {"denied text frames emit sanitized errors and never dispatch commands", fun denied_frames/0},
      {"valid text frame still reaches command dispatch", fun successful_frame/0},
      {"handshake denials preserve HTTP 403 without logging reasons", fun denied_handshakes/0},
      {"valid handshake preserves account and authorization", fun successful_handshake/0},
      {"unsupported binary frame contents are not logged", fun unsupported_frame/0},
      {"empty context token still reaches the validator", fun empty_token/0}]}.

mocks() -> [lager, kz_auth, kz_nodes, kz_buckets, kapps_config, cowboy_req,
            blackhole_tracking, blackhole_bindings].

setup() ->
    Bindings = ets:new(kazoo_bindings, [named_table, public, bag]),
    ok = meck:new(lager, [non_strict, no_link]),
    lists:foreach(fun(M) -> ok = meck:new(M, [no_link]) end,
                  [kz_auth, kz_nodes, kz_buckets, kapps_config, cowboy_req, blackhole_tracking]),
    ok = meck:new(blackhole_bindings, [passthrough, no_link]),
    lists:foreach(fun(Level) ->
        meck:expect(lager, Level, fun(_) -> ok end),
        meck:expect(lager, Level, fun(_, _) -> ok end)
    end, [debug, info, warning, error]),
    meck:expect(lager, md, fun() ->
        case erlang:get(blackhole_redaction_metadata) of undefined -> []; Metadata -> Metadata end
    end),
    meck:expect(lager, md, fun(Metadata) when is_list(Metadata) ->
        erlang:put(blackhole_redaction_metadata, Metadata), ok
    end),
    meck:expect(kz_nodes, node_hostname, fun() -> <<"fixture.invalid">> end),
    meck:expect(kz_buckets, consume_token,
                fun(<<"blackhole">>, <<"fixture-session">>) -> true end),
    meck:expect(kapps_config, get_integer,
                fun(<<"blackhole">>, <<"max_connections_per_ip">>) -> 10 end),
    meck:expect(kapps_config, get_integer,
                fun(<<"blackhole">>, <<"max_queued_messages">>, 50) -> 50 end),
    meck:expect(cowboy_req, parse_header,
                fun(<<"sec-websocket-protocol">>, _) -> undefined;
                   (<<"authorization">>, _) -> ?SECRET
                end),
    meck:expect(cowboy_req, peer, fun(_) -> {{127, 0, 0, 1}, 9999} end),
    meck:expect(cowboy_req, header, fun(<<"x-forwarded-for">>, _) -> undefined end),
    meck:expect(cowboy_req, reply, fun(403, Req) -> Req#{fixture_status => 403} end),
    meck:expect(blackhole_tracking, session_count_by_ip, fun(<<"127.0.0.1">>) -> 0 end),
    meck:expect(blackhole_bindings, map, fun dispatch/2),
    meck:expect(blackhole_bindings, fold,
                fun(<<"blackhole.finish.fixture">>, C, []) -> C end),
    Bindings.

cleanup(Bindings) ->
    meck:unload(mocks()),
    ets:delete(Bindings).

dispatch(<<"blackhole.authenticate.fixture">>, [Context, Payload]) ->
    [bh_token_auth:authenticate(Context, Payload)];
dispatch(Event, [Context, _Payload]) ->
    ?assert(lists:member(Event, [<<"blackhole.validate.fixture">>,
                                <<"blackhole.authorize.fixture">>,
                                <<"blackhole.limits.fixture">>,
                                <<"blackhole.command.fixture">>])),
    [Context].

configure(Result) ->
    erlang:erase(blackhole_redaction_metadata),
    meck:expect(kz_auth, validate_token,
                fun(?SECRET) -> Result;
                   (<<>>) -> Result
                end),
    lists:foreach(fun meck:reset/1, mocks()).

context() -> bh_context:new(self(), <<"fixture-session">>).
claims() -> kz_json:from_list([{<<"account_id">>, ?ACCOUNT}]).
frame() ->
    kz_json:encode(kz_json:from_list([{<<"action">>, ?ACTION},
                                    {<<"auth_token">>, ?SECRET},
                                    {<<"request_id">>, ?REQUEST}])).
reasons() -> [invalid_jwt, token_expired, {upstream, #{authorization => ?SECRET}}].

assert_clean_logs() ->
    History = meck:history(lager),
    ?assert(History =/= []),
    ?assertEqual(nomatch, binary:match(term_to_binary(History), ?SECRET)).

assert_no_reply() ->
    receive {send_data, _} -> ?assert(false)
    after 0 -> ok
    end.

successful_auth() ->
    configure({ok, claims()}),
    Before = bh_context:set_auth_token(context(), ?SECRET),
    After = bh_token_auth:authenticate(Before, kz_json:new()),
    ?assertEqual(bh_context:set_auth_account_id(Before, ?ACCOUNT), After),
    ?assertEqual(?SECRET, bh_context:auth_token(After)),
    ?assertEqual(true, bh_context:is_authenticated(After)),
    ?assertEqual(false, bh_context:authorized(After)),
    ?assert(meck:called(kz_auth, validate_token, [?SECRET])),
    ?assert(meck:called(lager, debug, ["trying to authenticate with token"])),
    assert_clean_logs().

authorized_bypass() ->
    configure({error, unexpected_validation}),
    Before = bh_context:set_authorized(bh_context:set_auth_account_id(
                bh_context:set_auth_token(context(), ?SECRET), ?ACCOUNT)),
    ?assertEqual(Before, bh_token_auth:authenticate(Before, kz_json:new())),
    ?assertEqual([], meck:history(kz_auth)),
    ?assertEqual([], meck:history(lager)).

denied_frames() ->
    lists:foreach(fun(Reason) ->
        configure({error, Reason}),
        Before = context(),
        ?assertEqual({ok, Before, hibernate},
                     blackhole_socket_handler:websocket_handle({text, frame()}, Before)),
        Expected = kz_json:from_list([{<<"action">>, <<"reply">>},
            {<<"request_id">>, ?REQUEST}, {<<"status">>, <<"error">>},
            {<<"data">>, kz_json:from_list([{<<"errors">>, [<<"failed to authenticate token">>]}])}]),
        receive
            {send_data, Reply} ->
                ?assertEqual(Expected, Reply),
                {reply, {text, Encoded}, Before} = blackhole_socket_handler:websocket_info({send_data, Reply}, Before),
                ?assertEqual(Expected, kz_json:decode(Encoded)),
                ?assertEqual(nomatch, binary:match(Encoded, ?SECRET))
        after 1000 -> ?assert(false)
        end,
        ?assert(meck:called(kz_auth, validate_token, [?SECRET])),
        ?assert(meck:called(lager, md, [[{callid, ?REQUEST}]])),
        Events = [Event || {_, {blackhole_bindings, map, [Event, _]}, _} <- meck:history(blackhole_bindings)],
        ?assertEqual([<<"blackhole.authenticate.fixture">>], Events),
        ?assert(meck:called(lager, debug, ["failed to authenticate token auth"])),
        assert_clean_logs(), assert_no_reply()
    end, reasons()).

successful_frame() ->
    configure({ok, claims()}),
    {ok, After, hibernate} = blackhole_socket_handler:websocket_handle({text, frame()}, context()),
    ?assertEqual(?ACCOUNT, bh_context:auth_account_id(After)),
    ?assertEqual(?SECRET, bh_context:auth_token(After)),
    ?assertEqual(?REQUEST, bh_context:req_id(After)),
    ?assertEqual([], bh_context:errors(After)),
    ?assert(meck:called(lager, md, [[{callid, ?REQUEST}]])),
    ?assert(meck:called(blackhole_bindings, map, [<<"blackhole.command.fixture">>, '_'])),
    assert_clean_logs(), assert_no_reply().

denied_handshakes() ->
    lists:foreach(fun(Reason) ->
        configure({error, Reason}),
        Req = #{fixture_request => true}, Options = [],
        ?assertEqual({ok, Req#{fixture_status => 403}, Options},
                     blackhole_socket_handler:init(Req, Options)),
        ?assert(meck:called(cowboy_req, reply, [403, Req])),
        ?assert(meck:called(kz_auth, validate_token, [?SECRET])),
        ?assertEqual([], meck:history(blackhole_bindings)),
        ?assert(meck:called(lager, debug, ["failed to authenticate token auth"])),
        assert_clean_logs(), assert_no_reply()
    end, reasons()).

successful_handshake() ->
    configure({ok, claims()}),
    Req = #{fixture_request => true},
    {cowboy_websocket, Req, Context, #{idle_timeout := 3600000}} = blackhole_socket_handler:init(Req, []),
    ?assertEqual(?ACCOUNT, bh_context:auth_account_id(Context)),
    ?assertEqual(?SECRET, bh_context:auth_token(Context)),
    ?assertEqual(true, bh_context:authorized(Context)),
    ?assertEqual(<<"127.0.0.1:9999">>, bh_context:websocket_session_id(Context)),
    ?assertNot(meck:called(cowboy_req, reply, '_')),
    assert_clean_logs().

unsupported_frame() ->
    configure({error, unexpected_validation}),
    Before = context(),
    ?assertEqual({ok, Before, hibernate},
                 blackhole_socket_handler:websocket_handle({binary, frame()}, Before)),
    ?assertEqual([], meck:history(kz_auth)),
    ?assertEqual([], meck:history(blackhole_bindings)),
    ?assert(meck:called(lager, debug, ["not handling unsupported websocket message"])),
    assert_clean_logs(), assert_no_reply().

empty_token() ->
    configure({error, invalid_jwt}),
    Before = context(),
    ?assertEqual(<<>>, bh_context:auth_token(Before)),
    After = bh_token_auth:authenticate(Before, kz_json:new()),
    ?assertEqual(bh_context:add_error(Before, <<"failed to authenticate token">>), After),
    ?assert(meck:called(kz_auth, validate_token, [<<>>])),
    assert_clean_logs().
