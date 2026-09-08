#!/usr/bin/env bash
# Real SIP/RTP acceptance and bounded load test for the isolated Kazoo ACDC
# tenant created by test-kazoo-call-provision.sh. No PSTN routes are used.
# shellcheck disable=SC2317
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
readonly SCRIPT_DIR
readonly SCENARIO_DIR=${SCRIPT_DIR}/sip-tests
readonly DEFAULT_STATE_FILE=/etc/kazoo/acceptance-secrets.env
readonly DEFAULT_HELPER=${SCRIPT_DIR}/test-kazoo-call-provision.sh
readonly SIPP_VERSION=3.7.7
readonly SIPP_COMMIT=369b3c187f0ff96f3ec9795650820e80cf17c776
readonly SIPP_SOURCE=/usr/local/src/kazoo5-tests/sipp-${SIPP_VERSION}
readonly MAX_ANSWERED_CALLS=30
readonly AGENT_CONTACT_PORT_BASE=15100
readonly CALLER_PORT=15064
readonly NEGATIVE_REGISTER_PORT=15068
readonly AGENT_MEDIA_MIN=40000
readonly CALLER_MEDIA_MIN=42000
readonly CALLER_MEDIA_MAX=42998
readonly CALL_START_RATE=2
readonly FUNCTIONAL_HOLD_MS=30000
readonly STAGE_HOLD_MS=60000
readonly CAPACITY_HOLD_MS=360000
readonly CAPACITY_SOAK_SECONDS=180
readonly QUEUED_EXCESS_HOLD_MS=360000
readonly QUEUED_EXCESS_DELAY_MS=120000

STATE_FILE=$DEFAULT_STATE_FILE
STATE_HELPER=$DEFAULT_HELPER
STAGES=1,5,10,20,30
QUEUED_EXCESS=5
MODE=all
LIVE=false
INSTALL_DEPS=true
RUN_ROOT=/var/log/kazoo-acceptance
RUN_DIR=
LOCAL_IP=
LOCAL_IP_OVERRIDE=
declare -A STATE=()
declare -a ACTIVE_PIDS=()
declare -a AGENT_PIDS=()
AGENTS_REGISTERED=0
CALLER_REGISTERED=false
CLEANING_UP=false
STATUS_AGENT_MAX=0

usage() {
    cat <<'USAGE'
Usage: test-kazoo-calls.sh [OPTIONS]

Modes:
  --prepare-only       Validate protected state, scenarios, and SIPp only
  --registration-probe Register agent 1 for 60 seconds, then deregister
  --functional         One call: queue wait, agent ring/answer, RTP, hangup, idle
  --stress             Bounded answered-call stages only
  --all                Functional test then stress (default)

Options:
  --live               Required before any SIP traffic or agent-state mutation
  --config FILE        Root-owned 0600 base64 state file
  --state-helper FILE  Acceptance provisioner/status helper
  --stages LIST        Increasing answered concurrency, maximum 30
  --queued-excess N    Extra callers held while 30 agents are busy (default 5)
  --no-install-deps    Do not build SIPp when v3.7.7 is absent
  --run-root DIR       Protected results directory (default /var/log/kazoo-acceptance)
  --local-ip ADDRESS   SIPp source/media address (auto-selects 127.0.0.20 for local proxy)
  -h, --help           Show this help

The script uses only extensions 1001, 1002..1031, and queue 2000 from the
isolated acceptance tenant. It never originates a PSTN call. SIP passwords are
loaded from the protected base64 state and written only to temporary 0600 SIPp
injection files; they are never placed in process arguments or console output.
USAGE
}

log() { printf '[kazoo-call-test] %s\n' "$*"; }
warn() { printf '[kazoo-call-test] WARNING: %s\n' "$*" >&2; }
die() { printf '[kazoo-call-test] ERROR: %s\n' "$*" >&2; exit 1; }

parse_args() {
    while (($#)); do
        case $1 in
            --prepare-only) MODE=prepare ;;
            --registration-probe) MODE=registration-probe ;;
            --functional) MODE=functional ;;
            --stress) MODE=stress ;;
            --all) MODE=all ;;
            --live) LIVE=true ;;
            --config) (($# >= 2)) || die '--config requires a file'; STATE_FILE=$2; shift ;;
            --state-helper) (($# >= 2)) || die '--state-helper requires a file'; STATE_HELPER=$2; shift ;;
            --stages) (($# >= 2)) || die '--stages requires a list'; STAGES=$2; shift ;;
            --queued-excess) (($# >= 2)) || die '--queued-excess requires a number'; QUEUED_EXCESS=$2; shift ;;
            --no-install-deps) INSTALL_DEPS=false ;;
            --run-root) (($# >= 2)) || die '--run-root requires a directory'; RUN_ROOT=$2; shift ;;
            --local-ip) (($# >= 2)) || die '--local-ip requires an address'; LOCAL_IP_OVERRIDE=$2; shift ;;
            -h|--help) usage; exit 0 ;;
            *) die "Unknown option: $1" ;;
        esac
        shift
    done
}

validate_protected_file() {
    local path=$1 owner mode
    [[ -f $path && ! -L $path ]] || die "Protected file is missing or is a symlink: $path"
    owner=$(stat -Lc '%u:%g' -- "$path")
    mode=$(stat -Lc '%a' -- "$path")
    [[ $owner == 0:0 && $mode == 600 ]] || die "Protected file must be root:root 0600: $path"
}

load_state() {
    local line key encoded value
    validate_protected_file "$STATE_FILE"
    while IFS= read -r line || [[ -n $line ]]; do
        [[ -z $line || $line == \#* ]] && continue
        [[ $line == *=* ]] || die 'Malformed acceptance state line'
        key=${line%%=*}
        encoded=${line#*=}
        [[ $key =~ ^ACCEPTANCE_[A-Z0-9_]+$ ]] || die 'Invalid acceptance state key'
        [[ $encoded =~ ^[A-Za-z0-9+/]*={0,2}$ ]] || die "Invalid base64 for $key"
        value=$(printf '%s' "$encoded" | base64 -d 2>/dev/null) || die "Invalid base64 for $key"
        [[ $value != *$'\n'* && $value != *$'\r'* ]] || die "Multiline value rejected for $key"
        STATE["$key"]=$value
    done < "$STATE_FILE"
}

need_state() {
    local key=$1
    [[ -n ${STATE[$key]:-} ]] || die "Acceptance state is missing $key"
}

validate_state() {
    local key index count
    for key in ACCEPTANCE_ACCOUNT_ID ACCEPTANCE_REALM ACCEPTANCE_QUEUE_ID \
        ACCEPTANCE_CALLER_SIP_USERNAME ACCEPTANCE_CALLER_SIP_PASSWORD \
        ACCEPTANCE_SIP_PROXY_HOST ACCEPTANCE_SIP_PROXY_PORT ACCEPTANCE_SIP_TRANSPORT \
        ACCEPTANCE_CALLER_EXTENSION ACCEPTANCE_QUEUE_EXTENSION ACCEPTANCE_AGENT_COUNT; do
        need_state "$key"
    done
    [[ ${STATE[ACCEPTANCE_ACCOUNT_ID]} =~ ^[a-f0-9]{32}$ ]] || die 'Invalid acceptance account ID'
    [[ ${STATE[ACCEPTANCE_QUEUE_ID]} =~ ^[a-f0-9]{32}$ ]] || die 'Invalid acceptance queue ID'
    [[ ${STATE[ACCEPTANCE_REALM]} =~ ^[A-Za-z0-9.-]+$ ]] || die 'Invalid SIP realm'
    [[ ${STATE[ACCEPTANCE_SIP_PROXY_HOST]} =~ ^[A-Za-z0-9.:_-]+$ ]] || die 'Invalid SIP proxy host'
    [[ ${STATE[ACCEPTANCE_SIP_PROXY_PORT]} =~ ^[0-9]+$ ]] || die 'Invalid SIP proxy port'
    ((STATE[ACCEPTANCE_SIP_PROXY_PORT] >= 1 && STATE[ACCEPTANCE_SIP_PROXY_PORT] <= 65535)) || die 'Invalid SIP proxy port'
    [[ ${STATE[ACCEPTANCE_SIP_TRANSPORT],,} == udp ]] || die 'This RTP load harness currently requires UDP SIP transport'
    [[ ${STATE[ACCEPTANCE_CALLER_EXTENSION]} == 1001 && ${STATE[ACCEPTANCE_QUEUE_EXTENSION]} == 2000 ]] ||
        die 'Refusing non-isolated or PSTN-capable destinations; expected caller 1001 and queue 2000'
    validate_sip_credential ACCEPTANCE_CALLER_SIP_USERNAME
    validate_sip_credential ACCEPTANCE_CALLER_SIP_PASSWORD
    count=${STATE[ACCEPTANCE_AGENT_COUNT]}
    if [[ ! $count =~ ^[0-9]+$ ]] || ((count < 1 || count > MAX_ANSWERED_CALLS)); then
        die 'Invalid acceptance agent count'
    fi
    for ((index=1; index<=count; index++)); do
        for key in USER_ID EXTENSION SIP_USERNAME SIP_PASSWORD; do
            need_state "ACCEPTANCE_AGENT_${index}_${key}"
        done
        [[ ${STATE[ACCEPTANCE_AGENT_${index}_USER_ID]} =~ ^[a-f0-9]{32}$ ]] || die "Invalid agent $index user ID"
        [[ ${STATE[ACCEPTANCE_AGENT_${index}_EXTENSION]} == $((1001 + index)) ]] || die "Unexpected agent $index extension"
        validate_sip_credential "ACCEPTANCE_AGENT_${index}_SIP_USERNAME"
        validate_sip_credential "ACCEPTANCE_AGENT_${index}_SIP_PASSWORD"
    done
}

validate_sip_credential() {
    local key=$1 value=${STATE[$1]:-}
    [[ -n $value && ${#value} -le 192 ]] || die "Invalid SIP credential length for $key"
    # SIPp injection uses semicolons as separators and square brackets for
    # recursive authentication keywords, so reject those metacharacters.
    [[ $value =~ ^[A-Za-z0-9._~!$\&\'\(\)*+,/:=@%-]+$ ]] || die "Unsafe SIP credential characters for $key"
}

validate_stages() {
    local previous=0 stage
    [[ $STAGES =~ ^[0-9]+(,[0-9]+)*$ ]] || die 'Stages must be a comma-separated integer list'
    IFS=, read -r -a STAGE_LIST <<< "$STAGES"
    for stage in "${STAGE_LIST[@]}"; do
        ((stage >= 1 && stage <= MAX_ANSWERED_CALLS)) || die "Stage $stage is outside 1..30"
        ((stage > previous)) || die 'Stages must be strictly increasing'
        ((stage <= STATE[ACCEPTANCE_AGENT_COUNT])) || die "Stage $stage exceeds provisioned agents"
        previous=$stage
    done
    if [[ ! $QUEUED_EXCESS =~ ^[0-9]+$ ]] || ((QUEUED_EXCESS < 0 || QUEUED_EXCESS > 10)); then
        die 'Queued excess must be between 0 and 10'
    fi
}

ensure_sipp_version_tag() {
    local version_tag="refs/tags/v${SIPP_VERSION}"
    # SIPp generates version.h with git describe. A commit-only shallow fetch
    # builds the right source but advertises only its hash, failing consumers'
    # release/feature checks. Never trust a release tag without the commit pin.
    if ! git -C "$SIPP_SOURCE" show-ref --verify --quiet "$version_tag"; then
        git -C "$SIPP_SOURCE" fetch -q --depth 1 origin "$version_tag:$version_tag" ||
            die 'Could not fetch pinned SIPp release tag'
    fi
    [[ $(git -C "$SIPP_SOURCE" rev-parse "${version_tag}^{commit}") == "$SIPP_COMMIT" ]] ||
        die 'SIPp release tag does not match pinned commit'
}

ensure_sipp() {
    local version_output=
    if ! command -v tcpdump >/dev/null 2>&1; then
        [[ $INSTALL_DEPS == true ]] || die 'tcpdump is required for RTP packet verification'
        command -v dnf >/dev/null 2>&1 || die 'Automatic tcpdump installation requires dnf'
        dnf -q install -y tcpdump >/dev/null
    fi
    if command -v sipp >/dev/null 2>&1; then
        version_output=$(sipp -v 2>&1 || true)
        if grep -F "SIPp v${SIPP_VERSION}-TLS-PCAP-SHA256" <<< "$version_output" >/dev/null; then return 0; fi
    fi
    [[ $INSTALL_DEPS == true ]] || die "SIPp ${SIPP_VERSION} with TLS/PCAP/SHA256 is required"
    command -v dnf >/dev/null 2>&1 || die 'Automatic SIPp installation requires dnf'
    log "Installing pinned SIPp ${SIPP_VERSION} test dependency"
    dnf -q install -y git cmake gcc-c++ libpcap-devel ncurses-devel openssl-devel tcpdump >/dev/null
    if [[ ! -d $SIPP_SOURCE/.git ]]; then
        [[ ! -e $SIPP_SOURCE ]] || die "Refusing unexpected existing SIPp source path: $SIPP_SOURCE"
        install -d -m 0755 "$(dirname -- "$SIPP_SOURCE")"
        git init -q "$SIPP_SOURCE"
        git -C "$SIPP_SOURCE" remote add origin https://github.com/SIPp/sipp.git
        git -C "$SIPP_SOURCE" fetch -q --depth 1 origin "$SIPP_COMMIT"
        git -C "$SIPP_SOURCE" checkout -q --detach FETCH_HEAD
    fi
    [[ $(git -C "$SIPP_SOURCE" rev-parse HEAD) == "$SIPP_COMMIT" ]] || die 'Existing SIPp source is not the pinned commit'
    ensure_sipp_version_tag
    cmake -S "$SIPP_SOURCE" -B "$SIPP_SOURCE/build" -DUSE_SSL=ON -DUSE_PCAP=ON \
        -DUSE_SCTP=OFF -DUSE_GSL=OFF -DCMAKE_BUILD_TYPE=Release >/dev/null
    cmake --build "$SIPP_SOURCE/build" --parallel 2 >/dev/null
    cmake --install "$SIPP_SOURCE/build" --prefix /usr/local >/dev/null
    version_output=$(sipp -v 2>&1 || true)
    grep -F "SIPp v${SIPP_VERSION}-TLS-PCAP-SHA256" <<< "$version_output" >/dev/null || die 'SIPp feature verification failed'
}

validate_scenarios() {
    local scenario scratch input
    scratch=$(mktemp -d /tmp/kazoo-sipp-parse.XXXXXX)
    chmod 700 "$scratch"
    input=$scratch/input.csv
    printf 'SEQUENTIAL\ndummy;[authentication username=dummy password=dummy];example.invalid;5099;600\n' > "$input"
    chmod 600 "$input"
    for scenario in register.xml register-rejected.xml caller-to-queue.xml agent-answer.xml; do
        timeout 5 sipp -ci 127.0.0.1 127.0.0.1:9 -sf "$SCENARIO_DIR/$scenario" -inf "$input" \
            -i 127.0.0.1 -p 5099 -mi 127.0.0.1 -mp 45000 -m 0 -nostdin \
            >"$scratch/$scenario.out" 2>&1 || die "SIPp rejected scenario $scenario"
        ! grep -Eq 'parse error|is not a floating point|Unable to load|Unknown element' "$scratch/$scenario.out" ||
            die "SIPp rejected scenario $scenario"
    done
    find "$scratch" -type f -delete
    rmdir "$scratch"
}

resolve_local_ip() {
    local route route_source
    if [[ -n $LOCAL_IP_OVERRIDE ]]; then
        [[ $LOCAL_IP_OVERRIDE =~ ^[0-9a-fA-F:.]+$ ]] || die 'Invalid SIPp local IP override'
        LOCAL_IP=$LOCAL_IP_OVERRIDE
        return 0
    fi
    route=$(ip -o route get "${STATE[ACCEPTANCE_SIP_PROXY_HOST]}" 2>/dev/null) || die 'No route to SIP proxy'
    route_source=$(awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}' <<< "$route")
    # When SIPp originates from Kamailio's own listening IP, the stock config's
    # src_ip==myself shortcut intentionally bypasses registered-endpoint token
    # creation. Use a distinct loopback address for an all-local acceptance test
    # so packets traverse the same registered-device authorization path as a
    # remote phone while remaining entirely on the host.
    if [[ $route_source == "${STATE[ACCEPTANCE_SIP_PROXY_HOST]}" && $route_source == *.* ]]; then
        LOCAL_IP=127.0.0.20
    else
        LOCAL_IP=$route_source
    fi
    [[ $LOCAL_IP =~ ^[0-9a-fA-F:.]+$ ]] || die 'Could not resolve local SIP source address'
}

create_run_dir() {
    local stamp
    stamp=$(date -u +%Y%m%dT%H%M%SZ)
    install -d -m 0700 "$RUN_ROOT"
    RUN_DIR=$RUN_ROOT/$stamp
    if [[ -e $RUN_DIR ]]; then RUN_DIR=${RUN_DIR}-$$; fi
    install -d -m 0700 "$RUN_DIR"
    printf 'stage\tanswered_target/total_calls\tcaller_success\tcaller_failed\tagent_success\tagent_failed\tpeak_cpu_pct\tmin_mem_available_kb\terror_logs\tnew_cores\tverified_concurrent_hold_s\n' > "$RUN_DIR/summary.tsv"
    chmod 600 "$RUN_DIR/summary.tsv"
}

auth_keyword() {
    local username=$1 password=$2
    printf '[authentication username=%s password=%s]' "$username" "$password"
}

write_agent_registration_csv() {
    local file=$1 index=$2 expires=$3 username password
    printf 'SEQUENTIAL\n' > "$file"
    username=${STATE[ACCEPTANCE_AGENT_${index}_SIP_USERNAME]}
    password=${STATE[ACCEPTANCE_AGENT_${index}_SIP_PASSWORD]}
    printf '%s;%s;%s;%s;%s\n' "$username" "$(auth_keyword "$username" "$password")" \
        "${STATE[ACCEPTANCE_REALM]}" "$((AGENT_CONTACT_PORT_BASE + index - 1))" "$expires" >> "$file"
    chmod 600 "$file"
}

write_caller_csv() {
    local file=$1 count=$2 main_count=$3 main_hold_ms=$4 excess_hold_ms=$5
    local excess_delay_ms=$6 index username password hold_ms start_delay_ms
    username=${STATE[ACCEPTANCE_CALLER_SIP_USERNAME]}
    password=${STATE[ACCEPTANCE_CALLER_SIP_PASSWORD]}
    printf 'SEQUENTIAL\n' > "$file"
    for ((index=1; index<=count; index++)); do
        hold_ms=$main_hold_ms
        start_delay_ms=0
        if ((index > main_count)); then
            hold_ms=$excess_hold_ms
            start_delay_ms=$excess_delay_ms
        fi
        printf '%s;%s;%s;%s;%s;%s\n' "$username" "$(auth_keyword "$username" "$password")" \
            "${STATE[ACCEPTANCE_REALM]}" "${STATE[ACCEPTANCE_QUEUE_EXTENSION]}" \
            "$hold_ms" "$start_delay_ms" >> "$file"
    done
    chmod 600 "$file"
}

write_caller_registration_csv() {
    local file=$1 contact_port=$2 expires=$3 username password
    username=${STATE[ACCEPTANCE_CALLER_SIP_USERNAME]}
    password=${STATE[ACCEPTANCE_CALLER_SIP_PASSWORD]}
    printf 'SEQUENTIAL\n%s;%s;%s;%s;%s\n' "$username" \
        "$(auth_keyword "$username" "$password")" "${STATE[ACCEPTANCE_REALM]}" \
        "$contact_port" "$expires" > "$file"
    chmod 600 "$file"
}

stat_value() {
    local file=$1 column=$2
    awk -F';' -v wanted="$column" '
        NR == 1 {for (i=1; i<=NF; i++) if ($i == wanted) col=i; next}
        NF > 2 && col {value=$col}
        END {if (value == "") exit 1; print value}
    ' "$file"
}

assert_stats() {
    local label=$1 file=$2 expected=$3 successful failed
    [[ -s $file ]] || die "$label did not write SIPp statistics"
    successful=$(stat_value "$file" 'SuccessfulCall(C)') || die "$label success counter missing"
    failed=$(stat_value "$file" 'FailedCall(C)') || die "$label failure counter missing"
    [[ $successful =~ ^[0-9]+$ && $failed =~ ^[0-9]+$ ]] || die "$label counters are invalid"
    ((successful == expected && failed == 0)) || die "$label: expected $expected success/0 failure, got $successful/$failed"
}

wait_current_calls() {
    local file=$1 expected=$2 deadline=$((SECONDS + 45)) current=0
    while ((SECONDS < deadline)); do
        if [[ -s $file ]]; then current=$(stat_value "$file" 'CurrentCall' 2>/dev/null || printf 0); fi
        ((current >= expected)) && return 0
        sleep 1
    done
    return 1
}

wait_answered_calls() {
    local file=$1 expected=$2 deadline=$((SECONDS + 45)) answered=0
    while ((SECONDS < deadline)); do
        if [[ ${CALLER_PID:-} =~ ^[0-9]+$ ]] && ! kill -0 "$CALLER_PID" 2>/dev/null; then return 1; fi
        if [[ -s $file ]]; then answered=$(stat_value "$file" 'answered(C)' 2>/dev/null || printf 0); fi
        ((answered >= expected)) && return 0
        sleep 1
    done
    return 1
}

wait_agent_ready() {
    local index=$1 deadline=$((SECONDS + 30)) key output account_arg agent_arg
    key="ACCEPTANCE_AGENT_${index}_USER_ID"
    printf -v account_arg '<<"%s">>' "${STATE[ACCEPTANCE_ACCOUNT_ID]}"
    printf -v agent_arg '<<"%s">>' "${STATE[$key]}"
    while ((SECONDS < deadline)); do
        output=$(timeout 15 sup -e acdc_agent_maintenance agent_status \
            "$account_arg" "$agent_arg" </dev/null 2>/dev/null || true)
        grep -Eq '(^|[[:space:]])state:[[:space:]]*ready([[:space:]]|$)' <<< "$output" && return 0
        sleep 1
    done
    return 1
}

wait_agents_ready() {
    local count=$1 index
    for ((index=1; index<=count; index++)); do
        wait_agent_ready "$index" || return 1
    done
}

best_effort_clear_acceptance_calls() {
    local fs_cli=/usr/local/freeswitch/bin/fs_cli caller_pid=${MAIN_CALLER_PID:-${CALLER_PID:-}}
    local channels uuid suffix
    [[ $caller_pid =~ ^[0-9]+$ && -x $fs_cli && -n ${LOCAL_IP:-} ]] || return 0
    suffix="-${caller_pid}@${LOCAL_IP}"
    channels=$($fs_cli -x 'show channels as json' 2>/dev/null || true)
    jq -e '.rows | type == "array"' <<<"$channels" >/dev/null 2>&1 || return 0
    while IFS= read -r uuid; do
        [[ -n $uuid ]] || continue
        $fs_cli -x "uuid_kill $uuid NORMAL_CLEARING" >/dev/null 2>&1 || true
    done < <(jq -r --arg suffix "$suffix" \
        '.rows[] | select(.direction == "inbound" and (.uuid | endswith($suffix))) | .uuid' \
        <<<"$channels")
}

agent_status() {
    local action=$1 start=$2 end=$3
    [[ -x $STATE_HELPER ]] || die "State helper is not executable: $STATE_HELPER"
    KAZOO_ACCEPTANCE_STATE_FILE=$STATE_FILE "$STATE_HELPER" --agent-status "$action" --agent-range "$start:$end" >/dev/null
}

register_agents() {
    local label=$1 count=$2 expires=${3:-600}
    local index port csv stats output
    for ((index=1; index<=count; index++)); do
        port=$((AGENT_CONTACT_PORT_BASE + index - 1))
        csv=$RUN_DIR/$label-agent-$index-register-input.csv
        stats=$RUN_DIR/$label-agent-$index-register-stats.csv
        output=$RUN_DIR/$label-agent-$index-register.log
        write_agent_registration_csv "$csv" "$index" "$expires"
        if ! sipp -ci 127.0.0.1 "${STATE[ACCEPTANCE_SIP_PROXY_HOST]}:${STATE[ACCEPTANCE_SIP_PROXY_PORT]}" \
            -sf "$SCENARIO_DIR/register.xml" -inf "$csv" -i "$LOCAL_IP" -p "$port" \
            -m 1 -l 1 -r 1 -rp 1000 -nostdin -timeout 30s -timeout_error \
            -trace_stat -fd 1s -stf "$stats" >"$output" 2>&1; then
            rm -f -- "$csv"
            die "$label agent $index registration failed; protected diagnostics: $output"
        fi
        rm -f -- "$csv"
        assert_stats "$label agent $index registration" "$stats" 1
    done
    if ((expires > 0)); then AGENTS_REGISTERED=$count; else AGENTS_REGISTERED=0; fi
}

register_caller() {
    local label=$1 contact_port=$2 expires=${3:-600}
    local csv=$RUN_DIR/$label-caller-register-input.csv
    local stats=$RUN_DIR/$label-caller-register-stats.csv output=$RUN_DIR/$label-caller-register.log
    write_caller_registration_csv "$csv" "$contact_port" "$expires"
    if ! sipp -ci 127.0.0.1 "${STATE[ACCEPTANCE_SIP_PROXY_HOST]}:${STATE[ACCEPTANCE_SIP_PROXY_PORT]}" \
        -sf "$SCENARIO_DIR/register.xml" -inf "$csv" -i "$LOCAL_IP" -p "$contact_port" \
        -m 1 -l 1 -r 1 -rp 1000 -nostdin -timeout 30s -timeout_error \
        -trace_stat -fd 1s -stf "$stats" >"$output" 2>&1; then
        rm -f -- "$csv"
        die "$label caller registration failed; protected diagnostics: $output"
    fi
    rm -f -- "$csv"
    assert_stats "$label caller registration" "$stats" 1
    if ((expires > 0)); then CALLER_REGISTERED=true; else CALLER_REGISTERED=false; fi
}

negative_registration_test() {
    local label=$1 username=${STATE[ACCEPTANCE_CALLER_SIP_USERNAME]} bad_secret csv stats output locations
    bad_secret=$(openssl rand -hex 32)
    csv=$RUN_DIR/$label-negative-register-input.csv
    stats=$RUN_DIR/$label-negative-register-stats.csv
    output=$RUN_DIR/$label-negative-register.log
    printf 'SEQUENTIAL\n%s;%s;%s;%s;%s\n' "$username" \
        "$(auth_keyword "$username" "$bad_secret")" "${STATE[ACCEPTANCE_REALM]}" \
        "$NEGATIVE_REGISTER_PORT" 600 > "$csv"
    chmod 600 "$csv"
    if ! sipp -ci 127.0.0.1 "${STATE[ACCEPTANCE_SIP_PROXY_HOST]}:${STATE[ACCEPTANCE_SIP_PROXY_PORT]}" \
        -sf "$SCENARIO_DIR/register-rejected.xml" -inf "$csv" -i "$LOCAL_IP" -p "$NEGATIVE_REGISTER_PORT" \
        -m 1 -l 1 -r 1 -rp 1000 -nostdin -timeout 30s -timeout_error \
        -trace_stat -fd 1s -stf "$stats" >"$output" 2>&1; then
        rm -f -- "$csv"
        die 'Wrong-credential REGISTER did not produce a verified authentication rejection'
    fi
    rm -f -- "$csv"
    assert_stats "$label authentication rejection" "$stats" 1
    locations=$(kamcmd ul.lookup location "$username@${STATE[ACCEPTANCE_REALM]}" 2>/dev/null || true)
    [[ $locations != *":$NEGATIVE_REGISTER_PORT"* ]] || die 'Wrong-credential REGISTER created a location binding'
    log 'Negative authentication PASS: wrong credential rejected with no location binding'
}

best_effort_deregister_agents() {
    local count=$1 index port csv
    for ((index=1; index<=count; index++)); do
        port=$((AGENT_CONTACT_PORT_BASE + index - 1))
        csv=$RUN_DIR/cleanup-agent-$index-register-input.csv
        write_agent_registration_csv "$csv" "$index" 0
        sipp -ci 127.0.0.1 "${STATE[ACCEPTANCE_SIP_PROXY_HOST]}:${STATE[ACCEPTANCE_SIP_PROXY_PORT]}" \
            -sf "$SCENARIO_DIR/register.xml" -inf "$csv" -i "$LOCAL_IP" -p "$port" \
            -m 1 -l 1 -r 1 -rp 1000 -nostdin -timeout 15s \
            >"$RUN_DIR/cleanup-agent-$index-register.log" 2>&1 || true
        rm -f -- "$csv"
    done
}

best_effort_deregister_caller() {
    local contact_port=$1 label=$2
    local csv=$RUN_DIR/$label-register-input.csv
    write_caller_registration_csv "$csv" "$contact_port" 0
    sipp -ci 127.0.0.1 "${STATE[ACCEPTANCE_SIP_PROXY_HOST]}:${STATE[ACCEPTANCE_SIP_PROXY_PORT]}" \
        -sf "$SCENARIO_DIR/register.xml" -inf "$csv" -i "$LOCAL_IP" -p "$contact_port" \
        -m 1 -l 1 -r 1 -rp 1000 -nostdin -timeout 15s \
        >"$RUN_DIR/$label-register.log" 2>&1 || true
    rm -f -- "$csv"
}

start_agent_uas() {
    local label=$1 count=$2 excess=${3:-0}
    local index calls port media stats output pid
    AGENT_PIDS=()
    for ((index=1; index<=count; index++)); do
        calls=1; ((excess > 0)) && calls=2
        port=$((AGENT_CONTACT_PORT_BASE + index - 1))
        # SIPp reserves the audio socket and an implicit video socket at +2,
        # even though this scenario advertises audio only. Give each process a
        # four-port slot so adjacent agent UAS processes cannot collide.
        media=$((AGENT_MEDIA_MIN + (index - 1) * 4))
        stats=$RUN_DIR/$label-agent-$index-stats.csv
        output=$RUN_DIR/$label-agent-$index.log
        sipp -ci 127.0.0.1 -sf "$SCENARIO_DIR/agent-answer.xml" -i "$LOCAL_IP" -p "$port" \
            -mi "$LOCAL_IP" -min_rtp_port "$media" -max_rtp_port "$((media + 1))" \
            -rtp_echo -m "$calls" -l 1 -r 1 -rp 1000 -nostdin -aa \
            -timeout 600s -timeout_error -trace_stat -fd 1s -stf "$stats" >"$output" 2>&1 &
        pid=$!
        AGENT_PIDS+=("$pid")
        ACTIVE_PIDS+=("$pid")
    done
    sleep 1
    for pid in "${AGENT_PIDS[@]}"; do
        kill -0 "$pid" 2>/dev/null || die "$label agent SIPp exited before calls arrived"
    done
}

start_callers() {
    local label=$1 count=$2 port=$3 media_min=$4 media_max=$5 hold_ms=$6
    local main_count=${7:-$count} excess_hold_ms=${8:-$hold_ms} excess_delay_ms=${9:-0}
    local csv=$RUN_DIR/$label-caller-input.csv stats=$RUN_DIR/$label-caller-stats.csv output=$RUN_DIR/$label-caller.log
    local timeout_seconds=$(((excess_delay_ms + excess_hold_ms) / 1000 + 120)) rate=$count
    # Capacity means concurrent established calls, not a burst-CPS test. Pace
    # setup so the final 35 arrivals overlap for the full soak without turning
    # this 2-vCPU acceptance host's dialplan-fetch timeout into the bottleneck.
    ((rate > CALL_START_RATE)) && rate=$CALL_START_RATE
    write_caller_csv "$csv" "$count" "$main_count" "$hold_ms" "$excess_hold_ms" "$excess_delay_ms"
    sipp -ci 127.0.0.1 "${STATE[ACCEPTANCE_SIP_PROXY_HOST]}:${STATE[ACCEPTANCE_SIP_PROXY_PORT]}" \
        -sf "$SCENARIO_DIR/caller-to-queue.xml" -inf "$csv" -i "$LOCAL_IP" -p "$port" \
        -mi "$LOCAL_IP" -min_rtp_port "$media_min" -max_rtp_port "$media_max" \
        -m "$count" -l "$count" -r "$rate" -rp 1000 -nostdin -aa -audiotolerance 0.95 \
        -timeout "${timeout_seconds}s" -timeout_error \
        -trace_stat -fd 1s -stf "$stats" >"$output" 2>&1 &
    CALLER_PID=$!
    ACTIVE_PIDS+=("$CALLER_PID")
}

wait_checked() {
    local label=$1 pid=$2
    if ! wait "$pid"; then die "$label SIPp process failed; see protected run diagnostics"; fi
}

wait_agents_checked() {
    local label=$1 pid
    for pid in "${AGENT_PIDS[@]}"; do wait_checked "$label agent" "$pid"; done
}

stop_waiting_agents_checked() {
    local label=$1 pid
    # All caller BYEs have completed. SIGUSR1 asks SIPp to stop accepting a
    # second call on agents that were not selected for queued-member drain,
    # while processes that handled two calls have already exited normally.
    for pid in "${AGENT_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill -USR1 "$pid" 2>/dev/null || true
        fi
    done
    for pid in "${AGENT_PIDS[@]}"; do wait_checked "$label agent" "$pid"; done
}

wait_agents_current() {
    local label=$1 count=$2 deadline=$((SECONDS + 45)) index current active
    while ((SECONDS < deadline)); do
        active=0
        for ((index=1; index<=count; index++)); do
            current=$(stat_value "$RUN_DIR/$label-agent-$index-stats.csv" 'CurrentCall' 2>/dev/null || printf 0)
            ((current >= 1)) && active=$((active + 1))
        done
        ((active >= count)) && return 0
        sleep 1
    done
    return 1
}

concurrent_call_legs_present() {
    local label=$1 agent_count=$2 caller_expected=$3 index current caller_current caller_answered active=0
    caller_current=$(stat_value "$RUN_DIR/$label-caller-stats.csv" 'CurrentCall' 2>/dev/null || printf 0)
    caller_answered=$(stat_value "$RUN_DIR/$label-caller-stats.csv" 'answered(C)' 2>/dev/null || printf 0)
    for ((index=1; index<=agent_count; index++)); do
        current=$(stat_value "$RUN_DIR/$label-agent-$index-stats.csv" 'CurrentCall' 2>/dev/null || printf 0)
        ((current >= 1)) && active=$((active + 1))
    done
    ((caller_current >= caller_expected && caller_answered >= caller_expected && active >= agent_count))
}

wait_concurrent_call_legs() {
    local label=$1 agent_count=$2 caller_expected=$3 deadline=$((SECONDS + 60))
    while ((SECONDS < deadline)); do
        concurrent_call_legs_present "$label" "$agent_count" "$caller_expected" && return 0
        sleep 1
    done
    return 1
}

hold_concurrent_call_legs() {
    local label=$1 agent_count=$2 caller_expected=$3 duration=$4
    local deadline=$((SECONDS + duration))
    while ((SECONDS < deadline)); do
        concurrent_call_legs_present "$label" "$agent_count" "$caller_expected" || return 1
        sleep 1
    done
}

wait_agent_observed_answer() {
    local label=$1 index=$2 deadline=$((SECONDS + 45)) current successful
    while ((SECONDS < deadline)); do
        current=$(stat_value "$RUN_DIR/$label-agent-$index-stats.csv" 'CurrentCall' 2>/dev/null || printf 0)
        successful=$(stat_value "$RUN_DIR/$label-agent-$index-stats.csv" 'SuccessfulCall(C)' 2>/dev/null || printf 0)
        ((current >= 1 || successful >= 1)) && return 0
        sleep 1
    done
    return 1
}

agent_stats_totals() {
    local label=$1 count=$2 index successful=0 failed=0 value
    for ((index=1; index<=count; index++)); do
        value=$(stat_value "$RUN_DIR/$label-agent-$index-stats.csv" 'SuccessfulCall(C)') || return 1
        successful=$((successful + value))
        value=$(stat_value "$RUN_DIR/$label-agent-$index-stats.csv" 'FailedCall(C)') || return 1
        failed=$((failed + value))
    done
    printf '%s %s\n' "$successful" "$failed"
}

assert_agent_stats() {
    local label=$1 count=$2 expected=$3 successful failed
    read -r successful failed < <(agent_stats_totals "$label" "$count") || die "$label agent counters missing"
    ((successful == expected && failed == 0)) ||
        die "$label agent bridge/hangup: expected $expected success/0 failure, got $successful/$failed"
}

sample_resources() {
    local output=$1 stop_file=$2 prev_total=0 prev_idle=0 line user nice system idle iowait irq softirq steal total idle_all delta delta_idle cpu mem
    while [[ ! -e $stop_file ]]; do
        read -r line user nice system idle iowait irq softirq steal _ < /proc/stat
        total=$((user + nice + system + idle + iowait + irq + softirq + steal))
        idle_all=$((idle + iowait))
        if ((prev_total > 0 && total > prev_total)); then
            delta=$((total - prev_total)); delta_idle=$((idle_all - prev_idle))
            cpu=$((100 * (delta - delta_idle) / delta))
            mem=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
            printf '%s\t%s\t%s\n' "$(date +%s)" "$cpu" "$mem" >> "$output"
        fi
        prev_total=$total; prev_idle=$idle_all
        sleep 1
    done
}

start_monitor() {
    local label=$1
    MONITOR_FILE=$RUN_DIR/$label-resources.tsv
    MONITOR_STOP=$RUN_DIR/$label-monitor.stop
    : > "$MONITOR_FILE"; chmod 600 "$MONITOR_FILE"
    sample_resources "$MONITOR_FILE" "$MONITOR_STOP" &
    MONITOR_PID=$!
    ACTIVE_PIDS+=("$MONITOR_PID")
}

start_rtp_capture() {
    local label=$1
    RTP_PCAP=$RUN_DIR/$label-rtp.pcap
    RTP_CAPTURE_LOG=$RUN_DIR/$label-rtp-capture.log
    tcpdump -q -n -i any -U -w "$RTP_PCAP" \
        'udp and portrange 40000-44998' >"$RTP_CAPTURE_LOG" 2>&1 &
    RTP_CAPTURE_PID=$!
    ACTIVE_PIDS+=("$RTP_CAPTURE_PID")
    sleep 1
    kill -0 "$RTP_CAPTURE_PID" 2>/dev/null || die "$label RTP capture failed to start"
}

stop_rtp_capture() {
    if kill -0 "$RTP_CAPTURE_PID" 2>/dev/null; then kill -INT "$RTP_CAPTURE_PID" 2>/dev/null || true; fi
    wait "$RTP_CAPTURE_PID" 2>/dev/null || true
}

pcap_count() {
    local filter=$1
    tcpdump -q -nn -r "$RTP_PCAP" "$filter" 2>/dev/null | awk 'END{print NR+0}'
}

assert_rtp_capture() {
    local label=$1 agent_count=$2 caller_count=$3 index port agent_in agent_out caller_in caller_out minimum
    [[ -s $RTP_PCAP ]] || die "$label did not capture RTP packets"
    for ((index=1; index<=agent_count; index++)); do
        port=$((AGENT_MEDIA_MIN + (index - 1) * 4))
        agent_in=$(pcap_count "udp dst port $port")
        agent_out=$(pcap_count "udp src port $port")
        ((agent_in >= 10 && agent_out >= 10)) ||
            die "$label agent $index RTP was not bidirectional (in=$agent_in out=$agent_out)"
    done
    caller_in=$(pcap_count "udp dst portrange $CALLER_MEDIA_MIN-$CALLER_MEDIA_MAX")
    caller_out=$(pcap_count "udp src portrange $CALLER_MEDIA_MIN-$CALLER_MEDIA_MAX")
    minimum=$((caller_count * 10))
    ((caller_in >= minimum && caller_out >= minimum)) ||
        die "$label caller RTP packet floor failed (in=$caller_in out=$caller_out expected-at-least=$minimum)"
    printf 'agent_endpoints\t%s\ncaller_calls\t%s\ncaller_rtp_in\t%s\ncaller_rtp_out\t%s\n' \
        "$agent_count" "$caller_count" "$caller_in" "$caller_out" > "$RUN_DIR/$label-rtp-counts.tsv"
    chmod 600 "$RUN_DIR/$label-rtp-counts.tsv"
    rm -f -- "$RTP_PCAP"
}

capture_log_baseline() {
    local label=$1 path
    : > "$RUN_DIR/$label-log-baseline.tsv"
    while IFS= read -r path; do
        printf '%s\t%s\n' "$path" "$(wc -l < "$path")" >> "$RUN_DIR/$label-log-baseline.tsv"
    done < <(find -H /var/log/kazoo /var/log/freeswitch /opt/kz5/log \
        -maxdepth 4 -type f -name '*.log' -print 2>/dev/null)
    chmod 600 "$RUN_DIR/$label-log-baseline.tsv"
}

new_error_log_matches() {
    local label=$1 path lines count=0 found
    while IFS=$'\t' read -r path lines; do
        [[ -r $path && $lines =~ ^[0-9]+$ ]] || continue
        found=$(tail -n "+$((lines + 1))" -- "$path" 2>/dev/null |
            # Event identifiers such as CHANNEL_EXECUTE_ERROR occur in normal
            # subscription logs. Match diagnostic words, not identifier parts.
            grep -Eic '\[(err|crit|alert|emerg)\]|(^|[^[:alnum:]_])(error|fatal|crash|segfault|core dumped)([^[:alnum:]_]|$)' || true)
        count=$((count + found))
    done < "$RUN_DIR/$label-log-baseline.tsv"
    printf '%s\n' "$count"
}

count_journal_error_messages() {
    # Kamailio uses "ERROR:" as well as bracketed native severities. Preserve
    # routing/AMQP failure checks without mistaking event identifiers for errors.
    awk 'BEGIN{IGNORECASE=1}
        /\[(err|crit|alert|emerg)\]|(^|[^[:alnum:]_])(error|fatal|crash|segfault|core dumped)([^[:alnum:]_]|$)|badmatch|no amqp connection available|timeout after .* receiving route response|no available handlers/{count++}
        END{print count+0}'
}

stop_monitor() {
    : > "$MONITOR_STOP"
    wait "$MONITOR_PID" 2>/dev/null || true
}

core_count() {
    local output rc
    command -v coredumpctl >/dev/null 2>&1 || { printf 0; return; }
    # systemd returns status 1 when the journal contains no coredumps. Accept
    # only that explicit result; permission, journal, or query failures must
    # still fail the evidence gate.
    set +e
    output=$(LC_ALL=C coredumpctl --no-pager --no-legend list 2>&1)
    rc=$?
    set -e
    if ((rc == 1)) && [[ $output == 'No coredumps found.' ]]; then
        printf 0
        return 0
    fi
    if ((rc != 0)); then
        printf '%s\n' "$output" >&2
        return "$rc"
    fi
    awk 'END{print NR+0}' <<< "$output"
}

record_stage() {
    local label=$1 answered_target=$2 total_expected=$3 caller_stats=$4 agent_count=$5 cores_before=$6 since=$7 excess_stats=${8:-}
    local verified_hold=${9:-0}
    local cs cf as af peak min_mem errors file_errors cores_after new_cores
    cs=$(stat_value "$caller_stats" 'SuccessfulCall(C)'); cf=$(stat_value "$caller_stats" 'FailedCall(C)')
    if [[ -n $excess_stats ]]; then
        cs=$((cs + $(stat_value "$excess_stats" 'SuccessfulCall(C)')))
        cf=$((cf + $(stat_value "$excess_stats" 'FailedCall(C)')))
    fi
    read -r as af < <(agent_stats_totals "$label" "$agent_count") || die "$label agent counters missing"
    peak=$(awk 'BEGIN{m=0} $2>m{m=$2} END{print m}' "$MONITOR_FILE")
    min_mem=$(awk 'NR==1{m=$3} $3<m{m=$3} END{print m+0}' "$MONITOR_FILE")
    errors=$(journalctl -q --since "@$since" --no-pager -o json \
        -u kazoo-apps -u kazoo-ecallmgr -u kazoo-freeswitch -u kazoo-kamailio \
        -u rabbitmq-server -u couchdb 2>/dev/null |
        jq -r '.MESSAGE | if type == "array" then implode elif type == "string" then . else empty end' |
        count_journal_error_messages)
    file_errors=$(new_error_log_matches "$label")
    cores_after=$(core_count); new_cores=$((cores_after - cores_before)); ((new_cores >= 0)) || new_cores=0
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$label" "$answered_target/$total_expected" "$cs" "$cf" "$as" "$af" "$peak" "$min_mem" "$errors/$file_errors" "$new_cores" "$verified_hold" >> "$RUN_DIR/summary.tsv"
    ((errors == 0 && file_errors == 0)) || die "$label generated fresh service/file log errors ($errors/$file_errors)"
    ((new_cores == 0)) || die "$label generated $new_cores new core dump(s)"
}

run_functional() {
    local label=functional caller_stats cores_before since
    log 'Functional: proving queue wait before endpoint availability'
    STATUS_AGENT_MAX=${STATE[ACCEPTANCE_AGENT_COUNT]}
    agent_status logout 1 "$STATUS_AGENT_MAX"
    negative_registration_test "$label"
    cores_before=$(core_count); since=$(date +%s); capture_log_baseline "$label"; start_monitor "$label"; start_rtp_capture "$label"
    register_caller "$label" "$CALLER_PORT"
    start_callers "$label" 1 "$CALLER_PORT" "$CALLER_MEDIA_MIN" "$CALLER_MEDIA_MAX" "$FUNCTIONAL_HOLD_MS"
    wait_answered_calls "$RUN_DIR/$label-caller-stats.csv" 1 ||
        die 'Caller did not receive the ACDC answer/hold while the agent was logged out'
    register_agents "$label" 1
    start_agent_uas "$label" 1 0
    agent_status login 1 1
    # The status helper waits for ACDC convergence. A short functional call can
    # complete while that request is still polling, so accept either the live
    # leg or SIPp's cumulative successful-leg proof. Stress stages retain the
    # stricter simultaneous CurrentCall assertion below.
    wait_agent_observed_answer "$label" 1 || die 'Agent did not ring and answer the queued call'
    wait_checked "$label caller" "$CALLER_PID"
    wait_agents_checked "$label"
    stop_rtp_capture; stop_monitor
    caller_stats=$RUN_DIR/$label-caller-stats.csv
    assert_stats "$label caller/RTP" "$caller_stats" 1
    assert_agent_stats "$label" 1 1
    assert_rtp_capture "$label" 1 1
    agent_status verify 1 1
    wait_agent_ready 1 || die 'Agent did not return to ready/idle after the functional call'
    record_stage "$label" 1 1 "$caller_stats" 1 "$cores_before" "$since"
    log 'Functional PASS: wait, ring, answer, bidirectional RTP check, BYE, and idle'
}

run_stress_stage() {
    local count=$1 excess=${2:-0}
    local label=answered-$count expected=$((count + excess))
    local cores_before since caller_stats hold_ms verified_hold=0
    if ((excess > 0)); then
        log "Stress stage: $count simultaneous answered ACDC calls plus $excess queued excess"
    else
        log "Stress stage: $count simultaneous answered ACDC calls"
    fi
    STATUS_AGENT_MAX=${STATE[ACCEPTANCE_AGENT_COUNT]}
    agent_status logout 1 "$STATUS_AGENT_MAX"
    agent_status login 1 "$count"
    cores_before=$(core_count); since=$(date +%s); capture_log_baseline "$label"; start_monitor "$label"; start_rtp_capture "$label"
    register_agents "$label" "$count"
    start_agent_uas "$label" "$count" "$excess"
    register_caller "$label" "$CALLER_PORT"
    if ((count == MAX_ANSWERED_CALLS)); then hold_ms=$CAPACITY_HOLD_MS; else hold_ms=$STAGE_HOLD_MS; fi
    # All calls share the caller's registered source tuple. This avoids a
    # second contact for the same AOR replacing the first and invalidating its
    # registered-source authorization at Kamailio.
    start_callers "$label" "$expected" "$CALLER_PORT" "$CALLER_MEDIA_MIN" "$CALLER_MEDIA_MAX" \
        "$hold_ms" "$count" "$QUEUED_EXCESS_HOLD_MS" \
        "$((excess > 0 ? QUEUED_EXCESS_DELAY_MS : 0))"
    MAIN_CALLER_PID=$CALLER_PID
    wait_concurrent_call_legs "$label" "$count" "$expected" ||
        die "$label did not simultaneously hold $expected caller legs and $count answered agent legs"
    if ((count == MAX_ANSWERED_CALLS)); then
        hold_concurrent_call_legs "$label" "$count" "$expected" "$CAPACITY_SOAK_SECONDS" ||
            die "$label did not sustain $expected caller legs and $count answered agent legs for ${CAPACITY_SOAK_SECONDS}s"
        verified_hold=$CAPACITY_SOAK_SECONDS
    fi
    if ((excess > 0)); then
        # ACDC consumes member messages from RabbitMQ immediately and tracks
        # them in its queue-manager state, so broker depth is not a member-wait
        # metric. All caller legs receiving 200 while only `count` agent legs
        # are active proves the excess legs were accepted and held by ACDC.
        wait_answered_calls "$RUN_DIR/$label-caller-stats.csv" "$expected" ||
            die "$label did not answer/hold all $excess excess callers while $count agents were busy"
    fi
    wait_checked "$label caller" "$MAIN_CALLER_PID"
    if ((excess > 0)); then
        stop_waiting_agents_checked "$label"
    else
        wait_agents_checked "$label"
    fi
    stop_rtp_capture; stop_monitor
    caller_stats=$RUN_DIR/$label-caller-stats.csv
    assert_stats "$label caller/RTP" "$caller_stats" "$expected"
    assert_agent_stats "$label" "$count" "$expected"
    assert_rtp_capture "$label" "$count" "$expected"
    agent_status verify 1 "$count"
    wait_agents_ready "$count" || die "$label agents did not all return to ready/idle"
    record_stage "$label" "$count" "$expected" "$caller_stats" "$count" "$cores_before" "$since" '' "$verified_hold"
    log "Stress PASS: $count concurrent answered calls, exact SIP counters, and RTP"
}

cleanup() {
    local exit_code=$? pid
    [[ $CLEANING_UP == false ]] || return
    CLEANING_UP=true
    for pid in "${ACTIVE_PIDS[@]}"; do
        if [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null || true; fi
    done
    for pid in "${ACTIVE_PIDS[@]}"; do
        if [[ $pid =~ ^[0-9]+$ ]]; then wait "$pid" 2>/dev/null || true; fi
    done
    # A failed assertion terminates SIPp before it can send BYE. Clear only
    # channels whose Call-ID suffix contains this run's caller PID and source
    # IP; bridged agent legs then clear through normal FreeSWITCH linkage.
    best_effort_clear_acceptance_calls
    if [[ $LIVE == true && -n $RUN_DIR && ${#STATE[@]} -gt 0 ]]; then
        if ((AGENTS_REGISTERED > 0)); then best_effort_deregister_agents "$AGENTS_REGISTERED"; fi
        if [[ $CALLER_REGISTERED == true ]]; then
            best_effort_deregister_caller "$CALLER_PORT" cleanup-main
        fi
        if ((STATUS_AGENT_MAX > 0)); then
            agent_status logout 1 "$STATUS_AGENT_MAX" >/dev/null 2>&1 || true
        fi
    fi
    find "${RUN_DIR:-/nonexistent}" -maxdepth 1 -type f -name '*-input.csv' -delete 2>/dev/null || true
    return "$exit_code"
}

main() {
    local stage last_stage
    umask 077
    ((EUID == 0)) || die 'Run as root to protect credentials and acceptance logs'
    parse_args "$@"
    load_state
    validate_state
    validate_stages
    ensure_sipp
    validate_scenarios
    resolve_local_ip
    if [[ $MODE == prepare ]]; then
        log "PASS: protected state and SIPp ${SIPP_VERSION} scenarios are ready; no SIP traffic sent"
        return 0
    fi
    [[ $LIVE == true ]] || die 'Live SIP traffic is gated; rerun with --live after the ALL deployment is healthy'
    create_run_dir
    trap cleanup EXIT INT TERM
    if [[ $MODE == registration-probe ]]; then
        register_agents registration-probe 1
        log 'Registration probe is active for 60 seconds'
        sleep 60
        log 'Registration probe complete; cleanup will deregister agent 1'
        return 0
    fi
    [[ $MODE == functional || $MODE == all ]] && run_functional
    if [[ $MODE == stress || $MODE == all ]]; then
        last_stage=${STAGE_LIST[$((${#STAGE_LIST[@]} - 1))]}
        for stage in "${STAGE_LIST[@]}"; do
            if ((stage == last_stage)); then run_stress_stage "$stage" "$QUEUED_EXCESS"
            else run_stress_stage "$stage" 0
            fi
        done
    fi
    log "PASS: completed requested ACDC SIP/RTP tests; protected results: $RUN_DIR"
}

if [[ ${KAZOO_CALLS_LIBRARY:-false} != true ]]; then
    main "$@"
fi
