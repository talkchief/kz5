#!/usr/bin/env node
'use strict';
// Native SIPp receiver regression; loopback only, no Kazoo/service/API access.
const assert=require('node:assert/strict'),dgram=require('node:dgram'),cp=require('node:child_process');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {phoneCallLimit}=require('./test-channel-monitor-live.cjs');
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function run(limit) {
    const dir=fs.mkdtempSync(path.join(os.tmpdir(),'monitor-options-'));
    const socket=dgram.createSocket('udp4'),reserve=dgram.createSocket('udp4');
    const bind=s=>new Promise(r=>s.bind(0,'127.0.0.1',r));
    await bind(socket);await bind(reserve);
    const port=reserve.address().port,source=socket.address().port;
    await new Promise(r=>reserve.close(r));
    const csv=path.join(dir,'input.csv');fs.writeFileSync(csv,'SEQUENTIAL\nunused-tone.ulaw\n',{mode:0o600});
    const replies=[];socket.on('message',b=>replies.push(b.toString()));
    const child=cp.spawn('sipp',['-sf',path.join(__dirname,'sip-tests/monitor-agent.xml'),'-inf',csv,
        '-i','127.0.0.1','-p',String(port),'-ci','127.0.0.1','-m',limit,'-l','1','-aa',
        '-nostdin','-timeout','8s','-timeout_error'],{stdio:'ignore',cwd:dir});
    const exited=new Promise(r=>child.once('exit',r));
    try {
        await sleep(400);assert.equal(child.exitCode,null,'SIPp did not start');
        function send(method,id) {
            const packet=[`${method} sip:fixture@127.0.0.1:${port} SIP/2.0`,
                `Via: SIP/2.0/UDP 127.0.0.1:${source};branch=z9hG4bK-${id}`,
                'From: <sip:test@localhost>;tag=fixture','To: <sip:fixture@localhost>',
                `Call-ID: ${id}@localhost`,`CSeq: 1 ${method}`,
                `Contact: <sip:test@127.0.0.1:${source}>`,'Content-Length: 0','',''].join('\r\n');
            socket.send(packet,port,'127.0.0.1');
        }
        send('OPTIONS','healthcheck');await sleep(500);
        assert(replies.some(v=>v.startsWith('SIP/2.0 200')&&v.includes('healthcheck@localhost')));
        send('INVITE','actual-call');await sleep(1000);
        return replies.some(v=>v.startsWith('SIP/2.0 180')&&v.includes('actual-call@localhost'));
    } finally {
        child.kill('SIGKILL');await exited;socket.close();
        // Retain the tiny private fixture directory as regression evidence.
    }
}
(async()=>{
    assert.equal(phoneCallLimit('customer'),'1');
    assert.equal(await run('1'),false,'Old SIPp limit must reproduce refused INVITE');
    assert.equal(await run(phoneCallLimit('agent')),true,'Receiver must ring after OPTIONS');
    console.log('PASS native loopback OPTIONS then INVITE: old limit fails, bounded receiver rings; customer remains one call');
})().catch(()=>{console.error('FAIL native loopback OPTIONS regression');process.exitCode=1;});
