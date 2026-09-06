#!/usr/bin/env node
'use strict';
// SUP uses its existing protected config. This helper never reads a cookie,
// database/provider credential, or endpoint URL and never writes to CouchDB.
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const cp = require('node:child_process'), assert = require('node:assert/strict');
const crypto = require('node:crypto');
const sha = b => crypto.createHash('sha256').update(b).digest('hex');
function parseArgs(argv) {
  const o = {toolDirectory: __dirname};
  for (let i = 0; i < argv.length; i++) {
    if (['--check', '--activate'].includes(argv[i])) {
      assert(!o.mode, 'Choose exactly one mapping mode'); o.mode = argv[i].slice(2); continue;
    }
    const k = {'--node': 'node', '--receipt': 'receipt', '--fixed-pack': 'fixed', '--completion-pack': 'completion',
      '--supplemental-pack': 'supplemental', '--tool-dir': 'toolDirectory'}[argv[i]];
    assert(k && argv[i + 1] && !argv[i + 1].startsWith('--') && (k === 'toolDirectory' || !o[k]), 'Unknown or repeated mapping option');
    o[k] = argv[++i];
  }
  assert(o.mode && o.node && o.receipt && o.fixed && o.completion, 'Explicit mode/node/receipt/asset directories are required');
  assert(/^[a-z][a-z0-9_]*@[A-Za-z0-9_.-]+$/.test(o.node) && o.node.length <= 255, 'Invalid configured node name');
  for (const k of ['receipt', 'fixed', 'completion', 'toolDirectory']) assert(path.isAbsolute(o[k]), 'Absolute paths are required');
  if (o.supplemental) assert(path.isAbsolute(o.supplemental), 'Absolute supplemental path is required');
  return o;
}
function protectedReceipt(file) {
  assert(fs.realpathSync(file) === file, 'Symlinked receipt');
  const s = fs.lstatSync(file);
  assert(s.isFile() && s.uid === 0 && !(s.mode & 0o022) && s.size > 0 && s.size <= 1024 * 1024, 'Expected root-owned non-writable media receipt');
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}
function expectedDocuments(plan, receipt, importer, validator) {
  validator(receipt, plan);
  const revisions = new Map(receipt.prompts.map(p => [p.document_id, p.revision]));
  return plan.map(asset => {
    const doc = importer.document(asset, 0);
    return {_id: asset.id, _rev: revisions.get(asset.id), prompt_id: asset.prompt_id, language: asset.locale,
      source_voice: doc.source_voice, source_type: doc.source_type, content_length: asset.bytes.length,
      digest: asset.md5, attachment: asset.attachment, expected_path: '/system_media/' + encodeURIComponent(asset.id)};
  });
}
function render(template, expected, mode, node) {
  assert(['activate', 'check'].includes(mode));
  assert(/^[a-z][a-z0-9_]*@[A-Za-z0-9_.-]+$/.test(node));
  assert(Array.isArray(expected) && [165, 210].includes(expected.length));
  const replacements = {NODE: node, MODE: mode, EXPECTED_BASE64: Buffer.from(JSON.stringify(expected)).toString('base64')};
  for (const [key, value] of Object.entries(replacements)) {
    const marker = '@@' + key + '@@'; assert.equal(template.split(marker).length, 2, 'Template marker mismatch'); template = template.replace(marker, value);
  }
  assert(!template.includes('@@'), 'Unresolved template marker'); return template;
}
function validateResult(stdout, mode, count = 165) {
  assert([165, 210].includes(count), 'Unsupported mapping inventory');
  const value = stdout.replace(/\s/g, '');
  const m = value.match(/^\{ok,\{ok,\{gemini_mapping_verified,(activate|check),(\d+),(\d+),(\d+),no_database_writes\}\}\}$/);
  assert(m && m[1] === mode && Number(m[2]) === count && Number(m[3]) === count * 2 &&
    Number(m[4]) <= count * 2 && (mode !== 'check' || Number(m[4]) === 0), 'Unconfirmed mapping result');
  return Number(m[4]);
}
function execute(o, {spawn = cp.spawnSync, temporaryParent = os.tmpdir(), templateDirectory = __dirname} = {}) {
  assert(process.getuid() === 0, 'Run mapping verification as root through protected SUP');
  const importer = require(path.join(o.toolDirectory, 'import-acdc-gemini-voices.cjs'));
  const {validateReceipt} = require(path.join(o.toolDirectory, 'validate-acdc-gemini-receipt.cjs'));
  const {LOCALES} = require(path.join(o.toolDirectory, 'generate-acdc-gemini-samples.cjs'));
  const receipt = protectedReceipt(o.receipt), plan = importer.loadPlan(o.fixed, o.completion, LOCALES, o.supplemental);
  const expected = expectedDocuments(plan, receipt, importer, validateReceipt);
  const template = fs.readFileSync(path.join(templateDirectory, 'refresh-acdc-gemini-mappings.erl.template'), 'utf8');
  const code = render(template, expected, o.mode, o.node);
  const group = spawn('getent', ['group', 'kazoo'], {encoding: 'utf8', timeout: 5000, maxBuffer: 4096});
  assert(group.status === 0 && /^kazoo:[^:]*:\d+:/.test(group.stdout), 'Kazoo service group unavailable');
  const gid = Number(group.stdout.split(':')[2]); assert(Number.isSafeInteger(gid) && gid > 0);
  const directory = fs.mkdtempSync(path.join(temporaryParent, 'kazoo-gemini-map.'));
  fs.chownSync(directory, 0, gid); fs.chmodSync(directory, 0o750);
  const file = path.join(directory, 'verify.erl');
  try {
    fs.writeFileSync(file, code, {mode: 0o640, flag: 'wx'}); fs.chownSync(file, 0, gid);
    // The root installer can use umask077; make service-group readability
    // explicit without granting write permission or exposing secrets.
    fs.chmodSync(file, 0o640);
    // SUP itself appends the local configured hostname; passing a full node
    // here would produce two @ separators. The evaluated code separately
    // asserts the full expected node before opening any media document.
    const result = spawn('/usr/local/bin/sup', ['-t', '60000', '-n', o.node.split('@')[0], '-e', 'true', 'file', 'script', JSON.stringify(file)],
      {encoding: 'utf8', timeout: 65000, maxBuffer: 16384});
    assert(!result.error && result.status === 0, 'Mapping RPC failed or timed out; completion is unconfirmed');
    const missingBefore = validateResult(result.stdout, o.mode, plan.length);
    return {schema_version: 1, mode: o.mode, node: o.node, documents_verified: plan.length, mappings_verified: plan.length * 2,
      missing_before: missingBefore, database_writes: false, queue_configuration_changed: false,
      full_position_language_ready: false, runtime_language_capability_published: false,
      expected_inventory_sha256: sha(JSON.stringify(expected)), media_receipt_sha256: sha(JSON.stringify(receipt))};
  } finally {
    if (fs.existsSync(file)) fs.unlinkSync(file);
    fs.rmdirSync(directory);
  }
}
module.exports = {parseArgs, protectedReceipt, expectedDocuments, render, validateResult, execute};
if (require.main === module) {
  try { console.log(JSON.stringify(execute(parseArgs(process.argv.slice(2))))); }
  catch (_) { console.error('Gemini prompt mapping verification failed; no database or customer recording changes were attempted.'); process.exitCode = 1; }
}
