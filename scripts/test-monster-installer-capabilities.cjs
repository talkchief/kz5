'use strict';
// Execute the installer's actual readiness-file gate without filesystem writes.
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm');
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
assert(source.includes("rsync -a --delete --exclude='/apps/acdc/language-capabilities.json'"), 'Full installer lost runtime artifact preservation');
const install = source.split('install_monster_ui() {')[1].split('\nverify_monster_ui() {')[0];
assert(install.indexOf('A Monster UI build must not manufacture runtime language readiness') < install.indexOf('rsync -a --delete'));
assert(install.includes('$(monster_language_capability_hash) == "$runtime_capability_hash"'), 'Post-copy runtime proof comparison missing');
const locations = source.match(/location = \/apps\/acdc\/language-capabilities\.json \{[\s\S]*?\n    \}/g);
assert.equal(locations.length, 2, 'Both HTTPS and HTTP need an exact readiness-file route');
for (const location of locations) {
    assert(location.includes('try_files \\$uri =404;'), 'Missing readiness must return 404, not SPA HTML');
    assert(location.includes('add_header Cache-Control "no-store" always;'), 'Runtime proof response must not be cached');
}
console.log('PASS installer readiness gate: absent/protected proof, corrupt/unprotected/symlink/oversize rejection; build-claim exclusion and preservation wiring');
