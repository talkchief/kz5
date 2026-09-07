#!/usr/bin/env node
'use strict';
// Read-only authoring proposal, not a provider runner or runtime/import path.
const path = require('node:path'), crypto = require('node:crypto');
const pack = require('./acdc-cardinal-pack.cjs');
const MODEL = 'gemini-3.1-flash-tts-preview';
const LOCALES = Object.freeze(['he-il', 'ar-sa', 'es-es']);
const ALIASES = Object.freeze(['es-es/acdc-cardinal-v1-number-4', 'es-es/acdc-cardinal-v1-number-9']);
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const sha = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const absolute = value => typeof value === 'string' && path.isAbsolute(value) && path.resolve(value) === value;
class PlanError extends Error { constructor(code) { super(code); this.code = code; } }
const check = (ok, code) => {if (!ok) throw new PlanError(code);};
function validate(o) {
  check(o && typeof o === 'object' && !Array.isArray(o)
    && Object.keys(o).every(k => ['sourceDirectory','sourceManifestSha256','approvalSha256','trials','maxRequests'].includes(k)), 'INVALID_PLAN_OPTIONS');
  check(absolute(o.sourceDirectory) && sha(o.sourceManifestSha256) && sha(o.approvalSha256), 'PINNED_SOURCE_AND_APPROVAL_REQUIRED');
  check(Number.isInteger(o.maxRequests) && o.maxRequests >= 1 && o.maxRequests <= 12, 'REQUEST_LIMIT_ONE_TO_TWELVE');
  check(Array.isArray(o.trials) && o.trials.length >= 1 && o.trials.length <= 64
    && o.trials.every(t => t && typeof t === 'object' && !Array.isArray(t)
      && Object.keys(t).length === 2 && absolute(t.directory) && sha(t.sha256)), 'EXPLICIT_PINNED_PRIOR_TRIALS_REQUIRED');
  check(new Set(o.trials.map(t => t.directory)).size === o.trials.length
    && new Set(o.trials.map(t => t.sha256)).size === o.trials.length, 'DUPLICATE_PRIOR_TRIAL');
  return o;
}
function options(argv) {
  const o = {trials: [], maxRequests: 3}, seen = new Set();
  const flags = {'--source-pack':'sourceDirectory','--source-manifest-sha256':'sourceManifestSha256',
    '--approval-sha256':'approvalSha256','--max-requests':'maxRequests'};
  for (let i=0; i<argv.length; i++) {
    const arg=argv[i];
    if (arg === '--prior-trial') {
      check(absolute(argv[i+1]) && sha(argv[i+2]), 'EXPLICIT_PINNED_PRIOR_TRIALS_REQUIRED');
      o.trials.push({directory:argv[++i],sha256:argv[++i]}); continue;
    }
    check(!seen.has(arg), 'DUPLICATE_OPTION'); seen.add(arg);
    if (arg === '--plan') continue;
    check(Object.hasOwn(flags,arg) && typeof argv[i+1] === 'string' && !argv[i+1].startsWith('--'), 'INVALID_OPTION');
    const value=argv[++i];
    if (arg === '--max-requests') check(/^(?:[1-9]|1[0-2])$/.test(value), 'REQUEST_LIMIT_ONE_TO_TWELVE');
    o[flags[arg]]=arg === '--max-requests' ? Number(value) : value;
  }
  return validate(o);
}
function plan(input, deps = {}) {
  const o=validate(input);
  // No credential/provider/generator module is loaded. The shared read-only
  // resolver verifies complete source history, pinned trials and actual WAVs.
  const open=deps.openResolution || require('./acdc-cardinal-model-trial-assets.cjs').openResolution;
  const trials=[...o.trials].sort((a,b)=>a.sha256.localeCompare(b.sha256));
  const resolution=open({sourceDirectory:o.sourceDirectory,sourceManifestSha256:o.sourceManifestSha256,
    approvalSha256:o.approvalSha256,trials});
  const source=resolution.sourceManifest(), summary=resolution.summary();
  pack.requireAuthoringApproval(source,LOCALES,o.approvalSha256);
  const successes=new Set(), reserved=new Map();
  for (const t of summary.trials) for (const entry of t.outcomes) {
    check(['QA_PASSED','FAILED','SELECTED'].includes(entry.status), 'AMBIGUOUS_PRIOR_TRIAL_STATE');
    if (entry.status === 'SELECTED') continue;
    reserved.set(entry.identity,(reserved.get(entry.identity)||0)+1);
    if (entry.status === 'QA_PASSED') {
      check(!successes.has(entry.identity), 'DUPLICATE_SUCCESS_IDENTITY'); successes.add(entry.identity);
    }
  }
  const byIdentity=new Map(source.prompts.map(e=>[`${e.locale}/${e.id}`,e]));
  // Catalog order is stable even if the source JSON prompt array is reordered.
  const ordered=pack.createManifest().prompts.map(e=>byIdentity.get(`${e.locale}/${e.id}`));
  const exclusions=[], eligible=[];
  for (const entry of ordered) {
    const identity=`${entry.locale}/${entry.id}`;
    if (!LOCALES.includes(entry.locale) || entry.generation_status !== 'FAILED') continue;
    const prior=reserved.get(identity)||0, total=entry.attempts.length+prior;
    let reason=successes.has(identity) ? 'saved_model_trial_qa'
      : ALIASES.includes(identity) ? 'exact_supplemental_alias'
        : prior ? 'manual_diagnostic_required'
          : total >= pack.HARD_MAX_ATTEMPTS ? 'hard_attempt_cap' : null;
    if (reason) {exclusions.push({identity,reason,source_attempt_count:entry.attempts.length,
      prior_model_requests:prior,total_historical_requests:total});continue;}
    check(entry.attempts.length > 0 && entry.attempts.at(-1).status === 'FAILED', 'TARGET_NOT_FAILED');
    const body=pack.requestBody(entry,pack.CONCISE_SYNTHESIS_RECIPE);
    eligible.push({identity,transcript:entry.transcript,transcript_sha256:entry.transcript_sha256,
      source_entry_sha256:pack.digest(entry),source_attempts_sha256:pack.digest(entry.attempts),
      source_attempt_count:entry.attempts.length,prior_model_requests:prior,total_historical_requests:total,
      total_requests_if_generated:total+1,request_body_sha256:hash(JSON.stringify(body)),
      synthesis_recipe:pack.CONCISE_SYNTHESIS_RECIPE});
  }
  const selected=eligible.slice(0,o.maxRequests), batches=[];
  for(let i=0;i<selected.length;i+=3) batches.push({number:batches.length+1,identities:selected.slice(i,i+3).map(e=>e.identity)});
  // Recheck the shared resolver's source/trial pins after constructing output.
  resolution.sourceManifest();
  const result={owner:'kazoo5-acdc-cardinal-model-recovery-plan',mode:'PLAN_ONLY_NO_PROVIDER',
    model:MODEL,voice:pack.VOICE,source_manifest_sha256:o.sourceManifestSha256,approvals_sha256:o.approvalSha256,
    catalog_sha256:pack.CATALOG_HASH,prior_trials:trials.map(t=>({directory:t.directory,trial_manifest_sha256:t.sha256})),
    source_requests_reserved:source.requests_reserved,additional_prior_trial_requests:summary.additional_trial_requests,
    selection_scope:LOCALES,ordering:'catalog-order',request_limit:o.maxRequests,requests_proposed:selected.length,
    eligible_unrequested_count:eligible.length,remaining_after_plan:eligible.length-selected.length,
    selected,batches,exclusions,automatic_retries:0,source_history_reset:false,
    runtime_ready:false,importable:false,deployed:false,native_listening_approved:false,
    prior_trial_inventory_scope:'explicitly supplied pins only; caller must include every known prior trial'};
  return {...result,plan_sha256:pack.digest(result)};
}
function main(argv) {console.log(JSON.stringify(plan(options(argv))));}
module.exports=Object.freeze({MODEL,LOCALES,ALIASES,PlanError,options,plan,main});
if(require.main===module) {
  try {main(process.argv.slice(2));}
  catch (_) {console.error('Cardinal recovery plan rejected safely; no provider, key, write, import or runtime action was attempted.');process.exitCode=1;}
}
