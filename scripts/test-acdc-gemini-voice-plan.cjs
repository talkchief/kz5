#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const importer = require('./import-acdc-gemini-voices.cjs');
const planner = require('./plan-acdc-gemini-voices.cjs');
const {LOCALES} = require('./generate-acdc-gemini-samples.cjs');
const assets = importer.loadPlan(planner.BUNDLED_FIXED, planner.BUNDLED_COMPLETION, LOCALES);
const map = planner.mapping(assets);
assert.equal(assets.length, 165);
assert.equal(map.mode, 'OFFLINE_SOURCE_MAPPING_NOT_RUNTIME_CAPABILITIES');
assert.equal(map.runtime_ready, false);
assert.equal(map.installed_verified, false);
for (const [locale, language] of Object.entries(map.languages)) {
  assert.equal(language.fixed_prompt_count, 29);
  assert.equal(language.native_speaker_review, false);
  assert.equal(language.full_language_ready, false);
  assert.equal(language.position.source_full_range_complete, false);
  assert.equal(language.position.generated_full_number_count, 0);
  assert.equal(language.position.supported_position_range, null);
  assert.equal(language.callback.runtime_ready, false);
  assert.equal(language.wait_time.runtime_ready, false);
  const digitKeys = Object.keys(language.callback.telephone_digit_mapping);
  assert.equal(digitKeys.length, ['ar-sa', 'he-il'].includes(locale) ? 10 : 0);
  if (digitKeys.length) assert.deepEqual(digitKeys.sort(), Array.from({length: 10}, (_, n) => String(n)));
}
console.log('PASS165 verified sources separate fixed callback/digit capability from full positional range and all runtime claims');

const queue = {callback: {enabled: false, entry_key: '4', allow_alternate_number: true}, announcements: {initial_delay: 30}};
const before = JSON.stringify(queue), proposal = planner.englishQueueProposal(map, queue);
assert.equal(JSON.stringify(queue), before);
assert.equal(proposal.updates.length, 10);
assert.equal(proposal.baseline_english_compatible, true);
assert(proposal.updates.every(p => p.expected.present === false && p.path.length === 3));
assert.equal(proposal.updates.find(p => p.path.join('.') === 'callback.media.offer').value,
  map.languages['en-us'].prompts['acdc-callback-offer-4']);
assert.equal(proposal.updates.find(p => p.path.join('.') === 'callback.media.menu').value,
  map.languages['en-us'].prompts['acdc-callback-menu-alternate']);
assert.equal(proposal.updates.find(p => p.path.join('.') === 'announcements.media.you_are_at_position').value,
  map.languages['en-us'].prompts['acdc-queue-your-current-position-is']);
assert.equal(Object.keys(proposal.wait_time_bucket_mapping_for_runtime_review).length, 8);
assert.equal(proposal.callback_enabled_changed, false);
assert.equal(proposal.alternate_number_policy_changed, false);
assert.equal(proposal.caller_id_or_routing_changed, false);
assert.equal(proposal.announcement_timers_changed, false);
console.log('PASS English proposal honors current offer digit/alternate policy without enabling callback or changing queue timers');

const custom = {callback: {media: {offer: 'my-custom-offer', success: 'acdc-callback-success', menu: ''}},
  announcements: {media: {you_are_at_position: null, in_the_queue: 'https://example.invalid/custom.wav'}}};
const preserved = planner.englishQueueProposal(map, custom);
assert.equal(preserved.preserved.length, 5);
assert.equal(preserved.updates.length, 5);
assert(preserved.preserved.some(p => p.path.join('.') === 'callback.media.success'));
assert(!JSON.stringify(preserved).includes('my-custom-offer'));
assert(!JSON.stringify(preserved).includes('example.invalid'));
console.log('PASS every explicit override remains unchanged, even stock-looking IDs/empty/null values; custom values are not exposed');

for (const locale of ['he-il', 'ar-sa', 'fr-fr', 'es-es']) {
  const blocked = planner.englishQueueProposal(map, {announcements: {language: locale}});
  assert.equal(blocked.baseline_english_compatible, false);
  assert.equal(blocked.updates.length, 0);
}
assert.equal(planner.englishQueueProposal(map, {announcements: {language: 'en_US'}}).updates.length, 10);
assert.throws(() => planner.englishQueueProposal(map, {callback: {entry_key: '14'}}));
assert.throws(() => planner.englishQueueProposal(map, {callback: {entry_key: 4}}));
assert.throws(() => planner.englishQueueProposal(map, {callback: {allow_alternate_number: 'true'}}));
assert.throws(() => planner.englishQueueProposal(map, {callback: {media: []}}));
console.log('PASS non-English queues never receive English overrides; invalid digit/policy/container inputs fail closed');

const applied = structuredClone(queue);
for (const update of proposal.updates) {
  applied[update.path[0]].media ||= {};
  applied[update.path[0]].media[update.path[2]] = update.value;
}
const repeated = planner.englishQueueProposal(map, applied);
assert.equal(repeated.updates.length, 0);
assert.equal(repeated.preserved.length, 10);
assert.throws(() => planner.mapping(assets.filter(p => p.canonical_id !== 'acdc-number-9')));
assert.throws(() => planner.mapping(assets.slice(1)));
console.log('PASS proposals are idempotent; incomplete fixed or callback-digit source maps fail closed');
console.log('5 Gemini voice-map offline test groups passed; zero network, key reads, queue or media writes.');
