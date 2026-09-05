'use strict';
// SPDX-License-Identifier: MPL-2.0
// Execute the real initializer with a memory filesystem: no live writes/API use.
const fs = require('node:fs'), vm = require('node:vm'), path = require('node:path');
const assert = require('node:assert/strict'), crypto = require('node:crypto');
const validator = require('./validate-acdc-language-capabilities.cjs');
const source = fs.readFileSync(path.join(__dirname, 'ensure-acdc-language-capabilities.cjs'), 'utf8');
const webRoot = '/private/web', directory = webRoot + '/apps/acdc', target = directory + '/language-capabilities.json';
const legacy = JSON.stringify(validator.legacyLanguageCapabilities('2026-09-05T12:00:00Z'));
const full = JSON.parse(legacy); delete full.backend_mode;
for (const [locale, entry] of Object.entries(full.languages)) Object.assign(entry, {
    ready: true, position: true, wait_time: true, callback: true,
    numbers: ['ar-sa', 'he-il'].includes(locale) ? 'prerecorded' : 'native_say',
    number_range: [0, 999999999], numeric_prompt_count: ['ar-sa', 'he-il'].includes(locale) ? 2999 : 0,
    required_prompt_ids: validator.requiredPromptIds.slice(), source_catalog_sha256: 'a'.repeat(64),
    installed_media_sha256: 'b'.repeat(64)
});
validator.assertLanguageCapabilities(full);
const fullBytes = JSON.stringify(full, null, 2) + '\n';

function fixture(options = {}) {
    const nodes = new Map(), fds = new Map(), mutations = [];
    let nextInode = 1, nextFd = 40;
    const make = (kind, data, properties = {}) => ({kind, data: Buffer.from(data || ''), uid: 0,
        mode: kind === 'directory' ? 0o755 : 0o644, dev: 1, ino: nextInode++, mtimeMs: 1, nlink: 1, ...properties});
    for (const name of ['/', '/private', webRoot, webRoot + '/apps', directory]) nodes.set(name, make('directory'));
    if (options.parent) Object.assign(nodes.get(directory), options.parent);
    if (options.content !== undefined) nodes.set(target, make('file', options.content, options.properties));
    const error = code => Object.assign(new Error('fixture ' + code), {code});
    const nodeFor = name => { if (!nodes.has(name)) throw error('ENOENT'); return nodes.get(name); };
    function info(node) {
        return {...node, size: node.data.length, isFile: () => node.kind === 'file',
            isDirectory: () => node.kind === 'directory', isSymbolicLink: () => node.kind === 'symlink'};
    }
    const fakeFs = {
        constants: fs.constants,
        lstatSync: name => info(nodeFor(name)),
        fstatSync: fd => info(fds.get(fd)),
        openSync(name, flags, mode) {
            assert(flags & fs.constants.O_NOFOLLOW, 'Every file open must refuse symlinks');
            if (flags & fs.constants.O_CREAT) {
                assert(flags & fs.constants.O_EXCL, 'Creation must be exclusive');
                if (nodes.has(name)) throw error('EEXIST');
                nodes.set(name, make('file', '', {mode})); mutations.push(['create', name]);
            }
            const node = nodeFor(name);
            if (node.kind === 'symlink') throw error('ELOOP');
            const fd = nextFd++; fds.set(fd, node); return fd;
        },
        readFileSync(fd) {
            if (options.readFailure) throw error('EIO');
            const node = fds.get(fd);
            if (options.changeWhileRead) node.mtimeMs++;
            return Buffer.from(node.data);
        },
        writeFileSync(fd, value) {
            fds.get(fd).data = Buffer.from(value); mutations.push(['write']);
            if (options.writeFailure) throw error('ENOSPC');
        },
        fchmodSync(fd, mode) { fds.get(fd).mode = mode; mutations.push(['chmod', mode]); },
        fsyncSync() { if (options.fsyncFailure) throw error('EIO'); },
        closeSync(fd) { assert(fds.delete(fd), 'Invalid or duplicate descriptor close'); },
        linkSync(from, to) {
            assert.equal(to, target); mutations.push(['link_attempt']);
            if (options.concurrent !== undefined) nodes.set(target, make('file', options.concurrent));
            if (nodes.has(to)) throw error('EEXIST');
            if (options.linkFailure) throw error('EIO');
            nodes.set(to, nodeFor(from)); nodeFor(from).nlink++; mutations.push(['publish']);
        },
        unlinkSync(name) {
            assert(name.startsWith(directory + '/.language-capabilities-') && name.endsWith('.tmp'),
                'Cleanup must never delete the runtime artifact');
            nodeFor(name).nlink--; nodes.delete(name); mutations.push(['unlink']);
        }
    };
    const module = {exports: {}};
    const sandbox = {module, process: {getuid: () => options.uid === undefined ? 0 : options.uid}, Buffer, JSON, Object,
        require(name) {
            if (name === 'node:fs') return fakeFs;
            if (name === './validate-acdc-language-capabilities.cjs') return validator;
            return require(name);
        }};
    vm.runInNewContext(source, sandbox);
    return {run: () => module.exports.ensureCapabilities(webRoot), nodes, mutations, fds,
        content: () => nodes.get(target) && nodes.get(target).data.toString(),
        temporaryCount: () => [...nodes.keys()].filter(name => name.includes('/.language-capabilities-')).length};
}
let passed = 0;
function test(name, body) { body(); passed++; console.log('PASS: ' + name); }
test('Absent artifact creates only an explicit negative legacy state with root0644 ownership', () => {
    const item = fixture(), result = item.run(), manifest = JSON.parse(item.content());
    assert.equal(result.result, 'created_legacy_pending');
    assert.equal(manifest.backend_mode, 'legacy');
    validator.assertLanguageCapabilities(manifest);
    assert(Object.values(manifest.languages).every(entry => Object.values(entry).every(value => value === false)));
    assert.equal(item.nodes.get(target).uid, 0); assert.equal(item.nodes.get(target).mode, 0o644);
    assert.equal(item.temporaryCount(), 0); assert.equal(item.fds.size, 0);
    assert.equal(result.sha256, crypto.createHash('sha256').update(item.content()).digest('hex'));
    assert.equal(item.mutations.filter(value => value[0] === 'publish').length, 1);
});
test('Current fully ready and legacy artifacts are preserved byte-for-byte with zero mutations', () => {
    for (const content of [fullBytes, legacy]) {
        const item = fixture({content});
        assert.equal(item.run().result, 'preserved');
        assert.equal(item.content(), content); assert.deepEqual(item.mutations, []); assert.equal(item.fds.size, 0);
    }
});
test('Corrupt, oversized or contradictory legacy claims fail before any mutations', () => {
    const contradictory = JSON.parse(legacy); contradictory.languages['en-us'].position = true;
    for (const content of ['{broken', '{}', '', ' '.repeat(131073), JSON.stringify(contradictory)]) {
        const item = fixture({content});
        assert.throws(item.run); assert.equal(item.content(), content); assert.deepEqual(item.mutations, []);
    }
});
test('Symlink, nonregular, unowned, writable files and unsafe parents fail closed', () => {
    for (const properties of [{kind: 'symlink'}, {kind: 'directory'}, {kind: 'fifo'}, {uid: 1000}, {mode: 0o666}]) {
        const item = fixture({content: legacy, properties});
        assert.throws(item.run); assert.deepEqual(item.mutations, []);
    }
    for (const parent of [{kind: 'symlink'}, {uid: 1000}, {mode: 0o777}]) {
        const item = fixture({parent}); assert.throws(item.run); assert.deepEqual(item.mutations, []);
    }
    const unprivileged = fixture({uid: 1000}); assert.throws(unprivileged.run); assert.deepEqual(unprivileged.mutations, []);
});
test('Concurrent valid publisher wins exclusive publication and is never overwritten', () => {
    const item = fixture({concurrent: fullBytes});
    assert.equal(item.run().result, 'preserved'); assert.equal(item.content(), fullBytes);
    assert.equal(item.temporaryCount(), 0); assert.equal(item.fds.size, 0);
    assert(!item.mutations.some(value => value[0] === 'publish'));
});
test('Concurrent corrupt publisher aborts without replacing or deleting its artifact', () => {
    const item = fixture({concurrent: '{broken'});
    assert.throws(item.run); assert.equal(item.content(), '{broken'); assert.equal(item.temporaryCount(), 0);
});
test('Write, fsync and publication failures leave no partial public artifact or staging leak', () => {
    for (const options of [{writeFailure: true}, {fsyncFailure: true}, {linkFailure: true}]) {
        const item = fixture(options); assert.throws(item.run);
        assert.equal(item.content(), undefined); assert.equal(item.temporaryCount(), 0); assert.equal(item.fds.size, 0);
    }
});
test('Read error and runtime mutation preserve existing artifact and fail closed', () => {
    for (const options of [{readFailure: true}, {changeWhileRead: true}]) {
        const item = fixture({content: fullBytes, ...options}); assert.throws(item.run);
        assert.equal(item.content(), fullBytes); assert.deepEqual(item.mutations, []); assert.equal(item.fds.size, 0);
    }
});
console.log(`PASS: ${passed} memory-only legacy capability initializer groups`);
