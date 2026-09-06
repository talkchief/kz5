#!/usr/bin/env bash
# Offline auth/validation proof only. No shared ebin, live HTTP/RPC or config writes.
set -Eeuo pipefail
umask 077
[[ $# == 0 ]] || { printf 'Usage: %s\n' "$0" >&2; exit 2; }
auth_editor_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
auth_editor_output=$(mktemp -d /tmp/kazoo-queue-editor-auth.XXXXXX)
auth_editor_completed=0
cd "$auth_editor_root"
auth_editor_sources=(
    applications/crossbar/src/api_util.erl
    applications/crossbar/src/cb_context.erl
    applications/crossbar/src/crossbar_bindings.erl
    applications/crossbar/src/crossbar_util.erl
    applications/crossbar/src/crossbar_auth.erl
    applications/crossbar/src/modules/cb_token_auth.erl
    applications/crossbar/src/modules/cb_simple_authz.erl
    applications/crossbar/src/modules/cb_token_restrictions.erl
    applications/crossbar/src/modules/cb_users.erl
    applications/crossbar/src/modules/cb_media.erl
    applications/crossbar/src/modules/cb_phone_numbers.erl
    core/kazoo_auth/src/kz_auth.erl
    core/kazoo_auth/src/kz_auth_jwt.erl
    core/kazoo_auth/src/kz_auth_scope.erl
    applications/acdc/src/cb_acdc_queue_editor.erl
)
# Existing utility/matcher and mock-provider metadata are dependencies, NOT
# freshly compiled production source. Pin their actual BEAM bytes and paths.
# This list does not claim a rebuild of every transitive Erlang/OTP dependency.
auth_editor_dependencies=(
    core/kazoo_bindings/ebin/kazoo_bindings.beam
    core/kazoo_documents/ebin/kz_doc.beam
    core/kazoo_documents/ebin/kzd_accounts.beam
    core/kazoo_stdlib/ebin/kz_json.beam
    core/kazoo_stdlib/ebin/kz_term.beam
    core/kazoo_stdlib/ebin/kz_binary.beam
    core/kazoo_stdlib/ebin/kz_time.beam
    core/kazoo_stdlib/ebin/props.beam
    core/kazoo_stdlib/ebin/kz_base64url.beam
    core/kazoo_schemas/ebin/kz_json_schema.beam
    core/kazoo_data/ebin/kzs_util.beam
    core/kazoo_data/ebin/kz_datamgr.beam
    core/kazoo_apps/ebin/kapps_config.beam
    core/kazoo_apps/ebin/kz_amqp_worker.beam
    core/kazoo_auth/ebin/kz_auth_keys.beam
    core/kazoo_auth/ebin/kz_auth_identity.beam
    applications/acdc/ebin/cb_queues.beam
    applications/crossbar/ebin/cb_callflows.beam
    deps/meck/ebin/meck.beam
    deps/meck/ebin/meck_proc.beam
    deps/meck/ebin/meck_code.beam
    deps/meck/ebin/meck_code_gen.beam
    deps/meck/ebin/meck_util.beam
    deps/meck/ebin/meck_ret_spec.beam
    deps/meck/ebin/meck_expect.beam
    deps/meck/ebin/meck_args_matcher.beam
    deps/meck/ebin/meck_cover.beam
    deps/meck/ebin/meck_history.beam
    deps/meck/ebin/meck_matcher.beam
    deps/lager/ebin/lager.beam
    deps/lager/ebin/lager_transform.beam
    deps/lager/ebin/lager_util.beam
    deps/lager/ebin/lager_config.beam
    deps/jiffy/ebin/jiffy.beam
    deps/jiffy/ebin/jiffy_utf8.beam
)
auth_editor_native_inputs=(deps/jiffy/priv/jiffy.so deps/jiffy/ebin/jiffy.app)
auth_editor_test=scripts/erlang-tests/acdc_queue_editor_real_auth_tests.erl
for auth_editor_input in "${auth_editor_sources[@]}" "${auth_editor_dependencies[@]}" "${auth_editor_native_inputs[@]}" "$auth_editor_test"; do
    [[ -f $auth_editor_input && ! -L $auth_editor_input ]] || {
        printf 'Missing or symlinked auth fixture input: %s\n' "$auth_editor_input" >&2
        exit 2
    }
done
sha256sum scripts/test-acdc-queue-editor-real-auth.sh "$auth_editor_test" \
    "${auth_editor_sources[@]}" >"$auth_editor_output/source-pins.sha256"
sha256sum "${auth_editor_dependencies[@]}" "${auth_editor_native_inputs[@]}" >"$auth_editor_output/dependency-pins.sha256"
printf '%s\n' "${auth_editor_sources[@]}" >"$auth_editor_output/production-paths.txt"
printf '%s\n' "${auth_editor_dependencies[@]}" >"$auth_editor_output/dependency-paths.txt"
finish() {
    local auth_editor_status=$?
    trap - EXIT
    if [[ $auth_editor_status == 0 && $auth_editor_completed != 1 ]]; then
        printf 'FAIL auth fixture validation interrupted before completion\n' >&2
        auth_editor_status=99
    fi
    if ! sha256sum --check --status "$auth_editor_output/source-pins.sha256" ||
       ! sha256sum --check --status "$auth_editor_output/dependency-pins.sha256"; then
        printf 'FAIL auth fixture source or dependency bytes changed during validation\n' >&2
        auth_editor_status=99
    fi
    printf 'Queue editor real-auth exit=%s; retained private evidence: %s\n' "$auth_editor_status" "$auth_editor_output"
    exit "$auth_editor_status"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Prevent inherited compiler defines/code-path flags from changing auth gates.
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS ERL_INETRC
export ERL_LIBS="$auth_editor_root/deps:$auth_editor_root/core:$auth_editor_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
export KAZOO_EDITOR_AUTH_TEST_ROOT="$auth_editor_root" KAZOO_EDITOR_AUTH_TEST_OUTPUT="$auth_editor_output"
# Deliberately NO -DTEST anywhere: the fixture uses public editor functions and
# cb_token_restrictions must retain production lookup/hierarchy implementation.
for auth_editor_source in "${auth_editor_sources[@]}"; do
    printf 'Compiling production source: %s\n' "$auth_editor_source" | tee -a "$auth_editor_output/compile.log"
    erlc +debug_info -Werror -I applications/crossbar/src -I applications/acdc/src \
        -I applications/acdc/include -pa deps/lager/ebin +'{parse_transform,lager_transform}' \
        -o "$auth_editor_output" "$auth_editor_source" 2>&1 | tee -a "$auth_editor_output/compile.log"
done
erlc +debug_info -Werror -o "$auth_editor_output" "$auth_editor_test" \
    2>&1 | tee -a "$auth_editor_output/compile.log"
erl -pa "$auth_editor_output" -noshell -eval '
Root = os:getenv("KAZOO_EDITOR_AUTH_TEST_ROOT"), Private = os:getenv("KAZOO_EDITOR_AUTH_TEST_OUTPUT"),
Paths = fun(Name) -> {ok, Bin} = file:read_file(filename:join(Private, Name)),
    [binary_to_list(P) || P <- binary:split(Bin, <<"\n">>, [global]), P =/= <<>>] end,
Production = Paths("production-paths.txt"), Dependencies = Paths("dependency-paths.txt"),
Gate = fun() ->
    JiffyPriv = filename:join([Root, "deps", "jiffy", "priv"]), JiffyPriv = code:priv_dir(jiffy),
    {module, acdc_queue_editor_real_auth_tests} = code:ensure_loaded(acdc_queue_editor_real_auth_tests),
    TestPath = filename:join(Private, "acdc_queue_editor_real_auth_tests.beam"),
    TestPath = code:which(acdc_queue_editor_real_auth_tests),
    lists:foreach(fun(Source) ->
        Module = list_to_atom(filename:basename(Source, ".erl")),
        {module, Module} = code:ensure_loaded(Module),
        Expected = filename:join(Private, atom_to_list(Module) ++ ".beam"),
        Expected = code:which(Module),
        Options = proplists:get_value(options, Module:module_info(compile), []),
        false = lists:any(fun({d, '\''TEST'\''}) -> true; ({d, '\''TEST'\'', _}) -> true; (_) -> false end, Options)
    end, Production),
    lists:foreach(fun(Relative) ->
        Module = list_to_atom(filename:basename(Relative, ".beam")),
        {module, Module} = code:ensure_loaded(Module),
        Expected = filename:join(Root, Relative), Expected = code:which(Module)
    end, Dependencies)
end,
io:format("OTP ~s ERTS ~s; existing pinned JSON NIF, no native compilation~n", [erlang:system_info(otp_release), erlang:system_info(version)]),
Gate(), io:format("PASS ~p production module paths/no-TEST defines and ~p pinned dependency paths~n", [length(Production), length(Dependencies)]),
Result = eunit:test(acdc_queue_editor_real_auth_tests, [verbose]),
Gate(), io:format("PASS post-test module path/no-TEST checks~n"),
case Result of ok -> halt(0); _ -> halt(1) end.' 2>&1 | tee "$auth_editor_output/eunit.log"
auth_editor_completed=1
