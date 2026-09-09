#!/usr/bin/env node
'use strict';
const assert=require('node:assert/strict');
const audio=require('./monitor-audio.cjs');

function packet(time, source, sp, dest, dp, pt, stamp, ssrc, data) {
    const p=Buffer.alloc(14+20+8+12+data.length);
    p.writeUInt16BE(0x0800,12);p[14]=0x45;p.writeUInt16BE(p.length-14,16);p[22]=64;p[23]=17;
    source.split('.').forEach((x,i)=>p[26+i]=Number(x));dest.split('.').forEach((x,i)=>p[30+i]=Number(x));
    p.writeUInt16BE(sp,34);p.writeUInt16BE(dp,36);p.writeUInt16BE(p.length-34,38);
    p[42]=0x80;p[43]=pt;p.writeUInt16BE(Math.floor(stamp/160)%65536,44);p.writeUInt32BE(stamp,46);p.writeUInt32BE(ssrc,50);data.copy(p,54);
    const header=Buffer.alloc(16);header.writeUInt32LE(Math.floor(time),0);header.writeUInt32LE(Math.round((time%1)*1e6),4);
    header.writeUInt32LE(p.length,8);header.writeUInt32LE(p.length,12);return Buffer.concat([header,p]);
}
function capture(mode,{leak=false,missingDigit=false,missingSupervisor=false,address=audio.IP}={}) {
    const header=Buffer.alloc(24);header.writeUInt32LE(0xa1b2c3d4);header.writeUInt16LE(2,4);header.writeUInt16LE(4,6);header.writeUInt32LE(65535,16);header.writeUInt32LE(1,20);
    const buffers=[header], tones=new Map();
    function samples(fs,start){const key=fs.join();if(!tones.has(key))tones.set(key,audio.tone(fs));return tones.get(key).subarray(start%8000,start%8000+160);}
    for(let n=0;n<650;n++) {
        const time=100+n/50,stamp=n*160;
        for(const [index,[role,port]] of Object.entries(audio.PORTS).entries()) {
            if(missingSupervisor&&role==='supervisor')continue;
            buffers.push(packet(time,address,port,'127.0.0.1',30000+index*2,0,stamp,index+1,samples([audio.FREQUENCIES[index]],stamp)));
            const receive=role==='customer'?[660]:role==='agent'?[440]:[440,660];
            if(role==='agent'&&mode!=='eavesdrop')receive.push(880);
            if(role==='customer'&&(['barge','join'].includes(mode)||(leak&&time>=107)))receive.push(880);
            buffers.push(packet(time,'127.0.0.1',30000+index*2,address,port,0,stamp,index+11,samples(receive,stamp)));
        }
        if(n===250&&!missingDigit)buffers.push(packet(time,address,49004,'127.0.0.1',30004,96,stamp,3,Buffer.from([3,0x8a,0x06,0x40])));
    }
    return Buffer.concat(buffers);
}
const windows=[{start:102,end:104},{start:107,end:110}];
for(const mode of ['eavesdrop','whisper','barge','join']) {
    const proof=audio.inspect(capture(mode),mode,windows);
    assert.equal(proof.windows.length,2);assert.equal(proof.keypad_3_packets,1);
    console.log('PASS synthetic '+mode+' directionality before and after keypad3');
}
assert.throws(()=>audio.inspect(capture('whisper',{leak:true}),'whisper',windows),/leaked/);
assert.throws(()=>audio.inspect(capture('eavesdrop',{missingDigit:true}),'eavesdrop',windows),/No keypad/);
assert.throws(()=>audio.inspect(capture('join',{missingSupervisor:true}),'join',windows),/Missing/);
assert.throws(()=>audio.inspect(capture('barge').subarray(0,100),'barge',windows),/Truncated/);
assert.throws(()=>audio.inspect(capture('barge'),'barge',[]),/windows/);
console.log('PASS fail-closed leakage, missing keypad, missing stimulus, truncated capture and missing phase gates');
const distributed=audio.distributed();
assert.equal(distributed.IP,'172.30.253.1');assert.equal(audio.IP,'127.0.0.50');
for(const mode of ['eavesdrop','whisper','barge','join'])
    assert.equal(distributed.inspect(capture(mode,{address:distributed.IP}),mode,windows).windows.length,2);
assert.throws(()=>distributed.inspect(capture('whisper',{address:distributed.IP,leak:true}),'whisper',windows),/leaked/);
assert.throws(()=>distributed.inspect(capture('whisper'),'whisper',windows),/Missing/);
assert.throws(()=>audio.packets(capture('join'),'10.1.0.28'),/Unapproved/);
console.log('PASS separate fixed lab audio address with identical directionality/privacy gates and foreign-address refusal');
module.exports={capture,packet};
