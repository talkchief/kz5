%%% SPDX-License-Identifier: MPL-2.0
%%% Real Cowboy/Ranch/Jiffy wire framing and Blackhole lifecycle, entirely inside
%%% a private network namespace. Fixture authentication and command providers do
%%% not establish JWT, account authorization, broker, or live deployment proof.
-module(blackhole_frame_wire_tests).
-include_lib("eunit/include/eunit.hrl").
-export([session_open/1, session_close/1, echo/2]).

-define(SECRET, <<"BH_FRAME_ONLY_SECRET">>).
-define(TABLE, blackhole_frame_fixture).
-define(LISTENER, blackhole_frame_wire_fixture).

frames_test_() ->
    {setup, fun setup/0, fun cleanup/1,
     [{"schema pin and raw configuration bounds", fun configuration/0},
      {"real Jiffy escaping, Unicode and trailing whitespace", fun valid_json/0},
      {"malformed, trailing and duplicate JSON never dispatch or log input", fun malformed_json/0},
      {"decoded scalars and arrays close without dispatch", fun nonobjects/0},
      {"callback errors remain outside the decode catch", fun callback_errors/0},
      {"ping/pong controls and unsupported direct frames", fun controls/0},
      {"wire malformed JSON closes 1007 and cleans session bindings", fun wire_malformed/0},
      {"wire nonobjects and binary frames close 1003 and clean sessions", fun wire_unsupported/0},
      {"wire exact frame bound accepts while bound plus one closes 1009", fun wire_boundary/0},
      {"wire fragmented aggregate bound is enforced", fun wire_fragments/0},
      {"wire default bound is finite at 65536 bytes", fun wire_default_bound/0},
      {"wire ping payload is auto-ponged and connection remains usable", fun wire_controls/0},
      {"wire client close reason is redacted while real cleanup runs", fun wire_close_reason/0}]}.

val(Key) -> [{Key, Value}] = ets:lookup(?TABLE, Key), Value.
put_value(Key, Value) -> ets:insert(?TABLE, {Key, Value}).
mocks() -> [lager, kz_nodes, kz_buckets, kz_auth, kapps_config, kz_app_config,
            gen_listener, blackhole_listener, blackhole_socket_callback].

setup() ->
    ets:new(?TABLE, [named_table, public]),
    ets:insert(?TABLE, [{max_bytes, absent}, {mode, capture}, {calls, 0}, {owner, self()}]),
    ok = meck:new(lager, [non_strict, no_link]),
    lists:foreach(fun(M) -> ok = meck:new(M, [no_link]) end,
                  [kz_nodes, kz_buckets, kz_auth, kapps_config, kz_app_config, gen_listener, blackhole_listener]),
    ok = meck:new(blackhole_socket_callback, [passthrough, no_link]),
    lists:foreach(fun(Level) ->
        meck:expect(lager, Level, fun(_) -> ok end),
        meck:expect(lager, Level, fun(_, _) -> ok end)
    end, [debug, info, warning, error]),
    meck:expect(lager, md, fun() ->
        case erlang:get(blackhole_frame_metadata) of undefined -> []; Metadata -> Metadata end
    end),
    meck:expect(lager, md, fun(Metadata) -> erlang:put(blackhole_frame_metadata, Metadata), ok end),
    meck:expect(kz_nodes, node_hostname, fun() -> <<"frame-fixture.invalid">> end),
    meck:expect(kz_buckets, consume_token, fun(<<"blackhole">>, _) -> true end),
    meck:expect(kz_auth, validate_token, fun(<<"frame-fixture-token">>) ->
        {ok,kz_json:from_list([{<<"account_id">>,<<"frame-fixture-account">>}])}
    end),
    meck:expect(kapps_config, get, fun(<<"blackhole">>, <<"max_frame_size_bytes">>, 65536) ->
        case val(max_bytes) of absent -> 65536; Value -> Value end
    end),
    meck:expect(kapps_config, get_integer,
                fun(<<"blackhole">>, <<"max_connections_per_ip">>) -> 4 end),
    meck:expect(kapps_config, get_integer,
                fun(<<"blackhole">>, <<"max_queued_messages">>, 50) -> 50 end),
    meck:expect(kz_app_config, get_boolean,
                fun(blackhole, <<"keep_client_alive">>, false) -> false end),
    meck:expect(gen_listener, cast,
                fun(blackhole_tracking, {monitor, _, Pid}) when is_pid(Pid) -> ok;
                   (blackhole_tracking, {demonitor, Pid}) when is_pid(Pid) -> ok
                end),
    meck:expect(blackhole_listener, add_bindings, fun(_) -> ok end),
    meck:expect(blackhole_listener, remove_bindings, fun(_) -> ok end),
    meck:expect(blackhole_socket_callback, recv, fun receive_callback/2),
    %% Start only the real in-memory binding server, not the Kazoo application or
    %% broker listener. Give it its normal protected table as the ETS manager does.
    {ok, BindingPid} = kazoo_bindings:start_link(), unlink(BindingPid),
    Table = ets:new(kazoo_bindings:table_id(), kazoo_bindings:table_options()),
    true = ets:give_away(Table, BindingPid, ok),
    true = gen_server:call(BindingPid, is_ready),
    {ok, []} = blackhole_tracking:init([]),
    ok = blackhole_bindings:bind(<<"blackhole.session.open">>, ?MODULE, session_open),
    ok = blackhole_bindings:bind(<<"blackhole.session.close">>, bh_events, close),
    ok = blackhole_bindings:bind(<<"blackhole.session.close">>, ?MODULE, session_close),
    ok = blackhole_bindings:bind(<<"blackhole.command.frame">>, ?MODULE, echo),
    ok = bh_token_auth:init(),
    {ok, Started} = application:ensure_all_started(cowboy),
    Dispatch = cowboy_router:compile([{'_', [{"/", blackhole_socket_handler, []}]}]),
    {ok, _} = cowboy:start_clear(?LISTENER,
        #{num_acceptors => 1, max_connections => 4, socket_opts => [{ip, {127,0,0,1}}, {port, 0}]},
        #{env => #{dispatch => Dispatch}, request_timeout => 3000}),
    put_value(port, ranch:get_port(?LISTENER)),
    {BindingPid, Started}.

cleanup({BindingPid, Started}) ->
    ok = cowboy:stop_listener(?LISTENER),
    lists:foreach(fun application:stop/1, lists:reverse(Started)),
    gen_server:stop(BindingPid),
    ets:delete(blackhole_tracking),
    meck:unload(mocks()),
    ets:delete(?TABLE).

reset(Mode) ->
    ets:insert(?TABLE, [{mode, Mode}, {calls, 0}, {owner, self()}]),
    lists:foreach(fun meck:reset/1, mocks()).

receive_callback(Packet, Context) ->
    ets:update_counter(?TABLE, calls, 1),
    put_value(last_packet, Packet),
    case val(mode) of
        capture -> {ok, Context};
        delegate -> meck:passthrough([Packet, Context]);
        {throw, Reason} -> throw(Reason);
        {error, Reason} -> erlang:error(Reason)
    end.

%% A synthetic authenticated session and event subscription isolate frame and
%% cleanup behavior. No real authentication or external listener is invoked.
session_open(Context) ->
    Id = bh_context:websocket_session_id(Context), Pid = bh_context:websocket_pid(Context),
    put_value({closed_count,Id},0),
    AMQP = <<"fixture.", Id/binary>>, Client = <<"fixture.client">>,
    Listeners = [{fixture_listener, Id}],
    Payload = #{subscribed_key => Client, subscription_key => AMQP, session_pid => Pid, session_id => Id},
    ok = blackhole_bindings:bind(<<"blackhole.event.", AMQP/binary>>, bh_events, event, Payload),
    ok = blackhole_listener:add_bindings(Listeners),
    Ctx = bh_context:setters(Context, [fun bh_context:set_authorized/1,
        {fun bh_context:set_auth_token/2, <<"frame-fixture-token">>},
        {fun bh_context:set_auth_account_id/2, <<"frame-fixture-account">>},
        {fun bh_context:set_bindings/2, [{Client, [AMQP]}]},
        {fun bh_context:add_listeners/2, Listeners}]),
    blackhole_tracking:update_socket(Ctx),
    val(owner) ! {opened, Id, Pid, AMQP, Listeners}, Ctx.

session_close(Context) ->
    Id = bh_context:websocket_session_id(Context),
    ets:update_counter(?TABLE,{closed_count,Id},1),
    ?assertEqual([], bh_context:bindings(Context)),
    ?assertEqual([], bh_context:listeners(Context)),
    ?assertEqual({error, not_found}, blackhole_tracking:get_context_by_session_id(Id)),
    val(owner) ! {closed, Id}, Context.

echo(Context, _Payload) ->
    bh_context:set_resp_data(Context, kz_json:from_list([{<<"accepted">>, true}])).

configuration() ->
    Root = os:getenv("KAZOO_BLACKHOLE_FRAME_ROOT"),
    {ok, SchemaBytes} = file:read_file(filename:join(Root,
        "applications/crossbar/priv/couchdb/schemas/system_config.blackhole.json")),
    Schema = kz_json:unsafe_decode(SchemaBytes),
    Field = kz_json:get_value([<<"properties">>, <<"max_frame_size_bytes">>], Schema),
    ?assertEqual(<<"integer">>, kz_json:get_value(<<"type">>, Field)),
    ?assertEqual(65536, kz_json:get_value(<<"default">>, Field)),
    ?assertEqual(1, kz_json:get_value(<<"minimum">>, Field)),
    ?assertEqual(1048576, kz_json:get_value(<<"maximum">>, Field)),
    {ok, Baseline} = file:read_file(os:getenv("KAZOO_BLACKHOLE_FRAME_SCHEMA_BASELINE")),
    ?assertEqual(undefined, kz_json:get_value([<<"properties">>, <<"max_frame_size_bytes">>], kz_json:unsafe_decode(Baseline))),
    Req = #{peer => {{127,0,0,1}, 9999}, headers => #{}},
    lists:foreach(fun({Raw, Expected}) ->
        put_value(max_bytes, Raw),
        {cowboy_websocket, Req, _Context, Opts} = blackhole_socket_handler:init(Req, []),
        ?assertEqual(#{idle_timeout => 3600000, max_frame_size => Expected}, Opts)
    end, [{absent,65536}, {1,1}, {256,256}, {65536,65536}, {1048576,1048576}]
        ++ [{Invalid,65536} || Invalid <- [undefined,null,false,true,0,-1,1048577,1.0,<<"256">>,[],#{},kz_json:new()]]),
    put_value(max_bytes, absent).

valid_json() ->
    lists:foreach(fun({Bytes, Action, Payload}) ->
        reset(capture), C = bh_context:new(),
        ?assertEqual({ok,C,hibernate}, blackhole_socket_handler:websocket_handle({text,Bytes}, C)),
        ?assertEqual(1, val(calls)), ?assertEqual({Action,Payload}, val(last_packet))
    end, [{<<"{}">>, <<"noop">>, kz_json:new()},
          {<<"{\"action\":\"frame\",\"text\":\"quote:\\\" slash:\\\\ newline:\\n\",\"unicode\":\"\\u03bb\\ud83d\\ude03\"} \r\n\t">>,
           <<"frame">>, kz_json:from_list([{<<"text">>, <<"quote:\" slash:\\ newline:\n">>},
                                          {<<"unicode">>, <<206,187,240,159,152,131>>}])}]),
    %% Envelope compatibility only: capture never dispatches bh_api or HTTP.
    lists:foreach(fun({Action,Data}) ->
        Payload = kz_json:from_list([{<<"request_id">>,<<"compatibility">>},{<<"data">>,Data}]),
        Bytes = kz_json:encode(kz_json:set_value(<<"action">>,Action,Payload)),
        ?assert(byte_size(Bytes) =< 65536), reset(capture), C = bh_context:new(),
        ?assertEqual({ok,C,hibernate},blackhole_socket_handler:websocket_handle({text,Bytes},C)),
        ?assertEqual({Action,Payload},val(last_packet)), ?assertEqual(1,val(calls))
    end, [{<<"subscribe">>,kz_json:from_list([{<<"binding">>,<<"call.CHANNEL_ANSWER.*">>}])},
          {<<"unsubscribe">>,kz_json:from_list([{<<"bindings">>,[<<"call.CHANNEL_ANSWER.*">>]}])},
          {<<"api">>,kz_json:from_list([{<<"endpoint">>,<<"/v2/accounts/fixture/users">>},
              {<<"verb">>,<<"post">>},{<<"body">>,<<"{\"data\":{\"note\":\"quote:\\\" slash:\\\\\"}}">>}])}]).

no_secret_logs() ->
    ?assertEqual(nomatch, binary:match(term_to_binary(meck:history(lager)), ?SECRET)).

malformed_json() ->
    lists:foreach(fun(Bytes) ->
        reset(capture), C = bh_context:new(),
        ?assertEqual({reply,{close,1007,<<"invalid JSON">>},C},
                     blackhole_socket_handler:websocket_handle({text,Bytes}, C)),
        ?assertEqual(0, val(calls)), no_secret_logs()
    end, [<<>>, <<" \r\n\t">>, <<"{\"secret\":\"",?SECRET/binary,"\",">>, <<"{}{}">>, <<"{} trailing">>,
          <<"{\"action\":\"frame\",\"action\":\"again\"}">>, <<"{\"x\":\"\\q\"}">>]).

nonobjects() ->
    lists:foreach(fun(Bytes) ->
        reset(capture), C = bh_context:new(),
        ?assertEqual({reply,{close,1003,<<"JSON object required">>},C},
                     blackhole_socket_handler:websocket_handle({text,Bytes}, C)),
        ?assertEqual(0, val(calls)), no_secret_logs()
    end, [<<"[]">>, <<"[{}]">>, <<"null">>, <<"true">>, <<"false">>, <<"42">>,
          <<"\"",?SECRET/binary,"\"">>]).

callback_errors() ->
    C = bh_context:new(), Reason = {invalid_json, fixture_callback, ?SECRET},
    reset({throw,Reason}),
    ?assertThrow(Reason, blackhole_socket_handler:websocket_handle({text,<<"{}">>}, C)),
    ?assertEqual(1, val(calls)),
    reset({error,fixture_callback_failed}),
    ?assertError(fixture_callback_failed, blackhole_socket_handler:websocket_handle({text,<<"{}">>}, C)),
    ?assertEqual(1, val(calls)), no_secret_logs().

controls() ->
    reset(capture), C = bh_context:new(),
    lists:foreach(fun(Frame) -> ?assertEqual({ok,C,hibernate}, blackhole_socket_handler:websocket_handle(Frame,C)) end,
                  [ping,pong,{ping,?SECRET},{pong,?SECRET}]),
    lists:foreach(fun(Frame) ->
        ?assertEqual({reply,{close,1003,<<"unsupported frame">>},C}, blackhole_socket_handler:websocket_handle(Frame,C))
    end, [{binary,?SECRET},{text,"{}"},unexpected_frame]),
    ?assertEqual(0,val(calls)),
    ?assert(meck:history(lager) =/= []), no_secret_logs().

%% Passive, masked RFC6455 client. Only the private listener port is used.
connect() ->
    reset(delegate),
    {ok,S} = gen_tcp:connect({127,0,0,1},val(port),[binary,{active,false},{packet,http_bin}],1500),
    ok = gen_tcp:send(S, <<"GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n">>),
    {ok,{http_response,_,101,_}} = gen_tcp:recv(S,0,1500),
    Headers = headers(S,[]),
    ?assert(lists:any(fun({K,V}) -> string:lowercase(binary_to_list(kz_term:to_binary(K))) =:= "sec-websocket-accept"
                                      andalso V =:= <<"s3pPLMBiTxaQ9kYGzzhZRbK+xOo=">> end, Headers)),
    ok = inet:setopts(S,[{packet,raw}]),
    receive {opened,Id,Pid,AMQP,Listeners} ->
        ?assertEqual(Pid,bh_context:websocket_pid(blackhole_tracking:get_context_by_session_id(Id))),
        ?assert(ets:lookup(kazoo_bindings,<<"blackhole.event.",AMQP/binary>>) =/= []),
        {S,Id,Pid,erlang:monitor(process,Pid),AMQP,Listeners}
    after 1500 -> gen_tcp:close(S), erlang:error(open_timeout)
    end.

headers(S,Acc) ->
    case gen_tcp:recv(S,0,1500) of
        {ok,http_eoh} -> Acc;
        {ok,{http_header,_,Key,_,Value}} -> headers(S,[{Key,Value}|Acc]);
        Other -> erlang:error({bad_upgrade_header,Other})
    end.

client_frame(Fin,Opcode,Payload) ->
    Size = byte_size(Payload),
    %% A zero masking key is legal and makes deterministic fixture bytes simple.
    Length = if Size < 126 -> <<1:1,Size:7>>;
                Size =< 65535 -> <<1:1,126:7,Size:16>>;
                true -> <<1:1,127:7,Size:64>> end,
    <<Fin:1,0:3,Opcode:4,Length/binary,0:32,Payload/binary>>.

recv_frame(S) ->
    {ok,<<1:1,0:3,Opcode:4,0:1,Len:7>>} = gen_tcp:recv(S,2,1500),
    Size = case Len of
        126 -> {ok,<<N:16>>} = gen_tcp:recv(S,2,1500), N;
        127 -> {ok,<<N:64>>} = gen_tcp:recv(S,8,1500), N;
        N -> N
    end,
    ?assert(Size =< 131072),
    Payload = case Size of 0 -> <<>>; _ -> {ok,Bin} = gen_tcp:recv(S,Size,1500), Bin end,
    {Opcode,Payload}.

cleaned({_S,Id,Pid,Ref,AMQP,Listeners}) ->
    receive {closed,Id} -> ok after 1500 -> erlang:error(cleanup_timeout) end,
    receive {'DOWN',Ref,process,Pid,Reason} -> ?assertEqual(normal,Reason)
    after 1500 -> erlang:error(connection_down_timeout) end,
    ?assertEqual({error,not_found},blackhole_tracking:get_context_by_session_id(Id)),
    ?assertEqual([],ets:lookup(kazoo_bindings,<<"blackhole.event.",AMQP/binary>>)),
    ?assertEqual(1,val({closed_count,Id})),
    ?assertEqual(1,length([ok || {_,{blackhole_listener,remove_bindings,[Actual]},_} <- meck:history(blackhole_listener), Actual =:= Listeners])),
    ?assertEqual(1,length([ok || {_,{gen_listener,cast,[blackhole_tracking,{demonitor,Actual}]},_} <- meck:history(gen_listener), Actual =:= Pid])),
    ?assertEqual(1,length([ok || {_,{blackhole_socket_callback,close,[Ctx]},_} <- meck:history(blackhole_socket_callback),
                               bh_context:websocket_session_id(Ctx) =:= Id])),
    receive {closed,Id} -> erlang:error(duplicate_cleanup_notice)
    after 0 -> ok
    end.

expect_close(Connection={S,_,_,_,_,_},Code,Reason) ->
    {8,<<Code:16,Actual/binary>>} = recv_frame(S),
    case Reason of any -> ok; _ -> ?assertEqual(Reason,Actual) end,
    ?assertEqual({error,closed},gen_tcp:recv(S,0,1500)), cleaned(Connection).

with_connection(Fun) ->
    Connection = connect(),
    try Fun(Connection)
    after gen_tcp:close(element(1,Connection))
    end.

accepted(S) ->
    {1,Bytes} = recv_frame(S), J = kz_json:unsafe_decode(Bytes),
    ?assertEqual(<<"success">>,kz_json:get_value(<<"status">>,J)),
    ?assertEqual(true,kz_json:get_value([<<"data">>,<<"accepted">>],J)).

normal_close(Connection={S,_,_,_,_,_}) ->
    ok = gen_tcp:send(S,client_frame(1,8,<<1000:16>>)), expect_close(Connection,1000,<<>>).

padded(Size) ->
    Prefix = <<"{\"action\":\"frame\",\"pad\":\"">>, Suffix = <<"\"}">>,
    Padding = binary:copy(<<"x">>,Size-byte_size(Prefix)-byte_size(Suffix)),
    <<Prefix/binary,Padding/binary,Suffix/binary>>.

wire_malformed() ->
    put_value(max_bytes,256),
    with_connection(fun(C={S,_,_,_,_,_}) ->
        ok = gen_tcp:send(S,client_frame(1,1,<<"{\"secret\":\"",?SECRET/binary,"\",">>)),
        expect_close(C,1007,<<"invalid JSON">>), ?assertEqual(0,val(calls)), no_secret_logs()
    end).

wire_unsupported() ->
    put_value(max_bytes,256),
    lists:foreach(fun({Opcode,Bytes,Reason}) ->
        with_connection(fun(C={S,_,_,_,_,_}) ->
            ok = gen_tcp:send(S,client_frame(1,Opcode,Bytes)),
            expect_close(C,1003,Reason), ?assertEqual(0,val(calls)), no_secret_logs()
        end)
    end,[{1,<<"[]">>,<<"JSON object required">>},{2,?SECRET,<<"unsupported frame">>}]).

wire_boundary() ->
    put_value(max_bytes,256),
    with_connection(fun(C={S,_,_,_,_,_}) ->
        ok = gen_tcp:send(S,client_frame(1,1,padded(256))), accepted(S),
        ?assertEqual(1,val(calls)), normal_close(C)
    end),
    with_connection(fun(C={S,_,_,_,_,_}) ->
        %% Announced oversized length is rejected before any payload is needed.
        ok = gen_tcp:send(S,<<1:1,0:3,1:4,1:1,126:7,257:16,0:32>>),
        expect_close(C,1009,any), ?assertEqual(0,val(calls))
    end).

wire_fragments() ->
    put_value(max_bytes,256),
    lists:foreach(fun(Size) ->
        with_connection(fun(C={S,_,_,_,_,_}) ->
            <<First:128/binary,Last/binary>> = padded(Size),
            ok = gen_tcp:send(S,client_frame(0,1,First)),
            ok = gen_tcp:send(S,client_frame(1,0,Last)),
            case Size of
                256 -> accepted(S), ?assertEqual(1,val(calls)), normal_close(C);
                257 -> expect_close(C,1009,any), ?assertEqual(0,val(calls))
            end
        end)
    end,[256,257]),
    with_connection(fun(C={S,_,_,_,_,_}) ->
        %% The second fragment already exceeds the aggregate before FIN exists.
        <<First:128/binary,Last/binary>> = padded(257),
        ok = gen_tcp:send(S,client_frame(0,1,First)),
        ok = gen_tcp:send(S,client_frame(0,0,Last)),
        expect_close(C,1009,any), ?assertEqual(0,val(calls))
    end).

wire_default_bound() ->
    put_value(max_bytes,absent),
    with_connection(fun(C={S,_,_,_,_,_}) ->
        ok = gen_tcp:send(S,client_frame(1,1,padded(65536))), accepted(S),
        ?assertEqual(1,val(calls)), normal_close(C)
    end),
    with_connection(fun(C={S,_,_,_,_,_}) ->
        ok = gen_tcp:send(S,<<1:1,0:3,1:4,1:1,127:7,65537:64,0:32>>),
        expect_close(C,1009,any), ?assertEqual(0,val(calls))
    end).

wire_controls() ->
    put_value(max_bytes,256),
    with_connection(fun(C={S,_,_,_,_,_}) ->
        ok = gen_tcp:send(S,client_frame(1,9,?SECRET)),
        ?assertEqual({10,?SECRET},recv_frame(S)),
        ok = gen_tcp:send(S,client_frame(1,10,?SECRET)),
        ok = gen_tcp:send(S,client_frame(1,1,padded(64))), accepted(S),
        ?assertEqual(1,val(calls)), no_secret_logs(), normal_close(C)
    end).

wire_close_reason() ->
    put_value(max_bytes,256),
    with_connection(fun(C={S,_,_,_,_,_}) ->
        ok = gen_tcp:send(S,client_frame(1,8,<<1000:16,?SECRET/binary>>)),
        expect_close(C,1000,<<>>), ?assertEqual(0,val(calls)),
        ?assert(meck:history(lager) =/= []), no_secret_logs()
    end).
