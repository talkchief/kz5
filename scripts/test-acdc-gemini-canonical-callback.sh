#!/usr/bin/env bash
# Compile current canonical sources into a private tree; no aggregate replay,
# live BEAM writes, database traffic, media imports, or telephone calls.
set -Eeuo pipefail
callback_test_mode=${1:-all}
[[ $# -le 1 && ( $callback_test_mode == all || $callback_test_mode == --media-only ) ]] || {
    printf 'Usage: %s [--media-only]\n' "$0" >&2
    exit 2
}
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo-gemini-canonical-callback.XXXXXX)
cleanup() {
    find "$test_dir" -type f -delete
    rmdir -- "$test_dir/production" "$test_dir/test" "$test_dir"
}
trap cleanup EXIT
mkdir "$test_dir/production" "$test_dir/test"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
sources=(acdc_gemini_prompts cf_acdc_member acdc_callback_caller acdc_announcements
         acdc_announcements_sup acdc_callback_menu acdc_language kapi_acdc_callback
         acdc_callback_internal acdc_callback_policy acdc_callback_store
         acdc_cardinal_media acdc_cardinal_prompts)
source_files=()
for module in "${sources[@]}"; do source_files+=("$project_root/applications/acdc/src/$module.erl"); done
test_files=(acdc_gemini_prompts_tests acdc_gemini_canonical_callback_tests
            cf_acdc_callback_feedback_tests cf_acdc_callback_integration_tests
            acdc_callback_caller_tests acdc_callback_announcement_tests cf_acdc_callback_success_tests)
test_sources=()
for module in "${test_files[@]}"; do test_sources+=("$project_root/scripts/erlang-tests/$module.erl"); done
inputs=("${source_files[@]}" "${test_sources[@]}"
        "$project_root/scripts/test-acdc-gemini-canonical-callback.sh"
        "$project_root/applications/acdc/src/acdc.hrl"
        "$project_root/applications/acdc/include/acdc_config.hrl"
        "$project_root/applications/callflow/src/callflow.hrl"
        "$project_root/core/kazoo_stdlib/include/kz_types.hrl"
        "$project_root/core/kazoo_stdlib/include/kz_records.hrl"
        "$project_root/core/kazoo_stdlib/include/kz_log.hrl"
        "$project_root/core/kazoo_stdlib/include/kz_databases.hrl"
        "$project_root/core/kazoo_amqp/include/kz_api_literals.hrl"
        "$project_root/core/kazoo_amqp/include/kz_api.hrl"
        "$project_root/core/kazoo_amqp/include/kz_amqp.hrl"
        "$project_root/core/kazoo_amqp/src/kz_amqp_util.hrl"
        "$project_root/core/kazoo_amqp/src/api/kapi_dialplan.hrl"
        "$project_root/core/kazoo_numbers/include/knm_phone_number.hrl"
        "$project_root/core/kazoo_call/include/kapps_call_command_types.hrl"
        "$project_root/core/kazoo_documents/include/kazoo_documents.hrl"
        "$project_root/core/kazoo_sip/include/kzsip_uri.hrl"
        "$project_root/applications/acdc/src/acdc_gemini_map.hrl"
        "$project_root/applications/acdc/src/acdc_cardinal_map.hrl"
        "$project_root/scripts/test-fixtures/gemini-runtime/kz_datamgr.erl"
        "$project_root/core/kazoo_amqp/src/api/kapi_dialplan.erl")
before=$(sha256sum -- "${inputs[@]}" | sha256sum | cut -d ' ' -f 1)
compiler=(-Werror +warn_missing_spec -I "$project_root/applications/acdc/src"
          -I "$project_root/applications/acdc/include" -pa "$project_root/deps/lager/ebin"
          +'{parse_transform,lager_transform}')
erlc "${compiler[@]}" -o "$test_dir/production" "${source_files[@]}"
erlc -DTEST +debug_info "${compiler[@]}" -o "$test_dir/test" "${source_files[@]}"
erlc -Werror +debug_info -I "$project_root/applications/acdc/src" -o "$test_dir/test" \
    "$project_root/scripts/test-fixtures/gemini-runtime/kz_datamgr.erl" "${test_sources[@]}"
erlc -Werror -I "$project_root/core/kazoo_amqp/include" -I "$project_root/core/kazoo_amqp/src" \
    -pa "$project_root/deps/lager/ebin" +'{parse_transform,lager_transform}' -o "$test_dir/test" \
    "$project_root/core/kazoo_amqp/src/api/kapi_dialplan.erl"
KAZOO_CANONICAL_TEST_MODE="$callback_test_mode" \
KAZOO_CANONICAL_TEST_DIR="$test_dir/test" KAZOO_CANONICAL_PRODUCTION_DIR="$test_dir/production" \
erl -noshell -pa "$test_dir/test" -eval '
    Private=os:getenv("KAZOO_CANONICAL_TEST_DIR"),
    [code:del_path(P) || P <- code:get_path(), P =/= Private,
        filelib:is_regular(filename:join(P,"acdc_announcements.beam"))],
    lists:foreach(fun(M) ->
        Private=filename:dirname(code:which(M))
    end,[acdc_gemini_prompts,cf_acdc_member,acdc_callback_caller,acdc_announcements,kz_datamgr]),
    Prod=os:getenv("KAZOO_CANONICAL_PRODUCTION_DIR"),
    lists:foreach(fun({M,Hook}) ->
        {ok,{M,[{exports,Exports}]}}=beam_lib:chunks(filename:join(Prod,atom_to_list(M)++".beam"),[exports]),
        false=lists:member(Hook,Exports)
    end,[{acdc_gemini_prompts,{auxiliary_with,4}},{cf_acdc_member,{callback_config,2}},
         {acdc_callback_caller,{confirmation_prompt,2}},{acdc_announcements,{resolve_callback_audio,2}}]),
    Suites = case os:getenv("KAZOO_CANONICAL_TEST_MODE") of
        "--media-only" -> [acdc_gemini_prompts_tests,acdc_gemini_canonical_callback_tests];
        "all" -> [acdc_gemini_prompts_tests,acdc_gemini_canonical_callback_tests,
                    cf_acdc_callback_feedback_tests,cf_acdc_callback_integration_tests,
                    acdc_callback_caller_tests,acdc_callback_announcement_tests,
                    cf_acdc_callback_success_tests]
    end,
    case eunit:test(Suites,[verbose]) of
        ok -> halt(0); _ -> halt(1)
    end.'
after=$(sha256sum -- "${inputs[@]}" | sha256sum | cut -d ' ' -f 1)
[[ $before == "$after" ]] || { printf '%s\n' 'Current callback inputs changed during verification.' >&2; exit 1; }
printf 'PASS current canonical callback sources; scope %s; input SHA-256 %s; no live writes.\n' "$callback_test_mode" "$after"
