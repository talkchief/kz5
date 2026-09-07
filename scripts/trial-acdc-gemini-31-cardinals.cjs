#!/usr/bin/env node
'use strict';
// Separate, explicit authoring experiment. Never imported by runtime/install.
// No model switch, resume, automatic retry, source mutation or readiness claim.
// Model: https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-tts-preview
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const https = require('node:https'), cp = require('node:child_process');
const pack = require('./acdc-cardinal-pack.cjs');
const author = require('./generate-acdc-gemini-cardinal-pack.cjs');
const MODEL = 'gemini-3.1-flash-tts-preview', VOICE = 'Sulafat';
const ENDPOINT = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`;
const MAX_RESPONSE_BYTES = 2 * 1024 * 1024, REQUEST_TIMEOUT_MS = 90000;
const OWNER = 'kazoo5-acdc-gemini-31-cardinal-model-trial';
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const absolute = file => typeof file === 'string' && path.isAbsolute(file) && path.resolve(file) === file;
const sha = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
class TrialError extends Error { constructor(code) { super(code); this.code = code; } }
const check = (ok, code) => { if (!ok) throw new TrialError(code); };
const inode = (a, b) => a.dev === b.dev && a.ino === b.ino;
function absent(file) {
  try { fs.lstatSync(file); return false; } catch (error) { if (error.code === 'ENOENT') return true; throw error; }
}
function read(file, maximum = 8 * 1024 * 1024) {
  check(absolute(file) && fs.realpathSync(path.dirname(file)) === path.dirname(file), 'NONCANONICAL_INPUT');
  const before = fs.lstatSync(file);
  check(before.isFile() && !before.isSymbolicLink() && before.nlink === 1 && !(before.mode & 0o022)
    && before.size > 0 && before.size <= maximum, 'UNSAFE_INPUT_FILE');
  const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
  try {
    const opened = fs.fstatSync(fd); check(inode(before, opened) && opened.size === before.size, 'INPUT_CHANGED');
    const bytes = Buffer.alloc(opened.size + 1); let size = 0, n;
    while (size < bytes.length && (n = fs.readSync(fd, bytes, size, bytes.length - size, null)) > 0) size += n;
    const after = fs.fstatSync(fd), named = fs.lstatSync(file);
    check(size === opened.size && inode(opened, named) && opened.size === after.size
      && opened.mtimeMs === after.mtimeMs && opened.ctimeMs === after.ctimeMs
      && named.mtimeMs === after.mtimeMs && named.ctimeMs === after.ctimeMs
      && fs.realpathSync(path.dirname(file)) === path.dirname(file), 'INPUT_CHANGED');
    return bytes.subarray(0, size);
  } finally { fs.closeSync(fd); }
}
function options(argv) {
  const o = {mode: 'plan'}, seen = new Set();
  const flags = {'--source-pack': 'source', '--source-manifest-sha256': 'sourceHash', '--approval-sha256': 'approvalHash',
    '--identities': 'identities', '--output': 'output', '--key-file': 'keyFile'};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]; check(!seen.has(arg), 'DUPLICATE_OPTION'); seen.add(arg);
    if (['--plan', '--generate'].includes(arg)) {
      check(!seen.has('mode'), 'CONFLICTING_MODES'); seen.add('mode'); o.mode = arg.slice(2);
    } else {
      check(Object.hasOwn(flags, arg) && argv[i + 1] && !argv[i + 1].startsWith('--'), 'INVALID_OPTION');
      o[flags[arg]] = argv[++i];
    }
  }
  if (typeof o.identities === 'string') o.identities = o.identities.split(',');
  check(absolute(o.source) && sha(o.sourceHash) && sha(o.approvalHash), 'PINNED_SOURCE_AND_APPROVAL_REQUIRED');
  check(Array.isArray(o.identities) && o.identities.length >= 1 && o.identities.length <= 3
    && new Set(o.identities).size === o.identities.length
    && o.identities.every(id => typeof id === 'string' && /^(he-il|ar-sa|es-es)\/acdc-cardinal-v1-[a-z0-9-]+$/.test(id)),
  'SELECT_ONE_TO_THREE_EXACT_FAILED_IDENTITIES');
  check(o.mode === 'generate' ? absolute(o.output) && absolute(o.keyFile) : o.output === undefined && o.keyFile === undefined,
    'OUTPUT_AND_KEY_ONLY_FOR_EXPLICIT_GENERATION');
  return o;
}
function selection(o) {
  // Revalidate public function inputs as well as CLI inputs. This does not
  // import the credential/provider helper, create output, or call a provider.
  check(['plan', 'generate'].includes(o.mode) && absolute(o.source) && sha(o.sourceHash) && sha(o.approvalHash), 'INVALID_TRIAL_OPTIONS');
  check(Array.isArray(o.identities) && o.identities.length >= 1 && o.identities.length <= 3
    && new Set(o.identities).size === o.identities.length && o.identities.every(id => typeof id === 'string'
      && /^(he-il|ar-sa|es-es)\/acdc-cardinal-v1-[a-z0-9-]+$/.test(id)), 'SELECT_ONE_TO_THREE_EXACT_FAILED_IDENTITIES');
  const sourceFile = path.join(o.source, 'manifest.json');
  const unchanged = () => {
    check(absent(path.join(o.source, '.generation.lock')), 'SOURCE_AUTHORING_IN_PROGRESS');
    check(hash(read(sourceFile)) === o.sourceHash, 'SOURCE_MANIFEST_PIN_CHANGED');
  };
  unchanged();
  const manifest = pack.readManifest(o.source); unchanged();
  check(!manifest.prompts.some(p => p.generation_status === 'REQUESTING'), 'SOURCE_HAS_INFLIGHT_REQUEST');
  const rows = o.identities.map(identity => {
    const entry = manifest.prompts.find(p => `${p.locale}/${p.id}` === identity);
    check(entry && entry.generation_status === 'FAILED' && entry.attempts.length > 0
      && entry.attempts.at(-1).status === 'FAILED', 'TARGET_NOT_FAILED');
    check(entry.attempts.length < pack.HARD_MAX_ATTEMPTS, 'SOURCE_ATTEMPT_CAP_REACHED');
    const body = pack.requestBody(entry, pack.CONCISE_SYNTHESIS_RECIPE);
    return {identity, entry, body};
  });
  pack.requireAuthoringApproval(manifest, [...new Set(rows.map(row => row.entry.locale))], o.approvalHash);
  return {manifest, rows, unchanged};
}
function plan(o) {
  const {manifest, rows} = selection(o);
  return {owner: OWNER, mode: 'PLAN_ONLY_NO_PROVIDER', model: MODEL, voice: VOICE, endpoint: ENDPOINT,
    source_model: manifest.model, source_manifest_sha256: o.sourceHash, approvals_sha256: o.approvalHash,
    selected: rows.map(({identity, entry, body}) => ({identity, transcript: entry.transcript,
      transcript_sha256: entry.transcript_sha256, source_entry_sha256: pack.digest(entry),
      source_attempt_count: entry.attempts.length, request_body_sha256: hash(JSON.stringify(body)),
      synthesis_recipe: pack.CONCISE_SYNTHESIS_RECIPE})),
    requests_maximum: rows.length, automatic_retries: 0, source_history_reset: false,
    runtime_ready: false, importable: false, deployed: false, native_listening_approved: false};
}
function requestSpeech(body, key, request = https.request) {
  return new Promise((resolve, reject) => {
    let req, timer, settled = false;
    const fail = code => {
      if (settled) return;
      settled = true; clearTimeout(timer); if (req) req.destroy(); reject(new TrialError(code));
    };
    try {
      const bytes = Buffer.from(JSON.stringify(body));
      req = request(ENDPOINT, {method: 'POST', headers: {'Content-Type': 'application/json',
        'Content-Length': bytes.length, 'x-goog-api-key': key}}, response => {
        if (response.statusCode !== 200) {
          response.destroy(); fail(`GEMINI_HTTP_${Number.isInteger(response.statusCode) ? response.statusCode : 'UNKNOWN'}`); return;
        }
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
      req.on('error', () => fail('GEMINI_REQUEST_FAILED'));
      timer = setTimeout(() => fail('GEMINI_REQUEST_TIMED_OUT'), REQUEST_TIMEOUT_MS);
      req.end(bytes);
    } catch (_) { fail('GEMINI_REQUEST_FAILED'); }
  });
}
function sync(dir) { const fd = fs.openSync(dir, fs.constants.O_RDONLY | fs.constants.O_DIRECTORY); try { fs.fsyncSync(fd); } finally { fs.closeSync(fd); } }
function audioMime(mime) {
  // Diagnostics contain only fixed literals/booleans, never provider strings.
  const diagnostic = {present: mime !== undefined, media_type: null, rate: null, channels: null, codec: null,
    malformed_parameters: false, duplicate_parameters: false, unknown_parameters: false, accepted: false};
  if (typeof mime !== 'string') return {diagnostic, error: 'AUDIO_MIME_MISSING'};
  const fields = mime.toLowerCase().split(';').map(value => value.trim());
  diagnostic.media_type = fields.shift() === 'audio/l16' ? 'audio/l16' : 'UNKNOWN';
  const parameters = Object.create(null);
  for (const field of fields) {
    const pair = field.split('=');
    if (pair.length !== 2 || !pair[0] || !pair[1]) { diagnostic.malformed_parameters = true; continue; }
    if (Object.hasOwn(parameters, pair[0])) diagnostic.duplicate_parameters = true;
    parameters[pair[0]] = pair[1];
    if (!['rate', 'channels', 'codec'].includes(pair[0])) diagnostic.unknown_parameters = true;
  }
  for (const [name, allowed] of [['rate', ['8000', '16000', '24000', '44100', '48000']],
    ['channels', ['1', '2']], ['codec', ['pcm']]]) {
    if (Object.hasOwn(parameters, name)) diagnostic[name] = allowed.includes(parameters[name]) ? parameters[name] : 'UNKNOWN';
  }
  let error = diagnostic.media_type !== 'audio/l16' ? 'UNSUPPORTED_AUDIO_MIME'
    : diagnostic.malformed_parameters || diagnostic.duplicate_parameters ? 'INVALID_AUDIO_MIME_PARAMETERS'
      : diagnostic.unknown_parameters || parameters.rate !== '24000'
        || (parameters.channels !== undefined && parameters.channels !== '1')
        || (parameters.codec !== undefined && parameters.codec !== 'pcm')
        || (parameters.channels === undefined && parameters.codec !== 'pcm') ? 'UNSUPPORTED_AUDIO_FORMAT' : null;
  diagnostic.accepted = error === null;
  return {diagnostic, error};
}
function audioMimeDiagnostics(response) {
  const parts = response?.candidates?.[0]?.content?.parts;
  const audio = Array.isArray(parts) ? parts.filter(part => part && part.inlineData !== undefined) : [];
  return audioMime(audio.length === 1 ? audio[0].inlineData?.mimeType : undefined).diagnostic;
}
function extractTrialPcm(response, helper) {
  check(response && Array.isArray(response.candidates) && response.candidates.length > 0, 'NO_AUDIO_CANDIDATE');
  const candidate = response.candidates[0];
  check(candidate?.finishReason === 'STOP', 'AUDIO_GENERATION_NOT_COMPLETE');
  const parts = candidate.content?.parts;
  check(Array.isArray(parts), 'NO_AUDIO_PARTS');
  const audio = parts.filter(part => part && part.inlineData !== undefined);
  check(audio.length === 1, 'EXPECTED_ONE_AUDIO_PART');
  const parsed = audioMime(audio[0].inlineData?.mimeType);
  check(parsed.error === null, parsed.error);
  // Trial-only MIME compatibility, not byte conversion or endian detection.
  // Google's 3.1 example writes decoded PCM directly to mono/24k/16-bit WAV:
  // https://ai.google.dev/gemini-api/docs/speech-generation (single-speaker).
  // Retain the old codec=pcm form; new channels=1 requires explicit 24k rate.
  // Feed a copy to the unchanged strict helper for STOP/base64/PCM validation.
  return helper.extractPcm({...response, candidates: [{...candidate, content: {...candidate.content,
    parts: parts.map(part => part === audio[0] ? {...part, inlineData: {...part.inlineData,
      mimeType: 'audio/L16;codec=pcm;rate=24000'}} : part)}}, ...response.candidates.slice(1)]});
}
function writeNew(file, bytes) {
  const fd = fs.openSync(file, fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_NOFOLLOW, 0o600);
  try { fs.writeFileSync(fd, bytes); fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
  sync(path.dirname(file));
}
function safeCode(error, helper) {
  // A provider exception may carry arbitrary strings, including credentials.
  // Only known local codes (or a numeric HTTP status) enter the trial ledger.
  const allowed = ['LOCAL_OPERATION_FAILED', 'SOURCE_AUTHORING_IN_PROGRESS', 'SOURCE_MANIFEST_PIN_CHANGED',
    'INPUT_CHANGED', 'NONCANONICAL_INPUT', 'UNSAFE_INPUT_FILE', 'TRIAL_DIRECTORY_CHANGED', 'TRIAL_LEDGER_CHANGED',
    'TRIAL_AUDIO_CHANGED', 'TRIAL_RETURNED_MODEL_MISMATCH', 'NO_AUDIO_CANDIDATE', 'AUDIO_GENERATION_NOT_COMPLETE',
    'NO_AUDIO_PARTS', 'EXPECTED_ONE_AUDIO_PART', 'AUDIO_MIME_MISSING', 'UNSUPPORTED_AUDIO_MIME',
    'INVALID_AUDIO_MIME_PARAMETERS', 'UNSUPPORTED_AUDIO_FORMAT', 'INVALID_AUDIO_BASE64', 'INVALID_PCM_BYTES',
    'INVALID_WAVE_INPUT', 'INVALID_WAVE_CONTAINER', 'AUDIO_DURATION_OUT_OF_BOUNDS', 'AUDIO_CLIPPED',
    'AUDIO_SILENT_OR_TOO_QUIET', 'RESAMPLING_DEADLINE_EXCEEDED', 'SOX_REPLAY_FAILED', 'SOX_VERSION_MISMATCH',
    'INVALID_REPLAY_PCM', 'GEMINI_HTTP_UNKNOWN', 'GEMINI_RESPONSE_TOO_LARGE', 'GEMINI_RESPONSE_FAILED',
    'GEMINI_RESPONSE_ABORTED', 'GEMINI_INVALID_JSON', 'GEMINI_REQUEST_FAILED', 'GEMINI_REQUEST_TIMED_OUT'];
  if ((error instanceof TrialError || error instanceof pack.PackError || helper?.SampleError && error instanceof helper.SampleError)
    && typeof error.code === 'string' && (allowed.includes(error.code) || /^GEMINI_HTTP_[1-5][0-9]{2}$/.test(error.code))) return error.code;
  return 'LOCAL_OPERATION_FAILED';
}
async function generate(o, deps = {}) {
  check(o.mode === 'generate' && absolute(o.output) && absolute(o.keyFile), 'EXPLICIT_GENERATION_REQUIRED');
  const selected = selection(o);
  check(!o.output.startsWith(o.source + '/') && o.output !== o.source
    && !o.keyFile.startsWith(o.output + '/'), 'TRIAL_MUST_BE_SEPARATE_FROM_SOURCE_AND_KEY');
  author.outputTarget(o.output, false);
  const sox = cp.spawnSync(pack.RESAMPLING.tool, ['--version'], {env: {PATH: '/usr/bin:/bin', LC_ALL: 'C', TZ: 'UTC'},
    encoding: 'utf8', timeout: 5000, maxBuffer: 4096});
  check(!sox.error && sox.status === 0 && sox.stderr === '' && /^(?:\/usr\/bin\/)?sox:\s+SoX v14\.4\.2$/.test(sox.stdout.trim()),
    'SOX_PREFLIGHT_FAILED');
  const helper = (deps.loadHelper || (() => require('./generate-acdc-gemini-samples.cjs')))();
  check(helper.VOICE === VOICE, 'VOICE_HELPER_CHANGED');
  // Key failure cannot strand a new output; it is never read during a plan.
  let key = (deps.readKey || helper.readProtectedKey)(o.keyFile);
  selected.unchanged();
  fs.mkdirSync(o.output, {mode: 0o700}); sync(path.dirname(o.output));
  const root = fs.lstatSync(o.output), ledgerFile = path.join(o.output, 'trial.json');
  const checkRoot = () => {
    const now = fs.lstatSync(o.output);
    check(now.isDirectory() && !now.isSymbolicLink() && inode(root, now) && now.uid === process.getuid()
      && !(now.mode & 0o077) && fs.realpathSync(o.output) === o.output, 'TRIAL_DIRECTORY_CHANGED');
  };
  const ledger = {schema_version: 1, owner: OWNER, status: 'PREPARED', created_at: new Date().toISOString(),
    provider: 'google-gemini', model: MODEL, voice: VOICE, endpoint: ENDPOINT,
    source_model: selected.manifest.model, source_manifest_sha256: o.sourceHash,
    source_requests_reserved: selected.manifest.requests_reserved, source_retry_budget: selected.manifest.retry_request_budget,
    catalog_sha256: pack.CATALOG_HASH, approvals_sha256: o.approvalHash,
    request_limit: selected.rows.length, requests_reserved: 0, automatic_retries: 0,
    source_history_reset: false, runtime_ready: false, importable: false, deployed: false, native_listening_approved: false,
    resampling_recipe_sha256: pack.digest(pack.RESAMPLING),
    entries: selected.rows.map(({identity, entry, body}) => ({identity, locale: entry.locale, id: entry.id,
      transcript: entry.transcript, transcript_sha256: entry.transcript_sha256,
      source_entry_sha256: pack.digest(entry), source_attempt_count: entry.attempts.length,
      source_attempt_count_plus_this_trial: entry.attempts.length + 1,
      source_attempts_sha256: pack.digest(entry.attempts), source_generation_status: entry.generation_status,
      synthesis_recipe: pack.CONCISE_SYNTHESIS_RECIPE, synthesis_instruction: body.contents[0].parts[0].text,
      request_body_sha256: hash(JSON.stringify(body)), status: 'SELECTED', reserved_at: null,
      returned_model_version: null, response_diagnostics: null, audio_mime_diagnostics: null, failure_code: null,
      raw_pcm_sha256: null, master: null, telephony: null}))};
  let ledgerHash = null;
  const save = () => {
    checkRoot();
    check(ledgerHash === null ? absent(ledgerFile) : hash(read(ledgerFile)) === ledgerHash, 'TRIAL_LEDGER_CHANGED');
    const bytes = Buffer.from(JSON.stringify(ledger, null, 2) + '\n');
    if (ledgerHash === null) writeNew(ledgerFile, bytes);
    else {
      const temporary = path.join(o.output, `.trial-${crypto.randomUUID()}.tmp`);
      writeNew(temporary, bytes); checkRoot();
      check(hash(read(ledgerFile)) === ledgerHash, 'TRIAL_LEDGER_CHANGED');
      fs.renameSync(temporary, ledgerFile); sync(o.output);
    }
    ledgerHash = hash(bytes);
  };
  const request = deps.requestSpeech || requestSpeech;
  try {
    save();
    for (let i = 0; i < selected.rows.length; i++) {
      selected.unchanged(); checkRoot();
      const trial = ledger.entries[i], {body} = selected.rows[i];
      trial.status = 'REQUESTING'; trial.reserved_at = new Date().toISOString();
      ledger.requests_reserved++; ledger.status = 'IN_PROGRESS'; save(); // durable before request
      try {
        const response = await request(body, key);
        trial.response_diagnostics = author.responseDiagnostics(response);
        trial.returned_model_version = response?.modelVersion === MODEL ? MODEL
          : response?.modelVersion === pack.MODEL ? pack.MODEL : response?.modelVersion === undefined ? null : 'UNKNOWN';
        trial.audio_mime_diagnostics = audioMimeDiagnostics(response);
        save(); // Persist safe response/format evidence before any extraction or QA.
        check(trial.returned_model_version === MODEL, 'TRIAL_RETURNED_MODEL_MISMATCH');
        const pcm = extractTrialPcm(response, helper); trial.raw_pcm_sha256 = hash(pcm);
        const master = helper.makeWave(pcm, 24000), masterMetrics = pack.technicalQa(pack.inspectWave(master, 24000));
        const phone = helper.makeWave(pack.resampleMaster(master), 8000), phoneMetrics = pack.technicalQa(pack.inspectWave(phone, 8000));
        selected.unchanged(); checkRoot();
        const base = `${String(i + 1).padStart(2, '0')}-${trial.locale}-${trial.id}`;
        const masterFile = `${base}.master-24000.wav`, phoneFile = `${base}.telephony-8000.wav`;
        writeNew(path.join(o.output, masterFile), master); trial.master = {file: masterFile, ...masterMetrics};
        writeNew(path.join(o.output, phoneFile), phone); trial.telephony = {file: phoneFile, ...phoneMetrics};
        check(hash(read(path.join(o.output, masterFile), MAX_RESPONSE_BYTES)) === masterMetrics.sha256
          && hash(read(path.join(o.output, phoneFile), MAX_RESPONSE_BYTES)) === phoneMetrics.sha256, 'TRIAL_AUDIO_CHANGED');
        trial.status = 'QA_PASSED'; save();
      } catch (error) {
        trial.status = 'FAILED'; trial.failure_code = safeCode(error, helper);
        ledger.status = 'STOPPED_ON_FAILURE'; save();
        throw new TrialError(trial.failure_code); // stop; never retry or silently continue
      }
    }
    selected.unchanged(); ledger.status = 'TRIAL_QA_COMPLETE_NOT_APPROVED'; save();
    return {owner: OWNER, status: ledger.status, model: MODEL, voice: VOICE,
      trial_manifest_sha256: ledgerHash, source_manifest_sha256: o.sourceHash,
      requests_reserved: ledger.requests_reserved, runtime_ready: false, importable: false, deployed: false};
  } catch (error) {
    if (ledger.status !== 'STOPPED_ON_FAILURE') {
      ledger.status = 'STOPPED_ON_FAILURE'; ledger.failure_code = safeCode(error, helper);
      try { save(); } catch (_) { /* Preserve existing evidence if its path/hash changed. */ }
    }
    throw new TrialError(safeCode(error, helper));
  } finally { key = undefined; }
}
async function main(argv) {
  const o = options(argv);
  console.log(JSON.stringify(o.mode === 'generate' ? await generate(o) : plan(o)));
}
module.exports = Object.freeze({MODEL, VOICE, ENDPOINT, MAX_RESPONSE_BYTES, REQUEST_TIMEOUT_MS,
  TrialError, options, plan, requestSpeech, audioMimeDiagnostics, extractTrialPcm, generate, main});
if (require.main === module) main(process.argv.slice(2)).catch(() => {
  console.error('Cardinal model trial stopped safely; inspect its separate trial ledger. Original history and runtime were not modified.');
  process.exitCode = 1;
});
