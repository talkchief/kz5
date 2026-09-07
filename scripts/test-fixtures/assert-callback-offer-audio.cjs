'use strict';
// Exact-dialog/negotiated-peer proof for the isolated2098 offer timing call.
const fs = require('node:fs'), assert = require('node:assert/strict'), crypto = require('node:crypto');
const {packets, audioSdp} = require('./assert-callback-confirmation-pcap.cjs');
const {phraseMatches} = require('./assert-announcement-audio.cjs');
const sha = data => crypto.createHash('sha256').update(data).digest('hex');
function assertCaptureLog(text) {
    assert(typeof text === 'string' && text.length <= 65536, 'Invalid capture completion log');
    const values = {};
    for (const field of ['captured', 'received by filter', 'dropped by kernel']) {
        const matches = [...text.matchAll(new RegExp('^([0-9]+) packets ' + field + '$', 'gm'))];
        assert(matches.length === 1, 'Missing or ambiguous capture completion: ' + field);
        values[field] = Number(matches[0][1]);
        assert(Number.isSafeInteger(values[field]), 'Invalid capture packet count');
    }
    assert(values.captured > 0 && values['received by filter'] > 0, 'Empty capture');
    assert(values['dropped by kernel'] === 0, 'Capture loss makes absence evidence inconclusive');
}
function decode(byte) { const x = ~byte & 255, s = (((x & 15) << 3) + 132) << ((x >> 4) & 7); return x & 128 ? 132 - s : s - 132; }
function completeMatches(audio, reference) {
    assert(reference.length >= 512 && reference.length < 7 * 8000, 'Installed reference must be audible and shorter than7seconds');
    const candidates = phraseMatches(audio, reference.subarray(0, 24000));
    return candidates.filter(match => {
        if (match.sample + reference.length > audio.length) return false;
        let dot = 0, a = 0, b = 0;
        for (let i = 0; i < reference.length; i++) { const x = decode(audio[match.sample+i]), y = decode(reference[i]); dot += x*y; a += x*x; b += y*y; }
        match.correlation = dot / Math.sqrt(a*b); return match.correlation >= .985;
    });
}
function assertGeminiEntrySilence(audio,times,anchor) {
    // Offer onset permits +/-1s around its configured3s deadline. Inspect only
    // [entry,entry+2s), never the legitimate earliest onset at entry+2s.
    // PCMU silence/quiet comfort noise is allowed, as are at most two20ms
    // energetic windows (brief transients). This is a quantified early-audio
    // check, not a claim of bit-perfect silence or acoustic speaker review.
    const windowSamples=160, rmsLimit=256, allowedEnergeticWindows=2;
    let count=0,energy=0,inWindow=0,energetic=0,maxRms=0,first,last;
    for(let i=0;i<audio.length;i++) {
        if(times[i]<anchor||times[i]>=anchor+2)continue;
        if(first===undefined)first=times[i];last=times[i];count++;
        energy+=decode(audio[i])**2;inWindow++;
        if(inWindow===windowSamples) {
            const rms=Math.sqrt(energy/windowSamples);maxRms=Math.max(maxRms,rms);
            if(rms>rmsLimit)energetic++;
            energy=0;inWindow=0;
        }
    }
    // With capture beginning before INVITE, zero kernel drops (CLI prerequisite)
    // and the full observed RTP stream covered, allow <=100ms before first RTP.
    // That initial interval is a no-RTP startup gap, NOT observed silence.
    // A later capture or longer startup is still refused; speech-energy and
    // scheduled-onset limits above are unchanged.
    const observation={samples:count,
        first_after_queue_entry_seconds:first===undefined?null:Number((first-anchor).toFixed(6)),
        last_after_queue_entry_seconds:last===undefined?null:Number((last-anchor).toFixed(6))};
    assert(count>=15200&&count<=16160&&first<=anchor+.1&&last>=anchor+1.98,
        'Insufficient Gemini entry-silence observation: '+JSON.stringify(observation));
    if(inWindow&&Math.sqrt(energy/inWindow)>rmsLimit)energetic++;
    assert(energetic<=allowedEnergeticWindows,'Unexpected energetic audio before Gemini offer window');
    return {start_after_queue_entry_seconds:0,end_after_queue_entry_seconds:2,
        ...observation,allowed_startup_gap_ms:100,
        pre_rtp_gap_seconds:Number(Math.max(0,times[0]-anchor).toFixed(6)),
        startup_gap_is_observed_silence:false,
        rms_limit_pcm16:rmsLimit,window_ms:20,allowed_energetic_windows:allowedEnergeticWindows,
        observed_energetic_windows:energetic,max_full_window_rms:Number(maxRms.toFixed(3))};
}
function sip(packet) {
    const text = packet.payload.toString('latin1'), split = text.indexOf('\r\n\r\n');
    assert(split >= 0, 'Incomplete SIP message');
    const lines = text.slice(0, split).split('\r\n'), first = lines.shift(), headers = {};
    for (const line of lines) { const m = /^([^:\s]+):\s*(.*)$/.exec(line); assert(m, 'Malformed SIP header'); (headers[m[1].toLowerCase()] ||= []).push(m[2]); }
    const one = key => { assert(headers[key]?.length === 1, 'Missing/duplicate SIP ' + key); return headers[key][0]; };
    const seq = /^(\d+) ([A-Z]+)$/.exec(one('cseq')), body = text.slice(split+4);
    assert(seq && Number(one('content-length')) === Buffer.byteLength(body, 'latin1'), 'Invalid SIP sequence/body');
    const tag = key => /(?:^|;)tag=([^;\s]+)/.exec(one(key))?.[1];
    return {...packet, first, headers, body, callId: one('call-id'), method: seq[2], seq: Number(seq[1]), from: tag('from'), to: tag('to')};
}
function inspect(buffer, refs, expected) {
    const mode=expected.audio_mode===undefined?'legacy':expected.audio_mode;
    assert(['legacy','gemini'].includes(mode),'Unexpected offer audio mode');
    if(mode==='gemini')assert(refs.offer.length>5*8000&&refs.offer.length<7*8000,
        'Gemini probe requires the complete longer-than-five-second offer');
    assert(buffer.length <= 32*1024*1024 && /^[a-f0-9]{32}$/.test(expected.queue_id), 'Invalid fixture capture/queue');
    assert(expected.ip === '127.0.0.20' && expected.sip_port === 15064 && expected.media_port === 47200
        && /^1-[1-9][0-9]*@127\.0\.0\.20$/.test(expected.call_id), 'Unexpected fixture endpoint');
    const all = packets(buffer), messages = [];
    for (const packet of all) {
        const endpoint = (packet.src === expected.ip && packet.sport === expected.sip_port)
            || (packet.dst === expected.ip && packet.dport === expected.sip_port);
        if (!endpoint || !/^(SIP\/2\.0 |[A-Z]+ sip:)/.test(packet.payload.toString('latin1', 0, 20))) continue;
        const message = sip(packet);
        assert(message.callId === expected.call_id || message.method === 'OPTIONS', 'Foreign dialog on reserved fixture SIP port');
        if (message.callId === expected.call_id) messages.push(message);
    }
    function select(predicate, label) {
        const found = messages.filter(predicate); assert(found.length, 'Missing ' + label);
        const first = found[0]; assert(found.every(m => m.payload.equals(first.payload)), 'Ambiguous ' + label);
        return found.reduce((a,b) => a.time < b.time ? a : b);
    }
    const answer = select(m => /^SIP\/2.0 200 /.test(m.first) && m.method === 'INVITE', 'INVITE200');
    assert(messages.every(m => ['INVITE','ACK','BYE','OPTIONS'].includes(m.method)), 'Unexpected SIP method/DTMF registration');
    const invite = select(m => /^INVITE /.test(m.first) && m.seq === answer.seq, 'answered INVITE');
    const ack = select(m => /^ACK /.test(m.first) && m.seq === answer.seq && m.to === answer.to, 'dialog ACK');
    const bye = select(m => /^BYE /.test(m.first), 'BYE');
    const done = select(m => /^SIP\/2.0 200 /.test(m.first) && m.method === 'BYE' && m.seq === bye.seq, 'BYE200');
    assert(invite.from && answer.to && invite.from === answer.from && ack.from === answer.from && bye.from === answer.from && bye.to === answer.to
        && done.from === bye.from && done.to === bye.to, 'Dialog tags disagree');
    assert(invite.src === expected.ip && ack.src === expected.ip && bye.src === expected.ip && answer.dst === expected.ip,
        'Caller must originate and normally end the exact call');
    assert(bye.time-answer.time >= 45 && bye.time-answer.time <= 52 && done.time >= bye.time, 'Unexpected call duration/teardown');
    const local = audioSdp(invite, false), remote = audioSdp(answer, false);
    assert(local.ip === expected.ip && local.port === expected.media_port
        && (remote.ip.startsWith('127.') || (expected.local_engine_ips || []).includes(remote.ip)), 'Non-local negotiated media');
    const incoming = [];
    for (const packet of all) {
        if (packet.src === local.ip && packet.sport === local.port) {
            assert(packet.dst === remote.ip && packet.dport === remote.port && packet.payload.length >= 12
                && packet.payload[0] >> 6 === 2 && (packet.payload[1]&127) === 0, 'Outbound media left local dialog or sent DTMF');
        }
        if (packet.dst !== local.ip || packet.dport !== local.port) continue;
        const b = packet.payload; assert(packet.src === remote.ip && packet.sport === remote.port, 'Foreign RTP sender');
        assert(b.length >= 12 && b[0] >> 6 === 2 && (b[1]&127) === 0, 'Invalid/non-PCMU received RTP');
        let start = 12 + 4*(b[0]&15); assert(start <= b.length, 'Truncated RTP');
        if (b[0]&16) { assert(start+4 <= b.length); start += 4+4*b.readUInt16BE(start+2); }
        const padding = b[0]&32 ? b.at(-1) : 0; assert(!(b[0]&32) || padding > 0);
        assert(start < b.length-padding && packet.time <= bye.time+1, 'Invalid/post-hangup RTP');
        incoming.push({...packet, stamp: b.readUInt32BE(4), ssrc: b.readUInt32BE(8), audio: b.subarray(start,b.length-padding)});
    }
    assert(incoming.length > 1500 && new Set(incoming.map(p => p.ssrc)).size === 1, 'Insufficient/ambiguous media stream');
    const base = incoming[0].stamp, length = Math.max(...incoming.map(p => ((p.stamp-base)>>>0)+p.audio.length));
    assert(length <= 55*8000, 'Invalid media timeline');
    const audio = Buffer.alloc(length,255), covered = new Uint8Array(length), times = new Float64Array(length);
    for (const p of incoming) {
        const offset = (p.stamp-base)>>>0;
        for (let j=0;j<p.audio.length;j++) { assert(!covered[offset+j] || audio[offset+j] === p.audio[j], 'Conflicting duplicate RTP');
            if (!covered[offset+j]) times[offset+j] = p.time+j/8000; covered[offset+j]=1; audio[offset+j]=p.audio[j]; }
    }
    // Absence claims (no offer on entry or extra offer between expected ones)
    // require the whole observed stream, not just the matching phrases.
    assert(covered.every(Boolean), 'Missing RTP in observed announcement timeline');
    const anchor = expected.queue_entry;
    assert(Number.isFinite(anchor) && Math.abs(anchor-answer.time)<5, 'Missing exact queue-entry anchor');
    const entrySilence=mode==='gemini'?assertGeminiEntrySilence(audio,times,anchor):undefined;
    const result = {};
    const targetsByName=mode==='gemini'?[['offer',[3,18,33]]]:[['offer',[3,18,33]], ['position',[11,26,41]]];
    for (const [name, targets] of targetsByName) {
        const reference = refs[name], matches = completeMatches(audio,reference);
        assert(matches.length === 3, 'Expected exactly3 complete '+name+' phrases, found'+matches.length);
        result[name] = matches.map((m,i) => {
            assert(covered.subarray(m.sample,m.sample+reference.length).every(Boolean), 'Missing RTP inside full '+name+' phrase');
            const delay = times[m.sample]-anchor;
            assert(Math.abs(delay-targets[i])<=1, 'Wrong '+name+' schedule; observed '+delay.toFixed(3));
            assert(Math.abs(times[m.sample+reference.length-1]-times[m.sample]-(reference.length-1)/8000)<.3, 'Audio wall-clock continuity failed');
            return {after_queue_entry_seconds:Number(delay.toFixed(3)), correlation:Number(m.correlation.toFixed(6)),
                complete_end_after_queue_entry_seconds:Number((times[m.sample+reference.length-1]-anchor+1/8000).toFixed(3))};
        });
        result[name+'_reference_sha256'] = sha(reference);
    }
    return {result:'PASS',...result, audio_mode:mode,scope:mode==='gemini'?'offer_only_silence_hold':'legacy_dual_schedule',
        ...(mode==='gemini'?{entry_silence:entrySilence}:{}),
        position_verified:mode==='legacy',offer_duration_seconds:refs.offer.length/8000,
        expected_offer_seconds:[3,18,33], expected_position_seconds:mode==='gemini'?[]:[11,26,41],
        delivery_tolerance_seconds:1, no_offer_on_entry:true, exact_negotiated_received_pcmu:true, complete_audio_coverage:true,
        call_duration_seconds:Number((bye.time-answer.time).toFixed(3)), normal_sip_teardown:true};
}
function assertReferenceReceipt(receipt,refs,mode='legacy') {
    assert(['legacy','gemini'].includes(mode),'Unexpected offer audio mode');
    if(mode==='gemini') {
        assert(receipt.audio_mode==='gemini'&&receipt.scope==='offer_only_silence_hold'&&receipt.position_verified===false);
        const r=receipt.offer;
        assert(r&&r.installed_callback_assets_verified===42&&r.canonical_prompt_id==='acdc-callback-offer-6'
            &&/^[a-f0-9]{64}$/.test(r.wav_sha256)&&/^[1-9][0-9]*-[a-f0-9]{32}$/.test(r.revision));
        const prompt='acdc-callback-offer-6-gemini-sulafat-'+r.wav_sha256.slice(0,16);
        assert(r.document_id==='en-us/'+prompt&&r.attachment===prompt+'.wav'
            &&r.immutable_path==='/system_media/'+r.document_id,'Not the immutable built-in offer');
        assert(r.duration_seconds>5&&r.duration_seconds<7&&Math.abs(refs.offer.length/8000-r.duration_seconds)<.001);
    } else assert(receipt.audio_mode===undefined||receipt.audio_mode==='legacy','Legacy proof cannot use a Gemini-only receipt');
    for(const key of mode==='gemini'?['offer']:['offer','position'])
        assert(sha(refs[key])===receipt[key].ulaw_sha256,'Installed reference receipt mismatch');
}
module.exports = {inspect, completeMatches, assertCaptureLog,assertReferenceReceipt,assertGeminiEntrySilence};
if (require.main === module) {
    try {
        const run = process.argv[2], read = name => { const p=run+'/'+name,s=fs.lstatSync(p); assert(s.isFile()&&!s.isSymbolicLink()&&s.uid===0&&(s.mode&511)===384); return fs.readFileSync(p); };
        assertCaptureLog(read('offer-capture.log').toString('utf8'));
        const expected = JSON.parse(read('offer-call.json')), fixture = JSON.parse(read('offer-fixture.json'));
        assert(expected.queue_id===fixture.queue_id && expected.account===fixture.account);
        expected.audio_mode=fixture.audio_mode===undefined?'legacy':fixture.audio_mode;
        const evidence=JSON.parse(read('offer-queue-entry.json')); assert(evidence.call_id===expected.call_id && evidence.queue_id===expected.queue_id);
        expected.queue_entry=Date.parse(evidence.entry_at)/1000;
        expected.local_engine_ips=Object.values(require('node:os').networkInterfaces()).flat().filter(x=>x.family==='IPv4').map(x=>x.address);
        const receipt=JSON.parse(read('offer-reference-receipt.json')),refs={offer:read('offer-reference.ulaw')};
        if(expected.audio_mode==='legacy')refs.position=read('position-reference.ulaw');
        assertReferenceReceipt(receipt,refs,expected.audio_mode);
        console.log(JSON.stringify(inspect(read('offer-rtp.pcap'),refs,expected)));
    } catch(error) {console.error('Callback offer audio FAIL: '+error.message);process.exitCode=1;}
}
