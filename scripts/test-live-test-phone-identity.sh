#!/usr/bin/env bash
# All process, SIP/API, stat and signal operations below are pure function mocks.
set -Eeuo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=run-live-test-agents.sh
source "$script_dir/run-live-test-agents.sh"
declare -a REPAIRS=() DELIVERED=() WAITED=() FAKE_STATES=()
log() { :; }
systemd-notify() { :; }
kill() { printf '%s\n' 'Forbidden numeric-PID signal or probe' >&2; exit 99; }
owned_helper() { printf '%s\n' 'Forbidden roster/status operation' >&2; exit 99; }
contact_present() { [[ ${CONTACTS_PRESENT:-true} == true ]]; }
failed_registrations() { return 1; }
start_phone() { REPAIRS+=("$1"); }
wait() { WAITED+=("$1"); }
sleep() { SECONDS=$((SECONDS+6)); }

# Actual birth parser: stat field22, not whitespace field22 of the full line.
PHONE_PIDS=(500)
FAKE_STAT="500 (sipp parent ) test) S $SUPERVISOR_PID"
for ((number=0; number<17; number++)); do FAKE_STAT+=' 0'; done
FAKE_STAT+=' 12345'
read_phone_stat() { PHONE_PROC_STAT=$FAKE_STAT; [[ ${STAT_READABLE:-true} == true ]]; }
record_phone_identity 1
[[ ${PHONE_START_TICKS[0]} == 12345 ]]
for FAKE_STAT in '500 (sipp) S 1' '501 (sipp) S 200' 'not a proc stat'; do
    if record_phone_identity 1; then exit 1; fi
    [[ -z ${PHONE_START_TICKS[0]} ]]
done
STAT_READABLE=false
if record_phone_identity 1; then exit 1; fi
[[ -z ${PHONE_START_TICKS[0]} ]]

# The real Bash transport only supplies a fixed operation and three numeric
# identities; malformed output and unavailable Python are not dead evidence.
PHONE_PIDS=(500)
PHONE_START_TICKS=(12345)
python3() {
    [[ $# == 6 && $1 == -I && $2 == "$PHONE_PROCESS_HELPER" && $3 == check &&
       $4 == 500 && $5 == 12345 && $6 == "$SUPERVISOR_PID" ]] || return 99
    printf '%s\n' "${FAKE_RESULT:-alive}"
    return "${FAKE_EXIT:-0}"
}
[[ $(phone_process_state 1) == alive ]]
FAKE_RESULT=foreign
[[ $(phone_process_state 1) == foreign ]]
FAKE_RESULT=SECRET-DO-NOT-LOG
[[ $(phone_process_state 1) == unknown ]]
FAKE_EXIT=1
[[ $(phone_process_state 1) == unknown ]]
PHONE_START_TICKS=()
[[ $(phone_process_state 1) == unknown ]]
unset -f python3

# This fake models the helper's independently tested pidfd policy. State
# probes run in substitutions, but attempted signal delivery runs in-parent.
phone_process_action() {
    local index=$1 operation=$2 state=${FAKE_STATES[$1]:-unknown}
    if [[ $operation == check ]]; then printf '%s\n' "$state"; return; fi
    [[ $operation == INT || $operation == KILL ]] || exit 99
    if [[ $state == alive ]]; then
        DELIVERED+=("$index:$operation")
        FAKE_STATES[index]=${AFTER_SIGNAL:-dead}
        printf '%s\n' sent
    else
        printf '%s\n' "$state"
    fi
}
for index in {1..30}; do PHONE_PIDS[index-1]=$((10000+index)); PHONE_START_TICKS[index-1]=$((20000+index)); FAKE_STATES[index]=alive; done
FAKE_STATES[1]=foreign
FAKE_STATES[2]=unknown
FAKE_STATES[3]=dead
ZERO_CALLS=false
no_active_calls() { [[ $ZERO_CALLS == true ]]; }
monitor_phones
[[ $REGISTERED_PHONES == 27 && ${#REPAIRS[@]} == 0 && ${#DELIVERED[@]} == 0 ]]
ZERO_CALLS=true
OWNERSHIP_VERIFIED=false
monitor_phones
[[ ${#REPAIRS[@]} == 0 ]]
OWNERSHIP_VERIFIED=true
monitor_phones
[[ ${REPAIRS[*]} == 3 && ${#DELIVERED[@]} == 0 && ${WAITED[*]} == 10003 ]]
# A newly reused PID during the zero-call observation cannot trigger repair.
REPAIRS=()
no_active_calls() { FAKE_STATES[3]=foreign; return 0; }
monitor_phones
[[ ${#REPAIRS[@]} == 0 ]]
# A same-child registration lapse still cannot trigger a phone restart.
for index in {1..30}; do FAKE_STATES[index]=alive; done
CONTACTS_PRESENT=false
monitor_phones
[[ $REGISTERED_PHONES == 0 && ${#REPAIRS[@]} == 0 && ${#DELIVERED[@]} == 0 ]]
CONTACTS_PRESENT=true
monitor_phones
[[ $REGISTERED_PHONES == 30 ]]
check_children
FAKE_STATES[1]=foreign
if (check_children); then exit 1; fi
FAKE_STATES[1]=unknown
if (check_children); then exit 1; fi
FAKE_STATES[1]=dead
if (check_children); then exit 1; fi

# Normal cleanup delivers INT only to the exact child. Reused, vanished,
# unreadable and never-captured identities never receive INT or KILL.
PHONE_PIDS=(101 102 103 104)
PHONE_START_TICKS=(201 202 203 204)
FAKE_STATES=([1]=alive [2]=foreign [3]=dead [4]=unknown)
WAITED=()
stop_phones
[[ ${DELIVERED[*]} == '1:INT' && ${WAITED[*]} == '101 103' &&
   ${#PHONE_PIDS[@]} == 0 && ${#PHONE_START_TICKS[@]} == 0 ]]
# If the PID is reused after INT, the final KILL must not hit its new owner.
PHONE_PIDS=(101)
PHONE_START_TICKS=(201)
FAKE_STATES=([1]=alive)
AFTER_SIGNAL=foreign
DELIVERED=()
WAITED=()
stop_phones
[[ ${DELIVERED[*]} == '1:INT' && ${#WAITED[@]} == 0 ]]
# A surviving exact child is eligible for the bounded INT->KILL sequence.
PHONE_PIDS=(101)
PHONE_START_TICKS=(201)
FAKE_STATES=([1]=alive)
AFTER_SIGNAL=alive
DELIVERED=()
stop_phones
[[ ${DELIVERED[*]} == '1:INT 1:KILL' && ${#WAITED[@]} == 0 ]]
printf '%s\n' 'PASS 12 grouped mocked PID identity cases: birth parser, exact transport, unknown failure, reused/foreign/dead health, zero-call recheck, same-child health, startup checks, INT/KILL ownership and no status effects'
