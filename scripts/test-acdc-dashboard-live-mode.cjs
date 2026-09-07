#!/usr/bin/env node
'use strict';
// Actual CLI control flow with external boundaries replaced. No real credentials,
// calls, authentication, network, files or processes are changed by this fixture.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const {createRequire}=require('node:module');
const {EventEmitter}=require('node:events');
const file=path.join(__dirname,'test-acdc-strategies-live.cjs'),source=fs.readFileSync(file,'utf8'),load=createRequire(file);
function fixture(options={}){
    const events=[],mod={exports:{}};
    const forbidden=()=>{throw Error('unexpected mutation or process');};
    const readFs={...fs,existsSync:()=>!!options.ledger,writeFileSync:forbidden,openSync:forbidden,
        mkdirSync:forbidden,mkdtempSync:forbidden,renameSync:forbidden,unlinkSync:forbidden,chmodSync:forbidden};
    const localRequire=name=>name==='node:fs'?readFs:name==='node:child_process'?{
        spawn:()=>options.lockChild||forbidden(),execFileSync:forbidden,spawnSync:forbidden}:load(name);
    localRequire.main=null;
    const context={require:localRequire,module:mod,__dirname,console:{log(){}},process:{getuid:()=>0,exit:code=>events.push('exit:'+code)},
        Buffer,setTimeout,clearTimeout,setInterval,clearInterval,probeEvents:events,options};
    vm.runInNewContext(source+`
      prepare=()=>{probeEvents.push('prepare');state={};for(let i=0;i<4;i++){
        const p=i?'ACCEPTANCE_AGENT_'+i:'ACCEPTANCE_CALLER';
        state[p+'_USER_ID']=String(i+1).padStart(32,'0');
      }return [];};
      authenticate=async()=>{probeEvents.push('authenticate');};
      verifyBorrowed=async()=>{probeEvents.push('identities');};
      noTenantCalls=async()=>{probeEvents.push('no_calls');};
      contacts=e=>{probeEvents.push('contacts');return options.contact?['foreign']:[];};
      status=async e=>{probeEvents.push('status');return options.status||'logged_out';};
      request=async(method,p)=>{probeEvents.push(method);if(method!=='GET')throw Error('unexpected mutation');return {data:options.membership||[]};};
      performCleanup=async()=>{probeEvents.push('cleanup');await options.cleanupBarrier;return true;};
      module.exports.testMain=main;
      module.exports.testCleanup=cleanup;module.exports.testShutdown=shutdown;module.exports.testLock=acquireLock;
      module.exports.testForward=forward;module.exports.testFinishShutdown=finishShutdown;
      module.exports.testPendingWorkflow=async()=>{await options.forwardBarrier;probeEvents.push('response_bookkept');forward();probeEvents.push('forbidden_new_write');};
    `,context,{filename:file,timeout:1000});
    return {events,run:args=>mod.exports.testMain(args),api:mod.exports,process:context.process};
}
async function main(){
    let f=fixture();await f.run(['--check-live']);
    assert.deepEqual(f.events,['prepare','authenticate','identities','no_calls',
        'contacts','contacts','contacts','contacts','status','GET','status','GET','status','GET']);
    f=fixture();await f.run(['--prepare-only']);assert.deepEqual(f.events,['prepare']);
    for(const options of [{contact:true},{status:'paused'},{status:'unknown'},{membership:['bad']},{ledger:true}]){
        f=fixture(options);await assert.rejects(f.run(['--check-live']));
        assert(!f.events.some(e=>['POST','PATCH','PUT','DELETE'].includes(e)));
    }
    for(const args of [[],['--unknown'],['--dashboard-live','--live']]){
        f=fixture();await assert.rejects(f.run(args));assert.deepEqual(f.events,[]);
    }
    // Dashboard mode must reach the same shared lock boundary as ordinary live
    // acceptance, not silently become preparation or bypass locking.
    for(const mode of ['--dashboard-live','--live']){
        f=fixture();await assert.rejects(f.run([mode]),/unexpected mutation or process/);
        assert.deepEqual(f.events,['prepare']);
    }
    let release;f=fixture({cleanupBarrier:new Promise(resolve=>{release=resolve;})});
    const s1=f.api.testShutdown(143),s2=f.api.testShutdown(130);assert.equal(s1,s2);
    assert.deepEqual(f.events,[],'Signal must not race cleanup against forward work');
    assert.throws(f.api.testForward,/forward work stopped/);
    const c1=f.api.testCleanup(),c2=f.api.testCleanup();assert.equal(c1,c2);
    assert.deepEqual(f.events,['cleanup']);assert.doesNotThrow(f.api.testForward);
    release();await Promise.all([c1,c2]);assert.throws(f.api.testForward,/forward work stopped/);
    assert.equal(f.process.exitCode,undefined);f.api.testFinishShutdown();await Promise.all([s1,s2]);
    assert.equal(f.process.exitCode,143);assert.deepEqual(f.events,['cleanup']);
    let response;f=fixture({forwardBarrier:new Promise(resolve=>{response=resolve;})});
    const workflow=f.api.testPendingWorkflow(),shutdown=f.api.testShutdown(143);
    response();await assert.rejects(workflow,/forward work stopped/);
    assert.deepEqual(f.events,['response_bookkept']);await f.api.testCleanup();f.api.testFinishShutdown();await shutdown;
    assert.deepEqual(f.events,['response_bookkept','cleanup']);
    function child(){const c=new EventEmitter();c.stdout=new EventEmitter();c.exitCode=null;
        c.stdin={end(){c.ended=true;}};c.kill=()=>{c.killed=true;};return c;}
    const held=child();f=fixture({lockChild:held});let admitted=false;
    const lock=f.api.testLock('/synthetic/lock').then(value=>{admitted=true;return value;});
    await new Promise(resolve=>setImmediate(resolve));assert.equal(admitted,false,'Alive child is not lock acquisition');
    held.stdout.emit('data',Buffer.from('LOC'));await new Promise(resolve=>setImmediate(resolve));assert.equal(admitted,false);
    held.stdout.emit('data',Buffer.from('KED\n'));assert.equal(await lock,held);
    for(const kind of ['exit','garbage']){
        const rejected=child();f=fixture({lockChild:rejected});const p=f.api.testLock('/synthetic/lock');
        if(kind==='exit'){rejected.exitCode=1;rejected.emit('exit',1);}else rejected.stdout.emit('data',Buffer.from('invalid\n'));
        await assert.rejects(p,/not acquired/);assert.equal(rejected.ended,true);
    }
    console.log('PASS dashboard CLI boundaries: read-only preflight, drift refusal, acquired-lock ACK, shared cleanup and repeated-signal completion; no live calls');
}
main().catch(error=>{console.error('FAIL dashboard CLI boundary fixture',error);process.exitCode=1;});
