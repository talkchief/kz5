#!/usr/bin/env bash
# Read-only sync-response probe tests; private beams and no live AMQP use.
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo-acdc-callback-agent-probe-test.XXXXXX)
cleanup() {
    rm -f -- "$test_dir/kapi_acdc_agent.beam" \
        "$test_dir/kapi_acdc_queue.beam" \
        "$test_dir/acdc_callback_agent_probe.beam" \
        "$test_dir/acdc_callback_agent_probe_tests.beam"
    rmdir -- "$test_dir"
}
trap cleanup EXIT
cd "$project_root"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
erlc -DTEST -Werror +warn_missing_spec -I applications/acdc/src -I applications/acdc/include \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' -o "$test_dir" \
    applications/acdc/src/kapi_acdc_agent.erl \
    applications/acdc/src/kapi_acdc_queue.erl \
    applications/acdc/src/acdc_callback_agent_probe.erl
erlc -Werror -o "$test_dir" scripts/erlang-tests/acdc_callback_agent_probe_tests.erl
erl -pa "$test_dir" -noshell \
    -eval 'case eunit:test(acdc_callback_agent_probe_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
