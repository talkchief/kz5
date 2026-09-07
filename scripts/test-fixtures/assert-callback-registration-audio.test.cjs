'use strict';
const assert = require('node:assert/strict'), {spawnSync} = require('node:child_process');
const {inspect} = require('./assert-callback-registration-audio.cjs');
const {capture, sdp} = require('./assert-callback-confirmation-pcap.test.cjs');
const wav = require('node:path').resolve(__dirname, '../assets/acdc-callback-prompts/en-us/acdc-callback-success.wav');
const converted = spawnSync('sox', [wav, '-t', 'raw', '-r', '8000', '-c', '1', '-e', 'mu-law', '-']);
assert.equal(converted.status, 0); const reference = converted.stdout;
const callId = '1-999@127.0.0.20', local = '127.0.0.20', peer = '127.0.0.1';
function message(first, method, body = '', reverse = false, sequence = 2, id = callId) {
    return Buffer.from(first + '\r\nCall-ID: ' + id + '\r\nCSeq: ' + sequence + ' ' + method
        + '\r\nFrom: <sip:fixture@acceptance.invalid>;tag=' + (reverse ? 'server' : 'caller')
        + '\r\nTo: <sip:queue@acceptance.invalid>;tag=' + (reverse ? 'caller' : 'server')
        + (body ? '\r\nContent-Type: application/sdp' : '')
        + '\r\nContent-Length: ' + Buffer.byteLength(body) + '\r\n\r\n' + body);
}
function signalling(time, payload, outbound = false) {
    return {time, payload, src: outbound ? local : peer, dst: outbound ? peer : local,
        sport: outbound ? 15064 : 5060, dport: outbound ? 5060 : 15064};
}
function digit(event, start) {
    return [false, true].map(end => {
        const payload = Buffer.alloc(16); payload[0] = 128; payload[1] = 96;
        payload.writeUInt16BE(end ? 2 : 1, 2); payload.writeUInt32BE(event * 8000, 4);
        payload.writeUInt32BE(321, 8); payload[12] = event; payload[13] = end ? 138 : 10;
        payload.writeUInt16BE(end ? 1600 : 0, 14);
        return {time: start + (end ? 0.2 : 0), payload, src: local, dst: peer, sport: 43000, dport: 30000};
    });
}
function records(mode = 'confirm-current') {
    const result = [
        signalling(99.9, message('INVITE sip:2000@acceptance.invalid SIP/2.0', 'INVITE', sdp(96, local, 43000)), true),
        signalling(100, message('SIP/2.0 200 OK', 'INVITE', sdp(96, peer, 30000))),
        signalling(100.01, message('ACK sip:fixture@127.0.0.1 SIP/2.0', 'ACK'), true),
        ...digit(6, 105), ...(mode === 'confirm-current' ? digit(1, 107.5) : [])
    ];
    const audio = Buffer.alloc(15 * 8000, 255); reference.copy(audio, 8 * 8000);
    for (let start = 0; start < audio.length; start += 160) {
        const payload = Buffer.alloc(172); payload[0] = 128;
        payload.writeUInt16BE(start / 160, 2); payload.writeUInt32BE(start, 4); payload.writeUInt32BE(123, 8);
        audio.copy(payload, 12, start, start + 160);
        result.push({time: 100 + start / 8000, payload, src: peer, dst: local, sport: 30000, dport: 43000});
    }
    result.push(signalling(115, message('BYE sip:fixture@127.0.0.20 SIP/2.0', 'BYE', '', true, 3)),
        signalling(115.001, message('SIP/2.0 200 OK', 'BYE', '', true, 3), true));
    return result.sort((a, b) => a.time - b.time);
}
let count = 0;
for (const mode of ['confirm-current', 'entry-only']) for (const link of [1, 113, 276]) for (const little of [false, true]) {
    const result = inspect(capture(records(mode), link, little), reference, callId, local, 15064, 43000, mode);
    assert.equal(result.correlation, 1); assert.equal(result.confirmation_start_epoch_seconds, 108);
    assert.equal(result.confirmation_end_epoch_seconds, 108 + reference.length / 8000);
    assert.equal(result.original_bye_epoch_seconds, 115); assert.equal(result.entry_after_answer_seconds, 5); count++;
    assert.equal(result.registration_mode, mode);
    assert.deepEqual(result.expected_registration_digits, mode === 'entry-only' ? [6] : [6, 1]);
    assert.deepEqual(result.observed_registration_digits, result.expected_registration_digits);
}
for (const mode of ['confirm-current', 'entry-only']) {
    const other = mode === 'entry-only' ? 'confirm-current' : 'entry-only';
    assert.throws(() => inspect(capture(records(other)), reference, callId, local, 15064, 43000, mode),
        undefined, 'Cross-mode capture must fail'); count++;
}
assert.throws(() => inspect(capture(records()), reference, callId, local, 15064, 43000, 'auto')); count++;
const extraEntry = digit(6, 106).map(packet => {
    packet.payload.writeUInt32BE(56000, 4); return packet;
});
assert.throws(() => inspect(capture([...records('entry-only'), ...extraEntry].sort((a, b) => a.time - b.time)),
    reference, callId, local, 15064, 43000, 'entry-only')); count++;
const sipIs = (r, first) => r.payload.toString('latin1').startsWith(first);
const incomingAudio = r => r.sport === 30000;
const dtmf = r => r.sport === 43000;
const negative = [
    r => r.filter(p => !sipIs(p, 'SIP/2.0 200 OK')),
    r => r.filter(p => !sipIs(p, 'ACK ')),
    r => r.filter(p => !sipIs(p, 'BYE ')),
    r => r.filter(p => !(sipIs(p, 'SIP/2.0 200 OK') && p.sport === 15064)),
    r => {r.find(p => sipIs(p, 'BYE ')).payload = message('BYE sip:fixture@127.0.0.20 SIP/2.0', 'BYE', '', true, 3, 'other'); return r;},
    r => {r.find(p => sipIs(p, 'BYE ')).payload = message('BYE sip:fixture@127.0.0.20 SIP/2.0', 'BYE', '', false, 3); return r;},
    r => {r.find(p => sipIs(p, 'BYE ')).src = '127.0.0.99'; return r;},
    r => {r.find(p => sipIs(p, 'BYE ')).time = 112; return r;},
    r => {r.find(p => sipIs(p, 'SIP/2.0 200 OK')).payload = message('SIP/2.0 200 OK', 'INVITE', sdp(101, peer, 30000)); return r;},
    r => {r.find(p => sipIs(p, 'SIP/2.0 200 OK')).payload = message('SIP/2.0 200 OK', 'INVITE', sdp(96, peer, 30002)); return r;},
    r => {r.find(p => sipIs(p, 'INVITE ')).payload = message('INVITE sip:2000@acceptance.invalid SIP/2.0', 'INVITE', sdp(96, local, 43002)); return r;},
    r => {r.find(p => sipIs(p, 'INVITE ')).payload = message('INVITE sip:2000@acceptance.invalid SIP/2.0', 'INVITE', sdp(96, local, 43000).replace('RTP/AVP 0 96', 'RTP/AVP 0')); return r;},
    r => {r.find(p => sipIs(p, 'INVITE ')).payload = message('INVITE sip:2000@acceptance.invalid SIP/2.0', 'INVITE', sdp(96, local, 43000).replace('a=fmtp:96 0-16', 'a=fmtp:96 0-5')); return r;},
    r => r.filter(p => !dtmf(p)),
    r => {r.filter(dtmf).forEach(p => p.sport = 43002); return r;},
    r => {r.filter(dtmf).forEach(p => p.payload[1] = 101); return r;},
    r => {r.filter(dtmf).forEach(p => p.payload[13] &= 127); return r;},
    r => {r.filter(dtmf).forEach(p => p.payload.writeUInt16BE(0, 14)); return r;},
    r => {r.filter(dtmf).forEach(p => p.time -= 1); return r;},
    r => {r.filter(dtmf).forEach(p => p.payload[12] = 1); return r;},
    r => {r.filter(incomingAudio).forEach(p => p.dport = 43020); return r;},
    r => {r.filter(incomingAudio).forEach(p => p.src = '127.0.0.99'); return r;},
    r => {r.filter(incomingAudio).forEach(p => p.payload[1] = 8); return r;},
    r => {r.filter(incomingAudio).forEach(p => {if (p.time > 111) p.payload.fill(255, 12);}); return r;},
    r => r.filter(p => !(incomingAudio(p) && p.time === 110)),
    r => {r.find(p => incomingAudio(p) && p.time === 110).payload.writeUInt32BE(456, 8); return r;},
    r => {const copy = {...r.find(p => incomingAudio(p) && p.time === 110)}; copy.payload = Buffer.from(copy.payload); copy.payload[12] ^= 255; return [...r, copy];},
    r => {r.find(p => incomingAudio(p) && p.time === 110).fragment = true; return r;},
    r => {const p = r.find(p => sipIs(p, 'SIP/2.0 200 OK')); p.payload = Buffer.from(p.payload.toString().replace('Content-Length: ', 'Content-Length: 9')); return r;},
    r => {const p = r.find(p => sipIs(p, 'BYE ')); p.payload = Buffer.from(p.payload.toString().replace('Call-ID: ', 'Call-ID: duplicate\r\nCall-ID: ')); return r;}
];
for (const mode of ['confirm-current', 'entry-only']) for (const [index, alter] of negative.entries()) {
    assert.throws(() => inspect(capture(alter(records(mode))), reference, callId, local, 15064, 43000, mode),
        undefined, 'False pass in ' + mode + ' fault ' + index); count++;
}
assert.throws(() => inspect(capture(records()), reference.subarray(0, 24000), callId)); count++;
assert.throws(() => inspect(capture(records()), reference, '1-999@127.0.0.40')); count++;
assert.throws(() => inspect(capture(records()).subarray(0, -1), reference, callId)); count++;
console.log('PASS ' + count + ' registration audio gates: full installed-reference delivery, exact SDP/dialog/DTMF scope, five-second entry, complete success before server BYE, missing/truncated/corrupt audio fail closed');
