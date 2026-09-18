#!/usr/bin/env bash
# Offline regression for the installed node identity: the start guard, the
# installer's refusal of a changed hostname, and the pinned RabbitMQ node name.
# Reproduces the September 18, 2026 outage inputs. Nothing under /etc is touched.
set -Eeuo pipefail
umask 077
ni_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
ni_installer="$ni_root/scripts/install-kazoo5.sh"
ni_guard="$ni_root/scripts/kazoo5-identity-guard.sh"
ni_work=$(mktemp -d /tmp/kazoo-node-identity.XXXXXX)
trap 'rm -rf -- "$ni_work"' EXIT
ni_pass=0
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { ni_pass=$((ni_pass + 1)); printf 'PASS: %s\n' "$*"; }
function_body() { sed -n "/^$1() {\$/,/^}\$/p" "$ni_installer"; }
host=$(hostname -f 2>/dev/null || hostname)

bash -n "$ni_installer"; bash -n "$ni_guard"
guard() {   # identity-file config role -> prints message, returns guard status
    KAZOO_NODE_IDENTITY_FILE=$1 KAZOO_CONFIG=$2 bash "$ni_guard" "$3" 2>&1
}
printf 'NODE_HOST=%s\n' "$host" > "$ni_work/identity"
printf '[kazoo_apps]\ncookie = x\nhost = %s\n\n[ecallmgr]\ncookie = x\nhost = %s\n' "$host" "$host" > "$ni_work/good.ini"
guard "$ni_work/identity" "$ni_work/good.ini" kazoo_apps >/dev/null || fail 'consistent identity refused'
guard "$ni_work/identity" "$ni_work/good.ini" ecallmgr >/dev/null || fail 'consistent ecallmgr identity refused'
pass 'consistent identity starts'

expect_refusal() {   # description expected-text identity config role
    local out status=0
    out=$(guard "$3" "$4" "$5") || status=$?
    [[ $status == 78 ]] || fail "$1: exit $status, expected 78"
    grep -Fq "$2" <<<"$out" || fail "$1: message lacks '$2': $out"
    [[ $(wc -l <<<"$out") == 1 ]] || fail "$1: expected exactly one line"
}
# The outage: config.ini hand-edited to the public DNS name.
printf '[kazoo_apps]\nhost = kz5-dev.talkchief.io\n[ecallmgr]\nhost = kz5-dev.talkchief.io\n' > "$ni_work/edited.ini"
expect_refusal 'edited config.ini' "says host = 'kz5-dev.talkchief.io'" "$ni_work/identity" "$ni_work/edited.ini" ecallmgr
# The outage: hostname changed after installation.
printf 'NODE_HOST=installed-elsewhere.example.net\n' > "$ni_work/other"
expect_refusal 'changed hostname' 'hostnamectl set-hostname installed-elsewhere.example.net' "$ni_work/other" "$ni_work/good.ini" kazoo_apps
printf '[kazoo_apps]\ncookie = x\n' > "$ni_work/nohost.ini"
expect_refusal 'section without host' 'starts on defaults' "$ni_work/identity" "$ni_work/nohost.ini" kazoo_apps
expect_refusal 'missing identity file' 'is missing' "$ni_work/absent" "$ni_work/good.ini" kazoo_apps
printf 'NODE_HOST=bad host;rm\n' > "$ni_work/garbage"
expect_refusal 'invalid identity file' 'no valid NODE_HOST' "$ni_work/garbage" "$ni_work/good.ini" kazoo_apps
expect_refusal 'unreadable config' 'is not readable' "$ni_work/identity" "$ni_work/absent.ini" kazoo_apps
expect_refusal 'unknown role' 'unknown role' "$ni_work/identity" "$ni_work/good.ini" freeswitch
pass 'seven inconsistent identities refuse with exit 78 and one explicit line each'

units=$(function_body install_kazoo_systemd_units)
for role in kazoo_apps ecallmgr; do
    grep -Fq "ExecStartPre=+/usr/local/libexec/kazoo5-identity-guard ${role}" <<<"$units" || fail "unit for ${role} lacks the start guard"
done
[[ $(grep -c '^RestartPreventExitStatus=78$' <<<"$units") == 2 ]] || fail 'a refused start must stay failed, not loop'
grep -Fq 'install_kazoo_identity_guard' <<<"$units" || fail 'guard is not installed with the units'
# The guard must run before anything else can start the node on defaults.
awk '/ExecStartPre=/{print; exit}' <<<"$units" | grep -Fq 'kazoo5-identity-guard' || fail 'guard is not the first ExecStartPre'
grep -Fq 'verify_kazoo_identity_guard kazoo_apps' <<<"$(function_body verify_kazoo_apps)" || fail 'apps verification omits identity'
grep -Fq 'verify_kazoo_identity_guard ecallmgr' <<<"$(function_body verify_ecallmgr)" || fail 'ecallmgr verification omits identity'
pass 'both units run the guard first, stay failed on refusal, and verification checks identity'

# Installer refuses a changed hostname before doing anything, in every mode.
config="$ni_work/deployment.env"
printf 'KAZOO_NODE_HOST=%s\n' "$(printf 'installed-elsewhere.example.net' | base64 -w0)" > "$config"; chmod 0600 "$config"
for mode in '--dry-run kazoo-apps' '--verify-only kazoo-apps'; do
    status=0
    # shellcheck disable=SC2086
    out=$(KAZOO_DEPLOYMENT_CONFIG="$config" KAZOO_CONFIG_DIR="$ni_work/etc" bash "$ni_installer" $mode 2>&1) || status=$?
    [[ $status != 0 ]] || fail "installer accepted a changed hostname in: $mode"
    grep -Fq "was installed as 'installed-elsewhere.example.net'" <<<"$out" || fail "refusal lacks the cause in: $mode"
    grep -Fq 'hostnamectl set-hostname installed-elsewhere.example.net' <<<"$out" || fail "refusal lacks the remedy in: $mode"
done
printf 'KAZOO_NODE_HOST=%s\n' "$(printf '%s' "$host" | base64 -w0)" > "$config"
KAZOO_DEPLOYMENT_CONFIG="$config" KAZOO_CONFIG_DIR="$ni_work/etc" bash "$ni_installer" --dry-run rabbitmq >/dev/null 2>&1 || \
    fail 'installer refused the unchanged hostname'
grep -Fq 'KAZOO_COOKIE_FILE KAZOO_NODE_HOST' "$ni_installer" || fail 'installed identity is not persisted'
pass 'installer refuses a changed hostname with cause and remedy in dry-run and verify-only; unchanged passes; identity persisted'

pin() {   # env-file node-host [dry]
    (
        DRY_RUN=${3:-false} KAZOO_NODE_HOST=$2 KAZOO_RABBITMQ_ENV_FILE=$1
        log() { printf '%s\n' "$*"; }
        die() { printf '%s\n' "$*" >&2; exit 1; }
        eval "$(function_body rabbitmq_node_name)"; eval "$(function_body pin_rabbitmq_node_name)"
        pin_rabbitmq_node_name
    )
}
env_file="$ni_work/rabbitmq-env.conf"
pin "$env_file" broker1.example.net | grep -Fq 'Pinned the RabbitMQ node name rabbit@broker1' || fail 'first pin'
grep -Fxq 'NODENAME=rabbit@broker1' "$env_file" || fail 'pin not written as the short node name'
before=$(sha256sum < "$env_file"); pin "$env_file" broker1.example.net >/dev/null
[[ $(sha256sum < "$env_file") == "$before" ]] || fail 'repeat pin rewrote the file'
if pin "$env_file" renamed.example.net >/dev/null 2>&1; then fail 'an existing pin was re-keyed'; fi
[[ $(sha256sum < "$env_file") == "$before" ]] || fail 'a refused re-key modified the file'
printf '# operator settings\nRABBITMQ_NODE_PORT=5672\n' > "$ni_work/existing.conf"
pin "$ni_work/existing.conf" broker1 >/dev/null
grep -Fxq 'RABBITMQ_NODE_PORT=5672' "$ni_work/existing.conf" && grep -Fxq 'NODENAME=rabbit@broker1' "$ni_work/existing.conf" || \
    fail 'existing operator settings were not preserved'
[[ $(pin "$ni_work/dry.conf" broker1 true) == 'Would pin the RabbitMQ node name rabbit@broker1' && ! -e $ni_work/dry.conf ]] || fail 'dry run wrote a file'
grep -Fq 'pin_rabbitmq_node_name' <<<"$(function_body install_rabbitmq)" || fail 'broker installation does not pin the node name'
grep -Fq 'verify_rabbitmq_node_name' <<<"$(function_body verify_rabbitmq)" || fail 'broker verification does not check the node name'
pass 'broker node name pinned once, idempotent, never re-keyed, operator settings kept, dry run inert, installed and verified'
printf 'All %d node identity groups passed\n' "$ni_pass"
