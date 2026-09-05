-module(acdc_gemini_runtime_tests).
-include_lib("eunit/include/eunit.hrl").
-define(ACCOUNT, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).

legacy_account_aliases_and_explicit_presence_test() -> with_store(fun() ->
    Legacy = <<"queue-in_the_queue">>, Canonical = <<"acdc-queue-in_the_queue">>,
    ?assertMatch({gemini,_},acdc_gemini_prompts:default_alias(Legacy,Canonical,<<"en-us">>,?ACCOUNT,absent)),
    meck:expect(kz_datamgr,open_cache_doc,fun(<<"system_media">>,Id) -> acdc_gemini_prompts_tests:read(Id);
        (_,Legacy0) when Legacy0=:=Legacy -> {ok,{[]}}; (_,_) -> {error,not_found} end),
    ?assertEqual({custom,Legacy},acdc_gemini_prompts:default_alias(Legacy,Canonical,<<"en-us">>,?ACCOUNT,absent)),
    meck:expect(kz_datamgr,open_cache_doc,fun(_,_) -> {error,timeout} end),
    ?assertEqual({error,account_override_unavailable},acdc_gemini_prompts:default_alias(Legacy,Canonical,<<"en-us">>,?ACCOUNT,absent)),
    ?assertEqual({custom,Legacy},acdc_gemini_prompts:default_alias(Legacy,Canonical,<<"en-us">>,?ACCOUNT,{configured,Legacy})),
    ?assertEqual(absent,acdc_gemini_prompts:selection(<<"x">>,{[]})),
    ?assertEqual({configured,null},acdc_gemini_prompts:selection(<<"x">>,{[{<<"x">>,null}]})),
    ?assertEqual({error,invalid_explicit_media},acdc_gemini_prompts:default_alias(Legacy,Canonical,<<"en-us">>,?ACCOUNT,{configured,null}))
end).

complete_callback_contract_and_pure_numeric_readback_test() -> with_store(fun() ->
    lists:foreach(fun(L) ->
        {ok,C}=case L of
            <<"en-us">> -> acdc_gemini_prompts:callback(<<"6">>,false,{[]},L,?ACCOUNT);
            _ ->
                ?assertEqual({error,auxiliary_callback_media_unverified},acdc_gemini_prompts:callback(<<"6">>,false,{[]},L,?ACCOUNT)),
                {ok,English}=acdc_gemini_prompts:callback(<<"6">>,false,{[]},<<"en-us">>,?ACCOUNT),
                {ok,Digits}=acdc_gemini_prompts:telephone(<<"0123456789">>,L,?ACCOUNT),
                {ok,English#{readback:=maps:from_list(lists:zip("0123456789",Digits)),non_gemini_numeric_dependency:=false}}
        end,
        ?assertEqual(6,map_size(maps:get(media,C))),
        lists:foreach(fun(P) -> ?assertMatch({_,_},binary:match(P,<<"-gemini-sulafat-">>)) end,maps:values(maps:get(media,C))),
        Count=meck:num_calls(kz_datamgr,open_cache_doc,'_'),
        {ok,Prompts}=acdc_gemini_prompts:callback_readback(<<"00129">>,C),
        ?assertEqual(Count,meck:num_calls(kz_datamgr,open_cache_doc,'_')),
        case L of
            <<"en-us">> -> ?assertEqual([{say,<<"00129">>,<<"telephone_number">>}],Prompts), ?assert(maps:get(non_gemini_numeric_dependency,C));
            _ -> ?assertEqual(5,length(Prompts)),?assertEqual(hd(Prompts),lists:nth(2,Prompts)),
                 ?assertNot(maps:get(non_gemini_numeric_dependency,C)),
                 ?assertEqual([], [P || {say,_,_}=P <- Prompts])
        end,
        lists:foreach(fun(D) -> ?assertEqual({error,invalid_readback},acdc_gemini_prompts:callback_readback(D,C)) end,
                      [undefined,<<>>,<<"+12">>,<<"1234567890123456">>])
    end,[<<"en-us">>,<<"ar-sa">>,<<"he-il">>]),
    lists:foreach(fun(L) -> ?assertEqual({error,numeric_readback_unverified},acdc_gemini_prompts:callback(<<"6">>,false,{[]},L,?ACCOUNT)) end,
                  [<<"fr-fr">>,<<"es-es">>,<<"de-de">>]),
    ?assertEqual({error,invalid_entry_key},acdc_gemini_prompts:callback(<<"66">>,false,{[]},<<"en-us">>,?ACCOUNT))
end).

missing_returned_or_any_digit_disables_callback_and_offer_test() -> with_store(fun() ->
    lists:foreach(fun(Missing) ->
        meck:expect(kz_datamgr,open_cache_doc,fun(<<"system_media">>,Id) ->
            case binary:match(Id,Missing) of nomatch -> acdc_gemini_prompts_tests:read(Id); _ -> {error,not_found} end;
            (_,_) -> {error,not_found} end),
        ?assertMatch({error,_},acdc_gemini_prompts:callback(<<"6">>,false,{[]},<<"he-il">>,?ACCOUNT)),
        case Missing of
            <<"acdc-callback-returned-confirmation-">> ->
                ?assertMatch({error,_},acdc_gemini_prompts:callback(<<"6">>,false,{[]},<<"en-us">>,?ACCOUNT));
            _ -> ?assertEqual({error,gemini_digits_unavailable},acdc_gemini_prompts:telephone(<<"0123456789">>,<<"he-il">>,?ACCOUNT))
        end,
        C=acdc_announcements:resolve_media(acdc_announcements:get_config(props(false,false,true)),call(<<"he-il">>)),
        ?assertEqual([],acdc_announcements:callback_offer_prompts(<<"he-il">>,C)),
        ?assertEqual(undefined,cf_acdc_member:callback_config(queue(true),call(<<"he-il">>)))
    end,[<<"acdc-callback-returned-confirmation-">>,<<"acdc-number-9-">>])
end).

position_default_and_customer_recordings_preserved_test() -> with_store(fun() ->
    Base=acdc_announcements:get_config(props(true,false,false)),
    C=acdc_announcements:resolve_media(Base,call(<<"en-us">>)),
    [{prompt,Combined,_,_},{say,<<"1">>,<<"number">>}]=acdc_announcements:position_prompts(1,<<"en-us">>,C),
    ?assertMatch({0,_},binary:match(Combined,<<"acdc-queue-your-current-position-is-gemini-">>)),
    Custom=Base#{configured_announcements_media := [{<<"you_are_at_position">>,<<"queue-you_are_at_position">>}]},
    CC=acdc_announcements:resolve_media(Custom,call(<<"en-us">>)),
    ?assertMatch([{prompt,<<"queue-you_are_at_position">>,_,_},{say,_,_},{prompt,_,_,_}],acdc_announcements:position_prompts(3,<<"en-us">>,CC)),
    meck:expect(kz_datamgr,open_cache_doc,fun(<<"system_media">>,Id) -> acdc_gemini_prompts_tests:read(Id);
        (_,<<"queue-in_the_queue">>) -> {ok,{[]}}; (_,_) -> {error,not_found} end),
    AC=acdc_announcements:resolve_media(Base,call(<<"en-us">>)),
    ?assertMatch([{prompt,_,_,_},{say,_,_},{prompt,<<"queue-in_the_queue">>,_,_}],acdc_announcements:position_prompts(2,<<"en-us">>,AC)),
    meck:expect(kz_datamgr,open_cache_doc,fun(<<"system_media">>,Id) -> acdc_gemini_prompts_tests:read(Id); (_,_) -> {error,not_found} end),
    lists:foreach(fun(L) ->
        Foreign=acdc_announcements:resolve_media(Base,call(L)),
        ?assertEqual([],acdc_announcements:position_prompts(1,L,Foreign))
    end,[<<"ar-sa">>,<<"he-il">>,<<"fr-fr">>,<<"es-es">>])
end).

legacy_custom_nonenglish_paths_remain_distinct_test() -> with_store(fun() ->
    Media=[{K,<<"customer-",K/binary>>} || K <- [<<"offer">>,<<"menu">>,<<"number_readback">>,<<"confirmation">>,<<"success">>]],
    lists:foreach(fun(L) ->
        {ok,C}=acdc_gemini_prompts:callback(<<"6">>,false,Media,L,?ACCOUNT),
        ?assert(maps:get(legacy_custom_media,C)),?assert(maps:get(non_gemini_numeric_dependency,C)),
        ?assertEqual(5,map_size(maps:get(media,C))),
        ?assertEqual({ok,[{say,<<"0123">>,<<"telephone_number">>}]},acdc_gemini_prompts:callback_readback(<<"0123">>,C)),
        Base=acdc_announcements:get_config(props(true,false,false)),
        Custom=Base#{configured_announcements_media := [{<<"you_are_at_position">>,<<"customer-prefix">>}]},
        Resolved=acdc_announcements:resolve_media(Custom,call(L)),
        ?assert(maps:get(non_gemini_position_dependency,Resolved)),
        ?assertMatch([{prompt,<<"customer-prefix">>,_,_},{say,_,_},{prompt,_,_,_}],acdc_announcements:position_prompts(3,L,Resolved))
    end,[<<"ar-sa">>,<<"he-il">>,<<"fr-fr">>,<<"es-es">>]),
    meck:expect(kz_datamgr,open_cache_doc,fun(_,_) -> error(unexpected_io) end),
    ?assertMatch({ok,#{legacy_custom_media := true}},acdc_gemini_prompts:callback(<<"6">>,true,Media,<<"xx-custom">>,?ACCOUNT))
end).

real_returned_prompt_path_is_idempotent_test() ->
    ok=meck:new(kz_datamgr,[passthrough,no_link,non_strict]),
    ok=meck:new(kapps_config,[passthrough,no_link]),
    meck:expect(kz_datamgr,open_cache_doc,fun(<<"system_media">>,Id) -> acdc_gemini_prompts_tests:read(Id); (_,_) -> {error,not_found} end),
    meck:expect(kz_datamgr,get_results,fun(_,_,_) -> {ok,[]} end),
    meck:expect(kz_datamgr,get_uuid,fun() -> <<"offline-noop">> end),
    meck:expect(kapps_config,get_is_true,fun(_,<<"support_account_overrides">>,_) -> false end),
    try
        Call=kapps_call:set_custom_publish_function(fun(Commands,_) -> put(real_commands,Commands),ok end,call(<<"en-us">>)),
        Queue=kz_json:set_value([<<"announcements">>,<<"language">>],<<"HE_IL">>,queue(true)),
        {ok,URI}=acdc_callback_caller:confirmation_prompt(Queue,Call),
        ?assertMatch(<<"prompt://system_media/",_/binary>>,URI),
        ?assertMatch({_,_},binary:match(URI,<<"/he-il">>)),
        ?assertEqual(URI,kapps_call:get_prompt(Call,URI)),
        ?assertEqual(URI,kapps_call:get_prompt(Call,URI,<<"fr-fr">>)),
        ?assertEqual(URI,kz_media_util:get_prompt(URI,<<"es-es">>,?ACCOUNT)),
        ?assertEqual(<<"offline-noop">>,kapps_call_command:prompt(URI,Call)),
        Commands=proplists:get_value(<<"Commands">>,get(real_commands)),
        [Play]=[P || P <- Commands,kz_json:get_value(<<"Application-Name">>,P)=:=<<"play">>],
        ?assertEqual(URI,kz_json:get_value(<<"Media-Name">>,Play)),
        ?assertEqual(<<"gemini-test">>,kz_json:get_value(<<"Call-ID">>,Play))
    after meck:unload(kz_datamgr),meck:unload(kapps_config),erase(real_commands) end.

fixed_wait_all_languages_once_no_tick_queries_test() -> with_store(fun() ->
    lists:foreach(fun(L) ->
        C=acdc_announcements:resolve_media(acdc_announcements:get_config(props(false,true,false)),call(L)),
        Count=meck:num_calls(kz_datamgr,open_cache_doc,'_'),
        lists:foreach(fun(T) ->
            {P,T}=acdc_announcements:wait_time_prompts(T,0,L,C),
            ?assert(length(P)>=2),
            lists:foreach(fun({prompt,Id,_,_}) -> ?assertMatch({_,_},binary:match(Id,<<"-gemini-sulafat-">>)) end,P)
        end,[0,61,301,601,901,1801,2701,3601]),
        ?assertEqual(Count,meck:num_calls(kz_datamgr,open_cache_doc,'_')),
        ?assertEqual({[],undefined},acdc_announcements:wait_time_prompts(undefined,undefined,L,C))
    end,[<<"en-us">>,<<"ar-sa">>,<<"he-il">>,<<"fr-fr">>,<<"es-es">>])
end).

menu_offer_toggle_and_returned_confirmation_test() -> with_store(fun() ->
    Queue=queue(true), Call=call(<<"en-us">>),
    ?assertMatch(#{entry_key := <<"6">>},cf_acdc_member:callback_config(Queue,Call)),
    ?assertEqual(undefined,cf_acdc_member:callback_config(queue(false),Call)),
    Off=acdc_announcements:get_config([{<<"callback">>,[{<<"enabled">>,true},{<<"announcement">>,[{<<"enabled">>,false}]}]}]),
    OC=acdc_announcements:resolve_media(Off,Call),
    ?assertEqual([],acdc_announcements:callback_offer_prompts(<<"en-us">>,OC)),
    lists:foreach(fun(L) ->
        {ok,Id}=acdc_callback_caller:confirmation_prompt(Queue,call(L)),
        ?assertMatch({_,_},binary:match(Id,<<"-gemini-sulafat-">>))
    end,[<<"en-us">>,<<"ar-sa">>,<<"he-il">>,<<"fr-fr">>,<<"es-es">>]),
    Custom=kz_json:set_value([<<"callback">>,<<"media">>,<<"returned_confirmation">>],<<"account-custom">>,Queue),
    ?assertEqual({ok,<<"account-custom">>},acdc_callback_caller:confirmation_prompt(Custom,call(<<"fr-fr">>))),
    Invalid=kz_json:set_value([<<"callback">>,<<"media">>,<<"returned_confirmation">>],<<"bad\nmedia">>,Queue),
    ?assertEqual({error,missing_localized_media},acdc_callback_caller:confirmation_prompt(Invalid,Call))
end).

no_staged_language_dependency_test() ->
    ?assertEqual(non_existing,code:which(acdc_language)),
    lists:foreach(fun(M) ->
        {ok,{M,[{imports,I}]}}=beam_lib:chunks(code:which(M),[imports]),
        ?assertEqual([],[X || {D,_,_}=X <- I,D=:=acdc_language])
    end,[acdc_gemini_prompts,cf_acdc_member,acdc_announcements,acdc_callback_caller]).

queue_locale_reaches_actual_paths_without_identity_change_test() -> with_store(fun() ->
    Original=call(<<"he-il">>),
    Queue=kz_json:set_value([<<"announcements">>,<<"language">>],<<"EN_US">>,queue(true)),
    C=cf_acdc_member:callback_config(Queue,Original),
    ?assertEqual(<<"en-us">>,maps:get(language,C)),
    meck:expect(kapps_call,get_prompt,fun(C0,Prompt,Locale) ->
        ?assertEqual(Original,C0),
        ?assertEqual(<<"en-us">>,Locale),
        <<"prompt://system_media/",Prompt/binary,"/",Locale/binary>>
    end),
    Menu=cf_acdc_member:callback_media_path(menu,C,Original),
    ?assertMatch({_,_},binary:match(Menu,<<"/en-us">>)),
    {ok,Returned}=acdc_callback_caller:confirmation_prompt(Queue,Original),
    ?assertMatch({_,_},binary:match(Returned,<<"/en-us">>)),
    ?assertEqual(<<"he-il">>,kapps_call:language(Original)),
    ?assertEqual(?ACCOUNT,kapps_call:account_id(Original)),
    ?assertEqual(<<"gemini-test">>,kapps_call:call_id(Original))
end).

existing_scheduler_and_lifecycle_test_() ->
    {timeout,75,fun() ->
        ok=meck:new(acdc_gemini_prompts,[passthrough,no_link]),
        meck:expect(acdc_gemini_prompts,default_alias,fun(Legacy,_,_,_,_) -> {gemini,Legacy} end),
        meck:expect(acdc_gemini_prompts,default,fun(P,_,_,_) -> {gemini,P} end),
        meck:expect(acdc_gemini_prompts,callback,fun(Entry,_,_,_,_) -> {ok,#{media=>#{offer=><<"acdc-callback-offer-",Entry/binary>>}}} end),
        try
            acdc_callback_announcement_tests:configuration_defaults_and_bounds_test(),
            acdc_callback_announcement_tests:offer_switch_and_callback_disabled_are_independent_test(),
            acdc_callback_announcement_tests:independent_deadlines_and_combined_due_test(),
            acdc_callback_announcement_tests:late_wakeup_never_replays_missed_intervals_test(),
            acdc_callback_announcement_tests:disabled_clocks_never_spin_and_resume_resets_delays_test(),
            acdc_callback_announcement_tests:correlated_completion_and_terminal_events_test(),
            {timeout,_,Timer}=acdc_callback_announcement_tests:real_worker_timer_test_(), Timer(),
            {timeout,_,Lifecycle}=acdc_callback_announcement_tests:worker_failure_lifecycle_test_(), Lifecycle()
        after meck:unload(acdc_gemini_prompts) end
    end}.

existing_callback_protocol_test_() ->
    [fun cf_acdc_callback_integration_tests:register_request_is_minimal_and_protocol_valid_test/0,
     fun cf_acdc_callback_integration_tests:response_requires_full_scope_and_valid_wire_shape_test/0,
     cf_acdc_callback_integration_tests:alternate_entry_is_audible_without_replaying_between_digits_test_(),
     cf_acdc_callback_integration_tests:alternate_wrapper_preserves_invalid_digits_and_cancellation_test_(),
     cf_acdc_callback_integration_tests:alternate_wrapper_bounds_prompt_wait_and_observes_hangup_test_(),
     fun acdc_callback_caller_tests:cleanup_disposition_requires_positive_proof_test/0,
     fun acdc_callback_caller_tests:owner_loss_retains_uncertain_attempt_listener_test/0,
     fun acdc_callback_caller_tests:owner_protocol_messages_keep_lease_and_private_handles_test/0,
     fun acdc_callback_caller_tests:confirmation_events_are_fail_closed_test/0,
     fun acdc_callback_caller_tests:attempt_context_is_bound_to_original_member_test/0].

with_store(F) ->
    ok=meck:new(kz_datamgr,[passthrough,no_link]),
    ok=meck:new(kapps_call,[passthrough,no_link]),
    meck:expect(kapps_call,get_prompt,fun(_,P,_) -> P end),
    meck:expect(kz_datamgr,open_cache_doc,fun(<<"system_media">>,Id) -> acdc_gemini_prompts_tests:read(Id); (_,_) -> {error,not_found} end),
    meck:expect(kz_datamgr,get_results,fun(_,_,_) -> {ok,[]} end),
    try F() after meck:unload(kz_datamgr),meck:unload(kapps_call) end.
call(L) -> kapps_call:set_language(L,kapps_call:set_account_id(?ACCOUNT,kapps_call:set_call_id(<<"gemini-test">>,kapps_call:new()))).
queue(Enabled) -> kz_json:from_list([{<<"pvt_account_id">>,?ACCOUNT},{<<"callback">>,kz_json:from_list([{<<"enabled">>,Enabled}])}]).
props(Position,Wait,Callback) ->
    [{<<"position_announcements_enabled">>,Position},{<<"wait_time_announcements_enabled">>,Wait},
     {<<"callback">>,[{<<"enabled">>,Callback},{<<"entry_key">>,<<"6">>}]}].
