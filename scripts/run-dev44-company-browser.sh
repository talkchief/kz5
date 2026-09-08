#!/usr/bin/env bash
# Company reads or explicitly armed isolated queue Save. No secret argv.
set -Eeuo pipefail
[[ $EUID == 0 && ( $# == 0 || ( $# == 1 && ( $1 == --callflows-users || $1 == --queue-create-form ) ) || ( $# == 2 && $1 == --queue-create-save && $2 == --allow-fixture-writes ) ) ]] || { echo 'Usage: sudo bash scripts/run-dev44-company-browser.sh [--callflows-users|--queue-create-form|--queue-create-save --allow-fixture-writes]' >&2; exit 64; }
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
if [[ ${1:-} == --queue-create-save ]]; then
    export KAZOO_CALLBACK_TEST_ACCOUNT_ID=8310dc3170a18de37f205d0da172df65
    node "$script_dir/test-fixtures/callback-fixture-account.cjs" --ensure-lock
    exec 9<>/etc/kazoo/monitor-acceptance.lock
    flock -n 9 || exit 75
fi
exec timeout --signal=TERM --kill-after=10 180 \
    "$release/node_modules/node-linux-x64/bin/node" "$script_dir/test-dev44-company-browser.cjs" "$@"
