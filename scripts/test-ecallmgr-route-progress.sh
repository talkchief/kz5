#!/usr/bin/env bash
# Public XML-generator regressions in a private VM; no services or calls touched.
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo-route-progress-test.XXXXXX)
cleanup() {
    rm -f -- "$test_dir/ecallmgr_fs_xml.beam" "$test_dir/ecallmgr_util.beam" \
        "$test_dir/ecallmgr_route_progress_tests.beam"
    rmdir -- "$test_dir"
}
trap cleanup EXIT
cd "$project_root"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
erlc -Werror +debug_info -I applications/ecallmgr/src -I applications/ecallmgr/include \
    -pa deps/lager/ebin '+{parse_transform,lager_transform}' -o "$test_dir" \
    applications/ecallmgr/src/ecallmgr_fs_xml.erl applications/ecallmgr/src/ecallmgr_util.erl
erlc -Werror -o "$test_dir" scripts/erlang-tests/ecallmgr_route_progress_tests.erl
erl -pa "$test_dir" -noshell -eval \
    'case eunit:test(ecallmgr_route_progress_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
