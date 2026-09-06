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
    assert.equal(spec.components.schemas.MonitorStart.properties.timeout.default, 20);
    for (const status of ['202', '400', '401', '403', '404', '409', '503']) assert(channel.responses[status]);
    const ajv = new Ajv({strict: false, validateFormats: false});
    const validate = name => ajv.compile({components: spec.components, $ref: '#/components/schemas/' + name});
    const start = validate('MonitorStart'), stop = validate('MonitorStop'), callback = validate('CallbackPublic');
    const device_id = '0'.repeat(32), request_id = '1'.repeat(32);
    for (const action of ['eavesdrop', 'whisper', 'barge', 'join']) assert(start({action, device_id}));
    for (const value of [{action: 'listen', device_id}, {action: 'whisper'}, {action: 'join', device_id, timeout: 4}, {action: 'join', device_id, timeout: 61}, {action: 'join', device_id, route: 'forbidden'}, {action: 'barge', device_id, timeout: '20'}]) assert.equal(start(value), false);
    assert(stop({action: 'stop_monitoring', request_id}));
    assert.equal(stop({action: 'stop_monitoring', request_id, device_id}), false);
    assert.equal(callback({status: 'queued', number: 'private-number'}), false);
    const schedule = spec.components.schemas.queues.properties.callback.properties.announcement;
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
        assert.equal(spec.paths[url][method]['x-implementation-status'], 'implemented-in-source; isolated-live-verified-2026-09-05');
        assert.equal(spec.paths[url][method]['x-live-verification'].host, 'kz5.talkchief.io');
    }
    assert(spec.paths['/accounts/{ACCOUNT_ID}/queues/{QUEUE_ID}/callbacks']);
    assert(spec.paths['/accounts/{ACCOUNT_ID}/queues/editor'].put.responses['201']);
    assert.equal(spec.components.schemas.QueueEditorSnapshot.required.includes('language_capabilities'), false);
    assert.deepEqual(spec.components.schemas.QueueEditorLanguageCapabilities.properties.backend_mode.enum, ['legacy']);
    const members = spec.paths['/accounts/{ACCOUNT_ID}/members/devices'].get;
    assert.equal(members['x-implementation-status'], 'implemented-source-reviewed');
    assert.equal(members['x-required-integration'].built_in_custom_route, 'members');
    assert.equal(members['x-required-integration'].preserve_existing_custom_routes, true);
    assert.equal(members.responses['200'].headers['Cache-Control'].schema.enum[0], 'no-store');
    const planned = JSON.parse(fs.readFileSync(path.join(committed, 'planned.openapi.json')));
    assert(!planned.paths['/accounts/{ACCOUNT_ID}/members/devices'], 'Implemented route must leave the planned catalog');
    const installer = fs.readFileSync(path.join(__dirname, 'install-kazoo5.sh'), 'utf8');
    assert.equal(installer.split('location = /apis { return 308 /apis/; }').length - 1, 2);
    assert.equal(installer.split('location ^~ /apis/').length - 1, 2);
    assert(installer.indexOf('    install_api_developer_docs\n') > installer.indexOf('rsync -a --delete'));
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
    console.log(JSON.stringify({offline: 'PASS', ...result, schema_negative_cases: 31, deterministic_rebuild: 'PASS', tamper_detection: 'PASS'}));
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
        assert.deepEqual(denied, []);
        assert.deepEqual(errors, []);
        assert(requests.every(line => !line.includes('/v2/')));
        console.log(JSON.stringify({browser: 'PASS', operations_loaded: total, request_count: requests.length, external_requests: denied.length, console_errors: errors.length, try_it_out: 'disabled', authorization_storage: 'disabled', planned_isolation: 'PASS'}));
    } finally {await browser.close(); await new Promise(resolve => server.close(resolve));}
}
(async () => {await offline(); if (process.argv.includes('--browser')) await browser();})().catch(e => {console.error(e.stack); process.exit(1);});
