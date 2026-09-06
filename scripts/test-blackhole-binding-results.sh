#!/usr/bin/env bash
# Pure production filter regression. Retained private compile, no live node.
set -Eeuo pipefail
umask 077
[[ $# == 0 ]] || exit 2
binding_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
binding_output=$(mktemp -d /tmp/kazoo-blackhole-bindings.XXXXXX)
cd "$binding_root"
binding_sources=(applications/blackhole/src/blackhole_bindings.erl applications/blackhole/src/bh_context.erl)
binding_inputs=("${binding_sources[@]}" scripts/test-blackhole-binding-results.sh
    scripts/erlang-tests/blackhole_binding_results_tests.erl applications/blackhole/src/blackhole.hrl
    core/kazoo_stdlib/include/kz_types.hrl core/kazoo_stdlib/include/kz_records.hrl
    core/kazoo_stdlib/include/kz_log.hrl core/kazoo_stdlib/include/kz_databases.hrl)
binding_deps=(core/kazoo_bindings/ebin/kazoo_bindings.beam core/kazoo_nodes/ebin/kz_nodes.beam
    core/kazoo_stdlib/ebin/kz_term.beam core/kazoo_stdlib/ebin/kz_binary.beam
    core/kazoo_stdlib/ebin/kz_time.beam deps/lager/ebin/lager_transform.beam
    deps/lager/ebin/lager_util.beam)
sha256sum "${binding_inputs[@]}" "${binding_deps[@]}" >"$binding_output/input-pins.sha256"
finish() {
    local binding_status=$?
    trap - EXIT
    sha256sum --check --status "$binding_output/input-pins.sha256" || binding_status=99
    printf 'Binding result test exit=%s; retained evidence %s\n' "$binding_status" "$binding_output"
    exit "$binding_status"
}
trap finish EXIT
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS ERL_INETRC
export ERL_LIBS="$binding_root/deps:$binding_root/core:$binding_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1' ERL_CRASH_DUMP=/dev/null
erlc -Werror +debug_info -I applications/blackhole/src -pa deps/lager/ebin \
    +'{parse_transform,lager_transform}' -o "$binding_output" "${binding_sources[@]}" \
    2>&1 | tee "$binding_output/compile.log"
erlc -Werror -o "$binding_output" scripts/erlang-tests/blackhole_binding_results_tests.erl
export KAZOO_BINDING_TEST_OUTPUT="$binding_output" KAZOO_BINDING_TEST_ROOT="$binding_root"
erl -pa "$binding_output" -noshell -eval '
Private = os:getenv("KAZOO_BINDING_TEST_OUTPUT"), Root = os:getenv("KAZOO_BINDING_TEST_ROOT"),
lists:foreach(fun(M) -> {module,M} = code:ensure_loaded(M),
    Expected = filename:join(Private, atom_to_list(M) ++ ".beam"), Expected = code:which(M),
    Opts = proplists:get_value(options, M:module_info(compile), []),
    false = lists:any(fun({d, '\''TEST'\''}) -> true; ({d, '\''TEST'\'', _}) -> true; (export_all) -> true; (_) -> false end, Opts)
end, [blackhole_bindings, bh_context, blackhole_binding_results_tests]),
lists:foreach(fun({M, Path}) -> {module,M} = code:ensure_loaded(M),
    Expected = filename:join(Root, Path), Expected = code:which(M)
end, [{kazoo_bindings,"core/kazoo_bindings/ebin/kazoo_bindings.beam"},
      {kz_nodes,"core/kazoo_nodes/ebin/kz_nodes.beam"},
      {kz_term,"core/kazoo_stdlib/ebin/kz_term.beam"},
      {kz_binary,"core/kazoo_stdlib/ebin/kz_binary.beam"},
      {kz_time,"core/kazoo_stdlib/ebin/kz_time.beam"}]),
case eunit:test(blackhole_binding_results_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.' \
    2>&1 | tee "$binding_output/eunit.log"
