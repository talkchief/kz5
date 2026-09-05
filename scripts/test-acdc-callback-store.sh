#!/usr/bin/env bash
# Isolated beams only: make eunit/compile-test must not touch service ebins.
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo-acdc-callback-test.XXXXXX)
cleanup() {
    rm -f -- "$test_dir/acdc_callback_store.beam" "$test_dir/acdc_callback_store_tests.beam"
    rmdir -- "$test_dir"
}
trap cleanup EXIT
cd "$project_root"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 2:2 +A 1'
export ERL_CRASH_DUMP=/dev/null
erlc -Werror +warn_missing_spec -I applications/acdc/src -I applications/acdc/include -pa deps/lager/ebin \
    +'{parse_transform,lager_transform}' -o "$test_dir" \
    applications/acdc/src/acdc_callback_store.erl
erlc -Werror -o "$test_dir" scripts/erlang-tests/acdc_callback_store_tests.erl
erl -pa "$test_dir" -noshell \
    -eval 'case eunit:test(acdc_callback_store_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
