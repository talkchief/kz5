#!/usr/bin/env bash
# Offline ordinary bridge-proof regression. Root owns guarded execution.
set -Eeuo pipefail
umask 077
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS ERL_INETRC
bridge_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
bridge_mode=${1:-current}
[[ $# -le 1 && ( $bridge_mode == current || $bridge_mode == --baseline ) ]] || { printf 'Use no arguments or --baseline\n' >&2; exit 2; }
bridge_output=$(mktemp -d /tmp/kazoo-ordinary-bridge-proof.XXXXXX)
cd "$bridge_root"
export ERL_LIBS="$bridge_root/deps:$bridge_root/core:$bridge_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP="$bridge_output/erl_crash.dump"
export ACDC_ORDINARY_BRIDGE_OUTPUT="$bridge_output"
bridge_exit() {
    local bridge_code=$?
    trap - EXIT
    if [[ -f "$bridge_output/inputs.sha256" ]]; then
        if ! sha256sum --check "$bridge_output/inputs.sha256"; then bridge_code=99; fi
    fi
    printf 'Ordinary bridge proof %s exit %s; retained evidence: %s\n' "$bridge_mode" "$bridge_code" "$bridge_output"
    exit "$bridge_code"
}
trap bridge_exit EXIT
bridge_fsm=applications/acdc/src/acdc_queue_fsm.erl
if [[ $bridge_mode == --baseline ]]; then
    git rev-parse --verify 'd7dde11^{commit}' > "$bridge_output/baseline-commit.txt"
    git show 'd7dde11:applications/acdc/src/acdc_queue_fsm.erl' > "$bridge_output/acdc_queue_fsm.erl"
    bridge_fsm="$bridge_output/acdc_queue_fsm.erl"
fi
bridge_sources=("$bridge_fsm" applications/acdc/src/acdc_queue_strategy.erl
    applications/acdc/src/acdc_callback_recovery_io.erl)
bridge_inputs=("${bridge_sources[@]}" scripts/test-acdc-ordinary-bridge-proof.sh
    scripts/erlang-tests/acdc_queue_strategy_tests.erl)
/usr/bin/find applications/acdc/src applications/acdc/include core/kazoo_stdlib/include \
    core/kazoo_amqp/include core/kazoo_documents/include -type f -name '*.hrl' > "$bridge_output/headers.list"
LC_ALL=C /usr/bin/sort -o "$bridge_output/headers.list" "$bridge_output/headers.list"
while IFS= read -r bridge_header; do bridge_inputs+=("$bridge_header"); done < "$bridge_output/headers.list"
sha256sum "${bridge_inputs[@]}" > "$bridge_output/inputs.sha256"
mkdir "$bridge_output/production" "$bridge_output/test"
printf 'Scope: three production modules no TEST/-Werror; separate TEST-export FSM for actual connecting/ready handlers. Channel snapshot provider controlled; no broker, calls, services or fresh live bridge proof. Existing callback recovery I/O production source compiled; its separate correlation tests remain required. All other OTP/ERL_LIBS dependencies prebuilt, unrebuilt and unpinned. Baseline expected nonzero.\n' | tee "$bridge_output/scope.log"
erlc -Werror +debug_info -I applications/acdc/src -I applications/acdc/include \
    -pa deps/lager/ebin '+{parse_transform,lager_transform}' -o "$bridge_output/production" "${bridge_sources[@]}"
erlc -DTEST -Werror +debug_info -I applications/acdc/src -I applications/acdc/include \
    -pa deps/lager/ebin '+{parse_transform,lager_transform}' -o "$bridge_output/test" "$bridge_fsm"
erlc -Werror -I applications/acdc/src -I applications/acdc/include -o "$bridge_output/test" \
    scripts/erlang-tests/acdc_queue_strategy_tests.erl
erl -pa "$bridge_output/production" -noshell -eval '
    Root=os:getenv("ACDC_ORDINARY_BRIDGE_OUTPUT"),
    lists:foreach(fun(M)->
        {module,M}=code:ensure_loaded(M),
        Expected=filename:join([Root,"production",atom_to_list(M)++".beam"]),Expected=code:which(M),
        false=lists:any(fun({d,'\''TEST'\''})->true;({d,'\''TEST'\'',_})->true;(export_all)->true;(_)->false end,
            proplists:get_value(options,M:module_info(compile),[]))
    end,[acdc_queue_fsm,acdc_queue_strategy,acdc_callback_recovery_io]),halt(0).'
erl -pa "$bridge_output/production" -pa "$bridge_output/test" -noshell -eval '
    Root=os:getenv("ACDC_ORDINARY_BRIDGE_OUTPUT"),
    {module,acdc_queue_fsm}=code:ensure_loaded(acdc_queue_fsm),
    Expected=filename:join([Root,"test","acdc_queue_fsm.beam"]),Expected=code:which(acdc_queue_fsm),
    true=erlang:function_exported(acdc_queue_fsm,callback_test_state,1),
    Module=acdc_queue_strategy_tests,
    Tests=lists:sort([N || {N,0}<-Module:module_info(exports),
        lists:prefix("ordinary_",atom_to_list(N)),lists:suffix("_test",atom_to_list(N))]),
    6=length(Tests),io:format("Six ordinary bridge regression groups: ~p~n",[Tests]),
    case eunit:test([{test,Module,N} || N<-Tests],[verbose,{scale_timeouts,4}]) of ok->halt(0);_->halt(1) end.' \
    | tee "$bridge_output/eunit.log"
