'use strict';
// Strict live browser regression. Only local read requests and user_auth are
// allowed; edits stay on unsaved canvases. No HAR, trace, cookie or frame dumps.
const fs = require('node:fs'), path = require('node:path'), dns = require('node:dns').promises;
const os = require('node:os'), assert = require('node:assert/strict');
const MASTER = '302ae5a70c403124f764cbc54229cfcd';
const QUEUE = '6729981c1d697e88aa31921eb6bad2da';
function urlPath(value) {
    try { const u = new URL(value); return u.protocol + '//' + u.host + u.pathname; }
    catch { return '[invalid-url]'; }
}
function sanitize(value, secrets = []) {
    let result = String(value);
    for (const secret of secrets.filter(s => typeof s === 'string' && s.length > 3)) result = result.split(secret).join('[redacted]');
    return result.replace(/\b(?:https?|wss?):\/\/[^\s"'<>]+/g, urlPath)
        .replace(/\?[^\s"'<>]*/g, '?[redacted]')
        .replace(/\b(?:auth[_-]?token|authorization|password|credentials|cookie|secret)\b["'\s]*[:=][^,}\n]*/gi, '[credential-redacted]')
        .replace(/\b[a-f0-9]{32,}\b/gi, '[hex-redacted]').slice(0, 1000);
}
function protectedSecrets(file) {
    const st = fs.lstatSync(file);
    assert(st.isFile() && !st.isSymbolicLink() && st.uid === 0 && (st.mode & 0o777) === 0o600, 'Credentials must be root-owned 0600 regular file');
    return Object.fromEntries(fs.readFileSync(file, 'utf8').split('\n').filter(s => s && !s.startsWith('#')).map(s => {
        const index = s.indexOf('='); assert(index > 0, 'Malformed protected credentials'); return [s.slice(0, index), s.slice(index + 1)];
    }));
}
function isRead(method) { return ['GET', 'HEAD', 'OPTIONS'].includes(method); }
function isStaticFont(method, url, headers) {
    return ['GET', 'HEAD'].includes(method) && !headers.authorization && !headers.cookie && !url.username && !url.password
        && !Array.from(url.searchParams.keys()).some(k => /key|token|auth|secret|password/i.test(k))
        && ((url.hostname === 'fonts.googleapis.com' && /^\/css2?$/.test(url.pathname))
            || (url.hostname === 'fonts.gstatic.com' && /^\/s\/[A-Za-z0-9_./-]+\.(woff2?|ttf|otf)$/.test(url.pathname)));
}
function unique(items) { return [...new Set(items)]; }
if (process.argv.includes('--self-test')) {
    assert.equal(urlPath('https://u:p@host/path?token=secret#secret'), 'https://host/path');
    const cleaned = sanitize('password=topsecret https://host/path?auth_token=topsecret aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', ['topsecret']);
    assert(!cleaned.includes('topsecret') && !cleaned.includes('aaaaaaaa') && !cleaned.includes('auth_token'));
    assert(isRead('GET') && !isRead('POST') && !isRead('PUT'));
    assert(isStaticFont('GET', new URL('https://fonts.googleapis.com/css?family=Lato'), {}));
    assert(isStaticFont('GET', new URL('https://fonts.gstatic.com/s/lato/v1/example.woff2'), {}));
    assert(!isStaticFont('GET', new URL('https://fonts.googleapis.com/css?key=secret'), {}));
    assert(!isStaticFont('GET', new URL('https://maps.google.com/maps/api/js'), {}));
    console.log('PASS console harness redaction and write guards');
} else {
    main().catch(error => { console.error('Console harness failed: ' + sanitize(error.message)); process.exitCode = 1; });
}

async function main() {
    process.umask(0o077);
    assert.equal(process.getuid(), 0, 'Protected MASTER browser test requires root');
    const target = new URL(process.env.KAZOO_TEST_UI_URL || 'http://kz5.talkchief.io/');
    assert(['http:', 'https:'].includes(target.protocol) && !target.username && !target.password && !target.search && !target.hash, 'Unexpected UI URL');
    const localAddresses = new Set(['127.0.0.1', '::1', ...Object.values(os.networkInterfaces()).flat().filter(Boolean).map(x => x.address)]);
    const resolved = await dns.lookup(target.hostname, {all: true});
    assert(resolved.length && resolved.every(x => localAddresses.has(x.address)), 'UI hostname must resolve only to this server');
    const allowedHosts = new Set([target.hostname, 'localhost', ...localAddresses]);
    let stageRoot;
    if (process.env.KAZOO_TEST_WEB_STAGE) {
        const candidate = path.resolve(process.env.KAZOO_TEST_WEB_STAGE), st = fs.lstatSync(candidate);
        assert(st.isDirectory() && !st.isSymbolicLink() && st.uid === 0, 'Private web stage must be a root-owned directory');
        stageRoot = fs.realpathSync(candidate);
        assert(stageRoot.startsWith('/tmp/kazoo-') || stageRoot.startsWith('/usr/local/src/kazoo5-installer/monster-'), 'Unexpected private web stage location');
    }
    const secrets = protectedSecrets(process.env.KAZOO_INSTALLER_SECRETS || '/etc/kazoo/installer-secrets.env');
    assert(secrets.KAZOO_MASTER_ADMIN_PASSWORD, 'Missing protected MASTER password');
    const secretValues = Object.values(secrets);
    const {chromium} = require(process.env.KAZOO_PLAYWRIGHT_MODULE || '/tmp/kazoo-ui-browser.eXdEqS/node_modules/playwright');
    const browser = await chromium.launch({headless: true});
    const timeout = setTimeout(() => browser.close().catch(() => {}), 180000);
    const raw = {console: [], page_errors: [], failed_requests: [], failed_responses: [], blocked_writes: [], external_requests: [], static_fonts: []};
    const stagedAssets = new Set();
    const stages = [], handshakes = [], wsPaths = new Map();
    let authWrites = 0, page, websocket, fatal, collecting = true;
    try {
        const context = await browser.newContext({viewport: {width: 1600, height: 1000}, serviceWorkers: 'block'});
        await context.route('**/*', async route => {
            const request = route.request(), u = new URL(request.url());
            if (!['http:', 'https:'].includes(u.protocol)) return route.continue();
            if (!allowedHosts.has(u.hostname)) {
                if (isStaticFont(request.method(), u, await request.allHeaders())) {
                    raw.static_fonts.push(urlPath(u.href));
                    return route.continue();
                }
                raw.external_requests.push(request.method() + ' ' + urlPath(u.href));
                return route.abort('blockedbyclient');
            }
            if (!isRead(request.method())) {
                if (request.method() === 'PUT' && u.pathname === '/v2/user_auth') { authWrites++; return route.continue(); }
                raw.blocked_writes.push(request.method() + ' ' + urlPath(u.href));
                return route.abort('blockedbyclient');
            }
            if (stageRoot && request.method() === 'GET' && u.host === target.host && !/^\/v2(?:\/|$)/.test(u.pathname)
                && /\.(?:js|css|html|json|png|jpe?g|svg|gif|ico|woff2?|ttf)$/.test(u.pathname)) {
                const relative = decodeURIComponent(u.pathname).replace(/^\/+/, ''), file = path.resolve(stageRoot, relative);
                assert(file.startsWith(stageRoot + '/'), 'Unsafe private asset path');
                if (fs.existsSync(file)) {
                    const st = fs.lstatSync(file);
                    assert(st.isFile() && !st.isSymbolicLink() && st.uid === 0 && fs.realpathSync(file).startsWith(stageRoot + '/'), 'Private asset escaped stage');
                    stagedAssets.add(u.pathname);
                    return route.fulfill({path: file});
                }
            }
            return route.continue();
        });
        page = await context.newPage();
        page.setDefaultTimeout(15000);
        page.on('console', message => { if (collecting && ['error', 'warning'].includes(message.type())) raw.console.push(message.type() + ': ' + message.text()); });
        page.on('pageerror', error => { if (collecting) raw.page_errors.push(error.message); });
        page.on('requestfailed', request => { if (collecting) raw.failed_requests.push(request.method() + ' ' + urlPath(request.url()) + ' ' + (request.failure()?.errorText || 'failed')); });
        page.on('response', response => { if (collecting && response.status() >= 400) raw.failed_responses.push(response.status() + ' ' + urlPath(response.url())); });
        const cdp = await context.newCDPSession(page);
        await cdp.send('Network.enable');
        cdp.on('Network.webSocketCreated', event => wsPaths.set(event.requestId, urlPath(event.url)));
        cdp.on('Network.webSocketHandshakeResponseReceived', event => handshakes.push({path: wsPaths.get(event.requestId), status: event.response.status}));
        // Deliberately do not subscribe to frame, request-header or cookie events.
        await page.goto(target.href, {waitUntil: 'domcontentloaded', timeout: 45000});
        await page.locator('#login').fill(secrets.KAZOO_MASTER_ADMIN_USER || 'admin');
        await page.locator('#password').fill(secrets.KAZOO_MASTER_ADMIN_PASSWORD);
        await page.locator('#account_name').fill('KazooMaster');
        const authPromise = page.waitForResponse(response => new URL(response.url()).pathname === '/v2/user_auth' && response.request().method() === 'PUT');
        await page.getByRole('button', {name: 'Sign in', exact: true}).click();
        const authResponse = await authPromise, auth = await authResponse.json();
        if (auth.auth_token) secretValues.push(auth.auth_token);
        assert(authResponse.ok() && auth.status === 'success' && auth.data?.account_id === MASTER, 'Login must resolve to protected MASTER account');
        await page.locator('#login').waitFor({state: 'hidden', timeout: 30000});
        await page.waitForFunction(() => window.require('monster').apps.auth.appsStore !== undefined);
        await page.waitForTimeout(2500);
        stages.push({name: 'login_core', passed: true});
        async function stage(name, work) {
            try { const proof = await work(); stages.push({name, passed: true, proof}); }
            catch (error) { stages.push({name, passed: false, error: error.message}); }
        }
        async function hideMyAccount() {
            await page.evaluate(() => window.require('monster').pub('myaccount.hide'));
            await page.locator('#monster_content').waitFor({state: 'visible'});
        }
        await stage('myaccount_billing', async () => {
            const open = await page.locator('#myaccount').evaluate(e => e.classList.contains('myaccount-open'));
            // Use the app's normal read-only open method, not the first-use
            // walkthrough whose completion can persist a user UI flag.
            if (!open) await page.evaluate(() => window.require('monster').apps.myaccount.renderDropdown(true));
            await page.locator('#myaccount.myaccount-open').waitFor({state: 'visible'});
            await page.locator('#myaccount .myaccount-element[data-module="billing"]').click();
            await page.locator('#myaccount .billing-content-wrapper').waitFor({state: 'visible'});
            await page.waitForTimeout(1800);
            return {rendered: true, saved: false};
        });
        await stage('acdc_queue_unsaved', async () => {
            await hideMyAccount();
            await page.evaluate(() => window.require('monster').routing.goTo('apps/acdc'));
            await page.locator('#acdc_wrapper .acdc-summary-grid').waitFor({state: 'visible', timeout: 30000});
            await page.locator('.acdc-tab[data-tab="queues"]').click();
            const rosterReply = page.waitForResponse(response => new URL(response.url()).pathname === `/v2/accounts/${MASTER}/queues/${QUEUE}/roster`
                && response.request().method() === 'GET');
            await page.locator(`.acdc-edit-queue[data-id="${QUEUE}"]`).click();
            const response = await rosterReply, roster = await response.json();
            assert(response.ok() && roster.status === 'success' && Array.isArray(roster.data) && !roster.next_start_key, 'Current roster must be complete');
            await page.locator('.acdc-queue-form').waitFor({state: 'visible'});
            await page.waitForFunction(expected => {
                const rosterSelect = document.querySelector('.acdc-roster');
                return rosterSelect && JSON.stringify(Array.from(rosterSelect.selectedOptions, o => o.value).sort()) === JSON.stringify(expected.slice().sort());
            }, roster.data);
            const members = roster.data.length;
            assert(await page.locator('[name="callback.enabled"]').isVisible(), 'Callback editor must render');
            await page.locator('.acdc-cancel').first().click();
            return {selected_members: members, matches_current_api_roster: true, saved: false};
        });
        await stage('callflows_unsaved', async () => {
            await hideMyAccount();
            await page.evaluate(() => window.require('monster').routing.goTo('apps/callflows'));
            await page.locator('#callflow_container .entity-manager .callflow-element').click();
            await page.locator('#callflow_container .callflow-edition .list-add').click();
            const action = page.locator('.action[name="acdc_member[id=*]"]');
            await action.waitFor({state: 'attached', timeout: 30000});
            if (!await action.isVisible()) await action.locator('xpath=ancestor::div[contains(@class,"category")]').locator('.open').click();
            const targetNode = page.locator('#ws_cf_flow .node[name="root"]');
            await targetNode.waitFor({state: 'visible'}); await action.scrollIntoViewIfNeeded();
            const from = await action.boundingBox(), to = await targetNode.boundingBox();
            assert(from && to, 'Callflow drag geometry unavailable');
            await page.mouse.move(from.x + from.width / 2, from.y + from.height / 2); await page.mouse.down();
            await page.mouse.move(from.x + from.width / 2 + 8, from.y + from.height / 2 + 8, {steps: 3});
            await page.mouse.move(to.x + to.width / 2, to.y + to.height / 2, {steps: 20}); await page.mouse.up();
            await page.locator('#acdc_queue_selector').selectOption(QUEUE);
            await page.locator('[data-action="save-acdc-queue"]').click(); // Local dialog metadata only, never Save Callflow.
            const proof = await page.evaluate(expected => {
                const app = window.require('monster').apps.callflows, node = app.flow.root.children[0].serialize();
                return {unsaved: !app.flow.id, exact_queue_action: node.module === 'acdc_member' && node.data.id === expected};
            }, QUEUE);
            assert(proof.unsaved && proof.exact_queue_action); return proof;
        });
        await stage('websocket_authenticated_subscription', async () => {
            websocket = await page.evaluate(async expectedAccount => {
                const monster = window.require('monster'), info = monster.socket.getInfo();
                if (!info.isConfigured) return {configured: false, reason: info.configurationError || 'not_configured'};
                const url = new URL(info.uri);
                if (url.host !== location.host || !/^wss?:$/.test(url.protocol) || url.pathname !== '/websocket' || url.search || url.hash) return {configured: false, reason: 'unexpected_endpoint'};
                if (monster.apps.auth.originalAccount.id !== expectedAccount) return {configured: false, reason: 'wrong_account'};
                return new Promise(resolve => {
                    const ws = new WebSocket(url.href), id = 'console-probe-' + Date.now() + '-' + Math.random().toString(16).slice(2);
                    const binding = 'call.CHANNEL_CREATE.' + id;
                    let subscribed = false, settled = false;
                    const finish = result => { if (settled) return; settled = true; clearTimeout(timer); ws.close(); resolve(result); };
                    const timer = setTimeout(() => finish({configured: true, subscribed, unsubscribed: false, reason: 'timeout'}), 12000);
                    const send = action => ws.send(JSON.stringify({action, auth_token: monster.util.getAuthToken(), request_id: id + '-' + action,
                        data: {account_id: expectedAccount, binding}}));
                    ws.onopen = () => send('subscribe');
                    ws.onerror = () => finish({configured: true, subscribed, unsubscribed: false, reason: 'transport_error'});
                    ws.onmessage = event => {
                        let reply; try { reply = JSON.parse(event.data); } catch { return; }
                        if (reply.action !== 'reply') return;
                        if (reply.request_id === id + '-subscribe') {
                            subscribed = reply.status === 'success' && Array.isArray(reply.data?.subscribed) && reply.data.subscribed.includes(binding);
                            if (!subscribed) return finish({configured: true, subscribed: false, unsubscribed: false, reason: 'subscribe_rejected'});
                            return send('unsubscribe');
                        }
                        if (reply.request_id === id + '-unsubscribe') finish({configured: true, subscribed, unsubscribed: reply.status === 'success'
                            && Array.isArray(reply.data?.unsubscribed) && reply.data.unsubscribed.includes(binding)});
                    };
                });
            }, MASTER);
            assert(websocket.configured && websocket.subscribed && websocket.unsubscribed, 'WebSocket authenticated subscribe/unsubscribe proof failed');
            return websocket;
        });
        await page.waitForTimeout(1200);
    } catch (error) { fatal = error.message; }
    finally { collecting = false; clearTimeout(timeout); await browser.close(); }
    const clean = values => unique(values.map(s => sanitize(s, secretValues)));
    const evidence = {checked_at: new Date().toISOString(), target: urlPath(target.href), read_only: true, authentication_writes: authWrites,
        artifact: stageRoot ? 'private_preview' : 'live_deployment', staged_assets: [...stagedAssets].sort(),
        stages: stages.map(stage => ({...stage, ...(stage.error ? {error: sanitize(stage.error, secretValues)} : {})})),
        console: clean(raw.console), page_errors: clean(raw.page_errors), failed_requests: clean(raw.failed_requests),
        failed_responses: clean(raw.failed_responses), blocked_writes: clean(raw.blocked_writes), external_requests_blocked: clean(raw.external_requests),
        static_font_requests: clean(raw.static_fonts),
        websocket_handshakes: handshakes, websocket, fatal: fatal && sanitize(fatal, secretValues),
        limitations: ['No calls or status changes', 'Only unauthenticated static Google CSS/font assets allowed externally; Maps/payment/webphone blocked',
            'No callflow/queue/account save', 'No real call-event delivery or load proof']};
    evidence.result = !fatal && stages.length === 5 && stages.every(s => s.passed) && !evidence.console.length && !evidence.page_errors.length
        && !evidence.failed_requests.length && !evidence.failed_responses.length && !evidence.blocked_writes.length && !evidence.external_requests_blocked.length
        && handshakes.some(h => h.status === 101 && h.path?.endsWith('/websocket')) ? 'PASS' : 'FAIL';
    const directory = '/var/log/kazoo-acceptance';
    const output = process.env.KAZOO_TEST_CONSOLE_EVIDENCE || path.join(directory, 'monster-console-' + new Date().toISOString().replace(/[:.]/g, '-') + '.json');
    assert(path.dirname(path.resolve(output)) === directory, 'Evidence must stay in protected acceptance log directory');
    fs.mkdirSync(directory, {recursive: true, mode: 0o700});
    const fd = fs.openSync(output, 'wx', 0o600);
    try { fs.writeFileSync(fd, JSON.stringify(evidence, null, 2) + '\n'); } finally { fs.closeSync(fd); }
    console.log(JSON.stringify({...evidence, evidence_path: output}));
    if (evidence.result !== 'PASS') process.exitCode = 1;
}
