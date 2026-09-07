#!/usr/bin/env node
'use strict';
// Real pinned AMD apps.load/changeAppShortcuts + Core _loadApps. Only the lower
// resource-loading seam, routing and UI sinks are controlled. No browser/API.
// All replay writes are confined to a retained private fixture, not the cache.
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const vm = require('node:vm'), cp = require('node:child_process'), crypto = require('node:crypto');
const assert = require('node:assert/strict');
const args = process.argv.slice(2), baselineMode = args.includes('--baseline');
const positional = args.filter(arg => arg !== '--baseline');
assert(args.filter(arg => arg === '--baseline').length <= 1 && positional.length <= 1);
const cache = positional[0] || '/usr/local/src/kazoo5-installer/monster-ui';
assert(path.isAbsolute(cache), 'An absolute existing framework cache is required');
const pin = '7ef735eada6fd0e2b96c06f32c0bb868867f7d18';
const appsPath = 'src/js/lib/monster.apps.js', corePath = 'src/apps/core/app.js';
const patchPath = path.join(__dirname, 'patches/monster-ui-background-app-load.patch');
const brandingPath = path.join(__dirname, 'patches/monster-ui-branding-billing.patch');
const readinessPath = path.join(__dirname, 'patches/monster-ui-account-picker-readiness.patch');
const installerPath = path.join(__dirname, 'install-kazoo5.sh');
const lodashPath = require.resolve(path.join(cache, 'node_modules/lodash'));
const asyncPath = require.resolve(path.join(cache, 'node_modules/async'));
const lodash = require(lodashPath), async = require(asyncPath);
const installer = fs.readFileSync(installerPath, 'utf8');
const env = Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith('GIT_')));
delete env.BASH_ENV; delete env.ENV; delete env.NODE_OPTIONS; delete env.NODE_PATH;
process.umask(0o077);
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'monster-background-app-proof.'));
const stage = path.join(directory, 'source');
console.log('Retaining offline background-app evidence in ' + directory);
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const inputFiles = [__filename, patchPath, brandingPath, readinessPath, installerPath,
    lodashPath, asyncPath, process.execPath, '/usr/bin/git', '/bin/bash'];
const hashes = () => inputFiles.map(file => ({file, sha256: digest(fs.readFileSync(file))}));
const before = hashes();
const write = (file, bytes) => { fs.mkdirSync(path.dirname(file), {recursive: true}); fs.writeFileSync(file, bytes); };
write(path.join(directory, 'inputs.before.json'), JSON.stringify(before, null, 2) + '\n');
function git(...command) {
    return cp.execFileSync('/usr/bin/git', command, {encoding: 'utf8', env, timeout: 10000,
        maxBuffer: 2 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe']});
}
function hook(name) {
    const found = installer.match(new RegExp('^' + name + '\\(\\) \\{[\\s\\S]*?^\\}', 'm'));
    assert(found, 'Missing actual installer hook: ' + name); return found[0];
}
function applyRequired() {
    cp.execFileSync('/bin/bash', ['--noprofile', '--norc', '-s', '--', stage, patchPath], {
        encoding: 'utf8', env, timeout: 10000, maxBuffer: 1024 * 1024, stdio: ['pipe', 'pipe', 'pipe'],
        input: 'set -euo pipefail\nDRY_RUN=false\nlog(){ :; }\ndie(){ exit 65; }\n'
            + hook('apply_required_source_patch') + '\napply_required_source_patch "$1" "$2"\n'
    });
}
let baseline, candidate, passed = 0;
const checks = [];
function test(name, body) { body(); passed++; checks.push(name); console.log('PASS ' + name); }
function setup(bytes = baselineMode ? baseline : candidate, options = {}) {
    const loads = [], callbacks = [], shortcutCalls = [], routes = [], states = [];
    const monster = {waterfall: async.waterfall, parallel: async.parallel,
        config: {whitelabel: {additionalLoggedInApps: options.additional || []}},
        util: {isAdmin: () => true},
        ui: {removeShortcut(category) { shortcutCalls.push(['remove', category]); },
            addShortcut(shortcut) { shortcutCalls.push(['add', shortcut.key, shortcut.title]); }},
        pub() { throw Error('Unexpected publication'); }};
    function amd(source, filename) {
        let exported;
        function requireDependency(name) {
            if (name === 'lodash') return lodash;
            if (name === 'monster') return monster;
            if (name === 'jquery') return () => { throw Error('Unexpected DOM operation'); };
            throw Error('Unexpected AMD dependency');
        }
        vm.runInNewContext(source, {define(factory) { exported = factory(requireDependency); }, require: requireDependency,
            console: {warn() {}}, window: {}, document: {}}, {filename, timeout: 1000});
        return exported;
    }
    monster.apps = amd(bytes.apps, appsPath);
    monster.apps.auth = {currentAccount: {id: 'a'.repeat(32)}};
    monster.apps._loadApp = (name, callback, loadOptions) => loads.push({name, callback, options: loadOptions});
    const core = amd(bytes.core, corePath);
    core._setAccountBrowserState = state => { states.push(state); core.appFlags.accountBrowserState = state; };
    function app(name) {
        return {name, shortcuts: {x: name + '.shortcut'}, i18n: {active: () => ({shortcuts: {x: name}})},
            accountId: 'a'.repeat(32), getTemplate() {}, accountBrowserRender() {}, callApi() {}};
    }
    function complete(name, error = null) {
        const pending = loads.find(load => load.name === name && !load.completed);
        assert(pending, 'Expected pending native resource load: ' + name); pending.completed = true;
        const loaded = app(name);
        if (!error) monster.apps[name] = loaded;
        pending.callback(error, error ? undefined : loaded);
        return loaded;
    }
    function load(name, loadOptions) {
        monster.apps.load(name, (error, loaded) => callbacks.push({name, error, loaded}), loadOptions);
    }
    monster.routing = {parseHash() { routes.push('parse'); }, hasMatch: () => !!options.routeMatch,
        goTo(route) { routes.push(route); load(route.slice('apps/'.length)); }};
    return {monster, core, loads, callbacks, shortcutCalls, routes, states, app, complete, load,
        activate(name) { load(name); if (!monster.apps[name]) complete(name); },
        active: () => monster.apps.getActiveApp()};
}
try {
    test('pinned prerequisites, exact installer forward/repeat/reverse replay', () => {
        assert.equal(git('-C', cache, 'rev-parse', pin + '^{commit}').trim(), pin);
        for (const file of [appsPath, corePath]) write(path.join(stage, file), git('-C', cache, 'show', pin + ':' + file));
        git('-C', stage, 'apply', '--include=' + corePath, brandingPath);
        git('-C', stage, 'apply', '--include=' + corePath, readinessPath);
        baseline = {apps: fs.readFileSync(path.join(stage, appsPath), 'utf8'), core: fs.readFileSync(path.join(stage, corePath), 'utf8')};
        const names = [...fs.readFileSync(patchPath, 'utf8').matchAll(/^diff --git a\/(\S+) b\/\1$/gm)].map(m => m[1]);
        assert.deepEqual(names, [appsPath, corePath]);
        applyRequired();
        candidate = {apps: fs.readFileSync(path.join(stage, appsPath), 'utf8'), core: fs.readFileSync(path.join(stage, corePath), 'utf8')};
        applyRequired();
        assert.equal(fs.readFileSync(path.join(stage, appsPath), 'utf8'), candidate.apps);
        assert.equal(fs.readFileSync(path.join(stage, corePath), 'utf8'), candidate.core);
        git('-C', stage, 'apply', '--reverse', '--check', patchPath);
        git('-C', stage, 'apply', '--reverse', patchPath);
        assert.equal(fs.readFileSync(path.join(stage, appsPath), 'utf8'), baseline.apps);
        assert.equal(fs.readFileSync(path.join(stage, corePath), 'utf8'), baseline.core);
        applyRequired();
        write(path.join(directory, 'source-lineage.json'), JSON.stringify({pin, prerequisites: ['branding', 'account-picker-readiness'],
            baseline: {apps: digest(baseline.apps), core: digest(baseline.core)},
            candidate: {apps: digest(candidate.apps), core: digest(candidate.core)}}, null, 2) + '\n');
    });
    test('before-fix deferred Myaccount completion overwrites ACDC and shortcuts', () => {
        const t = setup(baseline); t.load('myaccount', {background: true}); t.activate('acdc');
        t.complete('myaccount'); assert.equal(t.active(), 'myaccount');
        assert.equal(t.shortcutCalls.at(-1)[2], 'myaccount');
    });
    test('deferred background plugins preserve the latest foreground app and shortcuts', () => {
        for (const name of ['myaccount', 'common', 'apploader', 'fixture-extra']) {
            const t = setup(); t.load(name, {background: true}); t.activate('acdc');
            const shortcuts = t.shortcutCalls.slice(); const loaded = t.complete(name);
            assert.equal(t.active(), 'acdc'); assert.deepEqual(t.shortcutCalls, shortcuts);
            assert.equal(t.callbacks.at(-1).loaded, loaded); assert.equal(t.callbacks.at(-1).error, null);
        }
    });
    test('background completion cannot restore an older captured foreground value', () => {
        const t = setup(); t.activate('acdc'); t.load('common', {background: true}); t.activate('voip');
        const shortcuts = t.shortcutCalls.slice(); t.complete('common');
        assert.equal(t.active(), 'voip'); assert.deepEqual(t.shortcutCalls, shortcuts);
    });
    test('cached background loads still callback without resource reads or activation', () => {
        const t = setup(); t.activate('acdc'); t.monster.apps.common = t.app('common');
        const reads = t.loads.length, shortcuts = t.shortcutCalls.slice(); t.load('common', {background: true});
        assert.equal(t.active(), 'acdc'); assert.equal(t.loads.length, reads); assert.deepEqual(t.shortcutCalls, shortcuts);
        assert.equal(t.callbacks.at(-1).loaded, t.monster.apps.common);
    });
    test('only literal true selects background behavior; foreground callback sees activation', () => {
        for (const options of [undefined, null, {}, {background: false}, {background: 'true'}, {background: 1}]) {
            const t = setup(); t.activate('acdc'); t.monster.apps.myaccount = t.app('myaccount');
            let seen;
            t.monster.apps.load('myaccount', (error, loaded) => { seen = [error, loaded, t.active(), t.shortcutCalls.at(-1)[2]]; }, options);
            assert.equal(seen[0], null); assert.equal(seen[1], t.monster.apps.myaccount);
            assert.deepEqual(seen.slice(2), ['myaccount', 'myaccount']);
        }
    });
    test('error identity and no-callback loads preserve native behavior', () => {
        for (const background of [true, false]) {
            const t = setup(); t.activate('acdc'); const shortcuts = t.shortcutCalls.slice(), error = Error('offline_fixture');
            t.load('common', {background}); t.complete('common', error);
            assert.equal(t.callbacks.at(-1).error, error); assert.equal(t.callbacks.at(-1).loaded, undefined);
            assert.equal(t.active(), 'acdc'); assert.deepEqual(t.shortcutCalls, shortcuts);
            t.monster.apps.load('common', undefined, {background}); t.complete('common', error);
            assert.equal(t.active(), 'acdc');
        }
    });
    test('resource options pass through unchanged and callbacks are not duplicated', () => {
        const t = setup(), options = {background: true, sourceUrl: '/fixture', apiUrl: '/fixture-api'};
        t.load('common', options); assert.equal(t.loads[0].options, options); t.complete('common');
        assert.equal(t.callbacks.length, 1); assert.equal(t.active(), undefined); assert.equal(t.shortcutCalls.length, 0);
    });
    test('actual Core both plugin branches use background loading and preserve foreground', () => {
        const t = setup(undefined, {additional: ['fixture-extra'], routeMatch: true});
        t.core._loadApps({defaultApp: 'acdc'}); t.activate('acdc'); const shortcuts = t.shortcutCalls.slice();
        for (const name of ['common', 'apploader', 'myaccount', 'fixture-extra']) {
            assert.equal(t.loads.find(load => load.name === name).options.background, true);
            t.complete(name); assert.equal(t.active(), 'acdc'); assert.deepEqual(t.shortcutCalls, shortcuts);
        }
        assert.equal(t.core.appFlags.accountBrowserState, 'ready'); assert.deepEqual(t.routes, ['parse']);
    });
    test('cached Common readiness survives and native default routing still activates ACDC', () => {
        const t = setup(); t.monster.apps.common = t.app('common'); t.core._loadApps({defaultApp: 'acdc'});
        assert.equal(t.core.appFlags.accountBrowserState, 'ready'); assert.equal(t.active(), undefined);
        t.complete('myaccount'); t.complete('apploader'); assert.deepEqual(t.routes, ['parse', 'apps/acdc']);
        assert.equal(t.active(), undefined); t.complete('acdc'); assert.equal(t.active(), 'acdc');
        assert.equal(t.shortcutCalls.at(-1)[2], 'acdc');
    });
    test('Core Common error retains failed readiness and does not claim activation', () => {
        const t = setup(undefined, {routeMatch: true}); t.activate('acdc'); t.core._loadApps({});
        const error = Error('offline_common_failure'); t.complete('common', error);
        assert.equal(t.core.appFlags.accountBrowserState, 'failed'); assert.equal(t.active(), 'acdc');
        t.complete('myaccount'); t.complete('apploader'); assert.equal(t.active(), 'acdc');
        assert.deepEqual(t.routes, ['parse']);
    });
    test('installer registers after prerequisites and fails closed on conflicting source', () => {
        assert(hook('monster_ui_build_fingerprint').includes('monster-ui-background-app-load.patch:patches/monster-ui-background-app-load.patch'));
        const sync = hook('sync_monster_ui_sources');
        const registration = 'apply_required_source_patch "$source_dir" "$SCRIPT_DIR/patches/monster-ui-background-app-load.patch"';
        assert(sync.includes(registration));
        assert(sync.indexOf(registration) > sync.indexOf('apply_required_source_patch "$source_dir" "$SCRIPT_DIR/patches/monster-ui-account-picker-readiness.patch"'));
        const file = path.join(stage, appsPath), original = fs.readFileSync(file, 'utf8');
        write(file, original.replace('options.background !== true', 'options.background !== "operator-change"'));
        const changed = fs.readFileSync(file, 'utf8'); assert.throws(applyRequired, error => error.status === 65);
        assert.equal(fs.readFileSync(file, 'utf8'), changed); write(file, original);
    });
    console.log('PASS ' + passed + ' offline background-app groups');
} finally {
    const after = hashes(), stable = JSON.stringify(before) === JSON.stringify(after);
    write(path.join(directory, 'inputs.after.json'), JSON.stringify(after, null, 2) + '\n');
    write(path.join(directory, 'receipt.json'), JSON.stringify({kind: 'offline_actual_amd_background_load', mode: baselineMode ? 'baseline' : 'candidate',
        groups: passed, checks, input_pins_stable: stable, actual_load_and_shortcuts_executed: true,
        resource_loader_controlled: true, routing_controlled: true, browser_executed: false, api_calls: 0}, null, 2) + '\n');
    assert(stable, 'Background-app inputs changed during validation');
}
