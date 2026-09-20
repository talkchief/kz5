#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Offline proof for scripts/remote-install-kazoo5.sh with recording ssh/scp stand-ins.
# No host is contacted. The wrapper runs from a private clone of this commit.
# shellcheck disable=SC2016,SC2015  # literal stub text; A && B || fail is the suite's idiom
set -Eeuo pipefail
rt_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
rt_work=$(mktemp -d "${TMPDIR:-/tmp}/kz5-remote-install-test.XXXXXX")
trap 'rm -rf -- "$rt_work"' EXIT
rt_pass=0
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { rt_pass=$((rt_pass + 1)); printf 'PASS: %s\n' "$*"; }

git clone -q --no-hardlinks "$rt_root" "$rt_work/repo"   # the temp dir may be another filesystem (Jenkins, build 3)
cp -- "$rt_root/scripts/remote-install-kazoo5.sh" "$rt_work/repo/scripts/remote-install-kazoo5.sh"
git -C "$rt_work/repo" -c user.name=test -c user.email=test@invalid commit -q -a -m 'wrapper under test' --allow-empty
rt_script="$rt_work/repo/scripts/remote-install-kazoo5.sh"
rt_sha=$(git -C "$rt_work/repo" rev-parse HEAD)

mkdir -p "$rt_work/bin"
# ssh: record the remote command, answer like a healthy Rocky 9 target unless the scenario says otherwise.
cat > "$rt_work/bin/ssh" <<'STUB'
#!/usr/bin/env bash
command=${!#}
printf '%s\n' "$command" >> "$RT_LOG"
# Everything ssh was given, and what its password helper would answer, for the login checks.
printf '%s\n' "$*" >> "$RT_LOG.args"
[[ -z ${SSH_ASKPASS:-} ]] || printf 'askpass=%s require=%s\n' "$("$SSH_ASKPASS")" "${SSH_ASKPASS_REQUIRE:-}" >> "$RT_LOG.askpass"
case $command in
    true) [[ ${RT_NO_LOGIN:-} != 1 ]] ;;
    *'id -u'*) [[ ${RT_NOT_ROOT:-} != 1 ]] ;;
    *os-release*) [[ ${RT_NOT_ROCKY:-} != 1 ]] ;;
    *'list-units'*) [[ ${RT_BUSY:-} == 1 ]] ;;
    *'show channels count'*) echo "${RT_CALLS-0}" ;;
    *'git -C /opt/kz5 checkout'*) [[ ${RT_DIRTY_TARGET:-} != 1 ]] || { echo 'tracked files were edited on the target' >&2; exit 3; } ;;
    *'systemd-run'*) : ;;
    # systemd's own order, not the order asked: the first native run misread it.
    *'systemctl show -p SubState'*) printf 'ExecMainStatus=%s\nSubState=exited\nLines=3\n' "${RT_INSTALL_STATUS:-0}" ;;
    *"grep -E '^\\[kazoo5\\] '"*) printf '[kazoo5] PASS stub installer line\n' ;;
    *'is-enabled'*) echo "${RT_ENABLED:-enabled}" ;;
    *'is-active'*) echo active ;;
    *kazoo5-stack-health*) echo 'RESULT failures=0' ;;
esac
STUB
printf '#!/usr/bin/env bash\nprintf "scp %%s\\n" "$*" >> "$RT_LOG"\n' > "$rt_work/bin/scp"
chmod +x "$rt_work/bin/ssh" "$rt_work/bin/scp"
: > "$rt_work/key"; chmod 600 "$rt_work/key"
printf 'KAZOO_PUBLIC_IP=10.0.0.21\nKAZOO_COOKIE=abc123\n# comment\n' > "$rt_work/settings.env"

run() {   # ENV=value ... -- args...
    local -a assignments=()
    while [[ $1 != -- ]]; do assignments+=("$1"); shift; done; shift
    : > "$rt_work/log"; : > "$rt_work/log.args"; : > "$rt_work/log.askpass"
    env PATH="$rt_work/bin:$PATH" RT_LOG="$rt_work/log" RI_POLL_SECONDS=0 TMPDIR="$rt_work" "${assignments[@]}" \
        bash "$rt_script" --host 10.0.0.21 ${RT_LOGIN:---identity "$rt_work/key"} "$@" > "$rt_work/out" 2>&1
}

run -- --env-file "$rt_work/settings.env" ecallmgr freeswitch || { cat "$rt_work/out"; fail 'a healthy install failed'; }
grep -Fq "RESULT PASS install of ecallmgr freeswitch on 10.0.0.21 at ${rt_sha}" "$rt_work/out" || fail 'result line'
started=$(grep -c 'systemd-run' "$rt_work/log")
[[ $started == 1 ]] || fail "the installer must be started exactly once, saw ${started}"
grep -F 'systemd-run' "$rt_work/log" | grep -Fq "/opt/kz5/scripts/install-kazoo5.sh  ecallmgr freeswitch >" || fail 'the unit does not run the installer with the selected components'
grep -F 'systemd-run' "$rt_work/log" | grep -Fq 'EnvironmentFile=/var/lib/kazoo-remote-install/input-' || fail 'the settings are not handed to the unit'
grep -Fq "checkout -q --detach ${rt_sha}" "$rt_work/log" || fail 'the exact commit is not checked out'
grep -Eq 'is-enabled kazoo-ecallmgr.service' "$rt_work/log" && grep -Eq 'is-enabled kazoo-freeswitch.service' "$rt_work/log" || fail 'enabled state not checked per service'
grep -Fq 'kazoo5-stack-health' "$rt_work/log" || fail 'health not checked'
tail -n 1 "$rt_work/log" | grep -Fq 'rm -f -- /var/lib/kazoo-remote-install/input-' || fail 'the settings file is not removed last'
! grep -Fq 'abc123' "$rt_work/out" "$rt_work/log" || fail 'a setting value reached the output or a remote command line'
pass 'install: exact commit placed, installer started once as a unit with the settings, services checked enabled and healthy, settings removed'

# Nothing but the installer may change the target: every remote command is one of a known few.
while IFS= read -r line; do
    case $line in
        true|'test "$(id -u)" = 0'|*os-release*|install\ -d\ -m\ 0700*|*list-units*|*'show channels count'*|scp\ *|\
        'command -v git'*|'set -e'|*'git -C /opt/kz5'*|*'git clone -q'*|*'rm -f -- /var/lib/kazoo-remote-install/'*|'    '*|\
        chmod\ 0600*|systemd-run*|*'systemctl show -p SubState'*|sed\ -n*|*reset-failed*|*is-enabled*|*is-active*|*kazoo5-stack-health*) ;;
        *) fail "unexpected remote command: ${line}" ;;
    esac
done < "$rt_work/log"
! grep -Eq 'sup |hotload|systemctl (restart|start|enable) ' "$rt_work/log" || fail 'the wrapper itself restarts, enables or wires something'
pass 'every remote command is source placement, the installer unit, or a read-only check; no sup, no restart, no enable'

run -- --action dry-run kamailio || fail 'dry-run failed'
grep -F 'systemd-run' "$rt_work/log" | grep -Fq 'install-kazoo5.sh --dry-run kamailio' || fail 'dry-run flag'
! grep -Eq 'is-enabled|show channels' "$rt_work/log" || fail 'dry-run must not judge services or calls'
run -- --action verify-only couchdb || fail 'verify-only failed'
grep -F 'systemd-run' "$rt_work/log" | grep -Fq 'install-kazoo5.sh --verify-only couchdb' || fail 'verify-only flag'
run -- all || fail 'all failed'
grep -F 'systemd-run' "$rt_work/log" | grep -Fq 'couchdb rabbitmq haproxy kazoo-apps ecallmgr freeswitch kamailio monster-ui push-bridge' || fail 'all is not the nine components'
pass 'dry-run and verify-only pass the installer flag and skip service judgement; all expands to the nine components'

refuse() {   # description expected-text ENV... -- args...
    local description=$1 expected=$2; shift 2
    if run "$@"; then cat "$rt_work/out"; fail "${description}: accepted"; fi
    grep -Fq -- "$expected" "$rt_work/out" || { cat "$rt_work/out"; fail "${description}: missing '${expected}'"; }
    ! grep -Fq 'systemd-run' "$rt_work/log" || fail "${description}: the installer was started anyway"
}
refuse 'live calls' 'carries 7 live channel(s)' RT_CALLS=7 -- ecallmgr
refuse 'unknown call count' 'refusing to restart services blind' RT_CALLS= -- freeswitch
refuse 'login refused' 'Could not log in to the target' RT_NO_LOGIN=1 -- couchdb
refuse 'not root' 'must be root' RT_NOT_ROOT=1 -- couchdb
refuse 'other OS' 'Rocky Linux 9 only' RT_NOT_ROCKY=1 -- couchdb
refuse 'install already running' 'Another remote installation' RT_BUSY=1 -- couchdb
refuse 'edited target tree' 'Could not place commit' RT_DIRTY_TARGET=1 -- couchdb
refuse 'unknown component' 'Unknown component: mysql' -- mysql
refuse 'repeated component' 'named twice' -- couchdb couchdb
refuse 'no component' 'at least one component' --
refuse 'bad action' '--action is install' -- --action remove couchdb
printf 'KAZOO_X=$(reboot)\n' > "$rt_work/bad.env"
refuse 'command substitution in settings' 'without $ or backticks' -- --env-file "$rt_work/bad.env" couchdb
printf 'PATH=/tmp\n' > "$rt_work/bad.env"
refuse 'foreign variable in settings' 'may hold only' -- --env-file "$rt_work/bad.env" couchdb
: > "$rt_work/log"
if env PATH="$rt_work/bin:$PATH" RT_LOG="$rt_work/log" bash "$rt_script" --host '10.0.0.21;reboot' --identity "$rt_work/key" couchdb >/dev/null 2>&1; then fail 'a host with shell characters was accepted'; fi
[[ ! -s $rt_work/log ]] || fail 'a bad host was contacted'
run RT_CALLS=7 -- --allow-active-calls ecallmgr || fail 'the explicit live-call override was refused'
pass 'fourteen unsafe requests are refused before the installer starts; live calls need the explicit override'

if run RT_INSTALL_STATUS=1 -- --env-file "$rt_work/settings.env" kazoo-apps; then fail 'a failed installer was reported as success'; fi
grep -Fq 'The installer exited 1 on the target' "$rt_work/out" || fail 'installer failure not reported'
tail -n 1 "$rt_work/log" | grep -Fq 'rm -f -- /var/lib/kazoo-remote-install/input-' || fail 'settings left behind after a failed install'
if run RT_ENABLED=disabled -- haproxy; then fail 'a disabled service passed'; fi
grep -Fq 'would not come back after a reboot' "$rt_work/out" || fail 'disabled service not explained'
pass 'a failed installer and a service that is not enabled fail the run; settings are removed either way'

# Servers that only have a user and a password: the password may never be an argument.
RT_LOGIN='--password-env RT_SECRET' run RT_SECRET='p@ss w0rd/secret' -- --user deploy rabbitmq || { cat "$rt_work/out"; fail 'password login failed'; }
grep -Fq 'PubkeyAuthentication=no' "$rt_work/log.args" && grep -Fq 'deploy@10.0.0.21' "$rt_work/log.args" || fail 'password login options'
! grep -Fq 'BatchMode=yes' "$rt_work/log.args" || fail 'BatchMode would forbid the password prompt'
grep -Fxq 'askpass=p@ss w0rd/secret require=force' "$rt_work/log.askpass" || fail 'the helper does not hand ssh the password'
! grep -Fq 'w0rd' "$rt_work/log.args" "$rt_work/log" "$rt_work/out" || fail 'the password reached a command line, a remote command or the output'
[[ -z $(find "$rt_work" -name askpass -print -quit) ]] || fail 'the password helper was left behind'
if RT_LOGIN='--password-env RT_SECRET' run RT_SECRET= -- rabbitmq; then fail 'an empty password variable was accepted'; fi
if RT_LOGIN="--password-env RT_SECRET --identity $rt_work/key" run RT_SECRET=x -- rabbitmq; then fail 'key and password together were accepted'; fi
if RT_LOGIN=' ' run -- rabbitmq; then fail 'a run without any login was accepted'; fi
pass 'password login: ssh is asked through a private helper, the password never reaches an argument, a remote command or the output'

echo 'edit' >> "$rt_work/repo/README.md"
if run -- couchdb; then fail 'an uncommitted tree was deployed'; fi
grep -Fq 'deploy a commit, not a working copy' "$rt_work/out" || fail 'dirty source not explained'
git -C "$rt_work/repo" checkout -q README.md
pass 'only a commit is deployed, never a working copy'

# The unit names the wrapper checks must be the installer's own.
for pair in couchdb:couchdb rabbitmq:rabbitmq-server haproxy:haproxy kazoo-apps:kazoo-apps ecallmgr:kazoo-ecallmgr \
            freeswitch:kazoo-freeswitch kamailio:kazoo-kamailio monster-ui:nginx push-bridge:kazoo-push-bridge; do
    grep -A14 '^component_unit() {' "$rt_root/scripts/install-kazoo5.sh" | grep -Fq "${pair%%:*}) printf ${pair##*:} ;;" || \
        fail "the installer's unit for ${pair%%:*} is no longer ${pair##*:}"
done
grep -Fq 'scripts/remote-install-kazoo5.sh' "$rt_root/jenkins/Jenkinsfile" || fail 'the Jenkins pipeline does not use the wrapper'
! grep -Eq "sh ['\"].*(ssh|scp) " "$rt_root/jenkins/Jenkinsfile" || fail 'the Jenkins pipeline reaches a host beside the wrapper'
pass 'service names match the installer; the Jenkins pipeline reaches hosts only through the wrapper'
printf 'All %d remote install groups passed\n' "$rt_pass"
