#!/usr/bin/env node
'use strict';
// Offline contract fixtures only. No SUP, DB, provider or service subprocess.
const test = require('node:test'), assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const probe = require('./probe-acdc-prerecorded-runtime.cjs');
const publisher = require('./publish-acdc-prerecorded-capabilities.cjs');
const {legacyLanguageCapabilities} = require('./validate-acdc-language-capabilities.cjs');
const clone = x => JSON.parse(JSON.stringify(x));
const H = n => String(n).repeat(64), NOW = Date.parse('2026-09-07T12:00:00.000Z');
const ACCOUNT = '302ae5a70c403124f764cbc54229cfcd'; // Fixture, never production admission policy.
function fixture() {
  const input = {node: 'kazoo_apps@isolated.invalid', account: ACCOUNT,
    beam_manifest_sha256: H(1), cardinal_receipt_sha256: H(2), fixed_receipt_sha256: H(3),
    beams: probe.MODULES.map(module => ({module, path: '/explicit-fixture/' + module + '.beam', sha256: H(4)})),
    documents: [{synthetic_fixture_only: true}],
    locales: Object.entries(probe.COUNTS).map(([locale, count]) => ({locale, count,
      cardinal_map_sha256: probe.sha(locale), fixed_map_sha256: H(5), source_catalog_sha256: H(6)}))};
  return probe.makeReceipt(input, H(7), new Date(NOW - 1000).toISOString(), new Date(NOW).toISOString(), H(8));
}
test('exact measured receipt produces selectable v2, never full/native/SIP ready', () => {
  const r = fixture(), c = publisher.capability(r, H(9), NOW);
  assert.equal(c.schema_version, 2);
  assert.deepEqual(Object.keys(c.languages).sort(), Object.keys(probe.COUNTS).sort());
  for (const [locale, l] of Object.entries(c.languages)) {
    assert.equal(l.numeric_prompt_count, probe.COUNTS[locale]); assert.equal(l.callback_prompt_count, 42);
    for (const k of ['selection_ready', 'position', 'wait_time', 'callback', 'position_installed_verified',
      'callback_installed_verified', 'position_runtime_verified', 'callback_runtime_verified', 'wait_time_runtime_verified']) assert.equal(l[k], true);
    assert.equal(l.ready, false); assert.equal(l.native_speaker_review, false); assert.equal(l.native_review_sha256, null);
    assert.equal(l.runtime_evidence_sha256, H(9)); assert.equal(l.numbers, 'prerecorded-cardinal');
  }
  assert.equal(r.live_SIP_verified, false); assert.equal(r.full_language_ready, false);
});
test('fail closed on every missing/extra evidence field and unsafe readiness claim', () => {
  const r = fixture();
  for (const key of Object.keys(r)) { const bad = clone(r); delete bad[key]; assert.throws(() => publisher.validateReceipt(bad, NOW), key); }
  assert.throws(() => publisher.validateReceipt({...r, invented_evidence: true}, NOW));
  for (const key of ['live_SIP_verified', 'native_listening_approved', 'full_language_ready', 'database_writes',
    'queue_configuration_changed', 'service_restarts']) {
    assert.throws(() => publisher.validateReceipt({...r, [key]: true}, NOW), key);
    assert.throws(() => publisher.validateReceipt({...r, [key]: 0}, NOW), key);
  }
  for (const key of ['documents_verified', 'mappings_verified', 'position_playlist_cases', 'callback_prepare_cases', 'wait_playlist_cases'])
    assert.throws(() => publisher.validateReceipt({...r, [key]: r[key] - 1}, NOW), key);
  for (const patch of [{runtime_function_testable: false}, {provider_requests: 1}, {account: 'G'.repeat(32)},
    {node: 'node@host;bad'}, {installed_media_sha256: H(0)}, {number_cases: [1]}, {wait_cases: [0]}])
    assert.throws(() => publisher.validateReceipt({...r, ...patch}, NOW));
});
test('locale/model build evidence cannot be duplicated, incomplete or stale', () => {
  const r = fixture();
  for (const change of [x => x.locales.pop(), x => {x.locales[1] = clone(x.locales[0]);},
    x => x.beams.pop(), x => {x.beams[1] = clone(x.beams[0]);},
    x => {x.beams[0].path = '/wrong.beam';}, x => {x.beams[0].sha256 = 'not-a-hash';}]) {
    const bad = clone(r); change(bad); assert.throws(() => publisher.validateReceipt(bad, NOW));
  }
  for (const key of Object.keys(r.locales[0])) {
    const bad = clone(r); delete bad.locales[0][key]; assert.throws(() => publisher.validateReceipt(bad, NOW), key);
  }
  for (const patch of [{count: 2999}, {callback_count: 41}, {wait_count: 9}, {position_runtime_verified: false},
    {callback_runtime_verified: false}, {wait_time_runtime_verified: false}, {fixed_map_sha256: H(0)}, {extra: true}]) {
    const bad = clone(r); Object.assign(bad.locales[0], patch); assert.throws(() => publisher.validateReceipt(bad, NOW));
  }
  publisher.validateReceipt(r, NOW + 300000);
  assert.throws(() => publisher.validateReceipt(r, NOW + 300001));
  assert.throws(() => publisher.validateReceipt(r, NOW - 1));
  assert.throws(() => publisher.validateReceipt({...r, started_at: new Date(NOW + 1).toISOString()}, NOW));
  assert.throws(() => publisher.validateReceipt({...r, started_at: new Date(NOW - 300001).toISOString()}, NOW));
  assert.throws(() => publisher.validateReceipt({...r, started_at: [r.started_at]}, NOW));
  assert.throws(() => publisher.validateReceipt({...r, finished_at: NOW}, NOW));
});
test('small sidecar render is exact; unconfirmed RPC output never becomes evidence', () => {
  const template = fs.readFileSync(path.join(__dirname, 'probe-acdc-prerecorded-runtime.erl.template'), 'utf8');
  const code = probe.render(template, '/tmp/protected-fixture/input.json', H(1), 'kazoo_apps@isolated.invalid');
  assert(!code.includes('@@')); assert(Buffer.byteLength(code) < 32768);
  assert.throws(() => probe.render(template, '/tmp/inject".json', H(1), 'kazoo_apps@isolated.invalid'));
  assert.throws(() => probe.render(template + '@@SIDECAR@@', '/tmp/a.json', H(1), 'kazoo_apps@isolated.invalid'));
  const ok = `{ok,{ok,{prerecorded_runtime_verified,<<"${H(1)}">>,796,1592,5,95,10,80,no_database_writes,no_calls,no_native_review}}}`;
  probe.validateResult(ok, H(1));
  for (const bad of ['', 'timeout', ok.replace('1592', '1591'), ok.replace(H(1), H(2)),
    ok.replace('no_calls', 'calls'), ok + 'junk', ok + ok]) assert.throws(() => probe.validateResult(bad, H(1)));
  // These guards are supplementary source contracts, not an Erlang execution claim.
  assert(code.includes('ets:lookup(M, Key)')); assert(code.includes('beam_lib:md5(Bytes)'));
  assert(code.includes('file:pread(Fd, 0, Size + 1)'));
  assert(code.includes('Size = ValidStat(BeforeInfo)'));
  assert(code.includes('StatIdentity(OpenInfo) =:= StatIdentity(FinalInfo)'));
  assert(code.includes('BoundedRead(Path, 8388608, beam'));
  assert(!code.includes('file:read_file('));
  assert(code.includes('acdc_wait_time_media:prepare')); assert(code.includes('acdc_cardinal_media:playlist'));
  assert(!/\b(?:start_link|save_doc|add_mapping|publish_command|flush)\s*\(/.test(code));
  assert(!/kapps_config:get[A-Za-z_]*\s*\(/.test(code)); assert(!code.includes('prompt_path('));
});
test('publication CLI requires exact prior-state pin and cannot target its evidence', () => {
  const a = ['--account', ACCOUNT, '--receipt', '/root/fixture/probe.json', '--receipt-sha256', H(1), '--output', '/root/fixture/capability.json', '--previous-sha256', 'absent'];
  assert.equal(publisher.parseArgs(a)['previous-sha256'], 'absent');
  assert.throws(() => publisher.parseArgs(a.slice(0, -2)));
  assert.throws(() => publisher.parseArgs([...a, '--output', '/other']));
  assert.throws(() => publisher.parseArgs(a.map(x => x === '/root/fixture/capability.json' ? '/root/fixture/probe.json' : x)));
  assert.throws(() => publisher.parseArgs(a.map(x => x === 'absent' ? 'unverified' : x)));
  assert.throws(() => publisher.parseArgs(a.slice(2)));
  for (const account of ['', 'a'.repeat(31), 'a'.repeat(33), 'A'.repeat(32), ACCOUNT + '\n', ' ' + ACCOUNT, 123, null]) {
    assert.equal(probe.validAccount(account), false);
    assert.throws(() => publisher.validateReceipt({...fixture(), account}, NOW));
  }
  assert.equal(publisher.parseArgs(a.map(x => x === ACCOUNT ? 'a'.repeat(32) : x)).account, 'a'.repeat(32));
  publisher.validateReceipt({...fixture(), account: 'a'.repeat(32)}, NOW);
});
test('probe requires explicit syntactically exact account without a tenant allowlist', () => {
  const options = {node: 'kazoo_apps@isolated.invalid', account: ACCOUNT,
    'cardinal-receipt': '/fixture/cardinal.json', 'cardinal-receipt-sha256': H(1),
    'fixed-receipt': '/fixture/fixed.json', 'fixed-receipt-sha256': H(2),
    'beam-manifest': '/fixture/beams.json', 'beam-manifest-sha256': H(3),
    'fixed-pack': '/fixture/fixed', 'completion-pack': '/fixture/completion',
    'fixed-map': '/fixture/map.hrl', 'fixed-map-sha256': H(4), output: '/fixture/output.json'};
  const args = o => Object.entries(o).flatMap(([k, v]) => ['--' + k, v]);
  assert.equal(probe.parseArgs(args(options)).account, ACCOUNT);
  assert.equal(probe.parseArgs(args({...options, account: 'b'.repeat(32)})).account, 'b'.repeat(32));
  for (const account of ['', 'A'.repeat(32), 'a'.repeat(31), ACCOUNT + '\n', ' ' + ACCOUNT])
    assert.throws(() => probe.parseArgs(args({...options, account})));
  const missing = {...options}; delete missing.account; assert.throws(() => probe.parseArgs(args(missing)));
});
test('protected local evidence is pinned/create-only and refuses aliases or writable parents', () => {
  assert.equal(process.getuid(), 0, 'Protected filesystem fixture requires root');
  const base = fs.mkdtempSync('/root/acdc-runtime-proof-test-'), payload = Buffer.from('fixture-only\n');
  try {
    const target = path.join(base, 'proof.json');
    assert.equal(probe.createEvidence(target, payload), probe.sha(payload));
    assert.deepEqual(probe.readPinned(target, probe.sha(payload)), payload);
    assert.throws(() => probe.createEvidence(target, Buffer.from('overwrite')));
    assert.throws(() => probe.readPinned(target, H(1)));
    fs.symlinkSync(target, path.join(base, 'alias.json'));
    assert.throws(() => probe.readPinned(path.join(base, 'alias.json'), probe.sha(payload)));
    fs.linkSync(target, path.join(base, 'hardlink.json'));
    assert.throws(() => probe.readPinned(target, probe.sha(payload)));
    fs.unlinkSync(path.join(base, 'hardlink.json'));
    fs.chmodSync(target, 0o666); assert.throws(() => probe.readPinned(target, probe.sha(payload)));
    fs.chmodSync(target, 0o600); fs.chmodSync(base, 0o777);
    assert.throws(() => probe.readPinned(target, probe.sha(payload))); fs.chmodSync(base, 0o700);
  } finally {
    fs.chmodSync(base, 0o700);
    for (const name of fs.readdirSync(base)) fs.unlinkSync(path.join(base, name)); fs.rmdirSync(base);
  }
});
test('atomic publisher refuses stale prior state, preserves backup, never edits receipt', () => {
  const base = fs.mkdtempSync('/root/acdc-runtime-publisher-test-');
  try {
    const r = fixture(), now = Date.now();
    r.started_at = new Date(now - 1).toISOString(); r.finished_at = new Date(now).toISOString();
    for (const m of r.beams) {
      m.path = path.join(base, m.module + '.beam');
      const bytes = Buffer.from('EXPLICIT SYNTHETIC OFFLINE BEAM FIXTURE ' + m.module);
      fs.writeFileSync(m.path, bytes, {mode: 0o600}); m.sha256 = probe.sha(bytes);
    }
    const receipt = path.join(base, 'probe.json'), raw = Buffer.from(JSON.stringify(r));
    probe.createEvidence(receipt, raw);
    const output = path.join(base, 'capability.json'), prior = Buffer.from(JSON.stringify(legacyLanguageCapabilities()));
    probe.createEvidence(output, prior);
    const options = {account: ACCOUNT, receipt, 'receipt-sha256': probe.sha(raw), output, 'previous-sha256': H(0)};
    assert.throws(() => publisher.publish(options)); assert.deepEqual(fs.readFileSync(output), prior);
    assert.throws(() => publisher.publish({...options, account: 'a'.repeat(32)}));
    assert.deepEqual(fs.readFileSync(output), prior);
    options['previous-sha256'] = probe.sha(prior);
    const result = publisher.publish(options);
    assert.equal(result.selection_ready, true); assert.equal(result.full_language_ready, false);
    assert.deepEqual(fs.readFileSync(output + '.before-' + probe.sha(prior)), prior);
    assert.deepEqual(fs.readFileSync(receipt), raw);
    assert.throws(() => publisher.publish(options));
    const capability = JSON.parse(fs.readFileSync(output));
    assert(Object.values(capability.languages).every(l => l.selection_ready && !l.ready));
  } finally {
    for (const name of fs.readdirSync(base)) fs.unlinkSync(path.join(base, name)); fs.rmdirSync(base);
  }
});
test('actual buildInput uses exported dependencies and real fixed receipt/document adapter', () => {
  const installer = require('./install-acdc-cardinal-pack.cjs');
  const cardinal = require('./refresh-acdc-cardinal-mappings.cjs');
  const fixed = require('./refresh-acdc-gemini-mappings.cjs');
  const importer = require('./import-acdc-gemini-voices.cjs');
  const actualFixedDocuments = fixed.expectedDocuments;
  const originals = {releasePlans: installer.releasePlans, cardinalDocuments: cardinal.expectedDocuments,
    loadPlan: importer.loadPlan};
  const directory = fs.mkdtempSync('/root/acdc-runtime-build-input-test-');
  // Source/WAV-loader doubles are explicit here. The actual fixed210 header,
  // fixed expectedDocuments, importer.document, receipt validator, protected
  // reads and production buildInput body are NOT replaced.
  try {
    const text = fs.readFileSync(path.join(__dirname, '../applications/acdc/src/acdc_gemini_map.hrl'), 'utf8');
    const rows = probe.fixedMapRows(text);
    assert.equal(rows.length, 210);
    const plan = rows.map(r => ({locale: r[0], canonical_id: r[1], prompt_id: r[2], id: r[0] + '/' + r[2],
      attachment: r[2] + '.wav', sha256: r[3], md5: r[4], bytes: Buffer.alloc(r[5]),
      transcript_sha256: r[6], source_file: 'EXPLICIT-SYNTHETIC-FIXTURE-NOT-AUDIO'}));
    const receipt = {schema_version: 1, owner: importer.OWNER, created: 0, preserved: 210, verified: 210,
      queue_configuration_changed: false, runtime_ready: false, full_position_language_ready: false,
      prompts: plan.map(p => ({locale: p.locale, canonical_id: p.canonical_id, prompt_id: p.prompt_id,
        document_id: p.id, attachment: p.attachment, sha256: p.sha256, revision: '2-' + 'a'.repeat(32)}))};
    const c = {locales: Object.keys(probe.COUNTS).map(locale => ({locale, map_sha256: probe.sha(locale)}))};
    const write = (name, bytes) => {
      const file = path.join(directory, name); fs.writeFileSync(file, bytes, {mode: 0o600});
      return [file, probe.sha(bytes)];
    };
    const options = {node: 'kazoo_apps@isolated.invalid', account: ACCOUNT, resolution: {},
      'fixed-pack': '/synthetic/fixed', 'completion-pack': '/synthetic/completion', 'supplemental-pack': '/synthetic/supplemental'};
    const putInput = (key, name, data) => {
      const [file, digest] = write(name, Buffer.from(typeof data === 'string' ? data : JSON.stringify(data)));
      options[key] = file; options[key + '-sha256'] = digest;
    };
    putInput('fixed-receipt', 'fixed.json', receipt); putInput('cardinal-receipt', 'cardinal.json', c);
    putInput('fixed-map', 'map.hrl', text);
    const beams = probe.MODULES.map(module => {
      const [file, digest] = write(module + '.beam', Buffer.from('SYNTHETIC BEAM ' + module));
      return {module, path: file, sha256: digest};
    });
    putInput('beam-manifest', 'beams.json', {schema_version: 1, modules: beams});
    const selected = {fixture: 'source plans'}, cardinalDocs = Array.from({length: 586}, (_, i) => ({_id: 'synthetic-cardinal/' + i}));
    let cardinalCalls = 0, fixedCalls = 0;
    installer.releasePlans = (a, b, resolution) => {
      assert.equal(a, undefined); assert.equal(b, undefined); assert.deepEqual(resolution, {}); return selected;
    };
    cardinal.expectedDocuments = (entries, inputReceipt) => {
      assert.equal(entries, selected); assert.deepEqual(inputReceipt, c); cardinalCalls++; return cardinalDocs;
    };
    importer.loadPlan = (a, b, locales, supplemental) => {
      assert.equal(a, '/synthetic/fixed'); assert.equal(b, '/synthetic/completion');
      assert.deepEqual(locales, Object.keys(probe.COUNTS)); assert.equal(supplemental, '/synthetic/supplemental');
      fixedCalls++; return plan;
    };
    assert.equal(typeof cardinal.row, 'undefined', 'Regression must not rely on a private/unexported row parser');
    const input = probe.buildInput(options);
    assert.equal(cardinalCalls, 1); assert.equal(fixedCalls, 1); assert.equal(input.documents.length, 796);
    assert.equal(fixed.expectedDocuments, actualFixedDocuments, 'Real fixed adapter must remain installed');
    for (const p of plan) {
      const doc = input.documents.find(d => d._id === p.id);
      assert.equal(doc._rev, '2-' + 'a'.repeat(32)); assert.equal(doc.content_length, p.bytes.length);
      assert.equal(doc.source_voice.canonical_prompt_id, p.canonical_id);
      assert.equal(doc.source_voice.transcript_sha256, p.transcript_sha256);
      assert.equal(doc.digest, p.md5); assert.equal(doc.source_cardinal_resolution, null);
    }
    // Exercise the real wrapper with an explicit synthetic SUP response. SUP
    // accepts seconds, whereas spawnSync uses milliseconds; neither may become
    // an accidentally unbounded remote RPC.
    options.output = path.join(directory, 'synthetic-runtime-receipt.json');
    let rpcCalls = 0;
    const result = probe.execute(options, {spawn(command, args, spawnOptions) {
      if (command === 'getent') return {status: 0, stdout: 'kazoo:x:987:\n'};
      assert.equal(command, '/usr/local/bin/sup');
      assert.equal(args[args.indexOf('-t') + 1], '180');
      assert.equal(spawnOptions.timeout, 190000);
      const script = JSON.parse(args.at(-1));
      const raw = fs.readFileSync(path.join(path.dirname(script), 'input.json'));
      rpcCalls++;
      return {status: 0, stdout: '{ok,{ok,{prerecorded_runtime_verified,<<"' + probe.sha(raw)
        + '">>,796,1592,5,95,10,80,no_database_writes,no_calls,no_native_review}}}'};
    }});
    assert.equal(rpcCalls, 1);
    assert.equal(result.full_language_ready, false);
    // Real fixed validator must reject an uncorrelated receipt before rendering.
    const badReceipt = clone(receipt); badReceipt.prompts[0].sha256 = H(0);
    putInput('fixed-receipt', 'fixed.json', badReceipt); assert.throws(() => probe.buildInput(options));
    putInput('fixed-receipt', 'fixed.json', receipt);
    putInput('fixed-map', 'map.hrl', text.replace(rows[0][6], H(0))); assert.throws(() => probe.buildInput(options));
    for (const bad of [text + '\n-define(UNEXPECTED, 1).\n', text.replace('GEMINI_ASSETS', 'OTHER_ASSETS'),
      text.replace(rows[1][2], rows[0][2]), text.replace(']).', ',\n]).'),
      text.replace(']).', ']).\nos:cmd("forbidden").')]) assert.throws(() => probe.fixedMapRows(bad));
  } finally {
    installer.releasePlans = originals.releasePlans; cardinal.expectedDocuments = originals.cardinalDocuments;
    importer.loadPlan = originals.loadPlan;
    for (const name of fs.readdirSync(directory)) fs.unlinkSync(path.join(directory, name)); fs.rmdirSync(directory);
  }
});
