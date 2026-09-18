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
// The default hold spans the agent's reconciliation interval. RabbitMQ only
// drops the unreachable node's connection, and REDELIVERS its unacknowledged
// member call to the healthy node, after a longer silence; run8 showed that
// path ringing an agent for a dead caller and logging it out. An explicit longer
// hold exercises it. It must end before the independent 3-minute route watchdog.
function partitionHoldMs(value=process.env.KZ5_QUEUE_PARTITION_HOLD_MS) {
    if(value===undefined||value==='')return 35000;
    assert(/^[1-9][0-9]{4,5}$/.test(value),'Partition hold must be whole milliseconds');
    const hold=Number(value);
    assert(hold>=35000&&hold<=150000,'Partition hold must be 35000..150000 ms, below the 3-minute restore watchdog');
    return hold;
}
function partitionTarget(value=process.env.KZ5_QUEUE_PARTITION_TARGET) {
    if(value===undefined||value==='')return 'owner';
    assert(['owner','other'].includes(value),'Partition target must be owner or other');
    return value;
}
// Fault matrix (readiness plan C3): one role is lost while a queued call is
// bridged. "owner" is the applications node holding the caller's delivery.
const SERVICE_FAULTS={
    'apps-kill':{guest:'owner',unit:'kazoo-apps.service',action:'kill'},
    'broker-restart':{guest:'kz5-stage-rabbitmq',unit:'rabbitmq-server.service',action:'restart'},
    'ecallmgr-kill':{guest:'kz5-stage-ecallmgr',unit:'kazoo-ecallmgr.service',action:'kill'},
    'couchdb-outage':{guest:'kz5-stage-couchdb',unit:'couchdb.service',action:'outage'},
    // The media server takes the call down with it: the bridge must NOT survive, and
    // both media controllers must see the node again before the next call is judged.
    'freeswitch-restart':{guest:'kz5-stage-freeswitch',unit:'kazoo-freeswitch.service',action:'restart',callLost:true,
        mediaControllers:['kz5-stage-ecallmgr','kz5-stage-ecallmgr-peer']}
};
function serviceFault(value=process.env.KZ5_QUEUE_FAULT) {
    assert(Object.hasOwn(SERVICE_FAULTS,String(value)),'KZ5_QUEUE_FAULT must be one of '+Object.keys(SERVICE_FAULTS).join(', '));
    return {name:value,...SERVICE_FAULTS[value]};
}
function strictInventory(v,s) {
    assert.equal(v.schema_version,2);assert.equal(v.all_agent_workers_observed,true);
    assert.equal(v.complete_cluster_drain_proven,false);
    assert.equal(v.agents.length,3);
    assert.deepEqual(v.agents.map(a=>a.agent_id).sort(),[1,2,3].map(i=>s[`ACCEPTANCE_AGENT_${i}_USER_ID`]).sort());
    for(const a of v.agents) {
        assert.equal(a.account_id,s.ACCEPTANCE_ACCOUNT_ID);assert.equal(a.state,'ready');
        assert.deepEqual(a.queues,[s.ACCEPTANCE_QUEUE_ID]);
    }
    return v;
}
function context(h) {
    identity(h.state);
    let fault,nodes,pinned,lastNative;
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
        lastNative=values;
        if(!values.every(v=>v.state===wanted))return false;
        if(correlate)for(const v of values) {
            assert.equal(v.member_call_id,h.getCurrent().caller_id,'Uncorrelated queue member');
            assert.equal(v.agent_call_id,h.getCurrent().agent_id,'Uncorrelated queue agent leg');
        }
        return values;
    }
    function deliveryOwner() {
        const owners=nodes.filter(n=>{
            h.command('podman',['cp',path.join(__dirname,'queue-owner-rpc.escript'),n.id+':/var/lib/kazoo-stage/queue-owner-rpc.escript']);
            h.command('podman',['exec',n.id,'chmod','0600','/var/lib/kazoo-stage/queue-owner-rpc.escript']);
            const v=JSON.parse(h.command('podman',['exec',n.id,'escript','/var/lib/kazoo-stage/queue-owner-rpc.escript',
                s.ACCEPTANCE_QUEUE_ID,h.getCurrent().caller_id],12000));
            assert(Number.isSafeInteger(v.workers)&&v.workers>0&&typeof v.owns==='boolean','Invalid queue owner observation');
            return v.owns;
        });
        assert(owners.length<=1,'A member delivery cannot be owned by both applications nodes');
        return owners[0]?.ip;
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
        pinned=nodes.map(n=>{const v=probe(n,agent);assert.equal(v.state,'ready');
            assert.equal(v.listener_consuming,true);assert(v.agent_queues.includes(q.id));return v.fsm;});
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
        h.log(label+': exact SIP queue bridge verified; observing native replica states');
        const answered=await h.until(()=>both('answered',true),15).catch(error=>{
            h.writePrivate(label+'-fsm-observation.json',JSON.stringify(lastNative,null,2)+'\n');throw error;
        });
        const start=Date.now()/1000+0.5;await h.sleep(3500);alive();
        const end=Date.now()/1000;
        h.terminate(tcpdump);await h.until(()=>tcpdump.exitCode!==null,5);fs.chmodSync(capture,384);
        const proof={answered,audio:inspectAudio(h.audio,fs.readFileSync(capture),start,end)};
        if(onAnswered)proof.partition=await onAnswered();
        else await h.clearStage();
        for(const file of Object.values(input))fs.unlinkSync(file);
        h.writePrivate(label+'-evidence.json',JSON.stringify(proof,null,2)+'\n');return proof;
    }
    const quietly=fn=>()=>{try{return fn();}catch(_){return false;}};
    async function injectServiceFault() {
        const f=serviceFault(),owner=deliveryOwner();
        const guest=f.guest==='owner'?nodes.find(n=>n.ip===(owner||nodes[0].ip)).id:f.guest;
        const unit=(...a)=>h.command('podman',['exec',guest,'systemctl',...a],60000);
        const others=[2,3].map(i=>s[`ACCEPTANCE_AGENT_${i}_USER_ID`]);
        h.log('Service fault '+f.name+': '+f.action+' '+f.unit+' in '+(f.guest==='owner'?'the delivery owner '+(owner||nodes[0].ip):guest)+' during the bridged queue call');
        const injected=Date.now()/1000;
        if(f.action==='kill')unit('kill','-s','KILL',f.unit);
        else if(f.action==='restart')unit('restart',f.unit);
        else {unit('stop',f.unit);await h.sleep(30000);unit('start',f.unit);}
        await h.sleep(3000);
        // Evidence, not an assumption: whether the media bridge outlived the role.
        let survived=true;try{alive();}catch(_){survived=false;}
        if(f.callLost)assert.equal(survived,false,'A call cannot outlive its media server; the observation is wrong');
        await h.clearStage();
        if(f.mediaControllers)await h.until(quietly(()=>f.mediaControllers.every(c=>
            /freeswitch@/.test(h.command('podman',['exec',c,'bash','-lc','sup -n ecallmgr ecallmgr_maintenance list_fs_nodes'],30000)))),240);
        // A killed node starts new agent processes, so the pinned pids no longer apply.
        pinned=undefined;
        const quiet=quietly;
        const recovered=await h.until(quiet(()=>both('ready')),300);
        // No unrelated agent state change: the two paused agents are still paused on both nodes.
        let seen;
        const observe=()=>{seen=others.map(u=>nodes.map(n=>{try{const v=probe(n,u);return {node:n.ip,agent:u,state:v.state};}
            catch(e){return {node:n.ip,agent:u,error:String(e.message).slice(0,120)};}}));return seen.flat().every(v=>v.state==='paused');};
        const paused=await h.until(observe,120).catch(()=>{
            h.writePrivate('queue-fault-unrelated-agents.json',JSON.stringify(seen,null,2)+'\n');
            throw Error('An unrelated paused agent did not come back paused after '+f.name+': '+JSON.stringify(seen.flat().map(v=>v.node+'='+(v.state||v.error))));
        });
        h.log('Both agent replicas ready again without re-login after '+f.name+'; unrelated agents still paused');
        return {fault:f.name,unit:f.unit,action:f.action,owner:owner||null,injected_at:injected,
            bridge_survived:survived,recovered_after_s:Math.round(Date.now()/1000-injected),recovered,others_still_paused:paused};
    }
    async function run({partition=true,serviceFaultMode=false}={}) {
        assert(typeof partition==='boolean'&&typeof serviceFaultMode==='boolean'&&!(partition&&serviceFaultMode));
        if(serviceFaultMode)serviceFault();
        fault=partitions.prepare('kazoo-apps');nodes=fault.nodes;
        const es=h.endpoints(s).slice(0,2);
        es.forEach(e=>assert.equal(h.contacts(e).length,0,'Synthetic phone already registered'));
        await verifyAndPause();
        for(const e of es)h.registration(e,600);
        h.log('Queue2000: both native agent replicas pinned; alternate synthetic agents temporarily paused');
        const first=await call(partition?'queue-before-partition':serviceFaultMode?'queue-before-fault':'queue-first',serviceFaultMode?injectServiceFault:partition?async()=>{
            // Partition the node whose worker holds this caller's unacknowledged
            // delivery: only that strands, and later redelivers, the call.
            const owner=deliveryOwner(),wanted=partitionTarget();
            // owner: strands and later redelivers the call (redelivery admission).
            // other: the cut-off manager misses the non-durable removal broadcast
            // and used to keep a phantom waiting member (member reconciliation).
            const target=!owner?nodes[0].ip:wanted==='owner'?owner:nodes.find(n=>n.ip!==owner).ip;
            if(target!==nodes[0].ip) {
                fault=partitions.prepare('kazoo-apps',target);nodes=fault.nodes;pinned.reverse();
            }
            h.log(owner?'Member delivery owned by '+owner+'; partitioning the '+wanted+' applications node '+target:
                'Member delivery already settled on both nodes; no broker redelivery can occur in this run');
            h.setFault(fault);await fault.start();
            h.log('Applications node '+nodes[0].ip+' broker disconnected; '+nodes[1].ip+' healthy; ending exact synthetic conversation');
            await h.clearStage();
            const samples=[],end=Date.now()+partitionHoldMs();
            while(Date.now()<end) {
                assert(!fault.available(nodes[0])&&fault.available(nodes[1]));
                const v=probe(nodes[0],agent,pinned[0]);assert.equal(v.state,'answered','Unknown disconnected call must remain conservatively busy');
                samples.push({at:Date.now()/1000,state:v.state});await h.sleep(1000);
            }
            const proof=await fault.restore();h.setFault(null);
            const recovered=await h.until(()=>both('ready'),90);
            h.log('Both original FSM replicas recovered ready without re-login or SIP re-registration');
            return {...proof,busy_samples:samples,recovered};
        }:undefined);
        if(!partition&&!serviceFaultMode)await h.until(()=>both('ready'),30);
        // Existing contacts must remain exact; do not REGISTER between calls. A
        // lost registrar (eCallMgr) or its datastore may legitimately need one.
        if(serviceFaultMode)for(const e of es){if(h.contacts(e).length===0)h.registration(e,600);}
        for(const e of es)assert.deepEqual(h.contacts(e),[`sip:${e.username}@${h.audio.IP}:${e.port}`]);
        const second=await call(partition?'queue-after-partition':serviceFaultMode?'queue-after-fault':'queue-second');
        const ready=await h.until(()=>both('ready'),30);
        await restorePauses();
        // Public "ready" alone cannot establish listener drain. This installed
        // read-only collector also verifies pending work and actual bindings.
        const drained=await h.until(()=>{
            try{return nodes.map(n=>strictInventory(JSON.parse(h.command('podman',
                ['exec',n.id,'escript','/usr/local/libexec/kazoo5-maintenance-snapshot','--snapshot',n.ip],20000)),s));}
            catch(_){return false;}
        // A leg whose end was lost with the fault is retired by the listener's
        // reconciliation: 30 s minimum age, the next 60 s tick, then the probe.
        },serviceFaultMode?200:45);
        h.writePrivate('queue-post-call-agent-inventories.json',JSON.stringify(drained,null,2)+'\n');
        h.writePrivate(partition?'queue-partition-evidence.json':serviceFaultMode?'queue-fault-evidence.json':'queue-calls-evidence.json',JSON.stringify({first,second,ready,
            strict_all_replica_agent_drain:true,partition_exercised:partition,service_fault:serviceFaultMode?serviceFault().name:null,
            same_fsm_replicas:!serviceFaultMode,no_agent_relogin:true,no_sip_reregistration:!serviceFaultMode},null,2)+'\n');
        h.log(serviceFaultMode?'PASS queued call through '+serviceFault().name+': automatic agent recovery, unrelated agents unchanged, second real call with directional audio, strict inventory on both nodes':partition?'PASS two actual queued calls, directional audio, missed-hangup partition and same-FSM recovery':
            'PASS two actual queued calls and directional audio without agent re-login, SIP re-registration or broker interruption');
    }
    return {run,restorePauses};
}
module.exports={context,identity,snapshot,inspectAudio,ownedAgent,strictInventory,partitionHoldMs,partitionTarget,serviceFault,SERVICE_FAULTS};
