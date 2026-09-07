#!/usr/bin/env bash
# Offline focused proof; no service, database or broker changes.
set -Eeuo pipefail
umask 077
unset ERL_AFLAGS ERL_ZFLAGS ERL_COMPILER_OPTIONS ERL_INETRC
types_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
types_mode=${1:-current}
[[ $# -le 1 && ( $types_mode == current || $types_mode == --baseline ) ]] || exit 2
types_output=$(mktemp -d /tmp/kazoo-queue-content-types.XXXXXX)
cd "$types_root"
export ERL_LIBS="$types_root/deps:$types_root/core:$types_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP="$types_output/erl_crash.dump"
export ACDC_TYPES_OUTPUT="$types_output"
types_exit() {
    local rc=$?
    trap - EXIT
    if [[ -f "$types_output/inputs.sha256" ]]; then
        sha256sum --check --status "$types_output/inputs.sha256" || rc=99
    fi
    printf 'Queue content negotiation %s exit %s; evidence: %s\n' "$types_mode" "$rc" "$types_output"
    exit "$rc"
}
trap types_exit EXIT
types_queue=applications/acdc/src/cb_queues.erl
if [[ $types_mode == --baseline ]]; then
    git show d7992ca:applications/acdc/src/cb_queues.erl > "$types_output/cb_queues.erl"
    types_queue="$types_output/cb_queues.erl"
fi
types_inputs=("$types_queue" applications/crossbar/src/cb_context.erl
    applications/acdc/ebin/acdc.app applications/crossbar/ebin/crossbar.app
    scripts/test-acdc-queue-content-types.sh scripts/erlang-tests/acdc_queue_content_types_tests.erl)
while IFS= read -r header; do types_inputs+=("$header"); done < <(
    find applications/acdc/src applications/acdc/include applications/crossbar/src \
        core/kazoo_stdlib/include core/kazoo_amqp/include core/kazoo_documents/include \
        -type f -name '*.hrl' | LC_ALL=C sort)
sha256sum "${types_inputs[@]}" > "$types_output/inputs.sha256"
mkdir "$types_output/acdc" "$types_output/crossbar"
# Lager infers the application metadata from the compiler output directory.
# Keep the production app tags and never attribute cb_context logs to ACDC.
cp applications/acdc/ebin/acdc.app "$types_output/acdc/acdc.app"
cp applications/crossbar/ebin/crossbar.app "$types_output/crossbar/crossbar.app"
erlc -Werror +warn_missing_spec +debug_info -I applications/acdc/src -I applications/acdc/include \
    -I applications/crossbar/src -pa deps/lager/ebin +'{parse_transform,lager_transform}' \
    -o "$types_output/acdc" "$types_queue"
erlc -Werror +warn_missing_spec +debug_info -I applications/crossbar/src \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' \
    -o "$types_output/crossbar" applications/crossbar/src/cb_context.erl
erlc -Werror +debug_info -o "$types_output" scripts/erlang-tests/acdc_queue_content_types_tests.erl
sha256sum "$types_output/acdc/cb_queues.beam" "$types_output/crossbar/cb_context.beam" > "$types_output/artifacts.sha256"
erl -noshell -pa "$types_output" "$types_output/acdc" "$types_output/crossbar" -eval '
    lists:foreach(fun(M)->
        {module,M}=code:ensure_loaded(M),
        App=case M of cb_queues->"acdc";cb_context->"crossbar" end,
        Expected=filename:join([os:getenv("ACDC_TYPES_OUTPUT"),App,atom_to_list(M)++".beam"]),
        Expected=code:which(M),
        Options=proplists:get_value(options,M:module_info(compile),[]),
        false=lists:any(fun({d,'\''TEST'\''})->true;({d,'\''TEST'\'',_})->true;(export_all)->true;(_)->false end,Options)
    end,[cb_queues,cb_context]),
    case eunit:test(acdc_queue_content_types_tests,[verbose]) of ok->halt(0);_->halt(1) end.' \
    | tee "$types_output/eunit.log"
printf 'Scope: direct real production cb_queues/cb_context callbacks; no HTTP/bindings/cluster proof. Remaining ERL_LIBS dependencies prebuilt.\n'
