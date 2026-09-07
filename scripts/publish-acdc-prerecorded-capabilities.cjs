#!/usr/bin/env node
'use strict';
// Explicit protected DEV publication, separate from the read-only probe.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto'), assert = require('node:assert/strict');
const probe = require('./probe-acdc-prerecorded-runtime.cjs');
const {assertLanguageCapabilities} = require('./validate-acdc-language-capabilities.cjs');
const TOP = ['schema_version', 'owner', 'node', 'account', 'started_at', 'finished_at', 'input_sha256', 'probe_script_sha256',
  'beam_manifest_sha256', 'beams', 'cardinal_receipt_sha256', 'fixed_receipt_sha256', 'installed_media_sha256',
  'expected_inventory_sha256', 'documents_verified', 'mappings_verified', 'number_cases', 'wait_cases',
  'position_playlist_cases', 'callback_prepare_cases', 'wait_playlist_cases', 'runtime_function_testable',
  'live_SIP_verified', 'native_listening_approved', 'full_language_ready', 'database_writes',
  'queue_configuration_changed', 'service_restarts', 'provider_requests', 'locales'];
function validateReceipt(r, now = Date.now()) {
  probe.exactKeys(r, TOP);
  assert(r.schema_version === 1 && r.owner === 'kazoo5-acdc-prerecorded-runtime-probe' && probe.validAccount(r.account)
    && typeof r.node === 'string' && r.node.length <= 255 && !/[\r\n]/.test(r.node)
    && /^[a-z][a-z0-9_]*@[A-Za-z0-9_.-]+$/.test(r.node), 'Wrong probe ownership/scope');
  for (const key of TOP.filter(k => k.endsWith('_sha256'))) assert(probe.validSha(r[key]), 'Invalid receipt pin');
  assert(['started_at', 'finished_at'].every(k => typeof r[k] === 'string' && r[k].length === 24
    && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(r[k])), 'Invalid receipt clock type');
  const begin = Date.parse(r.started_at), end = Date.parse(r.finished_at);
  assert(Number.isFinite(begin) && Number.isFinite(end) && begin <= end && end - begin <= 300000
    && end <= now && now - end <= 300000, 'Runtime evidence is stale or clock-invalid');
  assert.equal(r.installed_media_sha256, probe.sha(JSON.stringify({cardinal_receipt_sha256: r.cardinal_receipt_sha256,
    fixed_receipt_sha256: r.fixed_receipt_sha256})), 'Installed proof bundle differs');
  assert(r.runtime_function_testable === true && r.live_SIP_verified === false && r.native_listening_approved === false
    && r.full_language_ready === false && r.database_writes === false && r.queue_configuration_changed === false
    && r.service_restarts === false && r.provider_requests === 0, 'Probe must not claim unperformed operations');
  assert(r.documents_verified === 796 && r.mappings_verified === 1592 && r.position_playlist_cases === 95
    && r.callback_prepare_cases === 10 && r.wait_playlist_cases === 80, 'Incomplete measured inventory/cases');
  assert.deepEqual(r.number_cases, probe.NUMBERS); assert.deepEqual(r.wait_cases, probe.WAIT);
  assert(Array.isArray(r.beams) && r.beams.length === probe.MODULES.length);
  assert.deepEqual(r.beams.map(m => m.module).sort(), probe.MODULES.slice().sort());
  for (const m of r.beams) {
    probe.exactKeys(m, ['module', 'path', 'sha256']);
    assert(probe.absolute(m.path) && path.basename(m.path) === m.module + '.beam' && probe.validSha(m.sha256));
  }
  assert(Array.isArray(r.locales) && r.locales.length === 5);
  assert.deepEqual(r.locales.map(l => l.locale).sort(), Object.keys(probe.COUNTS).sort());
  for (const l of r.locales) {
    probe.exactKeys(l, ['locale', 'count', 'cardinal_map_sha256', 'fixed_map_sha256', 'source_catalog_sha256',
      'callback_count', 'wait_count', 'position_runtime_verified', 'callback_runtime_verified', 'wait_time_runtime_verified']);
    assert(l.count === probe.COUNTS[l.locale] && l.callback_count === 42 && l.wait_count === 10
      && l.position_runtime_verified === true && l.callback_runtime_verified === true && l.wait_time_runtime_verified === true);
    assert(['cardinal_map_sha256', 'fixed_map_sha256', 'source_catalog_sha256'].every(k => probe.validSha(l[k])));
  }
  assert(new Set(r.locales.map(l => l.fixed_map_sha256)).size === 1
    && new Set(r.locales.map(l => l.source_catalog_sha256)).size === 1, 'Inconsistent shared source pins');
  return r;
}
function capability(receipt, receiptSha, now = Date.now()) {
  validateReceipt(receipt, now); assert(probe.validSha(receiptSha));
  return assertLanguageCapabilities({schema_version: 2, backend_mode: 'prerecorded-cardinal-v1',
    generated_at: new Date(now).toISOString(), languages: Object.fromEntries(receipt.locales.map(l => [l.locale, {
      ready: false, selection_ready: true, position: true, wait_time: true, callback: true, native_speaker_review: false,
      position_installed_verified: true, callback_installed_verified: true,
      position_runtime_verified: true, callback_runtime_verified: true, wait_time_runtime_verified: true,
      numbers: 'prerecorded-cardinal', number_range: [0, 999999999], numeric_prompt_count: l.count, callback_prompt_count: 42,
      source_catalog_sha256: l.source_catalog_sha256, cardinal_map_sha256: l.cardinal_map_sha256,
      fixed_map_sha256: l.fixed_map_sha256, installed_media_sha256: receipt.installed_media_sha256,
      runtime_evidence_sha256: receiptSha, native_review_sha256: null
    }]))});
}
function parseArgs(args) {
  const out = {};
  for (let i = 0; i < args.length; i += 2) {
    const key = args[i], value = args[i + 1];
    assert(['--account', '--receipt', '--receipt-sha256', '--output', '--previous-sha256'].includes(key)
      && !Object.hasOwn(out, key.slice(2)) && typeof value === 'string' && !value.startsWith('--'), 'Invalid publication option');
    out[key.slice(2)] = value;
  }
  assert(probe.validAccount(out.account) && probe.absolute(out.receipt) && probe.absolute(out.output) && probe.validSha(out['receipt-sha256'])
    && (out['previous-sha256'] === 'absent' || probe.validSha(out['previous-sha256'])), 'Explicit publication and prior-state pins required');
  assert(out.output !== out.receipt, 'Evidence cannot be overwritten'); return out;
}
function publish(o) {
  assert(process.getuid() === 0, 'Protected publication requires root');
  probe.protectedParents(path.dirname(o.output));
  const raw = probe.readPinned(o.receipt, o['receipt-sha256'], 65536);
  const r = validateReceipt(JSON.parse(raw));
  assert(probe.validAccount(o.account) && r.account === o.account, 'Runtime receipt belongs to another explicit account');
  // The node was checked by the probe; this local recheck catches replaced
  // release files, not an unobserved hot reload. Serialize with deployment.
  probe.validateBeams({schema_version: 1, modules: r.beams});
  const next = Buffer.from(JSON.stringify(capability(r, o['receipt-sha256']), null, 2) + '\n');
  const lock = o.output + '.publish-lock', fd = fs.openSync(lock, 'wx', 0o600);
  let temporary;
  try {
    fs.writeFileSync(fd, JSON.stringify({owner: 'kazoo5-acdc-capability-publisher', pid: process.pid})); fs.fsyncSync(fd);
    let prior;
    if (o['previous-sha256'] === 'absent') assert(!fs.existsSync(o.output), 'Capability already exists');
    else {
      prior = probe.readPinned(o.output, o['previous-sha256'], 131072);
      const existing = assertLanguageCapabilities(JSON.parse(prior));
      assert(Object.values(existing.languages).every(l => !l.native_speaker_review), 'Existing native review needs explicit migration');
      const backup = o.output + '.before-' + o['previous-sha256'];
      if (fs.existsSync(backup)) probe.readPinned(backup, o['previous-sha256'], 131072);
      else probe.createEvidence(backup, prior);
    }
    probe.readPinned(o.receipt, o['receipt-sha256'], 65536); validateReceipt(r);
    temporary = path.join(path.dirname(o.output), '.acdc-capability-' + crypto.randomBytes(16).toString('hex'));
    const tf = fs.openSync(temporary, 'wx', 0o600);
    try { fs.writeFileSync(tf, next); fs.fchmodSync(tf, 0o644); fs.fsyncSync(tf); } finally { fs.closeSync(tf); }
    if (prior) {
      probe.readPinned(o.output, o['previous-sha256'], 131072);
      fs.renameSync(temporary, o.output); temporary = undefined;
    } else { fs.linkSync(temporary, o.output); fs.unlinkSync(temporary); temporary = undefined; }
    const directory = fs.openSync(path.dirname(o.output), 'r'); try { fs.fsyncSync(directory); } finally { fs.closeSync(directory); }
    probe.readPinned(o.output, probe.sha(next), 131072);
    return {path: o.output, sha256: probe.sha(next), selection_ready: true, full_language_ready: false,
      native_listening_approved: false, evidence_sha256: o['receipt-sha256']};
  } finally {
    fs.closeSync(fd); if (temporary) fs.unlinkSync(temporary); fs.unlinkSync(lock);
  }
}
module.exports = {validateReceipt, capability, parseArgs, publish};
if (require.main === module) {
  try { console.log(JSON.stringify(publish(parseArgs(process.argv.slice(2))))); }
  catch (_) { console.error('Protected capability publication failed; completion is unconfirmed.'); process.exitCode = 1; }
}
