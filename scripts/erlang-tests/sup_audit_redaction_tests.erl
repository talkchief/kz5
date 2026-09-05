%%% SPDX-License-Identifier: MPL-2.0
-module(sup_audit_redaction_tests).
-include_lib("eunit/include/eunit.hrl").
-export([args/7, echo/1, zero/0, raise/2]).

args(A, B, C, D, E, F, G) -> [A, B, C, D, E, F, G].
echo(Value) -> Value.
zero() -> 'ok'.
raise('error', Reason) -> erlang:error(Reason);
raise('throw', Reason) -> throw(Reason);
raise('exit', Reason) -> exit(Reason).

erlang_terms_are_not_formatted_as_strings_test() ->
    Secret = <<"SYNTHETIC_ARGUMENT_SECRET">>,
    As = [#{password => Secret}, {tuple, Secret}, [1, {nested, Secret}],
          123, self(), make_ref(), fun() -> Secret end],
    {Outcome, Notices} = capture(fun() -> sup:in_kazoo('synthetic_sup', ?MODULE, args, As) end),
    ?assertEqual({returned, As}, Outcome),
    metadata_only(Notices, args, 7, true),
    ?assertEqual(nomatch, binary:match(render(Notices), Secret)),
    ?assertEqual(true, get('is_sup_call')),
    ?assertEqual('synthetic_sup', get('sup_test_callid')).

large_secret_result_does_not_enter_remote_audit_test() ->
    Secret = binary:copy(<<"SYNTHETIC_RESULT_SECRET">>, 50000),
    Value = #{result => Secret, token => <<"SYNTHETIC_AUTH_TOKEN">>},
    {Outcome, Notices} = capture(fun() -> sup:in_kazoo('synthetic_sup', ?MODULE, echo, [Value]) end),
    ?assertEqual({returned, Value}, Outcome),
    metadata_only(Notices, echo, 1, true),
    ?assert(byte_size(render(Notices)) < 256),
    ?assertEqual(nomatch, binary:match(render(Notices), <<"SYNTHETIC_">>)).

zero_arity_and_return_sentinels_test() ->
    {Outcome, Notices} = capture(fun() -> sup:in_kazoo('synthetic_sup', ?MODULE, zero, []) end),
    ?assertEqual({returned, ok}, Outcome),
    metadata_only(Notices, zero, 0, true),
    lists:foreach(fun(Value) ->
        {Returned, Audit} = capture(fun() -> sup:in_kazoo('synthetic_sup', ?MODULE, echo, [Value]) end),
        ?assertEqual({returned, Value}, Returned),
        metadata_only(Audit, echo, 1, true)
    end, [no_return, {no_return, 4}, {error, denied}, undefined, false]).

exception_classes_and_reasons_preserved_test_() ->
    [{atom_to_list(Class), fun() ->
        Reason = {synthetic_failure, <<"SYNTHETIC_EXCEPTION_SECRET">>},
        {Outcome, Notices} = capture(fun() -> sup:in_kazoo('synthetic_sup', ?MODULE, raise, [Class, Reason]) end),
        ?assertEqual({raised, Class, Reason}, Outcome),
        metadata_only(Notices, raise, 2, false),
        ?assertEqual(nomatch, binary:match(render(Notices), <<"SYNTHETIC_EXCEPTION_SECRET">>))
    end} || Class <- [error, throw, exit]].

metadata_only(Notices, Function, Arity, Completed) ->
    Started = {"sup RPC ~p:~p/~B started", [?MODULE, Function, Arity]},
    Expected = case Completed of
                   true -> [Started, {"sup RPC ~p:~p/~B completed", [?MODULE, Function, Arity]}];
                   false -> [Started]
               end,
    ?assertEqual(Expected, Notices).

render(Notices) ->
    iolist_to_binary([io_lib:format(Format, Values) || {Format, Values} <- Notices]).

capture(Fun) ->
    meck:new(lager, [non_strict, no_link]),
    meck:new(kz_log, [non_strict, no_link]),
    try
        meck:expect(kz_log, put_callid, fun(Name) -> put('sup_test_callid', Name), ok end),
        %% Exercise the real formatter: a metadata type mismatch is a test failure.
        meck:expect(lager, notice, fun(Format, Values) -> _ = iolist_to_binary(io_lib:format(Format, Values)), ok end),
        Outcome = try {returned, Fun()} catch Class:Reason -> {raised, Class, Reason} end,
        Notices = [{Format, Values} || {_, {lager, notice, [Format, Values]}, ok} <- meck:history(lager)],
        {Outcome, Notices}
    after meck:unload([lager, kz_log])
    end.
