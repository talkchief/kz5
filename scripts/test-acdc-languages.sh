#!/usr/bin/env bash
set -Eeuo pipefail
language_test_mode=${1:-all}
[[ $# -le 1 && ( $language_test_mode == all || $language_test_mode == --snapshot-only ) ]] || exit 64
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo-acdc-languages-test.XXXXXX)
cleanup() {
    find "$test_dir" -maxdepth 1 -type f -name '*.beam' -delete
    rmdir -- "$test_dir"
}
trap cleanup EXIT
cd "$project_root"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
erlc -DTEST +debug_info -Werror -I applications/acdc/src -I applications/acdc/include \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' -o "$test_dir" \
    applications/acdc/src/acdc_language.erl applications/acdc/src/acdc_announcements.erl \
    applications/acdc/src/acdc_cardinal_media.erl applications/acdc/src/acdc_cardinal_prompts.erl \
    applications/acdc/src/acdc_gemini_prompts.erl \
    applications/acdc/src/acdc_wait_time_media.erl \
    applications/acdc/src/cf_acdc_member.erl applications/acdc/src/acdc_callback_caller.erl \
    applications/acdc/src/acdc_queue_member.erl applications/acdc/src/acdc_queue_fsm.erl
erlc -Werror -I applications/acdc/src -o "$test_dir" scripts/erlang-tests/acdc_language_tests.erl
KAZOO_LANGUAGE_TEST_MODE="$language_test_mode" erl -pa "$test_dir" -noshell \
    -eval 'Tests = case os:getenv("KAZOO_LANGUAGE_TEST_MODE") of
        "--snapshot-only" -> [{timeout, 30, fun acdc_language_tests:callback_response_keeps_admitted_language_after_queue_edit_test/0},
                              fun acdc_language_tests:callback_reservation_restores_snapshot_not_current_call_defaults_test/0,
                              fun acdc_language_tests:registration_settings_do_not_overwrite_admitted_language_test/0];
        "all" -> acdc_language_tests end,
        case eunit:test(Tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
