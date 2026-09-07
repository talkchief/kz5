#!/usr/bin/env node
'use strict';

// Provider-free resolution of two reviewed whole Spanish number words.
// Never writes audio/manifests, requests speech, changes attempt status, imports
// media or opens runtime admission. Only the existing fixed offline SoX recipe
// runs, through acdc-cardinal-pack. Historical failures remain failures.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const pack = require('./acdc-cardinal-pack.cjs');
const OWNER = 'kazoo5-acdc-cardinal-exact-word-reuse', MAX_JSON = 8 * 1024 * 1024, MAX_WAV = 2 * 1024 * 1024;
const SOURCE_MANIFEST = 'dc041f104ab060cdd956ee237aaf004dea2edef1db070e654473a85c13f5b50b';
const ALLOWED = Object.freeze({
  4: Object.freeze({transcript: 'cuatro', entry: 'c27483814379ef0a9f2bfcc437e0992b50fea2ac11ff02da6268d88e0af2c3d6',
    master: '30f68cacb6c86dbbaaaa68a0f74a6624bef334b0e30107fc5123e004333d047d'}),
  9: Object.freeze({transcript: 'nueve', entry: '18fbb6865e85470288c1aa560058ad4bce27592ac0fd2f730fc01e6853e051f3',
    master: 'ddc73f17793a69ebdd8fadc9fb0223d252c904185bd25de427f3a6336c914d37'})
});
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const sha = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const plain = value => value !== null && typeof value === 'object' && !Array.isArray(value)
  && Object.getPrototypeOf(value) === Object.prototype;
class ReuseError extends Error { constructor(code) { super(code); this.name = 'CardinalReuseError'; this.code = code; } }
const check = (ok, code) => { if (!ok) throw new ReuseError(code); };
function keys(value, wanted) {
  check(plain(value) && Object.keys(value).sort().join(',') === [...wanted].sort().join(','), 'UNEXPECTED_REUSE_FIELDS');
}
function directory(root) {
  check(typeof root === 'string' && path.isAbsolute(root) && path.resolve(root) === root
    && root.split(path.sep).filter(Boolean).length >= 2, 'INVALID_REUSE_DIRECTORY');
  const s = fs.lstatSync(root);
  check(s.isDirectory() && !s.isSymbolicLink() && !(s.mode & 0o022)
    && fs.realpathSync(root) === root, 'INVALID_REUSE_DIRECTORY');
}
const sameFile = (a, b) => ['dev', 'ino', 'size', 'mode', 'nlink', 'mtimeMs', 'ctimeMs'].every(k => a[k] === b[k]);
function read(root, relative, maximum) {
  directory(root);
  check(typeof relative === 'string' && relative.length < 512 && !relative.startsWith('/')
    && relative.split('/').every(p => /^[A-Za-z0-9_.-]+$/.test(p) && p !== '.' && p !== '..'), 'INVALID_REUSE_PATH');
  const file = path.join(root, relative), parent = path.dirname(file); directory(parent);
  const before = fs.lstatSync(file);
  check(before.isFile() && !before.isSymbolicLink() && before.nlink === 1 && !(before.mode & 0o022)
    && before.size > 0 && before.size <= maximum, 'INVALID_REUSE_FILE');
  const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
  try {
    const opened = fs.fstatSync(fd); check(sameFile(before, opened), 'REUSE_INPUT_CHANGED');
    const bytes = Buffer.alloc(opened.size + 1); let size = 0, count;
    while (size < bytes.length && (count = fs.readSync(fd, bytes, size, bytes.length - size, null)) > 0) size += count;
    check(size === opened.size && sameFile(opened, fs.fstatSync(fd)) && sameFile(opened, fs.lstatSync(file))
      && fs.realpathSync(parent) === parent, 'REUSE_INPUT_CHANGED');
    return bytes.subarray(0, size);
  } finally { fs.closeSync(fd); }
}
function json(bytes) {
  try { return JSON.parse(bytes.toString('utf8')); } catch (_) { throw new ReuseError('INVALID_REUSE_JSON'); }
}
function wrap(pcm) {
  check(Buffer.isBuffer(pcm) && pcm.length > 0 && pcm.length % 2 === 0 && pcm.length <= MAX_WAV - 44, 'INVALID_DERIVED_PCM');
  const h = Buffer.alloc(44); h.write('RIFF'); h.writeUInt32LE(pcm.length + 36, 4); h.write('WAVEfmt ', 8);
  h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22); h.writeUInt32LE(8000, 24);
  h.writeUInt32LE(16000, 28); h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34); h.write('data', 36); h.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([h, pcm]);
}
function openResolution(options) {
  keys(options, ['cardinalDirectory', 'supplementalDirectory', 'aliasFile', 'aliasSha256']);
  const {cardinalDirectory, supplementalDirectory, aliasFile, aliasSha256} = options;
  check(typeof aliasFile === 'string' && path.isAbsolute(aliasFile) && path.resolve(aliasFile) === aliasFile
    && sha(aliasSha256), 'PINNED_ALIAS_FILE_REQUIRED');
  const aliasRoot = path.dirname(aliasFile), aliasName = path.basename(aliasFile);
  const aliasBytes = read(aliasRoot, aliasName, 32768); check(hash(aliasBytes) === aliasSha256, 'ALIAS_PIN_MISMATCH');
  const aliases = json(aliasBytes);
  keys(aliases, ['schema_version', 'owner', 'catalog_sha256', 'source_manifest_sha256', 'recipe_sha256',
    'review', 'aliases', 'runtime_ready', 'deployed', 'full_position_numeric_range_ready']);
  check(aliases.schema_version === 1 && aliases.owner === OWNER && aliases.catalog_sha256 === pack.CATALOG_HASH
    && aliases.source_manifest_sha256 === SOURCE_MANIFEST && aliases.recipe_sha256 === pack.digest(pack.RESAMPLING)
    && aliases.runtime_ready === false && aliases.deployed === false && aliases.full_position_numeric_range_ready === false,
  'REUSE_CONTRACT_CHANGED');
  keys(aliases.review, ['kind', 'decision', 'evidence_sha256', 'listening_verified']);
  check(aliases.review.kind === 'source-backed-engineering' && aliases.review.decision === 'ALLOW_EXACT_WHOLE_WORD_REUSE'
    && sha(aliases.review.evidence_sha256) && aliases.review.listening_verified === false, 'REUSE_REVIEW_REQUIRED');
  check(Array.isArray(aliases.aliases) && aliases.aliases.length === 2, 'EXACT_TWO_ALIASES_REQUIRED');
  const cardinalHash = hash(read(cardinalDirectory, 'manifest.json', MAX_JSON));
  const manifest = pack.readManifest(cardinalDirectory); // Original schema/accounting, including all failed attempts, untouched.
  const supplementalBytes = read(supplementalDirectory, 'manifest.json', MAX_JSON);
  check(hash(supplementalBytes) === SOURCE_MANIFEST, 'SUPPLEMENTAL_MANIFEST_CHANGED');
  const supplemental = json(supplementalBytes), sourceEntries = supplemental.prompts;
  check(supplemental.owner === 'kazoo5-acdc-gemini-supplemental-pack' && Array.isArray(sourceEntries), 'INVALID_SUPPLEMENTAL_SOURCE');
  const byId = new Map(manifest.prompts.map(e => [e.locale + '/' + e.id, e])), byAlias = new Map();
  const expected = new Map(pack.plan().map(e => [e.locale + '/' + e.id, e]));
  for (const alias of aliases.aliases) {
    keys(alias, ['target', 'source']);
    const t = alias.target, s = alias.source;
    keys(t, ['locale', 'id', 'transcript', 'transcript_sha256', 'catalog_record_sha256', 'context_sha256', 'failed_entry_sha256']);
    keys(s, ['locale', 'id', 'transcript_sha256', 'provider', 'model', 'voice', 'entry_sha256', 'master_file', 'master_sha256']);
    const id = t.locale + '/' + t.id, wanted = expected.get(id), number = wanted?.value, allowed = ALLOWED[number];
    check(wanted && t.locale === 'es-es' && allowed && wanted.role === `number-${number}`
      && !byAlias.has(id) && ['locale', 'id', 'transcript', 'transcript_sha256', 'catalog_record_sha256', 'context_sha256']
        .every(k => t[k] === wanted[k]) && t.transcript === allowed.transcript && sha(t.failed_entry_sha256), 'UNAPPROVED_REUSE_TARGET');
    const failed = byId.get(id);
    check(failed.generation_status === 'FAILED' && failed.attempts.length > 0
      && failed.attempts.every(a => a.status === 'FAILED') && pack.digest(failed) === t.failed_entry_sha256, 'FAILED_HISTORY_CHANGED');
    check(s.locale === 'es-es' && s.id === `acdc-number-${number}` && s.transcript_sha256 === t.transcript_sha256
      && s.provider === 'google-gemini' && s.model === pack.MODEL && s.voice === pack.VOICE
      && s.entry_sha256 === allowed.entry && s.master_sha256 === allowed.master
      && s.master_file === `es-es/acdc-number-${number}.master-24000.wav`, 'UNAPPROVED_REUSE_SOURCE');
    const matches = sourceEntries.filter(e => e.locale === s.locale && e.id === s.id);
    check(matches.length === 1, 'SOURCE_IDENTITY_NOT_UNIQUE'); const entry = matches[0];
    check(pack.digest(entry) === s.entry_sha256 && entry.transcript === t.transcript
      && entry.transcript_sha256 === t.transcript_sha256 && entry.generation_status === 'GENERATED_QA_PASSED'
      && entry.provider_finish_reason === 'STOP' && entry.provider === s.provider && entry.model === s.model && entry.voice === s.voice
      && entry.master.file === s.master_file && entry.master.sha256 === s.master_sha256, 'SOURCE_PROVENANCE_CHANGED');
    byAlias.set(id, alias);
  }
  function stable() {
    check(hash(read(cardinalDirectory, 'manifest.json', MAX_JSON)) === cardinalHash
      && hash(read(supplementalDirectory, 'manifest.json', MAX_JSON)) === SOURCE_MANIFEST
      && hash(read(aliasRoot, aliasName, 32768)) === aliasSha256, 'REUSE_INPUT_CHANGED');
  }
  function resolve(locale, id) {
    check(typeof locale === 'string' && typeof id === 'string' && expected.has(locale + '/' + id), 'UNKNOWN_CARDINAL_IDENTITY');
    stable(); const entry = byId.get(locale + '/' + id), alias = byAlias.get(locale + '/' + id);
    let master, telephony, source_kind, provenance;
    if (alias) {
      master = read(supplementalDirectory, alias.source.master_file, MAX_WAV);
      check(hash(master) === alias.source.master_sha256, 'SOURCE_MASTER_CHANGED');
      pack.technicalQa(pack.inspectWave(master, 24000));
      telephony = wrap(pack.resampleMaster(master));
      source_kind = 'reused_supplemental_master';
      provenance = {alias_manifest_sha256: aliasSha256, review_evidence_sha256: aliases.review.evidence_sha256,
        source_manifest_sha256: SOURCE_MANIFEST, source_entry_sha256: alias.source.entry_sha256,
        source_locale: alias.source.locale, source_id: alias.source.id,
        source_master_sha256: alias.source.master_sha256, failed_entry_sha256: alias.target.failed_entry_sha256};
    } else {
      check(entry.generation_status === 'QA_PASSED', 'CARDINAL_AUDIO_UNRESOLVED');
      const attempt = entry.attempts.at(-1);
      master = read(cardinalDirectory, attempt.master.file, MAX_WAV);
      telephony = read(cardinalDirectory, attempt.telephony.file, MAX_WAV);
      check(hash(master) === attempt.master.sha256 && hash(telephony) === attempt.telephony.sha256, 'GENERATED_AUDIO_CHANGED');
      source_kind = 'generated_cardinal';
      provenance = {cardinal_entry_sha256: pack.digest(entry), attempt: attempt.number, request_body_sha256: attempt.request_body_sha256};
    }
    const masterMetrics = pack.technicalQa(pack.inspectWave(master, 24000));
    const phoneMetrics = pack.technicalQa(pack.inspectWave(telephony, 8000)); stable();
    return {locale, id, transcript: entry.transcript, source_kind, master, telephony,
      provenance: {...provenance, cardinal_manifest_sha256: cardinalHash, catalog_sha256: pack.CATALOG_HASH,
        catalog_record_sha256: entry.catalog_record_sha256, transcript_sha256: entry.transcript_sha256,
        context_sha256: entry.context_sha256, provider: 'google-gemini', model: pack.MODEL, voice: pack.VOICE,
        master_sha256: masterMetrics.sha256, telephony_sha256: phoneMetrics.sha256,
        telephony_pcm_sha256: phoneMetrics.pcm_sha256, duration_seconds: phoneMetrics.duration_seconds,
        resampling_recipe_sha256: pack.digest(pack.RESAMPLING)},
      runtime_ready: false, listening_verified: false, provider_provenance_authenticated: false};
  }
  // Verify the only two aliases before reporting them resolved. No persistent
  // cache of caller-mutable audio; each later resolve rereads/rederives its bytes.
  for (const alias of byAlias.values()) resolve(alias.target.locale, alias.target.id);
  const generated = manifest.prompts.filter(e => e.generation_status === 'QA_PASSED').length;
  return Object.freeze({resolve,
    verifyTelephony(locale, id, bytes) {
      check(Buffer.isBuffer(bytes) && bytes.length > 0 && bytes.length <= MAX_WAV, 'INVALID_RESOLVED_WAVE');
      const result = resolve(locale, id); check(result.telephony.equals(bytes), 'RESOLVED_TELEPHONY_MISMATCH');
      return result.provenance;
    },
    summary() {
      stable(); return {schema_version: 1, catalog_sha256: pack.CATALOG_HASH, cardinal_manifest_sha256: cardinalHash,
        alias_manifest_sha256: aliasSha256, generated, reused: byAlias.size, unresolved: manifest.prompts.length - generated - byAlias.size,
        historical_requests_reserved: manifest.requests_reserved, historical_artifact_complete: manifest.artifact_complete,
        alias_scope_verified: true, runtime_ready: false, deployed: false, listening_verified: false,
        full_position_numeric_range_ready: false};
    }
  });
}
function main(argv) {
  check(argv.length === 8 && ['--cardinal-pack', '--supplemental-pack', '--alias-file', '--alias-sha256']
    .every((flag, index) => argv[index * 2] === flag), 'INVALID_READ_ONLY_OPTIONS');
  const result = openResolution({cardinalDirectory: argv[1], supplementalDirectory: argv[3], aliasFile: argv[5], aliasSha256: argv[7]});
  console.log(JSON.stringify(result.summary()));
}
module.exports = Object.freeze({OWNER, ReuseError, openResolution, main});
if (require.main === module) try { main(process.argv.slice(2)); } catch (_) {
  console.error('Cardinal reuse verification failed; no provider, write, import or runtime action was attempted.'); process.exitCode = 1;
}
