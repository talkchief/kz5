#!/usr/bin/env bash
# Invoke only inside the root-coordinated resource guard and network namespace.
set -Eeuo pipefail
umask 077
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS ERL_INETRC
events_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
events_dir=$(mktemp -d /tmp/kazoo-dashboard-events.XXXXXX) || exit 73
[[ "$events_dir" == /tmp/kazoo-dashboard-events.* && -d "$events_dir" && ! -L "$events_dir" ]] || exit 73
readonly events_root events_dir
cd "$events_root"
export ERL_LIBS="$events_root/deps:$events_root/core:$events_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1 -no_dot_erlang'
export ERL_CRASH_DUMP="$events_dir/erl_crash.dump"
export TMPDIR="$events_dir"
export ACDC_DASHBOARD_EVENTS_PROOF="$events_dir"
events_complete=false
events_stage=inputs
events_exit() {
    local events_status=$? events_stable=false
    trap - EXIT
    if [[ -s "$events_dir/inputs.sha256" ]] && sha256sum --status --check "$events_dir/inputs.sha256"; then
        events_stable=true
    else
        printf 'Input pin verification failed; retained inputs.sha256 for diagnosis.\n' >&2
        events_status=1
    fi
    if [[ "$events_complete" != true ]]; then events_status=1; fi
    printf '{"exit_code":%s,"stage":"%s","complete":%s,"inputs_stable":%s,"provider":false,"network":false,"native_broker":false,"delivery_confirmed":false,"deployment":false}\n' \
        "$events_status" "$events_stage" "$events_complete" "$events_stable" > "$events_dir/receipt.json"
    printf 'Dashboard event proof exit %s; evidence: %s\n' "$events_status" "$events_dir"
    exit "$events_status"
}
trap events_exit EXIT
events_sources=(
    applications/acdc/src/kapi_acdc_dashboard_events.erl
    applications/acdc/src/acdc_dashboard_events.erl
    applications/acdc/src/acdc_stats.erl
    applications/acdc/src/acdc_stats_sup.erl
    applications/acdc/src/acdc_queue_handler.erl
    core/kazoo_stdlib/src/kz_json.erl
    core/kazoo_stdlib/src/kz_term.erl
    core/kazoo_stdlib/src/props.erl
    core/kazoo_amqp/src/api/kz_api.erl
    core/kazoo_amqp/src/api/kapi_conf.erl
    core/kazoo_amqp/src/kapi_definition.erl)
events_inputs=("${events_sources[@]}"
    scripts/test-acdc-dashboard-events.sh
    scripts/erlang-tests/acdc_dashboard_events_tests.erl
    doc/acdc_dashboard_events.md
    core/kazoo_apps/src/kz_amqp_worker.erl
    core/kazoo_amqp/src/kz_amqp_channel.erl
    core/kazoo_amqp/src/kz_amqp_util.erl
    core/kazoo_amqp/src/gen_listener.erl
    core/kazoo_amqp/src/listener_federator.erl
    applications/acdc/src/acdc_listener.erl
    applications/acdc/src/acdc_queue_manager.erl
    applications/acdc/src/acdc_queues_sup.erl
    applications/acdc/src/acdc_queue_sup.erl)
# Pin cached local Erlang dependencies actually available to ERL_LIBS, not only
# selected source files. Enumeration is checked, never hidden in substitution.
/usr/bin/find deps core applications -type f \
    \( -name '*.hrl' -o -path '*/ebin/*.beam' -o -path '*/ebin/*.app' \) \
    > "$events_dir/dependencies.list"
LC_ALL=C /usr/bin/sort -u -o "$events_dir/dependencies.list" "$events_dir/dependencies.list"
while IFS= read -r events_input; do events_inputs+=("$events_input"); done < "$events_dir/dependencies.list"
sha256sum "${events_inputs[@]}" > "$events_dir/inputs.sha256"
events_stage=production_compile
erlc -Werror +warn_missing_spec +debug_info -I applications/acdc/src -I applications/acdc/include \
    -I core/kazoo_amqp/include -I core/kazoo_amqp/src \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' \
    -o "$events_dir" "${events_sources[@]}" 2>&1 | tee "$events_dir/compile.log"
events_stage=fixture_compile
erlc -Werror -I applications/acdc/src -I applications/acdc/include -o "$events_dir" \
    scripts/erlang-tests/acdc_dashboard_events_tests.erl 2>&1 | tee "$events_dir/fixture-compile.log"
events_stage=tests
erl -no_dot_erlang -noshell -pa "$events_dir" -eval '
    Dir=os:getenv("ACDC_DASHBOARD_EVENTS_PROOF"),
    Mods=[kapi_acdc_dashboard_events,acdc_dashboard_events,acdc_stats,
          acdc_stats_sup,acdc_queue_handler,kz_json,kz_term,props,kz_api,kapi_conf,kapi_definition],
    [begin
        {module,M}=code:ensure_loaded(M),
        Expected=filename:join(Dir,atom_to_list(M)++".beam"),
        Expected=code:which(M),
        Opts=proplists:get_value(options,M:module_info(compile),[]),
        false=lists:member(export_all,Opts),
        false=lists:any(fun({d,'\''TEST'\''})->true; ({d,'\''TEST'\'',_})->true; (_)->false end,Opts)
     end || M<-Mods],
    false=erlang:function_exported(acdc_stats,force_archive_data,0),
    case eunit:test(acdc_dashboard_events_tests,[verbose]) of ok->halt(0);_->halt(1) end.
' 2>&1 | tee "$events_dir/eunit.log"
events_stage=complete
events_complete=true
