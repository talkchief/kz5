#!/usr/bin/env node
'use strict';
// Read-only deployed-function proof. Never starts a worker, call or provider.
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const cp = require('node:child_process'), crypto = require('node:crypto'), assert = require('node:assert/strict');
const cardinal = require('./refresh-acdc-cardinal-mappings.cjs');
const fixed = require('./refresh-acdc-gemini-mappings.cjs');
const installer = require('./install-acdc-cardinal-pack.cjs');
const importer = require('./import-acdc-gemini-voices.cjs');
const {validateReceipt: validateFixed} = require('./validate-acdc-gemini-receipt.cjs');
const {cardinalCounts: COUNTS} = require('./validate-acdc-language-capabilities.cjs');
const pack = require('./acdc-cardinal-pack.cjs');
const MODULES = ['acdc_announcements', 'acdc_callback_caller', 'acdc_cardinal_media', 'acdc_cardinal_prompts',
  'acdc_gemini_prompts', 'acdc_language', 'acdc_wait_time_media', 'cb_acdc_queue_editor', 'cf_acdc_member', 'kz_media_map', 'media_map'];
const NUMBERS = [1, 2, 4, 9, 11, 12, 21, 71, 80, 81, 89, 101, 102, 1000, 2000, 12000, 21000, 1001001, 999999999];
const WAIT = [0, 59, 60, 300, 301, 600, 601, 900, 901, 1800, 1801, 2700, 2701, 3600, 3601, 999999];
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const validSha = v => typeof v === 'string' && v.length === 64 && /^[a-f0-9]{64}$/.test(v);
const validAccount = v => typeof v === 'string' && v.length === 32 && /^[a-f0-9]{32}$/.test(v);
const exactKeys = (v, keys) => assert(v && Object.getPrototypeOf(v) === Object.prototype
  && JSON.stringify(Object.keys(v).sort()) === JSON.stringify(keys.slice().sort()), 'Unexpected evidence fields');
const absolute = f => typeof f === 'string' && path.isAbsolute(f) && path.resolve(f) === f && f !== '/';
const identity = (a, b) => ['dev', 'ino', 'size', 'uid', 'gid', 'mode', 'nlink', 'mtimeMs', 'ctimeMs'].every(k => a[k] === b[k]);
function protectedParents(directory) {
  for (let current = directory;; current = path.dirname(current)) {
    const s = fs.lstatSync(current);
    assert(s.isDirectory() && !s.isSymbolicLink() && s.uid === 0 && !(s.mode & 0o022), 'Unprotected evidence parent');
    if (path.dirname(current) === current) break;
  }
}
function readPinned(file, expected, limit = 8 * 1024 * 1024) {
  assert(absolute(file) && validSha(expected), 'Explicit exact path and SHA256 required');
  protectedParents(path.dirname(file));
  const before = fs.lstatSync(file);
  const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
  try {
    const s = fs.fstatSync(fd);
    assert(s.isFile() && s.uid === 0 && s.nlink === 1 && !(s.mode & 0o022) && s.size > 0 && s.size <= limit
      && identity(before, s), 'Unprotected or unbounded evidence');
    const bytes = Buffer.alloc(s.size + 1); let n, size = 0;
    while (size < bytes.length && (n = fs.readSync(fd, bytes, size, bytes.length - size, null)) > 0) size += n;
    assert(size === s.size && identity(s, fs.fstatSync(fd)) && identity(s, fs.lstatSync(file))
      && sha(bytes.subarray(0, size)) === expected, 'Evidence changed or wrong pin');
    return bytes.subarray(0, size);
  } finally { fs.closeSync(fd); }
}
function createEvidence(file, bytes) {
  assert(process.getuid() === 0 && absolute(file), 'Explicit protected output required');
  protectedParents(path.dirname(file));
  const temporary = path.join(path.dirname(file), '.acdc-proof-' + crypto.randomBytes(16).toString('hex'));
  const fd = fs.openSync(temporary, 'wx', 0o600);
  try { fs.writeFileSync(fd, bytes); fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
  try { fs.linkSync(temporary, file); } finally { fs.unlinkSync(temporary); }
  const dir = fs.openSync(path.dirname(file), 'r'); try { fs.fsyncSync(dir); } finally { fs.closeSync(dir); }
  return sha(readPinned(file, sha(bytes)));
}
function parseArgs(args) {
  const out = {}, resolution = [];
  const resolutionFlags = ['--model-trial-index', '--model-trial-index-sha256', '--supplemental-pack', '--alias-file', '--alias-sha256'];
  const names = ['node', 'account', 'cardinal-receipt', 'cardinal-receipt-sha256', 'fixed-receipt', 'fixed-receipt-sha256',
    'beam-manifest', 'beam-manifest-sha256', 'fixed-pack', 'completion-pack', 'fixed-map', 'fixed-map-sha256', 'output'];
  const seen = new Set();
  for (let i = 0; i < args.length; i += 2) {
    const flag = args[i], value = args[i + 1];
    assert(typeof flag === 'string' && flag.startsWith('--') && !seen.has(flag)
      && typeof value === 'string' && !value.startsWith('--'), 'Invalid or repeated probe option'); seen.add(flag);
    assert(names.includes(flag.slice(2)) || resolutionFlags.includes(flag), 'Unknown probe option');
    out[flag.slice(2)] = value;
    if (resolutionFlags.includes(flag)) resolution.push(flag, value);
  }
  assert(names.every(k => out[k]), 'Missing explicit probe input');
  assert(validAccount(out.account) && !/[\r\n]/.test(out.node) && /^[a-z][a-z0-9_]*@[A-Za-z0-9_.-]+$/.test(out.node)
    && out.node.length <= 255, 'Invalid explicit account/node scope');
  for (const key of names.filter(k => !['node', 'account'].includes(k)))
    assert(key.endsWith('sha256') ? validSha(out[key]) : absolute(out[key]), 'Invalid path or input pin');
  out.resolution = installer.options(['--plan', '--all-locales', ...resolution]).resolution || {};
  return out;
}
function validateBeams(manifest) {
  exactKeys(manifest, ['schema_version', 'modules']); assert.equal(manifest.schema_version, 1);
  assert(Array.isArray(manifest.modules) && manifest.modules.length === MODULES.length, 'Incomplete production module set');
  assert.deepEqual(manifest.modules.map(x => x.module).sort(), MODULES.slice().sort(), 'Wrong production module set');
  for (const m of manifest.modules) {
    exactKeys(m, ['module', 'path', 'sha256']);
    assert(absolute(m.path) && path.basename(m.path) === m.module + '.beam' && validSha(m.sha256), 'Invalid production module pin');
    readPinned(m.path, m.sha256, 8 * 1024 * 1024);
  }
  return manifest.modules;
}
// Fixed210 owns only seven-field literal rows. Do not depend on a private
// parser from the separate cardinal mapping adapter or evaluate header code.
function fixedMapRows(text) {
  assert(typeof text === 'string' && Buffer.byteLength(text) <= 262144, 'Unbounded fixed map');
  const hashes = [...text.matchAll(/^-define\(GEMINI_MAP_SHA256, <<"([a-f0-9]{64})">>\)\.$/gm)];
  const inventories = [...text.matchAll(/^-define\(GEMINI_ASSETS, \[\n([\s\S]*?)\n\]\)\.$/gm)];
  assert(hashes.length === 1 && inventories.length === 1, 'Exact fixed map macros required');
  const remaining = text.replace(hashes[0][0], '').replace(inventories[0][0], '');
  assert(remaining.split('\n').every(line => /^\s*$/.test(line) || /^%%/.test(line)), 'Unexpected fixed map expression');
  const lines = inventories[0][1].split('\n');
  const rows = lines.map((line, index) => {
    const literal = line.trim();
    assert(index === lines.length - 1 ? !literal.endsWith(',') : literal.endsWith(','), 'Invalid fixed row delimiter');
    const value = literal.replace(/,$/, ''); assert(/^\{[^\r\n]*\}$/.test(value), 'Invalid fixed row');
    let rest = value.slice(1, -1); const fields = [];
    while (rest.length) {
      const token = /^(?:<<("[A-Za-z0-9_+\/=.-]+")>>|([1-9][0-9]*))(?=,|$)/.exec(rest);
      assert(token, 'Invalid fixed literal field');
      fields.push(token[1] ? JSON.parse(token[1]) : Number(token[2]));
      rest = rest.slice(token[0].length);
      if (rest) { assert(rest.startsWith(',') && rest.length > 1); rest = rest.slice(1); }
    }
    assert(fields.length === 7 && [0, 1, 2, 3, 4, 6].every(i => typeof fields[i] === 'string')
      && Number.isSafeInteger(fields[5]) && fields[5] > 44, 'Wrong fixed row shape');
    return fields;
  });
  assert(rows.length === 210 && new Set(rows.map(r => r[0] + '/' + r[2])).size === 210, 'Exact unique fixed210 required');
  assert.equal(sha(JSON.stringify(rows)), hashes[0][1], 'Fixed map hash mismatch');
  return rows;
}
function buildInput(o) {
  const c = JSON.parse(readPinned(o['cardinal-receipt'], o['cardinal-receipt-sha256']));
  const f = JSON.parse(readPinned(o['fixed-receipt'], o['fixed-receipt-sha256']));
  const beams = validateBeams(JSON.parse(readPinned(o['beam-manifest'], o['beam-manifest-sha256'], 32768)));
  const entries = installer.releasePlans(undefined, undefined, o.resolution);
  const cardinalDocs = cardinal.expectedDocuments(entries, c);
  const fixedPlan = importer.loadPlan(o['fixed-pack'], o['completion-pack'], Object.keys(COUNTS), o['supplemental-pack']);
  assert.equal(fixedPlan.length, 210, 'Full fixed callback inventory required');
  const fixedDocs = fixed.expectedDocuments(fixedPlan, f, importer, validateFixed)
    .map(d => ({...d, source_cardinal_resolution: null}));
  const text = readPinned(o['fixed-map'], o['fixed-map-sha256'], 262144).toString('utf8');
  const rows = fixedMapRows(text);
  const fixedHash = sha(JSON.stringify(rows));
  for (const row of rows) {
    const d = fixedDocs.find(e => e._id === row[0] + '/' + row[2]);
    assert(d && row.length === 7 && row[1] === d.source_voice.canonical_prompt_id && row[3] === d.source_voice.sha256
      && row[4] === d.digest && row[5] === d.content_length && row[6] === d.source_voice.transcript_sha256, 'Fixed map differs from byte-verified receipt');
  }
  const documents = cardinalDocs.concat(fixedDocs).sort((a, b) => a._id.localeCompare(b._id, 'en'));
  assert(documents.length === 796 && new Set(documents.map(d => d._id)).size === 796, 'Exact unique owned inventory required');
  const locales = Object.keys(COUNTS).map(locale => ({locale, count: COUNTS[locale],
    cardinal_map_sha256: c.locales.find(e => e.locale === locale).map_sha256,
    fixed_map_sha256: fixedHash, source_catalog_sha256: pack.CATALOG_HASH}));
  const input = {schema_version: 1, node: o.node, account: o.account, beams, documents, locales,
    number_cases: NUMBERS, wait_cases: WAIT, cardinal_receipt_sha256: o['cardinal-receipt-sha256'],
    fixed_receipt_sha256: o['fixed-receipt-sha256'], beam_manifest_sha256: o['beam-manifest-sha256']};
  assert(Buffer.byteLength(JSON.stringify(input)) <= 8 * 1024 * 1024, 'Unbounded runtime sidecar');
  return input;
}
function render(template, sidecar, digest, node) {
  assert(absolute(sidecar) && /^[A-Za-z0-9_./-]+$/.test(sidecar) && validSha(digest)
    && /^[a-z][a-z0-9_]*@[A-Za-z0-9_.-]+$/.test(node), 'Unsafe runtime template input');
  for (const [key, value] of Object.entries({SIDECAR: sidecar, INPUT_SHA256: digest, NODE: node})) {
    const marker = '@@' + key + '@@'; assert.equal(template.split(marker).length, 2); template = template.replace(marker, value);
  }
  assert(!template.includes('@@') && Buffer.byteLength(template) < 32768, 'Unbounded runtime script'); return template;
}
function validateResult(stdout, inputSha) {
  assert(typeof stdout === 'string' && stdout.length <= 65536);
  const m = stdout.replace(/\s/g, '').match(/^\{ok,\{ok,\{prerecorded_runtime_verified,<<"([a-f0-9]{64})">>,796,1592,5,95,10,80,no_database_writes,no_calls,no_native_review\}\}\}$/);
  assert(m && m[1] === inputSha, 'Runtime completion unconfirmed');
}
function makeReceipt(input, inputSha, started, finished, codeSha) {
  return {schema_version: 1, owner: 'kazoo5-acdc-prerecorded-runtime-probe', node: input.node, account: input.account,
    started_at: started, finished_at: finished, input_sha256: inputSha, probe_script_sha256: codeSha,
    beam_manifest_sha256: input.beam_manifest_sha256, beams: input.beams,
    cardinal_receipt_sha256: input.cardinal_receipt_sha256, fixed_receipt_sha256: input.fixed_receipt_sha256,
    installed_media_sha256: sha(JSON.stringify({cardinal_receipt_sha256: input.cardinal_receipt_sha256,
      fixed_receipt_sha256: input.fixed_receipt_sha256})), expected_inventory_sha256: sha(JSON.stringify(input.documents)),
    documents_verified: 796, mappings_verified: 1592, number_cases: NUMBERS, wait_cases: WAIT,
    position_playlist_cases: 95, callback_prepare_cases: 10, wait_playlist_cases: 80,
    runtime_function_testable: true, live_SIP_verified: false, native_listening_approved: false, full_language_ready: false,
    database_writes: false, queue_configuration_changed: false, service_restarts: false, provider_requests: 0,
    locales: input.locales.map(e => ({...e, callback_count: 42, wait_count: 10,
      position_runtime_verified: true, callback_runtime_verified: true, wait_time_runtime_verified: true}))};
}
function execute(o, {spawn = cp.spawnSync} = {}) {
  assert(process.getuid() === 0, 'Protected DEV probe requires root');
  protectedParents(path.dirname(o.output)); assert(!fs.existsSync(o.output), 'Receipt output already exists');
  const input = buildInput(o), bytes = Buffer.from(JSON.stringify(input)), digest = sha(bytes);
  const template = fs.readFileSync(path.join(__dirname, 'probe-acdc-prerecorded-runtime.erl.template'), 'utf8');
  const group = spawn('getent', ['group', 'kazoo'], {encoding: 'utf8', timeout: 5000, maxBuffer: 4096});
  assert(group.status === 0 && /^kazoo:[^:]*:[1-9][0-9]*:/.test(group.stdout), 'Service group unavailable');
  const gid = Number(group.stdout.split(':')[2]), dir = fs.mkdtempSync(path.join(os.tmpdir(), 'kazoo-prerecorded-probe.'));
  fs.chownSync(dir, 0, gid); fs.chmodSync(dir, 0o750);
  const sidecar = path.join(dir, 'input.json'), script = path.join(dir, 'probe.erl');
  try {
    const code = render(template, sidecar, digest, o.node);
    for (const [file, content] of [[sidecar, bytes], [script, code]]) {
      fs.writeFileSync(file, content, {flag: 'wx', mode: 0o640}); fs.chownSync(file, 0, gid); fs.chmodSync(file, 0o640);
    }
    assert.equal(sha(JSON.stringify(buildInput(o))), digest, 'Probe prerequisites changed');
    const started = new Date().toISOString();
    // SUP -t is seconds; the child-process timeout below is milliseconds.
    const result = spawn('/usr/local/bin/sup', ['-t', '180', '-n', o.node.split('@')[0], '-e', 'true',
      'file', 'script', JSON.stringify(script)], {encoding: 'utf8', timeout: 190000, maxBuffer: 65536});
    assert(!result.error && result.status === 0, 'Probe RPC failed; completion unconfirmed');
    validateResult(result.stdout, digest);
    assert.equal(sha(JSON.stringify(buildInput(o))), digest, 'Probe prerequisites changed after RPC');
    const receipt = makeReceipt(input, digest, started, new Date().toISOString(), sha(code));
    const outputSha = createEvidence(o.output, Buffer.from(JSON.stringify(receipt, null, 2) + '\n'));
    return {receipt: o.output, sha256: outputSha, runtime_function_testable: true, full_language_ready: false};
  } finally {
    for (const file of [sidecar, script]) if (fs.existsSync(file)) fs.unlinkSync(file);
    fs.rmdirSync(dir);
  }
}
module.exports = {MODULES, COUNTS, NUMBERS, WAIT, sha, validSha, validAccount, exactKeys, absolute,
  protectedParents, readPinned, createEvidence, parseArgs, validateBeams, fixedMapRows, buildInput, render, validateResult, makeReceipt, execute};
if (require.main === module) {
  try { console.log(JSON.stringify(execute(parseArgs(process.argv.slice(2))))); }
  catch (_) { console.error('Prerecorded runtime probe failed safely; no capability was published and completion is unconfirmed.'); process.exitCode = 1; }
}
