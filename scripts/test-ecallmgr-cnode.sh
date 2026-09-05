#!/usr/bin/env bash
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo-cnode-test.XXXXXX)
cleanup() {
    rm -f -- "$test_dir/mod_kazoo.beam" "$test_dir/ecallmgr_cnode_regression_tests.beam"
    rmdir -- "$test_dir"
}
trap cleanup EXIT
cd "$project_root"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 2:2 +A 1'
erlc -I applications/ecallmgr/src -I applications/ecallmgr/include -o "$test_dir" \
    applications/ecallmgr/src/mod_kazoo.erl scripts/erlang-tests/ecallmgr_cnode_regression_tests.erl
erl -pa "$test_dir" -noshell \
    -eval 'case eunit:test(ecallmgr_cnode_regression_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
