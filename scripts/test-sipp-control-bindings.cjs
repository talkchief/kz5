#!/usr/bin/env node
'use strict';
// Static inventory + extracted argument evaluation only. No SIPp, network,
// credentials, API requests, registrations or fixture calls are executed.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process');
const vm=require('node:vm'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
function control(args){
    assert.equal(args.filter(x=>x==='-ci').length,1,'One explicit SIPp control binding required');
    const ip=args[args.indexOf('-ci')+1];
    assert(typeof ip==='string' && /^127(?:\.(?:0|[1-9][0-9]{0,2})){3}$/.test(ip)
        && ip.split('.').every(x=>Number(x)<=255),'SIPp control must be an explicit IPv4 loopback, never the remote proxy');
}
function withoutControl(args){return args.filter((_,i)=>args[i]!=='-ci'&&args[i-1]!=='-ci');}
function shellArguments(command){
    const input=`set -Eeuo pipefail
declare -A STATE=([ACCEPTANCE_SIP_PROXY_HOST]=198.51.100.9 [ACCEPTANCE_SIP_PROXY_PORT]=5060)
PHONE_IP=127.0.0.40
LOCAL_IP=127.0.0.20
CARRIER_IP=127.0.0.30
proxy=198.51.100.9:5060
`;
    const names=[...new Set([...command.matchAll(/\$\{?([A-Za-z_][A-Za-z0-9_]*)/g)].map(x=>x[1]))]
        .filter(x=>!['STATE','PHONE_IP','LOCAL_IP','CARRIER_IP','proxy'].includes(x));
    const setup=names.map(x=>`${x}=1`).join('\n');
    // This subprocess evaluates only the extracted invocation and an in-memory
    // shell function. The real executable cannot be reached through this path.
    const r=cp.spawnSync('/bin/bash',['--noprofile','--norc','-s'],{
        input:input+setup+'\nset +u\nsipp() { printf "%s\\0" "$@"; }\n'+command+'\n',
        encoding:'utf8',timeout:5000,env:{PATH:'/usr/bin:/bin',LANG:'C'}});
    assert.ifError(r.error);assert.equal(r.status,0,r.stderr);
    return r.stdout.split('\0').slice(0,-1);
}
function shellInvocations(text){
    const logical=text.replace(/\\\n/g,' '),out=[];
    for(const line of logical.split('\n')){
        const m=line.match(/^\s*(?:(?:if\s+!?\s*)?(?:timeout\s+\d+\s+)?)sipp\s/);
        if(!m)continue;
        const command=line.slice(line.indexOf('sipp ',m.index)).split(/\s+(?:\d?>|&>|\|\||&&)/)[0].trim();
        if(/^sipp\s+-(?:v|h)(?:\s|$)/.test(command))continue;
        out.push(shellArguments(command));
    }
    return out;
}
function arrayAt(text,start){
    assert.equal(text[start],'[');let depth=0,quote=null,escaped=false;
    for(let i=start;i<text.length;i++){
        const c=text[i];
        if(quote){if(escaped)escaped=false;else if(c==='\\')escaped=true;else if(c===quote)quote=null;continue;}
        if(c==='"'||c==="'"||c==='`'){quote=c;continue;}
        if(c==='[')depth++;else if(c===']'&&--depth===0)return text.slice(start,i+1);
    }
    throw Error('Unclosed SIPp argument array');
}
function jsInvocations(text){
    const out=[];
    const re=/\b(?:command|(?:cp\.)?spawn(?:Sync)?)\(\s*['"]sipp['"]\s*,\s*/g;
    for(const match of text.matchAll(re)){
        let start=match.index+match[0].length;
        if(text[start]!=='['){
            assert(/^args\b/.test(text.slice(start)),'Unreviewed dynamic SIPp argument variable');
            const builders=[...text.matchAll(/const args\s*=\s*\[/g)];
            assert.equal(builders.length,1,'Ambiguous dynamic SIPp argument builder');
            start=builders[0].index+builders[0][0].length-1;
        }
        const expression=arrayAt(text,start);
        const args=Array.from(vm.runInNewContext(expression,{
            state:{ACCEPTANCE_SIP_PROXY_HOST:'198.51.100.9'},path:{join:(...p)=>p.join('/')},
            SCENARIOS:'scenario',__dirname:'scripts',csv:'fixture.csv',scenario:'fixture.xml',file:'fixture.xml',
            audio:{IP:'127.0.0.51'},IP:'127.0.0.62',e:{role:'customer',port:19000,rtp:49000},
            port:19000,index:'0',name:'fixture.xml',peer:{address:()=>({port:19001})}
        },{timeout:1000}));
        if(args.length===1&&['-v','-h'].includes(args[0]))continue;
        out.push(args);
    }
    return out;
}
const files=cp.execFileSync('git',['ls-files','-z','--','scripts/*.sh','scripts/*.cjs'],{cwd:root,encoding:'utf8'})
    .split('\0').filter(Boolean).filter(p=>p!==path.relative(root,__filename));
let invocations=0,covered=0;
for(const file of files){
    const text=fs.readFileSync(path.join(root,file),'utf8');
    if(!/\bsipp\b/.test(text))continue;
    const read=file.endsWith('.sh')?shellInvocations:jsInvocations;
    const args=read(text);if(!args.length)continue;
    args.forEach(control);
    const previous=cp.execFileSync('git',['show','HEAD:'+file],{cwd:root,encoding:'utf8'}),baseline=read(previous);
    assert.equal(args.length,baseline.length,'Socket-creating scenario count changed');
    args.forEach((a,i)=>assert.deepEqual(withoutControl(a),withoutControl(baseline[i]),'SIP/media/timing arguments changed: '+file));
    invocations+=args.length;covered++;
}
assert.equal(invocations,28,'SIPp launch inventory changed; audit every new socket-creating path');
assert.equal(covered,13,'SIPp fixture file inventory changed');
for(const args of [[],['-i','127.0.0.1'],['-ci','0.0.0.0'],['-ci','198.51.100.9'],
    ['-ci','127.0.0.999'],['-ci','127.0.0.1','-ci','127.0.0.2']])assert.throws(()=>control(args));
control(['-ci','127.0.0.1']);control(['-ci','127.0.0.40']);
console.log(`PASS ${invocations} SIPp launch argument vectors across ${covered} files: explicit loopback control, original SIP/RTP/scenario arguments preserved; six unsafe-binding negatives; no sockets or live calls`);
