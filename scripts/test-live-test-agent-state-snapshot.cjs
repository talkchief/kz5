#!/usr/bin/env node
'use strict';
const assert=require('node:assert/strict');
const {projectMembership}=require('./snapshot-live-test-agent-state.cjs');
const {PROTECTED_USER}=require('./provision-live-test-agents.cjs');
const id='a'.repeat(32), protectedAgent={index:'protected'}, user={id:PROTECTED_USER};
const project=(agent,response,doc)=>projectMembership(agent,{status:'success',...response},doc);
assert.deepEqual(projectMembership(protectedAgent,{status:'success'},user),{membership_kind:'absent',queue_memberships:null});
assert.deepEqual(project({index:1},{data:[]}),{membership_kind:'present',queue_memberships:[]});
assert.deepEqual(project(protectedAgent,{data:[id]},{...user,queues:[id]}),{membership_kind:'present',queue_memberships:[id]});
for(const response of [{}, {data:null}, {data:'unknown'}, {data:{}}, {data:[id,id]}, {data:['unknown']}]) {
    assert.throws(()=>project({index:1},response));
}
for(const [response,doc] of [[{}, {...user,queues:[]}], [{data:null},user], [{data:[]},user],
    [{data:[id]},{...user,queues:[]}], [{}, {id:'b'.repeat(32)}], [{data:[id,id]},{...user,queues:[id,id]}]]) {
    assert.throws(()=>project(protectedAgent,response,doc));
}
assert.throws(()=>project(protectedAgent,{status:'error'},user));
assert.throws(()=>project(protectedAgent,{status:'unknown'},user));
console.log('PASS17 pure snapshot membership checks: explicit protected absence, owned arrays, failed/unknown/duplicate/contradictory responses fail closed; no API/files/services');
