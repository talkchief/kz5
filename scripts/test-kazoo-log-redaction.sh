#!/usr/bin/env bash
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo-plan-log-test.XXXXXX)
cleanup() {
    rm -f -- "$test_dir/kzs_plan.beam" "$test_dir/kzs_plan_log_regression_tests.beam" \
        "$test_dir/kz_dataconnection.beam" "$test_dir/kz_couch_util.beam" \
        "$test_dir/kz_couch_log_regression_tests.beam"
    rmdir -- "$test_dir"
}
trap cleanup EXIT
cd "$project_root"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 2:2 +A 1'
# Without the Lager transform, a mock sees the actual format and arguments
# before any logging backend could hide a credential in its output.
erlc +export_all +nowarn_export_all -I core/kazoo_data/src -I core/kazoo_data/include \
    -I core/kazoo_couch/src -o "$test_dir" core/kazoo_data/src/kzs_plan.erl \
    core/kazoo_data/src/kz_dataconnection.erl core/kazoo_couch/src/kz_couch_util.erl \
    scripts/erlang-tests/kzs_plan_log_regression_tests.erl \
    scripts/erlang-tests/kz_couch_log_regression_tests.erl
erl -pa "$test_dir" -noshell \
    -eval 'case eunit:test([kzs_plan_log_regression_tests, kz_couch_log_regression_tests], [verbose]) of ok -> halt(0); _ -> halt(1) end.'
