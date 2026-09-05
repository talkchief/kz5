/*
 * Kazoo ACDC Call Center contract checks
 * SPDX-License-Identifier: MPL-2.0
 */
'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const appRoot = path.resolve(__dirname, '..');
const projectRoot = path.resolve(appRoot, '..', '..');
const lodash = require(require.resolve('lodash', { paths: [process.cwd()] }));
const source = fs.readFileSync(path.join(appRoot, 'app.js'), 'utf8');
let app;

function jqueryStub() {
	throw new Error('DOM access is outside this contract test');
}
jqueryStub.trim = function(value) {
	return String(value).trim();
};

vm.runInNewContext(source, {
	define: function(factory) {
		app = factory(function(dependency) {
			if (dependency === 'jquery') {
				return jqueryStub;
			}
			if (dependency === 'lodash') {
				return lodash;
			}
			if (dependency === 'monster') {
				return { apps: {}, ui: {} };
			}
			throw new Error('Unexpected AMD dependency: ' + dependency);
		});
	},
	setTimeout: setTimeout,
	Date: Date,
	Math: Math
}, { filename: path.join(appRoot, 'app.js') });

assert(app, 'AMD module did not export the ACDC app');
assert.strictEqual(app.requests['acdc.queues.update'].verb, 'PATCH');
assert.strictEqual(app.requests['acdc.queues.updateRoster'].verb, 'POST');
assert.match(app.requests['acdc.queues.roster'].url, /paginate=false/);
assert.match(app.requests['acdc.queues.updateRoster'].url, /paginate=false/);
assert.match(app.requests['acdc.queues.list'].url, /paginate=false/);
assert.match(app.requests['acdc.agents.list'].url, /paginate=false/);
assert.match(app.requests['acdc.callStats.list'].url, /page_size=20/);
assert.match(app.requests['acdc.callStats.list'].url, /created_from=\{createdFrom\}/);
assert.strictEqual(app.callStatsWindowSeconds, 86400);
assert.strictEqual(app.kazooEpochOffsetSeconds, 62167219200);
assert.strictEqual(app.requests['acdc.callflows.create'].verb, 'PUT');
assert.strictEqual(app.requests['acdc.callflows.update'].verb, 'PATCH');
assert.strictEqual(app.requests['acdc.callflows.delete'].verb, 'DELETE');
assert.strictEqual(app.requests['acdc.callbacks.list'].verb, 'GET');
assert.match(app.requests['acdc.callbacks.list'].url, /page_size=\{pageSize\}/);
assert.match(app.requests['acdc.callbacks.list'].url, /cursor=\{cursor\}/);
assert.strictEqual(app.requests['acdc.callbacks.cancel'].verb, 'DELETE');
assert.strictEqual(app.defaultQueue().callback.use_local_resources, false,
	'local resource hunting must be an explicit queue opt-in');

function queueForm(values, checked, data = {}) {
	return {
		data: function(key) { return data[key]; },
		find: function(selector) {
			const match = selector.match(/^\[name="([^"]+)"\]$/);
			assert(match, 'unexpected form selector: ' + selector);
			return {
				val: function() { return values[match[1]] || ''; },
				is: function(query) {
					assert.strictEqual(query, ':checked');
					return Boolean(checked[match[1]]);
				}
			};
		}
	};
}

const formValues = {
	name: ' Support ',
	strategy: 'round_robin',
	agent_ring_timeout: '15',
	agent_wrapup_time: '5',
	connection_timeout: '3600',
	max_queue_size: '12',
	ring_simultaneously: '2',
	caller_exit_key: '#',
	moh: 'local_stream://default',
	announce: 'prompt://queue-you-are-next',
	'announcements.interval': '45',
	'announcements.initial_delay': '30',
	'announcements.language': 'fr-ca',
	'announcements.media.you_are_at_position': 'queue-you_are-at-position-fr',
	'announcements.media.in_the_queue': 'queue-in-the-queue-fr',
	'announcements.media.the_estimated_wait_time_is': 'queue-wait-time-fr',
	'announcements.media.increase_in_call_volume': 'queue-volume-fr',
	'callback.entry_key': '6',
	'callback.max_attempts': '3',
	'callback.retry_delay': '60',
	'callback.ttl': '3600',
	'callback.originate_timeout': '60',
	'callback.ready_ack_timeout': '5',
	'callback.confirmation_timeout': '10',
	'callback.handoff_timeout': '5',
	'callback.menu_timeout_ms': '30000',
	'callback.success_timeout_ms': '10000',
	'callback.outbound_authority.id': 'device-id',
	'callback.outbound_authority.type': 'device',
	'callback.outbound_caller_id.number': '+12025550123',
	'callback.outbound_caller_id.name': 'Support callback',
	'callback.media.offer': 'callback-offer-fr',
	'callback.media.menu': 'callback-menu-fr',
	'callback.media.number_readback': 'callback-number-fr',
	'callback.media.confirmation': 'callback-confirm-fr',
	'callback.media.success': 'callback-success-fr',
	'callback.media.returned_confirmation': 'callback-returned-fr'
};
const formChecks = {
	enter_when_empty: true,
	record_caller: false,
	'announcements.position_announcements_enabled': true,
	'announcements.wait_time_announcements_enabled': true,
	'callback.enabled': true,
	'callback.allow_alternate_number': false,
	'callback.use_local_resources': true
};
assert.deepStrictEqual(
	JSON.parse(JSON.stringify(app.serializeQueue(queueForm(formValues, formChecks), true))),
	{
		name: 'Support',
		strategy: 'round_robin',
		agent_ring_timeout: 15,
		agent_wrapup_time: 5,
		connection_timeout: 3600,
		max_queue_size: 12,
		ring_simultaneously: 2,
		caller_exit_key: '#',
		enter_when_empty: true,
		record_caller: false,
		moh: 'local_stream://default',
		announce: 'prompt://queue-you-are-next',
		announcements: {
			interval: 45,
			initial_delay: 30,
			language: 'fr-ca',
			position_announcements_enabled: true,
			wait_time_announcements_enabled: true,
			media: {
				you_are_at_position: 'queue-you_are-at-position-fr',
				in_the_queue: 'queue-in-the-queue-fr',
				the_estimated_wait_time_is: 'queue-wait-time-fr',
				increase_in_call_volume: 'queue-volume-fr'
			}
		},
		callback: {
			enabled: true,
			entry_key: '6',
			allow_alternate_number: false,
			use_local_resources: true,
			max_attempts: 3,
			retry_delay: 60,
			ttl: 3600,
			originate_timeout: 60,
			ready_ack_timeout: 5,
			confirmation_timeout: 10,
			handoff_timeout: 5,
			menu_timeout_ms: 30000,
			success_timeout_ms: 10000,
			return_confirmation_prompt: null,
			outbound_authority: { id: 'device-id', type: 'device' },
			outbound_caller_id: { number: '+12025550123', name: 'Support callback' },
			media: {
				offer: 'callback-offer-fr',
				menu: 'callback-menu-fr',
				number_readback: 'callback-number-fr',
				confirmation: 'callback-confirm-fr',
				success: 'callback-success-fr',
				returned_confirmation: 'callback-returned-fr'
			}
		}
	}
);
const clearedEdit = app.serializeQueue(queueForm(Object.assign({}, formValues, {
	moh: '',
	announce: '',
	'announcements.language': ''
}), formChecks), true);
assert.strictEqual(clearedEdit.moh, null, 'PATCH must remove cleared hold media');
assert.strictEqual(clearedEdit.announce, null, 'PATCH must remove a cleared pre-connect announcement');
assert.strictEqual(clearedEdit.announcements.language, null, 'PATCH must remove a cleared language override');
assert.strictEqual(clearedEdit.callback.return_confirmation_prompt, null,
	'PATCH must remove the obsolete returned-confirmation field');
const blankCreate = app.serializeQueue(queueForm(Object.assign({}, formValues, {
	moh: '',
	announce: '',
	'announcements.language': ''
}), formChecks), false);
assert.strictEqual(Object.hasOwn(blankCreate, 'moh'), false);
assert.strictEqual(Object.hasOwn(blankCreate, 'announce'), false);
assert.strictEqual(Object.hasOwn(blankCreate.announcements, 'language'), false);
const inheritedValues = Object.assign({}, formValues, {
	'callback.outbound_authority.id': 'named-user-id',
	'callback.outbound_authority.type': 'user',
	'callback.caller_id_source': 'inherit'
});
const inheritedCreate = app.serializeQueue(queueForm(inheritedValues, formChecks), false);
assert.strictEqual(inheritedCreate.callback.caller_id_source, 'inherit');
assert.strictEqual(inheritedCreate.callback.outbound_authority.type, 'user');
assert.strictEqual(inheritedCreate.callback.outbound_authority.id, 'named-user-id');
assert.strictEqual(Object.hasOwn(inheritedCreate.callback, 'outbound_caller_id'), false,
	'Inherited identity must not serialize stale UI number/name copies');
assert.strictEqual(app.serializeQueue(queueForm(inheritedValues, formChecks), true).callback.outbound_caller_id, null,
	'Switching to inheritance must clear a former explicit override on PATCH');
const customValues = Object.assign({}, inheritedValues, {
	'callback.caller_id_source': 'custom', 'callback.outbound_caller_id.name': ''
});
const customCreate = app.serializeQueue(queueForm(customValues, formChecks), false).callback;
assert.strictEqual(customCreate.caller_id_source, 'custom');
assert.strictEqual(customCreate.outbound_caller_id.number, '+12025550123');
assert.strictEqual(Object.hasOwn(customCreate.outbound_caller_id, 'name'), false,
	'Custom number selection must leave the caller name to fresh server resolution');
assert.strictEqual(app.serializeQueue(queueForm(customValues, formChecks), true).callback.outbound_caller_id.name, null);
const legacyCallback = app.serializeQueue(queueForm(formValues, formChecks), true).callback;
assert.strictEqual(Object.hasOwn(legacyCallback, 'caller_id_source'), false,
	'Legacy caller-ID behavior must remain absent until a deliberate selection');
assert.strictEqual(legacyCallback.outbound_authority.type, 'device');
assert.strictEqual(legacyCallback.outbound_caller_id.name, 'Support callback');
const ordered = app.orderedAgentIds(['agent-c', 'agent-a', 'agent-b', 'agent-c'], ['agent-b', 'former-agent']);
assert.deepStrictEqual(Array.from(ordered), ['agent-b', 'agent-a', 'agent-c'],
	'Explicit priority precedes every unlisted member in stable ID order');
const orderedValues = Object.assign({}, formValues, {strategy: 'in_order'});
assert.deepStrictEqual(app.serializeQueue(queueForm(orderedValues, formChecks, {
	'agent-order': ['agent-b', 'agent-a', 'agent-c']
}), true).agent_order, ['agent-b', 'agent-a', 'agent-c']);
assert.strictEqual(Object.hasOwn(app.serializeQueue(queueForm(orderedValues, formChecks, {
	'agent-order-read-only': true, 'agent-order': ['unknown-current-agent']
}), true), 'agent_order'), false, 'Incomplete priority inventory must never overwrite saved order');
const missingMedia = app.selectionOptions([{value: 'known', label: 'Known recording'}],
	'https://legacy.invalid/owned-recording.wav', 'Default', 'Keep current');
assert.strictEqual(missingMedia.filter(item => item.selected).length, 1);
assert.strictEqual(missingMedia.find(item => item.selected).value, 'https://legacy.invalid/owned-recording.wav');
assert.strictEqual(missingMedia.find(item => item.selected).preserved, true,
	'An unavailable legacy URI must be selected and preserved, never silently cleared');
const knownUser = app.selectionOptions([{value: 'user-1', label: 'Alice Agent'}], 'user-1', 'Choose', 'Keep current');
assert.strictEqual(knownUser.find(item => item.selected).label, 'Alice Agent');
assert.deepStrictEqual(
	JSON.parse(JSON.stringify(app.normalizeQueueCallback({
		callback: { return_confirmation_prompt: 'legacy-returned' }
	}))),
	{ callback: {
		return_confirmation_prompt: 'legacy-returned',
		media: { returned_confirmation: 'legacy-returned' }
	} }
);
assert.strictEqual(
	app.normalizeQueueCallback({
		callback: {
			return_confirmation_prompt: 'legacy-returned',
			media: { returned_confirmation: 'canonical-returned' }
		}
	}).callback.media.returned_confirmation,
	'canonical-returned',
	'canonical returned-confirmation media must win over the legacy field'
);

let callbacks = 0;
app.requestMany({}, function(errors, results) {
	callbacks++;
	assert.deepStrictEqual(Object.keys(errors), []);
	assert.deepStrictEqual(Object.keys(results), []);
});
assert.strictEqual(callbacks, 1, 'empty requestMany callback must run exactly once');

const originalRequest = app.request;
app.request = function(resource, data, callback) {
	callback(resource === 'failure' ? 'failed' : null, data);
};
callbacks = 0;
app.requestMany({
	first: { resource: 'success', data: { id: 1 } },
	second: { resource: 'failure', data: { id: 2 } }
}, function(errors, results) {
	callbacks++;
	assert.strictEqual(errors.second, 'failed');
	assert.strictEqual(results.first.id, 1);
});
assert.strictEqual(callbacks, 1, 'requestMany callback must run once after all requests');
app.request = originalRequest;

// POST roster is a full replacement: partial reads or hidden current members
// must disable this write, and a complete multi-agent selection must stay whole.
const inventoryOriginals = Object.fromEntries(['requestEnvelope', 'request', 'isCurrentView',
	'setFormBusy', 'rememberSavedQueueId', 'finishQueueSave'].map(key => [key, app[key]]));
const inventoryI18n = app.i18n.active;
app.i18n.active = () => ({acdc: {queues: {incompleteInventory: 'incomplete inventory'}}});
const thirtyIds = Array.from({length: 30}, (_, index) => index.toString(16).padStart(32, '0'));
const thirtyUsers = thirtyIds.map(id => ({id}));
assert.strictEqual(app.rosterInventoryState(thirtyUsers, thirtyIds).readOnly, false);
assert.strictEqual(app.rosterInventoryState(thirtyUsers.slice(0, 29), thirtyIds).readOnly, true);
assert.strictEqual(app.rosterInventoryState(thirtyUsers, thirtyIds, 'roster read failed').readOnly, true);
assert.strictEqual(app.rosterInventoryState(thirtyUsers, {}).readOnly, true);
for (const response of [{data: thirtyIds, next_start_key: ['more']},
	{data: thirtyIds, next_cursor: 'more'}, {data: {}}, null]) {
	app.requestEnvelope = (_resource, _data, done) => done(null, response);
	app.requestCompleteList('acdc.queues.roster', {}, (error, ids) => {
		assert.strictEqual(error, 'incomplete inventory');
		assert.strictEqual(ids, undefined, 'Partial roster must not be returned as a writable list');
	});
}
app.requestEnvelope = (_resource, _data, done) => done(null, {status: 'success', data: thirtyIds});
app.requestCompleteList('acdc.queues.roster', {}, (error, ids) => {
	assert.strictEqual(error, null);
	assert.deepStrictEqual(ids, thirtyIds);
});
const rosterWrites = [];
app.isCurrentView = () => true;
app.setFormBusy = () => {};
app.rememberSavedQueueId = () => 'q1';
app.finishQueueSave = () => {};
app.request = (resource, data, done) => {
	if (resource === 'acdc.queues.updateRoster') rosterWrites.push(data.data);
	done(null, {id: 'q1'});
};
app.saveQueue('q1', {name: 'Support'}, thirtyIds, null, {}, 1, 'account');
assert.deepStrictEqual(rosterWrites, [thirtyIds], 'All 30 selected members must be sent in one replacement');
app.saveQueue('q1', {name: 'Support'}, null, null, {}, 1, 'account');
assert.strictEqual(rosterWrites.length, 1, 'An incomplete/read-only roster must never be written');
Object.assign(app, inventoryOriginals);
app.i18n.active = inventoryI18n;

const catalogOriginals = {requestEnvelope: app.requestEnvelope, requestCompleteList: app.requestCompleteList,
	i18nActive: app.i18n.active};
app.i18n.active = () => ({acdc: {dropdowns: {incomplete: 'incomplete catalog'}}});
for (const response of [null, {data: {numbers: []}}, {status: 'error', data: {numbers: {}}},
	{data: {numbers: {}}, next_cursor: 'more'}, {data: {numbers: {}}, next_start_key: ['more']},
	{data: {numbers: {}}, next_cursor: 0}, {data: {numbers: {}}, next_start_key: 0}]) {
	app.requestEnvelope = (_resource, _data, done) => done(null, response);
	app.requestOwnedNumbers('acdc.numbers.list', {}, (error, numbers) => {
		assert.strictEqual(error, 'incomplete catalog');
		assert.strictEqual(numbers, undefined);
	});
}
app.requestEnvelope = (_resource, _data, done) => done(null, {status: 'success', data: {
	numbers: {'+12025550123': {state: 'in_service'}}
}});
app.requestOwnedNumbers('acdc.numbers.list', {}, (error, numbers) => {
	assert.strictEqual(error, null);
	assert.strictEqual(numbers[0].number, '+12025550123');
	assert.strictEqual(numbers[0].state, 'in_service');
});
const mediaInventory = [
	{id: 'en-us/ready', language: 'en-us', is_prompt: true},
	{id: 'fr-fr/ready', language: 'fr-fr', is_prompt: true},
	{id: 'en-us/empty', language: 'en-us', is_prompt: true},
	{id: 'en-us/not-prompt', language: 'en-us', is_prompt: false}
];
app.appFlags.acdc.verifiedSystemMedia = undefined;
app.requestCompleteList = (_resource, data, done) => done(null, data.promptId === 'ready'
	? [{id: 'en-us/ready', has_attachments: true}, {id: 'fr-fr/ready', has_attachments: false}]
	: [{id: 'en-us/empty', has_attachments: false}]);
app.verifySystemMedia(mediaInventory, (error, media) => {
	assert.strictEqual(error, null);
	assert.deepStrictEqual(media.map(item => item.id), ['en-us/ready'],
		'Only actual attachment-backed prompts may become installed dropdown choices');
});
app.appFlags.acdc.verifiedSystemMedia = undefined;
app.requestCompleteList = (_resource, _data, done) => done('partial inventory');
app.verifySystemMedia(mediaInventory, (error, media) => {
	assert.strictEqual(error, 'partial inventory');
	assert.strictEqual(media, undefined, 'A partial prompt verification must fail closed');
});
app.requestEnvelope = catalogOriginals.requestEnvelope;
app.requestCompleteList = catalogOriginals.requestCompleteList;
app.i18n.active = catalogOriginals.i18nActive;

assert.deepStrictEqual(
	JSON.parse(JSON.stringify(app.normalizeStatuses({
		a1: 'login',
		a2: { status: 'pause' },
		a3: {
			old: { timestamp: 100, status: 'logout' },
			'new': { timestamp: 200, status: 'resume' }
		}
	}))),
	{ a1: 'login', a2: 'pause', a3: 'resume' }
);
assert.strictEqual(app.statusClass('logged_out'), 'offline');
assert.strictEqual(app.statusClass('pause'), 'paused');
assert.strictEqual(app.statusClass('ready'), 'online');

assert.deepStrictEqual(
	JSON.parse(JSON.stringify(app.formatAgents([
		{ id: 'a1', first_name: 'Ada', last_name: 'Agent', queues: ['q1', 'q2'] }
	], [
		{ id: 'q1', name: 'Support' },
		{ id: 'q2', name: 'Sales' }
	], {
		a1: {
			'63955776932': { agent_id: 'a1', id: 'event-1', status: 'logged_out', timestamp: 63955776932 },
			'63955777129': { agent_id: 'a1', id: 'event-2', status: 'ready', timestamp: 63955777129 }
		}
	}, {
		a1: { answered_calls: 3, missed_calls: 1, total_calls: 4 }
	}))),
	[{
		id: 'a1',
		name: 'Ada Agent',
		status: 'ready',
		statusClass: 'online',
		queues: 'Support, Sales',
		answered: 3,
		missed: 1,
		total: 4
	}]
);

assert.deepStrictEqual(
	JSON.parse(JSON.stringify(app.buildQueueStats([
		{ id: 'q1', name: 'Support' }
	], [
		{ queue_id: 'q1', status: 'waiting' },
		{ queue_id: 'q1', status: 'handled' },
		{ queue_id: 'q1', status: 'processed' },
		{ queue_id: 'q1', status: 'abandoned' }
	]))),
	[{ id: 'q1', name: 'Support', waiting: 1, handling: 1, abandoned: 1, processed: 1 }]
);

const managedRoute = JSON.parse(JSON.stringify(app.buildManagedRoute('q1', 'Support', '2001')));
managedRoute.id = 'cf-owned';
assert.strictEqual(app.isStrictManagedRoute(managedRoute, 'q1'), true);
assert.deepStrictEqual(
	JSON.parse(JSON.stringify(managedRoute.flags)),
	['talkchief-acdc-managed', 'talkchief-acdc-queue:q1']
);
const routeWithoutQueueMarker = JSON.parse(JSON.stringify(managedRoute));
routeWithoutQueueMarker.flags = ['talkchief-acdc-managed'];
assert.strictEqual(app.isStrictManagedRoute(routeWithoutQueueMarker, 'q1'), false);
const normalizedManagedRoute = JSON.parse(JSON.stringify(managedRoute));
normalizedManagedRoute.numbers = ['+12025550123'];
assert.strictEqual(app.isStrictManagedRoute(normalizedManagedRoute, 'q1'), true);
const routeWithUnexpectedChild = JSON.parse(JSON.stringify(managedRoute));
routeWithUnexpectedChild.flow.children._ = {
	module: 'play',
	data: {},
	children: {}
};
assert.strictEqual(app.isStrictManagedRoute(routeWithUnexpectedChild, 'q1'), false);
const routeWithMultipleExtensions = JSON.parse(JSON.stringify(managedRoute));
routeWithMultipleExtensions.numbers.push('2002');
assert.strictEqual(app.isStrictManagedRoute(routeWithMultipleExtensions, 'q1'), false);
const externalRoute = {
	id: 'cf-external',
	numbers: ['2000'],
	flow: {
		module: 'menu',
		data: {},
		children: {
			'1': {
				module: 'acdc_member',
				data: { id: 'q1' },
				children: {}
			}
		}
	}
};
assert.strictEqual(app.isAcdcQueueReference(externalRoute.flow, 'q1'), true);
assert.strictEqual(app.isStrictManagedRoute(externalRoute, 'q1'), false);
assert.strictEqual(app.isAcdcQueueReference(externalRoute.flow, 'other-queue'), false);
assert.strictEqual(app.findExtensionCollision([
	{ id: 'cf-owned', numbers: ['2001'] },
	{ id: 'cf-external', numbers: ['2000'] }
], '2001', 'cf-owned'), undefined);
assert.strictEqual(app.findExtensionCollision([
	{ id: 'cf-owned', numbers: ['2001'] },
	{ id: 'cf-external', numbers: ['2000'] }
], '2000', 'cf-owned').id, 'cf-external');

const originalLoadInventory = app.loadAcdcCallflowInventory;
const originalIsCurrentView = app.isCurrentView;
const originalToastError = app.toastError;
const originalI18nActive = app.i18n.active;
const originalUiRequest = app.request;
let blockedDeleteMessage;
let mutationRequests = 0;
app.i18n.active = function() {
	return {
		acdc: {
			callbacks: {
				keyConflict: 'callback key conflict',
				reconciliationGeneric: 'Call state is being verified; no new attempt will be placed.',
				reconciliationReasons: {
					engine_restart: 'Engine restart recovery'
				},
				statuses: {
					queued: 'Queued',
					connecting: 'Connecting',
					reconciliation_required: 'Recovery pending'
				}
			},
			queues: {
				externalRouteDeleteBlocked: 'external route blocks deletion',
				multipleManagedRoutes: 'multiple routes',
				routeUnavailable: 'route unavailable',
				routeCollision: 'extension collision',
				routeOwnershipChanged: 'ownership changed'
			}
		}
	};
};
assert.strictEqual(
	app.callbackKeyError(queueForm(
		Object.assign({}, formValues, { caller_exit_key: '6' }),
		Object.assign({}, formChecks, { 'callback.enabled': true })
	)),
	'callback key conflict'
);
assert.strictEqual(
	app.callbackKeyError(queueForm(
		Object.assign({}, formValues, { caller_exit_key: '#', 'callback.entry_key': '6' }),
		Object.assign({}, formChecks, { 'callback.enabled': true })
	)),
	null
);
const formattedCallback = app.formatCallback({
	id: 'callback-id', status: 'queued', attempts: 0,
	enqueued_at: 62167219201, expires_at: 62167219202
});
assert.strictEqual(formattedCallback.status_label, 'Queued');
assert.strictEqual(formattedCallback.cancellable, true);
assert.notStrictEqual(formattedCallback.enqueued_label, '-');
assert.notStrictEqual(formattedCallback.expires_label, '-');
const reconcilingCallback = app.formatCallback({
	id: 'callback-recovery', status: 'connecting', attempts: 1,
	reconciliation_required: true, reconciliation_reason: 'engine_restart'
});
assert.strictEqual(reconcilingCallback.status_label, 'Recovery pending');
assert.strictEqual(reconcilingCallback.status_class, 'reconciling');
assert.strictEqual(reconcilingCallback.underlying_status_label, 'Connecting');
assert.strictEqual(reconcilingCallback.reconciliation_detail, 'Engine restart recovery');
assert.strictEqual(reconcilingCallback.cancellable, true,
	'uncertain active callbacks retain safe cancel but never gain a retry action');
const unknownReconciliation = app.formatCallback({
	status: 'dialing', reconciliation_required: true,
	reconciliation_reason: 'unrecognized_server_detail'
});
assert.strictEqual(unknownReconciliation.reconciliation_detail,
	'Call state is being verified; no new attempt will be placed.');
assert.notStrictEqual(unknownReconciliation.reconciliation_detail,
	unknownReconciliation.reconciliation_reason,
	'unknown server reason must not be rendered as raw operator text');
app.loadAcdcCallflowInventory = function(callback) {
	callback(null, { summaries: [], routes: [externalRoute] });
};
app.isCurrentView = function() {
	return true;
};
app.toastError = function(message) {
	blockedDeleteMessage = message;
};
app.request = function() {
	mutationRequests++;
};
app.deleteQueueSafely('q1', 1, 'account');
assert.strictEqual(blockedDeleteMessage, 'external route blocks deletion');
assert.strictEqual(mutationRequests, 0, 'external ACDC references must block every delete mutation');

const collisionView = {
	data: function(key) {
		if (key === 'callflow-summaries') {
			return [{ id: 'external', numbers: ['2000'] }];
		}
		return null;
	}
};
let collisionError;
app.syncManagedRoute('q1', 'Support', '2000', collisionView, function(error) {
	collisionError = error;
});
assert.strictEqual(collisionError, 'extension collision');
assert.strictEqual(mutationRequests, 0, 'extension collision must be rejected before mutation');
app.loadAcdcCallflowInventory = originalLoadInventory;
app.isCurrentView = originalIsCurrentView;
app.toastError = originalToastError;
app.i18n.active = originalI18nActive;
app.request = originalUiRequest;

const viewData = {};
const retryView = {
	data: function(key, value) {
		if (arguments.length === 2) {
			viewData[key] = value;
			return this;
		}
		return viewData[key];
	}
};
const savedQueueId = app.rememberSavedQueueId(retryView, null, { id: 'q-created' });
assert.strictEqual(savedQueueId, 'q-created');
assert.strictEqual(retryView.data('queue-id'), 'q-created');
assert.strictEqual(app.queueWriteResource(retryView.data('queue-id')), 'acdc.queues.update');

const metadata = JSON.parse(fs.readFileSync(path.join(appRoot, 'metadata', 'app.json'), 'utf8'));
assert.strictEqual(metadata.name, 'acdc');
assert.strictEqual(metadata.allowed_users, 'admins');
assert.strictEqual(metadata.masqueradable, true);
assert.strictEqual(metadata.author, 'Talkchief');

const templates = fs.readdirSync(path.join(appRoot, 'views'))
	.map(function(file) {
		return fs.readFileSync(path.join(appRoot, 'views', file), 'utf8');
	})
	.join('\n');
[
	'acdc-tab',
	'acdc-add-queue',
	'acdc-view-callbacks',
	'acdc-callback-inventory',
	'acdc-callback-cancel',
	'acdc-queue-form',
	'acdc-roster',
	'acdc-position-announcements',
	'acdc-wait-announcements',
	'acdc-announcement-interval',
	'acdc-announcement-initial-delay',
	'acdc-announcement-language',
	'acdc-preconnect-announcement',
	'acdc-callback-enabled',
	'acdc-callback-local-resources',
	'acdc-agent-action',
	'acdc-summary-grid',
	'acdc-retry'
].forEach(function(selector) {
	assert(templates.includes(selector), 'missing acceptance selector: ' + selector);
});
const callbacksTemplate = fs.readFileSync(path.join(appRoot, 'views', 'callbacks.html'), 'utf8');
const queueTemplate = fs.readFileSync(path.join(appRoot, 'views', 'queue-form.html'), 'utf8');
for (const name of ['callback.outbound_authority.id', 'callback.outbound_caller_id.number',
	'callback.caller_id_source', 'announcements.language', 'moh', 'announce', 'callback.media.offer']) {
	assert(new RegExp('<select[^>]*name="' + name.replaceAll('.', '\\.') + '"').test(queueTemplate),
		name + ' must be a real select control, not a technical free-text input');
}
assert.match(queueTemplate, /type="hidden" name="callback.outbound_authority.type"/);
assert.match(queueTemplate, /type="hidden" name="callback.outbound_caller_id.name"/);
assert(callbacksTemplate.includes('acdc-reconciliation-detail'),
	'recovery-pending detail must be visible in the callback inventory');
assert(callbacksTemplate.includes('acdc-reconciliation-state'),
	'recovery-pending rows must preserve the durable callback status');
assert(!callbacksTemplate.includes('retryCallback') && !callbacksTemplate.includes('force-redial'),
	'uncertain callbacks must never expose a redial or retry action');

const queuesApi = fs.readFileSync(path.join(projectRoot, 'applications', 'acdc', 'src', 'cb_queues.erl'), 'utf8');
const agentsApi = fs.readFileSync(path.join(projectRoot, 'applications', 'acdc', 'src', 'cb_agents.erl'), 'utf8');
const callStatsApi = fs.readFileSync(path.join(projectRoot, 'applications', 'acdc', 'src', 'cb_acdc_call_stats.erl'), 'utf8');
const callflowsApi = fs.readFileSync(path.join(projectRoot, 'applications', 'crossbar', 'src', 'modules', 'cb_callflows.erl'), 'utf8');
const queuesSchema = JSON.parse(fs.readFileSync(path.join(projectRoot, 'applications', 'crossbar', 'priv', 'couchdb', 'schemas', 'queues.json'), 'utf8'));
const announcementsRuntime = fs.readFileSync(path.join(projectRoot, 'applications', 'acdc', 'src', 'acdc_announcements.erl'), 'utf8');
assert(queuesApi.includes('validate_queue(Context, Id, ?HTTP_PATCH)'));
assert(queuesApi.includes('validate_queue_operation(Context, Id, ?ROSTER_PATH_TOKEN, ?HTTP_POST)'));
assert(agentsApi.includes('<<"login">>, <<"logout">>, <<"pause">>, <<"resume">>'));
assert(callStatsApi.includes('crossbar_view:load_modb'));
assert(callflowsApi.includes('validate_callflow(Context, DocId, ?HTTP_PATCH)'));
const announcementSchema = queuesSchema.properties.announcements.properties;
const callbackSchema = queuesSchema.properties.callback.properties;
assert.strictEqual(queuesSchema.properties.announce.type, 'string');
assert.strictEqual(announcementSchema.interval.minimum, 15);
assert.strictEqual(announcementSchema.initial_delay.type, 'integer');
assert.strictEqual(announcementSchema.initial_delay.default, 30);
assert.strictEqual(announcementSchema.initial_delay.minimum, 1);
assert.strictEqual(announcementSchema.initial_delay.maximum, 3600);
assert.strictEqual(announcementSchema.position_announcements_enabled.type, 'boolean');
assert.strictEqual(announcementSchema.wait_time_announcements_enabled.type, 'boolean');
assert.strictEqual(announcementSchema.language.pattern, '^[a-z]{2,3}(-[a-z0-9]{2,8})*$');
assert.deepStrictEqual(
	announcementSchema.media.required.slice().sort(),
	['in_the_queue', 'increase_in_call_volume', 'the_estimated_wait_time_is', 'you_are_at_position'].sort()
);
assert.strictEqual(callbackSchema.enabled.default, false);
assert.strictEqual(callbackSchema.max_attempts.minimum, 1);
assert.strictEqual(callbackSchema.max_attempts.maximum, 10);
assert.strictEqual(callbackSchema.retry_delay.minimum, 15);
assert.strictEqual(callbackSchema.retry_delay.maximum, 3600);
assert.strictEqual(callbackSchema.ttl.minimum, 60);
assert.strictEqual(callbackSchema.ttl.maximum, 86400);
assert.strictEqual(callbackSchema.entry_key.default, '6');
assert.strictEqual(callbackSchema.allow_alternate_number.default, false);
assert.strictEqual(callbackSchema.use_local_resources.type, 'boolean');
assert.strictEqual(callbackSchema.use_local_resources.default, false);
assert.strictEqual(callbackSchema.menu_timeout_ms.maximum, 120000);
assert.strictEqual(callbackSchema.success_timeout_ms.maximum, 30000);
assert.strictEqual(callbackSchema.originate_timeout.minimum, 5);
assert.strictEqual(callbackSchema.originate_timeout.maximum, 300);
assert.strictEqual(callbackSchema.media.properties.returned_confirmation.type, 'string');
assert(announcementsRuntime.includes('{\'queue_position\', kapps_call:call_id(Call)}'));
assert(announcementsRuntime.includes('{\'say\', kz_term:to_binary(Position), <<"number">>}'));

console.log('PASS ACDC Monster UI contract checks');
