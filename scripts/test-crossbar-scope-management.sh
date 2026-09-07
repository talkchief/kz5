#!/usr/bin/env bash
# Root-serialized offline proof only. No services, HTTP or live configuration.
set -Eeuo pipefail
umask 077
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS ERL_INETRC
scope_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
scope_mode=${1:-current}
[[ $# -le 1 && ( $scope_mode == current || $scope_mode == --baseline ) ]] || exit 64
scope_output=$(mktemp -d /tmp/kazoo-scope-management.XXXXXX)
cd "$scope_root"
export ERL_LIBS="$scope_root/deps:$scope_root/core:$scope_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1 -no_dot_erlang'
export ERL_CRASH_DUMP="$scope_output/erl_crash.dump"
export KAZOO_SCOPE_MANAGEMENT_OUTPUT="$scope_output"
scope_exit() {
    local scope_code=$?
    trap - EXIT
    if [[ -f "$scope_output/inputs.sha256" ]]; then
        sha256sum --status --check "$scope_output/inputs.sha256" || scope_code=99
    fi
    printf 'Scope-management %s exit %s; retained evidence: %s\n' "$scope_mode" "$scope_code" "$scope_output"
    exit "$scope_code"
}
trap scope_exit EXIT
scope_ref=2ac862830f9b626d2170d08daf1991b0ca33dba7
scope_patch="$scope_root/scripts/patches/crossbar-scope-management-guard.patch"
[[ $(git -C applications/crossbar rev-parse HEAD) == "$scope_ref" ]] || exit 65
scope_sources=(applications/crossbar/src/modules/cb_scope_restrictions.erl
    applications/crossbar/src/crossbar_config.erl applications/crossbar/src/cb_context.erl
    applications/crossbar/src/crossbar_util.erl core/kazoo_documents/src/kzd_users.erl
    core/kazoo_documents/src/kz_doc.erl core/kazoo_stdlib/src/kz_json.erl
    core/kazoo_stdlib/src/kz_term.erl core/kazoo_stdlib/src/props.erl
    core/kazoo_stdlib/src/kz_time.erl core/kazoo_data/src/kzs_util.erl)
scope_inputs=("${scope_sources[@]}" "$scope_patch" scripts/patches/crossbar-kazoo5-integration.patch scripts/install-kazoo5.sh
    scripts/test-crossbar-scope-management.sh scripts/erlang-tests/crossbar_scope_management_tests.erl)
scope_header_dirs=(applications/crossbar/src core/kazoo_stdlib/include core/kazoo_documents/src
    core/kazoo_documents/include core/kazoo_amqp/include core/kazoo_data/src
    core/kazoo_numbers/include core/kazoo_web/include core/kazoo_services/include)
if command -v rg >/dev/null 2>&1; then
    rg --files --hidden --no-ignore -g '*.hrl' "${scope_header_dirs[@]}" > "$scope_output/headers.unsorted"
else
    /usr/bin/find "${scope_header_dirs[@]}" -type f -name '*.hrl' > "$scope_output/headers.unsorted"
fi
[[ -s "$scope_output/headers.unsorted" ]]
LC_ALL=C sort "$scope_output/headers.unsorted" > "$scope_output/headers.list"
while IFS= read -r scope_header; do scope_inputs+=("$scope_header"); done < "$scope_output/headers.list"
sha256sum "${scope_inputs[@]}" > "$scope_output/inputs.sha256"
# The existing aggregate has no hunks on the owned files; require that
# invariant rather than silently composing overlapping source transformations.
awk '/^diff --git / {if ($3 == "a/src/crossbar.hrl" || $3 == "a/src/crossbar_config.erl" || $3 == "a/src/modules/cb_scope_restrictions.erl") exit 1}' \
    scripts/patches/crossbar-kazoo5-integration.patch
printf '%s\n' "$scope_ref" > "$scope_output/baseline-commit.txt"
mkdir "$scope_output/replay" "$scope_output/baseline"
git -C applications/crossbar archive "$scope_ref" src/crossbar.hrl src/crossbar_config.erl \
    src/modules/cb_scope_restrictions.erl | tar -xf - -C "$scope_output/replay"
cp -a "$scope_output/replay/src" "$scope_output/baseline/src"
sed -n '/^apply_required_source_patch() {$/,/^}$/p' scripts/install-kazoo5.sh > "$scope_output/installer-helper.sh"
[[ -s "$scope_output/installer-helper.sh" ]]
(
    source "$scope_output/installer-helper.sh"
    DRY_RUN=false
    log() { printf '%s\n' "$*"; }
    die() { printf '%s\n' "$*" >&2; exit 65; }
    apply_required_source_patch "$scope_output/replay" "$scope_patch"
    for scope_file in src/crossbar.hrl src/crossbar_config.erl src/modules/cb_scope_restrictions.erl; do
        cmp "$scope_output/replay/$scope_file" "applications/crossbar/$scope_file"
    done
    apply_required_source_patch "$scope_output/replay" "$scope_patch"
    for scope_file in src/crossbar.hrl src/crossbar_config.erl src/modules/cb_scope_restrictions.erl; do
        cmp "$scope_output/replay/$scope_file" "applications/crossbar/$scope_file"
    done
    git -C "$scope_output/replay" apply --reverse "$scope_patch"
    for scope_file in src/crossbar.hrl src/crossbar_config.erl src/modules/cb_scope_restrictions.erl; do
        cmp "$scope_output/replay/$scope_file" "$scope_output/baseline/$scope_file"
    done
    mkdir "$scope_output/conflict"
    cp -a "$scope_output/baseline/src" "$scope_output/conflict/src"
    cp scripts/test-crossbar-scope-management.sh "$scope_output/conflict/src/crossbar.hrl"
    if (apply_required_source_patch "$scope_output/conflict" "$scope_patch"); then exit 66; fi
    cmp "$scope_output/conflict/src/modules/cb_scope_restrictions.erl" \
        "$scope_output/baseline/src/modules/cb_scope_restrictions.erl"
)
sha256sum "$scope_output/baseline/src/crossbar.hrl" "$scope_output/baseline/src/crossbar_config.erl" \
    "$scope_output/baseline/src/modules/cb_scope_restrictions.erl" >> "$scope_output/inputs.sha256"
scope_includes=(-I applications/crossbar/src)
if [[ $scope_mode == --baseline ]]; then
    scope_sources[0]="$scope_output/baseline/src/modules/cb_scope_restrictions.erl"
    scope_sources[1]="$scope_output/baseline/src/crossbar_config.erl"
    scope_includes=(-I "$scope_output/baseline/src" -I applications/crossbar/src)
fi
printf '%s\n' 'Scope: admin-only public validation and deployment capability/default list, with real cb_context/kzd_users role logic. Eleven modules compiled -Werror/Lager/no TEST or export_all; other dependencies prebuilt/unrebuilt/unpinned. Schema/doc/view/config and identity datastore seams are controlled. Global auth, hierarchy, JWT crypto, HTTP, runtime activation and services are NOT proven here. Installer helper byte replay is proven separately from root-owned registration tests.' | tee "$scope_output/scope.log"
erlc -Werror +debug_info "${scope_includes[@]}" -I core/kazoo_documents/src \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' -o "$scope_output" "${scope_sources[@]}"
erlc -Werror +debug_info -o "$scope_output" scripts/erlang-tests/crossbar_scope_management_tests.erl
erl -noshell -pa "$scope_output" -eval '
    lists:foreach(fun(M) ->
        {module,M}=code:ensure_loaded(M),
        Expected=filename:join(os:getenv("KAZOO_SCOPE_MANAGEMENT_OUTPUT"),atom_to_list(M)++".beam"),
        Expected=code:which(M),
        Options=proplists:get_value(options,M:module_info(compile),[]),
        false=lists:any(fun({d,'\''TEST'\''})->true;({d,'\''TEST'\'',_})->true;(export_all)->true;(_)->false end,Options)
    end,[cb_scope_restrictions,crossbar_config,cb_context,crossbar_util,kzd_users,kz_doc,kz_json,kz_term,props,kz_time,kzs_util]),
    case eunit:test(crossbar_scope_management_tests,[verbose]) of ok->halt(0);_->halt(1) end.' \
    | tee "$scope_output/eunit.log"
