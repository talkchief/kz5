#!/usr/bin/env bash
# REJECTED candidate regression: expected to fail paused-worker detection.
# Never install its BEAMs. See doc/dashboard_caller_identity_upgrade.md.
set -Eeuo pipefail
umask 077
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
drain_dir=$(mktemp -d /tmp/kazoo-stats-upgrade-drain.XXXXXX)
cd "$project_root"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP="$drain_dir/erl_crash.dump"
export KAZOO_DRAIN_OUTPUT="$drain_dir"
drain_exit() {
    local drain_status=$?
    trap - EXIT
    if [[ -f "$drain_dir/inputs.sha256" ]]; then
        if ! sha256sum --check "$drain_dir/inputs.sha256"; then drain_status=99; fi
    fi
    printf 'Stats upgrade drain exit %s; retained evidence: %s\n' "$drain_status" "$drain_dir"
    exit "$drain_status"
}
trap drain_exit EXIT
sha256sum scripts/erlang-tests/candidates/acdc_stats_upgrade_drain.erl core/kazoo_stdlib/src/kz_process.erl \
    core/kazoo_amqp/src/gen_listener.erl core/kazoo_amqp/src/kz_amqp_channel.erl \
    applications/acdc/src/acdc_stats.erl \
    applications/acdc/src/acdc_stats_sup.erl core/kazoo_etsmgr/src/kazoo_etsmgr_srv.erl \
    core/kazoo_stdlib/include/kz_types.hrl \
    scripts/erlang-tests/acdc_stats_upgrade_drain_tests.erl scripts/experiments/reproduce-stats-upgrade-drain.sh \
    > "$drain_dir/inputs.sha256"
erlc -Werror +warn_missing_spec +debug_info -o "$drain_dir" \
    scripts/erlang-tests/candidates/acdc_stats_upgrade_drain.erl core/kazoo_stdlib/src/kz_process.erl
erlc -Werror -o "$drain_dir" scripts/erlang-tests/acdc_stats_upgrade_drain_tests.erl
printf '%s\n' 'Two production modules rebuilt without TEST; meck and other dependencies use unrebuilt workspace beams.'
erl -noshell -pa "$drain_dir" -eval '
    Dir=os:getenv("KAZOO_DRAIN_OUTPUT"),
    lists:foreach(fun(M)->
        {module,M}=code:ensure_loaded(M),Expected=filename:join(Dir,atom_to_list(M)++".beam"),Expected=code:which(M),
        false=lists:any(fun({d,'"'"'TEST'"'"'})->true;({d,'"'"'TEST'"'"',_})->true;(_)->false end,
            proplists:get_value(options,M:module_info(compile),[]))
    end,[acdc_stats_upgrade_drain,kz_process]),
    case eunit:test(acdc_stats_upgrade_drain_tests,[verbose]) of ok->halt(0);_->halt(1) end.' \
    | tee "$drain_dir/eunit.log"
