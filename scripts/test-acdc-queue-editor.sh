#!/usr/bin/env bash
# Private compile and memory-only EUnit; never loads live nodes or calls HTTP.
set -Eeuo pipefail
umask 077
editor_mode=${1:-all}
[[ $# -le 1 && ( $editor_mode == all || $editor_mode == --bulk-only ) ]] || {
    printf 'Usage: %s [--bulk-only]\n' "$0" >&2
    exit 2
}
editor_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
editor_output=$(mktemp -d /tmp/kazoo-queue-editor-test.XXXXXX)
editor_completed=0
finish() {
    local editor_status=$?
    trap - EXIT
    if [[ $editor_status == 0 && $editor_completed != 1 ]]; then
        printf 'FAIL queue editor validation interrupted before completion\n' >&2
        editor_status=99
    fi
    if ! sha256sum --check --status "$editor_output/source-pins.sha256"; then
        printf 'FAIL queue editor source changed during validation\n' >&2
        editor_status=99
    fi
    printf 'Queue editor validation exit=%s; retained private evidence: %s\n' "$editor_status" "$editor_output"
    exit "$editor_status"
}
cd "$editor_root"
sha256sum applications/acdc/src/cb_queues.erl applications/acdc/src/cb_acdc_queue_editor.erl \
    applications/acdc/src/acdc_gemini_prompts.erl applications/acdc/src/acdc_gemini_map.hrl \
    core/kazoo_documents/src/kz_doc.erl scripts/erlang-tests/acdc_queue_editor_tests.erl \
    scripts/erlang-tests/acdc_editor_manifest_path_tests.erl scripts/test-acdc-queue-editor.sh \
    >"$editor_output/source-pins.sha256"
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
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
if [[ $editor_mode == --bulk-only ]]; then
    editor_eunit='case eunit:test({generator, fun acdc_queue_editor_tests:bulk_outcomes_test_/0}, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
else
    editor_eunit='case eunit:test([acdc_queue_editor_tests, acdc_editor_manifest_path_tests], [verbose]) of ok -> halt(0); _ -> halt(1) end.'
fi
erl -pa "$editor_output" -noshell -eval "$editor_eunit" 2>&1 | tee "$editor_output/eunit.log"
editor_completed=1
