#!/usr/bin/env bash
# Recover the MAIN development stack on dev44 after its host identity changed.
#
# Every component was installed under the node identity `dev-testing` on the
# private address 10.1.0.44. RabbitMQ keeps its whole database under
# rabbit@<hostname>, Kazoo/FreeSWITCH/Kamailio node names and the per-node
# system_config sections use the same name. On September 18, 2026 the hostname
# was changed to the public DNS name and the host rebooted: RabbitMQ started an
# EMPTY broker (no kazoo user -> ACCESS_REFUSED), kazoo-apps fell back to
# 127.0.0.1, and four `listen=UDP_SIP advertise ...` lines added to Kamailio's
# local.cfg (read before listener-defs.cfg defines those names) made Kamailio
# refuse to start. The public name kz5-dev.talkchief.io is DNS/TLS only and does
# not need to be the hostname.
#
# Idempotent. Restarts main development services; refuses with live calls.
# Changing the hostname for real needs a tested migration, not this script.
set -Eeuo pipefail
umask 077
((EUID == 0)) || { echo 'Root required' >&2; exit 1; }
ip -o -4 address show | grep -Eq 'inet 10\.1\.0\.44/' || { echo 'Only development44 allowed' >&2; exit 1; }
readonly node_host=dev-testing node_ip=10.1.0.44
readonly config=/etc/kazoo/core/config.ini kam_local=/etc/kazoo/kamailio/local.cfg
readonly fs_cli=/usr/local/freeswitch/bin/fs_cli
note() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*"; }
fail() { note "FAILED: $*" >&2; exit 1; }

if "$fs_cli" -x 'show channels as json' >/dev/null 2>&1; then
    [[ $("$fs_cli" -x 'show channels as json' | jq -r '.row_count') == 0 ]] || fail 'FreeSWITCH has live channels'
fi

backup=$(mktemp -d "/root/kz5-node-identity-recovery-$(date -u +%Y%m%d).XXXXXXXX")
cp -a "$config" "$kam_local" /etc/hosts "$backup/"
(cd "$backup" && sha256sum config.ini local.cfg hosts > as-found.sha256)
note "As-found files kept in $backup"

[[ $(hostnamectl --static) == "$node_host" ]] || hostnamectl set-hostname "$node_host"
awk -v h="$node_host" '!/^[[:space:]]*#/ { for (i = 2; i <= NF; i++) if ($i == h) found = 1 } END { exit !found }' /etc/hosts || \
    printf '%s %s\n' "$node_ip" "$node_host" >> /etc/hosts
[[ $(getent ahostsv4 "$node_host" | awk 'NR==1{print $1}') == "$node_ip" ]] || fail "$node_host does not resolve to $node_ip"

# Only the two node host lines; credentials and every other setting untouched.
sed -i -E "s#^(host[[:space:]]*=[[:space:]]*).*\$#\\1${node_host}#" "$config"
[[ $(grep -cE "^host[[:space:]]*=[[:space:]]*${node_host}\$" "$config") == 2 ]] || fail 'config.ini host lines'

# local.cfg precedes listener-defs.cfg, so listener macro names are undefined
# there. Keep the operator's lines, disabled, with the supported alternative.
if grep -Eq '^listen=(UDP|TCP|TLS)_[A-Z_]+([[:space:]]|$)' "$kam_local"; then
    sed -i -E 's/^(listen=(UDP|TCP|TLS)_[A-Z_]+([[:space:]].*)?)$/## disabled (macro undefined in local.cfg; use MY_PUBLIC_IP + WITH_ADVERTISE_LISTENER + WITHOUT_DEFAULT_LISTENER): \1/' "$kam_local"
    note 'Disabled listener-macro lines in Kamailio local.cfg'
fi

note 'Restarting the broker on its original node identity'
systemctl restart rabbitmq-server
for _ in $(seq 1 30); do rabbitmqctl -q list_users >/dev/null 2>&1 && break; sleep 2; done
rabbitmqctl -q list_users | awk '{print $1}' | grep -Fxq kazoo || fail 'RabbitMQ has no kazoo user; its original database was not loaded'
note "PASS RabbitMQ runs as $(rabbitmqctl -q eval 'node().' 2>/dev/null) with the kazoo user"

systemctl restart kazoo-freeswitch.service
systemctl restart kazoo-apps.service kazoo-ecallmgr.service
systemctl reset-failed kazoo-kamailio.service 2>/dev/null || true
systemctl restart kazoo-kamailio.service
systemctl try-restart kazoo-push-bridge.service 2>/dev/null || true

note 'Waiting for Crossbar'
for _ in $(seq 1 90); do
    [[ $(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:8000/v2/ || true) =~ ^[234] ]] && break
    sleep 4
done
[[ $(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:8000/v2/ || true) =~ ^[234] ]] || fail 'Crossbar does not answer on 127.0.0.1:8000'
[[ $(timeout 30 sup -e erlang node </dev/null | tr -d "'[:space:]") == "kazoo_apps@${node_host}" ]] || fail 'SUP cannot reach kazoo_apps'
for _ in $(seq 1 45); do
    timeout 30 sup -n ecallmgr ecallmgr_maintenance list_fs_nodes </dev/null 2>/dev/null | grep -Fq "freeswitch@${node_host}" && break
    sleep 4
done
timeout 30 sup -n ecallmgr ecallmgr_maintenance list_fs_nodes </dev/null | grep -Fq "freeswitch@${node_host}" || fail 'eCallMgr is not connected to FreeSWITCH'
for unit in rabbitmq-server couchdb haproxy kazoo-apps kazoo-ecallmgr kazoo-freeswitch kazoo-kamailio nginx; do
    [[ $(systemctl is-active "$unit") == active ]] || fail "$unit is not active"
done
sleep 10
[[ $(systemctl is-active kazoo-kamailio) == active ]] || fail 'Kamailio did not stay up'
note 'PASS main development stack recovered: broker identity, API, SUP, FreeSWITCH link and SIP edge'
