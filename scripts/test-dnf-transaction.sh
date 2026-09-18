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
# Installed packages never open a transaction (about 700 MB of metadata; the
# private broker guest's dnf was OOM-killed beside RabbitMQ on September 18, 2026).
rpm() {
    if [[ $1 == -qp ]]; then [[ $4 == "$package_file" ]] || return 96; printf '%s\n' "$file_build"; return 0; fi
    [[ $1 == -q && $2 == -- ]] || return 97; shift 2
    for name in "$@"; do [[ " $present " == *" $name "* ]] || return 1; done
}
package_file=$(mktemp /tmp/kazoo-dnf-package.XXXXXX.rpm); file_build=rabbitmq-server-3.13.7-1.el8.noarch
reset_case; present='jq tar'
[[ $(dnf_install jq tar) == '[kazoo5] Packages already installed: jq tar' && ! -s $trace ]]
dnf_install jq missing-one >/dev/null 2>&1
grep -Fxq 'dnf --setopt=exit_on_lock=True install -y jq missing-one' "$trace"
# A group, URL or option is never judged by rpm -q: it always reaches dnf.
for spec in '@development' 'https://example.net/x.rpm' '--enablerepo=crb'; do
    reset_case; present="$spec"; dnf_install "$spec" >/dev/null 2>&1
    grep -Fq -- "install -y $spec" "$trace"
done
# A downloaded package file is present only as that exact build (the broker
# guest's second OOM kill was "dnf install /cache/rabbitmq-server-...rpm").
reset_case; present="$file_build"; dnf_install "$package_file" >/dev/null 2>&1; [[ ! -s $trace ]]
reset_case; present=rabbitmq-server-3.12.0-1.el8.noarch; dnf_install "$package_file" >/dev/null 2>&1
grep -Fq -- "install -y $package_file" "$trace"
rm -f -- "$package_file"
present=
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
reset_case; cache_exec+=' { path=/usr/bin/dnf ; argv[]=/usr/bin/dnf upgrade -y ; }'
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
reset_case
batch() { local i; for ((i=0;i<10;i++)); do (dnf_install bash-completion); done; }
with_dnf_guard batch >/dev/null 2>&1
[[ $(grep -c '^stop dnf-makecache.timer$' "$trace") == 1 ]]
[[ $(grep -c '^stop dnf-makecache.service$' "$trace") == 1 ]]
[[ $(grep -c '^start dnf-makecache.timer$' "$trace") == 1 ]]
[[ $(grep -c '^dnf ' "$trace") == 10 ]]
reset_case
install_requested() { KAZOO_MASTER_ACCOUNT_REALM=resolved.fixture.invalid; }
save_deployment_config() { [[ $KAZOO_MASTER_ACCOUNT_REALM == resolved.fixture.invalid ]] || return 99; echo persisted >> "$trace"; }
with_dnf_guard install_and_persist_requested >/dev/null 2>&1
[[ $(grep -c '^persisted$' "$trace") == 1 ]]
echo 'PASS 10 actual DNF coordination cases including nested batches and resolved-config persistence; no packages, timers or services touched'
