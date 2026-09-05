#!/usr/bin/env node
'use strict';
// Offline real Chromium form validity + exact baseline-feature regression.
// No authentication, live API, provider request or database write is allowed.
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm');
const assert = require('node:assert/strict');
const {overlay, readBaseline, digest} = require('./build-acdc-baseline-ui.cjs');
const dependencyRoot = '/usr/local/src/kazoo5-installer/monster-ui';
const modulePath = name => require.resolve(name, {paths: [dependencyRoot]});
const lodash = require(modulePath('lodash'));
const {chromium} = require(process.env.KAZOO_PLAYWRIGHT_MODULE || '/tmp/kazoo-ui-browser.eXdEqS/node_modules/playwright');
function load(source) {
    let app;
    vm.runInNewContext(source, {define: factory => { app = factory(name => {
        if (name === 'lodash') return lodash;
        if (name === 'jquery') return {trim: value => String(value || '').trim()};
        if (name === 'monster') return {apps: {}, ui: {}};
        throw Error('Unexpected AMD dependency');
    }); }, setTimeout, Date, Math});
    return app;
}
async function main() {
    const previewSource = fs.readFileSync(path.join(__dirname, 'test-monster-acdc-readonly.cjs'), 'utf8');
    const profileCode = previewSource.slice(previewSource.indexOf('const deploymentProfile ='), previewSource.indexOf('const secretsPath ='));
    const profile = env => vm.runInNewContext(profileCode + '\n({deploymentProfile, baselineProfile});', {process: {env}, assert});
    assert.equal(profile({}).deploymentProfile, 'staged');
    assert.equal(profile({KAZOO_TEST_ACDC_PROFILE: 'baseline', KAZOO_TEST_ACDC_STAGE: '/private/stage'}).baselineProfile, true);
    assert.throws(() => profile({KAZOO_TEST_ACDC_PROFILE: 'unknown'}), /Unknown expected/);
    assert.throws(() => profile({KAZOO_TEST_ACDC_PROFILE: 'baseline'}), /requires a pinned private build/);
    assert.throws(() => profile({KAZOO_TEST_ACDC_PROFILE: 'baseline', KAZOO_TEST_ACDC_STAGE: '/private/stage', KAZOO_TEST_QUEUE_EDITOR: 'true'}), /must not use the aggregate/);
    assert(previewSource.includes("control.count === 1 && control.tag === 'INPUT'") && previewSource.includes('Fresh queue announcements must serialize real default prompts'),
        'Default staged preview assertions must remain present');
    console.log('PASS explicit baseline preview profile fails closed and retains the default staged contract');
    const stage = fs.realpathSync(process.argv[2]);
    assert(stage.startsWith('/usr/local/src/kazoo5-installer/monster-acdc-baseline-'));
    const baseFiles = readBaseline(), files = overlay(baseFiles);
    assert.throws(() => overlay({...baseFiles, 'app.js': Buffer.from('unreviewed source')}), /Unexpected baseline/);
    const base = load(baseFiles['app.js'].toString()), app = load(files['app.js'].toString());
    const allowedChanges = new Set(['populateQueueDropdowns', 'defaultQueue', 'bindQueueForm', 'syncCallbackForm', 'serializeQueue']);
    assert.deepEqual(Object.keys(app), Object.keys(base));
    for (const key of Object.keys(base)) {
        if (allowedChanges.has(key)) continue;
        assert.equal(typeof app[key] === 'function' ? app[key].toString() : JSON.stringify(app[key]),
            typeof base[key] === 'function' ? base[key].toString() : JSON.stringify(base[key]), 'Unrelated baseline feature changed: ' + key);
    }
    assert.deepEqual(Array.from(app.announcementLocales).sort(), ['ar-sa', 'en-us', 'es-es', 'fr-fr', 'he-il']);
    assert(!Object.keys(app.requests).some(key => /editor/.test(key)));
    assert(!Object.values(app.requests).some(request => /\/editor/.test(request.url)));
    for (const [name, bytes] of Object.entries(files)) assert.equal(digest(fs.readFileSync(path.join(stage, 'src/apps/acdc', name))), digest(bytes));
    assert(!fs.existsSync(path.join(stage, 'dist/apps/acdc/language-capabilities.json')));
    assert.equal(fs.readFileSync(path.join(stage, 'dist/apps/acdc/VERSION'), 'utf8'), '1.0.0-baseline.5756082\n');
    const manifest = JSON.parse(fs.readFileSync(path.join(stage, 'baseline-build.json')));
    assert.equal(manifest.overlay_sha256, digest(fs.readFileSync(path.join(__dirname, 'build-acdc-baseline-ui.cjs'))));
    for (const [name, hash] of Object.entries(manifest.files)) assert.equal(digest(fs.readFileSync(path.join(stage, name))), hash);
    console.log('PASS exact pinned source/build hashes; only five scoped methods changed; unrelated actions/routes/language checks preserved');

    const browser = await chromium.launch({headless: true});
    const requests = [], errors = [];
    try {
        const page = await browser.newPage();
        await page.route('**/*', route => { requests.push(route.request().url()); return route.abort(); });
        page.on('pageerror', error => errors.push(error.message));
        await page.setContent('<!doctype html><html><body><main id="fixture"></main></body></html>');
        await page.addScriptTag({path: path.join(dependencyRoot, 'src/js/vendor/jquery-1.9.1.min.js')});
        await page.addScriptTag({path: modulePath('lodash')});
        await page.addScriptTag({path: path.join(path.dirname(modulePath('handlebars/package.json')), 'dist/handlebars.runtime.js')});
        await page.evaluate(() => {
            window.monster = {cache: {templates: {}}, apps: {}, ui: {chosen() {}}};
            window.define = factory => { window.fixtureApp = factory(name => {
                if (name === 'jquery') return window.jQuery;
                if (name === 'lodash') return window._;
                if (name === 'monster') return window.monster;
                throw Error('Unexpected dependency');
            }); };
            Handlebars.registerHelper('select', function(value, options) { return options.fn(this); });
        });
        await page.addScriptTag({path: path.join(stage, 'dist/apps/acdc/app.js')});
        const results = await page.evaluate(i18n => {
            const app = window.fixtureApp, $ = window.jQuery;
            app.i18n = {active: () => i18n};
            const assert = (condition, text) => { if (!condition) throw Error(text); };
            const copy = value => JSON.parse(JSON.stringify(value));
            const fresh = overrides => {
                const queue = _.merge(app.defaultQueue(), overrides || {});
                const view = $(monster.cache.templates.acdc._main['queue-form']({queue, users: [], i18n}));
                $('#fixture').empty().append(view);
                app.populateQueueDropdowns(view, queue, {
                    users: [{id: 'fixture-user', first_name: 'Fixture', last_name: 'Agent', enabled: true}],
                    media: [], verifiedSystemMedia: [], numbers: [], languageCapabilities: null
                }, {}, Boolean(overrides));
                const form = view.find('form'); form.find('[name="name"]').val('Offline baseline fixture');
                app.syncCallbackForm(form);
                return {queue, view, form};
            };
            let {form} = fresh();
            assert(form.find('[name^="announcements.media."], [name^="callback.media."]').length === 0, 'Custom prompt controls leaked');
            assert(form.find('[name="moh"], [name="announce"]').length === 2, 'Hold/pre-connect controls removed');
            assert(form[0].checkValidity(), 'Default new queue has an invalid hidden/required field');
            let payload = app.serializeQueue(form, false);
            assert(!Object.hasOwn(payload.announcements, 'media') && !Object.hasOwn(payload.callback, 'media'), 'Create must use backend prompts');
            assert(!Object.hasOwn(payload.callback, 'return_confirmation_prompt'), 'Create wrote legacy prompt');
            assert(payload.callback.enabled === false && payload.callback.announcement.enabled === true, 'Callback defaults changed');
            assert(!Object.hasOwn(payload.callback.announcement, 'initial_delay'), 'Inactive timing must be omitted');
            const choices = form.find('[name="announcements.language"] option').toArray().filter(option => option.value);
            assert(choices.length === 5 && choices.every(option => option.disabled), 'Unverified packs became selectable');
            assert(form.find('[name="announcements.language"]').val() === '', 'Default language must be valid');

            form.find('[name="callback.enabled"]').prop('checked', true);
            form.find('[name="callback.outbound_authority.id"]').val('fixture-user');
            form.find('[name="callback.announcement.initial_delay"]').val('5');
            form.find('[name="callback.announcement.interval"]').val('45');
            app.syncCallbackForm(form);
            assert(form[0].checkValidity(), 'Enabled callback with valid independent timings is invalid');
            assert(app.callbackKeyError(form) === null && app.callbackSelectionError(form) === null, 'Valid callback selection rejected');
            payload = app.serializeQueue(form, false);
            assert(JSON.stringify(payload.callback.announcement) === JSON.stringify({enabled: true, initial_delay: 5, interval: 45}), 'Independent callback timings not serialized');
            assert(payload.announcements.initial_delay === 30 && payload.announcements.interval === 30, 'Position timing was coupled to callback');
            for (const [field, values] of [['initial_delay', ['0', '3601', '1.5', '']], ['interval', ['14', '3601', '1.5', '']]]) {
                const input = form.find('[name="callback.announcement.' + field + '"]');
                const original = input.val();
                for (const value of values) { input.val(value); assert(!form[0].checkValidity(), 'Out-of-range active timing accepted'); }
                input.val(original);
            }
            form.find('[name="callback.announcement.enabled"]').prop('checked', false);
            form.find('[name="callback.announcement.initial_delay"], [name="callback.announcement.interval"]').val('');
            app.syncCallbackForm(form);
            assert(form[0].checkValidity(), 'Disabled callback announcement blocks default save');
            payload = app.serializeQueue(form, true);
            assert(payload.callback.enabled && !payload.callback.announcement.enabled, 'Turning offer off disabled callback itself');
            assert(Object.keys(payload.callback.announcement).length === 1, 'Disabled schedule was blanked');

            const overrides = {announcements: {media: {you_are_at_position: 'custom-prefix', in_the_queue: 'custom-suffix',
                the_estimated_wait_time_is: 'custom-wait', increase_in_call_volume: 'custom-volume'}},
                callback: {announcement: {enabled: false, initial_delay: 9, interval: 123},
                    media: {offer: 'immutable-offer', menu: 'custom-menu', success: 'immutable-success'},
                    return_confirmation_prompt: 'legacy-return'}};
            const fixture = fresh(overrides); form = fixture.form;
            const original = copy(overrides);
            const privatePrompts = form.data('preserved-prompt-overrides');
            assert(privatePrompts.announcements.you_are_at_position === 'custom-prefix' && privatePrompts.callback.offer === 'immutable-offer'
                && privatePrompts.return_confirmation_prompt === 'legacy-return', 'Prompt override private state lost');
            payload = app.serializeQueue(form, true);
            const after = _.merge(copy(original), copy(payload));
            assert(JSON.stringify(after.announcements.media) === JSON.stringify(original.announcements.media), 'PATCH changed legacy announcement overrides');
            assert(JSON.stringify(after.callback.media) === JSON.stringify(original.callback.media), 'PATCH changed immutable callback overrides');
            assert(after.callback.return_confirmation_prompt === 'legacy-return', 'PATCH erased the legacy returned prompt');
            assert(after.callback.announcement.initial_delay === 9 && after.callback.announcement.interval === 123, 'Inactive PATCH changed existing schedule');
            assert(!Object.hasOwn(payload.announcements, 'media') && !Object.hasOwn(payload.callback, 'media'), 'PATCH retransmitted stale hidden overrides');
            assert(form[0].checkValidity(), 'Existing queue with legacy overrides is invalid');
            const submitFixture = fresh();
            let captured;
            app.saveQueue = (...args) => { captured = args; };
            app.bindQueueForm(submitFixture.view, undefined, 1, 'offline-account');
            submitFixture.form.trigger('submit');
            assert(captured && captured[1].name === 'Offline baseline fixture', 'Normal submit handler did not reach the save boundary');
            assert(!Object.hasOwn(captured[1].announcements, 'media'), 'Submit handler reintroduced prompt overrides');
            submitFixture.form.find('[name="callback.enabled"]').prop('checked', true).trigger('change');
            assert(!submitFixture.form.find('[name="callback.announcement.initial_delay"]')[0].disabled, 'Bound enable change did not activate timing');
            submitFixture.form.find('[name="callback.announcement.enabled"]').prop('checked', false).trigger('change');
            assert(submitFixture.form.find('[name="callback.announcement.initial_delay"]')[0].disabled, 'Bound offer change did not disable timing');
            return {default_queue_valid: true, callback_timing_validated: true, disabled_offer_keeps_callback: true,
                saved_prompt_overrides_preserved: true, language_readiness_unchanged: true, normal_submit_reaches_save_boundary: true};
        }, JSON.parse(files['i18n/en-US.json']));
        assert.deepEqual(requests, [], 'Offline regression attempted network traffic');
        assert.deepEqual(errors, [], 'Compiled baseline caused browser errors');
        console.log('PASS offline compiled Chromium form: ' + JSON.stringify(results));
    } finally { await browser.close(); }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
