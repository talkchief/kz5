%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2017, Voxter Communications
%%% @doc
%%% @author Daniel Finke
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(acdc_announcements_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).
-export([maybe_start_announcements/3
        ,stop_announcements/1
        ]).

%% Supervisor callbacks
-export([init/1]).

-include("acdc.hrl").

-define(SERVER, ?MODULE).
%% The manager owns the initial PID. A restarted child would be untracked and
%% could escape menu/bridge cancellation, so per-call producers never restart.
-define(CHILDREN, [?WORKER_TYPE('acdc_announcements', 'temporary')]).

%%%=============================================================================
%%% API functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Starts the supervisor.
%% @end
%%------------------------------------------------------------------------------
-spec start_link() -> kz_types:sup_startchild_ret().
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%------------------------------------------------------------------------------
%% @doc Start one producer if position, wait-time, or callback-offer
%% announcements are enabled. Existing stop/resume lifecycle covers all three.
%%
%% @end
%%------------------------------------------------------------------------------
-spec maybe_start_announcements(pid(), kapps_call:call(), kz_term:proplist()) -> supervisor:startchild_ret() | 'false'.
maybe_start_announcements(Manager, Call, Props) ->
    Enabled = acdc_announcements:announcements_enabled(Props),
    Enabled
        andalso supervisor:start_child(?SERVER, [Manager, Call, Props]).

%%------------------------------------------------------------------------------
%% @doc Stop an announcements child process
%% @end
%%------------------------------------------------------------------------------
-spec stop_announcements(pid()) -> kz_types:sup_terminatechild_ret().
stop_announcements(Pid) ->
    supervisor:terminate_child(?SERVER, Pid).

%%%=============================================================================
%%% Supervisor callbacks
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Whenever a supervisor is started using `supervisor:start_link/[2,3]',
%% this function is called by the new process to find out about
%% restart strategy, maximum restart intensity, and child
%% specifications.
%%
%% @end
%%------------------------------------------------------------------------------
-spec init(list()) -> kz_types:sup_init_ret().
init([]) ->

    SupFlags = #{strategy => simple_one_for_one,
                 intensity => 1,
                 period => 5},

    {ok, {SupFlags, ?CHILDREN}}.

%%%=============================================================================
%%% Internal functions
%%%=============================================================================
