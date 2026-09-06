'use strict';
// Rocky Linux 9 real-entrypoint preflight plus portable pure helper fixtures.
// Run under the resource guard and network namespace; no installation/network.
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const cp = require('node:child_process'), assert = require('node:assert/strict');
const installerPath = path.join(__dirname, 'install-kazoo5.sh');
const source = fs.readFileSync(installerPath, 'utf8');
function section(name) {
    const start = source.indexOf('\n' + name + '() {');
    assert(start >= 0, name);
    const rest = source.slice(start + 1), next = /\n\w+\(\) \{/.exec(rest);
    assert(next, name);
    return rest.slice(0, next.index);
}
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'kazoo-endpoint-preflight.'));
assert(/^ID=["']?rocky["']?$/m.test(fs.readFileSync('/etc/os-release', 'utf8')),
    'Full entrypoint fixtures require Rocky Linux 9, matching the installer target');
const env = {PATH: '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin', LANG: 'C',
    KAZOO_DEPLOYMENT_CONFIG: path.join(scratch, 'absent.env'),
    KAZOO_CONFIG_DIR: path.join(scratch, 'absent-config'), KAZOO_INSTALLER_SECRETS: path.join(scratch, 'absent-secrets'),
    KAZOO_COOKIE: '0123456789abcdef'.repeat(4), KAZOO_PUBLIC_HOSTNAME: '', KAZOO_PUBLIC_IP: '127.0.0.1',
    KAZOO_API_URL: 'http://ui.example.invalid/v2/', KAZOO_API_UPSTREAM: 'http://apps.example.invalid:8000/v2/',
    KAZOO_WEBSOCKET_UPSTREAM: 'http://apps.example.invalid:5555/websocket', MONSTER_UI_WEBSOCKET_URL: 'auto'};
let cases = 0;
function run(script, overrides = {}) {
    const result = cp.spawnSync('/bin/bash', ['-c', 'set -Eeuo pipefail\n' + script],
        {env: {...env, ...overrides}, encoding: 'utf8', timeout: 10000, maxBuffer: 1024 * 1024});
    assert(!result.error, result.error?.message);
    assert.equal(result.signal, null);
    return result;
}
const helpers = 'die() { printf "%s\\n" "$*" >&2; exit 1; }\n'
    + section('is_ipv4_address') + section('validate_monster_endpoint') + section('validate_monster_endpoints') + '\nvalidate_monster_endpoints';
for (const [reply, code, expected] of [['1.1.1.1 via 10.20.0.1 dev eth0 src 10.20.0.12', '0', '10.20.0.12'], ['', '2', '127.0.0.1']]) {
    const probe = run(section('detect_primary_ipv4')
        + '\nip() { [[ $* == "-4 route get 1.1.1.1" ]] || exit 91; printf "%s" "$ROUTE_REPLY"; return "$ROUTE_CODE"; }\ndetect_primary_ipv4',
    {ROUTE_REPLY: reply, ROUTE_CODE: code});
    assert.equal(probe.status, 0); assert.equal(probe.stdout.trim(), expected); cases++;
}
assert(section('preflight').includes('KAZOO_PUBLIC_IP=$(detect_primary_ipv4)'));
assert.equal(run(helpers).status, 0); cases++;
for (const socket of ['disabled', 'same-origin', 'wss://events.example.invalid:8443/events', 'ws://events.example.invalid']) {
    assert.equal(run(helpers, {MONSTER_UI_WEBSOCKET_URL: socket}).status, 0); cases++;
}
for (const name of ['KAZOO_API_URL', 'KAZOO_API_UPSTREAM', 'KAZOO_WEBSOCKET_UPSTREAM', 'MONSTER_UI_WEBSOCKET_URL']) {
    const scheme = name === 'MONSTER_UI_WEBSOCKET_URL' ? 'wss' : 'https';
    const endpoint = name.includes('WEBSOCKET') ? '/websocket' : '/v2/';
    for (const value of [`${scheme}://fixture-user:fixture-secret@api.invalid${endpoint}`,
        `${scheme}://api.invalid${endpoint}?key=fixture-secret`, `${scheme}://api.invalid${endpoint}#fragment`,
        `${scheme}://api.invalid:0${endpoint}`, `${scheme}://api.invalid:65536${endpoint}`,
        `${scheme}://api.invalid:bad${endpoint}`, `${scheme}://api.invalid${endpoint}\nfixture-secret`,
        `${scheme}://api.invalid/prefix/..${endpoint}`, `${scheme}://999.999.999.999${endpoint}`,
        `${scheme}://api.123${endpoint}`, `${scheme}://0x7f.0.0.1${endpoint}`]) {
        const direct = run(helpers, {[name]: value});
        assert.notEqual(direct.status, 0, `${name} accepted invalid URL`);
        assert(!direct.stdout.includes('fixture-secret') && !direct.stderr.includes('fixture-secret'));
        // Full entrypoint must reject before logging endpoint values, packages,
        // source fetches or any selected-role installation even on HTTP UI.
        const full = cp.spawnSync('/bin/bash', [installerPath, '--dry-run', 'monster-ui'],
            {env: {...env, [name]: value}, encoding: 'utf8', timeout: 10000, maxBuffer: 1024 * 1024});
        assert(!full.error); assert.notEqual(full.status, 0);
        assert(full.stderr.includes(name), full.stderr);
        assert(!/fixture-secret|Endpoints:|Installing |\[dry-run\]/.test(full.stdout + full.stderr));
        cases++;
    }
}
for (const [name, value] of [['KAZOO_API_URL', 'http://api.invalid/'],
    ['KAZOO_API_UPSTREAM', 'http://api.invalid/prefix/v2/'],
    ['KAZOO_WEBSOCKET_UPSTREAM', 'http://api.invalid/prefix/websocket'],
    ['MONSTER_UI_WEBSOCKET_URL', 'ws://api.invalid/undefined']]) {
    assert.notEqual(run(helpers, {[name]: value}).status, 0); cases++;
}
assert.equal(run(helpers, {KAZOO_API_URL: 'https://api.invalid/prefix/v2/'}).status, 0); cases++;
assert.equal(run(helpers, {KAZOO_API_URL: 'https://api.invalid./v2/'}).status, 0); cases++;
const verifier = 'die() { printf "%s\\n" "$*" >&2; exit 1; }\n'
    + 'curl() { [[ $1 == --disable && ${*: -1} == "$KAZOO_API_URL" ]] || exit 91; '
    + '[[ $* == *"--connect-timeout 10 --max-time 30"* ]] || exit 92; '
    + '[[ ${FIXTURE_FAIL:-false} == false ]] || return 28; printf "%s\\n%s" "$FIXTURE_BODY" "$FIXTURE_STATUS"; }\n'
    + section('verify_monster_ui_api_endpoint') + '\nverify_monster_ui_api_endpoint';
for (const [body, status, valid] of [['{"status":"success","data":{}}', '200', true],
    ['{"status":"error","error":"404"}', '404', true], ['{"status":"error"}', '401', true],
    ['{"not":"crossbar"}', '200', false], ['[]', '200', false], ['1', '200', false],
    ['null', '200', false], ['<html>fallback</html>', '200', false], ['invalid', '200', false],
    ['{}\n{"status":"success"}', '200', false], ['{"status":"success"}\n{"status":"success"}', '200', false],
    ['{"status":"success"}', '302', false], ['{"status":"error"}', '503', false]]) {
    assert.equal(run(verifier, {FIXTURE_BODY: body, FIXTURE_STATUS: status}).status === 0, valid); cases++;
}
assert.notEqual(run(verifier, {FIXTURE_FAIL: 'true'}).status, 0); cases++;
assert(section('verify_monster_ui').includes('verify_monster_ui_api_endpoint'));
assert(section('preflight').indexOf('validate_monster_endpoints') < section('preflight').indexOf('log "Endpoints:'));
const main = source.slice(source.indexOf('\nmain() {'), source.indexOf('\nif [[ ${BASH_SOURCE[0]}'));
assert(main.indexOf('preflight') >= 0 && main.indexOf('preflight') < main.indexOf('install_requested'));
assert.deepEqual(fs.readdirSync(scratch), [], 'Preflight must not create deployment/config/secrets files');
fs.rmdirSync(scratch);
console.log(`PASS ${cases} endpoint validation and external Crossbar response cases; no network or install`);
