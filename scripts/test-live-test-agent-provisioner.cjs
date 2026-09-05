#!/usr/bin/env node
'use strict';
const assert = require('node:assert/strict');
const {validateState, collisionCheck, targets, marker, sameMarker, subset, merged, ACCOUNT,
    OWNER, PROTECTED_DEVICE, PROTECTED_USER, runtimeTargetMatches} = require('./provision-live-test-agents.cjs');
function fixture() {
    return {schema_version: 1, owner: OWNER, deployment_id: 'a'.repeat(32), account_id: ACCOUNT,
        realm: 'master.example.invalid', api_base: 'http://127.0.0.1:8000/v2',
        credentials_file: '/etc/kazoo/installer-secrets.env', protected_microsip_device_id: PROTECTED_DEVICE,
        queue_id: '', queue_callflow_id: '', queue_extension: '2000', sip_proxy_host: '192.0.2.1',
        sip_proxy_port: 5060, sip_transport: 'udp', agents: Array.from({length: 30}, (_, index) => ({
            index: index + 1, name: `LiveTestAgent${String(index + 1).padStart(2, '0')}`,
            extension: String(1002 + index), sip_username: `livetest${1002 + index}`,
            sip_password: 'b'.repeat(32), user_id: '', device_id: '', callflow_id: ''}))};
}
function inventory() { return {users: [], devices: [], queues: [], callflows: []}; }
let passed = 0;
function test(name, fn) { fn(); passed++; console.log(`PASS ${name}`); }
test('exact pinned 30-agent state and 92 resource targets', () => {
    const state = validateState(fixture()); assert.equal(targets(state).length, 92);
    collisionCheck(state, inventory());
});
test('wrong account rejected before API mutation', () => {
    const state = fixture(); state.account_id = 'c'.repeat(32); assert.throws(() => validateState(state));
});
test('protected MicroSIP identities cannot be adopted', () => {
    const state = fixture(); state.agents[0].device_id = PROTECTED_DEVICE;
    assert.throws(() => validateState(state)); state.agents[0].device_id = '';
    state.agents[0].user_id = PROTECTED_USER; assert.throws(() => validateState(state));
});
test('unrelated SIP username collision fails', () => {
    const docs = inventory(); docs.devices.push({id: 'c'.repeat(32), sip: {username: 'livetest1002'}});
    assert.throws(() => collisionCheck(fixture(), docs));
});
test('existing extension or pattern route fails without adoption', () => {
    const docs = inventory(); docs.callflows.push({id: 'c'.repeat(32), numbers: ['2000']});
    assert.throws(() => collisionCheck(fixture(), docs)); docs.callflows[0] = {patterns: ['.*']};
    assert.throws(() => collisionCheck(fixture(), docs));
});
test('unknown same-name resource cannot be overwritten', () => {
    const docs = inventory(); docs.users.push({id: 'c'.repeat(32), first_name: 'LiveTestAgent01'});
    assert.throws(() => collisionCheck(fixture(), docs));
});
test('lost create response is safely recovered using exact durable marker', () => {
    const state = fixture(); const docs = inventory();
    docs.users.push({id: 'c'.repeat(32), first_name: 'LiveTestAgent01', kz5_live_test: marker(state, 'user', 1)});
    collisionCheck(state, docs); assert.equal(state.agents[0].user_id, 'c'.repeat(32));
});
test('other deployment marker cannot be adopted', () => {
    const state = fixture(); const docs = inventory();
    docs.users.push({id: 'c'.repeat(32), first_name: 'LiveTestAgent01',
        kz5_live_test: {...marker(state, 'user', 1), deployment_id: 'd'.repeat(32)}});
    assert.throws(() => collisionCheck(state, docs));
});
test('duplicates and saved ID marker mismatch are rejected', () => {
    const state = fixture(); state.agents[0].user_id = 'c'.repeat(32);
    assert.throws(() => collisionCheck(state, inventory()));
    const docs = inventory(); docs.users = ['c', 'd'].map(char => ({id: char.repeat(32), kz5_live_test: marker(state, 'user', 1)}));
    assert.throws(() => collisionCheck(state, docs));
});
test('convergence preserves unrelated fields within owned resources', () => {
    const actual = {id: 'c'.repeat(32), custom: true, sip: {username: 'old', custom: true}};
    const desired = {sip: {username: 'new'}}; const result = merged(actual, desired);
    assert.deepEqual(result, {custom: true, sip: {username: 'new', custom: true}});
    assert(subset(result, desired)); assert(!sameMarker({}, marker(fixture(), 'user', 1)));
});
test('runtime permits edited queue operations without reverting them', () => {
    const state = fixture(); state.queue_id = 'e'.repeat(32);
    const target = targets(state).find(item => item.collection === 'queues');
    const actual = {...target.body(), id: state.queue_id, name: 'User Edited Queue', strategy: 'most_idle',
        connection_timeout: 900, agent_ring_timeout: 45, announcements: {interval: 60, initial_delay: 30,
            position_announcements_enabled: true, wait_time_announcements_enabled: false, language: 'en-us'}};
    const before = JSON.stringify(actual);
    assert(runtimeTargetMatches(actual, target));
    assert.equal(JSON.stringify(actual), before);
    assert(!subset(actual, target.body()));
});
test('runtime queue validation still rejects foreign marker, tenant and resource IDs', () => {
    const state = fixture(); state.queue_id = 'e'.repeat(32);
    const target = targets(state).find(item => item.collection === 'queues');
    const actual = {...target.body(), id: state.queue_id};
    assert(!runtimeTargetMatches({...actual, id: 'f'.repeat(32)}, target));
    assert(!runtimeTargetMatches({...actual, pvt_account_id: 'f'.repeat(32)}, target));
    assert(!runtimeTargetMatches({...actual, kz5_live_test: {...actual.kz5_live_test, account_id: 'f'.repeat(32)}}, target));
    assert(!runtimeTargetMatches({...actual, kz5_live_test: {...actual.kz5_live_test, deployment_id: 'f'.repeat(32)}}, target));
});
test('runtime keeps device owner and SIP authentication checks strict', () => {
    const state = fixture(); state.agents[0].user_id = 'c'.repeat(32); state.agents[0].device_id = 'd'.repeat(32);
    const target = targets(state).find(item => item.collection === 'devices');
    const actual = {...target.body(), id: state.agents[0].device_id};
    assert(runtimeTargetMatches(actual, target));
    assert(!runtimeTargetMatches({...actual, owner_id: PROTECTED_USER}, target));
    assert(!runtimeTargetMatches({...actual, sip: {...actual.sip, password: 'wrong'}}, target));
});
console.log(`PASS ${passed} collision, identity, resume, convergence and runtime ownership tests; no external writes`);
