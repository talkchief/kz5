#!/usr/bin/env node
'use strict';
// SPDX-License-Identifier: MPL-2.0
// Private packet/XML tests. --parse additionally uses installed SIPp -m0:
// no calls, credentials, media or API traffic are generated.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const assert = require('node:assert/strict');
const {inspect} = require('./test-fixtures/assert-callback-unanswered.cjs');
const {capture} = require('./test-fixtures/assert-callback-confirmation-pcap.test.cjs');
const file = path.join(__dirname, 'sip-tests/callback-unanswered.xml');
const source = fs.readFileSync(file, 'utf8');
const id = '1'.repeat(32), busyId = '2'.repeat(32);
const uri = 'sip:+12025550101@127.0.0.30:16060';
const from = '<sip:fixture@example.invalid>;tag=from1', to = '<' + uri + '>', taggedTo = to + ';tag=unanswered1';
const via = 'SIP/2.0/UDP 127.0.0.1:11000;branch=z9hG4bK-first';
function sip(first, method, tagged, body = '', overrides = {}) {
    const values = {'Via': via, 'From': from, 'To': tagged ? taggedTo : to, 'Call-ID': id,
        'CSeq': '1 ' + method, 'Content-Length': String(Buffer.byteLength(body)), ...overrides};
    return Buffer.from(first + '\r\n' + Object.entries(values).map(([key, value]) => key + ': ' + value).join('\r\n') + '\r\n\r\n' + body);
}
function record(time, response, payload) {
    return {time, payload, src: response ? '127.0.0.30' : '127.0.0.1', sport: response ? 16060 : 11000,
        dst: response ? '127.0.0.1' : '127.0.0.30', dport: response ? 11000 : 16060};
}
function records() {
    return [record(1, false, sip('INVITE ' + uri + ' SIP/2.0', 'INVITE', false, 'v=0\r\n')),
        record(1.1, true, sip('SIP/2.0 100 Trying', 'INVITE', false)),
        record(1.2, true, sip('SIP/2.0 180 Ringing', 'INVITE', true)),
        record(46, false, sip('CANCEL ' + uri + ' SIP/2.0', 'CANCEL', false)),
        record(46.1, true, sip('SIP/2.0 200 OK', 'CANCEL', true)),
        record(46.2, true, sip('SIP/2.0 487 Request Terminated', 'INVITE', true)),
        record(46.3, false, sip('ACK ' + uri + ' SIP/2.0', 'ACK', true))];
}
function validateXml(text) {
    text = text.replace(/<!--[\s\S]*?-->/g, '');
    const receives = [...text.matchAll(/<recv request="([A-Z]+)"[^>]*timeout="(\d+)"/g)];
    assert.deepEqual(receives.map(match => match[1]), ['INVITE', 'CANCEL', 'ACK']);
    assert.deepEqual(receives.map(match => Number(match[2])), [90000, 65000, 10000]);
    const sends = [...text.matchAll(/<send\b[^>]*>([\s\S]*?)<\/send>/g)].map(match => match[1]);
    assert.deepEqual(sends.map(body => /SIP\/2\.0 (\d+)/.exec(body)?.[1]), ['100', '180', '200', '487']);
    assert(text.indexOf('<recv request="CANCEL"') < text.indexOf('SIP/2.0 200 OK'));
    assert(text.indexOf('SIP/2.0 487 Request Terminated') < text.indexOf('<recv request="ACK"'));
    assert(/regexp="\^INVITE sip:\\\+12025550101@127\\\.0\\\.0\\\.30/.test(text), 'Exact isolated target must remain guarded');
    for (const header of ['via', 'from', 'to', 'call_id', 'cseq']) {
        assert(text.indexOf('assign_to="invite_' + header) < text.indexOf('<recv request="CANCEL"'));
        assert(sends[3].includes('[$invite_' + header + ']'), '487 must use saved INVITE ' + header);
    }
    for (const [header, variable] of [['Via', 'via'], ['From', 'from'], ['To', 'to'], ['Call-ID', 'call_id'], ['CSeq', 'cseq']]) {
        assert(sends[3].includes(header + ': [$invite_' + variable + ']'), 'Saved extraction is header VALUE, not full header');
    }
    for (const method of ['INVITE', 'CANCEL', 'ACK']) {
        assert(text.includes('regexp="^ *([0-9]+) ' + method + '" search_in="hdr" header="CSeq:"'), 'CSeq regexp must match extracted value');
    }
    assert(sends[2].includes('[last_CSeq:]') && !sends[3].includes('[last_'), 'Do not reply487 to CANCEL instead of original INVITE');
    for (const method of ['cancel', 'ack']) for (const header of ['via', 'call_id', 'sequence']) {
        assert(text.includes('<strcmp variable="invite_' + header + '" variable2="' + method + '_' + header + '" check_it="true"/>'));
    }
    assert(!/<exec|<pause|Content-Type:|m=audio|\[field\d+\]/.test(text), 'Unanswered phase has no answer/media/CSV dependency');
    assert.deepEqual([...text.matchAll(/<log message="([^"]+)"/g)].map(match => match[1]),
        ['callback-unanswered-invite timestamp=[timestamp]', 'callback-unanswered-cancel timestamp=[timestamp]', 'callback-unanswered-ack timestamp=[timestamp]']);
}
let count = 0;
function test(name, body) {body(); count++; console.log('PASS: ' + name);}
test('Actual unanswered XML saves original transaction and has only100/180/200CANCEL/487INVITE', () => validateXml(source));
for (const [name, alter] of [
    ['wrong final response CSeq source', s => s.replace('[$invite_cseq]\n      Content-Length: 0\n    ]]>\n  </send>\n  <recv request="ACK"', '[last_CSeq:]\n      Content-Length: 0\n    ]]>\n  </send>\n  <recv request="ACK"')],
    ['answer instead of ringing', s => s.replace('180 Ringing', '200 OK')],
    ['unbounded cancel wait', s => s.replace('request="CANCEL" timeout="65000"', 'request="CANCEL"')],
    ['missing ACK correlation', s => s.replace('<strcmp variable="invite_via" variable2="ack_via" check_it="true"/>', '')],
    ['media action added', s => s.replace('</scenario>', '<nop><action><exec rtp_stream="apattern,1,0,PCMU/8000"/></action></nop></scenario>')],
    ['private header log', s => s.replace('callback-unanswered-invite timestamp=[timestamp]', 'callback-unanswered-invite [$invite_from]')]
    ,['missing saved header prefix', s => s.replaceAll('Via: [$invite_via]', '[$invite_via]')]
    ,['CSeq regexp expects removed prefix', s => s.replace('regexp="^ *([0-9]+) INVITE"', 'regexp="^CSeq: *([0-9]+) INVITE"')]
]) test('XML rejects ' + name, () => assert.throws(() => validateXml(alter(source))));
for (const link of [1, 113, 276]) for (const little of [true, false]) test('Exact unanswered wire transaction ' + link + '/' + little, () => {
    assert.deepEqual(inspect(capture(records(), link, little)), {firstCallerSipId: id, offerAt: 1, cancelAt: 46, endAt: 46.3});
});
for (const [name, alter] of [
    ...['INVITE', '100', '180', 'CANCEL', '200 CANCEL', '487 INVITE', 'ACK'].map((name, index) => [name, r => {r.splice(index, 1);}]).filter(([name]) => name !== '100'),
    ['answered INVITE', r => {r[2].payload = sip('SIP/2.0 200 OK', 'INVITE', true);}],
    ['extra answered INVITE', r => {r.push(record(2, true, sip('SIP/2.0 200 OK', 'INVITE', true)));}],
    ['rejected instead of unanswered', r => {r[5].payload = sip('SIP/2.0 486 Busy Here', 'INVITE', true);}],
    ['wrong target', r => {r[0].payload = sip('INVITE sip:+12025550999@127.0.0.30:16060 SIP/2.0', 'INVITE', false);}],
    ['wrong CANCEL Call-ID', r => {r[3].payload = sip('CANCEL ' + uri + ' SIP/2.0', 'CANCEL', false, '', {'Call-ID': busyId});}],
    ['wrong CANCEL CSeq', r => {r[3].payload = sip('CANCEL ' + uri + ' SIP/2.0', 'CANCEL', false, '', {'CSeq': '2 CANCEL'});}],
    ['487 inherits CANCEL CSeq', r => {r[5].payload = sip('SIP/2.0 487 Request Terminated', 'CANCEL', true);}],
    ['wrong ACK branch', r => {r[6].payload = sip('ACK ' + uri + ' SIP/2.0', 'ACK', true, '', {'Via': via + '-wrong'});}],
    ['wrong ACK CSeq', r => {r[6].payload = sip('ACK ' + uri + ' SIP/2.0', 'ACK', true, '', {'CSeq': '2 ACK'});}],
    ['wrong To-tag', r => {r[6].payload = sip('ACK ' + uri + ' SIP/2.0', 'ACK', true, '', {'To': to + ';tag=wrong'});}],
    ['wrong From', r => {r[6].payload = sip('ACK ' + uri + ' SIP/2.0', 'ACK', true, '', {'From': '<sip:foreign@example.invalid>;tag=wrong'});}],
    ['duplicate identity header', r => {r[3].payload = Buffer.from(r[3].payload.toString().replace('Call-ID:', 'Call-ID: ' + id + '\r\nCall-ID:'));}],
    ['duplicate Via branch', r => {r[3].payload = sip('CANCEL ' + uri + ' SIP/2.0', 'CANCEL', false, '', {'Via': via + ';branch=z9hG4bK-second'});}],
    ['unsafe CSeq integer', r => {r[3].payload = sip('CANCEL ' + uri + ' SIP/2.0', 'CANCEL', false, '', {'CSeq': '999999999999999999999 CANCEL'});}],
    ['wrong request source', r => {r[3].src = '127.0.0.99';}],
    ['wrong request port', r => {r[3].sport = 11002;}],
    ['wrong response destination', r => {r[5].dst = '127.0.0.99';}],
    ['wrong response source', r => {r[5].src = '127.0.0.99';}],
    ['wrong response port', r => {r[5].sport = 16061;}],
    ['cancel before ringing', r => {r[3].time = 1.1;}],
    ['ACK before487', r => {r[6].time = 46.15;}],
    ['cancel200 before CANCEL', r => {r[4].time = 45;}],
    ['487 with SDP', r => {r[5].payload = sip('SIP/2.0 487 Request Terminated', 'INVITE', true, 'v=0\r\n');}],
    ['another first-attempt dialog', r => {r.push({...r[0], payload: sip('INVITE ' + uri + ' SIP/2.0', 'INVITE', false, '', {'Call-ID': busyId})});}]
]) test('Wire gate rejects ' + name, () => {const r = records(); alter(r); assert.throws(() => inspect(capture(r)));});
test('Retransmissions preserve one exact transaction', () => {
    const r = records(); r.push({...r[0], time: 1.05}, {...r[5], time: 46.25});
    assert.equal(inspect(capture(r)).firstCallerSipId, id);
});
test('No new agent may be offered; optional fullcapture exception is exact busy dialog only', () => {
    const r = records(), agent = {...r[0], dst: '127.0.0.20', dport: 15100,
        payload: sip('INVITE sip:fixture@127.0.0.20 SIP/2.0', 'INVITE', false, '', {'Call-ID': busyId})};
    r.push(agent); assert.throws(() => inspect(capture(r)));
    assert.equal(inspect(capture(r), busyId).firstCallerSipId, id);
    assert.throws(() => inspect(capture(r), '3'.repeat(32)));
});
if (process.argv.includes('--parse')) test('Actual installed SIPp parses scenario with zero-call limit', () => {
    const result = cp.spawnSync('sipp', ['-ci','127.0.0.1','-sf', file, '-i', '127.0.0.31', '-p', '0', '-m', '0', '-nostdin'],
        {encoding: 'utf8', timeout: 5000, maxBuffer: 1024 * 1024});
    assert.ifError(result.error); assert.equal(result.status, 0, result.stderr);
    assert(!/parse error|Unable to load|Unknown element|Variable .* referenced.*(?:not declared|[01] times)/i.test(result.stdout + result.stderr));
});
console.log('PASS: ' + count + ' unanswered callback packet/XML groups; no live traffic');
