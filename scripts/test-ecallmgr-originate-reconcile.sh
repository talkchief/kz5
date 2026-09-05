#!/usr/bin/env bash
# Compile and run originate reconciliation protocol tests only in /tmp.
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo-ecallmgr-originate-reconcile-test.XXXXXX)
cleanup() {
    rm -f -- "$test_dir/kapi_call.beam" "$test_dir/ecallmgr_originate.beam" \
        "$test_dir/ecallmgr_fs_channels.beam" \
        "$test_dir/ecallmgr_originate_reconcile_tests.beam"
    rmdir -- "$test_dir"
}
trap cleanup EXIT
cd "$project_root"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
erlc -Werror +warn_missing_spec -I core/kazoo_amqp/src -o "$test_dir" \
    core/kazoo_amqp/src/api/kapi_call.erl
erlc -DTEST -Werror +warn_missing_spec -I applications/ecallmgr/src \
    -I applications/ecallmgr/include -pa deps/lager/ebin \
    +'{parse_transform,lager_transform}' -o "$test_dir" \
    applications/ecallmgr/src/ecallmgr_originate.erl \
    applications/ecallmgr/src/ecallmgr_fs_channels.erl
erlc -Werror -o "$test_dir" scripts/erlang-tests/ecallmgr_originate_reconcile_tests.erl
erl -pa "$test_dir" -noshell \
    -eval 'case eunit:test(ecallmgr_originate_reconcile_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
