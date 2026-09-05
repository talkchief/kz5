'use strict';
// SPDX-License-Identifier: MPL-2.0
// Installer-owned runtime capability artifact, never a build-time readiness claim.
const assert = require('node:assert/strict');
const locales = ['en-us', 'ar-sa', 'he-il', 'es-es', 'fr-fr'];
const requiredPromptIds = [
    ...Array.from({length: 10}, (_, key) => 'acdc-callback-offer-' + key),
    ...['menu-current', 'menu-alternate', 'number-readback', 'confirmation', 'success', 'returned-confirmation']
        .map(name => 'acdc-callback-' + name),
    ...['your-current-position-is', 'you_are_at_position', 'in_the_queue', 'increase_in_call_volume',
        'the_estimated_wait_time_is', 'less_than_1_minute', 'about_5_minutes', 'about_10_minutes',
        'about_15_minutes', 'about_30_minutes', 'about_45_minutes', 'about_1_hour', 'at_least_1_hour']
        .map(name => 'acdc-queue-' + name)
];
const plain = value => value && typeof value === 'object' && !Array.isArray(value)
    && Object.getPrototypeOf(value) === Object.prototype;
const flags = ['ready', 'position', 'wait_time', 'callback', 'native_speaker_review'];
function assertLanguageCapabilities(manifest) {
    assert(plain(manifest) && manifest.schema_version === 1, 'Unknown language capability schema');
    assert(manifest.backend_mode === undefined || manifest.backend_mode === 'legacy', 'Unknown capability backend mode');
    const legacy = manifest.backend_mode === 'legacy';
    if (legacy) assert.deepEqual(Object.keys(manifest).sort(),
        ['schema_version', 'backend_mode', 'generated_at', 'languages'].sort(), 'Unexpected legacy capability claim');
    assert(typeof manifest.generated_at === 'string'
        && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z$/.test(manifest.generated_at)
		&& Number.isFinite(Date.parse(manifest.generated_at)), 'Invalid capability generation timestamp');
    assert(plain(manifest.languages), 'Missing language capability map');
    assert.deepEqual(Object.keys(manifest.languages).sort(), locales.slice().sort(), 'Unexpected capability locales');
    for (const locale of locales) {
        const entry = manifest.languages[locale], prerecorded = ['ar-sa', 'he-il'].includes(locale);
        assert(plain(entry), 'Invalid language capability entry');
        for (const key of flags) {
            assert.equal(typeof entry[key], 'boolean', 'Invalid capability flag: ' + key);
        }
        if (legacy) {
            assert.deepEqual(Object.keys(entry).sort(), flags.slice().sort(), 'Unexpected legacy language proof');
            assert(flags.every(key => entry[key] === false), 'Legacy mode must not claim localized readiness');
        }
        if (!entry.ready) continue;
        assert(entry.position && entry.wait_time && entry.callback, 'Incomplete ready language functions');
        assert.equal(entry.numbers, prerecorded ? 'prerecorded' : 'native_say', 'Invalid numeric capability mode');
        assert.deepEqual(entry.number_range, [0, 999999999], 'Incomplete numeric capability range');
        assert.equal(entry.numeric_prompt_count, prerecorded ? 2999 : 0, 'Incomplete numeric prompt pack');
        assert(Array.isArray(entry.required_prompt_ids) && entry.required_prompt_ids.every(id => typeof id === 'string'),
            'Invalid required prompt identifiers');
        assert.deepEqual(entry.required_prompt_ids.slice().sort(), requiredPromptIds.slice().sort(), 'Incomplete fixed prompt pack');
        for (const key of ['source_catalog_sha256', 'installed_media_sha256']) {
            assert(/^[a-f0-9]{64}$/.test(entry[key] || ''), 'Missing installed capability proof hash');
        }
    }
    return manifest;
}
function legacyLanguageCapabilities(generatedAt = new Date().toISOString()) {
    return assertLanguageCapabilities({schema_version: 1, backend_mode: 'legacy', generated_at: generatedAt,
        languages: Object.fromEntries(locales.map(locale => [locale, Object.fromEntries(flags.map(key => [key, false]))]))});
}
module.exports = {assertLanguageCapabilities, legacyLanguageCapabilities, locales, requiredPromptIds};
