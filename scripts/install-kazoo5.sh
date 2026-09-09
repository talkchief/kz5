#!/usr/bin/env bash
# shellcheck disable=SC2016
# Install modular or all-in-one Kazoo 5 nodes on Rocky Linux 9.
#
# This installer deliberately uses Kazoo's FreeSWITCH and Kamailio wrappers and
# configuration repositories. Reruns converge packages, source, configuration
# and systemd units, then run health checks. Selected services are restarted:
# schedule a maintenance window; this is not a rolling/zero-downtime upgrader.

set -Eeuo pipefail
shopt -s inherit_errexit

# Invocation-local proof only: never accept an environment value or old .app
# file as evidence that this invocation applied and compiled current sources.
KAZOO_BUILD_SUCCEEDED_THIS_RUN=false
KAZOO_BUILD_SNAPSHOT_THIS_RUN=''

readonly SCRIPT_NAME=${0##*/}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
readonly SCRIPT_DIR
DEFAULT_KAZOO_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
readonly DEFAULT_KAZOO_ROOT

# Persist only deployment inputs, never shell code. Explicit environment values
# win over saved settings, so a modular server can be rerun without losing its
# remote endpoints while still accepting intentional overrides.
KAZOO_DEPLOYMENT_CONFIG=${KAZOO_DEPLOYMENT_CONFIG:-/etc/kazoo/deployment.env}
readonly KAZOO_PERSISTED_KEYS=(
    KAZOO_ROOT KAZOO_BUILD_ROOT KAZOO_CACHE_DIR KAZOO_CONFIG_DIR KAZOO_COOKIE_FILE
    KAZOO_AMQP_HOST KAZOO_AMQP_PORT KAZOO_RABBITMQ_USER KAZOO_RABBITMQ_PASSWORD
    KAZOO_RABBITMQ_VHOST KAZOO_AMQP_URI KAZOO_COUCHDB_HOST KAZOO_COUCHDB_PORT
    KAZOO_RABBITMQ_API_URL KAZOO_RABBITMQ_API_USER KAZOO_RABBITMQ_API_PASSWORD
    KAZOO_RABBITMQ_API_CA_FILE
    KAZOO_COUCHDB_ADMIN_PORT KAZOO_COUCHDB_USER KAZOO_COUCHDB_PASSWORD
    KAZOO_COUCHDB_BIND KAZOO_RABBITMQ_BIND KAZOO_HAPROXY_BIND KAZOO_PUBLIC_IP
    KAZOO_ERLANG_DIST_IP KAZOO_API_URL KAZOO_MAKE_JOBS KAZOO_MIN_BUILD_FREE_MB
    KAZOO_APPS_LIST KAZOO_FREESWITCH_NODES KAZOO_START_TIMEOUT
    KAZOO_FREESWITCH_STABILITY_SECONDS KAZOO_REQUIRE_MEDIA_CONNECTION
    KAZOO_BOOTSTRAP_MASTER_ACCOUNT KAZOO_MASTER_ACCOUNT_NAME
    KAZOO_MASTER_ACCOUNT_REALM KAZOO_MASTER_ADMIN_USER KAZOO_INSTALLER_SECRETS
    KAZOO_PUBLIC_HOSTNAME KAZOO_TLS_CERT_FILE KAZOO_TLS_KEY_FILE
    KAZOO_TLS_CHAIN_FILE KAZOO_API_UPSTREAM KAZOO_WEBSOCKET_UPSTREAM
    COUCHDB_VERSION RABBITMQ_VERSION ERLANG_VERSION HTMLDOC_VERSION HTMLDOC_REF
    FREESWITCH_VERSION FREESWITCH_REF SPANDSP_REF SOFIA_SIP_REF MOD_KAZOO_REF
    FREESWITCH_CONFIG_REF KAZOO_CORE_CONFIG_REF KAZOO_CORE_REF KAZOO_CROSSBAR_REF KAZOO_BLACKHOLE_REF KAZOO_ECALLMGR_REF KAZOO_STEPSWITCH_REF KAZOO_CDR_REF KAZOO_SOUNDS_REF ACDC_REF KAMAILIO_VERSION
    KAMAILIO_CONFIG_REF KAMAILIO_CHILDREN KAMAILIO_TCP_CHILDREN
    KAMAILIO_AMQP_CONSUMERS KAMAILIO_AMQP_WORKERS MONSTER_UI_REF
    MONSTER_UI_NODE_MAJOR MONSTER_UI_WEB_ROOT MONSTER_UI_REGISTER_APPS MONSTER_UI_LOCK_SHA256
    MONSTER_UI_CATALOG_SSH_HOST MONSTER_UI_CATALOG_SSH_USER MONSTER_UI_CATALOG_SSH_PORT
    MONSTER_UI_CATALOG_IDENTITY_FILE MONSTER_UI_CATALOG_KNOWN_HOSTS_FILE MONSTER_UI_CATALOG_MASTER_ID
    MONSTER_UI_WEBSOCKET_URL MONSTER_UI_REMOTE_BRANDING MONSTER_UI_BRAINTREE
    MONSTER_UI_APPS_LIST MONSTER_UI_ACCOUNTS_REF MONSTER_UI_CALLFLOWS_REF
    MONSTER_UI_CSV_ONBOARDING_REF MONSTER_UI_FAX_REF MONSTER_UI_NUMBERS_REF
    MONSTER_UI_PBXS_REF MONSTER_UI_VOICEMAILS_REF MONSTER_UI_WEBHOOKS_REF
    MONSTER_UI_VOIP_REF
)
KAZOO_AMQP_SPLIT_OVERRIDE=false
for config_key in KAZOO_AMQP_HOST KAZOO_AMQP_PORT KAZOO_RABBITMQ_USER \
    KAZOO_RABBITMQ_PASSWORD KAZOO_RABBITMQ_VHOST; do
    if [[ -v $config_key ]]; then KAZOO_AMQP_SPLIT_OVERRIDE=true; fi
done
KAZOO_AMQP_URI_EXPLICIT=false
[[ ! -v KAZOO_AMQP_URI ]] || KAZOO_AMQP_URI_EXPLICIT=true
KAZOO_MASTER_ACCOUNT_REALM_EXPLICIT=false
[[ ! -v KAZOO_MASTER_ACCOUNT_REALM ]] || KAZOO_MASTER_ACCOUNT_REALM_EXPLICIT=true
KAZOO_MASTER_ADMIN_USER_EXPLICIT=false
[[ ! -v KAZOO_MASTER_ADMIN_USER ]] || KAZOO_MASTER_ADMIN_USER_EXPLICIT=true

load_deployment_config() {
    local line key encoded value allowed candidate mode owner argument
    for argument in "$@"; do
        case $argument in --help|-h|--list) return 0 ;; esac
    done
    [[ -e $KAZOO_DEPLOYMENT_CONFIG ]] || return 0
    [[ -f $KAZOO_DEPLOYMENT_CONFIG && ! -L $KAZOO_DEPLOYMENT_CONFIG ]] || {
        printf 'Deployment configuration must be a regular file\n' >&2; exit 1;
    }
    read -r owner mode < <(stat -c '%u %a' "$KAZOO_DEPLOYMENT_CONFIG")
    if [[ $owner != 0 || $mode != 600 ]]; then
        printf 'Deployment configuration must be owned by root with mode 0600\n' >&2
        exit 1
    fi
    [[ -r $KAZOO_DEPLOYMENT_CONFIG ]] || {
        printf 'Run as root to read the saved deployment configuration\n' >&2; exit 1;
    }
    while IFS= read -r line || [[ -n $line ]]; do
        [[ -n $line && $line != \#* ]] || continue
        [[ $line == *=* ]] || {
            printf 'Malformed deployment configuration line\n' >&2; exit 1;
        }
        key=${line%%=*}
        encoded=${line#*=}
        [[ -n $key ]] || {
            printf 'Malformed deployment configuration key\n' >&2; exit 1;
        }
        allowed=false
        for candidate in "${KAZOO_PERSISTED_KEYS[@]}"; do
            if [[ $key == "$candidate" ]]; then allowed=true; break; fi
        done
        [[ $allowed == true ]] || {
            printf 'Unknown setting in deployment configuration: %s\n' "$key" >&2; exit 1;
        }
        [[ ! -v $key ]] || continue
        if [[ $key == KAZOO_AMQP_URI && $KAZOO_AMQP_SPLIT_OVERRIDE == true ]]; then continue; fi
        value=$(printf '%s' "$encoded" | base64 --decode) || {
            printf 'Invalid encoded deployment setting: %s\n' "$key" >&2; exit 1;
        }
        printf -v "$key" '%s' "$value"
    done < "$KAZOO_DEPLOYMENT_CONFIG"
}
load_deployment_config "$@"
unset config_key

KAZOO_ROOT=${KAZOO_ROOT:-$DEFAULT_KAZOO_ROOT}
KAZOO_BUILD_ROOT=${KAZOO_BUILD_ROOT:-/usr/local/src/kazoo5-installer}
KAZOO_CACHE_DIR=${KAZOO_CACHE_DIR:-/var/cache/kazoo5-installer}
KAZOO_CONFIG_DIR=${KAZOO_CONFIG_DIR:-/etc/kazoo}
KAZOO_COOKIE_EXPLICIT=false
[[ -z ${KAZOO_COOKIE:-} ]] || KAZOO_COOKIE_EXPLICIT=true
KAZOO_COOKIE=${KAZOO_COOKIE:-}
KAZOO_COOKIE_FILE=${KAZOO_COOKIE_FILE:-${KAZOO_CONFIG_DIR}/.erlang.cookie}
KAZOO_ALLOW_COOKIE_ROTATION=${KAZOO_ALLOW_COOKIE_ROTATION:-false}
KAZOO_FREESWITCH_COOKIE_FILE=${KAZOO_FREESWITCH_COOKIE_FILE:-${KAZOO_CONFIG_DIR}/freeswitch/.erlang.cookie}
readonly KAZOO_RUNTIME_COOKIE_FILE=/var/lib/kazoo/.erlang.cookie
KAZOO_AMQP_HOST=${KAZOO_AMQP_HOST:-127.0.0.1}
KAZOO_AMQP_PORT=${KAZOO_AMQP_PORT:-5672}
KAZOO_RABBITMQ_USER=${KAZOO_RABBITMQ_USER:-kazoo}
KAZOO_RABBITMQ_PASSWORD=${KAZOO_RABBITMQ_PASSWORD:-change_me}
KAZOO_RABBITMQ_VHOST=${KAZOO_RABBITMQ_VHOST:-/}
KAZOO_AMQP_URI=${KAZOO_AMQP_URI:-}
KAZOO_RABBITMQ_API_URL=${KAZOO_RABBITMQ_API_URL:-}
KAZOO_RABBITMQ_API_USER=${KAZOO_RABBITMQ_API_USER:-}
KAZOO_RABBITMQ_API_PASSWORD=${KAZOO_RABBITMQ_API_PASSWORD:-}
KAZOO_RABBITMQ_API_CA_FILE=${KAZOO_RABBITMQ_API_CA_FILE:-}
KAZOO_COUCHDB_HOST=${KAZOO_COUCHDB_HOST:-127.0.0.1}
KAZOO_COUCHDB_PORT=${KAZOO_COUCHDB_PORT:-5984}
KAZOO_COUCHDB_ADMIN_PORT=${KAZOO_COUCHDB_ADMIN_PORT:-$KAZOO_COUCHDB_PORT}
KAZOO_COUCHDB_USER=${KAZOO_COUCHDB_USER:-admin}
KAZOO_COUCHDB_PASSWORD=${KAZOO_COUCHDB_PASSWORD:-admin}
KAZOO_COUCHDB_BIND=${KAZOO_COUCHDB_BIND:-127.0.0.1}
KAZOO_RABBITMQ_BIND=${KAZOO_RABBITMQ_BIND:-127.0.0.1}
KAZOO_HAPROXY_BIND=${KAZOO_HAPROXY_BIND:-127.0.0.1}
KAZOO_PUBLIC_IP=${KAZOO_PUBLIC_IP:-}
KAZOO_ERLANG_DIST_IP=${KAZOO_ERLANG_DIST_IP:-127.0.0.1}
KAZOO_API_URL=${KAZOO_API_URL:-}
KAZOO_PUBLIC_HOSTNAME=${KAZOO_PUBLIC_HOSTNAME:-}
KAZOO_TLS_CERT_FILE=${KAZOO_TLS_CERT_FILE:-}
KAZOO_TLS_KEY_FILE=${KAZOO_TLS_KEY_FILE:-}
KAZOO_TLS_CHAIN_FILE=${KAZOO_TLS_CHAIN_FILE:-}
KAZOO_API_UPSTREAM=${KAZOO_API_UPSTREAM:-http://127.0.0.1:8000/v2/}
KAZOO_MAKE_JOBS=${KAZOO_MAKE_JOBS:-$(nproc 2>/dev/null || printf '1')}
KAZOO_MIN_BUILD_FREE_MB=${KAZOO_MIN_BUILD_FREE_MB:-4096}
KAZOO_APPS_LIST=${KAZOO_APPS_LIST:-acdc,blackhole,callflow,cdr,conference,crossbar,fax,hangups,media_mgr,milliwatt,omnipresence,pivot,registrar,reorder,stepswitch,sysconf,tasks,teletype,trunkstore,webhooks}
KAZOO_FREESWITCH_NODES=${KAZOO_FREESWITCH_NODES:-}
KAZOO_START_TIMEOUT=${KAZOO_START_TIMEOUT:-180}
KAZOO_FREESWITCH_STABILITY_SECONDS=${KAZOO_FREESWITCH_STABILITY_SECONDS:-45}
KAZOO_REQUIRE_MEDIA_CONNECTION=${KAZOO_REQUIRE_MEDIA_CONNECTION:-auto}
KAZOO_BOOTSTRAP_MASTER_ACCOUNT=${KAZOO_BOOTSTRAP_MASTER_ACCOUNT:-true}
KAZOO_MASTER_ACCOUNT_NAME=${KAZOO_MASTER_ACCOUNT_NAME:-KazooMaster}
KAZOO_MASTER_ACCOUNT_REALM=${KAZOO_MASTER_ACCOUNT_REALM:-}
KAZOO_MASTER_ADMIN_USER=${KAZOO_MASTER_ADMIN_USER:-admin}
KAZOO_MASTER_ADMIN_PASSWORD=${KAZOO_MASTER_ADMIN_PASSWORD:-}
KAZOO_SOUNDS_REF=${KAZOO_SOUNDS_REF:-c82a707d9f06cf8160891aa57025ee606806bd0b}
KAZOO_ECALLMGR_REF=${KAZOO_ECALLMGR_REF:-fb8eba201b41762ce8fae928c61bd5d22379a1bc}
KAZOO_STEPSWITCH_REF=${KAZOO_STEPSWITCH_REF:-b04805b6354b2e0bbab8aca72c8514dcf6e1d828}
KAZOO_CDR_REF=${KAZOO_CDR_REF:-5e317c9a0b9aba87db78a3549ea340d8f790c502}
KAZOO_INSTALLER_SECRETS=${KAZOO_INSTALLER_SECRETS:-/etc/kazoo/installer-secrets.env}

COUCHDB_VERSION=${COUCHDB_VERSION:-3.5.2.1-1.el9}
RABBITMQ_VERSION=${RABBITMQ_VERSION:-3.13.7}
ERLANG_VERSION=${ERLANG_VERSION:-26.2.5}
HTMLDOC_VERSION=${HTMLDOC_VERSION:-1.9.23}
HTMLDOC_REF=${HTMLDOC_REF:-2de07fe97da08de65f1284c8497b90cfaa24d9eb}
FREESWITCH_VERSION=${FREESWITCH_VERSION:-1.11.3}
FREESWITCH_REF=${FREESWITCH_REF:-ef32e205295e29f034f1453ad245ba5efb07b94a}
SPANDSP_REF=${SPANDSP_REF:-8f1e1646bdec99eac5fd2cd92c35563f736b9b89}
SOFIA_SIP_REF=${SOFIA_SIP_REF:-ad36ac8f755308e8b87f98a505e83d4e408e5cc3}
MOD_KAZOO_REF=${MOD_KAZOO_REF:-0878e13e02db5db7bde765d61a9453b3cf279399}
FREESWITCH_CONFIG_REF=${FREESWITCH_CONFIG_REF:-62b833c5e19f76f6ec81c9b5efc8e9c0efbdf101}
KAZOO_CORE_CONFIG_REF=${KAZOO_CORE_CONFIG_REF:-03263e6c9834658a6cb19b33f690bb4542c52a9d}
KAZOO_CORE_REF=${KAZOO_CORE_REF:-5defa1df755ea9cf4d0f3f81f8145bd8a0c7dd72}
KAZOO_CROSSBAR_REF=${KAZOO_CROSSBAR_REF:-2ac862830f9b626d2170d08daf1991b0ca33dba7}
KAZOO_BLACKHOLE_REF=${KAZOO_BLACKHOLE_REF:-4e3f02a5ab01c09a44c287f4f93b15d2782f5614}
ACDC_REF=${ACDC_REF:-6f71c85f67ee2228efb0edceb5248b6334ba1998}
KAMAILIO_VERSION=${KAMAILIO_VERSION:-${KAMAILIO_SERIES:-6.1.4}}
KAMAILIO_CONFIG_REF=${KAMAILIO_CONFIG_REF:-9d61bded9890325182f1783aeb4bd2182eb2d846}
KAMAILIO_CHILDREN=${KAMAILIO_CHILDREN:-4}
KAMAILIO_TCP_CHILDREN=${KAMAILIO_TCP_CHILDREN:-4}
KAMAILIO_AMQP_CONSUMERS=${KAMAILIO_AMQP_CONSUMERS:-2}
KAMAILIO_AMQP_WORKERS=${KAMAILIO_AMQP_WORKERS:-4}
MONSTER_UI_REF=${MONSTER_UI_REF:-7ef735eada6fd0e2b96c06f32c0bb868867f7d18}
MONSTER_UI_NODE_MAJOR=${MONSTER_UI_NODE_MAJOR:-18}
MONSTER_UI_LOCK_SHA256=${MONSTER_UI_LOCK_SHA256:-da59e0891ebb949b5acdb81663463fcc09362ce7f956f9ed50beeafe7ecd6222}
MONSTER_UI_WEB_ROOT=${MONSTER_UI_WEB_ROOT:-/var/www/html/monster-ui}
MONSTER_UI_REGISTER_APPS=${MONSTER_UI_REGISTER_APPS:-auto}
MONSTER_UI_CATALOG_SSH_HOST=${MONSTER_UI_CATALOG_SSH_HOST:-}
MONSTER_UI_CATALOG_SSH_USER=${MONSTER_UI_CATALOG_SSH_USER:-}
MONSTER_UI_CATALOG_SSH_PORT=${MONSTER_UI_CATALOG_SSH_PORT:-22}
MONSTER_UI_CATALOG_IDENTITY_FILE=${MONSTER_UI_CATALOG_IDENTITY_FILE:-}
MONSTER_UI_CATALOG_KNOWN_HOSTS_FILE=${MONSTER_UI_CATALOG_KNOWN_HOSTS_FILE:-}
MONSTER_UI_CATALOG_MASTER_ID=${MONSTER_UI_CATALOG_MASTER_ID:-}
# Invocation-local resolution, never an inherited authority selection.
MONSTER_CATALOG_MODE=''
MONSTER_UI_WEBSOCKET_URL=${MONSTER_UI_WEBSOCKET_URL:-auto}
MONSTER_UI_REMOTE_BRANDING=${MONSTER_UI_REMOTE_BRANDING:-auto}
MONSTER_UI_BRAINTREE=${MONSTER_UI_BRAINTREE:-auto}
KAZOO_WEBSOCKET_UPSTREAM=${KAZOO_WEBSOCKET_UPSTREAM:-http://127.0.0.1:5555/websocket}
MONSTER_UI_APPS_LIST=${MONSTER_UI_APPS_LIST:-acdc,accounts,callflows,csv-onboarding,fax,numbers,pbxs,voicemails,webhooks,voip}
MONSTER_UI_ACCOUNTS_REF=${MONSTER_UI_ACCOUNTS_REF:-bcdc6b734c45f370f835276a79827513b111482a}
MONSTER_UI_CALLFLOWS_REF=${MONSTER_UI_CALLFLOWS_REF:-11d6a7f797576f2ddd3cbadf6474787e95d5c760}
MONSTER_UI_CSV_ONBOARDING_REF=${MONSTER_UI_CSV_ONBOARDING_REF:-37171524c948d26885f4a92e2433dd06e9b2472a}
MONSTER_UI_FAX_REF=${MONSTER_UI_FAX_REF:-a2f7a30e49e037f8550266ecd0736b7ec74ae4bd}
MONSTER_UI_NUMBERS_REF=${MONSTER_UI_NUMBERS_REF:-bab6986730a1008f3cb2e297ecb569f0e8c589de}
MONSTER_UI_PBXS_REF=${MONSTER_UI_PBXS_REF:-d3b3c88b39d257d1791c7b9316348239c899bf36}
MONSTER_UI_VOICEMAILS_REF=${MONSTER_UI_VOICEMAILS_REF:-e789ecc73bc066b0e30d9f323da1f82b0ad16ac9}
MONSTER_UI_WEBHOOKS_REF=${MONSTER_UI_WEBHOOKS_REF:-0773771b1fdcd1ae9a7a0d4c18fba9d26f00c7e1}
MONSTER_UI_VOIP_REF=${MONSTER_UI_VOIP_REF:-514ec370faf0063f42862f31c087ab484c122194}

DRY_RUN=false
VERIFY_ONLY=false
KAZOO_HOSTNAME=
KAZOO_NODE_NAME_TYPE=
KAZOO_FREESWITCH_SHORTNAME=false
declare -a REQUESTED=()
declare -A SELECTED=()

usage() {
    cat <<EOF
Usage: sudo ./${SCRIPT_NAME} [OPTIONS] COMPONENT [COMPONENT ...]

Installable components:
  couchdb       Apache CouchDB configured as a single Kazoo node
  rabbitmq      RabbitMQ with Kazoo-required consistent-hash plugin
  haproxy       HAProxy front end for CouchDB on ports 15984/15986
  kazoo-apps    Compile Kazoo and run the kazoo-apps.service node
  ecallmgr      Compile Kazoo and run the kazoo-ecallmgr.service node
  freeswitch    Kazoo FreeSWITCH, including mod_kazoo and its wrapper
  kamailio      Kazoo Kamailio, including the kazoo module and wrapper
  monster-ui    Build Monster UI and serve it through nginx
  push-bridge   Native FCM/APNs bridge (requires protected mobile configuration)
  all           Install and verify every component above

Aliases accepted: apps, kazoo_apps, monster_ui, and the common typo kamaialio.

Options:
  --dry-run      Print the resolved installation without changing the host
  --verify-only  Do not install; verify the requested components
  --list         Print component names and exit
  --couchdb-host HOST  CouchDB host used by Kazoo/HAProxy
  --amqp-host HOST     RabbitMQ host used by Kazoo/media/SIP
  --api-url URL        Crossbar URL used by Monster UI
  --public-ip IP       Address on which Kamailio listens
  --erlang-dist-ip IP  Address for Kazoo Erlang distribution (ports 11500-11999)
  --hostname NAME     Public Monster UI HTTPS hostname
  --tls-cert FILE     PEM server certificate (or full chain)
  --tls-key FILE      Matching PEM private key
  --tls-chain FILE    Optional intermediate certificate bundle
  --api-upstream URL  Crossbar upstream for the HTTPS /v2/ proxy
  -h, --help     Show this help

Configuration is supplied through environment variables. Useful overrides:
  KAZOO_DEPLOYMENT_CONFIG (root-only saved settings; environment overrides it),
  KAZOO_PUBLIC_HOSTNAME, KAZOO_TLS_CERT_FILE, KAZOO_TLS_KEY_FILE,
  KAZOO_TLS_CHAIN_FILE, KAZOO_API_UPSTREAM,
  KAZOO_ROOT, KAZOO_COOKIE, KAZOO_COOKIE_FILE, KAZOO_PUBLIC_IP,
  KAZOO_ERLANG_DIST_IP, KAZOO_API_URL,
  KAZOO_COUCHDB_HOST, KAZOO_COUCHDB_USER, KAZOO_COUCHDB_PASSWORD,
  KAZOO_AMQP_HOST, KAZOO_AMQP_URI, KAZOO_RABBITMQ_USER,
  KAZOO_RABBITMQ_PASSWORD, KAZOO_FREESWITCH_NODES,
  KAZOO_REQUIRE_MEDIA_CONNECTION, KAZOO_ALLOW_COOKIE_ROTATION,
  KAZOO_MAKE_JOBS, KAZOO_MIN_BUILD_FREE_MB, COUCHDB_VERSION, ERLANG_VERSION,
  FREESWITCH_VERSION,
  KAMAILIO_VERSION, KAMAILIO_CONFIG_REF, KAMAILIO_CHILDREN,
  MONSTER_UI_REF, MONSTER_UI_APPS_LIST, MONSTER_UI_REGISTER_APPS,
  MONSTER_UI_CATALOG_SSH_HOST, MONSTER_UI_CATALOG_SSH_USER, MONSTER_UI_CATALOG_SSH_PORT,
  MONSTER_UI_CATALOG_IDENTITY_FILE, MONSTER_UI_CATALOG_KNOWN_HOSTS_FILE,
  MONSTER_UI_CATALOG_MASTER_ID (standalone UI: explicit pinned apps-node authority).

Examples:
  sudo ./${SCRIPT_NAME} couchdb rabbitmq
  sudo KAZOO_COUCHDB_HOST=db1.example.net KAZOO_AMQP_HOST=mq1.example.net \\
    ./${SCRIPT_NAME} kazoo-apps ecallmgr
  sudo ./${SCRIPT_NAME} ALL
  sudo ./${SCRIPT_NAME} --verify-only all

Mobile bridge (also selected by ALL) requires /etc/kazoo-push-bridge/config.json
and provider key files before installation; see services/push-bridge/README.md.
It uses its own reviewed AMQP host/config and never implies local RabbitMQ or
Kamailio installation. Bridge readiness verifies a broker consumer, not a phone.
EOF
}

log() {
    printf '[kazoo5] %s\n' "$*"
}

warn() {
    printf '[kazoo5] WARNING: %s\n' "$*" >&2
}

die() {
    printf '[kazoo5] ERROR: %s\n' "$*" >&2
    exit 1
}

on_error() {
    local exit_code=$?
    printf '[kazoo5] ERROR: command failed at line %s (exit %s)\n' "${BASH_LINENO[0]}" "$exit_code" >&2
    exit "$exit_code"
}
trap on_error ERR

quote_command() {
    printf ' %q' "$@"
    printf '\n'
}

run() {
    if [[ $DRY_RUN == true ]]; then
        printf '[dry-run]'
        quote_command "$@"
        return 0
    fi
    "$@"
}

url_encode() {
    local LC_ALL=C
    local input=$1
    local output=
    local char encoded i
    for ((i = 0; i < ${#input}; i++)); do
        char=${input:i:1}
        case "$char" in
            [a-zA-Z0-9.~_-]) output+=$char ;;
            *)
                printf -v encoded '%%%02X' "'$char"
                output+=$encoded
                ;;
        esac
    done
    printf '%s' "$output"
}

is_loopback_address() {
    case ${1,,} in
        127.*|localhost|::1) return 0 ;;
        *) return 1 ;;
    esac
}

is_ipv4_address() {
    local address=$1 octet
    local -a octets=()
    IFS=. read -r -a octets <<<"$address"
    ((${#octets[@]} == 4)) || return 1
    for octet in "${octets[@]}"; do
        [[ $octet =~ ^[0-9]{1,3}$ ]] || return 1
        [[ $octet == 0 || $octet != 0* ]] || return 1
        ((10#$octet <= 255)) || return 1
    done
}

is_public_dns_hostname() {
    local hostname=$1 label
    local -a labels=()
    [[ ${#hostname} -le 253 && $hostname == *.* && $hostname != *..* ]] || return 1
    IFS=. read -r -a labels <<<"$hostname"
    [[ ${labels[-1]} =~ [a-zA-Z] ]] || return 1
    for label in "${labels[@]}"; do
        [[ ${#label} -le 63 && $label =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]] || \
            return 1
    done
}

local_probe_address() {
    case $1 in
        0.0.0.0) printf '127.0.0.1\n' ;;
        *) printf '%s\n' "$1" ;;
    esac
}

validate_port() {
    local name=$1 value=$2
    [[ $value =~ ^[0-9]+$ ]] || die "${name} must be an integer TCP/UDP port"
    ((value >= 1 && value <= 65535)) || die "${name} must be between 1 and 65535"
}

validate_safe_value() {
    local name=$1 value=$2
    [[ ! $value =~ [[:cntrl:]] ]] || \
        die "${name} must not contain control characters"
}

validate_install_directory() {
    local name=$1 value=$2
    [[ $value =~ ^/[-a-zA-Z0-9_.]+(/[-a-zA-Z0-9_.]+)*$ && \
       /$value/ != */../* && /$value/ != */./* ]] || \
        die "${name} must be a canonical absolute path using only letters, digits, slash, underscore, dot or hyphen"
}

amqp_uri_from_split_settings() {
    printf 'amqp://%s:%s@%s:%s/%s' \
        "$(url_encode "$KAZOO_RABBITMQ_USER")" \
        "$(url_encode "$KAZOO_RABBITMQ_PASSWORD")" \
        "$KAZOO_AMQP_HOST" "$KAZOO_AMQP_PORT" \
        "$(url_encode "$KAZOO_RABBITMQ_VHOST")"
}

resolve_amqp_uri() {
    [[ -n $KAZOO_AMQP_URI ]] && return 0
    KAZOO_AMQP_URI=$(amqp_uri_from_split_settings)
}

write_file() {
    local mode=$1
    local destination=$2
    local temporary
    if [[ $DRY_RUN == true ]]; then
        cat >/dev/null
        log "Would install ${destination} (mode ${mode})"
        return 0
    fi
    temporary=$(mktemp)
    cat >"$temporary"
    install -D -m "$mode" "$temporary" "$destination"
    rm -f "$temporary"
}

cookie_component_selected() {
    [[ ${SELECTED[kazoo-apps]:-} || ${SELECTED[ecallmgr]:-} || ${SELECTED[freeswitch]:-} ]]
}

coordinated_local_cookie_install() {
    [[ ${SELECTED[kazoo-apps]:-} && ${SELECTED[ecallmgr]:-} && ${SELECTED[freeswitch]:-} ]] &&
        is_loopback_address "$KAZOO_ERLANG_DIST_IP" &&
        [[ -z $KAZOO_FREESWITCH_NODES ]]
}

distributed_cookie_install() {
    ! is_loopback_address "$KAZOO_ERLANG_DIST_IP" ||
        [[ -n $KAZOO_FREESWITCH_NODES || $KAZOO_REQUIRE_MEDIA_CONNECTION == true ]]
}

weak_kazoo_cookie() {
    case ${1,,} in
        change_me|cluecon|monster|changeme|default) return 0 ;;
        *) return 1 ;;
    esac
}

validate_kazoo_cookie() {
    local cookie=$1
    [[ $cookie =~ ^[a-zA-Z0-9_@.-]{32,128}$ ]] ||
        die 'KAZOO_COOKIE must be 32-128 characters using only letters, numbers, underscore, @, dot, and dash'
    weak_kazoo_cookie "$cookie" && die 'KAZOO_COOKIE must not use a known default value'
    return 0
}

read_ini_cookie() {
    local file=$1 section=$2
    [[ -r $file ]] || return 0
    awk -v wanted="[$section]" '
        $0 == wanted { found=1; next }
        /^\[/ { found=0 }
        found && /^[[:space:]]*cookie[[:space:]]*=/ {
            sub(/^[^=]*=[[:space:]]*/, "")
            sub(/[[:space:]]*$/, "")
            print
            exit
        }
    ' "$file"
}

read_freeswitch_inline_cookie() {
    local file=$1
    [[ -r $file ]] || return 0
    sed -n -E 's#.*<param name="cookie" value="([^"]+)"[[:space:]]*/>.*#\1#p' "$file" |
        head -n 1
}

generate_kazoo_cookie() {
    LC_ALL=C od -An -N48 -tx1 /dev/urandom | tr -d ' \n'
}

validate_existing_root_secret() {
    local file=$1 owner mode
    [[ -e $file ]] || return 0
    [[ -f $file && ! -L $file ]] || die "Cookie file must be a regular non-symlink file: ${file}"
    read -r owner mode < <(stat -c '%u %a' "$file")
    [[ $owner == 0 && $mode =~ ^[0-7]+$ && $((8#$mode & 077)) == 0 ]] ||
        die "Cookie file must be root-owned and inaccessible to group/other: ${file}"
}

reject_secret_symlink() {
    local file=$1
    [[ ! -L $file ]] || die "Refusing to replace a symlinked cookie file: ${file}"
    [[ ! -e $file || -f $file ]] || die "Cookie path is not a regular file: ${file}"
}

validate_config_directory() {
    local directory=$1
    [[ ! -L $directory ]] || die "Refusing a symlinked configuration directory: ${directory}"
    [[ ! -e $directory || -d $directory ]] || die "Configuration path is not a directory: ${directory}"
    if [[ -e $directory ]]; then
        [[ $(stat -c '%u' "$directory") == 0 ]] || die "Configuration directory must be root-owned: ${directory}"
    fi
}

resolve_kazoo_cookie() {
    local candidate installed_cookie='' stored_cookie='' selected_cookie=''
    local installed_conflict=false needs_rotation=false
    local core_config=${KAZOO_CONFIG_DIR}/core/config.ini
    local freeswitch_config=${KAZOO_CONFIG_DIR}/freeswitch/autoload_configs/kazoo.conf.xml
    local -a installed_candidates=()

    cookie_component_selected || return 0
    [[ $KAZOO_COOKIE_FILE == /* && $KAZOO_COOKIE_FILE != / &&
       ! $KAZOO_COOKIE_FILE =~ [[:space:]] && ${KAZOO_COOKIE_FILE##*/} == .erlang.cookie ]] ||
        die 'KAZOO_COOKIE_FILE must be an absolute path ending in /.erlang.cookie without whitespace'
    [[ $KAZOO_FREESWITCH_COOKIE_FILE == /* && $KAZOO_FREESWITCH_COOKIE_FILE != / &&
       $KAZOO_FREESWITCH_COOKIE_FILE =~ ^/[a-zA-Z0-9_./-]+$ ]] ||
        die 'KAZOO_FREESWITCH_COOKIE_FILE must be an absolute file path using only letters, numbers, underscore, dot, slash, and dash'
    [[ $KAZOO_ALLOW_COOKIE_ROTATION == true || $KAZOO_ALLOW_COOKIE_ROTATION == false ]] ||
        die 'KAZOO_ALLOW_COOKIE_ROTATION must be true or false'
    validate_existing_root_secret "$KAZOO_COOKIE_FILE"

    if [[ -r $KAZOO_COOKIE_FILE ]]; then
        stored_cookie=$(tr -d '\r\n' <"$KAZOO_COOKIE_FILE")
    fi
    installed_candidates+=("$(read_ini_cookie "$core_config" kazoo_apps)")
    installed_candidates+=("$(read_ini_cookie "$core_config" ecallmgr)")
    installed_candidates+=("$(read_freeswitch_inline_cookie "$freeswitch_config")")
    if [[ -r $KAZOO_FREESWITCH_COOKIE_FILE ]]; then
        installed_candidates+=("$(tr -d '\r\n' <"$KAZOO_FREESWITCH_COOKIE_FILE")")
    fi
    for candidate in "${installed_candidates[@]}"; do
        [[ -n $candidate ]] || continue
        if [[ -z $installed_cookie ]]; then
            installed_cookie=$candidate
        elif [[ $candidate != "$installed_cookie" ]]; then
            installed_conflict=true
        fi
    done

    if [[ $installed_conflict == true ]]; then
        if coordinated_local_cookie_install && [[ $VERIFY_ONLY != true ]]; then
            needs_rotation=true
        else
            die 'Installed Kazoo components use conflicting Erlang cookies; run a coordinated local install or provide KAZOO_COOKIE with KAZOO_ALLOW_COOKIE_ROTATION=true on every cluster node'
        fi
    fi

    if [[ $KAZOO_COOKIE_EXPLICIT == true ]]; then
        validate_kazoo_cookie "$KAZOO_COOKIE"
        selected_cookie=$KAZOO_COOKIE
        if [[ -n $stored_cookie && $stored_cookie != "$selected_cookie" ]] ||
           [[ -n $installed_cookie && $installed_cookie != "$selected_cookie" ]]; then
            needs_rotation=true
        fi
    elif [[ -n $stored_cookie ]]; then
        selected_cookie=$stored_cookie
        if weak_kazoo_cookie "$selected_cookie"; then
            needs_rotation=true
        else
            validate_kazoo_cookie "$selected_cookie"
        fi
        [[ -z $installed_cookie || $installed_cookie == "$selected_cookie" ]] || needs_rotation=true
    elif [[ -n $installed_cookie ]] && ! weak_kazoo_cookie "$installed_cookie"; then
        validate_kazoo_cookie "$installed_cookie"
        selected_cookie=$installed_cookie
    elif [[ -n $installed_cookie ]]; then
        needs_rotation=true
    fi

    if [[ $needs_rotation == true && $KAZOO_ALLOW_COOKIE_ROTATION != true ]] &&
       ! coordinated_local_cookie_install; then
        die 'Refusing to rotate an installed Erlang cookie on only part of a deployment; use the same strong KAZOO_COOKIE and KAZOO_ALLOW_COOKIE_ROTATION=true on every affected node'
    fi
    if [[ $needs_rotation == true && $KAZOO_COOKIE_EXPLICIT != true ]] &&
       distributed_cookie_install &&
       { [[ -z $stored_cookie ]] || weak_kazoo_cookie "$stored_cookie"; }; then
        die 'Distributed cookie rotation requires the same explicit strong KAZOO_COOKIE on every affected Kazoo and FreeSWITCH node'
    fi
    if [[ $needs_rotation == true && $KAZOO_COOKIE_EXPLICIT != true ]] &&
       { [[ -z $stored_cookie ]] || weak_kazoo_cookie "$stored_cookie"; }; then
        if [[ $VERIFY_ONLY == true ]]; then
            die 'The installed Erlang cookie requires rotation; run a coordinated installation before verification'
        elif [[ $DRY_RUN == true ]]; then
            selected_cookie=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
            log "Would generate and persist a strong shared Erlang cookie in ${KAZOO_COOKIE_FILE}"
        else
            selected_cookie=$(generate_kazoo_cookie)
            log "Rotating the all-local Kazoo Erlang cookie; the secret is stored in ${KAZOO_COOKIE_FILE}"
        fi
    fi
    if [[ -z $selected_cookie ]]; then
        if [[ $VERIFY_ONLY == true ]]; then
            die "No Kazoo Erlang cookie is installed at ${KAZOO_COOKIE_FILE}"
        elif distributed_cookie_install; then
            die 'Distributed Erlang requires the same strong KAZOO_COOKIE or provisioned KAZOO_COOKIE_FILE on every Kazoo and FreeSWITCH node'
        elif [[ $DRY_RUN == true ]]; then
            selected_cookie=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
            log "Would generate and persist a strong shared Erlang cookie in ${KAZOO_COOKIE_FILE}"
        else
            selected_cookie=$(generate_kazoo_cookie)
            log "Generated a strong shared Erlang cookie in ${KAZOO_COOKIE_FILE}"
        fi
    fi
    validate_kazoo_cookie "$selected_cookie"
    KAZOO_COOKIE=$selected_cookie

    if [[ $DRY_RUN != true && $VERIFY_ONLY != true ]]; then
        if [[ ! -r $KAZOO_COOKIE_FILE ]] ||
           [[ $(tr -d '\r\n' <"$KAZOO_COOKIE_FILE") != "$KAZOO_COOKIE" ]]; then
            printf '%s\n' "$KAZOO_COOKIE" | write_file 0600 "$KAZOO_COOKIE_FILE"
        else
            chmod 0600 "$KAZOO_COOKIE_FILE"
        fi
    fi
    return 0
}

configure_local_epmd_socket() {
    local listener unit node names
    coordinated_local_cookie_install || return 0
    # CouchDB and RabbitMQ also register with this host-wide mapper. A partial
    # install must not strand those unselected services during migration.
    [[ ${SELECTED[couchdb]:-} && ${SELECTED[rabbitmq]:-} ]] || return 0
    log "Binding EPMD to the all-local Erlang interface ${KAZOO_ERLANG_DIST_IP}:4369"
    write_file 0644 /etc/systemd/system/epmd.socket.d/kazoo5-bind.conf <<EOF
[Socket]
ListenStream=
ListenStream=${KAZOO_ERLANG_DIST_IP}:4369
EOF
    run systemctl daemon-reload
    if [[ $DRY_RUN == true || ! -e /usr/lib/systemd/system/epmd.socket ]]; then
        return 0
    fi
    systemctl enable epmd.socket
    listener=$(ss -H -ltn 'sport = :4369' 2>/dev/null || true)
    if [[ $listener == *"${KAZOO_ERLANG_DIST_IP}:4369"* && \
          $listener != *'0.0.0.0:4369'* && $listener != *'[::]:4369'* ]]; then
        return 0
    fi
    names=$(epmd -names 2>/dev/null || true)
    while read -r node; do
        case $node in couchdb|rabbit|kazoo_apps|ecallmgr|freeswitch|'') ;;
            *) die "Cannot migrate EPMD while unrelated Erlang node ${node} is registered" ;;
        esac
    done < <(awk '$1 == "name" {print $2}' <<<"$names")
    # CouchDB may have started its own detached epmd before systemd's socket.
    # Gracefully stop only selected roles, then use epmd's guarded shutdown
    # (which refuses while any node remains registered) before taking ownership.
    for unit in kazoo-ecallmgr kazoo-freeswitch kazoo-apps rabbitmq-server couchdb; do
        if systemctl is-active --quiet "$unit.service"; then
            systemctl stop "$unit.service"
        fi
    done
    systemctl stop epmd.service epmd.socket
    if ss -H -ltn 'sport = :4369' | grep -q .; then
        epmd -kill >/dev/null || die 'EPMD is still in use; cannot safely migrate its listener'
    fi
    systemctl reset-failed epmd.socket epmd.service
    systemctl start epmd.socket
}

verify_local_epmd_socket() {
    local listener
    coordinated_local_cookie_install || return 0
    [[ ${SELECTED[couchdb]:-} && ${SELECTED[rabbitmq]:-} ]] || return 0
    if [[ $DRY_RUN == true ]]; then
        log "Would verify EPMD on ${KAZOO_ERLANG_DIST_IP}:4369 without a wildcard listener"
        return 0
    fi
    listener=$(ss -H -ltn 'sport = :4369' 2>/dev/null || true)
    grep -F "${KAZOO_ERLANG_DIST_IP}:4369" <<<"$listener" >/dev/null ||
        die "EPMD is not bound to ${KAZOO_ERLANG_DIST_IP}:4369"
    [[ $listener != *'0.0.0.0:4369'* && $listener != *'[::]:4369'* ]] ||
        die 'EPMD still has a wildcard listener'
    log "PASS EPMD bound to ${KAZOO_ERLANG_DIST_IP}:4369"
}

verify_cookie_copy() {
    local file=$1 expected_owner=$2 owner mode
    [[ -f $file && ! -L $file ]] || die "Protected Erlang cookie file is missing: ${file}"
    read -r owner mode < <(stat -c '%U %a' "$file")
    [[ $owner == "$expected_owner" && $mode == 400 ]] ||
        die "Erlang cookie file must be mode 0400 and owned by ${expected_owner}: ${file}"
    cmp -s "$KAZOO_COOKIE_FILE" "$file" ||
        die "Erlang cookie file does not match the protected cluster cookie: ${file}"
}

save_deployment_config() {
    local key
    [[ $DRY_RUN != true && $VERIFY_ONLY != true ]] || return 0
    {
        printf '# Kazoo deployment settings, base64 values; managed by %s\n' "$SCRIPT_NAME"
        for key in "${KAZOO_PERSISTED_KEYS[@]}"; do
            [[ -v $key ]] || continue
            printf '%s=' "$key"
            printf '%s' "${!key}" | base64 -w0
            printf '\n'
        done
    } | write_file 0600 "$KAZOO_DEPLOYMENT_CONFIG"
    log "Saved deployment settings in ${KAZOO_DEPLOYMENT_CONFIG} (root-only)"
}

download() {
    local url=$1
    local destination=$2
    if [[ -s $destination ]]; then
        return 0
    fi
    run mkdir -p "$(dirname -- "$destination")"
    if [[ $DRY_RUN == true ]]; then
        log "Would download ${url} to ${destination}"
        return 0
    fi
    curl --fail --location --retry 5 --retry-all-errors \
        --connect-timeout 20 --output "${destination}.part" "$url"
    mv -f "${destination}.part" "$destination"
}

sync_git() {
    local url=$1
    local destination=$2
    local ref=${3:-master}
    # Do not rely on errexit: a caller testing this function's status disables
    # it inside the function, and an unconditional return could hide a failure.
    if [[ ! -d $destination/.git ]]; then
        run mkdir -p "$(dirname -- "$destination")" || die 'Cannot prepare source parent directory'
        if [[ $ref =~ ^[0-9a-fA-F]{40}$ ]]; then
            run mkdir -p "$destination" || die 'Cannot prepare source directory'
            run git -C "$destination" init || die 'Cannot initialize source repository'
            run git -C "$destination" remote add origin "$url" || die 'Cannot configure source remote'
            run git -C "$destination" fetch --depth 1 origin "$ref" || die 'Cannot fetch required source revision'
            run git -C "$destination" checkout --detach FETCH_HEAD || die 'Cannot check out required source revision'
            if [[ $DRY_RUN != true ]]; then
                [[ $(git -C "$destination" rev-parse --verify HEAD) == "${ref,,}" ]] ||
                    die 'Checked-out source does not match required revision'
            fi
        else
            run git clone --branch "$ref" --depth 1 "$url" "$destination" || die 'Cannot clone required source branch'
        fi
        return 0
    fi
    if [[ $DRY_RUN == true ]]; then
        log "Would fast-forward ${destination} from ${url} (${ref})"
        return 0
    fi
    git -C "$destination" remote set-url origin "$url" || die 'Cannot configure source remote'
    git -C "$destination" fetch --depth 1 origin "$ref" || die 'Cannot fetch required source revision'
    if [[ $ref =~ ^[0-9a-fA-F]{40}$ ]]; then
        git -C "$destination" checkout --detach FETCH_HEAD || die 'Cannot check out required source revision'
        [[ $(git -C "$destination" rev-parse --verify HEAD) == "${ref,,}" ]] ||
            die 'Checked-out source does not match required revision'
    elif git -C "$destination" show-ref --verify --quiet "refs/remotes/origin/${ref}"; then
        git -C "$destination" checkout "$ref" || die 'Cannot check out required source branch'
        git -C "$destination" merge --ff-only FETCH_HEAD || die 'Cannot fast-forward source branch'
    else
        git -C "$destination" checkout --detach FETCH_HEAD || die 'Cannot check out fetched source revision'
    fi
}

# Metadata refresh is safe to pause; arbitrary DNF/RPM transactions are not.
# Restore the timer's active state even when installation or a signal fails.
KAZOO_DNF_GUARD_HELD=false
with_dnf_guard() (
    [[ $DRY_RUN != true && $KAZOO_DNF_GUARD_HELD != true ]] || { "$@"; return; }
    local timer_state cache_state cache_command restore_timer=false
    trap 'rc=$?; trap - EXIT; if [[ $restore_timer == true ]]; then timeout 60 systemctl start dnf-makecache.timer || rc=1; fi; exit "$rc"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    timer_state=$(systemctl show --value -p ActiveState dnf-makecache.timer) || return 1
    if [[ $timer_state == active || $timer_state == activating ]]; then
        restore_timer=true
        timeout 60 systemctl stop dnf-makecache.timer || return 1
    fi
    cache_state=$(systemctl show --value -p ActiveState dnf-makecache.service) || return 1
    if [[ $cache_state == active || $cache_state == activating ]]; then
        cache_command=$(systemctl show --value -p ExecStart dnf-makecache.service) || return 1
        [[ $cache_command == '{ path=/usr/bin/dnf ; argv[]=/usr/bin/dnf makecache --timer ; '* &&
           ${cache_command#*'{ path='} != *'{ path='* ]] ||
            die 'Nonstandard dnf-makecache service; refusing to interrupt an unknown package operation'
        log 'Pausing the OS metadata refresh while installing packages; its timer will be restored' >&2
        timeout 60 systemctl stop dnf-makecache.service || return 1
    fi
    # A different package manager owner is not ours to terminate. Refuse its
    # lock promptly instead of waiting indefinitely behind an unknown writer.
    KAZOO_DNF_GUARD_HELD=true
    "$@"
)

dnf_transaction() {
    with_dnf_guard run dnf --setopt=exit_on_lock=True "$@"
}

dnf_install() {
    dnf_transaction install -y "$@"
}

service_local_addresses() {
    local unit=$1
    case $unit in
        couchdb.service) printf '%s' "$KAZOO_COUCHDB_BIND" ;;
        rabbitmq-server.service) printf '%s' "$KAZOO_RABBITMQ_BIND" ;;
        haproxy.service) printf '%s' "$KAZOO_HAPROXY_BIND" ;;
        kazoo-apps.service|kazoo-ecallmgr.service|kazoo-freeswitch.service)
            printf '%s' "$KAZOO_ERLANG_DIST_IP" ;;
        kazoo-kamailio.service) printf '%s' "$KAZOO_PUBLIC_IP" ;;
        *) return 0 ;;
    esac
}

install_service_address_gate() {
    local unit=$1 addresses
    addresses=$(service_local_addresses "$unit")
    [[ -n $addresses ]] || return 0
    validate_config_directory /usr/local/libexec
    run install -d -o root -g root -m 0755 /usr/local/libexec
    run install -m 0755 "$SCRIPT_DIR/wait-kazoo-local-address.py" /usr/local/libexec/kazoo5-wait-local-address
    write_file 0644 "/etc/systemd/system/${unit}.d/30-kazoo-local-address.conf" <<EOF
[Unit]
Wants=network-online.target
After=network-online.target

[Service]
ExecStartPre=/usr/local/libexec/kazoo5-wait-local-address --timeout 120 ${addresses}
TimeoutStartSec=180
Restart=on-failure
RestartSec=5
EOF
}

verify_service_address_gate() {
    local unit=$1 addresses commands
    addresses=$(service_local_addresses "$unit")
    [[ -n $addresses ]] || return 0
    cmp -s "$SCRIPT_DIR/wait-kazoo-local-address.py" /usr/local/libexec/kazoo5-wait-local-address || \
        die 'Installed local-address startup helper differs; reinstall the selected role'
    commands=$(systemctl show "$unit" -p ExecStartPre --value) || die 'Cannot inspect address startup gate'
    [[ $commands == *"argv[]=/usr/local/libexec/kazoo5-wait-local-address --timeout 120 ${addresses} ;"* ]] || \
        die "${unit} is missing the configured local-address startup gate"
}

service_enable_restart() {
    local unit=$1
    install_service_address_gate "$unit"
    run systemctl daemon-reload
    run systemctl enable "$unit"
    run systemctl restart "$unit"
}

wait_for_port() {
    local host=$1
    local port=$2
    local timeout=${3:-90}
    local elapsed=0
    if [[ $DRY_RUN == true ]]; then
        log "Would wait for ${host}:${port}"
        return 0
    fi
    while ! timeout 1 bash -c "</dev/tcp/${host}/${port}" 2>/dev/null; do
        ((elapsed += 1))
        if (( elapsed >= timeout )); then
            return 1
        fi
        sleep 1
    done
}

check_sip_options() {
    local host=$1
    local port=${2:-5060}
    [[ $DRY_RUN != true ]] || { log "Would send SIP OPTIONS to ${host}:${port}"; return 0; }
    python3 - "$host" "$port" <<'PY'
import random
import socket
import sys

host = sys.argv[1]
port = int(sys.argv[2])
branch = f"z9hG4bK-kazoo5-{random.getrandbits(48):012x}"
tag = f"kz5-{random.getrandbits(32):08x}"
call_id = f"kz5-{random.getrandbits(64):016x}@127.0.0.1"
payload = (
    f"OPTIONS sip:{host}:{port} SIP/2.0\r\n"
    f"Via: SIP/2.0/UDP 127.0.0.1:0;branch={branch};rport\r\n"
    f"From: <sip:kazoo5-check@127.0.0.1>;tag={tag}\r\n"
    f"To: <sip:{host}>\r\n"
    f"Call-ID: {call_id}\r\n"
    "CSeq: 1 OPTIONS\r\n"
    "Max-Forwards: 1\r\n"
    "Content-Length: 0\r\n\r\n"
).encode()
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.settimeout(5)
sock.bind(("127.0.0.1", 0))
sock.sendto(payload, (host, port))
data, _ = sock.recvfrom(65535)
status = data.split(b"\r\n", 1)[0]
if not status.startswith(b"SIP/2.0 200"):
    raise SystemExit(f"unexpected SIP OPTIONS response: {status.decode(errors='replace')}")
PY
}

assert_service() {
    local unit=$1
    verify_service_address_gate "$unit"
    systemctl is-enabled --quiet "$unit" || die "${unit} is not enabled"
    systemctl is-active --quiet "$unit" || {
        systemctl --no-pager --full status "$unit" >&2 || true
        journalctl -u "$unit" -n 80 --no-pager >&2 || true
        die "${unit} is not active"
    }
    log "PASS service enabled and active: ${unit}"
}

normalize_component() {
    local value=${1,,}
    value=${value//_/-}
    value=${value// /-}
    case "$value" in
        couch|couchdb) printf 'couchdb\n' ;;
        rabbit|rabbitmq|rabbitmq-server) printf 'rabbitmq\n' ;;
        haproxy) printf 'haproxy\n' ;;
        apps|kazoo|kazoo-apps|kazoo-applications) printf 'kazoo-apps\n' ;;
        ecallmgr|ecall-manager) printf 'ecallmgr\n' ;;
        freeswitch|kazoo-freeswitch) printf 'freeswitch\n' ;;
        kamailio|kamaialio|kazoo-kamailio) printf 'kamailio\n' ;;
        monster|monster-ui) printf 'monster-ui\n' ;;
        bridge|mobile-bridge|push-bridge|kazoo-push-bridge) printf 'push-bridge\n' ;;
        all) printf 'all\n' ;;
        *) return 1 ;;
    esac
}

select_component() {
    local component=$1
    case "$component" in
        couchdb)
            SELECTED[couchdb]=1
            ;;
        rabbitmq)
            SELECTED[rabbitmq]=1
            ;;
        haproxy)
            SELECTED[haproxy]=1
            ;;
        kazoo-apps)
            SELECTED[kazoo-apps]=1
            ;;
        ecallmgr)
            SELECTED[ecallmgr]=1
            ;;
        freeswitch)
            SELECTED[freeswitch]=1
            ;;
        kamailio)
            SELECTED[kamailio]=1
            ;;
        monster-ui)
            SELECTED[monster-ui]=1
            ;;
        push-bridge)
            SELECTED[push-bridge]=1
            ;;
        all)
            select_component couchdb
            select_component rabbitmq
            select_component haproxy
            select_component kazoo-apps
            select_component ecallmgr
            select_component freeswitch
            select_component kamailio
            select_component monster-ui
            select_component push-bridge
            ;;
        *) die "Internal error: unknown component ${component}" ;;
    esac
}

parse_arguments() {
    local normalized
    while (($#)); do
        case "$1" in
            --dry-run) DRY_RUN=true ;;
            --verify-only) VERIFY_ONLY=true ;;
            --couchdb-host)
                (($# >= 2)) || die '--couchdb-host requires a value'
                KAZOO_COUCHDB_HOST=$2
                shift
                ;;
            --amqp-host)
                (($# >= 2)) || die '--amqp-host requires a value'
                KAZOO_AMQP_HOST=$2
                KAZOO_AMQP_URI=
                KAZOO_AMQP_URI_EXPLICIT=false
                KAZOO_AMQP_SPLIT_OVERRIDE=true
                shift
                ;;
            --api-url)
                (($# >= 2)) || die '--api-url requires a value'
                KAZOO_API_URL=$2
                shift
                ;;
            --public-ip)
                (($# >= 2)) || die '--public-ip requires a value'
                KAZOO_PUBLIC_IP=$2
                shift
                ;;
            --erlang-dist-ip)
                (($# >= 2)) || die '--erlang-dist-ip requires a value'
                KAZOO_ERLANG_DIST_IP=$2
                shift
                ;;
            --hostname|--tls-cert|--tls-key|--tls-chain|--api-upstream)
                (($# >= 2)) || die "$1 requires a value"
                case $1 in
                    --hostname) KAZOO_PUBLIC_HOSTNAME=$2 ;;
                    --tls-cert) KAZOO_TLS_CERT_FILE=$2 ;;
                    --tls-key) KAZOO_TLS_KEY_FILE=$2 ;;
                    --tls-chain) KAZOO_TLS_CHAIN_FILE=$2 ;;
                    --api-upstream) KAZOO_API_UPSTREAM=$2 ;;
                esac
                shift
                ;;
            --list)
                printf '%s\n' couchdb rabbitmq haproxy kazoo-apps ecallmgr freeswitch kamailio monster-ui push-bridge all
                exit 0
                ;;
            -h|--help) usage; exit 0 ;;
            --) shift; REQUESTED+=("$@"); break ;;
            -*) die "Unknown option: $1" ;;
            *) REQUESTED+=("$1") ;;
        esac
        shift
    done
    ((${#REQUESTED[@]})) || { usage >&2; exit 2; }
    for component in "${REQUESTED[@]}"; do
        normalized=$(normalize_component "$component") || die "Unknown component: ${component}"
        select_component "$normalized"
    done
}

check_build_disk_space() {
    local probe_path=$KAZOO_BUILD_ROOT
    local available_mb
    local build_heavy=false
    [[ $DRY_RUN != true && $VERIFY_ONLY != true ]] || return 0
    if [[ ${SELECTED[kazoo-apps]:-} || ${SELECTED[ecallmgr]:-} || \
          ${SELECTED[freeswitch]:-} || ${SELECTED[monster-ui]:-} ]]; then
        build_heavy=true
    fi
    [[ $build_heavy == true ]] || return 0
    while [[ ! -e $probe_path && $probe_path != / ]]; do
        probe_path=$(dirname -- "$probe_path")
    done
    available_mb=$(df -Pm -- "$probe_path" | awk 'NR == 2 {print $4}')
    [[ $available_mb =~ ^[0-9]+$ ]] || die "Could not determine free space for ${KAZOO_BUILD_ROOT}"
    log "Build filesystem free space: ${available_mb} MiB"
    ((available_mb >= KAZOO_MIN_BUILD_FREE_MB)) || \
        die "Build-heavy selections require at least ${KAZOO_MIN_BUILD_FREE_MB} MiB free under ${probe_path}"
    if ((available_mb < 10240)); then
        warn 'Less than 10 GiB is free; this is below the recommended temporary build headroom'
    fi
}

detect_primary_ipv4() {
    local address
    # Private-only nodes may have no external route. Do not exit under
    # errexit/pipefail before reaching the intended loopback fallback.
    address=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}') || address=
    printf '%s\n' "${address:-127.0.0.1}"
}

validate_monster_endpoint() {
    # Pure Bash preflight: no downloaded runtime is needed, and rejected values
    # are never echoed (they may contain accidentally supplied credentials).
    local name=$1 value=$2 schemes=$3 suffix=$4 authority host last_label port
    local pattern="^(${schemes})://([a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?\\.?(:[0-9]{1,5})?)(/[a-zA-Z0-9._~/-]*)?$"
    [[ $value =~ $pattern ]] || die "${name} must be a credentials-free URL with a DNS/IPv4 host and no query or fragment"
    authority=${BASH_REMATCH[2]}
    host=${authority%%:*}
    last_label=${host%.}
    last_label=${last_label##*.}
    # Browser URL parsers treat numeric final labels as IPv4, including short
    # and hexadecimal forms. Accept only our normal dotted-decimal contract.
    if [[ $last_label =~ ^([0-9]+|0[xX][0-9a-fA-F]+)$ ]]; then
        [[ $host != *. ]] || die "${name} has an invalid IPv4 host"
        is_ipv4_address "$host" || die "${name} has an invalid IPv4 host"
    fi
    if [[ $authority == *:* ]]; then
        port=${authority##*:}
        (( 10#$port >= 1 && 10#$port <= 65535 )) || die "${name} has an invalid port"
    fi
    [[ ! ${value#*://} =~ /\.\.?(/|$) ]] || die "${name} must not contain dot path segments"
    [[ -z $suffix || $value == *"$suffix" ]] || die "${name} has an invalid endpoint path"
}

validate_monster_endpoints() {
    validate_monster_endpoint KAZOO_API_URL "$KAZOO_API_URL" 'http|https' '/v2/'
    validate_monster_endpoint KAZOO_API_UPSTREAM "$KAZOO_API_UPSTREAM" 'http|https' '/v2/'
    validate_monster_endpoint KAZOO_WEBSOCKET_UPSTREAM "$KAZOO_WEBSOCKET_UPSTREAM" 'http|https' '/websocket'
    # nginx proxy paths are deliberately exact, not arbitrary URL prefixes.
    [[ $KAZOO_API_UPSTREAM =~ ^https?://[^/]+/v2/$ ]] || die 'KAZOO_API_UPSTREAM must use /v2/'
    [[ $KAZOO_WEBSOCKET_UPSTREAM =~ ^https?://[^/]+/websocket$ ]] || die 'KAZOO_WEBSOCKET_UPSTREAM must use /websocket'
    case $MONSTER_UI_WEBSOCKET_URL in
        auto|same-origin|disabled) ;;
        *) validate_monster_endpoint MONSTER_UI_WEBSOCKET_URL "$MONSTER_UI_WEBSOCKET_URL" 'ws|wss' ''
           [[ ! $MONSTER_UI_WEBSOCKET_URL =~ ^wss?://[^/]+/undefined$ ]] || die 'MONSTER_UI_WEBSOCKET_URL must not use /undefined' ;;
    esac
}

validate_build_login_environment() {
    [[ $DRY_RUN != true && $VERIFY_ONLY != true ]] || return 0
    [[ ${SELECTED[kazoo-apps]:-} || ${SELECTED[ecallmgr]:-} ]] || return 0
    [[ ${HOME:-} == /* && -d ${HOME:-} ]] ||
        die 'Erlang source builds require a login home; use sudo -i or systemd-run --property=User=root. No installation changes were made.'
}

preflight() {
    validate_build_login_environment
    [[ -r /etc/os-release ]] || die '/etc/os-release is missing'
    # shellcheck disable=SC1091
    source /etc/os-release
    [[ ${ID:-} == rocky ]] || \
        die "This tested installer supports Rocky Linux 9 only; found ${ID:-unknown}"
    [[ ${VERSION_ID%%.*} == 9 ]] || die "Rocky Linux 9 is required; found ${VERSION_ID:-unknown}"
    validate_install_directory KAZOO_ROOT "$KAZOO_ROOT"
    [[ -d $KAZOO_ROOT/.git ]] || die "KAZOO_ROOT is not a Git checkout: ${KAZOO_ROOT}"
    validate_install_directory KAZOO_BUILD_ROOT "$KAZOO_BUILD_ROOT"
    validate_install_directory KAZOO_CACHE_DIR "$KAZOO_CACHE_DIR"
    validate_install_directory KAZOO_CONFIG_DIR "$KAZOO_CONFIG_DIR"
    [[ $KAZOO_INSTALLER_SECRETS == /* && $KAZOO_INSTALLER_SECRETS != / && \
       ! $KAZOO_INSTALLER_SECRETS =~ [[:space:]] ]] || \
        die 'KAZOO_INSTALLER_SECRETS must be an absolute file path without whitespace'
    command -v systemctl >/dev/null || die 'systemd is required'
    if [[ $DRY_RUN != true && $VERIFY_ONLY != true && $EUID -ne 0 ]]; then
        die 'Run installation as root (sudo)'
    fi
    [[ $KAZOO_MAKE_JOBS =~ ^[1-9][0-9]*$ ]] || die 'KAZOO_MAKE_JOBS must be a positive integer'
    [[ $KAZOO_MIN_BUILD_FREE_MB =~ ^[1-9][0-9]*$ ]] || \
        die 'KAZOO_MIN_BUILD_FREE_MB must be a positive integer'
    if (( KAZOO_MAKE_JOBS > 2 )); then
        KAZOO_MAKE_JOBS=2
    fi
    KAZOO_HOSTNAME=$(hostname -f 2>/dev/null || hostname)
    if [[ $KAZOO_HOSTNAME == *.* ]]; then
        KAZOO_NODE_NAME_TYPE=-name
        KAZOO_FREESWITCH_SHORTNAME=false
    else
        # Long distributed-Erlang node names reject unqualified hostnames.
        # Short names keep single-node lab installs valid without weakening
        # normal FQDN-based clustered deployments.
        KAZOO_NODE_NAME_TYPE=-sname
        KAZOO_FREESWITCH_SHORTNAME=true
    fi
    resolve_amqp_uri
    if [[ -z $KAZOO_PUBLIC_IP ]]; then
        KAZOO_PUBLIC_IP=$(detect_primary_ipv4)
    fi
    if [[ -n $KAZOO_PUBLIC_HOSTNAME ]]; then
        KAZOO_API_URL=${KAZOO_API_URL:-https://${KAZOO_PUBLIC_HOSTNAME}/v2/}
    else
        # Fresh UI deployments use nginx's same-origin API proxy. Explicit or
        # saved external API endpoints remain the operator's configuration.
        KAZOO_API_URL=${KAZOO_API_URL:-http://${KAZOO_PUBLIC_IP}/v2/}
    fi
    validate_monster_endpoints
    KAZOO_MASTER_ACCOUNT_REALM=${KAZOO_MASTER_ACCOUNT_REALM:-master.${KAZOO_HOSTNAME//_/-}}
    validate_port KAZOO_COUCHDB_PORT "$KAZOO_COUCHDB_PORT"
    validate_port KAZOO_COUCHDB_ADMIN_PORT "$KAZOO_COUCHDB_ADMIN_PORT"
    validate_port KAZOO_AMQP_PORT "$KAZOO_AMQP_PORT"
    [[ $KAZOO_START_TIMEOUT =~ ^[1-9][0-9]*$ ]] || die 'KAZOO_START_TIMEOUT must be a positive integer'
    [[ $KAZOO_FREESWITCH_STABILITY_SECONDS =~ ^[1-9][0-9]*$ ]] || \
        die 'KAZOO_FREESWITCH_STABILITY_SECONDS must be a positive integer'
    [[ $KAZOO_REQUIRE_MEDIA_CONNECTION == auto || \
       $KAZOO_REQUIRE_MEDIA_CONNECTION == true || \
       $KAZOO_REQUIRE_MEDIA_CONNECTION == false ]] || \
        die 'KAZOO_REQUIRE_MEDIA_CONNECTION must be auto, true, or false'
    [[ $KAZOO_BOOTSTRAP_MASTER_ACCOUNT == true || $KAZOO_BOOTSTRAP_MASTER_ACCOUNT == false ]] || \
        die 'KAZOO_BOOTSTRAP_MASTER_ACCOUNT must be true or false'
    [[ $KAZOO_COUCHDB_HOST =~ ^[a-zA-Z0-9._-]+$ ]] || die 'KAZOO_COUCHDB_HOST is invalid'
    [[ $KAZOO_AMQP_HOST =~ ^[a-zA-Z0-9._-]+$ ]] || die 'KAZOO_AMQP_HOST is invalid'
    is_ipv4_address "$KAZOO_COUCHDB_BIND" || die 'KAZOO_COUCHDB_BIND must be an IPv4 address'
    is_ipv4_address "$KAZOO_RABBITMQ_BIND" || die 'KAZOO_RABBITMQ_BIND must be an IPv4 address'
    is_ipv4_address "$KAZOO_HAPROXY_BIND" || die 'KAZOO_HAPROXY_BIND must be an IPv4 address'
    is_ipv4_address "$KAZOO_PUBLIC_IP" || die 'KAZOO_PUBLIC_IP must be an IPv4 address'
    is_ipv4_address "$KAZOO_ERLANG_DIST_IP" || \
        die 'KAZOO_ERLANG_DIST_IP must be an IPv4 address'
    if cookie_component_selected && [[ $KAZOO_ERLANG_DIST_IP == 0.0.0.0 ]]; then
        die 'KAZOO_ERLANG_DIST_IP must name a loopback or explicit private interface, not 0.0.0.0'
    fi
    resolve_kazoo_cookie
    [[ $KAZOO_APPS_LIST =~ ^[a-zA-Z0-9_,-]+$ ]] || \
        die 'KAZOO_APPS_LIST must be a comma-separated list of application names'
    [[ $MONSTER_UI_APPS_LIST =~ ^[a-z0-9,-]+$ ]] || \
        die 'MONSTER_UI_APPS_LIST must be a comma-separated list of supported app names'
    [[ $MONSTER_UI_REGISTER_APPS == auto || $MONSTER_UI_REGISTER_APPS == true || \
       $MONSTER_UI_REGISTER_APPS == false ]] || \
        die 'MONSTER_UI_REGISTER_APPS must be auto, true, or false'
    monster_catalog_preflight
    [[ $MONSTER_UI_NODE_MAJOR == 18 ]] || \
        die 'Monster UI 5.5.13 requires the tested Node.js 18 build toolchain'
    [[ $MONSTER_UI_LOCK_SHA256 =~ ^[a-f0-9]{64}$ ]] || \
        die 'MONSTER_UI_LOCK_SHA256 must identify the exact reviewed framework dependency lock'
    validate_install_directory MONSTER_UI_WEB_ROOT "$MONSTER_UI_WEB_ROOT"
    [[ $KAZOO_FREESWITCH_NODES =~ ^[a-zA-Z0-9_.@,-]*$ ]] || \
        die 'KAZOO_FREESWITCH_NODES must contain comma-separated Erlang node names'
    if cookie_component_selected; then
        validate_kazoo_cookie "$KAZOO_COOKIE"
    fi
    [[ $KAZOO_COUCHDB_USER =~ ^[a-zA-Z0-9_.@-]+$ ]] || die 'KAZOO_COUCHDB_USER is invalid'
    [[ $KAZOO_COUCHDB_PASSWORD =~ ^[a-zA-Z0-9_.@!%+=:-]+$ ]] || \
        die 'KAZOO_COUCHDB_PASSWORD contains unsupported characters'
    [[ $KAZOO_RABBITMQ_USER =~ ^[a-zA-Z0-9_.@-]+$ ]] || die 'KAZOO_RABBITMQ_USER is invalid'
    [[ $KAZOO_RABBITMQ_PASSWORD =~ ^[a-zA-Z0-9_.@!%+=:-]+$ ]] || \
        die 'KAZOO_RABBITMQ_PASSWORD contains unsupported characters'
    [[ $KAZOO_MASTER_ACCOUNT_NAME =~ ^[a-zA-Z0-9_.@-]+$ ]] || \
        die 'KAZOO_MASTER_ACCOUNT_NAME contains unsupported characters'
    [[ $KAZOO_MASTER_ACCOUNT_REALM =~ ^[a-zA-Z0-9.-]+$ ]] || \
        die 'KAZOO_MASTER_ACCOUNT_REALM is invalid'
    [[ $KAZOO_MASTER_ADMIN_USER =~ ^[a-zA-Z0-9_.@-]+$ ]] || \
        die 'KAZOO_MASTER_ADMIN_USER is invalid'
    validate_safe_value KAZOO_AMQP_URI "$KAZOO_AMQP_URI"
    case $KAZOO_AMQP_URI in
        amqp://*|amqps://*) ;;
        *) die 'KAZOO_AMQP_URI must begin with amqp:// or amqps://' ;;
    esac
    [[ $KAZOO_AMQP_URI != *[[:space:]]* && $KAZOO_AMQP_URI != *'!'* && \
       $KAZOO_AMQP_URI != *\'* && $KAZOO_AMQP_URI != *'"'* && \
       $KAZOO_AMQP_URI != *\\* ]] || \
        die 'KAZOO_AMQP_URI contains characters unsafe for generated Kazoo/Kamailio configuration; percent-encode them'
    if [[ ${SELECTED[freeswitch]:-} ]] && \
       [[ $KAZOO_AMQP_URI != "$(amqp_uri_from_split_settings)" ]]; then
        if [[ $KAZOO_AMQP_URI_EXPLICIT == true ]]; then
            die 'FreeSWITCH cannot consume an explicit KAZOO_AMQP_URI directly; use KAZOO_AMQP_HOST, KAZOO_AMQP_PORT, KAZOO_RABBITMQ_USER, KAZOO_RABBITMQ_PASSWORD, and KAZOO_RABBITMQ_VHOST consistently instead'
        fi
        die 'The saved KAZOO_AMQP_URI conflicts with FreeSWITCH split AMQP settings; override KAZOO_AMQP_HOST (or the other split settings) to rebuild and save a consistent URI'
    fi
    validate_safe_value KAZOO_RABBITMQ_VHOST "$KAZOO_RABBITMQ_VHOST"
    validate_safe_value KAZOO_MASTER_ADMIN_PASSWORD "$KAZOO_MASTER_ADMIN_PASSWORD"
    if [[ ${SELECTED[couchdb]:-} ]] && ! is_loopback_address "$KAZOO_COUCHDB_BIND" && \
       [[ $KAZOO_COUCHDB_USER == admin && $KAZOO_COUCHDB_PASSWORD == admin ]]; then
        die 'Refusing to expose CouchDB with admin/admin; set strong CouchDB credentials or bind it to 127.0.0.1'
    fi
    if [[ ${SELECTED[rabbitmq]:-} ]] && ! is_loopback_address "$KAZOO_RABBITMQ_BIND" && \
       [[ $KAZOO_RABBITMQ_PASSWORD == change_me ]]; then
        die 'Refusing to expose RabbitMQ with the default password; set KAZOO_RABBITMQ_PASSWORD or bind it to 127.0.0.1'
    fi
    [[ $FREESWITCH_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
        die 'FREESWITCH_VERSION must be a semantic version such as 1.11.3'
    [[ $RABBITMQ_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
        die 'RABBITMQ_VERSION must be a semantic version such as 3.13.7'
    [[ $ERLANG_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
        die 'ERLANG_VERSION must be a semantic version such as 26.2.5'
    [[ $HTMLDOC_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
        die 'HTMLDOC_VERSION must be a semantic version such as 1.9.23'
    [[ $COUCHDB_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?-[0-9]+\.el9$ ]] || \
        die 'COUCHDB_VERSION must be a Rocky 9 package version such as 3.5.2.1-1.el9'
    [[ $KAMAILIO_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
        die 'KAMAILIO_VERSION must be a semantic version such as 6.1.4'
    [[ $KAMAILIO_CONFIG_REF =~ ^[a-zA-Z0-9._/-]+$ ]] || \
        die 'KAMAILIO_CONFIG_REF contains unsupported characters'
    [[ $HTMLDOC_REF =~ ^[0-9a-f]{40}$ && $FREESWITCH_REF =~ ^[0-9a-f]{40}$ && \
       $SOFIA_SIP_REF =~ ^[0-9a-f]{40}$ && $SPANDSP_REF =~ ^[0-9a-f]{40}$ && \
       $MOD_KAZOO_REF =~ ^[0-9a-f]{40}$ && $FREESWITCH_CONFIG_REF =~ ^[0-9a-f]{40}$ && \
       $KAZOO_CORE_CONFIG_REF =~ ^[0-9a-f]{40}$ && $ACDC_REF =~ ^[0-9a-f]{40}$ && \
       $KAZOO_CORE_REF =~ ^[0-9a-f]{40}$ && $KAZOO_CROSSBAR_REF =~ ^[0-9a-f]{40}$ && \
       $KAZOO_BLACKHOLE_REF =~ ^[0-9a-f]{40}$ && \
       $KAZOO_SOUNDS_REF =~ ^[0-9a-f]{40}$ && $KAZOO_ECALLMGR_REF =~ ^[0-9a-f]{40}$ && \
       $KAZOO_STEPSWITCH_REF =~ ^[0-9a-f]{40}$ && $KAZOO_CDR_REF =~ ^[0-9a-f]{40}$ && \
       $KAMAILIO_CONFIG_REF =~ ^[0-9a-f]{40}$ && $MONSTER_UI_REF =~ ^[0-9a-f]{40}$ && \
       $MONSTER_UI_ACCOUNTS_REF =~ ^[0-9a-f]{40}$ && \
       $MONSTER_UI_CALLFLOWS_REF =~ ^[0-9a-f]{40}$ && \
       $MONSTER_UI_CSV_ONBOARDING_REF =~ ^[0-9a-f]{40}$ && \
       $MONSTER_UI_FAX_REF =~ ^[0-9a-f]{40}$ && \
       $MONSTER_UI_NUMBERS_REF =~ ^[0-9a-f]{40}$ && \
       $MONSTER_UI_PBXS_REF =~ ^[0-9a-f]{40}$ && \
       $MONSTER_UI_VOICEMAILS_REF =~ ^[0-9a-f]{40}$ && \
       $MONSTER_UI_WEBHOOKS_REF =~ ^[0-9a-f]{40}$ && \
       $MONSTER_UI_VOIP_REF =~ ^[0-9a-f]{40}$ ]] || \
        die 'Pinned Kazoo integration source refs must be full lowercase commit hashes'
    [[ $KAMAILIO_CHILDREN =~ ^[1-9][0-9]*$ && $KAMAILIO_TCP_CHILDREN =~ ^[1-9][0-9]*$ ]] || \
        die 'Kamailio child counts must be positive integers'
    [[ $KAMAILIO_AMQP_CONSUMERS =~ ^[1-9][0-9]*$ && $KAMAILIO_AMQP_WORKERS =~ ^[1-9][0-9]*$ ]] || \
        die 'Kamailio AMQP worker counts must be positive integers'
    check_build_disk_space
    validate_tls_configuration
    log "Host: ${KAZOO_HOSTNAME} (${KAZOO_PUBLIC_IP}); Erlang mode ${KAZOO_NODE_NAME_TYPE}"
    log "Kazoo source: ${KAZOO_ROOT}"
    log "Endpoints: CouchDB ${KAZOO_COUCHDB_HOST}:${KAZOO_COUCHDB_PORT}; AMQP ${KAZOO_AMQP_HOST}:${KAZOO_AMQP_PORT}; Erlang ${KAZOO_ERLANG_DIST_IP}:11500-11999; API ${KAZOO_API_URL}"
}

ensure_crb_repository() {
    # config-manager --set-enabled always saves the repository file. Rewriting
    # rocky.repo on every deployment expires otherwise usable metadata for its
    # sibling BaseOS/AppStream repositories as well. Do not change enabled CRB.
    if [[ $DRY_RUN == true ]]; then
        run dnf config-manager --set-enabled crb
        return
    fi
    local configuration enabled
    configuration=$(dnf -q config-manager --dump crb) || die 'Cannot inspect CRB repository configuration'
    enabled=$(awk '$1 == "enabled" && $2 == "=" {print $3}' <<<"$configuration")
    case $enabled in
        1) return ;;
        0) run dnf config-manager --set-enabled crb ;;
        *) die 'Missing or ambiguous CRB repository enabled state' ;;
    esac
    configuration=$(dnf -q config-manager --dump crb) || die 'Cannot verify CRB repository configuration'
    enabled=$(awk '$1 == "enabled" && $2 == "=" {print $3}' <<<"$configuration")
    [[ $enabled == 1 ]] || die 'CRB repository did not become enabled'
}

install_base_dependencies() {
    local curl_package=curl
    log 'Installing Rocky Linux repositories and base tooling'
    dnf_install dnf-plugins-core epel-release
    ensure_crb_repository
    # Rocky minimal/cloud images already supply curl-minimal. Both providers
    # support our HTTP(S) transfers; requesting full curl conflicts with the
    # installed minimal RPM. Preserve the provider instead of broad erasure.
    if rpm -q curl-minimal >/dev/null 2>&1; then curl_package=curl-minimal; fi
    dnf_install \
        bash-completion ca-certificates "$curl_package" diffutils findutils git gzip iproute jq logrotate \
        openssl procps-ng python3 rsync tar unzip util-linux wget which zip
    run mkdir -p "$KAZOO_BUILD_ROOT" "$KAZOO_CACHE_DIR" "$KAZOO_CONFIG_DIR"
}

couchdb_curl() {
    local credential="${KAZOO_COUCHDB_USER}:${KAZOO_COUCHDB_PASSWORD}"
    validate_safe_value 'CouchDB credentials' "$credential"
    credential=${credential//\\/\\\\}
    credential=${credential//\"/\\\"}
    printf 'user = "%s"\n' "$credential" | curl --config - "$@"
}

configure_couchdb_cookie() {
    local couch_root=${1:-/opt/couchdb} owner=${2:-couchdb:couchdb}
    local arguments="$couch_root/etc/vm.args" cookie_file="$couch_root/.erlang.cookie"
    local line literal cookie='' saved_cookie='' cookie_count=0
    local -a argument_lines=()
    if [[ $DRY_RUN == true ]]; then
        log 'Would preserve the CouchDB cluster cookie in a private file, outside process arguments'
        return 0
    fi
    [[ -f $arguments && ! -L $arguments ]] || die 'CouchDB vm.args must be a regular file'
    while IFS= read -r line || [[ -n $line ]]; do
        if [[ $line =~ ^[[:space:]]*-setcookie[[:space:]]+(.+)$ ]]; then
            literal=${BASH_REMATCH[1]}
            # Accept the dedicated, optionally quoted cookie line used by the
            # package. Never evaluate shell/Erlang source or guess at custom flags.
            if [[ $literal == \"*\" || $literal == \'*\' ]]; then
                literal=${literal:1:${#literal}-2}
            fi
            [[ $literal =~ ^[a-zA-Z0-9_@.-]{1,255}$ ]] || \
                die 'Unsupported CouchDB cookie syntax; use one dedicated -setcookie line'
            cookie=$literal
            cookie_count=$((cookie_count + 1))
            argument_lines+=('# Cluster authentication is loaded from the CouchDB user .erlang.cookie file.')
        else
            if [[ ! $line =~ ^[[:space:]]*# && $line =~ (^|[[:space:]])-setcookie([[:space:]]|$) ]]; then
                die 'Ambiguous CouchDB cookie arguments; no configuration was changed'
            fi
            argument_lines+=("$line")
        fi
    done <"$arguments"
    ((cookie_count <= 1)) || die 'Multiple CouchDB cookie arguments; no configuration was changed'
    if [[ -e $cookie_file || -L $cookie_file ]]; then
        [[ -f $cookie_file && ! -L $cookie_file ]] || die 'CouchDB cookie must be a regular file'
        saved_cookie=$(<"$cookie_file")
        [[ $saved_cookie =~ ^[a-zA-Z0-9_@.-]{1,255}$ ]] || die 'Invalid existing CouchDB cookie file'
        [[ -z $cookie || $cookie == "$saved_cookie" ]] || \
            die 'CouchDB cookie sources disagree; refusing to replace either credential'
        cookie=$saved_cookie
    fi
    [[ -n $cookie ]] || cookie=$(openssl rand -hex 32)
    # Write the preserved credential before removing its old argument. A
    # restart between these writes continues using the identical credential.
    printf '%s\n' "$cookie" | write_file 0400 "$cookie_file"
    printf '%s\n' "${argument_lines[@]}" | write_file 0640 "$arguments"
    run chown "$owner" "$cookie_file" "$arguments"
    log 'CouchDB cluster cookie is preserved in a private file; activation requires a service restart'
}

install_couchdb_shell() {
    # Upstream remsh requires a -setcookie argument; provide a file-backed
    # equivalent without putting a credential in argv, environment or output.
    write_file 0755 /usr/local/sbin/kazoo-couchdb-shell <<'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ $EUID == 0 ]]; then
    exec runuser --user couchdb -- "$0" "$@"
fi
[[ $(id -un) == couchdb ]] || { printf 'Run this command as root or couchdb\n' >&2; exit 1; }
[[ -r /opt/couchdb/.erlang.cookie ]] || { printf 'CouchDB cookie file is unavailable\n' >&2; exit 1; }
node=$(awk '$1 == "-name" {print $2}' /opt/couchdb/etc/vm.args)
[[ $node =~ ^[a-zA-Z0-9_-]+@[a-zA-Z0-9_.-]+$ ]] || { printf 'Invalid CouchDB node name\n' >&2; exit 1; }
read -r erts_version _ </opt/couchdb/releases/start_erl.data
[[ $erts_version =~ ^[0-9.]+$ ]] || exit 1
exec "/opt/couchdb/erts-$erts_version/bin/erl" \
    -boot /opt/couchdb/releases/start_clean \
    -name "kazoo_couchdb_shell_$$@127.0.0.1" -hidden -remsh "$node" "$@"
SCRIPT
}

verify_couchdb_cookie() {
    local pid
    [[ $(stat -c '%U:%G:%a' /opt/couchdb/.erlang.cookie) == couchdb:couchdb:400 ]] || \
        die 'CouchDB cluster cookie must be owned by couchdb with mode 0400'
    [[ $(stat -c '%a' /opt/couchdb/etc/vm.args) == 640 ]] || die 'CouchDB vm.args must have mode 0640'
    pid=$(systemctl show couchdb.service -p MainPID --value)
    [[ $pid =~ ^[1-9][0-9]*$ && -r /proc/$pid/cmdline ]] || die 'CouchDB process is unavailable'
    if tr '\0' '\n' <"/proc/$pid/cmdline" | grep -Fx -- -setcookie >/dev/null; then
        die 'CouchDB still exposes its cluster cookie in process arguments; reinstall the couchdb role'
    fi
}

install_couchdb() {
    local probe_address
    log 'Installing Apache CouchDB for Kazoo'
    download https://couchdb.apache.org/repo/couchdb.repo "$KAZOO_CACHE_DIR/couchdb.repo"
    run install -D -m 0644 "$KAZOO_CACHE_DIR/couchdb.repo" /etc/yum.repos.d/couchdb.repo
    dnf_install "couchdb-${COUCHDB_VERSION}"
    configure_couchdb_cookie /opt/couchdb couchdb:couchdb
    install_couchdb_shell
    write_file 0640 /opt/couchdb/etc/local.d/20-kazoo.ini <<EOF
[admins]
${KAZOO_COUCHDB_USER} = ${KAZOO_COUCHDB_PASSWORD}

[chttpd]
bind_address = ${KAZOO_COUCHDB_BIND}
port = ${KAZOO_COUCHDB_PORT}

[couchdb]
single_node = true

[cluster]
q = 1
n = 1
r = 1
w = 1
EOF
    run chown couchdb:couchdb /opt/couchdb/etc/local.d/20-kazoo.ini
    service_enable_restart couchdb.service
    probe_address=$(local_probe_address "$KAZOO_COUCHDB_BIND")
    wait_for_port "$probe_address" "$KAZOO_COUCHDB_PORT" 120 || \
        die "CouchDB did not open port ${KAZOO_COUCHDB_PORT}"
    verify_couchdb
}

verify_couchdb() {
    local probe_address installed_version
    if [[ $DRY_RUN == true ]]; then log 'Would verify CouchDB'; return 0; fi
    assert_service couchdb.service
    verify_couchdb_cookie
    installed_version=$(rpm -q --qf '%{VERSION}-%{RELEASE}' couchdb 2>/dev/null) || \
        die 'The CouchDB RPM is not installed'
    [[ $installed_version == "$COUCHDB_VERSION" ]] || \
        die "Installed CouchDB version ${installed_version} does not match ${COUCHDB_VERSION}"
    probe_address=$(local_probe_address "$KAZOO_COUCHDB_BIND")
    couchdb_curl --fail --silent --show-error --connect-timeout 5 --max-time 30 \
        "http://${probe_address}:${KAZOO_COUCHDB_PORT}/_up" | jq -e '.status == "ok"' >/dev/null || \
        die 'CouchDB /_up health check failed'
    log "PASS CouchDB ${installed_version} authenticated /_up check"
}

rabbitmqctl_password() (
    # Never accept a password argument: caller xtrace runs before this helper.
    # RabbitMQ 3.13 accepts these passwords on stdin when the argument is absent.
    set +x
    local operation=${1:-}
    [[ $# == 1 ]] || return 2
    case $operation in add_user|change_password|authenticate_user) ;; *) return 2 ;; esac
    # The CLI trims stdin. Match the existing installer policy so input cannot
    # be truncated or changed by whitespace, newline or option interpretation.
    [[ ${KAZOO_RABBITMQ_USER:-} =~ ^[a-zA-Z0-9_.@-]+$ &&
       ${KAZOO_RABBITMQ_PASSWORD:-} =~ ^[a-zA-Z0-9_.@!%+=:-]+$ ]] || return 2
    # Do not inherit the clear text or its encoded AMQP-URI form in the child.
    export -n KAZOO_RABBITMQ_PASSWORD KAZOO_AMQP_URI
    {
        builtin printf '%s\n' "$KAZOO_RABBITMQ_PASSWORD" |
            # RabbitMQ 3.13's shell wrapper enables stdin only for exactly
            # operation + user. Even -q adds an argument and disables input.
            timeout --signal=TERM --kill-after=5 30 \
                rabbitmqctl "$operation" "$KAZOO_RABBITMQ_USER"
    } >/dev/null 2>&1
)

install_rabbitmq() {
    local rpm_file="${KAZOO_CACHE_DIR}/rabbitmq-server-${RABBITMQ_VERSION}.rpm"
    local rpm_url="https://github.com/rabbitmq/rabbitmq-server/releases/download/v${RABBITMQ_VERSION}/rabbitmq-server-${RABBITMQ_VERSION}-1.el8.noarch.rpm"
    log "Installing RabbitMQ ${RABBITMQ_VERSION} with Kazoo plugins"
    dnf_install "erlang-${ERLANG_VERSION}" logrotate socat
    download "$rpm_url" "$rpm_file"
    dnf_install "$rpm_file"
    run mkdir -p /etc/rabbitmq
    write_file 0644 /etc/rabbitmq/rabbitmq.conf <<EOF
listeners.tcp.default = ${KAZOO_RABBITMQ_BIND}:${KAZOO_AMQP_PORT}
management.tcp.port = 15672
management.tcp.ip = ${KAZOO_RABBITMQ_BIND}
distribution.listener.interface = ${KAZOO_RABBITMQ_BIND}
distribution.listener.port_range.min = 25672
distribution.listener.port_range.max = 25672
channel_max = 0
disk_free_limit.absolute = 512MB
vm_memory_high_watermark.relative = 0.6
loopback_users.guest = true
collect_statistics = coarse
collect_statistics_interval = 60000
EOF
    run rabbitmq-plugins enable --offline rabbitmq_management rabbitmq_consistent_hash_exchange
    # The root CLI creates this file with the caller's umask. With umask 077
    # a fresh install otherwise fails at boot with enabled_plugins/eacces.
    if [[ $DRY_RUN != true ]]; then
        [[ -f /etc/rabbitmq/enabled_plugins && ! -L /etc/rabbitmq/enabled_plugins ]] || \
            die 'RabbitMQ enabled_plugins must be a regular file'
        [[ $(stat -c '%h' /etc/rabbitmq/enabled_plugins) == 1 ]] || \
            die 'RabbitMQ enabled_plugins must not be hard-linked'
    fi
    run chown root:rabbitmq /etc/rabbitmq/enabled_plugins
    run chmod 0640 /etc/rabbitmq/enabled_plugins
    service_enable_restart rabbitmq-server.service
    if [[ $DRY_RUN != true ]]; then
        timeout 120 bash -c 'until rabbitmq-diagnostics -q ping; do sleep 2; done' || \
            die 'RabbitMQ diagnostics did not become healthy'
        if rabbitmqctl -q list_users | awk '{print $1}' | grep -Fx "$KAZOO_RABBITMQ_USER" >/dev/null; then
            rabbitmqctl_password change_password || die 'RabbitMQ password update failed'
        else
            rabbitmqctl_password add_user || die 'RabbitMQ user creation failed'
        fi
        if ! rabbitmqctl -q list_vhosts name | grep -Fx "$KAZOO_RABBITMQ_VHOST" >/dev/null; then
            rabbitmqctl add_vhost "$KAZOO_RABBITMQ_VHOST"
        fi
        rabbitmqctl set_permissions -p "$KAZOO_RABBITMQ_VHOST" \
            "$KAZOO_RABBITMQ_USER" '.*' '.*' '.*'
    fi
    verify_rabbitmq
}

verify_rabbitmq() {
    local installed_version installed_erlang listener permissions amqp_listeners
    if [[ $DRY_RUN == true ]]; then log 'Would verify RabbitMQ'; return 0; fi
    assert_service rabbitmq-server.service
    listener=$(ss -H -ltn 'sport = :25672')
    grep -F "${KAZOO_RABBITMQ_BIND}:25672" <<<"$listener" >/dev/null || \
        die "RabbitMQ distribution does not use its configured interface ${KAZOO_RABBITMQ_BIND}:25672"
    installed_version=$(rpm -q --qf '%{VERSION}' rabbitmq-server 2>/dev/null) || \
        die 'The RabbitMQ RPM is not installed'
    [[ $installed_version == "$RABBITMQ_VERSION" ]] || \
        die "Installed RabbitMQ version ${installed_version} does not match ${RABBITMQ_VERSION}"
    installed_erlang=$(rpm -q --qf '%{VERSION}' erlang 2>/dev/null) || \
        die 'The Erlang RPM required by RabbitMQ is not installed'
    [[ $installed_erlang == "$ERLANG_VERSION" ]] || \
        die "Installed Erlang version ${installed_erlang} does not match ${ERLANG_VERSION}"
    rabbitmq-diagnostics -q ping >/dev/null || die 'RabbitMQ ping failed'
    # The root RPM wrapper repairs cookie permissions even for `list`.
    # Inspect through the underlying CLI as its existing service user instead.
    runuser --user rabbitmq -- /usr/lib/rabbitmq/bin/rabbitmq-plugins list -e -m | \
        grep -Fx rabbitmq_consistent_hash_exchange >/dev/null || \
        die 'rabbitmq_consistent_hash_exchange is not enabled'
    rabbitmqctl_password authenticate_user || \
        die "RabbitMQ user ${KAZOO_RABBITMQ_USER} failed authentication"
    # Authentication alone does not prove access to the configured vhost.
    # The vhost-scoped command fails for an absent vhost; require exactly one
    # selected user row with the same permissions that installation grants.
    permissions=$(timeout --signal=TERM --kill-after=5 30 \
        rabbitmqctl -q list_permissions -p "$KAZOO_RABBITMQ_VHOST" --formatter json 2>/dev/null) || \
        die 'RabbitMQ configured-vhost permissions inspection failed'
    jq -e -s --arg user "$KAZOO_RABBITMQ_USER" '
        length == 1 and (.[0] | type == "array" and
            all(.[]; type == "object" and
                (.user | type) == "string" and (.configure | type) == "string" and
                (.write | type) == "string" and (.read | type) == "string") and
            ([.[] | select(.user == $user)] |
                length == 1 and .[0].configure == ".*" and
                .[0].write == ".*" and .[0].read == ".*"))
    ' <<<"$permissions" >/dev/null 2>&1 || \
        die 'RabbitMQ configured user lacks exact configure/write/read permissions on the configured vhost'
    # RabbitMQ 3.13 JSON listener rows bind interface, port and protocol in one
    # record. A wildcard or another interface must not satisfy a private bind.
    amqp_listeners=$(timeout --signal=TERM --kill-after=5 30 \
        rabbitmq-diagnostics -q listeners --formatter json 2>/dev/null) || \
        die 'RabbitMQ AMQP listener inspection failed'
    jq -e -s --arg interface "$KAZOO_RABBITMQ_BIND" --argjson port "$KAZOO_AMQP_PORT" '
        length == 1 and (.[0] | type == "object" and .result == "ok" and
            (.node | type) == "string" and (.node | length) > 0 and
            (.listeners | type) == "array" and
            (.listeners | all(.[]; type == "object" and (.interface | type) == "string" and
                    (.protocol | type) == "string" and (.port | type) == "number" and
                    .port == (.port | floor)) and
                any(.[]; .interface == $interface and .port == $port and .protocol == "amqp")))
    ' <<<"$amqp_listeners" >/dev/null 2>&1 || \
        die "RabbitMQ is not listening for AMQP on its configured interface ${KAZOO_RABBITMQ_BIND}:${KAZOO_AMQP_PORT}"
    log "PASS RabbitMQ ${installed_version} on Erlang ${installed_erlang}: ping, exact AMQP listener, authentication, configured-vhost permissions, and consistent-hash plugin checks"
}

install_haproxy() {
    local probe_address
    log 'Installing HAProxy with Kazoo CouchDB listeners'
    dnf_install haproxy
    write_file 0644 /etc/haproxy/haproxy.cfg <<EOF
global
    log         127.0.0.1 local2
    chroot      /var/lib/haproxy
    maxconn     4096
    user        haproxy
    group       haproxy
    daemon

defaults
    mode                    tcp
    log                     global
    option                  tcplog
    option                  dontlognull
    timeout connect         5s
    timeout client          60s
    timeout server          60s

frontend kazoo_couchdb
    bind ${KAZOO_HAPROXY_BIND}:15984
    default_backend couchdb_http

backend couchdb_http
    option tcp-check
    server couchdb1 ${KAZOO_COUCHDB_HOST}:${KAZOO_COUCHDB_PORT} check

frontend kazoo_couchdb_admin
    bind ${KAZOO_HAPROXY_BIND}:15986
    default_backend couchdb_admin

backend couchdb_admin
    option tcp-check
    server couchdb1_admin ${KAZOO_COUCHDB_HOST}:${KAZOO_COUCHDB_ADMIN_PORT} check
EOF
    if command -v getenforce >/dev/null && [[ $(getenforce) == Enforcing ]]; then
        run setsebool -P haproxy_connect_any 1
    fi
    run haproxy -c -f /etc/haproxy/haproxy.cfg
    service_enable_restart haproxy.service
    probe_address=$(local_probe_address "$KAZOO_HAPROXY_BIND")
    wait_for_port "$probe_address" 15984 30 || die 'HAProxy did not open port 15984'
    wait_for_port "$probe_address" 15986 30 || die 'HAProxy did not open port 15986'
    verify_haproxy
}

verify_haproxy() {
    local probe_address
    if [[ $DRY_RUN == true ]]; then log 'Would verify HAProxy'; return 0; fi
    assert_service haproxy.service
    haproxy -c -f /etc/haproxy/haproxy.cfg >/dev/null || die 'HAProxy configuration check failed'
    probe_address=$(local_probe_address "$KAZOO_HAPROXY_BIND")
    couchdb_curl --fail --silent --show-error --connect-timeout 5 --max-time 30 \
        "http://${probe_address}:15984/_up" | jq -e '.status == "ok"' >/dev/null || \
        die 'CouchDB through HAProxy failed'
    couchdb_curl --fail --silent --show-error --connect-timeout 5 --max-time 30 \
        "http://${probe_address}:15986/_up" | jq -e '.status == "ok"' >/dev/null || \
        die 'CouchDB admin listener through HAProxy failed'
    log 'PASS HAProxy configuration and both proxied CouchDB listeners'
}

install_htmldoc() {
    local source_dir="$KAZOO_BUILD_ROOT/htmldoc-${HTMLDOC_VERSION}"
    local marker=/usr/local/share/kazoo5-installer/htmldoc-version
    local expected_build="${HTMLDOC_VERSION}:${HTMLDOC_REF}"
    if [[ -x /usr/local/bin/htmldoc && -r $marker && $(<"$marker") == "$expected_build" ]]; then
        return 0
    fi
    sync_git https://github.com/michaelrsweet/htmldoc.git "$source_dir" "$HTMLDOC_REF"
    if [[ $DRY_RUN == true ]]; then
        log "Would build HTMLDOC ${HTMLDOC_VERSION}"
        return 0
    fi
    (
        cd "$source_dir"
        ./configure --prefix=/usr/local
        make -j"$KAZOO_MAKE_JOBS"
        make install
    )
    write_file 0644 "$marker" <<<"$expected_build"
}

install_kazoo_build_dependencies() {
    log 'Installing Kazoo build dependencies (including pinned Erlang from EPEL)'
    dnf_install \
        autoconf automake bzip2-devel cpio cups-devel expat-devel gcc gcc-c++ git \
        espeak-ng ghostscript glibc-devel ImageMagick java-17-openjdk-headless jq \
        libcurl-devel libjpeg-turbo-devel libpng-devel libreoffice-writer \
        libstdc++-devel libtiff-tools libtool \
        libuuid-devel libxslt-devel make ncurses-devel openssl-devel patch \
        patchutils python3 python3-pip readline-devel rsync sox systemd-devel \
        the_silver_searcher unzip wget zip zlib-devel "erlang-${ERLANG_VERSION}"
    install_htmldoc
    if [[ $DRY_RUN != true ]]; then
        local required_otp actual_otp otp_release otp_root
        required_otp=$(tr -d '[:space:]' <"${KAZOO_ROOT}/make/erlang_version")
        otp_root=$(erl -noshell -eval 'io:format("~s", [code:root_dir()]), halt().' 2>/dev/null)
        otp_release=$(erl -noshell -eval 'io:format("~s", [erlang:system_info(otp_release)]), halt().' 2>/dev/null)
        actual_otp=$(<"${otp_root}/releases/${otp_release}/OTP_VERSION")
        [[ $actual_otp == "$required_otp" || $actual_otp == "${required_otp}."* ]] || \
            die "Kazoo requires OTP ${required_otp}.x; installed OTP is ${actual_otp}"
    fi
}

ensure_bundled_acdc_source() {
    local acdc_dir="${KAZOO_ROOT}/applications/acdc"
    if [[ $DRY_RUN == true ]]; then
        log 'Would use ACDC source tracked in kz5 (no separate clone or integration patch)'
        return 0
    fi
    [[ ! -e $acdc_dir/.git && ! -L $acdc_dir/.git ]] || \
        die 'ACDC still has nested Git metadata; complete the kz5 source migration first'
    [[ -s $acdc_dir/Makefile && -s $acdc_dir/src/acdc_agent_fsm.erl && -s $acdc_dir/src/acdc.app.src ]] || \
        die 'Bundled ACDC source is missing; restore applications/acdc from this kz5 revision'
    git -C "$KAZOO_ROOT" ls-files --error-unmatch \
        applications/acdc/Makefile applications/acdc/src/acdc_agent_fsm.erl applications/acdc/src/acdc.app.src \
        >/dev/null 2>&1 || die 'ACDC source must be tracked by the kz5 repository'
}

ensure_kazoo_sources() {
    local core_dir="${KAZOO_ROOT}/core"
    local cookie_patch="${SCRIPT_DIR}/patches/kazoo-cookie-redaction.patch"
    [[ -f ${KAZOO_ROOT}/make/apps.mk ]] || die 'Kazoo source manifest is missing'
    ensure_bundled_acdc_source
    [[ $DRY_RUN == true || -d $core_dir/.git ]] || die 'Kazoo core source checkout is missing'
    if [[ $DRY_RUN != true ]]; then
        [[ $(git -C "$core_dir" rev-parse HEAD) == "$KAZOO_CORE_REF" ]] || \
            die 'Existing Kazoo core checkout differs from the tested pinned revision'
        [[ $(git -C "$KAZOO_ROOT/applications/crossbar" rev-parse HEAD) == "$KAZOO_CROSSBAR_REF" ]] || \
            die 'Existing Crossbar checkout differs from the tested pinned revision'
        [[ $(git -C "$KAZOO_ROOT/applications/blackhole" rev-parse HEAD) == "$KAZOO_BLACKHOLE_REF" ]] || \
            die 'Existing Blackhole checkout differs from the tested pinned revision'
        [[ $(git -C "$KAZOO_ROOT/applications/ecallmgr" rev-parse HEAD) == "$KAZOO_ECALLMGR_REF" ]] || \
            die 'Existing eCallMgr checkout differs from the tested pinned revision'
        [[ $(git -C "$KAZOO_ROOT/applications/stepswitch" rev-parse HEAD) == "$KAZOO_STEPSWITCH_REF" ]] || \
            die 'Existing Stepswitch checkout differs from the tested pinned revision'
        [[ $(git -C "$KAZOO_ROOT/applications/cdr" rev-parse HEAD) == "$KAZOO_CDR_REF" ]] || \
            die 'Existing CDR checkout differs from the tested pinned revision'
    fi
    [[ -f $cookie_patch ]] || die "Required Kazoo cookie-redaction patch is missing: ${cookie_patch}"
    if [[ $DRY_RUN == true ]]; then
        log 'Would apply the Kazoo/SUP cookie-redaction patch when needed'
    elif git -C "$core_dir" apply --check "$cookie_patch" 2>/dev/null; then
        git -C "$core_dir" apply "$cookie_patch"
        log 'Applied Kazoo/SUP cookie-redaction patch'
    elif git -C "$core_dir" apply --reverse --check "$cookie_patch" 2>/dev/null; then
        log 'Kazoo/SUP cookie-redaction patch is already applied'
    else
        die 'Kazoo core source does not match either side of the cookie-redaction patch'
    fi
    grep -Eq '^DEPS[[:space:]]*\?=[[:space:]]*acdc' "${KAZOO_ROOT}/make/apps.mk" || \
        die 'ACDC is not declared in make/apps.mk; use the integrated project revision'
    apply_required_source_patch "$core_dir" "$SCRIPT_DIR/patches/kazoo-jwt-malformed-input.patch"
    apply_required_source_patch "$core_dir" "$SCRIPT_DIR/patches/kazoo-identity-authoritative-read.patch"
    apply_required_source_patch "$core_dir" "$SCRIPT_DIR/patches/kazoo-entitlements-master-ancestry.patch"
    apply_required_source_patch "$core_dir" "$SCRIPT_DIR/patches/kazoo-media-reseller-language.patch"
    apply_required_source_patch "$core_dir" "$SCRIPT_DIR/patches/kazoo-config-startup-redaction.patch"
    apply_required_source_patch "$core_dir" "$SCRIPT_DIR/patches/kazoo-dataplan-log-redaction.patch"
    apply_required_source_patch "$core_dir" "$SCRIPT_DIR/patches/kazoo-couch-single-delete-result.patch"
    apply_required_source_patch "$core_dir" "$SCRIPT_DIR/patches/kazoo-stacktrace-argument-redaction.patch"
    apply_required_source_patch "$core_dir" "$SCRIPT_DIR/patches/kazoo-bindings-exception-diagnostics.patch"
    apply_required_source_patch "$core_dir" "$SCRIPT_DIR/patches/kazoo-amqp-originate-reconcile.patch"
    apply_required_source_patch "$core_dir" "$SCRIPT_DIR/patches/kazoo-amqp-basic-nack.patch"
    apply_required_source_patch "$core_dir" "$SCRIPT_DIR/patches/kazoo-amqp-connection-uri-redaction.patch"
    apply_required_source_patch "$core_dir" "$SCRIPT_DIR/patches/kazoo-amqp-supervised-registration.patch"
    apply_required_source_patch "$core_dir" "$SCRIPT_DIR/patches/kazoo-listener-secondary-queue-recovery.patch"
    apply_required_source_patch "$core_dir" "$SCRIPT_DIR/patches/kazoo-registration-collection.patch"
    apply_required_source_patch "$core_dir" "$SCRIPT_DIR/patches/kazoo-channel-monitoring.patch"
    apply_required_source_patch "$core_dir" "$SCRIPT_DIR/patches/kazoo-playback-file-timeout.patch"
    apply_required_source_patch "$core_dir" "$SCRIPT_DIR/patches/kazoo-sup-audit-redaction.patch"
    apply_required_source_patch "$core_dir" "$SCRIPT_DIR/patches/kazoo-sup-completion-local-build.patch"
    apply_required_source_patch "$core_dir" "$SCRIPT_DIR/patches/kazoo-sup-archive-order.patch"
    apply_required_source_patch "$core_dir" "$SCRIPT_DIR/patches/kazoo-call-forward-confirmation.patch"
    apply_required_source_patch "$core_dir" "$SCRIPT_DIR/patches/kazoo-media-scoped-migration.patch"
    # One patch per overlapping source stack makes reinstallation idempotent:
    # later callback edits must not invalidate reverse checks of earlier OTP
    # and announcement hunks. Feature patches remain review/test provenance.
    # ACDC is already part of kz5; its historical patches are not applied.
    apply_kazoo_integration_patch crossbar
    apply_required_source_patch "$KAZOO_ROOT/applications/crossbar" \
        "$SCRIPT_DIR/patches/crossbar-call-forward-confirmation.patch"
    apply_required_source_patch "$KAZOO_ROOT/applications/crossbar" \
        "$SCRIPT_DIR/patches/crossbar-soft-delete-revision.patch"
    apply_required_source_patch "$KAZOO_ROOT/applications/crossbar" \
        "$SCRIPT_DIR/patches/crossbar-scope-management-guard.patch"
    apply_required_source_patch "$KAZOO_ROOT/applications/crossbar" \
        "$SCRIPT_DIR/patches/crossbar-optional-content-defaults.patch"
    if grep -Fq "case kapps_config:get_category(?CONFIG_CAT, 'false') of" \
            "$KAZOO_ROOT/applications/crossbar/src/crossbar_maintenance.erl"; then
        apply_required_source_patch "$KAZOO_ROOT/applications/crossbar" \
            "$SCRIPT_DIR/patches/crossbar-module-autoload-public-read.patch"
    fi
    apply_required_source_patch "$KAZOO_ROOT/applications/crossbar" \
        "$SCRIPT_DIR/patches/crossbar-module-autoload-scope.patch"
    apply_kazoo_integration_patch blackhole
    apply_required_source_patch "$KAZOO_ROOT/applications/blackhole" \
        "$SCRIPT_DIR/patches/blackhole-command-auth.patch"
    apply_required_source_patch "$KAZOO_ROOT/applications/blackhole" \
        "$SCRIPT_DIR/patches/blackhole-outbound-guard.patch"
    apply_required_source_patch "$KAZOO_ROOT/applications/stepswitch" \
        "$SCRIPT_DIR/patches/stepswitch-callback-origination.patch"
    apply_kazoo_integration_patch ecallmgr
    apply_required_source_patch "$KAZOO_ROOT/applications/ecallmgr" \
        "$SCRIPT_DIR/patches/ecallmgr-bridge-peer-identity.patch"
    apply_required_source_patch "$KAZOO_ROOT/applications/ecallmgr" \
        "$SCRIPT_DIR/patches/ecallmgr-location-cache-recovery.patch"
    apply_required_source_patch "$KAZOO_ROOT/applications/cdr" \
        "$SCRIPT_DIR/patches/cdr-report-timestamp-fallback.patch"
}

apply_kazoo_integration_patch() (
    set -euo pipefail
    [[ $# == 1 || ( $# == 2 && $1 == mod_kazoo ) ]] ||
        die 'Expected a Kazoo integration family, with an explicit source only for mod_kazoo'
    [[ $1 != mod_kazoo || $# == 2 ]] || die 'mod_kazoo requires its explicit source directory'
    # Scope every Git command to this function's explicit working directory.
    # Inherited repository/worktree/config/trace overrides must not redirect
    # the private preflight or the eventual source write. This is a subshell:
    # the caller's environment is unchanged.
    local transition_git_env
    for transition_git_env in "${!GIT_@}"; do
        unset -v "$transition_git_env" || die 'Cannot isolate Git environment'
    done
    local transition_app=$1 transition_new transition_old transition_delta
    local transition_source transition_relative transition_path
    local transition_state transition_stage transition_intercept='' transition_cleanup=''
    local transition_pre_queue='' transition_queue_live=''
    local transition_stream_old='' transition_stream_delta=''
    local transition_pre_catalog='' transition_catalog=''
    local transition_format='' transition_unformat=false
    local transition_apply=()
    local transition_files=() transition_old_files=() transition_delta_files=()
    local transition_created_files=()
    case $transition_app in
        blackhole)
            transition_new=blackhole-kazoo5-integration.patch
            transition_old=blackhole-token-redaction.patch
            transition_delta=blackhole-redaction-to-integration.patch
            transition_files=(src/blackhole_bindings.erl src/blackhole_socket_handler.erl src/modules/bh_token_auth.erl
                              src/bh_context.erl src/bh_events.erl src/blackhole.hrl src/modules/bh_queue_live.erl)
            transition_old_files=(src/blackhole_socket_handler.erl src/modules/bh_token_auth.erl)
            transition_delta_files=(src/blackhole_bindings.erl src/blackhole_socket_handler.erl)
            transition_cleanup=blackhole-binding-cleanup.patch
            transition_pre_queue=blackhole-pre-queue-live-integration.patch
            transition_queue_live=blackhole-queue-live.patch
            transition_stream_old=blackhole-before-stream-guard.patch
            transition_stream_delta=blackhole-stream-guard-transition.patch
            transition_created_files=(src/modules/bh_queue_live.erl)
            ;;
        crossbar)
            transition_new=crossbar-kazoo5-integration.patch
            transition_old=crossbar-kazoo5-before-frame.patch
            transition_delta=crossbar-blackhole-frame-schema.patch
            transition_pre_catalog=crossbar-kazoo5-before-empty-icon.patch
            transition_catalog=crossbar-empty-icon.patch
            transition_format=crossbar-build-json-format.patch
            transition_files=(priv/couchdb/schemas/queue_update.json priv/couchdb/schemas/queues.json
                src/api_util.erl src/crossbar_auth.erl src/modules/cb_channels.erl src/modules/cb_devices.erl
                priv/couchdb/schemas/channel_monitoring.json src/cb_channel_monitor.erl
                src/kazoo_monster_catalog.erl src/modules/cb_members.erl
                priv/couchdb/schemas/system_config.blackhole.json)
            transition_old_files=("${transition_files[@]:0:10}")
            transition_delta_files=(priv/couchdb/schemas/system_config.blackhole.json)
            transition_created_files=(priv/couchdb/schemas/channel_monitoring.json src/cb_channel_monitor.erl
                src/kazoo_monster_catalog.erl src/modules/cb_members.erl)
            ;;
        ecallmgr)
            transition_new=ecallmgr-kazoo5-integration.patch
            transition_old=ecallmgr-kazoo5-before-atomic.patch
            transition_delta=ecallmgr-atomic-answer-runtime.patch
            transition_files=(src/call_cmd/ecallmgr_call_command.erl src/call_cmd/ecallmgr_fs_bridge.erl
                src/ecallmgr_fs_channels.erl src/ecallmgr_fs_resource.erl src/ecallmgr_fs_xml.erl
                src/ecallmgr_originate.erl src/ecallmgr_util.erl src/event_stream/ecallmgr_fs_event_stream.erl
                src/mod_kazoo.erl src/node/ecallmgr_fs_nodes.erl src/node/ecallmgr_fs_pinger.erl
                src/ecallmgr_call_monitor.erl)
            transition_old_files=("${transition_files[@]}")
            transition_delta_files=(src/ecallmgr_originate.erl)
            transition_created_files=(src/ecallmgr_call_monitor.erl)
            ;;
        mod_kazoo)
            transition_new=mod-kazoo-kz5-integration.patch
            transition_old=mod-kazoo-before-version.patch
            transition_delta=mod-kazoo-version-namespace.patch
            transition_source=$2
            transition_intercept=mod-kazoo-atomic-intercept.patch
            transition_files=(kazoo_api.c kazoo_commands.c kazoo_config.c kazoo_dptools.c
                kazoo_ei.h kazoo_ei_config.c kazoo_ei_utils.c kazoo_event_stream.c
                kazoo_fetch_agent.c kazoo_fields.h kazoo_message.c kazoo_node.c mod_kazoo.c mod_kazoo.h
                kazoo_intercept.h)
            transition_old_files=("${transition_files[@]:0:14}")
            transition_delta_files=(kazoo_api.c kazoo_ei.h kazoo_fetch_agent.c kazoo_node.c)
            transition_created_files=(kazoo_intercept.h)
            ;;
        *) die 'Unknown Kazoo integration family' ;;
    esac
    transition_safe_file() {
        local transition_file=$1
        [[ -f $transition_file && ! -L $transition_file &&
           $(realpath -e -- "$transition_file") == "$transition_file" &&
           $(stat -c %h -- "$transition_file") == 1 ]] ||
            die 'Required integration input is missing, linked or unsafe'
    }
    transition_new="$SCRIPT_DIR/patches/$transition_new"
    transition_old="$SCRIPT_DIR/patches/$transition_old"
    transition_delta="$SCRIPT_DIR/patches/$transition_delta"
    [[ ! $transition_intercept ]] || transition_intercept="$SCRIPT_DIR/patches/$transition_intercept"
    [[ ! $transition_cleanup ]] || transition_cleanup="$SCRIPT_DIR/patches/$transition_cleanup"
    [[ ! $transition_pre_queue ]] || transition_pre_queue="$SCRIPT_DIR/patches/$transition_pre_queue"
    [[ ! $transition_queue_live ]] || transition_queue_live="$SCRIPT_DIR/patches/$transition_queue_live"
    [[ ! $transition_stream_old ]] || transition_stream_old="$SCRIPT_DIR/patches/$transition_stream_old"
    [[ ! $transition_stream_delta ]] || transition_stream_delta="$SCRIPT_DIR/patches/$transition_stream_delta"
    [[ ! $transition_pre_catalog ]] || transition_pre_catalog="$SCRIPT_DIR/patches/$transition_pre_catalog"
    [[ ! $transition_catalog ]] || transition_catalog="$SCRIPT_DIR/patches/$transition_catalog"
    [[ ! $transition_format ]] || transition_format="$SCRIPT_DIR/patches/$transition_format"
    # The reviewed formatter delta contains one COMPLETE old/new hunk per
    # schema. Match those entire bytes, not JSON equality or Git hunk presence:
    # duplicate keys, extra properties and unknown whitespace remain edits.
    # This reads only; normalization is rehearsed later in the private copy.
    transition_exact_json_bytes() {
        /usr/bin/python3 -I - "$transition_format" "$1" "$2" <<'PY'
import pathlib, re, sys
try:
    patch, directory, side = sys.argv[1:]
    assert side in ('raw', 'formatted')
    def bounded(file):
        with open(file, 'rb') as stream:
            data = stream.read(4 * 1024 * 1024 + 1)
        assert 0 < len(data) <= 4 * 1024 * 1024
        return data
    sections = bounded(patch).split(b'diff --git ')
    assert sections[0] == b'' and len(sections) == 4
    wanted = {'priv/couchdb/schemas/' + name + '.json'
              for name in ('channel_monitoring', 'queues', 'queue_update')}
    for section in sections[1:]:
        lines = section.splitlines(keepends=True)
        header = re.fullmatch(rb'a/([^\n ]+) b/([^\n ]+)\n', lines[0])
        assert header and header[1] == header[2]
        name = header[1].decode('ascii')
        assert name in wanted
        wanted.remove(name)
        assert re.fullmatch(rb'index [0-9a-f]+\.\.[0-9a-f]+ 100644\n', lines[1])
        assert lines[2] == b'--- a/' + header[1] + b'\n'
        assert lines[3] == b'+++ b/' + header[1] + b'\n'
        hunk = re.fullmatch(rb'@@ -1,([0-9]+) \+1,([0-9]+) @@\n', lines[4])
        assert hunk
        old, new = [], []
        for line in lines[5:]:
            assert line[:1] in (b' ', b'-', b'+') and line.endswith(b'\n')
            if line[:1] != b'+': old.append(line[1:])
            if line[:1] != b'-': new.append(line[1:])
        assert len(old) == int(hunk[1]) and len(new) == int(hunk[2])
        expected = b''.join(old if side == 'raw' else new)
        assert bounded(pathlib.Path(directory) / name) == expected
    assert not wanted
except Exception:
    sys.exit(1)
PY
    }
    if [[ $DRY_RUN == true ]]; then
        transition_safe_file "$transition_new"
        transition_safe_file "$transition_old"
        transition_safe_file "$transition_delta"
        [[ ! $transition_intercept ]] || transition_safe_file "$transition_intercept"
        [[ ! $transition_cleanup ]] || transition_safe_file "$transition_cleanup"
        [[ ! $transition_pre_queue ]] || transition_safe_file "$transition_pre_queue"
        [[ ! $transition_queue_live ]] || transition_safe_file "$transition_queue_live"
        [[ ! $transition_stream_old ]] || transition_safe_file "$transition_stream_old"
        [[ ! $transition_stream_delta ]] || transition_safe_file "$transition_stream_delta"
        [[ ! $transition_pre_catalog ]] || transition_safe_file "$transition_pre_catalog"
        [[ ! $transition_catalog ]] || transition_safe_file "$transition_catalog"
        [[ ! $transition_format ]] || transition_safe_file "$transition_format"
        log "Would ensure $transition_app integration with private preflight; source state and preflight are unverified"
        return 0
    fi
    # Reject traversal and symlinked ancestors, including above the source root.
    if [[ $transition_app != mod_kazoo ]]; then
        [[ $KAZOO_ROOT == /* && $KAZOO_ROOT != / &&
           $(realpath -e -- "$KAZOO_ROOT") == "$KAZOO_ROOT" ]] ||
            die 'Kazoo source root must be an existing canonical absolute directory'
        transition_source="$KAZOO_ROOT/applications/$transition_app"
    fi
    [[ $transition_source == /* && $transition_source != / &&
       -d $transition_source && ! -L $transition_source &&
       $(realpath -e -- "$transition_source") == "$transition_source" ]] ||
        die 'Unsafe Kazoo integration source directory'
    # Match the complete, literal file inventory of each reviewed patch.
    # Quoted paths, renames, binary numstat and unexpected/deleted paths fail.
    transition_check_inventory() {
        local transition_inventory_patch=$1
        shift
        local -A transition_inventory=()
        local transition_inventory_file transition_inventory_rows
        local transition_inventory_add transition_inventory_remove transition_inventory_path
        for transition_inventory_file in "$@"; do
            transition_inventory["$transition_inventory_file"]=1
        done
        transition_safe_file "$transition_inventory_patch"
        transition_inventory_rows=$(git -C "$transition_source" apply --numstat "$transition_inventory_patch") ||
            die 'Cannot parse integration patch inventory'
        while IFS=$'\t' read -r transition_inventory_add transition_inventory_remove transition_inventory_path; do
            [[ $transition_inventory_add =~ ^[0-9]+$ && $transition_inventory_remove =~ ^[0-9]+$ &&
               ( $transition_inventory_path =~ ^(src|priv)/[a-zA-Z0-9_./-]+$ ||
                 ( $transition_app == mod_kazoo && $transition_inventory_path =~ ^[a-z_]+\.[ch]$ ) ) &&
               ${transition_inventory[$transition_inventory_path]:-} == 1 ]] ||
                die 'Integration patch has an unexpected source path'
            unset 'transition_inventory[$transition_inventory_path]'
        done <<<"$transition_inventory_rows"
        [[ ${#transition_inventory[@]} == 0 ]] ||
            die 'Integration patch omits a required source path'
        ! /usr/bin/grep -Eq '^(deleted file mode|rename from|rename to|copy from|copy to|GIT binary patch)' "$transition_inventory_patch" ||
            die 'Unsupported integration patch operation'
    }
    transition_check_inventory "$transition_new" "${transition_files[@]}"
    transition_check_inventory "$transition_old" "${transition_old_files[@]}"
    transition_check_inventory "$transition_delta" "${transition_delta_files[@]}"
    if [[ $transition_cleanup ]]; then
        transition_check_inventory "$transition_cleanup" src/bh_context.erl src/bh_events.erl
        transition_check_inventory "$transition_pre_queue" "${transition_files[@]:0:5}"
        transition_check_inventory "$transition_queue_live" src/bh_context.erl src/blackhole_socket_handler.erl \
            src/blackhole.hrl src/modules/bh_queue_live.erl
        transition_check_inventory "$transition_stream_old" "${transition_files[@]}"
        transition_check_inventory "$transition_stream_delta" src/blackhole_socket_handler.erl
    fi
    if [[ $transition_intercept ]]; then
        transition_check_inventory "$transition_intercept" kazoo_intercept.h kazoo_dptools.c mod_kazoo.h mod_kazoo.c
    fi
    if [[ $transition_catalog ]]; then
        transition_check_inventory "$transition_pre_catalog" "${transition_files[@]}"
        transition_check_inventory "$transition_catalog" src/kazoo_monster_catalog.erl
        transition_check_inventory "$transition_format" priv/couchdb/schemas/channel_monitoring.json \
            priv/couchdb/schemas/queues.json priv/couchdb/schemas/queue_update.json
    fi
    # Only explicitly added files may be absent before their reviewed transition.
    transition_check_sources() {
        local transition_check_file transition_check_path transition_check_created transition_may_be_absent
        for transition_check_file in "${transition_files[@]}"; do
            transition_check_path="$transition_source/$transition_check_file"
            if [[ -e $transition_check_path || -L $transition_check_path ]]; then
                transition_safe_file "$transition_check_path"
            else
                transition_may_be_absent=false
                for transition_check_created in "${transition_created_files[@]}"; do
                    [[ $transition_check_file != "$transition_check_created" ]] || transition_may_be_absent=true
                done
                [[ $transition_may_be_absent == true &&
                   $(realpath -e -- "$(dirname -- "$transition_check_path")") == "$(dirname -- "$transition_check_path")" ]] ||
                    die 'Required integration source is missing or has unsafe ancestors'
            fi
        done
    }
    transition_check_sources
    if git -C "$transition_source" apply --check "$transition_new" 2>/dev/null; then
        transition_state=clean
        transition_apply=("$transition_new")
    elif git -C "$transition_source" apply --reverse --check "$transition_new" 2>/dev/null; then
        [[ ! $transition_format ]] || transition_exact_json_bytes "$transition_source" raw ||
            die 'Current Crossbar schemas are not the exact reviewed raw bytes'
        log "Required $transition_app integration is already current"
        return 0
    elif [[ $transition_app == blackhole ]]; then
        # Queue-live overlaps the frame and cleanup files. Classify and apply
        # older steps in private copies, proving the complete pre-queue baseline
        # before trying the queue-live delta. Never infer independent deltas here.
        transition_state=previous
    elif [[ $transition_app == crossbar ]]; then
        # Prove either complete historical baseline privately before applying
        # the empty-icon delta; an unknown/partial catalog is never overwritten.
        transition_state=previous
    elif [[ $transition_app == mod_kazoo ]]; then
        # Namespace and atomic interception touch disjoint file sets. Existing
        # installations can have neither, either, or both reviewed additions.
        # Select only missing deltas; the private full-aggregate reverse check
        # below must still prove the complete result before any target write.
        for transition_relative in "${transition_old_files[@]}"; do
            transition_safe_file "$transition_source/$transition_relative"
        done
        for transition_path in "$transition_delta" "$transition_intercept"; do
            if git -C "$transition_source" apply --check "$transition_path" 2>/dev/null; then
                transition_apply+=("$transition_path")
            elif ! git -C "$transition_source" apply --reverse --check "$transition_path" 2>/dev/null; then
                die 'Source is neither the clean, current nor explicitly supported previous integration'
            fi
        done
        [[ ${#transition_apply[@]} -gt 0 ]] ||
            die 'Source is neither the clean, current nor explicitly supported previous integration'
        transition_state=previous
    elif git -C "$transition_source" apply --reverse --check "$transition_old" 2>/dev/null &&
         git -C "$transition_source" apply --check "$transition_delta" 2>/dev/null; then
        transition_state=previous
        transition_apply=("$transition_delta")
        for transition_relative in "${transition_files[@]}"; do
            transition_safe_file "$transition_source/$transition_relative"
        done
    else
        die 'Source is neither the clean, current nor explicitly supported previous integration'
    fi
    transition_stage=$(mktemp -d /tmp/kazoo-integration-preflight.XXXXXX) ||
        die 'Cannot allocate integration preflight directory'
    [[ $transition_stage =~ ^/tmp/kazoo-integration-preflight\.[a-zA-Z0-9]{6}$ &&
       -d $transition_stage && ! -L $transition_stage &&
       $(realpath -e -- "$transition_stage") == "$transition_stage" ]] ||
        die 'Unsafe integration preflight directory'
    chmod 0700 "$transition_stage" || die 'Cannot protect integration preflight directory'
    # Keep the protected original/desired copies for failure recovery and audit.
    trap 'log "Retained integration preflight: $transition_stage"' EXIT
    mkdir -m 0700 "$transition_stage/original" "$transition_stage/desired" ||
        die 'Cannot create integration preflight copies'
    local -A transition_metadata=()
    # Owner/group/link metadata is a concurrent-change guard, not an ownership
    # preservation promise: source writes retain normal git-apply ownership.
    for transition_relative in "${transition_files[@]}"; do
        transition_path="$transition_source/$transition_relative"
        mkdir -p -- "$transition_stage/original/$(dirname -- "$transition_relative")" \
            "$transition_stage/desired/$(dirname -- "$transition_relative")" ||
            die 'Cannot create integration preflight source directories'
        if [[ -f $transition_path ]]; then
            transition_metadata["$transition_relative"]=$(stat -c '%a:%u:%g:%h' -- "$transition_path") ||
                die 'Cannot read integration source metadata'
            cp --preserve=mode,timestamps -- "$transition_path" "$transition_stage/original/$transition_relative" ||
                die 'Cannot retain original integration source'
            cp --preserve=mode,timestamps -- "$transition_path" "$transition_stage/desired/$transition_relative" ||
                die 'Cannot stage desired integration source'
        else
            transition_metadata["$transition_relative"]=absent
        fi
    done
    sha256sum "$transition_new" "$transition_old" "$transition_delta" >"$transition_stage/patch-pins.sha256" ||
        die 'Cannot retain integration patch hashes'
    if [[ $transition_cleanup ]]; then
        sha256sum "$transition_cleanup" "$transition_pre_queue" "$transition_queue_live" \
            "$transition_stream_old" "$transition_stream_delta" \
            >>"$transition_stage/patch-pins.sha256" ||
            die 'Cannot retain Blackhole transition patch hashes'
    fi
    if [[ $transition_intercept ]]; then
        sha256sum "$transition_intercept" >>"$transition_stage/patch-pins.sha256" ||
            die 'Cannot retain intercept patch hash'
    fi
    if [[ $transition_catalog ]]; then
        sha256sum "$transition_pre_catalog" "$transition_catalog" "$transition_format" >>"$transition_stage/patch-pins.sha256" ||
            die 'Cannot retain catalog transition patch hashes'
    fi
    if [[ $transition_app == blackhole && $transition_state == previous ]]; then
      if ! git -C "$transition_stage/desired" apply --reverse --check "$transition_stream_old" 2>/dev/null; then
        if ! git -C "$transition_stage/desired" apply --reverse --check "$transition_pre_queue" 2>/dev/null; then
            for transition_path in "$transition_delta" "$transition_cleanup"; do
                if git -C "$transition_stage/desired" apply --check "$transition_path" 2>/dev/null; then
                    git -C "$transition_stage/desired" apply "$transition_path" ||
                        die 'Cannot normalize previous Blackhole source privately'
                    transition_apply+=("$transition_path")
                elif ! git -C "$transition_stage/desired" apply --reverse --check "$transition_path" 2>/dev/null; then
                    die 'Source is neither the clean, current nor explicitly supported previous integration'
                fi
            done
        fi
        git -C "$transition_stage/desired" apply --reverse --check "$transition_pre_queue" ||
            die 'Previous Blackhole source is not the complete pre-queue integration'
        git -C "$transition_stage/desired" apply --check "$transition_queue_live" ||
            die 'Queue-live transition cannot apply to the previous Blackhole integration'
        git -C "$transition_stage/desired" apply "$transition_queue_live" ||
            die 'Cannot apply queue-live transition to private source copies'
        transition_apply+=("$transition_queue_live")
      fi
        git -C "$transition_stage/desired" apply --reverse --check "$transition_stream_old" ||
            die 'Previous Blackhole source is not the complete pre-stream integration'
        git -C "$transition_stage/desired" apply --check "$transition_stream_delta" ||
            die 'Stream guard transition cannot apply to the previous Blackhole integration'
        git -C "$transition_stage/desired" apply "$transition_stream_delta" ||
            die 'Cannot apply stream guard transition to private source copies'
        transition_apply+=("$transition_stream_delta")
    elif [[ $transition_app == crossbar && $transition_state == previous ]]; then
        if ! transition_exact_json_bytes "$transition_stage/desired" raw; then
            transition_exact_json_bytes "$transition_stage/desired" formatted ||
                die 'Crossbar schemas are neither exact reviewed raw nor build-formatted bytes'
            git -C "$transition_stage/desired" apply --reverse --check "$transition_format" ||
                die 'Reviewed Crossbar formatter transition cannot reverse privately'
            git -C "$transition_stage/desired" apply --reverse "$transition_format" ||
                die 'Cannot normalize reviewed Crossbar build formatting privately'
            transition_unformat=true
        fi
        if git -C "$transition_stage/desired" apply --reverse --check "$transition_new" 2>/dev/null; then
            : # Current code with only the exact known build formatting drift.
        else
            if ! git -C "$transition_stage/desired" apply --reverse --check "$transition_pre_catalog" 2>/dev/null; then
                git -C "$transition_stage/desired" apply --reverse --check "$transition_old" ||
                    die 'Previous Crossbar source is not a complete reviewed integration'
                git -C "$transition_stage/desired" apply --check "$transition_delta" ||
                    die 'Previous Crossbar frame transition does not apply'
                git -C "$transition_stage/desired" apply "$transition_delta" ||
                    die 'Cannot normalize previous Crossbar source privately'
                transition_apply+=("$transition_delta")
            fi
            git -C "$transition_stage/desired" apply --reverse --check "$transition_pre_catalog" ||
                die 'Previous Crossbar source is not the complete pre-icon integration'
            git -C "$transition_stage/desired" apply --check "$transition_catalog" ||
                die 'Catalog empty-icon transition does not apply'
            git -C "$transition_stage/desired" apply "$transition_catalog" ||
                die 'Cannot apply catalog empty-icon transition privately'
            transition_apply+=("$transition_catalog")
        fi
    else
        git -C "$transition_stage/desired" apply --check "${transition_apply[@]}" ||
            die 'Integration patch cannot apply to private source copies'
        git -C "$transition_stage/desired" apply "${transition_apply[@]}" ||
            die 'Cannot apply integration patch to private source copies'
    fi
    git -C "$transition_stage/desired" apply --reverse --check "$transition_new" ||
        die 'Transition does not produce the complete current integration'
    [[ ! $transition_format ]] || transition_exact_json_bytes "$transition_stage/desired" raw ||
        die 'Desired Crossbar schemas are not the exact reviewed raw bytes'
    # All validation above is private. Recheck every real target and patch
    # immediately before git apply (never --reject/--index). This validates all
    # hunks, but is not a crash-atomic transaction across multiple source files.
    transition_check_sources
    sha256sum --check --status "$transition_stage/patch-pins.sha256" ||
        die 'Integration patch inputs changed during preflight'
    for transition_relative in "${transition_files[@]}"; do
        transition_path="$transition_source/$transition_relative"
        if [[ ${transition_metadata[$transition_relative]} == absent ]]; then
            [[ ! -e $transition_path && ! -L $transition_path ]] ||
                die 'Integration source appeared during preflight'
        else
            [[ $(stat -c '%a:%u:%g:%h' -- "$transition_path") == "${transition_metadata[$transition_relative]}" ]] &&
                cmp -s -- "$transition_stage/original/$transition_relative" "$transition_path" ||
                die 'Integration source changed during preflight'
        fi
    done
    if [[ $transition_app == crossbar && $transition_state == previous ]]; then
        if [[ $transition_unformat == true ]]; then
            git -C "$transition_source" apply --reverse --check "$transition_format" ||
                die 'Reviewed Crossbar formatter transition no longer reverses on target'
            git -C "$transition_source" apply --reverse "$transition_format" ||
                die 'Cannot restore reviewed raw Crossbar schema representation'
        fi
        for transition_path in "${transition_apply[@]}"; do
            git -C "$transition_source" apply --check "$transition_path" ||
                die 'Crossbar transition no longer applies to target sources'
            git -C "$transition_source" apply "$transition_path" ||
                die 'Cannot apply ordered Crossbar transition to target sources'
        done
    elif [[ $transition_app == blackhole && $transition_state == previous ]]; then
        # These overlapping steps were already rehearsed in order against the
        # exact original bytes above. Keep that order; this is not crash-atomic.
        for transition_path in "${transition_apply[@]}"; do
            git -C "$transition_source" apply --check "$transition_path" ||
                die 'Blackhole transition no longer applies to target sources'
            git -C "$transition_source" apply "$transition_path" ||
                die 'Cannot apply ordered Blackhole transition to target sources'
        done
    else
        git -C "$transition_source" apply --check "${transition_apply[@]}" ||
            die 'Integration patch no longer applies to target sources'
        git -C "$transition_source" apply "${transition_apply[@]}" ||
            die 'Cannot apply integration patch to target sources'
    fi
    git -C "$transition_source" apply --reverse --check "$transition_new" ||
        die 'Applied integration failed its final current-source check'
    for transition_relative in "${transition_files[@]}"; do
        cmp -s -- "$transition_stage/desired/$transition_relative" "$transition_source/$transition_relative" ||
            die 'Applied integration differs from its private preflight result'
        [[ $(stat -c %a -- "$transition_stage/desired/$transition_relative") == $(stat -c %a -- "$transition_source/$transition_relative") ]] ||
            die 'Applied integration mode differs from its private preflight result'
    done
    log "Applied $transition_app integration from $transition_state after private preflight"
)

apply_required_source_patch() {
    local source_dir=$1 patch_file=$2
    [[ -f $patch_file ]] || die "Required source patch is missing: ${patch_file}"
    if [[ $DRY_RUN == true ]]; then
        log "Would apply required source patch $(basename "$patch_file")"
    elif git -C "$source_dir" apply --check "$patch_file" 2>/dev/null; then
        git -C "$source_dir" apply "$patch_file"
        log "Applied required source patch $(basename "$patch_file")"
    elif git -C "$source_dir" apply --reverse --check "$patch_file" 2>/dev/null; then
        log "Required source patch is already applied: $(basename "$patch_file")"
    else
        die "Source does not match required patch: ${patch_file}"
    fi
}

configure_kazoo() {
    local fqdn
    fqdn=$KAZOO_HOSTNAME
    if ! getent group kazoo >/dev/null; then
        run groupadd --system kazoo
    fi
    sync_git https://github.com/2600hz/kazoo-configs-core.git \
        "$KAZOO_BUILD_ROOT/kazoo-configs-core" "$KAZOO_CORE_CONFIG_REF"
    # A preceding data-only install may create this shared parent under umask
    # 077. Services need traversal; secret files retain their separate 0600/
    # 0640 permissions. Never recursively relax permissions on its contents.
    validate_config_directory "$KAZOO_CONFIG_DIR"
    validate_config_directory "$KAZOO_CONFIG_DIR/core"
    run install -d -o root -g root -m 0755 "$KAZOO_CONFIG_DIR" "$KAZOO_CONFIG_DIR/core"
    run mkdir -p /var/log/kazoo /var/lib/kazoo "$KAZOO_ROOT/var/lib/ra"
    write_file 0640 "$KAZOO_CONFIG_DIR/core/config.ini" <<EOF
[amqp]
uri = ${KAZOO_AMQP_URI}

[data]
config = couchdb3

[couchdb3]
ip = ${KAZOO_COUCHDB_HOST}
port = ${KAZOO_COUCHDB_PORT}
username = ${KAZOO_COUCHDB_USER}
password = ${KAZOO_COUCHDB_PASSWORD}

[zone]
name = local
amqp_uri = ${KAZOO_AMQP_URI}

[kazoo_apps]
cookie = ${KAZOO_COOKIE}
host = ${fqdn}

[ecallmgr]
cookie = ${KAZOO_COOKIE}
host = ${fqdn}

[log]
syslog = none
console = info
file = error
EOF
    run chown root:kazoo "$KAZOO_CONFIG_DIR/core/config.ini"
    if [[ ! -e /opt/kazoo ]]; then
        run ln -s "$KAZOO_ROOT" /opt/kazoo
    elif [[ $(readlink -f /opt/kazoo) != $(readlink -f "$KAZOO_ROOT") ]]; then
        warn "/opt/kazoo already exists and does not point at ${KAZOO_ROOT}; rel/sys.config uses /opt/kazoo for RA data"
    fi
    if ! getent hosts "$fqdn" >/dev/null; then
        warn "Hostname ${fqdn} does not resolve; distributed Erlang may not start"
    fi
}

kazoo_test_compiled_beams() {
    KAZOO_BEAM_SCAN_ROOT=$KAZOO_ROOT erl +S 1:1 +A 1 -noshell -eval '
Root = os:getenv("KAZOO_BEAM_SCAN_ROOT"),
Files = filelib:wildcard(filename:join([Root, "core", "*", "ebin", "*.beam"]))
        ++ filelib:wildcard(filename:join([Root, "applications", "*", "ebin", "*.beam"]))
        ++ filelib:wildcard(filename:join([Root, "deps", "*", "ebin", "*.beam"])),
IsTestCompiled = fun(File) ->
    case beam_lib:chunks(File, [compile_info]) of
        {ok, {_, [{compile_info, Info}]}} ->
            lists:any(fun({d, '\''TEST'\''}) -> true;
                         ({d, '\''TEST'\'', _}) -> true;
                         (_) -> false
                      end,
                      proplists:get_value(options, Info, []));
        Error ->
            io:format(standard_error, "cannot inspect ~s: ~p~n", [File, Error]),
            halt(2)
    end
end,
lists:foreach(fun(File) ->
                      case IsTestCompiled(File) of
                          true -> io:format("~s~n", [File]);
                          false -> ok
                      end
              end, Files),
halt().
' 2>/dev/null
}

remove_test_compiled_kazoo_beams() {
    local beam beam_real root_real scan_output
    local -a test_beams=()
    [[ $DRY_RUN != true ]] || return 0
    scan_output=$(kazoo_test_compiled_beams) ||
        die 'Could not inspect every Kazoo runtime BEAM for TEST-only code'
    [[ -z $scan_output ]] || mapfile -t test_beams <<<"$scan_output"
    ((${#test_beams[@]})) || return 0
    warn "Removing ${#test_beams[@]} TEST-compiled BEAM file(s) before the production build"
    root_real=$(readlink -f -- "$KAZOO_ROOT") || die "Could not resolve Kazoo source root: ${KAZOO_ROOT}"
    for beam in "${test_beams[@]}"; do
        beam_real=$(readlink -f -- "$beam") || die "Could not resolve generated BEAM path: ${beam}"
        [[ $beam_real == "$root_real"/core/*/ebin/*.beam ||
           $beam_real == "$root_real"/applications/*/ebin/*.beam ||
           $beam_real == "$root_real"/deps/*/ebin/*.beam ]] ||
            die "Refusing to remove unexpected BEAM path: ${beam}"
        rm -f -- "$beam_real"
    done
}

verify_kazoo_production_beams() {
    local scan_output
    local -a test_beams=()
    [[ $DRY_RUN != true ]] || return 0
    scan_output=$(kazoo_test_compiled_beams) ||
        die 'Could not inspect every Kazoo runtime BEAM for TEST-only code'
    [[ -z $scan_output ]] || mapfile -t test_beams <<<"$scan_output"
    ((${#test_beams[@]} == 0)) ||
        die "Kazoo production tree still contains ${#test_beams[@]} TEST-compiled BEAM file(s); refusing to install them"
    log 'PASS Kazoo runtime BEAM files were compiled without TEST-only code'
}

prepare_kazoo_runtime_artifact_permissions() {
    local runtime_root atomic_script
    [[ $DRY_RUN != true ]] || return 0
    runtime_root=$(readlink -f -- "$KAZOO_ROOT")
    [[ -n $runtime_root && $runtime_root != / && -d $runtime_root/applications && -d $runtime_root/core ]] || \
        die 'Cannot validate the Kazoo code tree for runtime artifact permissions'
    # This exact public read-only script is evaluated as the Kazoo service user.
    # A fresh root checkout/build under umask077 must not leave it unreadable.
    atomic_script="$SCRIPT_DIR/verify-ecallmgr-atomic-media.erl"
    [[ -f $atomic_script && ! -L $atomic_script &&
       $(realpath -e -- "$atomic_script") == "$atomic_script" &&
       $(stat -c '%u:%h' -- "$atomic_script") == 0:1 ]] ||
        die 'Cannot prepare an unsafe atomic media verification script'
    chmod 0644 -- "$atomic_script" || die 'Cannot prepare atomic media verification script permissions'
    # Root builds may inherit umask 077. These are code and public schema/view
    # definitions, not deployment configuration, logs, keys, or credential files.
    find "$runtime_root/core" "$runtime_root/applications" "$runtime_root/deps" -type f \
        \( -path '*/ebin/*.beam' -o -path '*/ebin/*.app' \
           -o -path '*/priv/couchdb/*.json' -o -path '*/priv/defaults/*.json' \) \
        -exec chmod 0644 -- {} +
}

# Invocation-local reuse check, not a persistent build cache. Include generated
# BEAMs as well as sources so a test compile or an external rebuild cannot hide
# behind unchanged .app files. Timestamps are ignored; deployment credential
# files are outside this source/build-artifact inventory.
kazoo_build_snapshot() (
    set -o pipefail
    cd -- "$KAZOO_ROOT" || exit 1
    [[ -f Makefile && -f erlang.mk && -f VERSION && -f .base_branch &&
       -d scripts && -d make && -d core && -d applications && -d deps ]] || return 1
    # A skipped linked directory could hide changed compile inputs. Individual
    # linked files are hashed through their target; dangling links fail hashing.
    [[ ! -L scripts && ! -L make && ! -L core && ! -L applications && ! -L deps ]] || return 1
    # Dependency fetch tools keep separate rebar build trees with directory
    # links. They are not the core/apps/deps runtime src/include/ebin inventory.
    linked_directories=$(find scripts make core applications deps \
        \( -name .git -o -name .erlang.mk -o -name _build \) -prune -o \
        -type l -xtype d -print -quit) || return 1
    [[ -z $linked_directories ]] || return 1
    {
        printf '%s\0' "$PWD" "${ERLANG_VERSION:-}" "${ERL_FLAGS:-}" \
            "${ERL_AFLAGS:-}" "${ERL_ZFLAGS:-}" "${ERL_LIBS:-}" \
            "${ERLC_OPTS:-}" "${ERLC_OPTS_SUPERSECRET:-}" "${KZ_VERSION:-}" \
            "${ERL_COMPILER_OPTIONS:-}"
        find Makefile erlang.mk VERSION .base_branch scripts make core applications deps \
            \( -name .git -o -name .erlang.mk -o -name _build \) -prune -o \( \( -type f -o -type l \) \
            \( -name '*.erl' -o -name '*.hrl' -o -name '*.app.src' \
               -o -name '*.beam' -o -name '*.app' -o -name 'Makefile' \
               -o -name '*.mk' -o -name '*.yrl' -o -name '*.xrl' \
               -o -name '*.erl.src' -o -name 'mime.types' -o -name 'dialcodes.json' \
               -o -name 'VERSION' -o -name '.base_branch' -o -name 'next_version' \
               -o -name '*.bash' -o -name '*.sh' -o -name '*.escript' \
               -o -name '*.py' -o -name '*.cjs' \) -print0 \) \
            | LC_ALL=C sort -z | xargs -0 -r sha256sum -- || exit 1
    } | sha256sum | cut -d ' ' -f 1
)

verify_kazoo_current_build() {
    local current_snapshot
    [[ $DRY_RUN != true ]] || return 0
    [[ ${KAZOO_BUILD_SUCCEEDED_THIS_RUN:-false} == true &&
       ${KAZOO_BUILD_SNAPSHOT_THIS_RUN:-} =~ ^[a-f0-9]{64}$ ]] ||
        die 'No successful Kazoo build snapshot from this invocation'
    current_snapshot=$(kazoo_build_snapshot) || die 'Cannot inspect Kazoo build inputs for reuse'
    [[ $current_snapshot == "$KAZOO_BUILD_SNAPSHOT_THIS_RUN" ]] ||
        die 'Kazoo sources or build artifacts changed after compilation; refusing mixed-version activation. Rerun the installer in a maintenance window.'
}

build_kazoo() {
    KAZOO_BUILD_SUCCEEDED_THIS_RUN=false
    KAZOO_BUILD_SNAPSHOT_THIS_RUN=''
    install_kazoo_build_dependencies
    # A new project clone has no ignored core/ or applications/ checkouts yet.
    # Fetch sources before patching or generating files inside those trees.
    run env FETCH_AS=https://github.com/ make -C "$KAZOO_ROOT" \
        JOBS="$KAZOO_MAKE_JOBS" \
        "dep_core=git https://github.com/2600hz/kazoo-core.git $KAZOO_CORE_REF" \
        "dep_crossbar=git https://github.com/2600hz/kazoo-crossbar.git $KAZOO_CROSSBAR_REF" \
        "dep_blackhole=git https://github.com/2600hz/kazoo-blackhole.git $KAZOO_BLACKHOLE_REF" \
        "dep_ecallmgr=git https://github.com/2600hz/kazoo-ecallmgr.git $KAZOO_ECALLMGR_REF" \
        "dep_stepswitch=git https://github.com/2600hz/kazoo-stepswitch.git $KAZOO_STEPSWITCH_REF" \
        "dep_cdr=git https://github.com/2600hz/kazoo-cdr.git $KAZOO_CDR_REF" \
        fetch-core fetch-apps
    ensure_kazoo_sources
    configure_kazoo
    log "Compiling Kazoo with ${KAZOO_MAKE_JOBS} parallel job(s)"
    if [[ $DRY_RUN == true ]]; then
        log "Would generate kazoo_numbers ISO-3166 and kazoo_web MIME sources"
        log "Would build Kazoo core, fetch apps, prebuild webhooks, build apps, and build-dev-release"
        return 0
    fi
    # erlang.mk's compile-test target rewrites normal modules in the shared
    # ebin directories with -DTEST. A later `make all` considers those BEAMs
    # up to date, which can silently deploy test-only branches (notably
    # kapps_config:fetch_category/2 returning not_found for production config).
    # Remove only generated BEAMs that carry the TEST define so make rebuilds
    # their production variants. Source files and runtime data are untouched.
    remove_test_compiled_kazoo_beams
    # The MIME source target also compiles its module with lager_transform.
    # A fresh checkout therefore needs dependency BEAMs before generators, not
    # only when the later top-level core target runs. This is cached by make.
    FETCH_AS=https://github.com/ make -C "$KAZOO_ROOT" JOBS="$KAZOO_MAKE_JOBS" deps
    # kazoo_numbers expands its SOURCES list while parsing its Makefile.  Under
    # a parallel top-level build, that can happen before its generated ISO-3166
    # modules are written, leaving erlc with a source path that does not exist.
    # Materialize both modules first so `make all` is deterministic at any -j.
    # Drop dependency files left malformed by an interrupted generator run.
    rm -f "$KAZOO_ROOT/core/kazoo_numbers/.deps.rules" \
        "$KAZOO_ROOT/core/kazoo_web/.deps.rules"
    # Force only these local outputs, not download prerequisites: newer generated
    # files must not hide restored templates or data carrying older mtimes.
    make -C "$KAZOO_ROOT/core/kazoo_numbers" \
        --eval='.PHONY: src/knm_iso3166a2_itu.erl src/knm_iso3166_util.erl' \
        src/knm_iso3166a2_itu.erl src/knm_iso3166_util.erl
    make -C "$KAZOO_ROOT/core/kazoo_web" --eval='.PHONY: src/kz_mime.erl' src/kz_mime.erl
    # `skel` declares gen_webhook as a behaviour, but the generated aggregate
    # Makefile does not encode inter-application ordering and places webhooks
    # after skel.  Build the behaviour provider once before the parallel app
    # pass so OTP 26's undefined-behaviour warning cannot fail under -Werror.
    FETCH_AS=https://github.com/ make -C "$KAZOO_ROOT" \
        JOBS="$KAZOO_MAKE_JOBS" KAZOO_FORCE_RECOMPILE=1 core fetch-apps
    make -C "$KAZOO_ROOT/applications/webhooks" KAZOO_FORCE_RECOMPILE=1 all
    # Core and app dependencies were already built/fetched above. The root
    # `apps` target depends on `core` and would force that entire build twice.
    # Use its exact applications aggregate recipe while retaining a fresh
    # compilation of every application and the webhooks-before-skel ordering.
    FETCH_AS=https://github.com/ make -C "$KAZOO_ROOT/applications" \
        ROOT="$KAZOO_ROOT" -j"$KAZOO_MAKE_JOBS" KAZOO_FORCE_RECOMPILE=1 all
    FETCH_AS=https://github.com/ make -C "$KAZOO_ROOT" JOBS="$KAZOO_MAKE_JOBS" build-dev-release
    prepare_kazoo_runtime_artifact_permissions
    verify_kazoo_production_beams
    KAZOO_BUILD_SNAPSHOT_THIS_RUN=$(kazoo_build_snapshot) || die 'Cannot record Kazoo build inputs'
    [[ $KAZOO_BUILD_SNAPSHOT_THIS_RUN =~ ^[a-f0-9]{64}$ ]] || die 'Invalid Kazoo build snapshot'
    KAZOO_BUILD_SUCCEEDED_THIS_RUN=true
}

install_kazoo_pivot_port_reservation() {
    local helper=/usr/local/libexec/kazoo5-reserve-pivot-ports parent owner mode
    [[ $DRY_RUN == true || -f $SCRIPT_DIR/reserve-kazoo-pivot-ports.py ]] || \
        die 'Required additive Pivot port-reservation helper is missing'
    if [[ $DRY_RUN != true ]]; then
        for parent in /usr /usr/local /usr/local/libexec; do
            [[ -e $parent || -L $parent ]] || continue
            [[ -d $parent && ! -L $parent ]] || die 'Pivot helper directory must not be a symlink'
            read -r owner mode < <(stat -c '%u %a' "$parent")
            [[ $owner == 0 && $mode =~ ^[0-7]+$ && $((8#$mode & 022)) == 0 ]] || \
                die 'Pivot helper directory must be root-owned and not writable by group/other'
        done
        [[ ! -L $helper && ( ! -e $helper || -f $helper ) ]] || \
            die 'Pivot helper must be a regular non-symlink file'
    fi
    run install -D -o root -g root -m 0755 "$SCRIPT_DIR/reserve-kazoo-pivot-ports.py" "$helper"
    # A static sysctl.d assignment would replace operator reservations. Merge
    # the current kernel list after systemd-sysctl, before either Kazoo node.
    write_file 0644 /etc/systemd/system/kazoo-pivot-port-reservation.service <<'EOF'
[Unit]
Description=Reserve Kazoo Pivot listeners against ephemeral port assignment
Wants=systemd-sysctl.service
After=systemd-sysctl.service
Before=kazoo-apps.service kazoo-ecallmgr.service

[Service]
Type=oneshot
User=root
Group=root
UMask=0077
RuntimeDirectory=kazoo5-reserved-ports
RuntimeDirectoryMode=0700
ExecStart=/usr/local/libexec/kazoo5-reserve-pivot-ports --apply
RemainAfterExit=yes
TimeoutStartSec=15
NoNewPrivileges=yes
EOF
}

install_kazoo_systemd_units() {
    local fqdn role=${1:-}
    [[ $# == 1 ]] || die 'Specify exactly one service-unit role: kazoo-apps, ecallmgr, or all'
    case $role in
        kazoo-apps|ecallmgr|all) ;;
        *) die 'Unknown Kazoo service-unit role; no units were changed' ;;
    esac
    case ${KAZOO_NODE_NAME_TYPE:-} in
        -name|-sname) ;;
        *) die 'Run installer preflight before writing Kazoo service units; Erlang naming mode is not initialized' ;;
    esac
    fqdn=$KAZOO_HOSTNAME
    if ! getent group kazoo >/dev/null; then
        run groupadd --system kazoo
    fi
    if ! id kazoo >/dev/null 2>&1; then
        run useradd --system --gid kazoo --home-dir /var/lib/kazoo --shell /sbin/nologin kazoo
    fi
    run mkdir -p /var/lib/kazoo "$KAZOO_ROOT/log" \
        "$KAZOO_ROOT/scripts/log/log" "$KAZOO_ROOT/var/lib/ra"
    reject_secret_symlink "$KAZOO_RUNTIME_COOKIE_FILE"
    printf '%s\n' "$KAZOO_COOKIE" | write_file 0400 "$KAZOO_RUNTIME_COOKIE_FILE"
    run chown kazoo:kazoo "$KAZOO_RUNTIME_COOKIE_FILE"
    run chown -R kazoo:kazoo /var/lib/kazoo \
        "$KAZOO_ROOT/log" "$KAZOO_ROOT/scripts/log" "$KAZOO_ROOT/var"
    run install -d -m 0750 -o kazoo -g kazoo /var/log/kazoo
    install_kazoo_pivot_port_reservation
    if [[ $role == kazoo-apps || $role == all ]]; then
        run install -d -m 0750 -o kazoo -g kazoo /var/log/kazoo/kazoo_apps /var/log/kazoo/kazoo_apps/log
        run chown -R kazoo:kazoo /var/log/kazoo/kazoo_apps
        write_file 0644 /etc/systemd/system/kazoo-apps.service <<EOF
[Unit]
Description=Kazoo 5 Applications Node
Wants=network-online.target
Requires=kazoo-pivot-port-reservation.service
After=network-online.target kazoo-pivot-port-reservation.service

[Service]
Type=simple
User=kazoo
Group=kazoo
UMask=0027
WorkingDirectory=${KAZOO_ROOT}
Environment=KAZOO_ROOT=${KAZOO_ROOT}
Environment=HOME=/var/lib/kazoo
Environment=KAZOO_CONFIG=${KAZOO_CONFIG_DIR}/core/config.ini
Environment=KAZOO_ACDC_EDITOR_CAPABILITIES=${KAZOO_CONFIG_DIR}/acdc/language-capabilities.json
Environment=KAZOO_LOG_ROOT=/var/log/kazoo/kazoo_apps
Environment="KAZOO_APPS=${KAZOO_APPS_LIST}"
Environment="KAZOO_NODE_NAME_TYPE=${KAZOO_NODE_NAME_TYPE}"
Environment="KAZOO_ERLANG_DIST_IP=${KAZOO_ERLANG_DIST_IP}"
Environment="ERL_FLAGS=-noshell -noinput"
ExecStartPre=/usr/local/libexec/kazoo5-reserve-pivot-ports --check
ExecStartPre=/usr/bin/env KAZOO_DEPLOYMENT_CONFIG=/nonexistent /usr/bin/bash -c 'source ${SCRIPT_DIR}/install-kazoo5.sh; verify_kazoo_production_beams'
ExecStart=${KAZOO_ROOT}/scripts/dev-start-apps.sh kazoo_apps
Restart=on-failure
RestartSec=5
TimeoutStartSec=180
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
Alias=kazoo-applications.service
EOF
    fi
    if [[ $role == ecallmgr || $role == all ]]; then
        run install -d -m 0750 -o kazoo -g kazoo /var/log/kazoo/ecallmgr /var/log/kazoo/ecallmgr/log
        run chown -R kazoo:kazoo /var/log/kazoo/ecallmgr
        write_file 0644 /etc/systemd/system/kazoo-ecallmgr.service <<EOF
[Unit]
Description=Kazoo 5 eCallMgr Node
Wants=network-online.target
Requires=kazoo-pivot-port-reservation.service
After=network-online.target kazoo-pivot-port-reservation.service

[Service]
Type=simple
User=kazoo
Group=kazoo
UMask=0027
WorkingDirectory=${KAZOO_ROOT}
Environment=KAZOO_ROOT=${KAZOO_ROOT}
Environment=HOME=/var/lib/kazoo
Environment=KAZOO_CONFIG=${KAZOO_CONFIG_DIR}/core/config.ini
Environment=KAZOO_LOG_ROOT=/var/log/kazoo/ecallmgr
Environment=KAZOO_APPS=ecallmgr
Environment="KAZOO_NODE_NAME_TYPE=${KAZOO_NODE_NAME_TYPE}"
Environment="KAZOO_ERLANG_DIST_IP=${KAZOO_ERLANG_DIST_IP}"
Environment="ERL_FLAGS=-noshell -noinput"
ExecStartPre=/usr/local/libexec/kazoo5-reserve-pivot-ports --check
ExecStartPre=/usr/bin/env KAZOO_DEPLOYMENT_CONFIG=/nonexistent /usr/bin/bash -c 'source ${SCRIPT_DIR}/install-kazoo5.sh; verify_kazoo_production_beams'
ExecStart=${KAZOO_ROOT}/scripts/dev-start-ecallmgr.sh ecallmgr
Restart=on-failure
RestartSec=5
TimeoutStartSec=180
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
    fi
    run systemctl daemon-reload
}

install_sup_cli() {
    log 'Installing the Kazoo SUP administration command and Bash completion'
    [[ $DRY_RUN == true || -x ${KAZOO_ROOT}/core/sup/sup ]] || \
        die 'The SUP executable was not produced by the Kazoo build'
    run env -u ERL_FLAGS -u ERL_AFLAGS -u ERL_ZFLAGS -u ERL_LIBS \
        escript "$SCRIPT_DIR/verify-sup-archive.escript" "$KAZOO_ROOT/core/sup/sup"
    if [[ $DRY_RUN == true ]]; then
        run make -C "$KAZOO_ROOT" sup_completion
    else
        make -C "$KAZOO_ROOT" sup_completion >/dev/null
    fi
    write_file 0644 /usr/local/share/kazoo5-installer/kazoo-root <<<"$KAZOO_ROOT"
    write_file 0755 /usr/local/bin/sup <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Keep credentials out of this world-readable wrapper, its environment, and
# process arguments. The protected installer-owned config is the source of
# truth; SUP reads the cookie from that file itself.
readonly DEFAULT_KAZOO_ROOT=/opt/kazoo
readonly DEFAULT_KAZOO_CONFIG=/etc/kazoo/core/config.ini
if [[ -n ${KAZOO_ROOT:-} ]]; then
    sup_root=$KAZOO_ROOT
elif [[ -r /usr/local/share/kazoo5-installer/kazoo-root ]]; then
    sup_root=$(</usr/local/share/kazoo5-installer/kazoo-root)
else
    sup_root=$DEFAULT_KAZOO_ROOT
fi
sup_config=${KAZOO_CONFIG:-$DEFAULT_KAZOO_CONFIG}

[[ -r $sup_config ]] || {
    printf 'SUP cannot read its protected Kazoo configuration: %s\n' "$sup_config" >&2
    exit 1
}
export KAZOO_ROOT="$sup_root" KAZOO_CONFIG="$sup_config"
unset KAZOO_COOKIE

# OTP 26 rejects a hostname-qualified short node name. SUP's default name
# inference predates that behavior, so select short names explicitly on hosts
# whose canonical hostname has no domain component.
declare -a name_args=()
sup_host=$(hostname -f 2>/dev/null || hostname)
[[ $sup_host == *.* ]] || name_args=(-s true)

# Compatibility spelling requested by operators. The pinned Kazoo controller
# exports running_apps/0, not kapps/0. Preserve all SUP options and only map the
# exact argument-free module/function pair; other commands remain untouched.
sup_args=("$@")
sup_command_index=0
while ((sup_command_index < ${#sup_args[@]})); do
    case ${sup_args[sup_command_index]} in
        -n|-c|-t|--node|--cookie|--timeout) ((sup_command_index+=2)) ;;
        --node=*|--cookie=*|--timeout=*|--use_short=*|--erl_term_args=*|-v|--verbose)
            ((sup_command_index+=1)) ;;
        -s|-e|--use_short|--erl_term_args)
            ((sup_command_index+=1))
            case ${sup_args[sup_command_index]:-} in
                true|false) ((sup_command_index+=1)) ;;
            esac ;;
        --) ((sup_command_index+=1)); break ;;
        *) break ;;
    esac
done
if ((sup_command_index + 2 == ${#sup_args[@]})) &&
   [[ ${sup_args[sup_command_index]} == kapps_controller && ${sup_args[sup_command_index+1]} == kapps ]]; then
    sup_args[sup_command_index+1]=running_apps
fi

# Root systemd/automation invocations may have no HOME. OTP initializes its
# distribution authentication before SUP reads the configured cluster cookie,
# and otherwise crashes in filename:basedir_join_home/1. Resolve the real
# invoking user's home through NSS; never invent a shared writable directory.
if [[ -z ${HOME:-} ]]; then
    sup_passwd=$(getent passwd "$(id -u)") || {
        printf 'SUP cannot resolve the invoking user home directory\n' >&2
        exit 1
    }
    IFS=: read -r _ _ _ _ _ sup_home _ <<<"$sup_passwd"
    [[ $sup_home == /* && -d $sup_home && ! $sup_home =~ [[:cntrl:]] ]] || {
        printf 'SUP requires a valid invoking user home directory\n' >&2
        exit 1
    }
    exec env "HOME=$sup_home" "$sup_root/core/sup/sup" "${name_args[@]}" "${sup_args[@]}"
fi
exec "$sup_root/core/sup/sup" "${name_args[@]}" "${sup_args[@]}"
EOF
    run install -D -m 0644 "$KAZOO_ROOT/sup.bash" /etc/bash_completion.d/sup
}

persist_kazoo_apps_config() {
    local fqdn erl_call_bin output rpc deadline app erlang_apps=
    local -a apps
    [[ $DRY_RUN != true ]] || return 0
    fqdn=$KAZOO_HOSTNAME
    erl_call_bin=$(find_erl_call) || die 'erl_call was not installed with Erlang'
    IFS=, read -r -a apps <<<"$KAZOO_APPS_LIST"
    for app in "${apps[@]}"; do
        [[ -z $erlang_apps ]] || erlang_apps+=,
        erlang_apps+="<<\"${app}\">>"
    done
    # erl_call's -a parser represents quoted values as Erlang charlists. That
    # would turn the key "kapps" into nested numeric JSON keys. Evaluate a
    # constrained expression (the input was validated in preflight) so the
    # category, key, and values are real Erlang binaries.
    rpc="kapps_config:set_default(<<\"kapps_controller\">>, <<\"kapps\">>, [${erlang_apps}])."
    deadline=$((SECONDS + KAZOO_START_TIMEOUT))
    while ((SECONDS < deadline)); do
        output=$(printf '%s\n' "$rpc" | timeout --signal=KILL 10 \
            runuser --user kazoo -- "$erl_call_bin" \
            "$KAZOO_NODE_NAME_TYPE" "kazoo_apps@${fqdn}" -e 2>/dev/null || true)
        if [[ $output == \{ok,* ]]; then
            log 'Persisted kapps_controller.kapps for SUP and future restarts'
            return 0
        fi
        sleep 2
    done
    die 'Could not persist the Kazoo application list through the running applications node'
}

load_or_create_master_credentials() {
    local stored_password stored_realm stored_user owner mode
    [[ -n $KAZOO_MASTER_ACCOUNT_REALM ]] || \
        KAZOO_MASTER_ACCOUNT_REALM="master.${KAZOO_HOSTNAME//_/-}"
    if [[ -e $KAZOO_INSTALLER_SECRETS || -L $KAZOO_INSTALLER_SECRETS ]]; then
        [[ -f $KAZOO_INSTALLER_SECRETS && ! -L $KAZOO_INSTALLER_SECRETS ]] || \
            die 'The installer credential store must be a regular file, not a symlink'
        read -r owner mode < <(stat -c '%u %a' "$KAZOO_INSTALLER_SECRETS")
        [[ $owner == 0 && $mode == 600 ]] || \
            die 'The installer credential store must be owned by root with mode 0600'
        [[ -r $KAZOO_INSTALLER_SECRETS ]] || \
            die "Cannot read installer credentials: ${KAZOO_INSTALLER_SECRETS}"
        stored_password=$(sed -n 's/^KAZOO_MASTER_ADMIN_PASSWORD=//p' \
            "$KAZOO_INSTALLER_SECRETS" | tail -1)
        stored_realm=$(sed -n 's/^KAZOO_MASTER_ACCOUNT_REALM=//p' \
            "$KAZOO_INSTALLER_SECRETS" | tail -1)
        stored_user=$(sed -n 's/^KAZOO_MASTER_ADMIN_USER=//p' \
            "$KAZOO_INSTALLER_SECRETS" | tail -1)
        [[ -n $stored_password ]] || die 'The installer credential store has no administrator password'
        [[ -n $stored_realm ]] || die 'The installer credential store has no master account realm'
        [[ -n $stored_user ]] || die 'The installer credential store has no administrator username'
        [[ -n $KAZOO_MASTER_ADMIN_PASSWORD ]] || KAZOO_MASTER_ADMIN_PASSWORD=$stored_password
        [[ $KAZOO_MASTER_ACCOUNT_REALM_EXPLICIT == true ]] || KAZOO_MASTER_ACCOUNT_REALM=$stored_realm
        [[ $KAZOO_MASTER_ADMIN_USER_EXPLICIT == true ]] || KAZOO_MASTER_ADMIN_USER=$stored_user
    fi
    [[ $KAZOO_MASTER_ACCOUNT_REALM =~ ^[a-zA-Z0-9.-]+$ ]] || \
        die 'The stored master account realm is invalid'
    [[ $KAZOO_MASTER_ADMIN_USER =~ ^[a-zA-Z0-9_.@-]+$ ]] || \
        die 'The stored master administrator username is invalid'
    validate_safe_value KAZOO_MASTER_ADMIN_PASSWORD "$KAZOO_MASTER_ADMIN_PASSWORD"
    [[ $DRY_RUN != true && $VERIFY_ONLY != true ]] || return 0
    # A caller-supplied initial password also has to survive the next run.
    # Never replace an existing credential store with an unverified override.
    [[ ! -e $KAZOO_INSTALLER_SECRETS ]] || return 0
    [[ -n $KAZOO_MASTER_ADMIN_PASSWORD ]] || KAZOO_MASTER_ADMIN_PASSWORD=$(openssl rand -hex 24)
    {
        printf 'KAZOO_MASTER_ACCOUNT_REALM=%s\n' "$KAZOO_MASTER_ACCOUNT_REALM"
        printf 'KAZOO_MASTER_ADMIN_USER=%s\n' "$KAZOO_MASTER_ADMIN_USER"
        printf 'KAZOO_MASTER_ADMIN_PASSWORD=%s\n' "$KAZOO_MASTER_ADMIN_PASSWORD"
    } | write_file 0600 "$KAZOO_INSTALLER_SECRETS"
    log "Saved the initial Monster UI administrator credentials in ${KAZOO_INSTALLER_SECRETS} (mode 0600)"
}

master_account_id() {
    timeout --signal=KILL 30 sup kapps_util get_master_account_id </dev/null 2>/dev/null || true
}

configured_master_account_id() {
    local configured
    # get_master_account_id/0 auto-discovers and saves a missing master ID.
    # Verification must instead fail without bootstrapping configuration.
    configured=$(timeout --signal=KILL 30 sup -e kapps_config get_ne_binary \
        '<<"accounts">>' '<<"master_account_id">>' </dev/null) || \
        die 'Could not read the configured Kazoo master account ID'
    [[ $configured =~ ^\<\<\"([0-9a-f]{32})\"\>\>$ ]] || \
        die 'Kazoo master account ID is not configured; verification does not auto-discover or save it'
    printf '%s\n' "${BASH_REMATCH[1]}"
}

bootstrap_master_account_rpc() {
    local erl_call_bin account_name_b64 realm_b64 admin_user_b64 admin_password_b64 rpc status output
    local xtrace_enabled=false
    erl_call_bin=$(find_erl_call) || die 'erl_call was not installed with Erlang'
    verify_cookie_copy "$KAZOO_RUNTIME_COOKIE_FILE" kazoo

    # Keep every operator-supplied value out of argv and make the expression
    # inert even when names or passwords contain quotes, Unicode, or Erlang
    # syntax. The RPC client reads its authentication cookie from the protected
    # kazoo-owned cookie file; inherited secret variables are removed as well.
    if [[ $- == *x* ]]; then
        set +x
        xtrace_enabled=true
    fi
    account_name_b64=$(printf '%s' "$KAZOO_MASTER_ACCOUNT_NAME" | base64 -w0)
    realm_b64=$(printf '%s' "$KAZOO_MASTER_ACCOUNT_REALM" | base64 -w0)
    admin_user_b64=$(printf '%s' "$KAZOO_MASTER_ADMIN_USER" | base64 -w0)
    admin_password_b64=$(printf '%s' "$KAZOO_MASTER_ADMIN_PASSWORD" | base64 -w0)
    printf -v rpc '%s' \
        "try case crossbar_maintenance:create_account(base64:decode(<<\"${account_name_b64}\">>), base64:decode(<<\"${realm_b64}\">>), base64:decode(<<\"${admin_user_b64}\">>), base64:decode(<<\"${admin_password_b64}\">>)) of ok -> ok; _ -> failed end catch _:_ -> failed end."
    # erl_call exits zero even when the maintenance function returns failed.
    # Return only fixed atoms, suppress remote stdout, and accept exact success.
    if output=$(timeout --signal=KILL 120 runuser --user kazoo -- \
        env -u KAZOO_COOKIE -u KAZOO_MASTER_ADMIN_PASSWORD \
        "$erl_call_bin" "$KAZOO_NODE_NAME_TYPE" "kazoo_apps@${KAZOO_HOSTNAME}" \
        -e <<<"$rpc" 2>/dev/null); then
        status=1
        [[ $output != '{ok, ok}' ]] || status=0
    else
        status=$?
    fi
    [[ $xtrace_enabled == false ]] || set -x
    return "$status"
}

wait_kazoo_bootstrap_ready() {
    local erl_call_bin rpc output deadline
    erl_call_bin=$(find_erl_call) || die 'erl_call was not installed with Erlang'
    verify_cookie_copy "$KAZOO_RUNTIME_COOKIE_FILE" kazoo
    # Crossbar starts its binding modules asynchronously. Datastore readiness
    # and even an HTTP listener alone do not mean account/user routes are ready.
    # create_account constructs schema defaults before its own prechecks. Wait
    # for their read-only loads before allowing any initial account mutation.
    rpc='try M = crossbar_bindings:modules_loaded(), Schemas = lists:all(fun(S) -> case kz_json_schema:load(S) of {ok, _} -> true; _ -> false end end, [<<"accounts">>, <<"users">>, <<"profile">>]), case Schemas andalso lists:keymember(crossbar, 1, application:which_applications()) andalso lists:all(fun(A) -> lists:member(A, M) end, [cb_accounts, cb_users]) of true -> ready; false -> not_ready end catch _:_ -> not_ready end.'
    deadline=$((SECONDS + KAZOO_START_TIMEOUT))
    while ((SECONDS < deadline)); do
        if output=$(timeout --signal=KILL 10 runuser --user kazoo -- "$erl_call_bin" \
            "$KAZOO_NODE_NAME_TYPE" "kazoo_apps@${KAZOO_HOSTNAME}" -e <<<"$rpc" 2>/dev/null); then
            if [[ $output == '{ok, ready}' ]]; then
                log 'PASS Crossbar account/user bootstrap bindings are ready'
                return 0
            fi
        fi
        sleep 2
    done
    die 'Crossbar account/user bindings did not become ready; no account creation attempted'
}

ensure_master_account() {
    local account_id deadline
    [[ $KAZOO_BOOTSTRAP_MASTER_ACCOUNT == true ]] || return 0
    command -v sup >/dev/null || die 'SUP is required to bootstrap the Kazoo master account'
    account_id=$(master_account_id)
    if [[ $account_id == \{ok,* ]]; then
        log "Kazoo master account already exists: ${account_id}"
        return 0
    fi
    wait_kazoo_bootstrap_ready
    load_or_create_master_credentials
    [[ -n $KAZOO_MASTER_ADMIN_PASSWORD ]] || \
        die "No master account exists; set KAZOO_MASTER_ADMIN_PASSWORD or run installation (credentials are stored in ${KAZOO_INSTALLER_SECRETS})"
    if ! bootstrap_master_account_rpc; then
        die 'Could not create the Kazoo master account through the protected Erlang RPC'
    fi
    deadline=$((SECONDS + KAZOO_START_TIMEOUT))
    while ((SECONDS < deadline)); do
        account_id=$(master_account_id)
        [[ $account_id == \{ok,* ]] && {
            log "Created Kazoo master account ${account_id}; credentials are in ${KAZOO_INSTALLER_SECRETS}"
            return 0
        }
        sleep 2
    done
    die 'Crossbar returned success but the Kazoo master account was not discoverable'
}

install_acdc_editor_capabilities() {
    if [[ $DRY_RUN == true ]]; then
        log "Would preserve or create a protected all-false editor language manifest in ${KAZOO_CONFIG_DIR}/acdc; no full-language readiness publication"
        return 0
    fi
    # Node is installed by the immutable voice preflight. The configuration root
    # exists from common installation preparation. No SUP or database lookup is
    # needed, so a separate apps host works before its first service start.
    node "$SCRIPT_DIR/ensure-acdc-language-capabilities.cjs" --config-root "$KAZOO_CONFIG_DIR" || \
        die 'Could not safely initialize the apps-owned editor capability fallback'
}

finalize_acdc_prerecorded_capabilities() (
    set -euo pipefail
    local mode=${1:---install} account=''
    [[ $mode == --install || $mode == --check ]] || die 'Invalid prerecorded capability operation'
    if [[ $DRY_RUN == true ]]; then
        log 'Would prove prerecorded runtime functions before publishing installer-owned selection capability; native/full readiness stays false'
        return 0
    fi
    if [[ $mode == --install ]]; then
        [[ $VERIFY_ONLY != true ]] || die 'Verification cannot publish prerecorded capability'
        verify_kazoo_current_build
        account=$(configured_master_account_id) || die 'Prerecorded proof requires the configured existing account'
        [[ $account =~ ^[0-9a-f]{32}$ ]] || die 'Invalid prerecorded proof account'
    fi
    node - "$mode" "$SCRIPT_DIR" "$KAZOO_ROOT" "$KAZOO_CONFIG_DIR" "$KAZOO_HOSTNAME" \
        "$account" "${KAZOO_BUILD_SNAPSHOT_THIS_RUN:-}" "$(acdc_cardinal_index_pin)" "$MONSTER_UI_WEB_ROOT" <<'JS'
// ACDC_PRERECORDED_FINALIZATION_BEGIN
'use strict';
try {
    const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
    const assert = require('node:assert/strict');
    const [mode, scripts, root, configRoot, host, account, build, indexSha, webRoot] = process.argv.slice(2);
    const probe = require(path.join(scripts, 'probe-acdc-prerecorded-runtime.cjs'));
    const publisher = require(path.join(scripts, 'publish-acdc-prerecorded-capabilities.cjs'));
    const {assertLanguageCapabilities} = require(path.join(scripts, 'validate-acdc-language-capabilities.cjs'));
    const run = args => {
        const r = cp.spawnSync('/usr/local/bin/sup', ['-e', ...args],
            {encoding: 'utf8', timeout: 30000, maxBuffer: 65536, stdio: ['ignore', 'pipe', 'pipe']});
        assert(!r.error && r.status === 0, 'Capability config RPC failed'); return r.stdout.trim();
    };
    // fetch_current has the same node/zone/default precedence but never saves a
    // missing category (get/get_ne_binary may do so, even in verify-only).
    const configArgs = ['kapps_config', 'fetch_current', '<<"acdc.queues">>', '<<"editor_language_capabilities_path">>'];
    const readConfig = () => { const value = run(configArgs); return /^\{error,\s*not_found\}$/.test(value) ? 'undefined' : value; };
    const configured = readConfig(), fallback = path.join(configRoot, 'acdc', 'language-capabilities.json');
    const matched = configured.match(/^<<"(\/[^"\\\r\n]+)">>$/);
    assert(configured === 'undefined' || matched, 'Unsupported explicit capability path');
    const configuredTarget = matched ? matched[1] : fallback;
    assert(probe.absolute(configuredTarget) && probe.absolute(webRoot), 'Noncanonical capability path');
    const pin = (file, limit = 131072) => {
        probe.protectedParents(path.dirname(file));
        const st = fs.lstatSync(file);
        assert(st.isFile() && !st.isSymbolicLink() && st.uid === 0 && st.nlink === 1
            && !(st.mode & 0o022) && st.size > 0 && st.size <= limit, 'Unprotected installer input');
        const h = cp.spawnSync('/usr/bin/sha256sum', [file], {encoding: 'utf8', timeout: 10000, maxBuffer: 4096});
        assert(!h.error && h.status === 0 && probe.validSha(h.stdout.slice(0, 64)), 'Cannot pin installer input');
        const sha256 = h.stdout.slice(0, 64); return {sha256, bytes: probe.readPinned(file, sha256, limit)};
    };
    // Only the current configured web root's exact old installer artifact may
    // migrate. Validation requires all five locales and every legacy flag false.
    // Never overwrite this file: publish under the apps configuration root and
    // switch the effective path only after measured proof and final repins.
    const legacyPath = path.join(webRoot, 'apps', 'acdc', 'language-capabilities.json');
    const legacyInput = configuredTarget === legacyPath && legacyPath !== fallback && fs.existsSync(legacyPath)
        ? pin(legacyPath) : null;
    const legacy = legacyInput ? assertLanguageCapabilities(JSON.parse(legacyInput.bytes)) : null;
    const migrateLegacy = Boolean(legacy && legacy.schema_version === 1 && legacy.backend_mode === 'legacy');
    const target = migrateLegacy ? fallback : configuredTarget;
    assert(probe.absolute(target), 'Noncanonical capability path');
    assert(target !== fallback || /^\/[A-Za-z0-9_./-]+$/.test(target), 'Unsafe default capability path');
    const assertPublicationInputs = () => {
        assert(readConfig() === configured, 'Capability configuration changed during proof/publication');
        if (migrateLegacy) {
            const current = pin(legacyPath);
            assert(current.sha256 === legacyInput.sha256 && current.bytes.equals(legacyInput.bytes),
                'Legacy capability changed during proof/publication');
        }
    };
    const markerPath = digest => target + '.installer-' + digest + '.json';
    const existing = target === fallback && fs.existsSync(target) ? pin(target) : null;
    const old = existing ? assertLanguageCapabilities(JSON.parse(existing.bytes)) : null;
    const native = old && Object.values(old.languages).some(l => l.native_speaker_review);
    const initial = old && old.schema_version === 1 && old.backend_mode === 'legacy';
    let owned = false;
    if (existing && fs.existsSync(markerPath(existing.sha256))) {
        const marker = JSON.parse(pin(markerPath(existing.sha256)).bytes);
        probe.exactKeys(marker, ['owner', 'capability_sha256', 'receipt', 'receipt_sha256']);
        assert(marker.owner === 'kazoo5-acdc-prerecorded-finalization' && marker.capability_sha256 === existing.sha256
            && probe.absolute(marker.receipt) && probe.validSha(marker.receipt_sha256), 'Invalid installer ownership marker');
        owned = marker;
    }
    // Explicit operator paths and reviewed/non-installer artifacts are never
    // automatically replaced, even when the generic publisher could accept them.
    if (migrateLegacy && mode === '--check') {
        console.log('UNAVAILABLE prerecorded selection capability: configured legacy installer artifact is all-negative; install is required to migrate after runtime proof');
        process.exitCode = 1;
    } else if (target !== fallback || native || old && !initial && !owned) {
        console.log('SKIP automatic voice capability publication/check: preserved custom or reviewed artifact; no five-language selection claim');
    } else if (mode === '--check') {
        assert(owned, 'No installer-owned runtime capability proof');
        const evidence = pin(owned.receipt, 65536);
        assert(evidence.sha256 === owned.receipt_sha256, 'Runtime evidence changed');
        const receipt = JSON.parse(evidence.bytes);
        // Routine verification checks old evidence against current files and
        // media receipts; the five-minute publication age rule is not a TTL.
        publisher.validateReceipt(receipt, Date.parse(receipt.finished_at));
        probe.validateBeams({schema_version: 1, modules: receipt.beams});
        assert(receipt.node === 'kazoo_apps@' + host, 'Runtime proof belongs to another node');
        assert(pin('/usr/local/share/kazoo5-installer/acdc-cardinal-media.json', 8 * 1024 * 1024).sha256 === receipt.cardinal_receipt_sha256
            && pin('/usr/local/share/kazoo5-installer/acdc-gemini-media.json').sha256 === receipt.fixed_receipt_sha256,
        'Installed media evidence changed');
        const expected = publisher.capability(receipt, evidence.sha256, Date.parse(old.generated_at));
        assert.deepEqual(old, expected, 'Capability differs from measured runtime evidence');
        assert(configured !== 'undefined', 'Installer capability is shadowed by legacy path precedence');
        console.log('PASS matching installer capability and retained runtime evidence; native/full readiness remains false');
    } else {
        assert(probe.validAccount(account) && probe.validSha(build) && probe.validSha(indexSha));
        probe.protectedParents(path.dirname(target));
        const directory = fs.mkdtempSync(path.join(path.dirname(target), '.prerecorded-proof-'));
        fs.chmodSync(directory, 0o700);
        const modules = probe.MODULES.map(module => {
            const area = module === 'kz_media_map' ? 'core/kazoo_media' : module === 'media_map' ? 'applications/media_mgr' : 'applications/acdc';
            const file = path.join(root, area, 'ebin', module + '.beam');
            return {module, path: file, sha256: pin(file, 8 * 1024 * 1024).sha256};
        });
        const manifest = path.join(directory, 'production-beams.json');
        const manifestSha = probe.createEvidence(manifest, Buffer.from(JSON.stringify({schema_version: 1, modules}) + '\n'));
        probe.createEvidence(path.join(directory, 'build-lineage.json'), Buffer.from(JSON.stringify({
            schema_version: 1, build_snapshot_sha256: build, beam_manifest_sha256: manifestSha, account}) + '\n'));
        const cardinalReceipt = '/usr/local/share/kazoo5-installer/acdc-cardinal-media.json';
        const fixedReceipt = '/usr/local/share/kazoo5-installer/acdc-gemini-media.json';
        const fixedMap = path.join(root, 'applications/acdc/src/acdc_gemini_map.hrl');
        const receipt = path.join(directory, 'runtime-receipt.json');
        const options = probe.parseArgs(['--node', 'kazoo_apps@' + host, '--account', account,
            '--cardinal-receipt', cardinalReceipt, '--cardinal-receipt-sha256', pin(cardinalReceipt, 8 * 1024 * 1024).sha256,
            '--fixed-receipt', fixedReceipt, '--fixed-receipt-sha256', pin(fixedReceipt).sha256,
            '--beam-manifest', manifest, '--beam-manifest-sha256', manifestSha,
            '--fixed-map', fixedMap, '--fixed-map-sha256', pin(fixedMap, 262144).sha256,
            '--fixed-pack', path.join(scripts, 'assets/acdc-gemini-fixed-20260905'),
            '--completion-pack', path.join(scripts, 'assets/acdc-gemini-completion-20260905'),
            '--supplemental-pack', path.join(scripts, 'assets/acdc-gemini-supplemental-20260906'),
            '--model-trial-index', path.join(scripts, 'assets/acdc-gemini-cardinal-model-trials-20260907/index.json'),
            '--model-trial-index-sha256', indexSha, '--alias-file', path.join(scripts, 'acdc-cardinal-reuse-es-20260907.json'),
            '--alias-sha256', 'f1338ba60bbb360a91491fcf3be0d161ca25ff267a2f7ec32c2faacc49ca1b6d', '--output', receipt]);
        const result = probe.execute(options);
        assertPublicationInputs();
        const published = publisher.publish({account, receipt, 'receipt-sha256': result.sha256,
            output: target, 'previous-sha256': existing ? existing.sha256 : 'absent'});
        probe.createEvidence(markerPath(published.sha256), Buffer.from(JSON.stringify({
            owner: 'kazoo5-acdc-prerecorded-finalization', capability_sha256: published.sha256,
            receipt, receipt_sha256: result.sha256}) + '\n'));
        if (configured === 'undefined' || migrateLegacy) {
            assertPublicationInputs();
            run(['kapps_config', 'set_default', '<<"acdc.queues">>', '<<"editor_language_capabilities_path">>', '<<"' + target + '">>']);
            assert(readConfig() === '<<"' + target + '">>', 'Capability path publication unconfirmed');
        }
        console.log('PASS five-language selection capability from measured runtime proof; native/full readiness remains false');
    }
} catch (_) { console.error('Prerecorded capability finalization failed safely; publication/readiness is unconfirmed.'); process.exitCode = 1; }
// ACDC_PRERECORDED_FINALIZATION_END
JS
)

acdc_broker_upgrade_preflight() (
    set +x
    if [[ $DRY_RUN == true ]]; then
        log 'Would verify callback queue properties on the configured broker before apps build/restart'
        return 0
    fi
    export KAZOO_AMQP_URI KAZOO_RABBITMQ_API_URL KAZOO_RABBITMQ_API_USER KAZOO_RABBITMQ_API_PASSWORD
    if [[ -n $KAZOO_RABBITMQ_API_CA_FILE ]]; then
        export KAZOO_RABBITMQ_API_CA_FILE
        # Validate before Node loads extra trust; scope it to this subshell only.
        env -u NODE_EXTRA_CA_CERTS node "$SCRIPT_DIR/acdc-broker-preflight.cjs" --validate-management-ca ||
            die 'RabbitMQ management CA must be a protected certificate-only PEM file'
        export NODE_EXTRA_CA_CERTS=$KAZOO_RABBITMQ_API_CA_FILE
    fi
    timeout --signal=TERM --kill-after=5 90 node "$SCRIPT_DIR/acdc-broker-preflight.cjs" ||
        die 'ACDC broker upgrade preflight failed; no automatic queue deletion. See doc/acdc_broker_upgrade.md'
)

install_kazoo_apps() {
    install_nodejs_toolchain
    acdc_broker_upgrade_preflight
    # Validate/import immutable defaults before touching the application build
    # or restarting mapped code. Fresh bootstrap needs only configured CouchDB,
    # not SUP or a running local Kazoo/FreeSWITCH service.
    install_call_forward_confirmation_pack
    install_acdc_language_packs
    install_acdc_editor_capabilities
    build_kazoo
    install_kazoo_systemd_units kazoo-apps
    install_sup_cli
    install_monster_catalog_receiver
    acdc_broker_upgrade_preflight
    service_enable_restart kazoo-apps.service
    if [[ $DRY_RUN != true ]]; then
        wait_kazoo_datastore_ready kazoo_apps
        persist_kazoo_apps_config
        wait_kazoo_bootstrap_ready
        ensure_master_account
        configure_kazoo_api_modules
    fi
    install_kazoo_prompts
    activate_acdc_voice_mappings
    finalize_acdc_prerecorded_capabilities --install
    verify_kazoo_apps
}

prepare_kazoo_sounds() {
    local source_dir="$KAZOO_BUILD_ROOT/kazoo-sounds"
    if [[ $DRY_RUN == true || ! -d $source_dir/.git ]] || \
       [[ $(git -C "$source_dir" rev-parse HEAD) != "$KAZOO_SOUNDS_REF" ]]; then
        sync_git https://github.com/2600hz/kazoo-sounds.git "$source_dir" "$KAZOO_SOUNDS_REF"
    fi
}

prompt_documents() {
    local manifest=$1
    couchdb_curl --fail --silent --show-error --connect-timeout 5 --max-time 30 \
            -H 'Content-Type: application/json' --data-binary "@$manifest" \
            "http://${KAZOO_COUCHDB_HOST}:${KAZOO_COUCHDB_PORT}/system_media/_all_docs?include_docs=true"
}

install_kazoo_prompts() (
    local source_dir="$KAZOO_BUILD_ROOT/kazoo-sounds/kazoo-core/en/us"
    local manifest=/usr/local/share/kazoo5-installer/system-media-manifest.json
    local import_dir file documents output imported=0
    prepare_kazoo_sounds
    if [[ $DRY_RUN == true ]]; then
        log 'Would import missing pinned English-US system prompts and verify every audio attachment; no synthetic ACDC generation'
        return 0
    fi
    verify_erlang_applications kazoo_apps "$KAZOO_APPS_LIST"
    verify_kazoo_amqp_ready kazoo_apps
    [[ -d $source_dir ]] || die 'Pinned Kazoo English-US prompts are missing'
    # ACDC defaults use separately imported immutable Gemini IDs. Ship this
    # change with that resolver; never regenerate canonical synthetic media.
    # Pinned official prompts remain available for ordinary non-ACDC flows.
    output=$(node "$SCRIPT_DIR/official-kazoo-prompt-manifest.cjs" \
        --source-root "$KAZOO_BUILD_ROOT/kazoo-sounds" --ref "$KAZOO_SOUNDS_REF") || \
        die 'Could not verify the pinned official prompt inventory'
    printf '%s\n' "$output" | write_file 0644 "$manifest"
    jq -e '.keys | length > 0' "$manifest" >/dev/null || die 'Kazoo prompt manifest is empty'
    output=$(timeout 30 sup kz_datamgr db_create system_media) || die 'Could not create system_media'
    [[ $output == true ]] || die 'system_media database is unavailable'
    documents=$(prompt_documents "$manifest")
    import_dir=$(mktemp -d /tmp/kazoo-prompts-import.XXXXXX)
    trap 'find "$import_dir" -maxdepth 1 -type f -name "*.wav" -delete; rmdir -- "$import_dir"' EXIT
    chmod 0755 "$import_dir"
    while IFS= read -r file; do
        [[ $file =~ ^[a-zA-Z0-9_-]+\.wav$ ]] || die 'Invalid source prompt name'
        # Import the selected immutable blob, not a possibly modified/ignored
        # checkout file. Existing remote/custom attachments remain untouched.
        git -C "$KAZOO_BUILD_ROOT/kazoo-sounds" show \
            "${KAZOO_SOUNDS_REF}:kazoo-core/en/us/${file}" >"$import_dir/$file" || \
            die 'A required pinned source prompt is missing'
        [[ -s $import_dir/$file ]] || die 'A required pinned source prompt is empty'
        chmod 0644 "$import_dir/$file"
        imported=$((imported + 1))
    done < <(jq -r '.rows[] | select(.error == "not_found" or .value.deleted == true or ((.doc._attachments // {}) | length == 0)) | .key | ltrimstr("en-us/") + ".wav"' <<<"$documents")
    if ((imported > 0)); then
        log "Importing ${imported} missing English-US prompts; existing audio is preserved"
        output=$(timeout 600 sup kazoo_media_maintenance import_prompts "$import_dir" en-us) || \
            die 'Kazoo system prompt import did not finish successfully'
        [[ $output == *'importing went successfully'* ]] || die 'Kazoo reported errors importing system prompts'
    fi
    verify_kazoo_prompts
)

verify_kazoo_prompts() {
    local manifest=/usr/local/share/kazoo5-installer/system-media-manifest.json documents expected
    [[ $DRY_RUN != true ]] || return 0
    [[ -s $manifest ]] || die 'Kazoo system prompt manifest is missing; install kazoo-apps'
    expected=$(jq -er '.keys | length | select(. > 0)' "$manifest") || die 'Invalid prompt manifest'
    documents=$(prompt_documents "$manifest") || die 'Could not verify system prompt documents'
    validate_prompt_documents "$expected" <<<"$documents" || \
        die 'A required Kazoo system prompt has no usable audio attachment'
    log "PASS ${expected} English-US system prompts with audio attachments"
}

validate_prompt_documents() {
    jq -e --argjson expected "$1" '.rows | length == $expected and all(.[]; .error == null and .value.deleted != true and ((.doc._attachments // {}) | length > 0) and all(.doc._attachments[]; .length > 0))' >/dev/null
}

ensure_system_media_database() (
    local response status
    if [[ $DRY_RUN == true ]]; then
        log "Would ensure only system_media exists in configured CouchDB ${KAZOO_COUCHDB_HOST}:${KAZOO_COUCHDB_PORT}; existing contents are preserved"
        return 0
    fi
    response=$(mktemp /tmp/kazoo-system-media-database.XXXXXX)
    trap 'rm -f -- "$response"' EXIT
    status=$(couchdb_curl --silent --show-error --connect-timeout 5 --max-time 30 \
        --request PUT --output "$response" --write-out '%{http_code}' \
        "http://${KAZOO_COUCHDB_HOST}:${KAZOO_COUCHDB_PORT}/system_media") || \
        die 'Could not ensure the configured system_media database'
    case $status in
        201|202) jq -e '.ok == true' "$response" >/dev/null || die 'Unconfirmed system_media creation' ;;
        412) jq -e '.error == "file_exists"' "$response" >/dev/null || die 'Unexpected system_media conflict' ;;
        *) die 'Configured CouchDB rejected system_media creation/existence check' ;;
    esac
    couchdb_curl --fail --silent --show-error --connect-timeout 5 --max-time 30 \
        "http://${KAZOO_COUCHDB_HOST}:${KAZOO_COUCHDB_PORT}/system_media" | \
        jq -e '.db_name == "system_media"' >/dev/null || die 'Configured system_media identity could not be verified'
)

acdc_cardinal_index_pin() {
    printf '%s\n' 'b6c4e2a2ef515be72d378a239086b4421992a095447003c1c397c925d98c1e51'
}

run_acdc_cardinal_pack() {
    local mode=$1
    [[ $mode == --plan || $mode == --import || $mode == --verify-only ]] || die 'Invalid cardinal media operation'
    [[ -s $SCRIPT_DIR/install-acdc-cardinal-pack.cjs ]] || die 'Required checked-in cardinal installer adapter is missing'
    # Release pin is updated only after the complete saved recording inventory
    # is verified. Never derive trust from a locally altered index at install.
    node "$SCRIPT_DIR/install-acdc-cardinal-pack.cjs" "$mode" --all-locales \
        --model-trial-index "$SCRIPT_DIR/assets/acdc-gemini-cardinal-model-trials-20260907/index.json" \
        --model-trial-index-sha256 "$(acdc_cardinal_index_pin)" \
        --supplemental-pack "$SCRIPT_DIR/assets/acdc-gemini-supplemental-20260906" \
        --alias-file "$SCRIPT_DIR/acdc-cardinal-reuse-es-20260907.json" \
        --alias-sha256 f1338ba60bbb360a91491fcf3be0d161ca25ff267a2f7ec32c2faacc49ca1b6d
}

validate_acdc_cardinal_receipt() {
    local mode=$1
    jq -e --arg mode "$mode" '
        .owner == "kazoo5-acdc-cardinal-installer" and .scope == "all-locales"
        and .mode == $mode and .count == 584 and .source_complete == true
        and .resolution_mode == "indexed-model-trials-v1" and .resolution_complete == true
        and .runtime_ready == false and .five_language_release_ready == false
        and .listening_verified == false and .queue_configuration_changed == false
        and (.locales | length == 5)
        and ([.locales[].locale] | sort == ["ar-sa","en-us","es-es","fr-fr","he-il"])
        and all(.locales[]; .count == ({"en-us":31,"he-il":131,"fr-fr":161,"es-es":53,"ar-sa":208}[.locale]))
        and (if $mode == "PLAN_ONLY_NO_DATABASE_ACCESS" then .database_verified == false
            else .database_verified == true and .verified == 584
                and all(.locales[]; .mode == "VERIFY_ONLY" and .verified == .count
                    and .created == 0 and .intro_installed_verified == true) end)
    ' >/dev/null
}

install_call_forward_confirmation_pack() (
    if [[ $DRY_RUN == true ]]; then
        log 'Would verify and create-only import five packaged EN/HE/AR/ES/FR forwarded-call confirmation recordings; no account changes or synthesis'
        return 0
    fi
    install_nodejs_toolchain
    node "$SCRIPT_DIR/call-forward-confirmation-pack.cjs" --plan >/dev/null || die 'Forwarded-call confirmation source pack is incomplete'
    ensure_system_media_database
    export KAZOO_COUCHDB_HOST KAZOO_COUCHDB_PORT KAZOO_COUCHDB_USER KAZOO_COUCHDB_PASSWORD
    node "$SCRIPT_DIR/call-forward-confirmation-pack.cjs" --import || die 'Forwarded-call confirmation import/readback failed'
)

verify_call_forward_confirmation_pack() (
    [[ $DRY_RUN != true ]] || return 0
    export KAZOO_COUCHDB_HOST KAZOO_COUCHDB_PORT KAZOO_COUCHDB_USER KAZOO_COUCHDB_PASSWORD
    node "$SCRIPT_DIR/call-forward-confirmation-pack.cjs" --verify-only || die 'Forwarded-call confirmation recordings are missing or changed'
)

install_acdc_language_packs() (
    local fixed_dir="$SCRIPT_DIR/assets/acdc-gemini-fixed-20260905"
    local completion_dir="$SCRIPT_DIR/assets/acdc-gemini-completion-20260905" receipt
    local supplemental_dir="$SCRIPT_DIR/assets/acdc-gemini-supplemental-20260906"
    if [[ $DRY_RUN == true ]]; then
        log "Would create-only import and verify 210 checked-in Gemini EN/AR/HE/ES/FR fixed/callback-digit assets into configured CouchDB ${KAZOO_COUCHDB_HOST}:${KAZOO_COUCHDB_PORT}; preserve official and customer recordings"
        log 'Voice media import requires no provider key, generation call, eSpeak, or local FreeSWITCH; it does not publish runtime or full-position readiness'
        log 'Would preflight all 584 prerecorded EN/HE/FR/ES/AR cardinal assets and exact compiled maps before any media database effects; separately import and byte-verify them and their approved intros'
        return 0
    fi
    [[ -s $SCRIPT_DIR/import-acdc-gemini-voices.cjs && -s $SCRIPT_DIR/validate-acdc-gemini-receipt.cjs ]] || \
        die 'Required immutable voice import/receipt tools are missing'
    install_nodejs_toolchain
    # The source verifier replays the pinned resampling recipe offline. Apps
    # build dependencies are installed later, so clean hosts need SoX here.
    dnf_install sox || die 'Could not install prerecorded audio verification dependency: sox'
    receipt=$(mktemp /tmp/kazoo-acdc-gemini-media.XXXXXX)
    trap 'rm -f -- "$receipt"' EXIT
    # Verify every checked-in source before any database or application effect.
    node "$SCRIPT_DIR/import-acdc-gemini-voices.cjs" --plan --all-locales \
        --fixed-pack "$fixed_dir" --completion-pack "$completion_dir" --supplemental-pack "$supplemental_dir" >"$receipt"
    jq -e '.mode == "PLAN_ONLY_NO_DATABASE_ACCESS" and .count == 210
        and .creates_only_versioned_ids == true and .preserves_legacy_and_custom_media == true
        and .runtime_ready == false' "$receipt" >/dev/null || die 'Incomplete immutable voice source plan'
    run_acdc_cardinal_pack --plan >"$receipt" || die 'Incomplete immutable five-language cardinal source plan'
    validate_acdc_cardinal_receipt PLAN_ONLY_NO_DATABASE_ACCESS <"$receipt" || die 'Invalid five-language cardinal source plan'
    ensure_system_media_database
    # Credentials are inherited only by this child, never placed in argv, URLs,
    # receipts, or public capability artifacts. CouchDB may be a separate host.
    export KAZOO_COUCHDB_HOST KAZOO_COUCHDB_PORT KAZOO_COUCHDB_USER KAZOO_COUCHDB_PASSWORD
    node "$SCRIPT_DIR/import-acdc-gemini-voices.cjs" --import --all-locales \
        --fixed-pack "$fixed_dir" --completion-pack "$completion_dir" --supplemental-pack "$supplemental_dir" >"$receipt"
    validate_acdc_language_receipt <"$receipt" || die 'Incomplete or inconsistent immutable Gemini media import receipt'
    # Do not restart mapped applications based only on a create acknowledgement.
    # Re-fetch and byte-verify all targets through the importer's read-only mode.
    # Publish this latest verification receipt, not earlier create revisions.
    node "$SCRIPT_DIR/import-acdc-gemini-voices.cjs" --verify-only --all-locales \
        --fixed-pack "$fixed_dir" --completion-pack "$completion_dir" --supplemental-pack "$supplemental_dir" >"$receipt"
    validate_acdc_language_receipt <"$receipt" || die 'Immutable Gemini media failed final prestart verification'
    # This receipt is not the language-capabilities runtime manifest. Leave
    # legacy receipts and existing prompt/queue/account documents untouched.
    write_file 0644 /usr/local/share/kazoo5-installer/acdc-gemini-media.json <"$receipt"
    run_acdc_cardinal_pack --import >"$receipt"
    validate_acdc_cardinal_receipt IMPORT_AND_VERIFY <"$receipt" || die 'Incomplete immutable cardinal import readback'
    run_acdc_cardinal_pack --verify-only >"$receipt"
    validate_acdc_cardinal_receipt VERIFY_ONLY <"$receipt" || die 'Incomplete immutable cardinal final readback'
    write_file 0644 /usr/local/share/kazoo5-installer/acdc-cardinal-media.json <"$receipt"
    log 'PASS 210 immutable Gemini voice assets verified; existing audio preserved; runtime and full-position readiness are separate gates'
    log 'PASS 584 immutable five-language cardinal assets and approved intros verified; no provider call; runtime/listening acceptance is separate'
)

validate_acdc_language_receipt() {
    node "$SCRIPT_DIR/validate-acdc-gemini-receipt.cjs" \
        --fixed-pack "$SCRIPT_DIR/assets/acdc-gemini-fixed-20260905" \
        --completion-pack "$SCRIPT_DIR/assets/acdc-gemini-completion-20260905" \
        --supplemental-pack "$SCRIPT_DIR/assets/acdc-gemini-supplemental-20260906"
}

run_acdc_voice_mapping_check() {
    local mode=$1 receipt=$2
    [[ $mode == --activate || $mode == --check ]] || die 'Invalid voice mapping operation'
    [[ -n ${KAZOO_HOSTNAME:-} ]] || \
        die 'Kazoo hostname is not initialized; run installer validation or explicitly set KAZOO_HOSTNAME before sourced verification'
    [[ -s $SCRIPT_DIR/refresh-acdc-gemini-mappings.cjs && -s $SCRIPT_DIR/refresh-acdc-gemini-mappings.erl.template ]] || \
        die 'Required immutable voice mapping tools are missing'
    node "$SCRIPT_DIR/refresh-acdc-gemini-mappings.cjs" "$mode" \
        --node "kazoo_apps@${KAZOO_HOSTNAME}" --receipt "$receipt" \
        --fixed-pack "$SCRIPT_DIR/assets/acdc-gemini-fixed-20260905" \
        --completion-pack "$SCRIPT_DIR/assets/acdc-gemini-completion-20260905" \
        --supplemental-pack "$SCRIPT_DIR/assets/acdc-gemini-supplemental-20260906" || \
        die 'Immutable Gemini prompt mappings could not be verified on the running apps node'
}

run_acdc_cardinal_mapping_check() {
    local mode=$1 receipt=$2
    [[ $mode == --activate || $mode == --check ]] || die 'Invalid cardinal mapping operation'
    [[ -n ${KAZOO_HOSTNAME:-} ]] || die 'Kazoo hostname is required for cardinal mapping verification'
    [[ -s $SCRIPT_DIR/refresh-acdc-cardinal-mappings.cjs && -s $SCRIPT_DIR/refresh-acdc-cardinal-mappings.erl.template ]] || \
        die 'Required prerecorded cardinal mapping tools are missing'
    node "$SCRIPT_DIR/refresh-acdc-cardinal-mappings.cjs" "$mode" \
        --node "kazoo_apps@${KAZOO_HOSTNAME}" --receipt "$receipt" \
        --model-trial-index "$SCRIPT_DIR/assets/acdc-gemini-cardinal-model-trials-20260907/index.json" \
        --model-trial-index-sha256 "$(acdc_cardinal_index_pin)" \
        --supplemental-pack "$SCRIPT_DIR/assets/acdc-gemini-supplemental-20260906" \
        --alias-file "$SCRIPT_DIR/acdc-cardinal-reuse-es-20260907.json" \
        --alias-sha256 f1338ba60bbb360a91491fcf3be0d161ca25ff267a2f7ec32c2faacc49ca1b6d || \
        die 'Prerecorded cardinal mappings could not be verified on the running apps node'
}

activate_acdc_voice_mappings() {
    if [[ $DRY_RUN == true ]]; then
        log 'Would activate/verify the 210 fixed prompts and separate 584 cardinals plus two intros in both running media caches; no database or custom recording changes'
        return 0
    fi
    # Imports happen before services start. Existing nodes/reruns also need
    # targeted cache activation because direct CouchDB imports emit no Kazoo
    # configuration events. This is safe while initial map loading completes.
    verify_erlang_applications kazoo_apps "$KAZOO_APPS_LIST"
    run_acdc_voice_mapping_check --activate /usr/local/share/kazoo5-installer/acdc-gemini-media.json
    run_acdc_cardinal_mapping_check --activate /usr/local/share/kazoo5-installer/acdc-cardinal-media.json
    log 'PASS 796 owned prerecorded media documents resolve in both active maps; no language capability was published'
}

verify_acdc_language_packs() (
    [[ $DRY_RUN != true ]] || return 0
    local receipt
    receipt=$(mktemp /tmp/kazoo-acdc-gemini-verify.XXXXXX)
    trap 'rm -f -- "$receipt"' EXIT
    export KAZOO_COUCHDB_HOST KAZOO_COUCHDB_PORT KAZOO_COUCHDB_USER KAZOO_COUCHDB_PASSWORD
    node "$SCRIPT_DIR/import-acdc-gemini-voices.cjs" --verify-only --all-locales \
        --fixed-pack "$SCRIPT_DIR/assets/acdc-gemini-fixed-20260905" \
        --completion-pack "$SCRIPT_DIR/assets/acdc-gemini-completion-20260905" \
        --supplemental-pack "$SCRIPT_DIR/assets/acdc-gemini-supplemental-20260906" >"$receipt" || \
        die 'Immutable Gemini voice media could not be verified; install kazoo-apps'
    validate_acdc_language_receipt <"$receipt" || die 'Immutable Gemini voice verification receipt is inconsistent'
    # Verification must never repair caches or turn on incomplete languages.
    # Fresh byte verification supplies exact current revisions for this check.
    run_acdc_voice_mapping_check --check "$receipt"
    run_acdc_cardinal_pack --verify-only >"$receipt" || die 'Immutable five-language cardinal media could not be verified'
    validate_acdc_cardinal_receipt VERIFY_ONLY <"$receipt" || die 'Immutable cardinal verification receipt is inconsistent'
    run_acdc_cardinal_mapping_check --check "$receipt"
    log 'PASS 584 cardinal assets plus two new intros, exact installed revisions and both running prompt maps'
    log 'PASS 210 Gemini assets, installed audio bytes and both running prompt maps; no full-position readiness claim'
)

configure_kazoo_api_modules() {
    local module output
    configure_kazoo_scope_management
    for module in cb_queues cb_agents cb_acdc_call_stats cb_external_numbers cb_members cb_entitlements; do
        output=$(timeout 30 sup crossbar_maintenance start_module "$module" </dev/null) || \
            die "Could not register Kazoo Crossbar module ${module}"
        [[ $output != *'failed to start'* ]] || die "Kazoo Crossbar module ${module} failed to start"
    done
    log 'Registered and persisted ACDC and Monster UI Crossbar APIs'
    verify_kazoo_entitlements_module
    configure_kazoo_storage_module
    configure_kazoo_queue_live_module
}

configure_kazoo_storage_module() {
    local output before_autoload before_running after_autoload after_running module
    [[ $DRY_RUN != true ]] || { log 'Would register native storage API without provisioning storage plans'; return 0; }
    output=$(timeout 30 sup crossbar_config autoload_modules </dev/null) || die 'Could not read Crossbar autoload modules before storage registration'
    before_autoload=$(kazoo_blackhole_module_output autoload "$output") || die 'Invalid Crossbar autoload list before storage registration'
    output=$(timeout 30 sup crossbar_bindings modules_loaded </dev/null) || die 'Could not read running Crossbar modules before storage registration'
    before_running=$(kazoo_blackhole_module_output running "$output") || die 'Invalid running Crossbar list before storage registration'
    if [[ $'\n'"$before_autoload"$'\n' == *$'\n'cb_storage$'\n'* &&
          $'\n'"$before_running"$'\n' == *$'\n'cb_storage$'\n'* ]]; then
        log 'PASS native storage API already running and effective'
        return 0
    fi
    # Preserve all existing modules. Do not create account/system storage plans,
    # change provider credentials, or hide an absent optional plan with fake data.
    output=$(timeout 30 sup crossbar_maintenance start_module cb_storage </dev/null) || die 'Could not register native storage API'
    [[ $output != *'failed to start'* ]] || die 'Native storage API failed to start'
    output=$(timeout 30 sup crossbar_config autoload_modules </dev/null) || die 'Could not verify storage startup registration'
    after_autoload=$(kazoo_blackhole_module_output autoload "$output") || die 'Invalid storage autoload readback'
    output=$(timeout 30 sup crossbar_bindings modules_loaded </dev/null) || die 'Could not verify running storage registration'
    after_running=$(kazoo_blackhole_module_output running "$output") || die 'Invalid storage runtime readback'
    [[ $'\n'"$after_autoload"$'\n' == *$'\n'cb_storage$'\n'* &&
       $'\n'"$after_running"$'\n' == *$'\n'cb_storage$'\n'* ]] || die 'Native storage API is not running/effective; inspect node overrides'
    while IFS= read -r module; do
        [[ -z $module || $'\n'"$after_autoload"$'\n' == *$'\n'"$module"$'\n'* ]] || die 'Storage registration lost an existing autoload module'
    done <<<"$before_autoload"
    while IFS= read -r module; do
        [[ -z $module || $'\n'"$after_running"$'\n' == *$'\n'"$module"$'\n'* ]] || die 'Storage registration lost a running module'
    done <<<"$before_running"
    log 'PASS native storage API running/effective; existing modules preserved; no storage plans provisioned'
}

verify_kazoo_storage_module() {
    local kind output modules
    [[ $DRY_RUN != true ]] || return 0
    for kind in autoload running; do
        if [[ $kind == autoload ]]; then
            output=$(timeout 30 sup crossbar_config autoload_modules </dev/null) || die 'Could not inspect storage startup registration'
        else
            output=$(timeout 30 sup crossbar_bindings modules_loaded </dev/null) || die 'Could not inspect storage runtime registration'
        fi
        modules=$(kazoo_blackhole_module_output "$kind" "$output") || die 'Invalid storage registration output'
        [[ $'\n'"$modules"$'\n' == *$'\n'cb_storage$'\n'* ]] || die "cb_storage missing from ${kind}; install kazoo-apps"
    done
}

verify_kazoo_entitlements_module() {
    local kind output modules
    [[ $DRY_RUN != true ]] || return 0
    for kind in autoload running; do
        if [[ $kind == autoload ]]; then
            output=$(timeout 30 sup crossbar_config autoload_modules </dev/null) || die 'Could not inspect entitlement startup registration'
        else
            output=$(timeout 30 sup crossbar_bindings modules_loaded </dev/null) || die 'Could not inspect entitlement runtime registration'
        fi
        modules=$(kazoo_blackhole_module_output "$kind" "$output") || die 'Invalid Crossbar registration output'
        [[ $'\n'"$modules"$'\n' == *$'\n'cb_entitlements$'\n'* ]] || die "cb_entitlements missing from ${kind}; install kazoo-apps"
    done
}

configure_kazoo_scope_management() {
    local output before_autoload before_running after_autoload after_running module
    [[ $DRY_RUN != true ]] || { log 'Would register admin-guarded scope management with preserving readback'; return 0; }
    monster_registration_available || return 0
    # Monster-only installs also reach registration. Never expose an older,
    # unguarded backend merely because the corrected module name exists.
    output=$(timeout 30 sup cb_scope_restrictions management_guard_version </dev/null) || die 'Install the guarded Kazoo applications backend before enabling scope management'
    [[ $output == 1 ]] || die 'Scope management guard version is not supported'
    output=$(timeout 30 sup crossbar_config autoload_modules </dev/null) || die 'Could not read effective Crossbar modules'
    # Both services use the same bounded native atom/binary-list grammar.
    before_autoload=$(kazoo_blackhole_module_output autoload "$output") || die 'Invalid Crossbar autoload list'
    output=$(timeout 30 sup crossbar_bindings modules_loaded </dev/null) || die 'Could not read running Crossbar modules'
    before_running=$(kazoo_blackhole_module_output running "$output") || die 'Invalid running Crossbar list'
    if [[ $'\n'"$before_autoload"$'\n' == *$'\n'cb_scope_restrictions$'\n'* &&
          $'\n'"$before_running"$'\n' == *$'\n'cb_scope_restrictions$'\n'* ]]; then
        log 'PASS guarded scope management already running and effective'
        return 0
    fi
    output=$(timeout 30 sup crossbar_maintenance start_module cb_scope_restrictions </dev/null) || die 'Could not register guarded scope management'
    [[ $output != *'failed to start'* ]] || die 'Scope management failed to start'
    output=$(timeout 30 sup crossbar_config autoload_modules </dev/null) || die 'Could not verify Crossbar autoload modules'
    after_autoload=$(kazoo_blackhole_module_output autoload "$output") || die 'Invalid Crossbar autoload readback'
    output=$(timeout 30 sup crossbar_bindings modules_loaded </dev/null) || die 'Could not verify running Crossbar modules'
    after_running=$(kazoo_blackhole_module_output running "$output") || die 'Invalid running Crossbar readback'
    [[ $'\n'"$after_autoload"$'\n' == *$'\n'cb_scope_restrictions$'\n'* &&
       $'\n'"$after_running"$'\n' == *$'\n'cb_scope_restrictions$'\n'* ]] || die 'Guarded scope management is not running/effective; inspect node overrides'
    while IFS= read -r module; do
        [[ -z $module || $'\n'"$after_autoload"$'\n' == *$'\n'"$module"$'\n'* ]] || die 'Scope registration lost an existing autoload module'
    done <<<"$before_autoload"
    while IFS= read -r module; do
        [[ -z $module || $'\n'"$after_running"$'\n' == *$'\n'"$module"$'\n'* ]] || die 'Scope registration lost a running module'
    done <<<"$before_running"
    log 'PASS guarded scope management running/effective; existing modules preserved'
}

verify_kazoo_scope_management() {
    local output kind modules
    [[ $DRY_RUN != true ]] || return 0
    monster_registration_available || return 0
    output=$(timeout 30 sup cb_scope_restrictions management_guard_version </dev/null) || die 'Scope management guard is unavailable'
    [[ $output == 1 ]] || die 'Scope management guard version is not supported'
    for kind in autoload running; do
        if [[ $kind == autoload ]]; then
            output=$(timeout 30 sup crossbar_config autoload_modules </dev/null) || die 'Could not verify Crossbar autoload modules'
        else
            output=$(timeout 30 sup crossbar_bindings modules_loaded </dev/null) || die 'Could not verify running Crossbar modules'
        fi
        modules=$(kazoo_blackhole_module_output "$kind" "$output") || die 'Invalid Crossbar module verification output'
        [[ $'\n'"$modules"$'\n' == *$'\n'cb_scope_restrictions$'\n'* ]] || die "Scope management missing from ${kind}; install kazoo-apps"
    done
    log 'PASS guarded scope management registration (read-only)'
}

kazoo_queue_live_selected() {
    local app
    for app in acdc blackhole crossbar; do
        [[ ",${KAZOO_APPS_LIST}," == *",${app},"* ]] || return 1
    done
}

# Parse only the bounded native SUP list/maintenance formats, never evaluate
# Erlang text. A substring match would accept bh_queue_live_other as ready.
kazoo_blackhole_module_output() {
    node - "$1" "$2" <<'NODE'
'use strict';
const [kind, raw] = process.argv.slice(2);
function reject() { process.stderr.write('Invalid Blackhole module readback\n'); process.exit(1); }
if (typeof raw !== 'string' || Buffer.byteLength(raw) > 65536) reject();
if (kind === 'start') {
    const lines = raw.trim().split(/\r?\n/).map(line => line.trim());
    if (lines.shift() !== 'starting bh_queue_live:' || lines.pop() !== 'ok') reject();
    let groups = 0, fields;
    for (const line of lines) {
        if (/^node [^\s\x00-\x1f]{1,256} returned:$/.test(line)) {
            if (fields && fields.size !== 2) reject();
            if (++groups > 1024) reject();
            fields = new Set();
        } else {
            const match = /^(Persisted|Started): true$/.exec(line);
            if (!fields || !match || fields.has(match[1])) reject();
            fields.add(match[1]);
        }
    }
    if (!groups || fields.size !== 2) reject();
    process.exit(0);
}
if (kind !== 'running' && kind !== 'autoload') reject();
let text = raw.trim(), names = [];
if (!text.startsWith('[') || !text.endsWith(']')) reject();
text = text.slice(1, -1).trim();
const item = kind === 'autoload' ? /^<<"([A-Za-z0-9_@.-]{1,128})">>/ :
    /^(?:([a-z][A-Za-z0-9_@]{0,127})|'([A-Za-z0-9_@.-]{1,128})')/;
while (text) {
    const match = item.exec(text);
    if (!match || names.length >= 1024) reject();
    names.push(match[1] || match[2]);
    text = text.slice(match[0].length).trim();
    if (!text) break;
    if (text[0] !== ',' || !text.slice(1).trim()) reject();
    text = text.slice(1).trim();
}
// Duplicate configured entries are preserved by the native migration, but
// membership verification only needs their distinct names.
process.stdout.write([...new Set(names)].sort().join('\n'));
NODE
}

configure_kazoo_queue_live_module() {
    local before_autoload before_running after_autoload after_running output module
    kazoo_queue_live_selected || return 0
    if [[ $DRY_RUN == true ]]; then
        log 'Would ensure bh_queue_live with native preserving autoload migration and exact readback'
        return 0
    fi
    if ! monster_registration_available; then
        log 'No local Kazoo applications authority; queue-live Blackhole configuration is delegated'
        return 0
    fi
    verify_erlang_applications kazoo_apps acdc,blackhole,crossbar || die 'Required local queue-live applications are not active'
    output=$(timeout 30 sup blackhole_config autoload_modules </dev/null) || die 'Could not read effective Blackhole autoload modules'
    before_autoload=$(kazoo_blackhole_module_output autoload "$output") || die 'Invalid effective Blackhole autoload list'
    # The maintenance alias returns this same list, but SUP deliberately exits
    # 2 for non-ok maintenance results. Use the non-maintenance read API.
    output=$(timeout 30 sup blackhole_bindings modules_loaded </dev/null) || die 'Could not read running Blackhole modules'
    before_running=$(kazoo_blackhole_module_output running "$output") || die 'Invalid running Blackhole module list'
    if [[ $'\n'"$before_autoload"$'\n' == *$'\n'bh_queue_live$'\n'* &&
          $'\n'"$before_running"$'\n' == *$'\n'bh_queue_live$'\n'* ]]; then
        log 'PASS bh_queue_live already running and present in effective autoload modules'
        return 0
    fi
    # start_module/1 defaults Persist=true and adds to the effective list via
    # the native listener. Never set/replace all modules or erase node overrides.
    output=$(timeout 30 sup blackhole_maintenance start_module bh_queue_live </dev/null) || die 'Could not start/persist bh_queue_live'
    kazoo_blackhole_module_output start "$output" || die 'Blackhole did not confirm every start/persist response'
    output=$(timeout 30 sup blackhole_config autoload_modules </dev/null) || die 'Could not verify effective Blackhole autoload modules'
    after_autoload=$(kazoo_blackhole_module_output autoload "$output") || die 'Invalid effective Blackhole autoload readback'
    output=$(timeout 30 sup blackhole_bindings modules_loaded </dev/null) || die 'Could not verify running Blackhole modules'
    after_running=$(kazoo_blackhole_module_output running "$output") || die 'Invalid running Blackhole readback'
    [[ $'\n'"$after_autoload"$'\n' == *$'\n'bh_queue_live$'\n'* &&
       $'\n'"$after_running"$'\n' == *$'\n'bh_queue_live$'\n'* ]] || die 'bh_queue_live is not running/effective; a node override may mask persistence'
    while IFS= read -r module; do
        [[ -z $module || $'\n'"$after_autoload"$'\n' == *$'\n'"$module"$'\n'* ]] || die 'Blackhole migration did not preserve an existing effective autoload module'
    done <<<"$before_autoload"
    while IFS= read -r module; do
        [[ -z $module || $'\n'"$after_running"$'\n' == *$'\n'"$module"$'\n'* ]] || die 'Blackhole migration lost a running module'
    done <<<"$before_running"
    log 'PASS bh_queue_live running and effective; existing Blackhole modules preserved'
}

verify_kazoo_queue_live_module() {
    local kind output modules
    kazoo_queue_live_selected || return 0
    [[ $DRY_RUN != true ]] || return 0
    monster_registration_available || return 0
    for kind in autoload running; do
        if [[ $kind == autoload ]]; then
            output=$(timeout 30 sup blackhole_config autoload_modules </dev/null) || die 'Could not verify Blackhole autoload modules'
        else
            output=$(timeout 30 sup blackhole_bindings modules_loaded </dev/null) || die 'Could not verify running Blackhole modules'
        fi
        modules=$(kazoo_blackhole_module_output "$kind" "$output") || die 'Invalid Blackhole module verification output'
        [[ $'\n'"$modules"$'\n' == *$'\n'bh_queue_live$'\n'* ]] || die "bh_queue_live missing from ${kind} modules; install kazoo-apps to migrate safely"
    done
    log 'PASS bh_queue_live running and effective autoload membership (read-only)'
}

verify_acdc_interfaces() {
    local modules module credential_hash auth_body token account_id endpoint result
    verify_kazoo_scope_management
    verify_kazoo_entitlements_module
    verify_kazoo_storage_module
    modules=$(timeout 30 sup crossbar_bindings modules_loaded </dev/null) || \
        die 'Could not inspect Crossbar module registrations'
    for module in cb_queues cb_agents cb_acdc_call_stats cb_external_numbers cb_members cb_entitlements; do
        [[ $modules == *"$module"* ]] || die "Kazoo Crossbar module ${module} is not registered"
    done
    verify_kazoo_queue_live_module
    if [[ -z $KAZOO_MASTER_ADMIN_PASSWORD && ! -r $KAZOO_INSTALLER_SECRETS ]]; then
        log 'PASS ACDC API registrations; authenticated API probe requires existing master credentials'
        return 0
    fi
    load_or_create_master_credentials
    credential_hash=$(printf '%s:%s' "$KAZOO_MASTER_ADMIN_USER" "$KAZOO_MASTER_ADMIN_PASSWORD" | md5sum | cut -d' ' -f1)
    auth_body=$(printf '{"data":{"credentials":"%s","method":"md5","realm":"%s"}}' \
        "$credential_hash" "$KAZOO_MASTER_ACCOUNT_REALM" | curl --fail --silent --show-error \
        --connect-timeout 5 --max-time 30 -X PUT -H 'Content-Type: application/json' \
        --data-binary @- http://127.0.0.1:8000/v2/user_auth) || die 'Crossbar master login failed'
    token=$(jq -er '.auth_token | select(type == "string" and length > 0)' <<<"$auth_body") || \
        die 'Crossbar master login did not return an authentication token'
    account_id=$(jq -er '.data.account_id' <<<"$auth_body") || die 'Crossbar master login did not return an account ID'
    [[ $token =~ ^[a-zA-Z0-9._-]+$ && $account_id =~ ^[a-zA-Z0-9_-]+$ ]] || \
        die 'Crossbar returned invalid authentication identifiers'
    for endpoint in queues agents external_numbers entitlements; do
        result=$(printf 'header = "X-Auth-Token: %s"\n' "$token" | \
            curl --config - --fail --silent --show-error --connect-timeout 5 --max-time 30 \
            "http://127.0.0.1:8000/v2/accounts/${account_id}/${endpoint}") || \
            die "Kazoo authenticated ${endpoint} API failed"
        if [[ $endpoint == entitlements ]]; then
            jq -e '.status == "success" and (.data.capabilities | type == "object") and (.data.enrollments | type == "object")' <<<"$result" >/dev/null || \
                die 'Kazoo entitlement API did not return capabilities and enrollments'
        else
            jq -e '.status == "success" and (.data | type == "array")' <<<"$result" >/dev/null || \
                die "Kazoo ${endpoint} API did not return a successful collection"
        fi
    done
    # Account /storage can legitimately be absent. The administrator's native
    # plan collection proves the module works without inventing an empty plan.
    result=$(printf 'header = "X-Auth-Token: %s"\n' "$token" | \
        curl --config - --fail --silent --show-error --connect-timeout 5 --max-time 30 \
        'http://127.0.0.1:8000/v2/storage/plans') || die 'Kazoo native storage-plan collection failed'
    jq -e '.status == "success" and (.data | type == "array")' <<<"$result" >/dev/null || \
        die 'Kazoo storage-plan API did not return a successful collection'
    log 'PASS Crossbar administrator login, ACDC APIs, and Monster UI external-number/entitlement/storage-plan APIs'
}

install_ecallmgr() {
    log 'Installing Kazoo ecallmgr'
    if [[ ${KAZOO_BUILD_SUCCEEDED_THIS_RUN:-false} != true ]]; then
        build_kazoo
    fi
    verify_kazoo_current_build
    configure_kazoo
    install_kazoo_systemd_units ecallmgr
    install_sup_cli
    service_enable_restart kazoo-ecallmgr.service
    if [[ $DRY_RUN != true ]]; then
        wait_kazoo_datastore_ready ecallmgr
        configure_ecallmgr_dialplan_applications
        configure_ecallmgr_callback_cleanup
        configure_ecallmgr_event_stream_framing
        configure_ecallmgr_sbc_discovery
        register_configured_freeswitch_nodes
        verify_ecallmgr
    fi
}

verify_erlang_node() {
    local service=$1
    local node_prefix=$2
    local distribution_port listener
    assert_service "$service"
    distribution_port=$(epmd -names 2>/dev/null | \
        awk -v node="$node_prefix" '$1 == "name" && $2 == node && $3 == "at" && $4 == "port" {print $5; exit}')
    [[ $distribution_port =~ ^[1-9][0-9]*$ ]] || \
        die "EPMD does not list ${node_prefix}"
    listener=$(ss -H -ltn "sport = :${distribution_port}" 2>/dev/null || true)
    grep -F "${KAZOO_ERLANG_DIST_IP}:${distribution_port}" <<<"$listener" >/dev/null || \
        die "${node_prefix} does not listen on configured Erlang distribution address ${KAZOO_ERLANG_DIST_IP}:${distribution_port}"
    log "PASS EPMD node registered: ${node_prefix} on ${KAZOO_ERLANG_DIST_IP}:${distribution_port}"
}

wait_kazoo_datastore_ready() {
    local node_prefix=${1:-} erl_call_bin output rpc deadline remaining rpc_timeout
    case $node_prefix in
        kazoo_apps|ecallmgr) ;;
        *) die 'Unsupported Kazoo datastore readiness node'; return 1 ;;
    esac
    [[ ${KAZOO_HOSTNAME:-} =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ && ${#KAZOO_HOSTNAME} -le 253 ]] || \
        { die 'Invalid Kazoo hostname for datastore readiness'; return 1; }
    case ${KAZOO_NODE_NAME_TYPE:-} in
        -name|-sname) ;;
        *) die 'Invalid Erlang naming mode for datastore readiness'; return 1 ;;
    esac
    [[ ${KAZOO_START_TIMEOUT:-} =~ ^[1-9][0-9]{0,8}$ ]] || \
        { die 'Invalid Kazoo datastore readiness timeout'; return 1; }
    if [[ $DRY_RUN == true ]]; then
        log "Would wait for read-only local datastore readiness on ${node_prefix}"
        return 0
    fi
    verify_cookie_copy "$KAZOO_RUNTIME_COOKIE_FILE" kazoo
    erl_call_bin=$(find_erl_call) || { die 'erl_call was not installed with Erlang'; return 1; }
    # get_server can return the result of logging (ok) while its ETS table is
    # absent. Accept only a real driver/server pair and a successful read-only
    # server_info response. Never return connection records or exception text.
    rpc='try case kz_dataconnections:get_server(<<"local">>) of {Driver, Server} when is_atom(Driver) -> case Driver:server_info(Server) of {ok, _} -> ready; _ -> not_ready end; _ -> not_ready end catch _:_ -> not_ready end.'
    deadline=$((SECONDS + KAZOO_START_TIMEOUT))
    while ((SECONDS < deadline)); do
        remaining=$((deadline - SECONDS))
        ((remaining > 0)) || break
        rpc_timeout=$remaining
        ((rpc_timeout <= 10)) || rpc_timeout=10
        if output=$(printf '%s\n' "$rpc" | timeout --signal=KILL "$rpc_timeout" \
            runuser --user kazoo -- "$erl_call_bin" \
            "$KAZOO_NODE_NAME_TYPE" "${node_prefix}@${KAZOO_HOSTNAME}" -e 2>/dev/null); then
            if [[ $output == '{ok, ready}' && $SECONDS -lt $deadline ]]; then
                log "PASS read-only local datastore ready on ${node_prefix}"
                return 0
            fi
        fi
        remaining=$((deadline - SECONDS))
        ((remaining > 0)) || break
        if ((remaining > 2)); then sleep 2; else sleep "$remaining"; fi
    done
    die "Kazoo local datastore did not become ready on ${node_prefix}; no startup configuration was attempted"
    return 1
}

find_erl_call() {
    local candidate
    for candidate in /usr/lib64/erlang/erts-*/bin/erl_call \
        /usr/lib64/erlang/bin/erl_call /usr/bin/erl_call; do
        if [[ -x $candidate ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

verify_erlang_applications() {
    local node_prefix=$1
    local expected_apps=$2
    local fqdn erl_call_bin output app deadline all_running
    # CLI preflight initializes both derived values. Sourced maintenance calls
    # must do the same: an empty erl_call name-mode would otherwise be retried
    # until the full readiness deadline, hiding an invocation/configuration bug.
    if [[ -z ${KAZOO_HOSTNAME:-} ]]; then
        die 'Kazoo hostname is not initialized; run installer preflight or explicitly set KAZOO_HOSTNAME before sourced verification'
        return 1
    fi
    case ${KAZOO_NODE_NAME_TYPE:-} in
        -name|-sname) ;;
        *)
            die 'Kazoo Erlang naming mode is not initialized: KAZOO_NODE_NAME_TYPE must be exactly -name or -sname before verification'
            return 1 ;;
    esac
    fqdn=$KAZOO_HOSTNAME
    verify_cookie_copy "$KAZOO_RUNTIME_COOKIE_FILE" kazoo
    erl_call_bin=$(find_erl_call) || die 'erl_call was not installed with Erlang'
    deadline=$((SECONDS + KAZOO_START_TIMEOUT))
    while ((SECONDS < deadline)); do
        output=$(timeout 10 runuser --user kazoo -- "$erl_call_bin" \
            "$KAZOO_NODE_NAME_TYPE" "${node_prefix}@${fqdn}" \
            -a 'application which_applications' 2>/dev/null || true)
        all_running=true
        for app in ${expected_apps//,/ }; do
            if [[ $output != *"{${app},"* ]]; then
                all_running=false
                break
            fi
        done
        if [[ $all_running == true ]]; then
            verify_erlang_logging "$node_prefix" "$erl_call_bin"
            log "PASS Erlang applications running on ${node_prefix}: ${expected_apps}"
            return 0
        fi
        sleep 2
    done
    die "Erlang applications did not become ready on ${node_prefix}: ${expected_apps}"
}

verify_acdc_stats_ready() {
    if [[ $DRY_RUN == true ]]; then
        log 'Would require migrated ACDC stats tables and native broker consumption'
        return 0
    fi
    local erl_call_bin output deadline
    verify_cookie_copy "$KAZOO_RUNTIME_COOKIE_FILE" kazoo
    erl_call_bin=$(find_erl_call) || die 'erl_call was not installed with Erlang'
    deadline=$((SECONDS + KAZOO_START_TIMEOUT))
    while ((SECONDS < deadline)); do
        if output=$(timeout 10 runuser --user kazoo -- "$erl_call_bin" \
            "$KAZOO_NODE_NAME_TYPE" "kazoo_apps@${KAZOO_HOSTNAME}" \
            -a 'acdc_maintenance stats_ready []' 2>/dev/null); then
            if [[ $output == ready ]]; then
                log 'PASS ACDC retained stats migrated and native listener consuming'
                return 0
            fi
        fi
        sleep 2
    done
    die 'ACDC stats did not confirm migrated tables and broker consumption; retain tables and inspect startup readiness'
}

verify_erlang_logging() {
    local node_prefix=$1 erl_call_bin=$2 output
    local expected_root="/var/log/kazoo/$node_prefix"
    output=$(timeout 10 runuser --user kazoo -- "$erl_call_bin" \
        "$KAZOO_NODE_NAME_TYPE" "${node_prefix}@${KAZOO_HOSTNAME}" \
        -a 'application get_env [lager,log_root]') || die "Could not inspect ${node_prefix} log configuration"
    [[ $output == "{ok, \"${expected_root}\"}" ]] || \
        die "${node_prefix} must use its own Lager root ${expected_root}; reinstall/restart the node"
    [[ -d $expected_root/log && $(stat -c '%U:%G:%a' "$expected_root/log") == kazoo:kazoo:750 ]] || \
        die "${node_prefix} log directory must be kazoo:kazoo mode 0750"
    log "PASS isolated ${node_prefix} log root: ${expected_root}"
}

verify_kazoo_pivot_port_reservation() {
    local service=$1 property dependencies
    [[ $service == kazoo-apps.service || $service == kazoo-ecallmgr.service ]] || \
        die 'Unexpected Kazoo node for Pivot reservation verification'
    [[ $DRY_RUN != true ]] || return 0
    python3 -B -I "$SCRIPT_DIR/reserve-kazoo-pivot-ports.py" --check >/dev/null || \
        die 'Pivot listener ports are not protected against ephemeral assignment'
    systemctl is-active --quiet kazoo-pivot-port-reservation.service || \
        die 'The boot-time Pivot port reservation service is not active'
    for property in Requires After; do
        dependencies=$(systemctl show "$service" --property="$property" --value) || \
            die "Cannot read ${service} effective ${property} dependencies"
        [[ " $dependencies " == *' kazoo-pivot-port-reservation.service '* ]] || \
            die "${service} lacks its effective ${property} Pivot reservation dependency"
    done
    log "PASS reserved Pivot ports and effective boot dependencies: ${service}"
}

verify_kazoo_apps() {
    if [[ $DRY_RUN == true ]]; then log 'Would verify Kazoo apps'; return 0; fi
    local api_result api_body api_status deadline
    verify_kazoo_pivot_port_reservation kazoo-apps.service
    verify_kazoo_production_beams
    verify_erlang_node kazoo-apps.service kazoo_apps
    verify_erlang_applications kazoo_apps "$KAZOO_APPS_LIST"
    verify_acdc_stats_ready
    deadline=$((SECONDS + KAZOO_START_TIMEOUT))
    while ((SECONDS < deadline)); do
        api_result=$(curl --connect-timeout 5 --max-time 15 --silent --show-error \
            --write-out $'\n%{http_code}' http://127.0.0.1:8000/v2/ 2>/dev/null || true)
        api_status=${api_result##*$'\n'}
        api_body=${api_result%$'\n'*}
        if [[ $api_status =~ ^[234][0-9][0-9]$ ]] && jq -e . <<<"$api_body" >/dev/null 2>&1; then
            log "PASS Crossbar API JSON check on 127.0.0.1:8000 (HTTP ${api_status})"
            break
        fi
        sleep 2
    done
    if [[ ! $api_status =~ ^[234][0-9][0-9]$ ]] || ! jq -e . <<<"$api_body" >/dev/null 2>&1; then
        die 'Crossbar API did not return JSON on http://127.0.0.1:8000/v2/'
    fi
    couchdb_curl --fail --silent --show-error --connect-timeout 5 --max-time 30 \
        "http://${KAZOO_COUCHDB_HOST}:${KAZOO_COUCHDB_PORT}/acdc" | \
        jq -e '.db_name == "acdc"' >/dev/null || die 'ACDC CouchDB database is not ready'
    log 'PASS ACDC database is ready'
    if [[ $KAZOO_BOOTSTRAP_MASTER_ACCOUNT == true ]]; then
        configured_master_account_id >/dev/null || die 'Kazoo master account is not ready'
        log 'PASS Kazoo master account is ready'
    fi
    verify_sup_cli
    verify_acdc_interfaces
    verify_kazoo_prompts
    verify_call_forward_confirmation_pack
    verify_acdc_language_packs
    finalize_acdc_prerecorded_capabilities --check
}

verify_sup_beam_export() {
    local module=$1 function=$2 arity=$3 resolved expected root_real location
    case "$module:$function:$arity" in
        kazoo_maintenance:syslog_level:1|kapps_controller:start_app:1) ;;
        *) die 'Unexpected SUP command export check' ;;
    esac
    # code:which reports available code without loading the target module.
    # Read exports from the exact local runtime BEAM, not function_exported/3,
    # which returns false for perfectly available but not-yet-loaded modules.
    location=$(timeout --signal=KILL 30 sup -e code which "$module" </dev/null) || \
        die "SUP could not locate ${module}"
    [[ $location == \"/*\" ]] || die "SUP ${module} is not available as a runtime BEAM"
    location=${location#\"}; location=${location%\"}
    [[ $location =~ ^/[-a-zA-Z0-9_./]+$ ]] || die "SUP ${module} returned an unsafe code path"
    root_real=$(readlink -f -- "$KAZOO_ROOT") || die 'Cannot resolve the configured Kazoo runtime root'
    expected="$root_real/core/kazoo_apps/ebin/$module.beam"
    resolved=$(readlink -f -- "$location") || die "Cannot resolve SUP ${module} code path"
    [[ $resolved == "$expected" && -f $expected && $(readlink -f -- "$expected") == "$expected" ]] || \
        die "SUP ${module} does not resolve to its configured runtime BEAM"
    KAZOO_VERIFY_BEAM_FILE=$expected KAZOO_VERIFY_BEAM_MODULE=$module \
        KAZOO_VERIFY_BEAM_FUNCTION=$function KAZOO_VERIFY_BEAM_ARITY=$arity \
        erl +S 1:1 +A 1 -noshell -eval '
File = os:getenv("KAZOO_VERIFY_BEAM_FILE"),
WantedModule = os:getenv("KAZOO_VERIFY_BEAM_MODULE"),
WantedFunction = os:getenv("KAZOO_VERIFY_BEAM_FUNCTION"),
WantedArity = list_to_integer(os:getenv("KAZOO_VERIFY_BEAM_ARITY")),
case beam_lib:chunks(File, [exports]) of
    {ok, {Module, [{exports, Exports}]}} ->
        case atom_to_list(Module) =:= WantedModule andalso
             lists:any(fun({Function, Arity}) -> atom_to_list(Function) =:= WantedFunction
                          andalso Arity =:= WantedArity end, Exports) of
            true -> halt(0);
            false -> halt(1)
        end;
    _ -> halt(1)
end.
' || die "SUP ${module}:${function}/${arity} is unavailable in its runtime BEAM"
}

verify_sup_cli() {
    local configured_apps running_apps
    command -v sup >/dev/null || die 'The SUP command is not installed in PATH'
    [[ -s /etc/bash_completion.d/sup ]] || die 'SUP Bash completion is not installed'
    running_apps=$(timeout --signal=KILL 60 sup kapps_controller running_apps </dev/null) || \
        die 'SUP could not call kapps_controller:running_apps/0'
    [[ $running_apps == *acdc* ]] || die 'SUP running_apps result does not include ACDC'
    configured_apps=$(timeout --signal=KILL 60 sup kapps_config get kapps_controller kapps </dev/null) || \
        die 'SUP could not read the kapps_controller application configuration'
    [[ $configured_apps == *acdc* ]] || \
        die 'SUP kapps_controller configuration does not include ACDC'
    verify_sup_beam_export kazoo_maintenance syslog_level 1
    verify_sup_beam_export kapps_controller start_app 1
    log "PASS SUP controller/config command checks (configured kapps: ${configured_apps})"
}

configure_ecallmgr_sbc_discovery() {
    local output current
    [[ $DRY_RUN != true ]] || return 0
    # Standalone Kamailio advertises exact Proxy listener addresses on the
    # authenticated zone broker. Native discovery persists these authoritative
    # ACL entries and reloads media ACLs, including SBCs installed later.
    output=$(timeout --signal=KILL 30 sup -n ecallmgr -e kapps_config set_default \
        '<<"ecallmgr">>' '<<"enable_discovery_server">>' true </dev/null 2>/dev/null) ||
        die 'Could not persist eCallMgr SBC discovery'
    [[ $output == \{ok,* ]] || die 'eCallMgr rejected SBC discovery configuration'
    current=$(timeout --signal=KILL 30 sup -n ecallmgr -e erlang whereis \
        ecallmgr_discovery </dev/null 2>/dev/null) || die 'Could not inspect SBC discovery'
    if [[ $current == undefined ]]; then
        output=$(timeout --signal=KILL 30 sup -n ecallmgr -e supervisor restart_child \
            ecallmgr_auxiliary_sup ecallmgr_discovery </dev/null 2>/dev/null) ||
            die 'Could not start supervised SBC discovery'
        [[ $output == '{ok,<'* ]] || die 'Supervised SBC discovery did not start'
    fi
    verify_ecallmgr_sbc_discovery
}

verify_ecallmgr_sbc_discovery() {
    local configured current
    [[ $DRY_RUN != true ]] || return 0
    configured=$(timeout --signal=KILL 30 sup -n ecallmgr -e kz_app_config is_true \
        '<<"ecallmgr">>' '<<"enable_discovery_server">>' </dev/null 2>/dev/null) ||
        die 'Could not read effective SBC discovery configuration'
    [[ $configured == true ]] || die 'Effective SBC discovery is disabled'
    current=$(timeout --signal=KILL 30 sup -n ecallmgr -e erlang whereis \
        ecallmgr_discovery </dev/null 2>/dev/null) || die 'Could not inspect SBC discovery process'
    [[ $current =~ ^\<[0-9]+\.[0-9]+\.[0-9]+\>$ ]] || die 'SBC discovery process is not running'
    log 'PASS supervised eCallMgr discovery for authenticated zone SBC advertisements'
}

configure_ecallmgr_dialplan_applications() {
    local application output
    if [[ $DRY_RUN == true ]]; then
        log 'Would configure supported FreeSWITCH dialplan application compatibility settings'
        return 0
    fi
    for application in event intercept; do
        output=$(timeout --signal=KILL 30 sup -n ecallmgr -e kapps_config set_default \
            '<<"ecallmgr">>' "[<<\"dialplan\">>,<<\"apps\">>,<<\"${application}\">>]" \
            "<<\"${application}\">>" </dev/null) || \
            die "Could not configure the eCallMgr FreeSWITCH ${application} application"
        [[ $output == \{ok,* ]] || \
            die "eCallMgr rejected the FreeSWITCH ${application} application compatibility setting"
    done
}

verify_ecallmgr_dialplan_applications() {
    local application configured
    [[ $DRY_RUN != true ]] || return 0
    for application in event intercept; do
        configured=$(timeout --signal=KILL 30 sup -n ecallmgr -e kapps_config get \
            '<<"ecallmgr">>' "[<<\"dialplan\">>,<<\"apps\">>,<<\"${application}\">>]" \
            </dev/null) || die "Could not read the eCallMgr FreeSWITCH ${application} application setting"
        [[ $configured == "<<\"${application}\">>" ]] || \
            die "eCallMgr is not configured to use the supported FreeSWITCH ${application} application"
    done
    log 'PASS eCallMgr uses supported FreeSWITCH event and intercept applications'
}

configure_ecallmgr_callback_cleanup() {
    local output
    if [[ $DRY_RUN == true ]]; then
        log 'Would permit only ACDC exact-node hangup for callback recovery'
        return 0
    fi
    output=$(timeout --signal=KILL 30 sup -n ecallmgr -e kapps_config set_default \
        '<<"ecallmgr">>' '[<<"node_call_command_allowed_applications">>,<<"acdc">>,<<"hangup">>]' \
        true </dev/null) || die 'Could not configure the ACDC callback cleanup permission'
    [[ $output == \{ok,* ]] || die 'eCallMgr rejected the ACDC callback cleanup permission'
    verify_ecallmgr_callback_cleanup
}

verify_ecallmgr_callback_cleanup() {
    local configured
    [[ $DRY_RUN != true ]] || return 0
    configured=$(timeout --signal=KILL 30 sup -n ecallmgr -e kz_app_config is_true \
        '<<"ecallmgr">>' '[<<"node_call_command_allowed_applications">>,<<"acdc">>,<<"hangup">>]' \
        </dev/null) || die 'Could not inspect the effective ACDC callback cleanup permission'
    [[ $configured == true ]] || die 'ACDC exact-node callback hangup is not permitted by eCallMgr'
    log 'PASS eCallMgr permits ACDC exact-node callback hangup'
}

configure_ecallmgr_event_stream_framing() {
    local configured output
    if [[ $DRY_RUN == true ]]; then
        log 'Would configure four-byte eCallMgr/FreeSWITCH event-stream framing'
        return 0
    fi
    configured=$(timeout --signal=KILL 30 sup -n ecallmgr -e kapps_config get \
        '<<"ecallmgr">>' '<<"tcp_packet_type">>' </dev/null) || \
        die 'Could not read the eCallMgr event-stream packet setting'
    if [[ $configured == 4 ]]; then
        return 0
    fi
    output=$(timeout --signal=KILL 30 sup -n ecallmgr -e kapps_config set_default \
        '<<"ecallmgr">>' '<<"tcp_packet_type">>' 4 </dev/null) || \
        die 'Could not configure four-byte eCallMgr event-stream framing'
    [[ $output == \{ok,* ]] || \
        die 'eCallMgr rejected four-byte event-stream framing'
    configured=$(timeout --signal=KILL 30 sup -n ecallmgr -e kapps_config get \
        '<<"ecallmgr">>' '<<"tcp_packet_type">>' </dev/null) || \
        die 'Could not confirm four-byte eCallMgr event-stream framing'
    [[ $configured == 4 ]] || die 'eCallMgr did not persist four-byte event-stream framing'
    log 'Restarting eCallMgr once to activate four-byte event-stream sockets'
    service_enable_restart kazoo-ecallmgr.service
    sleep 5
}

verify_ecallmgr_event_stream_framing() {
    local configured deadline node runtime
    [[ $DRY_RUN != true ]] || return 0
    configured=$(timeout --signal=KILL 30 sup -n ecallmgr -e kapps_config get \
        '<<"ecallmgr">>' '<<"tcp_packet_type">>' </dev/null) || \
        die 'Could not read the eCallMgr event-stream packet setting'
    [[ $configured == 4 ]] || die 'eCallMgr event-stream framing is not configured for four-byte frames'
    for node in $(freeswitch_nodes_to_manage); do
        [[ $node == *@* ]] || node="freeswitch@${node}"
        deadline=$((SECONDS + KAZOO_START_TIMEOUT))
        runtime=''
        while ((SECONDS < deadline)); do
            runtime=$(timeout --signal=KILL 30 sup -n ecallmgr -e freeswitch \
                event_stream_framing "'${node}'" </dev/null 2>/dev/null || true)
            [[ $runtime == \{ok,4\} ]] && break
            sleep 2
        done
        [[ $runtime == \{ok,4\} ]] || \
            die "eCallMgr and FreeSWITCH node ${node} did not negotiate four-byte event-stream framing"
    done
    log 'PASS eCallMgr and configured FreeSWITCH nodes use four-byte event-stream framing'
}

verify_ecallmgr_atomic_media() {
    if [[ $DRY_RUN == true ]]; then
        log 'Would verify native kz_intercept on every configured FreeSWITCH node through eCallMgr; no call or native admission change'
        return 0
    fi
    local script="$SCRIPT_DIR/verify-ecallmgr-atomic-media.erl" raw node output parent owner mode
    local -a nodes=()
    local -A seen=()
    # A runtime file:script read must use the exact protected checked-in file.
    [[ $script =~ ^/[a-zA-Z0-9_./-]+$ && -f $script && ! -L $script && $(realpath -e -- "$script") == "$script" &&
       $(stat -c '%u:%a:%h' -- "$script") == 0:644:1 ]] ||
        die 'Atomic media verification script is missing, linked or unprotected'
    parent=$(dirname -- "$script")
    while :; do
        [[ -d $parent && ! -L $parent ]] || die 'Atomic media verifier ancestor is unsafe'
        read -r owner mode < <(stat -c '%u %a' -- "$parent")
        [[ $owner == 0 && $mode =~ ^[0-7]+$ && $((8#$mode & 022)) == 0 &&
           $((8#$mode & 001)) != 0 ]] || die 'Atomic media verifier ancestor is not protected and traversable'
        [[ $parent != / ]] || break
        parent=$(dirname -- "$parent")
    done
    raw=$(freeswitch_nodes_to_manage) || die 'Cannot resolve configured FreeSWITCH nodes'
    [[ ${#raw} -le 32768 ]] || die 'Configured FreeSWITCH inventory is unbounded'
    while IFS= read -r node; do
        [[ -n $node ]] || continue
        [[ $node == *@* ]] || node="freeswitch@${node}"
        [[ ${#node} -le 255 && $node =~ ^[a-zA-Z0-9_.-]+@[a-zA-Z0-9_.-]+$ &&
           ! ${seen[$node]:-} ]] || die 'Invalid or duplicate FreeSWITCH node in atomic media scope'
        seen[$node]=1
        nodes+=("$node")
    done <<<"$raw"
    [[ ${#nodes[@]} -le 128 ]] || die 'Too many FreeSWITCH nodes in atomic media scope'
    if ((${#nodes[@]} == 0)); then
        warn 'No configured FreeSWITCH nodes; atomic media compatibility remains unverified'
        return 0
    fi
    for node in "${nodes[@]}"; do
        output=$(timeout --signal=KILL 20 sup -t 15 -n ecallmgr -e file script \
            "\"$script\"" "[{'MediaNode','$node'}]" </dev/null 2>/dev/null) ||
            die 'Remote atomic media verification failed; upgrade native mod_kazoo before eCallMgr'
        [[ $output == '{ok,ecallmgr_atomic_media_verified}' ]] ||
            die 'Configured FreeSWITCH lacks verified native kz_intercept; upgrade media before eCallMgr'
        log "PASS native kz_intercept/mod_kazoo inventory through eCallMgr: ${node} (no call performed)"
    done
}

verify_ecallmgr() {
    if [[ $DRY_RUN == true ]]; then log 'Would verify eCallMgr'; return 0; fi
    verify_kazoo_pivot_port_reservation kazoo-ecallmgr.service
    verify_kazoo_production_beams
    verify_erlang_node kazoo-ecallmgr.service ecallmgr
    verify_erlang_applications ecallmgr ecallmgr
    verify_kazoo_amqp_ready ecallmgr
    verify_ecallmgr_dialplan_applications
    verify_ecallmgr_callback_cleanup
    verify_ecallmgr_event_stream_framing
    verify_ecallmgr_sbc_discovery
    verify_configured_freeswitch_nodes
    verify_ecallmgr_atomic_media
    if systemctl is-active --quiet kazoo-kamailio.service 2>/dev/null &&
       systemctl is-active --quiet kazoo-freeswitch.service 2>/dev/null; then
        wait_kamailio_dispatcher_ready
    fi
}

verify_kazoo_amqp_ready() {
    local node_prefix=$1 available deadline
    [[ $DRY_RUN != true ]] || return 0
    [[ $node_prefix == ecallmgr || $node_prefix == kazoo_apps ]] || die 'Invalid AMQP readiness node'
    deadline=$((SECONDS + KAZOO_START_TIMEOUT))
    while ((SECONDS < deadline)); do
        available=$(timeout --signal=KILL 15 sup -n "$node_prefix" -e \
            kz_amqp_connections is_available </dev/null 2>/dev/null) || available=false
        if [[ $available == true ]]; then
            log "PASS ${node_prefix} has an available registered AMQP broker"
            return 0
        fi
        sleep 2
    done
    die "${node_prefix} has no available registered AMQP broker"
}

freeswitch_nodes_to_manage() {
    if [[ -n $KAZOO_FREESWITCH_NODES ]]; then
        tr ',' '\n' <<<"$KAZOO_FREESWITCH_NODES" | sed '/^$/d'
    elif systemctl is-active --quiet kazoo-freeswitch.service 2>/dev/null; then
        printf 'freeswitch@%s\n' "$KAZOO_HOSTNAME"
    fi
}

register_configured_freeswitch_nodes() {
    local node output configured deadline
    local ready=false
    local -a nodes=()
    mapfile -t nodes < <(freeswitch_nodes_to_manage)
    ((${#nodes[@]})) || return 0
    if [[ $DRY_RUN == true ]]; then
        for node in "${nodes[@]}"; do
            [[ $node == *@* ]] || node="freeswitch@${node}"
            log "Would register FreeSWITCH node with eCallMgr: ${node}"
        done
        return 0
    fi
    systemctl is-active --quiet kazoo-ecallmgr.service 2>/dev/null || return 0
    command -v sup >/dev/null || die 'SUP is required to register FreeSWITCH with eCallMgr'
    # get_fs_nodes reads saved configuration and can succeed before the media
    # supervisor exists. Do not attempt registration until its app has started.
    verify_erlang_applications ecallmgr ecallmgr
    deadline=$((SECONDS + KAZOO_START_TIMEOUT))
    while ((SECONDS < deadline)); do
        if configured=$(timeout --signal=KILL 30 sup -n ecallmgr \
            ecallmgr_maintenance get_fs_nodes </dev/null 2>/dev/null); then
            ready=true
            break
        fi
        sleep 2
    done
    [[ $ready == true ]] || \
        die 'eCallMgr did not become ready for FreeSWITCH node registration'
    for node in "${nodes[@]}"; do
        [[ $node == *@* ]] || node="freeswitch@${node}"
        if grep -Fx "$node" <<<"$configured" >/dev/null; then
            log "FreeSWITCH node is already configured in eCallMgr: ${node}"
            continue
        fi
        if ! output=$(timeout --signal=KILL 60 sup -n ecallmgr \
            ecallmgr_maintenance add_fs_node "$node" </dev/null 2>&1); then
            [[ $output == *'{error,node_exists}'* ]] || \
                die "Could not register ${node} with eCallMgr; inspect protected eCallMgr logs"
        fi
        # A failed SUP call can include the distribution cookie in its Erlang
        # argument dump. Never print raw success or error output here.
        log "Registered FreeSWITCH node with eCallMgr: ${node}"
        configured+=$'\n'"$node"
    done
}

verify_configured_freeswitch_nodes() {
    local node connected deadline
    [[ $DRY_RUN != true ]] || return 0
    for node in $(freeswitch_nodes_to_manage); do
        [[ $node == *@* ]] || node="freeswitch@${node}"
        deadline=$((SECONDS + KAZOO_START_TIMEOUT))
        while ((SECONDS < deadline)); do
            connected=$(timeout --signal=KILL 30 sup -n ecallmgr \
                ecallmgr_maintenance list_fs_nodes </dev/null 2>/dev/null || true)
            if grep -Fx "$node" <<<"$connected" >/dev/null; then
                log "PASS eCallMgr connected to FreeSWITCH: ${node}"
                break
            fi
            sleep 2
        done
        grep -Fx "$node" <<<"$connected" >/dev/null || \
            die "eCallMgr did not connect to FreeSWITCH node ${node}"
    done
}

build_sofia_sip() {
    local source_dir="$KAZOO_BUILD_ROOT/sofia-sip"
    local marker=/usr/local/share/kazoo5-installer/sofia-sip-ref
    sync_git https://github.com/freeswitch/sofia-sip.git "$source_dir" "$SOFIA_SIP_REF"
    if [[ -r $marker && $(<"$marker") == "$SOFIA_SIP_REF" ]] && \
       PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:${PKG_CONFIG_PATH:-} \
        pkg-config --exists sofia-sip-ua 2>/dev/null; then
        return 0
    fi
    if [[ $DRY_RUN == true ]]; then
        log "Would build Sofia-SIP at ${SOFIA_SIP_REF}"
        return 0
    fi
    (
        cd "$source_dir"
        ./bootstrap.sh
        ./configure --prefix=/usr/local
        make -j"$KAZOO_MAKE_JOBS"
        make install
    )
    write_file 0644 "$marker" <<<"$SOFIA_SIP_REF"
    run ldconfig
}

build_spandsp() {
    local source_dir="$KAZOO_BUILD_ROOT/spandsp"
    local marker=/usr/local/share/kazoo5-installer/spandsp-ref
    sync_git https://github.com/freeswitch/spandsp.git "$source_dir" "$SPANDSP_REF"
    if [[ -r $marker && $(<"$marker") == "$SPANDSP_REF" ]] && \
       PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:${PKG_CONFIG_PATH:-} \
        pkg-config --exists spandsp 2>/dev/null; then
        return 0
    fi
    if [[ $DRY_RUN == true ]]; then
        log "Would build SpanDSP at ${SPANDSP_REF}"
        return 0
    fi
    (
        cd "$source_dir"
        ./bootstrap.sh
        ./configure --prefix=/usr/local
        make -j"$KAZOO_MAKE_JOBS"
        make install
    )
    write_file 0644 "$marker" <<<"$SPANDSP_REF"
    run ldconfig
}

prepare_mod_kazoo_source() {
    local freeswitch_source=$1
    local module_dir="$freeswitch_source/src/mod/outoftree/mod_kazoo"
    local patch_file
    local -a patch_files=(
        "$SCRIPT_DIR/patches/mod-kazoo-fetch-reply-ownership.patch"
        "$SCRIPT_DIR/patches/mod-kazoo-thread-lifecycle.patch"
        "$SCRIPT_DIR/patches/mod-kazoo-worker-shutdown-synchronization.patch"
        "$SCRIPT_DIR/patches/mod-kazoo-cookie-redaction.patch"
        "$SCRIPT_DIR/patches/mod-kazoo-prefixes-serialization.patch"
        "$SCRIPT_DIR/patches/mod-kazoo-fetch-channel-data.patch"
        "$SCRIPT_DIR/patches/mod-kazoo-fetch-log-redaction.patch"
        "$SCRIPT_DIR/patches/mod-kazoo-originate-compatibility.patch"
        "$SCRIPT_DIR/patches/mod-kazoo-reply-completeness.patch"
        "$SCRIPT_DIR/patches/mod-kazoo-sync-command-protocol.patch"
        "$SCRIPT_DIR/patches/mod-kazoo-originate-reconcile.patch"
        "$SCRIPT_DIR/patches/mod-kazoo-hold-dtmf-events.patch"
        "$SCRIPT_DIR/patches/mod-kazoo-version-namespace.patch"
        "$SCRIPT_DIR/patches/mod-kazoo-atomic-intercept.patch"
    )
    sync_git https://github.com/freeswitch/mod_kazoo.git "$module_dir" "$MOD_KAZOO_REF"
    for patch_file in "${patch_files[@]}"; do
        [[ -f $patch_file ]] || die "Required mod_kazoo patch is missing: ${patch_file}"
        if [[ $DRY_RUN == true ]]; then
            log "Required mod_kazoo integration input: $(basename "$patch_file")"
        fi
    done
    # Later patches modify code introduced by earlier patches. Checking each
    # earlier patch in reverse therefore cannot recognize the combined result.
    # Use reviewed whole-series snapshots and the explicit previous-to-current
    # delta, retaining private preflight and source-change checks.
    apply_kazoo_integration_patch mod_kazoo "$module_dir"
}

freeswitch_build_fingerprint() {
    printf '%s\n' \
        "freeswitch=${FREESWITCH_VERSION}@${FREESWITCH_REF}" \
        "freeswitch_core=module-load-shutdown-v1" \
        "speech_modules=en-es-fr-v1" \
        "mod_sofia=profile-thread-lifecycle-v1+kazoo-proxy-uri-v1" \
        "mod_kazoo=${MOD_KAZOO_REF}+fetch-reply-ownership-v1+thread-lifecycle-v1+worker-shutdown-v3+cookie-redaction-v1+prefixes-serialization-v2+fetch-channel-data-v1+fetch-log-redaction-v1+originate-compatibility-v1+reply-completeness-v1+sync-command-protocol-v1+originate-reconcile-v1+hold-dtmf-events-v1+version-namespace-v1+atomic-intercept-v1" \
        "sofia_sip=${SOFIA_SIP_REF}" \
        "spandsp=${SPANDSP_REF}"
}

prepare_freeswitch_source() {
    local source_dir=$1
    local patch_file
    local -a patch_files=(
        "$SCRIPT_DIR/patches/freeswitch-mod-sofia-thread-lifecycle.patch"
        "$SCRIPT_DIR/patches/freeswitch-mod-sofia-kazoo-proxy-uri.patch"
        "$SCRIPT_DIR/patches/freeswitch-module-load-shutdown.patch"
    )
    for patch_file in "${patch_files[@]}"; do
        [[ -f $patch_file ]] || die "Required FreeSWITCH patch is missing: ${patch_file}"
        if [[ $DRY_RUN == true ]]; then
            log "Would apply required FreeSWITCH patch $(basename "$patch_file")"
        elif git -C "$source_dir" apply --check "$patch_file" 2>/dev/null; then
            git -C "$source_dir" apply "$patch_file"
            log "Applied required FreeSWITCH patch $(basename "$patch_file")"
        elif git -C "$source_dir" apply --reverse --check "$patch_file" 2>/dev/null; then
            log "Required FreeSWITCH patch is already applied: $(basename "$patch_file")"
        else
            die "FreeSWITCH source does not match required patch: ${patch_file}"
        fi
    done
}

install_freeswitch_build_dependencies() {
    # mod_kazoo links the Erlang EI client library. A standalone media host
    # cannot rely on kazoo-apps or RabbitMQ having installed it first.
    dnf_install \
        alsa-lib-devel autoconf automake bzip2-devel cmake curl-devel \
        gcc gcc-c++ git lame-devel libedit-devel libjpeg-turbo-devel libogg-devel \
        libsndfile-devel libtiff-devel libtool libuuid-devel libvorbis-devel \
        libxml2-devel make ncurses-devel openssl-devel opus-devel pcre-devel pcre2-devel \
        pkgconf-pkg-config speex-devel speexdsp-devel sqlite-devel yasm zlib-devel \
        "erlang-${ERLANG_VERSION}"
}

build_kazoo_freeswitch() {
    # A version-specific checkout prevents generated headers and object files
    # from an older FreeSWITCH release being reused after a version upgrade.
    local source_dir="$KAZOO_BUILD_ROOT/freeswitch-${FREESWITCH_VERSION}"
    local marker=/usr/local/share/kazoo5-installer/freeswitch-build
    install_freeswitch_build_dependencies
    build_sofia_sip
    build_spandsp
    sync_git https://github.com/signalwire/freeswitch.git "$source_dir" "$FREESWITCH_REF"
    prepare_freeswitch_source "$source_dir"
    if [[ $DRY_RUN != true && -f $source_dir/src/mod/outoftree/mod_kazoo/Makefile ]]; then
        # The parent distclean does not invalidate this out-of-tree module's
        # configure result. A failed first install may have cached no Erlang.
        make -C "$source_dir/src/mod/outoftree/mod_kazoo" distclean
    fi
    if [[ $DRY_RUN != true && -f $source_dir/Makefile ]]; then
        # A prior configure may have selected different dependency ABIs. A
        # distclean here makes a requested rebuild actually relink the core and
        # modules, while normal idempotent runs skip this function entirely.
        (cd "$source_dir" && make distclean) || true
    fi
    write_file 0644 "$source_dir/modules.conf" <<'EOF'
applications/mod_commands
applications/mod_conference
applications/mod_dptools
applications/mod_expr
applications/mod_http_cache
codecs/mod_opus
applications/mod_spandsp
dialplans/mod_dialplan_xml
endpoints/mod_loopback
endpoints/mod_sofia
event_handlers/mod_event_socket
formats/mod_local_stream
formats/mod_sndfile
formats/mod_tone_stream
loggers/mod_console
loggers/mod_logfile
say/mod_say_en
say/mod_say_es
say/mod_say_fr
mod_kazoo|https://github.com/freeswitch/mod_kazoo.git -b master
EOF
    if [[ $DRY_RUN == true ]]; then
        log "Would build Kazoo FreeSWITCH ${FREESWITCH_VERSION} with mod_kazoo"
        return 0
    fi
    (
        cd "$source_dir"
        ./bootstrap.sh -j
    )
    prepare_mod_kazoo_source "$source_dir"
    (
        cd "$source_dir"
        PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:${PKG_CONFIG_PATH:-} \
            LDFLAGS="-L/usr/local/lib64 -Wl,-rpath,/usr/local/lib64" \
            ./configure --prefix=/usr/local/freeswitch --disable-dependency-tracking
        make -j"$KAZOO_MAKE_JOBS"
        (umask 022; make install)
    )
    freeswitch_build_fingerprint | write_file 0644 "$marker"
    ldconfig
}

configure_freeswitch_logging() {
    # Native rotation avoids copytruncate races and unbounded upstream logs.
    # Keep five 10-MiB archives plus the active file for each profile.
    write_file 0644 "$KAZOO_CONFIG_DIR/freeswitch/autoload_configs/logfile.conf.xml" <<'EOF'
<configuration name="logfile.conf" description="Bounded Kazoo File Logging">
    <settings>
        <param name="rotate-on-hup" value="true"/>
    </settings>
    <profiles>
        <profile name="debug">
            <settings>
                <param name="logfile" value="/var/log/freeswitch/kazoo-debug.log"/>
                <param name="rollover" value="10485760"/>
                <param name="maximum-rotate" value="5"/>
                <param name="uuid" value="true"/>
            </settings>
            <mappings>
                <map name="all" value="info,notice,warning,err,crit,alert"/>
            </mappings>
        </profile>
        <profile name="error">
            <settings>
                <param name="logfile" value="/var/log/freeswitch/kazoo-error.log"/>
                <param name="rollover" value="10485760"/>
                <param name="maximum-rotate" value="5"/>
                <param name="uuid" value="true"/>
            </settings>
            <mappings>
                <map name="all" value="warning,err,crit,alert"/>
            </mappings>
        </profile>
    </profiles>
</configuration>
EOF
}

prepare_freeswitch_runtime_permissions() {
    # Build output contains public executables/libraries, not deployment secrets.
    # Repair only their parent directories on an existing restrictive-umask build.
    local directory
    for directory in /usr/local/freeswitch /usr/local/freeswitch/bin \
        /usr/local/freeswitch/lib /usr/local/freeswitch/lib/freeswitch \
        /usr/local/freeswitch/lib/freeswitch/mod; do
        validate_config_directory "$directory"
        run install -d -o root -g root -m 0755 "$directory"
    done
}

configure_kazoo_freeswitch() {
    local config_source="$KAZOO_BUILD_ROOT/kazoo-configs-freeswitch"
    local module module_config
    validate_config_directory "$KAZOO_CONFIG_DIR"
    validate_config_directory "$KAZOO_CONFIG_DIR/freeswitch"
    run install -d -o root -g root -m 0755 "$KAZOO_CONFIG_DIR" "$KAZOO_CONFIG_DIR/freeswitch"
    sync_git https://github.com/2600hz/kazoo-configs-freeswitch.git \
        "$config_source" "$FREESWITCH_CONFIG_REF"
    # Normalize only incoming public source templates, not existing secrets or
    # recordings. Git checkouts made under umask077 otherwise remain unreadable.
    run rsync -a --chmod=Du=rwx,Dgo=rx,Fu=rwX,Fgo=rX "$config_source/freeswitch/" "$KAZOO_CONFIG_DIR/freeswitch/"
    configure_freeswitch_logging
    reject_secret_symlink "$KAZOO_FREESWITCH_COOKIE_FILE"
    printf '%s\n' "$KAZOO_COOKIE" | write_file 0400 "$KAZOO_FREESWITCH_COOKIE_FILE"
    module_config="$KAZOO_CONFIG_DIR/freeswitch/autoload_configs/modules.conf.xml"
    if [[ $DRY_RUN != true ]]; then
        for module in mod_say_en mod_say_es mod_say_fr; do
            [[ -f /usr/local/freeswitch/lib/freeswitch/mod/${module}.so ]] || \
                die "Required queue speech module is missing: ${module}"
            if ! grep -Eq "^[[:space:]]*<load module=\"${module}\"[[:space:]]*/>" "$module_config"; then
                sed -i "/<\/modules>/i\\        <load module=\"${module}\"/>" "$module_config"
            fi
        done
        # The upstream configuration also lists optional/proprietary codecs and
        # video/TTS modules. Remove only load elements for which no shared
        # object was built. Deleting the element (instead of adding an XML
        # comment) matters because some optional loads are already inside a
        # multi-line XML comment.
        while IFS= read -r module; do
            if [[ ! -f /usr/local/freeswitch/lib/freeswitch/mod/${module}.so ]]; then
                sed -i -E "/^[[:space:]]*<load module=\"${module}\"[[:space:]]*\/>/d" "$module_config"
            fi
        done < <(sed -n -E 's/^[[:space:]]*<load module="([^"]+)"[[:space:]]*\/>.*/\1/p' "$module_config")
        sed -i -E \
            -e "s#(<param name=\"listen-ip\" value=\")[^\"]*(\"[[:space:]]*/>)#\1${KAZOO_ERLANG_DIST_IP}\2#" \
            -e "s#<param name=\"cookie\" value=\"[^\"]*\"[[:space:]]*/>#<param name=\"cookie-file\" value=\"${KAZOO_FREESWITCH_COOKIE_FILE}\" />#" \
            -e "s#(<param name=\"shortname\" value=\")[^\"]*(\"[[:space:]]*/>)#\1${KAZOO_FREESWITCH_SHORTNAME}\2#" \
            "$KAZOO_CONFIG_DIR/freeswitch/autoload_configs/kazoo.conf.xml"
        if grep -q '<param name="event-stream-framing"' \
            "$KAZOO_CONFIG_DIR/freeswitch/autoload_configs/kazoo.conf.xml"; then
            sed -i -E 's#(<param name="event-stream-framing" value=")[^"]*("[[:space:]]*/>)#\14\2#' \
                "$KAZOO_CONFIG_DIR/freeswitch/autoload_configs/kazoo.conf.xml"
        else
            sed -i '/<param name="listen-port"/a\        <param name="event-stream-framing" value="4" />' \
                "$KAZOO_CONFIG_DIR/freeswitch/autoload_configs/kazoo.conf.xml"
        fi
        grep -Eq "<param name=\"cookie-file\" value=\"${KAZOO_FREESWITCH_COOKIE_FILE}\"[[:space:]]*/>" \
            "$KAZOO_CONFIG_DIR/freeswitch/autoload_configs/kazoo.conf.xml" ||
            die 'FreeSWITCH mod_kazoo configuration does not use the protected cookie file'
        ! grep -Eq '<param name="cookie" value="[^"]+"[[:space:]]*/>' \
            "$KAZOO_CONFIG_DIR/freeswitch/autoload_configs/kazoo.conf.xml" ||
            die 'FreeSWITCH mod_kazoo configuration still contains an inline Erlang cookie'
        grep -Eq '<param name="event-stream-framing" value="4"[[:space:]]*/>' \
            "$KAZOO_CONFIG_DIR/freeswitch/autoload_configs/kazoo.conf.xml" ||
            die 'FreeSWITCH mod_kazoo configuration does not use four-byte event-stream framing'
        sed -i -E \
            "s#(<param name=\"shortname\" value=\")[^\"]*(\"[[:space:]]*/>)#\1${KAZOO_FREESWITCH_SHORTNAME}\2#" \
            "$KAZOO_CONFIG_DIR/freeswitch/autoload_configs/com.kazoo.conf.xml"
    fi
    {
        printf 'export KZ_AMQP_HOST=%q\n' "$KAZOO_AMQP_HOST"
        printf 'export KZ_AMQP_PORT=%q\n' "$KAZOO_AMQP_PORT"
        printf 'export KZ_AMQP_VHOST=%q\n' "$KAZOO_RABBITMQ_VHOST"
        printf 'export KZ_AMQP_USER=%q\n' "$KAZOO_RABBITMQ_USER"
        printf 'export KZ_AMQP_PASS=%q\n' "$KAZOO_RABBITMQ_PASSWORD"
        printf 'export KZ_AMQP_ZONE=%q\n' local
    } | write_file 0640 "$KAZOO_CONFIG_DIR/freeswitch/env"
    write_file 0644 /etc/sysconfig/freeswitch <<'EOF'
FS_BIN=/usr/local/freeswitch/bin/freeswitch
FS_CONFIG=/etc/kazoo/freeswitch
FS_HOME=/var/lib/kazoo-freeswitch
RAM_DISK_ENABLED=false
EOF
    write_file 0644 /etc/ld.so.conf.d/kazoo-freeswitch.conf <<'EOF'
/usr/local/lib64
/usr/local/lib
/usr/local/freeswitch/lib
EOF
    run ldconfig
    run install -D -m 0755 "$config_source/system/sbin/kazoo-freeswitch" /usr/sbin/kazoo-freeswitch
    write_file 0644 /etc/systemd/system/kazoo-freeswitch.service <<'EOF'
[Unit]
Description=FreeSWITCH Configured for Kazoo (mod_kazoo)
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=freeswitch
Group=freeswitch
UMask=0027
EnvironmentFile=-/etc/sysconfig/freeswitch
ExecStartPre=+/usr/sbin/kazoo-freeswitch prepare
ExecStart=/usr/sbin/kazoo-freeswitch start -nc -nf
Restart=on-failure
RestartSec=5
LimitCORE=infinity
LimitNOFILE=100000
LimitNPROC=60000
LimitNICE=-20
LimitRTPRIO=99
AmbientCapabilities=CAP_SYS_NICE
CapabilityBoundingSet=CAP_SYS_NICE

[Install]
WantedBy=multi-user.target
EOF
    run systemctl disable --now freeswitch.service 2>/dev/null || true
    if ! getent group freeswitch >/dev/null; then
        run groupadd --system freeswitch
    fi
    if ! id freeswitch >/dev/null 2>&1; then
        run useradd --system --gid freeswitch --home-dir /var/lib/kazoo-freeswitch --shell /sbin/nologin freeswitch
    fi
    run chown freeswitch:freeswitch "$KAZOO_FREESWITCH_COOKIE_FILE"
    run chown root:freeswitch "$KAZOO_CONFIG_DIR/freeswitch/env"
    run mkdir -p /var/lib/kazoo-freeswitch /var/log/freeswitch /run/freeswitch /usr/share/kazoo-freeswitch/sounds
    run chown -R freeswitch:freeswitch /var/lib/kazoo-freeswitch /var/log/freeswitch /run/freeswitch /usr/share/kazoo-freeswitch
    run install -d -m 0750 -o freeswitch -g freeswitch /var/log/freeswitch
    prepare_freeswitch_runtime_permissions
    install_freeswitch_sounds
}

install_freeswitch_sounds() {
    local manifest=/usr/local/share/kazoo5-installer/freeswitch-sounds.manifest locale
    prepare_kazoo_sounds
    for locale in en/us es/es fr/fr; do
        run install -d -m 0755 "/usr/share/kazoo-freeswitch/sounds/${locale%/*}" "/usr/share/kazoo-freeswitch/sounds/$locale"
        run rsync -a --ignore-existing --chmod=D755,F644 "$KAZOO_BUILD_ROOT/kazoo-sounds/freeswitch/$locale/" \
            "/usr/share/kazoo-freeswitch/sounds/$locale/"
    done
    run mkdir -p /usr/share/kazoo-freeswitch/sounds/music
    run rsync -a --ignore-existing --chmod=D755,F644 "$KAZOO_BUILD_ROOT/kazoo-sounds/freeswitch/music/" \
        /usr/share/kazoo-freeswitch/sounds/music/
    if [[ $DRY_RUN != true ]]; then
        (cd "$KAZOO_BUILD_ROOT/kazoo-sounds/freeswitch" && find en/us es/es fr/fr music -type f -name '*.wav' -print) | \
            sort | write_file 0644 "$manifest"
        verify_freeswitch_sounds
    fi
    log 'Installed pinned English, Spanish and French FreeSWITCH sounds; existing files preserved'
}

verify_freeswitch_sounds() {
    local manifest=/usr/local/share/kazoo5-installer/freeswitch-sounds.manifest file count=0
    [[ -s $manifest ]] || die 'FreeSWITCH sound manifest is missing; reinstall freeswitch'
    while IFS= read -r file; do
        [[ $file =~ ^[a-zA-Z0-9_/-]+\.wav$ && $file != /* && $file != *..* ]] || die 'Invalid FreeSWITCH sound manifest'
        [[ -s /usr/share/kazoo-freeswitch/sounds/$file ]] || die "Missing FreeSWITCH sound: ${file}"
        count=$((count + 1))
    done < "$manifest"
    runuser --user freeswitch -- python3 -B -I -c '
import pathlib, sys
try:
    for name in sys.stdin.read().splitlines():
        with (pathlib.Path("/usr/share/kazoo-freeswitch/sounds") / name).open("rb") as audio:
            if not audio.read(1):
                raise OSError("empty audio")
except OSError:
    raise SystemExit("FreeSWITCH service user cannot read a required sound")
' < "$manifest" || die 'FreeSWITCH sounds are not readable by the service user'
    log "PASS ${count} FreeSWITCH speech and hold-music files"
}

install_freeswitch() {
    local marker=/usr/local/share/kazoo5-installer/freeswitch-build
    local expected_build installed_build='' installed_binary_version='' spandsp_link_errors=''
    log "Installing Kazoo FreeSWITCH ${FREESWITCH_VERSION}"
    expected_build=$(freeswitch_build_fingerprint)
    [[ -r $marker ]] && installed_build=$(<"$marker")
    if [[ -x /usr/local/freeswitch/bin/freeswitch ]]; then
        installed_binary_version=$(/usr/local/freeswitch/bin/freeswitch -version 2>&1 || true)
    fi
    if [[ -f /usr/local/freeswitch/lib/freeswitch/mod/mod_spandsp.so ]]; then
        spandsp_link_errors=$(ldd -r /usr/local/freeswitch/lib/freeswitch/mod/mod_spandsp.so 2>&1 | \
            grep -F 'undefined symbol' || true)
    fi
    if [[ $installed_build != "$expected_build" || \
          $installed_binary_version != *"${FREESWITCH_VERSION}"* || \
          -n $spandsp_link_errors || \
          ! -x /usr/local/freeswitch/bin/freeswitch || \
          ! -f /usr/local/freeswitch/lib/freeswitch/mod/mod_kazoo.so || \
          ! -f /usr/local/freeswitch/lib/freeswitch/mod/mod_spandsp.so || \
          ! -f /usr/local/freeswitch/lib/freeswitch/mod/mod_say_es.so || \
          ! -f /usr/local/freeswitch/lib/freeswitch/mod/mod_say_fr.so ]]; then
        build_kazoo_freeswitch
    fi
    configure_kazoo_freeswitch
    if [[ $DRY_RUN != true ]]; then
        runuser --user freeswitch -- /usr/local/freeswitch/bin/freeswitch -version >/dev/null || \
            die 'FreeSWITCH service user cannot execute the installed binary'
    fi
    service_enable_restart kazoo-freeswitch.service
    wait_for_port 127.0.0.1 8021 90 || die 'Kazoo FreeSWITCH event socket did not open port 8021'
    wait_for_port "$KAZOO_ERLANG_DIST_IP" 8031 90 || \
        die "Kazoo FreeSWITCH mod_kazoo did not open ${KAZOO_ERLANG_DIST_IP}:8031"
    if [[ ${SELECTED[ecallmgr]:-} ]]; then
        log 'Deferring the FreeSWITCH/eCallMgr dependency check until eCallMgr is converged'
        verify_freeswitch deferred
    else
        register_configured_freeswitch_nodes
        verify_freeswitch
    fi
}

verify_freeswitch() {
    if [[ $DRY_RUN == true ]]; then log 'Would verify Kazoo FreeSWITCH'; return 0; fi
    verify_freeswitch_sounds
    local verification_mode=${1:-full}
    local module module_config=/etc/kazoo/freeswitch/autoload_configs/modules.conf.xml
    local pid initial_restarts current_restarts seconds_alive wait_seconds erlang_status active_since listener
    local sofia_status api_list node framing
    local require_media_connection=false media_connected=false
    assert_service kazoo-freeswitch.service
    verify_cookie_copy "$KAZOO_FREESWITCH_COOKIE_FILE" freeswitch
    /usr/local/freeswitch/bin/freeswitch -version | grep -F "$FREESWITCH_VERSION" >/dev/null || \
        die "Installed FreeSWITCH is not version ${FREESWITCH_VERSION}"
    [[ -f /usr/local/freeswitch/lib/freeswitch/mod/mod_kazoo.so ]] || die 'mod_kazoo.so is missing'
    if ldd -r /usr/local/freeswitch/lib/freeswitch/mod/mod_spandsp.so 2>&1 | \
        grep -F 'undefined symbol' >/dev/null; then
        die 'mod_spandsp has unresolved dependency symbols'
    fi
    /usr/local/freeswitch/bin/fs_cli -x status >/dev/null || die 'FreeSWITCH CLI status failed'
    /usr/local/freeswitch/bin/fs_cli -x 'module_exists mod_kazoo' | grep -i true >/dev/null || \
        die 'FreeSWITCH did not load mod_kazoo'
    api_list=$(/usr/local/freeswitch/bin/fs_cli -x 'show api') || \
        die 'FreeSWITCH API inventory failed'
    grep -Eq '^kz_originate,' <<<"$api_list" || \
        die 'FreeSWITCH mod_kazoo does not provide the Kazoo originate API'
    grep -Eq '^kz_originate_cancel,' <<<"$api_list" || \
        die 'FreeSWITCH mod_kazoo does not provide the Kazoo originate cancellation API'
    grep -Eq '^kz_originate_reconcile,' <<<"$api_list" || \
        die 'FreeSWITCH mod_kazoo does not provide the Kazoo originate reconciliation API'
    /usr/local/freeswitch/bin/fs_cli -x 'show application as json' | \
        jq -e '[.rows[] | select(.name == "kz_intercept" and .ikey == "mod_kazoo")] | length == 1' >/dev/null || \
        die 'FreeSWITCH mod_kazoo lacks atomic ACDC pickup; update the media module before eCallMgr'
    /usr/local/freeswitch/bin/fs_cli -x 'module_exists mod_spandsp' | grep -i true >/dev/null || \
        die 'FreeSWITCH did not load mod_spandsp'
    for module in mod_say_en mod_say_es mod_say_fr; do
        /usr/local/freeswitch/bin/fs_cli -x "module_exists ${module}" | grep -i true >/dev/null || \
            die "FreeSWITCH did not load required speech module ${module}"
    done
    listener=$(ss -H -ltn 'sport = :8031' 2>/dev/null || true)
    grep -F "${KAZOO_ERLANG_DIST_IP}:8031" <<<"$listener" >/dev/null || \
        die "FreeSWITCH mod_kazoo is not bound to ${KAZOO_ERLANG_DIST_IP}:8031"
    while IFS= read -r module; do
        [[ -f /usr/local/freeswitch/lib/freeswitch/mod/${module}.so ]] || \
            die "FreeSWITCH config enables missing module ${module}"
    done < <(sed -n -E 's/^[[:space:]]*<load module="([^"]+)"[[:space:]]*\/>.*/\1/p' "$module_config")
    pid=$(systemctl show kazoo-freeswitch.service -p MainPID --value)
    [[ $pid =~ ^[1-9][0-9]*$ ]] || die 'FreeSWITCH systemd unit has no live main PID'
    initial_restarts=$(systemctl show kazoo-freeswitch.service -p NRestarts --value)
    seconds_alive=$(ps -o etimes= -p "$pid" | tr -d '[:space:]')
    [[ $seconds_alive =~ ^[0-9]+$ ]] || die 'Could not determine FreeSWITCH process age'
    wait_seconds=$((KAZOO_FREESWITCH_STABILITY_SECONDS - seconds_alive))
    if ((wait_seconds > 0)); then
        log "Holding FreeSWITCH stability check for ${wait_seconds}s"
        sleep "$wait_seconds"
    fi
    assert_service kazoo-freeswitch.service
    [[ $(systemctl show kazoo-freeswitch.service -p MainPID --value) == "$pid" ]] || \
        die 'FreeSWITCH restarted during its stability check'
    current_restarts=$(systemctl show kazoo-freeswitch.service -p NRestarts --value)
    [[ $current_restarts == "$initial_restarts" ]] || \
        die 'FreeSWITCH restart counter changed during its stability check'
    active_since=$(systemctl show kazoo-freeswitch.service -p ActiveEnterTimestamp --value)
    if journalctl -u kazoo-freeswitch.service --since "$active_since" --no-pager 2>/dev/null | \
        grep -Eiq 'double free|corrupt(ed|ion)|core-dump|status=6/ABRT'; then
        die 'FreeSWITCH logged a heap corruption or core dump in the current activation'
    fi
    erlang_status=$(/usr/local/freeswitch/bin/fs_cli -x 'erlang status' 2>&1) || \
        die 'mod_kazoo erlang status failed'
    [[ $erlang_status == *'Running mod_kazoo'* ]] || die 'mod_kazoo status is unavailable'
    [[ $erlang_status != *' with cookie '* ]] || \
        die 'FreeSWITCH mod_kazoo status discloses the Erlang cookie'
    if [[ $erlang_status == *'Connected to:'* && $erlang_status == *'ecallmgr@'* ]]; then
        media_connected=true
    fi
    if [[ $verification_mode == deferred ]]; then
        log 'PASS stable Kazoo FreeSWITCH, mod_kazoo, and mod_spandsp checks; eCallMgr link and Sofia verification deferred'
        return 0
    fi
    case $KAZOO_REQUIRE_MEDIA_CONNECTION in
        true) require_media_connection=true ;;
        auto)
            if systemctl is-active --quiet kazoo-ecallmgr.service 2>/dev/null; then
                require_media_connection=true
            fi
            ;;
    esac
    if [[ $require_media_connection == true && $media_connected != true ]]; then
        die 'FreeSWITCH mod_kazoo is not connected to an eCallMgr node'
    fi
    if [[ $media_connected == true ]]; then
        while IFS= read -r node; do
            framing=$(/usr/local/freeswitch/bin/fs_cli -x \
                "erlang node ${node} option event-stream-framing" 2>&1) || \
                die "Could not read event-stream framing for ${node}"
            [[ $framing == '+OK 4' ]] || \
                die "FreeSWITCH event stream for ${node} is not using four-byte framing"
        done < <(sed -n -E 's/^[[:space:]]*(ecallmgr@[^[:space:]]+)[[:space:]].*/\1/p' <<<"$erlang_status")
    fi
    if [[ $media_connected == true || $require_media_connection == true ]]; then
        sofia_status=$(/usr/local/freeswitch/bin/fs_cli -x 'sofia status profile sipinterface_1' 2>&1) || \
            die 'FreeSWITCH Sofia profile sipinterface_1 status command failed'
        [[ $sofia_status == *'Name'*'sipinterface_1'* && \
           $sofia_status == *'BIND-URL'*':11000'* ]] || \
            die 'FreeSWITCH Sofia profile sipinterface_1 is not running on SIP port 11000'
    fi
    if systemctl is-active --quiet kazoo-ecallmgr.service 2>/dev/null; then
        verify_configured_freeswitch_nodes
    fi
    if [[ $media_connected == true ]]; then
        log 'PASS stable Kazoo FreeSWITCH, Sofia SIP profile, eCallMgr link, mod_kazoo, and mod_spandsp checks'
    else
        log 'PASS stable Kazoo FreeSWITCH, mod_kazoo, and mod_spandsp checks; remote eCallMgr link and Sofia readiness are delegated'
    fi
}

install_kamailio_packages() {
    download https://rpm.kamailio.org/centos/kamailio.repo "$KAZOO_CACHE_DIR/kamailio.repo"
    run install -D -m 0644 "$KAZOO_CACHE_DIR/kamailio.repo" /etc/yum.repos.d/kamailio.repo
    dnf_install --disablerepo=kamailio --enablerepo="kamailio-${KAMAILIO_VERSION}" \
        kamailio kamailio-kazoo kamailio-outbound kamailio-presence \
        kamailio-sqlite kamailio-tcpops kamailio-uuid
}

rewrite_kamailio_flags() {
    local flags_file=$1
    local temporary
    [[ $DRY_RUN != true ]] || return 0
    temporary=$(mktemp)
    awk '
        /^bflags[[:space:]]*$/ {
            print "#!define FLB_NATB 0"
            print "#!define FLB_KEEP_ALIVE 1"
            print "#!define FLB_UAC_REDIRECT 2"
            skipping = 1
            next
        }
        skipping && /;[[:space:]]*$/ { skipping = 0; next }
        skipping { next }
        { print }
    ' "$flags_file" >"$temporary"
    install -m 0644 "$temporary" "$flags_file"
    rm -f "$temporary"
}

rewrite_kamailio_61_compatibility() {
    local config_dir=$1
    local cfg
    local -a cfg_files=()
    [[ $DRY_RUN != true ]] || return 0
    mapfile -d '' -t cfg_files < <(
        find "$config_dir" -type f -name '*.cfg' -print0 | sort -z
    )
    ((${#cfg_files[@]})) || die "No Kamailio configuration files found in ${config_dir}"
    for cfg in "${cfg_files[@]}"; do
        sed -i \
            -e '/modparam("dispatcher", "uri_pvname",/d' \
            -e '/modparam("dispatcher", "ds_rehash_max",/d' \
            -e 's/rollingexpire=1/updateexpire=1/g' \
            -e 's/modparamx("usrloc", "nat_bflag", \$bflag(FLB_NATB))/modparam("usrloc", "nat_bflag", FLB_NATB)/g' \
            -e '/modparamx("usrloc", "ka_flag",/d' \
            -e 's/\$var(fast_pickup_redirected_to) = \$var(ds_uri);/\$var(fast_pickup_redirected_to) = \$vn(presence_redirect_to);/' \
            -e 's/\$du = \$var(ds_uri);/\$du = \$T_rpl(\$hdr(X-Redirect-Server));/' \
            -e 's/\$(knode{/$(def(KAZOO_PROXY_NODE){/g' \
            -e 's/\$knode/\$def(KAZOO_PROXY_NODE)/g' \
            -e 's/\$ki/\$var(kz_log_id)/g' \
            "$cfg"
    done

    # Kamailio 6.1 changed corex.list_sockets JSON keys to lower case.  The
    # pinned 2600Hz configuration predates that API change and otherwise
    # publishes an invalid nodes advertisement with empty listener fields.
    sed -i \
        -e 's/{kz\.json,PROTO}/{kz.json,proto}/g' \
        -e 's/{kz\.json,ADDRLIST\.ADDR}/{kz.json,addrlist.addr}/g' \
        -e 's/{kz\.json,PORT}/{kz.json,port}/g' \
        -e 's/{kz\.json,ADVERTISE}/{kz.json,advertise}/g' \
        "$config_dir/nodes-role.cfg"

    # db_sqlite intentionally does not expose DB_CAP_AFFECTED_ROWS. Every
    # legacy presence/older-dispatcher checks retain their existing fallback.
    # The installed 5.7 dispatcher instead reads SQLite changes() immediately
    # after DML. Replacing its result with 1 causes unnecessary reloads which
    # invalidate in-flight OPTIONS identifiers in stock dispatcher 6.1.4.
    for cfg in "${cfg_files[@]}"; do
        if [[ ${cfg##*/} != dispatcher-role-5.7.cfg ]]; then
            sed -i -E 's/\$sqlrows\([^)]*\)/1/g' "$cfg"
        fi
        # The current kazoo module's four-argument synchronous query treats
        # argument four as a writable destination PV.  The 2600Hz config uses
        # legacy numeric AMQP flags there and reads the reply from $kzR, so use
        # the supported three-argument form.
        sed -i -E \
            '/kazoo_query\(.*\$def\([^)]*_AMQP_FLAGS\)/ s/,[[:space:]]*"\$def\([^)]*_AMQP_FLAGS\)"\)/)/' \
            "$cfg"
        # In the stock 6.1 kazoo module the optional last argument to both
        # registrar calls is an AMQP-header list, not a numeric flag field.
        # Even an empty string invokes the parser and logs an error, so omit
        # the optional registrar AMQP-header argument altogether.
        sed -i -E \
            's/,[[:space:]]*"\$def\(REGISTRAR_AMQP_FLAGS\)"\)/)/g' \
            "$cfg"
    done

    # The legacy kz.filename transformation and nested preprocessor escaping
    # no longer produce a usable xlog format in 6.1. Configure the module with
    # native PVs directly so prefix_mode evaluates the values at runtime.
    sed -i \
        -e 's~^modparamx("xlog", "prefix_mode",.*~modparam("xlog", "prefix_mode", 1)~' \
        -e 's~^modparamx("xlog", "prefix",.*~modparam("xlog", "prefix", "|$var(kz_log_id)|$cfg(name):$cfg(line) ")~' \
        "$config_dir/default.cfg"
}

rewrite_kamailio_imports() {
    local config_dir=$1
    local main_config=$config_dir/kamailio.cfg
    local line indent relative_dir basename temporary
    local import_re='^([[:space:]]*)import_files?[[:space:]]+"([a-zA-Z0-9_.-]+)/\*\.cfg"[[:space:]]*$'
    local -a imported_files=()
    [[ $DRY_RUN != true ]] || return 0
    temporary=$(mktemp)
    while IFS= read -r line || [[ -n $line ]]; do
        if [[ ! $line =~ $import_re ]]; then
            printf '%s\n' "$line" >>"$temporary"
            continue
        fi
        indent=${BASH_REMATCH[1]}
        relative_dir=${BASH_REMATCH[2]}
        imported_files=()
        if [[ -d $config_dir/$relative_dir ]]; then
            mapfile -t imported_files < <(
                find "$config_dir/$relative_dir" -maxdepth 1 -type f -name '*.cfg' \
                    -printf '%f\n' | sort
            )
        fi
        if ((${#imported_files[@]} == 0)); then
            printf '%s# No %s/*.cfg files installed\n' "$indent" "$relative_dir" >>"$temporary"
            continue
        fi
        for basename in "${imported_files[@]}"; do
            [[ $basename =~ ^[a-zA-Z0-9_.-]+$ ]] || \
                die "Unsupported Kamailio include filename: ${relative_dir}/${basename}"
            printf '%simport_file "%s/%s"\n' \
                "$indent" "$relative_dir" "$basename" >>"$temporary"
        done
    done <"$main_config"
    install -m 0644 "$temporary" "$main_config"
    rm -f "$temporary"
}

rewrite_kamailio_route_extensions() {
    local config_dir=$1
    local cfg line indent argument prefix handler method temporary
    local route_call_re='^([[:space:]]*)routes\((.*)\);[[:space:]]*$'
    local -a route_names=()
    local replacements=0 handlers=0
    [[ $DRY_RUN != true ]] || {
        log 'Would expand 2600Hz wildcard route extension points for stock Kamailio'
        return 0
    }
    mapfile -t route_names < <(
        find "$config_dir" -type f -name '*.cfg' -print0 | sort -z | \
            xargs -0 sed -n -E 's/^[[:space:]]*route\[([^]]+)\].*/\1/p' | sort -u
    )
    ((${#route_names[@]})) || die 'No Kamailio route blocks were found in the 2600Hz configuration'
    while IFS= read -r -d '' cfg; do
        temporary=$(mktemp)
        while IFS= read -r line || [[ -n $line ]]; do
            if [[ ! $line =~ $route_call_re ]]; then
                printf '%s\n' "$line" >>"$temporary"
                continue
            fi
            indent=${BASH_REMATCH[1]}
            argument=${BASH_REMATCH[2]}
            argument=${argument#\"}
            argument=${argument%\"}
            handlers=0
            case "$argument" in
                'KZ_$(rm)_START_ROUTE')
                    for handler in "${route_names[@]}"; do
                        if [[ $handler =~ ^KZ_([A-Z]+)_START_ROUTE_ ]]; then
                            method=${BASH_REMATCH[1]}
                            printf '%sif (is_method("%s")) { route_if_exists("%s"); }\n' \
                                "$indent" "$method" "$handler" >>"$temporary"
                            ((handlers += 1))
                        fi
                    done
                    ;;
                'KZ_LOCAL_$(rm)')
                    for handler in "${route_names[@]}"; do
                        if [[ $handler =~ ^KZ_LOCAL_([A-Z]+)_ ]]; then
                            method=${BASH_REMATCH[1]}
                            printf '%sif (is_method("%s")) { route_if_exists("%s"); }\n' \
                                "$indent" "$method" "$handler" >>"$temporary"
                            ((handlers += 1))
                        fi
                    done
                    ;;
                *'$('*|*')'*)
                    die "Unsupported dynamic 2600Hz routes() expression in ${cfg}: ${argument}"
                    ;;
                *)
                    [[ $argument =~ ^[A-Z][A-Z0-9_]*$ ]] || \
                        die "Unsupported 2600Hz routes() expression in ${cfg}: ${argument}"
                    prefix=${argument}_
                    for handler in "${route_names[@]}"; do
                        if [[ $handler == "$prefix"* ]]; then
                            printf '%sroute_if_exists("%s");\n' "$indent" "$handler" >>"$temporary"
                            ((handlers += 1))
                        fi
                    done
                    ;;
            esac
            if ((handlers == 0)); then
                printf '%sroute_if_exists("__KAZOO_COMPAT_NOOP"); # no extensions for %s\n' \
                    "$indent" "$argument" >>"$temporary"
            fi
            ((replacements += 1))
        done <"$cfg"
        install -m 0644 "$temporary" "$cfg"
        rm -f "$temporary"
    done < <(find "$config_dir" -type f -name '*.cfg' -print0 | sort -z)
    ((replacements > 0)) || die 'The expected 2600Hz routes() extension points were not found'
    log "Expanded ${replacements} 2600Hz wildcard route extension points"
}

configure_kamailio_sqlite() {
    local config_dir=$1
    write_file 0644 "$config_dir/db_sqlite.cfg" <<EOF
#### db_sqlite module (stock Kamailio compatibility) ####
loadmodule "db_sqlite.so"
#!define KZ_DISPATCHER_SQLITE_AFFECTED_ROWS
# Use the exact database component of sqlite:////absolute/path. Without a
# per-connection busy timeout, concurrent presence/ACL writers fail instantly.
modparam("db_sqlite", "db_set_busy_timeout", "$config_dir/db/kazoo.db=1000;")
modparam("db_sqlite", "db_set_journal_mode", "$config_dir/db/kazoo.db=WAL;")

include_file "db_queries_kazoo.cfg"
EOF
    write_file 0755 "$config_dir/db_scripts/db_sqlite-specific" <<'EOF'
#!/usr/bin/env bash

sql_db_pre_setup() {
cat <<'SQL'
PRAGMA foreign_keys=OFF;
PRAGMA journal_mode=WAL;
PRAGMA wal_autocheckpoint=25;
BEGIN TRANSACTION;
SQL
}

sql_setup() {
    local db_location=${2:-${DB_LOCATION:-/etc/kazoo/kamailio/db}}
    mkdir -p "$db_location"
    sqlite3 "$db_location/kazoo.db" <"$1" >/dev/null
}

sql_header() { :; }

sql_extra_tables() {
    # db_kazoo is an embedded SQLite driver. Reuse its Kazoo-specific
    # schema additions while stock Kamailio supplies the db_sqlite driver.
    # shellcheck disable=SC1090
    source "${DB_SCRIPT_DIR}/db_kazoo-specific"
    sql_extra_tables
}

sql_footer() { :; }
EOF
    if [[ $DRY_RUN != true ]]; then
        sed -i 's|$(dirname $0)/$DB_ENGINE-specific|$(dirname "${BASH_SOURCE[0]}")/$DB_ENGINE-specific|' \
            "$config_dir/db_scripts/kazoodb-sql.sh"
    fi
    write_file 0755 /usr/local/libexec/kazoo-kamailio-prepare <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

config_dir=${KAMAILIO_CONFIG_DIR:-/etc/kazoo/kamailio}
db_dir=${KAMAILIO_DB_LOCATION:-${config_dir}/db}
script_dir=${config_dir}/db_scripts
runtime_dir=${KAMAILIO_RUNTIME_DIR:-/run/kamailio}
temporary=$(mktemp -d /tmp/kazoo-kamailio-db.XXXXXX)
trap 'rm -rf -- "$temporary"' EXIT

install -d -m 0750 -o kamailio -g kamailio "$runtime_dir" "$db_dir"
export DB_ENGINE=db_sqlite
export DB_LOCATION=$db_dir
export DB_SCRIPT_DIR=$script_dir
export KAMAILIO_SHARE_DIR=${KAMAILIO_SHARE_DIR:-/usr/share/kamailio}
export RESULTED_SQL=$temporary/schema.sql
# shellcheck disable=SC1090
source "$script_dir/kazoodb-sql.sh" --source-only

# Loading every stock schema creates duplicate tables. These are precisely
# the modules used by the enabled Kazoo roles; db_kazoo-specific adds the
# remaining Kazoo tables, indexes, triggers and views.
sql_filelist() {
    printf '%s\n' \
        dispatcher-create.sql \
        htable-create.sql \
        permissions-create.sql \
        presence-create.sql \
        usrloc-create.sql
}

schema_file=$(sql_db_prepare)
sqlite3 "$temporary/kazoo.db" <"$schema_file" >/dev/null
expected_versions=$(sqlite3 "$temporary/kazoo.db" \
    "SELECT group_concat(table_name || ':' || table_version, ',') FROM (SELECT table_name, table_version FROM version ORDER BY table_name);")

if [[ ! -s $db_dir/kazoo.db ]]; then
    install -m 0640 -o kamailio -g kamailio "$temporary/kazoo.db" "$db_dir/kazoo.db"
else
    current_versions=$(sqlite3 "$db_dir/kazoo.db" \
        "SELECT group_concat(table_name || ':' || table_version, ',') FROM (SELECT table_name, table_version FROM version ORDER BY table_name);" 2>/dev/null || true)
    if [[ $current_versions != "$expected_versions" ]]; then
        printf 'Existing Kamailio database schema does not match the pinned Kazoo configuration.\n' >&2
        printf 'Back up %s and migrate it before changing KAMAILIO_CONFIG_REF.\n' "$db_dir/kazoo.db" >&2
        exit 1
    fi
fi

# The upstream helper creates this scratch table in a short-lived KazooDB
# process, despite calling it temporary. SQLite drops TEMP tables with their
# connection, so keep a normal, empty scratch table for the long-running
# Kamailio SQL connections.
sqlite3 "$db_dir/kazoo.db" <<'SQL'
CREATE TABLE IF NOT EXISTS tmp_probe (
    event TEXT NOT NULL,
    presentity_uri TEXT NOT NULL,
    action INTEGER NOT NULL
);
DELETE FROM tmp_probe;
SQL

for init_script in "$script_dir"/db_init_*.sql; do
    [[ -e $init_script ]] || continue
    sqlite3 "$db_dir/kazoo.db" <"$init_script"
done
chown kamailio:kamailio "$db_dir/kazoo.db"
chmod 0640 "$db_dir/kazoo.db"
EOF
}

configure_kazoo_kamailio() {
    local config_source="$KAZOO_BUILD_ROOT/kazoo-configs-kamailio"
    local installer_config fqdn
    fqdn=$(hostname -f 2>/dev/null || hostname)
    validate_config_directory "$KAZOO_CONFIG_DIR"
    validate_config_directory "$KAZOO_CONFIG_DIR/kamailio"
    run install -d -o root -g root -m 0755 "$KAZOO_CONFIG_DIR" "$KAZOO_CONFIG_DIR/kamailio"
    sync_git https://github.com/2600hz/kazoo-configs-kamailio.git \
        "$config_source" "$KAMAILIO_CONFIG_REF"
    apply_required_source_patch "$config_source" "$SCRIPT_DIR/patches/kamailio-registration-sequences.patch"
    apply_required_source_patch "$config_source" "$SCRIPT_DIR/patches/kamailio-registered-source-credentials.patch"
    apply_required_source_patch "$config_source" "$SCRIPT_DIR/patches/kamailio-dispatcher-reload-bookkeeping.patch"
    apply_required_source_patch "$config_source" "$SCRIPT_DIR/patches/kamailio-push-freshness.patch"
    run rsync -a --chmod=Du=rwx,Dgo=rx,Fu=rwX,Fgo=rX \
        --exclude db/ --exclude local.d/ --exclude defs.d/ \
        --exclude listeners.d/ --exclude extras.d/ \
        "$config_source/kamailio/" "$KAZOO_CONFIG_DIR/kamailio/"
    if [[ $DRY_RUN != true ]]; then
        sed -i 's/include_file "dispatcher-role-MAJOR.cfg"/include_file "dispatcher-role-5.7.cfg"/' \
            "$KAZOO_CONFIG_DIR/kamailio/default.cfg"
    else
        log 'Would configure Kazoo Kamailio hostname, address, and AMQP URI'
    fi
    installer_config="$KAZOO_CONFIG_DIR/kamailio/local.d/00-kazoo5-installer.cfg"
    write_file 0640 "$installer_config" <<EOF
#!substdef "!MY_HOSTNAME!${fqdn}!g"
#!substdef "!MY_IP_ADDRESS!${KAZOO_PUBLIC_IP}!g"
#!substdef "!MY_AMQP_URL!${KAZOO_AMQP_URI}!g"
#!define KZ_DB_MODULE sqlite
#!define KAZOO_PROXY_NODE "kamailio@${fqdn}"
#!substdef "!KAZOO_DB_URL!sqlite:///${KAZOO_CONFIG_DIR}/kamailio/db/kazoo.db!g"
#!trydef CHILDREN ${KAMAILIO_CHILDREN}
#!trydef TCP_CHILDREN ${KAMAILIO_TCP_CHILDREN}
#!trydef MY_AMQP_CONSUMER_PROCESSES ${KAMAILIO_AMQP_CONSUMERS}
#!trydef MY_AMQP_CONSUMER_WORKERS ${KAMAILIO_AMQP_WORKERS}
# Kamailio 6.1's stock kazoo module does not publish the per-zone amqpc XAVP
# consumed by the newer registrar-role availability guard.  Keeping that
# guard enabled drops every REGISTER before kazoo_async_query(), even with a
# healthy broker connection.  The query itself still fails closed on AMQP
# send error or timeout, so disabling only the incompatible early guard does
# not bypass SIP authentication.
#!define REGISTRAR_CHECK_AMQP_AVAILABILITY 0
# The same stock module defines the optional final publish/query argument as
# AMQP headers (key=value;...), whereas this config revision calls its value
# REGISTRAR_AMQP_FLAGS and defaults it to the numeric string 2048. An empty
# value keeps diagnostic log formatting valid; the compatibility rewrite
# omits the optional registrar AMQP-header argument from the actual calls.
#!define REGISTRAR_AMQP_FLAGS ""
EOF
    run chown root:kamailio "$installer_config"
    write_file 0640 "$KAZOO_CONFIG_DIR/kamailio/extras.d/99-kazoo5-compat.cfg" <<'EOF'
# Stock Kamailio's route_if_exists() returns an error for a missing route.
# The 2600Hz wildcard-route bridge uses this concrete no-op route whenever
# an optional extension point has no installed handlers.
route[__KAZOO_COMPAT_NOOP] {
    return;
}
EOF
    run chown root:kamailio "$KAZOO_CONFIG_DIR/kamailio/extras.d/99-kazoo5-compat.cfg"
    rewrite_kamailio_imports "$KAZOO_CONFIG_DIR/kamailio"
    rewrite_kamailio_flags "$KAZOO_CONFIG_DIR/kamailio/flags.cfg"
    rewrite_kamailio_61_compatibility "$KAZOO_CONFIG_DIR/kamailio"
    configure_kamailio_sqlite "$KAZOO_CONFIG_DIR/kamailio"
    rewrite_kamailio_route_extensions "$KAZOO_CONFIG_DIR/kamailio"
    write_file 0644 "$KAZOO_CONFIG_DIR/kamailio/options" <<EOF
KAMAILIO_BIN=/usr/sbin/kamailio
KAMAILIO_CONFIG=${KAZOO_CONFIG_DIR}/kamailio/kamailio.cfg
KAMAILIO_HOME=/run/kamailio
RAM_DISK_ENABLED=false
SKIP_RAM_DISK_CHECK=true
LISTENER_LOCAL_IP=${KAZOO_PUBLIC_IP}
LISTENER_PUBLIC_IP=disable
SHM_MEMORY=64
PKG_MEMORY=16
EOF
    run install -D -m 0755 "$config_source/system/sbin/kazoo-kamailio" /usr/sbin/kazoo-kamailio
    write_file 0644 /etc/systemd/system/kazoo-kamailio.service <<'EOF'
[Unit]
Description=Kamailio SIP Server Configured for Kazoo
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=kamailio
Group=kamailio
ExecStartPre=+/usr/local/libexec/kazoo-kamailio-prepare
ExecStart=/usr/sbin/kazoo-kamailio foreground
ExecStop=/usr/sbin/kamcmd core.kill
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
LimitCORE=infinity
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOF
    run systemctl disable --now kamailio.service 2>/dev/null || true
}

register_kamailio_sbc() {
    local name output persisted
    [[ $DRY_RUN != true ]] || return 0
    systemctl is-active --quiet kazoo-ecallmgr.service 2>/dev/null || {
        log 'Local eCallMgr is absent; the remote eCallMgr will discover this SBC from its Kazoo node advertisement'
        return 0
    }
    command -v sup >/dev/null || die 'SUP is required to register Kamailio with local eCallMgr'
    if systemctl is-active --quiet kazoo-apps.service 2>/dev/null; then
        ensure_master_account
    fi
    name="kamailio@${KAZOO_HOSTNAME}"
    # The FreeSWITCH acl.conf fetch handler calls authoritative_acls/0, which
    # reads the "default" config scope.  Pass true so allow_sbc writes there;
    # the two-argument form writes a node-local value that FS never receives.
    if ! output=$(timeout --signal=KILL 60 sup -n ecallmgr \
        ecallmgr_maintenance allow_sbc "$name" "$KAZOO_PUBLIC_IP" true </dev/null 2>&1); then
        die "Could not register ${name} (${KAZOO_PUBLIC_IP}) as an eCallMgr SBC: ${output}"
    fi
    # SUP can exit zero even when the remote maintenance function throws. Do
    # not report success unless the default-scope value is readable through
    # the same uncached API used by the FreeSWITCH acl.conf fetch handler.
    [[ $output != *'error getting system acls'* && $output != *'got '*' error(s)'* ]] ||
        die "Could not register ${name} in the persisted eCallMgr ACL configuration: ${output}"
    persisted=$(timeout --signal=KILL 30 sup -n ecallmgr -e kapps_config fetch_current \
        '<<"ecallmgr">>' '<<"acls">>' '{[]}' '<<"default">>' </dev/null 2>&1) ||
        die "Could not read the persisted default eCallMgr SBC ACL: ${persisted}"
    [[ $persisted == *"<<\"${name}\">>"* &&
       $persisted == *"<<\"${KAZOO_PUBLIC_IP}/32\">>"* &&
       $persisted == *'<<"network-list-name">>,<<"authoritative">>'* ]] ||
        die "Persisted eCallMgr SBC ACL does not contain ${name} (${KAZOO_PUBLIC_IP}) in the authoritative list"
    log "Registered Kazoo SBC ACL: ${name} -> ${KAZOO_PUBLIC_IP}"
}

verify_kamailio_sbc() {
    local result
    systemctl is-active --quiet kazoo-ecallmgr.service 2>/dev/null || return 0
    result=$(timeout --signal=KILL 60 sup -n ecallmgr \
        ecallmgr_maintenance test_sbc_ip "$KAZOO_PUBLIC_IP" </dev/null 2>&1) || \
        die "Could not verify the eCallMgr SBC ACL: ${result}"
    [[ $result != *'would be denied'* ]] || \
        die "eCallMgr denies the installed Kamailio address ${KAZOO_PUBLIC_IP}"
    [[ $result == *'would be accepted'* || $result == *'would be allowed'* ]] || \
        die "eCallMgr did not confirm the installed Kamailio address: ${result}"
    log "PASS eCallMgr allows the Kamailio SBC address ${KAZOO_PUBLIC_IP}"
}

verify_kamailio_amqp_connection() {
    local endpoint host port vhost protocol address connections deadline
    local -a broker_addresses=()
    # This URI is what configure_kazoo_kamailio rendered, including an explicit
    # operator URI. Never place its credentials in argv or diagnostic output.
    endpoint=$(printf '%s' "$KAZOO_AMQP_URI" | \
        python3 -B -I "$SCRIPT_DIR/kamailio-amqp-endpoint.py") || \
        die 'Could not parse the effective Kamailio AMQP endpoint'
    host=$(jq -r '.host' <<<"$endpoint")
    port=$(jq -r '.port' <<<"$endpoint")
    vhost=$(jq -r '.vhost' <<<"$endpoint")
    protocol=$(jq -r '.protocol' <<<"$endpoint")
    mapfile -t broker_addresses < <(
        getent ahosts "$host" | awk '{print $1}' | sort -u
    )
    ((${#broker_addresses[@]})) || \
        die 'Could not resolve the effective Kamailio AMQP host'
    deadline=$((SECONDS + KAZOO_START_TIMEOUT))
    while ((SECONDS < deadline)); do
        connections=$(ss -H -tnp state established \
            "( dport = :${port} )" 2>/dev/null || true)
        # Confined root can see sockets but lack permission to inspect another
        # UID's /proc descriptors. Inspect as the fixed service user instead;
        # still require the exact Kamailio process and effective broker peer.
        # This grants no extra capability and never accepts a bare TCP socket.
        if [[ $EUID == 0 && $connections != *'("kamailio",'* ]] && \
                command -v runuser >/dev/null 2>&1 && id kamailio >/dev/null 2>&1; then
            connections=$(runuser -u kamailio -- ss -H -tnp state established \
                "( dport = :${port} )" 2>/dev/null || true)
        fi
        for address in "${broker_addresses[@]}"; do
            # ss omits the state column when a state filter is supplied; peer
            # is field four. Literal comparison avoids regex/address ambiguity.
            if awk -v peer="${address}:${port}" -v peer6="[${address}]:${port}" \
                '($4 == peer || $4 == peer6) && index($0, "(\"kamailio\",") { found=1 }
                 END { exit !found }' <<<"$connections"; then
                log 'PASS Kamailio established transport to its effective AMQP endpoint'
                verify_kamailio_local_amqp_queues "$port" "$vhost" "$protocol" "$address" "${broker_addresses[@]}"
                return 0
            fi
        done
        sleep 2
    done
    die 'Kamailio has no established transport to its effective AMQP endpoint; run verification as root and check broker credentials/connectivity'
}

verify_kamailio_local_amqp_queues() {
    local port=$1 vhost=$2 protocol=$3 connected_address=$4 address local_addresses listeners queues
    shift 4
    systemctl is-active --quiet rabbitmq-server.service 2>/dev/null || {
        log 'Kamailio queue inspection skipped: no active local RabbitMQ service (transport only)'
        return 0
    }
    local_addresses=$(ip -j address show | jq -er '[.[].addr_info[].local] | .[]') || \
        die 'Could not determine local addresses for Kamailio broker verification'
    for address in "$@"; do
        if [[ $address != 127.* && $address != ::1 ]] && \
           ! grep -Fxq -- "$address" <<<"$local_addresses"; then
            log 'Kamailio queue inspection skipped: effective broker is remote or mixed-locality (transport only)'
            return 0
        fi
    done
    listeners=$(timeout --signal=TERM --kill-after=5 30 \
        rabbitmq-diagnostics -q listeners --formatter json 2>/dev/null) || \
        die 'Could not inspect local RabbitMQ listener identity for Kamailio'
    # The CLI's node must own the exact endpoint before its queue inventory
    # can prove anything. An unrelated local broker is not remote evidence.
    if ! jq -e -s --arg address "$connected_address" --argjson port "$port" --arg protocol "$protocol" '
        length == 1 and (.[0] | type == "object" and .result == "ok" and
            (.node | type) == "string" and (.node | length) > 0 and
            (.listeners | type) == "array" and
            any(.listeners[]; .port == $port and .protocol == $protocol and
                (.interface == $address or
                    (.interface == "0.0.0.0" and ($address | contains(":") | not)) or
                    (.interface == "::" and ($address | contains(":"))))))
    ' <<<"$listeners" >/dev/null 2>&1; then
        die 'Local RabbitMQ listener does not match the effective Kamailio AMQP endpoint'
    fi
    queues=$(timeout --signal=TERM --kill-after=5 30 \
        rabbitmqctl -q -p "$vhost" list_queues name 2>/dev/null) || \
        die 'Could not inspect Kamailio queues on the effective AMQP vhost'
    grep -F -- "kamailio@${KAZOO_HOSTNAME}-" <<<"$queues" | \
        awk -v prefix="kamailio@${KAZOO_HOSTNAME}-" 'index($0, prefix) == 1 { found=1 } END { exit !found }' || \
        die 'Kamailio did not create Kazoo AMQP consumer queues on the effective vhost'
    log 'PASS Kamailio consumer queues on the exact local AMQP endpoint and vhost'
}

install_kamailio() {
    log "Installing Kazoo Kamailio ${KAMAILIO_VERSION}"
    install_kamailio_packages
    configure_kazoo_kamailio
    run /usr/sbin/kazoo-kamailio check
    service_enable_restart kazoo-kamailio.service
    wait_for_port "$KAZOO_PUBLIC_IP" 5060 90 || die 'Kazoo Kamailio did not open port 5060'
    register_kamailio_sbc
    verify_kamailio
}

wait_kamailio_dispatcher_ready() {
    local deadline=$((SECONDS + KAZOO_START_TIMEOUT))
    while ((SECONDS < deadline)); do
        if python3 -B -I "$SCRIPT_DIR/kamailio-dispatcher-ready.py" >/dev/null 2>&1; then
            log 'PASS active Kamailio media destination in effective INVITE groups'
            return 0
        fi
        sleep 2
    done
    die 'Kamailio has no active destination in its effective primary/secondary INVITE groups'
}

verify_kamailio() {
    if [[ $DRY_RUN == true ]]; then log 'Would verify Kazoo Kamailio'; return 0; fi
    local pid seconds_alive wait_seconds
    assert_service kazoo-kamailio.service
    /usr/sbin/kamailio -v 2>&1 | grep -F "$KAMAILIO_VERSION" >/dev/null || \
        die "Installed Kamailio is not version ${KAMAILIO_VERSION}"
    /usr/sbin/kazoo-kamailio check >/dev/null || die 'Kazoo Kamailio configuration check failed'
    if grep -ER 'kazoo_(async_query|publish)\(.*REGISTRAR_AMQP_FLAGS' \
        "$KAZOO_CONFIG_DIR/kamailio" >/dev/null; then
        die 'Kamailio registrar still passes an incompatible optional AMQP-header argument'
    fi
    /usr/sbin/kamcmd core.version 2>/dev/null | grep -i kamailio >/dev/null || \
        die 'Kamailio RPC version check failed'
    /usr/sbin/kamailio -v 2>&1 | grep -i kazoo >/dev/null || \
        [[ -f /usr/lib64/kamailio/modules/kazoo.so ]] || \
        die 'Kamailio kazoo module is missing'
    systemctl is-enabled --quiet kamailio.service 2>/dev/null && \
        die 'The stock kamailio.service must be disabled in favor of kazoo-kamailio.service'
    sqlite3 -readonly "$KAZOO_CONFIG_DIR/kamailio/db/kazoo.db" 'PRAGMA integrity_check;' | \
        grep -Fx ok >/dev/null || die 'Kamailio SQLite database integrity check failed'
    sqlite3 -readonly "$KAZOO_CONFIG_DIR/kamailio/db/kazoo.db" \
        "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('dispatcher','tmp_probe') ORDER BY name;" | \
        grep -Fx dispatcher >/dev/null || die 'Kamailio dispatcher database table is missing'
    pid=$(systemctl show kazoo-kamailio.service -p MainPID --value)
    seconds_alive=$(ps -o etimes= -p "$pid" | tr -d '[:space:]')
    [[ $seconds_alive =~ ^[0-9]+$ ]] || die 'Could not determine Kamailio process age'
    wait_seconds=$((35 - seconds_alive))
    if ((wait_seconds > 0)); then
        log "Holding Kamailio integration check for ${wait_seconds}s"
        sleep "$wait_seconds"
    fi
    assert_service kazoo-kamailio.service
    [[ $(systemctl show kazoo-kamailio.service -p MainPID --value) == "$pid" ]] || \
        die 'Kamailio restarted during its integration check'
    check_sip_options "$KAZOO_PUBLIC_IP" 5060 || die 'Kamailio SIP OPTIONS check failed'
    verify_kamailio_amqp_connection
    [[ $(/usr/sbin/kamcmd cfg.get kazoo registrar_check_amqp_availability 2>/dev/null) == 0 ]] || \
        die 'Kamailio registrar has the incompatible AMQP XAVP availability guard enabled'
    if systemctl is-active --quiet kazoo-freeswitch.service 2>/dev/null && \
       systemctl is-active --quiet kazoo-ecallmgr.service 2>/dev/null; then
        wait_kamailio_dispatcher_ready
        verify_kamailio_sbc
    fi
    verify_kamailio_journal
    [[ $(systemctl show kazoo-kamailio.service -p MainPID --value) == "$pid" ]] || \
        die 'Kamailio restarted during its journal/JWT check'
    log 'PASS Kazoo Kamailio SIP, AMQP, dispatcher, database, RPC, and module checks'
}

verify_kamailio_journal() {
    local active_since active_usec boot_id stats query report
    active_since=$(systemctl show kazoo-kamailio.service -p ActiveEnterTimestamp --value)
    active_usec=$(systemctl show kazoo-kamailio.service -p ActiveEnterTimestampMonotonic --value)
    read -r boot_id < /proc/sys/kernel/random/boot_id
    boot_id=${boot_id//-/}
    [[ -n $active_since && $active_usec =~ ^[1-9][0-9]*$ ]] || die 'Could not bind Kamailio journal to service activation'
    stats=$(timeout --signal=KILL 10 /usr/sbin/kamcmd htable.stats) || die 'Could not read Kamailio JWT table statistics'
    query=$(timeout --signal=KILL 10 /usr/sbin/kamcmd pv.shvGet jwt_keys_query) || die 'Could not read Kamailio JWT retry state'
    report=$(timeout --signal=KILL 30 journalctl -u kazoo-kamailio.service --boot="$boot_id" \
        --since "$active_since" --output=json \
        --output-fields=_BOOT_ID,_PID,__MONOTONIC_TIMESTAMP,MESSAGE --no-pager 2>/dev/null | \
        python3 -B -I "$SCRIPT_DIR/verify-kamailio-jwt-journal.py" --boot-id "$boot_id" \
            --active-usec "$active_usec" --stats "$stats" --query "$query" --config-dir "$KAZOO_CONFIG_DIR") || \
        die "Kamailio journal/JWT verification failed: ${report}"
    [[ $(systemctl show kazoo-kamailio.service -p ActiveEnterTimestampMonotonic --value) == "$active_usec" ]] || \
        die 'Kamailio restarted while journal/JWT evidence was read'
    log "$report"
}

monster_app_ref() {
    case $1 in
        acdc) monster_local_app_fingerprint acdc ;;
        accounts) printf '%s\n' "$MONSTER_UI_ACCOUNTS_REF" ;;
        callflows) printf '%s\n' "$MONSTER_UI_CALLFLOWS_REF" ;;
        csv-onboarding) printf '%s\n' "$MONSTER_UI_CSV_ONBOARDING_REF" ;;
        fax) printf '%s\n' "$MONSTER_UI_FAX_REF" ;;
        numbers) printf '%s\n' "$MONSTER_UI_NUMBERS_REF" ;;
        pbxs) printf '%s\n' "$MONSTER_UI_PBXS_REF" ;;
        voicemails) printf '%s\n' "$MONSTER_UI_VOICEMAILS_REF" ;;
        webhooks) printf '%s\n' "$MONSTER_UI_WEBHOOKS_REF" ;;
        voip) printf '%s\n' "$MONSTER_UI_VOIP_REF" ;;
        *) die "Unsupported Monster UI app: $1" ;;
    esac
}

monster_local_app_fingerprint() {
    local app=$1 app_dir="$SCRIPT_DIR/../monster-ui/$1"
    [[ $app == acdc && -s $app_dir/app.js && -s $app_dir/metadata/app.json ]] || \
        die "Bundled Monster UI app ${app} is incomplete"
    [[ -z $(find "$app_dir" -type l -print -quit) ]] || \
        die "Bundled Monster UI app ${app} must not contain symbolic links"
    # Hash relative names as well as contents, independent of checkout path.
    (cd "$app_dir" && find . -type f -print0 | LC_ALL=C sort -z | \
        xargs -0 sha256sum | sha256sum | awk '{print "local-sha256:" $1}')
}

monster_ui_build_fingerprint() {
    local app ref entry digest node_version npm_version hooks
    local -a inputs=(
        framework_myaccount_patch:patches/monster-ui-myaccount-transition.patch
        monster-ui-branding-billing.patch:patches/monster-ui-branding-billing.patch
        monster-ui-account-picker-readiness.patch:patches/monster-ui-account-picker-readiness.patch
        monster-ui-background-app-load.patch:patches/monster-ui-background-app-load.patch
        monster-ui-app-load-singleflight.patch:patches/monster-ui-app-load-singleflight.patch
        monster-ui-websocket-config.patch:patches/monster-ui-websocket-config.patch
        monster-ui-websocket-subscription-lifecycle.patch:patches/monster-ui-websocket-subscription-lifecycle.patch
        monster-ui-dialog-resize-lifecycle.patch:patches/monster-ui-dialog-resize-lifecycle.patch
        monster-ui-request-indicator-lifecycle.patch:patches/monster-ui-request-indicator-lifecycle.patch
        monster-ui-bounded-sdk-reads.patch:patches/monster-ui-bounded-sdk-reads.patch
        monster-ui-optional-integrations.patch:patches/monster-ui-optional-integrations.patch
        monster-ui-storage-selector-errors.patch:patches/monster-ui-storage-selector-errors.patch
        monster-ui-isolated-minify.patch:patches/monster-ui-isolated-minify.patch
        monster-ui-preloaded-apps.patch:patches/monster-ui-preloaded-apps.patch
        runtime_configuration:configure-monster-runtime.cjs
        owned_deployment:deploy-owned-monster.cjs
        build_boundary:monster-build-inputs.cjs
        lock_audit_helper:audit-monster-lock.cjs
        installed_dependency_verifier:verify-monster-build-dependencies.cjs
        bounded_production_builder:build-monster-production.cjs
        production_artifact_verifier:verify-monster-production-artifact.cjs
        production_minifier_profile:assets/monster-ui/minifier-profile.json
        production_minifier_profile_helper:monster-minifier-profile.cjs
        build_package_lock:assets/monster-ui/package-lock.npm10.json
        npm_native_overrides_patch:patches/monster-ui-npm-native-overrides.patch
    )
    node_version=$(node --version) || die 'Cannot fingerprint Node version'
    npm_version=$(npm --version) || die 'Cannot fingerprint npm version'
    printf '%s\n' \
        "monster_ui=${MONSTER_UI_REF}" \
        "node=${MONSTER_UI_NODE_MAJOR}" \
        "node_actual=$node_version" \
        "npm_actual=$npm_version" \
        "source_package_lock=${MONSTER_UI_LOCK_SHA256}" \
        "api=${KAZOO_API_URL}" \
        "socket=${MONSTER_UI_WEBSOCKET_URL}" \
        "remote_branding=${MONSTER_UI_REMOTE_BRANDING}" \
        "braintree=${MONSTER_UI_BRAINTREE}"
    if [[ ",${MONSTER_UI_APPS_LIST}," == *',callflows,'* ]]; then
        inputs+=(callflows_acdc_queue_patch:patches/monster-ui-callflows-acdc-queue.patch
                 callflows_confirmation_patch:patches/monster-ui-call-forward-confirmation.patch
                 callflows_css_nesting_patch:patches/monster-ui-callflows-css-nesting.patch)
    fi
    if [[ ",${MONSTER_UI_APPS_LIST}," == *',voip,'* ]]; then
        inputs+=(smartpbx_loading_recovery_patch:patches/monster-ui-smartpbx-loading-recovery.patch)
    fi
    for entry in "${inputs[@]}"; do
        digest=$(sha256sum "$SCRIPT_DIR/${entry#*:}") || die "Cannot fingerprint ${entry%%:*}"
        digest=${digest%% *}
        [[ $digest =~ ^[a-f0-9]{64}$ ]] || die "Invalid fingerprint for ${entry%%:*}"
        printf '%s=%s\n' "${entry%%:*}" "$digest"
    done
    hooks=$(node "$SCRIPT_DIR/monster-build-inputs.cjs" --hook-hash "$SCRIPT_DIR/install-kazoo5.sh") || \
        die 'Cannot fingerprint installer build hooks'
    [[ $hooks =~ ^[a-f0-9]{64}$ ]] || die 'Invalid installer build hook fingerprint'
    printf 'installer_build_hooks=%s\n' "$hooks"
    for app in ${MONSTER_UI_APPS_LIST//,/ }; do
        ref=$(monster_app_ref "$app") || die "Cannot fingerprint selected app ${app}"
        printf 'app_%s=%s\n' "$app" "$ref"
    done
}

install_nodejs_toolchain() {
    local enabled_stream= module_inventory
    # --enabled exits 1 on a clean server with no enabled stream. Query all
    # streams so an empty selection is distinct from a repository/query error.
    module_inventory=$(LC_ALL=C dnf -q module list nodejs) || \
        die 'Cannot inspect available Node.js module streams'
    enabled_stream=$(awk '$1 == "nodejs" && /\[e\]/ {gsub(/[^0-9].*/, "", $2); print $2; exit}' \
        <<<"$module_inventory")
    if [[ $enabled_stream != "$MONSTER_UI_NODE_MAJOR" ]]; then
        if [[ -n $enabled_stream ]]; then
            dnf_transaction module switch-to -y "nodejs:${MONSTER_UI_NODE_MAJOR}/common"
        else
            dnf_transaction module enable -y "nodejs:${MONSTER_UI_NODE_MAJOR}"
        fi
    fi
    dnf_install nodejs npm
    if [[ $DRY_RUN != true ]]; then
        [[ $(node -p 'process.versions.node.split(".")[0]') == "$MONSTER_UI_NODE_MAJOR" ]] || \
            die "Kazoo build tools require Node.js ${MONSTER_UI_NODE_MAJOR}; installed version is $(node --version)"
    fi
}

install_monster_nodejs() {
    install_nodejs_toolchain
    dnf_install nginx
}

sync_monster_ui_sources() {
    local source_dir=$1
    local app ref app_dir callflows_patch myaccount_patch
    # This function accepts only an absent target inside an installer-created
    # protected stage. Never discard changes in an old source checkout.
    if [[ $DRY_RUN != true ]]; then
        node "$SCRIPT_DIR/monster-build-inputs.cjs" --absent-source "$source_dir"
    fi
    sync_git https://github.com/2600hz/monster-ui.git "$source_dir" "$MONSTER_UI_REF"
    if [[ $DRY_RUN != true ]]; then
        [[ $(git -C "$source_dir" rev-parse HEAD) == "$MONSTER_UI_REF" ]] || die 'Framework source pin mismatch'
        [[ $(sha256sum "$source_dir/package-lock.json" | awk '{print $1}') == "$MONSTER_UI_LOCK_SHA256" ]] || \
            die 'Framework dependency lock differs from its reviewed source hash'
    fi
    myaccount_patch="$SCRIPT_DIR/patches/monster-ui-myaccount-transition.patch"
    [[ -s $myaccount_patch ]] || die 'Required Monster UI MyAccount transition patch is missing'
    if [[ $DRY_RUN == true ]]; then
        log 'Would apply the MyAccount late-transition visibility fix'
    elif git -C "$source_dir" apply --check "$myaccount_patch" 2>/dev/null; then
        git -C "$source_dir" apply "$myaccount_patch"
    elif ! git -C "$source_dir" apply --reverse --check "$myaccount_patch" 2>/dev/null; then
        die 'Monster UI source does not match the MyAccount visibility patch'
    fi
    apply_required_source_patch "$source_dir" "$SCRIPT_DIR/patches/monster-ui-branding-billing.patch"
    apply_required_source_patch "$source_dir" "$SCRIPT_DIR/patches/monster-ui-account-picker-readiness.patch"
    apply_required_source_patch "$source_dir" "$SCRIPT_DIR/patches/monster-ui-background-app-load.patch"
    apply_required_source_patch "$source_dir" "$SCRIPT_DIR/patches/monster-ui-app-load-singleflight.patch"
    apply_required_source_patch "$source_dir" "$SCRIPT_DIR/patches/monster-ui-websocket-config.patch"
    apply_required_source_patch "$source_dir" "$SCRIPT_DIR/patches/monster-ui-websocket-subscription-lifecycle.patch"
    apply_required_source_patch "$source_dir" "$SCRIPT_DIR/patches/monster-ui-dialog-resize-lifecycle.patch"
    apply_required_source_patch "$source_dir" "$SCRIPT_DIR/patches/monster-ui-request-indicator-lifecycle.patch"
    apply_required_source_patch "$source_dir" "$SCRIPT_DIR/patches/monster-ui-bounded-sdk-reads.patch"
    apply_required_source_patch "$source_dir" "$SCRIPT_DIR/patches/monster-ui-optional-integrations.patch"
    apply_required_source_patch "$source_dir" "$SCRIPT_DIR/patches/monster-ui-storage-selector-errors.patch"
    apply_required_source_patch "$source_dir" "$SCRIPT_DIR/patches/monster-ui-isolated-minify.patch"
    apply_required_source_patch "$source_dir" "$SCRIPT_DIR/patches/monster-ui-preloaded-apps.patch"
    apply_required_source_patch "$source_dir" "$SCRIPT_DIR/patches/monster-ui-npm-native-overrides.patch"
    if [[ $DRY_RUN != true ]]; then
        node "$SCRIPT_DIR/monster-build-inputs.cjs" --prepare-lock "$source_dir" \
            "$SCRIPT_DIR/assets/monster-ui/package-lock.npm10.json"
    fi
    for app in ${MONSTER_UI_APPS_LIST//,/ }; do
        ref=$(monster_app_ref "$app")
        app_dir="$source_dir/src/apps/$app"
        if [[ $DRY_RUN != true ]]; then
            node "$SCRIPT_DIR/monster-build-inputs.cjs" --absent-source "$app_dir"
        fi
        if [[ $app == acdc ]]; then
            run mkdir -p "$app_dir"
            run cp -a "$SCRIPT_DIR/../monster-ui/acdc/." "$app_dir/"
            log "Bundled Monster UI ACDC Call Center app: ${ref}"
            continue
        fi
        sync_git "https://github.com/2600hz/monster-ui-${app}.git" "$app_dir" "$ref"
        if [[ $DRY_RUN != true ]]; then
            [[ $(git -C "$app_dir" rev-parse HEAD 2>/dev/null || true) == "$ref" ]] || \
                die "Monster UI app ${app} is not at its pinned revision"
            [[ -s $app_dir/metadata/app.json ]] || \
                die "Monster UI app ${app} has no metadata/app.json"
        fi
    done
    if [[ ",${MONSTER_UI_APPS_LIST}," == *',voip,'* ]]; then
        apply_required_source_patch "$source_dir/src/apps/voip" \
            "$SCRIPT_DIR/patches/monster-ui-smartpbx-loading-recovery.patch"
    fi
    if [[ ",${MONSTER_UI_APPS_LIST}," == *',callflows,'* ]]; then
        callflows_patch="$SCRIPT_DIR/patches/monster-ui-callflows-css-nesting.patch"
        [[ -f $callflows_patch ]] || \
            die "Required Monster UI Callflows CSS patch is missing: ${callflows_patch}"
        app_dir="$source_dir/src/apps/callflows"
        if [[ $DRY_RUN == true ]]; then
            log 'Would apply the Callflows production-CSS compatibility patch'
        elif git -C "$app_dir" apply --check "$callflows_patch" 2>/dev/null; then
            git -C "$app_dir" apply "$callflows_patch"
            log 'Applied Monster UI Callflows production-CSS compatibility patch'
        elif git -C "$app_dir" apply --reverse --check "$callflows_patch" 2>/dev/null; then
            log 'Monster UI Callflows production-CSS compatibility patch is already applied'
        else
            die 'Monster UI Callflows source does not match the required CSS compatibility patch'
        fi
        apply_required_source_patch "$app_dir" \
            "$SCRIPT_DIR/patches/monster-ui-callflows-acdc-queue.patch"
        apply_required_source_patch "$app_dir" \
            "$SCRIPT_DIR/patches/monster-ui-call-forward-confirmation.patch"
    fi
}

configure_monster_ui_api() {
    local source_dir=$1
    [[ $DRY_RUN != true ]] || return 0
    node "$SCRIPT_DIR/monster-build-inputs.cjs" --configure "$MONSTER_UI_WEB_ROOT" "$source_dir" \
        "$KAZOO_API_URL" "$MONSTER_UI_WEBSOCKET_URL" "$MONSTER_UI_REMOTE_BRANDING" "$MONSTER_UI_BRAINTREE"
    node "$SCRIPT_DIR/configure-monster-runtime.cjs" "$source_dir/src/js/config.js" \
        "$KAZOO_API_URL" "$MONSTER_UI_WEBSOCKET_URL" "$MONSTER_UI_REMOTE_BRANDING" "$MONSTER_UI_BRAINTREE"
    if [[ ",${MONSTER_UI_APPS_LIST}," == *',acdc,'* ]]; then
        jq --arg api "$KAZOO_API_URL" '.api_url = $api' \
            "$source_dir/src/apps/acdc/metadata/app.json" | \
            write_file 0644 "$source_dir/src/apps/acdc/metadata/app.json"
    fi
}

monster_registration_available() {
    command -v sup >/dev/null && systemctl is-active --quiet kazoo-apps.service 2>/dev/null
}

monster_catalog_preflight() {
    [[ ${SELECTED[monster-ui]:-} ]] || return 0
    local value path owner mode
    if [[ $MONSTER_UI_REGISTER_APPS == false ]]; then
        MONSTER_CATALOG_MODE=disabled
        return 0
    fi
    value="${MONSTER_UI_CATALOG_SSH_HOST}${MONSTER_UI_CATALOG_SSH_USER}${MONSTER_UI_CATALOG_IDENTITY_FILE}${MONSTER_UI_CATALOG_KNOWN_HOSTS_FILE}${MONSTER_UI_CATALOG_MASTER_ID}"
    if [[ -n $value || $MONSTER_UI_CATALOG_SSH_PORT != 22 ]]; then
        MONSTER_CATALOG_MODE=remote
        [[ $MONSTER_UI_CATALOG_SSH_HOST =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ && \
           $MONSTER_UI_CATALOG_SSH_USER =~ ^[a-z_][a-z0-9_-]{0,31}$ && \
           $MONSTER_UI_CATALOG_MASTER_ID =~ ^[0-9a-f]{32}$ ]] || \
            die 'Remote catalog requires explicit SSH host/user and expected 32-hex master ID; no authority is inferred from API URLs'
        validate_port MONSTER_UI_CATALOG_SSH_PORT "$MONSTER_UI_CATALOG_SSH_PORT"
        for path in "$MONSTER_UI_CATALOG_IDENTITY_FILE" "$MONSTER_UI_CATALOG_KNOWN_HOSTS_FILE"; do
            [[ $path =~ ^/[a-zA-Z0-9_./-]+$ && -f $path && ! -L $path ]] || \
                die 'Remote catalog requires explicit protected identity and pinned known-hosts files'
            read -r owner mode < <(stat -c '%u %a' "$path")
            [[ $owner == 0 && $mode == 600 ]] || die 'Remote catalog authority files must be root-owned mode 0600'
        done
    elif [[ ${SELECTED[kazoo-apps]:-} ]] || monster_registration_available; then
        MONSTER_CATALOG_MODE=local
    else
        die 'Standalone Monster UI requires explicit remote catalog authority; use MONSTER_UI_REGISTER_APPS=false only for a deliberate assets-only deployment'
    fi
}

monster_catalog_remote() {
    local action=$1 source_hash
    shift
    [[ $MONSTER_CATALOG_MODE == remote ]] || die 'Remote catalog authority was not preflighted'
    if [[ $DRY_RUN == true ]]; then
        log "Would perform pinned remote catalog ${action}; no SSH or catalog changes in dry run"
        return 0
    fi
    source_hash=$(sha256sum "$SCRIPT_DIR/monster-catalog-transport.py" | awk '{print $1}')
    python3 -B -I "$SCRIPT_DIR/monster-catalog-transport.py" "$action" \
        "$MONSTER_UI_CATALOG_SSH_HOST" "$MONSTER_UI_CATALOG_SSH_USER" "$MONSTER_UI_CATALOG_SSH_PORT" \
        "$MONSTER_UI_CATALOG_IDENTITY_FILE" "$MONSTER_UI_CATALOG_KNOWN_HOSTS_FILE" \
        "$MONSTER_UI_CATALOG_MASTER_ID" "$source_hash" "$@" || \
        die 'Remote catalog was not verified; no automatic retry, overwrite or rollback. Review the exact apps-node target before rerunning'
}

install_monster_catalog_receiver() {
    # Fixed receiver, no SSH server/identity/authorized-keys/sudoers provisioning.
    dnf_install sudo
    run python3 -B -I "$SCRIPT_DIR/monster-catalog-transport.py" --install-receiver \
        "$KAZOO_ROOT" "$KAZOO_CONFIG_DIR/core/config.ini" "$KAZOO_HOSTNAME" "$KAZOO_NODE_NAME_TYPE"
}

verify_monster_app_registration() {
    local registered app account_id account_db
    if [[ $MONSTER_CATALOG_MODE == remote ]]; then
        monster_catalog_remote --verify "$MONSTER_UI_WEB_ROOT" "$KAZOO_API_URL" "$MONSTER_UI_APPS_LIST"
        return 0
    fi
    if [[ $MONSTER_CATALOG_MODE == disabled || $MONSTER_UI_REGISTER_APPS == false ]]; then
        log 'Catalog registration explicitly disabled: assets-only scope, cluster catalog integration not verified'
        return 0
    fi
    if ! monster_registration_available; then
        die 'Local Monster UI catalog verification requires SUP and an active kazoo-apps.service'
    fi
    [[ $MONSTER_UI_REGISTER_APPS != false ]] || return 0
    account_id=$(configured_master_account_id) || die 'Cannot verify app catalog without a configured master account'
    account_db="account%2F${account_id:0:2}%2F${account_id:2:2}%2F${account_id:4}"
    # Direct read-only view access avoids maintenance:apps/0's implicit
    # master-account discovery and view repair when prerequisites are absent.
    registered=$(couchdb_curl --fail --silent --show-error --connect-timeout 5 --max-time 30 \
        "http://${KAZOO_COUCHDB_HOST}:${KAZOO_COUCHDB_PORT}/${account_db}/_design/apps_store/_view/crossbar_listing") || \
        die 'Could not read the existing Monster UI app catalog view'
    for app in ${MONSTER_UI_APPS_LIST//,/ }; do
        jq -e --arg app "$app" '(.rows | type == "array") and ([.rows[] | select(.key == $app)] | length == 1)' \
            <<<"$registered" >/dev/null || \
            die "Monster UI app ${app} must have exactly one registration in the Kazoo master account"
    done
    log "PASS Monster UI app catalog registration: ${MONSTER_UI_APPS_LIST}"
}

register_monster_apps() {
    local output app
    [[ $DRY_RUN != true ]] || return 0
    if [[ $MONSTER_CATALOG_MODE == remote ]]; then
        monster_catalog_remote --install "$MONSTER_UI_WEB_ROOT" "$KAZOO_API_URL" "$MONSTER_UI_APPS_LIST"
        verify_monster_app_registration
        return 0
    fi
    if [[ $MONSTER_CATALOG_MODE == disabled || $MONSTER_UI_REGISTER_APPS == false ]]; then
        log 'Catalog registration explicitly disabled: assets-only scope, no cluster catalog changes'
        return 0
    fi
    if ! monster_registration_available; then
        die 'Local Monster UI catalog registration requires SUP and an active kazoo-apps.service'
    fi
    [[ $MONSTER_UI_REGISTER_APPS != false ]] || {
        log 'Monster UI app registration disabled by MONSTER_UI_REGISTER_APPS=false'
        return 0
    }
    ensure_master_account
    configure_kazoo_api_modules
    # The packaged module preserves every existing document and image. No
    # fallback to init_apps/init_app: those replace existing image attachments.
    for app in ${MONSTER_UI_APPS_LIST//,/ }; do
        if ! output=$(timeout --signal=KILL 60 sup kazoo_monster_catalog init_app \
            "$app" "$MONSTER_UI_WEB_ROOT/apps/$app" "$KAZOO_API_URL" </dev/null 2>&1); then
            die "App registration interrupted for ${app}; inspect its exact target before retrying"
        fi
        [[ $output == created || $output == preserved ]] || \
            die "App registration not verified for ${app}; no automatic update, rollback or retry"
        log "PASS selected catalog ${app}: ${output}"
    done
    verify_monster_app_registration
}

validate_tls_configuration() {
    local path cert_public key_public
    [[ $KAZOO_DEPLOYMENT_CONFIG == /* && $KAZOO_DEPLOYMENT_CONFIG != / && \
       ! $KAZOO_DEPLOYMENT_CONFIG =~ [[:cntrl:]] ]] || \
        die 'KAZOO_DEPLOYMENT_CONFIG must be an absolute file path'
    [[ ${SELECTED[monster-ui]:-} ]] || return 0
    if [[ -z $KAZOO_PUBLIC_HOSTNAME && -z $KAZOO_TLS_CERT_FILE && \
          -z $KAZOO_TLS_KEY_FILE && -z $KAZOO_TLS_CHAIN_FILE ]]; then return 0; fi
    is_public_dns_hostname "$KAZOO_PUBLIC_HOSTNAME" || \
        die 'A valid public DNS hostname is required for TLS'
    [[ -n $KAZOO_TLS_CERT_FILE && -n $KAZOO_TLS_KEY_FILE ]] || \
        die 'HTTPS requires both KAZOO_TLS_CERT_FILE and KAZOO_TLS_KEY_FILE'
    [[ $KAZOO_API_URL == https://* ]] || \
        die 'Monster UI served over HTTPS requires an HTTPS KAZOO_API_URL'
    [[ $KAZOO_API_UPSTREAM =~ ^https?://[a-zA-Z0-9._:-]+/v2/$ ]] || \
        die 'KAZOO_API_UPSTREAM must be an http(s) host[:port]/v2/ URL without credentials'
    for path in "$KAZOO_TLS_CERT_FILE" "$KAZOO_TLS_KEY_FILE" "$KAZOO_TLS_CHAIN_FILE"; do
        [[ -n $path ]] || continue
        [[ $path == /* && $path != / && ! $path =~ [[:cntrl:]] ]] || \
            die 'TLS input files must use absolute file paths without control characters'
        if [[ $DRY_RUN != true ]]; then
            [[ -s $path && -r $path ]] || die "TLS input file is missing or unreadable: ${path}"
        fi
    done
    [[ $DRY_RUN != true ]] || return 0
    openssl x509 -in "$KAZOO_TLS_CERT_FILE" -noout -checkhost "$KAZOO_PUBLIC_HOSTNAME" >/dev/null || \
        die 'TLS certificate does not cover the configured hostname'
    openssl x509 -in "$KAZOO_TLS_CERT_FILE" -noout -checkend 86400 >/dev/null || \
        die 'TLS certificate is expired or expires within one day'
    openssl pkey -in "$KAZOO_TLS_KEY_FILE" -passin pass: -check -noout >/dev/null 2>&1 || \
        die 'TLS key is invalid or encrypted; unattended nginx requires an unencrypted, protected key file'
    cert_public=$(openssl x509 -in "$KAZOO_TLS_CERT_FILE" -pubkey -noout | openssl pkey -pubin -outform DER | sha256sum)
    key_public=$(openssl pkey -in "$KAZOO_TLS_KEY_FILE" -passin pass: -pubout -outform DER | sha256sum)
    [[ $cert_public == "$key_public" ]] || die 'TLS certificate and private key do not match'
    openssl verify -purpose sslserver -verify_hostname "$KAZOO_PUBLIC_HOSTNAME" \
        -untrusted "${KAZOO_TLS_CHAIN_FILE:-$KAZOO_TLS_CERT_FILE}" "$KAZOO_TLS_CERT_FILE" >/dev/null || \
        die 'TLS certificate chain is incomplete or not trusted by this server'
}

install_api_developer_docs() {
    # Committed static assets only: no npm, external validator, API calls or credentials.
    run node "$SCRIPT_DIR/verify-api-docs.cjs" "$SCRIPT_DIR/assets/api-docs"
    if [[ $DRY_RUN != true ]]; then
        [[ ! -L $MONSTER_UI_WEB_ROOT/apis ]] || die 'Refusing a symlinked API documentation directory'
    fi
    run node "$SCRIPT_DIR/verify-api-docs.cjs" --check-target "$MONSTER_UI_WEB_ROOT/apis"
    run install -d -m 0755 "$MONSTER_UI_WEB_ROOT/apis"
    run cp -a "$SCRIPT_DIR/assets/api-docs/." "$MONSTER_UI_WEB_ROOT/apis/"
    # Public static documentation only; cp -a can preserve a root-only umask.
    run chmod 0755 "$MONSTER_UI_WEB_ROOT/apis" "$MONSTER_UI_WEB_ROOT/apis/vendor"
    local docs_asset
    for docs_asset in index.html portal.js portal.css openapi.json planned.openapi.json \
        blackhole.html coverage.json manifest.json vendor/LICENSE vendor/NOTICE \
        vendor/swagger-ui-bundle.js vendor/swagger-ui.css; do
        run chmod 0644 "$MONSTER_UI_WEB_ROOT/apis/$docs_asset"
    done
    run node "$SCRIPT_DIR/verify-api-docs.cjs" "$MONSTER_UI_WEB_ROOT/apis"
}

monster_ui_crossbar_proxy() {
    # One route contract for both transports; HTTP must never claim HTTPS or
    # send Crossbar failures into the single-page application's HTML fallback.
    cat <<EOF
    location = /v2 { return 308 /v2/\$is_args\$args; }
    location ^~ /v2/ {
        proxy_pass ${KAZOO_API_UPSTREAM};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Connection "";
        proxy_connect_timeout 10s;
        proxy_read_timeout 120s;
        proxy_intercept_errors off;
        proxy_ssl_server_name on;
        proxy_ssl_verify on;
        proxy_ssl_trusted_certificate /etc/pki/tls/certs/ca-bundle.crt;
        client_max_body_size 50m;
    }
EOF
}

configure_monster_ui_nginx() {
    local tls_dir=/etc/nginx/kazoo-tls
    [[ $KAZOO_API_UPSTREAM =~ ^https?://[a-zA-Z0-9._:-]+/v2/$ ]] || \
        die 'KAZOO_API_UPSTREAM must be an http(s) host[:port]/v2/ URL without credentials'
    [[ $KAZOO_WEBSOCKET_UPSTREAM =~ ^https?://[a-zA-Z0-9._:-]+/websocket$ ]] || \
        die 'KAZOO_WEBSOCKET_UPSTREAM must be an http(s) host[:port]/websocket URL without credentials'
    if [[ -n $KAZOO_PUBLIC_HOSTNAME ]]; then
        run install -d -m 0700 "$tls_dir"
        {
            if [[ $DRY_RUN != true ]]; then
                cat "$KAZOO_TLS_CERT_FILE"
                [[ -z $KAZOO_TLS_CHAIN_FILE ]] || cat "$KAZOO_TLS_CHAIN_FILE"
            fi
        } | write_file 0644 "$tls_dir/fullchain.pem"
        run install -m 0600 "$KAZOO_TLS_KEY_FILE" "$tls_dir/privkey.pem"
        write_file 0644 /etc/nginx/conf.d/monster-ui.conf <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name ${KAZOO_PUBLIC_HOSTNAME};
    return 308 https://${KAZOO_PUBLIC_HOSTNAME}\$request_uri;
}

server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    server_name ${KAZOO_PUBLIC_HOSTNAME};
    ssl_certificate ${tls_dir}/fullchain.pem;
    ssl_certificate_key ${tls_dir}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:KazooTLS:10m;
    ssl_session_timeout 10m;
    server_tokens off;
    root ${MONSTER_UI_WEB_ROOT};
    index index.html;
    client_max_body_size 50m;

    location = /websocket {
        proxy_pass ${KAZOO_WEBSOCKET_UPSTREAM};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_buffering off;
        proxy_ssl_server_name on;
        proxy_ssl_verify on;
        proxy_ssl_trusted_certificate /etc/pki/tls/certs/ca-bundle.crt;
    }

    location = /apis { return 308 /apis/; }
    location ^~ /apis/ {
        index index.html;
        try_files \$uri \$uri/ =404;
        add_header Cache-Control "no-store" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "no-referrer" always;
        add_header Content-Security-Policy "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'none'" always;
    }

$(monster_ui_crossbar_proxy)

    location = /apps/acdc/language-capabilities.json {
        default_type application/json;
        add_header Cache-Control "no-store" always;
        try_files \$uri =404;
    }

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
        if [[ $DRY_RUN != true ]] && command -v restorecon >/dev/null; then
            restorecon -RF "$tls_dir"
        fi
    else
        write_file 0644 /etc/nginx/conf.d/monster-ui.conf <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _monster_ui_default_;
    root ${MONSTER_UI_WEB_ROOT};
    index index.html;

$(monster_ui_crossbar_proxy)

    location = /apis { return 308 /apis/; }
    location ^~ /apis/ {
        index index.html;
        try_files \$uri \$uri/ =404;
        add_header Cache-Control "no-store" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "no-referrer" always;
        add_header Content-Security-Policy "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'none'" always;
    }

    location = /websocket {
        proxy_pass ${KAZOO_WEBSOCKET_UPSTREAM};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_buffering off;
        proxy_ssl_server_name on;
        proxy_ssl_verify on;
        proxy_ssl_trusted_certificate /etc/pki/tls/certs/ca-bundle.crt;
    }

    location = /apps/acdc/language-capabilities.json {
        default_type application/json;
        add_header Cache-Control "no-store" always;
        try_files \$uri =404;
    }

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
    fi
    # Both HTTP and HTTPS proxy Crossbar and the Blackhole WebSocket.
    if [[ $DRY_RUN != true ]] && command -v getenforce >/dev/null && \
       [[ $(getenforce) != Disabled ]]; then
        run setsebool -P httpd_can_network_connect on
    fi
}

verify_monster_ui_transport() {
    local redirect capability_url capability_status expected_capability_status=404
    local api_proxy_url api_proxy_result api_proxy_status api_proxy_body
    local ui_url asset asset_url expected_asset_hash served_asset_hash
    local -a capability_resolve=()
    if [[ -n $KAZOO_PUBLIC_HOSTNAME ]]; then
        ui_url="https://${KAZOO_PUBLIC_HOSTNAME}"
        capability_url="https://${KAZOO_PUBLIC_HOSTNAME}/apps/acdc/language-capabilities.json"
        api_proxy_url="https://${KAZOO_PUBLIC_HOSTNAME}/v2/"
        capability_resolve=(--noproxy '*' --resolve "${KAZOO_PUBLIC_HOSTNAME}:443:127.0.0.1")
        redirect=$(curl --disable --noproxy '*' --silent --show-error --output /dev/null --write-out '%{http_code} %{redirect_url}' \
            --connect-timeout 10 --max-time 30 --resolve "${KAZOO_PUBLIC_HOSTNAME}:80:127.0.0.1" \
            "http://${KAZOO_PUBLIC_HOSTNAME}/") || die 'Monster UI HTTP redirect check failed'
        [[ $redirect == "308 https://${KAZOO_PUBLIC_HOSTNAME}/" ]] || \
            die 'Monster UI HTTP does not redirect to the configured HTTPS hostname'
        [[ $(stat -c '%a:%U' /etc/nginx/kazoo-tls/privkey.pem) == 600:root ]] || \
            die 'nginx TLS private key must be root-owned with mode 0600'
    else
        ui_url=http://127.0.0.1
        capability_url=http://127.0.0.1/apps/acdc/language-capabilities.json
        api_proxy_url=http://127.0.0.1/v2/
        capability_resolve=(--noproxy '*' --header "Host: ${KAZOO_PUBLIC_IP}")
    fi
    # verify_monster_ui_owned has already bound this configured root and its
    # exact files/configuration to the ownership receipt. Include HTTP 200 in
    # the hash input so a redirect body cannot pass as an installed asset.
    # Keep the bytes in pipelines; shell variables would strip trailing LFs.
    for asset in index.html js/main.js js/config.js; do
        asset_url="${ui_url}/${asset}"
        [[ $asset != index.html ]] || asset_url="${ui_url}/"
        expected_asset_hash=$({ cat -- "$MONSTER_UI_WEB_ROOT/$asset" && printf '\n200'; } | \
            sha256sum | awk '{print $1}') || die "Cannot hash installed Monster UI asset ${asset}"
        served_asset_hash=$(curl --disable --fail --silent --show-error --connect-timeout 10 --max-time 30 \
            --max-filesize 20971520 --header 'Accept-Encoding: identity' "${capability_resolve[@]}" \
            --write-out $'\n%{http_code}' "$asset_url" | sha256sum | awk '{print $1}') || \
            die "Cannot retrieve served Monster UI asset ${asset}"
        [[ $served_asset_hash == "$expected_asset_hash" ]] || \
            die "Served Monster UI asset ${asset} does not match the verified configured web root with HTTP 200"
    done
    log 'PASS served Monster UI index, main bundle and configuration match the verified owned deployment'
    if [[ -n $KAZOO_PUBLIC_HOSTNAME ]]; then
        log "PASS HTTPS certificate, hostname, content, and HTTP redirect: ${KAZOO_PUBLIC_HOSTNAME}"
    fi
    if [[ -e $MONSTER_UI_WEB_ROOT/apps/acdc/language-capabilities.json ]]; then
        monster_language_capability_hash >/dev/null || die 'Invalid installed language capability file'
        expected_capability_status=200
    fi
    capability_status=$(curl --disable --silent --show-error --connect-timeout 10 --max-time 30 \
        "${capability_resolve[@]}" --output /dev/null --write-out '%{http_code}' "$capability_url") || \
        die 'Monster UI language capability route is unreachable'
    [[ $capability_status == "$expected_capability_status" ]] || \
        die 'Language capability route must return its actual file or HTTP 404, never the HTML application fallback'
    api_proxy_result=$(curl --disable --silent --show-error --connect-timeout 10 --max-time 30 \
        "${capability_resolve[@]}" --write-out $'\n%{http_code}' "$api_proxy_url") || \
        die 'Same-origin Crossbar proxy is unreachable'
    api_proxy_status=${api_proxy_result##*$'\n'}
    api_proxy_body=${api_proxy_result%$'\n'*}
    [[ $api_proxy_status =~ ^[234][0-9][0-9]$ ]] && \
        jq -e 'type == "object" and (.status == "success" or .status == "error")' <<<"$api_proxy_body" >/dev/null || \
        die 'Same-origin /v2/ must return a Crossbar JSON response, never the HTML application fallback'
    log 'PASS same-origin Crossbar proxy and JSON response (transport security depends on configured HTTP/HTTPS)'
}

monster_language_capability_hash() {
    node - "$SCRIPT_DIR/validate-acdc-language-capabilities.cjs" \
        "$MONSTER_UI_WEB_ROOT/apps/acdc/language-capabilities.json" <<'JS'
const fs = require('node:fs'), crypto = require('node:crypto'), assert = require('node:assert/strict');
const [validator, file] = process.argv.slice(2);
if (!fs.existsSync(file)) { console.log('absent'); process.exit(0); }
const stat = fs.lstatSync(file);
assert(stat.isFile() && !stat.isSymbolicLink() && stat.uid === 0 && (stat.mode & 0o022) === 0 && stat.size <= 131072,
    'Runtime language readiness must be a protected root-owned regular file');
const bytes = fs.readFileSync(file);
require(validator).assertLanguageCapabilities(JSON.parse(bytes.toString('utf8')));
console.log(crypto.createHash('sha256').update(bytes).digest('hex'));
JS
}

deploy_monster_ui_owned() {
    local source_dir=$1 state=/usr/local/share/kazoo5-installer/monster-ui-owned
    local plan_dir approval configuration_change=null build_inputs build_fingerprint
    build_inputs=$(monster_ui_build_fingerprint) || die 'Cannot fingerprint build before deployment planning'
    build_fingerprint=$(printf '%s\n' "$build_inputs" | sha256sum | awk '{print $1}') || \
        die 'Cannot hash build inputs before deployment planning'
    plan_dir=$(mktemp -d "$KAZOO_BUILD_ROOT/monster-owned-plan.XXXXXX")
    if [[ -f $source_dir/.kazoo-configuration-plan.json ]]; then
        configuration_change=$(jq -c . "$source_dir/.kazoo-configuration-plan.json")
    fi
    jq -n --arg web "$MONSTER_UI_WEB_ROOT" --arg stage "$source_dir/dist" --arg state "$state" \
        --arg selected "$MONSTER_UI_APPS_LIST" \
        --argjson configuration_change "$configuration_change" \
        --arg fingerprint "$build_fingerprint" \
        '{web:$web,stage:$stage,state:$state,selected:($selected|split(",")),inputs:{fingerprint_sha256:$fingerprint},adopt_existing:false,configuration_change:$configuration_change}' \
        | write_file 0600 "$plan_dir/options.json"
    # Legacy nonempty deployments without an ownership receipt fail closed.
    # Retain this stage, then separately review a fresh explicit adoption plan;
    # never infer ownership from a legacy marker, name, URL or directory alone.
    node "$SCRIPT_DIR/deploy-owned-monster.cjs" --plan "$plan_dir/options.json" \
        | write_file 0600 "$plan_dir/result.json"
    jq '.plan' "$plan_dir/result.json" | write_file 0600 "$plan_dir/plan.json"
    approval=$(jq -er '.approval_sha256' "$plan_dir/result.json")
    node "$SCRIPT_DIR/deploy-owned-monster.cjs" --apply "$plan_dir/plan.json" "$approval" "$plan_dir/rollback"
    build_inputs=$(monster_ui_build_fingerprint) || die 'Cannot recheck build fingerprint after deployment'
    verify_monster_ui_owned "$build_inputs"
}

verify_monster_ui_owned() {
    local expected_build=$1 result
    result=$(node "$SCRIPT_DIR/deploy-owned-monster.cjs" --verify \
        /usr/local/share/kazoo5-installer/monster-ui-owned/owned.json) || die 'Owned Monster UI output verification failed'
    jq -e --arg web "$MONSTER_UI_WEB_ROOT" --arg fingerprint "$(printf '%s\n' "$expected_build" | sha256sum | awk '{print $1}')" \
        '.status == "complete" and .web == $web and .fingerprint_sha256 == $fingerprint' <<<"$result" >/dev/null || \
        die 'Owned Monster UI output does not match its requested source/lock/patch fingerprint'
}

install_monster_ui() {
    (
    local source_dir stage_dir workflow_lock build_lock_sha
    local state=/usr/local/share/kazoo5-installer/monster-ui-owned
    local marker=/usr/local/share/kazoo5-installer/monster-ui-build
    local expected_build installed_build='' runtime_capability_hash
    log 'Installing pinned Monster UI and selected apps with owned-asset preservation'
    if [[ $MONSTER_CATALOG_MODE == remote ]]; then
        dnf_install openssh-clients
        # Read-only authority/version/master check before Node, asset staging,
        # source sync, web-root replacement, nginx configuration, or restarts.
        monster_catalog_remote --check
    fi
    install_monster_nodejs
    if [[ $DRY_RUN == true ]]; then
        log 'Would create a fresh protected Monster UI source stage; existing checkouts and unselected apps remain untouched'
        sync_monster_ui_sources "$KAZOO_BUILD_ROOT/monster-owned-dry-run/source"
        log 'Would build selected apps using the verified lock, plan bounded owned deployment, verify content, then register missing selected catalog apps only'
        install_api_developer_docs
        configure_monster_ui_nginx
        return 0
    fi
    node "$SCRIPT_DIR/monster-build-inputs.cjs" --prepare-roots "$MONSTER_UI_WEB_ROOT" "$state" "$KAZOO_BUILD_ROOT"
    workflow_lock="$state/workflow.lock"
    mkdir -m 0700 "$workflow_lock" || die 'Monster UI workflow is locked; inspect any previous incomplete installation before retrying'
    trap 'rmdir -- "$workflow_lock" 2>/dev/null || true' EXIT
    expected_build=$(monster_ui_build_fingerprint)
    [[ -r $marker ]] && installed_build=$(<"$marker")
    if [[ -e $state/owned.json ]]; then
        # Refuse changed managed files/config even if a rebuild was requested.
        node "$SCRIPT_DIR/deploy-owned-monster.cjs" --verify "$state/owned.json" \
            | jq -e --arg web "$MONSTER_UI_WEB_ROOT" '.status == "complete" and .web == $web' >/dev/null \
            || die 'Owned Monster UI web root/content verification failed'
    fi
    if [[ $installed_build != "$expected_build" || ! -s $MONSTER_UI_WEB_ROOT/index.html || ! -e $state/owned.json ]]; then
        stage_dir=$(node "$SCRIPT_DIR/monster-build-inputs.cjs" --new-stage "$KAZOO_BUILD_ROOT")
        source_dir="$stage_dir/source"
        log "Retaining private build and recovery evidence in ${stage_dir}"
        sync_monster_ui_sources "$source_dir"
        configure_monster_ui_api "$source_dir"
        build_lock_sha=$(sha256sum "$SCRIPT_DIR/assets/monster-ui/package-lock.npm10.json" | awk '{print $1}')
        (
            cd "$source_dir"
            [[ $(sha256sum package-lock.json | awk '{print $1}') == "$build_lock_sha" ]] || die 'Dependency lock changed before npm ci'
            # No unpinned root preinstall resolver; run only the explicitly
            # required, pinned native Sass/RE2 lifecycles after a consistent ci.
            # npm otherwise sizes V8 against host RAM and can exhaust a smaller
            # build cgroup before GC. Bound dependency resolution/downloads too,
            # not only the later production minifier workers.
            NODE_OPTIONS=--max-old-space-size=192 npm_config_maxsockets=2 npm_config_jobs=1 \
                npm ci --ignore-scripts --no-audit --no-fund
            node "$SCRIPT_DIR/verify-monster-build-dependencies.cjs" "$source_dir"
            NODE_OPTIONS=--max-old-space-size=192 npm_config_maxsockets=2 \
                npm_config_jobs=1 MAKEFLAGS=-j1 npm rebuild node-sass re2
            node -e 'require("node-sass").renderSync({data:".fixture { color: red; }"}); if (!new (require("re2"))("^fixture$").test("fixture")) process.exit(1)'
            [[ $(sha256sum package-lock.json | awk '{print $1}') == "$build_lock_sha" ]] || die 'Dependency lock changed during npm ci'
            node "$SCRIPT_DIR/build-monster-production.cjs" "$source_dir"
            node "$SCRIPT_DIR/verify-monster-production-artifact.cjs" "$source_dir"
        )
        [[ $(monster_ui_build_fingerprint) == "$expected_build" ]] || die 'Build inputs changed during compilation; refusing deployment'
        runtime_capability_hash=$(monster_language_capability_hash) || die 'Existing runtime language capability is invalid'
        deploy_monster_ui_owned "$source_dir"
        [[ $(monster_language_capability_hash) == "$runtime_capability_hash" ]] || \
            die 'Runtime language capability changed during deployment; inspect evidence before proceeding'
        if command -v restorecon >/dev/null; then restorecon -RF "$MONSTER_UI_WEB_ROOT" || true; fi
        # The compatibility marker is not proof: actual owned output and config
        # are verified first; any partial activation retains its backup receipt.
        verify_monster_ui_owned "$expected_build"
        printf '%s\n' "$expected_build" | write_file 0644 "$marker"
    else
        verify_monster_ui_owned "$expected_build"
    fi
    if [[ ",${MONSTER_UI_APPS_LIST}," == *',acdc,'* ]]; then
        node "$SCRIPT_DIR/ensure-acdc-language-capabilities.cjs" --web-root "$MONSTER_UI_WEB_ROOT"
    fi
    # /apis is preserved by owned deployment and refreshed by its own verifier.
    install_api_developer_docs
    configure_monster_ui_nginx
    if [[ -f /etc/nginx/nginx.conf ]]; then
        sed -i '/^[[:space:]]*server[[:space:]]*{/,/^[[:space:]]*}/ { /listen[[:space:]]\+80 default_server/d; /listen[[:space:]]\+\[::\]:80 default_server/d; }' /etc/nginx/nginx.conf
    fi
    run nginx -t
    service_enable_restart nginx.service
    wait_for_port 127.0.0.1 80 30 || die 'nginx did not open port 80'
    register_monster_apps
    verify_monster_ui
    )
}

verify_monster_ui_api_endpoint() {
    local api_result api_body api_status
    api_result=$(curl --disable --connect-timeout 10 --max-time 30 --silent --show-error \
        --write-out $'\n%{http_code}' "$KAZOO_API_URL") || \
        die 'Configured Monster UI API is unreachable'
    api_status=${api_result##*$'\n'}
    api_body=${api_result%$'\n'*}
    [[ $api_status =~ ^[24][0-9][0-9]$ ]] && \
        jq -e -s 'length == 1 and (.[0] | type == "object" and (.status == "success" or .status == "error"))' <<<"$api_body" >/dev/null 2>&1 || \
        die 'Configured Monster UI API must return a Crossbar JSON response with HTTP 2xx/4xx'
}

verify_monster_ui() {
    if [[ $DRY_RUN == true ]]; then log 'Would verify Monster UI'; return 0; fi
    local app expected_build installed_build
    assert_service nginx.service
    expected_build=$(monster_ui_build_fingerprint)
    [[ -r /usr/local/share/kazoo5-installer/monster-ui-build ]] || \
        die 'Monster UI build fingerprint is missing'
    installed_build=$(</usr/local/share/kazoo5-installer/monster-ui-build)
    [[ $installed_build == "$expected_build" ]] || \
        die 'Deployed Monster UI does not match the requested pinned build and app bundle'
    verify_monster_ui_owned "$expected_build"
    [[ $(node -p 'process.versions.node.split(".")[0]') == "$MONSTER_UI_NODE_MAJOR" ]] || \
        die "Monster UI build toolchain is not Node.js ${MONSTER_UI_NODE_MAJOR}"
    verify_monster_ui_transport
    grep -R -F -- "$KAZOO_API_URL" "$MONSTER_UI_WEB_ROOT" >/dev/null || \
        die "Monster UI build does not contain the configured API URL: ${KAZOO_API_URL}"
    for app in ${MONSTER_UI_APPS_LIST//,/ }; do
        [[ -s $MONSTER_UI_WEB_ROOT/apps/$app/metadata/app.json ]] || \
            die "Deployed Monster UI is missing app metadata for ${app}"
        if [[ $app == acdc ]]; then
            jq -e --arg api "$KAZOO_API_URL" '.api_url == $api' \
                "$MONSTER_UI_WEB_ROOT/apps/acdc/metadata/app.json" >/dev/null || \
                die 'Deployed ACDC metadata has an incorrect API URL'
        fi
    done
    verify_monster_ui_api_endpoint
    verify_monster_app_registration
    log 'PASS Monster UI, stable app bundle, API reachability, and nginx checks'
}

push_bridge_preflight() {
    [[ ${SELECTED[push-bridge]:-} ]] || return 0
    if [[ $DRY_RUN == true ]]; then
        log 'Would validate protected mobile config, credential permissions and broker/provider inputs before host changes'
        return 0
    fi
    [[ $(uname -m) == x86_64 ]] || die 'Push bridge dependency lock currently supports Rocky 9 x86_64 only'
    command -v python3 >/dev/null || die 'Python 3 is required for the offline bridge configuration preflight'
    [[ -f $SCRIPT_DIR/../services/push-bridge/requirements.lock ]] || die 'Push bridge dependency lock is missing'
    python3 -B -I "$SCRIPT_DIR/../services/push-bridge/service_launcher.py" --check || \
        die 'Mobile bridge configuration is missing or invalid; prepare /etc/kazoo-push-bridge/config.json and protected provider files (no services changed)'
}

push_bridge_fingerprint() {
    local source_dir="$SCRIPT_DIR/../services/push-bridge" file
    {
    # Dependency layout is part of release identity. Do not reuse a previously
    # staged root-only venv merely because its Python source bytes are equal.
    printf '%s\n' 'bridge-install-layout=venv-umask022-v1'
    for file in bridge.py apns_sender.py delivery_settlement.py delivery_retry.py push_payload.py validate_config.py amqp_topology.py amqp_management.py freshness.py freshness_runtime.py \
        service_launcher.py service_notify.py requirements.lock kazoo-push-bridge.service; do
        [[ -f $source_dir/$file && ! -L $source_dir/$file ]] || die 'Bridge release source is missing or linked'
        sha256sum "$source_dir/$file" | awk -v name="$file" '{ print $1 "  " name }'
    done
    } | sha256sum | awk '{ print $1 }'
}

push_bridge_install_venv() (
    local release=$1
    # This tree contains public program/dependency files only. Configuration and
    # provider credentials remain protected in /etc, outside this subshell.
    # Never change the caller's mask or recursively relax credential paths.
    umask 022
    run python3.11 -I -m venv "$release/venv" || return $?
    run "$release/venv/bin/python" -I -m pip --isolated install --disable-pip-version-check \
        --index-url https://pypi.org/simple --only-binary=:all: --require-hashes \
        --retries 2 --timeout 30 -r "$release/requirements.lock" || return $?
)

install_push_bridge() {
    local source_dir="$SCRIPT_DIR/../services/push-bridge"
    local base=/usr/local/lib/kazoo-push-bridge release fingerprint file previous='' temporary
    if [[ $DRY_RUN == true ]]; then
        log 'Would install Python 3.11, isolated hash-locked bridge dependencies and root-owned release'
        log 'Would install and enable/start kazoo-push-bridge.service as kazoo-push-bridge; wait for AMQP consumer readiness'
        return 0
    fi
    dnf_install python3.11 python3.11-pip
    if ! getent passwd kazoo-push-bridge >/dev/null; then
        run useradd --system --user-group --no-create-home --home-dir /nonexistent \
            --shell /sbin/nologin kazoo-push-bridge
    fi
    [[ $(id -u kazoo-push-bridge) != 0 && $(id -gn kazoo-push-bridge) == kazoo-push-bridge ]] || \
        die 'Push bridge requires a dedicated non-root user and primary group'
    python3 -B -I "$source_dir/service_launcher.py" --prepare-permissions
    [[ ! -L $base && ! -L $base/releases ]] || die 'Bridge installation directories must not be symlinks'
    run install -d -o root -g root -m 0755 "$base" "$base/releases"
    fingerprint=$(push_bridge_fingerprint)
    release="$base/releases/$fingerprint"
    [[ ! -e $base/current || -L $base/current ]] || die 'Bridge current path must be an installer-owned release link'
    if [[ -L $base/current ]]; then
        previous=$(readlink "$base/current")
        [[ $previous =~ ^/usr/local/lib/kazoo-push-bridge/releases/[0-9a-f]{64}$ ]] || \
            die 'Refusing to replace an unrelated bridge current link'
    fi
    if [[ $previous != "$release" ]]; then
        [[ ! -L $release ]] || die 'Bridge release directory must not be a symlink'
        run install -d -o root -g root -m 0755 "$release"
        for file in bridge.py apns_sender.py delivery_settlement.py delivery_retry.py push_payload.py validate_config.py amqp_topology.py amqp_management.py freshness.py freshness_runtime.py \
            service_launcher.py service_notify.py requirements.lock kazoo-push-bridge.service; do
            run install -o root -g root -m 0644 "$source_dir/$file" "$release/$file"
        done
        push_bridge_install_venv "$release"
    fi
    run "$release/venv/bin/python" -I -m pip --isolated check
    run "$release/venv/bin/python" -B -I "$release/service_launcher.py" --check-dependencies
    for file in bridge.py apns_sender.py delivery_settlement.py delivery_retry.py push_payload.py validate_config.py amqp_topology.py amqp_management.py freshness.py freshness_runtime.py \
        service_launcher.py service_notify.py requirements.lock kazoo-push-bridge.service; do
        cmp -s "$source_dir/$file" "$release/$file" || die 'Bridge release bytes do not match source'
    done
    run runuser -u kazoo-push-bridge -- "$release/venv/bin/python" -B -I "$release/service_launcher.py" --check
    # Publish only after dependencies and service-user credential access pass.
    temporary="$base/current.new.$$"
    run ln -s "$release" "$temporary"
    run mv -T "$temporary" "$base/current"
    write_file 0644 /etc/systemd/system/kazoo-push-bridge.service <"$source_dir/kazoo-push-bridge.service"
    run systemctl daemon-reload
    run systemctl enable kazoo-push-bridge.service
    local bridge_activation_failed=false bridge_verification_pid
    if ! systemctl restart kazoo-push-bridge.service; then
        bridge_activation_failed=true
    else
        # Do not test verify_push_bridge directly in an if/! expression: Bash
        # would suppress errexit inside it and could hide a dependency failure.
        # A child also contains its explicit die/exit without exiting before
        # rollback. Launch outside a conditional; wait only tests its status.
        ( set -e; verify_push_bridge ) &
        bridge_verification_pid=$!
        if ! wait "$bridge_verification_pid"; then
            bridge_activation_failed=true
        fi
    fi
    if [[ $bridge_activation_failed == true ]]; then
        if [[ -n $previous && $previous != "$release" ]]; then
            ln -s "$previous" "$temporary"
            mv -T "$temporary" "$base/current"
            install -o root -g root -m 0644 "$previous/kazoo-push-bridge.service" \
                /etc/systemd/system/kazoo-push-bridge.service
            systemctl daemon-reload
            systemctl restart kazoo-push-bridge.service || warn 'Previous bridge release could not be restarted; operator recovery required'
        fi
        die 'Bridge restart or post-start verification failed; inspect protected configuration and service state'
    fi
}

verify_push_bridge() {
    if [[ $DRY_RUN == true ]]; then log 'Would verify push bridge release, unit, enabled state and registered consumer'; return 0; fi
    local base=/usr/local/lib/kazoo-push-bridge release file actual
    release="$base/releases/$(push_bridge_fingerprint)"
    [[ -L $base/current && $(readlink "$base/current") == "$release" ]] || die 'Active bridge release differs from requested source'
    for file in bridge.py apns_sender.py delivery_settlement.py delivery_retry.py push_payload.py validate_config.py amqp_topology.py amqp_management.py freshness.py freshness_runtime.py \
        service_launcher.py service_notify.py requirements.lock kazoo-push-bridge.service; do
        cmp -s "$SCRIPT_DIR/../services/push-bridge/$file" "$release/$file" || die 'Bridge release verification failed'
    done
    cmp -s "$release/kazoo-push-bridge.service" /etc/systemd/system/kazoo-push-bridge.service || \
        die 'Bridge unit differs from tracked unit'
    [[ $(systemctl show -p DropInPaths --value kazoo-push-bridge.service) == '' ]] || die 'Unreviewed bridge unit drop-ins found'
    actual=$(systemctl show -p User --value kazoo-push-bridge.service)
    [[ $actual == kazoo-push-bridge ]] || die 'Bridge effective service user is incorrect'
    [[ $(systemctl show -p Type --value kazoo-push-bridge.service) == notify ]] || die 'Bridge readiness type is incorrect'
    [[ $(systemctl show -p SubState --value kazoo-push-bridge.service) == running ]] || die 'Bridge consumer is not running'
    [[ $(systemctl show -p StatusText --value kazoo-push-bridge.service) == 'AMQP consumer registered; mobile delivery not verified' ]] || \
        die 'Bridge consumer readiness notification is missing'
    systemctl is-enabled --quiet kazoo-push-bridge.service && systemctl is-active --quiet kazoo-push-bridge.service || \
        die 'Bridge service must be enabled and active'
    runuser -u kazoo-push-bridge -- "$release/venv/bin/python" -B -I "$release/service_launcher.py" --check
    "$release/venv/bin/python" -I -m pip --isolated check
    "$release/venv/bin/python" -B -I "$release/service_launcher.py" --check-dependencies
    log 'PASS bridge source, protected configuration and broker-consumer service readiness; real mobile delivery still requires acceptance'
}

verify_requested() {
    verify_local_epmd_socket
    if [[ ${SELECTED[couchdb]:-} ]]; then verify_couchdb; fi
    if [[ ${SELECTED[rabbitmq]:-} ]]; then verify_rabbitmq; fi
    if [[ ${SELECTED[haproxy]:-} ]]; then verify_haproxy; fi
    if [[ ${SELECTED[kazoo-apps]:-} ]]; then verify_kazoo_apps; fi
    if [[ ${SELECTED[ecallmgr]:-} ]]; then verify_ecallmgr; fi
    if [[ ${SELECTED[freeswitch]:-} ]]; then verify_freeswitch; fi
    if [[ ${SELECTED[kamailio]:-} ]]; then verify_kamailio; fi
    if [[ ${SELECTED[monster-ui]:-} ]]; then verify_monster_ui; fi
    if [[ ${SELECTED[push-bridge]:-} ]]; then verify_push_bridge; fi
}

install_requested() {
    install_base_dependencies
    configure_local_epmd_socket
    if [[ ${SELECTED[couchdb]:-} ]]; then install_couchdb; fi
    if [[ ${SELECTED[rabbitmq]:-} ]]; then install_rabbitmq; fi
    if [[ ${SELECTED[haproxy]:-} ]]; then install_haproxy; fi
    if [[ ${SELECTED[kazoo-apps]:-} ]]; then install_kazoo_apps; fi
    if [[ ${SELECTED[freeswitch]:-} ]]; then install_freeswitch; fi
    if [[ ${SELECTED[ecallmgr]:-} ]]; then install_ecallmgr; fi
    if [[ ${SELECTED[kamailio]:-} ]]; then install_kamailio; fi
    if [[ ${SELECTED[monster-ui]:-} ]]; then install_monster_ui; fi
    if [[ ${SELECTED[push-bridge]:-} ]]; then install_push_bridge; fi
    verify_requested
}

install_and_persist_requested() {
    install_requested
    save_deployment_config
}

acquire_installer_lock() {
    # All roles share configuration, source and package/service managers. Even
    # verification must not report a half-published installation as healthy.
    [[ $DRY_RUN != true ]] || return 0
    [[ $EUID == 0 ]] || die 'Run the installer as root'
    command -v flock >/dev/null || die 'flock (util-linux) is required before installation'
    local lock_dir=/run/kazoo5-installer lock_file
    if [[ ! -e $lock_dir && ! -L $lock_dir ]]; then
        mkdir -m 0700 -- "$lock_dir" 2>/dev/null || [[ -d $lock_dir ]] || die 'Cannot create installer lock directory'
    fi
    [[ -d $lock_dir && ! -L $lock_dir && $(stat -c '%u:%a' "$lock_dir") == 0:700 ]] || \
        die 'Installer lock directory must be root-owned, unlinked and mode 0700'
    lock_file=$lock_dir/host.lock
    [[ ! -L $lock_file && ( ! -e $lock_file || ( -f $lock_file && $(stat -c '%u:%h' "$lock_file") == 0:1 ) ) ]] || \
        die 'Unsafe installer lock file'
    # Keep the descriptor open for the whole invocation and its running build
    # children. Never unlink the inode: that would permit a second lock domain.
    exec {KAZOO_INSTALL_LOCK_FD}<>"$lock_file"
    if ! flock -n "$KAZOO_INSTALL_LOCK_FD"; then
        die 'Another Kazoo installer or verification is running on this host; wait for it to finish'
    fi
}

main() {
    parse_arguments "$@"
    acquire_installer_lock
    push_bridge_preflight
    preflight
    log "Resolved components: ${!SELECTED[*]}"
    if [[ $VERIFY_ONLY == true ]]; then
        verify_requested
    else
        # Keep one metadata pause across nested package/media/build steps.
        # Repeated timer stop/start can exhaust systemd's start-rate limit.
        with_dnf_guard install_and_persist_requested
    fi
    if [[ $DRY_RUN == true ]]; then
        log 'Dry run complete; no components were installed or live health checks performed'
    else
        log 'All requested Kazoo 5 components passed validation'
    fi
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
