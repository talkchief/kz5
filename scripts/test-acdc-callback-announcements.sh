#!/usr/bin/env bash
# Pure scheduler and real worker timers in private BEAM output only; no live API.
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo-callback-announcements-test.XXXXXX)
cleanup() {
    rm -f -- "$test_dir/acdc_language.beam" "$test_dir/acdc_announcements.beam" \
        "$test_dir/acdc_announcements_sup.beam" "$test_dir/acdc_queue_manager.beam" \
        "$test_dir/acdc_callback_announcement_tests.beam"
    rmdir -- "$test_dir"
}
trap cleanup EXIT
cd "$project_root"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
# Check production exports/warnings too; test compilation then replaces only
# these private files, never application ebin or a running node's code path.
erlc -Werror -I applications/acdc/src -I applications/acdc/include \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' -o "$test_dir" \
    applications/acdc/src/acdc_announcements.erl applications/acdc/src/acdc_announcements_sup.erl \
    applications/acdc/src/acdc_queue_manager.erl
erlc -DTEST +debug_info -Werror -I applications/acdc/src -I applications/acdc/include \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' -o "$test_dir" \
    applications/acdc/src/acdc_language.erl applications/acdc/src/acdc_announcements.erl \
    applications/acdc/src/acdc_announcements_sup.erl
erlc -Werror -o "$test_dir" scripts/erlang-tests/acdc_callback_announcement_tests.erl
erl -pa "$test_dir" -noshell \
    -eval 'case eunit:test(acdc_callback_announcement_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
