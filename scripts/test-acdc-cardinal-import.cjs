#!/usr/bin/env node
'use strict';

// Offline fixture only. The full real validator/SoX recipe and existing
// create-only media writer run; only CouchDB is doubled. Retain every fixture.
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const crypto = require('node:crypto'), assert = require('node:assert/strict');
const cp = require('node:child_process'), http = require('node:http'), https = require('node:https');
const pack = require('./acdc-cardinal-pack.cjs');
const hash = (bytes, algorithm = 'sha256', encoding = 'hex') => crypto.createHash(algorithm).update(bytes).digest(encoding);
const clone = value => JSON.parse(JSON.stringify(value));
const root = path.resolve(__dirname, '..');
const introSource = path.join(__dirname, 'assets/acdc-gemini-fixed-20260905/en-us/acdc-queue-your-current-position-is.telephony-8000.wav');
const introSources = Object.freeze(Object.fromEntries(['en-us', 'es-es', 'fr-fr', 'he-il', 'ar-sa'].map(locale =>
  [locale, ['he-il', 'ar-sa'].includes(locale)
    ? path.join(__dirname, 'assets/acdc-gemini-cardinal-intros-20260907', locale,
      'acdc-cardinal-intro-v1-current-position-number.attempt-1.telephony-8000.wav')
    : path.join(__dirname, 'assets/acdc-gemini-fixed-20260905', locale,
      'acdc-queue-your-current-position-is.telephony-8000.wav')])));
const reuseSources = {
  cardinal: path.join(__dirname, 'assets/acdc-gemini-cardinals-20260907/manifest.json'),
  supplemental: path.join(__dirname, 'assets/acdc-gemini-supplemental-20260906'),
  aliases: path.join(__dirname, 'acdc-cardinal-reuse-es-20260907.json')
};
const modelTrialSource = path.join(__dirname, 'assets/acdc-gemini-cardinal-model-trials-20260907/format-compatible');
const inputs = [__filename, path.join(__dirname, 'import-acdc-gemini-cardinals.cjs'),
  path.join(__dirname, 'acdc-cardinal-pack.cjs'), path.join(__dirname, 'acdc-cardinal-catalog.cjs'),
  path.join(__dirname, 'import-acdc-gemini-voices.cjs'), path.join(__dirname, 'import-acdc-language-packs.cjs'),
  path.join(root, 'applications/acdc/src/acdc_gemini_map.hrl'), ...Object.values(introSources), '/usr/bin/sox',
  reuseSources.cardinal, reuseSources.aliases, path.join(reuseSources.supplemental, 'manifest.json'),
  ...[4, 9].map(n => path.join(reuseSources.supplemental, `es-es/acdc-number-${n}.master-24000.wav`)),
  path.join(root, 'doc/acdc_cardinal_exact_word_reuse.md')];
inputs.push(path.join(modelTrialSource, 'trial.json'), ...['01-he-il-acdc-cardinal-v1-tens-30',
  '03-es-es-acdc-cardinal-v1-number-13'].flatMap(base => ['master-24000', 'telephony-8000']
  .map(variant => path.join(modelTrialSource, `${base}.${variant}.wav`))));
const pins = () => Object.fromEntries([...new Set([...inputs, ...Object.keys(require.cache).filter(f => f.startsWith(__dirname + '/'))])]
  .sort().map(file => [file, hash(fs.readFileSync(file))]));
const output = fs.mkdtempSync(path.join(os.tmpdir(), 'acdc-cardinal-import-proof.'));
assert.equal(fs.realpathSync(output), output); fs.chmodSync(output, 0o700);
const originalSpawn = cp.spawnSync, originalHttp = http.request, originalHttps = https.request, originalFetch = globalThis.fetch;
let soxCalls = 0, checks = 0, terminal = 1, failure, before, importer, media, sequence = 0;
const groups = [];
const equal = (a, b) => { checks++; assert.deepEqual(a, b); };
const rejects = (fn, code) => { checks++; assert.throws(fn, e => e instanceof Error && (!code || e.code === code)); };
const rejectsAsync = async (fn, code) => { checks++; await assert.rejects(fn, e => e instanceof Error && (!code || e.code === code)); };
async function group(name, fn) { await fn(); groups.push(name); console.log('PASS ' + name); }
function write(file, value) {
  fs.mkdirSync(path.dirname(file), {recursive: true, mode: 0o700});
  fs.writeFileSync(file, Buffer.isBuffer(value) ? value : JSON.stringify(value) + '\n', {mode: 0o600});
}
function wav(pcm, rate) {
  const h = Buffer.alloc(44); h.write('RIFF'); h.writeUInt32LE(pcm.length + 36, 4); h.write('WAVEfmt ', 8);
  h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22); h.writeUInt32LE(rate, 24);
  h.writeUInt32LE(rate * 2, 28); h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34); h.write('data', 36);
  h.writeUInt32LE(pcm.length, 40); return Buffer.concat([h, pcm]);
}
function tone(rate, frequency = 500) {
  const pcm = Buffer.alloc(rate / 2);
  for (let i = 0; i < rate / 4; i++) pcm.writeInt16LE(Math.round(1200 * Math.cos(i * 2 * Math.PI * frequency / rate)), i * 2);
  return wav(pcm, rate);
}
let master, phone, prototype;
function attempt(entry, status, number) {
  const body = pack.requestBody(entry), instruction = body.contents[0].parts[0].text;
  return {number, status, reserved_at: '2026-09-07T00:00:00.000Z', synthesis_instruction: instruction,
    instruction_sha256: hash(instruction), request_body_sha256: hash(JSON.stringify(body)),
    failure_code: status === 'FAILED' ? 'AUDIO_GENERATION_NOT_COMPLETE' : null,
    provider_finish_reason: status === 'FAILED' ? 'OTHER' : status === 'QA_PASSED' ? 'STOP' : null,
    raw_pcm_sha256: null, master: null, telephony: null};
}
function fixture(name) {
  const location = path.join(output, `${++sequence}-${name}`);
  fs.cpSync(prototype, location, {recursive: true});
  const cardinalDirectory = path.join(location, 'cardinal'), introFile = path.join(location, 'intro.wav');
  const manifest = JSON.parse(fs.readFileSync(path.join(cardinalDirectory, 'manifest.json')));
  return {location, cardinalDirectory, introFile, approvalSha256: manifest.approvals_sha256, locale: 'en-us', manifest};
}
function source(f) { return {cardinalDirectory: f.cardinalDirectory, introFile: f.introFile, approvalSha256: f.approvalSha256,
  locale: f.locale, ...(f.aliasSha256 ? {supplementalDirectory: f.supplementalDirectory,
    aliasFile: f.aliasFile, aliasSha256: f.aliasSha256} : {}),
  ...(f.modelTrialIndex ? {modelTrialIndex: f.modelTrialIndex, modelTrialIndexSha256: f.modelTrialIndexSha256} : {})}; }
function save(f) { write(path.join(f.cardinalDirectory, 'manifest.json'), f.manifest); }
function open(f) { return importer.openPlan(source(f)); }
function localeFixture(locale) {
  const f = fixture(locale); f.locale = locale;
  const approval = f.manifest.approvals.find(a => a.locale === locale);
  for (const name of ['transcript', 'delivery', 'intro']) Object.assign(approval[name], {status: 'APPROVED', evidence_sha256: '1'.repeat(64)});
  Object.assign(approval.intro, importer.INTROS[locale]);
  write(f.introFile, fs.readFileSync(introSources[locale]));
  for (const entry of f.manifest.prompts.filter(e => e.locale === locale)) {
    const a = attempt(entry, 'QA_PASSED', 1); a.raw_pcm_sha256 = pack.inspectWave(master, 24000).pcm_sha256;
    for (const [variant, bytes, rate] of [['master', master, 24000], ['telephony', phone, 8000]]) {
      const file = pack.fileName(entry, 1, variant); write(path.join(f.cardinalDirectory, file), bytes);
      a[variant] = {file, ...pack.technicalQa(pack.inspectWave(bytes, rate))};
    }
    entry.generation_status = 'QA_PASSED'; entry.attempts = [a];
  }
  f.manifest.requests_reserved = f.manifest.prompts.reduce((n, e) => n + e.attempts.length, 0);
  f.manifest.approvals_sha256 = f.approvalSha256 = pack.digest(f.manifest.approvals);
  save(f); return f;
}
function document(asset, timestamp) {
  const doc = {...media.document(asset, timestamp), ...(asset.resolution ? {source_cardinal_resolution: clone(asset.resolution)} : {})};
  if (asset.resolution?.source_kind === 'separate_model_trial') doc.source_voice.model = asset.resolution.model;
  return doc;
}
function nativeDoc(asset) {
  const doc = document(asset, 0); doc._rev = '1-' + 'a'.repeat(32);
  const attachment = doc._attachments[asset.attachment];
  attachment.digest = asset.md5; attachment.length = asset.bytes.length;
  return doc;
}
function assets(f) {
  const build = (id, transcript, bytes, file) => {
    const sha256 = hash(bytes), promptId = `${id}-gemini-sulafat-${sha256.slice(0, 16)}`;
    return {locale: f.locale, canonical_id: id, prompt_id: promptId, id: `${f.locale}/${promptId}`, attachment: `${promptId}.wav`,
      sha256, md5: 'md5-' + hash(bytes, 'md5', 'base64'), bytes, source_file: path.relative(root, file), transcript_sha256: transcript};
  };
  const definition = importer.INTROS[f.locale];
  const intro = build(definition.canonical_id, definition.transcript_sha256, fs.readFileSync(f.introFile), f.introFile);
  if (f.aliasSha256) {
    const resolver = require('./acdc-cardinal-reuse.cjs').openResolution({cardinalDirectory: f.cardinalDirectory,
      supplementalDirectory: f.supplementalDirectory, aliasFile: f.aliasFile, aliasSha256: f.aliasSha256});
    const summary = open(f).summary();
    const index = f.modelTrialIndex ? JSON.parse(fs.readFileSync(f.modelTrialIndex)) : null;
    const trials = index ? require('./acdc-cardinal-model-trial-assets.cjs').openResolution({sourceDirectory: f.cardinalDirectory,
      sourceManifestSha256: index.source_manifest_sha256, approvalSha256: f.approvalSha256,
      trials: index.trials.map(t => ({directory: path.join(path.dirname(f.modelTrialIndex), t.directory), sha256: t.sha256}))}) : null;
    const trialSummary = trials?.summary();
    const cardinal = pack.plan(f.locale).map(entry => {
      const retained = f.manifest.prompts.find(e => e.locale === f.locale && e.id === entry.id);
      const resolved = retained.generation_status !== 'QA_PASSED' && trialSummary?.successful_identities.includes(`${f.locale}/${entry.id}`)
        ? trials.resolve(f.locale, entry.id) : resolver.resolve(f.locale, entry.id), p = resolved.provenance;
      const file = resolved.source_kind === 'generated_cardinal'
        ? path.join(f.cardinalDirectory, retained.attempts.at(-1).telephony.file)
        : resolved.source_kind === 'separate_model_trial'
          ? path.join(f.location, 'model-trial', `01-${f.locale}-${entry.id}.telephony-8000.wav`)
        : path.join(f.supplementalDirectory, `${p.source_locale}/${p.source_id}.master-24000.wav`);
      return {...build(entry.id, entry.transcript_sha256, resolved.telephony, file),
        resolution: {...summary.prompts.find(p => p.id === entry.id).resolution,
          resolved_asset_set_sha256: summary.resolved_asset_set_sha256}};
    }).sort((a, b) => a.id.localeCompare(b.id, 'en'));
    return {intro, cardinal};
  }
  const cardinal = f.manifest.prompts.filter(e => e.locale === f.locale && e.generation_status === 'QA_PASSED').map(e => {
    const file = path.join(f.cardinalDirectory, e.attempts.at(-1).telephony.file);
    return build(e.id, e.transcript_sha256, fs.readFileSync(file), file);
  }).sort((a, b) => a.id.localeCompare(b.id, 'en'));
  return {intro, cardinal};
}
function database(f, {installed = false, hook = () => undefined} = {}) {
  const plan = assets(f), docs = new Map([[plan.intro.id, nativeDoc(plan.intro)]]), calls = [];
  if (installed) for (const asset of plan.cardinal) docs.set(asset.id, nativeDoc(asset));
  // Unrelated media is observable in the double and must remain untouched.
  docs.set('en-us/customer-recording', {_id: 'en-us/customer-recording', protected: 'unchanged'});
  const client = async (method, resource, body) => {
    const call = {method, resource, body: clone(body)}; calls.push(call);
    const overridden = hook({method, resource, body, docs, calls, plan});
    if (overridden !== undefined) return overridden;
    if (method === 'POST') {
      equal(resource, '_all_docs?include_docs=true&attachments=true&conflicts=true');
      return {status: 200, body: {rows: body.keys.map(key => docs.has(key)
        ? {key, id: key, doc: clone(docs.get(key))} : {key, error: 'not_found'})}};
    }
    equal(method, 'PUT'); equal(body._rev, undefined); equal(decodeURIComponent(resource), body._id);
    const asset = [...plan.cardinal, ...(['he-il', 'ar-sa'].includes(f.locale) ? [plan.intro] : [])].find(a => a.id === body._id);
    assert(asset, 'Only selected cardinal identities and new HE/AR intros may be created');
    equal(body, document(asset, (body.pvt_created - 62167219200) * 1000));
    if (docs.has(asset.id)) return {status: 409, body: {error: 'conflict'}};
    docs.set(asset.id, nativeDoc(asset));
    return {status: 201, body: {ok: true, id: asset.id, rev: docs.get(asset.id)._rev}};
  };
  return {client, calls, docs, plan};
}
function reuseFixture(name) {
  const f = localeFixture('es-es');
  const retained = JSON.parse(fs.readFileSync(reuseSources.cardinal));
  for (const n of [4, 9]) {
    const id = `acdc-cardinal-v1-number-${n}`;
    const index = f.manifest.prompts.findIndex(e => e.locale === f.locale && e.id === id);
    f.manifest.prompts[index] = clone(retained.prompts.find(e => e.locale === f.locale && e.id === id));
  }
  f.manifest.requests_reserved = f.manifest.prompts.reduce((n, e) => n + e.attempts.length, 0);
  f.supplementalDirectory = path.join(f.location, 'supplemental-' + name);
  f.aliasFile = path.join(f.location, 'aliases.json');
  write(f.aliasFile, fs.readFileSync(reuseSources.aliases)); f.aliasSha256 = hash(fs.readFileSync(f.aliasFile));
  write(path.join(f.supplementalDirectory, 'manifest.json'), fs.readFileSync(path.join(reuseSources.supplemental, 'manifest.json')));
  for (const n of [4, 9]) {
    const file = `es-es/acdc-number-${n}.master-24000.wav`;
    write(path.join(f.supplementalDirectory, file), fs.readFileSync(path.join(reuseSources.supplemental, file)));
  }
  save(f); return f;
}
function modelFixture() {
  const f = reuseFixture('model'), retained = JSON.parse(fs.readFileSync(reuseSources.cardinal));
  for (const [locale, id] of [['es-es', 'acdc-cardinal-v1-number-13'], ['he-il', 'acdc-cardinal-v1-tens-30']]) {
    const index = f.manifest.prompts.findIndex(e => e.locale === locale && e.id === id);
    f.manifest.prompts[index] = clone(retained.prompts.find(e => e.locale === locale && e.id === id));
  }
  f.manifest.approvals[f.manifest.approvals.findIndex(a => a.locale === 'he-il')] = clone(retained.approvals.find(a => a.locale === 'he-il'));
  f.manifest.approvals_sha256 = f.approvalSha256 = pack.digest(f.manifest.approvals);
  f.manifest.requests_reserved = f.manifest.prompts.reduce((n, e) => n + e.attempts.length, 0);
  f.manifest.retry_request_budget = f.manifest.prompts.reduce((n, e) => n + Math.max(0, e.attempts.length - 1), 0);
  f.manifest.retries_explicitly_enabled = f.manifest.retry_request_budget > 0; save(f);
  f.modelTrialIndex = path.join(f.location, 'trial-index.json');
  f.trialIndex = {schema_version: 1, owner: importer.TRIAL_INDEX_OWNER,
    source_manifest_sha256: hash(fs.readFileSync(path.join(f.cardinalDirectory, 'manifest.json'))),
    catalog_sha256: pack.CATALOG_HASH, approvals_sha256: f.approvalSha256, trials: [],
    runtime_ready: false, native_listening_approved: false};
  appendModelTrial(f, 'es-es', 'model-trial'); return f;
}
function saveIndex(f) {
  write(f.modelTrialIndex, f.trialIndex); f.modelTrialIndexSha256 = hash(fs.readFileSync(f.modelTrialIndex));
}
function appendModelTrial(f, locale, relative) {
  const ledger = JSON.parse(fs.readFileSync(path.join(modelTrialSource, 'trial.json')));
  const entry = ledger.entries.find(e => e.locale === locale), directory = path.join(f.location, relative);
  for (const variant of ['master', 'telephony']) {
    const original = path.join(modelTrialSource, entry[variant].file);
    entry[variant].file = `01-${locale}-${entry.id}.${variant === 'master' ? 'master-24000' : 'telephony-8000'}.wav`;
    write(path.join(directory, entry[variant].file), fs.readFileSync(original));
  }
  Object.assign(ledger, {entries: [entry], request_limit: 1, requests_reserved: 1,
    source_manifest_sha256: f.trialIndex.source_manifest_sha256, source_requests_reserved: f.manifest.requests_reserved,
    source_retry_budget: f.manifest.retry_request_budget, approvals_sha256: f.approvalSha256});
  write(path.join(directory, 'trial.json'), ledger);
  f.trialIndex.trials.push({directory: relative, sha256: hash(fs.readFileSync(path.join(directory, 'trial.json')))}); saveIndex(f);
}
function treePins(directory, relative = '') {
  const result = {};
  for (const name of fs.readdirSync(path.join(directory, relative)).sort()) {
    const file = path.join(relative, name), stat = fs.lstatSync(path.join(directory, file));
    if (stat.isDirectory()) Object.assign(result, treePins(directory, file));
    else if (stat.isFile()) result[file] = hash(fs.readFileSync(path.join(directory, file)));
  }
  return result;
}
async function run() {
  http.request = https.request = globalThis.fetch = () => assert.fail('Real network/provider access forbidden');
  cp.spawnSync = (command, argv, options) => {
    equal(command, '/usr/bin/sox'); equal(options.shell, false);
    equal(options.env, {PATH: '/usr/bin:/bin', LC_ALL: 'C', TZ: 'UTC'});
    equal(argv, argv.length === 1 ? ['--version'] : [...pack.RESAMPLING.argv]);
    soxCalls++; return originalSpawn(command, argv, options);
  };
  importer = require('./import-acdc-gemini-cardinals.cjs'); media = require('./import-acdc-gemini-voices.cjs');
  before = pins();
  master = tone(24000); phone = wav(pack.resampleMaster(master), 8000);
  prototype = path.join(output, 'prototype'); const directory = path.join(prototype, 'cardinal');
  fs.mkdirSync(directory, {recursive: true, mode: 0o700});
  const manifest = pack.createManifest(), approval = manifest.approvals.find(a => a.locale === 'en-us');
  for (const name of ['transcript', 'delivery', 'intro']) Object.assign(approval[name], {status: 'APPROVED', evidence_sha256: '1'.repeat(64)});
  Object.assign(approval.intro, importer.INTRO);
  manifest.approvals_sha256 = pack.digest(manifest.approvals);
  for (const entry of manifest.prompts.filter(e => e.locale === 'en-us')) {
    const a = attempt(entry, 'QA_PASSED', 1); a.raw_pcm_sha256 = pack.inspectWave(master, 24000).pcm_sha256;
    for (const [variant, bytes, rate] of [['master', master, 24000], ['telephony', phone, 8000]]) {
      const file = pack.fileName(entry, 1, variant); write(path.join(directory, file), bytes);
      a[variant] = {file, ...pack.technicalQa(pack.inspectWave(bytes, rate))};
    }
    entry.generation_status = 'QA_PASSED'; entry.attempts = [a];
  }
  const failed = manifest.prompts.find(e => e.locale === 'es-es' && e.id === 'acdc-cardinal-v1-number-4');
  failed.generation_status = 'FAILED'; failed.attempts = [attempt(failed, 'FAILED', 1), attempt(failed, 'FAILED', 2)];
  manifest.requests_reserved = 33; manifest.retry_request_budget = 1; manifest.retries_explicitly_enabled = true;
  manifest.conversion.version = pack.RESAMPLING.version;
  write(path.join(directory, 'manifest.json'), manifest); write(path.join(prototype, 'intro.wav'), fs.readFileSync(introSource));
  const base = fixture('valid'), opened = open(base), originalTree = treePins(base.location);
  await group('full584 partial ledger, exact31 EN, failed histories and approved existing intro retained', () => {
    const s = opened.summary(); equal(s.count, 31); equal(s.historical_requests_reserved, 33);
    equal(s.historical_artifact_complete, false); equal(s.locale_catalog_sha256, pack.LOCALE_HASHES['en-us']);
    equal(s.intro.wav_sha256, hash(fs.readFileSync(introSource))); equal(s.selected_asset_set_sha256, pack.assetSetHash(base.manifest, 'en-us'));
    for (const key of ['runtime_ready', 'full_position_language_ready', 'five_language_release_ready', 'listening_verified', 'provider_provenance_authenticated']) equal(s[key], false);
    equal(s.prompts.length, 31); equal(new Set(s.prompts.map(e => e.id)).size, 31);
    const header = opened.renderMap(); equal((header.match(/    \{<<"en-us">>/g) || []).length, 31);
    const parsedRows = header.split('\n').filter(line => line.startsWith('    {')).map(line =>
      JSON.parse(line.trim().replace(/^\{/, '[').replace(/\},?$/, ']').replace(/<<|>>/g, '')));
    const expectedRows = assets(base).cardinal.map(a => [a.locale, a.canonical_id, a.prompt_id,
      a.sha256, a.md5, a.bytes.length, a.transcript_sha256]);
    equal(parsedRows, expectedRows); equal(hash(JSON.stringify(parsedRows)), s.map_sha256);
    equal(header.includes('GEMINI_ASSETS'), false); equal(header.includes('CARDINAL_EN_CONTEXT_SHA256'), true);
    equal(header, opened.renderMap()); s.prompts.length = 0; equal(opened.summary().prompts.length, 31);
  });
  await group('unsupported locales, incomplete CLI and approval pins reject before source or network access', async () => {
    for (const locale of ['en', 'he', 'ar', 'EN-US', 'de-de', 'all', undefined,
      ['he-il'], {toString: () => 'ar-sa'}, null]) {
      rejects(() => importer.openPlan({...source(base), cardinalDirectory: '/missing/source', locale}), 'CARDINAL_LOCALE_NOT_STAGED');
    }
    rejects(() => importer.openPlan({...source(base), approvalSha256: '0'.repeat(64)}), 'INDEPENDENT_APPROVAL_PIN_REQUIRED');
    const args = ['--plan', '--locale', 'en-us', '--cardinal-pack', base.cardinalDirectory, '--intro-file', base.introFile, '--approval-sha256', base.approvalSha256];
    equal(importer.options(args).source, source(base));
    for (const locale of Object.keys(importer.COUNTS)) {
      const selectedArgs = [...args]; selectedArgs[2] = locale;
      equal(importer.options(selectedArgs).source.locale, locale);
    }
    for (const invalid of [[], ['--all-locales'], [...args, '--plan'], [...args, '--import'], [...args, '--unknown'], args.slice(0, -1)]) {
      await rejectsAsync(() => importer.main(invalid));
    }
  });
  await group('incomplete EN and mutated catalog/context/intro cannot reach the database', () => {
    for (const kind of ['pending', 'duplicate', 'context', 'unapproved', 'intro']) {
      const f = fixture(kind), entry = f.manifest.prompts[0], a = f.manifest.approvals[0];
      if (kind === 'pending') { entry.attempts = []; entry.generation_status = 'PENDING'; f.manifest.requests_reserved--; }
      if (kind === 'duplicate') f.manifest.prompts[1] = clone(entry);
      if (kind === 'context') entry.context_sha256 = '0'.repeat(64);
      if (kind === 'unapproved') { a.transcript.status = 'PENDING'; a.transcript.evidence_sha256 = null; }
      if (kind === 'intro') { a.intro.transcript = 'Your ticket is.'; a.intro.transcript_sha256 = hash(a.intro.transcript); }
      f.manifest.approvals_sha256 = f.approvalSha256 = pack.digest(f.manifest.approvals); save(f); rejects(() => open(f));
    }
  });
  await group('source WAV tampering, same-duration wrong resample and file aliasing are rejected', () => {
    const wrong = fixture('wrong-frequency'), entry = wrong.manifest.prompts[0], a = entry.attempts[0];
    const bytes = tone(8000, 900); write(path.join(wrong.cardinalDirectory, a.telephony.file), bytes);
    a.telephony = {file: a.telephony.file, ...pack.technicalQa(pack.inspectWave(bytes, 8000))}; save(wrong);
    rejects(() => open(wrong), 'TELEPHONY_NOT_EXACT_MASTER_RESAMPLE');
    for (const kind of ['tamper', 'symlink', 'hardlink', 'writable']) {
      const f = fixture(kind), file = f.introFile;
      if (kind === 'tamper') { const b = fs.readFileSync(file); b[100] ^= 1; write(file, b); }
      if (kind === 'writable') fs.chmodSync(file, 0o666);
      if (kind === 'symlink' || kind === 'hardlink') { fs.renameSync(file, file + '.retained'); fs[kind === 'symlink' ? 'symlinkSync' : 'linkSync'](file + '.retained', file); }
      rejects(() => open(f));
    }
  });
  await group('missing installed intro prevents all31 creates', async () => {
    const db = database(base); db.docs.delete(db.plan.intro.id);
    await rejectsAsync(() => opened.install(db.client, true)); equal(db.calls.some(c => c.method === 'PUT'), false);
  });
  await group('create-only31, exact native attachments, idempotence and read-only verification', async () => {
    const db = database(base), receipt = await opened.install(db.client, true);
    equal(receipt.created, 31); equal(receipt.verified, 31); equal(receipt.intro_installed_verified, true);
    equal(receipt.installed, db.plan.cardinal.map(a => ({locale: a.locale, canonical_id: a.canonical_id,
      prompt_id: a.prompt_id, document_id: a.id, attachment: a.attachment, sha256: a.sha256,
      revision: '1-' + 'a'.repeat(32)})));
    equal(db.calls.filter(c => c.method === 'PUT').length, 31); equal(receipt.database_requests <= 128, true);
    equal(db.docs.get('en-us/customer-recording'), {_id: 'en-us/customer-recording', protected: 'unchanged'});
    const first = clone([...db.docs]); db.calls.length = 0;
    const again = await opened.install(db.client, true); equal(again.created, 0); equal(again.preserved, 31);
    equal(db.calls.every(c => c.method === 'POST'), true); equal([...db.docs], first);
    const verified = await opened.install(db.client, false); equal(verified.mode, 'VERIFY_ONLY'); equal(verified.verified, 31);
  });
  await group('409 preserves exact concurrent audio, rejects different winner without revision retry', async () => {
    for (const mismatch of [false, true]) {
      const db = database(base, {hook: ({method, body, docs, plan}) => {
        if (method !== 'PUT') return;
        const asset = plan.cardinal.find(a => a.id === body._id), doc = nativeDoc(asset);
        if (mismatch) doc.source_voice.transcript_sha256 = '0'.repeat(64);
        docs.set(asset.id, doc); return {status: 409, body: {error: 'conflict'}};
      }});
      if (mismatch) { await rejectsAsync(() => opened.install(db.client, true)); equal(db.calls.filter(c => c.method === 'PUT').length, 1); }
      else { const r = await opened.install(db.client, true); equal(r.created, 0); equal(r.verified, 31); }
      equal(db.calls.filter(c => c.method === 'PUT').every(c => c.body._rev === undefined), true);
    }
  });
  await group('existing conflict metadata, foreign ownership and wrong downloaded bytes fail closed', async () => {
    for (const kind of ['conflict', 'owner', 'bytes', 'attachment', 'row']) {
      const db = database(base, {installed: true}); const first = db.docs.get(db.plan.cardinal[0].id);
      if (kind === 'conflict') first._conflicts = ['2-' + 'b'.repeat(32)];
      if (kind === 'owner') first.source_type = 'customer';
      if (kind === 'bytes') { const name = Object.keys(first._attachments)[0]; first._attachments[name].data = tone(8000, 900).toString('base64'); }
      if (kind === 'attachment') first._attachments.extra = clone(Object.values(first._attachments)[0]);
      if (kind === 'row') first._id = db.plan.cardinal[1].id;
      await rejectsAsync(() => opened.install(db.client, true)); equal(db.calls.some(c => c.method === 'PUT'), false);
    }
  });
  await group('transport ambiguity and uncorrelated create acknowledgement never retry a write', async () => {
    for (const kind of ['transport', 'ack']) {
      const db = database(base, {hook: ({method}) => {
        if (method !== 'PUT') return;
        if (kind === 'transport') throw new Error('controlled transport failure');
        return {status: 201, body: {ok: true, id: 'foreign', rev: '1-' + 'a'.repeat(32)}};
      }});
      await rejectsAsync(() => opened.install(db.client, true)); equal(db.calls.filter(c => c.method === 'PUT').length, 1);
    }
  });
  await group('all four additional complete locales, exact intro pins, scoped maps and bounded idempotent creates', async () => {
    for (const locale of ['es-es', 'fr-fr', 'he-il', 'ar-sa']) {
      const f = localeFixture(locale), snapshot = open(f), beforeTree = treePins(f.location);
      const s = snapshot.summary(), count = importer.COUNTS[locale], newIntro = ['he-il', 'ar-sa'].includes(locale);
      equal(s.locale, locale); equal(s.count, count); equal(s.prompts.length, count);
      equal(s.locale_catalog_sha256, pack.LOCALE_HASHES[locale]);
      equal(s.selected_asset_set_sha256, pack.assetSetHash(f.manifest, locale));
      equal(s.intro.wav_sha256, hash(fs.readFileSync(introSources[locale])));
      for (const k of ['runtime_ready', 'full_position_language_ready', 'five_language_release_ready', 'listening_verified']) equal(s[k], false);
      const header = snapshot.renderMap(), prefix = 'CARDINAL_' + locale.slice(0, 2).toUpperCase();
      const rows = header.split('\n').filter(line => line.startsWith('    {')).map(line =>
        JSON.parse(line.trim().replace(/^\{/, '[').replace(/\},?$/, ']').replace(/<<|>>/g, '')));
      equal(rows.length, count); equal(rows.every(row => row[0] === locale), true);
      equal(hash(JSON.stringify(rows)), s.map_sha256); equal(header.includes(prefix + '_INTRO_ASSET'), true);
      equal(header.includes('CARDINAL_EN_'), false); equal(header.includes('GEMINI_ASSETS'), false);
      const db = database(f); db.docs.delete(db.plan.intro.id);
      await rejectsAsync(() => snapshot.install(db.client, false)); equal(db.calls.some(c => c.method === 'PUT'), false);
      db.calls.length = 0;
      if (!newIntro) {
        await rejectsAsync(() => snapshot.install(db.client, true)); equal(db.calls.some(c => c.method === 'PUT'), false);
        db.docs.set(db.plan.intro.id, nativeDoc(db.plan.intro)); db.calls.length = 0;
      }
      const receipt = await snapshot.install(db.client, true);
      equal(receipt.created, count); equal(receipt.verified, count); equal(receipt.intro_created, newIntro ? 1 : 0);
      equal(db.calls.filter(c => c.method === 'PUT').length, count + (newIntro ? 1 : 0));
      equal(receipt.database_requests <= receipt.database_request_limit, true);
      if (locale === 'ar-sa') equal(receipt.database_requests > 128, true);
      equal(db.calls.filter(c => c.method === 'PUT').every(c => c.body._id.startsWith(locale + '/') && c.body._rev === undefined), true);
      equal(db.docs.get('en-us/customer-recording'), {_id: 'en-us/customer-recording', protected: 'unchanged'});
      db.calls.length = 0;
      const again = await snapshot.install(db.client, true); equal(again.created, 0); equal(again.preserved, count);
      equal(again.intro_created, 0); equal(db.calls.every(c => c.method === 'POST'), true);
      equal(treePins(f.location), beforeTree);
      const entry = f.manifest.prompts.find(e => e.locale === locale);
      entry.attempts = []; entry.generation_status = 'PENDING'; f.manifest.requests_reserved--; save(f);
      rejects(() => open(f), 'CARDINAL_LOCALE_INCOMPLETE');
    }
  });
  await group('new intro source/approval substitution and cross-locale ledger corruption are rejected', async () => {
    const f = localeFixture('he-il'), original = clone(f.manifest);
    const approval = f.manifest.approvals.find(a => a.locale === f.locale);
    approval.intro.wav_sha256 = importer.INTROS['ar-sa'].wav_sha256;
    f.manifest.approvals_sha256 = f.approvalSha256 = pack.digest(f.manifest.approvals); save(f);
    rejects(() => open(f), 'APPROVED_LOCALE_INTRO_CHANGED');
    f.manifest = clone(original); f.approvalSha256 = original.approvals_sha256; save(f);
    write(f.introFile, fs.readFileSync(introSources['ar-sa']));
    rejects(() => open(f), 'CARDINAL_SOURCE_HASH_MISMATCH');
    write(f.introFile, fs.readFileSync(introSources['he-il']));
    const snapshot = open(f), db = database(f);
    db.docs.get(db.plan.intro.id)._conflicts = ['2-' + 'b'.repeat(32)];
    await rejectsAsync(() => snapshot.install(db.client, true), 'CARDINAL_MEDIA_CONFLICT');
    equal(db.calls.some(c => c.method === 'PUT'), false);
    f.manifest.prompts.find(e => e.locale === 'fr-fr').context_sha256 = '0'.repeat(64); save(f);
    rejects(() => open(f), 'CATALOG_TRANSCRIPT_OR_CONTEXT_CHANGED');
  });
  const reused = reuseFixture('valid'), reusedTree = treePins(reused.location);
  await group('aliases require explicit complete options and an independent exact byte pin', () => {
    const s = source(reused), args = ['--plan', '--locale', s.locale, '--cardinal-pack', s.cardinalDirectory,
      '--intro-file', s.introFile, '--approval-sha256', s.approvalSha256, '--supplemental-pack', s.supplementalDirectory,
      '--alias-file', s.aliasFile, '--alias-sha256', s.aliasSha256];
    equal(importer.options(args).source, s);
    for (const key of ['supplementalDirectory', 'aliasFile', 'aliasSha256']) {
      const partial = {...s}; delete partial[key];
      rejects(() => importer.openPlan(partial), 'INVALID_CARDINAL_OPTIONS');
    }
    rejects(() => importer.options(args.slice(0, -2)), 'INVALID_CARDINAL_OPTIONS');
    rejects(() => importer.options([...args, '--alias-file', s.aliasFile]), 'DUPLICATE_CARDINAL_OPTION');
    rejects(() => importer.openPlan({...s, aliasSha256: 'not-a-pin', cardinalDirectory: '/missing/source'}), 'INDEPENDENT_ALIAS_PIN_REQUIRED');
    rejects(() => importer.openPlan({...s, aliasSha256: '0'.repeat(64)}), 'ALIAS_PIN_MISMATCH');
    const {supplementalDirectory, aliasFile, aliasSha256, ...generatedOnly} = s;
    rejects(() => importer.openPlan(generatedOnly), 'CARDINAL_LOCALE_INCOMPLETE');
  });
  const reusedPlan = open(reused), reusedSummary = reusedPlan.summary();
  await group('complete ES51 generated plus two exact-word aliases has distinct resolved proof and no listening claim', () => {
    const s = reusedSummary;
    equal(s.count, 53); equal(s.selected_generated, 51); equal(s.selected_reused, 2); equal(s.selected_unresolved, 0);
    equal(s.asset_set_kind, 'cardinal-resolved-assets-v1'); equal(s.historical_generated_asset_set_sha256, null);
    equal(s.selected_asset_set_sha256, s.resolved_asset_set_sha256);
    equal(s.resolved_asset_set_sha256, pack.digest({schema_version: 1, kind: s.asset_set_kind, locale: s.locale,
      intro: importer.INTROS[s.locale], prompts: s.prompts}));
    equal(s.alias_manifest_sha256, reused.aliasSha256);
    for (const k of ['listening_approval_declared', 'resolved_listening_approval_declared', 'listening_verified',
      'runtime_ready', 'full_position_language_ready', 'five_language_release_ready', 'historical_artifact_complete']) equal(s[k], false);
    for (const n of [4, 9]) {
      const id = `acdc-cardinal-v1-number-${n}`, entry = reused.manifest.prompts.find(e => e.locale === 'es-es' && e.id === id);
      const p = s.prompts.find(e => e.id === id).resolution;
      equal(entry.generation_status, 'FAILED'); equal(entry.attempts.length, n === 4 ? 2 : 1);
      equal(p.source_kind, 'reused_supplemental_master'); equal(p.failed_entry_sha256, pack.digest(entry));
      equal(p.alias_manifest_sha256, reused.aliasSha256); equal(p.transcript_sha256, entry.transcript_sha256);
      equal(p.master_sha256, hash(fs.readFileSync(path.join(reused.supplementalDirectory,
        `es-es/acdc-number-${n}.master-24000.wav`))));
      equal(p.attempt, undefined); equal(p.request_body_sha256, undefined);
    }
    equal((reusedPlan.renderMap().match(/    \{<<"es-es">>/g) || []).length, 53);
    equal(treePins(reused.location), reusedTree);
  });
  await group('resolved create-only records bind full provenance and audio hashes with exact idempotent readback', async () => {
    const db = database(reused), r = await reusedPlan.install(db.client, true);
    equal(r.created, 53); equal(r.verified, 53); equal(r.selected_reused, 2);
    for (const a of db.plan.cardinal) {
      const doc = db.docs.get(a.id), p = doc.source_cardinal_resolution;
      equal(p, a.resolution); equal(p.telephony_sha256, a.sha256);
      equal(p.resolved_asset_set_sha256, reusedSummary.resolved_asset_set_sha256);
      equal(p.cardinal_manifest_sha256, undefined);
      equal(p.runtime_ready, false); equal(p.listening_verified, false);
    }
    equal(db.docs.get(db.plan.intro.id).source_cardinal_resolution, undefined);
    const original = clone([...db.docs]); db.calls.length = 0;
    const again = await reusedPlan.install(db.client, true); equal(again.created, 0); equal(again.preserved, 53);
    equal(db.calls.every(c => c.method === 'POST'), true); equal([...db.docs], original);
    equal((await reusedPlan.install(db.client, false)).verified, 53);
    equal(treePins(reused.location), reusedTree);
  });
  await group('unrelated locale progress preserves resolved identity while selected lineage drift cannot overwrite', async () => {
    const f = reuseFixture('unrelated-progress'), first = open(f), previous = first.summary(), db = database(f);
    await first.install(db.client, true); const documents = clone([...db.docs]);
    const other = f.manifest.prompts.find(e => e.locale === 'fr-fr');
    other.generation_status = 'FAILED'; other.attempts = [attempt(other, 'FAILED', 1)];
    f.manifest.requests_reserved++; save(f);
    rejects(() => first.summary(), 'CARDINAL_INPUT_CHANGED');
    const next = open(f), current = next.summary();
    equal(current.cardinal_manifest_sha256 === previous.cardinal_manifest_sha256, false);
    equal(current.resolved_asset_set_sha256, previous.resolved_asset_set_sha256);
    equal(current.prompts, previous.prompts); equal(current.map_sha256, previous.map_sha256);
    db.calls.length = 0; const receipt = await next.install(db.client, true);
    equal(receipt.created, 0); equal(receipt.preserved, 53); equal(db.calls.every(c => c.method === 'POST'), true);
    equal([...db.docs], documents);
    const selected = f.manifest.prompts.find(e => e.locale === 'es-es' && e.id === 'acdc-cardinal-v1-number-5');
    selected.attempts[0].reserved_at = '2026-09-06T00:00:00.000Z'; save(f);
    const changed = open(f); equal(changed.summary().resolved_asset_set_sha256 === current.resolved_asset_set_sha256, false);
    db.calls.length = 0;
    await rejectsAsync(() => changed.install(db.client, true), 'CARDINAL_RESOLUTION_PROVENANCE_MISMATCH');
    equal(db.calls.some(c => c.method === 'PUT'), false); equal([...db.docs], documents);
  });
  await group('resolved missing/altered provenance and 409 winners cannot bypass create-only verification', async () => {
    for (const kind of ['missing', 'digest', 'extra', 'readiness', '409']) {
      const db = database(reused, {installed: kind !== '409', hook: ({method, body, docs, plan}) => {
        if (kind !== '409' || method !== 'PUT') return;
        const a = plan.cardinal.find(a => a.id === body._id), doc = nativeDoc(a);
        delete doc.source_cardinal_resolution; docs.set(a.id, doc);
        return {status: 409, body: {error: 'conflict'}};
      }});
      if (kind !== '409') {
        const doc = db.docs.get(db.plan.cardinal[0].id);
        if (kind === 'missing') delete doc.source_cardinal_resolution;
        if (kind === 'digest') doc.source_cardinal_resolution.resolved_asset_set_sha256 = '0'.repeat(64);
        if (kind === 'extra') doc.source_cardinal_resolution.extra = true;
        if (kind === 'readiness') doc.source_cardinal_resolution.runtime_ready = true;
      }
      await rejectsAsync(() => reusedPlan.install(db.client, true), 'CARDINAL_RESOLUTION_PROVENANCE_MISMATCH');
      equal(db.calls.filter(c => c.method === 'PUT').length, kind === '409' ? 1 : 0);
    }
  });
  await group('one unresolved selected role, forged listening approval and modified failure history remain fatal', () => {
    for (const kind of ['pending', 'listening', 'history']) {
      const f = reuseFixture(kind);
      if (kind === 'pending') {
        const e = f.manifest.prompts.find(e => e.locale === 'es-es' && e.id === 'acdc-cardinal-v1-number-5');
        f.manifest.requests_reserved -= e.attempts.length; e.attempts = []; e.generation_status = 'PENDING';
      }
      if (kind === 'listening') {
        const a = f.manifest.approvals.find(a => a.locale === f.locale);
        Object.assign(a.listening, {status: 'APPROVED', evidence_sha256: '1'.repeat(64),
          asset_set_sha256: reusedSummary.resolved_asset_set_sha256});
        f.manifest.approvals_sha256 = f.approvalSha256 = pack.digest(f.manifest.approvals);
      }
      if (kind === 'history') f.manifest.prompts.find(e => e.locale === 'es-es'
        && e.id === 'acdc-cardinal-v1-number-4').attempts[0].reserved_at = '2026-09-06T00:00:00.000Z';
      save(f); rejects(() => open(f), {pending: 'CARDINAL_AUDIO_UNRESOLVED', listening: 'LISTENING_ASSETS_CHANGED', history: 'FAILED_HISTORY_CHANGED'}[kind]);
    }
  });
  await group('alias, supplemental manifest and master mutations after planning prevent all database access', async () => {
    for (const kind of ['alias', 'manifest', 'master']) {
      const f = reuseFixture('post-open-' + kind), snapshot = open(f);
      const file = kind === 'alias' ? f.aliasFile : path.join(f.supplementalDirectory,
        kind === 'manifest' ? 'manifest.json' : 'es-es/acdc-number-4.master-24000.wav');
      fs.appendFileSync(file, ' ');
      rejects(() => snapshot.summary()); rejects(() => snapshot.renderMap());
      let contacted = false;
      await rejectsAsync(() => snapshot.install(async () => { contacted = true; }, true)); equal(contacted, false);
    }
  });
  const mixed = modelFixture(), mixedTree = treePins(mixed.location), mixedPlan = open(mixed);
  await group('model trial index is explicit, independently pinned, bounded and descendant-only', () => {
    const s = source(mixed), args = ['--plan', '--locale', s.locale, '--cardinal-pack', s.cardinalDirectory,
      '--intro-file', s.introFile, '--approval-sha256', s.approvalSha256,
      '--model-trial-index', s.modelTrialIndex, '--model-trial-index-sha256', s.modelTrialIndexSha256];
    equal(importer.options(args).source.modelTrialIndex, s.modelTrialIndex);
    for (const key of ['modelTrialIndex', 'modelTrialIndexSha256']) {
      const partial = {...s}; delete partial[key]; rejects(() => importer.openPlan(partial), 'INVALID_CARDINAL_OPTIONS');
    }
    rejects(() => importer.options(args.slice(0, -2)), 'INVALID_CARDINAL_OPTIONS');
    rejects(() => importer.options([...args, '--model-trial-index', s.modelTrialIndex]), 'DUPLICATE_CARDINAL_OPTION');
    rejects(() => importer.openPlan({...s, modelTrialIndexSha256: '0'.repeat(64)}), 'CARDINAL_SOURCE_HASH_MISMATCH');
    const f = modelFixture(), original = clone(f.trialIndex);
    for (const mutate of [v => v.extra = true, v => v.runtime_ready = true, v => v.native_listening_approved = true,
      v => v.source_manifest_sha256 = '0'.repeat(64), v => v.trials = [], v => v.trials.push(clone(v.trials[0])),
      v => v.trials[0].directory = '../model-trial', v => v.trials[0].directory = '/absolute/model-trial',
      v => v.trials[0].sha256 = '0'.repeat(64)]) {
      f.trialIndex = clone(original); mutate(f.trialIndex); saveIndex(f); rejects(() => open(f));
    }
    // Explicit trials cannot silently fill missing reviewed aliases or an
    // unlisted failed cardinal. Both paths fail during planning, before DB.
    const {supplementalDirectory, aliasFile, aliasSha256, ...noAliases} = s;
    rejects(() => importer.openPlan(noAliases), 'CARDINAL_LOCALE_INCOMPLETE');
    const {modelTrialIndex, modelTrialIndexSha256, ...noTrials} = s;
    rejects(() => importer.openPlan(noTrials), 'CARDINAL_AUDIO_UNRESOLVED');
  });
  await group('mixed staging preserves original and reused2.5 plus real3.1 provenance without history or readiness claims', async () => {
    const s = mixedPlan.summary(); equal(s.count, 53); equal(s.selected_generated, 50);
    equal(s.selected_reused, 2); equal(s.selected_model_trials, 1); equal(s.additional_trial_requests, 1);
    equal(s.selected_unresolved, 0); equal(s.historical_generated_asset_set_sha256, null);
    equal(s.staged_candidates_only, true); equal(s.model_trial_index_sha256, mixed.modelTrialIndexSha256);
    for (const k of ['runtime_ready', 'native_listening_approved', 'listening_verified', 'resolved_listening_approval_declared',
      'historical_artifact_complete', 'five_language_release_ready']) equal(s[k], false);
    const proof = s.prompts.find(p => p.id === 'acdc-cardinal-v1-number-13').resolution;
    equal(proof.model, 'gemini-3.1-flash-tts-preview'); equal(proof.voice, 'Sulafat');
    equal(proof.source_kind, 'separate_model_trial'); equal(proof.source_manifest_sha256, undefined);
    equal(proof.model_trial_index_sha256, undefined); equal(proof.trial_manifest_sha256, mixed.trialIndex.trials[0].sha256);
    const original = mixed.manifest.prompts.find(e => e.locale === 'es-es' && e.id === 'acdc-cardinal-v1-number-13');
    equal(original.generation_status, 'FAILED'); equal(proof.source_entry_sha256, pack.digest(original));
    const db = database(mixed), receipt = await mixedPlan.install(db.client, true);
    equal(receipt.created, 53); equal(receipt.verified, 53);
    for (const a of db.plan.cardinal) equal(db.docs.get(a.id).source_voice.model, a.resolution.model);
    const trial = db.plan.cardinal.find(a => a.canonical_id === original.id);
    equal(db.docs.get(trial.id).source_voice.model, 'gemini-3.1-flash-tts-preview');
    equal(db.docs.get(trial.id).source_cardinal_resolution.trial_entry_sha256, proof.trial_entry_sha256);
    equal(db.docs.get(db.plan.intro.id).source_voice.model, pack.MODEL);
    db.calls.length = 0;
    equal((await mixedPlan.install(db.client, true)).created, 0); equal(db.calls.every(c => c.method === 'POST'), true);
    equal(db.docs.get(trial.id).source_voice.model, 'gemini-3.1-flash-tts-preview'); // Internal compatibility view never mutates stored data.
    equal(treePins(mixed.location), mixedTree);
  });
  await group('real mixed-model readbacks and conflict winners cannot relabel3.1 as2.5 or backfill provenance', async () => {
    for (const kind of ['model', 'voice', 'provenance', '409']) {
      const db = database(mixed, {installed: true, hook: ({method, body, docs, plan}) => {
        if (kind !== '409' || method !== 'PUT') return;
        const a = plan.cardinal.find(a => a.id === body._id), doc = nativeDoc(a);
        doc.source_voice.model = pack.MODEL; docs.set(a.id, doc);
        return {status: 409, body: {error: 'conflict'}};
      }});
      const a = db.plan.cardinal.find(a => a.resolution.source_kind === 'separate_model_trial'), doc = db.docs.get(a.id);
      if (kind === 'model') doc.source_voice.model = pack.MODEL;
      if (kind === 'voice') doc.source_voice.voice = 'Kore';
      if (kind === 'provenance') delete doc.source_cardinal_resolution;
      if (kind === '409') db.docs.delete(a.id);
      await rejectsAsync(() => mixedPlan.install(db.client, true), kind === 'provenance'
        ? 'CARDINAL_RESOLUTION_PROVENANCE_MISMATCH' : 'CARDINAL_MODEL_PROVENANCE_MISMATCH');
      equal(db.calls.filter(c => c.method === 'PUT').length, kind === '409' ? 1 : 0);
    }
  });
  await group('index growth for unrelated Hebrew trial keeps selectedES identity and zero-write reinstall stable', async () => {
    const f = modelFixture(), first = open(f), before = first.summary(), db = database(f);
    await first.install(db.client, true); const documents = clone([...db.docs]);
    appendModelTrial(f, 'he-il', 'other-model-trial');
    rejects(() => first.summary(), 'CARDINAL_INPUT_CHANGED');
    const next = open(f), after = next.summary();
    equal(after.model_trial_index_sha256 === before.model_trial_index_sha256, false);
    equal(after.additional_trial_requests, 2); equal(after.selected_model_trials, 1);
    equal(after.cardinal_manifest_sha256, before.cardinal_manifest_sha256);
    equal(after.resolved_asset_set_sha256, before.resolved_asset_set_sha256); equal(after.prompts, before.prompts);
    equal(after.map_sha256, before.map_sha256);
    db.calls.length = 0; equal((await next.install(db.client, true)).created, 0);
    equal(db.calls.every(c => c.method === 'POST'), true); equal([...db.docs], documents);
    fs.appendFileSync(path.join(f.location, 'model-trial/trial.json'), ' ');
    let contacted = false; await rejectsAsync(() => next.install(async () => { contacted = true; }, true)); equal(contacted, false);
  });
  await group('final readback catches earlier mutation and exact source pins survive every operation', async () => {
    const db = database(base, {hook: ({method, body, docs, plan}) => {
      if (method === 'POST' && docs.has(plan.cardinal.at(-1).id) && body.keys.length === 10
        && body.keys.includes(plan.cardinal[0].id)) docs.get(plan.cardinal[0].id).source_voice.sha256 = '0'.repeat(64);
    }});
    await rejectsAsync(() => opened.install(db.client, true)); equal(db.calls.filter(c => c.method === 'PUT').length, 31);
    equal(treePins(base.location), originalTree);
    const changed = fixture('post-open'), snapshot = open(changed); fs.appendFileSync(path.join(changed.cardinalDirectory, 'manifest.json'), ' ');
    rejects(() => snapshot.summary(), 'CARDINAL_INPUT_CHANGED'); rejects(() => snapshot.renderMap(), 'CARDINAL_INPUT_CHANGED');
    let contacted = false; await rejectsAsync(() => snapshot.install(async () => { contacted = true; }, true), 'CARDINAL_INPUT_CHANGED'); equal(contacted, false);
    equal(pins(), before);
  });
}
run().then(() => { terminal = 0; }).catch(error => {
  failure = {name: error.name, code: error.code || 'FIXTURE_ASSERTION_FAILED'};
  console.error(error.stack); // Offline synthetic inputs only; never provider/CouchDB responses.
}).finally(() => {
  cp.spawnSync = originalSpawn; http.request = originalHttp; https.request = originalHttps; globalThis.fetch = originalFetch;
  const after = pins(), stable = before !== undefined && JSON.stringify(before) === JSON.stringify(after);
  const receipt = {schema_version: 1, fixture_only: true, groups, checks, source_hashes_before: before || {},
    source_hashes_after: after, source_stable: stable, sox_calls: soxCalls, provider_calls: 0, real_database_requests: 0,
    runtime_ready: false, native_acceptance: false, output_directory: output,
    ...(failure ? {failure} : {}), terminal_exit: stable ? terminal : 1};
  fs.writeFileSync(path.join(output, 'receipt.json'), JSON.stringify(receipt, null, 2) + '\n', {flag: 'wx', mode: 0o600});
  console.log(JSON.stringify(receipt)); process.exitCode = receipt.terminal_exit;
});
