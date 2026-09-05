#!/usr/bin/env bash
# Compile and run callback recovery I/O regressions only in an isolated temp dir.
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo-acdc-callback-recovery-io-test.XXXXXX)
cleanup() {
    rm -f -- "$test_dir/kapi_call.beam" "$test_dir/acdc_callback_recovery_io.beam" \
        "$test_dir/acdc_callback_recovery_io_tests.beam"
    rmdir -- "$test_dir"
}
trap cleanup EXIT
cd "$project_root"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 2:2 +A 1'
export ERL_CRASH_DUMP=/dev/null
erlc -Werror +warn_missing_spec -I core/kazoo_amqp/src -o "$test_dir" \
    core/kazoo_amqp/src/api/kapi_call.erl
erlc -DTEST -Werror +warn_missing_spec -I applications/acdc/src -I applications/acdc/include \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' -o "$test_dir" \
    applications/acdc/src/acdc_callback_recovery_io.erl
erlc -Werror -o "$test_dir" scripts/erlang-tests/acdc_callback_recovery_io_tests.erl
erl -pa "$test_dir" -noshell \
    -eval 'case eunit:test(acdc_callback_recovery_io_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
