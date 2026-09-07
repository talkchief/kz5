%%% Execute only the actual template's pure bounded-reader closures offline.
-module(acdc_runtime_probe_reader_tests).
-export([run/1]).

-spec run(string()) -> no_return().
run(Directory) ->
    {ok, Template} = file:read_file("scripts/probe-acdc-prerecorded-runtime.erl.template"),
    {ok, Tokens, _} = erl_scan:string(binary_to_list(Template)),
    {ok, [{'try', _, Body, _, _, _}]} = erl_parse:parse_exprs(Tokens),
    Names = ['Hex', 'StatIdentity', 'BoundedRead'],
    Selected = [E || E = {match, _, {var, _, Name}, _} <- Body, lists:member(Name, Names)],
    Names = [Name || {match, _, {var, _, Name}, _} <- Selected],
    {value, _, Bindings} = erl_eval:exprs(Selected, erl_eval:new_bindings()),
    {value, Read} = erl_eval:binding('BoundedRead', Bindings),
    {value, Hex} = erl_eval:binding('Hex', Bindings),
    Hash = fun(B) -> Hex(crypto:hash(sha256, B)) end,
    Failure = fun(F) ->
        Result = try F(), accepted catch _:_ -> refused end,
        refused = Result
    end,
    ok = file:change_mode(Directory, 8#750),
    File = filename:join(Directory, "reader-fixture.json"), Data = <<"synthetic offline fixture">>,
    ok = file:write_file(File, Data), ok = file:change_mode(File, 8#640),
    Data = Read(File, byte_size(Data), sidecar, Hash(Data)),
    Data = Read(File, byte_size(Data), beam, Hash(Data)),
    Failure(fun() -> Read(File, byte_size(Data) - 1, sidecar, Hash(Data)) end),
    Failure(fun() -> Read(File, byte_size(Data), sidecar, Hash(<<"wrong">>)) end),
    Empty = filename:join(Directory, "empty"), ok = file:write_file(Empty, <<>>),
    ok = file:change_mode(Empty, 8#640), Failure(fun() -> Read(Empty, 100, sidecar, Hash(<<>>)) end),
    Failure(fun() -> Read(Directory, 100, beam, Hash(Data)) end),
    Link = filename:join(Directory, "symlink"), ok = file:make_symlink(File, Link),
    Failure(fun() -> Read(Link, 100, sidecar, Hash(Data)) end),
    Hard = filename:join(Directory, "hardlink"), ok = file:make_link(File, Hard),
    Failure(fun() -> Read(File, 100, sidecar, Hash(Data)) end), ok = file:delete(Hard),
    ok = file:change_mode(File, 8#666), Failure(fun() -> Read(File, 100, beam, Hash(Data)) end),
    ok = file:change_mode(File, 8#600), Failure(fun() -> Read(File, 100, sidecar, Hash(Data)) end),
    Data = Read(File, 100, beam, Hash(Data)),
    ok = file:change_mode(File, 8#640), ok = file:change_mode(Directory, 8#777),
    Failure(fun() -> Read(File, 100, beam, Hash(Data)) end), ok = file:change_mode(Directory, 8#750),
    io:format("PASS actual template bounded-reader success and 9 refusal cases; no native runtime/SUP execution~n"),
    halt(0).
