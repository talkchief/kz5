#!/usr/bin/env bash
# Offline logger/dispatch proof only. Root owns serialized guarded execution.
set -Eeuo pipefail
umask 077
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS ERL_INETRC
binding_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
binding_mode=${1:-current}
[[ $# -le 1 && ( $binding_mode == current || $binding_mode == --baseline ) ]] || { printf 'Use no arguments or --baseline\n' >&2; exit 2; }
binding_output=$(mktemp -d /tmp/kazoo-bindings-exceptions.XXXXXX)
cd "$binding_root"
export ERL_LIBS="$binding_root/deps:$binding_root/core:$binding_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP="$binding_output/erl_crash.dump"
export KAZOO_BINDINGS_EXCEPTION_OUTPUT="$binding_output"
binding_exit() {
    local binding_code=$?
    trap - EXIT
    if [[ -f "$binding_output/inputs.sha256" ]]; then
        if ! sha256sum --check "$binding_output/inputs.sha256"; then binding_code=99; fi
    fi
    printf 'Binding exceptions %s exit %s; retained evidence: %s\n' "$binding_mode" "$binding_code" "$binding_output"
    exit "$binding_code"
}
trap binding_exit EXIT
binding_source=core/kazoo_bindings/src/kazoo_bindings.erl
binding_core_ref=5defa1df755ea9cf4d0f3f81f8145bd8a0c7dd72
binding_patch="$binding_root/scripts/patches/kazoo-bindings-exception-diagnostics.patch"
[[ $(git -C core rev-parse HEAD) == "$binding_core_ref" ]] || { printf 'Unexpected core revision\n' >&2; exit 1; }
printf '%s\n' "$binding_core_ref" > "$binding_output/baseline-commit.txt"
binding_sources=("$binding_source" core/kazoo_bindings/src/kazoo_bindings_rt.erl)
binding_inputs=("${binding_sources[@]}" scripts/test-kazoo-bindings-exceptions.sh
    scripts/erlang-tests/kazoo_bindings_exception_tests.erl "$binding_patch" scripts/install-kazoo5.sh)
if command -v rg >/dev/null 2>&1; then
    rg --files --hidden --no-ignore core/kazoo_bindings/src core/kazoo_stdlib/include -g '*.hrl' > "$binding_output/headers.list"
else
    # Restricted validation PATHs may not include rg. Do not silently lose pins.
    /usr/bin/find core/kazoo_bindings/src core/kazoo_stdlib/include -type f -name '*.hrl' > "$binding_output/headers.list"
fi
LC_ALL=C /usr/bin/sort -o "$binding_output/headers.list" "$binding_output/headers.list"
while IFS= read -r binding_header; do binding_inputs+=("$binding_header"); done < "$binding_output/headers.list"
sha256sum "${binding_inputs[@]}" > "$binding_output/inputs.sha256"
mkdir "$binding_output/replay" "$binding_output/baseline"
git -C core archive "$binding_core_ref" kazoo_bindings/src/kazoo_bindings.erl | tar -xf - -C "$binding_output/replay"
cp "$binding_output/replay/kazoo_bindings/src/kazoo_bindings.erl" "$binding_output/baseline/kazoo_bindings.erl"
git -C "$binding_output/replay" apply --check "$binding_patch"
# Execute only the actual narrow installer helper, never the installer entry
# point/config loader. The exact source registration is part of the contract.
[[ $(grep -Fc '    apply_required_source_patch "$core_dir" "$SCRIPT_DIR/patches/kazoo-bindings-exception-diagnostics.patch"' scripts/install-kazoo5.sh) == 1 ]]
sed -n '/^apply_required_source_patch() {$/,/^}$/p' scripts/install-kazoo5.sh > "$binding_output/installer-helper.sh"
[[ -s "$binding_output/installer-helper.sh" ]]
(
    source "$binding_output/installer-helper.sh"
    DRY_RUN=false
    log() { printf '%s\n' "$*"; }
    die() { printf '%s\n' "$*" >&2; exit 1; }
    apply_required_source_patch "$binding_output/replay" "$binding_patch"
    cp "$binding_output/replay/kazoo_bindings/src/kazoo_bindings.erl" "$binding_output/after-first-apply.erl"
    apply_required_source_patch "$binding_output/replay" "$binding_patch"
    cmp "$binding_output/after-first-apply.erl" "$binding_output/replay/kazoo_bindings/src/kazoo_bindings.erl"
    mkdir "$binding_output/rejected-source"
    if (apply_required_source_patch "$binding_output/rejected-source" "$binding_patch"); then
        printf 'Installer accepted unmatched source\n' >&2; exit 1
    fi
    [[ -z $(ls -A "$binding_output/rejected-source") ]]
) > "$binding_output/installer-replay.log" 2>&1
git -C "$binding_output/replay" apply --reverse --check "$binding_patch"
if git -C "$binding_output/replay" apply --check "$binding_patch" 2>/dev/null; then
    printf 'Patch unexpectedly applies twice\n' >&2; exit 1
fi
cmp "$binding_source" "$binding_output/replay/kazoo_bindings/src/kazoo_bindings.erl"
git -C core apply --reverse --check "$binding_patch"
if [[ $binding_mode == --baseline ]]; then binding_sources[0]="$binding_output/baseline/kazoo_bindings.erl"; fi
sha256sum "$binding_output/baseline/kazoo_bindings.erl" \
    "$binding_output/replay/kazoo_bindings/src/kazoo_bindings.erl" >> "$binding_output/inputs.sha256"
mkdir "$binding_output/production" "$binding_output/capture"
printf 'Scope: two production modules compile with -Werror, without TEST, and with the real Lager transform. A separate no-TEST/no-transform build of the same sources executes real registry/map/pmap/fold with logger sinks substituted, so exact unformatted logging arguments can be checked. No service, broker, HTTP or real credential proof. Other OTP/ERL_LIBS dependencies are prebuilt, unrebuilt and unpinned. Baseline must fail.\n' | tee "$binding_output/scope.log"
erlc -Werror +debug_info -I core/kazoo_bindings/src -pa deps/lager/ebin \
    '+{parse_transform,lager_transform}' -o "$binding_output/production" "${binding_sources[@]}"
erlc -Werror +debug_info -I core/kazoo_bindings/src -o "$binding_output/capture" "${binding_sources[@]}"
erlc -Werror +debug_info -o "$binding_output/capture" scripts/erlang-tests/kazoo_bindings_exception_tests.erl
erl -pa "$binding_output/production" -noshell -eval '
    Root=os:getenv("KAZOO_BINDINGS_EXCEPTION_OUTPUT"),
    lists:foreach(fun(M)->
        {module,M}=code:ensure_loaded(M),
        Expected=filename:join([Root,"production",atom_to_list(M)++".beam"]),Expected=code:which(M),
        Options=proplists:get_value(options,M:module_info(compile),[]),
        true=lists:member({parse_transform,lager_transform},Options),
        false=lists:any(fun({d,'\''TEST'\''})->true;({d,'\''TEST'\'',_})->true;(export_all)->true;(_)->false end,Options)
    end,[kazoo_bindings,kazoo_bindings_rt]),halt(0).'
erl -pa "$binding_output/capture" -noshell -eval '
    Root=os:getenv("KAZOO_BINDINGS_EXCEPTION_OUTPUT"),
    lists:foreach(fun(M)->
        {module,M}=code:ensure_loaded(M),
        Expected=filename:join([Root,"capture",atom_to_list(M)++".beam"]),Expected=code:which(M),
        false=lists:any(fun({d,'\''TEST'\''})->true;({d,'\''TEST'\'',_})->true;
            ({parse_transform,_})->true;(export_all)->true;(_)->false end,
            proplists:get_value(options,M:module_info(compile),[]))
    end,[kazoo_bindings,kazoo_bindings_rt]),
    case eunit:test(kazoo_bindings_exception_tests,[verbose,{scale_timeouts,4}]) of ok->halt(0);_->halt(1) end.' \
    | tee "$binding_output/eunit.log"
