#!/usr/bin/env bash
# Install the explicitly requested MASTER account fixture-phone service.
# Default is a non-mutating dry run; installation enables but does not start it.
set -Eeuo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
readonly SCRIPT_DIR
readonly UNIT_PATH=/etc/systemd/system/kazoo-live-test-agents.service

unit_text() {
    printf '%s\n' \
        '[Unit]' \
        'Description=Kazoo MASTER live test agents (30 receive-only SIP/RTP echo phones)' \
        'Documentation=file:/opt/kz5/doc/live_test_agents.md' \
        'Wants=kazoo-apps.service kazoo-ecallmgr.service kazoo-freeswitch.service kazoo-kamailio.service' \
        'After=network-online.target kazoo-apps.service kazoo-ecallmgr.service kazoo-freeswitch.service kazoo-kamailio.service' \
        'StartLimitIntervalSec=600' \
        'StartLimitBurst=5' \
        '' \
        '[Service]' \
        'Type=notify' \
        'NotifyAccess=all' \
        'User=root' \
        'Group=root' \
        'UMask=0077' \
        'RuntimeDirectory=kazoo-live-test-agents' \
        'RuntimeDirectoryMode=0700' \
        'RuntimeDirectoryPreserve=restart' \
        'WorkingDirectory=/run/kazoo-live-test-agents' \
        "ExecStart=/usr/bin/bash $SCRIPT_DIR/run-live-test-agents.sh --run" \
        "ExecStopPost=/usr/bin/bash $SCRIPT_DIR/run-live-test-agents.sh --cleanup" \
        'Restart=on-failure' \
        'RestartSec=15' \
        'KillMode=mixed' \
        'TimeoutStartSec=300' \
        'TimeoutStopSec=300' \
        'NoNewPrivileges=true' \
        'PrivateTmp=true' \
        'ProtectHome=true' \
        'ProtectSystem=full' \
        'ReadWritePaths=/etc/kazoo/live-test-agents.lock' \
        'RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX AF_NETLINK' \
        'LimitNOFILE=4096' \
        'TasksMax=256' \
        'StandardOutput=journal' \
        'StandardError=journal' \
        '' \
        '[Install]' \
        'WantedBy=multi-user.target'
}

case ${1:---dry-run} in
    --dry-run)
        [[ $# -le 1 ]] || exit 2
        printf '%s\n' 'DRY RUN: would install and enable kazoo-live-test-agents.service; would NOT start it.'
        unit_text
        ;;
    --install)
        [[ $# == 1 && $EUID == 0 ]] || { printf '%s\n' 'Root is required for --install' >&2; exit 1; }
        [[ $SCRIPT_DIR =~ ^/opt/[A-Za-z0-9._/-]+/scripts$ && $SCRIPT_DIR != *..* ]] || exit 1
        for file in run-live-test-agents.sh provision-live-test-agents.cjs sip-tests/live-agent-register.xml sip-tests/agent-answer.xml sip-tests/register.xml; do
            [[ -f $SCRIPT_DIR/$file && ! -L $SCRIPT_DIR/$file ]] || { printf '%s\n' 'A required service source file is missing' >&2; exit 1; }
        done
        [[ ! -L $UNIT_PATH ]] || { printf '%s\n' 'Refusing a symlinked unit path' >&2; exit 1; }
        unit_text >"$UNIT_PATH"
        chmod 0644 "$UNIT_PATH"
        systemd-analyze verify "$UNIT_PATH"
        systemctl daemon-reload
        systemctl enable kazoo-live-test-agents.service
        printf '%s\n' 'Installed and enabled kazoo-live-test-agents.service; NOT started. Start only after deployment coordination.'
        ;;
    *) printf '%s\n' 'Usage: install-live-test-agents.sh [--dry-run|--install]' >&2; exit 2 ;;
esac
