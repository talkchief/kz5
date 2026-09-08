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
const files = ['app.js', 'views/accountSettings.html', 'i18n/en-US.json', 'i18n/de-DE.json', 'style/app.scss'];
function element() {
    return {handlers: {}, attrs: {}, value: '', message: '', removed: false,
        on(event, fn) {this.handlers[event] = fn; return this;},
        click(fn) {return this.on('click', fn);}, fileUpload() {return this;},
        prop(key, value) {if (arguments.length === 1) return this.attrs[key]; this.attrs[key] = value; return this;},
        val(value) {if (!arguments.length) return this.value; this.value = value; return this;},
        text(value) {this.message = value; return this;}, remove() {this.removed = true;}};
}
function fixture(admin = true, saved) {
    const elements = Object.fromEntries(['section', 'select', 'save', 'status', 'accountSave'].map(k => [k, element()]));
    const e = elements, requests = [], storage = {}, otherElements = {}; let renders = 0;
    const monster = {config: {}, apps: {auth: {originalAccount: {superduper_admin: false}}},
        util: {isAdmin: () => admin, isSuperDuper: () => false, getCapability: () => ({isEnabled: false})},
        ui: {valid: () => true, getFormData: () => ({music_on_hold: {media_id: ''}, preflow: {always: '_disabled'}})}};
    let app;
    vm.runInNewContext(fs.readFileSync(path.join(stage, 'app.js'), 'utf8'), {define: factory => {
        app = factory(name => ({jquery: {}, lodash: _, monster})[name]);
    }});
    e.section.find = selector => ({'.forward-confirmation-language': e.select, '.forward-confirmation-save': e.save, '.forward-confirmation-status': e.status})[selector];
    const template = {attached: true, find: selector => ({'.forward-confirmation-settings': e.section, '.account-settings-update': e.accountSave})[selector] || (otherElements[selector] ||= element()),
        data(key, value) {if (arguments.length === 1) return storage[key]; storage[key] = value; return this;},
        closest() {return {length: this.attached ? 1 : 0};}};
    const translations = JSON.parse(fs.readFileSync(path.join(stage, 'i18n/en-US.json'))), strings = translations.callflows.accountSettings.forwardConfirmation;
    const data = {account: {id: 'a'.repeat(32), name: 'Keep pending edits', ...(saved ? {call_forward_confirmation: {language: saved}} : {})}};
    app.i18n = {active: () => translations};
    app.accountId = data.account.id; app.callApi = request => requests.push(request);
    app.render = () => {renders++;}; app.compactObject = () => {};
    app.bindForwardedCallConfirmation(template, data);
    return {app, data, template, requests, strings, ...e, get renders() {return renders;},
        bindUpdate() {app.bindAccountSettingsEvents(template, data, {getSelectedItems: () => []});}};
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
    assert(view.includes('value="he-il" lang="he">עברית') && view.includes('value="ar-sa" lang="ar">العربية'));
    assert(view.includes('id="forward_confirmation_title"') && view.includes('for="forward_confirmation_language"'));
    const css = fs.readFileSync(path.join(stage, 'style/app.scss'), 'utf8');
    assert(css.includes('text-align-last: left') && css.includes('width: 320px'));
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
    // Exercise the real Account Settings Update handler, including the closure
    // shared with the dedicated PATCH control.
    for (const language of ['en-us', 'he-il', 'ar-sa', 'es-es', 'fr-fr', '']) {
        f = fixture(true, language === '' ? 'he-il' : undefined); f.bindUpdate();
        f.select.val(language); f.select.handlers.change(); f.accountSave.handlers.click(); f.accountSave.handlers.click();
        assert.equal(f.requests.length, 1); const r = f.requests[0];
        assert.equal(r.resource, 'account.update');
        assert.equal(r.data.data.call_forward_confirmation.language, language || null);
        assert.equal(r.data.data.name, 'Keep pending edits');
        const returned = JSON.parse(JSON.stringify(r.data.data)); if (!language) delete returned.call_forward_confirmation;
        r.success({data: returned}); assert.equal(f.renders, 0);
        assert.equal(f.select.value, language); assert.equal(f.status.message, f.strings.accountSaved);
        assert.equal(f.data.account.call_forward_confirmation?.language || '', language);
    }
    f = fixture(true, 'he-il'); f.bindUpdate(); f.accountSave.handlers.click();
    assert(!Object.hasOwn(f.requests[0].data.data, 'call_forward_confirmation'));
    f.requests[0].success({data: {...f.data.account, call_forward_confirmation: {language: 'ar-sa'}}});
    assert.equal(f.select.value, 'ar-sa'); assert.equal(f.renders, 0);
    f = fixture(); f.bindUpdate(); f.select.val('fr-fr'); f.accountSave.handlers.click(); f.requests[0].error();
    assert.equal(f.select.value, 'fr-fr'); assert.equal(f.renders, 0); assert.equal(f.status.message, f.strings.updateFailed);
    assert(!Object.hasOwn(f.data.account, 'call_forward_confirmation'));
    f = fixture(); f.bindUpdate(); f.app.accountId = 'b'.repeat(32); f.select.val('he-il'); f.accountSave.handlers.click();
    assert.equal(f.requests.length, 0);
    f = fixture();
    assert.equal(f.app.formatAccountSettingsData({account: f.data.account, callflows: [], numberList: {}}).forwardConfirmation.title, 'Forwarded-call confirmation');
    f.app.i18n.active = () => ({});
    assert.equal(f.app.formatAccountSettingsData({account: f.data.account, callflows: [], numberList: {}}).forwardConfirmation.language, 'Confirmation language');
    assert.equal(f.app.getForwardedCallConfirmationStrings().title, 'Forwarded-call confirmation');
    assert.equal(f.app.getForwardedCallConfirmationStrings().language, 'Confirmation language');
    console.log('PASS actual patched Monster AMD: EN/HE/AR/ES/FR save/reset/readback, no automatic adoption, duplicate-click/error handling, stale-account protection, restricted user, visible fallback labels, left alignment and main Update save/reset/stale/error behavior.');
} finally { fs.rmSync(stage, {recursive: true, force: true}); }
