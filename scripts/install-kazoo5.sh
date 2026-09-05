#!/usr/bin/env bash
# shellcheck disable=SC2016
# Install modular or all-in-one Kazoo 5 nodes on Rocky Linux 9.
#
# This installer deliberately uses Kazoo's FreeSWITCH and Kamailio wrappers and
# configuration repositories.  It is safe to re-run: packages, repositories,
# source checkouts, configuration files and systemd units are converged before
# their health checks run.

set -Eeuo pipefail
shopt -s inherit_errexit

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
    KAZOO_COUCHDB_ADMIN_PORT KAZOO_COUCHDB_USER KAZOO_COUCHDB_PASSWORD
    KAZOO_COUCHDB_BIND KAZOO_RABBITMQ_BIND KAZOO_HAPROXY_BIND KAZOO_PUBLIC_IP
    KAZOO_ERLANG_DIST_IP KAZOO_API_URL KAZOO_MAKE_JOBS KAZOO_MIN_BUILD_FREE_MB
    KAZOO_APPS_LIST KAZOO_FREESWITCH_NODES KAZOO_START_TIMEOUT
    KAZOO_FREESWITCH_STABILITY_SECONDS KAZOO_REQUIRE_MEDIA_CONNECTION
    KAZOO_BOOTSTRAP_MASTER_ACCOUNT KAZOO_MASTER_ACCOUNT_NAME
    KAZOO_MASTER_ACCOUNT_REALM KAZOO_MASTER_ADMIN_USER KAZOO_INSTALLER_SECRETS
    KAZOO_PUBLIC_HOSTNAME KAZOO_TLS_CERT_FILE KAZOO_TLS_KEY_FILE
    KAZOO_TLS_CHAIN_FILE KAZOO_API_UPSTREAM
    COUCHDB_VERSION RABBITMQ_VERSION ERLANG_VERSION HTMLDOC_VERSION HTMLDOC_REF
    FREESWITCH_VERSION FREESWITCH_REF SPANDSP_REF SOFIA_SIP_REF MOD_KAZOO_REF
    FREESWITCH_CONFIG_REF KAZOO_CORE_CONFIG_REF KAZOO_CORE_REF KAZOO_CROSSBAR_REF KAZOO_ECALLMGR_REF KAZOO_STEPSWITCH_REF KAZOO_CDR_REF KAZOO_SOUNDS_REF ACDC_REF KAMAILIO_VERSION
    KAMAILIO_CONFIG_REF KAMAILIO_CHILDREN KAMAILIO_TCP_CHILDREN
    KAMAILIO_AMQP_CONSUMERS KAMAILIO_AMQP_WORKERS MONSTER_UI_REF
    MONSTER_UI_NODE_MAJOR MONSTER_UI_WEB_ROOT MONSTER_UI_REGISTER_APPS
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
ACDC_REF=${ACDC_REF:-6f71c85f67ee2228efb0edceb5248b6334ba1998}
KAMAILIO_VERSION=${KAMAILIO_VERSION:-${KAMAILIO_SERIES:-6.1.4}}
KAMAILIO_CONFIG_REF=${KAMAILIO_CONFIG_REF:-9d61bded9890325182f1783aeb4bd2182eb2d846}
KAMAILIO_CHILDREN=${KAMAILIO_CHILDREN:-4}
KAMAILIO_TCP_CHILDREN=${KAMAILIO_TCP_CHILDREN:-4}
KAMAILIO_AMQP_CONSUMERS=${KAMAILIO_AMQP_CONSUMERS:-2}
KAMAILIO_AMQP_WORKERS=${KAMAILIO_AMQP_WORKERS:-4}
MONSTER_UI_REF=${MONSTER_UI_REF:-7ef735eada6fd0e2b96c06f32c0bb868867f7d18}
MONSTER_UI_NODE_MAJOR=${MONSTER_UI_NODE_MAJOR:-18}
MONSTER_UI_WEB_ROOT=${MONSTER_UI_WEB_ROOT:-/var/www/html/monster-ui}
MONSTER_UI_REGISTER_APPS=${MONSTER_UI_REGISTER_APPS:-auto}
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
  MONSTER_UI_REF, MONSTER_UI_APPS_LIST, MONSTER_UI_REGISTER_APPS.

Examples:
  sudo ./${SCRIPT_NAME} couchdb rabbitmq
  sudo KAZOO_COUCHDB_HOST=db1.example.net KAZOO_AMQP_HOST=mq1.example.net \\
    ./${SCRIPT_NAME} kazoo-apps ecallmgr
  sudo ./${SCRIPT_NAME} ALL
  sudo ./${SCRIPT_NAME} --verify-only all
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
    [[ $value == /* && $value != / && ! $value =~ [[:space:]] ]] || \
        die "${name} must be an absolute, non-root path without whitespace"
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
    if [[ ! -d $destination/.git ]]; then
        run mkdir -p "$(dirname -- "$destination")"
        if [[ $ref =~ ^[0-9a-fA-F]{40}$ ]]; then
            run mkdir -p "$destination"
            run git -C "$destination" init
            run git -C "$destination" remote add origin "$url"
            run git -C "$destination" fetch --depth 1 origin "$ref"
            run git -C "$destination" checkout --detach FETCH_HEAD
        else
            run git clone --branch "$ref" --depth 1 "$url" "$destination"
        fi
        return 0
    fi
    if [[ $DRY_RUN == true ]]; then
        log "Would fast-forward ${destination} from ${url} (${ref})"
        return 0
    fi
    git -C "$destination" remote set-url origin "$url"
    git -C "$destination" fetch --depth 1 origin "$ref"
    if [[ $ref =~ ^[0-9a-fA-F]{40}$ ]]; then
        git -C "$destination" checkout --detach FETCH_HEAD
    elif git -C "$destination" show-ref --verify --quiet "refs/remotes/origin/${ref}"; then
        git -C "$destination" checkout "$ref"
        git -C "$destination" merge --ff-only FETCH_HEAD
    else
        git -C "$destination" checkout --detach FETCH_HEAD
    fi
}

dnf_install() {
    run dnf install -y "$@"
}

service_enable_restart() {
    local unit=$1
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
        all)
            select_component couchdb
            select_component rabbitmq
            select_component haproxy
            select_component kazoo-apps
            select_component ecallmgr
            select_component freeswitch
            select_component kamailio
            select_component monster-ui
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
                printf '%s\n' couchdb rabbitmq haproxy kazoo-apps ecallmgr freeswitch kamailio monster-ui all
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

preflight() {
    [[ -r /etc/os-release ]] || die '/etc/os-release is missing'
    # shellcheck disable=SC1091
    source /etc/os-release
    [[ ${ID:-} == rocky ]] || \
        die "This tested installer supports Rocky Linux 9 only; found ${ID:-unknown}"
    [[ ${VERSION_ID%%.*} == 9 ]] || die "Rocky Linux 9 is required; found ${VERSION_ID:-unknown}"
    [[ -d $KAZOO_ROOT/.git ]] || die "KAZOO_ROOT is not a Git checkout: ${KAZOO_ROOT}"
    validate_install_directory KAZOO_ROOT "$KAZOO_ROOT"
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
        KAZOO_PUBLIC_IP=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')
        KAZOO_PUBLIC_IP=${KAZOO_PUBLIC_IP:-127.0.0.1}
    fi
    if [[ -n $KAZOO_PUBLIC_HOSTNAME ]]; then
        KAZOO_API_URL=${KAZOO_API_URL:-https://${KAZOO_PUBLIC_HOSTNAME}/v2/}
    else
        KAZOO_API_URL=${KAZOO_API_URL:-http://${KAZOO_PUBLIC_IP}:8000/v2/}
    fi
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
    [[ $KAZOO_API_URL =~ ^https?://[^[:space:]]+/$ ]] || \
        die 'KAZOO_API_URL must be an http(s) URL ending in /'
    [[ $KAZOO_API_URL != *\'* && $KAZOO_API_URL != *'"'* && $KAZOO_API_URL != *\\* ]] || \
        die 'KAZOO_API_URL must not contain quotes or backslashes'
    [[ $KAZOO_APPS_LIST =~ ^[a-zA-Z0-9_,-]+$ ]] || \
        die 'KAZOO_APPS_LIST must be a comma-separated list of application names'
    [[ $MONSTER_UI_APPS_LIST =~ ^[a-z0-9,-]+$ ]] || \
        die 'MONSTER_UI_APPS_LIST must be a comma-separated list of supported app names'
    [[ $MONSTER_UI_REGISTER_APPS == auto || $MONSTER_UI_REGISTER_APPS == true || \
       $MONSTER_UI_REGISTER_APPS == false ]] || \
        die 'MONSTER_UI_REGISTER_APPS must be auto, true, or false'
    [[ $MONSTER_UI_NODE_MAJOR == 18 ]] || \
        die 'Monster UI 5.5.13 requires the tested Node.js 18 build toolchain'
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

install_base_dependencies() {
    log 'Installing Rocky Linux repositories and base tooling'
    dnf_install dnf-plugins-core epel-release
    run dnf config-manager --set-enabled crb
    dnf_install \
        bash-completion ca-certificates curl findutils git gzip iproute jq logrotate \
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
    service_enable_restart rabbitmq-server.service
    if [[ $DRY_RUN != true ]]; then
        timeout 120 bash -c 'until rabbitmq-diagnostics -q ping; do sleep 2; done' || \
            die 'RabbitMQ diagnostics did not become healthy'
        if rabbitmqctl -q list_users | awk '{print $1}' | grep -Fx "$KAZOO_RABBITMQ_USER" >/dev/null; then
            rabbitmqctl change_password "$KAZOO_RABBITMQ_USER" "$KAZOO_RABBITMQ_PASSWORD"
        else
            rabbitmqctl add_user "$KAZOO_RABBITMQ_USER" "$KAZOO_RABBITMQ_PASSWORD"
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
    local installed_version installed_erlang listener
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
    rabbitmq-plugins list -e -m | grep -Fx rabbitmq_consistent_hash_exchange >/dev/null || \
        die 'rabbitmq_consistent_hash_exchange is not enabled'
    rabbitmqctl authenticate_user "$KAZOO_RABBITMQ_USER" "$KAZOO_RABBITMQ_PASSWORD" >/dev/null || \
        die "RabbitMQ user ${KAZOO_RABBITMQ_USER} failed authentication"
    rabbitmq-diagnostics -q listeners | grep -E "Interface: .* port: ${KAZOO_AMQP_PORT}, protocol: amqp" >/dev/null || \
        die "RabbitMQ is not listening for AMQP on port ${KAZOO_AMQP_PORT}"
    log "PASS RabbitMQ ${installed_version} on Erlang ${installed_erlang}: ping, listener, authentication, and consistent-hash plugin checks"
}

install_haproxy() {
    local probe_address
    log 'Installing HAProxy with Kazoo CouchDB listeners'
    dnf_install haproxy
    write_file 0644 /etc/haproxy/haproxy.cfg <<EOF
global
    log         127.0.0.1 local2
    chroot      /var/lib/haproxy
    pidfile     /run/haproxy.pid
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

ensure_kazoo_sources() {
    local acdc_dir="${KAZOO_ROOT}/applications/acdc"
    local core_dir="${KAZOO_ROOT}/core"
    local cookie_patch="${SCRIPT_DIR}/patches/kazoo-cookie-redaction.patch"
    [[ -f ${KAZOO_ROOT}/make/apps.mk ]] || die 'Kazoo source manifest is missing'
    if [[ ! -d ${acdc_dir}/.git ]]; then
        sync_git https://github.com/kazoo-community/kazoo-acdc.git \
            "$acdc_dir" "$ACDC_REF"
    elif [[ $(git -C "$acdc_dir" rev-parse HEAD 2>/dev/null || true) != "$ACDC_REF" ]]; then
        die "Existing ACDC checkout is not the pinned compatible revision ${ACDC_REF}"
    fi
    [[ $DRY_RUN == true || -d $core_dir/.git ]] || die 'Kazoo core source checkout is missing'
    if [[ $DRY_RUN != true ]]; then
        [[ $(git -C "$core_dir" rev-parse HEAD) == "$KAZOO_CORE_REF" ]] || \
            die 'Existing Kazoo core checkout differs from the tested pinned revision'
        [[ $(git -C "$KAZOO_ROOT/applications/crossbar" rev-parse HEAD) == "$KAZOO_CROSSBAR_REF" ]] || \
            die 'Existing Crossbar checkout differs from the tested pinned revision'
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
    apply_required_source_patch "$core_dir" "$SCRIPT_DIR/patches/kazoo-dataplan-log-redaction.patch"
    apply_required_source_patch "$core_dir" "$SCRIPT_DIR/patches/kazoo-amqp-originate-reconcile.patch"
    apply_required_source_patch "$core_dir" "$SCRIPT_DIR/patches/kazoo-registration-collection.patch"
    apply_required_source_patch "$core_dir" "$SCRIPT_DIR/patches/kazoo-channel-monitoring.patch"
    # One patch per overlapping source stack makes reinstallation idempotent:
    # later callback edits must not invalidate reverse checks of earlier OTP
    # and announcement hunks. Feature patches remain review/test provenance.
    apply_required_source_patch "$acdc_dir" "$SCRIPT_DIR/patches/acdc-kazoo5-integration.patch"
    apply_required_source_patch "$KAZOO_ROOT/applications/crossbar" \
        "$SCRIPT_DIR/patches/crossbar-kazoo5-integration.patch"
    apply_required_source_patch "$KAZOO_ROOT/applications/stepswitch" \
        "$SCRIPT_DIR/patches/stepswitch-callback-origination.patch"
    apply_required_source_patch "$KAZOO_ROOT/applications/ecallmgr" \
        "$SCRIPT_DIR/patches/ecallmgr-kazoo5-integration.patch"
    apply_required_source_patch "$KAZOO_ROOT/applications/cdr" \
        "$SCRIPT_DIR/patches/cdr-report-timestamp-fallback.patch"
}

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
    run mkdir -p "$KAZOO_CONFIG_DIR/core" /var/log/kazoo /var/lib/kazoo "$KAZOO_ROOT/var/lib/ra"
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
    local runtime_root
    [[ $DRY_RUN != true ]] || return 0
    runtime_root=$(readlink -f -- "$KAZOO_ROOT")
    [[ -n $runtime_root && $runtime_root != / && -d $runtime_root/applications && -d $runtime_root/core ]] || \
        die 'Cannot validate the Kazoo code tree for runtime artifact permissions'
    # Root builds may inherit umask 077. These are code and public schema/view
    # definitions, not deployment configuration, logs, keys, or credential files.
    find "$runtime_root/core" "$runtime_root/applications" "$runtime_root/deps" -type f \
        \( -path '*/ebin/*.beam' -o -path '*/ebin/*.app' \
           -o -path '*/priv/couchdb/views/*.json' -o -path '*/priv/couchdb/schemas/*.json' \) \
        -exec chmod 0644 -- {} +
}

build_kazoo() {
    install_kazoo_build_dependencies
    # A new project clone has no ignored core/ or applications/ checkouts yet.
    # Fetch sources before patching or generating files inside those trees.
    run env FETCH_AS=https://github.com/ make -C "$KAZOO_ROOT" \
        JOBS="$KAZOO_MAKE_JOBS" \
        "dep_core=git https://github.com/2600hz/kazoo-core.git $KAZOO_CORE_REF" \
        "dep_crossbar=git https://github.com/2600hz/kazoo-crossbar.git $KAZOO_CROSSBAR_REF" \
        "dep_ecallmgr=git https://github.com/2600hz/kazoo-ecallmgr.git $KAZOO_ECALLMGR_REF" \
        "dep_stepswitch=git https://github.com/2600hz/kazoo-stepswitch.git $KAZOO_STEPSWITCH_REF" \
        "dep_cdr=git https://github.com/2600hz/kazoo-cdr.git $KAZOO_CDR_REF" \
        "dep_acdc=git https://github.com/kazoo-community/kazoo-acdc.git $ACDC_REF" \
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
    # kazoo_numbers expands its SOURCES list while parsing its Makefile.  Under
    # a parallel top-level build, that can happen before its generated ISO-3166
    # modules are written, leaving erlc with a source path that does not exist.
    # Materialize both modules first so `make all` is deterministic at any -j.
    # Drop dependency files left malformed by an interrupted generator run.
    rm -f "$KAZOO_ROOT/core/kazoo_numbers/.deps.rules" \
        "$KAZOO_ROOT/core/kazoo_web/.deps.rules"
    make -C "$KAZOO_ROOT/core/kazoo_numbers" \
        src/knm_iso3166a2_itu.erl src/knm_iso3166_util.erl
    make -C "$KAZOO_ROOT/core/kazoo_web" src/kz_mime.erl
    # `skel` declares gen_webhook as a behaviour, but the generated aggregate
    # Makefile does not encode inter-application ordering and places webhooks
    # after skel.  Build the behaviour provider once before the parallel app
    # pass so OTP 26's undefined-behaviour warning cannot fail under -Werror.
    FETCH_AS=https://github.com/ make -C "$KAZOO_ROOT" \
        JOBS="$KAZOO_MAKE_JOBS" core fetch-apps
    make -C "$KAZOO_ROOT/applications/webhooks" all
    FETCH_AS=https://github.com/ make -C "$KAZOO_ROOT" \
        JOBS="$KAZOO_MAKE_JOBS" apps
    FETCH_AS=https://github.com/ make -C "$KAZOO_ROOT" JOBS="$KAZOO_MAKE_JOBS" build-dev-release
    prepare_kazoo_runtime_artifact_permissions
    verify_kazoo_production_beams
}

install_kazoo_systemd_units() {
    local fqdn
    fqdn=$KAZOO_HOSTNAME
    if ! getent group kazoo >/dev/null; then
        run groupadd --system kazoo
    fi
    if ! id kazoo >/dev/null 2>&1; then
        run useradd --system --gid kazoo --home-dir /var/lib/kazoo --shell /sbin/nologin kazoo
    fi
    run mkdir -p /var/lib/kazoo /var/log/kazoo/kazoo_apps/log /var/log/kazoo/ecallmgr/log "$KAZOO_ROOT/log" \
        "$KAZOO_ROOT/scripts/log/log" "$KAZOO_ROOT/var/lib/ra"
    reject_secret_symlink "$KAZOO_RUNTIME_COOKIE_FILE"
    printf '%s\n' "$KAZOO_COOKIE" | write_file 0400 "$KAZOO_RUNTIME_COOKIE_FILE"
    run chown kazoo:kazoo "$KAZOO_RUNTIME_COOKIE_FILE"
    run chown -R kazoo:kazoo /var/lib/kazoo /var/log/kazoo \
        "$KAZOO_ROOT/log" "$KAZOO_ROOT/scripts/log" "$KAZOO_ROOT/var"
    run install -d -m 0750 -o kazoo -g kazoo /var/log/kazoo \
        /var/log/kazoo/kazoo_apps /var/log/kazoo/kazoo_apps/log \
        /var/log/kazoo/ecallmgr /var/log/kazoo/ecallmgr/log
    write_file 0644 /etc/systemd/system/kazoo-apps.service <<EOF
[Unit]
Description=Kazoo 5 Applications Node
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=kazoo
Group=kazoo
UMask=0027
WorkingDirectory=${KAZOO_ROOT}
Environment=HOME=/var/lib/kazoo
Environment=KAZOO_CONFIG=${KAZOO_CONFIG_DIR}/core/config.ini
Environment=KAZOO_LOG_ROOT=/var/log/kazoo/kazoo_apps
Environment="KAZOO_APPS=${KAZOO_APPS_LIST}"
Environment="KAZOO_NODE_NAME_TYPE=${KAZOO_NODE_NAME_TYPE}"
Environment="KAZOO_ERLANG_DIST_IP=${KAZOO_ERLANG_DIST_IP}"
Environment="ERL_FLAGS=-noshell -noinput"
ExecStartPre=/usr/bin/env KAZOO_DEPLOYMENT_CONFIG=/nonexistent /usr/bin/bash -c 'source ${SCRIPT_DIR}/install-kazoo5.sh; verify_kazoo_production_beams'
ExecStart=${KAZOO_ROOT}/scripts/dev-start-apps.sh kazoo_apps
Restart=on-failure
RestartSec=5
TimeoutStartSec=180
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
    write_file 0644 /etc/systemd/system/kazoo-ecallmgr.service <<EOF
[Unit]
Description=Kazoo 5 eCallMgr Node
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=kazoo
Group=kazoo
UMask=0027
WorkingDirectory=${KAZOO_ROOT}
Environment=HOME=/var/lib/kazoo
Environment=KAZOO_CONFIG=${KAZOO_CONFIG_DIR}/core/config.ini
Environment=KAZOO_LOG_ROOT=/var/log/kazoo/ecallmgr
Environment=KAZOO_APPS=ecallmgr
Environment="KAZOO_NODE_NAME_TYPE=${KAZOO_NODE_NAME_TYPE}"
Environment="KAZOO_ERLANG_DIST_IP=${KAZOO_ERLANG_DIST_IP}"
Environment="ERL_FLAGS=-noshell -noinput"
ExecStartPre=/usr/bin/env KAZOO_DEPLOYMENT_CONFIG=/nonexistent /usr/bin/bash -c 'source ${SCRIPT_DIR}/install-kazoo5.sh; verify_kazoo_production_beams'
ExecStart=${KAZOO_ROOT}/scripts/dev-start-ecallmgr.sh ecallmgr
Restart=on-failure
RestartSec=5
TimeoutStartSec=180
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
    run systemctl daemon-reload
}

install_sup_cli() {
    log 'Installing the Kazoo SUP administration command and Bash completion'
    [[ $DRY_RUN == true || -x ${KAZOO_ROOT}/core/sup/sup ]] || \
        die 'The SUP executable was not produced by the Kazoo build'
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

exec "$sup_root/core/sup/sup" "${name_args[@]}" "$@"
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

bootstrap_master_account_rpc() {
    local erl_call_bin account_name_b64 realm_b64 admin_user_b64 admin_password_b64 rpc status
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
        "crossbar_maintenance:create_account(base64:decode(<<\"${account_name_b64}\">>), base64:decode(<<\"${realm_b64}\">>), base64:decode(<<\"${admin_user_b64}\">>), base64:decode(<<\"${admin_password_b64}\">>))."
    if timeout --signal=KILL 120 runuser --user kazoo -- \
        env -u KAZOO_COOKIE -u KAZOO_MASTER_ADMIN_PASSWORD \
        "$erl_call_bin" "$KAZOO_NODE_NAME_TYPE" "kazoo_apps@${KAZOO_HOSTNAME}" \
        -e -no_result_term <<<"$rpc" >/dev/null 2>&1; then
        status=0
    else
        status=$?
    fi
    [[ $xtrace_enabled == false ]] || set -x
    return "$status"
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

install_kazoo_apps() {
    build_kazoo
    install_kazoo_systemd_units
    install_sup_cli
    service_enable_restart kazoo-apps.service
    if [[ $DRY_RUN != true ]]; then
        sleep 5
        persist_kazoo_apps_config
        ensure_master_account
        configure_kazoo_api_modules
    fi
    install_kazoo_prompts
    install_acdc_language_packs
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
    local callback_dir="$KAZOO_BUILD_ROOT/acdc-callback-prompts/en-us"
    local manifest=/usr/local/share/kazoo5-installer/system-media-manifest.json
    local import_dir file documents output imported=0
    prepare_kazoo_sounds
    if [[ $DRY_RUN == true ]]; then
        log 'Would render English-US callback prompts, import missing system prompts and verify every audio attachment'
        return 0
    fi
    verify_erlang_applications kazoo_apps "$KAZOO_APPS_LIST"
    [[ -d $source_dir ]] || die 'Pinned Kazoo English-US prompts are missing'
    [[ -x $SCRIPT_DIR/generate-acdc-callback-prompts.sh ]] || die 'Callback prompt generator is missing'
    dnf_install espeak-ng sox
    "$SCRIPT_DIR/generate-acdc-callback-prompts.sh" "$callback_dir"
    find "$source_dir" "$callback_dir" -maxdepth 1 -type f -name '*.wav' -printf '%f\n' | \
        sort -u | jq -Rsc '{keys: (split("\n") | map(select(length > 0) | "en-us/" + rtrimstr(".wav")))}' | \
        write_file 0644 "$manifest"
    jq -e '.keys | length > 0' "$manifest" >/dev/null || die 'Kazoo prompt manifest is empty'
    output=$(timeout 30 sup kz_datamgr db_create system_media) || die 'Could not create system_media'
    [[ $output == true ]] || die 'system_media database is unavailable'
    documents=$(prompt_documents "$manifest")
    import_dir=$(mktemp -d /tmp/kazoo-prompts-import.XXXXXX)
    trap 'find "$import_dir" -maxdepth 1 -type f -name "*.wav" -delete; rmdir -- "$import_dir"' EXIT
    chmod 0755 "$import_dir"
    while IFS= read -r file; do
        [[ $file =~ ^[a-zA-Z0-9_-]+\.wav$ ]] || die 'Invalid source prompt name'
        if [[ -s $source_dir/$file ]]; then
            [[ ! -e $callback_dir/$file ]] || die 'Callback and official prompt IDs collide'
            install -m 0644 "$source_dir/$file" "$import_dir/$file"
        elif [[ -s $callback_dir/$file ]]; then
            install -m 0644 "$callback_dir/$file" "$import_dir/$file"
        else
            die 'A required source prompt is missing'
        fi
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

install_acdc_language_packs() (
    local pack_dir="$KAZOO_BUILD_ROOT/acdc-language-prompts"
    local speech_dir="$KAZOO_BUILD_ROOT/espeak-ng-1.52.0" receipt
    if [[ $DRY_RUN == true ]]; then
        log "Would prepare pinned speech dependencies and import complete EN/AR/HE/ES/FR packs into configured CouchDB ${KAZOO_COUCHDB_HOST}:${KAZOO_COUCHDB_PORT}; preserve existing recordings"
        log 'Language media import does not require local FreeSWITCH or publish runtime readiness'
        return 0
    fi
    install_nodejs_toolchain
    dnf_install cmake gcc gcc-c++ make git sox
    bash "$SCRIPT_DIR/prepare-acdc-speech-engine.sh" "$KAZOO_BUILD_ROOT"
    if ! node "$SCRIPT_DIR/generate-acdc-language-prompts.cjs" --output-dir "$pack_dir" --verify-only >/dev/null 2>&1; then
        node "$SCRIPT_DIR/generate-acdc-language-prompts.cjs" --output-dir "$pack_dir" \
            --espeak "$speech_dir/build/src/espeak-ng" --espeak-data "$speech_dir/build"
    fi
    receipt=$(mktemp /tmp/kazoo-acdc-language-media.XXXXXX)
    trap 'rm -f -- "$receipt"' EXIT
    # Credentials are inherited only by this child, never placed in argv, URLs,
    # receipts, or public capability artifacts. CouchDB may be a separate host.
    export KAZOO_COUCHDB_HOST KAZOO_COUCHDB_PORT KAZOO_COUCHDB_USER KAZOO_COUCHDB_PASSWORD
    node "$SCRIPT_DIR/import-acdc-language-packs.cjs" --import --pack-dir "$pack_dir" >"$receipt"
    validate_acdc_language_receipt <"$receipt" || die 'Incomplete localized media import receipt'
    write_file 0644 /usr/local/share/kazoo5-installer/acdc-language-media.json <"$receipt"
    log 'PASS complete five-language media import; existing audio preserved; runtime capability is a separate gate'
)

validate_acdc_language_receipt() {
    jq -e '.schema_version == 1 and .owner == "kazoo5-acdc-media-importer" and .runtime_ready == false
        and (.languages | keys == ["ar-sa", "en-us", "es-es", "fr-fr", "he-il"])
        and all(.languages[]; .media_verified == true and .ready == false and .native_speaker_review == false
            and (.source_catalog_sha256 | test("^[a-f0-9]{64}$"))
            and (.installed_media_sha256 | test("^[a-f0-9]{64}$")))' >/dev/null
}

verify_acdc_language_packs() (
    [[ $DRY_RUN != true ]] || return 0
    export KAZOO_COUCHDB_HOST KAZOO_COUCHDB_PORT KAZOO_COUCHDB_USER KAZOO_COUCHDB_PASSWORD
    node "$SCRIPT_DIR/import-acdc-language-packs.cjs" --verify-only \
        --pack-dir "$KAZOO_BUILD_ROOT/acdc-language-prompts" | validate_acdc_language_receipt || \
        die 'Complete localized media could not be verified; install kazoo-apps'
    log 'PASS EN/AR/HE/ES/FR source packs and current installed audio attachments'
)

configure_kazoo_api_modules() {
    local module output
    for module in cb_queues cb_agents cb_acdc_call_stats cb_external_numbers; do
        output=$(timeout 30 sup crossbar_maintenance start_module "$module" </dev/null) || \
            die "Could not register Kazoo Crossbar module ${module}"
        [[ $output != *'failed to start'* ]] || die "Kazoo Crossbar module ${module} failed to start"
    done
    log 'Registered and persisted ACDC and Monster UI Crossbar APIs'
}

verify_acdc_interfaces() {
    local modules module credential_hash auth_body token account_id endpoint result
    modules=$(timeout 30 sup crossbar_bindings modules_loaded </dev/null) || \
        die 'Could not inspect Crossbar module registrations'
    for module in cb_queues cb_agents cb_acdc_call_stats cb_external_numbers; do
        [[ $modules == *"$module"* ]] || die "Kazoo Crossbar module ${module} is not registered"
    done
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
    for endpoint in queues agents external_numbers; do
        result=$(printf 'header = "X-Auth-Token: %s"\n' "$token" | \
            curl --config - --fail --silent --show-error --connect-timeout 5 --max-time 30 \
            "http://127.0.0.1:8000/v2/accounts/${account_id}/${endpoint}") || \
            die "Kazoo authenticated ${endpoint} API failed"
        jq -e '.status == "success" and (.data | type == "array")' <<<"$result" >/dev/null || \
            die "Kazoo ${endpoint} API did not return a successful collection"
    done
    log 'PASS Crossbar administrator login, ACDC queue/agent APIs, and Monster UI external-number API'
}

install_ecallmgr() {
    log 'Installing Kazoo ecallmgr'
    [[ -f ${KAZOO_ROOT}/core/kazoo_apps/ebin/kazoo_apps.app && \
       -f ${KAZOO_ROOT}/applications/ecallmgr/ebin/ecallmgr.app ]] || build_kazoo
    configure_kazoo
    install_kazoo_systemd_units
    install_sup_cli
    service_enable_restart kazoo-ecallmgr.service
    if [[ $DRY_RUN != true ]]; then
        sleep 5
        configure_ecallmgr_dialplan_applications
        configure_ecallmgr_callback_cleanup
        configure_ecallmgr_event_stream_framing
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

verify_kazoo_apps() {
    if [[ $DRY_RUN == true ]]; then log 'Would verify Kazoo apps'; return 0; fi
    local api_result api_body api_status deadline
    verify_kazoo_production_beams
    verify_erlang_node kazoo-apps.service kazoo_apps
    verify_erlang_applications kazoo_apps "$KAZOO_APPS_LIST"
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
        [[ $(master_account_id) == \{ok,* ]] || die 'Kazoo master account is not ready'
        log 'PASS Kazoo master account is ready'
    fi
    verify_sup_cli
    verify_acdc_interfaces
    verify_kazoo_prompts
    verify_acdc_language_packs
}

verify_sup_cli() {
    local configured_apps running_apps exported loaded
    command -v sup >/dev/null || die 'The SUP command is not installed in PATH'
    [[ -s /etc/bash_completion.d/sup ]] || die 'SUP Bash completion is not installed'
    running_apps=$(timeout --signal=KILL 60 sup kapps_controller running_apps </dev/null) || \
        die 'SUP could not call kapps_controller:running_apps/0'
    [[ $running_apps == *acdc* ]] || die 'SUP running_apps result does not include ACDC'
    configured_apps=$(timeout --signal=KILL 60 sup kapps_config get kapps_controller kapps </dev/null) || \
        die 'SUP could not read the kapps_controller application configuration'
    [[ $configured_apps == *acdc* ]] || \
        die 'SUP kapps_controller configuration does not include ACDC'
    loaded=$(timeout --signal=KILL 30 sup -e code ensure_loaded \
        kazoo_maintenance </dev/null) || \
        die 'SUP could not load kazoo_maintenance'
    [[ $loaded == \{module,kazoo_maintenance\} ]] || \
        die "SUP did not load kazoo_maintenance: ${loaded}"
    exported=$(timeout --signal=KILL 30 sup -e erlang function_exported \
        kazoo_maintenance syslog_level 1 </dev/null) || \
        die 'SUP could not inspect kazoo_maintenance:syslog_level/1'
    [[ $exported == true ]] || die 'SUP syslog_level/1 command is not exported'
    loaded=$(timeout --signal=KILL 30 sup -e code ensure_loaded \
        kapps_controller </dev/null) || \
        die 'SUP could not load kapps_controller'
    [[ $loaded == \{module,kapps_controller\} ]] || \
        die "SUP did not load kapps_controller: ${loaded}"
    exported=$(timeout --signal=KILL 30 sup -e erlang function_exported \
        kapps_controller start_app 1 </dev/null) || \
        die 'SUP could not inspect kapps_controller:start_app/1'
    [[ $exported == true ]] || die 'SUP kapps_controller commands are not exported'
    log "PASS SUP controller/config command checks (configured kapps: ${configured_apps})"
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

verify_ecallmgr() {
    if [[ $DRY_RUN == true ]]; then log 'Would verify eCallMgr'; return 0; fi
    verify_kazoo_production_beams
    verify_erlang_node kazoo-ecallmgr.service ecallmgr
    verify_erlang_applications ecallmgr ecallmgr
    verify_ecallmgr_dialplan_applications
    verify_ecallmgr_callback_cleanup
    verify_ecallmgr_event_stream_framing
    verify_configured_freeswitch_nodes
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
                die "Could not register ${node} with eCallMgr: ${output}"
        fi
        log "Registered FreeSWITCH node with eCallMgr: ${node} (${output:-ok})"
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
    )
    sync_git https://github.com/freeswitch/mod_kazoo.git "$module_dir" "$MOD_KAZOO_REF"
    for patch_file in "${patch_files[@]}"; do
        [[ -f $patch_file ]] || die "Required mod_kazoo patch is missing: ${patch_file}"
        if [[ $DRY_RUN == true ]]; then
            log "Would apply required mod_kazoo patch $(basename "$patch_file")"
        elif git -C "$module_dir" apply --check "$patch_file" 2>/dev/null; then
            git -C "$module_dir" apply "$patch_file"
            log "Applied required mod_kazoo patch $(basename "$patch_file")"
        elif git -C "$module_dir" apply --reverse --check "$patch_file" 2>/dev/null; then
            log "Required mod_kazoo patch is already applied: $(basename "$patch_file")"
        else
            die "mod_kazoo source does not match required patch: ${patch_file}"
        fi
    done
}

freeswitch_build_fingerprint() {
    printf '%s\n' \
        "freeswitch=${FREESWITCH_VERSION}@${FREESWITCH_REF}" \
        "freeswitch_core=module-load-shutdown-v1" \
        "speech_modules=en-es-fr-v1" \
        "mod_sofia=profile-thread-lifecycle-v1+kazoo-proxy-uri-v1" \
        "mod_kazoo=${MOD_KAZOO_REF}+fetch-reply-ownership-v1+thread-lifecycle-v1+worker-shutdown-v3+cookie-redaction-v1+prefixes-serialization-v2+fetch-channel-data-v1+fetch-log-redaction-v1+originate-compatibility-v1+reply-completeness-v1+sync-command-protocol-v1+originate-reconcile-v1+hold-dtmf-events-v1" \
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
    dnf_install \
        alsa-lib-devel autoconf automake bzip2-devel cmake curl-devel \
        gcc gcc-c++ git lame-devel libedit-devel libjpeg-turbo-devel libogg-devel \
        libsndfile-devel libtiff-devel libtool libuuid-devel libvorbis-devel \
        libxml2-devel make ncurses-devel openssl-devel opus-devel pcre-devel pcre2-devel \
        pkgconf-pkg-config speex-devel speexdsp-devel sqlite-devel yasm zlib-devel
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
        make install
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

configure_kazoo_freeswitch() {
    local config_source="$KAZOO_BUILD_ROOT/kazoo-configs-freeswitch"
    local module module_config
    sync_git https://github.com/2600hz/kazoo-configs-freeswitch.git \
        "$config_source" "$FREESWITCH_CONFIG_REF"
    run mkdir -p "$KAZOO_CONFIG_DIR/freeswitch"
    run rsync -a "$config_source/freeswitch/" "$KAZOO_CONFIG_DIR/freeswitch/"
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
    install_freeswitch_sounds
}

install_freeswitch_sounds() {
    local manifest=/usr/local/share/kazoo5-installer/freeswitch-sounds.manifest locale
    prepare_kazoo_sounds
    for locale in en/us es/es fr/fr; do
        run mkdir -p "/usr/share/kazoo-freeswitch/sounds/$locale"
        run rsync -a --ignore-existing "$KAZOO_BUILD_ROOT/kazoo-sounds/freeswitch/$locale/" \
            "/usr/share/kazoo-freeswitch/sounds/$locale/"
    done
    run mkdir -p /usr/share/kazoo-freeswitch/sounds/music
    run rsync -a --ignore-existing "$KAZOO_BUILD_ROOT/kazoo-sounds/freeswitch/music/" \
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
    # affected-row check in this configuration follows a DML call whose own
    # return value was already checked. Treat successful DML as changed so
    # idempotent dispatcher reloads and presence cleanup still run.
    for cfg in "${cfg_files[@]}"; do
        sed -i -E 's/\$sqlrows\([^)]*\)/1/g' "$cfg"
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
    sync_git https://github.com/2600hz/kazoo-configs-kamailio.git \
        "$config_source" "$KAMAILIO_CONFIG_REF"
    apply_required_source_patch "$config_source" "$SCRIPT_DIR/patches/kamailio-registration-sequences.patch"
    run mkdir -p "$KAZOO_CONFIG_DIR/kamailio"
    run rsync -a \
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
    local address connections deadline escaped_address
    local -a broker_addresses=()
    mapfile -t broker_addresses < <(
        getent ahostsv4 "$KAZOO_AMQP_HOST" | awk '{print $1}' | sort -u
    )
    ((${#broker_addresses[@]})) || \
        die "Could not resolve configured AMQP host ${KAZOO_AMQP_HOST}"
    deadline=$((SECONDS + KAZOO_START_TIMEOUT))
    while ((SECONDS < deadline)); do
        connections=$(ss -H -tnp state established \
            "( dport = :${KAZOO_AMQP_PORT} )" 2>/dev/null || true)
        for address in "${broker_addresses[@]}"; do
            escaped_address=${address//./\\.}
            if grep -E "[[:space:]]${escaped_address}:${KAZOO_AMQP_PORT}[[:space:]].*\\(\\\"kamailio\\\"" \
                <<<"$connections" >/dev/null; then
                log "PASS Kamailio established AMQP transport to ${KAZOO_AMQP_HOST}:${KAZOO_AMQP_PORT}"
                return 0
            fi
        done
        sleep 2
    done
    die "Kamailio has no established AMQP transport to port ${KAZOO_AMQP_PORT}; run verification as root and check ${KAZOO_AMQP_HOST} credentials/connectivity"
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

verify_kamailio() {
    if [[ $DRY_RUN == true ]]; then log 'Would verify Kazoo Kamailio'; return 0; fi
    local pid seconds_alive wait_seconds active_since errors dispatcher deadline
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
    sqlite3 "$KAZOO_CONFIG_DIR/kamailio/db/kazoo.db" 'PRAGMA integrity_check;' | \
        grep -Fx ok >/dev/null || die 'Kamailio SQLite database integrity check failed'
    sqlite3 "$KAZOO_CONFIG_DIR/kamailio/db/kazoo.db" \
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
    if systemctl is-active --quiet rabbitmq-server.service 2>/dev/null; then
        rabbitmqctl -q list_queues name 2>/dev/null | \
            grep -E "^kamailio@${KAZOO_HOSTNAME//./\\.}-" >/dev/null || \
            die 'Kamailio did not create Kazoo AMQP consumer queues'
    fi
    if systemctl is-active --quiet kazoo-freeswitch.service 2>/dev/null && \
       systemctl is-active --quiet kazoo-ecallmgr.service 2>/dev/null; then
        deadline=$((SECONDS + KAZOO_START_TIMEOUT))
        while ((SECONDS < deadline)); do
            dispatcher=$(/usr/sbin/kamcmd dispatcher.list 2>&1 || true)
            [[ $dispatcher != *'No Destination Sets'* && $dispatcher == *'DEST'* ]] && break
            sleep 2
        done
        [[ $dispatcher != *'No Destination Sets'* && $dispatcher == *'DEST'* ]] || \
            die 'Kamailio did not discover a FreeSWITCH media destination through Kazoo'
        verify_kamailio_sbc
    fi
    active_since=$(systemctl show kazoo-kamailio.service -p ActiveEnterTimestamp --value)
    errors=$(journalctl -u kazoo-kamailio.service --since "$active_since" --no-pager 2>/dev/null | \
        grep -E ' ERROR:|empty or invalid JSON|destination pseudo-variable is not writable|\$var\(kz_log_id\)|Header-Value can.t be parsed|no amqp connection available' || true)
    [[ -z $errors ]] || die "Kamailio logged runtime integration errors after startup: ${errors}"
    log 'PASS Kazoo Kamailio SIP, AMQP, dispatcher, database, RPC, and module checks'
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
    local app ref
    printf '%s\n' \
        "monster_ui=${MONSTER_UI_REF}" \
        "node=${MONSTER_UI_NODE_MAJOR}" \
        "api=${KAZOO_API_URL}"
    printf 'framework_myaccount_patch=%s\n' \
        "$(sha256sum "$SCRIPT_DIR/patches/monster-ui-myaccount-transition.patch" | awk '{print $1}')"
    for app in ${MONSTER_UI_APPS_LIST//,/ }; do
        ref=$(monster_app_ref "$app")
        printf 'app_%s=%s\n' "$app" "$ref"
    done
    if [[ ",${MONSTER_UI_APPS_LIST}," == *',callflows,'* ]]; then
        printf 'callflows_acdc_queue_patch=%s\n' \
            "$(sha256sum "$SCRIPT_DIR/patches/monster-ui-callflows-acdc-queue.patch" | awk '{print $1}')"
    fi
}

install_nodejs_toolchain() {
    local enabled_stream=
    enabled_stream=$(dnf -q module list nodejs --enabled 2>/dev/null | \
        awk '$1 == "nodejs" {gsub(/[^0-9].*/, "", $2); print $2; exit}')
    if [[ $enabled_stream != "$MONSTER_UI_NODE_MAJOR" ]]; then
        if [[ -n $enabled_stream ]]; then
            run dnf module switch-to -y "nodejs:${MONSTER_UI_NODE_MAJOR}/common"
        else
            run dnf module enable -y "nodejs:${MONSTER_UI_NODE_MAJOR}"
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
    local app ref app_dir callflows_patch myaccount_patch supported_app
    local -a supported_apps=(acdc accounts callflows csv-onboarding fax numbers pbxs voicemails webhooks voip)
    if [[ $DRY_RUN != true && -d $source_dir/.git ]]; then
        git -C "$source_dir" checkout -- package.json package-lock.json src/js/config.js
    fi
    sync_git https://github.com/2600hz/monster-ui.git "$source_dir" "$MONSTER_UI_REF"
    myaccount_patch="$SCRIPT_DIR/patches/monster-ui-myaccount-transition.patch"
    [[ -s $myaccount_patch ]] || die 'Required Monster UI MyAccount transition patch is missing'
    if [[ $DRY_RUN == true ]]; then
        log 'Would apply the MyAccount late-transition visibility fix'
    elif git -C "$source_dir" apply --check "$myaccount_patch" 2>/dev/null; then
        git -C "$source_dir" apply "$myaccount_patch"
    elif ! git -C "$source_dir" apply --reverse --check "$myaccount_patch" 2>/dev/null; then
        die 'Monster UI source does not match the MyAccount visibility patch'
    fi
    for supported_app in "${supported_apps[@]}"; do
        if [[ ",${MONSTER_UI_APPS_LIST}," != *",${supported_app},"* ]]; then
            if [[ $DRY_RUN == true ]]; then
                log "Would remove unselected Monster UI app source: ${supported_app}"
            else
                rm -rf -- "$source_dir/src/apps/$supported_app"
                log "Removed unselected Monster UI app source: ${supported_app}"
            fi
        fi
    done
    for app in ${MONSTER_UI_APPS_LIST//,/ }; do
        ref=$(monster_app_ref "$app")
        app_dir="$source_dir/src/apps/$app"
        if [[ $app == acdc ]]; then
            run mkdir -p "$app_dir"
            run rsync -a --delete "$SCRIPT_DIR/../monster-ui/acdc/" "$app_dir/"
            log "Bundled Monster UI ACDC Call Center app: ${ref}"
            continue
        fi
        if [[ $app == callflows && $DRY_RUN != true && -d $app_dir/.git ]]; then
            git -C "$app_dir" checkout -- \
                submodules/device/device.css submodules/user/user.css 2>/dev/null || true
        fi
        sync_git "https://github.com/2600hz/monster-ui-${app}.git" "$app_dir" "$ref"
        if [[ $DRY_RUN != true ]]; then
            [[ $(git -C "$app_dir" rev-parse HEAD 2>/dev/null || true) == "$ref" ]] || \
                die "Monster UI app ${app} is not at its pinned revision"
            [[ -s $app_dir/metadata/app.json ]] || \
                die "Monster UI app ${app} has no metadata/app.json"
        fi
    done
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
    fi
}

configure_monster_ui_api() {
    local source_dir=$1
    local escaped_api
    [[ $DRY_RUN != true ]] || return 0
    git -C "$source_dir" checkout -- src/js/config.js
    escaped_api=${KAZOO_API_URL//\\/\\\\}
    escaped_api=${escaped_api//&/\\&}
    escaped_api=${escaped_api//#/\\#}
    if grep -Eq "['\"]default['\"][[:space:]]*:" "$source_dir/src/js/config.js"; then
        sed -i -E "s#(['\"]default['\"][[:space:]]*:[[:space:]]*)['\"][^'\"]*['\"]#\\1'${escaped_api}'#" \
            "$source_dir/src/js/config.js"
    else
        sed -i "/^[[:space:]]*define({/a\\\tapi: { 'default': '${escaped_api}' }," \
            "$source_dir/src/js/config.js"
    fi
    if [[ ",${MONSTER_UI_APPS_LIST}," == *',acdc,'* ]]; then
        jq --arg api "$KAZOO_API_URL" '.api_url = $api' \
            "$source_dir/src/apps/acdc/metadata/app.json" | \
            write_file 0644 "$source_dir/src/apps/acdc/metadata/app.json"
    fi
}

monster_registration_available() {
    command -v sup >/dev/null && systemctl is-active --quiet kazoo-apps.service 2>/dev/null
}

verify_monster_app_registration() {
    local registered app
    if ! monster_registration_available; then
        [[ $MONSTER_UI_REGISTER_APPS != true ]] || \
            die 'MONSTER_UI_REGISTER_APPS=true requires SUP and a running local kazoo-apps.service'
        log 'Monster UI app catalog registration is delegated to a Kazoo applications node'
        return 0
    fi
    [[ $MONSTER_UI_REGISTER_APPS != false ]] || return 0
    registered=$(timeout --signal=KILL 180 sup crossbar_maintenance apps </dev/null) || \
        die 'SUP could not read the Monster UI app catalog'
    for app in ${MONSTER_UI_APPS_LIST//,/ }; do
        grep -F "key: \"${app}\"" <<<"$registered" >/dev/null || \
            die "Monster UI app ${app} is not registered in the Kazoo master account"
    done
    log "PASS Monster UI app catalog registration: ${MONSTER_UI_APPS_LIST}"
}

register_monster_apps() {
    local output
    [[ $DRY_RUN != true ]] || return 0
    if ! monster_registration_available; then
        [[ $MONSTER_UI_REGISTER_APPS != true ]] || \
            die 'MONSTER_UI_REGISTER_APPS=true requires SUP and a running local kazoo-apps.service'
        log 'No local Kazoo applications node; skipping cluster-wide Monster UI app registration'
        return 0
    fi
    [[ $MONSTER_UI_REGISTER_APPS != false ]] || {
        log 'Monster UI app registration disabled by MONSTER_UI_REGISTER_APPS=false'
        return 0
    }
    ensure_master_account
    configure_kazoo_api_modules
    if ! output=$(timeout --signal=KILL 600 sup crossbar_maintenance init_apps \
        "$MONSTER_UI_WEB_ROOT/apps" "$KAZOO_API_URL" </dev/null 2>&1); then
        die "Could not register Monster UI apps through SUP: ${output}"
    fi
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

configure_monster_ui_nginx() {
    local tls_dir=/etc/nginx/kazoo-tls
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

    location /v2/ {
        proxy_pass ${KAZOO_API_UPSTREAM};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Connection "";
        proxy_connect_timeout 10s;
        proxy_read_timeout 120s;
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
        if [[ $DRY_RUN != true ]] && command -v restorecon >/dev/null; then
            restorecon -RF "$tls_dir"
        fi
        if [[ $DRY_RUN != true ]] && command -v getenforce >/dev/null && \
           [[ $(getenforce) != Disabled ]]; then
            run setsebool -P httpd_can_network_connect on
        fi
    else
        write_file 0644 /etc/nginx/conf.d/monster-ui.conf <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _monster_ui_default_;
    root ${MONSTER_UI_WEB_ROOT};
    index index.html;

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
}

verify_monster_ui_transport() {
    local redirect capability_url capability_status expected_capability_status=404
    local -a capability_resolve=()
    if [[ -n $KAZOO_PUBLIC_HOSTNAME ]]; then
        capability_url="https://${KAZOO_PUBLIC_HOSTNAME}/apps/acdc/language-capabilities.json"
        capability_resolve=(--resolve "${KAZOO_PUBLIC_HOSTNAME}:443:127.0.0.1")
        curl --fail --silent --show-error --connect-timeout 10 --max-time 30 \
            --resolve "${KAZOO_PUBLIC_HOSTNAME}:443:127.0.0.1" \
            "https://${KAZOO_PUBLIC_HOSTNAME}/" | grep -i '<html' >/dev/null || \
            die 'Monster UI HTTPS certificate/content check failed'
        redirect=$(curl --silent --show-error --output /dev/null --write-out '%{http_code} %{redirect_url}' \
            --connect-timeout 10 --max-time 30 --resolve "${KAZOO_PUBLIC_HOSTNAME}:80:127.0.0.1" \
            "http://${KAZOO_PUBLIC_HOSTNAME}/") || die 'Monster UI HTTP redirect check failed'
        [[ $redirect == "308 https://${KAZOO_PUBLIC_HOSTNAME}/" ]] || \
            die 'Monster UI HTTP does not redirect to the configured HTTPS hostname'
        [[ $(stat -c '%a:%U' /etc/nginx/kazoo-tls/privkey.pem) == 600:root ]] || \
            die 'nginx TLS private key must be root-owned with mode 0600'
        log "PASS HTTPS certificate, hostname, content, and HTTP redirect: ${KAZOO_PUBLIC_HOSTNAME}"
    else
        capability_url=http://127.0.0.1/apps/acdc/language-capabilities.json
        curl --fail --silent --show-error --connect-timeout 10 --max-time 30 \
            http://127.0.0.1/ | grep -i '<html' >/dev/null || die 'Monster UI HTTP content check failed'
    fi
    if [[ -e $MONSTER_UI_WEB_ROOT/apps/acdc/language-capabilities.json ]]; then
        monster_language_capability_hash >/dev/null || die 'Invalid installed language capability file'
        expected_capability_status=200
    fi
    capability_status=$(curl --silent --show-error --connect-timeout 10 --max-time 30 \
        "${capability_resolve[@]}" --output /dev/null --write-out '%{http_code}' "$capability_url") || \
        die 'Monster UI language capability route is unreachable'
    [[ $capability_status == "$expected_capability_status" ]] || \
        die 'Language capability route must return its actual file or HTTP 404, never the HTML application fallback'
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

install_monster_ui() {
    local source_dir="$KAZOO_BUILD_ROOT/monster-ui"
    local marker=/usr/local/share/kazoo5-installer/monster-ui-build
    local expected_build installed_build='' runtime_capability_hash
    log 'Installing and building Monster UI source tag 5.5.13 with the pinned Kazoo app bundle'
    install_monster_nodejs
    expected_build=$(monster_ui_build_fingerprint)
    [[ -r $marker ]] && installed_build=$(<"$marker")
    if [[ $installed_build != "$expected_build" || ! -s $MONSTER_UI_WEB_ROOT/index.html ]]; then
        sync_monster_ui_sources "$source_dir"
        if [[ $DRY_RUN != true ]]; then
            configure_monster_ui_api "$source_dir"
            (
                cd "$source_dir"
                NPM_CONFIG_YES=true npm install --no-audit --no-fund
                npm rebuild node-sass
                ./node_modules/.bin/gulp build-prod
            )
            [[ -s $source_dir/dist/index.html ]] || \
                die 'Monster UI production build did not create dist/index.html'
            for app in ${MONSTER_UI_APPS_LIST//,/ }; do
                [[ -s $source_dir/dist/apps/$app/metadata/app.json ]] || \
                    die "Monster UI production build omitted ${app} metadata"
            done
            [[ ! -e $source_dir/dist/apps/acdc/language-capabilities.json && \
               ! -L $source_dir/dist/apps/acdc/language-capabilities.json ]] || \
                die 'A Monster UI build must not manufacture runtime language readiness'
            runtime_capability_hash=$(monster_language_capability_hash) || \
                die 'Existing runtime language capability is invalid; refusing web replacement'
            mkdir -p "$MONSTER_UI_WEB_ROOT"
            rsync -a --delete --exclude='/apps/acdc/language-capabilities.json' \
                "$source_dir/dist/" "$MONSTER_UI_WEB_ROOT/"
            [[ $(monster_language_capability_hash) == "$runtime_capability_hash" ]] || \
                die 'Runtime language capability changed during the web deployment; reverify before activation'
            if command -v restorecon >/dev/null; then
                restorecon -RF "$MONSTER_UI_WEB_ROOT" || true
            fi
            monster_ui_build_fingerprint | write_file 0644 "$marker"
        else
            log "Would configure Monster UI API as ${KAZOO_API_URL} and run gulp build-prod"
        fi
    fi
    configure_monster_ui_nginx
    if [[ -f /etc/nginx/nginx.conf && $DRY_RUN != true ]]; then
        sed -i '/^[[:space:]]*server[[:space:]]*{/,/^[[:space:]]*}/ { /listen[[:space:]]\+80 default_server/d; /listen[[:space:]]\+\[::\]:80 default_server/d; }' /etc/nginx/nginx.conf
    fi
    run nginx -t
    service_enable_restart nginx.service
    wait_for_port 127.0.0.1 80 30 || die 'nginx did not open port 80'
    register_monster_apps
    verify_monster_ui
}

verify_monster_ui() {
    if [[ $DRY_RUN == true ]]; then log 'Would verify Monster UI'; return 0; fi
    local api_result api_body api_status app expected_build installed_build
    assert_service nginx.service
    expected_build=$(monster_ui_build_fingerprint)
    [[ -r /usr/local/share/kazoo5-installer/monster-ui-build ]] || \
        die 'Monster UI build fingerprint is missing'
    installed_build=$(</usr/local/share/kazoo5-installer/monster-ui-build)
    [[ $installed_build == "$expected_build" ]] || \
        die 'Deployed Monster UI does not match the requested pinned build and app bundle'
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
    api_result=$(curl --connect-timeout 10 --max-time 30 --silent --show-error \
        --write-out $'\n%{http_code}' "$KAZOO_API_URL") || \
        die "Monster UI API is unreachable: ${KAZOO_API_URL}"
    api_status=${api_result##*$'\n'}
    api_body=${api_result%$'\n'*}
    [[ $api_status =~ ^[234][0-9][0-9]$ ]] || \
        die "Monster UI API returned HTTP ${api_status}: ${KAZOO_API_URL}"
    jq -e . <<<"$api_body" >/dev/null || \
        die "Monster UI API did not return JSON: ${KAZOO_API_URL}"
    verify_monster_app_registration
    log 'PASS Monster UI, stable app bundle, API reachability, and nginx checks'
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
    verify_requested
}

main() {
    parse_arguments "$@"
    preflight
    log "Resolved components: ${!SELECTED[*]}"
    if [[ $VERIFY_ONLY == true ]]; then
        verify_requested
    else
        install_requested
        save_deployment_config
    fi
    log 'All requested Kazoo 5 components passed validation'
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
