#!/usr/bin/env bash
# Compile/test only in a private VM; never replace running BEAM files.
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo-channel-monitoring.XXXXXX)
cleanup() {
    find "$test_dir" -maxdepth 1 -type f -name '*.beam' -delete
    rmdir -- "$test_dir"
}
trap cleanup EXIT
cd "$project_root"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
common=(-Werror +warn_missing_spec -pa deps/lager/ebin '+{parse_transform,lager_transform}' -o "$test_dir")
erlc "${common[@]}" -I core/kazoo_amqp/src core/kazoo_amqp/src/api/kapi_resource.erl core/kazoo_amqp/src/api/kapi_dialplan.erl
erlc "${common[@]}" -DTEST -I applications/crossbar/src -I applications/crossbar/include applications/crossbar/src/cb_channel_monitor.erl
erlc "${common[@]}" -I applications/crossbar/src -I applications/crossbar/include applications/crossbar/src/modules/cb_channels.erl
erlc "${common[@]}" -DTEST -I applications/ecallmgr/src applications/ecallmgr/src/ecallmgr_call_monitor.erl
erlc "${common[@]}" -I applications/ecallmgr/src applications/ecallmgr/src/freeswitch.erl applications/ecallmgr/src/mod_kazoo.erl
erlc "${common[@]}" -DTEST -I applications/ecallmgr/src applications/ecallmgr/src/ecallmgr_originate.erl
erlc "${common[@]}" -I applications/ecallmgr/src applications/ecallmgr/src/ecallmgr_fs_resource.erl
erlc "${common[@]}" -I applications/acdc/src -I applications/acdc/include -I applications/crossbar/include applications/acdc/src/cb_queues.erl
erlc -Werror -o "$test_dir" scripts/erlang-tests/channel_monitoring_tests.erl
erl -pa "$test_dir" -noshell -eval 'case eunit:test(channel_monitoring_tests, [verbose]) of ok -> halt(0); _ -> halt(1) end.'
