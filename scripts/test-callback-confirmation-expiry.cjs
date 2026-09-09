'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {scenario,timing,inspectPackets}=require('./test-fixtures/callback-confirmation-expiry.cjs');
const source=fs.readFileSync(path.join(__dirname,'sip-tests/callback-returned.xml'),'utf8');
const xml=scenario(source);
assert(xml.includes('acceptance1001@'));
assert(xml.includes('<recv request="BYE" timeout="15000"/>'));
assert(xml.includes('rtp_stream="apattern,1,0,PCMU/8000"'));
assert(!xml.includes('play_pcap_audio')&&!xml.includes('CALLBACK_NEGOTIATED_DTMF'));
assert(!xml.includes('BYE [next_url]')&&!xml.includes('<pause variable='));
assert(xml.endsWith('</scenario>\n'));
assert.throws(()=>scenario(source.replace('<pause variable="confirm_delay_ms"/>','')));
assert.throws(()=>scenario(source+source));
assert.equal(timing(100,100.5,104.831,107.86,3).response_timeout_seconds,3);
for(const bad of [[100,100.5,104.831,103.5,3],[100,100.5,104.831,106,3],
    [100,100.5,104.831,110,3],[100,100.5,102.5,105.5,3],
    [100,99,103.331,106.331,3],[100,100.5,104.831,107.86,15]])assert.throws(()=>timing(...bad));
assert.throws(()=>inspectPackets([],Buffer.alloc(34648), 'owned-call'));
console.log('PASS confirmation-expiry generator, timeout boundaries and missing-evidence rejection');
