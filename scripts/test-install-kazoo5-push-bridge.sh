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
printf '%s\n' 'PASS push bridge aliases, standalone/ALL selection, dry-run and early fail-closed dispatch'
