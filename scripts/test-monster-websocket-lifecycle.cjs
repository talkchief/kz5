#!/usr/bin/env node
'use strict';
// Real pinned AMD source; fake sockets, clocks and credentials only. Actual git
// patch application is confined to a retained mktemp fixture, never the cache.
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const vm = require('node:vm'), crypto = require('node:crypto'), cp = require('node:child_process');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const cache = process.argv[2] || '/usr/local/src/kazoo5-installer/monster-ui';
assert(process.argv.length <= 3, 'Only an optional existing framework cache is accepted');
const lodashPath = require.resolve(path.join(cache, 'node_modules/lodash'));
const pin = '7ef735eada6fd0e2b96c06f32c0bb868867f7d18';
const relative = 'src/js/lib/monster.socket.js';
const configPatch = path.join(__dirname, 'patches/monster-ui-websocket-config.patch');
const lifecyclePatch = path.join(__dirname, 'patches/monster-ui-websocket-subscription-lifecycle.patch');
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'monster-socket-lifecycle-proof.'));
fs.chmodSync(directory, 0o700);
console.log('Retaining offline lifecycle evidence in ' + directory);
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const inputs = [__filename, configPatch, lifecyclePatch, path.join(__dirname, 'install-kazoo5.sh'),
    path.join(__dirname, 'test-monster-websocket-config.cjs'), lodashPath, process.execPath, '/usr/bin/git'];
const hashes = () => inputs.map(file => ({file, sha256: digest(fs.readFileSync(file))}));
const before = hashes();
fs.writeFileSync(path.join(directory, 'inputs.before.json'), JSON.stringify(before, null, 2) + '\n');
const lodash = require(lodashPath);
let groups = 0, baseline, source;
const plain = value => JSON.parse(JSON.stringify(value));
function test(name, body) { body(); groups++; console.log('PASS ' + name); }
function git(...args) { return cp.execFileSync('/usr/bin/git', args, {encoding: 'utf8', timeout: 10000, stdio: ['ignore', 'pipe', 'pipe']}); }
function setup(bytes = source, uri = 'wss://fixture.invalid/websocket') {
    let api, clock = 0, nextId = 1, nextTimer = 1;
    const sockets = [], timers = new Map(), publications = [], logs = [];
    class Socket {
        static CONNECTING = 0; static OPEN = 1; static CLOSING = 2; static CLOSED = 3;
        constructor(url) { this.url = url; this.readyState = 0; this.events = new Map(); this.sent = []; this.throwSends = 0; this.closes = 0; sockets.push(this); }
        addEventListener(name, fn) { this.events.set(name, [...(this.events.get(name) || []), fn]); }
        emit(name, event) { (this.events.get(name) || []).slice().forEach(fn => fn(event)); }
        open() { this.readyState = 1; this.emit('open', {}); }
        close() { this.closes++; this.readyState = 3; this.emit('close', {wasClean: true}); }
        fail() { this.readyState = 3; this.emit('close', {wasClean: false}); }
        send(data) { assert.equal(this.readyState, 1); if (this.throwSends-- > 0) throw Error('SYNTHETIC_SECRET_SEND_ERROR'); this.sent.push(JSON.parse(data)); }
        message(data) { this.emit('message', {data: JSON.stringify(data)}); }
        raw(data) { this.emit('message', {data}); }
    }
    const monster = {config: {api: {socket: uri}}, isDev: () => true,
        util: {guid: () => 'request-' + nextId++, getAuthToken: () => 'synthetic-token-not-real',
            logoutAndReload: () => publications.push({name: 'fixture.logout'})},
        pub: (name, data) => publications.push({name, data}),
        waterfall: (steps, done) => steps[0](done)};
    vm.runInNewContext(bytes, {define(factory) { api = factory(name => name === 'lodash' ? lodash : monster); },
        WebSocket: Socket, URL, window: {location: {protocol: 'https:'}},
        console: {log: (...args) => logs.push(args), warn: (...args) => logs.push(args)},
        setTimeout(fn, delay) { const id = nextTimer++; timers.set(id, {fn, at: clock + delay}); return id; },
        clearTimeout(id) { timers.delete(id); }}, {filename: relative, timeout: 1000});
    return {api, monster, sockets, timers, publications, logs,
        connect() { api.connect(); const socket = sockets[sockets.length - 1]; socket.open(); return socket; },
        advance(ms) { const until = clock + ms; let steps = 0;
            while (true) { const found = [...timers].sort((a, b) => a[1].at - b[1].at)[0];
                if (!found || found[1].at > until) break;
                assert(++steps < 10000, 'Timer loop was not bounded');
                const [id, timer] = found; timers.delete(id); clock = timer.at; timer.fn();
            } clock = until;
        }};
}
const account = 'a'.repeat(32), otherAccount = 'b'.repeat(32), queue = '1'.repeat(32);
const binding = 'queue_live.changed.' + queue;
function tracked(t, overrides = {}) {
    const events = [], acknowledgements = [], errors = [], disconnects = [];
    const params = {accountId: account, binding, source: 'acdc', callback: data => events.push(plain(data)),
        lifecycle: {timeoutMs: 3000, onAck: value => acknowledgements.push(plain(value)),
            onError: value => errors.push(plain(value)), onDisconnect: value => disconnects.push(plain(value))}, ...overrides};
    return {params, events, acknowledgements, errors, disconnects, cancel: t.api.bind(params)};
}
function reply(socket, request, status = 'success', data) {
    socket.message({action: 'reply', status, request_id: request.request_id,
        data: data || {subscribed: request.action === 'subscribe' ? [request.data.binding] : [],
            unsubscribed: request.action === 'unsubscribe' ? [request.data.binding] : [],
            subscriptions: request.action === 'subscribe' ? [request.data.binding] : []}});
}
function event(socket, id = account, key = binding) {
    socket.message({action: 'event', subscribed_key: key, data: {version: 1, account_id: id, kind: 'invalidate'}});
}
function registry(t) { return t.api.getInfo().client.lifecycle; }
function legacyTrace(bytes, mode) {
    const t = setup(bytes), events = []; t.api.connect(); const first = t.sockets[0];
    if (mode !== 'preopen') first.open();
    const callback = value => events.push(plain(value));
    const params = {accountId: 'legacy-account', binding: 'call.CHANNEL_CREATE.*', source: 'legacy', callback};
    const cancel = t.api.bind(params);
    if (mode === 'preopen') first.open();
    if (first.sent.length) {
        if (mode === 'auth') {
            reply(first, first.sent[0], 'error', {errors: ['failed to authenticate token: fixture']});
            t.publications.find(item => item.name === 'auth.retryLogin').data.success();
            reply(first, first.sent[1]);
        } else reply(first, first.sent[0]);
        first.message({action: 'event', subscribed_key: params.binding, data: {call_id: 'synthetic-call'}});
        const secondCancel = t.api.bind({...params, source: 'legacy-two', callback: value => events.push(plain(value))});
        first.message({action: 'event', subscribed_key: params.binding, data: {call_id: 'synthetic-two'}});
        secondCancel();
    }
    if (mode === 'reconnect') {
        first.fail(); t.advance(250); const second = t.sockets[1]; second.open(); reply(second, second.sent[0]);
        second.message({action: 'event', subscribed_key: params.binding, data: {call_id: 'synthetic-after-reconnect'}});
    }
    cancel(); t.api.disconnect();
    return plain({events, writes: t.sockets.map(socket => socket.sent), closes: t.sockets.map(socket => socket.closes),
        publications: t.publications.map(item => item.name), timers: [...t.timers.values()].map(timer => timer.at),
        connected: t.api.getInfo().isConnected});
}
function main() {
    test('pinned private actual patch replay, forward/repeat/reverse and installer identity', () => {
        const upstream = git('-C', cache, 'show', pin + ':' + relative);
        const stage = path.join(directory, 'source'), target = path.join(stage, relative);
        fs.mkdirSync(path.dirname(target), {recursive: true}); fs.writeFileSync(target, upstream);
        git('-C', stage, 'apply', '--check', configPatch); git('-C', stage, 'apply', configPatch);
        baseline = fs.readFileSync(target, 'utf8');
        git('-C', stage, 'apply', '--check', lifecyclePatch); git('-C', stage, 'apply', lifecyclePatch);
        source = fs.readFileSync(target, 'utf8');
        assert.throws(() => git('-C', stage, 'apply', '--check', lifecyclePatch));
        git('-C', stage, 'apply', '--reverse', '--check', lifecyclePatch);
        git('-C', stage, 'apply', '--reverse', '--check', configPatch);
        git('-C', stage, 'apply', '--reverse', lifecyclePatch);
        assert.equal(fs.readFileSync(target, 'utf8'), baseline);
        git('-C', stage, 'apply', '--check', lifecyclePatch); git('-C', stage, 'apply', lifecyclePatch);
        assert.equal(fs.readFileSync(target, 'utf8'), source);
        assert.equal((fs.readFileSync(lifecyclePatch, 'utf8').match(/^diff --git /gm) || []).length, 1);
        const installer = fs.readFileSync(path.join(__dirname, 'install-kazoo5.sh'), 'utf8');
        assert(installer.includes('monster-ui-websocket-subscription-lifecycle.patch:patches/monster-ui-websocket-subscription-lifecycle.patch'));
        assert(installer.includes('apply_required_source_patch "$source_dir" "$SCRIPT_DIR/patches/monster-ui-websocket-subscription-lifecycle.patch"'));
        fs.writeFileSync(path.join(directory, 'source-lineage.json'), JSON.stringify({pin, upstream_sha256: digest(upstream),
            configured_baseline_sha256: digest(baseline), candidate_sha256: digest(source)}, null, 2) + '\n');
    });
    test('entire existing socket configuration regression passes against the private candidate', () => {
        const output = cp.execFileSync(process.execPath, [path.join(__dirname, 'test-monster-websocket-config.cjs'),
            path.join(directory, 'source', relative), lodashPath], {encoding: 'utf8', timeout: 10000,
            maxBuffer: 128 * 1024, stdio: ['ignore', 'pipe', 'pipe']});
        fs.writeFileSync(path.join(directory, 'legacy-config.log'), output);
        assert(output.includes('PASS: missing/invalid/placeholder/mixed-content'));
    });
    for (const mode of ['normal', 'preopen', 'auth', 'reconnect']) test('legacy trace unchanged: ' + mode, () => {
        assert.deepEqual(legacyTrace(source, mode), legacyTrace(baseline, mode));
    });
    test('legacy send failure and unsuccessful authentication retry keep their original behavior', () => {
        function trace(bytes) {
            const t = setup(bytes), socket = t.connect(); socket.throwSends = 1;
            const options = {accountId: 'legacy', binding: 'call.CHANNEL_CREATE.*', source: 'legacy', callback() {}};
            t.api.bind(options); assert.equal(socket.sent.length, 0);
            t.api.bind(options); reply(socket, socket.sent[0], 'error', {errors: ['failed to authenticate token: fixture']});
            t.publications.find(item => item.name === 'auth.retryLogin').data.error();
            return plain({writes: socket.sent, publications: t.publications.map(item => item.name), timers: t.timers.size});
        }
        assert.deepEqual(trace(source), trace(baseline));
    });
    test('legacy invalid configuration and ordinary missing-client bind remain unchanged', () => {
        for (const uri of [undefined, false, '/websocket', 'wss://user:password@fixture.invalid/ws', 'ws://fixture.invalid/ws']) {
            for (const bytes of [baseline, source]) {
                const t = setup(bytes); t.monster.config.api.socket = uri;
                assert.equal(t.api.bind({binding: 'call.X.*', source: 'legacy'}), undefined);
                assert.equal(t.api.connect(), false); assert.equal(t.sockets.length, 0); assert.equal(t.timers.size, 0);
            }
        }
    });
    test('opt-in before connect sends once on first open, scopes events and exposes only reply acknowledgement', () => {
        const t = setup(), p = tracked(t); assert.equal(t.sockets.length, 0);
        t.api.connect(); assert.equal(t.sockets[0].sent.length, 0); const socket = t.sockets[0]; socket.open();
        assert.equal(socket.sent.length, 1); assert.equal(socket.sent[0].auth_token, 'synthetic-token-not-real');
        event(socket); assert.equal(p.events.length, 0); reply(socket, socket.sent[0]);
        assert.equal(p.acknowledgements.length, 1); assert.equal(p.acknowledgements[0].brokerReadinessVerified, false);
        assert.equal(p.acknowledgements[0].ackScope, 'blackhole_subscription_reply');
        event(socket, otherAccount); event(socket, account, binding + '.wrong'); event(socket);
        assert.equal(p.events.length, 1); socket.open(); assert.equal(socket.sent.length, 1);
        p.cancel(); reply(socket, socket.sent[1]); assert.equal(registry(t).size, 0); assert.equal(t.timers.size, 0);
    });
    test('pre-open deadline is not restarted by opening and cancellation before open sends nothing', () => {
        const t = setup(), p = tracked(t); t.advance(2900); const socket = t.connect(); t.advance(100);
        assert.equal(p.errors[0].code, 'timeout'); assert.equal(socket.sent.length, 2);
        assert.equal(socket.sent[1].action, 'unsubscribe'); reply(socket, socket.sent[1]); assert.equal(registry(t).size, 0);
        const second = setup(), cancelled = tracked(second); cancelled.cancel(); cancelled.cancel(); second.connect(); second.advance(15000);
        assert.equal(second.sockets[0].sent.length, 0); assert.equal(cancelled.errors.length, 0); assert.equal(second.timers.size, 0);
    });
    test('bounded options require account identities and exact bindings; never open an alternate connection', () => {
        for (const overrides of [{accountId: 'wrong'}, {binding: 'call.CHANNEL_CREATE.*'}, {binding: binding + '.*'},
            {binding: ''}, {binding: 'queue_live changed'}, {binding: 'x'.repeat(257)}, {source: ''}, {callback: null}]) {
            const t = setup(), p = tracked(t, overrides); assert.equal(p.errors[0].code, 'invalid_options');
            assert.equal(t.sockets.length, 0); assert.equal(t.timers.size, 0);
        }
        for (const timeoutMs of [0, 99, 15001, '3000', 100.5]) {
            const t = setup(), errors = []; tracked(t, {lifecycle: {timeoutMs, onAck() {}, onError: value => errors.push(value)}});
            assert.equal(errors[0].code, 'invalid_options'); assert.equal(t.timers.size, 0);
        }
        const disabled = setup(source, false), p = tracked(disabled);
        assert.equal(p.errors[0].code, 'configuration_unavailable'); assert.equal(disabled.sockets.length, 0);
    });
    test('rejection, invalid success and malformed frames do not authenticate or expose raw errors', () => {
        const t = setup(), socket = t.connect(), rejected = tracked(t);
        reply(socket, socket.sent[0], 'error', {errors: ['failed to authenticate token SYNTHETIC_SECRET']});
        assert.equal(rejected.errors[0].code, 'rejected'); assert.equal(registry(t).size, 0);
        assert(!t.publications.some(item => item.name === 'auth.retryLogin'));
        assert(!JSON.stringify([t.logs, rejected.errors]).includes('SYNTHETIC_SECRET'));
        const malformed = tracked(t); reply(socket, socket.sent[1], 'success', {subscriptions: []});
        assert.equal(malformed.errors[0].code, 'invalid_reply'); assert.equal(socket.sent[2].action, 'unsubscribe');
        reply(socket, socket.sent[2]); socket.raw('{broken'); socket.message(null); socket.message([]);
        assert.equal(registry(t).size, 0);
    });
    test('pending cancellation blocks reuse, ignores late ACK and settles exact unsubscribe', () => {
        const t = setup(), socket = t.connect(), first = tracked(t), old = socket.sent[0]; first.cancel();
        assert.equal(socket.sent[1].action, 'unsubscribe'); const blocked = tracked(t);
        assert.equal(blocked.errors[0].code, 'cleanup_pending'); reply(socket, old); event(socket);
        assert.equal(first.acknowledgements.length, 0); assert.equal(first.events.length, 0);
        reply(socket, socket.sent[1]); const next = tracked(t); reply(socket, socket.sent[2]);
        assert.equal(next.acknowledgements.length, 1); first.cancel(); event(socket); assert.equal(next.events.length, 1);
    });
    test('identical callbacks still have independent cancellation and source-scoped unbind preserves siblings', () => {
        const t = setup(), socket = t.connect(), events = [], callback = value => events.push(value);
        const one = tracked(t, {callback}), two = tracked(t, {callback});
        assert.equal(socket.sent.length, 1); reply(socket, socket.sent[0]);
        one.cancel(); assert.equal(socket.sent.length, 1); event(socket); assert.equal(events.length, 1);
        const third = tracked(t, {callback, source: 'other-app'});
        t.api.unbind({accountId: account, binding, source: 'acdc'}); assert.equal(socket.sent.length, 1);
        event(socket); assert.equal(events.length, 2); assert.equal(third.acknowledgements.length, 1);
        t.api.unbind({accountId: account, binding, source: 'other-app'}); assert.equal(socket.sent.length, 2);
        assert.equal(two.acknowledgements.length, 1); reply(socket, socket.sent[1]); assert.equal(registry(t).listeners, 0);
    });
    test('account separation and caller option mutation cannot retarget pending subscriptions', () => {
        const t = setup(), socket = t.connect(), first = tracked(t), secondBinding = 'acdc.queue.' + otherAccount + '.' + queue;
        const second = tracked(t, {accountId: otherAccount, binding: secondBinding});
        first.params.accountId = otherAccount; first.params.lifecycle.onAck = () => { throw Error('changed callback'); };
        reply(socket, socket.sent[0]); reply(socket, socket.sent[1]); event(socket); event(socket, otherAccount, secondBinding);
        assert.equal(first.acknowledgements[0].accountId, account); assert.equal(first.events.length, 1); assert.equal(second.events.length, 1);
        first.cancel(); event(socket, otherAccount, secondBinding); assert.equal(second.events.length, 2);
    });
    test('same native binding in accounts A/B has independent ACK, event and unsubscribe ownership', () => {
        const t = setup(), socket = t.connect(), a = tracked(t), b = tracked(t, {accountId: otherAccount});
        assert.equal(socket.sent.length, 2); assert.equal(socket.sent[0].data.binding, socket.sent[1].data.binding);
        assert.notEqual(socket.sent[0].data.account_id, socket.sent[1].data.account_id);
        reply(socket, socket.sent[0]); event(socket, otherAccount); assert.equal(b.events.length, 0);
        reply(socket, socket.sent[1]); event(socket); event(socket, otherAccount);
        assert.equal(a.events.length, 1); assert.equal(b.events.length, 1);
        a.cancel(); assert.equal(socket.sent[2].data.account_id, account);
        reply(socket, socket.sent[2], 'success', {unsubscribed: [binding], subscriptions: [binding]});
        assert.equal(registry(t).size, 1); event(socket); event(socket, otherAccount);
        assert.equal(a.events.length, 1); assert.equal(b.events.length, 2);
        const again = tracked(t); reply(socket, socket.sent[3]); a.cancel();
        t.api.unbind({accountId: otherAccount, binding, source: 'acdc'});
        assert.equal(socket.sent[4].data.account_id, otherAccount);
        reply(socket, socket.sent[4], 'success', {unsubscribed: [binding], subscriptions: [binding]});
        event(socket); event(socket, otherAccount); assert.equal(again.events.length, 1); assert.equal(b.events.length, 2);
        assert.equal(registry(t).size, 1);
    });
    test('callback exceptions and reentrant sibling cancellation cannot strand state or call a cancelled sibling', () => {
        const t = setup(), socket = t.connect(); let other, ownEvents = 0;
        tracked(t, {callback() { ownEvents++; throw Error('fixture'); }, lifecycle: {
            onAck() { other.cancel(); throw Error('fixture'); }, onError() { throw Error('fixture'); }, onDisconnect() { throw Error('fixture'); }}});
        other = tracked(t); reply(socket, socket.sent[0]); assert.equal(other.acknowledgements.length, 0);
        event(socket); assert.equal(ownEvents, 1); assert.equal(other.events.length, 0);
        socket.fail(); assert.equal(t.timers.size, 1); t.advance(250); t.sockets[1].open(); reply(t.sockets[1], t.sockets[1].sent[0]);
        assert.equal(registry(t).listeners, 1);
    });
    test('disconnect during ACK and reentrant cross-entry cancellation never publish a later stale ACK', () => {
        const t = setup(), socket = t.connect(); let other;
        tracked(t, {lifecycle: {onAck() { socket.fail(); }, onError() {}, onDisconnect() { other.cancel(); }}});
        other = tracked(t, {binding: binding + '.other'});
        const same = tracked(t);
        reply(socket, socket.sent[0]); assert.equal(same.acknowledgements.length, 0);
        assert.equal(other.acknowledgements.length, 0); assert.equal(other.errors.length, 0);
        assert.equal(registry(t).listeners, 2);
    });
    test('disconnect during event delivery suppresses remaining callbacks for that old connection', () => {
        const t = setup(), socket = t.connect();
        tracked(t, {callback() { socket.fail(); }}); const other = tracked(t);
        reply(socket, socket.sent[0]); event(socket); assert.equal(other.events.length, 0);
        assert.equal(other.disconnects.length, 1);
    });
    test('ambiguous send and unsubscribe timeout retain bounded cleanup without closing shared socket', () => {
        const t = setup(), socket = t.connect(); socket.throwSends = 2; const p = tracked(t);
        assert.equal(p.errors[0].code, 'send_failed'); assert.equal(socket.closes, 0);
        assert.equal(registry(t).size, 1); assert.equal(Object.keys(registry(t).requests).length, 0);
        t.advance(60000); assert.equal(socket.closes, 0); assert.equal(tracked(t).errors[0].code, 'cleanup_pending');
        socket.fail(); t.advance(250); t.sockets[1].open(); assert.equal(registry(t).size, 0);
        const current = t.sockets[1], q = tracked(t); reply(current, current.sent[0]); q.cancel(); t.advance(15000);
        assert.equal(Object.keys(registry(t).requests).length, 0); assert.equal(registry(t).size, 1); assert.equal(current.closes, 0);
    });
    test('reconnect resubscribes once and rejects old-socket/old-request ACKs before new acknowledgement', () => {
        const t = setup(), first = t.connect(), p = tracked(t), old = first.sent[0]; reply(first, old);
        first.fail(); assert.equal(p.disconnects.length, 1); t.advance(250); const second = t.sockets[1]; second.open();
        assert.equal(second.sent.length, 1); reply(first, old); reply(second, old); event(second);
        assert.equal(p.acknowledgements.length, 1); assert.equal(p.events.length, 0);
        reply(second, second.sent[0]); reply(second, second.sent[0]); event(second);
        assert.equal(p.acknowledgements.length, 2); assert.equal(p.acknowledgements[1].connectionGeneration, 2); assert.equal(p.events.length, 1);
        assert.equal(Object.keys(registry(t).requests).length, 0);
    });
    test('pending disconnect exposes one failure then a bounded new attempt; deliberate disconnect retires intent', () => {
        const t = setup(), first = t.connect(), p = tracked(t); first.fail();
        assert.equal(p.errors[0].code, 'disconnected'); t.advance(250); t.sockets[1].open(); t.advance(3000);
        assert.deepEqual(p.errors.map(error => error.code), ['disconnected', 'timeout']);
        t.api.disconnect(); assert.equal(registry(t).size, 0); assert.equal(t.timers.size, 0);
        t.api.connect(); t.sockets[2].open(); assert.equal(t.sockets[2].sent.length, 0);
    });
    test('listener and pending-cleanup registries are capped at 256 without shared-socket closure', () => {
        const t = setup(), socket = t.connect(), handles = [];
        for (let i = 0; i < 256; i++) handles.push(tracked(t));
        assert.equal(socket.sent.length, 1); assert.equal(tracked(t).errors[0].code, 'subscription_limit');
        reply(socket, socket.sent[0]); handles.forEach(handle => handle.cancel()); reply(socket, socket.sent[1]);
        assert.equal(registry(t).size, 0); assert.equal(registry(t).listeners, 0);
        for (let i = 0; i < 256; i++) {
            const p = tracked(t, {binding: 'acdc.queue.' + account + '.' + i.toString(16).padStart(32, '0')}); p.cancel();
        }
        assert.equal(registry(t).size, 256); assert.equal(Object.keys(registry(t).requests).length, 256);
        assert.equal(tracked(t, {binding: binding + '.new'}).errors[0].code, 'subscription_limit');
        t.advance(15000); assert.equal(Object.keys(registry(t).requests).length, 0); assert.equal(registry(t).size, 256);
        assert.equal(t.timers.size, 0); assert.equal(socket.closes, 0);
    });
    test('opt-in and legacy cannot borrow each other’s pending/acknowledged wire subscription', () => {
        const t = setup(), socket = t.connect();
        const legacyCancel = t.api.bind({accountId: account, binding, source: 'legacy', callback() {}});
        assert.equal(tracked(t).errors[0].code, 'binding_in_use'); reply(socket, socket.sent[0]);
        assert.equal(tracked(t).errors[0].code, 'binding_in_use'); legacyCancel();
        assert.equal(tracked(t).errors[0].code, 'binding_in_use'); reply(socket, socket.sent[1]);
        const next = tracked(t); reply(socket, socket.sent[2]); assert.equal(next.acknowledgements.length, 1);
        const second = setup(), current = second.connect(), p = tracked(second);
        const oldCancel = second.api.bind({accountId: account, binding, source: 'legacy', callback() {}});
        assert.equal(current.sent.length, 1); oldCancel(); assert.equal(current.sent.length, 1);
        reply(current, current.sent[0]); p.cancel(); assert.equal(current.sent.length, 2);
    });
    test('legacy ownership observer is bounded without limiting existing legacy wire behavior', () => {
        const t = setup(), socket = t.connect();
        for (let i = 0; i < 257; i++) {
            t.api.bind({accountId: account, binding: 'call.EVENT.' + i, source: 'legacy', callback() {}});
        }
        assert.equal(socket.sent.length, 257);
        assert.equal(Object.keys(t.api.getInfo().client.legacyPending).length, 256);
        assert.equal(tracked(t).errors[0].code, 'legacy_ownership_unknown');
        assert.equal(socket.closes, 0); t.api.disconnect(); assert.equal(t.api.getInfo().client.legacyUncertain, false);
    });
    test('configuration replacement cancels opt-in intent through existing explicit connect only', () => {
        const t = setup(), first = t.connect(), p = tracked(t); reply(first, first.sent[0]);
        t.monster.config.api.socket = 'wss://second.fixture.invalid/ws';
        const refused = tracked(t); assert.equal(refused.errors[0].code, 'configuration_unavailable'); assert.equal(t.sockets.length, 1);
        t.api.connect(); assert.equal(first.closes, 1); assert.equal(p.disconnects.length, 1); assert.equal(t.sockets.length, 2);
        t.sockets[1].open(); assert.equal(t.sockets[1].sent.length, 0); assert.equal(registry(t).size, 0);
    });
}
let result = 'PASS', failure;
try { main(); } catch (error) { result = 'FAIL'; failure = error.stack; console.error(failure); }
let after;
try { after = hashes(); assert.deepEqual(after, before, 'Inputs changed during fixture'); }
catch (error) { result = 'FAIL'; failure = (failure || '') + '\n' + error.stack; console.error(error.stack); }
if (after) fs.writeFileSync(path.join(directory, 'inputs.after.json'), JSON.stringify(after, null, 2) + '\n');
const receipt = {result, groups, source_pin: pin, candidate_sha256: source ? digest(source) : null,
    input_pins_stable: after ? JSON.stringify(before) === JSON.stringify(after) : false,
    network: false, browser: false, broker_readiness: false, runtime_deployment: false, directory, failure: failure || null};
fs.writeFileSync(path.join(directory, 'receipt.json'), JSON.stringify(receipt, null, 2) + '\n');
console.log(JSON.stringify(receipt));
if (result !== 'PASS') process.exitCode = 1;
