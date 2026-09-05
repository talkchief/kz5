#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d /tmp/kazoo-acdc-callback-feedback.XXXXXX)
cleanup() {
    find "$test_dir" -maxdepth 1 -type f -delete
    rmdir -- "$test_dir"
}
trap cleanup EXIT

export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"

# Compile only into this private directory, never a live application's ebin.
erlc -DTEST -Werror +warn_missing_spec -I "$project_root/applications/acdc/include" \
    -pa "$project_root/deps/lager/ebin" +'{parse_transform,lager_transform}' -o "$test_dir" \
    "$project_root/applications/acdc/src/acdc_callback_menu.erl" \
    "$project_root/applications/acdc/src/acdc_language.erl" \
    "$project_root/applications/acdc/src/cf_acdc_member.erl" \
    "$project_root/applications/acdc/src/kapi_acdc_callback.erl"
erlc -Werror -I "$project_root/core/kazoo_amqp/include" -I "$project_root/core/kazoo_amqp/src" \
    -pa "$project_root/deps/lager/ebin" +'{parse_transform,lager_transform}' -o "$test_dir" \
    "$project_root/core/kazoo_amqp/src/api/kapi_dialplan.erl"
erlc -Werror -pa "$test_dir" -o "$test_dir" \
    "$project_root/scripts/erlang-tests/cf_acdc_callback_feedback_tests.erl"
erl -noshell -pa "$test_dir" \
    -eval 'case eunit:test(cf_acdc_callback_feedback_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
