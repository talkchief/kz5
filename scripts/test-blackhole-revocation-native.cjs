'use strict';
// Explicitly armed wrapper holds fixture lock. Rotate only the fixed test user's
// JWT signature secret by revision CAS; do not restore a revoked signing secret.
const assert=require('node:assert/strict'),path=require('node:path'),{randomBytes}=require('node:crypto');
const {spawnSync}=require('node:child_process');
function rpc(...args) {
    const r=spawnSync('/usr/bin/escript',[path.join(__dirname,'test-fixtures/blackhole-stream-rpc.escript'),...args],
        {encoding:'utf8',timeout:12000,maxBuffer:32768});
    assert.equal(r.status,0,'Exact fixture RPC refused');return r.stdout.trim();
}
async function main() {
    assert.equal(process.argv.length,2);
    const {chromium}=require(process.env.KZ5_PLAYWRIGHT_ROOT);
    const browser=await chromium.launch({headless:true,args:['--no-sandbox','--disable-dev-shm-usage',
        '--host-resolver-rules=MAP kz5-dev.talkchief.io 10.1.0.44']});
    let phase='setup';const checks=[];
    try {
        const page=await browser.newPage();
        await page.goto('https://kz5-dev.talkchief.io/',{waitUntil:'domcontentloaded',timeout:15000});
        const issued=JSON.parse(rpc('issue-user')),tag='streamguard-'+randomBytes(16).toString('hex');
        await page.evaluate(async ({token,tag})=>{
            const socket=new WebSocket('wss://'+location.host+'/websocket');
            window.revocationTest={socket,events:[],closed:null};
            socket.onmessage=e=>{try{window.revocationTest.events.push(JSON.parse(e.data));}catch(_){}};
            socket.onclose=e=>{window.revocationTest.closed=e.code;};
            await new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(Error('timeout')),7000);
                socket.onopen=()=>{clearTimeout(timer);resolve();};socket.onerror=()=>{clearTimeout(timer);reject(Error('error'));};});
            socket.send(JSON.stringify({action:'ping',auth_token:token,request_id:tag}));
        },{token:issued.token,tag});
        await page.waitForFunction(tag=>window.revocationTest.events.some(e=>e.request_id===tag&&e.status==='success'),tag,{timeout:7000});
        phase='valid-delivery-warms-cache';rpc('emit',tag,'before-expiry');
        await page.waitForFunction(()=>window.revocationTest.events.some(e=>e.data==='before-expiry'),null,{timeout:5000});checks.push(phase);
        phase='revoke-exact-fixture-identity';rpc('revoke-user',tag,issued.user_revision);checks.push(phase);
        phase='revoked-delivery-denied';rpc('emit',tag,'after-revocation');
        await page.waitForFunction(()=>window.revocationTest.closed!==null,null,{timeout:5000});
        assert.deepEqual(await page.evaluate(()=>({code:window.revocationTest.closed,
            leaked:window.revocationTest.events.some(e=>e.data==='after-revocation')})),{code:1008,leaked:false});checks.push(phase);
        phase='revoked-http-denied-before-expiry';assert(Date.now()<issued.expires*1000);
        const status=await page.evaluate(async token=>(await fetch('/v2/accounts/8310dc3170a18de37f205d0da172df65/users/10cbff5eb98c9c7e4231b7156b15a3fd',
            {headers:{'X-Auth-Token':token},redirect:'error',signal:AbortSignal.timeout(5000)})).status,issued.token);
        assert.equal(status,401);checks.push(phase);
        console.log(JSON.stringify({status:'PASS',checks,scope:'one fixed test-user signature rotated; real same-node cache invalidation, HTTPS and WSS; no global-partition claim'}));
    } catch(_) {console.error(JSON.stringify({status:'FAIL',phase,checks}));process.exitCode=1;}
    finally {await browser.close();}
}
main().catch(()=>{console.error('Revocation test refused before setup');process.exitCode=1;});
