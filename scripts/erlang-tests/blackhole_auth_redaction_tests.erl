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
      {"cached native command identity cannot bypass rejected tokens", fun cached_token_rejected/0},
      {"native command token replacement requires reconnect", fun changed_token_rejected/0},
      {"native commands require a positive authentication handler", fun missing_auth_handler/0},
      {"cached native commands are freshly authenticated", fun cached_token_revalidated/0},
      {"denied text frames emit sanitized errors and never dispatch commands", fun denied_frames/0},
      {"mixed authentication failures stop both result orders", fun mixed_auth_results/0},
      {"valid text frame still reaches command dispatch", fun successful_frame/0},
      {"handshake denials preserve HTTP 403 without logging reasons", fun denied_handshakes/0},
      {"valid handshake preserves account and authorization", fun successful_handshake/0},
      {"unsupported binary frame contents are not logged", fun unsupported_frame/0},
      {"empty context token still reaches the validator", fun empty_token/0},
      {"early termination does not log arbitrary close reasons", fun early_close_reason/0}]}.

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
    meck:expect(kapps_config, get,
                fun(<<"blackhole">>, <<"max_frame_size_bytes">>, 65536) -> 65536 end),
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
        ?assertEqual([], Events),
        assert_clean_logs(), assert_no_reply()
    end, reasons()).

cached_context() ->
    bh_context:set_authorized(bh_context:set_auth_account_id(
        bh_context:set_auth_token(context(), ?SECRET), ?ACCOUNT)).

assert_command_denied(Before, Frame) ->
    ?assertEqual({ok, Before, hibernate},
        blackhole_socket_handler:websocket_handle({text, Frame}, Before)),
    receive {send_data, Reply} ->
        ?assertEqual(<<"error">>, kz_json:get_value(<<"status">>, Reply)),
        ?assertEqual(nomatch, binary:match(kz_json:encode(Reply), ?SECRET))
    after 1000 -> ?assert(false)
    end,
    ?assertNot(meck:called(blackhole_bindings, map, [<<"blackhole.command.fixture">>, '_'])),
    ?assertNot(meck:called(blackhole_bindings, fold, '_')),
    assert_clean_logs(), assert_no_reply().

cached_token_rejected() ->
    lists:foreach(fun(Reason) ->
        configure({error, Reason}),
        assert_command_denied(cached_context(), frame()),
        ?assert(meck:called(kz_auth, validate_token, [?SECRET]))
    end, reasons()),
    configure({ok, kz_json:new()}),
    assert_command_denied(cached_context(), frame()),
    configure({ok, kz_json:from_list([{<<"account_id">>, <<"different-account">>}])}),
    assert_command_denied(cached_context(), frame()),
    configure({error, unavailable}),
    meck:expect(kz_auth, validate_token, fun(_) -> erlang:error({unavailable, ?SECRET}) end),
    assert_command_denied(cached_context(), frame()).

changed_token_rejected() ->
    configure({ok, claims()}),
    Other = kz_json:set_value(<<"auth_token">>, <<"changed-token">>, kz_json:decode(frame())),
    assert_command_denied(cached_context(), kz_json:encode(Other)),
    ?assertEqual([], meck:history(kz_auth)).

missing_auth_handler() ->
    try
        lists:foreach(fun(Result) ->
            configure({ok, claims()}),
            meck:expect(blackhole_bindings, map, fun
                (<<"blackhole.authenticate.fixture">>, _) -> Result;
                (Event, Args) -> dispatch(Event, Args)
            end),
            assert_command_denied(cached_context(), frame())
        end, [[], [false], [true]])
    after meck:expect(blackhole_bindings, map, fun dispatch/2)
    end.

cached_token_revalidated() ->
    configure({ok, claims()}),
    WithoutToken = kz_json:delete_key(<<"auth_token">>, kz_json:decode(frame())),
    {ok, After, hibernate} = blackhole_socket_handler:websocket_handle(
        {text, kz_json:encode(WithoutToken)}, cached_context()),
    ?assertEqual(?ACCOUNT, bh_context:auth_account_id(After)),
    ?assertEqual(1, meck:num_calls(kz_auth, validate_token, [?SECRET])),
    ?assert(meck:called(blackhole_bindings, map, [<<"blackhole.command.fixture">>, '_'])),
    assert_clean_logs(), assert_no_reply().

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

mixed_auth_results() ->
    try
        lists:foreach(fun(Order) ->
            configure({ok, claims()}),
            meck:expect(blackhole_bindings, map, fun
                (<<"blackhole.authenticate.fixture">>=Event, Args) ->
                    [Good] = dispatch(Event, Args),
                    Bad = bh_context:add_error(Good, <<"fixture authentication denied">>),
                    case Order of good_first -> [Good,Bad]; bad_first -> [Bad,Good] end;
                (Event, Args) -> dispatch(Event, Args)
            end),
            Before = context(),
            ?assertEqual({ok,Before,hibernate}, blackhole_socket_handler:websocket_handle({text,frame()},Before)),
            receive {send_data, Reply} ->
                ?assertEqual(<<"error">>,kz_json:get_value(<<"status">>,Reply)),
                ?assertEqual([<<"fixture authentication denied">>],kz_json:get_value([<<"data">>,<<"errors">>],Reply)),
                ?assertEqual(nomatch,binary:match(kz_json:encode(Reply),?SECRET))
            after 1000 -> ?assert(false)
            end,
            Events = [Event || {_,{blackhole_bindings,map,[Event,_]},_} <- meck:history(blackhole_bindings)],
            ?assertEqual([<<"blackhole.authenticate.fixture">>],Events),
            ?assertNot(meck:called(blackhole_bindings,fold,'_')),
            assert_clean_logs(), assert_no_reply()
        end,[good_first,bad_first]),
        meck:expect(blackhole_bindings,map,fun
            (<<"blackhole.authenticate.fixture">>=Event,Args) ->
                [Good] = dispatch(Event,Args), [Good,Good];
            (Event,Args) -> dispatch(Event,Args)
        end),
        successful_frame()
    after meck:expect(blackhole_bindings,map,fun dispatch/2)
    end.

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
    {cowboy_websocket, Req, Context, #{idle_timeout := 3600000, max_frame_size := 65536}} = blackhole_socket_handler:init(Req, []),
    ?assertEqual(?ACCOUNT, bh_context:auth_account_id(Context)),
    ?assertEqual(?SECRET, bh_context:auth_token(Context)),
    ?assertEqual(true, bh_context:authorized(Context)),
    ?assertEqual(<<"127.0.0.1:9999">>, bh_context:websocket_session_id(Context)),
    ?assertNot(meck:called(cowboy_req, reply, '_')),
    assert_clean_logs().

unsupported_frame() ->
    configure({error, unexpected_validation}),
    Before = context(),
    ?assertEqual({reply, {close, 1003, <<"unsupported frame">>}, Before},
                 blackhole_socket_handler:websocket_handle({binary, frame()}, Before)),
    ?assertEqual([], meck:history(kz_auth)),
    ?assertEqual([], meck:history(blackhole_bindings)),
    ?assert(meck:called(lager, debug, ["closing unsupported websocket message"])),
    assert_clean_logs(), assert_no_reply().

empty_token() ->
    configure({error, invalid_jwt}),
    Before = context(),
    ?assertEqual(<<>>, bh_context:auth_token(Before)),
    After = bh_token_auth:authenticate(Before, kz_json:new()),
    ?assertEqual(bh_context:add_error(Before, <<"failed to authenticate token">>), After),
    ?assert(meck:called(kz_auth, validate_token, [<<>>])),
    assert_clean_logs().

early_close_reason() ->
    configure({error,unexpected_validation}),
    ?assertEqual(ok,blackhole_socket_handler:terminate({remote,1000,?SECRET},#{fixture_request => true},[])),
    ?assertEqual([],meck:history(blackhole_bindings)),
    assert_clean_logs().
