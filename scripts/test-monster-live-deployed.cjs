#!/usr/bin/env node
'use strict';
// Opt-in actual deployed UI smoke. Only normal web authentication and reads;
// native subscribe/unsubscribe frames are forwarded unchanged to the real server.
// No stage overlays, fake API/socket replies, events, calls, screenshots, HAR,
// traces, saved browser state, payload dumps or raw exception logging.
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const crypto = require('node:crypto'), dns = require('node:dns').promises;
const ID = /^[a-f0-9]{32}$/, HASH = /^[a-f0-9]{64}$/;
class Failure extends Error {}
function check(ok, code) { if (!ok) throw new Failure(code); }
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
function readFile(file, privateFile = false) {
    check(path.isAbsolute(file) && fs.realpathSync(file) === file, 'unsafe_input_path');
    const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
    try {
        const s = fs.fstatSync(fd);
        check(s.isFile() && s.uid === 0 && s.nlink === 1 && !(s.mode & 0o022)
            && (!privateFile || (s.mode & 0o777) === 0o600)
            && s.size > 0 && s.size <= (privateFile ? 65536 : 32 * 1024 * 1024), 'unsafe_input_file');
        const bytes = fs.readFileSync(fd), after = fs.fstatSync(fd);
        check(['dev', 'ino', 'size', 'mtimeMs', 'ctimeMs', 'mode'].every(k => s[k] === after[k]), 'input_changed_while_reading');
        return bytes;
    } finally { fs.closeSync(fd); }
}
function credentials() {
    const data = readFile(process.env.KAZOO_INSTALLER_SECRETS || '/etc/kazoo/installer-secrets.env', true);
    try {
        const values = new Map();
        for (const line of data.toString('utf8').split('\n')) {
            if (!line || line.startsWith('#')) continue;
            const n = line.indexOf('='); check(n > 0 && !values.has(line.slice(0, n)), 'invalid_credential_record');
            values.set(line.slice(0, n), line.slice(n + 1));
        }
        const user = values.get('KAZOO_MASTER_ADMIN_USER'), password = values.get('KAZOO_MASTER_ADMIN_PASSWORD');
        check(user && password, 'missing_web_credentials'); return {user, password};
    } finally { data.fill(0); }
}
function endpoint(value, protocols, pathname) {
    let u; try { u = new URL(value); } catch (_) { throw new Failure('invalid_endpoint'); }
    check(protocols.includes(u.protocol) && !u.username && !u.password && !u.search && !u.hash
        && u.pathname === pathname, 'unsafe_endpoint'); return u;
}
async function main() {
    process.umask(0o077);
    check(process.getuid() === 0 && Number(process.versions.node.split('.')[0]) >= 20, 'root_and_node20_required');
    check(process.argv.length === 2 && !process.env.KAZOO_TEST_WEB_STAGE && !process.env.KAZOO_TEST_ACDC_STAGE,
        'deployed_only_no_stage_or_cli');
    check(process.env.NODE_TLS_REJECT_UNAUTHORIZED !== '0', 'tls_verification_required');
    const target = endpoint(process.env.KAZOO_TEST_UI_URL || 'http://kz5.talkchief.io/', ['http:', 'https:'], '/');
    const api = endpoint(process.env.KAZOO_TEST_API_URL || target.origin + '/v2', ['http:', 'https:'], '/v2');
    const socket = endpoint(process.env.KAZOO_TEST_WS_URL || target.origin.replace(/^http/, 'ws') + '/websocket', ['ws:', 'wss:'], '/websocket');
    const account = process.env.KAZOO_TEST_ACCOUNT_ID, queue = process.env.KAZOO_TEST_QUEUE_ID;
    check(ID.test(account || '') && ID.test(queue || ''), 'explicit_account_and_queue_required');
    const accountName = process.env.KAZOO_TEST_ACCOUNT_NAME || 'KazooMaster';
    const requiredSocket = process.env.KAZOO_TEST_REQUIRE_WEBSOCKET === 'true';
    check([undefined, 'true', 'false'].includes(process.env.KAZOO_TEST_REQUIRE_WEBSOCKET), 'invalid_websocket_mode');
    const web = process.env.KAZOO_TEST_WEB_ROOT || '/var/www/html/monster-ui';
    check(path.isAbsolute(web) && fs.realpathSync(web) === web, 'unsafe_web_root');
    const buildBytes = readFile(path.join(web, 'build-config.json')), build = JSON.parse(buildBytes);
    check(build.type === 'production' && Array.isArray(build.preloadedApps)
        && build.preloadedApps.every(name => typeof name === 'string' && /^[a-z0-9_-]+$/.test(name))
        && new Set(build.preloadedApps).size === build.preloadedApps.length, 'deployed_preloads_required');
    const preloadedAcdc = build.preloadedApps.includes('acdc');
    // Production embeds preloaded applications in main.js and their views in
    // templates.js; the deployer deliberately removes the standalone app.js.
    const assets = ['index.html', 'js/main.js', 'js/templates.js', 'js/config.js', 'build-config.json',
        'css/style.css', 'apps/acdc/style/app.css', ...(preloadedAcdc ? [] : ['apps/acdc/app.js'])];
    const pins = () => Object.fromEntries([__filename, ...assets.map(p => path.join(web, p))].map(p => [p, digest(readFile(p))]));
    const before = pins();
    check(before[path.join(web, 'build-config.json')] === digest(buildBytes), 'preload_manifest_changed');
    const expected = [['KAZOO_TEST_EXPECT_MAIN_SHA256', 'js/main.js'],
        ['KAZOO_TEST_EXPECT_TEMPLATES_SHA256', 'js/templates.js'],
        ...(preloadedAcdc ? [] : [['KAZOO_TEST_EXPECT_ACDC_SHA256', 'apps/acdc/app.js']])];
    for (const [key, file] of expected) {
        check(HASH.test(process.env[key] || '') && before[path.join(web, file)] === process.env[key], 'expected_deployed_artifact_hash_required');
    }
    const local = new Set(['127.0.0.1', '::1', ...Object.values(os.networkInterfaces()).flat().filter(Boolean).map(x => x.address)]);
    const hosts = [...new Set([target.hostname, api.hostname, socket.hostname])];
    for (const host of hosts) {
        const rows = await dns.lookup(host.replace(/^\[|\]$/g, ''), {all: true});
        check(rows.length > 0 && rows.every(r => local.has(r.address)), 'endpoints_must_be_this_server');
    }
    // Pin hostname resolution to loopback after the local-host check; no DNS
    // rebinding or external font/analytics traffic during credentialed browsing.
    const resolver = hosts.filter(h => !h.includes(':')).map(h => 'MAP ' + h + ' 127.0.0.1').join(', ');
    const evidenceDir = fs.mkdtempSync('/tmp/kazoo-monster-live-deployed.');
    const result = {status: 'FAIL', kind: 'actual_deployed_ui_readonly', preloaded_acdc: preloadedAcdc, before, checks: [],
        checkpoints: [], http_failures: [], live_queries: [], timeline: [], diagnostics_truncated: false,
        counts: {auth: 0, blocked_http_writes: 0, blocked_socket_frames: 0, external: 0,
            console_errors: 0, page_errors: 0, failed_http: 0, failed_requests: 0,
            omitted_external_font_requests: 0, overview_gets: 0, detail_gets: 0, supplemental_gets: 0,
            late_overview_gets: 0, native_subscribe_acks: 0, native_unsubscribe_acks: 0, native_events: 0},
        native: {required: requiredSocket, supported: null, detail_ack: false, ack_refetch: false,
            disposal_unsubscribe_sent: false, disposal_unsubscribe_ack: false,
            event_refetch_verified: false, broker_barrier_verified: false}, production_assets: {}, after: null};
    let browser, context, phase = 'bootstrap', stopping = false, fatal = null, serial = 0;
    let firstDetailAck = null, firstDetailOrder = null, detailStarted = 0, detailInFlight = 0, maxDetailInFlight = 0;
    let overviewGeneration = null;
    let disposalStartOrder = null, disposalSendOrder = null, disposalAckOrder = null;
    const detailLedger = [], pending = new Set(), requests = new Map(), scopedRequests = new Set();
    const requestPhases = new WeakMap(), httpOrders = new WeakMap();
    const overviewPath = '/v2/accounts/' + account + '/queues/live';
    const detailPath = '/v2/accounts/' + account + '/queues/' + queue + '/live';
    const fail = code => { fatal ||= code; };
    const track = (work, code) => { const p = Promise.resolve(work).catch(() => fail(code)).finally(() => pending.delete(p)); pending.add(p); };
    function same(u, base) { return u.origin === base.origin && !u.username && !u.password; }
    function livePath(u) { return same(u, api) && [overviewPath, detailPath].includes(u.pathname); }
    function category(u) {
        if (same(u, api)) {
            if (u.pathname === overviewPath) return 'live_overview';
            if (u.pathname === detailPath) return 'live_detail';
            if (u.pathname === '/v2/user_auth') return 'web_auth';
            if (u.pathname === '/v2/accounts/' + account + '/queues') return 'queue_catalog';
            if (u.pathname === '/v2/accounts/' + account + '/alerts') return 'framework_alerts';
            if (u.pathname === '/v2/accounts/' + account + '/agents/status') return 'agent_global_status';
            if (u.pathname === '/v2/accounts/' + account + '/agents') return 'agent_names';
            if (u.pathname === '/v2/accounts/' + account + '/users') return 'user_names';
            if (u.pathname === '/v2/accounts/' + account + '/queues/' + queue + '/roster') return 'queue_roster';
            if (new RegExp('^/v2/accounts/' + account + '/apps_store/[a-f0-9]{32}/icon$').test(u.pathname)) return 'framework_app_icon';
            if (u.pathname.startsWith('/v2/')) return 'other_api';
        }
        if (same(u, target)) {
            const relative = u.pathname === '/' ? 'index.html' : u.pathname.slice(1);
            const known = {'index.html': 'ui_index', 'js/main.js': 'ui_main', 'js/templates.js': 'ui_templates',
                'js/config.js': 'ui_config', 'build-config.json': 'ui_build_config', 'css/style.css': 'ui_css',
                'apps/acdc/style/app.css': 'acdc_css', 'apps/acdc/app.js': 'acdc_module'};
            return known[relative] || 'other_ui_asset';
        }
        return 'external';
    }
    function diagnostic(list, data) {
        if (list.length < 100) list.push(data); else result.diagnostics_truncated = true;
    }
    function checkpoint(name) { diagnostic(result.checkpoints, name); }
    function timeline(kind, route, status = null, requestOrder = null, replyStatus = null) {
        const order = ++serial;
        diagnostic(result.timeline, {order, kind, category: route, status, request_order: requestOrder, reply_status: replyStatus, phase});
        return order;
    }
    function httpFailure(request, status) {
        diagnostic(result.http_failures, {category: category(new URL(request.url())), status,
            phase: requestPhases.get(request) || 'bootstrap',
            method: ['GET', 'HEAD', 'OPTIONS', 'PUT', 'POST', 'PATCH', 'DELETE'].includes(request.method()) ? request.method() : 'other'});
    }
    function queryDiagnostic(u) {
        const keys = [...u.searchParams.keys()], rawSize = u.searchParams.get('page_size');
        const size = rawSize !== null && /^[1-9][0-9]{0,2}$/.test(rawSize) ? Number(rawSize) : null;
        diagnostic(result.live_queries, {category: category(u),
            page_size: size !== null && size <= 100 ? size : null,
            invalid_page_size: rawSize !== null && (size === null || size > 100),
            cursor_present: u.searchParams.has('start_queue_id'),
            cursor_valid: !u.searchParams.has('start_queue_id') || ID.test(u.searchParams.get('start_queue_id')),
            cache_buster_present: u.searchParams.has('_'), duplicate_keys: new Set(keys).size !== keys.length,
            unexpected_key: keys.some(k => !(u.pathname === overviewPath ? ['page_size', 'start_queue_id'] : []).includes(k))});
    }
    function checkClean() {
        check(!fatal, fatal || 'unexpected_failure');
        check(['blocked_http_writes', 'blocked_socket_frames', 'external', 'console_errors', 'page_errors',
            'failed_http', 'failed_requests', 'supplemental_gets', 'late_overview_gets'].every(k => result.counts[k] === 0), 'scoped_flow_not_clean');
    }
    try {
        checkpoint('protected_inputs_ready'); const secret = credentials();
        const {chromium} = require(process.env.KAZOO_PLAYWRIGHT_MODULE || '/tmp/kazoo-ui-browser.eXdEqS/node_modules/playwright');
        checkpoint('launching_chromium'); browser = await chromium.launch({headless: true, args: resolver ? ['--host-resolver-rules=' + resolver] : []});
        const deadline = setTimeout(() => { fail('overall_timeout'); browser.close().catch(() => {}); }, 105000);
        try {
            context = await browser.newContext({viewport: {width: 1600, height: 1000}, serviceWorkers: 'block'});
            check(typeof context.routeWebSocket === 'function', 'playwright_socket_route_required');
            await context.route('**/*', async route => {
                try {
                    const request = route.request(), u = new URL(request.url()), method = request.method();
                    if (!same(u, target) && !same(u, api)) {
                        // Optional font presentation only; never substitute application/API assets.
                        if (['GET', 'HEAD'].includes(method) && ['fonts.googleapis.com', 'fonts.gstatic.com'].includes(u.hostname)) {
                            result.counts.omitted_external_font_requests++;
                            return route.fulfill({status: 200, contentType: 'text/css', body: ''});
                        }
                        result.counts.external++; return route.abort('blockedbyclient');
                    }
                    if (!['GET', 'HEAD', 'OPTIONS'].includes(method)) {
                        if (same(u, api) && u.pathname === '/v2/user_auth' && !u.search && method === 'PUT' && result.counts.auth === 0) {
                            result.counts.auth++; return route.continue();
                        }
                        result.counts.blocked_http_writes++; return route.abort('blockedbyclient');
                    }
                    return route.continue();
                } catch (_) { fail('http_guard_failed'); return route.abort('blockedbyclient'); }
            });
            await context.routeWebSocket('**/*', route => {
                try {
                    const u = new URL(route.url());
                    if (u.href !== socket.href) { result.counts.external++; route.close(); return; }
                    const server = route.connectToServer(), wire = new Map();
                    route.onMessage(message => {
                        try {
                            check(typeof message === 'string' && Buffer.byteLength(message) <= 65536, 'unsafe_socket_frame');
                            const j = JSON.parse(message);
                            check(j && Object.keys(j).sort().join(',') === 'action,auth_token,data,request_id'
                                && j.data && Object.keys(j.data).sort().join(',') === 'account_id,binding'
                                && typeof j.auth_token === 'string' && j.auth_token.length > 0 && j.auth_token.length <= 16384
                                && ['subscribe', 'unsubscribe'].includes(j.action) && j.data.account_id === account
                                && /^queue_live\.changed\.[a-f0-9]{32}$/.test(j.data?.binding || '')
                                && typeof j.request_id === 'string' && /^lifecycle-[A-Za-z0-9-]+$/.test(j.request_id) && j.request_id.length <= 128
                                && !wire.has(j.request_id) && wire.size < 200, 'unexpected_socket_command');
                            const selected = j.data.binding === 'queue_live.changed.' + queue;
                            const order = timeline('socket_' + j.action, selected ? 'selected_queue_subscription' : 'other_page_queue_subscription');
                            const disposal = selected && j.action === 'unsubscribe' && phase === 'cleanup'
                                && disposalStartOrder !== null && order > disposalStartOrder;
                            if (disposal && disposalSendOrder === null) {
                                disposalSendOrder = order; result.native.disposal_unsubscribe_sent = true;
                            }
                            wire.set(j.request_id, {action: j.action, binding: j.data.binding, phase, order,
                                disposal, afterDetailGet: firstDetailOrder !== null && order > firstDetailOrder});
                            server.send(message); // Actual bytes, token stays only in memory.
                        } catch (_) { result.counts.blocked_socket_frames++; route.close(); }
                    });
                    server.onMessage(message => {
                        try {
                            check(typeof message === 'string' && Buffer.byteLength(message) <= 65536, 'unsafe_server_frame');
                            const j = JSON.parse(message), sent = wire.get(j.request_id);
                            if (j.action === 'reply' && sent) {
                                wire.delete(j.request_id);
                                const selected = sent.binding === 'queue_live.changed.' + queue;
                                const order = timeline('socket_reply', selected ? 'selected_queue_subscription' : 'other_page_queue_subscription',
                                    null, sent.order, j.status === 'success' ? 'success' : j.status === 'error' ? 'error' : 'invalid');
                                if (sent.action === 'subscribe' && j.status === 'success'
                                    && Array.isArray(j.data?.subscriptions) && j.data.subscriptions.includes(sent.binding)) {
                                    result.counts.native_subscribe_acks++;
                                    if (sent.phase === 'detail' && sent.afterDetailGet && selected && firstDetailAck === null) {
                                        firstDetailAck = {order, time: Date.now()}; result.native.detail_ack = true;
                                    }
                                }
                                if (sent.action === 'unsubscribe') {
                                    const accepted = j.status === 'success' && Array.isArray(j.data?.unsubscribed)
                                        && j.data.unsubscribed.includes(sent.binding);
                                    if (accepted) result.counts.native_unsubscribe_acks++;
                                    if (sent.disposal && sent.order === disposalSendOrder) {
                                        if (!accepted) fail('selected_disposal_unsubscribe_rejected');
                                        else { disposalAckOrder = order; result.native.disposal_unsubscribe_ack = true; }
                                    }
                                }
                            }
                            if (j.action === 'event' && j.name === 'changed'
                                && j.subscribed_key === 'queue_live.changed.' + queue
                                && j.data?.version === 1 && j.data.account_id === account && j.data.queue_id === queue) result.counts.native_events++;
                            route.send(message); // No fake ACK, event or payload rewriting.
                        } catch (_) { fail('native_frame_observation_failed'); route.close(); }
                    });
                } catch (_) { fail('socket_guard_failed'); route.close(); }
            });
            const page = await context.newPage(); page.setDefaultTimeout(15000);
            page.on('console', m => { if (!stopping && m.type() === 'error') result.counts.console_errors++; });
            page.on('pageerror', () => { if (!stopping) result.counts.page_errors++; });
            page.on('request', request => {
                const u = new URL(request.url());
                if (request.method() === 'GET' && same(u, api) && u.pathname === detailPath && firstDetailOrder === null) {
                    // Playwright click can wait through overview ACK/refreshes.
                    // The first actual selected-detail GET, not starting click(),
                    // establishes the detail request/subscription boundary.
                    if (phase !== 'detail_transition') fail('unexpected_detail_request_before_click');
                    phase = 'detail'; detailStarted = Date.now();
                }
                requestPhases.set(request, phase);
                if (phase !== 'bootstrap') scopedRequests.add(request);
                if (!same(u, api) || !u.pathname.startsWith('/v2/')) return;
                const order = timeline('http_request', category(u));
                httpOrders.set(request, order);
                if (request.method() !== 'GET') return;
                if (livePath(u)) queryDiagnostic(u);
                if (u.pathname === overviewPath) {
                    result.counts.overview_gets++;
                    // A response to an already-started overview GET may finish
                    // after navigation; a new overview GET must not be launched.
                    if (firstDetailOrder !== null && order > firstDetailOrder) {
                        result.counts.late_overview_gets++; fail('overview_request_started_after_detail');
                    }
                }
                if (u.pathname === detailPath) {
                    if (firstDetailOrder === null) firstDetailOrder = order;
                    result.counts.detail_gets++; detailInFlight++; maxDetailInFlight = Math.max(maxDetailInFlight, detailInFlight);
                    const item = {order, time: Date.now(), status: null}; detailLedger.push(item); requests.set(request, item);
                } else if ((phase === 'detail' && !livePath(u)) || (phase === 'detail_transition'
                    && ['queue_roster', 'agent_names', 'agent_global_status', 'user_names'].includes(category(u)))) result.counts.supplemental_gets++;
            });
            page.on('requestfinished', r => { if (requests.has(r)) detailInFlight--; });
            page.on('requestfailed', r => {
                if (requests.has(r)) detailInFlight--;
                if (!stopping) { httpFailure(r, 0); if (scopedRequests.has(r)) result.counts.failed_requests++; }
            });
            page.on('response', response => {
                const u = new URL(response.url()), item = requests.get(response.request());
                if (item) item.status = response.status();
                if (same(u, api) && u.pathname.startsWith('/v2/')) timeline('http_response', category(u), response.status(), httpOrders.get(response.request()) || null);
                if (!stopping && response.status() >= 400) {
                    httpFailure(response.request(), response.status());
                    if (scopedRequests.has(response.request())) result.counts.failed_http++;
                }
                const relative = u.pathname === '/' ? 'index.html' : u.pathname.slice(1);
                if (same(u, target) && assets.includes(relative) && response.status() === 200) track((async () => {
                    const bytes = await response.body(); check(digest(bytes) === before[path.join(web, relative)], 'served_asset_not_deployed_bytes');
                    result.production_assets[relative] = digest(bytes);
                })(), 'served_asset_hash_failed');
            });
            checkpoint('opening_production_index'); await page.goto(target.href, {waitUntil: 'domcontentloaded', timeout: 30000});
            checkpoint('filling_normal_login');
            await page.locator('#login').fill(secret.user); await page.locator('#password').fill(secret.password);
            secret.password = ''; secret.user = '';
            await page.locator('#account_name').fill(accountName);
            const authWait = page.waitForResponse(r => same(new URL(r.url()), api)
                && new URL(r.url()).pathname === '/v2/user_auth' && r.request().method() === 'PUT');
            checkpoint('submitting_normal_login'); await page.getByRole('button', {name: 'Sign in', exact: true}).click();
            const authResponse = await authWait;
            const auth = await authResponse.json();
            check(authResponse.ok() && auth.status === 'success' && auth.data?.account_id === account, 'web_login_scope_failed');
            delete auth.auth_token;
            checkpoint('waiting_authenticated_shell'); await page.locator('#login').waitFor({state: 'hidden', timeout: 25000});
            await page.waitForFunction(() => window.require('monster').apps.auth.appsStore !== undefined);
            await page.waitForLoadState('networkidle', {timeout: 15000});
            result.checks.push('normal_web_login_expected_account');
            await page.evaluate(() => window.require('monster').pub('myaccount.hide'));
            phase = 'overview';
            checkpoint('routing_to_acdc');
            await page.evaluate(() => window.require('monster').routing.goTo('apps/acdc'));
            checkpoint('waiting_overview_grid');
            await page.locator('.acdc-live-queue-grid').waitFor({state: 'visible'});
            // Normal dashboard tab and queue controls, never app request/mock seams.
            checkpoint('clicking_dashboard_tab'); await page.locator('.acdc-tab[data-tab="dashboard"]').click();
            checkpoint('waiting_valid_overview_snapshot');
            await page.waitForFunction(expected => {
                const app = window.require('monster').apps.acdc, c = app.appFlags.acdc.liveDashboardController;
                const s = app.appFlags.acdc.liveDashboardSnapshot;
                return c && !c.inFlight && s && !s.queueId && s.accountId === expected && app.liveSnapshotValid(s.results.live, expected, undefined, s.page);
            }, account);
            checkpoint('waiting_overview_ack_and_coalesced_gets_settled');
            await page.waitForFunction(expected => {
                const app = window.require('monster').apps.acdc, c = app.appFlags.acdc.liveDashboardController;
                const s = app.appFlags.acdc.liveDashboardSnapshot;
                return c && !c.queueId && c.accountId === expected && !c.inFlight && !c.dirty
                    && !c.coalesceTimer && !c.admitting && !c.admissionTimer
                    && (!c.supported || app.liveTransportState(c) === 'acknowledged')
                    && s && !s.queueId && app.liveSnapshotValid(s.results.live, expected, undefined, s.page);
            }, account, {timeout: 20000});
            await page.waitForLoadState('networkidle', {timeout: 10000});
            overviewGeneration = await page.evaluate(() => window.require('monster').apps.acdc.appFlags.acdc.liveDashboardController.generation);
            checkpoint('waiting_selected_queue_on_page');
            await page.locator('.acdc-open-live-queue[data-queue-id="' + queue + '"]').first().waitFor({state: 'visible'});
            result.checks.push('current_authorized_overview_page_contains_queue');
            phase = 'detail_transition';
            checkpoint('clicking_selected_queue');
            await page.locator('.acdc-open-live-queue[data-queue-id="' + queue + '"]').first().click();
            checkpoint('waiting_detail_members_panel');
            await page.locator('.acdc-live-members-panel').waitFor({state: 'visible'});
            checkpoint('waiting_valid_detail_snapshot');
            await page.waitForFunction(({account, queue}) => {
                const app = window.require('monster').apps.acdc, c = app.appFlags.acdc.liveDashboardController;
                const s = app.appFlags.acdc.liveDashboardSnapshot;
                return c && !c.inFlight && c.queueId === queue && s && s.accountId === account && s.queueId === queue
                    && app.liveSnapshotValid(s.results.live, account, queue, s.page);
            }, {account, queue});
            const detail = await page.evaluate(({account, queue, overviewGeneration}) => {
                const app = window.require('monster').apps.acdc, s = app.appFlags.acdc.liveDashboardSnapshot;
                const d = s.results.live, g = d.agents;
                const c = app.appFlags.acdc.liveDashboardController;
                return {scope: s.accountId === account && s.queueId === queue && c.accountId === account && c.queueId === queue
                        && c.generation !== overviewGeneration, websocket: d.capabilities.websocket_updates,
                    runtime: d.capabilities.agent_runtime, reachability: g.endpoint_reachability_verified,
                    roster: g.roster_complete ? g.rows.length : null,
                    waiting: d.queues[0].metrics_available ? d.queues[0].metrics.current_waiting : null,
                    handled: d.queues[0].metrics_available ? d.queues[0].metrics.current_handled : null,
                    valid: app.liveAgentsValid(g),
                    rendered: Array.from(document.querySelectorAll('.acdc-live-detail-metrics strong'), e => e.textContent)};
            }, {account, queue, overviewGeneration});
            check(detail.scope && detail.valid && detail.runtime === true && detail.reachability === false, 'current_detail_agents_contract_failed');
            result.native.supported = detail.websocket;
            check(JSON.stringify(detail.rendered) === JSON.stringify([detail.waiting, detail.handled, detail.roster].map(n => n === null ? '—' : String(n))), 'rendered_detail_counts_not_dto');
            result.checks.push('single_get_current_agents_detail_rendered_unknowns_preserved');
            if (detail.websocket) {
                checkpoint('waiting_native_detail_ack');
                await page.waitForFunction(() => {
                    const app = window.require('monster').apps.acdc, c = app.appFlags.acdc.liveDashboardController;
                    return c && app.liveTransportState(c) === 'acknowledged' && !c.inFlight;
                }, null, {timeout: 10000});
                // Node-side wire receipt must precede another real detail GET;
                // both must occur before the controller's first 15s periodic repair.
                const until = Math.min(detailStarted + 14000, Date.now() + 5000);
                checkpoint('waiting_ack_followup_get');
                while (Date.now() < until && !(firstDetailAck && detailLedger.some(r => r.order > firstDetailAck.order && r.status === 200))) {
                    await page.waitForTimeout(50);
                }
                check(firstDetailAck !== null && detailLedger.filter(r => r.order < firstDetailAck.order).length === 1, 'exactly_one_initial_detail_get_required');
                check(detailLedger.some(r => r.order > firstDetailAck.order && r.status === 200 && r.time < detailStarted + 14000), 'native_ack_refetch_before_periodic_repair_required');
                await page.waitForFunction(({account, queue, ackAt}) => {
                    const app = window.require('monster').apps.acdc, c = app.appFlags.acdc.liveDashboardController;
                    const s = app.appFlags.acdc.liveDashboardSnapshot;
                    return c && !c.inFlight && c.queueId === queue && s && s.queueId === queue && s.receivedAt >= ackAt
                        && app.liveSnapshotValid(s.results.live, account, queue, s.page)
                        && !document.querySelector('.acdc-live-refresh-error');
                }, {account, queue, ackAt: firstDetailAck.time}, {timeout: 3000});
                result.native.ack_refetch = true; result.checks.push('real_native_detail_ack_then_authorized_refetch');
            } else {
                check(!requiredSocket, 'websocket_capability_not_active');
                check(detailLedger.length === 1, 'exactly_one_detail_get_required');
                result.checks.push('unsupported_websocket_explicit_snapshot_only');
            }
            check(maxDetailInFlight === 1 && result.counts.supplemental_gets === 0, 'detail_fanout_or_overlap');
            check(result.counts.auth === 1, 'exactly_one_normal_auth_required');
            checkClean();
            // Normal navigation retires the local controller, then closing the
            // ephemeral context removes the session. No persistent logout write.
            phase = 'cleanup';
            checkpoint('navigating_away_from_live_detail');
            disposalStartOrder = timeline('navigation_disposal', 'selected_queue_subscription');
            await page.locator('.acdc-tab[data-tab="queues"]').click();
            await page.waitForFunction(() => !window.require('monster').apps.acdc.appFlags.acdc.liveDashboardController);
            result.checks.push('navigation_disposes_live_controller');
            if (detail.websocket) {
                checkpoint('waiting_selected_disposal_unsubscribe_ack');
                const until = Date.now() + 5000;
                while (Date.now() < until && disposalAckOrder === null && !fatal) await page.waitForTimeout(50);
                check(disposalSendOrder !== null && disposalAckOrder !== null && disposalAckOrder > disposalSendOrder,
                    'correlated_selected_disposal_unsubscribe_ack_required');
                result.checks.push('normal_navigation_selected_unsubscribe_sent_and_acknowledged');
            }
            checkpoint('verifying_served_asset_hashes'); await Promise.all([...pending]); checkClean();
            check(['index.html', 'js/main.js', 'js/templates.js', 'js/config.js', 'css/style.css']
                .every(file => result.production_assets[file])
                && (preloadedAcdc || result.production_assets['apps/acdc/app.js']), 'actual_deployed_asset_receipts_missing');
            result.checks.push('actual_served_production_bytes_match_expected_deployed_files');
            result.status = requiredSocket ? 'PASS' : (detail.websocket ? 'PASS' : 'PASS_SNAPSHOT_ONLY');
        } finally { clearTimeout(deadline); }
    } catch (e) {
        result.failure = fatal || (e instanceof Failure ? e.message : 'browser_or_input_step_failed');
        result.failure_phase = phase; result.failure_checkpoint = result.checkpoints.at(-1) || 'preflight';
    }
    finally {
        stopping = true;
        if (context) await context.close().catch(() => fail('context_cleanup_failed'));
        if (browser) await browser.close().catch(() => fail('browser_cleanup_failed'));
        await Promise.all([...pending]);
        try { result.after = pins(); check(JSON.stringify(result.after) === JSON.stringify(before), 'input_changed_during_smoke'); }
        catch (_) { fail('input_changed_during_smoke'); }
        if (fatal) { result.status = 'FAIL'; result.failure = fatal; }
        // Fixed codes and numeric/boolean/hash observations only. No exception,
        // response text, credentials, frames, request IDs or user/call names.
        fs.writeFileSync(path.join(evidenceDir, 'receipt.json'), JSON.stringify(result, null, 2) + '\n', {flag: 'wx', mode: 0o600});
        process.stdout.write(JSON.stringify({status: result.status, evidence: path.join(evidenceDir, 'receipt.json'),
            checks: result.checks.length, failure: result.failure || null}) + '\n');
        if (result.status === 'FAIL') process.exitCode = 1;
    }
}
if (require.main === module) main().catch(e => {
    process.stderr.write(JSON.stringify({status: 'FAIL', failure: e instanceof Failure ? e.message : 'preflight_failed'}) + '\n');
    process.exitCode = 1;
});
