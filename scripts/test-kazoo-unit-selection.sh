#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# Normal CLI in non-mutating mode, with synthetic inputs and no saved credentials.
export KAZOO_DEPLOYMENT_CONFIG=/nonexistent/kz5-unit-selection.env
export KAZOO_CONFIG_DIR=/tmp/kz5-unit-selection-config
export KAZOO_COOKIE=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
export KAZOO_PUBLIC_IP=127.0.0.1 KAZOO_ERLANG_DIST_IP=127.0.0.1
for selection in kazoo-apps ecallmgr 'kazoo-apps ecallmgr'; do
    read -r -a roles <<<"$selection"
    output=$(bash "$script_dir/install-kazoo5.sh" --dry-run "${roles[@]}" 2>&1) || {
        printf 'FAIL normal installer dry-run for selected unit roles (output suppressed)\n' >&2
        exit 1
    }
    for pair in 'kazoo-apps:kazoo-apps' 'ecallmgr:kazoo-ecallmgr'; do
        role=${pair%%:*} unit=${pair#*:}
        count=$(awk -v marker="Would install /etc/systemd/system/$unit.service " \
            'index($0, marker) {count++} END {print count+0}' <<<"$output")
        expected=0
        [[ " $selection " != *" $role "* ]] || expected=1
        [[ $count == "$expected" ]] || {
            printf 'FAIL service definition scope for %s: expected %s, got %s\n' "$selection" "$expected" "$count" >&2
            exit 1
        }
    done
    printf 'PASS normal CLI unit selection: %s (dry-run, not live installation)\n' "$selection"
done
