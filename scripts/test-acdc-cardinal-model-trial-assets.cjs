#!/usr/bin/env node
'use strict';

// Offline only: original saved trial WAVs, copied receipts, synthetic complete
// catalog/source ledger containing the three real failed source entries. Retain
// fixtures/receipt. Root runs this under its serialized resource guard.
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const crypto = require('node:crypto'), assert = require('node:assert/strict');
const cp = require('node:child_process'), Module = require('node:module');
const pack = require('./acdc-cardinal-pack.cjs');
const fr89 = require('./acdc-cardinal-fr89-one-shot-policy.cjs');
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const clone = value => JSON.parse(JSON.stringify(value));
const trialRoot = path.join(__dirname, 'assets/acdc-gemini-cardinal-model-trials-20260907');
const sourceFile = path.join(__dirname, 'assets/acdc-gemini-cardinals-20260907/manifest.json');
const moduleFile = path.join(__dirname, 'acdc-cardinal-model-trial-assets.cjs');
const saved = Object.fromEntries(['format-rejected', 'format-compatible'].map(name =>
  [name, JSON.parse(fs.readFileSync(path.join(trialRoot, name, 'trial.json')))]));
const files = [__filename, moduleFile, sourceFile, require.resolve('./acdc-cardinal-pack.cjs'),
  require.resolve('./acdc-cardinal-fr89-one-shot-policy.cjs'),
  require.resolve('./acdc-cardinal-catalog.cjs'), '/usr/bin/sox',
  ...Object.keys(saved).map(name => path.join(trialRoot, name, 'trial.json')),
  ...saved['format-compatible'].entries.flatMap(e => ['master', 'telephony'].map(k => path.join(trialRoot, 'format-compatible', e[k].file)))];
const pins = () => Object.fromEntries(files.map(file => [file, hash(fs.readFileSync(file))]));
const before = pins(), root = fs.mkdtempSync(path.join(os.tmpdir(), 'acdc-cardinal-trial-assets-proof.'));
fs.chmodSync(root, 0o700);
const originalSource = JSON.parse(fs.readFileSync(sourceFile));
const groups = []; let checks = 0, sequence = 0, soxCalls = 0, verifier, terminal = 1, failure;
const equal = (a, b) => { checks++; assert.deepEqual(a, b); };
const rejects = (fn, code) => { checks++; assert.throws(fn, e => e instanceof Error && (!code || e.code === code)); };
const group = (name, fn) => { fn(); groups.push(name); console.log('PASS ' + name); };
function write(file, value) {
  fs.mkdirSync(path.dirname(file), {recursive: true, mode: 0o700});
  fs.writeFileSync(file, Buffer.isBuffer(value) ? value : JSON.stringify(value) + '\n', {mode: 0o600});
}
function fixture(includeFr = false) {
  const location = path.join(root, `fixture-${++sequence}`), sourceDirectory = path.join(location, 'source');
  const source = pack.createManifest(); source.approvals = clone(originalSource.approvals);
  source.approvals_sha256 = pack.digest(source.approvals);
  const identities = saved['format-compatible'].entries.map(e => e.identity);
  if (includeFr) identities.push(fr89.identity);
  source.prompts = source.prompts.map(e => identities.includes(`${e.locale}/${e.id}`)
    ? clone(originalSource.prompts.find(p => p.locale === e.locale && p.id === e.id)) : e);
  source.requests_reserved = source.prompts.reduce((n, e) => n + e.attempts.length, 0);
  source.retry_request_budget = source.prompts.reduce((n, e) => n + Math.max(0, e.attempts.length - 1), 0);
  source.retries_explicitly_enabled = source.retry_request_budget > 0; source.conversion.version = pack.RESAMPLING.version;
  write(path.join(sourceDirectory, 'manifest.json'), source);
  const sourceManifestSha256 = hash(fs.readFileSync(path.join(sourceDirectory, 'manifest.json'))), ledgers = [], trials = [];
  for (const [name, value] of Object.entries(saved)) {
    const directory = path.join(location, name), ledger = clone(value);
    Object.assign(ledger, {source_manifest_sha256: sourceManifestSha256,
      source_requests_reserved: source.requests_reserved, source_retry_budget: source.retry_request_budget});
    write(path.join(directory, 'trial.json'), ledger);
    for (const e of ledger.entries) for (const variant of ['master', 'telephony']) if (e[variant])
      write(path.join(directory, e[variant].file), fs.readFileSync(path.join(trialRoot, name, e[variant].file)));
    trials.push({directory, sha256: hash(fs.readFileSync(path.join(directory, 'trial.json')))}); ledgers.push(ledger);
  }
  return {location, source, ledgers, options: {sourceDirectory, sourceManifestSha256,
    approvalSha256: source.approvals_sha256, trials}};
}
function save(f, index = 1) {
  const item = f.options.trials[index]; write(path.join(item.directory, 'trial.json'), f.ledgers[index]);
  item.sha256 = hash(fs.readFileSync(path.join(item.directory, 'trial.json')));
}
function treePins(directory, prefix = '') {
  const out = {};
  for (const name of fs.readdirSync(path.join(directory, prefix)).sort()) {
    const relative = path.join(prefix, name), stat = fs.lstatSync(path.join(directory, relative));
    if (stat.isDirectory()) Object.assign(out, treePins(directory, relative));
    else if (stat.isFile()) out[relative] = hash(fs.readFileSync(path.join(directory, relative)));
  }
  return out;
}
function readOnly(fn) {
  const savedFs = new Map(), savedCp = new Map(), originalOpen = fs.openSync, originalFetch = globalThis.fetch;
  for (const key of ['writeFileSync', 'appendFileSync', 'writeSync', 'writevSync', 'mkdirSync', 'mkdtempSync',
    'renameSync', 'copyFileSync', 'cpSync', 'unlinkSync', 'rmSync', 'rmdirSync', 'chmodSync', 'fchmodSync',
    'chownSync', 'fchownSync', 'truncateSync', 'ftruncateSync', 'utimesSync', 'futimesSync', 'linkSync',
    'symlinkSync', 'createWriteStream']) {
    savedFs.set(key, fs[key]); fs[key] = () => assert.fail('Verifier filesystem mutation forbidden');
  }
  for (const key of ['spawn', 'exec', 'execSync', 'execFile', 'execFileSync', 'fork']) {
    savedCp.set(key, cp[key]); cp[key] = () => assert.fail('Unexpected verifier subprocess');
  }
  globalThis.fetch = () => assert.fail('Verifier network forbidden');
  fs.openSync = (file, flags, ...args) => {
    assert(flags === 'r' || typeof flags === 'number' && !(flags & (fs.constants.O_WRONLY | fs.constants.O_RDWR
      | fs.constants.O_CREAT | fs.constants.O_TRUNC | fs.constants.O_APPEND)));
    return originalOpen(file, flags, ...args);
  };
  try { return fn(); } finally {
    fs.openSync = originalOpen; globalThis.fetch = originalFetch;
    for (const [k, v] of savedFs) fs[k] = v;
    for (const [k, v] of savedCp) cp[k] = v;
  }
}
const open = f => readOnly(() => (f.verifier || verifier).openResolution(f.options));
function oneShotFixture() {
  // Synthetic FR receipt uses saved PCM solely to test technical admission.
  // This is NOT an authored/spoken French recording or a listening approval.
  const f=fixture(true),original=f.source.prompts.find(e=>`${e.locale}/${e.id}`===fr89.identity);
  const policy={...fr89,source_manifest_sha256:f.options.sourceManifestSha256};
  const ledger=clone(f.ledgers[1]), entry=clone(ledger.entries[0]);
  const body=pack.requestBody(original,pack.CONCISE_SYNTHESIS_RECIPE);
  Object.assign(entry,{identity:fr89.identity,locale:original.locale,id:original.id,transcript:original.transcript,
    transcript_sha256:original.transcript_sha256,source_entry_sha256:pack.digest(original),
    source_attempts_sha256:pack.digest(original.attempts),source_attempt_count:6,source_attempt_count_plus_this_trial:7,
    synthesis_instruction:body.contents[0].parts[0].text,request_body_sha256:hash(JSON.stringify(body))});
  const directory=path.join(f.location,'fr89-one-shot');
  for(const variant of ['master','telephony']) {
    const bytes=fs.readFileSync(path.join(f.options.trials[1].directory,entry[variant].file));
    entry[variant].file=`01-${entry.locale}-${entry.id}.${variant==='master'?'master-24000':'telephony-8000'}.wav`;
    write(path.join(directory,entry[variant].file),bytes);
  }
  Object.assign(ledger,{entries:[entry],request_limit:1,requests_reserved:1,one_shot_diagnostic:policy});
  write(path.join(directory,'trial.json'),ledger);
  f.ledgers=[ledger];f.options.trials=[{directory,sha256:hash(fs.readFileSync(path.join(directory,'trial.json')))}];
  const previousLoad=Module._load,isolated=new Module(moduleFile,module);
  isolated.filename=moduleFile;isolated.paths=module.paths;
  try {
    Module._load=function(request,parent,...rest) {
      if(parent===isolated && request==='./acdc-cardinal-fr89-one-shot-policy.cjs')return Object.freeze({...policy});
      return previousLoad.call(this,request,parent,...rest);
    };
    isolated._compile(fs.readFileSync(moduleFile,'utf8'),moduleFile);f.verifier=isolated.exports;
  } finally {Module._load=previousLoad;}
  f.policy=policy;return f;
}
const originalSpawn = cp.spawnSync, originalLoad = Module._load;
cp.spawnSync = (command, argv, options) => {
  equal(command, '/usr/bin/sox'); equal(options.shell, false);
  equal(options.env, {PATH: '/usr/bin:/bin', LC_ALL: 'C', TZ: 'UTC'});
  equal(argv, argv.length === 1 ? ['--version'] : [...pack.RESAMPLING.argv]);
  soxCalls++; return originalSpawn(command, argv, options);
};
try {
  Module._load = function(request, parent, isMain) {
    if (parent?.filename === moduleFile) assert(['node:fs', 'node:path', 'node:crypto', './acdc-cardinal-pack.cjs',
      './acdc-cardinal-fr89-one-shot-policy.cjs'].includes(request));
    return originalLoad.call(this, request, parent, isMain);
  };
  verifier = readOnly(() => require('./acdc-cardinal-model-trial-assets.cjs'));
  const base = fixture(), resolver = open(base), originalTree = treePins(base.location);
  group('three real saved QA candidates and first rejected request remain distinct from original history', () => {
    const summary = readOnly(() => resolver.summary());
    equal(summary.successful_identities, saved['format-compatible'].entries.map(e => e.identity).sort());
    equal(summary.source_requests_reserved, 4); equal(summary.additional_trial_requests, 4);
    equal(summary.trials[0].outcomes.map(e => [e.status, e.additional_trial_requests]), [['FAILED', 1], ['SELECTED', 0], ['SELECTED', 0]]);
    equal(summary.trials[1].outcomes.map(e => e.source_attempt_count), [2, 1, 1]);
    for (const key of ['runtime_ready', 'importable', 'deployed', 'native_listening_approved', 'source_history_reset', 'provider_provenance_authenticated']) equal(summary[key], false);
    for (const entry of saved['format-compatible'].entries) {
      const candidate = readOnly(() => resolver.resolve(entry.locale, entry.id));
      equal(candidate.master, fs.readFileSync(path.join(trialRoot, 'format-compatible', entry.master.file)));
      equal(candidate.telephony, fs.readFileSync(path.join(trialRoot, 'format-compatible', entry.telephony.file)));
      equal(candidate.provenance.model, 'gemini-3.1-flash-tts-preview'); equal(candidate.provenance.voice, 'Sulafat');
      equal(candidate.provenance.source_entry_sha256, entry.source_entry_sha256);
      equal(candidate.provenance.source_attempts_sha256, entry.source_attempts_sha256);
      equal(candidate.provenance.request_body_sha256, entry.request_body_sha256);
      equal(candidate.provenance.telephony_sha256, hash(candidate.telephony));
      equal(candidate.listening_verified, false); equal(candidate.runtime_ready, false);
      candidate.telephony[50] ^= 1; candidate.provenance.voice = 'changed';
      equal(readOnly(() => resolver.resolve(entry.locale, entry.id)).provenance.voice, 'Sulafat');
      equal(hash(readOnly(() => resolver.resolve(entry.locale, entry.id)).telephony), entry.telephony.sha256);
    }
    const copy = readOnly(() => resolver.sourceManifest()); copy.prompts.length = 0;
    equal(readOnly(() => resolver.sourceManifest()).prompts.length, 584);
    rejects(() => readOnly(() => resolver.resolve('fr-fr', 'acdc-cardinal-v1-terminal-4')), 'TRIAL_AUDIO_UNRESOLVED');
    rejects(() => readOnly(() => resolver.resolve({toString: () => 'he-il'}, 'acdc-cardinal-v1-tens-30')), 'UNKNOWN_TRIAL_IDENTITY');
    equal(treePins(base.location), originalTree);
  });
  group('independent source/approval/trial pins, exact options and finite allowlist are mandatory', () => {
    for (const key of ['sourceManifestSha256', 'approvalSha256']) {
      const f = fixture(); f.options[key] = '0'.repeat(64); rejects(() => open(f));
    }
    for (const mutate of [o => o.trials[1].sha256 = '0'.repeat(64), o => o.trials = [],
      o => o.trials.push(clone(o.trials[0])), o => o.trials = Array(65).fill(o.trials[0]),
      o => o.extra = true, o => o.trials[0].extra = true, o => o.trials[0].sha256 = null]) {
      const f = fixture(); mutate(f.options); rejects(() => open(f));
    }
  });
  group('source, request, model, identity, counts and readiness mutations fail even with repinned trial bytes', () => {
    const mutations = [l => l.extra = true, l => l.owner = 'other', l => l.model = pack.MODEL,
      l => l.voice = 'Kore', l => l.endpoint += '?key=forbidden', l => l.catalog_sha256 = '0'.repeat(64),
      l => l.source_manifest_sha256 = '0'.repeat(64), l => l.approvals_sha256 = '0'.repeat(64),
      l => l.source_requests_reserved++, l => l.requests_reserved--, l => l.request_limit--,
      l => l.entries.pop(), l => l.entries[1] = clone(l.entries[0]),
      ...['runtime_ready', 'importable', 'deployed', 'native_listening_approved', 'source_history_reset'].map(k => l => l[k] = true),
      ...['identity', 'id', 'locale', 'transcript', 'transcript_sha256', 'source_entry_sha256', 'source_attempts_sha256',
        'synthesis_recipe', 'synthesis_instruction', 'request_body_sha256', 'returned_model_version'].map(k => l => l.entries[0][k] = 'changed'),
      l => l.entries[0].source_attempt_count++, l => l.entries[0].source_attempt_count_plus_this_trial++,
      l => l.entries[0].extra = true, l => l.entries[0].reserved_at = false];
    for (const mutate of mutations) { const f = fixture(); mutate(f.ledgers[1]); save(f); rejects(() => open(f)); }
  });
  group('successful candidates require exact STOP, one audio-only part and accepted mono24k MIME', () => {
    for (const mutate of [e => delete e.audio_mime_diagnostics, e => e.audio_mime_diagnostics = null,
      e => e.audio_mime_diagnostics.channels = '2', e => e.audio_mime_diagnostics.rate = '16000',
      e => e.audio_mime_diagnostics.codec = 'UNKNOWN', e => e.audio_mime_diagnostics.accepted = false,
      e => e.audio_mime_diagnostics.extra = true, e => e.audio_mime_diagnostics.unknown_parameters = true,
      e => e.response_diagnostics.finish_reason = 'OTHER', e => e.response_diagnostics.text_parts = 1,
      e => e.response_diagnostics.candidate_count = 2, e => e.response_diagnostics.inline_audio_parts = 2,
      e => e.response_diagnostics.prompt_block_reason = 'SAFETY', e => e.failure_code = 'LOCAL_OPERATION_FAILED']) {
      const f = fixture(); mutate(f.ledgers[1].entries[0]); save(f); rejects(() => open(f));
    }
    const compatible = fixture();
    Object.assign(compatible.ledgers[1].entries[0].audio_mime_diagnostics, {channels: null, codec: 'pcm'});
    save(compatible); equal(readOnly(() => open(compatible).summary()).successful_identities.length, 3);
  });
  group('inflight and conflicting outcomes reject; failed-only receipts cannot resolve audio', () => {
    const failed = fixture(); failed.options.trials.pop();
    const failureOnly = open(failed); equal(readOnly(() => failureOnly.summary()).successful_identities, []);
    rejects(() => readOnly(() => failureOnly.resolve('he-il', 'acdc-cardinal-v1-tens-30')), 'TRIAL_AUDIO_UNRESOLVED');
    for (const mutate of [l => l.status = 'IN_PROGRESS', l => l.entries[0].status = 'REQUESTING',
      l => l.entries[1].status = 'QA_PASSED', l => l.entries[1].reserved_at = l.created_at]) {
      const f = fixture(); mutate(f.ledgers[0]); save(f, 0); rejects(() => open(f));
    }
    const duplicate = fixture(), directory = path.join(duplicate.location, 'duplicate');
    fs.cpSync(duplicate.options.trials[1].directory, directory, {recursive: true});
    const ledger = clone(duplicate.ledgers[1]); ledger.created_at = '2026-09-07T18:38:20.000Z';
    write(path.join(directory, 'trial.json'), ledger);
    duplicate.options.trials.push({directory, sha256: hash(fs.readFileSync(path.join(directory, 'trial.json')))});
    rejects(() => open(duplicate), 'DUPLICATE_TRIAL_SUCCESS');
    const conflicting = fixture(); conflicting.ledgers[0].created_at = '2026-09-08T00:00:00.000Z';
    conflicting.ledgers[0].entries[0].reserved_at = conflicting.ledgers[0].created_at; save(conflicting, 0);
    rejects(() => open(conflicting), 'CONFLICTING_TRIAL_OUTCOMES');
    const partial = fixture(); partial.options.trials.pop();
    partial.ledgers[0].entries[0].raw_pcm_sha256 = '1'.repeat(64); save(partial, 0);
    equal(readOnly(() => open(partial).summary()).additional_trial_requests, 1);
  });
  group('audio bytes, metrics and deterministic resampling must agree, including original raw PCM', () => {
    for (const mutate of [e => e.master.file = '../outside.wav', e => e.master.sha256 = '0'.repeat(64),
      e => e.master.extra = true, e => e.telephony.sample_rate_hz = 24000,
      e => e.raw_pcm_sha256 = '0'.repeat(64), e => e.telephony = null]) {
      const f = fixture(); mutate(f.ledgers[1].entries[0]); save(f); rejects(() => open(f));
    }
    const f = fixture(), e = f.ledgers[1].entries[0], other = f.ledgers[1].entries[1];
    const bytes = fs.readFileSync(path.join(f.options.trials[1].directory, other.telephony.file));
    write(path.join(f.options.trials[1].directory, e.telephony.file), bytes);
    e.telephony = {file: e.telephony.file, ...pack.technicalQa(pack.inspectWave(bytes, 8000))}; save(f);
    rejects(() => open(f), 'TRIAL_AUDIO_RESAMPLING_CHANGED');
  });
  group('symlink, hardlink, writable, traversal and post-open changes fail without writes', () => {
    for (const kind of ['symlink', 'hardlink', 'writable', 'directory', 'traversal']) {
      const f = fixture(), item = f.options.trials[1], file = path.join(item.directory, 'trial.json');
      if (kind === 'symlink' || kind === 'hardlink') {
        fs.renameSync(file, file + '.retained'); fs[kind === 'symlink' ? 'symlinkSync' : 'linkSync'](file + '.retained', file);
      }
      if (kind === 'writable') fs.chmodSync(file, 0o666);
      if (kind === 'directory') { fs.symlinkSync(item.directory, item.directory + '-alias'); item.directory += '-alias'; }
      if (kind === 'traversal') item.directory += '/../format-compatible';
      rejects(() => open(f));
    }
    for (const kind of ['source', 'ledger', 'master', 'lock']) {
      const f = fixture(), opened = open(f);
      const file = kind === 'source' ? path.join(f.options.sourceDirectory, 'manifest.json')
        : kind === 'lock' ? path.join(f.options.sourceDirectory, '.generation.lock')
          : path.join(f.options.trials[1].directory, kind === 'ledger' ? 'trial.json' : f.ledgers[1].entries[0].master.file);
      fs.appendFileSync(file, ' ');
      rejects(() => readOnly(() => opened.summary())); rejects(() => readOnly(() => opened.sourceManifest()));
      rejects(() => readOnly(() => opened.assertUnchanged()));
      rejects(() => readOnly(() => opened.resolve('he-il', 'acdc-cardinal-v1-tens-30')));
    }
    equal(treePins(base.location), originalTree); equal(pins(), before);
  });
  group('FR89 one-shot exact marker preserves six old failures and the distinct seventh request',()=>{
    const original=originalSource.prompts.find(e=>`${e.locale}/${e.id}`===fr89.identity);
    equal(hash(fs.readFileSync(sourceFile)),fr89.source_manifest_sha256);
    equal(pack.digest(original),fr89.source_entry_sha256);equal(pack.digest(original.attempts),fr89.source_attempts_sha256);
    equal(original.attempts.length,6);equal(original.attempts.every(a=>a.status==='FAILED'),true);
    const f=oneShotFixture(),tree=treePins(f.location),opened=open(f);
    const summary=readOnly(()=>opened.summary()),candidate=readOnly(()=>opened.resolve('fr-fr','acdc-cardinal-v1-terminal-89'));
    equal(summary.successful_identities,[fr89.identity]);equal(summary.additional_trial_requests,1);
    equal(summary.trials[0].one_shot_diagnostic,f.policy);equal(summary.trials[0].outcomes[0].source_attempt_count,6);
    equal(candidate.provenance.one_shot_diagnostic,f.policy);equal(candidate.provenance.source_attempt_count,6);
    equal(candidate.provenance.source_attempts_sha256,fr89.source_attempts_sha256);
    equal(candidate.native_listening_approved,false);equal(candidate.runtime_ready,false);
    equal(readOnly(()=>opened.sourceManifest()).prompts.find(e=>`${e.locale}/${e.id}`===fr89.identity),original);
    equal(treePins(f.location),tree);
    // The real policy cannot admit a fixture's repinned synthetic source.
    rejects(()=>readOnly(()=>verifier.openResolution(f.options)),'ONE_SHOT_POLICY_CHANGED');
  });
  group('FR89 exception rejects unmarked, altered, broad, pending and repeated one-shot receipts',()=>{
    for(const mutate of [l=>delete l.one_shot_diagnostic,l=>l.one_shot_diagnostic=null,
      l=>l.one_shot_diagnostic.extra=true,
      ...Object.keys(fr89).map(k=>l=>l.one_shot_diagnostic[k]='changed'),
      l=>l.entries.push(clone(l.entries[0])),l=>l.request_limit=2,l=>l.requests_reserved=0,
      l=>l.entries[0].source_attempt_count=5,l=>l.entries[0].source_attempt_count=7,
      l=>l.entries[0].source_attempt_count_plus_this_trial=6,
      l=>l.entries[0].identity='fr-fr/acdc-cardinal-v1-terminal-88',
      l=>l.entries[0].status='SELECTED',l=>l.entries[0].status='REQUESTING',l=>l.status='IN_PROGRESS']) {
      const f=oneShotFixture();mutate(f.ledgers[0]);save(f,0);rejects(()=>open(f));
    }
    const markedNormal=fixture();markedNormal.ledgers[1].one_shot_diagnostic=clone(fr89);save(markedNormal);
    rejects(()=>open(markedNormal));
    function failReceipt(f) {
      const ledger=f.ledgers[0],entry=ledger.entries[0];ledger.status='STOPPED_ON_FAILURE';
      Object.assign(entry,{status:'FAILED',failure_code:'GEMINI_REQUEST_TIMED_OUT',returned_model_version:null,
        response_diagnostics:null,audio_mime_diagnostics:null,raw_pcm_sha256:null,master:null,telephony:null});save(f,0);
    }
    const failed=oneShotFixture();failReceipt(failed);
    const failedResolver=open(failed);equal(readOnly(()=>failedResolver.summary()).successful_identities,[]);
    equal(readOnly(()=>failedResolver.summary()).additional_trial_requests,1);
    rejects(()=>readOnly(()=>failedResolver.resolve('fr-fr','acdc-cardinal-v1-terminal-89')),'TRIAL_AUDIO_UNRESOLVED');
    for(const outcome of ['FAILED','QA_PASSED']) {
      const f=oneShotFixture();if(outcome==='FAILED')failReceipt(f);
      const directory=path.join(f.location,'repeated-fr89'),ledger=clone(f.ledgers[0]);
      ledger.created_at='2026-09-08T00:00:00.000Z';ledger.entries[0].reserved_at=ledger.created_at;
      write(path.join(directory,'trial.json'),ledger);
      f.options.trials.push({directory,sha256:hash(fs.readFileSync(path.join(directory,'trial.json')))});
      rejects(()=>open(f),'DUPLICATE_ONE_SHOT_RESERVATION');
    }
    equal(pins(),before);equal(pack.HARD_MAX_ATTEMPTS,6);
  });
  terminal = 0;
} catch (error) {
  failure = {name: error.name, code: error.code || 'FIXTURE_ASSERTION_FAILED'};
  console.error(error.stack); // Local fixture source only, never provider exceptions.
} finally {
  Module._load = originalLoad; cp.spawnSync = originalSpawn;
  const after = pins(), stable = JSON.stringify(before) === JSON.stringify(after);
  const receipt = {schema_version: 1, fixture_only: true, groups, checks, sox_calls: soxCalls,
    source_hashes_before: before, source_hashes_after: after, source_stable: stable,
    provider_calls: 0, runtime_ready: false, listening_verified: false, output_directory: root,
    ...(failure ? {failure} : {}), terminal_exit: stable ? terminal : 1};
  fs.writeFileSync(path.join(root, 'receipt.json'), JSON.stringify(receipt, null, 2) + '\n', {flag: 'wx', mode: 0o600});
  console.log(JSON.stringify(receipt)); process.exitCode = receipt.terminal_exit;
}
