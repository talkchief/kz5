#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Run scripts/install-kazoo5.sh on another host, for Jenkins or by hand.
#
# This is not a second installation path: on the target it runs the installer and
# nothing else. It only does what the installer cannot do for itself on a machine
# it is not on yet: put this exact commit there, hand over the host's settings,
# start the installer as a systemd unit (an SSH drop must not kill an install
# half way), follow it, and check that the selected services are enabled, active
# and healthy. Wiring a new eCallMgr or FreeSWITCH into the cluster (sup
# commands) is deliberately left to the operator.
#
#   remote-install-kazoo5.sh --host 10.0.0.21 (--identity KEY | --password-env VAR) [--user root]
#       [--port 22] [--env-file FILE] [--action install|dry-run|verify-only]
#       [--allow-active-calls] COMPONENT [COMPONENT ...]
#
# --password-env VAR: log in with the password held in environment variable VAR. It is
# never put on a command line: ssh asks a private helper for it (SSH_ASKPASS).
#
# --env-file: KEY=value lines with the installer's inputs for that host (addresses,
# cookie, passwords; see install-kazoo5.sh --help). It is copied root-only, given to
# the installer's unit and removed again, also when the run fails.
# shellcheck disable=SC2016,SC2029  # remote command strings are expanded on the target on purpose
set -Eeuo pipefail
ri_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
readonly ri_root
readonly RI_COMPONENTS='couchdb rabbitmq haproxy kazoo-apps ecallmgr freeswitch kamailio monster-ui push-bridge'
readonly RI_REMOTE_ROOT=/opt/kz5 RI_STATE=/var/lib/kazoo-remote-install RI_LOGS=/var/log/kazoo-remote-install

die() { printf '[remote-install] ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '[remote-install] %s\n' "$*"; }

component_unit() {
    case $1 in
        couchdb) echo couchdb ;;
        rabbitmq) echo rabbitmq-server ;;
        haproxy) echo haproxy ;;
        kazoo-apps) echo kazoo-apps ;;
        ecallmgr) echo kazoo-ecallmgr ;;
        freeswitch) echo kazoo-freeswitch ;;
        kamailio) echo kazoo-kamailio ;;
        monster-ui) echo nginx ;;
        push-bridge) echo kazoo-push-bridge ;;
        *) return 1 ;;
    esac
}

ri_host='' ri_user=root ri_port=22 ri_identity='' ri_password_env='' ri_env_file='' ri_action=install ri_allow_calls=false
ri_components=()
while (($#)); do
    case $1 in
        --host) (($# >= 2)) || die '--host needs a value'; ri_host=$2; shift ;;
        --user) (($# >= 2)) || die '--user needs a value'; ri_user=$2; shift ;;
        --port) (($# >= 2)) || die '--port needs a value'; ri_port=$2; shift ;;
        --identity) (($# >= 2)) || die '--identity needs a file'; ri_identity=$2; shift ;;
        --password-env) (($# >= 2)) || die '--password-env needs a variable name'; ri_password_env=$2; shift ;;
        --env-file) (($# >= 2)) || die '--env-file needs a file'; ri_env_file=$2; shift ;;
        --action) (($# >= 2)) || die '--action needs a value'; ri_action=$2; shift ;;
        --allow-active-calls) ri_allow_calls=true ;;
        -h|--help) sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        --*) die "Unknown option: $1" ;;
        *) ri_components+=("$1") ;;
    esac
    shift
done

[[ $ri_host =~ ^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$ ]] || die 'Give --host as a host name or IPv4 address'
[[ $ri_user =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die 'Invalid --user'
if [[ ! $ri_port =~ ^[0-9]{1,5}$ ]] || ((ri_port < 1 || ri_port > 65535)); then die 'Invalid --port'; fi
[[ $ri_action == install || $ri_action == dry-run || $ri_action == verify-only ]] || die '--action is install, dry-run or verify-only'
if [[ -n $ri_password_env ]]; then
    [[ -z $ri_identity ]] || die 'Give --identity or --password-env, not both'
    [[ $ri_password_env =~ ^[A-Za-z_][A-Za-z0-9_]*$ && -n ${!ri_password_env:-} ]] || die '--password-env must name a non-empty environment variable'
else
    [[ -n $ri_identity && -f $ri_identity && ! -L $ri_identity ]] || die 'Give --identity (an SSH private key file) or --password-env'
fi
((${#ri_components[@]} >= 1)) || die 'Name at least one component'
[[ " ${ri_components[*]} " != *' all '* ]] || read -r -a ri_components <<<"$RI_COMPONENTS"
declare -A ri_seen=()
for ri_component in "${ri_components[@]}"; do
    [[ " $RI_COMPONENTS " == *" $ri_component "* ]] || die "Unknown component: ${ri_component} (one of: ${RI_COMPONENTS}, all)"
    [[ -z ${ri_seen[$ri_component]:-} ]] || die "Component named twice: ${ri_component}"
    ri_seen[$ri_component]=1
done
if [[ -n $ri_env_file ]]; then
    [[ -f $ri_env_file && ! -L $ri_env_file ]] || die '--env-file must be a regular file'
    # Exactly the installer's own namespaces, one assignment per line: nothing here is ever evaluated by a shell.
    if grep -Evq '^(#.*|[[:space:]]*|(KAZOO|KAMAILIO|FREESWITCH|COUCHDB|RABBITMQ|MONSTER|PUSH_BRIDGE|ACDC)_[A-Z0-9_]*=[^`$]*)$' "$ri_env_file"; then
        die '--env-file may hold only KAZOO_*/KAMAILIO_*/... KEY=value lines without $ or backticks'
    fi
fi
[[ -z $(git -C "$ri_root" status --porcelain --untracked-files=no) ]] || die 'The source tree has uncommitted changes; deploy a commit, not a working copy'
ri_source=$(git -C "$ri_root" rev-parse HEAD)
readonly ri_source
ri_run="$(date -u +%Y%m%dT%H%M%SZ)-${ri_source:0:7}"
readonly ri_run

ri_work=$(mktemp -d "${TMPDIR:-/tmp}/kz5-remote-install.XXXXXX")
ri_common=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -o ServerAliveInterval=30)
if [[ -n $ri_password_env ]]; then
    # ssh asks this helper instead of a terminal; the password travels in the environment only.
    printf '#!/bin/sh\nprintf "%%s\\n" "$RI_SSH_PASSWORD"\n' > "$ri_work/askpass"
    chmod 0700 "$ri_work/askpass"
    RI_SSH_PASSWORD=${!ri_password_env}
    export RI_SSH_PASSWORD SSH_ASKPASS="$ri_work/askpass" SSH_ASKPASS_REQUIRE=force DISPLAY="${DISPLAY:-none}"
    ri_common+=(-o PubkeyAuthentication=no -o "PreferredAuthentications=password,keyboard-interactive" -o NumberOfPasswordPrompts=1)
else
    ri_common+=(-i "$ri_identity" -o BatchMode=yes -o IdentitiesOnly=yes)
fi
ri_ssh=(ssh -p "$ri_port" "${ri_common[@]}" "${ri_user}@${ri_host}")
ri_scp=(scp -q -P "$ri_port" "${ri_common[@]}")
remote() { "${ri_ssh[@]}" "$@"; }

cleanup() {
    # The host's settings never stay behind, whatever happened. This must come before the
    # work directory goes: it holds the password helper, and without it this last login
    # failed silently and four settings files stayed on the first real server
    # (September 20, 2026).
    remote "rm -f -- ${RI_STATE}/input-*.env" >/dev/null 2>&1 || true
    rm -rf -- "$ri_work"
}
trap cleanup EXIT

log "Target ${ri_user}@${ri_host}, action ${ri_action}, components: ${ri_components[*]}, source ${ri_source}"
remote true || die 'Could not log in to the target: check the address, the user and the credential'
remote 'test "$(id -u)" = 0' || die 'The remote user must be root (the installer requires it)'
remote 'grep -Eq "^ID=\"?rocky\"?$" /etc/os-release && grep -Eq "^VERSION_ID=\"?9" /etc/os-release' || die 'The installer supports Rocky Linux 9 only'
remote "install -d -m 0700 ${RI_STATE} ${RI_LOGS}"
if remote 'systemctl list-units --no-legend --state=activating,active "kz5-remote-install-*" | grep -q .'; then
    die 'Another remote installation is still running on that host'
fi

# A server keeps its settings only after an installation that passed. Without them the
# installer detects addresses itself, and on a host with a public interface it chose that
# one for SIP (first real server, Jenkins build 12).
if [[ $ri_action == install && -z $ri_env_file ]]; then
    remote 'test -s /etc/kazoo/deployment.env' || \
        die 'This server has no saved settings yet (no installation has passed on it): give its settings with --env-file'
fi

if [[ $ri_action != dry-run && $ri_allow_calls != true ]]; then
    ri_calls=$(remote 'if [ -x /usr/local/freeswitch/bin/fs_cli ] && systemctl is-active --quiet kazoo-freeswitch; then /usr/local/freeswitch/bin/fs_cli -x "show channels count" | sed -n "s/^\([0-9][0-9]*\) total.*/\1/p"; else echo 0; fi')
    [[ $ri_calls =~ ^[0-9]+$ ]] || die 'Could not read the live channel count on the target; refusing to restart services blind'
    ((ri_calls == 0)) || die "The target carries ${ri_calls} live channel(s); drain it first or pass --allow-active-calls"
fi

# The exact commit, as a bundle: the target needs no access to the repository host.
git -C "$ri_root" bundle create "$ri_work/source.bundle" HEAD >/dev/null 2>&1 || die 'Could not bundle the source'
"${ri_scp[@]}" "$ri_work/source.bundle" "${ri_user}@${ri_host}:${RI_STATE}/source-${ri_run}.bundle"
remote 'command -v git >/dev/null || dnf -y -q install git-core' || die 'git is required on the target to receive the source'
remote "set -e
    if [ -d ${RI_REMOTE_ROOT}/.git ]; then
        test -z \"\$(git -C ${RI_REMOTE_ROOT} status --porcelain --untracked-files=no)\" || { echo 'tracked files were edited on the target' >&2; exit 3; }
        git -C ${RI_REMOTE_ROOT} fetch -q ${RI_STATE}/source-${ri_run}.bundle HEAD
    else
        test ! -e ${RI_REMOTE_ROOT} || { echo '${RI_REMOTE_ROOT} exists and is not this repository' >&2; exit 3; }
        git clone -q ${RI_STATE}/source-${ri_run}.bundle ${RI_REMOTE_ROOT}
    fi
    git -C ${RI_REMOTE_ROOT} checkout -q --detach ${ri_source}
    test \"\$(git -C ${RI_REMOTE_ROOT} rev-parse HEAD)\" = ${ri_source}
    rm -f -- ${RI_STATE}/source-${ri_run}.bundle" || die "Could not place commit ${ri_source} in ${RI_REMOTE_ROOT} on the target"
log "PASS source ${ri_source} is checked out in ${RI_REMOTE_ROOT}"

ri_environment=''
if [[ -n $ri_env_file ]]; then
    "${ri_scp[@]}" "$ri_env_file" "${ri_user}@${ri_host}:${RI_STATE}/input-${ri_run}.env"
    remote "chmod 0600 ${RI_STATE}/input-${ri_run}.env"
    ri_environment="-p EnvironmentFile=${RI_STATE}/input-${ri_run}.env"
fi
ri_flag=''
[[ $ri_action != dry-run ]] || ri_flag=--dry-run
[[ $ri_action != verify-only ]] || ri_flag=--verify-only
readonly ri_unit="kz5-remote-install-${ri_run}" ri_log="${RI_LOGS}/${ri_run}.log"

# The one thing this wrapper runs on the target. The unit itself removes the settings when
# the installer ends: an aborted Jenkins build cannot run this wrapper's clean-up, and one
# settings file stayed behind that way (build 14). The log is created private first; the
# installer itself keeps the ordinary umask (under 077 its build was unreadable to the
# kazoo user: Jenkins build 9).
remote "systemd-run --quiet --unit ${ri_unit} -p RemainAfterExit=yes -p TimeoutStartSec=5400 -E HOME=/root ${ri_environment} \
    /usr/bin/bash -c 'install -m 0600 /dev/null ${ri_log}; /usr/bin/bash ${RI_REMOTE_ROOT}/scripts/install-kazoo5.sh ${ri_flag} ${ri_components[*]} >> ${ri_log} 2>&1; status=\$?; rm -f -- ${RI_STATE}/input-${ri_run}.env; exit \$status'" \
    || die 'Could not start the installer on the target'
log "Installer running on the target as ${ri_unit}; full log there: ${ri_log}"

ri_shown=0 ri_lost=0
while :; do
    sleep "${RI_POLL_SECONDS:-15}"
    # By property name: systemd prints properties in its own order, not the order asked.
    if ! ri_state=$(remote "systemctl show -p SubState -p ExecMainStatus ${ri_unit}; printf 'Lines=%s\n' \"\$(grep -c '' ${ri_log})\""); then
        ri_lost=$((ri_lost + 1))
        ((ri_lost < 40)) || die "Lost contact with the target for ten minutes; the installer keeps running there as ${ri_unit}"
        continue
    fi
    ri_lost=0
    ri_substate=$(sed -n 's/^SubState=//p' <<<"$ri_state")
    ri_status=$(sed -n 's/^ExecMainStatus=//p' <<<"$ri_state")
    ri_lines=$(sed -n 's/^Lines=//p' <<<"$ri_state")
    [[ $ri_lines =~ ^[0-9]+$ && -n $ri_substate ]] || die "Unreadable unit state on the target; the installer keeps running there as ${ri_unit}"
    if ((ri_lines > ri_shown)); then
        # Only the installer's own status lines: the full log can name settings.
        remote "sed -n '$((ri_shown + 1)),${ri_lines}p' ${ri_log} | grep -E '^\[kazoo5\] '" || true
        ri_shown=$ri_lines
    fi
    [[ $ri_substate == running || $ri_substate == start ]] || break
done
remote "systemctl reset-failed ${ri_unit} >/dev/null 2>&1; systemctl stop ${ri_unit} >/dev/null 2>&1" || true
[[ $ri_status == 0 ]] || die "The installer exited ${ri_status} on the target; read ${ri_log} there"
log "PASS installer ${ri_action} exited 0"

if [[ $ri_action == install ]]; then
    for ri_component in "${ri_components[@]}"; do
        ri_service=$(component_unit "$ri_component").service
        [[ $(remote "systemctl is-enabled ${ri_service}") == enabled ]] || die "${ri_service} is not enabled: it would not come back after a reboot"
        [[ $(remote "systemctl is-active ${ri_service}") == active ]] || die "${ri_service} is not active"
        log "PASS ${ri_service} enabled and active"
    done
    remote '/usr/local/libexec/kazoo5-stack-health' | sed 's/^/[target health] /' || die 'The stack health check fails on the target'
fi
log "RESULT PASS ${ri_action} of ${ri_components[*]} on ${ri_host} at ${ri_source}"
