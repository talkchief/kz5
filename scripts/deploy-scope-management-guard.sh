#!/usr/bin/env bash
# Development-only guarded module/default repair; no customer policy writes.
set -Eeuo pipefail
umask 077
[[ $# == 2 && $1 == --tested-build && $2 =~ ^/tmp/kazoo-scope-management\.[A-Za-z0-9]+$ ]] || exit 64
scope_build=$2
cd /opt/kz5
[[ $(id -u) == 0 && $(realpath "$scope_build") == "$scope_build" && $(stat -c '%u:%a' "$scope_build") == 0:700 ]]
sha256sum --status --check "$scope_build/inputs.sha256"
grep -Fq 'All 7 tests passed.' "$scope_build/eunit.log"
systemctl is-active --quiet kazoo-apps kazoo-ecallmgr kazoo-live-test-agents
scope_calls=$(/usr/local/freeswitch/bin/fs_cli -x 'show calls count')
[[ $scope_calls =~ ^[[:space:]]*0[[:space:]]total\.[[:space:]]*$ && ! -e /etc/kazoo/ring-strategy-acceptance.json ]]
scope_backup=$(mktemp -d /tmp/kazoo-scope-deployment.XXXXXX)
mkdir "$scope_backup/before"
scope_names=(cb_scope_restrictions crossbar_config)
for scope_name in "${scope_names[@]}"; do
    scope_target=/opt/kz5/applications/crossbar/ebin/$scope_name.beam
    [[ -f $scope_target && ! -L $scope_target && -f $scope_build/$scope_name.beam && ! -L $scope_build/$scope_name.beam ]]
    cp -p "$scope_target" "$scope_backup/before/"
    sha256sum "$scope_target" "$scope_build/$scope_name.beam" "$scope_backup/before/$scope_name.beam" >> "$scope_backup/artifacts.sha256"
done
bash scripts/run-kazoo-validation.sh --memory-mib 192 --reserve-mib 512 --runtime-sec 180 -- \
    /usr/bin/node /opt/kz5/scripts/snapshot-live-test-agent-state.cjs --snapshot "$scope_backup/phone-snapshot-before.json"
scope_changed=false
scope_finish() {
    local scope_status=$?
    trap - EXIT
    if ((scope_status != 0)) && [[ $scope_changed == true ]]; then
        systemctl stop kazoo-apps || { printf 'Could not stop apps for safe rollback; no rollback writes attempted\n'; exit 1; }
        # A persisted corrected name may survive rollback. Never load the old
        # unguarded policy module, even after an interrupted initial copy.
        install -m 0644 "$scope_build/cb_scope_restrictions.beam" /opt/kz5/applications/crossbar/ebin/cb_scope_restrictions.beam &&
            cmp --silent "$scope_build/cb_scope_restrictions.beam" /opt/kz5/applications/crossbar/ebin/cb_scope_restrictions.beam || {
                printf 'Guarded module could not be restored; apps left stopped; backup %s\n' "$scope_backup"; exit 1;
            }
        install -m 0644 "$scope_backup/before/crossbar_config.beam" /opt/kz5/applications/crossbar/ebin/crossbar_config.beam &&
            cmp --silent "$scope_backup/before/crossbar_config.beam" /opt/kz5/applications/crossbar/ebin/crossbar_config.beam || {
                printf 'Config module could not be restored; apps left stopped; backup %s\n' "$scope_backup"; exit 1;
            }
        printf 'Scope deployment failed; previous config BEAM restored, guarded policy BEAM retained for safe retry\n'
    fi
    systemctl start kazoo-apps || scope_status=1
    systemctl is-active --quiet kazoo-apps || scope_status=1
    printf 'Scope deployment exit %s; receipt/backup %s\n' "$scope_status" "$scope_backup"
    exit "$scope_status"
}
trap scope_finish EXIT
systemctl stop kazoo-apps
sha256sum --status --check "$scope_build/inputs.sha256"
sha256sum --status --check "$scope_backup/artifacts.sha256"
scope_changed=true
for scope_name in "${scope_names[@]}"; do
    install -m 0644 "$scope_build/$scope_name.beam" "/opt/kz5/applications/crossbar/ebin/$scope_name.beam"
    cmp --silent "$scope_build/$scope_name.beam" "/opt/kz5/applications/crossbar/ebin/$scope_name.beam"
done
systemctl start kazoo-apps
bash scripts/run-kazoo-validation.sh --memory-mib 192 --reserve-mib 512 --runtime-sec 180 -- \
    /usr/bin/node /opt/kz5/scripts/verify-scope-management-runtime.cjs "$scope_build" | tee "$scope_backup/runtime.json"
bash scripts/run-kazoo-validation.sh --memory-mib 192 --reserve-mib 512 --runtime-sec 180 -- \
    /usr/bin/node /opt/kz5/scripts/snapshot-live-test-agent-state.cjs --snapshot "$scope_backup/phone-snapshot-after.json"
/usr/bin/node scripts/snapshot-live-test-agent-state.cjs --compare "$scope_backup/phone-snapshot-before.json" "$scope_backup/phone-snapshot-after.json"
printf 'PASS: guarded scope management deployed; user/queue dashboard isolation still requires live tests\n'
