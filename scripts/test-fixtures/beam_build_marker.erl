%%% SPDX-License-Identifier: MPL-2.0
-module(beam_build_marker).
-export([mode/0]).
-ifdef(TEST).
mode() -> test.
-else.
mode() -> production.
-endif.
