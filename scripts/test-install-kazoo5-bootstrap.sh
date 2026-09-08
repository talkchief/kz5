#!/usr/bin/env bash
# Master-account bootstrap transport regression tests; no live RPC or account changes.
# shellcheck disable=SC1091,SC2016,SC2034
set -Eeuo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo5-bootstrap-test.XXXXXX)
cleanup() {
    rm -f -- "$test_dir/erl_call" "$test_dir/args" "$test_dir/cmdline" \
        "$test_dir/environ" "$test_dir/stdin" "$test_dir/cookie-verified" \
        "$test_dir/rpc-called"
    rmdir -- "$test_dir"
}
trap cleanup EXIT
# shellcheck source=install-kazoo5.sh
source "$SCRIPT_DIR/install-kazoo5.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\0" "$@" >"$RPC_ARGS_FILE"' \
    'tr "\0" "\n" </proc/$$/cmdline >"$RPC_CMDLINE_FILE"' \
    'tr "\0" "\n" </proc/$$/environ >"$RPC_ENVIRON_FILE"' \
    'IFS= read -r rpc || true' \
    'printf "%s" "$rpc" >"$RPC_STDIN_FILE"' \
    'printf "mock erl_call diagnostic that must be suppressed\n" >&2' \
    'touch "$RPC_CALLED_FILE"' \
    'printf "%s" "${RPC_RESULT:-{ok, ok\}}"' \
    'exit "${RPC_EXIT_CODE:-0}"' >"$test_dir/erl_call"
chmod 0700 "$test_dir/erl_call"

export RPC_ARGS_FILE="$test_dir/args"
export RPC_CMDLINE_FILE="$test_dir/cmdline"
export RPC_ENVIRON_FILE="$test_dir/environ"
export RPC_STDIN_FILE="$test_dir/stdin"
export RPC_CALLED_FILE="$test_dir/rpc-called"
export RPC_EXIT_CODE=0

find_erl_call() { printf '%s\n' "$test_dir/erl_call"; }
verify_cookie_copy() {
    [[ $1 == "$KAZOO_RUNTIME_COOKIE_FILE" && $2 == kazoo ]] || \
        fail 'bootstrap did not verify the protected kazoo cookie'
    touch "$test_dir/cookie-verified"
}
timeout() {
    [[ $1 == --signal=KILL && $2 == 120 ]] || fail 'unexpected timeout invocation'
    shift 2
    "$@"
}
runuser() {
    [[ $1 == --user && $2 == kazoo && $3 == -- ]] || fail 'unexpected runuser invocation'
    shift 3
    "$@"
}

KAZOO_HOSTNAME=bootstrap.example.test
KAZOO_NODE_NAME_TYPE=-name
KAZOO_MASTER_ACCOUNT_NAME='Mäster HQ "$(not-code)"'
KAZOO_MASTER_ACCOUNT_REALM=master.example.test
KAZOO_MASTER_ADMIN_USER='admín'
export KAZOO_MASTER_ADMIN_PASSWORD='päss word "$(still-not-code)" \ []'
export KAZOO_COOKIE='must-not-reach-rpc-environment'

bootstrap_master_account_rpc || fail 'safe bootstrap RPC failed'
[[ -e $test_dir/cookie-verified ]] || fail 'protected cookie was not verified'
[[ -e $test_dir/rpc-called ]] || fail 'mock erl_call was not invoked'

name_b64=$(printf '%s' "$KAZOO_MASTER_ACCOUNT_NAME" | base64 -w0)
realm_b64=$(printf '%s' "$KAZOO_MASTER_ACCOUNT_REALM" | base64 -w0)
user_b64=$(printf '%s' "$KAZOO_MASTER_ADMIN_USER" | base64 -w0)
password_b64=$(printf '%s' "$KAZOO_MASTER_ADMIN_PASSWORD" | base64 -w0)
expected_rpc="try case crossbar_maintenance:create_account(base64:decode(<<\"${name_b64}\">>), base64:decode(<<\"${realm_b64}\">>), base64:decode(<<\"${user_b64}\">>), base64:decode(<<\"${password_b64}\">>)) of ok -> ok; _ -> failed end catch _:_ -> failed end."
[[ $(<"$test_dir/stdin") == "$expected_rpc" ]] || fail 'stdin RPC did not preserve UTF-8 values exactly'

for exposed in "$KAZOO_MASTER_ACCOUNT_NAME" "$KAZOO_MASTER_ADMIN_PASSWORD" \
    "$name_b64" "$password_b64"; do
    ! grep -F -- "$exposed" "$test_dir/args" "$test_dir/cmdline" >/dev/null || \
        fail 'master-account input was exposed in process argv'
done
! grep -F 'KAZOO_MASTER_ADMIN_PASSWORD=' "$test_dir/environ" >/dev/null || \
    fail 'administrator password variable reached erl_call environment'
! grep -F 'KAZOO_COOKIE=' "$test_dir/environ" >/dev/null || \
    fail 'cluster cookie variable reached erl_call environment'
if grep -Fx -- '-fetch_stdout' < <(tr '\0' '\n' <"$test_dir/args") >/dev/null; then
    fail 'remote diagnostics must not be fetched'
fi
for result in '{ok, failed}' '{error, timeout}' 'unexpected diagnostic'; do
    export RPC_RESULT=$result
    if failure_output=$(bootstrap_master_account_rpc 2>&1); then
        fail 'non-success RPC result was accepted with transport exit zero'
    fi
    [[ -z $failure_output ]] || fail 'RPC result failure emitted potentially sensitive diagnostics'
done
unset RPC_RESULT

(
    KAZOO_START_TIMEOUT=10
    timeout() { local request; read -r request; [[ $request == *'application:which_applications()'* && $request == *'[cb_accounts, cb_users]'* ]] || exit 8; printf '{ok, ready}'; }
    wait_kazoo_bootstrap_ready
) || fail 'ready Crossbar bootstrap gate was rejected'
if (
    KAZOO_START_TIMEOUT=1
    timeout() { local request; read -r request; printf '{ok, not_ready}'; }
    sleep() { SECONDS=$((SECONDS+2)); }
    wait_kazoo_bootstrap_ready
) >/dev/null 2>&1; then
    fail 'unready Crossbar bootstrap gate passed'
fi

trace_output=$({
    set -x
    bootstrap_master_account_rpc
    set +x
} 2>&1)
[[ $trace_output != *"$KAZOO_MASTER_ADMIN_PASSWORD"* && $trace_output != *"$password_b64"* ]] || \
    fail 'shell tracing disclosed administrator credentials'

RPC_EXIT_CODE=23
export RPC_EXIT_CODE
if failure_output=$(bootstrap_master_account_rpc 2>&1); then
    fail 'RPC transport failure was accepted'
fi
[[ -z $failure_output ]] || fail 'RPC transport failure emitted potentially sensitive diagnostics'

sup() { :; }
master_account_id() { :; }
load_or_create_master_credentials() { :; }
wait_kazoo_bootstrap_ready() { :; }
if failure_output=$( (ensure_master_account) 2>&1); then
    fail 'account bootstrap accepted an RPC transport failure'
fi
[[ $failure_output == *'Could not create the Kazoo master account through the protected Erlang RPC'* ]] || \
    fail 'account bootstrap did not report a safe generic error'
[[ $failure_output != *"$KAZOO_MASTER_ADMIN_PASSWORD"* && $failure_output != *"$password_b64"* ]] || \
    fail 'account bootstrap failure disclosed administrator credentials'

printf 'PASS: master-account bootstrap uses protected stdin RPC without argv/log disclosure\n'
