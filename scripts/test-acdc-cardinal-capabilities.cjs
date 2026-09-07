'use strict';
// Pure structural validator and actual UI functions; no DOM/network/runtime writes.
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm'), assert = require('node:assert/strict');
const validator = require('./validate-acdc-language-capabilities.cjs');
const {cardinalCapabilities} = require('./test-fixtures/acdc-cardinal-capabilities.cjs');
const root = path.resolve(__dirname, '..');
const lodash = require(path.join(process.env.KAZOO_MONSTER_VENDOR_ROOT
    || '/usr/local/src/kazoo5-installer/monster-ui/src/js/vendor', 'lodash-4.17.4.js'));
let app;
vm.runInNewContext(fs.readFileSync(path.join(root, 'monster-ui/acdc/app.js'), 'utf8'), {define(factory) {
    app = factory(name => ({lodash, jquery() { throw Error('Unexpected DOM access'); }, monster: {}})[name]);
}});
app.i18n = {active: () => JSON.parse(fs.readFileSync(path.join(root, 'monster-ui/acdc/i18n/en-US.json'), 'utf8'))};
const map = fs.readFileSync(path.join(root, 'applications/acdc/src/acdc_gemini_map.hrl'), 'utf8');
const fixedHash = map.match(/GEMINI_MAP_SHA256, <<"([a-f0-9]{64})">>/)[1];
const media = [...map.matchAll(/\{<<"([a-z]{2}-[a-z]{2})">>,<<"([^"]+)">>,<<"([^"]+)">>,<<"([a-f0-9]{64})">>/g)]
    .map(([, locale, canonical, prompt, sha]) => ({id: locale + '/' + prompt, name: canonical, language: locale,
        has_attachments: true, prompt_id: prompt, canonical_prompt_id: canonical, sha256: sha,
        source_type: 'kazoo5_acdc_gemini_voice_installer', source_map_sha256: fixedHash, import_metadata_verified: true}));
assert.equal(media.length, 210);
const clone = value => JSON.parse(JSON.stringify(value));
const choices = (manifest, items = media, error = null) => clone(app.languageCapabilityOptions(manifest, items, error));
let checks = 0;
function valid(manifest) {
    assert.doesNotThrow(() => validator.assertLanguageCapabilities(manifest));
    assert.equal(app.validLanguageCapabilities(manifest), true); checks++;
}
function invalid(manifest) {
    assert.throws(() => validator.assertLanguageCapabilities(manifest));
    assert.equal(app.validLanguageCapabilities(manifest), false); checks++;
}
for (const stage of ['source', 'installed', 'runtime', 'reviewed']) {
    const manifest = cardinalCapabilities(stage); valid(manifest);
    assert.equal(Object.values(manifest.languages).reduce((n, e) => n + e.numeric_prompt_count, 0), 584);
    const options = choices(manifest);
    assert.equal(options.filter(x => !x.disabled).length, ['runtime', 'reviewed'].includes(stage) ? 5 : 0);
    if (stage === 'runtime') {
        assert(Object.values(manifest.languages).every(e => !e.ready && e.selection_ready && !e.native_speaker_review
            && e.native_review_sha256 === null));
        assert(options.every(x => x.label.includes('Available for voice testing') && x.label.includes('review pending')));
    }
    if (stage === 'reviewed') assert(options.every(x => x.label.endsWith(' — Ready')));
}
const runtime = cardinalCapabilities('runtime');
for (const key of ['position_runtime_verified', 'callback_runtime_verified', 'wait_time_runtime_verified']) {
    const value = clone(runtime), entry = value.languages['ar-sa'];
    entry[key] = false; entry[{position_runtime_verified: 'position', callback_runtime_verified: 'callback', wait_time_runtime_verified: 'wait_time'}[key]] = false;
    entry.selection_ready = false; valid(value);
    assert.equal(choices(value).find(x => x.value === 'ar-sa').disabled, true);
    assert.equal(choices(value).filter(x => !x.disabled).length, 4);
}
for (const [key, value] of [['schema_version', 3], ['backend_mode', 'legacy'], ['generated_at', 'invalid'], ['extra', true]]) {
    invalid({...runtime, [key]: value});
}
for (const key of Object.keys(runtime.languages['en-us'])) {
    const value = clone(runtime); delete value.languages['en-us'][key]; invalid(value);
}
for (const [key, value] of [['ready', true], ['selection_ready', false], ['position', false], ['callback', false], ['wait_time', false],
    ['position_runtime_verified', 'true'], ['native_speaker_review', true], ['native_review_sha256', 'e'.repeat(64)],
    ['installed_media_sha256', null], ['runtime_evidence_sha256', null], ['runtime_evidence_sha256', 'bad'],
    ['numbers', 'native_say'], ['numeric_prompt_count', 2999], ['numeric_prompt_count', '31'], ['callback_prompt_count', 32],
    ['number_range', [0, 1000000000]], ['cardinal_map_sha256', 'bad'], ['extra', 'private']]) {
    const manifest = clone(runtime); manifest.languages['en-us'][key] = value; invalid(manifest);
}
for (const locales of [{...runtime.languages, 'de-de': runtime.languages['en-us']},
    Object.fromEntries(Object.entries(runtime.languages).filter(([locale]) => locale !== 'ar-sa'))]) invalid({...runtime, languages: locales});
for (const locale of Object.keys(runtime.languages)) {
    const selected = media.filter(x => x.language === locale); assert.equal(selected.length, 42);
    for (const item of selected) {
        const options = choices(runtime, media.filter(x => x !== item));
        assert.equal(options.find(x => x.value === locale).disabled, true);
        assert.equal(options.filter(x => !x.disabled).length, 4); checks++;
    }
    for (const [key, value] of [['import_metadata_verified', false], ['source_map_sha256', '0'.repeat(64)],
        ['canonical_prompt_id', 'acdc-unknown'], ['id', locale + '/canonical-alias'], ['has_attachments', false]]) {
        const items = media.map(x => x === selected[0] ? {...x, [key]: value} : x);
        assert.equal(choices(runtime, items).find(x => x.value === locale).disabled, true); checks++;
    }
    assert.equal(choices(runtime, media.concat(selected[0])).find(x => x.value === locale).disabled, true);
}
assert(choices(runtime, [], 'unavailable').every(x => x.disabled));
const source = cardinalCapabilities('source'); source.languages['en-us'].selection_ready = true; invalid(source);
const legacy = validator.legacyLanguageCapabilities('2026-09-07T12:00:00Z'); valid(legacy);
assert(Object.values(legacy.languages).every(e => Object.values(e).every(x => x === false)));
console.log(`PASS ${checks} prerecorded capability validator/UI checks; synthetic evidence, no deployment or native listening claim`);
