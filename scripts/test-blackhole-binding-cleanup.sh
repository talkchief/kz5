#!/usr/bin/env bash
# Offline public subscription cleanup with real binding/listener reference counts.
# No broker, auth, socket, services or deployment. Production tuples require restart.
set -Eeuo pipefail
umask 077
[[ $# == 0 ]] || exit 2
cleanup_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cleanup_output=$(mktemp -d /tmp/kazoo-blackhole-cleanup.XXXXXX)
cleanup_replay="$cleanup_output/replay"
cleanup_repo="$cleanup_root/applications/blackhole"
cleanup_patch="$cleanup_root/scripts/patches/blackhole-kazoo5-integration.patch"
readonly cleanup_ref=4e3f02a5ab01c09a44c287f4f93b15d2782f5614
cd "$cleanup_root"
cleanup_sources=(src/bh_context.erl src/bh_events.erl src/blackhole_bindings.erl
    src/blackhole_listener.erl src/blackhole_data_emitter.erl)
cleanup_archive_sources=("${cleanup_sources[@]}" src/blackhole_socket_handler.erl src/modules/bh_token_auth.erl)
cleanup_replay_sources=("${cleanup_archive_sources[@]}" src/modules/bh_queue_live.erl)
cleanup_deps=(core/kazoo_bindings/ebin/kazoo_bindings.beam core/kazoo_bindings/ebin/kazoo_bindings_rt.beam
    core/kazoo_stdlib/ebin/kz_json.beam core/kazoo_stdlib/ebin/kz_log.beam
    core/kazoo_stdlib/ebin/kz_term.beam core/kazoo_stdlib/ebin/kz_binary.beam
    core/kazoo_stdlib/ebin/kz_time.beam core/kazoo_stdlib/ebin/kz_process.beam
    core/kazoo_stdlib/ebin/props.beam core/kazoo_nodes/ebin/kz_nodes.beam
    core/kazoo_apps/ebin/kapps_config.beam core/kazoo_amqp/ebin/gen_listener.beam
    core/kazoo_amqp/ebin/kz_events.beam core/kazoo_amqp/ebin/kz_api.beam
    deps/lager/ebin/lager.beam deps/lager/ebin/lager_transform.beam
    deps/lager/ebin/lager_util.beam deps/lager/ebin/lager_config.beam
    deps/meck/ebin/meck.beam deps/meck/ebin/meck_args_matcher.beam deps/meck/ebin/meck_code.beam
    deps/meck/ebin/meck_code_gen.beam deps/meck/ebin/meck_cover.beam deps/meck/ebin/meck_expect.beam
    deps/meck/ebin/meck_history.beam deps/meck/ebin/meck_matcher.beam deps/meck/ebin/meck_proc.beam
    deps/meck/ebin/meck_ret_spec.beam deps/meck/ebin/meck_util.beam
    deps/jiffy/ebin/jiffy.beam deps/jiffy/ebin/jiffy_utf8.beam)
cleanup_inputs=(scripts/test-blackhole-binding-cleanup.sh
    scripts/erlang-tests/blackhole_binding_cleanup_tests.erl
    scripts/patches/blackhole-kazoo5-integration.patch scripts/patches/blackhole-binding-cleanup.patch
    scripts/patches/blackhole-queue-live.patch
    scripts/install-kazoo5.sh applications/blackhole/src/blackhole.hrl
    core/kazoo_amqp/src/api/kapi_websockets.hrl
    core/kazoo_stdlib/include/kz_types.hrl core/kazoo_stdlib/include/kz_records.hrl
    core/kazoo_stdlib/include/kz_log.hrl core/kazoo_stdlib/include/kz_databases.hrl
    deps/jiffy/ebin/jiffy.app deps/jiffy/priv/jiffy.so "${cleanup_deps[@]}")
for cleanup_source in "${cleanup_replay_sources[@]}"; do
    cleanup_inputs+=("applications/blackhole/$cleanup_source")
done
for cleanup_input in "${cleanup_inputs[@]}"; do
    [[ -f $cleanup_input && ! -L $cleanup_input ]] || { printf 'Missing cleanup input %s\n' "$cleanup_input" >&2; exit 2; }
done
sha256sum "${cleanup_inputs[@]}" >"$cleanup_output/input-pins.sha256"
finish() {
    local cleanup_status=$?
    trap - EXIT
    for cleanup_manifest in input-pins.sha256 replay-pins.sha256 artifact-pins.sha256; do
        if [[ -f $cleanup_output/$cleanup_manifest ]] &&
           ! sha256sum --check --status "$cleanup_output/$cleanup_manifest"; then
            cleanup_status=99
        fi
    done
    printf 'Blackhole cleanup exit=%s; retained evidence: %s\n' "$cleanup_status" "$cleanup_output"
    exit "$cleanup_status"
}
trap finish EXIT
[[ $(git -C "$cleanup_repo" rev-parse HEAD) == "$cleanup_ref" ]] || exit 2
mkdir -m 0700 "$cleanup_replay" "$cleanup_output/production"
git -C "$cleanup_repo" archive "$cleanup_ref" "${cleanup_archive_sources[@]}" src/blackhole.hrl |
    tar -xf - -C "$cleanup_replay"
git -C "$cleanup_replay" apply --check "$cleanup_patch"
git -C "$cleanup_replay" apply "$cleanup_patch"
git -C "$cleanup_replay" apply --reverse --check "$cleanup_patch"
# The older cleanup hunk shares context with the new private session field.
# Verify its retained predecessor after reversing only the queue-live delta,
# then restore the complete candidate before equality/pins/compilation.
git -C "$cleanup_replay" apply --reverse "$cleanup_root/scripts/patches/blackhole-queue-live.patch"
git -C "$cleanup_replay" apply --reverse --check "$cleanup_root/scripts/patches/blackhole-binding-cleanup.patch"
git -C "$cleanup_replay" apply "$cleanup_root/scripts/patches/blackhole-queue-live.patch"
cleanup_compile_sources=()
cleanup_replay_inputs=()
for cleanup_source in "${cleanup_replay_sources[@]}" src/blackhole.hrl; do
    cmp -- "$cleanup_repo/$cleanup_source" "$cleanup_replay/$cleanup_source"
    cleanup_replay_inputs+=("$cleanup_replay/$cleanup_source")
done
for cleanup_source in "${cleanup_sources[@]}"; do cleanup_compile_sources+=("$cleanup_replay/$cleanup_source"); done
sha256sum "${cleanup_replay_inputs[@]}" >"$cleanup_output/replay-pins.sha256"
printf '%s\n' "${cleanup_sources[@]}" >"$cleanup_output/production-paths.txt"
printf '%s\n' "${cleanup_deps[@]}" >"$cleanup_output/dependency-paths.txt"
printf 'PASS pinned replay, full current reverse and shared source equality\n'
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS ERL_INETRC
export ERL_LIBS="$cleanup_root/deps:$cleanup_root/core:$cleanup_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1' ERL_CRASH_DUMP=/dev/null
# Production compiler evidence is separate from direct logging-provider doubles.
erlc -Werror +debug_info -I "$cleanup_replay/src" -pa deps/lager/ebin \
    +'{parse_transform,lager_transform}' -o "$cleanup_output/production" "${cleanup_compile_sources[@]}" \
    2>&1 | tee "$cleanup_output/production-compile.log"
erlc -Werror +debug_info -I "$cleanup_replay/src" -o "$cleanup_output" "${cleanup_compile_sources[@]}" \
    scripts/erlang-tests/blackhole_binding_cleanup_tests.erl 2>&1 | tee "$cleanup_output/compile.log"
sha256sum "$cleanup_output"/*.beam "$cleanup_output/production"/*.beam >"$cleanup_output/artifact-pins.sha256"
export KAZOO_CLEANUP_ROOT="$cleanup_root" KAZOO_CLEANUP_OUTPUT="$cleanup_output"
erl -pa "$cleanup_output" -noshell -eval '
Root = os:getenv("KAZOO_CLEANUP_ROOT"), Private = os:getenv("KAZOO_CLEANUP_OUTPUT"),
Paths = fun(Name) -> {ok, B} = file:read_file(filename:join(Private, Name)),
    [binary_to_list(P) || P <- binary:split(B, <<"\n">>, [global]), P =/= <<>>] end,
Production = Paths("production-paths.txt"), Dependencies = Paths("dependency-paths.txt"),
Gate = fun() ->
    lists:foreach(fun(Source) ->
        M = list_to_atom(filename:basename(Source, ".erl")), {module,M} = code:ensure_loaded(M),
        Expected = filename:join(Private, atom_to_list(M)++".beam"), Expected = code:which(M),
        Opts = proplists:get_value(options,M:module_info(compile),[]),
        false = lists:any(fun({d,'\''TEST'\''}) -> true; ({d,'\''TEST'\'',_}) -> true;
                            (export_all) -> true; ({parse_transform,_}) -> true; (_) -> false end,Opts),
        Beam = filename:join([Private,"production",atom_to_list(M)++".beam"]),
        {ok,{M,[{compile_info,Info}]}} = beam_lib:chunks(Beam,[compile_info]),
        POpts = proplists:get_value(options,Info,[]),
        true = lists:member({parse_transform,lager_transform},POpts),
        false = lists:any(fun({d,'\''TEST'\''}) -> true; ({d,'\''TEST'\'',_}) -> true; (export_all) -> true; (_) -> false end,POpts)
    end,Production),
    lists:foreach(fun(Rel) -> M = list_to_atom(filename:basename(Rel,".beam")),
        {module,M} = code:ensure_loaded(M), Expected = filename:join(Root,Rel), Expected = code:which(M)
    end,Dependencies),
    Jiffy = filename:join([Root,"deps","jiffy","priv"]), Jiffy = code:priv_dir(jiffy),
    {module,blackhole_binding_cleanup_tests} = code:ensure_loaded(blackhole_binding_cleanup_tests),
    Test = filename:join(Private,"blackhole_binding_cleanup_tests.beam"), Test = code:which(blackhole_binding_cleanup_tests)
end,
Gate(), Result = eunit:test(blackhole_binding_cleanup_tests,[verbose]), Gate(),
io:format("PASS fresh production, no-DTEST and dependency path checks before/after~n"),
case Result of ok -> halt(0); _ -> halt(1) end.' 2>&1 | tee "$cleanup_output/eunit.log"
