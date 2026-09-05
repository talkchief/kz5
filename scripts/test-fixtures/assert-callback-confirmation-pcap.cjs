#!/usr/bin/env node
'use strict';
// Read-only packet gate: the exact local returned caller's RFC2833 digit 1
// must precede every INVITE to the isolated agent endpoint. No packet payloads
// or credentials are printed. tcpdump's classic pcap Ethernet/SLL/SLL2 formats
// are supported; unknown/truncated input fails closed.
const fs = require('node:fs');
const assert = require('node:assert/strict');

function inspect(buffer, carrierRtpPort = 44000, agentSipPort = 15100) {
    assert(buffer.length >= 24, 'Missing pcap header');
    const magic = buffer.subarray(0, 4).toString('hex');
    const little = ['d4c3b2a1', '4d3cb2a1'].includes(magic);
    const nano = ['4d3cb2a1', 'a1b23c4d'].includes(magic);
    assert(little || ['a1b2c3d4', 'a1b23c4d'].includes(magic), 'Unsupported pcap format');
    const u32 = offset => little ? buffer.readUInt32LE(offset) : buffer.readUInt32BE(offset);
    const link = u32(20);
    assert([1, 113, 276].includes(link), 'Unsupported pcap link type');
    let digit = Infinity, invite = Infinity, digitPackets = 0, invites = 0;
    for (let offset = 24; offset < buffer.length;) {
        assert(offset + 16 <= buffer.length, 'Truncated pcap record');
        const time = u32(offset) + u32(offset + 4) / (nano ? 1e9 : 1e6);
        const length = u32(offset + 8);
        assert(offset + 16 + length <= buffer.length, 'Truncated pcap packet');
        const packet = buffer.subarray(offset + 16, offset + 16 + length);
        offset += 16 + length;
        let ip = link === 1 ? 14 : link === 113 ? 16 : 20;
        const protocolOffset = link === 1 ? 12 : link === 113 ? 14 : 0;
        if (packet.length < ip || packet.readUInt16BE(protocolOffset) !== 0x0800) continue;
        if (packet.length < ip + 20 || packet[ip] >> 4 !== 4 || packet[ip + 9] !== 17) continue;
        assert((packet.readUInt16BE(ip + 6) & 0x3fff) === 0, 'Fragmented UDP cannot prove confirmation ordering');
        const udp = ip + (packet[ip] & 15) * 4;
        if (packet.length < udp + 8) continue;
        const sourcePort = packet.readUInt16BE(udp), destinationPort = packet.readUInt16BE(udp + 2);
        const udpLength = packet.readUInt16BE(udp + 4);
        assert(udpLength >= 8 && udp + udpLength <= packet.length, 'Truncated UDP packet');
        const payload = packet.subarray(udp + 8, udp + udpLength);
        if (destinationPort === agentSipPort && payload.subarray(0, 7).toString() === 'INVITE ') {
            invite = Math.min(invite, time); invites++;
        }
        if (sourcePort !== carrierRtpPort || packet.subarray(ip + 12, ip + 16).toString('hex') !== '7f00001e') continue;
        // SIPp play_dtmf emits PT 96; callback-returned.xml negotiates that
        // exact telephone-event payload type, independently of agent SDP.
        if (payload.length < 16 || payload[0] >> 6 !== 2 || (payload[1] & 127) !== 96) continue;
        let rtp = 12 + (payload[0] & 15) * 4;
        if (payload[0] & 16) {
            assert(payload.length >= rtp + 4, 'Truncated RTP extension');
            rtp += 4 + payload.readUInt16BE(rtp + 2) * 4;
        }
        if (payload.length >= rtp + 4 && payload[rtp] === 1) {
            digit = Math.min(digit, time); digitPackets++;
        }
    }
    assert(digitPackets > 0, 'No returned caller RFC2833 digit 1 observed');
    assert(invites > 0, 'No native agent INVITE observed');
    assert(invite >= digit, 'Agent INVITE preceded returned caller confirmation');
    return {digit_packets: digitPackets, agent_invites: invites, first_agent_invite_after_digit_ms: Math.round((invite - digit) * 1000)};
}

module.exports = {inspect};
if (require.main === module) {
    try {
        assert(process.argv.length === 3, 'Usage: assert-callback-confirmation-pcap.cjs capture.pcap');
        assert(fs.statSync(process.argv[2]).size <= 64 * 1024 * 1024, 'Capture exceeds acceptance bound');
        process.stdout.write(JSON.stringify(inspect(fs.readFileSync(process.argv[2]))) + '\n');
    } catch (error) {
        process.stderr.write('Callback confirmation evidence FAIL: ' + error.message + '\n');
        process.exitCode = 1;
    }
}
