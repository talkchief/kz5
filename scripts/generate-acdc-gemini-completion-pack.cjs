#!/usr/bin/env node
'use strict';

// Separately authorized: 20 AR/HE callback digits + at most five failed-request
// retries. Together with the original 140-attempt pack this cannot exceed 165.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const fixed = require('./generate-acdc-gemini-fixed-pack.cjs');
const samples = require('./generate-acdc-gemini-samples.cjs');
const {SampleError, MODEL, VOICE} = samples;
const OWNER = 'kazoo5-acdc-gemini-completion-pack';
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const check = (ok, code) => { if (!ok) throw new SampleError(code); };
const safeCode = error => error instanceof SampleError ? error.code : 'LOCAL_OPERATION_FAILED';
const identity = p => `${p.locale}/${p.id}`;
const DIGITS = ['ar-sa', 'he-il'].flatMap(locale => Array.from({length: 10}, (_, digit) => ({
  locale, id: `acdc-number-${digit}`, transcript: String(digit),
  language: locale === 'ar-sa' ? 'Modern Standard Arabic' : 'Israeli Hebrew',
  maximum_duration_seconds: 5, kind: 'callback-digit'
})));
function expectedEntry(entry) { return [...fixed.FIXED, ...DIGITS].find(p => identity(p) === identity(entry)); }
function requestBody(entry) {
  if (entry.kind !== 'callback-digit') return fixed.requestBody(entry);
  const wanted = DIGITS.find(p => identity(p) === identity(entry));
  check(wanted && entry.transcript === wanted.transcript, 'UNAPPROVED_DIGIT');
  return {contents: [{parts: [{text:
    `Read only the single digit below in native ${wanted.language}, as part of a telephone number. ` +
    'Use a professional, warm, natural adult female call-center voice. ' +
    'Speak the digit clearly at a comfortable conversational pace, without a robotic cadence. ' +
    'Do not add an introduction, explanations, music or sound effects. Do not speak English.\n\n' +
    `Digit: ${wanted.transcript}`}]}], generationConfig: {responseModalities: ['AUDIO'],
      speechConfig: {voiceConfig: {prebuiltVoiceConfig: {voiceName: VOICE}}}}};
}
function entryPath(entry, variant, attempt) {
  return `${entry.locale}/${entry.id}.attempt-${attempt}.${variant === 'master' ? 'master-24000' : 'telephony-8000'}.wav`;
}
function verifyEntry(directory, entry) {
  const wanted = expectedEntry(entry);
  check(wanted && entry.transcript === wanted.transcript && entry.transcript_sha256 === hash(wanted.transcript), 'EXTRA_CATALOG_CHANGED');
  check(entry.provider === 'google-gemini' && entry.model === MODEL && entry.voice === VOICE &&
    entry.generation_status === 'GENERATED_QA_PASSED', 'EXTRA_VOICE_PROVENANCE_MISMATCH');
  check(Array.isArray(entry.attempts) && entry.attempts.length >= 1 && entry.attempts.length <= 6, 'INVALID_ATTEMPT_HISTORY');
  for (const variant of ['master', 'telephony']) {
    const saved = entry[variant];
    check(saved && saved.file === entryPath(entry, variant, entry.attempts.length), 'UNEXPECTED_EXTRA_AUDIO_PATH');
    const actual = fixed.metrics(fixed.regularBytes(path.join(directory, saved.file)), variant === 'master' ? 24000 : 8000, wanted);
    check(actual.sha256 === saved.sha256 && actual.duration_seconds === saved.duration_seconds, 'EXTRA_AUDIO_HASH_OR_METRICS_MISMATCH');
  }
  check(Math.abs(entry.master.duration_seconds - entry.telephony.duration_seconds) <= 1 / 8000, 'RESAMPLING_CHANGED_DURATION');
  check(/^[a-f0-9]{64}$/.test(entry.request_body_sha256) && /^[a-f0-9]{64}$/.test(entry.raw_pcm_sha256), 'INCOMPLETE_PROVENANCE');
  return entry;
}
function readManifest(directory) {
  fixed.directoryTarget(directory, true);
  const manifest = JSON.parse(fixed.regularBytes(path.join(directory, 'manifest.json')));
  check(manifest.owner === OWNER && manifest.model === MODEL && manifest.voice === VOICE &&
    manifest.initial_digit_budget === 20 && manifest.retry_budget === 5, 'UNOWNED_COMPLETION_PACK');
  check(Array.isArray(manifest.prompts) && new Set(manifest.prompts.map(identity)).size === manifest.prompts.length, 'DUPLICATE_COMPLETION_ENTRY');
  const attempts = manifest.prompts.flatMap(p => p.attempts);
  check(attempts.every(p => ['initial_digit', 'retry'].includes(p.kind)), 'INVALID_ATTEMPT_KIND');
  check(attempts.filter(p => p.kind === 'initial_digit').length === manifest.initial_digit_requests &&
    manifest.initial_digit_requests <= 20 && attempts.filter(p => p.kind === 'retry').length === manifest.retry_requests &&
    manifest.retry_requests <= 5, 'COMPLETION_BUDGET_ACCOUNTING_MISMATCH');
  for (const entry of manifest.prompts) {
    check(expectedEntry(entry) && entry.transcript === expectedEntry(entry).transcript, 'UNEXPECTED_COMPLETION_ENTRY');
    if (entry.generation_status === 'GENERATED_QA_PASSED') verifyEntry(directory, entry);
  }
  return manifest;
}
function retryable(code) {
  return !/^GEMINI_HTTP_4\d\d$/.test(code) || code === 'GEMINI_HTTP_429';
}
function write(directory, manifest) {
  manifest.updated_at = new Date().toISOString();
  manifest.digits_complete = DIGITS.every(p => manifest.prompts.some(e => identity(e) === identity(p) && e.generation_status === 'GENERATED_QA_PASSED'));
  manifest.complete = false; manifest.runtime_ready = false; manifest.deployed = false;
  fixed.manifestWrite(directory, manifest);
}
async function generate(o, deps = {}) {
  check(o.generate === true, 'GENERATION_NOT_EXPLICITLY_ENABLED');
  fixed.directoryTarget(o.output, !!o.resume);
  const source = fixed.readManifest(o.fixedPack);
  check(!['IN_PROGRESS'].includes(source.generation_status), 'WAIT_FOR_FIXED_GENERATOR_TO_FINISH');
  if (!o.resume) {
    fs.mkdirSync(o.output, {mode: 0o755});
    for (const locale of samples.LOCALES) fs.mkdirSync(path.join(o.output, locale), {mode: 0o755});
  }
  const lockPath = path.join(o.output, '.generation.lock'); let lock;
  try { lock = fs.openSync(lockPath, fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_NOFOLLOW, 0o600); }
  catch (_) { throw new SampleError('GENERATION_LOCKED'); }
  let key;
  try {
    const manifest = o.resume ? readManifest(o.output) : {schema_version: 1, owner: OWNER,
      provider: 'google-gemini', model: MODEL, preview_model: true, voice: VOICE,
      scope: 'callback-digits-and-failed-fixed-retries', initial_digit_budget: 20, retry_budget: 5,
      initial_digit_requests: 0, retry_requests: 0, fixed_pack_initial_budget: 140, combined_new_request_ceiling: 165,
      audio_listening_review: false, native_speaker_review: false, full_position_numeric_range_ready: false,
      conversion: {tool: 'sox', version: (deps.conversionVersion || fixed.conversionVersion)(), transformations: 'resampling only; no speedup or normalization'},
      generation_status: 'IN_PROGRESS', created_at: new Date().toISOString(), prompts: []};
    const failed = source.prompts.filter(p => p.generation_status === 'FAILED');
    const entries = [...failed.map(p => ({...expectedEntry(p), source: 'fixed_retry',
      original_failure_code: p.failure_code, original_fixed_manifest: path.relative(path.join(__dirname, '..'), path.join(o.fixedPack, 'manifest.json'))})),
      ...DIGITS.map(p => ({...p, source: 'new_digit'}))];
    for (const entry of entries) if (!manifest.prompts.some(p => identity(p) === identity(entry))) {
      manifest.prompts.push({...entry, provider: 'google-gemini', model: MODEL, voice: VOICE,
        transcript_sha256: hash(entry.transcript), generation_status: 'PENDING', attempts: []});
    }
    write(o.output, manifest);
    const pending = manifest.prompts.filter(p => p.generation_status !== 'GENERATED_QA_PASSED');
    if (!pending.length) return manifest;
    key = (deps.readProtectedKey || samples.readProtectedKey)(o.keyFile);
    const ask = deps.requestSpeech || samples.requestSpeech, convert = deps.resample || fixed.resample;
    const wait = deps.backoff || (ms => new Promise(resolve => setTimeout(resolve, ms)));
    const output = deps.output || (p => console.log(JSON.stringify(p)));
    manifest.generation_status = 'IN_PROGRESS';
    for (const entry of pending) {
      check(entry.attempts.every(p => !p.failure_code || retryable(p.failure_code)) &&
        (!entry.original_failure_code || retryable(entry.original_failure_code)), 'NONRETRYABLE_PROVIDER_FAILURE');
      while (entry.generation_status !== 'GENERATED_QA_PASSED') {
        const initial = entry.source === 'new_digit' && entry.attempts.length === 0;
        check(initial ? manifest.initial_digit_requests < 20 : manifest.retry_requests < 5, 'COMPLETION_RETRY_BUDGET_EXHAUSTED');
        const attempt = {kind: initial ? 'initial_digit' : 'retry', status: 'RESERVED', reserved_at: new Date().toISOString()};
        entry.attempts.push(attempt);
        if (initial) manifest.initial_digit_requests++; else manifest.retry_requests++;
        entry.generation_status = 'REQUESTING'; write(o.output, manifest);
        if (!initial) await wait(Math.min(8000, 1000 * 2 ** (entry.attempts.length - 1)));
        try {
          const body = requestBody(entry);
          attempt.request_body_sha256 = hash(JSON.stringify(body));
          attempt.synthesis_instruction = body.contents[0].parts[0].text;
          write(o.output, manifest);
          const response = await ask(body, key), pcm = samples.extractPcm(response);
          entry.synthesis_instruction = body.contents[0].parts[0].text;
          entry.request_body_sha256 = attempt.request_body_sha256; entry.raw_pcm_sha256 = hash(pcm);
          attempt.raw_pcm_sha256 = entry.raw_pcm_sha256;
          entry.source_audio_mime = response.candidates[0].content.parts.find(p => p.inlineData).inlineData.mimeType;
          if (typeof response.modelVersion === 'string' && /^gemini-[A-Za-z0-9._-]{1,120}$/.test(response.modelVersion)) entry.returned_model_version = response.modelVersion;
          const master = samples.makeWave(pcm, 24000), masterFile = entryPath(entry, 'master', entry.attempts.length);
          fs.writeFileSync(path.join(o.output, masterFile), master, {flag: 'wx', mode: 0o644});
          entry.master = {file: masterFile, ...samples.inspectWave(master, 24000)};
          attempt.master = entry.master;
          fixed.metrics(master, 24000, entry);
          const phoneFile = entryPath(entry, 'telephony', entry.attempts.length);
          convert(path.join(o.output, masterFile), path.join(o.output, phoneFile));
          entry.telephony = {file: phoneFile, ...fixed.metrics(fixed.regularBytes(path.join(o.output, phoneFile)), 8000, entry)};
          attempt.telephony = entry.telephony;
          check(Math.abs(entry.master.duration_seconds - entry.telephony.duration_seconds) <= 1 / 8000, 'RESAMPLING_CHANGED_DURATION');
          entry.generation_status = 'GENERATED_QA_PASSED'; attempt.status = 'PASSED';
          entry.completed_at = new Date().toISOString();
          output({locale: entry.locale, id: entry.id, qa: 'PASSED', duration_seconds: entry.telephony.duration_seconds,
            extra_requests: manifest.initial_digit_requests + manifest.retry_requests, sha256: entry.telephony.sha256});
        } catch (error) {
          const code = safeCode(error); attempt.status = 'FAILED'; attempt.failure_code = code;
          entry.generation_status = 'FAILED'; write(o.output, manifest);
          if (!retryable(code)) throw new SampleError(code);
        }
        write(o.output, manifest);
      }
    }
    manifest.generation_status = 'QA_PASSED'; write(o.output, manifest); return manifest;
  } finally { key = undefined; if (lock !== undefined) { fs.closeSync(lock); fs.unlinkSync(lockPath); } }
}
function verifiedAssets(fixedDirectory, extraDirectory) {
  const source = fixed.readManifest(fixedDirectory), extra = readManifest(extraDirectory);
  const assets = [...fixed.FIXED, ...DIGITS].map(wanted => {
    const original = source.prompts.find(p => identity(p) === identity(wanted) && p.generation_status === 'GENERATED_QA_PASSED');
    if (original) return {entry: fixed.verifyEntry(fixedDirectory, original), directory: fixedDirectory};
    const recovered = extra.prompts.find(p => identity(p) === identity(wanted) && p.generation_status === 'GENERATED_QA_PASSED');
    check(recovered, 'RELEASE_FIXED_OR_DIGIT_AUDIO_MISSING');
    return {entry: verifyEntry(extraDirectory, recovered), directory: extraDirectory};
  });
  check(source.requests_reserved + extra.initial_digit_requests + extra.retry_requests <= 165, 'COMBINED_REQUEST_CEILING_EXCEEDED');
  return assets;
}
function options(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    if (['--generate', '--resume', '--verify-only'].includes(argv[i])) out[argv[i].slice(2)] = true;
    else { const key = {'--output': 'output', '--fixed-pack': 'fixedPack', '--key-file': 'keyFile'}[argv[i]];
      check(key && i + 1 < argv.length && !argv[i + 1].startsWith('--'), 'UNKNOWN_OR_INCOMPLETE_OPTION'); out[key] = argv[++i]; }
  }
  check(out.output && path.isAbsolute(out.output) && out.fixedPack && path.isAbsolute(out.fixedPack), 'ABSOLUTE_PACK_PATHS_REQUIRED');
  check(!(out.generate && out['verify-only']) && (!out.resume || out.generate), 'CONFLICTING_MODES');
  if (out.generate) check(out.keyFile && path.isAbsolute(out.keyFile), 'ABSOLUTE_KEY_PATH_REQUIRED');
  return out;
}
async function main(argv) {
  const o = options(argv);
  if (o.generate) await generate(o);
  else if (o['verify-only']) console.log(JSON.stringify({fixed_and_digit_assets: verifiedAssets(o.fixedPack, o.output).length,
    callback_digits_complete: true, full_position_range_ready: false, runtime_ready: false, deployed: false}));
  else console.log(JSON.stringify({mode: 'PLAN_ONLY_NO_API_CALLS', digits: 20, maximum_retries: 5, combined_request_ceiling: 165}));
}
module.exports = {OWNER, DIGITS, requestBody, readManifest, verifyEntry, verifiedAssets, retryable, generate, main};
if (require.main === module) main(process.argv.slice(2)).catch(error => {
  console.error(`Gemini completion pack stopped: ${safeCode(error)}. No live media was imported.`); process.exitCode = 1;
});
