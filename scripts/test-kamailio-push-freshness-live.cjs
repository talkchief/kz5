#!/usr/bin/env node
'use strict';
// Explicit opt-in only. The caller must create a new network namespace and
// bring lo up. This test never uses production configuration or AMQP services.
// Run under the coordinated guard:
// unshare --net /bin/bash -c 'ip link set lo up; exec node /opt/kz5/scripts/test-kamailio-push-freshness-live.cjs --live-isolated'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const dgram = require('node:dgram');
const crypto = require('node:crypto');
const {spawn, spawnSync} = require('node:child_process');
const {setTimeout: pause} = require('node:timers/promises');
const binary = '/usr/sbin/kamailio';
const env = {PATH: '/usr/bin:/bin', LC_ALL: 'C', TZ: 'UTC'};
const patchFile = path.join(__dirname, 'patches/kamailio-push-freshness.patch');
let fixtureRoot, child, socket, groupOwned = false, childClosed = false, childError;
let logs = '', interrupted = false;
function command(program, args) {
    const result = spawnSync(program, args, {env, encoding: 'utf8', timeout: 5000, maxBuffer: 65536});
    assert.ifError(result.error);
    assert.equal(result.status, 0, `${program} precondition failed`);
    return result.stdout;
}
function groupExists() {
    if (!groupOwned) return false;
    try { process.kill(-child.pid, 0); return true; }
    catch (error) { if (error.code === 'ESRCH') return false; throw error; }
}
function signalChild(signal) {
    if (!child?.pid) return;
    try {
        if (groupOwned) process.kill(-child.pid, signal);
        else if (!childClosed) child.kill(signal);
    } catch (error) { if (error.code !== 'ESRCH') throw error; }
}
async function cleanup() {
    if (socket) { try { socket.close(); } catch (_) {} socket = null; }
    signalChild('SIGTERM');
    for (let n = 0; n < 40 && (groupExists() || child && !childClosed); n++) await pause(50);
    if (groupExists() || child && !childClosed) signalChild('SIGKILL');
    for (let n = 0; n < 40 && (groupExists() || child && !childClosed); n++) await pause(50);
    assert(!groupExists() && (!child || childClosed), 'private Kamailio child group did not terminate');
    if (fixtureRoot) {
        assert(path.dirname(fixtureRoot) === os.tmpdir() && path.basename(fixtureRoot).startsWith('kazoo-freshness-live.'));
        fs.rmSync(fixtureRoot, {recursive: true, force: true});
        fixtureRoot = null;
    }
}
for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, () => {
    interrupted = true;
    signalChild('SIGTERM');
    if (socket) socket.close();
});

async function main() {
    assert.deepEqual(process.argv.slice(2), ['--live-isolated'], 'requires explicit --live-isolated');
    assert.notEqual(fs.readlinkSync('/proc/self/ns/net'), fs.readlinkSync('/proc/1/ns/net'),
        'refusing initial/production network namespace');
    const interfaces = JSON.parse(command('/usr/sbin/ip', ['-j', 'address', 'show']));
    assert.equal(interfaces.length, 1, 'isolated namespace must contain loopback only');
    assert.equal(interfaces[0].ifname, 'lo');
    assert(interfaces[0].flags.includes('UP'), 'caller must bring isolated lo up');
    assert(interfaces[0].addr_info.some(a => a.family === 'inet' && a.local === '127.0.0.1' && a.prefixlen === 8));
    assert(interfaces[0].addr_info.every(a => a.local === '127.0.0.1' || a.local === '::1'));
    for (const family of ['-4', '-6']) assert.equal(JSON.parse(command('/usr/sbin/ip', [family, '-j', 'route', 'show', 'default'])).length, 0);
    const elf = fs.readFileSync(binary);
    assert.equal(elf.subarray(0, 6).toString('hex'), '7f454c460201', '64-bit little-endian ELF required');
    assert.equal(elf.readUInt16LE(18), 62, 'x86-64 LP64 required');
    assert.match(command(binary, ['-v']), /kamailio 6\.1\.4\b/);

    const patch = fs.readFileSync(patchFile, 'utf8');
    const added = patch.split('\n').filter(line => line.startsWith('+') && !line.startsWith('+++')).map(line => line.slice(1));
    const arithmetic = added.filter(line => /^\s*\$var\(Push(?:CreatedSeconds|CreatedAtMs|DeadlineMs)\) =/.test(line));
    assert.deepEqual(arithmetic.map(line => line.trim()), [
        '$var(PushCreatedSeconds) = $TV(sn);',
        '$var(PushCreatedAtMs) = ($var(PushCreatedSeconds) * 1000) + ($TV(un) / 1000);',
        '$var(PushDeadlineMs) = $var(PushCreatedAtMs) + 60000;'
    ], 'execute the exact reviewed timestamp expressions, not a rewritten model');
    const payloads = added.filter(line => line.startsWith('   $var(Payload) = $_s('));
    assert.equal(payloads.length, 1);
    const payload = payloads[0];
    assert(payload.includes('"Push-Freshness" : { "version" : 1, "created_at_ms" : $var(PushCreatedAtMs), "deadline_ms" : $var(PushDeadlineMs) }'));

    // Reserve an ephemeral address within this already verified namespace.
    socket = dgram.createSocket('udp4');
    await new Promise((resolve, reject) => { socket.once('error', reject); socket.bind(0, '127.0.0.1', resolve); });
    const port = socket.address().port;
    await new Promise(resolve => socket.close(resolve)); socket = null;
    fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'kazoo-freshness-live.'));
    const config = path.join(fixtureRoot, 'kamailio.cfg');
    fs.writeFileSync(config, `#!KAMAILIO
debug=1
log_stderror=yes
auto_aliases=no
children=1
disable_tcp=yes
enable_sctp=no
listen=udp:127.0.0.1:${port}
loadmodule "pv.so"
loadmodule "sl.so"
loadmodule "textops.so"
loadmodule "cfgutils.so"
modparam("sl", "bind_tm", 0)
request_route {
    if (!is_method("OPTIONS") || $rU != "freshness-fixture") {
        sl_send_reply("403", "Fixture Only");
        exit;
    }
    $var(TokenID) = "synthetic-token";
    $var(TokenType) = "apns";
    $var(TokenApp) = "invalid.example.fixture";
    $var(from) = "synthetic-caller";
    $var(PushPayload) = "{}";
${arithmetic.join('\n')}
${payload}
    $avp(push_payload) = $var(Payload);
    append_to_reply("X-Freshness-Before: $avp(push_payload)\\r\\n");
    usleep("1200000");
    # Delayed reuse must read the saved AVP, not rebuild the payload or clock.
    append_to_reply("X-Freshness-After: $avp(push_payload)\\r\\n");
    sl_send_reply("200", "Freshness Fixture");
    exit;
}
`, {flag: 'wx', mode: 0o600});
    child = spawn(binary, ['-DD', '-E', '-f', config, '-m', '16', '-M', '4',
        '-P', path.join(fixtureRoot, 'kamailio.pid'), '-Y', fixtureRoot],
    {env, cwd: fixtureRoot, detached: true, stdio: ['ignore', 'pipe', 'pipe']});
    child.once('error', error => { childError = error; });
    child.once('close', () => { childClosed = true; });
    for (const stream of [child.stdout, child.stderr]) stream.on('data', bytes => {
        logs += bytes.toString('utf8');
        if (logs.length > 65536) { logs = logs.slice(-65536); interrupted = true; signalChild('SIGTERM'); }
    });
    assert(Number.isInteger(child.pid) && child.pid > 1);
    const stat = fs.readFileSync(`/proc/${child.pid}/stat`, 'utf8');
    const statFields = stat.slice(stat.lastIndexOf(') ') + 2).split(' ');
    assert.equal(Number(statFields[2]), child.pid, 'must own a separate process group');
    assert.equal(Number(statFields[3]), child.pid, 'must own a separate session');
    groupOwned = true;
    const localAddress = `0100007F:${port.toString(16).toUpperCase().padStart(4, '0')}`;
    const readyUntil = Date.now() + 5000;
    let ready = false;
    while (Date.now() < readyUntil) {
        assert(!interrupted && !childClosed && !childError, 'private instance stopped before ready');
        ready = fs.readFileSync('/proc/net/udp', 'utf8').split('\n').some(line => line.trim().split(/\s+/)[1] === localAddress);
        if (ready) break;
        await pause(25);
    }
    assert(ready, 'private loopback UDP listener did not become ready');
    socket = dgram.createSocket('udp4');
    await new Promise((resolve, reject) => { socket.once('error', reject); socket.bind(0, '127.0.0.1', resolve); });
    const clientPort = socket.address().port;
    const callId = `synthetic-freshness-${crypto.randomUUID()}@fixture.invalid`;
    const request = Buffer.from(`OPTIONS sip:freshness-fixture@127.0.0.1:${port} SIP/2.0\r\n`
        + `Via: SIP/2.0/UDP 127.0.0.1:${clientPort};branch=z9hG4bK-${crypto.randomUUID()};rport\r\n`
        + `From: <sip:fixture@fixture.invalid>;tag=synthetic\r\nTo: <sip:freshness-fixture@fixture.invalid>\r\n`
        + `Call-ID: ${callId}\r\nCSeq: 1 OPTIONS\r\nMax-Forwards: 1\r\nContent-Length: 0\r\n\r\n`);
    const sentAt = Date.now();
    const response = await new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error('bounded synthetic OPTIONS timeout')), 5000);
        socket.once('message', (bytes, peer) => {
            clearTimeout(timer);
            try {
                assert.equal(peer.address, '127.0.0.1'); assert.equal(peer.port, port);
                assert(bytes.length < 8192);
                resolve({text: bytes.toString('utf8'), receivedAt: Date.now()});
            } catch (error) { reject(error); }
        });
        socket.once('error', error => { clearTimeout(timer); reject(error); });
        socket.send(request, port, '127.0.0.1', error => { if (error) { clearTimeout(timer); reject(error); } });
    });
    assert(!interrupted && !childError && !childClosed, 'private child did not remain healthy');
    assert(response.text.startsWith('SIP/2.0 200 '));
    function header(name) {
        const values = response.text.split('\r\n').filter(line => line.toLowerCase().startsWith(`${name.toLowerCase()}:`));
        assert.equal(values.length, 1, 'exactly one correlated fixture header required');
        return values[0].slice(values[0].indexOf(':') + 1).trim();
    }
    assert.equal(header('Call-ID'), callId);
    assert.equal(header('CSeq'), '1 OPTIONS');
    const before = header('X-Freshness-Before'), after = header('X-Freshness-After');
    assert.equal(after, before, 'actual saved AVP bytes changed during delayed reuse');
    const body = JSON.parse(before), freshness = body['Push-Freshness'];
    assert.equal(body['Call-ID'], callId);
    assert.deepEqual(Object.keys(freshness).sort(), ['created_at_ms', 'deadline_ms', 'version']);
    assert.equal(freshness.version, 1);
    assert(Number.isSafeInteger(freshness.created_at_ms) && Number.isSafeInteger(freshness.deadline_ms));
    assert(freshness.created_at_ms > 2147483647, 'actual route result must exceed signed 32-bit');
    assert(freshness.created_at_ms >= sentAt && freshness.created_at_ms <= response.receivedAt,
        'actual created_at_ms must lie between send/receive Unix milliseconds');
    assert.equal(freshness.deadline_ms - freshness.created_at_ms, 60000);
    assert(response.receivedAt - freshness.created_at_ms >= 1100, 'actual delayed AVP reuse was not exercised');
    assert(!/ERROR:|CRITICAL:|ALERT:/.test(logs), 'private instance logged runtime errors');
    return {status: 'PASS', mode: 'isolated-synthetic-route',
        patch_sha256: crypto.createHash('sha256').update(patch).digest('hex'),
        timestamp_is_json_integer: true, timestamp_exceeds_int32: true, created_within_send_receive: true,
        deadline_delta_ms: 60000, saved_avp_bytes_unchanged: true,
        observed_delay_ms: response.receivedAt - freshness.created_at_ms,
        production_traffic: false, broker_delivery_verified: false};
}
(async () => {
    let report;
    try { report = await main(); }
    catch (error) {
        process.exitCode = 1;
        console.error(`FAIL isolated producer freshness: ${error.message}`);
        // Logs contain only generated fixtures, but do not print raw messages.
        if (logs) console.error(`Private instance diagnostics retained in memory only; bytes=${Buffer.byteLength(logs)}`);
    }
    try { await cleanup(); }
    catch (error) { process.exitCode = 1; console.error(`FAIL private cleanup: ${error.message}`); }
    if (!process.exitCode && report) console.log(JSON.stringify({...report, private_child_and_files_cleaned: true}));
})();
