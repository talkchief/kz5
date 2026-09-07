#!/usr/bin/env node
'use strict';
// Offline: checked-in audio only, no database, provider or service access.
const assert = require('node:assert/strict'), crypto = require('node:crypto');
const {assetFor, ulaw, validateReceipt} = require('./test-fixtures/callback-gemini-reference.cjs');
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const asset = assetFor('acdc-callback-success'), referenceHash = hash(ulaw(asset.bytes));
const receipt = {schema_version: 1, voice_family: 'gemini-sulafat',
    document_id: asset.id, attachment_name: asset.attachment, installed_wav_sha256: asset.sha256,
    reference_ulaw_sha256: referenceHash, canonical_prompt_id: asset.canonical_id, revision: '1-' + 'a'.repeat(32)};
assert.equal(validateReceipt(receipt, referenceHash), 'gemini-sulafat');
let checks = 1;
for (const [key, value] of [['schema_version', 2], ['voice_family', 'legacy'],
    ['document_id', asset.id + '0'], ['attachment_name', 'other.wav'],
    ['installed_wav_sha256', 'b'.repeat(64)], ['reference_ulaw_sha256', 'b'.repeat(64)],
    ['canonical_prompt_id', 'acdc-callback-offer-6'], ['revision', 'bad'],
    ['revision', '0-' + 'a'.repeat(32)]]) {
    assert.throws(() => validateReceipt({...receipt, [key]: value}, referenceHash)); checks++;
}
assert.throws(() => validateReceipt({...receipt, reference_ulaw_sha256: 'c'.repeat(64)}, 'c'.repeat(64)));
checks++;
const legacy = {document_id: 'en-us/acdc-callback-success', attachment_name: 'acdc-callback-success.wav',
    installed_wav_sha256: 'd'.repeat(64), reference_ulaw_sha256: 'e'.repeat(64)};
assert.equal(validateReceipt(legacy, legacy.reference_ulaw_sha256), 'legacy'); checks++;
assert.throws(() => validateReceipt(legacy, 'f'.repeat(64))); checks++;
assert.throws(() => validateReceipt({...legacy, attachment_name: 'wrong.wav'}, legacy.reference_ulaw_sha256)); checks++;
assert.throws(() => assetFor('../private')); checks++;
// Execute the actual retry argument/preflight function with a synthetic verifier.
// No state helper, API, SIP, provider, real credentials or temporary files.
const fs = require('node:fs'), path = require('node:path'), {spawnSync} = require('node:child_process');
const retrySource = fs.readFileSync(path.join(__dirname, 'test-acdc-callback-retry.sh'), 'utf8');
const argsFunction = retrySource.slice(retrySource.indexOf('retry_args() {'), retrySource.indexOf('\nretry_snapshot() {'));
assert(argsFunction.startsWith('retry_args() {')); checks++;
for (const [proof, expected] of [
    ['{"voice_family":"gemini-sulafat"}', 0],
    ['{"voice_family":"legacy"}', 78], ['{}', 78], ['not-json', 78]
]) {
    const result = spawnSync('/usr/bin/bash', ['-c', `set -euo pipefail
CALLBACK_PREPARE=false; CALLBACK_LIVE=false; KEEP_FIXTURE=false
CALLBACK_TEST_TRANSPORT=external; RETRY_REGISTRATION_MODE=confirm-current
retry_script_dir=/synthetic; RETRY_REFERENCE=
die() { exit 78; }
validate_protected_file() { :; }
node() { printf '%s\\n' "$FIXTURE_PROOF"; }
${argsFunction}
retry_args --prepare-only --confirmation-reference "$1"
`, 'fixture', __filename], {env: {PATH: '/usr/bin:/bin', FIXTURE_PROOF: proof}, timeout: 5000, encoding: 'utf8'});
    assert.ifError(result.error); assert.equal(result.status, expected); checks += 2;
}
console.log('PASS ' + checks + ' callback Gemini reference identity/conversion and legacy compatibility checks');
