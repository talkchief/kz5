#!/usr/bin/env node
'use strict';
// Pure mocked GETs only. Never opens protected files or runs the CLI entrypoint.
const assert = require('node:assert/strict');
const {verifyPhones, targets, ACCOUNT, OWNER, PROTECTED_DEVICE, PROTECTED_USER} = require('./provision-live-test-agents.cjs');
const id = n => n.toString(16).padStart(32, '0');
function fixture() {
    const state = {schema_version: 1, owner: OWNER, deployment_id: 'a'.repeat(32), account_id: ACCOUNT,
        realm: 'master.example.invalid', api_base: 'http://127.0.0.1:8000/v2',
        credentials_file: '/etc/kazoo/installer-secrets.env', protected_microsip_device_id: PROTECTED_DEVICE,
        queue_id: id(500), queue_callflow_id: id(501), queue_extension: '2000', sip_proxy_host: '192.0.2.1',
        sip_proxy_port: 5060, sip_transport: 'udp', agents: Array.from({length: 30}, (_, index) => ({
            index: index + 1, name: `LiveTestAgent${String(index + 1).padStart(2, '0')}`,
            extension: String(1002 + index), sip_username: `livetest${1002 + index}`,
            sip_password: 'b'.repeat(32), user_id: id(index + 1), device_id: id(index + 101), callflow_id: id(index + 201)}))};
    const docs = new Map(targets(state).filter(t => ['users', 'devices'].includes(t.collection)).map(t =>
        [`accounts/${ACCOUNT}/${t.collection}/${t.holder[t.key]}`, {...t.body(), id: t.holder[t.key]}]));
    docs.set(`accounts/${ACCOUNT}/devices/${PROTECTED_DEVICE}`, {id: PROTECTED_DEVICE, owner_id: PROTECTED_USER});
    docs.set(`accounts/${ACCOUNT}/users/${PROTECTED_USER}`, {id: PROTECTED_USER});
    const calls = [];
    const get = async (method, path, body, token) => {
        assert.equal(method, 'GET'); assert.equal(body, undefined); assert.equal(token, 'mock-token');
        assert.match(path, new RegExp(`^accounts/${ACCOUNT}/(users|devices)/[a-f0-9]{32}$`));
        calls.push(path); return {data: docs.get(path)};
    };
    return {state, docs, calls, get};
}
let passed = 0;
async function test(name, fn) { await fn(); passed++; console.log(`PASS ${name}`); }
async function main() {
    await test('62 exact scoped GETs; arbitrary queue roster/status/routes neither read nor changed', async () => {
        const f = fixture(), before = JSON.stringify(f.state), docsBefore = JSON.stringify([...f.docs]);
        // No queue/agent/callflow responses exist. Even a one-agent or empty
        // operator roster therefore cannot become a phone-recovery dependency.
        await verifyPhones(f.state, 'mock-token', f.get);
        assert.equal(f.calls.length, 62); assert.equal(new Set(f.calls).size, 62);
        assert.equal(JSON.stringify(f.state), before); assert.equal(JSON.stringify([...f.docs]), docsBefore);
    });
    for (const key of ['user_id', 'device_id', 'sip_username']) await test(`duplicate ${key} fails before GET`, async () => {
        const f = fixture(); f.state.agents[1][key] = f.state.agents[0][key];
        await assert.rejects(verifyPhones(f.state, 'mock-token', f.get)); assert.equal(f.calls.length, 0);
    });
    for (const key of ['user_id', 'device_id']) await test(`missing ${key} fails before GET`, async () => {
        const f = fixture(); f.state.agents[0][key] = '';
        await assert.rejects(verifyPhones(f.state, 'mock-token', f.get), /missing_or_duplicate_identity/);
        assert.equal(f.calls.length, 0);
    });
    const mutations = [
        ['user name', 'users', d => {d.first_name = 'Different';}],
        ['user privilege', 'users', d => {d.priv_level = 'admin';}],
        ['device password', 'devices', d => {d.sip.password = 'wrong';}],
        ['device username', 'devices', d => {d.sip.username = 'foreign';}],
        ['device realm', 'devices', d => {d.sip.realm = 'foreign.invalid';}],
        ['device owner', 'devices', d => {d.owner_id = PROTECTED_USER;}],
        ['device disabled', 'devices', d => {d.enabled = false;}],
        ['missing device', 'devices', () => undefined],
        ['foreign document ID', 'devices', d => {d.id = id(999);}],
        ['foreign tenant', 'devices', d => {d.pvt_account_id = id(999);}],
        ['foreign deployment marker', 'devices', d => {d.kz5_live_test.deployment_id = id(999);}],
        ['wrong marker index', 'devices', d => {d.kz5_live_test.index = 30;}]
    ];
    for (const [name, collection, mutate] of mutations) await test(`${name} is rejected`, async () => {
        const f = fixture(), key = `accounts/${ACCOUNT}/${collection}/${f.state.agents[0][collection === 'users' ? 'user_id' : 'device_id']}`;
        const doc = f.docs.get(key); mutate(doc); if (name === 'missing device') f.docs.delete(key);
        await assert.rejects(verifyPhones(f.state, 'mock-token', f.get), /PHONE_OWNERSHIP: owned_(user|device)_mismatch/);
    });
    await test('protected MicroSIP owner is immutable and no protected device can be adopted', async () => {
        const f = fixture(); f.docs.get(`accounts/${ACCOUNT}/devices/${PROTECTED_DEVICE}`).owner_id = id(999);
        await assert.rejects(verifyPhones(f.state, 'mock-token', f.get), /protected_microsip_mismatch/);
        f.state.agents[0].device_id = PROTECTED_DEVICE;
        await assert.rejects(verifyPhones(f.state, 'mock-token', f.get), /protected MicroSIP/);
    });
    await test('API failure is not converted into ownership success', async () => {
        await assert.rejects(verifyPhones(fixture().state, 'mock-token', async () => {throw Error('mock transport unavailable');}), /transport unavailable/);
    });
    console.log(`PASS ${passed} mocked phone-ownership tests; no network/files/services/roster mutations`);
}
main().catch(error => {console.error(error); process.exitCode = 1;});
