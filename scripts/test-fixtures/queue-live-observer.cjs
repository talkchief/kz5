'use strict';
// Read-only, natural-event observer for an externally owned isolated call test.
// No login, event publication, call command, retrying auth or persistent state.
const path = require('node:path'), crypto = require('node:crypto');
const http = require('node:http'), https = require('node:https');
const {performance} = require('node:perf_hooks');
const Ajv = require('../api-docs-tooling/node_modules/ajv');
const {queueLiveContract} = require('../api-docs-queue-live.cjs');
const ID = /^[a-f0-9]{32}$/, BODY_LIMIT = 2 * 1024 * 1024, FRAME_LIMIT = 65536;
const STEP_MS = 5000, POLL_MS = 250;
class ObserverError extends Error { constructor(code) { super(code); this.name = 'QueueLiveObserverError'; this.code = code; } }
function check(ok, code) { if (!ok) throw new ObserverError(code); }
function exact(o, keys) { return o && !Array.isArray(o) && typeof o === 'object'
    && Object.keys(o).sort().join(',') === keys.slice().sort().join(','); }
function safeText(value) { return typeof value === 'string' && value.length > 0
    && Buffer.byteLength(value, 'utf8') <= 256 && !/[\x00-\x1f\x7f]/.test(value); }
function endpoint(value, protocols, pathname) {
    let u; try { u = new URL(value); } catch (_) { throw new ObserverError('invalid_endpoint'); }
    check(protocols.includes(u.protocol) && ['127.0.0.1', '[::1]'].includes(u.hostname)
        && !u.username && !u.password && !u.search && !u.hash && u.pathname.replace(/\/$/, '') === pathname,
    'literal_loopback_endpoint_required'); return u;
}
let validateSchema;
function validateDetail(body, account, queue) {
    if (!validateSchema) {
        const schemas = queueLiveContract().schemas;
        validateSchema = new Ajv({strict: false, validateFormats: false}).compile({components: {schemas},
            $ref: '#/components/schemas/QueueLiveDetailEnvelope'});
    }
    check(body && body.status === 'success' && validateSchema(body), 'invalid_detail_schema');
    const d = body.data, q = d.queues[0], c = d.calls, s = d.source, g = d.agents;
    check(d.account_id === account && q.id === queue, 'foreign_snapshot_scope');
    check(Number.isSafeInteger(d.generated_at) && Number.isSafeInteger(d.window.to) && d.window.to <= d.generated_at
        && d.window.from === d.window.to - 3600, 'invalid_snapshot_window');
    check(d.capabilities.websocket_updates === true, 'native_capability_unavailable');
    const available = s.status === 'available';
    check(q.metrics_available === available && c.available === available, 'inconsistent_source_availability');
    check((s.observation_started_at === null && s.observation_finished_at === null)
        || (Number.isSafeInteger(s.observation_started_at) && Number.isSafeInteger(s.observation_finished_at)
            && s.observation_started_at <= s.observation_finished_at && s.observation_finished_at <= d.generated_at),
    'invalid_source_times');
    if (available) {
        check(Number.isSafeInteger(c.observed_count) && Number.isSafeInteger(q.metrics.current_waiting)
            && Number.isSafeInteger(q.metrics.current_handled)
            && c.observed_count === q.metrics.current_waiting + q.metrics.current_handled
            && c.rows.length === Math.min(c.observed_count, 200), 'inconsistent_call_counts');
        let previous, waiting = 0, handled = 0; const seen = new Set();
        for (const row of c.rows) {
            check(row.queue_id === queue && safeText(row.call_id) && !seen.has(row.call_id), 'foreign_or_duplicate_call');
            seen.add(row.call_id);
            check(Number.isSafeInteger(row.entered_at) && row.entered_at <= d.generated_at
                && (row.handled_at === null || (Number.isSafeInteger(row.handled_at)
                    && row.entered_at <= row.handled_at && row.handled_at <= d.generated_at)), 'invalid_call_times');
            check(!previous || previous.entered_at < row.entered_at || (previous.entered_at === row.entered_at
                && Buffer.compare(Buffer.from(previous.call_id), Buffer.from(row.call_id)) < 0), 'invalid_call_order');
            previous = row; if (row.status === 'waiting') waiting++; else handled++;
        }
        check(c.truncated ? waiting <= q.metrics.current_waiting && handled <= q.metrics.current_handled
            : waiting === q.metrics.current_waiting && handled === q.metrics.current_handled, 'inconsistent_call_state_counts');
    }
    let previousAgent;
    for (const row of g.rows) {
        check(safeText(row.name) && (!previousAgent || previousAgent < row.agent_id), 'invalid_agent_identity_order');
        previousAgent = row.agent_id;
    }
    const timed = Number.isSafeInteger(g.observation_started) && Number.isSafeInteger(g.observation_finished);
    check((timed && g.observation_started <= g.observation_finished)
        || (g.observation_started === null && g.observation_finished === null), 'invalid_agent_times');
    check(g.runtime_complete === (timed && !g.truncated && g.rows.every(row => row.observed))
        && (timed || g.rows.every(row => !row.observed && row.reason === 'source_unavailable')), 'inconsistent_agent_availability');
    return d;
}
function validateEvent(j, account, queue) {
    const binding = 'queue_live.changed.' + queue, routing = 'acdc.dashboard.changed.' + account + '.' + queue;
    check(exact(j, ['action', 'name', 'subscribed_key', 'subscription_key', 'routing_key', 'data'])
        && j.action === 'event' && j.name === 'changed' && j.subscribed_key === binding
        && j.subscription_key === routing && j.routing_key === routing
        && exact(j.data, ['version', 'account_id', 'queue_id']) && j.data.version === 1
        && j.data.account_id === account && j.data.queue_id === queue, 'invalid_or_foreign_invalidation');
}
class QueueLiveObserver {
    constructor(options) {
        check(exact(options, ['accountId', 'queueId', 'token', 'apiUrl', 'wsUrl', 'wsModule']), 'invalid_observer_options');
        const {accountId: account, queueId: queue} = options;
        check(ID.test(account) && ID.test(queue), 'invalid_observer_scope');
        check(typeof options.token === 'string' && /^[\x21-\x7e]{1,16384}$/.test(options.token), 'invalid_observer_token');
        check(typeof options.wsModule === 'string' && path.isAbsolute(options.wsModule), 'absolute_ws_module_required');
        check(process.env.NODE_TLS_REJECT_UNAUTHORIZED !== '0', 'tls_verification_required');
        const api = endpoint(options.apiUrl, ['http:', 'https:'], '/v2');
        const socketUrl = endpoint(options.wsUrl, ['ws:', 'wss:'], '/websocket');
        const detailUrl = new URL(api.href.replace(/\/$/, '') + '/accounts/' + account + '/queues/' + queue + '/live');
        let WebSocket; try { WebSocket = require(options.wsModule); } catch (_) { throw new ObserverError('ws_dependency_unavailable'); }
        check(typeof WebSocket === 'function', 'invalid_ws_dependency');
        let token = options.token, state = 'new', ws, fault, pendingCommand, activeHttp, wake, busy = false;
        let subscribed = false, consumedEvents = 0, lastRequestStart = -Infinity, frameBytes = 0, frames = 0;
        const seenCalls = new Map();
        const proof = {opened_at_ms: null, subscribe_ack_at_ms: null, closed_at_ms: null, unsubscribe_ack_at_ms: null,
            http_requests: 0, valid_snapshots: 0, invalidations: 0, first_invalidation_at_ms: null,
            last_invalidation_at_ms: null, phase_timeouts: 0, phases: [], last_snapshot: null};
        const evidence = () => JSON.parse(JSON.stringify({...proof,
            event_causal_correlation_verified: false, broker_barrier_verified: false}));
        function fail(code) {
            fault ||= new ObserverError(code);
            if (pendingCommand) { const p = pendingCommand; pendingCommand = null; clearTimeout(p.timer); p.reject(fault); }
            if (activeHttp) activeHttp.abort(fault);
            if (wake) wake();
        }
        function ready() { if (fault) throw fault; check(state === 'open', 'observer_not_open'); }
        function delay(ms) {
            return new Promise(resolve => {
                const timer = setTimeout(done, ms);
                function done() { clearTimeout(timer); if (wake === done) wake = null; resolve(); }
                wake = done;
            });
        }
        function command(action) {
            if (fault) return Promise.reject(fault);
            check(!pendingCommand, 'concurrent_socket_command');
            const id = 'queue-observer-' + crypto.randomBytes(12).toString('hex');
            return new Promise((resolve, reject) => {
                pendingCommand = {id, action, resolve, reject, timer: setTimeout(() => fail('socket_reply_timeout'), STEP_MS)};
                try { ws.send(JSON.stringify({action, request_id: id, auth_token: token,
                    data: {account_id: account, binding: 'queue_live.changed.' + queue}}), error => { if (error) fail('socket_send_failed'); }); }
                catch (_) { fail('socket_send_failed'); }
            });
        }
        function message(data, binary) {
            try {
                frames++; frameBytes += data.length;
                check(!binary && data.length <= FRAME_LIMIT && frames <= 4096 && frameBytes <= 4 * 1024 * 1024, 'socket_input_limit');
                const j = JSON.parse(data.toString('utf8'));
                if (j.action === 'event') {
                    validateEvent(j, account, queue);
                    check(subscribed, 'invalidation_before_subscription');
                    proof.invalidations++; proof.last_invalidation_at_ms = Date.now();
                    proof.first_invalidation_at_ms ??= proof.last_invalidation_at_ms;
                } else {
                    check(j.action === 'reply' && pendingCommand && j.request_id === pendingCommand.id, 'unexpected_socket_reply');
                    const p = pendingCommand, binding = 'queue_live.changed.' + queue;
                    const field = p.action === 'subscribe' ? 'subscribed' : 'unsubscribed';
                    check(j.status === 'success' && exact(j.data, [field, 'subscriptions'])
                        && Array.isArray(j.data[field]) && j.data[field].length === 1 && j.data[field][0] === binding
                        && Array.isArray(j.data.subscriptions)
                        && JSON.stringify(j.data.subscriptions) === JSON.stringify(p.action === 'subscribe' ? [binding] : []),
                    'invalid_subscription_ack');
                    pendingCommand = null; clearTimeout(p.timer); subscribed = p.action === 'subscribe';
                    if (subscribed) proof.subscribe_ack_at_ms = Date.now(); else proof.unsubscribe_ack_at_ms = Date.now();
                    p.resolve();
                }
            } catch (error) { fail(error instanceof ObserverError ? error.code : 'invalid_socket_json'); }
        }
        async function fetchSnapshot(timeout = STEP_MS) {
            ready(); check(!activeHttp, 'concurrent_snapshot');
            proof.http_requests++; lastRequestStart = performance.now();
            const eventsAtRequest = proof.invalidations;
            const body = await new Promise((resolve, reject) => {
                let req, timer, settled = false;
                function finish(error, value) {
                    if (settled) return; settled = true; clearTimeout(timer); activeHttp = null;
                    if (error) { if (req) req.destroy(); reject(error); } else resolve(value);
                }
                activeHttp = {abort: error => finish(error)};
                timer = setTimeout(() => finish(new ObserverError('http_timeout')), timeout);
                try {
                    req = (detailUrl.protocol === 'https:' ? https : http).get(detailUrl, {agent: false,
                        headers: {Accept: 'application/json', 'X-Auth-Token': token}}, res => {
                        if (res.statusCode !== 200) return finish(new ObserverError('detail_http_status'));
                        if (res.headers['cache-control'] !== 'no-store') return finish(new ObserverError('detail_no_store_required'));
                        const chunks = []; let size = 0;
                        res.on('data', chunk => {
                            size += chunk.length;
                            if (size > BODY_LIMIT) finish(new ObserverError('http_body_limit'));
                            else chunks.push(chunk);
                        });
                        res.on('aborted', () => finish(new ObserverError('http_response_aborted')));
                        res.on('error', () => finish(new ObserverError('http_response_error')));
                        res.on('end', () => {
                            if (settled) return;
                            try { finish(null, JSON.parse(Buffer.concat(chunks).toString('utf8'))); }
                            catch (_) { finish(new ObserverError('invalid_http_json')); }
                        });
                    });
                    req.on('error', () => finish(new ObserverError('http_transport_failed')));
                } catch (_) { finish(new ObserverError('http_transport_failed')); }
            });
            ready(); const d = validateDetail(body, account, queue), q = d.queues[0];
            proof.valid_snapshots++;
            const clean = {observed_at_ms: Date.now(), generated_at: d.generated_at,
                source_observation_started_at: d.source.observation_started_at,
                source_observation_finished_at: d.source.observation_finished_at,
                available: d.calls.available, complete: d.calls.complete, truncated: d.calls.truncated,
                waiting_count: q.metrics_available ? q.metrics.current_waiting : null,
                handled_count: q.metrics_available ? q.metrics.current_handled : null,
                active_count: d.calls.observed_count, call_rows: d.calls.rows.length};
            proof.last_snapshot = clean;
            return {data: d, clean, eventsAtRequest};
        }
        async function exclusive(work) {
            ready(); check(!busy, 'observer_operation_in_progress'); busy = true;
            try { const value = await work(); ready(); return value; }
            catch (e) { throw e instanceof ObserverError ? e : new ObserverError('observer_operation_failed'); }
            finally { busy = false; }
        }
        this.open = async () => {
            check(state === 'new', 'observer_already_started'); state = 'opening';
            try {
                ws = new WebSocket(socketUrl.href, {maxPayload: FRAME_LIMIT, handshakeTimeout: STEP_MS,
                    perMessageDeflate: false, followRedirects: false, rejectUnauthorized: true});
                ws.on('message', message); ws.on('error', () => fail('socket_transport_failed'));
                ws.on('close', () => { if (state !== 'closed') fail('socket_closed_early'); });
                await new Promise((resolve, reject) => {
                    const timer = setTimeout(() => { cleanup(); reject(new ObserverError('socket_open_timeout')); }, STEP_MS);
                    function cleanup() { clearTimeout(timer); ws.removeListener('open', opened); ws.removeListener('error', failed); ws.removeListener('close', failed); }
                    function opened() { cleanup(); resolve(); }
                    function failed() { cleanup(); reject(new ObserverError('socket_open_failed')); }
                    ws.once('open', opened); ws.once('error', failed); ws.once('close', failed);
                });
                await command('subscribe'); if (fault) throw fault;
                state = 'open'; proof.opened_at_ms = Date.now(); return evidence();
            } catch (e) {
                state = 'closed'; token = undefined; if (ws) ws.terminate();
                throw e instanceof ObserverError ? e : new ObserverError('observer_open_failed');
            }
        };
        this.snapshot = () => exclusive(async () => JSON.parse(JSON.stringify((await fetchSnapshot()).clean)));
        this.waitForPhase = (callId, phase, timeout) => exclusive(async () => {
            check(safeText(callId) && ['waiting', 'handled', 'gone'].includes(phase), 'invalid_phase_request');
            check(Number.isInteger(timeout) && timeout >= 250 && timeout <= 60000, 'invalid_phase_timeout');
            check(seenCalls.get(callId) !== 'gone', 'call_already_observed_gone');
            check(phase !== 'gone' || seenCalls.has(callId), 'terminal_absence_requires_prior_observation');
            check(seenCalls.has(callId) || seenCalls.size < 64, 'observed_call_limit');
            const deadline = performance.now() + timeout, before = proof.http_requests;
            while (performance.now() < deadline) {
                ready(); const remaining = deadline - performance.now();
                let sample;
                try { sample = await fetchSnapshot(Math.min(STEP_MS, Math.max(1, remaining))); }
                catch (error) {
                    // A final request gets only the phase's remaining budget.
                    // Expiring that shortened budget is not a five-second API
                    // timeout; retain the distinction in acceptance evidence.
                    if (error.code === 'http_timeout' && remaining < STEP_MS && performance.now() >= deadline) {
                        proof.phase_timeouts++; throw new ObserverError('phase_observation_timeout');
                    }
                    throw error;
                }
                const calls = sample.data.calls, row = calls.rows.find(r => r.call_id === callId);
                const complete = calls.available && calls.complete && !calls.truncated;
                if (performance.now() < deadline && complete && sample.eventsAtRequest > consumedEvents
                    && (phase === 'gone' ? !row : row && row.status === phase)) {
                    const result = {phase, ...sample.clean, invalidations_since_prior_phase: sample.eventsAtRequest - consumedEvents,
                        total_invalidations: sample.eventsAtRequest, snapshots_for_phase: proof.http_requests - before};
                    consumedEvents = sample.eventsAtRequest; seenCalls.set(callId, phase); proof.phases.push(result);
                    check(proof.phases.length <= 192, 'phase_evidence_limit'); return JSON.parse(JSON.stringify(result));
                }
                await delay(Math.max(1, Math.min(deadline - performance.now(), POLL_MS - (performance.now() - lastRequestStart))));
            }
            proof.phase_timeouts++; throw new ObserverError('phase_observation_timeout');
        });
        this.close = async () => {
            if (state === 'closed') return evidence();
            check(state === 'new' || state === 'open', 'observer_transition_in_progress');
            state = 'closing';
            if (activeHttp) activeHttp.abort(new ObserverError('observer_closing'));
            if (wake) wake();
            try { if (subscribed) await command('unsubscribe'); if (fault) throw fault; }
            finally { state = 'closed'; token = undefined; if (ws) ws.terminate(); proof.closed_at_ms = Date.now(); }
            return evidence();
        };
        this.evidence = evidence;
        Object.freeze(this);
    }
}
module.exports = {QueueLiveObserver};
