#!/usr/bin/env bash
# Offline shared live authorization; no broker/HTTP/socket/service operations.
set -Eeuo pipefail
umask 077
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS ERL_INETRC
auth_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
auth_output=$(mktemp -d /tmp/kazoo-live-auth.XXXXXX)
cd "$auth_root"
export ERL_LIBS="$auth_root/deps:$auth_root/core:$auth_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP="$auth_output/erl_crash.dump"
export ACDC_LIVE_AUTH_OUTPUT="$auth_output"
auth_exit() {
    local auth_status=$?
    trap - EXIT
    if [[ -f "$auth_output/inputs.sha256" ]]; then
        if ! sha256sum --check "$auth_output/inputs.sha256"; then auth_status=1; fi
    fi
    printf 'Live auth checks exit %s; retained evidence: %s\n' "$auth_status" "$auth_output"
    exit "$auth_status"
}
trap auth_exit EXIT
auth_sources=(applications/acdc/src/acdc_live_auth.erl applications/acdc/src/cb_acdc_live.erl
    applications/acdc/src/cb_queues.erl applications/acdc/src/cb_agents.erl
    applications/crossbar/src/modules/cb_token_auth.erl
    applications/crossbar/src/crossbar_bindings.erl applications/crossbar/src/cb_context.erl
    applications/crossbar/src/api_util.erl applications/crossbar/src/crossbar_util.erl
    core/kazoo_bindings/src/kazoo_bindings.erl core/kazoo_bindings/src/kazoo_bindings_rt.erl
    core/kazoo_documents/src/kz_doc.erl core/kazoo_data/src/kzs_util.erl
    core/kazoo_stdlib/src/kz_json.erl core/kazoo_stdlib/src/kz_term.erl
    core/kazoo_stdlib/src/props.erl)
auth_inputs=("${auth_sources[@]}" scripts/test-acdc-live-auth.sh
    scripts/erlang-tests/acdc_live_auth_tests.erl applications/crossbar/src/crossbar_auth.erl
    core/kazoo_auth/src/kz_auth.erl core/kazoo_auth/src/kz_auth_jwt.erl)
/usr/bin/find applications/acdc/src applications/acdc/include applications/crossbar/src core/kazoo_bindings/src \
    core/kazoo_stdlib/include core/kazoo_amqp/include core/kazoo_documents/include core/kazoo_data/src \
    -type f -name '*.hrl' > "$auth_output/headers.list"
LC_ALL=C /usr/bin/sort -o "$auth_output/headers.list" "$auth_output/headers.list"
while IFS= read -r auth_header; do auth_inputs+=("$auth_header"); done < "$auth_output/headers.list"
sha256sum "${auth_inputs[@]}" > "$auth_output/inputs.sha256"
printf 'Scope: listed modules rebuilt without TEST; remaining ERL_LIBS/OTP dependencies are prebuilt, unrebuilt and unpinned. Token validation provider is controlled; native cb_token_auth expiry handling and real binding registry are exercised, not JWT cryptography or global revocation.\n' \
    | tee "$auth_output/scope.log"
erlc -Werror +warn_missing_spec +debug_info \
    -I applications/acdc/src -I applications/acdc/include -I applications/crossbar/src -I core/kazoo_bindings/src \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' -o "$auth_output" "${auth_sources[@]}"
erlc -Werror +debug_info -o "$auth_output" scripts/erlang-tests/acdc_live_auth_tests.erl
erl -noshell -pa "$auth_output" -eval '
    lists:foreach(fun(M) ->
        {module,M}=code:ensure_loaded(M),
        Expected=filename:join(os:getenv("ACDC_LIVE_AUTH_OUTPUT"),atom_to_list(M)++".beam"),
        Expected=code:which(M),
        Options=proplists:get_value(options,M:module_info(compile),[]),
        false=lists:any(fun({d,'\''TEST'\''})->true;({d,'\''TEST'\'',_})->true;(export_all)->true;(_)->false end,Options)
    end,[acdc_live_auth,cb_acdc_live,cb_agents,cb_token_auth,crossbar_bindings,kazoo_bindings,cb_context]),
    case eunit:test(acdc_live_auth_tests,[verbose]) of ok->halt(0);_->halt(1) end.' \
    | tee "$auth_output/eunit.log"
