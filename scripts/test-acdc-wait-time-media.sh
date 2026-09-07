#!/usr/bin/env bash
# Private production/test compilation and memory-only fixtures; root serializes.
set -Eeuo pipefail
wait_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
wait_build=$(mktemp -d /tmp/kazoo-wait-time-media.XXXXXX)
mkdir "$wait_build/production" "$wait_build/test"
trap 'printf "Private wait-time media artifacts: %s\n" "$wait_build"' EXIT
cd "$wait_root"
export ERL_LIBS="$wait_root/deps:$wait_root/core:$wait_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
wait_inputs=(applications/acdc/src/acdc_wait_time_media.erl applications/acdc/src/acdc_announcements.erl
    applications/acdc/src/acdc_gemini_prompts.erl applications/acdc/src/acdc_gemini_map.hrl
    scripts/erlang-tests/acdc_wait_time_media_tests.erl scripts/test-acdc-wait-time-media.sh)
wait_before=$(sha256sum -- "${wait_inputs[@]}" | sha256sum | cut -d ' ' -f 1)
erlc -Werror -I applications/acdc/src -I applications/acdc/include -pa deps/lager/ebin \
    +'{parse_transform,lager_transform}' -o "$wait_build/production" "${wait_inputs[@]:0:3}"
erlc -DTEST +debug_info -Werror -I applications/acdc/src -I applications/acdc/include -pa deps/lager/ebin \
    +'{parse_transform,lager_transform}' -o "$wait_build/test" "${wait_inputs[@]:0:3}"
erlc -Werror -I applications/acdc/src -o "$wait_build/test" "${wait_inputs[4]}"
erl -noshell -pa "$wait_build/test" \
    -eval 'case eunit:test(acdc_wait_time_media_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
wait_after=$(sha256sum -- "${wait_inputs[@]}" | sha256sum | cut -d ' ' -f 1)
[[ $wait_before == "$wait_after" ]] || { printf '%s\n' 'Wait-time media source changed during validation' >&2; exit 1; }
printf 'PASS wait-time media fixture; input SHA-256 %s\n' "$wait_after"
