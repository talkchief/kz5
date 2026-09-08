-module(kazoo_media_maintenance_tests).

-include_lib("eunit/include/eunit.hrl").

%% Match the binding dispatch arity exactly. No application/database setup is
%% performed: a scoped hook must not enter the global system_config migration.
scoped_migration_test_() ->
    [?_assertEqual('ok', apply(kazoo_media_maintenance, migrate, [Accounts]))
     || Accounts <- [[],
                     [<<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>],
                     [<<"account%2Faa%2Faa%2Faaaaaaaaaaaaaaaaaaaaaaaaaaaa">>,
                      <<"account%2Fbb%2Fbb%2Fbbbbbbbbbbbbbbbbbbbbbbbbbbbb">>]]].

non_list_scope_rejected_test() ->
    ?assertError(function_clause, kazoo_media_maintenance:migrate(<<"not-an-account-list">>)).
