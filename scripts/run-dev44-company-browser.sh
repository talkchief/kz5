#!/usr/bin/env bash
# Read-only company acceptance on the main development server. No secret argv.
set -Eeuo pipefail
[[ $# == 0 && $EUID == 0 ]] || { echo 'Usage: sudo bash scripts/run-dev44-company-browser.sh' >&2; exit 64; }
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
exec timeout --signal=TERM --kill-after=10 180 \
    "$release/node_modules/node-linux-x64/bin/node" "$script_dir/test-dev44-company-browser.cjs"
