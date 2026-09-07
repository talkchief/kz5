#!/usr/bin/env node
'use strict';
// Opt-in read-only HTTP + native Blackhole smoke. Never authenticates by password,
// publishes an event, spawns a trigger, changes calls, or prints server payloads.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const http = require('node:http');
const https = require('node:https');
const ID = /^[a-f0-9]{32}$/;
const MAX_BODY = 2 * 1024 * 1024, MAX_FRAME = 65536, STEP_MS = 8000;
class SmokeError extends Error {}
function check(ok, code) { if (!ok) throw new SmokeError(code); }
function log(result, extra = {}) { process.stdout.write(JSON.stringify({result, ...extra}) + '\n'); }
function options(argv) {
    const o = {};
    const values = new Set(['account', 'queue', 'api-url', 'ws-url', 'token-file', 'token-env', 'ws-module', 'wait-event-ms']);
    for (let i = 0; i < argv.length; i++) {
        const k = argv[i].replace(/^--/, '');
        check(argv[i].startsWith('--') && !Object.hasOwn(o, k), 'invalid_cli');
        if (k === 'trust-cleartext') o[k] = true;
        else { check(values.has(k) && i + 1 < argv.length && !argv[i + 1].startsWith('--'), 'invalid_cli'); o[k] = argv[++i]; }
    }
    check(ID.test(o.account || '') && ID.test(o.queue || ''), 'explicit_scope_required');
    check(Boolean(o['token-file']) !== Boolean(o['token-env']), 'exactly_one_token_input_required');
    const wait = o['wait-event-ms'] === undefined ? 0 : Number(o['wait-event-ms']);
    check(Number.isInteger(wait) && (wait === 0 || wait >= 1000 && wait <= 60000), 'invalid_event_timeout');
    o.wait = wait;
    for (const [key, protocols] of [['api-url', ['http:', 'https:']], ['ws-url', ['ws:', 'wss:']]]) {
        let u; try { u = new URL(o[key]); } catch (_) { throw new SmokeError('invalid_endpoint'); }
        check(protocols.includes(u.protocol) && !u.username && !u.password && !u.search && !u.hash, 'unsafe_endpoint');
        const local = ['127.0.0.1', '[::1]', 'localhost'].includes(u.hostname);
        check(u.protocol === protocols[1] || local || o['trust-cleartext'] === true, 'cleartext_requires_explicit_trust');
        check(key === 'api-url' ? /^\/.*v2\/?$/.test(u.pathname) : u.pathname === '/websocket', 'invalid_endpoint_path');
        o[key] = u;
    }
    check(process.env.NODE_TLS_REJECT_UNAUTHORIZED !== '0', 'tls_verification_required');
    return o;
}
function tokenInput(o) {
    let token;
    if (o['token-env']) {
        check(/^[A-Z][A-Z0-9_]{0,127}$/.test(o['token-env']), 'invalid_token_env_name');
        token = process.env[o['token-env']];
        delete process.env[o['token-env']];
    } else {
        check(path.isAbsolute(o['token-file']), 'token_file_must_be_absolute');
        const fd = fs.openSync(o['token-file'], fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
        try {
            const s = fs.fstatSync(fd);
            check(s.isFile() && (s.uid === process.getuid() || s.uid === 0) && (s.mode & 0o777) === 0o600 && s.size > 0 && s.size <= 16385,
                'unsafe_token_file');
            const bytes = Buffer.alloc(16386), n = fs.readSync(fd, bytes, 0, bytes.length, 0);
            check(n <= 16385, 'token_file_too_large');
            token = bytes.subarray(0, n).toString('utf8').replace(/\n$/, '');
            bytes.fill(0);
        } finally { fs.closeSync(fd); }
    }
    check(typeof token === 'string' && /^[\x21-\x7e]{1,16384}$/.test(token), 'invalid_token');
    return token;
}
function exact(o, keys) { return o && !Array.isArray(o) && typeof o === 'object' && Object.keys(o).sort().join(',') === keys.slice().sort().join(','); }
function validateEvent(j, o) {
    const binding = 'queue_live.changed.' + o.queue, routing = 'acdc.dashboard.changed.' + o.account + '.' + o.queue;
    check(exact(j, ['action', 'name', 'subscribed_key', 'subscription_key', 'routing_key', 'data']) && j.action === 'event' &&
        j.name === 'changed' && j.subscribed_key === binding && j.subscription_key === routing && j.routing_key === routing &&
        exact(j.data, ['version', 'account_id', 'queue_id']) && j.data.version === 1 && j.data.account_id === o.account && j.data.queue_id === o.queue,
    'invalid_or_foreign_event');
}
function httpGet(url, token, resources) {
    return new Promise((resolve, reject) => {
        const req = (url.protocol === 'https:' ? https : http).get(url, {agent: false,
            headers: {Accept: 'application/json', ...(token ? {'X-Auth-Token': token} : {})}}, res => {
            const chunks = []; let size = 0;
            res.on('data', b => {
                size += b.length;
                if (size > MAX_BODY) req.destroy(new SmokeError('http_body_limit'));
                else chunks.push(b);
            });
            res.on('error', () => req.destroy(new SmokeError('http_response_error')));
            res.on('end', () => {
                let body; try { body = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
                catch (_) { reject(new SmokeError('http_json_required')); return; }
                resolve({status: res.statusCode, headers: res.headers, body});
            });
        });
        resources.add(req);
        const timer = setTimeout(() => req.destroy(new SmokeError('http_timeout')), STEP_MS);
        req.on('error', e => reject(e instanceof SmokeError ? e : new SmokeError('http_transport_failed')));
        req.on('close', () => { clearTimeout(timer); resources.delete(req); });
    });
}
async function main() {
    const o = options(process.argv.slice(2));
    const Ajv = require('./api-docs-tooling/node_modules/ajv');
    const {queueLiveContract} = require('./api-docs-queue-live.cjs');
    // ws supplies hard reassembled-message limits and terminate(); no install is performed.
    check(!o['ws-module'] || path.isAbsolute(o['ws-module']), 'ws_module_must_be_absolute');
    const WebSocket = require(o['ws-module'] || 'ws');
    const schemas = queueLiveContract().schemas, ajv = new Ajv({strict: false, validateFormats: false});
    const validators = ['QueueLiveEnvelope', 'QueueLiveDetailEnvelope'].map(name =>
        ajv.compile({components: {schemas}, $ref: '#/components/schemas/' + name}));
    let token = tokenInput(o), ws, stopping = false, pending, eventWait;
    const resources = new Set();
    const cleanup = () => {
        stopping = true;
        if (pending) clearTimeout(pending.timer);
        if (eventWait) clearTimeout(eventWait.timer);
        for (const r of resources) r.destroy();
        if (ws) ws.terminate();
        token = undefined;
    };
    const interrupted = () => { cleanup(); log('FAIL', {code: 'interrupted'}); process.exit(130); };
    const deadline = setTimeout(() => { cleanup(); log('FAIL', {code: 'overall_timeout'}); process.exit(1); }, 120000);
    process.once('SIGINT', interrupted); process.once('SIGTERM', interrupted);
    try {
        const base = o['api-url'].href.replace(/\/$/, '') + '/accounts/' + o.account + '/queues';
        const urls = [new URL(base + '/live?page_size=100'), new URL(base + '/' + o.queue + '/live')];
        for (const url of urls) {
            const r = await httpGet(url, undefined, resources);
            check([401, 403].includes(r.status), 'anonymous_http_not_rejected');
        }
        async function snapshot(index) {
            const r = await httpGet(urls[index], token, resources);
            check(r.status === 200 && r.body.status === 'success', 'authenticated_http_failed');
            check(r.headers['cache-control'] === 'no-store', 'no_store_missing');
            check(validators[index](r.body), 'http_schema_failed');
            const d = r.body.data;
            check(d.account_id === o.account && (index === 0 || d.queues[0].id === o.queue), 'http_scope_failed');
            check(new Set(d.queues.map(q => q.id)).size === d.queues.length, 'duplicate_queue');
            if (index === 1 && d.calls.available) {
                check(d.calls.rows.length === Math.min(200, d.calls.observed_count), 'call_count_mismatch');
                let previous; const seen = new Set();
                for (const row of d.calls.rows) {
                    check(row.queue_id === o.queue && !seen.has(row.call_id) && row.entered_at <= d.generated_at &&
                        (row.handled_at === null || row.entered_at <= row.handled_at && row.handled_at <= d.generated_at), 'call_scope_or_timeline_failed');
                    const key = [row.queue_id, row.entered_at, row.call_id];
                    check(!previous || previous[0] < key[0] || previous[0] === key[0] &&
                        (previous[1] < key[1] || previous[1] === key[1] && Buffer.compare(Buffer.from(previous[2]), Buffer.from(key[2])) < 0), 'call_order_failed');
                    previous = key; seen.add(row.call_id);
                }
            }
            return {source_status: d.source.status, source_reason: d.source.reason, websocket_capability: d.capabilities.websocket_updates};
        }
        const overview = await snapshot(0), detail = await snapshot(1);
        log('HTTP_PASS', {overview, detail});
        let fatal, subscribed = false, events = 0, bytes = 0, frames = 0;
        function fail(code) {
            fatal ||= new SmokeError(code);
            if (pending) { clearTimeout(pending.timer); pending.reject(fatal); pending = undefined; }
            if (eventWait) { clearTimeout(eventWait.timer); eventWait.reject(fatal); eventWait = undefined; }
        }
        ws = new WebSocket(o['ws-url'].href, {maxPayload: MAX_FRAME, handshakeTimeout: STEP_MS,
            perMessageDeflate: false, followRedirects: false, rejectUnauthorized: true});
        ws.on('error', () => fail('websocket_transport_failed'));
        ws.on('close', () => { if (!stopping) fail('websocket_closed'); });
        ws.on('message', (data, binary) => {
            try {
                bytes += data.length; frames++;
                check(!binary && bytes <= 1024 * 1024 && frames <= 256, 'websocket_input_limit');
                const j = JSON.parse(data.toString('utf8'));
                if (j.action === 'event') {
                    validateEvent(j, o); check(subscribed, 'event_outside_subscription'); events++;
                    if (eventWait) { clearTimeout(eventWait.timer); eventWait.resolve(); eventWait = undefined; }
                } else {
                    check(j.action === 'reply' && pending && j.request_id === pending.id && ['success', 'error'].includes(j.status), 'unexpected_reply');
                    const p = pending; pending = undefined; clearTimeout(p.timer);
                    if (p.success && j.status === 'success') subscribed = p.action === 'subscribe';
                    p.resolve(j);
                }
            } catch (e) { fail(e instanceof SmokeError ? e.message : 'invalid_websocket_json'); }
        });
        await new Promise((resolve, reject) => {
            const timer = setTimeout(() => reject(new SmokeError('websocket_open_timeout')), STEP_MS);
            ws.once('open', () => { clearTimeout(timer); resolve(); });
            ws.once('error', () => { clearTimeout(timer); reject(new SmokeError('websocket_open_failed')); });
        });
        async function command(action, binding, credential, success) {
            if (fatal) throw fatal;
            const id = 'queue-live-smoke-' + crypto.randomBytes(12).toString('hex');
            const reply = await new Promise((resolve, reject) => {
                pending = {id, action, success, resolve, reject, timer: setTimeout(() => fail('websocket_reply_timeout'), STEP_MS)};
                ws.send(JSON.stringify({action, request_id: id, ...(credential ? {auth_token: credential} : {}),
                    data: {account_id: o.account, binding}}), e => { if (e) fail('websocket_send_failed'); });
            });
            const knownErrors = ['queue_live authorization denied', 'queue_live binding unavailable',
                'queue_live authorization busy', 'rate limited', 'invalid queue_live request'];
            const knownError = Array.isArray(reply.data?.errors) &&
                knownErrors.find(value => reply.data.errors.includes(value));
            check(reply.status === (success ? 'success' : 'error'),
                success ? 'authorized_' + action + '_rejected' + (knownError ? ':' + knownError.replace(/ /g, '_') : '') :
                    (credential ? 'wildcard_subscription_accepted' : 'anonymous_subscription_accepted'));
            if (success) {
                const field = action === 'subscribe' ? 'subscribed' : 'unsubscribed';
                check(exact(reply.data, [field, 'subscriptions']) && Array.isArray(reply.data[field]) &&
                    reply.data[field].length === 1 && reply.data[field][0] === binding &&
                    Array.isArray(reply.data.subscriptions) && JSON.stringify(reply.data.subscriptions) === JSON.stringify(action === 'subscribe' ? [binding] : []),
                'subscription_ack_scope_failed');
            }
        }
        const binding = 'queue_live.changed.' + o.queue;
        await command('subscribe', binding, undefined, false);
        await command('subscribe', 'queue_live.changed.*', token, false);
        await command('subscribe', binding, token, true);
        if (o.wait) {
            const waiting = new Promise((resolve, reject) => {
                eventWait = {resolve, reject, timer: setTimeout(() => fail('invalidation_timeout'), o.wait)};
            });
            log('READY_FOR_EXTERNAL_EVENT', {wait_ms: o.wait});
            await waiting;
            await snapshot(1);
        }
        await command('unsubscribe', binding, token, true);
        subscribed = false;
        if (fatal) throw fatal;
        log('PASS', {http: 'anonymous rejection and authenticated production-schema DTOs',
            websocket: 'anonymous/wildcard rejection; exact sequential subscribe/unsubscribe ACKs',
            invalidation: o.wait ? 'closed scoped event followed by HTTP refetch' : 'not tested',
            observed_events: events, mutation_trigger: 'none; external operator only'});
    } finally {
        clearTimeout(deadline); process.removeListener('SIGINT', interrupted); process.removeListener('SIGTERM', interrupted); cleanup();
    }
}
if (require.main === module) main().catch(e => {
    // Never log arbitrary Error.message, URL, token, body, frame, stack or Ajv errors.
    log('FAIL', {code: e instanceof SmokeError ? e.message : 'local_dependency_or_io_failure'});
    process.exitCode = 1;
});
module.exports = {options, validateEvent};
