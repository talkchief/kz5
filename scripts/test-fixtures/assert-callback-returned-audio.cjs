'use strict';
// Additive offline replay. Does not modify or replace an earlier PASS receipt.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const reference=require('./callback-returned-reference.cjs');
const ACCOUNT='7807ad61761269a1ccec833dde63f621';
function dependencies(root){assert(path.isAbsolute(root)&&fs.realpathSync(root)===root);return {media:require(path.join(root,'scripts/test-fixtures/assert-callback-confirmation-pcap.cjs')),
    phrase:require(path.join(root,'scripts/test-fixtures/assert-callback-registration-audio.cjs')).fullPhrase,
    retry:require(path.join(root,'scripts/test-fixtures/assert-callback-retry.cjs')),
    captureLog:require(path.join(root,'scripts/test-fixtures/assert-callback-offer-audio.cjs')).assertCaptureLog,
    probe:require(path.join(root,'scripts/probe-acdc-prerecorded-runtime.cjs'))};}
function sip(packet){
    const text=packet.payload.toString('latin1'),end=text.indexOf('\r\n\r\n');assert(end>=0);
    const lines=text.slice(0,end).split('\r\n'),first=lines.shift(),headers={};
    for(const line of lines){const m=/^([^:\s]+):\s*(.*)$/.exec(line);assert(m);(headers[m[1].toLowerCase()]||=[]).push(m[2].trim());}
    const one=k=>{assert.equal(headers[k]?.length,1);return headers[k][0];};
    const callId=one('call-id'),cseq=/^(\d+) (INVITE|ACK)$/.exec(one('cseq')),body=text.slice(end+4);
    assert(cseq&&/^\d+$/.test(one('content-length'))&&Number(one('content-length'))===Buffer.byteLength(body,'latin1'));
    return {...packet,first,headers,body,callId,cseq:Number(cseq[1]),method:cseq[2]};
}
function transaction(messages){
    assert(messages.length>0);const first=messages[0];
    assert(messages.every(m=>m.callId===first.callId&&m.cseq===first.cseq&&m.body===first.body));
    return messages.reduce((a,b)=>a.time<b.time?a:b);
}
function rtp(packet){
    const b=packet.payload;assert(b.length>=12&&b[0]>>6===2);let offset=12+4*(b[0]&15);assert(offset<=b.length);
    if(b[0]&16){assert(offset+4<=b.length);offset+=4+4*b.readUInt16BE(offset+2);}
    const pad=b[0]&32?b.at(-1):0;assert(!(b[0]&32)||pad>0);assert(offset<b.length-pad);
    return {...packet,pt:b[1]&127,stamp:b.readUInt32BE(4),ssrc:b.readUInt32BE(8),audio:b.subarray(offset,b.length-pad)};
}
function inspect(buffer,raw,proof,payload,transport,deps){
    assert(Buffer.isBuffer(buffer)&&buffer.length>24&&buffer.length<=16*1024*1024);
    assert(Buffer.isBuffer(raw)&&raw.length>=32000&&raw.length<=80000);
    // Preserve the established caller digit1 -> agent origination and bridge
    // transport gate, independently recomputed from the same saved capture.
    const prior=deps.media.inspect(buffer,proof,payload,transport),all=deps.media.packets(buffer);
    const ip=transport==='internal'?'127.0.0.20':'127.0.0.30';assert(['internal','external'].includes(transport));
    const messages=all.filter(p=>(p.sport===16060||p.dport===16060)
        &&/\r\nCSeq:\s*\d+ (INVITE|ACK)\r\n/i.test(p.payload.toString('latin1',0,Math.min(p.payload.length,8192)))).map(sip);
    assert(messages.every(m=>m.callId===proof.callerCallId),'Unexpected returned dialog');
    const offer=transaction(messages.filter(m=>m.dst===ip&&m.dport===16060&&m.first.startsWith('INVITE ')));
    const answer=transaction(messages.filter(m=>m.src===ip&&m.sport===16060&&m.first.startsWith('SIP/2.0 200 ')));
    const ack=transaction(messages.filter(m=>m.dst===ip&&m.dport===16060&&m.first.startsWith('ACK ')));
    const remote=deps.media.audioSdp(offer),local=deps.media.audioSdp(answer);
    assert(local.ip===ip&&local.port===44000&&remote.payload===payload);
    const digits=all.filter(p=>p.src===local.ip&&p.sport===local.port&&p.dst===remote.ip&&p.dport===remote.port)
        .map(rtp).filter(p=>p.pt===payload&&p.audio[0]===1&&p.time>=ack.time);
    assert(digits.length>0);const digitAt=Math.min(...digits.map(p=>p.time));
    assert(digitAt>ack.time&&digitAt-ack.time<=15,'Unbounded returned confirmation window');
    const incoming=all.filter(p=>p.dst===local.ip&&p.dport===local.port&&p.time>=ack.time&&p.time<digitAt).map(p=>{
        assert(p.src===remote.ip&&p.sport===remote.port,'Foreign returned audio source');const r=rtp(p);
        assert(r.pt===0,'Returned prompt is not PCMU');return r;
    }).sort((a,b)=>a.time-b.time);
    assert(incoming.length>=200&&new Set(incoming.map(p=>p.ssrc)).size===1,'Missing or ambiguous returned audio');
    const base=incoming[0].stamp;let length=0;
    for(const p of incoming)length=Math.max(length,((p.stamp-base)>>>0)+p.audio.length);
    assert(length>0&&length<=15*8000,'Unbounded returned audio timeline');
    const audio=Buffer.alloc(length,255),covered=new Uint8Array(length),times=new Float64Array(length);
    for(const p of incoming){const start=(p.stamp-base)>>>0;
        for(let i=0;i<p.audio.length;i++){assert(!covered[start+i]||audio[start+i]===p.audio[i],'Conflicting duplicate RTP');
            if(!covered[start+i])times[start+i]=p.time+i/8000;audio[start+i]=p.audio[i];covered[start+i]=1;}}
    assert(covered.every(Boolean),'Missing RTP in returned confirmation window');
    const matches=deps.phrase(audio,raw);assert.equal(matches.length,1,'Missing, repeated or truncated full returned phrase');
    const match=matches[0],end=match.sample+raw.length;
    assert(end<=length&&covered.subarray(match.sample,end).every(Boolean));
    const startAt=times[match.sample],endAt=times[end-1]+1/8000;
    assert(startAt>=ack.time&&endAt<=digitAt,'Full returned phrase did not finish before digit1');
    // Capture arrival jitter may make adjacent packet sample times overlap;
    // sequence completeness comes from RTP timestamps, not arrival spacing.
    for(let i=match.sample+1;i<end;i++)assert(Math.abs(times[i]-times[i-1]-1/8000)<.3,'Returned audio time discontinuity');
    assert(Math.abs(endAt-startAt-raw.length/8000)<.3,'Returned audio duration discontinuity');
    return {returned_confirmation_verified:true,phrase_samples:raw.length,correlation:match.correlation,
        start_after_ack_seconds:startAt-ack.time,end_after_ack_seconds:endAt-ack.time,
        completion_before_digit_seconds:digitAt-endAt,existing_returned_gate:prior};
}
function replay(run,runPin,language,referenceDirectory,referencePin,output,sourceRoot=path.resolve(__dirname,'../..')){
    reference.locale(language);assert(/^[a-f0-9]{64}$/.test(runPin)&&/^[a-f0-9]{64}$/.test(referencePin));
    assert(path.isAbsolute(run)&&fs.realpathSync(run)===run&&/^\/var\/log\/kazoo-acceptance\/[0-9]{8}T[0-9]{6}Z$/.test(run));
    const deps=dependencies(sourceRoot),pins={},contents={};
    const read=(name,limit=128*1024)=>{const b=reference.read(path.join(run,name),limit);pins[name]=reference.sha(b);contents[name]=b;return b;};
    const json=name=>JSON.parse(read(name));
    const saved=json('retry-packet-evidence.json');assert.equal(pins['retry-packet-evidence.json'],runPin);
    assert(saved.scenario==='busy-agent-unanswered-first-callback-retry'&&saved.account_id===ACCOUNT
        &&saved.attempts===2&&saved.durable_retry_wait===true&&saved.retained_fixture===true&&saved.full_cleanup_acceptance===false
        &&(saved.confirmation_language===language||language==='en-us'&&saved.confirmation_language===undefined)
        &&saved.confirmation_prompt_id.startsWith(language+'/acdc-callback-success-gemini-sulafat-'));
    const evidence={registered:json('callback-registration-evidence.json'),first:json('retry-first-attempt.json'),
        backoff:json('retry-backoff-evidence.json'),bridged:json('retry-bridge-evidence.json'),busy:json('retry-busy-before-release.json'),
        audio:json('retry-registration-audio.json'),release:Number(read('retry-busy-release-epoch.txt',128).toString().trim())};
    assert.deepEqual(evidence.audio,saved.original_registration_audio);
    const proof=deps.retry.lifecycle(evidence,saved.transport);
    deps.captureLog(read('retry-returned-capture.log',65536).toString());
    const payload=deps.media.negotiatedPayload(read('callback-carrier-negotiation.log',8192).toString());
    const capture=read('retry-returned.pcap',16*1024*1024),ref=reference.load(referenceDirectory,referencePin,language,sourceRoot);
    const waveform=inspect(capture,ref.raw,proof,payload,saved.transport,deps);
    assert.deepEqual(waveform.existing_returned_gate,saved.second_attempt,'Replayed transport result differs from the original proof');
    // No saved input is rewritten, and all bytes are re-pinned before output.
    for(const [name,digest] of Object.entries(pins))assert.equal(reference.sha(reference.read(path.join(run,name),contents[name].length)),digest);
    assert.equal(reference.sha(reference.read(path.join(referenceDirectory,'reference.json'))),referencePin);
    assert.equal(reference.sha(reference.read(path.join(referenceDirectory,'returned-confirmation.ulaw'))),ref.receipt.ulaw_sha256);
    const result={schema_version:1,scope:'additive-returned-confirmation-waveform-replay',language,account_id:ACCOUNT,
        original_pass_sha256:runPin,input_sha256:pins,reference_receipt_sha256:referencePin,reference:ref.receipt,
        registration_mode:saved.registration_mode,...waveform,persisted_language_verified:false,
        historical_persisted_language_verified:false,native_listening_approved:false,full_language_ready:false,
        observed_at:new Date().toISOString()};
    deps.probe.createEvidence(output,Buffer.from(JSON.stringify(result,null,2)+'\n'));return result;
}
module.exports={inspect,replay,dependencies,rtp,sip};
if(require.main===module){try{
    const [action,run,pin,language,refdir,refpin,output,sourceRoot]=process.argv.slice(2);
    assert(action==='replay'&&[9,10].includes(process.argv.length));
    const r=replay(run,pin,language,refdir,refpin,output,sourceRoot);
    console.log(JSON.stringify({result:'PASS',language:r.language,returned_confirmation_verified:true,persisted_language_verified:false}));
}catch{console.error('Returned confirmation replay failed safely; original evidence unchanged.');process.exitCode=1;}}
