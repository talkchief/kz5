#!/usr/bin/env node
'use strict';
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const assert = require('node:assert/strict');
const pack = require('./call-forward-confirmation-pack.cjs');
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cfwd-pack-test.'));
let requests = 0, writes = 0;
async function run() {
    const pcm = Buffer.alloc(3 * 24000 * 2);
    for (let i = 0; i < pcm.length / 2; i++) pcm.writeInt16LE(Math.round(4000 * Math.sin(i * Math.PI / 30)), i * 2);
    const directory = path.join(root, 'generated');
    await pack.generate(directory, '/not-a-key', {deps: {readKey: () => 'fixture-only', output: () => {}, request: async () => {
        requests++; return {candidates: [{finishReason: 'STOP', content: {parts: [{inlineData: {mimeType: 'audio/L16;codec=pcm;rate=24000', data: pcm.toString('base64')}}]}}]};
    }}});
    assert.equal(requests, 5);
    await pack.generate(directory, '/not-a-key', {resume: true, deps: {readKey: () => {throw Error('must not read credentials');}}});
    const plan = pack.loadPlan(directory), db = new Map();
    const client = async (method, uri, body) => {
        if (method === 'POST') {
            assert.equal(uri, '_all_docs?include_docs=true&attachments=true&conflicts=true');
            return {status: 200, body: {rows: body.keys.map(id => db.has(id)
                ? {key: id, id, value: {rev: db.get(id)._rev}, doc: structuredClone(db.get(id))}
                : {key: id, error: 'not_found'})}};
        }
        const id = decodeURIComponent(uri.split('?')[0]);
        assert.equal(method, 'PUT'); assert(!db.has(id)); writes++;
        const a = plan.find(p => p.id === id), doc = structuredClone(body);
        doc._rev = '1-' + 'a'.repeat(32); doc._attachments[a.attachment].digest = a.md5;
        db.set(id, doc); return {status: 201, body: {ok: true, id, rev: doc._rev}};
    };
    await assert.rejects(pack.install(plan, client), /not installed/);
    assert.equal(writes, 0);
    assert.equal((await pack.install(plan, client, true)).created, 5);
    assert.equal((await pack.install(plan, client, true)).created, 0);
    assert.equal((await pack.install(plan, client)).verified, 5);
    assert.equal(writes, 5);
    const damaged = db.get(plan[2].id); damaged.source_type = 'customer-owned';
    db.delete(plan[0].id);
    await assert.rejects(pack.install(plan, client, true)); assert.equal(writes, 5);
    await assert.rejects(pack.install(plan, async () => ({status: 200, body: {rows: [{key: plan[0].id, id: plan[0].id,
        value: {deleted: true, rev: '1-' + 'a'.repeat(32)}}]}}), true));
    const file = path.join(directory, pack.readManifest(directory).attempts[0].telephony.file);
    const bytes = fs.readFileSync(file); bytes[bytes.length - 1] ^= 1; fs.writeFileSync(file, bytes);
    assert.throws(() => pack.loadPlan(directory));
    const failedDirectory = path.join(root, 'failed');
    await assert.rejects(pack.generate(failedDirectory, '/not-a-key', {deps: {readKey: () => 'fixture-only', output: () => {}, request: async () => {throw Error('fixture');}}}));
    assert.equal(pack.readManifest(failedDirectory).requests_reserved, 5);
    await assert.rejects(pack.generate(failedDirectory, '/not-a-key', {resume: true, deps: {readKey: () => {throw Error('no automatic retry');}}}));
    assert.equal(pack.readManifest(failedDirectory).requests_reserved, 5);
    console.log('PASS confirmation pack: bounded authoring/resume, five locales, create-only import/readback, preflight conflicts, tombstones and WAV tamper rejection. No provider calls.');
}
run().catch(error => {console.error(error); process.exitCode = 1;}).finally(() => fs.rmSync(root, {recursive: true, force: true}));
