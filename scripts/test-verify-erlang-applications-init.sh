#!/usr/bin/env bash
# Source-only invocation regression. Every readiness effect is intercepted;
# no cookie, service, distributed-Erlang command or polling sleep is reached.
set -Eeuo pipefail
erlang_test_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
erlang_test_work=$(mktemp -d /tmp/kazoo-erlang-init-fixture.XXXXXX)
trap 'printf "Retained private Erlang initialization fixture: %s\n" "$erlang_test_work"' EXIT
export KAZOO_DEPLOYMENT_CONFIG="$erlang_test_work/no-deployment.env"
# shellcheck source=/dev/null
source "$erlang_test_root/scripts/install-kazoo5.sh"
record() { printf '%s\n' "$1" >> "$erlang_test_work/effects"; }
# Return, rather than exit, deliberately verifies that the new guard remains
# fail-fast even when its caller tests status and Bash suppresses errexit.
die() { printf 'REFUSED %s\n' "$1"; return 1; }
log() { :; }
verify_cookie_copy() { record cookie; }
find_erl_call() { record lookup; printf '%s\n' /fixture/erl_call; }
verify_erlang_logging() { record logging; }
sleep() { record sleep; return 91; }
runuser() { record forbidden-runuser; return 92; }
timeout() {
    local expected=(10 runuser --user kazoo -- /fixture/erl_call
        "$KAZOO_NODE_NAME_TYPE" "kazoo_apps@${KAZOO_HOSTNAME}" -a 'application which_applications')
    [[ $# == ${#expected[@]} ]] || return 93
    local item index=0
    for item in "$@"; do [[ $item == "${expected[$index]}" ]] || return 94; index=$((index + 1)); done
    record rpc
    printf '%s\n' '[{acdc,"test",[]},{crossbar,"test",[]}]'
}

case_run() {
    local case_name=$1 expected_status=$2 expected_effects=$3 actual_status=0 actual_effects output
    : > "$erlang_test_work/effects"
    output=$(
        # Keep the installer's readonly cookie path: the stub records only its
        # invocation and never opens the path or invokes an external command.
        export KAZOO_START_TIMEOUT=1
        export KAZOO_HOSTNAME=fixture.example.invalid KAZOO_NODE_NAME_TYPE=-name
        case $case_name in
            unset-host) unset KAZOO_HOSTNAME ;;
            empty-host) KAZOO_HOSTNAME= ;;
            unset-type) unset KAZOO_NODE_NAME_TYPE ;;
            empty-type) KAZOO_NODE_NAME_TYPE= ;;
            bare-type) KAZOO_NODE_NAME_TYPE=name ;;
            unrelated-type) KAZOO_NODE_NAME_TYPE=-hidden ;;
            whitespace-type) KAZOO_NODE_NAME_TYPE=' -name' ;;
            compound-type) KAZOO_NODE_NAME_TYPE='-name -setcookie value' ;;
            long-name) : ;;
            short-name) KAZOO_HOSTNAME=fixture KAZOO_NODE_NAME_TYPE=-sname ;;
            *) exit 95 ;;
        esac
        verify_erlang_applications kazoo_apps acdc,crossbar
    ) || actual_status=$?
    actual_effects=$(< "$erlang_test_work/effects")
    [[ $actual_status == "$expected_status" && $actual_effects == "$expected_effects" ]] || {
        printf 'FAIL %s status=%s effects=%s\n' "$case_name" "$actual_status" "$actual_effects" >&2
        return 1
    }
    if [[ $expected_status != 0 ]]; then
        [[ $output == REFUSED* ]] || return 1
    fi
    printf 'PASS %s\n' "$case_name"
}
for erlang_test_case in unset-host empty-host unset-type empty-type bare-type unrelated-type whitespace-type compound-type; do
    case_run "$erlang_test_case" 1 ''
done
case_run long-name 0 $'cookie\nlookup\nrpc\nlogging'
case_run short-name 0 $'cookie\nlookup\nrpc\nlogging'
printf '%s\n' 'PASS10 initialization cases:8 invalid invocations refused before effects, both normal naming modes preserve readiness path'
