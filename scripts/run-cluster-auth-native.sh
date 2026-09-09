#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
[[ $EUID == 0 && $# == 1 && ( $1 == --revocation || $1 == --partition ) ]] || exit 64
lab_dir=/var/lib/kazoo5-install-lab
[[ -d $lab_dir && ! -L $lab_dir && $(stat -c '%u:%a' "$lab_dir") == 0:700 ]] || exit 78
[[ -f $lab_dir/lock && ! -L $lab_dir/lock && $(stat -c '%u:%h' "$lab_dir/lock") == 0:1 ]] || exit 78
exec 9<>"$lab_dir/lock"
flock -n 9 || exit 75
base=/usr/local/lib/kazoo5-browser-tests
[[ -d $base && ! -L $base && $(stat -c '%u:%a' "$base") == 0:700 ]] || exit 78
[[ -L $base/current && $(readlink "$base/current") =~ ^release\.[[:alnum:]]+$ ]] || exit 78
release=$(readlink -f "$base/current")
[[ $release == "$base"/release.* && -d $release && ! -L $release ]] || exit 78
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
cmp "$script_dir/browser-tests/package-lock.json" "$release/package-lock.json"
unset NODE_OPTIONS NODE_PATH
exec timeout --signal=TERM --kill-after=10 120 "$release/node_modules/node-linux-x64/bin/node" \
    "$script_dir/test-fixtures/distributed-lab/cluster-auth.cjs" "$1"
