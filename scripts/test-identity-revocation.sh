#!/usr/bin/env bash
# Actual production module in an isolated VM; no live node or secrets.
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo-identity-revocation.XXXXXX)
cleanup() {
    [[ ! -f $test_dir/kz_auth_identity.beam ]] || rm -- "$test_dir/kz_auth_identity.beam"
    [[ ! -f $test_dir/kz_auth_identity_revocation_tests.beam ]] || rm -- "$test_dir/kz_auth_identity_revocation_tests.beam"
    rmdir -- "$test_dir"
}
trap cleanup EXIT
cd "$project_root"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 2:2 +A 2'
erlc -Werror -I core/kazoo_auth/src -I core/kazoo_auth/include -pa deps/lager/ebin \
    +'{parse_transform,lager_transform}' -o "$test_dir" \
    core/kazoo_auth/src/kz_auth_identity.erl scripts/erlang-tests/kz_auth_identity_revocation_tests.erl
KAZOO_CONFIG="$project_root/rel/config-test.ini" erl -pa "$test_dir" -noshell \
    -eval 'application:ensure_all_started(lager), case eunit:test(kz_auth_identity_revocation_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
