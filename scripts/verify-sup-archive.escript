#!/usr/bin/env escript
%%! +S 1:1 +SDcpu 1 +SDio 1 +A 1
%% Verify packaged dependencies without starting distribution or reading cookies.
main([File]) ->
    try
        {ok, Sections} = escript:extract(File, []),
        {archive, Archive} = lists:keyfind(archive, 1, Sections),
        {ok, Entries} = zip:extract(Archive, [memory]),
        Required = [sup, props, kz_binary, kz_term, kz_network_utils,
                    kazoo_config_init, kz_config, getopt, zucchini, lager],
        lists:foreach(fun(Module) ->
            Name = atom_to_list(Module) ++ ".beam",
            [{_, Bytes}] = [{Path, Binary} || {Path, Binary} <- Entries,
                                            filename:basename(Path) =:= Name],
            {ok, {Module, _}} = beam_lib:chunks(Bytes, [exports])
        end, Required),
        [{_, Props}] = [{Path, Binary} || {Path, Binary} <- Entries,
                                          filename:basename(Path) =:= "props.beam"],
        {module, props} = code:load_binary(props, "verified-sup-archive", Props),
        packaged = props:get_value(probe, [{probe, packaged}]),
        io:format("PASS SUP archive embeds required modules and executes packaged props; no distribution~n")
    catch _:_ ->
        io:format(standard_error, "SUP archive dependency verification failed; rebuild SUP before bootstrap~n", []),
        halt(1)
    end;
main(_) -> halt(64).
