#!/usr/bin/env bash
# Private VM only: no live nodes, HTTP, AMQP, database or service writes.
set -Eeuo pipefail
queue_project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
queue_output=$(mktemp -d /tmp/kazoo-agent-queue-runtime-test.XXXXXX)
cleanup() {
    rm -f -- "$queue_output/cb_agents.beam" "$queue_output/cb_acdc_agent_queue.beam" \
        "$queue_output/acdc_agent_handler.beam" "$queue_output/acdc_agent_listener.beam" \
        "$queue_output/kapi_acdc_agent.beam" "$queue_output/acdc_agent_queue_runtime_tests.beam"
    rmdir -- "$queue_output"
}
trap cleanup EXIT
export ERL_LIBS="$queue_project/deps:$queue_project/core:$queue_project/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
cd "$queue_project"
erlc -Werror +debug_info -I applications/acdc/src -I applications/acdc/include \
    -pa deps/lager/ebin '+{parse_transform,lager_transform}' -o "$queue_output" \
    applications/acdc/src/cb_agents.erl applications/acdc/src/cb_acdc_agent_queue.erl \
    applications/acdc/src/acdc_agent_handler.erl applications/acdc/src/acdc_agent_listener.erl \
    applications/acdc/src/kapi_acdc_agent.erl
erlc -Werror +debug_info -o "$queue_output" scripts/erlang-tests/acdc_agent_queue_runtime_tests.erl
erl -pa "$queue_output" -noshell -eval \
    'case eunit:test(acdc_agent_queue_runtime_tests,[verbose]) of ok->halt(0);_->halt(1) end.'
