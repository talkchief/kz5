#!/usr/bin/env node
'use strict';

// Two NEW introduction identities only. Provider-free inspection; no import,
// account changes, automatic approval, or changes to the 584/210 inventories.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const cardinal = require('./acdc-cardinal-pack.cjs');
const OWNER = 'kazoo5-acdc-cardinal-intros-v1';
const ID = 'acdc-cardinal-intro-v1-current-position-number';
const FRAME = 'current-queue-position-number-label';
const {MODEL, VOICE, RESAMPLING, PackError, digest, inspectWave, technicalQa, resampleMaster} = cardinal;
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const check = (ok, code) => { if (!ok) throw new PackError(code); };
const plain = v => v !== null && typeof v === 'object' && !Array.isArray(v)
  && Object.getPrototypeOf(v) === Object.prototype;
const sha = v => typeof v === 'string' && /^[a-f0-9]{64}$/.test(v);
const exact = (v, names) => check(plain(v) && Object.keys(v).sort().join(',') === [...names].sort().join(','), 'UNEXPECTED_INTRO_FIELDS');
const PROMPTS = Object.freeze([
  {locale: 'he-il', language: 'Israeli Hebrew', grammatical_context: 'abstract-number-label-feminine',
    transcript: 'מִסְפַּר מְקוֹמְכֶם הַנּוֹכְחִי בַּתּוֹר הוּא.'},
  {locale: 'ar-sa', language: 'Modern Standard Arabic', grammatical_context: 'msa-masculine-nominative-number-label',
    transcript: 'رَقْمُ مَوْقِعِكَ الْحَالِي فِي طَابُورِ الِانْتِظَارِ هُوَ.'}
].map(p => Object.freeze({...p, id: ID, semantic_frame: FRAME, transcript_sha256: hash(p.transcript)})));
const CATALOG_HASH = digest(PROMPTS), MAX_JSON = 256 * 1024, MAX_WAV = 2 * 1024 * 1024;
const FINISH_REASONS = Object.freeze(['STOP', 'MAX_TOKENS', 'SAFETY', 'RECITATION', 'LANGUAGE', 'OTHER',
  'BLOCKLIST', 'PROHIBITED_CONTENT', 'SPII', 'MALFORMED_FUNCTION_CALL', 'IMAGE_SAFETY',
  'UNEXPECTED_TOOL_CALL', 'TOO_MANY_TOOL_CALLS', 'IMAGE_PROHIBITED_CONTENT', 'NO_IMAGE',
  'IMAGE_RECITATION', 'IMAGE_OTHER', 'FINISH_REASON_UNSPECIFIED', 'UNKNOWN']);
function plan() { return PROMPTS.map(p => ({...p})); }
function requestBody(entry) {
  const p = PROMPTS.find(p => p.locale === entry.locale && p.id === entry.id);
  check(p && Object.keys(p).every(k => entry[k] === p[k]), 'INTRO_TRANSCRIPT_CHANGED');
  return {contents: [{parts: [{text: `Read the transcript below verbatim in native ${p.language}. `
    + 'Use a professional, warm, natural adult female call-center voice. '
    + 'This introduces the number of the caller\'s current position in a queue, not a ticket number or the count of callers ahead. '
    + 'Speak clearly at a comfortable conversational pace. Only speak the transcript: no added number, introduction, music or sound effects. '
    + 'End with a natural brief pause before a separately recorded number. '
    + 'The complete introduction must fit within ten seconds; do not rush or omit words.\n\n'
    + `Transcript:\n${p.transcript}`}]}], generationConfig: {responseModalities: ['AUDIO'],
    speechConfig: {voiceConfig: {prebuiltVoiceConfig: {voiceName: VOICE}}}}};
}
function reviewTemplate() {
  return {schema_version: 1, catalog_sha256: CATALOG_HASH, decision: 'PENDING',
    review_kind: 'source-backed-engineering', evidence_sha256: null};
}
function validateReview(review, trusted) {
  exact(review, Object.keys(reviewTemplate()));
  check(review.schema_version === 1 && review.catalog_sha256 === CATALOG_HASH
    && review.decision === 'AUTHOR_INTROS_ONLY' && review.review_kind === 'source-backed-engineering'
    && sha(review.evidence_sha256), 'INTRO_SOURCE_REVIEW_REQUIRED');
  if (trusted !== undefined) check(sha(trusted) && digest(review) === trusted, 'INTRO_REVIEW_PIN_CHANGED');
  return review;
}
const absolute = file => typeof file === 'string' && path.isAbsolute(file) && path.resolve(file) === file;
const same = (a, b) => ['dev', 'ino', 'size', 'mtimeMs', 'ctimeMs', 'mode', 'nlink'].every(k => a[k] === b[k]);
function directory(dir, privateMode = false) {
  check(absolute(dir) && dir.split('/').filter(Boolean).length >= 1 && fs.realpathSync(dir) === dir,
    'INTRO_DIRECTORY_NOT_CANONICAL');
  const s = fs.lstatSync(dir);
  check(s.isDirectory() && !s.isSymbolicLink() && s.uid === process.getuid()
    && !(s.mode & (privateMode ? 0o077 : 0o022)), 'INTRO_DIRECTORY_NOT_PROTECTED');
  return s;
}
function readBytes(file, maximum = MAX_JSON) {
  check(absolute(file), 'INTRO_FILE_NOT_CANONICAL');
  directory(path.dirname(file));
  const before = fs.lstatSync(file);
  check(before.isFile() && !before.isSymbolicLink() && before.nlink === 1 && before.uid === process.getuid()
    && !(before.mode & 0o022) && before.size > 0 && before.size <= maximum, 'INTRO_FILE_NOT_PROTECTED');
  const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
  try {
    const s = fs.fstatSync(fd); check(same(before, s), 'INTRO_FILE_CHANGED');
    const bytes = Buffer.alloc(s.size + 1); let length = 0, n;
    while (length < bytes.length && (n = fs.readSync(fd, bytes, length, bytes.length - length, null)) > 0) length += n;
    check(length === s.size && same(s, fs.fstatSync(fd)) && same(s, fs.lstatSync(file))
      && fs.realpathSync(path.dirname(file)) === path.dirname(file), 'INTRO_FILE_CHANGED');
    return bytes.subarray(0, length);
  } finally { fs.closeSync(fd); }
}
function jsonFile(file) {
  const bytes = readBytes(file);
  try { return JSON.parse(bytes.toString('utf8')); } catch (_) { throw new PackError('INVALID_INTRO_JSON'); }
}
function fileName(entry, number, variant) {
  check(PROMPTS.some(p => p.locale === entry.locale && p.id === entry.id)
    && [1, 2].includes(number) && ['master', 'telephony'].includes(variant), 'INVALID_INTRO_AUDIO_IDENTITY');
  return `${entry.locale}/${ID}.attempt-${number}.${variant === 'master' ? 'master-24000' : 'telephony-8000'}.wav`;
}
function createManifest(review) {
  validateReview(review);
  return {schema_version: 1, owner: OWNER, catalog_sha256: CATALOG_HASH, provider: 'google-gemini', model: MODEL, voice: VOICE,
    source_review: review, source_review_sha256: digest(review), conversion_recipe_sha256: digest(RESAMPLING),
    initial_request_budget: 2, retry_request_budget: 0, requests_reserved: 0, automatic_retries: 0,
    artifact_complete: false, native_speaker_review: false, audio_listening_review: false, runtime_ready: false, deployed: false,
    prompts: plan().map(p => ({...p, generation_status: 'PENDING', attempts: []}))};
}
function validateEntry(dir, entry) {
  const p = PROMPTS.find(p => p.locale === entry?.locale && p.id === entry.id);
  check(p, 'UNKNOWN_INTRO_IDENTITY'); exact(entry, [...Object.keys(p), 'generation_status', 'attempts']);
  check(Object.keys(p).every(k => entry[k] === p[k]), 'INTRO_TRANSCRIPT_CHANGED');
  check(Array.isArray(entry.attempts) && entry.attempts.length <= 2
    && entry.generation_status === (entry.attempts.at(-1)?.status || 'PENDING'), 'INVALID_INTRO_ATTEMPTS');
  entry.attempts.forEach((a, index) => {
    exact(a, ['number', 'status', 'reserved_at', 'synthesis_instruction', 'instruction_sha256', 'request_body_sha256',
      'failure_code', 'provider_finish_reason', 'returned_model_version', 'raw_pcm_sha256', 'master', 'telephony']);
    check(a.number === index + 1 && ['REQUESTING', 'FAILED', 'QA_PASSED'].includes(a.status)
      && (!index || entry.attempts[index - 1].status === 'FAILED'), 'INTRO_RETRY_OF_SUCCESS_OR_INDETERMINATE');
    check(typeof a.reserved_at === 'string' && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(a.reserved_at)
      && Number.isFinite(Date.parse(a.reserved_at)), 'INVALID_INTRO_RESERVATION');
    const body = requestBody(p);
    check(a.synthesis_instruction === body.contents[0].parts[0].text && a.instruction_sha256 === hash(a.synthesis_instruction)
      && a.request_body_sha256 === hash(JSON.stringify(body)), 'INTRO_REQUEST_PROVENANCE_CHANGED');
    check(a.provider_finish_reason === null || FINISH_REASONS.includes(a.provider_finish_reason), 'INVALID_INTRO_FINISH_REASON');
    check(a.returned_model_version === null || typeof a.returned_model_version === 'string'
      && /^gemini-[A-Za-z0-9._-]{1,120}$/.test(a.returned_model_version), 'INVALID_INTRO_MODEL_VERSION');
    check(a.status === 'FAILED' ? typeof a.failure_code === 'string' && /^[A-Z][A-Z0-9_]{0,95}$/.test(a.failure_code)
      : a.failure_code === null, 'INVALID_INTRO_FAILURE');
    check(a.raw_pcm_sha256 === null || sha(a.raw_pcm_sha256), 'INVALID_INTRO_PCM_HASH');
    let master, telephony;
    for (const variant of ['master', 'telephony']) if (a[variant] !== null) {
      check(a[variant].file === fileName(p, a.number, variant), 'INTRO_AUDIO_PATH_CHANGED');
      const bytes = readBytes(path.join(dir, a[variant].file), MAX_WAV);
      const measured = inspectWave(bytes, variant === 'master' ? 24000 : 8000);
      check(digest(a[variant]) === digest({file: a[variant].file, ...measured}), 'INTRO_AUDIO_OR_METRICS_CHANGED');
      if (a.status === 'QA_PASSED') technicalQa(measured);
      if (variant === 'master') { master = bytes; check(measured.pcm_sha256 === a.raw_pcm_sha256, 'INTRO_RAW_PCM_CHANGED'); }
      else telephony = measured;
    }
    check(!telephony || master, 'INTRO_TELEPHONY_WITHOUT_MASTER');
    if (a.status === 'QA_PASSED') {
      check(master && telephony && a.provider_finish_reason === 'STOP', 'INTRO_QA_INCOMPLETE');
      const raw = resampleMaster(master);
      check(hash(raw) === telephony.pcm_sha256 && raw.length / 2 === telephony.sample_count, 'INTRO_NOT_MASTER_RESAMPLE');
    }
  });
  return entry;
}
function verifyEntry(dir, entry) {
  validateEntry(dir, entry); check(entry.generation_status === 'QA_PASSED', 'INTRO_QA_INCOMPLETE'); return entry;
}
function validateManifest(dir, m, trusted) {
  exact(m, Object.keys(createManifest(m.source_review)));
  check(m.schema_version === 1 && m.owner === OWNER && m.catalog_sha256 === CATALOG_HASH
    && m.provider === 'google-gemini' && m.model === MODEL && m.voice === VOICE
    && m.source_review_sha256 === digest(m.source_review) && m.conversion_recipe_sha256 === digest(RESAMPLING), 'INTRO_MANIFEST_CHANGED');
  validateReview(m.source_review, trusted);
  check(['native_speaker_review', 'audio_listening_review', 'runtime_ready', 'deployed'].every(k => m[k] === false), 'UNPROVEN_INTRO_READINESS');
  check(m.initial_request_budget === 2 && m.automatic_retries === 0 && Number.isInteger(m.retry_request_budget)
    && m.retry_request_budget >= 0 && m.retry_request_budget <= 2 && Number.isInteger(m.requests_reserved), 'INVALID_INTRO_BUDGET');
  check(Array.isArray(m.prompts) && m.prompts.length === 2 && new Set(m.prompts.map(p => p?.locale)).size === 2,
    'INVALID_INTRO_INVENTORY');
  m.prompts.forEach(p => validateEntry(dir, p));
  const attempts = m.prompts.reduce((sum, p) => sum + p.attempts.length, 0);
  const retries = m.prompts.reduce((sum, p) => sum + Math.max(0, p.attempts.length - 1), 0);
  check(m.requests_reserved === attempts && retries <= m.retry_request_budget && attempts <= 2 + m.retry_request_budget,
    'INTRO_REQUEST_ACCOUNTING_CHANGED');
  check(m.artifact_complete === m.prompts.every(p => p.generation_status === 'QA_PASSED'), 'FALSE_INTRO_COMPLETION');
  return m;
}
function readManifest(dir, trusted) {
  const root = directory(dir), file = path.join(dir, 'manifest.json'), bytes = readBytes(file);
  let m; try { m = JSON.parse(bytes); } catch (_) { throw new PackError('INVALID_INTRO_JSON'); }
  validateManifest(dir, m, trusted);
  check(same(root, directory(dir)) && hash(bytes) === hash(readBytes(file)), 'INTRO_PACK_CHANGED');
  return m;
}
function verifyPack(dir, trusted) {
  const m = readManifest(dir, trusted); check(m.artifact_complete, 'INTRO_PACK_INCOMPLETE');
  return {schema_version: 1, catalog_sha256: CATALOG_HASH, count: 2, technical_qa_complete: true,
    resampling_provenance_verified: true, independently_pinned_source_review: trusted !== undefined,
    // Facts suitable for the existing cardinal approval fields, NOT approvals.
    intro_inputs: m.prompts.map(p => ({locale: p.locale, canonical_id: p.id, transcript: p.transcript,
      transcript_sha256: p.transcript_sha256, wav_sha256: p.attempts.at(-1).telephony.sha256})),
    source_review_sha256: m.source_review_sha256, requests_reserved: m.requests_reserved,
    native_speaker_review: false, audio_listening_review: false, runtime_ready: false, deployed: false};
}
module.exports = Object.freeze({OWNER, ID, FRAME, MODEL, VOICE, RESAMPLING, CATALOG_HASH, FINISH_REASONS,
  PackError, check, hash, digest, absolute, plan, requestBody, reviewTemplate, validateReview,
  directory, readBytes, jsonFile, fileName, createManifest, validateEntry, verifyEntry, readManifest, verifyPack});
