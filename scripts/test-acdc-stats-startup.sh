#!/usr/bin/env bash
# Offline production startup/ETS proof. External root guard supplies bounded
# resources and a network namespace. No live app, service or retained-table work.
set -Eeuo pipefail
umask 077
[[ $# == 0 ]] || exit 64
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS ERL_INETRC
startup_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
startup_dir=$(/usr/bin/mktemp -d /tmp/kazoo-stats-startup.XXXXXX) || exit 73
[[ $startup_dir == /tmp/kazoo-stats-startup.* && -d $startup_dir && ! -L $startup_dir ]] || exit 73
readonly startup_root startup_dir
cd "$startup_root"
export ERL_LIBS="$startup_root/deps:$startup_root/core:$startup_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1 -no_dot_erlang'
export ERL_CRASH_DUMP="$startup_dir/erl_crash.dump"
export KAZOO_STARTUP_OUTPUT="$startup_dir"
startup_stage=pinning
startup_exit() {
    local startup_status=$?
    trap - EXIT
    if [[ -f "$startup_dir/inputs.sha256" ]] && ! sha256sum --check --status "$startup_dir/inputs.sha256"; then
        printf '%s\n' 'Startup source inputs changed; retained manifest.' >&2
        startup_status=99
    fi
    printf 'Stats startup stage=%s exit=%s; retained evidence: %s\n' "$startup_stage" "$startup_status" "$startup_dir"
    exit "$startup_status"
}
trap startup_exit EXIT
startup_sources=(applications/acdc/src/acdc_stats.erl
    applications/acdc/src/acdc_stats_migration.erl applications/acdc/src/acdc_dashboard_caller.erl
    applications/acdc/src/acdc_agent_stats.erl applications/acdc/src/acdc_dashboard_snapshot.erl
    core/kazoo_amqp/src/gen_listener.erl core/kazoo_amqp/src/listener_utils.erl
    core/kazoo_stdlib/src/kz_json.erl core/kazoo_stdlib/src/kz_term.erl
    core/kazoo_stdlib/src/props.erl core/kazoo_stdlib/src/kz_time.erl
    core/kazoo_stdlib/src/kz_module.erl)
startup_inputs=("${startup_sources[@]}" scripts/erlang-tests/acdc_stats_startup_tests.erl
    scripts/test-acdc-stats-startup.sh core/kazoo_etsmgr/src/kazoo_etsmgr_srv.erl
    applications/acdc/src/acdc_stats_sup.erl)
/usr/bin/find applications/acdc/src applications/acdc/include core/kazoo_stdlib/include \
    core/kazoo_amqp/include core/kazoo_amqp/src -type f -name '*.hrl' > "$startup_dir/headers.list"
LC_ALL=C sort -o "$startup_dir/headers.list" "$startup_dir/headers.list"
while IFS= read -r startup_header; do startup_inputs+=("$startup_header"); done < "$startup_dir/headers.list"
sha256sum "${startup_inputs[@]}" > "$startup_dir/inputs.sha256"
printf '%s\n' 'Scope: listed production modules compiled without TEST; other ERL_LIBS/OTP dependencies are prebuilt and unpinned. Real gen_listener and owner ETS migration; controlled external broker/config/monitor dependencies, no real consumption or live upgrade.' \
    | tee "$startup_dir/scope.log"
startup_stage=production_compile
erlc -Werror +warn_missing_spec +debug_info -I applications/acdc/src -I applications/acdc/include \
    -I core/kazoo_amqp/include -I core/kazoo_amqp/src \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' \
    -o "$startup_dir" "${startup_sources[@]}" 2>&1 | tee "$startup_dir/production-compile.log"
startup_stage=fixture_compile
erlc -Werror -I applications/acdc/src -o "$startup_dir" \
    scripts/erlang-tests/acdc_stats_startup_tests.erl 2>&1 | tee "$startup_dir/fixture-compile.log"
startup_stage=eunit
erl -noshell -pa "$startup_dir" -eval '
    Dir=os:getenv("KAZOO_STARTUP_OUTPUT"),
    Modules=[acdc_stats,acdc_stats_migration,acdc_dashboard_caller,acdc_agent_stats,
             acdc_dashboard_snapshot,gen_listener,listener_utils,kz_json,kz_term,props,kz_time,kz_module],
    lists:foreach(fun(M)->
        {module,M}=code:ensure_loaded(M),
        Expected=filename:join(Dir,atom_to_list(M)++".beam"),Expected=code:which(M),
        Options=proplists:get_value(options,M:module_info(compile),[]),
        false=lists:any(fun({d,'"'"'TEST'"'"'})->true;({d,'"'"'TEST'"'"',_})->true;
                          (export_all)->true;(_)->false end,Options)
    end,Modules),
    false=erlang:function_exported(acdc_stats,force_archive_data,0),
    false=erlang:function_exported(acdc_stats,cleanup_data,1),
    case eunit:test(acdc_stats_startup_tests,[verbose]) of ok->halt(0);_->halt(1) end.' \
    2>&1 | tee "$startup_dir/eunit.log"
startup_stage=complete
