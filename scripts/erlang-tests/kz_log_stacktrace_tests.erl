%%% SPDX-License-Identifier: MPL-2.0
-module(kz_log_stacktrace_tests).
-include_lib("eunit/include/eunit.hrl").

argument_values_never_reach_logger_test() ->
    Secret = <<"FIXTURE_ONLY_SIP_AUTH_SECRET">>,
    Endpoint = #{sip => #{password => Secret}},
    Call = {call, #{auth_token => Secret, custom_channel_vars => #{password => Secret}}},
    Trace = [{kz_endpoint_v5, maybe_owner_called_self, [Endpoint, #{}, <<"offnet-termination">>, Call], [{line, 1067}]}],
    History = capture(Trace),
    Logged = iolist_to_binary(io_lib:format("~p", [History])),
    ?assertEqual(nomatch, binary:match(Logged, Secret)),
    ?assertEqual(nomatch, binary:match(Logged, <<"offnet-termination">>)),
    ?assert(lists:any(fun({_, {lager, error, [_, [kz_endpoint_v5, maybe_owner_called_self, 4, 1067]]}, ok}) -> true;
                        (_) -> false end, History)).

arity_and_empty_arguments_preserve_diagnostics_test() ->
    History = capture([{fixture, first, 2, [{line, 17}]}, {fixture, second, [], []}]),
    ?assert(lists:any(fun({_, {lager, error, [_, [fixture, first, 2, 17]]}, ok}) -> true;
                        (_) -> false end, History)),
    ?assert(lists:any(fun({_, {lager, error, [_, [fixture, second, 0, 0]]}, ok}) -> true;
                        (_) -> false end, History)).

real_exception_arguments_never_reach_logger_test() ->
    Secret = <<"FIXTURE_ONLY_BADARG_SECRET">>,
    Trace = try failing_hd(Secret) catch error:badarg:ST -> ST end,
    Logged = iolist_to_binary(io_lib:format("~p", [capture(Trace)])),
    ?assertEqual(nomatch, binary:match(Logged, Secret)),
    ?assertNotEqual(nomatch, binary:match(Logged, <<"erlang,hd,1">>)).

failing_hd(Value) -> erlang:hd(Value).

capture(Trace) ->
    meck:new(lager, [non_strict, no_link]),
    try
        meck:expect(lager, error, fun(_, _) -> ok end),
        ?assertEqual(ok, kz_log:log_stacktrace(Trace, "fixture failure", [])),
        meck:history(lager)
    after meck:unload(lager)
    end.
