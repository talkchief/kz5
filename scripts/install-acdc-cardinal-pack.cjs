#!/usr/bin/env node
'use strict';
// Installer adapter for checked-in audio only. No provider key or synthesis.
const fs = require('node:fs');
const path = require('node:path');
const {openPlan, COUNTS, INTROS} = require('./import-acdc-gemini-cardinals.cjs');
const pack = require('./acdc-cardinal-pack.cjs');
const {couchClient} = require('./import-acdc-language-packs.cjs');
// Five-locale authoring declaration; the EN staging scope below is unchanged.
// New HE/AR approvals bind separately verified intros, not listening readiness.
const APPROVAL = '452b815a65f726e4d221b2585f61162fae0a1c43d6fb1370a0f27bb3a37b8ea5';
const LOCALES = Object.freeze(['en-us', 'he-il', 'fr-fr', 'es-es', 'ar-sa']);
const MODES = Object.freeze(['--plan', '--import', '--verify-only']);
const sameFile = (a, b) => ['dev', 'ino', 'size', 'mode', 'nlink', 'mtimeMs', 'ctimeMs'].every(k => a[k] === b[k]);
const sha = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const absolute = value => typeof value === 'string' && path.isAbsolute(value) && path.resolve(value) === value;

function resolutionOptions(value) {
  const fields = ['modelTrialIndex', 'modelTrialIndexSha256'];
  const aliases = ['supplementalDirectory', 'aliasFile', 'aliasSha256'];
  if (!value || Object.getPrototypeOf(value) !== Object.prototype) throw new Error('invalid cardinal resolution options');
  const keys = Object.keys(value);
  if (keys.length === 0) return {};
  const hasAliases = aliases.some(k => Object.hasOwn(value, k));
  const expected = [...fields, ...(hasAliases ? aliases : [])];
  if (keys.sort().join(',') !== expected.sort().join(',') || !absolute(value.modelTrialIndex)
      || !sha(value.modelTrialIndexSha256) || hasAliases && (!absolute(value.supplementalDirectory)
        || !absolute(value.aliasFile) || !sha(value.aliasSha256))) throw new Error('explicit pinned cardinal resolution options required');
  return {...value};
}

// The mixed adapter keeps EN's deployed generated-only document shape. Every
// other locale must supply a complete resolved inventory, never a historical
// completion declaration manufactured from trial candidates or reused words.
function completeMixed(summary, locale) {
  if (!Array.isArray(summary.prompts) || typeof summary.historical_artifact_complete !== 'boolean') return false;
  const prompts = [...summary.prompts].sort((a, b) => a.id.localeCompare(b.id, 'en'));
  if (locale === 'en-us') {
    return summary.model_trial_index_sha256 === undefined && summary.asset_set_kind === undefined
      && prompts.every(p => sha(p.master_sha256) && sha(p.telephony_sha256) && sha(p.entry_sha256)
        && Number.isInteger(p.attempt) && p.attempt >= 1 && p.attempt <= pack.HARD_MAX_ATTEMPTS)
      && summary.selected_asset_set_sha256 === pack.digest(prompts.map(p =>
        ({id: p.id, master: p.master_sha256, telephony: p.telephony_sha256})));
  }
  if (!sha(summary.model_trial_index_sha256) || summary.asset_set_kind !== 'cardinal-resolved-assets-v1'
      || summary.staged_candidates_only !== true || summary.native_listening_approved !== false
      || summary.resolved_listening_approval_declared !== false || summary.selected_unresolved !== 0
      || summary.resolved_asset_set_sha256 !== summary.selected_asset_set_sha256
      || !summary.model_trial_audit || summary.model_trial_audit.source_manifest_sha256 !== summary.cardinal_manifest_sha256
      || summary.model_trial_audit.approvals_sha256 !== APPROVAL || summary.model_trial_audit.runtime_ready !== false
      || summary.model_trial_audit.native_listening_approved !== false
      || !Number.isInteger(summary.additional_trial_requests) || summary.additional_trial_requests < 1
      || summary.additional_trial_requests !== summary.model_trial_audit.additional_trial_requests
      || locale !== 'es-es' && summary.alias_manifest_sha256 !== undefined) return false;
  const counts = {generated_cardinal: 0, separate_model_trial: 0, reused_supplemental_master: 0};
  const wanted = new Map(pack.plan(locale).map(p => [p.id, p]));
  for (const p of prompts) {
    const r = p.resolution, role = wanted.get(p.id);
    if (!role || !r || !Object.hasOwn(counts, r.source_kind) || r.provider !== 'google-gemini' || r.voice !== 'Sulafat'
        || r.model !== (r.source_kind === 'separate_model_trial' ? 'gemini-3.1-flash-tts-preview' : pack.MODEL)
        || r.transcript_sha256 !== role.transcript_sha256 || r.context_sha256 !== role.context_sha256
        || r.catalog_record_sha256 !== role.catalog_record_sha256 || !sha(r.master_sha256) || !sha(r.telephony_sha256)
        || r.resampling_recipe_sha256 !== pack.digest(pack.RESAMPLING) || r.runtime_ready !== false
        || r.listening_verified !== false || r.provider_provenance_authenticated !== false) return false;
    if (r.source_kind === 'reused_supplemental_master' && (locale !== 'es-es' || !sha(summary.alias_manifest_sha256)
        || r.alias_manifest_sha256 !== summary.alias_manifest_sha256 || r.source_locale !== 'es-es'
        || !['acdc-number-4', 'acdc-number-9'].includes(r.source_id))) return false;
    counts[r.source_kind]++;
  }
  return summary.selected_generated === counts.generated_cardinal && summary.selected_model_trials === counts.separate_model_trial
    && summary.selected_reused === counts.reused_supplemental_master
    && summary.resolved_asset_set_sha256 === pack.digest({schema_version: 1, kind: 'cardinal-resolved-assets-v1',
      locale, intro: INTROS[locale], prompts});
}

function checkedHeader(filename, maximum = 65536) {
  const parent = path.dirname(filename), before = fs.lstatSync(filename);
  const parentStat = fs.lstatSync(parent);
  if (!path.isAbsolute(filename) || path.resolve(filename) !== filename || fs.realpathSync(parent) !== parent
      || !parentStat.isDirectory() || (parentStat.mode & 0o022)) {
    throw new Error('invalid checked-in cardinal map path');
  }
  const fd = fs.openSync(filename, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
  try {
    const stat = fs.fstatSync(fd);
    if (!stat.isFile() || stat.nlink !== 1 || (stat.mode & 0o022) || stat.size <= 0 || stat.size > maximum
        || !sameFile(before, stat)) {
      throw new Error('invalid checked-in cardinal map');
    }
    const bytes = Buffer.alloc(stat.size + 1); let size = 0, count;
    while (size < bytes.length && (count = fs.readSync(fd, bytes, size, bytes.length - size, null)) > 0) size += count;
    if (size !== stat.size || !sameFile(stat, fs.fstatSync(fd)) || !sameFile(stat, fs.lstatSync(filename))
        || fs.realpathSync(parent) !== parent) throw new Error('cardinal source map changed');
    return bytes.subarray(0, size).toString('utf8');
  } finally { fs.closeSync(fd); }
}

async function install(mode, plan, client, header) {
  if (!['--plan', '--import', '--verify-only'].includes(mode)) throw new Error('invalid mode');
  const expected = plan.renderMap();
  if (header() !== expected) throw new Error('cardinal source map mismatch');
  if (mode === '--plan') return {...plan.summary(), mode: 'PLAN_ONLY_NO_DATABASE_ACCESS'};
  if (mode === '--import') await plan.install(client, true);
  // A separate complete fresh byte readback is required after any writes.
  const receipt = await plan.install(client, false);
  if (header() !== expected) throw new Error('cardinal source map changed');
  if (receipt.mode !== 'VERIFY_ONLY' || receipt.count !== 31 || receipt.verified !== 31 ||
      receipt.created !== 0 || receipt.intro_installed_verified !== true ||
      receipt.map_sha256 !== plan.summary().map_sha256) throw new Error('invalid cardinal receipt');
  return receipt;
}

// Source-only prerequisite: all five plans must represent the same completed
// original ledger and approved release, with exact independently stored maps.
// Explicit mixed mode requires complete selected assets, not a falsely completed
// original generation ledger. Original EN documents remain generated-only.
// No database call or credential lookup occurs here.
function preflightAll(entries) {
  if (!Array.isArray(entries) || entries.length !== LOCALES.length
      || new Set(entries.map(e => e?.locale)).size !== LOCALES.length
      || entries.some(e => !e || typeof e.locale !== 'string' || !LOCALES.includes(e.locale)
        || typeof e.header !== 'function' || typeof e.plan?.renderMap !== 'function'
        || typeof e.plan?.summary !== 'function' || typeof e.plan?.install !== 'function')) {
    throw new Error('exactly five explicit cardinal locales are required');
  }
  const summaries = new Map(entries.map(e => [e.locale, e.plan.summary()]));
  const mixed = [...summaries.values()].some(s => s && Object.hasOwn(s, 'model_trial_index_sha256'));
  const snapshots = LOCALES.map(locale => {
    const entry = entries.find(e => e.locale === locale), summary = summaries.get(locale);
    const intro = INTROS[locale], count = COUNTS[locale];
    const expectedIds = pack.plan(locale).map(p => p.id).sort();
    if (!summary || typeof summary !== 'object' || summary.locale !== locale || summary.count !== count || summary.catalog_sha256 !== pack.CATALOG_HASH
        || summary.locale_catalog_sha256 !== pack.LOCALE_HASHES[locale]
        || summary.context_sha256 !== pack.digest(pack.contexts[locale]) || summary.approval_sha256 !== APPROVAL
        || !sha(summary.cardinal_manifest_sha256) || !sha(summary.selected_asset_set_sha256) || !sha(summary.map_sha256)
        || (mixed ? !completeMixed(summary, locale) : summary.historical_artifact_complete !== true)
        || summary.authoring_approval_declared !== true
        || summary.resampling_provenance_verified !== true || summary.preserves_original_request_history !== true
        || summary.preserves_210_inventory !== true || summary.creates_only_versioned_ids !== true
        || summary.runtime_ready !== false || summary.full_position_language_ready !== false
        || summary.five_language_release_ready !== false || summary.listening_verified !== false
        || !summary.intro || Object.keys(intro).some(k => summary.intro[k] !== intro[k])
        || summary.intro.source_bytes_verified !== true
        || summary.intro.document_id !== `${locale}/${intro.canonical_id}-gemini-sulafat-${intro.wav_sha256.slice(0, 16)}`
        || !Array.isArray(summary.prompts) || summary.prompts.length !== count
        || pack.digest(summary.prompts.map(p => p.id).sort()) !== pack.digest(expectedIds)) {
      throw new Error('incomplete or mismatched five-locale cardinal source');
    }
    const map = entry.plan.renderMap();
    if (typeof map !== 'string' || map.length === 0 || entry.header() !== map) throw new Error('cardinal source map mismatch');
    return {...entry, summary, summaryHash: pack.digest(summary), map};
  });
  if (snapshots.some(s => s.summary.cardinal_manifest_sha256 !== snapshots[0].summary.cardinal_manifest_sha256)) {
    throw new Error('five-locale cardinal ledger mismatch');
  }
  if (mixed) {
    const indexed = snapshots.filter(s => s.locale !== 'en-us'), first = indexed[0].summary;
    if (snapshots.some(s => s.summary.historical_artifact_complete !== first.historical_artifact_complete)
        || indexed.some(s => s.summary.model_trial_index_sha256 !== first.model_trial_index_sha256
          || pack.digest(s.summary.model_trial_audit) !== pack.digest(first.model_trial_audit))) {
      throw new Error('five-locale cardinal resolution index mismatch');
    }
  }
  return snapshots;
}

function stableAll(snapshots) {
  for (const s of snapshots) {
    if (s.header() !== s.map || s.plan.renderMap() !== s.map || pack.digest(s.plan.summary()) !== s.summaryHash) {
      throw new Error('five-locale cardinal source changed');
    }
  }
}

function verifiedReceipt(receipt, source, mixed = false) {
  return receipt && receipt.mode === 'VERIFY_ONLY' && receipt.locale === source.locale
    && receipt.count === source.count && receipt.verified === source.count && receipt.created === 0
    && receipt.intro_installed_verified === true && receipt.map_sha256 === source.map_sha256
    && receipt.catalog_sha256 === source.catalog_sha256 && receipt.locale_catalog_sha256 === source.locale_catalog_sha256
    && receipt.context_sha256 === source.context_sha256 && receipt.approval_sha256 === source.approval_sha256
    && receipt.cardinal_manifest_sha256 === source.cardinal_manifest_sha256
    && receipt.selected_asset_set_sha256 === source.selected_asset_set_sha256
    && receipt.intro && pack.digest(receipt.intro) === pack.digest(source.intro)
    && receipt.runtime_ready === false && receipt.full_position_language_ready === false
    && receipt.five_language_release_ready === false && receipt.listening_verified === false
    && (!mixed || Object.keys(source).every(k =>
      Object.hasOwn(receipt, k) && pack.digest(receipt[k]) === pack.digest(source[k])));
}

async function installAll(mode, entries, client) {
  if (!MODES.includes(mode)) throw new Error('invalid mode');
  const snapshots = preflightAll(entries);
  stableAll(snapshots);
  const indexed = snapshots.find(s => s.summary.model_trial_index_sha256 !== undefined);
  const common = {schema_version: 1, owner: 'kazoo5-acdc-cardinal-installer', scope: 'all-locales',
    count: 584, catalog_sha256: pack.CATALOG_HASH, approval_sha256: APPROVAL,
    cardinal_manifest_sha256: snapshots[0].summary.cardinal_manifest_sha256,
    source_complete: true, preserves_210_inventory: true,
    runtime_ready: false, full_position_language_ready: false, five_language_release_ready: false,
    listening_verified: false, queue_configuration_changed: false};
  if (indexed) Object.assign(common, {resolution_mode: 'indexed-model-trials-v1', resolution_complete: true,
    historical_artifact_complete: indexed.summary.historical_artifact_complete,
    model_trial_index_sha256: indexed.summary.model_trial_index_sha256,
    additional_trial_requests: indexed.summary.additional_trial_requests,
    selected_generated: 31 + snapshots.filter(s => s.locale !== 'en-us').reduce((n, s) => n + s.summary.selected_generated, 0),
    selected_model_trials: snapshots.filter(s => s.locale !== 'en-us').reduce((n, s) => n + s.summary.selected_model_trials, 0),
    selected_reused: snapshots.filter(s => s.locale !== 'en-us').reduce((n, s) => n + s.summary.selected_reused, 0),
    staged_candidates_only: true, native_listening_approved: false});
  if (mode === '--plan') return {...common, mode: 'PLAN_ONLY_NO_DATABASE_ACCESS',
    database_verified: false, locales: snapshots.map(s => s.summary)};
  if (typeof client !== 'function') throw new Error('invalid cardinal database client');
  let writePhase = mode === '--import';
  const pinnedClient = async (method, resource, body) => {
    if (!(method === 'POST' && resource === '_all_docs?include_docs=true&attachments=true&conflicts=true'
          || method === 'PUT' && writePhase)) throw new Error('invalid cardinal database operation');
    // Map reads are cheap enough to repeat before each create. Full source/WAV
    // pins are rechecked at locale boundaries by this adapter and each plan.
    if (method === 'PUT') for (const s of snapshots) {
      if (s.header() !== s.map) throw new Error('five-locale cardinal source changed');
    }
    return client(method, resource, body);
  };
  if (mode === '--import') for (const s of snapshots) {
    stableAll(snapshots);
    await s.plan.install(pinnedClient, true);
  }
  // Fresh readback of ALL locales starts only after the last requested write.
  writePhase = false;
  const receipts = [];
  for (const s of snapshots) {
    stableAll(snapshots);
    const receipt = await s.plan.install(pinnedClient, false);
    if (!verifiedReceipt(receipt, s.summary, Boolean(indexed))) throw new Error('invalid five-locale cardinal receipt');
    receipts.push(receipt);
  }
  stableAll(snapshots);
  return {...common, mode: mode === '--import' ? 'IMPORT_AND_VERIFY' : 'VERIFY_ONLY',
    database_verified: true, verified: 584, locales: receipts};
}

function source(locale) {
  return {locale,
    cardinalDirectory: path.join(__dirname, 'assets/acdc-gemini-cardinals-20260907'),
    introFile: ['he-il', 'ar-sa'].includes(locale)
      ? path.join(__dirname, 'assets/acdc-gemini-cardinal-intros-20260907', locale,
        'acdc-cardinal-intro-v1-current-position-number.attempt-1.telephony-8000.wav')
      : path.join(__dirname, 'assets/acdc-gemini-fixed-20260905', locale,
        'acdc-queue-your-current-position-is.telephony-8000.wav'),
    approvalSha256: APPROVAL};
}

function releasePlans(open = openPlan, readHeader = checkedHeader, selectedResolution = {}) {
  const resolution = resolutionOptions(selectedResolution);
  const {supplementalDirectory, aliasFile, aliasSha256, ...trials} = resolution;
  return LOCALES.map(locale => ({locale, plan: open({...source(locale),
    ...(locale === 'en-us' ? {} : locale === 'es-es' ? resolution : trials)}),
    header: () => readHeader(locale === 'en-us'
      ? path.join(__dirname, '../applications/acdc/src/acdc_cardinal_map.hrl')
      : path.join(__dirname, '../applications/acdc/src/cardinal_maps', `acdc_cardinal_${locale}.hrl`),
    locale === 'en-us' ? 65536 : 256 * 1024)}));
}

function options(args) {
  if (!Array.isArray(args) || !args.every(a => typeof a === 'string') || !MODES.includes(args[0])) {
    throw new Error('one explicit mode and optional --all-locales are required');
  }
  const resolution = {}, seen = new Set(); let allLocales = false;
  const flags = {'--model-trial-index': 'modelTrialIndex', '--model-trial-index-sha256': 'modelTrialIndexSha256',
    '--supplemental-pack': 'supplementalDirectory', '--alias-file': 'aliasFile', '--alias-sha256': 'aliasSha256'};
  for (let i = 1; i < args.length; i++) {
    const flag = args[i];
    if (seen.has(flag)) throw new Error('duplicate cardinal adapter option');
    seen.add(flag);
    if (flag === '--all-locales') allLocales = true;
    else {
      if (!Object.hasOwn(flags, flag) || !args[i + 1] || args[i + 1].startsWith('--')) throw new Error('invalid cardinal adapter option');
      resolution[flags[flag]] = args[++i];
    }
  }
  const selected = resolutionOptions(resolution);
  if (Object.keys(selected).length && !allLocales) throw new Error('mixed cardinal resolution requires all-locales');
  return {mode: args[0], allLocales, ...(Object.keys(selected).length ? {resolution: selected} : {})};
}

async function main(args) {
  const {mode, allLocales, resolution = {}} = options(args);
  let receipt;
  if (allLocales) {
    const entries = releasePlans(openPlan, checkedHeader, resolution);
    // Reject missing/incomplete release material before even constructing the
    // database client. The adapter never stages a partial locale selection.
    preflightAll(entries);
    receipt = await installAll(mode, entries, mode === '--plan' ? null : couchClient(process.env));
  } else {
    const plan = openPlan(source('en-us'));
    const client = mode === '--plan' ? null : couchClient(process.env);
    const header = () => checkedHeader(path.join(__dirname, '../applications/acdc/src/acdc_cardinal_map.hrl'));
    receipt = await install(mode, plan, client, header);
  }
  process.stdout.write(JSON.stringify(receipt, null, 2) + '\n');
}
module.exports = {install, installAll, preflightAll, releasePlans, options, checkedHeader, APPROVAL, LOCALES, main};
if (require.main === module) main(process.argv.slice(2)).catch(() => {
  console.error('Checked-in cardinal installation failed safely; no runtime readiness claim.');
  process.exitCode = 1;
});
