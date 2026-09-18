#!/usr/bin/env bash
# A patch that has been deployed is never edited: the installer recognises an
# applied patch by reversing it, so changing its bytes makes every host that
# already has it fail its next install (private apps install 21 failed exactly
# that way). A change is a NEW patch stacked after it. scripts/patches/
# MANIFEST.sha256 pins every patch; this fails on a changed, missing or unlisted
# patch. Adding a patch means appending its line:
#   (cd scripts/patches && sha256sum NEW.patch >> MANIFEST.sha256 && LC_ALL=C sort -k2 -o MANIFEST.sha256 MANIFEST.sha256)
set -Eeuo pipefail
pi_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
pi_dir="$pi_root/scripts/patches"; pi_manifest="$pi_dir/MANIFEST.sha256"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
[[ -f $pi_manifest && ! -L $pi_manifest ]] || fail 'scripts/patches/MANIFEST.sha256 is missing'
[[ $(LC_ALL=C sort -k2 "$pi_manifest") == "$(<"$pi_manifest")" ]] || fail 'manifest is not sorted by name'
[[ $(awk '{print $2}' "$pi_manifest" | sort | uniq -d | wc -l) == 0 ]] || fail 'manifest lists a patch twice'
changed=$(cd "$pi_dir" && sha256sum --check --quiet MANIFEST.sha256 2>&1 | sed -n 's/: FAILED.*//p' || true)
[[ -z $changed ]] || fail "deployed patch bytes changed; add a new stacked patch instead: $(tr '\n' ' ' <<<"$changed")"
(cd "$pi_dir" && sha256sum --check --quiet --strict MANIFEST.sha256 >/dev/null 2>&1) || fail 'a listed patch is missing or the manifest is malformed'
unlisted=$(comm -13 <(awk '{print $2}' "$pi_manifest" | LC_ALL=C sort) <(cd "$pi_dir" && ls -- *.patch | LC_ALL=C sort))
[[ -z $unlisted ]] || fail "patch not listed in the manifest: $(tr '\n' ' ' <<<"$unlisted")"
# Every patch the installer applies must exist and be pinned.
while read -r name; do
    grep -Fq "  $name" "$pi_manifest" || fail "installer applies an unpinned patch: $name"
done < <(grep -o 'patches/[A-Za-z0-9._-]*\.patch' "$pi_root/scripts/install-kazoo5.sh" | sed 's#patches/##' | sort -u)
printf 'PASS: %d patches pinned, none changed, none unlisted, every installer patch pinned\nAll 1 patch immutability groups passed\n' "$(wc -l < "$pi_manifest")"
