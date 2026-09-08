'use strict';
// UI-03: execute the installer registration verifier with controlled SUP lists.
const fs = require('node:fs'), cp = require('node:child_process');
const assert = require('node:assert/strict');
const source = fs.readFileSync(__dirname + '/install-kazoo5.sh', 'utf8');
function extract(name) {
    const start = source.indexOf('\n' + name + '() {'); assert(start >= 0);
    const marker = name === 'kazoo_blackhole_module_output' ? '\nNODE\n}' : '\n}';
    const end = source.indexOf(marker, start); assert(end > start);
    return source.slice(start + 1, end + marker.length) + '\n';
}
assert(extract('ensure_kazoo_sources').includes('patches/kazoo-entitlements-master-ancestry.patch'));
assert.match(extract('configure_kazoo_api_modules'), /for module in [^\n]* cb_entitlements; do/);
assert(extract('configure_kazoo_api_modules').includes('    verify_kazoo_entitlements_module\n'));
assert(extract('verify_acdc_interfaces').includes('    verify_kazoo_entitlements_module\n'));
assert(extract('verify_acdc_interfaces').includes('for endpoint in queues agents external_numbers entitlements; do'));
assert(extract('verify_acdc_interfaces').includes('.data.capabilities | type == "object"'));
const script = `set -Eeuo pipefail
die(){ exit 77; }
timeout(){
  [[ $1 == 30 && $2 == sup ]] || exit 90
  case "$3 $4" in
    'crossbar_config autoload_modules') printf '%s' "$AUTO" ;;
    'crossbar_bindings modules_loaded') printf '%s' "$RUN" ;;
    *) exit 90 ;;
  esac
}
` + extract('kazoo_blackhole_module_output') + extract('verify_kazoo_entitlements_module') + '\nverify_kazoo_entitlements_module\n';
const base = {PATH: '/usr/bin:/bin', DRY_RUN: 'false',
    AUTO: '[<<"cb_users">>,<<"cb_entitlements">>]', RUN: '[cb_users,cb_entitlements]'};
let tests = 0;
for (const [name, overrides, expected] of [
    ['both registered', {}, 0],
    ['missing startup', {AUTO: '[<<"cb_users">>]'}, 77],
    ['missing runtime', {RUN: '[cb_users]'}, 77],
    ['wrong startup suffix', {AUTO: '[<<"cb_entitlements_other">>]'}, 77],
    ['wrong runtime suffix', {RUN: '[cb_entitlements_other]'}, 77],
    ['malformed startup', {AUTO: '{error,unavailable}'}, 77],
    ['malformed runtime', {RUN: '{error,unavailable}'}, 77],
    ['dry run', {DRY_RUN: 'true', AUTO: '', RUN: ''}, 0]
]) {
    const result = cp.spawnSync('/bin/bash', ['--noprofile', '--norc', '-s'],
        {input: script, env: {...base, ...overrides}, encoding: 'utf8', timeout: 5000});
    assert.ifError(result.error); assert.equal(result.status, expected, name + ': ' + result.stderr);
    tests++;
}
console.log('PASS UI-03 installer wiring and ' + tests + ' exact registration checks');
