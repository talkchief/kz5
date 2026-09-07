#!/usr/bin/env node
'use strict';
// Synthetic, offline fixtures. Real HTTPS and real protected-key reads forbidden.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path');
const os = require('node:os'), crypto = require('node:crypto'), https = require('node:https');
const {EventEmitter} = require('node:events');
const {spawnSync} = require('node:child_process');
const trial = require('./trial-acdc-gemini-31-cardinals.cjs'), pack = require('./acdc-cardinal-pack.cjs');
const samples = require('./generate-acdc-gemini-samples.cjs');
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const SENTINEL = 'SYNTHETIC_PROVIDER_KEY_MUST_NEVER_BE_PERSISTED';
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'acdc-31-trial-test.'));
fs.chmodSync(root, 0o700);
const realRequest = https.request; https.request = () => assert.fail('REAL HTTPS FORBIDDEN');
let checks = 0, sequence = 0;
const equal = (a, b) => { checks++; assert.deepEqual(a, b); };
async function rejects(fn, code) { checks++; await assert.rejects(fn, e => !code || e.code === code); }
function sourceFixture(locale = 'he-il', n = 1, attempts = 1) {
  const dir = path.join(root, `source-${++sequence}`); fs.mkdirSync(dir, {mode: 0o700});
  const m = pack.createManifest();
  for (const approval of m.approvals) {
    for (const kind of ['transcript','delivery','intro']) Object.assign(approval[kind], {status: 'APPROVED', evidence_sha256: hash('synthetic approval')});
    Object.assign(approval.intro, {canonical_id: 'acdc-synthetic-intro', transcript: 'SYNTHETIC ONLY',
      transcript_sha256: hash('SYNTHETIC ONLY'), wav_sha256: hash('synthetic wave')});
  }
  m.approvals_sha256 = pack.digest(m.approvals);
  const selected = m.prompts.filter(p => p.locale === locale).slice(0, n);
  for (const entry of selected) {
    const body = pack.requestBody(entry);
    entry.generation_status = 'FAILED';
    entry.attempts = Array.from({length: attempts}, (_, index) => ({number: index + 1, status: 'FAILED',
      reserved_at: '2026-09-07T00:00:00.000Z', synthesis_instruction: body.contents[0].parts[0].text,
      instruction_sha256: hash(body.contents[0].parts[0].text), request_body_sha256: hash(JSON.stringify(body)),
      failure_code: 'AUDIO_GENERATION_NOT_COMPLETE', provider_finish_reason: 'OTHER', raw_pcm_sha256: null,
      master: null, telephony: null}));
  }
  m.requests_reserved = n * attempts; m.retry_request_budget = n * (attempts - 1);
  m.retries_explicitly_enabled = m.retry_request_budget > 0;
  m.conversion.version = pack.RESAMPLING.version;
  const file = path.join(dir, 'manifest.json');
  fs.writeFileSync(file, JSON.stringify(m) + '\n', {flag: 'wx', mode: 0o600});
  return {dir, file, m, selected};
}
function options(fixture, generate = false) {
  const args = ['--source-pack', fixture.dir, '--source-manifest-sha256', hash(fs.readFileSync(fixture.file)),
    '--approval-sha256', fixture.m.approvals_sha256, '--identities', fixture.selected.map(e => `${e.locale}/${e.id}`).join(',')];
  if (generate) args.push('--generate', '--output', path.join(root, `trial-${++sequence}`), '--key-file', path.join(root, 'never-read.key'));
  return trial.options(args);
}
const pcm = Buffer.alloc(24000 / 4 * 2);
for (let n = 0; n < pcm.length / 2; n++) pcm.writeInt16LE(Math.round(1200 * Math.cos(n * 2 * Math.PI * 500 / 24000)), n * 2);
const response = () => ({modelVersion: trial.MODEL, candidates: [{finishReason: 'STOP', content: {parts: [{inlineData: {
  mimeType: 'audio/L16;codec=pcm;rate=24000', data: pcm.toString('base64')}}]}}]});
function dependencies(o, behavior = async () => response()) {
  const counts = {loads: 0, keys: 0, requests: 0};
  return {counts, loadHelper() { counts.loads++; return samples; }, readKey(file) {
    equal(file, path.join(root, 'never-read.key')); counts.keys++; return SENTINEL;
  }, async requestSpeech(body, key) {
    counts.requests++; equal(key, SENTINEL);
    const ledger = JSON.parse(fs.readFileSync(path.join(o.output, 'trial.json')));
    equal(ledger.requests_reserved, counts.requests);
    const entry = ledger.entries[counts.requests - 1];
    equal(entry.status, 'REQUESTING'); equal(entry.request_body_sha256, hash(JSON.stringify(body)));
    equal(ledger.model, trial.MODEL); equal(ledger.voice, 'Sulafat');
    equal(ledger.source_manifest_sha256, o.sourceHash);
    equal(fs.statSync(path.join(o.output, 'trial.json')).mode & 0o777, 0o600);
    assert(entry.reserved_at); checks++;
    return behavior({body, ledger, entry, counts});
  }};
}
const noAccess = {loadHelper() { assert.fail('helper/key/provider load before preflight'); }};
function files(dir) { return fs.readdirSync(dir, {withFileTypes: true}).flatMap(e => e.isDirectory() ? files(path.join(dir, e.name)) : [path.join(dir, e.name)]); }
function fakeHttp(spec, inspect = () => {}) {
  return (url, opts, callback) => {
    const req = new EventEmitter(); req.destroy = () => {};
    req.end = bytes => {
      inspect(url, opts, bytes);
      queueMicrotask(() => {
        if (spec.requestError) { req.emit('error', new Error(SENTINEL)); return; }
        const res = new EventEmitter(); res.statusCode = spec.status ?? 200;
        res.destroy = () => {}; callback(res);
        if (res.statusCode !== 200) return;
        if (spec.abort) { res.emit('aborted'); return; }
        if (spec.responseError) { res.emit('error', new Error(SENTINEL)); return; }
        for (const bytes of spec.chunks || [Buffer.from(JSON.stringify(response()))]) res.emit('data', bytes);
        res.emit('end');
      });
    };
    return req;
  };
}
async function main() {
  const withMime = mime => {const r=response(); r.candidates[0].content.parts[0].inlineData.mimeType=mime; return r;};
  for(const mime of ['audio/L16;codec=pcm;rate=24000','audio/L16;rate=24000;channels=1',
    'audio/L16;rate=24000;channels=1;codec=pcm','audio/L16;channels=1;codec=pcm;rate=24000',
    ' AUDIO/L16 ; RATE=24000 ; CHANNELS=1 ; CODEC=PCM ']) {
    const r=withMime(mime), original=JSON.stringify(r);
    equal(trial.extractTrialPcm(r,samples),pcm); equal(JSON.stringify(r),original);
    equal(trial.audioMimeDiagnostics(r).accepted,true);
  }
  // Legacy shared parser stays strict and unchanged: only this trial adapts.
  await rejects(async()=>samples.extractPcm(withMime('audio/L16;rate=24000;channels=1')),'UNSUPPORTED_AUDIO_FORMAT');
  for(const [mime,code] of [
    [undefined,'AUDIO_MIME_MISSING'],[null,'AUDIO_MIME_MISSING'],[{},'AUDIO_MIME_MISSING'],
    ['','UNSUPPORTED_AUDIO_MIME'],['audio/wav;rate=24000;channels=1','UNSUPPORTED_AUDIO_MIME'],
    ['audio/L16;rate=24000','UNSUPPORTED_AUDIO_FORMAT'],['audio/L16;channels=1','UNSUPPORTED_AUDIO_FORMAT'],
    ['audio/L16;rate=48000;channels=1','UNSUPPORTED_AUDIO_FORMAT'],
    ['audio/L16;rate=024000;channels=1','UNSUPPORTED_AUDIO_FORMAT'],
    ['audio/L16;rate=24000;channels=2','UNSUPPORTED_AUDIO_FORMAT'],
    ['audio/L16;rate=24000;channels=01','UNSUPPORTED_AUDIO_FORMAT'],
    ['audio/L16;rate=24000;channels=1;codec=opus','UNSUPPORTED_AUDIO_FORMAT'],
    ['audio/L16;rate=24000;channels=1;endian=big','UNSUPPORTED_AUDIO_FORMAT'],
    ['audio/L16;rate=24000;channels=1;codec=pcm_s16le','UNSUPPORTED_AUDIO_FORMAT'],
    ['audio/L16;rate="24000";channels=1','UNSUPPORTED_AUDIO_FORMAT'],
    ['audio/L16;rate=24000;channels=1;','INVALID_AUDIO_MIME_PARAMETERS'],
    ['audio/L16;rate=24000;channels','INVALID_AUDIO_MIME_PARAMETERS'],
    ['audio/L16;rate=24000;channels=','INVALID_AUDIO_MIME_PARAMETERS'],
    ['audio/L16;rate=24000;channels=1=2','INVALID_AUDIO_MIME_PARAMETERS'],
    ['audio/L16;rate=24000;rate=24000;channels=1','INVALID_AUDIO_MIME_PARAMETERS'],
    ['audio/L16;rate=24000;channels=1;CHANNELS=1','INVALID_AUDIO_MIME_PARAMETERS'],
    ['audio/L16;rate=24000;codec=pcm;codec=pcm','INVALID_AUDIO_MIME_PARAMETERS'],
    [`audio/L16;rate=${SENTINEL};channels=${SENTINEL};codec=${SENTINEL};${SENTINEL}=x`,'UNSUPPORTED_AUDIO_FORMAT'],
    [SENTINEL,'UNSUPPORTED_AUDIO_MIME'],
  ]) {
    const r=withMime(mime), original=JSON.stringify(r);
    await rejects(async()=>trial.extractTrialPcm(r,samples),code);
    equal(trial.audioMimeDiagnostics(r).accepted,false);equal(JSON.stringify(r),original);
    equal(JSON.stringify(trial.audioMimeDiagnostics(r)).includes(SENTINEL),false);
  }
  equal(trial.audioMimeDiagnostics(withMime('audio/L16;rate=24000;channels=1')),
    {present:true,media_type:'audio/l16',rate:'24000',channels:'1',codec:null,
      malformed_parameters:false,duplicate_parameters:false,unknown_parameters:false,accepted:true});
  equal(trial.audioMimeDiagnostics(withMime(undefined)).present,false);
  equal(trial.audioMimeDiagnostics(withMime(null)).present,true);
  equal(trial.audioMimeDiagnostics(withMime(`audio/L16;codec=${SENTINEL}`)).codec,'UNKNOWN');
  equal(trial.audioMimeDiagnostics(withMime('audio/L16;rate=24000;rate=24000;channels=1')).duplicate_parameters,true);
  for(const data of [SENTINEL,'AA==','AAAA=','']) {
    const r=withMime('audio/L16;rate=24000;channels=1');r.candidates[0].content.parts[0].inlineData.data=data;
    await rejects(async()=>trial.extractTrialPcm(r,samples));
  }
  const notStopped=withMime('audio/L16;rate=24000;channels=1');notStopped.candidates[0].finishReason='OTHER';
  await rejects(async()=>trial.extractTrialPcm(notStopped,samples),'AUDIO_GENERATION_NOT_COMPLETE');
  const duplicateAudio=withMime('audio/L16;rate=24000;channels=1');
  duplicateAudio.candidates[0].content.parts.push(duplicateAudio.candidates[0].content.parts[0]);
  await rejects(async()=>trial.extractTrialPcm(duplicateAudio,samples),'EXPECTED_ONE_AUDIO_PART');
  const base = sourceFixture('he-il', 3, 2), before = fs.readFileSync(base.file);
  const p = options(base), beforeFiles = files(root);
  const planned = trial.plan(p);
  equal(planned.mode, 'PLAN_ONLY_NO_PROVIDER'); equal(planned.requests_maximum, 3);
  equal(planned.source_model, pack.MODEL); equal(planned.model, trial.MODEL);
  equal(files(root), beforeFiles); equal(fs.readFileSync(base.file), before);
  equal(planned.selected.map(x => x.source_attempt_count), [2,2,2]);
  equal(planned.selected.map(x => x.request_body_sha256), base.selected.map(e => hash(JSON.stringify(pack.requestBody(e, pack.CONCISE_SYNTHESIS_RECIPE)))));
  equal(planned.runtime_ready, false); equal(planned.importable, false);
  // Exercise the actual file entrypoint in a fresh process. A missing
  // require.main guard would otherwise silently exit zero without doing work.
  // Synthetic source has no WAVs, so its plan needs neither SoX nor any child.
  const preload=path.join(root,'deny-cli-side-effects.cjs');
  fs.writeFileSync(preload,`
'use strict';
const fs=require('node:fs'), Module=require('node:module');
const deny=()=>{process.stderr.write('FORBIDDEN_OFFLINE_ACCESS\\n');throw new Error('offline CLI access prohibited');};
for(const name of ['writeFileSync','appendFileSync','mkdirSync','rmSync','unlinkSync','renameSync','copyFileSync',
  'chmodSync','symlinkSync','linkSync','truncateSync','writeSync','writeFile','appendFile','mkdir','rm','unlink','rename']) fs[name]=deny;
const open=fs.openSync;
fs.openSync=(file,flags,...rest)=>{
  if(typeof flags==='string' ? flags!=='r' : flags&(fs.constants.O_WRONLY|fs.constants.O_RDWR|fs.constants.O_CREAT|fs.constants.O_TRUNC|fs.constants.O_APPEND)) deny();
  return open(file,flags,...rest);
};
for(const name of ['http','https']) {const transport=require('node:'+name);transport.request=deny;transport.get=deny;}
const net=require('node:net');net.connect=deny;net.createConnection=deny;
require('node:tls').connect=deny;global.fetch=deny;
const cp=require('node:child_process');
for(const name of ['spawn','spawnSync','exec','execSync','execFile','execFileSync','fork']) cp[name]=deny;
const load=Module._load;
Module._load=function(request,...rest){
  if(typeof request==='string'&&request.endsWith('generate-acdc-gemini-samples.cjs')) deny();
  return load.call(this,request,...rest);
};
`,{flag:'wx',mode:0o600});
  const cliArgs=['--source-pack',base.dir,'--source-manifest-sha256',p.sourceHash,
    '--approval-sha256',p.approvalHash,'--identities',p.identities.join(',')];
  const cliFiles=files(root), cliSource=fs.readFileSync(base.file);
  function cli(args) {
    const result=spawnSync(process.execPath,['--require',preload,path.join(__dirname,'trial-acdc-gemini-31-cardinals.cjs'),...args],
      {env:{PATH:'/usr/bin:/bin',LC_ALL:'C',TZ:'UTC'},encoding:'utf8',timeout:15000,maxBuffer:128*1024});
    assert.ifError(result.error);checks++;
    equal(result.signal,null);equal((result.stdout+result.stderr).includes(SENTINEL),false);
    equal(files(root),cliFiles);equal(fs.readFileSync(base.file),cliSource);
    return result;
  }
  for(const args of [cliArgs,['--plan',...cliArgs]]) {
    const result=cli(args);
    equal(result.status,0);equal(result.stderr,'');
    equal(result.stdout.trim().split('\n').length,1);
    equal(JSON.parse(result.stdout),planned);
  }
  const safeFailure='Cardinal model trial stopped safely; inspect its separate trial ledger. Original history and runtime were not modified.\n';
  for(const args of [[],['--unknown',SENTINEL],['--plan',...cliArgs,'--key-file',SENTINEL],
    ['--plan','--generate',...cliArgs]]) {
    const result=cli(args);
    equal(result.status,1);equal(result.stdout,'');equal(result.stderr,safeFailure);
  }
  for (const change of [[], ['--model', trial.MODEL], ['--endpoint', 'https://example.invalid'], ['--resume'],
    ['--plan','--generate'], ['--source-pack',base.dir,'--source-pack',base.dir]]) {
    checks++; assert.throws(() => trial.options(change), trial.TrialError);
  }
  for (const identities of [[], p.identities.concat('he-il/acdc-cardinal-v1-extra'), [p.identities[0],p.identities[0]],
    ['fr-fr/acdc-cardinal-v1-terminal-89'], ['en-us/acdc-cardinal-v1-number-1'], [['he-il/acdc-cardinal-v1-number-0']]])
    await rejects(async () => trial.plan({...p, identities}), 'SELECT_ONE_TO_THREE_EXACT_FAILED_IDENTITIES');
  await rejects(async () => trial.plan({...p, identities:['he-il/acdc-cardinal-v1-nonexistent']}), 'TARGET_NOT_FAILED');
  const pending = base.m.prompts.find(e => e.locale === 'he-il' && e.generation_status === 'PENDING');
  await rejects(async () => trial.plan({...p, identities:[`${pending.locale}/${pending.id}`]}), 'TARGET_NOT_FAILED');
  await rejects(async () => trial.plan({...p, sourceHash:'0'.repeat(64)}), 'SOURCE_MANIFEST_PIN_CHANGED');
  await rejects(async () => trial.plan({...p, approvalHash:'0'.repeat(64)}), 'INDEPENDENT_APPROVAL_PIN_REQUIRED');
  const capped = sourceFixture('he-il',1,6);
  await rejects(() => trial.generate(options(capped,true),noAccess), 'SOURCE_ATTEMPT_CAP_REACHED');
  const inflight = sourceFixture();
  // A source generation lock blocks before any pack replay/provider dependency.
  fs.writeFileSync(path.join(inflight.dir,'.generation.lock'),'synthetic',{flag:'wx',mode:0o600});
  await rejects(() => trial.generate(options(inflight,true),noAccess), 'SOURCE_AUTHORING_IN_PROGRESS');
  const requesting = sourceFixture(), inFlightEntry=requesting.selected[0];
  inFlightEntry.generation_status='REQUESTING'; Object.assign(inFlightEntry.attempts[0],
    {status:'REQUESTING',failure_code:null,provider_finish_reason:null});
  fs.writeFileSync(requesting.file,JSON.stringify(requesting.m)+'\n');
  await rejects(()=>trial.generate(options(requesting,true),noAccess),'SOURCE_HAS_INFLIGHT_REQUEST');
  const unsafe = options(base,true);
  await rejects(() => trial.generate({...unsafe,output:base.dir},noAccess), 'TRIAL_MUST_BE_SEPARATE_FROM_SOURCE_AND_KEY');
  await rejects(() => trial.generate({...unsafe,output:'/opt/kz5/not-a-trial'},noAccess), 'PRIVATE_AUTHORING_OUTPUT_REQUIRED');
  fs.mkdirSync(unsafe.output,{mode:0o700});
  await rejects(() => trial.generate(unsafe,noAccess), 'OUTPUT_ALREADY_EXISTS');

  const o = options(base,true), deps = dependencies(o);
  const done = await trial.generate(o,deps);
  equal(deps.counts.requests,3); equal(done.requests_reserved,3); equal(done.runtime_ready,false);
  equal(done.status,'TRIAL_QA_COMPLETE_NOT_APPROVED'); equal(fs.readFileSync(base.file),before);
  const ledger = JSON.parse(fs.readFileSync(path.join(o.output,'trial.json')));
  equal(ledger.source_requests_reserved,6); equal(ledger.source_retry_budget,3); equal(ledger.source_history_reset,false);
  for(let i=0;i<3;i++) {
    const e=ledger.entries[i]; equal(e.status,'QA_PASSED'); equal(e.source_attempt_count,2);
    equal(e.source_attempt_count_plus_this_trial,3);
    equal(e.source_entry_sha256,pack.digest(base.selected[i])); equal(e.source_attempts_sha256,pack.digest(base.selected[i].attempts));
    equal(e.transcript_sha256,hash(e.transcript)); equal(e.returned_model_version,trial.MODEL);
    equal(e.synthesis_instruction,pack.requestBody(base.selected[i],pack.CONCISE_SYNTHESIS_RECIPE).contents[0].parts[0].text);
    for(const variant of ['master','telephony']) {
      const wav=fs.readFileSync(path.join(o.output,e[variant].file));
      equal(hash(wav),e[variant].sha256); pack.technicalQa(pack.inspectWave(wav,variant==='master'?24000:8000)); checks++;
    }
    equal(e.master.pcm_sha256,e.raw_pcm_sha256);
    equal(hash(pack.resampleMaster(fs.readFileSync(path.join(o.output,e.master.file)))),e.telephony.pcm_sha256);
  }
  await rejects(() => trial.generate(o,noAccess),'OUTPUT_ALREADY_EXISTS');
  const successfulSource=sourceFixture(), sourceEntry=successfulSource.selected[0], qa=ledger.entries[0];
  sourceEntry.generation_status='QA_PASSED';
  Object.assign(sourceEntry.attempts[0],{status:'QA_PASSED',failure_code:null,provider_finish_reason:'STOP',raw_pcm_sha256:qa.raw_pcm_sha256});
  fs.mkdirSync(path.join(successfulSource.dir,sourceEntry.locale),{mode:0o700});
  for(const variant of ['master','telephony']) {
    const file=pack.fileName(sourceEntry,1,variant);
    sourceEntry.attempts[0][variant]={...qa[variant],file};
    fs.copyFileSync(path.join(o.output,qa[variant].file),path.join(successfulSource.dir,file));
  }
  fs.writeFileSync(successfulSource.file,JSON.stringify(successfulSource.m)+'\n');
  await rejects(()=>trial.generate(options(successfulSource,true),noAccess),'TARGET_NOT_FAILED');
  // No subsequent target is requested after a failure; original history stays.
  const failureOptions=options(base,true), rejected=response();
  rejected.candidates[0].finishReason='OTHER'; rejected.candidates[0].finishMessage=SENTINEL;
  rejected.promptFeedback={blockReason:SENTINEL};
  const failed=dependencies(failureOptions,async()=>rejected);
  await rejects(()=>trial.generate(failureOptions,failed),'AUDIO_GENERATION_NOT_COMPLETE');
  equal(failed.counts.requests,1);
  const failureLedger=JSON.parse(fs.readFileSync(path.join(failureOptions.output,'trial.json')));
  equal(failureLedger.entries.map(e=>e.status),['FAILED','SELECTED','SELECTED']);
  equal(failureLedger.entries[0].master,null); equal(failureLedger.entries[0].telephony,null);
  equal(failureLedger.entries[0].response_diagnostics.prompt_block_reason,'UNKNOWN');
  equal(failureLedger.entries[0].response_diagnostics.first_candidate_finish_message_present,true);
  equal(JSON.stringify(failureLedger).includes(SENTINEL),false); equal(fs.readFileSync(base.file),before);
  for(const returned of [undefined,pack.MODEL,SENTINEL]) {
    const f=sourceFixture('es-es'), opt=options(f,true), dep=dependencies(opt,async()=>({...response(),modelVersion:returned}));
    await rejects(()=>trial.generate(opt,dep),'TRIAL_RETURNED_MODEL_MISMATCH');
    equal(dep.counts.requests,1); equal(fs.readFileSync(path.join(opt.output,'trial.json'),'utf8').includes(SENTINEL),false);
  }
  const ar=sourceFixture('ar-sa'), arPlan=trial.plan(options(ar));
  equal(arPlan.selected[0].transcript,ar.selected[0].transcript);
  // Real WAV/SoX QA for both new spellings; diagnostics must already be on
  // disk while the shared helper first sees the normalized response copy.
  for(const mime of ['audio/L16;rate=24000;channels=1','audio/L16;codec=pcm;rate=24000;channels=1']) {
    const f=sourceFixture(), opt=options(f,true), r=withMime(mime), original=JSON.stringify(r);
    const dep=dependencies(opt,async()=>r);let extractions=0;
    dep.loadHelper=()=>({...samples,extractPcm(normalized){
      extractions++;
      const reserved=JSON.parse(fs.readFileSync(path.join(opt.output,'trial.json')));
      equal(reserved.entries[0].status,'REQUESTING');
      equal(reserved.entries[0].audio_mime_diagnostics,trial.audioMimeDiagnostics(r));
      equal(reserved.entries[0].returned_model_version,trial.MODEL);
      equal(reserved.entries[0].response_diagnostics.finish_reason,'STOP');
      equal(reserved.entries[0].raw_pcm_sha256,null);
      return samples.extractPcm(normalized);
    }});
    await trial.generate(opt,dep);equal(extractions,1);equal(dep.counts.requests,1);equal(JSON.stringify(r),original);
    const saved=JSON.parse(fs.readFileSync(path.join(opt.output,'trial.json'))).entries[0];
    equal(saved.status,'QA_PASSED');equal(saved.raw_pcm_sha256,hash(pcm));
    equal(saved.audio_mime_diagnostics,trial.audioMimeDiagnostics(r));equal(fs.readFileSync(f.file),Buffer.from(JSON.stringify(f.m)+'\n'));
  }
  const badMimeSource=sourceFixture(), badMimeOptions=options(badMimeSource,true);
  const badMimeResponse=withMime(`audio/L16;rate=24000;channels=1;codec=${SENTINEL};${SENTINEL}=x`);
  const badMimeDeps=dependencies(badMimeOptions,async()=>badMimeResponse);
  await rejects(()=>trial.generate(badMimeOptions,badMimeDeps),'UNSUPPORTED_AUDIO_FORMAT');
  const badMimeBytes=fs.readFileSync(path.join(badMimeOptions.output,'trial.json'),'utf8');
  equal(badMimeBytes.includes(SENTINEL),false);equal(badMimeDeps.counts.requests,1);
  const badMimeEntry=JSON.parse(badMimeBytes).entries[0];
  equal(badMimeEntry.audio_mime_diagnostics.codec,'UNKNOWN');equal(badMimeEntry.audio_mime_diagnostics.unknown_parameters,true);
  equal(badMimeEntry.status,'FAILED');equal(badMimeEntry.master,null);equal(badMimeEntry.telephony,null);
  for(const [name,behavior,code] of [
    ['local-error',async()=>{throw new Error(SENTINEL);},'LOCAL_OPERATION_FAILED'],
    ['typed-secret-error',async()=>{throw new trial.TrialError(SENTINEL);},'LOCAL_OPERATION_FAILED'],
    ['silent',async()=>{const r=response();r.candidates[0].content.parts[0].inlineData.data=Buffer.alloc(pcm.length).toString('base64');return r;},'AUDIO_SILENT_OR_TOO_QUIET'],
    ['no-audio',async()=>({modelVersion:trial.MODEL,candidates:[{finishReason:'STOP',content:{parts:[]}}]}),'EXPECTED_ONE_AUDIO_PART'],
  ]) {
    const f=sourceFixture(), opt=options(f,true), dep=dependencies(opt,behavior);
    await rejects(()=>trial.generate(opt,dep),code); equal(dep.counts.requests,1);
    equal(fs.readFileSync(path.join(opt.output,'trial.json'),'utf8').includes(SENTINEL),false);
  }
  const changed=sourceFixture(), changedOptions=options(changed,true), changedDeps=dependencies(changedOptions,async()=>{
    fs.appendFileSync(changed.file,' '); return response();
  });
  await rejects(()=>trial.generate(changedOptions,changedDeps),'SOURCE_MANIFEST_PIN_CHANGED'); equal(changedDeps.counts.requests,1);

  equal(trial.REQUEST_TIMEOUT_MS,90000); equal(trial.MAX_RESPONSE_BYTES,2*1024*1024);
  let transports=0;
  await trial.requestSpeech(pack.requestBody(base.selected[0],pack.CONCISE_SYNTHESIS_RECIPE),SENTINEL,fakeHttp({},(url,opts,bytes)=>{
    transports++; equal(url,'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-tts-preview:generateContent');
    equal(opts.method,'POST'); equal(opts.headers['x-goog-api-key'],SENTINEL);
    equal(url.includes(SENTINEL),false); equal(bytes.includes(Buffer.from(SENTINEL)),false);
    equal(opts.headers['Content-Length'],bytes.length);
  })); equal(transports,1);
  for(const [spec,code] of [[{status:302},'GEMINI_HTTP_302'],[{status:500},'GEMINI_HTTP_500'],
    [{requestError:true},'GEMINI_REQUEST_FAILED'],[{responseError:true},'GEMINI_RESPONSE_FAILED'],
    [{abort:true},'GEMINI_RESPONSE_ABORTED'],[{chunks:[Buffer.from(SENTINEL)]},'GEMINI_INVALID_JSON'],
    [{chunks:[Buffer.alloc(2*1024*1024+1)]},'GEMINI_RESPONSE_TOO_LARGE']]) {
    let calls=0;
    await rejects(()=>trial.requestSpeech({},SENTINEL,fakeHttp(spec,()=>{calls++;})),code);
    equal(calls,1);
  }
  const realTimer=global.setTimeout;
  try {
    global.setTimeout=(fn,ms)=>{equal(ms,90000);const timer=realTimer(()=>{},5000);queueMicrotask(fn);return timer;};
    let destroyed=0;
    const hanging=()=>{const req=new EventEmitter();req.end=()=>{};req.destroy=()=>{destroyed++;};return req;};
    await rejects(()=>trial.requestSpeech({},SENTINEL,hanging),'GEMINI_REQUEST_TIMED_OUT');
    equal(destroyed,1);
  } finally { global.setTimeout=realTimer; }
  for(const file of files(root).filter(f=>f.endsWith('.json'))) equal(fs.readFileSync(file,'utf8').includes(SENTINEL),false);
  console.log(`PASS separate Gemini 3.1 cardinal model trial: ${checks} offline checks; no provider calls or original history writes`);
}
main().catch(error=>{console.error(error);process.exitCode=1;}).finally(()=>{
  https.request=realRequest;
  assert(path.dirname(root)===os.tmpdir()&&path.basename(root).startsWith('acdc-31-trial-test.'));
  fs.rmSync(root,{recursive:true,force:true});
});
