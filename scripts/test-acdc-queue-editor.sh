#!/usr/bin/env bash
# Private compile and memory-only EUnit; never loads live nodes or calls HTTP.
set -Eeuo pipefail
editor_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
editor_output=$(mktemp -d /tmp/kazoo-queue-editor-test.XXXXXX)
cleanup() {
    rm -f -- "$editor_output/cb_queues.beam" "$editor_output/cb_acdc_queue_editor.beam" "$editor_output/acdc_gemini_prompts.beam" "$editor_output/acdc_queue_editor_tests.beam" "$editor_output/acdc_editor_manifest_path_tests.beam"
    rmdir -- "$editor_output"
}
trap cleanup EXIT
cd "$editor_root"
export ERL_LIBS="$editor_root/deps:$editor_root/core:$editor_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
erlc +warn_export_all +warn_unused_import +warn_unused_vars +warn_missing_spec -Werror \
    -I applications/acdc/src -I applications/acdc/include -pa deps/lager/ebin \
    +'{parse_transform,lager_transform}' -o "$editor_output" \
    applications/acdc/src/cb_queues.erl applications/acdc/src/cb_acdc_queue_editor.erl applications/acdc/src/acdc_gemini_prompts.erl
erlc -DTEST +debug_info -Werror -I applications/acdc/src -I applications/acdc/include \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' -o "$editor_output" applications/acdc/src/cb_acdc_queue_editor.erl
erlc +debug_info -Werror -I applications/acdc/src -o "$editor_output" scripts/erlang-tests/acdc_queue_editor_tests.erl scripts/erlang-tests/acdc_editor_manifest_path_tests.erl
erl -pa "$editor_output" -noshell -eval 'case eunit:test([acdc_queue_editor_tests, acdc_editor_manifest_path_tests], [verbose]) of ok -> halt(0); _ -> halt(1) end.'
