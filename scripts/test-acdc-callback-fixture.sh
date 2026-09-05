#!/usr/bin/env bash
# Converge or remove the account-local simulated carrier used by the ACDC
# callback acceptance test. This helper never sends SIP traffic or originates a
# call. It owns only explicitly marked resources in the isolated acceptance
# tenant and the two NANP fictional-use numbers below.
# shellcheck disable=SC1091,SC2034
set -Eeuo pipefail

callback_fixture_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
source "$callback_fixture_dir/install-kazoo5.sh" __acdc_callback_fixture__

readonly ACCEPTANCE_STATE_FILE=${KAZOO_ACCEPTANCE_STATE_FILE:-/etc/kazoo/acceptance-secrets.env}
readonly FIXTURE_STATE_FILE=${KAZOO_CALLBACK_FIXTURE_STATE_FILE:-/etc/kazoo/acceptance-callback-fixture.env}
readonly API_BASE=http://127.0.0.1:8000/v2
readonly CALLBACK_NUMBER=+12025550101
readonly OUTBOUND_CALLER_ID=+12025550100
readonly ENCODED_CALLBACK_NUMBER=%2B12025550101
readonly ENCODED_OUTBOUND_CALLER_ID=%2B12025550100
readonly CARRIER_IP=127.0.0.30
readonly CARRIER_PORT=16060
readonly FIXTURE_MARKER=kazoo-acdc-callback-local-v1

ACTION=verify
CANCEL_ORIGINAL_CALL_ID=
MASTER_TOKEN=
MASTER_ACCOUNT_ID=
ACCEPTANCE_ACCOUNT_ID=
ACCEPTANCE_CALLER_DEVICE_ID=
ACCEPTANCE_QUEUE_ID=
ACCEPTANCE_ACCOUNT_NAME=
ACCEPTANCE_QUEUE_EXTENSION=
FIXTURE_ACCOUNT_ID=
FIXTURE_RESOURCE_ID=
FIXTURE_ORIGINAL_QUEUE=

fixture_usage() {
    cat <<'EOF'
Usage: sudo ./scripts/test-acdc-callback-fixture.sh setup|verify|evidence|cleanup
       sudo ./scripts/test-acdc-callback-fixture.sh cancel-original CALL_ID

setup    Create an exact-prefix, account-local SIP resource on 127.0.0.30:16060,
         assign +12025550100/+12025550101 through knm_local, and enable callback
         settings on the isolated acceptance queue.
verify   Read-only validation of the saved fixture and its ownership markers.
evidence Read-only, secret-free durable callback projection for acceptance gates.
cleanup Restore the exact queue snapshot and delete only marked fixture objects.
cancel-original Cancel only the callback belonging to one exact SIPp caller ID.

The RFC 5733/NANP fictional-use numbers never leave this host. Setup and cleanup
require the root-owned acceptance and installer credential files. The state file
is base64 data (not shell syntax), root:root 0600, and contains no credentials.
EOF
}

fixture_die() { printf '[kazoo-callback-fixture] ERROR: %s\n' "$*" >&2; exit 1; }
fixture_log() { printf '[kazoo-callback-fixture] %s\n' "$*"; }

parse_fixture_args() {
    if (($# == 2)) && [[ $1 == cancel-original ]]; then
        [[ $2 =~ ^1-[1-9][0-9]*@127\.0\.0\.20$ ]] || fixture_die 'Unexpected local callback caller ID'
        ACTION=cancel-original
        CANCEL_ORIGINAL_CALL_ID=$2
        return
    fi
    (($# == 1)) || { fixture_usage; fixture_die 'Choose exactly setup, verify, evidence, or cleanup'; }
    case $1 in
        setup|verify|evidence|cleanup) ACTION=$1 ;;
        -h|--help) fixture_usage; exit 0 ;;
        *) fixture_usage; fixture_die "Unknown action: $1" ;;
    esac
}

validate_private_file() {
    local path=$1 owner mode
    [[ -f $path && ! -L $path ]] || fixture_die "Protected file is missing or not regular: $path"
    read -r owner mode < <(stat -Lc '%u %a' -- "$path")
    [[ $owner == 0 && $mode == 600 ]] || fixture_die "Protected file must be root:root 0600: $path"
}

load_acceptance_state() {
    local line key encoded value
    validate_private_file "$ACCEPTANCE_STATE_FILE"
    while IFS= read -r line || [[ -n $line ]]; do
        [[ -n $line && $line != \#* ]] || continue
        [[ $line == *=* ]] || fixture_die 'Malformed acceptance state line'
        key=${line%%=*}; encoded=${line#*=}
        case $key in
            ACCEPTANCE_ACCOUNT_ID|ACCEPTANCE_CALLER_DEVICE_ID|ACCEPTANCE_QUEUE_ID|ACCEPTANCE_ACCOUNT_NAME|ACCEPTANCE_QUEUE_EXTENSION) ;;
            *) continue ;;
        esac
        value=$(printf '%s' "$encoded" | base64 --decode 2>/dev/null) || fixture_die "Invalid acceptance state value: $key"
        [[ $value != *$'\n'* && $value != *$'\r'* ]] || fixture_die "Multiline acceptance state value: $key"
        printf -v "$key" '%s' "$value"
    done < "$ACCEPTANCE_STATE_FILE"
    [[ $ACCEPTANCE_ACCOUNT_ID =~ ^[a-f0-9]{32}$ && $ACCEPTANCE_CALLER_DEVICE_ID =~ ^[a-f0-9]{32}$ && \
       $ACCEPTANCE_QUEUE_ID =~ ^[a-f0-9]{32}$ ]] || fixture_die 'Acceptance tenant IDs are invalid'
    [[ $ACCEPTANCE_ACCOUNT_NAME =~ ^Kazoo5\ Acceptance\ [a-f0-9]{12}$ && $ACCEPTANCE_QUEUE_EXTENSION == 2000 ]] || \
        fixture_die 'Refusing a non-isolated acceptance tenant'
}

fixture_state_key_allowed() {
    case $1 in
        FIXTURE_ACCOUNT_ID|FIXTURE_RESOURCE_ID|FIXTURE_ORIGINAL_QUEUE) return 0 ;;
        *) return 1 ;;
    esac
}

load_fixture_state() {
    local line key encoded value
    [[ -e $FIXTURE_STATE_FILE || -L $FIXTURE_STATE_FILE ]] || return 0
    validate_private_file "$FIXTURE_STATE_FILE"
    while IFS= read -r line || [[ -n $line ]]; do
        [[ -n $line && $line != \#* ]] || continue
        [[ $line == *=* ]] || fixture_die 'Malformed callback fixture state line'
        key=${line%%=*}; encoded=${line#*=}
        fixture_state_key_allowed "$key" || fixture_die "Unknown callback fixture state key: $key"
        value=$(printf '%s' "$encoded" | base64 --decode 2>/dev/null) || fixture_die "Invalid callback fixture state value: $key"
        [[ $value != *$'\n'* && $value != *$'\r'* ]] || fixture_die "Multiline callback fixture state value: $key"
        printf -v "$key" '%s' "$value"
    done < "$FIXTURE_STATE_FILE"
    [[ -z $FIXTURE_ACCOUNT_ID || $FIXTURE_ACCOUNT_ID =~ ^[a-f0-9]{32}$ ]] || fixture_die 'Invalid fixture account ID'
    [[ -z $FIXTURE_RESOURCE_ID || $FIXTURE_RESOURCE_ID =~ ^[a-f0-9]{32}$ ]] || fixture_die 'Invalid fixture resource ID'
    [[ -z $FIXTURE_ORIGINAL_QUEUE ]] || jq -e 'type == "object"' <<<"$FIXTURE_ORIGINAL_QUEUE" >/dev/null || \
        fixture_die 'Invalid saved queue snapshot'
}

save_fixture_state() {
    {
        printf '# Kazoo ACDC callback acceptance fixture; base64 values; do not source\n'
        for key in FIXTURE_ACCOUNT_ID FIXTURE_RESOURCE_ID FIXTURE_ORIGINAL_QUEUE; do
            printf '%s=' "$key"
            printf '%s' "${!key}" | base64 -w0
            printf '\n'
        done
    } | write_file 0600 "$FIXTURE_STATE_FILE"
}

authenticate_master() {
    local credential_hash auth_body
    KAZOO_HOSTNAME=$(hostname -f 2>/dev/null || hostname)
    VERIFY_ONLY=true
    load_or_create_master_credentials
    [[ -n $KAZOO_MASTER_ADMIN_PASSWORD ]] || fixture_die 'Existing master credentials are required'
    credential_hash=$(printf '%s:%s' "$KAZOO_MASTER_ADMIN_USER" "$KAZOO_MASTER_ADMIN_PASSWORD" | md5sum | cut -d' ' -f1)
    auth_body=$(printf '{"data":{"credentials":"%s","method":"md5","realm":"%s"}}' \
        "$credential_hash" "$KAZOO_MASTER_ACCOUNT_REALM" | \
        curl --fail --silent --show-error --connect-timeout 5 --max-time 30 \
            -X PUT -H 'Content-Type: application/json' --data-binary @- "$API_BASE/user_auth") || \
        fixture_die 'Crossbar master login failed'
    MASTER_TOKEN=$(jq -er '.auth_token | select(type == "string" and length > 0)' <<<"$auth_body") || \
        fixture_die 'Crossbar master login returned no token'
    MASTER_ACCOUNT_ID=$(jq -er '.data.account_id | select(test("^[a-f0-9]{32}$"))' <<<"$auth_body") || \
        fixture_die 'Crossbar master login returned invalid account ID'
    [[ $MASTER_TOKEN =~ ^[A-Za-z0-9._-]+$ ]] || fixture_die 'Crossbar returned an invalid token'
}

api_request() {
    local method=$1 path=$2 body=${3-} response
    if (($# >= 3)); then
        response=$(printf '%s' "$body" | curl \
            --config <(printf 'header = "X-Auth-Token: %s"\n' "$MASTER_TOKEN") \
            --fail --silent --show-error --connect-timeout 5 --max-time 60 \
            -X "$method" -H 'Content-Type: application/json' --data-binary @- "$API_BASE/$path") || \
            fixture_die "Crossbar $method failed for $path"
    else
        response=$(curl --config <(printf 'header = "X-Auth-Token: %s"\n' "$MASTER_TOKEN") \
            --fail --silent --show-error --connect-timeout 5 --max-time 60 \
            -X "$method" -H 'Content-Type: application/json' "$API_BASE/$path") || \
            fixture_die "Crossbar $method failed for $path"
    fi
    jq -e '.status == "success"' <<<"$response" >/dev/null || fixture_die "Crossbar $method returned failure for $path"
    printf '%s' "$response"
}

api_get_optional() {
    local path=$1 output status
    output=$(mktemp /tmp/kazoo-callback-api.XXXXXX)
    status=$(curl --config <(printf 'header = "X-Auth-Token: %s"\n' "$MASTER_TOKEN") \
        --silent --show-error --connect-timeout 5 --max-time 60 -o "$output" -w '%{http_code}' \
        "$API_BASE/$path") || { rm -f -- "$output"; fixture_die "Crossbar GET transport failed for $path"; }
    case $status in
        200) cat "$output"; rm -f -- "$output" ;;
        404) rm -f -- "$output"; return 1 ;;
        *) rm -f -- "$output"; fixture_die "Crossbar GET $path returned HTTP $status" ;;
    esac
}

create_owned_number() {
    local encoded=$1 number=$2 response body
    if response=$(api_get_optional "accounts/$ACCEPTANCE_ACCOUNT_ID/phone_numbers/$encoded"); then
        jq -e --arg marker "$FIXTURE_MARKER" --arg number "$number" --arg account "$ACCEPTANCE_ACCOUNT_ID" \
            '.status == "success" and .data.id == $number and
             .data.kazoo_acceptance_fixture == $marker and
             ((.data.assigned_to // .data.account_id // $account) == $account)' <<<"$response" >/dev/null || \
            fixture_die "Refusing existing unowned fictional number: $number"
        return 0
    fi
    body=$(jq -cn --arg marker "$FIXTURE_MARKER" \
        '{data:{create_with_state:"in_service",kazoo_acceptance_fixture:$marker}}')
    response=$(api_request PUT "accounts/$ACCEPTANCE_ACCOUNT_ID/phone_numbers/$encoded?accept_charges=true" "$body")
    jq -e --arg number "$number" '.data.id == $number and .data.state == "in_service"' <<<"$response" >/dev/null || \
        fixture_die "Fictional number was not placed in service: $number"
}

resource_body() {
    local name="Kazoo Callback Carrier ${ACCEPTANCE_ACCOUNT_ID:0:8}"
    jq -cn --arg name "$name" --arg marker "$FIXTURE_MARKER" --arg server "$CARRIER_IP" --argjson port "$CARRIER_PORT" \
        '{data:{name:$name,enabled:true,weight_cost:1,grace_period:1,
                rules:["^\\+120255501[0-9]{2}$"],
                flags:[],require_flags:false,ignore_flags:false,
                kazoo_acceptance_fixture:$marker,
                gateways:[{server:$server,port:$port,enabled:true,endpoint_type:"sip",
                           invite_format:"route",caller_id_type:"external",
                           bypass_media:false,codecs:["PCMU"],progress_timeout:5}]}}'
}

create_local_resource() {
    local response body id name="Kazoo Callback Carrier ${ACCEPTANCE_ACCOUNT_ID:0:8}"
    body=$(resource_body)
    if [[ -n $FIXTURE_RESOURCE_ID ]]; then
        response=$(api_request GET "accounts/$ACCEPTANCE_ACCOUNT_ID/resources/$FIXTURE_RESOURCE_ID")
        jq -e --arg marker "$FIXTURE_MARKER" --arg name "$name" \
            '.data.name == $name and .data.kazoo_acceptance_fixture == $marker' <<<"$response" >/dev/null || \
            fixture_die 'Saved local resource ID is not owned by this fixture'
        api_request POST "accounts/$ACCEPTANCE_ACCOUNT_ID/resources/$FIXTURE_RESOURCE_ID" "$body" >/dev/null
        return 0
    fi
    response=$(api_request PUT "accounts/$ACCEPTANCE_ACCOUNT_ID/resources" "$body")
    id=$(jq -er '.data.id | select(test("^[a-f0-9]{32}$"))' <<<"$response") || fixture_die 'Local resource create returned no ID'
    FIXTURE_RESOURCE_ID=$id
    save_fixture_state
}

configure_acceptance_queue() {
    local response current callback updated body
    response=$(api_request GET "accounts/$ACCEPTANCE_ACCOUNT_ID/queues/$ACCEPTANCE_QUEUE_ID")
    current=$(jq -c '.data' <<<"$response")
    jq -e '.name == "Acceptance Queue 2000"' <<<"$current" >/dev/null || fixture_die 'Refusing unexpected queue document'
    if [[ -z $FIXTURE_ORIGINAL_QUEUE ]]; then
        FIXTURE_ORIGINAL_QUEUE=$current
        save_fixture_state
    fi
    callback=$(jq -cn --arg authority "$ACCEPTANCE_CALLER_DEVICE_ID" --arg cid "$OUTBOUND_CALLER_ID" \
        '{enabled:true,entry_key:"6",allow_alternate_number:false,use_local_resources:true,
          outbound_authority:{id:$authority,type:"device"},
          outbound_caller_id:{number:$cid,name:"Kazoo Callback Acceptance"},
          menu_timeout_ms:30000,success_timeout_ms:15000,ttl:600,max_attempts:1,
          retry_delay:15,originate_timeout:45,confirmation_timeout:15,
          ready_ack_timeout:5,handoff_timeout:5}')
    updated=$(jq -c --argjson callback "$callback" '.callback=$callback' <<<"$current")
    body=$(jq -cn --argjson data "$updated" '{data:$data}')
    api_request POST "accounts/$ACCEPTANCE_ACCOUNT_ID/queues/$ACCEPTANCE_QUEUE_ID" "$body" >/dev/null
}

reload_local_resources() {
    local account_arg output
    printf -v account_arg '<<"%s">>' "$ACCEPTANCE_ACCOUNT_ID"
    output=$(timeout 20 sup -e stepswitch_maintenance reload_resources "$account_arg" </dev/null 2>&1) || \
        fixture_die 'stepswitch local resource reload failed'
    [[ $output != *exception* && $output != *error* ]] || fixture_die 'stepswitch local resource reload returned an error'
}

verify_fixture() {
    local response name="Kazoo Callback Carrier ${ACCEPTANCE_ACCOUNT_ID:0:8}"
    [[ $FIXTURE_ACCOUNT_ID == "$ACCEPTANCE_ACCOUNT_ID" && $FIXTURE_RESOURCE_ID =~ ^[a-f0-9]{32}$ && \
       -n $FIXTURE_ORIGINAL_QUEUE ]] || fixture_die 'Callback fixture state is incomplete or belongs to another tenant'
    response=$(api_request GET "accounts/$ACCEPTANCE_ACCOUNT_ID/resources/$FIXTURE_RESOURCE_ID")
    jq -e --arg marker "$FIXTURE_MARKER" --arg name "$name" --arg ip "$CARRIER_IP" --argjson port "$CARRIER_PORT" \
        '.data.name == $name and .data.kazoo_acceptance_fixture == $marker and
         .data.enabled == true and .data.rules == ["^\\+120255501[0-9]{2}$"] and
         (.data.gateways|length)==1 and .data.gateways[0].server==$ip and
         .data.gateways[0].port==$port' <<<"$response" >/dev/null || fixture_die 'Local simulated carrier verification failed'
    for pair in "$ENCODED_CALLBACK_NUMBER:$CALLBACK_NUMBER" "$ENCODED_OUTBOUND_CALLER_ID:$OUTBOUND_CALLER_ID"; do
        response=$(api_request GET "accounts/$ACCEPTANCE_ACCOUNT_ID/phone_numbers/${pair%%:*}")
        jq -e --arg marker "$FIXTURE_MARKER" --arg number "${pair#*:}" \
            '.data.id == $number and .data.state == "in_service" and .data.kazoo_acceptance_fixture == $marker' \
            <<<"$response" >/dev/null || fixture_die "Fixture number verification failed: ${pair#*:}"
    done
    response=$(api_request GET "accounts/$ACCEPTANCE_ACCOUNT_ID/queues/$ACCEPTANCE_QUEUE_ID")
    jq -e --arg authority "$ACCEPTANCE_CALLER_DEVICE_ID" --arg cid "$OUTBOUND_CALLER_ID" \
        '.data.callback.enabled == true and .data.callback.entry_key == "6" and
         .data.callback.allow_alternate_number == false and .data.callback.use_local_resources == true and
         .data.callback.outbound_authority == {id:$authority,type:"device"} and
         .data.callback.outbound_caller_id.number == $cid' <<<"$response" >/dev/null || \
        fixture_die 'Acceptance queue callback configuration verification failed'
    fixture_log 'PASS: tenant-local carrier, fictional number ownership, authority, and queue callback settings verified'
}

callback_evidence() {
    local db response
    [[ $FIXTURE_ACCOUNT_ID == "$ACCEPTANCE_ACCOUNT_ID" && -n $FIXTURE_ORIGINAL_QUEUE ]] || \
        fixture_die 'An owned fixture is required for callback evidence'
    db="account%2F${ACCEPTANCE_ACCOUNT_ID:0:2}%2F${ACCEPTANCE_ACCOUNT_ID:2:2}%2F${ACCEPTANCE_ACCOUNT_ID:4}"
    response=$(couchdb_curl --fail --silent --show-error --connect-timeout 3 --max-time 5 \
        "http://${KAZOO_COUCHDB_HOST}:${KAZOO_COUCHDB_PORT}/$db/_all_docs?include_docs=true&limit=1001&startkey=%22acdc-callback-%22&endkey=%22acdc-callback-~%22") || \
        fixture_die 'Durable callback evidence query failed'
    jq -e --arg account "$ACCEPTANCE_ACCOUNT_ID" --arg queue "$ACCEPTANCE_QUEUE_ID" \
        'if (.rows | length) > 1000 then error("callback evidence limit exceeded") else
         [.rows[].doc | select(.pvt_type == "acdc_callback" and .pvt_deleted != true and
                              .pvt_account_id == $account and .queue_id == $queue) |
          {id:._id,status,original_call_id,enqueued_at,enqueue_sequence,attempts,
           caller_call_id:.pvt_caller_call_id,agent_call_id:.pvt_agent_call_id,
           selected_agents:.pvt_selected_agents,reconciliation_required}] end' <<<"$response"
}

cancel_original_callback() {
    local callbacks document callback_id status response
    callbacks=$(callback_evidence) || fixture_die 'Cannot establish callback ownership for cancellation'
    document=$(jq -ce --arg call "$CANCEL_ORIGINAL_CALL_ID" \
        '[.[] | select(.original_call_id==$call)] |
         if length<=1 then (.[0] // {}) else error("duplicate callback identity") end' <<<"$callbacks") || \
        fixture_die 'Ambiguous callback identity during cleanup'
    callback_id=$(jq -r '.id // empty' <<<"$document")
    [[ -n $callback_id ]] || return 0
    [[ $callback_id =~ ^acdc-callback-[a-f0-9]{64}$ ]] || fixture_die 'Unexpected callback ID during cleanup'
    status=$(jq -r '.status' <<<"$document")
    case $status in completed|cancelled|failed|expired) return 0 ;; esac
    response=$(api_request DELETE "accounts/$ACCEPTANCE_ACCOUNT_ID/queues/$ACCEPTANCE_QUEUE_ID/callbacks/$callback_id")
    status=$(jq -r '.data.status' <<<"$response")
    case $status in
        cancelled|completed|failed|expired) fixture_log 'PASS: exact test callback is terminal' ;;
        cancelling) fixture_die 'Exact test callback still requires positive live-leg/originate settlement; fixture retained' ;;
        *) fixture_die 'Unexpected callback cancellation response; fixture retained' ;;
    esac
}

setup_fixture() {
    local response
    if [[ -n $FIXTURE_ACCOUNT_ID && $FIXTURE_ACCOUNT_ID != "$ACCEPTANCE_ACCOUNT_ID" ]]; then
        fixture_die 'Existing callback fixture belongs to another tenant; clean it with the matching acceptance state'
    fi
    FIXTURE_ACCOUNT_ID=$ACCEPTANCE_ACCOUNT_ID
    # Persist the restoration snapshot before creating any owned objects so a
    # partially failed setup can still clean up only its exact marked objects.
    if [[ -z $FIXTURE_ORIGINAL_QUEUE ]]; then
        response=$(api_request GET "accounts/$ACCEPTANCE_ACCOUNT_ID/queues/$ACCEPTANCE_QUEUE_ID")
        jq -e '.data.name == "Acceptance Queue 2000"' <<<"$response" >/dev/null || \
            fixture_die 'Refusing unexpected queue document during fixture setup'
        FIXTURE_ORIGINAL_QUEUE=$(jq -c '.data' <<<"$response")
    fi
    save_fixture_state
    create_owned_number "$ENCODED_OUTBOUND_CALLER_ID" "$OUTBOUND_CALLER_ID"
    create_owned_number "$ENCODED_CALLBACK_NUMBER" "$CALLBACK_NUMBER"
    create_local_resource
    configure_acceptance_queue
    reload_local_resources
    verify_fixture
}

delete_marked_number() {
    local encoded=$1 number=$2 response
    if ! response=$(api_get_optional "accounts/$ACCEPTANCE_ACCOUNT_ID/phone_numbers/$encoded"); then return 0; fi
    jq -e --arg marker "$FIXTURE_MARKER" --arg number "$number" \
        '.data.id == $number and .data.kazoo_acceptance_fixture == $marker' <<<"$response" >/dev/null || \
        fixture_die "Refusing to delete unowned number: $number"
    api_request DELETE "accounts/$ACCEPTANCE_ACCOUNT_ID/phone_numbers/$encoded?hard=true" >/dev/null
}

cleanup_fixture() {
    local response body
    [[ $FIXTURE_ACCOUNT_ID == "$ACCEPTANCE_ACCOUNT_ID" && -n $FIXTURE_ORIGINAL_QUEUE ]] || \
        fixture_die 'No complete owned callback fixture state is available for cleanup'
    response=$(api_request GET "accounts/$ACCEPTANCE_ACCOUNT_ID/queues/$ACCEPTANCE_QUEUE_ID")
    jq -e '.data.name == "Acceptance Queue 2000"' <<<"$response" >/dev/null || fixture_die 'Refusing unexpected queue during cleanup'
    body=$(jq -cn --argjson data "$FIXTURE_ORIGINAL_QUEUE" '{data:$data}')
    api_request POST "accounts/$ACCEPTANCE_ACCOUNT_ID/queues/$ACCEPTANCE_QUEUE_ID" "$body" >/dev/null
    if [[ -n $FIXTURE_RESOURCE_ID ]]; then
        response=$(api_request GET "accounts/$ACCEPTANCE_ACCOUNT_ID/resources/$FIXTURE_RESOURCE_ID")
        jq -e --arg marker "$FIXTURE_MARKER" '.data.kazoo_acceptance_fixture == $marker' <<<"$response" >/dev/null || \
            fixture_die 'Refusing to delete an unowned local resource'
        api_request DELETE "accounts/$ACCEPTANCE_ACCOUNT_ID/resources/$FIXTURE_RESOURCE_ID" >/dev/null
    fi
    delete_marked_number "$ENCODED_CALLBACK_NUMBER" "$CALLBACK_NUMBER"
    delete_marked_number "$ENCODED_OUTBOUND_CALLER_ID" "$OUTBOUND_CALLER_ID"
    reload_local_resources
    rm -f -- "$FIXTURE_STATE_FILE"
    fixture_log 'PASS: restored queue snapshot and removed exact marked callback fixture objects'
}

main_fixture() {
    umask 077
    ((EUID == 0)) || fixture_die 'Run as root'
    parse_fixture_args "$@"
    load_acceptance_state
    load_fixture_state
    if [[ $ACTION == evidence ]]; then callback_evidence; return; fi
    authenticate_master
    case $ACTION in
        setup) setup_fixture ;;
        verify) verify_fixture ;;
        cleanup) cleanup_fixture ;;
        cancel-original) cancel_original_callback ;;
    esac
}

if [[ ${KAZOO_CALLBACK_FIXTURE_LIBRARY:-false} != true ]]; then
    main_fixture "$@"
fi
