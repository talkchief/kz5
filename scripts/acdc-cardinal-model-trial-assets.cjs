'use strict';

// Read-only candidates from explicitly pinned, terminal 3.1 trial receipts.
// No trial/provider/helper imports, requests, ledger edits, promotion or runtime
// admission. Original 2.5 attempts and additional trial requests stay distinct.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const pack = require('./acdc-cardinal-pack.cjs');
const fr89 = require('./acdc-cardinal-fr89-one-shot-policy.cjs');
const OWNER = 'kazoo5-acdc-cardinal-model-trial-assets';
const TRIAL_OWNER = 'kazoo5-acdc-gemini-31-cardinal-model-trial';
const MODEL = 'gemini-3.1-flash-tts-preview', VOICE = 'Sulafat', MAX_TRIALS = 64;
const ENDPOINT = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`;
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const sha = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const clone = value => JSON.parse(JSON.stringify(value));
class TrialAssetsError extends Error { constructor(code) { super(code); this.name = 'CardinalTrialAssetsError'; this.code = code; } }
const check = (ok, code) => { if (!ok) throw new TrialAssetsError(code); };
function keys(value, expected) {
  check(value !== null && typeof value === 'object' && Object.getPrototypeOf(value) === Object.prototype
    && Object.keys(value).sort().join(',') === [...expected].sort().join(','), 'UNEXPECTED_TRIAL_FIELDS');
}
function directory(root) {
  check(typeof root === 'string' && path.isAbsolute(root) && path.resolve(root) === root
    && root.split(path.sep).filter(Boolean).length >= 2, 'UNSAFE_TRIAL_DIRECTORY');
  const s = fs.lstatSync(root);
  check(s.isDirectory() && !s.isSymbolicLink() && !(s.mode & 0o022) && fs.realpathSync(root) === root, 'UNSAFE_TRIAL_DIRECTORY');
}
const sameFile = (a, b) => ['dev', 'ino', 'size', 'mode', 'nlink', 'mtimeMs', 'ctimeMs'].every(k => a[k] === b[k]);
function read(root, relative, maximum) {
  directory(root);
  check(typeof relative === 'string' && relative.length < 512 && relative.split('/').every(p =>
    /^[A-Za-z0-9_.-]+$/.test(p) && p !== '.' && p !== '..'), 'UNSAFE_TRIAL_PATH');
  const file = path.join(root, relative), parent = path.dirname(file); directory(parent);
  const before = fs.lstatSync(file);
  check(before.isFile() && !before.isSymbolicLink() && before.nlink === 1 && !(before.mode & 0o022)
    && before.size > 0 && before.size <= maximum, 'UNSAFE_TRIAL_FILE');
  const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
  try {
    const opened = fs.fstatSync(fd); check(sameFile(before, opened), 'TRIAL_INPUT_CHANGED');
    const bytes = Buffer.alloc(opened.size + 1); let size = 0, n;
    while (size < bytes.length && (n = fs.readSync(fd, bytes, size, bytes.length - size, null)) > 0) size += n;
    check(size === opened.size && sameFile(opened, fs.fstatSync(fd)) && sameFile(opened, fs.lstatSync(file))
      && fs.realpathSync(parent) === parent, 'TRIAL_INPUT_CHANGED');
    return bytes.subarray(0, size);
  } finally { fs.closeSync(fd); }
}
const timestamp = value => typeof value === 'string' && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(value)
  && Number.isFinite(Date.parse(value)) && new Date(value).toISOString() === value;
function diagnostics(value, success) {
  if (value === null && !success) return;
  keys(value, ['candidate_count', 'first_candidate_part_count', 'inline_audio_parts', 'text_parts',
    'finish_reason', 'prompt_block_reason', 'first_candidate_finish_message_present']);
  for (const k of ['candidate_count', 'first_candidate_part_count', 'inline_audio_parts', 'text_parts']) {
    check(Number.isInteger(value[k]) && value[k] >= 0 && value[k] <= 1000,
      'INVALID_TRIAL_RESPONSE_DIAGNOSTICS');
  }
  check(typeof value.first_candidate_finish_message_present === 'boolean'
    && ['STOP', 'MAX_TOKENS', 'SAFETY', 'RECITATION', 'LANGUAGE', 'OTHER', 'BLOCKLIST', 'PROHIBITED_CONTENT', 'SPII',
      'MALFORMED_FUNCTION_CALL', 'IMAGE_SAFETY', 'UNEXPECTED_TOOL_CALL', 'TOO_MANY_TOOL_CALLS', 'IMAGE_PROHIBITED_CONTENT',
      'NO_IMAGE', 'IMAGE_RECITATION', 'IMAGE_OTHER', 'FINISH_REASON_UNSPECIFIED', 'UNKNOWN'].includes(value.finish_reason)
    && [null, 'BLOCK_REASON_UNSPECIFIED', 'SAFETY', 'OTHER', 'BLOCKLIST', 'PROHIBITED_CONTENT', 'IMAGE_SAFETY', 'UNKNOWN']
      .includes(value.prompt_block_reason),
  'INVALID_TRIAL_RESPONSE_DIAGNOSTICS');
  if (success) check(value.candidate_count === 1 && value.first_candidate_part_count === 1
    && value.inline_audio_parts === 1 && value.text_parts === 0 && value.finish_reason === 'STOP'
    && value.prompt_block_reason === null && value.first_candidate_finish_message_present === false, 'UNACCEPTED_TRIAL_RESPONSE');
}
function mime(value, success) {
  if ((value === undefined || value === null) && !success) return;
  keys(value, ['present', 'media_type', 'rate', 'channels', 'codec', 'malformed_parameters',
    'duplicate_parameters', 'unknown_parameters', 'accepted']);
  for (const k of ['present', 'malformed_parameters', 'duplicate_parameters', 'unknown_parameters', 'accepted'])
    check(typeof value[k] === 'boolean', 'INVALID_TRIAL_AUDIO_FORMAT');
  for (const [k, allowed] of [['media_type', [null, 'UNKNOWN', 'audio/l16']],
    ['rate', [null, 'UNKNOWN', '8000', '16000', '24000', '44100', '48000']],
    ['channels', [null, 'UNKNOWN', '1', '2']], ['codec', [null, 'UNKNOWN', 'pcm']]])
    check(allowed.includes(value[k]), 'INVALID_TRIAL_AUDIO_FORMAT');
  const accepted = value.present && value.media_type === 'audio/l16' && value.rate === '24000'
    && [null, '1'].includes(value.channels) && [null, 'pcm'].includes(value.codec)
    && (value.channels === '1' || value.codec === 'pcm')
    && !value.malformed_parameters && !value.duplicate_parameters && !value.unknown_parameters;
  check(value.accepted === accepted && (!success || accepted), 'UNACCEPTED_TRIAL_AUDIO_FORMAT');
}
function openResolution(options) {
  keys(options, ['sourceDirectory', 'sourceManifestSha256', 'approvalSha256', 'trials']);
  const {sourceDirectory, sourceManifestSha256, approvalSha256, trials} = options;
  check(sha(sourceManifestSha256) && sha(approvalSha256), 'INDEPENDENT_SOURCE_PINS_REQUIRED');
  check(Array.isArray(trials) && trials.length >= 1 && trials.length <= MAX_TRIALS, 'BOUNDED_TRIAL_ALLOWLIST_REQUIRED');
  const paths = new Set(), hashes = new Set();
  let fr89Reservations = 0;
  for (const item of trials) {
    keys(item, ['directory', 'sha256']);
    check(sha(item.sha256) && typeof item.directory === 'string' && !paths.has(item.directory)
      && !hashes.has(item.sha256), 'DUPLICATE_OR_UNPINNED_TRIAL');
    directory(item.directory);
    check(item.directory !== sourceDirectory && !item.directory.startsWith(sourceDirectory + '/'), 'TRIAL_SOURCE_PATH_OVERLAP');
    paths.add(item.directory); hashes.add(item.sha256);
  }
  const pins = [], remember = (root, relative, maximum, expected) => {
    const bytes = read(root, relative, maximum), actual = hash(bytes);
    check(expected === undefined || actual === expected, 'TRIAL_INPUT_PIN_MISMATCH');
    pins.push({root, relative, maximum, sha256: actual}); return bytes;
  };
  function assertUnchanged() {
    try { fs.lstatSync(path.join(sourceDirectory, '.generation.lock')); throw new TrialAssetsError('SOURCE_AUTHORING_IN_PROGRESS'); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    for (const pin of pins) check(hash(read(pin.root, pin.relative, pin.maximum)) === pin.sha256, 'TRIAL_INPUT_CHANGED');
  }
  remember(sourceDirectory, 'manifest.json', 8 * 1024 * 1024, sourceManifestSha256);
  assertUnchanged();
  const source = pack.readManifest(sourceDirectory);
  check(source.approvals_sha256 === approvalSha256 && !source.prompts.some(e => e.generation_status === 'REQUESTING'),
    'SOURCE_APPROVAL_OR_INFLIGHT_CHANGED');
  const sourceEntries = new Map(source.prompts.map(e => [`${e.locale}/${e.id}`, e]));
  const candidates = new Map(), receipts = [], histories = new Map();
  const topKeys = ['schema_version', 'owner', 'status', 'created_at', 'provider', 'model', 'voice', 'endpoint',
    'source_model', 'source_manifest_sha256', 'source_requests_reserved', 'source_retry_budget', 'catalog_sha256',
    'approvals_sha256', 'request_limit', 'requests_reserved', 'automatic_retries', 'source_history_reset',
    'runtime_ready', 'importable', 'deployed', 'native_listening_approved', 'resampling_recipe_sha256', 'entries'];
  const entryKeys = ['identity', 'locale', 'id', 'transcript', 'transcript_sha256', 'source_entry_sha256',
    'source_attempt_count', 'source_attempt_count_plus_this_trial', 'source_attempts_sha256', 'source_generation_status',
    'synthesis_recipe', 'synthesis_instruction', 'request_body_sha256', 'status', 'reserved_at', 'returned_model_version',
    'response_diagnostics', 'failure_code', 'raw_pcm_sha256', 'master', 'telephony'];
  for (const item of trials) {
    let ledger;
    try { ledger = JSON.parse(remember(item.directory, 'trial.json', 128 * 1024, item.sha256).toString('utf8')); }
    catch (error) { if (error instanceof SyntaxError) throw new TrialAssetsError('INVALID_TRIAL_JSON'); throw error; }
    const oneShot = Object.hasOwn(ledger, 'one_shot_diagnostic');
    keys(ledger, [...topKeys, ...(oneShot ? ['one_shot_diagnostic'] : [])]);
    if (oneShot) {
      keys(ledger.one_shot_diagnostic, Object.keys(fr89));
      check(pack.digest(ledger.one_shot_diagnostic) === pack.digest(fr89)
        && sourceManifestSha256 === fr89.source_manifest_sha256 && approvalSha256 === fr89.approvals_sha256,
      'ONE_SHOT_POLICY_CHANGED');
      check(Array.isArray(ledger.entries) && ledger.entries.length === 1
        && ledger.request_limit === 1 && ledger.requests_reserved === 1
        && ledger.entries[0]?.identity === fr89.identity
        && ['QA_PASSED', 'FAILED'].includes(ledger.entries[0]?.status), 'ONE_SHOT_REQUEST_SCOPE_CHANGED');
      check(++fr89Reservations === 1, 'DUPLICATE_ONE_SHOT_RESERVATION');
    }
    check(ledger.schema_version === 1 && ledger.owner === TRIAL_OWNER && ledger.provider === 'google-gemini'
      && ledger.model === MODEL && ledger.voice === VOICE && ledger.endpoint === ENDPOINT && ledger.source_model === pack.MODEL
      && ledger.source_manifest_sha256 === sourceManifestSha256 && ledger.source_requests_reserved === source.requests_reserved
      && ledger.source_retry_budget === source.retry_request_budget && ledger.catalog_sha256 === pack.CATALOG_HASH
      && ledger.approvals_sha256 === approvalSha256 && ledger.resampling_recipe_sha256 === pack.digest(pack.RESAMPLING)
      && ledger.automatic_retries === 0 && ledger.source_history_reset === false
      && ['runtime_ready', 'importable', 'deployed', 'native_listening_approved'].every(k => ledger[k] === false), 'TRIAL_CONTRACT_CHANGED');
    check(timestamp(ledger.created_at) && ['TRIAL_QA_COMPLETE_NOT_APPROVED', 'STOPPED_ON_FAILURE'].includes(ledger.status), 'NONTERMINAL_TRIAL');
    check(Array.isArray(ledger.entries) && ledger.entries.length >= 1 && ledger.entries.length <= 3
      && ledger.request_limit === ledger.entries.length && Number.isInteger(ledger.requests_reserved)
      && ledger.requests_reserved >= 1 && ledger.requests_reserved <= ledger.request_limit, 'TRIAL_REQUEST_ACCOUNTING_CHANGED');
    const identities = new Set(), outcomes = []; let reserved = 0, failed = false, lastTime = ledger.created_at;
    for (let index = 0; index < ledger.entries.length; index++) {
      const e = ledger.entries[index];
      keys(e, [...entryKeys, ...(Object.hasOwn(e, 'audio_mime_diagnostics') ? ['audio_mime_diagnostics'] : [])]);
      const original = sourceEntries.get(e.identity);
      check(original && (oneShot ? e.identity === fr89.identity : ['he-il', 'ar-sa', 'es-es'].includes(e.locale)) && e.identity === `${e.locale}/${e.id}`
        && original.locale === e.locale && original.id === e.id && !identities.has(e.identity), 'TRIAL_IDENTITY_MISMATCH');
      identities.add(e.identity);
      if (oneShot) check(original.attempts.length === fr89.source_attempt_count
        && original.attempts.every(a => a.status === 'FAILED') && pack.digest(original) === fr89.source_entry_sha256
        && pack.digest(original.attempts) === fr89.source_attempts_sha256
        && original.transcript_sha256 === fr89.transcript_sha256 && MODEL === fr89.model && VOICE === fr89.voice,
      'ONE_SHOT_SOURCE_HISTORY_CHANGED');
      check(original.generation_status === 'FAILED' && original.attempts.length > 0
        && (oneShot || original.attempts.length < pack.HARD_MAX_ATTEMPTS)
        && e.source_generation_status === 'FAILED' && e.source_entry_sha256 === pack.digest(original)
        && e.source_attempts_sha256 === pack.digest(original.attempts) && e.source_attempt_count === original.attempts.length
        && e.source_attempt_count_plus_this_trial === original.attempts.length + 1
        && e.transcript === original.transcript && e.transcript_sha256 === original.transcript_sha256, 'TRIAL_SOURCE_HISTORY_CHANGED');
      pack.requireAuthoringApproval(source, [e.locale], approvalSha256);
      const body = pack.requestBody(original, pack.CONCISE_SYNTHESIS_RECIPE);
      if (oneShot) check(hash(JSON.stringify(body)) === fr89.request_body_sha256, 'ONE_SHOT_REQUEST_BODY_CHANGED');
      check(e.synthesis_recipe === pack.CONCISE_SYNTHESIS_RECIPE && e.synthesis_instruction === body.contents[0].parts[0].text
        && e.request_body_sha256 === hash(JSON.stringify(body)), 'TRIAL_REQUEST_BODY_CHANGED');
      check(['QA_PASSED', 'FAILED', 'SELECTED'].includes(e.status) && (failed ? e.status === 'SELECTED' : e.status !== 'SELECTED'),
        'TRIAL_OUTCOME_SEQUENCE_CHANGED');
      if (e.status === 'SELECTED') {
        check(['reserved_at', 'returned_model_version', 'response_diagnostics', 'failure_code', 'raw_pcm_sha256', 'master', 'telephony']
          .every(k => e[k] === null) && (e.audio_mime_diagnostics === undefined || e.audio_mime_diagnostics === null), 'UNSENT_TRIAL_HAS_OUTCOME');
      } else {
        reserved++;
        check(timestamp(e.reserved_at) && e.reserved_at >= lastTime, 'TRIAL_TIMESTAMP_CHANGED'); lastTime = e.reserved_at;
        check([null, 'UNKNOWN', pack.MODEL, MODEL].includes(e.returned_model_version), 'TRIAL_RETURNED_MODEL_CHANGED');
        diagnostics(e.response_diagnostics, e.status === 'QA_PASSED'); mime(e.audio_mime_diagnostics, e.status === 'QA_PASSED');
        const readAudio = (variant, rate) => {
          const file = `${String(index + 1).padStart(2, '0')}-${e.locale}-${e.id}.${variant === 'master' ? 'master-24000' : 'telephony-8000'}.wav`;
          check(e[variant] && e[variant].file === file && sha(e[variant].sha256), 'TRIAL_AUDIO_PATH_CHANGED');
          const bytes = remember(item.directory, file, 2 * 1024 * 1024, e[variant].sha256);
          const metrics = pack.technicalQa(pack.inspectWave(bytes, rate));
          check(pack.digest(e[variant]) === pack.digest({file, ...metrics}), 'TRIAL_AUDIO_METRICS_CHANGED');
          return bytes;
        };
        if (e.status === 'FAILED') {
          failed = true;
          check(typeof e.failure_code === 'string' && /^[A-Z][A-Z0-9_]{0,79}$/.test(e.failure_code)
            && (e.raw_pcm_sha256 === null || sha(e.raw_pcm_sha256)) && (e.telephony === null || e.master !== null),
          'UNSUPPORTED_FAILED_TRIAL_ARTIFACT');
          // A stopped trial may have saved a hash or a QA-checked master before
          // a later local failure. Verify any retained bytes, never resolve them.
          const master = e.master === null ? null : readAudio('master', 24000);
          const phone = e.telephony === null ? null : readAudio('telephony', 8000);
          check(!master || e.master.pcm_sha256 === e.raw_pcm_sha256, 'TRIAL_AUDIO_RESAMPLING_CHANGED');
          check(!phone || hash(pack.resampleMaster(master)) === e.telephony.pcm_sha256, 'TRIAL_AUDIO_RESAMPLING_CHANGED');
        } else {
          check(e.returned_model_version === MODEL && e.failure_code === null && sha(e.raw_pcm_sha256), 'UNACCEPTED_TRIAL_RESULT');
          check(!candidates.has(e.identity), 'DUPLICATE_TRIAL_SUCCESS');
          const audio = {};
          for (const [variant, rate] of [['master', 24000], ['telephony', 8000]]) {
            audio[variant] = readAudio(variant, rate);
          }
          check(e.master.pcm_sha256 === e.raw_pcm_sha256 && hash(pack.resampleMaster(audio.master)) === e.telephony.pcm_sha256,
            'TRIAL_AUDIO_RESAMPLING_CHANGED');
          const provenance = {trial_manifest_sha256: item.sha256, trial_entry_sha256: pack.digest(e),
            source_manifest_sha256: sourceManifestSha256, source_entry_sha256: e.source_entry_sha256,
            source_attempts_sha256: e.source_attempts_sha256, source_attempt_count: e.source_attempt_count,
            catalog_sha256: pack.CATALOG_HASH, catalog_record_sha256: original.catalog_record_sha256,
            context_sha256: original.context_sha256, approvals_sha256: approvalSha256,
            transcript_sha256: e.transcript_sha256, request_body_sha256: e.request_body_sha256,
            synthesis_recipe: e.synthesis_recipe, provider: 'google-gemini', model: MODEL, voice: VOICE,
            master_sha256: e.master.sha256, telephony_sha256: e.telephony.sha256, telephony_pcm_sha256: e.telephony.pcm_sha256,
            duration_seconds: e.telephony.duration_seconds, resampling_recipe_sha256: ledger.resampling_recipe_sha256};
          if (oneShot) provenance.one_shot_diagnostic = clone(fr89);
          candidates.set(e.identity, {locale: e.locale, id: e.id, transcript: e.transcript,
            source_kind: 'separate_model_trial', ...audio, provenance,
            runtime_ready: false, importable: false, deployed: false, listening_verified: false,
            native_listening_approved: false, provider_provenance_authenticated: false});
        }
        const history = histories.get(e.identity) || [];
        history.push({status: e.status, reserved_at: e.reserved_at}); histories.set(e.identity, history);
      }
      outcomes.push({identity: e.identity, status: e.status, source_attempt_count: e.source_attempt_count,
        additional_trial_requests: e.status === 'SELECTED' ? 0 : 1, failure_code: e.failure_code});
    }
    check(reserved === ledger.requests_reserved && (ledger.status === 'STOPPED_ON_FAILURE' ? failed : !failed
      && reserved === ledger.request_limit), 'TRIAL_REQUEST_ACCOUNTING_CHANGED');
    receipts.push({trial_manifest_sha256: item.sha256, status: ledger.status, requests_reserved: reserved, outcomes,
      ...(oneShot ? {one_shot_diagnostic: clone(fr89)} : {})});
  }
  for (const history of histories.values()) {
    history.sort((a, b) => a.reserved_at.localeCompare(b.reserved_at));
    check(history.every((e, i) => !i || history[i - 1].status !== 'QA_PASSED'
      && history[i - 1].reserved_at !== e.reserved_at), 'CONFLICTING_TRIAL_OUTCOMES');
  }
  const summary = {schema_version: 1, owner: OWNER, model: MODEL, voice: VOICE,
    source_manifest_sha256: sourceManifestSha256, catalog_sha256: pack.CATALOG_HASH, approvals_sha256: approvalSha256,
    source_requests_reserved: source.requests_reserved, source_retry_budget: source.retry_request_budget,
    additional_trial_requests: receipts.reduce((n, r) => n + r.requests_reserved, 0),
    successful_identities: [...candidates.keys()].sort(), trials: receipts,
    source_history_reset: false, runtime_ready: false, importable: false, deployed: false,
    native_listening_approved: false, provider_provenance_authenticated: false};
  assertUnchanged();
  return Object.freeze({
    assertUnchanged,
    sourceManifest() { assertUnchanged(); return clone(source); },
    summary() { assertUnchanged(); return clone(summary); },
    resolve(locale, id) {
      check(typeof locale === 'string' && typeof id === 'string', 'UNKNOWN_TRIAL_IDENTITY');
      assertUnchanged(); const candidate = candidates.get(`${locale}/${id}`);
      check(candidate, 'TRIAL_AUDIO_UNRESOLVED');
      const {master, telephony, ...record} = candidate;
      return {...clone(record), master: Buffer.from(master), telephony: Buffer.from(telephony)};
    }
  });
}
module.exports = Object.freeze({OWNER, MODEL, VOICE, MAX_TRIALS, TrialAssetsError, openResolution});
