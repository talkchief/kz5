#!/usr/bin/env bash
# Sequential offline test phases: Node exits before erlc/erl are started.
# Full586-document/1172-map scope and all original assertions are unchanged.
set -Eeuo pipefail
cardinal_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cardinal_test_directory=$(mktemp -d /tmp/kazoo-cardinal-map-validation.XXXXXX)
trap 'printf "Retained private cardinal mapping artifacts: %s\n" "$cardinal_test_directory"' EXIT
cd "$cardinal_root"
export KAZOO_CARDINAL_MAPPING_TEST_DIR="$cardinal_test_directory"
export ERL_LIBS="$cardinal_root/deps:$cardinal_root/core"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
cardinal_inputs=(
    scripts/test-refresh-acdc-cardinal-mappings.sh
    scripts/test-refresh-acdc-cardinal-mappings.cjs
    scripts/refresh-acdc-cardinal-mappings.cjs
    scripts/refresh-acdc-cardinal-mappings.erl.template
    scripts/install-acdc-cardinal-pack.cjs
    scripts/import-acdc-gemini-cardinals.cjs
    scripts/acdc-cardinal-pack.cjs
    scripts/acdc-cardinal-catalog.cjs
    scripts/gemini-cache-test-stubs/kz_datamgr.erl
    scripts/gemini-cache-test-stubs/gen_listener.erl
    scripts/gemini-cache-test-stubs/media_map.erl
    scripts/gemini-cache-test-stubs/kz_media_map.erl
)
cardinal_before=$(sha256sum -- "${cardinal_inputs[@]}" | sha256sum | cut -d ' ' -f 1)
timeout 120 node --test scripts/test-refresh-acdc-cardinal-mappings.cjs
# Synchronous wait above reaps both node:test parent and its child. Nothing
# starts Erlang until that entire phase has successfully exited.
cardinal_generated=("$cardinal_test_directory/docs.json" "$cardinal_test_directory/check.erl"
    "$cardinal_test_directory/activate.erl" "$cardinal_test_directory/cardinal_mapping_runner.erl"
    "$cardinal_test_directory/expected.json")
for cardinal_file in "${cardinal_generated[@]}"; do
    [[ -f $cardinal_file && ! -L $cardinal_file && -s $cardinal_file ]] || {
        printf '%s\n' 'Missing actual-template fixture; refusing partial test completion' >&2
        exit 1
    }
done
cardinal_generated_before=$(sha256sum -- "${cardinal_generated[@]}" | sha256sum | cut -d ' ' -f 1)
timeout 30 erlc -Werror -o "$cardinal_test_directory" \
    scripts/gemini-cache-test-stubs/kz_datamgr.erl \
    scripts/gemini-cache-test-stubs/gen_listener.erl \
    scripts/gemini-cache-test-stubs/media_map.erl \
    scripts/gemini-cache-test-stubs/kz_media_map.erl \
    "$cardinal_test_directory/cardinal_mapping_runner.erl"
timeout 90 erl -pa "$cardinal_test_directory" -noshell \
    -eval 'cardinal_mapping_runner:run(os:getenv("KAZOO_CARDINAL_MAPPING_TEST_DIR")).'
cardinal_after=$(sha256sum -- "${cardinal_inputs[@]}" | sha256sum | cut -d ' ' -f 1)
cardinal_generated_after=$(sha256sum -- "${cardinal_generated[@]}" | sha256sum | cut -d ' ' -f 1)
[[ $cardinal_before == "$cardinal_after" && $cardinal_generated_before == "$cardinal_generated_after" ]] || {
    printf '%s\n' 'Mapping fixture/source drift; refusing successful receipt' >&2
    exit 1
}
printf 'PASS all7 mapping groups including standalone actual Erlang586/1172 scope; sourceSHA256 %s\n' "$cardinal_after"
