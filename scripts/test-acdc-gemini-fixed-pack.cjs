#!/usr/bin/env node
'use strict';

// Offline regression tests. Every provider boundary and key read is replaced.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');
const generator = require('./generate-acdc-gemini-fixed-pack.cjs');
const samples = require('./generate-acdc-gemini-samples.cjs');
let groups = 0;
const report = name => { groups++; console.log(`PASS ${name}`); };
const fakeKey = 'AI' + 'za' + 'offline-not-an-actual-provider-key';
function tone(rate, seconds = 0.5, amplitude = 8000) {
  const data = Buffer.alloc(Math.round(rate * seconds) * 2);
  for (let i = 0; i < data.length / 2; i++) data.writeInt16LE(Math.round(amplitude * Math.sin(2 * Math.PI * 440 * i / rate)), i * 2);
  return data;
}
function response(seconds = 0.5) { return {modelVersion: samples.MODEL, candidates: [{finishReason: 'STOP', content: {parts: [
  {inlineData: {mimeType: 'audio/L16;codec=pcm;rate=24000', data: tone(24000, seconds).toString('base64')}}
]}}]}; }
const mocked = {readProtectedKey: () => fakeKey, conversionVersion: () => '14.4.2', output: () => {},
  resample: (_source, destination) => fs.writeFileSync(destination, samples.makeWave(tone(8000), 8000), {flag: 'wx'}),
  requestSpeech: async () => response()};
const errorCode = code => error => error instanceof samples.SampleError && error.code === code;

async function main() {
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'kazoo-acdc-gemini-fixed-test-'));
  try {
    const fixed = generator.plan();
    assert.equal(fixed.length, 145); assert.equal(new Set(fixed.map(p => `${p.locale}/${p.id}`)).size, 145);
    for (const locale of samples.LOCALES) assert.equal(fixed.filter(p => p.locale === locale).length, 29);
    assert(fixed.every(p => !p.id.startsWith('acdc-number-') && !p.transcript.includes('[[')));
    const hebrew = fixed.find(p => p.locale === 'he-il'); assert(/[א-ת]/u.test(hebrew.transcript));
    assert(generator.requestBody(hebrew).contents[0].parts[0].text.endsWith(hebrew.transcript));
    assert.throws(() => generator.requestBody({...hebrew, transcript: 'unapproved'}), errorCode('UNAPPROVED_FIXED_TEXT'));
    report('exact 145 fixed native-text entries; no numeric or Hebrew phoneme submission');

    assert.throws(() => generator.options(['--concurrency', '3']), errorCode('CONCURRENCY_MUST_BE_ONE_OR_TWO'));
    assert.throws(() => generator.options(['--generate', '--plan']), errorCode('CONFLICTING_MODES'));
    assert.throws(() => generator.options(['--resume']), errorCode('RESUME_REQUIRES_GENERATE'));
    const dry = cp.spawnSync(process.execPath, [path.join(__dirname, 'generate-acdc-gemini-fixed-pack.cjs'), '--plan',
      '--key-file', path.join(scratch, 'does-not-exist')], {encoding: 'utf8', timeout: 10000});
    assert.equal(dry.status, 0); assert.equal(dry.stderr, ''); assert.match(dry.stdout, /PLAN_ONLY_NO_API_CALLS/);
    report('plan needs no credentials; generation and concurrency are explicit and bounded');

    const success = fixed.find(p => p.id === 'acdc-callback-success'), ordinary = fixed[0];
    assert.throws(() => generator.metrics(samples.makeWave(tone(24000, 10.1), 24000), 24000, success), errorCode('AUDIO_DURATION_OUT_OF_BOUNDS'));
    assert.throws(() => generator.metrics(samples.makeWave(tone(24000, 20.1), 24000), 24000, ordinary), errorCode('AUDIO_DURATION_OUT_OF_BOUNDS'));
    assert.throws(() => generator.metrics(samples.makeWave(Buffer.alloc(24000), 24000), 24000, ordinary), errorCode('AUDIO_SILENT_OR_TOO_QUIET'));
    const clipped = tone(24000); clipped.writeInt16LE(32767, 0);
    assert.throws(() => generator.metrics(samples.makeWave(clipped, 24000), 24000, ordinary), errorCode('AUDIO_CLIPPED'));
    report('ten/twenty-second limits, silence and even one clipped sample fail closed');

    const preview = path.join(scratch, 'previews');
    await samples.generateSamples({generate: true, keyFile: '/not-read', output: preview},
      {...mocked, checkSox: () => '14.4.2'});
    const completeDir = path.join(scratch, 'complete');
    const opts = output => ({generate: true, concurrency: 2, keyFile: '/not-read', output, reuseSamples: preview});
    let requests = 0, flight = 0, peak = 0;
    const complete = await generator.generatePack(opts(completeDir), {...mocked, requestSpeech: async (body, key) => {
      assert.equal(key, fakeKey); requests++; flight++; peak = Math.max(peak, flight);
      assert(!JSON.stringify(body).includes(fakeKey)); await new Promise(resolve => setImmediate(resolve)); flight--;
      return response();
    }});
    assert.equal(requests, 140); assert.equal(peak, 2); assert.equal(complete.prompts.length, 145);
    assert.equal(complete.prompts.filter(p => p.source === 'reused_preview').length, 5);
    assert.equal(complete.requests_reserved, 140); assert.equal(complete.fixed_set_complete, true);
    assert.equal(complete.complete, false); assert.equal(complete.runtime_ready, false); assert.equal(complete.deployed, false);
    assert.equal(complete.audio_listening_review, false); assert.equal(complete.native_speaker_review, false);
    assert.equal(complete.locales.filter(p => p.numeric_required === 2999).length, 2);
    const packed = fs.readFileSync(path.join(completeDir, 'manifest.json'), 'utf8');
    assert(!packed.includes(fakeKey)); assert(!packed.includes('/not-read'));
    assert.equal(generator.verifyPack(completeDir).fixed_prompts, 145);
    report('five hashed preview reuses plus exactly 140 bounded requests; complete fixed set never claims runtime/numeric/listening readiness');

    let touched = false;
    await generator.generatePack({...opts(completeDir), resume: true}, {...mocked,
      readProtectedKey: () => { touched = true; throw Error('must not read key'); },
      requestSpeech: () => { touched = true; throw Error('must not contact provider'); }});
    assert.equal(touched, false);
    report('completed pack resume verifies existing assets without credentials or paid regeneration');

    const lockPath = path.join(completeDir, '.generation.lock');
    fs.writeFileSync(lockPath, '', {flag: 'wx', mode: 0o600});
    const lockedManifest = path.join(completeDir, 'manifest.json'), validManifest = fs.readFileSync(lockedManifest);
    fs.writeFileSync(lockedManifest, 'not a manifest');
    await assert.rejects(generator.generatePack({...opts(completeDir), resume: true}, mocked), errorCode('GENERATION_LOCKED'));
    fs.writeFileSync(lockedManifest, validManifest); fs.unlinkSync(lockPath);
    report('resume locks before reading its reservation ledger; another active generator cannot produce a stale budget snapshot');

    const failedDir = path.join(scratch, 'partial'); let count = 0;
    await assert.rejects(generator.generatePack({...opts(failedDir), concurrency: 1}, {...mocked, requestSpeech: async () => {
      count++; if (count === 2) throw Error('upstream secret ' + fakeKey); return response();
    }}), errorCode('LOCAL_OPERATION_FAILED'));
    const partial = generator.readManifest(failedDir);
    assert.equal(partial.requests_reserved, 2); assert.equal(partial.prompts.length, 7);
    const priorHash = partial.prompts.find(p => p.source === 'new_request' && p.generation_status === 'GENERATED_QA_PASSED').master.sha256;
    let resumed = 0;
    await assert.rejects(generator.generatePack({...opts(failedDir), resume: true}, {...mocked, requestSpeech: async () => {
      resumed++; return response();
    }}), errorCode('INCOMPLETE_PACK_REQUIRES_SEPARATE_RETRY_AUTHORIZATION'));
    const after = generator.readManifest(failedDir);
    assert.equal(resumed, 138); assert.equal(after.requests_reserved, 140);
    assert(after.prompts.some(p => p.master && p.master.sha256 === priorHash));
    assert.equal(after.fixed_set_complete, false);
    assert(!fs.readFileSync(path.join(failedDir, 'manifest.json'), 'utf8').includes(fakeKey));
    await assert.rejects(generator.generatePack({...opts(failedDir), resume: true}, {...mocked,
      readProtectedKey: () => { throw Error('must not read key'); }}), errorCode('INCOMPLETE_PACK_REQUIRES_SEPARATE_RETRY_AUTHORIZATION'));
    report('failed requests count against persistent budget; resume preserves successes, skips failed attempts, never hides provider errors or retries');

    const overlongDir = path.join(scratch, 'overlong');
    await assert.rejects(generator.generatePack({...opts(overlongDir), concurrency: 1}, {...mocked,
      requestSpeech: async () => response(20.1)}), errorCode('AUDIO_DURATION_OUT_OF_BOUNDS'));
    const overlong = generator.readManifest(overlongDir).prompts.find(p => p.source === 'new_request');
    assert.equal(overlong.master.duration_seconds, 20.1); assert.equal(overlong.telephony, undefined);
    report('failed long master is preserved for inspection, never sped up or silently truncated');

    const first = complete.prompts[0], waveFile = path.join(completeDir, first.telephony.file);
    const original = fs.readFileSync(waveFile); fs.appendFileSync(waveFile, Buffer.from([0]));
    assert.throws(() => generator.verifyPack(completeDir), errorCode('INVALID_WAVE_CONTAINER'));
    fs.writeFileSync(waveFile, original);
    fs.renameSync(waveFile, waveFile + '.saved'); fs.symlinkSync(waveFile + '.saved', waveFile);
    assert.throws(() => generator.verifyPack(completeDir), errorCode('INVALID_OWNED_FILE'));
    fs.unlinkSync(waveFile); fs.renameSync(waveFile + '.saved', waveFile);
    report('tampered waveform and symlink substitution are rejected');

    const source = path.join(scratch, 'resample-master.wav'), delivery = path.join(scratch, 'resample-telephony.wav');
    fs.writeFileSync(source, samples.makeWave(tone(24000), 24000)); generator.resample(source, delivery);
    const converted = generator.metrics(fs.readFileSync(delivery), 8000, ordinary);
    assert.equal(converted.duration_seconds, 0.5); assert.equal(converted.clipped_samples, 0);
    report('real offline SoX conversion preserves duration and passes PCM16 mono 8kHz QA');
    console.log(`${groups} fixed-pack offline test groups passed; zero provider requests.`);
  } finally { fs.rmSync(scratch, {recursive: true, force: false}); }
}
main().catch(error => { console.error(error.stack); process.exitCode = 1; });
