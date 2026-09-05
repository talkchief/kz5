#!/usr/bin/env bash
# Private returned-call construction and real endpoint-policy regressions.
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo-acdc-returned-call-test.XXXXXX)
cleanup() {
    rm -f -- "$test_dir/acdc_callback_caller.beam" "$test_dir/acdc_callback_returned_call_tests.beam"
    rmdir -- "$test_dir"
}
trap cleanup EXIT
cd "$project_root"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
erlc -DTEST -Werror +warn_missing_spec -I applications/acdc/src -I applications/acdc/include \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' -o "$test_dir" \
    applications/acdc/src/acdc_callback_caller.erl
erlc -Werror -o "$test_dir" scripts/erlang-tests/acdc_callback_returned_call_tests.erl
erl -pa "$test_dir" -noshell \
    -eval 'case eunit:test(acdc_callback_returned_call_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
