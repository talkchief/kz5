#!/usr/bin/env node
'use strict';

// Offline resolver evidence only. Root executes through the serial resource
// guard. Keep all fixtures and the receipt; never generate/provider-retry audio.
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const crypto = require('node:crypto'), assert = require('node:assert/strict');
const Module = require('node:module'), cp = require('node:child_process');
const pack = require('./acdc-cardinal-pack.cjs');
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const clone = value => JSON.parse(JSON.stringify(value));
const realCardinal = path.join(__dirname, 'assets/acdc-gemini-cardinals-20260907');
const realSupplemental = path.join(__dirname, 'assets/acdc-gemini-supplemental-20260906');
const aliasSource = path.join(__dirname, 'acdc-cardinal-reuse-es-20260907.json');
const resolverSource = path.join(__dirname, 'acdc-cardinal-reuse.cjs');
const reviewSource = path.join(__dirname, '../doc/acdc_cardinal_exact_word_reuse.md');
const supplementalManifestHash = 'dc041f104ab060cdd956ee237aaf004dea2edef1db070e654473a85c13f5b50b';
const sourceMasters = {
  'es-es/acdc-number-4.master-24000.wav': '30f68cacb6c86dbbaaaa68a0f74a6624bef334b0e30107fc5123e004333d047d',
  'es-es/acdc-number-9.master-24000.wav': 'ddc73f17793a69ebdd8fadc9fb0223d252c904185bd25de427f3a6336c914d37'
};
const sourceFiles = [__filename, resolverSource, aliasSource, reviewSource,
  require.resolve('./acdc-cardinal-pack.cjs'), require.resolve('./acdc-cardinal-catalog.cjs'),
  require.resolve('./acdc-gemini-supplemental-catalog.cjs'), '/usr/bin/sox',
  path.join(realCardinal, 'manifest.json'), path.join(realSupplemental, 'manifest.json'),
  ...Object.keys(sourceMasters).map(file => path.join(realSupplemental, file))];
const pins = () => Object.fromEntries(sourceFiles.map(file => [file, hash(fs.readFileSync(file))]));
const before = pins(), output = fs.mkdtempSync(path.join(os.tmpdir(), 'acdc-cardinal-reuse-proof.'));
assert.equal(fs.realpathSync(output), output); fs.chmodSync(output, 0o700);
const imports = [], groups = []; let checks = 0, sequence = 0, soxCalls = 0, reuse;
const equal = (actual, expected) => { checks++; assert.deepEqual(actual, expected); };
function group(name, fn) { fn(); groups.push(name); console.log('PASS ' + name); }
function rejects(fn, code) {
  checks++;
  assert.throws(fn, error => error instanceof Error && (!code || error.code === code));
}
function save(file, value) { fs.writeFileSync(file, JSON.stringify(value) + '\n', {mode: 0o600}); }
function writeNew(file, bytes) {
  fs.mkdirSync(path.dirname(file), {recursive: true, mode: 0o700});
  fs.writeFileSync(file, bytes, {flag: 'wx', mode: 0o600});
}
function wrapPcm(data, rate) {
  const header = Buffer.alloc(44);
  header.write('RIFF'); header.writeUInt32LE(data.length + 36, 4); header.write('WAVEfmt ', 8);
  header.writeUInt32LE(16, 16); header.writeUInt16LE(1, 20); header.writeUInt16LE(1, 22);
  header.writeUInt32LE(rate, 24); header.writeUInt32LE(rate * 2, 28);
  header.writeUInt16LE(2, 32); header.writeUInt16LE(16, 34);
  header.write('data', 36); header.writeUInt32LE(data.length, 40);
  return Buffer.concat([header, data]);
}
function tone(rate, samples = rate / 4, frequency = 500) {
  const pcm = Buffer.alloc(samples * 2);
  for (let i = 0; i < samples; i++) pcm.writeInt16LE(i < rate / 100 || i >= samples - rate / 50
    ? 0 : Math.round(1200 * Math.cos(i * 2 * Math.PI * frequency / rate)), i * 2);
  return wrapPcm(pcm, rate);
}
function success(directory, entry, master, telephony, number = 1, prior = []) {
  const body = pack.requestBody(entry), instruction = body.contents[0].parts[0].text;
  const attempt = {number, status: 'QA_PASSED', reserved_at: '2026-09-07T00:00:00.000Z',
    synthesis_instruction: instruction, instruction_sha256: hash(instruction),
    request_body_sha256: hash(JSON.stringify(body)), failure_code: null,
    provider_finish_reason: 'STOP', raw_pcm_sha256: pack.inspectWave(master, 24000).pcm_sha256};
  for (const [variant, bytes, rate] of [['master', master, 24000], ['telephony', telephony, 8000]]) {
    const file = pack.fileName(entry, number, variant);
    writeNew(path.join(directory, file), bytes);
    attempt[variant] = {file, ...pack.technicalQa(pack.inspectWave(bytes, rate))};
  }
  return {...entry, generation_status: 'QA_PASSED', attempts: [...clone(prior), attempt]};
}
const supplementalBytes = fs.readFileSync(path.join(realSupplemental, 'manifest.json'));
const retained = JSON.parse(fs.readFileSync(path.join(realCardinal, 'manifest.json')));
const aliasBytes = fs.readFileSync(aliasSource), aliasValue = JSON.parse(aliasBytes);
const failures = retained.prompts.filter(entry => entry.locale === 'es-es'
  && ['acdc-cardinal-v1-number-4', 'acdc-cardinal-v1-number-9'].includes(entry.id));
const failurePins = failures.map(entry => ({locale: entry.locale, id: entry.id, sha256: pack.digest(entry)}));
let syntheticMaster, syntheticTelephony;
function fixture(name) {
  const root = path.join(output, `${++sequence}-${name}`), cardinalDirectory = path.join(root, 'cardinal');
  const supplementalDirectory = path.join(root, 'supplemental'), aliasFile = path.join(root, 'aliases.json');
  fs.mkdirSync(cardinalDirectory, {recursive: true, mode: 0o700});
  fs.mkdirSync(supplementalDirectory, {mode: 0o700});
  const manifest = pack.createManifest();
  manifest.prompts = manifest.prompts.map(entry => clone(failures.find(f => f.locale === entry.locale && f.id === entry.id) || entry));
  manifest.prompts[0] = success(cardinalDirectory, manifest.prompts[0], syntheticMaster, syntheticTelephony);
  manifest.requests_reserved = 4; manifest.retry_request_budget = 1; manifest.retries_explicitly_enabled = true;
  manifest.conversion.version = pack.RESAMPLING.version;
  save(path.join(cardinalDirectory, 'manifest.json'), manifest);
  writeNew(path.join(supplementalDirectory, 'manifest.json'), supplementalBytes);
  for (const file of Object.keys(sourceMasters)) writeNew(path.join(supplementalDirectory, file), fs.readFileSync(path.join(realSupplemental, file)));
  writeNew(aliasFile, aliasBytes);
  return {root, manifest, cardinalDirectory, supplementalDirectory, aliasFile, aliasSha256: hash(aliasBytes)};
}
function open(f) {
  return readOnly(() => reuse.openResolution({cardinalDirectory: f.cardinalDirectory,
    supplementalDirectory: f.supplementalDirectory, aliasFile: f.aliasFile, aliasSha256: f.aliasSha256}));
}
function mutateAliases(f, mutate) {
  const value = clone(aliasValue); mutate(value); save(f.aliasFile, value);
  f.aliasSha256 = hash(fs.readFileSync(f.aliasFile));
}
function mutateCardinal(f, mutate) {
  mutate(f.manifest); save(path.join(f.cardinalDirectory, 'manifest.json'), f.manifest);
}
function sourceEntry(value, number = 4) {
  return value.prompts.find(entry => entry.locale === 'es-es' && entry.id === `acdc-number-${number}`);
}
function targetEntry(value, number = 4) {
  return value.prompts.find(entry => entry.locale === 'es-es' && entry.id === `acdc-cardinal-v1-number-${number}`);
}
function treePins(root, relative = '') {
  const result = {};
  for (const name of fs.readdirSync(path.join(root, relative)).sort()) {
    const file = path.join(relative, name), stat = fs.lstatSync(path.join(root, file));
    if (stat.isDirectory()) Object.assign(result, treePins(root, file));
    else result[file] = hash(fs.readFileSync(path.join(root, file)));
  }
  return result;
}
// The resolver may only read local files and execute the pack's fixed SoX
// replay. Deny mutations while it loads or handles every test operation.
function readOnly(fn) {
  const saved = new Map(), mutators = ['writeFileSync', 'appendFileSync', 'writeSync', 'writevSync',
    'mkdirSync', 'mkdtempSync', 'renameSync', 'copyFileSync', 'cpSync', 'unlinkSync', 'rmSync',
    'rmdirSync', 'chmodSync', 'fchmodSync', 'chownSync', 'fchownSync', 'truncateSync',
    'ftruncateSync', 'utimesSync', 'futimesSync', 'linkSync', 'symlinkSync', 'createWriteStream'];
  for (const key of mutators) if (typeof fs[key] === 'function') {
    saved.set(key, fs[key]); fs[key] = () => assert.fail(`Resolver filesystem write forbidden: ${key}`);
  }
  const originalOpen = fs.openSync;
  const savedFetch = globalThis.fetch, subprocesses = new Map();
  globalThis.fetch = () => assert.fail('Resolver network request forbidden');
  for (const key of ['spawn', 'exec', 'execSync', 'execFile', 'execFileSync', 'fork']) {
    subprocesses.set(key, cp[key]); cp[key] = () => assert.fail('Unexpected resolver subprocess: ' + key);
  }
  fs.openSync = (file, flags, ...args) => {
    assert(typeof flags === 'number' && !(flags & (fs.constants.O_WRONLY | fs.constants.O_RDWR
      | fs.constants.O_CREAT | fs.constants.O_TRUNC | fs.constants.O_APPEND)) || flags === 'r');
    return originalOpen(file, flags, ...args);
  };
  try { return fn(); }
  finally {
    fs.openSync = originalOpen; globalThis.fetch = savedFetch;
    for (const [key, value] of saved) fs[key] = value;
    for (const [key, value] of subprocesses) cp[key] = value;
  }
}
const originalSpawn = cp.spawnSync, originalLoad = Module._load;
const allowedImports = new Set(['node:fs', 'node:path', 'node:crypto', 'node:child_process',
  './acdc-cardinal-pack.cjs', './acdc-cardinal-catalog.cjs', './acdc-gemini-supplemental-catalog.cjs']);
cp.spawnSync = (command, argv, options) => {
  assert.equal(command, '/usr/bin/sox'); assert.equal(options.shell, false);
  assert.deepEqual(options.env, {PATH: '/usr/bin:/bin', LC_ALL: 'C', TZ: 'UTC'});
  assert.deepEqual(argv, argv.length === 1 ? ['--version'] : [...pack.RESAMPLING.argv]);
  soxCalls++; return originalSpawn(command, argv, options);
};
let terminal = 1, failure;
try {
  Module._load = function(request, parent, isMain) {
    if (parent && parent.filename === resolverSource) {
      imports.push(request); assert(allowedImports.has(request), 'Unexpected resolver import: ' + request);
    }
    return originalLoad.call(this, request, parent, isMain);
  };
  reuse = readOnly(() => require('./acdc-cardinal-reuse.cjs'));
  syntheticMaster = tone(24000);
  syntheticTelephony = wrapPcm(pack.resampleMaster(syntheticMaster), 8000);
  const base = fixture('valid'), resolver = open(base), initialFixturePins = treePins(base.root);
  group('exact source pins, three retained failures and incomplete 584-role inventory', () => {
    equal(hash(supplementalBytes), supplementalManifestHash);
    equal(hash(fs.readFileSync(reviewSource)), aliasValue.review.evidence_sha256);
    for (const [file, expected] of Object.entries(sourceMasters)) equal(hash(fs.readFileSync(path.join(realSupplemental, file))), expected);
    equal(failures.map(entry => [entry.value, entry.generation_status, entry.attempts.length]), [[4, 'FAILED', 2], [9, 'FAILED', 1]]);
    for (const entry of failures) {
      equal(targetEntry(base.manifest, entry.value), entry);
      equal(pack.digest(entry), aliasValue.aliases.find(alias => alias.target.id === entry.id).target.failed_entry_sha256);
    }
    const summary = readOnly(() => resolver.summary());
    for (const [key, expected] of Object.entries({generated: 1, reused: 2, unresolved: 581,
      historical_requests_reserved: 4, historical_artifact_complete: false, alias_scope_verified: true,
      runtime_ready: false, deployed: false, listening_verified: false, full_position_numeric_range_ready: false})) equal(summary[key], expected);
    equal(summary.cardinal_manifest_sha256, hash(fs.readFileSync(path.join(base.cardinalDirectory, 'manifest.json'))));
    equal(summary.alias_manifest_sha256, base.aliasSha256);
  });
  group('generated default and two whole-word aliases resolve exact audio without old telephone files', () => {
    const generated = readOnly(() => resolver.resolve('en-us', 'acdc-cardinal-v1-number-0'));
    equal(generated.source_kind, 'generated_cardinal'); equal(generated.master, syntheticMaster);
    equal(generated.telephony, syntheticTelephony); equal(generated.provenance.attempt, 1);
    for (const [number, transcript] of [[4, 'cuatro'], [9, 'nueve']]) {
      const id = `acdc-cardinal-v1-number-${number}`, result = readOnly(() => resolver.resolve('es-es', id));
      const master = fs.readFileSync(path.join(realSupplemental, `es-es/acdc-number-${number}.master-24000.wav`));
      equal(result.source_kind, 'reused_supplemental_master'); equal(result.transcript, transcript);
      equal(result.master, master); equal(result.telephony, wrapPcm(pack.resampleMaster(master), 8000));
      equal(result.provenance.failed_entry_sha256, pack.digest(targetEntry(base.manifest, number)));
      equal(result.provenance.source_id, `acdc-number-${number}`);
      equal(result.provenance.source_manifest_sha256, supplementalManifestHash);
      equal(result.provenance.resampling_recipe_sha256, pack.digest(pack.RESAMPLING));
      equal(result.provenance.master_sha256, hash(result.master)); equal(result.provenance.telephony_sha256, hash(result.telephony));
      equal(result.runtime_ready, false); equal(result.listening_verified, false); equal(result.provider_provenance_authenticated, false);
      equal(fs.existsSync(path.join(base.supplementalDirectory, `es-es/acdc-number-${number}.telephony-8000.wav`)), false);
      equal(readOnly(() => resolver.verifyTelephony('es-es', id, result.telephony)), result.provenance);
    }
    rejects(() => readOnly(() => resolver.resolve('es-es', 'acdc-cardinal-v1-number-21')), 'CARDINAL_AUDIO_UNRESOLVED');
    rejects(() => readOnly(() => resolver.resolve('fr-fr', 'acdc-cardinal-v1-terminal-4')), 'CARDINAL_AUDIO_UNRESOLVED');
    rejects(() => readOnly(() => resolver.resolve('es-es', 'acdc-number-4')), 'UNKNOWN_CARDINAL_IDENTITY');
  });
  group('independent alias byte pin, exact schema, review and recipe fail closed', () => {
    const f = fixture('wrong-alias-pin'); f.aliasSha256 = '0'.repeat(64);
    rejects(() => open(f), 'ALIAS_PIN_MISMATCH');
    const mutations = [value => value.extra = true, value => value.schema_version++, value => value.owner = 'other',
      value => value.catalog_sha256 = '0'.repeat(64), value => value.source_manifest_sha256 = '0'.repeat(64),
      value => value.recipe_sha256 = '0'.repeat(64), value => value.runtime_ready = true,
      value => value.deployed = true, value => value.full_position_numeric_range_ready = true,
      value => value.review.kind = 'listening', value => value.review.decision = 'PENDING',
      value => value.review.evidence_sha256 = null, value => value.review.listening_verified = true,
      value => value.aliases.pop(), value => value.aliases.push(clone(value.aliases[0]))];
    for (const mutate of mutations) { const f = fixture('alias-contract'); mutateAliases(f, mutate); rejects(() => open(f)); }
    rejects(() => readOnly(() => reuse.main(['--generate', base.cardinalDirectory])), 'INVALID_READ_ONLY_OPTIONS');
  });
  group('only exact Spanish 4 and 9 target/source identities and transcripts are admitted', () => {
    const mutations = [value => value.aliases[1] = clone(value.aliases[0]),
      value => value.aliases[0].target.locale = 'fr-fr', value => value.aliases[0].target.id = 'acdc-cardinal-v1-number-5',
      value => value.aliases[0].target.transcript = 'cuatro cinco', value => value.aliases[0].target.transcript_sha256 = '0'.repeat(64),
      value => value.aliases[0].target.context_sha256 = '0'.repeat(64), value => value.aliases[0].target.catalog_record_sha256 = '0'.repeat(64),
      value => value.aliases[0].source.locale = 'en-us', value => value.aliases[0].source.id = 'acdc-number-5',
      value => value.aliases[0].source.provider = 'other', value => value.aliases[0].source.model = 'other',
      value => value.aliases[0].source.voice = 'Kore', value => value.aliases[0].source.entry_sha256 = '0'.repeat(64),
      value => value.aliases[0].source.master_sha256 = '0'.repeat(64), value => value.aliases[0].source.master_file = '../outside.wav'];
    for (const mutate of mutations) { const f = fixture('identity-drift'); mutateAliases(f, mutate); rejects(() => open(f)); }
  });
  group('failed histories cannot be edited, erased, in flight or replaced by success under an alias', () => {
    for (const mutate of [entry => entry.attempts[0].reserved_at = '2026-09-06T00:00:00.000Z',
      entry => entry.attempts[0].provider_finish_reason = 'MAX_TOKENS']) {
      const f = fixture('history-drift'); mutateCardinal(f, value => mutate(targetEntry(value)));
      rejects(() => open(f), 'FAILED_HISTORY_CHANGED');
    }
    const erased = fixture('erased-history'); mutateCardinal(erased, value => {
      targetEntry(value).attempts.pop(); value.requests_reserved--;
    }); rejects(() => open(erased), 'FAILED_HISTORY_CHANGED');
    const requesting = fixture('request-in-flight'); mutateCardinal(requesting, value => {
      const entry = targetEntry(value), last = entry.attempts.at(-1);
      entry.generation_status = last.status = 'REQUESTING'; last.failure_code = null; last.provider_finish_reason = null;
    }); rejects(() => open(requesting), 'FAILED_HISTORY_CHANGED');
    const succeeded = fixture('alias-over-success'); mutateCardinal(succeeded, value => {
      const index = value.prompts.findIndex(entry => entry.locale === 'es-es' && entry.value === 4);
      const original = value.prompts[index]; value.prompts[index] = success(succeeded.cardinalDirectory,
        original, syntheticMaster, syntheticTelephony, 2, [original.attempts[0]]);
    }); rejects(() => open(succeeded), 'FAILED_HISTORY_CHANGED');
  });
  group('supplemental manifest bytes pin language, status, request provenance and source metrics', () => {
    const mutations = [value => sourceEntry(value).language = 'French from France',
      value => sourceEntry(value).transcript = 'quatre', value => sourceEntry(value).generation_status = 'FAILED',
      value => sourceEntry(value).provider_finish_reason = 'OTHER', value => sourceEntry(value).request_body_sha256 = '0'.repeat(64),
      value => sourceEntry(value).raw_pcm_sha256 = '0'.repeat(64), value => sourceEntry(value).master.sha256 = '0'.repeat(64),
      value => value.prompts.push(clone(sourceEntry(value)))];
    for (const mutate of mutations) {
      const f = fixture('supplemental-drift'), value = JSON.parse(supplementalBytes); mutate(value);
      save(path.join(f.supplementalDirectory, 'manifest.json'), value);
      rejects(() => open(f), 'SUPPLEMENTAL_MANIFEST_CHANGED');
    }
  });
  group('source master bytes, regular-file identity and private file modes are required', () => {
    const file = 'es-es/acdc-number-4.master-24000.wav';
    const changed = fixture('master-tamper'), bytes = fs.readFileSync(path.join(changed.supplementalDirectory, file));
    bytes.writeInt16LE(1111, 1000); fs.writeFileSync(path.join(changed.supplementalDirectory, file), bytes);
    rejects(() => open(changed), 'SOURCE_MASTER_CHANGED');
    for (const mode of ['missing', 'symlink', 'hardlink', 'writable']) {
      const f = fixture(mode), target = path.join(f.supplementalDirectory, file), retainedFile = target + '.retained';
      if (mode === 'writable') fs.chmodSync(target, 0o666);
      else {
        fs.renameSync(target, retainedFile);
        if (mode === 'symlink') fs.symlinkSync(retainedFile, target);
        if (mode === 'hardlink') fs.linkSync(retainedFile, target);
      }
      rejects(() => open(f), mode === 'missing' ? 'ENOENT' : 'INVALID_REUSE_FILE');
    }
  });
  group('exact telephony verification rejects equal-duration wrong frequency and changed recipe', () => {
    const result = readOnly(() => resolver.resolve('es-es', 'acdc-cardinal-v1-number-4'));
    const metrics = pack.inspectWave(result.telephony, 8000), unrelated = tone(8000, metrics.sample_count, 900);
    equal(pack.inspectWave(unrelated, 8000).duration_seconds, metrics.duration_seconds);
    equal(hash(unrelated) === hash(result.telephony), false);
    rejects(() => readOnly(() => resolver.verifyTelephony('es-es', result.id, unrelated)), 'RESOLVED_TELEPHONY_MISMATCH');
    rejects(() => readOnly(() => resolver.verifyTelephony('es-es', result.id, Buffer.alloc(0))), 'INVALID_RESOLVED_WAVE');
    const f = fixture('generated-wrong-frequency'), entry = f.manifest.prompts[0];
    const wrongPhone = tone(8000, 2000, 900), file = entry.attempts[0].telephony.file;
    fs.writeFileSync(path.join(f.cardinalDirectory, file), wrongPhone);
    entry.attempts[0].telephony = {file, ...pack.technicalQa(pack.inspectWave(wrongPhone, 8000))};
    save(path.join(f.cardinalDirectory, 'manifest.json'), f.manifest);
    rejects(() => open(f), 'TELEPHONY_NOT_EXACT_MASTER_RESAMPLE');
    const recipe = fixture('cardinal-recipe-drift'); mutateCardinal(recipe, value => value.conversion.recipe_sha256 = '0'.repeat(64));
    rejects(() => open(recipe), 'INVALID_CONVERSION_PROVENANCE');
  });
  group('returned buffer and metadata mutation cannot change a later resolution', () => {
    for (const [locale, id] of [['es-es', 'acdc-cardinal-v1-number-4'], ['en-us', 'acdc-cardinal-v1-number-0']]) {
      const first = readOnly(() => resolver.resolve(locale, id));
      const masterPin = hash(first.master), phonePin = hash(first.telephony), proof = clone(first.provenance);
      first.master.fill(0); first.telephony.fill(0); first.provenance.master_sha256 = '0'.repeat(64);
      const next = readOnly(() => resolver.resolve(locale, id));
      equal(hash(next.master), masterPin); equal(hash(next.telephony), phonePin); equal(next.provenance, proof);
      rejects(() => readOnly(() => resolver.verifyTelephony(locale, id, first.telephony)), 'RESOLVED_TELEPHONY_MISMATCH');
    }
    const summary = readOnly(() => resolver.summary()); summary.generated = 584;
    equal(readOnly(() => resolver.summary()).generated, 1);
  });
  group('read-only operations retain inputs and detect manifest or audio drift after opening', () => {
    equal(treePins(base.root), initialFixturePins);
    for (const part of ['cardinal', 'supplemental', 'alias']) {
      const f = fixture('post-open-' + part), opened = open(f);
      const file = part === 'alias' ? f.aliasFile : path.join(part === 'cardinal' ? f.cardinalDirectory : f.supplementalDirectory, 'manifest.json');
      fs.appendFileSync(file, ' ');
      rejects(() => readOnly(() => opened.summary()), 'REUSE_INPUT_CHANGED');
      rejects(() => readOnly(() => opened.resolve('es-es', 'acdc-cardinal-v1-number-4')), 'REUSE_INPUT_CHANGED');
    }
    const f = fixture('post-open-generated-audio'), opened = open(f), entry = f.manifest.prompts[0];
    const file = path.join(f.cardinalDirectory, entry.attempts[0].telephony.file), bytes = fs.readFileSync(file);
    bytes.writeInt16LE(1111, 1000); fs.writeFileSync(file, bytes);
    rejects(() => readOnly(() => opened.resolve(entry.locale, entry.id)), 'GENERATED_AUDIO_CHANGED');
    equal(imports.every(name => allowedImports.has(name)), true);
    equal(pack.digest(failures), pack.digest(retained.prompts.filter(entry => entry.locale === 'es-es' && [4, 9].includes(entry.value))));
    equal(pins(), before);
  });
  terminal = 0;
} catch (error) {
  failure = {name: error.name, message: error.message}; console.error(error.stack);
} finally {
  Module._load = originalLoad; cp.spawnSync = originalSpawn;
  const after = pins(), stable = JSON.stringify(before) === JSON.stringify(after);
  const receipt = {schema_version: 1, fixture_only: true, groups, checks, source_hashes_before: before,
    source_hashes_after: after, source_stable: stable, retained_failure_entry_pins: failurePins,
    provider_calls: 0, imports, sox_calls: soxCalls, actual_sox_replay: soxCalls > 0,
    resampling_recipe_sha256: pack.digest(pack.RESAMPLING), runtime_ready: false,
    listening_verified: false, language_review_performed: false, native_acceptance: false,
    output_directory: output, ...(failure ? {failure} : {}), terminal_exit: stable ? terminal : 1};
  fs.writeFileSync(path.join(output, 'receipt.json'), JSON.stringify(receipt, null, 2) + '\n', {flag: 'wx', mode: 0o600});
  console.log(JSON.stringify(receipt)); process.exitCode = receipt.terminal_exit;
}
