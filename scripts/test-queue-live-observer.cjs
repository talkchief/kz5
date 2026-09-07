#!/usr/bin/env node
'use strict';
// Offline boundaries only: actual observer and production OpenAPI validator;
// synthetic HTTP/WebSocket/clock. No server, socket, auth, calls or publication.
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm');
const crypto = require('node:crypto'), {EventEmitter} = require('node:events');
const assert = require('node:assert/strict'), {createRequire} = require('node:module');
const file = path.join(__dirname, 'test-fixtures/queue-live-observer.cjs'), bytes = fs.readFileSync(file);
const schemaFile = path.join(__dirname, 'api-docs-queue-live.cjs'), schemaBytes = fs.readFileSync(schemaFile);
const actualRequire = createRequire(file), A = 'a'.repeat(32), Q = '1'.repeat(32), B = 'b'.repeat(32);
const CALL = 'synthetic-private-call', SECRET = 'SYNTHETIC_TOKEN_MUST_NOT_ESCAPE', EPOCH = 1788739200000;
const copy = o => JSON.parse(JSON.stringify(o));
function dto(state = 'waiting') {
    const rows = state === 'gone' ? [] : [{call_id: CALL, queue_id: Q, status: state,
        entered_at: EPOCH / 1000 - 30, handled_at: state === 'handled' ? EPOCH / 1000 - 1 : null}];
    const waiting = state === 'waiting' ? 1 : 0, handled = state === 'handled' ? 1 : 0;
    return {status: 'success', data: {version: 1, account_id: A, generated_at: EPOCH / 1000,
        window: {from: EPOCH / 1000 - 3600, to: EPOCH / 1000, seconds: 3600},
        queues: [{id: Q, name: 'PRIVATE_QUEUE_LABEL', strategy: 'round_robin', metrics_available: true,
            metrics: {current_waiting: waiting, current_handled: handled, max_current_wait_seconds: waiting ? 30 : null,
                records_entered: rows.length, waiting_in_cohort: waiting, handled_in_cohort: handled, processed_in_cohort: 0,
                abandoned_in_cohort: 0, average_answered_wait_seconds: handled ? 29 : null, average_processed_talk_seconds: null}}],
        calls: {available: true, complete: true, truncated: false, limit: 200, observed_count: rows.length,
            order: 'queue_id_entered_call_id', rows},
        agents: {limit: 200, roster_complete: true, truncated: false, runtime_complete: true,
            endpoint_reachability_verified: false, observation_started: EPOCH / 1000, observation_finished: EPOCH / 1000, rows: []},
        pagination: {page_size: 1, has_more: false, next_start_queue_id: null},
        source: {coverage: 'observed_replicas', all_known_sources_responded: true, consistent: true, atomic_snapshot: false,
            status: 'available', reason: 'consensus', observation_started_at: EPOCH / 1000, observation_finished_at: EPOCH / 1000},
        capabilities: {live_call_details: true, agent_runtime: true, websocket_updates: true, historical_reporting: false}}};
}
function setup(options = {}) {
    let clock = 0, nextTimer = 0, exported, current = dto(), pendingHttp = 0, maxHttp = 0;
    const timers = new Map(), sent = [], gets = [], sockets = [], logs = [];
    const schedule = (fn, ms) => { timers.set(++nextTimer, {fn, at: clock + ms}); return nextTimer; };
    const cancel = id => timers.delete(id);
    class Clock extends Date { static now() { return EPOCH + clock; } }
    class Socket extends EventEmitter {
        constructor(url, config) { super(); this.url = url; this.config = config; sockets.push(this);
            queueMicrotask(() => { if (options.openError) this.emit('error', Error(SECRET)); else this.emit('open'); }); }
        send(value, callback) {
            const frame = JSON.parse(value); sent.push(frame);
            assert(['subscribe', 'unsubscribe'].includes(frame.action));
            if (options.sendError) { callback(Error(SECRET)); return; }
            if (!options.holdAck) queueMicrotask(() => this.ack(frame));
            if (callback) callback();
        }
        ack(frame = sent.at(-1), change = x => x) {
            const field = frame.action === 'subscribe' ? 'subscribed' : 'unsubscribed';
            this.emit('message', Buffer.from(JSON.stringify(change({action: 'reply', request_id: frame.request_id,
                status: 'success', data: {[field]: [frame.data.binding], subscriptions: frame.action === 'subscribe' ? [frame.data.binding] : []}}))), false);
        }
        event(change = x => x) {
            const routing = 'acdc.dashboard.changed.' + A + '.' + Q;
            this.emit('message', Buffer.from(JSON.stringify(change({action: 'event', name: 'changed', subscribed_key: 'queue_live.changed.' + Q,
                subscription_key: routing, routing_key: routing, data: {version: 1, account_id: A, queue_id: Q}}))), false);
        }
        terminate() { this.terminated = true; this.emit('close'); }
    }
    const transport = {get(url, config, callback) {
        gets.push({url: url.href, config, at: clock}); pendingHttp++; maxHttp = Math.max(maxHttp, pendingHttp);
        const req = new EventEmitter(); let ended = false;
        req.destroy = () => { if (!ended) { ended = true; pendingHttp--; } };
        queueMicrotask(() => {
            if (options.httpError) { req.emit('error', Error(SECRET)); return; }
            if (options.holdHttp) return;
            const response = new EventEmitter();
            response.statusCode = options.status || 200; response.headers = {'cache-control': options.cache || 'no-store'};
            callback(response);
            if (ended) return;
            const payload = options.rawBody === undefined ? Buffer.from(JSON.stringify(current)) : Buffer.from(options.rawBody);
            response.emit('data', payload); response.emit('end');
            if (!ended) { ended = true; pendingHttp--; }
        });
        return req;
    }};
    const module = {exports: {}};
    vm.runInNewContext(bytes.toString('utf8'), {module, exports: module.exports, __filename: file,
        require(name) {
            if (name === 'node:http' || name === 'node:https') return transport;
            if (name === 'node:perf_hooks') return {performance: {now: () => clock}};
            if (name === '/offline/controlled-ws.cjs') return Socket;
            return actualRequire(name);
        }, Buffer, URL, Date: Clock, process: {env: {}}, setTimeout: schedule, clearTimeout: cancel,
        console: {log: value => logs.push(value), error: value => logs.push(value)}}, {filename: file, timeout: 1000});
    exported = module.exports;
    const input = {accountId: A, queueId: Q, token: SECRET, apiUrl: 'http://127.0.0.1:8000/v2',
        wsUrl: 'ws://127.0.0.1:5555/websocket', wsModule: '/offline/controlled-ws.cjs'};
    const observer = new exported.QueueLiveObserver(input);
    const flush = async () => { for (let i = 0; i < 20; i++) await Promise.resolve(); };
    return {observer, input, Constructor: exported.QueueLiveObserver, sent, gets, sockets, timers, logs,
        set(value) { current = copy(value); }, maxHttp: () => maxHttp,
        async advance(ms) { const end = clock + ms; let count = 0; await flush();
            while (true) { const next = [...timers].filter(([, t]) => t.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
                if (!next) break; assert(++count < 2000, 'Unbounded timer loop'); clock = next[1].at;
                timers.delete(next[0]); next[1].fn(); await flush(); }
            clock = end; await flush(); }, flush};
}
let groups = 0;
async function group(name, run) { await run(); groups++; console.log('PASS ' + name); }
const rejects = (promise, code) => assert.rejects(promise, e => e.code === code && !e.message.includes(SECRET));
async function run() {
    await group('literal loopback endpoints, explicit scope, token and absolute ws module reject unsafe input', async () => {
        const f = setup();
        for (const change of [x => x.accountId = '../tenant', x => x.queueId = B.toUpperCase(), x => x.token = 'bad\nheader',
            x => x.apiUrl = 'http://example.invalid/v2', x => x.apiUrl = 'http://localhost/v2',
            x => x.apiUrl = 'http://127.0.0.1/v2?secret=value', x => x.wsUrl = 'ws://user:pass@127.0.0.1/websocket',
            x => x.wsModule = 'ws', x => x.extra = true]) {
            const input = {...f.input}; change(input); assert.throws(() => new f.Constructor(input));
        }
        assert.equal(f.gets.length, 0); assert.equal(f.sent.length, 0); await f.observer.close();
    });
    await group('exact subscribe, one query-free detail GET, sanitized schema result and exact unsubscribe', async () => {
        const f = setup(); await f.observer.open(); const snap = await f.observer.snapshot();
        assert.equal(f.gets.length, 1); assert.equal(f.gets[0].url, 'http://127.0.0.1:8000/v2/accounts/' + A + '/queues/' + Q + '/live');
        assert.equal(f.gets[0].config.headers['X-Auth-Token'], SECRET); assert.equal(snap.waiting_count, 1);
        const proof = await f.observer.close(); assert.equal(proof.http_requests, 1); assert.equal(proof.valid_snapshots, 1);
        assert(proof.unsubscribe_ack_at_ms); assert.deepEqual(f.sent.map(x => x.action), ['subscribe', 'unsubscribe']);
        for (const secret of [SECRET, CALL, 'PRIVATE_QUEUE_LABEL', A, Q]) assert(!JSON.stringify({snap, proof}).includes(secret));
        assert.equal(f.timers.size, 0); assert(f.sockets[0].terminated); assert.equal(f.logs.length, 0);
        assert.deepEqual(await f.observer.close(), proof);
        snap.waiting_count = 999; proof.http_requests = 999;
        assert.equal(f.observer.evidence().http_requests, 1); assert.equal(f.observer.evidence().last_snapshot.waiting_count, 1);
    });
    await group('waiting handled gone each needs a fresh post-open invalidation and later GET; no causal event nonce claim', async () => {
        const f = setup(); await f.observer.open(); await f.observer.snapshot();
        for (const phase of ['waiting', 'handled', 'gone']) {
            f.set(dto(phase)); f.sockets[0].event();
            const result = await f.observer.waitForPhase(CALL, phase, 2000);
            assert.equal(result.phase, phase); assert.equal(result.invalidations_since_prior_phase, 1);
            assert.equal(result.active_count, phase === 'gone' ? 0 : 1);
        }
        const e = await f.observer.close(); assert.equal(e.phases.length, 3); assert.equal(e.invalidations, 3);
        assert.equal(e.event_causal_correlation_verified, false); assert.equal(f.maxHttp(), 1);
        await rejects(f.observer.snapshot(), 'observer_not_open');
    });
    await group('polling state alone cannot pass and does not recycle the previous phase event', async () => {
        const f = setup(); await f.observer.open();
        let wait = f.observer.waitForPhase(CALL, 'waiting', 1000); const failure = rejects(wait, 'phase_observation_timeout');
        await f.advance(1000); await failure; assert.equal(f.observer.evidence().phases.length, 0);
        for (let i = 1; i < f.gets.length; i++) assert(f.gets[i].at - f.gets[i - 1].at >= 250);
        f.sockets[0].event(); await f.observer.waitForPhase(CALL, 'waiting', 1000); f.set(dto('handled'));
        wait = f.observer.waitForPhase(CALL, 'handled', 1000); const second = rejects(wait, 'phase_observation_timeout');
        await f.advance(1000); await second; await f.observer.close();
    });
    await group('terminal absence needs prior positive observation and complete nontruncated source', async () => {
        const f = setup(); await f.observer.open(); f.set(dto('gone')); f.sockets[0].event();
        await rejects(f.observer.waitForPhase(CALL, 'gone', 1000), 'terminal_absence_requires_prior_observation');
        f.set(dto()); await f.observer.waitForPhase(CALL, 'waiting', 1000);
        const partial = dto('gone'); Object.assign(partial.data.source, {status: 'unavailable', reason: 'source_unavailable',
            consistent: false, all_known_sources_responded: false, observation_started_at: null, observation_finished_at: null});
        Object.assign(partial.data.queues[0], {metrics_available: false, metrics: null});
        Object.assign(partial.data.calls, {available: false, complete: false, observed_count: null});
        f.set(partial); f.sockets[0].event(); const wait = rejects(f.observer.waitForPhase(CALL, 'gone', 1000), 'phase_observation_timeout');
        await f.advance(1000); await wait;
        const capped = dto(); capped.data.calls.complete = false; capped.data.calls.truncated = true;
        capped.data.calls.observed_count = 201;
        Object.assign(capped.data.queues[0].metrics, {current_waiting: 201, records_entered: 201, waiting_in_cohort: 201});
        capped.data.calls.rows = Array.from({length: 200}, (_, i) => ({...dto().data.calls.rows[0], call_id: 'other-' + String(i).padStart(3, '0')}));
        f.set(capped); const absentInCap = rejects(f.observer.waitForPhase(CALL, 'gone', 1000), 'phase_observation_timeout');
        await f.advance(1000); await absentInCap; await f.observer.close();
    });
    await group('production schema and runtime scope/count/order/time contradictions reject', async () => {
        for (const change of [x => x.data.account_id = B, x => x.data.queues[0].id = B,
            x => x.data.calls.rows[0].queue_id = B, x => x.data.calls.rows[0].status = 'answered',
            x => x.data.calls.rows[0].caller_number = SECRET, x => x.data.calls.observed_count = 2,
            x => x.data.queues[0].metrics.current_waiting = 2,
            x => x.data.calls.rows[0].entered_at = x.data.generated_at + 1,
            x => x.data.window.to = x.data.generated_at + 1,
            x => x.data.agents.runtime_complete = false, x => x.data.capabilities.websocket_updates = false,
            x => { x.data.calls.rows.push({...x.data.calls.rows[0], status: 'handled', handled_at: EPOCH / 1000});
                x.data.calls.observed_count = 2; x.data.queues[0].metrics.current_handled = 1; },
            x => { x.data.calls.rows = ['z-last', 'a-first'].map(call_id => ({...x.data.calls.rows[0], call_id}));
                x.data.calls.observed_count = 2; x.data.queues[0].metrics.current_waiting = 2; }]) {
            const f = setup(); await f.observer.open(); const invalid = dto(); change(invalid); f.set(invalid);
            await assert.rejects(f.observer.snapshot(), e => typeof e.code === 'string' && !e.message.includes(SECRET)); await f.observer.close();
        }
        const f = setup(); await f.observer.open(); const valid = dto(); valid.data.generated_at += 2; f.set(valid);
        assert.equal((await f.observer.snapshot()).available, true, 'Response generation may follow cohort window time'); await f.observer.close();
    });
    await group('wrong or malformed native event fails closed without exporting the frame', async () => {
        for (const change of [x => { x.data.account_id = B; return x; }, x => { x.data.queue_id = B; return x; },
            x => { x.routing_key = 'foreign'; return x; }, x => { x.data.secret = SECRET; return x; },
            x => { x.data.version = 2; return x; }]) {
            const f = setup(); await f.observer.open(); f.sockets[0].event(change);
            await rejects(f.observer.snapshot(), 'invalid_or_foreign_invalidation');
            await rejects(f.observer.close(), 'invalid_or_foreign_invalidation');
            assert(f.sockets[0].terminated); assert(!JSON.stringify(f.observer.evidence()).includes(SECRET));
        }
    });
    await group('subscribe and unsubscribe acknowledgements must exactly match one owned binding', async () => {
        const f = setup({holdAck: true}); const opening = f.observer.open(); await f.flush();
        f.sockets[0].ack(undefined, reply => { reply.data.subscriptions = []; return reply; });
        await rejects(opening, 'invalid_subscription_ack'); assert(f.sockets[0].terminated);
        const g = setup({holdAck: true}); const opened = g.observer.open(); await g.flush(); g.sockets[0].ack(); await opened;
        const closing = g.observer.close(); await g.flush();
        g.sockets[0].ack(undefined, reply => { reply.data.unsubscribed = []; return reply; });
        await rejects(closing, 'invalid_subscription_ack'); assert.equal(g.observer.evidence().unsubscribe_ack_at_ms, null);
    });
    await group('transport/HTTP errors and oversized or invalid bodies have fixed secret-free failure codes', async () => {
        for (const [options, code] of [[{httpError: true}, 'http_transport_failed'], [{status: 302}, 'detail_http_status'],
            [{status: 403}, 'detail_http_status'], [{cache: 'private'}, 'detail_no_store_required'],
            [{rawBody: SECRET}, 'invalid_http_json'], [{rawBody: 'x'.repeat(2 * 1024 * 1024 + 1)}, 'http_body_limit']]) {
            const f = setup(options); await f.observer.open(); await rejects(f.observer.snapshot(), code); await f.observer.close();
        }
        const f = setup({openError: true}); await rejects(f.observer.open(), 'socket_open_failed'); assert(f.sockets[0].terminated);
    });
    await group('concurrent observation rejected, close aborts pending HTTP and still acknowledges unsubscribe', async () => {
        const f = setup({holdHttp: true}); await f.observer.open(); const read = f.observer.snapshot();
        const cancelled = rejects(read, 'observer_closing'); await rejects(f.observer.snapshot(), 'observer_operation_in_progress');
        await f.observer.close(); await cancelled; assert.equal(f.maxHttp(), 1); assert.equal(f.timers.size, 0);
        assert(f.observer.evidence().unsubscribe_ack_at_ms);
    });
    await group('held subscription and HTTP operations obey hard timeouts and clean timers', async () => {
        const f = setup({holdAck: true}); const opening = rejects(f.observer.open(), 'socket_reply_timeout');
        await f.advance(5000); await opening; assert(f.sockets[0].terminated); assert.equal(f.timers.size, 0);
        const g = setup({holdHttp: true}); await g.observer.open(); const read = rejects(g.observer.snapshot(), 'http_timeout');
        await g.advance(5000); await read; await g.observer.close(); assert.equal(g.timers.size, 0);
    });
    await group('shortened final HTTP budget reports phase deadline without hiding full HTTP timeouts', async () => {
        const f = setup({holdHttp: true}); await f.observer.open();
        const phase = rejects(f.observer.waitForPhase(CALL, 'waiting', 1000), 'phase_observation_timeout');
        await f.advance(1000); await phase;
        assert.equal(f.observer.evidence().phase_timeouts, 1); await f.observer.close();
        const g = setup({holdHttp: true}); await g.observer.open();
        const transport = rejects(g.observer.waitForPhase(CALL, 'waiting', 6000), 'http_timeout');
        await g.advance(5000); await transport;
        assert.equal(g.observer.evidence().phase_timeouts, 0); await g.observer.close();
    });
    assert(bytes.equals(fs.readFileSync(file))); assert(schemaBytes.equals(fs.readFileSync(schemaFile)));
    console.log(JSON.stringify({status: 'PASS', groups, synthetic_io_only: true,
        observer_sha256: crypto.createHash('sha256').update(bytes).digest('hex'),
        schema_sha256: crypto.createHash('sha256').update(schemaBytes).digest('hex')}));
}
run().catch(error => { console.error(error); process.exitCode = 1; });
