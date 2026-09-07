#!/usr/bin/env node
'use strict';
// No HTTP, WebSocket, secret-file reads, services or fixture provisioning.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path');
const crypto = require('node:crypto');
const cp = require('node:child_process');
const h = require('./test-queue-live-isolation.cjs');
const sourcePath = path.join(__dirname, 'test-queue-live-isolation.cjs'), before = fs.readFileSync(sourcePath);
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const clone = x => JSON.parse(JSON.stringify(x)), A = 'a'.repeat(32), Q = 'b'.repeat(32), D = 'c'.repeat(32), F = 'd'.repeat(32);
const REV = '1-' + 'e'.repeat(32), NOW = 1800000000;
let groups = 0, checks = 0;
const test = async (name, f) => { await f(); groups++; console.log('PASS ' + name); };
const rejects = async (f, text) => { checks++; await assert.rejects(f, new RegExp(text)); };
const throws = (f, text) => { checks++; assert.throws(f, new RegExp(text)); };
function ledger() { return {version: 1, owner: h.OWNER, run: '1'.repeat(32), account: A, realm: 'acceptance-123456abcdef.invalid',
    positive_queue: Q, denied_queue: D, foreign_account: F, foreign_queue: 'f'.repeat(32),
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
            const parts = route.split('/'), collection = parts[2], id = decodeURIComponent(parts[3] || '');
            if (method === 'PUT') {
                assert.equal(token, 'setup-only');
                const row = l.resources.at(-1);
                assert.equal(row.state, 'create_pending');
                assert.equal(saves.at(-1).resources.at(-1).state, 'create_pending');
                assert.deepEqual(saves.at(-1).resources.at(-1).body, body);
                const created = {...clone(body), id: body.id || hash(row.kind).slice(0, 32)}; delete created.password;
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
        h.checkHttpDenial({status: 403, body: {status: 'error', data: {}}});
        for (const data of [undefined, null, [], {sentinel: 'must-not-leak'}, {subscriptions: [Q]},
            {queues: []}, {calls: null}, {agents: null}, {metrics: {current_waiting: 1}}]) {
            throws(() => h.checkHttpDenial({status: 403, body: {status: 'error', data}}), 'denial_not_proven');
        }
    });
    await test('public run and cleanup are hard closed before any fixture access', () => {
        assert(/async function main\(argv\) \{\s*(?:\/\/[^\n]*\n\s*)*need\(false, 'live_admission_closed_cleanup_not_atomic'\);/.test(before.toString()));
        for (const mode of ['run', 'cleanup']) {
            const r = cp.spawnSync(process.execPath, [sourcePath, '--mode', mode, '--allow-fixture-writes',
                '--run-dir', '/must-not-access-queue-live-sentinel', '--admin-token-file', '/must-not-read-token-sentinel',
                '--acceptance-file', '/must-not-read-acceptance-sentinel', '--create-owned-denied-queue'],
            {env: {PATH: '/usr/bin:/bin', LANG: 'C'}, encoding: 'utf8', timeout: 5000, maxBuffer: 65536});
            assert.ifError(r.error); assert.equal(r.status, 1); assert.equal(r.stdout, '');
            assert.deepEqual(JSON.parse(r.stderr), {result: 'FAIL_RETAIN', code: 'live_admission_closed_cleanup_not_atomic'});
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
        const l = ledger(), io = double(l); await h.setup(io, io.save, l, 'setup-only', true);
        h.validateLedger(l); assert.equal(l.resources.length, 9);
        assert.equal(l.resources.filter(r => r.collection === 'users' && r.login === 'verified').length, 4);
        assert(io.trace.filter(r => r.method === 'PUT').every(r => r.route === 'user_auth' ||
            new RegExp(`^accounts/${A}/(queues|users|scope_restrictions)$`).test(r.route)));
        assert(!io.trace.some(r => /token_restrictions$|devices|callflows|status|restart/.test(r.route || '')));
        const row = l.resources.find(r => r.collection === 'users'), doc = io.docs.get('users/' + row.id);
        assert(h.owned(doc, row, l)); assert(!h.owned({...doc, priv_level: 'admin'}, row, l));
        assert(!h.owned({...doc, queues: [Q]}, row, l));
        assert(!h.owned({...doc, [h.KEY]: {...doc[h.KEY], run: '2'.repeat(32)}}, row, l));
    });
    await test('ambiguous create stays pending and is never retried', async () => {
        const l = ledger(), io = double(l), request = io.request; let calls = 0;
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
                body: {status: 'success', data: {account_id: A, queues: [{id: Q}]}}} : {status: 403, body: {status: 'error', data: {}}};
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
        const l = ledger(), io = double(l); await h.setup(io, io.save, l, 'setup-only', true);
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
        const l = ledger(), io = double(l); await h.setup(io, io.save, l, 'setup-only', true); io.expire();
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
    await test('source contract guards supported policies and unsupported short user_auth TTL', () => {
        const read = p => fs.readFileSync(path.join(__dirname, '..', p), 'utf8');
        assert(read('applications/crossbar/src/modules/cb_user_auth.erl').includes('crossbar_auth:create_auth_token(maybe_include_claims(Context), ?MODULE).'));
        assert(read('applications/crossbar/src/crossbar_auth.erl').includes("props:get_integer_value('expiration', TokenOptions)"));
        assert(read('applications/crossbar/src/crossbar_util.erl').includes('kz_datamgr:get_results(AccountDb, <<"scope_restrictions/crossbar_listing">>, ViewOptions)'));
        assert(read('applications/crossbar/src/modules/cb_scope_restrictions.erl').includes("[{'startkey', ScopeRestriction}"));
        assert(read('deps/cowboy/src/cowboy_rest.erl').includes('cowboy_req:parse_header(<<"if-match">>, Req)'));
        assert.equal(hash(fs.readFileSync(sourcePath)), hash(before));
    });
    console.log(JSON.stringify({result: 'PASS', groups, explicit_rejection_checks: checks, source_sha256: hash(before),
        real_http: false, real_websocket: false, credentials_read: false, fixture_writes: false}));
})().catch(() => { console.error('FAIL isolated queue-live harness regression; no secret diagnostics'); process.exitCode = 1; });
