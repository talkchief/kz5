'use strict';
// Synthetic PCAP replay only; no SIP, services, credentials or provider calls.
const assert=require('node:assert/strict'),path=require('node:path');
const root=process.env.KAZOO_ACCEPTANCE_SOURCE_ROOT||path.resolve(__dirname,'../..');
const fixtures=require(path.join(root,'scripts/test-fixtures/assert-callback-confirmation-pcap.test.cjs'));
const {inspect}=require('./assert-callback-returned-audio.cjs');
const deps={media:require(path.join(root,'scripts/test-fixtures/assert-callback-confirmation-pcap.cjs')),
    phrase:require(path.join(root,'scripts/test-fixtures/assert-callback-registration-audio.cjs')).fullPhrase};
function noise(size,seed=79){const b=Buffer.alloc(size);for(let i=0;i<size;i++){seed=(Math.imul(seed,1664525)+1013904223)>>>0;b[i]=(seed>>>24)&127;}return b;}
const reference=noise(42648);
function scenario(options={}){
    const duration=options.duration||8,digitAt=options.digitAt||9,transport=options.transport||'external';
    const carrier=transport==='internal'?'127.0.0.20':'127.0.0.30';
    const records=fixtures.records().map(p=>({...p,time:p.time>=1?p.time+digitAt-1:p.time}));
    const audio=Buffer.alloc(duration*8000,255);
    for(const at of options.starts||[.2])reference.copy(audio,Math.round(at*8000));
    for(let offset=0;offset<audio.length;offset+=160){
        if(options.loss&&offset===8000)continue;
        const length=Math.min(160,audio.length-offset),b=Buffer.alloc(12+length);
        b[0]=128;b[1]=options.nonPcmu?8:0;b.writeUInt16BE(offset/160,2);b.writeUInt32BE(offset,4);
        b.writeUInt32BE(options.secondStream&&offset>=16000?6:5,8);audio.copy(b,12,offset,offset+length);
        records.push({time:.5+offset/8000+(options.clockJump&&offset>=16000?.5:0),src:options.foreign?'127.0.0.2':'127.0.0.1',
            sport:20000,dst:'127.0.0.30',dport:44000,payload:b});
    }
    if(transport==='internal')for(const p of records){
        if(p.src==='127.0.0.30')p.src=carrier;if((p.dst||'127.0.0.30')==='127.0.0.30')p.dst=carrier;
        if(p.payload[0]>>6!==2)p.payload=Buffer.from(p.payload.toString().replaceAll('127.0.0.30',carrier).replace('sip:+12025550101@','sip:acceptance1001@'));
    }
    return fixtures.capture(records.sort((a,b)=>a.time-b.time),options.link||276,options.little!==false);
}
let groups=0;
// Replay must use explicitly selected fixture scope, never adopt the account
// from a captured receipt. Both original and main development hosts are valid.
for(const [selected,saved,accepted] of [
    [undefined,'7807ad61761269a1ccec833dde63f621',true],
    ['8310dc3170a18de37f205d0da172df65','8310dc3170a18de37f205d0da172df65',true],
    ['8310dc3170a18de37f205d0da172df65','7807ad61761269a1ccec833dde63f621',false],
    [undefined,'8310dc3170a18de37f205d0da172df65',false],
    ['d8520ce3f29c5b6db692289e782c92af','d8520ce3f29c5b6db692289e782c92af',false],
    ['adecbb84fbe9e06902a76731914d1943','adecbb84fbe9e06902a76731914d1943',false],
    ['302ae5a70c403124f764cbc54229cfcd','302ae5a70c403124f764cbc54229cfcd',false],
    ['invalid','invalid',false]
]){
    const env={PATH:process.env.PATH};
    if(selected!==undefined)env.KAZOO_CALLBACK_TEST_ACCOUNT_ID=selected;
    const code=`require(${JSON.stringify(path.join(__dirname,'assert-callback-returned-audio.cjs'))}).accountScope({account_id:${JSON.stringify(saved)}})`;
    const result=require('node:child_process').spawnSync(process.execPath,['-e',code],{env,timeout:5000,maxBuffer:16384});
    assert(!result.error);assert.equal(result.status===0,accepted);
}groups++;
for(const transport of ['external','internal'])for(const link of [1,113,276])for(const little of [true,false]){
    const result=inspect(scenario({transport,link,little}),reference,fixtures.proof,101,transport,deps);
    assert.equal(result.returned_confirmation_verified,true);assert.equal(result.phrase_samples,reference.length);
    assert(result.correlation>=.985&&result.completion_before_digit_seconds>2.9);
    assert(result.existing_returned_gate.first_agent_invite_after_digit_end_ms>0);
}groups++;
for(const options of [{loss:true},{foreign:true},{nonPcmu:true},{secondStream:true},{clockJump:true},
    {duration:4},{starts:[5]},{duration:13,digitAt:14,starts:[.2,6.2]}])
    assert.throws(()=>inspect(scenario(options),reference,fixtures.proof,101,'external',deps));groups++;
assert.throws(()=>inspect(scenario(),noise(reference.length,99),fixtures.proof,101,'external',deps));
assert.throws(()=>inspect(scenario(),reference,{...fixtures.proof,callerCallId:'f'.repeat(32)},101,'external',deps));
assert.throws(()=>inspect(scenario(),reference,fixtures.proof,102,'external',deps));
assert.throws(()=>inspect(scenario().subarray(0,-1),reference,fixtures.proof,101,'external',deps));groups++;
console.log('PASS '+groups+' synthetic returned waveform replay groups; no live acceptance claim');
