%%% Real binding registry and dispatcher; only logging sinks are substituted.
-module(kazoo_bindings_exception_tests).
-include_lib("eunit/include/eunit.hrl").
-export([respond/1, continue/1, actual_clause/1]).
-define(ROUTE, <<"fixture.binding.exception">>).
-define(SECRET, <<"FIXTURE_ONLY_BINDING_AUTH_SECRET">>).

respond({raise,Class,Reason,Trace}) -> erlang:raise(Class,Reason,Trace);
respond({actual_clause,Value}) -> actual_clause(Value);
respond({return,Value}) -> Value.
actual_clause(allowed) -> allowed.
continue(Value) -> {continued,Value}.

with_bindings(Work) ->
    meck:new([lager,kz_log],[non_strict,no_link]),
    try
        [begin
             meck:expect(lager,Level,fun(_) -> ok end),
             meck:expect(lager,Level,fun(_,_) -> ok end)
         end || Level <- [debug,info,error]],
        meck:expect(kz_log,put_callid,fun(_)->ok end),
        meck:expect(kz_log,get_callid,fun()-><<"fixture">> end),
        meck:expect(kz_log,log_stacktrace,fun(_)->ok end),
        {ok,Pid}=kazoo_bindings:start_link(),unlink(Pid),
        try
            Table=ets:new(kazoo_bindings:table_id(),kazoo_bindings:table_options()),
            true=ets:give_away(Table,Pid,fixture),true=gen_server:call(Pid,is_ready),
            ok=kazoo_bindings:bind(?ROUTE,?MODULE,respond),
            Work()
        after gen_server:stop(Pid) end
    after meck:unload([lager,kz_log]) end.

raise_input(Class,Reason,Args) ->
    {raise,Class,Reason,[{fixture_inner,failed,Args,[{file,?SECRET},{line,17}]}]}.
redacted() ->
    Logs=iolist_to_binary(io_lib:format("~p",[[meck:history(lager),meck:history(kz_log)]])),
    ?assertEqual(nomatch,binary:match(Logs,?SECRET)),
    ?assertEqual(0,meck:num_calls(kz_log,log_stacktrace,'_')),
    ok.

integer_arity_function_clause_preserves_map_and_pmap_test() -> with_bindings(fun()->
    Input=raise_input(error,function_clause,1),
    {raise,_,_,ST}=Input,
    ?assertEqual([{'EXIT',{function_clause,ST}}],kazoo_bindings:map(?ROUTE,[Input])),
    ?assertEqual([{'EXIT',{function_clause,ST}}],kazoo_bindings:pmap(?ROUTE,[Input])),
    redacted()
end).

integer_arity_undef_preserves_map_test() -> with_bindings(fun()->
    Input=raise_input(error,undef,2),{raise,_,_,ST}=Input,
    ?assertEqual([{'EXIT',{undef,ST}}],kazoo_bindings:map(?ROUTE,[Input])),redacted()
end).

real_function_clause_never_logs_request_arguments_test() -> with_bindings(fun()->
    ?assertMatch([{'EXIT',{function_clause,_}}],kazoo_bindings:map(?ROUTE,[{actual_clause,?SECRET}])),
    redacted()
end).

argument_lists_and_frame_metadata_are_redacted_and_bounded_test() -> with_bindings(fun()->
    ST=lists:duplicate(32,{fixture_inner,failed,[#{auth_token=>?SECRET}],[{file,?SECRET},{line,17}]}),
    Input={raise,error,function_clause,ST},
    % OTP may truncate raised stacks to its configured backtrace depth. Compare
    % to the actual subscriber exception, not the pre-raise synthetic list.
    Raised=try respond(Input) catch error:function_clause:RaisedST -> RaisedST end,
    ?assert(length(Raised) >= 8),
    ?assertEqual([{'EXIT',{function_clause,Raised}}],kazoo_bindings:map(?ROUTE,[Input])),
    redacted(),
    Frames=[Fs || {_,{lager,error,[_,[function_clause,{?MODULE,respond,1},Fs]]},ok} <- meck:history(lager)],
    ?assertEqual([lists:duplicate(8,{fixture_inner,failed,1})],Frames)
end).

generic_error_throw_exit_preserve_original_results_without_reason_logging_test() -> with_bindings(fun()->
    lists:foreach(fun(Class)->
        Reason={private_reason,?SECRET},Input=raise_input(Class,Reason,[?SECRET]),{raise,_,_,ST}=Input,
        Expected=case Class of error -> {'EXIT',{Reason,ST}}; _ -> {'EXIT',Reason} end,
        ?assertEqual([Expected],kazoo_bindings:map(?ROUTE,[Input]))
    end,[error,throw,exit]),redacted()
end).

fold_continues_after_subscriber_exceptions_test() -> with_bindings(fun()->
    ok=kazoo_bindings:bind(?ROUTE,?MODULE,continue),
    lists:foreach(fun({Class,Reason})->
        Input=raise_input(Class,Reason,1),
        ?assertEqual({continued,Input},kazoo_bindings:fold(?ROUTE,[Input]))
    end,[{error,function_clause},{error,undef},{error,{private_reason,?SECRET}},
          {throw,?SECRET},{exit,?SECRET}]),redacted()
end).

returned_error_and_exit_fold_semantics_are_unchanged_test() -> with_bindings(fun()->
    ok=kazoo_bindings:bind(?ROUTE,?MODULE,continue),
    %% Preserve even this existing fold result-unwrapping failure; this patch
    %% changes diagnostics, not returned-error interpretation.
    ?assertError({badmatch,{error,?SECRET}},kazoo_bindings:fold(?ROUTE,[{return,{error,?SECRET}}])),
    Input={return,{'EXIT',?SECRET}},
    ?assertEqual({continued,Input},kazoo_bindings:fold(?ROUTE,[Input])),redacted()
end).

logger_failure_cannot_replace_subscriber_exception_test() -> with_bindings(fun()->
    meck:expect(lager,error,fun(_,_)->erlang:error(logger_failed) end),
    ok=kazoo_bindings:bind(?ROUTE,?MODULE,continue),
    Input=raise_input(error,function_clause,1),{raise,_,_,ST}=Input,
    Results=kazoo_bindings:map(?ROUTE,[Input]),
    ?assert(lists:member({'EXIT',{function_clause,ST}},Results)),
    ?assert(lists:member({continued,Input},Results)),
    ?assertEqual({continued,Input},kazoo_bindings:fold(?ROUTE,[Input]))
end).
