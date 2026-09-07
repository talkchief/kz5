%%% Actual production Lager-transform runtime; no logger or dispatcher mocks.
%%% Private in-memory gen_event sink only: no application/file handlers started.
-module(kazoo_bindings_lager_tests).
-behaviour(gen_event).
-include_lib("eunit/include/eunit.hrl").
-export([init/1,handle_event/2,handle_call/2,handle_info/2,terminate/2,code_change/3]).
-export([respond/1,continue/1,actual_clause/1]).
-define(ROUTE, <<"fixture.binding.transformed">>).
-define(SECRET, <<"FIXTURE_ONLY_TRANSFORMED_BINDING_SECRET">>).

init([]) -> {ok,[]}.
handle_event({log,Msg},Rows) when length(Rows) < 128 ->
    %% Both rendering and metadata come from real Lager, after its generated
    %% eligibility check, do_log, format, lager_msg and sync_notify path.
    Rendered=iolist_to_binary(lager_default_formatter:format(Msg,
        [severity," ",module,":",function," ",message])),
    true=byte_size(Rendered) =< 8192,
    Row=#{rendered=>Rendered,metadata=>lager_msg:metadata(Msg),severity=>lager_msg:severity(Msg)},
    {ok,[Row|Rows]};
handle_event(_,_) -> exit(fixture_capture_overflow).
handle_call(rows,Rows) -> {ok,lists:reverse(Rows),Rows};
handle_call(clear,_) -> {ok,ok,[]}.
handle_info(_,Rows) -> {ok,Rows}.
terminate(_,_) -> ok.
code_change(_,Rows,_) -> {ok,Rows}.

respond({raise,Class,Reason,Trace}) -> erlang:raise(Class,Reason,Trace);
respond({actual_clause,Value}) -> actual_clause(Value).
actual_clause(allowed) -> allowed.
continue(Value) -> {continued,Value}.

with_runtime(Work) ->
    ?assertEqual(undefined,whereis(lager_event)),
    ?assertEqual(undefined,whereis(kazoo_bindings)),
    ok=lager_config:new(),
    _=lager_config:set(loglevel,{255,[]}),_=lager_config:set(async,false),
    {ok,Sink}=gen_event:start_link({local,lager_event}),unlink(Sink),
    try
        ok=gen_event:add_handler(Sink,?MODULE,[]),
        ?assertEqual([?MODULE],gen_event:which_handlers(Sink)),
        ok=kz_log:put_callid(<<"fixture-transformed-binding">>),
        {ok,Bindings}=kazoo_bindings:start_link(),unlink(Bindings),
        try
            Table=ets:new(kazoo_bindings:table_id(),kazoo_bindings:table_options()),
            true=ets:give_away(Table,Bindings,fixture),true=gen_server:call(Bindings,is_ready),
            ok=kazoo_bindings:bind(?ROUTE,?MODULE,respond),
            ok=gen_event:call(Sink,?MODULE,clear),
            Work(Sink)
        after gen_server:stop(Bindings) end
    after gen_event:stop(Sink),lager_config:cleanup() end.

input(Class,Reason,Arity) ->
    {raise,Class,Reason,[{fixture_inner,failed,Arity,[{file,?SECRET},{line,17}]}]}.
exception(Input) ->
    try respond(Input) catch Class:Reason:ST ->
        case Class of error -> {'EXIT',{Reason,ST}}; _ -> {'EXIT',Reason} end
    end.
logged(Sink) ->
    Rows=gen_event:call(Sink,?MODULE,rows),
    ?assert(is_list(Rows)),
    Errors=[R || #{severity:=error}=R <- Rows],
    ?assert(length(Errors) > 0),
    Bytes=iolist_to_binary(io_lib:format("~p",[Rows])),
    ?assertEqual(nomatch,binary:match(Bytes,?SECRET)),
    ?assert(lists:all(fun(#{rendered:=Text,metadata:=Metadata})->
        binary:match(Text,<<"binding responder failure">>) =/= nomatch
        andalso binary:match(Text,<<"{kazoo_bindings_lager_tests,respond,1}">>) =/= nomatch
        andalso proplists:get_value(module,Metadata) =:= kazoo_bindings
        andalso proplists:get_value(function,Metadata) =:= log_binding_exception
    end,Errors)),
    Errors.

category_count(Rows,Category) ->
    Needle=iolist_to_binary(["(",atom_to_list(Category),")"]),
    length([ok || #{rendered:=Text} <- Rows,binary:match(Text,Needle) =/= nomatch]).

transformed_integer_arity_map_and_pmap_test() -> with_runtime(fun(Sink)->
    lists:foreach(fun(Reason)->
        Input=input(error,Reason,1),Expected=exception(Input),
        ?assertEqual([Expected],kazoo_bindings:map(?ROUTE,[Input])),
        ?assertEqual([Expected],kazoo_bindings:pmap(?ROUTE,[Input]))
    end,[function_clause,undef]),
    Rows=logged(Sink),?assertEqual(4,length(Rows)),
    ?assertEqual(2,category_count(Rows,function_clause)),
    ?assertEqual(2,category_count(Rows,undef))
end).

transformed_actual_clause_and_sensitive_reasons_are_redacted_test() -> with_runtime(fun(Sink)->
    ?assertMatch([{'EXIT',{function_clause,_}}],kazoo_bindings:map(?ROUTE,[{actual_clause,?SECRET}])),
    lists:foreach(fun(Class)->
        Input=input(Class,{private_reason,?SECRET},[#{auth_token=>?SECRET}]),
        ?assertEqual([exception(Input)],kazoo_bindings:map(?ROUTE,[Input]))
    end,[error,throw,exit]),
    Rows=logged(Sink),?assertEqual(4,length(Rows)),
    [?assertEqual(1,category_count(Rows,Category)) || Category <- [function_clause,error,throw,exit]]
end).

transformed_fold_preserves_later_responder_test() -> with_runtime(fun(Sink)->
    ok=kazoo_bindings:bind(?ROUTE,?MODULE,continue),
    lists:foreach(fun({Class,Reason})->
        Input=input(Class,Reason,1),
        ?assertEqual({continued,Input},kazoo_bindings:fold(?ROUTE,[Input]))
    end,[{error,function_clause},{error,undef},{error,{private_reason,?SECRET}},
          {throw,?SECRET},{exit,?SECRET}]),
    Rows=logged(Sink),?assertEqual(5,length(Rows)),
    [?assertEqual(1,category_count(Rows,Category)) || Category <- [function_clause,undef,error,throw,exit]]
end).

transformed_missing_backend_preserves_exception_test() -> with_runtime(fun(Sink)->
    Input=input(error,function_clause,1),Expected=exception(Input),
    ?assertEqual([Expected],kazoo_bindings:map(?ROUTE,[Input])),
    ?assertEqual(1,length(logged(Sink))),
    %% Real gen_event backend removal, not a substitute lager:error function.
    ok=gen_event:delete_handler(Sink,?MODULE,normal),
    ?assertEqual([],gen_event:which_handlers(Sink)),
    ?assertEqual([Expected],kazoo_bindings:map(?ROUTE,[Input])),
    ok=kazoo_bindings:bind(?ROUTE,?MODULE,continue),
    ?assertEqual({continued,Input},kazoo_bindings:fold(?ROUTE,[Input]))
end).
