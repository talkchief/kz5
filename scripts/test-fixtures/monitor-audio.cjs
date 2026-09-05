#!/usr/bin/env node
'use strict';
// Synthetic-tone-only RTP evidence. Never decode or print arbitrary call audio.
const assert = require('node:assert/strict');
const IP = '127.0.0.50';
const PORTS = {customer:49000,agent:49002,supervisor:49004};
const FREQUENCIES = [440,660,880];

function encode(sample) {
    const sign = sample < 0 ? 128 : 0;
    let value = Math.min(32635, Math.abs(Math.round(sample))) + 132, exponent = 7;
    for (let mask = 0x4000; exponent > 0 && !(value & mask); mask >>= 1) exponent--;
    return (~(sign | exponent << 4 | (value >> (exponent + 3) & 15))) & 255;
}
function decode(byte) {
    const value = (~byte) & 255;
    const sample = (((value & 15) << 3) + 132) << ((value >> 4) & 7);
    return (value & 128) ? 132 - sample : sample - 132;
}
function tone(frequencies, seconds=1) {
    assert(frequencies.every(f => FREQUENCIES.includes(f)) && seconds >= 1 && seconds <= 10);
    return Buffer.from(Array.from({length:8000*seconds}, (_,i) =>
        encode(frequencies.reduce((sum,f) => sum + 6000*Math.sin(2*Math.PI*f*i/8000),0))));
}
function packets(buffer) {
    assert(buffer.length >= 24 && buffer.length <= 64*1024*1024, 'Invalid capture size');
    const magic = buffer.subarray(0,4).toString('hex');
    const little = ['d4c3b2a1','4d3cb2a1'].includes(magic);
    const nano = ['4d3cb2a1','a1b23c4d'].includes(magic);
    assert(little || ['a1b2c3d4','a1b23c4d'].includes(magic), 'Unsupported pcap');
    const u32 = o => little ? buffer.readUInt32LE(o) : buffer.readUInt32BE(o);
    const link = u32(20); assert([1,113,276].includes(link), 'Unsupported link type');
    const result=[];
    for(let o=24;o<buffer.length;) {
        assert(o+16<=buffer.length,'Truncated record');
        const time=u32(o)+u32(o+4)/(nano?1e9:1e6), length=u32(o+8);
        assert(length<=65535 && o+16+length<=buffer.length,'Truncated packet');
        const p=buffer.subarray(o+16,o+16+length); o+=16+length;
        const ip=link===1?14:link===113?16:20, proto=link===1?12:link===113?14:0;
        if(p.length<ip+20 || p.readUInt16BE(proto)!==0x0800 || p[ip]>>4!==4 || p[ip+9]!==17) continue;
        assert((p.readUInt16BE(ip+6)&0x3fff)===0,'Fragmented UDP');
        const udp=ip+(p[ip]&15)*4; assert(udp+8<=p.length,'Truncated UDP');
        const size=p.readUInt16BE(udp+4); assert(size>=8 && udp+size<=p.length,'Truncated payload');
        const source=p.subarray(ip+12,ip+16).join('.'), dest=p.subarray(ip+16,ip+20).join('.');
        const sp=p.readUInt16BE(udp), dp=p.readUInt16BE(udp+2), r=p.subarray(udp+8,udp+size);
        if(r.length<12 || r[0]>>6!==2) continue;
        if(![0,96].includes(r[1]&127)) continue; // Ignore RTCP and non-negotiated payloads.
        let start=12+(r[0]&15)*4;
        if(r[0]&16) {assert(start+4<=r.length,'RTP extension');start+=4+4*r.readUInt16BE(start+2);}
        const end=(r[0]&32)?r.length-r[r.length-1]:r.length;
        assert(start<=end,'Invalid RTP bounds');
        if(source!==IP && dest!==IP) continue;
        assert((source===IP && Object.values(PORTS).includes(sp)) ||
            (dest===IP && Object.values(PORTS).includes(dp)), 'Capture contains non-fixture UDP');
        result.push({time,source,dest,sp,dp,pt:r[1]&127,stamp:r.readUInt32BE(4),ssrc:r.readUInt32BE(8),payload:r.subarray(start,end)});
    }
    return result;
}
function amplitudes(items) {
    const byStream=new Map();
    for(const packet of items) {
        if(packet.pt!==0) continue;
        const key=packet.ssrc, s=byStream.get(key)||{n:0,packets:0,re:[0,0,0],im:[0,0,0]};
        s.packets++;
        for(let j=0;j<packet.payload.length;j++) {
            const v=decode(packet.payload[j]), t=((packet.stamp+j)>>>0)%8000;
            FREQUENCIES.forEach((f,i)=>{const a=2*Math.PI*f*t/8000;s.re[i]+=v*Math.cos(a);s.im[i]+=v*Math.sin(a);});
            s.n++;
        }
        byStream.set(key,s);
    }
    assert(byStream.size===1,'Missing or ambiguous RTP SSRC');
    const s=[...byStream.values()][0];
    assert(s.n>=8000 && s.packets>=40,'Insufficient audio evidence');
    return Object.fromEntries(FREQUENCIES.map((f,i)=>[f,Math.round(2*Math.hypot(s.re[i],s.im[i])/s.n)]));
}
function inspect(buffer, mode, windows) {
    assert(['eavesdrop','whisper','barge','join'].includes(mode),'Unknown monitor mode');
    assert(Array.isArray(windows)&&windows.length===2,'Both pre/post-keypad windows required');
    const all=packets(buffer), evidence=[];
    for(const [index,window] of windows.entries()) {
        assert(Number.isFinite(window.start)&&Number.isFinite(window.end)&&window.end-window.start>=1.5,'Invalid evidence window');
        const frame=all.filter(p=>p.time>=window.start&&p.time<window.end), row={};
        for(const [role,port] of Object.entries(PORTS)) {
            const outbound=amplitudes(frame.filter(p=>p.source===IP&&p.sp===port));
            const incoming=amplitudes(frame.filter(p=>p.dest===IP&&p.dp===port));
            const own={customer:440,agent:660,supervisor:880}[role];
            assert(outbound[own]>2000,`${role} stimulus missing`);
            const expected=role==='customer'?[660]:role==='agent'?[440]:[440,660];
            if(role==='agent'&&mode!=='eavesdrop') expected.push(880);
            if(role==='customer'&&['barge','join'].includes(mode)) expected.push(880);
            expected.forEach(f=>assert(incoming[f]>500,`${mode} ${role} cannot hear required ${f}Hz`));
            if(role!=='supervisor'&&!expected.includes(880))
                assert(incoming[880]<100&&incoming[880]<Math.max(...expected.map(f=>incoming[f]))*0.025,
                    `${mode} supervisor audio leaked to ${role}`);
            row[role]={transmit:outbound,receive:incoming};
        }
        evidence.push({phase:index===0?'before_keypad_3':'after_keypad_3',...row});
    }
    const digits=all.filter(p=>p.source===IP&&p.sp===PORTS.supervisor&&p.pt===96&&p.payload[0]===3);
    assert(digits.some(p=>p.time>=windows[0].end&&p.time<=windows[1].start),'No keypad-3 escalation attempt between evidence windows');
    return {mode,keypad_3_packets:digits.length,windows:evidence};
}
module.exports={IP,PORTS,FREQUENCIES,encode,decode,tone,packets,amplitudes,inspect};
