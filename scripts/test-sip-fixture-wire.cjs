#!/usr/bin/env node
'use strict';
// SPDX-License-Identifier: MPL-2.0
// Explicit private SIPp wire test: synthetic messages on127.0.0.62 only,
// ephemeral UDP ports, no Kazoo/proxy/API/media. Never prints SIP/auth payloads.
const fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const dgram = require('node:dgram'), cp = require('node:child_process'), assert = require('node:assert/strict');
const IP = '127.0.0.62', pause = ms => new Promise(resolve => setTimeout(resolve, ms));
function parse(buffer) {
    const text = buffer.toString(), split = text.indexOf('\r\n\r\n');
    assert(split >= 0, 'Rendered SIP has no header boundary');
    const lines = text.slice(0, split).split('\r\n'), first = lines.shift(), headers = {};
    for (const line of lines) {
        const m = /^([^:\s]+):\s*(.*)$/.exec(line); assert(m, 'Rendered SIP has an unprefixed header value');
        (headers[m[1].toLowerCase()] ||= []).push(m[2].trim());
    }
    const one = key => {assert.equal(headers[key]?.length, 1, 'Rendered SIP missing/ambiguous ' + key); return headers[key][0];};
    for (const key of ['via', 'from', 'to', 'call-id', 'cseq', 'content-length']) one(key);
    assert.equal(Number(one('content-length')), Buffer.byteLength(text.slice(split + 4)));
    return {first, headers, one};
}
function reply(request, code, tag = '', extras = {}) {
    const headers = {'Via': request.one('via'), 'From': request.one('from'),
        'To': request.one('to') + (tag ? ';tag=' + tag : ''), 'Call-ID': request.one('call-id'),
        'CSeq': request.one('cseq'), ...extras, 'Content-Length': '0'};
    return Buffer.from('SIP/2.0 ' + code + '\r\n' + Object.entries(headers).map(([k,v]) => k + ': ' + v).join('\r\n') + '\r\n\r\n');
}
function request(method, uri, headers) {
    return Buffer.from(method + ' ' + uri + ' SIP/2.0\r\n' + Object.entries({...headers, 'Content-Length': '0'})
        .map(([k,v]) => k + ': ' + v).join('\r\n') + '\r\n\r\n');
}
async function bound() {
    const socket = dgram.createSocket('udp4');
    await new Promise((resolve, reject) => {socket.once('error', reject); socket.bind(0, IP, resolve);});
    return socket;
}
async function fixture(name, csv, body) {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'kazoo-private-sip-wire.'));
    const peer = await bound(), reservation = await bound(), port = reservation.address().port;
    await new Promise(resolve => reservation.close(resolve));
    let child, exit, diagnostic = '', received = [];
    peer.on('message', (buffer, source) => {received.push({buffer, source});});
    try {
        const args = [IP + ':' + peer.address().port, '-sf', path.join(__dirname, 'sip-tests', name),
            '-i', IP, '-p', String(port), '-m', '1', '-l', '1', '-nostdin', '-timeout', '8s', '-timeout_error'];
        if (csv) {const file = path.join(directory, 'synthetic.csv'); fs.writeFileSync(file, csv, {mode: 0o600}); args.push('-inf', file);}
        child = cp.spawn('sipp', args, {cwd: directory, stdio: ['ignore', 'pipe', 'pipe']});
        exit = new Promise((resolve, reject) => {child.once('error', reject); child.once('exit', (code, signal) => resolve({code, signal}));});
        for (const output of [child.stdout, child.stderr]) output.on('data', b => {if (diagnostic.length < 8192) diagnostic += b.toString();});
        const send = buffer => new Promise((resolve, reject) => peer.send(buffer, port, IP, error => error ? reject(error) : resolve()));
        const observed = [];
        const take = async (predicate, timeout = 2500) => {
            const until = Date.now() + timeout;
            while (Date.now() < until) {
                while (received.length) {
                    const incoming = received.shift();
                    assert.equal(incoming.source.address, IP); assert.equal(incoming.source.port, port);
                    const message = parse(incoming.buffer);
                    observed.push(message);
                    if (predicate(message)) return message;
                }
                if (child.exitCode !== null) throw new Error('SIPp exited before expected private wire exchange');
                await pause(10);
            }
            throw new Error('Private wire response timed out');
        };
        await body({send, take, exit, peerPort: peer.address().port, observed});
        assert(!/Failed regexp|strcmp.*failed|parse error|Unknown element|unrecognized keyword/i.test(diagnostic), 'SIPp rejected header extraction/rendering');
    } finally {
        if (child && child.exitCode === null && child.signalCode === null) child.kill('SIGTERM');
        if (exit) await Promise.race([exit.catch(() => {}), pause(1000)]);
        if (child && child.exitCode === null && child.signalCode === null) {child.kill('SIGKILL'); await exit;}
        peer.close();
        assert(directory.startsWith(path.join(os.tmpdir(), 'kazoo-private-sip-wire.')));
        fs.rmSync(directory, {recursive: true});
    }
}
async function challenge(name, status) {
    const csv = 'SEQUENTIAL\ndummy;[authentication username=dummy password=dummy];example.invalid;2000;'
        + (name === 'callback-request.xml' ? '+12025550101;6' : '1000;0') + '\n';
    await fixture(name, csv, async ({send, take}) => {
        const invite = await take(m => m.first.startsWith('INVITE '));
        const challenge = reply(invite, status + ' Challenge', 'challenge-tag', {
            [status === 401 ? 'WWW-Authenticate' : 'Proxy-Authenticate']: 'Digest realm="example.invalid",nonce="0123456789abcdef",algorithm=MD5,qop="auth"'});
        await send(challenge);
        const checkAck = ack => {
            for (const key of ['via', 'from', 'call-id']) assert.equal(ack.one(key), invite.one(key), 'Challenge ACK lost original ' + key);
            assert.equal(ack.one('to'), invite.one('to') + ';tag=challenge-tag', 'Challenge ACK lost original To-tag');
            assert.equal(ack.one('cseq'), '1 ACK');
        };
        checkAck(await take(m => m.first.startsWith('ACK ')));
        const authenticated = await take(m => m.first.startsWith('INVITE ') && m.one('cseq') === '2 INVITE');
        assert.notEqual(authenticated.one('via'), invite.one('via'));
        assert.equal(authenticated.one('call-id'), invite.one('call-id'));
        assert.equal(authenticated.headers[status === 401 ? 'authorization' : 'proxy-authorization']?.length, 1);
        await send(reply(authenticated, '100 Trying'));
        await send(reply(authenticated, '180 Ringing', 'newer-transaction-tag'));
        await pause(50);
        await send(challenge);
        checkAck(await take(m => m.first.startsWith('ACK ') && m.one('cseq') === '1 ACK'));
    });
    console.log('PASS private wire ' + name + ' ' + status + ': saved Via/To/Call-ID/CSeq survive later response');
}
async function unanswered() {
    await fixture('callback-unanswered.xml', null, async ({send, take, exit, peerPort, observed}) => {
        const uri = 'sip:+12025550101@127.0.0.30:16060';
        const headers = {'Via': 'SIP/2.0/UDP ' + IP + ':' + peerPort + ';branch=z9hG4bK-private-wire',
            'From': '<sip:fixture@example.invalid>;tag=private-from', 'To': '<' + uri + '>',
            'Call-ID': 'private-unanswered@127.0.0.62', 'CSeq': '1 INVITE'};
        await pause(100);
        await send(request('INVITE', uri, headers));
        const trying = await take(m => m.first.startsWith('SIP/2.0 100 '));
        const ringing = await take(m => m.first.startsWith('SIP/2.0 180 '));
        for (const item of [trying, ringing]) {
            assert.equal(item.one('cseq'), '1 INVITE'); assert.equal(item.one('call-id'), headers['Call-ID']);
            assert.equal(item.one('from'), headers.From); assert.equal(item.one('via'), headers.Via);
        }
        assert.equal(trying.one('to'), headers.To);
        assert(ringing.one('to').startsWith(headers.To + ';tag='));
        await send(request('CANCEL', uri, {...headers, CSeq: '1 CANCEL'}));
        const ok = await take(m => m.first.startsWith('SIP/2.0 200 '));
        const terminated = await take(m => m.first.startsWith('SIP/2.0 487 '));
        assert.equal(ok.one('cseq'), '1 CANCEL'); assert.equal(terminated.one('cseq'), '1 INVITE');
        for (const item of [ok, terminated]) for (const key of ['via', 'from', 'to', 'call-id']) {
            assert.equal(item.one(key), ringing.one(key));
        }
        assert(!observed.some(m => m.first.startsWith('SIP/2.0 200 ') && / INVITE$/.test(m.one('cseq'))),
            'Unanswered SIPp fixture must never answer INVITE');
        await send(request('ACK', uri, {...headers, To: terminated.one('to'), CSeq: '1 ACK'}));
        const finished = await exit; assert.equal(finished.code, 0, 'Unanswered SIPp transaction did not complete');
    });
    console.log('PASS private wire unanswered:100/180 then200CANCEL/487INVITE and matchedACK; no200INVITE');
}
(async () => {
    for (const name of ['callback-request.xml', 'caller-to-queue.xml']) for (const code of [401, 407]) await challenge(name, code);
    await unanswered();
    console.log('PASS five actual SIPp exchanges on private127.0.0.62 only; no Kazoo/API/media traffic');
})().catch(error => {console.error('Private SIP fixture wire FAIL: ' + error.message); process.exitCode = 1;});
