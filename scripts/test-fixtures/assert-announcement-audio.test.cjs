'use strict';
const assert = require('node:assert/strict'), {spawnSync} = require('node:child_process');
const {inspect} = require('./assert-announcement-audio.cjs');
const wav = require('node:path').resolve(__dirname, '../assets/acdc-callback-prompts/en-us/acdc-queue-your-current-position-is.wav');
const converted = spawnSync('sox', [wav, '-t', 'raw', '-r', '8000', '-c', '1', '-e', 'mu-law', '-']);
assert.equal(converted.status, 0); const reference = converted.stdout;
const call = '1-999@127.0.0.20';
function capture(first = 30, second = 60, corrupt = false) {
    const header = Buffer.alloc(24); header.writeUInt32LE(0xa1b2c3d4); header.writeUInt16LE(2, 4); header.writeUInt16LE(4, 6);
    header.writeUInt32LE(65535, 16); header.writeUInt32LE(1, 20); const records = [header];
    function udp(time, payload, port) {
        const packet = Buffer.alloc(42 + payload.length); packet.writeUInt16BE(0x0800, 12); packet[14] = 0x45;
        packet.writeUInt16BE(28 + payload.length, 16); packet[23] = 17;
        Buffer.from([127, 0, 0, 1]).copy(packet, 26); Buffer.from([127, 0, 0, 20]).copy(packet, 30);
        packet.writeUInt16BE(30000, 34); packet.writeUInt16BE(port, 36); packet.writeUInt16BE(payload.length + 8, 38);
        payload.copy(packet, 42); const record = Buffer.alloc(16);
        record.writeUInt32LE(Math.floor(time), 0); record.writeUInt32LE(Math.round((time % 1) * 1e6), 4);
        record.writeUInt32LE(packet.length, 8); record.writeUInt32LE(packet.length, 12); records.push(record, packet);
    }
    udp(100, Buffer.from(`SIP/2.0 200 OK\r\nCall-ID: ${call}\r\nCSeq: 1 INVITE\r\n\r\n`), 15064);
    const audio = Buffer.alloc(75 * 8000, 255); reference.copy(audio, first * 8000); reference.copy(audio, second * 8000);
    if (corrupt) audio.fill(255, first * 8000 + reference.length / 2, first * 8000 + reference.length);
    for (let offset = 0; offset < audio.length; offset += 160) {
        const rtp = Buffer.alloc(172); rtp[0] = 128; rtp.writeUInt16BE(offset / 160, 2); rtp.writeUInt32BE(offset, 4);
        rtp.writeUInt32BE(123, 8); audio.copy(rtp, 12, offset, offset + 160); udp(100 + offset / 8000, rtp, 47000);
    }
    udp(175, Buffer.from(`BYE sip:test SIP/2.0\r\nCall-ID: ${call}\r\nCSeq: 3 BYE\r\n\r\n`), 15064);
    return Buffer.concat(records);
}
const valid = capture(), result = inspect(valid, reference, call, '127.0.0.20', 47000);
assert.equal(result.full_prefix_matches.length, 2); assert.equal(result.repeat_spacing_seconds, 30);
assert.throws(() => inspect(capture(0, 60), reference, call, '127.0.0.20', 47000), /delayed30seconds/);
assert.throws(() => inspect(capture(30, 55), reference, call, '127.0.0.20', 47000), /repeat spacing/);
assert.throws(() => inspect(capture(30, 60, true), reference, call, '127.0.0.20', 47000), /complete audible prefixes/);
assert.throws(() => inspect(valid, reference, 'wrong-call', '127.0.0.20', 47000), /exact caller/);
assert.throws(() => inspect(valid.subarray(0, valid.length - 1), reference, call, '127.0.0.20', 47000), /Truncated/);
console.log('PASS6 announcement audio gates: full received prefix, delayed/repeat timing, truncated phrase, exact call scope and truncated capture');
