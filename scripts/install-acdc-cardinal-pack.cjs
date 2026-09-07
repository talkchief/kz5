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
// No database call or credential lookup occurs here.
function preflightAll(entries) {
  if (!Array.isArray(entries) || entries.length !== LOCALES.length
      || new Set(entries.map(e => e?.locale)).size !== LOCALES.length
      || entries.some(e => !e || typeof e.locale !== 'string' || !LOCALES.includes(e.locale)
        || typeof e.header !== 'function' || typeof e.plan?.renderMap !== 'function'
        || typeof e.plan?.summary !== 'function' || typeof e.plan?.install !== 'function')) {
    throw new Error('exactly five explicit cardinal locales are required');
  }
  const snapshots = LOCALES.map(locale => {
    const entry = entries.find(e => e.locale === locale), summary = entry.plan.summary();
    const intro = INTROS[locale], count = COUNTS[locale];
    const expectedIds = pack.plan(locale).map(p => p.id).sort();
    if (!summary || typeof summary !== 'object' || summary.locale !== locale || summary.count !== count || summary.catalog_sha256 !== pack.CATALOG_HASH
        || summary.locale_catalog_sha256 !== pack.LOCALE_HASHES[locale]
        || summary.context_sha256 !== pack.digest(pack.contexts[locale]) || summary.approval_sha256 !== APPROVAL
        || !sha(summary.cardinal_manifest_sha256) || !sha(summary.selected_asset_set_sha256) || !sha(summary.map_sha256)
        || summary.historical_artifact_complete !== true || summary.authoring_approval_declared !== true
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
  return snapshots;
}

function stableAll(snapshots) {
  for (const s of snapshots) {
    if (s.header() !== s.map || s.plan.renderMap() !== s.map || pack.digest(s.plan.summary()) !== s.summaryHash) {
      throw new Error('five-locale cardinal source changed');
    }
  }
}

function verifiedReceipt(receipt, source) {
  return receipt && receipt.mode === 'VERIFY_ONLY' && receipt.locale === source.locale
    && receipt.count === source.count && receipt.verified === source.count && receipt.created === 0
    && receipt.intro_installed_verified === true && receipt.map_sha256 === source.map_sha256
    && receipt.catalog_sha256 === source.catalog_sha256 && receipt.locale_catalog_sha256 === source.locale_catalog_sha256
    && receipt.context_sha256 === source.context_sha256 && receipt.approval_sha256 === source.approval_sha256
    && receipt.cardinal_manifest_sha256 === source.cardinal_manifest_sha256
    && receipt.selected_asset_set_sha256 === source.selected_asset_set_sha256
    && receipt.intro && pack.digest(receipt.intro) === pack.digest(source.intro)
    && receipt.runtime_ready === false && receipt.full_position_language_ready === false
    && receipt.five_language_release_ready === false && receipt.listening_verified === false;
}

async function installAll(mode, entries, client) {
  if (!MODES.includes(mode)) throw new Error('invalid mode');
  const snapshots = preflightAll(entries);
  stableAll(snapshots);
  const common = {schema_version: 1, owner: 'kazoo5-acdc-cardinal-installer', scope: 'all-locales',
    count: 584, catalog_sha256: pack.CATALOG_HASH, approval_sha256: APPROVAL,
    cardinal_manifest_sha256: snapshots[0].summary.cardinal_manifest_sha256,
    source_complete: true, preserves_210_inventory: true,
    runtime_ready: false, full_position_language_ready: false, five_language_release_ready: false,
    listening_verified: false, queue_configuration_changed: false};
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
    if (!verifiedReceipt(receipt, s.summary)) throw new Error('invalid five-locale cardinal receipt');
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

function releasePlans(open = openPlan, readHeader = checkedHeader) {
  return LOCALES.map(locale => ({locale, plan: open(source(locale)),
    header: () => readHeader(locale === 'en-us'
      ? path.join(__dirname, '../applications/acdc/src/acdc_cardinal_map.hrl')
      : path.join(__dirname, '../applications/acdc/src/cardinal_maps', `acdc_cardinal_${locale}.hrl`),
    locale === 'en-us' ? 65536 : 256 * 1024)}));
}

function options(args) {
  if (!Array.isArray(args) || !MODES.includes(args[0])
      || !(args.length === 1 || args.length === 2 && args[1] === '--all-locales')) {
    throw new Error('one explicit mode and optional --all-locales are required');
  }
  return {mode: args[0], allLocales: args.length === 2};
}

async function main(args) {
  const {mode, allLocales} = options(args);
  let receipt;
  if (allLocales) {
    const entries = releasePlans();
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
