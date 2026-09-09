#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
node --test "$script_dir/acdc-broker-preflight.test.cjs"
# Execute the real apps installer body. An incompatible broker must abort before
# any media import, compilation, unit installation or service restart.
body=$(sed -n '/^install_kazoo_apps() {/,/^}/p' "$script_dir/install-kazoo5.sh")
eval "$body"
install_nodejs_toolchain() { :; }
acdc_broker_upgrade_preflight() { exit 73; }
set +e
(install_kazoo_apps)
status=$?
set -e
[[ $status == 73 ]]
printf 'PASS real apps installer aborts at broker guard before application mutations\n'
# A newly incompatible inventory at the second read must also prevent restart.
count=0
acdc_broker_upgrade_preflight() { count=$((count + 1)); if [[ $count == 2 ]]; then exit 74; fi; }
for step in install_call_forward_confirmation_pack install_acdc_language_packs \
    install_acdc_editor_capabilities build_kazoo install_kazoo_systemd_units \
    install_sup_cli install_monster_catalog_receiver; do
    eval "$step() { :; }"
done
service_enable_restart() { exit 99; }
set +e
(install_kazoo_apps)
status=$?
set -e
[[ $status == 74 ]]
printf 'PASS apps restart is blocked when the second broker check fails\n'
bash -n "$script_dir/install-kazoo5.sh"
