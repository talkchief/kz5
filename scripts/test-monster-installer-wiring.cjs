'use strict';
// SPDX-License-Identifier: MPL-2.0
// Actual installer functions run under no-write shell stubs; patch replay is in memory.
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm');
const cp = require('node:child_process'), assert = require('node:assert/strict');
const {configure} = require('./configure-monster-runtime.cjs');
const framework = process.argv[2] || '/usr/local/src/kazoo5-installer/monster-ui';
const installer = fs.readFileSync(path.join(__dirname, 'install-kazoo5.sh'), 'utf8');
const options = {api: 'https://api.fixture.invalid/v2/', socket: 'auto', branding: 'auto', braintree: 'auto'};
function evaluate(source, host = 'ui.fixture.invalid', protocol = 'https:') {
    let result;
    vm.runInNewContext(source, {window: {location: {host, hostname: host.split(':')[0], protocol}},
        define(value) { result = typeof value === 'function' ? value() : value; }});
    return JSON.parse(JSON.stringify(result));
}
function functionSource(name) {
    const start = installer.indexOf('\n' + name + '() {');
    assert(start >= 0, 'Missing installer function: ' + name);
    const rest = installer.slice(start + 1), next = /\n[A-Za-z_][A-Za-z0-9_]*\(\) \{/.exec(rest);
    assert(next, 'Could not bound installer function');
    return rest.slice(0, next.index);
}
let passed = 0;
function test(name, body) { body(); passed++; console.log('PASS: ' + name); }
test('Explicit disabled socket survives auto and disabled-to-auto regeneration', () => {
    const initial = 'define({api:{socket:false},custom:{value:"preserve"}});';
    assert.equal(evaluate(configure(initial, options)).api.socket, false);
    const disabled = configure('define({api:{socket:"wss://events.fixture.invalid/websocket"}});', {...options, socket: 'disabled'});
    assert.equal(evaluate(disabled).api.socket, false);
    assert.equal(evaluate(configure(disabled, options)).api.socket, false);
});
test('Managed socket remains browser-relative, but retained comments cannot overwrite custom endpoints', () => {
    const managed = configure('define({})', options);
    const regenerated = configure(managed, options);
    assert.equal(evaluate(regenerated, 'another-ui.fixture.invalid:8443').api.socket, 'wss://another-ui.fixture.invalid:8443/websocket');
    const replaced = managed.replace(/config\.api\.socket = .*;/,
        'config.api.socket = "wss://operator-events.fixture.invalid/events";');
    assert(replaced.includes('// kazoo5-managed-same-origin-websocket'));
    assert.equal(evaluate(configure(replaced, options)).api.socket, 'wss://operator-events.fixture.invalid/events');
    const laterOverride = managed.replace('\treturn config;',
        '\tconfig.api.socket = "wss://later-override.fixture.invalid/events";\n\treturn config;');
    assert.equal(evaluate(configure(laterOverride, options)).api.socket, 'wss://later-override.fixture.invalid/events');
});
test('Configured optional services/custom data remain unchanged in automatic mode', () => {
    const original = {api: {default: 'https://old.fixture.invalid/v2/', socket: 'wss://operator.fixture.invalid/events',
        socketWebphone: 'wss://phone.fixture.invalid/sip', googleMaps: {apiKey: 'fixture-browser-key', geocoding: true},
        braintree: 'https://billing.fixture.invalid/'}, whitelabel: {logoPath: 'custom/logo.svg', faviconPath: 'custom/icon.png',
        fetchFromApi: true, bookkeepers: {braintree: true, custom: 'keep'}}, custom: {nested: [0, false, 'keep']}};
    const result = evaluate(configure('define(' + JSON.stringify(original) + ');', options));
    original.api.default = options.api;
    assert.deepEqual(result, original);
});
test('New settings are persisted, fingerprinted and passed through the real source configuration hook', () => {
    const persisted = installer.split('readonly KAZOO_PERSISTED_KEYS=(')[1].split('\n)')[0];
    for (const name of ['KAZOO_WEBSOCKET_UPSTREAM', 'MONSTER_UI_WEBSOCKET_URL', 'MONSTER_UI_REMOTE_BRANDING', 'MONSTER_UI_BRAINTREE']) {
        assert(new RegExp('\\b' + name + '\\b').test(persisted), 'Missing persisted option: ' + name);
    }
    const fingerprint = functionSource('monster_ui_build_fingerprint');
    for (const name of ['MONSTER_UI_WEBSOCKET_URL', 'MONSTER_UI_REMOTE_BRANDING', 'MONSTER_UI_BRAINTREE',
        'configure-monster-runtime.cjs', 'monster-ui-branding-billing.patch', 'monster-ui-websocket-config.patch',
        'monster-ui-optional-integrations.patch']) assert(fingerprint.includes(name), 'Missing build identity input: ' + name);
    const configureApi = functionSource('configure_monster_ui_api');
    assert(configureApi.includes('"$KAZOO_API_URL" "$MONSTER_UI_WEBSOCKET_URL" "$MONSTER_UI_REMOTE_BRANDING" "$MONSTER_UI_BRAINTREE"'));
    assert(configureApi.includes('[[ $DRY_RUN != true ]] || return 0'));
    assert(!configureApi.includes('checkout'), 'Configuration hook must not discard operator settings');
    assert(!/checkout[^\n]*src\/js\/config\.js/.test(functionSource('sync_monster_ui_sources')));
});
test('Legacy initializer runs after artifact preservation, outside rebuild-only path, before nginx verification', () => {
    const install = functionSource('install_monster_ui');
    const call = install.indexOf('node "$SCRIPT_DIR/ensure-acdc-language-capabilities.cjs" --web-root "$MONSTER_UI_WEB_ROOT"');
    assert(call > install.indexOf('Runtime language capability changed during the web deployment'));
    assert(call > install.indexOf('\n    fi\n'), 'Initializer must run on already-built installs too');
    assert(call < install.indexOf('\n    configure_monster_ui_nginx'));
    assert(install.slice(0, call).endsWith('if [[ $DRY_RUN != true && ",${MONSTER_UI_APPS_LIST}," == *\',acdc,\'* ]]; then\n        '),
        'Default state must require a real install with ACDC selected');
    assert(install.indexOf('configure_monster_ui_nginx') < install.indexOf('run nginx -t'));
    assert(install.indexOf('run nginx -t') < install.indexOf('service_enable_restart nginx.service'));
});

function renderNginx(host, upstream, apiUpstream = 'https://api.fixture.invalid/v2/') {
    const stubs = `
set -eu
run() { printf 'RUN %s\\n' "$*" >&2; }
die() { printf 'REJECT %s\\n' "$*" >&2; exit 42; }
log() { :; }
getenforce() { printf 'Enforcing\\n'; }
restorecon() { printf 'RESTORECON %s\\n' "$*" >&2; }
cat() {
    if (( $# )); then return; fi
    while IFS= read -r line; do printf '%s\\n' "$line"; done
}
write_file() {
    while IFS= read -r line; do
        if [[ $2 == /etc/nginx/conf.d/monster-ui.conf ]]; then printf '%s\\n' "$line"; fi
    done
}
`;
    return cp.spawnSync('bash', ['--noprofile', '--norc', '-s'], {encoding: 'utf8', timeout: 10000,
        input: stubs + functionSource('monster_ui_crossbar_proxy') + '\n'
            + functionSource('configure_monster_ui_nginx') + '\nconfigure_monster_ui_nginx\n',
        env: {PATH: '/usr/bin:/bin', LANG: 'C', DRY_RUN: 'false', KAZOO_PUBLIC_HOSTNAME: host,
            KAZOO_WEBSOCKET_UPSTREAM: upstream, KAZOO_API_UPSTREAM: apiUpstream,
            MONSTER_UI_WEB_ROOT: '/private/web', KAZOO_TLS_CERT_FILE: '/fixture/cert',
            KAZOO_TLS_KEY_FILE: '/fixture/key', KAZOO_TLS_CHAIN_FILE: ''}});
}
test('HTTP and HTTPS render modular upstream Upgrade routes with TLS verification and SELinux permission', () => {
    for (const host of ['', 'ui.fixture.invalid']) for (const upstream of [
        'http://events.fixture.invalid:5555/websocket', 'https://events.fixture.invalid:7443/websocket']) {
        const result = renderNginx(host, upstream);
        assert.equal(result.status, 0, result.stderr);
        const block = /location = \/websocket \{([\s\S]*?)\n    \}/.exec(result.stdout);
        assert(block, 'Missing exact WebSocket route');
        for (const directive of ['proxy_pass ' + upstream + ';', 'proxy_http_version 1.1;',
            'proxy_set_header Upgrade $http_upgrade;', 'proxy_set_header Connection "upgrade";',
            'proxy_read_timeout 3600s;', 'proxy_send_timeout 3600s;', 'proxy_buffering off;',
            'proxy_ssl_server_name on;', 'proxy_ssl_verify on;',
            'proxy_ssl_trusted_certificate /etc/pki/tls/certs/ca-bundle.crt;']) assert(block[1].includes(directive), directive);
        assert(result.stderr.includes('RUN setsebool -P httpd_can_network_connect on'),
            'Enforcing SELinux also needs network permission for HTTP-only modular UI');
        assert(result.stdout.includes('location = /apps/acdc/language-capabilities.json'));
        assert(result.stdout.includes('try_files $uri =404;'));
        assert(result.stdout.includes('add_header Cache-Control "no-store" always;'));
    }
});
test('Unsafe upstream credentials, query strings, relative URLs and nginx injection are rejected', () => {
    for (const upstream of ['http://user:pass@events.fixture.invalid/websocket', '/websocket',
        'http://events.fixture.invalid/websocket?x=1', 'http://events.fixture.invalid/websocket;return 200;',
        'http://events.fixture.invalid/websocket\n}', 'ftp://events.fixture.invalid/websocket']) {
        const result = renderNginx('', upstream);
        assert.notEqual(result.status, 0); assert.equal(result.stdout, '');
    }
});
test('HTTP and HTTPS use the same Crossbar route, retain URL/query forwarding and cannot fall back to UI HTML', () => {
    for (const host of ['', 'ui.fixture.invalid']) for (const upstream of [
        'http://127.0.0.1:8000/v2/', 'https://apps.fixture.invalid:8443/v2/']) {
        const result = renderNginx(host, 'http://events.fixture.invalid:5555/websocket', upstream);
        assert.equal(result.status, 0, result.stderr);
        const blocks = [...result.stdout.matchAll(/location \^~ \/v2\/ \{([\s\S]*?)\n    \}/g)];
        assert.equal(blocks.length, 1, 'Exactly one API route on the serving virtual host');
        for (const directive of ['proxy_pass ' + upstream + ';', 'proxy_set_header Host $host;',
            'proxy_set_header X-Forwarded-Proto $scheme;', 'proxy_intercept_errors off;',
            'proxy_ssl_server_name on;', 'proxy_ssl_verify on;',
            'proxy_ssl_trusted_certificate /etc/pki/tls/certs/ca-bundle.crt;', 'client_max_body_size 50m;']) {
            assert(blocks[0][1].includes(directive), directive);
        }
        assert(!blocks[0][1].includes('try_files'));
        assert(!blocks[0][1].includes('proxy_set_header X-Forwarded-Proto https;'));
        assert(result.stdout.includes('location = /v2 { return 308 /v2/$is_args$args; }'));
        assert(result.stdout.includes('location ^~ /apis/'));
        assert(result.stdout.includes('location = /websocket'));
        assert(result.stdout.includes('location = /apps/acdc/language-capabilities.json'));
        assert(result.stdout.includes('try_files $uri $uri/ /index.html;'));
    }
});
test('Unsafe Crossbar upstreams are rejected before either HTTP or TLS configuration is rendered', () => {
    for (const host of ['', 'ui.fixture.invalid']) for (const upstream of [
        'http://user:pass@apps.fixture.invalid/v2/', '/v2/', 'https://apps.fixture.invalid/v2/?x=1',
        'https://apps.fixture.invalid/v2/#fragment', 'http://apps.fixture.invalid/v2/;return 200;',
        'http://apps.fixture.invalid/v2/\n}', 'ftp://apps.fixture.invalid/v2/', 'http://apps.fixture.invalid/']) {
        const result = renderNginx(host, 'http://events.fixture.invalid/websocket', upstream);
        assert.notEqual(result.status, 0); assert.equal(result.stdout, '');
    }
});
test('Only the inferred fresh HTTP endpoint changes; saved or explicitly configured API URLs remain authoritative', () => {
    const source = functionSource('preflight');
    const begin = source.indexOf('    if [[ -n $KAZOO_PUBLIC_HOSTNAME ]]; then\n        KAZOO_API_URL=');
    assert(begin >= 0);
    const end = source.indexOf('\n    fi', begin) + '\n    fi'.length;
    const endpointSelection = source.slice(begin, end);
    for (const [host, configured, expected] of [
        ['', '', 'http://192.0.2.10/v2/'],
        ['ui.fixture.invalid', '', 'https://ui.fixture.invalid/v2/'],
        ['', 'https://external.fixture.invalid/v2/', 'https://external.fixture.invalid/v2/'],
        ['', 'http://192.0.2.10:8000/v2/', 'http://192.0.2.10:8000/v2/']]) {
        const result = cp.spawnSync('bash', ['--noprofile', '--norc', '-s'], {encoding: 'utf8', timeout: 10000,
            input: 'set -eu\n' + endpointSelection + '\nprintf "%s" "$KAZOO_API_URL"\n',
            env: {PATH: '/usr/bin:/bin', KAZOO_PUBLIC_IP: '192.0.2.10', KAZOO_PUBLIC_HOSTNAME: host, KAZOO_API_URL: configured}});
        assert.equal(result.status, 0, result.stderr); assert.equal(result.stdout, expected);
    }
});
function verifyTransport(host, apiResult) {
    const stubs = `
set -eu
die() { printf 'REJECT %s\\n' "$*" >&2; exit 42; }
log() { :; }
stat() { printf '600:root\\n'; }
curl() {
    case "\${@: -1}" in
        */apps/acdc/language-capabilities.json) printf '404' ;;
        */v2/) printf '%s' "$FAKE_API_RESULT" ;;
        https://*) printf '<html>fixture</html>' ;;
        http://ui.fixture.invalid/) printf '308 https://ui.fixture.invalid/' ;;
        http://127.0.0.1/) printf '<html>fixture</html>' ;;
        *) return 99 ;;
    esac
}
`;
    return cp.spawnSync('bash', ['--noprofile', '--norc', '-s'], {encoding: 'utf8', timeout: 10000,
        input: stubs + functionSource('verify_monster_ui_transport') + '\nverify_monster_ui_transport\n',
        env: {PATH: '/usr/bin:/bin', KAZOO_PUBLIC_HOSTNAME: host, MONSTER_UI_WEB_ROOT: '/nonexistent-kazoo-test-web-root', FAKE_API_RESULT: apiResult}});
}
test('Real transport verification rejects HTML200 and upstream5xx while allowing an unauthenticated Crossbar JSON error', () => {
    for (const host of ['', 'ui.fixture.invalid']) {
        assert.equal(verifyTransport(host, '{"status":"error","error":"404"}\n404').status, 0);
        for (const response of ['<html>app fallback</html>\n200', '{"status":"error"}\n502',
            '{"not":"crossbar"}\n200', 'upstream unavailable\n502']) {
            const result = verifyTransport(host, response);
            assert.notEqual(result.status, 0); assert(result.stderr.includes('Crossbar JSON response'));
        }
    }
});

test('Transition + branding/billing + socket + optional patches replay pinned framework byte-exactly', () => {
    const pin = '7ef735eada6fd0e2b96c06f32c0bb868867f7d18';
    assert.equal(cp.execFileSync('git', ['-C', framework, 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(), pin);
    const files = new Map(), patches = ['monster-ui-myaccount-transition.patch', 'monster-ui-branding-billing.patch',
        'monster-ui-websocket-config.patch', 'monster-ui-optional-integrations.patch'];
    for (const patchName of patches) {
        const patchPath = path.join(__dirname, 'patches', patchName);
        const patch = fs.readFileSync(patchPath, 'utf8');
        for (const section of patch.split(/(?=^diff --git )/m).filter(Boolean)) {
            const lines = section.replace(/\n$/, '').split('\n');
            const match = /^diff --git a\/(\S+) b\/\1$/.exec(lines[0]);
            assert(match, 'Unexpected non-text/rename patch section');
            const file = match[1];
            if (!files.has(file)) files.set(file, cp.execFileSync('git', ['-C', framework, 'show', pin + ':' + file], {encoding: 'utf8'}));
            const baseline = files.get(file).split('\n'), result = [];
            let cursor = 0, index = lines.findIndex(line => line.startsWith('@@ '));
            assert(index > 0);
            while (index < lines.length) {
                const hunk = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/.exec(lines[index++]);
                assert(hunk, 'Malformed patch hunk');
                const oldStart = Number(hunk[1]) - 1, oldCount = Number(hunk[2] || 1), newCount = Number(hunk[4] || 1);
                assert(oldStart >= cursor); result.push(...baseline.slice(cursor, oldStart)); cursor = oldStart;
                assert.equal(Number(hunk[3]) - 1, result.length, 'Wrong destination offset');
                let removed = 0, added = 0;
                while (index < lines.length && !lines[index].startsWith('@@ ')) {
                    const line = lines[index++], kind = line[0];
                    assert([' ', '+', '-'].includes(kind));
                    if (kind !== '+') {assert.equal(line.slice(1), baseline[cursor++], patchName + ': ' + file); removed++;}
                    if (kind !== '-') {result.push(line.slice(1)); added++;}
                }
                assert.equal(removed, oldCount); assert.equal(added, newCount);
            }
            result.push(...baseline.slice(cursor)); files.set(file, result.join('\n'));
        }
    }
    assert.equal(files.size, 9, 'Unexpected framework patch scope');
    for (const [file, bytes] of files) assert.equal(fs.readFileSync(path.join(framework, file), 'utf8'), bytes, 'Byte mismatch: ' + file);
    cp.execFileSync('git', ['-C', framework, 'apply', '--check', '--reverse',
        ...patches.map(name => path.join(__dirname, 'patches', name))], {stdio: 'pipe'});
});
console.log(`PASS: ${passed} no-deployment Monster installer/configuration/patch groups`);
