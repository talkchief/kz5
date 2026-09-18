#!/usr/bin/env bash
# Offline regression for apply_required_source_patch_stack using the real
# ecallmgr ACL patches against the pinned ecallmgr source. A deployed patch must
# stay immutable; later edits to the same lines are further patches of a stack.
# Reproduces private install 21: a host that had the first patch refused the
# in-place edited one. Nothing outside a temporary directory is changed.
set -Eeuo pipefail
umask 077
ps_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
ps_installer="$ps_root/scripts/install-kazoo5.sh"
ps_first="$ps_root/scripts/patches/ecallmgr-acl-command-forwarding.patch"
ps_second="$ps_root/scripts/patches/ecallmgr-acl-forwarding-node-registry.patch"
ps_file=src/ecallmgr_maintenance.erl
ps_work=$(mktemp -d /tmp/kazoo-patch-stack-test.XXXXXX)
trap 'rm -rf -- "$ps_work"' EXIT
ps_pass=0
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { ps_pass=$((ps_pass + 1)); printf 'PASS: %s\n' "$*"; }
function_body() { sed -n "/^$1() {\$/,/^}\$/p" "$ps_installer"; }

bash -n "$ps_installer"
sources=$(function_body ensure_kazoo_sources)
grep -Fq 'apply_required_source_patch_stack "$KAZOO_ROOT/applications/ecallmgr"' <<<"$sources" || fail 'ecallmgr ACL patches are not applied as a stack'
grep -A2 -F 'apply_required_source_patch_stack "$KAZOO_ROOT/applications/ecallmgr"' <<<"$sources" | tr -d '\n' | \
    grep -Eq 'ecallmgr-acl-command-forwarding\.patch.*ecallmgr-acl-forwarding-node-registry\.patch' || fail 'stack order is wrong'
# The first patch is what the private pair already applied; it must never change again.
git -C "$ps_root" diff --quiet e8b7344 -- scripts/patches/ecallmgr-acl-command-forwarding.patch || \
    fail 'the deployed first patch was modified'
pass 'installer applies the two ACL patches as one ordered stack; the deployed first patch is unchanged'

fresh() {
    rm -rf -- "$ps_work/$1"; mkdir -p "$ps_work/$1/src"
    git -C "$ps_root/applications/ecallmgr" show "HEAD:$ps_file" > "$ps_work/$1/$ps_file"
    git -C "$ps_work/$1" init -q
}
stack() {
    local dir=$1; shift
    (
        DRY_RUN=false
        log() { printf '%s\n' "$*"; }
        die() { printf '%s\n' "$*" >&2; exit 1; }
        eval "$(function_body apply_required_source_patch_stack)"
        apply_required_source_patch_stack "$dir" "$@"
    )
}
fresh final; git -C "$ps_work/final" apply "$ps_first"; git -C "$ps_work/final" apply "$ps_second"
expected=$(sha256sum < "$ps_work/final/$ps_file")
is_final() { [[ $(sha256sum < "$ps_work/$1/$ps_file") == "$expected" ]]; }

fresh clean
out=$(stack "$ps_work/clean" "$ps_first" "$ps_second")
[[ $(grep -c '^Applied required source patch' <<<"$out") == 2 ]] && is_final clean || fail 'fresh source'
pass 'fresh pinned source receives both patches'

fresh lab; git -C "$ps_work/lab" apply "$ps_first"
# Why a stack helper exists: with the second patch on top, the plain helper can
# no longer recognise the first one as applied and refuses the whole install.
if ( DRY_RUN=false; log() { :; }; die() { exit 1; }; eval "$(function_body apply_required_source_patch)"
     apply_required_source_patch "$ps_work/lab" "$ps_second" >/dev/null 2>&1 && \
     apply_required_source_patch "$ps_work/lab" "$ps_first" >/dev/null 2>&1 ); then
    fail 'plain helper unexpectedly handles a stacked first patch; the stack helper can be revisited'
fi
fresh lab; git -C "$ps_work/lab" apply "$ps_first"
out=$(stack "$ps_work/lab" "$ps_first" "$ps_second")
[[ $(grep -c '^Applied required source patch' <<<"$out") == 1 ]] && grep -Fq 'node-registry.patch' <<<"$out" && is_final lab || fail 'host with only the first patch'
pass 'host that already has the first patch (private install 21) receives only the second'

out=$(stack "$ps_work/lab" "$ps_first" "$ps_second")
grep -Fq 'already applied' <<<"$out" && [[ $(grep -c '^Applied' <<<"$out") == 0 ]] && is_final lab || fail 'repeat run'
before=$(stat -c '%Y:%i' "$ps_work/lab/$ps_file")
stack "$ps_work/lab" "$ps_first" "$ps_second" >/dev/null
[[ $(stat -c '%Y:%i' "$ps_work/lab/$ps_file") == "$before" ]] || fail 'a repeat run rewrote the source'
pass 'fully applied source is recognised and left untouched'

fresh drift; git -C "$ps_work/drift" apply "$ps_first"
sed -i 's/forward_to_ecallmgr(Function, _Args, \[\]) ->/forward_to_ecallmgr(Function, _Args, []) -> %% local edit/' "$ps_work/drift/$ps_file"
saved=$(sha256sum < "$ps_work/drift/$ps_file")
if stack "$ps_work/drift" "$ps_first" "$ps_second" >/dev/null 2>&1; then fail 'drifted source accepted'; fi
[[ $(sha256sum < "$ps_work/drift/$ps_file") == "$saved" ]] || fail 'a refused stack modified the source'
if stack "$ps_work/clean" "$ps_first" "$ps_work/missing.patch" >/dev/null 2>&1; then fail 'missing patch accepted'; fi
[[ $(DRY_RUN=true; log() { printf '%s\n' "$*"; }; die() { exit 1; }; eval "$(function_body apply_required_source_patch_stack)"
     apply_required_source_patch_stack "$ps_work/drift" "$ps_first" "$ps_second") == 'Would apply required source patch stack'* ]] || fail 'dry run'
pass 'drifted source and a missing patch refuse without modifying anything; dry run only reports'
printf 'All %d patch stack groups passed\n' "$ps_pass"
