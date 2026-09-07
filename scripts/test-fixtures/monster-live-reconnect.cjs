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
module.exports = {createReconnectTracker, ReconnectError, matchReconnectCallRendering};
