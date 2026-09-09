#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
[[ $EUID == 0 && ( $# == 0 || ( $# == 1 && $1 == --principal ) ) ]] || exit 64
test_file=test-blackhole-stream-native.cjs
[[ $# == 0 ]] || test_file=test-blackhole-principal-native.cjs
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
base=/usr/local/lib/kazoo5-browser-tests
[[ -d $base && ! -L $base && $(stat -c '%u:%a' "$base") == 0:700 ]] || exit 78
[[ -L $base/current && $(readlink "$base/current") =~ ^release\.[[:alnum:]]+$ ]] || exit 78
release=$(readlink -f "$base/current")
[[ $release == "$base"/release.* && -d $release && ! -L $release ]] || exit 78
cmp "$script_dir/browser-tests/package-lock.json" "$release/package-lock.json"
export KZ5_PLAYWRIGHT_ROOT=$release/node_modules/playwright
export PLAYWRIGHT_BROWSERS_PATH=$release/browsers
unset KZ5_BROWSER_EXECUTABLE NODE_OPTIONS NODE_PATH
exec timeout --signal=TERM --kill-after=10 90 \
    "$release/node_modules/node-linux-x64/bin/node" "$script_dir/$test_file"
