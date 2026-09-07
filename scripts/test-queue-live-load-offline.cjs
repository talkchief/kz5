#!/usr/bin/env node
'use strict';
// Controlled clock, HTTP adapter and EventEmitter sockets; real validators.
// Does not open a listener, acquire the platform lock, or read a token file.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path');
const crypto = require('node:crypto'), cp = require('node:child_process');
const {EventEmitter} = require('node:events');
const h = require('./test-queue-live-load.cjs');
const {validateDetail} = require('./test-fixtures/queue-live-observer.cjs');
const A = 'a'.repeat(32), Q = 'b'.repeat(32), SECRET = 'OFFLINE_PRIVATE_TOKEN_SENTINEL', EPOCH = 1800000000000;
const files = ['test-queue-live-load.cjs', 'test-queue-live-load-offline.cjs', 'test-queue-live-isolation.cjs',
    'test-queue-live-wire.cjs', 'test-fixtures/queue-live-observer.cjs', 'api-docs-queue-live.cjs'];
const digest = () => Object.fromEntries(files.map(file => [file, crypto.createHash('sha256')
    .update(fs.readFileSync(path.join(__dirname, file))).digest('hex')]));
const before = digest(); let groups = 0;
const argv = () => ['--allow-load', '--account', A, '--queue', Q, '--api-url', 'http://127.0.0.1:8000/v2',
    '--ws-url', 'ws://127.0.0.1:5555/websocket', '--token-file', '/offline/never-read-token',
    '--ws-module', '/offline/ws.cjs', '--clients', '2', '--duration-seconds', '30'];
function dto(time) {
    const t = Math.floor(time / 1000);
    return {status: 'success', data: {version: 1, account_id: A, generated_at: t,
        window: {from: t - 3600, to: t, seconds: 3600},
        queues: [{id: Q, name: 'PRIVATE_QUEUE_NAME', strategy: 'round_robin', metrics_available: true,
            metrics: {current_waiting: 0, current_handled: 0, max_current_wait_seconds: null, records_entered: 0,
                waiting_in_cohort: 0, handled_in_cohort: 0, processed_in_cohort: 0, abandoned_in_cohort: 0,
                average_answered_wait_seconds: null, average_processed_talk_seconds: null}}],
        calls: {available: true, complete: true, truncated: false, limit: 200, observed_count: 0,
            order: 'queue_id_entered_call_id', rows: []},
        agents: {limit: 200, roster_complete: true, truncated: false, runtime_complete: true,
            endpoint_reachability_verified: false, observation_started: t, observation_finished: t, rows: []},
        pagination: {page_size: 1, has_more: false, next_start_queue_id: null},
        source: {coverage: 'observed_replicas', all_known_sources_responded: true, consistent: true, atomic_snapshot: false,
            status: 'available', reason: 'consensus', observation_started_at: t, observation_finished_at: t},
        capabilities: {live_call_details: true, agent_runtime: true, websocket_updates: true, historical_reporting: false}}};
}
function fixture(fault = {}) {
    let time = 0, timerId = 0, closed = false, held = true;
    const timers = new Map(), sockets = [], requests = [], frames = [], signals = new EventEmitter(), pendingHttp = new Set();
    const schedule = (fn, ms) => { timers.set(++timerId, {fn, at: time + ms}); return timerId; };
    class Socket extends EventEmitter {
        constructor(url, config) {
            super(); this.at = time; this.config = config; this.terminated = false; sockets.push(this);
            assert.equal(url, 'ws://127.0.0.1:5555/websocket');
            queueMicrotask(() => {
                if (fault.open === 'error') this.emit('error', Error(SECRET));
                else if (fault.open === 'close') this.emit('close');
                else if (fault.open !== 'stall') this.emit('open');
            });
        }
        send(raw, callback) {
            const j = JSON.parse(raw); frames.push({j, at: time});
            assert.equal(j.auth_token, SECRET); assert.equal(j.data.account_id, A);
            assert.equal(j.data.binding, 'queue_live.changed.' + Q);
            assert(['subscribe', 'unsubscribe'].includes(j.action));
            if (fault.send) { callback(Error(SECRET)); return; }
            callback(); if (fault.ack === 'stall') return;
            const field = j.action === 'subscribe' ? 'subscribed' : 'unsubscribed';
            const reply = {action: 'reply', status: 'success', request_id: j.request_id,
                data: {[field]: [j.data.binding], subscriptions: j.action === 'subscribe' ? [j.data.binding] : []}};
            if (fault.ack === 'foreign') reply.data[field] = ['queue_live.changed.' + 'c'.repeat(32)];
            if (fault.ack === 'replay') reply.request_id = 'old';
            queueMicrotask(() => {
                this.emit('message', Buffer.from(JSON.stringify(reply)), false);
                if (fault.ack === 'duplicate') this.emit('message', Buffer.from(JSON.stringify(reply)), false);
            });
        }
        event(foreign = false) {
            const routing = `acdc.dashboard.changed.${A}.${Q}`;
            this.emit('message', Buffer.from(JSON.stringify({action: 'event', name: 'changed',
                subscribed_key: 'queue_live.changed.' + Q, subscription_key: routing, routing_key: routing,
                data: {version: 1, account_id: foreign ? 'c'.repeat(32) : A, queue_id: Q}})), false);
        }
        terminate() { if (!this.terminated) { this.terminated = true; this.emit('close'); } }
    }
    const io = {
        close() { closed = true; for (const reject of pendingHttp) reject(Error(SECRET)); pendingHttp.clear(); },
        async request(method, relative, body, token) {
            assert.equal(closed, false); assert.equal(method, 'GET'); assert.equal(body, undefined); assert.equal(token, SECRET);
            assert.equal(relative, `accounts/${A}/queues/${Q}/live`); requests.push({at: time, relative});
            if (fault.http === 'error') throw Error(SECRET);
            if (fault.http === 'stall') return new Promise((_, reject) => pendingHttp.add(reject));
            const value = dto(EPOCH + time);
            if (fault.http === 'foreign') value.data.account_id = 'c'.repeat(32);
            if (fault.http === 'stale') {
                value.data.source.observation_started_at -= 60; value.data.source.observation_finished_at -= 60;
            }
            if (fault.http === 'incomplete') Object.assign(value.data.agents,
                {runtime_complete: false, observation_started: null, observation_finished: null});
            if (fault.http === 'calls') {
                const call = {call_id: 'PRIVATE_CALL_ID', queue_id: Q, status: 'waiting', entered_at: EPOCH / 1000, handled_at: null};
                value.data.calls.rows = [call]; value.data.calls.observed_count = 1;
                value.data.queues[0].metrics.current_waiting = 1;
            }
            if (['partial', 'unavailable'].includes(fault.http)) {
                value.data.source.status = fault.http;
                value.data.source.reason = fault.http === 'partial' ? 'source_timeout' : 'source_unavailable';
                value.data.source.all_known_sources_responded = false; value.data.source.consistent = false;
                value.data.queues[0].metrics_available = false;
                value.data.queues[0].metrics = null;
                Object.assign(value.data.calls, {available: false, complete: false, observed_count: null});
            }
            return {status: fault.http === 'status' ? 503 : 200,
                headers: {'cache-control': fault.http === 'cache' ? 'public' : 'no-store'}, body: value};
        }
    };
    const o = h.options(argv()); if (fault.clients) o.clients = fault.clients;
    const done = h.run(o, {WebSocket: Socket, io, token: SECRET, lock: {alive: () => held}, validateDetail,
        now: () => time, wallNow: () => EPOCH + time, setTimeout: schedule, clearTimeout: id => timers.delete(id), signals});
    const flush = async () => { for (let i = 0; i < 50; i++) await Promise.resolve(); };
    async function advance(ms) {
        const end = time + ms; let ticks = 0; await flush();
        while (true) {
            const next = [...timers].filter(([, t]) => t.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
            if (!next) break; assert(++ticks <= 10000, 'unbounded timer work'); time = next[1].at;
            timers.delete(next[0]); next[1].fn(); await flush();
        }
        time = end; await flush();
    }
    return {done, sockets, requests, frames, timers, signals, advance, flush, loseLock() { held = false; }, closed: () => closed};
}
async function finish(f) {
    await f.advance(240000);
    let receipt; f.done.then(value => { receipt = value; }); await f.flush();
    assert(receipt, 'bounded run did not settle'); assert.equal(f.timers.size, 0); assert(f.closed());
    assert(f.sockets.every(s => s.terminated));
    const encoded = JSON.stringify(receipt);
    for (const secret of [SECRET, 'PRIVATE_QUEUE_NAME', 'PRIVATE_CALL_ID', A, Q]) assert(!encoded.includes(secret));
    assert.equal(f.signals.listenerCount('SIGINT'), 0); assert.equal(f.signals.listenerCount('SIGTERM'), 0);
    return receipt;
}
async function group(name, fn) { await fn(); groups++; console.log('PASS ' + name); }
(async () => {
    await group('arming fails before private paths or dependency/network access', () => {
        assert.throws(() => h.options(argv().slice(1)), /explicit_load_arming_required/);
        const result = cp.spawnSync(process.execPath, [path.join(__dirname, 'test-queue-live-load.cjs')],
            {encoding: 'utf8', timeout: 3000, maxBuffer: 4096, env: {PATH: '/usr/bin:/bin', LANG: 'C'}});
        assert.ifError(result.error); assert.equal(result.status, 1); assert.equal(result.stdout, '');
        assert.deepEqual(JSON.parse(result.stderr), {result: 'FAIL', kind: 'idle_viewer_load', code: 'explicit_load_arming_required'});
    });
    await group('explicit bounds scope and literal loopback endpoints', () => {
        for (const [key, value] of [['clients', '0'], ['clients', '31'], ['clients', '1.0'], ['duration-seconds', '29'],
            ['duration-seconds', '181'], ['account', '../foreign'], ['queue', Q.toUpperCase()],
            ['api-url', 'http://example.invalid/v2'], ['api-url', 'http://127.0.0.1:8000/v2?x=1'],
            ['ws-url', 'ws://user:password@127.0.0.1/websocket'], ['ws-module', 'ws']]) {
            const args = argv(); args[args.indexOf('--' + key) + 1] = value; assert.throws(() => h.options(args));
        }
        assert.throws(() => h.options([...argv(), '--allow-load']), /invalid_cli/);
        assert.throws(() => h.options([...argv(), '--retry', '1']), /invalid_cli/);
    });
    await group('two real-protocol viewers periodic detail and exact cleanup', async () => {
        const f = fixture(), r = await finish(f);
        assert.equal(r.result, 'PASS'); assert.equal(r.socket_peak, 2); assert.equal(r.subscribe_acks, 2);
        assert.equal(r.unsubscribe_acks, 2); assert(r.valid_snapshots >= 4);
        assert.equal(r.full_cohort_observed_ms, 30000); assert.equal(r.errors, 0);
        assert(f.sockets.every(s => s.config.maxPayload === 65536 && s.config.followRedirects === false));
        assert.equal(r.latency.http.samples, r.valid_snapshots);
        assert(f.requests.some(x => x.at === 15000)); assert(f.requests.some(x => x.at === 15500));
    });
    await group('thirty viewers start no faster than two per second and hold full cohort', async () => {
        const f = fixture({clients: 30}), r = await finish(f);
        assert.equal(r.result, 'PASS'); assert.equal(r.socket_peak, 30); assert.equal(f.sockets.length, 30);
        for (let i = 1; i < 30; i++) assert(f.sockets[i].at - f.sockets[i - 1].at >= 500);
        assert.equal(r.full_cohort_observed_ms, 30000); assert.equal(r.unsubscribe_acks, 30);
    });
    await group('open error close or timeout fail once without retry', async () => {
        for (const open of ['error', 'close', 'stall']) {
            const f = fixture({open}), r = await finish(f); assert.equal(r.result, 'FAIL');
            assert.equal(r.errors, 1); assert(f.sockets.length <= 2); assert.equal(r.reconnects, 0);
        }
    });
    await group('wrong-scope replay duplicate and stalled ACK fail closed', async () => {
        for (const ack of ['foreign', 'replay', 'duplicate', 'stall']) {
            const r = await finish(fixture({ack})); assert.equal(r.result, 'FAIL'); assert.equal(r.errors, 1);
        }
    });
    await group('send errors and HTTP failures never trigger auth or request retry', async () => {
        for (const fault of [{send: true}, {http: 'error'}, {http: 'status'}, {http: 'cache'}, {http: 'foreign'}]) {
            const f = fixture(fault), r = await finish(f); assert.equal(r.result, 'FAIL'); assert(f.requests.length <= 1);
        }
    });
    await group('schema-valid stale observations and active calls cannot pass idle readiness', async () => {
        for (const http of ['stale', 'calls', 'incomplete', 'partial', 'unavailable']) {
            const r = await finish(fixture({http})); assert.equal(r.result, 'FAIL'); assert.equal(r.errors, 1);
            if (['partial', 'unavailable', 'incomplete'].includes(http)) {
                assert.equal(r.code, 'idle_baseline_unavailable'); assert.equal(r.valid_snapshots, 1);
                assert.equal(r.incomplete_snapshots, 1);
                if (http === 'partial') assert.equal(r.partial_snapshots, 1);
                if (http === 'unavailable') assert.equal(r.unavailable_snapshots, 1);
            }
        }
    });
    await group('natural scoped hint validates without event-driven HTTP burst', async () => {
        const f = fixture(); await f.advance(1000); const before = f.requests.length;
        f.sockets[0].event(); await f.flush(); assert.equal(f.requests.length, before);
        const r = await finish(f); assert.equal(r.result, 'PASS'); assert.equal(r.invalidations, 1);
    });
    await group('foreign binary and oversized frames stop the whole cohort', async () => {
        for (const kind of ['foreign', 'binary', 'oversize']) {
            const f = fixture(); await f.advance(1000);
            if (kind === 'foreign') f.sockets[0].event(true);
            else f.sockets[0].emit('message', Buffer.alloc(kind === 'oversize' ? 65537 : 1), kind === 'binary');
            const r = await finish(f); assert.equal(r.result, 'FAIL'); assert.equal(r.errors, 1);
        }
    });
    await group('signal and shared-lock loss stop forward work and remove all resources', async () => {
        for (const kind of ['signal', 'lock']) {
            const f = fixture({clients: 30}); await f.advance(1000);
            if (kind === 'signal') f.signals.emit('SIGTERM'); else f.loseLock();
            const count = f.sockets.length, r = await finish(f);
            assert.equal(r.result, 'FAIL'); assert.equal(f.sockets.length, count); assert.equal(r.errors, 1);
        }
    });
    await group('pending HTTP is cancelled on interruption and global deadline without hanging', async () => {
        for (const signal of [false, true]) {
            const f = fixture({http: 'stall'}); await f.advance(1000);
            if (signal) f.signals.emit('SIGINT');
            const r = await finish(f); assert.equal(r.result, 'FAIL');
            assert.equal(r.code, signal ? 'interrupted' : 'overall_timeout'); assert.equal(r.errors, 1);
        }
    });
    await group('native shared transport retains real-fd locking HTTP bounds and no redirects', () => {
        const source = fs.readFileSync(path.join(__dirname, 'test-queue-live-load.cjs'), 'utf8');
        const shared = fs.readFileSync(path.join(__dirname, 'test-queue-live-isolation.cjs'), 'utf8');
        assert(source.includes('const lock = await lockFixture()'));
        assert(source.includes("const io = transport(o['api-url'], o['ws-url'], o['ws-module'], lock)"));
        assert(shared.includes('/usr/bin/flock -n 3 || exit 75; exec "$@"'));
        assert(shared.includes('bytes > 2 * 1024 * 1024'));
        assert(shared.includes('maxHeaderSize: 16384'));
        assert(shared.includes("cancel('http_redirect_refused')"));
    });
    await group('bounded latency aggregates contain no SLA inference or raw samples', () => {
        assert.deepEqual(h.latency([]), {samples: 0, p50_ms: null, p95_ms: null, max_ms: null});
        assert.deepEqual(h.latency([4, 1, 3, 2]), {samples: 4, p50_ms: 2, p95_ms: 4, max_ms: 4});
    });
    assert.deepEqual(digest(), before);
    console.log(JSON.stringify({result: 'PASS', groups, source_sha256: before, real_network: false, credentials_read: false,
        call_capacity_proven: false, failover_proven: false}));
})().catch(() => { console.error('FAIL queue-live load offline regression; no private diagnostics'); process.exitCode = 1; });
