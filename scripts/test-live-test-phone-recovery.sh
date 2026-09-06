#!/usr/bin/env bash
# Pure shell-function mocks: no SIPp, signals, API, systemd or protected files.
set -Eeuo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
source "$script_dir/run-live-test-agents.sh"
declare -a NOTIFICATIONS=() REPAIRS=() LOGS=()
log() { LOGS+=("$*"); }
systemd-notify() { NOTIFICATIONS+=("$*"); }
timeout() {
    [[ $1 == 90 && $2 == node && $3 == "$HELPER" ]] || return 99
    if [[ $4 == --verify-only ]]; then SAW_FULL_VERIFY=true; return 0; fi
    [[ $4 == --verify-phones-only ]] || return 99
    if [[ ${FAKE_FAILURE:-false} == true ]]; then
        printf '%s\n' 'ERROR: PHONE_OWNERSHIP: owned_device_mismatch' 'SECRET-FIXTURE-DO-NOT-LOG'
        return 1
    fi
}
# The real sourced function is deliberately exercised before its later mock.
# shellcheck disable=SC2218
owned_helper verify_phones
[[ $PHONE_OWNERSHIP_DIAGNOSTIC == verified ]]
FAKE_FAILURE=true
if owned_helper verify_phones; then exit 1; fi
[[ $PHONE_OWNERSHIP_DIAGNOSTIC == owned_device_mismatch ]]
SAW_FULL_VERIFY=false
# shellcheck disable=SC2218
owned_helper verify
[[ $SAW_FULL_VERIFY == true ]]
OWNERSHIP_VERIFIED=false
report_phone_health
[[ $PHONE_HEALTH_STATUS == 'DEGRADED: 0/30 phones registered; recovery blocked: owned_device_mismatch; agent statuses preserved' ]]
[[ ${NOTIFICATIONS[*]} != *SECRET* && ${LOGS[*]} != *SECRET* ]]
unset -f timeout
# Actual FreeSWITCH emits {"row_count":0} without rows. No other missing or
# contradictory payload is evidence of zero calls.
timeout() { [[ $1 == 5 && $2 == "$FS_CLI" && $3 == -x && $4 == 'show channels as json' ]] || return 99; printf '%s\n' "$FAKE_CHANNELS"; }
for FAKE_CHANNELS in '{"row_count":0}' '{"row_count":0,"rows":[]}'; do no_active_calls; done
for FAKE_CHANNELS in '{}' '[]' 'null' '{"row_count":"0"}' '{"row_count":1}' '{"row_count":1,"rows":[]}' \
    '{"row_count":0,"rows":[{}]}' '{"row_count":0,"rows":null}' '{"row_count":0,"rows":{}}' \
    '{"rows":[]}' '{"error":"unavailable"}' '{"row_count":0,"error":"unavailable"}' '{"row_count":0,"status":"error"}' 'not-json'; do
    if no_active_calls; then printf '%s\n' 'Invalid zero-call evidence accepted' >&2; exit 1; fi
done
unset -f timeout
# Called indirectly only if monitor_phones accidentally grows status effects.
# The real clear_fixture_calls is exercised before its later cleanup-effect mock.
channel_effects=0
FAKE_ACCOUNT=$ACCOUNT_ID
FAKE_DEVICE=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
FAKE_PEER=$PHONE_IP
STATE='{"agents":[{"device_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}]}'
timeout() {
    [[ $2 == "$FS_CLI" && $3 == -x ]] || return 99
    case "$4" in
        'show channels as json') [[ $1 == 10 ]] || return 99; printf '%s\n' "$FAKE_CHANNELS" ;;
        'uuid_getvar owned-leg ecallmgr_Account-ID') printf '%s\n' "$FAKE_ACCOUNT" ;;
        'uuid_getvar owned-leg ecallmgr_Authorizing-ID') printf '%s\n' "$FAKE_DEVICE" ;;
        'uuid_getvar owned-leg sip_network_ip') printf '%s\n' "$FAKE_PEER" ;;
        'uuid_kill owned-leg NORMAL_CLEARING') channel_effects=$((channel_effects+1)) ;;
        *) return 99 ;;
    esac
}
for FAKE_CHANNELS in '{"row_count":0}' '{"row_count":0,"rows":[]}'; do
    # shellcheck disable=SC2218
    clear_fixture_calls
    [[ $channel_effects == 0 ]]
done
for FAKE_CHANNELS in '{}' '[]' 'null' '{"row_count":"0"}' '{"row_count":1}' '{"row_count":1,"rows":[]}' \
    '{"row_count":0,"rows":[{"uuid":"owned-leg"}]}' '{"row_count":"1","rows":[{"uuid":"owned-leg"}]}' \
    '{"row_count":2,"rows":[{"uuid":"owned-leg"}]}' '{"row_count":1,"rows":[{"uuid":"owned-leg"}],"error":"failed"}' \
    '{"row_count":0,"rows":null}' '{"row_count":0,"rows":{}}' '{"rows":[]}' \
    '{"error":"unavailable"}' '{"row_count":0,"error":"unavailable"}' 'not-json'; do
    if clear_fixture_calls; then printf '%s\n' 'Invalid cleanup listing accepted' >&2; exit 1; fi
    [[ $channel_effects == 0 ]]
done
FAKE_CHANNELS='{"row_count":1,"rows":[{"uuid":"owned-leg"}]}'
FAKE_ACCOUNT=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
# shellcheck disable=SC2218
clear_fixture_calls
[[ $channel_effects == 0 ]]
FAKE_ACCOUNT=$ACCOUNT_ID
FAKE_DEVICE=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
# shellcheck disable=SC2218
clear_fixture_calls
[[ $channel_effects == 0 ]]
FAKE_DEVICE=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
FAKE_PEER=127.0.0.20
# shellcheck disable=SC2218
clear_fixture_calls
[[ $channel_effects == 0 ]]
FAKE_PEER=$PHONE_IP
# shellcheck disable=SC2218
clear_fixture_calls
[[ $channel_effects == 1 ]]
unset -f timeout
# Called indirectly only if monitor_phones accidentally grows status effects.
# shellcheck disable=SC2317
owned_helper() { printf '%s\n' 'Unexpected login/logout/ownership helper during phone repair' >&2; exit 1; }
for index in {1..30}; do PHONE_PIDS[index-1]=$((10000+index)); done
phone_process_state() {
    if [[ ${ALL_DEAD:-false} == true || $1 == 2 ]]; then printf '%s\n' dead; else printf '%s\n' alive; fi
}
contact_present() { [[ $1 != 2 ]]; }
no_active_calls() { [[ ${ZERO_CALLS:-false} == true ]]; }
start_phone() { REPAIRS+=("$1"); }
wait() { return 127; }
monitor_phones
[[ ${#REPAIRS[@]} == 0 && $REGISTERED_PHONES == 29 ]]
OWNERSHIP_VERIFIED=true
monitor_phones
[[ ${#REPAIRS[@]} == 0 ]]
ZERO_CALLS=true
monitor_phones
[[ ${REPAIRS[*]} == 2 ]]
[[ $REGISTERED_PHONES == 29 && $PHONE_HEALTH_STATUS == 'DEGRADED: 29/30'* ]]
# Thirty dead processes plus failed ownership can never turn a zero-call
# snapshot into permission to touch phones or change agent statuses.
ALL_DEAD=true
OWNERSHIP_VERIFIED=false
REPAIRS=()
monitor_phones
[[ ${#REPAIRS[@]} == 0 && $REGISTERED_PHONES == 0 && $PHONE_HEALTH_STATUS == 'DEGRADED: 0/30'* ]]
ALL_DEAD=false
phone_process_state() { printf '%s\n' alive; }
contact_present() { return 0; }
OWNERSHIP_VERIFIED=true
monitor_phones
[[ $REGISTERED_PHONES == 30 && $PHONE_HEALTH_STATUS == '30/30 owned test phones registered; agent statuses preserved' ]]
notifications=${#NOTIFICATIONS[@]}
monitor_phones
[[ ${#NOTIFICATIONS[@]} == "$notifications" ]]
# Cleanup is not phone repair: its full verifier fails before any logout,
# hangup/deregister operation, or protected runtime-file deletion.
cleanup_check=none
owned_helper() { cleanup_check=$1; [[ $1 == verify ]] || exit 1; return 1; }
clear_fixture_calls() { printf '%s\n' 'Unexpected cleanup call action' >&2; exit 1; }
deregister_phones() { printf '%s\n' 'Unexpected cleanup registration action' >&2; exit 1; }
if cleanup_resources; then exit 1; fi
[[ $cleanup_check == verify ]]
bash -n "$script_dir/run-live-test-agents.sh"
printf '%s\n' 'PASS mocked supervisor verification-mode selection, full cleanup gate/no effects on failure, strict zero cleanup/no effects, unchanged nonzero account/device/IP guards, bounded diagnostics, accurate 0/30 readiness, per-dead-child repair, ownership/zero-call gates and agent-status preservation'
