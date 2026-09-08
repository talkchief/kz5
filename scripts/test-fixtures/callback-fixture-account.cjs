'use strict';
// Explicit acceptance identity, never inferred from a live caller or receipt.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const LEGACY = '7807ad61761269a1ccec833dde63f621';
const forbidden = new Set(['302ae5a70c403124f764cbc54229cfcd',
    'adecbb84fbe9e06902a76731914d1943', 'd8520ce3f29c5b6db692289e782c92af']);
function selectedAccount(env = process.env) {
    const id = env.KAZOO_CALLBACK_TEST_ACCOUNT_ID === undefined ? LEGACY : env.KAZOO_CALLBACK_TEST_ACCOUNT_ID;
    assert(typeof id === 'string' && /^[a-f0-9]{32}$/.test(id) && !forbidden.has(id),
        'Invalid or forbidden callback acceptance account');
    return id;
}
function validateState(state, selected = selectedAccount()) {
    assert.equal(state.ACCEPTANCE_ACCOUNT_ID, selectedAccount({KAZOO_CALLBACK_TEST_ACCOUNT_ID:selected}),
        'Selected callback account differs from protected state');
    assert(/^Kazoo5 Acceptance [a-f0-9]{12}$/.test(state.ACCEPTANCE_ACCOUNT_NAME));
    assert.equal(state.ACCEPTANCE_REALM, 'acceptance-' + state.ACCEPTANCE_ACCOUNT_NAME.slice(-12) + '.invalid');
    assert.equal(state.ACCEPTANCE_CALLER_EXTENSION, '1001');
    assert.equal(state.ACCEPTANCE_CALLER_SIP_USERNAME, 'acceptance1001');
    assert.equal(state.ACCEPTANCE_QUEUE_EXTENSION, '2000');
    for (const key of ['ACCEPTANCE_QUEUE_ID', 'ACCEPTANCE_QUEUE_CALLFLOW_ID'])
        assert(/^[a-f0-9]{32}$/.test(state[key]), 'Missing owned queue identity');
    return selected;
}
function readState(file) {
    assert.equal(file, '/etc/kazoo/acceptance-secrets.env', 'Only canonical acceptance state is allowed');
    const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
    try {
        const st = fs.fstatSync(fd);
        assert(st.isFile() && st.uid === 0 && st.nlink === 1 && (st.mode & 0o777) === 0o600 && st.size < 65536);
        const state = require('../test-channel-monitor-live.cjs').baseState(fs.readFileSync(fd, 'utf8'));
        validateState(state);
        return state;
    } finally {fs.closeSync(fd);}
}
function ensureLock(file = '/etc/kazoo/monitor-acceptance.lock') {
    assert.equal(process.getuid(), 0, 'Acceptance lock requires root');
    const parent = fs.lstatSync(path.dirname(file));
    assert(parent.isDirectory() && !parent.isSymbolicLink() && parent.uid === 0 && !(parent.mode & 0o022));
    try {fs.closeSync(fs.openSync(file, 'wx', 0o600));}
    catch (error) {if (error.code !== 'EEXIST') throw error;}
    const fd = fs.openSync(file, fs.constants.O_RDWR | fs.constants.O_NOFOLLOW);
    try {
        const st = fs.fstatSync(fd);
        assert(st.isFile() && st.uid === 0 && st.nlink === 1 && (st.mode & 0o777) === 0o600);
    } finally {fs.closeSync(fd);}
}
module.exports = {LEGACY, selectedAccount, validateState, readState, ensureLock};
if (require.main === module) {
    try {
        assert.equal(process.argv.length, 3);
        if (process.argv[2] === '--ensure-lock') {
            readState('/etc/kazoo/acceptance-secrets.env');
            ensureLock();
            console.log('PASS protected acceptance lock ready; existing inode/content preserved');
        } else {
            readState(process.argv[2]);
            console.log('PASS explicit callback account matches protected isolated state; no writes');
        }
    } catch (_) {console.error('Callback acceptance identity refused; private state withheld');process.exitCode = 1;}
}
