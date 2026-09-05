#!/usr/bin/env node
'use strict';

// Offline only: mock the request boundary and never inspect real credentials.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');
const generator = require('./generate-acdc-gemini-samples.cjs');
const {catalog} = require('./acdc-language-catalog.cjs');
const {SampleError} = generator;
let count = 0;
function test(name, fn) { fn(); count++; console.log(`PASS ${name}`); }
function throwsCode(fn, code) { assert.throws(fn, error => error instanceof SampleError && error.code === code); }
function tone(rate, seconds = 1, amplitude = 8000) {
  const data = Buffer.alloc(Math.round(rate * seconds) * 2);
  for (let index = 0; index < data.length / 2; index++) data.writeInt16LE(Math.round(amplitude * Math.sin(2 * Math.PI * 440 * index / rate)), index * 2);
  return data;
}
function response(pcm = tone(24000)) { return {candidates: [{finishReason: 'STOP', content: {parts: [
  {inlineData: {mimeType: 'audio/L16;codec=pcm;rate=24000', data: pcm.toString('base64')}}
]}}]}; }
const fakeKey = 'AI' + 'za' + 'not-a-real-key-for-offline-testing-only';

async function main() {
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'acdc-gemini-samples-test.'));
  try {
    test('default and explicit plan cannot generate', () => {
      assert.equal(generator.parseOptions([]).generate, false);
      assert.equal(generator.parseOptions(['--plan']).generate, false);
      assert.equal(generator.parseOptions(['--dry-run', '--key-file', '/unread']).generate, false);
      throwsCode(() => generator.parseOptions(['--generate', '--plan']), 'CONFLICTING_MODES');
      throwsCode(() => generator.parseOptions(['--generate']), 'ABSOLUTE_KEY_PATH_REQUIRED');
      throwsCode(() => generator.parseOptions(['--generate', '--key-file', '/test']), 'ABSOLUTE_OUTPUT_PATH_REQUIRED');
      throwsCode(() => generator.parseOptions(['--output']), 'INVALID_OPTION_VALUE');
      throwsCode(() => generator.parseOptions(['--surprise']), 'UNKNOWN_OPTION');
    });
    test('exact five locale transcripts are from the catalog', () => {
      assert.deepEqual(generator.plan().map(sample => sample.locale), ['en-us', 'he-il', 'ar-sa', 'fr-fr', 'es-es']);
      for (const sample of generator.plan()) {
        assert.equal(sample.transcript, catalog(sample.locale).prompts.find(prompt => prompt.id === sample.id).text);
        assert.equal(sample.status, 'SAMPLE_NOT_APPROVED_NOT_DEPLOYED');
        const body = generator.requestBody(sample);
        assert.deepEqual(body.generationConfig.responseModalities, ['AUDIO']);
        assert.equal(body.generationConfig.speechConfig.voiceConfig.prebuiltVoiceConfig.voiceName, 'Sulafat');
        assert(body.contents[0].parts[0].text.includes(sample.transcript));
      }
      throwsCode(() => generator.requestBody({...generator.plan()[0], transcript: 'Caller controlled text'}), 'UNAPPROVED_SAMPLE_TEXT');
      assert.equal(new URL(generator.ENDPOINT).origin, 'https://generativelanguage.googleapis.com');
    });
    test('ambiguous or absent keys fail without including secret content', () => {
      assert.equal(generator.extractKey(`Gemini key: ${fakeKey}\n${fakeKey}`), fakeKey);
      throwsCode(() => generator.extractKey('no key'), 'EXPECTED_ONE_GEMINI_KEY');
      throwsCode(() => generator.extractKey(fakeKey + '\n' + fakeKey + 'different'), 'EXPECTED_ONE_GEMINI_KEY');
    });
    test('credential files require protected mode and no symlinks', () => {
      const file = path.join(scratch, 'fixture-key');
      fs.writeFileSync(file, `Wrapper: ${fakeKey}`, {mode: 0o600});
      assert.equal(generator.readProtectedKey(file), fakeKey);
      fs.chmodSync(file, 0o644);
      throwsCode(() => generator.readProtectedKey(file), 'KEY_PERMISSIONS_TOO_OPEN');
      fs.chmodSync(file, 0o600);
      fs.symlinkSync(file, path.join(scratch, 'fixture-key-link'));
      throwsCode(() => generator.readProtectedKey(path.join(scratch, 'fixture-key-link')), 'KEY_NOT_REGULAR_FILE');
      throwsCode(() => generator.readProtectedKey(scratch), 'KEY_NOT_REGULAR_FILE');
    });
    test('output cannot overwrite files or use live paths and symlink parents', () => {
      throwsCode(() => generator.validateOutputTarget(scratch), 'OUTPUT_ALREADY_EXISTS');
      throwsCode(() => generator.validateOutputTarget('/var/www/new-samples'), 'LIVE_OUTPUT_FORBIDDEN');
      fs.symlinkSync(scratch, path.join(scratch, 'directory-link'));
      throwsCode(() => generator.validateOutputTarget(path.join(scratch, 'directory-link', 'new')), 'OUTPUT_PARENT_NOT_REAL_DIRECTORY');
      generator.validateOutputTarget(path.join(scratch, 'new-output'));
    });
    test('accept raw PCM only with complete single-candidate audio format', () => {
      assert.deepEqual(generator.extractPcm(response()), tone(24000));
      const incomplete = response(); incomplete.candidates[0].finishReason = 'MAX_TOKENS';
      throwsCode(() => generator.extractPcm(incomplete), 'AUDIO_GENERATION_NOT_COMPLETE');
      const wrong = response(); wrong.candidates[0].content.parts[0].inlineData.mimeType = 'audio/mp3';
      throwsCode(() => generator.extractPcm(wrong), 'UNSUPPORTED_AUDIO_MIME');
      const rate = response(); rate.candidates[0].content.parts[0].inlineData.mimeType = 'audio/L16;codec=pcm;rate=48000';
      throwsCode(() => generator.extractPcm(rate), 'UNSUPPORTED_AUDIO_FORMAT');
      const duplicate = response(); duplicate.candidates[0].content.parts.push(duplicate.candidates[0].content.parts[0]);
      throwsCode(() => generator.extractPcm(duplicate), 'EXPECTED_ONE_AUDIO_PART');
      const corrupt = response(); corrupt.candidates[0].content.parts[0].inlineData.data = 'not base64';
      throwsCode(() => generator.extractPcm(corrupt), 'INVALID_AUDIO_BASE64');
      throwsCode(() => generator.extractPcm({}), 'NO_AUDIO_CANDIDATE');
    });
    test('WAV validates format duration clipping and silence without accelerating', () => {
      for (const rate of [8000, 24000]) {
        const metrics = generator.inspectWave(generator.makeWave(tone(rate), rate), rate);
        generator.validateMetrics(metrics); assert.equal(metrics.duration_seconds, 1);
      }
      throwsCode(() => generator.validateMetrics(generator.inspectWave(generator.makeWave(tone(8000, 10.1), 8000), 8000)), 'AUDIO_EXCEEDS_TEN_SECOND_SUCCESS_TIMEOUT');
      throwsCode(() => generator.validateMetrics(generator.inspectWave(generator.makeWave(tone(8000, 0.1), 8000), 8000)), 'AUDIO_TOO_SHORT');
      throwsCode(() => generator.validateMetrics(generator.inspectWave(generator.makeWave(Buffer.alloc(16000), 8000), 8000)), 'AUDIO_SILENT_OR_TOO_QUIET');
      const clipped = tone(8000); clipped.writeInt16LE(-32768, 500);
      throwsCode(() => generator.validateMetrics(generator.inspectWave(generator.makeWave(clipped, 8000), 8000)), 'AUDIO_CLIPPED');
      throwsCode(() => generator.inspectWave(generator.makeWave(tone(8000), 8000).subarray(0, 100), 8000), 'INVALID_WAVE_CONTAINER');
      throwsCode(() => generator.inspectWave(generator.makeWave(tone(8000), 8000), 24000), 'REQUIRE_PCM16_MONO_EXPECTED_RATE');
    });
    test('default CLI never reads even an invalid supplied credential path', () => {
      const run = cp.spawnSync(process.execPath, [path.join(__dirname, 'generate-acdc-gemini-samples.cjs'),
        '--key-file', path.join(scratch, 'does-not-exist')], {encoding: 'utf8', timeout: 10000});
      assert.equal(run.status, 0); assert.equal(run.stderr, '');
      assert.equal(run.stdout.trim().split('\n').length, 5);
      assert(run.stdout.includes('PLAN_ONLY_NO_API_CALLS'));
    });

    const common = {
      readProtectedKey: () => fakeKey, checkSox: () => {}, output: () => {},
      resample: (_source, destination) => fs.writeFileSync(destination, generator.makeWave(tone(8000), 8000))
    };
    let requests = 0, inFlight = 0;
    const complete = await generator.generateSamples({generate: true, keyFile: '/fake-unused-key', output: path.join(scratch, 'complete')}, {
      ...common, requestSpeech: async (body, key) => {
        assert.equal(key, fakeKey); assert.equal(inFlight, 0); inFlight++; requests++;
        await new Promise(resolve => setImmediate(resolve)); inFlight--; return response();
      }
    });
    test('exactly five sequential requests retain five pairs of hashed review-only WAVs', () => {
      assert.equal(requests, 5); assert.equal(complete.complete, false); assert.equal(complete.sample_set_complete, true);
      assert.equal(complete.scope, 'preview'); assert.equal(complete.approved, false);
      assert.equal(complete.runtime_ready, false); assert.equal(complete.deployed, false);
      assert.equal(complete.audio_listening_review, false); assert.equal(complete.native_speaker_review, false);
      assert.equal(complete.samples.length, 5); assert.equal(complete.retries, 0);
      const json = fs.readFileSync(path.join(scratch, 'complete', 'manifest.json'), 'utf8');
      assert(!json.includes(fakeKey)); assert(!json.includes('/fake-unused-key'));
      for (const sample of complete.samples) for (const variant of ['master', 'telephony']) {
        assert.equal(sample[variant].sha256.length, 64);
        assert(fs.statSync(path.join(scratch, 'complete', sample[variant].file)).isFile());
      }
      for (const sample of complete.samples) {
        assert(sample.synthesis_instruction.endsWith(sample.transcript));
        assert.equal(sample.request_body_sha256.length, 64);
        assert.equal(sample.raw_pcm_sha256.length, 64);
        assert.equal(sample.source_audio_mime, 'audio/L16;codec=pcm;rate=24000');
      }
    });

    const soxComplete = await generator.generateSamples({generate: true, keyFile: '/fake-unused-key', output: path.join(scratch, 'sox')}, {
      readProtectedKey: () => fakeKey, output: () => {}, requestSpeech: async () => response()
    });
    test('real offline SoX resampling produces validated 8kHz mono PCM16 without duration changes', () => {
      assert.equal(soxComplete.samples.length, 5);
      assert.match(soxComplete.conversion.version, /^[0-9.]+$/);
      for (const sample of soxComplete.samples) {
        assert.equal(sample.master.sample_rate_hz, 24000);
        assert.equal(sample.telephony.sample_rate_hz, 8000);
        assert.equal(sample.master.duration_seconds, sample.telephony.duration_seconds);
        assert.equal(sample.telephony.clipped_samples, 0);
        assert.equal(sample.telephony.bits_per_sample, 16);
      }
    });

    requests = 0;
    await assert.rejects(generator.generateSamples({generate: true, keyFile: '/not-read', output: path.join(scratch, 'failed')}, {
      ...common, requestSpeech: async () => {
        requests++; if (requests === 2) throw new Error('Sensitive upstream response ' + fakeKey); return response();
      }
    }), error => error.code === 'LOCAL_OPERATION_FAILED');
    test('first failure stops without paid retries and preserves completed sample and safe partial manifest', () => {
      assert.equal(requests, 2);
      const text = fs.readFileSync(path.join(scratch, 'failed', 'manifest.json'), 'utf8');
      const saved = JSON.parse(text);
      assert.equal(saved.complete, false); assert.equal(saved.generation_status, 'STOPPED_ON_FIRST_FAILURE');
      assert.equal(saved.samples.length, 2); assert.equal(saved.samples[0].generation_status, 'GENERATED_QA_PASSED');
      assert.equal(saved.samples[1].failure_code, 'LOCAL_OPERATION_FAILED');
      assert(!text.includes(fakeKey)); assert(!text.includes('Sensitive upstream'));
    });
    requests = 0;
    await assert.rejects(generator.generateSamples({generate: true, keyFile: '/not-read', output: path.join(scratch, 'overlong')}, {
      ...common, requestSpeech: async () => { requests++; return response(tone(24000, 10.2)); }
    }), error => error.code === 'AUDIO_EXCEEDS_TEN_SECOND_SUCCESS_TIMEOUT');
    test('overlong generated master remains inspectable and is never silently time-stretched', () => {
      assert.equal(requests, 1);
      const saved = JSON.parse(fs.readFileSync(path.join(scratch, 'overlong', 'manifest.json'), 'utf8'));
      assert.equal(saved.samples[0].master.duration_seconds, 10.2);
      assert.equal(saved.samples[0].telephony, undefined);
      assert.equal(saved.complete, false);
    });
    await assert.rejects(generator.generateSamples({generate: true, keyFile: '/not-read', output: path.join(scratch, 'complete')}, {
      ...common, readProtectedKey: () => { throw new Error('Must not read credentials'); },
      requestSpeech: () => { throw new Error('Must not contact API'); }
    }), error => error.code === 'OUTPUT_ALREADY_EXISTS');
    count++; console.log('PASS existing output is rejected before credentials or API calls');
    console.log(`${count} offline Gemini sample test groups passed; zero provider requests.`);
  } finally {
    // Only this exact test-owned mkdtemp tree; never an input/output supplied by an operator.
    fs.rmSync(scratch, {recursive: true, force: false});
  }
}
main().catch(error => { console.error(error.stack); process.exitCode = 1; });
