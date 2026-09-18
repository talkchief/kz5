#!/usr/bin/env bash
# Promote the checked-out kz5 revision to the MAIN development runtime on dev44
# through the normal installer. Codifies doc/main_dev_runtime_promotion.md:
# idle admission, checksummed recovery backups, SIP ingress closed during the
# restart-based install and reopened only after the installer passes.
#
# This restarts kazoo-apps and kazoo-ecallmgr. It is a development procedure,
# not a rolling upgrade and not a tested rollback. A failed install deliberately
# leaves SIP ingress stopped for inspection. Launch it detached with a login
# environment, for example:
#   systemd-run --unit kz5-main-promotion-$(date +%Y%m%d) --property=User=root \
#     --property=RemainAfterExit=yes --property=TimeoutStartSec=2400 \
#     /usr/bin/bash -lc 'exec bash /opt/kz5/scripts/promote-main-dev-runtime.sh'
set -Eeuo pipefail
umask 077
((EUID == 0)) || { echo 'Root required' >&2; exit 1; }
ip -o -4 address show | grep -Eq 'inet 10\.1\.0\.44/' || { echo 'Only development44 allowed' >&2; exit 1; }
[[ -n ${HOME:-} && -d $HOME ]] || { echo 'A login home is required by the installer' >&2; exit 1; }
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$root"
readonly ingress=kazoo-kamailio.service fs_cli=/usr/local/freeswitch/bin/fs_cli
refuse() { printf 'Main promotion refused: %s\n' "$*" >&2; exit 1; }

[[ -z $(git status --porcelain --untracked-files=no) ]] || refuse 'tracked files are modified; promote a committed revision'
source_id=$(git rev-parse HEAD)
exec 9<>/etc/kazoo/monitor-acceptance.lock
flock -n 9 || refuse 'an acceptance run holds the shared lock'

# Idle means no call and no agent on, or being offered, a call. Logged-in agents
# are restored from the database when the node starts, so their mere presence is
# not work in progress; the strict snapshot refuses if any worker is unobserved.
idle() {
    local snapshot address busy
    [[ $("$fs_cli" -x 'show channels as json' | jq -r '.row_count') == 0 ]] || refuse 'main FreeSWITCH has live channels'
    address=$(getent ahostsv4 "$(hostname)" | awk 'NR==1{print $1}')
    snapshot=$(timeout --signal=KILL 120 escript /usr/local/libexec/kazoo5-maintenance-snapshot --snapshot "$address" 2>/dev/null) || \
        refuse 'the strict ACDC agent snapshot refused or is not installed'
    jq -e '.schema_version == 2 and .all_agent_workers_observed == true and (.agents | type) == "array"' <<<"$snapshot" >/dev/null || \
        refuse 'the ACDC agent snapshot is incomplete'
    busy=$(jq -r '[.agents[] | select(.state != "ready" and .state != "paused")] | length' <<<"$snapshot")
    [[ $busy == 0 ]] || refuse "${busy} main ACDC agents are neither ready nor paused"
}
idle
run_dir=$(mktemp -d "/root/kz5-main-promotion-$(date -u +%Y%m%d).XXXXXXXX")
log="$run_dir/run.log"
note() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$log"; }
receipt() {
    printf '{"status":"%s","source":"%s","finished_at":"%s","ingress":"%s"}\n' \
        "$1" "$source_id" "$(date -u +%FT%TZ)" "$(systemctl is-active "$ingress" || true)" > "$run_dir/receipt.json"
}
trap 'receipt FAIL; note "FAILED; SIP ingress is left as is for deliberate recovery: $(systemctl is-active $ingress || true)"' ERR

note "Admitted idle main runtime for source $source_id; run directory $run_dir"
# Recovery material only, never proof of a tested rollback. Never publish.
find core applications deps -type d -name ebin -print0 | tar --null -czf "$run_dir/previous-runtime.tar.gz" -T -
tar -czf "$run_dir/previous-config.tar.gz" -C / etc/kazoo
(cd "$run_dir" && sha256sum previous-runtime.tar.gz previous-config.tar.gz > backups.sha256 && sha256sum --check --quiet backups.sha256)
note 'Checksummed runtime and configuration backups written'

idle
systemctl stop "$ingress"
note 'SIP ingress stopped; starting the normal installer'
# Ingress is closed by this script, so the installer's health gate must not judge it.
KAZOO_INGRESS_CLOSED=true bash scripts/install-kazoo5.sh kazoo-apps ecallmgr >> "$run_dir/install.log" 2>&1
grep -Fq 'All requested Kazoo 5 components passed validation' "$run_dir/install.log" || { note 'Installer did not report validation'; false; }
systemctl start "$ingress"
[[ $(systemctl is-active "$ingress") == active ]] || { note 'SIP ingress did not return'; false; }
# The exemption above is repaid here: every role, including the SIP edge.
sleep 8
/usr/local/libexec/kazoo5-stack-health >> "$run_dir/health.log" 2>&1 || { note "Stack health failed after reopening ingress: $run_dir/health.log"; false; }
trap - ERR
receipt PASS
note "PASS normal installer on $source_id; SIP ingress reopened"
