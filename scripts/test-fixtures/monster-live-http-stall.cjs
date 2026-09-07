'use strict';
// Opt-in transport fault only: hold an actual selected-detail GET response.
// Never modify response bytes, application state, authentication or socket data.
const crypto = require('node:crypto');
const {performance} = require('node:perf_hooks');
const {validateDetail} = require('./queue-live-observer.cjs');
const ID = /^[a-f0-9]{32}$/;
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
class HttpStallError extends Error {}
function need(ok, code) { if (!ok) throw new HttpStallError(code); }
function httpStallOptions(env, natural, reconnect) {
    need([undefined, 'false', 'true'].includes(env.KAZOO_TEST_HTTP_STALL), 'invalid_http_stall_mode');
    const enabled = env.KAZOO_TEST_HTTP_STALL === 'true';
    need(!enabled || (!natural && !reconnect && env.KAZOO_TEST_REQUIRE_WEBSOCKET === 'true'), 'standalone_native_http_stall_required');
    return enabled;
}
function selectedGet(request, apiOrigin, account, queue) {
    const u = new URL(request.url());
    return request.method() === 'GET' && u.origin === apiOrigin && !u.username && !u.password && !u.search && !u.hash
        && u.pathname === '/v2/accounts/' + account + '/queues/' + queue + '/live';
}
function readStallView({accountId, queueId}) {
    const monster = window.require('monster'), app = monster.apps.acdc, f = app?.appFlags.acdc;
    const c = f?.liveDashboardController, s = f?.liveDashboardSnapshot;
    const root = document.querySelector('.acdc-live-dashboard');
    function visible(node) {
        if (!node?.isConnected || !node.getClientRects().length) return false;
        for (let e = node; e && e.nodeType === 1; e = e.parentElement) {
            const style = window.getComputedStyle(e);
            if (e.hidden || style.display === 'none' || ['hidden', 'collapse'].includes(style.visibility) || style.opacity === '0') return false;
        }
        return true;
    }
    const account = app?.accountId === accountId && monster.apps.auth.currentAccount?.id === accountId
        && monster.apps.getActiveApp() === 'acdc';
    const scope = account && c && !c.stopped && s && c.accountId === accountId && s.accountId === accountId
        && c.queueId === queueId && s.queueId === queueId && f.currentTab === 'dashboard'
        && c.view?.[0] === root && visible(root) && app.liveSnapshotValid(s.results.live, accountId, queueId, s.page);
    const counters = root ? [...root.querySelectorAll('.acdc-live-detail-metrics strong')] : [];
    const refresh = root?.querySelector('.acdc-refresh');
    return {scope: Boolean(scope), account, disposed: account && !c && f.currentTab === 'queues' && !root,
        dto: s?.accountId === accountId && s.queueId === queueId ? JSON.stringify(s.results.live) : null,
        receivedAt: s?.receivedAt, generation: c?.generation, inFlight: Boolean(c?.inFlight),
        quiet: Boolean(c && !c.inFlight && !c.dirty && !c.coalesceTimer && !c.admitting && !c.admissionTimer),
        acknowledged: Boolean(c && app.liveTransportState(c) === 'acknowledged'),
        busy: root?.getAttribute('aria-busy'), counters: counters.map(e => e.textContent),
        countersVisible: counters.length === 3 && counters.every(visible),
        refreshEnabled: visible(refresh) && !refresh.disabled,
        error: visible(root?.querySelector('.acdc-live-refresh-error')),
        stale: visible(root?.querySelector('.acdc-live-freshness.is-stale'))};
}
function renderedMatches(view, dto) {
    if (!view?.scope || !view.countersVisible || view.dto !== JSON.stringify(dto)) return false;
    const q = dto.queues[0], roster = dto.agents.roster_complete ? dto.agents.rows.length : null;
    const expected = [q.metrics_available ? q.metrics.current_waiting : null,
        q.metrics_available ? q.metrics.current_handled : null, roster].map(v => v === null ? '—' : String(v));
    return JSON.stringify(view.counters) === JSON.stringify(expected);
}
function expectedCancellation(record, request, now) {
    return Boolean(record && request === record.request && !record.cancelled
        && request.failure()?.errorText === 'net::ERR_ABORTED'
        && (record.disposing || now - record.started >= 9500));
}
function createHttpStallProbe({page, apiOrigin, accountId, queueId, checkClean}) {
    need(ID.test(accountId) && ID.test(queueId) && new URL(apiOrigin).origin === apiOrigin, 'invalid_http_stall_scope');
    const scope = {accountId, queueId}, records = [], owned = new WeakMap(), starts = new WeakMap(), pending = new Set();
    let armed = null, fault = null, latest = null, closed = false, phase = 'new', saved, responseSequence = 0;
    const proof = {mode: 'real_selected_detail_get', held_requests: 0, validated_real_responses: 0,
        watchdog_stale_error: false, retained_snapshot_verified: false, refresh_usable: false,
        manual_refresh_recovered: false, disposal_unchanged: false, late_javascript_callback_executed: false,
        late_callback_ignore_verified: false, attempts: []};
    const now = () => performance.now();
    const selector = url => url.origin === apiOrigin && url.pathname === '/v2/accounts/' + accountId + '/queues/' + queueId + '/live';
    function fail(code) { fault ||= new HttpStallError(code); }
    async function wait(predicate, timeout, code) {
        const until = now() + timeout;
        while (now() < until) {
            checkClean(); if (fault) throw fault;
            const value = await predicate(); if (value) return value;
            await page.waitForTimeout(50);
        }
        throw new HttpStallError(code);
    }
    function decode(response, bytes) {
        need(response.status() === 200 && response.headers()['cache-control'] === 'no-store'
            && bytes.length > 0 && bytes.length <= 2 * 1024 * 1024, 'stall_real_response_status_or_size');
        let dto;
        try { dto = validateDetail(JSON.parse(bytes.toString('utf8')), accountId, queueId); }
        catch (_) { throw new HttpStallError('stall_real_response_schema'); }
        need(dto.source.status === 'available', 'stall_complete_source_required');
        return dto;
    }
    async function routeHandler(route) {
        const request = route.request();
        const selected = selectedGet(request, apiOrigin, accountId, queueId);
        if (selected && phase === 'recovering') starts.set(request, Date.now());
        if (!armed || !selected) return route.fallback();
        const record = armed; armed = null; record.request = request; record.started = now();
        owned.set(request, record); proof.held_requests++;
        let response;
        const work = (async () => {
            try {
                // fetch performs only the browser's original GET, with redirects
                // forbidden. The original bytes/headers are later passed as-is.
                response = await route.fetch({maxRedirects: 0, maxRetries: 0, timeout: 5000});
                const bytes = await response.body(), dto = decode(response, bytes);
                record.realHash = hash(JSON.stringify(dto)); record.fetched = true;
                proof.validated_real_responses++;
                await record.gate;
                if (closed) { await route.abort('aborted').catch(() => {}); return; }
                record.released = now();
                try { await route.fulfill({response}); record.fulfillAccepted = true; }
                catch (_) { need(record.cancelled, 'stall_late_release_failed_without_owned_abort'); }
                record.finished = true;
            } catch (error) {
                fail(error instanceof HttpStallError ? error.message : 'stall_route_failed');
                await route.abort('failed').catch(() => {});
            } finally { if (response) await response.dispose().catch(() => {}); }
        })();
        pending.add(work); try { await work; } finally { pending.delete(work); }
    }
    function arm(kind) {
        need(!closed && !armed && records.length < 2, 'stall_admission_closed_or_full');
        let release; const gate = new Promise(resolve => { release = resolve; });
        const record = {kind, gate, release, started: null, cancelled: false, disposing: false,
            fetched: false, finished: false, fulfillAccepted: false};
        records.push(record); armed = record; return record;
    }
    async function release(record) {
        await wait(() => record.cancelled, 1000, 'stall_owned_abort_not_observed');
        record.release(); await wait(() => record.finished, 3000, 'stall_release_timeout');
        need(record.cancelled, 'stall_owned_client_abort_required');
        proof.attempts.push({kind: record.kind, response_sha256: record.realHash,
            hold_ms: Math.round(record.released - record.started), transport_cancelled: record.cancelled,
            fulfill_call_resolved: record.fulfillAccepted, delivered_late_to_javascript: false});
    }
    const read = () => page.evaluate(readStallView, scope);
    const quiet = () => wait(async () => {
        const v = await read(); if (!v.scope || !v.quiet || !v.acknowledged || v.error || v.stale) return false;
        let dto; try { dto = JSON.parse(v.dto); } catch (_) { return false; }
        return renderedMatches(v, dto) ? v : false;
    }, 10000, 'stall_ready_detail_timeout');
    return {
        async install() { await page.route(selector, routeHandler); },
        expectedFailure(request) {
            const record = owned.get(request);
            if (!expectedCancellation(record, request, now())) return false;
            record.cancelled = true; return true;
        },
        async response(response) {
            const request = response.request();
            if (phase !== 'recovering' || owned.has(request) || !selectedGet(request, apiOrigin, accountId, queueId)) return;
            const requestAt = starts.get(request); if (requestAt === undefined) return;
            const sequence = ++responseSequence, dto = decode(response, await response.body());
            if (!latest || sequence > latest.sequence) latest = {dto, requestAt, sequence};
        },
        async deadlineRecovery() {
            phase = 'deadline'; const before = await quiet(), record = arm('deadline');
            await page.locator('.acdc-refresh').click();
            await wait(() => record.fetched, 8000, 'stall_real_get_not_captured');
            const stale = await wait(async () => {
                const v = await read();
                return v.scope && v.error && v.stale && !v.inFlight && v.busy === 'false' && v.refreshEnabled ? v : false;
            }, 12000, 'stall_watchdog_did_not_release_ui');
            need(now() - record.started >= 9500 && now() - record.started < 16000, 'stall_watchdog_latency_out_of_bounds');
            need(stale.dto === before.dto && stale.receivedAt === before.receivedAt
                && renderedMatches(stale, JSON.parse(before.dto)), 'stall_cached_snapshot_changed');
            proof.watchdog_stale_error = proof.retained_snapshot_verified = proof.refresh_usable = true;
            await release(record); await page.waitForTimeout(250);
            const late = await read();
            need(late.dto === before.dto && late.receivedAt === before.receivedAt && late.error
                && renderedMatches(late, JSON.parse(before.dto)), 'stall_late_response_changed_expired_view');
            phase = 'recovering'; const retryAt = Date.now();
            await page.locator('.acdc-refresh').click();
            await wait(async () => {
                const v = await read();
                return latest && latest.requestAt >= retryAt && v.receivedAt >= latest.requestAt
                    && !v.inFlight && !v.error && !v.stale && v.refreshEnabled && renderedMatches(v, latest.dto);
            }, 10000, 'stall_manual_refresh_not_recovered');
            proof.manual_refresh_recovered = true; phase = 'recovered'; latest = null;
        },
        async prepareDisposal() {
            await quiet(); const record = arm('disposal');
            // Preserve the established native subscription: wait for its normal
            // 15s reconciliation GET instead of creating a new controller.
            await wait(() => record.fetched, 19000, 'stall_reconciliation_get_missing');
            saved = await read(); need(saved.scope && saved.inFlight, 'stall_disposal_request_not_active');
            record.disposing = true; phase = 'disposing';
        },
        async finishDisposal() {
            const record = records[1]; need(record?.fetched && phase === 'disposing', 'stall_disposal_not_prepared');
            const before = await read(); need(before.disposed && before.dto === saved.dto, 'stall_navigation_did_not_dispose');
            await release(record); await page.waitForTimeout(1000);
            const after = await read(); need(after.disposed && after.dto === saved.dto && after.receivedAt === saved.receivedAt,
                'stall_late_response_changed_disposed_view');
            checkClean(); proof.disposal_unchanged = true; phase = 'complete';
        },
        evidence() { return JSON.parse(JSON.stringify(proof)); },
        async close() {
            closed = true; armed = null; for (const record of records) record.release();
            await Promise.all([...pending]); await page.unroute(selector, routeHandler).catch(() => {});
            if (fault) throw fault;
        }
    };
}
module.exports = {HttpStallError, httpStallOptions, selectedGet, readStallView, renderedMatches, expectedCancellation, createHttpStallProbe};
