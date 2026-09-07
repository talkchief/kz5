#!/usr/bin/env bash
# Offline real-ETS owner/heir proof, not deployed lifecycle admission proof.
set -Eeuo pipefail
umask 077
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
migration_dir=$(mktemp -d /tmp/kazoo-stats-migration.XXXXXX)
cd "$project_root"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP="$migration_dir/erl_crash.dump"
export KAZOO_MIGRATION_OUTPUT="$migration_dir"
migration_exit() {
    local migration_status=$?
    trap - EXIT
    if [[ -f "$migration_dir/inputs.sha256" ]]; then
        if ! sha256sum --check "$migration_dir/inputs.sha256"; then migration_status=99; fi
    fi
    printf 'Stats migration validation exit %s; retained evidence: %s\n' "$migration_status" "$migration_dir"
    exit "$migration_status"
}
trap migration_exit EXIT
sha256sum applications/acdc/src/acdc_stats_migration.erl \
    applications/acdc/src/acdc_dashboard_caller.erl applications/acdc/src/acdc_stats.hrl \
    scripts/erlang-tests/acdc_stats_migration_tests.erl scripts/test-acdc-stats-migration.sh \
    > "$migration_dir/inputs.sha256"
erlc -Werror +warn_missing_spec +debug_info -I applications/acdc/src -o "$migration_dir" \
    applications/acdc/src/acdc_dashboard_caller.erl applications/acdc/src/acdc_stats_migration.erl
erlc -Werror -I applications/acdc/src -o "$migration_dir" \
    scripts/erlang-tests/acdc_stats_migration_tests.erl
erl -noshell -pa "$migration_dir" -eval '
    {ok,_}=application:ensure_all_started(crypto),
    Dir=os:getenv("KAZOO_MIGRATION_OUTPUT"),
    lists:foreach(fun(M) ->
        {module,M}=code:ensure_loaded(M),
        Expected=filename:join(Dir,atom_to_list(M)++".beam"),Expected=code:which(M),
        false=lists:any(fun({d,'"'"'TEST'"'"'}) -> true; ({d,'"'"'TEST'"'"',_}) -> true; (_) -> false end,
            proplists:get_value(options,M:module_info(compile),[]))
    end,[acdc_stats_migration,acdc_dashboard_caller]),
    case eunit:test(acdc_stats_migration_tests,[verbose]) of ok -> halt(0); _ -> halt(1) end.' \
    | tee "$migration_dir/eunit.log"
