#!/usr/bin/env bash
# Offline candidate proof only. Parent orchestration supplies resource/network
# isolation. No services, provider calls, datastore or retained-table migration.
set -Eeuo pipefail
umask 077
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
caller_dir=$(mktemp -d /tmp/kazoo-dashboard-caller.XXXXXX)
cd "$project_root"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP="$caller_dir/erl_crash.dump"
export KAZOO_CALLER_OUTPUT="$caller_dir"
caller_exit() {
    local caller_status=$?
    trap - EXIT
    if [[ -f "$caller_dir/inputs.sha256" ]]; then
        if ! sha256sum --check "$caller_dir/inputs.sha256"; then caller_status=99; fi
    fi
    printf 'Dashboard caller checks exit %s; retained evidence: %s\n' "$caller_status" "$caller_dir"
    exit "$caller_status"
}
trap caller_exit EXIT
caller_sources=(applications/acdc/src/acdc_dashboard_caller.erl
    applications/acdc/src/acdc_queue_manager.erl applications/acdc/src/acdc_stats.erl
    applications/acdc/src/kapi_acdc_stats.erl core/kazoo_endpoint/src/kz_privacy.erl
    core/kazoo_call/src/kapps_call.erl core/kazoo_stdlib/src/kz_json.erl
    core/kazoo_stdlib/src/kz_term.erl core/kazoo_stdlib/src/props.erl
    core/kazoo_stdlib/src/kz_time.erl core/kazoo_amqp/src/api/kz_api.erl
    core/kazoo_data/src/kzs_util.erl)
caller_inputs=("${caller_sources[@]}" scripts/test-acdc-dashboard-caller.sh
    scripts/erlang-tests/acdc_dashboard_caller_tests.erl)
caller_header_roots=(applications/acdc/src applications/acdc/include
    core/kazoo_stdlib/include core/kazoo_amqp/include core/kazoo_amqp/src
    core/kazoo_endpoint/src core/kazoo_call/src core/kazoo_call/include
    core/kazoo_numbers/include core/kazoo_sip/include core/kazoo_data/src
    core/kazoo_documents/include)
# No process substitution: enumeration failure must not silently omit pins.
if command -v rg >/dev/null 2>&1; then
    rg --files --hidden --no-ignore -g '*.hrl' "${caller_header_roots[@]}" > "$caller_dir/headers.list"
else
    /usr/bin/find "${caller_header_roots[@]}" -type f -name '*.hrl' > "$caller_dir/headers.list"
fi
LC_ALL=C sort -o "$caller_dir/headers.list" "$caller_dir/headers.list"
while IFS= read -r caller_header; do caller_inputs+=("$caller_header"); done < "$caller_dir/headers.list"
sha256sum "${caller_inputs[@]}" > "$caller_dir/inputs.sha256"
printf '%s\n' 'Production no-TEST/-Werror build; remaining runtime dependencies are existing, unrebuilt workspace beams.'
erlc -Werror +warn_missing_spec +debug_info \
    -I applications/acdc/src -I applications/acdc/include \
    -I core/kazoo_amqp/include -I core/kazoo_amqp/src \
    -I core/kazoo_endpoint/src -I core/kazoo_call/src -I core/kazoo_call/include -I core/kazoo_data/src \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' -o "$caller_dir" \
    "${caller_sources[@]}"
erlc -Werror -I applications/acdc/src -o "$caller_dir" \
    scripts/erlang-tests/acdc_dashboard_caller_tests.erl
erl -noshell -pa "$caller_dir" -eval '
    Dir=os:getenv("KAZOO_CALLER_OUTPUT"),
    Modules=[acdc_dashboard_caller,acdc_queue_manager,acdc_stats,kapi_acdc_stats,
             kz_privacy,kapps_call,kz_json,kz_term,props,kz_time,kz_api,kzs_util],
    lists:foreach(fun(M) ->
        {module,M}=code:ensure_loaded(M),
        Expected=filename:join(Dir,atom_to_list(M)++".beam"),
        Expected=code:which(M),
        Options=proplists:get_value(options,M:module_info(compile),[]),
        false=lists:any(fun({d,'"'"'TEST'"'"'}) -> true;
                           ({d,'"'"'TEST'"'"',_}) -> true; (_) -> false end,Options)
    end,Modules),
    case eunit:test(acdc_dashboard_caller_tests,[verbose]) of ok -> halt(0); _ -> halt(1) end.' \
    | tee "$caller_dir/eunit.log"
