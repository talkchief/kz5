'use strict';
// Explicit, fixed development fixture only. No production broker or messages.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const {spawnSync} = require('node:child_process');

async function main() {
    assert.deepEqual(process.argv.slice(2), ['--run-development-remote-preflight']);
    assert.equal(process.getuid(), 0);
    assert.equal(os.hostname(), 'kz5-testing');
    const input = '/root/kz5-bridge-remote-proof-client/client.json';
    const info = fs.lstatSync(input);
    assert(info.isFile() && info.uid === 0 && (info.mode & 511) === 384);
    const f = JSON.parse(fs.readFileSync(input));
    for (const [key, value] of Object.entries({owner: 'kz5-bridge-proof', host: '10.1.0.44',
        port: 35671, management_port: 35672, username: 'kz5-bridge-proof', vhost: 'kz5-bridge-proof'})) {
        assert.equal(f[key], value);
    }
    assert(/^[a-f0-9]{64}$/.test(f.password));
    assert.equal(fs.readFileSync(process.env.NODE_EXTRA_CA_CERTS, 'utf8'), f.ca_pem);
    assert(!process.env.NODE_TLS_REJECT_UNAUTHORIZED || process.env.NODE_TLS_REJECT_UNAUTHORIZED === '1');
    const origin = 'https://10.1.0.44:35672';
    let activeReceipt;
    async function request(method, route, body, expected = 200) {
        const response = await fetch(origin + route, {method, redirect: 'error',
            signal: AbortSignal.timeout(10000), headers: {'Content-Type': 'application/json',
                Authorization: 'Basic ' + Buffer.from(f.username + ':' + f.password).toString('base64')},
            body: body === undefined ? undefined : JSON.stringify(body)});
        if (activeReceipt) activeReceipt.last_http = {method, status: response.status, expected};
        assert.equal(response.status, expected, 'Fixture HTTP request did not return expected status');
        const text = await response.text();
        assert(text.length < 1024 * 1024);
        return text ? JSON.parse(text) : null;
    }
    const overview = await request('GET', '/api/overview');
    assert.equal(overview.node, 'rabbit_kz5_bridgeproof@localhost');
    assert.equal(overview.cluster_name, 'rabbit_kz5_bridgeproof@dev-testing');
    assert((await request('GET', '/api/whoami')).tags.includes('monitoring'));
    const parent = '/var/log/kazoo-acceptance';
    const stat = fs.lstatSync(parent);
    assert(stat.isDirectory() && stat.uid === 0 && !(stat.mode & 18));
    const dir = fs.mkdtempSync(parent + '/acdc-broker-preflight.');
    fs.chmodSync(dir, 448);
    const nonce = crypto.randomBytes(16).toString('hex');
    const name = 'acdc.queue.' + nonce + '.installer-proof';
    const route = '/api/queues/kz5-bridge-proof/' + encodeURIComponent(name);
    const receipt = {complete: false, client: '10.1.0.26', broker: '10.1.0.44:35671',
        management: origin, vhost: f.vhost, queue: name, checks: [], message_publishes: 0,
        provider_requests: 0, runtime_installs: 0, cleanup_complete: false};
    activeReceipt = receipt;
    receipt.guard_results = [];
    const helper = path.join(__dirname, 'acdc-broker-preflight.cjs');
    const installer = path.join(__dirname, 'install-kazoo5.sh');
    const digest = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
    receipt.helper_sha256 = digest(helper);
    receipt.installer_sha256 = digest(installer);
    const setupEnv = {...process.env, KAZOO_DEPLOYMENT_CONFIG: path.join(dir, 'deployment.env'),
        KAZOO_AMQP_URI: `amqps://${f.username}:${f.password}@${f.host}:${f.port}/${f.vhost}`,
        KAZOO_RABBITMQ_API_URL: origin, KAZOO_RABBITMQ_API_USER: '', KAZOO_RABBITMQ_API_PASSWORD: '',
        KAZOO_RABBITMQ_API_CA_FILE: process.env.NODE_EXTRA_CA_CERTS};
    const saved = spawnSync('/bin/bash', ['-c', 'set +x; source "$1"; save_deployment_config',
        'preflight-proof-config', installer], {env: setupEnv, encoding: 'utf8', timeout: 10000});
    assert.equal(saved.status, 0, 'Installer did not save protected fixture settings');
    assert.equal(fs.statSync(setupEnv.KAZOO_DEPLOYMENT_CONFIG).mode & 0o777, 0o600);
    const env = {...process.env};
    for (const key of Object.keys(env)) {
        if (key.startsWith('KAZOO_') || key === 'NODE_EXTRA_CA_CERTS') delete env[key];
    }
    env.KAZOO_DEPLOYMENT_CONFIG = setupEnv.KAZOO_DEPLOYMENT_CONFIG;
    receipt.persisted_ca_input = true;
    receipt.child_extra_ca_environment = false;
    function guard(allowed) {
        const result = spawnSync('/bin/bash', ['-c',
            'set +x; source "$1"; resolve_amqp_uri; acdc_broker_upgrade_preflight', 'preflight-proof', installer],
        {env, encoding: 'utf8', timeout: 95000, maxBuffer: 128 * 1024});
        receipt.guard_results.push({expected_allowed: allowed, status: result.status,
            result: result.stdout?.includes('PASS ACDC broker upgrade preflight') ? 'accepted' :
                /incompatible ACDC queues/.test(result.stderr) ? 'legacy_rejected' :
                /inventory/.test(result.stderr) ? 'inventory_unconfirmed' : 'other_failure'});
        if (allowed) assert(result.status === 0 && result.stdout.includes('PASS ACDC broker upgrade preflight'),
            'Real installer guard did not accept compatible remote inventory');
        else assert(result.status !== 0 && /incompatible ACDC queues/.test(result.stderr),
            'Real installer guard did not reject legacy remote inventory');
    }
    let owned = false, autoDelete;
    async function removeOwned() {
        if (!owned) return;
        const statsView = await request('GET', route);
        const q = await request('GET', route + '?disable_stats=true');
        receipt.cleanup_observations ??= [];
        receipt.cleanup_observations.push({name_matches: q.name === name, vhost_matches: q.vhost === f.vhost,
            durable_matches: q.durable === false, auto_delete_matches: q.auto_delete === autoDelete,
            owner_matches: q.arguments?.['x-kz5-preflight-proof'] === nonce,
            stats_view_owner_matches: statsView.arguments?.['x-kz5-preflight-proof'] === nonce,
            stats_view_auto_delete_matches: statsView.auto_delete === autoDelete,
            stats_view_name_matches: statsView.name === name,
            stats_view_vhost_matches: statsView.vhost === f.vhost,
            stats_view_durable_matches: statsView.durable === false});
        assert(q.name === name && q.vhost === f.vhost && q.durable === false &&
            q.auto_delete === autoDelete && q.arguments?.['x-kz5-preflight-proof'] === nonce);
        // Classic queue deletion is broker-atomic and refuses consumers/messages.
        await request('DELETE', route + '?if-empty=true&if-unused=true', undefined, 204);
        owned = false;
    }
    try {
        receipt.phase = 'initial_guard';
        guard(true);
        receipt.checks.push('initial_remote_inventory_accepted');
        for (const value of [true, false]) {
            autoDelete = value;
            receipt.phase = value ? 'create_legacy' : 'create_retained';
            // Mark potential ownership before PUT: timeout must not hide a created queue.
            owned = true;
            await request('PUT', route, {auto_delete: value, durable: false,
                arguments: {'x-queue-type': 'classic', 'x-kz5-preflight-proof': nonce}}, 201);
            receipt.phase = value ? 'legacy_guard' : 'retained_guard';
            guard(!value);
            receipt.checks.push(value ? 'legacy_remote_queue_rejected' : 'retained_remote_queue_accepted');
            receipt.phase = value ? 'remove_legacy' : 'remove_retained';
            await removeOwned();
        }
        receipt.phase = 'final_guard';
        guard(true);
        receipt.checks.push('post_cleanup_remote_inventory_accepted');
        assert.equal(digest(helper), receipt.helper_sha256);
        assert.equal(digest(installer), receipt.installer_sha256);
        receipt.complete = true;
        receipt.phase = 'complete';
    } catch (error) {
        receipt.failure_http = receipt.last_http;
        throw error;
    } finally {
        try { await removeOwned(); receipt.cleanup_complete = true; }
        finally {
            fs.writeFileSync(path.join(dir, 'receipt.json'), JSON.stringify(receipt, null, 2) + '\n',
                {mode: 384, flag: 'wx'});
            console.log('Receipt: ' + path.join(dir, 'receipt.json'));
        }
    }
    console.log('PASS actual installer guard: remote monitoring identity, legacy rejection, retained acceptance, owned empty queue cleanup');
}
main().catch(() => {
    console.error('Remote preflight acceptance failed; inspect protected receipt; details suppressed.');
    process.exitCode = 1;
});
