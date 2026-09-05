#!/usr/bin/env bash
# Compile logical queue-member tests into private temporary beams only.
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo-acdc-queue-member-test.XXXXXX)
cleanup() {
    rm -f -- "$test_dir/acdc_queue_strategy.beam" "$test_dir/kapps_call.beam" \
        "$test_dir/acdc_queue_member.beam" \
        "$test_dir/acdc_queue_manager.beam" \
        "$test_dir/kapi_acdc_queue.beam" \
        "$test_dir/acdc_queue_member_tests.beam" \
        "$test_dir/acdc_queue_manager_tests.beam"
    rmdir -- "$test_dir"
}
trap cleanup EXIT
cd "$project_root"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
erlc -DTEST -Werror -I core/kazoo_call/include \
    -I applications/acdc/src -I applications/acdc/include \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' -o "$test_dir" \
    core/kazoo_call/src/kapps_call.erl \
    applications/acdc/src/acdc_queue_member.erl \
    applications/acdc/src/kapi_acdc_queue.erl \
    applications/acdc/src/acdc_queue_strategy.erl applications/acdc/src/acdc_queue_manager.erl \
    applications/acdc/test/acdc_queue_member_tests.erl \
    applications/acdc/test/acdc_queue_manager_tests.erl
KAZOO_CONFIG="$project_root/rel/config-test.ini" erl -pa "$test_dir" -noshell \
    -eval 'application:ensure_all_started(lager), case eunit:test([acdc_queue_member_tests,acdc_queue_manager_tests], [verbose]) of ok -> halt(0); _ -> halt(1) end.'
