#!/usr/bin/env bash
# Explicitly released isolated2098 call: offer3/18/33, position11/26/41.
# No agent status edits, callback DTMF, outbound registration or PSTN route.
# shellcheck disable=SC1091,SC2034,SC2317
set -Eeuo pipefail
offer_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
KAZOO_CALLS_LIBRARY=true source "$offer_dir/test-kazoo-calls.sh"
INSTALL_DEPS=false
offer_fixture=$SCRIPT_DIR/test-fixtures/callback-offer-queue.cjs
offer_audio=$SCRIPT_DIR/test-fixtures/assert-callback-offer-audio.cjs
offer_scenario=$SCRIPT_DIR/test-fixtures/callback-offer-scenario.cjs
offer_capture_pid='' offer_call_id='' offer_queue_id='' offer_cleaning=false offer_fixture_started=false
offer_services=(couchdb rabbitmq-server haproxy nginx kazoo-apps kazoo-ecallmgr kazoo-freeswitch kazoo-kamailio kazoo-live-test-agents)
offer_empty() {
    /usr/local/freeswitch/bin/fs_cli -x 'show channels as json' |
        jq -e '.row_count==0 and (.rows==null or .rows==[])' >/dev/null
}
offer_service_snapshot() {
    local service
    for service in "${offer_services[@]}"; do
        systemctl is-active --quiet "$service" || return 1
        printf '%s\n' "$service"
        systemctl show "$service" -p MainPID -p NRestarts -p ActiveState
    done
}
offer_clear_owned() {
    local dump exists
    [[ -n $offer_call_id ]] || return 0
    exists=$(/usr/local/freeswitch/bin/fs_cli -x "uuid_exists $offer_call_id")
    [[ $exists != false ]] || return 0
    [[ $exists == true && -n $offer_queue_id ]] || return 1
    dump=$(/usr/local/freeswitch/bin/fs_cli -x "uuid_dump $offer_call_id json") || return 1
    jq -e --arg call "$offer_call_id" --arg account "${STATE[ACCEPTANCE_ACCOUNT_ID]}" \
        --arg device "${STATE[ACCEPTANCE_CALLER_DEVICE_ID]}" --arg user "${STATE[ACCEPTANCE_CALLER_USER_ID]}" '
        .["Unique-ID"]==$call and .variable_sip_call_id==$call and
        .["variable_ecallmgr_Account-ID"]==$account and .variable_sip_contact_host=="127.0.0.20" and
        (.variable_sip_contact_port|tonumber)==15064 and
        (.["variable_ecallmgr_Authorizing-ID"]==$device or .["variable_ecallmgr_Authorizing-ID"]==$user) and
        (.variable_bridge_to==null or .variable_bridge_to=="")' <<< "$dump" >/dev/null || return 1
    # A fresh exact queue-entry receipt provides the queue ownership proof.
    node "$offer_fixture" entry "$RUN_DIR" || return 1
    [[ $(/usr/local/freeswitch/bin/fs_cli -x "uuid_kill $offer_call_id NORMAL_CLEARING") == +OK ]] || return 1
}
offer_stop_capture() {
    [[ -n $offer_capture_pid ]] || return 0
    # Also drain on failure: -U flushes user-space writes, not pending packets
    # in the kernel capture buffer. Never infer teardown from truncated evidence.
    if kill -0 "$offer_capture_pid" 2>/dev/null; then sleep 2; fi
    kill -INT "$offer_capture_pid" 2>/dev/null || true
    wait "$offer_capture_pid" 2>/dev/null || true
    offer_capture_pid=
    [[ -f $RUN_DIR/offer-rtp.pcap && ! -L $RUN_DIR/offer-rtp.pcap && $(stat -c %h "$RUN_DIR/offer-rtp.pcap") == 1 ]] || return 1
    chown root:root "$RUN_DIR/offer-rtp.pcap"; chmod 600 "$RUN_DIR/offer-rtp.pcap"
}
offer_cleanup() {
    local result=$? pid
    [[ $offer_cleaning == false ]] || return; offer_cleaning=true
    for pid in "${ACTIVE_PIDS[@]}"; do
        [[ $pid == "$offer_capture_pid" ]] && continue
        if kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null || true; fi
        wait "$pid" 2>/dev/null || true
    done
    offer_clear_owned || result=1
    offer_stop_capture || result=1
    if [[ $CALLER_REGISTERED == true ]]; then best_effort_deregister_caller "$CALLER_PORT" offer-cleanup; fi
    if [[ $offer_fixture_started == true ]]; then
        offer_empty || result=1
        KAZOO_ACCEPTANCE_STATE_FILE=$STATE_FILE node "$offer_fixture" cleanup "$RUN_DIR" || result=1
    fi
    trap - EXIT; exit "$result"
}
offer_main() {
    local mode=${1:-} expected_md5='' live_md5 before_cores since log_errors file_errors caller_exit=0
    local gemini=false interval30=false hold_ms=46000
    local prerecorded_locale='' reference_index='' reference_sha=''
    local -a fixture_audio_options=()
    umask 077
    ((EUID==0)) || die 'Root required'
    [[ $mode == --prepare-only || $mode == --live ]] || die 'Use --prepare-only or --live --runtime-md5 HEX'
    shift
    while (($#)); do
        case $1 in
            --gemini) [[ $gemini == false && -z $prerecorded_locale ]] || die 'Duplicate Gemini option'; gemini=true; fixture_audio_options=(--gemini); shift ;;
            --gemini-30) [[ $gemini == false && -z $prerecorded_locale ]] || die 'Duplicate Gemini option'; gemini=true; interval30=true; hold_ms=76000; fixture_audio_options=(--gemini-30); shift ;;
            --prerecorded-locale)
                [[ $# -ge 2 && $gemini == false && -z $prerecorded_locale ]] || die 'Conflicting prerecorded locale'
                case $2 in en-us|he-il|fr-fr|es-es|ar-sa) prerecorded_locale=$2 ;; *) die 'Unsupported explicit locale' ;; esac
                shift 2 ;;
            --reference-index) [[ $# -ge 2 && -z $reference_index && $2 == /* ]] || die 'Invalid reference index'; reference_index=$2; shift 2 ;;
            --reference-index-sha256) [[ $# -ge 2 && -z $reference_sha && $2 =~ ^[a-f0-9]{64}$ ]] || die 'Invalid reference index pin'; reference_sha=$2; shift 2 ;;
            --runtime-md5) [[ $# -ge 2 && -z $expected_md5 && $2 =~ ^[a-f0-9]{32}$ ]] || die 'Invalid runtime MD5'; expected_md5=$2; shift 2 ;;
            *) die 'Unexpected options' ;;
        esac
    done
    if [[ -n $prerecorded_locale ]]; then
        [[ -n $reference_index && -n $reference_sha ]] || die 'Pinned all-five reference index required'
        hold_ms=86000
        fixture_audio_options=(--prerecorded-locale "$prerecorded_locale" --reference-index "$reference_index" --reference-index-sha256 "$reference_sha")
    else
        [[ -z $reference_index && -z $reference_sha ]] || die 'Reference options require explicit prerecorded locale'
    fi
    [[ $mode == --live || -z $expected_md5 ]] || die 'Runtime MD5 applies only to live mode'
    load_state; validate_state; resolve_local_ip; ensure_sipp
    [[ ${STATE[ACCEPTANCE_ACCOUNT_ID]} == 7807ad61761269a1ccec833dde63f621 && $LOCAL_IP == 127.0.0.20 ]] || die 'Wrong isolated local fixture'
    ip -o route get "${STATE[ACCEPTANCE_SIP_PROXY_HOST]}" | grep -Eq '(^| )local .* dev lo( |$)' || die 'SIP proxy must route locally'
    command -v sox >/dev/null; command -v tcpdump >/dev/null
    node --check "$offer_fixture"; node --check "$offer_audio"; node --check "$offer_scenario"
    if [[ -n $prerecorded_locale ]]; then
        node "$SCRIPT_DIR/test-fixtures/callback-prerecorded-reference.cjs" check "$reference_index" "$reference_sha" "$prerecorded_locale"
    fi
    if [[ $mode == --prepare-only ]]; then log 'PASS prepare only; no API writes, reference fetch or SIP traffic'; return; fi
    [[ -n $expected_md5 ]] || die 'Live run requires root-approved loaded scheduler module MD5'
    exec {offer_lock_fd}>/etc/kazoo/monitor-acceptance.lock
    flock -n "$offer_lock_fd" || die 'Acceptance lock is held'
    LIVE=true; create_run_dir; trap offer_cleanup EXIT; trap 'exit 130' INT TERM
    offer_empty || die 'Calls already active'
    offer_service_snapshot > "$RUN_DIR/offer-services-before.txt"
    live_md5=$(sup -e acdc_announcements module_info md5 | node -e '
        const s=require("fs").readFileSync(0,"utf8"),m=/^\s*<<([0-9,\s]+)>>\s*$/.exec(s);
        if(!m)process.exit(1);const b=m[1].split(",").map(x=>Number(x.trim()));
        if(b.length!==16||b.some(x=>!Number.isInteger(x)||x<0||x>255))process.exit(1);
        process.stdout.write(Buffer.from(b).toString("hex"));') || die 'Could not prove loaded scheduler MD5'
    [[ $live_md5 == "$expected_md5" ]] || die 'Loaded scheduler differs from approved code'
    node "$offer_scenario" "$RUN_DIR" "$SCENARIO_DIR/caller-to-queue.xml"
    before_cores=$(core_count); since=$(date +%s); capture_log_baseline offer
    offer_fixture_started=true
    KAZOO_ACCEPTANCE_STATE_FILE=$STATE_FILE node "$offer_fixture" setup "$RUN_DIR" "${fixture_audio_options[@]}"
    offer_queue_id=$(jq -er '.queue_id' "$RUN_DIR/offer-fixture.json")
    sup -e supervisor which_children acdc_announcements_sup > "$RUN_DIR/offer-workers-before.txt"
    STATE[ACCEPTANCE_QUEUE_EXTENSION]=2098
    register_caller offer "$CALLER_PORT"
    # Bounded8MiB capture buffer tolerates scheduling jitter under the shared
    # validation CPU cap. The zero-kernel-drop acceptance gate stays strict.
    tcpdump -q -n -s 0 -B 8192 -i any --immediate-mode -U -w "$RUN_DIR/offer-rtp.pcap" \
        'udp and host 127.0.0.20 and (port 15064 or port 47200)' \
        > "$RUN_DIR/offer-capture.log" 2>&1 &
    offer_capture_pid=$!; ACTIVE_PIDS+=("$offer_capture_pid"); sleep 1
    kill -0 "$offer_capture_pid" || die 'Capture did not start'
    write_caller_csv "$RUN_DIR/offer-input.csv" 1 1 "$hold_ms" "$hold_ms" 0
    sipp -ci 127.0.0.1 "${STATE[ACCEPTANCE_SIP_PROXY_HOST]}:${STATE[ACCEPTANCE_SIP_PROXY_PORT]}" \
        -sf "$RUN_DIR/offer-caller.xml" -inf "$RUN_DIR/offer-input.csv" \
        -i "$LOCAL_IP" -p "$CALLER_PORT" -mi "$LOCAL_IP" -mp 47200 -min_rtp_port 47200 -max_rtp_port 47203 \
        -m 1 -l 1 -r 1 -rp 1000 -nostdin -aa -timeout 105s -timeout_error \
        -trace_stat -fd 1s -stf "$RUN_DIR/offer-caller-stats.csv" > "$RUN_DIR/offer-caller.log" 2>&1 &
    CALLER_PID=$!; ACTIVE_PIDS+=("$CALLER_PID"); offer_call_id="1-${CALLER_PID}@${LOCAL_IP}"
    jq -n --arg call "$offer_call_id" --arg queue "$offer_queue_id" --arg account "${STATE[ACCEPTANCE_ACCOUNT_ID]}" \
        '{call_id:$call,queue_id:$queue,account:$account,ip:"127.0.0.20",sip_port:15064,media_port:47200}' > "$RUN_DIR/offer-call.json"
    wait_answered_calls "$RUN_DIR/offer-caller-stats.csv" 1 || die 'Caller was not answered'
    sup -e supervisor which_children acdc_announcements_sup > "$RUN_DIR/offer-workers-during.txt"
    if [[ -n $prerecorded_locale ]]; then
        log "Owned2098 $prerecorded_locale: callback offer30/60, ordered position1 at45/75; wait-time disabled/unverified; no DTMF"
    elif [[ $interval30 == true ]]; then
        log 'Owned2098 Gemini offer at30/60 seconds; silent hold before29s, generic interval15 remains separate; no position/DTMF proof'
    elif [[ $gemini == true ]]; then
        log 'Owned2098 Gemini offer-only: complete >5s phrase at3/18/33, silence hold, no position/DTMF proof'
    else
        log 'Owned2098 caller waits46seconds: offer3/18/33, position11/26/41; no DTMF is sent'
    fi
    wait "$CALLER_PID" || caller_exit=$?
    printf '%s\n' "$caller_exit" > "$RUN_DIR/offer-caller-exit-code.txt"
    ((caller_exit==0)) || die "Offer SIPp caller failed with exit status $caller_exit"
    assert_stats 'offer caller' "$RUN_DIR/offer-caller-stats.csv" 1
    ! grep -Eiq 'Could not bind|rtp.*(error|fail)|stream.*(error|fail)' "$RUN_DIR/offer-caller.log" || die 'SIPp media failure'
    offer_stop_capture; offer_empty || die 'Channels remain after normal BYE'
    sup -e supervisor which_children acdc_announcements_sup > "$RUN_DIR/offer-workers-after.txt"
    node "$offer_fixture" entry "$RUN_DIR"
    node "$offer_audio" "$RUN_DIR" | tee "$RUN_DIR/offer-audio-evidence.json"
    node - "$RUN_DIR" <<'NODE'
const fs=require('fs'),assert=require('assert/strict'),run=process.argv[2];
const workers=stage=>new Set(fs.readFileSync(run+'/offer-workers-'+stage+'.txt','utf8').match(/<\d+\.\d+\.\d+>/g)||[]);
const before=workers('before'),during=workers('during'),after=workers('after'),added=[...during].filter(x=>!before.has(x));
assert.equal(added.length,1,'Expected exactly one producer');assert(!after.has(added[0]),'Owned producer remains');
assert.deepEqual([...after].sort(),[...before].sort(),'Other producer inventory changed');
NODE
    offer_service_snapshot > "$RUN_DIR/offer-services-after.txt"
    cmp -s "$RUN_DIR/offer-services-before.txt" "$RUN_DIR/offer-services-after.txt" || die 'Service PID/restart state changed'
    log_errors=$(journalctl -q --since "@$since" --no-pager -o json -u kazoo-apps -u kazoo-ecallmgr -u kazoo-freeswitch -u kazoo-kamailio |
        jq -r '.MESSAGE|if type=="array" then implode elif type=="string" then . else empty end' | count_journal_error_messages)
    file_errors=$(new_error_log_matches offer)
    [[ $(core_count) == "$before_cores" ]] || die 'New core dump'
    ((log_errors==0 && file_errors==0)) || die "Fresh errors remain:$log_errors/$file_errors"
    log "PASS functional media, clocks and runtime gates; conditional fixture cleanup still required:$RUN_DIR"
}
offer_main "$@"
