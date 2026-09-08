#!/usr/bin/env node
'use strict';

// Git protocol output is deliberately secret-bearing. Invoke through Git, never
// directly in a terminal/log collector. Only this repository may request it.
const fs = require('node:fs');
const path = require('node:path');
const TOKEN_FILE = '/root/.config/kz5/github.token';
const TOKEN_PATTERN = /^(?:ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})$/;

function requestAllowed(input) {
    if (Buffer.byteLength(input) > 4096 || /[\r\0]/.test(input)) return false;
    const fields = Object.create(null);
    let ended = false;
    for (const line of input.split('\n')) {
        if (!line) { ended = true; continue; }
        if (ended) return false;
        const match = /^([^=]+)=(.*)$/.exec(line);
        if (!match || Object.hasOwn(fields, match[1])) return false;
        fields[match[1]] = match[2];
    }
    return fields.protocol === 'https' && fields.host === 'github.com' &&
        ['talkchief/kz5', 'talkchief/kz5.git'].includes(fields.path) &&
        (!Object.hasOwn(fields, 'username') || fields.username === 'x-access-token') &&
        Object.keys(fields).every(key => ['protocol', 'host', 'path', 'username'].includes(key));
}

function protectedDirectory(directory) {
    const stat = fs.lstatSync(directory);
    if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== 0 || (stat.mode & 0o022)) {
        throw new Error('Unsafe credential directory');
    }
}

function validateParents(file) {
    let directory = path.dirname(file);
    while (true) {
        protectedDirectory(directory);
        if (directory === '/') break;
        directory = path.dirname(directory);
    }
}

function readToken(file = TOKEN_FILE) {
    validateParents(file);
    const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
    try {
        const stat = fs.fstatSync(fd);
        if (!stat.isFile() || stat.uid !== 0 || stat.nlink !== 1 ||
                (stat.mode & 0o777) !== 0o600 || stat.size > 512) {
            throw new Error('Unsafe credential file');
        }
        const bytes = fs.readFileSync(fd);
        try {
            const token = bytes.toString('utf8').replace(/\n$/, '');
            if (!TOKEN_PATTERN.test(token)) throw new Error('Invalid credential');
            return token;
        } finally { bytes.fill(0); }
    } finally { fs.closeSync(fd); }
}

function provisionToken(input, file = TOKEN_FILE) {
    if (process.getuid() !== 0 || !Buffer.isBuffer(input) || input.length > 512) {
        throw new Error('Invalid provisioning request');
    }
    const token = input.toString('utf8').replace(/\n$/, '');
    if (!TOKEN_PATTERN.test(token)) throw new Error('Invalid credential');
    // Check each ancestor before creating the next component. Never follow an
    // existing symlink, replace a file, or relax a directory's permissions.
    const directories = [];
    let directory = path.dirname(file);
    while (directory !== '/') { directories.unshift(directory); directory = path.dirname(directory); }
    protectedDirectory('/');
    for (directory of directories) {
        try { protectedDirectory(directory); }
        catch (error) {
            if (error.code !== 'ENOENT') throw error;
            fs.mkdirSync(directory, { mode: 0o700 });
            protectedDirectory(directory);
        }
    }
    try {
        const fd = fs.openSync(file, fs.constants.O_WRONLY | fs.constants.O_CREAT |
            fs.constants.O_EXCL | fs.constants.O_NOFOLLOW, 0o600);
        try { fs.writeFileSync(fd, token + '\n'); fs.fsyncSync(fd); }
        finally { fs.closeSync(fd); }
    } catch (error) {
        if (error.code !== 'EEXIST' || readToken(file) !== token) throw error;
    }
    if (readToken(file) !== token) throw new Error('Credential readback failed');
}

async function main() {
    const operation = process.argv[2];
    if (process.argv.length !== 3) throw new Error('Invalid operation');
    // Do not accept credentials supplied by another helper or clear protected
    // storage on Git's erase request. Rotation is an explicit operator action.
    if (operation === 'store' || operation === 'erase') return;
    if (!['get', '--provision-stdin'].includes(operation)) throw new Error('Invalid operation');
    const chunks = [];
    let size = 0;
    for await (const chunk of process.stdin) {
        size += chunk.length;
        if (size > (operation === 'get' ? 4096 : 512)) throw new Error('Oversized input');
        chunks.push(chunk);
    }
    const input = Buffer.concat(chunks);
    try {
        if (operation === '--provision-stdin') { provisionToken(input); return; }
        if (!requestAllowed(input.toString('utf8'))) return;
        const token = readToken();
        process.stdout.write('username=x-access-token\npassword=' + token + '\n\n');
    } finally { input.fill(0); chunks.forEach(chunk => chunk.fill(0)); }
}

module.exports = { requestAllowed, readToken, provisionToken };
if (require.main === module) main().catch(() => {
    // Never include input, paths from protocol requests, tokens or exceptions.
    process.stderr.write('kz5 Git credential operation refused\n');
    process.exitCode = 1;
});
