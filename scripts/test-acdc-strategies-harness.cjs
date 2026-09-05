#!/usr/bin/env node
'use strict';
// Offline safety and synthetic SIP state tests: no Crossbar or live SIP calls.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const h=require('./test-acdc-strategies-live.cjs'),sip=require('./test-fixtures/strategy-sip-phone.cjs');
const fsEvents=require('./test-fixtures/strategy-fs-events.cjs');
const id=n=>n.toString(16).padStart(32,'0');
const s={ACCEPTANCE_ACCOUNT_ID:id(1),ACCEPTANCE_ACCOUNT_NAME:'Kazoo5 Acceptance abcdef123456',ACCEPTANCE_REALM:'acceptance-abcdef123456.invalid',
    ACCEPTANCE_SIP_PROXY_HOST:'127.0.0.1',ACCEPTANCE_SIP_PROXY_PORT:'5060',ACCEPTANCE_SIP_TRANSPORT:'udp'};
['ACCEPTANCE_CALLER','ACCEPTANCE_AGENT_1','ACCEPTANCE_AGENT_2','ACCEPTANCE_AGENT_3'].forEach((p,i)=>Object.assign(s,{
    [p+'_EXTENSION']:String(1001+i),[p+'_SIP_USERNAME']:'acceptance'+(1001+i),[p+'_SIP_PASSWORD']:id(20+i),
    [p+'_USER_ID']:id(30+i),[p+'_DEVICE_ID']:id(40+i),[p+'_CALLFLOW_ID']:id(50+i)}));
const encode=x=>Object.entries(x).map(([k,v])=>k+'='+Buffer.from(v).toString('base64')).join('\n');
assert.deepEqual(h.parseState(encode(s)),s);
for(const [key,value] of Object.entries({ACCEPTANCE_ACCOUNT_ID:'302ae5a70c403124f764cbc54229cfcd',ACCEPTANCE_REALM:'live.example',
    ACCEPTANCE_AGENT_3_EXTENSION:'+12025550101',ACCEPTANCE_AGENT_3_SIP_PASSWORD:'bad;[exec]',ACCEPTANCE_AGENT_3_DEVICE_ID:s.ACCEPTANCE_AGENT_1_DEVICE_ID}))
    assert.throws(()=>h.parseState(encode({...s,[key]:value})),key);
const es=h.endpoints(s),saved={schema_version:1,owner:h.OWNER,deployment_id:id(77),account_id:s.ACCEPTANCE_ACCOUNT_ID,realm:s.ACCEPTANCE_REALM,
    device_ids:es.map(e=>e.device),queue_id:id(80),flow_id:id(81),agents:Object.fromEntries(es.slice(1).map(e=>[e.user,{status:'ready',membership:[id(82)]}]))};
assert.equal(h.validateSaved(saved,s),saved);
assert.throws(()=>h.validateSaved({...saved,current:{caller_id:'unrelated-call'}},s));
assert.throws(()=>h.validateSaved({...saved,agents:{[id(99)]:{status:'ready',membership:[]}}},s));
assert.throws(()=>h.validateSaved({...saved,agents:{...saved.agents,[es[1].user]:{status:'paused',membership:[]}}},s));
const doc={id:saved.queue_id,kz5_strategy_test:{owner:h.OWNER,deployment_id:saved.deployment_id,account_id:saved.account_id,kind:'queue'}};
assert(h.owned(doc,'queue',saved));assert(!h.owned({...doc,id:id(99)},'queue',saved));
assert(!h.owned({...doc,kz5_strategy_test:{...doc.kz5_strategy_test,account_id:id(99)}},'queue',saved));
const caller='1-123@127.0.0.52',e=es[1],c={id:'agent-leg',account:s.ACCEPTANCE_ACCOUNT_ID,device:e.device,agent:e.user,member:caller,
    ip:h.IP,port:e.port,peer:'127.0.0.1'};
const own=x=>h.ownedChannel(x,e,caller,s.ACCEPTANCE_ACCOUNT_ID,'127.0.0.1',es[0].device);
assert(own(c));for(const mutation of [{account:id(99)},{agent:id(99)},{device:id(99)},{member:'other-caller'},{ip:'127.0.0.50'},{port:18200},{peer:'192.0.2.1'},{auth_ip:'192.0.2.1'}])assert(!own({...c,...mutation}));
assert(own({...c,device:e.user,authorizing_type:'user',to_user:e.device}));
assert(!own({...c,device:e.user,authorizing_type:'user',to_user:id(99)}));
const source=fs.readFileSync(path.join(__dirname,'test-acdc-strategies-live.cjs'),'utf8');
assert(source.indexOf("if(args[0]==='--prepare-only')return;")<source.indexOf('await authenticate();'));
assert(source.includes("'/etc/kazoo/monitor-acceptance.lock'")&&source.includes("contacts(e).length===0"));
assert(!/systemctl|uuid_kill all|originate |--agent-status/.test(source));
assert.deepEqual(h.channelRows({row_count:0}),[]);assert.deepEqual(h.channelRows({row_count:0,rows:[]}),[]);
assert.deepEqual(h.channelRows({row_count:1,rows:[{uuid:'one'}]}),[{uuid:'one'}]);
assert.throws(()=>h.channelRows({error:'unavailable'}));assert.throws(()=>h.channelRows({row_count:1,rows:[]}));
const fixtureEvent='INCOMING DATA [text/event-json]\n'+JSON.stringify({'Event-Name':'CHANNEL_BRIDGE','Unique-ID':caller,'Other-Leg-Unique-ID':'agent-leg',
    variable_sdp:'v=0\r\n\r\nx={100%}',nested:{quoted:'"}\\'},'variable_ecallmgr_Account-ID':s.ACCEPTANCE_ACCOUNT_ID})+'\n';
const split=fixtureEvent.length-3,part=fsEvents.extract('banner\n'+fixtureEvent.slice(0,split));assert.equal(part.events.length,0);
const parsed=fsEvents.extract(part.rest+fixtureEvent.slice(split));assert.equal(parsed.events.length,1);
assert.equal(fsEvents.partner(parsed.events[0],caller,s.ACCEPTANCE_ACCOUNT_ID),'agent-leg');
assert.throws(()=>fsEvents.partner(parsed.events[0],caller,id(999)),/scope/);
const reverse={...parsed.events[0],'Unique-ID':'agent-leg','Other-Leg-Unique-ID':caller};assert.equal(fsEvents.partner(reverse,caller,s.ACCEPTANCE_ACCOUNT_ID),'agent-leg');
const explicit={'Event-Name':'CHANNEL_BRIDGE','Bridge-A-Unique-ID':'agent-leg','Bridge-B-Unique-ID':caller,'variable_ecallmgr_Account-ID':s.ACCEPTANCE_ACCOUNT_ID};
assert.equal(fsEvents.partner(explicit,caller,s.ACCEPTANCE_ACCOUNT_ID),'agent-leg');

function invite(id='fixture-call',method='INVITE'){return Buffer.from(`${method} sip:${e.username}@${h.IP}:${e.port} SIP/2.0\r\n`+
    'Via: SIP/2.0/UDP 127.0.0.1:5060;branch=z9hG4bKtest\r\nVia: SIP/2.0/UDP 127.0.0.1:5070;branch=z9hG4bKinner\r\n'+
    `From: <sip:1001@${s.ACCEPTANCE_REALM}>;tag=caller\r\nTo: <sip:${e.username}@${s.ACCEPTANCE_REALM}>\r\nCall-ID: ${id}\r\nCSeq: 1 ${method}\r\nContent-Length: 0\r\n\r\n`);}
async function phones(){const messages=[],events=[],p=new sip.Phone(e,h.IP,['127.0.0.1'],evt=>events.push(evt));p.send=b=>messages.push(sip.parse(b));
    const peer={address:'127.0.0.1',port:5060};
    try {
        p.receive(invite(),peer);p.receive(invite(),peer);
        assert.equal(events.filter(e=>e.type==='invite').length,1,'Retransmission created a duplicate call');
        assert.equal(messages.at(-1).first,'SIP/2.0 180 Ringing');assert.equal(messages.at(-1).headers.via.length,2);
        p.receive(invite('fixture-call','CANCEL'),peer);assert.equal(messages.at(-1).first,'SIP/2.0 487 Request Terminated');
        assert(p.dialogs.get('fixture-call').ended);assert(!p.dialogs.get('fixture-call').answered);
        p.policy=()=>2;p.receive(invite('answered-call'),peer);await new Promise(r=>setTimeout(r,15));
        assert.equal(messages.at(-1).first,'SIP/2.0 200 OK');assert(messages.at(-1).body.includes('PCMU/8000'));
        p.receive(invite('answered-call','ACK'),peer);p.receive(invite('answered-call','BYE'),peer);
        assert(p.dialogs.get('answered-call').acked&&p.dialogs.get('answered-call').ended);
        assert.throws(()=>p.receive(invite('bad-peer'),{...peer,address:'192.0.2.1'}),/nonlocal/);
        assert.throws(()=>p.receive(Buffer.from(invite('wrong-user').toString().replace('sip:'+e.username+'@','sip:outsider@')),peer),/another fixture/);
        assert.throws(()=>p.receive(invite('unknown-dialog','BYE'),peer),/Non-fixture/);
    }finally{p.close();}
}
phones().then(()=>console.log('PASS offline strategy harness: isolated identity/PSTN/duplicate guards; exact marked ownership and saved restoration; account+agent+member+contact cleanup; shared lock and opt-in; SIP retransmit/CANCEL/ACK/BYE correlation'))
    .catch(e=>{console.error(e.message);process.exitCode=1;});
