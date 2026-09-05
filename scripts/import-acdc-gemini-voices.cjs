#!/usr/bin/env node
'use strict';

// Create-only, content-addressed system prompts. Never overwrites legacy media,
// changes queue/account configuration, or publishes language readiness.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const assert = require('node:assert/strict');
const fixed = require('./generate-acdc-gemini-fixed-pack.cjs');
const extra = require('./generate-acdc-gemini-completion-pack.cjs');
const {LOCALES, MODEL, VOICE} = require('./generate-acdc-gemini-samples.cjs');
const {couchClient} = require('./import-acdc-language-packs.cjs');
const OWNER = 'kazoo5_acdc_gemini_voice_installer';
const hash = (bytes, algorithm = 'sha256', encoding = 'hex') => crypto.createHash(algorithm).update(bytes).digest(encoding);
const identity = p => `${p.locale}/${p.id}`;
const revision = value => typeof value === 'string' && /^[1-9][0-9]*-[a-f0-9]{32}$/.test(value);

function loadPlan(fixedDirectory, completionDirectory, locales) {
  assert(Array.isArray(locales) && locales.length > 0 && new Set(locales).size === locales.length && locales.every(l => LOCALES.includes(l)), 'Invalid voice locale selection');
  const original = fixed.readManifest(fixedDirectory);
  const completed = completionDirectory ? extra.readManifest(completionDirectory) : {prompts: []};
  const wanted = [...fixed.FIXED, ...extra.DIGITS].filter(p => locales.includes(p.locale));
  return wanted.map(expected => {
    let entry = original.prompts.find(p => identity(p) === identity(expected) && p.generation_status === 'GENERATED_QA_PASSED');
    let directory = fixedDirectory;
    if (entry) fixed.verifyEntry(directory, entry);
    else {
      directory = completionDirectory;
      entry = completed.prompts.find(p => identity(p) === identity(expected) && p.generation_status === 'GENERATED_QA_PASSED');
      assert(directory && entry, 'Selected locale has incomplete fixed or callback-digit audio');
      extra.verifyEntry(directory, entry);
    }
    const bytes = fixed.regularBytes(path.join(directory, entry.telephony.file));
    const sha256 = hash(bytes), promptId = `${entry.id}-gemini-sulafat-${sha256.slice(0, 16)}`;
    assert(/^[A-Za-z0-9_-]+$/.test(promptId) && promptId.length <= 128, 'Invalid versioned prompt identity');
    return {locale: entry.locale, canonical_id: entry.id, prompt_id: promptId, id: `${entry.locale}/${promptId}`,
      attachment: `${promptId}.wav`, sha256, md5: 'md5-' + hash(bytes, 'md5', 'base64'), bytes,
      source_file: path.relative(path.join(__dirname, '..'), path.join(directory, entry.telephony.file)),
      transcript_sha256: entry.transcript_sha256, duration_seconds: entry.telephony.duration_seconds};
  });
}
function document(asset, timestamp = Date.now()) {
  const now = Math.floor(timestamp / 1000) + 62167219200;
  return {_id: asset.id, name: asset.id, prompt_id: asset.prompt_id, language: asset.locale,
    pvt_type: 'media', pvt_account_db: 'system_media', pvt_vsn: '1', pvt_created: now, pvt_modified: now,
    source_type: OWNER, content_type: 'audio/wav', content_length: asset.bytes.length, streamable: true,
    source_voice: {provider: 'google-gemini', model: MODEL, voice: VOICE, canonical_prompt_id: asset.canonical_id,
      sha256: asset.sha256, transcript_sha256: asset.transcript_sha256, source_file: asset.source_file},
    _attachments: {[asset.attachment]: {content_type: 'audio/wav', data: asset.bytes.toString('base64')}}};
}
function verifyDocument(asset, doc) {
  assert(doc && doc._id === asset.id && revision(doc._rev) && !doc._deleted && !doc.pvt_deleted &&
    doc.pvt_type === 'media' && doc.pvt_account_db === 'system_media' && doc.source_type === OWNER &&
    doc.prompt_id === asset.prompt_id && doc.language === asset.locale && doc.content_type === 'audio/wav' &&
    doc.content_length === asset.bytes.length && doc.streamable === true, 'Existing versioned identity is not owned media');
  assert(doc.source_voice?.provider === 'google-gemini' && doc.source_voice.model === MODEL && doc.source_voice.voice === VOICE &&
    doc.source_voice.canonical_prompt_id === asset.canonical_id && doc.source_voice.sha256 === asset.sha256 &&
    doc.source_voice.transcript_sha256 === asset.transcript_sha256, 'Installed voice provenance differs');
  assert(doc._attachments && Object.keys(doc._attachments).length === 1 && doc._attachments[asset.attachment], 'Unexpected installed voice attachment inventory');
  const attachment = doc._attachments[asset.attachment];
  assert(attachment.content_type === 'audio/wav' && attachment.digest === asset.md5 &&
    typeof attachment.data === 'string' && /^[A-Za-z0-9+/]*={0,2}$/.test(attachment.data), 'Invalid downloaded voice attachment');
  const bytes = Buffer.from(attachment.data, 'base64');
  assert(bytes.toString('base64') === attachment.data && bytes.length === asset.bytes.length && hash(bytes) === asset.sha256,
    'Downloaded voice audio failed exact length/hash verification');
  return doc._rev;
}
async function rows(client, assets) {
  const result = await client('POST', '_all_docs?include_docs=true&attachments=true', {keys: assets.map(a => a.id)});
  assert(result.status === 200 && Array.isArray(result.body?.rows) && result.body.rows.length === assets.length, 'Incomplete voice inventory response');
  const map = new Map(), wanted = new Set(assets.map(a => a.id));
  for (const row of result.body.rows) {
    assert(wanted.has(row.key) && !map.has(row.key), 'Uncorrelated voice inventory row');
    if (row.error !== undefined) assert(row.error === 'not_found' && row.doc === undefined && row.value === undefined, 'Unverified missing voice document');
    else assert(row.doc && row.id === row.key && row.doc._id === row.key, 'Voice document identity mismatch');
    map.set(row.key, row.error === 'not_found' ? null : row.doc);
  }
  return map;
}
async function install(plan, client, allowWrite = false) {
  assert(plan.length > 0 && plan.length <= 165 && new Set(plan.map(a => a.id)).size === plan.length, 'Invalid bounded voice import plan');
  let created = 0, preserved = 0;
  const records = [];
  for (let offset = 0; offset < plan.length; offset += 10) {
    const batch = plan.slice(offset, offset + 10), existing = await rows(client, batch);
    for (const asset of batch) {
      let current = existing.get(asset.id);
      if (current) { verifyDocument(asset, current); preserved++; }
      else {
        assert(allowWrite, 'Required versioned voice is not installed');
        const result = await client('PUT', encodeURIComponent(asset.id), document(asset));
        assert([201, 202, 409].includes(result.status), 'Versioned voice create failed');
        if (result.status !== 409) {
          assert(result.body?.ok === true && result.body.id === asset.id && revision(result.body.rev), 'Uncorrelated voice create acknowledgment');
          created++;
        } else preserved++;
        // A conflict is never followed by an overwrite or revision-based retry.
        current = (await rows(client, [asset])).get(asset.id);
        verifyDocument(asset, current);
      }
      records.push({locale: asset.locale, canonical_id: asset.canonical_id, prompt_id: asset.prompt_id,
        document_id: asset.id, attachment: asset.attachment, sha256: asset.sha256, revision: current._rev});
    }
  }
  // Re-read every target after all writes; earlier documents may have changed.
  for (let offset = 0; offset < plan.length; offset += 10) {
    const batch = plan.slice(offset, offset + 10), verified = await rows(client, batch);
    for (const asset of batch) {
      const currentRevision = verifyDocument(asset, verified.get(asset.id));
      records.find(record => record.document_id === asset.id).revision = currentRevision;
    }
  }
  return {schema_version: 1, owner: OWNER, created, preserved, verified: plan.length,
    queue_configuration_changed: false, runtime_ready: false, full_position_language_ready: false,
    prompts: records};
}
function publicPlan(plan) {
  return {mode: 'PLAN_ONLY_NO_DATABASE_ACCESS', count: plan.length, creates_only_versioned_ids: true,
    preserves_legacy_and_custom_media: true, runtime_ready: false,
    prompts: plan.map(({bytes, md5, ...asset}) => asset)};
}
async function main(argv) {
  const o = {locales: ['en-us'], mode: 'plan'};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (['--plan', '--import', '--verify-only'].includes(arg)) o.mode = arg.slice(2);
    else if (arg === '--all-locales') o.locales = LOCALES;
    else {
      const key = {'--fixed-pack': 'fixedDirectory', '--completion-pack': 'completionDirectory', '--locale': 'locale'}[arg];
      assert(key && i + 1 < argv.length && !argv[i + 1].startsWith('--'), 'Unknown or incomplete voice import option'); o[key] = argv[++i];
    }
  }
  if (o.locale) o.locales = [o.locale];
  assert(o.fixedDirectory && path.isAbsolute(o.fixedDirectory), 'An absolute fixed pack directory is required');
  if (o.completionDirectory) assert(path.isAbsolute(o.completionDirectory), 'An absolute completion pack directory is required');
  const plan = loadPlan(o.fixedDirectory, o.completionDirectory, o.locales);
  console.log(JSON.stringify(o.mode === 'plan' ? publicPlan(plan) : await install(plan, couchClient(process.env), o.mode === 'import'), null, 2));
}
module.exports = {OWNER, loadPlan, document, verifyDocument, install, publicPlan, main};
if (require.main === module) main(process.argv.slice(2)).catch(() => {
  console.error('Gemini voice import/verification failed safely; no legacy recording or queue configuration was overwritten.'); process.exitCode = 1;
});
