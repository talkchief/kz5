#!/usr/bin/env node
'use strict';

// A media receipt is never a runtime language capability. Validate the exact
// checked-in content-addressed inventory before publishing a nonsecret receipt.
const fs = require('node:fs');
const assert = require('node:assert/strict');
const path = require('node:path');
const IMPORTER_OWNER = 'kazoo5_acdc_gemini_voice_installer';
const LOCALES = ['en-us', 'ar-sa', 'he-il', 'es-es', 'fr-fr'];
const TOP_KEYS = ['schema_version', 'owner', 'created', 'preserved', 'verified',
  'queue_configuration_changed', 'runtime_ready', 'full_position_language_ready', 'prompts'].sort();
const RECORD_KEYS = ['locale', 'canonical_id', 'prompt_id', 'document_id', 'attachment', 'sha256', 'revision'].sort();
const plain = value => value !== null && typeof value === 'object' && !Array.isArray(value)
  && Object.getPrototypeOf(value) === Object.prototype;

function validateReceipt(receipt, plan) {
  assert(Array.isArray(plan) && plan.length === 165 && new Set(plan.map(p => p.id)).size === 165,
    'Incomplete immutable source plan');
  assert(plain(receipt), 'Invalid immutable voice receipt');
  assert.deepEqual(Object.keys(receipt).sort(), TOP_KEYS, 'Unexpected receipt fields');
  assert(receipt.schema_version === 1 && receipt.owner === IMPORTER_OWNER &&
    receipt.verified === 165 && receipt.queue_configuration_changed === false &&
    receipt.runtime_ready === false && receipt.full_position_language_ready === false,
    'Media import must not assert runtime readiness or mutate queue configuration');
  for (const key of ['created', 'preserved']) assert(Number.isSafeInteger(receipt[key]) &&
    receipt[key] >= 0 && receipt[key] <= 165, 'Invalid media receipt count');
  assert(receipt.created + receipt.preserved === 165, 'Inconsistent media receipt totals');
  assert(Array.isArray(receipt.prompts) && receipt.prompts.length === 165, 'Incomplete media receipt');
  const expected = new Map(plan.map(p => [p.id, p])), seen = new Set();
  for (const record of receipt.prompts) {
    assert(plain(record), 'Invalid voice inventory record');
    assert.deepEqual(Object.keys(record).sort(), RECORD_KEYS, 'Unexpected voice inventory fields');
    const source = expected.get(record.document_id);
    assert(source && !seen.has(record.document_id), 'Uncorrelated or duplicate voice inventory');
    seen.add(record.document_id);
    for (const key of ['locale', 'canonical_id', 'prompt_id', 'attachment', 'sha256'])
      assert.equal(record[key], source[key], 'Voice receipt differs from checked-in asset identity');
    assert(typeof record.revision === 'string' && /^[1-9][0-9]*-[a-f0-9]{32}$/.test(record.revision),
      'Invalid installed voice revision');
  }
  assert.deepEqual([...new Set(receipt.prompts.map(p => p.locale))].sort(), [...LOCALES].sort(),
    'Incomplete five-language receipt');
  return true;
}

function main(argv) {
  const options = {};
  for (let i = 0; i < argv.length; i += 2) {
    const key = {'--fixed-pack': 'fixed', '--completion-pack': 'completion'}[argv[i]];
    assert(key && !options[key] && argv[i + 1] && path.isAbsolute(argv[i + 1]),
      'Two explicit absolute asset directories are required');
    options[key] = argv[i + 1];
  }
  assert(options.fixed && options.completion, 'Fixed and completion voice assets are required');
  const bytes = fs.readFileSync(0);
  assert(bytes.length > 0 && bytes.length <= 1024 * 1024, 'Invalid voice receipt size');
  const importer = require('./import-acdc-gemini-voices.cjs');
  validateReceipt(JSON.parse(bytes.toString('utf8')), importer.loadPlan(options.fixed, options.completion, LOCALES));
}
module.exports = {validateReceipt, main};
if (require.main === module) {
  try { main(process.argv.slice(2)); }
  catch (_) { console.error('Immutable Gemini media receipt validation failed; no runtime readiness was published.'); process.exitCode = 1; }
}
