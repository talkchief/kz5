#!/usr/bin/env bash
# Dashboard API regression only. Existing test-acdc-live.sh is unrelated and
# must not be replaced: it tests live lifecycle/storage fixtures.
set -Eeuo pipefail
umask 077
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS
live_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
live_test_dir=$(mktemp -d /tmp/kazoo-live-snapshot.XXXXXX)
cd "$live_root"
export ERL_LIBS="$live_root/deps:$live_root/core:$live_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP="$live_test_dir/erl_crash.dump"
export LIVE_SNAPSHOT_DIR="$live_test_dir"
live_exit() {
    local live_status=$?
    trap - EXIT
    if [[ -f "$live_test_dir/inputs.sha256" ]]; then
        if ! sha256sum --check "$live_test_dir/inputs.sha256"; then live_status=1; fi
    fi
    printf 'Live dashboard snapshot checks exit %s; retained evidence: %s\n' "$live_status" "$live_test_dir"
    exit "$live_status"
}
trap live_exit EXIT
mkdir "$live_test_dir/production" "$live_test_dir/test" "$live_test_dir/fixture"
live_sources=(applications/acdc/src/cb_acdc_live.erl applications/acdc/src/acdc_live_auth.erl applications/acdc/src/cb_queues.erl
    applications/acdc/src/cb_acdc_live_agents.erl applications/acdc/src/acdc_dashboard_agent_codec.erl
    applications/acdc/src/cb_agents.erl
    applications/acdc/src/kapi_acdc_dashboard.erl applications/crossbar/src/cb_context.erl
    applications/crossbar/src/api_util.erl applications/crossbar/src/crossbar_util.erl
    core/kazoo_documents/src/kz_doc.erl core/kazoo_data/src/kzs_util.erl
    core/kazoo_stdlib/src/kz_json.erl core/kazoo_stdlib/src/kz_term.erl
    core/kazoo_stdlib/src/props.erl core/kazoo_amqp/src/api/kz_api.erl)
live_inputs=("${live_sources[@]}" scripts/erlang-tests/acdc_live_tests.erl scripts/erlang-tests/acdc_live_agents_tests.erl scripts/test-acdc-live-snapshot.sh
    scripts/test-acdc-live-response-contract.cjs scripts/api-docs-queue-live.cjs
    scripts/api-docs-tooling/package-lock.json /usr/bin/node)
/usr/bin/find applications/acdc/src applications/acdc/include applications/crossbar/src \
    core/kazoo_stdlib/include core/kazoo_amqp/include core/kazoo_documents/include core/kazoo_data/src \
    -type f -name '*.hrl' > "$live_test_dir/headers.list"
LC_ALL=C /usr/bin/sort -o "$live_test_dir/headers.list" "$live_test_dir/headers.list"
while IFS= read -r live_header; do live_inputs+=("$live_header"); done < "$live_test_dir/headers.list"
sha256sum "${live_inputs[@]}" > "$live_test_dir/inputs.sha256"
# This bounded proof rebuilds only live_sources above. Other runtime dependencies
# (including meck/lager and OTP) are prebuilt fallbacks, not rebuilt or source-pinned.
printf 'Dependency scope: listed production sources rebuilt and pinned; remaining ERL_LIBS/OTP dependencies are prebuilt, unrebuilt and unpinned. ERL_LIBS=%s\n' "$ERL_LIBS" \
    | tee "$live_test_dir/dependency-scope.log"
# Production proof first: no TEST exports/branches in these compiled modules.
erlc -Werror +warn_missing_spec +debug_info \
    -I applications/acdc/src -I applications/acdc/include \
    -I applications/crossbar/src -I applications/crossbar/include \
    -I core/kazoo_amqp/include -I core/kazoo_amqp/src \
    -I core/kazoo_data/include -I core/kazoo_data/src \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' \
    -o "$live_test_dir/production" "${live_sources[@]}"
# Only the pure test exports of this module are added in the separate build.
erlc -DTEST -Werror +debug_info \
    -I applications/crossbar/src -I applications/crossbar/include \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' \
    -o "$live_test_dir/test" applications/acdc/src/cb_acdc_live.erl
erlc -Werror +debug_info -o "$live_test_dir/fixture" scripts/erlang-tests/acdc_live_tests.erl scripts/erlang-tests/acdc_live_agents_tests.erl
# Exercise the real public-route cases with the production beam only.
erl -noshell -pa "$live_test_dir/production" -pa "$live_test_dir/fixture" \
    -eval '
        {module, cb_acdc_live} = code:ensure_loaded(cb_acdc_live),
        Expected = filename:join([os:getenv("LIVE_SNAPSHOT_DIR"), "production", "cb_acdc_live.beam"]),
        Expected = code:which(cb_acdc_live),
        Options = proplists:get_value(options, cb_acdc_live:module_info(compile), []),
        false = lists:any(fun({d, '\''TEST'\''}) -> true; ({d, '\''TEST'\'', _}) -> true; (_) -> false end, Options),
        false = erlang:function_exported(cb_acdc_live, options, 2),
        io:format("Production public-route beam: ~s; compile options: ~p~n", [Expected, Options]),
        case eunit:test([{generator, fun acdc_live_tests:public_route_test_/0}, acdc_live_agents_tests], [verbose]) of
            ok -> halt(0); _ -> halt(1)
        end.' \
    | tee "$live_test_dir/eunit-public-production.log"
/usr/bin/node scripts/test-acdc-live-response-contract.cjs "$live_test_dir/public-responses.ndjson" \
    | tee "$live_test_dir/response-contract.log"
# A separate VM loads TEST exports solely for the two pure helper cases.
erl -noshell -pa "$live_test_dir/production" -pa "$live_test_dir/test" -pa "$live_test_dir/fixture" \
    -eval '
        {module, cb_acdc_live} = code:ensure_loaded(cb_acdc_live),
        Expected = filename:join([os:getenv("LIVE_SNAPSHOT_DIR"), "test", "cb_acdc_live.beam"]),
        Expected = code:which(cb_acdc_live),
        Options = proplists:get_value(options, cb_acdc_live:module_info(compile), []),
        true = lists:any(fun({d, '\''TEST'\''}) -> true; ({d, '\''TEST'\'', _}) -> true; (_) -> false end, Options),
        true = erlang:function_exported(cb_acdc_live, options, 2),
        io:format("TEST helper beam: ~s; compile options: ~p~n", [Expected, Options]),
        case eunit:test([fun acdc_live_tests:bounded_options_test/0,
                         fun acdc_live_tests:replica_assessment_test/0], [verbose]) of
            ok -> halt(0); _ -> halt(1)
        end.' \
    | tee "$live_test_dir/eunit-pure-helpers.log"
