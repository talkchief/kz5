#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
collector_test_dir=$(mktemp -d /tmp/kazoo-dashboard-collector.XXXXXX)
cd "$project_root"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP="$collector_test_dir/erl_crash.dump"
collector_inputs=(applications/acdc/src/acdc_dashboard_collector.erl
    applications/acdc/src/acdc_dashboard_caller.erl
    applications/acdc/src/acdc_dashboard_snapshot.erl
    applications/acdc/src/acdc_dashboard_projection.erl
    applications/acdc/src/acdc_stats.hrl
    scripts/erlang-tests/acdc_dashboard_collector_tests.erl
    scripts/test-acdc-dashboard-collector.sh)
collector_exit() {
    local collector_status=$?
    trap - EXIT
    if [[ -f "$collector_test_dir/inputs.sha256" ]]; then
        if ! sha256sum --check "$collector_test_dir/inputs.sha256"; then collector_status=1; fi
    fi
    printf 'Collector validation exit %s; retained private evidence: %s\n' "$collector_status" "$collector_test_dir"
    exit "$collector_status"
}
trap collector_exit EXIT
sha256sum "${collector_inputs[@]}" > "$collector_test_dir/inputs.sha256"
erlc -Werror +warn_missing_spec -I applications/acdc/src -o "$collector_test_dir" \
    applications/acdc/src/acdc_dashboard_caller.erl \
    applications/acdc/src/acdc_dashboard_projection.erl \
    applications/acdc/src/acdc_dashboard_collector.erl
erlc -Werror -I applications/acdc/src -o "$collector_test_dir" \
    scripts/erlang-tests/acdc_dashboard_collector_tests.erl
erl -pa "$collector_test_dir" -noshell -eval \
    'Dir=filename:dirname(code:which(acdc_dashboard_collector_tests)),
     lists:foreach(fun(M) ->
         {module,M}=code:ensure_loaded(M),
         Dir=filename:dirname(code:which(M)),
         false=lists:any(fun({d,'"'"'TEST'"'"'}) -> true; ({d,'"'"'TEST'"'"',_}) -> true; (_) -> false end,
             proplists:get_value(options,M:module_info(compile),[]))
     end,[acdc_dashboard_collector,acdc_dashboard_projection,acdc_dashboard_caller]),
     case eunit:test(acdc_dashboard_collector_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.' \
    | tee "$collector_test_dir/eunit.log"
printf 'Collector checks passed; retained evidence: %s\n' "$collector_test_dir"
