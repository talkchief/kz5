#!/usr/bin/env node
'use strict';
// Memory-only database/MVCC tests. No installed media or account is changed.
const assert = require('node:assert/strict'), crypto = require('node:crypto');
const http = require('node:http'), {EventEmitter} = require('node:events');
const {catalog} = require('./acdc-language-catalog.cjs');
const importer = require('./import-acdc-language-packs.cjs');
const revision = n => n + '-' + 'a'.repeat(32);
const digest = data => 'md5-' + crypto.createHash('md5').update(data).digest('base64');
const copy = value => JSON.parse(JSON.stringify(value));
function manifest(locale = 'en-us') {
    return {schema_version: 1, owner: 'kazoo5-acdc-language-generator', locale, complete: true,
        engine: 'espeak-ng', engine_version: '1.52.0', source_commit: '4870adfa25b1a32b4361592f1be8a40337c58d6c',
        runtime_ready: false, native_speaker_review: false,
        prompts: catalog(locale).prompts.map(p => ({...p, synthesis_text: p.synthesis_text || p.text, sha256: 'b'.repeat(64)}))};
}
const pack = importer.validateManifest(manifest(), 'en-us');
const ids = pack.prompts.map(p => pack.locale + '/' + p.id);
function document(id, recording = 'existing custom recording') {
    return {_id: id, _rev: revision(1), language: id.slice(0, 5), prompt_id: id.slice(6), pvt_type: 'media',
        name: 'Keep my custom metadata', _attachments: {'custom.wav': {content_type: 'audio/wav', length: recording.length, digest: digest(recording)}}};
}
function fixture(options = {}, packs = [pack]) {
    const ids = packs.flatMap(p => p.prompts.map(prompt => p.locale + '/' + prompt.id));
    const documents = new Map(), writes = [], requests = [];
    let sequence = 0, reads = 0, metadataReads = 0;
    const bumpSequence = () => sequence++;
    for (const id of ids) documents.set(id, document(id));
    const response = keys => ({rows: keys.map(key => documents.has(key)
        ? {key, id: key, value: {rev: documents.get(key)._rev}, doc: copy(documents.get(key))} : {key, error: 'not_found'})});
    const client = async (method, resource, body) => {
        requests.push({method, resource});
        if (method === 'GET') {
            assert.equal(resource, null); assert.equal(body, undefined);
            metadataReads++;
            if (options.unstable && metadataReads % 2 === 0) bumpSequence();
            const update_seq = options.sequencePrefix ? options.sequencePrefix + sequence : sequence;
            return {status: 200, body: {db_name: 'system_media', update_seq}};
        }
        if (method === 'POST') {
            reads++;
            options.onRead?.({documents, keys: body.keys, reads, metadataReads, bumpSequence});
            return {status: options.readStatus || 200, body: response(body.keys)};
        }
        assert.equal(method, 'PUT'); assert(!resource.includes('?')); const id = decodeURIComponent(resource);
        assert(ids.includes(id), 'Cross-scope media write'); writes.push(copy(body));
        if (options.conflict) {
            if (options.conflict !== 'forever') {
                documents.set(id, document(id, 'a racing custom recording')); bumpSequence();
            }
            return {status: 409, body: {error: 'conflict'}};
        }
        if (options.writeStatus) return {status: options.writeStatus, body: {error: 'unavailable'}};
        const current = documents.get(id);
        assert.equal(body._rev, current?._rev, 'Unconditional overwrite');
        const next = copy(body); next._rev = revision(current ? 2 : 1);
        for (const value of Object.values(next._attachments)) {
            const bytes = Buffer.from(value.data, 'base64');
            delete value.data; value.length = bytes.length; value.digest = digest(bytes);
        }
        documents.set(id, next);
        bumpSequence();
        return {status: 201, body: {ok: true, id: options.wrongAck ? 'another-document' : id, rev: next._rev}};
    };
    return {documents, writes, requests, response, client};
}

async function run() {
    for (const mutation of [{complete: false}, {runtime_ready: true}, {native_speaker_review: true},
        {source_commit: 'c'.repeat(40)}, {locale: 'ar-sa'}, {prompts: manifest().prompts.slice(1)}]) {
        assert.throws(() => importer.validateManifest({...manifest(), ...mutation}, 'en-us'));
    }
    const duplicate = manifest(); duplicate.prompts[1] = duplicate.prompts[0];
    assert.throws(() => importer.validateManifest(duplicate, 'en-us'));
    assert.equal(importer.validateManifest(manifest('ar-sa'), 'ar-sa').prompts.length, 3028);
    assert.equal(importer.validateManifest(manifest('he-il'), 'he-il').prompts.length, 3028);
    {
        const f = fixture(), result = await importer.installPack(pack, f.client, true);
        assert.equal(f.writes.length, 0); assert.equal(result.preserved, 29);
        assert.equal(result.proof.ready, false); assert.equal(result.proof.media_verified, true);
        assert.notEqual(result.proof.installed_media_sha256, result.proof.source_catalog_sha256);
        const original = result.proof.installed_media_sha256;
        f.documents.set(ids[0], document(ids[0], 'different custom audio'));
        const changed = await importer.installPack(pack, f.client, false);
        assert.notEqual(changed.proof.installed_media_sha256, original);
    }
    {
        const f = fixture(); f.documents.delete(ids[0]);
        const result = await importer.installPack(pack, f.client, true, () => Buffer.from('synthetic test audio'));
        assert.equal(result.imported, 1); assert.equal(f.writes.length, 1); assert(!('_rev' in f.writes[0]));
        assert.equal(f.writes[0].language, 'en-us'); assert.equal(f.writes[0].pvt_type, 'media');
        assert.equal(Object.keys(f.writes[0]._attachments).length, 1);
    }
    {
        const f = fixture(); delete f.documents.get(ids[0])._attachments;
        await importer.installPack(pack, f.client, true, () => Buffer.from('synthetic test audio'));
        assert.equal(f.writes[0]._rev, revision(1)); assert.equal(f.writes[0].name, 'Keep my custom metadata');
    }
    {
        const f = fixture({conflict: true}); f.documents.delete(ids[0]);
        const result = await importer.installPack(pack, f.client, true, () => Buffer.from('synthetic test audio'));
        assert.equal(f.writes.length, 1, 'A concurrent recording must not be overwritten on retry');
        assert.equal(result.imported, 0); assert.equal(f.documents.get(ids[0])._attachments['custom.wav'].digest, digest('a racing custom recording'));
    }
    for (const options of [{conflict: 'forever'}, {writeStatus: 500}, {wrongAck: true}, {readStatus: 503}]) {
        const f = fixture(options); f.documents.delete(ids[0]);
        await assert.rejects(importer.installPack(pack, f.client, true, () => Buffer.from('synthetic test audio')));
        assert(f.writes.length <= 3, 'Unbounded import retry');
    }
    {
        const f = fixture(); f.documents.delete(ids[0]);
        await assert.rejects(importer.installPack(pack, f.client, false)); assert.equal(f.writes.length, 0);
    }
    for (const mutation of [row => { row.key = 'foreign/document'; }, row => { row.id = 'foreign/document'; },
        row => { row.value.deleted = true; }, row => { row.doc.pvt_deleted = true; }, row => { row.doc.pvt_deleted = 'true'; },
        row => { row.doc._deleted = 'false'; }, row => { row.doc.language = 'fr-fr'; },
        row => { row.doc._id = ids[1]; }, row => { row.doc.pvt_type = 'user'; }, row => { row.doc._rev = revision(2); },
        row => { row.doc._conflicts = [revision(2)]; }, row => { row.doc._attachments['custom.wav'].length = 0; },
        row => { row.doc._attachments['custom.wav'].digest = 'missing'; },
        row => { row.doc._attachments['custom.wav'].content_type = 'text/plain'; }]) {
        const f = fixture(), response = f.response([ids[0]]); mutation(response.rows[0]);
        assert.throws(() => importer.inspectRows('en-us', [ids[0]], response));
    }
    {
        const f = fixture(), response = f.response(ids);
        response.rows[1] = response.rows[0]; assert.throws(() => importer.inspectRows('en-us', ids, response));
        assert.throws(() => importer.inspectRows('en-us', ids, {rows: []}));
        assert.throws(() => importer.couchClient({KAZOO_COUCHDB_HOST: 'user:password@example.invalid'}));
    }
    {
        // Regression: first batch disappears while the last AR batch is read.
        // The old importer published media_verified=true from stale batches.
        const arabic = importer.validateManifest(manifest('ar-sa'), 'ar-sa');
        const first = arabic.locale + '/' + arabic.prompts[0].id;
        const f = fixture({onRead({documents, reads, bumpSequence}) {
            if (reads === 61) { documents.delete(first); bumpSequence(); }
        }}, [arabic]);
        await assert.rejects(importer.installPack(arabic, f.client, false), /remains missing/);
        assert.equal(f.writes.length, 0);
        assert.equal(f.requests.filter(r => r.method === 'GET').length, 4, 'Changed inventory was not retried coherently');
    }
    {
        // A concurrent valid replacement is preserved and included in the
        // final proof, not rejected merely because the DB changed once.
        const arabic = importer.validateManifest(manifest('ar-sa'), 'ar-sa');
        const first = arabic.locale + '/' + arabic.prompts[0].id;
        const f = fixture({onRead({documents, reads, bumpSequence}) {
            if (reads === 61) { documents.set(first, document(first, 'new custom recording')); bumpSequence(); }
        }}, [arabic]);
        const result = await importer.installPack(arabic, f.client, false);
        const stable = await importer.verifyInstalledPacks([arabic], f.client);
        assert.equal(result.proof.installed_media_sha256, stable.languages['ar-sa'].installed_media_sha256);
        assert.equal(f.writes.length, 0);
    }
    {
        const f = fixture({unstable: true});
        await assert.rejects(importer.installPack(pack, f.client, false), /every bounded verification attempt/);
        assert.equal(f.requests.filter(r => r.method === 'GET').length, 6, 'Final verification exceeded three attempts');
        assert.equal(f.writes.length, 0);
    }
    {
        const f = fixture({sequencePrefix: '42-opaque-cluster-token-'});
        const result = await importer.verifyInstalledPacks([pack], f.client);
        assert.equal(result.database_update_seq, '42-opaque-cluster-token-0');
    }
    for (const body of [{db_name: 'another_database', update_seq: 1}, {db_name: 'system_media'},
        {db_name: 'system_media', update_seq: null}, {db_name: 'system_media', update_seq: -1},
        {db_name: 'system_media', update_seq: {}}, {db_name: 'system_media', update_seq: ''}]) {
        await assert.rejects(importer.databaseSequence(async () => ({status: 200, body})));
    }
    {
        // Exercise the real HTTP adapter without a socket or supplied secret.
        const originalRequest = http.request, captured = [];
        http.request = (options, callback) => {
            const request = new EventEmitter();
            request.setTimeout = () => request;
            request.end = payload => {
                captured.push({options, payload});
                queueMicrotask(() => {
                    const response = new EventEmitter(); response.statusCode = 200;
                    callback(response);
                    response.emit('data', Buffer.from(JSON.stringify({db_name: 'system_media', update_seq: '10-cluster'})));
                    response.emit('end');
                });
            };
            return request;
        };
        try {
            const client = importer.couchClient({KAZOO_COUCHDB_HOST: 'database.example.invalid',
                KAZOO_COUCHDB_PORT: '15984', KAZOO_COUCHDB_USER: 'fixture-user', KAZOO_COUCHDB_PASSWORD: 'fixture-only'});
            assert.equal(await importer.databaseSequence(client), '10-cluster');
            assert.equal(captured[0].options.path, '/system_media');
            assert.equal(captured[0].options.host, 'database.example.invalid');
            assert.equal(captured[0].options.port, 15984);
            assert.equal(captured[0].payload, undefined);
            assert.equal(captured[0].options.headers['Content-Length'], undefined);
            await client('POST', '_all_docs?include_docs=true&conflicts=true', {keys: [ids[0]]});
            assert.equal(captured[1].options.path, '/system_media/_all_docs?include_docs=true&conflicts=true');
            assert.deepEqual(JSON.parse(captured[1].payload), {keys: [ids[0]]});
            await assert.rejects(client('GET', '_all_docs', undefined));
            assert.equal(captured.length, 2, 'Invalid metadata request reached the transport');
        } finally { http.request = originalRequest; }
    }
    {
        // Main uses installPacks, whose combined final pass must not reuse the
        // English proof obtained before installing/verifying Spanish.
        const spanish = importer.validateManifest(manifest('es-es'), 'es-es');
        const f = fixture({onRead({documents, keys, metadataReads, bumpSequence}) {
            if (metadataReads === 3 && keys[0].startsWith('es-es/')) {
                documents.delete(ids[0]); bumpSequence();
            }
        }}, [pack, spanish]);
        await assert.rejects(importer.installPacks([pack, spanish], f.client, false), /remains missing/);
        assert.equal(f.writes.length, 0);
    }
    {
        // Also catch an English deletion during the final cross-locale pass.
        const spanish = importer.validateManifest(manifest('es-es'), 'es-es');
        const f = fixture({onRead({documents, keys, metadataReads, bumpSequence}) {
            if (metadataReads === 5 && keys[0].startsWith('es-es/')) {
                documents.delete(ids[0]); bumpSequence();
            }
        }}, [pack, spanish]);
        await assert.rejects(importer.installPacks([pack, spanish], f.client, false), /remains missing/);
        assert.equal(f.writes.length, 0);
        assert.equal(f.requests.filter(r => r.method === 'GET').length, 8);
    }
    {
        const selected = ['en-us', 'ar-sa', 'he-il', 'es-es', 'fr-fr']
            .map(locale => importer.validateManifest(manifest(locale), locale));
        const f = fixture({}, selected), result = await importer.installPacks(selected, f.client, false);
        assert.equal(Object.keys(result.languages).length, 5);
        assert.equal(result.summaries.reduce((total, item) => total + item.preserved, 0), 6143);
        assert.equal(result.database_update_seq, 0);
        assert.equal(f.writes.length, 0);
        assert.equal(f.requests.filter(r => r.method === 'GET').length, 12, 'Missing combined final verification');
    }
    console.log('PASS language media import: complete pinned catalog, 29/3028 prompts, zero-write preservation, atomic metadata/audio, MVCC race, bounded failures, exact identities, coherent full-pack and five-locale installed digest proof');
}
run().catch(error => { console.error(error); process.exitCode = 1; });
