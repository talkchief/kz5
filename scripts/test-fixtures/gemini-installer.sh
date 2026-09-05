#!/usr/bin/env bash
# Stub every package, network, service and deployment effect. Private files only.
set -Eeuo pipefail
export KAZOO_DEPLOYMENT_CONFIG="$KAZOO_TEST_WORK/no-deployment.env"
export KAZOO_ROOT="$KAZOO_TEST_WORK/not-deployed-source" KAZOO_BUILD_ROOT="$KAZOO_TEST_WORK/build"
export KAZOO_COUCHDB_HOST=database.example.invalid KAZOO_COUCHDB_PORT=15984
export KAZOO_COUCHDB_USER=fixture-user KAZOO_COUCHDB_PASSWORD=fixture-password
# shellcheck source=/dev/null
source "$KAZOO_TEST_SOURCE_ROOT/scripts/install-kazoo5.sh"
record() { printf '%s\n' "$1" >>"$KAZOO_TEST_TRACE"; }
node() {
    local file=$1
    shift
    case ${file##*/} in
        import-acdc-gemini-voices.cjs)
            "$KAZOO_TEST_NODE" "$KAZOO_TEST_SOURCE_ROOT/scripts/test-install-kazoo5-gemini.cjs" --fixture-importer "$@" ;;
        validate-acdc-gemini-receipt.cjs)
            "$KAZOO_TEST_NODE" "$KAZOO_TEST_SOURCE_ROOT/scripts/test-install-kazoo5-gemini.cjs" --fixture-validator "$@" ;;
        refresh-acdc-gemini-mappings.cjs)
            [[ $1 == --check || $1 == --activate ]] || return 1
            record "cache-${1#--}"
            [[ $KAZOO_TEST_CASE != cache-failure ]] || return 1 ;;
        *) printf 'Forbidden fixture node command\n' >&2; return 1 ;;
    esac
}
couchdb_curl() { "$KAZOO_TEST_NODE" "$KAZOO_TEST_SOURCE_ROOT/scripts/test-install-kazoo5-gemini.cjs" --fixture-couch "$@"; }
install_nodejs_toolchain() { record node-tooling; }
build_kazoo() { record build; }
install_kazoo_systemd_units() { record units; }
install_sup_cli() { record sup-install; }
service_enable_restart() { [[ $1 == kazoo-apps.service ]]; record restart; }
sleep() { :; }
persist_kazoo_apps_config() { record apps-config; }
ensure_master_account() { record master-account; }
configure_kazoo_api_modules() { record api-modules; }
install_kazoo_prompts() { record official-prompts; }
verify_kazoo_apps() { record apps-verify; }
verify_erlang_applications() { [[ $1 == kazoo_apps ]]; record apps-ready; }
write_file() {
    [[ $1 == 0644 && $2 == /usr/local/share/kazoo5-installer/acdc-gemini-media.json ]]
    node "$SCRIPT_DIR/validate-acdc-gemini-receipt.cjs" \
        --fixed-pack "$SCRIPT_DIR/assets/acdc-gemini-fixed-20260905" \
        --completion-pack "$SCRIPT_DIR/assets/acdc-gemini-completion-20260905"
    record receipt-published
}
dnf_install() { printf 'Unexpected direct dependency installation\n' >&2; return 1; }
run() { printf 'Unexpected installer external command\n' >&2; return 1; }
curl() { printf 'Unexpected unstubbed network access\n' >&2; return 1; }
systemctl() { printf 'Unexpected unstubbed service operation\n' >&2; return 1; }
sup() { printf 'Prestart voice import must not call SUP\n' >&2; return 1; }
export DRY_RUN=false
case $KAZOO_TEST_CASE in
    dry-run) DRY_RUN=true; install_acdc_language_packs ;;
    verify-only) verify_acdc_language_packs ;;
    *) install_kazoo_apps ;;
esac
