#!/usr/bin/env bash
# Local Cowboy wire proof only in a private network namespace; no live deployment/auth proof.
set -Eeuo pipefail
umask 077
[[ $# == 0 ]] || { printf 'Usage: %s\n' "$0" >&2; exit 2; }
blackhole_frame_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
blackhole_frame_output=$(mktemp -d /tmp/kazoo-blackhole-frames.XXXXXX)
readonly blackhole_frame_ref=4e3f02a5ab01c09a44c287f4f93b15d2782f5614
readonly blackhole_frame_crossbar_ref=2ac862830f9b626d2170d08daf1991b0ca33dba7
readonly blackhole_frame_schema_relative=priv/couchdb/schemas/system_config.blackhole.json
blackhole_frame_schema_replay="$blackhole_frame_output/schema-replay"
blackhole_frame_repo="$blackhole_frame_root/applications/blackhole"
blackhole_frame_replay="$blackhole_frame_output/replay"
blackhole_frame_production="$blackhole_frame_output/production"
blackhole_frame_patch="$blackhole_frame_root/scripts/patches/blackhole-kazoo5-integration.patch"
cd "$blackhole_frame_root"
blackhole_frame_sources=(
    applications/blackhole/src/modules/bh_token_auth.erl
    applications/blackhole/src/modules/bh_queue_live.erl
    applications/blackhole/src/bh_context.erl
    applications/blackhole/src/blackhole_bindings.erl
    applications/blackhole/src/blackhole_socket_callback.erl
    applications/blackhole/src/blackhole_data_emitter.erl
    applications/blackhole/src/blackhole_socket_handler.erl
    applications/blackhole/src/blackhole_tracking.erl
    applications/blackhole/src/bh_events.erl
)
# Existing utilities and mock-provider metadata are pinned bytecode, not fresh
# production rebuilds. This is a bounded list, not a full dependency closure.
blackhole_frame_dependencies=(
    core/kazoo_bindings/ebin/kazoo_bindings.beam
    core/kazoo_bindings/ebin/kazoo_bindings_rt.beam
    core/kazoo_auth/ebin/kz_auth.beam
    core/kazoo_stdlib/ebin/kz_json.beam
    core/kazoo_stdlib/ebin/kz_log.beam
    core/kazoo_stdlib/ebin/kz_term.beam
    core/kazoo_stdlib/ebin/kz_binary.beam
    core/kazoo_stdlib/ebin/kz_time.beam
    core/kazoo_stdlib/ebin/kz_network_utils.beam
    core/kazoo_stdlib/ebin/props.beam
    core/kazoo_auth/ebin/kz_auth.beam
    core/kazoo_nodes/ebin/kz_nodes.beam
    core/kazoo_token_buckets/ebin/kz_buckets.beam
    core/kazoo_apps/ebin/kapps_config.beam
    core/kazoo_stdlib/ebin/kz_app_config.beam
    core/kazoo_stdlib/ebin/kz_process.beam
    core/kazoo_amqp/ebin/gen_listener.beam
    applications/blackhole/ebin/blackhole_listener.beam
    deps/lager/ebin/lager.beam
    deps/lager/ebin/lager_transform.beam
    deps/lager/ebin/lager_util.beam
    deps/lager/ebin/lager_config.beam
    deps/meck/ebin/meck.beam
    deps/meck/ebin/meck_args_matcher.beam
    deps/meck/ebin/meck_code.beam
    deps/meck/ebin/meck_code_gen.beam
    deps/meck/ebin/meck_cover.beam
    deps/meck/ebin/meck_expect.beam
    deps/meck/ebin/meck_history.beam
    deps/meck/ebin/meck_matcher.beam
    deps/meck/ebin/meck_proc.beam
    deps/meck/ebin/meck_ret_spec.beam
    deps/meck/ebin/meck_util.beam
    deps/jiffy/ebin/jiffy.beam
    deps/jiffy/ebin/jiffy_utf8.beam
    deps/cowboy/ebin/*.beam
    deps/cowlib/ebin/*.beam
    deps/ranch/ebin/*.beam
)
blackhole_frame_other_inputs=(
    scripts/test-blackhole-frame-wire.sh
    scripts/erlang-tests/blackhole_frame_wire_tests.erl
    scripts/patches/blackhole-kazoo5-integration.patch
    scripts/patches/blackhole-command-auth.patch
    scripts/install-kazoo5.sh
    scripts/patches/crossbar-kazoo5-integration.patch
    applications/crossbar/priv/couchdb/schemas/system_config.blackhole.json
    deps/cowboy/ebin/cowboy.app
    deps/cowlib/ebin/cowlib.app
    deps/ranch/ebin/ranch.app
    applications/blackhole/src/blackhole.hrl
    core/kazoo_stdlib/include/kz_types.hrl
    core/kazoo_stdlib/include/kz_records.hrl
    core/kazoo_stdlib/include/kz_log.hrl
    core/kazoo_stdlib/include/kz_databases.hrl
    deps/jiffy/ebin/jiffy.app
    deps/jiffy/priv/jiffy.so
)
for blackhole_frame_input in "${blackhole_frame_sources[@]}" "${blackhole_frame_dependencies[@]}" "${blackhole_frame_other_inputs[@]}"; do
    [[ -f $blackhole_frame_input && ! -L $blackhole_frame_input ]] || {
        printf 'Missing or symlinked frame input: %s\n' "$blackhole_frame_input" >&2
        exit 2
    }
done
sha256sum "${blackhole_frame_sources[@]}" "${blackhole_frame_dependencies[@]}" \
    "${blackhole_frame_other_inputs[@]}" >"$blackhole_frame_output/input-pins.sha256"
printf '%s\n' "${blackhole_frame_sources[@]}" >"$blackhole_frame_output/production-paths.txt"
printf '%s\n' "${blackhole_frame_dependencies[@]}" >"$blackhole_frame_output/dependency-paths.txt"
finish() {
    local blackhole_frame_status=$?
    trap - EXIT
    if ! sha256sum --check --status "$blackhole_frame_output/input-pins.sha256"; then
        printf 'FAIL frame source or dependency bytes changed during validation\n' >&2
        blackhole_frame_status=99
    fi
    for blackhole_frame_manifest in replay-pins.sha256 artifact-pins.sha256; do
        if [[ -f $blackhole_frame_output/$blackhole_frame_manifest ]] &&
           ! sha256sum --check --status "$blackhole_frame_output/$blackhole_frame_manifest"; then
            printf 'FAIL retained replay or compiled artifact changed: %s\n' "$blackhole_frame_manifest" >&2
            blackhole_frame_status=99
        fi
    done
    printf 'Blackhole frame/wire exit=%s; retained private evidence: %s\n' "$blackhole_frame_status" "$blackhole_frame_output"
    exit "$blackhole_frame_status"
}
trap finish EXIT
[[ $(git -C "$blackhole_frame_repo" rev-parse HEAD) == "$blackhole_frame_ref" ]] || {
    printf 'Blackhole checkout is not the tested pinned revision\n' >&2; exit 2;
}
# Source assertions only: this test never sources or runs the installer.
blackhole_frame_hooks=(
    'KAZOO_BLACKHOLE_REF=${KAZOO_BLACKHOLE_REF:-4e3f02a5ab01c09a44c287f4f93b15d2782f5614}'
    'KAZOO_CROSSBAR_REF KAZOO_BLACKHOLE_REF KAZOO_ECALLMGR_REF'
    '$KAZOO_BLACKHOLE_REF =~ ^[0-9a-f]{40}$'
    '[[ $(git -C "$KAZOO_ROOT/applications/blackhole" rev-parse HEAD) == "$KAZOO_BLACKHOLE_REF" ]]'
    '"dep_blackhole=git https://github.com/2600hz/kazoo-blackhole.git $KAZOO_BLACKHOLE_REF"'
    'apply_kazoo_integration_patch blackhole'
    'transition_new=blackhole-kazoo5-integration.patch'
)
for blackhole_frame_hook in "${blackhole_frame_hooks[@]}"; do
    /usr/bin/grep -Fq -- "$blackhole_frame_hook" scripts/install-kazoo5.sh || {
        printf 'Missing Blackhole installer pin/patch integration hook\n' >&2; exit 2;
    }
done
mkdir -m 0700 "$blackhole_frame_replay" "$blackhole_frame_production" "$blackhole_frame_schema_replay"
blackhole_frame_relative_sources=()
blackhole_frame_archive_sources=()
blackhole_frame_replayed_sources=()
blackhole_frame_artifacts=("$blackhole_frame_output/blackhole_frame_wire_tests.beam")
for blackhole_frame_source in "${blackhole_frame_sources[@]}"; do
    blackhole_frame_relative=${blackhole_frame_source#applications/blackhole/}
    blackhole_frame_relative_sources+=("$blackhole_frame_relative")
    if [[ $blackhole_frame_relative != src/modules/bh_queue_live.erl ]]; then
        blackhole_frame_archive_sources+=("$blackhole_frame_relative")
    fi
    blackhole_frame_replayed_sources+=("$blackhole_frame_replay/$blackhole_frame_relative")
    blackhole_frame_module=${blackhole_frame_relative##*/}
    blackhole_frame_artifacts+=("$blackhole_frame_production/${blackhole_frame_module%.erl}.beam"
                              "$blackhole_frame_output/${blackhole_frame_module%.erl}.beam")
done
git -C "$blackhole_frame_repo" archive "$blackhole_frame_ref" \
    "${blackhole_frame_archive_sources[@]}" src/blackhole.hrl | tar -xf - -C "$blackhole_frame_replay"
git -C "$blackhole_frame_replay" apply --check "$blackhole_frame_patch"
git -C "$blackhole_frame_replay" apply "$blackhole_frame_patch"
git -C "$blackhole_frame_replay" apply --reverse --check "$blackhole_frame_patch"
git -C "$blackhole_frame_replay" apply --check "$blackhole_frame_root/scripts/patches/blackhole-command-auth.patch"
git -C "$blackhole_frame_replay" apply "$blackhole_frame_root/scripts/patches/blackhole-command-auth.patch"
git -C "$blackhole_frame_replay" apply --reverse --check "$blackhole_frame_root/scripts/patches/blackhole-command-auth.patch"
if git -C "$blackhole_frame_replay" apply --check "$blackhole_frame_patch" 2>/dev/null; then
    printf 'Blackhole frame/wire patch unexpectedly applies twice\n' >&2; exit 2
fi
for blackhole_frame_relative in "${blackhole_frame_relative_sources[@]}" src/blackhole.hrl; do
    cmp -- "$blackhole_frame_repo/$blackhole_frame_relative" "$blackhole_frame_replay/$blackhole_frame_relative"
done
# Replay only the bounded Crossbar schema hunk, never the rest of Crossbar.
[[ $(git -C applications/crossbar rev-parse HEAD) == "$blackhole_frame_crossbar_ref" ]]
git -C applications/crossbar archive "$blackhole_frame_crossbar_ref" "$blackhole_frame_schema_relative" \
    | tar -xf - -C "$blackhole_frame_schema_replay"
cp -- "$blackhole_frame_schema_replay/$blackhole_frame_schema_relative" "$blackhole_frame_output/schema-baseline.json"
blackhole_frame_crossbar_patch="$blackhole_frame_root/scripts/patches/crossbar-kazoo5-integration.patch"
git -C "$blackhole_frame_schema_replay" apply --check --include="$blackhole_frame_schema_relative" "$blackhole_frame_crossbar_patch"
git -C "$blackhole_frame_schema_replay" apply --include="$blackhole_frame_schema_relative" "$blackhole_frame_crossbar_patch"
git -C "$blackhole_frame_schema_replay" apply --reverse --check --include="$blackhole_frame_schema_relative" "$blackhole_frame_crossbar_patch"
if git -C "$blackhole_frame_schema_replay" apply --check --include="$blackhole_frame_schema_relative" "$blackhole_frame_crossbar_patch" 2>/dev/null; then
    printf 'Crossbar frame schema patch unexpectedly applies twice\n' >&2; exit 2
fi
cmp -- "applications/crossbar/$blackhole_frame_schema_relative" "$blackhole_frame_schema_replay/$blackhole_frame_schema_relative"
sha256sum "${blackhole_frame_replayed_sources[@]}" "$blackhole_frame_replay/src/blackhole.hrl" \
    "$blackhole_frame_schema_replay/$blackhole_frame_schema_relative" "$blackhole_frame_output/schema-baseline.json" \
    >"$blackhole_frame_output/replay-pins.sha256"
printf 'PASS fresh pinned Crossbar one-schema replay, equality and reverse/idempotence\n' \
    | tee "$blackhole_frame_output/schema-replay.log"
printf 'PASS pinned Blackhole %s patch replay, source equality, reverse/idempotence and installer hooks\n' \
    "$blackhole_frame_ref" | tee "$blackhole_frame_output/replay.log"
# Fail closed outside a fresh private netns; touch only its isolated loopback.
[[ $(readlink /proc/self/ns/net) != $(readlink /proc/1/ns/net) ]] || {
    printf 'Frame wire tests require a separate network namespace\n' >&2; exit 2;
}
[[ $(/usr/sbin/ip -o link show | /usr/bin/wc -l) -eq 1 ]]
/usr/sbin/ip link show dev lo >/dev/null
/usr/sbin/ip link set dev lo up
printf 'PASS private network namespace with loopback only\n' | tee "$blackhole_frame_output/network.log"
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS ERL_INETRC
export ERL_LIBS="$blackhole_frame_root/deps:$blackhole_frame_root/core:$blackhole_frame_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
export KAZOO_BLACKHOLE_FRAME_ROOT="$blackhole_frame_root" KAZOO_BLACKHOLE_FRAME_OUTPUT="$blackhole_frame_output"
export KAZOO_BLACKHOLE_FRAME_SCHEMA_BASELINE="$blackhole_frame_output/schema-baseline.json"
# Separate real production compile evidence: same source replay, with the Lager
# transform and warnings-as-errors. These BEAMs are retained, not used by the
# raw-logging observation suite below.
erlc -Werror +debug_info -I "$blackhole_frame_replay/src" -pa deps/lager/ebin \
    +'{parse_transform,lager_transform}' -o "$blackhole_frame_production" \
    "${blackhole_frame_replayed_sources[@]}" 2>&1 | tee "$blackhole_frame_output/production-compile.log"
printf 'PASS nine production Blackhole modules compiled with -Werror and Lager transform\n' \
    | tee -a "$blackhole_frame_output/production-compile.log"
# No Lager transform: the mock must observe raw format strings and arguments,
# regardless of backend configuration/log level. No TEST or export_all defines.
erlc -Werror +debug_info -I "$blackhole_frame_replay/src" -o "$blackhole_frame_output" \
    "${blackhole_frame_replayed_sources[@]}" scripts/erlang-tests/blackhole_frame_wire_tests.erl \
    2>&1 | tee "$blackhole_frame_output/compile.log"
sha256sum "${blackhole_frame_artifacts[@]}" >"$blackhole_frame_output/artifact-pins.sha256"
erl -pa "$blackhole_frame_output" -noshell -eval '
Root = os:getenv("KAZOO_BLACKHOLE_FRAME_ROOT"), Private = os:getenv("KAZOO_BLACKHOLE_FRAME_OUTPUT"),
Paths = fun(Name) -> {ok, Bin} = file:read_file(filename:join(Private, Name)),
    [binary_to_list(P) || P <- binary:split(Bin, <<"\n">>, [global]), P =/= <<>>] end,
Production = Paths("production-paths.txt"), Dependencies = Paths("dependency-paths.txt"),
Gate = fun() ->
    JiffyPriv = filename:join([Root, "deps", "jiffy", "priv"]), JiffyPriv = code:priv_dir(jiffy),
    {module, blackhole_frame_wire_tests} = code:ensure_loaded(blackhole_frame_wire_tests),
    TestPath = filename:join(Private, "blackhole_frame_wire_tests.beam"),
    TestPath = code:which(blackhole_frame_wire_tests),
    lists:foreach(fun(Source) ->
        Module = list_to_atom(filename:basename(Source, ".erl")),
        {module, Module} = code:ensure_loaded(Module),
        Expected = filename:join(Private, atom_to_list(Module) ++ ".beam"), Expected = code:which(Module),
        Options = proplists:get_value(options, Module:module_info(compile), []),
        false = lists:any(fun({d, '\''TEST'\''}) -> true; ({d, '\''TEST'\'', _}) -> true;
                             ({parse_transform, _}) -> true; (export_all) -> true; (_) -> false end, Options),
        ProductionBeam = filename:join([Private, "production", atom_to_list(Module) ++ ".beam"]),
        {ok, {Module, [{compile_info, CompileInfo}]}} = beam_lib:chunks(ProductionBeam, [compile_info]),
        ProductionOptions = proplists:get_value(options, CompileInfo, []),
        true = lists:member({parse_transform, lager_transform}, ProductionOptions),
        false = lists:any(fun({d, '\''TEST'\''}) -> true; ({d, '\''TEST'\'', _}) -> true;
                             (export_all) -> true; (_) -> false end, ProductionOptions)
    end, Production),
    lists:foreach(fun(Relative) ->
        Module = list_to_atom(filename:basename(Relative, ".beam")),
        {module, Module} = code:ensure_loaded(Module),
        Expected = filename:join(Root, Relative), Expected = code:which(Module)
    end, Dependencies)
end,
io:format("OTP ~s ERTS ~s; raw logging-call capture; pinned existing JSON NIF~n", [erlang:system_info(otp_release), erlang:system_info(version)]),
Gate(), io:format("PASS ~p fresh production modules/no transforms and ~p dependency paths~n", [length(Production), length(Dependencies)]),
Result = eunit:test(blackhole_frame_wire_tests, [verbose]),
Gate(), io:format("PASS post-test module path checks~n"),
case Result of ok -> halt(0); _ -> halt(1) end.' 2>&1 | tee "$blackhole_frame_output/eunit.log"
