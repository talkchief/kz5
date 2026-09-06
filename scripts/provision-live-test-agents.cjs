#!/usr/bin/env node
'use strict';

// Explicit, persistent master-account fixture. No call originates or resource
// deletions occur here. Credentials are data in root-only files, never argv.
const fs = require('node:fs');
const crypto = require('node:crypto');
const childProcess = require('node:child_process');

const ACCOUNT = '302ae5a70c403124f764cbc54229cfcd';
const PROTECTED_DEVICE = 'b9765af7b7ce1e740263900e3fb11bb9';
const PROTECTED_USER = '12d1a51ac7fddbbc552c693215eda876';
const OWNER = 'kazoo5-master-live-test-agents';
const STATE_FILE = '/etc/kazoo/live-test-agents.json';
const AUTH_FILE = '/etc/kazoo/installer-secrets.env';
const API_BASE = 'http://127.0.0.1:8000/v2';
const ID = /^[a-f0-9]{32}$/;
const COLLECTIONS = ['users', 'devices', 'queues', 'callflows'];

function fail(message) { throw new Error(message); }
function check(condition, message) { if (!condition) fail(message); }
function hash(value) { return crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex'); }
function privateFile(path) {
    const stat = fs.lstatSync(path);
    check(stat.isFile() && !stat.isSymbolicLink() && stat.uid === 0 && (stat.mode & 0o777) === 0o600,
        `Refusing non-private file: ${path}`);
    return fs.readFileSync(path, 'utf8');
}
function secureParent() {
    const stat = fs.lstatSync('/etc/kazoo');
    check(stat.isDirectory() && !stat.isSymbolicLink() && stat.uid === 0 && (stat.mode & 0o022) === 0,
        'State directory must be root-owned and not group/world writable');
}
function saveState(state) {
    secureParent();
    if (fs.existsSync(STATE_FILE)) privateFile(STATE_FILE);
    const temporary = `${STATE_FILE}.${process.pid}.${crypto.randomBytes(4).toString('hex')}.tmp`;
    const fd = fs.openSync(temporary, fs.constants.O_WRONLY | fs.constants.O_CREAT |
        fs.constants.O_EXCL | fs.constants.O_NOFOLLOW, 0o600);
    try {
        fs.writeFileSync(fd, `${JSON.stringify(state, null, 2)}\n`);
        fs.fsyncSync(fd);
    } finally { fs.closeSync(fd); }
    fs.renameSync(temporary, STATE_FILE);
    const dir = fs.openSync('/etc/kazoo', fs.constants.O_RDONLY);
    try { fs.fsyncSync(dir); } finally { fs.closeSync(dir); }
}
function validateState(state) {
    check(state.schema_version === 1 && state.owner === OWNER && state.account_id === ACCOUNT &&
        ID.test(state.deployment_id) && state.api_base === API_BASE && state.credentials_file === AUTH_FILE &&
        state.protected_microsip_device_id === PROTECTED_DEVICE && state.queue_extension === '2000',
    'State account, owner, API, or protected device mismatch');
    check(typeof state.realm === 'string' && /^[a-zA-Z0-9.-]+$/.test(state.realm) &&
        typeof state.sip_proxy_host === 'string' && /^[a-zA-Z0-9.-]+$/.test(state.sip_proxy_host) && state.sip_proxy_port === 5060 &&
        state.sip_transport === 'udp', 'State SIP target is invalid');
    check(Array.isArray(state.agents) && state.agents.length === 30, 'State must contain exactly 30 agents');
    for (const [index, agent] of state.agents.entries()) {
        const extension = String(1002 + index);
        check(agent.index === index + 1 && agent.name === `LiveTestAgent${String(index + 1).padStart(2, '0')}` &&
            agent.extension === extension && agent.sip_username === `livetest${extension}` &&
            /^[a-f0-9]{32}$/.test(agent.sip_password), 'State agent identity or credential shape mismatch');
        for (const key of ['user_id', 'device_id', 'callflow_id'])
            check(!agent[key] || ID.test(agent[key]), 'Invalid saved agent resource ID');
        check(agent.user_id !== PROTECTED_USER && agent.device_id !== PROTECTED_DEVICE,
            'State tries to own the protected MicroSIP identity');
    }
    for (const key of ['queue_id', 'queue_callflow_id']) check(!state[key] || ID.test(state[key]), 'Invalid queue ID');
    return state;
}
function createState(realm) {
    const route = childProcess.execFileSync('ip', ['-4', 'route', 'get', '1.1.1.1'], {encoding: 'utf8'});
    const source = /\bsrc\s+([0-9.]+)/.exec(route);
    check(source, 'Cannot resolve local SIP proxy address');
    return validateState({schema_version: 1, owner: OWNER, deployment_id: crypto.randomBytes(16).toString('hex'),
        account_id: ACCOUNT, realm, queue_id: '', queue_callflow_id: '', queue_extension: '2000',
        sip_proxy_host: source[1], sip_proxy_port: 5060, sip_transport: 'udp', api_base: API_BASE,
        credentials_file: AUTH_FILE, protected_microsip_device_id: PROTECTED_DEVICE,
        agents: Array.from({length: 30}, (_, index) => ({index: index + 1,
            name: `LiveTestAgent${String(index + 1).padStart(2, '0')}`, extension: String(1002 + index),
            user_id: '', device_id: '', callflow_id: '', sip_username: `livetest${1002 + index}`,
            sip_password: crypto.randomBytes(16).toString('hex')}))});
}
function marker(state, kind, index = 0) {
    return {owner: OWNER, deployment_id: state.deployment_id, account_id: ACCOUNT, kind, index};
}
function sameMarker(doc, expected) {
    const actual = doc.kz5_live_test;
    return actual && Object.keys(expected).every(key => actual[key] === expected[key]);
}
function subset(actual, expected) {
    if (Array.isArray(expected)) return JSON.stringify(actual) === JSON.stringify(expected);
    if (expected && typeof expected === 'object') return actual && typeof actual === 'object' &&
        Object.keys(expected).every(key => subset(actual[key], expected[key]));
    return actual === expected;
}
function merged(actual, expected) {
    if (!expected || typeof expected !== 'object' || Array.isArray(expected)) return expected;
    const result = {...actual};
    for (const [key, value] of Object.entries(expected)) result[key] = merged(actual?.[key], value);
    delete result.id;
    return result;
}
async function request(method, path, body, token) {
    let response;
    try {
        response = await fetch(`${API_BASE}/${path}`, {method,
            headers: {'Content-Type': 'application/json', ...(token ? {'X-Auth-Token': token} : {})},
            body: body === undefined ? undefined : JSON.stringify({data: body}),
            signal: AbortSignal.timeout(60000)});
    } catch (_) { fail(`Crossbar ${method} transport failure; rerun safely after service recovery`); }
    let json;
    try { json = await response.json(); } catch (_) { fail(`Crossbar ${method} returned invalid JSON`); }
    check(response.ok && json.status === 'success', `Crossbar ${method} ${path.split('?')[0]} failed: HTTP ${response.status}`);
    return json;
}
async function authenticate() {
    const values = new Map();
    for (const line of privateFile(AUTH_FILE).split('\n')) {
        if (!line || line.startsWith('#')) continue;
        const separator = line.indexOf('=');
        check(separator > 0, 'Malformed administrator credential file');
        const key = line.slice(0, separator);
        check(!values.has(key), 'Duplicate administrator credential key');
        values.set(key, line.slice(separator + 1));
    }
    const user = values.get('KAZOO_MASTER_ADMIN_USER');
    const password = values.get('KAZOO_MASTER_ADMIN_PASSWORD');
    const realm = values.get('KAZOO_MASTER_ACCOUNT_REALM');
    check(user && password && realm, 'Missing saved administrator credentials');
    const credentials = crypto.createHash('md5').update(`${user}:${password}`).digest('hex');
    const auth = await request('PUT', 'user_auth', {credentials, method: 'md5', realm});
    check(auth.data?.account_id === ACCOUNT && typeof auth.auth_token === 'string' && auth.auth_token,
        'Refusing authentication to any account other than the pinned master account');
    return {token: auth.auth_token, realm};
}
function accountPath(collection, id = '') { return `accounts/${ACCOUNT}/${collection}${id ? `/${id}` : ''}`; }
async function inventory(token) {
    const result = {};
    for (const collection of COLLECTIONS) {
        const response = await request('GET', `${accountPath(collection)}?paginate=false`, undefined, token);
        check(Array.isArray(response.data) && response.data.length <= 500 && !response.next_start_key,
            `Refusing incomplete or oversized ${collection} inventory`);
        result[collection] = [];
        for (const item of response.data) {
            check(ID.test(item.id), `Invalid ${collection} inventory ID`);
            result[collection].push((await request('GET', accountPath(collection, item.id), undefined, token)).data);
        }
    }
    return result;
}
function targets(state) {
    const result = [];
    for (const agent of state.agents) {
        result.push({collection: 'users', holder: agent, key: 'user_id', mark: marker(state, 'user', agent.index),
            collision: doc => doc.first_name === agent.name || doc.username?.toLowerCase() === agent.name.toLowerCase(),
            body: () => ({first_name: agent.name, last_name: 'Agent', enabled: true, priv_level: 'user',
                kz5_live_test: marker(state, 'user', agent.index)})});
        result.push({collection: 'devices', holder: agent, key: 'device_id', mark: marker(state, 'device', agent.index),
            collision: doc => doc.name === agent.name || doc.sip?.username === agent.sip_username,
            body: () => ({name: agent.name, owner_id: agent.user_id, enabled: true, device_type: 'softphone',
                sip: {method: 'password', username: agent.sip_username, password: agent.sip_password,
                    transport: 'udp', expire_seconds: 300}, kz5_live_test: marker(state, 'device', agent.index)})});
        result.push({collection: 'callflows', holder: agent, key: 'callflow_id', mark: marker(state, 'callflow', agent.index),
            collision: doc => doc.name === agent.name || doc.numbers?.includes(agent.extension) || doc.patterns?.length > 0,
            body: () => ({name: agent.name, numbers: [agent.extension], owner_id: agent.user_id,
                flow: {module: 'user', data: {id: agent.user_id}, children: {}},
                kz5_live_test: marker(state, 'callflow', agent.index)})});
    }
    result.push({collection: 'queues', holder: state, key: 'queue_id', mark: marker(state, 'queue'),
        collision: doc => doc.name === 'CallCenterLiveTest', body: () => ({name: 'CallCenterLiveTest',
            strategy: 'round_robin', connection_timeout: 300, agent_ring_timeout: 20, agent_wrapup_time: 0,
            enter_when_empty: true, max_queue_size: 100, ring_simultaneously: 1, record_caller: false,
            announcements: {position_announcements_enabled: true, wait_time_announcements_enabled: true,
                interval: 30, language: 'en-us'}, kz5_live_test: marker(state, 'queue')})});
    result.push({collection: 'callflows', holder: state, key: 'queue_callflow_id', mark: marker(state, 'queue_callflow'),
        collision: doc => doc.name === 'CallCenterLiveTest' || doc.numbers?.includes('2000') || doc.patterns?.length > 0,
        body: () => ({name: 'CallCenterLiveTest', numbers: ['2000'],
            flow: {module: 'acdc_member', data: {id: state.queue_id}, children: {}},
            kz5_live_test: marker(state, 'queue_callflow')})});
    return result;
}
function collisionCheck(state, existing) {
    for (const target of targets(state)) {
        const owned = existing[target.collection].filter(doc => sameMarker(doc, target.mark));
        check(owned.length <= 1, `Duplicate marked ${target.collection} resource`);
        const saved = target.holder[target.key];
        if (saved) check(owned.length === 1 && owned[0].id === saved, `Saved ${target.collection} ID lost its exact ownership marker`);
        for (const doc of existing[target.collection]) {
            if (sameMarker(doc, target.mark)) continue;
            check(!target.collision(doc), `Unrelated ${target.collection} collision; no resources changed`);
        }
        if (!saved && owned.length) target.holder[target.key] = owned[0].id;
    }
}
function unrelatedSnapshots(state, existing) {
    const marks = targets(state);
    return COLLECTIONS.flatMap(collection => existing[collection].filter(doc =>
        !marks.some(target => target.collection === collection && sameMarker(doc, target.mark)))
        .map(doc => ({collection, id: doc.id, digest: hash(doc)})));
}
async function rosterCheck(state, token) {
    if (!state.queue_id) return;
    const roster = (await request('GET', `${accountPath('queues', state.queue_id)}/roster`, undefined, token)).data;
    check(Array.isArray(roster) && roster.every(id => state.agents.some(agent => agent.user_id === id)),
        'Queue contains an unrelated agent; refusing roster replacement');
}
function runtimeTargetMatches(actual, target) {
    if (!actual || actual.id !== target.holder[target.key] || !sameMarker(actual, target.mark) ||
        (actual.pvt_account_id && actual.pvt_account_id !== ACCOUNT) ||
        (actual.account_id && actual.account_id !== ACCOUNT)) return false;
    // Operators legitimately edit queue announcements, timing, strategy and
    // labels through Monster UI. Those settings are not ownership evidence.
    // Runtime status/phone operations never converge or overwrite this queue.
    // Device auth/owner, user privileges and route destinations remain strict.
    return target.collection === 'queues' || subset(actual, target.body());
}
async function verify(state, token, requireDefaults = false) {
    for (const target of targets(state)) {
        check(ID.test(target.holder[target.key]), 'Provisioning is incomplete; rerun --provision');
        const actual = (await request('GET', accountPath(target.collection, target.holder[target.key]), undefined, token)).data;
        check(runtimeTargetMatches(actual, target) && (!requireDefaults || subset(actual, target.body())),
            `Owned ${target.collection} verification failed`);
    }
    const roster = (await request('GET', `${accountPath('queues', state.queue_id)}/roster`, undefined, token)).data;
    check(Array.isArray(roster) && roster.length === 30 && new Set(roster).size === 30 &&
        state.agents.every(agent => roster.includes(agent.user_id)), 'Queue roster must contain exactly the 30 owned agents');
    for (const agent of state.agents) {
        const membership = (await request('GET', `${accountPath('agents', agent.user_id)}/queue_status`, undefined, token)).data;
        check(Array.isArray(membership) && membership.includes(state.queue_id), 'An owned agent is missing queue membership');
    }
    const protectedDevice = (await request('GET', accountPath('devices', PROTECTED_DEVICE), undefined, token)).data;
    check(protectedDevice.owner_id === PROTECTED_USER, 'Protected MicroSIP owner changed');
}
// Registration recovery owns phones, not the operator's current queue roster.
// Keep verify() unchanged for full provisioning and explicit agent operations.
// This path performs only exact account-scoped user/device GETs; it must never
// read/converge queue membership or log any agent in/out.
async function verifyPhones(state, token, apiRequest = request) {
    validateState(state);
    for (const key of ['user_id', 'device_id', 'sip_username']) {
        const values = state.agents.map(agent => agent[key]);
        check(values.every(value => key === 'sip_username' || ID.test(value)) && new Set(values).size === 30,
            'PHONE_OWNERSHIP: missing_or_duplicate_identity');
    }
    for (const target of targets(state).filter(item => ['users', 'devices'].includes(item.collection))) {
        const actual = (await apiRequest('GET', accountPath(target.collection, target.holder[target.key]), undefined, token)).data;
        check(runtimeTargetMatches(actual, target), target.collection === 'users' ?
            'PHONE_OWNERSHIP: owned_user_mismatch' : 'PHONE_OWNERSHIP: owned_device_mismatch');
        // An explicit per-device realm must match the authenticated account;
        // absent realm inherits that account as it does during provisioning.
        if (target.collection === 'devices') check(actual.sip?.realm === undefined || actual.sip.realm === state.realm,
            'PHONE_OWNERSHIP: owned_device_mismatch');
    }
    const protectedDevice = (await apiRequest('GET', accountPath('devices', PROTECTED_DEVICE), undefined, token)).data;
    const protectedUser = (await apiRequest('GET', accountPath('users', PROTECTED_USER), undefined, token)).data;
    check(protectedDevice?.id === PROTECTED_DEVICE && protectedDevice.owner_id === PROTECTED_USER &&
        protectedUser?.id === PROTECTED_USER &&
        [protectedDevice, protectedUser].every(doc => (!doc.pvt_account_id || doc.pvt_account_id === ACCOUNT) &&
            (!doc.account_id || doc.account_id === ACCOUNT)), 'PHONE_OWNERSHIP: protected_microsip_mismatch');
}
async function setAgentStatus(state, token, action) {
    await verify(state, token);
    for (const agent of state.agents)
        await request('POST', `${accountPath('agents', agent.user_id)}/status`, {status: action}, token);
    const deadline = Date.now() + 90000;
    while (Date.now() < deadline) {
        let pending = 0;
        for (const agent of state.agents) {
            const value = (await request('GET', `${accountPath('agents', agent.user_id)}/status`, undefined, token)).data;
            const status = typeof value === 'string' ? value : value?.status;
            if (!(action === 'login' ? ['login', 'ready'] : ['logout', 'logged_out']).includes(status)) pending++;
        }
        if (!pending) { console.log(`PASS exactly 30 owned agents report ${action}`); return; }
        await new Promise(resolve => setTimeout(resolve, 2000));
    }
    fail('Agent status did not converge within 90 seconds');
}
async function main(args) {
    if (args.length === 1 && ['--help', '-h'].includes(args[0])) {
        console.log('Usage: sudo node scripts/provision-live-test-agents.cjs --provision|--verify-only|--verify-phones-only|--agent-status login|logout\nPinned master account only; fixed 30 agents 1002-1031 and queue 2000. --verify-phones-only checks phone ownership, not queue roster or agent status. Credentials: /etc/kazoo/live-test-agents.json (0600). No agent login occurs during provisioning.');
        return;
    }
    const mode = args[0];
    check((args.length === 1 && ['--provision', '--verify-only', '--verify-phones-only'].includes(mode)) ||
        (args.length === 2 && mode === '--agent-status' && ['login', 'logout'].includes(args[1])), 'Invalid arguments; use --help');
    check(process.getuid() === 0, 'Run as root');
    secureParent();
    if (process.env.KAZOO_LIVE_TEST_LOCK_HELD !== 'yes') {
        const lockFile = '/etc/kazoo/live-test-agents.lock';
        process.umask(0o077);
        if (fs.existsSync(lockFile)) privateFile(lockFile);
        else fs.closeSync(fs.openSync(lockFile, fs.constants.O_WRONLY | fs.constants.O_CREAT |
            fs.constants.O_EXCL | fs.constants.O_NOFOLLOW, 0o600));
        try {
            childProcess.execFileSync('flock', ['--exclusive', '--nonblock', lockFile, process.execPath, __filename, ...args],
                {stdio: 'inherit', env: {...process.env, KAZOO_LIVE_TEST_LOCK_HELD: 'yes'}});
        } catch (_) { fail('Provisioning/verification failed or another fixture operation holds the lock'); }
        return;
    }
    const {token, realm} = await authenticate();
    const account = (await request('GET', `accounts/${ACCOUNT}`, undefined, token)).data;
    check(account.id === ACCOUNT && account.realm === realm, 'Master account scope mismatch');
    const state = fs.existsSync(STATE_FILE) ? validateState(JSON.parse(privateFile(STATE_FILE))) :
        (mode === '--provision' ? createState(realm) : fail('No protected fixture state exists'));
    check(state.realm === realm, 'Saved SIP realm does not match the master account');
    if (mode !== '--provision') {
        if (mode === '--verify-phones-only') { await verifyPhones(state, token); console.log('PASS 30 exact owned phones; queue roster and agent statuses are not changed or required'); }
        else if (mode === '--verify-only') { await verify(state, token); console.log('PASS 30 owned agents/devices/routes and exact queue roster'); }
        else await setAgentStatus(state, token, args[1]);
        return;
    }
    const existing = await inventory(token);
    const protectedDevice = existing.devices.find(doc => doc.id === PROTECTED_DEVICE);
    check(protectedDevice?.owner_id === PROTECTED_USER && existing.users.some(doc => doc.id === PROTECTED_USER),
        'Expected existing MicroSIP device and owner were not found');
    collisionCheck(state, existing);
    await rosterCheck(state, token);
    const untouched = unrelatedSnapshots(state, existing);
    saveState(state); // Persist deployment ownership and passwords BEFORE the first create.
    const counts = {created: 0, updated: 0, unchanged: 0};
    for (const target of targets(state)) {
        let id = target.holder[target.key];
        const desired = target.body();
        if (!id) {
            const actual = (await request('PUT', accountPath(target.collection), desired, token)).data;
            check(ID.test(actual.id) && sameMarker(actual, target.mark), 'Create response lost ownership marker');
            target.holder[target.key] = actual.id;
            saveState(state);
            counts.created++;
        } else {
            const actual = (await request('GET', accountPath(target.collection, id), undefined, token)).data;
            check(sameMarker(actual, target.mark), 'Resource ownership changed before convergence');
            if (subset(actual, desired)) counts.unchanged++;
            else {
                const updated = (await request('POST', accountPath(target.collection, id), merged(actual, desired), token)).data;
                check(updated.id === id && sameMarker(updated, target.mark), 'Update changed resource identity');
                counts.updated++;
            }
        }
    }
    await rosterCheck(state, token);
    await request('POST', `${accountPath('queues', state.queue_id)}/roster`, state.agents.map(agent => agent.user_id), token);
    await verify(state, token, true);
    for (const snapshot of untouched) {
        const actual = (await request('GET', accountPath(snapshot.collection, snapshot.id), undefined, token)).data;
        check(hash(actual) === snapshot.digest, `Unrelated ${snapshot.collection} changed during provisioning`);
    }
    console.log(JSON.stringify({status: 'verified', account_id: ACCOUNT, queue_id: state.queue_id,
        queue_extension: '2000', users: 30, devices: 30, agent_callflows: 30, queue_callflows: 1,
        ...counts, unrelated_resources_unchanged: untouched.length, agent_status_changed: false}));
}

if (require.main === module) main(process.argv.slice(2)).catch(error => {
    console.error(`ERROR: ${error instanceof SyntaxError ? 'Invalid protected state JSON' : error.message}`);
    process.exitCode = 1;
});
module.exports = {validateState, collisionCheck, targets, marker, sameMarker, subset, merged, ACCOUNT,
    OWNER, PROTECTED_DEVICE, PROTECTED_USER, runtimeTargetMatches, verifyPhones};
