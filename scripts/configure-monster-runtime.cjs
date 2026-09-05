#!/usr/bin/env node
'use strict';
// Preserve existing public UI configuration while adding explicit deployment
// capabilities. No account, payment processor, SIP device or API key is created.
const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');

function configure(source, options) {
    const api = new URL(options.api);
    const managedSocket = '\n\t// kazoo5-managed-same-origin-websocket\n'
        + '\tconfig.api.socket = (window.location.protocol === "https:" ? "wss://" : "ws://") + window.location.host + "/websocket";\n';
    assert(['http:', 'https:'].includes(api.protocol) && !api.username && !api.password
        && api.pathname.endsWith('/v2/') && !api.search && !api.hash, 'Invalid public Kazoo API URL');
    let config, definitions = 0;
    vm.runInNewContext(source, {
        window: {location: {protocol: api.protocol, hostname: api.hostname, host: api.host}},
        define(value) {
            definitions++;
            config = typeof value === 'function' ? value(() => { throw new Error('External configuration imports are not supported'); }) : value;
        }
    }, {timeout: 1000});
    assert(definitions === 1 && config && typeof config === 'object' && !Array.isArray(config), 'Expected one AMD configuration object');
    // A JSON round-trip preserves the static deployment settings, not executable
    // configuration hooks; refuse those instead of silently dropping them.
    const staticConfig = JSON.parse(JSON.stringify(config, (key, value) => {
        assert(!['function', 'symbol', 'bigint', 'undefined'].includes(typeof value), 'Configuration must contain static JSON values');
        return value;
    }));
    staticConfig.api = staticConfig.api || {};
    staticConfig.whitelabel = staticConfig.whitelabel || {};
    staticConfig.whitelabel.bookkeepers = staticConfig.whitelabel.bookkeepers || {};
    for (const value of [staticConfig.api, staticConfig.whitelabel, staticConfig.whitelabel.bookkeepers]) {
        assert(value && typeof value === 'object' && !Array.isArray(value), 'Invalid existing configuration section');
    }
    function flag(option, existing, fallback) {
        assert(['auto', 'true', 'false'].includes(option), 'Invalid optional integration setting');
        return option === 'auto' ? typeof existing === 'boolean' ? existing : fallback : option === 'true';
    }
    staticConfig.api.default = options.api;
    staticConfig.whitelabel.fetchFromApi = flag(options.branding, staticConfig.whitelabel.fetchFromApi, false);
    staticConfig.whitelabel.bookkeepers.braintree = flag(options.braintree,
        staticConfig.whitelabel.bookkeepers.braintree, Boolean(staticConfig.api.braintree));
    let dynamicSocket = false;
    if (options.socket === 'auto') {
        dynamicSocket = staticConfig.api.socket !== false && !staticConfig.api.socket;
    } else if (options.socket === 'same-origin') {
        dynamicSocket = true;
    } else if (options.socket === 'disabled') {
        staticConfig.api.socket = false;
    } else {
        const socket = new URL(options.socket);
        assert(['ws:', 'wss:'].includes(socket.protocol) && !socket.username && !socket.password
            && !socket.hash && !socket.search && socket.pathname !== '/undefined', 'Invalid browser WebSocket endpoint');
        staticConfig.api.socket = options.socket;
    }
    // Keep the managed same-origin expression dynamic on repeat installation.
    // A leftover marker is not authority to overwrite an operator's endpoint.
    // Recognize only our unchanged assignment immediately before the return.
    if (options.socket === 'auto' && staticConfig.api.socket !== false
        && source.includes(managedSocket + '\treturn config;')) dynamicSocket = true;
    if (dynamicSocket) delete staticConfig.api.socket;
    const socketLine = dynamicSocket ? managedSocket : '';
    return '/* Public deployment settings; optional integrations require explicit configuration. */\n'
        + 'define(function() {\n\tvar config = ' + JSON.stringify(staticConfig, null, '\t').replace(/\n/g, '\n\t') + ';\n'
        + socketLine + '\treturn config;\n});\n';
}

if (require.main === module) {
    const [file, api, socket = 'auto', branding = 'auto', braintree = 'auto'] = process.argv.slice(2);
    assert(file && api && process.argv.length <= 7, 'Usage: configure-monster-runtime.cjs CONFIG API [SOCKET] [REMOTE_BRANDING] [BRAINTREE]');
    const stat = fs.lstatSync(file);
    assert(stat.isFile() && !stat.isSymbolicLink() && stat.size < 1024 * 1024, 'Configuration must be a regular non-symlinked file');
    const output = configure(fs.readFileSync(file, 'utf8'), {api, socket, branding, braintree});
    // Generated configuration is public. Do not print its contents or keys.
    const temporary = file + '.' + process.pid + '.tmp';
    fs.writeFileSync(temporary, output, {flag: 'wx', mode: 0o644});
    // Installers run with umask077; the browser still needs this public asset.
    fs.chmodSync(temporary, 0o644);
    fs.renameSync(temporary, file);
    console.log('PASS public Monster configuration: preserved existing settings and explicit optional capabilities');
}
module.exports = {configure};
