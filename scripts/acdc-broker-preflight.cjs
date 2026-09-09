'use strict';
// Read-only deployment guard. Never declare, purge or delete an AMQP queue.
const assert = require('node:assert/strict');
const dns = require('node:dns').promises;
const os = require('node:os');
const {execFileSync} = require('node:child_process');

function endpoint(raw) {
    const u = new URL(raw);
    assert(['amqp:', 'amqps:'].includes(u.protocol) && u.hostname && !u.hash);
    assert(u.pathname.startsWith('/') && u.pathname.length > 1);
    const vhost = decodeURIComponent(u.pathname.slice(1));
    assert(vhost && !/[\x00-\x1f\x7f]/.test(vhost));
    return {host: u.hostname.replace(/^\[|\]$/g, ''), port: Number(u.port ||
        (u.protocol === 'amqps:' ? 5671 : 5672)), protocol:
        u.protocol === 'amqps:' ? 'amqp/ssl' : 'amqp', vhost,
    user: decodeURIComponent(u.username), password: decodeURIComponent(u.password)};
}

function inspect(rows) {
    assert(Array.isArray(rows), 'Incomplete broker queue inventory');
    const names = new Set();
    let workQueues = 0, incompatible = 0;
    for (const q of rows) {
        assert(q && typeof q.name === 'string' && !names.has(q.name), 'Invalid queue inventory');
        names.add(q.name);
        if (!q.name.startsWith('acdc.queue.') || q.name.startsWith('acdc.queue.manager.')) continue;
        assert(/^acdc\.queue\.[a-f0-9]{32}\..+$/.test(q.name), 'Unrecognized ACDC work queue');
        assert(typeof q.auto_delete === 'boolean' && typeof q.durable === 'boolean',
            'Missing ACDC queue properties');
        workQueues++;
        if (q.auto_delete !== false || q.durable !== false) incompatible++;
    }
    assert.equal(incompatible, 0,
        `${incompatible} incompatible ACDC queues: drain callbacks and coordinate all old consumers before upgrade; see doc/acdc_broker_upgrade.md`);
    return {work_queues: workQueues, compatible: true};
}

function localEndpoint(ep, addresses, interfaces = os.networkInterfaces()) {
    const owned = new Set(Object.values(interfaces).flat().filter(Boolean).map(x => x.address));
    return addresses.length > 0 && addresses.every(x => owned.has(x.address));
}

function listenerMatches(ep, addresses, info) {
    assert(info?.result === 'ok' && typeof info.node === 'string' && info.node &&
        Array.isArray(info.listeners), 'Incomplete local broker listener inventory');
    assert(addresses.every(a => info.listeners.some(l => l.port === ep.port &&
        l.protocol === ep.protocol && (l.interface === a.address ||
        l.interface === (a.family === 6 ? '::' : '0.0.0.0')))),
    'Local RabbitMQ CLI node does not own the configured AMQP endpoint');
}

function cli(command, args) {
    return JSON.parse(execFileSync(command, args, {timeout: 30000, maxBuffer: 16 * 1024 * 1024,
        stdio: ['ignore', 'pipe', 'pipe'], encoding: 'utf8'}));
}

function management(ep, env) {
    assert(env.KAZOO_RABBITMQ_API_URL,
        'Remote broker requires KAZOO_RABBITMQ_API_URL and a monitoring/admin management identity; see doc/acdc_broker_upgrade.md');
    const u = new URL(env.KAZOO_RABBITMQ_API_URL);
    assert(['https:', 'http:'].includes(u.protocol) && !u.username && !u.password &&
        !u.search && !u.hash && u.pathname === '/' &&
        u.hostname.replace(/^\[|\]$/g, '') === ep.host &&
        (ep.protocol !== 'amqp/ssl' || u.protocol === 'https:'),
    'Management origin must match the AMQP host, without credentials/path or TLS downgrade');
    const user = env.KAZOO_RABBITMQ_API_USER || ep.user;
    const password = env.KAZOO_RABBITMQ_API_PASSWORD || ep.password;
    assert(user && password && !user.includes(':') && !/[\r\n]/.test(user + password),
        'Missing or invalid management credentials');
    return {origin: u.origin, authorization: 'Basic ' + Buffer.from(user + ':' + password).toString('base64')};
}

async function remoteInventory(ep, env, request = fetch) {
    const config = management(ep, env);
    const deadline = Date.now() + 60000;
    async function get(path) {
        const remaining = deadline - Date.now();
        assert(remaining > 0, 'Broker metadata deadline exceeded');
        const response = await request(config.origin + path, {method: 'GET', redirect: 'error',
            signal: AbortSignal.timeout(Math.min(15000, remaining)),
            headers: {Authorization: config.authorization, Accept: 'application/json'}});
        assert(response.status === 200, 'Management metadata request failed; verify endpoint and read permissions');
        const chunks = [];
        let bytes = 0;
        for await (const chunk of response.body) {
            bytes += chunk.length;
            assert(bytes <= 4 * 1024 * 1024, 'Management metadata response too large');
            chunks.push(Buffer.from(chunk));
        }
        return JSON.parse(Buffer.concat(chunks).toString('utf8'));
    }
    const who = await get('/api/whoami');
    const tags = Array.isArray(who.tags) ? who.tags : String(who.tags || '').split(',');
    assert(tags.some(t => ['administrator', 'monitoring'].includes(t)),
        'Management identity must see the complete broker inventory (monitoring/admin tag)');
    // Single-vhost details require administrator privileges in RabbitMQ 3.13.
    // Its built-in default exchange proves vhost existence using read access,
    // including when no ACDC queues exist yet. Never declare it as a probe.
    const scoped = '/api/exchanges/' + encodeURIComponent(ep.vhost) + '/amq.default?disable_stats=true';
    const exchange = await get(scoped);
    assert(exchange.vhost === ep.vhost && exchange.name === '' && exchange.type === 'direct',
        'Configured vhost default exchange not confirmed');
    const rows = [];
    let expected;
    for (let page = 1; page <= 100; page++) {
        const data = await get('/api/queues/' + encodeURIComponent(ep.vhost) +
            '?page=' + page + '&page_size=100&pagination=true&sort=name&disable_stats=true' +
            '&name=%5Eacdc%5B.%5Dqueue%5B.%5D&use_regex=true' +
            '&columns=name,vhost,auto_delete,durable');
        assert(data.page === page && data.page_size === 100 &&
            Number.isInteger(data.filtered_count) && data.filtered_count >= 0 &&
            Number.isInteger(data.total_count) && data.total_count >= data.filtered_count && Array.isArray(data.items),
        'Incomplete paginated broker inventory');
        expected ??= data.filtered_count;
        assert.equal(data.filtered_count, expected, 'Broker inventory changed during inspection; retry');
        const pages = Math.max(1, Math.ceil(expected / 100));
        assert(pages <= 100 && (data.page_count === pages || (expected === 0 && data.page_count === 0)) &&
            data.items.length === Math.min(100, expected - (page - 1) * 100),
        'Truncated broker inventory');
        assert(data.items.every(q => q.vhost === ep.vhost), 'Unexpected vhost in broker inventory');
        rows.push(...data.items);
        if (page === pages) return rows;
    }
    throw new Error('Broker inventory limit exceeded');
}

async function run(env = process.env) {
    const ep = endpoint(env.KAZOO_AMQP_URI);
    const addresses = await dns.lookup(ep.host, {all: true});
    let rows;
    if (!env.KAZOO_RABBITMQ_API_URL && localEndpoint(ep, addresses)) {
        listenerMatches(ep, addresses, cli('rabbitmq-diagnostics', ['-q', 'listeners', '--formatter', 'json']));
        rows = cli('rabbitmqctl', ['-q', '-p', ep.vhost, 'list_queues', 'name', 'auto_delete', 'durable', '--formatter=json']);
    } else rows = await remoteInventory(ep, env);
    console.log('PASS ACDC broker upgrade preflight ' + JSON.stringify(inspect(rows)));
}

module.exports = {endpoint, inspect, localEndpoint, listenerMatches, management, remoteInventory, run};
if (require.main === module) {
    // Never print external exceptions: HTTP/CLI/parser errors may contain credentials.
    run().catch(error => {
        console.error(error.code === 'ERR_ASSERTION' ? error.message.split('\n')[0] :
            'ACDC broker metadata check failed; verify configured broker access (details suppressed).');
        process.exitCode = 1;
    });
}
