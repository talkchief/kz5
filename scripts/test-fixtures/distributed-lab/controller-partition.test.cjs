'use strict';
const assert=require('node:assert/strict');
const {admit,Partition}=require('./controller-partition.cjs');
const a='a'.repeat(64),b='b'.repeat(64),owner='distributed-install-v1';
const s={owner,roles:{ecallmgr:{id:a,phase:'installed-service-verified'}},ecallmgrPeer:{id:b,phase:'installed'}};
const inspect=id=>({Config:{Labels:{'io.talkchief.kazoo.acceptance':owner,'io.talkchief.kazoo.role':id===a?'ecallmgr':'ecallmgr-peer'}},
    State:{Running:true,Paused:false},NetworkSettings:{Networks:{'kz5-install-stage':{IPAddress:id===a?'172.30.253.16':'172.30.253.21'}}}});
assert.equal(admit(s,inspect).length,2);
assert.throws(()=>admit({...s,owner:'production'},inspect));
for(const bad of ['ip','label','paused','stopped'])assert.throws(()=>admit(s,id=>{
    const c=inspect(id);if(bad==='ip')c.NetworkSettings.Networks['kz5-install-stage'].IPAddress='10.1.0.44';
    if(bad==='label')c.Config.Labels['io.talkchief.kazoo.role']='other';
    if(bad==='paused')c.State.Paused=true;if(bad==='stopped')c.State.Running=false;return c;
}));
async function test() {
    let blocked=false,killed=false,armed=false,consumerDelay=0;const calls=[];
    const run=args=>{
        calls.push(args);const c=args.join(' '),target=args[2]===a;
        if(args[0]==='systemd-run'){armed=true;return '';}
        if(args[0]==='systemctl'){if(args[1]==='is-active')return 'active';armed=false;return '';}
        if(c.includes('systemctl is-active'))return 'active';
        if(c.includes('MainPID'))return target?'100':'200';
        if(c.includes('is_available'))return target&&blocked&&killed?'false':'true';
        if(c.includes('is_consuming')) {
            if(target&&!blocked&&consumerDelay>0){consumerDelay--;return 'false';}
            return target&&blocked&&killed?'false':'true';
        }
        if(c.includes('ip -j route'))return blocked?'[{"type":"blackhole","dst":"172.30.253.12"}]':'[]';
        if(c.includes('route add')){assert(armed);blocked=true;return '';}
        if(c.includes('route del')){blocked=false;consumerDelay=3;return '';}
        if(c.includes('ss -K')){assert(blocked);killed=true;return '';}
        if(c.includes('ss -Hnt'))return '';
        throw Error('Unexpected fixture command');
    };
    const p=new Partition(admit(s,inspect),run);await p.start();assert(blocked&&armed);
    const proof=await p.restore();assert(!blocked&&!armed);assert(proof.same_controller_vms&&proof.registered_broker_recovered&&proof.query_consumers_recovered);
    assert.equal(proof.query_consumer_at_broker_recovery,false);assert.equal(consumerDelay,0);
    assert(calls.filter(a=>a.includes('add')||a.includes('del')).every(a=>a.includes('172.30.253.12/32')));
    await p.restore();
    const bad=new Partition(admit(s,inspect),()=>'{badrpc,timeout}');assert.throws(()=>bad.available(bad.nodes[0]));
    assert.equal(bad.queryReady(bad.nodes[0]),false);
    const rpcFailure=new Partition(admit(s,inspect),()=>{throw Error('RPC unavailable');});
    assert.equal(rpcFailure.queryReady(rpcFailure.nodes[0]),false);
    const occupied=new Partition(admit(s,inspect),args=>args.includes('route')?'[{"type":"blackhole"}]':run(args));
    await assert.rejects(()=>occupied.start());assert(!occupied.routeAdded);
    console.log('PASS controller partition ownership, exact route, watchdog ordering, restoration, same VM and invalid-status guards; no live commands');
}
test().catch(e=>{console.error(e.message);process.exitCode=1;});
