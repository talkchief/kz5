#!/usr/bin/env node
'use strict';
// Pure offline order/scope fixtures: no browser/network/config/credential access.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const helper = path.join(__dirname, 'test-fixtures/monster-live-reconnect.cjs');
const hashes = () => [__filename, helper].map(file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex'));
const before = hashes(), {createReconnectTracker, ReconnectError, matchReconnectCallRendering} = require(helper);
const A = 'a'.repeat(32), Q = 'b'.repeat(32), OTHER = 'c'.repeat(32), BINDING = 'queue_live.changed.' + Q;
let groups = 0;
function test(name, work) { work(); groups++; console.log('PASS ' + name); }
function tracker() { return createReconnectTracker({accountId: A, queueId: Q}); }
function sent(change = {}) { return {connection: 2, order: 12, requestId: 'lifecycle-fixture-2',
    action: 'subscribe', accountId: A, binding: BINDING, ...change}; }
function reply(change = {}) { return {connection: 2, order: 13, requestId: 'lifecycle-fixture-2', status: 'success',
    data: {subscribed: [BINDING], subscriptions: [BINDING]}, ...change}; }
function pending() { const t = tracker(); assert.equal(t.begin({connection: 1, order: 10}), true); return t; }
function subscribed() { const t = pending(); assert.equal(t.sent(sent()), true); return t; }
function acknowledged() { const t = subscribed(); assert.equal(t.reply(reply()), true); return t; }
function rejects(work, code) { assert.throws(work, e => e instanceof ReconnectError && e.code === code && e.message === code); }
try {
    test('visible counts and ordered rows must match validated DTO, including unknown and empty', () => {
        const dto = {queues: [{metrics_available: true, metrics: {current_waiting: 1, current_handled: 0}}],
            calls: {rows: [{call_id: 'synthetic-call', status: 'waiting'}]}};
        const rendered = {valid: true, waiting: '1', handled: '0', rows: [{callId: 'synthetic-call', state: 'waiting'}], empty: false};
        assert.equal(matchReconnectCallRendering(rendered, dto), true);
        for (const change of [{waiting: '0'}, {handled: '1'}, {rows: []}, {empty: true},
            {rows: [{callId: 'other-call', state: 'waiting'}]}, {rows: [{callId: 'synthetic-call', state: 'handled'}]}]) {
            rejects(() => matchReconnectCallRendering({...rendered, ...change}, dto), 'reconnect_call_rendering_mismatch');
        }
        rejects(() => matchReconnectCallRendering({...rendered, valid: false}, dto), 'invalid_reconnect_rendering');
        const unknown = {queues: [{metrics_available: false}], calls: {rows: []}};
        const empty = {valid: true, waiting: '—', handled: '—', rows: [], empty: true};
        assert.equal(matchReconnectCallRendering(empty, unknown), true);
        rejects(() => matchReconnectCallRendering({...empty, waiting: '0'}, unknown), 'reconnect_call_rendering_mismatch');
        dto.calls.rows = []; dto.queues[0].metrics.current_waiting = 0;
        assert.equal(matchReconnectCallRendering({...empty, waiting: '0', handled: '0'}, dto), true);
        dto.calls.rows = [{call_id: 'one', status: 'waiting'}, {call_id: 'two', status: 'handled'}];
        rejects(() => matchReconnectCallRendering({...rendered, rows: [{callId: 'two', state: 'handled'},
            {callId: 'one', state: 'waiting'}]}, dto), 'reconnect_call_rendering_mismatch');
    });
    test('scope is exact account and queue with no extra credential field', () => {
        for (const input of [null, {}, {accountId: A, queueId: '*'}, {accountId: OTHER.toUpperCase(), queueId: Q},
            {accountId: A, queueId: Q, auth_token: 'FIXTURE_ONLY_SECRET'}]) {
            rejects(() => createReconnectTracker(input), 'invalid_reconnect_scope');
        }
    });
    test('pre-begin traffic is ignored and cannot complete proof', () => {
        const t = tracker(); assert.equal(t.sent(sent()), false); assert.equal(t.reply(reply()), false);
        assert.equal(t.snapshot({requestOrder: 1, responseOrder: 2, noStore: true}), false);
        assert.equal(t.evidence().complete, false);
    });
    test('begin requires positive safe ordinals and cannot restart proof', () => {
        for (const bad of [{connection: 0, order: 1}, {connection: 1, order: 0}, {connection: 1.1, order: 2},
            {connection: Number.MAX_SAFE_INTEGER, order: 1}, {connection: 1, order: 1, extra: true}]) {
            rejects(() => tracker().begin(bad), 'invalid_reconnect_begin');
        }
        const t = pending(); rejects(() => t.begin({connection: 2, order: 20}), 'invalid_reconnect_begin');
    });
    test('only next-connection exact selected subscribe is admitted', () => {
        for (const bad of [{connection: 1}, {connection: 3}, {order: 10}, {action: 'unsubscribe'},
            {accountId: OTHER}, {binding: 'queue_live.changed.' + OTHER}, {binding: 'queue_live.changed.*'},
            {requestId: ''}, {requestId: 'lifecycle-' + 'x'.repeat(119)}, {auth_token: 'FIXTURE_ONLY_SECRET'}]) {
            rejects(() => pending().sent(sent(bad)), 'invalid_reconnect_subscribe');
        }
    });
    test('duplicate subscribe and a third connection cannot replace current attempt', () => {
        const t = subscribed(); rejects(() => t.sent(sent({order: 14})), 'invalid_reconnect_subscribe');
        rejects(() => t.sent(sent({connection: 3, order: 15})), 'invalid_reconnect_subscribe');
        assert.equal(t.evidence().subscribeOrder, 12);
    });
    test('ACK requires actual same-connection same-request success after send', () => {
        rejects(() => pending().reply(reply()), 'invalid_reconnect_ack');
        for (const bad of [{connection: 1}, {connection: 3}, {order: 12}, {requestId: 'lifecycle-old'}, {status: 'error'}]) {
            rejects(() => subscribed().reply(reply(bad)), 'invalid_reconnect_ack');
        }
    });
    test('ACK sets must contain exactly the selected binding', () => {
        for (const data of [{subscribed: [], subscriptions: [BINDING]}, {subscribed: [BINDING], subscriptions: []},
            {subscribed: [BINDING, BINDING], subscriptions: [BINDING]},
            {subscribed: [BINDING], subscriptions: [BINDING, 'queue_live.changed.' + OTHER]},
            {subscribed: [BINDING], subscriptions: [BINDING], extra: true}]) {
            rejects(() => subscribed().reply(reply({data})), 'invalid_reconnect_ack');
        }
    });
    test('duplicate ACK is rejected without altering receipt', () => {
        const t = acknowledged(); rejects(() => t.reply(reply({order: 14})), 'invalid_reconnect_ack');
        assert.equal(t.evidence().ackOrder, 13);
    });
    test('pre-ACK and already in-flight GET replies cannot complete reconnect', () => {
        const t = subscribed(); assert.equal(t.snapshot({requestOrder: 11, responseOrder: 14, noStore: true}), false);
        t.reply(reply());
        for (const requestOrder of [9, 12, 13]) assert.equal(t.snapshot({requestOrder, responseOrder: 15, noStore: true}), false);
        assert.equal(t.evidence().complete, false);
    });
    test('post-ACK response requires increasing order and no-store', () => {
        for (const input of [{requestOrder: 14, responseOrder: 14, noStore: true},
            {requestOrder: 14, responseOrder: 15, noStore: false}, {requestOrder: 14, responseOrder: 15, noStore: 'true'},
            {requestOrder: 14, responseOrder: 15, noStore: true, body: 'FIXTURE_ONLY_SECRET'}]) {
            rejects(() => acknowledged().snapshot(input), 'invalid_reconnect_snapshot');
        }
    });
    test('one actual ordered ACK-following snapshot completes bounded proof', () => {
        const t = acknowledged(); assert.equal(t.snapshot({requestOrder: 14, responseOrder: 15, noStore: true}), true);
        assert.deepEqual(t.evidence(), {oldConnection: 1, newConnection: 2, closeOrder: 10, subscribeOrder: 12,
            ackOrder: 13, requestOrder: 14, responseOrder: 15, complete: true});
        const copy = t.evidence(); copy.complete = false; assert.equal(t.evidence().complete, true);
    });
    test('replayed snapshot cannot replace completed proof', () => {
        const t = acknowledged(); t.snapshot({requestOrder: 14, responseOrder: 15, noStore: true});
        rejects(() => t.snapshot({requestOrder: 14, responseOrder: 16, noStore: true}), 'invalid_reconnect_snapshot');
        assert.equal(t.snapshot({requestOrder: 17, responseOrder: 18, noStore: true}), false);
        assert.equal(t.evidence().responseOrder, 15);
    });
    test('receipt contains only ordinals and booleans, never scope or request payload', () => {
        const t = acknowledged(); t.snapshot({requestOrder: 14, responseOrder: 15, noStore: true});
        assert(Object.values(t.evidence()).every(v => typeof v === 'boolean' || Number.isSafeInteger(v)));
        for (const value of [A, Q, BINDING, 'lifecycle-fixture-2']) assert(!JSON.stringify(t.evidence()).includes(value));
    });
    console.log('All ' + groups + ' reconnect tracker groups passed (offline only).');
} finally { assert.deepEqual(hashes(), before, 'Reconnect fixture inputs changed'); }
