#!/usr/bin/env bash
# Offline proposal fixtures. All source-executed commands are replaced before
# running installer functions. Never run the real installer entrypoint here.
set -euo pipefail
source_path=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/install-kazoo5.sh
task_tmp=$(mktemp -d)
trap 'rm -f -- "$task_tmp/identity" "$task_tmp/pins" "$task_tmp/effects"; rmdir -- "$task_tmp"' EXIT
# Extract functions by their top-level boundary; execute actual proposed bodies,
# not a reimplemented routing state machine or matching fixture-only strings.
for function_name in monster_catalog_preflight register_monster_apps verify_monster_app_registration install_monster_ui; do
    eval "$(sed -n "/^${function_name}() {/,/^}/p" "$source_path")"
done
declare -A SELECTED=([monster-ui]=1)
MONSTER_UI_REGISTER_APPS=auto
MONSTER_UI_CATALOG_SSH_HOST=''
MONSTER_UI_CATALOG_SSH_USER=''
MONSTER_UI_CATALOG_SSH_PORT=22
MONSTER_UI_CATALOG_IDENTITY_FILE=''
MONSTER_UI_CATALOG_KNOWN_HOSTS_FILE=''
MONSTER_UI_CATALOG_MASTER_ID=''
MONSTER_CATALOG_MODE=''
MONSTER_UI_APPS_LIST=acdc
MONSTER_UI_WEB_ROOT=/fixture/web
KAZOO_API_URL=https://ui.example.test/v2/
DRY_RUN=false
local_available=false
log() { :; }
die() { exit 91; }
monster_registration_available() { [[ $local_available == true ]]; }
validate_port() { [[ $2 =~ ^[1-9][0-9]*$ ]] && (( $2 <= 65535 )); }
if (monster_catalog_preflight); then
    printf 'FAIL missing standalone authority accepted\n' >&2; exit 1
fi
SELECTED[kazoo-apps]=1
monster_catalog_preflight
[[ $MONSTER_CATALOG_MODE == local ]]
unset 'SELECTED[kazoo-apps]'
local_available=true
monster_catalog_preflight
[[ $MONSTER_CATALOG_MODE == local ]]
local_available=false
MONSTER_UI_REGISTER_APPS=false
monster_catalog_preflight
[[ $MONSTER_CATALOG_MODE == disabled ]]
register_monster_apps
verify_monster_app_registration
MONSTER_UI_REGISTER_APPS=auto
MONSTER_UI_CATALOG_SSH_HOST=apps.example.test
if (monster_catalog_preflight); then
    printf 'FAIL partial authority accepted\n' >&2; exit 1
fi
touch "$task_tmp/identity" "$task_tmp/pins"
chmod 0600 "$task_tmp/identity" "$task_tmp/pins"
MONSTER_UI_CATALOG_SSH_USER=catalog
MONSTER_UI_CATALOG_IDENTITY_FILE=$task_tmp/identity
MONSTER_UI_CATALOG_KNOWN_HOSTS_FILE=$task_tmp/pins
MONSTER_UI_CATALOG_MASTER_ID=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
monster_catalog_preflight
[[ $MONSTER_CATALOG_MODE == remote ]]
# Remote preflight failure must precede Node installation and every UI mutation.
dnf_install() { [[ $* == openssh-clients ]]; }
monster_catalog_remote() { [[ $1 == --check ]] && return 1; exit 92; }
install_monster_nodejs() { touch "$task_tmp/effects"; exit 94; }
# Launch outside a conditional so Bash does not suppress errexit in the real
# installer subshell. The first potential UI effect is a bounded fixture stub.
(set -e; install_monster_ui) & fixture_pid=$!
if wait "$fixture_pid"; then
    printf 'FAIL remote read refusal accepted\n' >&2; exit 1
fi
[[ ! -e $task_tmp/effects ]]
# Remote verify is read-only and routes with the selected apps/API unchanged.
monster_catalog_remote() {
    [[ $# == 4 && $1 == --verify && $2 == /fixture/web && \
       $3 == https://ui.example.test/v2/ && $4 == acdc ]] || exit 93
}
verify_monster_app_registration
# No inherited or old mode can bypass re-resolution.
MONSTER_UI_CATALOG_SSH_HOST=''
MONSTER_UI_CATALOG_SSH_USER=''
MONSTER_UI_CATALOG_IDENTITY_FILE=''
MONSTER_UI_CATALOG_KNOWN_HOSTS_FILE=''
MONSTER_UI_CATALOG_MASTER_ID=''
MONSTER_CATALOG_MODE=remote
if (monster_catalog_preflight); then
    printf 'FAIL stale mode accepted\n' >&2; exit 1
fi
printf 'PASS offline catalog mode and pre-mutation routing fixtures\n'
