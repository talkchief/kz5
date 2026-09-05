#!/usr/bin/env node
'use strict';
// Exercise the actual shell capture filter against synthetic in-memory pcap.
// No sockets, credentials, API requests, or real packet capture are used.
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const assert = require('node:assert/strict');
const source = fs.readFileSync(path.join(__dirname, 'test-acdc-callback-calls.sh'), 'utf8');
const definition = source.match(/^callback_capture_filter\(\) \{\n[\s\S]*?^\}/m);
assert(definition, 'Capture filter function missing');
function filter(local = '127.0.0.20') {
    return cp.spawnSync('bash', ['-c', `set -Eeuo pipefail
die() { exit 1; }
LOCAL_IP=$1
CARRIER_IP=127.0.0.30
CALLBACK_ORIGINAL_MEDIA_PORT=43000
SENTINEL_MEDIA_PORT=43010
AGENT_MEDIA_MIN=40000
AGENT_CONTACT_PORT_BASE=15100
CARRIER_MEDIA_PORT=44000
CARRIER_PORT=16060
${definition[0]}
callback_capture_filter`, 'callback-capture-test', local], {encoding: 'utf8'});
}
const actual = filter();
assert.equal(actual.status, 0);
assert.notEqual(filter('192.0.2.10').status, 0, 'Nonlocal capture must fail closed');
const cases = [];
for (const port of [43000, 43010, 40000]) {
    cases.push(['127.0.0.20', port, '192.0.2.1', 18000, true]);
    cases.push(['192.0.2.1', 18000, '127.0.0.20', port, true]);
}
cases.push(['192.0.2.1', 5060, '127.0.0.20', 15100, true]);
cases.push(['127.0.0.30', 44000, '192.0.2.1', 18000, true]);
cases.push(['192.0.2.1', 18000, '127.0.0.30', 44000, true]);
cases.push(['192.0.2.1', 5060, '127.0.0.30', 16060, true]);
cases.push(['127.0.0.30', 16060, '192.0.2.1', 5060, true]);
// Shared port numbers on real phones and unrelated fixture ports are excluded.
for (const port of [40000, 42000, 43000, 43010, 44000, 44998, 15100]) {
    cases.push(['192.0.2.2', port, '192.0.2.1', port, false]);
    cases.push(['127.0.0.40', port, '192.0.2.1', port, false]);
}
cases.push(['127.0.0.20', 42000, '192.0.2.1', 18000, false]);
cases.push(['127.0.0.30', 43000, '192.0.2.1', 18000, false]);
cases.push(['127.0.0.20', 15100, '192.0.2.1', 5060, false]);
const header = Buffer.alloc(24);
header.writeUInt32LE(0xa1b2c3d4); header.writeUInt16LE(2, 4); header.writeUInt16LE(4, 6);
header.writeUInt32LE(65535, 16); header.writeUInt32LE(1, 20);
for (const [src, sport, dst, dport, expected] of cases) {
    const packet = Buffer.alloc(42);
    packet.writeUInt16BE(0x0800, 12); packet[14] = 0x45;
    packet.writeUInt16BE(28, 16); packet[22] = 64; packet[23] = 17;
    Buffer.from(src.split('.').map(Number)).copy(packet, 26);
    Buffer.from(dst.split('.').map(Number)).copy(packet, 30);
    packet.writeUInt16BE(sport, 34); packet.writeUInt16BE(dport, 36); packet.writeUInt16BE(8, 38);
    const record = Buffer.alloc(16);
    record.writeUInt32LE(1); record.writeUInt32LE(packet.length, 8); record.writeUInt32LE(packet.length, 12);
    const result = cp.spawnSync('tcpdump', ['-nn', '-r', '-', actual.stdout.trim()], {
        input: Buffer.concat([header, record, packet]), encoding: 'utf8'
    });
    assert.equal(result.status, 0, 'Offline filter rejected synthetic pcap');
    assert.equal(result.stdout.trim().length > 0, expected, `Unexpected capture: ${src}:${sport} -> ${dst}:${dport}`);
}
console.log(`PASS: ${cases.length} callback capture inclusion/exclusion cases; nonlocal source rejected`);
