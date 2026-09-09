'use strict';
// Durable coordinator journal, NOT an admission fence or an upgrade executor.
// Append-only revisions make interrupted writes fail closed. The coordinator
// must prove the real cluster fence/drain before recording those phases.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const transitions = Object.freeze({
    created: ['fenced'],
    fenced: ['checkpointed'],
    checkpointed: ['activating'],
    activating: ['restoring', 'rolling_back'],
    restoring: ['verified', 'rolling_back'],
    rolling_back: ['restoring_rollback'],
    restoring_rollback: ['verified_rollback'],
    verified: ['reopening'],
    verified_rollback: ['reopening'],
    reopening: ['completed'],
    completed: []
});
const digest = value => crypto.createHash('sha256').update(value).digest('hex');
const exact = (value, keys) => {
    assert(value && typeof value === 'object' && !Array.isArray(value), 'Object required');
    assert.deepEqual(Object.keys(value).sort(), keys.slice().sort(), 'Unexpected journal fields');
};
const hex = (value, length) => assert(typeof value === 'string' &&
    new RegExp('^[a-f0-9]{' + length + '}$').test(value), 'Invalid identifier');
function directory(dir) {
    assert.equal(path.resolve(dir), fs.realpathSync(dir), 'Symlinked journal path');
    const stat = fs.lstatSync(dir);
    assert(stat.isDirectory() && stat.uid === process.getuid() &&
        (stat.mode & 0o777) === 0o700, 'Private owned directory required');
}
function syncDirectory(dir) {
    const fd = fs.openSync(dir, fs.constants.O_RDONLY | fs.constants.O_DIRECTORY | fs.constants.O_NOFOLLOW);
    try { fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
}
function validateManifest(m) {
    exact(m, ['source_from', 'source_to', 'nodes']);
    hex(m.source_from, 40); hex(m.source_to, 40);
    assert(Array.isArray(m.nodes) && m.nodes.length > 0 && m.nodes.length <= 256, 'Invalid node inventory');
    const names = new Set();
    for (const n of m.nodes) {
        exact(n, ['name', 'role', 'epoch']);
        assert(typeof n.name === 'string' && /^[A-Za-z0-9_.@:-]{1,253}$/.test(n.name));
        assert(['kazoo-apps', 'ecallmgr', 'freeswitch', 'kamailio', 'rabbitmq', 'haproxy', 'monster-ui'].includes(n.role));
        assert(typeof n.epoch === 'string' && /^[A-Za-z0-9_.:-]{1,128}$/.test(n.epoch));
        assert(!names.has(n.name), 'Duplicate node'); names.add(n.name);
    }
    assert(m.nodes.some(n => n.role === 'kazoo-apps'), 'Missing applications inventory');
}
function validateAgents(agents, manifest) {
    assert(Array.isArray(agents) && agents.length <= 100000, 'Invalid agent inventory');
    const nodes = new Set(manifest.nodes.filter(n => n.role === 'kazoo-apps').map(n => n.name));
    const identities = new Set();
    for (const a of agents) {
        exact(a, ['node', 'account_id', 'agent_id', 'state', 'pause_until_unix_ms', 'queues']);
        assert(nodes.has(a.node), 'Agent node absent from manifest');
        hex(a.account_id, 32); hex(a.agent_id, 32);
        const identity = [a.node, a.account_id, a.agent_id].join('/');
        assert(!identities.has(identity), 'Duplicate agent replica'); identities.add(identity);
        assert(['ready', 'paused'].includes(a.state), 'Undrained agent');
        assert(a.state === 'ready' ? a.pause_until_unix_ms === 0 :
            a.pause_until_unix_ms === 'infinity' ||
            (Number.isSafeInteger(a.pause_until_unix_ms) && a.pause_until_unix_ms > 0), 'Invalid pause deadline');
        assert(Array.isArray(a.queues) && a.queues.length <= 10000, 'Invalid runtime queues');
        a.queues.forEach(q => hex(q, 32));
        assert.equal(new Set(a.queues).size, a.queues.length, 'Duplicate queue');
    }
}
function validatePayload(phase, payload, manifest) {
    if (phase === 'created') return validateManifest(payload);
    if (phase === 'checkpointed') {
        exact(payload, ['agents', 'drain_receipt_sha256']);
        validateAgents(payload.agents, manifest); hex(payload.drain_receipt_sha256, 64);
    } else {
        // The receipt digest identifies independently retained real probe/action
        // evidence. Supplying a digest does not establish the fence by itself.
        exact(payload, ['receipt_sha256']); hex(payload.receipt_sha256, 64);
    }
}
function append(dir, record) {
    directory(dir);
    const filename = path.join(dir, String(record.revision).padStart(4, '0') + '.json');
    const bytes = Buffer.from(JSON.stringify(record) + '\n');
    assert(bytes.length <= 32 * 1024 * 1024, 'Journal record too large');
    const fd = fs.openSync(filename, fs.constants.O_WRONLY | fs.constants.O_CREAT |
        fs.constants.O_EXCL | fs.constants.O_NOFOLLOW, 0o600);
    // Never remove a partial revision after an error. Recovery must inspect it,
    // not silently fall back to a stale checkpoint or repeat an uncertain action.
    try { fs.writeFileSync(fd, bytes); fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
    syncDirectory(dir);
    return {record, sha256: digest(bytes)};
}
function create(root, manifest) {
    directory(root); validateManifest(manifest);
    const generation = crypto.randomBytes(16).toString('hex');
    const dir = path.join(root, generation);
    fs.mkdirSync(dir, {mode: 0o700}); syncDirectory(root);
    append(dir, {version: 1, generation, revision: 0, phase: 'created',
        previous_sha256: null, timestamp_unix_ms: Date.now(), payload: manifest});
    return generation;
}
function read(root, generation) {
    directory(root); hex(generation, 32);
    const dir = path.join(root, generation); directory(dir);
    const names = fs.readdirSync(dir).sort();
    assert(names.length > 0 && names.length <= 32, 'Invalid journal revision inventory');
    let previous, manifest, checkpoint;
    names.forEach((name, revision) => {
        assert.equal(name, String(revision).padStart(4, '0') + '.json', 'Missing or foreign journal revision');
        const fd = fs.openSync(path.join(dir, name), fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
        let bytes;
        try {
            const stat = fs.fstatSync(fd);
            assert(stat.isFile() && stat.uid === process.getuid() && stat.nlink === 1 &&
                (stat.mode & 0o777) === 0o600 && stat.size > 0 && stat.size <= 32 * 1024 * 1024,
            'Unsafe journal revision');
            bytes = fs.readFileSync(fd);
        } finally { fs.closeSync(fd); }
        const r = JSON.parse(bytes);
        exact(r, ['version', 'generation', 'revision', 'phase', 'previous_sha256', 'timestamp_unix_ms', 'payload']);
        assert.equal(r.version, 1); assert.equal(r.generation, generation); assert.equal(r.revision, revision);
        assert(Number.isSafeInteger(r.timestamp_unix_ms) && r.timestamp_unix_ms > 0);
        if (!previous) {
            assert.equal(r.phase, 'created'); assert.equal(r.previous_sha256, null); manifest = r.payload;
        } else {
            assert.equal(r.previous_sha256, previous.sha256, 'Journal chain mismatch');
            assert(transitions[previous.record.phase]?.includes(r.phase), 'Invalid maintenance transition');
        }
        validatePayload(r.phase, r.payload, manifest);
        if (r.phase === 'checkpointed') checkpoint = r.payload;
        previous = {record: r, sha256: digest(bytes)};
    });
    return {...previous, manifest, checkpoint};
}
function advance(root, generation, expectedRevision, phase, payload) {
    const current = read(root, generation);
    assert.equal(current.record.revision, expectedRevision, 'Stale maintenance revision');
    assert(transitions[current.record.phase]?.includes(phase), 'Invalid maintenance transition');
    validatePayload(phase, payload, current.manifest);
    return append(path.join(root, generation), {version: 1, generation, revision: expectedRevision + 1,
        phase, previous_sha256: current.sha256, timestamp_unix_ms: Date.now(), payload});
}
function restoreCheckpoint(root, generation, expectedRevision) {
    const current = read(root, generation);
    assert.equal(current.record.revision, expectedRevision, 'Stale maintenance revision');
    assert(['restoring', 'restoring_rollback'].includes(current.record.phase),
        'Restoration not permitted in current maintenance phase');
    assert(current.checkpoint, 'Missing checkpoint');
    return current.checkpoint;
}
module.exports = {create, read, advance, restoreCheckpoint, validateManifest, validateAgents};
