#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const http = require('node:http');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {execFileSync} = require('node:child_process');
const {build, operations, validateRefs} = require('./build-api-docs.cjs');
const {verify, checkTarget} = require('./verify-api-docs.cjs');
const Ajv = require('./api-docs-tooling/node_modules/ajv');
const root = path.resolve(__dirname, '..');
const committed = path.join(__dirname, 'assets/api-docs');
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
async function offline() {
    execFileSync(process.execPath, ['--test', path.join(__dirname, 'test-api-supervision-examples.cjs')],
        {stdio: 'pipe', timeout: 15000});
    const result = verify(committed);
    const spec = JSON.parse(fs.readFileSync(path.join(committed, 'openapi.json')));
    const coverage = JSON.parse(fs.readFileSync(path.join(committed, 'coverage.json')));
    assert.equal(operations(spec).length, coverage.operation_count);
    assert.equal(new Set(Object.keys(spec.paths).map(url => url.replace(/\{[^}]+\}/g, '{}'))).size, coverage.path_count);
    assert.equal(spec.paths['/accounts/{ACCOUNT_ID}/agents/status/{USER_ID}'].post['x-implementation-status'], 'known-invalid-alias');
    assert.equal(validateRefs(spec), coverage.internal_reference_count);
    for (const input of coverage.inputs) assert.equal(hash(path.join(root, input.file)), input.sha256, 'Stale input: ' + input.file);
    for (const input of coverage.source_inventory) assert.equal(hash(path.join(root, input.file)), input.sha256, 'Stale source inventory: ' + input.file);
    const channel = spec.paths['/accounts/{ACCOUNT_ID}/channels/{UUID}'].post;
    assert.equal(channel['x-contract-review'], 'source-reviewed');
    assert.deepEqual(channel.security, [{CrossbarToken: []}]);
    const guide = fs.readFileSync(path.join(committed, 'supervision.html'), 'utf8');
    for (const name of ['Whisper', 'Barge', 'Join', 'Listen']) {
        assert(channel.description.includes('## ' + name + '\n'));
        assert(guide.includes('<h2>' + name + '</h2>'));
        assert(guide.includes('How to call ' + name));
        assert(guide.includes('How to stop ' + name));
        assert(fs.readFileSync(path.join(committed, 'index.html'), 'utf8').includes('./supervision.html#' + name.toLowerCase()));
    }
    assert(channel.description.includes('same audio mode as Barge'));
    assert(channel.description.includes('not the top-level HTTP request_id'));
    assert(channel.description.includes('Actual distributed SIP/RTP acceptance passed on 2026-09-09'));
    assert(channel.description.includes('new actual-call retest passing on 2026-09-10'));
    assert(channel.description.includes('Main development deployment also passed actual calls'));
    assert(channel.description.includes('doc/main_dev_runtime_promotion.md'));
    assert(channel.description.includes('does not certify media-node failover'));
    assert(!/<script\b|\son\w+\s*=|javascript:/i.test(guide), 'Supervision guide must not execute calls');
    assert.equal(spec.components.schemas.MonitorStart.properties.timeout.default, 20);
    for (const status of ['202', '400', '401', '403', '404', '409', '503']) assert(channel.responses[status]);
    const ajv = new Ajv({strict: false, validateFormats: false});
    const validate = name => ajv.compile({components: spec.components, $ref: '#/components/schemas/' + name});
    const start = validate('MonitorStart'), stop = validate('MonitorStop'), callback = validate('CallbackPublic');
    const device_id = '0'.repeat(32), request_id = '1'.repeat(32);
    const websocket = spec.paths['/websocket'];
    assert.equal(websocket.servers[0].url, '/');
    assert(websocket.get.responses['101']);
    assert.deepEqual(websocket.get.security, []);
    assert.deepEqual(spec.paths['/websockets'].get.security, []);
    assert.equal(spec['x-blackhole'].externalDocs.url, '/apis/blackhole.html');
    assert(spec['x-blackhole'].acdc_dashboard.startsWith('Implemented in source; deployment-specific acceptance required:'));
    assert.equal(spec['x-blackhole'].queue_live.reconciliation_seconds, 15);
    assert.equal(spec['x-blackhole'].queue_live.selector, 'queue_live.changed.QUEUE_ID');
    assert(!Object.keys(spec.paths).some(url => url.includes('/websocket/subscribe')));
    for (const action of ['subscribe', 'unsubscribe']) {
        const wsValidate = validate(action === 'subscribe' ? 'BlackholeSubscribe' : 'BlackholeUnsubscribe');
        const command = {action, auth_token: 'synthetic-only', request_id, data: {account_id: device_id, binding: 'call.CHANNEL_ANSWER.*'}};
        assert(wsValidate(command));
        assert(wsValidate({...command, data: {bindings: ['call.CHANNEL_ANSWER.*']}}));
        for (const data of [{}, {bindings: []}, {binding: ''}, {binding: 'call.*.*', bindings: ['call.*.*']}, {bindings: 'call.*.*'}]) assert.equal(wsValidate({...command, data}), false);
        for (const key of ['action', 'auth_token', 'request_id', 'data']) {const missing = {...command}; delete missing[key]; assert.equal(wsValidate(missing), false);}
    }
    const wsResult = validate('BlackholeSubscriptionResult');
    assert(wsResult({subscribed: [], subscriptions: ['call.CHANNEL_ANSWER.*']}));
    assert.equal(wsResult({subscribed: 'call.CHANNEL_ANSWER.*', subscriptions: []}), false);
    const wsEvent = validate('BlackholeEvent');
    const event = {action: 'event', subscribed_key: 'call.CHANNEL_ANSWER.*', subscription_key: 'call.fixture.CHANNEL_ANSWER.*', name: 'CHANNEL_ANSWER', routing_key: 'call.fixture.CHANNEL_ANSWER.call', data: {call_id: 'call'}};
    assert(wsEvent(event));
    assert.equal(wsEvent({...event, action: 'reply'}), false);
    assert.equal(wsEvent({...event, data: null}), false);
    const wsPage = fs.readFileSync(path.join(committed, 'blackhole.html'), 'utf8');
    assert(wsPage.includes('Next.js client lifecycle'));
    assert(wsPage.includes('Company, queue and agent selection'));
    assert(wsPage.includes('Call supervision is an HTTP command'));
    assert(wsPage.includes('planned, not callable'));
    assert(wsPage.includes('Exact queue-live invalidation'));
    assert(wsPage.includes('15 seconds'));
    assert(wsPage.includes('matching success ACKs'));
    assert(spec['x-blackhole'].filtering.company.includes('data.account_id'));
    assert(spec['x-blackhole'].filtering.queue_and_agent.includes('no agent selector'));
    assert.equal(spec['x-blackhole'].inbound_limits.default_bytes, 65536);
    assert.equal(spec['x-blackhole'].inbound_limits.maximum_configured_bytes, 1048576);
    assert.deepEqual(Object.keys(spec['x-blackhole'].inbound_limits.close_codes).sort(), ['1003', '1007', '1009']);
    assert(spec.components.schemas.BlackholeSubscribe.properties.data.properties.binding.description.includes('never a queue or agent ID'));
    assert(wsPage.includes('native commands revalidate the connection token'));
    assert(wsPage.includes('matching token/account validation before delivery'));
    assert(wsPage.includes('best effort'));
    assert(!/<script\b|\son\w+\s*=|javascript:/i.test(wsPage), 'Protocol reference must not execute scripts or open sockets');
    assert(fs.readFileSync(path.join(committed, 'index.html'), 'utf8').includes('./blackhole.html'));
    for (const action of ['eavesdrop', 'whisper', 'barge', 'join']) assert(start({action, device_id}));
    for (const value of [{action: 'listen', device_id}, {action: 'whisper'}, {action: 'join', device_id, timeout: 4}, {action: 'join', device_id, timeout: 61}, {action: 'join', device_id, route: 'forbidden'}, {action: 'barge', device_id, timeout: '20'}]) assert.equal(start(value), false);
    assert(stop({action: 'stop_monitoring', request_id}));
    assert.equal(stop({action: 'stop_monitoring', request_id, device_id}), false);
    assert.equal(callback({status: 'queued', number: 'private-number'}), false);
    const schedule = spec.components.schemas.queues.properties.callback.properties.announcement;
    for (const method of ['post', 'patch']) {
        const description = spec.paths['/accounts/{ACCOUNT_ID}/queues/{QUEUE_ID}'][method].description;
        assert(description.includes('Account-local extension callbacks:'));
        assert(description.includes('resolved again on every attempt'));
        assert(description.includes('never falls back to a carrier'));
        assert(!description.includes('An ordinary internal extension alone is not an authorized outbound callback route'));
    }
    const validSchedule = ajv.compile(schedule);
    for (const data of [{}, {enabled: false}, {initial_delay: 1, interval: 15}, {initial_delay: 3600, interval: 3600}]) assert(validSchedule(data));
    for (const data of [{initial_delay: 0}, {interval: 14}, {interval: 3601}, {enabled: 'true'}]) assert.equal(validSchedule(data), false);
    const editorWrite = validate('QueueEditorWrite');
    const editorBody = {queue: {name: 'Example queue'}, roster: null, route: null, revisions: {queue: null, users: {}, callflows: {}}, request_id};
    assert(editorWrite(editorBody));
    assert(editorWrite({...editorBody, roster: [device_id], route: {extension: '*100'}}));
    for (const invalid of [{...editorBody, request_id: 'invalid'}, {...editorBody, roster: [device_id, device_id]},
        {...editorBody, roster: new Array(501).fill(device_id)}, {...editorBody, route: {extension: 'abc'}},
        {...editorBody, route: {extension: '100', extra: true}}, {...editorBody, unexpected: true},
        {...editorBody, queue: {id: device_id}}, {...editorBody, queue: {agents: []}}]) assert.equal(editorWrite(invalid), false);
    for (const field of Object.keys(editorBody)) {const missing = {...editorBody}; delete missing[field]; assert.equal(editorWrite(missing), false);}
    const editorSettings = validate('QueueEditorSettings');
    const builtinAdoption = {announcements: {language: 'en-us', media: null},
        callback: {media: null, return_confirmation_prompt: null}};
    assert(editorSettings(builtinAdoption), 'PATCH must accept prompt deletion markers');
    for (const locale of ['en-us', 'he-il', 'fr-fr', 'es-es', 'ar-sa']) {
        assert(editorSettings({...builtinAdoption, announcements: {language: locale, media: null}}));
    }
    for (const media of [false, 42, 'recording', []]) {
        assert.equal(editorSettings({callback: {media}}), false);
        assert.equal(editorSettings({announcements: {media}}), false);
    }
    const editorCreate = validate('QueueEditorCreateSettings');
    assert(editorCreate({name: 'New queue', announcements: {language: 'en-us'}}));
    assert.equal(editorCreate({name: 'New queue', ...builtinAdoption}), false,
        'Creation must not inherit PATCH-only nullable prompt maps');
    assert.equal(spec.components.schemas.queues.properties.callback.properties.media.nullable, undefined,
        'PATCH overlay must not mutate the persisted/create queue schema');
    assert.equal(spec.components.schemas.QueueEditorCatalogState.properties.missing_prompt_ids.maxItems, 57);
    const catalogState = validate('QueueEditorCatalogState');
    const incompleteMedia = {complete: false, reason: 'english_media_prerequisites_incomplete',
        count: 0, limit: 500, missing_prompt_ids: Array.from({length: 57}, (_,i) => 'missing-' + i)};
    assert(catalogState(incompleteMedia));
    assert.equal(catalogState({...incompleteMedia, missing_prompt_ids: [...incompleteMedia.missing_prompt_ids, 'extra']}), false);
    assert(spec.components.schemas.QueueEditorSettings.description.includes('deletion marker'));
    const editorPatch = spec.paths['/accounts/{ACCOUNT_ID}/queues/{QUEUE_ID}/editor'].patch;
    assert(editorWrite(editorPatch.requestBody.content['application/json'].examples.builtinQueueLanguage.value.data));
    assert.equal(spec.paths['/accounts/{ACCOUNT_ID}/queues/editor'].put.requestBody.content['application/json'].schema.properties.data.$ref,
        '#/components/schemas/QueueEditorCreateWrite');
    const editorRecovery = validate('QueueEditorRecovery');
    const recovery = {queue_id: device_id, operation_id: 'acdc_queue_editor_' + '0'.repeat(64), state: 'running', phase: 'reserve_extensions',
        committed: [], in_flight: [], remaining: ['reserve_extensions', 'queue', 'roster', 'route', 'finalize_extensions'], extension_claims: [], atomic: false, reload_required: true};
    const claim = {id: 'acdc_queue_extension_' + '1'.repeat(64), extension: '100', revision: '1-example'};
    assert(editorRecovery(recovery));
    assert(editorRecovery({...recovery, phase: 'finalize_extensions', extension_claims: [claim]}));
    assert(editorRecovery({...recovery, state: 'complete', phase: 'complete', remaining: []}));
    for (const invalid of [{...recovery, phase: 'takeover'}, {...recovery, remaining: ['automatic_rollback']},
        {...recovery, extension_claims: [claim, claim, claim]}, {...recovery, extension_claims: [{...claim, id: device_id}]},
        {...recovery, extension_claims: [{...claim, extension: ''}]}, {...recovery, extension_claims: undefined}]) assert.equal(editorRecovery(invalid), false);
    for (const [url, method] of [['/accounts/{ACCOUNT_ID}/queues/editor', 'put'], ['/accounts/{ACCOUNT_ID}/queues/{QUEUE_ID}/editor', 'patch']]) {
        assert(spec.paths[url].get.responses['200']);
        assert(spec.paths[url][method].responses['409']);
        assert.equal(spec.paths[url][method]['x-implementation-status'], 'implemented-in-source; latest-revision-not-live-verified');
        assert.equal(spec.paths[url].get['x-implementation-status'], 'implemented-in-source; latest-revision-not-live-verified');
        assert(spec.paths[url][method]['x-live-verification'].coverage.includes('Historical checkpoint'));
        assert.equal(spec.paths[url][method]['x-live-verification'].host, 'kz5.talkchief.io');
    }
    assert(spec.components.schemas.QueueEditorRecovery.description.includes('nonempty revision'));
    assert(spec.paths['/accounts/{ACCOUNT_ID}/queues/{QUEUE_ID}/callbacks']);
    assert(spec.paths['/accounts/{ACCOUNT_ID}/queues/editor'].put.responses['201']);
    assert.equal(spec.components.schemas.QueueEditorSnapshot.required.includes('language_capabilities'), false);
    assert.deepEqual(spec.components.schemas.QueueEditorLanguageCapabilities.oneOf,
        [{$ref: '#/components/schemas/QueueEditorLanguageCapabilitiesV1'}, {$ref: '#/components/schemas/QueueEditorLanguageCapabilitiesV2'}]);
    assert.deepEqual(spec.components.schemas.QueueEditorLanguageCapabilitiesV1.properties.backend_mode.enum, ['legacy']);
    const cardinal = spec.components.schemas.QueueEditorLanguageCapabilitiesV2;
    assert.deepEqual(cardinal.properties.backend_mode.enum, ['prerecorded-cardinal-v1']);
    assert.equal(cardinal.additionalProperties, false);
    for (const [locale, count] of Object.entries({'en-us': 31, 'he-il': 131, 'fr-fr': 161, 'es-es': 53, 'ar-sa': 208})) {
        const entry = cardinal.properties.languages.properties[locale];
        assert.equal(entry.additionalProperties, false);
        assert.deepEqual(entry.properties.numeric_prompt_count.enum, [count]);
        assert.deepEqual(entry.properties.callback_prompt_count.enum, [42]);
        assert(entry.required.includes('selection_ready') && entry.required.includes('native_review_sha256'));
    }
    const members = spec.paths['/accounts/{ACCOUNT_ID}/members/devices'].get;
    assert.equal(members['x-implementation-status'], 'implemented-source-reviewed');
    for (const [route, verbs] of [
        ['/accounts/{ACCOUNT_ID}/scope_restrictions', ['get', 'put']],
        ['/accounts/{ACCOUNT_ID}/scope_restrictions/{SCOPE_RESTRICTION}', ['get', 'post', 'delete']]
    ]) for (const verb of verbs) {
        const op = spec.paths[route][verb];
        assert(op.description.includes('requires a native account administrator or superadmin'));
        assert(op.description.includes('do not delete an assigned policy'));
        assert(op.responses['403']);
        assert.deepEqual(op.security, [{CrossbarToken: []}]);
        assert.equal(op['x-contract-review'], 'upstream-generated; not individually verified');
        assert.match(op['x-auth-source-sha256'], /^[a-f0-9]{64}$/);
    }
    assert.equal(members['x-required-integration'].built_in_custom_route, 'members');
    assert.equal(members['x-required-integration'].preserve_existing_custom_routes, true);
    assert.equal(members.responses['200'].headers['Cache-Control'].schema.enum[0], 'no-store');
    const planned = JSON.parse(fs.readFileSync(path.join(committed, 'planned.openapi.json')));
    assert(!planned.paths['/accounts/{ACCOUNT_ID}/members/devices'], 'Implemented route must leave the planned catalog');
    const installer = fs.readFileSync(path.join(__dirname, 'install-kazoo5.sh'), 'utf8');
    assert.equal(installer.split('location = /apis { return 308 /apis/; }').length - 1, 2);
    assert.equal(installer.split('location ^~ /apis/').length - 1, 2);
    const monsterInstall = installer.match(/install_monster_ui\(\) \{[\s\S]*?\n\}/)[0];
    assert(monsterInstall.lastIndexOf('    install_api_developer_docs\n') > monsterInstall.indexOf('deploy_monster_ui_owned'));
    assert(monsterInstall.includes('deploy_monster_ui_owned'));
    assert(!monsterInstall.includes('rsync -a --delete'));
    const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'kazoo-api-docs-test-'));
    try {
        const oldMask = process.umask(0o077);
        try {await build(temp);} finally {process.umask(oldMask);}
        assert.doesNotThrow(() => verify(temp), 'Restrictive generator umask must still produce nginx-readable public assets');
        assert.deepEqual(checkTarget(temp), {target: 'safe'});
        assert.deepEqual(checkTarget(path.join(temp, 'not-created')), {target: 'safe'});
        fs.mkdirSync(path.join(temp, 'target'));
        fs.symlinkSync(path.join(temp, 'vendor'), path.join(temp, 'target/vendor'), 'dir');
        assert.throws(() => checkTarget(path.join(temp, 'target')), /symlink/);
        fs.symlinkSync(temp, path.join(temp, 'ancestor-link'), 'dir');
        assert.throws(() => checkTarget(path.join(temp, 'ancestor-link', 'new-webroot', 'apis')), /symlink/);
        fs.mkdirSync(path.join(temp, 'hardlinked-target'));
        fs.writeFileSync(path.join(temp, 'unrelated-owned-file'), 'must not be overwritten');
        fs.linkSync(path.join(temp, 'unrelated-owned-file'), path.join(temp, 'hardlinked-target', 'portal.js'));
        assert.throws(() => checkTarget(path.join(temp, 'hardlinked-target')), /hardlinked/);
        assert.throws(() => verify(path.join(temp, 'hardlinked-target')), /hardlinked/);
        assert.equal(fs.readFileSync(path.join(temp, 'unrelated-owned-file'), 'utf8'), 'must not be overwritten');
        const installFunction = installer.match(/install_api_developer_docs\(\) \{[\s\S]*?\n\}/)[0];
        // Exercise the actual installer function, simulating cp -a preserving
        // a restrictive previous build. Every write stays in this test tree.
        execFileSync('bash', ['-c', `set -euo pipefail
run() {
    "$@"
    if [[ $1 == cp ]]; then
        chmod 0700 "$MONSTER_UI_WEB_ROOT/apis" "$MONSTER_UI_WEB_ROOT/apis/vendor"
        chmod 0600 "$MONSTER_UI_WEB_ROOT/apis/index.html"
    fi
}
die() { echo "$*" >&2; exit 1; }
${installFunction}
install_api_developer_docs
`], {env: {...process.env, DRY_RUN: 'false', SCRIPT_DIR: __dirname, MONSTER_UI_WEB_ROOT: path.join(temp, 'webroot')}, stdio: 'pipe'});
        assert.doesNotThrow(() => verify(path.join(temp, 'webroot/apis')));
        const manifest = JSON.parse(fs.readFileSync(path.join(committed, 'manifest.json')));
        for (const item of manifest.files) assert.equal(hash(path.join(temp, item.file)), item.sha256, 'Regeneration changed ' + item.file);
        assert.equal(hash(path.join(temp, 'manifest.json')), hash(path.join(committed, 'manifest.json')));
        fs.appendFileSync(path.join(temp, 'portal.js'), '\n// tamper test\n');
        assert.throws(() => verify(temp), /Wrong byte length/);
    } finally {fs.rmSync(temp, {recursive: true, force: true});}
    console.log(JSON.stringify({offline: 'PASS', ...result, schema_negative_cases: 31, blackhole_schema_negative_cases: 21, deterministic_rebuild: 'PASS', tamper_detection: 'PASS'}));
}
async function browser() {
    const {chromium} = require(process.env.KAZOO_PLAYWRIGHT_MODULE || 'playwright');
    const installer = fs.readFileSync(path.join(__dirname, 'install-kazoo5.sh'), 'utf8');
    const csp = installer.match(/add_header Content-Security-Policy "([^"]+)" always;/)[1];
    const requests = [], denied = [], errors = [];
    const server = http.createServer((req, res) => {
        const url = new URL(req.url, 'http://localhost');
        const relative = url.pathname === '/apis/' ? 'index.html' : url.pathname.replace(/^\/apis\//, '');
        const file = path.resolve(committed, relative);
        if (!file.startsWith(committed + path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile()) {res.writeHead(404); res.end(); return;}
        const types = {'.json': 'application/json', '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css'};
        res.writeHead(200, {'Content-Type': types[path.extname(file)] || 'text/plain', 'Content-Security-Policy': csp, 'X-Content-Type-Options': 'nosniff'});
        res.end(fs.readFileSync(file));
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const origin = 'http://127.0.0.1:' + server.address().port;
    const browser = await chromium.launch({headless: true});
    try {
        const context = await browser.newContext({serviceWorkers: 'block'});
        await context.route('**/*', route => {
            const request = route.request(), url = new URL(request.url());
            requests.push(request.method() + ' ' + url.pathname);
            if (url.origin !== origin || request.method() !== 'GET' || !url.pathname.startsWith('/apis/')) {denied.push(request.url()); return route.abort();}
            return route.continue();
        });
        const page = await context.newPage();
        page.on('pageerror', e => errors.push(e.message));
        page.on('console', message => {if (message.type() === 'error') errors.push(message.text());});
        await page.goto(origin + '/apis/?url=https://example.invalid/injected.json', {waitUntil: 'networkidle'});
        try {await page.waitForSelector('.opblock-tag', {timeout: 10000});}
        catch (error) {console.error(JSON.stringify({errors, requests, denied, page: (await page.locator('body').innerText()).slice(0,1800)})); throw error;}
        const total = await page.evaluate(() => Object.values(window.kazooApiDocs.specSelectors.specJson().toJS().paths)
            .reduce((sum, item) => sum + ['get', 'put', 'post', 'patch', 'delete', 'head', 'options'].filter(method => item[method]).length, 0));
        const expected = JSON.parse(fs.readFileSync(path.join(committed, 'coverage.json'))).operation_count;
        assert.equal(total, expected);
        await page.locator('.opblock-tag').filter({hasText: 'Call supervision'}).click();
        const monitor = page.locator('.opblock-post').filter({hasText: 'Listen, whisper, barge, join, or stop supervision'});
        await monitor.locator('.opblock-summary').click();
        assert.equal(await page.getByRole('button', {name: 'Try it out', exact: true}).count(), 0);
        const safeguard = await page.evaluate(() => {
            const ui = window.kazooApiDocs;
            ui.authActions.authorize({CrossbarToken: {name: 'CrossbarToken', value: 'synthetic-test-only'}});
            const config = ui.getConfigs();
            let rejected = false;
            try {config.requestInterceptor({url: location.origin + '/v2/accounts', method: 'POST', headers: {}});} catch (_) {rejected = true;}
            return {authorization: ui.authSelectors.authorized().toJS(), rejected, methods: config.supportedSubmitMethods, validator: config.validatorUrl};
        });
        assert.deepEqual(safeguard, {authorization: {}, rejected: true, methods: [], validator: null});
        await page.getByRole('button', {name: 'Planned APIs — not implemented', exact: true}).click();
        await page.waitForFunction(() => document.querySelector('.swagger-ui .title')?.textContent.includes('PLANNED'));
        assert.equal(await page.evaluate(() => Object.keys(window.kazooApiDocs.specSelectors.specJson().toJS().paths).length), 0);
        assert.equal(await page.locator('#catalog-status').textContent(), 'PLANNED ONLY — these routes are not implemented or deployed. Do not call them.');
        await page.getByRole('button', {name: 'Current source catalog', exact: true}).click();
        await page.waitForFunction(() => document.querySelector('.swagger-ui .title')?.textContent.includes('source catalog'));
        await page.locator('.opblock-tag').filter({hasText: 'Blackhole WebSocket'}).click();
        const upgrade = page.locator('.opblock-get').filter({hasText: 'Upgrade to the native Blackhole WebSocket transport'});
        await upgrade.locator('.opblock-summary').click();
        await upgrade.getByText('101', {exact: true}).waitFor({state: 'visible'});
        assert((await upgrade.innerText()).includes('101'));
        await page.getByRole('link', {name: 'Blackhole / Next.js integration', exact: true}).click();
        await page.waitForURL(origin + '/apis/blackhole.html');
        assert.equal(await page.getByRole('heading', {name: 'Next.js client lifecycle', exact: true}).count(), 1);
        assert.equal(await page.getByRole('heading', {name: 'Company, queue and agent selection', exact: true}).count(), 1);
        assert.equal(await page.getByRole('heading', {name: 'Call supervision is an HTTP command', exact: true}).count(), 1);
        assert((await page.locator('body').innerText()).includes('planned, not callable'));
        assert.equal(await page.locator('script').count(), 0);
        assert((await page.locator('body').innerText()).includes('best effort'));
        await page.goto(origin + '/apis/');
        await page.getByRole('link', {name: 'Whisper', exact: true}).click();
        await page.waitForURL(origin + '/apis/supervision.html#whisper');
        for (const name of ['Whisper', 'Barge', 'Join', 'Listen']) {
            assert.equal(await page.getByRole('heading', {name, exact: true}).count(), 1);
            assert.equal(await page.getByRole('heading', {name: 'How to call ' + name, exact: true}).count(), 1);
            assert.equal(await page.getByRole('heading', {name: 'How to stop ' + name, exact: true}).count(), 1);
        }
        assert.equal(await page.locator('script').count(), 0);
        assert.deepEqual(denied, []);
        assert.deepEqual(errors, []);
        assert(requests.every(line => !line.includes('/v2/')));
        console.log(JSON.stringify({browser: 'PASS', operations_loaded: total, request_count: requests.length, external_requests: denied.length, console_errors: errors.length, try_it_out: 'disabled', authorization_storage: 'disabled', planned_isolation: 'PASS', blackhole_reference: 'PASS'}));
    } finally {await browser.close(); await new Promise(resolve => server.close(resolve));}
}
(async () => {await offline(); if (process.argv.includes('--browser')) await browser();})().catch(e => {console.error(e.stack); process.exit(1);});
