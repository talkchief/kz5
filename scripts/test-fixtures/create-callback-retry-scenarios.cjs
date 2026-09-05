#!/usr/bin/env node
'use strict';
// Fixture-only derivation: reuse the reviewed authentication transactions.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
function scenarios(root = path.join(__dirname, '..', 'sip-tests')) {
    let request = fs.readFileSync(path.join(root, 'callback-request.xml'), 'utf8');
    assert.equal((request.match(/<pause milliseconds="4000"\/>/g) || []).length, 1);
    // Pinned SIPp adds approximately 780ms of RTP warmup before play_dtmf's
    // first event. The received-packet gate, not this pause alone, proves5s.
    request = request.replace('<pause milliseconds="4000"/>',
        '<!-- 4200ms + pinned SIPp ~780ms DTMF warmup targets actual entry at5s. -->\n  <pause milliseconds="4200"/>');
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
module.exports = {scenarios};
if (require.main === module) {
    assert.equal(process.argv.length, 3, 'Usage: create-callback-retry-scenarios.cjs protected-directory');
    const directory = process.argv[2], stat = fs.lstatSync(directory);
    assert(stat.isDirectory() && !stat.isSymbolicLink() && stat.uid === 0 && (stat.mode & 0o077) === 0,
        'Scenario directory must be root-owned and private');
    for (const [name, source] of Object.entries(scenarios())) {
        fs.writeFileSync(path.join(directory, name), source, {mode: 0o600, flag: 'wx'});
    }
}
