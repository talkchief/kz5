#!/usr/bin/env node
'use strict';
// SPDX-License-Identifier: MPL-2.0
// Read-only proof of an unanswered fixture INVITE terminated by CANCEL.
// Never print SIP headers, credentials or payloads. Times are epoch seconds.
const assert = require('node:assert/strict');
const {packets} = require('./assert-callback-confirmation-pcap.cjs');
const validId = value => typeof value === 'string' && /^[A-Za-z0-9@._:-]{1,128}$/.test(value);
function message(packet) {
    const text = packet.payload.toString('latin1'), split = text.indexOf('\r\n\r\n');
    assert(split >= 0, 'Incomplete unanswered SIP message');
    const lines = text.slice(0, split).split('\r\n'), first = lines.shift(), headers = {};
    for (const line of lines) {
        const match = /^([^:\s]+):\s*(.*)$/.exec(line);
        assert(match, 'Malformed unanswered SIP header');
        (headers[match[1].toLowerCase()] ||= []).push(match[2].trim());
    }
    const one = name => {assert(headers[name]?.length === 1, 'Missing/ambiguous unanswered SIP header'); return headers[name][0];};
    const callId = one('call-id'), cseq = /^(\d+) (INVITE|CANCEL|ACK)$/.exec(one('cseq'));
    const via = one('via'), branches = [...via.matchAll(/(?:^|;)branch=([^;\s]+)/g)], branch = branches[0];
    assert(validId(callId) && cseq && Number.isSafeInteger(Number(cseq[1]))
        && branches.length === 1 && /^z9hG4bK[-A-Za-z0-9._]+$/.test(branch[1]), 'Invalid unanswered transaction identity');
    const length = one('content-length'), body = text.slice(split + 4);
    assert(/^\d+$/.test(length) && Number(length) === Buffer.byteLength(body, 'latin1'), 'Invalid unanswered SIP body length');
    return {...packet, first, callId, sequence: Number(cseq[1]), method: cseq[2], via, branch: branch[1],
        from: one('from'), to: one('to'), body};
}
function unique(messages, name) {
    assert(messages.length > 0, 'Missing unanswered ' + name);
    const first = messages[0];
    for (const item of messages) for (const key of ['first', 'callId', 'sequence', 'method', 'via', 'from', 'to', 'body', 'src', 'dst', 'sport', 'dport']) {
        assert(item[key] === first[key], 'Ambiguous unanswered ' + name);
    }
    return messages.reduce((before, item) => item.time < before.time ? item : before);
}
function inspect(buffer, busyAgentSipId) {
    assert(busyAgentSipId === undefined || validId(busyAgentSipId), 'Invalid permitted busy-agent dialog');
    const groups = {offer: [], ringing: [], cancel: [], cancelOk: [], terminated: [], ack: [], trying: []};
    for (const packet of packets(buffer)) {
        const start = packet.payload.subarray(0, 32).toString('latin1');
        if (packet.dst === '127.0.0.20' && packet.dport === 15100 && start.startsWith('INVITE ')) {
            const id = message(packet).callId;
            assert(busyAgentSipId !== undefined && id === busyAgentSipId, 'Agent offered before unanswered callback settled');
        }
        const incoming = packet.dst === '127.0.0.30' && packet.dport === 16060;
        const outgoing = packet.src === '127.0.0.30' && packet.sport === 16060;
        if ((!incoming && !outgoing) || !/^(?:INVITE |CANCEL |ACK |SIP\/2\.0 )/.test(start)) continue;
        const item = message(packet);
        let key;
        if (incoming && /^INVITE /.test(item.first)) key = 'offer';
        else if (incoming && /^CANCEL /.test(item.first)) key = 'cancel';
        else if (incoming && /^ACK /.test(item.first)) key = 'ack';
        else if (outgoing && /^SIP\/2\.0 100 /.test(item.first) && item.method === 'INVITE') key = 'trying';
        else if (outgoing && /^SIP\/2\.0 180 /.test(item.first) && item.method === 'INVITE') key = 'ringing';
        else if (outgoing && /^SIP\/2\.0 200 /.test(item.first) && item.method === 'CANCEL') key = 'cancelOk';
        else if (outgoing && /^SIP\/2\.0 487 /.test(item.first) && item.method === 'INVITE') key = 'terminated';
        else assert.fail('Unexpected response or answered first callback attempt');
        groups[key].push(item);
    }
    const offer = unique(groups.offer, 'INVITE'), ringing = unique(groups.ringing, '180'), cancel = unique(groups.cancel, 'CANCEL');
    const ok = unique(groups.cancelOk, '200 CANCEL'), terminated = unique(groups.terminated, '487 INVITE'), ack = unique(groups.ack, 'ACK');
    const uri = /^INVITE (sip:\+12025550101@127\.0\.0\.30(?::16060)?(?:;transport=udp)?) SIP\/2\.0$/.exec(offer.first)?.[1];
    assert(uri && offer.method === 'INVITE' && cancel.first === 'CANCEL ' + uri + ' SIP/2.0'
        && cancel.method === 'CANCEL' && ack.first === 'ACK ' + uri + ' SIP/2.0' && ack.method === 'ACK',
    'Unanswered request destination/method mismatch');
    for (const item of [ringing, cancel, ok, terminated, ack, ...groups.trying]) {
        assert(item.callId === offer.callId && item.sequence === offer.sequence
            && item.via === offer.via && item.branch === offer.branch && item.from === offer.from,
        'Unanswered original transaction correlation failed');
        const isRequest = item === cancel || item === ack;
        assert(isRequest ? item.src === offer.src && item.sport === offer.sport
            : item.dst === offer.src && item.dport === offer.sport, 'Unanswered SIP transport direction mismatch');
        assert(item.body === '', 'Unanswered response/request must not establish media');
    }
    const toBase = value => value.replace(/;tag=[^;\s]+/, '');
    assert(!/;tag=/.test(offer.to) && cancel.to === offer.to
        && toBase(ringing.to) === offer.to && /;tag=[^;\s]+/.test(ringing.to)
        && terminated.to === ringing.to && ack.to === ringing.to && ok.to === ringing.to,
    'Unanswered dialog To-tag correlation failed');
    assert(offer.time <= ringing.time && ringing.time < cancel.time
        && cancel.time <= ok.time && ok.time <= terminated.time && terminated.time <= ack.time,
    'Unanswered transaction ordering failed');
    for (const trying of groups.trying) assert(offer.time <= trying.time && trying.time <= ringing.time, 'Unanswered provisional ordering failed');
    return {firstCallerSipId: offer.callId, offerAt: offer.time, cancelAt: cancel.time, endAt: ack.time};
}
module.exports = {inspect};
