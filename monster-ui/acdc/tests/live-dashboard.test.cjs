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
const now = 1788739200000, offset = 62167219200, timestamp = now / 1000 + offset;
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
  class Clock extends Date { static now() { return clock; } }
  vm.runInNewContext(source, {
    define(factory) { app = factory(name => name === 'jquery' ? jquery : name === 'lodash' ? lodash : {apps: {}, ui: {}}); },
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
  app.requestLiveDashboard = (queueId, callback) => requests.push({queueId, callback});
  return {app, seam, requests, views, errors, navigation, content, container, timers,
    advance(ms) { clock += ms; },
    reply(index, results = data(), failures = {}) { requests[index].callback(failures, results); },
    current() { return content.items[0]; },
    fireTimer() { const entry = [...timers][0]; assert(entry); timers.delete(entry[0]); entry[1].fn(); }
  };
}
function data() {
  return {queues: [{id: Q, name: 'Support'}, {id: R, name: 'Sales'}],
    queueStats: {current_timestamp: timestamp, stats: [
      {queue_id: Q, call_id: 'waiting', status: 'waiting', entered_timestamp: timestamp - 75, caller_id_name: 'Caller', caller_id_number: '100'},
      {queue_id: Q, call_id: 'handled', status: 'handled', entered_timestamp: timestamp - 100, handled_timestamp: timestamp - 40, agent_id: U},
      {queue_id: Q, call_id: 'done', status: 'processed', entered_timestamp: timestamp - 200},
      {queue_id: R, call_id: 'foreign', status: 'waiting', caller_id_name: 'Other queue secret'},
      {queue_id: 'unlisted', call_id: 'not-listed', status: 'waiting'}]},
    roster: [U], agents: [{id: U, first_name: 'Ada', last_name: 'Agent'}, {id: V, first_name: 'Other', queues: [Q]}],
    statuses: {[U]: {status: 'ready'}, [V]: {status: 'ready'}}};
}
function model(f, results = data(), failures = {}, meta = {}) {
  return f.app.formatLiveDashboard(results, failures, {queueId: Q, receivedAt: now, ...meta});
}
test('overview read seam only uses existing inventory and stats, no history, status, writes or projection route', () => {
  const f = fixture(), reads = [];
  f.app.requestCompleteList = (r, d, cb) => { reads.push(r); cb(null, data().queues); };
  f.app.requestEnvelope = (r, d, cb) => { reads.push(r); cb(null, {status: 'success', data: data().queueStats}); };
  f.app.request = () => assert.fail('Unexpected request');
  f.seam.call(f.app, null, (errors, result) => { assert.deepEqual(plain(errors), {}); assert.equal(result.queues.length, 2); });
  assert.deepEqual(reads, ['acdc.queues.list', 'acdc.queues.stats']);
  reads.forEach(r => assert.equal(f.app.requests[r].verb, 'GET'));
});
test('detail adds only selected roster, agent names and global observed statuses', () => {
  const f = fixture(), reads = [];
  f.app.requestCompleteList = (r, d, cb) => { reads.push([r, plain(d)]); cb(null, []); };
  f.app.requestEnvelope = (r, d, cb) => { reads.push([r, plain(d)]); cb(null, {data: data().queueStats}); };
  f.app.request = (r, d, cb) => { reads.push([r, plain(d)]); cb(null, {}); };
  f.seam.call(f.app, Q, () => {});
  assert.deepEqual(reads.map(r => r[0]), ['acdc.queues.list', 'acdc.queues.stats', 'acdc.queues.roster', 'acdc.agents.list', 'acdc.agents.statuses']);
  assert.deepEqual(reads[2][1], {queueId: Q});
  reads.forEach(([r]) => assert.equal(f.app.requests[r].verb, 'GET'));
});
test('stats envelope errors and pagination cannot become observed zeroes', () => {
  for (const response of [null, {status: 'error'}, {data: data().queueStats, next_cursor: 'more'}, {data: data().queueStats, next_start_key: 'more'}]) {
    const f = fixture(); f.app.requestCompleteList = (r, d, cb) => cb(null, data().queues);
    f.app.requestEnvelope = (r, d, cb) => cb(null, response);
    f.seam.call(f.app, null, errors => assert(errors.queueStats));
  }
});
test('queue inventory fails closed on malformed, duplicate or unsafe identifiers', () => {
  const {app} = fixture();
  for (const queues of [null, {}, [null], [{id: Q}, {id: Q}], [{id: '../q'}], Array(1001).fill({id: Q})]) assert.equal(app.liveQueueInventoryValid(queues), false);
  assert.equal(app.liveQueueInventoryValid([]), true);
});
test('malformed, blank and oversized queue names fall back to IDs before sorting and detail rendering', () => {
  const f = fixture();
  for (const name of [null, {}, 9, '', '   ', 'x'.repeat(257)]) {
    const results = data(); results.queues[0].name = name;
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
test('missing, failed or malformed stats show unknown, while valid empty subset shows observed zero', () => {
  const f = fixture();
  for (const raw of [null, {}, {stats: []}, {current_timestamp: timestamp, stats: {}}, {current_timestamp: timestamp, stats: [{status: 'waiting'}]},
    {current_timestamp: timestamp + 120, stats: []}, {current_timestamp: '123', stats: []}]) {
    const result = model(f, {...data(), queueStats: raw}); assert.equal(result.available, false); assert.equal(result.selectedCard.waiting, '—'); assert(result.hasWarnings);
  }
  assert.equal(model(f, data(), {queueStats: true}).selectedCard.waiting, '—');
  const empty = model(f, {...data(), queueStats: {current_timestamp: timestamp, stats: []}});
  assert.equal(empty.available, true); assert.equal(empty.selectedCard.waiting, 0);
  const html = detail({...empty, i18n: strings}); assert(html.includes('does not prove the queue is empty'));
});
test('duplicate identities and unknown statuses cannot inflate or quietly drop records', () => {
  const f = fixture();
  for (const row of [data().queueStats.stats[0], {...data().queueStats.stats[0], status: 'unexpected'}]) {
    const input = data(); input.queueStats.stats.push(row);
    assert.equal(model(f, input).available, false);
  }
});
test('detail display is capped with explicit notices while counts still cover all returned rows and roster IDs', () => {
  const f = fixture(), input = data();
  input.queueStats.stats = Array.from({length: 300}, (_, n) => ({queue_id: Q, call_id: 'call-' + n, status: 'waiting', entered_timestamp: timestamp - n}));
  input.roster = Array.from({length: 250}, (_, n) => 'agent-' + n);
  const result = model(f, input); assert.equal(result.calls.length, 200); assert.equal(result.members.length, 200);
  assert.equal(result.selectedCard.waiting, 300); assert.equal(result.rosterCount, 250);
  assert.equal(result.callsTruncated, true); assert.equal(result.membersTruncated, true);
  const html = detail({...result, i18n: strings});
  assert(html.includes(strings.acdc.dashboard.callsTruncated)); assert(html.includes(strings.acdc.dashboard.membersTruncated));
});
test('unverified roster or statuses remain unknown; names failure preserves verified member IDs', () => {
  const f = fixture();
  for (const roster of [null, [U, U], [{}], ['../bad']]) { const result = model(f, {...data(), roster}); assert.equal(result.rosterCount, '—'); assert.equal(result.members.length, 0); }
  assert.equal(model(f, data(), {statuses: true}).members[0].status, 'Unknown');
  assert.equal(model(f, data(), {agents: true}).members[0].name, U);
  assert.equal(model(f, {...data(), roster: []}).rosterCount, 0);
});
test('response timestamps and client retrieval age both make snapshots stale without claiming observation freshness', () => {
  const f = fixture(); assert.equal(model(f).stale, false);
  assert.equal(model(f, data(), {}, {receivedAt: now - 30000}).stale, true);
  const input = data(); input.queueStats.current_timestamp -= 31;
  assert.equal(model(f, input).stale, true, 'Receiving an old response must not reset freshness');
  assert.equal(model(f, data(), {}, {refreshFailed: true}).stale, true);
  assert.equal(model(f).sourceTime, undefined);
  assert(strings.acdc.dashboard.responseTime.includes('not observation time'));
});
test('elapsed values are frozen to response with invalid timestamp values unknown', () => {
  const f = fixture(), result = model(f);
  assert.equal(result.calls.find(c => c.status === 'Waiting').wait, '1:15');
  const handled = result.calls.find(c => c.status === 'In progress'); assert.equal(handled.wait, '1:00'); assert.equal(handled.talk, '0:40');
  for (const value of [null, '1', NaN, timestamp + 1]) assert.equal(f.app.liveDuration(value, timestamp), '—');
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
  const f = fixture(); f.app.renderDashboard(); f.reply(0); f.app.renderDashboard(); f.reply(1, {}, {queues: true});
  assert.equal(f.current().spec.data.stale, true); assert.equal(f.current().spec.data.refreshFailed, true);
  assert.equal(f.current().spec.data.queueRows.find(row => row.id === Q).waiting, 1);
  const first = fixture(); first.app.renderDashboard(); first.reply(0, {}, {queues: true}); assert.equal(first.errors.length, 1); assert(!first.current());
  first.errors[0].retry(); assert.equal(first.requests.length, 2);
});
test('a later valid inventory removing the selected queue does not retain its old detail', () => {
  const f = fixture(); f.app.renderLiveDashboard(Q); f.reply(0); f.app.renderLiveDashboard(Q);
  const results = data(); results.queues = [{id: R, name: 'Sales'}]; f.reply(1, results);
  const result = f.current().spec.data; assert.equal(result.queueMissing, true);
  const html = detail({...result, i18n: strings}); assert(html.includes(strings.acdc.dashboard.queueMissing)); assert(!html.includes('Ada Agent'));
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
  const f = fixture(), input = data(); input.queues[0].name = '<img src=x onerror=alert(1)>';
  input.agents[0].first_name = '<script>alert(1)</script>'; input.queueStats.stats[0].caller_id_name = '<svg onload=x>';
  const result = model(f, input); const html = overview({...result, i18n: strings}) + detail({...result, i18n: strings});
  for (const unsafe of ['<img', '<script', '<svg']) assert(!html.includes(unsafe)); assert(html.includes('&lt;img'));
  assert(html.includes('role="status"')); assert(html.includes('data-queue-id="' + Q + '"'));
  assert(!html.includes('Agent Performance')); assert(!html.includes('Service Level')); assert(!html.includes('Recent calls'));
  const empty = overview({...model(f, {...data(), queues: []}), i18n: strings}); assert(empty.includes(strings.acdc.dashboard.noQueues));
});
test('legacy queue stats and global-status formatter remain unchanged for other tabs', () => {
  const {app} = fixture();
  assert.deepEqual(plain(app.buildQueueStats([{id: Q, name: 'Support'}], [{queue_id: Q, status: 'handled'}, {queue_id: Q, status: 'abandoned'}])),
    [{id: Q, name: 'Support', waiting: 0, handling: 1, abandoned: 1, processed: 0}]);
  assert.equal(app.statusClass('ready'), 'online');
});
console.log(JSON.stringify({result: 'PASS', groups, network: false, browser: false, live_writes: false}));
