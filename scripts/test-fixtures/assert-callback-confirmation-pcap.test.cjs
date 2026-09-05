'use strict';
const assert = require('node:assert/strict');
const {inspect} = require('./assert-callback-confirmation-pcap.cjs');

function packet({digit = 1, invite = false, address = [127, 0, 0, 30], port = 44000, fragment = false}, link) {
    const size = link === 1 ? 14 : link === 113 ? 16 : 20;
    const header = Buffer.alloc(size + 28);
    header.writeUInt16BE(0x0800, link === 1 ? 12 : link === 113 ? 14 : 0);
    header[size] = 0x45; header[size + 9] = 17;
    header.writeUInt16BE(fragment ? 0x2000 : 0, size + 6);
    Buffer.from(address).copy(header, size + 12);
    header.writeUInt16BE(invite ? 5060 : port, size + 20);
    header.writeUInt16BE(invite ? 15100 : 16000, size + 22);
    const payload = invite ? Buffer.from('INVITE sip:agent@127.0.0.20 SIP/2.0\r\n') : Buffer.from([128, 96, 0, 1, 0, 0, 0, 1, 0, 0, 0, 2, digit, 10, 0, 160]);
    header.writeUInt16BE(payload.length + 8, size + 24);
    header.writeUInt16BE(payload.length + 28, size + 2);
    return Buffer.concat([header, payload]);
}

function capture(records, link = 276, little = true) {
    const header = Buffer.alloc(24);
    Buffer.from(little ? 'd4c3b2a1' : 'a1b2c3d4', 'hex').copy(header);
    const write = (buffer, value, offset) => little ? buffer.writeUInt32LE(value, offset) : buffer.writeUInt32BE(value, offset);
    write(header, link, 20);
    return Buffer.concat([header, ...records.map(([time, settings]) => {
        const data = packet(settings, link);
        const record = Buffer.alloc(16);
        write(record, time, 0); write(record, data.length, 8); write(record, data.length, 12);
        return Buffer.concat([record, data]);
    })]);
}

let cases = 0;
for (const link of [1, 113, 276]) {
    for (const little of [true, false]) {
        assert.equal(inspect(capture([[1, {}], [2, {invite: true}]], link, little)).first_agent_invite_after_digit_ms, 1000);
        cases++;
    }
}
for (const records of [
    [[1, {invite: true}], [2, {}]],
    [[1, {digit: 6}], [2, {invite: true}]],
    [[1, {address: [127, 0, 0, 20]}], [2, {invite: true}]],
    [[1, {port: 43000}], [2, {invite: true}]],
    [[1, {fragment: true}], [2, {invite: true}]],
    [[1, {}]],
    [[1, {invite: true}]]
]) {
    assert.throws(() => inspect(capture(records))); cases++;
}
assert.throws(() => inspect(capture([[1, {}], [2, {invite: true}]]).subarray(0, 31))); cases++;
console.log(`PASS: ${cases} callback pcap ordering, exact source, format, and fail-closed tests`);
