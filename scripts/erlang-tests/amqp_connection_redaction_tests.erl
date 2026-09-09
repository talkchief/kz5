-module(amqp_connection_redaction_tests).
-include_lib("eunit/include/eunit.hrl").
-include("kz_amqp.hrl").

connection_messages_redact_credentials_test() ->
    meck:new(lager,[non_strict,no_link]),
    meck:new(kz_amqp_connections,[non_strict,no_link]),
    Parent=self(),
    [meck:expect(lager,L,fun(F,A)->Parent!{logged,L,iolist_to_binary(io_lib:format(F,A))},ok end)
     || L<-[debug,info,notice,warning,critical]],
    meck:expect(kz_amqp_connections,unavailable,fun(_)->ok end),
    meck:expect(kz_amqp_connections,broker_zone,fun(_)->local end),
    try
        [begin
            Ref=make_ref(), C=#kz_amqp_connection{broker=URI,manager=self(),connection_ref=Ref,available=true},
            {noreply,C}=kz_amqp_connection:handle_info(#'connection.blocked'{reason = <<"resource pressure">>},C),
            {noreply,C}=kz_amqp_connection:handle_info(#'connection.unblocked'{},C),
            {noreply,C,hibernate}=kz_amqp_connection:handle_info(unknown_fixture_message,C),
            {noreply,Next,hibernate}=kz_amqp_connection:handle_info({'DOWN',Ref,process,self(),shutdown},C),
            ?assertEqual(URI,Next#kz_amqp_connection.broker),
            erlang:cancel_timer(Next#kz_amqp_connection.reconnect_ref),
            Logs=collect([]),?assert(length(Logs)>=4),
            ?assert(lists:any(fun({critical,B})->binary:match(B,<<"broker.test">>)=/=nomatch;(_)->false end,Logs)),
            [?assertEqual(nomatch,binary:match(B,<<"SECRET_SENTINEL">>)) || {_,B}<-Logs],
            [?assertEqual(nomatch,binary:match(B,<<"PRIVATE_USER">>)) || {_,B}<-Logs]
         end || URI<-[<<"amqp://PRIVATE_USER:SECRET_SENTINEL@broker.test:5672/%2F">>,
                       <<"amqps://PRIVATE_USER:SECRET_SENTINEL@broker.test:5671/vhost">>]]
    after meck:unload(lager),meck:unload(kz_amqp_connections) end.
collect(Acc) -> receive {logged,L,B}->collect([{L,B}|Acc]) after 0->Acc end.
