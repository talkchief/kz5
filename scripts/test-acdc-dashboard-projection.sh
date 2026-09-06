#!/usr/bin/env bash
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
projection_test_dir=$(mktemp -d /tmp/kazoo-dashboard-projection.XXXXXX)
cd "$project_root"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP="$projection_test_dir/erl_crash.dump"
projection_inputs=(applications/acdc/src/acdc_dashboard_projection.erl
    applications/acdc/src/acdc_stats.hrl
    scripts/erlang-tests/acdc_dashboard_projection_tests.erl
    scripts/test-acdc-dashboard-projection.sh)
sha256sum "${projection_inputs[@]}" > "$projection_test_dir/inputs.sha256"
erlc -Werror +warn_missing_spec -I applications/acdc/src -o "$projection_test_dir" \
    applications/acdc/src/acdc_dashboard_projection.erl
erlc -Werror -I applications/acdc/src -o "$projection_test_dir" \
    scripts/erlang-tests/acdc_dashboard_projection_tests.erl
erl -pa "$projection_test_dir" -noshell -eval \
    'case eunit:test(acdc_dashboard_projection_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.' \
    | tee "$projection_test_dir/eunit.log"
sha256sum --check "$projection_test_dir/inputs.sha256"
printf 'Projection checks passed; retained evidence: %s\n' "$projection_test_dir"
