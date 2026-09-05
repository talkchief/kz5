#!/usr/bin/env bash
# Regression tests use isolated beams and mocks, never the running node.
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo-crossbar-auth-test.XXXXXX)
cleanup() {
    rm -- "$test_dir/crossbar_auth.beam" "$test_dir/kz_auth_jwt.beam" \
        "$test_dir/crossbar_auth_regression_tests.beam"
    rmdir -- "$test_dir"
}
trap cleanup EXIT
cd "$project_root"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 2:2 +A 2'
erlc -I applications/crossbar/src -I applications/crossbar/include -pa deps/lager/ebin \
    +'{parse_transform,lager_transform}' -o "$test_dir" \
    applications/crossbar/src/crossbar_auth.erl scripts/erlang-tests/crossbar_auth_regression_tests.erl
erlc -I core/kazoo_auth/src -I core/kazoo_auth/include -pa deps/lager/ebin \
    +'{parse_transform,lager_transform}' -o "$test_dir" core/kazoo_auth/src/kz_auth_jwt.erl
KAZOO_CONFIG="$project_root/rel/config-test.ini" erl -pa "$test_dir" -noshell \
    -eval 'application:ensure_all_started(lager), case eunit:test(crossbar_auth_regression_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
