-module(kazoo_monster_catalog_tests).
-include_lib("eunit/include/eunit.hrl").

preserves_existing_test() ->
    IO=fun(find,_)->{ok,[existing_operator_doc]}; (_,_) -> error(unexpected_write) end,
    ?assertEqual(preserved,kazoo_monster_catalog:create_only(<<"db">>,meta(),[],IO)).
duplicates_fail_test() ->
    IO=fun(find,_)->{ok,[a,b]}; (_,_) -> error(unexpected_write) end,
    ?assertEqual({error,ambiguous_existing_apps},kazoo_monster_catalog:create_only(<<"db">>,meta(),[],IO)).
existing_id_never_updated_test() ->
    IO=fun(find,_)->{ok,[]}; (read,_)->{ok,unrelated_target}; (_,_) -> error(unexpected_write) end,
    ?assertEqual({error,target_not_proven_absent},kazoo_monster_catalog:create_only(<<"db">>,meta(),[],IO)).
one_doc_with_images_test() ->
    IO=fun(find,_)->{ok,[]}; (read,_)->{error,not_found};
        (create,{_,D})->
            ?assertEqual(undefined,kz_json:get_value(<<"_rev">>,D)),
            ?assertEqual(32,byte_size(kz_json:get_value(<<"_id">>,D))),
            ?assertEqual(base64:encode(<<"image">>),kz_json:get_value([<<"_attachments">>,<<"icon.png">>,<<"data">>],D)),{ok,D};
        (verify,_)->true
    end,
    ?assertEqual(created,kazoo_monster_catalog:create_only(<<"db">>,meta(),[{<<"icon.png">>,<<"image/png">>,<<"image">>}],IO)).
no_retry_or_rollback_test() ->
    IO=fun(find,_)->{ok,[]}; (read,_)->{error,not_found}; (create,_)->put(attempts,get(attempts)+1),{error,conflict}; (_,_) -> error(unexpected_write) end,
    put(attempts,0),?assertEqual({error,concurrent_create},kazoo_monster_catalog:create_only(<<"db">>,meta(),[],IO)),?assertEqual(1,get(attempts)).
created_unverified_is_not_success_test() ->
    IO=fun(find,_)->{ok,[]}; (read,_)->{error,not_found}; (create,{_,D})->{ok,D}; (verify,_)->false end,
    ?assertEqual({error,created_unverified},kazoo_monster_catalog:create_only(<<"db">>,meta(),[],IO)).
competing_absent_plans_test() ->
    Table=ets:new(catalog_create_race,[public,set]), Parent=self(),
    IO=fun(find,_)->{ok,[]}; (read,_)->{error,not_found};
        (create,{_,D})->case ets:insert_new(Table,{kz_json:get_value(<<"_id">>,D),D}) of true->{ok,D};false->{error,conflict} end;
        (verify,_)->true end,
    [spawn(fun()->Parent!kazoo_monster_catalog:create_only(<<"db">>,meta(),[],IO) end)||_<-lists:seq(1,2)],
    R=[receive X->X after 1000->error(timeout) end||_<-lists:seq(1,2)],
    ?assertEqual(lists:sort([created,{error,concurrent_create}]),lists:sort(R)),?assertEqual(1,ets:info(Table,size)),ets:delete(Table).

meta() -> kz_json:from_list([{<<"name">>,<<"acdc">>},{<<"api_url">>,<<"http://fixture.invalid/v2/">>}]).

master_configuration_is_required_test() ->
    ?assertEqual(<<"account%2F00%2F00%2F0000000000000000000000000000">>,
        kazoo_monster_catalog:master_db(<<"00000000000000000000000000000000">>)),
    [?assertException(error,_,kazoo_monster_catalog:master_db(Id)) || Id <-
        [undefined,<<>>,<<"not-an-account">>,<<"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA">>,
         <<"account%2F00%2F00%2F0000000000000000000000000000">>]].

protected_file_identity_and_content_test() ->
    %% Real filesystem checks; no live directory or credentials are read.
    Dir=filename:join("/tmp","kazoo-catalog-file-"++integer_to_list(erlang:unique_integer([positive]))),
    ok=file:make_dir(Dir), ok=file:change_mode(Dir,8#700),
    Path=filename:join(Dir,"metadata.json"),
    try
        ok=file:write_file(Path,<<"abcd">>),ok=file:change_mode(Path,8#600),
        ?assertEqual(<<"abcd">>,kazoo_monster_catalog:read_regular(Path,16)),
        ?assertException(error,_,kazoo_monster_catalog:read_regular(Path,16,
            fun()->file:write_file(Path,<<"efgh">>) end)),
        ?assertException(error,_,kazoo_monster_catalog:read_regular(Path,16,
            fun()->ok=file:rename(Path,Path++".old"),ok=file:write_file(Path,<<"efgh">>),file:change_mode(Path,8#600) end)),
        ?assertException(error,_,kazoo_monster_catalog:read_regular(Path,2)),
        ok=file:change_mode(Path,8#666),
        ?assertException(error,_,kazoo_monster_catalog:read_regular(Path,16))
    after file:delete(Path),file:delete(Path++".old"),file:del_dir(Dir) end.
