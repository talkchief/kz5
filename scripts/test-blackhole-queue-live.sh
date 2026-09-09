#!/usr/bin/env bash
# Offline socket-callback/binding proof with controlled authorization providers.
# No broker, real JWT, Cowboy wire, live services or deployment acceptance.
set -Eeuo pipefail
umask 077
[[ $# == 0 ]] || exit 2
queue_live_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
queue_live_output=$(mktemp -d /tmp/kazoo-blackhole-queue-live.XXXXXX)
readonly queue_live_ref=4e3f02a5ab01c09a44c287f4f93b15d2782f5614
cd "$queue_live_root"
finish() {
    local queue_live_status=$?
    trap - EXIT
    for queue_live_manifest in inputs.sha256 replay.sha256 artifacts.sha256; do
        if [[ -f $queue_live_output/$queue_live_manifest ]] &&
           ! sha256sum --check --status "$queue_live_output/$queue_live_manifest"; then
            queue_live_status=99
        fi
    done
    printf 'Blackhole queue-live exit=%s; retained evidence: %s\n' "$queue_live_status" "$queue_live_output"
    exit "$queue_live_status"
}
trap finish EXIT
queue_live_archive=(src/bh_context.erl src/bh_events.erl src/blackhole_bindings.erl
    src/blackhole_socket_handler.erl src/blackhole_socket_callback.erl src/blackhole_data_emitter.erl
    src/blackhole_listener.erl src/modules/bh_token_auth.erl src/modules/bh_ping.erl)
queue_live_sources=("${queue_live_archive[@]}" src/modules/bh_queue_live.erl)
queue_live_extra=(applications/acdc/src/kapi_acdc_dashboard_events.erl applications/acdc/src/acdc_live_auth.erl)
queue_live_patches=(scripts/patches/blackhole-kazoo5-integration.patch
    scripts/patches/blackhole-pre-queue-live-integration.patch scripts/patches/blackhole-queue-live.patch
    scripts/patches/blackhole-command-auth.patch
    scripts/patches/blackhole-outbound-guard.patch
    scripts/patches/blackhole-stream-guard-transition.patch)
queue_live_deps=(core/kazoo_bindings/ebin/kazoo_bindings.beam core/kazoo_bindings/ebin/kazoo_bindings_rt.beam
    core/kazoo_stdlib/ebin/kz_json.beam core/kazoo_stdlib/ebin/kz_log.beam
    core/kazoo_stdlib/ebin/kz_term.beam core/kazoo_stdlib/ebin/kz_binary.beam
    core/kazoo_stdlib/ebin/kz_time.beam core/kazoo_stdlib/ebin/kz_process.beam
    core/kazoo_stdlib/ebin/props.beam core/kazoo_nodes/ebin/kz_nodes.beam
    core/kazoo_token_buckets/ebin/kz_buckets.beam core/kazoo_amqp/ebin/kz_api.beam
    applications/crossbar/ebin/cb_context.beam
    deps/lager/ebin/lager.beam deps/lager/ebin/lager_transform.beam deps/lager/ebin/lager_util.beam
    deps/lager/ebin/lager_config.beam deps/meck/ebin/*.beam deps/jiffy/ebin/*.beam)
queue_live_inputs=(scripts/test-blackhole-queue-live.sh scripts/erlang-tests/blackhole_queue_live_tests.erl
    "${queue_live_patches[@]}" "${queue_live_extra[@]}" "${queue_live_deps[@]}"
    deps/jiffy/ebin/jiffy.app deps/jiffy/priv/jiffy.so applications/blackhole/src/blackhole.hrl)
for queue_live_source in "${queue_live_sources[@]}"; do
    queue_live_inputs+=("applications/blackhole/$queue_live_source")
done
/usr/bin/find applications/acdc/src applications/acdc/include applications/crossbar/src \
    core/kazoo_stdlib/include core/kazoo_amqp/include core/kazoo_documents/include \
    -type f -name '*.hrl' > "$queue_live_output/headers.list"
LC_ALL=C /usr/bin/sort -o "$queue_live_output/headers.list" "$queue_live_output/headers.list"
while IFS= read -r queue_live_header; do queue_live_inputs+=("$queue_live_header"); done < "$queue_live_output/headers.list"
for queue_live_input in "${queue_live_inputs[@]}"; do
    [[ -f $queue_live_input && ! -L $queue_live_input ]] || {
        printf 'Missing queue-live input: %s\n' "$queue_live_input" >&2; exit 2;
    }
done
sha256sum "${queue_live_inputs[@]}" > "$queue_live_output/inputs.sha256"
[[ $(git -C applications/blackhole rev-parse HEAD) == "$queue_live_ref" ]]
mkdir -m 0700 "$queue_live_output/replay" "$queue_live_output/transition" "$queue_live_output/production"
for queue_live_lane in replay transition; do
    git -C applications/blackhole archive "$queue_live_ref" "${queue_live_archive[@]}" src/blackhole.hrl |
        tar -xf - -C "$queue_live_output/$queue_live_lane"
done
git -C "$queue_live_output/replay" apply --check "$queue_live_root/${queue_live_patches[0]}"
git -C "$queue_live_output/replay" apply "$queue_live_root/${queue_live_patches[0]}"
git -C "$queue_live_output/replay" apply --reverse --check "$queue_live_root/${queue_live_patches[0]}"
git -C "$queue_live_output/transition" apply "$queue_live_root/${queue_live_patches[1]}"
git -C "$queue_live_output/transition" apply --check "$queue_live_root/${queue_live_patches[2]}"
git -C "$queue_live_output/transition" apply "$queue_live_root/${queue_live_patches[2]}"
git -C "$queue_live_output/transition" apply --reverse --check "$queue_live_root/${queue_live_patches[2]}"
git -C "$queue_live_output/transition" apply "$queue_live_root/scripts/patches/blackhole-stream-guard-transition.patch"
for queue_live_lane in replay transition; do
    git -C "$queue_live_output/$queue_live_lane" apply "$queue_live_root/scripts/patches/blackhole-outbound-guard.patch"
    git -C "$queue_live_output/$queue_live_lane" apply --check "$queue_live_root/${queue_live_patches[3]}"
    git -C "$queue_live_output/$queue_live_lane" apply "$queue_live_root/${queue_live_patches[3]}"
    git -C "$queue_live_output/$queue_live_lane" apply --reverse --check "$queue_live_root/${queue_live_patches[3]}"
done
if git -C "$queue_live_output/replay" apply --check "$queue_live_root/${queue_live_patches[0]}" 2>/dev/null; then
    printf 'Aggregate unexpectedly applies twice\n' >&2; exit 2
fi
if git -C "$queue_live_output/transition" apply --check "$queue_live_root/${queue_live_patches[2]}" 2>/dev/null; then
    printf 'Transition unexpectedly applies twice\n' >&2; exit 2
fi
queue_live_compile=()
queue_live_replayed=()
for queue_live_source in "${queue_live_sources[@]}" src/blackhole.hrl; do
    for queue_live_lane in replay transition; do
        cmp "applications/blackhole/$queue_live_source" "$queue_live_output/$queue_live_lane/$queue_live_source"
        queue_live_replayed+=("$queue_live_output/$queue_live_lane/$queue_live_source")
    done
    if [[ $queue_live_source == *.erl ]]; then queue_live_compile+=("$queue_live_output/replay/$queue_live_source"); fi
done
sha256sum "${queue_live_replayed[@]}" > "$queue_live_output/replay.sha256"
queue_live_compile+=("${queue_live_extra[@]}")
printf '%s\n' "${queue_live_compile[@]}" > "$queue_live_output/production-paths.txt"
printf '%s\n' "${queue_live_deps[@]}" > "$queue_live_output/dependency-paths.txt"
printf 'Scope: exact aggregate/transition replay; 11 fresh production modules; no TEST/export_all. Runtime uses identical no-transform sources for logging doubles. Listed dependencies pinned but unrebuilt; other OTP/ERL_LIBS dependencies unrebuilt and unpinned. Authorization provider controlled, not live JWT/broker/wire proof.\n' | tee "$queue_live_output/scope.log"
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS ERL_INETRC
export ERL_LIBS="$queue_live_root/deps:$queue_live_root/core:$queue_live_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1' ERL_CRASH_DUMP=/dev/null
erlc -Werror +debug_info -I "$queue_live_output/replay/src" -I applications/acdc/src -I applications/acdc/include \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' -o "$queue_live_output/production" \
    "${queue_live_compile[@]}" 2>&1 | tee "$queue_live_output/production-compile.log"
erlc -Werror +debug_info -I "$queue_live_output/replay/src" -I applications/acdc/src -I applications/acdc/include \
    -o "$queue_live_output" "${queue_live_compile[@]}" scripts/erlang-tests/blackhole_queue_live_tests.erl \
    2>&1 | tee "$queue_live_output/compile.log"
sha256sum "$queue_live_output"/*.beam "$queue_live_output/production"/*.beam > "$queue_live_output/artifacts.sha256"
export KAZOO_QUEUE_LIVE_OUTPUT="$queue_live_output" KAZOO_QUEUE_LIVE_ROOT="$queue_live_root"
erl -pa "$queue_live_output" -noshell -eval '
Root=os:getenv("KAZOO_QUEUE_LIVE_ROOT"), Private=os:getenv("KAZOO_QUEUE_LIVE_OUTPUT"),
Paths=fun(Name)->{ok,B}=file:read_file(filename:join(Private,Name)),
    [binary_to_list(P)||P<-binary:split(B,<<"\n">>,[global]),P=/= <<>>] end,
Gate=fun()->
    lists:foreach(fun(Source)->
        M=list_to_atom(filename:basename(Source,".erl")),{module,M}=code:ensure_loaded(M),
        Expected=filename:join(Private,atom_to_list(M)++".beam"),Expected=code:which(M),
        Opts=proplists:get_value(options,M:module_info(compile),[]),
        false=lists:any(fun({d,'\''TEST'\''})->true;({d,'\''TEST'\'',_})->true;
            (export_all)->true;({parse_transform,_})->true;(_)->false end,Opts),
        Beam=filename:join([Private,"production",atom_to_list(M)++".beam"]),
        {ok,{M,[{compile_info,Info}]}}=beam_lib:chunks(Beam,[compile_info]),
        POpts=proplists:get_value(options,Info,[]),true=lists:member({parse_transform,lager_transform},POpts),
        false=lists:any(fun({d,'\''TEST'\''})->true;({d,'\''TEST'\'',_})->true;(export_all)->true;(_)->false end,POpts)
    end,Paths("production-paths.txt")),
    lists:foreach(fun(Rel)->M=list_to_atom(filename:basename(Rel,".beam")),{module,M}=code:ensure_loaded(M),
        Expected=filename:join(Root,Rel),Expected=code:which(M)
    end,Paths("dependency-paths.txt")),
    Jiffy=filename:join([Root,"deps","jiffy","priv"]),Jiffy=code:priv_dir(jiffy)
end,
Gate(),Result=eunit:test(blackhole_queue_live_tests,[verbose]),Gate(),
case Result of ok->halt(0);_->halt(1) end.' 2>&1 | tee "$queue_live_output/eunit.log"
