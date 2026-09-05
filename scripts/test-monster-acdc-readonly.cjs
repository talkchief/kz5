'use strict';
// Real browser rendering/serialization without submitting any queue, route,
// roster, status, or account changes. Authentication is the sole allowed write.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {chromium} = require(process.env.KAZOO_PLAYWRIGHT_MODULE || 'playwright');
const deploymentProfile = process.env.KAZOO_TEST_ACDC_PROFILE || 'staged';
assert(['staged', 'baseline'].includes(deploymentProfile), 'Unknown expected ACDC deployment profile');
const baselineProfile = deploymentProfile === 'baseline';
assert(!baselineProfile || process.env.KAZOO_TEST_QUEUE_EDITOR !== 'true', 'Baseline must not use the aggregate editor');
assert(!baselineProfile || process.env.KAZOO_TEST_ACDC_STAGE, 'Baseline preview requires a pinned private build');
const secretsPath = process.env.KAZOO_INSTALLER_SECRETS || '/etc/kazoo/installer-secrets.env';
const stat = fs.lstatSync(secretsPath);
assert(stat.isFile() && !stat.isSymbolicLink() && stat.uid === 0 && (stat.mode & 0o777) === 0o600,
    'Master credentials must be a root-owned 0600 regular file');
const secrets = Object.fromEntries(fs.readFileSync(secretsPath, 'utf8').split('\n')
    .filter(line => line && !line.startsWith('#')).map(line => {
        const index = line.indexOf('=');
        assert(index > 0, 'Malformed credential record');
        return [line.slice(0, index), line.slice(index + 1)];
    }));

(async () => {
    const browser = await chromium.launch({headless: true});
    const deadline = setTimeout(() => browser.close().catch(() => {}), 120000);
    const errors = [], blockedWrites = [], failedResponses = [], queueResponses = [];
    const requestCounts = {}, responseCounts = {};
    const editorRequests = [], separateEditorCatalogRequests = [];
    const apiOrigins = new Set();
    const aggregateEditor = process.env.KAZOO_TEST_QUEUE_EDITOR === 'true';
    let observingEditorLoad = false;
    let stagedAssetsServed = 0;
    let stagedAppScriptsServed = 0;
    const previewShellServed = new Set();
    let page;
    try {
        page = await browser.newPage({viewport: {width: 1600, height: 1000}});
        page.on('pageerror', error => errors.push(error.message));
        page.on('request', request => {
            const requestUrl = new URL(request.url()), pathname = requestUrl.pathname;
            if (pathname.startsWith('/v2/')) apiOrigins.add(requestUrl.origin);
            const category = pathname.startsWith('/v2/') ? pathname.replace(/\/accounts\/[^/]+/, '/accounts/ACCOUNT')
                .replace(/\/media\/prompts\/[^/]+/, '/media/prompts/PROMPT').replace(/[a-f0-9]{32}/g, 'ID') : undefined;
            if (category) requestCounts[category] = (requestCounts[category] || 0) + 1;
            if (baselineProfile && /\/queues\/(?:[a-f0-9]{32}\/)?editor$/.test(pathname)) {
                editorRequests.push(`${request.method()} ${pathname}`);
            }
            if (!aggregateEditor || !observingEditorLoad) return;
            if (/\/queues\/(?:[a-f0-9]{32}\/)?editor$/.test(pathname)) editorRequests.push(`${request.method()} ${pathname}`);
            if (/\/accounts\/[a-f0-9]{32}\/(?:users|media|phone_numbers|callflows)(?:\/|$)/.test(pathname)
                || /\/queues\/[a-f0-9]{32}\/roster$/.test(pathname)
                || /\/v2\/media(?:\/|$)/.test(pathname)) separateEditorCatalogRequests.push(`${request.method()} ${pathname}`);
        });
        page.on('console', message => {
            if (message.type() === 'error' && message.text().startsWith('This api does not exist.')) {
                errors.push(message.text());
            }
        });
        page.on('response', response => {
            const pathname = new URL(response.url()).pathname;
            const category = pathname.startsWith('/v2/') ? pathname.replace(/\/accounts\/[^/]+/, '/accounts/ACCOUNT')
                .replace(/\/media\/prompts\/[^/]+/, '/media/prompts/PROMPT').replace(/[a-f0-9]{32}/g, 'ID') : undefined;
            if (category) responseCounts[category] = (responseCounts[category] || 0) + 1;
            if (response.status() >= 400) failedResponses.push(`${response.status()} ${new URL(response.url()).pathname}`);
            if (new URL(response.url()).pathname.endsWith('/queues') && response.request().method() === 'GET') {
                response.json().then(body => queueResponses.push({keys: Object.keys(body),
                    isArray: Array.isArray(body.data), count: body.data && body.data.length,
                    hasNext: Boolean(body.next_start_key)})).catch(() => {});
            }
        });
        await page.route('**/v2/**', async route => {
            const request = route.request(), url = new URL(request.url());
            if (['GET', 'HEAD', 'OPTIONS'].includes(request.method()) ||
                (url.pathname === '/v2/user_auth' && request.method() === 'PUT')) return route.continue();
            blockedWrites.push(`${request.method()} ${url.pathname}`);
            return route.abort();
        });
        if (process.env.KAZOO_TEST_ACDC_STAGE) {
            const stage = fs.realpathSync(process.env.KAZOO_TEST_ACDC_STAGE);
            assert(stage.startsWith('/usr/local/src/kazoo5-installer/monster-acdc-'), 'Unexpected private build fixture path');
            const appRoot = path.join(stage, 'dist/apps/acdc');
            if (baselineProfile) {
                const manifest = JSON.parse(fs.readFileSync(path.join(stage, 'baseline-build.json')));
                const overlay = require('./build-acdc-baseline-ui.cjs');
                assert.equal(manifest.base_commit, overlay.BASE);
                assert.equal(manifest.release_type, 'temporary-legacy-editor-overlay');
                assert.equal(manifest.aggregate_editor_included, false);
                assert.equal(manifest.language_readiness_published, false);
                assert.equal(manifest.overlay_sha256, overlay.digest(fs.readFileSync(path.join(__dirname, 'build-acdc-baseline-ui.cjs'))));
                for (const [relative, expected] of Object.entries(manifest.files)) {
                    const filename = path.resolve(stage, relative);
                    assert(filename.startsWith(stage + '/') && !relative.includes('..'));
                    assert.equal(crypto.createHash('sha256').update(fs.readFileSync(filename)).digest('hex'), expected);
                }
                assert(!fs.existsSync(path.join(appRoot, 'language-capabilities.json')), 'Baseline cannot publish readiness');
            }
            // Production may preload an older named AMD module in main.js.
            // Overlaying app assets alone never replaces that cached module.
            // Preview the exact deployer's shell transform in memory, leaving
            // every other definition and live filesystem byte untouched.
            const acorn = require('/usr/local/src/kazoo5-installer/monster-ui/node_modules/acorn');
            const webRoot = '/var/www/html/monster-ui';
            const main = fs.readFileSync(path.join(webRoot, 'js/main.js'), 'utf8');
            const tree = acorn.parse(main, {ecmaVersion: 2018}), definitions = [], stack = [tree];
            while (stack.length) {
                const node = stack.pop();
                if (node.type === 'CallExpression' && node.callee.type === 'Identifier' && node.callee.name === 'define'
                    && node.arguments[0] && node.arguments[0].type === 'Literal' && node.arguments[0].value === 'apps/acdc/app') {
                    definitions.push(node);
                }
                for (const value of Object.values(node)) {
                    if (Array.isArray(value)) {
                        for (const child of value) if (child && typeof child.type === 'string') stack.push(child);
                    } else if (value && typeof value.type === 'string') stack.push(value);
                }
            }
            assert(definitions.length <= 1, 'Ambiguous embedded ACDC preview definitions');
            const span = definitions[0];
            const previewMain = span ? main.slice(0, span.start) + 'void 0' + main.slice(span.end) : main;
            acorn.parse(previewMain, {ecmaVersion: 2018});
            const build = JSON.parse(fs.readFileSync(path.join(webRoot, 'build-config.json'), 'utf8'));
            for (const key of ['preloadApps', 'preloadedApps']) {
                if (Array.isArray(build[key])) build[key] = build[key].filter(name => name !== 'acdc');
            }
            for (const [pathname, contentType, body] of [['/js/main.js', 'application/javascript', previewMain],
                ['/build-config.json', 'application/json', JSON.stringify(build)]]) {
                await page.route('**' + pathname + '*', route => {
                    assert.equal(new URL(route.request().url()).pathname, pathname, 'Unexpected preview shell path');
                    assert.equal(route.request().method(), 'GET', 'Preview shell must be read-only');
                    previewShellServed.add(pathname);
                    return route.fulfill({status: 200, contentType, body});
                });
            }
            await page.route('**/apps/acdc/**', async route => {
                const pathname = decodeURIComponent(new URL(route.request().url()).pathname);
                const relative = pathname.slice(pathname.indexOf('/apps/acdc/') + '/apps/acdc/'.length);
                const file = path.resolve(appRoot, relative);
                assert(file.startsWith(appRoot + '/'), 'Unsafe private fixture asset');
                assert.equal(route.request().method(), 'GET', 'Fixture assets must be read-only');
                if (!fs.existsSync(file)) {
                    // Installer-owned readiness comes from the live publisher,
                    // never a source/build fixture's unsupported ready claim.
                    if (relative === 'language-capabilities.json') return route.continue();
                    return route.fulfill({status: 404, body: ''});
                }
                assert(fs.lstatSync(file).isFile(), 'Fixture asset must be a regular file');
                stagedAssetsServed++;
                if (relative === 'app.js') stagedAppScriptsServed++;
                return route.fulfill({path: file});
            });
        }
        await page.goto(process.env.KAZOO_TEST_UI_URL || 'http://127.0.0.1/', {waitUntil: 'networkidle', timeout: 45000});
        await page.locator('#login').fill(secrets.KAZOO_MASTER_ADMIN_USER || 'admin');
        await page.locator('#password').fill(secrets.KAZOO_MASTER_ADMIN_PASSWORD);
        await page.locator('#account_name').fill(process.env.KAZOO_TEST_ACCOUNT_NAME || 'KazooMaster');
        const authentication = page.waitForResponse(response =>
            new URL(response.url()).pathname === '/v2/user_auth' && response.request().method() === 'PUT');
        await page.getByRole('button', {name: 'Sign in', exact: true}).click();
        const auth = await authentication;
        assert(auth.ok() && (await auth.json()).status === 'success', 'Browser authentication failed');
        await page.locator('#login').waitFor({state: 'hidden', timeout: 30000});
        await page.waitForLoadState('networkidle', {timeout: 30000});
        await page.waitForFunction(() => window.require('monster').apps.auth.appsStore !== undefined);
        const catalog = await page.evaluate(() => {
            const monster = window.require('monster'), metadata = monster.util.getAppStoreMetadata('acdc');
            const assigned = monster.apps.auth.currentUser.appList || [];
            return {visible: Boolean(metadata && assigned.some(item =>
                typeof item === 'string' ? item === metadata.id : item && (item.id === metadata.id || item.name === 'acdc'))),
                name: metadata && metadata.name,
                availableApps: Object.values(monster.apps.auth.appsStore || {}).map(app => app.name).sort()};
        });
        assert(catalog.visible && catalog.name === 'acdc', 'Call Center is not assigned in the app catalog');
        await page.waitForTimeout(1500);
        const accountPanelOpen = await page.locator('#myaccount').evaluate(element => element.classList.contains('myaccount-open'));
        if (accountPanelOpen) {
            await page.locator('#monster_content').waitFor({state: 'hidden', timeout: 10000});
            await page.evaluate(() => window.require('monster').pub('myaccount.hide'));
            await page.locator('#monster_content').waitFor({state: 'visible', timeout: 10000});
        }
        await page.evaluate(() => {
            const monster = window.require('monster');
            monster.routing.goTo('apps/acdc');
        });
        await page.locator('#acdc_wrapper .acdc-summary-grid').waitFor({state: 'visible', timeout: 30000});
        await page.locator('.acdc-tab[data-tab="queues"]').click();
        let rosterEvidence, orderEvidence;
        if (process.env.KAZOO_TEST_MASTER_ROSTER === 'true') {
            const queueId = process.env.KAZOO_TEST_MASTER_QUEUE_ID || '6729981c1d697e88aa31921eb6bad2da';
            assert(/^[a-f0-9]{32}$/.test(queueId));
            observingEditorLoad = true;
            const rosterResponse = page.waitForResponse(response =>
                new URL(response.url()).pathname.endsWith(`/queues/${queueId}/${aggregateEditor ? 'editor' : 'roster'}`) && response.request().method() === 'GET');
            await page.locator(`.acdc-edit-queue[data-id="${queueId}"]`).click();
            const response = await rosterResponse, body = await response.json();
            if (!aggregateEditor) assert.equal(new URL(response.url()).searchParams.get('paginate'), 'false');
            assert.equal(body.status, 'success');
            const roster = aggregateEditor ? body.data.roster : body.data;
            assert(Array.isArray(roster) && roster.length === 30 && !body.next_start_key);
            await page.locator('.acdc-queue-form').waitFor({state: 'visible', timeout: 30000});
            observingEditorLoad = false;
            if (aggregateEditor) {
                assert.equal(body.data.catalogs.users.complete, true);
                assert.equal(editorRequests.length, 1, 'Existing queue form must load through one aggregate GET');
                assert.deepEqual(separateEditorCatalogRequests, [], 'Aggregate editor must not fan out browser catalog requests');
            }
            const selection = await page.locator('.acdc-roster').evaluate(element => ({disabled: element.disabled,
                selected: Array.from(element.selectedOptions, option => option.value).sort()}));
            assert.equal(selection.disabled, false);
            assert.deepEqual(selection.selected, roster.slice().sort(), 'Every current agent must remain selected in the editor');
            rosterEvidence = {current_members: roster.length, selected_members: selection.selected.length,
                complete_inventory: true, writes: 0};
            if (process.env.KAZOO_TEST_IN_ORDER === 'true') {
                await page.locator('[name="strategy"]').selectOption('in_order');
                await page.locator('.acdc-agent-order-section').waitFor({state: 'visible'});
                const before = await page.locator('.acdc-agent-order-item').evaluateAll(elements => elements.map(element => ({
                    id: element.dataset.agentId, name: element.querySelector('.acdc-agent-order-name').textContent
                })));
                assert.equal(before.length, 30);
                assert(before.every(item => item.name && !item.name.includes(item.id)), 'Priority list must show names, not IDs');
                await page.locator('.acdc-agent-order-item').first().locator('[data-direction="1"]').click();
                orderEvidence = await page.evaluate(() => {
                    const app = window.require('monster').apps.acdc, $ = window.require('jquery');
                    const payload = app.serializeQueue($('.acdc-queue-form'), true);
                    return {strategy: payload.strategy, order: payload.agent_order,
                        parallel_limit_hidden: $('[name="ring_simultaneously"]').attr('type') === 'hidden'};
                });
                const expected = before.map(item => item.id);
                [expected[0], expected[1]] = [expected[1], expected[0]];
                assert.deepEqual(orderEvidence.order, expected, 'Move-down must serialize the exact changed priority');
                assert.equal(orderEvidence.strategy, 'in_order');
                assert.equal(orderEvidence.parallel_limit_hidden, true);
                orderEvidence = {real_named_members: 30, moved_one_step: true, serialized_unique_members: new Set(expected).size,
                    strategy: 'in_order', writes: 0, parallel_limit_hidden: true};
            }
            await page.locator('.acdc-cancel').first().click();
        }
        const existingEditorRequests = editorRequests.length;
        observingEditorLoad = true;
        await page.locator('.acdc-add-queue').click();
        await page.locator('.acdc-queue-form').waitFor({state: 'visible', timeout: 30000});
        observingEditorLoad = false;
        if (aggregateEditor) {
            assert.equal(editorRequests.length - existingEditorRequests, 1, 'New queue form must load through one aggregate GET');
            assert.deepEqual(separateEditorCatalogRequests, [], 'Aggregate editor must not fan out browser catalog requests');
        }
        const requiredControls = ['callback.enabled', 'callback.use_local_resources', 'callback.entry_key',
            'callback.allow_alternate_number', 'callback.outbound_authority.id', 'callback.caller_id_source',
            'callback.max_attempts', 'callback.retry_delay', 'callback.ttl', 'announcements.language',
            'announcements.position_announcements_enabled', 'announcements.wait_time_announcements_enabled'];
        if (process.env.KAZOO_TEST_INITIAL_DELAY === 'true') requiredControls.push('announcements.initial_delay');
        if (process.env.KAZOO_TEST_CALLBACK_ANNOUNCEMENT === 'true') {
            requiredControls.push('callback.announcement.enabled', 'callback.announcement.initial_delay', 'callback.announcement.interval');
        }
        for (const name of requiredControls) {
            assert(await page.locator(`[name="${name}"]`).isVisible(), `Missing rendered control ${name}`);
        }
        const legacyPromptFields = ['announcements.media.you_are_at_position', 'announcements.media.in_the_queue',
            'announcements.media.the_estimated_wait_time_is', 'announcements.media.increase_in_call_volume',
            'callback.media.offer', 'callback.media.menu', 'callback.media.number_readback', 'callback.media.confirmation',
            'callback.media.success', 'callback.media.returned_confirmation'];
        const legacyPromptEvidence = await page.locator('.acdc-queue-form').evaluate((form, names) => names.map(name => {
            const controls = form.querySelectorAll(`[name="${name}"]`), control = controls[0];
            return {name, count: controls.length, tag: control && control.tagName,
                type: control && control.type, required: control && control.required};
        }), legacyPromptFields);
        assert(baselineProfile ? legacyPromptEvidence.every(control => control.count === 0)
            : legacyPromptEvidence.every(control => control.count === 1 && control.tag === 'INPUT'
                && control.type === 'hidden' && control.required === false),
        'Legacy prompt overrides must be preserved internally without custom recording selectors or required hidden fields: '
            + JSON.stringify(legacyPromptEvidence));
        const dropdownEvidence = await page.locator('.acdc-queue-form').evaluate(form => {
            const names = ['callback.outbound_authority.id', 'callback.caller_id_source',
                'callback.outbound_caller_id.number', 'announcements.language', 'moh', 'announce'];
            const controls = Object.fromEntries(names.map(name => {
                const element = form.querySelector(`[name="${name}"]`);
                return [name, {tag: element.tagName, disabled: element.disabled, choices: element.options.length}];
            }));
            const users = Array.from(form.querySelector('[name="callback.outbound_authority.id"]').options)
                .filter(option => option.value && option.dataset.authorityType === 'user' && option.dataset.preserved !== 'true');
            const languageOptions = Array.from(form.querySelector('[name="announcements.language"]').options)
                .filter(option => option.value).map(option => ({locale: option.value, label: option.textContent,
                    disabled: option.disabled, preserved: option.dataset.preserved === 'true'}));
            const languages = languageOptions.filter(option => !option.disabled && !option.preserved).map(option => option.locale);
            return {controls, named_users: users.length, first_user: users[0] && users[0].value,
                users_have_names: users.every(option => option.textContent !== option.value), languages, language_options: languageOptions,
                authority_type_hidden: form.querySelector('[name="callback.outbound_authority.type"]').type === 'hidden',
                caller_name_hidden: form.querySelector('[name="callback.outbound_caller_id.name"]').type === 'hidden'};
        });
        for (const control of Object.values(dropdownEvidence.controls)) {
            assert.equal(control.tag, 'SELECT');
            assert.equal(control.disabled, false, 'Live catalogs must be complete for this acceptance run');
        }
        assert(dropdownEvidence.named_users > 0 && dropdownEvidence.users_have_names);
        assert(dropdownEvidence.authority_type_hidden && dropdownEvidence.caller_name_hidden);
        assert(dropdownEvidence.languages.includes('en-us'));
        if (process.env.KAZOO_TEST_LANGUAGE_CAPABILITIES === 'true') {
            assert.deepEqual(dropdownEvidence.language_options.map(option => option.locale).sort(),
                ['en-us', 'ar-sa', 'he-il', 'es-es', 'fr-fr'].sort());
            if (process.env.KAZOO_TEST_READY_LANGUAGES) {
                assert.deepEqual(dropdownEvidence.languages.slice().sort(), process.env.KAZOO_TEST_READY_LANGUAGES.split(',').sort());
            }
            assert(dropdownEvidence.language_options.filter(option => option.disabled).every(option => option.label.includes('Not installed or incomplete')));
        }
        await page.locator('[name="callback.outbound_authority.id"]').selectOption(dropdownEvidence.first_user);
        await page.locator('[name="callback.caller_id_source"]').selectOption('inherit');
        assert.equal(await page.locator('[name="callback.outbound_caller_id.number"]').isVisible(), false);
        const serialization = await page.evaluate(() => {
            const monster = window.require('monster'), $ = window.require('jquery'), app = monster.apps.acdc;
            const form = $('.acdc-queue-form');
            form.find('[name="name"]').val('Unsaved browser serialization probe');
            form.find('[name="announcements.language"]').val('en-us');
            for (const name of ['callback.enabled', 'callback.use_local_resources',
                'announcements.position_announcements_enabled', 'announcements.wait_time_announcements_enabled']) {
                form.find(`[name="${name}"]`).prop('checked', true).trigger('change');
            }
            const payload = app.serializeQueue(form, false);
            const recovery = app.formatCallback({status: 'connecting', reconciliation_required: true,
                reconciliation_reason: 'engine_restart'});
            return {payload, valid: form[0].checkValidity(), conflict: app.callbackKeyError(form) || app.callbackSelectionError(form),
                recovery, registeredMethods: Object.keys(app.requests).filter(key => key.startsWith('acdc.callbacks.')).sort()};
        });
        assert(serialization.valid && serialization.conflict === null, 'Rendered callback form failed local validation');
        const callback = serialization.payload.callback;
        assert.equal(callback.enabled, true);
        assert.equal(callback.use_local_resources, true);
        assert.equal(callback.allow_alternate_number, false);
        assert.equal(callback.entry_key, '6');
        assert.equal(callback.caller_id_source, 'inherit');
        assert.equal(callback.outbound_authority.type, 'user');
        assert.equal(callback.outbound_authority.id, dropdownEvidence.first_user);
        assert.equal(Object.hasOwn(callback, 'outbound_caller_id'), false);
        assert.equal(Object.hasOwn(callback, 'media'), false, 'Fresh callbacks must use built-in prompt defaults');
        if (baselineProfile) {
            assert.equal(Object.hasOwn(serialization.payload.announcements, 'media'), false,
                'Baseline creation must omit custom prompt fields and use backend defaults');
        } else {
            assert.deepEqual(serialization.payload.announcements.media, {
                you_are_at_position: 'queue-you_are_at_position', in_the_queue: 'queue-in_the_queue',
                the_estimated_wait_time_is: 'queue-the_estimated_wait_time_is', increase_in_call_volume: 'queue-increase_in_call_volume'
            }, 'Fresh queue announcements must serialize real default prompts, not empty overrides');
        }
        let callbackAnnouncementEvidence;
        if (process.env.KAZOO_TEST_CALLBACK_ANNOUNCEMENT === 'true') {
            assert.deepEqual(callback.announcement, {enabled: true, initial_delay: 30, interval: 60});
            callbackAnnouncementEvidence = await page.evaluate(() => {
                const app = window.require('monster').apps.acdc, $ = window.require('jquery'),
                    view = $('.acdc-queue-editor'), form = view.find('.acdc-queue-form'),
                    enabled = form.find('[name="callback.announcement.enabled"]'),
                    initial = form.find('[name="callback.announcement.initial_delay"]'),
                    interval = form.find('[name="callback.announcement.interval"]'),
                    beforePosition = app.serializeQueue(form, true).announcements;
                const numericRequired = [initial[0], interval[0]].every(element =>
                    element.type === 'number' && element.required && !element.disabled);
                const invalidValuesRejected = [[initial, '0'], [initial, '3601'], [initial, '1.5'],
                    [interval, '14'], [interval, '3601'], [interval, '15.5']].every(([field, value]) => {
                    field.val(value);
                    return !field[0].checkValidity();
                });
                initial.val('12'); interval.val('75');
                const configured = app.serializeQueue(form, true).callback.announcement;
                enabled.prop('checked', false).trigger('change');
                app.setFormBusy(view, true); app.setFormBusy(view, false);
                const disabledTiming = [initial[0], interval[0]].every(element => element.disabled);
                const offPayload = app.serializeQueue(form, true);
                const callbackKeyStillAvailable = offPayload.callback.enabled && offPayload.callback.entry_key === '6'
                    && !app.callbackKeyError(form) && !app.callbackSelectionError(form);
                enabled.prop('checked', true).trigger('change');
                const restoredTiming = [initial[0], interval[0]].every(element => !element.disabled);
                const positionUnchanged = JSON.stringify(app.serializeQueue(form, true).announcements) === JSON.stringify(beforePosition);
                initial.val('30'); interval.val('60');
                return {numericRequired, invalidValuesRejected, configured, disabledTiming, off: offPayload.callback.announcement,
                    callbackKeyStillAvailable, restoredTiming, positionUnchanged, valid: form[0].checkValidity()};
            });
            assert.deepEqual(callbackAnnouncementEvidence, {numericRequired: true, invalidValuesRejected: true,
                configured: {enabled: true, initial_delay: 12, interval: 75}, disabledTiming: true, off: {enabled: false},
                callbackKeyStillAvailable: true, restoredTiming: true, positionUnchanged: true, valid: true});
        }
        await page.locator('[name="callback.caller_id_source"]').selectOption('custom');
        assert(await page.locator('[name="callback.outbound_caller_id.number"]').isVisible());
        const customSelection = await page.locator('[name="callback.outbound_caller_id.number"]').evaluate(element => ({
            required: element.required, valid: element.checkValidity(), number_choices: element.options.length - 1
        }));
        assert.equal(customSelection.required, true);
        assert.equal(customSelection.valid, false, 'An empty custom caller ID must not pass form validation');
        await page.locator('[name="callback.caller_id_source"]').selectOption('inherit');
        const catalogSafetyEvidence = await page.evaluate(() => {
            const app = window.require('monster').apps.acdc, $ = window.require('jquery');
            // Detached copies exercise failure handling without replacing the
            // real rendered form or changing any account configuration.
            const view = $('.acdc-queue-editor').clone(false), form = view.find('.acdc-queue-form');
            const queue = app.defaultQueue();
            queue.moh = 'https://legacy.invalid/existing-music.wav';
            queue.announcements.language = 'legacy-locale';
            queue.callback.outbound_authority = {type: 'device', id: 'missing-legacy-device'};
            queue.callback.outbound_caller_id = {number: '+12025550999', name: 'Existing callback identity'};
            app.populateQueueDropdowns(view, queue, {users: [], media: [], numbers: [], verifiedSystemMedia: []},
                {media: 'incomplete', systemMedia: 'incomplete', numbers: 'incomplete'}, true);
            app.setFormBusy(view, true);
            app.setFormBusy(view, false);
            const payload = app.serializeQueue(form, true);
            return {partial_catalog_selectors_readonly: form.find('.acdc-catalog-readonly').get().every(element => element.disabled),
                warning_visible: !view.find('.acdc-catalog-warning').hasClass('hidden'),
                unknown_media_preserved: payload.moh === queue.moh,
                unknown_language_preserved: payload.announcements.language === queue.announcements.language,
                legacy_device_preserved: payload.callback.outbound_authority.type === 'device'
                    && payload.callback.outbound_authority.id === queue.callback.outbound_authority.id,
                legacy_identity_preserved: JSON.stringify(payload.callback.outbound_caller_id) === JSON.stringify(queue.callback.outbound_caller_id),
                legacy_source_absent: !Object.prototype.hasOwnProperty.call(payload.callback, 'caller_id_source')};
        });
        assert(Object.values(catalogSafetyEvidence).every(Boolean), 'Incomplete catalogs must preserve every existing setting');
        let baselineEvidence;
        if (baselineProfile) {
            baselineEvidence = await page.evaluate(() => {
                const app = window.require('monster').apps.acdc, $ = window.require('jquery'), _ = window.require('lodash');
                const view = $('.acdc-queue-editor').clone(false), form = view.find('.acdc-queue-form');
                const queue = app.defaultQueue();
                queue.announcements.media.you_are_at_position = 'fixture-custom-position';
                queue.callback.media.offer = 'fixture-immutable-offer';
                queue.callback.return_confirmation_prompt = 'fixture-legacy-return';
                app.populateQueueDropdowns(view, queue, {users: [], media: [], numbers: [], verifiedSystemMedia: []},
                    {media: 'incomplete', systemMedia: 'incomplete', numbers: 'incomplete'}, true);
                const payload = app.serializeQueue(form, true), saved = _.merge(_.cloneDeep(queue), payload);
                const state = form.data('preserved-prompt-overrides');
                return {editor_route_absent: !Object.values(app.requests).some(request => /\/editor/.test(request.url)),
                    prompt_fields_omitted: !Object.hasOwn(payload.announcements, 'media') && !Object.hasOwn(payload.callback, 'media')
                        && !Object.hasOwn(payload.callback, 'return_confirmation_prompt'),
                    original_state_retained: state.announcements.you_are_at_position === queue.announcements.media.you_are_at_position
                        && state.callback.offer === queue.callback.media.offer && state.return_confirmation_prompt === queue.callback.return_confirmation_prompt,
                    saved_overrides_preserved: saved.announcements.media.you_are_at_position === queue.announcements.media.you_are_at_position
                        && saved.callback.media.offer === queue.callback.media.offer && saved.callback.return_confirmation_prompt === queue.callback.return_confirmation_prompt};
            });
            assert(Object.values(baselineEvidence).every(Boolean), 'Baseline prompt preservation or API contract failed');
        }
        assert.equal(serialization.payload.announcements.language, 'en-us');
        assert.equal(serialization.payload.announcements.position_announcements_enabled, true);
        assert.equal(serialization.payload.announcements.wait_time_announcements_enabled, true);
        let initialDelayEvidence;
        if (process.env.KAZOO_TEST_INITIAL_DELAY === 'true') {
            assert.equal(serialization.payload.announcements.initial_delay, 30);
            initialDelayEvidence = await page.evaluate(() => {
                const app = window.require('monster').apps.acdc, $ = window.require('jquery');
                const form = $('.acdc-queue-form'), delay = form.find('[name="announcements.initial_delay"]');
                delay.val('0');
                const rejectsZero = !delay[0].checkValidity();
                delay.val('3601');
                const rejectsAboveMaximum = !delay[0].checkValidity();
                delay.val('37');
                form.find('[name="announcements.interval"]').val('45');
                const payload = app.serializeQueue(form, false);
                return {rejectsZero, rejectsAboveMaximum, initial_delay: payload.announcements.initial_delay,
                    interval: payload.announcements.interval, valid: form[0].checkValidity()};
            });
            assert.deepEqual(initialDelayEvidence, {rejectsZero: true, rejectsAboveMaximum: true,
                initial_delay: 37, interval: 45, valid: true});
        }
        const schema = JSON.parse(fs.readFileSync('/opt/kz5/applications/crossbar/priv/couchdb/schemas/queues.json', 'utf8'));
        if (initialDelayEvidence) {
            const definition = schema.properties.announcements.properties.initial_delay;
            assert.equal(definition.type, 'integer');
            assert.equal(definition.default, 30);
            assert.equal(definition.minimum, 1);
            assert.equal(definition.maximum, 3600);
        }
        for (const [key, value] of Object.entries(callback)) {
            const definition = schema.properties.callback.properties[key];
            assert(definition, `Serialized callback property missing from queue schema: ${key}`);
            if (definition.type === 'integer') {
                assert(Number.isInteger(value), `${key} must serialize as integer`);
                if (definition.minimum !== undefined) assert(value >= definition.minimum, `${key} below schema minimum`);
                if (definition.maximum !== undefined) assert(value <= definition.maximum, `${key} above schema maximum`);
            } else if (definition.type === 'boolean') assert.equal(typeof value, 'boolean');
        }
        assert.deepEqual(serialization.registeredMethods, ['acdc.callbacks.cancel', 'acdc.callbacks.list']);
        let callflowsEvidence;
        if (process.env.KAZOO_TEST_CALLFLOWS_ACDC === 'true') {
            const queueId = process.env.KAZOO_TEST_MASTER_QUEUE_ID || '6729981c1d697e88aa31921eb6bad2da';
            assert(/^[a-f0-9]{32}$/.test(queueId), 'Invalid expected master queue ID');
            await page.evaluate(() => window.require('monster').routing.goTo('apps/callflows'));
            await page.locator('#callflow_container .entity-manager .callflow-element').click();
            await page.locator('#callflow_container .callflow-edition .list-add').click();
            const action = page.locator('.action[name="acdc_member[id=*]"]');
            await action.waitFor({state: 'attached', timeout: 30000});
            if (!await action.isVisible()) {
                await action.locator('xpath=ancestor::div[contains(@class,"category")]').locator('.open').click();
            }
            assert(await action.isVisible(), 'ACDC Queue palette action is not visible');
            const target = page.locator('#ws_cf_flow .node[name="root"]');
            await target.waitFor({state: 'visible', timeout: 15000});
            await action.scrollIntoViewIfNeeded();
            const start = await action.boundingBox(), end = await target.boundingBox();
            assert(start && end, 'Actual draggable/drop-target coordinates unavailable');
            await page.evaluate(() => {
                window.acdcDragEvidence = [];
                const $ = window.require('jquery');
                $('.action[name="acdc_member[id=*]"]').on('dragstart.acdcReadOnlyProbe', () => window.acdcDragEvidence.push('dragstart'));
                $('#ws_cf_flow .node[name="root"]').on('drop.acdcReadOnlyProbe', () => window.acdcDragEvidence.push('drop'));
            });
            await page.mouse.move(start.x + start.width / 2, start.y + start.height / 2);
            await page.mouse.down();
            await page.mouse.move(start.x + start.width / 2 + 8, start.y + start.height / 2 + 8, {steps: 3});
            await page.mouse.move(end.x + end.width / 2, end.y + end.height / 2, {steps: 20});
            await page.mouse.up();
            const selector = page.locator('#acdc_queue_selector');
            await selector.waitFor({state: 'visible', timeout: 15000});
            const queueName = await selector.locator(`option[value="${queueId}"]`).textContent();
            assert(queueName && queueName.trim(), 'Master queue 2000 is absent from the real queue selector');
            await selector.selectOption(queueId);
            await page.locator('[data-action="save-acdc-queue"]').click();
            await selector.waitFor({state: 'detached', timeout: 15000});
            callflowsEvidence = await page.evaluate(() => {
                const app = window.require('monster').apps.callflows;
                return {actionListed: app.actions['acdc_member[id=*]'].isListed,
                    serialized: app.flow.root.children[0].serialize(),
                    nodeCaption: app.flow.root.children[0].caption,
                    unsaved: !app.flow.id};
            });
            assert.equal(callflowsEvidence.actionListed, true);
            assert.equal(callflowsEvidence.unsaved, true, 'Test must use a new unsaved canvas');
            assert.deepEqual(callflowsEvidence.serialized, {module: 'acdc_member', data: {id: queueId}, children: {}});
            assert.equal(callflowsEvidence.nodeCaption, queueName.trim());
            if (process.env.KAZOO_TEST_UI_SCREENSHOT) {
                await page.screenshot({path: process.env.KAZOO_TEST_UI_SCREENSHOT, fullPage: true});
            }
        }
        assert.deepEqual(blockedWrites, [], 'Browser attempted a non-authentication API write');
        assert.deepEqual(errors, [], 'Browser JavaScript errors');
        assert.deepEqual(failedResponses, [], 'Read-only browser HTTP requests must not fail');
        if (process.env.KAZOO_TEST_SAME_ORIGIN_API === 'true') {
            assert.deepEqual([...apiOrigins], [new URL(page.url()).origin],
                'Every browser API request must use the UI origin');
        }
        if (baselineProfile) assert.deepEqual(editorRequests, [], 'Baseline must never request an aggregate editor endpoint');
        if (process.env.KAZOO_TEST_ACDC_STAGE) {
            assert(stagedAppScriptsServed > 0, 'Private ACDC application JavaScript was not actually loaded');
            assert.deepEqual(Array.from(previewShellServed).sort(), ['/build-config.json', '/js/main.js'],
                'Private component preview must exercise the actual deployment shell transform');
        }
        const evidence = {result: 'PASS', checked_at: new Date().toISOString(), catalog, rendered_controls: requiredControls.length,
            expected_deployment_profile: deploymentProfile, baseline: baselineEvidence,
            artifact: process.env.KAZOO_TEST_ACDC_STAGE ? 'private_build_fixture' : 'live_deployment',
            staged_assets_served: stagedAssetsServed, staged_app_scripts_served: stagedAppScriptsServed,
            preview_shell_served: Array.from(previewShellServed).sort(), roster: rosterEvidence, hidden_legacy_prompt_fields: legacyPromptEvidence,
            dropdowns: {...dropdownEvidence, first_user: undefined, custom_selection: customSelection,
                isolated_catalog_fault_checks: catalogSafetyEvidence},
            callback_serialization_matches_schema: true, api_writes_other_than_authentication: 0,
            javascript_errors: 0, http_failures: failedResponses.length,
            api_origins: [...apiOrigins].sort(),
            same_origin_api_verified: process.env.KAZOO_TEST_SAME_ORIGIN_API === 'true',
            aggregate_editor: aggregateEditor ? {get_requests: editorRequests.length,
                separate_catalog_requests: separateEditorCatalogRequests.length, live_writes: 0} : undefined,
            initial_delay: initialDelayEvidence, callback_announcement: callbackAnnouncementEvidence,
            ordered_ringing: orderEvidence, callflows: callflowsEvidence};
        if (process.env.KAZOO_TEST_UI_EVIDENCE) {
            const evidencePath = path.resolve(process.env.KAZOO_TEST_UI_EVIDENCE);
            assert(evidencePath.startsWith('/var/log/kazoo-acceptance/'), 'Evidence must stay in the acceptance log directory');
            const descriptor = fs.openSync(evidencePath, 'wx', 0o600);
            try { fs.writeFileSync(descriptor, JSON.stringify(evidence, null, 2) + '\n'); }
            finally { fs.closeSync(descriptor); }
        }
        console.log(JSON.stringify(evidence));
    } catch (error) {
        const diagnostic = page && await page.evaluate(() => {
            const monster = window.require('monster');
            return {hash: location.hash, acdcLoaded: Boolean(monster.apps.acdc),
                contentDisplay: getComputedStyle(document.querySelector('#monster_content')).display,
                acdcCount: document.querySelectorAll('#acdc_wrapper').length,
                dragEvents: window.acdcDragEvidence,
                dialogTitles: Array.from(document.querySelectorAll('.ui-dialog-title')).map(element => element.textContent),
                queueSelectors: document.querySelectorAll('#acdc_queue_selector').length,
                queueForms: document.querySelectorAll('.acdc-queue-form').length,
                statePanels: document.querySelectorAll('.acdc-state').length,
                requestGeneration: monster.apps.acdc && monster.apps.acdc.appFlags.acdc.requestGeneration,
                templateNames: Object.keys(monster.cache.templates.acdc && monster.cache.templates.acdc._main || {}),
                verifiedMediaCount: monster.apps.acdc && monster.apps.acdc.appFlags.acdc.verifiedSystemMedia
                    && monster.apps.acdc.appFlags.acdc.verifiedSystemMedia.media.length,
                callflowChildren: monster.apps.callflows && monster.apps.callflows.flow.root &&
                    monster.apps.callflows.flow.root.children.map(child => child.actionName)};
        }).catch(() => ({}));
        throw new Error(`${error.message}; ${JSON.stringify({diagnostic, errors, blockedWrites, failedResponses, queueResponses, requestCounts, responseCounts})}`);
    } finally {
        clearTimeout(deadline);
        await browser.close();
    }
})().catch(error => { console.error('Read-only ACDC browser FAIL: ' + error.message); process.exitCode = 1; });
