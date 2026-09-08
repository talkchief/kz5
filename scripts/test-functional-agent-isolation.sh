#!/usr/bin/bash
# Execute the real functional orchestration with all external actions replaced.
set -euo pipefail
source_path=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/test-kazoo-calls.sh
eval "$(sed -n '/^run_functional() {/,/^}/p' "$source_path")"
for operation in log negative_registration_test capture_log_baseline start_monitor \
    start_rtp_capture register_caller start_callers wait_answered_calls register_agents \
    start_agent_uas wait_agent_observed_answer wait_checked wait_agents_checked \
    stop_rtp_capture stop_monitor assert_stats assert_agent_stats assert_rtp_capture \
    wait_agent_ready record_stage; do
    eval "$operation() { :; }"
done
core_count() { printf '0\n'; }
agent_status() { events+=("$*"); }
die() { printf '%s\n' "$*" >&2; exit 1; }
declare -A STATE=()
RUN_DIR=/fixture-readonly CALLER_PORT=15064 CALLER_MEDIA_MIN=42000 CALLER_MEDIA_MAX=42998
FUNCTIONAL_HOLD_MS=30000 CALLER_PID=1234
for count in 1 30; do
    STATE[ACCEPTANCE_AGENT_COUNT]=$count
    events=() STATUS_AGENT_MAX=0
    run_functional
    [[ $STATUS_AGENT_MAX == "$count" ]] || die 'Cleanup does not cover every fixture agent'
    [[ ${#events[@]} == 3 && ${events[0]} == "logout 1 $count" &&
       ${events[1]} == 'login 1 1' && ${events[2]} == 'verify 1 1' ]] ||
        die 'Functional test did not isolate one available agent from the full fixture'
done
printf 'PASS actual functional orchestration isolates one agent and scopes cleanup for 1/30-agent fixtures; no network or calls\n'
