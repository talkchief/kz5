#!/usr/bin/env node
'use strict';
// SPDX-License-Identifier: MPL-2.0
// Read-only evidence gate for one isolated callback dialog. Never prints SIP
// headers, credentials or audio. Unsupported SDP/capture shapes fail closed.
const fs = require('node:fs');
const assert = require('node:assert/strict');
const IP = {carrier: '127.0.0.30', agent: '127.0.0.20'};
const PORT = {carrierSip: 16060, carrierRtp: 44000, agentSip: 15100};
const validId = value => typeof value === 'string' && /^[A-Za-z0-9@._:-]{1,128}$/.test(value);
const ipv4 = value => /^\d{1,3}(\.\d{1,3}){3}$/.test(value) && value.split('.').every(part => Number(part) <= 255);

function packets(buffer) {
    assert(buffer.length >= 24, 'Missing pcap header');
    const magic = buffer.subarray(0, 4).toString('hex');
    const little = ['d4c3b2a1', '4d3cb2a1'].includes(magic);
    const nano = ['4d3cb2a1', 'a1b23c4d'].includes(magic);
    assert(little || ['a1b2c3d4', 'a1b23c4d'].includes(magic), 'Unsupported pcap format');
    const u32 = offset => little ? buffer.readUInt32LE(offset) : buffer.readUInt32BE(offset);
    const link = u32(20), result = [];
    assert([1, 113, 276].includes(link), 'Unsupported pcap link type');
    for (let offset = 24; offset < buffer.length;) {
        assert(offset + 16 <= buffer.length, 'Truncated pcap record');
        const fraction = u32(offset + 4), length = u32(offset + 8);
        assert(fraction < (nano ? 1e9 : 1e6), 'Invalid packet timestamp');
        const time = u32(offset) + fraction / (nano ? 1e9 : 1e6);
        assert(length === u32(offset + 12) && offset + 16 + length <= buffer.length, 'Truncated pcap packet');
        const packet = buffer.subarray(offset + 16, offset + 16 + length);
        offset += 16 + length;
        const ip = link === 1 ? 14 : link === 113 ? 16 : 20;
        const protocolOffset = link === 1 ? 12 : link === 113 ? 14 : 0;
        if (packet.length < ip || packet.readUInt16BE(protocolOffset) !== 0x0800) continue;
        if (packet.length < ip + 20 || packet[ip] >> 4 !== 4 || packet[ip + 9] !== 17) continue;
        assert((packet.readUInt16BE(ip + 6) & 0x3fff) === 0, 'Fragmented UDP cannot prove confirmation');
        const header = (packet[ip] & 15) * 4, total = packet.readUInt16BE(ip + 2), udp = ip + header;
        assert(header >= 20 && total >= header + 8 && ip + total <= packet.length, 'Invalid IPv4 length');
        const udpLength = packet.readUInt16BE(udp + 4);
        assert(udpLength >= 8 && header + udpLength === total, 'Invalid UDP length');
        result.push({time, src: [...packet.subarray(ip + 12, ip + 16)].join('.'),
            dst: [...packet.subarray(ip + 16, ip + 20)].join('.'),
            sport: packet.readUInt16BE(udp), dport: packet.readUInt16BE(udp + 2),
            payload: packet.subarray(udp + 8, udp + udpLength)});
    }
    return result;
}
function sip(packet) {
    const text = packet.payload.toString('latin1'), separator = text.indexOf('\r\n\r\n');
    assert(separator >= 0, 'Incomplete fixture SIP message');
    const lines = text.slice(0, separator).split('\r\n'), first = lines.shift(), headers = {};
    for (const line of lines) {
        const match = /^([^:\s]+):\s*(.*)$/.exec(line);
        assert(match, 'Malformed fixture SIP header');
        const key = match[1].toLowerCase();
        (headers[key] ||= []).push(match[2].trim());
    }
    function one(key) { assert(headers[key]?.length === 1, 'Missing or ambiguous SIP ' + key); return headers[key][0]; }
    const callId = one('call-id'), cseq = /^(\d+) (INVITE|ACK)$/.exec(one('cseq'));
    assert(validId(callId) && cseq, 'Invalid SIP dialog identity');
    const body = text.slice(separator + 4);
    assert(/^\d+$/.test(one('content-length')) && Number(one('content-length')) === Buffer.byteLength(body, 'latin1'),
        'SIP body length mismatch');
    return {...packet, first, body, callId, cseq: Number(cseq[1]), method: cseq[2], headers};
}
function audioSdp(message) {
    assert(message.headers['content-type']?.length === 1
        && /^application\/sdp(?:\s*;.*)?$/i.test(message.headers['content-type'][0]), 'Missing SDP content type');
    const lines = message.body.split(/\r?\n/).map(line => line.trim()).filter(Boolean);
    const media = lines.map((line, index) => line.startsWith('m=') ? index : -1).filter(index => index >= 0);
    assert(media.length === 1, 'Fixture requires one unambiguous audio media section');
    const start = media[0], m = /^m=audio (\d+) RTP\/AVP ((?:\d+)(?: \d+)*)$/.exec(lines[start]);
    assert(m && Number(m[1]) > 0 && Number(m[1]) < 65536, 'Invalid audio media line');
    const formats = m[2].split(' ').map(Number);
    assert(formats.includes(0) && new Set(formats).size === formats.length, 'Missing PCMU or duplicate media payload');
    const sessionConnections = lines.slice(0, start).filter(line => line.startsWith('c='));
    const mediaConnections = lines.slice(start + 1).filter(line => line.startsWith('c='));
    assert(sessionConnections.length <= 1 && mediaConnections.length <= 1, 'Ambiguous media address');
    const connection = /^c=IN IP4 (\S+)$/.exec((mediaConnections[0] || sessionConnections[0]) || '');
    assert(connection && ipv4(connection[1]) && connection[1] !== '0.0.0.0', 'Unsupported media address');
    const mappings = lines.slice(start + 1).filter(line => line.startsWith('a=rtpmap:'));
    assert(mappings.includes('a=rtpmap:0 PCMU/8000'), 'Fixture requires PCMU/8000');
    const events = mappings.map(line => /^a=rtpmap:(\d+) telephone-event\/8000(?:\/1)?$/i.exec(line)).filter(Boolean);
    assert(events.length === 1, 'Expected exactly one audio telephone-event mapping');
    const payload = Number(events[0][1]);
    assert(payload >= 96 && payload <= 127 && formats.includes(payload), 'Telephone-event payload is not offered in audio m-line');
    assert(mappings.filter(line => line.startsWith('a=rtpmap:' + payload + ' ')).length === 1, 'Conflicting payload mapping');
    const fmtp = lines.slice(start + 1).filter(line => line.startsWith('a=fmtp:' + payload + ' '));
    assert(fmtp.length === 1, 'Missing or ambiguous telephone-event range');
    const ranges = fmtp[0].slice(('a=fmtp:' + payload + ' ').length).split(',');
    assert(ranges.every(range => /^\d+(?:-\d+)?$/.test(range)), 'Unsupported telephone-event range');
    assert(ranges.some(range => {const [low, high = low] = range.split('-').map(Number); return low <= 1 && high >= 1;}),
        'Telephone event 1 is not supported');
    assert(!lines.some(line => ['a=inactive', 'a=sendonly', 'a=recvonly'].includes(line)), 'Inactive or one-way callback audio');
    return {ip: connection[1], port: Number(m[1]), payload};
}
function bridgeProof(evidence) {
    const {caller, agent, callback} = evidence || {};
    assert(caller && agent && callback && validId(caller.id) && validId(agent.id)
        && /^[a-f0-9]{32}$/.test(caller.account || '') && caller.account === agent.account
        && caller.bridge_to === agent.id && agent.bridge_to === caller.id
        && callback.caller_call_id === caller.id && callback.agent_call_id === agent.id
        && callback.status === 'completed' && callback.attempts === 1,
    'Missing exact native callback bridge evidence');
    assert(validId(caller.sip_call_id) && validId(agent.sip_call_id)
        && caller.sip_call_id !== agent.sip_call_id, 'Missing exact SIP dialog correlation');
    return {callerCallId: caller.sip_call_id, agentCallId: agent.sip_call_id};
}
function uniqueTransaction(messages, description) {
    assert(messages.length > 0, 'No ' + description + ' observed');
    const first = messages[0];
    assert(messages.every(message => message.callId === first.callId && message.cseq === first.cseq
        && message.body === first.body), 'Ambiguous ' + description + ' or media renegotiation');
    return messages.reduce((before, current) => current.time < before.time ? current : before);
}
function inspect(buffer, proof, logPayload) {
    assert(validId(proof?.callerCallId) && validId(proof?.agentCallId), 'Missing expected fixture dialogs');
    const all = packets(buffer), offers = [], answers = [], acknowledgements = [], agentInvites = [];
    for (const packet of all) {
        const first = packet.payload.subarray(0, 16).toString('latin1');
        if (packet.dst === IP.carrier && packet.dport === PORT.carrierSip && first.startsWith('INVITE ')) {
            const message = sip(packet);
            assert(message.callId === proof.callerCallId && /^INVITE sip:\+12025550101@\S+ SIP\/2.0$/.test(message.first),
                'Unrelated returned-caller INVITE');
            offers.push(message);
        } else if (packet.src === IP.carrier && packet.sport === PORT.carrierSip && first.startsWith('SIP/2.0 200 ')) {
            // A BYE response is irrelevant; only the INVITE transaction carries SDP.
            if (/\r\nCSeq:\s*\d+ INVITE\r\n/i.test(packet.payload.toString('latin1'))) answers.push(sip(packet));
        } else if (packet.dst === IP.carrier && packet.dport === PORT.carrierSip && first.startsWith('ACK ')) {
            acknowledgements.push(sip(packet));
        } else if (packet.dst === IP.agent && packet.dport === PORT.agentSip && first.startsWith('INVITE ')) {
            const message = sip(packet);
            assert(message.callId === proof.agentCallId, 'Unrelated agent INVITE cannot prove callback ordering');
            agentInvites.push(message);
        }
    }
    const offer = uniqueTransaction(offers, 'returned-caller offer');
    const answer = uniqueTransaction(answers, 'returned-caller answer');
    const ack = uniqueTransaction(acknowledgements, 'returned-caller ACK');
    const agent = uniqueTransaction(agentInvites, 'native agent INVITE');
    assert(answer.callId === offer.callId && ack.callId === offer.callId
        && answer.cseq === offer.cseq && ack.cseq === offer.cseq
        && answer.dst === offer.src && answer.dport === offer.sport
        && ack.src === offer.src && ack.sport === offer.sport
        && offer.time <= answer.time && answer.time <= ack.time, 'SIP dialog transaction/direction mismatch');
    const remote = audioSdp(offer), local = audioSdp(answer);
    assert(local.ip === IP.carrier && local.port === PORT.carrierRtp
        && local.payload === remote.payload && remote.payload === logPayload, 'Offer/answer/log negotiation mismatch');
    const events = [];
    for (const packet of all) {
        if (packet.src !== local.ip || packet.sport !== local.port || packet.dst !== remote.ip || packet.dport !== remote.port) continue;
        const payload = packet.payload;
        if (payload.length < 12 || payload[0] >> 6 !== 2 || (payload[1] & 127) !== remote.payload) continue;
        let offset = 12 + (payload[0] & 15) * 4;
        assert(offset <= payload.length, 'Truncated RTP header');
        if (payload[0] & 16) {
            assert(payload.length >= offset + 4, 'Truncated RTP extension');
            offset += 4 + payload.readUInt16BE(offset + 2) * 4;
        }
        const padding = payload[0] & 32 ? payload[payload.length - 1] : 0;
        assert(!(payload[0] & 32) || padding > 0, 'Invalid RTP padding');
        assert(payload.length - padding === offset + 4, 'Invalid telephone-event packet size');
        if (payload[offset] !== 1) continue;
        assert((payload[offset + 1] & 64) === 0 && payload.readUInt16BE(offset + 2) > 0,
            'Invalid telephone-event flags/duration');
        assert(packet.time >= ack.time, 'Confirmation preceded the established returned dialog');
        events.push({time: packet.time, end: !!(payload[offset + 1] & 128), duration: payload.readUInt16BE(offset + 2),
            sequence: payload.readUInt16BE(2), timestamp: payload.readUInt32BE(4), ssrc: payload.readUInt32BE(8)});
    }
    assert(events.length >= 2 && events.some(event => !event.end), 'No returned caller RFC2833 digit 1 start observed');
    events.sort((a, b) => a.time - b.time);
    const first = events[0], ended = events.find(event => event.end);
    assert(ended && ended.duration >= 160 && !first.end, 'No completed returned caller RFC2833 digit 1 observed');
    assert(events.every(event => event.ssrc === first.ssrc && event.timestamp === first.timestamp),
        'Ambiguous telephone-event streams');
    let duration = 0;
    for (const event of events) {assert(event.duration >= duration, 'Telephone-event duration regressed'); duration = event.duration;}
    assert(agent.time > ended.time, 'Agent INVITE preceded completed returned caller confirmation');
    return {negotiated_telephone_event: remote.payload, digit_packets: events.length, agent_invites: agentInvites.length,
        first_agent_invite_after_digit_ms: Math.round((agent.time - first.time) * 1000),
        first_agent_invite_after_digit_end_ms: Math.round((agent.time - ended.time) * 1000)};
}
function negotiatedPayload(log) {
    assert(!log.includes('callback-unsupported-telephone-event'), 'Carrier rejected negotiated payload');
    const matches = [...log.matchAll(/callback-negotiated-telephone-event=([0-9]+)(?=\s|$)/g)];
    assert.equal(matches.length, 1, 'Expected exactly one actual offered telephone-event mapping');
    const payload = Number(matches[0][1]);
    assert(Number.isInteger(payload) && payload >= 96 && payload <= 127, 'Unsupported offered payload');
    return payload;
}
module.exports = {inspect, negotiatedPayload, bridgeProof, audioSdp, packets};
if (require.main === module) {
    try {
        assert(process.argv.length === 5, 'Usage: assert-callback-confirmation-pcap.cjs capture.pcap negotiation.log bridge-evidence.json');
        for (const [file, max] of [[process.argv[2], 64 * 1024 * 1024], [process.argv[3], 8192], [process.argv[4], 65536]]) {
            const stat = fs.lstatSync(file);
            assert(stat.isFile() && !stat.isSymbolicLink() && stat.size <= max, 'Unsafe or oversized evidence file');
        }
        const payload = negotiatedPayload(fs.readFileSync(process.argv[3], 'utf8'));
        const proof = bridgeProof(JSON.parse(fs.readFileSync(process.argv[4], 'utf8')));
        process.stdout.write(JSON.stringify(inspect(fs.readFileSync(process.argv[2]), proof, payload)) + '\n');
    } catch (error) {
        process.stderr.write('Callback confirmation evidence FAIL: ' + error.message + '\n');
        process.exitCode = 1;
    }
}
