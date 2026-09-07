'use strict';
// Observes the deployed browser's own traffic and DOM. No network, call control,
// state injection, refresh invocation or synthetic response/event publication.
const crypto = require('node:crypto');
const {performance} = require('node:perf_hooks');
const {validateDetail, validateEvent} = require('./queue-live-observer.cjs');
const ID = /^[a-f0-9]{32}$/, CALL = /^1-[1-9][0-9]*@127\.0\.0\.52$/;
const hash = text => crypto.createHash('sha256').update(text).digest('hex');
class BrowserCallError extends Error { constructor(code) { super(code); this.code = code; } }
function need(ok, code) { if (!ok) throw new BrowserCallError(code); }
function exact(o, keys) { return o && typeof o === 'object' && !Array.isArray(o)
    && Object.keys(o).sort().join(',') === keys.slice().sort().join(','); }
function readRenderedCall({accountId, queueId}) {
    // One read-only browser turn captures the actual mounted DOM and snapshot.
    // DTO bytes are used in memory for response matching, never persisted.
    const monster = window.require('monster'), app = monster.apps.acdc, flags = app.appFlags.acdc;
    const c = flags.liveDashboardController, s = flags.liveDashboardSnapshot;
    const root = document.querySelector('.acdc-live-dashboard');
    function visible(node) {
        if (!node?.isConnected || !node.getClientRects().length) return false;
        for (let element = node; element && element.nodeType === 1; element = element.parentElement) {
            const style = window.getComputedStyle(element);
            if (element.hidden || style.display === 'none' || ['hidden', 'collapse'].includes(style.visibility)
                || style.opacity === '0') return false;
        }
        return true;
    }
    const valid = Boolean(c && s && root) && monster.apps.getActiveApp() === 'acdc' && app.accountId === accountId
        && monster.apps.auth.currentAccount?.id === accountId && c.view?.[0] === root && visible(root)
        && flags.currentTab === 'dashboard' && !c.stopped
        && c.accountId === accountId && c.queueId === queueId && s.accountId === accountId && s.queueId === queueId
        && !c.inFlight && !c.dirty && !c.coalesceTimer && !c.admitting && !c.admissionTimer
        && app.liveTransportState(c) === 'acknowledged' && root.getAttribute('aria-busy') === 'false'
        && !root.querySelector('.acdc-live-refresh-error') && !root.querySelector('.acdc-live-freshness.is-stale')
        && app.liveSnapshotValid(s.results.live, accountId, queueId, s.page);
    if (!valid) return {valid: false};
    const tableRows = Array.from(root.querySelectorAll('.acdc-live-calls-panel tbody tr'));
    const waiting = root.querySelector('.acdc-live-waiting strong'), handled = root.querySelector('.acdc-live-handling strong');
    if (!visible(waiting) || !visible(handled) || !tableRows.every(visible)) return {valid: false};
    if (!tableRows.every(row => {
        const status = row.querySelector('.acdc-status');
        if (!status) return true;
        const cells = Array.from(row.querySelectorAll('td'));
        return visible(status) && cells.length === 4 && cells.every(visible);
    })) return {valid: false};
    const rows = tableRows
        .filter(row => row.querySelector('.acdc-status')).map(row => {
            const cells = row.querySelectorAll('td'), status = row.querySelector('.acdc-status');
            return {callId: cells.length === 4 ? cells[1].textContent : null,
                state: status.classList.contains('acdc-live-status-waiting') ? 'waiting'
                    : status.classList.contains('acdc-live-status-handling') ? 'handled' : 'unknown'};
        });
    return {valid: true, generation: c.generation, receivedAt: s.receivedAt, dto: JSON.stringify(s.results.live), rows,
        waiting: waiting.textContent, handled: handled.textContent,
        empty: visible(root.querySelector('.acdc-live-calls-panel .acdc-empty-cell'))};
}
function createBrowserCallObserver(options) {
    need(exact(options, ['accountId', 'queueId', 'readPage', 'getOrder', 'checkClean'])
        && ID.test(options.accountId) && ID.test(options.queueId)
        && ['readPage', 'getOrder', 'checkClean'].every(k => typeof options[k] === 'function'), 'invalid_browser_observer_options');
    const {accountId, queueId, readPage, getOrder, checkClean} = options;
    const events = [], phases = [];
    let latestResponse = null, responseCount = 0;
    let ready = false, busy = false, closed = false, callId, generation, boundary = null, lastPending = null;
    const snapshotProof = sample => ({request_order: sample.requestOrder, response_order: sample.responseOrder,
        response_sha256: sample.hash, waiting: sample.waiting, handled: sample.handled,
        active: sample.rows.length, generated_at: sample.generatedAt});
    function match(page, phase, caller) {
        if (!page?.valid || typeof page.dto !== 'string') { lastPending = 'render_not_ready'; return null; }
        if (ready && page.generation !== generation) { lastPending = 'controller_changed'; return null; }
        const digest = hash(page.dto), waiting = phase === 'waiting' ? 1 : 0, handled = phase === 'handled' ? 1 : 0;
        const wanted = phase === 'gone' || phase === 'empty' ? [] : [{callId: caller, state: phase}];
        if (page.waiting !== String(waiting) || page.handled !== String(handled)) { lastPending = 'rendered_counts_mismatch'; return null; }
        if (page.empty !== (wanted.length === 0) || JSON.stringify(page.rows) !== JSON.stringify(wanted)) {
            lastPending = 'rendered_rows_mismatch'; return null;
        }
        const r = latestResponse;
        const matches = r && r.hash === digest && r.complete && r.waiting === waiting && r.handled === handled
            && page.receivedAt >= r.requestAt && JSON.stringify(r.rows) === JSON.stringify(wanted);
        lastPending = matches ? null : 'rendered_response_mismatch'; return matches ? r : null;
    }
    async function boundedRead(deadline) {
        const remaining = deadline - performance.now(); need(remaining > 0, 'browser_phase_timeout');
        let timer;
        try { return await Promise.race([Promise.resolve().then(readPage), new Promise((_, reject) => {
            timer = setTimeout(() => reject(new BrowserCallError('browser_phase_timeout')), remaining);
        })]); } finally { clearTimeout(timer); }
    }
    const api = {
        recordEvent(frame, order) {
            need(!closed && Number.isSafeInteger(order) && order > 0 && events.length < 128, 'browser_event_limit_or_order');
            validateEvent(frame, accountId, queueId);
            need(!events.length || order > events.at(-1).order, 'browser_event_order');
            events.push({order});
        },
        recordResponse(input) {
            need(!closed && exact(input, ['body', 'requestOrder', 'responseOrder', 'requestAt', 'noStore'])
                && responseCount < 128 && input.noStore === true
                && Number.isSafeInteger(input.requestOrder) && input.requestOrder > 0
                && Number.isSafeInteger(input.responseOrder) && input.responseOrder > input.requestOrder
                && Number.isSafeInteger(input.requestAt) && input.requestAt > 0
                && (!latestResponse || input.requestOrder > latestResponse.requestOrder), 'browser_response_limit_or_order');
            const d = validateDetail(input.body, accountId, queueId), calls = d.calls, q = d.queues[0];
            latestResponse = {requestOrder: input.requestOrder, responseOrder: input.responseOrder, requestAt: input.requestAt,
                hash: hash(JSON.stringify(d)), generatedAt: d.generated_at,
                complete: d.source.status === 'available' && calls.available && calls.complete && !calls.truncated,
                waiting: q.metrics_available ? q.metrics.current_waiting : null,
                handled: q.metrics_available ? q.metrics.current_handled : null,
                rows: calls.rows.map(r => ({callId: r.call_id, state: r.status}))};
            responseCount++;
        },
        async ready() {
            need(!ready && !closed && !busy, 'browser_observer_already_started');
            busy = true; const deadline = performance.now() + 10000;
            try {
                while (performance.now() < deadline) {
                    checkClean(); const page = await boundedRead(deadline), sample = match(page, 'empty');
                    if (sample && performance.now() < deadline) {
                        need(Number.isSafeInteger(page.generation) && page.generation > 0, 'browser_controller_generation_required');
                        generation = page.generation; boundary = getOrder();
                        need(Number.isSafeInteger(boundary) && boundary >= sample.responseOrder, 'browser_ready_order');
                        checkClean(); ready = true; return snapshotProof(sample);
                    }
                    await new Promise(resolve => setTimeout(resolve, Math.min(50, Math.max(1, deadline - performance.now()))));
                }
                need(false, 'browser_empty_detail_timeout');
            } finally { busy = false; }
        },
        async waitForPhase(caller, phase, timeout) {
            need(ready && !closed && !busy && timeout === 10000 && CALL.test(caller)
                && phase === ['waiting', 'handled', 'gone'][phases.length]
                && (!callId || caller === callId), 'invalid_browser_phase_sequence');
            busy = true; callId = caller;
            const deadline = performance.now() + timeout;
            try {
                while (performance.now() < deadline) {
                    checkClean(); const page = await boundedRead(deadline), sample = match(page, phase, caller);
                    const hint = sample && events.find(e => e.order > boundary && e.order < sample.requestOrder);
                    if (sample && !hint) lastPending = 'missing_fresh_hint';
                    if (hint && performance.now() < deadline) {
                        checkClean();
                        const proof = {phase, boundary_order: boundary, hint_order: hint.order, ...snapshotProof(sample),
                            rendered_dto_match: true, controller_scope_match: true};
                        boundary = getOrder(); need(boundary >= sample.responseOrder, 'browser_phase_order');
                        lastPending = null; phases.push(proof); return {...proof};
                    }
                    await new Promise(resolve => setTimeout(resolve, Math.min(50, Math.max(1, deadline - performance.now()))));
                }
                need(false, 'browser_phase_timeout');
            } finally { busy = false; }
        },
        finish() {
            need(ready && !busy && !closed && phases.map(p => p.phase).join(',') === 'waiting,handled,gone', 'browser_call_phases_incomplete');
            closed = true; return api.evidence();
        },
        evidence() { return {ready, phases: phases.map(p => ({...p})), native_hints: events.length, last_pending_reason: lastPending,
            validated_responses: responseCount, event_causal_correlation_verified: false, broker_barrier_verified: false}; }
    };
    return Object.freeze(api);
}
module.exports = {createBrowserCallObserver, readRenderedCall, BrowserCallError};
