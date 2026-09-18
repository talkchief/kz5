#!/usr/bin/env bash
# Stub every package, network, service and deployment effect. Private files only.
set -Eeuo pipefail
export KAZOO_DEPLOYMENT_CONFIG="$KAZOO_TEST_WORK/no-deployment.env"
export KAZOO_ROOT="$KAZOO_TEST_WORK/not-deployed-source" KAZOO_BUILD_ROOT="$KAZOO_TEST_WORK/build"
export KAZOO_CONFIG_DIR="$KAZOO_TEST_WORK/config"
export KAZOO_COUCHDB_HOST=database.example.invalid KAZOO_COUCHDB_PORT=15984
export KAZOO_COUCHDB_USER=fixture-user KAZOO_COUCHDB_PASSWORD=fixture-password
# shellcheck source=/dev/null
source "$KAZOO_TEST_SOURCE_ROOT/scripts/install-kazoo5.sh"
# Normal CLI validation initializes this derived value. This sourced fixture
# intentionally skips host validation and supplies its isolated node explicitly.
export KAZOO_HOSTNAME=kazoo-fixture.example.invalid
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
            [[ $# == 11 && ( $1 == --check || $1 == --activate ) &&
               $2 == --node && $3 == kazoo_apps@kazoo-fixture.example.invalid &&
               $4 == --receipt && $6 == --fixed-pack &&
               $7 == "$KAZOO_TEST_SOURCE_ROOT/scripts/assets/acdc-gemini-fixed-20260905" &&
               $8 == --completion-pack &&
               $9 == "$KAZOO_TEST_SOURCE_ROOT/scripts/assets/acdc-gemini-completion-20260905" &&
               ${10} == --supplemental-pack &&
               ${11} == "$KAZOO_TEST_SOURCE_ROOT/scripts/assets/acdc-gemini-supplemental-20260906" ]] || return 1
            record "cache-${1#--}"
            [[ $KAZOO_TEST_CASE != cache-failure ]] || return 1 ;;
        ensure-acdc-language-capabilities.cjs)
            [[ $# == 2 && $1 == --config-root && $2 == "$KAZOO_TEST_WORK/config" ]] || return 1
            record editor-capabilities
            [[ $KAZOO_TEST_CASE != capability-failure ]] || return 1 ;;
        *) printf 'Forbidden fixture node command\n' >&2; return 1 ;;
    esac
}
couchdb_curl() { "$KAZOO_TEST_NODE" "$KAZOO_TEST_SOURCE_ROOT/scripts/test-install-kazoo5-gemini.cjs" --fixture-couch "$@"; }
install_nodejs_toolchain() { record node-tooling; }
acdc_broker_upgrade_preflight() { record broker-preflight; }
install_call_forward_confirmation_pack() { record call-forward-pack; }
run_acdc_cardinal_pack() { record "cardinal-${1#--}"; }
validate_acdc_cardinal_receipt() { /usr/bin/cat >/dev/null; }
run_acdc_cardinal_mapping_check() { record "cardinal-cache-${1#--}"; }
install_monster_catalog_receiver() { record catalog-receiver; }
wait_kazoo_datastore_ready() { [[ $1 == kazoo_apps ]]; record datastore-ready; }
wait_kazoo_bootstrap_ready() { record bootstrap-ready; }
ensure_dns_validation_disabled() { record dns-validation; }
finalize_acdc_prerecorded_capabilities() { [[ $1 == --install ]]; record capability-finalize; }
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
    if [[ $1 == 0644 && $2 == /usr/local/share/kazoo5-installer/acdc-cardinal-media.json ]]; then
        /usr/bin/cat >/dev/null; record cardinal-published; return 0
    fi
    [[ $1 == 0644 && $2 == /usr/local/share/kazoo5-installer/acdc-gemini-media.json ]]
    node "$SCRIPT_DIR/validate-acdc-gemini-receipt.cjs" \
        --fixed-pack "$SCRIPT_DIR/assets/acdc-gemini-fixed-20260905" \
        --completion-pack "$SCRIPT_DIR/assets/acdc-gemini-completion-20260905" \
        --supplemental-pack "$SCRIPT_DIR/assets/acdc-gemini-supplemental-20260906"
    record receipt-published
}
dnf_install() { [[ $* == sox ]] || { printf 'Unexpected direct dependency installation\n' >&2; return 1; }; record dependency-sox; }
# External wrappers execute binaries and would bypass the function stubs above.
timeout() { printf 'Unexpected unstubbed external command wrapper\n' >&2; return 1; }
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
