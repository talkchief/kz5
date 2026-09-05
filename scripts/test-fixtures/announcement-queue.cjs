#!/usr/bin/env node
'use strict';
// Owns only a marked temporary queue/route in the protected acceptance tenant.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const assert = require('node:assert/strict');
const [action, runDirectory] = process.argv.slice(2);
assert(['setup', 'cleanup'].includes(action) && path.isAbsolute(runDirectory));
const root = fs.realpathSync(runDirectory), statePath = path.join(root, 'announcement-fixture.json');
assert(root.startsWith('/var/log/kazoo-acceptance/'));
function protectedContents(file) {
    const stat = fs.lstatSync(file);
    assert(stat.isFile() && !stat.isSymbolicLink() && stat.uid === 0 && (stat.mode & 0o777) === 0o600);
    return fs.readFileSync(file, 'utf8');
}
function env(file, encoded) {
    return Object.fromEntries(protectedContents(file).split('\n').filter(line => line && !line.startsWith('#')).map(line => {
        const split = line.indexOf('='); assert(split > 0);
        return [line.slice(0, split), encoded ? Buffer.from(line.slice(split + 1), 'base64').toString() : line.slice(split + 1)];
    }));
}
const state = env(process.env.KAZOO_ACCEPTANCE_STATE_FILE || '/etc/kazoo/acceptance-secrets.env', true);
const secrets = env('/etc/kazoo/installer-secrets.env', false), account = state.ACCEPTANCE_ACCOUNT_ID;
assert(/^[a-f0-9]{32}$/.test(account));
assert(/^acceptance-[a-f0-9]{12}\.invalid$/.test(state.ACCEPTANCE_REALM));
assert(/^Kazoo5 Acceptance [a-f0-9]{12}$/.test(state.ACCEPTANCE_ACCOUNT_NAME));
let token;
async function request(method, relative, data, optional404 = false) {
    assert(relative === 'user_auth' || relative === `accounts/${account}` || relative.startsWith(`accounts/${account}/`));
    const response = await fetch('http://127.0.0.1:8000/v2/' + relative, {method,
        headers: {'Content-Type': 'application/json', ...(token ? {'X-Auth-Token': token} : {})},
        ...(data !== undefined ? {body: JSON.stringify({data})} : {}), signal: AbortSignal.timeout(20000)});
    if (optional404 && method === 'GET' && response.status === 404) return {status: 'success', data: null};
    assert(response.ok, `HTTP ${response.status}: ${method} ${relative}`);
    const result = await response.json(); assert.equal(result.status, 'success', 'API envelope failure');
    return result;
}
function persist(fixture) {fs.writeFileSync(statePath, JSON.stringify(fixture, null, 2) + '\n', {mode: 0o600});}
function publicQueue(queue) {
    return Object.fromEntries(Object.entries(queue).filter(([key]) => !key.startsWith('_') && !key.startsWith('pvt_')
        && !['id', 'agents', 'read_only'].includes(key)));
}
(async () => {
    const auth = await request('PUT', 'user_auth', {
        credentials: crypto.createHash('md5').update((secrets.KAZOO_MASTER_ADMIN_USER || 'admin') + ':' + secrets.KAZOO_MASTER_ADMIN_PASSWORD).digest('hex'),
        method: 'md5', realm: secrets.KAZOO_MASTER_ACCOUNT_REALM});
    token = auth.auth_token; assert(token && auth.data.account_id !== account, 'Refusing master tenant');
    const tenant = (await request('GET', `accounts/${account}`)).data;
    assert.equal(tenant.name, state.ACCEPTANCE_ACCOUNT_NAME); assert.equal(tenant.realm, state.ACCEPTANCE_REALM);
    if (action === 'setup') {
        assert(!fs.existsSync(statePath), 'Fixture already exists; clean it explicitly first');
        const flows = await request('GET', `accounts/${account}/callflows?paginate=false`);
        assert(Array.isArray(flows.data) && !flows.next_start_key, 'Incomplete callflow inventory');
        assert(!flows.data.some(flow => (flow.numbers || []).includes('2099')), 'Extension2099 is already occupied');
        const fixture = {account, marker: 'acdc-announcement-' + crypto.randomBytes(8).toString('hex'), extension: '2099'};
        persist(fixture);
        const queue = (await request('PUT', `accounts/${account}/queues`, {
            name: fixture.marker, kazoo_acceptance_fixture: fixture.marker, enter_when_empty: true,
            connection_timeout: 120, strategy: 'round_robin', moh: 'silence_stream://-1',
            announcements: {position_announcements_enabled: false, wait_time_announcements_enabled: false}, callback: {enabled: false}})).data;
        assert(/^[a-f0-9]{32}$/.test(queue.id)); fixture.queue_id = queue.id; persist(fixture);
        const snapshot = (await request('GET', `accounts/${account}/queues/${queue.id}`)).data;
        fs.writeFileSync(path.join(root, 'announcement-queue-before.json'), JSON.stringify(snapshot, null, 2) + '\n', {mode: 0o600});
        await request('PATCH', `accounts/${account}/queues/${queue.id}`, {announcements: {
            position_announcements_enabled: true, wait_time_announcements_enabled: false,
            initial_delay: 30, interval: 30, language: 'en-us'}, callback: {enabled: false}});
        const route = (await request('PUT', `accounts/${account}/callflows`, {name: fixture.marker,
            kazoo_acceptance_fixture: fixture.marker, numbers: ['2099'],
            flow: {module: 'acdc_member', data: {id: queue.id}, children: {}}})).data;
        assert(/^[a-f0-9]{32}$/.test(route.id)); fixture.callflow_id = route.id; persist(fixture);
        const verified = (await request('GET', `accounts/${account}/queues/${queue.id}`)).data;
        assert.equal(verified.announcements.initial_delay, 30); assert.equal(verified.announcements.interval, 30);
        assert.equal(verified.callback.enabled, false); assert.deepEqual(verified.agents, []);
        console.log(JSON.stringify({result: 'PASS', action, ...fixture, agents_changed: 0}));
    } else {
        if (!fs.existsSync(statePath)) return;
        const fixture = JSON.parse(protectedContents(statePath)); assert.equal(fixture.account, account);
        assert(/^acdc-announcement-[a-f0-9]{16}$/.test(fixture.marker));
        if (fixture.cleaned_at) return;
        // A create can commit even if its HTTP reply is lost. Recover only by
        // the unpredictable marker persisted BEFORE creation, never by name.
        for (const [collection, key] of [['queues', 'queue_id'], ['callflows', 'callflow_id']]) {
            if (fixture[key]) continue;
            const inventory = await request('GET', `accounts/${account}/${collection}?paginate=false`);
            assert(Array.isArray(inventory.data) && !inventory.next_start_key, 'Incomplete cleanup inventory');
            const recovered = [];
            for (const summary of inventory.data.filter(item => item.name === fixture.marker)) {
                assert(/^[a-f0-9]{32}$/.test(summary.id));
                const document = (await request('GET', `accounts/${account}/${collection}/${summary.id}`, undefined, true)).data;
                if (document && document.kazoo_acceptance_fixture === fixture.marker) recovered.push(document.id);
            }
            assert(recovered.length <= 1, 'Ambiguous duplicate fixture marker');
            if (recovered.length) {fixture[key] = recovered[0]; persist(fixture);}
        }
        if (fixture.callflow_id) {
            const route = (await request('GET', `accounts/${account}/callflows/${fixture.callflow_id}`, undefined, true)).data;
            if (route) {
                assert.equal(route.kazoo_acceptance_fixture, fixture.marker);
                assert.deepEqual(route.numbers, ['2099']); assert.equal(route.flow.data.id, fixture.queue_id);
                await request('DELETE', `accounts/${account}/callflows/${fixture.callflow_id}`);
            }
            delete fixture.callflow_id; persist(fixture);
        }
        if (fixture.queue_id) {
            const queue = (await request('GET', `accounts/${account}/queues/${fixture.queue_id}`, undefined, true)).data;
            if (queue) {
                assert.equal(queue.kazoo_acceptance_fixture, fixture.marker);
                const snapshotFile = path.join(root, 'announcement-queue-before.json');
                if (fs.existsSync(snapshotFile)) {
                    const snapshot = JSON.parse(protectedContents(snapshotFile));
                    assert.equal(snapshot.id, fixture.queue_id);
                    await request('POST', `accounts/${account}/queues/${fixture.queue_id}`, publicQueue(snapshot));
                }
                await request('DELETE', `accounts/${account}/queues/${fixture.queue_id}`);
            }
            delete fixture.queue_id; persist(fixture);
        }
        fixture.cleaned_at = new Date().toISOString(); persist(fixture);
        console.log(JSON.stringify({result: 'PASS', action, deleted_only_marked_fixture: true, agents_changed: 0}));
    }
})().catch(error => {console.error('Announcement fixture FAIL: ' + error.message); process.exitCode = 1;});
