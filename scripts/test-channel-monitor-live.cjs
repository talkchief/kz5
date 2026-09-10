#!/usr/bin/env node
'use strict';
// Opt-in synthetic audio acceptance. Default monitoring never changes queue
// status. Explicit distributed queue-partition mode may pause only its two
// admitted synthetic alternate agents, with bounded expiry and owned recovery.
// No MASTER resources, PSTN routes or uncorrelated cleanup are allowed.
const fs=require('node:fs'), path=require('node:path'), crypto=require('node:crypto');
const cp=require('node:child_process'), assert=require('node:assert/strict');
let audio=require('./test-fixtures/monitor-audio.cjs');
const ROOT=path.resolve(__dirname,'..');
let API='http://127.0.0.1:8000/v2', BASE='/etc/kazoo/acceptance-secrets.env', FILE='/etc/kazoo/monitor-acceptance.json';
let AUTH='/etc/kazoo/installer-secrets.env', MASTER='302ae5a70c403124f764cbc54229cfcd', distributed=null;
const OWNER='kazoo5-isolated-monitor-acceptance', ID=/^[a-f0-9]{32}$/, CALL=/^[A-Za-z0-9_.:@-]{1,128}$/;
const SCENARIOS=path.join(__dirname,'sip-tests'), FSCLI='/usr/local/freeswitch/bin/fs_cli';
let state, fixture, masterToken, adminToken, userToken, runDir, current, cleaning=false;
let partitionEnabled=false, queuePartitionEnabled=false, queueCallsEnabled=false, mediaFenceEnabled=false, controllerFault=null;
let mainDev=null;
const children=new Set(), registered=new Set();
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const hex=()=>crypto.randomBytes(16).toString('hex');
const log=message=>console.log('[monitor-acceptance] '+message);

function privateRead(file) {
    const s=fs.lstatSync(file);
    assert(s.isFile()&&!s.isSymbolicLink()&&s.uid===0&&(s.mode&511)===384,'Protected file must be root-owned0600');
    return fs.readFileSync(file,'utf8');
}
function baseState(text) {
    const s={};
    for(const line of text.split('\n')) {
        if(!line||line.startsWith('#')) continue;
        const at=line.indexOf('='), key=line.slice(0,at), encoded=line.slice(at+1);
        assert(at>0&&/^ACCEPTANCE_[A-Z0-9_]+$/.test(key)&&!Object.hasOwn(s,key),'Malformed acceptance key');
        assert(/^[A-Za-z0-9+/]*={0,2}$/.test(encoded),'Malformed acceptance encoding');
        const value=Buffer.from(encoded,'base64').toString();
        assert(!/[\r\n\0]/.test(value),'Multiline acceptance value'); s[key]=value;
    }
    assert(ID.test(s.ACCEPTANCE_ACCOUNT_ID)&&s.ACCEPTANCE_ACCOUNT_ID!==MASTER,'Refusing MASTER or invalid tenant');
    assert(/^Kazoo5 Acceptance [a-f0-9]{12}$/.test(s.ACCEPTANCE_ACCOUNT_NAME)&&
        /^acceptance-[a-f0-9]{12}\.invalid$/.test(s.ACCEPTANCE_REALM),'Not an isolated acceptance tenant');
    assert(s.ACCEPTANCE_ACCOUNT_NAME.slice(-12)===s.ACCEPTANCE_REALM.slice(11,23),'Acceptance identity mismatch');
    assert(s.ACCEPTANCE_CALLER_EXTENSION==='1001'&&s.ACCEPTANCE_AGENT_1_EXTENSION==='1002'&&
        s.ACCEPTANCE_AGENT_2_EXTENSION==='1003','Only internal1001–1003 permitted');
    assert(s.ACCEPTANCE_SIP_PROXY_PORT==='5060'&&s.ACCEPTANCE_SIP_TRANSPORT==='udp'&&
        /^(?:\d{1,3}\.){3}\d{1,3}$/.test(s.ACCEPTANCE_SIP_PROXY_HOST),'Only pinned local IPv4 SIP proxy allowed');
    for(const prefix of ['ACCEPTANCE_CALLER','ACCEPTANCE_AGENT_1','ACCEPTANCE_AGENT_2']) {
        for(const key of ['USER_ID','DEVICE_ID','CALLFLOW_ID']) assert(ID.test(s[prefix+'_'+key]),'Missing fixture resource ID');
        assert(/^acceptance100[123]$/.test(s[prefix+'_SIP_USERNAME'])&&/^[a-f0-9]{32}$/.test(s[prefix+'_SIP_PASSWORD']),
            'Unsafe or non-fixture SIP credential');
    }
    for(const kind of ['USER_ID','DEVICE_ID','CALLFLOW_ID'])
        assert(new Set(['ACCEPTANCE_CALLER','ACCEPTANCE_AGENT_1','ACCEPTANCE_AGENT_2'].map(p=>s[p+'_'+kind])).size===3,
            'Duplicate borrowed fixture identity');
    return s;
}
function endpoints(s) {
    return ['ACCEPTANCE_CALLER','ACCEPTANCE_AGENT_1','ACCEPTANCE_AGENT_2'].map((prefix,i)=>({
        role:['customer','agent','supervisor'][i], port:18100+i, rtp:49000+2*i,
        device:s[prefix+'_DEVICE_ID'], user:s[prefix+'_USER_ID'], flow:s[prefix+'_CALLFLOW_ID'],
        extension:s[prefix+'_EXTENSION'], username:s[prefix+'_SIP_USERNAME'], password:s[prefix+'_SIP_PASSWORD']}));
}
function validFixture(f,s) {
    assert(f.schema_version===1&&f.owner===OWNER&&ID.test(f.deployment_id)&&f.account_id===s.ACCEPTANCE_ACCOUNT_ID,
        'Saved monitor fixture ownership mismatch');
    assert(f.realm===s.ACCEPTANCE_REALM&&JSON.stringify(f.device_ids)===JSON.stringify(endpoints(s).map(e=>e.device)),
        'Saved fixture identity drift');
    for(const role of ['admin','user']) {
        const u=f.users[role];
        assert(u&&u.username===`monitor-${role}-${f.deployment_id.slice(0,12)}`&&ID.test(u.password)&&(!u.id||ID.test(u.id)),
            'Saved fixture web-user mismatch');
    }
    if(f.current) {
        assert(new RegExp('^1-[1-9][0-9]*@'+audio.IP.replaceAll('.','\\.')+'$').test(f.current.caller_id)&&
            ['eavesdrop','whisper','barge','join','queue_partition'].includes(f.current.mode),'Invalid saved fixture call');
        if(f.current.agent_id) assert(CALL.test(f.current.agent_id),'Invalid saved agent ID');
        if(f.current.supervisor_id) assert(ID.test(f.current.supervisor_id)&&ID.test(f.current.request_id),'Invalid monitor correlation');
    }
    if(f.queue_paused) {
        assert(s.ACCEPTANCE_ACCOUNT_ID==='45e827067baf078029d0ca16a489fa8a'&&
            Array.isArray(f.queue_paused)&&f.queue_paused.length<=2&&new Set(f.queue_paused).size===f.queue_paused.length);
        for(const id of f.queue_paused)assert(ID.test(id)&&
            [s.ACCEPTANCE_AGENT_2_USER_ID,s.ACCEPTANCE_AGENT_3_USER_ID].includes(id),'Unowned paused agent');
    }
    if(f.media_fence)require('./test-fixtures/distributed-lab/media-fence.cjs').validate(f.media_fence,f.deployment_id,distributed?.media);
    return f;
}
function saveFixture() {
    const parent=fs.lstatSync('/etc/kazoo');
    assert(parent.isDirectory()&&!parent.isSymbolicLink()&&parent.uid===0&&(parent.mode&18)===0,'Unsafe state directory');
    if(fs.existsSync(FILE)) privateRead(FILE);
    const tmp=FILE+'.'+process.pid+'.'+hex()+'.tmp';
    const fd=fs.openSync(tmp,fs.constants.O_CREAT|fs.constants.O_EXCL|fs.constants.O_WRONLY|fs.constants.O_NOFOLLOW,384);
    try {fs.writeFileSync(fd,JSON.stringify(fixture)+'\n');fs.fsyncSync(fd);} finally {fs.closeSync(fd);}
    fs.renameSync(tmp,FILE);
}
function command(file,args,timeout=15000) {
    if(distributed&&file===FSCLI){args=['exec',distributed.media,file,...args];file='podman';}
    try {return cp.execFileSync(file,args,{encoding:'utf8',timeout,maxBuffer:4*1024*1024,stdio:['ignore','pipe','pipe']});}
    catch(_) {throw Error('Local dependency/diagnostic command failed: '+path.basename(file));}
}
async function request(method,route,body,token,expected=200) {
    let r,j;
    try {
        // Synchronous SIPp/FS commands can keep this event loop blocked beyond
        // Cowboy's idle keep-alive deadline. Do not reuse such sockets or
        // automatically retry mutating requests after an ambiguous response.
        r=await fetch(API+'/'+route,{method,headers:{'Content-Type':'application/json','Connection':'close',...(token?{'X-Auth-Token':token}:{})},
            body:body===undefined?undefined:JSON.stringify({data:body}),signal:AbortSignal.timeout(15000)});
        j=await r.json();
    } catch(error) {
        const kind=[error.name,error.cause?.code].filter(v=>typeof v==='string'&&/^[A-Za-z0-9_]+$/.test(v)).join('/');
        throw Error(`Local Crossbar response unavailable: ${method} ${route.split('?')[0]} (${kind||'unknown'})`);
    }
    const accepted=Array.isArray(expected)?expected:[expected];
    if(!accepted.includes(r.status)) {
        const safeRoute=route.split('?')[0];
        assert(/^[A-Za-z0-9_/-]{1,200}$/.test(safeRoute),'Unexpected diagnostic route');
        const retryAfter=r.headers.get('retry-after');
        const retry=/^[0-9]{1,4}$/.test(retryAfter||'')?`; retry-after ${retryAfter}s`:'';
        const category=/^[a-z_]{1,64}$/.test(j.message||'')?`; ${j.message}`:'';
        const monitorReasons=['channel ownership could not be verified','monitor execution could not be submitted',
            'live target or supervisor route could not be verified','supervisor termination could not be verified'];
        const reasonText=[j.data?.message,j.message].find(v=>monitorReasons.includes(v));
        const reason=reasonText?`; ${reasonText}`:'';
        const requestId=/^[a-f0-9]{32}$/.test(j.request_id||'')?`; request ${j.request_id}`:'';
        const error=Error(`Expected HTTP${expected}, received${r.status} for ${method} ${safeRoute}${category}${retry}${reason}${requestId}`);
        error.http_status=r.status;throw error;
    }
    if(r.status<300) assert(j.status==='success','Crossbar did not succeed');
    return j;
}
const route=(collection,id='')=>`accounts/${state.ACCEPTANCE_ACCOUNT_ID}/${collection}${id?'/'+id:''}`;
async function login(username,password,realm,account) {
    // Fresh distributed lab keeps the normal anti-abuse bucket: three fixture
    // logins at35 tokens each exceed its100-token burst when sent together.
    // Pace setup; never disable rate limiting or replay rejected mutations.
    if(distributed||mainDev)await sleep(4000);
    const j=await request('PUT','user_auth',{credentials:crypto.createHash('md5').update(username+':'+password).digest('hex'),method:'md5',realm},undefined,[200,201]);
    assert(j.data.account_id===account&&typeof j.auth_token==='string','Authentication account mismatch'); return j.auth_token;
}
async function authenticateMaster() {
    const values={};
    for(const line of privateRead(AUTH).split('\n')) {
        if(!line||line.startsWith('#')) continue;
        const at=line.indexOf('='); assert(at>0,'Malformed master credential file'); values[line.slice(0,at)]=line.slice(at+1);
    }
    masterToken=await login(values.KAZOO_MASTER_ADMIN_USER,values.KAZOO_MASTER_ADMIN_PASSWORD,values.KAZOO_MASTER_ACCOUNT_REALM,MASTER);
}
async function verifyBorrowed() {
    const a=(await request('GET',`accounts/${state.ACCEPTANCE_ACCOUNT_ID}`,undefined,masterToken)).data;
    assert(a.id===state.ACCEPTANCE_ACCOUNT_ID&&a.realm===state.ACCEPTANCE_REALM&&a.name===state.ACCEPTANCE_ACCOUNT_NAME,
        'Live acceptance tenant identity drift');
    assert(!a.call_forward?.enabled,'Acceptance account forwarding must be disabled');
    for(const e of endpoints(state)) {
        const u=(await request('GET',route('users',e.user),undefined,masterToken)).data;
        assert(u.id===e.user&&u.enabled===true&&u.priv_level==='user'&&!u.call_forward?.enabled,
            'Borrowed fixture user identity/forwarding changed');
        const d=(await request('GET',route('devices',e.device),undefined,masterToken)).data;
        assert(d.id===e.device&&d.owner_id===e.user&&d.enabled===true&&['softphone','sip_device'].includes(d.device_type)&&
            d.sip.method==='password'&&d.sip.username===e.username&&d.sip.password===e.password&&d.sip.transport==='udp'&&
            (!d.sip.realm||d.sip.realm===state.ACCEPTANCE_REALM)&&!d.call_forward?.enabled&&
            (!d.sip.invite_format||['username','contact'].includes(d.sip.invite_format))&&!d.sip.route&&!d.sip.ip&&!d.route&&!d.failover,
            'Borrowed fixture device identity/authentication changed');
        const f=(await request('GET',route('callflows',e.flow),undefined,masterToken)).data;
        assert(f.id===e.flow&&JSON.stringify(f.numbers)===JSON.stringify([e.extension])&&f.flow.module==='user'&&
            f.flow.data.id===e.user&&Object.keys(f.flow.children||{}).length===0,'Fixture direct route changed');
    }
}
function mark(role) {return {owner:OWNER,deployment_id:fixture.deployment_id,account_id:fixture.account_id,kind:role};}
function ownedUser(doc,role,saved=fixture) {
    const m=doc.kz5_monitor_test;
    const expected={owner:OWNER,deployment_id:saved.deployment_id,account_id:saved.account_id,kind:role};
    return doc.id===saved.users[role].id&&m&&Object.entries(expected).every(([k,v])=>m[k]===v)&&
        doc.username===saved.users[role].username&&doc.priv_level===(role==='admin'?'admin':'user')&&doc.enabled===true;
}
async function recoverUser(role) {
    const u=fixture.users[role];
    const list=await request('GET',route('users')+'?paginate=false',undefined,masterToken);
    assert(Array.isArray(list.data)&&!list.next_start_key&&list.data.length<500,'Incomplete users inventory');
    const matches=list.data.filter(d=>d.username===u.username);assert(matches.length<=1,'Ambiguous fixture user');
    if(!matches.length)return false;
    assert(ID.test(matches[0].id),'Invalid discovered user ID');u.id=matches[0].id;
    const doc=(await request('GET',route('users',u.id),undefined,masterToken)).data;
    assert(ownedUser(doc,role),'Cannot adopt unmarked fixture username');saveFixture();return true;
}
async function ensureUsers() {
    for(const role of ['admin','user']) {
        const u=fixture.users[role];
        if(!u.id) {
            // Recover only an exact persisted marker after a lost create response.
            if(!await recoverUser(role)) {
                const doc=(await request('PUT',route('users'),{first_name:'Monitor Acceptance',last_name:role,username:u.username,
                    password:u.password,enabled:true,priv_level:role==='admin'?'admin':'user',kz5_monitor_test:mark(role)},masterToken,[200,201])).data;
                assert(ID.test(doc.id),'Invalid created user ID');u.id=doc.id;saveFixture();
            }
        }
        assert(ownedUser((await request('GET',route('users',u.id),undefined,masterToken)).data,role),'Live monitor user ownership drift');
    }
    adminToken=await login(fixture.users.admin.username,fixture.users.admin.password,fixture.realm,fixture.account_id);
    userToken=await login(fixture.users.user.username,fixture.users.user.password,fixture.realm,fixture.account_id);
}
function writePrivate(name,content) {
    const file=path.join(runDir,name);assert(path.dirname(file)===runDir,'Unsafe private filename');
    fs.writeFileSync(file,content,{mode:384,flag:'wx'});return file;
}
function contacts(e) {
    const args=['ul.lookup','location',e.username+'@'+state.ACCEPTANCE_REALM];
    const r=cp.spawnSync(distributed?'podman':'kamcmd',distributed?['exec',distributed.registrar,'kamcmd',...args]:args,{encoding:'utf8',timeout:5000});
    if(r.status!==0) {assert((r.stdout+r.stderr).includes('404'),'Registrar observation unavailable');return [];}
    return [...r.stdout.matchAll(/^\s*Address:\s*(sip:\S+)/gm)].map(m=>m[1].split(';')[0]);
}
function registration(e,expiry) {
    const csv=writePrivate(`registration-${e.role}-${expiry}-${hex()}.csv`,
        `SEQUENTIAL\n${e.username};[authentication username=${e.username} password=${e.password}];${state.ACCEPTANCE_REALM};${e.port};${expiry}\n`);
    if(expiry)registered.add(e.role); // A lost REGISTER response still requires exact cleanup.
    try {command('sipp',['-ci','127.0.0.1',state.ACCEPTANCE_SIP_PROXY_HOST+':5060','-sf',path.join(SCENARIOS,'register.xml'),'-inf',csv,
        '-i',audio.IP,'-p',String(e.port),'-m','1','-l','1','-r','1','-nostdin','-timeout','15s','-timeout_error'],20000);}
    finally {fs.unlinkSync(csv);}
    if(expiry) {
        const expected=`sip:${e.username}@${audio.IP}:${e.port}`;
        assert(JSON.stringify(contacts(e))===JSON.stringify([expected]),'Registration must resolve only exact fixture contact');
        registered.add(e.role);
    } else registered.delete(e.role);
}
function phoneCallLimit(role) {
    // SIPp counts an automatically answered out-of-dialog OPTIONS as an
    // incoming call. A receiver with -m 1 then refuses the real INVITE.
    // Keep receivers available for bounded keepalives; exact call ownership,
    // active-leg counts, the 150s deadline and scoped cleanup remain enforced.
    return role==='customer'?'1':'100';
}
function spawnPhone(e,scenario,csv) {
    const args=['-ci','127.0.0.1',...(e.role==='customer'?[state.ACCEPTANCE_SIP_PROXY_HOST+':5060']:[]),'-sf',path.join(SCENARIOS,scenario),'-inf',csv,
        '-i',audio.IP,'-p',String(e.port),'-mi',audio.IP,'-mp',String(e.rtp),'-min_rtp_port',String(e.rtp),'-max_rtp_port',String(e.rtp+1),
        '-m',phoneCallLimit(e.role),'-l','1','-nostdin','-aa','-timeout','150s','-timeout_error',
        '-trace_shortmsg','-shortmessage_file',csv.replace(/\.csv$/,'-sip.tsv')];
    const child=cp.spawn('sipp',args,{stdio:'ignore'});children.add(child);child.once('exit',()=>children.delete(child));return child;
}
function channel(id) {
    assert(CALL.test(id),'Unsafe channel ID');
    const text=command(FSCLI,['-x',`uuid_dump ${id} json`],6000);
    if(text.trim().startsWith('-ERR')) return null;
    let d;try{d=JSON.parse(text);}catch(_){throw Error('Malformed channel observation');}
    assert(d['Unique-ID']===id,'Channel observation ID mismatch');
    if(d.variable_bridge_to&&d['Other-Leg-Unique-ID'])
        assert(d.variable_bridge_to===d['Other-Leg-Unique-ID'],'Ambiguous original bridge linkage');
    return {id,account:d['variable_ecallmgr_Account-ID'],device:d['variable_ecallmgr_Authorizing-ID'],
        ip:d.variable_sip_contact_host,port:Number(d.variable_sip_contact_port),peer:d.variable_sip_network_ip,
        auth_ip:d['variable_sip_h_X-AUTH-IP'],bridge:d.variable_bridge_to||d['Other-Leg-Unique-ID'],request:d['variable_ecallmgr_Monitor-Request-ID'],
        target:d['variable_ecallmgr_Monitor-Target-ID'],mode:d['variable_ecallmgr_Monitor-Mode'],
        observed_state:d['Channel-State'],observed_answer_epoch:d.variable_answer_epoch,
        observed_answer_us:d['Caller-Channel-Answered-Time'],observed_bridge_uuid:d.variable_bridge_uuid,observed_signal_bond:d.variable_signal_bond,
        observed_authorizing_type:d['variable_ecallmgr_Authorizing-Type'],observed_endpoint_id:d['variable_ecallmgr_Endpoint-ID'],
        observed_device_id:d['variable_ecallmgr_Device-ID'],observed_sip_to_user:d.variable_sip_to_user,
        observed_acdc_agent_id:d['variable_ecallmgr_Agent-ID'],observed_acdc_member_id:d['variable_ecallmgr_Member-Call-ID'],
        active:['CS_NEW','CS_INIT','CS_ROUTING','CS_SOFT_EXECUTE','CS_EXECUTE','CS_EXCHANGE_MEDIA','CS_PARK','CS_CONSUME_MEDIA','CS_HIBERNATE','CS_RESET'].includes(d['Channel-State']),
        // uuid_dump exposes the actual answered timestamp as an event header;
        // answer_epoch is not populated on every live channel before CDR close.
        answered:Number(d['Caller-Channel-Answered-Time']||d.variable_answer_epoch||0)>0};
}
function ownedChannel(c,e,account=state.ACCEPTANCE_ACCOUNT_ID,proxy=state.ACCEPTANCE_SIP_PROXY_HOST) {
    const endpoint=c&&(c.device===e.device||(c.device===e.user&&c.observed_authorizing_type==='user'&&c.observed_sip_to_user===e.device));
    return c&&c.active===true&&c.account===account&&endpoint&&c.ip===audio.IP&&c.port===e.port&&
        [audio.IP,proxy].includes(c.peer)&&(!c.auth_ip||c.auth_ip===audio.IP);
}
function monitorMatches(c) {
    const mode=current.mode==='eavesdrop'?'listen':current.mode==='whisper'?'whisper':'full';
    return ownedChannel(c,endpoints(state)[2])&&c.request===current.request_id&&c.target===current.agent_id&&c.mode===mode;
}
async function until(fn,seconds=15) {
    const end=Date.now()+seconds*1000;while(Date.now()<end){const value=await fn();if(value)return value;await sleep(250);}throw Error('Bounded live observation timed out');
}
function originalAlive() {
    const es=endpoints(state), a=channel(current.caller_id), b=channel(current.agent_id);
    assert(ownedChannel(a,es[0])&&ownedChannel(b,es[1])&&a.bridge===b.id&&b.bridge===a.id&&a.answered&&b.answered,
        'Original two-leg bridge did not survive monitoring');return true;
}
async function stopSupervisor(requireLive=false) {
    if(!current?.supervisor_id){assert(!requireLive,'Missing supervisor stop identity');return;}
    const c=channel(current.supervisor_id);if(!c){assert(!requireLive,'Supervisor vanished before stop API proof');return;}
    assert(monitorMatches(c),'Cannot stop unowned supervisor');
    await request('POST',route('channels',c.id),{action:'stop_monitoring',request_id:current.request_id},adminToken,202);
    await until(()=>!channel(c.id),8);
    return 202;
}
function ringingEvidence(text,callId) {
    assert(CALL.test(callId),'Invalid ringing evidence call ID');
    const rows=text.split('\n').map(line=>line.split('\t')).map(row=>
        row.length===7&&/^\d{4}-\d{2}-\d{2}$/.test(row[0])&&/^\d{2}:\d{2}:\d{2}\.\d+$/.test(row[1])&&Number(row[2])>0?
            [row[0]+'T'+row[1]+'Z',...row.slice(3)]:row).filter(row=>row.length===5&&row[1]==='R'&&
        row[2]===callId&&/^CSeq:[1-9][0-9]* INVITE$/.test(row[3]));
    const ringing=rows.findIndex(row=>/^SIP\/2\.0 180(?: |$)/.test(row[4]));
    const answered=rows.findIndex(row=>/^SIP\/2\.0 200(?: |$)/.test(row[4]));
    assert(ringing>=0&&answered>ringing,'Exact caller must receive SIP180 before SIP200');
    assert(rows[ringing][3]===rows[answered][3],'Ringing and answer transaction mismatch');
    return {caller_received_180_before_200:true,ringing_at:rows[ringing][0],answered_at:rows[answered][0]};
}
function terminate(child) {if(child&&child.exitCode===null&&!child.killed)child.kill('SIGINT');}
async function waitForAgentEnd(id,observe=channel,wait=until) {
    // SIP BYE completion on the peer can follow caller CHANNEL_DESTROY.
    // Observe only the exact saved leg; never terminate another call to pass.
    if(id)await wait(()=>!observe(id),8).catch(()=>{
        throw Error('Fixture agent leg remains; refusing broad cleanup');
    });
}
async function clearStage() {
    if(current?.supervisor_id)await stopSupervisor();
    if(current?.caller_id) {
        const c=channel(current.caller_id);
        if(c) {
            assert(ownedChannel(c,endpoints(state)[0]),'Refusing cleanup of unowned original leg');
            const result=command(FSCLI,['-x',`uuid_kill ${c.id} NORMAL_CLEARING`],6000);assert(result.startsWith('+OK'),'Fixture hangup failed');
            await until(()=>!channel(c.id),8);
        }
    }
    await waitForAgentEnd(current?.agent_id);
    for(const child of children)terminate(child);
    await sleep(600);
    for(const child of children)if(child.exitCode===null)child.kill('SIGKILL');
    if(fixture){delete fixture.current;saveFixture();}current=null;
}
async function stage(mode) {
    await verifyBorrowed();const es=endpoints(state);
    es.forEach(e=>assert(contacts(e).length===0,'Fixture SIP identity is already in use; wait for other acceptance runs'));
    for(const e of es)registration(e,600);
    const input={};
    es.forEach((e,i)=>{input[e.role]=writePrivate(`${mode}-${e.role}.csv`,e.role==='customer'?
        `SEQUENTIAL\n${e.username};[authentication username=${e.username} password=${e.password}];${state.ACCEPTANCE_REALM};1002;120000;0;${path.join(runDir,'tone-440.ulaw')}\n`:
        `SEQUENTIAL\n${path.join(runDir,'tone-'+[440,660,880][i]+'.ulaw')}\n`);});
    const capture=path.join(runDir,mode+'.pcap');
    const tcpdump=cp.spawn('tcpdump',['-i',distributed?distributed.iface:'lo','-Z','root','-n','-U','-s','512','-w',capture,'udp','and','host',audio.IP,'and','portrange','49000-49005'],{stdio:'ignore'});
    children.add(tcpdump);tcpdump.once('exit',()=>children.delete(tcpdump));
    const agent=spawnPhone(es[1],'monitor-agent.xml',input.agent), supervisor=spawnPhone(es[2],'monitor-supervisor.xml',input.supervisor);
    await sleep(500);assert(agent.exitCode===null&&supervisor.exitCode===null&&tcpdump.exitCode===null,'Fixture listener failed');
    const caller=spawnPhone(es[0],'monitor-customer.xml',input.customer);
    current={mode,caller_id:`1-${caller.pid}@${audio.IP}`};fixture.current=current;saveFixture();
    let lastObservation;
    const target=await until(()=>{
        const c=channel(current.caller_id);lastObservation={caller:c};if(!c?.bridge||!c.answered)return false;
        assert(ownedChannel(c,es[0]),'Caller scope mismatch');const a=channel(c.bridge);
        lastObservation.agent=a;
        return ownedChannel(a,es[1])&&a.answered?a:false;
    }).catch(error=>{writePrivate(mode+'-channel-observation.json',JSON.stringify(lastObservation,null,2)+'\n');throw error;});
    current.agent_id=target.id;saveFixture();
    const body={action:mode,device_id:es[2].device,timeout:10};
    await request('POST',route('channels',target.id),body,masterToken,403);
    await request('POST',route('channels',target.id),body,userToken,403);
    await request('POST',route('channels',hex()),body,adminToken,404);
    await request('POST',route('channels',target.id),{...body,route:'forbidden'},adminToken,400);
    originalAlive();
    const accepted=(await request('POST',route('channels',target.id),body,adminToken,202)).data;
    assert(accepted.status==='accepted'&&accepted.action===mode&&accepted.target_call_id===target.id&&
        ID.test(accepted.request_id)&&ID.test(accepted.supervisor_call_id),'Invalid monitor correlation response');
    current.supervisor_id=accepted.supervisor_call_id;current.request_id=accepted.request_id;saveFixture();
    await until(()=>{const c=channel(current.supervisor_id);return c&&monitorMatches(c)&&c.answered;});
    await request('POST',route('channels',target.id),{action:'stop_monitoring',request_id:current.request_id},adminToken,403);
    if(mediaFenceEnabled)await mediaContext().begin(mode);
    if(partitionEnabled) {
        originalAlive();assert(monitorMatches(channel(current.supervisor_id)));
        assert.equal(JSON.parse(command(FSCLI,['-x','show channels as json'])).row_count,3,
            'Controller fault requires exactly the three owned synthetic legs');
        controllerFault=require('./test-fixtures/distributed-lab/controller-partition.cjs').prepare();
        await controllerFault.start();
        log(mode+' controller16 broker partition verified; controller21 remains available');
    }
    await sleep(12500);originalAlive();
    let partitionProof;
    if(controllerFault) {
        assert(monitorMatches(channel(current.supervisor_id)),'Supervisor lost during broker partition');
        partitionProof=await controllerFault.restore();
        writePrivate(mode+'-partition.json',JSON.stringify(partitionProof,null,2)+'\n');controllerFault=null;
    }
    let mediaProof;
    if(mediaFenceEnabled)mediaProof=await mediaContext().release();
    const stopped=await stopSupervisor(true);originalAlive();await sleep(2500);originalAlive();
    terminate(tcpdump);await until(()=>tcpdump.exitCode!==null,5);fs.chmodSync(capture,384);
    const buffer=fs.readFileSync(capture), ps=audio.packets(buffer);
    const digit=ps.find(p=>p.source===audio.IP&&p.sp===49004&&p.pt===96&&p.payload[0]===3);
    assert(digit,'No explicit keypad escalation packet observed');
    if(partitionEnabled) {
        assert(partitionProof?.disconnected_registry_verified&&partitionProof.registered_broker_recovered&&partitionProof.same_controller_vms);
        assert(digit.time+2>=partitionProof.started&&digit.time+5<=partitionProof.restored,
            'Post-keypad audio evidence must be entirely inside the verified broker partition');
    }
    if(mediaProof)assert(digit.time+2>=mediaProof.closed_at&&digit.time+5<=mediaProof.released_at,
        'Post-keypad audio evidence must be entirely inside the verified media fence');
    const proof=audio.inspect(buffer,mode,[{start:digit.time-3,end:digit.time-1},{start:digit.time+2,end:digit.time+5}]);
    if(partitionProof)proof.controller_broker_partition=partitionProof;
    if(mediaProof)proof.media_admission_fence=mediaProof;
    proof.authorization_negatives=['cross_account403','non_admin403','stale404','extra_route400','stop_original403'];
    proof.call_ids={account_id:state.ACCEPTANCE_ACCOUNT_ID,...current};
    proof.supervisor_stop_http_status=stopped;
    proof.sip_ringing=ringingEvidence(fs.readFileSync(input.customer.replace(/\.csv$/,'-sip.tsv'),'utf8'),current.caller_id);
    proof.original_bridge_survived_monitor_stop=true;
    writePrivate(mode+'-evidence.json',JSON.stringify(proof,null,2)+'\n');
    await clearStage();
    for(const e of es)registration(e,0);
    for(const file of Object.values(input))fs.unlinkSync(file);
    log(mode+' PASS: tone routing before/after keypad3, authorization, supervisor-only stop');
}
async function cleanup() {
    if(cleaning)return;cleaning=true;let complete=true;
    if(controllerFault) {
        try {await controllerFault.restore();controllerFault=null;}
        catch {complete=false;log('Controller broker restoration incomplete; independent watchdog retained');}
    }
    try {await clearStage();}catch(error){complete=false;log('Scoped call cleanup incomplete: '+error.message+'; protected recovery state retained');}
    if(fixture?.media_fence){
        try{await mediaContext().release(true);}
        catch(_){complete=false;log('Owned media fence recovery incomplete; durable generation and fixture state retained');}
    }
    if(fixture?.queue_paused?.length) {
        try {await queueContext().restorePauses();}
        catch {complete=false;log('Synthetic agent pause restoration incomplete; bounded expiry and owned recovery state retained');}
    }
    for(const child of children)terminate(child);
    if(state&&runDir)for(const e of endpoints(state))if(registered.has(e.role)) {
        try {await verifyBorrowed();registration(e,0);}catch(_){complete=false;log('Exact registration cleanup incomplete; expires within600s');}
    }
    if(fixture&&masterToken&&complete)for(const role of ['admin','user']) {
        const u=fixture.users[role];
        try {
            if(!u.id&&!await recoverUser(role))continue;
            const d=(await request('GET',route('users',u.id),undefined,masterToken)).data;
            assert(ownedUser(d,role),'Cleanup marker mismatch');
            await request('DELETE',route('users',u.id),undefined,masterToken);delete u.id;saveFixture();
        } catch(error){
            if(error.http_status===404){delete u.id;saveFixture();}
            else {complete=false;log('Owned web-user cleanup incomplete; protected state retained');}
        }
    }
    if(runDir)for(const name of fs.readdirSync(runDir))if(name.endsWith('.csv'))fs.unlinkSync(path.join(runDir,name));
    if(complete&&fixture){fs.unlinkSync(FILE);log('Owned temporary web users and exact registrations removed; evidence retained privately');}
    return complete;
}
function queueContext() {
    assert(distributed,'Queue partition only allowed in admitted distributed lab');
    return require('./test-fixtures/distributed-lab/queue-partition.cjs').context({
        state,fixture,distributed,audio,runDir,adminToken,masterToken,children,
        request,route,command,endpoints,writePrivate,registration,contacts,spawnPhone,
        channel,ownedChannel,originalAlive,clearStage,saveFixture,until,sleep,log,terminate,
        setCurrent(value){current=value;fixture.current=value;saveFixture();},
        getCurrent(){return current;},
        setFault(value){controllerFault=value;}
    });
}
function mediaContext(){
    assert(distributed,'Media fence acceptance requires the private distributed lab');
    return require('./test-fixtures/distributed-lab/media-fence.cjs').context({
        fixture,distributed,command,writePrivate,saveFixture,originalAlive,until,log
    });
}
function prepare() {
    state=baseState(privateRead(BASE));
    if(mainDev)assert.equal(state.ACCEPTANCE_SIP_PROXY_HOST,mainDev.proxy,'Main dev SIP proxy mismatch');
    const local=JSON.parse(command('ip',['-j','-4','address','show'])).flatMap(x=>x.addr_info||[]).map(x=>x.local);
    assert(distributed?(state.ACCEPTANCE_SIP_PROXY_HOST==='172.30.253.17'&&local.includes(audio.IP)):
        local.includes(state.ACCEPTANCE_SIP_PROXY_HOST),'SIP proxy/fixture interface outside admitted profile');
    const version=cp.spawnSync('sipp',['-v'],{encoding:'utf8',timeout:5000});
    assert(!version.error&&(version.stdout+version.stderr).includes('SIPp v3.7.7-TLS-PCAP-SHA256'),'Pinned SIPp feature version required');
    command('tcpdump',['--version']);assert(fs.existsSync(FSCLI),'Local FS diagnostic client missing');
    for(const scenario of ['monitor-customer.xml','monitor-agent.xml','monitor-supervisor.xml']) {
        const text=fs.readFileSync(path.join(SCENARIOS,scenario),'utf8');
        assert(!text.includes('rtp_echo')&&!text.includes('system '),'Non-synthetic scenario action');
    }
    log('Prepared: isolated tenant only; three synthetic endpoints; no API writes, SIP traffic, or service changes');
}
async function main(args) {
    if(args[0]==='--main-dev') {
        args=args.slice(1);
        assert(args.length===1&&['--prepare-only','--live','--cleanup'].includes(args[0]),'Invalid main dev monitor mode');
        mainDev=require('./test-fixtures/main-dev-monitor-profile.cjs').prepare();
        MASTER=mainDev.master;
    }
    if(args[0]==='--distributed') {
        args=args.slice(1);
        if(args[0]==='--broker-partition') {partitionEnabled=true;args=args.slice(1);}
        if(args[0]==='--queue-partition') {queuePartitionEnabled=true;args=args.slice(1);}
        if(args[0]==='--queue-calls') {queueCallsEnabled=true;args=args.slice(1);}
        if(args[0]==='--media-fence') {mediaFenceEnabled=true;args=args.slice(1);}
        assert([partitionEnabled,queuePartitionEnabled,queueCallsEnabled,mediaFenceEnabled].filter(Boolean).length<=1,'Select one call profile');
        assert(args.length===1&&['--prepare-only','--live','--cleanup'].includes(args[0]),'Invalid distributed monitor mode');
        distributed=require('./test-fixtures/distributed-lab/monitor-profile.cjs').prepare();
        API=distributed.api;BASE=distributed.base;AUTH=distributed.auth;FILE=distributed.file;MASTER=distributed.master;
        audio=audio.distributed();
    }
    assert(args.length===1&&['--prepare-only','--live','--cleanup'].includes(args[0]),'Use --prepare-only, --live, or --cleanup');
    assert(process.getuid()===0,'Root required for protected fixture and local RTP evidence');prepare();
    if(args[0]==='--prepare-only')return;
    // Serializes this harness; other acceptance runs must also be idle. Every
    // stage refuses pre-existing contacts rather than stealing registrations.
    const lockPath='/etc/kazoo/monitor-acceptance.lock';
    if(fs.existsSync(lockPath)) {
        const st=fs.lstatSync(lockPath);assert(st.isFile()&&!st.isSymbolicLink()&&st.uid===0,'Unsafe fixture lock');
    }
    // Holding stdin open keeps the lock alive; parent exit closes it promptly.
    const lock=cp.spawn('flock',['-n',lockPath,process.execPath,'-e','process.stdin.resume();'],{stdio:['pipe','ignore','ignore']});
    await sleep(100);assert(lock.exitCode===null,'Monitor acceptance is already running');
    try {
        runDir=fs.mkdtempSync('/var/log/kazoo-monitor-acceptance-');fs.chmodSync(runDir,448);process.umask(63);
        await authenticateMaster();await verifyBorrowed();
        if(fs.existsSync(FILE))fixture=validFixture(JSON.parse(privateRead(FILE)),state);
        else {
            assert(args[0]==='--live','No saved fixture exists');
            const deployment=hex();fixture={schema_version:1,owner:OWNER,deployment_id:deployment,account_id:state.ACCEPTANCE_ACCOUNT_ID,
                realm:state.ACCEPTANCE_REALM,device_ids:endpoints(state).map(e=>e.device),users:Object.fromEntries(['admin','user'].map(role=>
                    [role,{username:`monitor-${role}-${deployment.slice(0,12)}`,password:hex()}]))};saveFixture();
        }
        current=fixture.current||null;
        if(args[0]==='--cleanup') {
            if(current?.supervisor_id||fixture.queue_paused?.length) {
                assert(fixture.users.admin.id&&ownedUser((await request('GET',route('users',fixture.users.admin.id),undefined,masterToken)).data,'admin'),
                    'Cannot authorize saved supervisor cleanup');
                adminToken=await login(fixture.users.admin.username,fixture.users.admin.password,fixture.realm,fixture.account_id);
            }
            // Recovery deletes only exact saved registrations, never creates users.
            endpoints(state).forEach(e=>{if(contacts(e).includes(`sip:${e.username}@${audio.IP}:${e.port}`))registered.add(e.role);});
            assert(await cleanup(),'Cleanup did not complete');return;
        }
        assert(!current,'Previous unfinished monitor run requires --cleanup first');
        process.once('SIGTERM',()=>{cleanup().finally(()=>process.exit(143));});
        process.once('SIGINT',()=>{cleanup().finally(()=>process.exit(130));});
        try {
            await ensureUsers();
            const channels=(await request('GET',route('channels'),undefined,adminToken)).data;
            assert(channels&&Object.keys(channels).length===0,'Acceptance tenant has active calls; wait for them to finish');
            for(const f of audio.FREQUENCIES)writePrivate('tone-'+f+'.ulaw',audio.tone([f]));
            if(queuePartitionEnabled||queueCallsEnabled)await queueContext().run({partition:queuePartitionEnabled});
            else for(const mode of ['eavesdrop','whisper','barge','join'])await stage(mode);
        }
        catch(error){log('Stage failed: '+error.message);throw error;}
        finally {assert(await cleanup(),'Scoped fixture cleanup incomplete');}
        log((queuePartitionEnabled?'Queued applications-partition recovery passed.':queueCallsEnabled?'Two queued calls passed.':'All four modes passed.')+' Private synthetic evidence: '+runDir);
    } finally {lock.stdin.end();terminate(lock);}
}
module.exports={baseState,endpoints,validFixture,ownedChannel,ownedUser,ringingEvidence,phoneCallLimit,waitForAgentEnd,MASTER,OWNER};
if(require.main===module)main(process.argv.slice(2)).catch(e=>{console.error('[monitor-acceptance] FAIL: '+e.message);process.exitCode=1;});
