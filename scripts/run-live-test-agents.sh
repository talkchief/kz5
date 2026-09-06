#!/usr/bin/env bash
# Persistent, receive-only SIP test phones for explicitly owned MASTER fixtures.
# Not a traffic generator: this service never sends an INVITE or a PSTN call.
set -Eeuo pipefail
umask 077

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
readonly SCRIPT_DIR
readonly STATE_FILE=/etc/kazoo/live-test-agents.json
readonly RUNTIME_DIR=/run/kazoo-live-test-agents
readonly OWNER=kazoo5-master-live-test-agents
readonly ACCOUNT_ID=302ae5a70c403124f764cbc54229cfcd
readonly PHONE_IP=127.0.0.40
readonly SIP_BASE=17100
readonly RTP_BASE=46000
readonly COUNT=30
readonly HELPER="$SCRIPT_DIR/provision-live-test-agents.cjs"
readonly FS_CLI=/usr/local/freeswitch/bin/fs_cli
readonly PHONE_PROCESS_HELPER="$SCRIPT_DIR/phone-process-identity.py"
readonly SUPERVISOR_PID=$BASHPID
MODE=dry-run
STATE=
RUN_STARTED=false
OWNERSHIP_VERIFIED=true
PHONE_OWNERSHIP_DIAGNOSTIC=not_checked
PHONE_HEALTH_STATUS=
REGISTERED_PHONES=0
CLEANING=false
declare -a PHONE_PIDS=()
declare -a PHONE_START_TICKS=()
PHONE_PROC_STAT=
declare -a STAT_COLUMNS=()
declare -a PHONE_WARNED=()

log() { printf '[kazoo-live-test-agents] %s\n' "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }

protected_file() {
    [[ -f $1 && ! -L $1 && $(stat -Lc '%u:%g:%a' -- "$1") == 0:0:600 ]] ||
        die 'Manifest must be a regular root:root 0600 file'
}

load_state() {
    protected_file "$STATE_FILE"
    STATE=$(<"$STATE_FILE")
    validate_state || die 'Invalid or out-of-scope live-agent manifest'
}

validate_state() {
    jq -e --arg owner "$OWNER" --arg account "$ACCOUNT_ID" '
      .schema_version == 1 and .owner == $owner and .account_id == $account and
      (.deployment_id | test("^[a-f0-9]{32}$")) and
      (.realm | test("^[A-Za-z0-9.-]+$")) and
      (.queue_id | test("^[a-f0-9]{32}$")) and .queue_extension == "2000" and
      .api_base == "http://127.0.0.1:8000/v2" and
      .credentials_file == "/etc/kazoo/installer-secrets.env" and
      (.sip_proxy_host | test("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$")) and
      .sip_proxy_port == 5060 and .sip_transport == "udp" and
      (.protected_microsip_device_id | test("^[a-f0-9]{32}$")) and
      (.agents | length == 30) and
      ([.agents[].index] | sort == [range(1;31)]) and
      ([.agents[].user_id] | unique | length == 30) and
      ([.agents[].device_id] | unique | length == 30) and
      ([.agents[].sip_username] | unique | length == 30) and
      (.protected_microsip_device_id as $protected | all(.agents[];
        (.user_id | test("^[a-f0-9]{32}$")) and
        (.device_id | test("^[a-f0-9]{32}$")) and .device_id != $protected and
        .extension == ((1001 + .index) | tostring) and
        .sip_username == ("livetest" + .extension) and
        (.sip_password | test("^[A-Za-z0-9._~-]{16,128}$"))))
    ' <<<"$STATE" >/dev/null 2>&1
}

prepare_runtime() {
    [[ ! -L $RUNTIME_DIR ]] || die 'Runtime directory cannot be a symlink'
    install -d -o root -g root -m 0700 "$RUNTIME_DIR"
    [[ $(stat -Lc '%u:%g:%a' "$RUNTIME_DIR") == 0:0:700 ]] || die 'Unsafe runtime directory'
    exec 9>"$RUNTIME_DIR/supervisor.lock"
    flock -n 9 || die 'Live agent supervisor is already running'
}

owned_helper() {
    local operation=$1 output code
    [[ -f $HELPER && ! -L $HELPER ]] || return 1
    if [[ $operation == verify_phones ]]; then
        if output=$(timeout 90 node "$HELPER" --verify-phones-only 2>&1); then
            PHONE_OWNERSHIP_DIAGNOSTIC=verified
            return 0
        fi
        PHONE_OWNERSHIP_DIAGNOSTIC=api_or_state_verification_failed
        # Only fixed diagnostic codes can reach journal/systemd status. Never
        # echo arbitrary helper output, API bodies, credentials or shell state.
        for code in missing_or_duplicate_identity owned_user_mismatch owned_device_mismatch protected_microsip_mismatch; do
            if [[ $output == *"PHONE_OWNERSHIP: $code"* ]]; then PHONE_OWNERSHIP_DIAGNOSTIC=$code; break; fi
        done
        return 1
    elif [[ $operation == verify ]]; then
        # Cleanup retains its original complete queue/route/roster gate.
        # Phone-registration authority must never widen cleanup authority.
        timeout 90 node "$HELPER" --verify-only >/dev/null 2>&1
    else
        timeout 90 node "$HELPER" --agent-status "$operation" >/dev/null 2>&1
    fi
}

dependencies_ready() {
    local response
    # GET cannot execute user_auth's PUT handler. Its exact method rejection
    # proves Crossbar has registered this route; it does not authenticate.
    response=$(curl -q --noproxy '*' --proto '=http' --connect-timeout 2 --max-time 3 \
        --silent --output /dev/null --write-out '%{http_code}' --request GET \
        http://127.0.0.1:8000/v2/user_auth 2>/dev/null) || return 1
    [[ $response == 405 ]] || return 1
    response=$(timeout 3 kamcmd core.version 2>/dev/null) || return 1
    [[ $response == *kamailio* ]] || return 1
    response=$(timeout 3 "$FS_CLI" -x 'module_exists mod_kazoo' 2>/dev/null) || return 1
    [[ $response == true ]]
}

wait_for_dependencies() {
    local deadline=$((SECONDS + 240))
    log 'Waiting up to 240 seconds for local Crossbar, registrar and FreeSWITCH read probes'
    # The loop contains no authentication, ownership helper, SIP REGISTER,
    # provisioner/status operation or cleanup. Ownership is checked once later.
    while ((SECONDS + 9 <= deadline)); do
        if dependencies_ready; then return 0; fi
        ((SECONDS + 5 < deadline)) || break
        sleep 5
    done
    log 'Local dependencies did not become ready within the bounded read-only startup wait' >&2
    return 1
}

write_input() {
    local index=$1 expires=$2 path=$3
    jq -r --argjson index "$index" --argjson port "$((SIP_BASE + index - 1))" --argjson expires "$expires" '
      .realm as $realm | .agents[] | select(.index == $index) |
      "SEQUENTIAL\n" + .sip_username + ";[authentication username=" + .sip_username +
      " password=" + .sip_password + "];" + $realm + ";" + ($port | tostring) + ";" + ($expires | tostring)
    ' <<<"$STATE" >"$path"
    chmod 600 "$path"
}

contact_present() {
    local index=$1 username realm result contact
    username=$(jq -r --argjson i "$index" '.agents[] | select(.index == $i) | .sip_username' <<<"$STATE")
    realm=$(jq -r '.realm' <<<"$STATE")
    result=$(timeout 5 kamcmd ul.lookup location "$username@$realm" 2>/dev/null) || return 1
    contact="sip:$username@$PHONE_IP:$((SIP_BASE + index - 1))"
    awk -v expected="$contact" '$1=="Address:" || $1=="Contact:" {split($2, parts, ";"); if(parts[1]==expected) found=1} END {exit !found}' <<<"$result"
}

failed_registrations() {
    local index=$1 path="$RUNTIME_DIR/agent-$1-stats.csv" column value
    [[ -s $path ]] || return 1
    column=${STAT_COLUMNS[$index]:-}
    if [[ -z $column ]]; then
        column=$(awk -F';' 'NR==1 {for(i=1;i<=NF;i++) if($i=="FailedCall(C)") {print i; exit}}' "$path")
        [[ $column =~ ^[0-9]+$ ]] || return 1
        STAT_COLUMNS[index]=$column
    fi
    value=$(awk -F';' -v column="$column" 'NF>column && $column ~ /^[0-9]+$/ {value=$column} END {print value+0}' "$path")
    ((value > 0))
}

read_phone_stat() {
    PHONE_PROC_STAT=
    [[ $1 =~ ^[1-9][0-9]*$ && $1 != 1 ]] || return 1
    IFS= read -r PHONE_PROC_STAT <"/proc/$1/stat" 2>/dev/null
}

record_phone_identity() {
    local index=$1 pid=${PHONE_PIDS[$(($1 - 1))]:-}
    local -a fields=()
    PHONE_START_TICKS[index-1]=
    # This read is in the spawning Bash, before launching another helper:
    # capture the fork's birth identity even if SIPp has not exec'd yet.
    read_phone_stat "$pid" || return 1
    [[ $PHONE_PROC_STAT == "$pid ("* && $PHONE_PROC_STAT == *') '* ]] || return 1
    read -r -a fields <<<"${PHONE_PROC_STAT##*) }"
    [[ ${#fields[@]} -ge 20 && ${fields[1]} == "$SUPERVISOR_PID" &&
       ${fields[19]} =~ ^[1-9][0-9]*$ ]] || return 1
    PHONE_START_TICKS[index-1]=${fields[19]}
}

phone_process_action() {
    local index=$1 operation=$2 pid=${PHONE_PIDS[$(($1 - 1))]:-} ticks=${PHONE_START_TICKS[$(($1 - 1))]:-} result
    if [[ ! $pid =~ ^[1-9][0-9]*$ || ! $ticks =~ ^[1-9][0-9]*$ || ! -f $PHONE_PROCESS_HELPER || -L $PHONE_PROCESS_HELPER ]]; then
        printf '%s\n' unknown
        return 0
    fi
    # Never fall back to kill(PID): the pidfd pins the task through validation
    # and signal delivery, including exit/PID-reuse races after the stat read.
    result=$(python3 -I "$PHONE_PROCESS_HELPER" "$operation" "$pid" "$ticks" "$SUPERVISOR_PID" 2>/dev/null 9>&-) || result=unknown
    case $result in alive|dead|foreign|unknown|sent) printf '%s\n' "$result" ;; *) printf '%s\n' unknown ;; esac
}

phone_process_state() { phone_process_action "$1" check; }
signal_phone() { phone_process_action "$1" "$2" >/dev/null; }

check_children() {
    local index
    for ((index=1; index<=${#PHONE_PIDS[@]}; index++)); do
        [[ $(phone_process_state "$index") == alive ]] || die "Phone $index child identity unavailable or exited; restarting the supervised fixture set"
        failed_registrations "$index" && die "Phone $index registration failed; restarting the supervised fixture set"
    done
    return 0
}

start_phones() {
    local index
    for ((index=1; index<=COUNT; index++)); do
        start_phone "$index"
        sleep 0.1
    done
}

start_phone() {
    local index=$1 port media proxy input
    proxy=$(jq -r '.sip_proxy_host + ":" + (.sip_proxy_port | tostring)' <<<"$STATE")
        port=$((SIP_BASE + index - 1)); media=$((RTP_BASE + (index - 1) * 4))
        input="$RUNTIME_DIR/agent-$index-input.csv"
        write_input "$index" 600 "$input"
        # SIPp mixed mode keeps refresh registration and incoming dialogs on
        # the same UDP socket. The primary scenario has one 240-second pause;
        # -users 1 limits only primary registrations, not secondary received calls.
        sipp "$proxy" -sf "$SCRIPT_DIR/sip-tests/live-agent-register.xml" \
            -rxsf "$SCRIPT_DIR/sip-tests/agent-answer.xml" -inf "$input" \
            -i "$PHONE_IP" -p "$port" -mi "$PHONE_IP" -ci "$PHONE_IP" \
            -min_rtp_port "$media" -max_rtp_port "$((media + 1))" \
            -rtp_echo -users 1 -nostdin -aa -recv_timeout 15000 \
            -trace_stat -fd 5s -stf "$RUNTIME_DIR/agent-$index-stats.csv" \
            >/dev/null 2>&1 9>&- &
        PHONE_PIDS[index-1]=$!
        record_phone_identity "$index" || die "Phone $index birth identity unavailable; refusing PID-only supervision"
        unset 'STAT_COLUMNS[index]'
}

no_active_calls() {
    local channels
    channels=$(timeout 5 "$FS_CLI" -x 'show channels as json' 2>/dev/null) || return 1
    valid_zero_channels <<<"$channels" >/dev/null 2>&1
}

valid_zero_channels() {
    jq -e 'type == "object" and .row_count == 0 and ((keys - ["row_count","rows"]) | length == 0) and
      ((has("rows") | not) or (.rows | type == "array" and length == 0))'
}

monitor_phones() {
    local index pid process_state healthy=0
    for ((index=1; index<=COUNT; index++)); do
        pid=${PHONE_PIDS[index-1]}
        process_state=$(phone_process_state "$index")
        if [[ $process_state == alive ]] && contact_present "$index"; then
            healthy=$((healthy + 1))
            if [[ ${PHONE_WARNED[index]:-false} == true ]]; then
                log "Phone $index registration recovered; existing agent status preserved"
                PHONE_WARNED[index]=false
            fi
            continue
        fi
        if [[ ${PHONE_WARNED[index]:-false} == false ]]; then
            log "Phone $index degraded; healthy phones and all agent statuses are preserved" >&2
            PHONE_WARNED[index]=true
        fi
        # A live process continues its own REGISTER refresh, including while
        # carrying an inbound user call. Never kill it over a refresh failure.
        # Restart ONLY a dead child, with fresh global zero-call evidence and
        # verified fixture ownership; never change login/pause/resume statuses.
        # Foreign or unreadable identity is not proof of a dead owned child.
        if [[ $process_state == dead && $OWNERSHIP_VERIFIED == true ]] && no_active_calls &&
           [[ $(phone_process_state "$index") == dead ]]; then
            wait "$pid" 2>/dev/null || true
            start_phone "$index"
            log "Restarted only phone $index after zero-call proof; agent statuses unchanged"
        fi
    done
    REGISTERED_PHONES=$healthy
    report_phone_health
    return 0
}

report_phone_health() {
    local status
    if ((REGISTERED_PHONES == COUNT)) && [[ $OWNERSHIP_VERIFIED == true ]]; then
        status="$COUNT/$COUNT owned test phones registered; agent statuses preserved"
    elif [[ $OWNERSHIP_VERIFIED != true ]]; then
        status="DEGRADED: $REGISTERED_PHONES/$COUNT phones registered; recovery blocked: $PHONE_OWNERSHIP_DIAGNOSTIC; agent statuses preserved"
    else
        status="DEGRADED: $REGISTERED_PHONES/$COUNT phones registered; recovery limited to dead owned phones after zero-call proof; agent statuses preserved"
    fi
    if [[ $PHONE_HEALTH_STATUS != "$status" ]]; then
        PHONE_HEALTH_STATUS=$status
        log "$status"
        if command -v systemd-notify >/dev/null; then systemd-notify --status="$status" || true; fi
    fi
}

stop_phones() {
    local index pid deadline=$((SECONDS + 5)) remaining
    for index in "${!PHONE_PIDS[@]}"; do signal_phone "$((index + 1))" INT; done
    while ((SECONDS < deadline)); do
        remaining=false
        for index in "${!PHONE_PIDS[@]}"; do
            [[ $(phone_process_state "$((index + 1))") == alive ]] && remaining=true
        done
        [[ $remaining == false ]] && break
        sleep 0.2
    done
    for index in "${!PHONE_PIDS[@]}"; do
        pid=${PHONE_PIDS[index]}
        signal_phone "$((index + 1))" KILL
        # wait is not a signal, but avoid blocking cleanup on any task whose
        # ownership/death cannot be proved. Bash/systemd reap remaining tasks.
        if [[ $(phone_process_state "$((index + 1))") == dead ]]; then wait "$pid" 2>/dev/null || true; fi
    done
    PHONE_PIDS=()
    PHONE_START_TICKS=()
}

clear_fixture_calls() {
    local channels uuid account authorizing peer
    [[ -x $FS_CLI ]] || return 1
    channels=$(timeout 10 "$FS_CLI" -x 'show channels as json' 2>/dev/null) || return 1
    # A complete zero response authorizes no call action and needs no row list.
    if valid_zero_channels <<<"$channels" >/dev/null 2>&1; then return 0; fi
    # Malformed/error/contradictory envelopes must not reach per-channel logic.
    # The existing account, device and source-IP guards below are unchanged.
    jq -e 'type == "object" and ((keys - ["row_count","rows"]) | length == 0) and
      (.row_count | type == "number" and . > 0) and (.rows | type == "array") and
      .row_count == (.rows | length)' <<<"$channels" >/dev/null 2>&1 || return 1
    while IFS= read -r uuid; do
        [[ $uuid =~ ^[A-Za-z0-9@._:+-]{1,192}$ ]] || continue
        account=$(timeout 3 "$FS_CLI" -x "uuid_getvar $uuid ecallmgr_Account-ID" 2>/dev/null) || continue
        [[ $account == "$ACCOUNT_ID" ]] || continue
        authorizing=$(timeout 3 "$FS_CLI" -x "uuid_getvar $uuid ecallmgr_Authorizing-ID" 2>/dev/null) || continue
        peer=$(timeout 3 "$FS_CLI" -x "uuid_getvar $uuid sip_network_ip" 2>/dev/null) || continue
        owned_channel "$account" "$authorizing" "$peer" || continue
        timeout 3 "$FS_CLI" -x "uuid_kill $uuid NORMAL_CLEARING" >/dev/null 2>&1 || true
    done < <(jq -r '.rows[].uuid // empty' <<<"$channels")
}

owned_channel() {
    [[ $1 == "$ACCOUNT_ID" && $3 == "$PHONE_IP" ]] || return 1
    jq -e --arg id "$2" 'any(.agents[]; .device_id == $id)' <<<"$STATE" >/dev/null
}

deregister_phones() {
    local index proxy input pid failed=0
    local -a pids=()
    proxy=$(jq -r '.sip_proxy_host + ":" + (.sip_proxy_port | tostring)' <<<"$STATE")
    for ((index=1; index<=COUNT; index++)); do
        input="$RUNTIME_DIR/agent-$index-deregister.csv"
        write_input "$index" 0 "$input"
        timeout 12 sipp "$proxy" -sf "$SCRIPT_DIR/sip-tests/register.xml" -inf "$input" \
            -i "$PHONE_IP" -p "$((SIP_BASE + index - 1))" -ci "$PHONE_IP" -m 1 -l 1 -r 1 -rp 1000 \
            -nostdin -timeout 10s -timeout_error >/dev/null 2>&1 9>&- &
        pids+=("$!")
        if ((${#pids[@]} == 5)); then
            for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
            pids=()
        fi
    done
    for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
    ((failed == 0))
}

cleanup_resources() {
    local failed=0 index
    # Fresh marker checks in the provisioner gate BOTH status mutations and
    # SIP cleanup. Never infer fixture ownership from extension numbers alone.
    if ! owned_helper verify; then
        log 'Cleanup ownership verification failed; no resource mutation performed' >&2
        return 1
    fi
    if ! owned_helper logout; then failed=1; log 'Scoped cleanup: agent logout did not converge' >&2; fi
    if ! clear_fixture_calls; then failed=1; log 'Scoped cleanup: channel observation unavailable' >&2; fi
    if ! deregister_phones; then failed=1; log 'Scoped cleanup: exact SIP deregistration failed' >&2; fi
    for ((index=1; index<=COUNT; index++)); do
        rm -f -- "$RUNTIME_DIR/agent-$index-input.csv" "$RUNTIME_DIR/agent-$index-deregister.csv"
    done
    if ((failed == 0)); then
        printf '%s\n' "$(jq -r '.deployment_id' <<<"$STATE")" >"$RUNTIME_DIR/cleanup-done"
        rm -f -- "$RUNTIME_DIR/preserve-agent-status"
        log 'Owned test agents logged out, exact contacts deregistered, and fixture legs cleared'
    else
        log 'Explicit cleanup incomplete; registrations expire within 600 seconds' >&2
    fi
    return "$failed"
}

phone_run_marker_matches() {
    local marker="$RUNTIME_DIR/phones-started"
    [[ -f $marker && ! -L $marker && $(stat -Lc '%u:%g:%a' -- "$marker") == 0:0:600 &&
       $(<"$marker") == "$(jq -r '.deployment_id' <<<"$STATE")" ]]
}

mark_phone_run() {
    local name
    for name in phones-started preserve-agent-status; do
        [[ ! -L $RUNTIME_DIR/$name ]] || die 'Runtime marker cannot be a symlink'
        printf '%s\n' "$(jq -r '.deployment_id' <<<"$STATE")" >"$RUNTIME_DIR/$name"
        chmod 600 "$RUNTIME_DIR/$name"
    done
}

cleanup_phones() {
    local index
    # This marker records that this deployment may have registered contacts.
    # It never grants authority over agent status, queue roster or call legs.
    phone_run_marker_matches || return 0
    if ! owned_helper verify_phones; then
        log 'Phone cleanup ownership unavailable; no deregistration attempted; agent statuses unchanged, contacts expire within 600 seconds' >&2
        return 1
    fi
    if ! deregister_phones; then
        log 'Exact phone deregistration incomplete; agent statuses unchanged, remaining contacts expire within 600 seconds' >&2
        return 1
    fi
    for ((index=1; index<=COUNT; index++)); do
        rm -f -- "$RUNTIME_DIR/agent-$index-input.csv" "$RUNTIME_DIR/agent-$index-deregister.csv"
    done
    rm -f -- "$RUNTIME_DIR/phones-started"
    log 'Exact owned phone contacts deregistered; agent statuses and queue roster unchanged; no native hangup command issued'
}

on_exit() {
    local status=$?
    [[ $CLEANING == false ]] || return
    CLEANING=true
    trap - EXIT TERM INT
    set +e
    stop_phones
    if [[ $RUN_STARTED == true ]]; then cleanup_phones; fi
    log 'Supervisor exit preserves all agent login/pause statuses and the operator queue roster'
    exit "$status"
}

run_service() {
    local index deadline next_check last_owned_check=0 file size version
    for command in sipp jq node kamcmd flock timeout python3 curl; do command -v "$command" >/dev/null || die "Missing dependency: $command"; done
    if [[ ! -f $PHONE_PROCESS_HELPER || -L $PHONE_PROCESS_HELPER ]] ||
       ! python3 -I "$PHONE_PROCESS_HELPER" --probe >/dev/null 2>&1; then
        die 'Python/kernel pidfd support is required; no PID-only fallback'
    fi
    version=$(sipp -v 2>&1 || true)
    [[ $version == *'SIPp v3.7.7-TLS-PCAP-SHA256'* ]] || die 'Pinned SIPp 3.7.7 is required'
    load_state
    prepare_runtime
    wait_for_dependencies || die 'Dependency readiness failed before phone registration'
    owned_helper verify_phones || die "Phone ownership verification failed before start: $PHONE_OWNERSHIP_DIAGNOSTIC"
    rm -f -- "$RUNTIME_DIR/cleanup-done"
    trap on_exit EXIT
    trap 'exit 0' TERM INT
    mark_phone_run
    RUN_STARTED=true
    start_phones
    deadline=$((SECONDS + 60))
    for ((index=1; index<=COUNT; index++)); do
        while true; do
            # Successful lookups can also consume the full five-second RPC
            # timeout. Reserve that budget before every probe, not just retries.
            ((SECONDS + 5 <= deadline)) || die 'Exact SIP contacts did not register before startup deadline'
            if contact_present "$index"; then
                ((SECONDS <= deadline)) || die 'Exact SIP contact proof arrived after startup deadline'
                break
            fi
            check_children
            ((SECONDS < deadline)) || die 'Exact SIP contacts did not register before startup deadline'
            sleep 1
        done
    done
    REGISTERED_PHONES=$COUNT
    # Preservation is unconditional, including after reboot clears /run.
    # The marker is evidence for existing read-only snapshot tooling only.
    log '30 owned MASTER phones registered; all existing agent statuses and queue roster preserved (RTP echo)'
    command -v systemd-notify >/dev/null && systemd-notify --ready
    report_phone_health
    next_check=$((SECONDS + 30))
    while :; do
        if ((SECONDS >= next_check)); then
            monitor_phones
            for ((index=1; index<=COUNT; index++)); do
                file="$RUNTIME_DIR/agent-$index-stats.csv"
                size=$(stat -c '%s' "$file" 2>/dev/null || printf 0)
                # Only statistics are logged. Keep each append-only CSV bounded;
                # its parsed field index survives truncation in supervisor memory.
                if ((size > 524288)) && [[ -n ${STAT_COLUMNS[$index]:-} ]]; then truncate -s 0 "$file"; fi
            done
            if ((SECONDS - last_owned_check >= 300)); then
                if owned_helper verify_phones; then
                    OWNERSHIP_VERIFIED=true
                else
                    OWNERSHIP_VERIFIED=false
                    log "Phone ownership check failed: $PHONE_OWNERSHIP_DIAGNOSTIC; repairs paused, agent statuses unchanged" >&2
                fi
                report_phone_health
                last_owned_check=$SECONDS
            fi
            next_check=$((SECONDS + 30))
        fi
        sleep 2
    done
}

main() {
    [[ $# -le 1 ]] || die 'Use --dry-run, --run, --cleanup-phones, or explicit --cleanup'
    MODE=${1:---dry-run}
    case $MODE in
        --dry-run)
            log 'DRY RUN: receive-only 30 MASTER owned test phones; no SIP/API/service mutations'
            log "Manifest: $STATE_FILE; SIP: $PHONE_IP:17100–17129; RTP: 46000–46119"
            log 'REGISTER expiry 600 s, refresh 240 s; service starts/stops preserve agent statuses and roster; explicit --cleanup is separate'
            ;;
        --run) [[ $EUID == 0 ]] || die 'Root is required'; run_service ;;
        --cleanup-phones)
            [[ $EUID == 0 ]] || die 'Root is required'
            load_state; prepare_runtime
            cleanup_phones
            ;;
        --cleanup)
            [[ $EUID == 0 ]] || die 'Root is required'
            load_state; prepare_runtime
            if [[ -f $RUNTIME_DIR/cleanup-done && ! -L $RUNTIME_DIR/cleanup-done &&
                  $(<"$RUNTIME_DIR/cleanup-done") == "$(jq -r '.deployment_id' <<<"$STATE")" ]]; then exit 0; fi
            cleanup_resources
            ;;
        *) die 'Use --dry-run, --run, --cleanup-phones, or explicit --cleanup' ;;
    esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
