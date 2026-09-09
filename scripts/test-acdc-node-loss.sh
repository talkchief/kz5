#!/usr/bin/env bash
# Real dev44-only queued call: lose eCallMgr before BYE, retain busy while
# evidence is unavailable, recover after reconnect, accept the next call.
set -Eeuo pipefail
recovery_script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
KAZOO_CALLS_LIBRARY=true source "$recovery_script_dir/test-kazoo-calls.sh"
RECOVERY_NODE_STOPPED=false
RECOVERY_WATCHDOG=''
RECOVERY_SERVICE=kazoo-ecallmgr.service

recovery_parse() {
    [[ $# == 1 || $# == 3 ]] || return 2
    [[ $1 == --prepare-only || $1 == --live ]] || return 2
    RECOVERY_SERVICE=kazoo-ecallmgr.service
    if [[ $# == 3 ]]; then
        [[ $2 == --fault && $3 == broker ]] || return 2
        RECOVERY_SERVICE=rabbitmq-server.service
    fi
}

recovery_status() {
    timeout 8 sup -n kazoo_apps -t 5 acdc_agent_maintenance agent_status \
        "${STATE[ACCEPTANCE_ACCOUNT_ID]}" "${STATE[ACCEPTANCE_AGENT_1_USER_ID]}" 2>/dev/null
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
    jq -e '.row_count==2 and ([.rows[].uuid]|unique|length)==2' <<<"$snapshot" >/dev/null || return 1
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
    recovery_parse "$@" || die 'Use --prepare-only or --live [--fault broker] (dev44 isolated fixture only)'
    [[ $EUID == 0 ]] || die 'Run as root'
    umask 077
    export KAZOO_CALLBACK_TEST_ACCOUNT_ID=8310dc3170a18de37f205d0da172df65
    node "$SCRIPT_DIR/test-fixtures/callback-fixture-account.cjs" --ensure-lock
    exec 9<>/etc/kazoo/monitor-acceptance.lock
    flock -n 9 || die 'Another fixture acceptance run is active'
    ip -o -4 addr show | grep -Eq '[[:space:]]10\.1\.0\.44/' || die 'Only main development host10.1.0.44 is allowed'
    load_state; validate_state
    [[ ${STATE[ACCEPTANCE_ACCOUNT_ID]} == "$KAZOO_CALLBACK_TEST_ACCOUNT_ID" ]] || die 'Wrong isolated account'
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
    trap recovery_cleanup EXIT INT TERM
    local before_apps before_fsm status deadline since cores
    before_apps=$(systemctl show -p MainPID --value kazoo-apps.service)
    STATUS_AGENT_MAX=${STATE[ACCEPTANCE_AGENT_COUNT]}
    agent_status logout 1 "$STATUS_AGENT_MAX"
    register_agents node-loss 1
    register_caller node-loss "$CALLER_PORT"
    start_agent_uas node-loss 1
    agent_status login 1 1
    start_callers node-loss 1 "$CALLER_PORT" "$CALLER_MEDIA_MIN" "$CALLER_MEDIA_MAX" 60000
    wait_concurrent_call_legs node-loss 1 1 || die 'Initial queued call not connected'
    status=$(recovery_status)
    recovery_has_state answered "$status" || die 'Agent must be answered before node loss'
    before_fsm=$(recovery_fsm_identity "$status")
    [[ $before_fsm =~ ^[0-9]+\.[0-9]+$ ]] || die 'Agent FSM identity missing'
    printf '%s\n' "$before_fsm" > "$RUN_DIR/fsm-before.txt"
    recovery_owned_pair || die 'Only the two answered isolated fixture legs may exist'
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
    assert_stats 'node-loss caller' "$RUN_DIR/node-loss-caller-stats.csv" 1
    assert_agent_stats node-loss 1 1
    recovery_channels | jq -e '.row_count==0' >/dev/null || die 'Native calls have not ended'
    # Cover one complete production30s reconciliation interval while no node
    # can supply authoritative status. Unknown evidence must not free the agent.
    deadline=$((SECONDS + 35))
    while ((SECONDS < deadline)); do
        status=$(recovery_status)
        recovery_has_state answered "$status" || die 'Agent became available without channel evidence'
        [[ $(recovery_fsm_identity "$status") == "$before_fsm" ]] || die 'Agent FSM was replaced during node loss'
        sleep 1
    done
    log 'PASS ended call remained conservatively busy while node evidence was unavailable'
    timeout 90 systemctl start "$RECOVERY_SERVICE"
    systemctl is-active --quiet "$RECOVERY_SERVICE"
    RECOVERY_NODE_STOPPED=false
    deadline=$((SECONDS + 90))
    while ((SECONDS < deadline)); do
        status=$(recovery_status)
        if recovery_has_state ready "$status"; then break; fi
        sleep 1
    done
    recovery_has_state ready "$status" || die 'Ended call did not recover after eCallMgr reconnect'
    [[ $(recovery_fsm_identity "$status") == "$before_fsm" ]] || die 'A replacement FSM is not recovery proof'
    printf '%s\n' "$(recovery_fsm_identity "$status")" > "$RUN_DIR/fsm-after.txt"
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
    start_agent_uas after-node-loss 1
    start_callers after-node-loss 1 "$CALLER_PORT" "$CALLER_MEDIA_MIN" "$CALLER_MEDIA_MAX" 30000
    wait_agent_observed_answer after-node-loss 1 || die 'Recovered agent did not answer the next call'
    wait_checked 'after-node-loss caller' "$CALLER_PID"
    wait_agents_checked after-node-loss
    stop_rtp_capture; stop_monitor
    assert_stats 'after-node-loss caller' "$RUN_DIR/after-node-loss-caller-stats.csv" 1
    assert_agent_stats after-node-loss 1 1
    assert_rtp_capture after-node-loss 1 1
    wait_agent_ready 1 || die 'Second call did not return agent to ready'
    record_stage after-node-loss 1 1 "$RUN_DIR/after-node-loss-caller-stats.csv" 1 "$cores" "$since"
    log "PASS native node-loss/missed-hangup recovery and next-call SIP/RTP; evidence: $RUN_DIR"
}
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then recovery_main "$@"; fi
