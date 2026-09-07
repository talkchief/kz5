'use strict';
// Actual ACDC source, jQuery/Handlebars templates and Chromium interaction.
// Only in-memory API responses; no authentication, broker, wire or deployed bundle proof.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const vendors = process.env.KAZOO_MONSTER_VENDOR_ROOT || '/usr/local/src/kazoo5-installer/monster-ui/src/js/vendor';
const {chromium} = require(process.env.KAZOO_PLAYWRIGHT_MODULE || 'playwright');
const vendorFiles = ['jquery-1.9.1.min.js', 'lodash-4.17.4.js', 'handlebars-v4.7.7.js'].map(f => path.join(vendors, f));
const files = [__filename, 'monster-ui/acdc/app.js', 'monster-ui/acdc/i18n/en-US.json',
    'monster-ui/acdc/views/dashboard.html', 'monster-ui/acdc/views/dashboard-detail.html'].map(f => path.resolve(root, f)).concat(vendorFiles);
const hashes = () => Object.fromEntries(files.map(file => [file, crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')]));
const before = hashes(), evidence = fs.mkdtempSync('/tmp/kazoo-monster-live-dashboard.');
const translations = JSON.parse(fs.readFileSync(path.join(root, 'monster-ui/acdc/i18n/en-US.json')));
const templates = Object.fromEntries(['dashboard', 'dashboard-detail'].map(name => [name,
    fs.readFileSync(path.join(root, 'monster-ui/acdc/views', name + '.html'), 'utf8')]));
const groups = [], network = [], errors = [];
let failure = null;
async function main() {
    const browser = await chromium.launch({headless: true});
    const deadline = setTimeout(() => browser.close().catch(() => {}), 90000);
    try {
        const context = await browser.newContext({serviceWorkers: 'block'});
        await context.route('**/*', route => { network.push(route.request().url()); return route.abort(); });
        const page = await context.newPage();
        page.on('pageerror', error => errors.push(error.message));
        await page.setContent('<main id="shell"><div class="acdc-content"></div></main>');
        for (const file of vendorFiles) await page.addScriptTag({path: file});
        await page.evaluate(() => {
            window.monster = {};
            window.define = factory => { window.app = factory(name => ({jquery: window.jQuery, lodash: window._, monster: window.monster})[name]); };
        });
        await page.addScriptTag({path: path.join(root, 'monster-ui/acdc/app.js')});
        await page.evaluate(({templates, translations}) => {
            const app = window.app, $ = window.jQuery;
            const compiled = Object.fromEntries(Object.entries(templates).map(([n, t]) => [n, window.Handlebars.compile(t)]));
            window.A = 'a'.repeat(32); window.Q = '1'.repeat(32);
            const RealDate = window.Date;
            window.clockNow = RealDate.now(); window.clockTimers = new Map(); window.clockNext = 0;
            window.Date = class extends RealDate { static now() { return clockNow; } };
            window.setTimeout = (fn, ms) => { clockTimers.set(++clockNext, {fn, at: clockNow + ms}); return clockNext; };
            window.clearTimeout = id => clockTimers.delete(id);
            window.tick = ms => {
                const end = clockNow + ms; let bound = 1000;
                for (;;) {
                    const next = [...clockTimers].filter(([, t]) => t.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
                    if (!next) break; if (--bound <= 0) throw Error('Unbounded fixture timer loop');
                    clockNow = next[1].at; clockTimers.delete(next[0]); next[1].fn();
                }
                clockNow = end;
            };
            window.paging = () => ({cursor: null, size: 50, history: []});
            app.i18n = {active: () => translations};
            app.getTemplate = ({name, data}) => compiled[name]({...data, i18n: translations});
            app.renderLoading = () => app.getContentContainer().html('<p class="loading">Loading</p>');
            app.renderError = message => app.getContentContainer().empty().append($('<p class="error">').text(message));
            window.metrics = (waiting = 1, handled = 1) => ({current_waiting: waiting, current_handled: handled,
                max_current_wait_seconds: waiting ? 120 : null, records_entered: waiting + handled,
                waiting_in_cohort: waiting, handled_in_cohort: handled, processed_in_cohort: 0, abandoned_in_cohort: 0,
                average_answered_wait_seconds: handled ? 30 : null, average_processed_talk_seconds: null});
            window.agentsDto = () => ({limit: 200, roster_complete: true, truncated: false, runtime_complete: true,
                endpoint_reachability_verified: false, observation_started: Math.floor(Date.now() / 1000), observation_finished: Math.floor(Date.now() / 1000),
                rows: [{agent_id: 'b'.repeat(32), name: 'Agent', observed: true, queue_member: true, state: 'ready', reason: 'observed'}]});
            window.dto = (detail = false) => {
                const now = Math.floor(Date.now() / 1000);
                return {version: 1, account_id: A, generated_at: now,
                    window: {from: now - 3600, to: now, seconds: 3600},
                    queues: [{id: Q, name: 'Alpha queue', strategy: 'round_robin', metrics_available: true, metrics: metrics()}],
                    calls: detail ? {available: true, complete: true, truncated: false, limit: 200, observed_count: 2,
                        order: 'queue_id_entered_call_id', rows: [
                            {call_id: 'waiting-call', queue_id: Q, status: 'waiting', entered_at: now - 120, handled_at: null},
                            {call_id: 'handled-call', queue_id: Q, status: 'handled', entered_at: now - 60, handled_at: now - 30}]} : null,
                    pagination: {page_size: detail ? 1 : 50, has_more: false, next_start_queue_id: null},
                    source: {coverage: 'observed_replicas', all_known_sources_responded: true, consistent: true,
                        atomic_snapshot: false, status: 'available', reason: 'consensus',
                        observation_started_at: now, observation_finished_at: now},
                    agents: detail ? agentsDto() : null,
                    capabilities: {live_call_details: detail, agent_runtime: detail, websocket_updates: false, historical_reporting: false}};
            };
            window.partial = (detail = false, reason = 'source_timeout') => {
                const d = dto(detail); d.source.status = 'partial'; d.source.reason = reason;
                d.source.consistent = false; d.source.all_known_sources_responded = false;
                d.queues.forEach(q => { q.metrics_available = false; q.metrics = null; });
                if (detail) Object.assign(d.calls, {available: false, complete: false, truncated: false, observed_count: null, rows: []});
                return d;
            };
            window.reset = () => {
                app.stopLiveDashboard(); clockTimers.clear(); clockNow = RealDate.now();
                app.accountId = A; app.appFlags.acdc.currentTab = 'dashboard'; app.appFlags.acdc.requestGeneration = 0;
                app.appFlags.acdc.container = $('#shell'); delete app.appFlags.acdc.liveDashboardSnapshot;
                window.ledger = []; window.held = []; window.defer = false; window.mainError = null;
                window.reply = dto(false);
                window.socketBindings = []; window.socketConnects = 0; window.syncAck = false;
                monster.socket = {
                    connect() { socketConnects++; return true; },
                    bind(params) {
                        if (socketBindings.some(b => b.pending && !b.cancelled)) throw Error('Parallel native authorization attempt');
                        const entry = {params: {...params, lifecycle: {...params.lifecycle}}, cancelled: 0, pending: true}; socketBindings.push(entry);
                        for (const key of ['onAck', 'onError', 'onDisconnect']) entry.params.lifecycle[key] = info => { entry.pending = false; params.lifecycle[key](info); };
                        if (syncAck) entry.params.lifecycle.onAck({accountId: params.accountId, binding: params.binding, connectionGeneration: 1});
                        return () => { entry.cancelled++; entry.pending = false; };
                    }
                };
                app.getContentContainer().empty();
                monster.request = options => {
                    ledger.push({resource: options.resource, data: JSON.parse(JSON.stringify(options.data)), verb: app.requests[options.resource].verb});
                    if (options.resource.startsWith('acdc.live.')) {
                        if (defer) { held.push(options); return; }
                        if (mainError) return options.error(mainError);
                        return options.success({status: 'success', data: reply});
                    }
                    throw Error('Unexpected supplemental request ' + options.resource);
                };
            };
            window.resolve = (index, data, error) => {
                const options = held[index]; if (!options) throw Error('Missing deferred request');
                if (error) options.error(error); else options.success({status: 'success', data});
            };
            window.ack = (index, generation = 1) => {
                const p = socketBindings[index].params;
                p.lifecycle.onAck({accountId: p.accountId, binding: p.binding, connectionGeneration: generation});
            };
            window.invalidate = (index, event) => {
                const p = socketBindings[index].params;
                p.callback(event || {version: 1, account_id: p.accountId, queue_id: p.binding.split('.').pop()});
            };
            reset();
        }, {templates, translations});
        const group = async (name, fn) => { await fn(); groups.push(name); console.log('PASS ' + name); };
        await group('one overview GET, DTO counts and page-local labels', async () => {
            await page.evaluate(() => { reply.queues[0].metrics = metrics(37, 9); app.renderLiveDashboard(null); });
            assert.deepEqual((await page.evaluate(() => ledger)).map(r => r.resource), ['acdc.live.overview']);
            assert.deepEqual(await page.locator('.acdc-live-card-metrics strong').allTextContents(), ['37', '9']);
            assert.match(await page.locator('.acdc-live-toolbar').first().textContent(), /on this page/);
            assert.equal(await page.locator('.acdc-live-next').isDisabled(), true);
        });
        await group('explicit next/previous page, no background all-page drain', async () => {
            await page.evaluate(() => {
                reset(); reply.queues = Array.from({length: 50}, (_, i) => ({id: (i + 1).toString(16).padStart(32, '0'),
                    name: 'Queue ' + i, strategy: null, metrics_available: true, metrics: metrics(0, 0)}));
                reply.pagination.has_more = true; reply.pagination.next_start_queue_id = '0'.repeat(30) + '33';
                window.firstPage = JSON.parse(JSON.stringify(reply)); app.renderLiveDashboard(null);
                reply = dto(); reply.queues[0].id = firstPage.pagination.next_start_queue_id; reply.queues[0].name = 'Second page';
            });
            assert.equal((await page.evaluate(() => ledger)).length, 1);
            await page.click('.acdc-live-next');
            let requests = await page.evaluate(() => ledger);
            assert.equal(requests.length, 2); assert.equal(requests[1].resource, 'acdc.live.page');
            assert.equal(requests[1].data.startQueueId, '0'.repeat(30) + '33');
            assert.match(await page.locator('.acdc-live-toolbar').last().textContent(), /Page 2/);
            await page.evaluate(() => { reply = firstPage; }); await page.click('.acdc-live-previous');
            requests = await page.evaluate(() => ledger);
            assert.equal(requests[2].resource, 'acdc.live.overview');
            assert.equal(requests[2].data.startQueueId, undefined);
            await page.locator('.acdc-live-search').fill('nonexistent');
            assert.equal(await page.locator('.acdc-live-no-match').isVisible(), true);
            assert.equal((await page.evaluate(() => ledger)).length, 3);
        });
        await group('detail scope, signed Unix durations and no invented caller/agent fields', async () => {
            await page.evaluate(() => {
                reset(); reply = dto(true); reply.calls.rows[0].caller_id_number = 'NEVER-RENDER-CALLER';
                app.renderLiveDashboard(Q);
            });
            assert.deepEqual((await page.evaluate(() => ledger)).map(r => r.resource), ['acdc.live.detail']);
            assert.deepEqual(await page.locator('.acdc-live-calls-panel .acdc-live-duration').allTextContents(), ['2:00', '—', '0:30', '0:30']);
            assert.doesNotMatch(await page.locator('#shell').textContent(), /NEVER-RENDER-CALLER/);
            assert.equal(await page.evaluate(() => app.liveDuration(-2, 0)), '0:02');
            assert.match(await page.locator('.acdc-live-members-panel').textContent(), /does not verify endpoint reachability/);
            assert.deepEqual(await page.locator('.acdc-live-members-panel tbody td').allTextContents(), ['Agent', 'Ready · observed', 'Member · observed']);
        });
        await group('200-row truncation uses metadata while card keeps full 201 count', async () => {
            await page.evaluate(() => {
                reset(); reply = dto(true); reply.queues[0].metrics = metrics(201, 0);
                Object.assign(reply.calls, {observed_count: 201, truncated: true, complete: false,
                    rows: Array.from({length: 200}, (_, i) => ({call_id: 'call-' + i.toString().padStart(3, '0'), queue_id: Q,
                        status: 'waiting', entered_at: reply.generated_at - 201 + i, handled_at: null}))});
                app.renderLiveDashboard(Q);
            });
            assert.equal(await page.locator('.acdc-live-calls-panel tbody tr').count(), 200);
            assert.match(await page.locator('.acdc-live-calls-truncated').textContent(), /201/);
            assert.equal(await page.locator('.acdc-live-detail-metrics strong').first().textContent(), '201');
        });
        await group('partial sources replace old counts with unknown, not stale zeros', async () => {
            await page.evaluate(() => { reset(); app.renderLiveDashboard(null); reply = partial(); });
            await page.click('.acdc-refresh');
            assert.deepEqual(await page.locator('.acdc-live-card-metrics strong').allTextContents(), ['—', '—']);
            assert.match(await page.locator('.acdc-live-source-state').textContent(), /Partial source.*Not every source/);
            assert.equal(await page.locator('.acdc-live-refresh-error').count(), 0);
        });
        await group('unavailable calls differ from complete observed empty calls', async () => {
            await page.evaluate(() => { reset(); reply = partial(true); app.renderLiveDashboard(Q); });
            assert.match(await page.locator('.acdc-live-calls-panel tbody').textContent(), /unavailable or invalid/);
            await page.evaluate(() => {
                reply = dto(true); reply.queues[0].metrics = metrics(0, 0); reply.calls.rows = []; reply.calls.observed_count = 0;
            });
            await page.click('.acdc-refresh');
            assert.match(await page.locator('.acdc-live-calls-panel tbody').textContent(), /No active records were returned/);
            assert.deepEqual(await page.locator('.acdc-live-detail-metrics strong').allTextContents(), ['0', '0', '1']);
        });
        await group('unavailable agent runtime preserves authorized names, valid calls and unknown membership', async () => {
            await page.evaluate(() => {
                reset(); reply = dto(true); Object.assign(reply.agents, {runtime_complete: false, observation_started: null, observation_finished: null});
                Object.assign(reply.agents.rows[0], {observed: false, queue_member: null, state: null, reason: 'source_unavailable'});
                app.renderLiveDashboard(Q);
            });
            assert.equal(await page.locator('.acdc-live-calls-panel tbody tr').count(), 2);
            assert.equal(await page.locator('.acdc-live-detail-metrics strong').last().textContent(), '1');
            assert.match(await page.locator('.acdc-live-members-panel tbody').textContent(), /Agent.*Unknown.*Runtime source unavailable.*Unknown/);
            assert.equal(await page.evaluate(() => ledger.length), 1);
        });
        await group('malformed initial reply fails closed; refresh keeps explicit stale snapshot', async () => {
            await page.evaluate(() => { reset(); reply.version = 2; app.renderLiveDashboard(null); });
            assert.equal(await page.locator('.error').count(), 1);
            await page.evaluate(() => { reset(); app.renderLiveDashboard(null); reply = JSON.parse(JSON.stringify(reply)); reply.account_id = 'c'.repeat(32); });
            await page.click('.acdc-refresh');
            assert.match(await page.locator('.acdc-live-refresh-error').textContent(), /previous snapshot/);
            assert.equal(await page.locator('.acdc-live-freshness.is-stale').count(), 1);
        });
        await group('401/403/404 clears cached data instead of showing revoked detail', async () => {
            for (const status of [401, 403, 404]) {
                await page.evaluate(status => { reset(); reply = dto(true); app.renderLiveDashboard(Q); mainError = {status}; }, status);
                await page.click('.acdc-refresh');
                assert.equal(await page.locator('.error').count(), 1);
                assert.equal(await page.locator('.acdc-live-calls-panel').count(), 0);
                assert.equal(await page.evaluate(() => Boolean(app.appFlags.acdc.liveDashboardSnapshot)), false);
            }
        });
        await group('late generation/queue/account/tab replies do not mount or launch supplementary reads', async () => {
            await page.evaluate(() => {
                reset(); defer = true; app.renderLiveDashboard(Q); app.renderLiveDashboard(null);
                resolve(1, dto(false)); resolve(0, dto(true));
            });
            assert.deepEqual((await page.evaluate(() => ledger)).map(r => r.resource), ['acdc.live.detail', 'acdc.live.overview']);
            assert.equal(await page.locator('.acdc-live-queue-grid').count(), 1);
            for (const boundary of ['account', 'tab']) {
                await page.evaluate(boundary => {
                    reset(); defer = true; app.renderLiveDashboard(Q);
                    if (boundary === 'account') app.accountId = 'c'.repeat(32); else app.appFlags.acdc.currentTab = 'queues';
                    app.getContentContainer().html('<p class="replacement">Replacement</p>'); resolve(0, dto(true));
                }, boundary);
                assert.equal(await page.locator('.replacement').count(), 1);
                assert.equal((await page.evaluate(() => ledger)).length, 1);
            }
        });
        await group('DTO contradictions, caps, scope, chronology and duplicate identities fail closed', async () => {
            const result = await page.evaluate(() => {
                const cases = [
                    d => { d.account_id = 'c'.repeat(32); }, d => { d.version = 2; },
                    d => { d.queues[0].id = 'c'.repeat(32); }, d => { d.queues.push(d.queues[0]); },
                    d => { d.queues[0].metrics.current_waiting = '1'; }, d => { d.queues[0].metrics.current_handled = -1; },
                    d => { d.queues[0].metrics = null; }, d => { d.queues[0].metrics_available = false; },
                    d => { d.source.status = 'partial'; }, d => { d.source.consistent = false; },
                    d => { d.source.coverage = 'cluster_complete'; }, d => { d.source.atomic_snapshot = true; },
                    d => { d.source.observation_finished_at = null; }, d => { d.source.observation_started_at = d.window.to - 1; },
                    d => { d.source.observation_finished_at = d.generated_at + 1; }, d => { d.window.seconds = 24 * 3600; },
                    d => { d.capabilities.agent_runtime = false; }, d => { d.capabilities.live_call_details = false; },
                    d => { d.calls = null; }, d => { d.calls.available = false; },
                    d => { d.calls.limit = 201; }, d => { d.calls.observed_count = 3; },
                    d => { d.calls.complete = false; }, d => { d.calls.truncated = true; },
                    d => { d.calls.rows[1] = d.calls.rows[0]; }, d => { d.calls.rows.reverse(); },
                    d => { d.calls.rows[0].queue_id = 'c'.repeat(32); }, d => { d.calls.rows[0].status = 'processed'; },
                    d => { d.calls.rows[0].handled_at = d.generated_at; }, d => { d.calls.rows[1].handled_at = d.generated_at + 1; },
                    d => { d.calls.rows[0].call_id = '\nsecret'; }, d => { d.pagination.has_more = true; },
                    d => { d.pagination.page_size = 50; }, d => { d.pagination.next_start_queue_id = Q; }
                ];
                const rejected = cases.map(change => { const d = dto(true); change(d); return !app.liveSnapshotValid(d, A, Q, paging()); });
                const positive = dto(true);
                positive.calls.rows[0].call_id = '\ue000'; positive.calls.rows[1].call_id = '\ud83d\ude00';
                positive.calls.rows[1].entered_at = positive.calls.rows[0].entered_at;
                const utf8Order = app.liveSnapshotValid(positive, A, Q, paging());
                const empty = dto(false); empty.queues = []; empty.source.reason = 'empty_scope';
                empty.source.observation_started_at = null; empty.source.observation_finished_at = null;
                const pageCases = [d => { d.pagination.page_size = 101; },
                    d => { d.pagination.has_more = true; d.pagination.next_start_queue_id = Q; },
                    d => { d.calls = dto(true).calls; }, d => { d.queues = Array(101).fill(d.queues[0]); }];
                const pagesRejected = pageCases.map(change => { const d = dto(); change(d); return !app.liveSnapshotValid(d, A, null, paging()); });
                const hundred = dto(); hundred.pagination.page_size = 100;
                const unavailable = partial(true); unavailable.source.status = 'unavailable'; unavailable.source.reason = 'source_unavailable';
                unavailable.source.observation_started_at = null; unavailable.source.observation_finished_at = null;
                return {rejected, pagesRejected, utf8Order, empty: app.liveSnapshotValid(empty, A, null, paging()),
                    hundred: app.liveSnapshotValid(hundred, A, null, {...paging(), size: 100}),
                    unavailable: app.liveSnapshotValid(unavailable, A, Q, paging())};
            });
            assert.equal(result.rejected.length, 34); assert(result.rejected.every(Boolean));
            assert.equal(result.pagesRejected.length, 4); assert(result.pagesRejected.every(Boolean));
            assert.equal(result.utf8Order, true); assert.equal(result.empty, true);
            assert.equal(result.hundred, true); assert.equal(result.unavailable, true);
        });
        await group('source age drives stale state and untrusted text remains escaped', async () => {
            await page.evaluate(() => {
                reset(); reply.queues[0].name = '<img src=x onerror=window.injected=true>';
                reply.generated_at -= 31; reply.window.from -= 31; reply.window.to -= 31;
                reply.source.observation_started_at -= 31; reply.source.observation_finished_at -= 31;
                app.renderLiveDashboard(null);
            });
            assert.equal(await page.locator('.acdc-live-freshness.is-stale').count(), 1);
            assert.equal(await page.locator('.acdc-live-queue-name img').count(), 0);
            assert.equal(await page.evaluate(() => Boolean(window.injected)), false);
            assert.equal((await page.evaluate(() => ledger)).every(r => r.verb === 'GET'), true);
        });
        await group('capability gates native bindings; shared synchronous ACK triggers one coalesced same-page refresh', async () => {
            await page.evaluate(() => { reset(); app.renderDashboard(); tick(16000); });
            assert.equal(await page.evaluate(() => socketBindings.length), 0);
            assert.equal(await page.evaluate(() => ledger.length), 1);
            assert.match(await page.locator('.acdc-live-transport').textContent(), /Native updates are unavailable/);
            await page.evaluate(() => { syncAck = true; reply = dto(); reply.capabilities.websocket_updates = true; });
            await page.click('.acdc-refresh');
            assert.deepEqual(await page.evaluate(() => socketBindings.map(b => ({accountId: b.params.accountId, binding: b.params.binding}))),
                [{accountId: 'a'.repeat(32), binding: 'queue_live.changed.' + '1'.repeat(32)}]);
            await page.evaluate(() => tick(100));
            assert.equal(await page.evaluate(() => ledger.length), 3);
            await page.evaluate(() => tick(1000));
            assert.equal(await page.evaluate(() => ledger.length), 3); assert.equal(await page.evaluate(() => socketBindings.length), 1);
            assert.match(await page.locator('.acdc-live-transport').textContent(), /not a broker binding barrier or replay/);
        });
        await group('native event burst and held HTTP batch preserve one-flight plus one dirty refresh', async () => {
            await page.evaluate(() => {
                reset(); reply = dto(true); reply.capabilities.websocket_updates = true; app.renderLiveDashboard(Q);
                defer = true; ack(0); tick(100);
                for (let i = 0; i < 40; i++) { invalidate(0); app.renderLiveDashboard(Q); }
                tick(1000);
            });
            assert.equal(await page.evaluate(() => held.length), 1);
            assert.equal(await page.evaluate(() => ledger.filter(r => r.resource === 'acdc.live.detail').length), 2);
            await page.evaluate(() => { resolve(0, reply); tick(100); });
            assert.equal(await page.evaluate(() => held.length), 2);
            await page.evaluate(() => { resolve(1, reply); tick(1000); });
            assert.equal(await page.evaluate(() => held.length), 2);
            assert.equal(await page.evaluate(() => socketBindings.length), 1);
            assert.equal(await page.evaluate(() => ledger.every(r => r.verb === 'GET')), true);
        });
        await group('native malformed/foreign hints are ignored; disconnect/reconnect and lost-event reconciliation retain counts', async () => {
            await page.evaluate(() => {
                reset(); reply.capabilities.websocket_updates = true; app.renderDashboard(); ack(0); tick(100);
                for (const e of [{version: 2, account_id: A, queue_id: Q}, {version: 1, account_id: 'b'.repeat(32), queue_id: Q},
                    {version: 1, account_id: A, queue_id: '2'.repeat(32)}]) invalidate(0, e);
                tick(1000); socketBindings[0].params.lifecycle.onDisconnect({code: 'disconnected'});
            });
            assert.equal(await page.evaluate(() => ledger.length), 2);
            assert.equal(await page.locator('.acdc-live-freshness.is-stale').count(), 1);
            assert.deepEqual(await page.locator('.acdc-live-card-metrics strong').allTextContents(), ['1', '1']);
            assert.match(await page.locator('.acdc-live-transport').textContent(), /disconnected/);
            await page.evaluate(() => { tick(1000); ack(1, 2); tick(100); });
            assert.equal(await page.evaluate(() => ledger.length), 3);
            await page.evaluate(() => { reply = dto(); reply.capabilities.websocket_updates = true; tick(15000); });
            assert.equal(await page.evaluate(() => ledger.length), 4);
            assert.equal(await page.evaluate(() => socketBindings.length), 2);
        });
        await group('native subscription failures back off across manual snapshots and retain periodic repair', async () => {
            await page.evaluate(() => {
                reset(); reply.capabilities.websocket_updates = true; app.renderDashboard();
                socketBindings[0].params.lifecycle.onError({code: 'rejected'});
            });
            assert.match(await page.locator('.acdc-live-transport').textContent(), /unavailable or rejected/);
            await page.click('.acdc-refresh');
            assert.equal(await page.evaluate(() => socketBindings.length), 1);
            await page.evaluate(() => tick(15100));
            assert.equal(await page.evaluate(() => socketBindings.length), 2);
            assert.equal(await page.evaluate(() => socketBindings[0].cancelled), 1);
        });
        await group('native capability removal and access denial immediately cancel exact listeners', async () => {
            await page.evaluate(() => { reset(); reply.capabilities.websocket_updates = true; app.renderDashboard(); reply = dto(); });
            await page.click('.acdc-refresh');
            assert.equal(await page.evaluate(() => socketBindings[0].cancelled), 1);
            await page.evaluate(() => { ack(0); invalidate(0); tick(16000); });
            assert.equal(await page.evaluate(() => ledger.length), 2);
            assert.match(await page.locator('.acdc-live-transport').textContent(), /Native updates are unavailable/);
            for (const status of [401, 403, 404]) {
                await page.evaluate(status => {
                    reset(); reply.capabilities.websocket_updates = true; app.renderDashboard(); mainError = {status};
                }, status);
                await page.click('.acdc-refresh');
                assert.equal(await page.evaluate(() => socketBindings[0].cancelled), 1);
                assert.equal(await page.evaluate(() => clockTimers.size), 0);
                assert.equal(await page.locator('.error').count(), 1);
            }
        });
        await group('native detail/page/account/tab/detached-view disposal blocks late events and replies', async () => {
            await page.evaluate(() => {
                reset(); reply.capabilities.websocket_updates = true; app.renderDashboard(); reply = dto(true); reply.capabilities.websocket_updates = true;
            });
            await page.locator('.acdc-open-live-queue').first().click();
            assert.equal(await page.evaluate(() => socketBindings[0].cancelled), 1);
            assert.equal(await page.evaluate(() => socketBindings.length), 2);
            for (const boundary of ['page', 'account', 'tab', 'detached']) {
                await page.evaluate(boundary => {
                    reset(); reply = dto(true); reply.capabilities.websocket_updates = true; app.renderLiveDashboard(Q);
                    defer = true; ack(0); tick(100);
                    if (boundary === 'page') app.renderLiveDashboard(null, undefined, {cursor: '2'.repeat(32), size: 50, history: [null]});
                    if (boundary === 'account') app.accountId = 'b'.repeat(32);
                    if (boundary === 'tab') app.appFlags.acdc.currentTab = 'queues';
                    app.getContentContainer().html('<p class="replacement">Replacement</p>');
                }, boundary);
                // Real MutationObserver delivery occurs after the DOM replacement.
                assert.equal(await page.evaluate(() => socketBindings[0].cancelled), 1);
                await page.evaluate(() => { resolve(0, reply); ack(0); invalidate(0); tick(20000); });
                assert.equal(await page.locator('.replacement').count(), 1);
                assert.equal(await page.evaluate(() => ledger.filter(r => r.resource === 'acdc.queues.roster').length), 0);
            }
        });
        await group('automatic refresh preserves current search/filter/focus/selection including edits during held GET', async () => {
            await page.evaluate(() => {
                reset(); reply.capabilities.websocket_updates = true;
                reply.queues.push({...reply.queues[0], id: '2'.repeat(32), name: 'Bravo queue'});
                app.renderDashboard(); defer = true;
            });
            await page.locator('.acdc-live-search').fill('Alpha');
            await page.locator('.acdc-live-search').evaluate(input => input.setSelectionRange(1, 4, 'backward'));
            await page.evaluate(() => { ack(0); tick(100); });
            const state = () => page.locator('.acdc-live-search').evaluate(input => ({value: input.value,
                focused: document.activeElement === input, start: input.selectionStart, end: input.selectionEnd, direction: input.selectionDirection}));
            assert.deepEqual(await state(), {value: 'Alpha', focused: true, start: 1, end: 4, direction: 'backward'});
            await page.locator('.acdc-live-search').fill('Bravo');
            await page.locator('.acdc-live-search').evaluate(input => input.setSelectionRange(2, 4, 'forward'));
            await page.evaluate(() => resolve(0, reply));
            assert.deepEqual(await state(), {value: 'Bravo', focused: true, start: 2, end: 4, direction: 'forward'});
            assert.equal(await page.locator('.acdc-live-queue-card:visible').count(), 1);
            assert.match(await page.locator('.acdc-live-queue-card:visible .acdc-live-queue-name').textContent(), /Bravo/);
            await page.evaluate(() => {
                jQuery('<button id="outside-focus">Outside view</button>').appendTo('body')[0].focus();
                invalidate(0); tick(100); resolve(1, null, {status: 503});
            });
            assert.equal((await state()).value, 'Bravo'); assert.equal((await state()).focused, false);
            assert.equal(await page.evaluate(() => document.activeElement.id), 'outside-focus');
            assert.equal(await page.locator('.acdc-live-queue-card:visible').count(), 1);
            assert.equal(await page.locator('.acdc-live-refresh-error').count(), 1);
        });
        await group('search state resets across detail, page and account navigation without stealing external focus', async () => {
            await page.evaluate(() => { reset(); app.renderDashboard(); });
            await page.locator('.acdc-live-search').fill('Alpha');
            await page.evaluate(() => { reply = dto(true); });
            await page.locator('.acdc-open-live-queue').first().click();
            await page.evaluate(() => { reply = dto(); }); await page.click('.acdc-live-back');
            assert.equal(await page.locator('.acdc-live-search').inputValue(), '');
            await page.locator('.acdc-live-search').fill('Alpha');
            await page.evaluate(() => {
                app.renderLiveDashboard(null, undefined, {cursor: Q, size: 50, history: [null]});
            });
            assert.equal(await page.locator('.acdc-live-search').inputValue(), '');
            await page.locator('.acdc-live-search').fill('Alpha');
            await page.evaluate(() => {
                document.querySelector('#outside-focus').focus(); app.accountId = 'b'.repeat(32);
                reply = dto(); reply.account_id = app.accountId; app.renderDashboard();
            });
            assert.equal(await page.locator('.acdc-live-search').inputValue(), '');
            assert.equal(await page.evaluate(() => document.activeElement.id), 'outside-focus');
        });
        await group('single detail GET renders eight runtime states and membership separately; unknown is never logout', async () => {
            await page.evaluate(() => {
                reset(); reply = dto(true);
                reply.agents.rows = ['wait', 'sync', 'ready', 'ringing', 'answered', 'wrapup', 'paused', 'outbound'].map((state, i) => ({
                    agent_id: (i + 1).toString(16).padStart(32, '0'), name: 'Agent ' + i, observed: true, queue_member: i % 2 === 0, state, reason: 'observed'}));
                reply.agents.rows.push({agent_id: 'f'.repeat(32), name: '<img src=x onerror=alert(1)>', observed: false,
                    queue_member: null, state: null, reason: 'inconsistent_sources'});
                reply.agents.runtime_complete = false; app.renderLiveDashboard(Q);
            });
            assert.deepEqual(await page.evaluate(() => ledger.map(r => r.resource)), ['acdc.live.detail']);
            assert.equal(await page.locator('.acdc-live-members-panel tbody tr').count(), 9);
            assert.equal(await page.locator('.acdc-live-members-panel img').count(), 0);
            assert.match(await page.locator('.acdc-live-members-panel tbody tr').last().textContent(), /Unknown.*Conflicting runtime observations.*Unknown/);
            assert.match(await page.locator('.acdc-live-agent-source').textContent(), /Runtime observations incomplete/);
            assert.deepEqual(await page.locator('.acdc-live-members-panel tbody tr').nth(2).locator('td').allTextContents(),
                ['Agent 2', 'Ready · observed', 'Member · observed']);
        });
        await group('strict agents contradictions reject whole detail without fallback HTTP; truncation and empty runtime stay explicit', async () => {
            const rejected = await page.evaluate(() => {
                const cases = [d => { delete d.agents; }, d => { d.capabilities.agent_runtime = false; },
                    d => { d.agents.endpoint_reachability_verified = true; }, d => { d.agents.runtime_complete = false; },
                    d => { d.agents.rows[0].state = 'logout'; }, d => { d.agents.rows[0].queue_member = null; },
                    d => { d.agents.rows[0].name = '\nsecret'; }, d => { d.agents.rows[0].name = 'é'.repeat(129); },
                    d => { d.agents.rows[0].device_id = 'PRIVATE'; }, d => { d.agents.rows.push(d.agents.rows[0]); },
                    d => { d.agents.rows[0].observed = false; }, d => { d.agents.observation_started = null; },
                    d => { d.agents.observation_finished = d.agents.observation_started - 1; }, d => { d.agents.roster_complete = false; }];
                return cases.map(change => { const d = dto(true); change(d); return !app.liveSnapshotValid(d, A, Q, paging()); });
            });
            assert.equal(rejected.length, 14); assert(rejected.every(Boolean));
            await page.evaluate(() => { reset(); reply = dto(true); delete reply.agents; app.renderLiveDashboard(Q); });
            assert.equal(await page.locator('.error').count(), 1); assert.equal(await page.evaluate(() => ledger.length), 1);
            await page.evaluate(() => {
                reset(); reply = dto(true); Object.assign(reply.agents, {roster_complete: false, truncated: true, runtime_complete: false,
                    rows: Array.from({length: 200}, (_, i) => ({agent_id: (i + 1).toString(16).padStart(32, '0'), name: 'Agent ' + i,
                        observed: true, queue_member: true, state: 'ready', reason: 'observed'}))}); app.renderLiveDashboard(Q);
            });
            assert.equal(await page.locator('.acdc-live-members-panel tbody tr').count(), 200);
            assert.equal(await page.locator('.acdc-live-detail-metrics strong').last().textContent(), '—');
            assert.match(await page.locator('.acdc-live-members-panel').textContent(), /total is not supplied/);
            await page.evaluate(() => { reply = dto(true); reply.agents.rows = []; app.renderLiveDashboard(Q); });
            assert.equal(await page.locator('.acdc-live-detail-metrics strong').last().textContent(), '0');
            assert.match(await page.locator('.acdc-live-agent-source').textContent(), /Runtime observations complete/);
            await page.evaluate(() => {
                Object.assign(reply.agents, {observation_started: null, observation_finished: null, runtime_complete: false}); app.renderLiveDashboard(Q);
            });
            assert.match(await page.locator('.acdc-live-agent-source').textContent(), /Runtime observations incomplete/);
        });
        await group('50-queue asynchronous ACK admission and reconnect never submit parallel native authorization', async () => {
            await page.evaluate(() => {
                reset(); reply.capabilities.websocket_updates = true;
                reply.queues = Array.from({length: 50}, (_, i) => ({id: (i + 1).toString(16).padStart(32, '0'),
                    name: 'Queue ' + i, strategy: null, metrics_available: true, metrics: metrics()}));
                app.renderDashboard(); tick(999);
            });
            assert.equal(await page.evaluate(() => socketBindings.length), 1);
            // Deliver ACKs in separate browser turns, not synchronously inside bind.
            for (let i = 0; i < 50; i++) {
                assert.equal(await page.evaluate(() => socketBindings.filter(b => b.pending && !b.cancelled).length), 1);
                await page.evaluate(index => ack(index), i);
            }
            assert.equal(await page.evaluate(() => socketBindings.length), 50);
            await page.evaluate(() => { tick(100); socketBindings[0].params.lifecycle.onDisconnect({code: 'disconnected'}); tick(1000); });
            assert.equal(await page.evaluate(() => socketBindings.slice(0, 50).every(b => b.cancelled === 1)), true);
            assert.equal(await page.evaluate(() => socketBindings.length), 51);
            await page.evaluate(() => { tick(1000); ack(0, 2); });
            assert.equal(await page.evaluate(() => socketBindings.length), 51, 'Retired ACK cannot drain queue and pending handle does not churn');
            await page.evaluate(() => { ack(50, 2); ack(51, 2); });
            assert.equal(await page.evaluate(() => socketBindings.length), 53);
            await page.evaluate(() => { reply = dto(); app.renderDashboard(); });
            assert.equal(await page.evaluate(() => socketBindings.slice(50).every(b => b.cancelled === 1)), true);
            assert.equal(await page.evaluate(() => Object.keys(app.appFlags.acdc.liveDashboardController.bindings).length), 0);
        });
        await group('busy/timeout admission is paced and connect false leaves no replayable desired handle', async () => {
            await page.evaluate(() => {
                reset(); reply.capabilities.websocket_updates = true;
                reply.queues.push({...reply.queues[0], id: '2'.repeat(32)}); app.renderDashboard();
                socketBindings[0].params.lifecycle.onError({code: 'rejected'}); tick(999);
            });
            assert.equal(await page.evaluate(() => socketBindings.length), 1);
            assert.equal(await page.evaluate(() => socketBindings[0].cancelled), 1);
            await page.evaluate(() => { tick(1); ack(1); tick(100); });
            assert.equal(await page.evaluate(() => socketBindings.length), 2);
            await page.evaluate(() => { tick(13900); });
            assert.equal(await page.evaluate(() => socketBindings.length), 3);
            await page.evaluate(() => {
                reset(); monster.socket.connect = () => false; reply = dto(true); reply.capabilities.websocket_updates = true; app.renderLiveDashboard(Q);
                socketBindings[0].params.lifecycle.onError({code: 'timeout'}); ack(0); tick(14999);
            });
            assert.equal(await page.evaluate(() => socketBindings.length), 1);
            assert.equal(await page.evaluate(() => socketBindings[0].cancelled), 1);
            await page.evaluate(() => { monster.socket.connect = () => true; tick(1); ack(1); tick(100); });
            assert.equal(await page.evaluate(() => socketBindings.length), 2);
            assert.equal(await page.evaluate(() => ledger.length), 2);
        });
        assert.deepEqual(network, []); assert.deepEqual(errors, []);
    } finally { clearTimeout(deadline); await browser.close(); }
}
main().catch(error => { failure = error.stack; process.exitCode = 1; }).finally(() => {
    const after = hashes();
    try { assert.deepEqual(after, before, 'Inputs changed during source UI validation'); }
    catch (error) { failure = [failure, error.stack].filter(Boolean).join('\n'); process.exitCode = 1; }
    const receipt = {mode: 'actual_source_templates_in_memory_api', success: failure === null,
        groups, network, page_errors: errors, inputs_before: before, inputs_after: after,
        failure, deployment: false, authentication: false, websocket_delivery: false};
    fs.writeFileSync(path.join(evidence, 'receipt.json'), JSON.stringify(receipt, null, 2) + '\n');
    console.log(JSON.stringify({success: receipt.success, groups: groups.length, evidence, failure}));
});
