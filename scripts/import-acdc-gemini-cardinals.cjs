#!/usr/bin/env node
'use strict';

// Explicit single-locale staging. Read the original 584-entry request ledger; never rewrite
// it, synthesize, retry, trim audio, overwrite media or publish runtime readiness.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const pack = require('./acdc-cardinal-pack.cjs');
const reuse = require('./acdc-cardinal-reuse.cjs');
const modelTrials = require('./acdc-cardinal-model-trial-assets.cjs');
const media = require('./import-acdc-gemini-voices.cjs');
const {couchClient} = require('./import-acdc-language-packs.cjs');
const OWNER = 'kazoo5-acdc-cardinal-import', LOCALE = 'en-us', COUNT = 31;
const TRIAL_INDEX_OWNER = 'kazoo5-acdc-cardinal-model-trial-index';
const MAX_JSON = 8 * 1024 * 1024, MAX_WAV = 2 * 1024 * 1024;
const INTRO = Object.freeze({canonical_id: 'acdc-queue-your-current-position-is',
  transcript: 'Your current position is.',
  transcript_sha256: '14dc2fb6f6e5de230d62fed0f66e70626b64b2f23a7a31a052528d4f0ece880d',
  wav_sha256: '1fe37e0db985dab9765745fca6cc2e78d17026a992a6088dc92fa37ac7be2dd6'});
// Release pins, independent of the supplied ledger and its approval declaration.
// EN aliases and its emitted map remain byte-compatible with the existing installer.
const COUNTS = Object.freeze({'en-us': 31, 'es-es': 53, 'fr-fr': 161, 'he-il': 131, 'ar-sa': 208});
const INTROS = Object.freeze({
  'en-us': INTRO,
  'es-es': Object.freeze({canonical_id: INTRO.canonical_id, transcript: 'Su posición actual es.',
    transcript_sha256: 'a3c7ef71bec8c1c0db48b96ebbf59f4733cce242df4c30384b216b8fcf831bd9',
    wav_sha256: '4753cdfe28956fa8ea620508984041b30ab7fb781845c9f80b565e2662f216d4'}),
  'fr-fr': Object.freeze({canonical_id: INTRO.canonical_id, transcript: 'Votre position actuelle est.',
    transcript_sha256: 'e5613b3e9cb8b84efc9081c6876fe28815eec069d9b27866d96c25503b09cca0',
    wav_sha256: '7ed7292b5feac6a03881c958532d2f9150d39ea4ca7ecf9d1d11385f10be6b2c'}),
  'he-il': Object.freeze({canonical_id: 'acdc-cardinal-intro-v1-current-position-number',
    transcript: 'מִסְפַּר מְקוֹמְכֶם הַנּוֹכְחִי בַּתּוֹר הוּא.',
    transcript_sha256: '3546259e51a69a94ea84d3c3ba28d8b9105397ae0830599cc2b7301a0fb7a2d1',
    wav_sha256: 'e688f91fc0e23f4926a9be5d87ecc993042389eb895e7f10a602137d4e8ad944'}),
  'ar-sa': Object.freeze({canonical_id: 'acdc-cardinal-intro-v1-current-position-number',
    transcript: 'رَقْمُ مَوْقِعِكَ الْحَالِي فِي طَابُورِ الِانْتِظَارِ هُوَ.',
    transcript_sha256: 'a90d20b338dcafa924d45f03364399aca462df3fce7de1924397097ee0e2166f',
    wav_sha256: '312fb7ff3cc60bd2a378027978679302716136504f5ddaf8a3220f6fca2b8598'})
});
const hash = (bytes, algorithm = 'sha256', encoding = 'hex') => crypto.createHash(algorithm).update(bytes).digest(encoding);
const sha = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const clone = value => JSON.parse(JSON.stringify(value));
class ImportError extends Error { constructor(code) { super(code); this.name = 'CardinalImportError'; this.code = code; } }
const check = (ok, code) => { if (!ok) throw new ImportError(code); };
function exactKeys(value, wanted) {
  check(value !== null && typeof value === 'object' && Object.getPrototypeOf(value) === Object.prototype
    && Object.keys(value).sort().join(',') === [...wanted].sort().join(','), 'INVALID_CARDINAL_OPTIONS');
}
function sourceOptions(value) {
  const required = ['cardinalDirectory', 'introFile', 'approvalSha256', 'locale'];
  const optional = ['supplementalDirectory', 'aliasFile', 'aliasSha256'];
  const trialOptions = ['modelTrialIndex', 'modelTrialIndexSha256'];
  const aliases = value !== null && typeof value === 'object' && optional.some(k => Object.hasOwn(value, k));
  const trials = value !== null && typeof value === 'object' && trialOptions.some(k => Object.hasOwn(value, k));
  exactKeys(value, [...required, ...(aliases ? optional : []), ...(trials ? trialOptions : [])]);
  if (aliases) {
    check(sha(value.aliasSha256), 'INDEPENDENT_ALIAS_PIN_REQUIRED');
    for (const k of ['supplementalDirectory', 'aliasFile']) check(typeof value[k] === 'string'
      && path.isAbsolute(value[k]) && path.resolve(value[k]) === value[k], 'PINNED_ALIAS_SOURCE_REQUIRED');
  }
  if (trials) check(sha(value.modelTrialIndexSha256) && typeof value.modelTrialIndex === 'string'
    && path.isAbsolute(value.modelTrialIndex) && path.resolve(value.modelTrialIndex) === value.modelTrialIndex,
  'INDEPENDENT_MODEL_TRIAL_INDEX_PIN_REQUIRED');
  return {aliases, trials};
}
function directory(root) {
  check(typeof root === 'string' && path.isAbsolute(root) && path.resolve(root) === root
    && root.split(path.sep).filter(Boolean).length >= 2, 'INVALID_CARDINAL_DIRECTORY');
  const stat = fs.lstatSync(root);
  check(stat.isDirectory() && !stat.isSymbolicLink() && !(stat.mode & 0o022)
    && fs.realpathSync(root) === root, 'INVALID_CARDINAL_DIRECTORY');
}
const sameFile = (a, b) => ['dev', 'ino', 'size', 'mode', 'nlink', 'mtimeMs', 'ctimeMs'].every(k => a[k] === b[k]);
function read(root, relative, maximum) {
  directory(root);
  check(typeof relative === 'string' && relative.length < 512 && !relative.startsWith('/')
    && relative.split('/').every(p => /^[A-Za-z0-9_.-]+$/.test(p) && p !== '.' && p !== '..'), 'INVALID_CARDINAL_PATH');
  const file = path.join(root, relative), parent = path.dirname(file); directory(parent);
  const before = fs.lstatSync(file);
  check(before.isFile() && !before.isSymbolicLink() && before.nlink === 1 && !(before.mode & 0o022)
    && before.size > 0 && before.size <= maximum, 'INVALID_CARDINAL_FILE');
  const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
  try {
    const opened = fs.fstatSync(fd); check(sameFile(before, opened), 'CARDINAL_INPUT_CHANGED');
    const bytes = Buffer.alloc(opened.size + 1); let size = 0, count;
    while (size < bytes.length && (count = fs.readSync(fd, bytes, size, bytes.length - size, null)) > 0) size += count;
    check(size === opened.size && sameFile(opened, fs.fstatSync(fd)) && sameFile(opened, fs.lstatSync(file))
      && fs.realpathSync(parent) === parent, 'CARDINAL_INPUT_CHANGED');
    return bytes.subarray(0, size);
  } finally { fs.closeSync(fd); }
}
function asset(locale, id, transcriptHash, bytes, file, duration) {
  const sha256 = hash(bytes), promptId = `${id}-gemini-sulafat-${sha256.slice(0, 16)}`;
  check(/^[a-z0-9_-]{1,128}$/.test(promptId) && sha(transcriptHash), 'INVALID_CARDINAL_IDENTITY');
  return {locale, canonical_id: id, prompt_id: promptId, id: `${locale}/${promptId}`,
    attachment: `${promptId}.wav`, sha256, md5: 'md5-' + hash(bytes, 'md5', 'base64'), bytes,
    source_file: path.relative(path.join(__dirname, '..'), file),
    transcript_sha256: transcriptHash, duration_seconds: duration};
}
function openPlan(options) {
  const {aliases, trials} = sourceOptions(options);
  const {cardinalDirectory, introFile, approvalSha256, locale} = options;
  // Reject unsupported scopes before opening any source or database connection.
  check(typeof locale === 'string' && Object.hasOwn(COUNTS, locale), 'CARDINAL_LOCALE_NOT_STAGED');
  const count = COUNTS[locale], intro = INTROS[locale], createIntro = ['he-il', 'ar-sa'].includes(locale);
  check(sha(approvalSha256), 'INDEPENDENT_APPROVAL_PIN_REQUIRED');
  check(typeof introFile === 'string' && path.isAbsolute(introFile) && path.resolve(introFile) === introFile,
    'EXACT_INTRO_FILE_REQUIRED');
  const inputPins = [], remember = (root, relative, maximum, expected) => {
    const bytes = read(root, relative, maximum), actual = hash(bytes);
    check(expected === undefined || actual === expected, 'CARDINAL_SOURCE_HASH_MISMATCH');
    inputPins.push({root, relative, maximum, sha256: actual}); return bytes;
  };
  const manifestHash = hash(remember(cardinalDirectory, 'manifest.json', MAX_JSON));
  // Real validator includes every original attempt and deterministic SoX replay.
  // verifyPack() deliberately is NOT used: other locales remain incomplete.
  const manifest = pack.readManifest(cardinalDirectory);
  pack.requireAuthoringApproval(manifest, [locale], approvalSha256);
  const approval = manifest.approvals.find(a => a.locale === locale);
  check(Object.keys(intro).every(k => approval.intro[k] === intro[k]),
    locale === LOCALE ? 'APPROVED_EN_INTRO_CHANGED' : 'APPROVED_LOCALE_INTRO_CHANGED');
  const introBytes = remember(path.dirname(introFile), path.basename(introFile), MAX_WAV, intro.wav_sha256);
  const introMetrics = pack.technicalQa(pack.inspectWave(introBytes, 8000));
  const introAsset = asset(locale, intro.canonical_id, intro.transcript_sha256, introBytes, introFile, introMetrics.duration_seconds);
  const documentVoice = media.document(introAsset, 0).source_voice;
  check(documentVoice.provider === manifest.provider && documentVoice.model === manifest.model
    && documentVoice.voice === manifest.voice, 'MEDIA_WRITER_PROVENANCE_MISMATCH');
  const expected = pack.plan(locale), selected = manifest.prompts.filter(e => e.locale === locale);
  check(expected.length === count && selected.length === count && new Set(selected.map(e => e.id)).size === count,
    locale === LOCALE ? 'EXACT_EN31_REQUIRED' : 'EXACT_LOCALE_INVENTORY_REQUIRED');
  const resolver = aliases ? reuse.openResolution({cardinalDirectory,
    supplementalDirectory: options.supplementalDirectory, aliasFile: options.aliasFile, aliasSha256: options.aliasSha256}) : null;
  let trialResolver, trialSummary, trialDirectories;
  if (trials) {
    const indexRoot = path.dirname(options.modelTrialIndex);
    const index = JSON.parse(remember(indexRoot, path.basename(options.modelTrialIndex), 32768, options.modelTrialIndexSha256));
    exactKeys(index, ['schema_version', 'owner', 'source_manifest_sha256', 'catalog_sha256', 'approvals_sha256',
      'trials', 'runtime_ready', 'native_listening_approved']);
    check(index.schema_version === 1 && index.owner === TRIAL_INDEX_OWNER && index.source_manifest_sha256 === manifestHash
      && index.catalog_sha256 === pack.CATALOG_HASH && index.approvals_sha256 === approvalSha256
      && index.runtime_ready === false && index.native_listening_approved === false
      && Array.isArray(index.trials) && index.trials.length >= 1 && index.trials.length <= modelTrials.MAX_TRIALS,
    'INVALID_MODEL_TRIAL_INDEX');
    const directories = new Set(), hashes = new Set();
    const entries = index.trials.map(item => {
      exactKeys(item, ['directory', 'sha256']);
      check(typeof item.directory === 'string' && item.directory.length < 512 && item.directory.split('/').every(p =>
        /^[A-Za-z0-9_.-]+$/.test(p) && p !== '.' && p !== '..') && sha(item.sha256)
        && !directories.has(item.directory) && !hashes.has(item.sha256), 'INVALID_MODEL_TRIAL_INDEX_ENTRY');
      directories.add(item.directory); hashes.add(item.sha256);
      return {directory: path.join(indexRoot, item.directory), sha256: item.sha256};
    });
    trialDirectories = new Map(entries.map(e => [e.sha256, e.directory]));
    trialResolver = modelTrials.openResolution({sourceDirectory: cardinalDirectory,
      sourceManifestSha256: manifestHash, approvalSha256, trials: entries});
    trialSummary = trialResolver.summary();
  }
  const trialIdentities = new Set(trialSummary?.successful_identities || []);
  const resolvedMode = resolver || trialResolver;
  const proof = [], assets = expected.map(wanted => {
    const entry = selected.find(e => e.id === wanted.id);
    if (resolvedMode) {
      // Resolve the whole selected inventory before a client can be opened. A
      // reused whole word is not a successful generation attempt in the ledger.
      check(entry, 'CARDINAL_LOCALE_INCOMPLETE');
      let resolved;
      if (entry.generation_status !== 'QA_PASSED' && trialIdentities.has(`${locale}/${wanted.id}`)) {
        resolved = trialResolver.resolve(locale, wanted.id);
      } else if (resolver) resolved = resolver.resolve(locale, wanted.id);
      else {
        check(entry.generation_status === 'QA_PASSED', 'CARDINAL_LOCALE_INCOMPLETE');
        const a = entry.attempts.at(-1), bytes = remember(cardinalDirectory, a.telephony.file, MAX_WAV, a.telephony.sha256);
        resolved = {transcript: entry.transcript, source_kind: 'generated_cardinal', telephony: bytes,
          provenance: {cardinal_entry_sha256: pack.digest(entry), attempt: a.number, request_body_sha256: a.request_body_sha256,
            cardinal_manifest_sha256: manifestHash, catalog_sha256: pack.CATALOG_HASH,
            catalog_record_sha256: entry.catalog_record_sha256, transcript_sha256: entry.transcript_sha256,
            context_sha256: entry.context_sha256, provider: manifest.provider, model: manifest.model, voice: manifest.voice,
            master_sha256: a.master.sha256, telephony_sha256: a.telephony.sha256,
            telephony_pcm_sha256: a.telephony.pcm_sha256, duration_seconds: a.telephony.duration_seconds,
            resampling_recipe_sha256: pack.digest(pack.RESAMPLING)}};
      }
      const p = resolved.provenance, trial = resolved.source_kind === 'separate_model_trial';
      check(resolved.transcript === entry.transcript && p.transcript_sha256 === entry.transcript_sha256
        && p.catalog_record_sha256 === entry.catalog_record_sha256 && p.context_sha256 === entry.context_sha256
        && (trial ? p.source_manifest_sha256 : p.cardinal_manifest_sha256) === manifestHash
        && p.provider === manifest.provider && p.voice === manifest.voice
        && p.model === (trial ? modelTrials.MODEL : manifest.model), 'CARDINAL_RESOLUTION_CHANGED');
      let file;
      if (trial) {
        const receipt = trialSummary.trials.find(t => t.trial_manifest_sha256 === p.trial_manifest_sha256);
        const index = receipt?.outcomes.findIndex(e => e.identity === `${locale}/${entry.id}` && e.status === 'QA_PASSED');
        check(Number.isInteger(index) && index >= 0 && p.source_entry_sha256 === pack.digest(entry), 'CARDINAL_RESOLUTION_CHANGED');
        file = path.join(trialDirectories.get(p.trial_manifest_sha256),
          `${String(index + 1).padStart(2, '0')}-${locale}-${entry.id}.telephony-8000.wav`);
      } else if (resolved.source_kind === 'generated_cardinal') {
        const attempt = entry.attempts.at(-1);
        remember(cardinalDirectory, attempt.master.file, MAX_WAV, p.master_sha256);
        file = path.join(cardinalDirectory, attempt.telephony.file);
        remember(cardinalDirectory, attempt.telephony.file, MAX_WAV, p.telephony_sha256);
      } else {
        check(resolved.source_kind === 'reused_supplemental_master', 'CARDINAL_RESOLUTION_CHANGED');
        const relative = `${p.source_locale}/${p.source_id}.master-24000.wav`;
        remember(options.supplementalDirectory, relative, MAX_WAV, p.master_sha256);
        file = path.join(options.supplementalDirectory, relative);
      }
      // Whole-ledger bytes are a per-operation audit pin, not immutable media
      // lineage: unrelated locales may legitimately finish later. Retain the
      // selected entry/failed-history and exact alias/source/content pins.
      const {cardinal_manifest_sha256, ...lineage} = p;
      // Supplemental source-manifest pins are stable source lineage; the
      // original cardinal manifest for a trial is only an operation audit pin.
      if (trial) delete lineage.source_manifest_sha256;
      const resolution = {schema_version: 1, owner: OWNER, source_kind: resolved.source_kind, ...lineage,
        listening_verified: false, provider_provenance_authenticated: false, runtime_ready: false};
      proof.push({id: entry.id, resolution});
      return {...asset(locale, entry.id, entry.transcript_sha256, resolved.telephony, file, p.duration_seconds), resolution};
    }
    check(entry && entry.generation_status === 'QA_PASSED', 'CARDINAL_LOCALE_INCOMPLETE');
    const attempt = entry.attempts.at(-1);
    remember(cardinalDirectory, attempt.master.file, MAX_WAV, attempt.master.sha256);
    const bytes = remember(cardinalDirectory, attempt.telephony.file, MAX_WAV, attempt.telephony.sha256);
    check(bytes.length === attempt.telephony.byte_length, 'CARDINAL_SOURCE_HASH_MISMATCH');
    proof.push({id: entry.id, entry_sha256: pack.digest(entry), attempt: attempt.number,
      master_sha256: attempt.master.sha256, telephony_sha256: attempt.telephony.sha256,
      transcript_sha256: entry.transcript_sha256, catalog_record_sha256: entry.catalog_record_sha256,
      context_sha256: entry.context_sha256, request_body_sha256: attempt.request_body_sha256});
    return asset(locale, entry.id, entry.transcript_sha256, bytes, path.join(cardinalDirectory, attempt.telephony.file),
      attempt.telephony.duration_seconds);
  }).sort((a, b) => a.id.localeCompare(b.id, 'en'));
  const rows = assets.map(a => [a.locale, a.canonical_id, a.prompt_id, a.sha256, a.md5, a.bytes.length, a.transcript_sha256]);
  const mapHash = hash(JSON.stringify(rows));
  const generatedAssetSetHash = pack.assetSetHash(manifest, locale);
  const resolvedAssetSetHash = resolvedMode ? pack.digest({schema_version: 1, kind: 'cardinal-resolved-assets-v1',
    locale, intro, prompts: [...proof].sort((a, b) => a.id.localeCompare(b.id, 'en'))}) : null;
  const resolutions = new Map(assets.filter(a => a.resolution).map(a => [a.id,
    {...a.resolution, resolved_asset_set_sha256: resolvedAssetSetHash}]));
  const summary = {schema_version: 1, owner: OWNER, locale, count,
    catalog_sha256: pack.CATALOG_HASH, locale_catalog_sha256: pack.LOCALE_HASHES[locale],
    context_sha256: approval.context_sha256, approval_sha256: approvalSha256,
    locale_approval_sha256: pack.digest(approval), cardinal_manifest_sha256: manifestHash,
    selected_asset_set_sha256: resolvedAssetSetHash || generatedAssetSetHash, map_sha256: mapHash,
    ...(resolvedMode ? {asset_set_kind: 'cardinal-resolved-assets-v1', resolved_asset_set_sha256: resolvedAssetSetHash,
      historical_generated_asset_set_sha256: generatedAssetSetHash, ...(resolver ? {alias_manifest_sha256: options.aliasSha256} : {}),
      selected_generated: assets.filter(a => a.resolution.source_kind === 'generated_cardinal').length,
      selected_reused: assets.filter(a => a.resolution.source_kind === 'reused_supplemental_master').length,
      selected_unresolved: 0, resolved_listening_approval_declared: false} : {}),
    ...(trialResolver ? {model_trial_index_sha256: options.modelTrialIndexSha256,
      selected_model_trials: assets.filter(a => a.resolution.source_kind === 'separate_model_trial').length,
      additional_trial_requests: trialSummary.additional_trial_requests, model_trial_audit: trialSummary,
      staged_candidates_only: true, native_listening_approved: false} : {}),
    resampling_recipe_sha256: pack.digest(pack.RESAMPLING), resampling_provenance_verified: true,
    intro: {...intro, document_id: introAsset.id, source_bytes_verified: true},
    authoring_approval_declared: true, listening_approval_declared: approval.listening.status === 'APPROVED',
    listening_verified: false, provider_provenance_authenticated: false,
    historical_requests_reserved: manifest.requests_reserved, historical_artifact_complete: manifest.artifact_complete,
    preserves_original_request_history: true, creates_only_versioned_ids: true, preserves_210_inventory: true,
    runtime_ready: false, full_position_language_ready: false, five_language_release_ready: false,
    prompts: proof.sort((a, b) => a.id.localeCompare(b.id, 'en'))};
  check(sha(summary.selected_asset_set_sha256), 'CARDINAL_LOCALE_INCOMPLETE');
  function stable() {
    for (const pin of inputPins) check(hash(read(pin.root, pin.relative, pin.maximum)) === pin.sha256, 'CARDINAL_INPUT_CHANGED');
    if (resolver) resolver.summary();
    if (trialResolver) trialResolver.assertUnchanged();
  }
  stable();
  return Object.freeze({
    summary() { stable(); return clone(summary); },
    renderMap() {
      stable();
      const erl = value => Number.isInteger(value) ? String(value) : '<<' + JSON.stringify(value) + '>>';
      if (locale !== LOCALE) {
        const prefix = 'CARDINAL_' + locale.slice(0, 2).toUpperCase();
        const introRow = [locale, introAsset.canonical_id, introAsset.prompt_id, introAsset.sha256,
          introAsset.md5, introAsset.bytes.length, introAsset.transcript_sha256];
        return `%% Generated by import-acdc-gemini-cardinals.cjs --emit-map; immutable ${locale}/${count} staging, not runtime readiness.\n`
          + `-define(${prefix}_MAP_SHA256, ${erl(mapHash)}).\n`
          + `-define(${prefix}_SOURCE_CATALOG_SHA256, ${erl(pack.CATALOG_HASH)}).\n`
          + `-define(${prefix}_CATALOG_SHA256, ${erl(pack.LOCALE_HASHES[locale])}).\n`
          + `-define(${prefix}_CONTEXT_SHA256, ${erl(approval.context_sha256)}).\n`
          + `-define(${prefix}_INTRO, {` + [intro.canonical_id, intro.transcript_sha256, intro.wav_sha256].map(erl).join(',') + '}).\n'
          + `-define(${prefix}_INTRO_ASSET, {` + introRow.map(erl).join(',') + '}).\n'
          + `-define(${prefix}_ASSETS, [\n` + rows.map(row => '    {' + row.map(erl).join(',') + '}').join(',\n') + '\n]).\n';
      }
      return '%% Generated by import-acdc-gemini-cardinals.cjs --emit-map; immutable EN31, not runtime readiness.\n'
        + `-define(CARDINAL_MAP_SHA256, ${erl(mapHash)}).\n`
        + `-define(CARDINAL_CATALOG_SHA256, ${erl(pack.CATALOG_HASH)}).\n`
        + `-define(CARDINAL_EN_CATALOG_SHA256, ${erl(pack.LOCALE_HASHES[LOCALE])}).\n`
        + `-define(CARDINAL_EN_CONTEXT_SHA256, ${erl(approval.context_sha256)}).\n`
        + '-define(CARDINAL_EN_INTRO, {' + [INTRO.canonical_id, INTRO.transcript_sha256, INTRO.wav_sha256].map(erl).join(',') + '}).\n'
        + '-define(CARDINAL_ASSETS, [\n' + rows.map(row => '    {' + row.map(erl).join(',') + '}').join(',\n') + '\n]).\n';
    },
    async install(client, allowWrite = false) {
      check(typeof client === 'function' && typeof allowWrite === 'boolean', 'INVALID_CARDINAL_IMPORT_OPERATION');
      stable();
      const allowed = new Set([...assets.map(a => a.id), introAsset.id]); let requests = 0;
      const writable = new Set([...assets.map(a => a.id), ...(createIntro ? [introAsset.id] : [])]);
      // Two requests per create (PUT/readback), two reads per ten-role batch,
      // and up to six intro requests. Keep the original EN128 bound.
      const requestLimit = Math.max(128, 2 * count + 2 * Math.ceil(count / 10) + 8);
      const boundedClient = async (method, resource, body) => {
        check(++requests <= requestLimit, 'CARDINAL_IMPORT_REQUEST_BOUND');
        if (method === 'POST') {
          check(resource === '_all_docs?include_docs=true&attachments=true' && body && Array.isArray(body.keys)
            && Object.keys(body).length === 1 && body.keys.length > 0 && body.keys.length <= 10
            && new Set(body.keys).size === body.keys.length && body.keys.every(id => allowed.has(id)), 'CARDINAL_IMPORT_SCOPE');
          // Request native conflict metadata too; never accept the winning leaf
          // alone as proof that a versioned identity has no conflicting copies.
          let response = await client(method, resource + '&conflicts=true', body);
          if (Array.isArray(response?.body?.rows)) for (const row of response.body.rows) if (row.doc) {
            check(row.doc._conflicts === undefined || Array.isArray(row.doc._conflicts) && row.doc._conflicts.length === 0,
              'CARDINAL_MEDIA_CONFLICT');
            if (resolutions.has(row.key)) check(row.doc.source_cardinal_resolution
              && pack.digest(row.doc.source_cardinal_resolution) === pack.digest(resolutions.get(row.key)),
            'CARDINAL_RESOLUTION_PROVENANCE_MISMATCH');
            const resolution = resolutions.get(row.key);
            if (resolution?.source_kind === 'separate_model_trial') check(row.doc.source_voice?.provider === resolution.provider
              && row.doc.source_voice.model === modelTrials.MODEL && row.doc.source_voice.voice === modelTrials.VOICE,
            'CARDINAL_MODEL_PROVENANCE_MISMATCH');
          }
          // Only after verifying actual mixed-model metadata, give the unchanged
          // fixed-model attachment verifier a private compatibility copy. Never
          // mutate the database response or persist this normalized view.
          if (trialResolver && Array.isArray(response?.body?.rows)) response = {...response,
            body: {...response.body, rows: response.body.rows.map(row => row.doc
              && resolutions.get(row.key)?.source_kind === 'separate_model_trial'
              ? {...row, doc: {...row.doc, source_voice: {...row.doc.source_voice, model: pack.MODEL}}} : row)}};
          return response;
        }
        check(allowWrite && method === 'PUT' && body && writable.has(body._id)
          && resource === encodeURIComponent(body._id) && body._rev === undefined, 'CARDINAL_IMPORT_SCOPE');
        const resolution = resolutions.get(body._id);
        return client(method, resource, resolution ? {...body, source_cardinal_resolution: clone(resolution),
          ...(resolution.source_kind === 'separate_model_trial'
            ? {source_voice: {...body.source_voice, provider: resolution.provider, model: modelTrials.MODEL, voice: modelTrials.VOICE}} : {})} : body);
      };
      // Historical EN/FR/ES intros remain in the fixed210 import contract.
      // Only the two new versioned introductions can be created here.
      const introResult = await media.install([introAsset], boundedClient, allowWrite && createIntro);
      const result = await media.install(assets, boundedClient, allowWrite);
      await media.install([introAsset], boundedClient, false);
      stable();
      return {...clone(summary), mode: allowWrite ? 'IMPORT' : 'VERIFY_ONLY', created: result.created,
        preserved: result.preserved, verified: result.verified, installed: result.prompts,
        intro_installed_verified: true, database_requests: requests, queue_configuration_changed: false,
        ...(locale === LOCALE ? {} : {intro_created: introResult.created, intro_preserved: introResult.preserved,
          database_request_limit: requestLimit})};
    }
  });
}
function options(argv) {
  check(Array.isArray(argv) && argv.every(a => typeof a === 'string'), 'INVALID_CARDINAL_OPTIONS');
  const out = {}, seen = new Set();
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]; check(!seen.has(arg), 'DUPLICATE_CARDINAL_OPTION'); seen.add(arg);
    if (['--plan', '--import', '--verify-only', '--emit-map'].includes(arg)) {
      check(out.mode === undefined, 'EXACTLY_ONE_CARDINAL_MODE'); out.mode = arg.slice(2);
    } else {
      const key = {'--cardinal-pack': 'cardinalDirectory', '--intro-file': 'introFile',
        '--approval-sha256': 'approvalSha256', '--locale': 'locale', '--supplemental-pack': 'supplementalDirectory',
        '--alias-file': 'aliasFile', '--alias-sha256': 'aliasSha256', '--model-trial-index': 'modelTrialIndex',
        '--model-trial-index-sha256': 'modelTrialIndexSha256'}[arg];
      check(key && i + 1 < argv.length && !argv[i + 1].startsWith('--'), 'INVALID_CARDINAL_OPTIONS');
      out[key] = argv[++i];
    }
  }
  check(out.mode !== undefined && typeof out.locale === 'string' && Object.hasOwn(COUNTS, out.locale), 'CARDINAL_LOCALE_NOT_STAGED');
  const {mode, ...source} = out;
  sourceOptions(source);
  return {mode, source};
}
async function main(argv) {
  const {mode, source} = options(argv), opened = openPlan(source);
  if (mode === 'emit-map') { process.stdout.write(opened.renderMap()); return; }
  const result = mode === 'plan' ? {...opened.summary(), mode: 'PLAN_ONLY_NO_DATABASE_ACCESS'}
    : await opened.install(couchClient(process.env), mode === 'import');
  console.log(JSON.stringify(result, null, 2));
}
module.exports = Object.freeze({OWNER, LOCALE, COUNT, INTRO, COUNTS, INTROS, TRIAL_INDEX_OWNER, ImportError, openPlan, options, main});
if (require.main === module) main(process.argv.slice(2)).catch(() => {
  console.error('Cardinal media staging failed safely; no provider call, legacy overwrite or runtime readiness claim.');
  process.exitCode = 1;
});
