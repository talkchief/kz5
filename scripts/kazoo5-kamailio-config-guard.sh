#!/usr/bin/env bash
# Start guard for kazoo-kamailio. Installed by install-kazoo5.sh as
# /usr/local/libexec/kazoo5-kamailio-config-guard and run as ExecStartPre.
#
# An invalid configuration cannot repair itself. With Restart=on-failure alone,
# seven hand-added lines in local.cfg made Kamailio restart 4,367 times in seven
# hours (September 18, 2026) with the cause buried in a scrolling journal. This
# guard runs Kamailio's own configuration check first. On failure it reports the
# parser's first errors once, at err priority, and exits 78; the unit sets
# RestartPreventExitStatus=78 so it stays failed and visible in
# `systemctl --failed`. Runtime crashes still restart as before. Read-only.
set -uo pipefail
check=${KAZOO_KAMAILIO_CHECK:-/usr/sbin/kazoo-kamailio check}

# shellcheck disable=SC2086
output=$($check 2>&1)
status=$?
((status != 0)) || exit 0

reason=$(grep -E 'CRITICAL|ERROR' <<<"$output" | grep -vE '^ERROR: Invalid configuration file' | head -n 3 | \
    sed -E 's/^[[:space:]]*[0-9]+\([0-9]+\)[[:space:]]*//' | tr '\n' ' ')
message="kazoo5-kamailio-config-guard: REFUSING to start Kamailio: its configuration check failed (${reason:-no parser detail}). \
Fix the configuration, verify with '/usr/sbin/kazoo-kamailio check', then 'systemctl reset-failed kazoo-kamailio && systemctl start kazoo-kamailio'. \
Listener macros such as UDP_SIP cannot be used in local.cfg; use the installer option KAMAILIO_PUBLIC_SIP_IP."
printf '%s\n' "$message" >&2
command -v logger >/dev/null 2>&1 && logger -p daemon.err -t kazoo5-kamailio-config-guard -- "$message"
exit 78
