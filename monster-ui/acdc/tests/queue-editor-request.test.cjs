'use strict';
// Offline actual Monster request serializer + actual ACDC wrapper/save methods.
// Only AJAX, UI widgets and unrelated framework dependencies are doubles.
// No browser, HTTP, queue creation, credentials or backend writes.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const lodash = require(require.resolve('lodash', {paths: [process.cwd()]}));
const appFile = path.resolve(__dirname, '../app.js');
const frameworkFile = process.env.KAZOO_MONSTER_REQUEST_SOURCE
    || '/usr/local/src/kazoo5-installer/monster-ui/src/js/lib/monster.js';
const backendFile = path.resolve(__dirname, '../../../applications/acdc/src/cb_acdc_queue_editor.erl');
const inputs = [appFile, frameworkFile, backendFile].map(file => ({file, bytes: fs.readFileSync(file)}));
const A = 'a'.repeat(32), Q = 'b'.repeat(32), U = 'c'.repeat(32), R = 'd'.repeat(32);
const keys = ['queue', 'request_id', 'revisions', 'roster', 'route'].sort();
const plain = value => JSON.parse(JSON.stringify(value));
let groups = 0;
function test(name, run) { run(); console.log('PASS ' + (++groups) + ' ' + name); }
function freeze(value) {
    if (value && typeof value === 'object') { Object.values(value).forEach(freeze); Object.freeze(value); }
    return value;
}
function body(edit = false) {
    return {queue: {name: 'Support', announcements: {language: 'en-us', ...(edit ? {media: null} : {})},
        callback: {enabled: false, ...(edit ? {media: null, return_confirmation_prompt: null} : {})}},
    roster: edit ? null : [U], route: edit ? null : {extension: ''},
    revisions: {queue: edit ? '1-queue' : null, users: {[U]: '1-user'}, callflows: {}}, request_id: R};
}
function fixture() {
    let app, monster;
    const sent = [];
    const $ = {each: lodash.forEach, parseJSON: JSON.parse,
        // jQuery's deep target extension semantics for these object-only payloads.
        extend(deep, target, ...sources) {
            assert.equal(deep, true);
            return lodash.merge(target, ...sources);
        },
        ajax(settings) { sent.push(settings); return {abort() { assert.fail('No write cancellation'); }}; }};
    const dependencies = {jquery: $, lodash, cookies: {get() {}, set() {}, remove() {}},
        postal: {channel: () => ({}), publish() {}}};
    vm.runInNewContext(inputs[1].bytes.toString('utf8'), {
        define(factory) { monster = factory(name => dependencies[name] || {}); },
        window: {location: {protocol: 'https:', hostname: 'fixture.invalid'}}, console
    }, {filename: frameworkFile, timeout: 1000});
    monster.config = {api: {default: 'https://fixture.invalid/v2/'}};
    monster.util = {getVersion: () => 'fixture-version', isLoggedIn: () => false};
    monster.error = () => {};
    vm.runInNewContext(inputs[0].bytes.toString('utf8'), {
        define(factory) { app = factory(name => name === 'jquery' ? $ : name === 'lodash' ? lodash : monster); },
        setTimeout() { assert.fail('Editor writes must not gain a read timeout'); }, clearTimeout() {}
    }, {filename: appFile, timeout: 1000});
    app.accountId = A;
    app.getAuthToken = () => 'synthetic-never-sent';
    for (const resource of ['acdc.editor.create', 'acdc.editor.update']) {
        monster._defineRequest(resource, app.requests[resource], app);
    }
    return {app, monster, sent};
}
function wire(settings, edit) {
    assert.equal(settings.type, edit ? 'PATCH' : 'PUT');
    assert.equal(settings.contentType, 'application/json');
    const url = new URL(settings.url);
    assert.equal(url.origin, 'https://fixture.invalid');
    assert.equal(url.pathname, '/v2/accounts/' + A + '/queues/' + (edit ? Q + '/' : '') + 'editor');
    assert.equal(url.search, '');
    const payload = JSON.parse(settings.data);
    assert.deepEqual(Object.keys(payload), ['data']);
    assert.deepEqual(Object.keys(payload.data).sort(), keys);
    assert(!Object.hasOwn(payload.data, 'ui_metadata'));
    assert(!Object.hasOwn(payload.data, 'removeMetadataAPI'));
    return payload.data;
}
try {
    test('backend still rejects an extra metadata field before any operation receipt lookup', () => {
        const backend = inputs[2].bytes.toString('utf8');
        const allowed = backend.match(/Allowed = \[(.*?)\],/s);
        assert(allowed);
        assert.deepEqual([...allowed[1].matchAll(/<<"([a-z_]+)">>/g)].map(m => m[1]).sort(), keys);
        assert(backend.includes('lists:sort(kz_json:get_keys(Body)) =:= lists:sort(Allowed), 400, <<"editor_body_requires_exact_fields">>'));
        const prepare = backend.slice(backend.indexOf('prepare_write(Context, QueueId) ->'));
        assert(prepare.indexOf('check_body(Body)') < prepare.indexOf('kz_datamgr:open_doc('));
    });
    test('negative control: the unchanged native serializer adds the rejected metadata without opt-out', () => {
        const f = fixture();
        f.monster.request({resource: 'acdc.editor.create', data: {accountId: A, data: body()}});
        const actual = JSON.parse(f.sent[0].data).data;
        assert.deepEqual(actual.ui_metadata, {version: 'fixture-version', ui: 'monster-ui'});
        assert.deepEqual(Object.keys(actual).sort(), [...keys, 'ui_metadata'].sort());
        assert.notDeepEqual(Object.keys(actual).sort(), keys);
    });
    for (const edit of [false, true]) {
        test((edit ? 'PATCH' : 'PUT') + ' serializes exactly the frozen input body without metadata or option leakage', () => {
            const f = fixture(), value = freeze(body(edit));
            const data = freeze({data: value, ...(edit ? {queueId: Q} : {})});
            const before = JSON.stringify(data);
            let result;
            f.app.requestQueueEditor(edit ? 'acdc.editor.update' : 'acdc.editor.create', data, (error, reply) => {
                assert.equal(error, null); result = reply;
            });
            assert.equal(f.sent.length, 1);
            assert.deepEqual(wire(f.sent[0], edit), plain(value));
            assert.equal(JSON.stringify(data), before);
            f.sent[0].success({status: 'success', data: {queue_id: Q, state: 'complete'}});
            assert.deepEqual(result, {queue_id: Q, state: 'complete'});
        });
    }
    test('editor wrapper forces its local opt-out without changing a caller option or body', () => {
        const f = fixture(), data = freeze({data: body(), removeMetadataAPI: false});
        f.app.requestQueueEditor('acdc.editor.create', data, () => {});
        assert.deepEqual(wire(f.sent[0], false), plain(data.data));
        assert.equal(data.removeMetadataAPI, false);
    });
    for (const edit of [false, true]) {
        test((edit ? 'update' : 'create') + ' save/retry preserves one request ID, the original fingerprint and exact wire bytes', () => {
            const f = fixture(), value = body(edit), values = {'editor-revisions': value.revisions};
            const view = {data(key, val) { if (arguments.length === 1) return values[key]; values[key] = val; return this; },
                removeData(key) { delete values[key]; return this; }};
            let minted = 0, rejected = 0, rendered = 0;
            f.app.newEditorRequestId = () => { minted++; return R; };
            f.app.setFormBusy = () => {};
            f.app.isCurrentView = () => true;
            f.app.showFormError = () => { rejected++; };
            f.app.toastSuccess = () => {};
            f.app.renderQueues = () => { rendered++; };
            f.app.i18n.active = () => ({acdc: {queues: {saved: 'saved'}}});
            const save = queue => f.app.saveQueue(edit ? Q : undefined, queue, value.roster, edit ? null : '', view, 1, A);
            save(value.queue);
            const pending = values['editor-pending'], fingerprint = pending.fingerprint;
            assert.equal(fingerprint, JSON.stringify({queue: value.queue, roster: value.roster,
                route: value.route, revisions: value.revisions}));
            assert.deepEqual(Object.keys(pending.body).sort(), keys);
            const pendingBefore = JSON.stringify(pending.body);
            save(value.queue); // No automatic retry; exercise an explicit identical invocation.
            assert.equal(minted, 1); assert.equal(f.sent.length, 2);
            assert.equal(f.sent[0].data, f.sent[1].data);
            assert.deepEqual(wire(f.sent[0], edit), plain(value));
            assert.equal(values['editor-pending'], pending);
            assert.equal(pending.fingerprint, fingerprint);
            assert.equal(JSON.stringify(pending.body), pendingBefore);
            save({...value.queue, name: 'Changed after an unresolved save'});
            assert.equal(rejected, 1); assert.equal(f.sent.length, 2); assert.equal(minted, 1);
            f.sent[1].success({status: 'success', data: {queue_id: Q, state: 'complete'}});
            assert.equal(values['editor-pending'], undefined); assert.equal(rendered, 1);
        });
    }
    test('native HTTP rejection remains an error and is never converted into save success', () => {
        const f = fixture(); let result, replies = 0;
        f.app.requestQueueEditor('acdc.editor.create', {data: body()}, (error, value) => {
            replies++; result = error; assert.equal(value, undefined);
        });
        const rejection = {status: 400, message: 'editor_body_requires_exact_fields', data: {}};
        f.sent[0].error(rejection);
        assert.equal(result, rejection); assert.equal(replies, 1); assert.equal(f.sent.length, 1);
    });
    console.log(JSON.stringify({result: 'PASS', groups, network: false, browser: false, backend_writes: false}));
} finally {
    for (const input of inputs) {
        assert(input.bytes.equals(fs.readFileSync(input.file)), 'Source input changed during fixture');
        console.log('INPUT ' + crypto.createHash('sha256').update(input.bytes).digest('hex') + ' ' + input.file);
    }
}
