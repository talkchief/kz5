#!/usr/bin/env bash
# Real dev44-only queued call: lose eCallMgr before BYE, retain busy while
# evidence is unavailable, recover after reconnect, accept the next call.
# Shared-library globals are consumed by test-kazoo-calls.sh helpers.
# shellcheck disable=SC2034
set -Eeuo pipefail
recovery_script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
KAZOO_CALLS_LIBRARY=true source "$recovery_script_dir/test-kazoo-calls.sh"
RECOVERY_NODE_STOPPED=false
RECOVERY_WATCHDOG=''
RECOVERY_SERVICE=kazoo-ecallmgr.service
RECOVERY_COUNT=1

recovery_parse() {
    [[ $# == 1 || $# == 3 || $# == 5 ]] || return 2
    [[ $1 == --prepare-only || $1 == --live ]] || return 2
    RECOVERY_SERVICE=kazoo-ecallmgr.service
    RECOVERY_COUNT=1
    if [[ $# -ge 3 ]]; then
        [[ $2 == --fault && $3 == broker ]] || return 2
        RECOVERY_SERVICE=rabbitmq-server.service
    fi
    if [[ $# == 5 ]]; then
        [[ $4 == --concurrent && $5 == 30 ]] || return 2
        RECOVERY_COUNT=30
    fi
}

recovery_status() {
    local index=${1:-1} key
    key=ACCEPTANCE_AGENT_${index}_USER_ID
    timeout 8 sup -n kazoo_apps -t 5 acdc_agent_maintenance agent_status \
        "${STATE[ACCEPTANCE_ACCOUNT_ID]}" "${STATE[$key]}" 2>/dev/null
}

recovery_has_state() {
    grep -Eq "(^|[[:space:]])state:[[:space:]]*$1([[:space:]]|$)" <<<"$2"
}

recovery_fsm_identity() {
    sed -nE 's/^[[:space:]]*FSM: <[0-9]+\.([0-9]+\.[0-9]+)>[[:space:]]*$/\1/p' <<<"$1"
}

recovery_channels() {
    timeout 5 /usr/local/freeswitch/bin/fs_cli -x 'show channels as json' |
        jq -ce 'if .row_count==0 then .rows=[] else . end |
            select((.rows|type)=="array" and .row_count==(.rows|length)) |
            {row_count,rows:[.rows[]|{uuid}]}'
}

recovery_owned_pair() {
    local snapshot id
    snapshot=$(recovery_channels) || return 1
    jq -e --argjson count "$((RECOVERY_COUNT * 2))" \
        '.row_count==$count and ([.rows[].uuid]|unique|length)==$count' <<<"$snapshot" >/dev/null || return 1
    while read -r id; do
        [[ $id =~ ^[A-Za-z0-9@._:-]{1,128}$ ]] || return 1
        timeout 5 /usr/local/freeswitch/bin/fs_cli -x "uuid_dump $id json" |
            jq -e --arg id "$id" --arg account "${STATE[ACCEPTANCE_ACCOUNT_ID]}" \
                '.["Unique-ID"]==$id and .["variable_ecallmgr_Account-ID"]==$account and
                 (.["Caller-Channel-Answered-Time"]|tonumber)>0' >/dev/null || return 1
    done < <(jq -r '.rows[].uuid' <<<"$snapshot")
    printf '%s\n' "$snapshot" > "$RUN_DIR/node-loss-owned-channels.json"
}

recovery_cleanup() {
    local rc=$?
    trap - EXIT INT TERM
    if [[ $RECOVERY_NODE_STOPPED == true ]]; then
        if ! timeout 90 systemctl start "$RECOVERY_SERVICE"; then
            warn 'Selected fault service restoration failed; operator recovery required'; rc=1
        fi
    fi
    if [[ -n $RECOVERY_WATCHDOG ]] && systemctl is-active --quiet "$RECOVERY_SERVICE"; then
        systemctl stop "$RECOVERY_WATCHDOG.timer" || rc=1
    fi
    cleanup || rc=1
    exit "$rc"
}

recovery_main() {
    recovery_parse "$@" || die 'Use --prepare-only or --live [--fault broker [--concurrent 30]] (dev44 isolated fixture only)'
    [[ $EUID == 0 ]] || die 'Run as root'
    umask 077
    export KAZOO_CALLBACK_TEST_ACCOUNT_ID=8310dc3170a18de37f205d0da172df65
    node "$SCRIPT_DIR/test-fixtures/callback-fixture-account.cjs" --ensure-lock
    exec 9<>/etc/kazoo/monitor-acceptance.lock
    flock -n 9 || die 'Another fixture acceptance run is active'
    ip -o -4 addr show | grep -Eq '[[:space:]]10\.1\.0\.44/' || die 'Only main development host10.1.0.44 is allowed'
    load_state; validate_state
    [[ ${STATE[ACCEPTANCE_ACCOUNT_ID]} == "$KAZOO_CALLBACK_TEST_ACCOUNT_ID" ]] || die 'Wrong isolated account'
    ((STATE[ACCEPTANCE_AGENT_COUNT] >= RECOVERY_COUNT)) || die 'Insufficient isolated fixture agents'
    INSTALL_DEPS=false
    ensure_sipp; validate_scenarios; resolve_local_ip
    systemctl is-active --quiet kazoo-apps.service
    systemctl is-active --quiet kazoo-ecallmgr.service
    systemctl is-active --quiet "$RECOVERY_SERVICE"
    recovery_channels | jq -e '.row_count==0' >/dev/null || die 'Requires no active channels'
    [[ $1 == --live ]] || { log 'PASS node-loss fixture preflight; no calls or service changes'; return; }
    LIVE=true
    RUN_ROOT=/var/log/kazoo-acceptance/node-loss
    create_run_dir
    printf '%s\n' "$RECOVERY_SERVICE" > "$RUN_DIR/fault-service.txt"
    printf '%s\n' "$RECOVERY_COUNT" > "$RUN_DIR/fault-concurrency.txt"
    trap recovery_cleanup EXIT INT TERM
    local before_apps status deadline since cores index all_ready hold_ms=60000
    local -A before_fsms=()
    ((RECOVERY_COUNT == 1)) || hold_ms=120000
    before_apps=$(systemctl show -p MainPID --value kazoo-apps.service)
    STATUS_AGENT_MAX=${STATE[ACCEPTANCE_AGENT_COUNT]}
    agent_status logout 1 "$STATUS_AGENT_MAX"
    register_agents node-loss "$RECOVERY_COUNT"
    register_caller node-loss "$CALLER_PORT"
    start_agent_uas node-loss "$RECOVERY_COUNT"
    agent_status login 1 "$RECOVERY_COUNT"
    start_callers node-loss "$RECOVERY_COUNT" "$CALLER_PORT" "$CALLER_MEDIA_MIN" "$CALLER_MEDIA_MAX" "$hold_ms"
    wait_concurrent_call_legs node-loss "$RECOVERY_COUNT" "$RECOVERY_COUNT" || die 'Initial concurrent queued calls not connected'
    for ((index=1; index<=RECOVERY_COUNT; index++)); do
        status=$(recovery_status "$index")
        recovery_has_state answered "$status" || die 'Every agent must be answered before node loss'
        before_fsms[$index]=$(recovery_fsm_identity "$status")
        [[ ${before_fsms[$index]} =~ ^[0-9]+\.[0-9]+$ ]] || die 'Agent FSM identity missing'
        printf '%s\t%s\n' "$index" "${before_fsms[$index]}" >> "$RUN_DIR/fsms-before.tsv"
    done
    printf '%s\n' "${before_fsms[1]}" > "$RUN_DIR/fsm-before.txt"
    recovery_owned_pair || die 'Only answered isolated fixture pairs may exist'
    # Independent restoration survives SIGKILL or loss of the SSH/test process.
    RECOVERY_WATCHDOG=kz5-acdc-node-loss-restore-$$
    systemd-run --unit="$RECOVERY_WATCHDOG" --on-active=5m --timer-property=AccuracySec=1s \
        /usr/bin/systemctl start "$RECOVERY_SERVICE"
    systemctl is-active --quiet "$RECOVERY_WATCHDOG.timer"
    # Mark BEFORE the stop so every error path attempts restoration.
    RECOVERY_NODE_STOPPED=true
    timeout 90 systemctl stop "$RECOVERY_SERVICE"
    [[ $(systemctl is-active "$RECOVERY_SERVICE" || true) == inactive ]] || die 'Selected fault service did not stop'
    log "$RECOVERY_SERVICE stopped after real bridge; waiting for SIP endpoints to hang up"
    wait_checked 'node-loss caller' "$CALLER_PID"
    wait_agents_checked node-loss
    assert_stats 'node-loss caller' "$RUN_DIR/node-loss-caller-stats.csv" "$RECOVERY_COUNT"
    assert_agent_stats node-loss "$RECOVERY_COUNT" "$RECOVERY_COUNT"
    recovery_channels | jq -e '.row_count==0' >/dev/null || die 'Native calls have not ended'
    # Cover one complete production30s reconciliation interval while no node
    # can supply authoritative status. Unknown evidence must not free the agent.
    deadline=$((SECONDS + 35))
    while ((SECONDS < deadline)); do
        for ((index=1; index<=RECOVERY_COUNT; index++)); do
            status=$(recovery_status "$index")
            recovery_has_state answered "$status" || die 'Agent became available without channel evidence'
            [[ $(recovery_fsm_identity "$status") == "${before_fsms[$index]}" ]] || die 'Agent FSM was replaced during node loss'
        done
        sleep 1
    done
    log 'PASS ended call remained conservatively busy while node evidence was unavailable'
    timeout 90 systemctl start "$RECOVERY_SERVICE"
    systemctl is-active --quiet "$RECOVERY_SERVICE"
    RECOVERY_NODE_STOPPED=false
    deadline=$((SECONDS + 90))
    while ((SECONDS < deadline)); do
        all_ready=true
        for ((index=1; index<=RECOVERY_COUNT; index++)); do
            status=$(recovery_status "$index")
            [[ $(recovery_fsm_identity "$status") == "${before_fsms[$index]}" ]] || die 'A replacement FSM is not recovery proof'
            recovery_has_state ready "$status" || all_ready=false
        done
        [[ $all_ready != true ]] || break
        sleep 1
    done
    [[ $all_ready == true ]] || die 'Not all ended calls recovered after service reconnect'
    printf '%s\n' "${before_fsms[1]}" > "$RUN_DIR/fsm-after.txt"
    [[ $(systemctl show -p MainPID --value kazoo-apps.service) == "$before_apps" ]] || die 'Apps restarted during recovery'
    log 'PASS same applications node recovered agent without logout/login or FSM reset'
    # A ready agent does not mean a newly booted media node has been admitted
    # by Kamailio yet. Require the actual INVITE groups to become routable;
    # merely finding a DEST entry or an active systemd process is insufficient.
    deadline=$((SECONDS + 90))
    local dispatcher_ready=false
    while ((SECONDS < deadline)); do
        if python3 -B -I "$SCRIPT_DIR/kamailio-dispatcher-ready.py" > "$RUN_DIR/dispatcher-after.json"; then
            dispatcher_ready=true; break
        fi
        sleep 2
    done
    [[ $dispatcher_ready == true ]] || die 'Media was not re-admitted by Kamailio after node restart'
    # No login or queue restart before this second call: readiness must work.
    since=$(date +%s); cores=$(core_count)
    capture_log_baseline after-node-loss; start_monitor after-node-loss; start_rtp_capture after-node-loss
    start_agent_uas after-node-loss "$RECOVERY_COUNT"
    start_callers after-node-loss "$RECOVERY_COUNT" "$CALLER_PORT" "$CALLER_MEDIA_MIN" "$CALLER_MEDIA_MAX" 30000
    wait_concurrent_call_legs after-node-loss "$RECOVERY_COUNT" "$RECOVERY_COUNT" || die 'Recovered agents did not accept concurrent calls'
    wait_checked 'after-node-loss caller' "$CALLER_PID"
    wait_agents_checked after-node-loss
    stop_rtp_capture; stop_monitor
    assert_stats 'after-node-loss caller' "$RUN_DIR/after-node-loss-caller-stats.csv" "$RECOVERY_COUNT"
    assert_agent_stats after-node-loss "$RECOVERY_COUNT" "$RECOVERY_COUNT"
    assert_rtp_capture after-node-loss "$RECOVERY_COUNT" "$RECOVERY_COUNT"
    wait_agents_ready "$RECOVERY_COUNT" || die 'Second calls did not return all agents to ready'
    record_stage after-node-loss "$RECOVERY_COUNT" "$RECOVERY_COUNT" "$RUN_DIR/after-node-loss-caller-stats.csv" "$RECOVERY_COUNT" "$cores" "$since"
    log "PASS native node-loss/missed-hangup recovery and next-call SIP/RTP; evidence: $RUN_DIR"
}
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then recovery_main "$@"; fi
