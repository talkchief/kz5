'use strict';
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path');
const cp = require('node:child_process'), os = require('node:os'), vm = require('node:vm');
const root = process.argv[2];
assert(root, 'Supply the pinned Monster UI source checkout');
const appRoot = path.join(root, 'src/apps/voip');
const original = (repo, file) => cp.execFileSync('git', ['show', 'HEAD:' + file], {cwd: repo, encoding: 'utf8'});
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'smartpbx-recovery.'));
const lodash = {
    assign: Object.assign,
    each: (obj, fn) => Object.entries(obj).forEach(([key, value]) => fn(value, key)),
    once: fn => { let used = false; return (...args) => { if (!used) { used = true; return fn(...args); } }; },
    bind: (fn, self) => fn.bind(self),
    find: (array, matcher) => array.find(typeof matcher === 'function' ? matcher : x => Object.keys(matcher).every(k => x[k] === matcher[k])),
    keyBy: (array, key) => Object.fromEntries(array.map(x => [x[key], x])),
    isEmpty: x => !Object.keys(x).length
};
function moduleFrom(source, monster) {
    let result;
    vm.runInNewContext(source, {define: fn => { result = fn(name => ({lodash, monster, jquery: {}, chart: {}})[name]); },
        document: {}, Error});
    return result;
}
function parallel(tasks, done) {
    let remaining = Object.keys(tasks).length, ended = false;
    const results = {};
    Object.entries(tasks).forEach(([key, task]) => task((error, data) => {
        if (ended) return;
        if (error) { ended = true; done(error, results); return; }
        results[key] = data;
        if (--remaining === 0) { ended = true; done(null, results); }
    }));
}
function loadCase(source, failing, duplicate = false, hasDirectory = true) {
    const mod = moduleFrom(source, {parallel}), requests = [];
    let callbacks = 0, error, formatted = 0;
    mod.accountId = 'fixture-account';
    mod.myOfficeFormatData = results => { formatted++; return results; };
    mod.getOrCreateMainVMBox = next => next(null, {});
    mod.callApi = options => {
        requests.push(options);
        if (options.resource === failing) {
            if (options.error) options.error({status: 503});
            if (duplicate) options.success({data: []});
            return;
        }
        const data = options.resource === 'numbers.list' ? {numbers: {}} :
            options.resource === 'directory.list' ? (hasDirectory ? [{name: 'SmartPBX Directory', id: 'directory'}] : []) : [];
        options.success({data});
    };
    mod.myOfficeLoadData((err) => { callbacks++; error = err; });
    return {callbacks, error, formatted, requests};
}
function sdk(source, verb) {
    const start = source.indexOf('\tfunction request(options) {');
    const end = source.indexOf('\n}(jQuery));', start);
    assert(start > 0 && end > start);
    let calls = 0;
    const $ = {extend: (...args) => Object.assign({}, ...args.filter(x => typeof x === 'object')),
        each: lodash.each, ajax: settings => { calls++; return settings; }};
    const fn = vm.runInNewContext('(' + source.slice(start, end).trim() + ')', {$, _: lodash, authTokens: {}});
    const events = [];
    const settings = fn({url: '/v2/accounts/fixture/devices', verb, data: {},
        onRequestEnd: () => events.push('end'), onRequestError: () => events.push('global-error'),
        error: () => events.push('error'), success: () => events.push('success')});
    return {settings, events, calls};
}
try {
    const sdkOld = original(root, 'src/js/lib/jquery.kazoosdk.js');
    const appOld = original(appRoot, 'app.js');
    const officeOld = original(appRoot, 'submodules/myOffice/myOffice.js');
    for (const [file, content] of Object.entries({'src/js/lib/jquery.kazoosdk.js': sdkOld,
        'app.js': appOld, 'submodules/myOffice/myOffice.js': officeOld,
        'i18n/en-US.json': original(appRoot, 'i18n/en-US.json')})) {
        const target = path.join(scratch, file);
        fs.mkdirSync(path.dirname(target), {recursive: true}); fs.writeFileSync(target, content);
    }
    assert.equal(sdk(sdkOld, 'get').settings.timeout, undefined, 'Reproduce unbounded GET');
    assert.equal(loadCase(officeOld, 'device.list').callbacks, 0, 'Reproduce failed read never settling');
    for (const name of ['monster-ui-bounded-sdk-reads.patch', 'monster-ui-smartpbx-loading-recovery.patch']) {
        const patch = path.join(__dirname, 'patches', name);
        cp.execFileSync('git', ['apply', '--check', patch], {cwd: scratch});
        cp.execFileSync('git', ['apply', patch], {cwd: scratch});
        cp.execFileSync('git', ['apply', '--reverse', '--check', patch], {cwd: scratch});
    }
    const sdkNew = fs.readFileSync(path.join(scratch, 'src/js/lib/jquery.kazoosdk.js'), 'utf8');
    for (const verb of ['get', 'GET', 'post', 'put', 'patch', 'delete']) {
        const f = sdk(sdkNew, verb);
        assert.equal(f.settings.timeout, verb.toLowerCase() === 'get' ? 15000 : undefined);
        f.settings.error({status: 0}, 'timeout');
        assert.deepEqual(f.events, ['end', 'global-error', 'error']); assert.equal(f.calls, 1);
    }
    const officeNew = fs.readFileSync(path.join(scratch, 'submodules/myOffice/myOffice.js'), 'utf8');
    for (const resource of ['account.get', 'user.list', 'device.list', 'numbers.list', 'channel.list',
        'callflow.list', 'numbers.listClassifiers', 'directory.list', 'directory.get']) {
        const r = loadCase(officeNew, resource, true);
        assert.equal(r.callbacks, 1, resource); assert(r.error, resource); assert.equal(r.formatted, 0);
    }
    for (const directory of [true, false]) {
        const r = loadCase(officeNew, null, false, directory);
        assert.equal(r.callbacks, 1); assert.equal(r.error, null); assert.equal(r.formatted, 1);
        assert(r.requests.every(x => !/create|update|delete/.test(x.resource)));
        assert(r.requests.every(x => x.data.accountId === 'fixture-account' && x.data.generateError === false));
    }
    const monster = {parallel, config: {whitelabel: {}, resellerId: 'fixture-reseller'}};
    const app = moduleFrom(fs.readFileSync(path.join(scratch, 'app.js'), 'utf8'), monster);
    let ended = 0;
    app.callApi = options => options.error();
    app.loadGlobalData(error => { assert(error); ended++; }); assert.equal(ended, 1);
    app.callApi = options => options.success({data: []});
    app.loadGlobalData(error => { assert.equal(error, null); ended++; }); assert.equal(ended, 2);
    monster.config.resellerId = '';
    app.callApi = () => { throw Error('No plan read expected'); };
    app.loadGlobalData(error => { assert.equal(error, null); ended++; }); assert.equal(ended, 3);
    const installer = fs.readFileSync(path.join(__dirname, 'install-kazoo5.sh'), 'utf8');
    for (const name of ['monster-ui-bounded-sdk-reads.patch', 'monster-ui-smartpbx-loading-recovery.patch']) {
        assert(installer.split(name).length >= 3, 'Fingerprint and required application: ' + name);
    }
    console.log('PASS original unbounded/hung reads reproduced; forward/reverse patches; GET timeout and unchanged mutations; 9 read failures/duplicate settlements; success/absent directory; no view writes; plan failure/success/no-reseller; installer wiring');
} finally { fs.rmSync(scratch, {recursive: true, force: true}); }
