#!/usr/bin/env node
'use strict';
// Fixture-only derivation: reuse the reviewed authentication transactions.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const sha = value => crypto.createHash('sha256').update(value).digest('hex');
function expectedDigits(mode) {
    assert(['entry-only', 'confirm-current'].includes(mode), 'Invalid registration mode');
    return mode === 'entry-only' ? [6] : [6, 1];
}
function scenarios(root = path.join(__dirname, '..', 'sip-tests'), mode = 'confirm-current') {
    expectedDigits(mode);
    let request = fs.readFileSync(path.join(root, 'callback-request.xml'), 'utf8');
    assert.equal((request.match(/<pause milliseconds="4000"\/>/g) || []).length, 1);
    // Pinned SIPp adds approximately 780ms of RTP warmup before play_dtmf's
    // first event. The received-packet gate, not this pause alone, proves5s.
    request = request.replace('<pause milliseconds="4000"/>',
        '<!-- 4200ms + pinned SIPp ~780ms DTMF warmup targets actual entry at5s. -->\n  <pause milliseconds="4200"/>');
    if (mode === 'entry-only') {
        const extraConfirmation = '  <pause milliseconds="2500"/>\n'
            + '  <nop><action><exec play_dtmf="1,200"/></action></nop>\n  <pause milliseconds="1000"/>';
        assert.equal(request.split(extraConfirmation).length, 2, 'Expected exact historical registration confirmation block');
        request = request.replace(extraConfirmation,
            '  <!-- entry-only: no registration digit1; receive the server BYE after full success audio. -->');
    }
    request = request.replace('<label id="menu"/>', '<label id="menu"/>\n  <!-- registration-mode: ' + mode + ' -->');
    for (const action of ['apattern,1,0,PCMU/8000', 'pauseapattern']) {
        const text = '<nop><action><exec rtp_stream="' + action + '"/></action></nop>';
        assert.equal(request.split(text).length, 2, 'Expected one original pattern action');
        request = request.replace(text, '<!-- Original caller receives queue media; no pattern-echo comparison. -->');
    }
    let busy = fs.readFileSync(path.join(root, 'caller-to-queue.xml'), 'utf8');
    const start = busy.indexOf('  <!-- Per-call duration');
    const end = busy.indexOf('  <ResponseTimeRepartition', start);
    assert(start > 0 && end > start && busy.slice(start, end).includes('start_txn="bye"'));
    busy = busy.slice(0, start) + `  <!-- The orchestrator releases ONLY this freshly proved fixture caller.
       Receive the server BYE normally, with an absolute bounded fallback. -->
  <Reference variables="hold_ms"/>
  <recv request="BYE" timeout="120000"/>
  <nop><action><exec rtp_stream="pauseapattern"/></action></nop>
  <send><![CDATA[
      SIP/2.0 200 OK
      [last_Via:]
      [last_From:]
      [last_To:]
      [last_Call-ID:]
      [last_CSeq:]
      Content-Length: 0
  ]]></send>

` + busy.slice(end);
    return {'callback-retry-request.xml': request, 'callback-busy-caller.xml': busy};
}
function modeReceipt(mode = 'confirm-current') {
    const sources = ['create-callback-retry-scenarios.cjs', 'assert-callback-registration-audio.cjs',
        'assert-callback-retry.cjs', '../test-acdc-callback-retry.sh', '../test-acdc-callback-fixture.sh',
        '../sip-tests/callback-request.xml', '../sip-tests/caller-to-queue.xml'];
    return {schema_version: 1, registration_mode: mode, expected_registration_digits: expectedDigits(mode),
        allow_alternate_number: false, scenario_sha256: Object.fromEntries(
            Object.entries(scenarios(undefined, mode)).map(([name, source]) => [name, sha(source)])),
        input_sha256: Object.fromEntries(sources.map(name => [name, sha(fs.readFileSync(path.join(__dirname, name)))]))};
}
module.exports = {scenarios, expectedDigits, modeReceipt};
if (require.main === module) {
    assert([3, 4].includes(process.argv.length), 'Usage: create-callback-retry-scenarios.cjs protected-directory [entry-only|confirm-current]');
    const directory = process.argv[2], mode = process.argv[3] || 'confirm-current', receipt = modeReceipt(mode), stat = fs.lstatSync(directory);
    assert(stat.isDirectory() && !stat.isSymbolicLink() && stat.uid === 0 && (stat.mode & 0o077) === 0,
        'Scenario directory must be root-owned and private');
    for (const [name, source] of Object.entries(scenarios(undefined, mode))) {
        fs.writeFileSync(path.join(directory, name), source, {mode: 0o600, flag: 'wx'});
    }
    fs.writeFileSync(path.join(directory, 'retry-registration-mode.json'), JSON.stringify(receipt, null, 2) + '\n', {mode: 0o600, flag: 'wx'});
}
