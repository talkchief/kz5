'use strict';
const assert = require('node:assert/strict');
const {inspect, bridgeProof} = require('./assert-callback-confirmation-pcap.cjs');
const proof = {callerCallId: 'c'.repeat(32), agentCallId: 'a'.repeat(32)};
function sdp(payload = 101, ip = '127.0.0.1', port = 20000, formats = '0 ' + payload) {
    return 'v=0\r\no=fixture 1 1 IN IP4 ' + ip + '\r\ns=fixture\r\nc=IN IP4 ' + ip
        + '\r\nt=0 0\r\nm=audio ' + port + ' RTP/AVP ' + formats
        + '\r\na=rtpmap:0 PCMU/8000\r\na=rtpmap:' + payload + ' telephone-event/8000\r\na=fmtp:'
        + payload + ' 0-16\r\na=sendrecv\r\n';
}
function sip(first, id, method, body = '') {
    return Buffer.from(first + '\r\nCall-ID: ' + id + '\r\nCSeq: 1 ' + method
        + (body ? '\r\nContent-Type: application/sdp' : '') + '\r\nContent-Length: '
        + Buffer.byteLength(body) + '\r\n\r\n' + body);
}
function packet(settings, link) {
    const size = link === 1 ? 14 : link === 113 ? 16 : 20;
    const payload = settings.payload, header = Buffer.alloc(size + 28);
    header.writeUInt16BE(0x0800, link === 1 ? 12 : link === 113 ? 14 : 0);
    header[size] = 0x45; header[size + 9] = 17;
    header.writeUInt16BE(settings.fragment ? 0x2000 : 0, size + 6);
    Buffer.from((settings.src || '127.0.0.1').split('.').map(Number)).copy(header, size + 12);
    Buffer.from((settings.dst || '127.0.0.30').split('.').map(Number)).copy(header, size + 16);
    header.writeUInt16BE(settings.sport || 5060, size + 20);
    header.writeUInt16BE(settings.dport || 16060, size + 22);
    header.writeUInt16BE(payload.length + 8, size + 24);
    header.writeUInt16BE(payload.length + 28, size + 2);
    return Buffer.concat([header, payload]);
}
function capture(records, link = 276, little = true) {
    const header = Buffer.alloc(24);
    Buffer.from(little ? 'd4c3b2a1' : 'a1b2c3d4', 'hex').copy(header);
    const write = (buffer, value, offset) => little ? buffer.writeUInt32LE(value, offset) : buffer.writeUInt32BE(value, offset);
    write(header, link, 20);
    return Buffer.concat([header, ...records.map(settings => {
        const data = packet(settings, link), record = Buffer.alloc(16), seconds = Math.floor(settings.time);
        write(record, seconds, 0); write(record, Math.round((settings.time - seconds) * 1e6), 4);
        write(record, data.length, 8); write(record, data.length, 12);
        return Buffer.concat([record, data]);
    })]);
}
function records(payload = 101) {
    const digit = end => {
        const data = Buffer.from([128, payload, 0, end ? 2 : 1, 0, 0, 0, 1, 0, 0, 0, 2, 1, end ? 138 : 10, 0, 160]);
        return {time: end ? 1.2 : 1, src: '127.0.0.30', sport: 44000, dst: '127.0.0.1', dport: 20000, payload: data};
    };
    return [
        {time: 0.1, payload: sip('INVITE sip:+12025550101@127.0.0.30 SIP/2.0', proof.callerCallId, 'INVITE', sdp(payload))},
        {time: 0.2, src: '127.0.0.30', sport: 16060, dst: '127.0.0.1', dport: 5060,
            payload: sip('SIP/2.0 200 OK', proof.callerCallId, 'INVITE', sdp(payload, '127.0.0.30', 44000))},
        {time: 0.3, payload: sip('ACK sip:+12025550101@127.0.0.30 SIP/2.0', proof.callerCallId, 'ACK')},
        digit(false), digit(true),
        {time: 2, dst: '127.0.0.20', dport: 15100,
            payload: sip('INVITE sip:fixture@127.0.0.20 SIP/2.0', proof.agentCallId, 'INVITE')}
    ];
}
module.exports = {proof, records, capture, sdp, sip, packet};
if (require.main === module) {
    let cases = 0;
    for (const link of [1, 113, 276]) for (const little of [true, false]) {
        const result = inspect(capture(records(), link, little), proof, 101);
        assert.equal(result.first_agent_invite_after_digit_ms, 1000);
        assert.equal(result.first_agent_invite_after_digit_end_ms, 800); cases++;
    }
    for (const alter of [
        r => {r[5].time = 1.1;},
        r => {r[5].dst = '127.0.0.40';},
        r => {r[5].payload = sip('INVITE sip:fixture@127.0.0.20 SIP/2.0', 'f'.repeat(32), 'INVITE');},
        r => {r[3].payload[12] = 6; r[4].payload[12] = 6;},
        r => {r[3].src = '127.0.0.20'; r[4].src = '127.0.0.20';},
        r => {r[3].dst = '127.0.0.99'; r[4].dst = '127.0.0.99';},
        r => {r[3].dport = 20002; r[4].dport = 20002;},
        r => {r[3].sport = 43000; r[4].sport = 43000;},
        r => {r[3].time = 0.25;},
        r => {r[3].fragment = true;},
        r => {r[4].payload[13] &= 127;},
        r => {r[4].payload.writeUInt16BE(0, 14);},
        r => {r[4].payload.writeUInt32BE(8, 8);},
        r => {r[4].payload.writeUInt32BE(8, 4);},
        r => {r[1].payload = sip('SIP/2.0 200 OK', 'f'.repeat(32), 'INVITE', sdp(101, '127.0.0.30', 44000));},
        r => {r[1].payload = sip('SIP/2.0 200 OK', proof.callerCallId, 'INVITE', sdp(96, '127.0.0.30', 44000));},
        r => {r[0].payload = sip('INVITE sip:+12025550101@127.0.0.30 SIP/2.0', proof.callerCallId, 'INVITE', sdp(101, '127.0.0.1', 20000, '0'));},
        r => {r[0].payload = sip('INVITE sip:+12025550101@127.0.0.30 SIP/2.0', proof.callerCallId, 'INVITE', sdp() + 'm=video 20002 RTP/AVP 101\r\n');},
        r => {r[0].payload = sip('INVITE sip:+12025550101@127.0.0.30 SIP/2.0', proof.callerCallId, 'INVITE', sdp().replace('a=fmtp:101 0-16', 'a=fmtp:101 2-16'));},
        r => {r.splice(2, 1);},
        r => {r.splice(1, 1);},
        r => {r.splice(0, 1);},
        r => {r.pop();},
        r => {r.splice(3, 2);}
    ]) {
        const input = records(); alter(input); assert.throws(() => inspect(capture(input), proof, 101)); cases++;
    }
    assert.throws(() => inspect(capture(records()).subarray(0, 31), proof, 101)); cases++;
    assert.throws(() => inspect(capture(records()), proof, 96)); cases++;
    const evidence = {caller: {id: '1'.repeat(32), account: '2'.repeat(32), bridge_to: '3'.repeat(32), sip_call_id: proof.callerCallId},
        agent: {id: '3'.repeat(32), account: '2'.repeat(32), bridge_to: '1'.repeat(32), sip_call_id: proof.agentCallId},
        callback: {caller_call_id: '1'.repeat(32), agent_call_id: '3'.repeat(32), status: 'completed', attempts: 1}};
    assert.deepEqual(bridgeProof(evidence), proof); cases++;
    for (const alter of [e => {delete e.caller.sip_call_id;}, e => {e.agent.account = '4'.repeat(32);},
        e => {e.callback.status = 'confirming';}, e => {e.callback.agent_call_id = '5'.repeat(32);},
        e => {e.callback.attempts = 2;}, e => {e.caller.bridge_to = null;}]) {
        const input = JSON.parse(JSON.stringify(evidence)); alter(input); assert.throws(() => bridgeProof(input)); cases++;
    }
    console.log('PASS: ' + cases + ' callback SDP/dialog/endpoint/completed-DTMF/ordering and capture-format tests');
}
