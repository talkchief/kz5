#!/usr/bin/env bash
# Private production compilation and exact terminal-event regressions.
set -Eeuo pipefail
umask 077
terminal_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
[[ $# == 0 ]] || exit 2
[[ $(readlink /proc/self/ns/net) != "$(readlink /proc/1/ns/net)" ]] || exit 2
terminal_output=$(mktemp -d /tmp/kazoo-acdc-terminal.XXXXXX)
cd "$terminal_root"
export ERL_LIBS="$terminal_root/deps:$terminal_root/core:$terminal_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
terminal_inputs=(applications/acdc/src/acdc_agent_fsm.erl
    applications/acdc/src/acdc_agent_listener.erl applications/acdc/src/acdc_agent_handler.erl
    scripts/erlang-tests/acdc_listener_maintenance_tests.erl
    scripts/erlang-tests/acdc_listener_terminal_tests.erl scripts/test-acdc-listener-terminal.sh)
sha256sum "${terminal_inputs[@]}" > "$terminal_output/source.sha256"
erlc -Werror +warn_missing_spec +debug_info -I applications/acdc/src -I applications/acdc/include \
    -pa deps/lager/ebin '+{parse_transform,lager_transform}' -o "$terminal_output" \
    applications/acdc/src/acdc_agent_fsm.erl applications/acdc/src/acdc_agent_listener.erl \
    applications/acdc/src/acdc_agent_handler.erl
erlc -Werror +debug_info -I applications/acdc/src -I applications/acdc/include -o "$terminal_output" \
    scripts/erlang-tests/acdc_listener_maintenance_tests.erl scripts/erlang-tests/acdc_listener_terminal_tests.erl
erl -pa "$terminal_output" -noshell -eval '
    case eunit:test(acdc_listener_terminal_tests,[verbose]) of ok -> halt(0); _ -> halt(1) end.'
sha256sum -c "$terminal_output/source.sha256"
printf 'PASS: production terminal-event regressions; evidence %s\n' "$terminal_output"
