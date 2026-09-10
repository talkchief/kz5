'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const m=require('./kazoo-maintenance-broker.cjs');
const node='rabbit@fixture',vhost='/';
const c=()=>({disk_nodes:[node],ram_nodes:[],running_nodes:[node],partitions:{},alarms:[]});
const q=()=>({name:'work',pid:'<queue>',state:'running',type:'classic',messages:0,messages_ready:0,messages_unacknowledged:0,consumers:1});
const conn=()=>({pid:'<connection>',vhost,state:'running',user:'fixture',peer_host:[127,0,0,1],channels:1});
const ch=()=>({pid:'<channel>',connection:'<connection>',vhost,consumer_count:1,messages_unacknowledged:0,messages_uncommitted:0,acks_uncommitted:0,messages_unconfirmed:0});
function fixture(change=()=>{}){
    const calls=[],seen={};
    return {calls,call:async(tool,n,args)=>{
        assert.equal(n,node);calls.push({tool,node:n,args});
        const command=args[0]==='-p'?args[2]:args[0];seen[command]=(seen[command]||0)+1;
        let result;
        switch(command){
            case 'cluster_status':result=c();break;
            case 'status':result={rabbitmq_version:'3.13.7',pid:123,is_under_maintenance:false,alarms:[]};break;
            case 'eval':assert.deepEqual(args,['eval','erlang:system_info(creation).']);result='456';break;
            case 'list_vhosts':result=[{name:vhost}];break;
            case 'list_queues':assert.deepEqual(args.slice(0,3),['-p',vhost,'list_queues']);result=[q()];break;
            case 'list_connections':result=[conn()];break;
            case 'list_channels':result=[ch()];break;
            default:throw Error('Unexpected command');
        }
        return change(result,command,seen[command])??result;
    }};
}
test('complete native observation checks both epochs, membership, queues and connections',async()=>{
    const f=fixture(),r=await m.collect(f.call,node,vhost);assert.equal(r.broker_work_empty,true);
    assert.equal(r.producer_fence_proven,false);assert.equal(r.complete_cluster_drain_proven,false);
    for(const command of ['cluster_status','status','eval','list_queues','list_connections'])assert.equal(f.calls.filter(x=>x.args.includes(command)).length,2);
    assert(!f.calls.some(x=>x.args.some(a=>['--online','--local','--offline'].includes(a))));m.requireQueues(r,['work']);
});
test('queued and delivered work are reported busy, never silently drained',async()=>{
    for(const state of ['ready','unacked']){
        const f=fixture((r,k)=>{
            if(k==='list_queues'){r[0].messages=1;r[0][state==='ready'?'messages_ready':'messages_unacknowledged']=1;}
            if(k==='list_channels'&&state==='unacked')r[0].messages_unacknowledged=1;
        });const r=await m.collect(f.call,node,vhost);assert.equal(r.broker_work_empty,false);assert.throws(()=>m.requireQueues(r,['work']));
    }
});
test('transaction, uncommitted ack and publisher-confirm work block emptiness',async()=>{
    for(const key of ['messages_uncommitted','acks_uncommitted','messages_unconfirmed']){
        const f=fixture((r,k)=>{if(k==='list_channels')r[0][key]=1;});assert.equal((await m.collect(f.call,node,vhost)).broker_work_empty,false);
    }
});
test('expected runtime queues cannot be absent, duplicated or consumerless',()=>{
    assert.throws(()=>m.requireQueues({queues:[q()]},['missing']));
    assert.throws(()=>m.requireQueues({queues:[q()]},['work','work']));
    assert.throws(()=>m.requireQueues({queues:[{...q(),consumers:0}]},['work']));
});
test('offline members, partitions, alarms and duplicate membership refuse',()=>{
    for(const patch of [{running_nodes:[]},{partitions:{[node]:['peer']}},{alarms:[{}]},
        {disk_nodes:[node,node]},{ram_nodes:[node]},{running_nodes:[node,node]}])assert.throws(()=>m.cluster({...c(),...patch}));
});
for(const [name,change] of [
    ['missing vhost',(r,k)=>k==='list_vhosts'?[]:undefined],
    ['epoch changed',(r,k,n)=>k==='eval'&&n===2?'457':undefined],
    ['PID changed',(r,k,n)=>{if(k==='status'&&n===2)r.pid++;}],
    ['unreviewed version',(r,k)=>{if(k==='status')r.rabbitmq_version='4.0.0';}],
    ['maintenance mode',(r,k)=>{if(k==='status')r.is_under_maintenance=true;}],
    ['changed queue',(r,k,n)=>{if(k==='list_queues'&&n===2)r[0].pid='<replacement>';}],
    ['changed connection',(r,k,n)=>{if(k==='list_connections'&&n===2)r[0].user='other';}],
    ['missing channel',(r,k)=>k==='list_channels'?[]:undefined],
    ['foreign channel connection',(r,k)=>{if(k==='list_channels')r[0].connection='<unknown>';}],
    ['unobserved consumer',(r,k)=>{if(k==='list_channels')r[0].consumer_count=0;}],
    ['unobserved delivered message',(r,k)=>{if(k==='list_channels')r[0].messages_unacknowledged=1;}],
    ['down queue',(r,k)=>{if(k==='list_queues')r[0].state='down';}],
    ['missing queue counts',(r,k)=>{if(k==='list_queues')delete r[0].messages_ready;}],
    ['duplicate queue',(r,k)=>{if(k==='list_queues')r.push({...r[0]});}],
    ['missing counters',(r,k)=>{if(k==='list_channels')delete r[0].messages_unconfirmed;}],
    ['flow-controlled connection',(r,k)=>{if(k==='list_connections')r[0].state='flow';}]
])test('refuses '+name,async()=>{await assert.rejects(m.collect(fixture(change).call,node,vhost));});
test('native command failure refuses instead of accepting a partial snapshot',async()=>{
    const f=fixture();await assert.rejects(m.collect(async(t,n,a)=>{if(a.includes('list_channels'))throw Error('timeout');return f.call(t,n,a);},node,vhost));
});
