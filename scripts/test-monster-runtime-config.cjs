'use strict';
const assert = require('node:assert/strict'), vm = require('node:vm');
const {configure} = require('./configure-monster-runtime.cjs');
const options = {api: 'https://api.example.invalid/v2/', socket: 'auto', branding: 'auto', braintree: 'auto'};
function read(source, protocol = 'https:', host = 'ui.example.invalid') {
    let result;
    vm.runInNewContext(source, {window: {location: {protocol, host}}, define: value => { result = typeof value === 'function' ? value() : value; }});
    return JSON.parse(JSON.stringify(result));
}
const original = 'define({api:{default:"http://old.invalid/v2/"}, whitelabel:{companyName:"Keep me",logoPath:"custom/logo.svg"}, custom:{nested:[1,true,"keep"]}});';
const once = configure(original, options), a = read(once);
assert.equal(a.api.socket, 'wss://ui.example.invalid/websocket');
assert.equal(read(once, 'http:', 'ui.example.invalid:8080').api.socket, 'ws://ui.example.invalid:8080/websocket');
assert.equal(a.whitelabel.fetchFromApi, false); assert.equal(a.whitelabel.bookkeepers.braintree, false);
assert.equal(a.whitelabel.companyName, 'Keep me'); assert.equal(a.whitelabel.logoPath, 'custom/logo.svg');
assert.deepEqual(a.custom, {nested: [1,true,'keep']});
assert.deepEqual(read(configure(once, options)), a, 'Repeated installation must preserve same-origin behavior');
const configured = 'define({api:{socket:"wss://events.example.invalid/websocket",braintree:"https://billing.example.invalid/",socketWebphone:"wss://phone.example.invalid/",googleMaps:{apiKey:"operator-browser-key"}},whitelabel:{fetchFromApi:true}});';
const b = read(configure(configured, options));
assert.equal(b.api.socket, 'wss://events.example.invalid/websocket');
assert.equal(b.api.socketWebphone, 'wss://phone.example.invalid/');
assert.equal(b.api.googleMaps.apiKey, 'operator-browser-key');
assert.equal(b.whitelabel.fetchFromApi, true); assert.equal(b.whitelabel.bookkeepers.braintree, true);
const c = read(configure(configured, {...options, socket:'disabled', branding:'false', braintree:'false'}));
assert.equal(c.api.socket,false); assert.equal(c.whitelabel.fetchFromApi,false); assert.equal(c.whitelabel.bookkeepers.braintree,false);
for (const socket of ['undefined','/undefined','ftp://bad.invalid/','wss://user:pass@bad.invalid/','ws://bad.invalid/undefined']) {
    assert.throws(() => configure(original, {...options,socket}));
}
assert.throws(() => configure(original, {...options,branding:'yes'}));
assert.throws(() => configure('define({custom:function(){}})',options));
assert.throws(() => configure('define({});define({})',options));
console.log('PASS public UI configuration: repeatable same-origin ws/wss; explicit/preserved endpoints; local branding/unconfigured billing; custom settings preserved; invalid inputs rejected');
