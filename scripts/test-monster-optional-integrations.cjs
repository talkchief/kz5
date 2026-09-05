'use strict';

// Offline only: no browser/network, keys, SIP devices, or deployment writes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const cp = require('node:child_process');
const root = process.argv[2] || '/usr/local/src/kazoo5-installer/monster-ui';
const read = relative => fs.readFileSync(path.join(root, 'src', relative), 'utf8');
const sources = {
    maps: read('apps/common/external/buyNumbers-googleMapsLoader.js'),
    e911: read('apps/common/submodules/e911/e911.js'),
    webphone: read('js/lib/monster.webphone.js')
};
const lodash = {get(object, property, fallback) {
    let value = object;
    for (const part of property.split('.')) value = value == null ? undefined : value[part];
    return value === undefined ? fallback : value;
}};
let passed = 0;
function test(name, body) { body(); passed++; console.log('PASS: ' + name); }
function mapsFixture(googleMaps, options = {}) {
    const scripts = [], logs = [], existing = options.existing || null;
    const document = {
        getElementById: id => scripts.find(script => script.id === id) || existing,
        createElement: name => { assert.equal(name, 'script'); return {}; }
    };
    const window = {monster: {config: {api: {googleMaps}}}, google: options.google};
    if (options.callback) window.gmap_draw = options.callback;
    const context = {window, document, console: {log: value => logs.push(value)}, $(target) {
        if (target === document) return {ready: fn => fn()};
        assert.equal(target, 'head');
        return {append: script => scripts.push(script)};
    }};
    const run = () => vm.runInNewContext(sources.maps, context);
    run();
    return {scripts, logs, window, run};
}
function amd(source, monster, window, kazoo) {
    let result;
    const logs = [];
    vm.runInNewContext(source, {window, console: {log: (...args) => logs.push(args)}, define(factory) {
        result = factory(name => {
            if (name === 'lodash') return lodash;
            if (name === 'jquery') return () => { throw new Error('Unexpected DOM operation'); };
            if (name === 'monster') return monster;
            if (name === 'kazoo') return kazoo;
            throw new Error('Unexpected dependency: ' + name);
        });
    }});
    return {result, logs};
}
function phoneFixture(endpoint, protocol = 'https:') {
    const starts = [], registrations = [], publications = [], delegates = [];
    const kazoo = {
        init: args => starts.push(args), register: args => registrations.push(args),
        connected: false, listCalls: () => [], getActiveCall: () => null,
        connect: arg => delegates.push(['connect', arg]), hangup: arg => delegates.push(['hangup', arg])
    };
    const monster = {config: {api: {socketWebphone: endpoint}},
        apps: {auth: {originalAccount: {realm: 'fixture.invalid'}}},
        pub: (...args) => publications.push(args)};
    const loaded = amd(sources.webphone, monster, {URL, location: {protocol}}, kazoo);
    return {phone: loaded.result, logs: loaded.logs, starts, registrations, publications, monster, kazoo, delegates};
}
function e911Fixture(config, options = {}) {
    const queries = [], requests = [];
    const monster = {config: {api: {googleMaps: config}}, request: args => requests.push(args)};
    const window = {};
    if (options.loaded !== false) window.google = {maps: {Geocoder: function() {
        this.geocode = (query, callback) => {
            queries.push(query);
            callback(options.results || [], options.status || 'OK');
        };
    }}};
    return {e911: amd(sources.e911, monster, window).result, queries, requests};
}

test('Maps missing/empty/malformed key or explicitly disabled: no script, callback or logs', () => {
    for (const config of [undefined, null, false, {}, {apiKey: ''}, {apiKey: '  '}, {apiKey: 12},
        {apiKey: 'fixture-key', enabled: false}]) {
        const item = mapsFixture(config);
        assert.equal(item.scripts.length, 0);
        assert.equal(item.window.gmap_draw, undefined);
        assert.equal(item.logs.length, 0);
    }
});
test('Configured Maps uses one HTTPS async quarterly request with encoded supplied key', () => {
    const item = mapsFixture({apiKey: ' fixture+/=key '});
    const script = item.scripts[0], url = new URL(script.src);
    assert.equal(item.scripts.length, 1);
    assert.equal(script.async, true);
    assert.equal(script.defer, true);
    assert.equal(url.origin, 'https://maps.googleapis.com');
    assert.equal(url.pathname, '/maps/api/js');
    assert.equal(url.searchParams.get('key'), 'fixture+/=key');
    assert.equal(url.searchParams.get('loading'), 'async');
    assert.equal(url.searchParams.get('v'), 'quarterly');
    assert.equal(url.searchParams.get('callback'), 'gmap_draw');
    assert.equal(typeof item.window.gmap_draw, 'function');
    item.run();
    assert.equal(item.scripts.length, 1, 'No duplicate loader while pending');
});
test('Maps preserves existing SDK and user-provided callback', () => {
    assert.equal(mapsFixture({apiKey: 'fixture-key'}, {google: {maps: {}}}).scripts.length, 0);
    const callback = () => {};
    assert.equal(mapsFixture({apiKey: 'fixture-key'}, {callback}).window.gmap_draw, callback);
    assert.equal(mapsFixture({apiKey: 'fixture-key'}, {google: {}}).scripts.length, 1);
});
test('Unconfigured or invalid webphone stays unavailable without SDK start or device creation', () => {
    for (const endpoint of [undefined, null, false, '', ' ', 42, 'https://fixture.invalid',
        'wss://', 'wss://user:password@fixture.invalid', 'wss://fixture.invalid/#fragment',
        'wss://fixture.invalid\n', 'wss://fixture.invalid:99999', 'ws://fixture.invalid']) {
        const item = phoneFixture(endpoint), failures = [];
        assert.equal(item.phone.init(), false);
        assert.equal(item.phone.isAvailable(), false);
        assert.equal(item.phone.login({error: failure => failures.push(failure)}), false);
        assert.equal(failures[0].code, 'webphone_unavailable');
        assert.equal(item.phone.login(), false, 'Missing callback must not throw');
        assert.equal(item.starts.length, 0);
        assert.equal(item.publications.length, 0);
        assert.equal(item.registrations.length, 0);
        assert.equal(item.logs.length, 0);
    }
});
test('Configured websocket endpoints preserved; pending and completed init are idempotent', () => {
    for (const [endpoint, protocol] of [['wss://fixture.invalid:7443/ws', 'https:'],
        ['ws://127.0.0.1:5066', 'http:'], ['wss://[::1]:7443/', 'https:']]) {
        const item = phoneFixture(endpoint, protocol);
        assert.equal(item.phone.init(), true);
        assert.equal(item.phone.init(), true);
        assert.equal(item.starts.length, 1);
        assert.equal(item.starts[0].prefixScripts, 'js/lib/kazoo/dependencies/');
        assert.equal(item.phone.isAvailable(), false, 'Not ready before SDK callback');
        let failure;
        item.phone.login({onError: value => { failure = value; }});
        assert.equal(failure.code, 'webphone_unavailable');
        assert.equal(item.publications.length, 0);
        item.starts[0].onLoaded();
        assert.equal(item.phone.isAvailable(), true);
        item.phone.init();
        assert.equal(item.starts.length, 1);
    }
});
test('Configured webphone preserves device login, supplied endpoint and call delegates', () => {
    const item = phoneFixture('wss://fixture.invalid/ws');
    item.phone.init(); item.starts[0].onLoaded();
    const device = {sip: {username: 'fixture-user', password: 'fixture-only'}}, events = [];
    item.phone.login({onConnected: value => events.push(value), onAccepted: value => events.push(value)});
    assert.equal(item.publications[0][0], 'common.webphone.getOrCreateUserDevice');
    item.publications[0][1].success(device);
    const registration = item.registrations[0];
    assert.equal(registration.wsUrl, 'wss://fixture.invalid/ws');
    assert.equal(registration.realm, 'fixture.invalid');
    assert.equal(registration.privateIdentity, 'fixture-user');
    assert.equal(registration.publicIdentity, 'sip:fixture-user@fixture.invalid');
    assert.equal(registration.password, device.sip.password);
    registration.onConnected(); registration.onAccepted('fixture-call'); registration.onError();
    assert.deepEqual(events, [device, 'fixture-call']);
    item.phone.connect(123); item.phone.hangup('fixture-call');
    assert.deepEqual(item.delegates, [['connect', '123'], ['hangup', 'fixture-call']]);
    item.monster.config.api.socketWebphone = null;
    assert.equal(item.phone.isAvailable(), false);
    item.phone.login({});
    assert.equal(item.publications.length, 1);
});
test('SDK initialization failures remain visible and can be retried', () => {
    const item = phoneFixture('wss://fixture.invalid/ws');
    item.kazoo.init = () => { throw new Error('fixture SDK failure'); };
    assert.throws(() => item.phone.init(), /fixture SDK failure/);
    item.kazoo.init = args => item.starts.push(args);
    item.phone.init();
    assert.equal(item.starts.length, 1);
});
test('E911 ZIP autofill requires a key, explicit paid-service opt-in and loaded Maps SDK', () => {
    for (const config of [undefined, null, {}, {apiKey: 'fixture-key'}, {apiKey: 'fixture-key', geocoding: false},
        {apiKey: 'fixture-key', geocoding: true, enabled: false}, {apiKey: '', geocoding: true},
        {apiKey: 12, geocoding: true}]) {
        const item = e911Fixture(config), failures = [];
        assert.equal(item.e911.e911GetAddressFromZipCode({data: {zipCode: '12345'},
            error: failure => failures.push(failure)}), false);
        assert.equal(failures[0].code, 'geocoding_unavailable');
        assert.equal(item.e911.e911GetAddressFromZipCode({data: {zipCode: '12345'}}), false);
        assert.equal(item.queries.length, 0);
        assert.equal(item.requests.length, 0, 'No unauthenticated REST fallback');
    }
    const loading = e911Fixture({apiKey: 'fixture-key', geocoding: true}, {loaded: false});
    assert.equal(loading.e911.e911GetAddressFromZipCode({data: {zipCode: '12345'}}), false);
});
test('Configured E911 autofill uses Geocoder with success/empty/error callbacks only', () => {
    for (const status of ['OK', 'ZERO_RESULTS', 'REQUEST_DENIED']) {
        const results = [{address_components: []}], item = e911Fixture(
            {apiKey: 'fixture-key', geocoding: true}, {status, results}), success = [], failures = [];
        assert.equal(item.e911.e911GetAddressFromZipCode({data: {zipCode: '12345'},
            success: value => success.push(value), error: value => failures.push(value)}), true);
        assert.equal(item.queries[0].address, '12345');
        assert.equal(item.requests.length, 0);
        if (status === 'REQUEST_DENIED') {
            assert.equal(success.length, 0);
            assert.equal(failures[0].code, 'geocoding_failed');
        } else assert.equal(success[0], results);
    }
});
test('All manual E911 form/render/save/validation functions are byte-identical to pinned source', () => {
    const baseline = cp.execFileSync('git', ['-C', root, 'show',
        '7ef735eada6fd0e2b96c06f32c0bb868867f7d18:src/apps/common/submodules/e911/e911.js'], {encoding: 'utf8'});
    const before = amd(baseline, {}, {}).result;
    const after = amd(sources.e911, {}, {}).result;
    for (const [name, implementation] of Object.entries(before)) {
        if (typeof implementation !== 'function' || name === 'e911GetAddressFromZipCode') continue;
        assert.equal(after[name].toString(), implementation.toString(), name + ' must remain unchanged');
    }
});
test('Exact 3-file patch replays onto pinned source in memory and reverses current worktree', () => {
    const patchPath = path.join(__dirname, 'patches/monster-ui-optional-integrations.patch');
    const patch = fs.readFileSync(patchPath, 'utf8');
    const expected = new Set(['src/apps/common/external/buyNumbers-googleMapsLoader.js',
        'src/apps/common/submodules/e911/e911.js', 'src/js/lib/monster.webphone.js']);
    for (const section of patch.split(/(?=^diff --git )/m).filter(Boolean)) {
        const lines = section.replace(/\n$/, '').split('\n');
        const match = /^diff --git a\/(\S+) b\/\1$/.exec(lines[0]);
        assert(match, 'Only exact path-preserving text sections are permitted');
        const file = match[1];
        assert(expected.delete(file), 'Unexpected or duplicate source path: ' + file);
        const baseline = cp.execFileSync('git', ['-C', root, 'show',
            '7ef735eada6fd0e2b96c06f32c0bb868867f7d18:' + file], {encoding: 'utf8'}).split('\n');
        const result = [];
        let cursor = 0, index = lines.findIndex(line => line.startsWith('@@ '));
        assert(index > 0, 'Missing patch hunks');
        while (index < lines.length) {
            const hunk = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/.exec(lines[index++]);
            assert(hunk, 'Malformed hunk');
            const oldStart = Number(hunk[1]) - 1, oldCount = Number(hunk[2] || 1), newCount = Number(hunk[4] || 1);
            assert(oldStart >= cursor, 'Overlapping hunks');
            result.push(...baseline.slice(cursor, oldStart)); cursor = oldStart;
            assert.equal(Number(hunk[3]) - 1, result.length, 'Exact target offset');
            let removed = 0, added = 0;
            while (index < lines.length && !lines[index].startsWith('@@ ')) {
                const line = lines[index++], kind = line[0];
                assert([' ', '+', '-'].includes(kind), 'Unsupported patch line');
                if (kind !== '+') {assert.equal(line.slice(1), baseline[cursor++], file); removed++;}
                if (kind !== '-') {result.push(line.slice(1)); added++;}
            }
            assert.equal(removed, oldCount); assert.equal(added, newCount);
        }
        result.push(...baseline.slice(cursor));
        assert.equal(result.join('\n'), fs.readFileSync(path.join(root, file), 'utf8'), 'Forward byte replay: ' + file);
    }
    assert.equal(expected.size, 0, 'Patch must contain every owned file');
    cp.execFileSync('git', ['-C', root, 'apply', '--check', '--reverse', patchPath], {stdio: 'pipe'});
});
console.log(`PASS: ${passed} optional integration regression groups; no network or filesystem mutations`);
