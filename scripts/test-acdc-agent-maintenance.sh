#!/usr/bin/env bash
# Compile production modules privately; exercise observations and fenced restore primitives.
set -Eeuo pipefail
umask 077
maintenance_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
[[ $# == 0 ]] || exit 2
[[ $(readlink /proc/self/ns/net) != "$(readlink /proc/1/ns/net)" ]] || {
    printf 'Private network namespace required\n' >&2; exit 2;
}
maintenance_output=$(mktemp -d /tmp/kazoo-acdc-maintenance.XXXXXX)
cd "$maintenance_root"
export ERL_LIBS="$maintenance_root/deps:$maintenance_root/core:$maintenance_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
maintenance_inputs=(applications/acdc/src/acdc_agent_fsm.erl
    applications/acdc/src/acdc_agent_listener.erl
    applications/acdc/src/acdc_queue_fsm.erl
    applications/acdc/src/acdc_queue_listener.erl
    applications/acdc/src/acdc_queue_manager.erl
    applications/acdc/src/acdc_queue_shared.erl
    applications/acdc/src/acdc_queue_manager.hrl
    scripts/erlang-tests/acdc_queue_maintenance_tests.erl
    scripts/erlang-tests/acdc_agent_maintenance_tests.erl
    scripts/erlang-tests/acdc_listener_maintenance_tests.erl
    scripts/erlang-tests/acdc_agent_restore_tests.erl
    scripts/erlang-tests/acdc_listener_restore_tests.erl
    scripts/test-acdc-agent-maintenance.sh)
sha256sum "${maintenance_inputs[@]}" > "$maintenance_output/source.sha256"
erlc -Werror +debug_info -I applications/acdc/src -I applications/acdc/include \
    -pa deps/lager/ebin '+{parse_transform,lager_transform}' -o "$maintenance_output" \
    applications/acdc/src/acdc_agent_fsm.erl \
    applications/acdc/src/acdc_agent_listener.erl \
    applications/acdc/src/acdc_queue_fsm.erl \
    applications/acdc/src/acdc_queue_listener.erl \
    applications/acdc/src/acdc_queue_manager.erl \
    applications/acdc/src/acdc_queue_shared.erl \
    scripts/erlang-tests/acdc_queue_maintenance_tests.erl \
    scripts/erlang-tests/acdc_agent_maintenance_tests.erl \
    scripts/erlang-tests/acdc_listener_maintenance_tests.erl \
    scripts/erlang-tests/acdc_agent_restore_tests.erl \
    scripts/erlang-tests/acdc_listener_restore_tests.erl
erl -pa "$maintenance_output" -noshell -eval '
    {module,acdc_agent_fsm} = code:ensure_loaded(acdc_agent_fsm),
    {module,acdc_agent_listener} = code:ensure_loaded(acdc_agent_listener),
    false = erlang:function_exported(acdc_agent_fsm,strategy_test_state,1),
    false = erlang:function_exported(acdc_agent_listener,maybe_connect_to_agent,7),
    {module,acdc_queue_fsm} = code:ensure_loaded(acdc_queue_fsm),
    {module,acdc_queue_listener} = code:ensure_loaded(acdc_queue_listener),
    {module,acdc_queue_manager} = code:ensure_loaded(acdc_queue_manager),
    false = erlang:function_exported(acdc_queue_fsm,callback_test_state,1),
    false = erlang:function_exported(acdc_queue_listener,callback_test_state,1),
    false = erlang:function_exported(acdc_queue_manager,update_properties,2),
    case eunit:test([acdc_agent_maintenance_tests,acdc_listener_maintenance_tests,acdc_agent_restore_tests,acdc_listener_restore_tests,acdc_queue_maintenance_tests],[verbose]) of
        ok -> halt(0); _ -> halt(1)
    end.'
sha256sum -c "$maintenance_output/source.sha256"
printf 'PASS: production maintenance observation/restore primitives; evidence %s\n' "$maintenance_output"
