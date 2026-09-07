%%% Execute the actual template's bounded-reader and BEAM-check closures offline.
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

    %% Evaluate the actual CheckBeams expression, not a duplicated expected
    %% beam_lib return pattern. The current module is a real compiled/loaded
    %% BEAM; no production module, RPC, datastore or media worker is involved.
    [CheckExpression] = [E || E = {match, _, {var, _, 'CheckBeams'}, _} <- Body],
    BeamFile = filename:join(Directory, atom_to_list(?MODULE) ++ ".beam"),
    BeamFile = code:which(?MODULE),
    {ok, BeamBytes} = file:read_file(BeamFile),
    Beam = #{<<"module">> => atom_to_binary(?MODULE, utf8),
             <<"path">> => list_to_binary(BeamFile), <<"sha256">> => Hash(BeamBytes)},
    Check = fun(Entry) ->
        WithGet = erl_eval:add_binding('Get', fun maps:get/2, Bindings),
        WithGuard = erl_eval:add_binding('Guard', fun() -> ok end, WithGet),
        WithBeams = erl_eval:add_binding('Beams', [Entry], WithGuard),
        {value, CheckFun, _} = erl_eval:expr(CheckExpression, WithBeams),
        CheckFun()
    end,
    ok = Check(Beam),
    Failure(fun() -> Check(Beam#{<<"path">> => list_to_binary(File)}) end),
    Failure(fun() -> Check(Beam#{<<"sha256">> => Hash(<<"wrong beam hash">>)}) end),
    %% Same module name and exact on-disk hash are insufficient: a different
    %% valid compiled body must fail against the still-loaded module's MD5.
    Forms = [{attribute, 1, module, ?MODULE},
             {attribute, 2, export, [{fixture_identity, 0}]},
             {function, 3, fixture_identity, 0,
                 [{clause, 3, [], [], [{atom, 3, different_unloaded_body}]}]}],
    {ok, ?MODULE, DifferentBeam, []} = compile:forms(Forms, [binary, return_errors, return_warnings]),
    try
        ok = file:write_file(BeamFile, DifferentBeam),
        Failure(fun() -> Check(Beam#{<<"sha256">> => Hash(DifferentBeam)}) end)
    after ok = file:write_file(BeamFile, BeamBytes) end,
    ok = Check(Beam),
    io:format("PASS actual template bounded-reader success and 9 refusal cases; BEAM closure success and 3 refusals (path/hash/loaded MD5); no native runtime/SUP execution~n"),
    halt(0).
