#!/usr/bin/env node
'use strict';
// Offline verifier contract: extract only the verifier, never source the
// installer or permit a real broker, service, package, or network command.
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const cp = require('node:child_process'), assert = require('node:assert/strict');
const source = fs.readFileSync(path.join(__dirname, 'install-kazoo5.sh'), 'utf8');
const matches = [...source.matchAll(/^verify_rabbitmq\(\) \{[\s\S]*?^\}/gm)];
assert.equal(matches.length, 1, 'Expected exactly one real RabbitMQ verifier');
const verifier = matches[0][0];
const workspace = fs.mkdtempSync(path.join(os.tmpdir(), 'rabbitmq-runtime-offline.'));
const emptyPath = path.join(workspace, 'empty-bin'); fs.mkdirSync(emptyPath);
const defaults = {user: 'kazoo', vhost: '/', bind: '127.0.0.1', port: 5672};
const selected = {user: 'fixture-user', vhost: 'fixture /%+ vhost', bind: '10.20.0.12', port: 5679};
const permission = user => ({user, configure: '.*', write: '.*', read: '.*'});
const listener = (interfaceAddress, port, protocol = 'amqp') =>
    ({node: 'rabbit@fixture', interface: interfaceAddress, port, protocol});
// Pinned RabbitMQ 3.13 ListenersCommand.output/2 emits this envelope, while
// list_permissions uses the default JSON stream formatter (one array).
const listenerEnvelope = listeners => ({result: 'ok', node: 'rabbit@fixture', listeners});
const encode = value => typeof value === 'string' ? value : JSON.stringify(value);
let cases = 0;

const stubs = String.raw`
set -euo pipefail
# Keep fixture diagnostics outside the production command's suppressed stderr.
exec 3>&2
fixture_error() { printf 'FIXTURE ERROR: %s\n' "$*" >&3; exit 98; }
trace() { printf 'CALL:%s\n' "$*" >&3; }
die() { printf 'REJECT: %s\n' "$*" >&2; exit 42; }
log() { printf '%s\n' "$*"; }
assert_service() {
    [[ $# == 1 && $1 == rabbitmq-server.service ]] || fixture_error 'unexpected service assertion'
    trace service-check
}
ss() {
    [[ $# == 3 && $1 == -H && $2 == -ltn && $3 == 'sport = :25672' ]] || fixture_error 'unexpected ss arguments'
    trace distribution-listener
    printf 'LISTEN 0 128 %s:25672 0.0.0.0:*\n' "$KAZOO_RABBITMQ_BIND"
}
rpm() {
    [[ $# == 4 && $1 == -q && $2 == --qf && $3 == '%{VERSION}' ]] || fixture_error 'unexpected rpm arguments'
    case $4 in
        rabbitmq-server) trace rpm-rabbitmq; printf '%s' "$RABBITMQ_VERSION" ;;
        erlang) trace rpm-erlang; printf '%s' "$ERLANG_VERSION" ;;
        *) fixture_error 'unexpected package' ;;
    esac
}
runuser() {
    [[ $# == 7 && $1 == --user && $2 == rabbitmq && $3 == -- &&
       $4 == /usr/lib/rabbitmq/bin/rabbitmq-plugins && $5 == list && $6 == -e && $7 == -m ]] ||
        fixture_error 'unexpected runuser command'
    trace plugins
    printf 'rabbitmq_consistent_hash_exchange\n'
}
rabbitmqctl_password() {
    [[ $# == 1 && $1 == authenticate_user ]] || fixture_error 'password mutation or unexpected helper'
    trace authenticate-user
}
rabbitmqctl() {
    [[ $# == 6 && $1 == -q && $2 == list_permissions && $3 == -p &&
       $4 == "$KAZOO_RABBITMQ_VHOST" && $5 == --formatter && $6 == json ]] ||
        fixture_error 'unexpected rabbitmqctl command or selected vhost'
    trace permissions
    printf '%s' "$FIXTURE_PERMISSIONS"
    return "$FIXTURE_PERMISSIONS_STATUS"
}
rabbitmq-diagnostics() {
    if [[ $# == 2 && $1 == -q && $2 == ping ]]; then trace ping; return 0; fi
    [[ $# == 4 && $1 == -q && $2 == listeners && $3 == --formatter && $4 == json ]] ||
        fixture_error 'unexpected RabbitMQ diagnostics command'
    trace amqp-listeners
    printf '%s' "$FIXTURE_LISTENERS"
    return "$FIXTURE_LISTENERS_STATUS"
}
timeout() {
    [[ $# -ge 4 && $1 == --signal=TERM && $2 == --kill-after=5 && $3 == 30 ]] ||
        fixture_error 'expected bounded read-only inspection'
    shift 3
    case $1 in rabbitmqctl|rabbitmq-diagnostics) ;; *) fixture_error 'unexpected bounded command' ;; esac
    trace "bounded-$1"
    "$@"
}
# Only these local pure parsers may execute outside the shell. PATH is empty;
# unexpected commands cannot fall through to installed RabbitMQ/system tools.
jq() { /usr/bin/jq "$@"; }
grep() { /usr/bin/grep "$@"; }
`;

function run(options = {}) {
    const config = {...selected, ...options.config};
    const permissions = options.permissions ?? [permission(config.user)];
    const listeners = options.listeners ?? [listener(config.bind, config.port)];
    const listenersResponse = options.listenersResponse ??
        (Array.isArray(listeners) ? listenerEnvelope(listeners) : listeners);
    const result = cp.spawnSync('/bin/bash', ['--noprofile', '--norc', '-s'], {
        input: stubs + '\n' + verifier + '\nverify_rabbitmq\n', encoding: 'utf8', timeout: 10000,
        env: {PATH: emptyPath, LC_ALL: 'C', DRY_RUN: String(options.dryRun ?? false),
            KAZOO_RABBITMQ_USER: config.user, KAZOO_RABBITMQ_VHOST: config.vhost,
            KAZOO_RABBITMQ_BIND: config.bind, KAZOO_AMQP_PORT: String(config.port),
            RABBITMQ_VERSION: '3.13.7', ERLANG_VERSION: '26.2.5',
            FIXTURE_PERMISSIONS: encode(permissions), FIXTURE_LISTENERS: encode(listenersResponse),
            FIXTURE_PERMISSIONS_STATUS: String(options.permissionsStatus ?? 0),
            FIXTURE_LISTENERS_STATUS: String(options.listenersStatus ?? 0)}
    });
    assert.ifError(result.error);
    assert.equal(result.signal, null, 'Verifier exceeded offline time bound');
    assert(!result.stderr.includes('FIXTURE ERROR:'), result.stderr);
    const calls = result.stderr.split('\n').filter(line => line.startsWith('CALL:')).map(line => line.slice(5));
    return {...result, calls};
}

function check(name, options = {}, accepted = false) {
    const result = run(options);
    assert.equal(result.status, accepted ? 0 : 42, name + '\n' + result.stdout + result.stderr);
    if (accepted && !options.dryRun) {
        for (const operation of ['authenticate-user', 'permissions', 'amqp-listeners',
            'bounded-rabbitmqctl', 'bounded-rabbitmq-diagnostics']) {
            assert.equal(result.calls.filter(value => value === operation).length, 1,
                name + ': expected exactly one ' + operation);
        }
        assert(result.stdout.includes('PASS RabbitMQ'), name + ': success receipt missing');
    }
    cases++;
    return result;
}

try {
    check('default user/vhost/interface/port', {config: defaults}, true);
    check('nondefault user and quoted vhost/private interface/port', {}, true);
    check('explicit wildcard binding', {config: {bind: '0.0.0.0'}}, true);
    check('other users are allowed alongside exactly one selected user', {
        permissions: [permission('other-user'), permission(selected.user)]
    }, true);
    check('unrelated listeners are allowed alongside the exact AMQP listener', {
        listeners: [listener('127.0.0.1', 15672, 'http'), listener(selected.bind, selected.port)]
    }, true);

    check('configured vhost absent (CLI failure)', {permissions: [], permissionsStatus: 65});
    check('configured vhost inspection failed despite plausible stdout', {permissionsStatus: 70});
    check('configured vhost inspection timed out', {permissionsStatus: 124});
    check('selected user has no permissions', {permissions: []});
    check('only another user has permissions', {permissions: [permission('other-user')]});
    check('selected username is not a prefix match', {permissions: [permission(selected.user + '-extra')]});
    check('selected username is not a suffix match', {permissions: [permission('other-' + selected.user)]});
    check('duplicate selected user is ambiguous', {permissions: [permission(selected.user), permission(selected.user)]});
    for (const key of ['configure', 'write', 'read']) {
        check(key + ' permission revoked', {permissions: [{...permission(selected.user), [key]: '^$'}]});
        check(key + ' permission narrowed', {permissions: [{...permission(selected.user), [key]: '^fixture-.*'}]});
        const missing = permission(selected.user); delete missing[key];
        check(key + ' permission absent', {permissions: [missing]});
    }
    check('another user cannot supply the selected users missing permission', {
        permissions: [{...permission(selected.user), write: '^$'}, permission('other-user')]
    });
    for (const malformed of ['not JSON', '{}', 'null', '[null]', '[{}]', '"permissions"']) {
        check('invalid permission response ' + malformed, {permissions: malformed});
    }
    check('multiple permission JSON documents are ambiguous', {
        permissions: JSON.stringify([permission(selected.user)]) + '\n' + JSON.stringify([permission(selected.user)])
    });
    check('valid permissions cannot hide a null row', {permissions: [permission(selected.user), null]});
    check('valid permissions cannot hide an incomplete other-user row', {
        permissions: [permission(selected.user), {user: 'other-user'}]
    });

    check('AMQP loopback instead of selected private interface', {listeners: [listener('127.0.0.1', selected.port)]});
    check('AMQP wrong private interface', {listeners: [listener('10.20.0.13', selected.port)]});
    check('AMQP wildcard instead of selected private interface', {listeners: [listener('0.0.0.0', selected.port)]});
    check('AMQP private interface instead of selected wildcard', {
        config: {bind: '0.0.0.0'}, listeners: [listener(selected.bind, selected.port)]
    });
    check('AMQP wrong port', {listeners: [listener(selected.bind, selected.port + 1)]});
    check('management listener is not AMQP', {listeners: [listener(selected.bind, selected.port, 'http')]});
    check('distribution listener is not AMQP', {listeners: [listener(selected.bind, selected.port, 'clustering')]});
    check('amqps does not prove configured plain AMQP listener', {listeners: [listener(selected.bind, selected.port, 'amqp/ssl')]});
    check('interface and port must match the same AMQP row', {
        listeners: [listener(selected.bind, selected.port + 1), listener('127.0.0.1', selected.port)]
    });
    check('protocol and interface must match the same row', {
        listeners: [listener(selected.bind, selected.port, 'http'), listener('127.0.0.1', selected.port)]
    });
    check('no AMQP listener', {listeners: []});
    check('listener inspection failed despite plausible stdout', {listenersStatus: 70});
    check('listener inspection timed out', {listenersStatus: 124});
    for (const malformed of ['not JSON', '{}', 'null', '[null]', '[{}]', '"listeners"']) {
        check('invalid listener response ' + malformed, {listeners: malformed});
    }
    check('multiple listener JSON documents are ambiguous', {
        listeners: JSON.stringify(listenerEnvelope([listener(selected.bind, selected.port)])) + '\n{}'
    });
    check('bare listener array is not the RabbitMQ diagnostics envelope', {
        listeners: JSON.stringify([listener(selected.bind, selected.port)])
    });
    for (const result of ['error', null, true]) {
        check('listener envelope must explicitly succeed: ' + result, {
            listenersResponse: {...listenerEnvelope([listener(selected.bind, selected.port)]), result}
        });
    }
    for (const node of ['', null, 1]) {
        check('listener envelope requires a node string: ' + node, {
            listenersResponse: {...listenerEnvelope([listener(selected.bind, selected.port)]), node}
        });
    }
    check('listener envelope requires a listeners array', {
        listenersResponse: {...listenerEnvelope([]), listeners: {interface: selected.bind, port: selected.port, protocol: 'amqp'}}
    });
    check('valid AMQP listener cannot hide a null row', {
        listeners: [listener(selected.bind, selected.port), null]
    });
    check('valid AMQP listener cannot hide an incomplete other row', {
        listeners: [listener(selected.bind, selected.port), {protocol: 'http'}]
    });
    check('valid AMQP listener cannot hide a string-valued port', {
        listeners: [listener(selected.bind, selected.port), listener('127.0.0.1', '15672', 'http')]
    });
    check('valid AMQP listener cannot hide a fractional port', {
        listeners: [listener(selected.bind, selected.port), listener('127.0.0.1', 15672.5, 'http')]
    });
    const dry = check('dry-run performs no inspections', {dryRun: true}, true);
    assert.deepEqual(dry.calls, []);
    console.log('PASS ' + cases + ' offline RabbitMQ runtime-verification scenarios; zero real broker/service/network operations');
} catch (error) {
    console.error(error.stack); process.exitCode = 1;
} finally {
    fs.rmSync(workspace, {recursive: true, force: true});
}
