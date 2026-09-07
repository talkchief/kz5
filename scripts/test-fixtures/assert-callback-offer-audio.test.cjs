'use strict';
// Synthetic exact-dialog SIP/RTP PCAP; does not call SIPp or any live service.
const assert=require('node:assert/strict'),{inspect,assertCaptureLog,assertReferenceReceipt,assertGeminiEntrySilence}=require('./assert-callback-offer-audio.cjs');
const call='1-999@127.0.0.20',expected={call_id:call,queue_id:'1'.repeat(32),ip:'127.0.0.20',sip_port:15064,media_port:47200,queue_entry:100};
function reference(length,seed){const b=Buffer.alloc(length);for(let i=0;i<length;i++){seed=(Math.imul(seed,1664525)+1013904223)>>>0;b[i]=(seed>>>24)&127;}return b;}
const refs={offer:reference(32000,41),position:reference(12000,79)};
function capture(options={}) {
    const header=Buffer.alloc(24);header.writeUInt32LE(0xa1b2c3d4);header.writeUInt16LE(2,4);header.writeUInt16LE(4,6);header.writeUInt32LE(65535,16);header.writeUInt32LE(1,20);
    const records=[header];
    function udp(time,payload,src,dst,sp,dp){const p=Buffer.alloc(42+payload.length);p.writeUInt16BE(0x0800,12);p[14]=0x45;
        p.writeUInt16BE(28+payload.length,16);p[23]=17;Buffer.from(src.split('.').map(Number)).copy(p,26);Buffer.from(dst.split('.').map(Number)).copy(p,30);
        p.writeUInt16BE(sp,34);p.writeUInt16BE(dp,36);p.writeUInt16BE(payload.length+8,38);payload.copy(p,42);
        const r=Buffer.alloc(16);r.writeUInt32LE(Math.floor(time),0);r.writeUInt32LE(Math.round((time-Math.floor(time))*1e6),4);r.writeUInt32LE(p.length,8);r.writeUInt32LE(p.length,12);records.push(r,p);}
    const sdp=(ip,port)=>`v=0\r\no=- 1 1 IN IP4 ${ip}\r\ns=fixture\r\nc=IN IP4 ${ip}\r\nt=0 0\r\nm=audio ${port} RTP/AVP 0\r\na=rtpmap:0 PCMU/8000\r\n`;
    function sip(time,first,seq,method,out,body='',to='remote') {
        const text=first+'\r\nCall-ID: '+call+'\r\nFrom: <sip:fixture@acceptance.invalid>;tag=local\r\nTo: <sip:2098@acceptance.invalid>'+ (to?';tag='+to:'')
            +'\r\nCSeq: '+seq+' '+method+'\r\n'+(body?'Content-Type: application/sdp\r\n':'')+'Content-Length: '+Buffer.byteLength(body)+'\r\n\r\n'+body;
        udp(time,Buffer.from(text),out?'127.0.0.20':'127.0.0.1',out?'127.0.0.1':'127.0.0.20',out?15064:5060,out?5060:15064);
    }
    sip(99.95,'INVITE sip:2098@acceptance.invalid SIP/2.0',2,'INVITE',true,sdp('127.0.0.20',47200),'');
    sip(100,'SIP/2.0 200 OK',2,'INVITE',false,sdp(options.remote||'127.0.0.1',30000));
    if(!options.noAck)sip(100.01,'ACK sip:2098@acceptance.invalid SIP/2.0',2,'ACK',true,'',options.badTag?'wrong':'remote');
    const duration=options.duration||46;
    const audio=Buffer.alloc(duration*8000,options.noiseByte===undefined?255:options.noiseByte);
    const selectedRefs=options.refs||refs;
    for(const at of options.offer||[3,18,33])selectedRefs.offer.copy(audio,at*8000);
    for(const at of options.position||[11,26,41])selectedRefs.position.copy(audio,at*8000);
    if(options.partialEntry)selectedRefs.offer.subarray(0,3200).copy(audio,400);
    if(options.earlySpeech)selectedRefs.offer.subarray(0,3200).copy(audio,20*8000);
    if(options.transient)selectedRefs.offer.subarray(0,160).copy(audio,1600);
    for(let offset=0;offset<audio.length;offset+=160){if((options.loss&&offset===3*8000+160)||offset===options.lossAt*8000
        ||offset<(options.skipRtpBefore||0)*8000)continue;
        const rtp=Buffer.alloc(172);rtp[0]=128;rtp.writeUInt16BE(offset/160,2);rtp.writeUInt32BE(offset,4);rtp.writeUInt32BE(77,8);audio.copy(rtp,12,offset,offset+160);
        udp(100+offset/8000+(options.rtpStartShift||0),rtp,options.foreign?'127.0.0.2':'127.0.0.1','127.0.0.20',30000,47200);}
    if(options.dtmf){const b=Buffer.alloc(16);b[0]=128;b[1]=101;udp(108,b,'127.0.0.20','127.0.0.1',47200,30000);}
    sip(100+duration,'BYE sip:2098@acceptance.invalid SIP/2.0',3,'BYE',true);
    if(!options.noByeAck)sip(100+duration+.01,'SIP/2.0 200 OK',3,'BYE',false);
    return Buffer.concat(records);
}
let groups=0;const valid=capture(),result=inspect(valid,refs,expected);
assert.deepEqual(result.offer.map(m=>m.after_queue_entry_seconds),[3,18,33]);
assert.deepEqual(result.position.map(m=>m.after_queue_entry_seconds),[11,26,41]);assert(result.no_offer_on_entry);groups++;
for(const [options,pattern] of [[{offer:[0,18,33]},/schedule/],[{offer:[3,17,31]},/schedule/],
    [{offer:[3,18]},/exactly3/],[{position:[8,23,38]},/schedule/],[{position:[11,26]},/exactly3/],
    [{foreign:true},/Foreign RTP/],[{remote:'198.51.100.2'},/Non-local/],[{noAck:true},/Missing dialog ACK/],
    [{badTag:true},/Missing dialog ACK/],[{noByeAck:true},/Missing BYE200/],[{dtmf:true},/DTMF/],[{loss:true},/exactly3|Missing RTP/],
    [{lossAt:1},/Missing RTP/],[{lossAt:16},/Missing RTP/],[{lossAt:45},/Missing RTP/]]) {
    assert.throws(()=>inspect(capture(options),refs,expected),pattern);groups++;
}
assert.throws(()=>inspect(valid,refs,{...expected,call_id:'1-888@127.0.0.20'}),/Foreign dialog/);groups++;
assert.throws(()=>inspect(valid.subarray(0,-1),refs,expected),/Truncated/);groups++;
assert.throws(()=>inspect(valid,{...refs,offer:Buffer.alloc(56000,17)},expected),/shorter than7/);groups++;
const geminiRefs={offer:reference(41368,41)},geminiExpected={...expected,audio_mode:'gemini'};
const geminiCapture=options=>capture({refs:geminiRefs,position:[],...options});
const geminiResult=inspect(geminiCapture(),geminiRefs,geminiExpected);
assert.equal(geminiResult.position_verified,false);assert.equal(geminiResult.scope,'offer_only_silence_hold');
assert.deepEqual(geminiResult.expected_position_seconds,[]);assert.equal(geminiResult.position,undefined);
assert.equal(geminiResult.offer_duration_seconds,5.171);
assert.deepEqual(geminiResult.offer.map(m=>m.complete_end_after_queue_entry_seconds),[8.171,23.171,38.171]);groups++;
assert.equal(geminiResult.entry_silence.observed_energetic_windows,0);
assert.equal(geminiResult.entry_silence.end_after_queue_entry_seconds,2);groups++;
const startupResult=inspect(geminiCapture({rtpStartShift:.034}),geminiRefs,geminiExpected);
assert.equal(startupResult.entry_silence.pre_rtp_gap_seconds,.034);
assert.equal(startupResult.entry_silence.first_after_queue_entry_seconds,.034);
assert.equal(startupResult.entry_silence.allowed_startup_gap_ms,100);
assert.equal(startupResult.entry_silence.startup_gap_is_observed_silence,false);
assert(startupResult.entry_silence.samples>=15200);groups++;
for(const options of [{rtpStartShift:.101},{skipRtpBefore:.12}])
    assert.throws(()=>inspect(geminiCapture(options),geminiRefs,geminiExpected),/Insufficient Gemini entry-silence observation/);groups++;
assert.throws(()=>inspect(geminiCapture({rtpStartShift:.034,partialEntry:true}),geminiRefs,geminiExpected),
    /energetic audio before Gemini/);groups++;
const incompleteTimes=Float64Array.from({length:8000},(_,i)=>101+i/8000);
assert.throws(()=>assertGeminiEntrySilence(Buffer.alloc(8000,255),incompleteTimes,100),error=>{
    const prefix='Insufficient Gemini entry-silence observation: ';
    assert(error.message.startsWith(prefix));
    assert.deepEqual(JSON.parse(error.message.slice(prefix.length)),{samples:8000,
        first_after_queue_entry_seconds:1,last_after_queue_entry_seconds:1.999875});return true;
});groups++;
for(const options of [{partialEntry:true},{offer:[0,3,18,33]}])
    assert.throws(()=>inspect(geminiCapture(options),geminiRefs,geminiExpected),/energetic audio before Gemini/);groups++;
for(const options of [{noiseByte:239},{transient:true},{offer:[2,18,33]}])
    assert.equal(inspect(geminiCapture(options),geminiRefs,geminiExpected).result,'PASS');groups++;
// The new silence guard is opt-in; legacy comparison retains its old scope.
assert.equal(inspect(capture({partialEntry:true}),refs,expected).result,'PASS');groups++;
for(const [options,pattern] of [[{offer:[0,18,33]},/energetic audio|schedule/],[{offer:[3,18]},/exactly3/],
    [{offer:[3,16,33]},/schedule/],[{lossAt:8},/Missing RTP/],[{dtmf:true},/DTMF/]])
    assert.throws(()=>inspect(geminiCapture(options),geminiRefs,geminiExpected),pattern);groups++;
assert.throws(()=>inspect(valid,refs,geminiExpected),/longer-than-five/);
assert.throws(()=>inspect(valid,refs,{...expected,audio_mode:'other'}),/audio mode/);groups++;
const thirtyExpected={...geminiExpected,timing_profile:'interval-30'};
const thirtyCapture=options=>geminiCapture({duration:76,offer:[30,60],...options});
const thirty=inspect(thirtyCapture(),geminiRefs,thirtyExpected);
assert.deepEqual(thirty.expected_offer_seconds,[30,60]);
assert.deepEqual(thirty.offer.map(m=>m.after_queue_entry_seconds),[30,60]);
assert.equal(thirty.entry_silence.end_after_queue_entry_seconds,29);
assert.equal(thirty.entry_silence.observed_energetic_windows,0);
assert.equal(thirty.position_verified,false);assert.equal(thirty.call_duration_seconds,76);groups++;
for(const [options,pattern] of [[{offer:[0,30,60]},/energetic/],[{offer:[30,45,60]},/exactly2/],
    [{offer:[30,62]},/schedule/],[{offer:[30]},/exactly2/],[{earlySpeech:true},/energetic/],
    [{lossAt:20},/Missing RTP/],[{duration:46},/duration/]]) {
    assert.throws(()=>inspect(thirtyCapture(options),geminiRefs,thirtyExpected),pattern);groups++;
}
assert.throws(()=>inspect(thirtyCapture(),geminiRefs,{...expected,timing_profile:'interval-30'}),/requires immutable/);
for(const invalid of [null,30,'30',[],{},'unknown'])
    assert.throws(()=>inspect(thirtyCapture(),geminiRefs,{...thirtyExpected,timing_profile:invalid}),/timing profile/);
groups++;
const hash=bytes=>require('node:crypto').createHash('sha256').update(bytes).digest('hex');
const wavHash='a'.repeat(64),prompt='acdc-callback-offer-6-gemini-sulafat-'+wavHash.slice(0,16);
const receipt={audio_mode:'gemini',scope:'offer_only_silence_hold',position_verified:false,
    offer:{document_id:'en-us/'+prompt,revision:'1-'+'b'.repeat(32),attachment:prompt+'.wav',wav_sha256:wavHash,
        immutable_path:'/system_media/en-us/'+prompt,canonical_prompt_id:'acdc-callback-offer-6',
        installed_callback_assets_verified:42,duration_seconds:5.171,ulaw_sha256:hash(geminiRefs.offer)}};
assertReferenceReceipt(receipt,geminiRefs,'gemini');groups++;
for(const mutate of [r=>r.audio_mode='legacy',r=>r.position_verified=true,r=>r.offer.installed_callback_assets_verified=41,
    r=>r.offer.document_id='en-us/acdc-callback-offer-6',r=>r.offer.immutable_path='/account_media/foreign',
    r=>r.offer.duration_seconds=4,r=>r.offer.ulaw_sha256='0'.repeat(64)]) {
    const bad=JSON.parse(JSON.stringify(receipt));mutate(bad);assert.throws(()=>assertReferenceReceipt(bad,geminiRefs,'gemini'));
}groups++;
assert.throws(()=>assertReferenceReceipt(receipt,geminiRefs,'legacy'));groups++;
const captureLog='2304 packets captured\n4608 packets received by filter\n0 packets dropped by kernel\n';
assertCaptureLog(captureLog);groups++;
for(const bad of ['', captureLog.replace('0 packets dropped','1 packets dropped'),
    captureLog.replace('2304 packets captured','0 packets captured'),
    captureLog.replace('4608 packets received by filter\n',''),
    captureLog+'0 packets dropped by kernel\n', 'x'.repeat(65537)]) {
    assert.throws(()=>assertCaptureLog(bad));groups++;
}
// New profile retains the same exact-dialog/coverage/DTMF/teardown checks.
// References are synthetic waveforms, not listening or deployed-audio evidence.
const positionParts=[reference(14000,79),reference(8000,101)],prerecordedOffer=reference(60000,91);
const combinedPosition=Buffer.concat([positionParts[0],Buffer.alloc(800,255),positionParts[1]]);
const prerecordedRefs={offer:prerecordedOffer,position_parts:positionParts};
const prerecordedCapture=options=>capture({refs:{offer:prerecordedOffer,position:combinedPosition},
    offer:[30,60],position:[45,75],duration:86,...options});
const prerecordedExpected={...expected,audio_mode:'prerecorded',timing_profile:'dual-prerecorded',locale:'en-us'};
const prerecordedValid=prerecordedCapture();
for(const locale of ['en-us','he-il','fr-fr','es-es','ar-sa']) {
    const got=inspect(prerecordedValid,prerecordedRefs,{...prerecordedExpected,locale});
    assert.equal(got.locale,locale);assert.equal(got.scope,'position-one-and-offer-six');assert.equal(got.spoken_position,1);
    assert.equal(got.wait_time_verified,false);assert.equal(got.native_listening_approved,false);assert.equal(got.full_language_ready,false);
    assert.deepEqual(got.offer.map(m=>m.after_queue_entry_seconds),[30,60]);
    assert.deepEqual(got.position.map(m=>m.after_queue_entry_seconds),[45,75]);
    assert(got.position.every(p=>p.components.length===2));assert.equal(got.entry_silence.end_after_queue_entry_seconds,29);
}groups++;
for(const [caseIndex,options] of [{dtmf:true},{foreign:true},{lossAt:20},{lossAt:46},{earlySpeech:true},
    {noByeAck:true},{position:[44,76.1]},{offer:[30,60,81]},
    {refs:{offer:prerecordedOffer,position:Buffer.concat([positionParts[1],positionParts[0]])}},
    {refs:{offer:prerecordedOffer,position:Buffer.concat([positionParts[0],Buffer.alloc(16000,255),positionParts[1]])}}].entries()) {
    assert.throws(()=>inspect(prerecordedCapture(options),prerecordedRefs,prerecordedExpected), 'prerecorded negative case '+caseIndex);
}groups++;
assert.throws(()=>inspect(prerecordedValid,prerecordedRefs,{...prerecordedExpected,locale:'en-gb'}));groups++;
console.log('PASS '+groups+' synthetic dual-schedule SIP/RTP gates; full ordered prerecorded position, exact peer, no DTMF, loss and timing negatives');
