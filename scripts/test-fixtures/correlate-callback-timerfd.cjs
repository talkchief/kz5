'use strict';
// Offline correlation only; does not rewrite a strict failure or its inputs.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const media = require('./assert-callback-confirmation-pcap.cjs');
const returned = require('./assert-callback-returned-audio.cjs');
const { diagnose } = require('./diagnose-callback-language-payload.cjs');
const [run, traceFile] = process.argv.slice(2);
assert.equal(process.argv.length, 4);
assert(/^\/var\/log\/kazoo-acceptance\/[0-9]{8}T[0-9]{6}Z$/.test(run));
assert(/^\/root\/kz5-acceptance\/callback-rtp-trace-[a-zA-Z0-9-]+\.log$/.test(traceFile));
const trace = fs.readFileSync(traceFile);
assert(trace.length < 16 * 1024 * 1024);
const text = trace.toString();
assert(/^TRACE_READY$/m.test(text) && /^TRACE_END$/m.test(text));
assert(text.includes('"trace_exit":0,"signal":null'));
assert(!/lost [1-9][0-9]* events|dropped [1-9][0-9]* events/i.test(text));
const entries = text.split('\n').filter(line => line.startsWith('RTP_TIMER ')).map(line => {
    const pairs = line.slice(10).split(' ').map(field => {
        const match = /^([a-z_]+)=(-?[0-9]+)$/.exec(field);
        assert(match); const value = Number(match[2]); assert(Number.isSafeInteger(value));
        return [match[1], value];
    });
    return Object.fromEntries(pairs);
});
assert(entries.length > 0);
const payload = diagnose(run, 'deadline');
assert.equal(payload.strict_audio_timing_passed, false);
const capture = fs.readFileSync(path.join(run, 'retry-returned.pcap'));
const packets = media.packets(capture);
const bridge = JSON.parse(fs.readFileSync(path.join(run, 'retry-bridge-evidence.json')));
const ack = Math.min(...packets.filter(p => p.dst === '127.0.0.20' && p.dport === 16060 &&
    p.payload.toString().startsWith('ACK ') &&
    p.payload.toString().includes('\r\nCall-ID: ' + bridge.caller.sip_call_id + '\r\n')).map(p => p.time));
assert(Number.isFinite(ack));
const digit = ack + payload.digit_after_ack_seconds;
const frames = packets.filter(p => p.dst === '127.0.0.20' && p.dport === 44000 && p.time >= ack && p.time < digit)
    .map(returned.rtp);
assert(frames.every(p => p.pt === 0));
const correlations = [];
for (let i = 1; i < frames.length; i++) {
    const before = frames[i - 1], after = frames[i];
    const delta = (after.stamp - before.stamp) >>> 0;
    if (delta === before.audio.length) continue;
    const found = entries.filter(e => e.ssrc === after.ssrc && e.before === before.stamp && e.after === after.stamp);
    assert.equal(found.length, 1, 'Every packet timestamp gap needs one exact runtime transition');
    const e = found[0];
    assert.equal(e.delta, delta); assert.equal(e.interval, before.audio.length);
    assert.equal(e.reads, 1); assert.equal(e.read_result, 8); assert.equal(e.timer_status, 0);
    assert(e.expirations > 1);
    assert.equal(e.tick_after - e.tick_before, e.expirations);
    assert.equal(e.samples_after - e.samples_before, e.expirations * e.interval);
    assert.equal(e.after, e.samples_after); assert.equal(e.marker, 1);
    assert.equal(after.payload[1] >> 7, 1);
    correlations.push({ ...e, extra_clock_ms: (delta - before.audio.length) / 8,
        packet_arrival_delta_ms: (after.time - before.time) * 1000 });
}
assert.equal(correlations.length, payload.rtp_timestamp_gaps.length);
assert(correlations.length > 0);
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const result = { scope: 'callback-runtime-timerfd-correlation', runtime_transition_proven: true,
    root_cause_of_delayed_timer_read_proven: false, strict_failure_reclassified: false,
    instrumentation_map_cleanup_warnings: (text.match(/Can't delete map element/g) || []).length,
    performance_acceptance: false, trace_sha256: sha(trace), capture_sha256: sha(capture),
    correlations, payload };
fs.writeFileSync(path.join(run, 'callback-timerfd-correlation.json'), JSON.stringify(result, null, 2) + '\n',
    { flag: 'wx', mode: 0o600 });
console.log(JSON.stringify(result));
