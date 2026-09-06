%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2026 2600Hz
%%% @doc Queue pre-connect announcement regression tests.
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%-----------------------------------------------------------------------------
-module(acdc_queue_fsm_tests).

-include_lib("eunit/include/eunit.hrl").

-define(ACCOUNT_ID, <<"00000000000000000000000000000001">>).

announcement_media_test_() ->
    [{"account media IDs resolve in the member account"
     ,?_assertEqual({'play', <<"/", ?ACCOUNT_ID/binary, "/queue-greeting">>}
                   ,acdc_queue_fsm:announcement_media('false', <<"queue-greeting">>, ?ACCOUNT_ID))
     }
    ,{"system media URIs are preserved"
     ,?_assertEqual({'play', <<"system_media/queue-greeting">>}
                   ,acdc_queue_fsm:announcement_media(
                      'false', <<"system_media/queue-greeting">>, ?ACCOUNT_ID))
     }
    ,{"stream URIs are preserved"
     ,?_assertEqual({'play', <<"local_stream://default">>}
                   ,acdc_queue_fsm:announcement_media(
                      'false', <<"local_stream://default">>, ?ACCOUNT_ID))
     }
    ,{"an absent announcement is skipped"
     ,?_assertEqual('skip'
                   ,acdc_queue_fsm:announcement_media('false', 'undefined', ?ACCOUNT_ID))
     }
    ,{"agent retries never repeat an announcement"
     ,?_assertEqual('skip'
                   ,acdc_queue_fsm:announcement_media('true', <<"queue-greeting">>, ?ACCOUNT_ID))
     }
    ].

announcement_event_id_test_() ->
    NoopId = <<"announcement-noop">>,
    [{"the matching noop completion supplies the barrier ID"
     ,?_assertEqual(NoopId
                   ,acdc_queue_fsm:announcement_event_id(
                      kz_json:from_list([{<<"Application-Name">>, <<"noop">>}
                                        ,{<<"Application-Response">>, NoopId}
                                        ])))
     }
    ,{"unrelated execute-complete events cannot release the barrier"
     ,?_assertEqual('undefined'
                   ,acdc_queue_fsm:announcement_event_id(
                      kz_json:from_list([{<<"Application-Name">>, <<"play">>}
                                        ,{<<"Application-Response">>, NoopId}
                                        ])))
     }
    ].

announcement_command_order_test() ->
    TestPid = self(),
    Publisher = fun(Command, _Call) -> TestPid ! {'command', Command}, 'ok' end,
    Call0 = kapps_call:set_call_id(<<"announcement-call">>, kapps_call:new()),
    Call = kapps_call:set_custom_publish_function(Publisher, Call0),
    NoopId = acdc_queue_fsm:start_announcement(<<"system_media/queue-greeting">>, Call),
    PlayQueue = receive {'command', PlayCommand} -> PlayCommand after 100 -> timeout end,
    ?assertEqual(<<"queue">>, props:get_value(<<"Application-Name">>, PlayQueue)),
    ?assertEqual(<<"flush">>, props:get_value(<<"Insert-At">>, PlayQueue)),
    Commands = props:get_value(<<"Commands">>, PlayQueue),
    [TerminalNoop, Play] = Commands,
    ?assertEqual(NoopId, kz_json:get_value(<<"Msg-ID">>, TerminalNoop)),
    ?assertEqual(<<"play">>, kz_json:get_value(<<"Application-Name">>, Play)),
    ?assertEqual(<<"system_media/queue-greeting">>, kz_json:get_value(<<"Media-Name">>, Play)),
    receive
        {'command', _UnexpectedSecondPublish} -> ?assert(false)
    after 20 ->
        ok
    end.
