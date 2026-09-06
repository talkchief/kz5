'use strict';
// Actual Chromium, source template and submit handler; all API responses mocked
// in memory. No authentication, SIP, live web preview or HTTP API writes.
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const vendors = process.env.KAZOO_MONSTER_VENDOR_ROOT || '/usr/local/src/kazoo5-installer/monster-ui/src/js/vendor';
const {chromium} = require(process.env.KAZOO_PLAYWRIGHT_MODULE || 'playwright');
const stage = process.env.KAZOO_TEST_ACDC_STAGE && fs.realpathSync(process.env.KAZOO_TEST_ACDC_STAGE);
if (stage) assert(stage.startsWith('/usr/local/src/kazoo5-installer/monster-acdc-'), 'Unexpected private stage path');
const appRoot = stage ? path.join(stage, 'dist/apps/acdc') : path.join(root, 'monster-ui/acdc');
const template = fs.readFileSync(path.join(root, 'monster-ui/acdc/views/queue-form.html'), 'utf8');
const translations = JSON.parse(fs.readFileSync(path.join(appRoot, 'i18n/en-US.json'), 'utf8'));
(async () => {
    const browser = await chromium.launch({headless: true}), page = await browser.newPage();
    const network = [], errors = [], deadline = setTimeout(() => browser.close(), 90000);
    page.on('request', req => network.push(req.url())); page.on('pageerror', error => errors.push(error.message));
    await page.route('**/*', route => route.abort());
    try {
        await page.setContent('<main id="content"></main>');
        for (const file of ['jquery-1.9.1.min.js', 'lodash-4.17.4.js', 'handlebars-v4.7.7.js']) {
            await page.addScriptTag({path: path.join(vendors, file)});
        }
        await page.evaluate(() => {
            window.monster = {ui: {chosen() {}}};
            window.define = (...args) => { window.app = args[args.length - 1](name => ({jquery: window.jQuery, lodash: window._, monster: window.monster})[name]); };
            window.Handlebars.registerHelper('select', function(value, options) {
                const element = window.jQuery('<select/>').html(options.fn(this));
                for (const item of Array.isArray(value) ? value : [value]) element.find('[value="' + item + '"]').attr('selected', 'selected');
                return element.html();
            });
        });
        await page.addScriptTag({path: path.join(appRoot, 'app.js')});
        await page.evaluate(({template, translations, built}) => {
            const app = window.app, $ = window.jQuery, _ = window._;
            app.accountId = 'a'.repeat(32); window.qid = 'b'.repeat(32);
            app.i18n = {active: () => translations}; app.appFlags.acdc.currentTab = 'queues';
            app.getContentContainer = () => $('#content');
            const queueTemplate = built ? window.monster.cache.templates.acdc._main['queue-form'] : window.Handlebars.compile(template);
            if (typeof queueTemplate !== 'function') throw new Error('Private built queue template was not loaded');
            app.getTemplate = ({name, data}) => name === 'queue-form'
                ? queueTemplate({...data, i18n: translations}) : '<div class="state">Loading</div>';
            app.toastSuccess = () => { window.successes++; };
            app.renderQueues = () => { window.navigations++; };
            window.resultData = () => {
                const users = Array.from({length: 30}, (_, n) => ({id: n.toString(16).padStart(32, '0'), first_name: 'Agent', last_name: String(n + 1), enabled: true}));
                const queue = app.defaultQueue(); queue.name = 'Queue loaded'; queue.announcements.language = 'en-us';
                queue.announcements.media.you_are_at_position = 'legacy-position'; queue.future_field = {keep: true};
                queue.callback.media.offer = 'legacy-callback';
                const required = app.requiredLanguagePromptIds();
                const language_capabilities = {schema_version: 1, generated_at: '2026-09-05T19:00:00Z', languages: {}};
                for (const locale of app.announcementLocales) language_capabilities.languages[locale] = {
                    ready: locale === 'en-us', position: locale === 'en-us', wait_time: locale === 'en-us', callback: locale === 'en-us',
                    native_speaker_review: false, numbers: 'native_say', number_range: [0, 999999999], numeric_prompt_count: 0,
                    required_prompt_ids: required, source_catalog_sha256: '1'.repeat(64), installed_media_sha256: '2'.repeat(64)};
                return {queue, users, roster: users.map(u => u.id), media: [], numbers: [],
                    system_media: required.map(id => ({id: 'en-us/' + id, name: id, language: 'en-us', has_attachments: true})),
                    language_capabilities, callflows: {summaries: [], routes: []},
                    catalogs: Object.fromEntries(['users', 'media', 'numbers', 'system_media', 'callflows'].map(k => [k, {complete: true, reason: 'complete', count: 0, limit: 500}])),
                    revisions: {queue: '1-initial', users: Object.fromEntries(users.map(u => [u.id, '1-user'])), callflows: {}}};
            };
            window.openEditor = ({create = false, error = null, partialCatalog = null} = {}) => {
                window.requests = []; window.successes = 0; window.navigations = 0; window.writeError = error;
                window.deferEditorGet = false; window.deferredEditorReads = [];
                app.accountId = 'a'.repeat(32); app.appFlags.acdc.currentTab = 'queues';
                window.next = window.resultData();
                if (create) { window.next.queue = {}; window.next.roster = []; window.next.revisions.queue = null; }
                if (partialCatalog) window.next.catalogs[partialCatalog] = {complete: false, reason: 'limit_exceeded', count: 0, limit: 500};
                window.monster.request = options => {
                    window.requests.push({resource: options.resource, data: JSON.parse(JSON.stringify(options.data))});
                    if (['acdc.editor.new', 'acdc.editor.get'].includes(options.resource)) {
                        if (options.resource === 'acdc.editor.get' && window.deferEditorGet) {
                            window.deferEditorGet = false; window.deferredEditorReads.push(options); return;
                        }
                        return options.success({status: 'success', data: window.next});
                    }
                    if (!['acdc.editor.create', 'acdc.editor.update'].includes(options.resource)) throw new Error('Unexpected legacy API request ' + options.resource);
                    if (window.writeError) return options.error(window.writeError);
                    options.success({status: 'success', data: {state: 'complete', queue_id: window.qid, atomic: false, reload_required: true}});
                };
                app.renderQueueForm(create ? undefined : window.qid);
            };
            window.resolveEditorGet = (error = null) => {
                const options = window.deferredEditorReads.shift();
                if (!options) throw new Error('No deferred editor GET');
                if (error) options.error(error);
                else options.success({status: 'success', data: window.next});
            };
            window.submitEditor = () => {
                const form = document.querySelector('.acdc-queue-form'), valid = form.checkValidity();
                if (valid) form.dispatchEvent(new Event('submit', {bubbles: true, cancelable: true}));
                return {valid, requests: window.requests, successes: window.successes, navigations: window.navigations};
            };
        }, {template, translations, built: Boolean(stage)});
        let cases = 0;
        await page.evaluate(() => window.openEditor());
        assert.deepEqual((await page.evaluate(() => requests)).map(x => x.resource), ['acdc.editor.get']); cases++;
        const controls = await page.locator('select[name="announcements.language"] option').evaluateAll(items => items.map(x => ({value: x.value, disabled: x.disabled})));
        assert.deepEqual(controls.filter(x => x.value).map(x => x.value), ['en-us', 'ar-sa', 'he-il', 'es-es', 'fr-fr']); cases++;
        let result = await page.evaluate(() => window.submitEditor());
        assert(result.valid); assert.deepEqual(result.requests.map(x => x.resource), ['acdc.editor.get', 'acdc.editor.update']);
        const body = result.requests[1].data.data;
        assert.equal(body.roster.length, 30); assert.equal(body.queue.announcements.media.you_are_at_position, 'legacy-position');
        assert.equal(body.queue.callback.media.offer, 'legacy-callback'); assert.match(body.request_id, /^[a-f0-9]{32}$/);
        assert.equal(body.revisions.queue, '1-initial'); assert.equal(result.successes, 1); cases++;
        await page.evaluate(() => window.openEditor({create: true}));
        await page.locator('[name="name"]').fill('New isolated queue');
        result = await page.evaluate(() => window.submitEditor());
        assert.deepEqual(result.requests.map(x => x.resource), ['acdc.editor.new', 'acdc.editor.create']);
        assert.equal(result.requests[1].data.data.revisions.queue, null); cases++;
        await page.evaluate(() => window.openEditor({error: {message: 'operation_incomplete_reload_before_recovery',
            data: {queue_id: window.qid, phase: 'roster', state: 'partial', committed: [{phase: 'queue', ids: [window.qid]}], reload_required: true}}}));
        await page.locator('[name="name"]').fill('Not finalized');
        result = await page.evaluate(() => window.submitEditor()); assert.equal(result.successes, 0); assert.equal(result.navigations, 0);
        assert.equal(await page.locator('[name="name"]').inputValue(), 'Not finalized');
        assert.match(await page.locator('.acdc-form-error').textContent(), /Some changes may already be saved/); cases++;
        await page.locator('[name="name"]').fill('Keep edits made after failure');
        result = await page.evaluate(() => window.submitEditor()); assert.equal(result.requests.length, 2, 'A changed payload must not reuse the unresolved operation'); cases++;
        await page.evaluate(() => { window.next.revisions.queue = '2-current'; window.writeError = null; });
        await page.locator('.acdc-editor-recovery').click();
        assert.deepEqual(errors, [], 'Recovery rendering must not raise a browser exception');
        assert.equal(await page.locator('[name="name"]').count(), 1, 'Recovery must render a real queue form: ' + await page.locator('#content').textContent());
        assert.equal(await page.locator('[name="name"]').inputValue(), 'Keep edits made after failure');
        result = await page.evaluate(() => window.submitEditor());
        assert.equal(result.requests[3].data.data.revisions.queue, '2-current');
        assert.notEqual(result.requests[1].data.data.request_id, result.requests[3].data.data.request_id); cases++;
        await page.evaluate(() => window.openEditor({create: true, error: {message: 'Network outcome unknown'}}));
        await page.locator('[name="name"]').fill('Idempotent create'); await page.evaluate(() => window.submitEditor());
        await page.locator('.acdc-editor-recovery').click();
        result = await page.evaluate(() => ({requests: window.requests}));
        assert.deepEqual(result.requests[1].data, result.requests[2].data, 'Ambiguous create retry must send identical owner-scoped request ID and body'); cases++;
        await page.evaluate(() => window.openEditor({partialCatalog: 'callflows'}));
        assert(await page.locator('[name="route_extension"]').isDisabled());
        result = await page.evaluate(() => window.submitEditor()); assert.equal(result.requests[1].data.data.route, null); cases++;
        await page.evaluate(() => window.openEditor({partialCatalog: 'users'}));
        assert.equal(await page.locator('.acdc-queue-form').count(), 0, 'Incomplete users cannot render a writable roster'); cases++;
        const selectedRoster = ['2', '7'].map(id => id.padStart(32, '0'));
        const beginDeferredRecovery = async () => {
            const initial = await page.evaluate(() => {
                window.openEditor({error: {message: 'operation_incomplete_reload_before_recovery', data: {
                    queue_id: window.qid, operation_id: 'acdc_queue_editor_' + '0'.repeat(64), state: 'partial', phase: 'roster',
                    committed: [{phase: 'queue', ids: [window.qid]}], in_flight: [],
                    remaining: ['roster', 'route', 'finalize_extensions'], extension_claims: [], atomic: false, reload_required: true}}});
                const result = window.submitEditor();
                window.recoveryView = window.jQuery('.acdc-queue-editor');
                window.recoveryPending = window.recoveryView.data('editor-pending');
                window.recoveryPendingJson = JSON.stringify(window.recoveryPending);
                window.deferEditorGet = true;
                return result;
            });
            assert(initial.valid); assert.equal(initial.requests.length, 2);
            await page.locator('.acdc-editor-recovery').click();
            assert.deepEqual(await page.evaluate(() => ({reads: window.deferredEditorReads.length,
                requests: window.requests.map(r => r.resource), successes: window.successes, navigations: window.navigations})),
            {reads: 1, requests: ['acdc.editor.get', 'acdc.editor.update', 'acdc.editor.get'], successes: 0, navigations: 0});
            assert(await page.locator('[type="submit"]').isDisabled(), 'Save must wait for the recovery read');
            assert(await page.locator('.acdc-editor-recovery').isDisabled(), 'Duplicate recovery must wait');
            for (const selector of ['[name="name"]', '.acdc-roster', '[name="route_extension"]']) {
                assert.equal(await page.locator(selector).isDisabled(), false, 'Recovery must keep edits enabled: ' + selector);
            }
            const blocked = await page.evaluate(() => {
                // Exercise the handlers even though native clicks are disabled:
                // identical Save must not launch an overlapping write, nor may
                // a duplicate recovery action replace the outstanding read.
                const saved = window.submitEditor();
                window.jQuery('.acdc-editor-recovery').triggerHandler('click');
                return {valid: saved.valid, reads: window.deferredEditorReads.length, requests: window.requests.length,
                    unchangedPending: JSON.stringify(window.recoveryView.data('editor-pending')) === window.recoveryPendingJson};
            });
            assert.deepEqual(blocked, {valid: true, reads: 1, requests: 3, unchangedPending: true});
        };
        await beginDeferredRecovery();
        await page.locator('[name="name"]').fill('Latest edits while reload is pending');
        await page.locator('.acdc-roster').selectOption(selectedRoster);
        await page.locator('[name="route_extension"]').fill('2096');
        result = await page.evaluate(() => window.submitEditor());
        assert(result.valid); assert.equal(result.requests.length, 3, 'Edited Save must also wait for recovery GET');
        await page.evaluate(() => {
            window.next.queue.name = 'Server state before latest edits'; window.next.roster = [window.next.users[0].id];
            window.next.revisions.queue = '2-reloaded';
            window.next.revisions.users = Object.fromEntries(window.next.users.map(u => [u.id, '2-reloaded-user']));
            window.writeError = null; window.resolveEditorGet();
        });
        assert.equal(await page.locator('[name="name"]').inputValue(), 'Latest edits while reload is pending');
        assert.deepEqual(await page.locator('.acdc-roster').evaluate(e => Array.from(e.selectedOptions, o => o.value)), selectedRoster);
        assert.equal(await page.locator('[name="route_extension"]').inputValue(), '2096');
        assert.deepEqual(await page.evaluate(() => ({requests: window.requests.length, successes: window.successes, navigations: window.navigations})),
            {requests: 3, successes: 0, navigations: 0}, 'Recovery GET must not submit or report a saved queue');
        result = await page.evaluate(() => window.submitEditor()); assert(result.valid); assert.equal(result.requests.length, 4);
        const recoveredBody = result.requests[3].data.data;
        assert.equal(recoveredBody.queue.name, 'Latest edits while reload is pending'); assert.deepEqual(recoveredBody.roster, selectedRoster);
        assert.deepEqual(recoveredBody.route, {extension: '2096'}); assert.equal(recoveredBody.revisions.queue, '2-reloaded');
        assert.equal(Object.keys(recoveredBody.revisions.users).length, 30);
        assert(Object.values(recoveredBody.revisions.users).every(rev => rev === '2-reloaded-user'));
        assert.notEqual(recoveredBody.request_id, result.requests[1].data.data.request_id); cases++;
        await beginDeferredRecovery();
        await page.locator('[name="name"]').fill('Latest edits before failed reload');
        await page.locator('.acdc-roster').selectOption(selectedRoster);
        await page.locator('[name="route_extension"]').fill('2098');
        await page.evaluate(() => window.resolveEditorGet({message: 'Fixture recovery GET unavailable'}));
        assert.equal(await page.locator('[name="name"]').inputValue(), 'Latest edits before failed reload');
        assert.deepEqual(await page.locator('.acdc-roster').evaluate(e => Array.from(e.selectedOptions, o => o.value)), selectedRoster);
        assert.equal(await page.locator('[name="route_extension"]').inputValue(), '2098');
        assert.match(await page.locator('.acdc-form-error').textContent(), /Saved state could not be verified/);
        assert.deepEqual(await page.evaluate(() => ({sameView: window.jQuery('.acdc-queue-editor')[0] === window.recoveryView[0],
            samePending: window.recoveryView.data('editor-pending') === window.recoveryPending,
            unchangedPending: JSON.stringify(window.recoveryView.data('editor-pending')) === window.recoveryPendingJson,
            requests: window.requests.length, successes: window.successes, navigations: window.navigations})),
        {sameView: true, samePending: true, unchangedPending: true, requests: 3, successes: 0, navigations: 0});
        assert.equal(await page.locator('[type="submit"]').isDisabled(), false, 'A failed recovery read must restore Save');
        assert.equal(await page.locator('.acdc-editor-recovery').isDisabled(), false, 'A failed recovery read must allow explicit retry');
        assert.equal(await page.evaluate(() => Boolean(window.recoveryView.data('editor-recovery-pending'))), false);
        await page.evaluate(() => { window.deferEditorGet = true; });
        await page.locator('.acdc-editor-recovery').click();
        assert.deepEqual(await page.evaluate(() => ({reads: window.deferredEditorReads.length, requests: window.requests.length,
            writes: window.requests.filter(r => r.resource === 'acdc.editor.update').length})), {reads: 1, requests: 4, writes: 1});
        await page.evaluate(() => window.resolveEditorGet());
        assert.equal(await page.locator('[name="name"]').inputValue(), 'Latest edits before failed reload');
        assert.deepEqual(await page.locator('.acdc-roster').evaluate(e => Array.from(e.selectedOptions, o => o.value)), selectedRoster);
        assert.equal(await page.locator('[name="route_extension"]').inputValue(), '2098'); cases++;
        for (const departure of ['replacement', 'account', 'detached']) {
            await beginDeferredRecovery();
            const after = await page.evaluate(departure => {
                if (departure === 'replacement') {
                    window.app.renderQueueForm(window.qid);
                    window.jQuery('[name="name"]').val('Replacement editor stays visible');
                } else if (departure === 'account') window.app.accountId = 'c'.repeat(32);
                else { window.recoveryView.detach(); window.jQuery('#content').text('Original editor was removed'); }
                const content = document.querySelector('#content'), html = content.innerHTML;
                const currentView = content.querySelector('.acdc-queue-editor'), generation = window.app.appFlags.acdc.requestGeneration;
                window.resolveEditorGet();
                return {unchanged: content.innerHTML === html && content.querySelector('.acdc-queue-editor') === currentView,
                    generationUnchanged: window.app.appFlags.acdc.requestGeneration === generation,
                    requests: window.requests.length, reads: window.deferredEditorReads.length,
                    successes: window.successes, navigations: window.navigations};
            }, departure);
            assert.deepEqual(after, {unchanged: true, generationUnchanged: true, requests: departure === 'replacement' ? 4 : 3,
                reads: 0, successes: 0, navigations: 0}, 'Late recovery GET must ignore ' + departure); cases++;
        }
        assert.deepEqual(errors, []); assert.deepEqual(network, []);
        console.log(JSON.stringify({result: 'PASS', artifact: stage ? 'private_build_mocked_API' : 'source_mocked_API', cases, one_editor_GET: true, one_create_or_edit_write: true,
            legacy_prompts_preserved: true, revision_snapshot: true, idempotency_and_partial_recovery: true, network_requests: 0, live_writes: 0}));
    } finally { clearTimeout(deadline); await browser.close(); }
})().catch(error => { console.error(error.stack); process.exitCode = 1; });
