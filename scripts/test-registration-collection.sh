#!/usr/bin/env bash
# All TEST objects and mocks remain private to an isolated temporary VM.
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo-registration-collection.XXXXXX)
cleanup() {
    rm -f -- "$test_dir/kapi_registration.beam" "$test_dir/cb_devices.beam" \
        "$test_dir/kapi_registration_collection_tests.beam"
    rmdir -- "$test_dir"
}
trap cleanup EXIT
cd "$project_root"
node scripts/test-fixtures/registration-payload.test.cjs
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
erlc -DTEST -Werror +warn_missing_spec -I core/kazoo_amqp/src -o "$test_dir" \
    core/kazoo_amqp/src/api/kapi_registration.erl
erlc -Werror +warn_missing_spec -I applications/crossbar/src -I applications/crossbar/include \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' -o "$test_dir" \
    applications/crossbar/src/modules/cb_devices.erl
erlc -Werror -o "$test_dir" scripts/erlang-tests/kapi_registration_collection_tests.erl
erl -pa "$test_dir" -noshell \
    -eval 'case eunit:test(kapi_registration_collection_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
