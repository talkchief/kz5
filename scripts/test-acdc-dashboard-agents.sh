#!/usr/bin/env bash
# Offline production-source protocol proof; does not start real agents/brokers.
set -Eeuo pipefail
umask 077
[[ $# == 0 ]] || exit 2
agents_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
agents_output=$(mktemp -d /tmp/kazoo-dashboard-agents.XXXXXX)
cd "$agents_root"
agents_finish() {
    local agents_status=$?
    trap - EXIT
    for agents_manifest in inputs.sha256 artifacts.sha256; do
        if [[ -f $agents_output/$agents_manifest ]] &&
           ! sha256sum --check --status "$agents_output/$agents_manifest"; then agents_status=99; fi
    done
    printf 'Runtime agents proof exit=%s; retained evidence: %s\n' "$agents_status" "$agents_output"
    exit "$agents_status"
}
trap agents_finish EXIT
agents_sources=(applications/acdc/src/acdc_dashboard_agents.erl
    applications/acdc/src/acdc_agent_fsm.erl applications/acdc/src/acdc_agent_sup.erl)
agents_inputs=("${agents_sources[@]}" scripts/test-acdc-dashboard-agents.sh
    scripts/erlang-tests/acdc_dashboard_agents_tests.erl
    core/kazoo_amqp/ebin/gen_listener.beam core/kazoo_stdlib/ebin/kz_binary.beam)
/usr/bin/find deps/gproc/ebin deps/lager/ebin -type f -name '*.beam' > "$agents_output/dependencies.list"
/usr/bin/find applications/acdc/src applications/acdc/include core/kazoo_stdlib/include core/kazoo_amqp/include \
    deps/amqp_client/include deps/rabbit_common/include -type f -name '*.hrl' > "$agents_output/headers.list"
while IFS= read -r agents_input; do agents_inputs+=("$agents_input"); done < "$agents_output/dependencies.list"
while IFS= read -r agents_input; do agents_inputs+=("$agents_input"); done < "$agents_output/headers.list"
for agents_input in "${agents_inputs[@]}"; do [[ -f $agents_input && ! -L $agents_input ]] || exit 2; done
sha256sum "${agents_inputs[@]}" > "$agents_output/inputs.sha256"
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS ERL_INETRC
export ERL_LIBS="$agents_root/deps:$agents_root/core:$agents_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1' ERL_CRASH_DUMP="$agents_output/erl_crash.dump"
erlc -Werror +debug_info -I applications/acdc/src -I applications/acdc/include -pa deps/lager/ebin \
    +'{parse_transform,lager_transform}' -o "$agents_output" "${agents_sources[@]}" \
    2>&1 | tee "$agents_output/compile.log"
erlc -Werror +debug_info -o "$agents_output" scripts/erlang-tests/acdc_dashboard_agents_tests.erl
sha256sum "$agents_output"/*.beam > "$agents_output/artifacts.sha256"
export KAZOO_DASHBOARD_AGENTS_OUTPUT="$agents_output"
erl -noshell -pa "$agents_output" -eval '
Out=os:getenv("KAZOO_DASHBOARD_AGENTS_OUTPUT"),
Gate=fun()->lists:foreach(fun(M)->
    {module,M}=code:ensure_loaded(M),Expected=filename:join(Out,atom_to_list(M)++".beam"),
    Expected=code:which(M),{ok,{M,MD5}}=beam_lib:md5(Expected),MD5=M:module_info(md5),
    Opts=proplists:get_value(options,M:module_info(compile),[]),
    false=lists:any(fun({d,'\''TEST'\''})->true;({d,'\''TEST'\'',_})->true;(export_all)->true;(_)->false end,Opts)
end,[acdc_dashboard_agents,acdc_agent_fsm,acdc_agent_sup]) end,
Gate(),Result=eunit:test(acdc_dashboard_agents_tests,[verbose]),Gate(),
case Result of ok->halt(0);_->halt(1) end.' 2>&1 | tee "$agents_output/eunit.log"
