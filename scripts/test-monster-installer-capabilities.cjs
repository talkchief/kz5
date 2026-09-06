'use strict';
// Actual readiness-file gate, executable scope check and private plan fixtures.
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm'), os = require('node:os');
const crypto = require('node:crypto'), assert = require('node:assert/strict');
const validator = require('./validate-acdc-language-capabilities.cjs');
const source = fs.readFileSync(path.join(__dirname, 'install-kazoo5.sh'), 'utf8');
const helper = source.split('monster_language_capability_hash() {')[1].split('\n}\n')[0];
const code = helper.split("<<'JS'\n")[1].split('\nJS')[0];
assert(code, 'Installer capability gate was not found');
const file = '/private/web/apps/acdc/language-capabilities.json';
const valid = JSON.stringify({schema_version: 1, generated_at: '2026-09-05T11:00:00Z',
    languages: Object.fromEntries(validator.locales.map(locale => [locale, {
        ready: false, position: false, wait_time: false, callback: false, native_speaker_review: false
    }]))});
function run(content, changes = {}) {
    const output = [], exited = Symbol('exit');
    const fakeFs = {
        existsSync: target => { assert.equal(target, file); return content !== undefined; },
        lstatSync: () => ({isFile: () => true, isSymbolicLink: () => false,
            uid: 0, mode: 0o644, size: Buffer.byteLength(content || ''), ...changes}),
        readFileSync: target => { assert.equal(target, file); return Buffer.from(content); }
    };
    try {
        vm.runInNewContext(code, {require(name) {
            return name === 'node:fs' ? fakeFs : name === '/validator.cjs' ? validator : require(name);
        }, process: {argv: ['node', '-', '/validator.cjs', file], exit: status => { assert.equal(status, 0); throw exited; }},
        console: {log: value => output.push(value)}, JSON});
    } catch (error) { if (error !== exited) throw error; }
    return output;
}
assert.deepEqual(run(undefined), ['absent']);
assert.deepEqual(run(valid), [crypto.createHash('sha256').update(valid).digest('hex')]);
for (const [content, changes] of [['{}', {}], [valid, {uid: 1000}], [valid, {mode: 0o666}],
    [valid, {size: 131073}], [valid, {isSymbolicLink: () => true}], [valid, {isFile: () => false}]]) {
    assert.throws(() => run(content, changes));
}
function installerGates(text) {
    const install = text.split('install_monster_ui() {')[1].split('\nverify_monster_ui() {')[0];
    const steps = ['node "$SCRIPT_DIR/verify-monster-production-artifact.cjs" "$source_dir"',
        'runtime_capability_hash=$(monster_language_capability_hash)',
        'deploy_monster_ui_owned "$source_dir"',
        '[[ $(monster_language_capability_hash) == "$runtime_capability_hash" ]] ||'];
    let previous = -1;
    for (const step of steps) {
        const index = install.indexOf(step);
        assert(index > previous, 'Missing or misordered artifact/capability gate: ' + step);
        previous = index;
    }
}
installerGates(source);
for (const gate of ['node "$SCRIPT_DIR/verify-monster-production-artifact.cjs" "$source_dir"',
    'runtime_capability_hash=$(monster_language_capability_hash)',
    '[[ $(monster_language_capability_hash) == "$runtime_capability_hash" ]] ||']) {
    assert.throws(() => installerGates(source.replace(gate, ':')), /gate/,
        'Removing an actual installer gate must fail the regression');
}
const owned = require('./deploy-owned-monster.cjs');
const deployment = fs.readFileSync(path.join(__dirname, 'deploy-owned-monster.cjs'), 'utf8');
const scope = deployment.match(/^function scoped\(file, selected\) \{[\s\S]*?^\}/m);
assert(scope, 'Actual owned-deployment scope function missing');
const cap = 'apps/acdc/language-capabilities.json';
function checkScope(code) {
    const scoped = vm.runInNewContext(code + '\nscoped', {CAP: cap, CONFIG: 'js/config.js', CORE: ['core']});
    assert.equal(scoped(cap, ['acdc']), false, 'Runtime capability must never become an owned build file');
    assert.equal(scoped('apps/acdc/app.js', ['acdc']), true);
}
checkScope(scope[0]);
assert.throws(() => checkScope(scope[0].replace('file === CAP || ', '')),
    /Runtime capability/, 'Removing capability scope exclusion must fail the regression');
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'monster-capability-plan.'));
try {
    const web = path.join(scratch, 'web'), stage = path.join(scratch, 'stage'), state = path.join(scratch, 'state');
    for (const dir of [web, stage, state]) fs.mkdirSync(dir, {mode: 0o700});
    function put(root, name, bytes) {
        const target = path.join(root, name);
        fs.mkdirSync(path.dirname(target), {recursive: true, mode: 0o700});
        fs.writeFileSync(target, bytes, {mode: 0o600});
    }
    for (const [name, bytes] of Object.entries({'index.html': 'fixture', 'js/main.js': 'fixture',
        'js/config.js': 'define({});', 'css/style.css': 'fixture',
        'build-config.json': '{"preloadedApps":["core","acdc"]}', 'apps/acdc/metadata/app.json': '{"name":"acdc"}'})) {
        put(stage, name, bytes);
    }
    put(web, cap, valid);
    const options = {web, stage, state, selected: ['acdc'], inputs: {fingerprint_sha256: 'a'.repeat(64)}, adopt_existing: true};
    const before = owned.snapshot(web), plan = owned.plan(options);
    assert.equal(plan.preserve[cap], before[cap]);
    assert(!Object.hasOwn(plan.files, cap) && !plan.removes.includes(cap) && !plan.changes.includes(cap));
    put(stage, cap, valid);
    assert.throws(() => owned.plan(options), /Build cannot publish runtime capability/);
    assert.deepEqual(owned.snapshot(web), before, 'Planning must not alter existing runtime proof');
} finally { fs.rmSync(scratch, {recursive: true, force: true}); }
const locations = source.match(/location = \/apps\/acdc\/language-capabilities\.json \{[\s\S]*?\n    \}/g);
assert.equal(locations.length, 2, 'Both HTTPS and HTTP need an exact readiness-file route');
for (const location of locations) {
    assert(location.includes('try_files \\$uri =404;'), 'Missing readiness must return 404, not SPA HTML');
    assert(location.includes('add_header Cache-Control "no-store" always;'), 'Runtime proof response must not be cached');
}
console.log('PASS installer readiness gate: absent/protected proof, corrupt/unprotected/symlink/oversize rejection; build-claim exclusion and preservation wiring');
