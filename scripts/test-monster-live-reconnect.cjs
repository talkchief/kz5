#!/usr/bin/env node
'use strict';
// Pure offline order/scope fixtures: no browser/network/config/credential access.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const helper = path.join(__dirname, 'test-fixtures/monster-live-reconnect.cjs');
const hashes = () => [__filename, helper].map(file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex'));
const before = hashes(), {createReconnectTracker, ReconnectError, matchReconnectCallRendering,
    createSummaryReconnectTracker, matchReconnectSummaryRendering} = require(helper);
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
function summaryPending(ids = [Q, OTHER]) {
    const t = createSummaryReconnectTracker({accountId: A, queueIds: ids}); t.begin({connection: 1, order: 10}); return t;
}
function summaryFirstAck() { const t = summaryPending(); t.sent(sent()); assert.equal(t.reply(reply()), false); return t; }
function summarySecond(t) { t.sent(sent({order: 14, requestId: 'lifecycle-second', binding: 'queue_live.changed.' + OTHER})); }
function summaryFinalReply(change = {}) { return reply({order: 15, requestId: 'lifecycle-second',
    data: {subscribed: ['queue_live.changed.' + OTHER], subscriptions: ['queue_live.changed.' + OTHER, BINDING]}, ...change}); }
function summaryRendering() {
    const dto = {calls: null, agents: null, queues: [
        {id: Q, metrics_available: true, metrics: {current_waiting: 1, current_handled: 0}},
        {id: OTHER, metrics_available: false, metrics: null}]};
    const rendered = {valid: true, selectedQueueId: Q, waiting: '1', handled: '0', queueCount: '2',
        cards: [{id: Q, waiting: '1', handled: '0'}, {id: OTHER, waiting: '—', handled: '—'}]};
    return {dto, rendered};
}
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
    test('summary scope is exactly one to100 unique concrete queue IDs', () => {
        for (const input of [null, {}, {accountId: A, queueIds: []}, {accountId: A, queueIds: [Q, Q]},
            {accountId: A, queueIds: [Q, '*']}, {accountId: A, queueIds: new Array(1)},
            {accountId: A, queueIds: Array.from({length: 101}, (_, i) => i.toString(16).padStart(32, '0'))},
            {accountId: A.toUpperCase(), queueIds: [Q]}, {accountId: A, queueIds: [Q], token: 'FIXTURE_ONLY_SECRET'}]) {
            rejects(() => createSummaryReconnectTracker(input), 'invalid_summary_reconnect_scope');
        }
        const ids = [Q], t = createSummaryReconnectTracker({accountId: A, queueIds: ids}); ids[0] = OTHER;
        assert.equal(t.sent(sent()), false); t.begin({connection: 1, order: 10}); t.sent(sent());
        assert.equal(t.reply(reply()), true); assert.equal(t.evidence().expectedBindings, 1);
    });
    test('100 sequential page subscriptions require100 real exact cumulative ACKs', () => {
        const ids = Array.from({length: 100}, (_, i) => i.toString(16).padStart(32, '0'));
        const t = summaryPending(ids), accumulated = []; let order = 10;
        for (let i = 0; i < ids.length; i++) {
            const binding = 'queue_live.changed.' + ids[i], requestId = 'lifecycle-summary-' + i;
            assert.equal(t.sent(sent({order: ++order, binding, requestId})), true);
            assert.equal(t.snapshot({requestOrder: ++order, responseOrder: ++order, noStore: true}), false);
            accumulated.push(binding);
            assert.equal(t.reply(reply({order: ++order, requestId,
                data: {subscribed: [binding], subscriptions: accumulated.slice().reverse()}})), i === 99);
            assert.equal(t.evidence().acknowledgedBindings, i + 1);
            assert.equal(t.evidence().ackOrder, i === 99 ? order : 0);
            assert.equal(t.evidence().complete, false);
        }
        assert.equal(t.snapshot({requestOrder: ++order, responseOrder: ++order, noStore: true}), true);
        assert.equal(t.evidence().expectedBindings, 100); assert.equal(t.evidence().complete, true);
    });
    test('summary rejects overlapping subscriptions and old or third connections', () => {
        const t = summaryPending(); t.sent(sent());
        rejects(() => summarySecond(t), 'invalid_reconnect_subscribe');
        for (const bad of [{connection: 1}, {connection: 3}, {accountId: OTHER},
            {binding: 'queue_live.changed.' + A}, {action: 'unsubscribe'}]) {
            rejects(() => summaryPending().sent(sent(bad)), 'invalid_reconnect_subscribe');
        }
        assert.equal(t.evidence().acknowledgedBindings, 0);
    });
    test('summary cumulative ACK rejects missing extra duplicate or wrong newly subscribed bindings', () => {
        for (const data of [{subscribed: ['queue_live.changed.' + OTHER], subscriptions: ['queue_live.changed.' + OTHER]},
            {subscribed: [BINDING], subscriptions: [BINDING, 'queue_live.changed.' + OTHER]},
            {subscribed: ['queue_live.changed.' + OTHER], subscriptions: [BINDING, BINDING]},
            {subscribed: ['queue_live.changed.' + OTHER], subscriptions: [BINDING, 'queue_live.changed.' + A]},
            {subscribed: ['queue_live.changed.' + OTHER], subscriptions: [BINDING, 'queue_live.changed.' + OTHER, 'extra']}]) {
            const t = summaryFirstAck(); summarySecond(t);
            rejects(() => t.reply(summaryFinalReply({data})), 'invalid_reconnect_ack');
            assert.equal(t.evidence().acknowledgedBindings, 1); assert.equal(t.evidence().ackOrder, 0);
        }
    });
    test('summary cannot replay request IDs ACKs or already acknowledged page bindings', () => {
        const t = summaryFirstAck();
        rejects(() => t.reply(reply({order: 14})), 'invalid_reconnect_ack');
        rejects(() => t.sent(sent({order: 14, requestId: 'lifecycle-next'})), 'invalid_reconnect_subscribe');
        rejects(() => t.sent(sent({order: 14, binding: 'queue_live.changed.' + OTHER})), 'invalid_reconnect_subscribe');
        rejects(() => t.sent(sent({order: 13, requestId: 'lifecycle-second', binding: 'queue_live.changed.' + OTHER})), 'invalid_reconnect_subscribe');
        summarySecond(t);
        for (const bad of [{connection: 1}, {order: 14}, {requestId: 'lifecycle-fixture-2'}, {status: 'error'}]) {
            rejects(() => t.reply(summaryFinalReply(bad)), 'invalid_reconnect_ack');
        }
        assert.equal(t.reply(summaryFinalReply()), true);
        rejects(() => t.reply(summaryFinalReply({order: 16})), 'invalid_reconnect_ack');
    });
    test('summary snapshot must start after final ACK not just one page ACK', () => {
        const t = summaryFirstAck();
        assert.equal(t.snapshot({requestOrder: 14, responseOrder: 15, noStore: true}), false);
        summarySecond(t); assert.equal(t.reply(summaryFinalReply()), true);
        assert.equal(t.snapshot({requestOrder: 14, responseOrder: 16, noStore: true}), false);
        assert.equal(t.snapshot({requestOrder: 15, responseOrder: 16, noStore: true}), false);
        rejects(() => t.snapshot({requestOrder: 16, responseOrder: 17, noStore: false}), 'invalid_reconnect_snapshot');
        assert.equal(t.snapshot({requestOrder: 16, responseOrder: 17, noStore: true}), true);
        rejects(() => t.snapshot({requestOrder: 16, responseOrder: 18, noStore: true}), 'invalid_reconnect_snapshot');
        assert.equal(t.snapshot({requestOrder: 18, responseOrder: 19, noStore: true}), false);
    });
    test('summary evidence is bounded numeric metadata and preserves first receipt', () => {
        const t = summaryFirstAck(); summarySecond(t); t.reply(summaryFinalReply());
        t.snapshot({requestOrder: 16, responseOrder: 17, noStore: true});
        const expected = {oldConnection: 1, newConnection: 2, closeOrder: 10, subscribeOrder: 12,
            ackOrder: 15, requestOrder: 16, responseOrder: 17, complete: true, expectedBindings: 2, acknowledgedBindings: 2};
        assert.deepEqual(t.evidence(), expected);
        const copy = t.evidence(); copy.acknowledgedBindings = 99; assert.deepEqual(t.evidence(), expected);
        assert(Object.values(t.evidence()).every(v => typeof v === 'boolean' || Number.isSafeInteger(v)));
    });
    test('summary rendering matches every card and selected values with unknown-as-dash', () => {
        const {dto, rendered} = summaryRendering();
        assert.equal(matchReconnectSummaryRendering(rendered, dto), true);
        assert.equal(matchReconnectSummaryRendering({...rendered, cards: rendered.cards.slice().reverse()}, dto), true);
        assert.equal(matchReconnectSummaryRendering({...rendered, selectedQueueId: OTHER, waiting: '—', handled: '—'}, dto), true);
    });
    test('summary stale counters page count selected values or foreign cards cannot pass', () => {
        for (const change of [r => r.cards[0].waiting = '0', r => r.cards[1].waiting = '0', r => r.queueCount = '999',
            r => r.waiting = '0', r => r.handled = '1', r => r.selectedQueueId = A,
            r => r.cards[1].id = Q, r => r.cards[1].id = A, r => r.selectedQueueId = OTHER]) {
            const {dto, rendered} = summaryRendering(); change(rendered);
            rejects(() => matchReconnectSummaryRendering(rendered, dto), 'reconnect_summary_rendering_mismatch');
        }
    });
    test('summary rendering rejects missing scope cards or malformed detail-shaped DTO', () => {
        for (const change of [(r, d) => r.valid = false, r => delete r.selectedQueueId, r => r.cards.pop(),
            (r, d) => d.calls = {}, (r, d) => d.queues[1].id = Q, r => r.cards[0].extra = 'FIXTURE_ONLY_SECRET']) {
            const {dto, rendered} = summaryRendering(); change(rendered, dto);
            rejects(() => matchReconnectSummaryRendering(rendered, dto), 'invalid_reconnect_summary_rendering');
        }
    });
    console.log('All ' + groups + ' reconnect tracker groups passed (offline only).');
} finally { assert.deepEqual(hashes(), before, 'Reconnect fixture inputs changed'); }
