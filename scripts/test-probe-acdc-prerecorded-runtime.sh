#!/usr/bin/env bash
# Offline only. Node contract/filesystem checks, then actual Erlang parser.
set -Eeuo pipefail
probe_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$probe_root"
probe_inputs=(scripts/probe-acdc-prerecorded-runtime.cjs scripts/probe-acdc-prerecorded-runtime.erl.template
  scripts/publish-acdc-prerecorded-capabilities.cjs scripts/test-probe-acdc-prerecorded-runtime.cjs
  scripts/test-probe-acdc-prerecorded-runtime.sh scripts/validate-acdc-language-capabilities.cjs
  scripts/refresh-acdc-cardinal-mappings.cjs scripts/refresh-acdc-gemini-mappings.cjs
  scripts/import-acdc-gemini-voices.cjs scripts/validate-acdc-gemini-receipt.cjs
  applications/acdc/src/acdc_gemini_map.hrl
  scripts/erlang-tests/acdc_runtime_probe_reader_tests.erl)
probe_before=$(sha256sum -- "${probe_inputs[@]}" | sha256sum | cut -d ' ' -f 1)
timeout 60 node --test scripts/test-probe-acdc-prerecorded-runtime.cjs
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
probe_reader_directory=$(mktemp -d /root/kazoo-runtime-reader.XXXXXX)
trap 'printf "Retained private reader fixture: %s\n" "$probe_reader_directory"' EXIT
export KAZOO_RUNTIME_READER_TEST_DIRECTORY="$probe_reader_directory"
timeout 30 erlc -Werror -o "$probe_reader_directory" scripts/erlang-tests/acdc_runtime_probe_reader_tests.erl
timeout 30 erl -pa "$probe_reader_directory" -noshell -eval \
  'acdc_runtime_probe_reader_tests:run(os:getenv("KAZOO_RUNTIME_READER_TEST_DIRECTORY")).'
probe_after=$(sha256sum -- "${probe_inputs[@]}" | sha256sum | cut -d ' ' -f 1)
[[ "$probe_before" == "$probe_after" ]] || { printf '%s\n' 'Probe sources changed during validation' >&2; exit 1; }
printf 'PASS offline probe/publication contracts, sourceSHA256 %s\n' "$probe_after"
