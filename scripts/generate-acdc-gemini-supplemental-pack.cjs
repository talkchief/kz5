#!/usr/bin/env node
'use strict';

// Exactly 45 missing fixed callback clips, in a separate reservation ledger.
// Opt-in authoring only; never called by account creation, editor or playback.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const samples=require('./generate-acdc-gemini-samples.cjs');
const fixed=require('./generate-acdc-gemini-fixed-pack.cjs');
const {PROMPTS,plan}=require('./acdc-gemini-supplemental-catalog.cjs');
const {SampleError,MODEL,VOICE,ENDPOINT}=samples;
const OWNER='kazoo5-acdc-gemini-supplemental-pack',REQUEST_BUDGET=45;
const RETRY_BUDGET=45,MAX_REQUEST_BUDGET=REQUEST_BUDGET+RETRY_BUDGET;
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const CATALOG_HASH=hash(JSON.stringify(PROMPTS));
const check=(ok,code)=>{if(!ok)throw new SampleError(code);};
const safeCode=e=>e instanceof SampleError?e.code:'LOCAL_OPERATION_FAILED';
const identity=p=>`${p.locale}/${p.id}`;
function expected(entry) { return PROMPTS.find(p=>identity(p)===identity(entry)); }
function requestBody(entry) {
  const wanted=expected(entry);
  check(wanted && Object.keys(wanted).every(k=>entry[k]===wanted[k]),'UNAPPROVED_SUPPLEMENTAL_TEXT');
  const context=wanted.kind==='callback-digit'
    ? 'This is one individually spoken telephone digit. Read its written word exactly once, not a number sequence or ordinal. '
    : '';
  return {contents:[{parts:[{text:`Read the transcript below verbatim in native ${wanted.language}. `+
    'Use a professional, warm, natural adult female call-center voice. '+context+
    'Speak clearly at a comfortable conversational pace. Only speak the transcript: no introduction, added words, music or sound effects. '+
    `The complete message must fit within ${wanted.maximum_duration_seconds} seconds; do not rush or omit any words.\n\nTranscript:\n${wanted.transcript}`}]}],
    generationConfig:{responseModalities:['AUDIO'],speechConfig:{voiceConfig:{prebuiltVoiceConfig:{voiceName:VOICE}}}}};
}
function fileName(entry,variant) {
  const suffix=attemptNumber(entry)===2?'.attempt-2':'';
  return `${entry.locale}/${entry.id}${suffix}.${variant==='master'?'master-24000':'telephony-8000'}.wav`;
}
function attemptNumber(entry) {return entry.attempt===undefined?1:entry.attempt;}
function validateRecord(entry) {
  const body=requestBody(entry);
  check(entry.source==='new_request' && entry.provider==='google-gemini' && entry.model===MODEL && entry.voice===VOICE &&
    ['REQUESTING','FAILED','GENERATED_QA_PASSED'].includes(entry.generation_status),'INVALID_PROMPT_STATUS');
  check(entry.transcript_sha256===hash(entry.transcript) && entry.request_body_sha256===hash(JSON.stringify(body)) &&
    entry.synthesis_instruction===body.contents[0].parts[0].text,'SUPPLEMENTAL_PROVENANCE_CHANGED');
}
function validateHistory(entry) {
  validateRecord(entry);
  const attempt=attemptNumber(entry),history=entry.previous_attempts;
  check(attempt===1 || attempt===2,'INVALID_ATTEMPT_HISTORY');
  if(attempt===1)check(history===undefined || (Array.isArray(history) && history.length===0),'INVALID_ATTEMPT_HISTORY');
  else {
    check(Array.isArray(history) && history.length===1,'INVALID_ATTEMPT_HISTORY');
    const prior=history[0];validateRecord(prior);
    check(identity(prior)===identity(entry) && attemptNumber(prior)===1 && prior.previous_attempts===undefined &&
      prior.generation_status==='FAILED','INVALID_ATTEMPT_HISTORY');
  }
  return attempt;
}
function finishReason(response) {
  const value=response?.candidates?.[0]?.finishReason;
  return ['STOP','MAX_TOKENS','SAFETY','RECITATION','LANGUAGE','OTHER','BLOCKLIST','PROHIBITED_CONTENT','SPII',
    'MALFORMED_FUNCTION_CALL','IMAGE_SAFETY','UNEXPECTED_TOOL_CALL','TOO_MANY_TOOL_CALLS',
    'IMAGE_PROHIBITED_CONTENT','NO_IMAGE','IMAGE_RECITATION','IMAGE_OTHER','FINISH_REASON_UNSPECIFIED'].includes(value)?value:'UNKNOWN';
}
function verifyEntry(directory,entry) {
  validateHistory(entry);
  const wanted=expected(entry);check(wanted,'UNEXPECTED_SUPPLEMENTAL_ENTRY');
  const body=requestBody(entry);
  check(entry.transcript_sha256===hash(wanted.transcript) &&
    entry.synthesis_instruction===body.contents[0].parts[0].text &&
    entry.request_body_sha256===hash(JSON.stringify(body)),'SUPPLEMENTAL_PROVENANCE_CHANGED');
  check(entry.provider==='google-gemini' && entry.model===MODEL && entry.voice===VOICE &&
    entry.generation_status==='GENERATED_QA_PASSED','SUPPLEMENTAL_VOICE_OR_STATUS_MISMATCH');
  check(/^[a-f0-9]{64}$/.test(entry.raw_pcm_sha256),'INCOMPLETE_PROVENANCE');
  for(const variant of ['master','telephony']) {
    const saved=entry[variant];check(saved && saved.file===fileName(entry,variant),'UNEXPECTED_AUDIO_PATH');
    const actual=fixed.metrics(fixed.regularBytes(path.join(directory,saved.file)),variant==='master'?24000:8000,wanted);
    check(Object.keys(actual).every(k=>actual[k]===saved[k]),'SUPPLEMENTAL_AUDIO_HASH_OR_METRICS_MISMATCH');
  }
  check(Math.abs(entry.master.duration_seconds-entry.telephony.duration_seconds)<=1/8000,'RESAMPLING_CHANGED_DURATION');
  return entry;
}
function readManifest(directory) {
  check(path.isAbsolute(directory) && path.resolve(directory)===directory &&
    fs.realpathSync(directory)===directory && fs.lstatSync(directory).isDirectory(),'INVALID_PACK_DIRECTORY');
  const m=JSON.parse(fixed.regularBytes(path.join(directory,'manifest.json')));
  check(m.schema_version===1 && m.owner===OWNER && m.catalog_sha256===CATALOG_HASH &&
    m.provider==='google-gemini' && m.model===MODEL && m.voice===VOICE,'UNOWNED_OR_CHANGED_SUPPLEMENTAL_PACK');
  const upgraded=m.attempts_per_prompt===2;
  check((m.attempts_per_prompt===1 || upgraded) && m.synthesis_requests_maximum===(upgraded?MAX_REQUEST_BUDGET:REQUEST_BUDGET) &&
    (!upgraded || (m.initial_request_budget===REQUEST_BUDGET && m.retry_request_budget===RETRY_BUDGET && m.retries_explicitly_enabled===true)) &&
    m.automatic_retries===0 && Number.isInteger(m.requests_reserved) && m.requests_reserved>=0 &&
    m.requests_reserved<=m.synthesis_requests_maximum,'INVALID_REQUEST_ACCOUNTING');
  check(Array.isArray(m.prompts) && m.prompts.length<=REQUEST_BUDGET &&
    new Set(m.prompts.map(identity)).size===m.prompts.length,'INVALID_PROMPT_INVENTORY');
  let attempts=0;
  for(const entry of m.prompts) {
    const count=validateHistory(entry);check(upgraded || count===1,'INVALID_ATTEMPT_HISTORY');attempts+=count;
    if(entry.generation_status==='GENERATED_QA_PASSED')verifyEntry(directory,entry);
  }
  check(attempts===m.requests_reserved,'INVALID_PROMPT_INVENTORY');
  check(m.runtime_ready===false && m.deployed===false && m.native_speaker_review===false &&
    m.audio_listening_review===false && m.full_position_numeric_range_ready===false,'UNEXPECTED_READINESS_CLAIM');
  return m;
}
function summarize(m) {
  m.supplemental_set_complete=PROMPTS.every(p=>m.prompts.some(e=>identity(e)===identity(p) && e.generation_status==='GENERATED_QA_PASSED'));
  m.runtime_ready=false;m.deployed=false;m.native_speaker_review=false;m.audio_listening_review=false;m.full_position_numeric_range_ready=false;
  m.updated_at=new Date().toISOString();
}
function save(directory,m) {summarize(m);fixed.manifestWrite(directory,m);}
function options(argv) {
  const o={concurrency:1},seen=new Set();
  for(let i=0;i<argv.length;i++) {
    const arg=argv[i];check(!seen.has(arg),'DUPLICATE_OPTION');seen.add(arg);
    if(['--plan','--generate','--resume','--retry-failed','--verify-only'].includes(arg))o[arg.slice(2)]=true;
    else {
      const key={'--key-file':'keyFile','--output':'output','--concurrency':'concurrency'}[arg];
      check(key && i+1<argv.length && !argv[i+1].startsWith('--'),'UNKNOWN_OR_INCOMPLETE_OPTION');o[key]=argv[++i];
    }
  }
  o.concurrency=Number(o.concurrency);check([1,2].includes(o.concurrency),'CONCURRENCY_MUST_BE_ONE_OR_TWO');
  check([o.plan,o.generate,o['verify-only']].filter(Boolean).length<=1 && (!o.resume || o.generate),'CONFLICTING_MODES');
  check(!o['retry-failed'] || (o.generate && o.resume),'RETRY_REQUIRES_EXPLICIT_GENERATE_RESUME');
  if(o.generate || o['verify-only'])check(o.output && path.isAbsolute(o.output),'ABSOLUTE_OUTPUT_REQUIRED');
  if(o.generate)check(o.keyFile && path.isAbsolute(o.keyFile),'ABSOLUTE_KEY_PATH_REQUIRED');
  return o;
}
async function generate(o,deps={}) {
  check(o.generate===true,'GENERATION_NOT_EXPLICITLY_ENABLED');
  check([1,2].includes(o.concurrency),'CONCURRENCY_MUST_BE_ONE_OR_TWO');
  check(!o['retry-failed'] || o.resume===true,'RETRY_REQUIRES_EXPLICIT_GENERATE_RESUME');
  fixed.directoryTarget(o.output,!!o.resume);
  if(!o.resume) {
    fs.mkdirSync(o.output,{mode:0o700});
    for(const locale of samples.LOCALES)fs.mkdirSync(path.join(o.output,locale),{mode:0o755});
  }
  const stat=fs.statSync(o.output);
  check(stat.uid===process.getuid() && (stat.mode&0o077)===0,'GENERATION_DIRECTORY_NOT_PROTECTED');
  const lockPath=path.join(o.output,'.generation.lock');let lock;
  try{lock=fs.openSync(lockPath,fs.constants.O_WRONLY|fs.constants.O_CREAT|fs.constants.O_EXCL|fs.constants.O_NOFOLLOW,0o600);}
  catch(_){throw new SampleError('GENERATION_LOCKED');}
  let key;
  try {
    const m=o.resume?readManifest(o.output):{schema_version:1,owner:OWNER,scope:'callback-auxiliary-five-locales-and-en-fr-es-telephone-digits',
      provider:'google-gemini',model:MODEL,preview_model:true,voice:VOICE,voice_style:'warm adult female',api_endpoint:ENDPOINT,
      source_catalog:'scripts/acdc-gemini-supplemental-catalog.cjs',catalog_sha256:CATALOG_HASH,
      synthesis_requests_maximum:REQUEST_BUDGET,requests_reserved:0,attempts_per_prompt:1,automatic_retries:0,
      generation_status:'IN_PROGRESS',created_at:new Date().toISOString(),prompts:[]};
    const pending=PROMPTS.filter(p=>!m.prompts.some(e=>identity(e)===identity(p))).map(wanted=>({wanted}));
    // Snapshot only already-failed first attempts. A failure in this invocation
    // never schedules its own retry, even when explicit retry mode was selected.
    const retries=o['retry-failed']?m.prompts.filter(e=>e.generation_status==='FAILED' && attemptNumber(e)===1)
      .map(prior=>({wanted:expected(prior),prior:JSON.parse(JSON.stringify(prior))})):[];
    const jobs=[...pending,...retries];
    summarize(m);
    if(!jobs.length) {
      check(m.supplemental_set_complete,o['retry-failed']?'SUPPLEMENTAL_RETRY_LIMIT_REACHED':'INCOMPLETE_PACK_REQUIRES_SEPARATE_RETRY_AUTHORIZATION');return m;
    }
    if(o['retry-failed']) {
      m.synthesis_requests_maximum=MAX_REQUEST_BUDGET;m.attempts_per_prompt=2;
      m.initial_request_budget=REQUEST_BUDGET;m.retry_request_budget=RETRY_BUDGET;m.retries_explicitly_enabled=true;
    }
    check(m.requests_reserved+jobs.length<=m.synthesis_requests_maximum,'REQUEST_BUDGET_EXHAUSTED');
    for(const locale of samples.LOCALES) {
      const dir=path.join(o.output,locale);check(fs.realpathSync(dir)===dir && fs.lstatSync(dir).isDirectory(),'INVALID_LOCALE_DIRECTORY');
    }
    const version=(deps.conversionVersion||fixed.conversionVersion)();
    if(!o.resume)m.conversion={tool:'sox',version,transformations:'resampling only; no speedup, trimming, gain or normalization'};
    else check(m.conversion?.tool==='sox' && m.conversion.version===version,'CONVERSION_VERSION_CHANGED');
    save(o.output,m);
    key=(deps.readProtectedKey||samples.readProtectedKey)(o.keyFile);
    const ask=deps.requestSpeech||samples.requestSpeech,convert=deps.resample||fixed.resample;
    const output=deps.output||(entry=>console.log(JSON.stringify(entry)));
    let next=0,stopped,incomplete;m.generation_status='IN_PROGRESS';delete m.failure_code;
    async function worker() {
      while(!stopped && next<jobs.length) {
        const {wanted,prior}=jobs[next++],body=requestBody(wanted);
        const entry={...wanted,source:'new_request',provider:'google-gemini',model:MODEL,voice:VOICE,
          generation_status:'REQUESTING',reserved_at:new Date().toISOString(),transcript_sha256:hash(wanted.transcript),
          synthesis_instruction:body.contents[0].parts[0].text,request_body_sha256:hash(JSON.stringify(body))};
        if(prior) {
          const index=m.prompts.findIndex(e=>identity(e)===identity(wanted));
          check(index>=0 && m.prompts[index].generation_status==='FAILED' && attemptNumber(m.prompts[index])===1,'RETRY_TARGET_CHANGED');
          const archived={...prior};delete archived.previous_attempts;
          entry.attempt=2;entry.previous_attempts=[archived];m.prompts[index]=entry;
        } else m.prompts.push(entry);
        m.requests_reserved++;check(m.requests_reserved<=m.synthesis_requests_maximum,'REQUEST_BUDGET_EXHAUSTED');
        save(o.output,m); // Durable initial/retry reservation before any transport.
        try {
          const response=await ask(body,key);entry.provider_finish_reason=finishReason(response);
          const pcm=samples.extractPcm(response);
          entry.raw_pcm_sha256=hash(pcm);
          entry.source_audio_mime=response.candidates[0].content.parts.find(p=>p.inlineData).inlineData.mimeType;
          if(typeof response.modelVersion==='string' && /^gemini-[A-Za-z0-9._-]{1,120}$/.test(response.modelVersion))entry.returned_model_version=response.modelVersion;
          const master=samples.makeWave(pcm,24000),masterFile=fileName(entry,'master');
          fs.writeFileSync(path.join(o.output,masterFile),master,{flag:'wx',mode:0o644});
          entry.master={file:masterFile,...samples.inspectWave(master,24000)};fixed.metrics(master,24000,wanted);
          const phoneFile=fileName(entry,'telephony');convert(path.join(o.output,masterFile),path.join(o.output,phoneFile));
          entry.telephony={file:phoneFile,...fixed.metrics(fixed.regularBytes(path.join(o.output,phoneFile)),8000,wanted)};
          check(Math.abs(entry.master.duration_seconds-entry.telephony.duration_seconds)<=1/8000,'RESAMPLING_CHANGED_DURATION');
          entry.generation_status='GENERATED_QA_PASSED';entry.completed_at=new Date().toISOString();verifyEntry(o.output,entry);
          output({locale:entry.locale,id:entry.id,qa:'PASSED',requests_reserved:m.requests_reserved,
            duration_seconds:entry.telephony.duration_seconds,sha256:entry.telephony.sha256});
        } catch(e) {
          entry.generation_status='FAILED';entry.failure_code=safeCode(e);
          // This isolated malformed/incomplete audio response consumed only its
          // reservation. Continue unrelated queued identities, never retry it.
          // HTTP/auth/rate/transport, other QA, and ledger failures still stop.
          if(entry.failure_code==='AUDIO_GENERATION_NOT_COMPLETE')incomplete=entry.failure_code;
          else stopped=entry.failure_code;
        }
        save(o.output,m);
      }
    }
    // Join every worker before releasing the ledger lock, including I/O failures.
    const results=await Promise.allSettled(Array.from({length:o.concurrency},()=>worker().catch(e=>{stopped=safeCode(e);throw e;})));
    if(results.some(r=>r.status==='rejected'))throw new SampleError(stopped);
    summarize(m);m.generation_status=stopped?'STOPPED_ON_FAILURE':(m.supplemental_set_complete?'QA_PASSED':'INCOMPLETE');
    if(stopped || incomplete)m.failure_code=stopped||incomplete;save(o.output,m);
    if(stopped)throw new SampleError(stopped);
    check(m.supplemental_set_complete,'INCOMPLETE_PACK_REQUIRES_SEPARATE_RETRY_AUTHORIZATION');return m;
  } finally {key=undefined;if(lock!==undefined){fs.closeSync(lock);fs.unlinkSync(lockPath);}}
}
function verifyPack(directory) {
  const m=readManifest(directory);summarize(m);check(m.supplemental_set_complete,'SUPPLEMENTAL_PACK_INCOMPLETE');
  return {supplemental_set_complete:true,prompts:PROMPTS.length,auxiliary:15,telephone_digits:30,requests_reserved:m.requests_reserved,
    provider:m.provider,model:MODEL,voice:VOICE,runtime_ready:false,deployed:false,full_position_numeric_range_ready:false};
}
async function main(argv) {
  const o=options(argv);
  if(o.generate)await generate(o);
  else if(o['verify-only'])console.log(JSON.stringify(verifyPack(o.output)));
  else console.log(JSON.stringify({mode:'PLAN_ONLY_NO_API_CALLS',prompts:plan(),new_request_budget:REQUEST_BUDGET,
    automatic_retries:0,maximum_concurrency:2,runtime_ready:false,deployed:false}));
}
module.exports={OWNER,REQUEST_BUDGET,RETRY_BUDGET,MAX_REQUEST_BUDGET,CATALOG_HASH,PROMPTS,plan,requestBody,options,readManifest,verifyEntry,verifyPack,generate,main};
if(require.main===module)main(process.argv.slice(2)).catch(e=>{
  console.error(`Gemini supplemental pack stopped: ${safeCode(e)}. No live media was imported.`);process.exitCode=1;
});
