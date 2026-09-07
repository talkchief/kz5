#!/usr/bin/env node
'use strict';

// One-time, explicitly authorized authoring only. Never imported by installation,
// account creation, editor or playback. Plan/no-op resume does not load a provider.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const cp = require('node:child_process'), pack = require('./acdc-cardinal-pack.cjs');
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const check = (ok, code) => { if (!ok) throw new pack.PackError(code); };
const locales = Object.keys(pack.LOCALE_HASHES);
const sameInode = (a, b) => a.dev === b.dev && a.ino === b.ino;
const MAX_JSON = 8 * 1024 * 1024;
function absolute(file) { return typeof file === 'string' && path.isAbsolute(file) && path.resolve(file) === file; }
function ownedDirectory(dir, privateMode = false) {
  check(absolute(dir) && fs.realpathSync(dir) === dir, 'DIRECTORY_NOT_CANONICAL');
  const s = fs.lstatSync(dir);
  check(s.isDirectory() && !s.isSymbolicLink() && s.uid === process.getuid()
    && !(s.mode & (privateMode ? 0o077 : 0o022)), 'DIRECTORY_NOT_PROTECTED');
  return s;
}
function readOwned(file, maximum = MAX_JSON) {
  check(absolute(file) && fs.realpathSync(path.dirname(file)) === path.dirname(file), 'FILE_NOT_CANONICAL');
  const before = fs.lstatSync(file);
  check(before.isFile() && !before.isSymbolicLink() && before.nlink === 1 && before.uid === process.getuid()
    && !(before.mode & 0o022) && before.size > 0 && before.size <= maximum, 'FILE_NOT_PROTECTED');
  const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
  try {
    const s = fs.fstatSync(fd); check(sameInode(before, s) && s.size === before.size, 'FILE_CHANGED');
    const b = Buffer.alloc(s.size + 1); let length = 0, n;
    while (length < b.length && (n = fs.readSync(fd, b, length, b.length - length, null)) > 0) length += n;
    const after = fs.fstatSync(fd), named = fs.lstatSync(file);
    check(length === s.size && sameInode(s, named) && s.size === after.size && s.mtimeMs === after.mtimeMs
      && s.ctimeMs === after.ctimeMs && fs.realpathSync(path.dirname(file)) === path.dirname(file), 'FILE_CHANGED');
    return b.subarray(0, length);
  } finally { fs.closeSync(fd); }
}
function absent(file) {
  try { fs.lstatSync(file); return false; } catch (e) { if (e.code === 'ENOENT') return true; throw e; }
}
function outputTarget(dir, resume) {
  check(absolute(dir) && (dir.startsWith('/tmp/') || dir.startsWith('/usr/local/src/kazoo5-installer/'))
    && dir.split('/').filter(Boolean).length >= 2, 'PRIVATE_AUTHORING_OUTPUT_REQUIRED');
  if (resume) return ownedDirectory(dir, true);
  check(absent(dir), 'OUTPUT_ALREADY_EXISTS');
  const parent = path.dirname(dir);
  check(fs.realpathSync(parent) === parent && fs.lstatSync(parent).isDirectory(), 'OUTPUT_PARENT_NOT_REAL');
  if (parent !== '/tmp') ownedDirectory(parent);
  return null;
}
function syncDirectory(dir) {
  const fd = fs.openSync(dir, fs.constants.O_RDONLY | fs.constants.O_DIRECTORY | fs.constants.O_NOFOLLOW);
  try { fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
}
function writeNew(file, bytes) {
  const fd = fs.openSync(file, fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_NOFOLLOW, 0o600);
  try { fs.writeFileSync(fd, bytes); fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
  syncDirectory(path.dirname(file));
}
function atomicJson(directory, name, value, previousHash) {
  check(name === 'manifest.json' || /^run-[a-f0-9-]{36}\.json$/.test(name), 'UNEXPECTED_RECEIPT_NAME');
  const target = path.join(directory, name), bytes = Buffer.from(JSON.stringify(value, null, 2) + '\n');
  check(bytes.length <= MAX_JSON, 'MANIFEST_TOO_LARGE');
  const unchanged = () => previousHash === null ? absent(target) : hash(readOwned(target)) === previousHash;
  check(unchanged(), 'MANIFEST_CHANGED_OUTSIDE_LOCK');
  const temporary = path.join(directory, `.cardinal-${crypto.randomUUID()}.tmp`);
  writeNew(temporary, bytes);
  check(unchanged(), 'MANIFEST_CHANGED_OUTSIDE_LOCK');
  fs.renameSync(temporary, target); syncDirectory(directory);
  return hash(bytes);
}
function readApprovals(file, trustedHash) {
  check(absolute(file) && /^[a-f0-9]{64}$/.test(trustedHash || ''), 'PINNED_APPROVAL_FILE_REQUIRED');
  let value;
  try { value = JSON.parse(readOwned(file, 256 * 1024)); } catch (e) { if (e instanceof pack.PackError) throw e; throw new pack.PackError('INVALID_APPROVAL_JSON'); }
  check(value && Object.keys(value).sort().join(',') === 'approvals,approvals_sha256,catalog_sha256,schema_version'
    && value.schema_version === 1 && value.catalog_sha256 === pack.CATALOG_HASH
    && value.approvals_sha256 === trustedHash && pack.digest(value.approvals) === trustedHash, 'APPROVAL_FILE_CHANGED');
  return value;
}
function applyApprovals(manifest, approved, selected) {
  // Once any attempt exists, that locale's authoring approval cannot be replaced.
  // Other untouched locales may acquire separately reviewed approvals on resume.
  for (const locale of locales) if (manifest.prompts.some(p => p.locale === locale && p.attempts.length)) {
    const old = manifest.approvals.find(a => a.locale === locale), next = approved.approvals.find(a => a.locale === locale);
    check(next && pack.digest(old) === pack.digest(next), 'ATTEMPTED_LOCALE_APPROVAL_CHANGED');
  }
  manifest.approvals = approved.approvals; manifest.approvals_sha256 = approved.approvals_sha256;
  pack.requireAuthoringApproval(manifest, selected, approved.approvals_sha256);
}
function preflightSox() {
  const result = cp.spawnSync(pack.RESAMPLING.tool, ['--version'], {encoding: 'utf8', shell: false,
    env: {PATH: '/usr/bin:/bin', LC_ALL: 'C', TZ: 'UTC'}, timeout: 5000, maxBuffer: 4096});
  check(!result.error && result.status === 0 && result.signal === null && result.stderr === ''
    && /^(?:\/usr\/bin\/)?sox:\s+SoX v14\.4\.2$/.test(result.stdout.trim()), 'SOX_PREFLIGHT_FAILED');
}
function safeCode(error, provider) {
  return error instanceof pack.PackError || provider?.SampleError && error instanceof provider.SampleError
    ? error.code : 'LOCAL_OPERATION_FAILED';
}
function finishReason(response) {
  const reason = response?.candidates?.[0]?.finishReason;
  return ['STOP', 'MAX_TOKENS', 'SAFETY', 'RECITATION', 'LANGUAGE', 'OTHER', 'BLOCKLIST', 'PROHIBITED_CONTENT', 'SPII',
    'MALFORMED_FUNCTION_CALL', 'IMAGE_SAFETY', 'UNEXPECTED_TOOL_CALL', 'TOO_MANY_TOOL_CALLS', 'IMAGE_PROHIBITED_CONTENT',
    'NO_IMAGE', 'IMAGE_RECITATION', 'IMAGE_OTHER', 'FINISH_REASON_UNSPECIFIED'].includes(reason) ? reason : 'UNKNOWN';
}
function options(argv) {
  const o = {mode: 'plan', locales: [...locales], concurrency: 1, resume: false, retryFailed: false}, seen = new Set();
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]; check(!seen.has(arg), 'DUPLICATE_OPTION'); seen.add(arg);
    if (['--plan', '--generate', '--verify-only'].includes(arg)) {
      check(!seen.has('MODE'), 'CONFLICTING_MODES'); seen.add('MODE'); o.mode = arg.slice(2);
    } else if (arg === '--resume') o.resume = true;
    else if (arg === '--retry-failed') o.retryFailed = true;
    else {
      const key = {'--output': 'output', '--key-file': 'keyFile', '--approval-file': 'approvalFile', '--approval-sha256': 'approvalHash',
        '--locales': 'locales', '--concurrency': 'concurrency', '--request-limit': 'requestLimit', '--retry-budget': 'retryBudget',
        '--attempt-limit': 'attemptLimit'}[arg];
      check(key && argv[i + 1] && !argv[i + 1].startsWith('--'), 'UNKNOWN_OR_INCOMPLETE_OPTION'); o[key] = argv[++i];
    }
  }
  if (typeof o.locales === 'string') o.locales = o.locales.split(',');
  check(o.locales.length > 0 && new Set(o.locales).size === o.locales.length && o.locales.every(l => locales.includes(l)), 'INVALID_LOCALE_SELECTION');
  const integer = (value, maximum) => /^(?:[1-9][0-9]*)$/.test(String(value)) && Number(value) <= maximum;
  check(integer(o.concurrency, 2), 'INVALID_CONCURRENCY'); o.concurrency = Number(o.concurrency);
  if (o.requestLimit !== undefined) { check(integer(o.requestLimit, 584), 'INVALID_REQUEST_LIMIT'); o.requestLimit = Number(o.requestLimit); }
  if (o.retryBudget !== undefined) { check(integer(o.retryBudget, 584), 'INVALID_RETRY_BUDGET'); o.retryBudget = Number(o.retryBudget); }
  check(!o.resume || o.mode === 'generate', 'RESUME_REQUIRES_GENERATE');
  check(!o.retryFailed || o.resume && o.mode === 'generate' && o.retryBudget !== undefined, 'EXPLICIT_RETRY_BUDGET_REQUIRED');
  check(o.retryBudget === undefined || o.retryFailed, 'RETRY_BUDGET_WITHOUT_RETRY');
  if (o.attemptLimit !== undefined) {
    check(integer(o.attemptLimit, pack.HARD_MAX_ATTEMPTS) && Number(o.attemptLimit) >= pack.MAX_ATTEMPTS, 'INVALID_ATTEMPT_LIMIT');
    o.attemptLimit = Number(o.attemptLimit);
    check(o.mode === 'generate' && o.resume && o.retryFailed && o.retryBudget !== undefined,
      'ATTEMPT_LIMIT_REQUIRES_EXPLICIT_RECOVERY');
  }
  if (o.mode !== 'plan') check(absolute(o.output), 'ABSOLUTE_OUTPUT_REQUIRED');
  if (o.mode === 'generate') check(o.requestLimit !== undefined, 'EXPLICIT_REQUEST_LIMIT_REQUIRED');
  return o;
}
function summary(manifest, selected, requested = 0) {
  const wanted = manifest.prompts.filter(p => selected.includes(p.locale));
  return {schema_version: 1, mode: 'AUTHORING_ONLY', catalog_sha256: pack.CATALOG_HASH,
    selected_locales: selected, selected_roles: wanted.length, selected_qa_passed: wanted.filter(p => p.generation_status === 'QA_PASSED').length,
    selected_complete: wanted.every(p => p.generation_status === 'QA_PASSED'), artifact_complete: manifest.artifact_complete,
    requests_this_run: requested, requests_reserved: manifest.requests_reserved, approvals_sha256: manifest.approvals_sha256,
    runtime_ready: false, deployed: false, native_speaker_review: false, audio_listening_review: false,
    intro_audio_verified: false, full_position_numeric_range_ready: false};
}
async function generate(o, deps = {}) {
  check(o.mode === 'generate' && Number.isInteger(o.requestLimit) && o.requestLimit >= 1 && o.requestLimit <= 584
    && [1, 2].includes(o.concurrency) && Array.isArray(o.locales) && o.locales.length > 0
    && new Set(o.locales).size === o.locales.length && o.locales.every(l => locales.includes(l)), 'INVALID_GENERATION_OPTIONS');
  check(!o.retryFailed || o.resume && Number.isInteger(o.retryBudget) && o.retryBudget > 0 && o.retryBudget <= 584,
    'EXPLICIT_RETRY_BUDGET_REQUIRED');
  check(o.retryBudget === undefined || o.retryFailed, 'RETRY_BUDGET_WITHOUT_RETRY');
  if (o.attemptLimit !== undefined) {
    check(Number.isInteger(o.attemptLimit) && o.attemptLimit >= pack.MAX_ATTEMPTS
      && o.attemptLimit <= pack.HARD_MAX_ATTEMPTS, 'INVALID_ATTEMPT_LIMIT');
    check(o.resume && o.retryFailed && Number.isInteger(o.retryBudget), 'ATTEMPT_LIMIT_REQUIRES_EXPLICIT_RECOVERY');
  }
  const attemptLimit = o.attemptLimit ?? pack.MAX_ATTEMPTS;
  outputTarget(o.output, !!o.resume);
  // A rejected fresh approval must not strand an empty output directory: it
  // has no manifest to resume, and a new invocation must never overwrite it.
  // Resume still reads/applies approvals only while holding its existing lock.
  let initialManifest;
  if (!o.resume) {
    check(absolute(o.keyFile) && !o.keyFile.startsWith(o.output + '/'), 'PROTECTED_EXTERNAL_KEY_PATH_REQUIRED');
    initialManifest = pack.createManifest();
    applyApprovals(initialManifest, readApprovals(o.approvalFile, o.approvalHash), o.locales);
  }
  if (!o.resume) { fs.mkdirSync(o.output, {mode: 0o700}); syncDirectory(path.dirname(o.output)); }
  const root = ownedDirectory(o.output, true), lockFile = path.join(o.output, '.generation.lock'); let lock, provider, key;
  try { lock = fs.openSync(lockFile, fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_NOFOLLOW, 0o600); }
  catch (_) { throw new pack.PackError('GENERATION_LOCKED'); }
  const lockStat = fs.fstatSync(lock), checkRoot = () => check(sameInode(root, ownedDirectory(o.output, true)), 'OUTPUT_DIRECTORY_CHANGED');
  let m, manifestHash, run, runName, runHash = null;
  const save = () => {
    checkRoot(); m.artifact_complete = m.prompts.every(p => p.generation_status === 'QA_PASSED');
    manifestHash = atomicJson(o.output, 'manifest.json', m, manifestHash);
  };
  const saveRun = () => { checkRoot(); runHash = atomicJson(o.output, runName, run, runHash); };
  try {
    m = o.resume ? pack.readManifest(o.output) : initialManifest;
    manifestHash = o.resume ? hash(readOwned(path.join(o.output, 'manifest.json'))) : null;
    const selected = m.prompts.filter(p => o.locales.includes(p.locale));
    check(!selected.some(p => p.generation_status === 'REQUESTING'), 'INDETERMINATE_REQUEST_REQUIRES_RECONCILIATION');
    // Snapshot candidates once. A failure in this run never schedules itself.
    const jobs = selected.filter(p => p.generation_status === 'PENDING'
      || o.retryFailed && p.generation_status === 'FAILED' && p.attempts.length < attemptLimit).slice(0, o.requestLimit);
    if (!jobs.length) {
      check(selected.every(p => p.generation_status === 'QA_PASSED'), 'INCOMPLETE_SELECTION_REQUIRES_EXPLICIT_RETRY');
      return summary(m, o.locales); // No provider load, key read or approval rewrite.
    }
    check(absolute(o.keyFile) && !o.keyFile.startsWith(o.output + '/'), 'PROTECTED_EXTERNAL_KEY_PATH_REQUIRED');
    if (o.resume) applyApprovals(m, readApprovals(o.approvalFile, o.approvalHash), o.locales);
    if (o.retryFailed) {
      check(o.retryBudget >= m.retry_request_budget, 'RETRY_BUDGET_CANNOT_DECREASE');
      m.retry_request_budget = o.retryBudget; m.retries_explicitly_enabled = true;
    }
    const retriesUsed = m.prompts.reduce((sum, p) => sum + Math.max(0, p.attempts.length - 1), 0);
    check(retriesUsed + jobs.filter(p => p.attempts.length).length <= m.retry_request_budget, 'RETRY_BUDGET_EXHAUSTED');
    const directories = new Map();
    for (const locale of o.locales) {
      const dir = path.join(o.output, locale);
      if (absent(dir)) { fs.mkdirSync(dir, {mode: 0o700}); syncDirectory(o.output); }
      directories.set(locale, ownedDirectory(dir, true));
    }
    const checkLocale = locale => { checkRoot(); check(sameInode(directories.get(locale), ownedDirectory(path.join(o.output, locale), true)), 'LOCALE_DIRECTORY_CHANGED'); };
    for (const e of jobs) for (const variant of ['master', 'telephony'])
      check(absent(path.join(o.output, pack.fileName(e, e.attempts.length + 1, variant))), 'ATTEMPT_AUDIO_ALREADY_EXISTS');
    preflightSox(); m.conversion.version = pack.RESAMPLING.version;
    runName = `run-${crypto.randomUUID()}.json`;
    run = {schema_version: 1, owner: 'kazoo5-cardinal-authoring-run', catalog_sha256: pack.CATALOG_HASH,
      approvals_sha256: m.approvals_sha256, selected_locales: o.locales, request_limit: o.requestLimit,
      concurrency: o.concurrency, explicit_retry: !!o.retryFailed, retry_budget: m.retry_request_budget,
      attempt_limit: attemptLimit, explicit_attempt_limit: o.attemptLimit !== undefined,
      requests_before: m.requests_reserved, requested: 0, status: 'PREPARED', started_at: new Date().toISOString(),
      events: [], runtime_ready: false, deployed: false};
    save(); saveRun();
    provider = (deps.loadProvider || (() => require('./generate-acdc-gemini-samples.cjs')))();
    check(provider.MODEL === pack.MODEL && provider.VOICE === pack.VOICE, 'PROVIDER_HELPER_VERSION_CHANGED');
    key = provider.readProtectedKey(o.keyFile);
    let next = 0, stopped = null, incomplete = false;
    const out = deps.output || (value => console.log(JSON.stringify(value)));
    async function worker() {
      while (!stopped && next < jobs.length) {
        const entry = jobs[next++], body = pack.requestBody(entry), number = entry.attempts.length + 1;
        check(number <= attemptLimit && (entry.generation_status === 'PENDING' && number === 1
          || o.retryFailed && entry.generation_status === 'FAILED' && entry.attempts.at(-1)?.status === 'FAILED'),
        'ATTEMPT_NOT_ELIGIBLE');
        const a = {number, status: 'REQUESTING', reserved_at: new Date().toISOString(),
          synthesis_instruction: body.contents[0].parts[0].text, instruction_sha256: hash(body.contents[0].parts[0].text),
          request_body_sha256: hash(JSON.stringify(body)), failure_code: null, provider_finish_reason: null,
          raw_pcm_sha256: null, master: null, telephony: null};
        checkLocale(entry.locale);
        for (const variant of ['master', 'telephony']) check(absent(path.join(o.output, pack.fileName(entry, number, variant))), 'ATTEMPT_AUDIO_ALREADY_EXISTS');
        entry.attempts.push(a); entry.generation_status = 'REQUESTING'; m.requests_reserved++; run.requested++;
        check(run.requested <= o.requestLimit && m.requests_reserved <= m.initial_request_budget + m.retry_request_budget, 'REQUEST_BUDGET_EXHAUSTED');
        save(); // File AND parent directory fsynced before provider transport.
        run.status = 'IN_PROGRESS'; saveRun();
        let returnedModelVersion = null;
        try {
          const response = await provider.requestSpeech(body, key); a.provider_finish_reason = finishReason(response);
          if (typeof response.modelVersion === 'string' && /^gemini-[A-Za-z0-9._-]{1,120}$/.test(response.modelVersion)) returnedModelVersion = response.modelVersion;
          const pcm = provider.extractPcm(response); a.raw_pcm_sha256 = hash(pcm);
          const master = provider.makeWave(pcm, 24000); checkLocale(entry.locale);
          const masterFile = pack.fileName(entry, number, 'master'); writeNew(path.join(o.output, masterFile), master);
          a.master = {file: masterFile, ...pack.inspectWave(master, 24000)}; pack.technicalQa(a.master);
          const phone = provider.makeWave(pack.resampleMaster(master), 8000), phoneFile = pack.fileName(entry, number, 'telephony');
          checkLocale(entry.locale); writeNew(path.join(o.output, phoneFile), phone);
          a.telephony = {file: phoneFile, ...pack.inspectWave(phone, 8000)}; pack.technicalQa(a.telephony);
          a.status = entry.generation_status = 'QA_PASSED'; pack.verifyEntry(o.output, entry);
        } catch (e) {
          const code = safeCode(e, provider); a.status = entry.generation_status = 'FAILED'; a.failure_code = code;
          if (code === 'AUDIO_GENERATION_NOT_COMPLETE') incomplete = true;
          else stopped ||= code;
        }
        save();
        run.events.push({locale: entry.locale, id: entry.id, attempt: number, status: a.status,
          failure_code: a.failure_code, finish_reason: a.provider_finish_reason, returned_model_version: returnedModelVersion,
          telephony_sha256: a.telephony?.sha256 || null}); saveRun();
        out({locale: entry.locale, id: entry.id, attempt: number, status: a.status,
          requests_this_run: run.requested, requests_reserved: m.requests_reserved});
      }
    }
    const results = await Promise.allSettled(Array.from({length: o.concurrency}, () => worker().catch(e => { stopped ||= safeCode(e, provider); throw e; })));
    if (results.some(r => r.status === 'rejected')) throw new pack.PackError(stopped);
    run.status = stopped ? 'STOPPED_ON_FAILURE' : incomplete ? 'INCOMPLETE_RESPONSE' : 'BATCH_COMPLETE';
    run.finished_at = new Date().toISOString(); saveRun();
    // Re-read exact bytes and replay SoX once more before a successful handoff.
    const verified = pack.readManifest(o.output);
    if (stopped) throw new pack.PackError(stopped);
    if (incomplete) throw new pack.PackError('INCOMPLETE_RESPONSE_REQUIRES_EXPLICIT_RETRY');
    return summary(verified, o.locales, run.requested);
  } catch (e) {
    if (run) {
      run.status = 'FAILED'; run.failure_code = safeCode(e, provider); run.finished_at = new Date().toISOString();
      try { saveRun(); } catch (_) { /* Preserve the first error and any partial receipt; never overwrite drift. */ }
    }
    throw new pack.PackError(safeCode(e, provider));
  } finally {
    key = undefined;
    try {
      checkRoot(); check(sameInode(lockStat, fs.lstatSync(lockFile)), 'GENERATION_LOCK_CHANGED');
      fs.unlinkSync(lockFile); syncDirectory(o.output);
    } finally { fs.closeSync(lock); }
  }
}
async function main(argv) {
  const o = options(argv);
  if (o.mode === 'generate') console.log(JSON.stringify(await generate(o)));
  else if (o.mode === 'verify-only') console.log(JSON.stringify(pack.verifyPack(o.output, o.approvalHash)));
  else console.log(JSON.stringify({mode: 'PLAN_ONLY_NO_PROVIDER', catalog_sha256: pack.CATALOG_HASH,
    prompts: pack.plan().filter(p => o.locales.includes(p.locale)), approvals: pack.createManifest().approvals,
    initial_request_capacity: 584, automatic_retries: 0, runtime_ready: false, deployed: false}));
}
module.exports = Object.freeze({options, readApprovals, outputTarget, generate, main});
if (require.main === module) main(process.argv.slice(2)).catch(e => {
  console.error(`Cardinal authoring stopped: ${e instanceof pack.PackError ? e.code : 'LOCAL_OPERATION_FAILED'}. No live media was imported.`);
  process.exitCode = 1;
});
