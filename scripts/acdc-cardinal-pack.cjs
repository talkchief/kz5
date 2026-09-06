#!/usr/bin/env node
'use strict';

// Read-only local authoring evidence. No provider/helper imports, credentials,
// network, writes or runtime activation. The sole subprocess is fixed local
// SoX with a fresh allowlisted environment, master stdin and bounded PCM stdout.
// A declared review is not reviewer authentication; accepting it requires an
// independently pinned approval-set hash. Intro audio is outside this pack.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const cp = require('node:child_process');
const catalog = require('./acdc-cardinal-catalog.cjs');
const OWNER = 'kazoo5-acdc-gemini-cardinal-pack';
const MODEL = 'gemini-2.5-pro-preview-tts', VOICE = 'Sulafat';
const MAX_MANIFEST_BYTES = 8 * 1024 * 1024, MAX_WAV_BYTES = 2 * 1024 * 1024;
const MAX_ATTEMPTS = 2, MAX_DURATION_SECONDS = 10;
const RESAMPLING = Object.freeze({tool: '/usr/bin/sox', version: '14.4.2',
  recipe: 'sox-14.4.2-rate-v-8000-pcm16le-no-dither-v1',
  argv: Object.freeze(['--no-dither', '-t', 'wav', '-', '-r', '8000', '-c', '1', '-b', '16',
    '-e', 'signed-integer', '-L', '-t', 'raw', '-', 'rate', '-v', '8000'])});
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const plain = value => value !== null && typeof value === 'object' && !Array.isArray(value)
  && Object.getPrototypeOf(value) === Object.prototype;
class PackError extends Error {
  constructor(code) { super(code); this.name = 'CardinalPackError'; this.code = code; }
}
const check = (ok, code) => { if (!ok) throw new PackError(code); };
function canonical(value) {
  if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
  if (plain(value)) return '{' + Object.keys(value).sort().map(k => JSON.stringify(k) + ':' + canonical(value[k])).join(',') + '}';
  check(value === null || ['string', 'boolean'].includes(typeof value)
    || typeof value === 'number' && Number.isFinite(value), 'NON_JSON_VALUE');
  return JSON.stringify(value);
}
const digest = value => hash(canonical(value));
const same = (a, b) => canonical(a) === canonical(b);
const sha = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
function keys(value, wanted, code = 'UNEXPECTED_FIELDS') {
  check(plain(value) && same(Object.keys(value).sort(), [...wanted].sort()), code);
}
const contexts = Object.freeze(Object.fromEntries(catalog.REQUIRED_LOCALES.map(locale => [locale, Object.freeze({
  semantic_frame: 'current-queue-position-number-label',
  grammar: {'en-us': 'american-cardinal-without-and', 'es-es': 'masculine-number-label-apocope-before-scale',
    'fr-fr': 'cardinal-contextual-scale-tails', 'he-il': catalog.HEBREW_CONTEXT, 'ar-sa': catalog.ARABIC_CONTEXT}[locale],
  delivery: locale === 'ar-sa' ? catalog.ARABIC_DELIVERY : 'natural-prerecorded-chunks',
  intro_approval_required: true
})])));
const CATALOG_HASH = digest(catalog.PROMPTS);
const expected = catalog.PROMPTS.map(p => Object.freeze({...p,
  catalog_record_sha256: digest(p), transcript_sha256: hash(p.transcript), context_sha256: digest(contexts[p.locale])}));
const byIdentity = new Map(expected.map(p => [p.locale + '/' + p.id, p]));
const LOCALE_HASHES = Object.freeze(Object.fromEntries(catalog.REQUIRED_LOCALES.map(l =>
  [l, digest(expected.filter(p => p.locale === l))])));
function plan(locale) {
  if (locale !== undefined) check(catalog.REQUIRED_LOCALES.includes(locale), 'UNSUPPORTED_LOCALE');
  return expected.filter(p => locale === undefined || p.locale === locale).map(p => ({...p}));
}
function pendingApproval(locale) {
  check(catalog.REQUIRED_LOCALES.includes(locale), 'UNSUPPORTED_LOCALE');
  const pending = () => ({status: 'PENDING', evidence_sha256: null});
  return {locale, locale_catalog_sha256: LOCALE_HASHES[locale], context_sha256: digest(contexts[locale]),
    transcript: pending(), delivery: {...pending(), policy: contexts[locale].delivery},
    intro: {...pending(), semantic_frame: contexts[locale].semantic_frame,
      canonical_id: null, transcript: null, transcript_sha256: null, wav_sha256: null},
    listening: {...pending(), asset_set_sha256: null}};
}
// Construction returns data only; a later authoring tool must reserve requests
// durably BEFORE transport. This verifier neither reserves nor retries anything.
function createManifest() {
  const approvals = catalog.REQUIRED_LOCALES.map(pendingApproval);
  return {schema_version: 1, owner: OWNER, catalog_version: catalog.VERSION, catalog_sha256: CATALOG_HASH,
    provider: 'google-gemini', model: MODEL, voice: VOICE,
    initial_request_budget: expected.length, retry_request_budget: 0, requests_reserved: 0,
    retries_explicitly_enabled: false, automatic_retries: 0,
    conversion: {tool: 'sox', version: null, transformations: 'resampling-only', recipe_sha256: digest(RESAMPLING)},
    approvals, approvals_sha256: digest(approvals), artifact_complete: false,
    runtime_ready: false, deployed: false, full_position_numeric_range_ready: false,
    prompts: expected.map(p => ({...p, generation_status: 'PENDING', attempts: []}))};
}
function validateBase(entry) {
  check(plain(entry), 'INVALID_ENTRY');
  const wanted = byIdentity.get(entry.locale + '/' + entry.id);
  check(wanted, 'UNEXPECTED_CARDINAL_IDENTITY');
  keys(entry, [...Object.keys(wanted), 'generation_status', 'attempts']);
  for (const key of Object.keys(wanted)) check(same(entry[key], wanted[key]), 'CATALOG_TRANSCRIPT_OR_CONTEXT_CHANGED');
  return wanted;
}
function fileName(entry, number, variant) {
  check(byIdentity.has(entry.locale + '/' + entry.id) && [1, 2].includes(number)
    && ['master', 'telephony'].includes(variant), 'INVALID_AUDIO_IDENTITY');
  return `${entry.locale}/${entry.id}.attempt-${number}.${variant === 'master' ? 'master-24000' : 'telephony-8000'}.wav`;
}
// Pure request-shape pin for later authoring. Constructing this data performs
// no request; keeping it here makes provenance verification provider-free.
function requestBody(entry) {
  const wanted = byIdentity.get(entry.locale + '/' + entry.id);
  check(wanted && Object.keys(wanted).every(k => same(entry[k], wanted[k])), 'CATALOG_TRANSCRIPT_OR_CONTEXT_CHANGED');
  const language = {'en-us': 'American English', 'es-es': 'Spanish from Spain', 'fr-fr': 'French from France',
    'he-il': 'Israeli Hebrew', 'ar-sa': 'Modern Standard Arabic'}[entry.locale];
  const delivery = entry.locale === 'ar-sa'
    ? 'This is one complete pausal chunk; preserve its written internal inflection and end at a natural pause. '
    : 'This is one complete prerecorded cardinal-number chunk. ';
  const text = `Read the transcript below verbatim in native ${language}. `
    + 'Use a professional, warm, natural adult female call-center voice. ' + delivery
    + 'Speak clearly at a comfortable conversational pace. Only speak the transcript: no introduction, added words, music or sound effects. '
    + `Do not rush or omit words; the complete chunk must fit within ${MAX_DURATION_SECONDS} seconds.\n\nTranscript:\n${wanted.transcript}`;
  return {contents: [{parts: [{text}]}], generationConfig: {responseModalities: ['AUDIO'],
    speechConfig: {voiceConfig: {prebuiltVoiceConfig: {voiceName: VOICE}}}}};
}
const metricKeys = ['sha256', 'pcm_sha256', 'byte_length', 'sample_count', 'sample_rate_hz', 'channels',
  'bits_per_sample', 'duration_seconds', 'rms', 'peak', 'clipped_samples', 'silence_fraction',
  'leading_silence_samples', 'trailing_silence_samples'];
function inspectWave(wav, rate) {
  check([8000, 24000].includes(rate) && Buffer.isBuffer(wav) && wav.length >= 44 && wav.length <= MAX_WAV_BYTES
    && wav.toString('ascii', 0, 4) === 'RIFF' && wav.toString('ascii', 8, 12) === 'WAVE'
    && wav.readUInt32LE(4) + 8 === wav.length, 'INVALID_WAVE_CONTAINER');
  let format, data, at = 12;
  while (at < wav.length) {
    check(at + 8 <= wav.length, 'TRUNCATED_WAVE_CHUNK');
    const name = wav.toString('ascii', at, at + 4), size = wav.readUInt32LE(at + 4), end = at + 8 + size;
    check(end + size % 2 <= wav.length, 'TRUNCATED_WAVE_CHUNK');
    if (name === 'fmt ') { check(!format && size === 16, 'AMBIGUOUS_WAVE_FORMAT'); format = wav.subarray(at + 8, end); }
    if (name === 'data') { check(!data, 'MULTIPLE_WAVE_PAYLOADS'); data = wav.subarray(at + 8, end); }
    at = end + size % 2;
  }
  check(format && data && data.length > 0 && data.length % 2 === 0 && format.readUInt16LE(0) === 1
    && format.readUInt16LE(2) === 1 && format.readUInt32LE(4) === rate && format.readUInt32LE(8) === rate * 2
    && format.readUInt16LE(12) === 2 && format.readUInt16LE(14) === 16, 'REQUIRE_PCM16_MONO_EXPECTED_RATE');
  let power = 0, peak = 0, clipped = 0, silence = 0, first = -1, last = -1;
  const count = data.length / 2;
  for (let i = 0; i < count; i++) {
    const sample = data.readInt16LE(i * 2), magnitude = Math.abs(sample);
    power += sample * sample; peak = Math.max(peak, magnitude);
    if (magnitude >= 32767) clipped++;
    if (magnitude <= 32) silence++;
    else { if (first < 0) first = i; last = i; }
  }
  // Edge silence is measured, never trimmed/padded or treated as cadence proof.
  return {sha256: hash(wav), pcm_sha256: hash(data), byte_length: wav.length, sample_count: count,
    sample_rate_hz: rate, channels: 1, bits_per_sample: 16, duration_seconds: count / rate,
    rms: Math.sqrt(power / count), peak, clipped_samples: clipped, silence_fraction: silence / count,
    leading_silence_samples: first < 0 ? count : first, trailing_silence_samples: last < 0 ? count : count - 1 - last};
}
function technicalQa(metrics) {
  check(metrics.duration_seconds >= 0.25 && metrics.duration_seconds <= MAX_DURATION_SECONDS, 'AUDIO_DURATION_OUT_OF_BOUNDS');
  check(metrics.clipped_samples === 0, 'AUDIO_CLIPPED');
  check(metrics.rms > 100 && metrics.silence_fraction < 0.98, 'AUDIO_SILENT_OR_TOO_QUIET');
  return metrics;
}
function resamplingScope() { return {deadline: Date.now() + 45000, checked: false, cache: new Map()}; }
function pcmPayload(wav) {
  // Only called on bytes already accepted by inspectWave in this operation.
  for (let at = 12; at < wav.length;) {
    const size = wav.readUInt32LE(at + 4);
    if (wav.toString('ascii', at, at + 4) === 'data') return wav.subarray(at + 8, at + 8 + size);
    at += 8 + size + size % 2;
  }
  throw new PackError('MISSING_WAVE_PCM');
}
function sox(argv, input, scope, maximum) {
  const remaining = scope.deadline - Date.now(); check(remaining > 0, 'RESAMPLING_DEADLINE_EXCEEDED');
  const result = cp.spawnSync(RESAMPLING.tool, argv, {input, encoding: null, shell: false,
    env: {PATH: '/usr/bin:/bin', LC_ALL: 'C', TZ: 'UTC'},
    timeout: Math.min(5000, remaining), maxBuffer: maximum});
  check(!result.error && result.status === 0 && result.signal === null && Buffer.isBuffer(result.stdout)
    && Buffer.isBuffer(result.stderr) && result.stderr.length === 0, 'SOX_REPLAY_FAILED');
  return result.stdout;
}
function resampleMaster(master, scope = resamplingScope()) {
  const measured = inspectWave(master, 24000);
  check(measured.duration_seconds <= MAX_DURATION_SECONDS, 'AUDIO_DURATION_OUT_OF_BOUNDS');
  if (!scope.checked) {
    const version = sox(['--version'], undefined, scope, 4096).toString('utf8').trim();
    check(/^(?:\/usr\/bin\/)?sox:\s+SoX v14\.4\.2$/.test(version), 'SOX_VERSION_MISMATCH');
    scope.checked = true;
  }
  const known = scope.cache.get(measured.sha256);
  if (known) return known;
  const raw = sox([...RESAMPLING.argv], master, scope, MAX_DURATION_SECONDS * 8000 * 2 + 4096);
  check(raw.length > 0 && raw.length % 2 === 0 && raw.length <= MAX_DURATION_SECONDS * 8000 * 2,
    'INVALID_REPLAY_PCM');
  // Private per-verification cache only; never trust a persisted derived hash.
  // Bound retained PCM to at most16 ten-second clips (2.56MB).
  if (scope.cache.size === 16) scope.cache.delete(scope.cache.keys().next().value);
  scope.cache.set(measured.sha256, raw);
  return raw;
}
function safeDirectory(directory) {
  check(typeof directory === 'string' && path.isAbsolute(directory) && path.resolve(directory) === directory
    && directory.split(path.sep).filter(Boolean).length >= 2, 'INVALID_PACK_DIRECTORY');
  const stat = fs.lstatSync(directory);
  check(stat.isDirectory() && !stat.isSymbolicLink() && !(stat.mode & 0o022)
    && fs.realpathSync(directory) === directory, 'INVALID_PACK_DIRECTORY');
  return stat;
}
function sameFile(a, b) {
  return ['dev', 'ino', 'size', 'mtimeMs', 'ctimeMs', 'mode', 'nlink'].every(k => a[k] === b[k]);
}
function regularBytes(directory, relative, maximum) {
  safeDirectory(directory);
  check(typeof relative === 'string' && relative.length < 512 && !relative.startsWith('/')
    && relative.split('/').every(p => /^[a-zA-Z0-9_.-]+$/.test(p) && p !== '.' && p !== '..'), 'INVALID_RELATIVE_FILE');
  const file = path.join(directory, relative), parent = path.dirname(file);
  safeDirectory(parent);
  const before = fs.lstatSync(file);
  check(before.isFile() && !before.isSymbolicLink() && before.nlink === 1 && !(before.mode & 0o022)
    && before.size > 0 && before.size <= maximum, 'INVALID_REGULAR_FILE');
  const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
  try {
    const opened = fs.fstatSync(fd);
    check(opened.isFile() && sameFile(before, opened), 'SOURCE_FILE_CHANGED');
    // Bound the read itself, not merely the preceding size observation.
    const bounded = Buffer.alloc(opened.size + 1); let size = 0, count;
    while (size < bounded.length && (count = fs.readSync(fd, bounded, size, bounded.length - size, null)) > 0) size += count;
    const bytes = bounded.subarray(0, size);
    check(bytes.length === opened.size && sameFile(opened, fs.fstatSync(fd))
      && sameFile(opened, fs.lstatSync(file)) && fs.realpathSync(parent) === parent, 'SOURCE_FILE_CHANGED');
    return bytes;
  } finally { fs.closeSync(fd); }
}
const finishReasons = new Set(['STOP', 'MAX_TOKENS', 'SAFETY', 'RECITATION', 'LANGUAGE', 'OTHER', 'BLOCKLIST',
  'PROHIBITED_CONTENT', 'SPII', 'MALFORMED_FUNCTION_CALL', 'IMAGE_SAFETY', 'UNEXPECTED_TOOL_CALL',
  'TOO_MANY_TOOL_CALLS', 'IMAGE_PROHIBITED_CONTENT', 'NO_IMAGE', 'IMAGE_RECITATION', 'IMAGE_OTHER',
  'FINISH_REASON_UNSPECIFIED', 'UNKNOWN']);
function validateAttempt(entry, attempt, index, directory, scope) {
  keys(attempt, ['number', 'status', 'reserved_at', 'synthesis_instruction', 'instruction_sha256',
    'request_body_sha256', 'failure_code', 'provider_finish_reason', 'raw_pcm_sha256', 'master', 'telephony']);
  check(attempt.number === index + 1 && ['REQUESTING', 'FAILED', 'QA_PASSED'].includes(attempt.status), 'INVALID_ATTEMPT_SEQUENCE');
  check(typeof attempt.reserved_at === 'string' && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(attempt.reserved_at)
    && Number.isFinite(Date.parse(attempt.reserved_at)), 'INVALID_RESERVATION_TIME');
  const body = requestBody(entry);
  check(attempt.synthesis_instruction === body.contents[0].parts[0].text
    && attempt.instruction_sha256 === hash(attempt.synthesis_instruction)
    && attempt.request_body_sha256 === hash(JSON.stringify(body)), 'INVALID_REQUEST_PROVENANCE');
  check(attempt.provider_finish_reason === null || finishReasons.has(attempt.provider_finish_reason), 'UNSAFE_FINISH_REASON');
  check(attempt.status === 'FAILED' ? typeof attempt.failure_code === 'string' && /^[A-Z][A-Z0-9_]{0,95}$/.test(attempt.failure_code)
    : attempt.failure_code === null, 'INVALID_FAILURE_CODE');
  check(attempt.raw_pcm_sha256 === null || sha(attempt.raw_pcm_sha256), 'INVALID_PCM_PROVENANCE');
  const bytes = {};
  for (const variant of ['master', 'telephony']) if (attempt[variant] !== null) {
    const saved = attempt[variant]; keys(saved, ['file', ...metricKeys]);
    check(saved.file === fileName(entry, attempt.number, variant), 'UNEXPECTED_AUDIO_PATH');
    bytes[variant] = regularBytes(directory, saved.file, MAX_WAV_BYTES);
    const actual = inspectWave(bytes[variant], variant === 'master' ? 24000 : 8000);
    for (const k of metricKeys) check(actual[k] === saved[k], 'AUDIO_HASH_OR_METRICS_CHANGED');
    if (variant === 'master') check(attempt.raw_pcm_sha256 === actual.pcm_sha256, 'RAW_PCM_HASH_CHANGED');
    if (attempt.status === 'QA_PASSED') technicalQa(actual);
  }
  check(attempt.telephony === null || attempt.master !== null, 'TELEPHONY_WITHOUT_MASTER');
  if (attempt.master && attempt.telephony) check(Math.abs(attempt.master.duration_seconds - attempt.telephony.duration_seconds) <= 1 / 8000,
    'RESAMPLING_CHANGED_DURATION');
  if (attempt.status === 'QA_PASSED') {
    check(attempt.master && attempt.telephony && attempt.provider_finish_reason === 'STOP', 'INCOMPLETE_TECHNICAL_QA');
    check(resampleMaster(bytes.master, scope).equals(pcmPayload(bytes.telephony)), 'TELEPHONY_NOT_EXACT_MASTER_RESAMPLE');
  }
}
function validateEntry(directory, entry, scope = resamplingScope()) {
  validateBase(entry);
  check(Array.isArray(entry.attempts) && entry.attempts.length <= MAX_ATTEMPTS, 'INVALID_ATTEMPT_HISTORY');
  check(entry.generation_status === (entry.attempts.length ? entry.attempts.at(-1).status : 'PENDING'), 'ENTRY_STATUS_MISMATCH');
  entry.attempts.forEach((attempt, index) => {
    if (index) check(entry.attempts[index - 1].status === 'FAILED', 'RETRY_OF_SUCCESS_OR_INDETERMINATE_REQUEST');
    validateAttempt(entry, attempt, index, directory, scope);
  });
  return entry;
}
function verifyEntry(directory, entry) {
  validateEntry(directory, entry);
  check(entry.generation_status === 'QA_PASSED', 'ENTRY_TECHNICAL_QA_INCOMPLETE');
  return entry;
}
function assetSetHash(manifest, locale) {
  const entries = manifest.prompts.filter(p => p.locale === locale);
  if (entries.length !== plan(locale).length || entries.some(p => p.generation_status !== 'QA_PASSED')) return null;
  return digest(entries.map(p => ({id: p.id, master: p.attempts.at(-1).master.sha256,
    telephony: p.attempts.at(-1).telephony.sha256})).sort((a, b) => a.id.localeCompare(b.id, 'en')));
}
function validateReview(review) {
  check(['PENDING', 'APPROVED'].includes(review.status) && (review.status === 'PENDING'
    ? review.evidence_sha256 === null : sha(review.evidence_sha256)), 'INVALID_DECLARED_REVIEW');
}
function validateApprovals(manifest) {
  check(Array.isArray(manifest.approvals) && manifest.approvals.length === catalog.REQUIRED_LOCALES.length
    && manifest.approvals_sha256 === digest(manifest.approvals), 'APPROVAL_SET_CHANGED');
  const seen = new Set();
  for (const a of manifest.approvals) {
    keys(a, ['locale', 'locale_catalog_sha256', 'context_sha256', 'transcript', 'delivery', 'intro', 'listening']);
    check(catalog.REQUIRED_LOCALES.includes(a.locale) && !seen.has(a.locale)
      && a.locale_catalog_sha256 === LOCALE_HASHES[a.locale] && a.context_sha256 === digest(contexts[a.locale]), 'APPROVAL_CONTEXT_CHANGED');
    seen.add(a.locale);
    keys(a.transcript, ['status', 'evidence_sha256']);
    keys(a.delivery, ['status', 'evidence_sha256', 'policy']);
    keys(a.intro, ['status', 'evidence_sha256', 'semantic_frame', 'canonical_id', 'transcript', 'transcript_sha256', 'wav_sha256']);
    keys(a.listening, ['status', 'evidence_sha256', 'asset_set_sha256']);
    for (const review of [a.transcript, a.delivery, a.intro, a.listening]) validateReview(review);
    check(a.delivery.policy === contexts[a.locale].delivery && a.intro.semantic_frame === contexts[a.locale].semantic_frame, 'APPROVAL_CONTEXT_CHANGED');
    if (a.intro.status === 'PENDING') check(['canonical_id', 'transcript', 'transcript_sha256', 'wav_sha256'].every(k => a.intro[k] === null), 'UNREVIEWED_INTRO');
    else check(typeof a.intro.canonical_id === 'string' && /^acdc-[a-z0-9_-]{1,120}$/.test(a.intro.canonical_id)
      && typeof a.intro.transcript === 'string' && a.intro.transcript.length > 0 && a.intro.transcript.length <= 2048
      && !/[\x00-\x1f\x7f]/.test(a.intro.transcript) && a.intro.transcript_sha256 === hash(a.intro.transcript)
      && sha(a.intro.wav_sha256), 'INVALID_APPROVED_INTRO');
    if (a.listening.status === 'PENDING') check(a.listening.asset_set_sha256 === null, 'UNREVIEWED_AUDIO');
    else check(a.transcript.status === 'APPROVED' && a.intro.status === 'APPROVED' && a.delivery.status === 'APPROVED'
      && sha(a.listening.asset_set_sha256) && a.listening.asset_set_sha256 === assetSetHash(manifest, a.locale), 'LISTENING_ASSETS_CHANGED');
  }
}
function validateManifest(directory, manifest) {
  keys(manifest, Object.keys(createManifest()));
  check(manifest.schema_version === 1 && manifest.owner === OWNER && manifest.catalog_version === catalog.VERSION
    && manifest.catalog_sha256 === CATALOG_HASH && manifest.provider === 'google-gemini' && manifest.model === MODEL && manifest.voice === VOICE,
  'UNOWNED_OR_CHANGED_CARDINAL_PACK');
  check(manifest.runtime_ready === false && manifest.deployed === false && manifest.full_position_numeric_range_ready === false, 'UNEXPECTED_READINESS_CLAIM');
  check(Array.isArray(manifest.prompts) && manifest.prompts.length === expected.length && manifest.prompts.every(plain)
    && new Set(manifest.prompts.map(p => p.locale + '/' + p.id)).size === expected.length, 'INCOMPLETE_OR_DUPLICATE_INVENTORY');
  check(manifest.initial_request_budget === expected.length && Number.isInteger(manifest.retry_request_budget)
    && manifest.retry_request_budget >= 0 && manifest.retry_request_budget <= expected.length
    && manifest.retries_explicitly_enabled === (manifest.retry_request_budget > 0) && manifest.automatic_retries === 0
    && Number.isInteger(manifest.requests_reserved) && manifest.requests_reserved >= 0, 'INVALID_REQUEST_BUDGET');
  let initial = 0, retries = 0; const scope = resamplingScope();
  for (const entry of manifest.prompts) {
    validateEntry(directory, entry, scope);
    if (entry.attempts.length) { initial++; retries += entry.attempts.length - 1; }
  }
  check(manifest.requests_reserved === initial + retries && retries <= manifest.retry_request_budget
    && manifest.requests_reserved <= manifest.initial_request_budget + manifest.retry_request_budget, 'REQUEST_ACCOUNTING_MISMATCH');
  keys(manifest.conversion, ['tool', 'version', 'transformations', 'recipe_sha256']);
  check(manifest.conversion.tool === 'sox' && manifest.conversion.transformations === 'resampling-only'
    && manifest.conversion.recipe_sha256 === digest(RESAMPLING)
    && (manifest.conversion.version === null ? initial === 0 : manifest.conversion.version === RESAMPLING.version), 'INVALID_CONVERSION_PROVENANCE');
  check(manifest.artifact_complete === manifest.prompts.every(p => p.generation_status === 'QA_PASSED'), 'FALSE_COMPLETION_CLAIM');
  validateApprovals(manifest);
  return manifest;
}
function readManifest(directory) {
  const before = safeDirectory(directory), bytes = regularBytes(directory, 'manifest.json', MAX_MANIFEST_BYTES);
  let manifest;
  try { manifest = JSON.parse(bytes.toString('utf8')); } catch (_) { throw new PackError('INVALID_MANIFEST_JSON'); }
  validateManifest(directory, manifest);
  check(sameFile(before, safeDirectory(directory)) && hash(regularBytes(directory, 'manifest.json', MAX_MANIFEST_BYTES)) === hash(bytes), 'PACK_CHANGED_DURING_VERIFICATION');
  return manifest;
}
function requireAuthoringApproval(manifest, locales, trustedApprovalHash) {
  validateApprovals(manifest);
  check(sha(trustedApprovalHash) && trustedApprovalHash === manifest.approvals_sha256, 'INDEPENDENT_APPROVAL_PIN_REQUIRED');
  check(Array.isArray(locales) && locales.length > 0 && new Set(locales).size === locales.length
    && locales.every(l => catalog.REQUIRED_LOCALES.includes(l)), 'INVALID_LOCALE_SELECTION');
  for (const locale of locales) {
    const a = manifest.approvals.find(a => a.locale === locale);
    check([a.transcript, a.delivery, a.intro].every(r => r.status === 'APPROVED'), 'AUTHORING_APPROVAL_PENDING');
  }
  return true;
}
function verifyPack(directory, trustedApprovalHash) {
  const manifest = readManifest(directory);
  check(manifest.artifact_complete, 'CARDINAL_PACK_INCOMPLETE');
  if (trustedApprovalHash !== undefined) {
    requireAuthoringApproval(manifest, catalog.REQUIRED_LOCALES, trustedApprovalHash);
    check(manifest.approvals.every(a => a.listening.status === 'APPROVED'), 'LISTENING_APPROVAL_PENDING');
  }
  return {schema_version: 1, owner: OWNER, catalog_sha256: CATALOG_HASH, prompts: expected.length,
    technical_qa_complete: true, resampling_provenance_verified: true, resampling_recipe_sha256: digest(RESAMPLING),
    approvals_sha256: manifest.approvals_sha256,
    declared_authoring_approval: manifest.approvals.every(a => [a.transcript, a.intro, a.delivery].every(r => r.status === 'APPROVED')),
    declared_listening_approval: manifest.approvals.every(a => a.listening.status === 'APPROVED'),
    independently_pinned_approval: trustedApprovalHash !== undefined,
    intro_audio_verified: false, provider_provenance_authenticated: false,
    requests_reserved: manifest.requests_reserved, runtime_ready: false, deployed: false,
    full_position_numeric_range_ready: false};
}
function main(argv) {
  check(argv.length === 2 && argv[0] === '--verify-only'
    || argv.length === 4 && argv[0] === '--verify-only' && argv[2] === '--approval-sha256', 'INVALID_READ_ONLY_OPTIONS');
  console.log(JSON.stringify(verifyPack(argv[1], argv[3])));
}
module.exports = Object.freeze({OWNER, MODEL, VOICE, CATALOG_HASH, LOCALE_HASHES, MAX_ATTEMPTS, RESAMPLING,
  MAX_DURATION_SECONDS, PackError, digest, contexts, plan, pendingApproval, createManifest,
  fileName, requestBody, inspectWave, technicalQa, resampleMaster, verifyEntry, validateManifest, readManifest,
  assetSetHash, requireAuthoringApproval, verifyPack, main});
if (require.main === module) {
  try { main(process.argv.slice(2)); }
  catch (_) { console.error('Cardinal pack verification failed safely; no provider, import or runtime operation was attempted.'); process.exitCode = 1; }
}
