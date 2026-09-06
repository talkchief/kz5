#!/usr/bin/env bash
# Offline public-entry-point redaction checks; no JWT/live socket proof.
set -Eeuo pipefail
umask 077
[[ $# == 0 ]] || { printf 'Usage: %s\n' "$0" >&2; exit 2; }
blackhole_test_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
blackhole_test_output=$(mktemp -d /tmp/kazoo-blackhole-redaction.XXXXXX)
readonly blackhole_test_ref=4e3f02a5ab01c09a44c287f4f93b15d2782f5614
blackhole_test_repo="$blackhole_test_root/applications/blackhole"
blackhole_test_replay="$blackhole_test_output/replay"
blackhole_test_production="$blackhole_test_output/production"
blackhole_test_patch="$blackhole_test_root/scripts/patches/blackhole-kazoo5-integration.patch"
cd "$blackhole_test_root"
blackhole_test_sources=(
    applications/blackhole/src/modules/bh_token_auth.erl
    applications/blackhole/src/bh_context.erl
    applications/blackhole/src/bh_events.erl
    applications/blackhole/src/blackhole_bindings.erl
    applications/blackhole/src/blackhole_socket_callback.erl
    applications/blackhole/src/blackhole_data_emitter.erl
    applications/blackhole/src/blackhole_socket_handler.erl
)
# Existing utilities and mock-provider metadata are pinned bytecode, not fresh
# production rebuilds. This is a bounded list, not a full dependency closure.
blackhole_test_dependencies=(
    core/kazoo_bindings/ebin/kazoo_bindings.beam
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
    applications/blackhole/ebin/blackhole_tracking.beam
    deps/cowboy/ebin/cowboy_req.beam
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
)
blackhole_test_other_inputs=(
    scripts/test-blackhole-auth-redaction.sh
    scripts/erlang-tests/blackhole_auth_redaction_tests.erl
    scripts/patches/blackhole-kazoo5-integration.patch
    scripts/install-kazoo5.sh
    applications/blackhole/src/blackhole.hrl
    core/kazoo_stdlib/include/kz_types.hrl
    core/kazoo_stdlib/include/kz_records.hrl
    core/kazoo_stdlib/include/kz_log.hrl
    core/kazoo_stdlib/include/kz_databases.hrl
    deps/jiffy/ebin/jiffy.app
    deps/jiffy/priv/jiffy.so
)
for blackhole_test_input in "${blackhole_test_sources[@]}" "${blackhole_test_dependencies[@]}" "${blackhole_test_other_inputs[@]}"; do
    [[ -f $blackhole_test_input && ! -L $blackhole_test_input ]] || {
        printf 'Missing or symlinked redaction input: %s\n' "$blackhole_test_input" >&2
        exit 2
    }
done
sha256sum "${blackhole_test_sources[@]}" "${blackhole_test_dependencies[@]}" \
    "${blackhole_test_other_inputs[@]}" >"$blackhole_test_output/input-pins.sha256"
printf '%s\n' "${blackhole_test_sources[@]}" >"$blackhole_test_output/production-paths.txt"
printf '%s\n' "${blackhole_test_dependencies[@]}" >"$blackhole_test_output/dependency-paths.txt"
finish() {
    local blackhole_test_status=$?
    trap - EXIT
    if ! sha256sum --check --status "$blackhole_test_output/input-pins.sha256"; then
        printf 'FAIL redaction source or dependency bytes changed during validation\n' >&2
        blackhole_test_status=99
    fi
    for blackhole_test_manifest in replay-pins.sha256 artifact-pins.sha256; do
        if [[ -f $blackhole_test_output/$blackhole_test_manifest ]] &&
           ! sha256sum --check --status "$blackhole_test_output/$blackhole_test_manifest"; then
            printf 'FAIL retained replay or compiled artifact changed: %s\n' "$blackhole_test_manifest" >&2
            blackhole_test_status=99
        fi
    done
    printf 'Blackhole redaction exit=%s; retained private evidence: %s\n' "$blackhole_test_status" "$blackhole_test_output"
    exit "$blackhole_test_status"
}
trap finish EXIT
[[ $(git -C "$blackhole_test_repo" rev-parse HEAD) == "$blackhole_test_ref" ]] || {
    printf 'Blackhole checkout is not the tested pinned revision\n' >&2; exit 2;
}
# Source assertions only: this test never sources or runs the installer.
blackhole_test_hooks=(
    'KAZOO_BLACKHOLE_REF=${KAZOO_BLACKHOLE_REF:-4e3f02a5ab01c09a44c287f4f93b15d2782f5614}'
    'KAZOO_CROSSBAR_REF KAZOO_BLACKHOLE_REF KAZOO_ECALLMGR_REF'
    '$KAZOO_BLACKHOLE_REF =~ ^[0-9a-f]{40}$'
    '[[ $(git -C "$KAZOO_ROOT/applications/blackhole" rev-parse HEAD) == "$KAZOO_BLACKHOLE_REF" ]]'
    '"dep_blackhole=git https://github.com/2600hz/kazoo-blackhole.git $KAZOO_BLACKHOLE_REF"'
    'apply_kazoo_integration_patch blackhole'
    'transition_new=blackhole-kazoo5-integration.patch'
)
for blackhole_test_hook in "${blackhole_test_hooks[@]}"; do
    /usr/bin/grep -Fq -- "$blackhole_test_hook" scripts/install-kazoo5.sh || {
        printf 'Missing Blackhole installer pin/patch integration hook\n' >&2; exit 2;
    }
done
mkdir -m 0700 "$blackhole_test_replay" "$blackhole_test_production"
blackhole_test_relative_sources=()
blackhole_test_replayed_sources=()
blackhole_test_artifacts=("$blackhole_test_output/blackhole_auth_redaction_tests.beam")
for blackhole_test_source in "${blackhole_test_sources[@]}"; do
    blackhole_test_relative=${blackhole_test_source#applications/blackhole/}
    blackhole_test_relative_sources+=("$blackhole_test_relative")
    blackhole_test_replayed_sources+=("$blackhole_test_replay/$blackhole_test_relative")
    blackhole_test_module=${blackhole_test_relative##*/}
    blackhole_test_artifacts+=("$blackhole_test_production/${blackhole_test_module%.erl}.beam"
                              "$blackhole_test_output/${blackhole_test_module%.erl}.beam")
done
git -C "$blackhole_test_repo" archive "$blackhole_test_ref" \
    "${blackhole_test_relative_sources[@]}" src/blackhole.hrl | tar -xf - -C "$blackhole_test_replay"
git -C "$blackhole_test_replay" apply --check "$blackhole_test_patch"
git -C "$blackhole_test_replay" apply "$blackhole_test_patch"
git -C "$blackhole_test_replay" apply --reverse --check "$blackhole_test_patch"
if git -C "$blackhole_test_replay" apply --check "$blackhole_test_patch" 2>/dev/null; then
    printf 'Blackhole redaction patch unexpectedly applies twice\n' >&2; exit 2
fi
for blackhole_test_relative in "${blackhole_test_relative_sources[@]}" src/blackhole.hrl; do
    cmp -- "$blackhole_test_repo/$blackhole_test_relative" "$blackhole_test_replay/$blackhole_test_relative"
done
sha256sum "${blackhole_test_replayed_sources[@]}" "$blackhole_test_replay/src/blackhole.hrl" \
    >"$blackhole_test_output/replay-pins.sha256"
printf 'PASS pinned Blackhole %s patch replay, source equality, reverse/idempotence and installer hooks\n' \
    "$blackhole_test_ref" | tee "$blackhole_test_output/replay.log"
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS ERL_INETRC
export ERL_LIBS="$blackhole_test_root/deps:$blackhole_test_root/core:$blackhole_test_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
export KAZOO_BLACKHOLE_TEST_ROOT="$blackhole_test_root" KAZOO_BLACKHOLE_TEST_OUTPUT="$blackhole_test_output"
# Separate real production compile evidence: same source replay, with the Lager
# transform and warnings-as-errors. These BEAMs are retained, not used by the
# raw-logging observation suite below.
erlc -Werror +debug_info -I "$blackhole_test_replay/src" -pa deps/lager/ebin \
    +'{parse_transform,lager_transform}' -o "$blackhole_test_production" \
    "${blackhole_test_replayed_sources[@]}" 2>&1 | tee "$blackhole_test_output/production-compile.log"
printf 'PASS seven production Blackhole modules compiled with -Werror and Lager transform\n' \
    | tee -a "$blackhole_test_output/production-compile.log"
# No Lager transform: the mock must observe raw format strings and arguments,
# regardless of backend configuration/log level. No TEST or export_all defines.
erlc -Werror +debug_info -I "$blackhole_test_replay/src" -o "$blackhole_test_output" \
    "${blackhole_test_replayed_sources[@]}" scripts/erlang-tests/blackhole_auth_redaction_tests.erl \
    2>&1 | tee "$blackhole_test_output/compile.log"
sha256sum "${blackhole_test_artifacts[@]}" >"$blackhole_test_output/artifact-pins.sha256"
erl -pa "$blackhole_test_output" -noshell -eval '
Root = os:getenv("KAZOO_BLACKHOLE_TEST_ROOT"), Private = os:getenv("KAZOO_BLACKHOLE_TEST_OUTPUT"),
Paths = fun(Name) -> {ok, Bin} = file:read_file(filename:join(Private, Name)),
    [binary_to_list(P) || P <- binary:split(Bin, <<"\n">>, [global]), P =/= <<>>] end,
Production = Paths("production-paths.txt"), Dependencies = Paths("dependency-paths.txt"),
Gate = fun() ->
    JiffyPriv = filename:join([Root, "deps", "jiffy", "priv"]), JiffyPriv = code:priv_dir(jiffy),
    {module, blackhole_auth_redaction_tests} = code:ensure_loaded(blackhole_auth_redaction_tests),
    TestPath = filename:join(Private, "blackhole_auth_redaction_tests.beam"),
    TestPath = code:which(blackhole_auth_redaction_tests),
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
Result = eunit:test(blackhole_auth_redaction_tests, [verbose]),
Gate(), io:format("PASS post-test module path checks~n"),
case Result of ok -> halt(0); _ -> halt(1) end.' 2>&1 | tee "$blackhole_test_output/eunit.log"
