'use strict';
const assert = require('node:assert/strict');
const {inspect} = require('./callback-retry-service-scope.cjs');
const units = ['kazoo-apps', 'kazoo-ecallmgr', 'kazoo-freeswitch', 'kazoo-kamailio', 'kazoo-live-test-agents'];
const baseline = units.map((name, i) => ({Id: name + '.service', LoadState: 'loaded',
    ActiveState: 'active', SubState: 'running', MainPID: String(100 + i), NRestarts: '0'}));
const render = states => states.map(state => Object.entries(state).map(([key, value]) => key + '=' + value).join('\n')).join('\n\n') + '\n';
let checks = 0;
assert.equal(inspect(render(baseline)).master_test_phones_paused, false); checks++;
assert.equal(inspect(render(baseline), true).master_test_phones_paused, false); checks++;
const paused = structuredClone(baseline);
Object.assign(paused[4], {ActiveState: 'inactive', SubState: 'dead', MainPID: '0'});
assert.equal(inspect(render(paused), true).master_test_phones_paused, true); checks++;
assert(inspect(render(paused), true).limitation.includes('not MASTER phone availability')); checks++;
assert.throws(() => inspect(render(paused))); checks++;
for (const mutate of [
    x => {x[4].ActiveState = 'failed';}, x => {x[4].ActiveState = 'activating';},
    x => {x[4].ActiveState = 'deactivating';}, x => {x[4].SubState = 'stop-sigterm';},
    x => {x[4].MainPID = '100';}, x => {x[4].LoadState = 'not-found';},
    x => {x[4].NRestarts = '-1';}, x => {x[4].NRestarts = 'NaN';},
    x => {x[4].Id = 'foreign.service';}, x => {delete x[4].SubState;},
    x => {x.pop();}, x => {x.push({...x[0]});}
]) {
    const value = structuredClone(paused); mutate(value);
    assert.throws(() => inspect(render(value), true)); checks++;
}
for (let i = 0; i < 4; i++) {
    const value = structuredClone(paused);
    Object.assign(value[i], {ActiveState: 'inactive', SubState: 'dead', MainPID: '0'});
    assert.throws(() => inspect(render(value), true)); checks++;
    value[i] = {...baseline[i], MainPID: '0'};
    assert.throws(() => inspect(render(value), true)); checks++;
}
assert.throws(() => inspect(render(paused), 'true')); checks++;
assert.throws(() => inspect(render(paused) + 'Id=kazoo-apps.service\n', true)); checks++;
console.log('PASS ' + checks + ' paused MASTER test-phone scope checks; no services contacted or changed');
