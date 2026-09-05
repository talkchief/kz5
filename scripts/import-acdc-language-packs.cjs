#!/usr/bin/env node
'use strict';
// SPDX-License-Identifier: MPL-2.0
// Media-only installation. Never activates backend code, changes an account,
// publishes UI readiness, or overwrites an existing recording.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const http = require('node:http'), https = require('node:https'), assert = require('node:assert/strict');
const {catalog, locales} = require('./acdc-language-catalog.cjs');
const {wave} = require('./generate-acdc-language-prompts.cjs');
const PIN = '4870adfa25b1a32b4361592f1be8a40337c58d6c';
const sha = value => crypto.createHash('sha256').update(value).digest('hex');
const plain = value => value !== null && typeof value === 'object' && !Array.isArray(value)
    && Object.getPrototypeOf(value) === Object.prototype;
const revision = value => typeof value === 'string' && /^[1-9][0-9]*-[a-f0-9]{32}$/.test(value);

function validateManifest(manifest, locale) {
    const source = catalog(locale), expected = new Map(source.prompts.map(prompt => [prompt.id, prompt]));
    assert(plain(manifest) && manifest.schema_version === 1 && manifest.owner === 'kazoo5-acdc-language-generator'
        && manifest.locale === locale && manifest.complete === true, 'Missing or incomplete generated language manifest');
    assert(manifest.engine === 'espeak-ng' && manifest.engine_version === '1.52.0' && manifest.source_commit === PIN,
        'Unrecognized speech source provenance');
    assert(manifest.runtime_ready === false && manifest.native_speaker_review === false,
        'A generator must not assert runtime or native-speaker approval');
    assert(Array.isArray(manifest.prompts) && manifest.prompts.length === expected.size, 'Incomplete source prompt set');
    const seen = new Set();
    for (const prompt of manifest.prompts) {
        const wanted = expected.get(prompt.id);
        assert(wanted && !seen.has(prompt.id) && prompt.kind === wanted.kind && prompt.text === wanted.text
            && prompt.synthesis_text === (wanted.synthesis_text || wanted.text) && /^[a-f0-9]{64}$/.test(prompt.sha256 || ''),
        'Generated prompt differs from the reviewed catalog');
        seen.add(prompt.id);
    }
    return {locale, source, prompts: manifest.prompts, source_catalog_sha256: sha(JSON.stringify(source))};
}

function loadPack(root, locale) {
    assert(path.isAbsolute(root) && fs.realpathSync(root) === path.resolve(root), 'Use a non-symlinked absolute pack directory');
    const directory = path.join(root, locale), manifestFile = path.join(directory, 'manifest.json');
    assert(fs.lstatSync(directory).isDirectory() && !fs.lstatSync(directory).isSymbolicLink(), 'Invalid locale directory');
    const stat = fs.lstatSync(manifestFile);
    assert(stat.isFile() && !stat.isSymbolicLink() && stat.size <= 8 * 1024 * 1024, 'Invalid source manifest file');
    const pack = validateManifest(JSON.parse(fs.readFileSync(manifestFile, 'utf8')), locale);
    pack.directory = directory;
    // Complete all local validation before the first database write.
    for (const prompt of pack.prompts) readWave(pack, prompt);
    return pack;
}

function readWave(pack, prompt) {
    const file = path.join(pack.directory, prompt.id + '.wav'), stat = fs.lstatSync(file);
    assert(stat.isFile() && !stat.isSymbolicLink() && stat.size <= 512 * 1024, 'Invalid source WAV file');
    const bytes = fs.readFileSync(file);
    assert.equal(sha(bytes), prompt.sha256, 'Source WAV no longer matches its generation manifest');
    wave(bytes);
    return bytes;
}

function attachmentProof(doc) {
    assert(plain(doc._attachments), 'Invalid attachment inventory');
    return Object.keys(doc._attachments).sort().map(name => {
        const item = doc._attachments[name];
        assert(name.length > 0 && name.length <= 255 && !/[\u0000-\u001f]/.test(name) && plain(item)
            && Number.isSafeInteger(item.length) && item.length > 0
            && typeof item.content_type === 'string' && /^audio\/[A-Za-z0-9.+-]+$/.test(item.content_type)
            && typeof item.digest === 'string' && /^md5-[A-Za-z0-9+/]{22}==$/.test(item.digest),
        'An existing recording has unusable attachment metadata; refusing replacement');
        return [name, item.digest, item.length, item.content_type];
    });
}

function inspectRows(locale, ids, response) {
    assert(plain(response) && Array.isArray(response.rows) && response.rows.length === ids.length, 'Incomplete CouchDB prompt response');
    const wanted = new Set(ids), rows = new Map();
    assert.equal(wanted.size, ids.length, 'Duplicate requested media identity');
    for (const row of response.rows) {
        assert(plain(row) && wanted.has(row.key) && !rows.has(row.key), 'Unexpected or duplicate media response identity');
        if (row.error !== undefined) {
            assert(row.error === 'not_found' && row.doc === undefined && row.value === undefined, 'Unverified missing media document');
            rows.set(row.key, {missing: true});
            continue;
        }
        assert(row.id === row.key && plain(row.value) && revision(row.value.rev) && row.value.deleted !== true,
            'Invalid or deleted media identity; explicit restoration is required');
        const doc = row.doc, prompt = row.key.slice(locale.length + 1);
        assert(plain(doc) && doc._id === row.key && doc._rev === row.value.rev
            && [undefined, false].includes(doc._deleted) && [undefined, false].includes(doc.pvt_deleted)
            && doc.pvt_type === 'media' && doc.language === locale && doc.prompt_id === prompt
            && (!doc._conflicts || (Array.isArray(doc._conflicts) && doc._conflicts.length === 0)),
        'Existing document has incompatible language, type, identity, or conflicts');
        const attachments = doc._attachments === undefined ? [] : attachmentProof(doc);
        rows.set(row.key, {missing: attachments.length === 0, doc, attachments});
    }
    return rows;
}

function mediaDocument(pack, prompt, old, bytes, now = Date.now()) {
    const id = pack.locale + '/' + prompt.id, timestamp = Math.floor(now / 1000) + 62167219200;
    assert(old.missing, 'Refusing to replace installed audio');
    const base = old.doc ? {...old.doc} : {_id: id, name: id, prompt_id: prompt.id,
        language: pack.locale, pvt_type: 'media', pvt_account_db: 'system_media', pvt_vsn: '1', pvt_created: timestamp};
    return {...base, content_type: 'audio/wav', content_length: bytes.length, streamable: true,
        source_type: 'kazoo5_acdc_language_installer', pvt_modified: timestamp,
        _attachments: {[prompt.id + '.wav']: {content_type: 'audio/wav', data: bytes.toString('base64')}}};
}

function mediaProof(pack, rows) {
    const ordered = pack.prompts.map(prompt => pack.locale + '/' + prompt.id).sort();
    const installed = ordered.map(id => {
        const row = rows.get(id);
        assert(row && !row.missing && row.attachments.length > 0, 'Required localized media remains missing');
        return [id, row.attachments];
    });
    return {media_verified: true, ready: false, position: false, wait_time: false, callback: false,
        native_speaker_review: false, numbers: ['ar-sa', 'he-il'].includes(pack.locale) ? 'prerecorded' : 'native_say',
        number_range: [0, 999999999], required_prompt_ids: pack.source.prompts.filter(p => p.kind === 'fixed').map(p => p.id),
        numeric_prompt_count: pack.source.prompts.filter(p => p.kind !== 'fixed').length,
        source_catalog_sha256: pack.source_catalog_sha256, installed_media_sha256: sha(JSON.stringify(installed))};
}

async function readRows(client, locale, ids) {
    const result = await client('POST', '_all_docs?include_docs=true&conflicts=true', {keys: ids});
    assert.equal(result.status, 200, 'CouchDB media lookup failed');
    return inspectRows(locale, ids, result.body);
}

async function databaseSequence(client) {
    const result = await client('GET', null);
    assert(result.status === 200 && plain(result.body) && result.body.db_name === 'system_media',
        'Could not verify the media database identity');
    const sequence = result.body.update_seq;
    // Cluster sequences are opaque strings; older single-node CouchDB uses
    // integers. Do not parse a cluster sequence into a lossy numeric prefix.
    assert((typeof sequence === 'string' && sequence.length > 0 && sequence.length <= 16384)
        || (Number.isSafeInteger(sequence) && sequence >= 0), 'Invalid media database update sequence');
    return sequence;
}

async function verifyInstalledPacks(packs, client) {
    assert(Array.isArray(packs) && packs.length > 0
        && new Set(packs.map(pack => pack.locale)).size === packs.length, 'Invalid final language inventory');
    for (let attempt = 0; attempt < 3; attempt++) {
        const before = await databaseSequence(client), inventories = new Map();
        // Re-read the entire requested inventory, not just the last batch or
        // locale. An earlier recording can change while later ones import.
        for (const pack of packs) {
            const installed = new Map();
            for (let start = 0; start < pack.prompts.length; start += 100) {
                const ids = pack.prompts.slice(start, start + 100).map(p => pack.locale + '/' + p.id);
                for (const [id, row] of await readRows(client, pack.locale, ids)) installed.set(id, row);
            }
            inventories.set(pack.locale, installed);
        }
        const after = await databaseSequence(client);
        if (before !== after) continue;
        const languages = {};
        for (const pack of packs) languages[pack.locale] = mediaProof(pack, inventories.get(pack.locale));
        return {languages, database_update_seq: after};
    }
    throw new Error('Media database changed during every bounded verification attempt');
}

async function installPack(pack, client, write, read = readWave) {
    let imported = 0, preserved = 0;
    for (let start = 0; start < pack.prompts.length; start += 100) {
        const batch = pack.prompts.slice(start, start + 100), ids = batch.map(p => pack.locale + '/' + p.id);
        const rows = await readRows(client, pack.locale, ids);
        for (const prompt of batch) {
            const id = pack.locale + '/' + prompt.id; let row = rows.get(id);
            if (!row.missing) { preserved++; continue; }
            assert(write, 'Required localized media is not installed');
            const bytes = read(pack, prompt);
            for (let attempt = 0; attempt < 3 && row.missing; attempt++) {
                // One MVCC write includes metadata and attachment: no unsafe
                // metadata upsert followed by a separately retried overwrite.
                const result = await client('PUT', encodeURIComponent(id), mediaDocument(pack, prompt, row, bytes));
                assert([201, 202, 409].includes(result.status), 'CouchDB media write failed');
                if (result.status !== 409) {
                    assert(result.body?.ok === true && result.body.id === id && revision(result.body.rev), 'Uncorrelated media write acknowledgement');
                    imported++;
                }
                row = (await readRows(client, pack.locale, [id])).get(id);
                // A concurrent recording wins. Never retry against its new revision.
            }
            assert(!row.missing, 'Media write could not be verified after bounded retries');
        }
    }
    const verified = await verifyInstalledPacks([pack], client);
    return {proof: verified.languages[pack.locale], imported, preserved};
}

async function installPacks(packs, client, write, read = readWave) {
    const summaries = [];
    for (const pack of packs) {
        const result = await installPack(pack, client, write, read);
        summaries.push({locale: pack.locale, count: pack.prompts.length,
            imported: result.imported, preserved: result.preserved});
    }
    // Per-locale success is not a combined five-locale proof: the first pack
    // may have changed during a later import. Only this final coherent pass
    // supplies the CLI receipt's language hashes.
    return {...await verifyInstalledPacks(packs, client), summaries};
}

function couchClient(env) {
    const host = env.KAZOO_COUCHDB_HOST, port = env.KAZOO_COUCHDB_PORT || '5984';
    assert(typeof host === 'string' && /^[A-Za-z0-9.-]+$/.test(host) && /^\d{1,5}$/.test(port)
        && Number(port) > 0 && Number(port) <= 65535, 'Explicit configured CouchDB host/port required');
    assert(env.KAZOO_COUCHDB_USER && env.KAZOO_COUCHDB_PASSWORD && !env.KAZOO_COUCHDB_USER.includes(':'), 'CouchDB credentials required');
    const tls = env.KAZOO_COUCHDB_TLS === 'true', transport = tls ? https : http;
    const authorization = 'Basic ' + Buffer.from(env.KAZOO_COUCHDB_USER + ':' + env.KAZOO_COUCHDB_PASSWORD).toString('base64');
    return (method, resource, body) => new Promise((resolve, reject) => {
        assert((method === 'GET' && resource === null && body === undefined)
            || (['POST', 'PUT'].includes(method) && typeof resource === 'string' && body !== undefined),
        'Invalid media database request');
        const payload = body === undefined ? undefined : Buffer.from(JSON.stringify(body));
        const headers = {authorization};
        if (payload) Object.assign(headers, {'Content-Type': 'application/json', 'Content-Length': payload.length});
        const request = transport.request({host, port: Number(port), method,
            path: resource === null ? '/system_media' : '/system_media/' + resource, headers}, response => {
            const parts = []; let size = 0;
            response.on('data', chunk => { size += chunk.length; if (size > 16 * 1024 * 1024) request.destroy(new Error('Oversized media response')); else parts.push(chunk); });
            response.on('error', () => reject(new Error('CouchDB response transport failed')));
            response.on('end', () => {
                try { resolve({status: response.statusCode, body: JSON.parse(Buffer.concat(parts).toString('utf8'))}); }
                catch { reject(new Error('CouchDB response was not JSON')); }
            });
        });
        request.setTimeout(30000, () => request.destroy(new Error('CouchDB request timed out')));
        request.on('error', () => reject(new Error('CouchDB media transport failed')));
        request.end(payload);
    });
}

async function main(args) {
    assert(['--verify-only', '--import'].includes(args[0]) && args[1] === '--pack-dir' && args[2]
        && (args.length === 3 || (args.length === 5 && args[3] === '--locale' && locales.includes(args[4]))),
    'Usage: import-acdc-language-packs.cjs --verify-only|--import --pack-dir ABSOLUTE [--locale LOCALE]');
    const packs = (args[4] ? [args[4]] : locales).map(locale => loadPack(args[2], locale));
    const result = await installPacks(packs, couchClient(process.env), args[0] === '--import');
    for (const summary of result.summaries)
        console.error(summary.locale + ': verified ' + summary.count + ' media documents; imported=' + summary.imported + '; preserved=' + summary.preserved);
    console.log(JSON.stringify({schema_version: 1, owner: 'kazoo5-acdc-media-importer', generated_at: new Date().toISOString(),
        runtime_ready: false, database_update_seq: result.database_update_seq, languages: result.languages}, null, 2));
}
module.exports = {validateManifest, inspectRows, mediaDocument, mediaProof, databaseSequence,
    verifyInstalledPacks, installPack, installPacks, couchClient, loadPack, main};
if (require.main === module) main(process.argv.slice(2)).catch(() => {
    // No raw network response or supplied secret is written to the terminal.
    console.error('ACDC language media verification/import failed; no runtime capability was published');
    process.exitCode = 1;
});
