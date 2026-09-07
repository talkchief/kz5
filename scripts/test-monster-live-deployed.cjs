#!/usr/bin/env node
'use strict';
// Opt-in actual deployed UI smoke. Only normal web authentication and reads;
// native subscribe/unsubscribe frames are forwarded unchanged to the real server.
// No stage overlays, fake API/socket replies, events, calls, screenshots, HAR,
// traces, saved browser state, payload dumps or raw exception logging.
// Optional standalone reconnect probe closes only its own browser/server socket.
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const crypto = require('node:crypto'), dns = require('node:dns').promises;
const ID = /^[a-f0-9]{32}$/, HASH = /^[a-f0-9]{64}$/;
const ACCOUNT_BROWSER_ASSET = 'apps/common/submodules/accountBrowser/accountBrowser.js';
const ACCOUNT_TOGGLE = '#main_topbar_account_toggle_container';
class Failure extends Error {}
function check(ok, code) { if (!ok) throw new Failure(code); }
function reconnectOptions(env, natural) {
    check([undefined, 'true', 'false'].includes(env.KAZOO_TEST_RECONNECT), 'invalid_reconnect_mode');
    const enabled = env.KAZOO_TEST_RECONNECT === 'true';
    check(!enabled || (!natural && env.KAZOO_TEST_REQUIRE_WEBSOCKET === 'true'), 'standalone_native_reconnect_required');
    return enabled;
}
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
function browserErrorDiagnostic(error, uiOrigin) {
    const name = ['TypeError', 'ReferenceError', 'SyntaxError', 'RangeError', 'Error'].includes(error.name) ? error.name : 'other';
    const message = typeof error.message === 'string' ? error.message : '';
    const kind = message.includes('is not a function') ? 'missing_function' :
        /Cannot read propert/.test(message) ? 'missing_property' : /[Tt]emplate/.test(message) ? 'template' : 'other';
    const frames = [];
    for (const match of String(error.stack || '').matchAll(/(https?:\/\/[^\s)]+):(\d+):(\d+)/g)) {
        let u; try { u = new URL(match[1]); } catch (_) { continue; }
        const known = {'/js/main.js': 'ui_main', '/js/templates.js': 'ui_templates',
            ['/' + ACCOUNT_BROWSER_ASSET]: 'account_browser'};
        if (u.origin === uiOrigin && known[u.pathname] && frames.length < 6) frames.push({asset: known[u.pathname], line: Number(match[2]), column: Number(match[3])});
    }
    return {name, kind, frames};
}
function accountScopeOptions(env) {
    const account = env.KAZOO_TEST_ACCOUNT_ID, queue = env.KAZOO_TEST_QUEUE_ID;
    const loginAccount = env.KAZOO_TEST_LOGIN_ACCOUNT_ID === undefined ? account : env.KAZOO_TEST_LOGIN_ACCOUNT_ID;
    const switching = account !== loginAccount;
    const loginQueue = switching ? env.KAZOO_TEST_LOGIN_QUEUE_ID : queue;
    const loginName = env.KAZOO_TEST_LOGIN_ACCOUNT_NAME === undefined ?
        (env.KAZOO_TEST_ACCOUNT_NAME || 'KazooMaster') : env.KAZOO_TEST_LOGIN_ACCOUNT_NAME;
    check(ID.test(account || '') && ID.test(queue || '') && ID.test(loginAccount || ''), 'explicit_account_and_queue_required');
    check(ID.test(loginQueue || ''), 'explicit_login_queue_required_for_switch');
    check(typeof loginName === 'string' && loginName.length > 0 && Buffer.byteLength(loginName) <= 256
        && !/[\x00-\x1f\x7f]/.test(loginName), 'invalid_login_account_name');
    return {account, queue, loginAccount, loginQueue, loginName, switching};
}
function socketAdmission(scope) {
    return {stage: scope.switching ? 'home' : 'target', subscribe: null, subscribeAck: null,
        disposalStart: null, unsubscribe: null, unsubscribeAck: null};
}
function socketScopeRole(scope, admission, data) {
    check(data && /^queue_live\.changed\.[a-f0-9]{32}$/.test(data.binding || ''), 'unexpected_socket_scope');
    if (admission.stage === 'home' || admission.stage === 'home_cleanup') {
        check(scope.switching && data.account_id === scope.loginAccount
            && data.binding === 'queue_live.changed.' + scope.loginQueue, 'unexpected_home_socket_scope');
        return 'home';
    }
    check(admission.stage === 'target' && data.account_id === scope.account, 'unexpected_target_socket_scope');
    return 'target';
}
function recordHomeCommand(admission, sent) {
    if (sent.role !== 'home') return;
    if (sent.action === 'subscribe') {
        check(admission.stage === 'home' && admission.subscribe === null, 'unexpected_home_subscribe');
        admission.subscribe = sent;
    } else {
        check(sent.action === 'unsubscribe' && admission.stage === 'home_cleanup'
            && admission.subscribeAck !== null && admission.unsubscribe === null
            && sent.order > admission.disposalStart, 'unexpected_home_unsubscribe');
        admission.unsubscribe = sent;
    }
}
function observeHomeReply(admission, sent, reply, order) {
    // Native ACKs carry bindings, not an account ID. The exact same-connection
    // request record provides account/role ownership; a stale record cannot win.
    if (!sent || sent.role !== 'home' || reply.request_id !== sent.requestId) return false;
    const subscribing = sent.action === 'subscribe', field = subscribing ? 'subscribed' : 'unsubscribed';
    check(sent === (subscribing ? admission.subscribe : admission.unsubscribe)
        && admission.stage === (subscribing ? 'home' : 'home_cleanup')
        && (subscribing ? admission.subscribeAck : admission.unsubscribeAck) === null
        && reply.action === 'reply' && reply.status === 'success' && order > sent.order
        && reply.data && Object.keys(reply.data).sort().join(',') === [field, 'subscriptions'].sort().join(',')
        && JSON.stringify(reply.data[field]) === JSON.stringify([sent.binding])
        && JSON.stringify(reply.data.subscriptions) === JSON.stringify(subscribing ? [sent.binding] : []),
    'exact_home_subscription_reply_required');
    if (subscribing) admission.subscribeAck = order;
    else admission.unsubscribeAck = order;
    return true;
}
function beginHomeDisposal(admission, order) {
    check(admission.stage === 'home' && admission.subscribeAck !== null
        && order > admission.subscribeAck, 'home_subscribe_ack_before_disposal_required');
    admission.disposalStart = order; admission.stage = 'home_cleanup';
}
function closeHomeAdmission(admission, disposed) {
    check(disposed === true && admission.stage === 'home_cleanup' && admission.subscribeAck !== null
        && admission.unsubscribe !== null && admission.unsubscribeAck > admission.unsubscribe.order
        && admission.unsubscribe.order > admission.disposalStart, 'home_disposal_and_exact_unsubscribe_ack_required');
    admission.stage = 'target';
}
function homeOverviewInBrowser({loginAccount, loginQueue}) {
    const monster = window.require('monster'), auth = monster.apps.auth, app = monster.apps.acdc;
    const flags = app?.appFlags.acdc, c = flags?.liveDashboardController, s = flags?.liveDashboardSnapshot;
    const toggle = document.querySelector('#main_topbar_account_toggle');
    return Boolean(toggle) && !toggle.classList.contains('masquerading')
        && auth.originalAccount?.id === loginAccount && auth.currentAccount?.id === loginAccount
        && app?.isMasqueradable === true && app.accountId === loginAccount && flags.currentTab === 'dashboard'
        && Boolean(c) && c.accountId === loginAccount && !c.queueId && !c.stopped && !c.inFlight && !c.dirty
        && !c.coalesceTimer && !c.admitting && !c.admissionTimer && c.supported === true
        && app.liveTransportState(c) === 'acknowledged' && Boolean(s) && s.accountId === loginAccount && !s.queueId
        && app.liveSnapshotValid(s.results.live, loginAccount, undefined, s.page)
        && s.results.live.queues.length === 1 && s.results.live.queues[0].id === loginQueue;
}
function queuesDisposedInBrowser() {
    const flags = window.require('monster').apps.acdc.appFlags.acdc;
    return flags.currentTab === 'queues' && !flags.liveDashboardController;
}
function accountScopeInBrowser({loginAccount, account, requireAcdc = false}) {
    // Read-only assertion executed in the real page; never replace auth/app state.
    const monster = window.require('monster'), auth = monster.apps.auth, app = monster.apps.acdc;
    const toggle = document.querySelector('#main_topbar_account_toggle');
    return Boolean(toggle) && auth.originalAccount?.id === loginAccount && auth.currentAccount?.id === account
        && Boolean(toggle?.classList.contains('masquerading')) === (loginAccount !== account)
        && (!requireAcdc || app?.isMasqueradable === true && app.accountId === account);
}
function targetAccountResponse(response, api, account) {
    const u = new URL(response.url());
    return u.origin === api.origin && !u.username && !u.password
        && u.pathname === '/v2/accounts/' + account && response.request().method() === 'GET';
}
async function verifyTargetAccountResponse(response, account) {
    const body = await response.json();
    check(response.status() === 200 && body?.status === 'success' && body.data?.id === account,
        'masquerade_account_readback_failed');
    // Native envelopes may echo the existing token. Never retain that envelope.
    delete body.auth_token;
}
async function switchTargetAccount(page, api, scope, checkpoint) {
    if (!scope.switching) return false;
    checkpoint('waiting_native_account_picker_ready');
    await page.locator('#main_topbar_account_toggle_link[aria-disabled="false"]').waitFor({state: 'visible', timeout: 10000});
    checkpoint('opening_native_account_switcher');
    await page.locator('#main_topbar_account_toggle_link').click();
    await page.locator(ACCOUNT_TOGGLE + ' .account-browser-search').waitFor({state: 'visible', timeout: 10000});
    await page.locator(ACCOUNT_TOGGLE + ' .account-list-loader').waitFor({state: 'detached', timeout: 10000});
    const row = page.locator(ACCOUNT_TOGGLE + ' .account-list .account-list-element[data-id="' + scope.account + '"] .account-link');
    if (await row.count() === 0) {
        checkpoint('searching_native_account_browser_by_id');
        const search = page.locator(ACCOUNT_TOGGLE + ' .account-browser-search');
        // A normal non-Enter keyup attaches the initially detached search link.
        // fill()+Enter alone does not exercise the native global-search control.
        await search.pressSequentially(scope.account);
        await search.press('Enter');
    }
    await row.waitFor({state: 'visible', timeout: 10000});
    check(await row.count() === 1, 'masquerade_target_row_not_unique');
    checkpoint('selecting_native_target_account');
    const [response] = await Promise.all([
        page.waitForResponse(r => targetAccountResponse(r, api, scope.account), {timeout: 10000}),
        row.click()
    ]);
    await verifyTargetAccountResponse(response, scope.account);
    // The framework's failed account.get callback can still continue routing.
    // Both successful server readback and actual switched state are mandatory.
    await page.waitForFunction(accountScopeInBrowser, scope, {timeout: 10000});
    return true;
}
async function restoreHomeAccount(page, scope, checkpoint) {
    if (!scope.switching) return false;
    checkpoint('waiting_home_account_picker_ready');
    await page.locator('#main_topbar_account_toggle_link[aria-disabled="false"]').waitFor({state: 'visible', timeout: 10000});
    checkpoint('restoring_home_with_native_account_control');
    await page.locator('#main_topbar_account_toggle_link').click();
    await page.locator(ACCOUNT_TOGGLE + ' .home-account-link').click();
    await page.waitForFunction(accountScopeInBrowser,
        {...scope, account: scope.loginAccount, requireAcdc: true}, {timeout: 10000});
    await page.waitForFunction(queuesDisposedInBrowser);
    return true;
}
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
async function main(natural) {
    const env = natural ? natural.env : process.env;
    const summaryMode = natural?.overview === true;
    process.umask(0o077);
    check(process.getuid() === 0 && Number(process.versions.node.split('.')[0]) >= 20, 'root_and_node20_required');
    check((natural || process.argv.length === 2) && !env.KAZOO_TEST_WEB_STAGE && !env.KAZOO_TEST_ACDC_STAGE,
        'deployed_only_no_stage_or_cli');
    check(process.env.NODE_TLS_REJECT_UNAUTHORIZED !== '0', 'tls_verification_required');
    const target = endpoint(process.env.KAZOO_TEST_UI_URL || 'http://kz5.talkchief.io/', ['http:', 'https:'], '/');
    const api = endpoint(process.env.KAZOO_TEST_API_URL || target.origin + '/v2', ['http:', 'https:'], '/v2');
    const socket = endpoint(process.env.KAZOO_TEST_WS_URL || target.origin.replace(/^http/, 'ws') + '/websocket', ['ws:', 'wss:'], '/websocket');
    const scope = accountScopeOptions(env), {account, queue, loginAccount, loginName} = scope;
    const admission = socketAdmission(scope);
    const requiredSocket = env.KAZOO_TEST_REQUIRE_WEBSOCKET === 'true';
    const reconnectMode = reconnectOptions(env, natural);
    check([undefined, 'true', 'false'].includes(env.KAZOO_TEST_REQUIRE_WEBSOCKET), 'invalid_websocket_mode');
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
        'css/style.css', 'apps/acdc/style/app.css', ...(preloadedAcdc ? [] : ['apps/acdc/app.js']),
        ...(scope.switching ? [ACCOUNT_BROWSER_ASSET, 'apps/common/style/app.css'] : [])];
    const helperFiles = natural || reconnectMode ? ['test-fixtures/monster-live-call-observer.cjs',
        'test-fixtures/queue-live-observer.cjs', 'api-docs-queue-live.cjs',
        ...(reconnectMode ? ['test-fixtures/monster-live-reconnect.cjs'] : [])].map(p => path.join(__dirname, p)) : [];
    const pins = () => Object.fromEntries([__filename, ...helperFiles, ...assets.map(p => path.join(web, p))].map(p => [p, digest(readFile(p))]));
    const before = pins();
    check(before[path.join(web, 'build-config.json')] === digest(buildBytes), 'preload_manifest_changed');
    const expected = [['KAZOO_TEST_EXPECT_MAIN_SHA256', 'js/main.js'],
        ['KAZOO_TEST_EXPECT_TEMPLATES_SHA256', 'js/templates.js'],
        ...(preloadedAcdc ? [] : [['KAZOO_TEST_EXPECT_ACDC_SHA256', 'apps/acdc/app.js']]),
        ...(scope.switching ? [['KAZOO_TEST_EXPECT_ACCOUNT_BROWSER_SHA256', ACCOUNT_BROWSER_ASSET]] : [])];
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
        checkpoints: [], http_failures: [], browser_errors: [], blocked_socket_diagnostics: [], live_queries: [], timeline: [], diagnostics_truncated: false,
        counts: {auth: 0, blocked_http_writes: 0, blocked_socket_frames: 0, external: 0,
            console_errors: 0, page_errors: 0, failed_http: 0, failed_requests: 0,
            omitted_external_font_requests: 0, overview_gets: 0, detail_gets: 0, supplemental_gets: 0,
            late_overview_gets: 0, native_subscribe_acks: 0, native_unsubscribe_acks: 0, native_events: 0},
        account_switch: {requested: scope.switching, target_verified: false, home_restored: false,
            home_overview_verified: false, home_subscribe_ack: false, home_controller_disposed: false,
            home_unsubscribe_ack: false, home_admission_closed: false,
            restricted_principal_verified: false},
        native: {required: requiredSocket, supported: null, detail_ack: false, ack_refetch: false,
            disposal_unsubscribe_sent: false, disposal_unsubscribe_ack: false,
            event_refetch_verified: false, broker_barrier_verified: false}, production_assets: {}, after: null};
    let browser, context, phase = 'bootstrap', stopping = false, fatal = null, serial = 0, callObserver, observerErrorClass, summary;
    let firstDetailAck = null, firstDetailOrder = null, detailStarted = 0, detailInFlight = 0, maxDetailInFlight = 0;
    let firstOverviewAck = null, firstOverviewOrder = null, overviewStarted = 0, overviewInFlight = 0, maxOverviewInFlight = 0;
    let overviewGeneration = null;
    let connectionSequence = 0, currentWire = null, reconnectProbe, reconnectActive = false;
    let reconnectGate = null, releaseReconnect = null, reconnectSnapshot = null, reconnectErrorClass, reconnectAckAt = null;
    if (reconnectMode) {
        const {createReconnectTracker, ReconnectError} = require('./test-fixtures/monster-live-reconnect.cjs');
        reconnectProbe = createReconnectTracker({accountId: account, queueId: queue});
        reconnectErrorClass = ReconnectError;
    }
    let disposalStartOrder = null, disposalSendOrder = null, disposalAckOrder = null;
    const detailLedger = [], overviewLedger = [], pending = new Set(), requests = new Map(), scopedRequests = new Set();
    const summaryBindings = new Map();
    let summaryFinalSubscriptionsEmpty = false;
    const requestPhases = new WeakMap(), httpOrders = new WeakMap();
    const overviewPath = '/v2/accounts/' + account + '/queues/live';
    const homeOverviewPath = '/v2/accounts/' + loginAccount + '/queues/live';
    const detailPath = '/v2/accounts/' + account + '/queues/' + queue + '/live';
    const fail = code => { fatal ||= code; };
    const track = (work, code) => { const p = Promise.resolve(work).catch(() => fail(code)).finally(() => pending.delete(p)); pending.add(p); };
    function same(u, base) { return u.origin === base.origin && !u.username && !u.password; }
    function livePath(u) { return same(u, api) && [overviewPath, detailPath].includes(u.pathname); }
    function category(u) {
        if (same(u, api)) {
            if (u.pathname === overviewPath) return 'live_overview';
            if (u.pathname === detailPath) return 'live_detail';
            if (scope.switching && u.pathname === homeOverviewPath) return 'home_live_overview';
            if (u.pathname === '/v2/user_auth') return 'web_auth';
            if (scope.switching && u.pathname === '/v2/accounts/' + account) return 'switch_target_account';
            if (scope.switching && u.pathname === '/v2/accounts/' + loginAccount + '/children') return 'switch_home_children';
            if (scope.switching && u.pathname === '/v2/accounts/' + account + '/children') return 'switch_target_children';
            if (scope.switching && u.pathname === '/v2/search/multi') return 'switch_account_search';
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
                'apps/acdc/style/app.css': 'acdc_css', 'apps/acdc/app.js': 'acdc_module',
                [ACCOUNT_BROWSER_ASSET]: 'framework_account_browser', 'apps/common/style/app.css': 'framework_common_css'};
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
        const deadline = setTimeout(() => { fail('overall_timeout'); browser.close().catch(() => {}); }, natural ? 150000 : 105000);
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
            await context.routeWebSocket('**/*', async route => {
                try {
                    const u = new URL(route.url());
                    if (u.href !== socket.href) { result.counts.external++; route.close(); return; }
                    const connection = ++connectionSequence;
                    if (reconnectMode) check(connection <= 2, 'unexpected_extra_socket_connection');
                    // Delay only the replacement transport until the real close
                    // has been observed in the DOM. No fake ACK/event is sent.
                    if (reconnectGate) await reconnectGate;
                    if (stopping) { await route.close(); return; }
                    const server = route.connectToServer(), wire = new Map(), seenRequestIds = new Set();
                    currentWire = {connection, route, server, wire};
                    route.onMessage(message => {
                        let frame;
                        try {
                            check(typeof message === 'string' && Buffer.byteLength(message) <= 65536, 'unsafe_socket_frame');
                            const j = JSON.parse(message); frame = j;
                            check(j && Object.keys(j).sort().join(',') === 'action,auth_token,data,request_id'
                                && j.data && Object.keys(j.data).sort().join(',') === 'account_id,binding'
                                && typeof j.auth_token === 'string' && j.auth_token.length > 0 && j.auth_token.length <= 16384
                                && ['subscribe', 'unsubscribe'].includes(j.action)
                                && /^queue_live\.changed\.[a-f0-9]{32}$/.test(j.data?.binding || '')
                                && typeof j.request_id === 'string' && /^lifecycle-[A-Za-z0-9-]+$/.test(j.request_id) && j.request_id.length <= 128
                                && !seenRequestIds.has(j.request_id) && seenRequestIds.size < 200
                                && wire.size < 200, 'unexpected_socket_command');
                            const role = socketScopeRole(scope, admission, j.data);
                            const selected = role === 'target' && j.data.binding === 'queue_live.changed.' + queue;
                            const order = timeline('socket_' + j.action, role === 'home' ? 'home_queue_subscription'
                                : selected ? 'selected_queue_subscription' : 'other_page_queue_subscription');
                            const disposal = selected && j.action === 'unsubscribe' && phase === 'cleanup'
                                && disposalStartOrder !== null && order > disposalStartOrder;
                            if (disposal && disposalSendOrder === null) {
                                disposalSendOrder = order; result.native.disposal_unsubscribe_sent = true;
                            }
                            if (summaryMode && role === 'target' && j.action === 'unsubscribe') {
                                const binding = summaryBindings.get(j.data.binding);
                                check(phase === 'cleanup' && binding && binding.sent === null
                                    && disposalStartOrder !== null && order > disposalStartOrder, 'unexpected_summary_unsubscribe');
                                binding.sent = order;
                            }
                            const sent = {action: j.action, binding: j.data.binding, account: j.data.account_id,
                                requestId: j.request_id, role, phase, order, connection,
                                disposal, afterDetailGet: firstDetailOrder !== null && order > firstDetailOrder,
                                afterOverviewGet: firstOverviewOrder !== null && order > firstOverviewOrder};
                            recordHomeCommand(admission, sent);
                            if (reconnectActive) reconnectProbe.sent({connection, order, requestId: j.request_id,
                                action: j.action, accountId: j.data.account_id, binding: j.data.binding});
                            seenRequestIds.add(j.request_id);
                            wire.set(j.request_id, sent);
                            server.send(message); // Actual bytes, token stays only in memory.
                        } catch (_) {
                            result.counts.blocked_socket_frames++;
                            diagnostic(result.blocked_socket_diagnostics, {phase,
                                action:['subscribe','unsubscribe'].includes(frame?.action)?frame.action:'other',
                                account:frame?.data?.account_id===account?'target':frame?.data?.account_id===loginAccount?'login':'other',
                                exact_queue_binding:/^queue_live\.changed\.[a-f0-9]{32}$/.test(frame?.data?.binding||''),
                                lifecycle_request:/^lifecycle-[A-Za-z0-9-]+$/.test(frame?.request_id||''),
                                top_shape:!!frame&&Object.keys(frame).sort().join(',')==='action,auth_token,data,request_id',
                                data_shape:!!frame?.data&&Object.keys(frame.data).sort().join(',')==='account_id,binding'});
                            route.close();
                        }
                    });
                    server.onMessage(message => {
                        try {
                            check(typeof message === 'string' && Buffer.byteLength(message) <= 65536, 'unsafe_server_frame');
                            const j = JSON.parse(message), sent = wire.get(j.request_id);
                            if (j.action === 'reply' && sent) {
                                wire.delete(j.request_id);
                                const selected = sent.role === 'target' && sent.binding === 'queue_live.changed.' + queue;
                                const order = timeline('socket_reply', sent.role === 'home' ? 'home_queue_subscription'
                                    : selected ? 'selected_queue_subscription' : 'other_page_queue_subscription',
                                    null, sent.order, j.status === 'success' ? 'success' : j.status === 'error' ? 'error' : 'invalid');
                                if (reconnectActive && reconnectProbe.reply({connection, order, requestId: j.request_id,
                                    status: j.status, data: j.data})) reconnectAckAt = Date.now();
                                if (observeHomeReply(admission, sent, j, order)) {
                                    if (sent.action === 'subscribe') result.account_switch.home_subscribe_ack = true;
                                    else result.account_switch.home_unsubscribe_ack = true;
                                }
                                if (sent.role === 'target' && sent.action === 'subscribe' && j.status === 'success'
                                    && Array.isArray(j.data?.subscriptions) && j.data.subscriptions.includes(sent.binding)) {
                                    result.counts.native_subscribe_acks++;
                                    if (summaryMode) {
                                        check(Array.isArray(j.data.subscribed) && j.data.subscribed.length === 1
                                            && j.data.subscribed[0] === sent.binding && !summaryBindings.has(sent.binding)
                                            && summaryBindings.size < 100, 'exact_summary_subscribe_ack_required');
                                        summaryBindings.set(sent.binding, {sent: null, ack: null});
                                    }
                                    if (sent.phase === 'detail' && sent.afterDetailGet && selected && firstDetailAck === null) {
                                        firstDetailAck = {order, time: Date.now(), connection}; result.native.detail_ack = true;
                                    }
                                    if (summaryMode && sent.phase === 'overview' && sent.afterOverviewGet && selected && firstOverviewAck === null) {
                                        firstOverviewAck = {order, time: Date.now()};
                                    }
                                }
                                if (sent.role === 'target' && sent.action === 'unsubscribe') {
                                    const accepted = j.status === 'success' && Array.isArray(j.data?.unsubscribed)
                                        && j.data.unsubscribed.includes(sent.binding);
                                    if (accepted) result.counts.native_unsubscribe_acks++;
                                    if (summaryMode) {
                                        const binding = summaryBindings.get(sent.binding);
                                        check(accepted && j.data.unsubscribed.length === 1 && binding
                                            && binding.sent === sent.order && Array.isArray(j.data.subscriptions)
                                            && !j.data.subscriptions.includes(sent.binding), 'exact_summary_unsubscribe_ack_required');
                                        binding.ack = order;
                                        summaryFinalSubscriptionsEmpty = j.data.subscriptions.length === 0;
                                    }
                                    if (sent.disposal && sent.order === disposalSendOrder) {
                                        if (reconnectMode) check(sent.connection === reconnectProbe.evidence().newConnection,
                                            'cleanup_not_on_reconnected_socket');
                                        if (!accepted) fail('selected_disposal_unsubscribe_rejected');
                                        else { disposalAckOrder = order; result.native.disposal_unsubscribe_ack = true; }
                                    }
                                }
                            }
                            if (j.action === 'event' && j.name === 'changed'
                                && j.subscribed_key === 'queue_live.changed.' + queue
                                && j.data?.version === 1 && j.data.account_id === account && j.data.queue_id === queue) result.counts.native_events++;
                            if (callObserver && (summaryMode ? ['overview', 'summary_call'].includes(phase) : phase === 'detail') && j.action === 'event'
                                && j.subscribed_key === 'queue_live.changed.' + queue) {
                                callObserver.recordEvent(j, timeline('socket_event', 'selected_queue_subscription'));
                            }
                            route.send(message); // No fake ACK, event or payload rewriting.
                        } catch (_) { fail('native_frame_observation_failed'); route.close(); }
                    });
                } catch (_) { fail('socket_guard_failed'); route.close(); }
            });
            const page = await context.newPage(); page.setDefaultTimeout(15000);
            if (natural) {
                const {createBrowserCallObserver, createBrowserSummaryObserver, readRenderedCall, BrowserCallError} = require('./test-fixtures/monster-live-call-observer.cjs');
                observerErrorClass = BrowserCallError;
                callObserver = (summaryMode ? createBrowserSummaryObserver : createBrowserCallObserver)({accountId: account, queueId: queue,
                    readPage: () => page.evaluate(readRenderedCall, {accountId: account, queueId: queue, overview: summaryMode}),
                    getOrder: () => serial, checkClean});
            }
            page.on('console', m => { if (!stopping && m.type() === 'error') result.counts.console_errors++; });
            page.on('pageerror', error => { if (!stopping) { result.counts.page_errors++; diagnostic(result.browser_errors, browserErrorDiagnostic(error, target.origin)); } });
            page.on('request', request => {
                const u = new URL(request.url());
                if (request.method() === 'GET' && same(u, api) && u.pathname === detailPath && firstDetailOrder === null) {
                    if (summaryMode) fail('unexpected_detail_get_in_summary');
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
                    if (summaryMode) {
                        if (firstOverviewOrder === null) { firstOverviewOrder = order; overviewStarted = Date.now(); }
                        if (overviewLedger.length >= 128) { fail('summary_request_limit'); return; }
                        overviewInFlight++; maxOverviewInFlight = Math.max(maxOverviewInFlight, overviewInFlight);
                        const item = {order, time: Date.now(), status: null, overview: true}; overviewLedger.push(item); requests.set(request, item);
                    }
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
                } else if ((phase === 'summary_call' && u.pathname !== overviewPath) || (phase === 'detail' && !livePath(u)) || (phase === 'detail_transition'
                    && ['queue_roster', 'agent_names', 'agent_global_status', 'user_names'].includes(category(u)))) result.counts.supplemental_gets++;
            });
            page.on('requestfinished', r => { if (requests.has(r)) { if (requests.get(r).overview) overviewInFlight--; else detailInFlight--; } });
            page.on('requestfailed', r => {
                if (requests.has(r)) { if (requests.get(r).overview) overviewInFlight--; else detailInFlight--; }
                if (!stopping) { httpFailure(r, 0); if (scopedRequests.has(r)) result.counts.failed_requests++; }
            });
            page.on('response', response => {
                const u = new URL(response.url()), item = requests.get(response.request());
                if (item) item.status = response.status();
                const responseOrder = same(u, api) && u.pathname.startsWith('/v2/')
                    ? timeline('http_response', category(u), response.status(), httpOrders.get(response.request()) || null) : null;
                if (reconnectActive && item && !item.overview && response.status() === 200 && !reconnectSnapshot) track((async () => {
                    const bytes = await response.body();
                    check(bytes.length <= 2 * 1024 * 1024, 'reconnect_detail_body_limit');
                    const {validateDetail} = require('./test-fixtures/queue-live-observer.cjs');
                    const dto = validateDetail(JSON.parse(bytes.toString('utf8')), account, queue);
                    if (!reconnectSnapshot && reconnectProbe.snapshot({requestOrder: item.order, responseOrder,
                        noStore: response.headers()['cache-control'] === 'no-store'})) {
                        reconnectSnapshot = {dto: JSON.stringify(dto), requestAt: item.time};
                    }
                })(), 'reconnect_snapshot_validation_failed');
                if (callObserver && item && Boolean(item.overview) === summaryMode && response.status() === 200) track((async () => {
                    const bytes = await response.body(); check(bytes.length <= 2 * 1024 * 1024, summaryMode ? 'natural_overview_body_limit' : 'natural_detail_body_limit');
                    callObserver.recordResponse({body: JSON.parse(bytes.toString('utf8')), requestOrder: item.order,
                        responseOrder, requestAt: item.time, noStore: response.headers()['cache-control'] === 'no-store'});
                })(), summaryMode ? 'natural_overview_validation_failed' : 'natural_detail_validation_failed');
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
            const initialUrl = new URL(target.href);
            if (scope.switching) initialUrl.hash = 'apps/acdc';
            checkpoint('opening_production_index'); await page.goto(initialUrl.href, {waitUntil: 'domcontentloaded', timeout: 30000});
            checkpoint('filling_normal_login');
            await page.locator('#login').fill(secret.user); await page.locator('#password').fill(secret.password);
            secret.password = ''; secret.user = '';
            await page.locator('#account_name').fill(loginName);
            const authWait = page.waitForResponse(r => same(new URL(r.url()), api)
                && new URL(r.url()).pathname === '/v2/user_auth' && r.request().method() === 'PUT');
            checkpoint('submitting_normal_login'); await page.getByRole('button', {name: 'Sign in', exact: true}).click();
            const authResponse = await authWait;
            const auth = await authResponse.json();
            check(authResponse.ok() && auth.status === 'success' && auth.data?.account_id === loginAccount, 'web_login_scope_failed');
            delete auth.auth_token;
            checkpoint('waiting_authenticated_shell'); await page.locator('#login').waitFor({state: 'hidden', timeout: 25000});
            await page.waitForFunction(() => window.require('monster').apps.auth.appsStore !== undefined);
            await page.waitForLoadState('networkidle', {timeout: 15000});
            result.checks.push('normal_web_login_expected_account');
            await page.evaluate(() => window.require('monster').pub('myaccount.hide'));
            if (scope.switching) {
                phase = 'home_overview';
                checkpoint('waiting_valid_home_overview_and_native_ack');
                await page.locator('.acdc-live-queue-grid').waitFor({state: 'visible'});
                await page.waitForFunction(homeOverviewInBrowser, scope, {timeout: 20000});
                const homeAckUntil = Date.now() + 5000;
                while (Date.now() < homeAckUntil && admission.subscribeAck === null && !fatal) await page.waitForTimeout(50);
                check(!fatal, fatal || 'home_native_observation_failed');
                check(admission.subscribeAck !== null, 'correlated_home_subscribe_ack_required');
                result.account_switch.home_overview_verified = true;
                phase = 'home_cleanup';
                checkpoint('navigating_home_to_queues');
                beginHomeDisposal(admission, timeline('navigation_disposal', 'home_queue_subscription'));
                await page.locator('.acdc-tab[data-tab="queues"]').click();
                await page.waitForFunction(queuesDisposedInBrowser);
                await page.waitForFunction(accountScopeInBrowser,
                    {...scope, account: loginAccount, requireAcdc: true}, {timeout: 10000});
                result.account_switch.home_controller_disposed = true;
                checkpoint('waiting_exact_home_unsubscribe_ack');
                const homeUntil = Date.now() + 5000;
                while (Date.now() < homeUntil && admission.unsubscribeAck === null && !fatal) await page.waitForTimeout(50);
                closeHomeAdmission(admission, await page.evaluate(queuesDisposedInBrowser));
                result.account_switch.home_admission_closed = true;
                checkClean();
                result.checks.push('pinned_home_overview_ack_and_disposal_ack_before_switch');
                phase = 'account_switch';
                result.account_switch.target_verified = await switchTargetAccount(page, api, scope, checkpoint);
                await page.waitForLoadState('networkidle', {timeout: 10000});
                checkClean();
                result.checks.push('normal_account_browser_target_read_and_scope_verified');
            }
            phase = 'overview';
            checkpoint('routing_to_acdc');
            await page.evaluate(() => window.require('monster').routing.goTo('apps/acdc'));
            if (scope.switching) await page.waitForFunction(accountScopeInBrowser,
                {...scope, requireAcdc: true}, {timeout: 10000});
            // A real company switch preserves the Queues tab used for home
            // disposal. Select Dashboard before waiting for its absent grid.
            if (scope.switching) {
                checkpoint('clicking_switched_dashboard_tab');
                await page.locator('.acdc-tab[data-tab="dashboard"]').click();
            }
            checkpoint('waiting_overview_grid'); await page.locator('.acdc-live-queue-grid').waitFor({state: 'visible'});
            // Normal dashboard tab and queue controls, never app request/mock seams.
            if (!scope.switching) {
                checkpoint('clicking_dashboard_tab'); await page.locator('.acdc-tab[data-tab="dashboard"]').click();
            }
            checkpoint('waiting_valid_overview_snapshot');
            await page.waitForFunction(expected => {
                const app = window.require('monster').apps.acdc, c = app.appFlags.acdc.liveDashboardController;
                const s = app.appFlags.acdc.liveDashboardSnapshot;
                return app.accountId === expected && c && !c.inFlight && s && !s.queueId && s.accountId === expected
                    && app.liveSnapshotValid(s.results.live, expected, undefined, s.page);
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
            if (summaryMode) {
                checkpoint('waiting_native_selected_overview_ack_refetch');
                const until = Math.min(overviewStarted + 14000, Date.now() + 5000);
                while (Date.now() < until && !(firstOverviewAck && overviewLedger.some(r => r.order > firstOverviewAck.order && r.status === 200)) && !fatal) {
                    await page.waitForTimeout(50);
                }
                check(firstOverviewAck && overviewLedger.some(r => r.order > firstOverviewAck.order && r.status === 200
                    && r.time < overviewStarted + 14000), 'native_overview_ack_refetch_before_periodic_required');
                await page.waitForFunction(({account, ackAt}) => {
                    const app = window.require('monster').apps.acdc, c = app.appFlags.acdc.liveDashboardController;
                    const s = app.appFlags.acdc.liveDashboardSnapshot;
                    return c && !c.queueId && c.accountId === account && !c.inFlight && s && !s.queueId
                        && s.accountId === account && s.receivedAt >= ackAt
                        && app.liveSnapshotValid(s.results.live, account, undefined, s.page);
                }, {account, ackAt: firstOverviewAck.time}, {timeout: 3000});
                result.native.supported = true;
                result.natural_summary = {selected_subscribe_ack: true, ack_refetch: true};
                await Promise.all([...pending]); checkClean();
                check(maxOverviewInFlight === 1 && result.counts.detail_gets === 0, 'summary_request_fanout');
                result.natural_summary.baseline = await callObserver.ready();
                callObserver.assertSummaryBindings([...summaryBindings.keys()]);
                phase = 'summary_call';
                checkpoint('observing_owned_call_in_visible_overview');
                await natural.runCall(Object.freeze({waitForPhase: callObserver.waitForPhase}));
                result.natural_summary.observation = callObserver.finish();
                callObserver.assertSummaryBindings([...summaryBindings.keys()]);
                check(maxOverviewInFlight === 1 && result.counts.detail_gets === 0 && result.counts.supplemental_gets === 0, 'summary_request_fanout');
                check(result.counts.auth === 1, 'exactly_one_normal_auth_required'); checkClean();
                result.checks.push('natural_summary_waiting_handled_zero_card_counts_and_page_dto_match');
            } else {
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
            if (reconnectMode) {
                checkpoint('closing_only_test_socket_for_reconnect');
                await Promise.all([...pending]); checkClean();
                const {readRenderedCall} = require('./test-fixtures/monster-live-call-observer.cjs');
                const baseline = await page.evaluate(readRenderedCall, {accountId: account, queueId: queue});
                check(baseline.valid && currentWire && currentWire.wire.size === 0
                    && currentWire.connection === firstDetailAck.connection && connectionSequence === 1,
                    'reconnect_baseline_not_quiescent');
                const oldWire = currentWire, started = Date.now();
                reconnectProbe.begin({connection: oldWire.connection, order: timeline('socket_test_close', 'selected_queue_subscription')});
                reconnectActive = true;
                reconnectGate = new Promise(resolve => { releaseReconnect = resolve; });
                await Promise.all([oldWire.server.close({code: 1012}), oldWire.route.close({code: 1012})]);
                checkpoint('waiting_visible_disconnected_stale_state');
                await page.waitForFunction(({account, queue, generation, dto}) => {
                    const app = window.require('monster').apps.acdc, c = app.appFlags.acdc.liveDashboardController;
                    const s = app.appFlags.acdc.liveDashboardSnapshot, root = document.querySelector('.acdc-live-dashboard');
                    const note = root?.querySelector('.acdc-live-stale-note');
                    return c && s && root && c.view?.[0] === root && root.getClientRects().length > 0
                        && c.generation === generation && c.accountId === account && c.queueId === queue
                        && s.accountId === account && s.queueId === queue && JSON.stringify(s.results.live) === dto
                        && app.liveTransportState(c) === 'disconnected' && root.querySelector('.acdc-live-freshness.is-stale')
                        && note && !note.hidden;
                }, {account, queue, generation: baseline.generation, dto: baseline.dto}, {timeout: 2000, polling: 20});
                result.checks.push('actual_disconnect_retains_snapshot_and_marks_visible_detail_stale');
                releaseReconnect(); releaseReconnect = null; reconnectGate = null;
                checkpoint('waiting_new_socket_ack_and_fresh_detail');
                while (Date.now() < started + 12000 && !reconnectSnapshot && !fatal) await page.waitForTimeout(50);
                await Promise.all([...pending]); checkClean();
                check(reconnectSnapshot && reconnectProbe.evidence().complete && connectionSequence === 2
                    && Date.now() < started + 12000 && reconnectAckAt !== null
                    && reconnectSnapshot.requestAt >= reconnectAckAt && reconnectSnapshot.requestAt <= reconnectAckAt + 5000,
                    'reconnect_ack_snapshot_deadline');
                await page.waitForFunction(({account, queue, generation, dto}) => {
                    const app = window.require('monster').apps.acdc, c = app.appFlags.acdc.liveDashboardController;
                    const s = app.appFlags.acdc.liveDashboardSnapshot;
                    return c && s && c.generation === generation && c.accountId === account && c.queueId === queue
                        && s.accountId === account && s.queueId === queue && !c.inFlight
                        && app.liveTransportState(c) === 'acknowledged' && JSON.stringify(s.results.live) === dto;
                }, {account, queue, generation: baseline.generation, dto: reconnectSnapshot.dto},
                {timeout: Math.max(1, Math.min(3000, started + 12000 - Date.now()))});
                const recovered = await page.evaluate(readRenderedCall, {accountId: account, queueId: queue});
                check(recovered.valid && recovered.generation === baseline.generation
                    && recovered.dto === reconnectSnapshot.dto && recovered.receivedAt >= reconnectSnapshot.requestAt
                    && maxDetailInFlight === 1 && Date.now() < started + 12000, 'reconnect_rendered_snapshot_mismatch');
                require('./test-fixtures/monster-live-reconnect.cjs').matchReconnectCallRendering(
                    recovered, JSON.parse(reconnectSnapshot.dto));
                result.reconnect = {...reconnectProbe.evidence(), disconnected_stale_observed: true,
                    rendered_call_counts_rows_match: true, same_controller: true, elapsed_ms: Date.now() - started,
                    periodic_causality_excluded: false};
                result.checks.push('new_socket_exact_ack_then_no_store_get_matches_visible_detail');
                reconnectActive = false;
            }
            if (natural) {
                checkpoint('waiting_empty_detail_before_owned_call');
                await Promise.all([...pending]); checkClean();
                result.natural_call = {baseline: await callObserver.ready()};
                checkpoint('observing_owned_call_in_actual_browser');
                await natural.runCall(Object.freeze({waitForPhase: callObserver.waitForPhase}));
                result.natural_call.observation = callObserver.finish();
                check(maxDetailInFlight === 1 && result.counts.supplemental_gets === 0, 'natural_detail_fanout_or_overlap');
                checkClean();
                result.checks.push('natural_waiting_handled_gone_native_hints_gets_and_rendered_rows');
            }
            }
            // Normal navigation retires the local controller, then closing the
            // ephemeral context removes the session. No persistent logout write.
            phase = 'cleanup';
            checkpoint(summaryMode ? 'navigating_away_from_live_overview' : 'navigating_away_from_live_detail');
            disposalStartOrder = timeline('navigation_disposal', 'selected_queue_subscription');
            await page.locator('.acdc-tab[data-tab="queues"]').click();
            await page.waitForFunction(() => !window.require('monster').apps.acdc.appFlags.acdc.liveDashboardController);
            result.checks.push('navigation_disposes_live_controller');
            if (result.native.supported) {
                checkpoint('waiting_selected_disposal_unsubscribe_ack');
                const until = Date.now() + 5000;
                while (Date.now() < until && disposalAckOrder === null && !fatal) await page.waitForTimeout(50);
                check(disposalSendOrder !== null && disposalAckOrder !== null && disposalAckOrder > disposalSendOrder,
                    'correlated_selected_disposal_unsubscribe_ack_required');
                result.checks.push('normal_navigation_selected_unsubscribe_sent_and_acknowledged');
                if (summaryMode) {
                    const allDisposed = () => summaryBindings.size > 0
                        && summaryFinalSubscriptionsEmpty
                        && [...summaryBindings.values()].every(b => b.sent !== null && b.ack !== null && b.ack > b.sent);
                    const allUntil = Date.now() + 5000;
                    while (Date.now() < allUntil && !allDisposed() && !fatal) await page.waitForTimeout(50);
                    check(allDisposed(), 'all_summary_unsubscribe_acks_required');
                    result.natural_summary.disposal = {bindings: summaryBindings.size,
                        exact_page_bindings_verified: true, all_unsubscribe_acks: true, final_subscriptions_empty: true};
                }
            }
            if (scope.switching) {
                // Restore only after normal detail disposal and its real ACK.
                // Failures instead close the ephemeral context; no logout write.
                await page.waitForLoadState('networkidle', {timeout: 10000});
                phase = 'account_restore';
                result.account_switch.home_restored = await restoreHomeAccount(page, scope, checkpoint);
                await page.waitForLoadState('networkidle', {timeout: 10000});
                check(result.counts.auth === 1, 'exactly_one_normal_auth_required');
                result.checks.push('normal_home_account_restored_after_detail_disposal');
            }
            checkpoint('verifying_served_asset_hashes'); await Promise.all([...pending]); checkClean();
            check(['index.html', 'js/main.js', 'js/templates.js', 'js/config.js', 'css/style.css']
                .every(file => result.production_assets[file])
                && (preloadedAcdc || result.production_assets['apps/acdc/app.js'])
                && (!scope.switching || result.production_assets[ACCOUNT_BROWSER_ASSET]), 'actual_deployed_asset_receipts_missing');
            result.checks.push('actual_served_production_bytes_match_expected_deployed_files');
            result.status = requiredSocket ? 'PASS' : (result.native.supported ? 'PASS' : 'PASS_SNAPSHOT_ONLY');
        } finally { clearTimeout(deadline); }
    } catch (e) {
        result.failure = fatal || (e instanceof Failure || (observerErrorClass && e instanceof observerErrorClass)
            || (reconnectErrorClass && e instanceof reconnectErrorClass)
            ? e.message : 'browser_or_input_step_failed');
        result.failure_phase = phase; result.failure_checkpoint = result.checkpoints.at(-1) || 'preflight';
    }
    finally {
        stopping = true;
        if (releaseReconnect) releaseReconnect();
        if (reconnectProbe && !result.reconnect) result.reconnect = reconnectProbe.evidence();
        if (context) await context.close().catch(() => fail('context_cleanup_failed'));
        if (browser) await browser.close().catch(() => fail('browser_cleanup_failed'));
        await Promise.all([...pending]);
        try { result.after = pins(); check(JSON.stringify(result.after) === JSON.stringify(before), 'input_changed_during_smoke'); }
        catch (_) { fail('input_changed_during_smoke'); }
        if (fatal) { result.status = 'FAIL'; result.failure = fatal; }
        // Fixed codes and numeric/boolean/hash observations only. No exception,
        // response text, credentials, frames, request IDs or user/call names.
        if (callObserver && result.status === 'FAIL') {
            const key = summaryMode ? 'natural_summary' : 'natural_call';
            result[key] = {...result[key], observation: callObserver.evidence()};
        }
        fs.writeFileSync(path.join(evidenceDir, 'receipt.json'), JSON.stringify(result, null, 2) + '\n', {flag: 'wx', mode: 0o600});
        summary = {status: result.status, evidence: path.join(evidenceDir, 'receipt.json'),
            checks: result.checks.length, failure: result.failure || null};
        if (!natural) {
            process.stdout.write(JSON.stringify(summary) + '\n');
            if (result.status === 'FAIL') process.exitCode = 1;
        }
    }
    return summary;
}
async function runNaturalBrowser(options, overview) {
    try {
        check(options && !Array.isArray(options) && Object.keys(options).sort().join(',')
            === 'accountId,loginAccountId,loginQueueId,queueId,runCall'
            && ['accountId', 'queueId', 'loginAccountId', 'loginQueueId'].every(k => ID.test(options[k] || ''))
            && options.accountId !== options.loginAccountId && typeof options.runCall === 'function', 'invalid_natural_call_options');
        const env = {...process.env, KAZOO_TEST_ACCOUNT_ID: options.accountId, KAZOO_TEST_QUEUE_ID: options.queueId,
            KAZOO_TEST_LOGIN_ACCOUNT_ID: options.loginAccountId, KAZOO_TEST_LOGIN_QUEUE_ID: options.loginQueueId,
            KAZOO_TEST_REQUIRE_WEBSOCKET: 'true'};
        return await main({env, runCall: options.runCall, overview});
    } catch (e) {
        return {status: 'FAIL', evidence: null, checks: 0,
            failure: e instanceof Failure ? e.message : 'embedded_browser_preflight_failed'};
    }
}
async function runWithNaturalCall(options) { return runNaturalBrowser(options, false); }
async function runWithNaturalSummaryCall(options) { return runNaturalBrowser(options, true); }
module.exports = {accountScopeOptions, accountScopeInBrowser, targetAccountResponse,
    verifyTargetAccountResponse, switchTargetAccount, restoreHomeAccount, browserErrorDiagnostic, ACCOUNT_BROWSER_ASSET,
    socketAdmission, socketScopeRole, recordHomeCommand, observeHomeReply, beginHomeDisposal, closeHomeAdmission,
    homeOverviewInBrowser, queuesDisposedInBrowser, runWithNaturalCall, runWithNaturalSummaryCall, reconnectOptions};
if (require.main === module) main().catch(e => {
    process.stderr.write(JSON.stringify({status: 'FAIL', failure: e instanceof Failure ? e.message : 'preflight_failed'}) + '\n');
    process.exitCode = 1;
});
