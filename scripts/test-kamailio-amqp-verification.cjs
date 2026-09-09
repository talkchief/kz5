#!/usr/bin/env node
'use strict';
// Offline fixtures only: extract actual installer functions, never source its
// protected deployment config, and replace every service/network command.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const scriptDir = __dirname;
const source = fs.readFileSync(path.join(scriptDir, 'install-kazoo5.sh'), 'utf8');
const extract = name => {
    const match = source.match(new RegExp(`^${name}\\(\\) \\{\\n[\\s\\S]*?^\\}`, 'm'));
    assert.ok(match, `missing production function ${name}`);
    return match[0];
};
const functions = ['verify_kamailio_amqp_connection', 'verify_kamailio_local_amqp_queues'].map(extract).join('\n');
let checks = 0;
const childEnv = {PATH: '/usr/bin:/bin', LC_ALL: 'C.UTF-8'};
function parse(uri, expected) {
    const child = spawnSync('/usr/bin/python3', ['-B', '-I', path.join(scriptDir, 'kamailio-amqp-endpoint.py')],
        {input: uri, encoding: 'utf8', env: childEnv, timeout: 5000});
    assert.ifError(child.error);
    if (expected) {
        assert.equal(child.status, 0, child.stderr);
        assert.deepEqual(JSON.parse(child.stdout), expected);
    } else {
        assert.notEqual(child.status, 0);
        assert.equal(child.stdout, '');
        assert.equal(child.stderr.trim(), 'Invalid or unsupported effective Kamailio AMQP URI');
    }
    assert.ok(!`${child.stdout}${child.stderr}`.includes('sentinel-secret'));
    checks++;
}
const plain = (host, port, vhost) => ({host, port, vhost, protocol: 'amqp'});
parse('amqp://user:sentinel-secret@mq.example.net', plain('mq.example.net', 5672, '/'));
parse('amqp://user:sentinel-secret@mq.example.net/', plain('mq.example.net', 5672, ''));
parse('amqp://user:sentinel-secret@mq.example.net:5679/team%2Fvoice', plain('mq.example.net', 5679, 'team/voice'));
parse('amqp://user:sentinel-secret@mq.example.net/%252F', plain('mq.example.net', 5672, '%2F'));
parse('amqps://user:sentinel-secret@[2001:db8::1]/%2F', {...plain('2001:db8::1', 5671, '/'), protocol: 'amqp/ssl'});
parse('amqp://user:sentinel-secret@127.0.0.1/%D7%A7%D7%95%D7%9C', plain('127.0.0.1', 5672, 'קול'));
for (const uri of [
    'https://user:sentinel-secret@mq.example.net/',
    'amqp://user:sentinel-secret@/vhost',
    'amqp://user:sentinel-secret@mq.example.net:0/',
    'amqp://user:sentinel-secret@mq.example.net:65536/',
    'amqp://user:sentinel-secret@mq.example.net:/',
    'amqp://user:sentinel-secret@mq.example.net/a/b',
    'amqp://user:sentinel-secret@mq.example.net/%0A',
    'amqp://user:sentinel-secret@mq.example.net/%FF',
    'amqp://user:sentinel-secret@mq.example.net/%xy',
    'amqp://user:sentinel-secret@mq.example.net/?heartbeat=5',
    'amqp://user:sentinel-secret@mq.example.net/#fragment',
    'amqp://user:sentinel-secret@mq.example.net/\n',
    'amqp://user:sentinel-secret@mq.example.net@other.example.net/',
    'amqp://user:sentinel-secret@[fe80::1%25eth0]/',
    `amqp://user:sentinel-secret@mq.example.net/${'a'.repeat(16385)}`,
]) parse(uri);

const listener = (address = '127.0.0.1', port = 5679, protocol = 'amqp') =>
    ({result: 'ok', node: 'rabbit@fixture', listeners: [{interface: address, port, protocol}]});
const connection = (peer = '127.0.0.1:5679', process = 'kamailio') =>
    `0 0 127.0.0.1:40300 ${peer} users:(("${process}",pid=123,fd=4))`;
const fixture = `
set -Eeuo pipefail
die() { printf 'FAIL %s\\n' "$*" >&2; exit 1; }
log() { printf '%s\\n' "$*"; }
getent() { [[ $1 == ahosts && $2 == "$F_HOST" ]] || die 'wrong effective host'; printf '%s\\n' "$F_ADDRESSES"; }
ss() { [[ $* == *"dport = :$F_PORT"* ]] || die 'wrong effective port'; printf '%s\\n' "$F_SS"; }
id() { [[ $* == kamailio ]]; }
runuser() {
    [[ $* == "-u kamailio -- ss -H -tnp state established ( dport = :$F_PORT )" ]] || die 'unexpected privilege change';
    printf '%s\\n' "$F_SS_USER";
}
systemctl() { [[ $* == 'is-active --quiet rabbitmq-server.service' ]] || die 'unexpected systemctl'; [[ $F_ACTIVE == true ]]; }
ip() { [[ $* == '-j address show' ]] || die 'unexpected ip'; printf '%s\\n' "$F_LOCAL"; }
rabbitmq-diagnostics() { printf 'LISTENERS\\n' >&2; printf '%s\\n' "$F_LISTENERS"; }
rabbitmqctl() {
    [[ $# == 5 && $1 == -q && $2 == -p && $3 == "$F_VHOST" && $4 == list_queues && $5 == name ]] || die 'wrong effective vhost';
    printf 'QUEUES\\n'; printf '%s\\n' "$F_QUEUES";
}
timeout() { [[ $1 == --signal=TERM && $2 == --kill-after=5 && $3 == 30 ]] || die 'unbounded CLI'; shift 3; "$@"; }
sleep() { SECONDS=999; }
${functions}
verify_kamailio_amqp_connection
`;
function run(name, changes = {}, success = true, queues = true, message = '') {
    const env = {...childEnv, SCRIPT_DIR: scriptDir,
        KAZOO_AMQP_URI: 'amqp://user:sentinel-secret@127.0.0.1:5679/team%2Fvoice',
        // Deliberately inconsistent legacy defaults must never drive checks.
        KAZOO_AMQP_HOST: 'wrong.example.net', KAZOO_AMQP_PORT: '5672', KAZOO_RABBITMQ_VHOST: '/',
        KAZOO_HOSTNAME: 'sbc.example.net', KAZOO_START_TIMEOUT: '1',
        F_HOST: '127.0.0.1', F_PORT: '5679', F_VHOST: 'team/voice',
        F_ADDRESSES: '127.0.0.1 STREAM broker', F_SS: connection(), F_SS_USER: '', F_ACTIVE: 'true',
        F_LOCAL: JSON.stringify([{addr_info: [{local: '127.0.0.1'}, {local: '10.0.0.2'}, {local: '::1'}]}]),
        F_LISTENERS: JSON.stringify(listener()), F_QUEUES: 'kamailio@sbc.example.net-consumer', ...changes};
    const child = spawnSync('/bin/bash', ['--noprofile', '--norc', '-c', fixture],
        {encoding: 'utf8', env, timeout: 5000});
    assert.ifError(child.error);
    const output = `${child.stdout}${child.stderr}`;
    assert.equal(child.status === 0, success, `${name}: ${output}`);
    assert.equal(output.includes('PASS Kamailio consumer queues'), queues, `${name}: ${output}`);
    assert.ok(!output.includes('sentinel-secret'), `${name}: credential leaked`);
    if (message) assert.ok(output.includes(message), `${name}: missing ${message}: ${output}`);
    checks++;
}
run('effective URI host, nonstandard port and decoded nondefault vhost');
run('confined root inspects as service UID', {F_SS: '0 0 127.0.0.1:40300 127.0.0.1:5679', F_SS_USER: connection()});
run('bare socket remains insufficient', {F_SS: '', F_SS_USER: '0 0 127.0.0.1:40300 127.0.0.1:5679'}, false, false);
run('service UID wrong peer remains rejected', {F_SS: '', F_SS_USER: connection('127.0.0.2:5679')}, false, false);
run('empty vhost remains empty', {KAZOO_AMQP_URI: 'amqp://user:sentinel-secret@127.0.0.1:5679/', F_VHOST: ''});
run('remote broker ignores active unrelated local RabbitMQ', {
    KAZOO_AMQP_URI: 'amqp://user:sentinel-secret@mq.example.net:5679/team%2Fvoice', F_HOST: 'mq.example.net',
    F_ADDRESSES: '192.0.2.8 STREAM broker', F_SS: connection('192.0.2.8:5679'),
    F_LISTENERS: 'invalid', F_QUEUES: ''}, true, false, 'remote or mixed-locality');
run('mixed local and remote DNS does not assert local queues', {
    F_ADDRESSES: '127.0.0.1 STREAM broker\n192.0.2.8 STREAM broker', F_LISTENERS: 'invalid', F_QUEUES: ''}, true, false, 'mixed-locality');
run('inactive local RabbitMQ permits transport-only check', {F_ACTIVE: 'false', F_QUEUES: ''}, true, false, 'no active local');
run('exact assigned local interface', {
    KAZOO_AMQP_URI: 'amqp://user:sentinel-secret@10.0.0.2:5679/team%2Fvoice', F_HOST: '10.0.0.2',
    F_ADDRESSES: '10.0.0.2 STREAM broker', F_SS: connection('10.0.0.2:5679'),
    F_LISTENERS: JSON.stringify(listener('10.0.0.2'))});
run('wildcard IPv4 listener', {F_LISTENERS: JSON.stringify(listener('0.0.0.0'))});
run('TLS URI default port and IPv6 peer', {
    KAZOO_AMQP_URI: 'amqps://user:sentinel-secret@[::1]/team%2Fvoice', F_HOST: '::1', F_PORT: '5671',
    F_ADDRESSES: '::1 STREAM broker', F_SS: connection('[::1]:5671'),
    F_LISTENERS: JSON.stringify(listener('::', 5671, 'amqp/ssl'))});
for (const [name, changes] of [
    ['wrong peer', {F_SS: connection('127.0.0.2:5679')}],
    ['wrong port', {F_SS: connection('127.0.0.1:5672')}],
    ['wrong process', {F_SS: connection('127.0.0.1:5679', 'other')}],
    ['process prefix collision', {F_SS: connection('127.0.0.1:5679', 'kamailio-other')}],
    ['another local listener port', {F_LISTENERS: JSON.stringify(listener('127.0.0.1', 5672))}],
    ['another local listener address', {F_LISTENERS: JSON.stringify(listener('10.0.0.2'))}],
    ['another local listener protocol', {F_LISTENERS: JSON.stringify(listener('127.0.0.1', 5679, 'amqp/ssl'))}],
    ['listener matches other DNS address but not connected peer', {
        F_ADDRESSES: '127.0.0.1 STREAM broker\n10.0.0.2 STREAM broker', F_LISTENERS: JSON.stringify(listener('10.0.0.2'))}],
    ['missing queues', {F_QUEUES: ''}],
    ['hostname substring queue is not evidence', {F_QUEUES: 'prefix-kamailio@sbc.example.net-consumer'}],
    ['wrong SBC queue', {F_QUEUES: 'kamailio@other.example.net-consumer'}],
    ['malformed listener evidence', {F_LISTENERS: '[]'}],
    ['unresolved effective host', {F_ADDRESSES: ''}],
    ['invalid effective URI', {KAZOO_AMQP_URI: 'amqp://user:sentinel-secret@host:0/'}],
]) run(name, changes, false, false);
assert.ok(extract('verify_kamailio').includes('verify_kamailio_amqp_connection'));
assert.ok(!extract('verify_kamailio').includes('rabbitmqctl -q list_queues'));
console.log(`PASS Kamailio effective AMQP endpoint: ${checks} offline fixtures`);
