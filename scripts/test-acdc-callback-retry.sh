#!/usr/bin/env bash
# Explicit opt-in retained-fixture diagnostic. Never a full cleanup/production
# acceptance claim: historical unresolved callback documents are NOT rewritten.
# shellcheck disable=SC1091,SC2034,SC2317
set -Eeuo pipefail
retry_script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
KAZOO_CALLBACK_CALLS_LIBRARY=true source "$retry_script_dir/test-acdc-callback-calls.sh"
RETRY_ACCOUNT_ID=7807ad61761269a1ccec833dde63f621
RETRY_ACCOUNT_EXPLICIT=false
readonly RETRY_BUSY_PORT=15066
readonly RETRY_BUSY_MEDIA=43020
RETRY_REFERENCE=
RETRY_REGISTRATION_MODE=confirm-current
RETRY_LANGUAGE=en-us
RETRY_LANGUAGE_EXPLICIT=false
RETRY_LANGUAGE_ARGS=()
RETRY_EDIT_PENDING_LANGUAGE=false
RETRY_SHORT_CONFIRMATION_WINDOW=false
RETRY_CONFIRMATION_EXPIRY=false
RETRY_QUEUE_RESTART=false
RETRY_WORKER_LOSS=false
RETRY_ALLOW_PAUSED_MASTER_TEST_PHONES=false
RETRY_ALLOW_ABSENT_MASTER_TEST_PHONES=false
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
        '       [--registration-mode entry-only|confirm-current] (default: confirm-current)' \
        '       [--language en-us|he-il|fr-fr|es-es|ar-sa] (explicit owned queue language; absent preserves queue)' \
        '       [--edit-pending-language] (main isolated fixture only; EN admission then FR queue edit and conditional restore)' \
        '       [--short-confirmation-window] (main isolated EN fixture only; response timeout3, full existing prompt, conditional restore)' \
        '       [--confirmation-expiry] (requires short window; answer retry without digit; assert timeout and no agent call)' \
        '       [--queue-restart-during-backoff] (main isolated fixture only; restart its queue with no active legs, retain retry)' \
        '       [--worker-loss-during-ringing] (main isolated fixture only; kill exactly its first active callback worker)' \
        '       [--fixture-account ACCOUNT_ID] (must match canonical protected isolated state)' \
        '       [--transport external|internal] (default: external; internal uses isolated1001)' \
        '       [--allow-paused-master-test-phones] (only an already inactive/dead helper)' \
        '       [--allow-absent-master-test-phones] (only a not-installed/dead helper)' \
        'Only the exact isolated local fixture is allowed. MASTER and PSTN are excluded.' \
        'Busy agent -> queued caller waits5s -> callback registration/audio proof ->' \
        'wait2s -> release busy call -> unanswered first attempt -> answered retry.' \
        'Requires explicit runtime release. Known server errors remain final log-gate failures.'
}

retry_args() {
    # Only this CLI's explicit option may authorize a fixture language write.
    # Clear inherited overrides before preflight, setup, evidence or cleanup.
    unset -v KAZOO_CALLBACK_TEST_LANGUAGE || die 'Cannot isolate callback fixture language environment'
    unset -v KAZOO_CALLBACK_TEST_ACCOUNT_ID || die 'Cannot isolate callback fixture account environment'
    while (($#)); do
        case $1 in
            --prepare-only) CALLBACK_PREPARE=true ;;
            --live) CALLBACK_LIVE=true ;;
            --keep-fixture) KEEP_FIXTURE=true ;;
            --confirmation-reference) (($# >= 2)) || die 'Missing reference'; RETRY_REFERENCE=$2; shift ;;
            --fixture-account)
                (($# >= 2)) || die 'Missing fixture account'
                [[ ${RETRY_ACCOUNT_EXPLICIT:-false} == false && $2 =~ ^[a-f0-9]{32}$ ]] || die 'Invalid or repeated fixture account'
                RETRY_ACCOUNT_ID=$2; RETRY_ACCOUNT_EXPLICIT=true; shift ;;
            --registration-mode) (($# >= 2)) || die 'Missing registration mode'; RETRY_REGISTRATION_MODE=$2; shift ;;
            --language)
                (($# >= 2)) || die 'Missing language'
                [[ $RETRY_LANGUAGE_EXPLICIT == false ]] || die 'Repeated language'
                case $2 in en-us|he-il|fr-fr|es-es|ar-sa) ;; *) die 'Unsupported callback retry language' ;; esac
                RETRY_LANGUAGE=$2; RETRY_LANGUAGE_EXPLICIT=true; RETRY_LANGUAGE_ARGS=("$2"); shift ;;
            --transport) (($# >= 2)) || die 'Missing transport'; CALLBACK_TEST_TRANSPORT=$2; shift ;;
            --edit-pending-language) [[ $RETRY_EDIT_PENDING_LANGUAGE == false ]] || die 'Repeated pending-language mode'; RETRY_EDIT_PENDING_LANGUAGE=true ;;
            --short-confirmation-window) [[ $RETRY_SHORT_CONFIRMATION_WINDOW == false ]] || die 'Repeated short-confirmation mode'; RETRY_SHORT_CONFIRMATION_WINDOW=true ;;
            --confirmation-expiry) [[ ${RETRY_CONFIRMATION_EXPIRY:-false} == false ]] || die 'Repeated confirmation-expiry mode'; RETRY_CONFIRMATION_EXPIRY=true ;;
            --queue-restart-during-backoff) [[ ${RETRY_QUEUE_RESTART:-false} == false ]] || die 'Repeated queue-restart mode'; RETRY_QUEUE_RESTART=true ;;
            --worker-loss-during-ringing) [[ $RETRY_WORKER_LOSS == false ]] || die 'Repeated worker-loss mode'; RETRY_WORKER_LOSS=true ;;
            --allow-paused-master-test-phones) RETRY_ALLOW_PAUSED_MASTER_TEST_PHONES=true ;;
            --allow-absent-master-test-phones) RETRY_ALLOW_ABSENT_MASTER_TEST_PHONES=true ;;
            -h|--help) retry_usage; exit 0 ;;
            *) die 'Unsupported callback retry option' ;;
        esac
        shift
    done
    [[ $RETRY_REGISTRATION_MODE == entry-only || $RETRY_REGISTRATION_MODE == confirm-current ]] || die 'Invalid registration mode'
    [[ $CALLBACK_TEST_TRANSPORT == external || $CALLBACK_TEST_TRANSPORT == internal ]] || die 'Invalid transport'
    [[ $RETRY_EDIT_PENDING_LANGUAGE != true || $RETRY_SHORT_CONFIRMATION_WINDOW != true ]] || die 'Choose only one pending queue edit case'
    [[ ${RETRY_CONFIRMATION_EXPIRY:-false} != true || $RETRY_SHORT_CONFIRMATION_WINDOW == true ]] || die 'Confirmation expiry requires explicit short confirmation window'
    [[ $RETRY_WORKER_LOSS != true || $RETRY_QUEUE_RESTART != true ]] || die 'Choose one callback fault boundary'
    if [[ ${RETRY_QUEUE_RESTART:-false} == true || $RETRY_WORKER_LOSS == true ]]; then
        [[ $RETRY_ACCOUNT_ID == 8310dc3170a18de37f205d0da172df65 && $RETRY_LANGUAGE_EXPLICIT == true &&
           $RETRY_LANGUAGE == en-us && $CALLBACK_TEST_TRANSPORT == internal && $RETRY_REGISTRATION_MODE == entry-only &&
           $RETRY_EDIT_PENDING_LANGUAGE == false && ${RETRY_CONFIRMATION_EXPIRY:-false} == false &&
           $RETRY_SHORT_CONFIRMATION_WINDOW == false ]] || die 'Queue restart requires the unedited main isolated EN/internal/entry-only fixture'
    fi
    if [[ $RETRY_EDIT_PENDING_LANGUAGE == true || $RETRY_SHORT_CONFIRMATION_WINDOW == true ]]; then
        [[ $RETRY_ACCOUNT_ID == 8310dc3170a18de37f205d0da172df65 && $RETRY_LANGUAGE_EXPLICIT == true &&
           $RETRY_LANGUAGE == en-us && $CALLBACK_TEST_TRANSPORT == internal && $RETRY_REGISTRATION_MODE == entry-only ]] ||
            die 'Pending-language case requires main isolated fixture, explicit EN, internal transport and entry-only'
    fi
    if [[ $CALLBACK_TEST_TRANSPORT == internal ]]; then CALLBACK_NUMBER=1001; CARRIER_IP=127.0.0.20; fi
    [[ $CALLBACK_PREPARE != "$CALLBACK_LIVE" ]] || die 'Choose exactly prepare-only or live'
    [[ $CALLBACK_LIVE != true || $KEEP_FIXTURE == true ]] || die 'Historical fixture is retained: --keep-fixture is mandatory'
    [[ -n $RETRY_REFERENCE && -f $RETRY_REFERENCE && ! -L $RETRY_REFERENCE ]] || die 'A verified local confirmation reference is required'
    validate_protected_file "$RETRY_REFERENCE"
    validate_protected_file "${RETRY_REFERENCE%/*}/reference-receipt.json"
    node "$retry_script_dir/test-fixtures/callback-gemini-reference.cjs" verify "$RETRY_REFERENCE" "$RETRY_LANGUAGE" \
        | jq -e --arg language "$RETRY_LANGUAGE" '.voice_family == "gemini-sulafat" and .language == $language' >/dev/null || \
        die 'Current callback acceptance requires a verified Gemini reference, not legacy audio'
    export KAZOO_CALLBACK_TEST_ACCOUNT_ID=${RETRY_ACCOUNT_ID:-7807ad61761269a1ccec833dde63f621}
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
    jq -ce --arg id "$id" --arg transport "$CALLBACK_TEST_TRANSPORT" 'select(.["Unique-ID"]==$id) |
        {id:.["Unique-ID"],account:.["variable_ecallmgr_Account-ID"],bridge_to:.variable_bridge_to,
         sip_call_id:(.variable_sip_call_id // (if $transport=="internal" and ($id|test("^[a-f0-9]{32}$")) then $id else null end)),
         sip_call_id_source:(if .variable_sip_call_id then "channel_variable" else "native_outbound_id_requires_packet_proof" end),
         contact_host:.variable_sip_contact_host,
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
    filter="udp and (((src host 127.0.0.20 and (src port 15064 or src port 15066 or src port 15100 or src port 43000 or src port 43020 or src port 40000)) or (dst host 127.0.0.20 and (dst port 15064 or dst port 15066 or dst port 15100 or dst port 43000 or dst port 43020 or dst port 40000))) or ((src host $CARRIER_IP and (src port 16060 or src port 44000)) or (dst host $CARRIER_IP and (dst port 16060 or dst port 44000))))"
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
    local scenario=$SCENARIO_DIR/callback-unanswered.xml
    if [[ $CALLBACK_TEST_TRANSPORT == internal ]]; then scenario=$RUN_DIR/callback-unanswered-internal.xml; fi
    sipp -ci 127.0.0.1 -sf "$scenario" -i "$CARRIER_IP" -p "$CARRIER_PORT" \
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
            if caller=$(retry_channel "$(jq -r '.caller_call_id' <<<"$doc")"); then
                # Restricted projection only, for diagnosing a failed invariant
                # without dumping raw SIP/channel variables or credentials.
                jq -n --argjson callback "$doc" --argjson caller "$caller" '{callback:$callback,caller:$caller}' \
                    > "$RUN_DIR/retry-first-observed.json"
                if jq -e --arg account "$RETRY_ACCOUNT_ID" --arg callback "$CALLBACK_TICKET_ID" '
                    .account==$account and .callback_id==$callback and
                    (.answered==null or (.answered|tonumber)==0) and
                    (.bridge_to==null or .bridge_to=="") and
                    (.sip_call_id|type)=="string"' <<<"$caller" >/dev/null; then
                jq -n --argjson callback "$doc" --argjson caller "$caller" '{callback:$callback,caller:$caller}' \
                    > "$RUN_DIR/retry-first-attempt.json"
                return 0
                fi
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
        # Assigned by start_returned_carrier in the sourced callback library.
        # shellcheck disable=SC2153
        kill -0 "$CARRIER_PID" 2>/dev/null || return 1
        doc=$(callback_document) || return 1
        if [[ $(jq -r '.status' <<<"$doc") == completed ]]; then
            jq -e --argjson before "$CALLBACK_REGISTRATION_EVIDENCE" '
                .id==$before.id and .enqueued_at==$before.enqueued_at and .enqueue_sequence==$before.enqueue_sequence and
                .attempts==2 and .max_attempts==2 and .retry_delay==15 and .reconciliation_required!=true and
                .originate_success_recorded==true' <<<"$doc" >/dev/null || return 1
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

# Fault injection is opt-in, queue-scoped and attempted at most once. Never
# restart services or infer that a timeout means the restart did not happen.
retry_restart_queue_in_backoff() {
    local doc snapshot before after before_local after_local queue now
    [[ ${RETRY_QUEUE_RESTART:-false} == true && $RETRY_ACCOUNT_ID == 8310dc3170a18de37f205d0da172df65 &&
       ${STATE[ACCEPTANCE_ACCOUNT_ID]} == "$RETRY_ACCOUNT_ID" &&
       ! -e $RUN_DIR/callback-queue-restart-started.json ]] || return 1
    queue=${STATE[ACCEPTANCE_QUEUE_ID]}
    [[ $queue == 67c5f3fb115bdd1dd574d6a604a7d29f ]] || return 1
    doc=$(callback_document) || return 1
    snapshot=$(retry_snapshot) || return 1
    now=$(date +%s) || return 1
    jq -e --argjson registered "$CALLBACK_REGISTRATION_EVIDENCE" --argjson now "$now" \
        --arg account "$RETRY_ACCOUNT_ID" --arg queue "$queue" '
        .account_id==$account and .queue_id==$queue and
        .id==$registered.id and .account_id==$registered.account_id and .queue_id==$registered.queue_id and
        .original_call_id==$registered.original_call_id and .status=="retry_wait" and .attempts==1 and
        .caller_call_id==null and .agent_call_id==null and .reconciliation_required!=true and
        .next_attempt_at>($now+62167219200+8)' <<<"$doc" >/dev/null || return 1
    jq -e '.row_count==0' <<<"$snapshot" >/dev/null || return 1
    before=$(sup -n kazoo_apps -t 5 acdc_queues_sup find_queue_supervisor "$RETRY_ACCOUNT_ID" "$queue") || return 1
    [[ $before =~ ^\<[0-9]{1,10}\.[0-9]{1,10}\.[0-9]{1,10}\>$ ]] || return 1
    # SUP prints an external PID in its own short-lived VM. The first number
    # is that client's node index, not a stable identity on the target node.
    before_local=${before#*.}; before_local=${before_local%>}
    jq -n --arg account "$RETRY_ACCOUNT_ID" --arg queue "$queue" --arg supervisor "$before" \
        --argjson doc "$doc" --argjson snapshot "$snapshot" --argjson started "$now" \
        '{account_id:$account,queue_id:$queue,supervisor_before:$supervisor,started_at:$started,
          callback:$doc,channels:$snapshot,restart_requests:1}' > "$RUN_DIR/callback-queue-restart-started.json" || return 1
    sup -n kazoo_apps -t 10 acdc_maintenance queue_restart "$RETRY_ACCOUNT_ID" "$queue" \
        > "$RUN_DIR/callback-queue-restart-command.txt" || return 1
    after=$(sup -n kazoo_apps -t 5 acdc_queues_sup find_queue_supervisor "$RETRY_ACCOUNT_ID" "$queue") || return 1
    [[ $after =~ ^\<[0-9]{1,10}\.[0-9]{1,10}\.[0-9]{1,10}\>$ ]] || return 1
    after_local=${after#*.}; after_local=${after_local%>}
    [[ $after_local != "$before_local" ]] || return 1
    jq --arg supervisor "$after" --arg before_local "$before_local" --arg after_local "$after_local" \
        --argjson finished "$(date +%s)" \
        '. + {supervisor_after:$supervisor,supervisor_before_local_id:$before_local,
              supervisor_after_local_id:$after_local,finished_at:$finished,replacement_verified:true}' \
        "$RUN_DIR/callback-queue-restart-started.json" > "$RUN_DIR/callback-queue-restart.json" || return 1
    log 'Isolated queue supervisor replaced during durable retry_wait; no services restarted'
}

# The first attempt is still unanswered. Only the returned second attempt is
# changed: answer, receive the full prompt, send no confirmation and await BYE.
retry_start_expiry_carrier() {
    write_returned_carrier_csv "$RUN_DIR/callback-carrier-input.csv" 6000
    node "$retry_script_dir/test-fixtures/callback-confirmation-expiry.cjs" generate "$RUN_DIR"
    sipp -ci 127.0.0.1 -sf "$RUN_DIR/callback-expiry.xml" -inf "$RUN_DIR/callback-carrier-input.csv" \
        -i "$CARRIER_IP" -p "$CARRIER_PORT" -mi "$CARRIER_IP" -mp "$CARRIER_MEDIA_PORT" \
        -min_rtp_port "$CARRIER_MEDIA_PORT" -max_rtp_port "$((CARRIER_MEDIA_PORT + 3))" \
        -m 1 -l 1 -nostdin -aa -timeout 90s -timeout_error -trace_stat -fd 1s \
        -stf "$RUN_DIR/callback-carrier-stats.csv" -trace_logs \
        -log_file "$RUN_DIR/callback-carrier-negotiation.log" > "$RUN_DIR/callback-carrier.log" 2>&1 &
    CARRIER_PID=$!; ACTIVE_PIDS+=("$CARRIER_PID")
    sleep 1
    kill -0 "$CARRIER_PID" 2>/dev/null || die 'No-confirmation caller exited before origination'
}

retry_wait_expiry() {
    local deadline=$((SECONDS + 60)) doc caller snapshot
    while ((SECONDS < deadline)); do
        doc=$(callback_document) || return 1
        jq -e --argjson before "$CALLBACK_REGISTRATION_EVIDENCE" '
            .id==$before.id and .attempts<=2 and .agent_call_id==null and
            .reconciliation_required!=true and .status!="completed"' <<<"$doc" >/dev/null || return 1
        if jq -e '.attempts==2 and (.caller_call_id|type)=="string"' <<<"$doc" >/dev/null; then
            if caller=$(retry_channel "$(jq -r '.caller_call_id' <<<"$doc")") &&
               jq -e --arg account "$RETRY_ACCOUNT_ID" --arg callback "$CALLBACK_TICKET_ID" '
                 .account==$account and .callback_id==$callback and (.answered|tonumber)>0 and
                 (.bridge_to==null or .bridge_to=="")' <<<"$caller" >/dev/null; then
                jq -n --argjson callback "$doc" --argjson caller "$caller" '{callback:$callback,caller:$caller}' \
                    > "$RUN_DIR/callback-expiry-answered.json"
            fi
        fi
        if jq -e '.status=="failed" and .attempts==2 and .last_cause=="confirmation_timeout" and
            .caller_call_id==null and .agent_call_id==null and .selected_agents==null' <<<"$doc" >/dev/null; then
            [[ -s $RUN_DIR/callback-expiry-answered.json ]] || return 1
            snapshot=$(retry_snapshot) || return 1
            jq -e '.row_count==0' <<<"$snapshot" >/dev/null || return 1
            printf '%s\n' "$doc" > "$RUN_DIR/callback-expiry-final.json"
            printf '%s\n' "$snapshot" > "$RUN_DIR/callback-expiry-both-down.json"
            return 0
        fi
        [[ $(jq -r '.status' <<<"$doc") != @(completed|cancelled|expired|failed) ]] || return 1
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
    if [[ $RETRY_EDIT_PENDING_LANGUAGE == true && -f $RUN_DIR/callback-language-edit.json ]]; then
        node "$retry_script_dir/test-fixtures/callback-language-edit.cjs" restore "$RUN_DIR" || {
            warn 'Conditional queue language restoration failed; retained private receipt, no forced overwrite'
            status=1
        }
    fi
    if [[ $RETRY_SHORT_CONFIRMATION_WINDOW == true && -f $RUN_DIR/callback-confirmation-deadline-edit.json ]]; then
        node "$retry_script_dir/test-fixtures/callback-language-edit.cjs" restore "$RUN_DIR" deadline || {
            warn 'Short confirmation-window restoration failed; inspect retained receipt, no blind overwrite'
            status=1
        }
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
    before=$(systemctl show kazoo-apps kazoo-ecallmgr kazoo-freeswitch kazoo-kamailio kazoo-live-test-agents -p Id -p LoadState -p ActiveState -p SubState -p MainPID -p NRestarts)
    printf '%s\n' "$before" > "$RUN_DIR/retry-service-before.txt"
    node "$retry_script_dir/test-fixtures/callback-retry-service-scope.cjs" "$RUN_DIR/retry-service-before.txt" \
        "$RETRY_ALLOW_PAUSED_MASTER_TEST_PHONES" "$RETRY_ALLOW_ABSENT_MASTER_TEST_PHONES" > "$RUN_DIR/retry-service-scope.json" || die 'Required service state failed strict scope validation'
    if [[ $RETRY_LANGUAGE_EXPLICIT == true ]]; then
        KAZOO_CALLBACK_TEST_LANGUAGE=$RETRY_LANGUAGE callback_fixture setup-retry
        KAZOO_CALLBACK_TEST_LANGUAGE=$RETRY_LANGUAGE callback_fixture verify
    else
        callback_fixture setup-retry
        callback_fixture verify
    fi
    if [[ $CALLBACK_TEST_TRANSPORT == internal ]]; then
        node "$retry_script_dir/test-fixtures/callback-internal-scenarios.cjs" preflight "$STATE_FILE"
        node "$retry_script_dir/probe-internal-callback.cjs" "$RETRY_ACCOUNT_ID" "${STATE[ACCEPTANCE_QUEUE_ID]}" 1001 \
            > "$RUN_DIR/internal-request-probe.txt" || die 'Internal native endpoint preflight failed'
    fi
    # verify_fixture reads the actual queue and fails unless callback is enabled,
    # entry_key is6, alternatives are false, and tenant/authority/routing match.
    jq -n --arg mode "$RETRY_REGISTRATION_MODE" --arg account "$RETRY_ACCOUNT_ID" \
        --arg language "${RETRY_LANGUAGE_ARGS[0]:-}" \
        '{registration_mode:$mode,account_id:$account,entry_key:"6",allow_alternate_number:false,fixture_verified:true}
         + (if $language=="" then {} else {language:$language} end)' \
        > "$RUN_DIR/retry-registration-policy.json"
    FIXTURE_CREATED=true
    STATUS_AGENT_MAX=${STATE[ACCEPTANCE_AGENT_COUNT]}
    agent_status logout 1 "$STATUS_AGENT_MAX"
    cores=$(core_count); since=$(date +%s)
    capture_log_baseline callback
    start_monitor callback
    if [[ $CALLBACK_TEST_TRANSPORT == internal ]]; then
        LOCAL_IP=$CARRIER_IP register_caller callback "$CARRIER_PORT" 600
    else
        register_caller callback "$CALLER_PORT" 600
    fi
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
    if [[ $RETRY_EDIT_PENDING_LANGUAGE == true ]]; then
        node "$retry_script_dir/test-fixtures/callback-language-edit.cjs" edit "$RUN_DIR" || die 'Pending callback language edit failed'
    elif [[ $RETRY_SHORT_CONFIRMATION_WINDOW == true ]]; then
        node "$retry_script_dir/test-fixtures/callback-language-edit.cjs" edit "$RUN_DIR" deadline || die 'Pending callback short confirmation-window edit failed'
    fi
    retry_stop_capture
    node "$retry_script_dir/test-fixtures/assert-callback-registration-audio.cjs" \
        "$RUN_DIR/retry-original.pcap" "$RETRY_REFERENCE" "$CALLBACK_ORIGINAL_CALL_ID" "$LOCAL_IP" "$CALLER_PORT" "$CALLBACK_ORIGINAL_MEDIA_PORT" "$RETRY_REGISTRATION_MODE" \
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
    if [[ $RETRY_WORKER_LOSS == true ]]; then
        local worker_call_id
        worker_call_id=$(jq -er '.caller.id' "$RUN_DIR/retry-first-attempt.json")
        timeout 20 escript "$retry_script_dir/test-fixtures/callback-worker-loss.escript" \
            --kill-fixture-worker "$CALLBACK_TICKET_ID" "$worker_call_id" \
            > "$RUN_DIR/retry-worker-loss.json" || die 'Worker fault boundary refused or unverified; never repeat blindly'
        log 'Exact active callback worker terminated; checking positive settlement and one retry'
    fi
    retry_wait_checked 'deliberately unanswered first returned attempt' "$RETRY_UNANSWERED_PID"
    assert_stats 'unanswered CANCEL transaction' "$RUN_DIR/retry-unanswered-stats.csv" 1
    retry_stop_capture
    retry_capture returned
    # Start the answering endpoint inside the configured 15s backoff window.
    if [[ $RETRY_CONFIRMATION_EXPIRY == true ]]; then
        retry_start_expiry_carrier
    elif [[ $RETRY_SHORT_CONFIRMATION_WINDOW == true ]]; then
        # EN prompt is4.331s. Six seconds after ACK is after the full prompt
        # but inside its three-second response window; waveform proof below
        # checks the actual times, not just this nominal schedule.
        start_returned_carrier 6000
    else
        start_returned_carrier
    fi
    retry_wait_backoff || die 'First unanswered attempt did not durably enter retry_wait with positive settlement'
    if [[ $RETRY_QUEUE_RESTART == true ]]; then
        retry_restart_queue_in_backoff || die 'Queue restart boundary failed; never blindly repeat a possibly completed restart'
    fi
    if [[ $RETRY_CONFIRMATION_EXPIRY == true ]]; then
        retry_wait_expiry || die 'No-confirmation retry did not cleanly expire without an agent leg'
        retry_wait_checked 'second returned caller without confirmation' "$CARRIER_PID"
        # Keep the agent listening throughout the timeout: an unexpected offer
        # must be detected, not hidden by removing its registered endpoint.
        stop_waiting_agents_checked callback 1
        assert_stats 'second returned caller without confirmation' "$RUN_DIR/callback-carrier-stats.csv" 1
        assert_agent_stats callback 1 1
        retry_stop_capture
        stop_monitor
        node "$retry_script_dir/test-fixtures/callback-confirmation-expiry.cjs" verify "$RUN_DIR" || die 'Native confirmation-expiry evidence failed'
    else
        retry_wait_bridge || die 'Second returned attempt did not durably complete an exact native bridge'
        log 'First attempt unanswered; durable retry_wait observed; second attempt completed with reciprocal native bridge'
        retry_wait_checked 'second returned carrier' "$CARRIER_PID"
        wait_agents_checked callback
        assert_stats 'second returned carrier' "$RUN_DIR/callback-carrier-stats.csv" 1
        assert_agent_stats callback 1 2
        retry_stop_capture
        stop_monitor
        local fault_args=()
        [[ $RETRY_WORKER_LOSS != true ]] || fault_args=(worker-loss)
        node "$retry_script_dir/test-fixtures/assert-callback-retry.cjs" "$RUN_DIR" "$RETRY_REGISTRATION_MODE" "$CALLBACK_TEST_TRANSPORT" "${RETRY_LANGUAGE_ARGS[@]}" "${fault_args[@]}" || die 'Strict unanswered/retry packet, media or timing gate failed'
        if [[ $RETRY_EDIT_PENDING_LANGUAGE == true ]]; then
            node "$retry_script_dir/test-fixtures/callback-language-edit.cjs" verify "$RUN_DIR" || die 'Returned callback did not prove admitted-language audio after queue edit'
        elif [[ $RETRY_SHORT_CONFIRMATION_WINDOW == true ]]; then
            node "$retry_script_dir/test-fixtures/callback-language-edit.cjs" verify "$RUN_DIR" deadline || die 'Returned callback did not prove full prompt and short response window'
        fi
    fi
    agent_status verify 1 1
    wait_agent_ready 1 || die 'Agent did not return ready after retry'
    systemctl show kazoo-apps kazoo-ecallmgr kazoo-freeswitch kazoo-kamailio kazoo-live-test-agents -p Id -p LoadState -p ActiveState -p SubState -p MainPID -p NRestarts \
        > "$RUN_DIR/retry-service-after.txt"
    [[ $(< "$RUN_DIR/retry-service-after.txt") == "$before" ]] || die 'A service changed during the retry diagnostic'
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
    node "$retry_script_dir/test-fixtures/callback-fixture-account.cjs" "$STATE_FILE" || die 'Protected callback fixture identity refused'
    ensure_sipp
    for file in create-callback-retry-scenarios.cjs assert-callback-retry.cjs assert-callback-registration-audio.cjs callback-confirmation-expiry.cjs; do
        node --check "$retry_script_dir/test-fixtures/$file"
    done
    if [[ $CALLBACK_PREPARE == true ]]; then log 'Retry sources and isolated state validated; no API writes or SIP traffic'; return; fi
    node "$retry_script_dir/test-fixtures/callback-fixture-account.cjs" --ensure-lock || die 'Cannot prepare protected shared acceptance lock'
    [[ -f /etc/kazoo/monitor-acceptance.lock && ! -L /etc/kazoo/monitor-acceptance.lock ]] || die 'Missing shared acceptance lock'
    exec 9<>/etc/kazoo/monitor-acceptance.lock
    flock -n 9 || die 'Another acceptance task owns the shared lock'
    create_run_dir
    trap retry_cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    sha256sum "$RETRY_REFERENCE" | awk '{print $1}' > "$RUN_DIR/retry-registration-reference-sha256.txt"
    cp -- "${RETRY_REFERENCE%/*}/reference-receipt.json" "$RUN_DIR/retry-registration-reference-receipt.json"
    node "$retry_script_dir/test-fixtures/create-callback-retry-scenarios.cjs" "$RUN_DIR" "$RETRY_REGISTRATION_MODE"
    if [[ $CALLBACK_TEST_TRANSPORT == internal ]]; then
        node "$retry_script_dir/test-fixtures/callback-internal-scenarios.cjs" unanswered "$RUN_DIR"
    fi
    retry_run
}

if [[ ${KAZOO_CALLBACK_RETRY_LIBRARY:-false} != true ]]; then main_retry "$@"; fi
