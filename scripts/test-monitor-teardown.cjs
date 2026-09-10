'use strict';
const assert=require('node:assert/strict');
const {waitForAgentEnd}=require('./test-channel-monitor-live.cjs');
(async()=>{
    const id='exact-synthetic-peer',seen=[];
    let samples=0;
    const wait=async(predicate,seconds)=>{
        assert.equal(seconds,8);
        for(let i=0;i<3;i++){samples++;if(predicate())return true;await Promise.resolve();}
        throw Error('bounded deadline');
    };
    await waitForAgentEnd(undefined,()=>assert.fail('No peer to inspect'),wait);
    assert.equal(samples,0);
    await waitForAgentEnd(id,observed=>{seen.push(observed);return seen.length<3?{id}:null;},wait);
    assert.deepEqual(seen,[id,id,id]);assert.equal(samples,3);
    samples=0;
    await assert.rejects(waitForAgentEnd(id,observed=>{assert.equal(observed,id);return {id};},wait),/refusing broad cleanup/);
    assert.equal(samples,3);
    await assert.rejects(waitForAgentEnd(id,()=>{throw Error('native observation unavailable');},wait),/refusing broad cleanup/);
    console.log('PASS bounded exact-agent teardown: delayed BYE, persistent leg, unavailable observation and absent peer');
})().catch(()=>{console.error('FAIL monitor teardown guard');process.exitCode=1;});
