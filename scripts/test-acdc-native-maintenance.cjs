#!/usr/bin/env node
'use strict';
// Opt-in finite-pause restart regression in the owned private dev44 lab.
// This is not the cluster maintenance coordinator or a complete admission fence.
const fs = require('node:fs'), cp = require('node:child_process');
const os = require('node:os'), path = require('node:path'), crypto = require('node:crypto');
const assert = require('node:assert/strict');
const ROOT = path.resolve(__dirname, '..');
const DIR = '/var/lib/kazoo5-install-lab';
const LOCK = '/etc/kazoo/monitor-acceptance.lock';
const A = '45e827067baf078029d0ca16a489fa8a';
const U = 'd757645c21f28890684a5b91fe83722d';
const Q = 'cabcfb72812b530ccc32ffba30ef680d';
function privateFile(file) {
    const s = fs.lstatSync(file);
    assert(s.isFile() && s.uid === 0 && s.nlink === 1 && (s.mode & 0o777) === 0o600);
    return s;
}
function run(args, input) {
    return cp.execFileSync('podman', args, {encoding: 'utf8', timeout: 25000,
        stdio: ['pipe', 'pipe', 'pipe'], input}).trim();
}
function owned(entry, role, ip) {
    assert(entry && typeof entry.id === 'string');
    const c = JSON.parse(run(['inspect', entry.id]))[0];
    assert.equal(c.Config.Labels['io.talkchief.kazoo.acceptance'], 'distributed-install-v1');
    assert.equal(c.Config.Labels['io.talkchief.kazoo.role'], role);
    assert.equal(c.State.Running, true);
    assert.equal(c.HostConfig.Privileged, false);
    assert.equal(c.NetworkSettings.Networks['kz5-install-stage'].IPAddress, ip);
    assert.equal(Object.keys(c.NetworkSettings.Networks).length, 1);
}
function agent(entry) {
    const d = JSON.parse(run(['exec', entry.id, 'escript',
        '/var/lib/kazoo-stage/queue-agent-rpc.escript', U]));
    assert.equal(d.present, true); assert.equal(d.state, 'ready');
    assert.equal(d.listener_consuming, true); assert.deepEqual(d.agent_queues, [Q]);
    assert(!d.member_call_id && !d.agent_call_id);
}
function assertInstalledSources(primary, peer) {
    assert(/^[a-f0-9]{40}$/.test(primary.source));
    assert.equal(primary.source, peer.source);
    assert.equal(primary.installedSource, primary.source, 'Primary source is not collected as installed');
    assert.equal(peer.installedSource, peer.source, 'Peer source is not collected as installed');
}
function execute() {
    const lockStat = privateFile(LOCK), inherited = fs.fstatSync(3);
    assert.equal(lockStat.dev, inherited.dev); assert.equal(lockStat.ino, inherited.ino);
    privateFile(DIR + '/lab.json');
    const s = JSON.parse(fs.readFileSync(DIR + '/lab.json'));
    const primary = s.roles['kazoo-apps'], peer = s.peer, media = s.roles.freeswitch, couch = s.roles.couchdb;
    owned(primary, 'kazoo-apps', '172.30.253.14');
    owned(peer, 'kazoo-apps-peer', '172.30.253.20');
    owned(media, 'freeswitch', '172.30.253.15');
    owned(couch, 'couchdb', '172.30.253.11');
    assert.equal(primary.phase, 'installed-service-verified'); assert.equal(peer.phase, 'installed');
    assertInstalledSources(primary, peer);
    assert(!fs.existsSync('/etc/kazoo/distributed-monitor-acceptance.json'), 'Other live fixture owns calls');
    assert.equal(JSON.parse(run(['exec', media.id, '/usr/local/freeswitch/bin/fs_cli',
        '-x', 'show channels as json'])).row_count, 0);
    const db = encodeURIComponent('account/' + A.slice(0,2) + '/' + A.slice(2,4) + '/' + A.slice(4));
    assert(/^[a-f0-9]+$/.test(s.secrets.couch), 'Unexpected private credential encoding');
    const config = 'url = "http://172.30.253.11:5984/' + db +
        '/_design/acdc_callbacks/_view/by_queue?reduce=false&limit=1"\nuser = "admin:' + s.secrets.couch + '"\n';
    const tickets = JSON.parse(run(['exec', '-i', couch.id, 'curl', '--fail', '--silent',
        '--show-error', '--connect-timeout', '5', '--max-time', '15', '--config', '-'], config));
    assert.deepEqual(tickets.rows, [], 'Private fixture has callback work');
    agent(primary); agent(peer);
    const source = ROOT + '/scripts/test-fixtures/distributed-lab/agent-restart-baseline.escript';
    const sha = crypto.createHash('sha256').update(fs.readFileSync(source)).digest('hex');
    const stem = DIR + '/agent-restore-' + Date.now() + '-' + crypto.randomBytes(4).toString('hex');
    const fd = fs.openSync(stem + '.log', 'wx', 0o600);
    let result;
    try {
        run(['cp', source, primary.id + ':/var/lib/kazoo-stage/agent-restart-restore.escript']);
        run(['exec', primary.id, 'chmod', '0600', '/var/lib/kazoo-stage/agent-restart-restore.escript']);
        result = cp.spawnSync('podman', ['exec', primary.id, 'escript',
            '/var/lib/kazoo-stage/agent-restart-restore.escript', '--live', '--restore'],
        {timeout: 90000, stdio: ['ignore', fd, fd]});
    } finally { fs.closeSync(fd); }
    const lines = fs.readFileSync(stem + '.log', 'utf8');
    const phases = lines.split('\n').filter(l => l.startsWith('{')).map(l => JSON.parse(l));
    let cleanupVerified = false;
    try { agent(primary); agent(peer); cleanupVerified = true; } catch (_) { /* Retain failed verification. */ }
    const after = phases.find(p => p.phase === 'after_restart');
    const pass = result.status === 0 && !result.error && cleanupVerified &&
        phases.filter(p => p.phase === 'restore_verified' && p.deadline_not_extended && p.runtime_membership_retained).length === 2 &&
        after?.pause_preserved === true && after.restore_executed === true &&
        after.states?.length === 2 && after.states.every(v => v === 'paused') &&
        !lines.includes('CLEANUP_UNVERIFIED');
    fs.writeFileSync(stem + '.json', JSON.stringify({status: pass ? 'PASS' : 'FAIL',
        native_exit: result.status, cleanup_verified: cleanupVerified, production_source: primary.source,
        fixture_sha256: sha, phases, complete_cluster_fence_proven: false,
        durable_cold_restart_proven: false}) + '\n', {mode: 0o600, flag: 'wx'});
    console.log(JSON.stringify({status: pass ? 'PASS' : 'FAIL', receipt: stem + '.json', cleanup_verified: cleanupVerified}));
    assert(pass, 'Native restore regression did not pass');
}
function main() { try {
    assert.equal(process.getuid(), 0);
    assert(Object.values(os.networkInterfaces()).flat().some(i => i.address === '10.1.0.44'));
    if (process.argv.length === 3 && process.argv[2] === '--live') {
        privateFile(LOCK);
        const fd = fs.openSync(LOCK, fs.constants.O_RDWR | fs.constants.O_NOFOLLOW);
        let child;
        try {
            const locked = cp.spawnSync('flock', ['-n', '3'], {stdio: ['ignore', 'pipe', 'pipe', fd]});
            assert(locked.status === 0 && !locked.error, 'Acceptance lock unavailable');
            child = cp.spawnSync(process.execPath, [__filename, '--locked'],
                {stdio: ['ignore', 'inherit', 'inherit', fd]});
        }
        finally { fs.closeSync(fd); }
        process.exitCode = child.status === 0 && !child.error ? 0 : 1;
    } else {
        assert.deepEqual(process.argv.slice(2), ['--locked']); execute();
    }
} catch (_) {
    // Never print subprocess input, credential-bearing configuration or raw RPC errors.
    console.error('NATIVE_MAINTENANCE_REFUSED_OR_FAILED'); process.exitCode = 1;
} }
module.exports = {assertInstalledSources};
if (require.main === module) main();
