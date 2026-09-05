#!/usr/bin/env node
'use strict';
const assert=require('node:assert/strict'), fs=require('node:fs'), path=require('node:path');
const h=require('./test-channel-monitor-live.cjs');
const id=n=>n.toString(16).padStart(32,'0');
const base={ACCEPTANCE_ACCOUNT_ID:id(1),ACCEPTANCE_ACCOUNT_NAME:'Kazoo5 Acceptance abcdef123456',
    ACCEPTANCE_REALM:'acceptance-abcdef123456.invalid',ACCEPTANCE_SIP_PROXY_HOST:'127.0.0.1',
    ACCEPTANCE_SIP_PROXY_PORT:'5060',ACCEPTANCE_SIP_TRANSPORT:'udp'};
['ACCEPTANCE_CALLER','ACCEPTANCE_AGENT_1','ACCEPTANCE_AGENT_2'].forEach((p,i)=>Object.assign(base,{
    [p+'_EXTENSION']:String(1001+i),[p+'_SIP_USERNAME']:'acceptance'+(1001+i),[p+'_SIP_PASSWORD']:id(20+i),
    [p+'_USER_ID']:id(30+i),[p+'_DEVICE_ID']:id(40+i),[p+'_CALLFLOW_ID']:id(50+i)}));
const serialize=s=>Object.entries(s).map(([k,v])=>k+'='+Buffer.from(v).toString('base64')).join('\n');
const saved={schema_version:1,owner:h.OWNER,deployment_id:id(1234),account_id:base.ACCEPTANCE_ACCOUNT_ID,
    realm:base.ACCEPTANCE_REALM,device_ids:h.endpoints(base).map(e=>e.device),users:{}};
for(const role of ['admin','user'])saved.users[role]={id:id(role==='admin'?60:61),
    username:`monitor-${role}-${saved.deployment_id.slice(0,12)}`,password:id(62)};
assert.deepEqual(h.baseState(serialize(base)),base);assert.equal(h.validFixture(saved,base),saved);
for(const [key,value] of Object.entries({ACCEPTANCE_ACCOUNT_ID:h.MASTER,ACCEPTANCE_REALM:'production.example',
    ACCEPTANCE_AGENT_1_EXTENSION:'+12025550101',ACCEPTANCE_CALLER_SIP_PASSWORD:'bad;[exec]',
    ACCEPTANCE_AGENT_2_DEVICE_ID:base.ACCEPTANCE_AGENT_1_DEVICE_ID}))
    assert.throws(()=>h.baseState(serialize({...base,[key]:value})),key);
assert.throws(()=>h.baseState(serialize(base)+'\nACCEPTANCE_REALM=Yg=='),/key/);
assert.throws(()=>h.validFixture({...saved,account_id:h.MASTER},base),/ownership/);
assert.throws(()=>h.validFixture({...saved,current:{mode:'whisper',caller_id:'unrelated-call'}},base),/saved fixture/);
const endpoint=h.endpoints(base)[0], channel={active:true,account:base.ACCEPTANCE_ACCOUNT_ID,device:endpoint.device,
    ip:'127.0.0.50',port:endpoint.port,peer:'127.0.0.1',auth_ip:'127.0.0.50'};
assert(h.ownedChannel(channel,endpoint,base.ACCEPTANCE_ACCOUNT_ID,base.ACCEPTANCE_SIP_PROXY_HOST));
for(const mutation of [{active:false},{account:h.MASTER},{device:id(99)},{ip:'127.0.0.20'},
    {port:18103},{peer:'192.0.2.1'},{auth_ip:'192.0.2.2'}])
    assert(!h.ownedChannel({...channel,...mutation},endpoint,base.ACCEPTANCE_ACCOUNT_ID,base.ACCEPTANCE_SIP_PROXY_HOST));
const userLeg={...channel,device:endpoint.user,observed_authorizing_type:'user',observed_sip_to_user:endpoint.device};
assert(h.ownedChannel(userLeg,endpoint,base.ACCEPTANCE_ACCOUNT_ID,base.ACCEPTANCE_SIP_PROXY_HOST));
for(const mutation of [{observed_authorizing_type:'device'},{observed_sip_to_user:id(99)},{device:id(99)}])
    assert(!h.ownedChannel({...userLeg,...mutation},endpoint,base.ACCEPTANCE_ACCOUNT_ID,base.ACCEPTANCE_SIP_PROXY_HOST));
const user={id:saved.users.admin.id,username:saved.users.admin.username,enabled:true,priv_level:'admin',
    kz5_monitor_test:{owner:h.OWNER,deployment_id:saved.deployment_id,account_id:saved.account_id,kind:'admin'}};
assert(h.ownedUser(user,'admin',saved));
for(const mutation of [{id:id(99)},{username:'real-admin'},{priv_level:'user'},{kz5_monitor_test:{...user.kz5_monitor_test,account_id:h.MASTER}}])
    assert(!h.ownedUser({...user,...mutation},'admin',saved));
const source=fs.readFileSync(path.join(__dirname,'test-channel-monitor-live.cjs'),'utf8');
assert(source.indexOf("if(args[0]==='--prepare-only')return;")<source.indexOf('await authenticateMaster();'));
assert(!source.includes("action:'hangup'")&&!source.includes('--agent-status'));
assert(source.includes('uuid_kill ${c.id} NORMAL_CLEARING')&&source.includes('ownedChannel(c,endpoints(state)[0])'));
assert(source.includes("'403'")===false); // Numeric response codes, not truthy string checks.
assert(source.includes("d['Caller-Channel-Answered-Time']||d.variable_answer_epoch||0"));
assert(source.includes("'Connection':'close'")&&source.includes('stopSupervisor(true)'));
const callId='1-1234@127.0.0.50';
const sip=(direction,id,seq,status)=>`2026-09-05\t11:00:00.123456\t1788606000.123456\t${direction}\t${id}\tCSeq:${seq} INVITE\tSIP/2.0 ${status}\n`;
const ring=sip('R',callId,1,'180 Ringing'),answer=sip('R',callId,1,'200 OK');
assert.equal(h.ringingEvidence(ring+answer,callId).caller_received_180_before_200,true);
for(const invalid of [answer,answer+ring,sip('S',callId,1,'180 Ringing')+answer,
    sip('R','1-9999@127.0.0.50',1,'180 Ringing')+answer,ring+sip('R',callId,2,'200 OK')])
    assert.throws(()=>h.ringingEvidence(invalid,callId),/SIP180|transaction mismatch/);
console.log('PASS monitor fixture: master/PSTN/injection/duplicate rejection, exact saved identity, account/device/IP cleanup guards, web-user markers, opt-in and no queue-status mutations');
