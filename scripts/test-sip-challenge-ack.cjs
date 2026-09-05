#!/usr/bin/env node
'use strict';
// SPDX-License-Identifier: MPL-2.0
// Private source/template regression; no SIP, sockets, credentials or files
// are created. Pinned SIPp3.7.7 call.cpp E_Message_Branch uses P_index+offset;
// ack_txn stores ackIndex only. Old-transaction ACK replay occurs before updating
// last_recv_msg, so a captured challenge Via must outlive newer responses.
const fs = require('node:fs'), path = require('node:path');
const assert = require('node:assert/strict');
const via = 'Via: SIP/2.0/UDP 127.0.0.20:15064;branch=z9hG4bK-777-1-0;received=127.0.0.20;rport=15064';
function parts(source) {
    const clean = source.replace(/<!--[\s\S]*?-->/g, '');
    const sends = [...clean.matchAll(/<send\b([^>]*)>([\s\S]*?)<\/send>/g)]
        .map(match => ({attributes: match[1], body: match[2], index: [...clean.slice(0, match.index)
            .matchAll(/<(?:send|recv|nop|pause)\b/g)].length}));
    const select = (test, name) => {
        const matches = sends.filter(test); assert.equal(matches.length, 1, 'Expected exactly one ' + name); return matches[0];
    };
    return {clean, sends,
        invite1: select(send => /start_txn="invite1"/.test(send.attributes), 'initial INVITE'),
        invite2: select(send => /start_txn="invite2"/.test(send.attributes), 'authenticated INVITE'),
        challenge: select(send => /ACK sip:\[field3\]@\[field2\] SIP\/2.0/.test(send.body), 'challenge ACK')};
}
function renderVia(send, savedVia, lastReceivedVia = savedVia) {
    if (send.body.includes('[$challenge_via]')) {
        // extractSubMessage(...,"Via:") returns bytes AFTER the header name.
        const value = savedVia.slice(savedVia.indexOf(':') + 1);
        return send.body.split('\n').find(line => line.includes('[$challenge_via]')).trim().replace('[$challenge_via]', value);
    }
    if (send.body.includes('[last_Via:]')) return lastReceivedVia;
    const branch = /\[branch([+-]\d+)?\]/.exec(send.body);
    assert(branch, 'Missing Via branch');
    return 'Via: SIP/2.0/UDP 127.0.0.20:15064;branch=z9hG4bK-777-1-' + (send.index + Number(branch[1] || 0));
}
const branchOf = header => /;branch=([^;\s]+)/.exec(header)?.[1];
function validate(source) {
    const {clean, sends, invite1, invite2, challenge} = parts(source);
    for (const code of [401, 407]) {
        const receive = new RegExp('<recv response="' + code
            + '"[^>]*response_txn="invite1"[^>]*next="challenge_ack">([\\s\\S]*?)</recv>').exec(clean);
        assert(receive, 'Challenge transaction must be correlated');
        assert(/<ereg regexp="\.\*" search_in="hdr" header="Via:" case_indep="true" check_it="true" assign_to="challenge_via"\/>/.test(receive[1]),
            'Capture the actual challenge Via before changing receive state');
    }
    assert(/ack_txn="invite1"/.test(challenge.attributes));
    assert.equal((challenge.body.match(/\[\$challenge_via\]/g) || []).length, 1, 'Reuse the saved Via exactly once');
    assert(!challenge.body.includes('[last_Via:]'), 'Late challenge ACK must not use a newer receive Via');
    assert(!/\[branch(?:[+-]\d+)?\]/.test(challenge.body), 'No fragile fresh or offset branch in non2xx ACK');
    assert.equal((challenge.body.match(/^\s*Via: \[\$challenge_via\]$/gm) || []).length, 1, 'Prefix saved header value with Via exactly once');
    assert(/CSeq: 1 ACK/.test(challenge.body) && /\[peer_tag_param\]/.test(challenge.body));
    assert(/Call-ID: \[call_id\]/.test(challenge.body));
    assert(!/\[field1\]|Authorization:/.test(challenge.body), 'Challenge ACK must not resend digest credentials');
    assert.equal(branchOf(renderVia(challenge, via, via.replace('-0;', '-99;'))), branchOf(via));
    for (const send of [invite1, invite2]) assert(/branch=\[branch\]/.test(send.body), 'New INVITEs retain distinct transaction branches');
    assert(/CSeq: 1 INVITE/.test(invite1.body) && /CSeq: 2 INVITE/.test(invite2.body));
    assert(!invite1.body.includes('[field1]') && invite2.body.includes('[field1]'), 'Digest belongs only to authenticated retry');
    const successfulAcks = sends.filter(send => /ACK \[next_url\] SIP\/2.0/.test(send.body));
    assert.equal(successfulAcks.length, 2, 'Keep direct and authenticated 2xx ACK paths');
    for (const send of successfulAcks) {
        assert(send.body.includes('[routes]') && /branch=\[branch\]/.test(send.body), '2xx ACK retains route set and new branch');
        assert(!send.body.includes('[last_Via:]'), '2xx ACK is a separate transaction');
    }
}
let count = 0;
for (const name of ['callback-request.xml', 'caller-to-queue.xml']) {
    const source = fs.readFileSync(path.join(__dirname, 'sip-tests', name), 'utf8');
    validate(source); count++;
    // Inserting scenario steps does not change a received Via; unlike branch
    // offsets, this remains correct when the scenario's message indices move.
    const shifted = source.replace('<label id="challenge_ack"/>', '<nop/><pause milliseconds="1"/><label id="challenge_ack"/>');
    validate(shifted); count++;
    const old = source.replace('Via: [$challenge_via]', 'Via: SIP/2.0/[transport] [local_ip]:[local_port];branch=[branch]');
    assert.throws(() => validate(old));
    assert.notEqual(branchOf(renderVia(parts(old).challenge, via)), branchOf(via)); count++;
    const originalIndex = parts(source).invite1.index, ackIndex = parts(source).challenge.index;
    const originalVia = via.replace(/-0;/, '-' + originalIndex + ';');
    const offset = source.replace('Via: [$challenge_via]', 'Via: SIP/2.0/[transport] [local_ip]:[local_port];branch=[branch-' + (ackIndex - originalIndex) + ']');
    assert.equal(branchOf(renderVia(parts(offset).challenge, originalVia)), branchOf(originalVia));
    const offsetShifted = offset.replace('<label id="challenge_ack"/>', '<nop/><label id="challenge_ack"/>');
    assert.notEqual(branchOf(renderVia(parts(offsetShifted).challenge, originalVia)), branchOf(originalVia));
    assert.throws(() => validate(offset)); count++;
    const late = source.replace('Via: [$challenge_via]', '[last_Via:]');
    const laterVia = via.replace('-0;', '-99;');
    assert.notEqual(branchOf(renderVia(parts(late).challenge, via, laterVia)), branchOf(via));
    assert.equal(branchOf(renderVia(parts(source).challenge, via, laterVia)), branchOf(via));
    assert.throws(() => validate(late)); count++;
    for (const alter of [
        text => text.replace('CSeq: 1 ACK', 'CSeq: 2 ACK'),
        text => text.replace('[$challenge_via]', '[$challenge_via]\n      [$challenge_via]'),
        text => text.replace('[$challenge_via]', '[$challenge_via]\n      [field1]'),
        text => text.replace('Via: [$challenge_via]', '[$challenge_via]'),
        text => text.replace('assign_to="challenge_via"', 'assign_to="wrong_saved_via"'),
        text => text.replace('response="407" auth="true" optional="true" response_txn="invite1"', 'response="407" auth="true" optional="true" response_txn="invite2"'),
        text => text.replace('CSeq: 2 INVITE', 'CSeq: 1 INVITE'),
        text => text.replace('ACK [next_url] SIP/2.0\n      Via: SIP/2.0/[transport] [local_ip]:[local_port];branch=[branch]', 'ACK [next_url] SIP/2.0\n      [last_Via:]'),
        text => text.replace('[routes]', '')
    ]) {assert.throws(() => validate(alter(source))); count++;}
}
console.log('PASS: ' + count + ' challenge-ACK transaction/template checks; no SIP or runtime changes');
