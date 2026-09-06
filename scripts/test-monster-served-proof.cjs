#!/usr/bin/env node
'use strict';
// Extracted production hooks, real file/receipt hashing, and a curl double.
// No network, service, catalog mutation, or live filesystem access.
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const assert = require('node:assert/strict'), {spawnSync} = require('node:child_process');
const owned = require('./deploy-owned-monster.cjs');
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'monster-served-proof.'));
const web = path.join(root, 'web'), served = path.join(root, 'served'), other = path.join(root, 'other');
const state = path.join(root, 'state'), trace = path.join(root, 'curl-argv');
const installer = fs.readFileSync(path.join(__dirname, 'install-kazoo5.sh'), 'utf8');
const contents = {'index.html': '<html>owned fixture</html>\n', 'js/main.js': 'main\0exact bytes\n\n',
    'js/config.js': 'config\r\n\n', 'css/style.css': 'style', 'build-config.json': '{"preloadedApps":["core"]}'};
let groups = 0;
const test = (name, body) => {body(); groups++; console.log('PASS ' + name);};
function hook(name) {
    const matches = [...installer.matchAll(new RegExp('^' + name + '\\(\\) \\{[\\s\\S]*?^\\}', 'gm'))];
    assert.equal(matches.length, 1); return matches[0][0];
}
const common = `set -euo pipefail
die(){ printf '%s\\n' "$*" >&2; exit 42; }
log(){ :; }
stat(){ printf '600:root\\n'; }
curl(){
    local url="\${@: -1}" asset
    printf '%s\\0' "$@" >> "$TRACE"
    case "$url" in
        https://ui.fixture.invalid/|http://127.0.0.1/) asset=index.html ;;
        *) asset="\${url#*://}"; asset="\${asset#*/}" ;;
    esac
    case "$asset" in
        index.html|js/main.js|js/config.js)
            if [[ $asset == "$BAD_ASSET" && $FAULT == curl ]]; then return 56; fi
            command cat -- "$SERVED/$asset"
            if [[ $asset == "$BAD_ASSET" ]]; then printf '\\n%s' "$STATUS"; else printf '\\n200'; fi ;;
        apps/acdc/language-capabilities.json) printf '404' ;;
        v2/) printf '{"status":"error"}\\n404' ;;
        '') [[ $url == http://ui.fixture.invalid/ ]] || return 98; printf '308 https://ui.fixture.invalid/' ;;
        *) return 99 ;;
    esac
}
`;
function run(options = {}) {
    if (fs.existsSync(trace)) fs.unlinkSync(trace);
    const code = [hook('verify_monster_ui_owned').replace('/usr/local/share/kazoo5-installer/monster-ui-owned/owned.json', path.join(state, 'owned.json')),
        hook('verify_monster_ui_transport'), 'verify_monster_ui_owned fixture', 'verify_monster_ui_transport'].join('\n');
    const result = spawnSync('bash', ['--noprofile', '--norc', '-s'], {encoding: 'utf8', timeout: 10000, input: common + code,
        env: {PATH: '/usr/bin:/bin', SCRIPT_DIR: __dirname, MONSTER_UI_WEB_ROOT: web, KAZOO_PUBLIC_HOSTNAME: '',
            KAZOO_PUBLIC_IP: '192.0.2.10', TRACE: trace, SERVED: served, BAD_ASSET: '', FAULT: '', STATUS: '200', ...options}});
    assert(!result.error, String(result.error)); return result;
}
function mismatch(asset, bytes, host = '') {
    fs.writeFileSync(path.join(served, asset), bytes);
    try {
        const result = run({KAZOO_PUBLIC_HOSTNAME: host});
        assert.equal(result.status, 42, result.stderr);
        assert(result.stderr.includes('does not match the verified configured web root with HTTP 200'));
        assert(!result.stderr.includes('PRIVATE_RESPONSE_BODY'));
    } finally {fs.writeFileSync(path.join(served, asset), contents[asset]);}
}
try {
    for (const dir of [web, served, other, state]) fs.mkdirSync(dir, {mode: 0o700});
    for (const dir of [web, served, other]) for (const [name, bytes] of Object.entries(contents)) {
        const file = path.join(dir, name); fs.mkdirSync(path.dirname(file), {recursive: true, mode: 0o700});
        fs.writeFileSync(file, bytes, {mode: 0o600});
    }
    const hashes = owned.snapshot(web);
    const owner = {version: 1, status: 'complete', web, inputs: {fingerprint_sha256: owned.hash('fixture\n')},
        files: Object.fromEntries(Object.entries(hashes).filter(([name]) => name !== 'js/config.js')),
        configuration_sha256: hashes['js/config.js']};
    fs.writeFileSync(path.join(state, 'owned.json'), JSON.stringify(owner), {mode: 0o600});
    test('normal installer verifies ownership before the served content gate', () => {
        const verifier = hook('verify_monster_ui');
        assert(verifier.indexOf('verify_monster_ui_owned "$expected_build"') < verifier.indexOf('verify_monster_ui_transport'));
    });
    test('HTTP bytes including NUL and trailing newlines pass with configured public-IP Host', () => {
        const result = run(); assert.equal(result.status, 0, result.stderr);
        const argv = fs.readFileSync(trace, 'utf8').split('\0');
        assert(argv.includes('Host: 192.0.2.10')); assert(argv.includes('http://127.0.0.1/js/config.js'));
        assert(argv.includes('--noproxy')); assert(argv.includes('*')); assert(argv.includes('Accept-Encoding: identity'));
        assert(argv.includes('--disable')); assert(!argv.includes('--location'));
    });
    test('HTTPS uses the configured hostname/SNI with loopback resolution and certificate verification', () => {
        const result = run({KAZOO_PUBLIC_HOSTNAME: 'ui.fixture.invalid'}); assert.equal(result.status, 0, result.stderr);
        const argv = fs.readFileSync(trace, 'utf8').split('\0');
        assert(argv.includes('ui.fixture.invalid:443:127.0.0.1')); assert(argv.includes('ui.fixture.invalid:80:127.0.0.1'));
        assert(argv.includes('https://ui.fixture.invalid/js/main.js')); assert(!argv.includes('--insecure')); assert(!argv.includes('-k'));
    });
    test('wrong main bundle, wrong configuration and generic HTML fallback each fail for both origins', () => {
        for (const host of ['', 'ui.fixture.invalid']) for (const asset of ['index.html', 'js/main.js', 'js/config.js'])
            mismatch(asset, '<html>PRIVATE_RESPONSE_BODY</html>', host);
    });
    test('one extra or missing trailing newline fails byte identity', () => {
        mismatch('js/config.js', contents['js/config.js'] + '\n');
        mismatch('js/main.js', contents['js/main.js'].slice(0, -1));
    });
    test('same asset bytes with redirect/error status or curl failure fail', () => {
        for (const status of ['301', '304', '404', '500']) {
            const result = run({BAD_ASSET: 'js/main.js', STATUS: status}); assert.equal(result.status, 42, result.stderr);
        }
        const failed = run({BAD_ASSET: 'js/main.js', FAULT: 'curl'});
        assert.equal(failed.status, 42); assert(failed.stderr.includes('Cannot retrieve served Monster UI asset js/main.js'));
    });
    test('identical alternate configured root fails ownership before any HTTP request', () => {
        const result = run({MONSTER_UI_WEB_ROOT: other}); assert.equal(result.status, 42); assert(!fs.existsSync(trace));
    });
    test('changed local owned bytes cannot redefine expected served proof', () => {
        fs.appendFileSync(path.join(web, 'js/main.js'), 'changed');
        const result = run(); assert.equal(result.status, 42); assert(!fs.existsSync(trace));
    });
    console.log(JSON.stringify({status: 'PASS', groups, scope: 'offline file fixtures and curl doubles only'}));
} finally {fs.rmSync(root, {recursive: true, force: true});}
