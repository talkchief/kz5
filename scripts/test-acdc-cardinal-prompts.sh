#!/usr/bin/env bash
# Offline pure grammar tests; private BEAMs only, no provider/runtime/media I/O.
set -Eeuo pipefail
cardinal_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cardinal_build=$(mktemp -d /tmp/kazoo-cardinal-prompts.XXXXXX)
trap 'printf "Private cardinal grammar artifacts: %s\n" "$cardinal_build"' EXIT
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
inputs=("$cardinal_root/applications/acdc/src/acdc_cardinal_prompts.erl"
        "$cardinal_root/scripts/erlang-tests/acdc_cardinal_prompts_tests.erl"
        "$cardinal_root/scripts/test-fixtures/acdc-cardinal-en-parity.cjs"
        "$cardinal_root/scripts/acdc-cardinal-catalog.cjs"
        "$cardinal_root/scripts/test-acdc-cardinal-prompts.sh"
        "$cardinal_root/scripts/test-fixtures/acdc-cardinal-multilingual-parity.cjs")
before=$(sha256sum -- "${inputs[@]}" | sha256sum | cut -d ' ' -f 1)
node "$cardinal_root/scripts/test-fixtures/acdc-cardinal-en-parity.cjs" > "$cardinal_build/parity.terms"
node "$cardinal_root/scripts/test-fixtures/acdc-cardinal-multilingual-parity.cjs" > "$cardinal_build/multilingual.terms"
erlc -Werror +warn_missing_spec -o "$cardinal_build" "${inputs[0]}"
erlc -Werror -o "$cardinal_build" "${inputs[1]}"
KAZOO_CARDINAL_PARITY_FIXTURE="$cardinal_build/parity.terms" \
KAZOO_CARDINAL_MULTILINGUAL_FIXTURE="$cardinal_build/multilingual.terms" \
erl -noshell -pa "$cardinal_build" \
    -eval 'case eunit:test(acdc_cardinal_prompts_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
after=$(sha256sum -- "${inputs[@]}" | sha256sum | cut -d ' ' -f 1)
[[ $before == "$after" ]] || { printf '%s\n' 'Cardinal test source changed during validation' >&2; exit 1; }
printf 'PASS five-language prerecorded grammar: 73240 JS-parity cases with per-language bounds; input SHA-256 %s\n' "$after"
