#!/usr/bin/env bash
# One-shot, read-mostly verification of the MAIN development stack after a
# reboot of dev44, followed by starting the private lab guests. Writes a receipt
# under /root so an unattended reboot leaves evidence. It never reconfigures the
# main stack; on failure it records what is wrong and exits nonzero.
#
#   scripts/verify-dev-stack-after-boot.sh --arm     # run once at next boot
#   scripts/verify-dev-stack-after-boot.sh           # run now
set -uo pipefail
umask 077
((EUID == 0)) || { echo 'Root required' >&2; exit 1; }
readonly unit=kz5-post-boot-verify.service node_host=dev-testing
self=$(readlink -f -- "${BASH_SOURCE[0]}")

if [[ ${1:-} == --arm ]]; then
    cat > "/etc/systemd/system/$unit" <<EOF
[Unit]
Description=kz5 one-shot post-boot verification of the development stack
After=network-online.target kazoo-apps.service kazoo-ecallmgr.service kazoo-kamailio.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/bash -lc 'exec bash $self'
ExecStartPost=/usr/bin/systemctl disable $unit
TimeoutStartSec=2400
Environment=HOME=/root

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable "$unit" >/dev/null 2>&1
    echo "Armed $unit for the next boot only"
    exit 0
fi

run_dir=$(mktemp -d "/root/kz5-post-boot-$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")
receipt="$run_dir/receipt.txt"
failures=0
note() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$receipt"; }
ok() { note "PASS $*"; }
bad() { failures=$((failures + 1)); note "FAIL $*"; }
until_ok() { local tries=$1; shift; for _ in $(seq 1 "$tries"); do "$@" >/dev/null 2>&1 && return 0; sleep 5; done; return 1; }

note "Post-boot verification on $(hostname); kernel $(uname -r); SELinux $(getenforce 2>/dev/null || echo unknown)"
[[ $(hostnamectl --static) == "$node_host" ]] && ok "hostname $node_host" || bad "hostname is $(hostnamectl --static), expected $node_host"
[[ $(getent ahostsv4 "$node_host" | awk 'NR==1{print $1}') == 10.1.0.44 ]] && ok 'node name resolves to the private address' || bad 'node name does not resolve to 10.1.0.44'

for service in couchdb rabbitmq-server haproxy kazoo-apps kazoo-ecallmgr kazoo-freeswitch kazoo-kamailio nginx; do
    until_ok 60 systemctl is-active --quiet "$service" && ok "$service active" || bad "$service is $(systemctl is-active "$service")"
done
broker_node() { rabbitmqctl -q eval 'node().' 2>/dev/null | tr -d "'[:space:]"; }
until_ok 24 rabbitmqctl -q list_users
[[ $(broker_node) == "rabbit@$node_host" ]] && ok "broker identity rabbit@$node_host" || bad "broker identity is $(broker_node)"
rabbitmqctl -q list_users 2>/dev/null | awk '{print $1}' | grep -Fxq kazoo && ok 'broker has the kazoo user' || bad 'broker has no kazoo user (empty database?)'

api() { [[ $(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:8000/v2/) =~ ^[234] ]]; }
until_ok 120 api && ok 'Crossbar answers on 127.0.0.1:8000' || bad 'Crossbar does not answer'
apps_node() { [[ $(timeout 30 sup -e erlang node </dev/null 2>/dev/null | tr -d "'[:space:]") == "kazoo_apps@$node_host" ]]; }
until_ok 24 apps_node && ok "SUP reaches kazoo_apps@$node_host" || bad 'SUP cannot reach kazoo_apps'
media() { timeout 30 sup -n ecallmgr ecallmgr_maintenance list_fs_nodes </dev/null 2>/dev/null | grep -Fq "freeswitch@$node_host"; }
until_ok 60 media && ok 'eCallMgr is connected to FreeSWITCH' || bad 'eCallMgr is not connected to FreeSWITCH'

listeners=(10.1.0.44)
public=$(grep -E '^KAMAILIO_PUBLIC_SIP_IP=' /etc/kazoo/deployment.env 2>/dev/null | cut -d= -f2- | base64 -d 2>/dev/null || true)
[[ -n $public ]] && listeners+=("$public")
for address in "${listeners[@]}"; do
    until_ok 24 bash -c "ss -H -lun 'sport = :5060' | grep -Fq '$address:5060'" && ok "Kamailio listens on $address:5060/udp" || bad "Kamailio is not listening on $address:5060/udp"
done
restarts=$(systemctl show -p NRestarts --value kazoo-kamailio)
[[ $restarts -lt 5 ]] && ok "Kamailio restarts $restarts" || bad "Kamailio restarted $restarts times"

# The Erlang port mapper must be the socket-activated service after a boot, not
# a daemon inside whichever Kazoo unit started first, and every role must be in it.
mapper=$(systemctl show -p MainPID --value epmd.service 2>/dev/null)
[[ $(systemctl is-active epmd.socket) == active && ${mapper:-0} != 0 ]] && ok "port mapper is epmd.service (pid $mapper)" || bad 'port mapper is not the socket-activated epmd.service'
for name in couchdb rabbit kazoo_apps ecallmgr freeswitch; do
    until_ok 24 bash -c "epmd -names 2>/dev/null | grep -q '^name $name '" && ok "$name registered with the port mapper" || bad "$name is not registered with the port mapper"
done
listeners=$(ss -H -ltn 'sport = :4369' | awk '{print $4}' | sort | tr '\n' ' ')
[[ $listeners != *'0.0.0.0:4369'* && $listeners != *'[::]:4369'* && $listeners == *'127.0.0.1:4369'* ]] && ok "port mapper listeners: $listeners" || bad "port mapper listeners: $listeners"
# The functional check the timer runs; here once, with its FAIL lines in the receipt.
if health=$(/usr/local/libexec/kazoo5-stack-health 2>&1); then ok 'stack health: failures=0'; else bad "stack health: $(grep '^FAIL' <<<"$health" | tr '\n' ';')"; fi
[[ $(sed -n 's/^[[:space:]]*NODENAME=//p' /etc/rabbitmq/rabbitmq-env.conf 2>/dev/null | tail -n 1) == "rabbit@${node_host}" ]] && ok 'broker node name pin intact' || bad 'broker node name pin is missing or wrong'

if [[ $(getenforce 2>/dev/null) == Disabled ]]; then
    note 'SKIP lab guests: SELinux is disabled and their stored mount labels cannot be mounted'
else
    # podman leaves conmon in the calling service's cgroup. When this one-shot
    # unit ended on September 18, 2026 systemd killed the monitors of nine
    # guests; they kept running unmonitored and the next "podman restart"
    # failed with "conmon process killed". Each guest gets its own scope.
    start_guest() {
        systemd-run --quiet --scope --slice=machine.slice podman start "$1" >/dev/null 2>&1
    }
    for guest in kz5-stage-couchdb kz5-stage-rabbitmq; do start_guest "$guest"; done
    sleep 25
    for guest in kz5-stage-haproxy kz5-stage-freeswitch; do start_guest "$guest"; done
    sleep 15
    for guest in kz5-stage-kazoo-apps kz5-stage-ecallmgr kz5-stage-kamailio kz5-stage-kazoo-apps-peer kz5-stage-ecallmgr-peer kz5-stage-push-bridge; do
        start_guest "$guest"
    done
    sleep 10
    running=$(podman ps --format '{{.Names}}' | grep -c '^kz5-stage-')
    [[ $running -ge 10 ]] && ok "lab guests running: $running" || bad "only $running lab guests are running"
    unmonitored=0
    for guest in $(podman ps --format '{{.Names}}' | grep '^kz5-stage-'); do
        monitor=$(podman inspect -f '{{.State.ConmonPid}}' "$guest")
        [[ $(cat "/proc/${monitor}/comm" 2>/dev/null) == conmon && $(cut -d: -f3 "/proc/${monitor}/cgroup") != *"$unit"* ]] || \
            unmonitored=$((unmonitored + 1))
    done
    [[ $unmonitored == 0 ]] && ok 'every lab guest monitor is alive outside this unit' || bad "$unmonitored lab guests have no monitor that outlives this unit"
    until_ok 36 podman exec kz5-stage-couchdb systemctl is-active --quiet couchdb && ok 'lab CouchDB active' || bad 'lab CouchDB is not active'
fi

note "RESULT failures=$failures receipt=$receipt"
((failures == 0))
