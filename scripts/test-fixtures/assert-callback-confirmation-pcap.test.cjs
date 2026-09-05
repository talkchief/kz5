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
function agentSdp(ip = '127.0.0.20', port = 40000) {
    return sdp(101, ip, port, '0').replace('a=rtpmap:101 telephone-event/8000\r\n', '')
        .replace('a=fmtp:101 0-16\r\n', '');
}
function audioPacket(index, incoming) {
    const data = Buffer.alloc(172, 0xff);
    data[0] = 0x80; data[1] = 0; data.writeUInt16BE(index, 2);
    data.writeUInt32BE(index * 160, 4); data.writeUInt32BE(incoming ? 10 : 20, 8);
    return {time: 2.4 + index * 0.02 + (incoming ? 0 : 0.005), payload: data,
        src: incoming ? '127.0.0.1' : '127.0.0.20', sport: incoming ? 20002 : 40000,
        dst: incoming ? '127.0.0.20' : '127.0.0.1', dport: incoming ? 40000 : 20002};
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
            payload: sip('INVITE sip:fixture@127.0.0.20 SIP/2.0', proof.agentCallId, 'INVITE', sdp(101, '127.0.0.1', 20002))},
        {time: 2.1, src: '127.0.0.20', sport: 15100, dst: '127.0.0.1', dport: 5060,
            payload: sip('SIP/2.0 200 OK', proof.agentCallId, 'INVITE', agentSdp())},
        {time: 2.2, dst: '127.0.0.20', dport: 15100,
            payload: sip('ACK sip:fixture@127.0.0.20 SIP/2.0', proof.agentCallId, 'ACK')},
        ...Array.from({length: 10}, (_, index) => [audioPacket(index, true), audioPacket(index, false)]).flat()
    ];
}
module.exports = {proof, records, capture, sdp, sip, packet};
if (require.main === module) {
    let cases = 0;
    for (const link of [1, 113, 276]) for (const little of [true, false]) {
        const result = inspect(capture(records(), link, little), proof, 101);
        assert.equal(result.first_agent_invite_after_digit_ms, 1000);
        assert.equal(result.first_agent_invite_after_digit_end_ms, 800);
        assert.deepEqual(result.agent_audio, {codec: 'PCMU/8000', payload: 0, to_agent: 10, from_agent: 10}); cases++;
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
        r => {r.splice(5, 1);},
        r => {r.splice(3, 2);}
    ]) {
        const input = records(); alter(input); assert.throws(() => inspect(capture(input), proof, 101)); cases++;
    }
    const agentOffer = body => sip('INVITE sip:fixture@127.0.0.20 SIP/2.0', proof.agentCallId, 'INVITE', body);
    const agentAnswer = body => sip('SIP/2.0 200 OK', proof.agentCallId, 'INVITE', body);
    const changeAudio = (records, change, incoming) => records.slice(8).forEach((record, index) => {
        if (incoming === undefined || (index % 2 === 0) === incoming) change(record);
    });
    for (const [name, alter] of [
        ['missing agent answer', r => {r.splice(6, 1);}],
        ['missing agent ACK', r => {r.splice(7, 1);}],
        ['unrelated agent answer', r => {r[6].payload = sip('SIP/2.0 200 OK', 'f'.repeat(32), 'INVITE', agentSdp());}],
        ['wrong answer CSeq', r => {r[6].payload = Buffer.from(r[6].payload.toString().replace('CSeq: 1 ', 'CSeq: 2 '));}],
        ['wrong ACK CSeq', r => {r[7].payload = Buffer.from(r[7].payload.toString().replace('CSeq: 1 ', 'CSeq: 2 '));}],
        ['wrong answer source', r => {r[6].src = '127.0.0.40';}],
        ['wrong answer source port', r => {r[6].sport = 15101;}],
        ['wrong answer destination', r => {r[6].dst = '127.0.0.99';}],
        ['wrong answer destination port', r => {r[6].dport = 5062;}],
        ['wrong ACK source', r => {r[7].src = '127.0.0.99';}],
        ['wrong ACK source port', r => {r[7].sport = 5062;}],
        ['answer before INVITE', r => {r[6].time = 1.9;}],
        ['ACK before answer', r => {r[7].time = 2.05;}],
        ['missing agent offer SDP', r => {r[5].payload = agentOffer('');}],
        ['missing agent answer SDP', r => {r[6].payload = agentAnswer('');}],
        ['multiple agent media', r => {r[6].payload = agentAnswer(agentSdp() + 'm=audio 40002 RTP/AVP 0\r\n');}],
        ['duplicate agent address', r => {r[6].payload = agentAnswer(agentSdp().replace('t=0 0', 'c=IN IP4 127.0.0.40\r\nt=0 0'));}],
        ['wrong negotiated agent address', r => {r[6].payload = agentAnswer(agentSdp('127.0.0.40'));}],
        ['wrong negotiated agent port', r => {r[6].payload = agentAnswer(agentSdp('127.0.0.20', 40002));}],
        ['wrong offered media address', r => {r[5].payload = agentOffer(sdp(101, '127.0.0.99', 20002));}],
        ['wrong offered media port', r => {r[5].payload = agentOffer(sdp(101, '127.0.0.1', 20004));}],
        ['agent PCMA instead of PCMU', r => {r[6].payload = agentAnswer(agentSdp().replace('PCMU/8000', 'PCMA/8000'));}],
        ['agent stereo PCM', r => {r[6].payload = agentAnswer(agentSdp().replace('PCMU/8000', 'PCMU/8000/2'));}],
        ['conflicting PCMU mapping', r => {r[6].payload = agentAnswer(agentSdp() + 'a=rtpmap:0 PCMA/8000\r\n');}],
        ['ambiguous accepted codec', r => {r[6].payload = agentAnswer(sdp(101, '127.0.0.20', 40000));}],
        ['send-only agent', r => {r[6].payload = agentAnswer(agentSdp().replace('a=sendrecv', 'a=sendonly'));}],
        ['receive-only FS', r => {r[5].payload = agentOffer(sdp(101, '127.0.0.1', 20002).replace('a=sendrecv', 'a=recvonly'));}],
        ['renegotiated agent answer', r => {r.push({...r[6], time: 2.15, payload: agentAnswer(agentSdp('127.0.0.20', 40002))});}],
        ['missing all agent RTP', r => {r.splice(8);}],
        ['missing outbound agent RTP', r => {r.splice(8, 20, ...r.slice(8).filter((_, i) => i % 2 === 0));}],
        ['missing inbound agent RTP', r => {r.splice(8, 20, ...r.slice(8).filter((_, i) => i % 2 !== 0));}],
        ['insufficient agent flow', r => {r.pop();}],
        ['wrong RTP source address', r => {changeAudio(r, p => {p.src = '127.0.0.99';}, false);}],
        ['wrong RTP source port', r => {changeAudio(r, p => {p.sport = 40002;}, false);}],
        ['wrong RTP destination address', r => {changeAudio(r, p => {p.dst = '127.0.0.99';}, false);}],
        ['wrong RTP destination port', r => {changeAudio(r, p => {p.dport = 20004;}, false);}],
        ['reversed incoming direction', r => {changeAudio(r, p => {
            [p.src, p.dst] = [p.dst, p.src]; [p.sport, p.dport] = [p.dport, p.sport];
        }, true);}],
        ['pre-ACK media only', r => {changeAudio(r, p => {p.time = 2.15;});}],
        ['wrong RTP version', r => {r[8].payload[0] = 0x40;}],
        ['wrong RTP codec payload', r => {r[8].payload[1] = 8;}],
        ['telephone events are not PCMU audio', r => {changeAudio(r, p => {p.payload[1] = 101;});}],
        ['short RTP header', r => {r[8].payload = r[8].payload.subarray(0, 10);}],
        ['missing audio payload', r => {r[8].payload = r[8].payload.subarray(0, 12);}],
        ['truncated RTP extension', r => {r[8].payload[0] |= 16; r[8].payload.writeUInt16BE(65535, 14);}],
        ['invalid zero padding', r => {r[8].payload[0] |= 32; r[8].payload[r[8].payload.length - 1] = 0;}],
        ['excessive padding', r => {r[8].payload[0] |= 32; r[8].payload[r[8].payload.length - 1] = 255;}],
        ['ambiguous audio SSRC', r => {r[8].payload.writeUInt32BE(99, 8);}],
        ['duplicate audio is not flow', r => {changeAudio(r, p => {p.payload.writeUInt16BE(1, 2); p.payload.writeUInt32BE(160, 4);});}],
        ['nonadvancing media timestamps', r => {changeAudio(r, p => {p.payload.writeUInt32BE(160, 4);});}],
        ['nonadvancing RTP sequences', r => {changeAudio(r, p => {p.payload.writeUInt16BE(1, 2);});}],
        ['nonadvancing capture times', r => {changeAudio(r, p => {p.time = 2.4;});}]
    ]) {
        const input = records(); alter(input);
        assert.throws(() => inspect(capture(input), proof, 101), undefined, name); cases++;
    }
    // Retransmitted SIP and duplicated capture observations do not inflate the
    // count; valid RTP header extensions, CSRCs and padding remain supported.
    const duplicates = records(); duplicates.push({...duplicates[6]}, {...duplicates[7]}, {...duplicates[8]});
    assert.equal(inspect(capture(duplicates), proof, 101).agent_audio.to_agent, 10); cases++;
    const benignSip = records();
    benignSip.push({time: 0.01, src: '127.0.0.20', sport: 15100, dst: '127.0.0.1', dport: 5060,
        payload: sip('REGISTER sip:fixture SIP/2.0', 'fixture-registration', 'REGISTER')},
    {time: 4, src: '127.0.0.20', sport: 15100, dst: '127.0.0.1', dport: 5060,
        payload: sip('SIP/2.0 200 OK', proof.agentCallId, 'BYE')});
    assert.equal(inspect(capture(benignSip), proof, 101).agent_audio.to_agent, 10); cases++;
    const headerVariants = records();
    for (let index = 8; index < headerVariants.length; index++) {
        const old = headerVariants[index].payload;
        const head = Buffer.from(old.subarray(0, 12)); head[0] |= 1 | 16 | 32;
        const extra = Buffer.alloc(12); extra.writeUInt16BE(1, 6);
        headerVariants[index].payload = Buffer.concat([head, extra, old.subarray(12), Buffer.from([0, 2])]);
    }
    assert.equal(inspect(capture(headerVariants), proof, 101).agent_audio.from_agent, 10); cases++;
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
    console.log('PASS: ' + cases + ' callback SDP/dialog/endpoint/completed-DTMF/ordering, negotiated bidirectional PCMU and capture-format tests');
}
