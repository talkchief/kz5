#!/usr/bin/env bash
# Offline private candidate only. No live source, ebin, API or daemon changes.
set -Eeuo pipefail
members_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
members_output=$(mktemp -d /tmp/kazoo-members-devices-test.XXXXXX)
cleanup() {
    rm -f -- "$members_output/cb_members.beam" "$members_output/cb_members_tests.beam" "$members_output/cb_members_auth_review_tests.beam" "$members_output/api_util.beam"
    rmdir -- "$members_output"
}
trap cleanup EXIT
cd "$members_root"
export ERL_LIBS="$members_root/deps:$members_root/core:$members_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
members_source=scripts/erlang-candidates/members_devices
members_runtime=applications/crossbar/src/modules/cb_members.erl
erlc +debug_info +warn_missing_spec -Werror -pa deps/lager/ebin \
    +'{parse_transform,lager_transform}' -o "$members_output" applications/crossbar/src/api_util.erl
erlc +debug_info +warn_export_all +warn_unused_import +warn_unused_vars +warn_missing_spec -Werror \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' -o "$members_output" "$members_runtime"
erlc -DTEST +debug_info -Werror -pa deps/lager/ebin +'{parse_transform,lager_transform}' \
    -o "$members_output" "$members_runtime" "$members_source/cb_members_tests.erl" "$members_source/cb_members_auth_review_tests.erl"
erl -pa "$members_output" -noshell -eval 'case eunit:test([cb_members_tests,cb_members_auth_review_tests],[verbose]) of ok -> halt(0); _ -> halt(1) end.'
