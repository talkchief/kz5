'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {request,matches,owned}=require('./test-acdc-cold-maintenance.cjs');
const generation='f'.repeat(32),account='1'.repeat(32),q='2'.repeat(32);
function snapshot(){return {node:'kazoo_apps@fixture',epoch:'123-456',agents:[1,2,3].map((i)=>({
    node:'kazoo_apps@fixture',account_id:account,agent_id:String(i+2).repeat(32),state:i===3?'ready':'paused',
    pause_until_unix_ms:i===1?Date.now()+600000:i===2?'infinity':0,queues:i===3?[]:[q]})),
    document_revisions:[1,2,3].map(i=>({account_id:account,agent_id:String(i+2).repeat(32),revision:'1-'+'a'.repeat(32)}))};}
test('cold restore request uses target epoch but retained absolute state and document revisions',()=>{
    const s=snapshot(),r=request(s,generation);
    assert.equal(r.expected_epoch,s.epoch);assert.equal(r.generation,generation);assert.equal(r.agents.length,3);
    assert.equal(r.agents[0].pause_until_unix_ms,s.agents[0].pause_until_unix_ms);
    assert.equal(r.agents[1].pause_until_unix_ms,'infinity');assert.deepEqual(r.agents[2].queues,[]);
    assert(r.agents.every(a=>a.document_revision==='1-'+'a'.repeat(32)));
});
test('restored comparison is order-independent but rejects cohort, revision and state loss',()=>{
    const saved=snapshot(),actual=structuredClone(saved);actual.agents.reverse();actual.document_revisions.reverse();matches(actual,saved);
    for(const mutate of [x=>x.agents.pop(),x=>x.agents[0].pause_until_unix_ms+=1000,x=>x.agents[1].state='ready',
        x=>x.agents[2].queues=[q],x=>x.document_revisions[0].revision='2-'+'a'.repeat(32)]){
        const bad=structuredClone(saved);mutate(bad);assert.throws(()=>matches(bad,saved));
    }
});
test('expired finite pauses restore ready without fabricating a longer pause',()=>{
    const s=snapshot();s.agents[0].pause_until_unix_ms=1;
    const a=structuredClone(s);a.agents[0].state='ready';a.agents[0].pause_until_unix_ms=0;matches(a,s);
    a.agents[0].state='paused';assert.throws(()=>matches(a,s));
});
test('uncollected runtime and foreign ownership refuse before container inspection',()=>{
    assert.throws(()=>owned({owner:'foreign'},{},'kazoo-apps','172.30.253.14','installed'));
    assert.throws(()=>owned({owner:'distributed-install-v1'},{phase:'installed',source:'new',installedSource:'old'},'kazoo-apps','172.30.253.14','installed'));
});
