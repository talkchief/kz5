#!/usr/bin/env node
'use strict';
// Private fixture files and deterministic subprocess doubles only. This tests
// real pack validation/cache routing, not SoX DSP correctness or live media.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const assert=require('node:assert/strict'),Module=require('node:module'),{createRequire}=Module;
const file=path.join(__dirname,'acdc-cardinal-pack.cjs'),source=fs.readFileSync(file,'utf8');
const nativeRequire=createRequire(file),root=fs.mkdtempSync(path.join(os.tmpdir(),'cardinal-replay-cache.'));
fs.chmodSync(root,0o700);
const capDeclaration='const REPLAY_CACHE_BYTES = 32 * 1024 * 1024, REPLAY_CACHE_ENTRIES = 1024;';
assert(source.includes(capDeclaration));
let checks=0;
function wave(value,rate=24000){const n=rate/4,b=Buffer.alloc(44+n*2);b.write('RIFF');b.writeUInt32LE(b.length-8,4);
 b.write('WAVEfmt ',8);b.writeUInt32LE(16,16);b.writeUInt16LE(1,20);b.writeUInt16LE(1,22);
 b.writeUInt32LE(rate,24);b.writeUInt32LE(rate*2,28);b.writeUInt16LE(2,32);b.writeUInt16LE(16,34);
 b.write('data',36);b.writeUInt32LE(n*2,40);for(let i=44;i<b.length;i+=2)b.writeInt16LE(value,i);return b;}
function load(small=false){const state={calls:0,versions:0,fail:false};
 const child={spawnSync(command,args,o){assert.equal(command,'/usr/bin/sox');assert(o.timeout>0&&o.timeout<=5000);
   assert.equal(o.shell,false);assert.deepEqual(Object.keys(o.env).sort(),['LC_ALL','PATH','TZ']);
   if(args[0]==='--version'){state.versions++;return {status:0,signal:null,stdout:Buffer.from('sox: SoX v14.4.2\n'),stderr:Buffer.alloc(0)};}
   state.calls++;if(state.fail)return {status:1,signal:null,stdout:Buffer.alloc(0),stderr:Buffer.alloc(0)};
   const out=Buffer.alloc(4000);for(let i=0;i<out.length;i+=2)out.writeInt16LE(o.input.readInt16LE(44),i);
   return {status:0,signal:null,stdout:out,stderr:Buffer.alloc(0)};
 }};
 const isolated=new Module(file);isolated.filename=file;
 isolated.require=name=>name==='node:child_process'?child:nativeRequire(name);
 isolated._compile(small?source.replace(capDeclaration,'const REPLAY_CACHE_BYTES = 8000, REPLAY_CACHE_ENTRIES = 1024;'):source,file);
 return {pack:isolated.exports,state,parse:JSON.parse};
}
function test(name,fn){fn();checks++;}
try {
 const {pack:p,state,parse}=load(),a=wave(1000),b=wave(1100),c=wave(1200);
 test('standalone calls keep fresh scopes',()=>{p.resampleMaster(a);p.resampleMaster(a);assert.equal(state.calls,2);});
 test('same call caches across newly created validation scopes',()=>{const n=state.calls,v=state.versions;
   p.withResamplingReplayCache(()=>{assert(p.resampleMaster(a).equals(p.resampleMaster(a)));assert.equal(state.calls,n+1);});
   assert.equal(state.versions,v+2,'existing per-scope version checks remain');});
 test('new wrapper never inherits prior successful cache',()=>{const n=state.calls;p.withResamplingReplayCache(()=>p.resampleMaster(a));assert.equal(state.calls,n+1);});
 test('caller cannot poison cached PCM via fresh or hit result',()=>{p.withResamplingReplayCache(()=>{
   p.resampleMaster(a).fill(0);assert.equal(p.resampleMaster(a).readInt16LE(0),1000);
   p.resampleMaster(a).fill(0);assert.equal(p.resampleMaster(a).readInt16LE(0),1000);});});
 test('actual master mutation changes key',()=>{const n=state.calls;p.withResamplingReplayCache(()=>{
   p.resampleMaster(a);assert.equal(p.resampleMaster(b).readInt16LE(0),1100);});assert.equal(state.calls,n+2);});
 test('bad wave is not accepted on warm cache',()=>{p.withResamplingReplayCache(()=>{
   p.resampleMaster(a);const changed=Buffer.from(a);changed.writeUInt32LE(8000,24);assert.throws(()=>p.resampleMaster(changed),/REQUIRE_PCM16/);});});
 test('exception clears cache',()=>{const n=state.calls;assert.throws(()=>p.withResamplingReplayCache(()=>{p.resampleMaster(a);throw Error('fixture');}),/fixture/);
   p.withResamplingReplayCache(()=>p.resampleMaster(a));assert.equal(state.calls,n+2);});
 test('failed replay is not cached',()=>{p.withResamplingReplayCache(()=>{state.fail=true;assert.throws(()=>p.resampleMaster(c),/SOX_REPLAY_FAILED/);
   state.fail=false;assert.equal(p.resampleMaster(c).readInt16LE(0),1200);});});
 test('nested and asynchronous scopes are rejected and cleaned',()=>{
   p.withResamplingReplayCache(()=>assert.throws(()=>p.withResamplingReplayCache(()=>null),/INVALID_REPLAY_CACHE_SCOPE/));
   assert.throws(()=>p.withResamplingReplayCache(()=>Promise.resolve()),/ASYNC_REPLAY_CACHE_SCOPE/);
   assert.throws(()=>p.withResamplingReplayCache({}),/INVALID_REPLAY_CACHE_SCOPE/);
   p.withResamplingReplayCache(()=>p.resampleMaster(a));});
 test('existing expired subprocess deadline still rejects',()=>{
   p.withResamplingReplayCache(()=>{p.resampleMaster(a);assert.throws(()=>p.resampleMaster(b,{deadline:-1,checked:true,cache:new Map()}),/RESAMPLING_DEADLINE_EXCEEDED/);});});
 test('small private cap evicts LRU deterministically',()=>{const q=load(true);q.pack.withResamplingReplayCache(()=>{
   q.pack.resampleMaster(a);q.pack.resampleMaster(b);q.pack.resampleMaster(a);q.pack.resampleMaster(c);
   assert.equal(q.state.calls,3);q.pack.resampleMaster(a);assert.equal(q.state.calls,3);
   q.pack.resampleMaster(b);assert.equal(q.state.calls,4,'B was least recently used');});});
 function entry(locale,value){const e=p.createManifest().prompts.find(e=>e.locale===locale);const master=wave(value),phone=wave(value,8000);
   const body=p.requestBody(e),m=p.inspectWave(master,24000),t=p.inspectWave(phone,8000);
   const attempt={number:1,status:'QA_PASSED',reserved_at:'2026-09-07T00:00:00.000Z',synthesis_instruction:body.contents[0].parts[0].text,
     instruction_sha256:require('node:crypto').createHash('sha256').update(body.contents[0].parts[0].text).digest('hex'),
     request_body_sha256:require('node:crypto').createHash('sha256').update(JSON.stringify(body)).digest('hex'),failure_code:null,
     provider_finish_reason:'STOP',raw_pcm_sha256:m.pcm_sha256,
     master:{file:p.fileName(e,1,'master'),...m},telephony:{file:p.fileName(e,1,'telephony'),...t}};
   e.generation_status='QA_PASSED';e.attempts=[parse(JSON.stringify(attempt))];
   for(const [v,bytes] of [['master',master],['telephony',phone]]){const target=path.join(root,attempt[v].file);
     fs.mkdirSync(path.dirname(target),{recursive:true,mode:0o700});fs.writeFileSync(target,bytes,{mode:0o600});}
   return e;
 }
 const en=entry('en-us',1000),es=entry('es-es',1000);
 test('same master across locales reuses DSP but revalidates identity/transcript',()=>{
   const n=state.calls;p.withResamplingReplayCache(()=>{p.verifyEntry(root,en);p.verifyEntry(root,es);assert.equal(state.calls,n+1);
     const wrong=parse(JSON.stringify(es));wrong.transcript=en.transcript+' altered';assert.throws(()=>p.verifyEntry(root,wrong),/CATALOG_TRANSCRIPT_OR_CONTEXT_CHANGED/);});});
 test('changed saved telephony still fails exact replay with warm cache and matching fresh metrics',()=>{
   p.withResamplingReplayCache(()=>{p.verifyEntry(root,en);const bad=wave(1200,8000),attempt=en.attempts[0],target=path.join(root,attempt.telephony.file),old=fs.statSync(target);
     fs.writeFileSync(target,bad);fs.utimesSync(target,old.atime,old.mtime);
     attempt.telephony=parse(JSON.stringify({file:attempt.telephony.file,...p.inspectWave(bad,8000)}));
     assert.throws(()=>p.verifyEntry(root,en),/TELEPHONY_NOT_EXACT_MASTER_RESAMPLE/);});});
 test('changed source file and unsafe link still rejected on warm cache',()=>{
   p.withResamplingReplayCache(()=>{p.verifyEntry(root,es);const target=path.join(root,es.attempts[0].master.file),old=fs.statSync(target);
     fs.writeFileSync(target,b);fs.utimesSync(target,old.atime,old.mtime);assert.throws(()=>p.verifyEntry(root,es),/AUDIO_HASH_OR_METRICS_CHANGED/);
     fs.unlinkSync(target);fs.symlinkSync(path.join(root,en.attempts[0].master.file),target);assert.throws(()=>p.verifyEntry(root,es));});});
 const adapter=fs.readFileSync(path.join(__dirname,'install-acdc-cardinal-pack.cjs'),'utf8');
 test('adapter wraps only synchronous five-locale construction',()=>{
   const section=adapter.slice(adapter.indexOf('function releasePlans('),adapter.indexOf('\nfunction options('));
   assert(section.includes('return pack.withResamplingReplayCache(() => LOCALES.map('));assert(!section.includes('await'));
   assert(section.includes("locale === 'en-us' ? {} : locale === 'es-es' ? resolution : trials"),'alias scope unchanged');});
 console.log('PASS '+checks+' isolated replay-cache/validation cases (SoX subprocess double; DSP correctness remains existing-suite gate)');
} finally {fs.rmSync(root,{recursive:true,force:true});}
