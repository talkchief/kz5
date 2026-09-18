#!/usr/bin/env node
// SPDX-License-Identifier: MPL-2.0
// Native injected duplicate callback registration (private lab only). Every running
// applications node fires COUNT identical registrations at the same moment against
// the real datastore. Exactly one ticket may exist, at its first revision, and every
// request must be answered with that ticket. The same caller with another number
// must be refused without touching it. The ticket is never activated, so no call is
// placed; it is cancelled and removed afterwards, also when a check fails.
'use strict';
const {spawn,spawnSync}=require('node:child_process');
const crypto=require('node:crypto');
const path=require('node:path');
const GUESTS=['kz5-stage-kazoo-apps','kz5-stage-kazoo-apps-peer'];
const FIXTURE=path.join(__dirname,'test-fixtures/distributed-lab/callback-duplicate-rpc.escript');
const REMOTE='/var/lib/kazoo-stage/callback-duplicate-rpc.escript';
const count=Number(process.env.KZ5_DUPLICATE_COUNT||16);
if(!Number.isInteger(count)||count<2||count>64){console.error('KZ5_DUPLICATE_COUNT must be 2..64');process.exit(2);}
function run(args,timeout=30000){
    const r=spawnSync('podman',args,{encoding:'utf8',timeout});
    if(r.status!==0)throw new Error(`podman ${args.slice(0,3).join(' ')} exited ${r.status}: ${(r.stdout+r.stderr).trim().slice(0,300)}`);
    return r.stdout.trim();
}
function probe(guest,args){return JSON.parse(run(['exec',guest,'escript',REMOTE,...args]));}
function probeAsync(guest,args){
    return new Promise((resolve,reject)=>{
        const child=spawn('podman',['exec',guest,'escript',REMOTE,...args]);let out='';
        const timer=setTimeout(()=>child.kill('SIGKILL'),30000);
        child.stdout.on('data',d=>{out+=d;});
        child.on('close',code=>{clearTimeout(timer);
            if(code!==0)return reject(new Error(`${guest}: probe exited ${code}: ${out.trim().slice(0,200)}`));
            try{resolve({guest,...JSON.parse(out)});}catch(e){reject(e);}});
    });
}
function check(ok,message){if(!ok)throw new Error(message);console.log(`PASS ${message}`);}
(async()=>{
    const running=GUESTS.filter(g=>spawnSync('podman',['inspect','-f','{{.State.Running}}',g],{encoding:'utf8'}).stdout.trim()==='true');
    if(running.length===0){console.error('FAIL no lab applications guest is running');process.exit(1);}
    for(const g of running){run(['cp',FIXTURE,`${g}:${REMOTE}`]);run(['exec',g,'chmod','0600',REMOTE]);}
    const callId='duplicate-probe-'+crypto.randomBytes(8).toString('hex');
    const at=String(Math.floor(Date.now()/1000)-5);
    console.log(`nodes=${running.join(',')} requests_per_node=${count} call=${callId}`);
    let created=false,failed=false;
    try{
        const answers=await Promise.all(running.map(g=>probeAsync(g,['create',callId,at,String(count)])));
        created=true;
        for(const a of answers)console.log(JSON.stringify(a));
        const total=count*running.length;
        check(answers.every(a=>a.accepted===count&&a.other.length===0),`all ${total} identical registrations were acknowledged`);
        const ids=new Set(answers.flatMap(a=>a.ids));
        check(ids.size===1,`every acknowledgement names the same ticket (${[...ids][0]})`);
        check(new Set(answers.flatMap(a=>a.created)).size===1,'every acknowledgement carries the first write\'s creation time');
        check(answers.every(a=>String(a.stored_revision).startsWith('1-')),`the stored ticket is still at its first revision (${answers[0].stored_revision})`);
        check(answers.every(a=>a.stored_status==='registering'),'the stored ticket was not activated by the duplicates');
        const conflict=probe(running[running.length-1],['conflict',callId,at]);
        console.log(JSON.stringify(conflict));
        check(conflict.answer==='{error,registration_conflict}','the same caller with another number is refused');
        check(conflict.stored_number==='1001'&&conflict.stored_revision===answers[0].stored_revision,'the refused request did not change the ticket');
    }catch(e){failed=true;console.error(`FAIL ${e.message}`);}
    if(created||failed){
        try{const c=probe(running[0],['cleanup',callId,at]);console.log(`PASS probe ticket ${c.removed} cancelled and removed`);}
        catch(e){if(created){failed=true;console.error(`FAIL cleanup: ${e.message}`);}}
    }
    console.log(`RESULT ${failed?'FAIL':'PASS'}`);process.exit(failed?1:0);
})();
