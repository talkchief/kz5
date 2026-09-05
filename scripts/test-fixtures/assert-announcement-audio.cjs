#!/usr/bin/env node
'use strict';
// Decodes only the exact synthetic acceptance caller's received PCMU stream.
// Correlates the complete known spoken prefix; packet counts alone cannot pass.
const fs = require('node:fs'), assert = require('node:assert/strict'), crypto = require('node:crypto');
function decode(byte) {
    const value = (~byte) & 255, sample = (((value & 15) << 3) + 132) << ((value >> 4) & 7);
    return (value & 128) ? 132 - sample : sample - 132;
}
function udpPackets(buffer) {
    assert(buffer.length >= 24 && buffer.length <= 32 * 1024 * 1024, 'Invalid capture length');
    const magic = buffer.subarray(0, 4).toString('hex');
    const little = ['d4c3b2a1', '4d3cb2a1'].includes(magic), nano = ['4d3cb2a1', 'a1b23c4d'].includes(magic);
    assert(little || ['a1b2c3d4', 'a1b23c4d'].includes(magic), 'Unknown pcap');
    const u32 = offset => little ? buffer.readUInt32LE(offset) : buffer.readUInt32BE(offset);
    const link = u32(20); assert([1, 113, 276].includes(link), 'Unknown link type');
    const packets = [];
    for (let offset = 24; offset < buffer.length;) {
        assert(offset + 16 <= buffer.length, 'Truncated record');
        const time = u32(offset) + u32(offset + 4) / (nano ? 1e9 : 1e6), length = u32(offset + 8);
        assert(offset + 16 + length <= buffer.length, 'Truncated packet');
        const packet = buffer.subarray(offset + 16, offset + 16 + length); offset += 16 + length;
        const ip = link === 1 ? 14 : link === 113 ? 16 : 20, proto = link === 1 ? 12 : link === 113 ? 14 : 0;
        if (packet.length < ip + 20 || packet.readUInt16BE(proto) !== 0x0800 || packet[ip + 9] !== 17) continue;
        assert((packet.readUInt16BE(ip + 6) & 0x3fff) === 0, 'Fragmented UDP');
        const udp = ip + (packet[ip] & 15) * 4; assert(udp + 8 <= packet.length);
        const size = packet.readUInt16BE(udp + 4); assert(size >= 8 && udp + size <= packet.length);
        packets.push({time, source: packet.subarray(ip + 12, ip + 16).join('.'), dest: packet.subarray(ip + 16, ip + 20).join('.'),
            sp: packet.readUInt16BE(udp), dp: packet.readUInt16BE(udp + 2), body: packet.subarray(udp + 8, udp + size)});
    }
    return packets;
}
function phraseMatches(audio, reference) {
    assert(reference.length >= 512 && reference.length <= 24000, 'Unexpected spoken-reference duration');
    const a = Float64Array.from(audio, decode), r = Float64Array.from(reference, decode), size = 256;
    let anchor = 0, anchorEnergy = 0, referenceEnergy = 0;
    for (const value of r) referenceEnergy += value * value;
    for (let index = 0; index + size <= r.length; index += size) {
        let energy = 0; for (let j = 0; j < size; j++) energy += r[index + j] ** 2;
        if (energy > anchorEnergy) {anchor = index; anchorEnergy = energy;}
    }
    assert(anchorEnergy > 1e8 && referenceEnergy > 1e9, 'Reference is silent');
    const candidates = new Set();
    const anchorBytes = reference.subarray(anchor, anchor + size);
    for (let position = audio.indexOf(anchorBytes); position !== -1; position = audio.indexOf(anchorBytes, position + 1)) {
        candidates.add(position - anchor);
    }
    if (!candidates.size) {
        const energies = new Float64Array(a.length + 1);
        for (let i = 0; i < a.length; i++) energies[i + 1] = energies[i] + a[i] ** 2;
        for (let i = anchor; i + r.length - anchor <= a.length; i++) {
            const energy = energies[i + size] - energies[i]; if (energy < 1e8) continue;
            let dot = 0; for (let j = 0; j < size; j++) dot += a[i + j] * r[anchor + j];
            if (dot / Math.sqrt(energy * anchorEnergy) >= 0.97) candidates.add(i - anchor);
        }
    }
    const matches = [];
    for (const start of Array.from(candidates).sort((x, y) => x - y)) {
        if (start < 0 || start + r.length > a.length || matches.some(match => Math.abs(match.sample - start) < 8000)) continue;
        let dot = 0, energy = 0;
        for (let j = 0; j < r.length; j++) {dot += a[start + j] * r[j]; energy += a[start + j] ** 2;}
        const score = dot / Math.sqrt(energy * referenceEnergy);
        if (score >= 0.985) matches.push({sample: start, correlation: Number(score.toFixed(6))});
    }
    return matches;
}
function inspect(buffer, reference, callId, ip, port, options = {}) {
    const packets = udpPackets(buffer), incoming = [];
    let answered = Infinity, bye = Infinity;
    for (const packet of packets) {
        const message = packet.body.toString('latin1');
        if (message.includes('\r\nCall-ID: ' + callId + '\r\n')) {
            if (message.startsWith('SIP/2.0 200') && /\r\nCSeq: \d+ INVITE\r\n/i.test(message)) answered = Math.min(answered, packet.time);
            if (message.startsWith('BYE ')) bye = Math.min(bye, packet.time);
        }
        const body = packet.body;
        if (packet.dest !== ip || packet.dp !== port || body.length < 12 || body[0] >> 6 !== 2 || (body[1] & 127) !== 0) continue;
        let start = 12 + (body[0] & 15) * 4;
        if (body[0] & 16) {assert(start + 4 <= body.length); start += 4 + 4 * body.readUInt16BE(start + 2);}
        const end = (body[0] & 32) ? body.length - body[body.length - 1] : body.length;
        assert(start <= end);
        incoming.push({time: packet.time, stamp: body.readUInt32BE(4), ssrc: body.readUInt32BE(8), payload: body.subarray(start, end)});
    }
    assert(Number.isFinite(answered) && Number.isFinite(bye), 'Missing exact caller answer/BYE');
    assert(bye - answered >= 70, 'Call did not last at least70seconds');
    assert(incoming.length >= 3000 && new Set(incoming.map(packet => packet.ssrc)).size === 1, 'Missing or ambiguous received audio');
    const first = incoming[0], length = Math.max(...incoming.map(packet => ((packet.stamp - first.stamp) >>> 0) + packet.payload.length));
    assert(length <= 960000, 'RTP timestamps exceed120seconds');
    const audio = Buffer.alloc(length, 255);
    for (const packet of incoming) packet.payload.copy(audio, (packet.stamp - first.stamp) >>> 0);
    const queueEntry = options.queueEntry === undefined ? answered : options.queueEntry;
    assert(Number.isFinite(queueEntry) && queueEntry >= answered - 10 && queueEntry <= answered + 10, 'Invalid queue-entry anchor');
    function wallTime(sample) {
        const packet = incoming.find(item => {
            const offset = (item.stamp - first.stamp) >>> 0;
            return offset <= sample && offset + item.payload.length > sample;
        });
        assert(packet, 'Matched speech sample has no received RTP packet');
        return packet.time + (sample - ((packet.stamp - first.stamp) >>> 0)) / 8000;
    }
    const matches = phraseMatches(audio, reference).map(match => ({...match,
        received_at: new Date(wallTime(match.sample) * 1000).toISOString(),
        after_answer_seconds: Number((wallTime(match.sample) - answered).toFixed(3)),
        after_queue_entry_seconds: Number((wallTime(match.sample) - queueEntry).toFixed(3))}));
    assert(matches.length === 2, `Expected exactly2 complete audible prefixes, found${matches.length}`);
    assert(matches[0].after_queue_entry_seconds >= 29.95 && matches[0].after_queue_entry_seconds <= 40,
        'First full prefix was not delayed30seconds: ' + JSON.stringify(matches));
    const interval = matches[1].after_answer_seconds - matches[0].after_answer_seconds;
    // The configured cadence schedules media commands, not packet arrival.
    // Explicit acceptance tolerance: ±250ms audible delivery jitter;50ms for
    // the first delay measured from the matched queue-entry log, not SIP200.
    assert(interval >= 29.75 && interval <= 30.25, 'Full prefix repeat spacing was not30seconds');
    assert(incoming.every(packet => packet.time <= bye + 1), 'Received RTP continued after hangup');
    let spokenPosition;
    if (options.digitReference) {
        const digits = phraseMatches(audio, options.digitReference);
        spokenPosition = matches.map(prefix => {
            const digit = digits.find(item => item.sample >= prefix.sample + reference.length - 160
                && item.sample <= prefix.sample + reference.length + 16000);
            assert(digit, 'Full spoken position one was not audible after the prefix');
            return {word: 'one', correlation: digit.correlation,
                after_prefix_seconds: Number(((digit.sample - prefix.sample) / 8000).toFixed(3))};
        });
    }
    return {result: 'PASS', received_rtp_packets: incoming.length, call_duration_seconds: Number((bye - answered).toFixed(3)),
        queue_entry_at: new Date(queueEntry * 1000).toISOString(), sip_answer_at: new Date(answered * 1000).toISOString(),
        initial_measurement_tolerance_ms: 50, repeat_delivery_tolerance_ms: 250,
        reference_sha256: crypto.createHash('sha256').update(reference).digest('hex'), full_prefix_matches: matches,
        spoken_position_matches: spokenPosition,
        repeat_spacing_seconds: Number(interval.toFixed(3)), received_rtp_stopped_after_bye: true};
}
function queueEntryEvidence(buffer, callId, expectedQueueId) {
    const date = new Date(udpPackets(buffer)[0].time * 1000).toISOString().slice(0, 10), found = [];
    const directory = '/var/log/kazoo/kazoo_apps/log';
    for (const name of fs.readdirSync(directory).filter(name => /^console\.log(\.[0-9]+)?$/.test(name))) {
        const file = directory + '/' + name;
        const lines = fs.readFileSync(file, 'utf8').split('\n');
        for (let index = 0; index < lines.length; index++) {
            const line = lines[index];
            if (!line.includes('|' + callId + '|acdc_queue_manager:')) continue;
            const match = line.match(/^(\d{2}:\d{2}:\d{2}\.\d{3}).*member call for queue ([a-f0-9]{32}) recv$/);
            if (match) found.push({source: file, line: index + 1, call_id: callId, queue_id: match[2], entry_at: date + 'T' + match[1] + 'Z'});
        }
    }
    assert.equal(found.length, 1, 'Exactly one call-scoped queue-entry log is required');
    assert.equal(found[0].queue_id, expectedQueueId, 'Queue-entry log does not belong to the exact temporary queue');
    return found[0];
}
module.exports = {udpPackets, phraseMatches, inspect};
if (require.main === module) {
    try {
        const [pcap, reference, callId, ip, port, run, digitReference] = process.argv.slice(2);
        const buffer = fs.readFileSync(pcap), entryPath = run + '/announcement-queue-entry.json';
        const queue = JSON.parse(fs.readFileSync(run + '/announcement-queue-before.json'));
        assert(/^[a-f0-9]{32}$/.test(queue.id) && /^acdc-announcement-[a-f0-9]{16}$/.test(queue.kazoo_acceptance_fixture));
        let entry = fs.existsSync(entryPath) ? JSON.parse(fs.readFileSync(entryPath)) : null;
        if (!entry || !entry.call_id) entry = queueEntryEvidence(buffer, callId, queue.id);
        assert.equal(entry.call_id, callId, 'Cached queue-entry evidence belongs to another call');
        assert.equal(entry.queue_id, queue.id, 'Cached queue-entry evidence belongs to another queue');
        fs.writeFileSync(entryPath, JSON.stringify(entry, null, 2) + '\n', {mode: 0o600});
        const result = inspect(buffer, fs.readFileSync(reference), callId, ip, Number(port), {
            queueEntry: Date.parse(entry.entry_at) / 1000,
            ...(digitReference ? {digitReference: fs.readFileSync(digitReference)} : {})});
        const workers = name => new Set(fs.readFileSync(run + '/announcement-workers-' + name + '.txt', 'utf8').match(/<\d+\.\d+\.\d+>/g) || []);
        const before = workers('before'), during = workers('during'), after = workers('after');
        const added = [...during].filter(pid => !before.has(pid));
        assert(added.length === 1 && !after.has(added[0]), 'Owned announcement worker did not disappear after BYE');
        result.new_announcement_worker_terminated = true;
        console.log(JSON.stringify(result));
    } catch (error) {console.error('Announcement audio FAIL: ' + error.message); process.exitCode = 1;}
}
