#!/usr/bin/env escript
%%! +A0
%% -*- coding: utf-8 -*-

-mode('compile').

-export([main/1]).

%% API

main([KazooRoot, AppL]) ->
    App = list_to_atom(AppL),

    AllDepApps = calc(KazooRoot, App),
    [io:format("~s ", [A]) || A <- AllDepApps].

calc(KazooRoot, App) ->
    handle_application_loaded(App, application:load(App)),
    calc(KazooRoot, App, get_dep_apps(KazooRoot, App)).

handle_application_loaded(_App, 'ok') -> 'ok';
handle_application_loaded(App, {'error', {'already_loaded', App}}) -> 'ok';
handle_application_loaded(_App, {'error', _E}) -> 'ok'.
%% stderr("failed to load ~s: ~p~n", [_App, E]).

calc(_KazooRoot, _App, {'error', 'not_found'}=E) ->
    stderr("dep apps not found for ~p~n", [_App]),
    E;
calc(KazooRoot, App, DepApps) ->
    calc(KazooRoot, App, DepApps, []).

calc(_KazooRoot, _App, [], AllDepApps) ->
    lists:usort(AllDepApps);
calc(KazooRoot, App, [DepApp | DepApps], AllDepApps) ->
    WithDepsOfDep = calc_deps_of_dep(KazooRoot, App, DepApp, AllDepApps),
    calc(KazooRoot, App, DepApps, WithDepsOfDep).

calc_deps_of_dep(KazooRoot, App, DepApp, AllDepApps) ->
    case lists:member(DepApp, AllDepApps) of
        'true' -> AllDepApps;
        'false' -> calc_deps_of_dep(KazooRoot, App, DepApp, AllDepApps, is_kazoo_app(DepApp))
    end.

calc_deps_of_dep(_KazooRoot, _App, _DepApp, AllDepApps, 'false') -> AllDepApps;
calc_deps_of_dep(KazooRoot, App, DepApp, AllDepApps, 'true') ->
    case calc(KazooRoot, DepApp) of
        {'error', 'not_found'} ->
            stderr("failed to find dep app ~p of parent app ~p: not found~n"
                  ,[DepApp, App]
                  ),
            {'error', 'not_found'};
        [] -> [App | AllDepApps];
        DepApps ->
            lists:usort([App | DepApps] ++ AllDepApps)
    end.

is_kazoo_app({'error', 'bad_name'}) -> 'false';
is_kazoo_app(App) when is_atom(App) ->
    is_kazoo_app(code:lib_dir(App));
is_kazoo_app(Path) when is_list(Path) ->
    'nomatch' =/= re:run(Path, "(core|applications)/").

get_dep_apps(KazooRoot, App) ->
    case application:get_key(App, 'applications') of
        {'ok', DepApps} -> DepApps;
        'undefined' -> consult_for_app_deps(KazooRoot, App)
    end.

consult_for_app_deps(KazooRoot, App) ->
    AppL = atom_to_list(App),
    case core_or_app(KazooRoot, AppL) of
        {'error', 'not_found'}=E -> E;
        CoreOrApp ->
            AppFile = filename:join([KazooRoot, CoreOrApp, AppL, "src", AppL ++ ".app.src"]),
            {'ok', [{'application', _App, Config}]} = file:consult(AppFile),
            proplists:get_value('applications', Config, [])
    end.

core_or_app(KazooRoot, AppL) ->
    core_or_app(KazooRoot, AppL, filelib:wildcard(KazooRoot ++ "/{core,applications,deps}/" ++ AppL)).

core_or_app(KazooRoot, AppL, []) ->
    stderr("failed to determine if ~s is core or dep in ~s~n", [AppL, KazooRoot]),
    {'error', 'not_found'};
core_or_app(_KazooRoot, _AppL, [Path]) ->
    filename:basename(filename:dirname(Path)).

stderr(Format, Args) ->
    io:format('standard_error', Format, Args).
