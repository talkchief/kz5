%% ACL maintenance commands run from a node without ecallmgr (SUP's default
%% applications node) must execute on the ecallmgr node, never half-apply locally.
-module(ecallmgr_acl_forwarding_tests).
-include_lib("eunit/include/eunit.hrl").
-include_lib("kazoo_stdlib/include/kz_types.hrl").

-define(MODS, [kapps_config, ecallmgr_fs_acls, ecallmgr_fs_nodes, freeswitch, kz_network_utils, ecallmgr_util, kz_nodes]).

mocks(Node) -> mocks(fun(M, F, A) -> erpc:call(Node, M, F, A) end, ok).

%% Call is how the node is reached: distribution, or a peer's standard I/O when
%% the test must not create the distribution connection itself.
mocks(Call, ok) ->
    %% Address parsing stays real; only name resolution is controlled.
    [ok = Call(meck, new, [M, mock_options(M)]) || M <- ?MODS],
    E = fun(M, F, Fun) -> ok = Call(meck, expect, [M, F, Fun]) end,
    E(kz_nodes, nodes, fun() -> [] end),
    E(ecallmgr_fs_acls, get, fun(_) -> kz_json:new() end),
    E(kapps_config, set_default, fun(_, _, _) -> {ok, kz_json:new()} end),
    E(kapps_config, set_node, fun(_, _, _, _) -> {ok, kz_json:new()} end),
    E(kapps_config, set, fun(_, _, _) -> {ok, kz_json:new()} end),
    E(kapps_config, flush, fun(_, _) -> ok end),
    E(kz_network_utils, resolve, fun(IP, _) -> [IP] end),
    E(ecallmgr_util, get_resolve_options, fun() -> [] end),
    E(ecallmgr_fs_nodes, connected, fun() -> [] end),
    ok.

mock_options(kz_network_utils) -> [passthrough, no_link];
mock_options(_) -> [non_strict, no_link].

unmock(Node) -> catch erpc:call(Node, meck, unload, [?MODS]), ok.
writes(Node) ->
    lists:sum([erpc:call(Node, meck, num_calls, [kapps_config, F, '_']) || F <- [set_default, set_node, set]]).

%% A minimal I/O server: remote io:format follows the caller's group leader, so
%% this also proves forwarded output returns to the operator.
capture(Fun) ->
    IO = spawn(fun() -> io_server(<<>>) end),
    Old = group_leader(), group_leader(IO, self()),
    try Fun() after group_leader(Old, self()) end,
    IO ! {take, self()},
    receive {taken, Bin} -> Bin after 5000 -> error(no_captured_output) end.

io_server(Acc) ->
    receive
        {io_request, From, ReplyAs, Request} ->
            From ! {io_reply, ReplyAs, ok},
            io_server(<<Acc/binary, (io_chars(Request))/binary>>);
        {take, From} -> From ! {taken, Acc}
    end.

io_chars({put_chars, _Enc, Chars}) -> unicode:characters_to_binary(Chars);
io_chars({put_chars, _Enc, M, F, A}) -> unicode:characters_to_binary(apply(M, F, A));
io_chars({put_chars, Chars}) -> unicode:characters_to_binary(Chars);
io_chars({requests, Requests}) -> << <<(io_chars(R))/binary>> || R <- Requests >>;
io_chars(_) -> <<>>.

%% The reproduced defect: no local ecallmgr and nothing reachable. It used to
%% store a node-scoped ACL under this node and then crash with noproc.
without_any_ecallmgr_nothing_is_written_test() ->
    undefined = whereis(ecallmgr_fs_nodes), ok = mocks(node()),
    try
        Out = capture(fun() ->
            no_return = ecallmgr_maintenance:allow_carrier(<<"bill">>, <<"95.217.1.19/32">>),
            no_return = ecallmgr_maintenance:allow_carrier(<<"bill">>, <<"95.217.1.19/32">>, true),
            no_return = ecallmgr_maintenance:deny_carrier(<<"bill">>, <<"95.217.1.19/32">>),
            no_return = ecallmgr_maintenance:allow_sbc(<<"sbc">>, <<"192.0.2.1/32">>),
            no_return = ecallmgr_maintenance:remove_acl(<<"bill">>),
            no_return = ecallmgr_maintenance:carrier_acls(),
            no_return = ecallmgr_maintenance:reload_acls()
        end),
        ?assertEqual(0, writes(node())),
        ?assertEqual(0, meck:num_calls(ecallmgr_fs_acls, get, '_')),
        ?assertNotEqual(nomatch, binary:match(Out, <<"nothing was changed">>)),
        ?assertNotEqual(nomatch, binary:match(Out, <<"sup -n ecallmgr ecallmgr_maintenance allow_carrier">>))
    after unmock(node()) end.

on_an_ecallmgr_node_commands_run_locally_test() ->
    Pid = spawn(fun() -> receive stop -> ok end end), true = register(ecallmgr_fs_nodes, Pid),
    ok = mocks(node()),
    try
        Out = capture(fun() -> ecallmgr_maintenance:allow_carrier(<<"bill">>, <<"95.217.1.19/32">>, true) end),
        ?assertEqual(1, meck:num_calls(kapps_config, set_default, '_')),
        ?assertEqual(nomatch, binary:match(Out, <<"does not run ecallmgr">>))
    after unmock(node()), Pid ! stop, catch unregister(ecallmgr_fs_nodes) end.

%% Two real distributed nodes: this one plays kazoo_apps, the peer plays ecallmgr
%% on "another host". They are NOT connected beforehand, as on separate servers:
%% the node is found through the AMQP node registry and connected on demand.
forwarded_to_the_real_ecallmgr_node_test_() -> {timeout, 120, fun forwarded/0}.
forwarded() ->
    undefined = whereis(ecallmgr_fs_nodes),
    {ok, Peer, Node} = peer:start(#{name => peer:random_name("ecallmgr"), host => "127.0.0.1", longnames => true
                                   ,connection => standard_io
                                   ,args => ["-pa", filename:dirname(code:which(?MODULE))
                                           ,"-setcookie", atom_to_list(erlang:get_cookie())]
                                   ,wait_boot => 60000}),
    Remote = fun(M, F, A) -> peer:call(Peer, M, F, A) end,
    try
        Keeper = Remote(erlang, spawn, [fun() -> true = register(ecallmgr_fs_nodes, self()), receive stop -> ok end end]),
        ok = mocks(node()), ok = mocks(Remote, ok),
        try
            %% An advertised node that does not run ecallmgr, and a dead one, are skipped.
            ok = meck:expect(kz_nodes, nodes, fun() ->
                [#kz_node{node=Node, kapps=[{<<"ecallmgr">>, running}]}
                ,#kz_node{node='ecallmgr@192.0.2.1', kapps=[{<<"ecallmgr">>, running}]}
                ,#kz_node{node='kazoo_apps@192.0.2.2', kapps=[{<<"crossbar">>, running}]}
                ] end),
            ?assertNot(lists:member(Node, nodes())),
            Out = capture(fun() ->
                no_return = ecallmgr_maintenance:allow_carrier(<<"bill">>, <<"95.217.1.19/32">>),
                no_return = ecallmgr_maintenance:allow_carrier(<<"bill2">>, <<"88.198.242.175/32">>, true),
                no_return = ecallmgr_maintenance:remove_acl(<<"bill">>, true)
            end),
            ?assert(lists:member(Node, nodes())),
            %% Nothing stored from the applications node; everything on ecallmgr.
            ?assertEqual(0, writes(node())),
            ?assertEqual(1, Remote(meck, num_calls, [kapps_config, set_node, '_'])),
            %% The mocked list is empty, so the forwarded removal has nothing to write.
            ?assertEqual(1, Remote(meck, num_calls, [kapps_config, set_default, '_'])),
            ?assert(Remote(meck, called, [kapps_config, set_node, [<<"ecallmgr">>, <<"acls">>, '_', Node]])),
            %% The remote command's own output reaches the operator's terminal.
            ?assertNotEqual(nomatch, binary:match(Out, <<"running allow_carrier on ", (atom_to_binary(Node))/binary>>)),
            ?assertNotEqual(nomatch, binary:match(Out, <<"running remove_acl on ", (atom_to_binary(Node))/binary>>)),
            ?assertNotEqual(nomatch, binary:match(Out, <<"updating trusted ACLs bill(95.217.1.19/32) to allow traffic">>)),
            ?assertEqual(nomatch, binary:match(Out, <<"192.0.2.">>))
        after unmock(node()), catch Remote(meck, unload, [?MODS]), Keeper ! stop end
    after peer:stop(Peer) end.
