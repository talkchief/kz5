#!/usr/bin/env node
'use strict';
// LIVE ADMISSION HARD CLOSED: default native soft-delete refreshes revision
// after If-Match validation; atomic owned cleanup is not proven. Offline only.
// Proposed development fixture writes only. No service/SUP/call/roster action.
// Real user_auth tokens exercise HTTP + the existing native Blackhole socket.
// Retain BOTH users and scope policies until authentication invalidation proves
// cleanup safe: missing user/policy documents can remove native restrictions.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const http = require('node:http'), https = require('node:https'), cp = require('node:child_process');
const {baseState, MASTER} = require('./test-channel-monitor-live.cjs');
const {options: wireOptions} = require('./test-queue-live-wire.cjs');
const ID = /^[a-f0-9]{32}$/, OWNER = 'kazoo5-queue-live-isolation-v1', KEY = 'kz5_queue_live_isolation';
const ROLES = ['allowed', 'no_stats', 'no_queue', 'no_roster'];
class IsolationError extends Error {}
const need = (ok, code) => { if (!ok) throw new IsolationError(code); };
const canonical = value => Array.isArray(value) ? value.map(canonical) : value && typeof value === 'object' ?
    Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])])) : value;
const sha = value => crypto.createHash('sha256').update(JSON.stringify(canonical(value))).digest('hex');
const exact = (a, b) => JSON.stringify(canonical(a)) === JSON.stringify(canonical(b));
function policy(account, queue, role) {
    need(ID.test(account) && ID.test(queue) && ROLES.includes(role), 'invalid_policy_scope');
    const rules = {'/': ['GET'], live: ['GET'], stats: ['GET'], [queue]: ['GET'],
        [queue + '/live']: ['GET'], [queue + '/roster']: ['GET']};
    if (role === 'no_stats') delete rules.stats;
    if (role === 'no_queue') delete rules[queue];
    if (role === 'no_roster') delete rules[queue + '/roster'];
    return {queues: [{allowed_accounts: [account], rules}],
        agents: [{allowed_accounts: [account], rules: {'#': ['GET']}}],
        token_auth: [{allowed_accounts: ['_'], rules: {'/': ['GET']}}],
        _: [{allowed_accounts: ['_'], rules: {}}]};
}
function mark(ledger, kind) { return {owner: OWNER, run: ledger.run, account_id: ledger.account, kind}; }
function owned(doc, row, ledger) {
    if (!doc || doc.id !== row.id || !exact(doc[KEY], mark(ledger, row.kind))) return false;
    if (row.collection === 'users') return doc.username === row.body.username && doc.priv_level === 'user' &&
        doc.enabled === true && exact(doc.scope_restrictions, row.body.scope_restrictions) &&
        (!doc.queues || exact(doc.queues, [])) && !doc.call_forward?.enabled;
    if (row.collection === 'scope_restrictions') return exact(doc.scopes, []) &&
        exact(doc.token_restrictions, row.body.token_restrictions);
    return row.collection === 'queues' && doc.name === row.body.name &&
        doc.enter_when_empty === false && (!doc.agents || exact(doc.agents, [])) && doc.callback?.enabled === false;
}
function tokenClaims(token, account, owner, scope) {
    need(typeof token === 'string' && /^[\x21-\x7e]{1,16384}$/.test(token), 'invalid_login_token');
    const pieces = token.split('.');
    need(pieces.length === 3 && pieces.every(p => /^[A-Za-z0-9_-]+$/.test(p)), 'signed_jwt_required');
    let claims; try { claims = JSON.parse(Buffer.from(pieces[1], 'base64url').toString('utf8')); }
    catch (_) { throw new IsolationError('invalid_jwt_claims'); }
    // Decoding is only a consistency check; real /token_auth below verifies it.
    need(claims.account_id === account && claims.owner_id === owner && claims.method === 'cb_user_auth' &&
        claims.scope === scope && Number.isInteger(claims.exp) && claims.exp > 0, 'unexpected_jwt_identity_or_expiry');
    return claims;
}
function checkReply(reply, binding, allowed, action = 'subscribe') {
    if (!allowed) {
        need(reply.status === 'error' && exact(reply.data, {errors: ['queue_live authorization denied']}),
            'policy_denial_not_proven');
    } else {
        const field = action === 'subscribe' ? 'subscribed' : 'unsubscribed';
        need(reply.status === 'success' && exact(reply.data?.[field], [binding]) &&
            exact(reply.data?.subscriptions, action === 'subscribe' ? [binding] : []), 'exact_subscription_ack_required');
    }
}
function checkHttpDenial(result) {
    need(result.status === 403 && result.body?.status === 'error' && exact(result.body.data, {}),
        'policy_http_denial_not_proven');
}
function protectedRead(file, max = 32768) {
    need(path.isAbsolute(file) && fs.realpathSync(path.dirname(file)) === path.dirname(file), 'unsafe_private_path');
    const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
    try {
        const st = fs.fstatSync(fd);
        need(st.isFile() && st.uid === 0 && (st.mode & 511) === 384 && st.nlink === 1 && st.size > 0 && st.size <= max,
            'unsafe_private_file');
        return fs.readFileSync(fd, 'utf8');
    } finally { fs.closeSync(fd); }
}
function validateLedger(l) {
    need(l && l.version === 1 && l.owner === OWNER && ID.test(l.run) && ID.test(l.account) && l.account !== MASTER &&
        ID.test(l.positive_queue) && ID.test(l.denied_queue) && l.positive_queue !== l.denied_queue &&
        ID.test(l.foreign_account) && l.foreign_account !== l.account && ID.test(l.foreign_queue) &&
        /^acceptance-[a-f0-9]{12}\.invalid$/.test(l.realm) && Array.isArray(l.resources) && l.resources.length <= 9 &&
        Array.isArray(l.checks) && l.checks.length <= 64 && ['preparing', 'testing', 'retained', 'cleaned'].includes(l.phase),
    'invalid_ledger');
    const seen = new Set();
    for (const row of l.resources) {
        need(row && ['users', 'scope_restrictions', 'queues'].includes(row.collection) &&
            typeof row.kind === 'string' && row.body && exact(row.body[KEY], mark(l, row.kind)) &&
            ['create_pending', 'created', 'delete_pending', 'deleted'].includes(row.state) &&
            (!row.id || (row.collection === 'scope_restrictions' ? /^api:queue-live-[a-f0-9]{32}-(allowed|no_stats|no_queue|no_roster)$/.test(row.id) : ID.test(row.id))),
        'invalid_owned_row');
        need(!seen.has(row.kind), 'duplicate_owned_kind'); seen.add(row.kind);
        if (row.collection === 'scope_restrictions') {
            const role = row.kind.replace(/^policy:/, '');
            need(row.id === `api:queue-live-${l.run}-${role}` && exact(row.body.scopes, []) &&
                exact(row.body.token_restrictions, policy(l.account, l.positive_queue, role)), 'policy_ledger_drift');
        } else if (row.collection === 'users') {
            const role = row.kind.replace(/^user:/, '');
            need(ROLES.includes(role) && row.body.username === `queue-live-${l.run}-${role}` &&
                row.body.priv_level === 'user' && row.body.enabled === true &&
                exact(row.body.scope_restrictions, [`api:queue-live-${l.run}-${role}`]), 'user_ledger_drift');
        } else need(row.kind === 'denied_queue' && row.id === l.denied_queue && row.body.enter_when_empty === false &&
            exact(row.body.agents, []) && exact(row.body.callback, {enabled: false}), 'queue_ledger_drift');
        if (row.token) tokenClaims(row.token, l.account, row.id, row.body.scope_restrictions[0]);
    }
    return l;
}
function options(argv) {
    const o = {}, flags = ['allow-fixture-writes', 'create-owned-denied-queue'];
    const values = ['mode', 'run-dir', 'admin-token-file', 'acceptance-file', 'api-url', 'ws-url', 'ws-module',
        'denied-queue', 'foreign-account', 'foreign-queue'];
    for (let i = 0; i < argv.length; i++) {
        const key = argv[i].slice(2);
        need(argv[i].startsWith('--') && !Object.hasOwn(o, key), 'invalid_cli');
        if (flags.includes(key)) o[key] = true;
        else { need(values.includes(key) && argv[i + 1] && !argv[i + 1].startsWith('--'), 'invalid_cli'); o[key] = argv[++i]; }
    }
    need(o['allow-fixture-writes'] && ['run', 'cleanup'].includes(o.mode) && path.isAbsolute(o['run-dir'] || '') &&
        path.isAbsolute(o['admin-token-file'] || '') && path.isAbsolute(o['acceptance-file'] || ''), 'explicit_arming_required');
    if (o.mode === 'run') need(Boolean(o['denied-queue']) !== Boolean(o['create-owned-denied-queue']) &&
        (!o['denied-queue'] || ID.test(o['denied-queue'])) && ID.test(o['foreign-account'] || '') && ID.test(o['foreign-queue'] || ''),
    'explicit_negative_scopes_required');
    return o;
}
function ledgerWriter(dir) {
    const st = fs.lstatSync(dir);
    need(st.isDirectory() && !st.isSymbolicLink() && st.uid === 0 && (st.mode & 511) === 448 &&
        fs.realpathSync(dir) === dir && /^\/var\/log\/kazoo-queue-live-isolation-[A-Za-z0-9]+$/.test(dir), 'unsafe_run_directory');
    const file = path.join(dir, 'ledger.json');
    return {file, save(l) {
        if (fs.existsSync(file)) protectedRead(file, 1024 * 1024);
        const next = file + '.next', fd = fs.openSync(next, 'wx', 384);
        try { fs.writeFileSync(fd, JSON.stringify(l, null, 2) + '\n'); fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
        fs.renameSync(next, file);
        const d = fs.openSync(dir, 'r'); try { fs.fsyncSync(d); } finally { fs.closeSync(d); }
    }};
}
async function lockFixture() {
    const file = '/etc/kazoo/monitor-acceptance.lock';
    const fd = fs.openSync(file, fs.constants.O_RDWR | fs.constants.O_NOFOLLOW), st = fs.fstatSync(fd);
    need(st.isFile() && st.uid === 0 && !(st.mode & 18) && st.nlink === 1, 'unsafe_shared_lock');
    const child = cp.spawn('/usr/bin/flock', ['-n', '3', process.execPath, '-e',
        'process.stdout.write("LOCKED\\n");process.stdin.resume();'], {stdio: ['pipe', 'pipe', 'ignore', fd],
        env: {PATH: '/usr/bin:/bin', LANG: 'C'}});
    fs.closeSync(fd);
    try {
        await new Promise((resolve, reject) => {
            let text = ''; const timer = setTimeout(() => reject(new IsolationError('shared_lock_timeout')), 3000);
            child.once('error', () => { clearTimeout(timer); reject(new IsolationError('shared_lock_failed')); });
            child.once('exit', () => { clearTimeout(timer); reject(new IsolationError('shared_lock_busy')); });
            child.stdout.on('data', data => { text += data; if (text === 'LOCKED\n') { clearTimeout(timer); resolve(); }
                else if (text.length > 32) { clearTimeout(timer); reject(new IsolationError('shared_lock_protocol')); } });
        });
        return {alive: () => child.exitCode === null && child.signalCode === null,
            close: () => { child.stdin.end(); child.kill('SIGTERM'); }};
    } catch (e) { child.kill('SIGTERM'); throw e; }
}
function transport(api, websocket, wsPath, lock) {
    const resources = new Set(); let closed = false;
    const check = () => need(!closed && lock.alive(), 'acceptance_session_stopped');
    return {close() { closed = true; for (const item of resources) item.destroy ? item.destroy() : item.terminate(); },
        async request(method, route, body, token, revision) {
            check(); const url = new URL(api.href.replace(/\/$/, '') + '/' + route);
            need(url.origin === api.origin, 'request_origin_changed');
            const data = body === undefined ? undefined : Buffer.from(JSON.stringify({data: body}));
            return new Promise((resolve, reject) => {
                const req = (api.protocol === 'https:' ? https : http).request(url, {method, agent: false, headers: {
                    Accept: 'application/json', ...(token ? {'X-Auth-Token': token} : {}),
                    ...(revision ? {'If-Match': '"' + revision + '"'} : {}),
                    ...(data ? {'Content-Type': 'application/json', 'Content-Length': data.length} : {})}}, res => {
                    const chunks = []; let bytes = 0;
                    res.on('data', part => { bytes += part.length; if (bytes > 2 * 1024 * 1024) req.destroy(); else chunks.push(part); });
                    res.on('error', () => req.destroy());
                    res.on('end', () => { try { check(); resolve({status: res.statusCode, headers: res.headers,
                        body: JSON.parse(Buffer.concat(chunks).toString('utf8'))}); } catch (_) { reject(new IsolationError('http_result_unavailable')); } });
                });
                resources.add(req); const timer = setTimeout(() => req.destroy(), 8000);
                req.on('error', () => reject(new IsolationError('http_transport_failed')));
                req.on('close', () => { resources.delete(req); clearTimeout(timer); });
                req.end(data);
            });
        },
        async socket(account, queue, token, allowed) {
            check(); const WebSocket = require(wsPath), ws = new WebSocket(websocket.href, {maxPayload: 65536,
                handshakeTimeout: 8000, perMessageDeflate: false, followRedirects: false, rejectUnauthorized: true});
            resources.add(ws); let pending, bytes = 0, frames = 0, fatal;
            const failure = code => { fatal = new IsolationError(code); if (pending) pending.reject(fatal); };
            ws.on('error', () => failure('websocket_transport_failed'));
            ws.on('close', () => { if (pending) failure('websocket_closed'); });
            ws.on('message', (data, binary) => {
                try {
                    need(!binary && ++frames <= 32 && (bytes += data.length) <= 262144, 'websocket_bound');
                    const j = JSON.parse(data.toString('utf8'));
                    // No event trigger in this harness. An allowed socket may
                    // receive naturally occurring hints, but never foreign data.
                    if (j.action === 'event') {
                        require('./test-queue-live-wire.cjs').validateEvent(j, {account, queue});
                        need(allowed, 'event_after_denial'); return;
                    }
                    need(pending && j.action === 'reply' && j.request_id === pending.id, 'uncorrelated_reply');
                    const p = pending; pending = undefined; p.resolve(j);
                } catch (_) { failure('invalid_or_foreign_websocket_frame'); }
            });
            try {
                await new Promise((resolve, reject) => {
                    const timer = setTimeout(() => reject(new IsolationError('websocket_open_timeout')), 8000);
                    ws.once('open', () => { clearTimeout(timer); resolve(); });
                    ws.once('error', () => { clearTimeout(timer); reject(new IsolationError('websocket_open_failed')); });
                });
                const binding = 'queue_live.changed.' + queue;
                async function command(action) {
                    check(); if (fatal) throw fatal;
                    const id = crypto.randomBytes(16).toString('hex');
                    return new Promise((resolve, reject) => {
                        const timer = setTimeout(() => reject(new IsolationError('websocket_reply_timeout')), 8000);
                        pending = {id, resolve: j => { clearTimeout(timer); resolve(j); }, reject: e => { clearTimeout(timer); reject(e); }};
                        ws.send(JSON.stringify({action, request_id: id, auth_token: token, data: {account_id: account, binding}}),
                            e => { if (e) failure('websocket_send_failed'); });
                    });
                }
                const reply = await command('subscribe');
                checkReply(reply, binding, allowed);
                if (allowed) {
                    const ended = await command('unsubscribe');
                    checkReply(ended, binding, true, 'unsubscribe');
                }
                if (fatal) throw fatal;
            } finally { pending = undefined; resources.delete(ws); ws.terminate(); }
        }
    };
}
const route = (l, collection, id = '') => `accounts/${l.account}/${collection}${id ? '/' + encodeURIComponent(id) : ''}`;
const success = r => { need([200, 201].includes(r.status) && r.body?.status === 'success', 'api_success_required'); return r.body.data; };
function document(result, collection) {
    const data = success(result);
    // The native selected scope endpoint returns a bounded exact-key view,
    // unlike users/queues' single-document GET. Do not assume an object.
    if (collection !== 'scope_restrictions') return data;
    need(Array.isArray(data) && data.length === 1 && !result.body.next_start_key, 'scope_readback_not_unique');
    return data[0];
}
function revision(result) {
    const value = result.body?.revision;
    need(typeof value === 'string' && /^[1-9][0-9]*-[a-f0-9]{32}$/.test(value), 'strong_revision_required');
    return value;
}
async function create(io, save, l, row, admin) {
    if (row.id) {
        const prior = await io.request('GET', route(l, row.collection, row.id), undefined, admin);
        need(row.collection === 'scope_restrictions' ? prior.status === 200 && prior.body?.status === 'success' &&
            exact(prior.body.data, []) && !prior.body.next_start_key : prior.status === 404 && prior.body?.status === 'error',
        'owned_create_target_not_virgin');
    }
    row.state = 'create_pending'; l.resources.push(row); save(l); // Before ANY request.
    const result = await io.request('PUT', route(l, row.collection), row.body, admin);
    const data = success(result);
    need(typeof data?.id === 'string' && (!row.id || row.id === data.id), 'created_identity_unknown');
    row.id = data.id; save(l); // Retain returned ID even if subsequent checks fail.
    need(owned(data, row, l), 'created_ownership_mismatch');
    row.revision = revision(result); save(l);
    const read = document(await io.request('GET', route(l, row.collection, row.id), undefined, admin), row.collection);
    need(owned(read, row, l), 'created_readback_mismatch');
    row.state = 'created'; row.public_hash = sha(read); save(l);
}
async function setup(io, save, l, admin, createDenied) {
    if (createDenied) await create(io, save, l, {collection: 'queues', kind: 'denied_queue', id: l.denied_queue,
        body: {id: l.denied_queue, name: 'Queue live isolation ' + l.run, agents: [], enter_when_empty: false,
            callback: {enabled: false}, [KEY]: mark(l, 'denied_queue')}}, admin);
    for (const role of ROLES) {
        const scope = `api:queue-live-${l.run}-${role}`;
        await create(io, save, l, {collection: 'scope_restrictions', kind: 'policy:' + role, id: scope,
            body: {id: scope, scopes: [], token_restrictions: policy(l.account, l.positive_queue, role),
                [KEY]: mark(l, 'policy:' + role)}}, admin);
        const row = {collection: 'users', kind: 'user:' + role, body: {first_name: 'Queue live isolation', last_name: role,
            username: `queue-live-${l.run}-${role}`, password: crypto.randomBytes(24).toString('hex'),
            enabled: true, priv_level: 'user', scope_restrictions: [scope], [KEY]: mark(l, 'user:' + role)}};
        await create(io, save, l, row, admin);
        row.login = 'pending'; save(l);
        const logged = await io.request('PUT', 'user_auth', {credentials: crypto.createHash('md5').update(
            row.body.username + ':' + row.body.password).digest('hex'), method: 'md5', realm: l.realm}, undefined);
        const data = success(logged);
        need(data.account_id === l.account && data.owner_id === row.id, 'login_identity_mismatch');
        row.token = logged.body.auth_token; save(l);
        const claims = tokenClaims(row.token, l.account, row.id, scope);
        const identity = success(await io.request('GET', 'token_auth', undefined, row.token));
        need(identity.account_id === l.account && identity.owner_id === row.id && identity.scope === scope &&
            identity.exp === claims.exp, 'real_token_validation_failed');
        const fresh = await io.request('GET', route(l, 'users', row.id), undefined, admin);
        const doc = document(fresh, 'users'); need(owned(doc, row, l), 'post_login_user_drift');
        row.revision = revision(fresh); row.public_hash = sha(doc);
        row.expires = claims.exp; row.login = 'verified'; save(l);
    }
}
async function matrix(io, save, l) {
    l.phase = 'testing'; save(l);
    const token = role => l.resources.find(r => r.kind === 'user:' + role).token;
    async function httpCase(name, account, queue, role, expected, query = '') {
        const p = `accounts/${account}/queues/${queue ? queue + '/' : ''}live${query}`;
        const r = await io.request('GET', p, undefined, token(role));
        need(r.status === expected, 'unexpected_http_authorization');
        if (expected === 200) {
            const d = success(r);
            need(d.account_id === account && Array.isArray(d.queues) && d.queues.length === 1 &&
                d.queues[0].id === queue && r.headers['cache-control'] === 'no-store', 'positive_scope_mismatch');
        } else checkHttpDenial(r);
        l.checks.push(name); save(l);
    }
    async function wsCase(name, account, queue, role, allowed) {
        await io.socket(account, queue, token(role), allowed); l.checks.push(name); save(l);
    }
    await httpCase('allowed_detail_before', l.account, l.positive_queue, 'allowed', 200);
    await wsCase('allowed_subscribe_before', l.account, l.positive_queue, 'allowed', true);
    await httpCase('same_account_other_queue_denied', l.account, l.denied_queue, 'allowed', 403);
    await wsCase('same_account_other_binding_denied', l.account, l.denied_queue, 'allowed', false);
    await httpCase('foreign_overview_denied', l.foreign_account, undefined, 'allowed', 403);
    await httpCase('foreign_detail_denied', l.foreign_account, l.foreign_queue, 'allowed', 403);
    await wsCase('foreign_binding_denied', l.foreign_account, l.foreign_queue, 'allowed', false);
    await wsCase('same_binding_foreign_account_denied', l.foreign_account, l.positive_queue, 'allowed', false);
    await httpCase('denied_cursor_denied', l.account, undefined, 'allowed', 403,
        '?page_size=1&start_queue_id=' + l.denied_queue);
    for (const role of ['no_stats', 'no_queue']) {
        await httpCase(role + '_detail_denied', l.account, l.positive_queue, role, 403);
        await wsCase(role + '_binding_denied', l.account, l.positive_queue, role, false);
    }
    await httpCase('no_roster_detail_denied', l.account, l.positive_queue, 'no_roster', 403);
    await wsCase('no_roster_hint_allowed', l.account, l.positive_queue, 'no_roster', true);
    await httpCase('allowed_detail_after', l.account, l.positive_queue, 'allowed', 200);
    await wsCase('allowed_subscribe_after', l.account, l.positive_queue, 'allowed', true);
    l.matrix_passed = true; l.phase = 'retained'; save(l);
}
async function cleanup(io, save, l, admin, now = Math.floor(Date.now() / 1000)) {
    validateLedger(l);
    need(l.resources.every(r => ['created', 'deleted'].includes(r.state)) &&
        l.resources.filter(r => r.collection === 'users').every(r => r.login === 'verified'), 'ambiguous_write_or_login_retain');
    // BEFORE deleting either the owner or scope: prove all issued tokens can
    // no longer authenticate. A 403/busy response is NOT invalidation proof.
    for (const row of l.resources.filter(r => r.collection === 'users')) {
        need(Number.isInteger(row.expires) && now > row.expires + 60, 'token_expiry_pending_retain');
        const r = await io.request('GET', 'token_auth', undefined, row.token);
        need(r.status === 401 && r.body?.status === 'error', 'token_invalidation_unproven_retain');
    }
    const ordered = ['users', 'queues', 'scope_restrictions'].flatMap(c => l.resources.filter(r => r.collection === c));
    for (const row of ordered) {
        if (row.state === 'deleted') continue;
        const d = document(await io.request('GET', route(l, row.collection, row.id), undefined, admin), row.collection);
        need(owned(d, row, l) && sha(d) === row.public_hash && /^[1-9][0-9]*-[a-f0-9]{32}$/.test(row.revision || ''),
            'cleanup_ownership_drift_retain');
        if (row.collection === 'queues') {
            const roster = success(await io.request('GET', route(l, 'queues', row.id) + '/roster', undefined, admin));
            need(Array.isArray(roster) && roster.length === 0, 'owned_queue_not_empty_retain');
        }
        row.state = 'delete_pending'; save(l);
        success(await io.request('DELETE', route(l, row.collection, row.id), undefined, admin, row.revision));
        const absent = await io.request('GET', route(l, row.collection, row.id), undefined, admin);
        need(row.collection === 'scope_restrictions' ? absent.status === 200 && absent.body?.status === 'success' &&
            exact(absent.body.data, []) && !absent.body.next_start_key : absent.status === 404 && absent.body?.status === 'error',
        'delete_not_verified_retain');
        row.state = 'deleted'; save(l);
    }
    l.phase = 'cleaned'; save(l);
}
async function main(argv) {
    // Both run AND cleanup are closed before option handling, secret/ledger
    // reads, lock acquisition, file writes or HTTP. No flag/environment bypass.
    // Offline exported functions model intent only, not native atomic deletion.
    need(false, 'live_admission_closed_cleanup_not_atomic');
    const o = options(argv);
    need(process.getuid() === 0 && !process.env.NODE_OPTIONS && !process.env.NODE_PATH &&
        process.env.NODE_TLS_REJECT_UNAUTHORIZED !== '0', 'clean_root_environment_required');
    const writer = ledgerWriter(o['run-dir']);
    const state = baseState(protectedRead(o['acceptance-file']));
    let l;
    if (o.mode === 'cleanup') l = validateLedger(JSON.parse(protectedRead(writer.file, 1024 * 1024)));
    else {
        need(!fs.existsSync(writer.file) && !fs.existsSync(writer.file + '.next'), 'existing_ledger_no_retry');
        l = {version: 1, owner: OWNER, run: crypto.randomBytes(16).toString('hex'), account: state.ACCEPTANCE_ACCOUNT_ID,
            realm: state.ACCEPTANCE_REALM, positive_queue: state.ACCEPTANCE_QUEUE_ID,
            denied_queue: o['denied-queue'] || crypto.randomBytes(16).toString('hex'), foreign_account: o['foreign-account'],
            foreign_queue: o['foreign-queue'], resources: [], checks: [], phase: 'preparing', matrix_passed: false};
        validateLedger(l);
    }
    need(l.account === state.ACCEPTANCE_ACCOUNT_ID && l.realm === state.ACCEPTANCE_REALM &&
        l.positive_queue === state.ACCEPTANCE_QUEUE_ID, 'acceptance_ledger_mismatch');
    const common = wireOptions(['--account', l.account, '--queue', l.positive_queue, '--api-url', o['api-url'],
        '--ws-url', o['ws-url'], '--token-file', o['admin-token-file'], '--ws-module', o['ws-module']]);
    need(path.isAbsolute(o['ws-module'] || ''), 'explicit_existing_ws_module_required');
    const admin = protectedRead(o['admin-token-file'], 16385).replace(/\n$/, '');
    need(/^[\x21-\x7e]{1,16384}$/.test(admin), 'invalid_admin_token');
    const lock = await lockFixture(), io = transport(common['api-url'], common['ws-url'], o['ws-module'], lock);
    const timer = setTimeout(() => io.close(), 180000);
    const interrupted = () => io.close(); process.once('SIGINT', interrupted); process.once('SIGTERM', interrupted);
    try {
        const account = success(await io.request('GET', 'accounts/' + l.account, undefined, admin));
        need(account.id === l.account && account.name === state.ACCEPTANCE_ACCOUNT_NAME && account.realm === l.realm &&
            !account.is_superduper_admin, 'acceptance_account_drift');
        if (o.mode === 'cleanup') await cleanup(io, writer.save, l, admin);
        else {
            for (const [a, q] of [[l.account, l.positive_queue], [l.foreign_account, l.foreign_queue]]) {
                const d = success(await io.request('GET', `accounts/${a}/queues/${q}`, undefined, admin));
                need(d.id === q, 'existing_queue_preflight_failed');
            }
            if (!o['create-owned-denied-queue']) {
                const d = success(await io.request('GET', route(l, 'queues', l.denied_queue), undefined, admin));
                need(d.id === l.denied_queue, 'existing_denied_queue_missing');
            }
            writer.save(l);
            await setup(io, writer.save, l, admin, o['create-owned-denied-queue']);
            await matrix(io, writer.save, l);
            // Do NOT delete users/policies immediately; signed JWTs remain live.
        }
        console.log(JSON.stringify({result: o.mode === 'cleanup' ? 'CLEANED' : 'MATRIX_PASS_FIXTURE_RETAINED',
            checks: l.checks.length, ledger: writer.file, fixture_retained: l.phase !== 'cleaned',
            expiry_cleanup_after: Math.max(0, ...l.resources.map(r => r.expires || 0)) + 61,
            delivery_or_revocation_proven: false}));
    } catch (error) {
        if (fs.existsSync(writer.file)) { l.phase = 'retained'; writer.save(l); }
        throw error;
    } finally {
        clearTimeout(timer); process.removeListener('SIGINT', interrupted); process.removeListener('SIGTERM', interrupted);
        io.close(); lock.close();
    }
}
module.exports = {policy, mark, owned, tokenClaims, checkReply, checkHttpDenial, validateLedger, options, document, revision,
    create, setup, matrix, cleanup, OWNER, KEY};
if (require.main === module) main(process.argv.slice(2)).catch(e => {
    console.error(JSON.stringify({result: 'FAIL_RETAIN', code: e instanceof IsolationError ? e.message : 'local_or_transport_failure'}));
    process.exitCode = 1;
});
