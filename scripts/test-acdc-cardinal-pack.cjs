#!/usr/bin/env node
'use strict';
// Offline synthetic evidence only. Run through the serial resource guard.
// Retain every fixture and receipt; only fixed offline SoX subprocesses.
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const crypto = require('node:crypto'), assert = require('node:assert/strict'), vm = require('node:vm');
const cp = require('node:child_process');
const pack = require('./acdc-cardinal-pack.cjs'), catalog = require('./acdc-cardinal-catalog.cjs');
const hash = b => crypto.createHash('sha256').update(b).digest('hex');
const copy = value => JSON.parse(JSON.stringify(value));
const sourceFiles = [__filename, require.resolve('./acdc-cardinal-pack.cjs'), require.resolve('./acdc-cardinal-catalog.cjs'), '/usr/bin/sox'];
const pins = () => Object.fromEntries(sourceFiles.map(f => [f, hash(fs.readFileSync(f))]));
const before = pins(), groups = [];
// Checked allocation before deriving output paths; no repurposing HOME.
const output = fs.mkdtempSync(path.join(os.tmpdir(), 'acdc-cardinal-pack-proof.'));
assert(fs.lstatSync(output).isDirectory() && fs.realpathSync(output) === output);
fs.chmodSync(output, 0o700);
let sequence = 0, assertions = 0;
function group(name, fn) { fn(); groups.push(name); console.log('PASS ' + name); }
function equal(a, b) { assertions++; assert.deepEqual(a, b); }
function rejects(fn, code) {
  assertions++;
  assert.throws(fn, e => e instanceof pack.PackError && (!code || e.code === code));
}
function directory(name) {
  const dir = path.join(output, `${++sequence}-${name}`); fs.mkdirSync(dir, {mode: 0o700}); return dir;
}
function save(dir, manifest) {
  fs.writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify(manifest) + '\n', {mode: 0o600});
}
function fixtureWave(rate, seconds = 0.25, mode = 'normal', frequency = 500) {
  const count = Math.round(rate * seconds), data = Buffer.alloc(count * 2);
  for (let i = 0; i < count; i++) {
    const sample = mode === 'silence' ? 0 : mode === 'clipped' ? 32767
      : i < rate / 100 || i >= count - rate / 50 ? 0 : Math.round(1200 * Math.cos(i * 2 * Math.PI * frequency / rate));
    data.writeInt16LE(sample, i * 2);
  }
  return wrapPcm(data, rate);
}
function wrapPcm(data, rate) {
  const header = Buffer.alloc(44);
  header.write('RIFF'); header.writeUInt32LE(data.length + 36, 4); header.write('WAVEfmt ', 8);
  header.writeUInt32LE(16, 16); header.writeUInt16LE(1, 20); header.writeUInt16LE(1, 22);
  header.writeUInt32LE(rate, 24); header.writeUInt32LE(rate * 2, 28);
  header.writeUInt16LE(2, 32); header.writeUInt16LE(16, 34); header.write('data', 36); header.writeUInt32LE(data.length, 40);
  return Buffer.concat([header, data]);
}
function attempt(entry, number = 1, status = 'REQUESTING', recipe) {
  const body = pack.requestBody(entry, recipe), instruction = body.contents[0].parts[0].text;
  return {number, status, reserved_at: '2026-09-06T00:00:00.000Z', synthesis_instruction: instruction,
    ...(recipe === undefined ? {} : {synthesis_recipe: recipe}),
    instruction_sha256: hash(instruction), request_body_sha256: hash(JSON.stringify(body)),
    failure_code: status === 'FAILED' ? 'AUDIO_GENERATION_NOT_COMPLETE' : null,
    provider_finish_reason: status === 'FAILED' ? 'MAX_TOKENS' : null,
    raw_pcm_sha256: null, master: null, telephony: null};
}
const waves = {master: fixtureWave(24000), telephony: null};
const measured = {master: pack.inspectWave(waves.master, 24000), telephony: null};
function completedEntry(dir, entry, number = 1, recipe) {
  const a = attempt(entry, number, 'QA_PASSED', recipe); a.provider_finish_reason = 'STOP'; a.raw_pcm_sha256 = measured.master.pcm_sha256;
  const localeDir = path.join(dir, entry.locale);
  if (!fs.existsSync(localeDir)) fs.mkdirSync(localeDir, {mode: 0o700});
  for (const variant of ['master', 'telephony']) {
    const file = pack.fileName(entry, number, variant);
    fs.writeFileSync(path.join(dir, file), waves[variant], {flag: 'wx', mode: 0o600});
    a[variant] = {file, ...measured[variant]};
  }
  return {...entry, generation_status: 'QA_PASSED', attempts: number === 1 ? [a] : [attempt(entry, 1, 'FAILED'), a]};
}
function approve(manifest, locale, listening = false) {
  const a = manifest.approvals.find(a => a.locale === locale);
  for (const key of ['transcript', 'delivery', 'intro']) Object.assign(a[key], {status: 'APPROVED', evidence_sha256: hash(`fixture-only-${locale}-${key}`)});
  Object.assign(a.intro, {canonical_id: 'acdc-cardinal-intro-v1-fixture', transcript: 'SYNTHETIC TEST INTRO, NOT LANGUAGE APPROVAL',
    transcript_sha256: hash('SYNTHETIC TEST INTRO, NOT LANGUAGE APPROVAL'), wav_sha256: hash('fixture-only-intro')});
  if (listening) Object.assign(a.listening, {status: 'APPROVED', evidence_sha256: hash(`fixture-only-${locale}-listening`),
    asset_set_sha256: pack.assetSetHash(manifest, locale)});
  manifest.approvals_sha256 = pack.digest(manifest.approvals);
}
let receipt, terminal = 1;
try {
  // This is a real deterministic conversion of synthetic master PCM, not an
  // independently generated phone waveform blessed by equal duration.
  waves.telephony = wrapPcm(pack.resampleMaster(waves.master), 8000);
  measured.telephony = pack.inspectWave(waves.telephony, 8000);
  const pendingDir = directory('pending'), pending = pack.createManifest(); save(pendingDir, pending);
  group('exact 584-role inventory, isolated from historical callback identities', () => {
    equal(pack.plan().length, 584);
    equal(Object.fromEntries(catalog.REQUIRED_LOCALES.map(l => [l, pack.plan(l).length])),
      {'en-us': 31, 'he-il': 131, 'fr-fr': 161, 'es-es': 53, 'ar-sa': 208});
    equal(pack.CATALOG_HASH, pack.digest(catalog.PROMPTS));
    for (const p of pack.plan()) {
      const original = catalog.PROMPTS.find(c => c.locale === p.locale && c.id === p.id);
      equal(p.catalog_record_sha256, pack.digest(original)); equal(p.transcript_sha256, hash(p.transcript));
      equal(p.context_sha256, pack.digest(pack.contexts[p.locale]));
      assert(p.id.startsWith('acdc-cardinal-v1-')); assertions++;
    }
    equal(pack.plan('ar-sa').every(p => p.authoring_status === 'provisional-needs-language-review'), true);
    const detached = pack.plan(); detached[0].transcript = 'changed'; equal(pack.plan()[0].transcript, catalog.PROMPTS[0].transcript);
    equal(pack.readManifest(pendingDir), pending);
    rejects(() => pack.verifyEntry(pendingDir, pending.prompts[0]), 'ENTRY_TECHNICAL_QA_INCOMPLETE');
    rejects(() => pack.verifyPack(pendingDir), 'CARDINAL_PACK_INCOMPLETE');
  });
  group('versioned speech recipes preserve every legacy request and exact transcript', () => {
    equal(pack.DEFAULT_SYNTHESIS_RECIPE, 'cardinal-verbatim-v1');
    equal(pack.CONCISE_SYNTHESIS_RECIPE, 'cardinal-concise-v2');
    equal(pack.SYNTHESIS_RECIPES, ['cardinal-verbatim-v1', 'cardinal-concise-v2']);
    equal(Object.isFrozen(pack.SYNTHESIS_RECIPES), true);
    const languages = {'en-us': 'American English', 'es-es': 'Spanish from Spain', 'fr-fr': 'French from France',
      'he-il': 'Israeli Hebrew', 'ar-sa': 'Modern Standard Arabic'};
    for (const entry of pack.plan()) {
      // Independent literal legacy oracle: changes to the v1 implementation
      // cannot silently re-pin all historical provider request hashes.
      const legacyText = `Read the transcript below verbatim in native ${languages[entry.locale]}. `
        + 'Use a professional, warm, natural adult female call-center voice. '
        + (entry.locale === 'ar-sa'
          ? 'This is one complete pausal chunk; preserve its written internal inflection and end at a natural pause. '
          : 'This is one complete prerecorded cardinal-number chunk. ')
        + 'Speak clearly at a comfortable conversational pace. Only speak the transcript: no introduction, added words, music or sound effects. '
        + `Do not rush or omit words; the complete chunk must fit within 10 seconds.\n\nTranscript:\n${entry.transcript}`;
      const body = {contents: [{parts: [{text: legacyText}]}], generationConfig: {responseModalities: ['AUDIO'],
        speechConfig: {voiceConfig: {prebuiltVoiceConfig: {voiceName: 'Sulafat'}}}}};
      equal(JSON.stringify(pack.requestBody(entry)), JSON.stringify(body));
      equal(pack.requestBody(entry, pack.DEFAULT_SYNTHESIS_RECIPE), body);
      const concise = pack.requestBody(entry, pack.CONCISE_SYNTHESIS_RECIPE);
      const conciseText = `Speak the following transcript verbatim in ${languages[entry.locale]} with a professional, warm, natural adult female voice.`
        + (entry.locale === 'ar-sa' ? ' This is one complete pausal chunk; preserve its written internal inflection and end at a natural pause.' : '')
        + `\n\nTranscript:\n${entry.transcript}`;
      equal(concise, {...body, contents: [{parts: [{text: conciseText}]}]});
      equal(conciseText.length < legacyText.length, true);
    }
    for (const recipe of [null, false, 2, '', 'unknown', 'CARDINAL-CONCISE-V2', {}, [], ['cardinal-concise-v2']])
      rejects(() => pack.requestBody(pending.prompts[0], recipe), 'INVALID_SYNTHESIS_RECIPE');
    for (const recipe of pack.SYNTHESIS_RECIPES) {
      const changed = {...pending.prompts[0], transcript: 'different words'};
      rejects(() => pack.requestBody(changed, recipe), 'CATALOG_TRANSCRIPT_OR_CONTEXT_CHANGED');
    }
    equal(pack.MODEL, 'gemini-2.5-pro-preview-tts'); equal(pack.VOICE, 'Sulafat'); equal(pack.MAX_DURATION_SECONDS, 10);
  });
  group('manifest/schema/catalog/context mutations fail closed', () => {
    const mutations = [
      m => m.schema_version++, m => m.owner = 'other', m => m.catalog_version = 'acdc-cardinal-v2',
      m => m.catalog_sha256 = '0'.repeat(64), m => m.provider = 'other', m => m.voice = 'other', m => m.model = 'other',
      m => m.prompts.pop(), m => m.prompts[1] = m.prompts[0], m => m.prompts[0].id = 'acdc-number-0',
      m => m.prompts[0].transcript = 'wrong', m => m.prompts[0].transcript_sha256 = '0'.repeat(64),
      m => m.prompts[0].context_sha256 = '0'.repeat(64), m => m.prompts[0].kind = 'other',
      m => m.prompts[0].value++, m => m.prompts[0].catalog_record_sha256 = '0'.repeat(64),
      m => m.prompts.find(p => p.locale === 'ar-sa').authoring_status = 'approved',
      m => m.prompts.find(p => p.locale === 'he-il').joined = true,
      m => m.runtime_ready = true, m => m.deployed = true, m => m.full_position_numeric_range_ready = true,
      m => m.artifact_complete = true, m => m.key_file = '/not/a/credential',
      m => m.conversion.transformations = 'trim-and-pad', m => m.conversion.recipe_sha256 = '0'.repeat(64),
      m => m.conversion.version = '14.4.1', m => m.approvals.pop()
    ];
    for (const mutate of mutations) { const m = copy(pending); mutate(m); rejects(() => pack.validateManifest(pendingDir, m)); }
    rejects(() => pack.main(['--generate', pendingDir]), 'INVALID_READ_ONLY_OPTIONS');
    rejects(() => pack.main(['--verify-only', pendingDir, '--key-file', '/not/a/credential']), 'INVALID_READ_ONLY_OPTIONS');
  });
  group('strict WAV format, exact payload and measured edges without transformation', () => {
    const original = Buffer.from(waves.master), info = pack.inspectWave(waves.master, 24000);
    equal(info.sample_count, 6000); equal(info.leading_silence_samples, 240); equal(info.trailing_silence_samples, 480);
    equal(info.pcm_sha256, hash(waves.master.subarray(44))); equal(waves.master, original);
    equal(pack.technicalQa(info), info);
    for (const mutate of [b => b.write('RIFX'), b => b.writeUInt32LE(0, 4), b => b.writeUInt16LE(3, 20),
      b => b.writeUInt16LE(2, 22), b => b.writeUInt32LE(16000, 24), b => b.writeUInt32LE(1, 28),
      b => b.writeUInt16LE(1, 32), b => b.writeUInt16LE(8, 34), b => b.writeUInt32LE(0xffffffff, 40)]) {
      const b = Buffer.from(original); mutate(b); rejects(() => pack.inspectWave(b, 24000));
    }
    rejects(() => pack.inspectWave(original.subarray(0, original.length - 1), 24000));
    rejects(() => pack.inspectWave(original, 8000));
    rejects(() => pack.technicalQa(pack.inspectWave(fixtureWave(8000, 0.1), 8000)), 'AUDIO_DURATION_OUT_OF_BOUNDS');
    rejects(() => pack.technicalQa(pack.inspectWave(fixtureWave(8000, 10.01), 8000)), 'AUDIO_DURATION_OUT_OF_BOUNDS');
    rejects(() => pack.technicalQa(pack.inspectWave(fixtureWave(8000, 0.25, 'silence'), 8000)), 'AUDIO_SILENT_OR_TOO_QUIET');
    rejects(() => pack.technicalQa(pack.inspectWave(fixtureWave(8000, 0.25, 'clipped'), 8000)), 'AUDIO_CLIPPED');
    for (const chunk of [original.subarray(12, 36), original.subarray(36)]) {
      const b = Buffer.concat([original, chunk]); b.writeUInt32LE(b.length - 8, 4); rejects(() => pack.inspectWave(b, 24000));
    }
  });
  const completeDir = directory('all-584-synthetic'), complete = copy(pending);
  complete.prompts = complete.prompts.map(e => completedEntry(completeDir, e));
  complete.requests_reserved = 584; complete.artifact_complete = true;
  complete.conversion.version = pack.RESAMPLING.version; save(completeDir, complete);
  group('all 1168 WAV identities pass technical QA but confer no approval/readiness', () => {
    const result = pack.verifyPack(completeDir);
    equal(result.prompts, 584); equal(result.technical_qa_complete, true);
    equal(result.resampling_provenance_verified, true); equal(result.resampling_recipe_sha256, pack.digest(pack.RESAMPLING));
    for (const k of ['declared_authoring_approval', 'declared_listening_approval', 'independently_pinned_approval',
      'intro_audio_verified', 'provider_provenance_authenticated', 'runtime_ready', 'deployed', 'full_position_numeric_range_ready']) equal(result[k], false);
    rejects(() => pack.verifyPack(completeDir, complete.approvals_sha256), 'AUTHORING_APPROVAL_PENDING');
    for (const locale of catalog.REQUIRED_LOCALES) assert(/^[a-f0-9]{64}$/.test(pack.assetSetHash(complete, locale)));
    assertions += 5;
  });
  group('entry provenance, exact file identity and every saved PCM metric are checked', () => {
    const e = complete.prompts[0]; equal(pack.verifyEntry(completeDir, e), e);
    for (const mutate of [
      x => x.attempts[0].synthesis_instruction += ' extra', x => x.attempts[0].instruction_sha256 = '0'.repeat(64),
      x => x.attempts[0].request_body_sha256 = '0'.repeat(64), x => x.attempts[0].raw_pcm_sha256 = '0'.repeat(64),
      x => x.attempts[0].provider_finish_reason = 'MAX_TOKENS', x => x.attempts[0].provider_finish_reason = 'unsafe provider text',
      x => x.attempts[0].reserved_at = 'invalid', x => x.attempts[0].master.file = '../outside.wav',
      x => x.attempts[0].master.file = x.attempts[0].master.file.replace('attempt-1', 'attempt-2'),
      x => x.attempts[0].master.file = complete.prompts[1].attempts[0].master.file,
      x => x.attempts[0].master.extra = true, x => x.attempts[0].master = null,
      x => x.attempts[0].telephony = null, x => x.attempts[0].failure_code = 'FAILED',
      x => x.attempts[0].number = 2, x => x.generation_status = 'PENDING'
    ]) { const x = copy(e); mutate(x); rejects(() => pack.verifyEntry(completeDir, x)); }
    for (const variant of ['master', 'telephony']) for (const key of Object.keys(measured[variant])) {
      const x = copy(e); x.attempts[0][variant][key] = typeof measured[variant][key] === 'number' ? measured[variant][key] + 1 : '0'.repeat(64);
      rejects(() => pack.verifyEntry(completeDir, x), 'AUDIO_HASH_OR_METRICS_CHANGED');
    }
    const target = path.join(completeDir, e.attempts[0].telephony.file), changed = Buffer.from(waves.telephony);
    changed.writeInt16LE(1111, 1000); fs.writeFileSync(target, changed);
    try { rejects(() => pack.verifyEntry(completeDir, e), 'AUDIO_HASH_OR_METRICS_CHANGED'); }
    finally { fs.writeFileSync(target, waves.telephony); }
  });
  group('pending/in-flight/failure ledgers and explicit bounded retry retain provenance', () => {
    const dir = directory('retry'), m = copy(pending), e = m.prompts[0];
    m.conversion.version = pack.RESAMPLING.version; m.requests_reserved = 1;
    e.generation_status = 'REQUESTING'; e.attempts = [attempt(e)];
    equal(pack.validateManifest(dir, m), m);
    const inFlightRetry = copy(m); inFlightRetry.retry_request_budget = 1; inFlightRetry.retries_explicitly_enabled = true;
    inFlightRetry.requests_reserved = 2; inFlightRetry.prompts[0].attempts.push(attempt(e, 2));
    rejects(() => pack.validateManifest(dir, inFlightRetry), 'RETRY_OF_SUCCESS_OR_INDETERMINATE_REQUEST');
    e.generation_status = 'FAILED'; e.attempts = [attempt(e, 1, 'FAILED')];
    equal(pack.validateManifest(dir, m), m);
    m.prompts[0] = completedEntry(dir, {...e, attempts: []}, 2);
    m.requests_reserved = 2; m.retry_request_budget = 1; m.retries_explicitly_enabled = true;
    equal(pack.validateManifest(dir, m), m);
    const failedHash = pack.digest(m.prompts[0].attempts[0]);
    save(dir, m); equal(pack.digest(pack.readManifest(dir).prompts[0].attempts[0]), failedHash);
    for (const mutate of [x => x.requests_reserved--, x => x.retry_request_budget = 0,
      x => x.retries_explicitly_enabled = false, x => x.automatic_retries = 1,
      x => x.initial_request_budget = 585, x => x.retry_request_budget = 585,
      x => x.prompts[0].attempts[0].status = 'REQUESTING', x => x.prompts[0].attempts[0].failure_code = 'unsafe text',
      x => x.prompts[0].attempts.push(attempt(e, 3)), x => x.conversion.version = null]) {
      const bad = copy(m); mutate(bad); rejects(() => pack.validateManifest(dir, bad));
    }
    const retrySuccess = copy(complete.prompts[0]); retrySuccess.attempts.push(attempt(retrySuccess, 2)); retrySuccess.generation_status = 'REQUESTING';
    rejects(() => pack.verifyEntry(completeDir, retrySuccess), 'RETRY_OF_SUCCESS_OR_INDETERMINATE_REQUEST');
  });
  group('mixed recipe ledgers require exact provenance without resetting history or retry limits', () => {
    const dir = directory('mixed-recipes'), m = copy(pending), v2 = pack.CONCISE_SYNTHESIS_RECIPE;
    const e = completedEntry(dir, m.prompts[0], 2, v2), legacy = copy(e.attempts[0]);
    m.prompts[0] = e; m.requests_reserved = 2; m.retry_request_budget = 1;
    m.retries_explicitly_enabled = true; m.conversion.version = pack.RESAMPLING.version;
    equal(pack.validateManifest(dir, m), m); equal(pack.verifyEntry(dir, e), e);
    save(dir, m); equal(pack.readManifest(dir).prompts[0].attempts[0], legacy);
    equal(Object.hasOwn(legacy, 'synthesis_recipe'), false);
    const explicitLegacy = copy(e); explicitLegacy.attempts[0].synthesis_recipe = pack.DEFAULT_SYNTHESIS_RECIPE;
    equal(pack.verifyEntry(dir, explicitLegacy), explicitLegacy);
    for (const value of [undefined, null, '', 'unknown', 2, false, {}, []]) {
      const bad = copy(e); bad.attempts[1].synthesis_recipe = value;
      rejects(() => pack.verifyEntry(dir, bad), 'INVALID_SYNTHESIS_RECIPE');
    }
    for (const mutate of [
      a => { delete a.synthesis_recipe; }, a => { a.synthesis_recipe = pack.DEFAULT_SYNTHESIS_RECIPE; },
      a => { a.synthesis_instruction += ' extra'; a.instruction_sha256 = hash(a.synthesis_instruction); },
      a => { a.request_body_sha256 = legacy.request_body_sha256; }
    ]) {
      const bad = copy(e); mutate(bad.attempts[1]);
      rejects(() => pack.verifyEntry(dir, bad), 'INVALID_REQUEST_PROVENANCE');
    }
    const relabeled = copy(e); relabeled.attempts[0].synthesis_recipe = v2;
    rejects(() => pack.verifyEntry(dir, relabeled), 'INVALID_REQUEST_PROVENANCE');
    const extra = copy(e); extra.attempts[1].recipe = v2;
    rejects(() => pack.verifyEntry(dir, extra), 'UNEXPECTED_FIELDS');
    // Recomputing both hashes cannot bless changed words, Arabic delivery or
    // another voice: verification reconstructs the exact allowlisted body.
    const ar = pending.prompts.find(p => p.locale === 'ar-sa');
    for (const mutate of [
      b => { b.contents[0].parts[0].text += ' extra words'; },
      b => { b.contents[0].parts[0].text = b.contents[0].parts[0].text.replace('preserve its written internal inflection', 'omit internal inflection'); },
      b => { b.generationConfig.speechConfig.voiceConfig.prebuiltVoiceConfig.voiceName = 'other'; }
    ]) {
      const bad = {...ar, generation_status: 'FAILED', attempts: [attempt(ar, 1, 'FAILED', v2)]};
      const body = copy(pack.requestBody(ar, v2)); mutate(body);
      Object.assign(bad.attempts[0], {synthesis_instruction: body.contents[0].parts[0].text,
        instruction_sha256: hash(body.contents[0].parts[0].text), request_body_sha256: hash(JSON.stringify(body))});
      rejects(() => pack.verifyEntry(dir, bad), 'INVALID_REQUEST_PROVENANCE');
    }
    equal(pack.MAX_ATTEMPTS, 2); equal(pack.HARD_MAX_ATTEMPTS, 6);
    const six = copy(m); six.prompts[0] = {...pending.prompts[0], generation_status: 'FAILED',
      attempts: Array.from({length: 6}, (_, i) => attempt(pending.prompts[0], i + 1, 'FAILED', i ? v2 : undefined))};
    six.requests_reserved = 6; six.retry_request_budget = 5;
    equal(pack.validateManifest(dir, six), six);
    const seven = copy(six); seven.prompts[0].attempts.push(attempt(pending.prompts[0], 7, 'FAILED', v2));
    seven.requests_reserved = 7; seven.retry_request_budget = 6;
    rejects(() => pack.validateManifest(dir, seven), 'INVALID_ATTEMPT_HISTORY');
    const requesting = copy(e); requesting.attempts[0] = attempt(e, 1, 'REQUESTING');
    rejects(() => pack.verifyEntry(dir, requesting), 'RETRY_OF_SUCCESS_OR_INDETERMINATE_REQUEST');
    const success = copy(e); success.attempts.push(attempt(e, 3, 'REQUESTING', v2)); success.generation_status = 'REQUESTING';
    rejects(() => pack.verifyEntry(dir, success), 'RETRY_OF_SUCCESS_OR_INDETERMINATE_REQUEST');
    const budget = copy(six); budget.retry_request_budget = 585;
    rejects(() => pack.validateManifest(dir, budget));
    equal(e.attempts[0], legacy);
  });
  group('partial output from failed attempts remains byte-pinned and never becomes QA', () => {
    const e = copy(complete.prompts[0]); e.generation_status = e.attempts[0].status = 'FAILED';
    e.attempts[0].failure_code = 'LOCAL_OPERATION_FAILED'; e.attempts[0].telephony = null;
    const m = copy(pending); m.prompts[0] = e; m.requests_reserved = 1; m.conversion.version = pack.RESAMPLING.version;
    equal(pack.validateManifest(completeDir, m), m);
    e.attempts[0].master.sha256 = '0'.repeat(64);
    rejects(() => pack.validateManifest(completeDir, m), 'AUDIO_HASH_OR_METRICS_CHANGED');
    const durationDir = directory('duration'), d = completedEntry(durationDir, pending.prompts[0]);
    const file = path.join(durationDir, d.attempts[0].telephony.file), different = fixtureWave(8000, 0.251);
    fs.writeFileSync(file, different); d.attempts[0].telephony = {file: d.attempts[0].telephony.file, ...pack.inspectWave(different, 8000)};
    rejects(() => pack.verifyEntry(durationDir, d), 'RESAMPLING_CHANGED_DURATION');
  });
  group('equal-duration different-frequency audio is rejected by actual SoX replay', () => {
    equal(pack.resampleMaster(waves.master), pack.resampleMaster(waves.master));
    const dir = directory('unrelated-telephony'), e = completedEntry(dir, pending.prompts[0]);
    const other = fixtureWave(8000, 0.25, 'normal', 900), metrics = pack.technicalQa(pack.inspectWave(other, 8000));
    equal(metrics.duration_seconds, e.attempts[0].master.duration_seconds);
    assert.notEqual(metrics.pcm_sha256, measured.telephony.pcm_sha256); assertions++;
    const file = e.attempts[0].telephony.file; fs.writeFileSync(path.join(dir, file), other);
    // All saved hashes/metrics honestly describe the unrelated waveform.
    e.attempts[0].telephony = {file, ...metrics};
    rejects(() => pack.verifyEntry(dir, e), 'TELEPHONY_NOT_EXACT_MASTER_RESAMPLE');
    const m = copy(complete); m.prompts[0] = e;
    // Put the mismatched pair under the complete fixture's exact identity too:
    // full release verification must not offer a duration-only acceptance mode.
    const liveFixtureFile = path.join(completeDir, file); fs.writeFileSync(liveFixtureFile, other); save(completeDir, m);
    try { rejects(() => pack.verifyPack(completeDir), 'TELEPHONY_NOT_EXACT_MASTER_RESAMPLE'); }
    finally { fs.writeFileSync(liveFixtureFile, waves.telephony); save(completeDir, complete); }
  });
  group('SoX recipe, isolated environment, limits and all subprocess errors fail closed', () => {
    const originalSpawn = cp.spawnSync, validVersion = Buffer.from('/usr/bin/sox: SoX v14.4.2\n');
    try {
      const failures = [
        {error: Error('fixture transport'), status: null, signal: null, stdout: Buffer.alloc(0), stderr: Buffer.alloc(0)},
        {status: 1, signal: null, stdout: validVersion, stderr: Buffer.alloc(0)},
        {status: 0, signal: 'SIGTERM', stdout: validVersion, stderr: Buffer.alloc(0)},
        {status: 0, signal: null, stdout: validVersion, stderr: Buffer.from('warning')}
      ];
      for (const result of failures) { cp.spawnSync = () => result; rejects(() => pack.resampleMaster(waves.master), 'SOX_REPLAY_FAILED'); }
      cp.spawnSync = () => ({status: 0, signal: null, stdout: Buffer.from('sox: SoX v14.4.1\n'), stderr: Buffer.alloc(0)});
      rejects(() => pack.resampleMaster(waves.master), 'SOX_VERSION_MISMATCH');
      let calls = 0;
      cp.spawnSync = (tool, argv, options) => {
        equal(tool, '/usr/bin/sox'); equal(options.env, {PATH: '/usr/bin:/bin', LC_ALL: 'C', TZ: 'UTC'});
        equal(options.shell, false); equal(options.encoding, null); assert(options.timeout > 0 && options.timeout <= 5000); assertions++;
        if (calls++ === 0) { equal(argv, ['--version']); equal(options.input, undefined); }
        else { equal(argv, [...pack.RESAMPLING.argv]); equal(options.input, waves.master); }
        return {status: 0, signal: null, stdout: calls === 1 ? validVersion : Buffer.alloc(1), stderr: Buffer.alloc(0)};
      };
      rejects(() => pack.resampleMaster(waves.master), 'INVALID_REPLAY_PCM'); equal(calls, 2);
    } finally { cp.spawnSync = originalSpawn; }
  });
  group('transcript/intro/delivery approvals require independent pin; AR/HE remain explicit', () => {
    const m = copy(pending);
    rejects(() => pack.requireAuthoringApproval(m, ['ar-sa'], m.approvals_sha256), 'AUTHORING_APPROVAL_PENDING');
    rejects(() => pack.requireAuthoringApproval(m, ['he-il'], m.approvals_sha256), 'AUTHORING_APPROVAL_PENDING');
    approve(m, 'ar-sa'); equal(pack.requireAuthoringApproval(m, ['ar-sa'], m.approvals_sha256), true);
    rejects(() => pack.requireAuthoringApproval(m, ['ar-sa']), 'INDEPENDENT_APPROVAL_PIN_REQUIRED');
    rejects(() => pack.requireAuthoringApproval(m, ['ar-sa'], '0'.repeat(64)), 'INDEPENDENT_APPROVAL_PIN_REQUIRED');
    rejects(() => pack.requireAuthoringApproval(m, ['ar-sa', 'ar-sa'], m.approvals_sha256), 'INVALID_LOCALE_SELECTION');
    for (const mutate of [a => a.context_sha256 = '0'.repeat(64), a => a.locale_catalog_sha256 = '0'.repeat(64),
      a => a.intro.semantic_frame = 'ticket-number', a => a.delivery.policy = 'trim-and-pad',
      a => a.intro.transcript_sha256 = '0'.repeat(64), a => a.intro.wav_sha256 = null,
      a => a.transcript.evidence_sha256 = null, a => a.intro.canonical_id = '../intro.wav']) {
      const bad = copy(m); mutate(bad.approvals.find(a => a.locale === 'ar-sa')); bad.approvals_sha256 = pack.digest(bad.approvals);
      rejects(() => pack.requireAuthoringApproval(bad, ['ar-sa'], bad.approvals_sha256));
    }
    const changed = copy(m); changed.approvals.find(a => a.locale === 'ar-sa').intro.transcript += ' changed';
    rejects(() => pack.requireAuthoringApproval(changed, ['ar-sa'], m.approvals_sha256), 'APPROVAL_SET_CHANGED');
  });
  group('listening approval binds exact locale audio, distinct from technical QA', () => {
    const m = copy(complete);
    for (const locale of catalog.REQUIRED_LOCALES) approve(m, locale);
    save(completeDir, m);
    try {
      rejects(() => pack.verifyPack(completeDir, m.approvals_sha256), 'LISTENING_APPROVAL_PENDING');
      for (const locale of catalog.REQUIRED_LOCALES) approve(m, locale, true);
      save(completeDir, m); const result = pack.verifyPack(completeDir, m.approvals_sha256);
      equal(result.declared_authoring_approval, true); equal(result.declared_listening_approval, true);
      equal(result.independently_pinned_approval, true); equal(result.runtime_ready, false); equal(result.intro_audio_verified, false);
      const bad = copy(m); bad.approvals[0].listening.asset_set_sha256 = '0'.repeat(64); bad.approvals_sha256 = pack.digest(bad.approvals);
      rejects(() => pack.requireAuthoringApproval(bad, catalog.REQUIRED_LOCALES, bad.approvals_sha256), 'LISTENING_ASSETS_CHANGED');
      const unpinned = pack.verifyPack(completeDir); equal(unpinned.independently_pinned_approval, false);
    } finally { save(completeDir, complete); }
  });
  group('filesystem traversal, symlinks, hardlinks, permissions and malformed input reject', () => {
    rejects(() => pack.readManifest(pendingDir + '/../' + path.basename(pendingDir)), 'INVALID_PACK_DIRECTORY');
    rejects(() => pack.readManifest('/tmp'), 'INVALID_PACK_DIRECTORY');
    const linked = path.join(output, 'symlink-pack'); fs.symlinkSync(pendingDir, linked);
    rejects(() => pack.readManifest(linked), 'INVALID_PACK_DIRECTORY');
    const dir = directory('symlink-manifest'); fs.symlinkSync(path.join(pendingDir, 'manifest.json'), path.join(dir, 'manifest.json'));
    rejects(() => pack.readManifest(dir), 'INVALID_REGULAR_FILE');
    const hard = directory('hardlink-manifest'); fs.linkSync(path.join(pendingDir, 'manifest.json'), path.join(hard, 'manifest.json'));
    try { rejects(() => pack.readManifest(hard), 'INVALID_REGULAR_FILE'); }
    finally { fs.unlinkSync(path.join(hard, 'manifest.json')); }
    const badJson = directory('bad-json'); fs.writeFileSync(path.join(badJson, 'manifest.json'), '{broken', {mode: 0o600});
    rejects(() => pack.readManifest(badJson), 'INVALID_MANIFEST_JSON');
    const writable = directory('writable'); save(writable, pending); fs.chmodSync(writable, 0o777);
    rejects(() => pack.readManifest(writable), 'INVALID_PACK_DIRECTORY');
    const fileMode = directory('writable-file'); save(fileMode, pending); fs.chmodSync(path.join(fileMode, 'manifest.json'), 0o666);
    rejects(() => pack.readManifest(fileMode), 'INVALID_REGULAR_FILE');
    const localeLink = directory('symlink-locale'); fs.symlinkSync(path.join(completeDir, 'en-us'), path.join(localeLink, 'en-us'));
    rejects(() => pack.verifyEntry(localeLink, complete.prompts[0]), 'INVALID_PACK_DIRECTORY');
  });
  group('sandboxed module has read-only local imports and no provider/key/environment capability', () => {
    const source = fs.readFileSync(require.resolve('./acdc-cardinal-pack.cjs'), 'utf8'), reads = [], imports = [];
    const allowedMethods = new Set(['lstatSync', 'realpathSync', 'openSync', 'readSync', 'fstatSync', 'closeSync']);
    const readonlyFs = new Proxy({}, {get(_target, key) {
      if (key === 'constants') return fs.constants;
      assert(allowedMethods.has(key), 'Unexpected filesystem operation: ' + String(key));
      return (...args) => {
        if (typeof args[0] === 'string') { assert(args[0] === pendingDir || args[0].startsWith(pendingDir + '/')); reads.push(args[0]); }
        if (key === 'openSync') assert.equal(args[1] & (fs.constants.O_WRONLY | fs.constants.O_RDWR | fs.constants.O_CREAT | fs.constants.O_TRUNC), 0);
        return fs[key](...args);
      };
    }});
    let context;
    const sandbox = {Buffer, module: {exports: {}}, console: {log() { throw Error('Unexpected output'); }}, require(name) {
      imports.push(name);
      // The frozen catalog data must inhabit the sandbox's Object realm too;
      // the verifier deliberately rejects non-plain cross-realm input objects.
      if (name === './acdc-cardinal-catalog.cjs') return vm.runInContext('JSON.parse(' + JSON.stringify(JSON.stringify(catalog)) + ')', context);
      return {'node:fs': readonlyFs, 'node:path': path, 'node:crypto': crypto,
        'node:child_process': {spawnSync() { throw Error('Pending metadata must not execute SoX'); }}}[name]
        || assert.fail('Forbidden import: ' + name);
    }};
    context = vm.createContext(sandbox);
    vm.runInContext(source, context, {filename: 'cardinal-pack-readonly.cjs', timeout: 5000});
    const result = sandbox.module.exports.readManifest(pendingDir);
    equal(result.prompts.length, 584); equal(imports, ['node:fs', 'node:path', 'node:crypto', 'node:child_process', './acdc-cardinal-catalog.cjs']);
    assert(reads.length > 0); assertions++;
    const count = reads.length;
    assert.throws(() => sandbox.module.exports.main(['--generate', pendingDir])); assertions++;
    equal(reads.length, count);
  });
  terminal = 0;
  receipt = {schema_version: 1, fixture_only: true, groups, assertions, complete_catalog_roles: 584,
    synthetic_wav_files: 1168, provider_calls: 0, resampling_recipe_sha256: pack.digest(pack.RESAMPLING),
    actual_sox_replay: true, runtime_ready: false, native_acceptance: false,
    language_review_performed: false, output_directory: output};
} catch (error) {
  receipt = {schema_version: 1, fixture_only: true, groups, assertions, runtime_ready: false,
    native_acceptance: false, failure: {name: error.name, message: error.message}, output_directory: output};
  console.error(error.stack);
} finally {
  const after = pins(), stable = JSON.stringify(before) === JSON.stringify(after);
  receipt = {...receipt, source_hashes_before: before, source_hashes_after: after, source_stable: stable,
    terminal_exit: stable ? terminal : 1};
  fs.writeFileSync(path.join(output, 'receipt.json'), JSON.stringify(receipt, null, 2) + '\n', {flag: 'wx', mode: 0o600});
  console.log(JSON.stringify(receipt)); process.exitCode = receipt.terminal_exit;
}
