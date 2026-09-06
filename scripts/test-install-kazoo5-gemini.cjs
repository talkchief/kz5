#!/usr/bin/env node
'use strict';
const fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const cp = require('node:child_process'), crypto = require('node:crypto'), assert = require('node:assert/strict');
for (const transport of ['node:http', 'node:https']) require(transport).request = () => {
  throw new Error('Network access is forbidden in offline installer tests');
};
global.fetch = () => { throw new Error('Provider access is forbidden in offline installer tests'); };
const ROOT = path.resolve(__dirname, '..');
const importer = require('./import-acdc-gemini-voices.cjs');
const {validateReceipt} = require('./validate-acdc-gemini-receipt.cjs');
const locales = ['en-us', 'ar-sa', 'he-il', 'es-es', 'fr-fr'];
const fixed = path.join(ROOT, 'scripts/assets/acdc-gemini-fixed-20260905');
const completion = path.join(ROOT, 'scripts/assets/acdc-gemini-completion-20260905');
const supplemental = path.join(ROOT, 'scripts/assets/acdc-gemini-supplemental-20260906');
const revision = '1-' + 'a'.repeat(32);
const clone = value => JSON.parse(JSON.stringify(value));
let cachedPlan;
const plan = () => cachedPlan || (cachedPlan = importer.loadPlan(fixed, completion, locales, supplemental));
const record = value => fs.appendFileSync(process.env.KAZOO_TEST_TRACE, value + '\n');

function receipt(assets = plan(), created = 210) {
  return {schema_version: 1, owner: importer.OWNER, created, preserved: 210 - created, verified: 210,
    queue_configuration_changed: false, runtime_ready: false, full_position_language_ready: false,
    prompts: assets.map(p => ({locale: p.locale, canonical_id: p.canonical_id, prompt_id: p.prompt_id,
      document_id: p.id, attachment: p.attachment, sha256: p.sha256, revision}))};
}

function assertPaths(args) {
  assert.deepEqual(args, ['--fixed-pack', fixed, '--completion-pack', completion, '--supplemental-pack', supplemental]);
}

async function fixture(kind, args) {
  const scenario = process.env.KAZOO_TEST_CASE;
  if (kind === '--fixture-importer') {
    const [mode, all, ...paths] = args;
    assert.equal(all, '--all-locales'); assertPaths(paths);
    assert(['--plan', '--import', '--verify-only'].includes(mode));
    const phase = mode.slice(2); record(phase);
    if (phase === 'plan') {
      assert.notEqual(scenario, 'missing-assets', 'Simulated absent/invalid checked-in asset');
      console.log(JSON.stringify(importer.publicPlan(plan()))); return;
    }
    assert.equal(process.env.KAZOO_COUCHDB_HOST, 'database.example.invalid');
    assert.equal(process.env.KAZOO_COUCHDB_PORT, '15984');
    assert.equal(process.env.KAZOO_COUCHDB_USER, 'fixture-user');
    assert.equal(process.env.KAZOO_COUCHDB_PASSWORD, 'fixture-password');
    if (phase === 'import') assert.notEqual(scenario, 'import-failure');
    if (phase === 'verify-only') assert.notEqual(scenario, 'verify-failure');
    const output = receipt(plan(), phase === 'import' ? 210 : 0);
    if (scenario === 'invalid-receipt') output.runtime_ready = true;
    console.log(JSON.stringify(output)); return;
  }
  if (kind === '--fixture-validator') {
    assertPaths(args);
    validateReceipt(JSON.parse(fs.readFileSync(0, 'utf8')), plan()); record('receipt-validated'); return;
  }
  assert.equal(kind, '--fixture-couch');
  assert.equal(args.at(-1), 'http://database.example.invalid:15984/system_media');
  assert(!args.includes('DELETE') && !args.some(a => /fixture-(user|password)/.test(a)));
  if (args.includes('--request')) {
    assert.equal(args[args.indexOf('--request') + 1], 'PUT');
    assert.equal(args[args.indexOf('--write-out') + 1], '%{http_code}');
    const output = args[args.indexOf('--output') + 1];
    assert(/^\/tmp\/kazoo-system-media-database\.[A-Za-z0-9]+$/.test(output));
    assert.equal(fs.lstatSync(output).mode & 0o777, 0o600);
    record('db-ensure');
    let code = scenario === 'database-exists' ? 412 : 201;
    let body = code === 412 ? {error: 'file_exists'} : {ok: true};
    if (scenario === 'database-forbidden') { code = 401; body = {error: 'unauthorized'}; }
    if (scenario === 'bad-database-ack') body = {ok: false};
    fs.writeFileSync(output, JSON.stringify(body)); process.stdout.write(String(code)); return;
  }
  record('db-identity');
  console.log(JSON.stringify({db_name: scenario === 'wrong-database-identity' ? 'another_database' : 'system_media'}));
}

function fakeDatabase() {
  const docs = new Map(), calls = [];
  return {docs, calls, client: async (method, resource, body) => {
    calls.push({method, resource});
    if (method === 'POST') {
      assert.equal(resource, '_all_docs?include_docs=true&attachments=true');
      assert(body.keys.length <= 10);
      return {status: 200, body: {rows: body.keys.map(key => docs.has(key) ?
        {key, id: key, doc: clone(docs.get(key))} : {key, error: 'not_found'})}};
    }
    assert.equal(method, 'PUT'); assert.equal(resource, encodeURIComponent(body._id));
    assert.equal(body._rev, undefined); assert.equal(docs.has(body._id), false);
    const doc = clone(body); doc._rev = revision;
    for (const attachment of Object.values(doc._attachments)) attachment.digest = 'md5-' +
      crypto.createHash('md5').update(Buffer.from(attachment.data, 'base64')).digest('base64');
    docs.set(doc._id, doc);
    return {status: 201, body: {ok: true, id: doc._id, rev: revision}};
  }};
}

async function main() {
  const assets = plan();
  assert.equal(assets.length, 210);
  assert.deepEqual(Object.fromEntries(locales.map(locale => [locale, assets.filter(p => p.locale === locale).length])),
    {'en-us': 42, 'ar-sa': 42, 'he-il': 42, 'es-es': 42, 'fr-fr': 42});
  const good = receipt(); assert.equal(validateReceipt(good, assets), true);
  for (const mutate of [p => { p.runtime_ready = true; }, p => { p.full_position_language_ready = true; },
    p => { p.queue_configuration_changed = true; }, p => { p.prompts.pop(); }, p => { p.prompts[1] = clone(p.prompts[0]); },
    p => { p.prompts[0].sha256 = '0'.repeat(64); }, p => { p.prompts[0].prompt_id = p.prompts[0].canonical_id; },
    p => { p.prompts[0].revision = 'bad'; }, p => { p.prompts[0].locale = 'de-de'; },
    p => { p.created = -1; }, p => { p.preserved = 1; }, p => { p.verified = 164; },
    p => { p.credentials = 'forbidden-extra-field'; }]) {
    const broken = clone(good); mutate(broken); assert.throws(() => validateReceipt(broken, assets));
  }
  assert.throws(() => importer.loadPlan('/tmp/definitely-missing-kazoo-voice-source', completion, locales));
  console.log('PASS exact210 inventory and13 negative receipt cases; missing source fails offline');

  const database = fakeDatabase();
  const customer = {custom: 'customer-owned recording'}, official = {official: 'ordinary prompt'};
  database.docs.set('en-us/acdc-callback-success', customer);
  database.docs.set('en-us/ivr-thank_you', official);
  const imported = await importer.install(assets, database.client, true);
  assert.equal(validateReceipt(imported, assets), true); assert.equal(imported.created, 210);
  assert.deepEqual(database.docs.get('en-us/acdc-callback-success'), customer);
  assert.deepEqual(database.docs.get('en-us/ivr-thank_you'), official);
  const writes = database.calls.filter(c => c.method === 'PUT').length;
  const verified = await importer.install(assets, database.client, false);
  assert.equal(validateReceipt(verified, assets), true); assert.equal(verified.created, 0);
  assert.equal(database.calls.filter(c => c.method === 'PUT').length, writes);
  database.docs.get(assets[0].id).source_type = 'customer-took-versioned-id';
  await assert.rejects(importer.install(assets, database.client, true));
  assert.equal(database.calls.filter(c => c.method === 'PUT').length, writes);
  console.log('PASS create-only210 import, byte-verified zero-write rerun, and existing official/customer media preserved');

  const workspace = fs.mkdtempSync(path.join(os.tmpdir(), 'kazoo-gemini-installer-tests.'));
  for (const scenario of ['success', 'database-exists', 'missing-assets', 'database-forbidden',
    'bad-database-ack', 'wrong-database-identity', 'import-failure', 'verify-failure', 'invalid-receipt', 'verify-only', 'dry-run', 'cache-failure', 'capability-failure']) {
    const trace = path.join(workspace, scenario + '.trace'); fs.writeFileSync(trace, '');
    const run = cp.spawnSync('bash', [path.join(__dirname, 'test-fixtures/gemini-installer.sh')], {encoding: 'utf8', timeout: 60000,
      env: {...process.env, KAZOO_TEST_CASE: scenario, KAZOO_TEST_SOURCE_ROOT: ROOT,
        KAZOO_TEST_WORK: workspace, KAZOO_TEST_TRACE: trace, KAZOO_TEST_NODE: process.execPath}});
    assert(!run.error, `${scenario}: subprocess failed`);
    const steps = fs.readFileSync(trace, 'utf8').trim().split('\n').filter(Boolean);
    const logs = run.stdout + run.stderr;
    assert(!/fixture-password|fixture-user/.test(logs), 'Credential leaked to output');
    if (['success', 'database-exists'].includes(scenario)) {
      assert.equal(run.status, 0, logs);
      assert.deepEqual(steps, ['node-tooling', 'plan', 'db-ensure', 'db-identity', 'import', 'receipt-validated',
        'verify-only', 'receipt-validated', 'receipt-validated', 'receipt-published',
        'editor-capabilities', 'build', 'units', 'sup-install', 'restart', 'apps-config', 'master-account', 'api-modules', 'official-prompts', 'apps-ready', 'cache-activate', 'apps-verify']);
    } else if (scenario === 'verify-only') {
      assert.equal(run.status, 0, logs); assert.deepEqual(steps, ['verify-only', 'receipt-validated', 'cache-check']);
    } else if (scenario === 'cache-failure') {
      assert.notEqual(run.status, 0, logs);
      assert(steps.includes('restart') && steps.includes('cache-activate') && !steps.includes('apps-verify'));
    } else if (scenario === 'capability-failure') {
      assert.notEqual(run.status, 0, logs);
      assert.equal(steps.at(-1), 'editor-capabilities');
      assert(steps.includes('receipt-published'), 'Verified immutable-media receipt remains separate from editor capabilities');
      for (const forbidden of ['build', 'units', 'sup-install', 'restart', 'apps-verify'])
        assert(!steps.includes(forbidden), 'Unsafe capability state must block application deployment');
    } else if (scenario === 'dry-run') {
      assert.equal(run.status, 0, logs); assert.deepEqual(steps, []);
      assert(logs.includes('database.example.invalid:15984') && logs.includes('210 checked-in Gemini'));
      assert(logs.includes('does not publish runtime or full-position readiness'));
    } else {
      assert.notEqual(run.status, 0, `${scenario}: failure did not abort installation`);
      for (const forbidden of ['build', 'units', 'sup-install', 'restart', 'receipt-published'])
        assert(!steps.includes(forbidden), `${scenario}: old application state changed`);
      if (scenario === 'missing-assets') assert.deepEqual(steps, ['node-tooling', 'plan']);
    }
    console.log(`PASS installer ${scenario}: ${steps.join(' > ') || 'no effects'}`);
  }
  const source = fs.readFileSync(path.join(__dirname, 'install-kazoo5.sh'), 'utf8');
  const officialSection = source.slice(source.indexOf('install_kazoo_prompts() ('), source.indexOf('\nverify_kazoo_prompts()'));
  assert(!/callback_dir|generate-acdc-|dnf_install|espeak-ng/.test(officialSection));
  assert(officialSection.includes('official-kazoo-prompt-manifest.cjs') && !officialSection.includes('find "$source_dir"') &&
    officialSection.includes('git -C "$KAZOO_BUILD_ROOT/kazoo-sounds" show') && officialSection.includes('prompt_documents "$manifest"') &&
    officialSection.includes('kazoo_media_maintenance import_prompts') && officialSection.includes('verify_kazoo_prompts'));
  const voicesSection = source.slice(source.indexOf('install_acdc_language_packs() ('), source.indexOf('\nconfigure_kazoo_api_modules()'));
  assert(!/prepare-acdc-speech|generate-acdc-|--generate|--key-file|dnf_install/.test(voicesSection));
  assert(!/write_file[^\n]*language-capabilities|write_file[^\n]*acdc-language-media/.test(voicesSection));
  console.log('PASS ordinary prompt/import verification preserved; no synthetic ACDC generator or runtime capability publication');
  console.log(`All offline installer tests passed. No live I/O; retained fixture traces: ${workspace}`);
}

if (process.argv[2]?.startsWith('--fixture-')) fixture(process.argv[2], process.argv.slice(3)).catch(() => {
  console.error('Simulated installer fixture failure'); process.exitCode = 1;
});
else main().catch(error => { console.error(error.stack); process.exitCode = 1; });
