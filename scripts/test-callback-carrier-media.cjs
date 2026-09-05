#!/usr/bin/env node
'use strict';
const assert = require('node:assert/strict');
const {digitPcap} = require('./test-fixtures/create-callback-carrier-scenario.cjs');
const {inspect, negotiatedPayload} = require('./test-fixtures/assert-callback-confirmation-pcap.cjs');
const {proof, records, capture} = require('./test-fixtures/assert-callback-confirmation-pcap.test.cjs');

function fixture(payload, agentTime = 2, address = '127.0.0.20') {
    const dialogs = records(payload);
    dialogs[5].time = agentTime; dialogs[5].dst = address;
    return Buffer.concat([capture(dialogs.slice(0, 3), 1), digitPcap(payload).subarray(24),
        capture([dialogs[5]], 1).subarray(24)]);
}
for (let payload = 96; payload <= 127; payload++) {
    const packets = fixture(payload), actual = inspect(packets, proof, payload);
    assert.equal(actual.negotiated_telephone_event, payload);
    assert.equal(actual.digit_packets, 13);
    assert.equal(actual.agent_invites, 1);
    assert.equal(actual.first_agent_invite_after_digit_ms, 1000);
    assert.equal(actual.first_agent_invite_after_digit_end_ms, 800);
    assert.throws(() => inspect(packets, proof, payload === 96 ? 101 : 96), /negotiation mismatch/);
    assert.equal(negotiatedPayload(`callback-negotiated-telephone-event=${payload}\n`), payload);
}
assert.throws(() => inspect(fixture(101, 1.1), proof, 101), /preceded completed/);
assert.throws(() => inspect(fixture(101, 2, '127.0.0.40'), proof, 101), /No native agent/);
assert.throws(() => inspect(digitPcap(101), proof, 101), /No returned-caller offer/);
for (const value of [95, 128, 1.1, NaN]) assert.throws(() => digitPcap(value));
for (const value of ['', 'callback-negotiated-telephone-event=95\n',
    'callback-negotiated-telephone-event=101\ncallback-negotiated-telephone-event=101\n',
    'callback-negotiated-telephone-event=101\ncallback-unsupported-telephone-event\n']) {
    assert.throws(() => negotiatedPayload(value));
}
console.log('PASS: all32 generated dynamic payloads bound to actual SDP/dialogs; mismatched DTMF, premature/wrong-endpoint INVITEs and ambiguous negotiation rejected');
