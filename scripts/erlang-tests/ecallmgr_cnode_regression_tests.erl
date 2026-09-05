%%% SPDX-License-Identifier: MPL-2.0
-module(ecallmgr_cnode_regression_tests).
-include_lib("eunit/include/eunit.hrl").

reference_reply_tag_test() ->
    Owner = self(),
    Server = spawn(fun() ->
                           receive
                               {'$gen_call', {From, Ref}, test_request} ->
                                   Owner ! {wire, is_pid(From), is_reference(Ref)},
                                   From ! {Ref, {ok, test_reply}}
                           end
                   end),
    register(kazoo_cnode_test_server, Server),
    try
        ?assertEqual({ok, test_reply}, mod_kazoo:call({kazoo_cnode_test_server, node()}, test_request, 1000)),
        receive {wire, true, true} -> ok after 1000 -> error(non_legacy_reply_tag) end
    after
        catch unregister(kazoo_cnode_test_server),
        exit(Server, kill)
    end.

bounded_timeout_test() ->
    Node = node(),
    Server = spawn(fun() -> receive stop -> ok end end),
    register(kazoo_cnode_test_server, Server),
    try
        ?assertExit({timeout, {gen_server, call, [{kazoo_cnode_test_server, Node}, no_reply, 20]}},
                    mod_kazoo:call({kazoo_cnode_test_server, node()}, no_reply, 20))
    after
        unregister(kazoo_cnode_test_server),
        exit(Server, kill)
    end.

version_based_ping_test_() ->
    [?_test(begin
                Server = spawn(fun() ->
                                       receive
                                           {'$gen_call', {From, Ref}, version} -> From ! {Ref, Reply}
                                       end
                               end),
                register(mod_kazoo, Server),
                try ?assertEqual(Expected, mod_kazoo:ping(node()))
                after catch unregister(mod_kazoo), exit(Server, kill)
                end
            end)
     || {Reply, Expected} <- [{{ok, <<"mod_kazoo">>}, pong}, {{error, unavailable}, pang}]].
