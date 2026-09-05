%%% SPDX-License-Identifier: MPL-2.0
-module(ecallmgr_route_progress_tests).
-include_lib("eunit/include/eunit.hrl").
-include_lib("xmerl/include/xmerl.hrl").

route_progress_test_() ->
    {setup, fun setup/0, fun cleanup/1,
     [fun park_rings_as_first_normal_action/0
     ,fun bridge_bootstrap_is_executable_and_continues/0
     ,fun bridge_rings_before_both_attempts/0
     ,fun ignore_progress_omits_automatic_ringing/0
     ,fun explicit_prepark_ring_is_preserved/0
     ,fun explicit_prepark_answer_remains_after_progress/0
     ,fun bridge_failure_response_remains_last/0
     ,fun error_response_does_not_gain_ringing/0
     ]}.

setup() ->
    ok = meck:new(kapps_config, [no_link]),
    meck:expect(kapps_config, get,
                fun(<<"ecallmgr">>, <<"default_ringback">>, Default) -> Default end),
    meck:expect(kapps_config, is_true,
                fun(<<"ecallmgr">>, <<"should_detect_inband_dtmf">>, Default) -> Default end),
    meck:expect(kapps_config, get_ne_binary,
                fun(<<"ecallmgr">>, <<"freeswitch_context">>, Default) -> Default end),
    ok = meck:new(ecallmgr_util, [passthrough, no_link]),
    meck:expect(ecallmgr_util, build_channel,
                fun(Route) -> {ok, kz_json:get_value(<<"Route">>, Route)} end).

cleanup(_) ->
    meck:unload(ecallmgr_util),
    meck:unload(kapps_config).

xml(Method, Extra) ->
    Context = #{payload => kz_json:new(), control_q => <<"test-control">>,
                control_p => self(), fetch_id => <<"test-fetch">>},
    Routes = [kz_json:from_list([{<<"Route">>, Route}])
              || Route <- [<<"loopback/first">>, <<"loopback/second">>]],
    Response = kz_json:from_list([{<<"Method">>, Method}, {<<"Routes">>, Routes},
                                  {<<"Context">>, <<"test-context">>},
                                  {<<"App-Name">>, <<"test-app">>},
                                  {<<"Node">>, <<"test-node">>},
                                  {<<"Server-ID">>, <<"test-server">>} | Extra]),
    {ok, RawXml} = ecallmgr_fs_xml:route_resp_xml(dialplan, Response, Context),
    {Xml, []} = xmerl_scan:string(binary_to_list(iolist_to_binary(RawXml)), [{quiet, true}]),
    Xml.

%% xmerl's descendant-axis enumeration is not execution/document order for
%% nested conditions. Walk the exported tree in source order for sequencing.
actions(Element=#xmlElement{name=action}) -> [Element];
actions(#xmlElement{content=Children}) -> lists:flatmap(fun actions/1, Children);
actions(_) -> [].
app(Element) -> attr(application, Element).
attr(Name, #xmlElement{attributes=Attributes}) ->
    case [Value || #xmlAttribute{name=Key, value=Value} <- Attributes, Key =:= Name] of
        [] -> undefined;
        [Value] -> Value
    end.
apps(Xml) -> [app(Action) || Action <- actions(Xml)].
ring_actions(Xml) -> [Action || Action <- actions(Xml), app(Action) =:= "ring_ready"].
normal_ring(Xml, Count) ->
    Rings = ring_actions(Xml),
    ?assertEqual(Count, length(Rings)),
    [?assertNotEqual("true", attr(inline, Ring)) || Ring <- Rings].

park_rings_as_first_normal_action() ->
    Xml = xml(<<"park">>, []),
    normal_ring(Xml, 1),
    ?assertEqual("ring_ready", hd(apps(Xml))),
    ?assertEqual("park", lists:last(apps(Xml))),
    ?assertEqual(1, length(xmerl_xpath:string("//extension[@name='park']/condition/action[@application='ring_ready']", Xml))),
    ?assertEqual([], [App || App <- apps(Xml), lists:member(App, ["answer", "pre_answer"])]).

bridge_bootstrap_is_executable_and_continues() ->
    Xml = xml(<<"bridge">>, []),
    [Context] = xmerl_xpath:string("//context", Xml),
    Children = [Child || Child=#xmlElement{} <- Context#xmlElement.content],
    ?assert(lists:all(fun(#xmlElement{name=Name}) -> Name =:= extension end, Children)),
    [Bootstrap | _] = Children,
    ?assertEqual("true", attr(continue, Bootstrap)),
    ?assertEqual(1, length(xmerl_xpath:string("condition/action[@application='ring_ready']", Bootstrap))),
    ?assertEqual(1, length(xmerl_xpath:string("condition/action[@application='kz_multiset_encoded']", Bootstrap))),
    ?assertEqual([], xmerl_xpath:string("//context/action | //context/condition", Xml)).

bridge_rings_before_both_attempts() ->
    Xml = xml(<<"bridge">>, []),
    normal_ring(Xml, 1),
    Apps = apps(Xml),
    ?assertEqual("ring_ready", hd(Apps)),
    ?assertEqual(2, length([App || App <- Apps, App =:= "bridge"])),
    Bridges = [attr(data, Action) || Action <- actions(Xml), app(Action) =:= "bridge"],
    ?assert(string:find(hd(Bridges), "loopback/first") =/= nomatch),
    ?assert(string:find(lists:last(Bridges), "loopback/second") =/= nomatch).

ignore_progress_omits_automatic_ringing() ->
    lists:foreach(fun(Method) ->
        Xml = xml(Method, [{<<"Ignore-Progress">>, true}]),
        normal_ring(Xml, 0),
        ?assertEqual([], [App || App <- apps(Xml), lists:member(App, ["answer", "pre_answer"])])
    end, [<<"park">>, <<"bridge">>]).

explicit_prepark_ring_is_preserved() ->
    lists:foreach(fun(Ignore) ->
        Xml = xml(<<"park">>, [{<<"Ignore-Progress">>, Ignore}, {<<"Pre-Park">>, <<"ring_ready">>}]),
        normal_ring(Xml, 1),
        ?assertEqual("park", lists:last(apps(Xml)))
    end, [true, false]).

explicit_prepark_answer_remains_after_progress() ->
    Xml = xml(<<"park">>, [{<<"Pre-Park">>, <<"answer">>}]),
    normal_ring(Xml, 1),
    ?assertEqual("ring_ready", hd(apps(Xml))),
    ?assertEqual(1, length([App || App <- apps(Xml), App =:= "answer"])),
    ?assertEqual("park", lists:last(apps(Xml))),
    Ignored = xml(<<"park">>, [{<<"Ignore-Progress">>, true}, {<<"Pre-Park">>, <<"answer">>}]),
    normal_ring(Ignored, 0),
    ?assertEqual(1, length([App || App <- apps(Ignored), App =:= "answer"])).

bridge_failure_response_remains_last() ->
    Xml = xml(<<"bridge">>, []),
    Extensions = xmerl_xpath:string("//context/extension", Xml),
    Failure = lists:last(Extensions),
    ?assertEqual("failed_bridge", attr(name, Failure)),
    ?assertEqual("false", attr(continue, Failure)),
    [Respond] = xmerl_xpath:string("condition/action", Failure),
    ?assertEqual("respond", app(Respond)),
    ?assertEqual("${bridge_hangup_cause}", attr(data, Respond)).

error_response_does_not_gain_ringing() ->
    Xml = xml(<<"error">>, [{<<"Route-Error-Code">>, <<"404">>},
                             {<<"Route-Error-Message">>, <<"Not Found">>}]),
    normal_ring(Xml, 0),
    ?assertEqual("respond", lists:last(apps(Xml))).
