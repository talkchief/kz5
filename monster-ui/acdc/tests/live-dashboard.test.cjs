/* SPDX-License-Identifier: MPL-2.0
 * Offline source/Handlebars/interaction doubles, not browser or live acceptance.
 */
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const lodash = require(require.resolve('lodash', {paths: [process.cwd()]}));
const Handlebars = require(require.resolve('handlebars', {paths: [process.cwd()]}));
const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const strings = JSON.parse(fs.readFileSync(path.join(root, 'i18n/en-US.json'), 'utf8'));
const overview = Handlebars.compile(fs.readFileSync(path.join(root, 'views/dashboard.html'), 'utf8'));
const detail = Handlebars.compile(fs.readFileSync(path.join(root, 'views/dashboard-detail.html'), 'utf8'));
const A = 'a'.repeat(32), B = 'b'.repeat(32), Q = '1'.repeat(32), R = '2'.repeat(32), U = '3'.repeat(32), V = '4'.repeat(32);
const now = 1788739200000, timestamp = now / 1000;
const paging = () => ({cursor: null, size: 50, history: []});
const plain = value => JSON.parse(JSON.stringify(value));
let groups = 0;
function test(name, run) { run(); console.log('PASS ' + (++groups) + ' ' + name); }
class Element {
  constructor() { this.children = {}; this.events = {}; this.props = {}; this.attrs = {}; this.classes = new Set(); this.value = ''; this.items = []; }
  find(key) { return this.children[key] || (this.children[key] = new Element()); }
  on(event, run) { this.events[event] = run; return this; }
  trigger(event, target = this) { this.events[event].call(target); return this; }
  prop(key, value) { if (arguments.length === 1) return this.props[key]; this.props[key] = value; return this; }
  attr(key, value) { if (arguments.length === 1) return this.attrs[key]; this.attrs[key] = value; return this; }
  text(value) { if (!arguments.length) return this.textValue || ''; this.textValue = value; return this; }
  val(value) { if (!arguments.length) return this.value; this.value = value; return this; }
  addClass(value) { this.classes.add(value); return this; }
  removeClass(value) { this.classes.delete(value); return this; }
  hasClass(value) { return this.classes.has(value); }
  empty() { this.items = []; return this; }
  append(value) { this.items.push(value); return this; }
  each(fn) { this.items.forEach(item => fn.call(item)); return this; }
}
function fixture() {
  let app, clock = now, nextTimer = 0;
  const timers = new Map(), requests = [], views = [], errors = [], navigation = [], container = new Element(), content = new Element();
  const jquery = value => value; jquery.trim = value => String(value).trim();
  const monster = {apps: {}, ui: {}};
  class Clock extends Date { static now() { return clock; } }
  vm.runInNewContext(source, {
    define(factory) { app = factory(name => name === 'jquery' ? jquery : name === 'lodash' ? lodash : monster); },
    Date: Clock, Math,
    setTimeout(fn, ms) { timers.set(++nextTimer, {fn, ms}); return nextTimer; },
    clearTimeout(id) { timers.delete(id); }
  }, {filename: path.join(root, 'app.js')});
  app.i18n.active = () => strings;
  app.accountId = A;
  app.appFlags.acdc.container = container;
  app.getContentContainer = () => content;
  app.getTemplate = spec => { const element = new Element(); element.spec = spec; views.push(element); return element; };
  app.renderLoading = message => { content.empty(); navigation.push({loading: message}); };
  app.renderError = (message, retry) => { content.empty(); errors.push({message, retry}); };
  app.renderQueueForm = id => { ++app.appFlags.acdc.requestGeneration; navigation.push({editor: id}); };
  app.renderAgents = () => navigation.push({agents: true});
  const seam = app.requestLiveDashboard;
  app.requestLiveDashboard = (queueId, callback, page) => requests.push({queueId, callback, page});
  return {app, seam, monster, requests, views, errors, navigation, content, container, timers,
    advance(ms) { clock += ms; },
    reply(index, results = data(Boolean(requests[index].queueId)), failures = {}) { requests[index].callback(failures, results); },
    current() { return content.items[0]; },
    fireTimer() { const entry = [...timers][0]; assert(entry); timers.delete(entry[0]); entry[1].fn(); }
  };
}
function metrics(waiting = 1, handled = 1) {
  return {current_waiting: waiting, current_handled: handled, max_current_wait_seconds: waiting ? 75 : null,
    records_entered: waiting + handled, waiting_in_cohort: waiting, handled_in_cohort: handled,
    processed_in_cohort: 0, abandoned_in_cohort: 0, average_answered_wait_seconds: handled ? 60 : null,
    average_processed_talk_seconds: null};
}
function data(selected = false) {
  const queues = [{id: Q, name: 'Support', strategy: 'round_robin', metrics_available: true, metrics: metrics()}];
  if (!selected) queues.push({id: R, name: 'Sales', strategy: null, metrics_available: true, metrics: metrics(2, 0)});
  return {queues, live: {version: 1, account_id: A, generated_at: timestamp,
    window: {from: timestamp - 3600, to: timestamp, seconds: 3600}, queues,
    pagination: {page_size: selected ? 1 : 50, has_more: false, next_start_queue_id: null},
    source: {coverage: 'observed_replicas', all_known_sources_responded: true, consistent: true,
      atomic_snapshot: false, status: 'available', reason: 'consensus', observation_started_at: timestamp, observation_finished_at: timestamp},
    capabilities: {live_call_details: selected, agent_runtime: false, websocket_updates: false, historical_reporting: false},
    calls: selected ? {available: true, complete: true, truncated: false, limit: 200, observed_count: 2,
      order: 'queue_id_entered_call_id', rows: [
        {queue_id: Q, call_id: 'handled', status: 'handled', entered_at: timestamp - 100, handled_at: timestamp - 40},
        {queue_id: Q, call_id: 'waiting', status: 'waiting', entered_at: timestamp - 75, handled_at: null}]} : null},
    roster: [U], agents: [{id: U, first_name: 'Ada', last_name: 'Agent'}, {id: V, first_name: 'Other', queues: [Q]}],
    statuses: {[U]: {status: 'ready'}, [V]: {status: 'ready'}}};
}
function model(f, results = data(true), failures = {}, meta = {}) {
  return f.app.formatLiveDashboard(results, failures, {queueId: Q, receivedAt: now, page: paging(), ...meta});
}
test('overview read seam uses one bounded live GET, not legacy inventory/stats or historical requests', () => {
  const f = fixture(), reads = [];
  f.monster.request = o => { reads.push(o.resource); assert.equal(o.data.pageSize, 50); o.success({status: 'success', data: data().live}); };
  f.app.requestCompleteList = f.app.request = () => assert.fail('Unexpected supplementary request');
  f.seam.call(f.app, null, (errors, result) => { assert.deepEqual(plain(errors), {}); assert.equal(result.queues.length, 2); });
  assert.deepEqual(reads, ['acdc.live.overview']);
  reads.forEach(r => assert.equal(f.app.requests[r].verb, 'GET'));
});
test('detail adds only selected roster, agent names and global observed statuses', () => {
  const f = fixture(), reads = [];
  f.monster.request = o => { reads.push([o.resource, plain(o.data)]); o.success({data: data(true).live}); };
  f.app.requestCompleteList = (r, d, cb) => { reads.push([r, plain(d)]); cb(null, []); };
  f.app.request = (r, d, cb) => { reads.push([r, plain(d)]); cb(null, {}); };
  f.seam.call(f.app, Q, () => {});
  assert.deepEqual(reads.map(r => r[0]), ['acdc.live.detail', 'acdc.queues.roster', 'acdc.agents.list', 'acdc.agents.statuses']);
  assert.deepEqual(reads[1][1], {accountId: A, queueId: Q});
  reads.forEach(([r]) => assert.equal(f.app.requests[r].verb, 'GET'));
});
test('malformed envelope and contradictory pagination cannot become observed zeroes', () => {
  const invalidPage = data().live; invalidPage.pagination.has_more = true;
  for (const response of [null, {status: 'error'}, {data: {}}, {data: invalidPage}]) {
    const f = fixture(); f.monster.request = o => o.success(response);
    f.seam.call(f.app, null, errors => assert(errors.live));
  }
});
test('DTO queue inventory fails closed on malformed, duplicate or unsafe identifiers', () => {
  const {app} = fixture();
  for (const queues of [null, {}, [null], [data().queues[0], data().queues[0]], [{id: '../q'}], Array(101).fill(data().queues[0])]) {
    const raw = data().live; raw.queues = queues; assert.equal(app.liveSnapshotValid(raw, A, null, paging()), false);
  }
  assert.equal(app.liveSnapshotValid(data().live, A, null, paging()), true);
});
test('malformed, blank and oversized queue names fall back to IDs before sorting and detail rendering', () => {
  const f = fixture();
  for (const name of [null, {}, 9, '', '   ', 'x'.repeat(257)]) {
    const results = data(true); results.queues[0].name = name;
    const result = model(f, results); assert.equal(result.queue.name, Q); assert.equal(result.selectedCard.name, Q);
  }
});
test('only selected queue active records and authoritative roster IDs reach detail', () => {
  const result = model(fixture());
  assert.equal(result.calls.length, 2); assert.equal(result.members.length, 1);
  assert.equal(result.members[0].name, 'Ada Agent'); assert.equal(result.members[0].status, 'Ready (global)');
  assert.equal(result.rosterCount, 1); assert.equal(result.selectedCard.waiting, 1); assert.equal(result.selectedCard.handling, 1);
  assert(!JSON.stringify(result.calls).includes('Other queue secret'));
  assert(!JSON.stringify(result.members).includes('Other'));
  for (const key of ['online', 'eligible', 'ready', 'sla', 'serviceLevel']) assert.equal(result[key], undefined);
});
test('partial observation shows unknown while complete empty calls show observed zero', () => {
  const f = fixture();
  const input = data(true); Object.assign(input.live.source, {status: 'partial', reason: 'source_timeout', consistent: false, all_known_sources_responded: false});
  Object.assign(input.queues[0], {metrics_available: false, metrics: null});
  Object.assign(input.live.calls, {available: false, complete: false, observed_count: null, rows: []});
  assert(f.app.liveSnapshotValid(input.live, A, Q, paging()));
  const result = model(f, input); assert.equal(result.available, false); assert.equal(result.selectedCard.waiting, '—'); assert(result.hasWarnings);
  const complete = data(true); complete.queues[0].metrics = metrics(0, 0); complete.live.calls.rows = []; complete.live.calls.observed_count = 0;
  const empty = model(f, complete);
  assert.equal(empty.available, true); assert.equal(empty.selectedCard.waiting, 0);
  const html = detail({...empty, i18n: strings}); assert(html.includes('does not prove the queue is empty'));
});
test('duplicate identities and unknown statuses cannot inflate or quietly drop records', () => {
  const f = fixture();
  for (const row of [data(true).live.calls.rows[0], {...data(true).live.calls.rows[1], status: 'unexpected'}]) {
    const input = data(true); input.live.calls.rows[1] = row;
    assert.equal(f.app.liveSnapshotValid(input.live, A, Q, paging()), false);
  }
});
test('detail display is capped with explicit notices while counts still cover all returned rows and roster IDs', () => {
  const f = fixture(), input = data(true);
  input.queues[0].metrics = metrics(300, 0);
  Object.assign(input.live.calls, {observed_count: 300, truncated: true, complete: false,
    rows: Array.from({length: 200}, (_, n) => ({queue_id: Q, call_id: 'call-' + n, status: 'waiting', entered_at: timestamp - 300 + n, handled_at: null}))});
  input.roster = Array.from({length: 250}, (_, n) => 'agent-' + n);
  const result = model(f, input); assert.equal(result.calls.length, 200); assert.equal(result.members.length, 200);
  assert.equal(result.selectedCard.waiting, 300); assert.equal(result.rosterCount, 250);
  assert.equal(result.callsTruncated, true); assert.equal(result.membersTruncated, true);
  const html = detail({...result, i18n: strings});
  assert(html.includes(strings.acdc.dashboard.callsTruncated)); assert(html.includes(strings.acdc.dashboard.membersTruncated));
});
test('unverified roster or statuses remain unknown; names failure preserves verified member IDs', () => {
  const f = fixture();
  for (const roster of [null, [U, U], [{}], ['../bad']]) { const result = model(f, {...data(true), roster}); assert.equal(result.rosterCount, '—'); assert.equal(result.members.length, 0); }
  assert.equal(model(f, data(true), {statuses: true}).members[0].status, 'Unknown');
  assert.equal(model(f, data(true), {agents: true}).members[0].name, U);
  assert.equal(model(f, {...data(true), roster: []}).rosterCount, 0);
});
test('observation-window timestamps and retrieval age both make snapshots stale', () => {
  const f = fixture(); assert.equal(model(f).stale, false);
  assert.equal(model(f, data(true), {}, {receivedAt: now - 30000}).stale, true);
  const input = data(true); input.live.source.observation_finished_at -= 31;
  assert.equal(model(f, input).stale, true, 'Receiving an old response must not reset freshness');
  assert.equal(model(f, data(true), {}, {refreshFailed: true}).stale, true);
  assert.equal(model(f).sourceTime, undefined);
  assert(strings.acdc.dashboard.responseTime.includes('Observation window'));
});
test('elapsed Unix values are frozen to observation window, signed times supported and invalid values unknown', () => {
  const f = fixture(), result = model(f);
  assert.equal(result.calls.find(c => c.status === 'Waiting').wait, '1:15');
  const handled = result.calls.find(c => c.status === 'In progress'); assert.equal(handled.wait, '1:00'); assert.equal(handled.talk, '0:40');
  for (const value of [null, '1', NaN, timestamp + 1]) assert.equal(f.app.liveDuration(value, timestamp), '—');
  assert.equal(f.app.liveDuration(-2, 0), '0:02');
  f.advance(40000); assert.equal(model(f).calls.find(c => c.status === 'Waiting').wait, '1:15');
});
test('first load, overview click, detail refresh and back have distinct generation-protected states', () => {
  const f = fixture(); f.app.renderDashboard(); assert(f.navigation[0].loading); assert.equal(f.requests[0].queueId, null);
  f.reply(0); const overviewView = f.current(); assert.equal(overviewView.spec.name, 'dashboard');
  overviewView.find('.acdc-open-live-queue').trigger('click', new Element().attr('data-queue-id', Q));
  assert.equal(f.requests[1].queueId, Q); f.reply(1); assert.equal(f.current().spec.name, 'dashboard-detail');
  f.current().find('.acdc-refresh').trigger('click'); assert.equal(f.current().spec.data.updating, true); assert.equal(f.requests[2].queueId, Q);
  f.reply(2); f.current().find('.acdc-live-back').trigger('click'); assert.equal(f.requests[3].queueId, null);
});
test('old navigation or foreign-account responses cannot overwrite current UI or populate cache', () => {
  const f = fixture(); f.app.renderDashboard(); f.app.renderLiveDashboard(Q); f.reply(0); assert.equal(f.views.length, 0);
  f.app.accountId = B; f.reply(1); assert.equal(f.views.length, 0); assert.equal(f.app.appFlags.acdc.liveDashboardSnapshot, undefined);
});
test('account switch cannot display a cached snapshot from another account', () => {
  const f = fixture(); f.app.renderDashboard(); f.reply(0); assert(f.current());
  f.app.accountId = B; f.app.renderDashboard(); assert.equal(f.current(), undefined); assert(f.navigation.at(-1).loading);
});
test('refresh failure retains exact previous snapshot stale; first failure stays error with retry', () => {
  const f = fixture(); f.app.renderDashboard(); f.reply(0); f.app.renderDashboard(); f.reply(1, {}, {live: true});
  assert.equal(f.current().spec.data.stale, true); assert.equal(f.current().spec.data.refreshFailed, true);
  assert.equal(f.current().spec.data.queueRows.find(row => row.id === Q).waiting, 1);
  const first = fixture(); first.app.renderDashboard(); first.reply(0, {}, {live: true}); assert.equal(first.errors.length, 1); assert(!first.current());
  first.errors[0].retry(); assert.equal(first.requests.length, 2);
});
test('a missing or forbidden selected queue clears cache; a wrong scoped response cannot replace detail', () => {
  const f = fixture(); f.app.renderLiveDashboard(Q); f.reply(0); f.app.renderLiveDashboard(Q);
  const results = data(true); results.queues[0].id = R; f.reply(1, results);
  assert.equal(f.current().spec.data.refreshFailed, true); assert.equal(f.current().spec.data.queue.id, Q);
  f.app.renderLiveDashboard(Q); f.reply(2, {}, {live: true, denied: true});
  assert.equal(f.current(), undefined); assert.equal(f.app.appFlags.acdc.liveDashboardSnapshot, undefined);
});
test('stale timer changes display without refetch; old timer is harmless after navigation', () => {
  const f = fixture(); f.app.renderDashboard(); f.reply(0); const view = f.current();
  f.advance(30000); f.fireTimer(); assert.equal(view.find('.acdc-live-freshness').text(), strings.acdc.dashboard.stale);
  assert.equal(view.find('.acdc-live-stale-note').prop('hidden'), false); assert.equal(f.requests.length, 1);
  f.app.renderDashboard(); f.reply(1); assert.equal(f.timers.size, 0, 'Old response is already stale');
});
test('queue search filters names as text, including literal markup characters, without requests', () => {
  const f = fixture(); f.app.renderDashboard(); f.reply(0); const view = f.current();
  const support = new Element(), sales = new Element(); support.find('.acdc-live-queue-name').text('Support <team>'); sales.find('.acdc-live-queue-name').text('Sales');
  view.find('.acdc-live-queue-card').items = [support, sales];
  view.find('.acdc-live-search').val('<team>').trigger('input'); assert.equal(support.prop('hidden'), false); assert.equal(sales.prop('hidden'), true);
  view.find('.acdc-live-search').val('none').trigger('input'); assert.equal(view.find('.acdc-live-no-match').prop('hidden'), false);
  assert.equal(f.requests.length, 1);
});
test('edit and agent controls navigate to existing implementations, no automatic mutation', () => {
  const f = fixture(); f.app.renderLiveDashboard(Q); f.reply(0); const view = f.current();
  view.find('.acdc-live-edit, .acdc-live-add').trigger('click', new Element());
  assert.equal(f.app.appFlags.acdc.currentTab, 'queues'); assert.deepEqual(f.navigation.at(-1), {editor: Q}); assert.equal(f.timers.size, 0);
  const g = fixture(); g.app.renderLiveDashboard(Q); g.reply(0); g.current().find('.acdc-live-agents').trigger('click');
  assert.equal(g.app.appFlags.acdc.currentTab, 'agents'); assert.deepEqual(g.navigation.at(-1), {agents: true});
});
test('templates escape all API labels and expose actual zero, empty, unknown and stale states', () => {
  const f = fixture(), input = data(true); input.queues[0].name = '<img src=x onerror=alert(1)>';
  input.agents[0].first_name = '<script>alert(1)</script>'; input.live.calls.rows[0].call_id = '<svg onload=x>';
  const result = model(f, input); const html = overview({...result, i18n: strings}) + detail({...result, i18n: strings});
  for (const unsafe of ['<img', '<script', '<svg']) assert(!html.includes(unsafe)); assert(html.includes('&lt;img'));
  assert(html.includes('role="status"')); assert(html.includes('data-queue-id="' + Q + '"'));
  assert(!html.includes('Agent Performance')); assert(!html.includes('Service Level')); assert(!html.includes('Recent calls'));
  const emptyInput = data(); emptyInput.queues = []; emptyInput.live.queues = [];
  const empty = overview({...model(f, emptyInput), i18n: strings}); assert(empty.includes(strings.acdc.dashboard.noQueues));
});
test('legacy queue stats and global-status formatter remain unchanged for other tabs', () => {
  const {app} = fixture();
  assert.deepEqual(plain(app.buildQueueStats([{id: Q, name: 'Support'}], [{queue_id: Q, status: 'handled'}, {queue_id: Q, status: 'abandoned'}])),
    [{id: Q, name: 'Support', waiting: 0, handling: 1, abandoned: 1, processed: 0}]);
  assert.equal(app.statusClass('ready'), 'online');
});
console.log(JSON.stringify({result: 'PASS', groups, network: false, browser: false, live_writes: false}));
