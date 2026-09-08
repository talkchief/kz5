'use strict';
// UI-01: registration, preservation and failure behavior of the real installer functions.
const fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const cp = require('node:child_process'), assert = require('node:assert/strict');
const source = fs.readFileSync(path.join(__dirname, 'install-kazoo5.sh'), 'utf8');
function extract(name) {
    const start = source.indexOf('\n' + name + '() {'); assert(start >= 0, name + ' missing');
    const marker = name === 'kazoo_blackhole_module_output' ? '\nNODE\n}' : '\n}';
    const end = source.indexOf(marker, start); assert(end > start);
    return source.slice(start + 1, end + marker.length) + '\n';
}
assert(extract('configure_kazoo_api_modules').includes('    configure_kazoo_storage_module\n'));
assert(extract('verify_acdc_interfaces').includes('    verify_kazoo_storage_module\n'));
assert(extract('verify_acdc_interfaces').includes('http://127.0.0.1:8000/v2/storage/plans'));
const script = `set -Eeuo pipefail
die(){ echo "$*" >&2; exit 77; }
log(){ :; }
timeout(){
  [[ $1 == 30 && $2 == sup ]] || exit 90
  case "$3 $4" in
    'crossbar_config autoload_modules')
      if [[ -e $CASE_DIR/started ]]; then printf '%s' "$AFTER_AUTO"; else printf '%s' "$BEFORE_AUTO"; fi ;;
    'crossbar_bindings modules_loaded')
      if [[ -e $CASE_DIR/started ]]; then printf '%s' "$AFTER_RUN"; else printf '%s' "$BEFORE_RUN"; fi ;;
    'crossbar_maintenance start_module')
      [[ $5 == cb_storage ]] || exit 90
      touch "$CASE_DIR/started"
      printf '%s' "$START_OUTPUT"
      return "$START_STATUS" ;;
    *) exit 90 ;;
  esac
}
` + extract('kazoo_blackhole_module_output') + extract('configure_kazoo_storage_module')
    + extract('verify_kazoo_storage_module') + '\n"$ACTION"\n';
const base = {PATH: '/usr/bin:/bin', DRY_RUN: 'false', ACTION: 'configure_kazoo_storage_module',
    BEFORE_AUTO: '[<<"cb_users">>]', BEFORE_RUN: '[cb_users]',
    AFTER_AUTO: '[<<"cb_users">>,<<"cb_storage">>]', AFTER_RUN: '[cb_users,cb_storage]',
    START_STATUS: '0', START_OUTPUT: 'started and added cb_storage to autoloaded modules'};
let tests = 0;
for (const [name, overrides, expected, wrote] of [
    ['register absent module and preserve others', {}, 0, true],
    ['already registered is read-only', {BEFORE_AUTO: base.AFTER_AUTO, BEFORE_RUN: base.AFTER_RUN}, 0, false],
    ['dry run is non-mutating', {DRY_RUN: 'true'}, 0, false],
    ['malformed initial list refuses mutation', {BEFORE_AUTO: '{error,unavailable}'}, 77, false],
    ['start nonzero', {START_STATUS: '1'}, 77, true],
    ['start failure text', {START_OUTPUT: 'failed to start cb_storage'}, 77, true],
    ['missing persistence', {AFTER_AUTO: base.BEFORE_AUTO}, 77, true],
    ['missing runtime', {AFTER_RUN: base.BEFORE_RUN}, 77, true],
    ['suffix is not membership', {AFTER_RUN: '[cb_users,cb_storage_other]'}, 77, true],
    ['malformed final list', {AFTER_AUTO: '{error,unavailable}'}, 77, true],
    ['lost existing persistence', {AFTER_AUTO: '[<<"cb_storage">>]'}, 77, true],
    ['lost existing runtime', {AFTER_RUN: '[cb_storage]'}, 77, true],
    ['verify registered without mutation', {ACTION: 'verify_kazoo_storage_module', BEFORE_AUTO: base.AFTER_AUTO, BEFORE_RUN: base.AFTER_RUN}, 0, false],
    ['verify missing without repair', {ACTION: 'verify_kazoo_storage_module'}, 77, false]
]) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'kz5-storage-installer-'));
    try {
        const result = cp.spawnSync('/bin/bash', ['--noprofile', '--norc', '-s'],
            {input: script, env: {...base, ...overrides, CASE_DIR: dir}, encoding: 'utf8', timeout: 5000});
        assert.ifError(result.error); assert.equal(result.status, expected, name + ': ' + result.stderr);
        assert.equal(fs.existsSync(path.join(dir, 'started')), wrote, name + ': unexpected mutation');
        tests++;
    } finally {
        const marker = path.join(dir, 'started');
        if (fs.existsSync(marker)) fs.unlinkSync(marker);
        fs.rmdirSync(dir);
    }
}
console.log('PASS UI-01 storage installer wiring and ' + tests + ' registration/preservation checks');
