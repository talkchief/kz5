#!/usr/bin/env node
'use strict';
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const cp = require('node:child_process'), vm = require('node:vm'), assert = require('node:assert/strict');
const cache = '/usr/local/src/kazoo5-installer/monster-ui';
const source = path.join(cache, 'src/apps/callflows');
const patch = path.join(__dirname, 'patches/monster-ui-call-forward-confirmation.patch');
const stage = fs.mkdtempSync(path.join(os.tmpdir(), 'monster-cfwd-test.'));
const _ = require(path.join(cache, 'node_modules/lodash'));
const git = (...args) => cp.execFileSync('/usr/bin/git', args, {encoding: 'utf8', timeout: 10000, maxBuffer: 4 * 1024 * 1024});
const files = ['app.js', 'views/accountSettings.html', 'i18n/en-US.json', 'i18n/de-DE.json'];
function element() {
    return {handlers: {}, attrs: {}, value: '', message: '', removed: false,
        on(event, fn) {this.handlers[event] = fn; return this;},
        prop(key, value) {if (arguments.length === 1) return this.attrs[key]; this.attrs[key] = value; return this;},
        val(value) {if (!arguments.length) return this.value; this.value = value; return this;},
        text(value) {this.message = value; return this;}, remove() {this.removed = true;}};
}
function fixture(admin = true, saved) {
    const elements = Object.fromEntries(['section', 'select', 'save', 'status', 'accountSave'].map(k => [k, element()]));
    const e = elements, requests = [];
    const monster = {config: {}, apps: {auth: {originalAccount: {superduper_admin: false}}},
        util: {isAdmin: () => admin, isSuperDuper: () => false}};
    let app;
    vm.runInNewContext(fs.readFileSync(path.join(stage, 'app.js'), 'utf8'), {define: factory => {
        app = factory(name => ({jquery: {}, lodash: _, monster})[name]);
    }});
    e.section.find = selector => ({'.forward-confirmation-language': e.select, '.forward-confirmation-save': e.save, '.forward-confirmation-status': e.status})[selector];
    const template = {attached: true, find: selector => ({'.forward-confirmation-settings': e.section, '.account-settings-update': e.accountSave})[selector],
        closest() {return {length: this.attached ? 1 : 0};}};
    const strings = JSON.parse(fs.readFileSync(path.join(stage, 'i18n/en-US.json'))).callflows.accountSettings.forwardConfirmation;
    const data = {account: {id: 'a'.repeat(32), name: 'Keep pending edits', ...(saved ? {call_forward_confirmation: {language: saved}} : {})}};
    app.i18n = {active: () => ({callflows: {accountSettings: {forwardConfirmation: strings}}})};
    app.accountId = data.account.id; app.callApi = request => requests.push(request);
    app.bindForwardedCallConfirmation(template, data);
    return {app, data, template, requests, strings, ...e};
}
try {
    assert.equal(git('-C', source, 'rev-parse', 'HEAD').trim(), '11d6a7f797576f2ddd3cbadf6474787e95d5c760');
    for (const file of files) {
        const target = path.join(stage, file); fs.mkdirSync(path.dirname(target), {recursive: true});
        fs.writeFileSync(target, git('-C', source, 'show', 'HEAD:' + file));
    }
    // Match installer order: the existing Callflows patch also repairs the
    // pinned upstream German JSON before this feature is applied.
    git('-C', stage, 'apply', path.join(__dirname, 'patches/monster-ui-callflows-acdc-queue.patch'));
    git('-C', stage, 'apply', '--check', patch); git('-C', stage, 'apply', patch);
    git('-C', stage, 'apply', '--reverse', '--check', patch);
    for (const file of ['i18n/en-US.json', 'i18n/de-DE.json']) JSON.parse(fs.readFileSync(path.join(stage, file)));
    const view = fs.readFileSync(path.join(stage, 'views/accountSettings.html'), 'utf8');
    assert(view.includes('value="he-il" dir="rtl">עברית') && view.includes('value="ar-sa" dir="rtl">العربية'));
    assert(!/<select[^>]*forward-confirmation-language[^>]*name=/.test(view));
    assert(fs.readFileSync(path.join(stage, 'app.js'), 'utf8').includes('delete newData.call_forward_confirmation;'));
    let f = fixture(); assert.equal(f.select.value, ''); assert.equal(f.save.attrs.disabled, true); assert.equal(f.requests.length, 0);
    for (const language of ['en-us', 'he-il', 'ar-sa', 'es-es', 'fr-fr']) {
        f = fixture(); f.select.val(language); f.select.handlers.change(); f.save.handlers.click(); f.save.handlers.click();
        assert.equal(f.requests.length, 1); assert.equal(f.requests[0].resource, 'account.patch');
        assert.deepEqual(JSON.parse(JSON.stringify(f.requests[0].data)), {accountId: f.data.account.id, data: {call_forward_confirmation: {language}}});
        assert.equal(f.accountSave.attrs.disabled, true);
        f.requests[0].success({data: {call_forward_confirmation: {language}}});
        assert.equal(f.data.account.call_forward_confirmation.language, language);
        assert.equal(f.data.account.name, 'Keep pending edits'); assert.equal(f.status.message, f.strings.saved);
    }
    f = fixture(true, 'he-il'); f.select.val(''); f.select.handlers.change(); f.save.handlers.click();
    assert.equal(f.requests[0].data.data.call_forward_confirmation.language, null);
    f.requests[0].success({data: {}}); assert(!Object.hasOwn(f.data.account, 'call_forward_confirmation'));
    f = fixture(true, 'he-il'); f.select.val('ar-sa'); f.save.handlers.click(); f.requests[0].error();
    assert.equal(f.data.account.call_forward_confirmation.language, 'he-il'); assert.equal(f.status.message, f.strings.failed);
    f = fixture(); f.select.val('he-il'); f.save.handlers.click(); f.app.accountId = 'b'.repeat(32);
    f.requests[0].success({data: {call_forward_confirmation: {language: 'he-il'}}});
    assert(!Object.hasOwn(f.data.account, 'call_forward_confirmation'));
    f = fixture(); f.app.accountId = 'b'.repeat(32); f.select.val('he-il'); f.save.handlers.click(); assert.equal(f.requests.length, 0);
    f = fixture(false); assert.equal(f.section.removed, true); assert.equal(f.requests.length, 0);
    console.log('PASS actual patched Monster AMD: EN/HE/AR/ES/FR save/reset/readback, no automatic adoption, duplicate-click/error handling, stale-account protection, restricted user and RTL labels.');
} finally { fs.rmSync(stage, {recursive: true, force: true}); }
