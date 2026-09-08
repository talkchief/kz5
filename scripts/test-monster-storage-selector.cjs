'use strict';
// UI-01: execute the actual AMD selector; no network, credentials or writes.
const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const source = fs.readFileSync(process.argv[2], 'utf8');
const lodash = require(require.resolve('lodash', {paths: [process.cwd()]}));
let groups = 0, failures = 0;
function test(name, run) {
    groups++;
    try {run(); console.log('PASS ' + name);} catch (error) {failures++; console.error('FAIL ' + name + ': ' + error.message);}
}
function fixture() {
    let app, request;
    const picks = [], notices = [], failures = [], selected = [], globalErrors = [];
    const monster = {ui: {fullScreenPicker: v => picks.push(v), toast: v => notices.push(v)},
        parallel(tasks, done) {tasks.storage((error, data) => done(error, {storage: data}));}};
    vm.runInNewContext(source, {define(factory) {app = factory(name => name === 'lodash' ? lodash : name === 'monster' ? monster : {extend: (deep, target, ...items) => lodash.merge(target, ...items)});}});
    app.accountId = 'a'.repeat(32);
    app.i18n = {active: () => ({storageSelector: {unavailable: 'Storage options are unavailable for this account.'}})};
    app.callApi = options => {assert.equal(options.resource, 'storage.get'); assert.equal(options.data.accountId, app.accountId); request = options;};
    return {app, picks, notices, failures, selected, globalErrors,
        render(extra = {}) {app.storageSelectorRender({...extra, error: error => failures.push(error), callback: choice => selected.push(choice)});},
        reply(data) {request.success({data});},
        fail(status) {if (request.error) request.error({status: 'error'}, status === undefined ? undefined : {status}, data => globalErrors.push(data));},
        getRequest: () => request};
}
test('404 settles as unavailable, never opens picker or selects a fake plan', () => {
    const f = fixture(); f.render(); f.fail(404);
    assert.equal(f.failures.length, 1); assert.equal(f.failures[0].status, 404);
    assert.equal(f.notices.length, 1); assert.equal(f.notices[0].type, 'warning');
    assert.equal(f.globalErrors.length, 0); assert.equal(f.picks.length, 0); assert.equal(f.selected.length, 0);
});
test('401,403,500 and transport errors settle and retain the genuine error handler', () => {
    for (const status of [401,403,500,0,undefined]) {
        const f = fixture(); f.render(); f.fail(status);
        assert.equal(f.failures.length, 1); assert.equal(f.globalErrors.length, 1);
        assert.equal(f.picks.length, 0); assert.equal(f.selected.length, 0); assert.equal(f.notices.length, 0);
    }
});
test('missing or empty successful storage data does not throw or offer phantom choices', () => {
    for (const data of [undefined, null, {}, {attachments: {}}]) {
        const f = fixture(); f.render(); f.reply(data);
        assert.equal(f.failures[0].code, 'no_storage_options'); assert.equal(f.notices.length, 1);
        assert.equal(f.picks.length, 0); assert.equal(f.selected.length, 0);
    }
});
test('configured storage still displays and returns the selected real attachment', () => {
    const f = fixture(), data = {attachments: {one: {handler: 's3', name: 'Existing storage'}}};
    f.render(); f.reply(data); assert.equal(f.picks.length, 1); assert.equal(f.picks[0].choices[0].id, 'one');
    f.picks[0].afterSelected('one'); assert.deepEqual(JSON.parse(JSON.stringify(f.selected)), [{id:'one', handler:'s3', name:'Existing storage'}]);
    assert.equal(f.failures.length, 0); assert.equal(f.notices.length, 0);
});
test('caller-provided storage avoids network and preserves selection behavior', () => {
    const f = fixture(); f.render({data: {attachments: {one: {handler:'s3',name:'Existing'}}}});
    assert.equal(f.getRequest(), undefined); assert.equal(f.picks.length, 1);
});
test('optional lookup opts out of generic error only for handled absence', () => {
    const f = fixture(); f.render(); assert.equal(f.getRequest().data.generateError, false);
});
const installer = fs.readFileSync(__dirname + '/install-kazoo5.sh', 'utf8');
test('installer fingerprints and requires the source patch', () => {
    assert(installer.includes('monster-ui-storage-selector-errors.patch:patches/monster-ui-storage-selector-errors.patch'));
    assert(installer.includes('apply_required_source_patch "$source_dir" "$SCRIPT_DIR/patches/monster-ui-storage-selector-errors.patch"'));
});
console.log(JSON.stringify({groups, failures, network:false, live_writes:false}));
process.exitCode = failures ? 1 : 0;
