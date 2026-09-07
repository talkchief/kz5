#!/usr/bin/env bash
# Development-only two-BEAM deployment. No installer-wide rebuild or data writes.
set -Eeuo pipefail
umask 077
[[ $# == 2 && $1 == --tested-local-couch-build && $2 =~ ^/tmp/kazoo-soft-delete-couch\.[A-Za-z0-9]+$ ]] || exit 64
revision_build=$2
cd /opt/kz5
[[ $(id -u) == 0 && $(realpath "$revision_build") == "$revision_build" &&
   $(stat -c '%u:%a' "$revision_build") == 0:700 ]]
sha256sum --status --check "$revision_build/inputs.sha256"
grep -Fxq 'PASS: native primary CouchDB CAS; synthetic database retained' "$revision_build/result.log"
[[ $(tail -1 "$revision_build/stages.log") == passed_marker_and_tombstones_retained ]]
systemctl is-active --quiet kazoo-apps kazoo-ecallmgr kazoo-live-test-agents
revision_calls=$(/usr/local/freeswitch/bin/fs_cli -x 'show calls count')
[[ $revision_calls =~ ^[[:space:]]*0[[:space:]]total\.[[:space:]]*$ ]]
[[ ! -e /etc/kazoo/ring-strategy-acceptance.json ]]
revision_backup=$(mktemp -d /tmp/kazoo-revision-deployment.XXXXXX)
mkdir "$revision_backup/before"
revision_targets=(/opt/kz5/applications/crossbar/ebin/crossbar_doc.beam
    /opt/kz5/core/kazoo_couch/ebin/kz_couch_doc.beam)
for revision_target in "${revision_targets[@]}"; do
    revision_name=${revision_target##*/}
    [[ -f $revision_target && ! -L $revision_target &&
       -f $revision_build/$revision_name && ! -L $revision_build/$revision_name ]]
    cp -p "$revision_target" "$revision_backup/before/$revision_name"
    sha256sum "$revision_target" "$revision_build/$revision_name" "$revision_backup/before/$revision_name" >> "$revision_backup/artifacts.sha256"
done
bash scripts/run-kazoo-validation.sh --memory-mib 192 --reserve-mib 512 --runtime-sec 180 -- \
    /usr/bin/node /opt/kz5/scripts/snapshot-live-test-agent-state.cjs --snapshot "$revision_backup/phone-snapshot-before.json"
revision_changed=false
revision_finish() {
    local revision_status=$?
    trap - EXIT
    if ((revision_status != 0)) && [[ $revision_changed == true ]]; then
        systemctl stop kazoo-apps kazoo-ecallmgr || true
        for revision_target in "${revision_targets[@]}"; do
            install -m 0644 "$revision_backup/before/${revision_target##*/}" "$revision_target" || revision_status=1
        done
        printf 'Revision deployment failed; previous BEAMs restored from %s\n' "$revision_backup/before"
    fi
    systemctl start kazoo-apps kazoo-ecallmgr || revision_status=1
    systemctl is-active --quiet kazoo-apps kazoo-ecallmgr || revision_status=1
    if ((revision_status != 0)) && [[ $revision_changed == true ]]; then
        bash scripts/run-kazoo-validation.sh --memory-mib 192 --reserve-mib 512 --runtime-sec 180 -- \
            /usr/bin/node /opt/kz5/scripts/verify-revision-safety-runtime.cjs "$revision_backup/before" \
            > "$revision_backup/rollback-runtime.json" || revision_status=1
    fi
    printf 'Revision deployment exit %s; receipt/backup %s\n' "$revision_status" "$revision_backup"
    exit "$revision_status"
}
trap revision_finish EXIT
systemctl stop kazoo-apps kazoo-ecallmgr
sha256sum --status --check "$revision_build/inputs.sha256"
sha256sum --status --check "$revision_backup/artifacts.sha256"
revision_changed=true
for revision_target in "${revision_targets[@]}"; do
    install -m 0644 "$revision_build/${revision_target##*/}" "$revision_target"
    cmp --silent "$revision_build/${revision_target##*/}" "$revision_target"
done
systemctl start kazoo-apps kazoo-ecallmgr
bash scripts/run-kazoo-validation.sh --memory-mib 192 --reserve-mib 512 --runtime-sec 180 -- \
    /usr/bin/node /opt/kz5/scripts/verify-revision-safety-runtime.cjs "$revision_build" | tee "$revision_backup/runtime.json"
bash scripts/run-kazoo-validation.sh --memory-mib 192 --reserve-mib 512 --runtime-sec 180 -- \
    /usr/bin/node /opt/kz5/scripts/snapshot-live-test-agent-state.cjs --snapshot "$revision_backup/phone-snapshot-after.json"
/usr/bin/node scripts/snapshot-live-test-agent-state.cjs --compare "$revision_backup/phone-snapshot-before.json" "$revision_backup/phone-snapshot-after.json"
printf 'PASS: two tested revision-safety BEAMs deployed; full HTTP acceptance remains separate\n'
