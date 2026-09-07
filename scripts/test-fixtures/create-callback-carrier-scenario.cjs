#!/usr/bin/env node
'use strict';
// Generate only local test media and a SIPp scenario. The actual INVITE's
// offered telephone-event mapping selects exactly one dynamic-payload branch.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

function digitPcap(payload, transport='external') {
    const endpointIp=require('./callback-internal-scenarios.cjs').endpointIp(transport);
    assert(Number.isInteger(payload) && payload >= 96 && payload <= 127);
    const header = Buffer.alloc(24);
    header.writeUInt32LE(0xa1b2c3d4); header.writeUInt16LE(2, 4); header.writeUInt16LE(4, 6);
    header.writeUInt32LE(65535, 16); header.writeUInt32LE(1, 20);
    const records = [header];
    for (let index = 0; index < 13; index++) {
        const packet = Buffer.alloc(58), udp = 34, rtp = 42;
        packet.writeUInt16BE(0x0800, 12); packet[14] = 0x45;
        packet.writeUInt16BE(44, 16); packet[22] = 64; packet[23] = 17;
        Buffer.from(endpointIp.split('.').map(Number)).copy(packet, 26);
        Buffer.from([127, 0, 0, 1]).copy(packet, 30);
        packet.writeUInt16BE(44000, udp); packet.writeUInt16BE(20000, udp + 2);
        packet.writeUInt16BE(24, udp + 4);
        packet[rtp] = 0x80; packet[rtp + 1] = payload | (index === 0 ? 0x80 : 0);
        packet.writeUInt16BE(index + 1, rtp + 2); packet.writeUInt32BE(16000, rtp + 4);
        packet.writeUInt32BE(0x43414c4c, rtp + 8);
        packet[rtp + 12] = 1; packet[rtp + 13] = (index >= 10 ? 0x80 : 0) | 10;
        packet.writeUInt16BE(Math.min(index + 1, 10) * 160, rtp + 14);
        const record = Buffer.alloc(16);
        record.writeUInt32LE(1); record.writeUInt32LE(index * 20000, 4);
        record.writeUInt32LE(packet.length, 8); record.writeUInt32LE(packet.length, 12);
        records.push(record, packet);
    }
    return Buffer.concat(records);
}

function generate(directory, transport='external') {
    require('./callback-internal-scenarios.cjs').target(transport);
    const stat = fs.lstatSync(directory);
    assert(stat.isDirectory() && !stat.isSymbolicLink() && stat.uid === 0 && (stat.mode & 0o077) === 0,
        'Generator requires an existing private root-owned fixture directory');
    assert(/^[a-zA-Z0-9_./-]+$/.test(directory) && path.resolve(directory) === directory,
        'Unsafe scenario directory');
    const choices = [], branches = [];
    for (let payload = 96; payload <= 127; payload++) {
        const pcap = path.join(directory, `callback-digit1-${payload}.pcap`);
        fs.writeFileSync(pcap, digitPcap(payload, transport), {flag: 'wx', mode: 0o600});
        choices.push(`  <nop><action><test assign_to="is_dtmf_${payload}" variable="dtmf_payload" compare="equal" value="${payload}"/></action></nop>\n  <nop test="is_dtmf_${payload}" next="dtmf_${payload}"/>`);
        branches.push(`  <label id="dtmf_${payload}"/>\n  <nop><action><ereg regexp="(^| )${payload}( |$)" search_in="var" variable="audio_payloads" check_it="true" assign_to="media_mapping_${payload}"/><exec play_pcap_audio="${pcap}"/></action></nop>\n  <Reference variables="media_mapping_${payload}"/>\n  <nop next="dtmf_done"/>`);
    }
    const marker = '  <!-- CALLBACK_NEGOTIATED_DTMF: expanded by the local fixture generator. -->';
    const source = fs.readFileSync(path.join(__dirname, '../sip-tests/callback-returned.xml'), 'utf8');
    assert.equal(source.split(marker).length, 2, 'Scenario must have one generation marker');
    const replacement = choices.join('\n') +
        '\n  <nop><action><log message="callback-unsupported-telephone-event"/><exec int_cmd="stop_call"/></action></nop>\n' +
        branches.join('\n') + '\n  <label id="dtmf_done"/>';
    const output = path.join(directory, 'callback-returned.xml');
    fs.writeFileSync(output, source.replace(marker, replacement), {flag: 'wx', mode: 0o600});
    return output;
}

module.exports = {digitPcap, generate};
if (require.main === module) {
    try {
        assert([3,4].includes(process.argv.length), 'Usage: create-callback-carrier-scenario.cjs PRIVATE_DIRECTORY [external|internal]');
        console.log(generate(process.argv[2],process.argv[3]||'external'));
    } catch (error) {
        console.error('Callback scenario generation failed: ' + error.message);
        process.exitCode = 1;
    }
}
