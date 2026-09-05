#!/usr/bin/env bash
# End-to-end ACDC virtual-callback acceptance using only the isolated tenant and
# the account-local SIP carrier created by test-acdc-callback-fixture.sh.
# shellcheck disable=SC1091,SC2034,SC2317
set -Eeuo pipefail

callback_test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
KAZOO_CALLS_LIBRARY=true source "$callback_test_dir/test-kazoo-calls.sh"

readonly CALLBACK_FIXTURE_HELPER=${callback_test_dir}/test-acdc-callback-fixture.sh
readonly CALLBACK_NUMBER=+12025550101
readonly OUTBOUND_CALLER_ID=+12025550100
readonly CALLBACK_ENTRY_KEY=6
readonly CARRIER_IP=127.0.0.30
readonly CARRIER_PORT=16060
readonly CARRIER_MEDIA_PORT=44000
readonly CALLBACK_ORIGINAL_MEDIA_PORT=43000
readonly SENTINEL_MEDIA_PORT=43010
readonly CALLBACK_SENTINEL_HOLD_MS=90000
readonly CALLBACK_CARRIER_CONFIRM_DELAY_MS=8000
readonly CALLBACK_BRIDGE_HOLD_MS=30000

CALLBACK_LIVE=false
CALLBACK_PREPARE=false
KEEP_FIXTURE=false
FIXTURE_CREATED=false
CALLBACK_CLEANING=false
CALLBACK_ORIGINAL_PID=
CARRIER_PID=
SENTINEL_PID=
CALLBACK_ORIGINAL_CALL_ID=
CALLBACK_TICKET_ID=
CALLBACK_REGISTRATION_EVIDENCE=
CALLBACK_CONFIRMING_OBSERVED=false

callback_usage() {
    cat <<'EOF'
Usage: sudo ./scripts/test-acdc-callback-calls.sh --prepare-only
       sudo ./scripts/test-acdc-callback-calls.sh --live [--keep-fixture]

--prepare-only  Validate protected tenant state, SIPp, scenarios, and helper
                syntax without API changes, SIP traffic, or agent mutations.
--live          Create the temporary local fixture and run one real callback:
                queued caller presses 6, confirms the same owned number, the
                original leg ends, the local carrier answers the returned call,
                presses 1, and ACDC bridges agent 1002 with bidirectional RTP.
--keep-fixture  Preserve the marked local resource/numbers/queue config for
                focused diagnosis. The default always restores and removes it.

The later sentinel caller remains queued while the callback is bridged. This
proves the virtual callback retained its original ordering rather than rejoining
at the tail. All telephone numbers are within +1-202-555-0100..0199, and the
only carrier gateway is 127.0.0.30:16060. No PSTN destination is reachable.
EOF
}

parse_callback_args() {
    while (($#)); do
        case $1 in
            --prepare-only) CALLBACK_PREPARE=true ;;
            --live) CALLBACK_LIVE=true ;;
            --keep-fixture) KEEP_FIXTURE=true ;;
            --config) (($# >= 2)) || die '--config requires a file'; STATE_FILE=$2; shift ;;
            --run-root) (($# >= 2)) || die '--run-root requires a directory'; RUN_ROOT=$2; shift ;;
            -h|--help) callback_usage; exit 0 ;;
            *) die "Unknown callback test option: $1" ;;
        esac
        shift
    done
    [[ $CALLBACK_PREPARE == true || $CALLBACK_LIVE == true ]] || die 'Choose --prepare-only or --live'
    [[ $CALLBACK_PREPARE != true || $CALLBACK_LIVE != true ]] || die '--prepare-only and --live are mutually exclusive'
    [[ $KEEP_FIXTURE != true || $CALLBACK_LIVE == true ]] || die '--keep-fixture requires --live'
}

validate_callback_scenarios() {
    local scratch request_input returned_input item scenario input port output
    command -v node >/dev/null || die 'Node.js is required for the callback packet-evidence gate'
    node --check "$callback_test_dir/test-fixtures/assert-callback-confirmation-pcap.cjs"
    bash -n "$CALLBACK_FIXTURE_HELPER"
    shellcheck -x "$CALLBACK_FIXTURE_HELPER"
    scratch=$(mktemp -d /tmp/kazoo-callback-sipp-parse.XXXXXX)
    chmod 700 "$scratch"
    request_input=$scratch/request.csv
    returned_input=$scratch/returned.csv
    printf 'SEQUENTIAL\ndummy;[authentication username=dummy password=dummy];example.invalid;2000;+12025550101;6\n' > "$request_input"
    printf 'SEQUENTIAL\n+12025550101;3500;15000\n' > "$returned_input"
    chmod 600 "$request_input" "$returned_input"
    for item in 'callback-request.xml request.csv 15064' 'callback-returned.xml returned.csv 16060'; do
        read -r scenario input port <<<"$item"
        output=$scratch/$scenario.out
        timeout 5 sipp 127.0.0.1:9 -sf "$SCENARIO_DIR/$scenario" -inf "$scratch/$input" \
            -i 127.0.0.30 -p "$port" -mi 127.0.0.30 -mp 45000 -m 0 -nostdin >"$output" 2>&1 || true
        ! grep -Eq 'parse error|Unable to load|Unknown element|Variable .* referenced.*(not declared|[01] times)' "$output" || \
            die "SIPp rejected callback scenario $scenario"
    done
    find "$scratch" -type f -delete
    rmdir "$scratch"
}

write_callback_request_csv() {
    local file=$1 username password
    username=${STATE[ACCEPTANCE_CALLER_SIP_USERNAME]}
    password=${STATE[ACCEPTANCE_CALLER_SIP_PASSWORD]}
    printf 'SEQUENTIAL\n%s;%s;%s;%s;%s;%s\n' "$username" \
        "$(auth_keyword "$username" "$password")" "${STATE[ACCEPTANCE_REALM]}" \
        "${STATE[ACCEPTANCE_QUEUE_EXTENSION]}" "$CALLBACK_NUMBER" "$CALLBACK_ENTRY_KEY" > "$file"
    chmod 600 "$file"
}

write_returned_carrier_csv() {
    local file=$1
    printf 'SEQUENTIAL\n%s;%s;%s\n' "$CALLBACK_NUMBER" \
        "$CALLBACK_CARRIER_CONFIRM_DELAY_MS" "$CALLBACK_BRIDGE_HOLD_MS" > "$file"
    chmod 600 "$file"
}

start_returned_carrier() {
    local csv=$RUN_DIR/callback-carrier-input.csv stats=$RUN_DIR/callback-carrier-stats.csv
    local output=$RUN_DIR/callback-carrier.log
    write_returned_carrier_csv "$csv"
    sipp -sf "$SCENARIO_DIR/callback-returned.xml" -inf "$csv" \
        -i "$CARRIER_IP" -p "$CARRIER_PORT" -mi "$CARRIER_IP" -mp "$CARRIER_MEDIA_PORT" \
        -min_rtp_port "$CARRIER_MEDIA_PORT" -max_rtp_port "$((CARRIER_MEDIA_PORT + 3))" \
        -rtp_echo -m 1 -l 1 -nostdin -aa -timeout 120s -timeout_error \
        -trace_stat -fd 1s -stf "$stats" >"$output" 2>&1 &
    CARRIER_PID=$!
    ACTIVE_PIDS+=("$CARRIER_PID")
    sleep 1
    kill -0 "$CARRIER_PID" 2>/dev/null || die 'Local simulated carrier SIPp exited before callback origination'
}

start_callback_request() {
    local csv=$RUN_DIR/callback-original-input.csv stats=$RUN_DIR/callback-original-stats.csv
    local output=$RUN_DIR/callback-original.log
    write_callback_request_csv "$csv"
    sipp "${STATE[ACCEPTANCE_SIP_PROXY_HOST]}:${STATE[ACCEPTANCE_SIP_PROXY_PORT]}" \
        -sf "$SCENARIO_DIR/callback-request.xml" -inf "$csv" -i "$LOCAL_IP" -p "$CALLER_PORT" \
        -mi "$LOCAL_IP" -mp "$CALLBACK_ORIGINAL_MEDIA_PORT" -min_rtp_port "$CALLBACK_ORIGINAL_MEDIA_PORT" \
        -max_rtp_port "$((CALLBACK_ORIGINAL_MEDIA_PORT + 3))" -rtp_echo \
        -m 1 -l 1 -r 1 -rp 1000 -nostdin -aa -timeout 75s -timeout_error \
        -trace_stat -fd 1s -stf "$stats" >"$output" 2>&1 &
    CALLBACK_ORIGINAL_PID=$!
    CALLBACK_ORIGINAL_CALL_ID="1-${CALLBACK_ORIGINAL_PID}@${LOCAL_IP}"
    ACTIVE_PIDS+=("$CALLBACK_ORIGINAL_PID")
}

start_sentinel_caller() {
    local csv=$RUN_DIR/callback-sentinel-input.csv stats=$RUN_DIR/callback-sentinel-stats.csv
    local output=$RUN_DIR/callback-sentinel.log
    write_caller_csv "$csv" 1 1 "$CALLBACK_SENTINEL_HOLD_MS" "$CALLBACK_SENTINEL_HOLD_MS" 0
    sipp "${STATE[ACCEPTANCE_SIP_PROXY_HOST]}:${STATE[ACCEPTANCE_SIP_PROXY_PORT]}" \
        -sf "$SCENARIO_DIR/caller-to-queue.xml" -inf "$csv" -i "$LOCAL_IP" -p "$CALLER_PORT" \
        -mi "$LOCAL_IP" -mp "$SENTINEL_MEDIA_PORT" -min_rtp_port "$SENTINEL_MEDIA_PORT" -max_rtp_port "$((SENTINEL_MEDIA_PORT + 3))" \
        -rtp_echo -m 1 -l 1 -r 1 -rp 1000 -nostdin -aa -timeout 150s -timeout_error \
        -trace_stat -fd 1s -stf "$stats" >"$output" 2>&1 &
    SENTINEL_PID=$!
    ACTIVE_PIDS+=("$SENTINEL_PID")
}

wait_callback_bridge() {
    local deadline=$((SECONDS + 75)) document callback_status agent_current caller_id agent_id caller agent sentinel
    while ((SECONDS < deadline)); do
        kill -0 "$CARRIER_PID" 2>/dev/null || return 1
        document=$(callback_document) || return 1
        callback_status=$(jq -r '.status' <<<"$document")
        agent_current=$(stat_value "$RUN_DIR/callback-agent-1-stats.csv" 'CurrentCall' 2>/dev/null || printf 0)
        if [[ $callback_status == confirming ]] && ((agent_current == 0)); then
            CALLBACK_CONFIRMING_OBSERVED=true
        fi
        if [[ $callback_status == completed ]]; then
            [[ $CALLBACK_CONFIRMING_OBSERVED == true ]] || die 'No returned-caller confirmation wait was observed'
            caller_id=$(jq -er '.caller_call_id | select(type=="string" and length>0)' <<<"$document") || return 1
            agent_id=$(jq -er '.agent_call_id | select(type=="string" and length>0)' <<<"$document") || return 1
            caller=$(callback_channel "$caller_id") || return 1
            agent=$(callback_channel "$agent_id") || return 1
            sentinel=$(callback_channel "1-${SENTINEL_PID}@${LOCAL_IP}") || return 1
            jq -e --arg caller "$caller_id" --arg agent "$agent_id" --arg account "${STATE[ACCEPTANCE_ACCOUNT_ID]}" \
                '.id==$caller and .account==$account and .bridge_to==$agent' <<<"$caller" >/dev/null || return 1
            jq -e --arg caller "$caller_id" --arg agent "$agent_id" --arg account "${STATE[ACCEPTANCE_ACCOUNT_ID]}" \
                '.id==$agent and .account==$account and .bridge_to==$caller' <<<"$agent" >/dev/null || return 1
            jq -e --arg account "${STATE[ACCEPTANCE_ACCOUNT_ID]}" \
                '.account==$account and (.bridge_to==null or .bridge_to=="")' <<<"$sentinel" >/dev/null || \
                die 'Later sentinel was bridged or not present in the acceptance tenant'
            jq -e --argjson before "$CALLBACK_REGISTRATION_EVIDENCE" \
                '.id==$before.id and .enqueued_at==$before.enqueued_at and
                 .enqueue_sequence==$before.enqueue_sequence and .attempts==1 and
                 .reconciliation_required!=true' <<<"$document" >/dev/null || \
                die 'Callback identity/order changed or required reconciliation'
            jq -n --argjson callback "$document" --argjson caller "$caller" --argjson agent "$agent" \
                --argjson sentinel "$sentinel" '{callback:$callback,caller:$caller,agent:$agent,sentinel:$sentinel}' \
                > "$RUN_DIR/callback-bridge-evidence.json"
            return 0
        fi
        [[ $callback_status != failed && $callback_status != cancelled && $callback_status != expired && $callback_status != cancelling ]] || return 1
        sleep 1
    done
    return 1
}

callback_document() {
    callback_fixture evidence | jq -e --arg call "$CALLBACK_ORIGINAL_CALL_ID" \
        '[.[] | select(.original_call_id==$call)] | if length==1 then .[0] else error("expected exactly one callback") end'
}

callback_fixture() {
    KAZOO_ACCEPTANCE_STATE_FILE=$STATE_FILE "$CALLBACK_FIXTURE_HELPER" "$@"
}

callback_channel() {
    local id=$1 raw
    [[ $id =~ ^[A-Za-z0-9@._:-]+$ ]] || return 1
    raw=$(timeout 5 /usr/local/freeswitch/bin/fs_cli -x "uuid_dump $id json" 2>/dev/null) || return 1
    # Raw channel variables can contain internal credentials; only this fixed
    # projection is ever retained or emitted by the harness.
    jq -e --arg id "$id" 'select(.["Unique-ID"]==$id) |
        {id:.["Unique-ID"],account:.["variable_ecallmgr_Account-ID"],bridge_to:.variable_bridge_to}' <<<"$raw"
}

wait_callback_registered() {
    local deadline=$((SECONDS + 15)) document channels
    while ((SECONDS < deadline)); do
        if document=$(callback_document 2>/dev/null) && jq -e '.status=="queued" and .attempts==0' <<<"$document" >/dev/null; then
            channels=$(timeout 5 /usr/local/freeswitch/bin/fs_cli -x 'show channels as json' 2>/dev/null) || return 1
            jq -e --arg call "$CALLBACK_ORIGINAL_CALL_ID" \
                -f "$callback_test_dir/test-fixtures/assert-channel-absent.jq" <<<"$channels" >/dev/null || return 1
            CALLBACK_REGISTRATION_EVIDENCE=$document
            CALLBACK_TICKET_ID=$(jq -r '.id' <<<"$document")
            printf '%s\n' "$document" > "$RUN_DIR/callback-registration-evidence.json"
            return 0
        fi
        sleep 1
    done
    return 1
}

start_callback_capture() {
    RTP_PCAP=$RUN_DIR/callback-rtp.pcap
    RTP_CAPTURE_LOG=$RUN_DIR/callback-rtp-capture.log
    tcpdump -q -n -i any -U -w "$RTP_PCAP" \
        'udp and (portrange 40000-44998 or dst port 15100)' >"$RTP_CAPTURE_LOG" 2>&1 &
    RTP_CAPTURE_PID=$!
    ACTIVE_PIDS+=("$RTP_CAPTURE_PID")
    sleep 1
    kill -0 "$RTP_CAPTURE_PID" 2>/dev/null || die 'Callback RTP/SIP evidence capture failed'
}

assert_callback_rtp() {
    local name port incoming outgoing
    [[ -s $RTP_PCAP ]] || die 'Callback test captured no RTP'
    for entry in "original:$CALLBACK_ORIGINAL_MEDIA_PORT" "carrier:$CARRIER_MEDIA_PORT" "agent:$AGENT_MEDIA_MIN"; do
        name=${entry%%:*}; port=${entry#*:}
        incoming=$(pcap_count "udp dst port $port")
        outgoing=$(pcap_count "udp src port $port")
        ((incoming >= 10 && outgoing >= 10)) || \
            die "Callback $name RTP was not bidirectional (in=$incoming out=$outgoing)"
    done
    printf 'leg\trtp_port\noriginal\t%s\nreturned_carrier\t%s\nagent\t%s\n' \
        "$CALLBACK_ORIGINAL_MEDIA_PORT" "$CARRIER_MEDIA_PORT" "$AGENT_MEDIA_MIN" > "$RUN_DIR/callback-rtp.tsv"
    chmod 600 "$RUN_DIR/callback-rtp.tsv"
}

run_callback_acceptance() {
    local cores_before since
    STATUS_AGENT_MAX=${STATE[ACCEPTANCE_AGENT_COUNT]}
    agent_status logout 1 "$STATUS_AGENT_MAX"
    FIXTURE_CREATED=true
    callback_fixture setup
    callback_fixture verify
    cores_before=$(core_count)
    since=$(date +%s)
    capture_log_baseline callback
    start_monitor callback
    start_callback_capture

    register_caller callback "$CALLER_PORT" 600
    register_agents callback 1 600
    start_returned_carrier
    start_callback_request
    MAIN_CALLER_PID=$CALLBACK_ORIGINAL_PID
    wait_checked 'callback original registration/menu' "$CALLBACK_ORIGINAL_PID"
    assert_stats 'callback original registration/menu' "$RUN_DIR/callback-original-stats.csv" 1
    wait_callback_registered || die 'Original hangup did not leave exactly one durable queued callback'

    # Join an ordinary caller only after durable callback registration. It is
    # therefore behind the callback's original queue position.
    start_sentinel_caller
    MAIN_CALLER_PID=$SENTINEL_PID
    wait_answered_calls "$RUN_DIR/callback-sentinel-stats.csv" 1 || \
        die 'Later sentinel caller was not accepted into the queue'
    start_agent_uas callback 1 0
    agent_status login 1 1
    wait_callback_bridge || die 'Returned caller and agent did not bridge ahead of the later sentinel'
    wait_checked 'returned local carrier' "$CARRIER_PID"
    wait_agents_checked callback
    assert_stats 'returned local carrier' "$RUN_DIR/callback-carrier-stats.csv" 1
    assert_agent_stats callback 1 1

    # The sentinel leaves normally after its bounded queue hold; no second
    # agent endpoint is available, so it must not increment the agent result.
    wait_checked 'later queue sentinel' "$SENTINEL_PID"
    assert_stats 'later queue sentinel' "$RUN_DIR/callback-sentinel-stats.csv" 1
    stop_rtp_capture
    stop_monitor
    assert_callback_rtp
    node "$callback_test_dir/test-fixtures/assert-callback-confirmation-pcap.cjs" "$RTP_PCAP" \
        > "$RUN_DIR/callback-confirmation-evidence.json" || die 'Packet evidence failed caller-confirmation-before-agent gate'
    agent_status verify 1 1
    wait_agent_ready 1 || die 'Agent did not return ready after callback bridge'
    record_stage callback 1 2 "$RUN_DIR/callback-original-stats.csv" 1 "$cores_before" "$since" \
        "$RUN_DIR/callback-sentinel-stats.csv"
    log "Callback PASS: same-number registration, original hangup, local returned INVITE, DTMF 1, preserved order, native agent bridge, and RTP; $RUN_DIR"
}

callback_cleanup() {
    local exit_code=$? pid callback_settled=true
    [[ $CALLBACK_CLEANING == false ]] || return
    CALLBACK_CLEANING=true
    for pid in "${ACTIVE_PIDS[@]}"; do
        if [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null || true; fi
    done
    for pid in "${ACTIVE_PIDS[@]}"; do
        if [[ $pid =~ ^[0-9]+$ ]]; then wait "$pid" 2>/dev/null || true; fi
    done
    best_effort_clear_acceptance_calls
    if [[ $CALLBACK_LIVE == true && -n $RUN_DIR ]]; then
        ((AGENTS_REGISTERED == 0)) || best_effort_deregister_agents "$AGENTS_REGISTERED"
        [[ $CALLER_REGISTERED != true ]] || best_effort_deregister_caller "$CALLER_PORT" callback-cleanup-caller
        ((STATUS_AGENT_MAX == 0)) || agent_status logout 1 "$STATUS_AGENT_MAX" >/dev/null 2>&1 || true
        if [[ $FIXTURE_CREATED == true && -n $CALLBACK_ORIGINAL_CALL_ID ]]; then
            callback_fixture cancel-original "$CALLBACK_ORIGINAL_CALL_ID" >/dev/null 2>&1 || callback_settled=false
        fi
        if [[ $FIXTURE_CREATED == true && $KEEP_FIXTURE != true ]]; then
            if [[ $callback_settled == true ]]; then
                callback_fixture cleanup >/dev/null 2>&1 || \
                    warn "Fixture cleanup needs attention: $CALLBACK_FIXTURE_HELPER cleanup"
            else
                warn 'Callback cancellation has unresolved settlement; retained owned fixture for recovery, not another test run'
            fi
        fi
    fi
    find "${RUN_DIR:-/nonexistent}" -maxdepth 1 -type f -name '*-input.csv' -delete 2>/dev/null || true
    return "$exit_code"
}

main_callback() {
    umask 077
    ((EUID == 0)) || die 'Run as root to protect credentials and callback diagnostics'
    parse_callback_args "$@"
    load_state
    validate_state
    ensure_sipp
    validate_callback_scenarios
    resolve_local_ip
    if [[ $CALLBACK_PREPARE == true ]]; then
        log 'PASS: callback fixture helper and SIPp scenarios are ready; no API mutation or SIP traffic sent'
        return 0
    fi
    create_run_dir
    trap callback_cleanup EXIT INT TERM
    run_callback_acceptance
}

main_callback "$@"
