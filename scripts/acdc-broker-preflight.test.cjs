'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {endpoint, inspect, localEndpoint, listenerMatches, management, remoteInventory} = require('./acdc-broker-preflight.cjs');
const ep = endpoint('amqp://user:pass@broker.test:5672/%2F');
const env = {KAZOO_RABBITMQ_API_URL: 'https://broker.test:15671'};
const name = 'acdc.queue.' + 'a'.repeat(32) + '.queue-test';
const queue = {name, vhost: '/', auto_delete: false, durable: false};

test('empty or retained work queues pass; secondary manager declaration is unrelated', () => {
    assert.equal(inspect([]).work_queues, 0);
    assert.equal(inspect([queue, {name: 'acdc.queue.manager.abc', auto_delete: true}]).work_queues, 1);
});
test('legacy auto-delete queues block even when empty with zero consumers', () => {
    assert.throws(() => inspect([{...queue, auto_delete: true, messages: 0, consumers: 0}]), /incompatible/);
    assert.throws(() => inspect([{...queue, durable: true}]), /incompatible/);
});
test('incomplete, duplicate or unexpected work-queue metadata fails closed', () => {
    for (const rows of [null, [queue, queue], [{name}], [{...queue, auto_delete: 'false'}],
        [{...queue, name: 'acdc.queue.unknown'}]]) assert.throws(() => inspect(rows));
});
test('effective URI owns vhost and port including encoded credentials', () => {
    const parsed = endpoint('amqps://a%40b:p%3Aword@broker.test/team%2Fone');
    assert.equal(parsed.vhost, 'team/one');
    assert.equal(parsed.port, 5671);
    assert.equal(parsed.user, 'a@b');
    for (const u of ['http://broker.test/%2F', 'amqp://broker.test', 'amqp://broker.test/',
        'amqp://broker.test/%00', 'amqp://broker.test/%zz']) assert.throws(() => endpoint(u));
});
test('local mode requires every resolved address owned by this server', () => {
    const interfaces = {lo: [{address: '127.0.0.1'}], eth0: [{address: '10.1.0.44'}]};
    assert(localEndpoint(ep, [{address: '10.1.0.44'}], interfaces));
    assert(!localEndpoint(ep, [], interfaces));
    assert(!localEndpoint(ep, [{address: '10.1.0.44'}, {address: '10.1.0.10'}], interfaces));
});
test('CLI listener must own exact address, protocol and port', () => {
    const addresses = [{address: '10.1.0.44', family: 4}];
    const info = {result: 'ok', node: 'rabbit@test', listeners: [{interface: '0.0.0.0', protocol: 'amqp', port: 5672}]};
    listenerMatches(ep, addresses, info);
    for (const changed of [{port: 5673}, {protocol: 'http'}, {interface: '127.0.0.1'}]) {
        assert.throws(() => listenerMatches(ep, addresses, {...info, listeners: [{...info.listeners[0], ...changed}]}));
    }
});
test('management origin rejects credential redirection and TLS downgrade', () => {
    assert.equal(management(ep, env).origin, 'https://broker.test:15671');
    for (const url of ['https://other.test', 'https://broker.test/path', 'https://user:pass@broker.test',
        'https://broker.test/?x=y', 'https://broker.test/#x']) {
        assert.throws(() => management(ep, {...env, KAZOO_RABBITMQ_API_URL: url}));
    }
    assert.throws(() => management({...ep, protocol: 'amqp/ssl'}, {KAZOO_RABBITMQ_API_URL: 'http://broker.test'}));
    assert.throws(() => management(ep, {}), /Remote broker requires/);
});

function mock(pages, who = {tags: ['monitoring']}, vhost = '/', exchangeOverride = {}) {
    const calls = [];
    return {calls, request: async (url, opts) => {
        calls.push(url);
        assert.equal(opts.method, 'GET');
        assert.equal(opts.redirect, 'error');
        assert(opts.signal);
        let data;
        if (url.endsWith('/api/whoami')) data = who;
        // RabbitMQ 3.13.7 reserves single-vhost details for administrators,
        // even when this monitoring identity can read all scoped queues.
        else if (url.includes('/api/vhosts/')) return new Response('{}', {status: 401});
        else if (url.includes('/api/exchanges/')) {
            assert(url.endsWith('/api/exchanges/%2F/amq.default?disable_stats=true'));
            data = {name: '', vhost, type: 'direct', ...exchangeOverride};
        }
        else {
            assert(url.includes('/api/queues/%2F?'));
            data = pages[Number(new URL(url).searchParams.get('page')) - 1];
        }
        return new Response(JSON.stringify(data), {status: 200});
    }};
}
const page = (items, n = 1, count = items.length) => ({page: n, page_size: 100,
    filtered_count: count, total_count: count, page_count: Math.ceil(count / 100), items});

test('remote reader accepts fresh empty vhost and reads only configured vhost metadata', async () => {
    const m = mock([page([])]);
    assert.deepEqual(await remoteInventory(ep, env, m.request), []);
    assert.equal(m.calls.length, 3);
});
test('remote reader obtains every page and enforces work-queue properties', async () => {
    const first = Array.from({length: 100}, (_, i) => ({...queue, name: name + i}));
    const m = mock([page(first, 1, 101), page([queue], 2, 101)]);
    assert.equal(inspect(await remoteInventory(ep, env, m.request)).work_queues, 101);
    const legacy = mock([page([{...queue, auto_delete: true}])]);
    const rows = await remoteInventory(ep, env, legacy.request);
    assert.throws(() => inspect(rows), /incompatible/);
});
test('restricted identity and unconfirmed vhost cannot claim empty inventory success', async () => {
    for (const m of [mock([page([])], {tags: 'management'}), mock([page([])], {tags: 'administrator'}, 'other'),
        mock([page([])], undefined, '/', {name: 'another'}), mock([page([])], undefined, '/', {type: 'topic'})]) {
        await assert.rejects(remoteInventory(ep, env, m.request));
    }
});
test('truncated, changing, wrong-vhost, unpaginated and failed responses fail closed', async () => {
    const invalid = [[], {...page([queue]), total_count: 0}, {...page([queue]), page_count: 2},
        {...page([queue]), page: 2}, page([{...queue, vhost: 'other'}]),
        {...page([queue]), filtered_count: 101, total_count: 101, page_count: 2}];
    for (const value of invalid) await assert.rejects(remoteInventory(ep, env, mock([value]).request));
    const first = Array.from({length: 100}, (_, i) => ({...queue, name: name + i}));
    await assert.rejects(remoteInventory(ep, env, mock([page(first, 1, 101), page([queue], 2, 102)]).request));
    const duplicate = await remoteInventory(ep, env, mock([page([queue, queue])]).request);
    assert.throws(() => inspect(duplicate), /inventory/);
    await assert.rejects(remoteInventory(ep, env, async () => new Response('denied', {status: 403})));
});
