#!/usr/bin/env bash
# Explicit opt-in retained-fixture diagnostic. Never a full cleanup/production
# acceptance claim: historical unresolved callback documents are NOT rewritten.
# shellcheck disable=SC1091,SC2034,SC2317
set -Eeuo pipefail
retry_script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
KAZOO_CALLBACK_CALLS_LIBRARY=true source "$retry_script_dir/test-acdc-callback-calls.sh"
readonly RETRY_ACCOUNT_ID=7807ad61761269a1ccec833dde63f621
readonly RETRY_BUSY_PORT=15066
readonly RETRY_BUSY_MEDIA=43020
RETRY_REFERENCE=
RETRY_BUSY_PID=
RETRY_BUSY_CALL_ID=
RETRY_BUSY_PROOF=
RETRY_UNANSWERED_PID=
RETRY_CLEANING=false
RETRY_BUSY_CLEARED=false

retry_usage() {
    printf '%s\n' \
        'Usage: test-acdc-callback-retry.sh --prepare-only --confirmation-reference FILE' \
        '       test-acdc-callback-retry.sh --live --keep-fixture --confirmation-reference FILE' \
        'Only the exact isolated local fixture is allowed. MASTER and PSTN are excluded.' \
        'Busy agent -> queued caller waits5s -> callback registration/audio proof ->' \
        'wait2s -> release busy call -> unanswered first attempt -> answered retry.' \
        'Requires explicit runtime release. Known server errors remain final log-gate failures.'
}

retry_args() {
    while (($#)); do
        case $1 in
            --prepare-only) CALLBACK_PREPARE=true ;;
            --live) CALLBACK_LIVE=true ;;
            --keep-fixture) KEEP_FIXTURE=true ;;
            --confirmation-reference) (($# >= 2)) || die 'Missing reference'; RETRY_REFERENCE=$2; shift ;;
            -h|--help) retry_usage; exit 0 ;;
            *) die 'Unsupported callback retry option' ;;
        esac
        shift
    done
    [[ $CALLBACK_PREPARE != "$CALLBACK_LIVE" ]] || die 'Choose exactly prepare-only or live'
    [[ $CALLBACK_LIVE != true || $KEEP_FIXTURE == true ]] || die 'Historical fixture is retained: --keep-fixture is mandatory'
    [[ -n $RETRY_REFERENCE && -f $RETRY_REFERENCE && ! -L $RETRY_REFERENCE ]] || die 'A verified local confirmation reference is required'
    validate_protected_file "$RETRY_REFERENCE"
    validate_protected_file "${RETRY_REFERENCE%/*}/reference-receipt.json"
    node "$retry_script_dir/test-fixtures/callback-gemini-reference.cjs" verify "$RETRY_REFERENCE" \
        >/dev/null || die 'Reference does not match installed-prompt receipt'
}

retry_snapshot() {
    local raw
    raw=$(timeout 5 /usr/local/freeswitch/bin/fs_cli -x 'show channels as json' 2>/dev/null) || return 1
    jq -ce 'if .row_count==0 and (.rows==null or .rows==[]) then .rows=[] else . end |
        select((.rows|type)=="array" and (.row_count|tonumber)==(.rows|length) and
            all(.rows[];(.uuid|type)=="string" and (.uuid|length)>0 and (.uuid|length)<=512) and
            ([.rows[].uuid]|unique|length)==(.rows|length)) |
        {row_count,rows:[.rows[]|{uuid,direction}]}' <<<"$raw"
}

retry_channel() {
    local id=$1 raw
    [[ $id =~ ^[A-Za-z0-9@._:-]{1,128}$ ]] || return 1
    raw=$(timeout 5 /usr/local/freeswitch/bin/fs_cli -x "uuid_dump $id json" 2>/dev/null) || return 1
    jq -ce --arg id "$id" 'select(.["Unique-ID"]==$id) |
        {id:.["Unique-ID"],account:.["variable_ecallmgr_Account-ID"],bridge_to:.variable_bridge_to,
         sip_call_id:.variable_sip_call_id,contact_host:.variable_sip_contact_host,
         contact_port:.variable_sip_contact_port,answered:.["Caller-Channel-Answered-Time"],
         authority:.["variable_ecallmgr_Authorizing-ID"],agent_id:.["variable_ecallmgr_Agent-ID"],
         callback_id:.["variable_ecallmgr_Callback-ID"]}' <<<"$raw" 2>/dev/null
}

retry_busy_pair() {
    local caller agent agent_id
    caller=$(retry_channel "$RETRY_BUSY_CALL_ID") || return 1
    agent_id=$(jq -er '.bridge_to|select(type=="string" and length>0)' <<<"$caller") || return 1
    agent=$(retry_channel "$agent_id") || return 1
    jq -cen --arg account "$RETRY_ACCOUNT_ID" --arg call "$RETRY_BUSY_CALL_ID" \
        --arg user "${STATE[ACCEPTANCE_AGENT_1_USER_ID]}" --arg device "${STATE[ACCEPTANCE_AGENT_1_DEVICE_ID]}" \
        --arg caller_device "${STATE[ACCEPTANCE_CALLER_DEVICE_ID]}" --arg caller_user "${STATE[ACCEPTANCE_CALLER_USER_ID]}" \
        --argjson caller "$caller" --argjson agent "$agent" '
        select($caller.id==$call and $caller.account==$account and $agent.account==$account and
          $caller.bridge_to==$agent.id and $agent.bridge_to==$caller.id and
          $caller.contact_host=="127.0.0.20" and ($caller.contact_port|tonumber)==15066 and
          $agent.contact_host=="127.0.0.20" and ($agent.contact_port|tonumber)==15100 and
          ($caller.answered|tonumber)>0 and ($agent.answered|tonumber)>0 and
          ($caller.authority==$caller_device or $caller.authority==$caller_user) and
          ($agent.authority==$user or $agent.authority==$device or $agent.agent_id==$user)) |
        {caller:$caller,agent:$agent}'
}

retry_wait_busy() {
    local deadline=$((SECONDS + 45)) proof
    while ((SECONDS < deadline)); do
        kill -0 "$RETRY_BUSY_PID" 2>/dev/null || return 1
        if proof=$(retry_busy_pair); then
            RETRY_BUSY_PROOF=$proof
            printf '%s\n' "$proof" > "$RUN_DIR/retry-busy-bridge.json"
            return 0
        fi
        sleep 1
    done
    return 1
}

retry_clear_busy() {
    local proof snapshot reply agent deadline=$((SECONDS + 10))
    [[ -n $RETRY_BUSY_CALL_ID && $RETRY_BUSY_CLEARED != true ]] || return 0
    snapshot=$(retry_snapshot) || return 1
    if jq -e --arg id "$RETRY_BUSY_CALL_ID" 'all(.rows[];.uuid!=$id)' <<<"$snapshot" >/dev/null; then
        # If a previously proved pair existed, absence of BOTH legs is needed.
        if [[ -n $RETRY_BUSY_PROOF ]]; then
            agent=$(jq -r '.agent.id' <<<"$RETRY_BUSY_PROOF")
            jq -e --arg id "$agent" 'all(.rows[];.uuid!=$id)' <<<"$snapshot" >/dev/null || return 1
        fi
        RETRY_BUSY_CLEARED=true; return 0
    fi
    proof=$(retry_busy_pair) || return 1
    if [[ -n $RETRY_BUSY_PROOF ]]; then
        jq -e --argjson old "$RETRY_BUSY_PROOF" '.caller.id==$old.caller.id and .agent.id==$old.agent.id' <<<"$proof" >/dev/null || return 1
    fi
    RETRY_BUSY_PROOF=$proof
    agent=$(jq -r '.agent.id' <<<"$proof")
    # Only this fixed, freshly correlated local caller UUID is terminated.
    date -u +%s.%N > "$RUN_DIR/retry-busy-release-epoch.txt"
    reply=$(timeout 5 /usr/local/freeswitch/bin/fs_cli -x "uuid_kill $RETRY_BUSY_CALL_ID NORMAL_CLEARING" 2>/dev/null) || return 1
    [[ $reply == '+OK' ]] || return 1
    while ((SECONDS < deadline)); do
        snapshot=$(retry_snapshot) || return 1
        if jq -e --arg caller "$RETRY_BUSY_CALL_ID" --arg agent "$agent" \
            'all(.rows[];.uuid!=$caller and .uuid!=$agent)' <<<"$snapshot" >/dev/null; then
            printf '%s\n' "$snapshot" > "$RUN_DIR/retry-busy-both-down.json"
            RETRY_BUSY_CLEARED=true; return 0
        fi
        sleep 1
    done
    return 1
}

retry_capture() {
    local phase=$1 filter
    filter="udp and (((src host 127.0.0.20 and (src port 15064 or src port 15066 or src port 15100 or src port 43000 or src port 43020 or src port 40000)) or (dst host 127.0.0.20 and (dst port 15064 or dst port 15066 or dst port 15100 or dst port 43000 or dst port 43020 or dst port 40000))) or ((src host 127.0.0.30 and (src port 16060 or src port 44000)) or (dst host 127.0.0.30 and (dst port 16060 or dst port 44000))))"
    RTP_PCAP=$RUN_DIR/retry-$phase.pcap
    RTP_CAPTURE_LOG=$RUN_DIR/retry-$phase-capture.log
    # -U flushes the output writer, not libpcap's kernel capture buffer.
    # Immediate delivery is required before stopping just after CANCEL/ACK.
    tcpdump --immediate-mode -B 16384 -q -n -i any -U -w "$RTP_PCAP" "$filter" >"$RTP_CAPTURE_LOG" 2>&1 &
    RTP_CAPTURE_PID=$!; ACTIVE_PIDS+=("$RTP_CAPTURE_PID")
    sleep 1
    kill -0 "$RTP_CAPTURE_PID" 2>/dev/null || die 'Scoped retry capture failed'
}

retry_stop_capture() {
    stop_rtp_capture
    # tcpdump drops its writer uid. Transfer ONLY this stopped phase's exact
    # file inside our root-private directory; never loosen evidence ownership.
    [[ -d $RUN_DIR && ! -L $RUN_DIR && $(stat -Lc '%u:%g:%a' "$RUN_DIR") == 0:0:700 &&
       ${RTP_PCAP%/*} == "$RUN_DIR" && -f $RTP_PCAP && ! -L $RTP_PCAP &&
       $(stat -Lc '%h' "$RTP_PCAP") == 1 ]] || die 'Unsafe stopped capture path'
    case ${RTP_PCAP##*/} in
        retry-original.pcap|retry-unanswered.pcap|retry-returned.pcap) ;;
        *) die 'Unknown retry capture phase' ;;
    esac
    chown 0:0 -- "$RTP_PCAP"
    chmod 0600 -- "$RTP_PCAP"
    [[ -f $RTP_CAPTURE_LOG && ! -L $RTP_CAPTURE_LOG && ${RTP_CAPTURE_LOG%/*} == "$RUN_DIR" ]] || die 'Missing exact capture completion log'
    grep -Eq '^0 packets dropped by kernel$' "$RTP_CAPTURE_LOG" || die 'Capture loss makes negative SIP evidence inconclusive'
}

retry_start_busy() {
    local csv=$RUN_DIR/retry-busy-input.csv
    write_caller_csv "$csv" 1 1 120000 120000 0
    sipp -ci 127.0.0.1 "${STATE[ACCEPTANCE_SIP_PROXY_HOST]}:${STATE[ACCEPTANCE_SIP_PROXY_PORT]}" \
        -sf "$RUN_DIR/callback-busy-caller.xml" -inf "$csv" -i "$LOCAL_IP" -p "$RETRY_BUSY_PORT" \
        -mi "$LOCAL_IP" -min_rtp_port "$RETRY_BUSY_MEDIA" -max_rtp_port "$((RETRY_BUSY_MEDIA + 3))" \
        -m 1 -l 1 -nostdin -timeout 150s -timeout_error -trace_stat -fd 1s \
        -stf "$RUN_DIR/retry-busy-stats.csv" >"$RUN_DIR/retry-busy.log" 2>&1 &
    RETRY_BUSY_PID=$!; ACTIVE_PIDS+=("$RETRY_BUSY_PID")
    RETRY_BUSY_CALL_ID="1-${RETRY_BUSY_PID}@${LOCAL_IP}"
}

retry_start_original() {
    local csv=$RUN_DIR/callback-original-input.csv
    write_callback_request_csv "$csv"
    sipp -ci 127.0.0.1 "${STATE[ACCEPTANCE_SIP_PROXY_HOST]}:${STATE[ACCEPTANCE_SIP_PROXY_PORT]}" \
        -sf "$RUN_DIR/callback-retry-request.xml" -inf "$csv" -i "$LOCAL_IP" -p "$CALLER_PORT" \
        -mi "$LOCAL_IP" -min_rtp_port "$CALLBACK_ORIGINAL_MEDIA_PORT" -max_rtp_port "$((CALLBACK_ORIGINAL_MEDIA_PORT + 3))" \
        -rtp_echo -m 1 -l 1 -nostdin -aa -timeout 75s -timeout_error -trace_stat -fd 1s \
        -stf "$RUN_DIR/callback-original-stats.csv" >"$RUN_DIR/callback-original.log" 2>&1 &
    CALLBACK_ORIGINAL_PID=$!; ACTIVE_PIDS+=("$CALLBACK_ORIGINAL_PID")
    CALLBACK_ORIGINAL_CALL_ID="1-${CALLBACK_ORIGINAL_PID}@${LOCAL_IP}"
    MAIN_CALLER_PID=$CALLBACK_ORIGINAL_PID
}

retry_start_unanswered() {
    sipp -ci 127.0.0.1 -sf "$SCENARIO_DIR/callback-unanswered.xml" -i "$CARRIER_IP" -p "$CARRIER_PORT" \
        -m 1 -l 1 -nostdin -timeout 90s -timeout_error -trace_stat -fd 1s \
        -stf "$RUN_DIR/retry-unanswered-stats.csv" -trace_logs \
        -log_file "$RUN_DIR/retry-unanswered-events.log" >"$RUN_DIR/retry-unanswered.log" 2>&1 &
    RETRY_UNANSWERED_PID=$!; ACTIVE_PIDS+=("$RETRY_UNANSWERED_PID")
    sleep 1
    kill -0 "$RETRY_UNANSWERED_PID" 2>/dev/null || die 'Unanswered carrier exited before first attempt'
}

retry_wait_backoff() {
    local deadline=$((SECONDS + 12)) doc snapshot first_id
    while ((SECONDS < deadline)); do
        doc=$(callback_document) || return 1
        if jq -e --argjson before "$CALLBACK_REGISTRATION_EVIDENCE" '
            .id==$before.id and .status=="retry_wait" and .attempts==1 and
            .max_attempts==2 and .retry_delay==15 and .next_attempt_at>0 and
            .reconciliation_required!=true' <<<"$doc" >/dev/null; then
            first_id=$(jq -er '.caller.id' "$RUN_DIR/retry-first-attempt.json") || return 1
            snapshot=$(retry_snapshot) || return 1
            jq -e --arg first "$first_id" --arg original "$CALLBACK_ORIGINAL_CALL_ID" \
                'all(.rows[];.uuid!=$first and .uuid!=$original)' <<<"$snapshot" >/dev/null || return 1
            printf '%s\n' "$snapshot" > "$RUN_DIR/retry-first-both-down.json"
            printf '%s\n' "$doc" > "$RUN_DIR/retry-backoff-evidence.json"; return 0
        fi
        [[ $(jq -r '.attempts' <<<"$doc") == 1 ]] || return 1
        sleep 1
    done
    return 1
}

retry_wait_first_attempt() {
    local deadline=$((SECONDS + 12)) doc caller
    while ((SECONDS < deadline)); do
        doc=$(callback_document) || return 1
        if jq -e '.attempts==1 and (.caller_call_id|type)=="string"' <<<"$doc" >/dev/null; then
            if caller=$(retry_channel "$(jq -r '.caller_call_id' <<<"$doc")") &&
                jq -e --arg account "$RETRY_ACCOUNT_ID" --arg callback "$CALLBACK_TICKET_ID" '
                    .account==$account and .callback_id==$callback and
                    (.answered==null or (.answered|tonumber)==0) and
                    (.bridge_to==null or .bridge_to=="") and
                    (.sip_call_id|type)=="string"' <<<"$caller" >/dev/null; then
                jq -n --argjson callback "$doc" --argjson caller "$caller" '{callback:$callback,caller:$caller}' \
                    > "$RUN_DIR/retry-first-attempt.json"
                return 0
            fi
        fi
        [[ $(jq -r '.attempts' <<<"$doc") != 2 ]] || return 1
        sleep 1
    done
    return 1
}

retry_wait_bridge() {
    local deadline=$((SECONDS + 75)) doc caller agent
    while ((SECONDS < deadline)); do
        kill -0 "$CARRIER_PID" 2>/dev/null || return 1
        doc=$(callback_document) || return 1
        if [[ $(jq -r '.status' <<<"$doc") == completed ]]; then
            jq -e --argjson before "$CALLBACK_REGISTRATION_EVIDENCE" '
                .id==$before.id and .enqueued_at==$before.enqueued_at and .enqueue_sequence==$before.enqueue_sequence and
                .attempts==2 and .max_attempts==2 and .retry_delay==15 and .reconciliation_required!=true' <<<"$doc" >/dev/null || return 1
            caller=$(callback_channel "$(jq -r '.caller_call_id' <<<"$doc")") || return 1
            agent=$(callback_channel "$(jq -r '.agent_call_id' <<<"$doc")") || return 1
            jq -cen --arg account "$RETRY_ACCOUNT_ID" --argjson callback "$doc" --argjson caller "$caller" --argjson agent "$agent" '
                select($caller.account==$account and $agent.account==$account and
                    $caller.bridge_to==$agent.id and $agent.bridge_to==$caller.id) |
                {callback:$callback,caller:$caller,agent:$agent}' > "$RUN_DIR/retry-bridge-evidence.json" || return 1
            return 0
        fi
        [[ $(jq -r '.status' <<<"$doc") != @(failed|cancelled|expired|cancelling) ]] || return 1
        sleep 1
    done
    return 1
}

retry_cleanup() {
    local status=$?
    [[ $RETRY_CLEANING == false ]] || return
    RETRY_CLEANING=true
    # A queued callback must be cancelled while the agent is STILL busy, not
    # after releasing it (which could trigger an unintended cleanup attempt).
    if [[ $FIXTURE_CREATED == true && -n $CALLBACK_ORIGINAL_CALL_ID ]]; then
        if ! callback_fixture cancel-original "$CALLBACK_ORIGINAL_CALL_ID" > "$RUN_DIR/retry-current-cleanup.log" 2>&1; then
            warn 'Current callback settlement failed; retaining fixture'
            ((status != 0)) || status=1
            # Prevent a ready agent starting another owned attempt if the
            # cancellation backend is unavailable. No MASTER agent is touched.
            agent_status logout 1 1 >/dev/null 2>&1 || true
        fi
    fi
    if ! retry_clear_busy; then
        warn 'Exact busy-call cleanup unavailable; retained fixture and proof'
        ((status != 0)) || status=1
    fi
    # This existing helper cancels/settles ONLY the current original callback.
    # Historical unknown tickets/resources remain untouched in keep mode.
    (exit "$status") || callback_cleanup
    callback_cleanup
}

retry_wait_checked() {
    local label=$1 pid=$2 status
    if wait "$pid"; then status=0; else status=$?; fi
    printf '%s\t%s\t%s\n' "$label" "$pid" "$status" >> "$RUN_DIR/retry-process-exits.tsv"
    ((status == 0)) || die "$label SIPp exited $status; SIP counters alone are not process/media success"
}

retry_run() {
    local since cores before snapshot
    callback_fixture preflight || die 'Callback SUP prerequisite failed before fixture or agent writes'
    snapshot=$(retry_snapshot) || die 'Native channel inventory unavailable'
    jq -e '.row_count==0' <<<"$snapshot" >/dev/null || die 'Live retry requires zero active calls at entry'
    before=$(systemctl show kazoo-apps kazoo-ecallmgr kazoo-freeswitch kazoo-kamailio kazoo-live-test-agents -p Id -p ActiveState -p MainPID -p NRestarts)
    printf '%s\n' "$before" > "$RUN_DIR/retry-service-before.txt"
    [[ $(grep -c '^ActiveState=active$' <<<"$before") == 5 ]] || die 'Required services are not active'
    callback_fixture setup-retry
    callback_fixture verify
    FIXTURE_CREATED=true
    STATUS_AGENT_MAX=${STATE[ACCEPTANCE_AGENT_COUNT]}
    agent_status logout 1 "$STATUS_AGENT_MAX"
    cores=$(core_count); since=$(date +%s)
    capture_log_baseline callback
    start_monitor callback
    register_caller callback "$CALLER_PORT" 600
    register_agents callback 1 600
    start_agent_uas callback 1 1
    agent_status login 1 1
    retry_start_busy
    retry_wait_busy || die 'Initial call did not prove an exact native agent bridge'
    # Registration and the first conversation's SIP setup precede this exact
    # original-caller phase. Its audio checker rejects unrelated SIP dialogs.
    retry_capture original
    retry_start_original
    retry_wait_checked 'retry original registration/menu' "$CALLBACK_ORIGINAL_PID"
    assert_stats 'retry original registration/menu' "$RUN_DIR/callback-original-stats.csv" 1
    wait_callback_registered || die 'Busy-agent callback did not remain queued with zero attempts'
    retry_stop_capture
    node "$retry_script_dir/test-fixtures/assert-callback-registration-audio.cjs" \
        "$RUN_DIR/retry-original.pcap" "$RETRY_REFERENCE" "$CALLBACK_ORIGINAL_CALL_ID" "$LOCAL_IP" "$CALLER_PORT" "$CALLBACK_ORIGINAL_MEDIA_PORT" \
        > "$RUN_DIR/retry-registration-audio.json" || die 'Received callback registration confirmation audio is unproven'
    retry_busy_pair > "$RUN_DIR/retry-busy-before-release.json" || die 'First call did not remain bridged through callback confirmation'
    retry_capture unanswered
    retry_start_unanswered
    sleep 2
    retry_clear_busy || die 'Could not safely release the exact initial fixture call'
    retry_wait_checked 'initial busy caller' "$RETRY_BUSY_PID"
    assert_stats 'initial busy caller' "$RUN_DIR/retry-busy-stats.csv" 1
    log 'Busy call bridged; queued callback confirmation audio proved; first call released after two-second post-proof wait'
    retry_wait_first_attempt || die 'First unanswered returned attempt lacks exact durable/native correlation'
    retry_wait_checked 'deliberately unanswered first returned attempt' "$RETRY_UNANSWERED_PID"
    assert_stats 'unanswered CANCEL transaction' "$RUN_DIR/retry-unanswered-stats.csv" 1
    retry_stop_capture
    retry_capture returned
    # Start the answering endpoint inside the configured 15s backoff window.
    start_returned_carrier
    retry_wait_backoff || die 'First unanswered attempt did not durably enter retry_wait with positive settlement'
    retry_wait_bridge || die 'Second returned attempt did not durably complete an exact native bridge'
    log 'First attempt unanswered; durable retry_wait observed; second attempt completed with reciprocal native bridge'
    retry_wait_checked 'second returned carrier' "$CARRIER_PID"
    wait_agents_checked callback
    assert_stats 'second returned carrier' "$RUN_DIR/callback-carrier-stats.csv" 1
    assert_agent_stats callback 1 2
    retry_stop_capture
    stop_monitor
    node "$retry_script_dir/test-fixtures/assert-callback-retry.cjs" "$RUN_DIR" || die 'Strict unanswered/retry packet, media or timing gate failed'
    agent_status verify 1 1
    wait_agent_ready 1 || die 'Agent did not return ready after retry'
    [[ $(systemctl show kazoo-apps kazoo-ecallmgr kazoo-freeswitch kazoo-kamailio kazoo-live-test-agents -p Id -p ActiveState -p MainPID -p NRestarts) == "$before" ]] || die 'A service changed during the retry diagnostic'
    record_stage callback 1 2 "$RUN_DIR/callback-original-stats.csv" 1 "$cores" "$since" "$RUN_DIR/retry-busy-stats.csv"
    log "Retained-fixture callback retry diagnostic passed; NOT full cleanup or production acceptance: $RUN_DIR"
}

main_retry() {
    umask 077
    ((EUID == 0)) || die 'Run as root to protect fixture credentials'
    retry_args "$@"
    INSTALL_DEPS=false
    load_state; validate_state; resolve_local_ip
    [[ ${STATE[ACCEPTANCE_ACCOUNT_ID]} == "$RETRY_ACCOUNT_ID" && $LOCAL_IP == 127.0.0.20 ]] || die 'Wrong account or non-isolated local endpoint'
    ensure_sipp
    for file in create-callback-retry-scenarios.cjs assert-callback-retry.cjs assert-callback-registration-audio.cjs; do
        node --check "$retry_script_dir/test-fixtures/$file"
    done
    if [[ $CALLBACK_PREPARE == true ]]; then log 'Retry sources and isolated state validated; no API writes or SIP traffic'; return; fi
    [[ -f /etc/kazoo/monitor-acceptance.lock && ! -L /etc/kazoo/monitor-acceptance.lock ]] || die 'Missing shared acceptance lock'
    exec 9<>/etc/kazoo/monitor-acceptance.lock
    flock -n 9 || die 'Another acceptance task owns the shared lock'
    create_run_dir
    trap retry_cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    sha256sum "$RETRY_REFERENCE" | awk '{print $1}' > "$RUN_DIR/retry-registration-reference-sha256.txt"
    cp -- "${RETRY_REFERENCE%/*}/reference-receipt.json" "$RUN_DIR/retry-registration-reference-receipt.json"
    node "$retry_script_dir/test-fixtures/create-callback-retry-scenarios.cjs" "$RUN_DIR"
    retry_run
}

if [[ ${KAZOO_CALLBACK_RETRY_LIBRARY:-false} != true ]]; then main_retry "$@"; fi
