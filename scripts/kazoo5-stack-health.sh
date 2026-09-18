#!/usr/bin/env bash
# Functional health of the Kazoo roles installed on this host. Installed by
# install-kazoo5.sh as /usr/local/libexec/kazoo5-stack-health and run by
# kazoo5-stack-health.timer shortly after boot and then periodically.
#
# systemd's "active" only means a process exists. On September 18, 2026
# kazoo-apps and kazoo-ecallmgr were "active" for seven hours while the broker
# refused their logins and the API was dead. Each check below asks the role to
# do its job. Any failure is logged at err priority and the unit fails, so the
# condition is visible in `systemctl --failed` and to any log alerting; the next
# healthy run clears it. Read-only: it never restarts or reconfigures anything.
set -uo pipefail
deployment=${KAZOO_DEPLOYMENT_CONFIG:-/etc/kazoo/deployment.env}
identity=${KAZOO_NODE_IDENTITY_FILE:-/etc/kazoo/node-identity}
failures=0

fail() {
    failures=$((failures + 1))
    printf 'FAIL %s\n' "$*" >&2
    command -v logger >/dev/null 2>&1 && logger -p daemon.err -t kazoo5-stack-health -- "FAIL $*"
}
ok() { printf 'PASS %s\n' "$*"; }
installed() { [[ $(systemctl is-enabled "$1" 2>/dev/null) == enabled ]]; }
setting() {   # deployment.env stores base64 values
    sed -n "s/^$1=//p" "$deployment" 2>/dev/null | head -n 1 | base64 -d 2>/dev/null
}
bounded() { timeout --signal=KILL "${HEALTH_STEP_SECONDS:-30}" "$@"; }

node_host=$(sed -n 's/^NODE_HOST=//p' "$identity" 2>/dev/null | head -n 1)
if [[ -n $node_host ]]; then
    current=$(hostname -f 2>/dev/null || hostname)
    [[ $current == "$node_host" ]] && ok "hostname ${node_host}" || fail "hostname is ${current}, installed as ${node_host}"
fi

for unit in couchdb rabbitmq-server haproxy kazoo-apps kazoo-ecallmgr kazoo-freeswitch kazoo-kamailio nginx kazoo-push-bridge; do
    installed "${unit}.service" || continue
    state=$(systemctl is-active "${unit}.service" 2>/dev/null)
    [[ $state == active ]] && ok "${unit} active" || fail "${unit} is ${state:-unknown}"
    restarts=$(systemctl show -p NRestarts --value "${unit}.service" 2>/dev/null)
    [[ ${restarts:-0} -lt ${HEALTH_MAX_RESTARTS:-5} ]] || fail "${unit} has restarted ${restarts} times since it was last started by hand"
done

# A role that is running but absent from the port mapper still works until its
# peers next reconnect, then cannot be found. FreeSWITCH never registers again
# by itself, which failed the September 18, 2026 main promotion.
names=$(bounded epmd -names 2>/dev/null)
for pair in couchdb:couchdb rabbitmq-server:rabbit kazoo-apps:kazoo_apps kazoo-ecallmgr:ecallmgr kazoo-freeswitch:freeswitch; do
    installed "${pair%%:*}.service" || continue
    grep -q "^name ${pair##*:} " <<<"$names" && ok "${pair##*:} is registered with the Erlang port mapper" || \
        fail "${pair##*:} is not registered with the Erlang port mapper: restart ${pair%%:*} when it is idle"
done
if installed epmd.socket; then
    owner=$(ss -H -ltnp 'sport = :4369' 2>/dev/null | grep -o 'pid=[0-9]*' | head -n 1 | cut -d= -f2)
    main=$(systemctl show -p MainPID --value epmd.service 2>/dev/null)
    [[ -z $owner || $owner == "${main:-0}" ]] && ok 'the Erlang port mapper runs in its own service' || \
        fail "the Erlang port mapper is owned by pid ${owner}, not epmd.service: restarting that service drops FreeSWITCH"
fi

if installed rabbitmq-server.service; then
    running=$(bounded rabbitmqctl -q eval 'node().' 2>/dev/null | tr -d "'[:space:]")
    pinned=$(sed -n 's/^[[:space:]]*NODENAME=//p' /etc/rabbitmq/rabbitmq-env.conf 2>/dev/null | tail -n 1)
    if [[ -n $pinned ]]; then
        [[ $running == "$pinned" ]] && ok "broker runs as ${pinned}" || fail "broker runs as ${running:-unknown}, pinned ${pinned}"
    fi
    user=$(setting KAZOO_RABBITMQ_USER); user=${user:-kazoo}
    bounded rabbitmqctl -q list_users 2>/dev/null | awk '{print $1}' | grep -Fxq "$user" && ok "broker has user ${user}" || \
        fail "broker has no user ${user}: it is running on an empty or wrong database"
fi

node_check() {   # sup-node human-name
    local answer
    answer=$(bounded sup -n "$1" -e kz_amqp_connections is_available </dev/null 2>/dev/null | tr -d '[:space:]')
    [[ $answer == true ]] && ok "$2 reaches it and its broker connection is available" || \
        fail "$2 cannot be reached by SUP or has no broker connection (answer: ${answer:-none})"
}
if installed kazoo-apps.service; then
    node_check kazoo_apps 'kazoo_apps: SUP'
    code=$(bounded curl -s -o /dev/null -w '%{http_code}' --max-time 8 http://127.0.0.1:8000/v2/ 2>/dev/null)
    [[ $code =~ ^[234][0-9][0-9]$ ]] && ok "Crossbar answers (HTTP ${code})" || fail "Crossbar does not answer on 127.0.0.1:8000 (HTTP ${code:-none})"
fi
if installed kazoo-ecallmgr.service; then
    node_check ecallmgr 'ecallmgr: SUP'
    wanted=$(setting KAZOO_FREESWITCH_NODES)
    if [[ -n $wanted ]] || installed kazoo-freeswitch.service; then
        media=$(bounded sup -n ecallmgr ecallmgr_maintenance list_fs_nodes </dev/null 2>/dev/null | grep -c '@')
        [[ ${media:-0} -ge 1 ]] && ok "eCallMgr is connected to ${media} FreeSWITCH node(s)" || fail 'eCallMgr is connected to no FreeSWITCH node'
    fi
fi
if installed kazoo-kamailio.service; then
    for address in "$(setting KAZOO_PUBLIC_IP)" "$(setting KAMAILIO_PUBLIC_SIP_IP)"; do
        [[ -n $address ]] || continue
        ss -H -lun 'sport = :5060' 2>/dev/null | grep -Fq "${address}:5060" && ok "Kamailio listens on ${address}:5060/udp" || \
            fail "Kamailio is not listening on ${address}:5060/udp"
    done
fi

printf 'RESULT failures=%d\n' "$failures"
((failures == 0))
