#!/usr/bin/env bash
# Replay only the ACDC palette patch against its exact official Callflows pin.
set -Eeuo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
source_dir=${CALLFLOWS_SOURCE_DIR:-/usr/local/src/kazoo5-installer/monster-ui/src/apps/callflows}
readonly expected_ref=11d6a7f797576f2ddd3cbadf6474787e95d5c760
[[ $(git -C "$source_dir" rev-parse HEAD) == "$expected_ref" ]]
test_dir=$(mktemp -d /tmp/kazoo-callflows-acdc-patch.XXXXXX)
cleanup() {
    rm -f -- "$test_dir/app.js" "$test_dir/i18n/en-US.json" "$test_dir/i18n/de-DE.json" \
        "$test_dir/submodules/acdc/acdc.js" "$test_dir/submodules/acdc/views/callflowEdit.html"
    rmdir -- "$test_dir/submodules/acdc/views" "$test_dir/submodules/acdc" \
        "$test_dir/submodules" "$test_dir/i18n" "$test_dir"
}
trap cleanup EXIT
git -C "$source_dir" archive HEAD app.js i18n/en-US.json i18n/de-DE.json | tar -x -C "$test_dir"
git -C "$test_dir" apply --check "$script_dir/patches/monster-ui-callflows-acdc-queue.patch"
git -C "$test_dir" apply "$script_dir/patches/monster-ui-callflows-acdc-queue.patch"
git -C "$test_dir" apply --reverse --check "$script_dir/patches/monster-ui-callflows-acdc-queue.patch"
# The installer applies the call-forward confirmation patch to the same three
# shared files after this one. Replay it in installer order only for the byte
# comparison with the deployed source, then return to the ACDC-only replay.
later_patch="$script_dir/patches/monster-ui-call-forward-confirmation.patch"
later_paths=(--include=app.js --include=i18n/en-US.json --include=i18n/de-DE.json)
git -C "$test_dir" apply "${later_paths[@]}" "$later_patch"
for file in app.js i18n/en-US.json i18n/de-DE.json submodules/acdc/acdc.js submodules/acdc/views/callflowEdit.html; do
    cmp "$source_dir/$file" "$test_dir/$file"
done
git -C "$test_dir" apply --reverse "${later_paths[@]}" "$later_patch"
node "$script_dir/test-monster-callflows-acdc.cjs" "$test_dir"
printf '%s\n' 'PASS fresh pinned Callflows ACDC patch replay, byte equality and reverse/idempotence check'
