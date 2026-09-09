#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=/dev/null
KAZOO_DEPLOYMENT_CONFIG=/nonexistent source "$root/scripts/install-kazoo5.sh"
dnf_install() { installed=("$@"); }
for ERLANG_VERSION in 26.2.5 26.2.6; do
    installed=()
    install_freeswitch_build_dependencies
    count=0
    for package in "${installed[@]}"; do
        case $package in
            erlang*) [[ $package == "erlang-${ERLANG_VERSION}" ]]; count=$((count+1)) ;;
        esac
    done
    [[ $count == 1 ]]
done
echo 'PASS standalone FreeSWITCH explicitly installs the selected Erlang/EI dependency'
