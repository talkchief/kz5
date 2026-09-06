#!/usr/bin/env node
'use strict';
// Offline only: provider and protected-key boundaries are prohibited globally,
// then injected with local doubles. Synthetic tones are fixture audio, not TTS.
const assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const crypto=require('node:crypto'),https=require('node:https');
const samples=require('./generate-acdc-gemini-samples.cjs'),fixed=require('./generate-acdc-gemini-fixed-pack.cjs');
const generator=require('./generate-acdc-gemini-supplemental-pack.cjs');
const hash=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const pinned=[__filename,'acdc-gemini-supplemental-catalog.cjs','generate-acdc-gemini-supplemental-pack.cjs',
  'generate-acdc-gemini-fixed-pack.cjs','generate-acdc-gemini-samples.cjs','acdc-language-catalog.cjs',
  'assets/acdc-gemini-fixed-20260905/manifest.json','assets/acdc-gemini-completion-20260905/manifest.json']
  .map(p=>path.isAbsolute(p)?p:path.join(__dirname,p));
const pins=Object.fromEntries(pinned.map(p=>[p,hash(p)]));
const scratch=fs.mkdtempSync(path.join(os.tmpdir(),'kazoo-gemini-supplemental-test.'));fs.chmodSync(scratch,0o700);
const savedRequest=https.request,savedKeyReader=samples.readProtectedKey;
let forbidden=0;https.request=()=>{forbidden++;throw Error('provider transport prohibited');};
samples.readProtectedKey=()=>{forbidden++;throw Error('credential access prohibited');};
const fakeKey='offline-supplemental-fixture-not-a-provider-key';
const code=wanted=>e=>e instanceof samples.SampleError && e.code===wanted;
const groups=[];const report=name=>{groups.push(name);console.log('PASS '+name);};
function pcm(rate,seconds=0.5) {
  const b=Buffer.alloc(Math.round(rate*seconds)*2);
  for(let i=0;i<b.length/2;i++)b.writeInt16LE(Math.round(8000*Math.sin(2*Math.PI*440*i/rate)),i*2);
  return b;
}
function response(seconds=0.5) {return {modelVersion:samples.MODEL,candidates:[{finishReason:'STOP',content:{parts:[
  {inlineData:{mimeType:'audio/L16;codec=pcm;rate=24000',data:pcm(24000,seconds).toString('base64')}}]}}]};}
const dependencies={readProtectedKey:()=>fakeKey,conversionVersion:()=> '14.4.2',output:()=>{},
  requestSpeech:async()=>response(),resample:(_source,destination)=>fs.writeFileSync(destination,samples.makeWave(pcm(8000),8000),{flag:'wx'})};
const opts=name=>({generate:true,concurrency:1,keyFile:'/not-read',output:path.join(scratch,name)});
function ledger(directory){return JSON.parse(fs.readFileSync(path.join(directory,'manifest.json'),'utf8'));}
function writeLedger(directory,m){fs.writeFileSync(path.join(directory,'manifest.json'),JSON.stringify(m)+'\n');}
async function run() {
  const prompts=generator.plan();assert.equal(prompts.length,45);assert.equal(new Set(prompts.map(p=>p.locale+'/'+p.id)).size,45);
  for(const locale of samples.LOCALES) {
    const entries=prompts.filter(p=>p.locale===locale),digits=entries.filter(p=>p.kind==='callback-digit');
    assert.equal(entries.filter(p=>p.kind==='callback-auxiliary').length,3);
    assert.equal(digits.length,['en-us','fr-fr','es-es'].includes(locale)?10:0);
    if(digits.length)assert.deepEqual(digits.map(p=>p.id),Array.from({length:10},(_,i)=>'acdc-number-'+i));
  }
  assert(prompts.filter(p=>p.kind==='callback-digit').every(p=>!/[0-9]/.test(p.transcript)));
  assert.equal(prompts.find(p=>p.locale==='fr-fr' && p.id==='acdc-number-0').transcript,'zéro');
  assert.equal(prompts.find(p=>p.locale==='es-es' && p.id==='acdc-number-1').transcript,'uno');
  assert(prompts.filter(p=>p.locale==='he-il').every(p=>/[א-ת]/u.test(p.transcript)));
  assert(prompts.filter(p=>p.locale==='ar-sa').every(p=>/[\u0600-\u06ff]/u.test(p.transcript)));
  for(const entry of prompts) {
    const body=generator.requestBody(entry);assert(body.contents[0].parts[0].text.endsWith(entry.transcript));
    assert.equal(body.generationConfig.speechConfig.voiceConfig.prebuiltVoiceConfig.voiceName,'Sulafat');
    for(const bad of [{transcript:'unapproved'},{language:'wrong'},{kind:'wrong'},{maximum_duration_seconds:1000}])
      assert.throws(()=>generator.requestBody({...entry,...bad}),code('UNAPPROVED_SUPPLEMENTAL_TEXT'));
  }
  report('exact45 immutable localized entries, spelled30 digits and strict request allowlist');
  assert.throws(()=>generator.options(['--generate','--plan']),code('CONFLICTING_MODES'));
  assert.throws(()=>generator.options(['--resume']),code('CONFLICTING_MODES'));
  assert.throws(()=>generator.options(['--concurrency','3']),code('CONCURRENCY_MUST_BE_ONE_OR_TWO'));
  assert.throws(()=>generator.options(['--output','/tmp/a','--output','/tmp/b']),code('DUPLICATE_OPTION'));
  assert.throws(()=>generator.options(['--generate','--output','/tmp/a']),code('ABSOLUTE_KEY_PATH_REQUIRED'));
  assert.throws(()=>generator.options(['--retry-failed']),code('RETRY_REQUIRES_EXPLICIT_GENERATE_RESUME'));
  const saveLog=console.log;let planned;try{console.log=text=>{planned=JSON.parse(text);};await generator.main(['--plan','--key-file','/never-read']);}finally{console.log=saveLog;}
  assert.equal(planned.mode,'PLAN_ONLY_NO_API_CALLS');assert.equal(planned.new_request_budget,45);assert.equal(forbidden,0);
  await assert.rejects(generator.generate({...opts('not-enabled'),generate:false},dependencies),code('GENERATION_NOT_EXPLICITLY_ENABLED'));
  await assert.rejects(generator.generate({...opts('live'),output:'/var/www/forbidden-supplement'},dependencies),code('LIVE_OUTPUT_FORBIDDEN'));
  report('plan reads no key or network; explicit bounded modes and live-output refusal');
  const completeOptions={...opts('complete'),concurrency:2};let requests=0,flight=0,peak=0;
  const complete=await generator.generate(completeOptions,{...dependencies,requestSpeech:async(body,key)=>{
    assert.equal(key,fakeKey);requests++;flight++;peak=Math.max(peak,flight);
    const m=ledger(completeOptions.output);assert(m.requests_reserved>=requests);
    assert(m.prompts.some(p=>p.generation_status==='REQUESTING' && p.synthesis_instruction===body.contents[0].parts[0].text));
    await new Promise(resolve=>setImmediate(resolve));flight--;return response();
  }});
  assert.equal(requests,45);assert.equal(peak,2);assert.equal(complete.requests_reserved,45);
  assert.equal(generator.readManifest(completeOptions.output).prompts.length,45);
  assert.equal(generator.verifyPack(completeOptions.output).supplemental_set_complete,true);
  for(const field of ['runtime_ready','deployed','audio_listening_review','native_speaker_review','full_position_numeric_range_ready'])assert.equal(complete[field],false);
  const manifestBytes=fs.readFileSync(path.join(completeOptions.output,'manifest.json'),'utf8');
  assert(!manifestBytes.includes(fakeKey));assert(!manifestBytes.includes('/not-read'));
  report('45 reserved-before-transport mock requests, max2 in flight, complete provenance and false runtime claims');
  await generator.generate({...completeOptions,resume:true},{conversionVersion:()=>{throw Error('must not need SoX');}});
  assert.equal(forbidden,0);report('complete resume and verify are credential/provider/converter-free');
  const locked=path.join(completeOptions.output,'.generation.lock');fs.writeFileSync(locked,'',{flag:'wx',mode:0o600});
  await assert.rejects(generator.generate({...completeOptions,resume:true},dependencies),code('GENERATION_LOCKED'));
  fs.unlinkSync(locked);
  const altered=ledger(completeOptions.output);altered.requests_reserved--;
  writeLedger(completeOptions.output,altered);assert.throws(()=>generator.readManifest(completeOptions.output),code('INVALID_PROMPT_INVENTORY'));
  writeLedger(completeOptions.output,complete);
  altered.requests_reserved=46;writeLedger(completeOptions.output,altered);
  assert.throws(()=>generator.readManifest(completeOptions.output),code('INVALID_REQUEST_ACCOUNTING'));writeLedger(completeOptions.output,complete);
  report('exclusive lock and persistent45-request ledger reject busy/tampered/excess inventory');
  const first=complete.prompts[0],audio=path.join(completeOptions.output,first.telephony.file),bytes=fs.readFileSync(audio);
  fs.appendFileSync(audio,Buffer.from([0]));assert.throws(()=>generator.verifyPack(completeOptions.output),code('INVALID_WAVE_CONTAINER'));fs.writeFileSync(audio,bytes);
  fs.renameSync(audio,audio+'.original');fs.symlinkSync(audio+'.original',audio);
  assert.throws(()=>generator.verifyEntry(completeOptions.output,first),code('INVALID_OWNED_FILE'));
  fs.unlinkSync(audio);fs.renameSync(audio+'.original',audio);
  assert.throws(()=>generator.verifyEntry(completeOptions.output,{...first,request_body_sha256:'0'.repeat(64)}),code('SUPPLEMENTAL_PROVENANCE_CHANGED'));
  assert.throws(()=>generator.verifyEntry(completeOptions.output,{...first,telephony:{...first.telephony,file:'../../outside.wav'}}),code('UNEXPECTED_AUDIO_PATH'));
  report('byte tampering, symlink/path substitution and changed request provenance rejected');
  const partialOptions=opts('partial');let attempted=0;
  await assert.rejects(generator.generate(partialOptions,{...dependencies,requestSpeech:async()=>{
    if(++attempted===2)throw Error('untrusted upstream text '+fakeKey);return response();
  }}),code('LOCAL_OPERATION_FAILED'));
  const partial=generator.readManifest(partialOptions.output);assert.equal(partial.requests_reserved,2);
  const saved=partial.prompts[0].master.sha256,failedInstruction=partial.prompts[1].synthesis_instruction;
  let resumed=0;await assert.rejects(generator.generate({...partialOptions,resume:true},{...dependencies,requestSpeech:async body=>{
    resumed++;assert.notEqual(body.contents[0].parts[0].text,failedInstruction);return response();
  }}),code('INCOMPLETE_PACK_REQUIRES_SEPARATE_RETRY_AUTHORIZATION'));
  assert.equal(resumed,43);const remaining=generator.readManifest(partialOptions.output);
  assert.equal(remaining.requests_reserved,45);assert.equal(remaining.prompts[0].master.sha256,saved);
  assert(!fs.readFileSync(path.join(partialOptions.output,'manifest.json'),'utf8').includes(fakeKey));
  await assert.rejects(generator.generate({...partialOptions,resume:true}),code('INCOMPLETE_PACK_REQUIRES_SEPARATE_RETRY_AUTHORIZATION'));
  assert.equal(forbidden,0);report('failed request remains charged; resume preserves good bytes and never retries or exceeds45');
  const originalFailed=remaining.prompts.find(p=>p.generation_status==='FAILED');
  const goodBefore=Object.fromEntries(remaining.prompts.filter(p=>p.generation_status==='GENERATED_QA_PASSED')
    .flatMap(p=>[p.master,p.telephony].map(audio=>[audio.file,hash(path.join(partialOptions.output,audio.file))])));
  let retries=0;
  const repaired=await generator.generate({...partialOptions,resume:true,'retry-failed':true},{...dependencies,requestSpeech:async body=>{
    retries++;assert.equal(body.contents[0].parts[0].text,originalFailed.synthesis_instruction);
    const reserved=ledger(partialOptions.output);assert.equal(reserved.requests_reserved,46);
    assert.equal(reserved.synthesis_requests_maximum,90);assert.equal(reserved.attempts_per_prompt,2);
    const current=reserved.prompts.find(p=>p.id===originalFailed.id && p.locale===originalFailed.locale);
    assert.equal(current.attempt,2);assert.equal(current.generation_status,'REQUESTING');
    assert.deepEqual(current.previous_attempts,[originalFailed]);return response();
  }});
  assert.equal(retries,1);assert.equal(repaired.requests_reserved,46);assert.equal(generator.verifyPack(partialOptions.output).supplemental_set_complete,true);
  const retryEntry=repaired.prompts.find(p=>p.attempt===2);assert.deepEqual(retryEntry.previous_attempts,[originalFailed]);
  assert(retryEntry.master.file.includes('.attempt-2.master-24000.wav'));assert(retryEntry.telephony.file.includes('.attempt-2.telephony-8000.wav'));
  for(const [file,digest] of Object.entries(goodBefore))assert.equal(hash(path.join(partialOptions.output,file)),digest);
  await generator.generate({...partialOptions,resume:true,'retry-failed':true});assert.equal(forbidden,0);
  report('explicit retry upgrades old45 ledger, reserves once, archives original failure, repairs only failed clip and preserves44 good clips');
  const unfinishedOptions=opts('incomplete-audio');let initial=0;
  await assert.rejects(generator.generate(unfinishedOptions,{...dependencies,requestSpeech:async()=>{
    initial++;const result=response();
    if(initial===1)result.candidates[0].finishReason='MAX_TOKENS';
    if(initial===3)result.candidates[0].finishReason='untrusted '+fakeKey;
    return result;
  }}),code('INCOMPLETE_PACK_REQUIRES_SEPARATE_RETRY_AUTHORIZATION'));
  assert.equal(initial,45);const incomplete=generator.readManifest(unfinishedOptions.output);
  assert.equal(incomplete.requests_reserved,45);assert.equal(incomplete.prompts.filter(p=>p.generation_status==='GENERATED_QA_PASSED').length,43);
  const originalFailures=incomplete.prompts.filter(p=>p.generation_status==='FAILED');
  assert.deepEqual(originalFailures.map(p=>p.provider_finish_reason),['MAX_TOKENS','UNKNOWN']);
  assert(!fs.readFileSync(path.join(unfinishedOptions.output,'manifest.json'),'utf8').includes(fakeKey));
  let retryCalls=0;
  await assert.rejects(generator.generate({...unfinishedOptions,resume:true,'retry-failed':true},{...dependencies,requestSpeech:async()=>{
    retryCalls++;const result=response();if(retryCalls===1)result.candidates[0].finishReason='MAX_TOKENS';return result;
  }}),code('INCOMPLETE_PACK_REQUIRES_SEPARATE_RETRY_AUTHORIZATION'));
  assert.equal(retryCalls,2);const attemptedTwice=generator.readManifest(unfinishedOptions.output);assert.equal(attemptedTwice.requests_reserved,47);
  for(const original of originalFailures){const current=attemptedTwice.prompts.find(p=>p.id===original.id && p.locale===original.locale);
    assert.equal(current.attempt,2);assert.deepEqual(current.previous_attempts,[original]);}
  await assert.rejects(generator.generate({...unfinishedOptions,resume:true,'retry-failed':true}),code('SUPPLEMENTAL_RETRY_LIMIT_REACHED'));
  assert.equal(forbidden,0);
  const corruptHistory=JSON.parse(JSON.stringify(attemptedTwice));corruptHistory.prompts[0].attempt=3;writeLedger(unfinishedOptions.output,corruptHistory);
  assert.throws(()=>generator.readManifest(unfinishedOptions.output),code('INVALID_ATTEMPT_HISTORY'));writeLedger(unfinishedOptions.output,attemptedTwice);
  report('incomplete audio continues unrelated initial/retry jobs; allowlisted finish reason only; second failure cannot get third request');
  let denied=0;await assert.rejects(generator.generate(opts('denied'),{...dependencies,requestSpeech:async()=>{
    denied++;throw new samples.SampleError('GEMINI_HTTP_403');
  }}),code('GEMINI_HTTP_403'));assert.equal(denied,1);report('403 stops without automatic retry');
  const digit=prompts.find(p=>p.kind==='callback-digit'),aux=prompts.find(p=>p.kind==='callback-auxiliary');
  assert.throws(()=>fixed.metrics(samples.makeWave(pcm(24000,5.1),24000),24000,digit),code('AUDIO_DURATION_OUT_OF_BOUNDS'));
  assert.throws(()=>fixed.metrics(samples.makeWave(pcm(24000,20.1),24000),24000,aux),code('AUDIO_DURATION_OUT_OF_BOUNDS'));
  assert.throws(()=>fixed.metrics(samples.makeWave(Buffer.alloc(24000),24000),24000,aux),code('AUDIO_SILENT_OR_TOO_QUIET'));
  const clipped=pcm(24000);clipped.writeInt16LE(32767,0);
  assert.throws(()=>fixed.metrics(samples.makeWave(clipped,24000),24000,aux),code('AUDIO_CLIPPED'));
  const tooLong=opts('too-long');await assert.rejects(generator.generate(tooLong,{...dependencies,requestSpeech:async()=>response(20.1)}),code('AUDIO_DURATION_OUT_OF_BOUNDS'));
  const longEntry=generator.readManifest(tooLong.output).prompts[0];assert.equal(longEntry.master.duration_seconds,20.1);assert.equal(longEntry.telephony,undefined);
  report('5/20-second limits, silence/clipping reject; overlong original retained without truncation');
}
let failure;
run().catch(e=>{failure=e.stack||String(e);process.exitCode=1;}).finally(()=>{
  const stable=Object.entries(pins).every(([p,digest])=>hash(p)===digest);
  if(!stable || forbidden){failure=(failure||'')+'\nSource changed or prohibited boundary invoked';process.exitCode=1;}
  https.request=savedRequest;samples.readProtectedKey=savedKeyReader;
  const receipt={status:failure?'failed':'pass',groups,source_inputs:pins,source_inputs_stable:stable,
    forbidden_boundary_calls:forbidden,real_provider_requests:0,real_credential_reads:0,output:scratch,
    fixture_audio:'synthetic tones only; mocked resampling',native_or_listening_acceptance:false,error:failure||null};
  fs.writeFileSync(path.join(scratch,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{mode:0o600});console.log(JSON.stringify(receipt));
  if(failure)console.error(failure);
});
