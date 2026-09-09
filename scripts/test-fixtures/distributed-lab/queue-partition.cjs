'use strict';
// Deliberately restricted fault acceptance, never part of normal installation.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),assert=require('node:assert/strict');
const partitions=require('./controller-partition.cjs');
const ACCOUNT='45e827067baf078029d0ca16a489fa8a',REALM='acceptance-724fa76c8821.invalid';
const ID=/^[a-f0-9]{32}$/;
function identity(s) {
    assert.equal(s.ACCEPTANCE_ACCOUNT_ID,ACCOUNT);assert.equal(s.ACCEPTANCE_REALM,REALM);
    assert.equal(s.ACCEPTANCE_QUEUE_EXTENSION,'2000');
    assert.equal(s.ACCEPTANCE_AGENT_3_EXTENSION,'1004');
    for(const key of ['ACCEPTANCE_QUEUE_ID','ACCEPTANCE_QUEUE_CALLFLOW_ID','ACCEPTANCE_AGENT_1_USER_ID',
        'ACCEPTANCE_AGENT_2_USER_ID','ACCEPTANCE_AGENT_3_USER_ID'])assert(ID.test(s[key]),'Invalid synthetic queue identity');
    assert.equal(new Set([1,2,3].map(i=>s[`ACCEPTANCE_AGENT_${i}_USER_ID`])).size,3);
}
function snapshot(value,pinned) {
    assert(value.present===true&&/^<0\.[0-9]+\.[0-9]+>$/.test(value.fsm),'Missing native agent FSM');
    if(pinned)assert.equal(value.fsm,pinned,'Agent FSM replaced');
    assert(typeof value.state==='string');return value;
}
function ownedAgent(c,e,s,callerId,ip) {
    // ACDC intentionally exports the original caller's Authorizing-ID (see
    // maybe_connect_to_agent/7). Do not relax the direct-call ownership gate.
    return Boolean(c&&c.active&&c.account===s.ACCEPTANCE_ACCOUNT_ID&&
        c.device===s.ACCEPTANCE_CALLER_DEVICE_ID&&c.observed_authorizing_type==='user'&&
        c.observed_sip_to_user===e.device&&c.observed_acdc_agent_id===e.user&&
        c.observed_acdc_member_id===callerId&&c.bridge===callerId&&
        c.ip===ip&&c.port===e.port&&[ip,s.ACCEPTANCE_SIP_PROXY_HOST].includes(c.peer)&&
        (!c.auth_ip||c.auth_ip===ip));
}
function inspectAudio(audio,buffer,start,end) {
    assert(end-start>=2);const packets=audio.packets(buffer).filter(p=>p.time>=start&&p.time<end),proof={start,end};
    for(const [role,port,own,other] of [['customer',49000,440,660],['agent',49002,660,440]]) {
        const tx=audio.amplitudes(packets.filter(p=>p.source===audio.IP&&p.sp===port));
        const rx=audio.amplitudes(packets.filter(p=>p.dest===audio.IP&&p.dp===port));
        assert(tx[own]>2000&&rx[other]>500,'Queued call missing actual directional audio');
        proof[role]={transmit:tx,receive:rx};
    }
    return proof;
}
function context(h) {
    identity(h.state);
    let fault,nodes,pinned;
    const s=h.state,agent=s.ACCEPTANCE_AGENT_1_USER_ID;
    function alive() {
        const c=h.getCurrent(),es=h.endpoints(s),a=h.channel(c.caller_id),b=h.channel(c.agent_id);
        assert(h.ownedChannel(a,es[0])&&ownedAgent(b,es[1],s,c.caller_id,h.audio.IP)&&
            a.bridge===b.id&&a.answered&&b.answered,'Exact queued bridge did not survive');
    }
    function probe(n,user,pin) {
        const text=h.command('podman',['exec',n.id,'escript','/var/lib/kazoo-stage/queue-agent-rpc.escript',user,...(pin?[pin]:[])],12000);
        return snapshot(JSON.parse(text),pin);
    }
    function both(wanted,correlate=false) {
        const values=nodes.map((n,i)=>probe(n,agent,pinned?.[i]));
        if(!values.every(v=>v.state===wanted))return false;
        if(correlate)for(const v of values) {
            assert.equal(v.member_call_id,h.getCurrent().caller_id,'Uncorrelated queue member');
            assert.equal(v.agent_call_id,h.getCurrent().agent_id,'Uncorrelated queue agent leg');
        }
        return values;
    }
    async function status(user) {
        const v=(await h.request('GET',h.route('agents',user)+'/status',undefined,h.adminToken)).data;
        return typeof v==='string'?v:v.status;
    }
    async function restorePauses() {
        for(const user of [...(h.fixture.queue_paused||[])]) {
            assert([s.ACCEPTANCE_AGENT_2_USER_ID,s.ACCEPTANCE_AGENT_3_USER_ID].includes(user));
            const v=await status(user);
            assert(['paused','pause','ready','login','resume'].includes(v),'Refusing to override changed agent state');
            if(['paused','pause'].includes(v))await h.request('POST',h.route('agents',user)+'/status',{status:'resume'},h.adminToken);
            await h.until(async()=>['ready','login','resume'].includes(await status(user)),20);
            h.fixture.queue_paused=h.fixture.queue_paused.filter(id=>id!==user);h.saveFixture();
        }
    }
    async function verifyAndPause() {
        const q=(await h.request('GET',h.route('queues',s.ACCEPTANCE_QUEUE_ID),undefined,h.masterToken)).data;
        assert(q.id===s.ACCEPTANCE_QUEUE_ID&&q.name==='Acceptance Queue 2000'&&q.agent_wrapup_time===0,'Queue configuration drift');
        const f=(await h.request('GET',h.route('callflows',s.ACCEPTANCE_QUEUE_CALLFLOW_ID),undefined,h.masterToken)).data;
        assert(f.id===s.ACCEPTANCE_QUEUE_CALLFLOW_ID&&JSON.stringify(f.numbers)==='["2000"]'&&
            f.flow.module==='acdc_member'&&f.flow.data.id===q.id&&Object.keys(f.flow.children||{}).length===0,'Queue route drift');
        const roster=(await h.request('GET',h.route('queues',q.id)+'/roster',undefined,h.masterToken)).data;
        assert.deepEqual([...roster].sort(),[1,2,3].map(i=>s[`ACCEPTANCE_AGENT_${i}_USER_ID`]).sort(),'Unexpected queue roster');
        for(const n of nodes) {
            h.command('podman',['cp',path.join(__dirname,'queue-agent-rpc.escript'),n.id+':/var/lib/kazoo-stage/queue-agent-rpc.escript']);
            h.command('podman',['exec',n.id,'chmod','0600','/var/lib/kazoo-stage/queue-agent-rpc.escript']);
        }
        pinned=nodes.map(n=>{const v=probe(n,agent);assert.equal(v.state,'ready');return v.fsm;});
        assert(!h.fixture.queue_paused?.length,'Previous paused-agent cleanup required');
        h.fixture.queue_paused=[];h.saveFixture();
        for(const i of [2,3]) {
            const user=s[`ACCEPTANCE_AGENT_${i}_USER_ID`];
            // Native identity/state checked on both replicas before any pause.
            for(const n of nodes)assert.equal(probe(n,user).state,'ready');
            h.fixture.queue_paused.push(user);h.saveFixture();
            await h.request('POST',h.route('agents',user)+'/status',{status:'pause',timeout:300},h.adminToken);
            await h.until(()=>nodes.every(n=>probe(n,user).state==='paused'),20);
        }
    }
    async function call(label,onAnswered) {
        const es=h.endpoints(s).slice(0,2),input={};
        input.customer=h.writePrivate(label+'-customer.csv',`SEQUENTIAL\n${es[0].username};[authentication username=${es[0].username} password=${es[0].password}];${s.ACCEPTANCE_REALM};2000;120000;0;${path.join(h.runDir,'tone-440.ulaw')}\n`);
        input.agent=h.writePrivate(label+'-agent.csv',`SEQUENTIAL\n${path.join(h.runDir,'tone-660.ulaw')}\n`);
        const capture=path.join(h.runDir,label+'.pcap');
        const tcpdump=cp.spawn('tcpdump',['-i',h.distributed.iface,'-Z','root','-n','-U','-s','512','-w',capture,
            'udp','and','host',h.audio.IP,'and','portrange','49000-49003'],{stdio:'ignore'});
        h.children.add(tcpdump);tcpdump.once('exit',()=>h.children.delete(tcpdump));
        const phone=h.spawnPhone(es[1],'monitor-agent.xml',input.agent);
        await h.sleep(500);assert(phone.exitCode===null&&tcpdump.exitCode===null);
        const caller=h.spawnPhone(es[0],'monitor-customer.xml',input.customer);
        h.setCurrent({mode:'queue_partition',caller_id:`1-${caller.pid}@${h.audio.IP}`});
        let last;
        const target=await h.until(()=>{
            const c=h.channel(h.getCurrent().caller_id);last={caller:c};if(!c?.bridge||!c.answered)return false;
            assert(h.ownedChannel(c,es[0]),'Queue caller ownership');const a=h.channel(c.bridge);last.agent=a;
            return ownedAgent(a,es[1],s,h.getCurrent().caller_id,h.audio.IP)&&a.answered?a:false;
        },35).catch(error=>{h.writePrivate(label+'-observation.json',JSON.stringify(last));throw error;});
        h.getCurrent().agent_id=target.id;h.saveFixture();alive();
        const answered=await h.until(()=>both('answered',true),15);
        const start=Date.now()/1000+0.5;await h.sleep(3500);alive();
        const end=Date.now()/1000;
        h.terminate(tcpdump);await h.until(()=>tcpdump.exitCode!==null,5);fs.chmodSync(capture,384);
        const proof={answered,audio:inspectAudio(h.audio,fs.readFileSync(capture),start,end)};
        if(onAnswered)proof.partition=await onAnswered();
        else await h.clearStage();
        for(const file of Object.values(input))fs.unlinkSync(file);
        h.writePrivate(label+'-evidence.json',JSON.stringify(proof,null,2)+'\n');return proof;
    }
    async function run() {
        fault=partitions.prepare('kazoo-apps');nodes=fault.nodes;
        const es=h.endpoints(s).slice(0,2);
        es.forEach(e=>assert.equal(h.contacts(e).length,0,'Synthetic phone already registered'));
        await verifyAndPause();
        for(const e of es)h.registration(e,600);
        h.log('Queue2000: both native agent replicas pinned; alternate synthetic agents temporarily paused');
        const first=await call('queue-before-partition',async()=>{
            h.setFault(fault);await fault.start();h.log('Applications14 broker disconnected; peer20 healthy; ending exact synthetic conversation');
            await h.clearStage();
            const samples=[],end=Date.now()+35000;
            while(Date.now()<end) {
                assert(!fault.available(nodes[0])&&fault.available(nodes[1]));
                const v=probe(nodes[0],agent,pinned[0]);assert.equal(v.state,'answered','Unknown disconnected call must remain conservatively busy');
                samples.push({at:Date.now()/1000,state:v.state});await h.sleep(1000);
            }
            const proof=await fault.restore();h.setFault(null);
            const recovered=await h.until(()=>both('ready'),90);
            h.log('Both original FSM replicas recovered ready without re-login or SIP re-registration');
            return {...proof,busy_samples:samples,recovered};
        });
        // Existing contacts must remain exact; do not REGISTER between calls.
        for(const e of es)assert.deepEqual(h.contacts(e),[`sip:${e.username}@${h.audio.IP}:${e.port}`]);
        const second=await call('queue-after-partition');
        const ready=await h.until(()=>both('ready'),30);
        await restorePauses();
        h.writePrivate('queue-partition-evidence.json',JSON.stringify({first,second,ready,
            same_fsm_replicas:true,no_agent_relogin:true,no_sip_reregistration:true},null,2)+'\n');
        h.log('PASS two actual queued calls, directional audio, missed-hangup partition and same-FSM recovery');
    }
    return {run,restorePauses};
}
module.exports={context,identity,snapshot,inspectAudio,ownedAgent};
