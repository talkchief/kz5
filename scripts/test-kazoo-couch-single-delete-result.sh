#!/usr/bin/env bash
# Offline public Couch driver result classification; no credentials/network.
set -Eeuo pipefail
umask 077
[[ $# == 0 || ( $# == 1 && $1 == --baseline ) ]] || exit 64
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS ERL_INETRC
result_mode=${1:-current}
result_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$result_root"
[[ $(readlink /proc/self/ns/net) != "$(readlink /proc/1/ns/net)" ]] || exit 65
result_output=$(mktemp -d /tmp/kazoo-couch-delete-result.XXXXXX)
export KAZOO_COUCH_DELETE_OUTPUT="$result_output"
export ERL_LIBS="$result_root/deps:$result_root/core:$result_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1 -no_dot_erlang'
export ERL_CRASH_DUMP="$result_output/erl_crash.dump"
result_exit() {
    local result_code=$?
    trap - EXIT
    if [[ -f "$result_output/inputs.sha256" ]]; then
        sha256sum --status --check "$result_output/inputs.sha256" || result_code=99
    fi
    printf 'Single-delete result %s exit %s; evidence: %s\n' "$result_mode" "$result_code" "$result_output"
    exit "$result_code"
}
trap result_exit EXIT
result_ref=5defa1df755ea9cf4d0f3f81f8145bd8a0c7dd72
[[ $(git -C core rev-parse HEAD) == "$result_ref" ]]
result_patch="$result_root/scripts/patches/kazoo-couch-single-delete-result.patch"
result_sources=(core/kazoo_couch/src/kz_couch_doc.erl
    core/kazoo_documents/src/kz_doc.erl core/kazoo_stdlib/src/kz_json.erl)
result_inputs=("${result_sources[@]}" "$result_patch" scripts/install-kazoo5.sh
    scripts/test-kazoo-couch-single-delete-result.sh scripts/erlang-tests/kz_couch_single_delete_result_tests.erl)
/usr/bin/find core deps/couchbeam/include -type f -name '*.hrl' | LC_ALL=C sort > "$result_output/headers.list"
while IFS= read -r result_header; do result_inputs+=("$result_header"); done < "$result_output/headers.list"
sha256sum "${result_inputs[@]}" > "$result_output/inputs.sha256"
mkdir "$result_output/replay" "$result_output/baseline"
git -C core archive "$result_ref" kazoo_couch/src/kz_couch_doc.erl | tar -xf - -C "$result_output/replay"
cp "$result_output/replay/kazoo_couch/src/kz_couch_doc.erl" "$result_output/baseline/kz_couch_doc.erl"
sha256sum "$result_output/baseline/kz_couch_doc.erl" >> "$result_output/inputs.sha256"
sed -n '/^apply_required_source_patch() {$/,/^}$/p' scripts/install-kazoo5.sh > "$result_output/helper.sh"
[[ -s "$result_output/helper.sh" ]]
[[ $(grep -Fc '    apply_required_source_patch "$core_dir" "$SCRIPT_DIR/patches/kazoo-couch-single-delete-result.patch"' scripts/install-kazoo5.sh) == 1 ]]
(
    source "$result_output/helper.sh"
    DRY_RUN=false
    log() { printf '%s\n' "$*"; }
    die() { printf '%s\n' "$*" >&2; exit 65; }
    apply_required_source_patch "$result_output/replay" "$result_patch"
    cmp "$result_output/replay/kazoo_couch/src/kz_couch_doc.erl" core/kazoo_couch/src/kz_couch_doc.erl
    apply_required_source_patch "$result_output/replay" "$result_patch"
    git -C "$result_output/replay" apply --reverse "$result_patch"
    cmp "$result_output/replay/kazoo_couch/src/kz_couch_doc.erl" "$result_output/baseline/kz_couch_doc.erl"
    mkdir -p "$result_output/conflict/kazoo_couch/src"
    cp scripts/test-kazoo-couch-single-delete-result.sh "$result_output/conflict/kazoo_couch/src/kz_couch_doc.erl"
    if (apply_required_source_patch "$result_output/conflict" "$result_patch"); then exit 66; fi
)
if [[ $result_mode == --baseline ]]; then result_sources[0]="$result_output/baseline/kz_couch_doc.erl"; fi
printf '%s\n' 'Public Couch single-delete classification with mocked connection/retry/Couchbeam seams. Three production modules compiled without TEST/export_all; other dependencies prebuilt. No actual HTTP/datastore, retries, publication, service or deployment proof.' | tee "$result_output/scope.log"
erlc -Werror +debug_info -I core/kazoo_couch/src -pa deps/lager/ebin \
    +'{parse_transform,lager_transform}' -o "$result_output" "${result_sources[@]}"
erlc -Werror +debug_info -o "$result_output" scripts/erlang-tests/kz_couch_single_delete_result_tests.erl
erl -noshell -pa "$result_output" -eval '
    lists:foreach(fun(M) ->
        {module,M}=code:ensure_loaded(M),
        Expected=filename:join(os:getenv("KAZOO_COUCH_DELETE_OUTPUT"),atom_to_list(M)++".beam"),
        Expected=code:which(M),
        Options=proplists:get_value(options,M:module_info(compile),[]),
        false=lists:any(fun({d,'\''TEST'\''})->true;({d,'\''TEST'\'',_})->true;(export_all)->true;(_)->false end,Options)
    end,[kz_couch_doc,kz_doc,kz_json]),
    case eunit:test(kz_couch_single_delete_result_tests,[verbose]) of ok->halt(0);_->halt(1) end.' | tee "$result_output/eunit.log"
