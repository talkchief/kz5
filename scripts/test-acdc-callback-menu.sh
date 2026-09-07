#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d /tmp/kazoo-acdc-callback-menu.XXXXXX)
cleanup() {
    rm -f -- "$test_dir/ebin/acdc_callback_menu.beam" \
        "$test_dir/ebin/acdc_callback_menu_tests.beam"
    rmdir -- "$test_dir/ebin" "$test_dir"
}
trap cleanup EXIT

mkdir -p "$test_dir/ebin"
# ACDC is tracked directly in kz5. Validate the source that the installer
# compiles, not the historical import patch's obsolete reducer snapshot.

export ERL_FLAGS="+S 1:1 +SDcpu 1 +SDio 1 +A 1"
export ERL_CRASH_DUMP=/dev/null
erlc -Werror +warn_missing_spec -o "$test_dir/ebin" \
    "$project_root/applications/acdc/src/acdc_callback_menu.erl"
erlc -Werror -pa "$test_dir/ebin" -o "$test_dir/ebin" \
    "$project_root/scripts/erlang-tests/acdc_callback_menu_tests.erl"
erl -noshell -pa "$test_dir/ebin" \
    -eval 'case eunit:test(acdc_callback_menu_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
