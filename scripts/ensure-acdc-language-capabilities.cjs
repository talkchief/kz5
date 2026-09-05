#!/usr/bin/env node
'use strict';
// SPDX-License-Identifier: MPL-2.0
// Installs a negative legacy state ONLY when no runtime artifact exists.
// Never call this as a readiness publisher: it probes no Erlang node or audio.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const {assertLanguageCapabilities, legacyLanguageCapabilities} = require('./validate-acdc-language-capabilities.cjs');

function protectedParents(directory) {
    let current = directory;
    for (;;) {
        const stat = fs.lstatSync(current);
        assert(stat.isDirectory() && !stat.isSymbolicLink() && stat.uid === 0 && (stat.mode & 0o022) === 0,
            'Capability parent must be a protected root-owned real directory: ' + current);
        const parent = path.dirname(current);
        if (parent === current) return;
        current = parent;
    }
}
function fileIdentity(left, right) { return left.dev === right.dev && left.ino === right.ino; }
function readExisting(target) {
    let fd;
    try { fd = fs.openSync(target, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK); }
    catch (error) { if (error.code === 'ENOENT') return null; throw error; }
    try {
        const before = fs.fstatSync(fd);
        assert(before.isFile() && before.uid === 0 && (before.mode & 0o022) === 0,
            'Existing capability must be a protected root-owned regular file');
        assert(before.size > 0 && before.size <= 131072, 'Invalid capability artifact size');
        const bytes = fs.readFileSync(fd), after = fs.fstatSync(fd), current = fs.lstatSync(target);
        assert(!current.isSymbolicLink() && fileIdentity(before, current) && fileIdentity(before, after)
            && before.size === bytes.length && after.size === before.size && before.mtimeMs === after.mtimeMs,
        'Capability artifact changed during validation');
        const manifest = assertLanguageCapabilities(JSON.parse(bytes.toString('utf8')));
        return {sha256: crypto.createHash('sha256').update(bytes).digest('hex'), manifest};
    } finally { fs.closeSync(fd); }
}
function ensureCapabilitiesFile(target) {
    assert(typeof process.getuid === 'function' && process.getuid() === 0, 'Run capability initialization as root');
    assert(typeof target === 'string' && path.isAbsolute(target) && path.resolve(target) === target && target !== '/',
        'Pass an absolute canonical capability file');
    const directory = path.dirname(target);
    protectedParents(directory);
    const existing = readExisting(target);
    if (existing) return {result: 'preserved', path: target, sha256: existing.sha256};

    const temporary = path.join(directory, '.language-capabilities-' + crypto.randomBytes(16).toString('hex') + '.tmp');
    let fd, identity, published = false;
    try {
        // Populate/fsync privately, then link atomically and exclusively. A failed
        // write never exposes a partial JSON file and a concurrent publisher wins.
        fd = fs.openSync(temporary, fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_NOFOLLOW, 0o600);
        identity = fs.fstatSync(fd);
        assert(identity.isFile() && identity.uid === 0 && identity.nlink === 1,
            'New capability staging file is not exclusively owned by root');
        fs.writeFileSync(fd, JSON.stringify(legacyLanguageCapabilities(), null, 2) + '\n');
        fs.fchmodSync(fd, 0o644);
        fs.fsyncSync(fd);
        fs.closeSync(fd); fd = undefined;
        try { fs.linkSync(temporary, target); published = true; }
        catch (error) { if (error.code !== 'EEXIST') throw error; }
    } finally {
        if (fd !== undefined) fs.closeSync(fd);
        if (identity) {
            const current = fs.lstatSync(temporary);
            assert(!current.isSymbolicLink() && fileIdentity(identity, current), 'Staging identity changed; refusing cleanup');
            fs.unlinkSync(temporary);
        }
    }
    const installed = readExisting(target);
    assert(installed, 'Capability disappeared during publication');
    return {result: published ? 'created_legacy_pending' : 'preserved', path: target, sha256: installed.sha256};
}
function ensureCapabilities(webRoot) {
    assert(typeof webRoot === 'string' && path.isAbsolute(webRoot) && path.resolve(webRoot) === webRoot && webRoot !== '/',
        'Pass an absolute canonical Monster UI web root');
    return ensureCapabilitiesFile(path.join(webRoot, 'apps', 'acdc', 'language-capabilities.json'));
}
function ensureAppsCapabilities(configRoot) {
    assert(typeof process.getuid === 'function' && process.getuid() === 0, 'Run capability initialization as root');
    assert(typeof configRoot === 'string' && path.isAbsolute(configRoot) && path.resolve(configRoot) === configRoot && configRoot !== '/',
        'Pass an absolute canonical Kazoo configuration root');
    // Validate existing ancestors before making this one installer-owned child.
    // Never recursively mkdir or chmod an operator's existing directory.
    protectedParents(configRoot);
    const directory = path.join(configRoot, 'acdc');
    try { fs.mkdirSync(directory, {mode: 0o755}); }
    catch (error) { if (error.code !== 'EEXIST') throw error; }
    protectedParents(directory);
    return ensureCapabilitiesFile(path.join(directory, 'language-capabilities.json'));
}
module.exports = {ensureCapabilities, ensureAppsCapabilities, ensureCapabilitiesFile};
if (require.main === module) {
    try {
        assert(process.argv.length === 4 && ['--web-root', '--config-root', '--file'].includes(process.argv[2]),
            'Usage: node ensure-acdc-language-capabilities.cjs {--web-root|--config-root|--file} /absolute/path');
        const operation = {'--web-root': ensureCapabilities, '--config-root': ensureAppsCapabilities, '--file': ensureCapabilitiesFile}[process.argv[2]];
        console.log(JSON.stringify(operation(process.argv[3])));
    } catch (error) {
        console.error('Language capability initialization failed: ' + error.message);
        process.exitCode = 1;
    }
}
