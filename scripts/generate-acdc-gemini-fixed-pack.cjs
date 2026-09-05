#!/usr/bin/env node
'use strict';

// Fixed catalog only. No caller text, numeric bulk synthesis or live import.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const cp = require('node:child_process');
const samples = require('./generate-acdc-gemini-samples.cjs');
const {catalog} = require('./acdc-language-catalog.cjs');
const {SampleError, MODEL, VOICE, ENDPOINT, LOCALES} = samples;
const OWNER = 'kazoo5-acdc-gemini-fixed-pack';
const REQUEST_BUDGET = 140;
const LANGUAGES = {'en-us': 'American English', 'he-il': 'Israeli Hebrew',
  'ar-sa': 'Modern Standard Arabic', 'fr-fr': 'French from France', 'es-es': 'Spanish from Spain'};
const hash = data => crypto.createHash('sha256').update(data).digest('hex');
const check = (condition, code) => { if (!condition) throw new SampleError(code); };
const safeCode = error => error instanceof SampleError ? error.code : 'LOCAL_OPERATION_FAILED';
const keyOf = entry => `${entry.locale}/${entry.id}`;

function plan() {
  return LOCALES.flatMap(locale => catalog(locale).prompts.filter(p => p.kind === 'fixed').map(p => ({
    locale, id: p.id, transcript: p.text, language: LANGUAGES[locale],
    maximum_duration_seconds: p.id === 'acdc-callback-success' ? 10 : 20
  })));
}
const FIXED = plan();
const CATALOG_HASH = hash(JSON.stringify(FIXED));
function requestBody(entry) {
  const expected = FIXED.find(p => keyOf(p) === keyOf(entry));
  check(expected && expected.transcript === entry.transcript, 'UNAPPROVED_FIXED_TEXT');
  check(!entry.transcript.includes('[['), 'PHONEME_INPUT_FORBIDDEN');
  return {contents: [{parts: [{text:
    `Read the transcript below verbatim in native ${expected.language}. ` +
    'Use a professional, warm, natural adult female call-center voice. ' +
    'Speak clearly at a comfortable conversational pace, without a robotic cadence. ' +
    'Only speak the transcript: no introduction, added words, music, or sound effects. ' +
    `The complete message must fit within ${expected.maximum_duration_seconds} seconds; do not rush or omit any words.\n\n` +
    `Transcript:\n${expected.transcript}`}]}], generationConfig: {responseModalities: ['AUDIO'],
      speechConfig: {voiceConfig: {prebuiltVoiceConfig: {voiceName: VOICE}}}}};
}

function options(argv) {
  const result = {concurrency: 2, reuseSamples: path.join(__dirname, 'assets/acdc-gemini-samples-20260905')};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (['--generate', '--resume', '--verify-only', '--plan'].includes(arg)) {
      const key = {'--verify-only': 'verifyOnly'}[arg] || arg.slice(2);
      check(!result[key], 'DUPLICATE_OPTION'); result[key] = true;
    } else {
      const key = {'--key-file': 'keyFile', '--output': 'output', '--reuse-samples': 'reuseSamples', '--concurrency': 'concurrency'}[arg];
      check(key && i + 1 < argv.length && !argv[i + 1].startsWith('--'), 'UNKNOWN_OR_INCOMPLETE_OPTION');
      result[key] = argv[++i];
    }
  }
  result.concurrency = Number(result.concurrency);
  check([1, 2].includes(result.concurrency), 'CONCURRENCY_MUST_BE_ONE_OR_TWO');
  check(!(result.generate && (result.plan || result.verifyOnly)), 'CONFLICTING_MODES');
  check(!result.resume || result.generate, 'RESUME_REQUIRES_GENERATE');
  if (result.generate || result.verifyOnly) check(result.output && path.isAbsolute(result.output), 'ABSOLUTE_OUTPUT_REQUIRED');
  if (result.generate) check(result.keyFile && path.isAbsolute(result.keyFile), 'ABSOLUTE_KEY_PATH_REQUIRED');
  return result;
}

function regularBytes(file, maximum = 2 * 1024 * 1024) {
  let fd;
  try {
    check(fs.realpathSync(path.dirname(file)) === path.dirname(file), 'SYMLINK_PARENT_FORBIDDEN');
    const before = fs.lstatSync(file);
    check(before.isFile() && !before.isSymbolicLink() && before.size <= maximum, 'INVALID_OWNED_FILE');
    fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
    const opened = fs.fstatSync(fd);
    check(before.dev === opened.dev && before.ino === opened.ino && opened.isFile(), 'OWNED_FILE_CHANGED');
    return fs.readFileSync(fd);
  } finally { if (fd !== undefined) fs.closeSync(fd); }
}
function directoryTarget(directory, existing) {
  check(path.isAbsolute(directory) && path.resolve(directory) === directory &&
    directory.split('/').filter(Boolean).length >= 3, 'DEDICATED_OUTPUT_REQUIRED');
  const forbidden = ['/etc', '/var/www', '/usr/share', '/usr/local/freeswitch', '/opt/kazoo'];
  check(!forbidden.some(p => directory === p || directory.startsWith(p + '/')), 'LIVE_OUTPUT_FORBIDDEN');
  if (existing) {
    const stat = fs.lstatSync(directory);
    check(stat.isDirectory() && !stat.isSymbolicLink() && fs.realpathSync(directory) === directory, 'INVALID_OUTPUT_DIRECTORY');
  } else {
    samples.validateOutputTarget(directory);
  }
}
function metrics(wav, rate, entry) {
  const result = samples.inspectWave(wav, rate);
  check(result.duration_seconds >= 0.25 && result.duration_seconds <= entry.maximum_duration_seconds, 'AUDIO_DURATION_OUT_OF_BOUNDS');
  check(result.clipped_samples === 0, 'AUDIO_CLIPPED');
  check(result.rms > 100 && result.silence_fraction < 0.98, 'AUDIO_SILENT_OR_TOO_QUIET');
  return result;
}
function conversionVersion() {
  const run = cp.spawnSync('sox', ['--version'], {encoding: 'utf8', timeout: 10000, maxBuffer: 65536});
  const version = run.stdout && run.stdout.match(/SoX v([0-9][0-9.]*)/);
  check(!run.error && run.status === 0 && version, 'SOX_UNAVAILABLE');
  return version[1];
}
function resample(source, destination) {
  check(!fs.existsSync(destination), 'AUDIO_OUTPUT_ALREADY_EXISTS');
  const run = cp.spawnSync('sox', [source, '-r', '8000', '-c', '1', '-b', '16', '-e', 'signed-integer', destination,
    'rate', '-v', '8000'], {encoding: 'utf8', timeout: 30000, maxBuffer: 65536});
  check(!run.error && run.status === 0, 'SOX_RESAMPLE_FAILED');
  check(!/clip/i.test(run.stderr || ''), 'SOX_REPORTED_CLIPPING');
  fs.chmodSync(destination, 0o644);
}
function fileName(entry, variant) {
  return `${entry.locale}/${entry.id}.${variant === 'master' ? 'master-24000' : 'telephony-8000'}.wav`;
}
function verifyEntry(directory, entry) {
  const expected = FIXED.find(p => keyOf(p) === keyOf(entry));
  check(expected && entry.transcript === expected.transcript && entry.transcript_sha256 === hash(expected.transcript), 'CATALOG_OR_TRANSCRIPT_CHANGED');
  check(entry.provider === 'google-gemini' && entry.model === MODEL && entry.voice === VOICE, 'VOICE_PROVENANCE_MISMATCH');
  check(entry.generation_status === 'GENERATED_QA_PASSED', 'FIXED_AUDIO_NOT_VALIDATED');
  for (const variant of ['master', 'telephony']) {
    const saved = entry[variant];
    check(saved && saved.file === fileName(entry, variant), 'UNEXPECTED_AUDIO_PATH');
    const audio = regularBytes(path.join(directory, saved.file));
    const actual = metrics(audio, variant === 'master' ? 24000 : 8000, expected);
    check(actual.sha256 === saved.sha256, 'AUDIO_HASH_MISMATCH');
    check(actual.duration_seconds === saved.duration_seconds, 'AUDIO_METRICS_MISMATCH');
  }
  check(Math.abs(entry.master.duration_seconds - entry.telephony.duration_seconds) <= 1 / 8000, 'RESAMPLING_CHANGED_DURATION');
  check(/^[a-f0-9]{64}$/.test(entry.request_body_sha256) && /^[a-f0-9]{64}$/.test(entry.raw_pcm_sha256), 'INCOMPLETE_PROVENANCE');
  return entry;
}
function manifestWrite(directory, manifest) {
  const temporary = path.join(directory, `.manifest-${crypto.randomBytes(8).toString('hex')}.tmp`);
  const fd = fs.openSync(temporary, fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_NOFOLLOW, 0o644);
  try { fs.writeFileSync(fd, JSON.stringify(manifest, null, 2) + '\n'); fs.fsyncSync(fd); }
  finally { fs.closeSync(fd); }
  fs.renameSync(temporary, path.join(directory, 'manifest.json'));
}
function readManifest(directory) {
  const manifest = JSON.parse(regularBytes(path.join(directory, 'manifest.json')).toString('utf8'));
  check(manifest.owner === OWNER && manifest.catalog_sha256 === CATALOG_HASH && manifest.voice === VOICE &&
    manifest.provider === 'google-gemini' && manifest.model === MODEL, 'UNOWNED_OR_CHANGED_PACK');
  check(manifest.synthesis_requests_maximum === REQUEST_BUDGET && Number.isInteger(manifest.requests_reserved) &&
    manifest.requests_reserved >= 0 && manifest.requests_reserved <= REQUEST_BUDGET, 'INVALID_REQUEST_ACCOUNTING');
  check(Array.isArray(manifest.prompts) && manifest.prompts.length <= FIXED.length &&
    new Set(manifest.prompts.map(keyOf)).size === manifest.prompts.length, 'INVALID_PROMPT_INVENTORY');
  for (const entry of manifest.prompts) {
    check(FIXED.some(p => keyOf(p) === keyOf(entry) && p.transcript === entry.transcript), 'UNEXPECTED_PROMPT_ENTRY');
    if (entry.generation_status === 'GENERATED_QA_PASSED') verifyEntry(directory, entry);
  }
  const requested = manifest.prompts.filter(p => p.source === 'new_request').length;
  check(requested === manifest.requests_reserved, 'REQUEST_ACCOUNTING_MISMATCH');
  return manifest;
}
function summarize(manifest) {
  manifest.fixed_set_complete = FIXED.every(p => manifest.prompts.some(e => keyOf(e) === keyOf(p) && e.generation_status === 'GENERATED_QA_PASSED'));
  manifest.complete = false; manifest.runtime_ready = false; manifest.deployed = false;
  manifest.locales = LOCALES.map(locale => ({locale,
    fixed_required: 29, fixed_validated: manifest.prompts.filter(e => e.locale === locale && e.generation_status === 'GENERATED_QA_PASSED').length,
    numeric_required: ['ar-sa', 'he-il'].includes(locale) ? 2999 : 0,
    numeric_generated: 0, runtime_ready: false, native_speaker_review: false}));
  manifest.updated_at = new Date().toISOString();
}
function createPack(directory, previewDirectory, version) {
  const sourceBytes = regularBytes(path.join(previewDirectory, 'manifest.json'));
  const source = JSON.parse(sourceBytes.toString('utf8'));
  check(source.owner === 'kazoo5-acdc-gemini-samples' && source.provider === 'google-gemini' &&
    source.model === MODEL && source.voice === VOICE && source.sample_set_complete === true, 'INVALID_PREVIEW_PROVENANCE');
  check(fs.realpathSync(previewDirectory) === previewDirectory, 'INVALID_PREVIEW_DIRECTORY');
  const reusable = LOCALES.map(locale => {
    const expected = FIXED.find(p => p.locale === locale && p.id === 'acdc-callback-success');
    const prior = source.samples.filter(p => p.locale === locale && p.id === expected.id);
    check(prior.length === 1, 'REQUIRE_FIVE_MATCHING_PREVIEWS');
    return verifyEntry(previewDirectory, {...prior[0], maximum_duration_seconds: 10});
  });
  fs.mkdirSync(directory, {mode: 0o755});
  const manifest = {schema_version: 1, owner: OWNER, scope: 'fixed-only', provider: 'google-gemini', model: MODEL,
    preview_model: true, voice: VOICE, voice_style: 'warm adult female', catalog_sha256: CATALOG_HASH,
    source_catalog: 'scripts/acdc-language-catalog.cjs', api_endpoint: ENDPOINT,
    generation_and_test_deployment_authorized: true, audio_listening_review: false, native_speaker_review: false,
    numeric_generation_authorized: false, synthesis_requests_maximum: REQUEST_BUDGET, requests_reserved: 0,
    attempts_per_prompt: 1, automatic_retries: 0, created_at: new Date().toISOString(),
    generation_status: 'IN_PROGRESS', conversion: {tool: 'sox', version,
      transformations: '24kHz to 8kHz resampling only; no speedup, trimming, gain or normalization'}, prompts: []};
  for (const locale of LOCALES) fs.mkdirSync(path.join(directory, locale), {mode: 0o755});
  for (const prior of reusable) {
    const entry = {...prior, source: 'reused_preview', maximum_duration_seconds: 10,
      reused_manifest_sha256: hash(sourceBytes),
      reused_manifest: path.relative(path.join(__dirname, '..'), path.join(previewDirectory, 'manifest.json'))};
    delete entry.status;
    for (const variant of ['master', 'telephony']) {
      fs.copyFileSync(path.join(previewDirectory, entry[variant].file), path.join(directory, entry[variant].file), fs.constants.COPYFILE_EXCL);
      fs.chmodSync(path.join(directory, entry[variant].file), 0o644);
    }
    manifest.prompts.push(entry);
  }
  summarize(manifest); manifestWrite(directory, manifest);
  return manifest;
}

async function generatePack(o, dependencies = {}) {
  check(o.generate === true, 'GENERATION_NOT_EXPLICITLY_ENABLED');
  check([1, 2].includes(o.concurrency), 'CONCURRENCY_MUST_BE_ONE_OR_TWO');
  directoryTarget(o.output, !!o.resume);
  const version = (dependencies.conversionVersion || conversionVersion)();
  const initial = o.resume ? undefined : createPack(o.output, o.reuseSamples, version);
  const lock = path.join(o.output, '.generation.lock');
  let lockFd;
  try { lockFd = fs.openSync(lock, fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_NOFOLLOW, 0o600); }
  catch (_) { throw new SampleError('GENERATION_LOCKED'); }
  let key, stopped, next = 0;
  try {
    // Read the reservation ledger only after taking the lock; a snapshot read
    // before locking could miss a just-completed concurrent generator request.
    const manifest = o.resume ? readManifest(o.output) : initial;
    const pending = FIXED.filter(p => !manifest.prompts.some(e => keyOf(e) === keyOf(p)));
    if (!pending.length) {
      summarize(manifest);
      check(manifest.fixed_set_complete, 'INCOMPLETE_PACK_REQUIRES_SEPARATE_RETRY_AUTHORIZATION');
      return manifest; // A complete resume reads neither credentials nor provider.
    }
    check(manifest.requests_reserved + pending.length <= REQUEST_BUDGET, 'REQUEST_BUDGET_EXHAUSTED');
    for (const locale of LOCALES) {
      const directory = path.join(o.output, locale);
      check(fs.realpathSync(directory) === directory && fs.lstatSync(directory).isDirectory(), 'INVALID_LOCALE_DIRECTORY');
    }
    key = (dependencies.readProtectedKey || samples.readProtectedKey)(o.keyFile);
    const ask = dependencies.requestSpeech || samples.requestSpeech;
    const convert = dependencies.resample || resample;
    const output = dependencies.output || (p => console.log(JSON.stringify(p)));
    manifest.generation_status = 'IN_PROGRESS'; delete manifest.failure_code;
    async function worker() {
      while (!stopped && next < pending.length) {
        const expected = pending[next++], body = requestBody(expected);
        const entry = {...expected, source: 'new_request', provider: 'google-gemini', model: MODEL, voice: VOICE,
          generation_status: 'REQUESTING', transcript_sha256: hash(expected.transcript),
          synthesis_instruction: body.contents[0].parts[0].text, request_body_sha256: hash(JSON.stringify(body))};
        manifest.prompts.push(entry); manifest.requests_reserved++;
        manifestWrite(o.output, manifest); // Reserve the paid request before transport.
        try {
          const response = await ask(body, key), pcm = samples.extractPcm(response);
          entry.source_audio_mime = response.candidates[0].content.parts.find(p => p.inlineData).inlineData.mimeType;
          entry.raw_pcm_sha256 = hash(pcm);
          if (typeof response.modelVersion === 'string' && /^gemini-[A-Za-z0-9._-]{1,120}$/.test(response.modelVersion)) entry.returned_model_version = response.modelVersion;
          const master = samples.makeWave(pcm, 24000), masterFile = fileName(entry, 'master');
          fs.writeFileSync(path.join(o.output, masterFile), master, {flag: 'wx', mode: 0o644});
          entry.master = {file: masterFile, ...samples.inspectWave(master, 24000)};
          metrics(master, 24000, expected);
          const deliveryFile = fileName(entry, 'telephony');
          convert(path.join(o.output, masterFile), path.join(o.output, deliveryFile));
          entry.telephony = {file: deliveryFile, ...metrics(regularBytes(path.join(o.output, deliveryFile)), 8000, expected)};
          check(Math.abs(entry.master.duration_seconds - entry.telephony.duration_seconds) <= 1 / 8000, 'RESAMPLING_CHANGED_DURATION');
          entry.generation_status = 'GENERATED_QA_PASSED'; entry.completed_at = new Date().toISOString();
          output({locale: entry.locale, id: entry.id, qa: 'PASSED', requests_reserved: manifest.requests_reserved,
            duration_seconds: entry.telephony.duration_seconds, sha256: entry.telephony.sha256});
        } catch (error) {
          entry.generation_status = 'FAILED'; entry.failure_code = safeCode(error); stopped = entry.failure_code;
        }
        summarize(manifest); manifestWrite(o.output, manifest);
      }
    }
    // Do not release the lock while another worker still has a paid request in
    // flight, even if a local ledger write failed outside its transport catch.
    const results = await Promise.allSettled(Array.from({length: o.concurrency}, () => worker().catch(error => {
      stopped = safeCode(error); throw error;
    })));
    if (results.some(result => result.status === 'rejected')) throw new SampleError(stopped);
    summarize(manifest);
    manifest.generation_status = stopped ? 'STOPPED_ON_FAILURE' : (manifest.fixed_set_complete ? 'FIXED_QA_PASSED' : 'INCOMPLETE');
    if (stopped) manifest.failure_code = stopped;
    manifestWrite(o.output, manifest);
    if (stopped) throw new SampleError(stopped);
    check(manifest.fixed_set_complete, 'INCOMPLETE_PACK_REQUIRES_SEPARATE_RETRY_AUTHORIZATION');
    return manifest;
  } finally {
    key = undefined;
    if (lockFd !== undefined) { fs.closeSync(lockFd); fs.unlinkSync(lock); }
  }
}
function verifyPack(directory) {
  directoryTarget(directory, true);
  const manifest = readManifest(directory); summarize(manifest);
  check(manifest.fixed_set_complete, 'FIXED_PACK_INCOMPLETE');
  return {fixed_set_complete: true, fixed_prompts: 145, requests_reserved: manifest.requests_reserved,
    provider: manifest.provider, voice: manifest.voice, runtime_ready: false, deployed: false,
    numeric_missing: {'ar-sa': 2999, 'he-il': 2999}};
}
async function main(argv) {
  const o = options(argv);
  if (o.verifyOnly) console.log(JSON.stringify(verifyPack(o.output)));
  else if (o.generate) await generatePack(o);
  else console.log(JSON.stringify({mode: 'PLAN_ONLY_NO_API_CALLS', fixed_prompts: FIXED.length,
    reuse_success_previews: 5, new_request_budget: REQUEST_BUDGET, maximum_concurrency: 2,
    numeric_generation: false, runtime_ready: false}));
}
module.exports = {OWNER, REQUEST_BUDGET, FIXED, plan, requestBody, options, metrics, resample,
  verifyEntry, readManifest, generatePack, verifyPack, regularBytes, directoryTarget,
  manifestWrite, conversionVersion, main};
if (require.main === module) main(process.argv.slice(2)).catch(error => {
  console.error(`Gemini fixed pack stopped: ${safeCode(error)}. No live media was imported.`);
  process.exitCode = 1;
});
