#!/usr/bin/env node
'use strict';
// SPDX-License-Identifier: MPL-2.0
// Read-only evidence for one synthetic original callback requester. A full
// installed prompt match proves delivery of those bytes, not human listening
// or an independent semantic transcription. Never emits headers or audio.
const fs = require('node:fs'), assert = require('node:assert/strict'), crypto = require('node:crypto');
const {packets, audioSdp} = require('./assert-callback-confirmation-pcap.cjs');
const {phraseMatches} = require('./assert-announcement-audio.cjs');
const LOCAL = {ip: '127.0.0.20', sip: 15064, rtp: 43000};
function sip(packet) {
    const text = packet.payload.toString('latin1'), split = text.indexOf('\r\n\r\n');
    assert(split >= 0, 'Incomplete original SIP message');
    const lines = text.slice(0, split).split('\r\n'), first = lines.shift(), headers = {};
    for (const line of lines) {
        const match = /^([^:\s]+):\s*(.*)$/.exec(line);
        assert(match, 'Malformed original SIP header');
        (headers[match[1].toLowerCase()] ||= []).push(match[2].trim());
    }
    const one = key => {assert(headers[key]?.length === 1, 'Missing or ambiguous original SIP ' + key); return headers[key][0];};
    const callId = one('call-id'), seq = /^(\d+) (INVITE|ACK|BYE|CANCEL|OPTIONS|INFO|UPDATE)$/.exec(one('cseq'));
    assert(seq, 'Invalid original SIP CSeq');
    const body = text.slice(split + 4);
    assert(/^\d+$/.test(one('content-length')) && Number(one('content-length')) === Buffer.byteLength(body, 'latin1'),
        'Original SIP body length mismatch');
    const tag = key => {
        const matches = [...one(key).matchAll(/;tag=([^;\s]+)/g)];
        assert(matches.length <= 1, 'Ambiguous original SIP dialog tag');
        return matches[0]?.[1];
    };
    return {...packet, first, headers, callId, body, cseq: Number(seq[1]), method: seq[2], fromTag: tag('from'), toTag: tag('to')};
}
function unique(messages, label) {
    assert(messages.length, 'Missing original ' + label);
    const first = messages[0];
    assert(messages.every(item => item.callId === first.callId && item.cseq === first.cseq
        && item.body === first.body && item.fromTag === first.fromTag && item.toTag === first.toTag
        && item.src === first.src && item.dst === first.dst && item.sport === first.sport && item.dport === first.dport),
    'Ambiguous original ' + label);
    return messages.reduce((a, b) => a.time < b.time ? a : b);
}
function rtp(packet) {
    const body = packet.payload;
    assert(body.length >= 12 && body[0] >> 6 === 2, 'Invalid original RTP header');
    let start = 12 + (body[0] & 15) * 4;
    assert(start <= body.length, 'Truncated original RTP CSRC');
    if (body[0] & 16) {
        assert(start + 4 <= body.length, 'Truncated original RTP extension');
        start += 4 + 4 * body.readUInt16BE(start + 2);
    }
    const padding = body[0] & 32 ? body[body.length - 1] : 0;
    assert(!(body[0] & 32) || padding > 0, 'Invalid original RTP padding');
    assert(start < body.length - padding, 'Missing original RTP payload');
    return {...packet, payload: body.subarray(start, body.length - padding), pt: body[1] & 127,
        stamp: body.readUInt32BE(4), ssrc: body.readUInt32BE(8), sequence: body.readUInt16BE(2)};
}
function decode(byte) {
    const value = (~byte) & 255, sample = (((value & 15) << 3) + 132) << ((value >> 4) & 7);
    return value & 128 ? 132 - sample : sample - 132;
}
function fullPhrase(audio, reference) {
    assert(reference.length >= 32000 && reference.length <= 160000, 'Expected complete 4..20 second success reference');
    const candidates = phraseMatches(audio, reference.subarray(0, 24000)), matches = [];
    for (const candidate of candidates) {
        if (candidate.sample + reference.length > audio.length) continue;
        let dot = 0, ae = 0, re = 0;
        for (let i = 0; i < reference.length; i++) {
            const a = decode(audio[candidate.sample + i]), r = decode(reference[i]);
            dot += a * r; ae += a * a; re += r * r;
        }
        assert(re > 1e9, 'Silent success reference');
        const correlation = dot / Math.sqrt(ae * re);
        if (correlation >= 0.985) matches.push({sample: candidate.sample, correlation: Number(correlation.toFixed(6))});
    }
    return matches;
}
function inspect(buffer, reference, callId, ip = LOCAL.ip, sipPort = LOCAL.sip, mediaPort = LOCAL.rtp) {
    assert(ip === LOCAL.ip && sipPort === LOCAL.sip && mediaPort === LOCAL.rtp
        && /^1-[1-9][0-9]*@127\.0\.0\.20$/.test(callId), 'Not the exact original synthetic callback endpoint');
    assert(buffer.length <= 64 * 1024 * 1024, 'Oversized original capture');
    const all = packets(buffer), messages = [];
    const incoming = packet => packet.dst === ip && packet.dport === sipPort;
    const outgoing = packet => packet.src === ip && packet.sport === sipPort;
    for (const packet of all) {
        if ((!incoming(packet) && !outgoing(packet)) || !/^(?:SIP\/2\.0 |[A-Z]+ sip:)/.test(packet.payload.toString('latin1', 0, 20))) continue;
        const message = sip(packet);
        if (message.callId === callId) messages.push(message);
        else assert(message.method === 'OPTIONS', 'Another SIP dialog uses the original fixture port');
    }
    const answer = unique(messages.filter(m => incoming(m) && /^SIP\/2\.0 200 /.test(m.first) && m.method === 'INVITE'), 'INVITE answer');
    const offer = unique(messages.filter(m => outgoing(m) && m.first.startsWith('INVITE ') && m.cseq === answer.cseq), 'answered INVITE offer');
    const ack = unique(messages.filter(m => outgoing(m) && m.first.startsWith('ACK ') && m.cseq === answer.cseq), 'answer ACK');
    const bye = unique(messages.filter(m => incoming(m) && m.first.startsWith('BYE ')), 'server BYE');
    const byeAck = unique(messages.filter(m => outgoing(m) && /^SIP\/2\.0 200 /.test(m.first) && m.method === 'BYE' && m.cseq === bye.cseq), 'BYE acknowledgement');
    assert(offer.fromTag && answer.toTag && answer.fromTag === offer.fromTag
        && ack.fromTag === answer.fromTag && ack.toTag === answer.toTag
        && bye.fromTag === answer.toTag && bye.toTag === answer.fromTag
        && byeAck.fromTag === bye.fromTag && byeAck.toTag === bye.toTag, 'Original SIP dialog tags differ');
    assert(offer.dst === answer.src && offer.dport === answer.sport
        && ack.dst === answer.src && ack.dport === answer.sport
        && bye.src === answer.src && bye.sport === answer.sport
        && byeAck.dst === answer.src && byeAck.dport === answer.sport, 'Original SIP peer changed');
    assert(offer.time < answer.time && answer.time <= ack.time && ack.time < bye.time
        && bye.time <= byeAck.time && byeAck.time - bye.time <= 2 && bye.time - answer.time <= 45,
    'Original answer/ACK/server BYE order or deadline failed');
    assert(!messages.some(m => outgoing(m) && m.first.startsWith('BYE ')), 'Original caller ended itself');
    const local = audioSdp(offer), remote = audioSdp(answer);
    assert(local.ip === ip && local.port === mediaPort && local.payload === remote.payload, 'Original SDP endpoint or DTMF negotiation mismatch');
    for (const message of [offer, answer]) {
        const ranges = message.body.split(/\r?\n/).find(line => line.startsWith('a=fmtp:' + local.payload + ' '))
            .slice(('a=fmtp:' + local.payload + ' ').length).split(',');
        assert(ranges.some(range => {const [low, high = low] = range.split('-').map(Number); return low <= 6 && high >= 6;}),
            'Telephone event6 is not negotiated');
    }
    const toward = p => p.src === remote.ip && p.sport === remote.port && p.dst === ip && p.dport === mediaPort;
    const away = p => p.src === ip && p.sport === mediaPort && p.dst === remote.ip && p.dport === remote.port;
    const received = [], eventPackets = [];
    for (const packet of all) {
        if ((!toward(packet) && !away(packet)) || packet.time < answer.time || packet.time > bye.time) continue;
        const parsed = rtp(packet);
        if (toward(packet) && parsed.pt === 0) received.push(parsed);
        if (away(packet) && parsed.pt === local.payload) eventPackets.push(parsed);
    }
    const events = new Map();
    for (const packet of eventPackets) {
        assert(packet.payload.length === 4 && !(packet.payload[1] & 64), 'Malformed original telephone-event');
        const event = packet.payload[0], duration = packet.payload.readUInt16BE(2);
        // SIPp starts a legitimate RFC2833 event at duration0. Completion must
        // still demonstrate increasing duration and a nonzero end packet.
        assert([1, 6].includes(event), 'Unexpected original telephone-event digit');
        const key = [packet.ssrc, packet.stamp, event].join(':');
        const group = events.get(key) || []; group.push({...packet, event, duration, end: !!(packet.payload[1] & 128)}); events.set(key, group);
    }
    const digits = [...events.values()].map(group => {
        group.sort((a, b) => a.time - b.time);
        const end = group.find(p => p.end && p.duration >= 800);
        assert(!group[0].end && end && group[0].time < end.time && group.every((p, i) => !i || p.duration >= group[i - 1].duration),
            'Original digit was not completely sent');
        return {event: group[0].event, start: group[0].time, end: end.time};
    }).sort((a, b) => a.start - b.start);
    assert(digits.length === 2 && digits[0].event === 6 && digits[1].event === 1
        && digits[0].end < digits[1].start, 'Missing exact entry6 then same-number1');
    assert(digits[0].start - answer.time >= 4.75 && digits[0].start - answer.time <= 5.75,
        'Callback entry digit was not sent about5seconds after answer');
    assert(received.length >= 200 && new Set(received.map(p => p.ssrc)).size === 1, 'Missing or ambiguous received PCMU');
    received.sort((a, b) => a.time - b.time);
    const first = received[0], size = Math.max(...received.map(p => ((p.stamp - first.stamp) >>> 0) + p.payload.length));
    assert(size <= 45 * 8000, 'Original RTP timestamps exceed call bound');
    const audio = Buffer.alloc(size, 255), present = new Uint8Array(size), times = new Float64Array(size);
    for (const packet of received) {
        const start = (packet.stamp - first.stamp) >>> 0;
        assert(packet.payload.length <= 1600, 'Oversized PCMU packet');
        for (let i = 0; i < packet.payload.length; i++) {
            const index = start + i;
            assert(!present[index] || audio[index] === packet.payload[i], 'Conflicting original RTP overlap');
            if (!present[index]) {audio[index] = packet.payload[i]; present[index] = 1; times[index] = packet.time + i / 8000;}
        }
    }
    const matches = fullPhrase(audio, reference);
    assert(matches.length === 1, 'Expected exactly one complete registered-success prompt');
    const match = matches[0], endSample = match.sample + reference.length;
    assert(present.subarray(match.sample, endSample).every(Boolean), 'Success audio contains uncaptured samples');
    const start = times[match.sample], end = times[endSample - 1] + 1 / 8000;
    assert(start >= digits[1].end && end <= bye.time && bye.time - end <= 2,
        'Full registration success was not received after selection and before server BYE');
    assert(Math.abs((end - start) - reference.length / 8000) <= 0.25, 'Success RTP wall-clock duration does not match complete phrase');
    return {result: 'PASS', proof_kind: 'installed_prompt_pcm_delivery_not_human_transcription',
        prompt_id: 'en-us/acdc-callback-success', reference_sha256: crypto.createHash('sha256').update(reference).digest('hex'),
        reference_duration_seconds: reference.length / 8000, correlation: match.correlation,
        sip_answer_epoch_seconds: answer.time, entry_digit_epoch_seconds: digits[0].start,
        entry_after_answer_seconds: Number((digits[0].start - answer.time).toFixed(6)),
        confirmation_start_epoch_seconds: start, confirmation_end_epoch_seconds: end,
        original_bye_epoch_seconds: bye.time, original_bye_ack_epoch_seconds: byeAck.time,
        complete_phrase_before_server_bye: true, missing_phrase_samples: 0, received_pcmu_packets: received.length};
}
module.exports = {inspect, fullPhrase};
if (require.main === module) {
    try {
        assert(process.argv.length === 8, 'Usage: assert-callback-registration-audio.cjs PCAP REFERENCE_ULAW CALL_ID 127.0.0.20 15064 43000');
        const [pcap, reference, callId, ip, sipPort, mediaPort] = process.argv.slice(2);
        for (const [file, max] of [[pcap, 64 * 1024 * 1024], [reference, 160000]]) {
            const stat = fs.lstatSync(file);
            assert(stat.isFile() && !stat.isSymbolicLink() && stat.size > 0 && stat.size <= max, 'Unsafe or oversized original evidence file');
        }
        process.stdout.write(JSON.stringify(inspect(fs.readFileSync(pcap), fs.readFileSync(reference), callId, ip, Number(sipPort), Number(mediaPort))) + '\n');
    } catch (error) {process.stderr.write('Callback registration audio FAIL: ' + error.message + '\n'); process.exitCode = 1;}
}
