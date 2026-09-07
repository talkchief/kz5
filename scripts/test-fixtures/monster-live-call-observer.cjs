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
let overviewSchema;
function validateOverview(body, accountId, queueId) {
    if (!overviewSchema) {
        const Ajv = require('../api-docs-tooling/node_modules/ajv');
        const {queueLiveContract} = require('../api-docs-queue-live.cjs');
        overviewSchema = new Ajv({strict: false, validateFormats: false}).compile({components: {schemas: queueLiveContract().schemas},
            $ref: '#/components/schemas/QueueLiveEnvelope'});
    }
    need(body?.status === 'success' && overviewSchema(body), 'invalid_browser_overview_schema');
    const d = body.data, s = d.source, p = d.pagination;
    need(d.account_id === accountId && d.calls === null && d.agents === null
        && d.capabilities.websocket_updates === true && d.capabilities.live_call_details === false
        && d.capabilities.agent_runtime === false, 'invalid_browser_overview_scope');
    need(d.window.from === d.window.to - 3600 && d.window.to <= d.generated_at
        && d.queues.length <= p.page_size && (!p.has_more || d.queues.length === p.page_size), 'invalid_browser_overview_window');
    need(s.observation_started_at === null && s.observation_finished_at === null
        || Number.isSafeInteger(s.observation_started_at) && Number.isSafeInteger(s.observation_finished_at)
        && s.observation_started_at >= d.window.to && s.observation_started_at <= s.observation_finished_at
        && s.observation_finished_at <= d.generated_at, 'invalid_browser_overview_times');
    let previous;
    for (const q of d.queues) {
        need((!previous || previous < q.id) && q.metrics_available === (s.status === 'available'), 'invalid_browser_overview_queue_order');
        previous = q.id;
    }
    need(d.queues.some(q => q.id === queueId) && s.reason !== 'empty_scope'
        && (!p.has_more || p.next_start_queue_id > previous), 'browser_summary_selected_queue_missing');
    if (s.status === 'available') need(s.observation_started_at !== null, 'invalid_browser_overview_times');
    return d;
}
function readRenderedCall({accountId, queueId, overview = false}) {
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
        && c.accountId === accountId && s.accountId === accountId
        && (overview ? !c.queueId && !s.queueId : c.queueId === queueId && s.queueId === queueId)
        && !c.inFlight && !c.dirty && !c.coalesceTimer && !c.admitting && !c.admissionTimer
        && app.liveTransportState(c) === 'acknowledged' && root.getAttribute('aria-busy') === 'false'
        && !root.querySelector('.acdc-live-refresh-error') && !root.querySelector('.acdc-live-freshness.is-stale')
        && app.liveSnapshotValid(s.results.live, accountId, overview ? undefined : queueId, s.page);
    if (!valid) return {valid: false};
    if (overview) {
        const articles = Array.from(root.querySelectorAll('.acdc-live-queue-card'));
        const total = root.querySelector('.acdc-live-toolbar p strong');
        if (!visible(total) || !articles.length || articles.length > 100) return {valid: false};
        const cards = [];
        for (const article of articles) {
            const links = Array.from(article.querySelectorAll('.acdc-open-live-queue'));
            const waiting = article.querySelector('.acdc-live-waiting strong'), handled = article.querySelector('.acdc-live-handling strong');
            if (!visible(article) || !visible(waiting) || !visible(handled) || !links.length || !visible(links[0])) return {valid: false};
            const id = links[0].getAttribute('data-queue-id');
            if (!links.every(link => link.getAttribute('data-queue-id') === id)) return {valid: false};
            cards.push({id, waiting: waiting.textContent, handled: handled.textContent});
        }
        cards.sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
        const selected = cards.filter(card => card.id === queueId);
        if (selected.length !== 1) return {valid: false};
        return {valid: true, generation: c.generation, receivedAt: s.receivedAt, dto: JSON.stringify(s.results.live),
            waiting: selected[0].waiting, handled: selected[0].handled, cards, queueCount: total.textContent};
    }
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
function createObserver(options, overview) {
    need(exact(options, ['accountId', 'queueId', 'readPage', 'getOrder', 'checkClean'])
        && ID.test(options.accountId) && ID.test(options.queueId)
        && ['readPage', 'getOrder', 'checkClean'].every(k => typeof options[k] === 'function'), 'invalid_browser_observer_options');
    const {accountId, queueId, readPage, getOrder, checkClean} = options;
    const events = [], phases = [];
    let latestResponse = null, responseCount = 0;
    let ready = false, busy = false, closed = false, callId, generation, pageIds, boundary = null, lastPending = null;
    const snapshotProof = sample => ({request_order: sample.requestOrder, response_order: sample.responseOrder,
        response_sha256: sample.hash, waiting: sample.waiting, handled: sample.handled,
        ...(overview ? {visible_page_queues: sample.cards.length, snapshot_call_identity_verified: false}
            : {active: sample.rows.length}), generated_at: sample.generatedAt});
    function match(page, phase, caller) {
        if (!page?.valid || typeof page.dto !== 'string') { lastPending = 'render_not_ready'; return null; }
        if (ready && page.generation !== generation) { lastPending = 'controller_changed'; return null; }
        const digest = hash(page.dto), waiting = phase === 'waiting' ? 1 : 0, handled = phase === 'handled' ? 1 : 0;
        const wanted = phase === 'gone' || phase === 'empty' ? [] : [{callId: caller, state: phase}];
        if (page.waiting !== String(waiting) || page.handled !== String(handled)) { lastPending = 'rendered_counts_mismatch'; return null; }
        if (!overview && (page.empty !== (wanted.length === 0) || JSON.stringify(page.rows) !== JSON.stringify(wanted))) {
            lastPending = 'rendered_rows_mismatch'; return null;
        }
        const r = latestResponse;
        if (overview && (!Array.isArray(page.cards) || !r || page.queueCount !== String(r.cards.length)
            || JSON.stringify(page.cards) !== JSON.stringify(r.cards)
            || ready && JSON.stringify(page.cards.map(c => c.id)) !== pageIds)) {
            lastPending = 'rendered_summary_cards_mismatch'; return null;
        }
        const matches = r && r.hash === digest && r.complete && r.waiting === waiting && r.handled === handled
            && page.receivedAt >= r.requestAt && (overview || JSON.stringify(r.rows) === JSON.stringify(wanted));
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
            const d = overview ? validateOverview(input.body, accountId, queueId) : validateDetail(input.body, accountId, queueId);
            const calls = d.calls, q = overview ? d.queues.find(q => q.id === queueId) : d.queues[0];
            latestResponse = {requestOrder: input.requestOrder, responseOrder: input.responseOrder, requestAt: input.requestAt,
                hash: hash(JSON.stringify(d)), generatedAt: d.generated_at,
                complete: d.source.status === 'available' && (overview || calls.available && calls.complete && !calls.truncated),
                waiting: q.metrics_available ? q.metrics.current_waiting : null,
                handled: q.metrics_available ? q.metrics.current_handled : null,
                ...(overview ? {cards: d.queues.map(q => ({id: q.id,
                    waiting: q.metrics_available ? String(q.metrics.current_waiting) : '—',
                    handled: q.metrics_available ? String(q.metrics.current_handled) : '—'}))}
                    : {rows: calls.rows.map(r => ({callId: r.call_id, state: r.status}))})};
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
                        if (overview) pageIds = JSON.stringify(page.cards.map(c => c.id));
                        need(Number.isSafeInteger(boundary) && boundary >= sample.responseOrder, 'browser_ready_order');
                        checkClean(); ready = true; return snapshotProof(sample);
                    }
                    await new Promise(resolve => setTimeout(resolve, Math.min(50, Math.max(1, deadline - performance.now()))));
                }
                need(false, overview ? 'browser_empty_summary_timeout' : 'browser_empty_detail_timeout');
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
        assertSummaryBindings(bindings) {
            need(overview && ready && Array.isArray(bindings)
                && JSON.stringify(bindings.slice().sort()) === JSON.stringify(JSON.parse(pageIds).map(id => 'queue_live.changed.' + id)),
            'summary_wire_page_bindings_mismatch');
        },
        evidence() { return {ready, phases: phases.map(p => ({...p})), native_hints: events.length, last_pending_reason: lastPending,
            ...(overview ? {scope: 'visible_overview_page', snapshot_call_identity_verified: false} : {}),
            validated_responses: responseCount, event_causal_correlation_verified: false, broker_barrier_verified: false}; }
    };
    return Object.freeze(api);
}
function createBrowserCallObserver(options) { return createObserver(options, false); }
function createBrowserSummaryObserver(options) { return createObserver(options, true); }
module.exports = {createBrowserCallObserver, createBrowserSummaryObserver, readRenderedCall, validateOverview, BrowserCallError};
