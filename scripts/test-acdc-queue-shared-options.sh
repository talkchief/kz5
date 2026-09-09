#!/usr/bin/env bash
# Exercise the production listener declaration without connecting to a broker.
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo-acdc-shared-options.XXXXXX)
cleanup() {
    rm -f -- "$test_dir/acdc_queue_shared.beam" "$test_dir/acdc_queue_shared_options_tests.beam" "$test_dir/kz_amqp_util.beam"
    rmdir -- "$test_dir"
}
trap cleanup EXIT
cd "$project_root"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 2:2 +A 1'
export ERL_CRASH_DUMP=/dev/null
erlc -Werror +debug_info -I applications/acdc/src -I applications/acdc/include -I core/kazoo_amqp/src \
    -pa deps/lager/ebin +'{parse_transform,lager_transform}' -o "$test_dir" \
    applications/acdc/src/acdc_queue_shared.erl core/kazoo_amqp/src/kz_amqp_util.erl
erlc -Werror -o "$test_dir" scripts/erlang-tests/acdc_queue_shared_options_tests.erl
erl -pa "$test_dir" -noshell \
    -eval 'case eunit:test(acdc_queue_shared_options_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
