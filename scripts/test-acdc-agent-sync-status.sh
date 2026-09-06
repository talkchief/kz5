#!/usr/bin/env bash
# Offline actual before/after prepare/publish proof; never start agents or a broker.
set -Eeuo pipefail
umask 077
[[ $# == 0 ]] || exit 2
sync_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
sync_output=$(mktemp -d /tmp/kazoo-agent-sync-status.XXXXXX)
readonly sync_baseline=d69cf045ecb1118b6b6e806d93e1b9a4dab5d8e2
readonly sync_baseline_sha=5fa6d863110327116c7be0f8323720441aa850dcee87539c963cd35e09668611
cd "$sync_root"
sync_finish() {
    local sync_status=$?
    trap - EXIT
    for sync_manifest in inputs.sha256 staged.sha256 artifacts.sha256; do
        if [[ -f $sync_output/$sync_manifest ]] &&
           ! sha256sum --check --status "$sync_output/$sync_manifest"; then sync_status=99; fi
    done
    printf 'Agent sync status proof exit=%s; retained evidence: %s\n' "$sync_status" "$sync_output"
    exit "$sync_status"
}
trap sync_finish EXIT
sync_common=(core/kazoo_amqp/src/api/kz_api.erl core/kazoo_stdlib/src/kz_json.erl
    core/kazoo_stdlib/src/kz_term.erl core/kazoo_stdlib/src/props.erl core/kazoo_stdlib/src/kz_log.erl)
sync_dependencies=(core/kazoo_amqp/ebin/kz_amqp_util.beam
    core/kazoo_stdlib/ebin/kz_binary.beam core/kazoo_stdlib/ebin/kz_time.beam
    deps/lager/ebin/lager.beam deps/lager/ebin/lager_config.beam
    deps/lager/ebin/lager_transform.beam deps/lager/ebin/lager_util.beam
    deps/meck/ebin/meck.beam deps/meck/ebin/meck_args_matcher.beam
    deps/meck/ebin/meck_code.beam deps/meck/ebin/meck_code_gen.beam
    deps/meck/ebin/meck_cover.beam deps/meck/ebin/meck_expect.beam
    deps/meck/ebin/meck_history.beam deps/meck/ebin/meck_matcher.beam
    deps/meck/ebin/meck_proc.beam deps/meck/ebin/meck_ret_spec.beam deps/meck/ebin/meck_util.beam
    deps/jiffy/ebin/jiffy.beam deps/jiffy/ebin/jiffy_utf8.beam)
sync_inputs=("${sync_common[@]}" "${sync_dependencies[@]}"
    scripts/test-acdc-agent-sync-status.sh scripts/erlang-tests/acdc_agent_sync_status_tests.erl
    applications/acdc/src/kapi_acdc_agent.erl applications/acdc/src/acdc_agent_fsm.erl
    applications/acdc/src/acdc_agent_listener.erl applications/acdc/src/acdc_agent_sup.erl
    core/kazoo_amqp/src/kz_amqp_util.hrl deps/jiffy/ebin/jiffy.app deps/jiffy/priv/jiffy.so)
/usr/bin/find applications/acdc/src core/kazoo_stdlib/include core/kazoo_amqp/include \
    deps/amqp_client/include deps/rabbit_common/include -type f -name '*.hrl' > "$sync_output/headers.list"
LC_ALL=C /usr/bin/sort -o "$sync_output/headers.list" "$sync_output/headers.list"
while IFS= read -r sync_header; do sync_inputs+=("$sync_header"); done < "$sync_output/headers.list"
for sync_input in "${sync_inputs[@]}"; do
    [[ -f $sync_input && ! -L $sync_input ]] || { printf 'Unsafe/missing input: %s\n' "$sync_input" >&2; exit 2; }
done
sha256sum "${sync_inputs[@]}" > "$sync_output/inputs.sha256"
mkdir -m 0700 "$sync_output/common" "$sync_output/baseline" "$sync_output/candidate"
# Read an exact locally available revision; no checkout, reset, fetch or source mutation.
git --no-replace-objects show "$sync_baseline:applications/acdc/src/kapi_acdc_agent.erl" > "$sync_output/baseline/kapi_acdc_agent.erl"
printf '%s  %s\n' "$sync_baseline_sha" "$sync_output/baseline/kapi_acdc_agent.erl" | sha256sum --check
cp -- applications/acdc/src/kapi_acdc_agent.erl "$sync_output/candidate/kapi_acdc_agent.erl"
sha256sum "$sync_output/baseline/kapi_acdc_agent.erl" "$sync_output/candidate/kapi_acdc_agent.erl" > "$sync_output/staged.sha256"
printf '%s\n' "$sync_baseline" > "$sync_output/baseline-revision.txt"
printf '%s\n' "${sync_dependencies[@]}" > "$sync_output/dependencies.list"
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS ERL_INETRC
export ERL_LIBS="$sync_root/deps:$sync_root/core:$sync_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1' ERL_CRASH_DUMP="$sync_output/erl_crash.dump"
sync_flags=(-Werror +debug_info -I applications/acdc/src -I core/kazoo_amqp/src
    -I core/kazoo_amqp/include -pa deps/lager/ebin +'{parse_transform,lager_transform}')
erlc "${sync_flags[@]}" -o "$sync_output/common" "${sync_common[@]}" 2>&1 | tee "$sync_output/common-compile.log"
for sync_mode in baseline candidate; do
    erlc "${sync_flags[@]}" -o "$sync_output/$sync_mode" "$sync_output/$sync_mode/kapi_acdc_agent.erl" \
        2>&1 | tee "$sync_output/$sync_mode/compile.log"
done
erlc -Werror +debug_info -o "$sync_output/common" scripts/erlang-tests/acdc_agent_sync_status_tests.erl \
    2>&1 | tee "$sync_output/fixture-compile.log"
sha256sum "$sync_output/common"/*.beam "$sync_output/baseline"/*.beam "$sync_output/candidate"/*.beam > "$sync_output/artifacts.sha256"
export KAZOO_SYNC_STATUS_ROOT="$sync_root" KAZOO_SYNC_STATUS_OUTPUT="$sync_output"
for sync_mode in baseline candidate; do
    export KAZOO_SYNC_STATUS_MODE="$sync_mode"
    erl -noshell -pa "$sync_output/common" "$sync_output/$sync_mode" -eval '
Root=os:getenv("KAZOO_SYNC_STATUS_ROOT"), Out=os:getenv("KAZOO_SYNC_STATUS_OUTPUT"),
Mode=os:getenv("KAZOO_SYNC_STATUS_MODE"),
{ok,DepBytes}=file:read_file(filename:join(Out,"dependencies.list")),
Dependencies=[binary_to_list(P) || P<-binary:split(DepBytes,<<"\n">>,[global]),P=/= <<>>],
{ok,Old}=file:read_file(filename:join([Out,"baseline","kapi_acdc_agent.erl"])),
{ok,New}=file:read_file(filename:join([Out,"candidate","kapi_acdc_agent.erl"])),
Delta = <<"                                          ,<<\"outbound\">>\n">>,
[_]=binary:matches(New,Delta), Old=binary:replace(New,Delta,<<>>),
Gate=fun()->
    lists:foreach(fun({M,Dir})->
        {module,M}=code:ensure_loaded(M), Expected=filename:join([Out,Dir,atom_to_list(M)++".beam"]),
        Expected=code:which(M), {ok,{M,MD5}}=beam_lib:md5(Expected), MD5=M:module_info(md5),
        Opts=proplists:get_value(options,M:module_info(compile),[]),
        true=lists:member({parse_transform,lager_transform},Opts),
        false=lists:any(fun({d,'\''TEST'\''})->true;({d,'\''TEST'\'',_})->true;(export_all)->true;(_)->false end,Opts)
    end,[{kapi_acdc_agent,Mode}|[{M,"common"} || M<-[kz_api,kz_json,kz_term,props,kz_log]]]),
    lists:foreach(fun(P)->M=list_to_atom(filename:basename(P,".beam")),
        {module,M}=code:ensure_loaded(M), Expected=filename:join(Root,P), Expected=code:which(M)
    end,Dependencies),
    Jiffy=filename:join([Root,"deps","jiffy","priv"]), Jiffy=code:priv_dir(jiffy),
    {module,acdc_agent_sync_status_tests}=code:ensure_loaded(acdc_agent_sync_status_tests),
    Fixture=filename:join([Out,"common","acdc_agent_sync_status_tests.beam"]),
    Fixture=code:which(acdc_agent_sync_status_tests)
end,
Gate(), Result=eunit:test(acdc_agent_sync_status_tests,[verbose]), Gate(),
io:format("PASS ~s actual production no-DTEST/path/MD5 checks before/after~n",[Mode]),
case Result of ok->halt(0);_->halt(1) end.' 2>&1 | tee "$sync_output/$sync_mode/eunit.log"
done
printf 'PASS actual historical failure/control and current status serialization; broker sink substituted, no live agent proof\n'
