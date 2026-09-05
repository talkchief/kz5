-module(ecallmgr_bridge_compatibility_tests).
-include_lib("eunit/include/eunit.hrl").
-define(UUID, <<"0123456789abcdef0123456789abcdef">>).

correlation_is_set_once_immediately_before_bridge_test() ->
    Vars = <<"<call_timeout=20,originate_timeout=20,kz-endpoint-runtime-context='{\"a\":1,\"b\":[2,3]}'>">>,
    Dial = <<"[^^!leg_timeout=20!presence_id=1002@test.invalid]kz/device@account">>,
    ?assertEqual([{"application",<<"kz_multiset ^^!app_uuid=",?UUID/binary,"!app_uuid_name=bridge">>},
                  {"application",<<"kz_bridge ",Vars/binary,Dial/binary>>}],
                 ecallmgr_fs_bridge:bridge_commands(<<"kz_bridge">>,?UUID,Vars,Dial)).

no_uuid_does_not_set_or_invent_correlation_test() ->
    ?assertEqual([{"application",<<"kz_bridge <a=1>[b=2]kz/d@a">>}],
                 ecallmgr_fs_bridge:bridge_commands(<<"kz_bridge">>,undefined,"<a=1>",<<"[b=2]kz/d@a">>)).

uuid_delimiter_injection_is_rejected_test() ->
    [ ?assertError(invalid_bridge_application_uuid,
                   ecallmgr_fs_bridge:bridge_commands(<<"kz_bridge">>,Id,[],<<"kz/d@a">>))
      || Id <- [<<>>,<<"not-a-uuid">>,<<?UUID/binary,"!app_uuid_name=evil">>,
                <<?UUID/binary,"\n">>,<<?UUID/binary,"\r\napplication=hangup">>,<<"/^[bad]">>] ].

standard_hyphenated_uuid_is_supported_test() ->
    Id = <<"01234567-89ab-cdef-0123-456789abcdef">>,
    [{"application",Set},{"application",_}]=ecallmgr_fs_bridge:bridge_commands(<<"kz_bridge">>,Id,[],<<"kz/d@a">>),
    ?assertEqual(<<"kz_multiset ^^!app_uuid=",Id/binary,"!app_uuid_name=bridge">>,Set).

empty_dialstring_cannot_publish_fake_bridge_test() ->
    ?assertError(empty_bridge_dialstring,ecallmgr_fs_bridge:bridge_commands(<<"kz_bridge">>,?UUID,"<a=1>",<<>>)).

multiple_endpoint_separator_is_preserved_test() ->
    Dial = <<"[a='1,2']kz/one@account,[a='3,4']kz/two@account">>,
    [{"application",_},{"application",Bridge}]=ecallmgr_fs_bridge:bridge_commands(<<"kz_bridge">>,?UUID,[],Dial),
    ?assertEqual(<<"kz_bridge ",Dial/binary>>,Bridge).
