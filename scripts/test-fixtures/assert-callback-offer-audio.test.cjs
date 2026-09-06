'use strict';
// Synthetic exact-dialog SIP/RTP PCAP; does not call SIPp or any live service.
const assert=require('node:assert/strict'),{inspect,assertCaptureLog}=require('./assert-callback-offer-audio.cjs');
const call='1-999@127.0.0.20',expected={call_id:call,queue_id:'1'.repeat(32),ip:'127.0.0.20',sip_port:15064,media_port:47200,queue_entry:100};
function reference(length,seed){const b=Buffer.alloc(length);for(let i=0;i<length;i++){seed=(Math.imul(seed,1664525)+1013904223)>>>0;b[i]=(seed>>>24)&127;}return b;}
const refs={offer:reference(32000,41),position:reference(12000,79)};
function capture(options={}) {
    const header=Buffer.alloc(24);header.writeUInt32LE(0xa1b2c3d4);header.writeUInt16LE(2,4);header.writeUInt16LE(4,6);header.writeUInt32LE(65535,16);header.writeUInt32LE(1,20);
    const records=[header];
    function udp(time,payload,src,dst,sp,dp){const p=Buffer.alloc(42+payload.length);p.writeUInt16BE(0x0800,12);p[14]=0x45;
        p.writeUInt16BE(28+payload.length,16);p[23]=17;Buffer.from(src.split('.').map(Number)).copy(p,26);Buffer.from(dst.split('.').map(Number)).copy(p,30);
        p.writeUInt16BE(sp,34);p.writeUInt16BE(dp,36);p.writeUInt16BE(payload.length+8,38);payload.copy(p,42);
        const r=Buffer.alloc(16);r.writeUInt32LE(Math.floor(time),0);r.writeUInt32LE(Math.round((time-Math.floor(time))*1e6),4);r.writeUInt32LE(p.length,8);r.writeUInt32LE(p.length,12);records.push(r,p);}
    const sdp=(ip,port)=>`v=0\r\no=- 1 1 IN IP4 ${ip}\r\ns=fixture\r\nc=IN IP4 ${ip}\r\nt=0 0\r\nm=audio ${port} RTP/AVP 0\r\na=rtpmap:0 PCMU/8000\r\n`;
    function sip(time,first,seq,method,out,body='',to='remote') {
        const text=first+'\r\nCall-ID: '+call+'\r\nFrom: <sip:fixture@acceptance.invalid>;tag=local\r\nTo: <sip:2098@acceptance.invalid>'+ (to?';tag='+to:'')
            +'\r\nCSeq: '+seq+' '+method+'\r\n'+(body?'Content-Type: application/sdp\r\n':'')+'Content-Length: '+Buffer.byteLength(body)+'\r\n\r\n'+body;
        udp(time,Buffer.from(text),out?'127.0.0.20':'127.0.0.1',out?'127.0.0.1':'127.0.0.20',out?15064:5060,out?5060:15064);
    }
    sip(99.95,'INVITE sip:2098@acceptance.invalid SIP/2.0',2,'INVITE',true,sdp('127.0.0.20',47200),'');
    sip(100,'SIP/2.0 200 OK',2,'INVITE',false,sdp(options.remote||'127.0.0.1',30000));
    if(!options.noAck)sip(100.01,'ACK sip:2098@acceptance.invalid SIP/2.0',2,'ACK',true,'',options.badTag?'wrong':'remote');
    const audio=Buffer.alloc(46*8000,255);
    for(const at of options.offer||[3,18,33])refs.offer.copy(audio,at*8000);
    for(const at of options.position||[11,26,41])refs.position.copy(audio,at*8000);
    for(let offset=0;offset<audio.length;offset+=160){if((options.loss&&offset===3*8000+160)||offset===options.lossAt*8000)continue;
        const rtp=Buffer.alloc(172);rtp[0]=128;rtp.writeUInt16BE(offset/160,2);rtp.writeUInt32BE(offset,4);rtp.writeUInt32BE(77,8);audio.copy(rtp,12,offset,offset+160);
        udp(100+offset/8000,rtp,options.foreign?'127.0.0.2':'127.0.0.1','127.0.0.20',30000,47200);}
    if(options.dtmf){const b=Buffer.alloc(16);b[0]=128;b[1]=101;udp(108,b,'127.0.0.20','127.0.0.1',47200,30000);}
    sip(146,'BYE sip:2098@acceptance.invalid SIP/2.0',3,'BYE',true);
    if(!options.noByeAck)sip(146.01,'SIP/2.0 200 OK',3,'BYE',false);
    return Buffer.concat(records);
}
let groups=0;const valid=capture(),result=inspect(valid,refs,expected);
assert.deepEqual(result.offer.map(m=>m.after_queue_entry_seconds),[3,18,33]);
assert.deepEqual(result.position.map(m=>m.after_queue_entry_seconds),[11,26,41]);assert(result.no_offer_on_entry);groups++;
for(const [options,pattern] of [[{offer:[0,18,33]},/schedule/],[{offer:[3,17,31]},/schedule/],
    [{offer:[3,18]},/exactly3/],[{position:[8,23,38]},/schedule/],[{position:[11,26]},/exactly3/],
    [{foreign:true},/Foreign RTP/],[{remote:'198.51.100.2'},/Non-local/],[{noAck:true},/Missing dialog ACK/],
    [{badTag:true},/Missing dialog ACK/],[{noByeAck:true},/Missing BYE200/],[{dtmf:true},/DTMF/],[{loss:true},/exactly3|Missing RTP/],
    [{lossAt:1},/Missing RTP/],[{lossAt:16},/Missing RTP/],[{lossAt:45},/Missing RTP/]]) {
    assert.throws(()=>inspect(capture(options),refs,expected),pattern);groups++;
}
assert.throws(()=>inspect(valid,refs,{...expected,call_id:'1-888@127.0.0.20'}),/Foreign dialog/);groups++;
assert.throws(()=>inspect(valid.subarray(0,-1),refs,expected),/Truncated/);groups++;
assert.throws(()=>inspect(valid,{...refs,offer:Buffer.alloc(56000,17)},expected),/shorter than7/);groups++;
const captureLog='2304 packets captured\n4608 packets received by filter\n0 packets dropped by kernel\n';
assertCaptureLog(captureLog);groups++;
for(const bad of ['', captureLog.replace('0 packets dropped','1 packets dropped'),
    captureLog.replace('2304 packets captured','0 packets captured'),
    captureLog.replace('4608 packets received by filter\n',''),
    captureLog+'0 packets dropped by kernel\n', 'x'.repeat(65537)]) {
    assert.throws(()=>assertCaptureLog(bad));groups++;
}
console.log('PASS '+groups+' synthetic dual-schedule SIP/RTP gates; full phrases, exact peer, no DTMF, loss and timing negatives');
