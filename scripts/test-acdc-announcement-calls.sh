#!/usr/bin/env bash
# One real caller; only a new marked queue2099 in the isolated acceptance tenant.
# shellcheck disable=SC1091,SC2034,SC2317
set -Eeuo pipefail
announcement_script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
KAZOO_CALLS_LIBRARY=true source "$announcement_script_dir/test-kazoo-calls.sh"
INSTALL_DEPS=false
announcement_fixture=$SCRIPT_DIR/test-fixtures/announcement-queue.cjs
announcement_audio=$SCRIPT_DIR/test-fixtures/assert-announcement-audio.cjs
announcement_media_port=47000
announcement_capture_pid=
announcement_fixture_started=false
announcement_cleaning=false
announcement_cleanup() {
    local result=$?
    [[ $announcement_cleaning == false ]] || return
    announcement_cleaning=true
    cleanup || true
    if [[ $announcement_fixture_started == true ]]; then
        KAZOO_ACCEPTANCE_STATE_FILE=$STATE_FILE node "$announcement_fixture" cleanup "$RUN_DIR" || result=1
    fi
    if ((result == 0)); then log "PASS real announcement audio/timing/teardown and exact fixture cleanup; protected evidence:$RUN_DIR"; fi
    trap - EXIT
    exit "$result"
}
announcement_main() {
    umask 077
    ((EUID == 0)) || die 'Run as root'
    case ${1:-} in --prepare-only) LIVE=false ;; --live) LIVE=true ;; *) die 'Use --prepare-only or --live' ;; esac
    load_state; validate_state; resolve_local_ip; ensure_sipp
    [[ ${STATE[ACCEPTANCE_REALM]} =~ ^acceptance-[a-f0-9]{12}\.invalid$ ]] || die 'Non-isolated realm'
    command -v sox >/dev/null || die 'sox is required for reference audio conversion'
    node --check "$announcement_fixture"; node --check "$announcement_audio"
    if [[ $LIVE != true ]]; then log 'PASS announcement prepare; no API mutations or SIP traffic'; return; fi
    create_run_dir
    trap announcement_cleanup EXIT
    trap 'exit 130' INT TERM
    announcement_fixture_started=true
    KAZOO_ACCEPTANCE_STATE_FILE=$STATE_FILE node "$announcement_fixture" setup "$RUN_DIR"
    sup -e supervisor which_children acdc_announcements_sup > "$RUN_DIR/announcement-workers-before.txt"
    # The fixture uses no agents; preserve all acceptance and MASTER statuses.
    STATE[ACCEPTANCE_QUEUE_EXTENSION]=2099
    register_caller announcement "$CALLER_PORT"
    RTP_PCAP=$RUN_DIR/announcement-rtp.pcap
    tcpdump -q -n -s 0 -i any -U -w "$RTP_PCAP" \
        "udp and host $LOCAL_IP and (port $announcement_media_port or port $CALLER_PORT)" \
        > "$RUN_DIR/announcement-capture.log" 2>&1 &
    announcement_capture_pid=$!; ACTIVE_PIDS+=("$announcement_capture_pid")
    sleep 1
    kill -0 "$announcement_capture_pid" || die 'Capture did not start'
    write_caller_csv "$RUN_DIR/announcement-input.csv" 1 1 75000 75000 0
    sipp "${STATE[ACCEPTANCE_SIP_PROXY_HOST]}:${STATE[ACCEPTANCE_SIP_PROXY_PORT]}" \
        -sf "$SCENARIO_DIR/caller-to-queue.xml" -inf "$RUN_DIR/announcement-input.csv" \
        -i "$LOCAL_IP" -p "$CALLER_PORT" -mi "$LOCAL_IP" -mp "$announcement_media_port" \
        -min_rtp_port "$announcement_media_port" -max_rtp_port "$((announcement_media_port+3))" \
        -rtp_echo -m 1 -l 1 -r 1 -rp 1000 -nostdin -aa -timeout 110s -timeout_error \
        -trace_stat -fd 1s -stf "$RUN_DIR/announcement-caller-stats.csv" \
        > "$RUN_DIR/announcement-caller.log" 2>&1 &
    CALLER_PID=$!; ACTIVE_PIDS+=("$CALLER_PID")
    jq -n --arg call "1-${CALLER_PID}@${LOCAL_IP}" --arg ip "$LOCAL_IP" --argjson port "$announcement_media_port" \
        '{call_id:$call,source_ip:$ip,media_port:$port}' > "$RUN_DIR/announcement-call.json"
    wait_answered_calls "$RUN_DIR/announcement-caller-stats.csv" 1 || die 'Owned caller not answered'
    sleep 2
    sup -e supervisor which_children acdc_announcements_sup > "$RUN_DIR/announcement-workers-during.txt"
    log "Owned queue2099 caller active for75seconds; capture:$RUN_DIR"
    wait "$CALLER_PID" || die 'Announcement SIPp caller failed'
    assert_stats 'announcement caller' "$RUN_DIR/announcement-caller-stats.csv" 1
    sleep 3
    sup -e supervisor which_children acdc_announcements_sup > "$RUN_DIR/announcement-workers-after.txt"
    /usr/local/freeswitch/bin/fs_cli -x "uuid_exists 1-${CALLER_PID}@${LOCAL_IP}" | grep -Fxq false || die 'Owned channel remains after BYE'
    kill -INT "$announcement_capture_pid"; wait "$announcement_capture_pid" || true
    chown root:root "$RTP_PCAP"; chmod 600 "$RTP_PCAP"
    sox "$SCRIPT_DIR/assets/acdc-callback-prompts/en-us/acdc-queue-your-current-position-is.wav" \
        -t raw -r 8000 -c 1 -e mu-law "$RUN_DIR/announcement-reference.ulaw"
    sox /usr/share/kazoo-freeswitch/sounds/en/us/callie/digits/8000/1.wav \
        -t raw -r 8000 -c 1 -e mu-law "$RUN_DIR/announcement-one-reference.ulaw"
    node "$announcement_audio" "$RTP_PCAP" "$RUN_DIR/announcement-reference.ulaw" \
        "1-${CALLER_PID}@${LOCAL_IP}" "$LOCAL_IP" "$announcement_media_port" "$RUN_DIR" "$RUN_DIR/announcement-one-reference.ulaw" \
        | tee "$RUN_DIR/announcement-audio-evidence.json"
    log "Audio/timing/teardown gate passed; exact fixture cleanup follows"
}
announcement_main "$@"
