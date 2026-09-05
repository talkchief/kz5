#!/usr/bin/env bash
# Isolated source-level regression tests. No service, API or telephony mutation.
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo-acdc-strategies.XXXXXX)
cleanup() {
    find "$test_dir" -maxdepth 1 -type f -name '*.beam' -delete
    rmdir -- "$test_dir"
}
trap cleanup EXIT
cd "$project_root"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
erlc -DTEST -Werror +debug_info -I applications/acdc/src -I applications/acdc/include \
    -pa deps/lager/ebin '+{parse_transform,lager_transform}' -o "$test_dir" \
    applications/acdc/src/acdc_queue_strategy.erl applications/acdc/src/acdc_queue_manager.erl \
    applications/acdc/src/acdc_queue_fsm.erl applications/acdc/src/acdc_agent_fsm.erl
erlc -Werror -I applications/acdc/src -I applications/acdc/include -o "$test_dir" scripts/erlang-tests/acdc_queue_strategy_tests.erl
erl -pa "$test_dir" -noshell -eval 'case eunit:test(acdc_queue_strategy_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
