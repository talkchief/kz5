#!/usr/bin/env bash
set -Eeuo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=/dev/null
source "$script_dir/test-acdc-node-loss.sh"
for action in --prepare-only --live; do
    recovery_parse "$action"
    [[ $RECOVERY_SERVICE == kazoo-ecallmgr.service ]]
    recovery_parse "$action" --fault broker
    [[ $RECOVERY_SERVICE == rabbitmq-server.service ]]
done
recovery_parse --live --fault arbitrary.service && exit 1
recovery_parse --live --fault && exit 1
recovery_parse --live --fault broker --extra && exit 1
recovery_parse --unknown && exit 1
recovery_parse && exit 1
echo 'PASS 9 actual fault-selection boundaries; no fixture, calls or service changes'
