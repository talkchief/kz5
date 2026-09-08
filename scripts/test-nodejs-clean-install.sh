#!/usr/bin/bash
set -euo pipefail
source_path=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/install-kazoo5.sh
eval "$(sed -n '/^install_nodejs_toolchain() {/,/^}/p' "$source_path")"
MONSTER_UI_NODE_MAJOR=18 DRY_RUN=true
die() { exit 91; }
dnf() {
    [[ $* == '-q module list nodejs' ]] || exit 92
    [[ $case_name != error ]] || return 11
    printf '%s\n' 'nodejs 18 common [d], development Javascript runtime'
    if [[ $case_name == existing ]]; then printf '%s\n' 'nodejs 18 [e] common [d] [i] Javascript runtime'; fi
    if [[ $case_name == other ]]; then printf '%s\n' 'nodejs 20 [e] common [d] [i] Javascript runtime'; fi
}
run() { commands+=("$*"); }
dnf_install() { [[ $* == 'nodejs npm' ]]; commands+=(packages); }
for case_name in fresh existing other; do
    commands=()
    install_nodejs_toolchain
    case $case_name in
        fresh) [[ ${commands[*]} == 'dnf module enable -y nodejs:18 packages' ]] ;;
        existing) [[ ${commands[*]} == packages ]] ;;
        other) [[ ${commands[*]} == 'dnf module switch-to -y nodejs:18/common packages' ]] ;;
    esac
done
case_name=error
if (install_nodejs_toolchain); then printf 'FAIL repository error was ignored\n' >&2; exit 1; fi
printf 'PASS Node.js fresh/existing/switch/error installer routing; no package or host changes\n'
