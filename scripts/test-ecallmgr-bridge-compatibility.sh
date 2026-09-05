#!/usr/bin/env bash
# Private source tests only; no calls, service changes, or runtime BEAM writes.
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo-ecallmgr-bridge-compatibility.XXXXXX)
cleanup() {
    find "$test_dir" -maxdepth 1 -type f -name '*.beam' -delete
    rmdir -- "$test_dir"
}
trap cleanup EXIT
cd "$project_root"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
erlc -DTEST -Werror +debug_info -I applications/ecallmgr/src -I applications/ecallmgr/include \
    -pa deps/lager/ebin '+{parse_transform,lager_transform}' -o "$test_dir" \
    applications/ecallmgr/src/call_cmd/ecallmgr_fs_bridge.erl
erlc -Werror -o "$test_dir" scripts/erlang-tests/ecallmgr_bridge_compatibility_tests.erl
erl -pa "$test_dir" -noshell -eval 'case eunit:test(ecallmgr_bridge_compatibility_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
