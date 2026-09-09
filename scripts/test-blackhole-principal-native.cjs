'use strict';
// Native ordinary-user account boundary acceptance; GET and own WSS only.
const assert=require('node:assert/strict'),path=require('node:path');
const {spawnSync}=require('node:child_process');
const ACCOUNT='8310dc3170a18de37f205d0da172df65',USER='10cbff5eb98c9c7e4231b7156b15a3fd';
const QUEUE='67c5f3fb115bdd1dd574d6a604a7d29f',MASTER='adecbb84fbe9e06902a76731914d1943';
async function main() {
    assert.equal(process.argv.length,2);
    const {chromium}=require(process.env.KZ5_PLAYWRIGHT_ROOT);
    const browser=await chromium.launch({headless:true,args:['--no-sandbox','--disable-dev-shm-usage',
        '--host-resolver-rules=MAP kz5-dev.talkchief.io 10.1.0.44']});
    let phase='setup';const checks=[];
    try {
        const page=await browser.newPage();
        await page.goto('https://kz5-dev.talkchief.io/',{waitUntil:'domcontentloaded',timeout:15000});
        const issued=spawnSync('/usr/bin/escript',[path.join(__dirname,'test-fixtures/blackhole-stream-rpc.escript'),'issue-user'],
            {encoding:'utf8',timeout:12000,maxBuffer:32768});
        assert.equal(issued.status,0,'Fixture ordinary-user guard failed');
        const {token}=JSON.parse(issued.stdout);
        for(const [name,route,status] of [
            ['ordinary-user-authenticated',`accounts/${ACCOUNT}/users/${USER}`,200],
            ['ordinary-user-policy-denied',`accounts/${ACCOUNT}/scope_restrictions`,403],
            ['foreign-users-denied',`accounts/${MASTER}/users`,403],
            ['foreign-members-devices-denied',`accounts/${MASTER}/members/devices`,403],
            ['foreign-queue-live-denied',`accounts/${MASTER}/queues/live?page_size=1`,403],
            ['own-queue-live-authorized',`accounts/${ACCOUNT}/queues/${QUEUE}/live`,200]
        ]) {
            phase=name;
            const actual=await page.evaluate(async ({route,token})=>{
                const r=await fetch('/v2/'+route,{headers:{'X-Auth-Token':token},redirect:'error',signal:AbortSignal.timeout(7000)});
                const j=await r.json();return {status:r.status,envelope:j.status};
            },{route,token});
            assert.equal(actual.status,status);assert.equal(actual.envelope,status===200?'success':'error');checks.push(name);
        }
        phase='wss-account-boundary';
        const result=await page.evaluate(async ({token,account,queue,master})=>{
            const socket=new WebSocket('wss://'+location.host+'/websocket');
            try {
                await new Promise((resolve,reject)=>{
                    const timer=setTimeout(()=>reject(Error('timeout')),7000);
                    socket.onopen=()=>{clearTimeout(timer);resolve();};socket.onerror=()=>{clearTimeout(timer);reject(Error('failed'));};
                });
                async function send(id,target,action='subscribe') {
                    return new Promise((resolve,reject)=>{
                        const timer=setTimeout(()=>{socket.removeEventListener('message',receive);reject(Error('timeout'));},7000);
                        function receive(e) {let j;try{j=JSON.parse(e.data);}catch(_){return;}
                            if(j.request_id!==id)return;clearTimeout(timer);socket.removeEventListener('message',receive);resolve(j.status);}
                        socket.addEventListener('message',receive);
                        socket.send(JSON.stringify({action,auth_token:token,request_id:id,data:{account_id:target,binding:'queue_live.changed.'+queue}}));
                    });
                }
                return {own:await send('principal-own',account),foreign:await send('principal-foreign',master),
                    unsubscribed:await send('principal-unsubscribe',account,'unsubscribe')};
            } finally {socket.close();}
        },{token,account:ACCOUNT,queue:QUEUE,master:MASTER});
        assert.deepEqual(result,{own:'success',foreign:'error',unsubscribed:'success'});checks.push(phase);
        console.log(JSON.stringify({status:'PASS',checks,scope:'fixed ordinary fixture user, real HTTPS/WSS, GET-only; no policy writes or calls'}));
    } catch(_) {console.error(JSON.stringify({status:'FAIL',phase,checks}));process.exitCode=1;}
    finally {await browser.close();}
}
main().catch(()=>{console.error('Principal test refused before setup');process.exitCode=1;});
