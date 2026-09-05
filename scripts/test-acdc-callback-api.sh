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
if git -C "$test_dir" apply --check "$project_root/scripts/patches/acdc-callback-crossbar-api.patch" 2>/dev/null; then
    git -C "$test_dir" apply "$project_root/scripts/patches/acdc-callback-crossbar-api.patch"
elif ! git -C "$test_dir" apply --reverse --check "$project_root/scripts/patches/acdc-callback-crossbar-api.patch" 2>/dev/null; then
    printf '%s\n' 'Callback API source does not match the tested patch' >&2
    exit 1
fi

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
