#!/usr/bin/env bash
# Offline regression for the Kazoo stack health check. Every external command is
# a controlled shim, so each failure class of the September 18, 2026 outage can
# be reproduced: units "active" while the broker database is empty, the broker
# refuses logins and the API is dead. No real service is queried or changed.
set -Eeuo pipefail
umask 077
sh_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
sh_installer="$sh_root/scripts/install-kazoo5.sh"
sh_health="$sh_root/scripts/kazoo5-stack-health.sh"
sh_work=$(mktemp -d /tmp/kazoo-stack-health.XXXXXX)
trap 'rm -rf -- "$sh_work"' EXIT
sh_pass=0
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { sh_pass=$((sh_pass + 1)); printf 'PASS: %s\n' "$*"; }
function_body() { sed -n "/^$1() {\$/,/^}\$/p" "$sh_installer"; }
bash -n "$sh_health"; bash -n "$sh_installer"

mkdir "$sh_work/bin"
shim() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$sh_work/bin/$1"; chmod +x "$sh_work/bin/$1"; }
# Scenario variables are read by the shims; defaults describe a healthy all-in-one host.
shim hostname 'echo "${T_HOSTNAME:-node1}"'
shim systemctl 'case "$1" in
  is-enabled) [[ " ${T_DISABLED:-} " == *" ${2%.service} "* ]] && echo disabled || echo enabled ;;
  is-active) [[ " ${T_INACTIVE:-} " == *" ${2%.service} "* ]] && echo inactive || echo active ;;
  show) [[ " ${T_LOOPING:-} " == *" ${5%.service} "* ]] && echo 4367 || echo 0 ;;
esac'
shim rabbitmqctl 'if [[ $* == *"node()."* ]]; then echo "${T_BROKER_NODE:-rabbit@node1}"; else printf "%s\n" ${T_BROKER_USERS:-kazoo guest}; fi'
shim sup 'if [[ $* == *is_available* ]]; then
  [[ $* == *"-n ecallmgr"* ]] && echo "${T_ECALLMGR_AMQP-true}" || echo "${T_APPS_AMQP-true}"
elif [[ $* == *list_fs_nodes* ]]; then printf "%s" "${T_MEDIA-freeswitch@node1}"; fi'
shim curl 'printf "%s" "${T_HTTP:-401}"'
shim pgrep 'printf "%s\n" ${T_STRAY-}'
shim epmd 'printf "name %s at port 1\n" ${T_EPMD-couchdb rabbit kazoo_apps ecallmgr freeswitch}'
shim ss 'printf "%s\n" "${T_LISTEN-UNCONN 0 0 10.0.0.5:5060 0.0.0.0:*}"'
shim logger 'printf "%s\n" "$*" >> "$T_LOGGER"'
shim timeout 'while [[ $1 == --* ]]; do shift; done; shift; exec "$@"'

printf 'NODE_HOST=node1\n' > "$sh_work/identity"
{ printf 'KAZOO_PUBLIC_IP=%s\n' "$(printf 10.0.0.5 | base64 -w0)"; printf 'KAZOO_RABBITMQ_USER=%s\n' "$(printf kazoo | base64 -w0)"; } > "$sh_work/deployment.env"
mkdir -p "$sh_work/etc"; printf 'NODENAME=rabbit@node1\n' > "$sh_work/rabbitmq-env.conf"
run() {   # VAR=value ... ; prints output, returns the check's status
    ( export PATH="$sh_work/bin:$PATH" KAZOO_DEPLOYMENT_CONFIG="$sh_work/deployment.env" KAZOO_NODE_IDENTITY_FILE="$sh_work/identity" \
             T_LOGGER="$sh_work/logger.out"
      for assignment in "$@"; do export "${assignment?}"; done
      sed "s#/etc/rabbitmq/rabbitmq-env.conf#$sh_work/rabbitmq-env.conf#" "$sh_health" > "$sh_work/health.sh"
      # shellcheck disable=SC2086
      bash "$sh_work/health.sh" ${T_ARGS:-} 2>&1 )
}
out=$(run) || { printf '%s\n' "$out"; fail 'a healthy host was reported unhealthy'; }
grep -Fq 'RESULT failures=0' <<<"$out" || fail 'healthy result line'
pass 'a healthy all-in-one host passes'

expect() {   # description expected-text assignments...
    local description=$1 expected=$2 out status=0; shift 2
    : > "$sh_work/logger.out"
    out=$(run "$@") || status=$?
    [[ $status != 0 ]] || { printf '%s\n' "$out"; fail "$description: reported healthy"; }
    grep -Fq "$expected" <<<"$out" || { printf '%s\n' "$out"; fail "$description: missing '$expected'"; }
    grep -Fq 'daemon.err' "$sh_work/logger.out" || fail "$description: no err-priority journal line"
}
# The outage, condition by condition: every unit still reports "active".
expect 'empty broker database' 'broker has no user kazoo' 'T_BROKER_USERS=guest'
expect 'broker on a new node name' 'broker runs as rabbit@kz5-dev, pinned rabbit@node1' 'T_BROKER_NODE=rabbit@kz5-dev'
expect 'apps node on defaults' 'kazoo_apps: SUP cannot be reached' 'T_APPS_AMQP='
expect 'ecallmgr login refused' 'ecallmgr: SUP cannot be reached' 'T_ECALLMGR_AMQP=false'
expect 'dead API' 'Crossbar does not answer' 'T_HTTP=000'
expect 'changed hostname' 'hostname is kz5-dev.talkchief.io, installed as node1' 'T_HOSTNAME=kz5-dev.talkchief.io'
expect 'restart loop' 'kazoo-kamailio has restarted 4367 times' 'T_LOOPING=kazoo-kamailio'
expect 'inactive role' 'kazoo-freeswitch is inactive' 'T_INACTIVE=kazoo-freeswitch'
expect 'no media link' 'connected to no FreeSWITCH node' 'T_MEDIA='
# The failed main promotion: a Kazoo restart replaced the port mapper and FreeSWITCH never registered again.
expect 'media node lost from the port mapper' 'freeswitch is not registered with the Erlang port mapper: restart kazoo-freeswitch' 'T_EPMD=couchdb rabbit kazoo_apps ecallmgr'
expect 'port mapper owned by a Kazoo service' 'runs outside epmd.service (pid 386407)' 'T_STRAY=386407'
expect 'SIP edge not listening' 'Kamailio is not listening on 10.0.0.5:5060/udp' 'T_LISTEN='
pass 'twelve failure classes, including every "active but dead" condition of the outage, fail with an err line'

# Roles that are not installed on this host are not judged.
out=$(run 'T_DISABLED=kazoo-apps kazoo-ecallmgr kazoo-freeswitch kazoo-kamailio nginx kazoo-push-bridge couchdb haproxy' 'T_HTTP=000' 'T_APPS_AMQP=' 'T_MEDIA=' 'T_LISTEN=') || \
    { printf '%s\n' "$out"; fail 'a broker-only host was judged on roles it does not run'; }
pass 'a split host is judged only on the roles it runs'

# The first health-gated main promotion failed on the ingress it had closed
# itself. The scope is explicit, visible, and covers the SIP edge only.
closed=('T_INACTIVE=kazoo-kamailio' 'T_LISTEN=')
if out=$(run "${closed[@]}"); then fail 'a stopped SIP edge passed without the explicit scope'; fi
out=$(run "${closed[@]}" 'T_ARGS=--ingress-closed') || { printf '%s\n' "$out"; fail 'a deliberately closed ingress failed the scoped check'; }
grep -Fxq 'SKIP kazoo-kamailio: SIP ingress was deliberately closed by the caller' <<<"$out" || fail 'the scope is not visible in the output'
if out=$(run "${closed[@]}" 'T_ARGS=--ingress-closed' 'T_MEDIA='); then fail 'the ingress scope hid an unrelated failure'; fi
status=0; out=$(run 'T_ARGS=--anything-else') || status=$?
[[ $status == 2 ]] || fail 'an unknown argument must be refused, not ignored'
verify=$(function_body verify_stack_health)
grep -Fq '[[ ${KAZOO_INGRESS_CLOSED:-false} != true ]] || scope=(--ingress-closed)' <<<"$verify" || fail 'installer does not pass the explicit scope'
! grep -Eq 'ingress|KAZOO_INGRESS' <<<"$(function_body install_stack_health)" || fail 'the timer must always run the full check'
promote="$sh_root/scripts/promote-main-dev-runtime.sh"
closed_line=$(grep -n '^KAZOO_INGRESS_CLOSED=true bash scripts/install-kazoo5.sh ' "$promote" | cut -d: -f1)
start_line=$(grep -n '^systemctl start "\$ingress"$' "$promote" | cut -d: -f1)
full_line=$(grep -n '^/usr/local/libexec/kazoo5-stack-health >> ' "$promote" | cut -d: -f1)
pass_line=$(grep -n '^receipt PASS$' "$promote" | cut -d: -f1)
[[ -n $closed_line && -n $start_line && -n $full_line && -n $pass_line ]] || fail 'promotion does not scope the installer and repay the full check'
((closed_line < start_line && start_line < full_line && full_line < pass_line)) || fail 'promotion must run the full check after reopening ingress and before PASS'
pass 'closed ingress is an explicit, visible, SIP-only scope; the timer is never scoped; the promotion repays the full check before PASS'

install=$(function_body install_stack_health)
grep -Fq 'kazoo5-stack-health.sh' <<<"$install" || fail 'health check is not installed'
grep -Fxq 'OnBootSec=4min' <<<"$install" && grep -Fxq 'OnUnitActiveSec=2min' <<<"$install" || fail 'timer does not cover boot and steady state'
grep -Fq 'enable --now kazoo5-stack-health.timer' <<<"$install" || fail 'timer is not enabled'
verify=$(function_body verify_stack_health)
grep -Fq 'die' <<<"$verify" && grep -Fq 'kazoo5-stack-health.timer is not enabled and active' <<<"$verify" || fail 'verification does not require the timer'
grep -Eq '^\s+install_stack_health$' "$sh_installer" && [[ $(grep -cE '^\s+verify_stack_health$' "$sh_installer") == 2 ]] || \
    fail 'install and verify-only paths must both check stack health'
! grep -Eq 'systemctl (restart|start|stop)|set_default|rabbitmqctl (add|delete|change)' "$sh_health" || fail 'the health check must never change anything'
pass 'installer installs, schedules and verifies the check in install and verify-only modes; the check is read-only'
printf 'All %d stack health groups passed\n' "$sh_pass"
