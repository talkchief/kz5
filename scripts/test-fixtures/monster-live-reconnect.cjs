'use strict';
// Pure wire-order proof only. The caller owns actual transport closure, DOM,
// schema validation, deadlines and cleanup. No tokens, frames or DTOs retained.
const ID = /^[a-f0-9]{32}$/, REQUEST = /^lifecycle-[A-Za-z0-9-]{1,118}$/;
class ReconnectError extends Error {
    constructor(code) { super(code); this.name = 'ReconnectError'; this.code = code; }
}
function need(ok, code) { if (!ok) throw new ReconnectError(code); }
function exact(o, keys) {
    return o && typeof o === 'object' && !Array.isArray(o)
        && Object.keys(o).sort().join(',') === keys.slice().sort().join(',');
}
function ordinal(n) { return Number.isSafeInteger(n) && n > 0; }
function createReconnectTracker(options) {
    need(exact(options, ['accountId', 'queueId']) && ID.test(options.accountId) && ID.test(options.queueId),
        'invalid_reconnect_scope');
    const {accountId, queueId} = options, binding = 'queue_live.changed.' + queueId;
    let started = false, requestId;
    const proof = {oldConnection: 0, newConnection: 0, closeOrder: 0, subscribeOrder: 0,
        ackOrder: 0, requestOrder: 0, responseOrder: 0, complete: false};
    return Object.freeze({
        begin(input) {
            need(!started && exact(input, ['connection', 'order']) && ordinal(input.connection)
                && input.connection < Number.MAX_SAFE_INTEGER && ordinal(input.order), 'invalid_reconnect_begin');
            started = true; proof.oldConnection = input.connection; proof.closeOrder = input.order;
            return true;
        },
        sent(input) {
            if (!started) return false;
            need(exact(input, ['connection', 'order', 'requestId', 'action', 'accountId', 'binding'])
                && input.connection === proof.oldConnection + 1 && ordinal(input.order)
                && input.order > proof.closeOrder && proof.subscribeOrder === 0
                && input.action === 'subscribe' && input.accountId === accountId && input.binding === binding
                && typeof input.requestId === 'string' && REQUEST.test(input.requestId), 'invalid_reconnect_subscribe');
            proof.newConnection = input.connection; proof.subscribeOrder = input.order; requestId = input.requestId;
            return true;
        },
        reply(input) {
            if (!started) return false;
            need(exact(input, ['connection', 'order', 'requestId', 'status', 'data'])
                && proof.subscribeOrder > 0 && proof.ackOrder === 0 && input.connection === proof.newConnection
                && ordinal(input.order) && input.order > proof.subscribeOrder && input.requestId === requestId
                && input.status === 'success' && exact(input.data, ['subscribed', 'subscriptions'])
                && Array.isArray(input.data.subscribed) && input.data.subscribed.length === 1
                && input.data.subscribed[0] === binding && Array.isArray(input.data.subscriptions)
                && input.data.subscriptions.length === 1 && input.data.subscriptions[0] === binding,
            'invalid_reconnect_ack');
            proof.ackOrder = input.order;
            return true;
        },
        snapshot(input) {
            if (!started) return false;
            need(exact(input, ['requestOrder', 'responseOrder', 'noStore']) && ordinal(input.requestOrder)
                && ordinal(input.responseOrder) && input.responseOrder > input.requestOrder
                && typeof input.noStore === 'boolean', 'invalid_reconnect_snapshot');
            // Old in-flight responses and pre-ACK polling cannot establish repair.
            if (proof.ackOrder === 0 || input.requestOrder <= proof.ackOrder) return false;
            need(input.noStore && (!proof.complete || input.requestOrder > proof.responseOrder),
                'invalid_reconnect_snapshot');
            // The owner normally stops feeding once complete. Later ordered
            // snapshots do not overwrite the first repair receipt.
            if (proof.complete) return false;
            proof.requestOrder = input.requestOrder; proof.responseOrder = input.responseOrder; proof.complete = true;
            return true;
        },
        evidence() { return {...proof}; }
    });
}
function matchReconnectCallRendering(rendered, dto) {
    // dto must first pass the public detail schema/scope validator. Compare the
    // independently captured DOM values, not just the controller's DTO object.
    const queue = dto?.queues?.[0], calls = dto?.calls;
    need(rendered?.valid === true && queue && calls && Array.isArray(calls.rows)
        && Array.isArray(rendered.rows), 'invalid_reconnect_rendering');
    const waiting = queue.metrics_available ? String(queue.metrics.current_waiting) : '—';
    const handled = queue.metrics_available ? String(queue.metrics.current_handled) : '—';
    const rows = calls.rows.map(row => ({callId: row.call_id, state: row.status}));
    need(rendered.waiting === waiting && rendered.handled === handled
        && JSON.stringify(rendered.rows) === JSON.stringify(rows)
        && rendered.empty === (rows.length === 0), 'reconnect_call_rendering_mismatch');
    return true;
}
function createSummaryReconnectTracker(options) {
    need(exact(options, ['accountId', 'queueIds']) && typeof options.accountId === 'string' && ID.test(options.accountId)
        && Array.isArray(options.queueIds) && options.queueIds.length > 0 && options.queueIds.length <= 100
        && Array.from(options.queueIds).every(id => typeof id === 'string' && ID.test(id))
        && new Set(options.queueIds).size === options.queueIds.length, 'invalid_summary_reconnect_scope');
    const accountId = options.accountId, expected = new Set(options.queueIds.map(id => 'queue_live.changed.' + id));
    const acknowledged = new Set(), requests = new Set();
    let started = false, pending = null, lastAckOrder = 0;
    const proof = {oldConnection: 0, newConnection: 0, closeOrder: 0, subscribeOrder: 0,
        ackOrder: 0, requestOrder: 0, responseOrder: 0, complete: false,
        expectedBindings: expected.size, acknowledgedBindings: 0};
    return Object.freeze({
        begin(input) {
            need(!started && exact(input, ['connection', 'order']) && ordinal(input.connection)
                && input.connection < Number.MAX_SAFE_INTEGER && ordinal(input.order), 'invalid_reconnect_begin');
            started = true; proof.oldConnection = input.connection; proof.closeOrder = input.order;
            return true;
        },
        sent(input) {
            if (!started) return false;
            need(exact(input, ['connection', 'order', 'requestId', 'action', 'accountId', 'binding'])
                && input.connection === proof.oldConnection + 1 && ordinal(input.order)
                && input.order > Math.max(proof.closeOrder, lastAckOrder) && pending === null
                && input.action === 'subscribe' && input.accountId === accountId && expected.has(input.binding)
                && !acknowledged.has(input.binding) && acknowledged.size < expected.size
                && typeof input.requestId === 'string' && REQUEST.test(input.requestId) && !requests.has(input.requestId),
            'invalid_reconnect_subscribe');
            pending = {requestId: input.requestId, binding: input.binding, order: input.order};
            requests.add(input.requestId); proof.newConnection = input.connection;
            if (proof.subscribeOrder === 0) proof.subscribeOrder = input.order;
            return true;
        },
        reply(input) {
            if (!started) return false;
            need(exact(input, ['connection', 'order', 'requestId', 'status', 'data']) && pending !== null
                && input.connection === proof.newConnection && ordinal(input.order) && input.order > pending.order
                && input.requestId === pending.requestId && input.status === 'success'
                && exact(input.data, ['subscribed', 'subscriptions'])
                && Array.isArray(input.data.subscribed) && input.data.subscribed.length === 1
                && input.data.subscribed[0] === pending.binding && Array.isArray(input.data.subscriptions)
                && input.data.subscriptions.length === acknowledged.size + 1
                && new Set(input.data.subscriptions).size === input.data.subscriptions.length
                && input.data.subscriptions.every(binding => binding === pending.binding || acknowledged.has(binding)),
            'invalid_reconnect_ack');
            acknowledged.add(pending.binding); pending = null; lastAckOrder = input.order;
            proof.acknowledgedBindings = acknowledged.size;
            const final = acknowledged.size === expected.size;
            if (final) proof.ackOrder = input.order;
            return final;
        },
        snapshot(input) {
            if (!started) return false;
            need(exact(input, ['requestOrder', 'responseOrder', 'noStore']) && ordinal(input.requestOrder)
                && ordinal(input.responseOrder) && input.responseOrder > input.requestOrder
                && typeof input.noStore === 'boolean', 'invalid_reconnect_snapshot');
            if (proof.ackOrder === 0 || input.requestOrder <= proof.ackOrder) return false;
            need(input.noStore && (!proof.complete || input.requestOrder > proof.responseOrder), 'invalid_reconnect_snapshot');
            if (proof.complete) return false;
            proof.requestOrder = input.requestOrder; proof.responseOrder = input.responseOrder; proof.complete = true;
            return true;
        },
        evidence() { return {...proof}; }
    });
}
function matchReconnectSummaryRendering(rendered, dto) {
    // The caller validates the overview DTO and controller/account scope first.
    // selectedQueueId is the caller's known scope, not inferred from a count.
    need(rendered?.valid === true && Array.isArray(dto?.queues) && dto.queues.length > 0 && dto.queues.length <= 100
        && dto.calls === null && dto.agents === null && Array.isArray(rendered.cards)
        && rendered.cards.length === dto.queues.length && typeof rendered.selectedQueueId === 'string'
        && ID.test(rendered.selectedQueueId), 'invalid_reconnect_summary_rendering');
    need(dto.queues.every(q => q && typeof q.id === 'string' && ID.test(q.id)
        && typeof q.metrics_available === 'boolean' && (!q.metrics_available || q.metrics
            && Number.isSafeInteger(q.metrics.current_waiting) && q.metrics.current_waiting >= 0
            && Number.isSafeInteger(q.metrics.current_handled) && q.metrics.current_handled >= 0))
        && new Set(dto.queues.map(q => q.id)).size === dto.queues.length,
    'invalid_reconnect_summary_rendering');
    const byId = (a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
    const expected = dto.queues.map(q => ({id: q.id, waiting: q.metrics_available ? String(q.metrics.current_waiting) : '—',
        handled: q.metrics_available ? String(q.metrics.current_handled) : '—'})).sort(byId);
    need(rendered.cards.every(c => exact(c, ['id', 'waiting', 'handled']) && typeof c.id === 'string' && ID.test(c.id)
        && typeof c.waiting === 'string' && typeof c.handled === 'string'), 'invalid_reconnect_summary_rendering');
    const cards = rendered.cards.slice().sort(byId), selected = expected.find(c => c.id === rendered.selectedQueueId);
    need(JSON.stringify(cards) === JSON.stringify(expected) && rendered.queueCount === String(expected.length)
        && selected && rendered.waiting === selected.waiting && rendered.handled === selected.handled,
    'reconnect_summary_rendering_mismatch');
    return true;
}
module.exports = {createReconnectTracker, ReconnectError, matchReconnectCallRendering,
    createSummaryReconnectTracker, matchReconnectSummaryRendering};
