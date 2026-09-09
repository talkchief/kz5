'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const j = require('./kazoo-maintenance-journal.cjs');
const receipt = {receipt_sha256: 'a'.repeat(64)};
const manifest = {source_from: 'b'.repeat(40), source_to: 'c'.repeat(40),
    nodes: [{name: 'kazoo_apps@apps-one', role: 'kazoo-apps', epoch: 'vm-before-1'},
        {name: 'kazoo_apps@apps-two', role: 'kazoo-apps', epoch: 'vm-before-2'}]};
const agent = {node: 'kazoo_apps@apps-one', account_id: '1'.repeat(32), agent_id: '2'.repeat(32),
    state: 'paused', pause_until_unix_ms: Date.now() + 45000, queues: ['3'.repeat(32)]};
const checkpoint = {agents: [agent], drain_receipt_sha256: 'd'.repeat(64)};
function fixture(t) {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'kazoo-maintenance-journal-test-'));
    fs.chmodSync(root, 0o700);
    t.after(() => {
        assert(path.basename(root).startsWith('kazoo-maintenance-journal-test-'));
        fs.rmSync(root, {recursive: true});
    });
    return {root, generation: j.create(root, manifest)};
}
function toRestoring(f) {
    j.advance(f.root, f.generation, 0, 'fenced', receipt);
    j.advance(f.root, f.generation, 1, 'checkpointed', checkpoint);
    j.advance(f.root, f.generation, 2, 'activating', receipt);
    j.advance(f.root, f.generation, 3, 'restoring', receipt);
}
test('durable forward lifecycle retains absolute deadline, refuses stale replay', t => {
    const f = fixture(t); toRestoring(f);
    assert.deepEqual(j.restoreCheckpoint(f.root, f.generation, 4), checkpoint);
    assert.throws(() => j.restoreCheckpoint(f.root, f.generation, 3));
    j.advance(f.root, f.generation, 4, 'verified', receipt);
    j.advance(f.root, f.generation, 5, 'reopening', receipt);
    assert.throws(() => j.restoreCheckpoint(f.root, f.generation, 6));
    j.advance(f.root, f.generation, 6, 'completed', receipt);
    assert.throws(() => j.advance(f.root, f.generation, 7, 'restoring', receipt));
    assert.throws(() => j.restoreCheckpoint(f.root, f.generation, 7));
    assert.equal(j.read(f.root, f.generation).record.phase, 'completed');
});
test('rollback uses the same pre-admission checkpoint and needs separate verification', t => {
    const f = fixture(t); toRestoring(f);
    j.advance(f.root, f.generation, 4, 'rolling_back', receipt);
    assert.throws(() => j.restoreCheckpoint(f.root, f.generation, 5));
    j.advance(f.root, f.generation, 5, 'restoring_rollback', receipt);
    assert.deepEqual(j.restoreCheckpoint(f.root, f.generation, 6), checkpoint);
    assert.throws(() => j.advance(f.root, f.generation, 6, 'reopening', receipt));
    j.advance(f.root, f.generation, 6, 'verified_rollback', receipt);
    j.advance(f.root, f.generation, 7, 'reopening', receipt);
    j.advance(f.root, f.generation, 8, 'completed', receipt);
});
test('reject phase skipping, duplicate writers and caller-supplied extra fields', t => {
    const f = fixture(t);
    assert.throws(() => j.advance(f.root, f.generation, 0, 'restoring', receipt));
    assert.throws(() => j.advance(f.root, f.generation, 0, 'fenced', {...receipt, auth_token: 'forbidden'}));
    j.advance(f.root, f.generation, 0, 'fenced', receipt);
    assert.throws(() => j.advance(f.root, f.generation, 0, 'fenced', receipt));
    assert.equal(j.read(f.root, f.generation).record.revision, 1);
});
test('truncated or missing latest revision cannot fall back to an earlier state', t => {
    const f = fixture(t);
    fs.writeFileSync(path.join(f.root, f.generation, '0001.json'), '{', {mode: 0o600, flag: 'wx'});
    assert.throws(() => j.read(f.root, f.generation));
    assert.throws(() => j.advance(f.root, f.generation, 0, 'fenced', receipt));
});
test('hash chain detects tampered earlier receipt', t => {
    const f = fixture(t); toRestoring(f);
    const file = path.join(f.root, f.generation, '0001.json');
    const value = JSON.parse(fs.readFileSync(file)); value.payload.receipt_sha256 = 'e'.repeat(64);
    fs.writeFileSync(file, JSON.stringify(value) + '\n');
    assert.throws(() => j.read(f.root, f.generation), /chain mismatch/);
});
test('refuse permissive, symlinked or hardlinked revision files', t => {
    const f = fixture(t), file = path.join(f.root, f.generation, '0000.json');
    fs.chmodSync(file, 0o644); assert.throws(() => j.read(f.root, f.generation));
    fs.chmodSync(file, 0o600);
    const alias = path.join(f.root, 'alias'); fs.linkSync(file, alias);
    assert.throws(() => j.read(f.root, f.generation)); fs.unlinkSync(alias);
    fs.renameSync(file, alias); fs.symlinkSync(alias, file);
    assert.throws(() => j.read(f.root, f.generation));
});
test('refuse unsafe parent, path traversal, gaps and extra files', t => {
    const f = fixture(t);
    assert.throws(() => j.read(f.root, '../anything'));
    fs.chmodSync(f.root, 0o755); assert.throws(() => j.read(f.root, f.generation));
    fs.chmodSync(f.root, 0o700);
    fs.writeFileSync(path.join(f.root, f.generation, '0002.json'), '{}', {mode: 0o600});
    assert.throws(() => j.read(f.root, f.generation), /Missing or foreign/);
});
test('validate identities, empty membership, finite/infinite pauses and replica scope', () => {
    j.validateAgents([agent, {...agent, node: 'kazoo_apps@apps-two', queues: [], pause_until_unix_ms: 'infinity'}], manifest);
    j.validateAgents([{...agent, state: 'ready', pause_until_unix_ms: 0}], manifest);
    for (const extra of [{state: 'answered'}, {pause_until_unix_ms: -1}, {pause_until_unix_ms: 2 ** 54},
        {state: 'ready'}, {queues: ['3'.repeat(32), '3'.repeat(32)]}, {queues: ['bad']},
        {node: 'foreign'}, {agent_id: 'bad'}, {password: 'forbidden'}]) {
        assert.throws(() => j.validateAgents([{...agent, ...extra}], manifest));
    }
    assert.throws(() => j.validateAgents([agent, agent], manifest));
    assert.throws(() => j.validateManifest({...manifest, nodes: [...manifest.nodes, manifest.nodes[0]]}));
});
