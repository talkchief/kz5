#!/usr/bin/env bash
# Private compiled artifacts, mocked directory/endpoint I/O, no dialing.
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo-acdc-callback-internal.XXXXXX)
trap 'printf "Private internal callback test artifacts: %s\n" "$test_dir"' EXIT
cd "$project_root"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
inputs=(applications/acdc/src/acdc_callback_internal.erl applications/acdc/src/acdc_callback_policy.erl
        applications/acdc/src/acdc_callback_caller.erl applications/acdc/src/acdc_callback_store.erl
        scripts/erlang-tests/acdc_callback_internal_tests.erl scripts/erlang-tests/acdc_callback_policy_tests.erl
        scripts/test-acdc-callback-internal.sh)
before=$(sha256sum -- "${inputs[@]}" | sha256sum | cut -d ' ' -f 1)
erlc -DTEST -Werror +warn_missing_spec -I applications/acdc/src -I applications/acdc/include \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' -o "$test_dir" "${inputs[@]:0:4}"
erlc -Werror -o "$test_dir" "${inputs[@]:4:2}"
erl -pa "$test_dir" -noshell \
    -eval 'case eunit:test([acdc_callback_internal_tests, acdc_callback_policy_tests], [verbose]) of ok -> halt(0); _ -> halt(1) end.'
after=$(sha256sum -- "${inputs[@]}" | sha256sum | cut -d ' ' -f 1)
[[ $before == "$after" ]] || { printf '%s\n' 'Callback test sources changed during validation' >&2; exit 1; }
printf 'PASS internal callback and external policy regressions; source SHA-256 %s\n' "$after"
