#!/usr/bin/env bash
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo-acdc-wait-test.XXXXXX)
cleanup() {
    rm -f -- "$test_dir/cf_acdc_member.beam" "$test_dir/cf_acdc_member_wait_tests.beam"
    rmdir -- "$test_dir"
}
trap cleanup EXIT
cd "$project_root"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 2:2 +A 1'
erlc -DTEST -I applications/acdc/src -pa deps/lager/ebin \
    +'{parse_transform,lager_transform}' -o "$test_dir" \
    applications/acdc/src/cf_acdc_member.erl scripts/erlang-tests/cf_acdc_member_wait_tests.erl
erl -pa "$test_dir" -noshell \
    -eval 'case eunit:test(cf_acdc_member_wait_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
