#!/usr/bin/env bash
# Private compile and command rendering only; no live channel or API writes.
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo-file-timeout-test.XXXXXX)
cleanup() {
    rm -f -- "$test_dir/kapi_dialplan.beam" "$test_dir/ecallmgr_call_command.beam" \
        "$test_dir/acdc_file_playback_timeout_tests.beam"
    rmdir -- "$test_dir"
}
trap cleanup EXIT
cd "$project_root"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
erlc -Werror -I core/kazoo_amqp/include -I core/kazoo_amqp/src -pa deps/lager/ebin \
    +'{parse_transform,lager_transform}' -o "$test_dir" core/kazoo_amqp/src/api/kapi_dialplan.erl
erlc -Werror -I applications/ecallmgr/include -I applications/ecallmgr/src -pa deps/lager/ebin \
    +'{parse_transform,lager_transform}' -o "$test_dir" applications/ecallmgr/src/call_cmd/ecallmgr_call_command.erl
erlc -DTEST +debug_info -Werror -I applications/ecallmgr/include -I applications/ecallmgr/src -pa deps/lager/ebin \
    +'{parse_transform,lager_transform}' -o "$test_dir" applications/ecallmgr/src/call_cmd/ecallmgr_call_command.erl
erlc -Werror -o "$test_dir" scripts/erlang-tests/acdc_file_playback_timeout_tests.erl
erl -pa "$test_dir" -noshell -eval 'case eunit:test(acdc_file_playback_timeout_tests,[verbose]) of ok -> halt(0); _ -> halt(1) end.'
