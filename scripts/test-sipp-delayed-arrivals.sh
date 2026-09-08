#!/usr/bin/bash
# Actual wait loop with virtual time and in-memory readiness; no SIP or sleeps.
set -euo pipefail
source_path=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/test-kazoo-calls.sh
eval "$(sed -n '/^wait_concurrent_call_legs() {/,/^}/p' "$source_path")"
sleep() { SECONDS=$((SECONDS + $1)); }
concurrent_call_legs_present() { ((SECONDS >= ready_at)); }
SECONDS=0 ready_at=15
wait_concurrent_call_legs ordinary 30 30
SECONDS=0 ready_at=137
if wait_concurrent_call_legs old_deadline 30 35; then exit 1; fi
SECONDS=0 ready_at=137
wait_concurrent_call_legs delayed 30 35 180
SECONDS=0 ready_at=181
if wait_concurrent_call_legs missing 30 35 180; then exit 1; fi
# Also verify real orchestration computes the allowance only for excess calls.
eval "$(sed -n '/^run_stress_stage() {/,/^}/p' "$source_path")"
for operation in log agent_status capture_log_baseline start_monitor start_rtp_capture \
    register_agents start_agent_uas register_caller start_callers wait_answered_calls \
    wait_checked stop_waiting_agents_checked wait_agents_checked stop_rtp_capture \
    stop_monitor assert_stats assert_agent_stats assert_rtp_capture wait_agents_ready \
    record_stage; do eval "$operation() { :; }"; done
core_count() { printf 0; }
wait_concurrent_call_legs() { actual_budget=$4; }
hold_concurrent_call_legs() { actual_hold=$4; }
declare -A STATE=([ACCEPTANCE_AGENT_COUNT]=30)
RUN_DIR=/fixture CALLER_PORT=15064 CALLER_MEDIA_MIN=42000 CALLER_MEDIA_MAX=42998
CAPACITY_HOLD_MS=360000 STAGE_HOLD_MS=60000 MAX_ANSWERED_CALLS=30
QUEUED_EXCESS_DELAY_MS=120000 QUEUED_EXCESS_HOLD_MS=360000 CALLER_PID=1
CAPACITY_SOAK_SECONDS=180
run_stress_stage 30 5
[[ $actual_budget == 180 && $actual_hold == 180 ]]
run_stress_stage 30 0
[[ $actual_budget == 60 && $actual_hold == 180 ]]
printf 'PASS delayed-arrival setup budget, missing-arrival failure, ordinary budget and unchanged 180s hold\n'
