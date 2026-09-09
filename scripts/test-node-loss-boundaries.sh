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
recovery_parse --prepare-only --fault broker --concurrent 30
[[ $RECOVERY_COUNT == 30 && $RECOVERY_SERVICE == rabbitmq-server.service ]]
recovery_parse --live --fault broker --concurrent 30
[[ $RECOVERY_COUNT == 30 && $RECOVERY_SERVICE == rabbitmq-server.service ]]
recovery_parse --live --fault broker --concurrent 300 && exit 1
recovery_parse --live --fault broker --concurrent 2 && exit 1
recovery_parse --live --fault arbitrary.service && exit 1
recovery_parse --live --fault && exit 1
recovery_parse --live --fault broker --extra && exit 1
recovery_parse --unknown && exit 1
recovery_parse && exit 1
echo 'PASS 13 actual fault/concurrency-selection boundaries; no fixture, calls or service changes'
