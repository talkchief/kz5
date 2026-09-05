#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016,SC2034,SC2154
set -Eeuo pipefail

TEST_SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
readonly TEST_SCRIPT_DIR
readonly INSTALLER=${TEST_SCRIPT_DIR}/install-kazoo5.sh
readonly STRONG_COOKIE=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

# Isolate resolver tests from the host's installed deployment without creating
# fixtures or changing services.
KAZOO_DEPLOYMENT_CONFIG=/tmp/kazoo5-cookie-test-no-config/deployment.env
KAZOO_CONFIG_DIR=/tmp/kazoo5-cookie-test-no-config
KAZOO_COOKIE_FILE=${KAZOO_CONFIG_DIR}/.erlang.cookie
KAZOO_FREESWITCH_COOKIE_FILE=${KAZOO_CONFIG_DIR}/freeswitch/.erlang.cookie
export KAZOO_DEPLOYMENT_CONFIG KAZOO_CONFIG_DIR KAZOO_COOKIE_FILE
export KAZOO_FREESWITCH_COOKIE_FILE
# shellcheck source=install-kazoo5.sh
source "$INSTALLER"

validate_kazoo_cookie "$STRONG_COOKIE"
if (validate_kazoo_cookie change_me) >/dev/null 2>&1; then
    fail 'known default Erlang cookie unexpectedly passed validation'
fi
if (validate_kazoo_cookie short-cookie) >/dev/null 2>&1; then
    fail 'short Erlang cookie unexpectedly passed validation'
fi
if (validate_kazoo_cookie '0123456789abcdef0123456789abcdef!') >/dev/null 2>&1; then
    fail 'Erlang cookie with unsafe characters unexpectedly passed validation'
fi

(
    SELECTED["kazoo-apps"]=1
    SELECTED["ecallmgr"]=1
    SELECTED["freeswitch"]=1
    KAZOO_COOKIE=
    KAZOO_COOKIE_EXPLICIT=false
    KAZOO_ERLANG_DIST_IP=127.0.0.1
    KAZOO_FREESWITCH_NODES=
    DRY_RUN=true
    VERIFY_ONLY=false
    resolve_kazoo_cookie >/dev/null
    validate_kazoo_cookie "$KAZOO_COOKIE"
) || fail 'fresh all-local dry run did not resolve a strong generated cookie'

if (
    SELECTED["ecallmgr"]=1
    KAZOO_COOKIE=
    KAZOO_COOKIE_EXPLICIT=false
    KAZOO_ERLANG_DIST_IP=10.20.0.13
    KAZOO_FREESWITCH_NODES=freeswitch@media1.example.net
    DRY_RUN=false
    VERIFY_ONLY=true
    resolve_kazoo_cookie
) >/dev/null 2>&1; then
    fail 'unprovisioned distributed Erlang deployment unexpectedly passed'
fi

(
    SELECTED["freeswitch"]=1
    KAZOO_COOKIE=$STRONG_COOKIE
    KAZOO_COOKIE_EXPLICIT=true
    KAZOO_ERLANG_DIST_IP=10.20.0.15
    DRY_RUN=true
    VERIFY_ONLY=false
    resolve_kazoo_cookie
    [[ $KAZOO_COOKIE == "$STRONG_COOKIE" ]]
) || fail 'explicit distributed Erlang cookie was not preserved'

grep -Fq 'mod-kazoo-cookie-redaction.patch' "$INSTALLER" ||
    fail 'installer does not apply the mod_kazoo cookie-redaction patch'
grep -Fq 'kazoo-cookie-redaction.patch' "$INSTALLER" ||
    fail 'installer does not apply the Kazoo/SUP cookie-redaction patch'
grep -Fq '<param name=\"cookie-file\" value=\"${KAZOO_FREESWITCH_COOKIE_FILE}\" />' "$INSTALLER" ||
    fail 'FreeSWITCH configuration does not use its protected cookie file'
grep -Fq 'KAZOO_ERLANG_DIST_IP}:8031' "$INSTALLER" ||
    fail 'FreeSWITCH mod_kazoo listener is not verified on its configured address'
if grep -Fq 'KAZOO_COOKIE=${KAZOO_COOKIE:-change_me}' "$INSTALLER"; then
    fail 'installer still has a known-default Erlang cookie fallback'
fi
if grep -Fq -- '-c "$KAZOO_COOKIE"' "$INSTALLER"; then
    fail 'installer still exposes its Erlang cookie in process arguments'
fi
grep -Fq 'verify_freeswitch deferred' "$INSTALLER" ||
    fail 'ALL does not defer the pre-eCallMgr media dependency check'
grep -Fq 'if [[ ${SELECTED[freeswitch]:-} ]]; then verify_freeswitch; fi' "$INSTALLER" ||
    fail 'final ALL verification does not rerun the strict FreeSWITCH media check'
deferred_line=$(grep -n -m1 'verification_mode == deferred' "$INSTALLER" | cut -d: -f1)
sofia_line=$(grep -n -m1 'sofia_status=.*sofia status profile' "$INSTALLER" | cut -d: -f1)
stability_line=$(grep -n -m1 'Holding FreeSWITCH stability check' "$INSTALLER" | cut -d: -f1)
media_gate_line=$(grep -n -m1 'require_media_connection == true &&.*media_connected' "$INSTALLER" | cut -d: -f1)
((stability_line < deferred_line && deferred_line < media_gate_line && media_gate_line < sofia_line)) ||
    fail 'deferred verification must retain native stability checks and postpone Sofia'
grep -Fq 'if [[ $media_connected == true || $require_media_connection == true ]]; then' "$INSTALLER" ||
    fail 'Sofia readiness is not conditional on an established or required eCallMgr link'
grep -Fq 'remote eCallMgr link and Sofia readiness are delegated' "$INSTALLER" ||
    fail 'standalone FreeSWITCH does not delegate dynamic Sofia readiness'
if grep -Eq 'cookie (to|matches).*~[ps]|with cookie ~[ps]' \
    "$TEST_SCRIPT_DIR/../core/kazoo_apps/src/kazoo_apps_init.erl" \
    "$TEST_SCRIPT_DIR/../core/sup/src/sup.erl"; then
    fail 'Kazoo or SUP still logs an Erlang cookie value'
fi

printf 'PASS: strong cookie resolution, distributed provisioning gates, protected FreeSWITCH cookie, and redaction checks\n'
