#!/usr/bin/env node
'use strict';
// Actual pinned _loadApp, monsterizeApp, locale loader, dependency pipeline and
// auth._initApp. Only module/HTTP delivery timing and UI sinks are controlled.
// Private patch replay only; no real browser/network/authentication or builds.
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const vm = require('node:vm'), cp = require('node:child_process'), crypto = require('node:crypto');
const assert = require('node:assert/strict');
assert(process.argv.length <= 3, 'Only an optional framework cache path is accepted');
const cache = process.argv[2] || '/usr/local/src/kazoo5-installer/monster-ui';
assert(path.isAbsolute(cache));
const pin = '7ef735eada6fd0e2b96c06f32c0bb868867f7d18';
const target = 'src/js/lib/monster.apps.js';
const patchFile = path.join(__dirname, 'patches/monster-ui-app-load-singleflight.patch');
const backgroundFile = path.join(__dirname, 'patches/monster-ui-background-app-load.patch');
const installerFile = path.join(__dirname, 'install-kazoo5.sh');
const acdcFile = path.join(__dirname, '../monster-ui/acdc/app.js');
const englishFile = path.join(__dirname, '../monster-ui/acdc/i18n/en-US.json');
const lodashFile = require.resolve(path.join(cache, 'node_modules/lodash'));
const asyncFile = require.resolve(path.join(cache, 'node_modules/async'));
const _ = require(lodashFile), async = require(asyncFile);
const inputFiles = [__filename, patchFile, backgroundFile, installerFile, acdcFile, englishFile,
    lodashFile, asyncFile, process.execPath, '/usr/bin/git', '/bin/bash'];
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const hashes = () => inputFiles.map(file => ({file, sha256: digest(fs.readFileSync(file))}));
const before = hashes(), installer = fs.readFileSync(installerFile, 'utf8');
const acdcSource = fs.readFileSync(acdcFile, 'utf8'), english = JSON.parse(fs.readFileSync(englishFile, 'utf8'));
const env = Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith('GIT_')));
for (const key of ['BASH_ENV', 'ENV', 'NODE_OPTIONS', 'NODE_PATH']) delete env[key];
process.umask(0o077);
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'monster-app-singleflight-proof.'));
assert(path.isAbsolute(directory) && fs.statSync(directory).isDirectory());
const stage = path.join(directory, 'source');
const write = (file, bytes) => { fs.mkdirSync(path.dirname(file), {recursive: true}); fs.writeFileSync(file, bytes); };
write(path.join(directory, 'inputs.before.json'), JSON.stringify(before, null, 2) + '\n');
console.log('Retaining offline app-load evidence in ' + directory);
function git(...args) {
    return cp.execFileSync('/usr/bin/git', args, {env, encoding: 'utf8', timeout: 10000,
        maxBuffer: 2 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe']});
}
function hook(name) {
    const found = installer.match(new RegExp('^' + name + '\\(\\) \\{[\\s\\S]*?^\\}', 'm'));
    assert(found, 'Missing installer hook'); return found[0];
}
function applyRequired() {
    cp.execFileSync('/bin/bash', ['--noprofile', '--norc', '-s', '--', stage, patchFile], {
        env, encoding: 'utf8', timeout: 10000, maxBuffer: 1024 * 1024,
        input: 'set -euo pipefail\nDRY_RUN=false\nlog(){ :; }\ndie(){ exit 65; }\n'
            + hook('apply_required_source_patch') + '\napply_required_source_patch "$1" "$2"\n'
    });
}
let baseline, candidate, authSource, groups = 0;
const checks = [];
function test(name, run) { run(); groups++; checks.push(name); console.log('PASS ' + name); }
function setup(source = candidate) {
    const requests = [], modules = [], scripts = [], callbacks = [], exceptions = [], subscriptions = [];
    const instances = new Map(), metadata = new Map(), shortcuts = [], init = [];
    let holdInit = false, failUnsubscribe = false;
    const $ = {extend(...args) {
        if (args[0] === true) return _.merge(args[1], ...args.slice(2));
        return Object.assign(args[0], ...args.slice(1));
    }, ajax(settings) { requests.push({...settings, done: false}); }};
    const monster = {waterfall: async.waterfall, parallel: async.parallel, defaultLanguage: 'en-US',
        config: {api: {default: 'https://fixture.invalid/v2/'}, whitelabel: {language: 'en-US'},
            developerFlags: {build: {preloadedApps: ['acdc', 'common', 'other']}}},
        normalizeUrlPathEnding: value => typeof value === 'string' ? value.replace(/\/?$/, '/') : undefined,
        util: {getAppStoreMetadata: name => metadata.get(name) || {}, getVersion: () => 'fixture-version',
            isUserPermittedApp: () => true, cacheUrl: (_app, url) => url},
        isDev: () => false, _defineRequest() {}, css() {},
        // Non-preloaded constructor slots stop at a pending VERSION request.
        // The native loader composes this callback before sending that request.
        parseVersionFile() { assert.fail('No VERSION response is supplied by this fixture'); },
        ui: {removeShortcut(value) { shortcuts.push(['remove', value]); }, addShortcut(value) { shortcuts.push(['add', value]); }, toast() {}},
        sub(topic, fn, app) { const record = {topic, fn, app, active: true}; subscriptions.push(record); return record; },
        unsub(record) { if (failUnsubscribe) throw Error('fixture_unsubscribe_failed'); assert(record.active); record.active = false; },
        getScript(url, callback) { scripts.push({url, callback}); },
        pub(topic, args) {
            assert.equal(topic, 'auth.initApp');
            const execute = () => monster.apps.auth._initApp(args);
            init.push({app: args.app, execute});
            if (!holdInit) execute();
        }};
    function amd(bytes, filename) {
        let value;
        function requireDependency(name, success, error) {
            if (Array.isArray(name)) { modules.push({name: name[0], success, error, done: false}); return; }
            if (name === 'jquery') return $;
            if (name === 'lodash') return _;
            if (name === 'monster') return monster;
            if (name === 'qrcode') return {};
            throw Error('Unexpected module dependency');
        }
        requireDependency.config = () => {};
        vm.runInNewContext(bytes, {define(factory) { value = factory(requireDependency); }, require: requireDependency,
            window: {location: {hash: ''}}, document: {}, console: {info() {}, warn() {}},
            setTimeout(fn, delay) { assert.equal(delay, 0); exceptions.push(fn); }}, {filename, timeout: 1000});
        return value;
    }
    monster.apps = amd(source, target);
    monster.apps.auth = amd(authSource, 'src/apps/auth/app.js');
    Object.assign(monster.apps.auth, {accountId: 'a'.repeat(32), userId: 'u'.repeat(32),
        currentAccount: {id: 'a'.repeat(32)}, currentUser: {}});
    function app(name) {
        if (!instances.has(name)) {
            const value = amd(acdcSource, 'actual-acdc-app.js');
            value.name = name; value.requests = {}; value.subscribe = {'fixture.topic': 'fixtureHandler'};
            value.fixtureHandler = () => {}; value.render = () => {};
            instances.set(name, value);
        }
        return instances.get(name);
    }
    function deliverModule(name = 'acdc', value, error) {
        const request = modules.find(item => !item.done && item.name === (name.includes('/') ? name : 'apps/' + name + '/app'));
        assert(request, 'Expected pending module ' + name); request.done = true;
        if (error) request.error(error); else request.success(value || app(name));
    }
    function locale(name = 'acdc', error = false, value = english) {
        const request = requests.find(item => !item.done && item.url.includes('apps/' + name + '/i18n/'));
        assert(request, 'Expected pending locale ' + name); request.done = true;
        if (error) request.error({}, 'error', 'fixture'); else request.success(value);
    }
    function load(name = 'acdc', options, direct = false, callback) {
        monster.apps[direct ? '_loadApp' : 'load'](name, callback || ((error, value) => callbacks.push({name, error, value})), options);
    }
    return {monster, modules, requests, scripts, callbacks, subscriptions, shortcuts, init, exceptions, metadata,
        app, deliverModule, locale, load, holdInit(value = true) { holdInit = value; },
        failUnsubscribe() { failUnsubscribe = true; }, activeSubscriptions: () => subscriptions.filter(s => s.active).length,
        finish(name = 'acdc') { deliverModule(name); locale(name); }};
}
let failure;
try {
    test('pinned source and actual installer forward/idempotent/reverse replay', () => {
        assert.equal(git('-C', cache, 'rev-parse', pin + '^{commit}').trim(), pin);
        write(path.join(stage, target), git('-C', cache, 'show', pin + ':' + target));
        authSource = git('-C', cache, 'show', pin + ':src/apps/auth/app.js');
        git('-C', stage, 'apply', '--include=' + target, backgroundFile);
        baseline = fs.readFileSync(path.join(stage, target), 'utf8');
        assert.deepEqual([...fs.readFileSync(patchFile, 'utf8').matchAll(/^diff --git a\/(\S+) b\/\1$/gm)].map(m => m[1]), [target]);
        applyRequired(); candidate = fs.readFileSync(path.join(stage, target), 'utf8');
        applyRequired(); assert.equal(fs.readFileSync(path.join(stage, target), 'utf8'), candidate);
        git('-C', stage, 'apply', '--reverse', patchFile);
        assert.equal(fs.readFileSync(path.join(stage, target), 'utf8'), baseline); applyRequired();
        write(path.join(directory, 'source-lineage.json'), JSON.stringify({pin, target,
            baseline: digest(baseline), candidate: digest(candidate), auth_init_source: digest(authSource)}, null, 2));
    });
    test('negative control: real duplicate loader clears an already rendered app translation table', () => {
        const t = setup(baseline); t.load(); t.load(); assert.equal(t.modules.length, 2);
        t.deliverModule(); t.locale(); assert(t.app('acdc').i18n.active().acdc);
        t.deliverModule(); assert.equal(t.app('acdc').i18n.active(), undefined);
        assert.throws(() => t.app('acdc').mountLiveDashboard({}, 1, {}), /acdc/);
        t.locale(); assert.equal(t.callbacks.length, 2);
    });
    test('overlapping public loads construct and initialize once without blanking i18n', () => {
        const t = setup(); t.load(); t.load(); assert.equal(t.modules.length, 1);
        t.finish(); assert.equal(t.callbacks.length, 2); assert.equal(t.init.length, 1);
        assert.equal(t.callbacks[0].value, t.callbacks[1].value);
        assert(t.app('acdc').i18n.active().acdc); assert.equal(t.activeSubscriptions(), 1);
    });
    test('partially published cache does not complete a later caller before native auth initialization', () => {
        const t = setup(); t.holdInit(); t.load(); t.finish();
        assert.equal(t.monster.apps.acdc, t.app('acdc')); assert.equal(t.callbacks.length, 0);
        t.load(); assert.equal(t.callbacks.length, 0); assert.equal(t.modules.length, 1);
        t.init[0].execute(); assert.equal(t.callbacks.length, 2);
        assert.equal(t.app('acdc').accountId, 'a'.repeat(32));
    });
    test('actual dependency load and public load share the same lower flight', () => {
        const t = setup(); t.metadata.set('acdc', {extensions: ['common']});
        t.load(); t.finish(); assert.equal(t.modules.filter(m => m.name === 'apps/common/app').length, 1);
        t.load('common'); t.load('common', undefined, true);
        assert.equal(t.modules.filter(m => m.name === 'apps/common/app').length, 1);
        t.finish('common'); assert.equal(t.callbacks.length, 3);
        assert.equal(t.init.filter(item => item.app.name === 'common').length, 1);
    });
    test('background and foreground activation remains per caller and cache does not reinitialize', () => {
        for (const first of [true, false]) {
            const t = setup(); t.load('acdc', {background: first}); t.load('acdc', {background: !first}); t.finish();
            assert.equal(t.monster.apps.lastLoadedApp, 'acdc'); assert.equal(t.shortcuts.length, 1);
            const table = t.app('acdc').data.i18n;
            t.load('acdc', {background: true}); assert.equal(t.shortcuts.length, 1);
            assert.equal(t.modules.length, 1); assert.equal(t.init.length, 1); assert.equal(t.app('acdc').data.i18n, table);
        }
        const t = setup(); t.load('acdc', {background: true}); t.finish();
        assert.equal(t.monster.apps.lastLoadedApp, undefined); assert.equal(t.shortcuts.length, 0);
    });
    test('differing effective source or API options fail without cross-source coalescing or cache mutation', () => {
        for (const options of [{sourceUrl: 'https://elsewhere.invalid/app'}, {apiUrl: 'https://elsewhere.invalid/v2'}]) {
            const t = setup(); t.load(); t.load('acdc', options); assert(t.callbacks[0].error);
            assert.equal(t.modules.length, 1); t.finish(); assert.equal(t.callbacks.length, 2);
            const table = t.app('acdc').data.i18n;
            t.load('acdc', options); assert(t.callbacks[2].error); assert.equal(t.app('acdc').data.i18n, table);
        }
        const t = setup(); t.load(); t.load('acdc', {apiUrl: 'https://fixture.invalid/v2'});
        assert.equal(t.modules.length, 1); t.finish(); assert(t.callbacks.every(c => !c.error));
    });
    test('module failure fans out once and a subsequent explicit retry can succeed', () => {
        const t = setup(), error = Error('fixture_module'); t.load(); t.load();
        t.deliverModule('acdc', undefined, error); assert.equal(t.callbacks.length, 2);
        assert(t.callbacks.every(c => c.error === error)); assert(!t.monster.apps.acdc);
        t.load(); t.finish(); assert.equal(t.callbacks.length, 3); assert(!t.callbacks[2].error);
    });
    test('locale failure cleans only attempt subscriptions before an explicit retry', () => {
        const t = setup(); t.load(); t.deliverModule(); assert.equal(t.activeSubscriptions(), 1);
        t.locale('acdc', true); assert(t.callbacks[0].error); assert.equal(t.activeSubscriptions(), 0);
        assert(!t.monster.apps.acdc); t.load(); t.finish();
        assert.equal(t.callbacks.length, 2); assert.equal(t.activeSubscriptions(), 1); assert(t.app('acdc').i18n.active().acdc);
    });
    test('failed submodule waits for late sibling mutation and unsubscribes before retry', () => {
        const t = setup(); t.app('acdc').subModules = ['bad', 'late']; t.load(); t.deliverModule();
        const error = Error('fixture_submodule');
        t.deliverModule('apps/acdc/submodules/bad/bad', undefined, error);
        t.load(); assert.equal(t.callbacks.length, 0); assert.equal(t.modules.filter(m => m.name === 'apps/acdc/app').length, 1);
        t.deliverModule('apps/acdc/submodules/late/late', {subscribe: {'fixture.late': () => {}}});
        assert.equal(t.callbacks.length, 2); assert(t.callbacks.every(c => c.error === error));
        assert.equal(t.activeSubscriptions(), 0);
        t.app('acdc').subModules = []; t.load(); t.finish(); assert.equal(t.callbacks.length, 3);
    });
    test('dependency error removes its exact partial parent cache and allows later retry', () => {
        const t = setup(); t.metadata.set('acdc', {extensions: ['common']}); t.load(); t.finish();
        assert(t.monster.apps.acdc); t.deliverModule('common', undefined, Error('fixture_dependency'));
        assert(t.callbacks[0].error); assert(!t.monster.apps.acdc); assert.equal(t.activeSubscriptions(), 0);
        t.metadata.set('acdc', {}); t.load(); t.finish(); assert(!t.callbacks[1].error);
    });
    test('native auth initialization uses current account and locale fallback remains a real loaded language', () => {
        const t = setup(); t.load(); t.deliverModule();
        t.monster.config.whitelabel.language = 'fr-FR';
        t.monster.apps.auth.currentAccount = {id: 'b'.repeat(32)};
        t.load(); t.locale(); assert.equal(t.init.length, 1);
        assert.equal(t.app('acdc').accountId, 'b'.repeat(32));
        assert.deepEqual(JSON.parse(JSON.stringify(t.app('acdc').i18n.active().acdc)), english.acdc);
        t.monster.config.whitelabel.language = 'en-US';
        assert(t.app('acdc').i18n.active().acdc);
        t.monster.apps.auth.currentAccount = {id: 'a'.repeat(32)};
        t.app('acdc').initApp(() => {}); assert.equal(t.app('acdc').accountId, 'a'.repeat(32));
    });
    test('one callback exception is reported asynchronously without stranding another accepted callback', () => {
        const t = setup(), error = Error('fixture_consumer');
        t.load('acdc', undefined, false, () => { throw error; }); t.load(); t.finish();
        assert.equal(t.callbacks.length, 1); assert.equal(t.exceptions.length, 1);
        assert.throws(t.exceptions[0], value => value === error);
        t.load(); assert.equal(t.callbacks.length, 2); assert.equal(t.modules.length, 1);
    });
    test('waiter and simultaneous-constructor caps reject overflow explicitly without losing accepted callers', () => {
        const t = setup(); for (let i = 0; i < 33; i++) t.load();
        assert.equal(t.modules.length, 1); assert.equal(t.callbacks.length, 1); assert(t.callbacks[0].error);
        t.finish(); assert.equal(t.callbacks.length, 33); assert.equal(t.callbacks.filter(c => !c.error).length, 32);
        const many = setup(); for (let i = 0; i < 33; i++) many.load('app-' + i);
        assert.equal(many.requests.length, 32); assert.equal(many.callbacks.length, 1); assert(many.callbacks[0].error);
        assert.deepEqual(many.requests.map(r => r.url), Array.from({length: 32}, (_, i) => 'apps/app-' + i + '/VERSION'));
        assert(many.requests.every(r => !r.done)); assert.equal(many.callbacks[0].name, 'app-32');
        assert.equal(many.callbacks[0].error.message, 'App load capacity exceeded');
    });
    test('failed ownership cleanup blocks a new constructor rather than leaking duplicate subscriptions', () => {
        const t = setup(); t.load(); t.deliverModule(); t.failUnsubscribe(); t.locale('acdc', true);
        assert(t.callbacks[0].error); t.load(); assert(t.callbacks[1].error); assert.equal(t.modules.length, 1);
    });
    test('installer fingerprints and applies the new patch after background semantics', () => {
        assert(hook('monster_ui_build_fingerprint').includes('monster-ui-app-load-singleflight.patch:patches/monster-ui-app-load-singleflight.patch'));
        const sync = hook('sync_monster_ui_sources');
        const current = 'apply_required_source_patch "$source_dir" "$SCRIPT_DIR/patches/monster-ui-app-load-singleflight.patch"';
        assert(sync.includes(current));
        assert(sync.indexOf(current) > sync.indexOf('apply_required_source_patch "$source_dir" "$SCRIPT_DIR/patches/monster-ui-background-app-load.patch"'));
    });
} catch (error) { failure = error; }
finally {
    const after = hashes(); write(path.join(directory, 'inputs.after.json'), JSON.stringify(after, null, 2) + '\n');
    try { assert.deepEqual(after, before); } catch (error) { failure = failure || error; }
    write(path.join(directory, 'receipt.json'), JSON.stringify({result: failure ? 'FAIL' : 'PASS', groups, checks,
        inputs_stable: JSON.stringify(before) === JSON.stringify(after), network: false, browser: false,
        source_only: true, live_acceptance: false}, null, 2) + '\n');
}
if (failure) throw failure;
console.log('PASS ' + groups + ' actual-loader offline groups');
