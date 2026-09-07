#!/usr/bin/env node
'use strict';
// Offline boundary tests of the actual harness helpers with a controlled page.
// No browser, HTTP/WS, credentials, account provisioning or production execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path');
const vm = require('node:vm'), crypto = require('node:crypto');
const h = require('./test-monster-live-deployed.cjs');
const sourceFile = path.join(__dirname, 'test-monster-live-deployed.cjs');
const appFile = path.join(__dirname, '../monster-ui/acdc/app.js');
const source = fs.readFileSync(sourceFile, 'utf8'), app = fs.readFileSync(appFile, 'utf8');
const hash = s => crypto.createHash('sha256').update(s).digest('hex');
const LOGIN = 'a'.repeat(32), TARGET = 'b'.repeat(32), QUEUE = 'c'.repeat(32), HOME_QUEUE = 'd'.repeat(32);
const api = new URL('http://127.0.0.1:8000/v2');
const base = {KAZOO_TEST_ACCOUNT_ID: TARGET, KAZOO_TEST_QUEUE_ID: QUEUE};
const switchEnv = {...base, KAZOO_TEST_LOGIN_ACCOUNT_ID: LOGIN, KAZOO_TEST_LOGIN_QUEUE_ID: HOME_QUEUE};
const scope = h.accountScopeOptions(switchEnv);
let groups = 0;
const test = async (name, f) => { await f(); groups++; console.log('PASS ' + name); };
function response({id = TARGET, status = 200, method = 'GET', url = api.origin + '/v2/accounts/' + TARGET,
    result = 'success'} = {}) {
    const body = {status: result, data: {id}, auth_token: 'OFFLINE-SECRET-NOT-LOGGED'};
    return {url: () => url, status: () => status, request: () => ({method: () => method}), json: async () => body, body};
}
function browser({original = LOGIN, current = TARGET, appAccount = TARGET, masquerading = true,
    liveController = undefined, masqueradable = true, tab = 'queues'} = {}) {
    const monster = {apps: {auth: {originalAccount: {id: original}, currentAccount: {id: current}},
        acdc: {accountId: appAccount, isMasqueradable: masqueradable,
            appFlags: {acdc: {currentTab: tab, liveDashboardController: liveController}}}}};
    const view = {masquerading};
    const context = {window: {require: name => { assert.equal(name, 'monster'); return monster; }},
        document: {querySelector: selector => {
            assert.equal(selector, '#main_topbar_account_toggle');
            return {classList: {contains: name => { assert.equal(name, 'masquerading'); return view.masquerading; }}};
        }}};
    return {monster, view, evaluate(fn, arg) {
        context.arg = arg;
        return vm.runInNewContext('(' + fn.toString() + ')(arg)', context, {timeout: 1000});
    }};
}
function pageDouble(options = {}) {
    const b = browser({current: LOGIN, appAccount: LOGIN, masquerading: false});
    let count = options.initialRows ?? 1, reply, typed = '', opened = false, inputVisible = false, listReady = false;
    const events = [], checkpoints = [];
    const rowSelector = '#main_topbar_account_toggle_container .account-list .account-list-element[data-id="' + TARGET + '"] .account-link';
    const page = {
        locator(selector) {
            if (selector === '#main_topbar_account_toggle_link[aria-disabled="false"]') return {async waitFor(o) {
                assert.equal(o.state, 'visible'); assert.equal(o.timeout, 10000);
                assert(!options.pickerDisabled, 'fixture_picker_not_ready'); events.push('picker_ready');
            }};
            if (selector === '#main_topbar_account_toggle_link') return {async click() { opened = true; events.push('open'); }};
            if (selector.endsWith(' .account-browser-search')) return {
                async waitFor(o) { assert(opened); assert.equal(o.state, 'visible'); inputVisible = true; events.push('input_visible'); },
                async pressSequentially(text) { assert(listReady); assert.equal(text, TARGET); typed = text; events.push('type_id'); },
                async press(key) { assert.equal(key, 'Enter'); assert.equal(typed, TARGET); count = 1; events.push('search_enter'); }
            };
            if (selector.endsWith(' .account-list-loader')) return {async waitFor(o) {
                assert(inputVisible); assert.equal(o.state, 'detached'); listReady = true; events.push('initial_list_ready');
            }};
            if (selector === rowSelector) return {
                async count() { return count; },
                async waitFor(o) { assert.equal(o.state, 'visible'); assert(count > 0); },
                async click() {
                    assert(reply, 'response waiter must precede native click'); events.push('click_target');
                    if (!options.failedSwitch) {
                        b.monster.apps.auth.currentAccount.id = TARGET;
                        b.monster.apps.acdc.accountId = TARGET; b.view.masquerading = true;
                    }
                    reply(options.response || response());
                }
            };
            if (selector === '#main_topbar_account_toggle_container .home-account-link') return {async click() {
                assert(opened); events.push('click_home'); b.monster.apps.auth.currentAccount.id = LOGIN;
                b.monster.apps.acdc.accountId = LOGIN; b.view.masquerading = false;
                if (options.homeController) b.monster.apps.acdc.appFlags.acdc.liveDashboardController = {accountId: LOGIN};
                if (options.homeTab) b.monster.apps.acdc.appFlags.acdc.currentTab = options.homeTab;
            }};
            throw Error('unexpected fixture locator');
        },
        waitForResponse(predicate, o) {
            assert.equal(o.timeout, 10000); assert(predicate(options.response || response())); events.push('watch_target_get');
            return new Promise(resolve => { reply = resolve; });
        },
        async waitForFunction(fn, arg) {
            events.push('assert_scope');
            assert.equal(b.evaluate(fn, arg), true, 'fixture_scope_not_reached');
        }
    };
    return {page, events, checkpoints, checkpoint: name => checkpoints.push(name), b};
}
function homeProof() {
    const admission = h.socketAdmission(scope), binding = 'queue_live.changed.' + HOME_QUEUE;
    const sent = {role: 'home', account: LOGIN, binding, action: 'subscribe', order: 1, requestId: 'lifecycle-home-1'};
    const reply = {action: 'reply', request_id: sent.requestId, status: 'success', data: {subscribed: [binding], subscriptions: [binding]}};
    h.recordHomeCommand(admission, sent);
    return {admission, sent, reply, binding};
}
function completeHome() {
    const f = homeProof(); h.observeHomeReply(f.admission, f.sent, f.reply, 2); h.beginHomeDisposal(f.admission, 3);
    f.stop = {...f.sent, action: 'unsubscribe', order: 4, requestId: 'lifecycle-home-2'};
    f.stopReply = {action: 'reply', request_id: f.stop.requestId, status: 'success', data: {unsubscribed: [f.binding], subscriptions: []}};
    h.recordHomeCommand(f.admission, f.stop); h.observeHomeReply(f.admission, f.stop, f.stopReply, 5);
    return f;
}
function homeBrowser() {
    const b = browser({current: LOGIN, appAccount: LOGIN, masquerading: false, tab: 'dashboard'});
    const app = b.monster.apps.acdc;
    app.appFlags.acdc.liveDashboardController = {accountId: LOGIN, supported: true};
    app.appFlags.acdc.liveDashboardSnapshot = {accountId: LOGIN, page: {}, results: {live: {queues: [{id: HOME_QUEUE}]}}};
    app.liveTransportState = () => 'acknowledged'; app.liveSnapshotValid = () => true;
    return b;
}
(async () => {
    await test('native startup route must finish before harness navigation', () => {
        const monster = {apps: {auth: {defaultApp: 'voip'}, core: {_defaultApp: 'appstore', appFlags: {accountBrowserState: 'loading'}},
            getActiveApp: () => active}, routing: {getUrl: () => url}, util: {isAdmin: () => true}};
        let active = 'auth', url = '';
        const context = {window: {require: () => monster}, args: {switching: false}};
        const read = () => vm.runInNewContext('(' + h.startupRouteReadyInBrowser.toString() + ')(args)', context);
        assert.equal(read(), false);
        active = 'voip'; url = 'apps/voip'; assert.equal(read(), false);
        monster.apps.core.appFlags.accountBrowserState = 'ready'; assert.equal(read(), true);
        active = 'myaccount'; assert.equal(read(), false);
        monster.apps.auth.defaultApp = 'acdc'; active = 'acdc'; url = 'apps/acdc'; assert.equal(read(), true);
        delete monster.apps.auth.defaultApp; active = 'appstore'; url = 'apps/appstore'; assert.equal(read(), true);
        context.args.switching = true; assert.equal(read(), false);
        active = 'acdc'; url = 'apps/acdc'; assert.equal(read(), true);
        assert(source.indexOf('await page.waitForFunction(startupRouteReadyInBrowser') < source.indexOf("checkpoint('routing_to_acdc')"));
        assert(source.includes("if (switching || monster.apps.getActiveApp() !== 'acdc') monster.routing.goTo('apps/acdc');"));
        assert(source.includes("['bootstrap', 'overview'].includes(sent.phase) && sent.afterOverviewGet && selected"));
    });
    await test('Core alert refresh is separate from forbidden dashboard supplemental reads', () => {
        for (const phase of ['summary_call', 'summary_reconnect', 'detail']) {
            assert.equal(h.supplementalLiveGet(phase, 'framework_alerts'), false);
            assert.equal(h.supplementalLiveGet(phase, 'live_overview'), false);
            for (const category of ['queue_roster', 'agent_names', 'agent_global_status', 'user_names', 'other_api', 'queue_catalog', 'home_live_overview']) {
                assert.equal(h.supplementalLiveGet(phase, category), true);
            }
        }
        assert.equal(h.supplementalLiveGet('summary_reconnect', 'live_detail'), true);
        assert.equal(h.supplementalLiveGet('detail', 'live_detail'), false);
        assert.equal(h.supplementalLiveGet('detail_transition', 'queue_roster'), true);
        assert(source.includes("u.pathname === '/v2/accounts/' + account + '/alerts'"));
        assert(source.includes("} else if (supplementalLiveGet(phase, category(u)))"));
    });
    await test('reconnect fault injection is explicit standalone and requires native sockets', () => {
        assert.equal(h.reconnectOptions({}, false), false);
        assert.equal(h.reconnectOptions({KAZOO_TEST_RECONNECT: 'false'}, true), false);
        assert.equal(h.reconnectOptions({KAZOO_TEST_RECONNECT: 'true', KAZOO_TEST_REQUIRE_WEBSOCKET: 'true'}, false), true);
        for (const view of ['detail', 'summary']) assert.equal(h.reconnectOptions({KAZOO_TEST_RECONNECT: 'true',
            KAZOO_TEST_REQUIRE_WEBSOCKET: 'true', KAZOO_TEST_RECONNECT_VIEW: view}, false), true);
        for (const value of ['', 'yes', true, 1, null]) {
            assert.throws(() => h.reconnectOptions({KAZOO_TEST_RECONNECT: value}, false), /invalid_reconnect_mode/);
        }
        assert.throws(() => h.reconnectOptions({KAZOO_TEST_RECONNECT: 'true'}, false), /standalone_native_reconnect_required/);
        assert.throws(() => h.reconnectOptions({KAZOO_TEST_RECONNECT: 'true', KAZOO_TEST_REQUIRE_WEBSOCKET: 'true'}, {}), /standalone_native_reconnect_required/);
        for (const view of ['', 'all', true, null, 'queue']) assert.throws(() => h.reconnectOptions({KAZOO_TEST_RECONNECT: 'true',
            KAZOO_TEST_REQUIRE_WEBSOCKET: 'true', KAZOO_TEST_RECONNECT_VIEW: view}, false), /invalid_reconnect_view/);
        assert.throws(() => h.reconnectOptions({KAZOO_TEST_RECONNECT_VIEW: 'summary'}, false), /invalid_reconnect_view/);
    });
    await test('page-error diagnostics omit messages, unknown paths and URL secrets', () => {
        const error = {name: 'TypeError', message: 'SECRET is not a function', stack: 'TypeError: SECRET\n at f (http://ui.invalid/js/main.js?token=SECRET:84:120)\n at g (http://foreign.invalid/js/main.js:3:2)\n at h (http://ui.invalid/private/SECRET.js:3:2)'};
        const d = h.browserErrorDiagnostic(error, 'http://ui.invalid');
        assert.deepEqual(d, {name: 'TypeError', kind: 'missing_function', frames: [{asset:'ui_main',line:84,column:120}]});
        assert(!JSON.stringify(d).includes('SECRET'));
        assert.deepEqual(h.browserErrorDiagnostic({name:'SECRET',message:'SECRET',stack:'SECRET'}, 'http://ui.invalid'), {name:'other',kind:'other',frames:[]});
    });
    await test('same-account defaults preserve legacy login name and need no switch', () => {
        const o = h.accountScopeOptions({...base, KAZOO_TEST_ACCOUNT_NAME: 'Existing company'});
        assert.equal(o.loginAccount, TARGET); assert.equal(o.loginName, 'Existing company'); assert.equal(o.switching, false);
        assert.equal(o.loginQueue, QUEUE);
        assert.equal(h.accountScopeOptions(base).loginName, 'KazooMaster');
    });
    await test('explicit login principal is distinct from target and rejects unsafe identities', () => {
        const o = h.accountScopeOptions({...switchEnv,
            KAZOO_TEST_ACCOUNT_NAME: 'Legacy login', KAZOO_TEST_LOGIN_ACCOUNT_NAME: 'Explicit login'});
        assert.equal(o.account, TARGET); assert.equal(o.loginAccount, LOGIN); assert.equal(o.loginName, 'Explicit login');
        assert.equal(o.switching, true);
        assert.equal(o.loginQueue, HOME_QUEUE);
        for (const value of [undefined, '', HOME_QUEUE.toUpperCase(), HOME_QUEUE + '/other']) {
            assert.throws(() => h.accountScopeOptions({...switchEnv, KAZOO_TEST_LOGIN_QUEUE_ID: value}), /explicit_login_queue_required/);
        }
        for (const env of [{KAZOO_TEST_LOGIN_ACCOUNT_ID: ''}, {KAZOO_TEST_ACCOUNT_ID: TARGET + '/other'},
            {KAZOO_TEST_QUEUE_ID: ''}, {KAZOO_TEST_LOGIN_ACCOUNT_NAME: ''},
            {KAZOO_TEST_LOGIN_ACCOUNT_NAME: 'secret\nline'}, {KAZOO_TEST_LOGIN_ACCOUNT_NAME: 'x'.repeat(257)}]) {
            assert.throws(() => h.accountScopeOptions({...base, ...env}));
        }
    });
    await test('target readback requires actual selected GET origin path status and identity', async () => {
        assert(h.targetAccountResponse(response(), api, TARGET));
        for (const r of [response({method: 'POST'}), response({url: api.origin + '/v2/accounts/' + LOGIN}),
            response({url: 'http://other.invalid/v2/accounts/' + TARGET}),
            response({url: 'http://user@127.0.0.1:8000/v2/accounts/' + TARGET})]) {
            assert.equal(h.targetAccountResponse(r, api, TARGET), false);
        }
        for (const r of [response({status: 403}), response({id: LOGIN}), response({result: 'error'})]) {
            await assert.rejects(() => h.verifyTargetAccountResponse(r, TARGET), /masquerade_account_readback_failed/);
        }
        const r = response(); await h.verifyTargetAccountResponse(r, TARGET); assert.equal(r.body.auth_token, undefined);
    });
    await test('page assertions require original current app and visible masquerading scope without writes', () => {
        const good = browser(), before = JSON.stringify(good.monster);
        assert.equal(good.evaluate(h.accountScopeInBrowser, {...scope, requireAcdc: true}), true);
        assert.equal(JSON.stringify(good.monster), before);
        for (const o of [{original: TARGET}, {current: LOGIN}, {appAccount: LOGIN},
            {masquerading: false}, {masqueradable: false}]) {
            assert.equal(browser(o).evaluate(h.accountScopeInBrowser, {...scope, requireAcdc: true}), false);
        }
    });
    await test('same-account switch and home helpers perform no page action', async () => {
        const same = h.accountScopeOptions(base);
        assert.equal(await h.switchTargetAccount({}, api, same, () => assert.fail()), false);
        assert.equal(await h.restoreHomeAccount({}, same, () => assert.fail()), false);
    });
    await test('home admission permits only the pinned home account and queue before target', () => {
        const a = h.socketAdmission(scope), home = {account_id: LOGIN, binding: 'queue_live.changed.' + HOME_QUEUE};
        assert.equal(h.socketScopeRole(scope, a, home), 'home');
        for (const data of [{...home, account_id: TARGET}, {...home, account_id: 'e'.repeat(32)},
            {...home, binding: 'queue_live.changed.' + QUEUE}, {...home, binding: 'queue_live.changed.*'}]) {
            assert.throws(() => h.socketScopeRole(scope, a, data));
        }
        assert.equal(h.socketScopeRole(h.accountScopeOptions(base), h.socketAdmission(h.accountScopeOptions(base)),
            {account_id: TARGET, binding: 'queue_live.changed.' + QUEUE}), 'target');
    });
    await test('home ACK requires exact request identity, action, success and native binding sets', () => {
        for (const change of [r => r.status = 'error', r => r.action = 'event',
            r => r.data.subscribed = [], r => r.data.subscribed = ['queue_live.changed.' + QUEUE],
            r => r.data.subscriptions.push('queue_live.changed.' + QUEUE), r => r.data.extra = 'sentinel']) {
            const f = homeProof(); change(f.reply);
            assert.throws(() => h.observeHomeReply(f.admission, f.sent, f.reply, 2), /exact_home/);
            assert.equal(f.admission.subscribeAck, null);
        }
        const f = homeProof();
        assert.equal(h.observeHomeReply(f.admission, undefined, f.reply, 2), false);
        assert.equal(h.observeHomeReply(f.admission, {...f.sent, role: 'target'}, f.reply, 2), false);
        assert.equal(h.observeHomeReply(f.admission, f.sent, {...f.reply, request_id: 'lifecycle-stale'}, 2), false);
        assert.throws(() => h.observeHomeReply(f.admission, {...f.sent}, f.reply, 2), /exact_home/);
        assert.throws(() => h.observeHomeReply(f.admission, f.sent, f.reply, 1), /exact_home/);
        assert.equal(h.observeHomeReply(f.admission, f.sent, f.reply, 2), true);
        assert.throws(() => h.observeHomeReply(f.admission, f.sent, f.reply, 3), /exact_home/);
    });
    await test('home cleanup requires ACK then navigation, refuses replacement subscriptions', () => {
        const f = homeProof();
        assert.throws(() => h.beginHomeDisposal(f.admission, 3), /home_subscribe_ack/);
        assert.throws(() => h.recordHomeCommand(f.admission, {...f.sent}), /unexpected_home_subscribe/);
        assert.throws(() => h.recordHomeCommand(f.admission, {...f.sent, action: 'unsubscribe', order: 4}), /unexpected_home_unsubscribe/);
        h.observeHomeReply(f.admission, f.sent, f.reply, 2); h.beginHomeDisposal(f.admission, 3);
        assert.throws(() => h.recordHomeCommand(f.admission, {...f.sent, order: 4}), /unexpected_home_subscribe/);
        assert.throws(() => h.closeHomeAdmission(f.admission, true), /home_disposal/);
        const stop = {...f.sent, action: 'unsubscribe', order: 4, requestId: 'lifecycle-stop'};
        h.recordHomeCommand(f.admission, stop);
        for (const data of [{unsubscribed: [], subscriptions: []}, {unsubscribed: [f.binding], subscriptions: [f.binding]},
            {unsubscribed: ['queue_live.changed.' + QUEUE], subscriptions: []}, {unsubscribed: [f.binding], subscriptions: [], extra: true}]) {
            assert.throws(() => h.observeHomeReply(f.admission, stop, {...f.reply, request_id: stop.requestId, data}, 5), /exact_home/);
        }
        assert.throws(() => h.closeHomeAdmission(f.admission, true), /home_disposal/);
    });
    await test('closed home window cannot reopen or lend a stale ACK to target scope', () => {
        const f = completeHome();
        assert.throws(() => h.closeHomeAdmission(f.admission, false), /home_disposal/);
        h.closeHomeAdmission(f.admission, true); assert.equal(f.admission.stage, 'target');
        assert.throws(() => h.socketScopeRole(scope, f.admission, {account_id: LOGIN, binding: f.binding}), /unexpected_target/);
        assert.throws(() => h.recordHomeCommand(f.admission, {...f.sent, order: 6}), /unexpected_home/);
        assert.throws(() => h.observeHomeReply(f.admission, f.stop, f.stopReply, 6), /exact_home/);
        assert.throws(() => h.beginHomeDisposal(f.admission, 6), /home_subscribe_ack/);
        assert.equal(h.socketScopeRole(scope, f.admission, {account_id: TARGET, binding: 'queue_live.changed.' + QUEUE}), 'target');
        // Same client binding in a different tenant is still a target-owned
        // request, not permission to reuse an old home request record.
        assert.equal(h.socketScopeRole(scope, f.admission, {account_id: TARGET, binding: f.binding}), 'target');
        assert.equal(h.observeHomeReply(f.admission, {...f.sent, role: 'target', account: TARGET}, f.reply, 7), false);
    });
    await test('home overview must be valid and acknowledged in the real login/controller scope', () => {
        const good = homeBrowser(), before = JSON.stringify(good.monster);
        assert.equal(good.evaluate(h.homeOverviewInBrowser, scope), true);
        assert.equal(JSON.stringify(good.monster), before);
        const changes = [b => b.monster.apps.auth.currentAccount.id = TARGET,
            b => b.monster.apps.auth.originalAccount.id = TARGET, b => b.view.masquerading = true,
            b => b.monster.apps.acdc.accountId = TARGET,
            b => b.monster.apps.acdc.appFlags.acdc.currentTab = 'queues',
            b => b.monster.apps.acdc.appFlags.acdc.liveDashboardController.accountId = TARGET,
            b => b.monster.apps.acdc.appFlags.acdc.liveDashboardController.queueId = HOME_QUEUE,
            b => b.monster.apps.acdc.appFlags.acdc.liveDashboardController.inFlight = true,
            b => b.monster.apps.acdc.appFlags.acdc.liveDashboardController.supported = false,
            b => b.monster.apps.acdc.appFlags.acdc.liveDashboardSnapshot.accountId = TARGET,
            b => b.monster.apps.acdc.appFlags.acdc.liveDashboardSnapshot.results.live.queues = [{id: QUEUE}],
            b => b.monster.apps.acdc.appFlags.acdc.liveDashboardSnapshot.results.live.queues.push({id: QUEUE}),
            b => b.monster.apps.acdc.liveSnapshotValid = () => false,
            b => b.monster.apps.acdc.liveTransportState = () => 'pending'];
        for (const change of changes) { const b = homeBrowser(); change(b); assert.equal(b.evaluate(h.homeOverviewInBrowser, scope), false); }
    });
    await test('listed target uses normal topbar and registers real readback before exact-row click', async () => {
        const f = pageDouble(); assert.equal(await h.switchTargetAccount(f.page, api, scope, f.checkpoint), true);
        assert.deepEqual(f.events, ['picker_ready', 'open', 'input_visible', 'initial_list_ready', 'watch_target_get', 'click_target', 'assert_scope']);
        const disabled = pageDouble({pickerDisabled: true});
        await assert.rejects(() => h.switchTargetAccount(disabled.page, api, scope, disabled.checkpoint), /fixture_picker_not_ready/);
        assert(!disabled.events.includes('open'));
    });
    await test('unlisted target uses native keystrokes then Enter after initial list readiness', async () => {
        const f = pageDouble({initialRows: 0}); await h.switchTargetAccount(f.page, api, scope, f.checkpoint);
        assert.deepEqual(f.events, ['picker_ready', 'open', 'input_visible', 'initial_list_ready', 'type_id', 'search_enter',
            'watch_target_get', 'click_target', 'assert_scope']);
    });
    await test('duplicate target rows failed GET or unchanged auth scope cannot pass selection', async () => {
        const duplicate = pageDouble({initialRows: 2});
        await assert.rejects(() => h.switchTargetAccount(duplicate.page, api, scope, duplicate.checkpoint), /target_row_not_unique/);
        assert(!duplicate.events.includes('click_target'));
        const denied = pageDouble({response: response({status: 403})});
        await assert.rejects(() => h.switchTargetAccount(denied.page, api, scope, denied.checkpoint), /readback_failed/);
        const unchanged = pageDouble({failedSwitch: true});
        await assert.rejects(() => h.switchTargetAccount(unchanged.page, api, scope, unchanged.checkpoint), /fixture_scope_not_reached/);
    });
    await test('normal home control restores original and rejects any remaining live controller', async () => {
        const f = pageDouble(); await h.switchTargetAccount(f.page, api, scope, f.checkpoint); f.events.length = 0;
        assert.equal(await h.restoreHomeAccount(f.page, scope, f.checkpoint), true);
        assert.deepEqual(f.events, ['picker_ready', 'open', 'click_home', 'assert_scope', 'assert_scope']);
        const wrong = pageDouble({homeController: true});
        await assert.rejects(() => h.restoreHomeAccount(wrong.page, scope, wrong.checkpoint), /fixture_scope_not_reached/);
        const wrongTab = pageDouble({homeTab: 'dashboard'});
        await assert.rejects(() => h.restoreHomeAccount(wrongTab.page, scope, wrongTab.checkpoint), /fixture_scope_not_reached/);
        const disabled = pageDouble({pickerDisabled: true});
        await assert.rejects(() => h.restoreHomeAccount(disabled.page, scope, disabled.checkpoint), /fixture_picker_not_ready/);
        assert(!disabled.events.includes('open'));
    });
    await test('main wiring preserves write barriers served pins and disposal-before-home ordering', () => {
        assert(source.includes("if (scope.switching) initialUrl.hash = 'apps/acdc'"));
        assert(!/apps\/apploader|waiting_neutral|framework_before|requirejs|postal/.test(source));
        assert(source.indexOf('await page.waitForFunction(homeOverviewInBrowser, scope') < source.indexOf('beginHomeDisposal(admission, timeline('));
        assert(source.indexOf('closeHomeAdmission(admission, await page.evaluate(queuesDisposedInBrowser))') < source.indexOf('result.account_switch.target_verified = await switchTargetAccount'));
        assert(source.indexOf("checkpoint('clicking_switched_dashboard_tab')") < source.indexOf("checkpoint('waiting_overview_grid')"));
        assert(source.includes("if (!scope.switching && !summaryMode) {\n                checkpoint('clicking_dashboard_tab')"));
        assert(source.includes("...(scope.switching ? [['KAZOO_TEST_EXPECT_ACCOUNT_BROWSER_SHA256', ACCOUNT_BROWSER_ASSET]] : [])"));
        assert(source.includes('(!scope.switching || result.production_assets[ACCOUNT_BROWSER_ASSET])'));
        assert(source.includes('auth.data?.account_id === loginAccount'));
        assert(source.includes("method === 'PUT' && result.counts.auth === 0"));
        assert(source.includes('const role = socketScopeRole(scope, admission, j.data)'));
        assert(source.includes('!seenRequestIds.has(j.request_id) && seenRequestIds.size < 200'));
        assert(source.includes("sent.role === 'target' && sent.binding === 'queue_live.changed.' + queue"));
        assert(source.includes("check(result.counts.auth === 1, 'exactly_one_normal_auth_required')"));
        assert(source.indexOf('result.account_switch.home_restored = await restoreHomeAccount') >
            source.indexOf("'correlated_selected_disposal_unsubscribe_ack_required'"));
        assert(source.includes("await page.locator('.acdc-tab[data-tab=\"queues\"]').click()"));
        assert(!/triggerImpersonateUser|auth\.impersonate|\.currentAccount\s*=/.test(source));
        assert(app.includes('self.renderSection(self.appFlags.acdc.currentTab);'));
        assert(app.includes('self.appFlags.acdc.currentTab = tab;'));
        assert(app.includes("if (tab === 'queues') {"));
        assert.equal(fs.readFileSync(sourceFile, 'utf8'), source); assert.equal(fs.readFileSync(appFile, 'utf8'), app);
    });
    console.log(JSON.stringify({result: 'PASS', groups, harness_sha256: hash(source), app_sha256: hash(app),
        real_browser: false, real_http: false, real_websocket: false, credentials_read: false, fixture_writes: false}));
})().catch(() => { console.error('FAIL deployed account-switch offline boundary; no private diagnostics'); process.exitCode = 1; });
