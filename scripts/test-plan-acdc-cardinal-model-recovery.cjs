#!/usr/bin/env node
'use strict';
// Offline planner-composition fixtures. The separately tested resolver owns
// source/ledger/WAV validation; no provider, keys or actual asset writes here.
const assert=require('node:assert/strict'), fs=require('node:fs'), path=require('node:path');
const os=require('node:os'), crypto=require('node:crypto'), {spawnSync}=require('node:child_process');
const planner=require('./plan-acdc-cardinal-model-recovery.cjs'), pack=require('./acdc-cardinal-pack.cjs');
let checks=0;
const equal=(a,b)=>{checks++;assert.deepEqual(a,b);};
const rejects=(fn,code)=>{checks++;assert.throws(fn,e=>!code||e.code===code);};
const hash=v=>crypto.createHash('sha256').update(v).digest('hex');
const clone=v=>JSON.parse(JSON.stringify(v));
const identity=e=>`${e.locale}/${e.id}`;
const secret='SYNTHETIC_RECOVERY_SECRET_MUST_NOT_LEAK';
const source=pack.createManifest();
for(const approval of source.approvals) {
  for(const kind of ['transcript','delivery','intro']) Object.assign(approval[kind],{status:'APPROVED',evidence_sha256:hash('synthetic approval')});
  Object.assign(approval.intro,{canonical_id:'acdc-synthetic-intro',transcript:'SYNTHETIC ONLY',
    transcript_sha256:hash('SYNTHETIC ONLY'),wav_sha256:hash('synthetic wave')});
}
source.approvals_sha256=pack.digest(source.approvals);
for(const entry of source.prompts) {
  entry.generation_status='FAILED';entry.attempts=[{status:'FAILED'}];
}
source.requests_reserved=source.prompts.length;
const he=source.prompts.filter(e=>e.locale==='he-il');
he[2].attempts=Array.from({length:6},()=>({status:'FAILED'}));
he[3].generation_status='PENDING';he[3].attempts=[];
he[4].generation_status='QA_PASSED';
const base={sourceDirectory:'/synthetic/source',sourceManifestSha256:'1'.repeat(64),approvalSha256:source.approvals_sha256,
  trials:[{directory:'/synthetic/trial-a',sha256:'2'.repeat(64)},{directory:'/synthetic/trial-b',sha256:'3'.repeat(64)}],maxRequests:12};
const summary={additional_trial_requests:3,trials:[
  {trial_manifest_sha256:base.trials[0].sha256,outcomes:[{identity:identity(he[0]),status:'FAILED'},
    {identity:identity(he[1]),status:'FAILED'},{identity:identity(he[5]),status:'SELECTED'}]},
  {trial_manifest_sha256:base.trials[1].sha256,outcomes:[{identity:identity(he[0]),status:'QA_PASSED'}]},
]};
function dependency(manifest=source,prior=summary) {
  const counts={opens:0,reads:0};
  return {counts,openResolution(o){counts.opens++;
    equal(o.sourceDirectory,base.sourceDirectory);equal(o.sourceManifestSha256,base.sourceManifestSha256);
    equal(o.approvalSha256,base.approvalSha256);
    return {sourceManifest(){counts.reads++;return clone(manifest);},summary(){return clone(prior);}};
  }};
}
const before=JSON.stringify({source,summary,base}), deps=dependency(), p=planner.plan(base,deps);
equal(deps.counts,{opens:1,reads:2});equal(JSON.stringify({source,summary,base}),before);
equal(p.requests_proposed,12);equal(p.batches.length,4);equal(p.batches.map(b=>b.identities.length),[3,3,3,3]);
equal(p.batches.flatMap(b=>b.identities),p.selected.map(e=>e.identity));
equal(p.model,'gemini-3.1-flash-tts-preview');equal(p.voice,'Sulafat');equal(p.automatic_retries,0);
for(const key of ['runtime_ready','deployed','importable','native_listening_approved','source_history_reset']) equal(p[key],false);
equal(p.exclusions.find(e=>e.identity===identity(he[0])).reason,'saved_model_trial_qa');
equal(p.exclusions.find(e=>e.identity===identity(he[0])).prior_model_requests,2);
equal(p.exclusions.find(e=>e.identity===identity(he[1])).reason,'manual_diagnostic_required');
equal(p.exclusions.find(e=>e.identity===identity(he[2])).reason,'hard_attempt_cap');
for(const id of planner.ALIASES) equal(p.exclusions.find(e=>e.identity===id).reason,'exact_supplemental_alias');
const all=planner.plan({...base,maxRequests:12},dependency());
const expected=source.prompts.filter(e=>planner.LOCALES.includes(e.locale)&&e.generation_status==='FAILED'
  &&e.attempts.length<6&&!planner.ALIASES.includes(identity(e))&&![identity(he[0]),identity(he[1])].includes(identity(e)));
equal(all.eligible_unrequested_count,expected.length);equal(all.selected.map(e=>e.identity),expected.slice(0,12).map(identity));
equal(all.selected.some(e=>e.identity.startsWith('fr-fr/')||e.identity.startsWith('en-us/')),false);
for(const row of p.selected) {
  const entry=source.prompts.find(e=>identity(e)===row.identity);
  equal(row.source_entry_sha256,pack.digest(entry));equal(row.source_attempts_sha256,pack.digest(entry.attempts));
  equal(row.transcript_sha256,hash(row.transcript));equal(row.prior_model_requests,0);
  equal(row.request_body_sha256,hash(JSON.stringify(pack.requestBody(entry,pack.CONCISE_SYNTHESIS_RECIPE))));
  equal(row.total_requests_if_generated,row.source_attempt_count+1);
}
const {plan_sha256,...digestible}=p;equal(plan_sha256,pack.digest(digestible));
const reordered=clone(source);reordered.prompts.reverse();
equal(planner.plan({...base,trials:[...base.trials].reverse()},dependency(reordered)),p);
for(const limit of [1,2,3,4,11,12]) {
  const proposed=planner.plan({...base,maxRequests:limit},dependency());
  equal(proposed.requests_proposed,limit);equal(proposed.batches.every(b=>b.identities.length<=3),true);
}
const none=clone(source);for(const e of none.prompts) e.generation_status='QA_PASSED';
const empty=planner.plan(base,dependency(none));equal(empty.requests_proposed,0);equal(empty.batches,[]);
const pendingTrial=clone(summary);pendingTrial.trials[0].outcomes[0].status='REQUESTING';
rejects(()=>planner.plan(base,dependency(source,pendingTrial)),'AMBIGUOUS_PRIOR_TRIAL_STATE');
const duplicates=clone(summary);duplicates.trials[0].outcomes[0].status='QA_PASSED';
rejects(()=>planner.plan(base,dependency(source,duplicates)),'DUPLICATE_SUCCESS_IDENTITY');
const selectedOnly=clone(summary);selectedOnly.trials.forEach(t=>t.outcomes.forEach(e=>e.status='SELECTED'));
equal(planner.plan(base,dependency(source,selectedOnly)).exclusions.some(e=>e.identity===identity(he[0])),false);
const badApproval=clone(source);badApproval.approvals[0].transcript.status='PENDING';
rejects(()=>planner.plan(base,dependency(badApproval)));
for(const change of [{maxRequests:0},{maxRequests:13},{maxRequests:'3'},{maxRequests:1.5},{trials:[]},
  {trials:[base.trials[0],base.trials[0]]},{trials:[base.trials[0],{directory:'/different',sha256:base.trials[0].sha256}]},
  {trials:[{directory:'relative',sha256:'1'.repeat(64)}]},{sourceManifestSha256:'bad'},
  {sourceDirectory:'/synthetic/../source'},{keyFile:secret},{generate:true}]) {
  rejects(()=>planner.plan({...base,...change},{openResolution(){assert.fail('invalid options accessed resolver');}}));
}
for(const code of ['MALFORMED_TRIAL','TRIAL_PIN_CHANGED','SOURCE_PIN_CHANGED','DUPLICATE_SUCCESS_IDENTITY'])
  rejects(()=>planner.plan(base,{openResolution(){throw Object.assign(new Error(secret),{code});}}),code);
let reads=0;
rejects(()=>planner.plan(base,{openResolution(){return {summary:()=>summary,sourceManifest(){
  if(++reads===2) throw Object.assign(new Error(secret),{code:'TRIAL_PIN_CHANGED'});return clone(source);
}};}}),'TRIAL_PIN_CHANGED');
const args=['--source-pack',base.sourceDirectory,'--source-manifest-sha256',base.sourceManifestSha256,
  '--approval-sha256',base.approvalSha256,'--prior-trial',base.trials[0].directory,base.trials[0].sha256,
  '--prior-trial',base.trials[1].directory,base.trials[1].sha256];
equal(planner.options(args),{...base,maxRequests:3});equal(planner.options(['--plan',...args,'--max-requests','12']),base);
for(const extra of [['--generate'],['--key-file',secret],['--output','/tmp/forbidden'],['--retry'],
  ['--max-requests','13'],['--max-requests','03'],['--max-requests','1e1'],['--plan','--plan'],['--prior-trial','/missing']])
  rejects(()=>planner.options([...args,...extra]));

// Real CLI dispatch with an explicitly synthetic resolver, network/write/key
// denial, and no dependence on the changing checked-in provider receipts.
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'acdc-recovery-plan-test.'));
try {
  const fixture=path.join(temp,'synthetic.json'), preload=path.join(temp,'preload.cjs');
  fs.writeFileSync(fixture,JSON.stringify({source,summary}),{mode:0o600,flag:'wx'});
  fs.writeFileSync(preload,`
'use strict';
const fs=require('node:fs'), Module=require('node:module');
const fixture=JSON.parse(fs.readFileSync(${JSON.stringify(fixture)},'utf8'));
const deny=()=>{throw new Error('FORBIDDEN_OFFLINE_OPERATION');};
for(const name of ['writeFileSync','appendFileSync','writeSync','mkdirSync','rmSync','unlinkSync','renameSync'])fs[name]=deny;
for(const name of ['http','https']){require('node:'+name).request=deny;require('node:'+name).get=deny;}
require('node:net').connect=deny;require('node:tls').connect=deny;global.fetch=deny;
const load=Module._load;
Module._load=function(request,...rest){
  if(request.endsWith('/acdc-cardinal-model-trial-assets.cjs'))return {openResolution(){return {
    sourceManifest:()=>fixture.source,summary:()=>fixture.summary};}};
  if(/generate-acdc|trial-acdc-gemini-31/.test(request))deny();
  return load.call(this,request,...rest);
};
`,{mode:0o600,flag:'wx'});
  const run=argv=>spawnSync(process.execPath,['--require',preload,path.join(__dirname,'plan-acdc-cardinal-model-recovery.cjs'),...argv],
    {env:{PATH:'/usr/bin:/bin',LC_ALL:'C',TZ:'UTC'},encoding:'utf8',timeout:15000,maxBuffer:128*1024});
  const result=run([...args,'--max-requests','12']);assert.ifError(result.error);checks++;
  equal(result.status,0);equal(result.stderr,'');equal(JSON.parse(result.stdout),p);
  for(const argv of [[],['--generate',secret],['--key-file',secret]]) {
    const invalid=run(argv);assert.ifError(invalid.error);checks++;
    equal(invalid.status,1);equal(invalid.stdout,'');equal(invalid.stderr.includes(secret),false);
    equal(invalid.stderr,'Cardinal recovery plan rejected safely; no provider, key, write, import or runtime action was attempted.\n');
  }
} finally {
  assert(path.dirname(temp)===os.tmpdir()&&path.basename(temp).startsWith('acdc-recovery-plan-test.'));
  fs.rmSync(temp,{recursive:true,force:true});
}
console.log(`PASS cardinal recovery planner: ${checks} offline checks; synthetic resolver, no provider calls`);
