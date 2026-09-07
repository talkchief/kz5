#!/usr/bin/env node
'use strict';
// Exact five-locale prerequisite; this adapter never obtains database/provider
// credentials. Protected SUP operates only the two existing in-memory maps.
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const cp = require('node:child_process'), assert = require('node:assert/strict');
const crypto = require('node:crypto');
const installer = require('./install-acdc-cardinal-pack.cjs');
const importer = require('./import-acdc-gemini-cardinals.cjs');
const pack = require('./acdc-cardinal-pack.cjs');
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const revision = value => typeof value === 'string' && /^[1-9][0-9]*-[a-f0-9]{32}$/.test(value);
const sha = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const nodeName = value => typeof value === 'string' && value.length <= 255 && /^[a-z][a-z0-9_]*@[A-Za-z0-9_.-]+$/.test(value);
const same = (a, b) => pack.digest(a) === pack.digest(b);
const sameFile = (a, b) => ['dev', 'ino', 'size', 'mode', 'uid', 'gid', 'nlink', 'mtimeMs', 'ctimeMs'].every(k => a[k] === b[k]);
const DOCS = 586, MAPPINGS = DOCS * 2;

function parseArgs(args) {
  const out = {}, seen = new Set(), resolutionArgs = [];
  const resolutionFlags = ['--model-trial-index', '--model-trial-index-sha256', '--supplemental-pack', '--alias-file', '--alias-sha256'];
  for (let i = 0; i < args.length; i++) {
    const flag = args[i];
    assert(!seen.has(flag), 'duplicate mapping option'); seen.add(flag);
    if (['--check', '--activate'].includes(flag)) {
      assert(!out.mode, 'exactly one mapping mode required'); out.mode = flag.slice(2);
    } else {
      assert(['--node', '--receipt', ...resolutionFlags].includes(flag) && args[i + 1] && !args[i + 1].startsWith('--'), 'invalid mapping option');
      const value = args[++i];
      if (resolutionFlags.includes(flag)) resolutionArgs.push(flag, value);
      else out[flag.slice(2)] = value;
    }
  }
  assert(out.mode && nodeName(out.node), 'explicit mapping mode and full node required');
  assert(typeof out.receipt === 'string' && path.isAbsolute(out.receipt) && path.resolve(out.receipt) === out.receipt, 'absolute receipt required');
  out.resolution = installer.options(['--plan', '--all-locales', ...resolutionArgs]).resolution || {};
  return out;
}

function protectedReceipt(file) {
  assert(path.isAbsolute(file) && path.resolve(file) === file && fs.realpathSync(file) === file, 'exact receipt path required');
  const before = fs.lstatSync(file);
  const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
  try {
    const stat = fs.fstatSync(fd);
    assert(stat.isFile() && stat.uid === 0 && stat.nlink === 1 && !(stat.mode & 0o022)
      && stat.size > 0 && stat.size <= 8 * 1024 * 1024 && sameFile(before, stat), 'protected bounded receipt required');
    const bytes = Buffer.alloc(stat.size + 1); let length = 0, n;
    while (length < bytes.length && (n = fs.readSync(fd, bytes, length, bytes.length - length, null)) > 0) length += n;
    assert(length === stat.size && sameFile(stat, fs.fstatSync(fd)) && sameFile(stat, fs.lstatSync(file))
      && fs.realpathSync(file) === file, 'receipt changed during read');
    return JSON.parse(bytes.subarray(0, length).toString('utf8'));
  } finally { fs.closeSync(fd); }
}

// Parse only the generated tuple literals, never evaluate Erlang or JavaScript.
function row(text) {
  assert(/^\{[^\r\n]*\}$/.test(text), 'invalid generated row');
  const body = text.slice(1, -1), result = [];
  let rest = body;
  while (rest.length) {
    const token = /^(?:<<("[A-Za-z0-9_+\/=.-]+")>>|([1-9][0-9]*))(?=,|$)/.exec(rest);
    assert(token, 'invalid generated field');
    result.push(token[1] ? JSON.parse(token[1]) : Number(token[2]));
    rest = rest.slice(token[0].length);
    if (rest) { assert(rest[0] === ',' && rest.length > 1, 'invalid row delimiter'); rest = rest.slice(1); }
  }
  assert([7, 9].includes(result.length), 'invalid row shape');
  return result;
}

function mapRows(snapshot) {
  const prefix = snapshot.locale === 'en-us' ? 'CARDINAL' : 'CARDINAL_' + snapshot.locale.slice(0, 2).toUpperCase();
  const matches = [...snapshot.map.matchAll(new RegExp(`^-define\\(${prefix}_ASSETS, \\[\\n([\\s\\S]*?)\\n\\]\\)\\.$`, 'gm'))];
  assert(matches.length === 1, 'exact cardinal map inventory required');
  const rows = matches[0][1].split('\n').map(line => row(line.trim().replace(/,$/, '')));
  assert(rows.length === importer.COUNTS[snapshot.locale], 'wrong cardinal row count');
  const resolved = snapshot.summary.map_row_schema === 'cardinal-resolved-row-v1';
  assert(rows.every(r => r.length === (resolved ? 9 : 7)), 'mixed row shape');
  assert(hash(JSON.stringify(resolved ? {schema_version: 1, row_schema: 'cardinal-resolved-row-v1', rows} : rows)) === snapshot.summary.map_sha256,
    'row inventory hash differs from verified source');
  let intro;
  if (['he-il', 'ar-sa'].includes(snapshot.locale)) {
    const match = [...snapshot.map.matchAll(new RegExp(`^-define\\(${prefix}_INTRO_ASSET, (\\{[^\\n]+\\})\\)\\.$`, 'gm'))];
    assert(match.length === 1, 'one exact intro asset required'); intro = row(match[0][1]);
    assert(intro.length === 7, 'intro model must remain fixed');
  }
  return {rows, intro};
}

function expectedRow(values, installed, source, resolution) {
  const [locale, canonical, prompt, wav, digest, length, transcript, model = pack.MODEL, kind] = values;
  assert(installer.LOCALES.includes(locale) && /^[a-z0-9_-]{1,128}$/.test(canonical)
    && prompt === `${canonical}-gemini-sulafat-${wav.slice(0, 16)}` && sha(wav) && sha(transcript)
    && /^md5-[A-Za-z0-9+/]{22}==$/.test(digest) && Number.isSafeInteger(length) && length > 44 && length <= 2 * 1024 * 1024,
  'invalid immutable asset row');
  assert(installed && installed.locale === locale && installed.canonical_id === canonical && installed.prompt_id === prompt
    && installed.document_id === `${locale}/${prompt}` && installed.attachment === `${prompt}.wav`
    && installed.sha256 === wav && revision(installed.revision), 'unmatched installed media revision');
  if (resolution) {
    assert(model === resolution.model && kind === resolution.source_kind && resolution.telephony_sha256 === wav
      && resolution.transcript_sha256 === transcript && resolution.provider === 'google-gemini' && resolution.voice === 'Sulafat', 'mixed model provenance differs');
  } else assert(model === pack.MODEL && kind === undefined, 'unexpected resolved model');
  return {_id: installed.document_id, _rev: installed.revision, prompt_id: prompt, language: locale,
    source_type: 'kazoo5_acdc_gemini_voice_installer', content_length: length, attachment: installed.attachment, digest,
    source_voice: {provider: 'google-gemini', model, voice: 'Sulafat', canonical_prompt_id: canonical,
      sha256: wav, transcript_sha256: transcript},
    source_cardinal_resolution: resolution ? {...resolution, resolved_asset_set_sha256: source.resolved_asset_set_sha256} : null,
    expected_path: '/system_media/' + encodeURIComponent(installed.document_id)};
}

function expectedDocuments(entries, receipt, preflight = installer.preflightAll) {
  const snapshots = preflight(entries);
  assert(receipt && receipt.schema_version === 1 && receipt.owner === 'kazoo5-acdc-cardinal-installer'
    && receipt.scope === 'all-locales' && ['VERIFY_ONLY', 'IMPORT_AND_VERIFY'].includes(receipt.mode)
    && receipt.database_verified === true && receipt.verified === 584 && receipt.count === 584
    && receipt.source_complete === true && receipt.catalog_sha256 === pack.CATALOG_HASH
    && receipt.approval_sha256 === installer.APPROVAL && receipt.cardinal_manifest_sha256 === snapshots[0].summary.cardinal_manifest_sha256
    && receipt.runtime_ready === false && receipt.five_language_release_ready === false
    && receipt.full_position_language_ready === false && receipt.listening_verified === false
    && receipt.queue_configuration_changed === false && receipt.preserves_210_inventory === true
    && Array.isArray(receipt.locales) && receipt.locales.length === 5
    && new Set(receipt.locales.map(r => r.locale)).size === 5, 'complete byte-verified five-locale receipt required');
  const expected = [];
  for (const snapshot of snapshots) {
    const source = snapshot.summary, actual = receipt.locales.find(r => r.locale === snapshot.locale);
    assert(actual && Object.keys(source).every(k => Object.hasOwn(actual, k) && same(source[k], actual[k]))
      && actual.mode === 'VERIFY_ONLY' && actual.created === 0 && actual.verified === source.count
      && actual.intro_installed_verified === true && Array.isArray(actual.installed) && actual.installed.length === source.count,
    'locale receipt differs from current source');
    assert(new Set(actual.installed.map(p => p.document_id)).size === source.count, 'duplicate installed identity');
    const {rows, intro} = mapRows(snapshot);
    const wanted = new Map(pack.plan(snapshot.locale).map(p => [p.id, p]));
    for (const values of rows) {
      const catalog = wanted.get(values[1]);
      assert(values[0] === snapshot.locale && catalog && catalog.transcript_sha256 === values[6], 'cross-locale or noncatalog recording');
      wanted.delete(values[1]);
      const proof = source.prompts.find(p => p.id === values[1]);
      expected.push(expectedRow(values, actual.installed.find(p => p.canonical_id === values[1]), source, proof.resolution));
    }
    assert(wanted.size === 0, 'missing catalog identity');
    if (intro) {
      const pin = importer.INTROS[snapshot.locale];
      assert(intro[0] === snapshot.locale && intro[1] === pin.canonical_id && intro[3] === pin.wav_sha256
        && intro[6] === pin.transcript_sha256, 'wrong reviewed intro');
      // Additive importer receipt field required: boolean availability alone
      // cannot pin the revision whose bytes were verified.
      expected.push(expectedRow(intro, actual.intro_installed, source));
    }
  }
  assert(expected.length === DOCS && new Set(expected.map(e => e._id)).size === DOCS, 'exact owned584+2 scope required');
  return expected.sort((a, b) => a._id.localeCompare(b._id, 'en'));
}

function render(template, expected, mode, node, sidecar) {
  assert(['activate', 'check'].includes(mode) && nodeName(node) && expected.length === DOCS
    && new Set(expected.map(e => e._id)).size === DOCS, 'invalid mapping operation');
  assert(sidecar && typeof sidecar.path === 'string' && sidecar.path.length <= 512
    && /^\/(?:[A-Za-z0-9_.-]+\/)*expected\.json$/.test(sidecar.path)
    && path.resolve(sidecar.path) === sidecar.path && Number.isSafeInteger(sidecar.gid) && sidecar.gid >= 0,
  'explicit protected sidecar identity required');
  const bytes = Buffer.from(JSON.stringify(expected));
  assert(bytes.length > 0 && bytes.length <= 8 * 1024 * 1024, 'bounded expected inventory required');
  for (const [key, value] of Object.entries({NODE: node, MODE: mode,
    EXPECTED_PATH: sidecar.path, EXPECTED_GID: String(sidecar.gid),
    EXPECTED_SHA256_BASE64: crypto.createHash('sha256').update(bytes).digest('base64')})) {
    const marker = '@@' + key + '@@'; assert.equal(template.split(marker).length, 2, 'template marker mismatch');
    template = template.replace(marker, value);
  }
  assert(!template.includes('@@') && Buffer.byteLength(template) < 16384, 'unbounded mapping script');
  return template;
}

function validateResult(stdout, mode) {
  const match = stdout.replace(/\s/g, '').match(/^\{ok,\{ok,\{cardinal_mapping_verified,(activate|check),586,1172,(\d+),no_database_writes\}\}\}$/);
  assert(match && match[1] === mode && Number(match[2]) <= MAPPINGS
    && (mode !== 'check' || Number(match[2]) === 0), 'unconfirmed cardinal mapping result');
  return Number(match[2]);
}

function execute(options, {spawn = cp.spawnSync, entries, receipt, temporaryParent = os.tmpdir(), templateDirectory = __dirname} = {}) {
  assert(process.getuid() === 0, 'protected SUP requires root');
  const selected = entries || installer.releasePlans(undefined, undefined, options.resolution);
  const sourceReceipt = receipt || protectedReceipt(options.receipt);
  const expected = expectedDocuments(selected, sourceReceipt);
  const template = installer.checkedHeader(path.join(templateDirectory, 'refresh-acdc-cardinal-mappings.erl.template'), 65536);
  const group = spawn('getent', ['group', 'kazoo'], {encoding: 'utf8', timeout: 5000, maxBuffer: 4096});
  assert(group.status === 0 && /^kazoo:[^:]*:\d+:/.test(group.stdout), 'Kazoo group unavailable');
  const gid = Number(group.stdout.split(':')[2]); assert(Number.isSafeInteger(gid) && gid > 0);
  const directory = fs.mkdtempSync(path.join(temporaryParent, 'kazoo-cardinal-map.'));
  fs.chownSync(directory, 0, gid); fs.chmodSync(directory, 0o750);
  const file = path.join(directory, 'verify.erl');
  const expectedFile = path.join(directory, 'expected.json');
  try {
    const code = render(template, expected, options.mode, options.node, {path: expectedFile, gid});
    fs.writeFileSync(expectedFile, JSON.stringify(expected), {flag: 'wx', mode: 0o640});
    fs.chownSync(expectedFile, 0, gid); fs.chmodSync(expectedFile, 0o640);
    fs.writeFileSync(file, code, {flag: 'wx', mode: 0o640}); fs.chownSync(file, 0, gid); fs.chmodSync(file, 0o640);
    // Recheck source and receipt immediately before handing off. No command
    // includes the Erlang cookie, CouchDB credential, provider key or payload.
    assert(same(expectedDocuments(selected, receipt || protectedReceipt(options.receipt)), expected), 'mapping prerequisites changed');
    // SUP -t is seconds; the child-process timeout below is milliseconds.
    const result = spawn('/usr/local/bin/sup', ['-t', '180', '-n', options.node.split('@')[0], '-e', 'true',
      'file', 'script', JSON.stringify(file)], {encoding: 'utf8', timeout: 190000, maxBuffer: 16384});
    assert(!result.error && result.status === 0, 'mapping RPC failed or timed out; completion is unconfirmed');
    const missing = validateResult(result.stdout, options.mode);
    assert(same(expectedDocuments(selected, receipt || protectedReceipt(options.receipt)), expected), 'mapping prerequisites changed after RPC');
    return {schema_version: 1, mode: options.mode, node: options.node, documents_verified: DOCS,
      mappings_verified: MAPPINGS, missing_before: missing, database_writes: false, queue_configuration_changed: false,
      runtime_language_capability_published: false, full_position_language_ready: false,
      five_language_release_ready: false, expected_inventory_sha256: hash(JSON.stringify(expected)),
      media_receipt_sha256: hash(JSON.stringify(sourceReceipt))};
  } finally {
    if (fs.existsSync(file)) fs.unlinkSync(file);
    if (fs.existsSync(expectedFile)) fs.unlinkSync(expectedFile);
    fs.rmdirSync(directory);
  }
}
module.exports = {parseArgs, protectedReceipt, mapRows, expectedRow, expectedDocuments, render, validateResult, execute};
if (require.main === module) {
  try { console.log(JSON.stringify(execute(parseArgs(process.argv.slice(2))), null, 2)); }
  catch (_) { console.error('Cardinal mapping verification failed safely; completion is unconfirmed and no database write was requested.'); process.exitCode = 1; }
}
