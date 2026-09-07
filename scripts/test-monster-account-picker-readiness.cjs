#!/usr/bin/env node
'use strict';
// Actual pinned Core + accountBrowser AMD source, controlled native-load callback
// and tiny DOM doubles. No browser, HTTP, credentials, account writes or sleeps.
// Patch replay/installer repeat checks only mutate a retained private fixture.
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const vm = require('node:vm'), cp = require('node:child_process'), crypto = require('node:crypto');
const assert = require('node:assert/strict');
const cache = process.argv[2] || '/usr/local/src/kazoo5-installer/monster-ui';
assert(process.argv.length <= 3 && path.isAbsolute(cache), 'Only an absolute existing framework cache is accepted');
const pin = '7ef735eada6fd0e2b96c06f32c0bb868867f7d18';
const corePath = 'src/apps/core/app.js', viewPath = 'src/apps/core/views/app.html';
const localePath = 'src/apps/core/i18n/en-US.json';
const browserPath = 'src/apps/common/submodules/accountBrowser/accountBrowser.js';
const patchPath = path.join(__dirname, 'patches/monster-ui-account-picker-readiness.patch');
const brandingPath = path.join(__dirname, 'patches/monster-ui-branding-billing.patch');
const installerPath = path.join(__dirname, 'install-kazoo5.sh');
const lodashPath = require.resolve(path.join(cache, 'node_modules/lodash'));
const lodash = require(lodashPath), installer = fs.readFileSync(installerPath, 'utf8');
const env = Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith('GIT_')));
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'monster-account-picker-proof.'));
fs.chmodSync(directory, 0o700);
console.log('Retaining offline account-picker evidence in ' + directory);
const stage = path.join(directory, 'source');
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const inputFiles = [__filename, patchPath, brandingPath, installerPath, lodashPath, process.execPath, '/usr/bin/git', '/bin/bash'];
const hashes = () => inputFiles.map(file => ({file, sha256: digest(fs.readFileSync(file))}));
const before = hashes();
const write = (file, bytes) => { fs.mkdirSync(path.dirname(file), {recursive: true}); fs.writeFileSync(file, bytes); };
write(path.join(directory, 'inputs.before.json'), JSON.stringify(before, null, 2) + '\n');
function git(...args) {
    return cp.execFileSync('/usr/bin/git', args, {encoding: 'utf8', env, timeout: 10000, stdio: ['ignore', 'pipe', 'pipe']});
}
function hook(name) {
    const found = installer.match(new RegExp('^' + name + '\\(\\) \\{[\\s\\S]*?^\\}', 'm'));
    assert(found, 'Missing actual installer hook: ' + name); return found[0];
}
function applyRequired() {
    cp.execFileSync('/bin/bash', ['--noprofile', '--norc', '-s', '--', stage, patchPath], {
        encoding: 'utf8', env, timeout: 10000, stdio: ['pipe', 'pipe', 'pipe'],
        input: 'set -euo pipefail\nDRY_RUN=false\nlog(){ :; }\ndie(){ exit 65; }\n'
            + hook('apply_required_source_patch') + '\napply_required_source_patch "$1" "$2"\n'
    });
}
let source, baseline, browserSource, labels, passed = 0;
const checks = [];
function test(name, body) { body(); passed++; checks.push(name); console.log('PASS ' + name); }
function setup(bytes = source, options = {}) {
    const nodes = new Map(), publications = [], templates = [], lists = [], eventBindings = [], loads = [], routes = [];
    let core, common, parseCount = 0, parallelCallbacks = 0;
    function query(selector) {
        assert.equal(typeof selector, 'string');
        if (nodes.has(selector)) return nodes.get(selector);
        const node = {attributes: {}, classes: new Set(), visible: true, content: '',
            attr(key, value) { if (value === undefined) return this.attributes[key]; this.attributes[key] = value; return this; },
            removeAttr(key) { delete this.attributes[key]; return this; },
            toggleClass(key, enabled) { enabled ? this.classes.add(key) : this.classes.delete(key); return this; },
            addClass(key) { this.classes.add(key); return this; },
            removeClass(key) { this.classes.delete(key); return this; },
            hasClass(key) { return this.classes.has(key); },
            find(child) { return query(selector + ' ' + child); },
            text(value) { this.content = value; return this; },
            html(value) { this.content = value; return this; },
            toggle(value) { this.visible = value; return this; },
            remove() { return this; }, empty() { this.content = ''; return this; },
            append(value) { this.content = value; return this; }};
        nodes.set(selector, node); return node;
    }
    const monster = {config: {whitelabel: {additionalLoggedInApps: options.additional || []}},
        util: {isAdmin: () => options.admin !== false},
        routing: {parseHash() { parseCount++; }, hasMatch: () => Boolean(options.routeMatch), goTo: value => routes.push(value)},
        apps: {auth: {currentAccount: {id: 'a'.repeat(32)}}, load(name, callback) { loads.push({name, callback}); }},
        parallel(tasks, done) {
            let remaining = tasks.length, finished = false;
            if (!remaining) { parallelCallbacks++; return done(null, []); }
            tasks.forEach(task => {
                let called = false;
                task((error, value) => {
                    assert(!called, 'Native plugin callback must not settle twice'); called = true;
                    if (finished) return;
                    if (error || --remaining === 0) { finished = true; parallelCallbacks++; done(error, [value]); }
                });
            });
        },
        pub(topic, args) {
            publications.push({topic, args});
            // Real accountBrowser public handler, with a deliberately partial
            // Common before the controlled successful native load callback.
            if (topic === 'common.accountBrowser.render') common.accountBrowserRender.call(common, args);
        }};
    function amd(bytes, file) {
        let app;
        vm.runInNewContext(bytes, {define(factory) { app = factory(name => {
            if (name === 'jquery') return query;
            if (name === 'lodash') return lodash;
            if (name === 'monster') return monster;
            throw Error('Unexpected source dependency');
        }); }, console: {warn() {}}, window: {}, document: {}}, {filename: file, timeout: 1000});
        return app;
    }
    core = amd(bytes, corePath); common = amd(browserSource, browserPath);
    core.i18n = {active: () => labels};
    if (options.cachedCommon) monster.apps.common = common;
    if (options.cachedMyaccount) monster.apps.myaccount = {};
    const link = query('#main_topbar_account_toggle_link');
    link.attr('aria-disabled', 'true').attr('tabindex', '-1').addClass('disabled');
    function complete(load, error = null) {
        assert(load, 'Expected native load request');
        if (load.name === 'common' && !error) {
            common.getTemplate = args => { templates.push(args); return '<fixture-layout>'; };
            common.accountBrowserRenderList = args => lists.push(args);
            common.accountBrowserBindEvents = args => eventBindings.push(args);
            common.callApi = () => { throw Error('No API allowed by this fixture'); };
            common.i18n = {active: () => labels};
            common.accountId = monster.apps.auth.currentAccount.id;
            monster.apps.common = common;
        }
        load.callback(error, load.name === 'common' ? common : {});
    }
    return {core, common, monster, nodes, publications, templates, lists, eventBindings, loads, routes, link,
        status: query('#main_topbar_account_toggle_link .account-browser-readiness-status'), complete,
        nativeCommon: () => loads.find(load => load.name === 'common'),
        finishOthers() { loads.filter(load => load.name !== 'common').forEach(load => complete(load)); },
        counts: () => ({parseCount, parallelCallbacks})};
}
function assertClosed(t) {
    assert.equal(t.publications.filter(event => event.topic === 'common.accountBrowser.render').length, 0);
    assert.equal(t.nodes.get('#main_topbar_account_toggle')?.hasClass('open') || false, false);
    assert.equal(t.link.attr('aria-disabled'), 'true');
}
try {
    test('actual installer fresh/repeat/reverse patch replay preserves pinned source and branding', () => {
        for (const relative of [corePath, viewPath, localePath, browserPath]) {
            write(path.join(stage, relative), git('-C', cache, 'show', pin + ':' + relative));
        }
        git('-C', stage, 'apply', '--include=' + corePath, brandingPath);
        baseline = fs.readFileSync(path.join(stage, corePath), 'utf8');
        browserSource = fs.readFileSync(path.join(stage, browserPath), 'utf8');
        const browserHash = digest(browserSource);
        applyRequired(); source = fs.readFileSync(path.join(stage, corePath), 'utf8');
        const first = [corePath, viewPath, localePath].map(file => digest(fs.readFileSync(path.join(stage, file))));
        applyRequired();
        assert.deepEqual([corePath, viewPath, localePath].map(file => digest(fs.readFileSync(path.join(stage, file)))), first);
        git('-C', stage, 'apply', '--reverse', '--check', patchPath);
        git('-C', stage, 'apply', '--reverse', patchPath);
        assert.equal(fs.readFileSync(path.join(stage, corePath), 'utf8'), baseline);
        applyRequired(); assert.equal(fs.readFileSync(path.join(stage, corePath), 'utf8'), source);
        assert.equal(digest(fs.readFileSync(path.join(stage, browserPath))), browserHash);
        labels = JSON.parse(fs.readFileSync(path.join(stage, localePath), 'utf8'));
        const names = [...fs.readFileSync(patchPath, 'utf8').matchAll(/^diff --git a\/(\S+) b\/\1$/gm)].map(match => match[1]);
        assert.deepEqual(names, [corePath, viewPath, localePath]);
        write(path.join(directory, 'source-lineage.json'), JSON.stringify({pin, baseline_sha256: digest(baseline),
            candidate_sha256: digest(source), account_browser_sha256: browserHash, patched_files: first}, null, 2) + '\n');
    });
    test('before-fix actual Core click reaches partial actual accountBrowser and throws', () => {
        const t = setup(baseline); t.core._loadApps({defaultApp: 'acdc'});
        assert.throws(() => t.core.toggleAccountToggle(), /getTemplate/);
        assert.equal(t.publications.filter(event => event.topic === 'common.accountBrowser.render').length, 1);
        assert.equal(t.templates.length, 0);
    });
    test('initial template is disabled with accessible loading status, not only a CSS hint', () => {
        const view = fs.readFileSync(path.join(stage, viewPath), 'utf8');
        assert.match(view, /id="main_topbar_account_toggle_link" aria-disabled="true" tabindex="-1"/);
        assert.match(view, /class="account-browser-readiness-status" role="status" aria-live="polite"/);
        assert.match(labels.accountToggle.failed, /Reload this page to retry\./);
    });
    test('direct and toggle clicks before or during Common loading publish nothing', () => {
        const t = setup(); t.core.showAccountToggle(); t.core.toggleAccountToggle(); assertClosed(t);
        t.core._loadApps({defaultApp: 'acdc'}); t.core.toggleAccountToggle(); t.core.showAccountToggle(); assertClosed(t);
        assert.equal(t.core.appFlags.accountBrowserState, 'loading'); assert.equal(t.status.content, labels.accountToggle.loading);
        t.finishOthers(); t.core.toggleAccountToggle(); assertClosed(t);
    });
    test('getter presence or publication of a partial Common cannot enable the picker', () => {
        const t = setup(source, {cachedCommon: true});
        t.common.getTemplate = () => { throw Error('Must not inspect template as readiness'); };
        t.core._loadApps({defaultApp: 'acdc'}); assert(t.nativeCommon());
        t.core.toggleAccountToggle(); assertClosed(t);
        assert.equal(t.core.appFlags.accountBrowserState, 'loading');
    });
    test('successful native Common callback enables actual public render exactly once per open', () => {
        const t = setup(); t.core._loadApps({defaultApp: 'acdc'}); t.complete(t.nativeCommon());
        assert.equal(t.core.appFlags.accountBrowserState, 'ready'); assert.equal(t.link.attr('aria-disabled'), 'false');
        assert.equal(t.link.attr('tabindex'), undefined); assert.equal(t.link.hasClass('disabled'), false);
        assert.equal(t.status.visible, false); assert.equal(t.status.content, '');
        t.core.toggleAccountToggle(); assert.equal(t.templates.length, 1); assert.equal(t.lists.length, 1);
        assert.equal(t.eventBindings.length, 1); assert.equal(t.templates[0].submodule, 'accountBrowser');
        t.core.toggleAccountToggle(); assert.equal(t.templates.length, 1);
        assert.equal(t.nodes.get('#main_topbar_account_toggle').hasClass('open'), false);
    });
    test('Common failure stays disabled with fixed reload instruction and no automatic retry', () => {
        const t = setup(); t.core._loadApps({defaultApp: 'acdc'});
        t.complete(t.nativeCommon(), Error('SYNTHETIC_FAILURE_NOT_DISPLAYED'));
        t.core.toggleAccountToggle(); t.core.showAccountToggle(); assertClosed(t);
        assert.equal(t.core.appFlags.accountBrowserState, 'failed'); assert.equal(t.status.content, labels.accountToggle.failed);
        assert.equal(t.loads.filter(load => load.name === 'common').length, 1);
        assert(!t.status.content.includes('SYNTHETIC'));
    });
    test('normal page reload gets a fresh loading generation and successful retry', () => {
        const failed = setup(); failed.core._loadApps({}); failed.complete(failed.nativeCommon(), Error('fixture failure'));
        const reloaded = setup(); reloaded.core._loadApps({}); assert.equal(reloaded.core.appFlags.accountBrowserState, 'loading');
        assertClosed(reloaded); reloaded.complete(reloaded.nativeCommon()); reloaded.core.toggleAccountToggle();
        assert.equal(reloaded.templates.length, 1); assert.equal(failed.core.appFlags.accountBrowserState, 'failed');
    });
    test('malformed success or cached pre-init/wrong-account Common fails closed', () => {
        for (const field of ['identity', 'getTemplate', 'accountBrowserRender', 'callApi', 'i18n', 'accountId', 'wrongAccount']) {
            const t = setup(); t.core._loadApps({});
            const common = t.common;
            Object.assign(common, {getTemplate() {}, callApi() {}, i18n: {active() {}}, accountId: 'a'.repeat(32)});
            t.monster.apps.common = common;
            if (field === 'identity') t.monster.apps.common = {};
            else if (field === 'wrongAccount') common.accountId = 'b'.repeat(32);
            else delete common[field];
            t.nativeCommon().callback(null, common);
            assert.equal(t.core.appFlags.accountBrowserState, 'failed', field); assertClosed(t);
        }
        for (const value of [undefined, null, false, {}]) {
            const t = setup(); t.core._loadApps({}); t.nativeCommon().callback(null, value);
            assert.equal(t.core.appFlags.accountBrowserState, 'failed'); assertClosed(t);
        }
    });
    test('additional Common entries still create exactly one native Common load task', () => {
        const t = setup(source, {additional: ['common', 'common']}); t.core._loadApps({});
        assert.equal(t.loads.filter(load => load.name === 'common').length, 1);
        t.complete(t.nativeCommon()); assert.equal(t.core.appFlags.accountBrowserState, 'ready');
    });
    test('duplicate success or failure callbacks cannot change settled readiness or settle parallel twice', () => {
        for (const firstError of [null, Error('fixture failure')]) {
            const t = setup(); t.core._loadApps({defaultApp: 'acdc'}); t.finishOthers();
            const load = t.nativeCommon(); t.complete(load, firstError);
            const state = t.core.appFlags.accountBrowserState, counts = t.counts();
            load.callback(firstError ? null : Error('late fixture failure'), t.common); load.callback(null, t.common);
            assert.equal(t.core.appFlags.accountBrowserState, state); assert.deepEqual(t.counts(), counts);
        }
    });
    test('late callback from previous load generation cannot enable or disable the current picker', () => {
        for (const oldError of [null, Error('old fixture failure')]) {
            const t = setup(); t.core._loadApps({}); const first = t.nativeCommon();
            t.core._loadApps({}); const second = t.loads.filter(load => load.name === 'common')[1];
            t.complete(first, oldError); assert.equal(t.core.appFlags.accountBrowserState, 'loading'); assertClosed(t);
            t.complete(second); assert.equal(t.core.appFlags.accountBrowserState, 'ready');
            first.callback(Error('duplicate old failure')); assert.equal(t.core.appFlags.accountBrowserState, 'ready');
        }
    });
    test('non-Common plugin completion/error and default/native-hash routing retain existing behavior', () => {
        for (const routeMatch of [false, true]) for (const error of [false, true]) {
            function trace(bytes) {
                const t = setup(bytes, {routeMatch, cachedMyaccount: true, additional: ['fixture-extra']});
                t.core._loadApps({defaultApp: 'acdc'});
                t.complete(t.loads.find(load => load.name === 'fixture-extra'), error ? Error('fixture plugin') : null);
                assert.equal(t.core.appFlags.accountBrowserState, bytes === baseline ? undefined : 'loading');
                t.complete(t.loads.find(load => load.name === 'apploader')); t.complete(t.nativeCommon());
                return {loads: t.loads.map(load => load.name), routes: t.routes, counts: t.counts()};
            }
            assert.deepEqual(trace(source), trace(baseline));
        }
    });
    test('installer fingerprints and applies readiness patch before build, and repeat hook fails closed on conflicts', () => {
        assert(hook('monster_ui_build_fingerprint').includes('monster-ui-account-picker-readiness.patch:patches/monster-ui-account-picker-readiness.patch'));
        assert(hook('sync_monster_ui_sources').includes('apply_required_source_patch "$source_dir" "$SCRIPT_DIR/patches/monster-ui-account-picker-readiness.patch"'));
        const file = path.join(stage, corePath), bytes = fs.readFileSync(file, 'utf8');
        write(file, bytes.replace("self._setAccountBrowserState(validCommon ? 'ready' : 'failed');", "self._setAccountBrowserState('operator-change');"));
        const changed = fs.readFileSync(file, 'utf8');
        assert.throws(applyRequired, error => error.status === 65);
        assert.equal(fs.readFileSync(file, 'utf8'), changed); write(file, bytes);
    });
    console.log('PASS ' + passed + ' offline account-picker readiness groups');
} finally {
    const after = hashes(); write(path.join(directory, 'inputs.after.json'), JSON.stringify(after, null, 2) + '\n');
    const stable = JSON.stringify(after) === JSON.stringify(before);
    write(path.join(directory, 'receipt.json'), JSON.stringify({kind: 'offline_actual_core_readiness', groups: passed, checks,
        input_pins_stable: stable, browser_executed: false, actual_native_loader_executed: false,
        api_calls: 0, account_mutations: 0}, null, 2) + '\n');
    assert(stable, 'Readiness inputs changed during validation');
}
