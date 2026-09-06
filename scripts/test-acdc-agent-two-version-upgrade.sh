#!/usr/bin/env bash
# Isolated actual two-version rehearsal; one fresh VM per case, no purge/live writes.
set -Eeuo pipefail
umask 077
[[ $# == 0 ]] || exit 2
upgrade_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
upgrade_fixture=$upgrade_root/scripts/erlang-tests/acdc_agent_two_version_tests.erl
[[ $(</proc/self/cgroup) =~ ^0::/system.slice/kazoo-validation-[a-f0-9-]{36}\.service$ ]] || {
    printf 'Resource guard required\n' >&2; exit 2;
}
[[ $(readlink /proc/self/ns/net) != "$(readlink /proc/1/ns/net)" ]] || {
    printf 'Private network namespace required\n' >&2; exit 2;
}
ip -json link show | node -e '
let s="";process.stdin.on("data",b=>s+=b);process.stdin.on("end",()=>{
 const links=JSON.parse(s);if(links.length!==1||links[0].ifname!=="lo")process.exit(1);
});'
cd "$upgrade_root"
upgrade_output=$(mktemp -d /tmp/kazoo-acdc-two-version-run.XXXXXX) || exit 2
upgrade_complete=0
printf 'Two-version retained evidence: %s\n' "$upgrade_output"
upgrade_candidate=$upgrade_output/source
mkdir -p "$upgrade_candidate/legacy/src" "$upgrade_candidate/current/src"
# Historical source must already exist in local Git history. Never fetch it.
upgrade_legacy_commit=83194e7252f84ce72ce07c72f03c3956acdeb9d4
for upgrade_name in acdc_agent_fsm.erl acdc.hrl; do
    upgrade_git_path=applications/acdc/src/$upgrade_name
    git --no-replace-objects cat-file blob "$upgrade_legacy_commit:$upgrade_git_path" \
        >"$upgrade_candidate/legacy/src/$upgrade_name"
    printf 'legacy %s %s\n' "$upgrade_legacy_commit" "$upgrade_git_path" >>"$upgrade_output/git-source-identity.txt"
    git --no-replace-objects rev-parse "$upgrade_legacy_commit:$upgrade_git_path" >>"$upgrade_output/git-source-identity.txt"
done
printf '%s  %s\n' \
    2424cf2f392edbde02bbdd3bceeccf436630f98ed1ded129813ba7125fdebf30 "$upgrade_candidate/legacy/src/acdc_agent_fsm.erl" \
    f333ea275c22bc9eed503e9ab18b9210209e3889a6f938a1a5330cc1cbd78cea "$upgrade_candidate/legacy/src/acdc.hrl" \
    >"$upgrade_output/legacy-source.sha256"
sha256sum --check --status "$upgrade_output/legacy-source.sha256"
# Current working-tree bytes, not a historical HEAD name, are authoritative.
# Hash before copying, then verify both the copied bytes and original identity.
sha256sum applications/acdc/src/acdc_agent_fsm.erl applications/acdc/src/acdc.hrl \
    >"$upgrade_output/current-source-before.sha256"
for upgrade_name in acdc_agent_fsm.erl acdc.hrl; do
    cp -- "applications/acdc/src/$upgrade_name" "$upgrade_candidate/current/src/$upgrade_name"
    cmp "applications/acdc/src/$upgrade_name" "$upgrade_candidate/current/src/$upgrade_name"
done
sha256sum --check --status "$upgrade_output/current-source-before.sha256"
printf 'current_source=working-tree-bytes\n' >>"$upgrade_output/git-source-identity.txt"
git --no-replace-objects rev-parse --verify HEAD >>"$upgrade_output/git-source-identity.txt"
upgrade_inputs=(
    "$upgrade_root/scripts/test-acdc-agent-two-version-upgrade.sh" "$upgrade_fixture"
    "$upgrade_candidate/legacy/src/acdc_agent_fsm.erl" "$upgrade_candidate/legacy/src/acdc.hrl"
    "$upgrade_candidate/current/src/acdc_agent_fsm.erl" "$upgrade_candidate/current/src/acdc.hrl"
    applications/acdc/src/acdc_agent_fsm.erl applications/acdc/src/acdc.hrl
    applications/acdc/include/acdc_config.hrl
    core/kazoo_stdlib/include/kz_types.hrl core/kazoo_stdlib/include/kz_records.hrl
    core/kazoo_stdlib/include/kz_log.hrl core/kazoo_stdlib/include/kz_databases.hrl
    core/kazoo_amqp/include/kz_api_literals.hrl
)
# Preserve an existing installed FSM if present, but do not require a live
# deployment's BEAM on a fresh checkout with prepared dependency libraries.
upgrade_installed=applications/acdc/ebin/acdc_agent_fsm.beam
upgrade_installed_present=0
if [[ -e $upgrade_installed || -L $upgrade_installed ]]; then
    upgrade_installed_present=1
    upgrade_inputs+=("$upgrade_installed")
fi
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS ERL_INETRC KAZOO_COOKIE
export ERL_LIBS="$upgrade_root/deps:$upgrade_root/core:$upgrade_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
export KAZOO_OTP_UPGRADE_OUTPUT="$upgrade_output"
export KAZOO_TWO_VERSION_OUTPUT="$upgrade_output"
upgrade_erl=$(readlink -f "$(command -v erl)")
upgrade_erlc=$(readlink -f "$(command -v erlc)")
upgrade_inputs+=("$upgrade_erl" "$upgrade_erlc")
# Obtain actual installed OTP paths, not host/version literals. The bounded
# library set covers executable OTP dependencies and compile transforms; the
# final VM also refuses any loaded file outside the pinned/private path set.
"$upgrade_erl" -noshell -eval '
  Private=os:getenv("KAZOO_OTP_UPGRADE_OUTPUT"),
  Libs=[kernel,stdlib,eunit,compiler,syntax_tools],
  Beams=lists:usort(lists:append([filelib:wildcard(filename:join([code:lib_dir(L),"ebin","*.beam"])) || L<-Libs])),
  true=Beams=/=[], true=length(Beams)=<2000,
  {ok,VM}=file:read_link("/proc/self/exe"),
  Includes=[filename:join([code:lib_dir(eunit),"include","eunit.hrl"]),
            filename:join([code:lib_dir(stdlib),"include","assert.hrl"]),
            filename:join([code:lib_dir(xmerl),"include","xmerl.hrl"])],
  Optional=[filename:join([code:lib_dir(stdlib),"src",atom_to_list(M)++".erl"]) || M<-[gen_statem,gen,sys,proc_lib]],
  Existing=[P || P<-Optional,filelib:is_regular(P)],
  Write=fun(Name,Paths)->ok=file:write_file(filename:join(Private,Name),[[P,"\n"] || P<-Paths]) end,
  Write("otp-beam-paths.txt",Beams), Write("otp-input-paths.txt",[VM|Includes]++Beams),
  Write("optional-inspected-otp-sources.txt",Existing), halt(0).'
mapfile -t upgrade_otp <"$upgrade_output/otp-input-paths.txt"
mapfile -t upgrade_optional <"$upgrade_output/optional-inspected-otp-sources.txt"
upgrade_inputs+=("${upgrade_otp[@]}" "${upgrade_optional[@]}")
for upgrade_input in deps/lager/ebin/*.beam; do upgrade_inputs+=("$upgrade_input"); done
for upgrade_input in "${upgrade_inputs[@]}"; do
    [[ -f $upgrade_input && ! -L $upgrade_input ]] || {
        printf 'Missing or symlinked fixture input: %s\n' "$upgrade_input" >&2; exit 2;
    }
done
sha256sum "${upgrade_inputs[@]}" >"$upgrade_output/inputs-before.sha256"
printf '%s\n' "$upgrade_root"/deps/lager/ebin/*.beam >"$upgrade_output/provider-beam-paths.txt"
finish() {
    local upgrade_status=$?
    trap - EXIT
    if [[ $upgrade_status == 0 && $upgrade_complete != 1 ]]; then
        upgrade_status=99
        printf 'FAIL interrupted before explicit completion\n' >&2
    fi
    if ! sha256sum --check --status "$upgrade_output/inputs-before.sha256" ||
       ! sha256sum --check --status "$upgrade_output/current-source-before.sha256"; then
        upgrade_status=99
        printf 'FAIL source/dependency bytes changed\n' >&2
    fi
    if [[ $upgrade_installed_present == 0 && ( -e $upgrade_installed || -L $upgrade_installed ) ]]; then
        upgrade_status=99
        printf 'FAIL previously absent shared FSM BEAM appeared\n' >&2
    fi
    sha256sum "${upgrade_inputs[@]}" >"$upgrade_output/inputs-after.sha256" || upgrade_status=99
    printf 'exit=%s\ncompleted=%s\nlive_runtime_mutation=false\n' "$upgrade_status" "$upgrade_complete" >"$upgrade_output/result.txt"
    printf 'OTP upgrade fixture exit=%s; retained evidence: %s\n' "$upgrade_status" "$upgrade_output"
    exit "$upgrade_status"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Compile the exact legacy and current-source snapshots with the same pinned
# local compiler/common dependencies. Neither production BEAM uses -DTEST.
mkdir "$upgrade_output/legacy" "$upgrade_output/current"
for upgrade_version in legacy current; do
    printf 'Compiling production version %s\n' "$upgrade_version" | tee -a "$upgrade_output/compile.log"
    "$upgrade_erlc" +debug_info -Werror -I "$upgrade_candidate/$upgrade_version/src" \
        -I applications/acdc/include -pa deps/lager/ebin +'{parse_transform,lager_transform}' \
        -o "$upgrade_output/$upgrade_version" "$upgrade_candidate/$upgrade_version/src/acdc_agent_fsm.erl" \
        2>&1 | tee -a "$upgrade_output/compile.log"
done
"$upgrade_erlc" +debug_info -Werror -o "$upgrade_output" "$upgrade_fixture" \
    2>&1 | tee -a "$upgrade_output/compile.log"
sha256sum "$upgrade_output/legacy/acdc_agent_fsm.beam" "$upgrade_output/current/acdc_agent_fsm.beam" \
    "$upgrade_output/acdc_agent_two_version_tests.beam" >"$upgrade_output/compiled-beams.sha256"
for upgrade_case in ready paused unsafe_legacy bad_legacy_tag; do
    export KAZOO_TWO_VERSION_CASE="$upgrade_case"
    "$upgrade_erl" -pa "$upgrade_output" -noshell -eval '
Private=os:getenv("KAZOO_TWO_VERSION_OUTPUT"),
Paths=fun(Name)->{ok,B}=file:read_file(filename:join(Private,Name)),
 [binary_to_list(P)||P<-binary:split(B,<<"\n">>,[global]),P=/=<<>>] end,
Pinned=Paths("otp-beam-paths.txt")++Paths("provider-beam-paths.txt"),
TestPath=filename:join(Private,"acdc_agent_two_version_tests.beam"),
PrivatePaths=[TestPath|[filename:join([Private,V,"acdc_agent_fsm.beam"])||V<-["legacy","current"]]],
Gate=fun() ->
  {module,acdc_agent_two_version_tests}=code:ensure_loaded(acdc_agent_two_version_tests),
  TestPath=code:which(acdc_agent_two_version_tests),
  lists:foreach(fun
    ({_,preloaded})->ok;
    ({M,File}) when is_list(File)->true=lists:member(File,Pinned++PrivatePaths),
       {ok,{M,Md5}}=beam_lib:md5(File),Md5=M:module_info(md5)
  end,code:all_loaded()),
  '\''nonode@nohost'\''=node(),[]=nodes()
end,
Gate(),false=code:is_loaded(acdc_agent_fsm),
io:format("PASS fresh private VM, pinned OTP ~s; case ~s~n",
 [erlang:system_info(otp_release),os:getenv("KAZOO_TWO_VERSION_CASE")]),
Result=eunit:test(acdc_agent_two_version_tests,[verbose]),
Gate(),io:format("PASS post-case loaded paths/MD5/no-distribution~n",[]),
case Result of ok->halt(0);_->halt(1) end.' 2>&1 | tee "$upgrade_output/$upgrade_case.log"
    printf '%s PASS\n' "$upgrade_case" >>"$upgrade_output/case-results.txt"
done
upgrade_complete=1
