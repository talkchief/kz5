#!/usr/bin/bash
set -euo pipefail
# Run the real install function up to service start against an isolated path.
source_path=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/install-kazoo5.sh
scratch=$(mktemp -d)
trap 'rm -f -- "$scratch/enabled_plugins"; rmdir -- "$scratch"' EXIT
body=$(sed -n '/^install_rabbitmq() {/,/^}/p' "$source_path")
body=${body//\/etc\/rabbitmq/$scratch}
eval "$body"
KAZOO_CACHE_DIR=$scratch RABBITMQ_VERSION=3.13.7 ERLANG_VERSION=26.2.5
KAZOO_RABBITMQ_BIND=127.0.0.1 KAZOO_AMQP_PORT=5672 DRY_RUN=false
log() { :; }
die() { printf '%s\n' "$*" >&2; exit 1; }
dnf_install() { :; }
download() { :; }
write_file() { while IFS= read -r _; do :; done; }
run() {
    case "$1" in
        rabbitmq-plugins)
            # Reproduce the root CLI's first-install output under umask 077.
            (umask 077; printf '[rabbitmq_management,rabbitmq_consistent_hash_exchange].\n' > "$scratch/enabled_plugins")
            [[ $(stat -c '%a' "$scratch/enabled_plugins") == 600 ]]
            ;;
        chown) [[ $2 == root:rabbitmq && $3 == "$scratch/enabled_plugins" ]] ;;
        *) "$@" ;;
    esac
}
service_enable_restart() {
    [[ $1 == rabbitmq-server.service ]]
    [[ $(stat -c '%a' "$scratch/enabled_plugins") == 640 ]]
    [[ $(<"$scratch/enabled_plugins") == '[rabbitmq_management,rabbitmq_consistent_hash_exchange].' ]]
    printf 'PASS fresh umask-077 plugin list is preserved and readable before service start\n'
    exit 0
}
(install_rabbitmq)
