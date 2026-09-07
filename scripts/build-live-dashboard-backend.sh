#!/usr/bin/env bash
# Production artifacts only. Root must supply the serialized resource/net guard.
# No module load, service operation, dependency fetch, tests, or runtime writes.
set -Eeuo pipefail
umask 077
[[ $# == 0 ]] || { printf 'Usage: %s (no arguments)\n' "$0" >&2; exit 64; }
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS ERL_INETRC MAKEFLAGS MFLAGS MAKEOVERRIDES
dashboard_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
dashboard_build_dir=$(mktemp -d /usr/local/src/kazoo5-installer/live-dashboard-backend.XXXXXX) || exit 73
[[ "$dashboard_build_dir" == /usr/local/src/kazoo5-installer/live-dashboard-backend.* &&
   -d "$dashboard_build_dir" && ! -L "$dashboard_build_dir" ]] || exit 73
readonly dashboard_root dashboard_build_dir
dashboard_stage="$dashboard_build_dir/source"
mkdir "$dashboard_stage"
export TMPDIR="$dashboard_build_dir"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1 -no_dot_erlang'
export ERL_CRASH_DUMP="$dashboard_build_dir/erl_crash.dump"
export ERL_LIBS="$dashboard_stage/applications:$dashboard_root/deps:$dashboard_root/core:$dashboard_root/applications"
export LIVE_DASHBOARD_BUILD_DIR="$dashboard_build_dir"
export PATH=/usr/bin:/bin
dashboard_step=inputs
dashboard_complete=false
dashboard_inputs_ready=false
dashboard_source_dirs=(applications/acdc/src applications/acdc/include applications/blackhole/src)
cd "$dashboard_root"

dashboard_inventory() {
    /usr/bin/find "${dashboard_source_dirs[@]}" \( -type f -o -type l \) \
        \( -name '*.erl' -o -name '*.hrl' -o -name '*.app.src' \) -print | LC_ALL=C sort
}
dashboard_exit() {
    local dashboard_rc=$? dashboard_stable=false
    trap - EXIT
    if [[ "$dashboard_inputs_ready" == true ]]; then
        if sha256sum --status --check "$dashboard_build_dir/inputs.sha256" &&
           dashboard_inventory > "$dashboard_build_dir/sources.after.list" &&
           cmp --silent "$dashboard_build_dir/sources.list" "$dashboard_build_dir/sources.after.list" &&
           (cd "$dashboard_stage" && sha256sum --status --check "$dashboard_build_dir/staged-inputs.sha256"); then
            dashboard_stable=true
        else
            printf 'Build inputs changed; retained manifests for diagnosis.\n' >&2
            dashboard_rc=1
        fi
    else dashboard_rc=1
    fi
    [[ "$dashboard_complete" == true ]] || dashboard_rc=1
    printf '{"exit_code":%s,"stage":"%s","complete":%s,"inputs_stable":%s,"production_artifacts":%s,"network":false,"tests":false,"module_loading":false,"runtime_writes":false,"deployment":false}\n' \
        "$dashboard_rc" "$dashboard_step" "$dashboard_complete" "$dashboard_stable" "$dashboard_complete" \
        > "$dashboard_build_dir/receipt.json"
    printf 'Live-dashboard backend build exit %s; retained artifacts/evidence: %s\n' "$dashboard_rc" "$dashboard_build_dir"
    exit "$dashboard_rc"
}
trap dashboard_exit EXIT

dashboard_inventory > "$dashboard_build_dir/sources.list"
mapfile -t dashboard_source_files < "$dashboard_build_dir/sources.list"
[[ ${#dashboard_source_files[@]} -gt 0 ]]
dashboard_stage_files=("${dashboard_source_files[@]}" .base_branch
    make/kz.mk make/rebar.mk make/splchk.mk make/fmt.mk
    applications/acdc/Makefile applications/acdc/apps.mk applications/acdc/deps.mk
    applications/blackhole/Makefile applications/blackhole/apps.mk applications/blackhole/deps.mk)
for dashboard_input in "${dashboard_stage_files[@]}"; do
    [[ "$dashboard_input" =~ ^[a-zA-Z0-9_./-]+$ && -f "$dashboard_input" && ! -L "$dashboard_input" &&
       "$(realpath -e -- "$dashboard_input")" == "$dashboard_root/$dashboard_input" ]]
done
sha256sum "${dashboard_stage_files[@]}" > "$dashboard_build_dir/staged-inputs.sha256"
dashboard_inputs=("${dashboard_stage_files[@]}" scripts/build-live-dashboard-backend.sh doc/build_live_dashboard_backend.md)
# Cached headers/BEAMs are read-only inputs, not rebuilt dependency claims.
# Pin all locally available ERL_LIBS dependencies before any compiler starts.
/usr/bin/find deps core applications -type f \
    \( -name '*.hrl' -o -path '*/ebin/*.beam' -o -path '*/ebin/*.app' \) \
    -print | LC_ALL=C sort -u > "$dashboard_build_dir/dependencies.list"
while IFS= read -r dashboard_input; do dashboard_inputs+=("$dashboard_input"); done < "$dashboard_build_dir/dependencies.list"
sha256sum "${dashboard_inputs[@]}" > "$dashboard_build_dir/inputs.sha256"
for dashboard_input in "${dashboard_stage_files[@]}"; do
    cp --parents -- "$dashboard_input" "$dashboard_stage/"
done
mkdir "$dashboard_stage/applications/acdc/ebin" "$dashboard_stage/applications/blackhole/ebin"
dashboard_inputs_ready=true
(cd "$dashboard_stage" && sha256sum --status --check "$dashboard_build_dir/staged-inputs.sha256")

dashboard_step=metadata_prepare
# This VM consults .app.src and filenames only. It does not load application
# BEAMs or execute tests. Keep the reviewed source versions, no guessed fallback.
erl -no_dot_erlang -noshell -eval '
    Dir=os:getenv("LIVE_DASHBOARD_BUILD_DIR"), Stage=filename:join(Dir,"source"),
    [begin
        AppDir=filename:join([Stage,"applications",atom_to_list(App)]),
        AppDir=code:lib_dir(App),
        {ok,[{application,App,Props}]}=file:consult(filename:join([AppDir,"src",atom_to_list(App)++".app.src"])),
        []=proplists:get_value(modules,Props),
        Version=proplists:get_value(vsn,Props),
        true=is_list(Version),true=(length(Version)>0 andalso length(Version)=<128),
        match=re:run(Version,"^[a-zA-Z0-9_.-]+$",[{capture,none}]),
        ok=file:write_file(filename:join(Dir,atom_to_list(App)++".version"),[Version,"\n"])
     end || App<-[acdc,blackhole]],halt(0).
' 2>&1 | tee "$dashboard_build_dir/prepare.log"

for dashboard_app in acdc blackhole; do
    dashboard_step="compile_$dashboard_app"
    dashboard_app_dir="$dashboard_stage/applications/$dashboard_app"
    dashboard_sources=()
    while IFS= read -r dashboard_input; do
        case "$dashboard_input" in
            "applications/$dashboard_app/src/ci/"*) ;; # Non-runtime property/API client fixture.
            "applications/$dashboard_app/src/"*.erl)
                dashboard_sources+=("${dashboard_input#applications/$dashboard_app/}") ;;
        esac
    done < "$dashboard_build_dir/sources.list"
    [[ ${#dashboard_sources[@]} -gt 0 ]]
    printf '%s\n' "${dashboard_sources[@]}" > "$dashboard_build_dir/$dashboard_app.sources.list"
    IFS= read -r dashboard_version < "$dashboard_build_dir/$dashboard_app.version"
    [[ "$dashboard_version" =~ ^[a-zA-Z0-9_.-]+$ ]]
    # Exact existing batch recipe, not compile/compile-direct: those also run
    # JSON/docs/dependency targets. Fresh ebin + forced app recipe compiles every
    # listed module and regenerates the module inventory, including BH ABI users.
    dashboard_make=(/usr/bin/make --no-print-directory -rR -j1 -C "$dashboard_app_dir"
        "ROOT=$dashboard_stage" "PROJECT_ROOT=$dashboard_app_dir" "KZ_VERSION=$dashboard_version"
        KAZOO_FORCE_RECOMPILE=1 PLATFORM=linux CHANGED= JSON= APPS_PA=
        "ELIBS=$ERL_LIBS" "EBINS=$dashboard_root/deps/lager/ebin"
        "DEPS_RULES=$dashboard_build_dir/not-present.deps.rules"
        "TEST_DEPS=$dashboard_build_dir/not-present.test.deps"
        "SOURCES=${dashboard_sources[*]}" "ebin/$dashboard_app.app")
    printf '%q ' "${dashboard_make[@]}" > "$dashboard_build_dir/$dashboard_app.argv"
    printf '\n' >> "$dashboard_build_dir/$dashboard_app.argv"
    env -i PATH=/usr/bin:/bin LANG=C LC_ALL=C TMPDIR="$TMPDIR" \
        ERL_FLAGS="$ERL_FLAGS" ERL_CRASH_DUMP="$ERL_CRASH_DUMP" ERL_LIBS="$ERL_LIBS" \
        "${dashboard_make[@]}" 2>&1 | tee "$dashboard_build_dir/$dashboard_app.compile.log"
done

dashboard_step=artifact_metadata
# beam_lib reads bytes, never code:load_file/load_binary or application:start.
erl -no_dot_erlang -noshell -eval '
    Dir=os:getenv("LIVE_DASHBOARD_BUILD_DIR"),
    Summary=[begin
        Name=atom_to_list(App),AppDir=filename:join([Dir,"source","applications",Name]),
        {ok,SourceBytes}=file:read_file(filename:join(Dir,Name++".sources.list")),
        Sources=[binary_to_list(B)||B<-binary:split(SourceBytes,<<"\n">>,[global]),B=/= <<>>],
        Modules=lists:sort([list_to_atom(filename:basename(S,".erl"))||S<-Sources]),
        Modules=lists:usort(Modules),
        Ebin=filename:join(AppDir,"ebin"),Files=filelib:wildcard(filename:join(Ebin,"*.beam")),
        true=(length(Modules)=:=length(Files)),
        {ok,[{application,App,AppProps}]}=file:consult(filename:join(Ebin,Name++".app")),
        Modules=lists:sort(proplists:get_value(modules,AppProps)),
        {ok,[{application,App,SourceProps}]}=file:consult(filename:join([AppDir,"src",Name++".app.src"])),
        true=(proplists:get_value(vsn,SourceProps)=:=proplists:get_value(vsn,AppProps)),
        [begin
            File=filename:join(Ebin,atom_to_list(M)++".beam"),
            {ok,{M,[{compile_info,Info},{exports,Exports}]}}=beam_lib:chunks(File,[compile_info,exports]),
            Options=proplists:get_value(options,Info,[]),
            []=[O||O<-Options,O=:=export_all orelse O=:={d,'\''TEST'\''} orelse O=:={d,'\''PROPER'\''}
                orelse (is_tuple(O) andalso tuple_size(O)=:=3 andalso element(1,O)=:=d
                    andalso lists:member(element(2,O),['\''TEST'\'','\''PROPER'\'']))],
            Source=proplists:get_value(source,Info),
            true=lists:member(Source,[filename:join(AppDir,S)||S<-Sources]),
            false=lists:keymember(test,1,Exports),
            false=lists:suffix("_tests",atom_to_list(M))
         end || M<-Modules],
        io:format("~s: ~p production modules; complete .app inventory and private-source metadata verified~n",[Name,length(Modules)]),
        {App,length(Modules),proplists:get_value(vsn,AppProps)}
     end || App<-[acdc,blackhole]],
    ok=file:write_file(filename:join(Dir,"artifact-summary.term"),io_lib:format("~p.~n",[Summary])),halt(0).
' 2>&1 | tee "$dashboard_build_dir/metadata.log"
/usr/bin/find "$dashboard_stage/applications/acdc/ebin" "$dashboard_stage/applications/blackhole/ebin" \
    -type f -print | LC_ALL=C sort > "$dashboard_build_dir/artifacts.list"
mapfile -t dashboard_artifacts < "$dashboard_build_dir/artifacts.list"
sha256sum "${dashboard_artifacts[@]}" > "$dashboard_build_dir/artifacts.sha256"
dashboard_step=complete
dashboard_complete=true
