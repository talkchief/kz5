-module(call_forward_confirmation_tests).
-include_lib("eunit/include/eunit.hrl").
-define(ACCOUNT, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(FOREIGN, <<"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb">>).
-define(FIELD, <<"call_forward_confirmation">>).

confirmation_test_() ->
    {foreach, fun setup/0, fun cleanup/1,
     [fun selection/0, fun media_rejection/0, fun endpoint_paths/0,
      fun account_normalization/0, fun account_permissions/0, fun readiness_failure/0,
      fun readiness_bytes/0]}.

setup() ->
    meck:new(kzd_accounts, [passthrough, no_link]),
    meck:expect(kzd_accounts, fetch, fun(Id) ->
        ?assertEqual(?ACCOUNT, Id), {ok, account(get(locale))}
    end),
    meck:expect(kzd_accounts, tree, fun(_) -> [] end),
    meck:new(kz_datamgr, [non_strict, no_link]),
    meck:expect(kz_datamgr, open_cache_doc, fun(<<"system_media">>, Id) -> media(Id) end),
    meck:expect(kz_datamgr, open_doc, fun(<<"system_media">>, Id, _) -> media(Id) end),
    meck:expect(kz_datamgr, fetch_attachment, fun(<<"system_media">>, Id, _) ->
        [L] = [L || {L, MediaId, _, _, _, _, _} <- kz_call_forward_confirmation:assets(), MediaId =:= Id],
        {ok, Bytes} = file:read_file(filename:join(["scripts", "assets", "call-forward-confirmation-20260908",
            binary_to_list(L) ++ ".attempt-1.telephony.wav"])),
        case get(bad_bytes) of true -> {ok, <<"corrupted">>}; _ -> {ok, Bytes} end
    end),
    meck:new(kapps_call, [non_strict, no_link]),
    meck:expect(kapps_call, account_id, fun(call) -> ?FOREIGN end),
    meck:expect(kapps_call, get_prompt, fun(call, <<"ivr-group_confirm">>) -> <<"legacy-call-language-and-custom-override">> end),
    meck:new(kzd_endpoint, [passthrough, no_link]),
    meck:expect(kzd_endpoint, get_prompt, fun(_, <<"ivr-group_confirm">>) -> <<"legacy-endpoint-language-and-custom-override">> end),
    meck:new(kapps_config, [non_strict, no_link]),
    meck:expect(kapps_config, get_ne_binary, fun(_, _, Default) -> Default end),
    put(locale, undefined), put(bad_media, false), ok.

cleanup(_) -> meck:unload(), erase(locale), erase(bad_media).

account(undefined) -> j([{<<"_id">>, ?ACCOUNT}]);
account(L) -> j([{<<"_id">>, ?ACCOUNT}, {?FIELD, j([{<<"language">>, L}])}]).

media(Id) ->
    [A] = [A || A <- kz_call_forward_confirmation:assets(), element(2,A) =:= Id],
    case get(bad_media) of true -> {error,not_found}; _ -> {ok,doc(A)} end.

doc({L,Id,Prompt,Sha,Md5,Size,Transcript}) ->
    j([{<<"_id">>,Id},{<<"_rev">>,<<"1-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>},
       {<<"pvt_type">>,<<"media">>},{<<"pvt_account_db">>,<<"system_media">>},
       {<<"source_type">>,<<"kazoo5_call_forward_confirmation_v1">>},{<<"prompt_id">>,Prompt},
       {<<"language">>,L},{<<"content_type">>,<<"audio/wav">>},{<<"content_length">>,Size},{<<"streamable">>,true},
       {<<"source_voice">>,j([{<<"provider">>,<<"google-gemini">>},{<<"model">>,<<"gemini-2.5-pro-preview-tts">>},
                            {<<"voice">>,<<"Sulafat">>},{<<"sha256">>,Sha},{<<"transcript_sha256">>,Transcript}])},
       {<<"_attachments">>,j([{<<Prompt/binary,".wav">>,j([{<<"content_type">>,<<"audio/wav">>},
                                                       {<<"digest">>,Md5},{<<"length">>,Size}])}])}]).

selection() ->
    ?assertEqual(legacy,kz_call_forward_confirmation:select(?ACCOUNT,fun()->legacy end)),
    lists:foreach(fun({L,Id,_,_,_,_,_})->
        put(locale,L), ?assertEqual(<<"/system_media/",Id/binary>>,
            kz_call_forward_confirmation:select(?ACCOUNT,fun()->error(unexpected_fallback) end))
    end,kz_call_forward_confirmation:assets()),
    put(locale,<<"he-il">>),put(bad_media,true),
    ?assertEqual(legacy,kz_call_forward_confirmation:select(?ACCOUNT,fun()->legacy end)),
    ?assertEqual(legacy,kz_call_forward_confirmation:select_with(?ACCOUNT,fun()->legacy end,
        fun(_)->{error,timeout} end,fun(_)->error(unexpected_media) end)),
    put(locale,undefined),put(bad_media,false),
    ?assertEqual(legacy,kz_call_forward_confirmation:select(?ACCOUNT,fun()->legacy end)).

media_rejection() ->
    lists:foreach(fun(A) ->
        D=doc(A), ?assert(kz_call_forward_confirmation:valid_media(A,{ok,D})),
        lists:foreach(fun({K,V})->
            ?assertNot(kz_call_forward_confirmation:valid_media(A,{ok,kz_json:set_value(K,V,D)}))
        end,[{<<"language">>,<<"de-de">>},{<<"source_type">>,<<"customer">>},
             {<<"_id">>,<<"different">>},{<<"pvt_deleted">>,true},{<<"_conflicts">>,[<<"2-conflict">>]},
             {[<<"source_voice">>,<<"sha256">>],<<"bad">>},{<<"_attachments">>,j([])}])
    end,kz_call_forward_confirmation:assets()),
    ?assertEqual({error,unsupported_language},kz_call_forward_confirmation:builtin(<<"de-de">>)).

endpoint_paths() ->
    EP=j([{<<"pvt_account_id">>,?ACCOUNT}]), Fwd=j([{<<"require_keypress">>,true}]), CCV=j([{<<"Existing">>,<<"preserved">>}]),
    lists:foreach(fun(Module)->
        put(locale,undefined), Before=Module:maybe_set_confirm_properties({EP,call,Fwd,CCV}),
        {EP,call,Fwd,OldVars}=Before, ?assertEqual(<<"1">>,kz_json:get_value(<<"Confirm-Key">>,OldVars)),
        lists:foreach(fun({L,Id,_,_,_,_,_})->
            put(locale,L), {EP,call,Fwd,Vars}=Module:maybe_set_confirm_properties({EP,call,Fwd,CCV}),
            ?assertEqual(<<"/system_media/",Id/binary>>,kz_json:get_value(<<"Confirm-File">>,Vars)),
            ?assertEqual(kz_json:delete_key(<<"Confirm-File">>,OldVars),kz_json:delete_key(<<"Confirm-File">>,Vars))
        end,kz_call_forward_confirmation:assets()),
        Off=j([{<<"require_keypress">>,false}]),
        ?assertEqual({EP,call,Off,CCV},Module:maybe_set_confirm_properties({EP,call,Off,CCV}))
    end,[kz_endpoint_v4,kz_endpoint_v5]),
    lists:foreach(fun(Kind)->
        Endpoint=kz_json:set_value(<<"call_failover">>,Fwd,EP),
        Call=fun()->case Kind of
            forward -> kz_directory_cfwd:call_forward_confirm_properties(<<"device">>,?ACCOUNT,Endpoint,Fwd,true);
            failover -> kz_directory_failover:call_failover_confirm_properties(<<"device">>,?ACCOUNT,Endpoint,true)
        end end,
        put(locale,undefined), Before=Call(),
        lists:foreach(fun({L,Id,_,_,_,_,_})->
            put(locale,L), After=Call(),
            ?assertEqual(<<"/system_media/",Id/binary>>,proplists:get_value(<<"Confirm-File">>,After)),
            ?assertEqual(proplists:delete(<<"Confirm-File">>,Before),proplists:delete(<<"Confirm-File">>,After)),
            ?assertEqual(<<"1">>,proplists:get_value(<<"Confirm-Key">>,After))
        end,kz_call_forward_confirmation:assets())
    end,[forward,failover]).

account_normalization() ->
    Existing=account(<<"he-il">>), Request=j([{<<"name">>,<<"Unrelated update">>}]),
    {ok,Kept,unchanged}=cb_account_call_forward_confirmation:normalize(undefined,Existing,Request),
    ?assertEqual(<<"he-il">>,kzd_accounts:call_forward_confirmation_language(Kept)),
    {ok,Reset,reset}=cb_account_call_forward_confirmation:normalize(j([{<<"language">>,null}]),Existing,Kept),
    ?assertEqual(undefined,kz_json:get_value(?FIELD,Reset)),
    ?assertEqual(<<"Unrelated update">>,kz_json:get_value(<<"name">>,Reset)),
    lists:foreach(fun(V)->?assertMatch({error,_},cb_account_call_forward_confirmation:normalize(V,Existing,Request)) end,
        [null,false,<<"he-il">>,j([]),j([{<<"language">>,<<"de-de">>}]),j([{<<"language">>,<<"he-il">>},{<<"url">>,<<"external">>}])]).

context(Admin,Value) -> cb_context:setters(cb_context:new(),[
    {fun cb_context:set_auth_account_id/2,?ACCOUNT},{fun cb_context:set_is_account_admin/2,Admin},
    {fun cb_context:set_is_superduper_admin/2,false},{fun cb_context:set_auth_doc/2,j([{<<"account_id">>,?ACCOUNT},{<<"owner_id">>,<<"user">>}])},
    {fun cb_context:set_req_data/2,j([{?FIELD,Value}])}]).

account_permissions() ->
    C=context(true,j([{<<"language">>,null}])),
    ?assert(cb_account_call_forward_confirmation:authorized(?ACCOUNT,C)),
    ?assertNot(cb_account_call_forward_confirmation:authorized(?FOREIGN,C)),
    ?assertNot(cb_account_call_forward_confirmation:authorized(?ACCOUNT,cb_context:set_is_account_admin(C,false))),
    ?assertNot(cb_account_call_forward_confirmation:authorized(?ACCOUNT,cb_context:set_auth_account_id(C,undefined))),
    API=cb_context:set_auth_doc(cb_context:set_is_account_admin(C,false),j([{<<"account_id">>,?ACCOUNT},{<<"method">>,<<"cb_api_auth">>}])),
    ?assert(cb_account_call_forward_confirmation:authorized(?ACCOUNT,API)),
    put(locale,<<"he-il">>),
    ?assertMatch({ok,_},cb_account_call_forward_confirmation:prepare(?ACCOUNT,C)),
    ?assertMatch({error,_},cb_account_call_forward_confirmation:prepare(?ACCOUNT,cb_context:set_is_account_admin(C,false))),
    Omitted=cb_context:set_req_data(C,j([{<<"name">>,<<"Unrelated">>}])),
    {ok,Kept}=cb_account_call_forward_confirmation:prepare(?ACCOUNT,Omitted),
    ?assertEqual(<<"he-il">>,kzd_accounts:call_forward_confirmation_language(cb_context:req_data(Kept))),
    Raw=cb_context:store(cb_context:set_req_data(C,account(<<"he-il">>)),cfwd_confirmation_request,j([{?FIELD,j([{<<"language">>,null}])}])),
    {ok,Cleared}=cb_account_call_forward_confirmation:prepare(?ACCOUNT,Raw),
    ?assertEqual(undefined,kz_json:get_value(?FIELD,cb_context:req_data(Cleared))).

readiness_failure() ->
    put(bad_media,true), C=context(true,j([{<<"language">>,<<"ar-sa">>}])),
    {error,Failed}=cb_account_call_forward_confirmation:prepare(?ACCOUNT,C),
    ?assertEqual(503,cb_context:resp_error_code(Failed)),
    ?assertEqual(undefined,get(locale)).

readiness_bytes() ->
    lists:foreach(fun({L,_,_,_,_,_,_}) ->
        ?assert(kz_call_forward_confirmation:ready(L)),
        ?assertMatch({ok,_},cb_account_call_forward_confirmation:prepare(?ACCOUNT,context(true,j([{<<"language">>,L}])))),
        put(bad_bytes,true),
        ?assertNot(kz_call_forward_confirmation:ready(L)),
        {error,Failed}=cb_account_call_forward_confirmation:prepare(?ACCOUNT,context(true,j([{<<"language">>,L}]))),
        ?assertEqual(503,cb_context:resp_error_code(Failed)),
        erase(bad_bytes)
    end,kz_call_forward_confirmation:assets()).

j(P) -> kz_json:from_list(P).
