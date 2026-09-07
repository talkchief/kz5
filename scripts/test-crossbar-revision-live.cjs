#!/usr/bin/env node
'use strict';
// Explicitly armed, isolated-account scope-policy HTTP probe. No login/token
// issuance, users, queues, calls, services, destructive retries or cleanup mode.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const http = require('node:http');
const {baseState, MASTER} = require('./test-channel-monitor-live.cjs');
const API = 'http://127.0.0.1:8000/v2', OWNER = 'kazoo5-crossbar-revision-v1';
const KEY = 'kz5_crossbar_revision_probe', ID = /^[a-f0-9]{32}$/;
const REV = /^[1-9][0-9]*-[a-f0-9]{32}$/, STEP_MS = 8000, TOTAL_MS = 120000, MAX_BODY = 65536;
class ProbeError extends Error {}
const need = (ok, code) => { if (!ok) throw new ProbeError(code); };
const canonical = v => Array.isArray(v) ? v.map(canonical) : v && typeof v === 'object' ?
    Object.fromEntries(Object.keys(v).sort().map(k => [k, canonical(v[k])])) : v;
const equal = (a, b) => JSON.stringify(canonical(a)) === JSON.stringify(canonical(b));
const hash = v => crypto.createHash('sha256').update(JSON.stringify(canonical(v))).digest('hex');
const object = v => !!v && typeof v === 'object' && !Array.isArray(v);

function options(argv) {
    const o = {}, values = ['run-dir', 'admin-token-file', 'acceptance-file', 'api-url'];
    for (let i = 0; i < argv.length; i++) {
        const key = argv[i].slice(2);
        need(argv[i].startsWith('--') && !Object.hasOwn(o, key), 'invalid_cli');
        if (key === 'allow-fixture-writes') o[key] = true;
        else { need(values.includes(key) && argv[i + 1] && !argv[i + 1].startsWith('--'), 'invalid_cli'); o[key] = argv[++i]; }
    }
    need(o['allow-fixture-writes'] === true, 'explicit_arming_required');
    need(values.slice(0, 3).every(k => path.isAbsolute(o[k] || '')), 'explicit_paths_required');
    need(o['api-url'] === API, 'pinned_local_api_required');
    return o;
}

function protectedRead(file, max) {
    need(fs.realpathSync(path.dirname(file)) === path.dirname(file), 'unsafe_private_path');
    const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
    try {
        const st = fs.fstatSync(fd);
        need(st.isFile() && st.uid === 0 && (st.mode & 511) === 384 && st.nlink === 1 && st.size > 0 && st.size <= max,
            'unsafe_private_file');
        return fs.readFileSync(fd, 'utf8');
    } finally { fs.closeSync(fd); }
}

function journalWriter(dir) {
    const st = fs.lstatSync(dir);
    need(st.isDirectory() && !st.isSymbolicLink() && st.uid === 0 && (st.mode & 511) === 448 &&
        fs.realpathSync(dir) === dir && fs.readdirSync(dir).length === 0, 'unsafe_or_nonempty_run_directory');
    const dirFd = fs.openSync(dir, fs.constants.O_RDONLY | fs.constants.O_DIRECTORY | fs.constants.O_NOFOLLOW);
    const file = path.join(dir, 'journal.json');
    let closed = false;
    return {file, close() { if (!closed) { closed = true; fs.closeSync(dirFd); } }, save(value) {
        need(!closed, 'journal_closed');
        const current = fs.lstatSync(dir), opened = fs.fstatSync(dirFd);
        need(current.dev === opened.dev && current.ino === opened.ino && !current.isSymbolicLink(), 'run_directory_changed');
        if (fs.existsSync(file)) protectedRead(file, 1024 * 1024);
        const fd = fs.openSync(file + '.next', fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_NOFOLLOW, 384);
        try { fs.writeFileSync(fd, JSON.stringify(value, null, 2) + '\n'); fs.fsyncSync(fd); }
        finally { fs.closeSync(fd); }
        fs.renameSync(file + '.next', file); fs.fsyncSync(dirFd);
    }};
}

function ledger(account, run) {
    need(ID.test(account) && account !== MASTER && ID.test(run), 'invalid_probe_scope');
    return {version: 1, owner: OWNER, account, run, id: `api:revision-${run}`,
        phase: 'preparing', pending: null, checks: [], writes: [], issued_tokens: 0};
}
const marker = (l, version) => ({owner: OWNER, account_id: l.account, run: l.run, version});
const collection = l => `accounts/${l.account}/scope_restrictions`;
const selected = l => `${collection(l)}/${encodeURIComponent(l.id)}`;
function success(r, statuses = [200]) {
    need(statuses.includes(r.status) && r.body?.status === 'success', 'api_success_required');
    return r.body.data;
}
function revision(r) { need(REV.test(r.body?.revision || ''), 'strong_revision_required'); return r.body.revision; }
function view(r) {
    const rows = success(r);
    need(Array.isArray(rows) && rows.length <= 1 && !r.body.next_start_key, 'scope_view_not_exact');
    return rows;
}
function owned(doc, l, version) {
    need(object(doc) && doc.id === l.id && equal(doc[KEY], marker(l, version)) &&
        equal(doc.scopes, []) && equal(doc.token_restrictions, {}), 'ownership_mismatch_retain');
}

// Only this account GET and this one selected policy's operations are admitted.
function admit(l, method, route, ifMatch) {
    need((method === 'GET' && route === `accounts/${l.account}`) ||
        (method === 'PUT' && route === collection(l)) ||
        (['GET', 'POST', 'DELETE'].includes(method) && route === selected(l)), 'request_scope_refused');
    need(ifMatch === undefined || /^(?:W\/)?"[1-9][0-9]*-[a-f0-9]{32}"$/.test(ifMatch), 'invalid_if_match');
}
function decodeResponse(status, bytes) {
    need(Number.isInteger(status) && !(status >= 300 && status < 400), 'redirect_refused');
    need(bytes.length <= MAX_BODY, 'http_body_limit');
    if (bytes.length === 0) { need(status === 412, 'unexpected_empty_body'); return {status, body: null}; }
    let body; try { body = JSON.parse(bytes.toString('utf8')); } catch (_) { throw new ProbeError('invalid_http_json'); }
    need(object(body), 'invalid_http_json');
    return {status, body};
}
function transport(l, token, request = http.request) {
    const active = new Set(), deadline = Date.now() + TOTAL_MS;
    let stopped = false;
    return {close() { stopped = true; for (const req of active) req.destroy(); },
        async request(method, route, body, ifMatch) {
            admit(l, method, route, ifMatch);
            need(!stopped && Date.now() < deadline, 'session_stopped');
            const payload = body === undefined ? undefined : Buffer.from(JSON.stringify({data: body}));
            need(!payload || payload.length <= MAX_BODY, 'request_body_limit');
            return new Promise((resolve, reject) => {
                let settled = false, timer;
                const finish = (error, value) => {
                    if (settled) return;
                    settled = true; clearTimeout(timer); active.delete(req);
                    error ? reject(error) : resolve(value);
                };
                const req = request(`${API}/${route}`, {method, agent: false, maxHeaderSize: 16384, headers: {
                    Accept: 'application/json', 'X-Auth-Token': token,
                    ...(ifMatch ? {'If-Match': ifMatch} : {}),
                    ...(payload ? {'Content-Type': 'application/json', 'Content-Length': payload.length} : {})
                }}, res => {
                    let size = 0; const chunks = [];
                    res.on('data', chunk => {
                        size += chunk.length;
                        if (size > MAX_BODY) { finish(new ProbeError('http_body_limit')); req.destroy(); }
                        else chunks.push(chunk);
                    });
                    res.on('aborted', () => finish(new ProbeError('http_response_aborted')));
                    res.on('error', () => finish(new ProbeError('http_transport_failed')));
                    res.on('end', () => {
                        try {
                            need(!stopped && Date.now() < deadline, 'session_stopped');
                            finish(null, decodeResponse(res.statusCode, Buffer.concat(chunks)));
                        } catch (e) { finish(e instanceof ProbeError ? e : new ProbeError('http_response_invalid')); }
                    });
                });
                active.add(req);
                req.on('error', () => finish(new ProbeError('http_transport_failed')));
                req.on('close', () => { if (!settled) finish(new ProbeError('http_response_incomplete')); });
                timer = setTimeout(() => { finish(new ProbeError('http_timeout')); req.destroy(); }, Math.min(STEP_MS, deadline - Date.now()));
                req.end(payload);
            });
        }};
}

async function probe(io, save, l, identity) {
    need(identity.ACCEPTANCE_ACCOUNT_ID === l.account && l.account !== MASTER, 'acceptance_scope_mismatch');
    save(l);
    const account = success(await io.request('GET', `accounts/${l.account}`));
    need(account?.id === l.account && account.name === identity.ACCEPTANCE_ACCOUNT_NAME &&
        account.realm === identity.ACCEPTANCE_REALM, 'live_acceptance_identity_mismatch');
    need(view(await io.request('GET', selected(l))).length === 0, 'target_not_virgin');
    async function write(stage, method, body, tag) {
        l.pending = stage; l.writes.push({stage, method, if_match: tag || null, body: body || null}); save(l);
        return io.request(method, method === 'PUT' ? collection(l) : selected(l), body, tag);
    }
    async function unchanged(expected, version) {
        const rows = view(await io.request('GET', selected(l)));
        need(rows.length === 1, 'owned_document_missing_retain'); owned(rows[0], l, version);
        need(equal(rows[0], expected) && hash(rows[0]) === hash(expected), 'public_body_drift_retain');
    }
    const input = {id: l.id, scopes: [], token_restrictions: {}, [KEY]: marker(l, 1)};
    const created = await write('create_pending', 'PUT', input);
    const first = success(created, [200, 201]); owned(first, l, 1);
    l.r1 = revision(created); l.expected = first; l.public_hash = hash(first); save(l);
    await unchanged(first, 1); l.pending = null; l.phase = 'created'; save(l);
    // Native POST merges only existing private fields: send the full public
    // document, not a PATCH-shaped fragment that would drop policy fields.
    const updated = await write('update_pending', 'POST', {...first, [KEY]: marker(l, 2)}, `"${l.r1}"`);
    const second = success(updated); owned(second, l, 2);
    need(equal(second, {...first, [KEY]: marker(l, 2)}), 'update_public_body_drift_retain');
    l.r2 = revision(updated); need(l.r2 !== l.r1, 'revision_did_not_advance');
    l.expected = second; l.public_hash = hash(second); save(l);
    await unchanged(second, 2); l.pending = null; l.phase = 'updated'; save(l);
    for (const [stage, tag] of [['stale', `"${l.r1}"`], ['weak', `W/"${l.r2}"`]]) {
        const result = await write(`${stage}_delete_pending`, 'DELETE', undefined, tag);
        need(result.status === 412, 'precondition_not_rejected_retain');
        await unchanged(second, 2); l.pending = null; l.checks.push(`${stage}_412_unchanged`); save(l);
    }
    // Fresh full-body ownership read, but never adopt a refreshed revision.
    await unchanged(l.expected, 2);
    need(hash(l.expected) === l.public_hash && REV.test(l.r2), 'final_ownership_hash_drift_retain');
    const deleted = await write('delete_pending', 'DELETE', undefined, `"${l.r2}"`);
    const deletedDoc = success(deleted); need(deletedDoc?.id === l.id, 'delete_identity_mismatch_retain');
    need(view(await io.request('GET', selected(l))).length === 0, 'delete_absence_unproven_retain');
    l.pending = null; l.phase = 'deleted'; l.checks.push('current_delete_200_absent'); save(l);
    return {result: 'PASS', checks: l.checks.length, issued_tokens: 0, resources_removed: 1};
}

async function main(argv) {
    const o = options(argv); // Unarmed: no private reads, directory access or HTTP.
    need(process.getuid?.() === 0, 'root_required');
    process.umask(0o077);
    const writer = journalWriter(o['run-dir']); let io;
    const stop = () => io?.close();
    try {
        const state = baseState(protectedRead(o['acceptance-file'], 65536));
        const identity = {ACCEPTANCE_ACCOUNT_ID: state.ACCEPTANCE_ACCOUNT_ID,
            ACCEPTANCE_ACCOUNT_NAME: state.ACCEPTANCE_ACCOUNT_NAME, ACCEPTANCE_REALM: state.ACCEPTANCE_REALM};
        const token = protectedRead(o['admin-token-file'], 16385).replace(/\n$/, '');
        need(/^[\x21-\x7e]{1,16384}$/.test(token), 'invalid_admin_token');
        const l = ledger(identity.ACCEPTANCE_ACCOUNT_ID, crypto.randomBytes(16).toString('hex'));
        io = transport(l, token); process.on('SIGINT', stop); process.on('SIGTERM', stop);
        const result = await probe(io, writer.save, l, identity);
        console.log(JSON.stringify({...result, journal: writer.file}));
    } finally {
        io?.close(); writer.close(); process.removeListener('SIGINT', stop); process.removeListener('SIGTERM', stop);
    }
}
if (require.main === module) main(process.argv.slice(2)).catch(e => {
    console.error(JSON.stringify({result: 'FAIL_RETAIN', code: e instanceof ProbeError ? e.message : 'probe_failed'}));
    process.exitCode = 1;
});
module.exports = {options, ledger, probe, transport, decodeResponse, admit, hash, marker, KEY, MASTER, API, ProbeError, MAX_BODY};
