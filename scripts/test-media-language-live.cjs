'use strict';
// Explicit main-dev-only acceptance. Creates two empty, disabled test accounts;
// never changes an existing company's settings or generates any voice assets.
const fs = require('node:fs'), https = require('node:https'), os = require('node:os');
const crypto = require('node:crypto'), assert = require('node:assert/strict');
const {spawnSync} = require('node:child_process');
const RECEIPT = '/root/kz5-acceptance/media-language-fixture-20260909.json';
const MASTER = 'adecbb84fbe9e06902a76731914d1943';
const LOCALES = ['en-us', 'he-il', 'fr-fr', 'es-es', 'ar-sa'];
const mode = process.argv[2];
let stage = 'arguments', token, state;
function privateText(file) {
    const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
    try {const s = fs.fstatSync(fd); assert(s.isFile() && s.uid === 0 && s.nlink === 1 && (s.mode & 511) === 384 && s.size < 65536);
        return fs.readFileSync(fd, 'utf8');} finally {fs.closeSync(fd);}
}
function save(create = false) {
    const fd = fs.openSync(RECEIPT, create ? 'wx' : fs.constants.O_WRONLY | fs.constants.O_NOFOLLOW, 0o600);
    try {const s = fs.fstatSync(fd); assert(s.isFile() && s.uid === 0 && s.nlink === 1 && (s.mode & 511) === 384);
        const bytes = Buffer.from(JSON.stringify(state, null, 2) + '\n');
        fs.writeFileSync(fd, bytes); fs.ftruncateSync(fd, bytes.length); fs.fsyncSync(fd);
    } finally {fs.closeSync(fd);}
}
function checkpoint(value) {stage = value; state.stage = value; save();}
function rpc(module, fn, args = [], terms = false) {
    const r = spawnSync('sup', ['-n', 'kazoo_apps', '-t', '15', ...(terms ? ['-e'] : []), module, fn, ...args],
        {encoding: 'utf8', timeout: 25000, maxBuffer: 65536});
    assert(!r.error && r.status === 0, 'Native read failed');
    return r.stdout.trim();
}
function binary(module, fn, args = []) {
    const value = rpc(module, fn, args).match(/^<<"([a-z0-9_-]+)">>$/);
    assert(value, 'Unexpected native binary result'); return value[1];
}
function api(method, path, data) {
    const body = data === undefined ? undefined : JSON.stringify({data});
    return new Promise((resolve, reject) => {
        const request = https.request({hostname: '10.1.0.44', servername: 'kz5-dev.talkchief.io',
            method, path: '/v2/' + path, timeout: 30000,
            headers: {Host: 'kz5-dev.talkchief.io', 'Content-Type': 'application/json',
                ...(token ? {'X-Auth-Token': token} : {}), ...(body ? {'Content-Length': Buffer.byteLength(body)} : {})}}, response => {
            let chunks = [], size = 0;
            response.on('data', part => {size += part.length;
                if (size > 1048576) request.destroy(new Error('Oversize response')); else chunks.push(part);});
            response.on('end', () => {
                try {assert(response.statusCode >= 200 && response.statusCode < 300, 'HTTP ' + response.statusCode);
                    const parsed = JSON.parse(Buffer.concat(chunks)); assert.equal(parsed.status, 'success'); resolve(parsed);
                } catch (error) {reject(error);}
            });
            response.on('error', reject);
        });
        request.on('timeout', () => request.destroy(new Error('Request timeout; not retried')));
        request.on('error', reject); request.end(body);
    });
}
async function owned(role) {
    const entry = state[role]; assert(entry && /^[a-f0-9]{32}$/.test(entry.id) && entry.id !== MASTER);
    const response = await api('GET', 'accounts/' + entry.id);
    assert.equal(response.data.id, entry.id); assert.equal(response.data.name, entry.name);
    assert.equal(response.data.realm, entry.realm); return response;
}
async function create(role, parent) {
    const name = 'Kazoo5 Language ' + role + ' ' + state.nonce;
    const realm = 'language-' + role + '-' + state.nonce + '.invalid';
    checkpoint('create_' + role);
    const data = {name, realm, enabled: false, ...(role === 'reseller' ? {language: 'he-il'} : {})};
    const response = await api('PUT', 'accounts/' + parent, data);
    const id = response.data.id; assert(/^[a-f0-9]{32}$/.test(id) && id !== MASTER);
    state[role] = {id, name, realm}; save();
    const current = await owned(role); assert.equal(current.metadata.enabled, false);
    return id;
}
async function assertEmptyChild() {
    for (const resource of ['users', 'devices', 'callflows', 'queues']) {
        const response = await api('GET', 'accounts/' + state.child.id + '/' + resource + '?paginate=false');
        assert(Array.isArray(response.data) && response.data.length === 0, 'Test child is not empty: ' + resource);
    }
}
async function main() {
    assert(process.argv.length === 3 && ['--prepare', '--verify'].includes(mode));
    assert(process.getuid() === 0 && os.hostname() === 'dev-testing');
    const dir = fs.lstatSync('/root/kz5-acceptance'); assert(dir.isDirectory() && !dir.isSymbolicLink() && dir.uid === 0 && !(dir.mode & 0o022));
    stage = 'private_auth';
    const secrets = Object.fromEntries(privateText('/etc/kazoo/installer-secrets.env').split('\n').filter(line => line && !line.startsWith('#'))
        .map(line => {const n = line.indexOf('='); assert(n > 0); return [line.slice(0, n), line.slice(n + 1)];}));
    assert.equal(secrets.KAZOO_MASTER_ADMIN_USER, 'admin'); assert(secrets.KAZOO_MASTER_ADMIN_PASSWORD);
    const auth = await api('PUT', 'user_auth', {account_name: 'KazooMaster', method: 'md5',
        credentials: crypto.createHash('md5').update('admin:' + secrets.KAZOO_MASTER_ADMIN_PASSWORD).digest('hex')});
    assert.equal(auth.data.account_id, MASTER); assert(auth.auth_token); token = auth.auth_token;
    if (mode === '--prepare') {
        state = {kind: 'kazoo5-media-language-acceptance', nonce: crypto.randomBytes(6).toString('hex'),
            phase: 'preparing', created_at: new Date().toISOString(), checks: []}; save(true);
        const parent = await create('reseller', MASTER);
        checkpoint('promote_owned_reseller'); await owned('reseller');
        await api('PUT', 'accounts/' + parent + '/reseller', {});
        assert.equal((await owned('reseller')).metadata.is_reseller, true);
        await create('child', parent);
        checkpoint('native_baseline'); await assertEmptyChild();
        assert.equal(binary('kz_services_reseller', 'get_id', [state.child.id]), parent);
        const child = await owned('child'); assert(!Object.hasOwn(child.data, 'language'));
        state.baseline = {reseller_language: 'he-il', child_language: binary('kz_media_util', 'prompt_language', [state.child.id])};
        state.phase = 'prepared'; save();
        console.log(JSON.stringify({result: 'PREPARED', receipt: RECEIPT, reseller: parent, child: state.child.id,
            baseline: state.baseline, disabled: true, users: 0, devices: 0, calls_created: 0}));
        return;
    }
    state = JSON.parse(privateText(RECEIPT));
    assert.equal(state.kind, 'kazoo5-media-language-acceptance'); assert.equal(state.phase, 'prepared');
    assert(/^[a-f0-9]{12}$/.test(state.nonce));
    for (const role of ['reseller', 'child']) {
        assert.equal(state[role].name, 'Kazoo5 Language ' + role + ' ' + state.nonce);
        assert.equal(state[role].realm, 'language-' + role + '-' + state.nonce + '.invalid');
        assert.equal((await owned(role)).metadata.enabled, false);
    }
    assert.notEqual(state.child.id, state.reseller.id);
    assert.equal(binary('kz_services_reseller', 'get_id', [state.child.id]), state.reseller.id);
    await assertEmptyChild();
    const map = fs.readFileSync('/opt/kz5/applications/acdc/src/acdc_gemini_map.hrl', 'utf8');
    const assets = [...map.matchAll(/\{<<"([^"]+)">>,<<"([^"]+)">>,<<"([^"]+)">>/g)];
    const term = value => '<<"' + value + '">>';
    for (const language of LOCALES) {
        checkpoint('reseller_language_' + language); await owned('reseller');
        const changed = await api('PATCH', 'accounts/' + state.reseller.id, {language});
        assert.equal(changed.data.language, language);
        let actual;
        for (let attempt = 0; attempt < 6; attempt++) {
            actual = binary('kz_media_util', 'prompt_language', [state.child.id]);
            if (actual === language) break;
            await new Promise(resolve => setTimeout(resolve, 500));
        }
        assert.equal(actual, language, 'Reseller update did not reach child language');
        assert(!Object.hasOwn((await owned('child')).data, 'language'));
        for (const prompt of ['acdc-queue-your-current-position-is', 'acdc-callback-offer-6', 'acdc-callback-success']) {
            const asset = assets.find(row => row[1] === language && row[2] === prompt); assert(asset);
            const result = rpc('acdc_gemini_prompts', 'default', [term(prompt), term(language), term(state.child.id), 'absent'], true);
            assert.equal(result.replace(/\s/g, ''), '{gemini,<<"' + asset[3] + '">>}', 'Shared voice resolution mismatch');
        }
        state.checks.push({language, inherited: true, shared_prompts: 3}); save();
    }
    checkpoint('explicit_child_override'); await owned('child');
    await api('PATCH', 'accounts/' + state.child.id, {language: 'es-es'});
    assert.equal(binary('kz_media_util', 'prompt_language', [state.child.id]), 'es-es');
    await owned('reseller'); await api('PATCH', 'accounts/' + state.reseller.id, {language: 'he-il'});
    assert.equal(binary('kz_media_util', 'prompt_language', [state.child.id]), 'es-es');
    await assertEmptyChild();
    for (const role of ['reseller', 'child']) assert.equal((await owned(role)).metadata.enabled, false);
    state.phase = 'verified'; state.verified_at = new Date().toISOString(); save();
    console.log(JSON.stringify({result: 'PASS', receipt: RECEIPT, inherited_locales: LOCALES, shared_prompt_reads: 15,
        explicit_child_override: true, retained_disabled_accounts: [state.reseller.id, state.child.id],
        calls_created: 0, voices_generated: 0, existing_company_language_changes: 0}));
}
main().catch(() => {console.error('Language acceptance stopped at ' + stage + '; inspect protected receipt, do not blindly retry.'); process.exitCode = 1;});
