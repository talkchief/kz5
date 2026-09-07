#!/usr/bin/env node
'use strict';
// Controlled clock/route/page fixtures only; no browser, requests, credentials,
// commands, real waits, services, persistent state or live API writes.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path');
const vm = require('node:vm'), crypto = require('node:crypto'), {createRequire} = require('node:module');
const file = path.join(__dirname, 'test-fixtures/monster-live-http-stall.cjs');
const files = [__filename, file, path.join(__dirname, 'test-monster-live-deployed.cjs'),
    path.join(__dirname, 'test-fixtures/queue-live-observer.cjs'), path.join(__dirname, 'api-docs-queue-live.cjs')];
const bytes = files.map(f => fs.readFileSync(f)), source = bytes[1].toString(), load = createRequire(file);
const helper = require(file), A = 'a'.repeat(32), Q = 'b'.repeat(32), OTHER = 'c'.repeat(32);
const ORIGIN = 'https://fixture.invalid', URL = ORIGIN + '/v2/accounts/' + A + '/queues/' + Q + '/live';
const EPOCH = 1788739200000, PRIVATE = 'PRIVATE_SENTINEL';
const copy = value => JSON.parse(JSON.stringify(value));
let groups = 0;
async function test(name, run) { await run(); groups++; console.log('PASS ' + name); }
function dto(handled = false) {
    return {status: 'success', data: {version: 1, account_id: A, generated_at: EPOCH / 1000,
        window: {from: EPOCH / 1000 - 3600, to: EPOCH / 1000, seconds: 3600},
        queues: [{id: Q, name: PRIVATE, strategy: 'round_robin', metrics_available: true,
            metrics: {current_waiting: handled ? 0 : 1, current_handled: handled ? 1 : 0,
                max_current_wait_seconds: handled ? null : 30, records_entered: 1,
                waiting_in_cohort: handled ? 0 : 1, handled_in_cohort: handled ? 1 : 0,
                processed_in_cohort: 0, abandoned_in_cohort: 0, average_answered_wait_seconds: handled ? 29 : null,
                average_processed_talk_seconds: null}}],
        calls: {available: true, complete: true, truncated: false, limit: 200, observed_count: 1,
            order: 'queue_id_entered_call_id', rows: [{queue_id: Q, call_id: PRIVATE,
                entered_at: EPOCH / 1000 - 30, handled_at: handled ? EPOCH / 1000 - 1 : null,
                status: handled ? 'handled' : 'waiting'}]},
        agents: {limit: 200, roster_complete: true, truncated: false, runtime_complete: true,
            endpoint_reachability_verified: false, observation_started: EPOCH / 1000,
            observation_finished: EPOCH / 1000, rows: []},
        pagination: {page_size: 1, has_more: false, next_start_queue_id: null},
        source: {coverage: 'observed_replicas', all_known_sources_responded: true, consistent: true,
            atomic_snapshot: false, status: 'available', reason: 'consensus',
            observation_started_at: EPOCH / 1000, observation_finished_at: EPOCH / 1000},
        capabilities: {live_call_details: true, agent_runtime: true, websocket_updates: true, historical_reporting: false}}};
}
function view(body = dto()) {
    return {scope: true, account: true, disposed: false, dto: JSON.stringify(body.data), receivedAt: EPOCH,
        generation: 1, inFlight: false, quiet: true, acknowledged: true, busy: 'false',
        counters: [String(body.data.queues[0].metrics.current_waiting), String(body.data.queues[0].metrics.current_handled), '0'],
        countersVisible: true, refreshEnabled: true, error: false, stale: false};
}
function request(url = URL, method = 'GET', errorText = 'net::ERR_ABORTED') {
    return {url: () => url, method: () => method, failure: () => ({errorText})};
}
function fixture({invalidResponse = false, wrongRecovery = false} = {}) {
    let time = 0, routeHandler, current = view(), probe, clicks = 0, active, autoAt = null, fault;
    const routes = [], tasks = [], mod = {exports: {}}, fetches = [], fulfills = [];
    vm.runInNewContext(source, {module: mod, require(name) {
        return name === 'node:perf_hooks' ? {performance: {now: () => time}} : load(name);
    }, Date: {now: () => EPOCH + time}, URL: global.URL, Buffer}, {filename: file, timeout: 1000});
    function begin() {
        const r = request(); active = {request: r, start: time, aborted: false};
        current.inFlight = true; current.quiet = false; current.busy = 'true'; current.refreshEnabled = false;
        const actual = dto(clicks >= 2); if (invalidResponse) actual.data.account_id = OTHER;
        const response = {status: () => 200, headers: () => ({'cache-control': 'no-store'}),
            body: async () => Buffer.from(JSON.stringify(actual)), request: () => r, dispose: async () => {}};
        const route = {request: () => r,
            async fetch(options) { fetches.push(options); return response; },
            async fulfill(options) { assert.equal(options.response, response); assert.deepEqual(Object.keys(options), ['response']);
                fulfills.push(options); throw Error('controlled_browser_aborted_request'); },
            async abort() {}, async fallback() {
                const fresh = dto(true); const real = {...response, body: async () => Buffer.from(JSON.stringify(fresh))};
                await probe.response(real); current = view(wrongRecovery ? dto() : fresh); current.receivedAt = EPOCH + time;
            }};
        const task = Promise.resolve(routeHandler(route)).catch(error => { fault = error; }); tasks.push(task);
        return task;
    }
    const page = {async route(selector, handler) { routes.push(selector); routeHandler = handler; }, async unroute() {},
        async evaluate(fn, scope) { assert.equal(fn.name, 'readStallView'); assert.equal(scope.accountId, A); assert.equal(scope.queueId, Q); return copy(current); },
        locator(selector) { assert.equal(selector, '.acdc-refresh'); return {async click() { clicks++; begin(); }}; },
        async waitForTimeout(ms) {
            time += ms;
            if (autoAt !== null && time >= autoAt) { autoAt = null; begin(); }
            if (active && !active.aborted && !current.disposed && current.inFlight && time - active.start >= 10000) {
                active.aborted = true; assert(probe.expectedFailure(active.request));
                Object.assign(current, {inFlight: false, quiet: true, busy: 'false', refreshEnabled: true, error: true, stale: true});
            }
            if (fault) throw fault;
        }};
    probe = mod.exports.createHttpStallProbe({page, apiOrigin: ORIGIN, accountId: A, queueId: Q, checkClean() { if (fault) throw fault; }});
    return {probe, fetches, fulfills, routes, get current() { return current; }, get time() { return time; },
        scheduleReconciliation() { autoAt = time + 15000; },
        dispose() { Object.assign(current, {scope: false, disposed: true, inFlight: false});
            active.aborted = true; assert(probe.expectedFailure(active.request)); },
        async settle() { await Promise.all(tasks); if (fault) throw fault; }};
}
async function main() {
    try {
        await test('mode is opt-in and incompatible with calls, reconnect, absent native capability or malformed flags', () => {
            assert.equal(helper.httpStallOptions({}, null, false), false);
            assert.equal(helper.httpStallOptions({KAZOO_TEST_HTTP_STALL: 'false'}, null, false), false);
            const enabled = {KAZOO_TEST_HTTP_STALL: 'true', KAZOO_TEST_REQUIRE_WEBSOCKET: 'true'};
            assert.equal(helper.httpStallOptions(enabled, null, false), true);
            for (const [env, natural, reconnect] of [[enabled, {}, false], [enabled, null, true],
                [{KAZOO_TEST_HTTP_STALL: 'true'}, null, false], [{KAZOO_TEST_HTTP_STALL: 'yes'}, null, false]]) {
                assert.throws(() => helper.httpStallOptions(env, natural, reconnect), helper.HttpStallError);
            }
        });
        await test('only the exact selected queue GET without query can be held', () => {
            assert(helper.selectedGet(request(), ORIGIN, A, Q));
            for (const r of [request(URL, 'PUT'), request(URL + '?_=1'), request(URL.replace(Q, OTHER)),
                request(URL.replace(A, OTHER)), request(URL.replace(ORIGIN, 'https://other.invalid')),
                request(ORIGIN + '/v2/accounts/' + A + '/queues/live')]) assert(!helper.selectedGet(r, ORIGIN, A, Q));
        });
        await test('rendered counters and exact retained DTO cannot silently zero or mix responses', () => {
            const d = dto(), v = view(d); assert(helper.renderedMatches(v, d.data));
            for (const wrong of [{...v, scope: false}, {...v, countersVisible: false}, {...v, counters: ['0', '0', '0']},
                {...v, dto: JSON.stringify(dto(true).data)}]) assert(!helper.renderedMatches(wrong, d.data));
        });
        await test('owned cancellation excludes early, unrelated, duplicate and non-abort failures', () => {
            const r = request(), owned = {request: r, started: 0, cancelled: false, disposing: false};
            assert(!helper.expectedCancellation(owned, r, 9499)); assert(helper.expectedCancellation(owned, r, 9500));
            assert(!helper.expectedCancellation(owned, request(), 10000));
            assert(!helper.expectedCancellation({...owned, cancelled: true}, r, 10000));
            const failed = request(URL, 'GET', 'net::ERR_CONNECTION_RESET');
            assert(!helper.expectedCancellation({...owned, request: failed}, failed, 10000));
            assert(helper.expectedCancellation({...owned, disposing: true}, r, 100));
        });
        await test('complete controlled 10s stall, nonzero retained snapshot, fresh recovery and disposal release', async () => {
            const t = fixture(); await t.probe.install(); await t.probe.deadlineRecovery();
            assert.equal(t.current.counters[1], '1'); assert(t.time >= 10000);
            t.scheduleReconciliation(); await t.probe.prepareDisposal(); t.dispose(); await t.probe.finishDisposal();
            await t.probe.close(); await t.settle(); const e = t.probe.evidence();
            assert.equal(e.held_requests, 2); assert.equal(e.validated_real_responses, 2);
            assert(e.watchdog_stale_error && e.retained_snapshot_verified && e.refresh_usable && e.manual_refresh_recovered && e.disposal_unchanged);
            assert.equal(e.late_javascript_callback_executed, false); assert.equal(e.late_callback_ignore_verified, false);
            assert(e.attempts.every(a => a.transport_cancelled && !a.fulfill_call_resolved && !a.delivered_late_to_javascript));
            assert.equal(t.fetches.length, 2); assert.equal(t.fulfills.length, 2);
            assert(t.fetches.every(f => f.maxRedirects === 0 && f.maxRetries === 0 && f.timeout === 5000));
            const safe = JSON.stringify(e); assert(!safe.includes(PRIVATE) && !safe.includes(A) && !safe.includes(Q));
        });
        await test('foreign real response is rejected before any held-response acceptance', async () => {
            const t = fixture({invalidResponse: true}); await t.probe.install();
            await assert.rejects(t.probe.deadlineRecovery(), /stall_real_response_schema/);
            assert.equal(t.probe.evidence().validated_real_responses, 0); assert.equal(t.fulfills.length, 0);
            await t.probe.close().catch(() => {});
        });
        await test('a new real response cannot recover a view that still shows the old DTO', async () => {
            const t = fixture({wrongRecovery: true}); await t.probe.install();
            await assert.rejects(t.probe.deadlineRecovery(), /stall_manual_refresh_not_recovered/);
            assert.equal(t.probe.evidence().manual_refresh_recovered, false); await t.probe.close();
        });
        await test('integration keeps pins, original write guards and exact owned abort exception', () => {
            const main = bytes[2].toString();
            assert(main.indexOf('const httpStallMode') < main.indexOf('const secret = credentials()'));
            assert(main.includes("...(httpStallMode ? ['test-fixtures/monster-live-http-stall.cjs'] : [])"));
            assert(main.includes('if (httpStall && httpStall.expectedFailure(r)) return;'));
            assert(main.includes('result.counts.blocked_http_writes++; return route.abort(\'blockedbyclient\');'));
            assert(main.indexOf('await httpStall.prepareDisposal()') < main.indexOf("phase = 'cleanup';"));
            assert(main.indexOf('await httpStall.finishDisposal()') > main.indexOf("'correlated_selected_disposal_unsubscribe_ack_required'"));
            assert(!source.includes('route.fulfill({status:'));
        });
        console.log(JSON.stringify({result: 'PASS', groups, browser: false, network: false, real_waits: false}));
    } finally { files.forEach((f, i) => { assert(bytes[i].equals(fs.readFileSync(f)), 'Source changed');
        console.log('INPUT ' + crypto.createHash('sha256').update(bytes[i]).digest('hex') + ' ' + f); }); }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
