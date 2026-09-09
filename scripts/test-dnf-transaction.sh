#!/usr/bin/env bash
# Exercise the real installer helper with private command adapters only.
# shellcheck disable=SC1091,SC2034
set -Eeuo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
source "$script_dir/install-kazoo5.sh"
trace=$(mktemp /tmp/kazoo-dnf-transaction.XXXXXX)
trap 'rm -f -- "$trace"' EXIT
systemctl() {
    printf '%s\n' "$*" >> "$trace"
    case "$*" in
        'show --value -p ActiveState dnf-makecache.timer') echo "$timer" ;;
        'show --value -p ActiveState dnf-makecache.service') echo "$cache" ;;
        'show --value -p ExecStart dnf-makecache.service') echo "$cache_exec" ;;
        'stop dnf-makecache.service') return "$stop_status" ;;
        'start dnf-makecache.timer') return "$restore_status" ;;
        'stop dnf-makecache.timer') return 0 ;;
        *) return 98 ;;
    esac
}
timeout() { [[ $1 == 60 ]] || return 99; shift; "$@"; }
dnf() { printf 'dnf %s\n' "$*" >> "$trace"; return "$dnf_status"; }
reset_case() {
    : > "$trace"
    timer=active cache=activating stop_status=0 restore_status=0 dnf_status=0
    cache_exec='{ path=/usr/bin/dnf ; argv[]=/usr/bin/dnf makecache --timer ; ignore_errors=no ; }'
    DRY_RUN=false
}
reset_case
dnf_install bash-completion >/dev/null 2>&1
[[ $(tail -n 3 "$trace") == $'stop dnf-makecache.service\ndnf --setopt=exit_on_lock=True install -y bash-completion\nstart dnf-makecache.timer' ]]
reset_case; timer=inactive; cache=inactive
dnf_install bash-completion >/dev/null 2>&1
if grep -Eq '^(stop|start) ' "$trace"; then exit 1; fi
grep -q '^dnf --setopt=exit_on_lock=True install -y bash-completion$' "$trace"
reset_case; cache_exec='{ path=/usr/bin/dnf ; argv[]=/usr/bin/dnf upgrade -y ; }'
if dnf_install bash-completion >/dev/null 2>&1; then exit 1; fi
if grep -Eq '^dnf |^stop dnf-makecache.service$' "$trace"; then exit 1; fi
[[ $(tail -n 1 "$trace") == 'start dnf-makecache.timer' ]]
reset_case; dnf_status=7
rc=0; dnf_install bash-completion >/dev/null 2>&1 || rc=$?
[[ $rc == 7 && $(tail -n 1 "$trace") == 'start dnf-makecache.timer' ]]
reset_case; stop_status=9
if dnf_install bash-completion >/dev/null 2>&1; then exit 1; fi
if grep -q '^dnf ' "$trace"; then exit 1; fi
[[ $(tail -n 1 "$trace") == 'start dnf-makecache.timer' ]]
reset_case; restore_status=9
if dnf_install bash-completion >/dev/null 2>&1; then exit 1; fi
reset_case; DRY_RUN=true
dnf_install bash-completion >/dev/null 2>&1
[[ ! -s $trace ]]
echo 'PASS 7 actual DNF coordination cases; no packages, timers or services touched'
