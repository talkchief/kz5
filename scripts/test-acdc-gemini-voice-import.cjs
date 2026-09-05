#!/usr/bin/env node
'use strict';

// Offline fake CouchDB only. Uses checked-in, verified English voice assets.
const assert = require('node:assert/strict'), path = require('node:path'), crypto = require('node:crypto');
const importer = require('./import-acdc-gemini-voices.cjs');
const fixedDirectory = path.join(__dirname, 'assets/acdc-gemini-fixed-20260905');
const revision = '1-' + 'a'.repeat(32);
const clone = object => JSON.parse(JSON.stringify(object));
function stored(asset) {
  const doc = importer.document(asset); doc._rev = revision;
  doc._attachments[asset.attachment].digest = asset.md5;
  return doc;
}
function fakeDatabase(hook = () => {}) {
  const docs = new Map(), calls = [];
  return {docs, calls, client: async (method, resource, body) => {
    calls.push({method, resource, body}); const overridden = hook(method, resource, body, docs, calls);
    if (overridden) return overridden;
    if (method === 'POST') {
      assert.equal(resource, '_all_docs?include_docs=true&attachments=true'); assert(body.keys.length <= 10);
      return {status: 200, body: {rows: body.keys.map(key => docs.has(key) ? {key, id: key, doc: clone(docs.get(key))} : {key, error: 'not_found'})}};
    }
    assert.equal(method, 'PUT'); assert.equal(resource, encodeURIComponent(body._id)); assert.equal(body._rev, undefined);
    assert.equal(docs.has(body._id), false); const doc = clone(body); doc._rev = revision;
    const attachment = doc._attachments[Object.keys(doc._attachments)[0]];
    attachment.digest = 'md5-' + crypto.createHash('md5').update(Buffer.from(attachment.data, 'base64')).digest('base64');
    docs.set(doc._id, doc); return {status: 201, body: {ok: true, id: doc._id, rev: revision}};
  }};
}
async function main() {
  const plan = importer.loadPlan(fixedDirectory, undefined, ['en-us']);
  assert.equal(plan.length, 29);
  assert(plan.every(p => p.id !== `${p.locale}/${p.canonical_id}` && p.id.includes('-gemini-sulafat-')));
  assert(plan.every(p => p.sha256 === crypto.createHash('sha256').update(p.bytes).digest('hex')));
  assert.equal(importer.publicPlan(plan).prompts.some(p => p.bytes), false);
  assert.throws(() => importer.loadPlan(fixedDirectory, undefined, ['ar-sa']), /incomplete/);
  console.log('PASS verified29 English sources, content-addressed identities, binary-free plan and Arabic digit gate');
  const database = fakeDatabase();
  const legacy = {unrecognized: 'custom recording retained'};
  database.docs.set('en-us/acdc-callback-success', legacy);
  const first = await importer.install(plan, database.client, true);
  assert.equal(first.created, 29); assert.equal(first.verified, 29); assert.equal(first.runtime_ready, false);
  assert.equal(first.queue_configuration_changed, false); assert.equal(first.full_position_language_ready, false);
  assert.deepEqual(database.docs.get('en-us/acdc-callback-success'), legacy);
  const writes = database.calls.filter(p => p.method === 'PUT').length;
  const second = await importer.install(plan, database.client, false);
  assert.equal(second.created, 0); assert.equal(second.preserved, 29);
  assert.equal(database.calls.filter(p => p.method === 'PUT').length, writes);
  console.log('PASS create-only import and zero-write idempotent verification preserve legacy/custom media and all runtime gates');
  const wrong = fakeDatabase(); wrong.docs.set(plan[0].id, {...stored(plan[0]), source_type: 'another-owner'});
  await assert.rejects(importer.install([plan[0]], wrong.client, true), /not owned/);
  assert.equal(wrong.calls.filter(p => p.method === 'PUT').length, 0);
  const corrupted = stored(plan[0]); corrupted._attachments[plan[0].attachment].data = Buffer.from('wrong audio').toString('base64');
  assert.throws(() => importer.verifyDocument(plan[0], corrupted), /verification/);
  const ambiguous = stored(plan[0]); ambiguous._attachments['another.wav'] = clone(ambiguous._attachments[plan[0].attachment]);
  assert.throws(() => importer.verifyDocument(plan[0], ambiguous), /inventory/);
  console.log('PASS foreign ownership, altered attachment bytes and ambiguous attachment inventories fail without replacement');
  const conflict = fakeDatabase((method, _resource, body, docs) => {
    if (method !== 'PUT') return;
    docs.set(body._id, {...stored(plan[0]), source_type: 'concurrent-administrator'});
    return {status: 409, body: {error: 'conflict'}};
  });
  await assert.rejects(importer.install([plan[0]], conflict.client, true), /not owned/);
  assert.equal(conflict.calls.filter(p => p.method === 'PUT').length, 1);
  assert.equal(conflict.docs.get(plan[0].id).source_type, 'concurrent-administrator');
  console.log('PASS409 never triggers overwrite/revision retry against a concurrent administrator');
  const race = fakeDatabase((method, _resource, _body, docs, calls) => {
    if (method === 'POST' && calls.filter(p => p.method === 'POST').length === 3) {
      docs.get(plan[0].id).source_voice.sha256 = '0'.repeat(64);
    }
  });
  await assert.rejects(importer.install([plan[0]], race.client, true), /provenance/);
  console.log('PASS final re-verification catches a document changed after its create acknowledgment');
  const missing = fakeDatabase();
  await assert.rejects(importer.install([plan[0]], missing.client, false), /not installed/);
  assert.equal(missing.calls.filter(p => p.method === 'PUT').length, 0);
  console.log('PASS verify-only cannot create missing media');
  console.log('6 voice-import offline test groups passed; zero database or provider traffic.');
}
main().catch(error => { console.error(error.stack); process.exitCode = 1; });
