#!/usr/bin/env bash
# Isolated compilation only: never replace any production service beam.
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo-acdc-roster-pagination.XXXXXX)
cleanup() {
    rm -f -- "$test_dir/cb_queues.beam" "$test_dir/cb_queues_roster_pagination_tests.beam"
    rmdir -- "$test_dir"
}
trap cleanup EXIT
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
erlc -Werror -I "$project_root/applications/acdc/src" \
    -I "$project_root/applications/acdc/include" -pa "$project_root/deps/lager/ebin" \
    -o "$test_dir" "$project_root/applications/acdc/src/cb_queues.erl" \
    "$project_root/scripts/erlang-tests/cb_queues_roster_pagination_tests.erl"
erl -noshell -pa "$test_dir" \
    -eval 'case eunit:test(cb_queues_roster_pagination_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
