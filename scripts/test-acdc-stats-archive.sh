#!/usr/bin/env bash
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo-acdc-stats-archive.XXXXXX)
cleanup() {
    find "$test_dir" -maxdepth 1 -type f -name '*.beam' -delete
    rmdir -- "$test_dir"
}
trap cleanup EXIT
cd "$project_root"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
erlc -DTEST -Werror +debug_info +warn_missing_spec -I applications/acdc/src -I applications/acdc/include \
    -pa deps/lager/ebin '+{parse_transform,lager_transform}' -o "$test_dir" \
    applications/acdc/src/acdc_stats.erl applications/acdc/src/acdc_agent_stats.erl \
    applications/acdc/src/acdc_stats_archive.erl applications/acdc/src/acdc_stats_sup.erl
erlc -Werror -I applications/acdc/src -o "$test_dir" scripts/erlang-tests/acdc_stats_archive_tests.erl
erl -pa "$test_dir" -noshell -eval 'case eunit:test(acdc_stats_archive_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
