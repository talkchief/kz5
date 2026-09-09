#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=/dev/null
KAZOO_DEPLOYMENT_CONFIG=/nonexistent source "$root/scripts/install-kazoo5.sh"
log() { :; }
ensure_crb_repository() { :; }
run() { :; }
dnf_install() { installed+=("$@"); }
rpm() { [[ $* == '-q curl-minimal' && $provider == minimal ]]; }
for provider in minimal full absent; do
    installed=()
    install_base_dependencies
    expected=curl
    [[ $provider != minimal ]] || expected=curl-minimal
    count=0
    for package in "${installed[@]}"; do
        case $package in
            curl|curl-minimal) [[ $package == "$expected" ]]; count=$((count+1)) ;;
        esac
    done
    [[ $count == 1 ]]
done
echo 'PASS 3 actual base-dependency curl-provider paths; no packages changed'
