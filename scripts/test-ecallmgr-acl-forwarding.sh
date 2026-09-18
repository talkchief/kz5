#!/usr/bin/env bash
# Offline regression for ecallmgr ACL maintenance commands run from a node that
# has no ecallmgr (SUP's default applications node). Compiles the pinned module
# plus the required patch into a private directory and uses two real Erlang
# nodes on loopback in a private network namespace. No service, broker, database
# or FreeSWITCH is contacted. --baseline runs the unpatched pinned module.
set -Eeuo pipefail
umask 077
acl_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
acl_mode=${1:-current}
[[ $# -le 1 && ( $acl_mode == current || $acl_mode == --baseline ) ]] || { echo 'Use no arguments or --baseline' >&2; exit 2; }
if [[ $(readlink /proc/self/ns/net) == "$(readlink /proc/1/ns/net)" ]]; then
    exec unshare --net -- bash "${BASH_SOURCE[0]}" "$@"
fi
ip link set lo up
acl_work=$(mktemp -d /tmp/kazoo-ecallmgr-acl-forwarding.XXXXXX)
trap 'code=$?; epmd -kill >/dev/null 2>&1 || true; printf "ecallmgr ACL forwarding %s exit %s; evidence %s\n" "$acl_mode" "$code" "$acl_work"' EXIT
cd "$acl_root"
export ERL_LIBS="$acl_root/deps:$acl_root/core:$acl_root/applications"
export HOME="$acl_work" ERL_CRASH_DUMP=/dev/null
acl_source=applications/ecallmgr/src/ecallmgr_maintenance.erl
# An ordered stack: the first patch is deployed and immutable, the second adds
# node-registry discovery (scripts/test-install-kazoo5-patch-stack.sh).
acl_patches=("$acl_root/scripts/patches/ecallmgr-acl-command-forwarding.patch"
    "$acl_root/scripts/patches/ecallmgr-acl-forwarding-node-registry.patch")
# Always rebuild from the pinned file so the patch itself is what is tested.
mkdir -p "$acl_work/repo/src" "$acl_work/ebin"
git -C applications/ecallmgr show "HEAD:src/ecallmgr_maintenance.erl" > "$acl_work/repo/src/ecallmgr_maintenance.erl"
git -C "$acl_work/repo" init -q
if [[ $acl_mode == current ]]; then
    for acl_patch in "${acl_patches[@]}"; do git -C "$acl_work/repo" apply "$acl_patch"; done
    cmp -s "$acl_work/repo/src/ecallmgr_maintenance.erl" "$acl_source" || \
        { echo 'Working ecallmgr source differs from pinned source plus the required patch' >&2; exit 1; }
fi
grep -Fq 'patches/ecallmgr-acl-forwarding-node-registry.patch' scripts/install-kazoo5.sh || \
    { echo 'The forwarding patch is not a required installer patch' >&2; exit 1; }
erlc -Werror +debug_info +warn_unused_vars +warn_missing_spec -I applications/ecallmgr/src -I applications/ecallmgr/include \
    -I applications -pa deps/lager/ebin '+{parse_transform,lager_transform}' -o "$acl_work/ebin" \
    "$acl_work/repo/src/ecallmgr_maintenance.erl"
erlc -Werror -o "$acl_work/ebin" scripts/erlang-tests/ecallmgr_acl_forwarding_tests.erl
cd "$acl_work"
erl -name "acl_apps_$$@127.0.0.1" -setcookie "acl$$" -pa "$acl_work/ebin" -noshell -eval '
    case eunit:test(ecallmgr_acl_forwarding_tests,[verbose]) of ok->halt(0);_->halt(1) end.' | tee "$acl_work/eunit.log"
