#!/usr/bin/env escript
%%! +A0 -sname kazoo_hank
%% -*- coding: utf-8 -*-

-mode('compile').

-export([main/1]).

%% API

main([]) ->
    AppFiles = lists:foldl(fun add_app_path/2, [], kz_ast_util:project_apps()),
    main(AppFiles);
main(Files) ->
    #{results := Results
     ,stats := Stats
     } = hank:analyze(Files
                     ,hank_ignores()
                     ,hank_rules()
                     ,parsing_style()
                     ,hank_context()
                     ),
    print_stats(Stats),
    io:format("results(~p):~n", [length(Results)]),
    {_LastRule, Counts} = lists:foldl(fun print_result/2, {'undefined', #{}}, Results),
    io:format("rule violations: ~p~n", [Counts]).

add_app_path(App, Acc) ->
    filelib:wildcard(
      filename:join([code:lib_dir(App), "**/*.[e|h]rl"])
     ) ++ Acc.

print_stats(#{ignored := Ignored
             ,parsing := ParsingMs
             ,analyzing := AnalysisMs
             ,total := TotalMs
             }) ->
    io:format("analysis took ~pms parsing, ~pms analyzing, ~pms total, ignore ~p files~n"
             ,[ParsingMs, AnalysisMs, TotalMs, Ignored]
             ).

print_result(#{file := File
              ,line := Line
              ,pattern := Pattern
              ,rule := Rule
              ,text := Text
              }
            ,{Rule, RuleCounts}
            ) ->
    io:format("~s:~p: ~s~n~n"
             ,[File, Line, rule_text(Rule, Text, Pattern)]
             ),
    {Rule, maps:update_with(Rule, fun(V) -> V+1 end, 1, RuleCounts)};
print_result(#{rule := NewRule}=Result
            ,{_OldRule, RuleCounts}
            ) ->
    io:format("rule violations for ~s:~n", [NewRule]),
    print_result(Result, {NewRule, RuleCounts}).

rule_text(_Rule, Text, _Pattern) ->
    Text.

-spec hank_ignores() -> [hank_rule:ignore_spec()].
hank_ignores() -> [].

hank_rules() ->
    hank_rule:default_rules().

parsing_style() ->
    'sequential'. % or parallel

hank_context() ->
    Apps = [{App, code:lib_dir(App)}
            || App <- kz_ast_util:project_apps()
           ],
    hank_context:new(maps:from_list(Apps), []).
