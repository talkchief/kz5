#!/usr/bin/env bash
# Offline public-delete regression; no HTTP, service, datastore or deployment.
# Run through the root-owned resource guard and a network-isolated namespace.
set -Eeuo pipefail
umask 077
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS ERL_INETRC
delete_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
delete_mode=${1:-current}
[[ $# -le 1 && ( $delete_mode == current || $delete_mode == --baseline ) ]] || exit 64
delete_output=$(mktemp -d /tmp/kazoo-soft-delete-revision.XXXXXX)
cd "$delete_root"
export ERL_LIBS="$delete_root/deps:$delete_root/core:$delete_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1 -no_dot_erlang'
export ERL_CRASH_DUMP="$delete_output/erl_crash.dump"
export KAZOO_SOFT_DELETE_OUTPUT="$delete_output"
delete_exit() {
    local delete_code=$?
    trap - EXIT
    if [[ -f "$delete_output/inputs.sha256" ]]; then
        sha256sum --status --check "$delete_output/inputs.sha256" || delete_code=99
    fi
    printf 'Soft-delete revision %s exit %s; retained evidence: %s\n' "$delete_mode" "$delete_code" "$delete_output"
    exit "$delete_code"
}
trap delete_exit EXIT
delete_ref=2ac862830f9b626d2170d08daf1991b0ca33dba7
delete_patch="$delete_root/scripts/patches/crossbar-soft-delete-revision.patch"
[[ $(git -C applications/crossbar rev-parse HEAD) == "$delete_ref" ]] || exit 65
delete_sources=(applications/crossbar/src/crossbar_doc.erl applications/crossbar/src/cb_context.erl
    applications/crossbar/src/crossbar_util.erl core/kazoo_documents/src/kz_doc.erl
    core/kazoo_stdlib/src/kz_json.erl core/kazoo_stdlib/src/kz_term.erl
    core/kazoo_stdlib/src/props.erl core/kazoo_stdlib/src/kz_time.erl
    core/kazoo_data/src/kzs_util.erl core/kazoo_schemas/src/kz_json_schema.erl)
delete_inputs=("${delete_sources[@]}" "$delete_patch" scripts/install-kazoo5.sh
    scripts/test-crossbar-soft-delete-revision.sh scripts/erlang-tests/crossbar_soft_delete_revision_tests.erl)
/usr/bin/find applications/crossbar/src core/kazoo_stdlib/include core/kazoo_documents/include \
    core/kazoo_amqp/include core/kazoo_data/src core/kazoo_schemas/src \
    core/kazoo_numbers/include core/kazoo_web/include -type f -name '*.hrl' | LC_ALL=C sort > "$delete_output/headers.list"
while IFS= read -r delete_header; do delete_inputs+=("$delete_header"); done < "$delete_output/headers.list"
sha256sum "${delete_inputs[@]}" > "$delete_output/inputs.sha256"
printf '%s\n' "$delete_ref" > "$delete_output/baseline-commit.txt"
mkdir "$delete_output/replay" "$delete_output/baseline"
git -C applications/crossbar archive "$delete_ref" src/crossbar_doc.erl | tar -xf - -C "$delete_output/replay"
cp "$delete_output/replay/src/crossbar_doc.erl" "$delete_output/baseline/crossbar_doc.erl"
sed -n '/^apply_required_source_patch() {$/,/^}$/p' scripts/install-kazoo5.sh > "$delete_output/installer-helper.sh"
[[ -s "$delete_output/installer-helper.sh" ]]
[[ $(grep -Fc '        "$SCRIPT_DIR/patches/crossbar-soft-delete-revision.patch"' scripts/install-kazoo5.sh) == 1 ]]
(
    source "$delete_output/installer-helper.sh"
    DRY_RUN=false
    log() { printf '%s\n' "$*"; }
    die() { printf '%s\n' "$*" >&2; exit 65; }
    apply_required_source_patch "$delete_output/replay" "$delete_patch"
    cmp "$delete_output/replay/src/crossbar_doc.erl" applications/crossbar/src/crossbar_doc.erl
    apply_required_source_patch "$delete_output/replay" "$delete_patch"
    cmp "$delete_output/replay/src/crossbar_doc.erl" applications/crossbar/src/crossbar_doc.erl
    git -C "$delete_output/replay" apply --reverse "$delete_patch"
    cmp "$delete_output/replay/src/crossbar_doc.erl" "$delete_output/baseline/crossbar_doc.erl"
    mkdir "$delete_output/conflict" "$delete_output/conflict/src"
    cp scripts/test-crossbar-soft-delete-revision.sh "$delete_output/conflict/src/crossbar_doc.erl"
    if (apply_required_source_patch "$delete_output/conflict" "$delete_patch"); then exit 66; fi
)
sha256sum "$delete_output/baseline/crossbar_doc.erl" >> "$delete_output/inputs.sha256"
if [[ $delete_mode == --baseline ]]; then delete_sources[0]="$delete_output/baseline/crossbar_doc.erl"; fi
printf '%s\n' 'Scope: public production crossbar_doc delete with real document/context transforms and controlled datastore seams. Ten modules rebuilt without TEST/export_all. Other dependencies are prebuilt/unpinned. No actual Cowboy/HTTP/CouchDB, secondary replication, cascade transaction, service or live isolation proof.' | tee "$delete_output/scope.log"
erlc -Werror +debug_info -I applications/crossbar/src \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' -o "$delete_output" "${delete_sources[@]}"
erlc -Werror +debug_info -o "$delete_output" scripts/erlang-tests/crossbar_soft_delete_revision_tests.erl
erl -noshell -pa "$delete_output" -eval '
    lists:foreach(fun(M) ->
        {module,M}=code:ensure_loaded(M),
        Expected=filename:join(os:getenv("KAZOO_SOFT_DELETE_OUTPUT"),atom_to_list(M)++".beam"),
        Expected=code:which(M),
        Options=proplists:get_value(options,M:module_info(compile),[]),
        false=lists:any(fun({d,'\''TEST'\''})->true;({d,'\''TEST'\'',_})->true;(export_all)->true;(_)->false end,Options)
    end,[crossbar_doc,cb_context,crossbar_util,kz_doc,kz_json,kz_term,props,kz_time,kzs_util,kz_json_schema]),
    case eunit:test(crossbar_soft_delete_revision_tests,[verbose]) of ok->halt(0);_->halt(1) end.' \
    | tee "$delete_output/eunit.log"
