#!/usr/bin/env node
'use strict';
// Pure schema/source fixtures; no sockets, credentials, generated assets or services.
const assert = require('node:assert/strict');
const path = require('node:path');
const Ajv = require('./api-docs-tooling/node_modules/ajv');
const {queueLiveBlackholeContract, applyBlackhole} = require('./api-docs-blackhole.cjs');
const {validateEvent} = require('./test-queue-live-wire.cjs');
const contract = queueLiveBlackholeContract(), schemas = contract.schemas;
const ajv = new Ajv({strict: false, validateFormats: false});
const compile = name => ajv.compile({components: {schemas}, $ref: '#/components/schemas/' + name});
const a = 'a'.repeat(32), q = 'b'.repeat(32), b = 'queue_live.changed.' + q;
let checks = 0;
function accept(test, value) { checks++; assert(test(value), 'Expected valid synthetic profile'); }
function reject(test, value) { checks++; assert.equal(test(value), false, 'Invalid synthetic profile accepted'); }
for (const action of ['subscribe', 'unsubscribe']) {
    const test = compile(action === 'subscribe' ? 'BlackholeQueueLiveSubscribe' : 'BlackholeQueueLiveUnsubscribe');
    const base = {action, auth_token: 'synthetic-only', request_id: 'synthetic-request', data: {account_id: a, binding: b}};
    accept(test, base); accept(test, {...base, data: {account_id: a, bindings: [b]}});
    for (const data of [{binding: b}, {account_id: a}, {account_id: a, binding: 'queue_live.changed.*'},
        {account_id: a, binding: 'call.CHANNEL_ANSWER.' + q}, {account_id: a.toUpperCase(), binding: b},
        {account_id: a, bindings: []}, {account_id: a, bindings: [b, b]},
        {account_id: a, binding: b, bindings: [b]}, {account_id: a, binding: b, queue_id: q}]) reject(test, {...base, data});
    for (const key of ['action', 'auth_token', 'request_id', 'data']) {
        const missing = {...base}; delete missing[key]; reject(test, missing);
    }
    reject(test, {...base, auth_token: ''}); reject(test, {...base, auth_token: 'x'.repeat(16385)});
    reject(test, {...base, request_id: 'x'.repeat(129)}); reject(test, {...base, token: 'synthetic-only'});
}
const route = 'acdc.dashboard.changed.' + a + '.' + q;
const event = {action: 'event', name: 'changed', subscribed_key: b, subscription_key: route, routing_key: route,
    data: {version: 1, account_id: a, queue_id: q}};
const test = compile('BlackholeQueueLiveEvent'); accept(test, event);
for (const key of Object.keys(event)) { const missing = {...event}; delete missing[key]; reject(test, missing); }
for (const data of [{...event.data, version: 2}, {...event.data, queue_id: '*'}, {...event.data, caller_id: 'synthetic'},
    {...event.data, current_waiting: 1}, {...event.data, agent_id: q}, {...event.data, sequence: 1}]) reject(test, {...event, data});
reject(test, {...event, auth_token: 'synthetic-only'});
validateEvent(event, {account: a, queue: q}); checks++;
// Regex structure cannot compare values: the runtime smoke must reject mismatched scopes.
const foreign = {...event, data: {...event.data, queue_id: 'c'.repeat(32)}};
accept(test, foreign); assert.throws(() => validateEvent(foreign, {account: a, queue: q})); checks++;
const spec = {components: {schemas: {}}, paths: {}};
const applied = applyBlackhole({spec, root: path.resolve(__dirname, '..')});
assert(applied.inputs.some(x => x.file.endsWith('/bh_queue_live.erl')));
assert(applied.inputs.some(x => x.file.endsWith('/blackhole-command-auth.patch')));
assert(spec['x-blackhole'].command_authentication.token_change.includes('Reconnect'));
assert(spec['x-blackhole'].command_authentication.lifetime_limit.includes('already subscribed'));
assert(applied.inputs.some(x => x.file.endsWith('/blackhole-outbound-guard.patch')));
assert(applied.inputs.some(x => x.file.endsWith('/kazoo-identity-authoritative-read.patch')));
assert(spec['x-blackhole'].command_authentication.lifetime_limit.includes('authoritative datastore'));
assert(spec['x-blackhole'].outbound_delivery.authentication.includes('1008'));
assert(spec['x-blackhole'].outbound_delivery.overload.includes('1013'));
assert(applied.inputs.some(x => x.file.endsWith('/acdc_live_auth.erl')));
assert(applied.inputs.some(x => x.file.endsWith('/kapi_acdc_dashboard_events.erl')));
assert.equal(spec['x-blackhole'].queue_live.reconciliation_seconds, 15);
assert(spec['x-blackhole'].queue_live.admission.includes('matching success request_id'));
assert(spec['x-blackhole'].queue_live.admission.includes('not a broker-ready barrier'));
assert(spec['x-blackhole'].queue_live.authorization.includes('not merely account hierarchy'));
assert(spec['x-blackhole'].queue_live.delivery.includes('on reconnect'));
assert.equal(spec['x-blackhole'].queue_live.implementation_status, 'implemented-in-source; deployment-specific acceptance required');
console.log(JSON.stringify({result: 'PASS', schema_checks: checks, source_guards: 'actual native module', scope: 'offline only'}));
