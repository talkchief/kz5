#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d /tmp/kazoo-acdc-callback-integration.XXXXXX)
cleanup() {
    find "$test_dir" -type f -delete
    rmdir -- "$test_dir"
}
trap cleanup EXIT

export ERL_FLAGS="+S 1:1 +SDcpu 1 +SDio 1 +A 1"
export ERL_CRASH_DUMP=/dev/null
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"

erlc -DTEST -Werror +warn_missing_spec \
    -I "$project_root/applications/acdc/include" -o "$test_dir" \
    "$project_root/applications/acdc/src/acdc_callback_menu.erl" \
    "$project_root/applications/acdc/src/acdc_language.erl" \
    "$project_root/applications/acdc/src/cf_acdc_member.erl" \
    "$project_root/applications/acdc/src/kapi_acdc_callback.erl"
erlc -Werror -pa "$test_dir" -o "$test_dir" \
    "$project_root/scripts/erlang-tests/cf_acdc_callback_integration_tests.erl"
erl -noshell -pa "$test_dir" \
    -eval 'case eunit:test(cf_acdc_callback_integration_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
