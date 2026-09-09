'use strict';
// One opt-in native callback timeout case. No provider calls or runtime writes.
// The parent holds the shared lock and edits/restores only its isolated queue.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const media=require('./assert-callback-confirmation-pcap.cjs');
const audio=require('./assert-callback-registration-audio.cjs');
const retry=require('./assert-callback-retry.cjs');
const {assertCaptureLog}=require('./assert-callback-offer-audio.cjs');
const ACCOUNT='8310dc3170a18de37f205d0da172df65',IP='127.0.0.20';
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
function scenario(source,mediaPath){
    assert(typeof mediaPath==='string'&&path.isAbsolute(mediaPath)&&/^[-A-Za-z0-9_./]+$/.test(mediaPath));
    const start='  <pause variable="confirm_delay_ms"/>';
    assert.equal(source.split(start).length,2);
    const head=source.slice(0,source.indexOf(start));
    assert(head.endsWith('  <nop><action><exec rtp_stream="apattern,1,0,PCMU/8000"/></action></nop>\n'));
    // Speech is not an echo of SIPp's transmitted test pattern. File-mode
    // silence drives native media reads; the strict received-prompt pcap gate
    // below supplies the media assertion without a false echo-pattern failure.
    return require('./callback-internal-scenarios.cjs').derive(head,'returned')
        .replace('rtp_stream="apattern,1,0,PCMU/8000"','rtp_stream="'+mediaPath+',-1,0,PCMU/8000"')+
        '  <Reference variables="confirm_delay_ms,bridge_hold_ms,dtmf_payload,us,them"/>\n'+
        '  <!-- No digit and no caller-initiated hangup: Kazoo must end this attempt. -->\n'+
        '  <recv request="BYE" timeout="15000"/>\n'+
        '  <nop><action><exec rtp_stream="pause"/></action></nop>\n'+
        '  <send><![CDATA[\nSIP/2.0 200 OK\n[last_Via:]\n[last_From:]\n[last_To:]\n[last_Call-ID:]\n[last_CSeq:]\nContent-Length: 0\n\n]]></send>\n'+
        '</scenario>\n';
}
function timing(ack,start,end,bye,seconds){
    assert(seconds===3&&start>=ack&&end>start&&end-start>3,'Missing complete long prompt');
    const wait=bye-end;
    // PCMU packet timestamps have20ms granularity. Allow bounded scheduling
    // tolerance, not early expiry during playback or a second full timeout.
    assert(wait>=seconds-.2&&wait<=seconds+1,'Response timeout did not start after the full prompt');
    return {prompt_start_after_ack_seconds:start-ack,prompt_end_after_ack_seconds:end-ack,
        bye_after_prompt_seconds:wait,response_timeout_seconds:seconds};
}
function inspectPackets(all,raw,callerId){
    const signal=all.filter(p=>p.sport===16060||p.dport===16060).filter(p=>
        /^(INVITE |ACK |BYE |CANCEL |INFO |SIP\/2.0 )/.test(p.payload.toString('latin1',0,32))).map(audio.sip).filter(p=>p.method!=='OPTIONS');
    assert(signal.length&&signal.every(p=>p.callId===callerId),'Unexpected returned dialog');
    assert(!signal.some(p=>['INFO','CANCEL'].includes(p.method)),'Unexpected confirmation or cancellation');
    assert(!all.some(p=>p.dst===IP&&p.dport===15100&&p.payload.subarray(0,7).toString()==='INVITE '),
        'Agent was offered before caller confirmation');
    const incoming=(method)=>audio.unique(signal.filter(p=>p.dst===IP&&p.dport===16060&&p.first.startsWith(method+' ')),method);
    const offer=incoming('INVITE'),ack=incoming('ACK'),bye=incoming('BYE');
    const answer=audio.unique(signal.filter(p=>p.src===IP&&p.sport===16060&&p.method==='INVITE'&&p.first.startsWith('SIP/2.0 200 ')),'answer');
    const cleared=audio.unique(signal.filter(p=>p.src===IP&&p.sport===16060&&p.method==='BYE'&&p.first.startsWith('SIP/2.0 200 ')),'BYE response');
    assert(offer.time<=answer.time&&answer.time<=ack.time&&ack.time<bye.time&&bye.time<=cleared.time);
    assert(offer.cseq===answer.cseq&&ack.cseq===offer.cseq&&cleared.cseq===bye.cseq);
    for(const p of [answer,ack,bye,cleared])assert(p.fromTag===offer.fromTag&&p.toTag===answer.toTag&&p.toTag);
    assert(!signal.some(p=>p.src===IP&&p.sport===16060&&p.first.startsWith('BYE ')),'Endpoint caused timeout itself');
    const remote=media.audioSdp(offer),local=media.audioSdp(answer);
    assert(local.ip===IP&&local.port===44000&&local.payload===remote.payload);
    const stream=all.filter(p=>p.src===IP&&p.sport===44000&&p.dst===remote.ip&&p.dport===remote.port).map(audio.rtp);
    assert(stream.length>100&&stream.every(p=>p.pt===0),'Caller sent DTMF or no RTP while awaiting expiry');
    const received=all.filter(p=>p.dst===IP&&p.dport===44000&&p.time>=ack.time&&p.time<bye.time).map(p=>{
        assert(p.src===remote.ip&&p.sport===remote.port);const r=audio.rtp(p);assert(r.pt===0);return r;
    }).sort((a,b)=>a.time-b.time);
    assert(received.length>200&&new Set(received.map(p=>p.ssrc)).size===1);
    const base=received[0].stamp;let length=0;
    for(const p of received)length=Math.max(length,((p.stamp-base)>>>0)+p.payload.length);
    assert(length>0&&length<=15*8000);
    const bytes=Buffer.alloc(length,255),covered=new Uint8Array(length),times=new Float64Array(length);
    for(const p of received){const offset=(p.stamp-base)>>>0;
        for(let i=0;i<p.payload.length;i++){
            assert(!covered[offset+i]||bytes[offset+i]===p.payload[i]);
            if(!covered[offset+i])times[offset+i]=p.time+i/8000;
            bytes[offset+i]=p.payload[i];covered[offset+i]=1;
        }
    }
    assert(covered.every(Boolean),'RTP timestamp gap in returned prompt window');
    const matches=audio.fullPhrase(bytes,raw);assert.equal(matches.length,1,'Missing complete returned prompt');
    const match=matches[0],end=match.sample+raw.length;
    const startAt=times[match.sample],endAt=times[end-1]+1/8000;
    assert(Math.abs(endAt-startAt-raw.length/8000)<.3,'Prompt timeline discontinuity');
    return {full_prompt_verified:true,phrase_samples:raw.length,correlation:match.correlation,
        no_confirmation_sent:true,no_agent_invite:true,server_bye_verified:true,
        ...timing(ack.time,startAt,endAt,bye.time,3),offer_epoch_seconds:offer.time};
}
function run(action,directory){
    assert(['generate','verify'].includes(action)&&process.getuid()===0);
    assert(/^\/var\/log\/kazoo-acceptance\/[0-9]{8}T[0-9]{6}Z$/.test(directory)&&fs.realpathSync(directory)===directory);
    const st=fs.statSync(directory);assert(st.uid===0&&(st.mode&511)===448&&st.isDirectory());
    const fixture=require('./callback-fixture-account.cjs');
    assert(fixture.readState('/etc/kazoo/acceptance-secrets.env').ACCEPTANCE_ACCOUNT_ID===ACCOUNT);
    const pins={},read=name=>{const file=path.join(directory,name),s=fs.lstatSync(file);
        assert(s.isFile()&&!s.isSymbolicLink()&&s.uid===0&&(s.mode&511)===384&&s.size<32*1024*1024);
        const b=fs.readFileSync(file);pins[name]=sha(b);return b;},json=name=>JSON.parse(read(name));
    const silence=path.join(directory,'callback-expiry-silence.ulaw');
    const source=()=>scenario(fs.readFileSync(path.join(__dirname,'../sip-tests/callback-returned.xml'),'utf8'),silence);
    if(action==='generate'){
        fs.writeFileSync(silence,Buffer.alloc(8000,255),{flag:'wx',mode:384});
        fs.writeFileSync(path.join(directory,'callback-expiry.xml'),source(),{flag:'wx',mode:384});return;
    }
    assert.deepEqual(read('callback-expiry-silence.ulaw'),Buffer.alloc(8000,255));
    assert.equal(read('callback-expiry.xml').toString(),source(),'No-confirmation scenario changed');
    const registered=json('callback-registration-evidence.json'),first=json('retry-first-attempt.json'),backoff=json('retry-backoff-evidence.json');
    const answered=json('callback-expiry-answered.json'),final=json('callback-expiry-final.json'),edit=json('callback-confirmation-deadline-edit.json');
    assert(registered.account_id===ACCOUNT&&registered.status==='queued'&&registered.attempts===0);
    for(const doc of [first.callback,backoff,answered.callback,final]){
        for(const key of ['id','account_id','queue_id','original_call_id','enqueued_at','enqueue_sequence','number','language'])assert.equal(doc[key],registered[key]);
        assert(doc.max_attempts===2&&doc.retry_delay===15&&doc.reconciliation_required!==true);
        assert.deepEqual(doc.internal_target,registered.internal_target);
    }
    assert(backoff.status==='retry_wait'&&backoff.attempts===1);
    assert(answered.callback.attempts===2&&answered.callback.agent_call_id===null&&answered.caller.account===ACCOUNT
        &&answered.caller.callback_id===registered.id&&answered.caller.id===answered.callback.caller_call_id
        &&Number(answered.caller.answered)>0&&!answered.caller.bridge_to);
    assert(final.status==='failed'&&final.attempts===2&&final.last_cause==='confirmation_timeout'
        &&final.caller_call_id===null&&final.agent_call_id===null&&final.selected_agents===null);
    assert(json('callback-expiry-both-down.json').row_count===0);
    assert(edit.state==='edited'&&edit.scenario==='deadline'&&edit.callback===registered.id
        &&edit.before.queue.callback.confirmation_timeout===15&&edit.after.queue.callback.confirmation_timeout===3);
    retry.registrationModeProof('entry-only',json('retry-registration-mode.json'),json('retry-registration-policy.json'),json('retry-registration-audio.json'),'en-us');
    for(const phase of ['original','unanswered','returned'])assertCaptureLog(read('retry-'+phase+'-capture.log').toString());
    const unanswered=require('./assert-callback-unanswered.cjs').inspect(read('retry-unanswered.pcap'),undefined,'internal');
    assert.equal(unanswered.firstCallerSipId,first.caller.sip_call_id);
    assert(first.caller.id!==answered.caller.id);
    const waveform=inspectPackets(media.packets(read('retry-returned.pcap')),read('callback-return-language.ulaw'),answered.caller.sip_call_id);
    const delay=retry.retryTiming(unanswered,waveform.offer_epoch_seconds,backoff);
    for(const name of ['callback-carrier.log','callback-agent-1.log'])assert(!/Could not (?:bind port for|open socket for|set up media IP for) RTP streaming/i.test(read(name).toString()));
    const result={scope:'native-second-attempt-confirmation-expiry',account_id:ACCOUNT,...waveform,
        retry_timing:delay,terminal_status:'failed',last_cause:'confirmation_timeout',attempts:2,
        agent_leg_created:false,zero_channels:true,input_sha256:pins,
        first_attempt_confirmation_timeout_retried:false,gemini_requests:0};
    fs.writeFileSync(path.join(directory,'callback-confirmation-expiry.json'),JSON.stringify(result,null,2)+'\n',{flag:'wx',mode:384});
    console.log('PASS full prompt then confirmation expiry; no digit, agent INVITE or remaining channel; attempts exhausted cleanly');
}
module.exports={scenario,timing,inspectPackets};
if(require.main===module){try{assert.equal(process.argv.length,4);run(...process.argv.slice(2));}
catch(e){console.error('Callback confirmation-expiry evidence failed: '+e.message);process.exitCode=1;}}
