#!/usr/bin/env bash
# Offline production agent status authorization; root serializes guarded runs.
set -Eeuo pipefail
umask 077
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS ERL_INETRC
status_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
status_mode=${1:-current}
[[ $# -le 1 && ( $status_mode == current || $status_mode == --baseline ) ]] || { printf 'Use no arguments or --baseline\n' >&2; exit 2; }
status_output=$(mktemp -d /tmp/kazoo-agent-status-auth.XXXXXX)
cd "$status_root"
export ERL_LIBS="$status_root/deps:$status_root/core:$status_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP="$status_output/erl_crash.dump"
export ACDC_STATUS_AUTH_OUTPUT="$status_output"
status_exit() {
    local status_code=$?
    trap - EXIT
    if [[ -f "$status_output/inputs.sha256" ]]; then
        if ! sha256sum --check "$status_output/inputs.sha256"; then status_code=99; fi
    fi
    printf 'Agent status authorization %s exit %s; retained evidence: %s\n' "$status_mode" "$status_code" "$status_output"
    exit "$status_code"
}
trap status_exit EXIT
status_agent=applications/acdc/src/cb_agents.erl
if [[ $status_mode == --baseline ]]; then
    # Immutable local pre-fix source only; no checkout, fetch or worktree edits.
    git rev-parse --verify '4c20bb7^{commit}' > "$status_output/baseline-commit.txt"
    git show '4c20bb7:applications/acdc/src/cb_agents.erl' > "$status_output/cb_agents.erl"
    status_agent="$status_output/cb_agents.erl"
fi
status_sources=("$status_agent" applications/crossbar/src/crossbar_bindings.erl
    applications/crossbar/src/cb_context.erl applications/crossbar/src/api_util.erl
    applications/crossbar/src/crossbar_util.erl core/kazoo_bindings/src/kazoo_bindings.erl
    core/kazoo_bindings/src/kazoo_bindings_rt.erl core/kazoo_documents/src/kz_doc.erl
    core/kazoo_data/src/kzs_util.erl core/kazoo_stdlib/src/kz_json.erl
    core/kazoo_stdlib/src/kz_term.erl core/kazoo_stdlib/src/props.erl)
status_inputs=("${status_sources[@]}" scripts/test-acdc-agent-status-authorization.sh
    scripts/erlang-tests/acdc_agent_status_authorization_tests.erl)
/usr/bin/find applications/acdc/src applications/acdc/include applications/crossbar/src core/kazoo_bindings/src \
    core/kazoo_stdlib/include core/kazoo_amqp/include core/kazoo_documents/include core/kazoo_data/src \
    -type f -name '*.hrl' > "$status_output/headers.list"
LC_ALL=C /usr/bin/sort -o "$status_output/headers.list" "$status_output/headers.list"
while IFS= read -r status_header; do status_inputs+=("$status_header"); done < "$status_output/headers.list"
sha256sum "${status_inputs[@]}" > "$status_output/inputs.sha256"
printf 'Scope: 12 production modules rebuilt without TEST; real cb_agents and native authorization/bindings. Global policy, exchange declarations and terminal stop renderer controlled. No HTTP/status mutation or JWT proof. Restart callback return contract only, not end-to-end veto proof. Other OTP/ERL_LIBS dependencies prebuilt, unrebuilt and unpinned. Baseline is expected to fail, never accepted as PASS.\n' | tee "$status_output/scope.log"
erlc -Werror +warn_missing_spec +debug_info \
    -I applications/acdc/src -I applications/acdc/include -I applications/crossbar/src -I core/kazoo_bindings/src \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' -o "$status_output" "${status_sources[@]}"
erlc -Werror +debug_info -o "$status_output" scripts/erlang-tests/acdc_agent_status_authorization_tests.erl
erl -noshell -pa "$status_output" -eval '
    lists:foreach(fun(M)->
        {module,M}=code:ensure_loaded(M),
        Expected=filename:join(os:getenv("ACDC_STATUS_AUTH_OUTPUT"),atom_to_list(M)++".beam"),
        Expected=code:which(M),
        Options=proplists:get_value(options,M:module_info(compile),[]),
        false=lists:any(fun({d,'\''TEST'\''})->true;({d,'\''TEST'\'',_})->true;(export_all)->true;(_)->false end,Options)
    end,[cb_agents,crossbar_bindings,cb_context,api_util,crossbar_util,kazoo_bindings,kazoo_bindings_rt,
        kz_doc,kzs_util,kz_json,kz_term,props]),
    case eunit:test(acdc_agent_status_authorization_tests,[verbose]) of ok->halt(0);_->halt(1) end.' \
    | tee "$status_output/eunit.log"
