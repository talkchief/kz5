#!/usr/bin/env node
'use strict';

// Release-authoring only. No provider load/key read for plan, verify or complete
// resume. Exactly two initial identities; serial, at most one explicit retry each.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const cp = require('node:child_process'), pack = require('./acdc-cardinal-intro-pack.cjs');
const cardinal = require('./acdc-cardinal-pack.cjs');
const {check, hash} = pack;
const inode = (a, b) => a.dev === b.dev && a.ino === b.ino;
function absent(file) {
  try { fs.lstatSync(file); return false; } catch (e) { if (e.code === 'ENOENT') return true; throw e; }
}
function outputTarget(dir, resume) {
  check(pack.absolute(dir) && (dir.startsWith('/tmp/') || dir.startsWith('/usr/local/src/kazoo5-installer/')),
    'PRIVATE_INTRO_OUTPUT_REQUIRED');
  if (resume) return pack.directory(dir, true);
  check(absent(dir), 'INTRO_OUTPUT_ALREADY_EXISTS');
  const parent = path.dirname(dir);
  check(fs.realpathSync(parent) === parent && fs.lstatSync(parent).isDirectory(), 'INTRO_OUTPUT_PARENT_NOT_REAL');
  if (parent !== '/tmp') pack.directory(parent);
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
function atomicJson(dir, name, value, previous) {
  check(name === 'manifest.json' || /^run-[a-f0-9-]{36}\.json$/.test(name), 'INVALID_INTRO_RECEIPT_NAME');
  const target = path.join(dir, name), bytes = Buffer.from(JSON.stringify(value, null, 2) + '\n');
  check(bytes.length <= 256 * 1024, 'INTRO_MANIFEST_TOO_LARGE');
  const unchanged = () => previous === null ? absent(target) : hash(pack.readBytes(target)) === previous;
  check(unchanged(), 'INTRO_MANIFEST_CHANGED_OUTSIDE_LOCK');
  const temporary = path.join(dir, `.intro-${crypto.randomUUID()}.tmp`);
  writeNew(temporary, bytes); check(unchanged(), 'INTRO_MANIFEST_CHANGED_OUTSIDE_LOCK');
  fs.renameSync(temporary, target); syncDirectory(dir); return hash(bytes);
}
function readReview(file, trusted) {
  check(pack.absolute(file) && /^[a-f0-9]{64}$/.test(trusted || ''), 'PINNED_INTRO_REVIEW_REQUIRED');
  return pack.validateReview(pack.jsonFile(file), trusted);
}
function preflightSox() {
  const r = cp.spawnSync(pack.RESAMPLING.tool, ['--version'], {encoding: 'utf8', shell: false,
    env: {PATH: '/usr/bin:/bin', LC_ALL: 'C', TZ: 'UTC'}, timeout: 5000, maxBuffer: 4096});
  check(!r.error && r.status === 0 && r.signal === null && r.stderr === ''
    && /^(?:\/usr\/bin\/)?sox:\s+SoX v14\.4\.2$/.test(r.stdout.trim()), 'INTRO_SOX_PREFLIGHT_FAILED');
}
function options(argv) {
  const o = {mode: 'plan', resume: false, retryFailed: false}, seen = new Set();
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]; check(!seen.has(arg), 'DUPLICATE_INTRO_OPTION'); seen.add(arg);
    if (['--plan', '--generate', '--verify-only'].includes(arg)) {
      check(!seen.has('MODE'), 'CONFLICTING_INTRO_MODES'); seen.add('MODE'); o.mode = arg.slice(2);
    } else if (arg === '--resume') o.resume = true;
    else if (arg === '--retry-failed') o.retryFailed = true;
    else {
      const key = {'--output': 'output', '--key-file': 'keyFile', '--review-file': 'reviewFile',
        '--review-sha256': 'reviewHash', '--request-limit': 'requestLimit', '--retry-budget': 'retryBudget'}[arg];
      check(key && argv[i + 1] && !argv[i + 1].startsWith('--'), 'UNKNOWN_INTRO_OPTION'); o[key] = argv[++i];
    }
  }
  for (const key of ['requestLimit', 'retryBudget']) if (o[key] !== undefined) {
    check(/^[12]$/.test(String(o[key])), 'INVALID_INTRO_REQUEST_BOUND'); o[key] = Number(o[key]);
  }
  check(!o.resume || o.mode === 'generate', 'INTRO_RESUME_REQUIRES_GENERATE');
  check(!o.retryFailed || o.resume && o.retryBudget !== undefined, 'EXPLICIT_INTRO_RETRY_BUDGET_REQUIRED');
  check(o.retryBudget === undefined || o.retryFailed, 'INTRO_RETRY_BUDGET_WITHOUT_RETRY');
  if (o.mode !== 'plan') check(pack.absolute(o.output), 'ABSOLUTE_INTRO_OUTPUT_REQUIRED');
  if (o.mode === 'generate') check([1, 2].includes(o.requestLimit), 'EXPLICIT_INTRO_REQUEST_LIMIT_REQUIRED');
  return o;
}
function safeCode(error, provider) {
  return error instanceof pack.PackError || provider?.SampleError && error instanceof provider.SampleError
    ? error.code : 'LOCAL_INTRO_OPERATION_FAILED';
}
function summary(m, requests) {
  return {schema_version: 1, catalog_sha256: pack.CATALOG_HASH, count: 2,
    qa_passed: m.prompts.filter(p => p.generation_status === 'QA_PASSED').length, artifact_complete: m.artifact_complete,
    requests_this_run: requests, requests_reserved: m.requests_reserved, source_review_sha256: m.source_review_sha256,
    native_speaker_review: false, audio_listening_review: false, runtime_ready: false, deployed: false};
}
async function generate(o, deps = {}) {
  check(o.mode === 'generate' && [1, 2].includes(o.requestLimit), 'EXPLICIT_INTRO_REQUEST_LIMIT_REQUIRED');
  check(!o.retryFailed || o.resume && [1, 2].includes(o.retryBudget), 'EXPLICIT_INTRO_RETRY_BUDGET_REQUIRED');
  check(o.retryBudget === undefined || o.retryFailed, 'INTRO_RETRY_BUDGET_WITHOUT_RETRY');
  outputTarget(o.output, !!o.resume);
  let initial;
  const checkKeyPath = () => check(pack.absolute(o.keyFile) && !o.keyFile.startsWith(o.output + '/'), 'EXTERNAL_INTRO_KEY_PATH_REQUIRED');
  if (!o.resume) {
    checkKeyPath(); initial = pack.createManifest(readReview(o.reviewFile, o.reviewHash));
    preflightSox(); // All fresh text/tool preflight precedes output creation.
    fs.mkdirSync(o.output, {mode: 0o700}); syncDirectory(path.dirname(o.output));
  }
  const root = pack.directory(o.output, true), lockFile = path.join(o.output, '.generation.lock'); let lock;
  try { lock = fs.openSync(lockFile, fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_NOFOLLOW, 0o600); }
  catch (_) { throw new pack.PackError('INTRO_GENERATION_LOCKED'); }
  const lockStat = fs.fstatSync(lock), checkRoot = () => check(inode(root, pack.directory(o.output, true)), 'INTRO_OUTPUT_DIRECTORY_CHANGED');
  let m, manifestHash, provider, key, run, runName, runHash = null;
  const save = () => {
    checkRoot(); m.artifact_complete = m.prompts.every(p => p.generation_status === 'QA_PASSED');
    manifestHash = atomicJson(o.output, 'manifest.json', m, manifestHash);
  };
  const saveRun = () => { checkRoot(); runHash = atomicJson(o.output, runName, run, runHash); };
  try {
    m = o.resume ? pack.readManifest(o.output) : initial;
    manifestHash = o.resume ? hash(pack.readBytes(path.join(o.output, 'manifest.json'))) : null;
    check(!m.prompts.some(p => p.generation_status === 'REQUESTING'), 'INDETERMINATE_INTRO_REQUEST_REQUIRES_RECONCILIATION');
    const jobs = m.prompts.filter(p => p.generation_status === 'PENDING'
      || o.retryFailed && p.generation_status === 'FAILED' && p.attempts.length === 1).slice(0, o.requestLimit);
    if (!jobs.length) {
      check(m.artifact_complete, 'INCOMPLETE_INTROS_REQUIRE_EXPLICIT_RETRY');
      return summary(m, 0); // Full verification already ran; no key/provider/review read or manifest write.
    }
    checkKeyPath();
    if (o.resume) {
      const reviewed = readReview(o.reviewFile, o.reviewHash);
      check(pack.digest(reviewed) === m.source_review_sha256, 'INTRO_AUTHORING_REVIEW_CHANGED');
      preflightSox();
    }
    if (o.retryFailed) {
      check(o.retryBudget >= m.retry_request_budget, 'INTRO_RETRY_BUDGET_CANNOT_DECREASE');
      m.retry_request_budget = o.retryBudget;
    }
    const used = m.prompts.reduce((n, p) => n + Math.max(0, p.attempts.length - 1), 0);
    check(used + jobs.filter(p => p.attempts.length).length <= m.retry_request_budget, 'INTRO_RETRY_BUDGET_EXHAUSTED');
    const dirs = new Map();
    for (const p of jobs) {
      const dir = path.join(o.output, p.locale);
      if (absent(dir)) { fs.mkdirSync(dir, {mode: 0o700}); syncDirectory(o.output); }
      dirs.set(p.locale, pack.directory(dir, true));
      for (const variant of ['master', 'telephony']) check(absent(path.join(o.output, pack.fileName(p, p.attempts.length + 1, variant))), 'INTRO_ATTEMPT_FILE_EXISTS');
    }
    const checkLocale = locale => { checkRoot(); check(inode(dirs.get(locale), pack.directory(path.join(o.output, locale), true)), 'INTRO_LOCALE_DIRECTORY_CHANGED'); };
    runName = `run-${crypto.randomUUID()}.json`;
    run = {schema_version: 1, owner: pack.OWNER, catalog_sha256: pack.CATALOG_HASH,
      source_review_sha256: m.source_review_sha256, status: 'PREPARED', started_at: new Date().toISOString(),
      request_limit: o.requestLimit, explicit_retry: !!o.retryFailed, retry_budget: m.retry_request_budget,
      requests_before: m.requests_reserved, requested: 0, events: [], runtime_ready: false, deployed: false};
    save(); saveRun();
    provider = (deps.loadProvider || (() => require('./generate-acdc-gemini-samples.cjs')))();
    check(provider.MODEL === pack.MODEL && provider.VOICE === pack.VOICE, 'INTRO_PROVIDER_HELPER_CHANGED');
    key = provider.readProtectedKey(o.keyFile);
    const out = deps.output || (value => console.log(JSON.stringify(value))); let stopped, incomplete = false;
    for (const p of jobs) {
      const body = pack.requestBody(p), number = p.attempts.length + 1;
      checkLocale(p.locale);
      for (const variant of ['master', 'telephony']) check(absent(path.join(o.output, pack.fileName(p, number, variant))), 'INTRO_ATTEMPT_FILE_EXISTS');
      const a = {number, status: 'REQUESTING', reserved_at: new Date().toISOString(),
        synthesis_instruction: body.contents[0].parts[0].text, instruction_sha256: hash(body.contents[0].parts[0].text),
        request_body_sha256: hash(JSON.stringify(body)), failure_code: null, provider_finish_reason: null,
        returned_model_version: null, raw_pcm_sha256: null, master: null, telephony: null};
      p.attempts.push(a); p.generation_status = 'REQUESTING'; m.requests_reserved++; run.requested++;
      check(run.requested <= o.requestLimit && m.requests_reserved <= 2 + m.retry_request_budget, 'INTRO_REQUEST_BUDGET_EXHAUSTED');
      save(); // Correlated reservation plus directory fsync BEFORE transport.
      run.status = 'IN_PROGRESS'; saveRun();
      try {
        const response = await provider.requestSpeech(body, key), reason = response?.candidates?.[0]?.finishReason;
        a.provider_finish_reason = pack.FINISH_REASONS.includes(reason) ? reason : 'UNKNOWN';
        if (typeof response?.modelVersion === 'string' && /^gemini-[A-Za-z0-9._-]{1,120}$/.test(response.modelVersion)) a.returned_model_version = response.modelVersion;
        const pcm = provider.extractPcm(response); a.raw_pcm_sha256 = hash(pcm);
        const master = provider.makeWave(pcm, 24000); checkLocale(p.locale);
        const masterFile = pack.fileName(p, number, 'master'); writeNew(path.join(o.output, masterFile), master);
        a.master = {file: masterFile, ...cardinal.inspectWave(master, 24000)}; cardinal.technicalQa(a.master);
        const phone = provider.makeWave(cardinal.resampleMaster(master), 8000); checkLocale(p.locale);
        const phoneFile = pack.fileName(p, number, 'telephony'); writeNew(path.join(o.output, phoneFile), phone);
        a.telephony = {file: phoneFile, ...cardinal.inspectWave(phone, 8000)}; cardinal.technicalQa(a.telephony);
        p.generation_status = a.status = 'QA_PASSED'; pack.verifyEntry(o.output, p);
      } catch (e) {
        a.failure_code = safeCode(e, provider); p.generation_status = a.status = 'FAILED';
        if (a.failure_code === 'AUDIO_GENERATION_NOT_COMPLETE') incomplete = true;
        else stopped = a.failure_code;
      }
      save();
      run.events.push({locale: p.locale, id: p.id, attempt: number, status: a.status,
        failure_code: a.failure_code, finish_reason: a.provider_finish_reason,
        telephony_sha256: a.telephony?.sha256 || null}); saveRun();
      out({locale: p.locale, id: p.id, attempt: number, status: a.status, requests_reserved: m.requests_reserved});
      if (stopped) break;
    }
    run.status = stopped ? 'STOPPED_ON_FAILURE' : incomplete ? 'INCOMPLETE_RESPONSE' : 'BATCH_COMPLETE';
    run.finished_at = new Date().toISOString(); saveRun();
    const verified = pack.readManifest(o.output);
    if (stopped) throw new pack.PackError(stopped);
    if (incomplete) throw new pack.PackError('INTRO_INCOMPLETE_RESPONSE_REQUIRES_EXPLICIT_RETRY');
    return summary(verified, run.requested);
  } catch (e) {
    if (run) {
      run.status = 'FAILED'; run.failure_code = safeCode(e, provider); run.finished_at = new Date().toISOString();
      try { saveRun(); } catch (_) { /* Preserve first failure and changed/partial evidence. */ }
    }
    throw new pack.PackError(safeCode(e, provider));
  } finally {
    key = undefined;
    try {
      checkRoot(); check(inode(lockStat, fs.lstatSync(lockFile)), 'INTRO_LOCK_CHANGED');
      fs.unlinkSync(lockFile); syncDirectory(o.output);
    } finally { fs.closeSync(lock); }
  }
}
async function main(argv) {
  const o = options(argv);
  if (o.mode === 'generate') console.log(JSON.stringify(await generate(o)));
  else if (o.mode === 'verify-only') console.log(JSON.stringify(pack.verifyPack(o.output, o.reviewHash)));
  else console.log(JSON.stringify({mode: 'PLAN_ONLY_NO_PROVIDER', prompts: pack.plan(), catalog_sha256: pack.CATALOG_HASH,
    source_review_template: pack.reviewTemplate(), initial_request_capacity: 2, automatic_retries: 0,
    native_speaker_review: false, audio_listening_review: false, runtime_ready: false, deployed: false}));
}
module.exports = Object.freeze({options, outputTarget, readReview, generate, main});
if (require.main === module) main(process.argv.slice(2)).catch(e => {
  console.error(`Introduction authoring stopped: ${safeCode(e)}. No live media was imported.`); process.exitCode = 1;
});
