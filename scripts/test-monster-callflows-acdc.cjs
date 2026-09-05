#!/usr/bin/env node
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = process.argv[2] || '/usr/local/src/kazoo5-installer/monster-ui/src/apps/callflows';
const labels = JSON.parse(fs.readFileSync(path.join(root, 'i18n/en-US.json'), 'utf8'));
const german = JSON.parse(fs.readFileSync(path.join(root, 'i18n/de-DE.json'), 'utf8'));
assert.deepEqual(Object.keys(labels.callflows.acdc).sort(), Object.keys(german.callflows.acdc).sort());
assert(fs.readFileSync(path.join(root, 'app.js'), 'utf8').includes("'acdc',"));
let app;
const lodash = {isArray: Array.isArray, filter: (items, fn) => items.filter(fn),
    find: (items, fn) => items.find(fn), sortBy: (items, key) => items.slice().sort((a,b) => a[key].localeCompare(b[key])),
    once: fn => { let called = false; return (...args) => { if (!called) { called = true; return fn(...args); } }; }};
const jquery = {extend: Object.assign};
const monster = {};
vm.runInNewContext(fs.readFileSync(path.join(root, 'submodules/acdc/acdc.js'), 'utf8'), {
    define: factory => { app = factory(name => ({jquery, lodash, monster})[name]); }
});
const context = Object.assign({}, app, {accountId: 'a'.repeat(32), i18n: {active: () => labels}});
const actions = {};
context.acdcDefineActions({actions});
const action = actions['acdc_member[id=*]'];
assert(action && action.isListed === true && action.isUsable === 'true');
assert.equal(action.module, 'acdc_member');
assert.equal(action.name, 'ACDC Queue');
assert.equal(context.requests['callflows.acdc.queues.list'].verb, 'GET');
assert.equal(context.requests['callflows.acdc.queues.list'].url, 'accounts/{accountId}/queues?paginate=false');

const selectedId = '1'.repeat(32), otherId = '2'.repeat(32);
const node = {metadata: {id: otherId, untouched: true},
    getMetadata(key) { return this.metadata[key]; }, setMetadata(key, value) { this.metadata[key] = value; }};
assert.equal(context.acdcSelectQueue(node, selectedId, [{id: selectedId, name: 'Master Queue 2000'}]), true);
assert.deepEqual(node.metadata, {id: selectedId, untouched: true});
assert.equal(node.caption, 'Master Queue 2000');
assert.equal(context.acdcSelectQueue(node, otherId, [{id: selectedId, name: 'Master Queue 2000'}]), false);
assert.equal(context.acdcSelectQueue(node, '', []), false);
assert.equal(node.metadata.id, selectedId);
assert.equal(action.caption(node, {[selectedId]: {name: 'Master Queue 2000'}}), 'Master Queue 2000');
assert.equal(action.caption(node, {}), selectedId);

let callbackItems, errors = 0;
context.callApi = () => { throw new Error('Custom four-part request must not use the two-part SDK dispatcher'); };
monster.request = request => {
    assert.equal(request.resource, 'callflows.acdc.queues.list');
    assert.equal(request.data.accountId, context.accountId);
    request.success({data: [{id: otherId, name: 'Zeta'}, {id: selectedId, name: 'Alpha'},
        {id: 'foreign/invalid', name: 'Ignore'}, {id: '3'.repeat(32), name: null}]});
};
context.acdcListQueues(items => { callbackItems = items; }, () => errors++);
assert.deepEqual(Array.from(callbackItems, item => item.name), ['Alpha', 'Zeta']);
assert.equal(errors, 0);
for (const response of [null, {data: {}}, {data: [], next_start_key: 'more'}]) {
    monster.request = request => request.success(response);
    context.acdcListQueues(() => { throw new Error('Invalid/partial queue inventory accepted'); }, () => errors++);
}
assert.equal(errors, 3);
const template = fs.readFileSync(path.join(root, 'submodules/acdc/views/callflowEdit.html'), 'utf8');
assert(template.includes('name="acdc_queue_id"') && template.includes('{{name}}') && !template.includes('{{{name}}}'));
assert(template.includes('{{#if empty}}disabled{{/if}}') && template.includes('data-role="selection-error"'));
console.log('PASS Callflows ACDC action: listed catalog, real acdc_member/data.id mapping, account-scoped queue API, validated selection, existing metadata preservation, partial/error handling, labels and escaped template');
