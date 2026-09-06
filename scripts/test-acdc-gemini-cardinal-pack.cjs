#!/usr/bin/env node
'use strict';
// Synthetic offline authoring fixtures only. Never read a real credential or
// invoke real requestSpeech. Run in the serialized, network-isolated guard.
const fs = require('node:fs'), path = require('node:path'), os = require('node:os'), crypto = require('node:crypto');
const assert = require('node:assert/strict'), vm = require('node:vm'), https = require('node:https');
const generator = require('./generate-acdc-gemini-cardinal-pack.cjs'), pack = require('./acdc-cardinal-pack.cjs');
const samples = require('./generate-acdc-gemini-samples.cjs');
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex'), clone = x => JSON.parse(JSON.stringify(x));
const files = [__filename, require.resolve('./generate-acdc-gemini-cardinal-pack.cjs'), require.resolve('./acdc-cardinal-pack.cjs'),
  require.resolve('./acdc-cardinal-catalog.cjs'), require.resolve('./generate-acdc-gemini-samples.cjs'),
  require.resolve('./acdc-language-catalog.cjs'), '/usr/bin/sox'];
const pins = () => Object.fromEntries(files.map(f => [f, hash(fs.readFileSync(f))]));
const before = pins(), output = fs.mkdtempSync(path.join(os.tmpdir(), 'acdc-cardinal-generator-proof.'));
assert(fs.realpathSync(output) === output && fs.lstatSync(output).isDirectory()); fs.chmodSync(output, 0o700);
const originalRequest = https.request; https.request = () => assert.fail('REAL NETWORK REQUEST FORBIDDEN');
const SENTINEL = 'SYNTHETIC_CREDENTIAL_MUST_NEVER_REACH_OUTPUT';
const groups = [], logs = []; let checks = 0, sequence = 0, totalMockRequests = 0, receipt;
const equal = (a, b) => { checks++; assert.deepEqual(a, b); };
async function rejects(fn, code) { checks++; await assert.rejects(fn, e => e instanceof pack.PackError && (!code || e.code === code)); }
async function group(name, fn) { await fn(); groups.push(name); console.log('PASS ' + name); }
const nextPath = name => path.join(output, `${++sequence}-${name}`);
function mkdir(name) { const dir = nextPath(name); fs.mkdirSync(dir, {mode: 0o700}); return dir; }
function save(dir, m) { fs.writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify(m) + '\n', {mode: 0o600}); }
function read(dir) { return JSON.parse(fs.readFileSync(path.join(dir, 'manifest.json'))); }
function approvedFile(selected = ['en-us']) {
  const m = pack.createManifest();
  for (const a of m.approvals) if (selected.includes(a.locale)) {
    for (const k of ['transcript', 'intro', 'delivery']) Object.assign(a[k], {status: 'APPROVED', evidence_sha256: hash(`SYNTHETIC-NOT-A-REAL-APPROVAL-${a.locale}-${k}`)});
    Object.assign(a.intro, {canonical_id: 'acdc-cardinal-intro-v1-test-only', transcript: 'SYNTHETIC TEST ONLY',
      transcript_sha256: hash('SYNTHETIC TEST ONLY'), wav_sha256: hash('SYNTHETIC TEST INTRO WAV')});
  }
  const value = {schema_version: 1, catalog_sha256: pack.CATALOG_HASH, approvals: m.approvals,
    approvals_sha256: pack.digest(m.approvals)};
  const file = nextPath('approvals.json'); fs.writeFileSync(file, JSON.stringify(value), {mode: 0o600});
  return {file, value};
}
const approval = approvedFile(), noApproval = approvedFile([]), allApproval = approvedFile(Object.keys(pack.LOCALE_HASHES));
const pcm = Buffer.alloc(24000 / 4 * 2);
for (let n = 0; n < pcm.length / 2; n++) pcm.writeInt16LE(Math.round(1200 * Math.cos(n * 2 * Math.PI * 500 / 24000)), n * 2);
const response = () => ({candidates: [{finishReason: 'STOP', content: {parts: [{inlineData: {
  mimeType: 'audio/L16;codec=pcm;rate=24000', data: pcm.toString('base64')}}]}}]});
function opts(dir, extra = [], a = approval) {
  return generator.options(['--generate', '--output', dir, '--locales', 'en-us', '--request-limit', '1',
    '--approval-file', a.file, '--approval-sha256', a.value.approvals_sha256,
    '--key-file', path.join(output, 'does-not-exist.key'), ...extra]);
}
function providerDeps(dir, behavior = async () => response()) {
  const counts = {loads: 0, keys: 0, requests: 0, active: 0, maximum_active: 0};
  return {counts, output: value => logs.push(JSON.stringify(value)), loadProvider() {
    counts.loads++;
    return {...samples, readProtectedKey(file) {
      equal(file, path.join(output, 'does-not-exist.key')); counts.keys++; return SENTINEL;
    }, async requestSpeech(body, key) {
      counts.requests++; totalMockRequests++; counts.active++; counts.maximum_active = Math.max(counts.maximum_active, counts.active);
      equal(key, SENTINEL);
      const m = read(dir), matched = m.prompts.find(p => p.attempts.at(-1)?.request_body_sha256 === hash(JSON.stringify(body))
        && p.generation_status === 'REQUESTING');
      assert(matched, 'Request was not preceded by a persisted correlated reservation'); checks++;
      equal(m.requests_reserved, m.prompts.reduce((n, p) => n + p.attempts.length, 0));
      assert(fs.existsSync(path.join(dir, '.generation.lock'))); checks++;
      try { return await behavior({body, m, matched, counts}); } finally { counts.active--; }
    }};
  }};
}
const noProvider = {loadProvider() { assert.fail('Provider must not load'); }, output: x => logs.push(JSON.stringify(x))};
function withAttempt(e, status = 'REQUESTING', number = 1) {
  const body = pack.requestBody(e), instruction = body.contents[0].parts[0].text;
  return {number, status, reserved_at: '2026-09-06T00:00:00.000Z', synthesis_instruction: instruction,
    instruction_sha256: hash(instruction), request_body_sha256: hash(JSON.stringify(body)),
    failure_code: status === 'FAILED' ? 'AUDIO_GENERATION_NOT_COMPLETE' : null, provider_finish_reason: status === 'FAILED' ? 'MAX_TOKENS' : null,
    raw_pcm_sha256: null, master: null, telephony: null};
}
function prepareManifest(dir, a = approval) {
  const m = pack.createManifest(); m.approvals = clone(a.value.approvals); m.approvals_sha256 = a.value.approvals_sha256;
  save(dir, m); return m;
}
function inputFiles(dir) {
  return fs.readdirSync(dir, {withFileTypes: true}).flatMap(e => e.isDirectory() ? inputFiles(path.join(dir, e.name)) : [path.join(dir, e.name)]);
}
async function main() {
  let exit = 1;
  try {
    await group('strict options and authoring-only output boundaries', async () => {
      equal(generator.options([]).mode, 'plan'); equal(generator.options(['--plan']).mode, 'plan');
      for (const args of [['--generate'], ['--plan', '--generate'], ['--plan', '--plan'], ['--resume'],
        ['--retry-failed'], ['--retry-budget', '1'], ['--locales', 'en-us,en-us'], ['--locales', 'zz-zz'],
        ['--concurrency', '3'], ['--concurrency', '01'], ['--request-limit', '0'], ['--request-limit', '585'], ['--unknown']]) {
        checks++; assert.throws(() => generator.options(args), pack.PackError);
      }
      for (const dir of ['/opt/kz5/cardinal-new', '/var/www/cardinal-new', '/usr/share/cardinal-new', '/run/cardinal-new', '/tmp']) {
        checks++; assert.throws(() => generator.outputTarget(dir, false), pack.PackError);
      }
      const link = nextPath('linked-parent'); fs.symlinkSync(output, link);
      checks++; assert.throws(() => generator.outputTarget(path.join(link, 'new'), false), pack.PackError);
    });
    await group('approval/intro/context pins block before provider access', async () => {
      await rejects(() => generator.generate(opts(nextPath('pending-review'), [], noApproval), noProvider), 'AUTHORING_APPROVAL_PENDING');
      const wrong = opts(nextPath('wrong-pin')); wrong.approvalHash = '0'.repeat(64);
      await rejects(() => generator.generate(wrong, noProvider), 'APPROVAL_FILE_CHANGED');
      const inside = nextPath('inside-key'), o = opts(inside); o.keyFile = path.join(inside, 'key');
      await rejects(() => generator.generate(o, noProvider), 'PROTECTED_EXTERNAL_KEY_PATH_REQUIRED');
      const changed = clone(approval.value); changed.approvals.find(a => a.locale === 'en-us').intro.semantic_frame = 'ticket-number';
      changed.approvals_sha256 = pack.digest(changed.approvals);
      const file = nextPath('wrong-context.json'); fs.writeFileSync(file, JSON.stringify(changed), {mode: 0o600});
      await rejects(() => generator.generate(opts(nextPath('wrong-context'), [], {file, value: changed}), noProvider), 'APPROVAL_CONTEXT_CHANGED');
    });
    const normalDir = nextPath('normal'), normalOpts = opts(normalDir), normalDeps = providerDeps(normalDir);
    await group('bounded new authoring uses real helpers/SoX and reserves before transport', async () => {
      const result = await generator.generate(normalOpts, normalDeps);
      equal(result.requests_this_run, 1); equal(result.selected_qa_passed, 1); equal(result.selected_complete, false);
      equal(result.artifact_complete, false); equal(result.runtime_ready, false); equal(result.audio_listening_review, false);
      equal(normalDeps.counts.requests, 1); equal(normalDeps.counts.keys, 1);
      const m = pack.readManifest(normalDir), e = m.prompts[0];
      equal(m.requests_reserved, 1); equal(e.generation_status, 'QA_PASSED'); equal(pack.verifyEntry(normalDir, e), e);
      equal(m.approvals_sha256, approval.value.approvals_sha256); equal(m.conversion.recipe_sha256, pack.digest(pack.RESAMPLING));
      equal(fs.existsSync(path.join(normalDir, '.generation.lock')), false);
    });
    await group('resume preserves earlier verified bytes and consumes only missing identities', async () => {
      const m = read(normalDir), e = m.prompts[0], names = ['master', 'telephony'].map(k => path.join(normalDir, e.attempts[0][k].file));
      const hashes = names.map(f => hash(fs.readFileSync(f)));
      const o = {...normalOpts, resume: true}, deps = providerDeps(normalDir);
      const result = await generator.generate(o, deps); equal(result.requests_this_run, 1); equal(deps.counts.requests, 1);
      equal(result.requests_reserved, 2); equal(names.map(f => hash(fs.readFileSync(f))), hashes);
      equal(read(normalDir).prompts[0], e);
    });
    await group('selected indeterminate request is never retried and no stale lock is stolen', async () => {
      const dir = mkdir('indeterminate'), m = prepareManifest(dir), e = m.prompts[0];
      e.attempts = [withAttempt(e)]; e.generation_status = 'REQUESTING'; m.requests_reserved = 1; m.conversion.version = pack.RESAMPLING.version; save(dir, m);
      const original = hash(fs.readFileSync(path.join(dir, 'manifest.json'))), o = {...opts(dir), resume: true};
      await rejects(() => generator.generate(o, noProvider), 'INDETERMINATE_REQUEST_REQUIRES_RECONCILIATION');
      await rejects(() => generator.generate({...o, retryFailed: true, retryBudget: 1}, noProvider), 'INDETERMINATE_REQUEST_REQUIRES_RECONCILIATION');
      equal(hash(fs.readFileSync(path.join(dir, 'manifest.json'))), original);
      const locked = mkdir('locked'); prepareManifest(locked);
      const lock = path.join(locked, '.generation.lock'); fs.writeFileSync(lock, 'stale-test-owner', {mode: 0o600});
      await rejects(() => generator.generate({...opts(locked), resume: true}, noProvider), 'GENERATION_LOCKED');
      equal(fs.readFileSync(lock, 'utf8'), 'stale-test-owner');
    });
    await group('incomplete provider response continues other initial jobs without automatic retry', async () => {
      const dir = nextPath('incomplete'), o = {...opts(dir), requestLimit: 2}, deps = providerDeps(dir, async ({counts}) =>
        counts.requests === 1 ? {candidates: [{finishReason: 'MAX_TOKENS'}]} : response());
      await rejects(() => generator.generate(o, deps), 'INCOMPLETE_RESPONSE_REQUIRES_EXPLICIT_RETRY');
      const m = pack.readManifest(dir); equal(deps.counts.requests, 2); equal(m.requests_reserved, 2);
      equal(m.prompts[0].attempts.length, 1); equal(m.prompts[0].attempts[0].provider_finish_reason, 'MAX_TOKENS');
      equal(m.prompts[0].generation_status, 'FAILED'); equal(m.prompts[1].generation_status, 'QA_PASSED');
      const prior = pack.digest(m.prompts[0].attempts[0]);
      const retryDeps = providerDeps(dir), retry = {...o, resume: true, requestLimit: 1, retryFailed: true, retryBudget: 1};
      await generator.generate(retry, retryDeps);
      const fixed = pack.readManifest(dir); equal(retryDeps.counts.requests, 1); equal(fixed.requests_reserved, 3);
      equal(fixed.prompts[0].attempts.length, 2); equal(pack.digest(fixed.prompts[0].attempts[0]), prior);
      assert(fixed.prompts[0].attempts[1].master.file.includes('.attempt-2.')); checks++;
      equal(fixed.prompts[1], m.prompts[1]);
    });
    await group('HTTP/transport failure stops subsequent jobs and emits only safe codes', async () => {
      for (const error of [new samples.SampleError('GEMINI_HTTP_403'), new Error(SENTINEL)]) {
        const dir = nextPath('stop'), deps = providerDeps(dir, async () => { throw error; });
        await rejects(() => generator.generate({...opts(dir), requestLimit: 3}, deps));
        equal(deps.counts.requests, 1); const m = pack.readManifest(dir); equal(m.requests_reserved, 1);
        equal(m.prompts[1].generation_status, 'PENDING');
        equal(m.prompts[0].attempts[0].failure_code, error instanceof samples.SampleError ? 'GEMINI_HTTP_403' : 'LOCAL_OPERATION_FAILED');
      }
    });
    await group('two workers join before releasing the lock after one failure', async () => {
      const dir = nextPath('concurrent'); let unblock;
      const second = new Promise(resolve => { unblock = resolve; });
      const deps = providerDeps(dir, async ({counts}) => {
        if (counts.requests === 1) { await second; throw new samples.SampleError('GEMINI_HTTP_429'); }
        unblock(); await new Promise(resolve => setTimeout(resolve, 20));
        assert(fs.existsSync(path.join(dir, '.generation.lock'))); checks++; return response();
      });
      await rejects(() => generator.generate({...opts(dir), requestLimit: 3, concurrency: 2}, deps), 'GEMINI_HTTP_429');
      equal(deps.counts.maximum_active, 2); equal(deps.counts.requests, 2); equal(deps.counts.active, 0);
      equal(fs.existsSync(path.join(dir, '.generation.lock')), false);
      const m = pack.readManifest(dir); equal(m.requests_reserved, 2); equal(m.prompts[1].generation_status, 'QA_PASSED');
    });
    await group('preexisting attempt path and manifest drift fail without overwrites', async () => {
      const dir = mkdir('orphan'), m = prepareManifest(dir); fs.mkdirSync(path.join(dir, 'en-us'), {mode: 0o700});
      const file = path.join(dir, pack.fileName(m.prompts[0], 1, 'master')); fs.writeFileSync(file, 'orphan-retained', {mode: 0o600});
      await rejects(() => generator.generate({...opts(dir), resume: true}, noProvider), 'ATTEMPT_AUDIO_ALREADY_EXISTS');
      equal(fs.readFileSync(file, 'utf8'), 'orphan-retained');
      const drift = nextPath('drift'); let altered;
      const deps = providerDeps(drift, async () => {
        altered = fs.readFileSync(path.join(drift, 'manifest.json'), 'utf8') + ' \n';
        fs.writeFileSync(path.join(drift, 'manifest.json'), altered); return response();
      });
      await rejects(() => generator.generate(opts(drift), deps), 'MANIFEST_CHANGED_OUTSIDE_LOCK');
      equal(fs.readFileSync(path.join(drift, 'manifest.json'), 'utf8'), altered);
    });
    await group('attempted-locale approval cannot change; untouched locale may gain review', async () => {
      const changed = clone(approval.value); changed.approvals.find(a => a.locale === 'en-us').transcript.evidence_sha256 = hash('different-review');
      changed.approvals_sha256 = pack.digest(changed.approvals);
      const file = nextPath('changed-review.json'); fs.writeFileSync(file, JSON.stringify(changed), {mode: 0o600});
      await rejects(() => generator.generate({...opts(normalDir, [], {file, value: changed}), resume: true}, noProvider), 'ATTEMPTED_LOCALE_APPROVAL_CHANGED');
      const o = {...opts(normalDir, [], allApproval), resume: true, locales: ['es-es']}, deps = providerDeps(normalDir);
      const result = await generator.generate(o, deps); equal(result.selected_locales, ['es-es']); equal(deps.counts.requests, 1);
      equal(read(normalDir).approvals_sha256, allApproval.value.approvals_sha256);
    });
    await group('complete584 resume requires neither key nor provider nor approval file', async () => {
      const dir = mkdir('complete584'), m = prepareManifest(dir, allApproval), master = samples.makeWave(pcm, 24000);
      const phone = samples.makeWave(pack.resampleMaster(master), 8000);
      for (const locale of Object.keys(pack.LOCALE_HASHES)) fs.mkdirSync(path.join(dir, locale), {mode: 0o700});
      for (const e of m.prompts) {
        const a = withAttempt(e, 'QA_PASSED'); a.provider_finish_reason = 'STOP'; a.raw_pcm_sha256 = hash(pcm);
        for (const [variant, bytes, rate] of [['master', master, 24000], ['telephony', phone, 8000]]) {
          const file = pack.fileName(e, 1, variant); fs.writeFileSync(path.join(dir, file), bytes, {flag: 'wx', mode: 0o600});
          a[variant] = {file, ...pack.inspectWave(bytes, rate)};
        }
        e.attempts = [a]; e.generation_status = 'QA_PASSED';
      }
      m.requests_reserved = 584; m.artifact_complete = true; m.conversion.version = pack.RESAMPLING.version; save(dir, m);
      const snapshot = inputFiles(dir).map(f => [f, hash(fs.readFileSync(f))]);
      const o = generator.options(['--generate', '--resume', '--output', dir, '--request-limit', '1']);
      const result = await generator.generate(o, noProvider); equal(result.requests_this_run, 0); equal(result.artifact_complete, true);
      equal(result.audio_listening_review, false); equal(result.runtime_ready, false);
      equal(inputFiles(dir).map(f => [f, hash(fs.readFileSync(f))]), snapshot);
    });
    await group('plan/import does not load provider or write; receipts never contain mock credential', async () => {
      const source = fs.readFileSync(require.resolve('./generate-acdc-gemini-cardinal-pack.cjs'), 'utf8'), imports = [], emitted = [];
      const sandbox = {module: {exports: {}}, console: {log: x => emitted.push(x)}, require(name) {
        imports.push(name);
        if (name === './acdc-cardinal-pack.cjs') return pack;
        if (name === 'node:path') return path;
        if (name === 'node:crypto') return crypto;
        if (name === 'node:fs' || name === 'node:child_process') return new Proxy({}, {get() { assert.fail('Plan must not perform I/O'); }});
        assert.fail('Unexpected provider/helper import: ' + name);
      }};
      vm.runInNewContext(source, sandbox, {timeout: 5000});
      await sandbox.module.exports.main([]); equal(JSON.parse(emitted[0]).mode, 'PLAN_ONLY_NO_PROVIDER');
      equal(imports.includes('./generate-acdc-gemini-samples.cjs'), false);
      for (const file of inputFiles(output).filter(f => f.endsWith('.json'))) {
        equal(fs.readFileSync(file, 'utf8').includes(SENTINEL), false);
      }
      equal(logs.join('\n').includes(SENTINEL), false);
    });
    exit = 0;
    receipt = {schema_version: 1, fixture_only: true, groups, checks, mock_requests: totalMockRequests,
      real_provider_calls: 0, real_key_reads: 0, actual_sox_recipe: pack.RESAMPLING.recipe,
      approvals_are_synthetic_fixtures: true, runtime_ready: false, native_acceptance: false};
  } catch (e) {
    receipt = {schema_version: 1, fixture_only: true, groups, checks, mock_requests: totalMockRequests,
      failure: {name: e.name, message: e.message}, runtime_ready: false, native_acceptance: false};
    console.error(e.stack);
  } finally {
    https.request = originalRequest;
    const after = pins(), stable = JSON.stringify(before) === JSON.stringify(after);
    receipt = {...receipt, output_directory: output, source_hashes_before: before, source_hashes_after: after,
      source_stable: stable, terminal_exit: stable ? exit : 1};
    fs.writeFileSync(path.join(output, 'receipt.json'), JSON.stringify(receipt, null, 2) + '\n', {flag: 'wx', mode: 0o600});
    console.log(JSON.stringify(receipt)); process.exitCode = receipt.terminal_exit;
  }
}
main();
