#!/usr/bin/env escript
%%! +S 1:1 +SDcpu 1 +SDio 1 +A 1 -setcookie unused_app_url_migration -start_epmd false -kernel logger_level none
%% SPDX-License-Identifier: MPL-2.0
%% Local, stdin-only, allowlisted migration bridge. No remote code installation.
-mode(compile).
-compile(warnings_as_errors).
-include_lib("kernel/include/file.hrl").

main(["--https"|Args]) ->
    true = erlang:get(migration_https) =:= undefined,
    put(migration_https, true),
    main(Args);
main(["--self-test"]) ->
    add_json_path(),
    ok = io:setopts(standard_io, [{encoding,unicode}]),
    self_test(),
    io:put_chars([jiffy:encode({[{<<"unicode">>,<<195,169,215,144>>}]}), "\n"]),
    io:put_chars("PASS bridge pure guards; no cookie read or distributed connection\n");
main(["--node", Node, "--cookie-file", CookiePath]) ->
    put(migration_stage, <<"json_loader">>),
    try
        add_json_path(),
        %% A C-locale service otherwise renders non-Latin metadata as \x{...},
        %% which is not a JSON escape. Keep the stdin/stdout protocol UTF-8.
        ok = io:setopts(standard_io, [{encoding,unicode}]),
        put(migration_stage, <<"local_identity">>),
        true = os:getenv("USER") =:= "root",
        {ok, Host} = inet:gethostname(),
        true = Node =:= "kazoo_apps@" ++ Host,
        put(migration_stage, <<"stdin_request">>),
        Request = read_request(),
        validate_request(Request),
        put(migration_stage, <<"cookie_file">>),
        {ok, #file_info{type=regular,uid=0,mode=Mode,links=1}} = file:read_link_info(CookiePath),
        true = (Mode band 8#077) =:= 0,
        {ok, Cookie0} = file:read_file(CookiePath),
        Cookie = list_to_binary(string:trim(binary_to_list(Cookie0))),
        true = byte_size(Cookie) >= 16 andalso byte_size(Cookie) =< 255,
        match = re:run(Cookie, <<"^[A-Za-z0-9_@.-]+$">>, [{capture,none}]),
        put(migration_stage, <<"local_distribution">>),
        ok = application:set_env(kernel, inet_dist_use_interface, {127,0,0,1}),
        Local = list_to_atom("app_url_migration_" ++ os:getpid() ++ "@" ++ Host),
        {ok, _} = net_kernel:start([Local, shortnames]),
        true = erlang:set_cookie(node(), binary_to_atom(Cookie, utf8)),
        put(migration_stage, <<"document_operation">>),
        Result = dispatch(list_to_atom(Node), Request),
        io:put_chars(jiffy:encode(Result)),
        io:put_chars("\n"),
        net_kernel:stop()
    catch
        _:_ ->
            %% Never render terms, stack traces, arguments, cookie or raw docs.
            %% The stage is a fixed internal label, never an exception term.
            io:put_chars(["{\"status\":\"error\",\"code\":\"bridge_failed\",\"stage\":\"",
                          get(migration_stage), "\"}\n"]),
            halt(1)
    end;
main(_) ->
    io:put_chars("Usage: bridge --node kazoo_apps@LOCAL_HOST --cookie-file FILE (JSON on stdin)\n"),
    halt(2).

add_json_path() ->
    Root = filename:dirname(filename:dirname(filename:absname(escript:script_name()))),
    true = code:add_patha(filename:join([Root,"deps","jiffy","ebin"])),
    {module,jiffy} = code:ensure_loaded(jiffy).

read_request() ->
    ok = io:setopts(standard_io, [binary]),
    Input = io:get_chars(standard_io, "", 8193),
    true = is_binary(Input) andalso byte_size(Input) =< 8192,
    jiffy:decode(Input).

apps() ->
    [{<<"accounts">>,<<"6fd9207e022cedcc3b1c9493b1bf7b20">>}
    ,{<<"acdc">>,<<"9ed4c13921516bb1d2afb9f1874290a3">>}
    ,{<<"callflows">>,<<"f607173df478e2654a7aa28b219c1a72">>}
    ,{<<"csv-onboarding">>,<<"747e264204ec61bae44a47fe8bc24532">>}
    ,{<<"fax">>,<<"1468daf86a7ec165af980daaf908bfdd">>}
    ,{<<"numbers">>,<<"f3248fe1214da79cb5d089614bf22651">>}
    ,{<<"pbxs">>,<<"ee30412619e9e4d922c99467db8a5268">>}
    ,{<<"voicemails">>,<<"f61021d214b6e7e8d3a41429133ea99b">>}
    ,{<<"voip">>,<<"f9a82ad18cf17c9a73b836ff0feba33f">>}
    ,{<<"webhooks">>,<<"b94a5cff43467f9e0755aa2f7e9d560e">>}].
db() -> <<"account%2F30%2F2a%2Fe5a70c403124f764cbc54229cfcd">>.
account() -> <<"302ae5a70c403124f764cbc54229cfcd">>.
from_url() ->
    case erlang:get(migration_https) of
        true -> <<"http://kz5.talkchief.io/v2/">>;
        _ -> <<"http://91.99.188.145:8000/v2/">>
    end.
to_url() ->
    case erlang:get(migration_https) of
        true -> <<"https://kz5.talkchief.io/v2/">>;
        _ -> <<"http://kz5.talkchief.io/v2/">>
    end.
get(Key, {Props}) -> proplists:get_value(Key, Props).
valid_revision(Rev) when is_binary(Rev) ->
    re:run(Rev, <<"^[1-9][0-9]*-[a-f0-9]+$">>, [{capture,none}]) =:= match;
valid_revision(_) -> false.

validate_request({Props}=Request) ->
    true = length(Props) =:= length(lists:ukeysort(1,Props)),
    Id = get(<<"id">>, Request),
    true = lists:keymember(Id, 2, apps()),
    case get(<<"action">>, Request) of
        <<"read">> -> true = lists:sort([K || {K,_} <- Props]) =:= [<<"action">>,<<"id">>];
        <<"save">> ->
            true = lists:sort([K || {K,_} <- Props]) =:= [<<"action">>,<<"expected_revision">>,<<"expected_sha256">>,<<"id">>],
            true = valid_revision(get(<<"expected_revision">>, Request)),
            match = re:run(get(<<"expected_sha256">>, Request), <<"^[a-f0-9]{64}$">>, [{capture,none}])
    end.

validate_doc(Id, {Props}=Doc) ->
    true = length(Props) =:= length(lists:ukeysort(1,Props)),
    {Name,Id} = lists:keyfind(Id,2,apps()),
    true = get(<<"_id">>,Doc) =:= Id,
    true = get(<<"name">>,Doc) =:= Name,
    true = get(<<"pvt_type">>,Doc) =:= <<"app">>,
    true = get(<<"pvt_account_id">>,Doc) =:= account(),
    true = get(<<"pvt_account_db">>,Doc) =:= db(),
    true = valid_revision(get(<<"_rev">>,Doc)),
    %% kz_datamgr deliberately deletes a public `id' key on save. Refuse that
    %% shape so the promise to preserve all unrelated fields stays true.
    false = lists:keymember(<<"id">>,1,Props),
    true = lists:member(get(<<"_deleted">>,Doc), [undefined,false]),
    true = lists:member(get(<<"pvt_deleted">>,Doc), [undefined,false]),
    ok.

sha256(Bin) ->
    iolist_to_binary([io_lib:format("~2.16.0b",[X]) || <<X>> <= crypto:hash(sha256,Bin)]).

%% Jiffy returns iodata, not necessarily a binary for larger app metadata.
encode_doc(Doc) -> iolist_to_binary(jiffy:encode(Doc)).

dispatch(Node, Request) ->
    Id = get(<<"id">>,Request),
    case rpc:call(Node,kz_datamgr,open_doc,[db(),Id],5000) of
        {ok,Doc} ->
            put(migration_stage, <<"document_identity">>),
            validate_doc(Id,Doc),
            put(migration_stage, <<"document_encoding">>),
            Raw = encode_doc(Doc),
            true = byte_size(Raw) =< 1048576,
            case get(<<"action">>,Request) of
                <<"read">> -> {[{<<"status">>,<<"ok">>},{<<"raw_json">>,Raw}]};
                <<"save">> -> save(Node,Id,Doc,Raw,Request)
            end;
        _ -> {[{<<"status">>,<<"error">>},{<<"code">>,<<"read_failed">>}]}
    end.

prepare_update(Id, {Props}=Doc, Raw, Request) ->
    validate_doc(Id,Doc),
    true = get(<<"_rev">>,Doc) =:= get(<<"expected_revision">>,Request),
    true = sha256(Raw) =:= get(<<"expected_sha256">>,Request),
    true = get(<<"api_url">>,Doc) =:= from_url(),
    {lists:keyreplace(<<"api_url">>,1,Props,{<<"api_url">>,to_url()})}.

save(Node,Id,Doc,Raw,Request) ->
    try prepare_update(Id,Doc,Raw,Request) of
        Updated ->
            %% Keep the original _rev. Never refresh it, ensure_saved/update_doc,
            %% suppress notices, or re-import application images.
            case rpc:call(Node,kz_datamgr,save_doc,[db(),Updated,[{publish_change_notice,true}]],5000) of
                {ok,Saved} ->
                    Rev = get(<<"_rev">>,Saved),
                    true = valid_revision(Rev),
                    true = Rev =/= get(<<"_rev">>,Doc),
                    {[{<<"status">>,<<"committed">>},{<<"revision">>,Rev}]};
                _ -> {[{<<"status">>,<<"uncertain">>},{<<"code">>,<<"save_unconfirmed">>}]}
            end
    catch
        _:_ -> {[{<<"status">>,<<"uncertain">>},{<<"code">>,<<"save_unconfirmed">>}]}
    end.

self_test() ->
    {Name,Id}=hd(apps()),
    Doc = {[{<<"_id">>,Id},{<<"_rev">>,<<"2-abcdef">>},{<<"name">>,Name}
           ,{<<"pvt_type">>,<<"app">>},{<<"pvt_account_id">>,account()},{<<"pvt_account_db">>,db()}
           ,{<<"api_url">>,from_url()},{<<"nested">>,{[{<<"secret">>,<<"do-not-print">>}]}}
           ,{<<"_attachments">>,{[{<<"icon.png">>,{[{<<"stub">>,true},{<<"digest">>,<<"md5-example">>}]}}]}}]},
    Raw=encode_doc(Doc),
    Request={[{<<"action">>,<<"save">>},{<<"id">>,Id},{<<"expected_revision">>,<<"2-abcdef">>},{<<"expected_sha256">>,sha256(Raw)}]},
    validate_request(Request),
    Updated=prepare_update(Id,Doc,Raw,Request),
    {Properties}=Doc,
    Doc={lists:keyreplace(<<"api_url">>,1,element(1,Updated),{<<"api_url">>,from_url()})},
    true=get(<<"api_url">>,Updated)=:=to_url(),
    lists:foreach(fun(Bad) ->
        {'EXIT',_}=(catch prepare_update(Id,Bad,jiffy:encode(Bad),Request))
    end,[{lists:keyreplace(<<"_rev">>,1,Properties,{<<"_rev">>,<<"3-abcdef">>})}
         ,{lists:keyreplace(<<"name">>,1,Properties,{<<"name">>,<<"other">>})}
         ,{[{<<"id">>,Id}|Properties]}]),
    {'EXIT',_}=(catch validate_request({[{<<"action">>,<<"delete">>},{<<"id">>,Id}]})),
    LargeDoc={[{<<"large_metadata">>,binary:copy(<<"x">>,65536)}|Properties]},
    LargeEncoded=jiffy:encode(LargeDoc),
    true=is_list(LargeEncoded),
    LargeRaw=encode_doc(LargeDoc),
    true=is_binary(LargeRaw),
    true=byte_size(LargeRaw)>65536,
    LargeDoc=jiffy:decode(LargeRaw),
    LargeRequest={lists:keyreplace(<<"expected_sha256">>,1,element(1,Request),
                                  {<<"expected_sha256">>,sha256(LargeRaw)})},
    LargeUpdated=prepare_update(Id,LargeDoc,LargeRaw,LargeRequest),
    LargeDoc={lists:keyreplace(<<"api_url">>,1,element(1,LargeUpdated),{<<"api_url">>,from_url()})},
    ok.
