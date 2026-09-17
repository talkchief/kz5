#!/usr/bin/env bash
# Offline regression for queue-manager cancellation markers and the delivery
# owner's settlement announcement. Compiles into an isolated directory; never
# touches live BEAMs, a broker or calls. Use --baseline for the expected failure
# against the preceding source.
set -Eeuo pipefail
umask 077
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS ERL_INETRC
marker_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
marker_mode=${1:-current}
[[ $# -le 1 && ( $marker_mode == current || $marker_mode == --baseline ) ]] || { printf 'Use no arguments or --baseline\n' >&2; exit 2; }
marker_output=$(mktemp -d /tmp/kazoo-acdc-cancel-markers.XXXXXX)
marker_exit() {
    local marker_code=$?
    trap - EXIT
    printf 'Cancellation marker regression %s exit %s; retained evidence: %s\n' "$marker_mode" "$marker_code" "$marker_output"
    exit "$marker_code"
}
trap marker_exit EXIT
cd "$marker_root"
export ERL_LIBS="$marker_root/deps:$marker_root/core:$marker_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
marker_source=applications/acdc/src
if [[ $marker_mode == --baseline ]]; then
    marker_source="$marker_output/baseline-src"
    mkdir -p "$marker_source"
    git rev-parse --verify 'd14880e^{commit}' > "$marker_output/baseline-commit.txt"
    git archive d14880e applications/acdc/src applications/acdc/include | tar -x -C "$marker_output"
    marker_source="$marker_output/applications/acdc/src"
fi
marker_modules=(acdc_queue_manager acdc_queue_listener kapi_acdc_queue acdc_queue_member)
marker_files=()
for marker_module in "${marker_modules[@]}"; do marker_files+=("$marker_source/$marker_module.erl"); done
sha256sum "${marker_files[@]}" scripts/erlang-tests/acdc_queue_cancel_marker_tests.erl > "$marker_output/inputs.sha256"
mkdir "$marker_output/ebin"
# Production warning flags; TEST only exposes the existing listener state helper.
erlc -DTEST -Werror +debug_info +warn_unused_vars +warn_unused_import \
    -I "$marker_source" -I "$(dirname "$marker_source")/include" -I applications \
    -pa deps/lager/ebin '+{parse_transform,lager_transform}' -o "$marker_output/ebin" "${marker_files[@]}"
marker_compile_test=0
marker_define=()
[[ $marker_mode == --baseline ]] && marker_define=(-DBASELINE)
erlc "${marker_define[@]}" -Werror -I "$marker_source" -I "$(dirname "$marker_source")/include" -o "$marker_output/ebin" \
    scripts/erlang-tests/acdc_queue_cancel_marker_tests.erl > "$marker_output/test-compile.log" 2>&1 || marker_compile_test=$?
if (( marker_compile_test != 0 )); then
    cat "$marker_output/test-compile.log"
    printf 'Fixture does not compile against this source (expected only for --baseline).\n'
    exit 1
fi
KAZOO_CONFIG="$marker_root/rel/config-test.ini" erl -pa "$marker_output/ebin" -noshell -eval '
    case eunit:test(acdc_queue_cancel_marker_tests,[verbose,{scale_timeouts,4}]) of ok->halt(0);_->halt(1) end.' \
    | tee "$marker_output/eunit.log"
