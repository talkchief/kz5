#!/usr/bin/env bash
# Offline regression for the installer's stable Erlang port mapper. On
# September 18, 2026 the main development promotion failed because epmd lived
# in kazoo-ecallmgr's cgroup: restarting that service replaced the mapper,
# FreeSWITCH's mod_kazoo never registered again, and the new eCallMgr could not
# find it. The installer functions run here against controlled commands; no
# real service, socket or file under /etc is touched.
set -Eeuo pipefail
umask 077
se_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
se_installer="$se_root/scripts/install-kazoo5.sh"
se_work=$(mktemp -d /tmp/kazoo-stable-epmd.XXXXXX)
trap 'rm -rf -- "$se_work"' EXIT
se_pass=0
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { se_pass=$((se_pass + 1)); printf 'PASS: %s\n' "$*"; }
function_body() { sed -n "/^$1() {\$/,/^}\$/p" "$se_installer"; }
bash -n "$se_installer"
for name in epmd_role_units epmd_role_name epmd_selected_roles epmd_stray_pids epmd_listener_is_stable epmd_wait_registered \
            configure_stable_epmd verify_stable_epmd freeswitch_channel_count; do
    [[ -n $(function_body "$name") ]] || fail "installer function ${name} is missing or not extractable"
done

# scenario: name; env: T_* variables describe the host. Prints the function's
# output; every state-changing command is appended to $se_work/<name>.actions.
scenario() {   # name function assignments...
    local name=$1 entry=$2; shift 2
    (
        set +e
        DRY_RUN=false KAZOO_ERLANG_DIST_IP=10.0.0.5
        T_SOCKET=inactive T_MAIN=0 T_LISTEN='' T_STRAYS='' T_ENABLED=enabled T_CHANNELS=0 T_UNIT_FILE=present
        T_ACTIVE='couchdb rabbitmq-server kazoo-apps kazoo-ecallmgr kazoo-freeswitch'
        T_NAMES='couchdb rabbit kazoo_apps ecallmgr freeswitch' T_NAMES_AFTER='' T_MAPPER_STARTS=true
        declare -A SELECTED=([kazoo-apps]=1 [ecallmgr]=1)
        for assignment in "$@"; do eval "$assignment"; done
        actions="$se_work/$name.actions"; : > "$actions"
        act() { printf '%s\n' "$*" >> "$actions"; }
        log() { printf '%s\n' "$*"; }
        die() { printf 'ERROR: %s\n' "$*"; exit 1; }
        run() { act "$*"; }
        is_loopback_address() { [[ $1 == 127.* ]]; }
        write_file() { mkdir -p "$se_work/$name$(dirname "$2")"; cat > "$se_work/$name$2"; }
        sleep() { :; }
        kill() { act "kill $*"; T_LISTEN=''; T_STRAYS=''; }
        epmd() { [[ $T_MAPPER_STARTS == true ]] || return 1; printf 'name %s at port 1\n' $T_NAMES; }
        ss() { [[ -n $T_LISTEN ]] && printf '%s\n' "$T_LISTEN"; return 0; }
        systemctl() {
            case $1 in
                is-active) if [[ $2 == --quiet ]]; then [[ " $T_ACTIVE " == *" ${3%.service} "* ]]; else
                               [[ $2 == epmd.socket ]] && printf '%s\n' "$T_SOCKET"; fi ;;
                is-enabled) [[ $T_ENABLED == enabled ]] ;;
                show) printf '%s\n' "$T_MAIN" ;;
                start) act "$*"; T_SOCKET=active; T_LISTEN='LISTEN 0 4096 127.0.0.1:4369 0.0.0.0:*'
                       [[ -z $T_NAMES_AFTER ]] || T_NAMES=$T_NAMES_AFTER ;;
                restart) act "$*"; T_NAMES="$T_NAMES freeswitch" ;;
                *) act "$*" ;;
            esac
        }
        eval "$(function_body epmd_role_units)"; eval "$(function_body epmd_role_name)"
        eval "$(function_body epmd_selected_roles)"; eval "$(function_body epmd_listener_is_stable)"
        eval "$(function_body epmd_wait_registered)"; eval "$(function_body configure_stable_epmd)"
        eval "$(function_body verify_stable_epmd)"
        freeswitch_channel_count() { printf '%s' "$T_CHANNELS"; }
        epmd_stray_pids() { printf '%s\n' $T_STRAYS; }
        # The real test for the packaged unit is a fixed path; honour the scenario instead.
        eval "$(declare -f configure_stable_epmd verify_stable_epmd | sed 's#-e /usr/lib/systemd/system/epmd.socket#$T_UNIT_FILE == present#')"
        SECONDS=0
        epmd_wait_registered() {   # no real clock: one look is the whole wait
            epmd | grep -q "^name $(epmd_role_name "$1") "
        }
        "$entry"
    ) 2>&1
}
actions() { cat "$se_work/$1.actions"; }
# Listeners deliberately carry no owner: a container guest's "ss -p" shows none,
# which made the first native migration find nothing to stop (private eCallMgr
# guest, install 6, September 18, 2026). Ownership comes from epmd_stray_pids.
readonly vm_owned="T_STRAYS=386407 T_LISTEN='LISTEN 0 4096 0.0.0.0:4369 0.0.0.0:*'"
readonly stable='LISTEN 0 4096 127.0.0.1:4369 0.0.0.0:*
LISTEN 0 4096 10.0.0.5:4369 0.0.0.0:*'

# 1. The September 18 host: epmd inside a Kazoo unit, wildcard listener, idle media.
out=$(scenario migrate configure_stable_epmd "$vm_owned" "T_NAMES='couchdb rabbit kazoo_apps ecallmgr'") || \
    { printf '%s\n' "$out"; fail 'idle migration failed'; }
dropin="$se_work/migrate/etc/systemd/system/epmd.socket.d/kazoo5-bind.conf"
grep -Fxq 'ListenStream=' "$dropin" && grep -Fxq 'ListenStream=127.0.0.1:4369' "$dropin" && \
    grep -Fxq 'ListenStream=10.0.0.5:4369' "$dropin" || fail 'socket is not bound to exactly loopback and the Erlang interface'
grep -Fxq 'FreeBind=true' "$dropin" || fail 'without FreeBind the socket fails after a reboot, before the address exists'
grep -Fxq 'LimitNPROC=infinity' "$se_work/migrate/etc/systemd/system/epmd.service.d/kazoo5-limits.conf" || \
    fail 'the packaged LimitNPROC=1 stops the third mapper of one numeric uid in a shared user namespace'
for unit in couchdb rabbitmq-server kazoo-apps kazoo-ecallmgr kazoo-freeswitch; do
    grep -Fxq 'After=epmd.socket' "$se_work/migrate/etc/systemd/system/${unit}.service.d/kazoo5-epmd.conf" || \
        fail "${unit} may start before the port mapper socket and spawn its own epmd"
done
want=$'daemon-reload\nenable epmd.socket\nstop epmd.service epmd.socket\nkill 386407\nreset-failed epmd.socket epmd.service\nstart epmd.socket\nrestart kazoo-freeswitch.service'
[[ $(actions migrate | sed 's/^systemctl //') == "$want" ]] || { actions migrate; fail 'migration steps or their order changed'; }
grep -Fq 'PASS every running Erlang role registered' <<<"$out" || fail 'migration did not confirm registrations'
pass 'a mapper owned by a Kazoo service is replaced by epmd.service; idle FreeSWITCH is restarted once so it registers'

# 2. A live call must never be cut: refuse before anything is changed.
status=0; out=$(scenario busy configure_stable_epmd "$vm_owned" T_CHANNELS=3) || status=$?
[[ $status != 0 ]] && grep -Fq 'it has 3 channels; rerun when it is idle' <<<"$out" || fail 'a busy FreeSWITCH did not refuse the migration'
! grep -Eq 'kill|stop|restart|start epmd' "$se_work/busy.actions" || { actions busy; fail 'a refused migration changed the host'; }
status=0; out=$(scenario unknown configure_stable_epmd "$vm_owned" T_CHANNELS=) || status=$?
[[ $status != 0 ]] && ! grep -q kill "$se_work/unknown.actions" || fail 'an unknown channel count must refuse, not proceed'
pass 'live or unknown channels refuse the migration before any change'

# 3. Converged host: repeat installs do nothing.
out=$(scenario repeat configure_stable_epmd T_SOCKET=active T_MAIN=900 "T_LISTEN='$stable'") || fail 'converged host failed'
! grep -Eq 'kill|stop|restart|start epmd' "$se_work/repeat.actions" || { actions repeat; fail 'a converged host was disturbed'; }
out=$(scenario lo configure_stable_epmd KAZOO_ERLANG_DIST_IP=127.0.0.1 "$vm_owned")
[[ $(grep -c '^ListenStream=.' "$se_work/lo/etc/systemd/system/epmd.socket.d/kazoo5-bind.conf") == 1 ]] || fail 'loopback install must listen once'
out=$(scenario nounit configure_stable_epmd T_UNIT_FILE=absent "$vm_owned") || fail 'a host without the packaged unit failed'
[[ ! -s $se_work/nounit.actions ]] || fail 'a single-role host without the packaged unit was changed'
out=$(scenario edge configure_stable_epmd 'SELECTED=([kamailio]=1)' "$vm_owned") && [[ ! -s $se_work/edge.actions ]] || \
    fail 'an install without Erlang roles touched the port mapper'
pass 'repeat, loopback, unit-less and non-Erlang installs are left undisturbed'

# 4. A role that does not come back is named with its remedy.
status=0; out=$(scenario stuck configure_stable_epmd "$vm_owned" "T_NAMES_AFTER='couchdb kazoo_apps ecallmgr'") || status=$?
[[ $status != 0 ]] && grep -Fq 'rabbit did not register with the new Erlang port mapper; run: systemctl restart rabbitmq-server' <<<"$out" || \
    { printf '%s\n' "$out"; fail 'an unregistered role was not reported with its remedy'; }
status=0; out=$(scenario dead configure_stable_epmd "$vm_owned" T_MAPPER_STARTS=false) || status=$?
[[ $status != 0 ]] && grep -Fq 'epmd.service does not answer behind its socket; see: journalctl -u epmd.service' <<<"$out" || \
    { printf '%s\n' "$out"; fail 'a mapper that cannot start was not reported'; }
! grep -q 'restart kazoo-freeswitch' "$se_work/dead.actions" || fail 'FreeSWITCH was restarted against a mapper that does not answer'
pass 'a role missing after migration, or a mapper that cannot start, fails the install with its remedy'

# 5. Verification, including verify-only, rejects each unsafe state.
scenario good verify_stable_epmd T_SOCKET=active T_MAIN=900 "T_LISTEN='$stable'" | grep -Fq 'PASS epmd.service owns port 4369' || fail 'stable host not verified'
reject() {   # description expected assignments...
    local description=$1 expected=$2 out status=0; shift 2
    out=$(scenario reject verify_stable_epmd "$@") || status=$?
    [[ $status != 0 ]] && grep -Fq "$expected" <<<"$out" || { printf '%s\n' "$out"; fail "$description"; }
    [[ ! -s $se_work/reject.actions ]] || fail "$description: verification changed the host"
}
reject 'the September 18 state passed verification' 'restarting a Kazoo service would drop FreeSWITCH' "$vm_owned"
reject 'a second mapper beside a correct listener passed' 'not owned by epmd.service' T_SOCKET=active T_MAIN=900 T_STRAYS=134 "T_LISTEN='$stable'"
reject 'a wildcard listener passed' 'without a wildcard listener' T_SOCKET=active T_MAIN=900 "T_LISTEN='${stable//127.0.0.1:4369/0.0.0.0:4369}'"
reject 'a socket that a reboot would lose passed' 'epmd.socket is not enabled' T_ENABLED=disabled T_SOCKET=active T_MAIN=900 "T_LISTEN='$stable'"
reject 'an unregistered FreeSWITCH passed' 'freeswitch is running but not registered' T_SOCKET=active T_MAIN=900 "T_LISTEN='$stable'" "T_NAMES='couchdb rabbit kazoo_apps ecallmgr'"
pass 'verification accepts the stable mapper and rejects five unsafe states without changing anything'

# 6. Wiring: converge before any role starts; verify in install and verify-only.
install=$(function_body install_requested); verify=$(function_body verify_requested)
[[ $(grep -n 'configure_stable_epmd' <<<"$install" | cut -d: -f1) -lt $(grep -n 'install_couchdb' <<<"$install" | cut -d: -f1) ]] || \
    fail 'the port mapper must be stable before the first Erlang role is installed'
[[ $(sed -n '2p' <<<"$verify") == '    verify_stable_epmd' ]] || fail 'verification must start with the port mapper'
! grep -q 'local_epmd_socket' "$se_installer" || fail 'the loopback-only predecessor is still referenced'
pass 'the mapper is converged before any role and verified first'
printf 'All %d stable port mapper groups passed\n' "$se_pass"
