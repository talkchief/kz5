#!/usr/bin/env bash
# Provision and verify an isolated internal-call/ACDC acceptance tenant.
# This script never deletes or modifies resources outside the IDs in its
# root-only state file.
# shellcheck disable=SC1091,SC2034
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# Pass a private sentinel so installer option parsing is not influenced by this
# script's arguments while still loading the saved deployment configuration.
source "$script_dir/install-kazoo5.sh" __acceptance_provisioner__

ACCEPTANCE_STATE_FILE=${KAZOO_ACCEPTANCE_STATE_FILE:-/etc/kazoo/acceptance-secrets.env}
readonly ACCEPTANCE_API_BASE=http://127.0.0.1:8000/v2
readonly ACCEPTANCE_MAX_AGENT_COUNT=30
readonly ACCEPTANCE_CALLER_EXTENSION_EXPECTED=1001
readonly ACCEPTANCE_FIRST_AGENT_EXTENSION=1002
readonly ACCEPTANCE_QUEUE_EXTENSION_EXPECTED=2000
readonly ACCEPTANCE_QUEUE_WAIT_SECONDS=600

mode=provision
status_action=
requested_agent_count=${KAZOO_ACCEPTANCE_AGENT_COUNT:-}
agent_range=
MASTER_TOKEN=
MASTER_ACCOUNT_ID=
declare -a ACCEPTANCE_STATE_KEYS=(
    ACCEPTANCE_ACCOUNT_ID ACCEPTANCE_ACCOUNT_NAME ACCEPTANCE_REALM
    ACCEPTANCE_CALLER_USER_ID ACCEPTANCE_CALLER_DEVICE_ID ACCEPTANCE_CALLER_CALLFLOW_ID
    ACCEPTANCE_CALLER_EXTENSION ACCEPTANCE_CALLER_SIP_USERNAME ACCEPTANCE_CALLER_SIP_PASSWORD
    ACCEPTANCE_QUEUE_ID ACCEPTANCE_QUEUE_CALLFLOW_ID ACCEPTANCE_QUEUE_EXTENSION
    ACCEPTANCE_AGENT_COUNT ACCEPTANCE_MAX_ANSWERED_CALLS
    ACCEPTANCE_SIP_PROXY_HOST ACCEPTANCE_SIP_PROXY_PORT ACCEPTANCE_SIP_TRANSPORT
)
for agent_index in {1..30}; do
    ACCEPTANCE_STATE_KEYS+=(
        "ACCEPTANCE_AGENT_${agent_index}_USER_ID"
        "ACCEPTANCE_AGENT_${agent_index}_DEVICE_ID"
        "ACCEPTANCE_AGENT_${agent_index}_CALLFLOW_ID"
        "ACCEPTANCE_AGENT_${agent_index}_EXTENSION"
        "ACCEPTANCE_AGENT_${agent_index}_SIP_USERNAME"
        "ACCEPTANCE_AGENT_${agent_index}_SIP_PASSWORD"
    )
done

usage_acceptance() {
    cat <<'EOF'
Usage: sudo ./scripts/test-kazoo-call-provision.sh [OPTION]

Provision or converge one isolated acceptance tenant containing caller 1001,
agents 1002-1031, and ACDC queue 2000.

Options:
  --verify-only          Read-only validation of saved tenant resources
  --agent-count COUNT    Provision 1-30 agents (new tenants default to 30)
  --agent-status ACTION  Set acceptance agents to login, logout, or verify
  --agent-range START:END  Limit --agent-status to an indexed agent range
  -h, --help             Show this help

State and generated SIP credentials are stored as base64 values in
/etc/kazoo/acceptance-secrets.env, owned by root with mode 0600. The file is
data, not shell syntax; do not source it.
EOF
}

parse_acceptance_arguments() {
    while (($#)); do
        case $1 in
            --verify-only) mode=verify ;;
            --agent-status)
                (($# >= 2)) || die '--agent-status requires login, logout, or verify'
                status_action=$2
                [[ $status_action == login || $status_action == logout || $status_action == verify ]] || \
                    die '--agent-status requires login, logout, or verify'
                mode=status
                shift
                ;;
            --agent-count)
                (($# >= 2)) || die '--agent-count requires an integer from 1 to 30'
                requested_agent_count=$2
                shift
                ;;
            --agent-range)
                (($# >= 2)) || die '--agent-range requires START:END'
                agent_range=$2
                shift
                ;;
            -h|--help) usage_acceptance; exit 0 ;;
            *) die "Unknown acceptance provisioner option: $1" ;;
        esac
        shift
    done
    if [[ -n $requested_agent_count ]]; then
        if [[ ! $requested_agent_count =~ ^[1-9][0-9]*$ ]] || \
           ((requested_agent_count > ACCEPTANCE_MAX_AGENT_COUNT)); then
            die '--agent-count must be an integer from 1 to 30'
        fi
    fi
}

state_key_allowed() {
    local requested=$1 key
    for key in "${ACCEPTANCE_STATE_KEYS[@]}"; do
        [[ $requested == "$key" ]] && return 0
    done
    return 1
}

load_acceptance_state() {
    local line key encoded value owner file_mode
    [[ -e $ACCEPTANCE_STATE_FILE || -L $ACCEPTANCE_STATE_FILE ]] || return 0
    [[ -f $ACCEPTANCE_STATE_FILE && ! -L $ACCEPTANCE_STATE_FILE ]] || \
        die 'Acceptance state must be a regular file, not a symlink'
    read -r owner file_mode < <(stat -c '%u %a' "$ACCEPTANCE_STATE_FILE")
    [[ $owner == 0 && $file_mode == 600 ]] || \
        die 'Acceptance state must be owned by root with mode 0600'
    [[ -r $ACCEPTANCE_STATE_FILE ]] || die "Cannot read acceptance state: ${ACCEPTANCE_STATE_FILE}"
    while IFS= read -r line || [[ -n $line ]]; do
        [[ -n $line && $line != \#* ]] || continue
        [[ $line == *=* ]] || die 'Malformed line in acceptance state'
        key=${line%%=*}
        encoded=${line#*=}
        [[ -n $key ]] || die 'Malformed key in acceptance state'
        state_key_allowed "$key" || die "Unknown key in acceptance state: ${key}"
        value=$(printf '%s' "$encoded" | base64 --decode) || \
            die "Invalid base64 value in acceptance state for ${key}"
        printf -v "$key" '%s' "$value"
    done < "$ACCEPTANCE_STATE_FILE"
}

resolve_requested_agent_count() {
    if [[ -z $requested_agent_count ]]; then
        requested_agent_count=${ACCEPTANCE_AGENT_COUNT:-30}
    fi
}

save_acceptance_state() {
    local key
    {
        printf '# Kazoo internal-call acceptance state; base64 values; do not source\n'
        for key in "${ACCEPTANCE_STATE_KEYS[@]}"; do
            printf '%s=' "$key"
            printf '%s' "${!key-}" | base64 -w0
            printf '\n'
        done
    } | write_file 0600 "$ACCEPTANCE_STATE_FILE"
}

initialize_acceptance_state() {
    local suffix agent_index extension
    if [[ -z ${ACCEPTANCE_REALM:-} ]]; then
        [[ $mode == provision ]] || die "No acceptance state exists at ${ACCEPTANCE_STATE_FILE}"
        suffix=$(openssl rand -hex 6)
        ACCEPTANCE_ACCOUNT_ID=
        ACCEPTANCE_ACCOUNT_NAME="Kazoo5 Acceptance ${suffix}"
        ACCEPTANCE_REALM="acceptance-${suffix}.invalid"
        ACCEPTANCE_CALLER_USER_ID=
        ACCEPTANCE_CALLER_DEVICE_ID=
        ACCEPTANCE_CALLER_CALLFLOW_ID=
        ACCEPTANCE_CALLER_EXTENSION=$ACCEPTANCE_CALLER_EXTENSION_EXPECTED
        ACCEPTANCE_CALLER_SIP_USERNAME=acceptance1001
        ACCEPTANCE_CALLER_SIP_PASSWORD=$(openssl rand -hex 16)
        ACCEPTANCE_QUEUE_ID=
        ACCEPTANCE_QUEUE_CALLFLOW_ID=
        ACCEPTANCE_QUEUE_EXTENSION=$ACCEPTANCE_QUEUE_EXTENSION_EXPECTED
        ACCEPTANCE_AGENT_COUNT=$requested_agent_count
        ACCEPTANCE_MAX_ANSWERED_CALLS=$requested_agent_count
        ACCEPTANCE_SIP_PROXY_HOST=${KAZOO_PUBLIC_IP:-}
        [[ -n $ACCEPTANCE_SIP_PROXY_HOST ]] || \
            ACCEPTANCE_SIP_PROXY_HOST=$(ip -4 route get 1.1.1.1 | \
                awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')
        ACCEPTANCE_SIP_PROXY_PORT=5060
        ACCEPTANCE_SIP_TRANSPORT=udp
        for ((agent_index = 1; agent_index <= ACCEPTANCE_AGENT_COUNT; agent_index++)); do
            extension=$((ACCEPTANCE_FIRST_AGENT_EXTENSION + agent_index - 1))
            printf -v "ACCEPTANCE_AGENT_${agent_index}_USER_ID" '%s' ''
            printf -v "ACCEPTANCE_AGENT_${agent_index}_DEVICE_ID" '%s' ''
            printf -v "ACCEPTANCE_AGENT_${agent_index}_CALLFLOW_ID" '%s' ''
            printf -v "ACCEPTANCE_AGENT_${agent_index}_EXTENSION" '%s' "$extension"
            printf -v "ACCEPTANCE_AGENT_${agent_index}_SIP_USERNAME" '%s' "acceptance${extension}"
            printf -v "ACCEPTANCE_AGENT_${agent_index}_SIP_PASSWORD" '%s' "$(openssl rand -hex 16)"
        done
        save_acceptance_state
        log "Created protected acceptance state at ${ACCEPTANCE_STATE_FILE}"
    fi
}

expand_acceptance_agents() {
    local previous_count agent_index extension
    [[ ${ACCEPTANCE_AGENT_COUNT:-} =~ ^[1-9][0-9]*$ ]] || return 0
    previous_count=$ACCEPTANCE_AGENT_COUNT
    ((requested_agent_count > previous_count)) || return 0
    [[ $mode == provision ]] || \
        die "Acceptance state has ${previous_count} agents; provision ${requested_agent_count} before using that range"
    for ((agent_index = previous_count + 1; agent_index <= requested_agent_count; agent_index++)); do
        extension=$((ACCEPTANCE_FIRST_AGENT_EXTENSION + agent_index - 1))
        printf -v "ACCEPTANCE_AGENT_${agent_index}_USER_ID" '%s' ''
        printf -v "ACCEPTANCE_AGENT_${agent_index}_DEVICE_ID" '%s' ''
        printf -v "ACCEPTANCE_AGENT_${agent_index}_CALLFLOW_ID" '%s' ''
        printf -v "ACCEPTANCE_AGENT_${agent_index}_EXTENSION" '%s' "$extension"
        printf -v "ACCEPTANCE_AGENT_${agent_index}_SIP_USERNAME" '%s' "acceptance${extension}"
        printf -v "ACCEPTANCE_AGENT_${agent_index}_SIP_PASSWORD" '%s' "$(openssl rand -hex 16)"
    done
    ACCEPTANCE_AGENT_COUNT=$requested_agent_count
    ACCEPTANCE_MAX_ANSWERED_CALLS=$requested_agent_count
    save_acceptance_state
    log "Expanded the protected acceptance tenant state from ${previous_count} to ${requested_agent_count} agents"
}

validate_acceptance_state() {
    local key value agent_index extension
    [[ $ACCEPTANCE_STATE_FILE == /* && $ACCEPTANCE_STATE_FILE != / && \
       ! $ACCEPTANCE_STATE_FILE =~ [[:cntrl:]] ]] || \
        die 'KAZOO_ACCEPTANCE_STATE_FILE must be an absolute file path'
    [[ ${ACCEPTANCE_ACCOUNT_NAME:-} =~ ^Kazoo5\ Acceptance\ [a-f0-9]{12}$ ]] || \
        die 'Acceptance account name in state is invalid'
    [[ ${ACCEPTANCE_REALM:-} =~ ^acceptance-[a-f0-9]{12}\.invalid$ ]] || \
        die 'Acceptance realm in state is invalid'
    [[ ${ACCEPTANCE_CALLER_EXTENSION:-} == "$ACCEPTANCE_CALLER_EXTENSION_EXPECTED" && \
       ${ACCEPTANCE_QUEUE_EXTENSION:-} == "$ACCEPTANCE_QUEUE_EXTENSION_EXPECTED" ]] || \
        die 'Acceptance state does not contain the fixed caller and queue extensions'
    if [[ ! ${ACCEPTANCE_AGENT_COUNT:-} =~ ^[1-9][0-9]*$ ]] || \
       ((ACCEPTANCE_AGENT_COUNT > ACCEPTANCE_MAX_AGENT_COUNT)); then
        die 'Acceptance state agent count must be from 1 to 30'
    fi
    [[ ${ACCEPTANCE_MAX_ANSWERED_CALLS:-} == "$ACCEPTANCE_AGENT_COUNT" ]] || \
        die 'Acceptance maximum answered calls must match its agent count'
    [[ ${ACCEPTANCE_SIP_PROXY_HOST:-} =~ ^[a-zA-Z0-9._-]+$ ]] || \
        die 'Acceptance SIP proxy host is invalid'
    [[ ${ACCEPTANCE_SIP_PROXY_PORT:-} == 5060 && ${ACCEPTANCE_SIP_TRANSPORT:-} == udp ]] || \
        die 'Acceptance SIP transport must be UDP port 5060'
    for key in ACCEPTANCE_CALLER_SIP_USERNAME ACCEPTANCE_CALLER_SIP_PASSWORD; do
        value=${!key:-}
        [[ $value =~ ^[a-zA-Z0-9_-]{5,32}$ ]] || die "Invalid acceptance credential field: ${key}"
    done
    for key in ACCEPTANCE_ACCOUNT_ID ACCEPTANCE_CALLER_USER_ID ACCEPTANCE_CALLER_DEVICE_ID \
        ACCEPTANCE_CALLER_CALLFLOW_ID ACCEPTANCE_QUEUE_ID ACCEPTANCE_QUEUE_CALLFLOW_ID; do
        value=${!key:-}
        [[ -z $value || $value =~ ^[a-f0-9]{32}$ ]] || die "Invalid acceptance resource ID: ${key}"
    done
    for ((agent_index = 1; agent_index <= ACCEPTANCE_AGENT_COUNT; agent_index++)); do
        extension=$((ACCEPTANCE_FIRST_AGENT_EXTENSION + agent_index - 1))
        key="ACCEPTANCE_AGENT_${agent_index}_EXTENSION"
        [[ ${!key:-} == "$extension" ]] || die "Acceptance agent ${agent_index} extension is invalid"
        for key in "ACCEPTANCE_AGENT_${agent_index}_SIP_USERNAME" \
            "ACCEPTANCE_AGENT_${agent_index}_SIP_PASSWORD"; do
            value=${!key:-}
            [[ $value =~ ^[a-zA-Z0-9_-]{5,32}$ ]] || die "Invalid acceptance credential field: ${key}"
        done
        for key in "ACCEPTANCE_AGENT_${agent_index}_USER_ID" \
            "ACCEPTANCE_AGENT_${agent_index}_DEVICE_ID" \
            "ACCEPTANCE_AGENT_${agent_index}_CALLFLOW_ID"; do
            value=${!key:-}
            [[ -z $value || $value =~ ^[a-f0-9]{32}$ ]] || die "Invalid acceptance resource ID: ${key}"
        done
    done
}

resolve_agent_range() {
    if [[ -z $agent_range ]]; then
        AGENT_RANGE_START=1
        AGENT_RANGE_END=$ACCEPTANCE_AGENT_COUNT
        return 0
    fi
    [[ $agent_range =~ ^([1-9][0-9]*):([1-9][0-9]*)$ ]] || \
        die '--agent-range must use START:END with positive integers'
    AGENT_RANGE_START=${BASH_REMATCH[1]}
    AGENT_RANGE_END=${BASH_REMATCH[2]}
    ((AGENT_RANGE_START <= AGENT_RANGE_END && AGENT_RANGE_END <= ACCEPTANCE_AGENT_COUNT)) || \
        die '--agent-range is outside the provisioned acceptance agent count'
}

authenticate_master() {
    local credential_hash auth_body
    KAZOO_HOSTNAME=$(hostname -f 2>/dev/null || hostname)
    VERIFY_ONLY=true
    load_or_create_master_credentials
    [[ -n $KAZOO_MASTER_ADMIN_PASSWORD ]] || die 'Existing Kazoo master credentials are required'
    credential_hash=$(printf '%s:%s' "$KAZOO_MASTER_ADMIN_USER" "$KAZOO_MASTER_ADMIN_PASSWORD" | \
        md5sum | cut -d' ' -f1)
    auth_body=$(printf '{"data":{"credentials":"%s","method":"md5","realm":"%s"}}' \
        "$credential_hash" "$KAZOO_MASTER_ACCOUNT_REALM" | \
        curl --fail --silent --show-error --connect-timeout 5 --max-time 30 \
            -X PUT -H 'Content-Type: application/json' --data-binary @- \
            "$ACCEPTANCE_API_BASE/user_auth") || die 'Crossbar master login failed'
    MASTER_TOKEN=$(jq -er '.auth_token | select(type == "string" and length > 0)' <<<"$auth_body") || \
        die 'Crossbar master login returned no token'
    MASTER_ACCOUNT_ID=$(jq -er '.data.account_id | select(test("^[a-f0-9]{32}$"))' <<<"$auth_body") || \
        die 'Crossbar master login returned an invalid account ID'
    [[ $MASTER_TOKEN =~ ^[a-zA-Z0-9._-]+$ ]] || die 'Crossbar returned an invalid token'
}

preflight_acceptance_runtime() {
    local unit listeners
    for unit in kazoo-apps.service kazoo-ecallmgr.service kazoo-freeswitch.service \
        kazoo-kamailio.service; do
        systemctl is-active --quiet "$unit" || die "Required local service is not active: ${unit}"
    done
    listeners=$(ss -H -lun 'sport = :5060' 2>/dev/null || true)
    grep -F "${ACCEPTANCE_SIP_PROXY_HOST}:${ACCEPTANCE_SIP_PROXY_PORT}" <<<"$listeners" >/dev/null || \
        die "Kazoo Kamailio is not listening on ${ACCEPTANCE_SIP_PROXY_HOST}:${ACCEPTANCE_SIP_PROXY_PORT}/udp"
}

acceptance_api() {
    local method=$1 path=$2 body=${3-} response
    if (($# >= 3)); then
        response=$(printf '%s' "$body" | curl --config <(printf 'header = "X-Auth-Token: %s"\n' "$MASTER_TOKEN") \
            --fail --silent --show-error --connect-timeout 5 --max-time 60 \
            -X "$method" -H 'Content-Type: application/json' --data-binary @- \
            "$ACCEPTANCE_API_BASE/$path") || die "Crossbar ${method} failed for ${path}"
    else
        response=$(curl --config <(printf 'header = "X-Auth-Token: %s"\n' "$MASTER_TOKEN") \
            --fail --silent --show-error --connect-timeout 5 --max-time 60 \
            -X "$method" -H 'Content-Type: application/json' \
            "$ACCEPTANCE_API_BASE/$path") || die "Crossbar ${method} failed for ${path}"
    fi
    jq -e '.status == "success"' <<<"$response" >/dev/null || \
        die "Crossbar ${method} did not return success for ${path}"
    printf '%s' "$response"
}

set_resource_id() {
    local key=$1 response=$2 resource_id
    resource_id=$(jq -er '.data.id | select(test("^[a-f0-9]{32}$"))' <<<"$response") || \
        die "Crossbar did not return a valid ID for ${key}"
    printf -v "$key" '%s' "$resource_id"
    save_acceptance_state
}

upsert_resource() {
    local collection=$1 id_key=$2 identity_field=$3 identity_value=$4 body=$5
    local resource_id=${!id_key:-} response
    if [[ -z $resource_id ]]; then
        response=$(acceptance_api PUT "accounts/$ACCEPTANCE_ACCOUNT_ID/$collection" "$body")
        set_resource_id "$id_key" "$response"
        return 0
    fi
    response=$(acceptance_api GET "accounts/$ACCEPTANCE_ACCOUNT_ID/$collection/$resource_id")
    jq -e --arg field "$identity_field" --arg expected "$identity_value" \
        '.data[$field] == $expected' <<<"$response" >/dev/null || \
        die "Refusing to modify unexpected acceptance resource ${resource_id}"
    response=$(acceptance_api POST "accounts/$ACCEPTANCE_ACCOUNT_ID/$collection/$resource_id" "$body")
    [[ $(jq -r '.data.id' <<<"$response") == "$resource_id" ]] || \
        die "Crossbar changed the ID while updating ${resource_id}"
}

ensure_acceptance_account() {
    local body response
    body=$(printf '{"data":{"name":"%s","realm":"%s","enabled":true}}' \
        "$ACCEPTANCE_ACCOUNT_NAME" "$ACCEPTANCE_REALM")
    if [[ -z $ACCEPTANCE_ACCOUNT_ID ]]; then
        response=$(acceptance_api PUT "accounts/$MASTER_ACCOUNT_ID" "$body")
        set_resource_id ACCEPTANCE_ACCOUNT_ID "$response"
        return 0
    fi
    response=$(acceptance_api GET "accounts/$ACCEPTANCE_ACCOUNT_ID")
    jq -e --arg name "$ACCEPTANCE_ACCOUNT_NAME" --arg realm "$ACCEPTANCE_REALM" \
        '.data.name == $name and .data.realm == $realm' <<<"$response" >/dev/null || \
        die 'Saved acceptance account ID does not match the isolated tenant'
}

provision_acceptance_resources() {
    local body agent_index extension username password id_key user_id queue_agents=
    body='{"data":{"first_name":"Acceptance","last_name":"Caller","enabled":true,"priv_level":"user"}}'
    upsert_resource users ACCEPTANCE_CALLER_USER_ID last_name Caller "$body"
    body=$(printf '{"data":{"name":"Acceptance Caller 1001","owner_id":"%s","enabled":true,"device_type":"softphone","sip":{"method":"password","username":"%s","password":"%s","transport":"udp","expire_seconds":300}}}' \
        "$ACCEPTANCE_CALLER_USER_ID" "$ACCEPTANCE_CALLER_SIP_USERNAME" "$ACCEPTANCE_CALLER_SIP_PASSWORD")
    upsert_resource devices ACCEPTANCE_CALLER_DEVICE_ID name 'Acceptance Caller 1001' "$body"

    for ((agent_index = 1; agent_index <= ACCEPTANCE_AGENT_COUNT; agent_index++)); do
        extension=$((ACCEPTANCE_FIRST_AGENT_EXTENSION + agent_index - 1))
        id_key="ACCEPTANCE_AGENT_${agent_index}_USER_ID"
        body=$(printf '{"data":{"first_name":"Acceptance","last_name":"Agent %s","enabled":true,"priv_level":"user"}}' \
            "$extension")
        upsert_resource users "$id_key" last_name "Agent ${extension}" "$body"
        user_id=${!id_key}
        id_key="ACCEPTANCE_AGENT_${agent_index}_DEVICE_ID"
        password="ACCEPTANCE_AGENT_${agent_index}_SIP_PASSWORD"
        username="ACCEPTANCE_AGENT_${agent_index}_SIP_USERNAME"
        body=$(printf '{"data":{"name":"Acceptance Agent %s","owner_id":"%s","enabled":true,"device_type":"softphone","sip":{"method":"password","username":"%s","password":"%s","transport":"udp","expire_seconds":300}}}' \
            "$extension" "$user_id" "${!username}" "${!password}")
        upsert_resource devices "$id_key" name "Acceptance Agent ${extension}" "$body"
        [[ -z $queue_agents ]] || queue_agents+=,
        queue_agents+="\"${user_id}\""
    done

    # Excess load callers wait for the six-minute main conversations to finish.
    # The ordinary two-minute queue policy would deliberately time them out
    # before the capacity hold/drain assertions can complete.
    body=$(printf '{"data":{"name":"Acceptance Queue 2000","strategy":"round_robin","connection_timeout":%s,"agent_ring_timeout":20,"agent_wrapup_time":0,"enter_when_empty":true,"max_queue_size":100,"ring_simultaneously":%s,"record_caller":false}}' \
        "$ACCEPTANCE_QUEUE_WAIT_SECONDS" "$ACCEPTANCE_AGENT_COUNT")
    upsert_resource queues ACCEPTANCE_QUEUE_ID name 'Acceptance Queue 2000' "$body"
    acceptance_api POST "accounts/$ACCEPTANCE_ACCOUNT_ID/queues/$ACCEPTANCE_QUEUE_ID/roster" \
        "{\"data\":[${queue_agents}]}" >/dev/null

    body=$(printf '{"data":{"name":"Acceptance Caller 1001","numbers":["%s"],"owner_id":"%s","flow":{"module":"user","data":{"id":"%s"},"children":{}}}}' \
        "$ACCEPTANCE_CALLER_EXTENSION" "$ACCEPTANCE_CALLER_USER_ID" "$ACCEPTANCE_CALLER_USER_ID")
    upsert_resource callflows ACCEPTANCE_CALLER_CALLFLOW_ID name 'Acceptance Caller 1001' "$body"
    for ((agent_index = 1; agent_index <= ACCEPTANCE_AGENT_COUNT; agent_index++)); do
        extension=$((ACCEPTANCE_FIRST_AGENT_EXTENSION + agent_index - 1))
        id_key="ACCEPTANCE_AGENT_${agent_index}_USER_ID"
        user_id=${!id_key}
        id_key="ACCEPTANCE_AGENT_${agent_index}_CALLFLOW_ID"
        body=$(printf '{"data":{"name":"Acceptance Agent %s","numbers":["%s"],"owner_id":"%s","flow":{"module":"user","data":{"id":"%s"},"children":{}}}}' \
            "$extension" "$extension" "$user_id" "$user_id")
        upsert_resource callflows "$id_key" name "Acceptance Agent ${extension}" "$body"
    done
    body=$(printf '{"data":{"name":"Acceptance Queue 2000","numbers":["%s"],"flow":{"module":"acdc_member","data":{"id":"%s"},"children":{}}}}' \
        "$ACCEPTANCE_QUEUE_EXTENSION" "$ACCEPTANCE_QUEUE_ID")
    upsert_resource callflows ACCEPTANCE_QUEUE_CALLFLOW_ID name 'Acceptance Queue 2000' "$body"
}

verify_acceptance_queue_wait() {
    local response
    response=$(acceptance_api GET "accounts/$ACCEPTANCE_ACCOUNT_ID/queues/$ACCEPTANCE_QUEUE_ID")
    jq -e --arg id "$ACCEPTANCE_QUEUE_ID" --argjson minimum "$ACCEPTANCE_QUEUE_WAIT_SECONDS" '
        .data.id == $id and .data.name == "Acceptance Queue 2000"
        and (.data.connection_timeout | type == "number")
        and .data.connection_timeout >= $minimum' <<<"$response" >/dev/null ||
        die 'Acceptance queue wait is too short or identity changed; converge the owned fixture with test-kazoo-call-provision.sh before live calls'
}

verify_acceptance_resources() {
    local response agent_index extension id_key user_id device_id callflow_id
    response=$(acceptance_api GET "accounts/$ACCEPTANCE_ACCOUNT_ID")
    jq -e --arg name "$ACCEPTANCE_ACCOUNT_NAME" --arg realm "$ACCEPTANCE_REALM" \
        '.data.name == $name and .data.realm == $realm' <<<"$response" >/dev/null || \
        die 'Acceptance tenant identity verification failed'
    response=$(acceptance_api GET "accounts/$ACCEPTANCE_ACCOUNT_ID/devices/$ACCEPTANCE_CALLER_DEVICE_ID")
    jq -e --arg owner "$ACCEPTANCE_CALLER_USER_ID" --arg sip "$ACCEPTANCE_CALLER_SIP_USERNAME" \
        '.data.owner_id == $owner and .data.sip.username == $sip' <<<"$response" >/dev/null || \
        die 'Acceptance caller device verification failed'
    response=$(acceptance_api GET "accounts/$ACCEPTANCE_ACCOUNT_ID/callflows/$ACCEPTANCE_CALLER_CALLFLOW_ID")
    jq -e --arg number "$ACCEPTANCE_CALLER_EXTENSION" --arg id "$ACCEPTANCE_CALLER_USER_ID" \
        '.data.numbers == [$number] and .data.flow.module == "user" and .data.flow.data.id == $id' \
        <<<"$response" >/dev/null || die 'Acceptance caller callflow verification failed'

    # Agent status operations call this verifier before changing state, hence
    # the call harness rejects stale short-wait fixtures before any SIP calls.
    verify_acceptance_queue_wait
    response=$(acceptance_api GET "accounts/$ACCEPTANCE_ACCOUNT_ID/queues/$ACCEPTANCE_QUEUE_ID/roster")
    for ((agent_index = 1; agent_index <= ACCEPTANCE_AGENT_COUNT; agent_index++)); do
        extension=$((ACCEPTANCE_FIRST_AGENT_EXTENSION + agent_index - 1))
        id_key="ACCEPTANCE_AGENT_${agent_index}_USER_ID"; user_id=${!id_key}
        id_key="ACCEPTANCE_AGENT_${agent_index}_DEVICE_ID"; device_id=${!id_key}
        id_key="ACCEPTANCE_AGENT_${agent_index}_CALLFLOW_ID"; callflow_id=${!id_key}
        jq -e --arg id "$user_id" '.data | index($id)' <<<"$response" >/dev/null || \
            die "Acceptance queue roster is missing agent ${extension}"
        acceptance_api GET "accounts/$ACCEPTANCE_ACCOUNT_ID/users/$user_id" | \
            jq -e --arg last_name "Agent ${extension}" '.data.last_name == $last_name' >/dev/null || \
            die "Acceptance agent ${extension} user verification failed"
        acceptance_api GET "accounts/$ACCEPTANCE_ACCOUNT_ID/devices/$device_id" | \
            jq -e --arg owner "$user_id" '.data.owner_id == $owner and .data.sip.method == "password"' >/dev/null || \
            die "Acceptance agent ${extension} device verification failed"
        acceptance_api GET "accounts/$ACCEPTANCE_ACCOUNT_ID/callflows/$callflow_id" | \
            jq -e --arg number "$extension" --arg id "$user_id" \
                '.data.numbers == [$number] and .data.flow.module == "user" and .data.flow.data.id == $id' >/dev/null || \
            die "Acceptance agent ${extension} callflow verification failed"
        acceptance_api GET "accounts/$ACCEPTANCE_ACCOUNT_ID/agents/$user_id/queue_status" | \
            jq -e --arg queue "$ACCEPTANCE_QUEUE_ID" '.data | index($queue)' >/dev/null || \
            die "Acceptance agent ${extension} queue membership verification failed"
    done
    acceptance_api GET "accounts/$ACCEPTANCE_ACCOUNT_ID/callflows/$ACCEPTANCE_QUEUE_CALLFLOW_ID" | \
        jq -e --arg number "$ACCEPTANCE_QUEUE_EXTENSION" --arg id "$ACCEPTANCE_QUEUE_ID" \
            '.data.numbers == [$number] and .data.flow.module == "acdc_member" and .data.flow.data.id == $id' >/dev/null || \
        die 'Acceptance queue callflow verification failed'
    log "PASS isolated caller, ${ACCEPTANCE_AGENT_COUNT} agents/devices, queue roster, and internal callflows"
}

agent_status_matches() {
    local response=$1 expected=$2
    if [[ $expected == login ]]; then
        jq -e 'if (.data | type) == "string" then
                   (.data == "login" or .data == "ready")
               else
                   (.data.status == "login" or .data.status == "ready")
               end' \
            <<<"$response" >/dev/null
    else
        jq -e 'if (.data | type) == "string" then
                   (.data == "logout" or .data == "logged_out")
               else
                   (.data.status == "logout" or .data.status == "logged_out")
               end' \
            <<<"$response" >/dev/null
    fi
}

set_all_agent_statuses() {
    local action=$1 agent_index id_key user_id response deadline pending
    for ((agent_index = AGENT_RANGE_START; agent_index <= AGENT_RANGE_END; agent_index++)); do
        id_key="ACCEPTANCE_AGENT_${agent_index}_USER_ID"; user_id=${!id_key}
        acceptance_api POST "accounts/$ACCEPTANCE_ACCOUNT_ID/agents/$user_id/status" \
            "{\"data\":{\"status\":\"${action}\"}}" >/dev/null
    done
    deadline=$((SECONDS + 90))
    while ((SECONDS < deadline)); do
        pending=0
        for ((agent_index = AGENT_RANGE_START; agent_index <= AGENT_RANGE_END; agent_index++)); do
            id_key="ACCEPTANCE_AGENT_${agent_index}_USER_ID"; user_id=${!id_key}
            response=$(acceptance_api GET "accounts/$ACCEPTANCE_ACCOUNT_ID/agents/$user_id/status")
            agent_status_matches "$response" "$action" || ((pending += 1))
        done
        ((pending == 0)) && {
            log "PASS acceptance agents ${AGENT_RANGE_START}:${AGENT_RANGE_END} report ${action}"
            return 0
        }
        sleep 2
    done
    die "Acceptance agents did not converge to ${action} status"
}

verify_acdc_runtime() {
    local queues agents agent_index id_key user_id
    queues=$(timeout 30 sup -e acdc_queues_sup queues_running </dev/null) || \
        die 'Could not inspect running ACDC queues'
    [[ $queues == *"$ACCEPTANCE_ACCOUNT_ID"* && $queues == *"$ACCEPTANCE_QUEUE_ID"* ]] || \
        die 'Acceptance ACDC queue worker is not running'
    agents=$(timeout 30 sup -e acdc_agents_sup agents_running </dev/null) || \
        die 'Could not inspect running ACDC agents'
    for ((agent_index = AGENT_RANGE_START; agent_index <= AGENT_RANGE_END; agent_index++)); do
        id_key="ACCEPTANCE_AGENT_${agent_index}_USER_ID"; user_id=${!id_key}
        [[ $agents == *"$ACCEPTANCE_ACCOUNT_ID"* && $agents == *"$user_id"* ]] || \
            die "Acceptance ACDC agent ${agent_index} worker is not running"
    done
    log "PASS ACDC queue and agents ${AGENT_RANGE_START}:${AGENT_RANGE_END} are running"
}

main_acceptance() {
    ((EUID == 0)) || die 'Run the acceptance provisioner as root'
    parse_acceptance_arguments "$@"
    for required_command in curl jq sup; do
        command -v "$required_command" >/dev/null || die "Required command is missing: ${required_command}"
    done
    load_acceptance_state
    resolve_requested_agent_count
    initialize_acceptance_state
    expand_acceptance_agents
    validate_acceptance_state
    resolve_agent_range
    preflight_acceptance_runtime
    authenticate_master
    if [[ $mode == provision ]]; then
        ensure_acceptance_account
        provision_acceptance_resources
        verify_acceptance_resources
        # Exercise both transitions, then leave every agent ready for the SIP
        # registration/call harness.
        AGENT_RANGE_START=1
        AGENT_RANGE_END=$ACCEPTANCE_AGENT_COUNT
        set_all_agent_statuses logout
        set_all_agent_statuses login
        verify_acdc_runtime
    elif [[ $mode == status ]]; then
        verify_acceptance_resources
        if [[ $status_action == verify ]]; then
            verify_acdc_runtime
        else
            set_all_agent_statuses "$status_action"
            [[ $status_action == login ]] && verify_acdc_runtime
        fi
    else
        verify_acceptance_resources
        log 'PASS acceptance provisioning state is reusable; status was not changed'
    fi
    log "Acceptance tenant is ready; protected SIP test data remains in ${ACCEPTANCE_STATE_FILE}"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main_acceptance "$@"
fi
