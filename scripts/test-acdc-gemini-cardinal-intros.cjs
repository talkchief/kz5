#!/usr/bin/env node
'use strict';

// Controlled provider doubles + real local SoX only. Root runs in an offline
// resource guard. All approvals/audio are synthetic fixtures, never release evidence.
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const assert = require('node:assert/strict'), https = require('node:https'), vm = require('node:vm');
const pack = require('./acdc-cardinal-intro-pack.cjs');
const generator = require('./generate-acdc-gemini-cardinal-intros.cjs');
const cardinal = require('./acdc-cardinal-pack.cjs'), samples = require('./generate-acdc-gemini-samples.cjs');
const files = [__filename, require.resolve('./acdc-cardinal-intro-pack.cjs'), require.resolve('./generate-acdc-gemini-cardinal-intros.cjs'),
  require.resolve('./acdc-cardinal-pack.cjs'), require.resolve('./acdc-cardinal-catalog.cjs'),
  require.resolve('./generate-acdc-gemini-samples.cjs'), require.resolve('./acdc-language-catalog.cjs'), '/usr/bin/sox'];
const pins = () => Object.fromEntries(files.map(f => [f, pack.hash(fs.readFileSync(f))]));
const before = pins(), output = fs.mkdtempSync(path.join(os.tmpdir(), 'acdc-cardinal-intros-proof.'));
assert.equal(fs.realpathSync(output), output); fs.chmodSync(output, 0o700);
const previousRequest = https.request; https.request = () => assert.fail('REAL PROVIDER REQUEST FORBIDDEN');
const SENTINEL = 'SYNTHETIC_INTRO_CREDENTIAL_NOT_FOR_OUTPUT';
let sequence = 0, checks = 0, mockRequests = 0; const groups = [], emitted = [];
const clone = o => JSON.parse(JSON.stringify(o)), equal = (a, b) => { checks++; assert.deepEqual(a, b); };
const rejects = async (fn, code) => { checks++; await assert.rejects(fn, e => e instanceof pack.PackError && (!code || e.code === code)); };
const group = async (name, fn) => { await fn(); groups.push(name); console.log('PASS ' + name); };
const next = name => path.join(output, `${++sequence}-${name}`);
const save = (dir, m) => fs.writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify(m) + '\n', {mode: 0o600});
const read = dir => JSON.parse(fs.readFileSync(path.join(dir, 'manifest.json')));
function reviewFile(value = {...pack.reviewTemplate(), decision: 'AUTHOR_INTROS_ONLY', evidence_sha256: pack.hash('SYNTHETIC_SOURCE_REVIEW')}) {
  const file = next('review.json'); fs.writeFileSync(file, JSON.stringify(value), {mode: 0o600});
  return {file, value, hash: pack.digest(value)};
}
const review = reviewFile();
function opts(dir, extra = []) {
  return generator.options(['--generate', '--output', dir, '--request-limit', '2',
    '--review-file', review.file, '--review-sha256', review.hash, '--key-file', path.join(output, 'not-a-real-key'), ...extra]);
}
function pcm(rate = 24000, frequency = 500) {
  const bytes = Buffer.alloc(rate); // Half a second, PCM16 mono.
  for (let i = 0; i < rate / 2; i++) bytes.writeInt16LE(Math.round(1600 * Math.cos(i * 2 * Math.PI * frequency / rate)), i * 2);
  return bytes;
}
const response = () => ({modelVersion: pack.MODEL, candidates: [{finishReason: 'STOP', content: {parts: [
  {inlineData: {mimeType: 'audio/L16;codec=pcm;rate=24000', data: pcm().toString('base64')}}]}}]});
const noProvider = {loadProvider() { assert.fail('Provider must not load'); }, output: x => emitted.push(JSON.stringify(x))};
function provider(dir, behavior = async () => response()) {
  const counts = {loads: 0, keys: 0, requests: 0, active: 0};
  return {counts, output: x => emitted.push(JSON.stringify(x)), loadProvider() {
    counts.loads++;
    return {...samples, readProtectedKey(file) { equal(file, path.join(output, 'not-a-real-key')); counts.keys++; return SENTINEL; },
      async requestSpeech(body, key) {
        equal(key, SENTINEL); counts.requests++; mockRequests++; equal(++counts.active, 1);
        const m = read(dir), p = m.prompts.find(p => p.generation_status === 'REQUESTING'
          && p.attempts.at(-1).request_body_sha256 === pack.hash(JSON.stringify(body)));
        equal(!!p, true); equal(m.requests_reserved, m.prompts.reduce((sum, p) => sum + p.attempts.length, 0));
        equal(fs.existsSync(path.join(dir, '.generation.lock')), true);
        try { return await behavior({body, m, p, counts}); } finally { counts.active--; }
      }};
  }};
}
function fixture(dir, m = pack.createManifest(review.value)) {
  fs.mkdirSync(dir, {mode: 0o700}); save(dir, m); return m;
}
function attempt(p, status = 'REQUESTING') {
  const body = pack.requestBody(p);
  return {number: 1, status, reserved_at: '2026-09-07T00:00:00.000Z', synthesis_instruction: body.contents[0].parts[0].text,
    instruction_sha256: pack.hash(body.contents[0].parts[0].text), request_body_sha256: pack.hash(JSON.stringify(body)),
    failure_code: status === 'FAILED' ? 'AUDIO_GENERATION_NOT_COMPLETE' : null,
    provider_finish_reason: status === 'FAILED' ? 'MAX_TOKENS' : null, returned_model_version: null,
    raw_pcm_sha256: null, master: null, telephony: null};
}
function inputFiles(dir) {
  return fs.readdirSync(dir, {withFileTypes: true}).flatMap(e => e.isDirectory()
    ? inputFiles(path.join(dir, e.name)) : [path.join(dir, e.name)]);
}
const fileHashes = dir => inputFiles(dir).map(f => [f, pack.hash(fs.readFileSync(f))]);
function duplicatePack(dir) {
  const copy = next('copy'); fs.cpSync(dir, copy, {recursive: true, errorOnExist: true}); fs.chmodSync(copy, 0o700); return copy;
}
async function main() {
  let exit = 1, failure;
  const normal = next('recoverable-output');
  try {
    await group('exact two context-qualified intros with no historical/cardinal identities', async () => {
      equal(pack.plan().map(p => p.locale), ['he-il', 'ar-sa']); equal(pack.plan().length, 2);
      equal(pack.plan().map(p => p.transcript), ['מִסְפַּר מְקוֹמְכֶם הַנּוֹכְחִי בַּתּוֹר הוּא.',
        'رَقْمُ مَوْقِعِكَ الْحَالِي فِي طَابُورِ الِانْتِظَارِ هُوَ.']);
      for (const p of pack.plan()) {
        equal(p.id, 'acdc-cardinal-intro-v1-current-position-number'); equal(p.semantic_frame, pack.FRAME);
        equal(p.transcript_sha256, pack.hash(p.transcript));
        equal(pack.requestBody(p).generationConfig.speechConfig.voiceConfig.prebuiltVoiceConfig.voiceName, 'Sulafat');
        checks++; assert.throws(() => pack.requestBody({...p, transcript: 'ticket number'}), pack.PackError);
      }
      equal(cardinal.plan().length, 584); equal(cardinal.plan().some(p => p.id === pack.ID), false);
    });
    await group('strict CLI/output/review preflight makes no output or provider request', async () => {
      equal(generator.options([]).mode, 'plan');
      for (const argv of [['--generate'], ['--generate', '--plan'], ['--plan', '--plan'], ['--resume'],
        ['--retry-failed'], ['--retry-budget', '1'], ['--request-limit', '0'], ['--request-limit', '3'],
        ['--request-limit', '01'], ['--concurrency', '2'], ['--locales', 'en-us'], ['--unknown']]) {
        checks++; assert.throws(() => generator.options(argv), pack.PackError);
      }
      for (const dir of ['/tmp', '/opt/kz5/new-intros', '/etc/new-intros', '/var/www/new-intros']) {
        checks++; assert.throws(() => generator.outputTarget(dir, false), pack.PackError);
      }
      const pending = reviewFile(pack.reviewTemplate());
      await rejects(() => generator.generate({...opts(normal), reviewFile: pending.file, reviewHash: pending.hash}, noProvider), 'INTRO_SOURCE_REVIEW_REQUIRED');
      equal(fs.existsSync(normal), false);
      await rejects(() => generator.generate({...opts(normal), reviewHash: '0'.repeat(64)}, noProvider), 'INTRO_REVIEW_PIN_CHANGED');
      equal(fs.existsSync(normal), false);
      await rejects(() => generator.generate({...opts(normal), keyFile: path.join(normal, 'key')}, noProvider), 'EXTERNAL_INTRO_KEY_PATH_REQUIRED');
      equal(fs.existsSync(normal), false);
    });
    await group('same-path corrected review reserves serially and checkpoints one intro', async () => {
      const deps = provider(normal), result = await generator.generate({...opts(normal), requestLimit: 1}, deps);
      equal(result.requests_this_run, 1); equal(result.qa_passed, 1); equal(result.artifact_complete, false);
      equal(deps.counts.requests, 1); equal(result.native_speaker_review, false); equal(result.runtime_ready, false);
      const m = pack.readManifest(normal); equal(m.requests_reserved, 1); equal(m.prompts[1].generation_status, 'PENDING');
      equal(fs.existsSync(path.join(normal, '.generation.lock')), false);
    });
    await group('resume preserves success and verifier exports exact telephony facts, not approval', async () => {
      const first = clone(read(normal).prompts[0]), old = [first.attempts[0].master.file, first.attempts[0].telephony.file]
        .map(f => pack.hash(fs.readFileSync(path.join(normal, f))));
      const deps = provider(normal), result = await generator.generate({...opts(normal), resume: true}, deps);
      equal(result.requests_this_run, 1); equal(result.artifact_complete, true); equal(result.requests_reserved, 2);
      equal(read(normal).prompts[0], first);
      equal([first.attempts[0].master.file, first.attempts[0].telephony.file].map(f => pack.hash(fs.readFileSync(path.join(normal, f)))), old);
      const verified = pack.verifyPack(normal, review.hash); equal(verified.resampling_provenance_verified, true);
      equal(verified.independently_pinned_source_review, true); equal(verified.audio_listening_review, false);
      for (const p of read(normal).prompts) equal(verified.intro_inputs.find(i => i.locale === p.locale), {
        locale: p.locale, canonical_id: p.id, transcript: p.transcript, transcript_sha256: p.transcript_sha256,
        wav_sha256: p.attempts[0].telephony.sha256});
      equal(verified.intro_inputs.some(p => Object.hasOwn(p, 'status')), false);
    });
    await group('complete resume uses no key/review/provider and changes no files', async () => {
      const before = fileHashes(normal);
      const result = await generator.generate(generator.options(['--generate', '--resume', '--output', normal, '--request-limit', '1']), noProvider);
      equal(result.requests_this_run, 0); equal(result.artifact_complete, true); equal(fileHashes(normal), before);
    });
    await group('incomplete audio continues other identity, explicit retry preserves history', async () => {
      const dir = next('retry'), deps = provider(dir, async ({counts}) => counts.requests === 1
        ? {candidates: [{finishReason: 'MAX_TOKENS'}]} : response());
      await rejects(() => generator.generate(opts(dir), deps), 'INTRO_INCOMPLETE_RESPONSE_REQUIRES_EXPLICIT_RETRY');
      const prior = read(dir), success = clone(prior.prompts[1]); equal(deps.counts.requests, 2);
      const retry = provider(dir); await generator.generate({...opts(dir), resume: true, retryFailed: true, retryBudget: 1}, retry);
      const m = pack.readManifest(dir); equal(retry.counts.requests, 1); equal(m.requests_reserved, 3);
      equal(m.prompts[0].attempts[0], prior.prompts[0].attempts[0]); equal(m.prompts[1], success);
      equal(m.prompts[0].attempts[1].telephony.file.includes('.attempt-2.'), true);
    });
    await group('indeterminate request and retained lock never authorize another request', async () => {
      const dir = next('indeterminate'), m = fixture(dir), p = m.prompts[0];
      p.attempts = [attempt(p)]; p.generation_status = 'REQUESTING'; m.requests_reserved = 1; save(dir, m);
      const before = fileHashes(dir);
      await rejects(() => generator.generate({...opts(dir), resume: true}, noProvider), 'INDETERMINATE_INTRO_REQUEST_REQUIRES_RECONCILIATION');
      await rejects(() => generator.generate({...opts(dir), resume: true, retryFailed: true, retryBudget: 2}, noProvider), 'INDETERMINATE_INTRO_REQUEST_REQUIRES_RECONCILIATION');
      equal(fileHashes(dir), before);
      const locked = next('locked'); fixture(locked); fs.writeFileSync(path.join(locked, '.generation.lock'), 'OWNED-LOCK', {mode: 0o600});
      await rejects(() => generator.generate({...opts(locked), resume: true}, noProvider), 'INTRO_GENERATION_LOCKED');
      equal(fs.readFileSync(path.join(locked, '.generation.lock'), 'utf8'), 'OWNED-LOCK');
      const changedReview = reviewFile({...review.value, evidence_sha256: pack.hash('DIFFERENT_SYNTHETIC_REVIEW')});
      const pending = next('changed-review'); fixture(pending); const pendingPins = fileHashes(pending);
      await rejects(() => generator.generate({...opts(pending), resume: true, reviewFile: changedReview.file,
        reviewHash: changedReview.hash}, noProvider), 'INTRO_AUTHORING_REVIEW_CHANGED');
      equal(fileHashes(pending), pendingPins);
    });
    await group('two attempts per identity and total four requests are hard limits', async () => {
      const dir = next('exhausted'), incomplete = async () => ({candidates: [{finishReason: 'MAX_TOKENS'}]});
      const first = provider(dir, incomplete); await rejects(() => generator.generate(opts(dir), first));
      const second = provider(dir, incomplete);
      await rejects(() => generator.generate({...opts(dir), resume: true, retryFailed: true, retryBudget: 2}, second));
      equal(pack.readManifest(dir).requests_reserved, 4); equal(read(dir).prompts.map(p => p.attempts.length), [2, 2]);
      await rejects(() => generator.generate({...opts(dir), resume: true, retryFailed: true, retryBudget: 2}, noProvider), 'INCOMPLETE_INTROS_REQUIRE_EXPLICIT_RETRY');
      equal(first.counts.requests + second.counts.requests, 4);
    });
    await group('HTTP/local failures stop later work and sanitize provider error strings', async () => {
      for (const e of [new samples.SampleError('GEMINI_HTTP_403'), new Error(SENTINEL)]) {
        const dir = next('stop'), deps = provider(dir, async () => { throw e; });
        await rejects(() => generator.generate(opts(dir), deps)); equal(deps.counts.requests, 1);
        const m = pack.readManifest(dir); equal(m.prompts[1].generation_status, 'PENDING');
        equal(m.prompts[0].attempts[0].failure_code, e instanceof samples.SampleError ? 'GEMINI_HTTP_403' : 'LOCAL_INTRO_OPERATION_FAILED');
      }
    });
    await group('changed transcript/review/readiness/accounting and rehashed wrong audio fail', async () => {
      for (const mutate of [m => { m.prompts[0].transcript = 'ticket number'; }, m => { m.requests_reserved++; },
        m => { m.runtime_ready = true; }, m => { m.prompts.reverse(); m.prompts[0].locale = 'he-il'; }]) {
        const copy = duplicatePack(normal), m = read(copy); mutate(m); save(copy, m);
        checks++; assert.throws(() => pack.readManifest(copy), pack.PackError);
      }
      checks++; assert.throws(() => pack.verifyPack(normal, '0'.repeat(64)), pack.PackError);
      const copy = duplicatePack(normal), m = read(copy), a = m.prompts[0].attempts[0];
      const phone = samples.makeWave(pcm(8000, 900), 8000); fs.writeFileSync(path.join(copy, a.telephony.file), phone);
      a.telephony = {file: a.telephony.file, ...cardinal.inspectWave(phone, 8000)}; cardinal.technicalQa(a.telephony); save(copy, m);
      equal(a.telephony.duration_seconds, a.master.duration_seconds);
      checks++; assert.throws(() => pack.verifyPack(copy), e => e.code === 'INTRO_NOT_MASTER_RESAMPLE');
    });
    await group('symlinks/hardlinks/orphans and external manifest drift never overwrite', async () => {
      const linked = next('linked'); fs.symlinkSync(normal, linked);
      checks++; assert.throws(() => pack.readManifest(linked), pack.PackError);
      const hard = duplicatePack(normal), a = read(hard).prompts[0].attempts[0];
      fs.linkSync(path.join(hard, a.master.file), next('hardlink.wav'));
      checks++; assert.throws(() => pack.verifyPack(hard), pack.PackError);
      const orphan = next('orphan'), m = fixture(orphan), p = m.prompts[0]; fs.mkdirSync(path.join(orphan, p.locale), {mode: 0o700});
      const file = path.join(orphan, pack.fileName(p, 1, 'master')); fs.writeFileSync(file, 'RETAIN', {mode: 0o600});
      await rejects(() => generator.generate({...opts(orphan), resume: true}, noProvider), 'INTRO_ATTEMPT_FILE_EXISTS');
      equal(fs.readFileSync(file, 'utf8'), 'RETAIN');
      const drift = next('drift'); let changed;
      const deps = provider(drift, async () => {
        changed = fs.readFileSync(path.join(drift, 'manifest.json'), 'utf8') + ' \n';
        fs.writeFileSync(path.join(drift, 'manifest.json'), changed); return response();
      });
      await rejects(() => generator.generate(opts(drift), deps), 'INTRO_MANIFEST_CHANGED_OUTSIDE_LOCK');
      equal(fs.readFileSync(path.join(drift, 'manifest.json'), 'utf8'), changed);
    });
    await group('plan has no provider/file/subprocess effects and evidence contains no credentials', async () => {
      const source = fs.readFileSync(require.resolve('./generate-acdc-gemini-cardinal-intros.cjs'), 'utf8'), values = [];
      const sandbox = {module: {exports: {}}, console: {log: v => values.push(v)}, require(name) {
        if (name === './acdc-cardinal-intro-pack.cjs') return pack;
        if (name === './acdc-cardinal-pack.cjs') return cardinal;
        if (name === 'node:path') return path;
        if (name === 'node:crypto') return require(name);
        if (name === 'node:fs' || name === 'node:child_process') return new Proxy({}, {get() { assert.fail('Plan side effect'); }});
        assert.fail('Unexpected provider/helper load');
      }};
      vm.runInNewContext(source, sandbox, {timeout: 5000}); await sandbox.module.exports.main([]);
      const planned = JSON.parse(values[0]); equal(planned.prompts.length, 2); equal(planned.source_review_template.decision, 'PENDING');
      equal(planned.runtime_ready, false);
      for (const file of inputFiles(output).filter(f => f.endsWith('.json'))) equal(fs.readFileSync(file, 'utf8').includes(SENTINEL), false);
      equal(emitted.join('\n').includes(SENTINEL), false);
    });
    exit = 0;
  } catch (e) { failure = {name: e.name, message: e.message}; console.error(e.stack); }
  finally {
    https.request = previousRequest;
    const after = pins(), stable = JSON.stringify(before) === JSON.stringify(after);
    const receipt = {schema_version: 1, fixture_only: true, groups, checks, mock_requests: mockRequests,
      real_provider_requests: 0, real_key_reads: 0, actual_sox_recipe: pack.RESAMPLING.recipe,
      source_review_is_synthetic: true, native_speaker_review: false, audio_listening_review: false, runtime_ready: false,
      failure: failure || null, source_hashes_before: before, source_hashes_after: after, source_stable: stable,
      terminal_exit: stable ? exit : 1};
    fs.writeFileSync(path.join(output, 'receipt.json'), JSON.stringify(receipt, null, 2) + '\n', {flag: 'wx', mode: 0o600});
    console.log(JSON.stringify({output_directory: output, ...receipt})); process.exitCode = receipt.terminal_exit;
  }
}
main();
