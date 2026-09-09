'use strict';
// Read-only installed-audio evidence. The Gemini branch is pinned to checked-in
// content, not merely an arbitrary receipt claiming a content-addressed name.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const assert = require('node:assert/strict'), {spawnSync} = require('node:child_process');
const os = require('node:os'), net = require('node:net');
const importer = require('../import-acdc-gemini-voices.cjs');
const root = path.resolve(__dirname, '../..');
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const LOCALES = ['en-us', 'he-il', 'fr-fr', 'es-es', 'ar-sa'];
const inventory = new Map();
function language(value = 'en-us') {
    assert(typeof value === 'string' && LOCALES.includes(value), 'Unsupported explicit reference language'); return value;
}
function assetFor(prompt, locale = 'en-us') {
    language(locale);
    assert(['acdc-callback-success', 'acdc-callback-offer-6', 'acdc-queue-your-current-position-is',
        'acdc-callback-invalid-entry', 'acdc-callback-enter-number', 'acdc-callback-unavailable'].includes(prompt),
        'Unexpected acceptance prompt');
    if (!inventory.has(locale)) inventory.set(locale, importer.loadPlan(path.join(root, 'scripts/assets/acdc-gemini-fixed-20260905'),
        path.join(root, 'scripts/assets/acdc-gemini-completion-20260905'), [locale],
        path.join(root, 'scripts/assets/acdc-gemini-supplemental-20260906')));
    const asset = inventory.get(locale).find(p => p.locale === locale && p.canonical_id === prompt);
    assert(asset, 'Missing checked-in Gemini reference'); return asset;
}
function ulaw(wav) {
    const result = spawnSync('sox', ['-D', '-t', 'wav', '-', '-t', 'raw', '-r', '8000', '-c', '1', '-e', 'mu-law', '-'],
        {input: wav, maxBuffer: 4 * 1024 * 1024});
    assert(!result.error && result.status === 0 && result.stdout.length >= 512, 'Reference conversion failed');
    return result.stdout;
}
function validateReceipt(receipt, referenceHash, locale = 'en-us') {
    language(locale);
    assert(receipt && /^[a-f0-9]{64}$/.test(referenceHash) && receipt.reference_ulaw_sha256 === referenceHash,
        'Reference digest mismatch');
    assert(receipt.language === undefined || receipt.language === locale, 'Reference language mismatch');
    if (receipt.document_id === 'en-us/acdc-callback-success') {
        // Historical diagnostic evidence remains readable, with its original
        // explicit limitation: installed legacy audio, not Gemini or semantics.
        assert(locale === 'en-us' && receipt.attachment_name === 'acdc-callback-success.wav' &&
            /^[a-f0-9]{64}$/.test(receipt.installed_wav_sha256), 'Invalid legacy audio receipt');
        return 'legacy';
    }
    const asset = assetFor('acdc-callback-success', locale);
    assert(receipt.schema_version === 1 && receipt.voice_family === 'gemini-sulafat' &&
        receipt.document_id === asset.id && receipt.attachment_name === asset.attachment &&
        receipt.installed_wav_sha256 === asset.sha256 &&
        receipt.reference_ulaw_sha256 === sha(ulaw(asset.bytes)) &&
        receipt.canonical_prompt_id === asset.canonical_id &&
        /^[1-9][0-9]*-[a-f0-9]{32}$/.test(receipt.revision), 'Unverified Gemini audio identity');
    return 'gemini-sulafat';
}
function protectedFile(file) {
    const stat = fs.lstatSync(file);
    assert(stat.isFile() && !stat.isSymbolicLink() && stat.uid === 0 && (stat.mode & 0o077) === 0 &&
        stat.size > 0 && stat.size < 4 * 1024 * 1024, 'Protected evidence file required');
    return fs.readFileSync(file);
}
function deployment() {
    return Object.fromEntries(protectedFile('/etc/kazoo/deployment.env').toString().split('\n')
        .filter(line => line && !line.startsWith('#')).map(line => {
            const n = line.indexOf('='), key = line.slice(0, n), encoded = line.slice(n + 1);
            assert(n > 0 && /^[A-Z][A-Z0-9_]*$/.test(key));
            const bytes = Buffer.from(encoded, 'base64'); assert(bytes.toString('base64') === encoded);
            const value = bytes.toString(); assert(!/[\r\n]/.test(value)); return [key, value];
        }));
}
function localMediaHost(host, interfaces = os.networkInterfaces()) {
    if (host === 'localhost' || host === '127.0.0.1') return '127.0.0.1';
    assert(typeof host === 'string' && net.isIP(host) === 4 &&
        Object.values(interfaces).some(entries => Array.isArray(entries) &&
            entries.some(entry => entry.family === 'IPv4' && entry.address === host)),
        'Reference source must be an address assigned to this host');
    return host;
}
async function capture(directory, locale = 'en-us') {
    language(locale);
    assert(path.isAbsolute(directory) && fs.realpathSync(directory) === directory &&
        directory.startsWith('/var/log/kazoo-acceptance/gemini-reference.'), 'Unexpected reference directory');
    const stat = fs.lstatSync(directory);
    assert(stat.isDirectory() && !stat.isSymbolicLink() && stat.uid === 0 && (stat.mode & 0o777) === 0o700 &&
        fs.readdirSync(directory).length === 0, 'Empty protected reference directory required');
    const env = deployment(), port = Number(env.KAZOO_COUCHDB_PORT || 5984);
    const host = localMediaHost(env.KAZOO_COUCHDB_HOST);
    assert(Number.isInteger(port) && port > 0 && port < 65536 &&
        env.KAZOO_COUCHDB_USER && !env.KAZOO_COUCHDB_USER.includes(':') && env.KAZOO_COUCHDB_PASSWORD,
    'Local authenticated media reference source required');
    const asset = assetFor('acdc-callback-success', locale);
    const url = 'http://' + host + ':' + port + '/system_media/' + encodeURIComponent(asset.id) + '?attachments=true';
    const headers = {accept: 'application/json', authorization: 'Basic ' + Buffer.from(env.KAZOO_COUCHDB_USER + ':' + env.KAZOO_COUCHDB_PASSWORD).toString('base64')};
    const get = async () => {
        const response = await fetch(url, {headers, redirect: 'error', signal: AbortSignal.timeout(15000)});
        assert(response.status === 200, 'Installed reference read failed');
        const bytes = Buffer.from(await response.arrayBuffer()); assert(bytes.length < 4 * 1024 * 1024);
        const doc = JSON.parse(bytes.toString()); importer.verifyDocument(asset, doc); return doc;
    };
    const doc = await get(), raw = ulaw(Buffer.from(doc._attachments[asset.attachment].data, 'base64'));
    assert((await get())._rev === doc._rev, 'Installed reference changed during capture');
    const receipt = {schema_version: 1, voice_family: 'gemini-sulafat',
        ...(locale === 'en-us' ? {} : {language: locale}),
        source: 'local CouchDB system_media attachment, authenticated read only',
        document_id: asset.id, attachment_name: asset.attachment, revision: doc._rev,
        canonical_prompt_id: asset.canonical_id, installed_wav_sha256: asset.sha256,
        reference_ulaw_sha256: sha(raw), duration_seconds: raw.length / 8000,
        claim_limit: 'Exact checked-in and installed Gemini audio delivery only; not independent transcription or native-speaker approval.'};
    validateReceipt(receipt, sha(raw), locale);
    fs.writeFileSync(path.join(directory, 'acdc-callback-success.ulaw'), raw, {flag: 'wx', mode: 0o600});
    fs.writeFileSync(path.join(directory, 'reference-receipt.json'), JSON.stringify(receipt, null, 2) + '\n', {flag: 'wx', mode: 0o600});
    return {result: 'PASS', document_id: asset.id, duration_seconds: raw.length / 8000, database_writes: 0};
}
module.exports = {LOCALES, language, assetFor, ulaw, validateReceipt, capture, localMediaHost};
if (require.main === module) {
    (async () => {
        const [action, target, locale = 'en-us'] = process.argv.slice(2); assert([4,5].includes(process.argv.length));
        language(locale);
        if (action === 'capture') console.log(JSON.stringify(await capture(target, locale)));
        else {
            assert(action === 'verify');
            const receipt = JSON.parse(protectedFile(path.join(path.dirname(target), 'reference-receipt.json')));
            console.log(JSON.stringify({voice_family: validateReceipt(receipt, sha(protectedFile(target)), locale), language: locale}));
        }
    })().catch(() => {console.error('Installed callback reference verification failed safely.'); process.exitCode = 1;});
}
