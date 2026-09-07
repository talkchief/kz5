#!/usr/bin/env node
'use strict';
// Pure helpers and controlled DOM/clock only. No browser, network, credential,
// call, provider, process spawn or service action is executed here.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path');
const vm = require('node:vm'), crypto = require('node:crypto'), {createRequire} = require('node:module');
const file = path.join(__dirname, 'test-fixtures/monster-live-call-observer.cjs');
const files = [__filename, file, path.join(__dirname, 'test-monster-live-deployed.cjs'),
    path.join(__dirname, 'test-fixtures/queue-live-observer.cjs'), path.join(__dirname, 'api-docs-queue-live.cjs')];
const bytes = files.map(f => fs.readFileSync(f)), source = bytes[1].toString(), load = createRequire(file);
const A = 'a'.repeat(32), Q = 'b'.repeat(32), L = 'c'.repeat(32), H = 'd'.repeat(32);
const CALL = '1-123@127.0.0.52', PRIVATE = 'PRIVATE_NAME_SENTINEL', EPOCH = 1788739200000;
const copy = x => JSON.parse(JSON.stringify(x));
function dto(state = 'gone') {
    const rows = state === 'gone' ? [] : [{call_id: CALL, queue_id: Q, status: state,
        entered_at: EPOCH / 1000 - 30, handled_at: state === 'handled' ? EPOCH / 1000 - 1 : null}];
    const waiting = state === 'waiting' ? 1 : 0, handled = state === 'handled' ? 1 : 0;
    return {status: 'success', data: {version: 1, account_id: A, generated_at: EPOCH / 1000,
        window: {from: EPOCH / 1000 - 3600, to: EPOCH / 1000, seconds: 3600},
        queues: [{id: Q, name: PRIVATE, strategy: 'round_robin', metrics_available: true,
            metrics: {current_waiting: waiting, current_handled: handled, max_current_wait_seconds: waiting ? 30 : null,
                records_entered: rows.length, waiting_in_cohort: waiting, handled_in_cohort: handled,
                processed_in_cohort: 0, abandoned_in_cohort: 0, average_answered_wait_seconds: handled ? 29 : null,
                average_processed_talk_seconds: null}}],
        calls: {available: true, complete: true, truncated: false, limit: 200, observed_count: rows.length,
            order: 'queue_id_entered_call_id', rows},
        agents: {limit: 200, roster_complete: true, truncated: false, runtime_complete: true,
            endpoint_reachability_verified: false, observation_started: EPOCH / 1000,
            observation_finished: EPOCH / 1000, rows: []},
        pagination: {page_size: 1, has_more: false, next_start_queue_id: null},
        source: {coverage: 'observed_replicas', all_known_sources_responded: true, consistent: true,
            atomic_snapshot: false, status: 'available', reason: 'consensus',
            observation_started_at: EPOCH / 1000, observation_finished_at: EPOCH / 1000},
        capabilities: {live_call_details: true, agent_runtime: true, websocket_updates: true, historical_reporting: false}}};
}
function event() {
    const key = 'acdc.dashboard.changed.' + A + '.' + Q;
    return {action: 'event', name: 'changed', subscribed_key: 'queue_live.changed.' + Q,
        subscription_key: key, routing_key: key, data: {version: 1, account_id: A, queue_id: Q}};
}
function page(body) {
    const d = body.data;
    return {valid: true, generation: 7, receivedAt: EPOCH + 100,
        dto: JSON.stringify(d), waiting: String(d.queues[0].metrics.current_waiting),
        handled: String(d.queues[0].metrics.current_handled), empty: !d.calls.rows.length,
        rows: d.calls.rows.map(r => ({callId: r.call_id, state: r.status}))};
}
function fixture() {
    let time = 0, timerId = 0, order = 0, currentPage, dirty = false, reads = 0, hangRead = false;
    const timers = new Map(), mod = {exports: {}};
    vm.runInNewContext(source, {module: mod, require(name) {
        return name === 'node:perf_hooks' ? {performance: {now: () => time}} : load(name);
    }, setTimeout(fn, ms) { const id = ++timerId; timers.set(id, {fn, at: time + ms}); return id; },
    clearTimeout(id) { timers.delete(id); }, Buffer}, {filename: file, timeout: 1000});
    const options = {accountId: A, queueId: Q, readPage: async () => {
        reads++; return hangRead ? new Promise(() => {}) : currentPage;
    }, getOrder: () => order, checkClean: () => { assert(!dirty, 'controlled_guard_failure'); }};
    const observer = mod.exports.createBrowserCallObserver(options);
    const flush = async () => { for (let i = 0; i < 20; i++) await Promise.resolve(); };
    return {observer, exported: mod.exports, options, timers, reads: () => reads,
        mutatePage(fn) { fn(currentPage); }, dirty() { dirty = true; }, hang() { hangRead = true; },
        hint(change = () => {}) { const j = event(); change(j); observer.recordEvent(j, ++order); },
        sample(body = dto(), change = () => {}, render = true) {
            const input = {body, requestOrder: ++order, responseOrder: ++order, requestAt: EPOCH, noStore: true};
            change(input); observer.recordResponse(input); if (render) currentPage = page(body); return input;
        },
        async ready() { this.sample(); await observer.ready(); },
        async timeout(p) { const expected = assert.rejects(p, /browser_phase_timeout/); await this.advance(10001); await expected; },
        async advance(ms) {
            const end = time + ms; let steps = 0; await flush();
            for (;;) {
                const next = [...timers].filter(([, t]) => t.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
                if (!next) break;
                assert(++steps < 1000, 'unbounded fixture timer'); time = next[1].at; timers.delete(next[0]); next[1].fn(); await flush();
            }
            time = end; await flush();
        }};
}
let groups = 0;
async function test(name, work) { await work(); groups++; console.log('PASS ' + name); }
(async () => {
    await test('embedded interface rejects malformed input before any browser or credential work', async () => {
        const {runWithNaturalCall} = require('./test-monster-live-deployed.cjs');
        const good = {accountId: A, queueId: Q, loginAccountId: L, loginQueueId: H, runCall: () => assert.fail()};
        const env = JSON.stringify(process.env), argv = JSON.stringify(process.argv);
        for (const input of [null, {}, {...good, extra: true}, {...good, queueId: 'unsafe'}, {...good, runCall: 'module'},
            {...good, loginAccountId: A}, {...good, loginQueueId: undefined}]) {
            assert.deepEqual(await runWithNaturalCall(input), {status: 'FAIL', evidence: null, checks: 0, failure: 'invalid_natural_call_options'});
        }
        assert.equal(JSON.stringify(process.env), env); assert.equal(JSON.stringify(process.argv), argv);
    });
    await test('actual shared schema gates reject malformed, foreign, cached and duplicate responses', () => {
        for (const change of [x => x.body.data.account_id = L, x => x.body.data.calls.observed_count = 9,
            x => x.noStore = false, x => x.body.data.capabilities.websocket_updates = false,
            x => x.responseOrder = x.requestOrder, x => x.body.data.calls.rows = [{call_id: PRIVATE}]]) {
            const f = fixture(); assert.throws(() => f.sample(dto(), change));
        }
        const f = fixture(), input = f.sample(); assert.throws(() => f.observer.recordResponse(input));
    });
    await test('empty complete rendered detail is mandatory before the call', async () => {
        const f = fixture(); f.sample(dto('waiting'));
        const refused = assert.rejects(f.observer.ready(), /browser_empty_detail_timeout/); await f.advance(10001); await refused;
        const g = fixture(); await g.ready(); assert.equal(g.observer.evidence().ready, true);
        await assert.rejects(g.observer.ready(), /already_started/);
        assert.throws(g.observer.finish, /phases_incomplete/);
        const late = fixture(), ready = late.observer.ready();
        await late.advance(50); late.sample(); await late.advance(50); await ready;
        assert.equal(late.observer.evidence().ready, true);
    });
    await test('fresh native hints and later exact GET DOM states prove the three ordered phases', async () => {
        const f = fixture(); await f.ready();
        for (const phase of ['waiting', 'handled', 'gone']) {
            f.hint(); f.sample(dto(phase)); const proof = await f.observer.waitForPhase(CALL, phase, 10000);
            assert.equal(proof.phase, phase); assert(proof.hint_order > proof.boundary_order);
            assert(proof.request_order > proof.hint_order); assert.equal(proof.rendered_dto_match, true);
        }
        const proof = f.observer.finish(), text = JSON.stringify(proof);
        assert.equal(proof.phases.length, 3); assert.equal(proof.event_causal_correlation_verified, false);
        assert.equal(proof.broker_barrier_verified, false); assert(!text.includes(PRIVATE)); assert(!text.includes(CALL));
    });
    await test('no hint, pre-boundary hint or GET begun before hint cannot prove waiting', async () => {
        for (const variant of [0, 1, 2]) {
            const f = fixture(); if (variant === 1) f.hint(); await f.ready();
            f.sample(dto('waiting')); if (variant === 2) f.hint();
            await f.timeout(f.observer.waitForPhase(CALL, 'waiting', 10000));
        }
    });
    await test('waiting does not lend its hint to handled; terminal absence needs both prior phases', async () => {
        const f = fixture(); await f.ready();
        await assert.rejects(f.observer.waitForPhase(CALL, 'gone', 10000), /invalid_browser_phase/);
        f.hint(); f.sample(dto('waiting')); await f.observer.waitForPhase(CALL, 'waiting', 10000);
        f.sample(dto('handled')); await f.timeout(f.observer.waitForPhase(CALL, 'handled', 10000));
    });
    await test('DOM counters, row status, identity, stale view and response mismatch all fail', async () => {
        for (const change of [p => p.waiting = '0', p => p.handled = '1', p => p.rows[0].state = 'handled',
            p => p.rows[0].callId = PRIVATE, p => p.generation++, p => p.valid = false,
            p => p.receivedAt = EPOCH - 1, p => p.dto += ' ', p => p.empty = true]) {
            const f = fixture(); await f.ready(); f.hint(); f.sample(dto('waiting')); f.mutatePage(change);
            await f.timeout(f.observer.waitForPhase(CALL, 'waiting', 10000));
        }
    });
    await test('latest response replaces old proof; an old rendered waiting DTO cannot pass', async () => {
        const f = fixture(); await f.ready(); f.hint(); f.sample(dto('waiting'));
        f.sample(dto('handled'), () => {}, false);
        await f.timeout(f.observer.waitForPhase(CALL, 'waiting', 10000));
    });
    await test('exact native envelopes reject wrong scope and sentinel payload fields', () => {
        for (const change of [j => j.data.account_id = L, j => j.data.queue_id = H,
            j => j.routing_key += '.other', j => j.subscription_key += '.other',
            j => j.subscribed_key = 'queue_live.changed.' + H, j => j.data.extra = PRIVATE,
            j => j.extra = PRIVATE, j => j.action = 'reply', j => j.name = 'other']) {
            const f = fixture(); assert.throws(() => f.hint(change));
        }
    });
    await test('phase timeout, hung page read, dirty guard and concurrent or foreign caller fail closed', async () => {
        const f = fixture(); await f.ready(); f.hang(); await f.timeout(f.observer.waitForPhase(CALL, 'waiting', 10000));
        assert.equal(f.timers.size, 0);
        const g = fixture(); await g.ready(); g.dirty(); await assert.rejects(g.observer.waitForPhase(CALL, 'waiting', 10000), /guard_failure/);
        const p = fixture(); await p.ready();
        for (const [caller, phase, timeout] of [[PRIVATE, 'waiting', 10000], [CALL, 'waiting', 9999], [CALL, 'handled', 10000]]) {
            await assert.rejects(p.observer.waitForPhase(caller, phase, timeout), /invalid_browser_phase/);
        }
        const pending = p.observer.waitForPhase(CALL, 'waiting', 10000);
        await assert.rejects(p.observer.waitForPhase(CALL, 'waiting', 10000), /invalid_browser_phase/); await p.timeout(pending);
    });
    await test('read-only DOM capture checks current controller, transport and mounted row classes', () => {
        const {readRenderedCall} = fixture().exported, body = dto('waiting'), display = page(body);
        const node = extra => ({isConnected: true, nodeType: 1, parentElement: null, getClientRects: () => [{}], ...extra});
        const status = node({classList: {contains: name => name === 'acdc-live-status-waiting'}});
        const cells = [node({}), node({textContent: CALL}), node({}), node({})];
        const row = node({querySelector: () => status, querySelectorAll: () => cells});
        const waiting = node({textContent: '1'}), handled = node({textContent: '0'}), ancestor = node({});
        let stale = false, refreshError = false;
        const root = node({parentElement: ancestor, getAttribute: () => 'false', querySelectorAll: () => [row], querySelector(selector) {
            return selector === '.acdc-live-waiting strong' ? waiting
                : selector === '.acdc-live-handling strong' ? handled
                : selector === '.acdc-live-freshness.is-stale' ? stale
                : selector === '.acdc-live-refresh-error' ? refreshError : null;
        }});
        const flags = {currentTab: 'dashboard', liveDashboardController: {accountId: A, queueId: Q, generation: 7, view: [root]},
            liveDashboardSnapshot: {accountId: A, queueId: Q, receivedAt: display.receivedAt, results: {live: body.data}}};
        const app = {accountId: A, appFlags: {acdc: flags}, liveTransportState: () => 'acknowledged', liveSnapshotValid: () => true};
        const auth = {currentAccount: {id: A}};
        let activeApp = 'acdc';
        const context = {window: {require: () => ({apps: {acdc: app, auth, getActiveApp: () => activeApp}}),
            getComputedStyle: n => ({display: 'block', visibility: 'visible', opacity: '1', ...n.style})},
        document: {querySelector: () => root}, input: {accountId: A, queueId: Q}};
        const run = () => vm.runInNewContext('(' + readRenderedCall.toString() + ')(input)', context, {timeout: 1000});
        assert.deepEqual(copy(run()), display);
        stale = true; assert.equal(run().valid, false); stale = false;
        refreshError = true; assert.equal(run().valid, false); refreshError = false;
        for (const target of [root, ancestor, row, waiting, handled, status, cells[1]]) {
            target.style = {display: 'none'}; assert.equal(run().valid, false);
            target.style = {visibility: 'hidden'}; assert.equal(run().valid, false); delete target.style;
        }
        root.getClientRects = () => []; assert.equal(run().valid, false); root.getClientRects = () => [{}];
        activeApp = 'myaccount'; assert.equal(run().valid, false); activeApp = 'acdc';
        flags.liveDashboardController.view = [ancestor]; assert.equal(run().valid, false); flags.liveDashboardController.view = [root];
        app.accountId = L; assert.equal(run().valid, false); app.accountId = A;
        auth.currentAccount.id = L; assert.equal(run().valid, false); auth.currentAccount.id = A;
        flags.liveDashboardController.accountId = L; assert.equal(run().valid, false);
    });
    await test('main wires the owned callback after readiness and phases before disposal with helper pins', () => {
        const main = bytes[2].toString();
        assert(main.indexOf('await callObserver.ready()') < main.indexOf('await natural.runCall('));
        assert(main.indexOf('callObserver.finish()') < main.indexOf("phase = 'cleanup'"));
        assert(main.includes('Object.freeze({waitForPhase: callObserver.waitForPhase})'));
        assert(main.includes('test-fixtures/monster-live-call-observer.cjs'));
        assert(main.includes("'test-fixtures/queue-live-observer.cjs', 'api-docs-queue-live.cjs'"));
        assert(main.includes("KAZOO_TEST_REQUIRE_WEBSOCKET: 'true'"));
        assert(main.includes('natural ? 150000 : 105000'));
        assert(!/process\.(?:env|argv)\s*=|process\.env\.[A-Za-z_]+\s*=/.test(main));
        for (let i = 0; i < files.length; i++) assert(fs.readFileSync(files[i]).equals(bytes[i]));
    });
    console.log(JSON.stringify({status: 'PASS', groups, source_sha256: crypto.createHash('sha256').update(bytes[1]).digest('hex'),
        real_browser: false, real_network: false, real_call: false, credentials_read: false}));
})().catch(() => { console.error('FAIL browser-call observer offline fixture; no private diagnostics'); process.exitCode = 1; });
