#!/usr/bin/env bash
# Reconstruct the historical pre-language media baseline privately.
# This is a legacy compatibility suite, not validation of all bundled source.
set -Eeuo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
project_root=$(cd -- "${script_dir}/.." && pwd -P)
replay_only=false
while (($#)); do
    case "$1" in
        --project-root)
            [[ $# -ge 2 && -d $2 ]] || { printf '%s\n' 'A project directory is required.' >&2; exit 2; }
            project_root=$(cd -- "$2" && pwd -P); shift 2 ;;
        --replay-only) replay_only=true; shift ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
    esac
done
for command in git tar node erlc erl sha256sum; do
    command -v "$command" >/dev/null || { printf 'Required test tool missing: %s\n' "$command" >&2; exit 2; }
done
patch_file="${project_root}/scripts/patches/acdc-kazoo5-integration.patch"
installer_file="${project_root}/scripts/install-kazoo5.sh"
acdc_repository="${project_root}/applications/acdc"
[[ -f $patch_file && -f $installer_file && -d $acdc_repository ]] || {
    printf '%s\n' 'The project must contain the installer, historical patches, and bundled ACDC source.' >&2; exit 2;
}
# Parse one literal pinned revision; do not source the privileged installer or
# evaluate its environment. The pin records historical provenance only.
pinned_ref=$(node - "$installer_file" "$script_dir/gemini-runtime-inputs.cjs" <<'NODE'
const fs=require('node:fs');
process.stdout.write(require(process.argv[3]).pinnedRef(fs.readFileSync(process.argv[2],'utf8')));
NODE
)
node "$script_dir/test-acdc-gemini-runtime-inputs.cjs"
inputs_before=$(node "$script_dir/gemini-runtime-inputs.cjs" "$project_root" "$script_dir")
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/kazoo-gemini-runtime.XXXXXX")
cleanup() {
    # This exact private directory was created above. find does not follow any
    # archive symlinks and deletes no shared source or application BEAM.
    if [[ -d $test_dir && ! -L $test_dir && $(basename -- "$test_dir") == kazoo-gemini-runtime.* ]]; then
        find "$test_dir" -depth -delete
    fi
}
trap cleanup EXIT
mkdir "$test_dir/source" "$test_dir/production" "$test_dir/test"
cp -- "$patch_file" "$test_dir/integration.patch"
patch_hash=$(sha256sum -- "$test_dir/integration.patch" | awk '{print $1}')
node - "$inputs_before" "$pinned_ref" "$patch_hash" <<'NODE'
const assert=require('node:assert/strict'),snapshot=JSON.parse(process.argv[2]);
assert.equal(snapshot.pinned_ref,process.argv[3],'Pinned revision changed before snapshot');
assert.equal(snapshot.patch_sha256,process.argv[4],'Patch changed while snapshotting');
NODE
# Copy source, never runtime BEAMs or nested Git metadata. This suite compiles
# only media modules; current agent/queue FSMs are tested by the source suites.
# Requiring unrelated FSMs to match historical patches prevents normal fixes
# to bundled ACDC without providing any additional coverage here.
tar -cf - -C "$acdc_repository" src include priv test | tar -xf - -C "$test_dir/source"
for layer in acdc-language-runtime; do
    cp -- "$project_root/scripts/patches/$layer.patch" "$test_dir/$layer.patch"
    git -C "$test_dir/source" apply --reverse --check "$test_dir/$layer.patch"
    git -C "$test_dir/source" apply --reverse "$test_dir/$layer.patch"
done
replay_paths=(src/acdc_gemini_prompts.erl src/cf_acdc_member.erl src/acdc_announcements.erl
    src/acdc_callback_caller.erl src/acdc_announcements_sup.erl src/acdc_callback_menu.erl
    src/kapi_acdc_callback.erl src/acdc_gemini_map.hrl)
replay_includes=()
for replay_path in "${replay_paths[@]}"; do replay_includes+=("--include=$replay_path"); done
git -C "$test_dir/source" apply --reverse --check "${replay_includes[@]}" "$test_dir/integration.patch"
[[ ! -e "$test_dir/source/src/acdc_language.erl" ]] || {
    printf '%s\n' 'Default replay unexpectedly contains the staged language module.' >&2; exit 1;
}
node "$script_dir/generate-acdc-gemini-map.cjs" --check --project-root "$project_root" \
    --output "$test_dir/source/src/acdc_gemini_map.hrl"
export ERL_LIBS="${project_root}/deps:${project_root}/core:${project_root}/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
compiler=(-Werror +warn_missing_spec -I "$test_dir/source/src" -I "$test_dir/source/include"
    -pa "$project_root/deps/lager/ebin" +'{parse_transform,lager_transform}')
modules=(acdc_gemini_prompts cf_acdc_member acdc_announcements acdc_callback_caller)
production_sources=()
for module in "${modules[@]}"; do production_sources+=("$test_dir/source/src/${module}.erl"); done
# Production flags match the verified baseline integration; production BEAMs
# are separate from TEST exports and never copied into application directories.
erlc "${compiler[@]}" -o "$test_dir/production" "${production_sources[@]}"
KAZOO_TEST_PRODUCTION="$test_dir/production" erl -noshell -eval '
  Directory = os:getenv("KAZOO_TEST_PRODUCTION"),
  lists:foreach(fun({Module, TestOnly}) ->
    Path = filename:join(Directory, atom_to_list(Module)),
    {module, Module} = code:load_abs(Path),
    {ok,{Module,[{imports,Imports}]}} = beam_lib:chunks(Path ++ ".beam", [imports]),
    [] = [I || {Dependency,_,_}=I <- Imports, Dependency =:= acdc_language],
    false = erlang:function_exported(Module, element(1,TestOnly), element(2,TestOnly))
  end,[{acdc_gemini_prompts,{default_with,6}}, {cf_acdc_member,{callback_config,2}},
       {acdc_announcements,{get_config,1}}, {acdc_callback_caller,{confirmation_prompt,2}}]),
  io:format("PASS production BEAMs: no TEST exports or staged acdc_language imports~n"), halt().'
if [[ $replay_only == false ]]; then
    erlc -DTEST +debug_info "${compiler[@]}" -o "$test_dir/test" "${production_sources[@]}" \
        "$test_dir/source/src/acdc_announcements_sup.erl" \
        "$test_dir/source/src/acdc_callback_menu.erl" "$test_dir/source/src/kapi_acdc_callback.erl"
    erlc -Werror -I "$project_root/core/kazoo_amqp/include" -I "$project_root/core/kazoo_amqp/src" \
        -pa "$project_root/deps/lager/ebin" +'{parse_transform,lager_transform}' -o "$test_dir/test" \
        "$project_root/core/kazoo_amqp/src/api/kapi_dialplan.erl"
    erlc -Werror +debug_info -I "$test_dir/source/src" -o "$test_dir/test" \
        "$script_dir/test-fixtures/gemini-runtime/kz_datamgr.erl" \
        "$script_dir/erlang-tests/acdc_gemini_prompts_tests.erl" \
        "$script_dir/erlang-tests/acdc_gemini_runtime_tests.erl" \
        "$script_dir/erlang-tests/cf_acdc_callback_success_tests.erl" \
        "$project_root/scripts/erlang-tests/acdc_callback_announcement_tests.erl" \
        "$project_root/scripts/erlang-tests/acdc_callback_caller_tests.erl" \
        "$project_root/scripts/erlang-tests/cf_acdc_callback_integration_tests.erl" \
        "$project_root/scripts/erlang-tests/cf_acdc_callback_feedback_tests.erl"
    erl -pa "$test_dir/test" -noshell -eval '
      %% Remove every installed/staged ACDC path: only the replayed modules and
      %% their private test dependencies may satisfy these media/runtime calls.
      [code:del_path(P) || P <- code:get_path(), filelib:is_regular(filename:join(P,"acdc_language.beam"))],
      non_existing = code:which(acdc_language),
      case eunit:test([acdc_gemini_prompts_tests,acdc_gemini_runtime_tests,
                      cf_acdc_callback_feedback_tests,cf_acdc_callback_success_tests],[verbose]) of
        ok -> halt(0); _ -> halt(1)
      end.'
fi
inputs_after=$(node "$script_dir/gemini-runtime-inputs.cjs" "$project_root" "$script_dir")
[[ $(sha256sum -- "$patch_file" | awk '{print $1}') == "$patch_hash" && \
   $inputs_before == "$inputs_after" ]] || {
    printf '%s\n' 'Actual replay/test inputs changed during verification; this result is not a current-source receipt.' >&2; exit 1;
}
printf 'PASS historical ACDC media baseline from %s; patch SHA-256 %s; no staged language source or live writes.\n' "$pinned_ref" "$patch_hash"
