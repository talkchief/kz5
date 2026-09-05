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
// Explicit same-origin migration changes the default API only. Existing
// custom apps, credentials-free external integrations and socket choices stay.
for (const protocol of ['http:', 'https:']) {
    const endpoint = protocol + '//kz5.talkchief.io/v2/';
    const changed = read(configure(original, {...options, api: endpoint}), protocol, 'kz5.talkchief.io');
    assert.equal(changed.api.default, endpoint);
    assert.equal(new URL(changed.api.default).origin, protocol + '//kz5.talkchief.io');
    assert.equal(changed.api.socket, (protocol === 'https:' ? 'wss:' : 'ws:') + '//kz5.talkchief.io/websocket');
    assert.deepEqual(changed.custom, {nested: [1,true,'keep']});
    assert.equal(changed.whitelabel.companyName, 'Keep me');
    const repeated = read(configure(configure(original, {...options, api: endpoint}), {...options, api: endpoint}), protocol, 'kz5.talkchief.io');
    assert.deepEqual(repeated, changed);
}
for (const api of ['http://user:pass@api.invalid/v2/', 'javascript:alert(1)', '/v2/',
    'https://api.invalid/v2/?token=forbidden', 'https://api.invalid/v2/#fragment']) {
    assert.throws(() => configure(original, {...options, api}));
}
console.log('PASS public UI configuration: repeatable same-origin ws/wss; explicit/preserved endpoints; local branding/unconfigured billing; custom settings preserved; invalid inputs rejected');

// Exercise the actual writer, not just configure(): a root install commonly
// has umask077, but nginx must still be able to read the generated public file.
{
    const fs = require('node:fs'), os = require('node:os'), path = require('node:path');
    const {spawnSync} = require('node:child_process');
    const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'kazoo-runtime-config-mode.'));
    const file = path.join(scratch, 'config.js');
    try {
        fs.writeFileSync(file, original, {mode: 0o600});
        // Run the CLI in its own child so require.main and umask match install.
        const cli = spawnSync(process.execPath, ['-e',
            'process.umask(0o077);const c=require("node:child_process").spawnSync(process.execPath,process.argv.slice(1),{stdio:"inherit"});process.exit(c.status??1);',
            path.join(__dirname, 'configure-monster-runtime.cjs'), file, options.api], {encoding: 'utf8'});
        assert.equal(cli.status, 0, cli.stderr);
        assert.equal(fs.statSync(file).mode & 0o777, 0o644);
        assert.equal(read(fs.readFileSync(file, 'utf8')).api.default, options.api);
        assert.deepEqual(fs.readdirSync(scratch), ['config.js']);
        console.log('PASS real CLI publishes readable0644 config with installer umask077');
    } finally { fs.unlinkSync(file); fs.rmdirSync(scratch); }
}
