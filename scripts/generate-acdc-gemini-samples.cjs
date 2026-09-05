#!/usr/bin/env node
'use strict';

// Deliberately a five-request SAMPLE workflow, not an installer or live importer.
// Generation is opt-in; the default plan never reads credentials or uses a network.
const fs = require('node:fs');
const path = require('node:path');
const https = require('node:https');
const crypto = require('node:crypto');
const cp = require('node:child_process');
const {definitions} = require('./acdc-language-catalog.cjs');

const MODEL = 'gemini-2.5-pro-preview-tts';
const VOICE = 'Sulafat';
const ORIGIN = 'https://generativelanguage.googleapis.com';
const ENDPOINT = `${ORIGIN}/v1beta/models/${MODEL}:generateContent`;
const LOCALES = ['en-us', 'he-il', 'ar-sa', 'fr-fr', 'es-es'];
const LANGUAGES = {
  'en-us': 'American English', 'he-il': 'Israeli Hebrew',
  'ar-sa': 'Modern Standard Arabic', 'fr-fr': 'French from France', 'es-es': 'Spanish from Spain'
};
const ID = 'acdc-callback-success';
const REQUEST_TIMEOUT_MS = 90000;
const MAX_RESPONSE_BYTES = 2 * 1024 * 1024;
const MAX_DURATION_SECONDS = 10;
const STATUS = 'SAMPLE_NOT_APPROVED_NOT_DEPLOYED';
const sha256 = data => crypto.createHash('sha256').update(data).digest('hex');

class SampleError extends Error {
  constructor(code) { super(code); this.name = 'SampleError'; this.code = code; }
}
function requireCondition(condition, code) { if (!condition) throw new SampleError(code); }
function safeCode(error) { return error instanceof SampleError ? error.code : 'LOCAL_OPERATION_FAILED'; }

function plan() {
  return LOCALES.map(locale => ({
    locale, id: ID, transcript: definitions[locale].callback[4],
    language: LANGUAGES[locale], provider: 'google-gemini', model: MODEL, voice: VOICE,
    status: STATUS
  }));
}

function requestBody(sample) {
  requireCondition(LOCALES.includes(sample.locale) && sample.id === ID &&
    sample.transcript === definitions[sample.locale].callback[4], 'UNAPPROVED_SAMPLE_TEXT');
  return {
    contents: [{parts: [{text:
      `Read the transcript below verbatim in native ${LANGUAGES[sample.locale]}. ` +
      'Use a professional, warm, natural adult female call-center voice. ' +
      'Speak clearly at a comfortable conversational pace, without a robotic cadence. ' +
      'Only speak the transcript: no introduction, added words, music, or sound effects. ' +
      'The complete message must fit within ten seconds; do not rush or omit any words.\n\n' +
      `Transcript:\n${sample.transcript}`}]}],
    generationConfig: {
      responseModalities: ['AUDIO'],
      speechConfig: {voiceConfig: {prebuiltVoiceConfig: {voiceName: VOICE}}}
    }
  };
}

function parseOptions(argv) {
  const out = {generate: false};
  let dry = false;
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    if (arg === '--generate') { requireCondition(!out.generate, 'DUPLICATE_OPTION'); out.generate = true; }
    else if (arg === '--dry-run' || arg === '--plan') dry = true;
    else if (arg === '--key-file' || arg === '--output') {
      const key = arg === '--key-file' ? 'keyFile' : 'output';
      requireCondition(!out[key] && index + 1 < argv.length && !argv[index + 1].startsWith('--'), 'INVALID_OPTION_VALUE');
      out[key] = argv[++index];
    } else throw new SampleError('UNKNOWN_OPTION');
  }
  requireCondition(!(dry && out.generate), 'CONFLICTING_MODES');
  if (out.generate) {
    requireCondition(out.keyFile && path.isAbsolute(out.keyFile), 'ABSOLUTE_KEY_PATH_REQUIRED');
    requireCondition(out.output && path.isAbsolute(out.output), 'ABSOLUTE_OUTPUT_PATH_REQUIRED');
  }
  return out;
}

function extractKey(text) {
  // Accommodate a key stored inside a small wrapper, but reject ambiguous files.
  const keys = [...new Set(text.match(/(?<![A-Za-z0-9_-])AIza[A-Za-z0-9_-]{20,}(?![A-Za-z0-9_-])/g) || [])];
  requireCondition(keys.length === 1, 'EXPECTED_ONE_GEMINI_KEY');
  return keys[0];
}

function readProtectedKey(file) {
  let fd;
  try {
    const before = fs.lstatSync(file);
    requireCondition(before.isFile() && !before.isSymbolicLink(), 'KEY_NOT_REGULAR_FILE');
    fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
    const stat = fs.fstatSync(fd);
    requireCondition(stat.isFile() && stat.dev === before.dev && stat.ino === before.ino, 'KEY_FILE_CHANGED');
    requireCondition(typeof process.getuid === 'function' && stat.uid === process.getuid(), 'KEY_OWNER_MISMATCH');
    requireCondition((stat.mode & 0o077) === 0, 'KEY_PERMISSIONS_TOO_OPEN');
    requireCondition(stat.size > 0 && stat.size <= 65536, 'KEY_FILE_SIZE_INVALID');
    return extractKey(fs.readFileSync(fd, 'utf8'));
  } catch (error) {
    throw error instanceof SampleError ? error : new SampleError('KEY_FILE_UNAVAILABLE');
  } finally { if (fd !== undefined) fs.closeSync(fd); }
}

function validateOutputTarget(directory) {
  requireCondition(path.isAbsolute(directory) && path.resolve(directory) === directory &&
    directory.split('/').filter(Boolean).length >= 2, 'DEDICATED_OUTPUT_REQUIRED');
  const denied = ['/etc', '/var/www', '/usr/share', '/usr/local/freeswitch', '/opt/kazoo'];
  requireCondition(!denied.some(prefix => directory === prefix || directory.startsWith(prefix + '/')), 'LIVE_OUTPUT_FORBIDDEN');
  try { fs.lstatSync(directory); throw new SampleError('OUTPUT_ALREADY_EXISTS'); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  const parent = path.dirname(directory);
  requireCondition(fs.statSync(parent).isDirectory() && fs.realpathSync(parent) === parent, 'OUTPUT_PARENT_NOT_REAL_DIRECTORY');
}

function extractPcm(response) {
  requireCondition(response && Array.isArray(response.candidates) && response.candidates.length > 0, 'NO_AUDIO_CANDIDATE');
  const candidate = response.candidates[0];
  requireCondition(candidate.finishReason === 'STOP', 'AUDIO_GENERATION_NOT_COMPLETE');
  const parts = candidate.content && candidate.content.parts;
  requireCondition(Array.isArray(parts), 'NO_AUDIO_PARTS');
  const audio = parts.filter(part => part.inlineData !== undefined);
  requireCondition(audio.length === 1, 'EXPECTED_ONE_AUDIO_PART');
  const {mimeType, data} = audio[0].inlineData || {};
  requireCondition(typeof mimeType === 'string', 'AUDIO_MIME_MISSING');
  const fields = mimeType.toLowerCase().split(';').map(value => value.trim());
  requireCondition(fields.shift() === 'audio/l16', 'UNSUPPORTED_AUDIO_MIME');
  const parameters = Object.create(null);
  for (const field of fields) {
    const pair = field.split('=');
    requireCondition(pair.length === 2 && !Object.hasOwn(parameters, pair[0]), 'INVALID_AUDIO_MIME_PARAMETERS');
    parameters[pair[0]] = pair[1];
  }
  requireCondition(parameters.codec === 'pcm' && parameters.rate === '24000' &&
    Object.keys(parameters).every(name => ['codec', 'rate'].includes(name)), 'UNSUPPORTED_AUDIO_FORMAT');
  requireCondition(typeof data === 'string' && data.length > 0 && data.length <= MAX_RESPONSE_BYTES &&
    data.length % 4 === 0 && /^[A-Za-z0-9+/]*={0,2}$/.test(data), 'INVALID_AUDIO_BASE64');
  const pcm = Buffer.from(data, 'base64');
  requireCondition(pcm.toString('base64') === data && pcm.length > 0 && pcm.length % 2 === 0, 'INVALID_PCM_BYTES');
  return pcm;
}

function makeWave(pcm, sampleRate) {
  requireCondition(Buffer.isBuffer(pcm) && pcm.length > 0 && pcm.length % 2 === 0 &&
    [8000, 24000].includes(sampleRate), 'INVALID_WAVE_INPUT');
  const header = Buffer.alloc(44);
  header.write('RIFF', 0); header.writeUInt32LE(pcm.length + 36, 4); header.write('WAVEfmt ', 8);
  header.writeUInt32LE(16, 16); header.writeUInt16LE(1, 20); header.writeUInt16LE(1, 22);
  header.writeUInt32LE(sampleRate, 24); header.writeUInt32LE(sampleRate * 2, 28);
  header.writeUInt16LE(2, 32); header.writeUInt16LE(16, 34); header.write('data', 36);
  header.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([header, pcm]);
}

function inspectWave(wav, expectedRate) {
  requireCondition(Buffer.isBuffer(wav) && wav.length >= 44 && wav.toString('ascii', 0, 4) === 'RIFF' &&
    wav.toString('ascii', 8, 12) === 'WAVE' && wav.readUInt32LE(4) + 8 === wav.length, 'INVALID_WAVE_CONTAINER');
  let format, data, at = 12;
  while (at < wav.length) {
    requireCondition(at + 8 <= wav.length, 'TRUNCATED_WAVE_CHUNK');
    const name = wav.toString('ascii', at, at + 4), size = wav.readUInt32LE(at + 4), end = at + 8 + size;
    requireCondition(end + size % 2 <= wav.length, 'TRUNCATED_WAVE_CHUNK');
    if (name === 'fmt ') { requireCondition(!format && size >= 16, 'AMBIGUOUS_WAVE_FORMAT'); format = wav.subarray(at + 8, end); }
    if (name === 'data') { requireCondition(!data, 'MULTIPLE_WAVE_PAYLOADS'); data = wav.subarray(at + 8, end); }
    at = end + size % 2;
  }
  requireCondition(format && data && data.length > 0 && data.length % 2 === 0 &&
    format.readUInt16LE(0) === 1 && format.readUInt16LE(2) === 1 &&
    format.readUInt32LE(4) === expectedRate && format.readUInt32LE(8) === expectedRate * 2 &&
    format.readUInt16LE(12) === 2 && format.readUInt16LE(14) === 16, 'REQUIRE_PCM16_MONO_EXPECTED_RATE');
  let power = 0, peak = 0, clipped = 0, silence = 0;
  for (let offset = 0; offset < data.length; offset += 2) {
    const sample = data.readInt16LE(offset), magnitude = Math.abs(sample);
    power += sample * sample; peak = Math.max(peak, magnitude);
    if (magnitude >= 32767) clipped++;
    if (magnitude <= 32) silence++;
  }
  const count = data.length / 2;
  return {sample_rate_hz: expectedRate, channels: 1, bits_per_sample: 16,
    duration_seconds: count / expectedRate, rms: Math.sqrt(power / count), peak,
    clipped_samples: clipped, silence_fraction: silence / count, sha256: sha256(wav)};
}

function validateMetrics(metrics) {
  requireCondition(Number.isFinite(metrics.duration_seconds) && metrics.duration_seconds >= 0.25, 'AUDIO_TOO_SHORT');
  requireCondition(metrics.duration_seconds <= MAX_DURATION_SECONDS, 'AUDIO_EXCEEDS_TEN_SECOND_SUCCESS_TIMEOUT');
  requireCondition(metrics.clipped_samples === 0, 'AUDIO_CLIPPED');
  requireCondition(Number.isFinite(metrics.rms) && metrics.rms > 100 && metrics.silence_fraction < 0.98, 'AUDIO_SILENT_OR_TOO_QUIET');
}

function requestSpeech(body, key) {
  // Fixed origin/path, header-only credentials, no redirects or automatic retries.
  return new Promise((resolve, reject) => {
    let settled = false, timer, request;
    const fail = code => {
      if (settled) return;
      settled = true; clearTimeout(timer);
      if (request) request.destroy();
      reject(new SampleError(code));
    };
    try {
      const bytes = Buffer.from(JSON.stringify(body));
      request = https.request(ENDPOINT, {method: 'POST', headers: {
        'Content-Type': 'application/json', 'Content-Length': bytes.length, 'x-goog-api-key': key
      }}, response => {
        const status = response.statusCode;
        if (status !== 200) { response.destroy(); fail(`GEMINI_HTTP_${Number.isInteger(status) ? status : 'UNKNOWN'}`); return; }
        let size = 0; const chunks = [];
        response.on('data', chunk => {
          size += chunk.length;
          if (size > MAX_RESPONSE_BYTES) { response.destroy(); fail('GEMINI_RESPONSE_TOO_LARGE'); return; }
          chunks.push(chunk);
        });
        response.on('error', () => fail('GEMINI_RESPONSE_FAILED'));
        response.on('aborted', () => fail('GEMINI_RESPONSE_ABORTED'));
        response.on('end', () => {
          if (settled) return;
          let parsed;
          try { parsed = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
          catch (_) { fail('GEMINI_INVALID_JSON'); return; }
          settled = true; clearTimeout(timer); resolve(parsed);
        });
      });
      request.on('error', () => fail('GEMINI_REQUEST_FAILED'));
      timer = setTimeout(() => fail('GEMINI_REQUEST_TIMED_OUT'), REQUEST_TIMEOUT_MS);
      request.end(bytes);
    } catch (_) { fail('GEMINI_REQUEST_FAILED'); }
  });
}

function checkSox() {
  const result = cp.spawnSync('sox', ['--version'], {encoding: 'utf8', timeout: 10000, maxBuffer: 65536});
  requireCondition(!result.error && result.status === 0 && /SoX/.test(result.stdout), 'SOX_UNAVAILABLE');
  const version = result.stdout.match(/SoX v([0-9][0-9.]*)/);
  requireCondition(version, 'SOX_VERSION_UNKNOWN');
  return version[1];
}
function resample(source, destination) {
  // Resampling only: no time stretching, synthesized additions, or hidden normalization.
  const result = cp.spawnSync('sox', [source, '-r', '8000', '-c', '1', '-b', '16', '-e', 'signed-integer', destination,
    'rate', '-v', '8000'], {encoding: 'utf8', timeout: 30000, maxBuffer: 65536});
  requireCondition(!result.error && result.status === 0, 'SOX_RESAMPLE_FAILED');
  requireCondition(!/clip/i.test(result.stderr || ''), 'SOX_REPORTED_CLIPPING');
}

function saveManifest(directory, manifest) {
  const temporary = path.join(directory, '.manifest.next.json');
  fs.writeFileSync(temporary, JSON.stringify(manifest, null, 2) + '\n', {flag: 'wx', mode: 0o644});
  fs.renameSync(temporary, path.join(directory, 'manifest.json'));
}

async function generateSamples(options, dependencies = {}) {
  const ask = dependencies.requestSpeech || requestSpeech;
  const keyReader = dependencies.readProtectedKey || readProtectedKey;
  const check = dependencies.checkSox || checkSox;
  const convert = dependencies.resample || resample;
  const output = dependencies.output || (entry => console.log(JSON.stringify(entry)));
  requireCondition(options.generate === true, 'GENERATION_NOT_EXPLICITLY_ENABLED');
  validateOutputTarget(options.output);
  const soxVersion = check();
  let key = keyReader(options.keyFile);
  fs.mkdirSync(options.output, {mode: 0o700}); // Exclusive creation; never overwrite a previous run.
  const manifest = {
    schema_version: 1, owner: 'kazoo5-acdc-gemini-samples', status: STATUS,
    scope: 'preview', approved: false,
    provider: 'google-gemini', model: MODEL, preview_model: true, voice: VOICE,
    api_surface: 'v1beta/models:generateContent', api_endpoint: ENDPOINT,
    voice_style: 'warm adult female', created_at: new Date().toISOString(),
    native_speaker_review: false, audio_listening_review: false, runtime_ready: false, deployed: false,
    synthesis_requests_maximum: 5, attempts_per_sample: 1, retries: 0,
    request_timeout_seconds: REQUEST_TIMEOUT_MS / 1000,
    success_prompt_timeout_seconds: MAX_DURATION_SECONDS,
    source_catalog: 'scripts/acdc-language-catalog.cjs',
    documentation: ['https://ai.google.dev/gemini-api/docs/generate-content/speech-generation',
      'https://cloud.google.com/text-to-speech/docs/gemini-tts'],
    conversion: {tool: 'sox', version: soxVersion || null,
      argv: ['<master.wav>', '-r', '8000', '-c', '1', '-b', '16', '-e', 'signed-integer',
        '<telephony.wav>', 'rate', '-v', '8000'],
      transformations: 'Resampling only; no time stretching or normalization'},
    complete: false, sample_set_complete: false, generation_status: 'IN_PROGRESS', samples: []
  };
  saveManifest(options.output, manifest);
  let current;
  try {
    for (const sample of plan()) {
      const body = requestBody(sample);
      current = {...sample, generation_status: 'REQUESTING', transcript_sha256: sha256(sample.transcript),
        synthesis_instruction: body.contents[0].parts[0].text,
        request_body_sha256: sha256(JSON.stringify(body))};
      manifest.samples.push(current); saveManifest(options.output, manifest);
      const response = await ask(body, key);
      const pcm = extractPcm(response);
      current.source_audio_mime = response.candidates[0].content.parts.find(part => part.inlineData).inlineData.mimeType;
      current.raw_pcm_sha256 = sha256(pcm);
      if (typeof response.modelVersion === 'string' && /^gemini-[A-Za-z0-9._-]{1,120}$/.test(response.modelVersion)) {
        current.returned_model_version = response.modelVersion;
      }
      const localeDir = path.join(options.output, sample.locale);
      fs.mkdirSync(localeDir, {mode: 0o755});
      const masterName = `${sample.locale}/${ID}.master-24000.wav`;
      const deliveryName = `${sample.locale}/${ID}.telephony-8000.wav`;
      const master = makeWave(pcm, 24000);
      fs.writeFileSync(path.join(options.output, masterName), master, {flag: 'wx', mode: 0o644});
      current.master = {file: masterName, ...inspectWave(master, 24000)};
      validateMetrics(current.master);
      convert(path.join(options.output, masterName), path.join(options.output, deliveryName));
      fs.chmodSync(path.join(options.output, deliveryName), 0o644);
      current.telephony = {file: deliveryName, ...inspectWave(fs.readFileSync(path.join(options.output, deliveryName)), 8000)};
      validateMetrics(current.telephony);
      requireCondition(Math.abs(current.master.duration_seconds - current.telephony.duration_seconds) <= 1 / 8000,
        'RESAMPLING_CHANGED_DURATION');
      current.generation_status = 'GENERATED_QA_PASSED';
      current.completed_at = new Date().toISOString();
      saveManifest(options.output, manifest);
      output({locale: sample.locale, id: sample.id, status: STATUS, qa: 'PASSED',
        duration_seconds: current.telephony.duration_seconds, sha256: current.telephony.sha256});
    }
    manifest.sample_set_complete = true; manifest.generation_status = 'GENERATED_QA_PASSED';
    saveManifest(options.output, manifest);
    return manifest;
  } catch (error) {
    const code = safeCode(error);
    if (current) { current.generation_status = 'FAILED'; current.failure_code = code; }
    manifest.generation_status = 'STOPPED_ON_FIRST_FAILURE'; manifest.failure_code = code;
    saveManifest(options.output, manifest);
    throw error instanceof SampleError ? error : new SampleError(code);
  } finally { key = undefined; }
}

async function main(argv) {
  const options = parseOptions(argv);
  if (!options.generate) {
    for (const sample of plan()) console.log(JSON.stringify({locale: sample.locale, id: sample.id, status: 'PLAN_ONLY_NO_API_CALLS'}));
    return;
  }
  await generateSamples(options);
}

module.exports = {MODEL, VOICE, ENDPOINT, LOCALES, STATUS, SampleError, plan, requestBody, parseOptions,
  extractKey, readProtectedKey, validateOutputTarget, extractPcm, makeWave, inspectWave, validateMetrics,
  requestSpeech, generateSamples, main};
if (require.main === module) main(process.argv.slice(2)).catch(error => {
  console.error(`Gemini samples stopped: ${safeCode(error)}. No live media was imported.`);
  process.exitCode = 1;
});
