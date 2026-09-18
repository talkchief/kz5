#!/usr/bin/env bash
# Start guard for Kazoo Erlang nodes. Installed by install-kazoo5.sh as
# /usr/local/libexec/kazoo5-identity-guard and run as ExecStartPre.
#
# RabbitMQ's database, the Erlang node names, the `host =` sections of
# config.ini and the per-node system_config documents are all keyed by the host
# name the node was installed with. When that identity no longer matches, Kazoo
# does not fail: it starts on built-in defaults (amqp://127.0.0.1) while systemd
# reports it active. On September 18, 2026 that was a seven-hour outage. This
# guard turns the same condition into one explicit error and a failed unit.
#
# Exit 0: identity consistent. Exit 78 (EX_CONFIG): refuse to start; the unit
# sets RestartPreventExitStatus=78 so it stays failed instead of looping.
# Read-only; never repairs anything.
set -uo pipefail
identity=${KAZOO_NODE_IDENTITY_FILE:-/etc/kazoo/node-identity}
config=${KAZOO_CONFIG:-/etc/kazoo/core/config.ini}
role=${1:-}

refuse() {
    local message="kazoo5-identity-guard: REFUSING to start ${role:-node}: $*"
    printf '%s\n' "$message" >&2
    command -v logger >/dev/null 2>&1 && logger -p daemon.err -t kazoo5-identity-guard -- "$message"
    exit 78
}

[[ $role == kazoo_apps || $role == ecallmgr ]] || refuse "unknown role '${role}' (expected kazoo_apps or ecallmgr)"
[[ -f $identity && ! -L $identity ]] || refuse "installed identity file ${identity} is missing; rerun the installer for this role"
installed=$(sed -n 's/^NODE_HOST=//p' "$identity" | head -n 1)
[[ $installed =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || refuse "installed identity file ${identity} has no valid NODE_HOST"

current=$(hostname -f 2>/dev/null || hostname)
[[ $current == "$installed" ]] || refuse "this host was installed as '${installed}' but its hostname is now '${current}'. \
RabbitMQ data, Erlang node names and per-node configuration are keyed by the installed name. \
Restore it with: hostnamectl set-hostname ${installed}   (a hostname change needs a migration, see doc/PRODUCTION_READINESS_PLAN.md gate A6)"

address=$(getent ahostsv4 "$installed" 2>/dev/null | awk 'NR==1{print $1}')
[[ -n $address ]] || refuse "installed host name '${installed}' does not resolve to an IPv4 address; restore its /etc/hosts or DNS entry"
if [[ $address != 127.* ]]; then
    ip -o -4 address show 2>/dev/null | grep -Fq " ${address}/" || \
        refuse "installed host name '${installed}' resolves to ${address}, which is not an address of this host"
fi

[[ -r $config ]] || refuse "Kazoo configuration ${config} is not readable"
section_host=$(awk -v want="[$role]" '
    /^\[/ { inside = ($0 == want) }
    inside && /^[[:space:]]*host[[:space:]]*=/ { sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); print; exit }
' "$config")
[[ -n $section_host ]] || refuse "${config} has no host entry in section [${role}]; without it this node starts on defaults"
[[ $section_host == "$installed" ]] || refuse "${config} section [${role}] says host = '${section_host}' but this node was installed as '${installed}'"
exit 0
