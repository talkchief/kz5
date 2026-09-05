#!/usr/bin/env node
'use strict';
const assert = require('node:assert/strict'), fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const fixed = require('./generate-acdc-gemini-fixed-pack.cjs'), samples = require('./generate-acdc-gemini-samples.cjs');
const extra = require('./generate-acdc-gemini-completion-pack.cjs');
const fakeKey = 'AI' + 'za' + 'offline-test-not-a-real-provider-key';
function pcm(rate) { const b = Buffer.alloc(rate); for (let i = 0; i < rate / 2; i++) b.writeInt16LE(Math.round(8000 * Math.sin(2 * Math.PI * 440 * i / rate)), i * 2); return b; }
function response() { return {modelVersion: samples.MODEL, candidates: [{finishReason: 'STOP', content: {parts: [
  {inlineData: {mimeType: 'audio/L16;codec=pcm;rate=24000', data: pcm(24000).toString('base64')}}]}}]}; }
const dependencies = {readProtectedKey: () => fakeKey, conversionVersion: () => '14.4.2', checkSox: () => '14.4.2',
  resample: (_source, file) => fs.writeFileSync(file, samples.makeWave(pcm(8000), 8000), {flag: 'wx'}),
  requestSpeech: async () => response(), output: () => {}, backoff: async () => {}};
const code = wanted => error => error instanceof samples.SampleError && error.code === wanted;
async function main() {
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'kazoo-acdc-gemini-completion-test-'));
  try {
    assert.equal(extra.DIGITS.length, 20);
    assert(extra.DIGITS.every(p => /acdc-number-[0-9]$/.test(p.id)));
    assert(extra.requestBody(extra.DIGITS[0]).contents[0].parts[0].text.includes('Modern Standard Arabic'));
    assert(extra.requestBody(extra.DIGITS[10]).contents[0].parts[0].text.includes('Israeli Hebrew'));
    assert.equal(extra.retryable('GEMINI_HTTP_401'), false); assert.equal(extra.retryable('GEMINI_HTTP_403'), false);
    assert.equal(extra.retryable('GEMINI_HTTP_400'), false); assert.equal(extra.retryable('GEMINI_HTTP_429'), true);
    console.log('PASS exact native-language digit0–9 scope and nonretryable authentication/access failures');
    const preview = path.join(scratch, 'previews'), base = path.join(scratch, 'fixed');
    await samples.generateSamples({generate: true, keyFile: '/not-read', output: preview}, dependencies);
    const baseOptions = {generate: true, concurrency: 1, keyFile: '/not-read', output: base, reuseSamples: preview};
    let count = 0;
    await assert.rejects(fixed.generatePack(baseOptions, {...dependencies, requestSpeech: async () => {
      if (++count === 2) throw new samples.SampleError('AUDIO_GENERATION_NOT_COMPLETE'); return response();
    }}), code('AUDIO_GENERATION_NOT_COMPLETE'));
    await assert.rejects(fixed.generatePack({...baseOptions, resume: true}, dependencies), code('INCOMPLETE_PACK_REQUIRES_SEPARATE_RETRY_AUTHORIZATION'));
    const target = path.join(scratch, 'extras'), opts = {generate: true, keyFile: '/not-read', output: target, fixedPack: base};
    let requests = 0; const pauses = [];
    const manifest = await extra.generate(opts, {...dependencies, backoff: async ms => pauses.push(ms), requestSpeech: async () => {
      requests++; if (requests === 2) throw new samples.SampleError('GEMINI_HTTP_503'); return response();
    }});
    assert.equal(requests, 22); assert.equal(manifest.initial_digit_requests, 20); assert.equal(manifest.retry_requests, 2);
    assert(pauses.every(ms => ms >= 1000 && ms <= 8000)); assert.equal(manifest.digits_complete, true);
    assert.equal(manifest.complete, false); assert.equal(manifest.runtime_ready, false); assert.equal(manifest.deployed, false);
    assert.equal(extra.verifiedAssets(base, target).length, 165);
    assert.equal(fixed.readManifest(base).requests_reserved + manifest.initial_digit_requests + manifest.retry_requests, 162);
    assert(manifest.prompts.some(p => p.attempts.some(a => a.failure_code === 'GEMINI_HTTP_503')));
    assert(!fs.readFileSync(path.join(target, 'manifest.json'), 'utf8').includes(fakeKey));
    console.log('PASS bounded retry history, preserved fixed failure,20 digits,165 verified effective assets and unchanged runtime gates');
    await extra.generate({...opts, resume: true}, {...dependencies, readProtectedKey: () => { throw Error('must not read key'); },
      requestSpeech: () => { throw Error('must not call provider'); }});
    console.log('PASS completed completion-pack resume never rereads credentials or regenerates good audio');
    let unauthorized = 0;
    await assert.rejects(extra.generate({...opts, output: path.join(scratch, 'unauthorized')}, {...dependencies, requestSpeech: async () => {
      unauthorized++; throw new samples.SampleError('GEMINI_HTTP_401');
    }}), code('GEMINI_HTTP_401'));
    assert.equal(unauthorized, 1);
    console.log('PASS401 stops after one request with no automatic retry');
    await assert.rejects(extra.generate({...opts, output: path.join(scratch, 'unauthorized'), resume: true},
      {...dependencies, requestSpeech: async () => { unauthorized++; return response(); }}), code('NONRETRYABLE_PROVIDER_FAILURE'));
    assert.equal(unauthorized, 1);
    console.log('PASS explicit resume also refuses another provider request after a recorded authentication failure');
    let failed = 0;
    const exhaustedDir = path.join(scratch, 'exhausted');
    await assert.rejects(extra.generate({...opts, output: exhaustedDir}, {...dependencies, requestSpeech: async () => {
      failed++; throw new samples.SampleError('GEMINI_HTTP_503');
    }}), code('COMPLETION_RETRY_BUDGET_EXHAUSTED'));
    assert.equal(failed, 5); assert.equal(extra.readManifest(exhaustedDir).retry_requests, 5);
    console.log('PASS shared five-retry ceiling cannot be exceeded despite persistent provider failure');
    console.log('6 completion-pack offline test groups passed; zero provider requests.');
  } finally { fs.rmSync(scratch, {recursive: true, force: false}); }
}
main().catch(error => { console.error(error.stack); process.exitCode = 1; });
