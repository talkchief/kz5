%%% Real production ETS lookup and play command selection, no live calls.
-module(ecallmgr_bridge_identity_tests).
-include_lib("eunit/include/eunit.hrl").
-include("ecallmgr.hrl").

bridge_identity_test_() ->
    [{Name, {timeout, 15, fun() -> check(Peer, Expected, CheckPlayback) end}} ||
        {Name, Peer, Expected, CheckPlayback} <-
        [{"self is not a bridged partner", self, false, false},
         {"empty legacy peer is not a bridge", <<>>, false, false},
         {"undefined peer stays unbridged", undefined, false, false},
         {"missing channel stays unbridged", missing, false, false},
         {"distinct nonempty peer remains bridged", <<"other-channel">>, true, false},
         {"self-referenced callback uses ordinary playback", self, false, true},
         {"empty peer uses ordinary playback", <<>>, false, true},
         {"real bridge retains broadcast to both legs", <<"other-channel">>, true, true}]].

check(Peer0, Expected, CheckPlayback) ->
    UUID = <<"isolated-returned-caller">>,
    Peer = case Peer0 of self -> UUID; _ -> Peer0 end,
    Table = ets:new(?CHANNELS_TBL, [named_table, set, {keypos, #channel.uuid}]),
    try
        case Peer of missing -> ok; _ -> ets:insert(Table, #channel{uuid=UUID, other_leg=Peer}) end,
        case CheckPlayback of
            false -> ?assertEqual(Expected, ecallmgr_fs_channel:is_bridged(UUID));
            true -> check_playback(UUID, Expected)
        end
    after ets:delete(Table) end.

check_playback(UUID, Bridged) ->
    ok = meck:new(ecallmgr_util, [non_strict, no_link]),
    try
        meck:expect(ecallmgr_util, media_path, fun(_, new, Id, _) when Id =:= UUID -> <<"/tmp/immutable-prompt.wav">> end),
        meck:expect(ecallmgr_util, process_fs_kv, fun(_, _, set) -> [] end),
        meck:expect(ecallmgr_util, fs_args_to_binary, fun([]) -> <<>> end),
        Request = kz_json:from_list([{<<"Application-Name">>, <<"play">>}, {<<"Call-ID">>, UUID},
            {<<"Media-Name">>, <<"/system_media/en-us/fixture-prompt">>}, {<<"Msg-ID">>, <<"fixture">>} |
            kz_api:default_headers(<<"call">>, <<"command">>, <<"bridge-test">>, <<"1">>)]),
        Apps = ecallmgr_call_command:fetch_dialplan(testnode, UUID, Request),
        Expected = case Bridged of
            false -> {<<"playback">>, <<"/tmp/immutable-prompt.wav">>};
            true -> {<<"broadcast">>, <<"'/tmp/immutable-prompt.wav' both">>}
        end,
        ?assert(lists:member(Expected, Apps))
    after meck:unload(ecallmgr_util) end.
