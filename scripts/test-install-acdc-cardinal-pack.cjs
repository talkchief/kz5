#!/usr/bin/env node
'use strict';
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs'), os = require('node:os');
const {install, installAll, releasePlans, options, checkedHeader, APPROVAL, LOCALES} = require('./install-acdc-cardinal-pack.cjs');
const pack = require('./acdc-cardinal-pack.cjs');
const {COUNTS, INTROS} = require('./import-acdc-gemini-cardinals.cjs');
const clone = value => JSON.parse(JSON.stringify(value));

// Adapter doubles only: no WAVs, provider calls, database connection, generated
// source maps or release readiness. The separate importer tests exercise real
// ledger/audio validation; these cases verify all-locale ordering and barriers.
function releaseFixture() {
  const events = [], states = new Map(), clientCalls = [];
  const client = async (...args) => { clientCalls.push(args); return {status: 201}; };
  const entries = LOCALES.map(locale => {
    const intro = INTROS[locale], count = COUNTS[locale];
    const state = {map: `synthetic-map-${locale}`, header: `synthetic-map-${locale}`,
      summary: {locale, count, catalog_sha256: pack.CATALOG_HASH, locale_catalog_sha256: pack.LOCALE_HASHES[locale],
        context_sha256: pack.digest(pack.contexts[locale]), approval_sha256: APPROVAL,
        cardinal_manifest_sha256: '1'.repeat(64), selected_asset_set_sha256: '2'.repeat(64), map_sha256: '3'.repeat(64),
        historical_artifact_complete: true, authoring_approval_declared: true, resampling_provenance_verified: true,
        preserves_original_request_history: true, preserves_210_inventory: true, creates_only_versioned_ids: true,
        runtime_ready: false, full_position_language_ready: false, five_language_release_ready: false, listening_verified: false,
        intro: {...intro, source_bytes_verified: true,
          document_id: `${locale}/${intro.canonical_id}-gemini-sulafat-${intro.wav_sha256.slice(0, 16)}`},
        prompts: pack.plan(locale).map(p => ({id: p.id}))}};
    states.set(locale, state);
    return {locale, header: () => state.header,
      plan: {summary: () => clone(state.summary), renderMap: () => state.map,
        install: async (connection, write) => {
          events.push([locale, write]);
          if (state.error) throw new Error(state.error);
          if (state.beforeOperation) state.beforeOperation();
          if (state.operation) await connection(...state.operation);
          if (state.afterInstall) state.afterInstall(write);
          return {...clone(state.summary), mode: write ? 'IMPORT' : 'VERIFY_ONLY',
            verified: count, created: 0, intro_installed_verified: true, ...state.receiptPatch};
        }}};
  });
  return {entries, states, events, clientCalls, client};
}

function mixedFixture() {
  const f = releaseFixture(), audit = {source_manifest_sha256: '1'.repeat(64), approvals_sha256: APPROVAL,
    runtime_ready: false, native_listening_approved: false, additional_trial_requests: 5};
  for (const locale of LOCALES) {
    const summary = f.states.get(locale).summary;
    summary.historical_artifact_complete = false;
    if (locale === 'en-us') {
      summary.prompts = pack.plan(locale).map(p => ({id: p.id, entry_sha256: '4'.repeat(64), attempt: 1,
        master_sha256: '5'.repeat(64), telephony_sha256: '6'.repeat(64)}));
      summary.selected_asset_set_sha256 = pack.digest(summary.prompts.map(p =>
        ({id: p.id, master: p.master_sha256, telephony: p.telephony_sha256})).sort((a, b) => a.id.localeCompare(b.id, 'en')));
      continue;
    }
    summary.prompts = pack.plan(locale).map((p, index) => {
      const reused = locale === 'es-es' && ['acdc-cardinal-v1-number-4', 'acdc-cardinal-v1-number-9'].includes(p.id);
      const kind = reused ? 'reused_supplemental_master' : index === 0 ? 'separate_model_trial' : 'generated_cardinal';
      return {id: p.id, resolution: {source_kind: kind, provider: 'google-gemini', voice: 'Sulafat',
        model: kind === 'separate_model_trial' ? 'gemini-3.1-flash-tts-preview' : pack.MODEL,
        master_sha256: '5'.repeat(64), telephony_sha256: '6'.repeat(64),
        transcript_sha256: p.transcript_sha256, context_sha256: p.context_sha256,
        catalog_record_sha256: p.catalog_record_sha256, resampling_recipe_sha256: pack.digest(pack.RESAMPLING),
        runtime_ready: false, listening_verified: false, provider_provenance_authenticated: false,
        ...(reused ? {alias_manifest_sha256: 'a'.repeat(64), source_locale: locale,
          source_id: p.id.endsWith('-4') ? 'acdc-number-4' : 'acdc-number-9'} : {})}};
    }).sort((a, b) => a.id.localeCompare(b.id, 'en'));
    Object.assign(summary, {asset_set_kind: 'cardinal-resolved-assets-v1', staged_candidates_only: true,
      model_trial_index_sha256: '7'.repeat(64), native_listening_approved: false, selected_unresolved: 0,
      resolved_listening_approval_declared: false, model_trial_audit: clone(audit), additional_trial_requests: 5,
      selected_generated: COUNTS[locale] - 1 - (locale === 'es-es' ? 2 : 0), selected_model_trials: 1,
      selected_reused: locale === 'es-es' ? 2 : 0,
      ...(locale === 'es-es' ? {alias_manifest_sha256: 'a'.repeat(64)} : {})});
    summary.selected_asset_set_sha256 = summary.resolved_asset_set_sha256 = pack.digest({schema_version: 1,
      kind: 'cardinal-resolved-assets-v1', locale, intro: INTROS[locale], prompts: summary.prompts});
  }
  return f;
}

async function mixedCases() {
  const resolution = {modelTrialIndex: '/tmp/cardinal-trials/index.json', modelTrialIndexSha256: '7'.repeat(64),
    supplementalDirectory: '/tmp/cardinal-supplemental', aliasFile: '/tmp/cardinal-aliases.json', aliasSha256: 'a'.repeat(64)};
  const args = ['--plan', '--all-locales', '--model-trial-index', resolution.modelTrialIndex,
    '--model-trial-index-sha256', resolution.modelTrialIndexSha256,
    '--supplemental-pack', resolution.supplementalDirectory, '--alias-file', resolution.aliasFile, '--alias-sha256', resolution.aliasSha256];
  assert.deepEqual(options(args), {mode: '--plan', allLocales: true, resolution});
  for (const invalid of [args.filter(a => a !== '--all-locales'), args.slice(0, -2), args.slice(0, 5),
    [...args, '--alias-file', resolution.aliasFile], [...args, '--model-trial-index', resolution.modelTrialIndex],
    ['--plan', '--all-locales', '--alias-file', resolution.aliasFile, '--alias-sha256', resolution.aliasSha256,
      '--supplemental-pack', resolution.supplementalDirectory],
    args.map(a => a === resolution.modelTrialIndex ? '/tmp/../outside/index.json' : a),
    args.map(a => a === resolution.modelTrialIndexSha256 ? 'not-a-hash' : a)]) assert.throws(() => options(invalid));
  const opened = [], maps = [];
  const entries = releasePlans(source => { opened.push(source); return {}; }, file => { maps.push(file); return 'map'; }, resolution);
  entries.forEach(e => e.header());
  assert.equal(opened[0].locale, 'en-us');
  assert.equal(opened[0].modelTrialIndex, undefined); assert.equal(opened[0].aliasFile, undefined);
  assert(opened.slice(1).every(s => s.modelTrialIndex === resolution.modelTrialIndex
    && s.modelTrialIndexSha256 === resolution.modelTrialIndexSha256));
  assert(opened.filter(s => s.locale !== 'es-es').every(s => s.aliasFile === undefined && s.supplementalDirectory === undefined));
  assert.equal(opened.find(s => s.locale === 'es-es').aliasFile, resolution.aliasFile);
  assert(maps.every(file => file.startsWith(path.join(__dirname, '../applications/acdc/src') + '/')));
  assert.throws(() => releasePlans(() => assert.fail('invalid options must fail before opening sources'), () => '',
    {modelTrialIndex: resolution.modelTrialIndex}));

  let f = mixedFixture();
  const plan = await installAll('--plan', f.entries, null);
  assert.equal(plan.count, 584); assert.equal(plan.source_complete, true); assert.equal(plan.resolution_complete, true);
  assert.equal(plan.historical_artifact_complete, false); assert.equal(plan.additional_trial_requests, 5);
  assert.equal(plan.selected_generated, 578); assert.equal(plan.selected_model_trials, 4); assert.equal(plan.selected_reused, 2);
  assert.equal(plan.database_verified, false); assert.deepEqual(f.events, []); assert.deepEqual(f.clientCalls, []);
  assert.equal(plan.locales[0].asset_set_kind, undefined); assert.equal(plan.locales[0].model_trial_index_sha256, undefined);
  for (const flag of ['runtime_ready', 'native_listening_approved', 'listening_verified', 'five_language_release_ready']) assert.equal(plan[flag], false);
  // A preserved/generated-only EN plan remains untouched on repeated complete
  // mixed installs: the adapter passes no trial/alias options and no source
  // metadata backfill operation is introduced. Byte-level idempotence lives in
  // the real importer suite; these doubles prove adapter ordering/forwarding.
  const enSource = clone(f.states.get('en-us').summary);
  for (let n = 0; n < 2; n++) {
    f.events.length = 0;
    const receipt = await installAll('--import', f.entries, f.client);
    assert.equal(receipt.verified, 584); assert.equal(receipt.locales[0].created, 0);
    assert.deepEqual(receipt.locales[0].prompts, enSource.prompts);
    assert.deepEqual(f.events, [...LOCALES.map(l => [l, true]), ...LOCALES.map(l => [l, false])]);
    assert.deepEqual(f.clientCalls, []);
  }
  for (const kind of ['partial-last', 'missing-index', 'different-index', 'different-audit', 'false-history',
    'source-count', 'role', 'model', 'voice', 'context', 'asset-set', 'listening', 'readiness', 'cross-locale-alias', 'en-proof', 'en-resolved']) {
    f = mixedFixture(); const last = f.states.get('ar-sa').summary;
    if (kind === 'partial-last') last.selected_unresolved = 1;
    if (kind === 'missing-index') delete last.model_trial_index_sha256;
    if (kind === 'different-index') last.model_trial_index_sha256 = '8'.repeat(64);
    if (kind === 'different-audit') last.model_trial_audit.extra = true;
    if (kind === 'false-history') last.historical_artifact_complete = true;
    if (kind === 'source-count') last.selected_model_trials++;
    if (kind === 'role') last.prompts.pop();
    if (kind === 'model') last.prompts[0].resolution.model = 'other';
    if (kind === 'voice') last.prompts[0].resolution.voice = 'Kore';
    if (kind === 'context') last.prompts[0].resolution.context_sha256 = '0'.repeat(64);
    if (kind === 'asset-set') last.resolved_asset_set_sha256 = '0'.repeat(64);
    if (kind === 'listening') last.native_listening_approved = true;
    if (kind === 'readiness') last.staged_candidates_only = false;
    if (kind === 'cross-locale-alias') last.alias_manifest_sha256 = 'a'.repeat(64);
    if (kind === 'en-proof') f.states.get('en-us').summary.prompts[0].master_sha256 = '0'.repeat(64);
    if (kind === 'en-resolved') f.states.get('en-us').summary.model_trial_index_sha256 = '7'.repeat(64);
    await assert.rejects(installAll('--import', f.entries, f.client), undefined, kind);
    assert.deepEqual(f.events, [], kind); assert.deepEqual(f.clientCalls, [], kind);
  }
  for (const patch of [{model_trial_index_sha256: '0'.repeat(64)}, {selected_model_trials: 99},
    {selected_unresolved: 1}, {prompts: []}, {historical_artifact_complete: true}, {native_listening_approved: true}]) {
    f = mixedFixture(); f.states.get('ar-sa').receiptPatch = patch;
    await assert.rejects(installAll('--verify-only', f.entries, f.client), /invalid five-locale cardinal receipt/);
  }
  f = mixedFixture(); f.states.get('en-us').receiptPatch = {prompts: []};
  await assert.rejects(installAll('--verify-only', f.entries, f.client), /invalid five-locale cardinal receipt/);
  f = mixedFixture(); f.states.get('en-us').afterInstall = () => {
    f.states.get('ar-sa').summary.model_trial_index_sha256 = '8'.repeat(64);
  };
  await assert.rejects(installAll('--import', f.entries, f.client), /source changed/);
  assert.deepEqual(f.events, [['en-us', true]]);
  process.stdout.write('PASS mixed-model all-five completeness, shared index, ES-only aliases, unchanged EN and exact final provenance; adapter doubles only\n');
}

async function allLocaleCases() {
  for (const mode of ['--plan', '--import', '--verify-only']) {
    assert.deepEqual(options([mode]), {mode, allLocales: false});
    assert.deepEqual(options([mode, '--all-locales']), {mode, allLocales: true});
  }
  for (const args of [[], ['--all-locales'], ['--plan', '--all-locales', '--all-locales'],
    ['--import', '--locale', 'he-il'], ['--plan', '--all-locales', '--cardinal-pack', '/tmp/foreign'],
    ['--plan', '--all-locales', '--map-directory', '/tmp/foreign'], ['--all-locales', '--plan']]) {
    assert.throws(() => options(args));
  }
  const sourceCalls = [], mapCalls = [];
  const located = releasePlans(source => { sourceCalls.push(source); return {}; },
    (file, maximum) => { mapCalls.push([file, maximum]); return 'synthetic'; });
  located.forEach(e => e.header());
  assert.deepEqual(sourceCalls.map(s => s.locale), LOCALES);
  assert(sourceCalls.every(s => s.cardinalDirectory === path.join(__dirname, 'assets/acdc-gemini-cardinals-20260907')
    && s.approvalSha256 === APPROVAL));
  assert.equal(mapCalls[0][0], path.join(__dirname, '../applications/acdc/src/acdc_cardinal_map.hrl'));
  assert.equal(mapCalls[0][1], 65536);
  assert(mapCalls.slice(1).every(([file, max]) => file.startsWith(path.join(__dirname, '../applications/acdc/src/cardinal_maps') + '/')
    && max === 256 * 1024));
  for (const source of sourceCalls) assert(source.introFile.includes(['he-il', 'ar-sa'].includes(source.locale)
    ? 'acdc-gemini-cardinal-intros-20260907' : 'acdc-gemini-fixed-20260905'));
  // Retained private reader specimens; these are not generated release maps.
  const specimen = fs.mkdtempSync(path.join(os.tmpdir(), 'cardinal-adapter-map-reader.'));
  fs.chmodSync(specimen, 0o700);
  const large = path.join(specimen, 'large-reader-specimen.txt'), ordinary = path.join(specimen, 'ordinary.txt');
  fs.writeFileSync(large, 'x'.repeat(70 * 1024), {mode: 0o600});
  fs.writeFileSync(ordinary, 'reader specimen', {mode: 0o600});
  assert.throws(() => checkedHeader(large), /invalid checked-in cardinal map/);
  assert.equal(checkedHeader(large, 256 * 1024).length, 70 * 1024);
  assert.equal(checkedHeader(ordinary), 'reader specimen');
  fs.symlinkSync(ordinary, path.join(specimen, 'symlink.txt'));
  assert.throws(() => checkedHeader(path.join(specimen, 'symlink.txt')));
  fs.linkSync(ordinary, path.join(specimen, 'hardlink.txt'));
  assert.throws(() => checkedHeader(ordinary), /invalid checked-in cardinal map/);
  fs.chmodSync(large, 0o666);
  assert.throws(() => checkedHeader(large, 256 * 1024), /invalid checked-in cardinal map/);

  let f = releaseFixture();
  const planned = await installAll('--plan', f.entries, null);
  assert.equal(planned.count, 584); assert.equal(planned.source_complete, true); assert.equal(planned.database_verified, false);
  assert.deepEqual(planned.locales.map(s => [s.locale, s.count]), LOCALES.map(l => [l, COUNTS[l]]));
  assert.deepEqual(f.events, []); assert.deepEqual(f.clientCalls, []);
  const imported = await installAll('--import', [...f.entries].reverse(), f.client);
  assert.deepEqual(f.events, [...LOCALES.map(l => [l, true]), ...LOCALES.map(l => [l, false])]);
  assert.equal(imported.verified, 584); assert.equal(imported.database_verified, true); assert.equal(imported.mode, 'IMPORT_AND_VERIFY');
  for (const key of ['runtime_ready', 'full_position_language_ready', 'five_language_release_ready', 'listening_verified', 'queue_configuration_changed']) {
    assert.equal(imported[key], false);
  }
  f = releaseFixture();
  assert.equal((await installAll('--verify-only', f.entries, f.client)).mode, 'VERIFY_ONLY');
  assert.deepEqual(f.events, LOCALES.map(l => [l, false]));

  for (const kind of ['missing-locale', 'duplicate-locale', 'wrong-locale', 'missing-map', 'wrong-map',
    'incomplete', 'wrong-count', 'missing-role', 'duplicate-role', 'context', 'approval', 'ledger', 'intro', 'intro-tuple', 'readiness']) {
    f = releaseFixture(); const last = f.states.get('ar-sa');
    if (kind === 'missing-locale') f.entries.pop();
    if (kind === 'duplicate-locale') f.entries[4] = f.entries[0];
    if (kind === 'wrong-locale') f.entries[4].locale = ['ar-sa'];
    if (kind === 'missing-map') f.entries[4].header = () => { throw new Error('missing reviewed map'); };
    if (kind === 'wrong-map') last.header = 'unreviewed';
    if (kind === 'incomplete') last.summary.historical_artifact_complete = false;
    if (kind === 'wrong-count') last.summary.count--;
    if (kind === 'missing-role') last.summary.prompts.pop();
    if (kind === 'duplicate-role') last.summary.prompts[1] = last.summary.prompts[0];
    if (kind === 'context') last.summary.context_sha256 = '0'.repeat(64);
    if (kind === 'approval') last.summary.approval_sha256 = '0'.repeat(64);
    if (kind === 'ledger') last.summary.cardinal_manifest_sha256 = '0'.repeat(64);
    if (kind === 'intro') last.summary.intro.wav_sha256 = INTROS['he-il'].wav_sha256;
    if (kind === 'intro-tuple') last.summary.intro.document_id = 'he-il/foreign-intro';
    if (kind === 'readiness') last.summary.runtime_ready = true;
    await assert.rejects(installAll('--import', f.entries, f.client), undefined, kind);
    assert.deepEqual(f.events, [], kind); assert.deepEqual(f.clientCalls, [], kind);
  }
  // Drift between the complete preflight and first import still blocks all writes.
  f = releaseFixture();
  f.entries[4].header = () => {
    f.states.get('en-us').summary.map_sha256 = '4'.repeat(64);
    return f.states.get('ar-sa').header;
  };
  await assert.rejects(installAll('--import', f.entries, f.client), /source changed/);
  assert.deepEqual(f.events, []);
  // If already-created immutable media exists when later drift is observed, no
  // later locale is written and no rollback/overwrite or retry is attempted.
  f = releaseFixture();
  f.states.get('en-us').afterInstall = () => { f.states.get('ar-sa').header = 'drift'; };
  await assert.rejects(installAll('--import', f.entries, f.client), /source changed/);
  assert.deepEqual(f.events, [['en-us', true]]);
  f = releaseFixture(); f.states.get('he-il').error = 'ambiguous transport';
  await assert.rejects(installAll('--import', f.entries, f.client), /ambiguous transport/);
  assert.deepEqual(f.events, [['en-us', true], ['he-il', true]]);
  f = releaseFixture();
  f.states.get('en-us').beforeOperation = () => { f.states.get('ar-sa').header = 'drift-before-put'; };
  f.states.get('en-us').operation = ['PUT', 'synthetic', {}];
  await assert.rejects(installAll('--import', f.entries, f.client), /source changed/);
  assert.deepEqual(f.clientCalls, []);

  for (const patch of [{verified: 207}, {created: 1}, {intro_installed_verified: false}, {intro: undefined},
    {locale: 'he-il'}, {map_sha256: '0'.repeat(64)}, {selected_asset_set_sha256: '0'.repeat(64)},
    {mode: 'IMPORT'}, {runtime_ready: true}, {listening_verified: true}]) {
    f = releaseFixture(); f.states.get('ar-sa').receiptPatch = patch;
    await assert.rejects(installAll('--verify-only', f.entries, f.client), /invalid five-locale cardinal receipt/);
  }
  f = releaseFixture(); f.states.get('ar-sa').afterInstall = () => { f.states.get('en-us').header = 'late-drift'; };
  await assert.rejects(installAll('--verify-only', f.entries, f.client), /source changed/);
  for (const mode of ['--verify-only', '--import']) {
    f = releaseFixture();
    f.states.get('en-us').operation = ['PUT', 'synthetic', {}];
    if (mode === '--import') f.states.get('ar-sa').afterInstall = write => {
      if (write) f.states.get('en-us').operation = ['PUT', 'synthetic', {}];
    };
    await assert.rejects(installAll(mode, f.entries, f.client), /invalid cardinal database operation/);
    assert.equal(f.clientCalls.length, mode === '--import' ? 1 : 0);
  }
  process.stdout.write('PASS five-locale installer barriers, fixed paths, complete ordering and read-only final verification; adapter doubles only\n');
}

async function main() {
  let calls = [];
  const good = {mode: 'VERIFY_ONLY', count: 31, verified: 31, created: 0,
    intro_installed_verified: true, map_sha256: 'expected-map'};
  const plan = {renderMap: () => 'header', summary: () => ({count: 31, map_sha256: 'expected-map'}),
    install: async (_client, write) => { calls.push(write); return {...good}; }};
  assert.equal((await install('--plan', plan, null, () => 'header')).mode, 'PLAN_ONLY_NO_DATABASE_ACCESS');
  assert.deepEqual(calls, []);
  assert.deepEqual(await install('--import', plan, {}, () => 'header'), good);
  assert.deepEqual(calls, [true, false]);
  calls = [];
  await install('--verify-only', plan, {}, () => 'header');
  assert.deepEqual(calls, [false]);
  calls = [];
  await assert.rejects(install('--import', plan, {}, () => 'wrong'), /map mismatch/);
  assert.deepEqual(calls, []);
  let reads = 0;
  await assert.rejects(install('--verify-only', plan, {}, () => ++reads === 1 ? 'header' : 'drift'), /map changed/);
  await assert.rejects(install('--import', {...plan, install: async () => { throw new Error('ambiguous'); }}, {}, () => 'header'), /ambiguous/);
  for (const bad of [{verified: 30}, {created: 1}, {intro_installed_verified: false},
    {map_sha256: 'different'}, {mode: 'IMPORT'}, {count: 32}]) {
    await assert.rejects(install('--verify-only', {...plan, install: async () => ({...good, ...bad})}, {}, () => 'header'), /invalid cardinal receipt/);
  }
  await assert.rejects(install('--all', plan, {}, () => 'header'), /invalid mode/);
  process.stdout.write('PASS 13 cardinal installer adapter cases; no provider, database, source or service writes\n');
  await allLocaleCases();
  await mixedCases();
}
main().catch(error => { console.error(error); process.exitCode = 1; });
