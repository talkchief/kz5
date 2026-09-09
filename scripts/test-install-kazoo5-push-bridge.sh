#!/usr/bin/env bash
# Root executes inside the serialized validation guard. No installation/network.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
export KAZOO_DEPLOYMENT_CONFIG=/nonexistent/kazoo-push-bridge-test.env
source "$root/scripts/install-kazoo5.sh"

[[ $(normalize_component bridge) == push-bridge ]]
[[ $(normalize_component mobile_bridge) == push-bridge ]]
[[ $(normalize_component kazoo-push-bridge) == push-bridge ]]
SELECTED=()
select_component push-bridge
[[ ${#SELECTED[@]} == 1 && ${SELECTED[push-bridge]} == 1 ]]
SELECTED=()
select_component all
[[ ${SELECTED[push-bridge]} == 1 && ${SELECTED[rabbitmq]} == 1 ]]
SELECTED=()
select_component push-bridge
DRY_RUN=true
# Any package/service mutation in dry-run is a regression.
dnf_install() { return 99; }
run() { return 99; }
push_bridge_preflight
install_push_bridge
verify_push_bridge
[[ $(push_bridge_fingerprint) =~ ^[0-9a-f]{64}$ ]]
# Every content-addressed release path must include the imported retry module:
# fingerprint, copy, post-copy comparison and independent verification.
[[ $(declare -f push_bridge_fingerprint | awk '/for file in .*delivery_retry[.]py/ {n++} END {print n+0}') == 1 ]]
[[ $(declare -f install_push_bridge | awk '/for file in .*delivery_retry[.]py/ {n++} END {print n+0}') == 2 ]]
[[ $(declare -f verify_push_bridge | awk '/for file in .*delivery_retry[.]py/ {n++} END {print n+0}') == 1 ]]
[[ $(declare -f push_bridge_fingerprint) == *'bridge-install-layout=venv-umask022-v1'* ]]
[[ $(declare -f install_push_bridge) == *'push_bridge_install_venv "$release"'* ]]

# Real production venv helper, synthetic commands only. Both build stages use
#022 despite a077 caller, failures propagate even in a conditional, and the
#caller retains077 for secrets/config writes after successful or failed builds.
(
    umask 077
    run() {
        [[ $(umask) == 0022 ]] || return 91
        case $1 in
            python3.11) printf '%s\n' venv; return "${venv_failure:-0}" ;;
            /fixture/release/venv/bin/python) printf '%s\n' pip; return "${pip_failure:-0}" ;;
            *) return 92 ;;
        esac
    }
    result=$(push_bridge_install_venv /fixture/release)
    [[ $result == $'venv\npip' && $(umask) == 0077 ]]
    venv_failure=21
    if result=$(push_bridge_install_venv /fixture/release); then exit 93; else [[ $? == 21 ]]; fi
    [[ $result == venv && $(umask) == 0077 ]]
    venv_failure=0 pip_failure=22
    if result=$(push_bridge_install_venv /fixture/release); then exit 94; else [[ $? == 22 ]]; fi
    [[ $result == $'venv\npip' && $(umask) == 0077 ]]
)

# The early preflight must run before generic preflight/install/save. All are
# replaced by sentinels: this tests dispatch, not /etc or the live host.
if (
    push_bridge_preflight() { exit 78; }
    preflight() { exit 91; }
    install_requested() { exit 92; }
    save_deployment_config() { exit 93; }
    main push-bridge
); then
    die 'Expected missing bridge configuration to reject the installation'
else
    [[ $? == 78 ]]
fi

# Exercise the exact activation/rollback tail, not a rewritten model. The
# prerequisite release/path/permission checks stay in install_push_bridge;
# these fixtures start after publishing a fully validated synthetic release.
# Every command in this tail is replaced: no /etc, live symlink, service,
# package, broker, dependency or credential operation is possible here.
bridge_activation_tail=$(declare -f install_push_bridge | awk '
    /local bridge_activation_failed=false/ {copy=1}
    copy {print}
')
[[ $bridge_activation_tail == *'wait "$bridge_verification_pid"'* ]]
eval "exercise_bridge_activation() {
$bridge_activation_tail"

bridge_fixture_dir=$(mktemp -d /tmp/kazoo-bridge-rollback-fixture.XXXXXXXX)
trap 'rm -f -- "$bridge_fixture_dir/events"; rmdir -- "$bridge_fixture_dir"' EXIT

bridge_rollback_case() {
    local scenario=$1 restart_calls=0
    local base=/usr/local/lib/kazoo-push-bridge
    local release=/fixture/releases/new previous=/fixture/releases/previous
    local temporary=/fixture/current.new
    case $scenario in
        first-install) previous='' ;;
        same-release) previous=$release ;;
    esac
    systemctl() {
        case "$*" in
            'restart kazoo-push-bridge.service')
                restart_calls=$((restart_calls + 1))
                printf 'restart:%s\n' "$restart_calls"
                if [[ $scenario == restart-failed && $restart_calls == 1 ||
                      $scenario == rollback-restart-failed && $restart_calls == 2 ]]; then
                    return 1
                fi
                ;;
            daemon-reload) printf '%s\n' daemon-reload ;;
            *) exit 91 ;;
        esac
    }
    ln() {
        [[ $# == 3 && $1 == -s && $2 == "$previous" && $3 == "$temporary" ]] || exit 91
        printf '%s\n' restore-link
    }
    mv() {
        [[ $# == 3 && $1 == -T && $2 == "$temporary" &&
           $3 == /usr/local/lib/kazoo-push-bridge/current ]] || exit 91
        printf '%s\n' publish-previous
    }
    install() {
        [[ "$*" == "-o root -g root -m 0644 $previous/kazoo-push-bridge.service /etc/systemd/system/kazoo-push-bridge.service" ]] || exit 91
        printf '%s\n' restore-unit
    }
    warn() { printf '%s\n' rollback-warning; }
    die() { printf '%s\n' activation-failed; exit 78; }
    verify_push_bridge() {
        printf '%s\n' verify
        case $scenario in
            success) return 0 ;;
            verify-command-failed)
                # A conditional function call would incorrectly reach this
                # success sentinel by suppressing errexit inside the verifier.
                false
                printf '%s\n' UNREACHABLE-verification-success
                ;;
            *) die 'synthetic fixed-category verification failure' ;;
        esac
    }
    exercise_bridge_activation
    printf '%s\n' activation-complete
}

for scenario in success restart-failed verify-exit verify-command-failed first-install same-release rollback-restart-failed; do
    # Launch outside conditional evaluation, matching production's errexit
    # semantics, and capture only fixed synthetic event names from the child.
    ( trap - EXIT; set -e; bridge_rollback_case "$scenario" ) >"$bridge_fixture_dir/events" 2>&1 &
    bridge_fixture_pid=$!
    bridge_fixture_status=0
    wait "$bridge_fixture_pid" || bridge_fixture_status=$?
    bridge_fixture_events=$(<"$bridge_fixture_dir/events")
    [[ $bridge_fixture_events != *UNREACHABLE* ]]
    if [[ $scenario == success ]]; then
        [[ $bridge_fixture_status == 0 && $bridge_fixture_events == $'restart:1\nverify\nactivation-complete' ]]
        continue
    fi
    [[ $bridge_fixture_status == 78 && $bridge_fixture_events != *activation-complete* ]]
    if [[ $scenario == first-install || $scenario == same-release ]]; then
        [[ $bridge_fixture_events != *restore-link* && $bridge_fixture_events != *restart:2* ]]
    else
        [[ $bridge_fixture_events == *$'restore-link\npublish-previous\nrestore-unit\ndaemon-reload\nrestart:2'* ]]
    fi
    if [[ $scenario == restart-failed ]]; then
        [[ $bridge_fixture_events != *verify* ]]
    else
        [[ $bridge_fixture_events == *verify* ]]
    fi
    if [[ $scenario == rollback-restart-failed ]]; then
        [[ $bridge_fixture_events == *rollback-warning* ]]
    else
        [[ $bridge_fixture_events != *rollback-warning* ]]
    fi
done
printf '%s\n' 'PASS push bridge aliases, standalone/ALL selection, dry-run, early fail-closed dispatch and seven activation/rollback cases'
