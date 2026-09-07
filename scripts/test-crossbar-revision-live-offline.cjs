#!/usr/bin/env node
'use strict';
// Controlled transports only; no listener, API, credential read or live writes.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path');
const crypto = require('node:crypto'), cp = require('node:child_process'), {EventEmitter} = require('node:events');
const h = require('./test-crossbar-revision-live.cjs');
const sourcePath = path.join(__dirname, 'test-crossbar-revision-live.cjs');
const sources = [__filename, sourcePath, path.join(__dirname, 'test-channel-monitor-live.cjs')];
const sha = p => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const pins = sources.map(p => [p, sha(p)]), clone = x => JSON.parse(JSON.stringify(x));
const A = 'a'.repeat(32), R1 = '1-' + '1'.repeat(32), R2 = '2-' + '2'.repeat(32);
const identity = {ACCEPTANCE_ACCOUNT_ID: A, ACCEPTANCE_ACCOUNT_NAME: 'Kazoo5 Acceptance 123456abcdef',
    ACCEPTANCE_REALM: 'acceptance-123456abcdef.invalid'};
const response = (data, revision = R1, status = 200) => ({status, body: {status: 'success', data, revision}});
const makeLedger = () => h.ledger(A, 'b'.repeat(32));
let groups = 0;
async function test(name, f) { await f(); groups++; console.log('PASS ' + name); }

function double(l, before) {
    let doc = null, getCount = 0;
    const trace = [], saves = [];
    const d = {trace, saves, get doc() { return doc; }, set doc(v) { doc = v; },
        save(v) { saves.push(clone(v)); },
        async request(method, route, body, tag) {
            h.admit(l, method, route, tag);
            const call = {method, route, body, tag, pending: saves.at(-1)?.pending}; trace.push(call);
            if (method !== 'GET') {
                assert.equal(saves.at(-1)?.pending, l.pending);
                assert(l.pending?.endsWith('_pending'));
                const entry = saves.at(-1).writes.at(-1);
                assert.equal(entry.method, method); assert.equal(entry.if_match, tag || null);
                assert.deepEqual(entry.body, body || null);
            }
            if (before) { const override = await before(call, d); if (override !== undefined) return override; }
            if (route === `accounts/${A}`) return response({id: A, name: identity.ACCEPTANCE_ACCOUNT_NAME, realm: identity.ACCEPTANCE_REALM});
            if (method === 'GET') {
                getCount++; d.getCount = getCount;
                // Scope GET intentionally has a view hash, not a document rev.
                return response(doc ? [clone(doc)] : [], '0123456789abcdef0123456789abcdef');
            }
            if (method === 'PUT') { assert.equal(doc, null); doc = clone(body); return response(clone(doc), R1, 201); }
            if (method === 'POST') {
                assert.equal(tag, `"${R1}"`); doc = clone(body); return response(clone(doc), R2);
            }
            assert.equal(method, 'DELETE');
            if (tag === `"${R1}"` || tag === `W/"${R2}"`) return {status: 412, body: null};
            assert.equal(tag, `"${R2}"`); const old = doc; doc = null; return response(old, R2);
        }};
    return d;
}
async function run(d, l) { return h.probe(d, d.save, l, identity); }

function fakeHttp(status, chunks, mode) {
    const calls = [];
    const request = (url, options, callback) => {
        const req = new EventEmitter(); calls.push({url, options});
        req.destroy = () => { queueMicrotask(() => { req.emit('error', new Error('private-transport-detail')); req.emit('close'); }); };
        req.end = payload => {
            calls.at(-1).payload = payload?.toString();
            queueMicrotask(() => {
                const res = new EventEmitter(); res.statusCode = status; callback(res);
                if (mode === 'aborted') { res.emit('aborted'); req.emit('close'); return; }
                for (const chunk of chunks) res.emit('data', chunk);
                res.emit('end'); req.emit('close');
            });
        };
        return req;
    };
    return {request, calls};
}

(async () => {
    await test('unarmed actual CLI refuses before any private file access', () => {
        const r = cp.spawnSync(process.execPath, [sourcePath, '--run-dir', '/must-not-touch-run',
            '--admin-token-file', '/must-not-read-token', '--acceptance-file', '/must-not-read-acceptance',
            '--api-url', h.API], {env: {PATH: '/usr/bin:/bin', LANG: 'C'}, encoding: 'utf8', timeout: 5000, maxBuffer: 8192});
        assert.ifError(r.error); assert.equal(r.status, 1); assert.equal(r.stdout, '');
        assert.deepEqual(JSON.parse(r.stderr), {result: 'FAIL_RETAIN', code: 'explicit_arming_required'});
    });
    await test('explicit paths, arming and literal local endpoint only', () => {
        const args = ['--allow-fixture-writes', '--run-dir', '/private/run', '--admin-token-file', '/private/token',
            '--acceptance-file', '/private/acceptance', '--api-url', h.API];
        assert.equal(h.options(args)['api-url'], h.API);
        for (const url of ['http://localhost:8000/v2', 'http://127.0.0.1:8000/v2/', 'https://127.0.0.1:8000/v2',
            'http://other:8000/v2', 'http://user:secret@127.0.0.1:8000/v2']) {
            assert.throws(() => h.options([...args.slice(0, -1), url]), /pinned_local_api/);
        }
        assert.throws(() => h.options([...args, '--allow-fixture-writes']), /invalid_cli/);
        assert.throws(() => h.ledger(h.MASTER, 'b'.repeat(32)), /invalid_probe_scope/);
    });
    await test('success journals all five write attempts and removes one policy', async () => {
        const l = makeLedger(), d = double(l); const result = await run(d, l);
        assert.deepEqual(result, {result: 'PASS', checks: 3, issued_tokens: 0, resources_removed: 1});
        assert.equal(l.phase, 'deleted'); assert.equal(l.pending, null); assert.equal(d.doc, null);
        assert.equal(l.r1, R1); assert.equal(l.r2, R2);
        assert.deepEqual(l.writes.map(w => w.stage), ['create_pending', 'update_pending', 'stale_delete_pending', 'weak_delete_pending', 'delete_pending']);
        assert.deepEqual(d.trace.filter(c => c.method === 'DELETE').map(c => c.tag), [`"${R1}"`, `W/"${R2}"`, `"${R2}"`]);
        assert.equal(JSON.stringify(d.saves).includes('X-Auth-Token'), false);
        assert(d.trace.every(c => !/users|queues|auth/.test(c.route)));
        assert.deepEqual(d.trace.find(c => c.method === 'POST').body,
            {...d.trace.find(c => c.method === 'PUT').body, [h.KEY]: h.marker(l, 2)});
    });
    await test('live account name realm and identity mismatch stop before writes', async () => {
        for (const bad of [{id: 'c'.repeat(32)}, {name: 'not-owned'}, {realm: 'foreign.invalid'}]) {
            const l = makeLedger(), d = double(l, c => c.route === `accounts/${A}` ?
                response({id: A, name: identity.ACCEPTANCE_ACCOUNT_NAME, realm: identity.ACCEPTANCE_REALM, ...bad}) : undefined);
            await assert.rejects(() => run(d, l), /live_acceptance_identity_mismatch/);
            assert.equal(d.trace.length, 1); assert.equal(l.writes.length, 0);
        }
    });
    await test('existing or ambiguous selected view is never overwritten', async () => {
        for (const bad of [response([{}]), response([{}, {}]), {...response([]), body: {status: 'success', data: [], next_start_key: 'next'}}]) {
            const l = makeLedger(), d = double(l, c => c.route.includes('scope_restrictions') ? bad : undefined);
            await assert.rejects(() => run(d, l), /target_not_virgin|scope_view_not_exact/);
            assert.equal(l.writes.length, 0);
        }
    });
    await test('ambiguous create or update leaves pending journal and no delete', async () => {
        for (const method of ['PUT', 'POST']) {
            const l = makeLedger(), d = double(l, c => { if (c.method === method) throw new h.ProbeError('http_timeout'); });
            await assert.rejects(() => run(d, l), /http_timeout/);
            assert.equal(l.pending, method === 'PUT' ? 'create_pending' : 'update_pending');
            assert.equal(d.trace.filter(c => c.method === method).length, 1);
            assert.equal(d.trace.filter(c => c.method === 'DELETE').length, 0);
        }
    });
    await test('write response must retain exact marker and a strong document revision', async () => {
        for (const kind of ['marker', 'revision']) {
            const l = makeLedger(), d = double(l, c => {
                if (c.method !== 'PUT') return;
                const data = clone(c.body); if (kind === 'marker') data[h.KEY].run = 'c'.repeat(32);
                return response(data, kind === 'revision' ? 'weak-view-hash' : R1);
            });
            await assert.rejects(() => run(d, l), /ownership_mismatch|strong_revision/);
            assert.equal(l.pending, 'create_pending'); assert.equal(l.writes.length, 1);
        }
    });
    await test('full body drift after creation update or final read prevents deletion', async () => {
        for (const at of [2, 3, 6]) {
            const l = makeLedger(), d = double(l, (c, state) => {
                if (c.method === 'GET' && c.route.includes('scope_restrictions') && (state.getCount || 0) + 1 === at && state.doc) {
                    state.doc = {...state.doc, foreign_change: true};
                }
            });
            await assert.rejects(() => run(d, l), /public_body_drift/);
            assert.equal(l.writes.some(w => w.stage === 'delete_pending'), false);
            assert(d.doc);
        }
    });
    await test('unexpected stale/weak outcome retains without final retry', async () => {
        for (const stage of ['stale_delete_pending', 'weak_delete_pending']) {
            for (const status of [200, 401, 403, 409, 500]) {
                const l = makeLedger(), d = double(l, c => c.pending === stage && c.method === 'DELETE' ? response({}, R2, status) : undefined);
                await assert.rejects(() => run(d, l), /precondition_not_rejected/);
                assert.equal(l.pending, stage); assert.equal(l.writes.some(w => w.stage === 'delete_pending'), false);
            }
        }
    });
    await test('412 with changed body is not a pass', async () => {
        const l = makeLedger(), d = double(l, (c, state) => {
            if (c.pending === 'stale_delete_pending' && c.method === 'DELETE') {
                state.doc = {...state.doc, unintended_change: true}; return {status: 412, body: null};
            }
        });
        await assert.rejects(() => run(d, l), /public_body_drift/);
        assert.equal(l.checks.length, 0); assert.equal(l.pending, 'stale_delete_pending');
    });
    await test('ambiguous final delete and failed absence retain without retry', async () => {
        for (const kind of ['timeout', 'false-success']) {
            const l = makeLedger(), d = double(l, (c, state) => {
                if (c.pending !== 'delete_pending' || c.method !== 'DELETE') return;
                if (kind === 'timeout') throw new h.ProbeError('http_timeout');
                return response(clone(state.doc), R2);
            });
            await assert.rejects(() => run(d, l), /http_timeout|delete_absence_unproven/);
            assert.equal(l.pending, 'delete_pending');
            assert.equal(l.writes.filter(w => w.stage === 'delete_pending').length, 1);
        }
    });
    await test('failed write-ahead persistence admits no request', async () => {
        const l = makeLedger(), d = double(l);
        await assert.rejects(() => h.probe(d, value => { if (value.pending) throw new Error('offline-disk-failure'); d.save(value); }, l, identity), /offline-disk/);
        assert.equal(d.trace.some(c => c.method !== 'GET'), false);
    });
    await test('transport preserves raw weak header and accepts empty native412', async () => {
        const l = makeLedger(), fake = fakeHttp(412, []), io = h.transport(l, 'offline-token', fake.request);
        try {
            assert.deepEqual(await io.request('DELETE', `accounts/${A}/scope_restrictions/${encodeURIComponent(l.id)}`, undefined, `W/"${R2}"`), {status: 412, body: null});
            assert.equal(fake.calls[0].options.headers['If-Match'], `W/"${R2}"`);
            assert.equal(fake.calls[0].options.headers['X-Auth-Token'], 'offline-token');
            assert.equal(fake.calls[0].options.agent, false);
        } finally { io.close(); }
    });
    await test('transport bounded response failures never follow redirects', async () => {
        for (const [status, chunks, mode, error] of [[302, [], undefined, /redirect_refused/],
            [200, [], undefined, /unexpected_empty/], [200, [Buffer.from('secret-non-json')], undefined, /invalid_http_json/],
            [200, [Buffer.alloc(h.MAX_BODY + 1)], undefined, /http_body_limit/], [200, [], 'aborted', /http_response_aborted/]]) {
            const l = makeLedger(), fake = fakeHttp(status, chunks, mode), io = h.transport(l, 'offline-token', fake.request);
            try { await assert.rejects(() => io.request('GET', `accounts/${A}`), error); assert.equal(fake.calls.length, 1); }
            finally { io.close(); }
        }
    });
    await test('scope guard forbids login foreign objects and requests after stop', async () => {
        const l = makeLedger(), fake = fakeHttp(200, []), io = h.transport(l, 'offline-token', fake.request);
        for (const [method, route] of [['PUT', 'user_auth'], ['PUT', `accounts/${A}/users`],
            ['DELETE', `accounts/${A}/scope_restrictions/api%3Aforeign`], ['GET', `accounts/${'c'.repeat(32)}`]]) {
            await assert.rejects(() => io.request(method, route), /request_scope_refused/);
        }
        io.close(); await assert.rejects(() => io.request('GET', `accounts/${A}`), /session_stopped/);
        assert.equal(fake.calls.length, 0);
    });
    console.log(JSON.stringify({result: 'PASS', groups, scope: 'offline controlled HTTP transport; no live acceptance'}));
})().catch(e => { console.error(e); process.exitCode = 1; }).finally(() => {
    for (const [file, before] of pins) if (sha(file) !== before) { console.error('FAIL input_drift'); process.exitCode = 99; }
});
