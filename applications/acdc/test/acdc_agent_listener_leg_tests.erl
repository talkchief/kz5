%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2026, TalkChief
%%% @doc Stranded agent leg reconciliation in acdc_agent_listener.
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at http://mozilla.org/MPL/2.0/.
%%% @end
%%%-----------------------------------------------------------------------------
-module(acdc_agent_listener_leg_tests).

-include_lib("eunit/include/eunit.hrl").

-define(LEG, <<"agent-leg-1">>).

%% First sight starts the clock; a leg is due only after the minimum age and
%% never while a call is in progress on the listener.
legs_due_test_() ->
    {Due0, Seen0} = acdc_agent_listener:legs_due([?LEG], #{}, 1000, 'false'),
    {Due1, _} = acdc_agent_listener:legs_due([?LEG], Seen0, 1000 + 29999, 'false'),
    {Due2, _} = acdc_agent_listener:legs_due([?LEG], Seen0, 1000 + 30000, 'false'),
    {Due3, _} = acdc_agent_listener:legs_due([?LEG], Seen0, 1000 + 90000, 'true'),
    {_, Seen4} = acdc_agent_listener:legs_due([], Seen0, 5000, 'false'),
    Many = [<<"leg-", (integer_to_binary(N))/binary>> || N <- lists:seq(1, 9)],
    {_, SeenMany} = acdc_agent_listener:legs_due(Many, #{}, 0, 'false'),
    {DueMany, _} = acdc_agent_listener:legs_due(Many, SeenMany, 60000, 'false'),
    [?_assertEqual([], Due0)
    ,?_assertEqual(#{?LEG => 1000}, Seen0)
    ,?_assertEqual([], Due1)
    ,?_assertEqual([?LEG], Due2)
    ,?_assertEqual([], Due3)
     %% A leg that is no longer tracked is forgotten, so a reused id starts afresh.
    ,?_assertEqual(#{}, Seen4)
    ,?_assertEqual(5, length(DueMany))
    ].

%% Only complete evidence of termination retires a leg.
leg_gone_test_() ->
    Evidence = fun(Complete, Channels) -> {'ok', #{'complete' => Complete, 'channels' => Channels}} end,
    Terminated = #{'call_id' => ?LEG, 'state' => 'terminated', 'responders' => [<<"ecallmgr@a">>]},
    [?_assert(acdc_agent_listener:leg_gone(Evidence('true', [Terminated]), ?LEG))
    ,?_assertNot(acdc_agent_listener:leg_gone(Evidence('false', [Terminated]), ?LEG))
    ,?_assertNot(acdc_agent_listener:leg_gone(Evidence('true', [Terminated#{'responders' => []}]), ?LEG))
    ,?_assertNot(acdc_agent_listener:leg_gone(Evidence('true', [Terminated#{'state' => 'active'}]), ?LEG))
    ,?_assertNot(acdc_agent_listener:leg_gone(Evidence('true', [Terminated#{'call_id' => <<"another-leg">>}]), ?LEG))
    ,?_assertNot(acdc_agent_listener:leg_gone(Evidence('true', []), ?LEG))
    ,?_assertNot(acdc_agent_listener:leg_gone({'error', 'unknown'}, ?LEG))
    ].
