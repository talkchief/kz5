#!/usr/bin/env bash
# Read-only verifier regressions: all Kazoo/SUP/CouchDB effects are doubles.
set -Eeuo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
test_dir=$(mktemp -d /tmp/kazoo-verify-readonly.XXXXXX)
export KAZOO_DEPLOYMENT_CONFIG="$test_dir/absent-deployment.env"
# shellcheck source=install-kazoo5.sh
source "$SCRIPT_DIR/install-kazoo5.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
export VERIFY_ONLY=true
master_reply='<<"0123456789abcdef0123456789abcdef">>'
api=https://api.example.net/v2/
catalog_reply='{"rows":[{"key":"acdc","value":{"api_url":"'$api'"}},{"key":"callflows","value":{"api_url":"'$api'"}}]}'
timeout() {
    [[ $# == 8 && $1 == --signal=KILL && $2 == 30 && $3 == sup ]] || fail 'Unexpected SUP timeout invocation'
    shift 2
    "$@"
}
sup() {
    [[ $* == '-e kapps_config get_ne_binary <<"accounts">> <<"master_account_id">>' ]] ||
        fail 'Verifier invoked a non-allowlisted maintenance operation'
    printf '%s\n' "$master_reply"
}
couchdb_curl() {
    [[ $* == '--fail --silent --show-error --connect-timeout 5 --max-time 30 http://database.invalid:15984/account%2F01%2F23%2F456789abcdef0123456789abcdef/_design/apps_store/_view/crossbar_listing' ]] ||
        fail 'App catalog must use the exact existing account view with GET only'
    printf 'GET\n' >>"$test_dir/couch-reads"
    printf '%s\n' "$catalog_reply"
}
monster_registration_available() { return 0; }
[[ $(configured_master_account_id) == 0123456789abcdef0123456789abcdef ]] || fail 'Configured master identity was changed'
for master_reply in undefined '{error,not_found}' '<<"not-an-account">>'; do
    if (configured_master_account_id >"$test_dir/rejected-id" 2>"$test_dir/rejected-id-error"); then
        fail 'Missing/malformed master identity must fail without automatic discovery'
    fi
done
printf 'PASS configured-master lookup fails closed without discovery/bootstrap\n'

export KAZOO_COUCHDB_HOST=database.invalid
export KAZOO_COUCHDB_PORT=15984
export MONSTER_UI_REGISTER_APPS=auto
export MONSTER_UI_APPS_LIST=acdc,callflows
export KAZOO_API_URL=$api
master_reply='<<"0123456789abcdef0123456789abcdef">>'
verify_monster_app_registration
[[ $(wc -l <"$test_dir/couch-reads") == 1 ]] || fail 'Catalog query count is not one'
master_reply=undefined
if (verify_monster_app_registration >"$test_dir/no-master" 2>&1); then fail 'Catalog accepted missing master'; fi
[[ $(wc -l <"$test_dir/couch-reads") == 1 ]] || fail 'Missing master still reached a catalog query'
master_reply='<<"0123456789abcdef0123456789abcdef">>'
for catalog_reply in '{"rows":[]}' '{"rows":[{"key":"acdc"}]}' '{"rows":"invalid"}' 'not-json' \
    '{"rows":[{"key":"acdc"},{"key":"acdc"},{"key":"callflows"}]}' \
    '{"rows":[{"key":"acdc"},{"key":"callflows"},{"key":"callflows"}]}'; do
    if (verify_monster_app_registration >"$test_dir/bad-catalog" 2>&1); then fail 'Malformed/incomplete/duplicate catalog accepted'; fi
done
# Registration preserves existing documents, so only verification can notice an
# app that still points at a previous API address. It reports, never repairs.
good_catalog='{"rows":[{"key":"acdc","value":{"api_url":"'$api'"}},{"key":"callflows","value":{"api_url":"'$api'"}}]}'
for catalog_reply in "${good_catalog/$api/http://198.51.100.9:8000/v2/}" \
    '{"rows":[{"key":"acdc","value":{"api_url":"'$api'"}},{"key":"callflows","value":{}}]}'; do
    if (verify_monster_app_registration >"$test_dir/stale-url" 2>&1); then fail 'An app on another or missing api_url was accepted'; fi
    grep -Fq "not the configured $api" "$test_dir/stale-url" && grep -Fq 'doc/monster_app_api_url_migration.md' "$test_dir/stale-url" || \
        fail 'The api_url refusal lacks the cause and the reviewed remedy'
done
grep -Fq 'api_url http://198.51.100.9:8000/v2/' <(catalog_reply="${good_catalog/$api/http://198.51.100.9:8000/v2/}"; verify_monster_app_registration 2>&1 || true) || \
    fail 'The refusal does not name the stale address'
printf 'PASS an app registered with another or no api_url is refused with the stale address and the reviewed migration, never rewritten\n'
printf 'PASS existing app-catalog GET, missing prerequisites, incomplete collections and duplicate selected names fail without repair\n'

if sqlite3 -readonly "$test_dir/missing-kamailio.db" 'PRAGMA integrity_check;' >"$test_dir/sqlite" 2>&1; then
    fail 'Readonly SQLite unexpectedly accepted an absent DB'
fi
[[ ! -e $test_dir/missing-kamailio.db ]] || fail 'Readonly SQLite created an absent DB'
node - "$SCRIPT_DIR/install-kazoo5.sh" <<'JS'
const fs=require('node:fs'), assert=require('node:assert/strict');
const source=fs.readFileSync(process.argv[2],'utf8');
const section=(name,next)=>source.slice(source.indexOf(name+'() {'),source.indexOf('\n'+next+'()'));
const sup=section('verify_sup_beam_export','configure_ecallmgr_dialplan_applications');
assert(sup.includes('sup -e code which'));
assert(sup.includes('beam_lib:chunks(File, [exports])'));
assert(!sup.includes('sup -e code is_loaded'));
assert(!sup.includes('ensure_loaded'), 'SUP verification must not load code');
assert(section('verify_kazoo_apps','verify_sup_cli').includes('configured_master_account_id >/dev/null'));
const catalog=section('verify_monster_app_registration','register_monster_apps');
assert(!catalog.includes('sup crossbar_maintenance apps'), 'Catalog must not invoke repair-capable discovery');
const kamailio=section('verify_kamailio','monster_app_ref');
assert.equal((kamailio.match(/sqlite3 -readonly /g)||[]).length,2);
const rabbit=section('verify_rabbitmq','install_haproxy');
assert(rabbit.includes('runuser --user rabbitmq -- /usr/lib/rabbitmq/bin/rabbitmq-plugins list -e -m'));
JS
printf 'PASS SQLite absent-file safety, SUP no-load checks, and nonrepairing RabbitMQ plugin listing\n'
