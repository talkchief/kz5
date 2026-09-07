#!/usr/bin/env bash
set -Eeuo pipefail
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
erlc -DTEST -Werror -I applications/acdc/src -I applications/acdc/include \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' -o "$test_dir" \
    applications/acdc/src/acdc_language.erl applications/acdc/src/acdc_announcements.erl \
    applications/acdc/src/acdc_cardinal_media.erl applications/acdc/src/acdc_cardinal_prompts.erl \
    applications/acdc/src/acdc_gemini_prompts.erl \
    applications/acdc/src/acdc_wait_time_media.erl \
    applications/acdc/src/cf_acdc_member.erl applications/acdc/src/acdc_callback_caller.erl
erlc -Werror -I applications/acdc/src -o "$test_dir" scripts/erlang-tests/acdc_language_tests.erl
erl -pa "$test_dir" -noshell \
    -eval 'case eunit:test(acdc_language_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
