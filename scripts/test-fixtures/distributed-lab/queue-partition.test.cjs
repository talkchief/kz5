'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs');
const {identity,snapshot,inspectAudio}=require('./queue-partition.cjs');
const s={ACCEPTANCE_ACCOUNT_ID:'45e827067baf078029d0ca16a489fa8a',ACCEPTANCE_REALM:'acceptance-724fa76c8821.invalid',
    ACCEPTANCE_QUEUE_EXTENSION:'2000',ACCEPTANCE_AGENT_3_EXTENSION:'1004'};
['ACCEPTANCE_QUEUE_ID','ACCEPTANCE_QUEUE_CALLFLOW_ID','ACCEPTANCE_AGENT_1_USER_ID','ACCEPTANCE_AGENT_2_USER_ID',
    'ACCEPTANCE_AGENT_3_USER_ID'].forEach((k,i)=>s[k]=String(i+1).repeat(32));
identity(s);
for(const change of [{ACCEPTANCE_ACCOUNT_ID:'a'.repeat(32)},{ACCEPTANCE_REALM:'prod.invalid'},
    {ACCEPTANCE_QUEUE_EXTENSION:'+12025550101'},{ACCEPTANCE_AGENT_3_USER_ID:s.ACCEPTANCE_AGENT_1_USER_ID}])
    assert.throws(()=>identity({...s,...change}));
snapshot({present:true,state:'ready',fsm:'<0.123.0>'},'<0.123.0>');
for(const v of [{present:false},{present:true,state:'ready',fsm:'<0.124.0>'}])assert.throws(()=>snapshot(v,'<0.123.0>'));
// Validate the gate itself rejects missing/wrong-direction stimuli. The real
// RTP parser/amplitude implementation has its separate synthetic packet suite.
const packets=[{source:'fixture',sp:49000},{dest:'fixture',dp:49000},{source:'fixture',sp:49002},{dest:'fixture',dp:49002}]
    .map(p=>({...p,time:11}));
const audio={IP:'fixture',packets:()=>packets,amplitudes:items=>{
    assert.equal(items.length,1);const p=items[0],frequency=p.sp===49000||p.dp===49002?440:660;
    return {[frequency]:6000};}};
inspectAudio(audio,Buffer.alloc(0),10,13);
assert.throws(()=>inspectAudio({...audio,amplitudes:()=>({440:0,660:0})},Buffer.alloc(0),10,13));
assert.throws(()=>inspectAudio(audio,Buffer.alloc(0),10,11));
const source=fs.readFileSync(__dirname+'/queue-partition.cjs','utf8');
assert(source.includes("timeout:300")&&source.includes('while(Date.now()<end)')&&source.includes('Date.now()+35000'));
assert(source.includes("both('ready'),90")&&source.includes('no_sip_reregistration:true'));
assert(!source.includes("status:'login'")&&!source.includes("status:'logout'")&&!source.includes('systemctl restart'));
console.log('PASS exact synthetic queue identity, same-FSM guard, directional audio rejection, bounded owned pauses and no manual recovery');
