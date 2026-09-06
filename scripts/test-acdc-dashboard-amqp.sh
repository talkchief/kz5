#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
dashboard_amqp_dir=$(mktemp -d /tmp/kazoo-dashboard-amqp.XXXXXX)
cd "$project_root"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP="$dashboard_amqp_dir/erl_crash.dump"
dashboard_exit() {
    local dashboard_status=$?
    trap - EXIT
    if [[ -f "$dashboard_amqp_dir/inputs.sha256" ]]; then
        if ! sha256sum --check "$dashboard_amqp_dir/inputs.sha256"; then dashboard_status=1; fi
    fi
    printf 'Dashboard AMQP checks exit %s; retained evidence: %s\n' "$dashboard_status" "$dashboard_amqp_dir"
    exit "$dashboard_status"
}
trap dashboard_exit EXIT
dashboard_sources=(applications/acdc/src/kapi_acdc_dashboard.erl
    applications/acdc/src/acdc_dashboard_snapshot.erl
    applications/acdc/src/acdc_dashboard_collector.erl
    applications/acdc/src/acdc_dashboard_projection.erl
    applications/acdc/src/acdc_stats.erl applications/acdc/src/acdc_stats_sup.erl
    core/kazoo_stdlib/src/kz_json.erl core/kazoo_stdlib/src/kz_term.erl
    core/kazoo_stdlib/src/props.erl core/kazoo_amqp/src/api/kz_api.erl
    core/kazoo_amqp/src/listener_federator.erl core/kazoo_amqp/src/kz_amqp_util.erl)
dashboard_inputs=("${dashboard_sources[@]}"
    scripts/erlang-tests/acdc_dashboard_amqp_tests.erl scripts/test-acdc-dashboard-amqp.sh
    core/kazoo_etsmgr/src/kazoo_etsmgr_srv.erl core/kazoo_amqp/src/gen_listener.erl
    core/kazoo_amqp/src/kz_amqp_channel.erl core/kazoo_apps/src/kz_amqp_worker.erl)
# The resource guard uses a minimal PATH. Enumeration failure must abort,
# never disappear in a process substitution and silently omit header pins.
/usr/bin/find applications/acdc/src core/kazoo_stdlib/include core/kazoo_amqp/include \
    -type f -name '*.hrl' > "$dashboard_amqp_dir/headers.list"
LC_ALL=C /usr/bin/sort -o "$dashboard_amqp_dir/headers.list" "$dashboard_amqp_dir/headers.list"
while IFS= read -r dashboard_header; do dashboard_inputs+=("$dashboard_header"); done < "$dashboard_amqp_dir/headers.list"
sha256sum "${dashboard_inputs[@]}" > "$dashboard_amqp_dir/inputs.sha256"
erlc -Werror +warn_missing_spec +debug_info -I applications/acdc/src -I applications/acdc/include \
    -I core/kazoo_amqp/include -I core/kazoo_amqp/src \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' -o "$dashboard_amqp_dir" \
    "${dashboard_sources[@]}"
erlc -Werror -I applications/acdc/src -o "$dashboard_amqp_dir" \
    scripts/erlang-tests/acdc_dashboard_amqp_tests.erl
erl -noshell -pa "$dashboard_amqp_dir" \
    -eval 'case eunit:test(acdc_dashboard_amqp_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.' \
    | tee "$dashboard_amqp_dir/eunit.log"
