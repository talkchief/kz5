#!/usr/bin/env node
'use strict';
// Native read-only RabbitMQ observation; never a producer fence or an upgrade
// executor. Management statistics are intentionally not used for drain counts.
const cp=require('node:child_process'),assert=require('node:assert/strict'),os=require('node:os');
const text=s=>assert(typeof s==='string'&&s.length>0&&Buffer.byteLength(s)<=512&&!/[\x00-\x1f\x7f]/.test(s));
const number=n=>assert(Number.isSafeInteger(n)&&n>=0);
const nodename=n=>{text(n);assert(/^[a-zA-Z0-9_-]+@[a-zA-Z0-9_.-]+$/.test(n));};
function cluster(c){
    for(const key of ['disk_nodes','ram_nodes','running_nodes']){assert(Array.isArray(c[key]));c[key].forEach(nodename);assert.equal(new Set(c[key]).size,c[key].length);}
    const nodes=[...c.disk_nodes,...c.ram_nodes].sort();assert(nodes.length>0&&nodes.length<=32);assert.equal(new Set(nodes).size,nodes.length);
    assert.deepEqual([...c.running_nodes].sort(),nodes,'Missing running broker');
    assert(c.partitions&&typeof c.partitions==='object'&&!Array.isArray(c.partitions)&&Object.keys(c.partitions).length===0,'Broker partition');
    assert(Array.isArray(c.alarms)&&c.alarms.length===0,'Broker alarm');return nodes;
}
function unique(rows,key){
    assert(Array.isArray(rows)&&rows.length<=100000);const seen=new Set();
    for(const row of rows){assert(row&&typeof row==='object'&&!Array.isArray(row));text(row[key]);assert(!seen.has(row[key]),'Duplicate broker identity');seen.add(row[key]);}
    return [...rows].sort((a,b)=>a[key]<b[key]?-1:a[key]>b[key]?1:0);
}
function queues(rows){
    return unique(rows,'name').map(q=>{
        text(q.pid);assert(Buffer.byteLength(q.name)<=255);assert.equal(q.state,'running','Unavailable queue');assert(['classic','quorum'].includes(q.type),'Unsupported queue type');
        for(const k of ['messages','messages_ready','messages_unacknowledged','consumers'])number(q[k]);
        assert.equal(q.messages,q.messages_ready+q.messages_unacknowledged,'Inconsistent queue counts');
        return q;
    });
}
function connections(rows,vhost){
    return unique(rows,'pid').filter(c=>{text(c.vhost);return c.vhost===vhost;}).map(c=>{
        text(c.user);assert.equal(c.state,'running','Connection is not stable');number(c.channels);
        assert(Array.isArray(c.peer_host)&&[4,8].includes(c.peer_host.length));
        assert(c.peer_host.every(n=>Number.isSafeInteger(n)&&n>=0&&n<=(c.peer_host.length===4?255:65535)));
        return c;
    });
}
function channels(rows,cs,vhost){
    const byConnection=new Map(cs.map(c=>[c.pid,0]));
    const selected=unique(rows,'pid').filter(c=>{text(c.vhost);return c.vhost===vhost;});
    for(const c of selected){
        text(c.connection);assert(byConnection.has(c.connection),'Channel connection absent from inventory');
        byConnection.set(c.connection,byConnection.get(c.connection)+1);
        for(const k of ['consumer_count','messages_unacknowledged','messages_uncommitted','acks_uncommitted','messages_unconfirmed'])number(c[k]);
    }
    for(const c of cs)assert.equal(byConnection.get(c.pid),c.channels,'Incomplete or changing channel inventory');
    return selected;
}
function totals(qs,hs){
    const sum=(rows,key)=>rows.reduce((n,r)=>n+r[key],0);
    assert.equal(sum(qs,'consumers'),sum(hs,'consumer_count'),'Consumer inventory mismatch');
    const out={messages_ready:sum(qs,'messages_ready'),messages_unacknowledged:sum(qs,'messages_unacknowledged'),
        channel_unacknowledged:sum(hs,'messages_unacknowledged'),messages_uncommitted:sum(hs,'messages_uncommitted'),
        acks_uncommitted:sum(hs,'acks_uncommitted'),messages_unconfirmed:sum(hs,'messages_unconfirmed')};
    Object.values(out).forEach(number);assert.equal(out.messages_unacknowledged,out.channel_unacknowledged,'Unacknowledged inventory mismatch');
    return out;
}
function requireQueues(snapshot,names){
    assert(Array.isArray(names)&&names.length<=100000);names.forEach(text);assert.equal(new Set(names).size,names.length);
    const observed=new Map(snapshot.queues.map(q=>[q.name,q]));
    for(const name of names){assert(observed.has(name),'Expected runtime queue absent from broker');const q=observed.get(name);assert.equal(q.messages,0,'Expected runtime queue still has work');assert(q.consumers>0,'Expected runtime queue has no consumer');}
}
async function collect(call,node,vhost){
    nodename(node);text(vhost);const started=Date.now();
    const nodes=cluster(await call('rabbitmqctl',node,['cluster_status']));assert(nodes.includes(node));
    const epoch=async n=>{
        const s=await call('rabbitmq-diagnostics',n,['status']);
        assert.equal(s.rabbitmq_version,'3.13.7','Unreviewed native CLI version');number(s.pid);assert(s.pid>0);
        assert(Array.isArray(s.alarms)&&s.alarms.length===0);assert.equal(s.is_under_maintenance,false);
        const creation=await call('rabbitmqctl',n,['eval','erlang:system_info(creation).']);
        assert(typeof creation==='string'&&/^[0-9]+$/.test(creation));return {node:n,pid:s.pid,creation};
    };
    const epochs=[];for(const n of nodes)epochs.push(await epoch(n));
    const vs=await call('rabbitmqctl',node,['list_vhosts','name']);assert(Array.isArray(vs)&&vs.filter(v=>v.name===vhost).length===1,'Vhost not confirmed');
    const queueArgs=['-p',vhost,'list_queues','name','pid','state','type','messages','messages_ready','messages_unacknowledged','consumers'];
    const connectionArgs=['list_connections','pid','vhost','state','user','peer_host','channels'];
    const channelArgs=['list_channels','pid','connection','vhost','consumer_count','messages_unacknowledged','messages_uncommitted','acks_uncommitted','messages_unconfirmed'];
    const qs=queues(await call('rabbitmqctl',node,queueArgs));
    const cs=connections(await call('rabbitmqctl',node,connectionArgs),vhost);
    const hs=channels(await call('rabbitmqctl',node,channelArgs),cs,vhost);
    assert.deepEqual(connections(await call('rabbitmqctl',node,connectionArgs),vhost),cs,'Connections changed');
    assert.deepEqual(queues(await call('rabbitmqctl',node,queueArgs)),qs,'Queues changed');
    for(const saved of epochs)assert.deepEqual(await epoch(saved.node),saved,'Broker epoch changed');
    assert.deepEqual(cluster(await call('rabbitmqctl',node,['cluster_status'])),nodes,'Broker membership changed');
    const counts=totals(qs,hs);
    return {schema_version:1,started_at_unix_ms:started,captured_at_unix_ms:Date.now(),vhost,epochs,
        queues:qs,connections:cs,channels:hs,counts,broker_work_empty:Object.values(counts).every(n=>n===0),
        producer_fence_proven:false,complete_cluster_drain_proven:false};
}
function native(){
    const deadline=Date.now()+120000;
    return async(tool,node,args)=>{
        const remaining=deadline-Date.now();assert(remaining>0,'Native broker observation deadline exceeded');
        assert(['rabbitmqctl','rabbitmq-diagnostics'].includes(tool));nodename(node);
        const raw=cp.execFileSync('/usr/sbin/runuser',['-u','rabbitmq','--','/usr/lib/rabbitmq/bin/'+tool,'-q','-n',node,
            '--timeout','12',...args,...(args[0]==='eval'?[]:['--formatter=json'])],
        {cwd:'/var/lib/rabbitmq',encoding:'utf8',timeout:Math.min(15000,remaining),maxBuffer:16*1024*1024,stdio:['ignore','pipe','pipe']}).trim();
        return args[0]==='eval'?raw:JSON.parse(raw);
    };
}
module.exports={cluster,queues,connections,channels,totals,requireQueues,collect,native};
if(require.main===module)(async()=>{
    assert.equal(process.getuid(),0);const [mode,node,vhost,...extra]=process.argv.slice(2);
    assert.equal(mode,'--snapshot');assert.equal(extra.length,0);nodename(node);
    assert.equal(node.split('@')[1],os.hostname(),'Run on the named broker host');
    console.log(JSON.stringify(await collect(native(),node,vhost)));
})().catch(()=>{console.error('MAINTENANCE_BROKER_INVENTORY_REFUSED');process.exitCode=1;});
