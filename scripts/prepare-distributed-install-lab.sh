#!/usr/bin/env bash
# Explicit development-only system-container acceptance, not a production installer.
set -Eeuo pipefail
((EUID == 0)) || { echo 'Root required for the private staging lab' >&2; exit 1; }
ip -o -4 address show | grep -Eq 'inet 10\.1\.0\.44/' || { echo 'Only development44 allowed' >&2; exit 1; }
lab_dir=/var/lib/kazoo5-install-lab
if [[ ${1:-} == --cold-bootstrap ]]; then lab_dir=/var/lib/kazoo5-cold-bootstrap-lab; fi
if [[ ${1:-} == --cold-bootstrap-final ]]; then lab_dir=/var/lib/kazoo5-cold-bootstrap-final; fi
if [[ ! -e $lab_dir && ! -L $lab_dir ]]; then install -d -m 0700 "$lab_dir"; fi
[[ -d $lab_dir && ! -L $lab_dir && $(stat -c '%u:%a' "$lab_dir") == 0:700 ]] || exit 1
[[ ! -L $lab_dir/lock && ( ! -e $lab_dir/lock || $(stat -c '%u:%h' "$lab_dir/lock") == 0:1 ) ]] || exit 1
exec 9<>"$lab_dir/lock"
flock -n 9 || { echo 'Another staging operation holds the lab lock' >&2; exit 75; }
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
exec node "$script_dir/test-fixtures/distributed-lab/lab.cjs" "$@"
