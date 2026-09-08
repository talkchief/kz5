#!/usr/bin/env node
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const helper = path.join(__dirname, 'kz5-git-credential.cjs');
const { requestAllowed, readToken, provisionToken } = require(helper);
let count = 0;
function test(name, callback) { callback(); count++; console.log('PASS ' + name); }
const request = 'protocol=https\nhost=github.com\npath=talkchief/kz5.git\n\n';
test('only exact HTTPS repository accepted', () => {
    assert.equal(requestAllowed(request), true);
    assert.equal(requestAllowed(request.replace('kz5.git', 'kz5')), true);
    assert.equal(requestAllowed(request.replace('\n\n', '\nusername=x-access-token\n\n')), true);
});
test('foreign or ambiguous scope rejected before reading a token', () => {
    for (const input of [
        request.replace('https', 'http'), request.replace('github.com', 'github.com.evil'),
        request.replace('github.com', 'github.com:443'), request.replace('kz5.git', 'kazoo-acdc.git'),
        request.replace('kz5.git', 'kz5.git/'), request.replace('talkchief/', ''),
        request.replace('talkchief/', '/talkchief/'), request.replace('kz5.git', 'kz5.git?secret=x'),
        request.replace('kz5.git', 'kz5%2egit'), request.replace('protocol=https\n', ''),
        request.replace('\n\n', '\nusername=root\n\n'), request + 'host=github.com\n',
        'host=github.com\n' + request, request.replace('\n', '\r\n'),
        request + '\0', request.replace('\n\n', '\npassword=foreign\n\n'), 'x'.repeat(4097)
    ]) assert.equal(requestAllowed(input), false);
});
test('CLI foreign get, store and erase emit no secret or diagnostics', () => {
    for (const operation of ['get', 'store', 'erase']) {
        const child = spawnSync(process.execPath, [helper, operation], {
            input: request.replace('talkchief/kz5.git', 'other/private.git'), encoding: 'utf8'
        });
        assert.equal(child.status, 0); assert.equal(child.stdout, ''); assert.equal(child.stderr, '');
    }
});
test('oversized and unsupported CLI requests fail without reflecting input', () => {
    for (const args of [['get'], ['--provision-stdin'], ['unsupported']]) {
        const child = spawnSync(process.execPath, [helper, ...args], {
            input: 'DO_NOT_REFLECT'.repeat(1000), encoding: 'utf8'
        });
        assert.equal(child.status, 1); assert.equal(child.stdout, '');
        assert.equal(child.stderr, 'kz5 Git credential operation refused\n');
    }
});

if (process.getuid() !== 0) throw new Error('Protected-file regression requires root');
const root = fs.mkdtempSync('/root/kz5-credential-test.');
const token = 'ghp_' + 'A'.repeat(36);
const changed = 'github_pat_' + 'B'.repeat(40);
try {
    const file = path.join(root, 'private', 'github.token');
    test('exclusive provisioning, protected modes, exact readback', () => {
        provisionToken(Buffer.from(token + '\n'), file);
        assert.equal(fs.statSync(path.dirname(file)).mode & 0o777, 0o700);
        assert.equal(fs.statSync(file).mode & 0o777, 0o600);
        assert.equal(readToken(file), token);
    });
    test('repeat preserves bytes/revision; changed token does not overwrite', () => {
        const before = fs.statSync(file);
        provisionToken(Buffer.from(token), file);
        assert.equal(fs.statSync(file).mtimeMs, before.mtimeMs);
        assert.throws(() => provisionToken(Buffer.from(changed), file));
        assert.equal(readToken(file), token);
    });
    test('unsafe file modes refused without repair', () => {
        for (const mode of [0o644, 0o400, 0o666]) {
            fs.chmodSync(file, mode);
            assert.throws(() => readToken(file));
            assert.throws(() => provisionToken(Buffer.from(token), file));
            assert.equal(fs.statSync(file).mode & 0o777, mode);
        }
        fs.chmodSync(file, 0o600);
    });
    test('symlinks and hard links refused', () => {
        const symlink = path.join(root, 'symlink');
        fs.symlinkSync(file, symlink);
        assert.throws(() => readToken(symlink));
        assert.throws(() => provisionToken(Buffer.from(token), symlink));
        const hardlink = path.join(root, 'hardlink');
        fs.linkSync(file, hardlink);
        assert.throws(() => readToken(hardlink));
        assert.throws(() => readToken(file));
        fs.unlinkSync(hardlink);
        assert.equal(readToken(file), token);
    });
    test('unsafe parent, symlink parent and foreign owner refused', () => {
        const parent = path.dirname(file);
        fs.chmodSync(parent, 0o770);
        assert.throws(() => readToken(file));
        assert.throws(() => provisionToken(Buffer.from(token), file));
        fs.chmodSync(parent, 0o700);
        fs.symlinkSync(parent, path.join(root, 'linked-parent'));
        assert.throws(() => provisionToken(Buffer.from(token), path.join(root, 'linked-parent', 'new')));
        assert.throws(() => readToken(path.join(root, 'linked-parent', 'github.token')));
        fs.chownSync(file, 65534, 65534);
        assert.throws(() => readToken(file));
        fs.chownSync(file, 0, 0);
    });
    test('malformed tokens refused; no partial creation', () => {
        const other = path.join(root, 'never-created');
        for (const value of ['invalid', token + '\n\n', token + '\0', token + '\r\n', token + changed,
            ' '.repeat(513), token.replace('A', '\u00c1')]) {
            assert.throws(() => provisionToken(Buffer.from(value), other));
            assert.equal(fs.existsSync(other), false);
        }
        fs.writeFileSync(other, token + '\n\n', { mode: 0o600 });
        assert.throws(() => readToken(other));
        fs.writeFileSync(other, 'x'.repeat(513));
        assert.throws(() => readToken(other));
    });
} finally {
    // Only this test's newly allocated private directory is removed.
    fs.rmSync(root, { recursive: true });
}
console.log('PASS ' + count + ' repository-scoped Git credential groups');
