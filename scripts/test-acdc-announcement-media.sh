#!/usr/bin/env bash
# Prompt playback and initial-delay tests use only isolated temporary BEAMs.
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo-announcement-media-test.XXXXXX)
cleanup() {
    rm -f -- "$test_dir/acdc_language.beam" "$test_dir/acdc_announcements.beam" "$test_dir/acdc_announcements_tests.beam" \
        "$test_dir/acdc_cardinal_media.beam" "$test_dir/acdc_cardinal_prompts.beam" "$test_dir/acdc_gemini_prompts.beam" \
        "$test_dir/acdc_wait_time_media.beam" \
        "$test_dir/ecallmgr_util.beam" "$test_dir/ecallmgr_prompt_media_tests.beam"
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
    applications/acdc/src/acdc_gemini_prompts.erl applications/acdc/src/acdc_wait_time_media.erl
erlc -Werror -I applications/ecallmgr/src -I applications/ecallmgr/include \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' -o "$test_dir" \
    applications/ecallmgr/src/ecallmgr_util.erl
erlc -Werror -o "$test_dir" applications/acdc/test/acdc_announcements_tests.erl \
    scripts/erlang-tests/ecallmgr_prompt_media_tests.erl
erl -pa "$test_dir" -noshell \
    -eval 'case eunit:test([acdc_announcements_tests,ecallmgr_prompt_media_tests], [verbose]) of ok -> halt(0); _ -> halt(1) end.'
