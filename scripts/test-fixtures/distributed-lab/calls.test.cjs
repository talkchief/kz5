'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {operation}=require('./calls.cjs'),ROOT=path.resolve(__dirname,'../../..');
function fixture() {
    const roles=['couchdb','rabbitmq','haproxy','kazoo-apps','freeswitch','ecallmgr','kamailio'];
    const state={owner:'distributed-install-v1',roles:Object.fromEntries(roles.map((role,i)=>[role,
        {id:role,ip:'172.30.253.'+(11+i),phase:'installed-service-verified'}]))};
    const events=[];
    return {state,events,h:{ROOT,DIR:'/fixture',readState:()=>state,saveState:()=>events.push('save'),ownedNetwork:()=>{},
        json:args=>[{Config:{Labels:{'io.talkchief.kazoo.acceptance':state.owner,'io.talkchief.kazoo.role':args[1]}},
            State:{Running:true,Paused:false},NetworkSettings:{Networks:{'kz5-install-stage':{IPAddress:state.roles[args[1]].ip}}}}],
        podman:args=>{
            if(args.includes('show channels as json'))return '{"row_count":0}';
            if(args.includes('sha256sum'))return crypto.createHash('sha256').update(fs.readFileSync(args.at(-1))).digest('hex')+'  source';
            events.push(args);return '';
        }}};
}
const valid=fixture();operation('start',valid.h);
assert.equal(valid.state.callFixture.phase,'provisioning');
assert(valid.events.some(e=>Array.isArray(e)&&e.includes('systemd-run')&&e.includes('--property=RuntimeMaxSec=900')));
for(const alter of [s=>{s.owner='other';},s=>{s.callFixture={};},s=>{s.roles.ecallmgr.phase='installing';}]) {
    const f=fixture();alter(f.state);assert.throws(()=>operation('start',f.h));assert.equal(f.events.length,0);
}
const src=fs.readFileSync(__dirname+'/provision-calls.sh','utf8');
assert(src.includes('KAZOO_PUBLIC_IP=172.30.253.17'));
assert(!src.includes('\nsave_deployment_config'));
assert(!src.includes('\npreflight_acceptance_runtime'));
console.log('PASS actual call fixture admission and start orchestration with isolated adapters; no services/data changed');
