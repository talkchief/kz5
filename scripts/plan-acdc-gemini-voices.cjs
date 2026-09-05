#!/usr/bin/env node
'use strict';

// Offline source/mapping proposal only. Import verification and queue-revision
// comparison are mandatory separate steps; this tool never changes live state.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const assert = require('node:assert/strict');
const importer = require('./import-acdc-gemini-voices.cjs');
const {LOCALES, MODEL, VOICE} = require('./generate-acdc-gemini-samples.cjs');
const OWNER = 'kazoo5-acdc-gemini-voice-map';
const BUNDLED_FIXED = path.join(__dirname, 'assets/acdc-gemini-fixed-20260905');
const BUNDLED_COMPLETION = path.join(__dirname, 'assets/acdc-gemini-completion-20260905');
const CALLBACK_KEYS = ['offer', 'menu', 'number_readback', 'confirmation', 'success', 'returned_confirmation'];
const ANNOUNCEMENT_KEYS = ['you_are_at_position', 'in_the_queue', 'increase_in_call_volume', 'the_estimated_wait_time_is'];
const TIME_KEYS = ['less_than_1_minute', 'about_5_minutes', 'about_10_minutes', 'about_15_minutes',
  'about_30_minutes', 'about_45_minutes', 'about_1_hour', 'at_least_1_hour'];
const plain = value => value !== null && typeof value === 'object' && !Array.isArray(value)
  && Object.getPrototypeOf(value) === Object.prototype;
const sha = value => crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
function mapping(plan) {
  assert(Array.isArray(plan) && plan.length > 0 && plan.length <= 165, 'Invalid bounded source plan');
  const languages = {};
  for (const locale of LOCALES) {
    const assets = plan.filter(a => a.locale === locale);
    if (!assets.length) continue;
    const prompts = Object.fromEntries(assets.map(a => [a.canonical_id, a.prompt_id]));
    assert(Object.keys(prompts).length === assets.length, 'Duplicate canonical voice identity');
    const fixed = assets.filter(a => !a.canonical_id.startsWith('acdc-number-'));
    const digits = assets.filter(a => a.canonical_id.startsWith('acdc-number-'));
    assert(fixed.length === 29 && fixed.every(a => /^[a-f0-9]{64}$/.test(a.sha256)), 'Incomplete fixed source pack');
    const prerecorded = ['ar-sa', 'he-il'].includes(locale);
    assert(digits.length === (prerecorded ? 10 : 0) && (!prerecorded ||
      Array.from({length: 10}, (_, n) => 'acdc-number-' + n).every(id => prompts[id])), 'Incomplete callback digit source pack');
    languages[locale] = {
      source_audio_verified: true, fixed_prompt_count: 29, native_speaker_review: false,
      callback: {fixed_audio_complete: true, telephone_digits_source: prerecorded ? 'gemini_prerecorded_0_to_9' : 'external_native_say',
        telephone_digit_asset_count: digits.length, telephone_digit_mapping: Object.fromEntries(digits.map(a => [a.canonical_id.slice(12), a.prompt_id])),
        installed_verified: false, runtime_ready: false},
      position: {source_full_range_complete: false, generated_full_number_count: 0,
        supported_position_range: null, runtime_ready: false},
      wait_time: {fixed_audio_complete: true, runtime_ready: false},
      full_language_ready: false,
      source_audio_sha256: sha(assets.map(a => [a.canonical_id, a.sha256]).sort()),
      prompts
    };
  }
  return {schema_version: 1, owner: OWNER, provider: 'google-gemini', model: MODEL, voice: VOICE,
    mode: 'OFFLINE_SOURCE_MAPPING_NOT_RUNTIME_CAPABILITIES', installed_verified: false, runtime_ready: false,
    queue_configuration_changed: false, languages};
}
function pathValue(object, keys) {
  let current = object;
  for (const key of keys) {
    if (!plain(current) || !Object.hasOwn(current, key)) return {present: false};
    current = current[key];
  }
  return {present: true, value: current};
}
function englishQueueProposal(manifest, queue) {
  assert(manifest.owner === OWNER && manifest.languages['en-us'] && plain(queue), 'English source mapping and queue object required');
  for (const key of ['callback', 'announcements']) {
    assert(queue[key] === undefined || plain(queue[key]), 'Invalid queue configuration object');
    assert(queue[key]?.media === undefined || plain(queue[key].media), 'Invalid queue media object');
  }
  const language = queue.announcements?.language;
  const isEnglish = language === undefined || (typeof language === 'string' && language.toLowerCase().replaceAll('_', '-') === 'en-us');
  const prompts = manifest.languages['en-us'].prompts;
  const rawEntry = queue.callback?.entry_key;
  const entry = rawEntry === undefined ? '6' : rawEntry;
  assert(typeof entry === 'string' && /^[0-9]$/.test(entry), 'Callback entry must be one configured digit');
  const alternate = queue.callback?.allow_alternate_number;
  assert(alternate === undefined || typeof alternate === 'boolean', 'Invalid callback alternate-number policy');
  const callback = {
    offer: 'acdc-callback-offer-' + entry,
    menu: 'acdc-callback-menu-' + (alternate === true ? 'alternate' : 'current'),
    number_readback: 'acdc-callback-number-readback', confirmation: 'acdc-callback-confirmation',
    success: 'acdc-callback-success', returned_confirmation: 'acdc-callback-returned-confirmation'
  };
  const announcements = Object.fromEntries(ANNOUNCEMENT_KEYS.map(key => [key,
    key === 'you_are_at_position' ? 'acdc-queue-your-current-position-is' : 'acdc-queue-' + key]));
  const updates = [], preserved = [];
  for (const [section, keys] of Object.entries({callback, announcements})) {
    for (const [key, canonical] of Object.entries(keys)) {
      const keysPath = [section, 'media', key], current = pathValue(queue, keysPath);
      assert(typeof prompts[canonical] === 'string', 'Selected fixed voice is missing');
      // Every explicit override, including a stock-looking ID, belongs to the
      // administrator. Only absent fields receive new default suggestions.
      if (current.present) preserved.push({path: keysPath, reason: 'explicit_configuration_preserved'});
      else if (isEnglish) updates.push({path: keysPath, expected: {present: false}, value: prompts[canonical]});
    }
  }
  return {mode: 'OFFLINE_QUEUE_PROPOSAL_NO_WRITES', baseline_english_compatible: isEnglish,
    requires_current_queue_revision_check: true, requires_importer_verify_only: true,
    callback_enabled_changed: false, language_changed: false, announcement_timers_changed: false,
    alternate_number_policy_changed: false, caller_id_or_routing_changed: false,
    updates, preserved,
    unresolved: [
      ...(!isEnglish ? ['Existing non-English queue language must not receive English media overrides'] : []),
      'Eight wait-time bucket IDs require a versioned runtime lookup before natural-voice activation',
      'Native numeric playback is an external runtime dependency; this pack cannot certify it',
      'AR/HE versioned digit playback requires a dedicated runtime mapping; digits do not supply full positions'
    ],
    wait_time_bucket_mapping_for_runtime_review: Object.fromEntries(TIME_KEYS.map(key => [key, prompts['acdc-queue-' + key]]))};
}
function main(argv) {
  const options = {fixedDirectory: BUNDLED_FIXED, completionDirectory: BUNDLED_COMPLETION, locales: LOCALES};
  for (let i = 0; i < argv.length; i++) {
    const key = {'--fixed-pack': 'fixedDirectory', '--completion-pack': 'completionDirectory', '--locale': 'locale', '--queue-json': 'queueFile'}[argv[i]];
    assert(key && i + 1 < argv.length && !argv[i + 1].startsWith('--'), 'Unknown or incomplete voice map option');
    options[key] = argv[++i];
  }
  if (options.locale) options.locales = [options.locale];
  for (const key of ['fixedDirectory', 'completionDirectory', 'queueFile']) {
    if (options[key]) assert(path.isAbsolute(options[key]), 'Voice plan paths must be absolute');
  }
  const manifest = mapping(importer.loadPlan(options.fixedDirectory, options.completionDirectory, options.locales));
  if (options.queueFile) {
    const stat = fs.lstatSync(options.queueFile);
    assert(stat.isFile() && !stat.isSymbolicLink() && stat.size <= 1048576, 'Invalid bounded queue input');
    const queue = JSON.parse(fs.readFileSync(options.queueFile, 'utf8'));
    manifest.queue_proposal = englishQueueProposal(manifest, queue);
  }
  console.log(JSON.stringify(manifest, null, 2));
}
module.exports = {OWNER, BUNDLED_FIXED, BUNDLED_COMPLETION, CALLBACK_KEYS, ANNOUNCEMENT_KEYS, TIME_KEYS, mapping, englishQueueProposal, main};
if (require.main === module) {
  try { main(process.argv.slice(2)); }
  catch (_) { console.error('Offline Gemini mapping failed validation; no source audio, media document or queue was changed.'); process.exitCode = 1; }
}
