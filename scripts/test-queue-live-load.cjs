#!/usr/bin/env node
'use strict';
// Explicitly armed, read-only idle viewer load. No login, fixtures, event
// publication, reconnect, call control or service operations.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const {performance} = require('node:perf_hooks');
const {lockFixture, transport, checkReply} = require('./test-queue-live-isolation.cjs');
const {validateEvent} = require('./test-queue-live-wire.cjs');
const ID = /^[a-f0-9]{32}$/, STEP = 8000, POLL = 15000, STAGGER = 500;
class LoadError extends Error { constructor(code) { super(code); this.code = code; } }
const need = (ok, code) => { if (!ok) throw new LoadError(code); };
function options(argv) {
    const o = {}, keys = ['account', 'queue', 'api-url', 'ws-url', 'token-file', 'ws-module', 'clients', 'duration-seconds'];
    for (let i = 0; i < argv.length; i++) {
        const key = argv[i].slice(2);
        need(argv[i].startsWith('--') && !Object.hasOwn(o, key), 'invalid_cli');
        if (key === 'allow-load') o[key] = true;
        else { need(keys.includes(key) && argv[i + 1] && !argv[i + 1].startsWith('--'), 'invalid_cli'); o[key] = argv[++i]; }
    }
    // Before token-file access, lock acquisition, dependency loading or network.
    need(o['allow-load'] === true, 'explicit_load_arming_required');
    need(ID.test(o.account || '') && ID.test(o.queue || ''), 'explicit_scope_required');
    for (const [key, low, high] of [['clients', 1, 30], ['duration-seconds', 30, 180]]) {
        need(typeof o[key] === 'string' && /^[1-9][0-9]*$/.test(o[key]), 'invalid_load_bound');
        o[key] = Number(o[key]); need(o[key] >= low && o[key] <= high, 'invalid_load_bound');
    }
    for (const [key, schemes, pathname] of [['api-url', ['http:', 'https:'], '/v2'], ['ws-url', ['ws:', 'wss:'], '/websocket']]) {
        let url; try { url = new URL(o[key]); } catch (_) { throw new LoadError('invalid_endpoint'); }
        need(schemes.includes(url.protocol) && ['127.0.0.1', '[::1]'].includes(url.hostname) &&
            !url.username && !url.password && !url.search && !url.hash && url.pathname.replace(/\/$/, '') === pathname,
        'literal_loopback_endpoint_required'); o[key] = url;
    }
    need(path.isAbsolute(o['token-file'] || '') && path.isAbsolute(o['ws-module'] || ''), 'explicit_private_inputs_required');
    return o;
}
function tokenInput(file) {
    need(fs.realpathSync(path.dirname(file)) === path.dirname(file), 'unsafe_token_path');
    const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
    try {
        const st = fs.fstatSync(fd);
        need(st.isFile() && st.uid === 0 && (st.mode & 0o777) === 0o600 && st.nlink === 1 && st.size > 0 && st.size <= 16385,
            'unsafe_token_file');
        const bytes = Buffer.alloc(16386);
        try {
            const n = fs.readSync(fd, bytes, 0, bytes.length, 0);
            need(n <= 16385, 'unsafe_token_file');
            const token = bytes.subarray(0, n).toString('utf8').replace(/\n$/, '');
            need(/^[\x21-\x7e]{1,16384}$/.test(token), 'invalid_token'); return token;
        } finally { bytes.fill(0); }
    } finally { fs.closeSync(fd); }
}
function latency(values) {
    if (!values.length) return {samples: 0, p50_ms: null, p95_ms: null, max_ms: null};
    const sorted = [...values].sort((a, b) => a - b), at = p => Math.round(sorted[Math.ceil(sorted.length * p) - 1] * 100) / 100;
    return {samples: sorted.length, p50_ms: at(0.5), p95_ms: at(0.95), max_ms: at(1)};
}
// Dependency seams are for bounded offline replay; CLI always uses native ws,
// the shared real HTTP transport and the production detail schema validator.
async function run(o, deps) {
    const {WebSocket, io, lock, token, validateDetail} = deps;
    const now = deps.now || (() => performance.now()), later = deps.setTimeout || setTimeout,
        cancel = deps.clearTimeout || clearTimeout, wallNow = deps.wallNow || (() => Date.now());
    const clients = [], sleepers = new Set(), samples = {http: [], subscribe: [], unsubscribe: []};
    const counts = {socket_attempts: 0, socket_opens: 0, socket_peak: 0, subscribe_acks: 0, unsubscribe_acks: 0,
        http_requests: 0, valid_snapshots: 0, partial_snapshots: 0, unavailable_snapshots: 0,
        incomplete_snapshots: 0, invalidations: 0, frames: 0, bytes: 0, errors: 0};
    const started = now(); let active = 0, fatal, ending = false, closing = false, readyAt, endedAt, endTimer;
    const totalBudget = o['duration-seconds'] * 1000 + o.clients * STAGGER + 5 * STEP + 1000;
    function check() {
        if (fatal) throw fatal;
        need(now() - started <= totalBudget, 'overall_timeout'); need(lock.alive(), 'shared_lock_lost');
    }
    function wake() { for (const finish of [...sleepers]) finish(); }
    function fail(code) {
        if (fatal || closing) return;
        fatal = new LoadError(code); counts.errors++; ending = true;
        io.close(); wake();
        for (const client of clients) {
            if (client.pending) client.pending.reject(fatal);
            if (client.openReject) client.openReject(fatal);
            client.ws.terminate();
        }
    }
    function sleep(ms) {
        check(); if (ending) return Promise.resolve();
        return new Promise(resolve => {
            let timer;
            const finish = () => { cancel(timer); sleepers.delete(finish); resolve(); };
            sleepers.add(finish); timer = later(finish, ms);
        });
    }
    function finishRun() { endedAt = now(); ending = true; wake(); }
    async function snapshot() {
        check(); const at = now(), wallAt = wallNow(); counts.http_requests++;
        const r = await io.request('GET', `accounts/${o.account}/queues/${o.queue}/live`, undefined, token);
        check(); need(r.status === 200 && r.headers?.['cache-control'] === 'no-store', 'detail_http_failed');
        const data = validateDetail(r.body, o.account, o.queue);
        counts.valid_snapshots++;
        if (data.source.status === 'partial') counts.partial_snapshots++;
        if (data.source.status === 'unavailable') counts.unavailable_snapshots++;
        samples.http.push(now() - at);
        const source = data.source, q = data.queues[0];
        const complete = source.status === 'available' && source.reason === 'consensus' && source.consistent &&
            source.all_known_sources_responded && q.metrics_available && data.calls.available && data.calls.complete &&
            data.agents.roster_complete && data.agents.runtime_complete;
        if (!complete) counts.incomplete_snapshots++;
        need(complete, 'idle_baseline_unavailable');
        // Same-host loopback, allowing one second for integer timestamp edges;
        // generated_at alone is not evidence that either source was refreshed.
        need(Number.isInteger(source.observation_started_at) && Number.isInteger(source.observation_finished_at) &&
            source.observation_started_at >= Math.floor(wallAt / 1000) - 1 &&
            source.observation_finished_at <= Math.ceil(wallNow() / 1000) + 1 &&
            data.agents.observation_started >= Math.floor(wallAt / 1000) - 1 &&
            data.agents.observation_finished <= Math.ceil(wallNow() / 1000) + 1, 'stale_source_observation');
        need(data.calls.observed_count === 0 && q.metrics.current_waiting === 0 && q.metrics.current_handled === 0,
            'idle_baseline_has_calls');
        return at;
    }
    async function startClient() {
        check(); counts.socket_attempts++;
        const ws = new WebSocket(o['ws-url'].href, {maxPayload: 65536, handshakeTimeout: STEP,
            perMessageDeflate: false, followRedirects: false, rejectUnauthorized: true});
        const c = {ws, subscribed: false, closing: false, pending: null, openReject: null, opened: false,
            frames: 0, bytes: 0, done: null}; clients.push(c);
        ws.on('error', () => fail('websocket_transport_failed'));
        ws.on('close', () => { if (c.opened) { active--; c.opened = false; }
            if (!c.closing && !closing) fail('websocket_closed'); });
        ws.on('message', (raw, binary) => {
            if (fatal || closing) return;
            try {
                need(!binary && Buffer.byteLength(raw) <= 65536 && ++c.frames <= 4096 &&
                    (c.bytes += Buffer.byteLength(raw)) <= 4 * 1024 * 1024, 'websocket_input_limit');
                counts.frames++; counts.bytes += Buffer.byteLength(raw);
                const j = JSON.parse(raw.toString('utf8'));
                if (j.action === 'event') {
                    validateEvent(j, o); need(c.subscribed, 'event_outside_subscription'); counts.invalidations++; return;
                }
                need(c.pending && j.action === 'reply' && j.request_id === c.pending.id, 'uncorrelated_reply');
                checkReply(j, 'queue_live.changed.' + o.queue, true, c.pending.action);
                c.subscribed = c.pending.action === 'subscribe'; c.pending.resolve();
            } catch (_) { fail('invalid_or_foreign_websocket_frame'); }
        });
        await new Promise((resolve, reject) => {
            let settled = false;
            const timer = later(() => finish(new LoadError('websocket_open_timeout')), STEP);
            function finish(error) {
                if (settled) return; settled = true; cancel(timer); c.openReject = null;
                if (error) reject(error); else resolve();
            }
            c.openReject = finish;
            ws.once('open', () => { c.opened = true; active++; counts.socket_opens++; counts.socket_peak = Math.max(counts.socket_peak, active); finish(); });
        });
        async function command(action) {
            check(); const at = now(), id = crypto.randomBytes(16).toString('hex');
            await new Promise((resolve, reject) => {
                let settled = false;
                const timer = later(() => finish(new LoadError('websocket_reply_timeout')), STEP);
                function finish(error) {
                    if (settled) return; settled = true; cancel(timer); c.pending = null;
                    if (error) reject(error); else resolve();
                }
                c.pending = {id, action, resolve: () => finish(), reject: finish};
                try { ws.send(JSON.stringify({action, request_id: id, auth_token: token,
                    data: {account_id: o.account, binding: 'queue_live.changed.' + o.queue}}),
                error => { if (error) finish(new LoadError('websocket_send_failed')); }); }
                catch (_) { finish(new LoadError('websocket_send_failed')); }
            });
            counts[action === 'subscribe' ? 'subscribe_acks' : 'unsubscribe_acks']++;
            samples[action].push(now() - at);
        }
        await command('subscribe'); let nextPoll = await snapshot() + POLL;
        c.done = (async () => {
            while (!ending) {
                await sleep(Math.max(0, nextPoll - now())); check();
                if (!ending) { nextPoll = await snapshot() + POLL; }
            }
            check(); await command('unsubscribe'); c.closing = true; ws.terminate();
        })().catch(error => { fail(error instanceof LoadError ? error.code : 'viewer_failed'); });
        return c;
    }
    const signal = () => fail('interrupted');
    if (deps.signals) { deps.signals.on('SIGINT', signal); deps.signals.on('SIGTERM', signal); }
    // Includes stagger, bounded initial HTTP/ACKs and final in-flight GET/ACK.
    const hardTimer = later(() => fail('overall_timeout'), totalBudget);
    const guardTimer = (() => { let timer;
        const tick = () => { if (!closing && !fatal) { if (!lock.alive()) fail('shared_lock_lost'); else timer = later(tick, 250); } };
        timer = later(tick, 250); return () => cancel(timer);
    })();
    try {
        const ready = [];
        for (let i = 0; i < o.clients; i++) {
            check(); ready.push(startClient().catch(error => { fail(error instanceof LoadError ? error.code : 'viewer_failed'); }));
            if (i + 1 < o.clients) await sleep(STAGGER);
        }
        await Promise.all(ready); check(); readyAt = now();
        endTimer = later(finishRun, o['duration-seconds'] * 1000);
        await Promise.all(clients.map(c => c.done)); check();
        need(counts.subscribe_acks === o.clients && counts.unsubscribe_acks === o.clients &&
            counts.socket_peak === o.clients && counts.valid_snapshots >= o.clients * 2, 'incomplete_viewer_load');
    } catch (error) { fail(error instanceof LoadError ? error.code : 'viewer_failed'); }
    finally {
        closing = true; ending = true; cancel(hardTimer); cancel(endTimer); guardTimer(); wake(); io.close();
        for (const c of clients) { if (c.pending) c.pending.reject(new LoadError('load_stopped'));
            if (c.openReject) c.openReject(new LoadError('load_stopped')); c.closing = true; c.ws.terminate(); }
        if (deps.signals) { deps.signals.removeListener('SIGINT', signal); deps.signals.removeListener('SIGTERM', signal); }
    }
    return {result: fatal ? 'FAIL' : 'PASS', code: fatal?.code || null, kind: 'idle_viewer_load',
        clients: o.clients, requested_full_cohort_seconds: o['duration-seconds'], poll_interval_ms: POLL,
        minimum_start_spacing_ms: STAGGER, elapsed_ms: Math.round(now() - started),
        full_cohort_observed_ms: readyAt === undefined ? 0 : Math.round((endedAt ?? now()) - readyAt), ...counts,
        latency: Object.fromEntries(Object.entries(samples).map(([name, values]) => [name, latency(values)])),
        call_capacity_proven: false, failover_proven: false, reconnects: 0, injected_events: 0};
}
async function main(argv) {
    const o = options(argv);
    need(process.getuid() === 0 && !process.env.NODE_OPTIONS && !process.env.NODE_PATH &&
        process.env.NODE_TLS_REJECT_UNAUTHORIZED !== '0', 'clean_root_environment_required');
    const WebSocket = require(o['ws-module']);
    const {validateDetail} = require('./test-fixtures/queue-live-observer.cjs');
    let token = tokenInput(o['token-file']); const lock = await lockFixture();
    try {
        const io = transport(o['api-url'], o['ws-url'], o['ws-module'], lock);
        const receipt = await run(o, {WebSocket, io, lock, token, validateDetail, signals: process});
        process.stdout.write(JSON.stringify(receipt) + '\n'); if (receipt.result !== 'PASS') process.exitCode = 1;
    } finally { token = undefined; lock.close(); }
}
module.exports = {options, latency, run, LoadError};
if (require.main === module) main(process.argv.slice(2)).catch(error => {
    process.stderr.write(JSON.stringify({result: 'FAIL', kind: 'idle_viewer_load',
        code: error instanceof LoadError ? error.code : 'local_or_transport_failure'}) + '\n'); process.exitCode = 1;
});
