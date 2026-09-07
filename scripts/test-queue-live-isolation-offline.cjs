#!/usr/bin/env node
'use strict';
// No HTTP, WebSocket, secret-file reads, services or API fixture provisioning.
// A real flock regression uses only a private temporary directory and children.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path');
const crypto = require('node:crypto');
const cp = require('node:child_process');
const {EventEmitter} = require('node:events');
const h = require('./test-queue-live-isolation.cjs');
const sourcePath = path.join(__dirname, 'test-queue-live-isolation.cjs'), before = fs.readFileSync(sourcePath);
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const clone = x => JSON.parse(JSON.stringify(x)), A = 'a'.repeat(32), Q = 'b'.repeat(32), D = 'c'.repeat(32), F = 'd'.repeat(32);
const REV = '1-' + 'e'.repeat(32), NOW = 1800000000;
let groups = 0, checks = 0;
const test = async (name, f) => { await f(); groups++; console.log('PASS ' + name); };
const rejects = async (f, text) => { checks++; await assert.rejects(f, new RegExp(text)); };
const throws = (f, text) => { checks++; assert.throws(f, new RegExp(text)); };
function httpDenial(kind = 'resource') {
    return {status: 403, body: {status: 'error', error: '403',
        message: kind === 'resource' ? 'queue_live_resource_forbidden' : 'forbidden',
        data: kind === 'resource' ? {} : kind === 'hierarchy' ? {message: 'forbidden'} :
            {cause: 'access denied by token restrictions', message: 'forbidden'}}};
}
function ledger(generated = false) { return {version: 1, owner: h.OWNER, run: '1'.repeat(32), account: A, realm: 'acceptance-123456abcdef.invalid',
    positive_queue: Q, denied_queue: generated ? undefined : D, denied_queue_source: generated ? 'generated' : 'existing',
    foreign_account: F, foreign_queue: 'f'.repeat(32),
    resources: [], checks: [], phase: 'preparing', matrix_passed: false}; }
function jwt(account, owner, scope, exp = NOW + 3600) {
    return [Buffer.from('{}').toString('base64url'), Buffer.from(JSON.stringify({account_id: account, owner_id: owner,
        scope, method: 'cb_user_auth', exp})).toString('base64url'), 'c2lnbmVk'].join('.');
}
function double(l) {
    const docs = new Map(), trace = [], saves = []; let expiry = false;
    const save = value => { saves.push(clone(value)); };
    const success = data => ({status: 200, headers: {'cache-control': 'no-store'}, body: {status: 'success', data, revision: REV}});
    const io = {expire() { expiry = true; }, docs, trace, saves, save,
        async socket(account, queue, token, allowed) { trace.push({method: 'WS', account, queue, allowed}); },
        async request(method, route, body, token, revision) {
            trace.push({method, route, revision});
            if (route === 'user_auth') {
                assert.equal(token, undefined);
                const row = l.resources.find(r => r.collection === 'users' && crypto.createHash('md5').update(
                    r.body.username + ':' + r.body.password).digest('hex') === body.credentials);
                assert(row && row.login === 'pending');
                assert.equal(saves.at(-1).resources.find(r => r.kind === row.kind).login, 'pending');
                const response = success({account_id: A, owner_id: row.id});
                response.body.auth_token = jwt(A, row.id, row.body.scope_restrictions[0]); return response;
            }
            if (route === 'token_auth') return expiry ? {status: 401, body: {status: 'error'}} :
                success(JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString()));
            const parsed = new URL(route, 'http://offline.invalid/');
            const parts = parsed.pathname.slice(1).split('/'), collection = parts[2], id = decodeURIComponent(parts[3] || '');
            if (method === 'PUT') {
                assert.equal(parsed.search, collection === 'users' ? '?send_email_on_creation=false' : '');
                assert.equal(token, 'setup-only');
                const row = l.resources.at(-1);
                assert.equal(row.state, 'create_pending');
                assert.equal(saves.at(-1).resources.at(-1).state, 'create_pending');
                assert.deepEqual(saves.at(-1).resources.at(-1).body, body);
                if (collection === 'queues') {
                    assert.equal(body.id, undefined); assert.equal(row.id, undefined);
                    assert.equal(saves.at(-1).denied_queue, undefined);
                }
                const created = {...clone(body), id: collection === 'queues' ? 'e'.repeat(32) : body.id || hash(row.kind).slice(0, 32)}; delete created.password;
                docs.set(collection + '/' + created.id, created); return success(created);
            }
            if (method === 'DELETE') {
                assert.equal(token, 'setup-only'); assert.equal(revision, REV);
                assert.equal(saves.at(-1).resources.find(r => r.id === id).state, 'delete_pending');
                assert(docs.delete(collection + '/' + id)); return success({id});
            }
            assert.equal(method, 'GET');
            if (parts[4] === 'roster') return success([]);
            const doc = docs.get(collection + '/' + id);
            if (collection === 'scope_restrictions') return success(doc ? [clone(doc)] : []);
            return doc ? success(clone(doc)) : {status: 404, body: {status: 'error'}};
        }};
    return io;
}
function httpDouble(mode = 'success', status = 200, raw = Buffer.from('{"status":"success","data":{}}')) {
    const calls = [], timers = new Map(); let nextTimer = 0;
    const seams = {
        setTimeout(fn, ms) { assert.equal(ms, 8000); timers.set(++nextTimer, fn); return nextTimer; },
        clearTimeout(id) { timers.delete(id); },
        request(url, options, callback) {
            const req = new EventEmitter(), record = {url, options, destroyed: 0}; calls.push(record);
            // Deliberately emit no error/close on destroy: cancellation must
            // settle on its own, not rely on an incidental Node event.
            req.destroy = () => { record.destroyed++; };
            req.end = data => {
                record.data = data;
                queueMicrotask(() => {
                    if (mode === 'stall') return;
                    if (mode === 'request_close') { req.emit('close'); return; }
                    if (mode === 'request_error') { req.emit('error', Error('private-error-sentinel')); return; }
                    const res = new EventEmitter(); res.statusCode = status; res.headers = {'cache-control': 'no-store'};
                    callback(res);
                    if (mode === 'response_close') { res.emit('close'); return; }
                    if (mode === 'aborted') { res.emit('aborted'); return; }
                    if (mode === 'response_error') { res.emit('error', Error('private-error-sentinel')); return; }
                    if (raw.length) res.emit('data', raw);
                    res.emit('end'); res.emit('close'); req.emit('close');
                    // Duplicate late events must neither resettle nor recurse.
                    req.emit('error', Error('private-late-error-sentinel'));
                });
            };
            return req;
        }
    };
    return {seams, calls, timers, fire() { for (const fn of [...timers.values()]) fn(); }};
}
const httpTransport = (d, lock = {alive: () => true}) => h.transport(new URL('http://127.0.0.1:8000/v2'),
    new URL('ws://127.0.0.1:5555/websocket'), '/unused-offline-ws', lock, d.seams);
async function within(promise) {
    let timer;
    try { return await Promise.race([promise, new Promise((_, reject) => {
        timer = setTimeout(() => reject(Error('offline-http-promise-never-settled')), 1500);
    })]); } finally { clearTimeout(timer); }
}
(async () => {
    await test('explicit arming and negative scope options', () => {
        const base = ['--mode', 'run', '--allow-fixture-writes', '--run-dir', '/private/run', '--admin-token-file', '/private/token',
            '--acceptance-file', '/private/acceptance', '--foreign-account', F, '--foreign-queue', Q, '--create-owned-denied-queue'];
        assert.equal(h.options(base).mode, 'run');
        throws(() => h.options(base.filter(x => x !== '--allow-fixture-writes')), 'arming');
        throws(() => h.options([...base, '--denied-queue', D]), 'negative_scopes');
        throws(() => h.options([...base, '--mode', 'cleanup']), 'invalid_cli');
        throws(() => h.options([...base, '--unknown']), 'invalid_cli');
    });
    await test('closed exact per-user rules and independent missing capabilities', () => {
        const allowed = h.policy(A, Q, 'allowed');
        assert.deepEqual(allowed.queues[0].allowed_accounts, [A]);
        assert.deepEqual(allowed._[0].rules, {});
        assert.equal(allowed.queues[0].rules[D], undefined);
        assert.deepEqual(allowed.queues[0].rules[Q + '/live'], ['GET']);
        for (const [role, key] of [['no_stats', 'stats'], ['no_queue', Q], ['no_roster', Q + '/roster']]) {
            assert.equal(h.policy(A, Q, role).queues[0].rules[key], undefined);
        }
        throws(() => h.policy(A, Q, 'admin'), 'invalid_policy');
    });
    await test('JWT claim checks are identity checks, not fake cryptographic proof', () => {
        const scope = 'api:fixture'; assert.equal(h.tokenClaims(jwt(A, Q, scope), A, Q, scope).exp, NOW + 3600);
        throws(() => h.tokenClaims(jwt(F, Q, scope), A, Q, scope), 'identity');
        throws(() => h.tokenClaims(jwt(A, D, scope), A, Q, scope), 'identity');
        throws(() => h.tokenClaims(jwt(A, Q, 'other'), A, Q, scope), 'identity');
        throws(() => h.tokenClaims(jwt(A, Q, scope, null), A, Q, scope), 'identity');
        throws(() => h.tokenClaims('legacy-document-token', A, Q, scope), 'signed_jwt');
    });
    await test('negative ACK must be policy denial, never infrastructure error', () => {
        const binding = 'queue_live.changed.' + Q;
        h.checkReply({status: 'error', data: {errors: ['queue_live authorization denied']}}, binding, false);
        for (const error of ['queue_live binding unavailable', 'queue_live authorization busy', 'rate limited']) {
            throws(() => h.checkReply({status: 'error', data: {errors: [error]}}, binding, false), 'denial_not_proven');
        }
        throws(() => h.checkReply({status: 'success', data: {}}, binding, false), 'denial_not_proven');
        h.checkReply({status: 'success', data: {subscribed: [binding], subscriptions: [binding]}}, binding, true);
        throws(() => h.checkReply({status: 'success', data: {subscribed: [binding], subscriptions: ['foreign']}}, binding, true), 'ack_required');
    });
    await test('WS denial rejects sentinel data and hidden subscription payloads', () => {
        const binding = 'queue_live.changed.' + Q;
        for (const extra of [{sentinel: 'must-not-leak'}, {subscriptions: [binding]}, {subscribed: [binding]},
            {routing_key: 'acdc.dashboard.changed.' + A + '.' + Q}, {payload: {count: 1}}]) {
            throws(() => h.checkReply({status: 'error', data: {errors: ['queue_live authorization denied'], ...extra}},
                binding, false), 'denial_not_proven');
        }
    });
    await test('HTTP403 requires exactly empty native data, never a sentinel payload', () => {
        h.checkHttpDenial(httpDenial());
        for (const data of [undefined, null, [], {sentinel: 'must-not-leak'}, {subscriptions: [Q]},
            {queues: []}, {calls: null}, {agents: null}, {metrics: {current_waiting: 1}}]) {
            const response = httpDenial(); response.body.data = data;
            throws(() => h.checkHttpDenial(response), 'denial_not_proven');
        }
    });
    await test('HTTP denial shapes are exact and scoped to their native authorization stage', () => {
        h.checkHttpDenial(httpDenial('token'), 'token');
        h.checkHttpDenial(httpDenial('token'), 'foreign');
        h.checkHttpDenial(httpDenial('hierarchy'), 'foreign');
        h.checkHttpDenial(httpDenial('resource'), 'resource');
        for (const [kind, stage] of [['hierarchy', 'token'], ['token', 'resource'], ['resource', 'token'],
            ['resource', 'foreign'], ['hierarchy', 'resource'], ['token', 'unknown']]) {
            throws(() => h.checkHttpDenial(httpDenial(kind), stage), 'denial_not_proven');
        }
    });
    await test('native denial data rejects sentinels wrong status cause message and code', () => {
        for (const [kind, stage] of [['token', 'token'], ['token', 'foreign'], ['hierarchy', 'foreign'], ['resource', 'resource']]) {
            for (const extra of [{sentinel: 'secret'}, {subscriptions: [Q]}, {queues: []}, {calls: null},
                {agents: null}, {metrics: {current_waiting: 1}}]) {
                const bad = httpDenial(kind); bad.body.data = {...bad.body.data, ...extra};
                throws(() => h.checkHttpDenial(bad, stage), 'denial_not_proven');
            }
            for (const mutate of [r => { r.status = 401; }, r => { r.status = 503; },
                r => { r.body.status = 'success'; }, r => { r.body.error = '401'; },
                r => { r.body.error = 403; }, r => { r.body.message = 'other-error'; },
                r => { r.body.data = {cause: 'wrong cause', message: 'forbidden'}; },
                r => { r.body.data = undefined; }]) {
                const bad = httpDenial(kind); mutate(bad);
                throws(() => h.checkHttpDenial(bad, stage), 'denial_not_proven');
            }
        }
    });
    await test('public run and cleanup require explicit arming before fixture access', () => {
        assert(/async function main\(argv\) \{\s*(?:\/\/[^\n]*\n\s*)*const o = options\(argv\);/.test(before.toString()));
        for (const mode of ['run', 'resume', 'cleanup']) {
            const r = cp.spawnSync(process.execPath, [sourcePath, '--mode', mode,
                '--run-dir', '/must-not-access-queue-live-sentinel', '--admin-token-file', '/must-not-read-token-sentinel',
                '--acceptance-file', '/must-not-read-acceptance-sentinel', '--create-owned-denied-queue'],
            {env: {PATH: '/usr/bin:/bin', LANG: 'C'}, encoding: 'utf8', timeout: 5000, maxBuffer: 65536});
            assert.ifError(r.error); assert.equal(r.status, 1); assert.equal(r.stdout, '');
            assert.deepEqual(JSON.parse(r.stderr), {result: 'FAIL_RETAIN', code: 'explicit_arming_required'});
        }
    });
    await test('actual scope GET view shape and strong revision gate', () => {
        const result = {status: 200, body: {status: 'success', data: [{id: 'api:scope'}], revision: REV}};
        assert.equal(h.document(result, 'scope_restrictions').id, 'api:scope'); assert.equal(h.revision(result), REV);
        throws(() => h.document({...result, body: {...result.body, data: []}}, 'scope_restrictions'), 'not_unique');
        throws(() => h.document({...result, body: {...result.body, data: result.body.data[0]}}, 'scope_restrictions'), 'not_unique');
        throws(() => h.revision({...result, body: {...result.body, revision: 'automatic'}}), 'strong_revision');
    });
    await test('write-ahead setup, real-login separation and owned-only resources', async () => {
        const l = ledger(true), io = double(l); await h.setup(io, io.save, l, 'setup-only', true);
        h.validateLedger(l); assert.equal(l.resources.length, 9);
        assert.equal(l.resources.filter(r => r.collection === 'users' && r.login === 'verified').length, 4);
        for (const row of l.resources.filter(r => r.collection === 'users'))
            assert.deepEqual(row.login_response, {http_status: 200});
        assert(io.trace.filter(r => r.method === 'PUT').every(r => r.route === 'user_auth' ||
            new RegExp(`^accounts/${A}/(queues|scope_restrictions|users\\?send_email_on_creation=false)$`).test(r.route)));
        assert(!io.trace.some(r => /token_restrictions$|devices|callflows|status|restart/.test(r.route || '')));
        const row = l.resources.find(r => r.collection === 'users'), doc = io.docs.get('users/' + row.id);
        assert(h.owned(doc, row, l)); assert(!h.owned({...doc, priv_level: 'admin'}, row, l));
        assert(!h.owned({...doc, queues: [Q]}, row, l));
        assert(!h.owned({...doc, [h.KEY]: {...doc[h.KEY], run: '2'.repeat(32)}}, row, l));
    });
    await test('native rate-limit login rejection is journaled without retry or cleanup permission', async () => {
        const l = ledger(), io = double(l), request = io.request, requestId = '9'.repeat(32);
        let attempts = 0;
        io.request = async (...args) => {
            if (args[1] !== 'user_auth') return request(...args);
            attempts++;
            assert.equal(io.saves.at(-1).resources.at(-1).login, 'pending');
            return {status: 429, body: {status: 'error', error: '429', message: 'too_many_requests',
                request_id: requestId, data: {message: 'too many requests'}}};
        };
        await rejects(() => h.setup(io, io.save, l, 'setup-only', false), 'login_rejected_rate_limit');
        assert.equal(attempts, 1);
        const row = io.saves.at(-1).resources.at(-1);
        assert.equal(row.login, 'rejected_rate_limit');
        assert.deepEqual(row.login_response, {http_status: 429, request_id: requestId});
        assert.equal(row.token, undefined);
        assert(!io.trace.some(r => r.route === 'token_auth'));
        const count = io.trace.length;
        await rejects(() => h.cleanup(io, io.save, l, 'setup-only', NOW + 86400), 'ambiguous_write_or_login_retain');
        assert.equal(io.trace.length, count);
    });
    await test('ambiguous login replies retain pending state and only bounded nonsecret diagnostics', async () => {
        const response = () => ({status: 429, body: {status: 'error', error: '429', message: 'too_many_requests',
            request_id: '9'.repeat(32), data: {message: 'too many requests'}}});
        const variants = [
            r => { r.status = 503; }, r => { r.body.status = 'success'; },
            r => { r.body.error = 429; }, r => { r.body.message = 'private-message-sentinel'; },
            r => { r.body.auth_token = 'private-token-sentinel'; }, r => { r.body.auth_token = null; },
            r => { r.body.data.auth_token = 'private-token-sentinel'; }, r => { r.body.data = {}; },
            r => { r.status = 999; }, r => { r.status = '429'; }
        ];
        for (const change of variants) {
            const l = ledger(), io = double(l), request = io.request, reply = response(); let attempts = 0;
            change(reply);
            io.request = async (...args) => {
                if (args[1] !== 'user_auth') return request(...args);
                attempts++; return reply;
            };
            await rejects(() => h.setup(io, io.save, l, 'setup-only', false), 'api_success_required');
            const row = io.saves.at(-1).resources.at(-1);
            assert.equal(attempts, 1); assert.equal(row.login, 'pending'); assert.equal(row.token, undefined);
            assert.deepEqual(row.login_response, {...(Number.isInteger(reply.status) && reply.status <= 599 ?
                {http_status: reply.status} : {}), request_id: '9'.repeat(32)});
            assert(!JSON.stringify(row.login_response).includes('private-'));
            assert(!io.trace.some(r => r.route === 'token_auth'));
        }
        for (const requestId of ['secret\nheader', 'f'.repeat(129), 'A'.repeat(32), {token: 'private-token-sentinel'}, null]) {
            const l = ledger(), io = double(l), request = io.request, reply = response();
            reply.body.request_id = requestId;
            io.request = async (...args) => args[1] === 'user_auth' ? reply : request(...args);
            await rejects(() => h.setup(io, io.save, l, 'setup-only', false), 'login_rejected_rate_limit');
            assert.deepEqual(io.saves.at(-1).resources.at(-1).login_response, {http_status: 429});
        }
    });
    await test('lost login response remains pending without invented status or follow-up', async () => {
        const l = ledger(), io = double(l), request = io.request; let attempts = 0;
        io.request = async (...args) => {
            if (args[1] !== 'user_auth') return request(...args);
            attempts++; throw Error('offline_lost_login');
        };
        await rejects(() => h.setup(io, io.save, l, 'setup-only', false), 'offline_lost_login');
        const row = io.saves.at(-1).resources.at(-1);
        assert.equal(row.login, 'pending'); assert.equal(row.login_response, undefined);
        assert.equal(attempts, 1); assert(!io.trace.some(r => r.route === 'token_auth'));
    });
    await test('real inherited-fd lock excludes competing flock and never creates cwd/3', async () => {
        const dir = fs.mkdtempSync(path.join(require('node:os').tmpdir(), 'queue-live-lock-offline-'));
        const file = path.join(dir, 'owned.lock'), cwd = process.cwd(); let lock;
        fs.chmodSync(dir, 0o700); fs.writeFileSync(file, '', {mode: 0o600, flag: 'wx'});
        const competing = () => cp.spawnSync('/usr/bin/flock', ['-E', '75', '-n', file, '/bin/true'],
            {cwd: dir, encoding: 'utf8', timeout: 1500, maxBuffer: 1024,
                env: {PATH: '/usr/bin:/bin', LANG: 'C'}});
        async function released(held) {
            const deadline = Date.now() + 1500;
            while (held.alive() && Date.now() < deadline) await new Promise(resolve => setTimeout(resolve, 10));
            assert.equal(held.alive(), false);
        }
        try {
            process.chdir(dir);
            lock = await h.lockFixture(file);
            assert.equal(lock.alive(), true); assert.equal(fs.existsSync(path.join(dir, '3')), false);
            const blocked = competing(); assert.equal(blocked.error, undefined); assert.equal(blocked.status, 75);
            await rejects(() => h.lockFixture(file), 'shared_lock_busy');
            assert.equal(fs.existsSync(path.join(dir, '3')), false);
            lock.close(); await released(lock); lock = undefined;
            const free = competing(); assert.equal(free.error, undefined); assert.equal(free.status, 0);
            lock = await h.lockFixture(file); assert.equal(lock.alive(), true);
            lock.close(); await released(lock); lock = undefined;
            fs.chmodSync(file, 0o602);
            await rejects(() => h.lockFixture(file), 'unsafe_shared_lock');
            assert.equal(fs.existsSync(path.join(dir, '3')), false);
        } finally {
            if (lock) { lock.close(); await released(lock); }
            process.chdir(cwd);
            for (const name of ['3', 'owned.lock']) {
                const ownedFile = path.join(dir, name);
                if (fs.existsSync(ownedFile)) fs.unlinkSync(ownedFile);
            }
            fs.rmdirSync(dir);
        }
    });
    await test('under-lock ledger admission rejects stale resume and late run collision without writing', () => {
        const dir = fs.mkdtempSync(path.join(require('node:os').tmpdir(), 'queue-live-ledger-offline-'));
        const file = path.join(dir, 'ledger.json'), l = ledger();
        try {
            h.admitLedger({file}, l, 'run');
            fs.writeFileSync(file, JSON.stringify(l), {mode: 0o600});
            h.admitLedger({file}, l, 'resume');
            throws(() => h.admitLedger({file}, l, 'run'), 'existing_ledger_no_retry');
            const changed = {...l, cleanup_hold: 'uncaptured_prior_login', resume_attempt: {ambiguous: true}};
            fs.writeFileSync(file, JSON.stringify(changed));
            for (const mode of ['resume', 'cleanup']) throws(() => h.admitLedger({file}, l, mode), 'ledger_changed_before_lock');
            assert.deepEqual(JSON.parse(fs.readFileSync(file)), changed);
            fs.unlinkSync(file); fs.writeFileSync(file + '.next', '{}', {mode: 0o600});
            throws(() => h.admitLedger({file}, l, 'run'), 'existing_ledger_no_retry');
            assert(before.toString().indexOf('admitLedger(writer, l, o.mode)') > before.toString().indexOf('const lock = await lockFixture()'));
            assert(before.toString().includes('if (ledgerAdmitted && fs.existsSync(writer.file))'));
        } finally {
            for (const p of [file, file + '.next']) if (fs.existsSync(p)) fs.unlinkSync(p);
            fs.rmdirSync(dir);
        }
    });
    await test('explicit resume reuses fixtures and permanently retains an uncaptured prior login', async () => {
        const l = ledger(true), io = double(l); await h.setup(io, io.save, l, 'setup-only', true);
        const row = l.resources.find(r => r.kind === 'user:no_roster');
        row.login = 'pending'; delete row.token; delete row.expires; l.phase = 'retained'; io.trace.length = 0;
        await rejects(() => h.resume(io, io.save, l, 'setup-only'), 'permanent_retention');
        assert.equal(io.trace.length, 0);
        const request = io.request;
        io.request = async (...args) => {
            const result = await request(...args);
            if (args[0] === 'GET' && args[1] === `accounts/${A}/queues/${l.denied_queue}`) delete result.body.revision;
            return result;
        };
        await h.resume(io, io.save, l, 'setup-only', true);
        assert.equal(row.login, 'verified'); assert.equal(l.cleanup_hold, 'uncaptured_prior_login');
        assert.deepEqual(l.resume_attempt, {prior_login: 'pending', ambiguous: true});
        assert.deepEqual(io.trace.filter(r => r.method !== 'GET').map(r => r.route), ['user_auth']);
        assert(io.saves.some(s => s.cleanup_hold === 'uncaptured_prior_login' && s.resources.find(r => r.kind === row.kind).login === 'pending'));
        await rejects(() => h.resume(io, io.save, l, 'setup-only', true), 'complete_owned_setup');
        io.expire(); io.trace.length = 0;
        await rejects(() => h.cleanup(io, io.save, l, 'setup-only', NOW + 7200), 'uncaptured_login_cleanup_hold');
        assert.equal(io.trace.length, 0);
        delete l.cleanup_hold;
        await rejects(() => h.cleanup(io, io.save, l, 'setup-only', NOW + 7200), 'uncaptured_login_cleanup_hold');
    });
    await test('definite rate-limit resume is explicit and does not create duplicate resources', async () => {
        const l = ledger(true), io = double(l); await h.setup(io, io.save, l, 'setup-only', true);
        const row = l.resources.find(r => r.kind === 'user:no_roster');
        row.login = 'rejected_rate_limit'; row.login_response = {http_status: 429};
        delete row.token; delete row.expires; l.phase = 'retained'; io.trace.length = 0;
        await h.resume(io, io.save, l, 'setup-only');
        assert.equal(l.cleanup_hold, undefined); assert.equal(l.resume_attempt.ambiguous, false);
        assert.deepEqual(io.trace.filter(r => r.method !== 'GET').map(r => r.route), ['user_auth']);
        io.expire(); await h.cleanup(io, io.save, l, 'setup-only', NOW + 7200);
        assert.equal(l.phase, 'cleaned');
    });
    await test('resume refuses fixture drift incomplete setup and failed retention persistence before login', async () => {
        for (const fault of ['body', 'incomplete', 'save']) {
            const l = ledger(true), io = double(l); await h.setup(io, io.save, l, 'setup-only', true);
            const row = l.resources.find(r => r.kind === 'user:no_roster');
            row.login = 'pending'; delete row.token; delete row.expires; l.phase = 'retained'; io.trace.length = 0;
            if (fault === 'body') io.docs.get('users/' + row.id).first_name = 'changed';
            if (fault === 'incomplete') row.state = 'create_pending';
            const save = fault === 'save' ? () => { throw Error('disk_failure'); } : io.save;
            await rejects(() => h.resume(io, save, l, 'setup-only', true), 'resume_fixture_drift|complete_owned_setup|disk_failure');
            assert.equal(io.trace.filter(r => r.method !== 'GET').length, 0);
        }
    });
    await test('ambiguous create stays pending and is never retried', async () => {
        const l = ledger(true), io = double(l), request = io.request; let calls = 0;
        io.request = async (...args) => { if (args[0] === 'PUT') { calls++; throw Error('lost response'); } return request(...args); };
        await rejects(() => h.setup(io, io.save, l, 'setup-only', true), 'lost response');
        assert.equal(calls, 1); assert.equal(l.resources[0].state, 'create_pending');
        await rejects(() => h.cleanup(io, io.save, l, 'setup-only', NOW + 9999), 'ambiguous_write');
        assert(!io.trace.some(r => r.method === 'DELETE'));
    });
    await test('modified policy readback fails before obtaining any token', async () => {
        const l = ledger(), io = double(l), request = io.request;
        io.request = async (...args) => { const r = await request(...args);
            if (args[0] === 'GET' && args[1].includes('/scope_restrictions/') && r.body.data[0]) r.body.data[0].token_restrictions = {};
            return r; };
        await rejects(() => h.setup(io, io.save, l, 'setup-only', false), 'readback_mismatch');
        assert(!io.trace.some(r => r.route === 'user_auth'));
    });
    await test('native matrix includes positive controls and never uses setup principal', async () => {
        const l = ledger(), io = double(l); await h.setup(io, io.save, l, 'setup-only', false);
        const outcomes = []; const fake = {async request(method, route, body, token) {
            assert.equal(method, 'GET'); assert.equal(body, undefined); assert.notEqual(token, 'setup-only');
            const role = l.resources.find(r => r.token === token).kind.slice(5);
            const positive = role === 'allowed' && route === `accounts/${A}/queues/${Q}/live`;
            outcomes.push(route); return positive ? {status: 200, headers: {'cache-control': 'no-store'},
                body: {status: 'success', data: {account_id: A, queues: [{id: Q}]}}} :
                httpDenial(route.startsWith(`accounts/${F}/`) || route === `accounts/${A}/queues/${D}/live` ? 'token' : 'resource');
        }, async socket(a, q, token, allowed) { assert.notEqual(token, 'setup-only'); outcomes.push([a, q, allowed]); }};
        await h.matrix(fake, io.save, l); assert.equal(l.checks.length, 17); assert.equal(l.matrix_passed, true);
        assert(l.checks.includes('same_binding_foreign_account_denied')); assert(l.checks.includes('no_roster_hint_allowed'));
        assert.equal(l.phase, 'retained'); assert.equal(outcomes.length, 17);
    });
    await test('HTTP 503 cannot substitute for authorization denial', async () => {
        const l = ledger(), io = double(l); await h.setup(io, io.save, l, 'setup-only', false);
        await rejects(() => h.matrix({request: async () => ({status: 503}), socket: async () => {}}, io.save, l), 'unexpected_http');
        assert.equal(l.matrix_passed, false);
    });
    await test('live JWT prevents ALL cleanup including deletion of its owner', async () => {
        const l = ledger(true), io = double(l); await h.setup(io, io.save, l, 'setup-only', true);
        await rejects(() => h.cleanup(io, io.save, l, 'setup-only', NOW), 'expiry_pending');
        assert(!io.trace.some(r => r.method === 'DELETE'));
        await rejects(() => h.cleanup(io, io.save, l, 'setup-only', NOW + 4000), 'invalidation_unproven');
        assert(!io.trace.some(r => r.method === 'DELETE'));
    });
    await test('403 policy rejection is NOT expired authentication', async () => {
        const l = ledger(), io = double(l); await h.setup(io, io.save, l, 'setup-only', false);
        const request = io.request; io.request = (...a) => a[1] === 'token_auth' ? Promise.resolve({status: 403, body: {status: 'error'}}) : request(...a);
        await rejects(() => h.cleanup(io, io.save, l, 'setup-only', NOW + 4000), 'invalidation_unproven');
        assert(!io.trace.some(r => r.method === 'DELETE'));
    });
    await test('expired authentication plus exact ownership permits conditional deletion', async () => {
        const l = ledger(true), io = double(l); await h.setup(io, io.save, l, 'setup-only', true); io.expire();
        await h.cleanup(io, io.save, l, 'setup-only', NOW + 4000);
        assert.equal(l.phase, 'cleaned'); assert.equal(io.docs.size, 0);
        assert.equal(io.trace.filter(r => r.method === 'DELETE').length, 9);
        assert(l.resources.every(r => r.state === 'deleted'));
    });
    await test('drift after expiry retains resource rather than refreshing revision', async () => {
        const l = ledger(), io = double(l); await h.setup(io, io.save, l, 'setup-only', false); io.expire();
        const user = l.resources.find(r => r.collection === 'users'); io.docs.get('users/' + user.id).first_name = 'Changed';
        await rejects(() => h.cleanup(io, io.save, l, 'setup-only', NOW + 4000), 'ownership_drift');
        assert(!io.trace.some(r => r.method === 'DELETE'));
    });
    await test('lost delete response remains ambiguous, never retry deletion', async () => {
        const l = ledger(), io = double(l); await h.setup(io, io.save, l, 'setup-only', false); io.expire();
        const request = io.request; let deletes = 0;
        io.request = async (...args) => { if (args[0] === 'DELETE') { deletes++; throw Error('lost delete'); } return request(...args); };
        await rejects(() => h.cleanup(io, io.save, l, 'setup-only', NOW + 4000), 'lost delete');
        await rejects(() => h.cleanup(io, io.save, l, 'setup-only', NOW + 4000), 'ambiguous_write');
        assert.equal(deletes, 1);
    });
    await test('user creation explicitly suppresses native notification only on user PUT', async () => {
        const l = ledger(), io = double(l); await h.setup(io, io.save, l, 'setup-only', false);
        const creates = io.trace.filter(r => r.method === 'PUT' && r.route !== 'user_auth');
        assert.equal(creates.length, 8);
        assert.equal(creates.filter(r => r.route === `accounts/${A}/users?send_email_on_creation=false`).length, 4);
        assert.equal(creates.filter(r => r.route === `accounts/${A}/scope_restrictions`).length, 4);
        assert(!io.trace.some(r => r.route.startsWith(`accounts/${A}/queues`)));
        assert(l.resources.every(r => r.body.send_email_on_creation === undefined));
    });
    await test('malformed returned user and queue IDs stay pending without follow-up or login', async () => {
        for (const kind of ['users', 'queues']) {
            const invalidIds = [undefined, null, 123, [], '', 'A'.repeat(32), 'a'.repeat(31), '../foreign', 'private-id-sentinel'];
            if (kind === 'queues') invalidIds.push(Q); // Never adopt the existing positive queue.
            for (const returnedId of invalidIds) {
                const l = ledger(kind === 'queues'), io = double(l), request = io.request;
                io.request = async (...args) => {
                    const result = await request(...args);
                    if (args[0] === 'PUT' && args[1].startsWith(`accounts/${A}/${kind}`)) result.body.data.id = returnedId;
                    return result;
                };
                await rejects(() => h.setup(io, io.save, l, 'setup-only', kind === 'queues'), 'created_identity_unknown');
                const row = l.resources.at(-1); assert.equal(row.collection, kind); assert.equal(row.state, 'create_pending');
                assert.equal(row.id, undefined);
                assert.equal(row.creation_diagnostic.code, 'invalid_created_id');
                if (typeof returnedId === 'string') assert(/^[a-f0-9]{64}$/.test(row.creation_diagnostic.returned_id_sha256));
                assert.equal(JSON.stringify(row.creation_diagnostic).includes('private-id-sentinel'), false);
                h.validateLedger(l);
                assert(!io.trace.some(r => r.route === 'user_auth'));
                const reads = io.trace.filter(r => r.method === 'GET' && r.route.startsWith(`accounts/${A}/${kind}/`));
                assert.equal(reads.length, 0); // No guessed queue ID or follow-up request.
                assert.equal(io.trace.filter(r => r.method === 'PUT' && r.route.startsWith(`accounts/${A}/${kind}`)).length, 1);
            }
        }
    });
    await test('owned denied queue adopts native UUID in one journal before readback', async () => {
        const l = ledger(true), io = double(l), request = io.request;
        h.validateLedger(l); let queueRead = false;
        io.request = async (...args) => {
            if (args[0] === 'GET' && args[1].startsWith(`accounts/${A}/queues/`)) {
                queueRead = true;
                assert.equal(l.denied_queue, 'e'.repeat(32));
                const saved = io.saves.at(-1), ownedQueue = saved.resources.find(r => r.collection === 'queues');
                assert.equal(saved.denied_queue, l.denied_queue); assert.equal(ownedQueue.id, l.denied_queue);
                assert.equal(ownedQueue.state, 'create_pending'); assert.equal(ownedQueue.body.id, undefined);
                assert.equal(args[1], `accounts/${A}/queues/${l.denied_queue}`);
            }
            return request(...args);
        };
        await h.setup(io, io.save, l, 'setup-only', true);
        assert(queueRead); h.validateLedger(l); assert.notEqual(l.denied_queue, D);
        const initial = io.saves.find(s => s.resources.some(r => r.collection === 'queues'));
        assert.equal(initial.denied_queue, undefined); assert.equal(initial.resources[0].id, undefined);
        assert.equal(initial.resources[0].state, 'create_pending');
        assert.equal(l.resources.find(r => r.collection === 'queues').state, 'created');
        assert.equal(io.trace.filter(r => r.method === 'PUT' && r.route === `accounts/${A}/queues`).length, 1);
    });
    await test('unknown queue creation retains an ID-less journal and cannot be retried', async () => {
        const l = ledger(true), io = double(l), request = io.request;
        io.request = async (...args) => {
            if (args[0] === 'PUT' && args[1] === `accounts/${A}/queues`) {
                await request(...args); throw Error('lost-native-create-response');
            }
            return request(...args);
        };
        await rejects(() => h.setup(io, io.save, l, 'setup-only', true), 'lost-native');
        assert.equal(l.denied_queue, undefined); assert.equal(l.resources[0].id, undefined);
        assert.equal(l.resources[0].state, 'create_pending'); h.validateLedger(l);
        l.phase = 'retained'; h.validateLedger(l);
        await rejects(() => h.setup(io, io.save, l, 'setup-only', true), 'owned_queue_create_no_retry');
        await rejects(() => h.cleanup(io, io.save, l, 'setup-only', NOW + 4000), 'ambiguous_write');
        assert.equal(io.trace.length, 1); assert.equal(io.docs.size, 1);
        const bad = clone(l); bad.phase = 'testing'; throws(() => h.validateLedger(bad), 'invalid_ledger');
    });
    await test('queue identity adoption requires owned response and durable save', async () => {
        for (const failure of ['ownership', 'journal']) {
            const l = ledger(true), io = double(l), request = io.request;
            io.request = async (...args) => {
                const result = await request(...args);
                if (failure === 'ownership' && args[0] === 'PUT') result.body.data[h.KEY].run = '2'.repeat(32);
                return result;
            };
            const save = value => {
                if (failure === 'journal' && value.denied_queue) throw Error('adoption-journal-failed');
                io.save(value);
            };
            await rejects(() => h.setup(io, save, l, 'setup-only', true), failure === 'ownership' ? 'ownership_mismatch' : 'adoption-journal');
            assert.equal(io.trace.length, 1); assert.equal(io.saves.at(-1).denied_queue, undefined);
            assert.equal(io.saves.at(-1).resources[0].id, undefined);
            assert.equal(io.saves.at(-1).resources[0].state, 'create_pending');
            h.validateLedger(io.saves.at(-1));
        }
        const missing = ledger(); delete missing.denied_queue;
        throws(() => h.validateLedger(missing), 'invalid_ledger');
        const existing = ledger(), io = double(existing);
        await rejects(() => h.setup(io, io.save, existing, 'setup-only', true), 'owned_queue_create_no_retry');
        assert.equal(io.trace.length, 0);
    });
    await test('HTTP clean JSON settlement preserves headers and conditional revision', async () => {
        const d = httpDouble(), io = httpTransport(d);
        try {
            const r = await within(io.request('DELETE', `accounts/${A}/users/${Q}`, undefined, 'offline-token', REV));
            assert.equal(r.status, 200); assert.deepEqual(r.body, {status: 'success', data: {}});
            assert.equal(r.headers['cache-control'], 'no-store');
            assert.equal(d.calls[0].options.headers['If-Match'], `"${REV}"`);
            assert.equal(d.calls[0].options.maxHeaderSize, 16384); assert.equal(d.calls[0].options.agent, false);
            assert.equal(d.calls.length, 1); assert.equal(d.timers.size, 0); assert.equal(d.calls[0].destroyed, 0);
        } finally { io.close(); }
    });
    await test('HTTP request close abort and response errors settle with fixed diagnostics', async () => {
        for (const [mode, code] of [['request_close', 'http_response_incomplete'], ['response_close', 'http_response_incomplete'],
            ['aborted', 'http_response_aborted'], ['request_error', 'http_transport_failed'], ['response_error', 'http_transport_failed']]) {
            const d = httpDouble(mode), io = httpTransport(d);
            try {
                await rejects(() => within(io.request('GET', 'accounts/' + A)), code);
                assert.equal(d.timers.size, 0); assert.equal(d.calls[0].destroyed, 1);
            } finally { io.close(); }
        }
    });
    await test('HTTP timeout settles without destroy event and cancels its timer', async () => {
        const d = httpDouble('stall'), io = httpTransport(d);
        try {
            const p = io.request('GET', 'accounts/' + A); const checked = rejects(() => within(p), 'http_timeout');
            d.fire(); await checked;
            assert.equal(d.calls.length, 1); assert.equal(d.calls[0].destroyed, 1); assert.equal(d.timers.size, 0);
        } finally { io.close(); }
    });
    await test('session stop immediately settles every HTTP request and rejects forward work', async () => {
        const d = httpDouble('stall'), io = httpTransport(d);
        const p1 = io.request('GET', 'accounts/' + A), p2 = io.request('GET', 'accounts/' + F);
        const checks = [rejects(() => within(p1), 'acceptance_session_stopped'), rejects(() => within(p2), 'acceptance_session_stopped')];
        io.close(); io.close(); await Promise.all(checks);
        assert.equal(d.timers.size, 0); assert(d.calls.every(c => c.destroyed === 1));
        await rejects(() => io.request('GET', 'accounts/' + A), 'acceptance_session_stopped');
        assert.equal(d.calls.length, 2);
    });
    await test('HTTP empty412 supported but other empty or invalid JSON rejected', async () => {
        const d = httpDouble('success', 412, Buffer.alloc(0)), io = httpTransport(d);
        try { assert.equal((await within(io.request('DELETE', 'accounts/' + A))).body, null); }
        finally { io.close(); }
        for (const [status, raw, code] of [[200, Buffer.alloc(0), 'http_unexpected_empty_body'],
            [204, Buffer.alloc(0), 'http_unexpected_empty_body'], [200, Buffer.from('private-json-sentinel'), 'http_result_unavailable']]) {
            const bad = httpDouble('success', status, raw), badIo = httpTransport(bad);
            try { await rejects(() => within(badIo.request('GET', 'accounts/' + A)), code); assert.equal(bad.timers.size, 0); }
            finally { badIo.close(); }
        }
    });
    await test('HTTP redirect and oversized input refused without followup request', async () => {
        for (const [status, raw, code] of [[302, Buffer.alloc(0), 'http_redirect_refused'],
            [307, Buffer.alloc(0), 'http_redirect_refused'], [200, Buffer.alloc(2 * 1024 * 1024 + 1), 'http_body_limit']]) {
            const d = httpDouble('success', status, raw), io = httpTransport(d);
            try {
                await rejects(() => within(io.request('GET', 'accounts/' + A)), code);
                assert.equal(d.calls.length, 1); assert.equal(d.timers.size, 0);
            } finally { io.close(); }
        }
    });
    await test('lost lock and oversized outgoing body fail before network or accepting reply', async () => {
        let alive = true;
        const d = httpDouble(), io = httpTransport(d, {alive: () => alive});
        try {
            const p = io.request('GET', 'accounts/' + A); alive = false;
            await rejects(() => within(p), 'acceptance_session_stopped');
            await rejects(() => io.request('GET', 'accounts/' + A), 'acceptance_session_stopped');
            assert.equal(d.calls.length, 1);
        } finally { io.close(); }
        const d2 = httpDouble(), io2 = httpTransport(d2);
        try {
            await rejects(() => io2.request('PUT', 'accounts/' + A, {large: 'x'.repeat(2 * 1024 * 1024)}), 'http_request_body_limit');
            assert.equal(d2.calls.length, 0);
        } finally { io2.close(); }
    });
    await test('source contract guards supported policies and unsupported short user_auth TTL', () => {
        const read = p => fs.readFileSync(path.join(__dirname, '..', p), 'utf8');
        assert(read('applications/crossbar/src/modules/cb_user_auth.erl').includes('crossbar_auth:create_auth_token(maybe_include_claims(Context), ?MODULE).'));
        assert(read('applications/crossbar/src/crossbar_auth.erl').includes("props:get_integer_value('expiration', TokenOptions)"));
        assert(read('applications/crossbar/src/crossbar_util.erl').includes('kz_datamgr:get_results(AccountDb, <<"scope_restrictions/crossbar_listing">>, ViewOptions)'));
        assert(read('applications/crossbar/src/modules/cb_scope_restrictions.erl').includes("[{'startkey', ScopeRestriction}"));
        assert(read('deps/cowboy/src/cowboy_rest.erl').includes('cowboy_req:parse_header(<<"if-match">>, Req)'));
        const tokenAuthz = read('applications/crossbar/src/modules/cb_token_restrictions.erl');
        assert(tokenAuthz.includes('{<<"cause">>, <<"access denied by token restrictions">>}'));
        assert(tokenAuthz.includes("cb_context:add_system_error('forbidden', Cause, Context)"));
        const contextSource = read('applications/crossbar/src/cb_context.erl');
        assert(contextSource.includes("build_system_error(429, 'too_many_requests', <<\"too many requests\">>, Context)"));
        assert(contextSource.includes('kz_json:from_list([{<<"message">>, Message}])'));
        assert(contextSource.includes("add_system_error('forbidden'=Error, JObj, Context) ->\n    J = kz_json:set_value(<<\"message\">>, <<\"forbidden\">>, JObj)"));
        assert(read('core/kazoo_schemas/src/kz_json_schema.erl').includes('build_error_message(_Version, JObj) ->\n    JObj.'));
        assert(read('applications/acdc/src/acdc_live_auth.erl').includes('false -> throw({live_error,403,<<"queue_live_resource_forbidden">>})'));
        assert(read('applications/acdc/src/cb_acdc_live.erl').includes('throw:{live_error, Code, Message} -> crossbar_util:response(error, Message, Code, Safe)'));
        assert(read('applications/acdc/src/cb_acdc_live_agents.erl').includes('acdc_live_auth:permit(C,<<"queues">>,[Q,<<"roster">>])'));
        assert(read('applications/crossbar/src/modules/cb_simple_authz.erl').includes("{'stop', cb_context:add_system_error('forbidden', Context)}"));
        assert(read('applications/crossbar/src/api_util.erl').includes('{<<"error">>, kz_term:to_binary(ErrorCode)}'));
        assert.equal(hash(fs.readFileSync(sourcePath)), hash(before));
    });
    console.log(JSON.stringify({result: 'PASS', groups, explicit_rejection_checks: checks, source_sha256: hash(before),
        real_http: false, real_websocket: false, credentials_read: false, fixture_writes: false,
        real_flock_private_temporary_file: true}));
})().catch(() => { console.error('FAIL isolated queue-live harness regression; no secret diagnostics'); process.exitCode = 1; });
