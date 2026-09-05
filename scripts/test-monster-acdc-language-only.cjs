'use strict';
// Real Chromium form validation and submission against the actual ACDC source
// and template. Everything is local/in-memory; no authentication or API writes.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const sourceRoot = path.resolve(__dirname, '..');
const vendorRoot = process.env.KAZOO_MONSTER_VENDOR_ROOT
    || '/usr/local/src/kazoo5-installer/monster-ui/src/js/vendor';
const {chromium} = require(process.env.KAZOO_PLAYWRIGHT_MODULE || 'playwright');
const keys = ['you_are_at_position', 'in_the_queue', 'the_estimated_wait_time_is', 'increase_in_call_volume'];
const callbackKeys = ['offer', 'menu', 'number_readback', 'confirmation', 'success', 'returned_confirmation'];
const fields = keys.map(key => 'announcements.media.' + key)
    .concat(callbackKeys.map(key => 'callback.media.' + key));
const defaults = Object.fromEntries(keys.map(key => [key, 'queue-' + key]));
const template = fs.readFileSync(path.join(sourceRoot, 'monster-ui/acdc/views/queue-form.html'), 'utf8');
const translations = JSON.parse(fs.readFileSync(path.join(sourceRoot, 'monster-ui/acdc/i18n/en-US.json'), 'utf8'));
const schema = JSON.parse(fs.readFileSync(path.join(sourceRoot, 'applications/crossbar/priv/couchdb/schemas/queues.json'), 'utf8'));
const requiredMedia = schema.properties.announcements.properties.media.required;
assert.deepEqual(requiredMedia.slice().sort(), keys.slice().sort(), 'Test must cover every schema-required announcement prompt');
const callbackAnnouncementSchema = schema.properties.callback.properties.announcement;
const Ajv = require(process.env.KAZOO_AJV_MODULE || path.resolve(vendorRoot, '../../../node_modules/ajv'));
const validateSchedule = new Ajv({useDefaults: true}).compile(callbackAnnouncementSchema);
for (const [key, expected] of Object.entries({enabled: {type: 'boolean', default: true},
    initial_delay: {type: 'integer', default: 30, minimum: 1, maximum: 3600},
    interval: {type: 'integer', default: 60, minimum: 15, maximum: 3600}})) {
    for (const [property, value] of Object.entries(expected)) {
        assert.equal(callbackAnnouncementSchema.properties[key][property], value, 'Callback announcement schema ' + key + '.' + property);
    }
}
let schemaCases = 0;
for (const [input, expected] of [[{}, {enabled: true, initial_delay: 30, interval: 60}],
    [{enabled: false}, {enabled: false, initial_delay: 30, interval: 60}],
    [{initial_delay: 1, interval: 15}, {enabled: true, initial_delay: 1, interval: 15}],
    [{enabled: true, initial_delay: 3600, interval: 3600}, {enabled: true, initial_delay: 3600, interval: 3600}]]) {
    assert.equal(validateSchedule(input), true, 'Valid/default callback announcement schema');
    assert.deepEqual(input, expected, 'Schema must supply per-key defaults without changing supplied values');
    schemaCases++;
}
for (const input of [{enabled: 'true'}, {enabled: null}, {initial_delay: 0}, {initial_delay: 3601},
    {initial_delay: 1.5}, {initial_delay: '30'}, {interval: 14}, {interval: 3601}, {interval: 15.5}, {interval: '60'}]) {
    assert.equal(validateSchedule(input), false, 'Invalid callback announcement value must fail schema validation');
    schemaCases++;
}

async function main() {
    const browser = await chromium.launch({headless: true});
    const deadline = setTimeout(() => browser.close().catch(() => {}), 60000);
    const network = [], errors = [];
    let cases = 0;
    try {
        const context = await browser.newContext({serviceWorkers: 'block'});
        await context.route('**/*', route => {
            network.push(route.request().method() + ' ' + new URL(route.request().url()).pathname);
            return route.abort('blockedbyclient');
        });
        const page = await context.newPage();
        page.on('pageerror', error => errors.push(error.message));
        await page.setContent('<!doctype html><html><head><style>.hidden{display:none}</style></head><body></body></html>');
        for (const file of ['jquery-1.9.1.min.js', 'lodash-4.17.4.js', 'handlebars-v4.7.7.js']) {
            await page.addScriptTag({path: path.join(vendorRoot, file)});
        }
        await page.evaluate(() => {
            window.monster = {ui: {chosen() {}}};
            window.define = factory => {
                window.acdc = factory(name => {
                    if (name === 'jquery') return window.jQuery;
                    if (name === 'lodash') return window._;
                    if (name === 'monster') return window.monster;
                    throw new Error('Unexpected ACDC dependency ' + name);
                });
            };
            // The framework select helper, using the actual jQuery/Handlebars
            // libraries. All ACDC dropdown population/validation is unmodified.
            window.Handlebars.registerHelper('select', function(value, options) {
                const element = window.jQuery('<select />').html(options.fn(this));
                for (const item of Array.isArray(value) ? value : [value]) {
                    element.find('[value="' + item + '"]').attr({selected: 'selected'});
                }
                return element.html();
            });
        });
        await page.addScriptTag({path: path.join(sourceRoot, 'monster-ui/acdc/app.js')});
        await page.evaluate(({template, translations}) => {
            const app = window.acdc, $ = window.jQuery, _ = window._;
            app.i18n = {active: () => translations};
            app.renderQueues = () => { throw new Error('Unexpected navigation'); };
            app.request = () => { throw new Error('Unexpected API request'); };
            app.saveQueue = (queueId, payload, agentIds, extension) => {
                window.saved.push({queueId, payload, agentIds, extension});
            };
            app.showFormError = (_view, message) => { window.formErrors.push(message); };
            window.renderFixture = ({legacy = false, callback = false, announcement} = {}) => {
                window.saved = [];
                window.formErrors = [];
                const queue = app.defaultQueue();
                queue.name = 'Unsaved language-only queue';
                queue.callback.enabled = callback;
                queue.callback.caller_id_source = 'inherit';
                queue.callback.outbound_authority = {type: 'user', id: 'fixture-callback-user'};
                if (announcement) _.assign(queue.callback.announcement, announcement);
                if (legacy) {
                    queue.announcements.media.you_are_at_position = 'legacy-position-audio';
                    queue.announcements.media.in_the_queue = 'legacy-suffix-audio';
                    queue.announcements.media.the_estimated_wait_time_is = 'legacy-wait-audio';
                    queue.announcements.media.increase_in_call_volume = 'legacy-volume-audio';
                    for (const key of ['offer', 'menu', 'number_readback', 'confirmation', 'success', 'returned_confirmation']) {
                        queue.callback.media[key] = 'legacy-callback-' + key;
                    }
                }
                const view = $(window.Handlebars.compile(template)({queue, i18n: translations,
                    isEdit: legacy, users: [], legacyPromptOverrides: app.hasLegacyPromptOverrides(queue)}));
                $('body').empty().append(view);
                view.data('roster-read-only', false).data('route-read-only', false)
                    .data('callflow-summaries', []).data('owned-route', null);
                const manifest = {schema_version: 1, backend_mode: 'legacy', generated_at: '2026-09-05T00:00:00Z',
                    languages: Object.fromEntries(app.announcementLocales.map(locale => [locale,
                        {ready: false, position: false, wait_time: false, callback: false, native_speaker_review: false}]))};
                const systemMedia = app.requiredLanguagePromptIds().map(id => ({
                    id: 'en-us/' + (id.indexOf('acdc-queue-') === 0 && id !== 'acdc-queue-your-current-position-is' ? id.slice(5) : id),
                    language: 'en-us', name: id
                }));
                app.populateQueueDropdowns(view, queue, {users: [{id: 'fixture-callback-user', first_name: 'Fixture', last_name: 'Agent'}],
                    media: [], numbers: [], verifiedSystemMedia: systemMedia, languageCapabilities: manifest}, {}, legacy);
                app.renderAgentOrder(view, []);
                app.bindQueueForm(view, legacy ? 'fixture-queue' : undefined, 1, 'fixture-account');
                return queue;
            };
        }, {template, translations});

        async function render(options) { return page.evaluate(options => window.renderFixture(options), options); }
        async function submit() {
            return page.evaluate(() => {
                const form = document.querySelector('.acdc-queue-form');
                const checked = form.checkValidity(), reported = form.reportValidity();
                form.requestSubmit();
                return {checked, reported, saved: window.saved, formErrors: window.formErrors};
            });
        }
        await render({});
        const controls = await page.evaluate(fields => ({
            hidden: fields.map(name => {
                const elements = document.querySelectorAll('[name="' + name + '"]');
                return {count: elements.length, type: elements[0]?.type, required: elements[0]?.required};
            }),
            language: Array.from(document.querySelector('[name="announcements.language"]').options)
                .filter(option => option.value).map(option => ({value: option.value, disabled: option.disabled})),
            warning: Boolean(document.querySelector('.acdc-legacy-prompt-warning')),
            remainingMedia: Array.from(document.querySelectorAll('select.acdc-media-select'), element => element.name)
        }), fields);
        assert(controls.hidden.every(item => item.count === 1 && item.type === 'hidden' && !item.required),
            'Announcement/callback media must have no custom recording selectors or hidden required controls');
        assert.deepEqual(controls.language.map(option => option.value).sort(), ['ar-sa', 'en-us', 'es-es', 'fr-fr', 'he-il']);
        assert.deepEqual(controls.language.filter(option => !option.disabled).map(option => option.value), ['en-us'],
            'Language-only UI must not turn unsupported languages into active choices');
        assert.equal(controls.warning, false);
        assert.deepEqual(controls.remainingMedia.sort(), ['announce', 'moh']);
        cases++;
        let result = await submit();
        assert(result.checked && result.reported, 'Canonical new queue must pass native validation');
        assert.equal(result.saved.length, 1);
        assert.deepEqual(result.saved[0].payload.announcements.media, defaults);
        assert.equal(Object.hasOwn(result.saved[0].payload.callback, 'media'), false, 'Fresh callback uses backend prompt defaults');
        assert.deepEqual(result.formErrors, []);
        cases++;

        await render({callback: true});
        let schedule = await page.evaluate(() => ({
            enabled: document.querySelector('[name="callback.announcement.enabled"]').checked,
            timing: Array.from(document.querySelectorAll('.acdc-callback-announcement-timing'), element => ({
                name: element.name, type: element.type, value: Number(element.value), disabled: element.disabled, required: element.required
            }))
        }));
        assert.equal(schedule.enabled, true);
        assert.deepEqual(schedule.timing.map(item => item.value), [30, 60]);
        assert(schedule.timing.every(item => item.type === 'number' && item.required && !item.disabled));
        await page.locator('[name="callback.announcement.initial_delay"]').fill('12');
        await page.locator('[name="callback.announcement.interval"]').fill('75');
        await page.locator('[name="announcements.initial_delay"]').fill('40');
        await page.locator('[name="announcements.interval"]').fill('45');
        result = await submit();
        assert(result.checked && result.reported && result.saved.length === 1);
        assert.deepEqual(result.saved[0].payload.callback.announcement, {enabled: true, initial_delay: 12, interval: 75});
        assert.equal(result.saved[0].payload.announcements.initial_delay, 40);
        assert.equal(result.saved[0].payload.announcements.interval, 45);
        cases++;

        for (const [key, value] of [['initial_delay', '0'], ['initial_delay', '3601'], ['initial_delay', '1.5'], ['initial_delay', ''],
            ['interval', '14'], ['interval', '3601'], ['interval', '15.5'], ['interval', '']]) {
            await render({callback: true});
            await page.locator('[name="callback.announcement.' + key + '"]').fill(value);
            result = await submit();
            assert(!result.checked && !result.reported && result.saved.length === 0,
                'Active callback announcement ' + key + '=' + value + ' must block native form submission');
            cases++;
        }
        for (const values of [{initial_delay: 1, interval: 15}, {initial_delay: 3600, interval: 3600}]) {
            await render({callback: true, announcement: values});
            result = await submit();
            assert(result.checked && result.reported && result.saved.length === 1);
            assert.deepEqual(result.saved[0].payload.callback.announcement, {enabled: true, ...values});
            cases++;
        }
        for (const disable of ['offer', 'callback']) {
            await render({callback: true, legacy: true});
            await page.locator('[name="callback.announcement.initial_delay"]').fill('0');
            await page.locator('[name="callback.announcement.interval"]').fill('0');
            await page.locator('[name="' + (disable === 'offer' ? 'callback.announcement.enabled' : 'callback.enabled') + '"]').uncheck();
            schedule = await page.evaluate(() => {
                const view = window.jQuery('.acdc-queue-editor'), form = view.find('.acdc-queue-form');
                window.acdc.setFormBusy(view, true);
                window.acdc.setFormBusy(view, false);
                return {disabled: Array.from(document.querySelectorAll('.acdc-callback-announcement-timing'), element => element.disabled),
                    conflict: window.acdc.callbackKeyError(form) || window.acdc.callbackSelectionError(form)};
            });
            assert.deepEqual(schedule.disabled, [true, true], 'Disabled timing controls must stay disabled after saving/error recovery');
            assert.equal(schedule.conflict, null);
            result = await submit();
            assert(result.checked && result.reported && result.saved.length === 1);
            assert.deepEqual(result.saved[0].payload.callback.announcement, {enabled: disable !== 'offer'},
                'Disabled timers must be omitted to preserve saved configuration on PATCH');
            assert.equal(result.saved[0].payload.callback.entry_key, '6');
            assert.equal(result.saved[0].payload.callback.enabled, disable === 'offer');
            cases++;
        }

        // Exercise the reported empty/default state too, including older empty
        // values loaded from existing data: never serialize empty audio IDs.
        for (const key of keys) {
            await render({});
            await page.evaluate(key => { document.querySelector('[name="announcements.media.' + key + '"]').value = ''; }, key);
            result = await submit();
            assert(result.checked && result.reported && result.saved.length === 1);
            assert.deepEqual(result.saved[0].payload.announcements.media, defaults);
            cases++;
        }
        const legacy = await render({legacy: true, callback: true});
        assert.equal(await page.locator('.acdc-legacy-prompt-warning').isVisible(), true);
        assert((await page.locator('.acdc-legacy-prompt-warning').innerText()).includes('preserved'));
        await page.locator('[name="name"]').fill('Unsaved unrelated rename');
        await page.locator('[name="announcements.language"]').selectOption('en-us');
        result = await submit();
        assert(result.checked && result.reported && result.saved.length === 1);
        assert.deepEqual(result.saved[0].payload.announcements.media, legacy.announcements.media);
        assert.deepEqual(result.saved[0].payload.callback.media, legacy.callback.media);
        assert.equal(result.saved[0].payload.announcements.language, 'en-us');
        assert.equal(result.saved[0].queueId, 'fixture-queue');
        cases++;

        for (const scenario of ['name', 'callback-user', 'custom-caller-id', 'retry-delay']) {
            await render({callback: true});
            if (scenario === 'name') await page.locator('[name="name"]').fill('');
            if (scenario === 'callback-user') await page.locator('[name="callback.outbound_authority.id"]').selectOption('');
            if (scenario === 'custom-caller-id') await page.locator('[name="callback.caller_id_source"]').selectOption('custom');
            if (scenario === 'retry-delay') await page.locator('[name="callback.retry_delay"]').fill('1');
            result = await submit();
            assert.equal(result.checked, false, scenario + ' must remain natively invalid');
            assert.equal(result.reported, false, scenario + ' reportValidity must remain false');
            assert.equal(result.saved.length, 0, scenario + ' must block submit');
            cases++;
        }
        assert.deepEqual(network, [], 'The private browser regression must never make network requests');
        assert.deepEqual(errors, [], 'The real form must not raise page exceptions');
        console.log(JSON.stringify({result: 'PASS', cases, actual_chromium_validation: true,
            actual_template_and_submit_handler: true, custom_prompt_selectors: 0,
            callback_announcement_schema_cases: schemaCases, callback_announcement_independent_timing: true,
            offered_locales: controls.language.map(option => option.value), active_legacy_locales: ['en-us'],
            legacy_overrides_preserved: true, network_requests: network.length, api_writes: 0}));
    } finally {
        clearTimeout(deadline);
        await browser.close();
    }
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
