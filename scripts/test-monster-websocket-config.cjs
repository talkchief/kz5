'use strict';
// Source-only AMD execution: fake sockets/timers; no network or tenant changes.
const fs = require('node:fs'), vm = require('node:vm'), path = require('node:path');
const assert = require('node:assert/strict');
const sourcePath = process.argv[2] || '/usr/local/src/kazoo5-installer/monster-ui/src/js/lib/monster.socket.js';
const source = fs.readFileSync(sourcePath, 'utf8');
// An explicit existing dependency permits private patched-source fixtures without
// copying node_modules or changing the configured source checkout.
const lodash = require(process.argv[3] || path.resolve(path.dirname(sourcePath), '../../../node_modules/lodash'));

function setup(uri, protocol = 'https:', supportsSocket = true) {
    let api, nextId = 1;
    const sockets = [], timers = new Map(), publications = [];
    class FakeSocket {
        static CONNECTING = 0; static OPEN = 1; static CLOSING = 2; static CLOSED = 3;
        constructor(url) { assert.equal(typeof url, 'string'); this.url = url; this.readyState = 0; this.events = new Map(); this.sent = []; sockets.push(this); }
        addEventListener(name, f) { this.events.set(name, [...(this.events.get(name) || []), f]); }
        emit(name, event) { (this.events.get(name) || []).forEach(f => f(event)); }
        open() { this.readyState = 1; this.emit('open', {}); }
        close() { this.readyState = 3; this.emit('close', {wasClean: true}); }
        fail() { this.readyState = 3; this.emit('close', {wasClean: false}); }
        send(data) { assert.equal(this.readyState, 1); this.sent.push(JSON.parse(data)); }
        message(data) { this.emit('message', {data: JSON.stringify(data)}); }
    }
    const monster = {
        config: {api: {socket: uri}}, isDev: () => false,
        pub: (name, data) => publications.push({name, data}),
        util: {guid: () => 'request-' + nextId++, getAuthToken: () => 'offline-fixture-token'},
        waterfall: (steps, done) => steps[0](done)
    };
    vm.runInNewContext(source, {
        define(factory) { api = factory(name => name === 'lodash' ? lodash : monster); },
        WebSocket: supportsSocket ? FakeSocket : undefined, URL, window: {location: {protocol}}, console,
        setTimeout(f, delay) { const id = nextId++; timers.set(id, {f, delay}); return id; },
        clearTimeout(id) { timers.delete(id); }
    }, {filename: sourcePath});
    return {api, monster, sockets, timers, publications,
        tick() { const [id, timer] = timers.entries().next().value; timers.delete(id); timer.f(); }};
}

for (const uri of [undefined, null, '', false, 'undefined', 'null', '/websocket', '//host/websocket',
    'http://example.invalid/websocket', 'ws://example.invalid/websocket', 'wss://undefined/websocket',
    'wss://example.invalid/undefined', 'wss://example.invalid/null', 'wss://user:password@example.invalid/websocket',
    'wss://example.invalid/websocket#token', 'wss://example.invalid/websocket#', ' wss://example.invalid/websocket', 'wss://']) {
    const t = setup(uri);
    for (let i = 0; i < 20; i++) assert.equal(t.api.connect(), false);
    assert.equal(t.sockets.length, 0); assert.equal(t.timers.size, 0);
    assert.equal(t.api.getInfo().isConfigured, false); assert.equal(t.api.getInfo().isConnected, false);
    assert(t.api.getInfo().configurationError); assert.equal(t.publications.length, 1);
    assert.equal(t.publications[0].name, 'socket.unavailable');
    assert(!JSON.stringify(t.publications).includes('password'));
}
{
    const t = setup('wss://example.invalid/websocket', 'https:', false);
    assert.equal(t.api.connect(), false); assert.equal(t.api.getInfo().configurationError, 'unsupported_browser');
    assert.equal(t.sockets.length, 0); assert.equal(t.timers.size, 0);
}
{
    const t = setup('wss://example.invalid/websocket');
    assert.equal(t.api.getInfo().isConfigured, true); assert.equal(t.api.getInfo().isConnected, false);
    assert.equal(t.api.connect(), true); assert.equal(t.sockets.length, 1);
    const ws = t.sockets[0]; assert.equal(ws.url, 'wss://example.invalid/websocket');
    t.api.connect(); assert.equal(t.sockets.length, 1, 'Duplicate connect is not another transport');
    ws.open(); assert.equal(t.api.getInfo().isConnected, true);
    let events = 0;
    const unbind = t.api.bind({accountId: 'fixture-account', binding: 'call.CHANNEL_CREATE.*', source: 'fixture', callback: () => events++});
    const subscribe = ws.sent[0];
    assert.equal(subscribe.action, 'subscribe'); assert.equal(subscribe.auth_token, 'offline-fixture-token');
    assert.equal(subscribe.data.account_id, 'fixture-account'); assert.equal(subscribe.data.binding, 'call.CHANNEL_CREATE.*');
    ws.message({action: 'reply', status: 'success', request_id: subscribe.request_id, data: {}});
    ws.message({action: 'event', subscribed_key: 'call.CHANNEL_CREATE.*', data: {call_id: 'offline-call'}});
    assert.equal(events, 1);
    unbind(); assert.equal(ws.sent[1].action, 'unsubscribe');
    ws.fail(); assert.equal(t.api.getInfo().isConnected, false); assert.equal(t.timers.size, 1);
    t.tick(); assert.equal(t.sockets.length, 2, 'Valid configured endpoints retain transient reconnection');
    t.sockets[1].open(); assert.equal(t.api.getInfo().isConnected, true); assert.equal(t.timers.size, 0);
    t.api.disconnect(); assert.equal(t.timers.size, 0); assert.equal(t.api.getInfo().isConnected, false);
}
{
    const t = setup('ws://example.invalid/websocket', 'http:');
    t.api.connect(); t.sockets[0].fail(); assert.equal(t.timers.size, 1);
    delete t.monster.config.api.socket;
    t.tick(); assert.equal(t.sockets.length, 1); assert.equal(t.timers.size, 0);
    assert.equal(t.api.getInfo().configurationError, 'not_configured');
    t.monster.config.api.socket = 'ws://example.invalid/websocket';
    t.api.connect(); assert.equal(t.sockets.length, 2);
}
console.log('PASS: missing/invalid/placeholder/mixed-content config creates no socket or retry; explicit capability; valid connect, authenticated subscribe/event/unsubscribe, disconnect and transient reconnect');
