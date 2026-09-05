'use strict';
const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const source = fs.readFileSync(process.argv[2] || '/usr/local/src/kazoo5-installer/monster-ui/src/apps/myaccount/app.js', 'utf8');
let app, hidden = false, completed = 0;
const listeners = new Map(), classes = new Set();
const panel = {hasClass: name => classes.has(name), addClass(name) {classes.add(name); return this;},
    removeClass(name) {classes.delete(name); return this;}, find() {return {first() {return this;}, empty() {return this;}};},
    off(event) {listeners.delete(event); return this;}, one(event, callback) {listeners.set(event, callback); return this;}};
const content = {hide() {hidden = true;}, show() {hidden = false;}};
function $(selector) {
    if (selector === '#monster_content') return content;
    if (selector === '#main_topbar_myaccount') return {addClass() {}, removeClass() {}};
    return panel;
}
vm.runInNewContext(source, {define(factory) {app = factory(name => {
    if (name === 'jquery') return $;
    if (name === 'lodash') return {};
    if (name === 'monster') return {config: {whitelabel: {}}, apps: {auth: {originalAccount: {}}}, pub() {}};
    throw new Error(name);
});}});
app._UIRestrictionsCompatibility = args => args.callback({});
app.getDefaultCategory = () => ({name: 'account'});
app.i18n = {active: () => ({account: {title: 'Account'}})};
app.activateSubmodule = args => args.callback();
app.displayUserSection = () => {};
function open() {app.toggle({callback: () => completed++});}
open();
assert(classes.has('myaccount-open'));
assert.equal(listeners.size, 1);
const lateCallback = listeners.get('transitionend.myaccountOpen');
app.hide(panel);
assert.equal(listeners.size, 0, 'Closing must clear only the pending namespaced open handler');
lateCallback();
assert.equal(hidden, false, 'Late opening transition must not hide the selected application');
assert.equal(completed, 0, 'Cancelled open must not signal completion');
open();
listeners.get('transitionend.myaccountOpen')();
assert.equal(hidden, true, 'Normal completed open hides underlying application');
assert.equal(completed, 1);
app.hide(panel);
assert.equal(hidden, false, 'Normal close restores underlying application');
console.log('PASS: MyAccount open/close/late-transition guard and normal-open regression sequences');
