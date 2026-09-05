'use strict';
// Local files/process mocks only; no network, credentials, or SIP traffic.
const fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const assert = require('node:assert/strict'), cp = require('node:child_process');
const {buildScenario, createFiles} = require('./callback-offer-scenario.cjs');
const root = path.resolve(__dirname, '..', '..');
const sourcePath = path.join(root, 'scripts/sip-tests/caller-to-queue.xml');
const source = fs.readFileSync(sourcePath, 'utf8');
const xml = buildScenario(source, '/tmp/protected-offer/offer-silence.ulaw');
assert(xml.includes('offer-silence.ulaw,-1,0,PCMU/8000'));
assert(xml.includes('<pause variable="hold_ms"/>'));
assert(xml.includes('<recv response="200" response_txn="bye"/>'));
assert(!xml.includes('apattern'));
for (const before of ['<exec rtp_stream="apattern,1,0,PCMU/8000"/>', '<exec rtp_stream="pauseapattern"/>']) {
    assert.throws(() => buildScenario(source.replace(before, ''), '/tmp/a'));
    assert.throws(() => buildScenario(source + before, '/tmp/a'));
}
for (const unsafe of ['relative', '/tmp/with,comma', '/tmp/with"quote', '/tmp/with\nnewline']) {
    assert.throws(() => buildScenario(source, unsafe));
}
const run = fs.mkdtempSync(path.join(os.tmpdir(), 'acdc-offer-scenario-test-'));
try {
    fs.chmodSync(run, 0o700);
    createFiles(run, sourcePath);
    const media = fs.readFileSync(path.join(run, 'offer-silence.ulaw'));
    assert.equal(media.length, 8000); assert(media.every(value => value === 255));
    for (const name of ['offer-silence.ulaw', 'offer-caller.xml']) assert.equal(fs.statSync(path.join(run, name)).mode & 511, 0o600);
    assert.throws(() => createFiles(run, sourcePath), /Never overwrite/);
    fs.chmodSync(run, 0o755); assert.throws(() => createFiles(run, sourcePath), /private root-owned/); fs.chmodSync(run, 0o700);
    const harness = fs.readFileSync(path.join(root, 'scripts/test-acdc-callback-offer-calls.sh'), 'utf8');
    assert(harness.includes('-sf "$RUN_DIR/offer-caller.xml"'));
    assert(harness.includes('--immediate-mode -U'));
    assert(harness.includes('wait "$CALLER_PID" || caller_exit=$?'));
    assert(harness.includes('((caller_exit==0)) || die'));
    assert(!harness.includes('-audiotolerance'));
    const stop = harness.match(/^offer_stop_capture\(\) \{[\s\S]*?^\}/m)?.[0];
    assert(stop, 'Actual capture-stop function missing');
    // Execute the actual shell function with mocked process control: both normal
    // and cleanup paths use it, and drainage must precede capture termination.
    fs.writeFileSync(path.join(run, 'offer-rtp.pcap'), '', {mode: 0o600});
    const result = cp.spawnSync('bash', ['-c', [
        'set -Eeuo pipefail', 'RUN_DIR=$1; offer_capture_pid=12345',
        'kill() { printf "kill:%s\\n" "$1"; }',
        'sleep() { printf "sleep:%s\\n" "$1"; }',
        'wait() { printf "wait:%s\\n" "$1"; }',
        stop, 'offer_stop_capture', '[[ -z $offer_capture_pid ]]'
    ].join('\n'), 'test', run], {encoding: 'utf8'});
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, 'kill:-0\nsleep:2\nkill:-INT\nwait:12345\n');
    assert.equal(fs.readFileSync(sourcePath, 'utf8'), source, 'Shared echo/stress scenario changed');
    console.log('PASS isolated file-mode scenario, strict exit gate, private evidence and failure capture-drain tests; no traffic');
} finally { fs.rmSync(run, {recursive: true, force: true}); }
