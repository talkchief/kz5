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
function fixture(options = {}) {
  let app, clock = now, nextTimer = 0;
  const timers = new Map(), requests = [], views = [], errors = [], navigation = [], bindings = [], observers = [], container = new Element(), content = new Element();
  const schedule = (fn, ms) => { timers.set(++nextTimer, {fn, ms, at: clock + ms}); return nextTimer; };
  const domDocument = {documentElement: {}, activeElement: null};
  const jquery = value => value; jquery.trim = value => String(value).trim();
  jquery.contains = (root, node) => node && node.attached;
  const monster = {apps: {}, ui: {}, socket: {connects: 0,
    connect() { this.connects++; return true; },
    bind(params) {
      assert.equal(bindings.filter(b => b.pending && !b.cancelled).length, 0, 'Only one pending native authorization');
      const binding = {params: {...params, lifecycle: {...params.lifecycle}}, cancelled: 0, pending: true}; bindings.push(binding);
      for (const key of ['onAck', 'onError', 'onDisconnect']) binding.params.lifecycle[key] = info => { binding.pending = false; params.lifecycle[key](info); };
      if (options.syncAck) binding.params.lifecycle.onAck({accountId: params.accountId, binding: params.binding, connectionGeneration: 1});
      return () => { binding.cancelled++; binding.pending = false; };
    }
  }};
  class Clock extends Date { static now() { return clock; } }
  vm.runInNewContext(source, {
    define(factory) { app = factory(name => name === 'jquery' ? jquery : name === 'lodash' ? lodash : monster); },
    Date: Clock, Math,
    setTimeout: schedule,
    clearTimeout(id) { timers.delete(id); },
    ...(options.dom ? {document: domDocument, MutationObserver: class {
      constructor(fn) { this.fn = fn; observers.push(this); }
      observe() { this.active = true; }
      disconnect() { this.active = false; }
    }} : {})
  }, {filename: path.join(root, 'app.js')});
  app.i18n.active = () => strings;
  app.accountId = A;
  app.appFlags.acdc.container = container;
  app.getContentContainer = () => content;
  app.getTemplate = spec => {
    const element = new Element(); element[0] = element; element.attached = true; element.spec = spec;
    const search = element.find('.acdc-live-search'); search[0] = search;
    search.focus = () => { domDocument.activeElement = search; };
    search.setSelectionRange = (start, end, direction) => Object.assign(search, {selectionStart: start, selectionEnd: end, selectionDirection: direction});
    views.push(element); return element;
  };
  app.renderLoading = message => { content.empty(); navigation.push({loading: message}); };
  app.renderError = (message, retry) => { content.empty(); errors.push({message, retry}); };
  app.renderQueueForm = id => { ++app.appFlags.acdc.requestGeneration; navigation.push({editor: id}); };
  app.renderAgents = () => navigation.push({agents: true});
  const seam = app.requestLiveDashboard;
  app.requestLiveDashboard = (queueId, callback, page) => requests.push({queueId, callback, page});
  return {app, seam, monster, requests, views, errors, navigation, content, container, timers, bindings, domDocument,
    scheduler: {setTimeout: schedule, clearTimeout: id => timers.delete(id)},
    advance(ms) { clock += ms; },
    tick(ms) {
      const end = clock + ms; let limit = 1000;
      for (;;) {
        const next = [...timers].filter(([, t]) => t.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
        if (!next) break; assert(--limit > 0, 'Unbounded timer loop');
        clock = next[1].at; timers.delete(next[0]); next[1].fn();
      }
      clock = end;
    },
    ack(index, generation = 1) { const p = bindings[index].params; p.lifecycle.onAck({accountId: p.accountId, binding: p.binding, connectionGeneration: generation}); },
    event(index, event) { const p = bindings[index].params; p.callback(event || {version: 1, account_id: p.accountId, queue_id: p.binding.split('.').pop()}); },
    detach() { content.items[0].attached = false; observers.filter(o => o.active).forEach(o => o.fn()); },
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
function agentData(rows = [{agent_id: U, name: 'Ada Agent', observed: true, queue_member: true, state: 'ready', reason: 'observed'}]) {
  return {limit: 200, roster_complete: true, truncated: false, runtime_complete: rows.every(row => row.observed),
    endpoint_reachability_verified: false, observation_started: timestamp, observation_finished: timestamp, rows};
}
function data(selected = false) {
  const queues = [{id: Q, name: 'Support', strategy: 'round_robin', metrics_available: true, metrics: metrics()}];
  if (!selected) queues.push({id: R, name: 'Sales', strategy: null, metrics_available: true, metrics: metrics(2, 0)});
  return {queues, live: {version: 1, account_id: A, generated_at: timestamp,
    window: {from: timestamp - 3600, to: timestamp, seconds: 3600}, queues,
    pagination: {page_size: selected ? 1 : 50, has_more: false, next_start_queue_id: null},
    source: {coverage: 'observed_replicas', all_known_sources_responded: true, consistent: true,
      atomic_snapshot: false, status: 'available', reason: 'consensus', observation_started_at: timestamp, observation_finished_at: timestamp},
    capabilities: {live_call_details: selected, agent_runtime: selected, websocket_updates: false, historical_reporting: false},
    agents: selected ? agentData() : null,
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
test('detail uses one GET with authorized roster/runtime DTO and no supplemental reads', () => {
  const f = fixture(), reads = [];
  f.monster.request = o => { reads.push([o.resource, plain(o.data)]); o.success({data: data(true).live}); };
  f.app.requestCompleteList = f.app.request = () => assert.fail('No supplemental read is authorized by this UI seam');
  f.seam.call(f.app, Q, () => {});
  assert.deepEqual(reads.map(r => r[0]), ['acdc.live.detail']);
  assert.deepEqual(reads[0][1], {accountId: A, queueId: Q, pageSize: 50});
  reads.forEach(([r]) => assert.equal(f.app.requests[r].verb, 'GET'));
});
test('all three strict live resources suppress the transport cache-buster without changing unrelated resources', () => {
  const {app} = fixture();
  for (const id of ['acdc.live.overview', 'acdc.live.page', 'acdc.live.detail']) {
    assert.equal(app.requests[id].cache, true); assert.equal(app.requests[id].verb, 'GET');
  }
  assert.equal(app.requests['acdc.queues.list'].cache, undefined);
  assert.equal(app.requests['acdc.editor.get'].cache, undefined);
});
test('actual Monster defineRequest/request constructor emits exact live query keys; former default reproduces forbidden underscore', () => {
  const framework = process.env.KAZOO_MONSTER_REQUEST_SOURCE || '/usr/local/src/kazoo5-installer/monster-ui/src/js/lib/monster.js';
  assert(path.isAbsolute(framework));
  const bytes = fs.readFileSync(framework), sent = [], publications = [];
  const jquery = {each: lodash.forEach, ajax: settings => { sent.push(settings); return settings; }};
  const dependencies = {jquery, lodash, handlebars: Handlebars,
    cookies: {get() {}, set() {}, remove() {}}, postal: {channel: () => ({}), publish: m => publications.push(m)}};
  let actual;
  vm.runInNewContext(bytes.toString('utf8'), {
    define(factory) { actual = factory(name => dependencies[name] || {}); },
    window: {location: {protocol: 'https:', hostname: 'fixture.invalid'}}, console
  }, {filename: framework, timeout: 1000});
  actual.config = {api: {default: 'https://fixture.invalid/v2/'}};
  const {app} = fixture(); app.getAuthToken = () => 'synthetic-never-sent';
  const rows = [
    ['acdc.live.overview', {accountId: A, pageSize: 50}, '/v2/accounts/' + A + '/queues/live?page_size=50'],
    ['acdc.live.page', {accountId: A, pageSize: 50, startQueueId: R}, '/v2/accounts/' + A + '/queues/live?page_size=50&start_queue_id=' + R],
    ['acdc.live.detail', {accountId: A, queueId: Q, pageSize: 50}, '/v2/accounts/' + A + '/queues/' + Q + '/live']
  ];
  for (const [resource, data, expected] of rows) {
    actual._defineRequest(resource, app.requests[resource], app);
    actual.request({resource, data});
    const settings = sent.pop(), url = new URL(settings.url);
    assert.equal(settings.type, 'GET'); assert.equal(settings.cache, true);
    assert.equal(url.pathname + url.search, expected); assert.equal(url.searchParams.has('_'), false);
    const baseline = {...app.requests[resource]}; delete baseline.cache;
    actual._defineRequest(resource, baseline, app); actual.request({resource, data});
    const previous = sent.pop();
    assert.equal(previous.cache, false); assert.equal(new URL(previous.url).searchParams.has('_'), true);
  }
  assert.equal(publications.length, 0, 'AJAX boundary is substituted; no headers, authentication or network executed');
  assert(bytes.equals(fs.readFileSync(framework)), 'Actual request source changed during fixture');
  console.log('INFO actual Monster request source SHA256 ' + require('crypto').createHash('sha256').update(bytes).digest('hex'));
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
  assert.equal(result.members[0].name, 'Ada Agent'); assert.equal(result.members[0].status, 'Ready · observed');
  assert.equal(result.members[0].membership, 'Member · observed');
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
test('detail call counts cover full DTO observations; truncated roster total stays unknown', () => {
  const f = fixture(), input = data(true);
  input.queues[0].metrics = metrics(300, 0);
  Object.assign(input.live.calls, {observed_count: 300, truncated: true, complete: false,
    rows: Array.from({length: 200}, (_, n) => ({queue_id: Q, call_id: 'call-' + n, status: 'waiting', entered_at: timestamp - 300 + n, handled_at: null}))});
  input.live.agents = {...agentData(Array.from({length: 200}, (_, n) => ({agent_id: (n + 1).toString(16).padStart(32, '0'),
    name: 'Agent ' + n, observed: true, queue_member: true, state: 'ready', reason: 'observed'}))),
    truncated: true, roster_complete: false, runtime_complete: false};
  const result = model(f, input); assert.equal(result.calls.length, 200); assert.equal(result.members.length, 200);
  assert.equal(result.selectedCard.waiting, 300); assert.equal(result.rosterCount, '—');
  assert.equal(result.callsTruncated, true); assert.equal(result.membersTruncated, true);
  const html = detail({...result, i18n: strings});
  assert(html.includes(strings.acdc.dashboard.callsTruncated)); assert(html.includes(strings.acdc.dashboard.membersTruncated));
});
test('invalid agents fail closed; unavailable runtime preserves authorized names with unknown state/member', () => {
  const f = fixture();
  for (const agents of [null, [U, U], {}, {rows: ['../bad']}]) {
    const input = data(true); input.live.agents = agents;
    assert.equal(f.app.liveSnapshotValid(input.live, A, Q, paging()), false);
    const result = model(f, input); assert.equal(result.rosterCount, '—'); assert.equal(result.members.length, 0);
  }
  const input = data(true); Object.assign(input.live.agents, {runtime_complete: false, observation_started: null, observation_finished: null});
  Object.assign(input.live.agents.rows[0], {observed: false, state: null, queue_member: null, reason: 'source_unavailable'});
  assert.equal(model(f, input).members[0].status, 'Unknown'); assert.equal(model(f, input).members[0].membership, 'Unknown');
  assert.equal(model(f, input).members[0].name, 'Ada Agent');
  input.live.agents = agentData([]); assert.equal(model(f, input).rosterCount, 0);
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
  input.live.agents.rows[0].name = '<script>alert(1)</script>'; input.live.calls.rows[0].call_id = '<svg onload=x>';
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
function liveData(detail = false) { const value = data(detail); value.live.capabilities.websocket_updates = true; return value; }
test('unsupported capability is manual-only; enabled capability binds exact authorized page IDs and separate account', () => {
  const f = fixture(); f.app.renderDashboard(); f.reply(0); f.tick(15000);
  assert.equal(f.bindings.length, 0); assert.equal(f.requests.length, 1); assert.equal(f.monster.socket.connects, 0);
  assert.equal(f.current().find('.acdc-live-transport').text(), strings.acdc.dashboard.transports.unavailable);
  f.app.renderDashboard(); f.reply(1, liveData());
  assert.equal(f.bindings.length, 1, 'Second authorization is local-only until first ACK');
  assert.equal(Object.keys(f.app.appFlags.acdc.liveDashboardController.bindings).length, 2); f.ack(0);
  assert.deepEqual(f.bindings.map(b => [b.params.accountId, b.params.binding, b.params.source]),
    [[A, 'queue_live.changed.' + Q, 'acdc'], [A, 'queue_live.changed.' + R, 'acdc']]);
  assert.equal(f.monster.socket.connects, 2); assert(f.bindings.every(b => b.params.lifecycle.timeoutMs === 3000));
});
test('ACK burst and invalidations coalesce; one snapshot in flight remembers one dirty follow-up', () => {
  const f = fixture(); f.app.renderDashboard(); f.reply(0, liveData()); f.ack(0); f.ack(1);
  for (let i = 0; i < 30; i++) f.event(i % 2);
  f.tick(99); assert.equal(f.requests.length, 1); f.tick(1); assert.equal(f.requests.length, 2);
  for (let i = 0; i < 30; i++) { f.event(0); f.app.renderDashboard(); }
  f.tick(500); assert.equal(f.requests.length, 2, 'No overlapping snapshot batches');
  f.reply(1, liveData()); f.tick(100); assert.equal(f.requests.length, 3);
  f.reply(2, liveData()); f.tick(1000); assert.equal(f.requests.length, 3);
  assert.equal(f.bindings.length, 2); assert(f.bindings.every(b => b.cancelled === 0));
});
test('synchronous shared ACK is safe and unchanged scope does not bind/ACK loop', () => {
  const f = fixture({syncAck: true}); f.app.renderLiveDashboard(Q); f.reply(0, liveData(true));
  assert.equal(f.bindings.length, 1); f.tick(100); assert.equal(f.requests.length, 2);
  f.reply(1, liveData(true)); f.tick(1000); assert.equal(f.requests.length, 2); assert.equal(f.bindings.length, 1);
});
test('event version/account/queue must match and pre-ACK events cannot request snapshots', () => {
  const f = fixture(); f.app.renderLiveDashboard(Q); f.reply(0, liveData(true)); f.event(0); f.tick(100); assert.equal(f.requests.length, 1);
  f.ack(0); f.tick(100); f.reply(1, liveData(true));
  for (const event of [null, {}, {version: 2, account_id: A, queue_id: Q}, {version: 1, account_id: B, queue_id: Q},
    {version: 1, account_id: A, queue_id: R}]) f.bindings[0].params.callback(event);
  f.tick(1000); assert.equal(f.requests.length, 2); f.event(0); f.tick(100); assert.equal(f.requests.length, 3);
});
test('disconnect keeps counts stale, reconnect ACK resnapshots and periodic repair survives missing events', () => {
  const f = fixture(); f.app.renderLiveDashboard(Q); f.reply(0, liveData(true)); f.ack(0); f.tick(100); f.reply(1, liveData(true));
  f.bindings[0].params.lifecycle.onDisconnect({code: 'disconnected'});
  assert(f.current().find('.acdc-live-freshness').hasClass('is-stale'));
  assert.equal(f.current().spec.data.selectedCard.waiting, 1);
  assert.equal(f.current().find('.acdc-live-transport').text(), strings.acdc.dashboard.transports.disconnected);
  f.tick(1000); assert.equal(f.bindings[0].cancelled, 1); f.ack(1, 2); f.tick(100); assert.equal(f.requests.length, 3); f.reply(2, liveData(true));
  assert.equal(f.bindings.length, 2); f.tick(15000); assert.equal(f.requests.length, 4, 'Reconcile without any event');
});
test('subscription error uses bounded backoff while periodic reconciliation continues', () => {
  const f = fixture(); f.app.renderLiveDashboard(Q); f.reply(0, liveData(true));
  f.bindings[0].params.lifecycle.onError({code: 'rejected'}); f.tick(14999); assert.equal(f.requests.length, 1);
  assert(f.current().find('.acdc-live-freshness').hasClass('is-stale'));
  f.tick(101); assert.equal(f.requests.length, 2); f.reply(1, liveData(true));
  assert.equal(f.bindings.length, 2); assert.equal(f.bindings[0].cancelled, 1);
  f.bindings[1].params.lifecycle.onError({code: 'timeout'}); f.tick(1000); assert.equal(f.requests.length, 2);
});
test('capability true to false retires bindings and periodic repair without replacing counts with zero', () => {
  const f = fixture(); f.app.renderDashboard(); f.reply(0, liveData()); f.app.renderDashboard(); f.reply(1);
  assert(f.bindings.every(b => b.cancelled === 1)); f.tick(16000); assert.equal(f.requests.length, 2);
  f.ack(0); f.event(0); f.tick(100); assert.equal(f.requests.length, 2);
  assert.equal(f.current().find('.acdc-live-transport').text(), strings.acdc.dashboard.transports.unavailable);
  assert.equal(f.current().spec.data.queueRows.find(q => q.id === Q).waiting, 1);
});
test('page shrink and navigation cancel exact listeners; stale callbacks cannot revive old scope', () => {
  const f = fixture(); f.app.renderDashboard(); f.reply(0, liveData()); f.ack(0);
  const smaller = liveData(); smaller.queues.pop(); f.app.renderDashboard(); f.reply(1, smaller);
  assert.equal(f.bindings[0].cancelled, 0); assert.equal(f.bindings[1].cancelled, 1);
  f.app.renderLiveDashboard(Q); assert.equal(f.bindings[0].cancelled, 1); f.reply(2, liveData(true));
  f.event(0); f.ack(1); f.tick(100); assert.equal(f.requests.length, 3);
  const page = {cursor: R, size: 50, history: [null]}; f.app.renderLiveDashboard(null, undefined, page);
  assert.equal(f.bindings[2].cancelled, 1); assert.deepEqual(plain(f.requests[3].page), page);
});
test('account/tab/DOM disposal cancels listeners, timers and late in-flight responses', () => {
  for (const boundary of ['account', 'tab', 'detach', 'editor']) {
    const f = fixture({dom: true}); f.app.renderLiveDashboard(Q); f.reply(0, liveData(true)); f.ack(0); f.tick(100);
    if (boundary === 'account') { f.app.accountId = B; f.event(0); }
    if (boundary === 'tab') f.app.renderSection('agents');
    if (boundary === 'detach') f.detach();
    if (boundary === 'editor') f.current().find('.acdc-live-edit, .acdc-live-add').trigger('click', new Element());
    assert.equal(f.bindings[0].cancelled, 1, boundary); assert.equal(f.timers.size, 0, boundary);
    const views = f.views.length; f.reply(1, liveData(true)); f.ack(0); f.event(0); f.tick(20000);
    assert.equal(f.views.length, views, boundary); assert.equal(f.requests.length, 2, boundary);
  }
});
test('401/403/404 cancels supported live scope immediately and does not retry automatically', () => {
  for (const status of [401, 403, 404]) {
    const f = fixture(); f.app.renderLiveDashboard(Q); f.reply(0, liveData(true)); f.app.renderLiveDashboard(Q);
    f.reply(1, {}, {live: true, denied: true, status}); assert.equal(f.bindings[0].cancelled, 1);
    assert.equal(f.app.appFlags.acdc.liveDashboardSnapshot, undefined); assert.equal(f.timers.size, 0);
    f.tick(20000); assert.equal(f.requests.length, 2);
  }
});
test('automatic same-page refresh preserves latest search, focus and selection through held GET and failure', () => {
  const f = fixture({dom: true}); f.app.renderDashboard(); f.reply(0, liveData());
  let search = f.current().find('.acdc-live-search'); search.val('Sup').trigger('input'); search.focus(); search.setSelectionRange(1, 3, 'backward');
  f.ack(0); f.tick(100);
  search = f.current().find('.acdc-live-search'); assert.equal(search.val(), 'Sup'); assert.equal(f.domDocument.activeElement, search);
  assert.deepEqual([search.selectionStart, search.selectionEnd, search.selectionDirection], [1, 3, 'backward']);
  search.val('Support latest').trigger('input'); search.setSelectionRange(4, 9, 'forward'); f.reply(1, liveData());
  search = f.current().find('.acdc-live-search'); assert.equal(search.val(), 'Support latest'); assert.equal(f.domDocument.activeElement, search);
  assert.deepEqual([search.selectionStart, search.selectionEnd, search.selectionDirection], [4, 9, 'forward']);
  f.event(0); f.tick(100); f.reply(2, {}, {live: true});
  search = f.current().find('.acdc-live-search'); assert.equal(search.val(), 'Support latest'); assert.equal(f.domDocument.activeElement, search);
  assert.equal(f.current().spec.data.refreshFailed, true);
});
test('same-page refresh never steals moved focus; queue/page/account navigation resets search', () => {
  const f = fixture({dom: true}); f.app.renderDashboard(); f.reply(0, liveData());
  f.current().find('.acdc-live-search').val('Support').trigger('input');
  const external = {}; f.domDocument.activeElement = external; f.ack(0); f.tick(100); f.reply(1, liveData());
  assert.equal(f.current().find('.acdc-live-search').val(), 'Support'); assert.equal(f.domDocument.activeElement, external);
  f.app.renderLiveDashboard(Q); f.reply(2, liveData(true)); f.app.renderDashboard(); f.reply(3, liveData());
  assert.equal(f.current().find('.acdc-live-search').val(), '');
  f.current().find('.acdc-live-search').val('Support').trigger('input');
  f.app.renderLiveDashboard(null, undefined, {cursor: Q, size: 50, history: [null]}); f.reply(4, liveData());
  assert.equal(f.current().find('.acdc-live-search').val(), '');
  f.current().find('.acdc-live-search').val('Support').trigger('input'); f.app.accountId = B; f.app.renderDashboard();
  const foreign = liveData(); foreign.live.account_id = B; f.reply(5, foreign);
  assert.equal(f.current().find('.acdc-live-search').val(), ''); assert.equal(f.domDocument.activeElement, external);
});
test('strict agents DTO rejects scope/cap/identity/state/completeness contradictions', () => {
  const f = fixture(), changes = [
    d => { delete d.agents; }, d => { d.capabilities.agent_runtime = false; },
    d => { d.agents.limit = 201; }, d => { d.agents.endpoint_reachability_verified = true; },
    d => { d.agents.extra = 'private'; }, d => { d.agents.roster_complete = false; },
    d => { d.agents.truncated = true; d.agents.roster_complete = false; d.agents.runtime_complete = false; },
    d => { d.agents.runtime_complete = false; }, d => { d.agents.observation_started = null; },
    d => { d.agents.observation_finished = d.agents.observation_started - 1; },
    d => { d.agents.rows.push(d.agents.rows[0]); }, d => { d.agents.rows[0].agent_id = '../foreign'; },
    d => { d.agents.rows[0].pid = '<0.1.0>'; }, d => { d.agents.rows[0].name = '\nsecret'; },
    d => { d.agents.rows[0].name = 'é'.repeat(129); }, d => { d.agents.rows[0].state = 'logout'; },
    d => { d.agents.rows[0].queue_member = null; }, d => { d.agents.rows[0].observed = false; },
    d => { d.agents.rows[0].reason = 'source_unavailable'; },
    d => { d.agents.rows = Array(201).fill(d.agents.rows[0]); }
  ];
  changes.forEach(change => { const input = data(true); change(input.live); assert.equal(f.app.liveSnapshotValid(input.live, A, Q, paging()), false); });
  const overviewData = data(); overviewData.live.agents = agentData(); assert.equal(f.app.liveSnapshotValid(overviewData.live, A, null, paging()), false);
});
test('all eight observed runtime states permit either membership without claiming reachability; unknown reasons stay unknown', () => {
  const f = fixture();
  for (const state of ['wait', 'sync', 'ready', 'ringing', 'answered', 'wrapup', 'paused', 'outbound']) for (const member of [true, false]) {
    const input = data(true); Object.assign(input.live.agents.rows[0], {state, queue_member: member});
    assert.equal(f.app.liveSnapshotValid(input.live, A, Q, paging()), true);
    assert.equal(model(f, input).members[0].membership, member ? strings.acdc.dashboard.queueMember : strings.acdc.dashboard.queueNotMember);
  }
  for (const reason of ['not_observed', 'inconsistent_sources', 'source_unavailable']) {
    const input = data(true); input.live.agents.runtime_complete = false;
    Object.assign(input.live.agents.rows[0], {observed: false, queue_member: null, state: null, reason});
    assert.equal(f.app.liveSnapshotValid(input.live, A, Q, paging()), true);
    assert.equal(model(f, input).members[0].status, 'Unknown'); assert.equal(model(f, input).members[0].membership, 'Unknown');
  }
  assert(strings.acdc.dashboard.memberContext.includes('does not verify endpoint reachability'));
});
test('available and unavailable empty agent rosters have distinct runtime completeness', () => {
  const f = fixture(), input = data(true); input.live.agents = agentData([]);
  assert.equal(f.app.liveSnapshotValid(input.live, A, Q, paging()), true); assert.equal(model(f, input).rosterCount, 0);
  Object.assign(input.live.agents, {observation_started: null, observation_finished: null, runtime_complete: false});
  assert.equal(f.app.liveSnapshotValid(input.live, A, Q, paging()), true);
  assert.equal(model(f, input).agentRuntimeStatus, strings.acdc.dashboard.runtimeIncomplete);
  input.live.agents.runtime_complete = true; assert.equal(f.app.liveSnapshotValid(input.live, A, Q, paging()), false);
});
test('100 local subscriptions admit exactly one pending authorization and drain only on asynchronous ACKs', () => {
  const f = fixture(), input = liveData(); input.queues.splice(0, input.queues.length, ...Array.from({length: 100}, (_, i) => ({
    id: (i + 1).toString(16).padStart(32, '0'), name: 'Queue ' + i, strategy: null, metrics_available: true, metrics: metrics()})));
  input.live.pagination.page_size = 100;
  f.app.renderLiveDashboard(null, undefined, {cursor: null, size: 100, history: []}); f.reply(0, input);
  assert.equal(f.bindings.length, 1); assert.equal(Object.keys(f.app.appFlags.acdc.liveDashboardController.bindings).length, 100);
  f.tick(999); assert.equal(f.bindings.length, 1, 'Do not churn a pending handle');
  for (let i = 0; i < 100; i++) { assert.equal(f.bindings.length, i + 1); f.ack(i); }
  assert.equal(f.bindings.length, 100); assert(f.bindings.every(b => !b.pending));
  f.tick(100); assert.equal(f.requests.length, 2, '100 ACKs coalesce to one snapshot');
});
test('busy rejection releases one slot with pacing, not a parallel burst or immediate retry loop', () => {
  const f = fixture(); f.app.renderDashboard(); f.reply(0, liveData());
  f.bindings[0].params.lifecycle.onError({code: 'rejected'}); f.tick(999); assert.equal(f.bindings.length, 1);
  f.tick(1); assert.equal(f.bindings.length, 2); f.ack(1); f.tick(100); f.reply(1, liveData());
  f.tick(13899); assert.equal(f.bindings.length, 2); f.tick(1); assert.equal(f.bindings.length, 3);
  assert.equal(f.bindings[2].params.binding, 'queue_live.changed.' + Q); assert.equal(f.bindings[0].cancelled, 1);
});
test('disconnect cancels framework replay handles and reconnect admits one handle awaiting real ACK', () => {
  const f = fixture(); f.app.renderDashboard(); f.reply(0, liveData()); f.ack(0); f.ack(1); f.tick(100); f.reply(1, liveData());
  f.bindings[0].params.lifecycle.onDisconnect({code: 'disconnected'});
  assert(f.bindings.every(b => b.cancelled === 1)); f.tick(1000); assert.equal(f.bindings.length, 3);
  f.tick(1000); assert.equal(f.bindings.length, 3, 'One pending handle waits, no per-second churn');
  f.ack(0, 2); assert.equal(f.bindings.length, 3, 'Old callback cannot advance admission');
  f.ack(2, 2); assert.equal(f.bindings.length, 4); f.ack(3, 2); f.tick(100);
  assert.equal(f.requests.length, 3); assert(f.bindings.slice(2).every(b => !b.pending));
  f.app.renderSection('agents'); assert(f.bindings.slice(2).every(b => b.cancelled === 1)); assert.equal(f.timers.size, 0);
});
test('connect false immediately cancels its desired handle; late timeout/ACK cannot replay before retry', () => {
  const f = fixture(); f.monster.socket.connect = () => false;
  f.app.renderLiveDashboard(Q); f.reply(0, liveData(true)); assert.equal(f.bindings[0].cancelled, 1);
  f.bindings[0].params.lifecycle.onError({code: 'timeout'}); f.ack(0); f.tick(14999);
  assert.equal(f.bindings.length, 1); assert.equal(f.requests.length, 1);
  f.monster.socket.connect = () => true; f.tick(1); assert.equal(f.bindings.length, 2); f.ack(1); f.tick(100);
  assert.equal(f.bindings[0].cancelled, 1); assert.equal(f.requests.length, 2);
});
test('only cleanup_pending gets three bounded one-second retries, then the existing fifteen-second floor', () => {
  const f = fixture(); f.app.renderLiveDashboard(Q); f.reply(0, liveData(true));
  for (let i = 0; i < 3; i++) {
    f.bindings[i].params.lifecycle.onError({code: 'cleanup_pending'});
    assert.equal(f.bindings[i].cancelled, 1); f.tick(999); assert.equal(f.bindings.length, i + 1);
    f.tick(1); assert.equal(f.bindings.length, i + 2);
  }
  f.bindings[3].params.lifecycle.onError({code: 'cleanup_pending'});
  f.tick(14999); assert.equal(f.bindings.length, 4); f.tick(1); assert.equal(f.bindings.length, 5);
  f.ack(4); assert.equal(f.app.appFlags.acdc.liveDashboardController.bindings[Q].cleanupRetries, 0);
  f.app.renderSection('agents'); assert.equal(f.timers.size, 0);
});
test('server/auth/transport errors never borrow cleanup retry speed, and navigation cancels pending local retry', () => {
  for (const code of ['rejected', 'timeout', 'send_failed', 'configuration_unavailable', 'cleanup_pending_wrong']) {
    const f = fixture(); f.app.renderLiveDashboard(Q); f.reply(0, liveData(true));
    f.bindings[0].params.lifecycle.onError({code}); f.tick(14999); assert.equal(f.bindings.length, 1);
    f.tick(1); assert.equal(f.bindings.length, 2);
  }
  const f = fixture(); f.app.renderLiveDashboard(Q); f.reply(0, liveData(true));
  f.bindings[0].params.lifecycle.onError({code: 'cleanup_pending'}); f.app.renderSection('agents');
  f.tick(20000); assert.equal(f.bindings.length, 1); assert.equal(f.timers.size, 0);
});
test('actual framework cleanup ACK permits one-second detail rebind and ACK snapshot after overview navigation', () => {
  const file = process.env.KAZOO_MONSTER_LIFECYCLE_SOURCE;
  assert(file && path.isAbsolute(file), 'Set KAZOO_MONSTER_LIFECYCLE_SOURCE to the current patched framework monster.socket.js');
  const bytes = fs.readFileSync(file), f = fixture(), sockets = [], publications = []; let api, requestId = 0;
  class Socket {
    static CONNECTING = 0; static OPEN = 1; static CLOSING = 2; static CLOSED = 3;
    constructor() { this.readyState = 0; this.events = new Map(); this.sent = []; sockets.push(this); }
    addEventListener(name, fn) { this.events.set(name, [...(this.events.get(name) || []), fn]); }
    emit(name, data) { (this.events.get(name) || []).slice().forEach(fn => fn(data)); }
    open() { this.readyState = 1; this.emit('open', {}); }
    close() { this.readyState = 3; this.emit('close', {wasClean: true}); }
    send(value) { assert.equal(this.readyState, 1); this.sent.push(JSON.parse(value)); }
    reply(request) { this.emit('message', {data: JSON.stringify({action: 'reply', request_id: request.request_id, status: 'success',
      data: {subscriptions: request.action === 'subscribe' ? [request.data.binding] : [],
        unsubscribed: request.action === 'unsubscribe' ? [request.data.binding] : []}})}); }
  }
  Object.assign(f.monster, {config: {api: {socket: 'wss://fixture.invalid/websocket'}}, isDev: () => true,
    util: {guid: () => 'fixture-' + ++requestId, getAuthToken: () => 'synthetic-never-real'},
    pub: name => publications.push(name), waterfall: (steps, done) => steps[0](done)});
  vm.runInNewContext(bytes.toString('utf8'), {
    define(factory) { api = factory(name => name === 'lodash' ? lodash : f.monster); },
    WebSocket: Socket, URL, window: {location: {protocol: 'https:'}},
    console: {log() {}, warn() {}}, ...f.scheduler
  }, {filename: file, timeout: 1000});
  f.monster.socket = api;
  const overview = liveData(); overview.queues = overview.live.queues = [overview.queues[0]];
  f.app.renderDashboard(); f.reply(0, overview); const socket = sockets[0]; socket.open();
  assert.equal(socket.sent.length, 1); assert.equal(socket.sent[0].action, 'subscribe'); socket.reply(socket.sent[0]);
  f.tick(100); f.reply(1, overview);
  f.app.renderLiveDashboard(Q); assert.equal(socket.sent[1].action, 'unsubscribe');
  f.reply(2, liveData(true)); // New bind arrives while real lifecycle entry is removing.
  assert.equal(socket.sent.length, 2, 'Cleanup-pending attempt must not send or borrow old ACK');
  assert.equal(f.app.appFlags.acdc.liveDashboardController.bindings[Q].cleanupRetries, 1);
  socket.reply(socket.sent[1]); f.tick(999); assert.equal(socket.sent.length, 2);
  f.tick(1); assert.equal(socket.sent.length, 3); assert.equal(socket.sent[2].action, 'subscribe');
  assert.equal(socket.sent[2].data.binding, 'queue_live.changed.' + Q); assert.equal(socket.sent[2].data.account_id, A);
  socket.reply(socket.sent[2]); f.tick(100); assert.equal(f.requests.length, 4);
  f.reply(3, liveData(true)); assert.equal(f.app.liveTransportState(f.app.appFlags.acdc.liveDashboardController), 'acknowledged');
  f.app.renderSection('agents'); assert.equal(socket.sent[3].action, 'unsubscribe'); socket.reply(socket.sent[3]);
  assert.equal(f.timers.size, 0); assert(!publications.includes('auth.retryLogin'));
  assert(bytes.equals(fs.readFileSync(file)), 'Actual lifecycle source changed during fixture');
  console.log('INFO actual Monster lifecycle source SHA256 ' + require('crypto').createHash('sha256').update(bytes).digest('hex'));
});
console.log(JSON.stringify({result: 'PASS', groups, network: false, browser: false, live_writes: false}));
