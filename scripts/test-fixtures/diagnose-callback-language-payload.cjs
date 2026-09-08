'use strict';
// Additive diagnosis only. Never converts a failed strict RTP-timing run to PASS.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const returned=require('./assert-callback-returned-audio.cjs');
const media=require('./assert-callback-confirmation-pcap.cjs');
const {fullPhrase}=require('./assert-callback-registration-audio.cjs');
const reference=require('./callback-returned-reference.cjs');
function diagnose(run,scenario='language'){
    assert(['language','deadline'].includes(scenario));const deadline=scenario==='deadline';
    assert(/^\/var\/log\/kazoo-acceptance\/[0-9]{8}T[0-9]{6}Z$/.test(run));
    const read=name=>reference.read(path.join(run,name),16*1024*1024);
    const receipt=JSON.parse(read(deadline?'callback-confirmation-deadline-edit.json':'callback-language-edit.json')),bridge=JSON.parse(read('retry-bridge-evidence.json'));
    assert(receipt.account==='8310dc3170a18de37f205d0da172df65'&&receipt.state==='restored'
        &&(receipt.scenario||'language')===scenario
        &&receipt.before.queue.announcements.language==='en-us'&&receipt.after.queue.announcements.language===(deadline?'en-us':'fr-fr')
        &&receipt.restored.queue.announcements.language==='en-us'
        &&bridge.callback.id===receipt.callback&&bridge.callback.language==='en-us'
        &&bridge.callback.status==='completed'&&bridge.callback.attempts===2);
    if(deadline)assert(receipt.before.queue.callback.confirmation_timeout===15
        &&receipt.after.queue.callback.confirmation_timeout===3&&receipt.restored.queue.callback.confirmation_timeout===15);
    const capture=read('retry-returned.pcap'),raw=read('callback-return-language.ulaw');
    const asset=reference.asset('en-us');assert(asset.sha256===receipt.reference_sha256&&raw.equals(reference.convert(asset.bytes)));
    const proof={callerCallId:bridge.caller.sip_call_id,agentCallId:bridge.agent.sip_call_id};
    const payload=media.negotiatedPayload(read('callback-carrier-negotiation.log').toString());
    media.inspect(capture,proof,payload,'internal'); // Exact SIP/DTMF/agent media gate remains mandatory.
    const packets=media.packets(capture);
    const acks=packets.filter(p=>p.dst==='127.0.0.20'&&p.dport===16060&&p.payload.toString().startsWith('ACK ')
        &&p.payload.toString().includes('\r\nCall-ID: '+proof.callerCallId+'\r\n'));
    assert(acks.length);const ack=Math.min(...acks.map(p=>p.time));
    const digits=packets.filter(p=>p.src==='127.0.0.20'&&p.sport===44000&&p.time>=ack).map(returned.rtp)
        .filter(p=>p.pt===payload&&p.audio[0]===1);assert(digits.length);
    const digit=Math.min(...digits.map(p=>p.time));
    const frames=packets.filter(p=>p.dst==='127.0.0.20'&&p.dport===44000&&p.time>=ack&&p.time<digit).map(returned.rtp);
    assert(frames.length>=200&&frames.every(p=>p.pt===0)&&new Set(frames.map(p=>p.ssrc)).size===1);
    const gaps=[];let offset=0;
    for(let i=0;i<frames.length;i++){
        const frame=frames[i];frame.offset=offset;offset+=frame.audio.length;
        if(i){const previous=frames[i-1];
            assert(((frame.payload.readUInt16BE(2)-previous.payload.readUInt16BE(2))&65535)===1,'Packet sequence loss or duplicate');
            const delta=((frame.stamp-previous.stamp)>>>0)-previous.audio.length;
            assert(delta>=0&&delta<=8000,'Unbounded or backward RTP timestamp');
            if(delta)gaps.push({payload_sample:frame.offset,seconds:delta/8000});
        }
    }
    const bytes=Buffer.concat(frames.map(f=>f.audio)),matches=fullPhrase(bytes,raw);assert(matches.length===1);
    const match=matches[0],end=match.sample+raw.length;
    const first=frames.find(f=>f.offset<=match.sample&&f.offset+f.audio.length>match.sample);
    const last=frames.find(f=>f.offset<end&&f.offset+f.audio.length>=end);assert(first&&last);
    const startAt=first.time+(match.sample-first.offset)/8000,endAt=last.time+(end-last.offset)/8000;
    assert(startAt>=ack&&endAt<=digit);
    if(deadline)assert(raw.length>3*8000&&digit-endAt>0&&digit-endAt<=3);
    let strictPassed=false;
    try{returned.inspect(capture,raw,proof,payload,'internal',returned.dependencies(path.resolve(__dirname,'../..')));strictPassed=true;}catch{}
    return {scope:deadline?'additive-deadline-payload-diagnosis':'additive-language-payload-diagnosis',language:'en-us',queue_language_during_retry:deadline?'en-us':'fr-fr',
        ...(deadline?{saved_confirmation_timeout_seconds:3,prompt_duration_seconds:raw.length/8000,
            prompt_completion_after_ack_seconds:endAt-ack,digit_after_ack_seconds:digit-ack,
            prompt_completion_before_digit_seconds:digit-endAt,
            positive_short_window_connection_verified:true,negative_response_expiry_live_verified:false}:{}),
        persisted_language_verified:true,complete_ordered_english_payload_before_digit1:true,
        correlation:match.correlation,sequence_loss:0,rtp_timestamp_gaps:gaps,
        gaps_inside_spoken_prompt:gaps.filter(g=>g.payload_sample>match.sample&&g.payload_sample<end),
        strict_audio_timing_passed:strictPassed,original_failed_run_reclassified:false,
        capture_sha256:reference.sha(capture),source_wav_sha256:asset.sha256,restoration_verified:true,
        database_writes:0,provider_requests:0};
}
module.exports={diagnose};
if(require.main===module){try{
    const [run,scenario='language']=process.argv.slice(2);assert(process.argv.length===3||process.argv.length===4);
    const result=diagnose(run,scenario);
    fs.writeFileSync(path.join(run,scenario==='deadline'?'callback-deadline-payload-diagnosis.json':'callback-language-payload-diagnosis.json'),JSON.stringify(result,null,2)+'\n',{flag:'wx',mode:384});
    console.log(JSON.stringify(result));
}catch{console.error('Callback language payload diagnosis refused; no existing evidence rewritten.');process.exitCode=1;}}
