#!/usr/bin/bash
set -euo pipefail
source_path=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/install-kazoo5.sh
eval "$(sed -n '/^ensure_crb_repository() {/,/^}/p' "$source_path")"
die() { printf '%s\n' "$*" >&2; exit 91; }
dnf() {
    [[ $* == '-q config-manager --dump crb' ]] || exit 92
    case $case_name in
        enabled) printf 'enabled = 1\n' ;;
        disabled) printf 'enabled = %s\n' "$state" ;;
        missing) printf 'unrelated = 1\n' ;;
        ambiguous) printf 'enabled = 1\nenabled = 0\n' ;;
        invalid) printf 'enabled = unknown\n' ;;
        error) return 11 ;;
        unchanged) printf 'enabled = 0\n' ;;
        *) exit 93 ;;
    esac
}
run() {
    [[ $* == 'dnf config-manager --set-enabled crb' ]] || exit 94
    commands+=(enable)
    state=1
}
DRY_RUN=false
for case_name in enabled disabled; do
    state=0 commands=()
    ensure_crb_repository
    if [[ $case_name == enabled ]]; then [[ ${#commands[@]} == 0 ]];
    else [[ ${commands[*]} == enable ]]; fi
done
for case_name in missing ambiguous invalid error unchanged; do
    commands=() state=0
    if (ensure_crb_repository >/dev/null 2>&1); then
        printf 'FAIL repository case %s was accepted\n' "$case_name" >&2; exit 1
    fi
done
DRY_RUN=true case_name=error commands=()
ensure_crb_repository
[[ ${commands[*]} == enable ]]
eval "$(sed -n '/^install_base_dependencies() {/,/^}/p' "$source_path")"
declare -f install_base_dependencies | grep -q ensure_crb_repository
printf 'PASS CRB enabled/disabled, missing/ambiguous/invalid/error, failed enable and dry-run; installer wiring\n'
