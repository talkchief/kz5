#!/usr/bin/env bash
# Compile upstream ACDC tests into an isolated directory, never the live beams.
set -Eeuo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo-acdc-test.XXXXXX)
cleanup() {
    rm -f -- "$test_dir/acdc_queue_strategy.beam" "$test_dir/acdc_agent_fsm.beam" "$test_dir/acdc_queue_fsm.beam" \
        "$test_dir/acdc_queue_manager.beam" "$test_dir/acdc_queue_member.beam" \
        "$test_dir/acdc_callback_store.beam" "$test_dir/kapi_acdc_callback.beam" \
        "$test_dir/kapi_acdc_queue.beam" "$test_dir/acdc_agent_fsm_tests.beam" \
        "$test_dir/acdc_queue_fsm_tests.beam" "$test_dir/acdc_queue_manager_tests.beam" \
        "$test_dir/acdc_queue_member_tests.beam"
    rmdir -- "$test_dir"
}
trap cleanup EXIT
cd "$project_root"
export ERL_LIBS="$project_root/deps:$project_root/core:$project_root/applications"
export ERL_FLAGS='+S 1:1 +SDcpu 1 +SDio 1 +A 1'
export ERL_CRASH_DUMP=/dev/null
erlc -DTEST -I applications/acdc/src -I applications/acdc/include -pa deps/lager/ebin \
    +'{parse_transform,lager_transform}' -o "$test_dir" \
    applications/acdc/src/acdc_callback_store.erl applications/acdc/src/acdc_queue_member.erl \
    applications/acdc/src/kapi_acdc_callback.erl applications/acdc/src/kapi_acdc_queue.erl \
    applications/acdc/src/acdc_queue_strategy.erl applications/acdc/src/acdc_agent_fsm.erl applications/acdc/src/acdc_queue_fsm.erl \
    applications/acdc/src/acdc_queue_manager.erl applications/acdc/test/acdc_agent_fsm_tests.erl \
    applications/acdc/test/acdc_queue_fsm_tests.erl applications/acdc/test/acdc_queue_manager_tests.erl \
    applications/acdc/test/acdc_queue_member_tests.erl
KAZOO_CONFIG="$project_root/rel/config-test.ini" erl -pa "$test_dir" -noshell \
    -eval '
      %% Mock compilation is included in EUnit wall time. At the validation
      %% guards 50% CPU quota, the five-second default intermittently expires
      %% in meck setup before an assertion runs. Keep every test/assertion and
      %% use the supported slow-host scale; production timers and the outer
      %% finite resource/runtime guard are unchanged.
      case eunit:test([acdc_agent_fsm_tests,acdc_queue_fsm_tests,acdc_queue_manager_tests,acdc_queue_member_tests],
                      [verbose,{scale_timeouts,4}]) of
        ok -> halt(0); _ -> halt(1)
      end.'
