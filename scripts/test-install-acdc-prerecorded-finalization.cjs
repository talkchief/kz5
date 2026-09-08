#!/usr/bin/env node
'use strict';
// Offline orchestration fixtures only: execute the exact main-SH JS with an
// in-memory filesystem and stubbed frozen probe/publisher. No RPC, key, BEAM,
// service, database, provider or real filesystem write is possible.
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm');
const assert = require('node:assert/strict'), crypto = require('node:crypto');
const capabilitySchema = require('./validate-acdc-language-capabilities.cjs');
const source = fs.readFileSync(path.join(__dirname, 'install-kazoo5.sh'), 'utf8');
const begin = '// ACDC_PRERECORDED_FINALIZATION_BEGIN', end = '// ACDC_PRERECORDED_FINALIZATION_END';
assert.equal(source.split(begin).length, 2); assert.equal(source.split(end).length, 2);
const code = source.split(begin)[1].split(end)[0];
new vm.Script(code);
assert.match(source, /activate_acdc_voice_mappings\n    finalize_acdc_prerecorded_capabilities --install\n    verify_kazoo_apps/);
assert.match(source, /verify_acdc_language_packs\n    finalize_acdc_prerecorded_capabilities --check/);
assert.match(source, /\[\[ \$VERIFY_ONLY != true \]\] \|\| die 'Verification cannot publish prerecorded capability'/);
assert.match(source, /verify_kazoo_current_build\n        account=\$\(configured_master_account_id\)/);
const hash = b => crypto.createHash('sha256').update(b).digest('hex');
const modules = ['acdc_announcements', 'acdc_callback_caller', 'acdc_cardinal_media', 'acdc_cardinal_prompts',
    'acdc_gemini_prompts', 'acdc_language', 'acdc_wait_time_media', 'cb_acdc_queue_editor', 'cf_acdc_member', 'kz_media_map', 'media_map'];
const account = '1234567890abcdef1234567890abcdef', target = '/fixture/config/acdc/language-capabilities.json';
const legacyPath = '/fixture/web/apps/acdc/language-capabilities.json';
assert.match(source, /"\$\(acdc_cardinal_index_pin\)" "\$MONSTER_UI_WEB_ROOT" <<'JS'/);
function fixture() {
    const files = new Map(), events = [], state = {configured: 'undefined', counter: 0, webRoot: '/fixture/web'};
    const put = (f, b) => files.set(f, Buffer.isBuffer(b) ? b : Buffer.from(typeof b === 'string' ? b : JSON.stringify(b)));
    put(target, capabilitySchema.legacyLanguageCapabilities('2020-01-01T00:00:00.000Z'));
    // Deliberately exceed the generic128KiB cap: the real cardinal receipt is
    // approximately1.6MiB and requires the explicit bounded8MiB input allowance.
    put('/usr/local/share/kazoo5-installer/acdc-cardinal-media.json', Buffer.alloc(1600000, 32));
    put('/usr/local/share/kazoo5-installer/acdc-gemini-media.json', '{}');
    put('/fixture/root/applications/acdc/src/acdc_gemini_map.hrl', 'synthetic-fixed-map');
    for (const module of modules) {
        const area = module === 'kz_media_map' ? 'core/kazoo_media' : module === 'media_map' ? 'applications/media_mgr' : 'applications/acdc';
        put('/fixture/root/' + area + '/ebin/' + module + '.beam', module);
    }
    const fakeFs = {
        existsSync: f => files.has(f),
        lstatSync: f => { assert(files.has(f)); return {isFile: () => true, isSymbolicLink: () => state.linkedLegacy && f === legacyPath,
            uid: 0, nlink: 1, mode: 0o600, size: files.get(f).length}; },
        mkdtempSync: prefix => { events.push('mkdir'); return prefix + ++state.counter; },
        chmodSync: () => events.push('chmod')
    };
    const fakeCp = {spawnSync(command, args) {
        if (command === '/usr/bin/sha256sum') return {status: 0, stdout: hash(files.get(args[0])) + '  fixture'};
        assert.equal(command, '/usr/local/bin/sup'); assert.equal(args[0], '-e'); assert.equal(args[1], 'kapps_config');
        if (args[2] === 'fetch_current') { events.push('read-config'); return {status: 0, stdout: state.configured}; }
        assert.equal(args[2], 'set_default'); events.push('set-default'); state.configured = args[5];
        return {status: 0, stdout: '{ok,synthetic}'};
    }};
    const probe = {
        MODULES: modules, validSha: h => /^[a-f0-9]{64}$/.test(h), validAccount: a => /^[a-f0-9]{32}$/.test(a),
        absolute: f => path.isAbsolute(f) && path.resolve(f) === f,
        protectedParents: () => {},
        exactKeys: (o, keys) => assert.equal(JSON.stringify(Object.keys(o).sort()), JSON.stringify(keys.slice().sort())),
        readPinned(f, h, limit = 8388608) { assert(files.has(f)); const bytes = files.get(f);
            assert(bytes.length <= limit); assert.equal(hash(bytes), h); return bytes; },
        createEvidence(f, bytes) { assert(!files.has(f)); events.push('create:' + path.basename(f)); put(f, bytes); return hash(bytes); },
        validateBeams(m) { assert.equal(m.modules.length, 11); for (const b of m.modules) assert.equal(hash(files.get(b.path)), b.sha256); },
        parseArgs(args) { const o = {}; for (let i = 0; i < args.length; i += 2) o[args[i].slice(2)] = args[i + 1];
            assert.equal(o.account, account); assert.equal(o['model-trial-index-sha256'], 'b'.repeat(64));
            assert(o['fixed-pack'].startsWith('/fixture/scripts/assets/')); return o; },
        execute(o) {
            events.push('probe'); if (state.probeFails) throw Error('synthetic secret-like provider string');
            const receipt = {node: o.node, account: o.account, finished_at: '2020-01-01T00:00:00.000Z',
                fixture_sequence: state.counter,
                beams: JSON.parse(files.get(o['beam-manifest'])).modules,
                cardinal_receipt_sha256: o['cardinal-receipt-sha256'], fixed_receipt_sha256: o['fixed-receipt-sha256']};
            put(o.output, receipt); if (state.configChanges) state.configured = '<<"/operator/changed.json">>';
            if (state.legacyChanges) put(legacyPath, 'changed during probe');
            return {sha256: hash(files.get(o.output))};
        }
    };
    const publisher = {
        validateReceipt(r, now) { assert.equal(now, Date.parse(r.finished_at)); },
        capability(_r, h, now) { return {schema_version: 2, backend_mode: 'prerecorded-cardinal-v1',
            generated_at: new Date(now).toISOString(), languages: {'en-us': {native_speaker_review: false}}, runtime_evidence_sha256: h}; },
        publish(o) { events.push('publish'); assert.equal(o.account, account);
            if (state.publishFails) throw Error('synthetic private failure');
            assert.equal(o['previous-sha256'], files.has(o.output) ? hash(files.get(o.output)) : 'absent');
            put(o.output, publisher.capability({}, o['receipt-sha256'], Date.parse('2020-01-01T00:01:00.000Z')));
            if (state.legacyChangesAfterPublish) put(legacyPath, 'changed during publication');
            if (state.configChangesAfterPublish) state.configured = '<<"/operator/changed.json">>';
            return {sha256: hash(files.get(o.output))}; }
    };
    function execute(mode = '--install') {
        events.length = 0; const messages = [], processStub = {argv: ['node', '-', mode, '/fixture/scripts',
            '/fixture/root', '/fixture/config', 'example.invalid', account, 'a'.repeat(64), 'b'.repeat(64), state.webRoot], exitCode: 0};
        // JSON crossing the VM boundary has another Object prototype; compare
        // data exactly without treating that harness-only prototype as a fault.
        const vmAssert = Object.assign((...args) => assert(...args), assert);
        vmAssert.deepEqual = (a, b, message) => assert.deepEqual(JSON.parse(JSON.stringify(a)), JSON.parse(JSON.stringify(b)), message);
        vm.runInNewContext(code, {Buffer, process: processStub, console: {log: m => messages.push(m), error: m => messages.push(m)},
            require(name) { if (name === 'node:fs') return fakeFs; if (name === 'node:path') return path;
                if (name === 'node:child_process') return fakeCp; if (name === 'node:assert/strict') return vmAssert;
                if (name.endsWith('/probe-acdc-prerecorded-runtime.cjs')) return probe;
                if (name.endsWith('/publish-acdc-prerecorded-capabilities.cjs')) return publisher;
                if (name.endsWith('/validate-acdc-language-capabilities.cjs')) return {assertLanguageCapabilities: x => {
                    // Exercise the actual strict five-locale/all-false legacy
                    // schema; v2 remains the existing synthetic publisher seam.
                    if (x.schema_version === 1) capabilitySchema.assertLanguageCapabilities(JSON.parse(JSON.stringify(x)));
                    return x;
                }};
                throw Error('Unexpected dependency'); } });
        return {status: processStub.exitCode, messages};
    }
    return {files, events, state, put, execute};
}
let checks = 0;
const f = fixture();
assert.equal(f.execute().status, 0); assert(f.events.indexOf('probe') < f.events.indexOf('publish'));
assert(f.events.indexOf('publish') < f.events.indexOf('set-default')); checks++;
assert.equal(f.state.configured, '<<"' + target + '">>');
assert.equal(f.execute().status, 0); assert(f.events.includes('publish')); assert(!f.events.includes('set-default')); checks++;
const before = [...f.files].map(([k, v]) => [k, hash(v)]);
assert.equal(f.execute('--check').status, 0); assert(f.events.every(e => e === 'read-config'));
assert.deepEqual([...f.files].map(([k, v]) => [k, hash(v)]), before); checks++;
f.put('/fixture/root/applications/acdc/ebin/acdc_language.beam', 'changed');
assert.equal(f.execute('--check').status, 1); checks++;
for (const kind of ['custom-path', 'unowned', 'native-reviewed']) {
    const t = fixture();
    if (kind === 'custom-path') t.state.configured = '<<"/operator/custom.json">>';
    else t.put(target, {schema_version: 2, languages: {'en-us': {native_speaker_review: kind === 'native-reviewed'}}});
    for (const mode of ['--install', '--check']) {
        const r = t.execute(mode); assert.equal(r.status, 0); assert(r.messages.some(m => m.startsWith('SKIP')));
        assert(!t.events.includes('publish') && !t.events.includes('probe') && !t.events.includes('set-default')); checks++;
    }
}
for (const kind of ['probeFails', 'publishFails', 'configChanges']) {
    const t = fixture(); t.state[kind] = true; const r = t.execute(); assert.equal(r.status, 1);
    assert(!t.events.includes('set-default'));
    if (kind !== 'publishFails') assert(!t.events.includes('publish'));
    assert(!r.messages.join('').includes('secret') && !r.messages.join('').includes('private failure')); checks++;
}
const empty = fixture(); assert.equal(empty.execute('--check').status, 1);
assert(empty.events.every(e => e === 'read-config')); checks++;
const changedMedia = fixture(); assert.equal(changedMedia.execute().status, 0);
changedMedia.put('/usr/local/share/kazoo5-installer/acdc-cardinal-media.json', 'changed media receipt');
assert.equal(changedMedia.execute('--check').status, 1); assert(changedMedia.events.every(e => e === 'read-config')); checks++;
const badMarker = fixture(); assert.equal(badMarker.execute().status, 0);
const marker = [...badMarker.files.keys()].find(k => k.includes('.installer-'));
badMarker.put(marker, {owner: 'not-installer'});
assert.equal(badMarker.execute().status, 1); assert(!badMarker.events.includes('publish')); checks++;
function legacyFixture(file = legacyPath) {
    const t = fixture(); t.put(file, capabilitySchema.legacyLanguageCapabilities('2020-01-01T00:00:00.000Z'));
    t.state.configured = '<<"' + file + '">>'; return t;
}
for (const webRoot of ['/fixture/web', '/fixture/other-web']) {
    const file = webRoot + '/apps/acdc/language-capabilities.json', t = legacyFixture(file);
    t.state.webRoot = webRoot; const original = hash(t.files.get(file));
    const r = t.execute(); assert.equal(r.status, 0, r.messages.join('\n'));
    assert.equal(hash(t.files.get(file)), original, 'legacy file remains unchanged');
    assert.equal(t.state.configured, '<<"' + target + '">>');
    assert(t.events.indexOf('probe') < t.events.indexOf('publish'));
    assert(t.events.indexOf('publish') < t.events.indexOf('set-default')); checks++;
}
const legacyCheck = legacyFixture(), beforeLegacyCheck = [...legacyCheck.files].map(([k, v]) => [k, hash(v)]);
const legacyChecked = legacyCheck.execute('--check'); assert.equal(legacyChecked.status, 1);
assert(legacyChecked.messages.some(m => m.startsWith('UNAVAILABLE')));
assert(legacyCheck.events.every(e => e === 'read-config'));
assert.deepEqual([...legacyCheck.files].map(([k, v]) => [k, hash(v)]), beforeLegacyCheck); checks++;
for (const kind of ['other-web-root', 'similar-custom-path', 'reviewed', 'unowned-fallback', 'no-legacy-mode']) {
    const file = kind === 'other-web-root' ? '/fixture/former-web/apps/acdc/language-capabilities.json'
        : kind === 'similar-custom-path' ? legacyPath + '.reviewed' : legacyPath;
    const t = legacyFixture(file);
    if (kind === 'reviewed') t.put(file, {schema_version: 2, languages: {'en-us': {native_speaker_review: true}}});
    if (kind === 'unowned-fallback') t.put(target, {schema_version: 2, languages: {'en-us': {native_speaker_review: false}}});
    if (kind === 'no-legacy-mode') { const value = JSON.parse(t.files.get(file)); delete value.backend_mode; t.put(file, value); }
    const oldFiles = [...t.files].map(([k, v]) => [k, hash(v)]);
    const r = t.execute(); assert.equal(r.status, 0); assert(r.messages.some(m => m.startsWith('SKIP')));
    assert(!t.events.includes('probe') && !t.events.includes('publish') && !t.events.includes('set-default'));
    assert.deepEqual([...t.files].map(([k, v]) => [k, hash(v)]), oldFiles); checks++;
}
for (const kind of ['positive-flag', 'missing-locale', 'extra-field', 'linkedLegacy']) {
    const t = legacyFixture(), bad = JSON.parse(t.files.get(legacyPath));
    if (kind === 'positive-flag') bad.languages['he-il'].position = true;
    if (kind === 'missing-locale') delete bad.languages['ar-sa'];
    if (kind === 'extra-field') bad.selection_ready = false;
    if (kind === 'linkedLegacy') t.state.linkedLegacy = true;
    t.put(legacyPath, bad); assert.equal(t.execute().status, 1);
    assert(!t.events.includes('probe') && !t.events.includes('publish') && !t.events.includes('set-default')); checks++;
}
for (const kind of ['legacyChanges', 'configChanges', 'legacyChangesAfterPublish', 'configChangesAfterPublish']) {
    const t = legacyFixture(); t.state[kind] = true;
    assert.equal(t.execute().status, 1); assert(!t.events.includes('set-default'));
    if (!kind.endsWith('AfterPublish')) assert(!t.events.includes('publish'));
    checks++;
}
console.log('PASS ' + checks + ' main-SH prerecorded finalization orchestration cases (synthetic, offline only)');
