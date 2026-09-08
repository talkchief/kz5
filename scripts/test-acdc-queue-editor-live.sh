#!/usr/bin/env bash
# Armed isolated editor acceptance; no calls, agent writes or automatic recovery.
set -Eeuo pipefail
editor_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
editor_main() {
    local action=${1:-} account='' extension='' run='' armed=false
    [[ $action == run || $action == run-languages || $action == cleanup ]] || return 64
    shift
    unset -v KAZOO_CALLBACK_TEST_ACCOUNT_ID KAZOO_TEST_QUEUE_EDITOR_EXTENSION KAZOO_ACCEPTANCE_STATE_FILE
    while (($#)); do
        case $1 in
            --fixture-account) [[ $# -ge 2 && -z $account && $2 =~ ^[a-f0-9]{32}$ ]] || return 64; account=$2; shift 2 ;;
            --extension) [[ $# -ge 2 && -z $extension && $2 =~ ^209[0-9]$ ]] || return 64; extension=$2; shift 2 ;;
            --run-dir) [[ $# -ge 2 && -z $run && $2 == /var/log/kazoo-acceptance/* ]] || return 64; run=$2; shift 2 ;;
            --allow-fixture-writes) [[ $armed == false ]] || return 64; armed=true; shift ;;
            *) return 64 ;;
        esac
    done
    [[ $EUID == 0 && -n $account && -n $extension && -n $run && $armed == true ]] || return 64
    export KAZOO_CALLBACK_TEST_ACCOUNT_ID=$account KAZOO_TEST_QUEUE_EDITOR_EXTENSION=$extension
    node "$editor_dir/test-fixtures/callback-fixture-account.cjs" --ensure-lock
    exec {editor_lock_fd}<>/etc/kazoo/monitor-acceptance.lock
    flock -n "$editor_lock_fd"
    node "$editor_dir/test-fixtures/queue-editor-acceptance.cjs" "$action" --allow-fixture-writes "$run"
}
umask 077
editor_main "$@"
