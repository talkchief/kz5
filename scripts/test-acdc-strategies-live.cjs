#!/usr/bin/env node
'use strict';
// Opt-in isolated queue acceptance. Never MASTER, PSTN, service operations, or
// uncorrelated channel cleanup. Credentials remain in protected files/memory.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),crypto=require('node:crypto');
const assert=require('node:assert/strict'),base=require('./test-channel-monitor-live.cjs');
const {Phone}=require('./test-fixtures/strategy-sip-phone.cjs'),audio=require('./test-fixtures/monitor-audio.cjs');
const fsEvents=require('./test-fixtures/strategy-fs-events.cjs');
const API='http://127.0.0.1:8000/v2',IP='127.0.0.52',OWNER='kazoo5-isolated-ring-strategy-acceptance';
const FILE='/etc/kazoo/ring-strategy-acceptance.json',BASE='/etc/kazoo/acceptance-secrets.env';
const FSCLI='/usr/local/freeswitch/bin/fs_cli',ID=/^[a-f0-9]{32}$/,CALL=/^[A-Za-z0-9_.:@-]{1,128}$/;
let state,saved,token,runDir,current,phones=[],registered=new Set(),events=[],children=new Set(),cleaning=false,eventReader,bridgeEvents=[];
const hex=()=>crypto.randomBytes(16).toString('hex'),sleep=ms=>new Promise(r=>setTimeout(r,ms));
const log=m=>console.log('[strategy-acceptance] '+m);
function privateRead(file){const st=fs.lstatSync(file);assert(st.isFile()&&!st.isSymbolicLink()&&st.uid===0&&(st.mode&511)===384,'Unsafe protected file');return fs.readFileSync(file,'utf8');}
function parseState(text){const s=base.baseState(text),p='ACCEPTANCE_AGENT_3';
    assert(s[p+'_EXTENSION']==='1004'&&s[p+'_SIP_USERNAME']==='acceptance1004'&&ID.test(s[p+'_SIP_PASSWORD']),'Third fixture agent missing');
    for(const k of ['USER_ID','DEVICE_ID','CALLFLOW_ID'])assert(ID.test(s[p+'_'+k]),'Third fixture identity missing');
    for(const k of ['user','device','flow'])assert(new Set(endpoints(s).map(e=>e[k])).size===4,'Duplicate fixture identities');return s;}
function endpoints(s){return ['ACCEPTANCE_CALLER','ACCEPTANCE_AGENT_1','ACCEPTANCE_AGENT_2','ACCEPTANCE_AGENT_3'].map((p,i)=>({index:i,
    user:s[p+'_USER_ID'],device:s[p+'_DEVICE_ID'],flow:s[p+'_CALLFLOW_ID'],extension:s[p+'_EXTENSION'],
    username:s[p+'_SIP_USERNAME'],password:s[p+'_SIP_PASSWORD'],port:18200+i,rtp:49200+2*i}));}
const es=()=>endpoints(state),agents=()=>es().slice(1),route=(c,id='')=>`accounts/${state.ACCEPTANCE_ACCOUNT_ID}/${c}${id?'/'+id:''}`;
function mark(kind){return {owner:OWNER,deployment_id:saved.deployment_id,account_id:saved.account_id,kind};}
function owned(doc,kind,f=saved){return doc?.id===f[kind+'_id']&&doc.kz5_strategy_test&&
    Object.entries({owner:OWNER,deployment_id:f.deployment_id,account_id:f.account_id,kind}).every(([k,v])=>doc.kz5_strategy_test[k]===v);}
function validateSaved(f,s){assert(f.schema_version===1&&f.owner===OWNER&&ID.test(f.deployment_id)&&f.account_id===s.ACCEPTANCE_ACCOUNT_ID&&f.realm===s.ACCEPTANCE_REALM,'Saved fixture scope mismatch');
    assert(JSON.stringify(f.device_ids)===JSON.stringify(endpoints(s).map(e=>e.device)),'Saved devices changed');
    for(const kind of ['queue','flow'])if(f[kind+'_id'])assert(ID.test(f[kind+'_id']),'Invalid owned resource ID');
    if(f.agents){assert(JSON.stringify(Object.keys(f.agents).sort())===JSON.stringify(endpoints(s).slice(1).map(e=>e.user).sort()),'Saved agent ownership mismatch');
        for(const a of Object.values(f.agents))assert(['login','ready','logout','logged_out'].includes(a.status)&&Array.isArray(a.membership)&&a.membership.every(i=>ID.test(i)), 'Unsafe saved agent restoration');}
    if(f.current)assert(/^1-[1-9][0-9]*@127\.0\.0\.52$/.test(f.current.caller_id),'Invalid saved fixture caller');return f;}
function save(){const d=fs.lstatSync('/etc/kazoo');assert(d.isDirectory()&&!d.isSymbolicLink()&&d.uid===0&&(d.mode&18)===0,'Unsafe state directory');
    if(fs.existsSync(FILE))privateRead(FILE);const tmp=FILE+'.'+hex()+'.tmp';const fd=fs.openSync(tmp,fs.constants.O_CREAT|fs.constants.O_EXCL|fs.constants.O_WRONLY|fs.constants.O_NOFOLLOW,384);
    try{fs.writeFileSync(fd,JSON.stringify(saved)+'\n');fs.fsyncSync(fd);}finally{fs.closeSync(fd);}fs.renameSync(tmp,FILE);}
function write(name,content){assert(path.basename(name)===name,'Unsafe evidence name');const p=path.join(runDir,name);fs.writeFileSync(p,content,{mode:384,flag:'wx'});return p;}
function command(file,args,timeout=10000){try{return cp.execFileSync(file,args,{encoding:'utf8',timeout,maxBuffer:8*1024*1024,stdio:['ignore','pipe','pipe']});}
    catch(_){throw Error('Local command failed: '+path.basename(file));}}
async function request(method,p,data){let r,j;try{r=await fetch(API+'/'+p,{method,headers:{'Content-Type':'application/json',...(token?{'X-Auth-Token':token}:{})},
    body:data===undefined?undefined:JSON.stringify({data}),signal:AbortSignal.timeout(15000)});j=await r.json();}catch(_){throw Error('Local API unavailable');}
    if(![200,201,202].includes(r.status)){const e=Error(`API ${method} failed HTTP${r.status}`);e.http_status=r.status;throw e;}assert(j.status==='success','API response did not succeed');return j;}
async function authenticate(){const vals={};for(const l of privateRead('/etc/kazoo/installer-secrets.env').split('\n')){if(!l||l.startsWith('#'))continue;const at=l.indexOf('=');assert(at>0,'Invalid credential data');vals[l.slice(0,at)]=l.slice(at+1);}
    const result=await request('PUT','user_auth',{credentials:crypto.createHash('md5').update(vals.KAZOO_MASTER_ADMIN_USER+':'+vals.KAZOO_MASTER_ADMIN_PASSWORD).digest('hex'),method:'md5',realm:vals.KAZOO_MASTER_ACCOUNT_REALM});
    assert(result.data.account_id===base.MASTER&&typeof result.auth_token==='string','Unexpected authentication account');token=result.auth_token;}
async function inventory(c){const j=await request('GET',route(c)+'?paginate=false');assert(Array.isArray(j.data)&&!j.next_start_key&&j.data.length<500,'Incomplete fixture inventory');return j.data;}
async function verifyBorrowed(){const a=(await request('GET',`accounts/${state.ACCEPTANCE_ACCOUNT_ID}`)).data;
    assert(a.id===state.ACCEPTANCE_ACCOUNT_ID&&a.name===state.ACCEPTANCE_ACCOUNT_NAME&&a.realm===state.ACCEPTANCE_REALM&&!a.call_forward?.enabled,'Acceptance account drift');
    for(const e of es()){
        const u=(await request('GET',route('users',e.user))).data,d=(await request('GET',route('devices',e.device))).data,f=(await request('GET',route('callflows',e.flow))).data;
        assert(u.id===e.user&&u.enabled===true&&u.priv_level==='user'&&!u.call_forward?.enabled,'Borrowed user identity changed');
        assert(d.id===e.device&&d.owner_id===e.user&&d.enabled===true&&['softphone','sip_device'].includes(d.device_type)&&d.sip?.method==='password'&&
            d.sip.username===e.username&&d.sip.password===e.password&&d.sip.transport==='udp'&&(!d.sip.realm||d.sip.realm===state.ACCEPTANCE_REALM)&&
            !d.call_forward?.enabled&&!d.failover&&!d.route&&!d.sip.route&&!d.sip.ip,'Borrowed device authentication/routing changed');
        assert(f.id===e.flow&&JSON.stringify(f.numbers)===JSON.stringify([e.extension])&&f.flow?.module==='user'&&f.flow.data.id===e.user&&Object.keys(f.flow.children||{}).length===0,'Borrowed internal route changed');
    }}
async function status(e){const d=(await request('GET',route('agents',e.user)+'/status')).data;return typeof d==='string'?d:d?.status;}
async function until(fn,seconds=15,checkObservers=true){const end=Date.now()+seconds*1000;while(Date.now()<end){
    if(checkObservers){for(const p of phones)if(p.failure)throw p.failure;
        for(const child of children)assert(!child.fixtureError,'Synthetic caller process failed');
        if(eventReader)assert(!eventReader.failure&&eventReader.child.exitCode===null,'Scoped bridge-event observation failed: '+(eventReader.failure||'reader exited'));}
    const v=await fn();if(v)return v;await sleep(200);}throw Error('Bounded live observation timed out');}
async function setStatus(e,action){await request('POST',route('agents',e.user)+'/status',{status:action});
    await until(async()=>['login','ready'].includes(action)?['login','ready'].includes(await status(e)):['logout','logged_out'].includes(await status(e)),30);}
async function readyAgents(exclude=[]){for(const e of agents().filter(e=>!exclude.includes(e.index)))await until(async()=>['login','ready'].includes(await status(e)),30);}
async function snapshotAgents(){saved.agents={};for(const e of agents()){
    const s=await status(e);assert(['login','ready','logout','logged_out'].includes(s),'Borrowed agent is busy/paused; refusing status override');
    const membership=(await request('GET',route('agents',e.user)+'/queue_status')).data;assert(Array.isArray(membership)&&membership.every(x=>ID.test(x)),'Unknown queue membership');
    saved.agents[e.user]={status:s,membership};}save();}
async function ensureResource(kind,collection,body,collision){if(!saved[kind+'_id']){
    const matches=(await inventory(collection)).filter(collision);assert(matches.length<=1,'Ambiguous fixture collision');
    if(matches.length){saved[kind+'_id']=matches[0].id;const d=(await request('GET',route(collection,matches[0].id))).data;assert(owned(d,kind),'Refusing unmarked fixture collision');save();}
    else {const d=(await request('PUT',route(collection),body)).data;assert(ID.test(d.id),'Invalid created ID');saved[kind+'_id']=d.id;save();}}
    assert(owned((await request('GET',route(collection,saved[kind+'_id']))).data,kind),'Owned resource marker changed');}
async function ensureFixture(){await ensureResource('queue','queues',{name:'Strategy Acceptance 2700',strategy:'round_robin',connection_timeout:60,agent_ring_timeout:3,
    agent_wrapup_time:0,enter_when_empty:true,record_caller:false,announcements:{position_announcements_enabled:false,wait_time_announcements_enabled:false},callback:{enabled:false},kz5_strategy_test:mark('queue')},d=>d.name==='Strategy Acceptance 2700');
    await ensureResource('flow','callflows',{name:'Strategy Acceptance 2700',numbers:['2700'],flow:{module:'acdc_member',data:{id:saved.queue_id},children:{}},kz5_strategy_test:mark('flow')},d=>d.numbers?.includes('2700'));
    const f=(await request('GET',route('callflows',saved.flow_id))).data;assert(JSON.stringify(f.numbers)==='["2700"]'&&f.flow.module==='acdc_member'&&f.flow.data.id===saved.queue_id,'Owned queue route changed');
    const roster=(await request('GET',route('queues',saved.queue_id)+'/roster')).data;assert(Array.isArray(roster)&&roster.every(id=>agents().some(e=>e.user===id)),'Unrelated agent in owned queue');
    await request('POST',route('queues',saved.queue_id)+'/roster',agents().map(e=>e.user));
    for(const e of agents())await setStatus(e,'login');}
async function configure(strategy){const q=(await request('GET',route('queues',saved.queue_id))).data;assert(owned(q,'queue'),'Cannot edit unowned queue');
    await request('PATCH',route('queues',saved.queue_id),{strategy,agent_order:agents().map(e=>e.user),agent_ring_timeout:3,agent_wrapup_time:0});
    await sleep(1200);await readyAgents();}
function contacts(e){const r=cp.spawnSync('kamcmd',['ul.lookup','location',e.username+'@'+state.ACCEPTANCE_REALM],{encoding:'utf8',timeout:5000});
    if(r.status!==0){assert((r.stdout+r.stderr).includes('404'),'Registrar unavailable');return [];}
    return [...r.stdout.matchAll(/^\s*Address:\s*(sip:\S+)/gm)].map(m=>m[1].split(';')[0]);}
function register(e,expires){const expected=`sip:${e.username}@${IP}:${e.port}`;assert(contacts(e).every(c=>c===expected),'Fixture identity has a foreign contact');
    const csv=write(`registration-${e.index}-${hex()}.csv`,`SEQUENTIAL\n${e.username};[authentication username=${e.username} password=${e.password}];${state.ACCEPTANCE_REALM};${e.port};${expires}\n`);
    if(expires)registered.add(e.index);try{command('sipp',[state.ACCEPTANCE_SIP_PROXY_HOST+':5060','-sf',path.join(__dirname,'sip-tests/register.xml'),'-inf',csv,
        '-i',IP,'-p',String(e.port),'-m','1','-l','1','-r','1','-nostdin','-timeout','15s','-timeout_error'],20000);}finally{fs.unlinkSync(csv);}
    assert(JSON.stringify(contacts(e))===JSON.stringify(expires?[expected]:[]),'Exact fixture registration mismatch');if(!expires)registered.delete(e.index);}
function channel(id){assert(CALL.test(id),'Unsafe channel ID');const t=command(FSCLI,['-x',`uuid_dump ${id} json`],5000);if(t.trim().startsWith('-ERR'))return null;
    let d;try{d=JSON.parse(t);}catch(_){throw Error('Invalid channel diagnostic');}assert(d['Unique-ID']===id,'Channel ID mismatch');
    return {id,account:d['variable_ecallmgr_Account-ID'],device:d['variable_ecallmgr_Authorizing-ID'],authorizing_type:d['variable_ecallmgr_Authorizing-Type'],to_user:d.variable_sip_to_user,
        agent:d['variable_ecallmgr_Agent-ID'],member:d['variable_ecallmgr_Member-Call-ID'],auth_ip:d['variable_sip_h_X-AUTH-IP'],
        ip:d.variable_sip_contact_host,port:Number(d.variable_sip_contact_port),peer:d.variable_sip_network_ip,bridge:d.variable_bridge_to||d['Other-Leg-Unique-ID'],
        answered:Number(d['Caller-Channel-Answered-Time']||d.variable_answer_epoch||0)>0};}
function ownedChannel(c,e,caller,account,proxy,callerDevice){return !!(c&&c.account===account&&c.ip===IP&&c.port===e.port&&[IP,proxy].includes(c.peer)&&
    (!c.auth_ip||c.auth_ip===IP)&&(e.index===0?c.id===caller&&c.device===e.device:c.agent===e.user&&c.member===caller&&
        ([e.device,callerDevice].includes(c.device)||(c.device===e.user&&c.authorizing_type==='user'&&c.to_user===e.device))));}
function ownedNow(c,e){return ownedChannel(c,e,current.caller_id,state.ACCEPTANCE_ACCOUNT_ID,state.ACCEPTANCE_SIP_PROXY_HOST,es()[0].device);}
function channelRows(d){if(d?.row_count===0&&(d.rows===undefined||Array.isArray(d.rows)&&d.rows.length===0))return [];
    assert(Array.isArray(d?.rows)&&d.rows.length===d.row_count,'Unusable channel inventory');return d.rows;}
function rows(){return channelRows(JSON.parse(command(FSCLI,['-x','show channels as json'])));}
function fixtureChannels(){const all=rows().map(r=>channel(r.uuid)).filter(c=>c?.account===state.ACCEPTANCE_ACCOUNT_ID);
    for(const c of all)assert(es().some(e=>ownedNow(c,e)),'Isolated tenant contains an unowned or uncorrelated call');return all;}
async function noTenantCalls(){const d=(await request('GET',route('channels'))).data;assert(d&&Object.keys(d).length===0,'Acceptance tenant already has active calls');}
async function startEventReader(){const child=cp.spawn('stdbuf',['-oL',FSCLI,'-b','-q','-n'],{stdio:['pipe','pipe','ignore']});
    const reader={child,buffer:'',filtered:false,subscribed:false,failure:false};eventReader=reader;child.once('error',()=>{reader.failure=true;});
    child.stdout.on('data',chunk=>{try{const text=chunk.toString();
        reader.buffer+=text;assert(reader.buffer.length<2*1024*1024,'Oversized event observation');
        reader.filtered ||= reader.buffer.includes('+OK filter added. [variable_ecallmgr_Account-ID]=['+state.ACCEPTANCE_ACCOUNT_ID+']');
        reader.subscribed ||= reader.buffer.includes('+OK event listener enabled json');
        const result=fsEvents.extract(reader.buffer);reader.buffer=result.rest;
        for(const e of result.events){assert(e['variable_ecallmgr_Account-ID']===state.ACCEPTANCE_ACCOUNT_ID,'Unscoped event received');
            if(current){const other=fsEvents.partner(e,current.caller_id,state.ACCEPTANCE_ACCOUNT_ID);if(other)bridgeEvents.push({
                type:e['Event-Name'],partner:other,time:Number(e['Event-Date-Timestamp'])});}}
    }catch(error){reader.failure=error.message;}});
    child.stdin.write('/filter variable_ecallmgr_Account-ID '+state.ACCEPTANCE_ACCOUNT_ID+'\n');
    await until(()=>reader.filtered,10);
    child.stdin.write('/event json CHANNEL_BRIDGE CHANNEL_UNBRIDGE\n');await until(()=>reader.subscribed,10);}
function startCaller(){const e=es()[0],csv=write('caller-'+hex()+'.csv',`SEQUENTIAL\n${e.username};[authentication username=${e.username} password=${e.password}];${state.ACCEPTANCE_REALM};2700;60000;0;${path.join(runDir,'tone-440.ulaw')}\n`);
    const child=cp.spawn('sipp',[state.ACCEPTANCE_SIP_PROXY_HOST+':5060','-sf',path.join(__dirname,'sip-tests/monitor-customer.xml'),'-inf',csv,
        '-i',IP,'-p',String(e.port),'-mi',IP,'-mp',String(e.rtp),'-min_rtp_port',String(e.rtp),'-max_rtp_port',String(e.rtp+1),
        '-m','1','-l','1','-r','1','-nostdin','-aa','-timeout','90s','-timeout_error'],{stdio:'ignore'});
    children.add(child);child.once('error',()=>{child.fixtureError=true;});child.once('exit',()=>children.delete(child));return child;}
async function closeCall(){if(!current)return;
    const list=fixtureChannels();const caller=list.find(c=>c.id===current.caller_id);
    if(caller){assert(ownedNow(caller,es()[0]),'Unowned caller cleanup refused');command(FSCLI,['-x',`uuid_kill ${caller.id} NORMAL_CLEARING`]);}
    await sleep(500);
    for(const c of fixtureChannels()){assert(agents().some(e=>ownedNow(c,e)),'Unowned residual leg cleanup refused');command(FSCLI,['-x',`uuid_kill ${c.id} NORMAL_CLEARING`]);}
    await until(()=>fixtureChannels().length===0,10,false);
    for(const child of children)if(child.exitCode===null)child.kill('SIGINT');await sleep(300);
    for(const child of children)if(child.exitCode===null)child.kill('SIGKILL');
    delete saved.current;save();current=null;}
async function runCall(label,policy,expected){await noTenantCalls();await verifyBorrowed();events=[];bridgeEvents=[];
    for(const p of phones){p.policy=d=>policy(p.endpoint.index,d);p.failure=null;}
    const caller=startCaller();assert(Number.isInteger(caller.pid),'Cannot start synthetic caller');current={label,caller_id:`1-${caller.pid}@${IP}`};saved.current=current;save();
    const proof={label,bridges:[],events:[],passed:false};
    try {
        const target=await until(()=>{const c=channel(current.caller_id);if(!c?.bridge||!c.answered)return false;
            assert(ownedNow(c,es()[0]),'Caller scope changed');const a=channel(c.bridge),e=agents().find(e=>ownedNow(a,e));return a?.answered&&e?{a,e}:false;},45);
        proof.winner=target.e.index;proof.agent_call_id=target.a.id;
        const observed=new Set();for(let i=0;i<12;i++){
            const channels=fixtureChannels(),c=channels.find(c=>c.id===current.caller_id);assert(c?.answered&&c.bridge===target.a.id,'Original bridge changed or disappeared');
            const linked=channels.filter(x=>x.id!==c.id&&x.bridge===c.id&&x.answered);assert(linked.length===1&&linked[0].id===target.a.id,'Duplicate customer bridge');
            observed.add(c.bridge);proof.bridges.push({time:Date.now(),agent:target.e.index,linked_agent_legs:linked.length});await sleep(200);}
        const residual=fixtureChannels().filter(c=>c.id!==current.caller_id&&c.id!==target.a.id);assert(residual.length===0,'Losing agent channel remained active');
        assert(observed.size===1,'Multiple bridge winners observed');
        const mediaWinners=new Set(bridgeEvents.filter(e=>e.type==='CHANNEL_BRIDGE').map(e=>e.partner));
        assert.equal(mediaWinners.size,1,'Missing or multiple winning bridge events');assert(mediaWinners.has(target.a.id),'Event and live bridge winner disagree');
        proof.bridge_events=bridgeEvents.slice();proof.events=events.slice();expected(proof);
        proof.passed=true;return proof;
    } catch(error){proof.failure=error.message;log(label+' did not pass: '+error.message);throw error;
    } finally {proof.events=events.slice();proof.bridge_events=bridgeEvents.slice();write(label+'-evidence.json',JSON.stringify(proof,null,2)+'\n');await closeCall();}}
const offers=p=>p.events.filter(e=>e.type==='invite');
function assertLosers(p){for(const e of offers(p).filter(e=>e.agent!==p.winner))assert(p.events.some(x=>x.call_id===e.call_id&&['cancel','bye'].includes(x.type)),'Losing INVITE lacked CANCEL/BYE');}
async function stages(){const proofs=[];
    await configure('ring_all');
    for(let n=0;n<3;n++){await readyAgents();proofs.push(await runCall('ring-all-'+(n+1),i=>i===1?1500:null,p=>{assert.deepEqual(offers(p).map(e=>e.agent).sort(),[1,2,3]);
        const ts=offers(p).map(e=>e.time);assert(Math.max(...ts)-Math.min(...ts)<1200,'Ring-all was not concurrent');assert.equal(p.winner,1);assertLosers(p);}));}
    await readyAgents();let barrier;
    proofs.push(await runCall('ring-all-answer-race',()=>{barrier??=Date.now()+1500;return Math.max(0,barrier-Date.now());},p=>{
        assert.deepEqual(offers(p).map(e=>e.agent).sort(),[1,2,3]);assert(p.events.filter(e=>e.type==='answer').length>=2,'Did not exercise a multiple-answer race');assertLosers(p);}));
    await readyAgents();assert((await Promise.all(agents().map(status))).every(s=>['ready','login'].includes(s)),'Ring-all caused agent logout');
    await configure('in_order');
    proofs.push(await runCall('in-order-progression',i=>i===3?300:null,p=>{assert.deepEqual(offers(p).map(e=>e.agent),[1,2,3]);assert.equal(p.winner,3);
        const o=offers(p);for(let n=1;n<o.length;n++)assert(o[n].time-o[n-1].time>=2500,'Ordered agents rang simultaneously');}));
    await readyAgents();await setStatus(agents()[0],'logout');
    proofs.push(await runCall('in-order-skip-unavailable',()=>300,p=>{assert.deepEqual(offers(p).map(e=>e.agent),[2]);assert.equal(p.winner,2);}));
    await setStatus(agents()[0],'login');await configure('round_robin');const rr=[];
    for(let n=0;n<6;n++){await readyAgents();const p=await runCall('round-robin-'+(n+1),()=>300,p=>assert.equal(offers(p).length,1));rr.push(p.winner);proofs.push(p);}
    assert(new Set(rr.slice(0,3)).size===3&&JSON.stringify(rr.slice(0,3))===JSON.stringify(rr.slice(3)),'Round-robin did not rotate fairly across two cycles');
    await configure('most_idle');proofs.push(await runCall('most-idle-single-offer',()=>300,p=>{assert.equal(offers(p).length,1);
        assert.equal(p.winner,rr[3],'Most-idle did not choose the longest-idle agent after the measured RR cycle');}));await readyAgents();
    write('summary.json',JSON.stringify({passed:true,account_id:state.ACCEPTANCE_ACCOUNT_ID,queue_id:saved.queue_id,proofs:proofs.map(p=>({label:p.label,winner:p.winner})),
        unproven:['cross-FreeSWITCH-node races','native callback ring-all','large-scale load','audio quality or whisper privacy']},null,2)+'\n');
    log('PASS ring-all concurrent offers/race and loser cleanup, in-order progression/skip, two RR cycles, most-idle single offer; '+runDir);}
async function cleanup(){if(cleaning)return false;cleaning=true;let ok=true;
    try{if(current)await closeCall();}catch(e){ok=false;log('Scoped channel cleanup incomplete: '+e.message);}
    if(eventReader){eventReader.child.stdin.end();if(eventReader.child.exitCode===null)eventReader.child.kill('SIGTERM');eventReader=null;}
    for(const p of phones)p.close();phones=[];for(const child of children)if(child.exitCode===null)child.kill('SIGINT');await sleep(300);
    for(const e of es())if(registered.has(e.index)){try{await verifyBorrowed();register(e,0);}catch(_){ok=false;log('Exact fixture deregistration incomplete; expiry bounded600s');}}
    if(ok&&saved?.queue_id){try{const q=(await request('GET',route('queues',saved.queue_id))).data;assert(owned(q,'queue'),'Queue ownership drift');
        const r=(await request('GET',route('queues',saved.queue_id)+'/roster')).data;assert(Array.isArray(r)&&r.every(id=>agents().some(e=>e.user===id)),'Unrelated roster member');
        await request('POST',route('queues',saved.queue_id)+'/roster',[]);
    }catch(e){ok=false;log('Owned roster cleanup incomplete: '+e.message);}}
    if(ok&&saved?.agents)for(const e of agents())try{
        const before=saved.agents[e.user];assert(before,'Missing original agent status');const membership=(await request('GET',route('agents',e.user)+'/queue_status')).data;
        assert(JSON.stringify([...membership].sort())===JSON.stringify([...before.membership].sort()),'Original memberships changed; refusing status restoration');
        assert(['ready','login','logout','logged_out'].includes(await status(e)),'Borrowed agent became paused/busy; refusing to overwrite its status');
        await setStatus(e,['ready','login'].includes(before.status)?'login':'logout');
    }catch(e){ok=false;log('Borrowed agent restoration incomplete: '+e.message);}
    if(ok)for(const [kind,collection] of [['flow','callflows'],['queue','queues']])if(saved[kind+'_id'])try{
        const d=(await request('GET',route(collection,saved[kind+'_id']))).data;assert(owned(d,kind),'Owned cleanup marker changed');
        await request('DELETE',route(collection,saved[kind+'_id']));delete saved[kind+'_id'];save();
    }catch(e){if(e.http_status===404){delete saved[kind+'_id'];save();}else{ok=false;log('Owned resource cleanup incomplete: '+e.message);}}
    if(ok&&fs.existsSync(FILE)){fs.unlinkSync(FILE);log('Only owned queue/flow removed; original agent memberships/statuses restored');}
    if(runDir)for(const name of fs.readdirSync(runDir))if(name.endsWith('.csv'))fs.unlinkSync(path.join(runDir,name));return ok;}
function prepare(){state=parseState(privateRead(BASE));const local=JSON.parse(command('ip',['-j','-4','address','show'])).flatMap(x=>x.addr_info||[]).map(x=>x.local);
    assert(local.includes(state.ACCEPTANCE_SIP_PROXY_HOST),'SIP proxy must be local');assert(fs.existsSync(FSCLI),'FS diagnostic client missing');
    const sipp=cp.spawnSync('sipp',['-v'],{encoding:'utf8',timeout:5000});assert(!sipp.error&&(sipp.stdout+sipp.stderr).includes('SIPp v3.7.7-TLS-PCAP-SHA256'),'Pinned SIPp version required');
    log('Prepared only: isolated borrowed1001–1004 and marked queue2700; no API writes, registrations or calls');return local;}
async function main(args){assert(args.length===1&&['--prepare-only','--live','--cleanup'].includes(args[0]),'Use --prepare-only, --live or --cleanup');
    assert(process.getuid()===0,'Root required');const peers=prepare();if(args[0]==='--prepare-only')return;
    const lockPath='/etc/kazoo/monitor-acceptance.lock';if(fs.existsSync(lockPath)){const s=fs.lstatSync(lockPath);assert(s.isFile()&&!s.isSymbolicLink()&&s.uid===0,'Unsafe shared acceptance lock');}
    const lock=cp.spawn('flock',['-n',lockPath,process.execPath,'-e','process.stdin.resume();'],{stdio:['pipe','ignore','ignore']});await sleep(100);assert(lock.exitCode===null,'Another acceptance run is active');
    try{process.umask(63);runDir=fs.mkdtempSync('/var/log/kazoo-strategy-acceptance-');fs.chmodSync(runDir,448);await authenticate();await verifyBorrowed();
        if(fs.existsSync(FILE))saved=validateSaved(JSON.parse(privateRead(FILE)),state);
        else {assert(args[0]==='--live','No saved fixture');saved={schema_version:1,owner:OWNER,deployment_id:hex(),account_id:state.ACCEPTANCE_ACCOUNT_ID,realm:state.ACCEPTANCE_REALM,device_ids:es().map(e=>e.device)};save();}
        current=saved.current||null;
        if(args[0]==='--cleanup'){es().forEach(e=>{if(contacts(e).includes(`sip:${e.username}@${IP}:${e.port}`))registered.add(e.index);});assert(await cleanup(),'Cleanup incomplete');return;}
        assert(!current&&!saved.agents,'An unfinished run requires --cleanup first');await noTenantCalls();es().forEach(e=>assert(contacts(e).length===0,'Borrowed identity already registered; refusing takeover'));
        await snapshotAgents();
        process.once('SIGTERM',()=>{cleanup().finally(()=>process.exit(143));});process.once('SIGINT',()=>{cleanup().finally(()=>process.exit(130));});
        try{await ensureFixture();write('tone-440.ulaw',audio.tone([440]));for(const e of es())register(e,600);
            phones=agents().map(e=>new Phone(e,IP,peers.concat(['127.0.0.1',IP]),evt=>events.push(evt)));for(const p of phones)await p.start();await startEventReader();await stages();
        }finally{assert(await cleanup(),'Scoped cleanup incomplete; protected recovery state retained');}
    }finally{lock.stdin.end();if(lock.exitCode===null)lock.kill('SIGTERM');}}
module.exports={parseState,endpoints,validateSaved,owned,ownedChannel,channelRows,OWNER,IP};
if(require.main===module)main(process.argv.slice(2)).catch(e=>{console.error('[strategy-acceptance] FAIL: '+e.message);process.exitCode=1;});
