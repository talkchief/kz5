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
elif [[ $* == *"-e ecallmgr_fs_nodes connected"* ]]; then printf "%s" "${T_MEDIA-[\x27freeswitch@node1\x27]}"
elif [[ $* == *list_fs_nodes* ]]; then echo "freeswitch@stale-listing"; fi'
shim fs_cli '[[ $* == "-x sofia status" ]] || exit 9; printf "%b" "${T_SOFIA-  sipinterface_1\tprofile\tsip:mod_sofia@10.0.0.5:11000\tRUNNING (0)\n}"'
shim curl '[[ $* == *"http://127.0.0.1:8000/" ]] || { echo "unexpected probe URL: $*" >&2; exit 9; }; printf "%s" "${T_HTTP:-200}"'
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
      export KAZOO_FS_CLI="$sh_work/bin/fs_cli"
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
expect 'API answering with an error' 'Crossbar does not answer' 'T_HTTP=503'
expect 'changed hostname' 'hostname is kz5-dev.talkchief.io, installed as node1' 'T_HOSTNAME=kz5-dev.talkchief.io'
expect 'restart loop' 'kazoo-kamailio has restarted 4367 times' 'T_LOOPING=kazoo-kamailio'
expect 'inactive role' 'kazoo-freeswitch is inactive' 'T_INACTIVE=kazoo-freeswitch'
expect 'no media link' 'connected to no FreeSWITCH node' 'T_MEDIA='
expect 'media link lost but still listed' 'connected to no FreeSWITCH node' 'T_MEDIA=[]'
expect 'media server without a SIP profile' 'FreeSWITCH has no running SIP profile' 'T_SOFIA=0 profiles 0 aliases\n'
expect 'media server not answering its console' 'FreeSWITCH has no running SIP profile' 'T_SOFIA='
# The failed main promotion: a Kazoo restart replaced the port mapper and FreeSWITCH never registered again.
expect 'media node lost from the port mapper' 'freeswitch is not registered with the Erlang port mapper: restart kazoo-freeswitch' 'T_EPMD=couchdb rabbit kazoo_apps ecallmgr'
expect 'port mapper owned by a Kazoo service' 'runs outside epmd.service (pid 386407)' 'T_STRAY=386407'
expect 'SIP edge not listening' 'Kamailio is not listening on 10.0.0.5:5060/udp' 'T_LISTEN='
pass 'sixteen failure classes, including every "active but dead" condition of the outage, fail with an err line'

# A CouchDB-only host: no epmd on PATH, only CouchDB's bundled client.
mkdir -p "$sh_work/couch/erts-1/bin"; printf '#!/usr/bin/env bash\necho "name couchdb at port 1"\n' > "$sh_work/couch/erts-1/bin/epmd"; chmod +x "$sh_work/couch/erts-1/bin/epmd"
couch_only() {   # bundled-client-glob assignments... -> runs the check with no epmd on PATH
    local glob=$1; shift
    ( export PATH="$sh_work/bin:$PATH" KAZOO_DEPLOYMENT_CONFIG="$sh_work/deployment.env" KAZOO_NODE_IDENTITY_FILE="$sh_work/identity" T_LOGGER="$sh_work/logger.out"
      for assignment in "$@"; do export "${assignment?}"; done
      sed -e "s#/etc/rabbitmq/rabbitmq-env.conf#$sh_work/rabbitmq-env.conf#" -e 's#command -v epmd 2>/dev/null#false#' \
          -e "s#/opt/couchdb/erts-\*/bin/epmd#$glob#" "$sh_health" > "$sh_work/health-couch.sh"
      bash "$sh_work/health-couch.sh" 2>&1 )
}
only_couch='T_DISABLED=rabbitmq-server haproxy kazoo-apps kazoo-ecallmgr kazoo-freeswitch kazoo-kamailio nginx kazoo-push-bridge epmd.socket'
out=$(couch_only "$sh_work/couch/erts-*/bin/epmd" "$only_couch") || { printf '%s\n' "$out"; fail 'a CouchDB-only host with its bundled epmd client was reported unhealthy'; }
grep -Fq 'PASS couchdb is registered with the Erlang port mapper' <<<"$out" || fail 'the bundled epmd client was not used'
out=$(couch_only "$sh_work/absent/erts-*/bin/epmd" "$only_couch") || { printf '%s\n' "$out"; fail 'a host without any epmd client must not fail on registrations'; }
grep -Fxq 'SKIP port mapper registrations: this host has no epmd client' <<<"$out" || fail 'the skipped judgement is not visible'
pass 'a CouchDB-only host is judged with its bundled epmd client, and never failed for having none'

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

# The gate waits through a transient and still fails on a persistent fault.
gate() {   # failures-before-healthy -> prints log, returns the gate's status
    ( set +e
      DRY_RUN=false SCRIPT_DIR=$sh_root/scripts KAZOO_CACHE_DIR=$sh_work; count="$sh_work/attempts"; : > "$count"
      log() { printf '%s\n' "$*"; }; die() { printf 'ERROR: %s\n' "$*"; exit 1; }
      cmp() { return 0; }; sleep() { :; }
      systemctl() { [[ $1 == is-enabled ]] && echo enabled || echo active; }
      printf '#!/usr/bin/env bash\necho x >> %q\n(( $(wc -l < %q) > %d )) || { echo "FAIL ecallmgr: reconnecting" >&2; exit 1; }\n' "$count" "$count" "$1" > "$sh_work/health-stub"
      chmod +x "$sh_work/health-stub"
      eval "$(function_body verify_stack_health | sed "s#/usr/local/libexec/kazoo5-stack-health \"#$sh_work/health-stub \"#")"
      verify_stack_health )
}
set +e; out=$(gate 3); status=$?; set -e
[[ $status == 0 && $(wc -l < "$sh_work/attempts") == 4 ]] && grep -Fq 'attempt 3 of 6 not yet healthy' <<<"$out" && grep -Fq 'PASS Kazoo stack health' <<<"$out" || \
    { printf '%s\n' "$out"; fail 'a role that reconnects within the wait must not fail the install'; }
set +e; out=$(gate 99 2>&1); status=$?; set -e
[[ $status != 0 && $(wc -l < "$sh_work/attempts") == 6 ]] && grep -Fq 'after six attempts' <<<"$out" && grep -Fq 'FAIL ecallmgr: reconnecting' <<<"$out" || \
    { printf '%s\n' "$out"; fail 'a persistent failure must fail after six attempts and show the FAIL lines'; }
pass 'the install gate waits through a transient, and fails with the FAIL lines on a persistent fault'

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
