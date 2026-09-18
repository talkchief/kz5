#!/usr/bin/env bash
# Guard for the deployment rule: scripts/install-kazoo5.sh is the only
# installation entry point, for one component, several or all. On
# September 18, 2026 an audit found nine tracked scripts that changed a host
# beside it: six focused "deploy" helpers the installer had superseded, and
# three stock upstream leftovers, one of which would have removed the live
# RabbitMQ database (setup-dev.sh: rm -rf /var/lib/rabbitmq, with /opt/kazoo a
# symlink to this tree). This reads tracked file names and text only.
set -Eeuo pipefail
ep_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
ep_installer="$ep_root/scripts/install-kazoo5.sh"
ep_pass=0
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { ep_pass=$((ep_pass + 1)); printf 'PASS: %s\n' "$*"; }
tracked() { git -C "$ep_root" ls-files -- scripts | sed -n 's#^scripts/\([^/]*\)$#\1#p'; }

for removed in setup-dev.sh sync_to_release.bash sync_to_remote.bash deploy-revision-safety-fixes.sh \
               deploy-scope-management-guard.sh deploy-internal-callback.cjs deploy-single-key-callback.cjs \
               deploy-monster-standalone-component.cjs patch-monster-myaccount-bundle.cjs; do
    [[ ! -e $ep_root/scripts/$removed ]] || fail "${removed} is back: it changes a host outside the installer"
done
pass 'the nine side deployment paths removed on September 18, 2026 are absent'

# A script named like an installation path is the installer, a helper the
# installer itself runs, or listed here with the reason it is not a deployment.
declare -A not_a_deployment=(
    [install-live-test-agents.sh]='loopback SIPp fixture phones for acceptance runs, never a stack role'
    [setup-kazoo-browser-tests.sh]='private browser test tooling, not a dependency of any stack role'
    [setup-git.sh]='developer git configuration'
    [setup_docs.bash]='documentation build'
)
while read -r name; do
    [[ $name =~ ^(deploy|install|setup|sync_to|patch-|promote) ]] || continue
    [[ $name != install-kazoo5.sh ]] || continue
    if grep -Fq -- "$name" "$ep_installer"; then continue; fi
    if [[ $name == promote-main-dev-runtime.sh ]]; then
        grep -Eq '^bash scripts/install-kazoo5\.sh ' "$ep_root/scripts/$name" || fail "${name} no longer deploys through the installer"
        continue
    fi
    [[ -n ${not_a_deployment[$name]:-} ]] || \
        fail "scripts/${name} looks like an installation path but the installer does not run it; fold it into install-kazoo5.sh"
done < <(tracked)
pass 'every install/deploy/setup script is the installer, one of its helpers, its development wrapper, or listed test tooling'

# Nothing beside the installer may put code into a running node.
while read -r name; do
    [[ $name != test-* && $name != install-kazoo5.sh ]] || continue
    case $name in *.sh|*.bash|*.cjs|*.py) ;; *) continue ;; esac
    ! grep -Eq 'kazoo_maintenance hotload|code:atomic_load|hotload_app' "$ep_root/scripts/$name" || \
        fail "scripts/${name} loads code into a running node outside the installer"
done < <(tracked)
pass 'no tracked script loads code into a running node beside the installer'

usage=$(bash "$ep_installer" --help)
grep -Fq 'only installation entry point' <<<"$usage" && grep -Fq -- '--interactive' <<<"$usage" || fail 'usage does not state the rule or the menu'
[[ $(bash "$ep_installer" --list | tr '\n' ' ') == 'couchdb rabbitmq haproxy kazoo-apps ecallmgr freeswitch kamailio monster-ui push-bridge all ' ]] || \
    fail 'the component list changed; update the menu and this guard together'
pass 'the installer states the rule and lists nine components plus all'
printf 'All %d single entry point groups passed\n' "$ep_pass"
