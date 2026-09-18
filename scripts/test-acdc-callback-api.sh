#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d /tmp/kazoo-acdc-callback-api.XXXXXX)
cleanup() {
    rm -f -- "$test_dir/src/cb_queues.erl" \
        "$test_dir/ebin/cb_queues.beam" \
        "$test_dir/ebin/cb_queues_callback_api_tests.beam"
    rmdir -- "$test_dir/src" "$test_dir/ebin" "$test_dir"
}
trap cleanup EXIT

mkdir -p "$test_dir/src" "$test_dir/ebin"
install -m 0644 "$project_root/applications/acdc/src/cb_queues.erl" "$test_dir/src/cb_queues.erl"
# ACDC is bundled kz5 source (doc/acdc_source_ownership.md); the installer no
# longer applies acdc-callback-crossbar-api.patch, so the bundled cb_queues.erl
# is the tested input and the historical patch is not a gate.
grep -q "callbacks" "$test_dir/src/cb_queues.erl" || {
    printf '%s\n' 'Bundled cb_queues.erl lacks the callback API' >&2
    exit 1
}

export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS="+S 1:1 +SDcpu 1 +SDio 1 +A 1"
export ERL_CRASH_DUMP=/dev/null
erlc -Werror -DTEST \
    -I "$project_root/applications/acdc/src" \
    -I "$project_root/applications/acdc/include" \
    -pa "$project_root/deps/lager/ebin" \
    -o "$test_dir/ebin" \
    "$test_dir/src/cb_queues.erl" \
    "$project_root/scripts/erlang-tests/cb_queues_callback_api_tests.erl"

erl -noshell -pa "$test_dir/ebin" \
    -eval 'case eunit:test(cb_queues_callback_api_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
