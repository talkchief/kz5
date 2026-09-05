#!/usr/bin/env node
'use strict';
// Small synthetic UAS for bounded queue routing acceptance, not a SIP client.
const assert=require('node:assert/strict'),dgram=require('node:dgram'),crypto=require('node:crypto');
function parse(buffer) {
    const text=buffer.toString('utf8');assert(text.length<=65535&&!text.includes('\0'),'Invalid SIP packet');
    const [head,...body]=text.split('\r\n\r\n'),lines=head.split('\r\n'),first=lines.shift(),headers={};
    for(const line of lines){const at=line.indexOf(':');assert(at>0,'Invalid SIP header');
        const key=line.slice(0,at).toLowerCase();(headers[key]??=[]).push(line.slice(at+1).trim());}
    return {first,headers,body:body.join('\r\n\r\n'),method:first.split(' ')[0]};
}
const one=(m,key)=>m.headers[key]?.[0];
function response(m,code,reason,tag,contact,body='') {
    const to=one(m,'to');assert(to&&one(m,'from')&&one(m,'call-id')&&one(m,'cseq')&&m.headers.via,'Incomplete SIP request');
    return Buffer.from([`SIP/2.0 ${code} ${reason}`,...m.headers.via.map(x=>'Via: '+x),
        ...(m.headers['record-route']||[]).map(x=>'Record-Route: '+x),
        'From: '+one(m,'from'),'To: '+to+(/;tag=/.test(to)||!tag?'':';tag='+tag),
        'Call-ID: '+one(m,'call-id'),'CSeq: '+one(m,'cseq'),...(contact?['Contact: <'+contact+'>']:[]),
        ...(body?['Content-Type: application/sdp']:[]),'Content-Length: '+Buffer.byteLength(body),'',body].join('\r\n'));
}
class Phone {
    constructor(endpoint,ip,allowedPeers,onEvent) {
        this.endpoint=endpoint;this.ip=ip;this.allowedPeers=new Set(allowedPeers);this.onEvent=onEvent;
        this.dialogs=new Map();this.timers=new Set();this.socket=dgram.createSocket('udp4');this.rtp=dgram.createSocket('udp4');
        this.policy=()=>null;this.failure=null;this.packetCount=0;
        this.socket.on('error',()=>{this.failure=Error('Fixture SIP socket failed');});
        this.rtp.on('error',()=>{this.failure=Error('Fixture RTP socket failed');});
        this.socket.on('message',(b,peer)=>{try{this.receive(b,peer);}catch(e){this.failure=e;}});
        this.rtp.on('message',(b,peer)=>{if(this.allowedPeers.has(peer.address)&&b.length>=12&&b[0]>>6===2){
            this.packetCount++;this.rtp.send(b,peer.port,peer.address);}});
    }
    async start(){await Promise.all([[this.socket,this.endpoint.port],[this.rtp,this.endpoint.rtp]].map(([s,p])=>
        new Promise((resolve,reject)=>{s.once('error',reject);s.bind(p,this.ip,resolve);})));}
    send(buffer,peer){this.socket.send(buffer,peer.port,peer.address);}
    event(type,dialog){this.onEvent({type,agent:this.endpoint.index,call_id:dialog.id,time:Date.now()});}
    receive(buffer,peer) {
        assert(this.allowedPeers.has(peer.address),'SIP packet from nonlocal peer');
        const m=parse(buffer);if(m.first.startsWith('SIP/2.0'))return;
        const id=one(m,'call-id');assert(id&&/^[A-Za-z0-9_.:@-]{1,128}$/.test(id),'Invalid fixture call ID');
        const contact=`sip:${this.endpoint.username}@${this.ip}:${this.endpoint.port}`;
        if(m.method==='OPTIONS'){this.send(response(m,200,'OK','',contact),peer);return;}
        if(m.method==='INVITE') {
            const target=m.first.split(' ')[1];
            assert(target?.startsWith('sip:'+this.endpoint.username+'@'),'INVITE targets another fixture identity');
            const old=this.dialogs.get(id);
            if(old){assert(one(old.invite,'cseq')===one(m,'cseq'),'Unexpected fixture re-INVITE');this.send(old.last,peer);return;}
            const dialog={id,invite:m,peer,tag:crypto.randomBytes(8).toString('hex'),ended:false,answered:false,acked:false};
            this.dialogs.set(id,dialog);this.event('invite',dialog);
            this.send(response(m,100,'Trying','',null),peer);
            dialog.last=response(m,180,'Ringing',dialog.tag,contact);this.send(dialog.last,peer);
            const delay=this.policy(dialog);
            if(delay!==null){assert(Number.isInteger(delay)&&delay>=0&&delay<=30000,'Unsafe answer delay');
                const timer=setTimeout(()=>{this.timers.delete(timer);if(dialog.ended)return;
                    dialog.answered=true;
                    const sdp=`v=0\r\no=strategy 1 1 IN IP4 ${this.ip}\r\ns=Isolated queue strategy\r\nc=IN IP4 ${this.ip}\r\nt=0 0\r\nm=audio ${this.endpoint.rtp} RTP/AVP 0\r\na=rtpmap:0 PCMU/8000\r\na=sendrecv\r\n`;
                    dialog.last=response(m,200,'OK',dialog.tag,contact,sdp);this.send(dialog.last,peer);this.event('answer',dialog);
                    let attempts=0;const repeat=setInterval(()=>{if(dialog.acked||dialog.ended||++attempts>14){clearInterval(repeat);this.timers.delete(repeat);return;}
                        this.send(dialog.last,peer);},500);this.timers.add(repeat);
                },delay);this.timers.add(timer);}
            return;
        }
        const dialog=this.dialogs.get(id);assert(dialog,'Non-fixture SIP dialog');
        if(m.method==='ACK'){dialog.acked=true;this.event('ack',dialog);return;}
        if(m.method==='CANCEL'){
            this.send(response(m,200,'OK',dialog.tag,contact),peer);this.event('cancel',dialog);
            if(!dialog.answered){dialog.ended=true;dialog.last=response(dialog.invite,487,'Request Terminated',dialog.tag,contact);this.send(dialog.last,dialog.peer);}return;
        }
        if(m.method==='BYE'){dialog.ended=true;this.send(response(m,200,'OK',dialog.tag,contact),peer);this.event('bye',dialog);return;}
        if(m.method==='INFO'){this.send(response(m,200,'OK',dialog.tag,contact),peer);return;}
        throw Error('Unexpected fixture SIP method');
    }
    close(){for(const t of this.timers){clearTimeout(t);clearInterval(t);}this.timers.clear();
        for(const socket of [this.socket,this.rtp])try{socket.close();}catch(_){} }
}
module.exports={parse,response,Phone};
