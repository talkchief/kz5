#!/usr/bin/env bash
# Compile and run only the offnet-originate event-forwarding regression in /tmp.
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo-stepswitch-callback-events.XXXXXX)
cleanup() {
    rm -f -- "$test_dir/stepswitch_originate.beam" "$test_dir/stepswitch_originate_callback_tests.beam"
    rmdir -- "$test_dir"
}
trap cleanup EXIT
cd "$project_root"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 2:2 +A 1'
export ERL_CRASH_DUMP=/dev/null
erlc -DTEST -Werror +warn_missing_spec -I applications/stepswitch/src \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' -o "$test_dir" \
    applications/stepswitch/src/stepswitch_originate.erl
erlc -Werror -o "$test_dir" scripts/erlang-tests/stepswitch_originate_callback_tests.erl
erl -pa "$test_dir" -noshell \
    -eval 'case eunit:test(stepswitch_originate_callback_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
