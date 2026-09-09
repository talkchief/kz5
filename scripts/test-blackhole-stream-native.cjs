'use strict';
// Fixed development host; short-lived fixture token remains in process memory.
const assert = require('node:assert/strict');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const {randomBytes} = require('node:crypto');
const helper = path.join(__dirname,'test-fixtures/blackhole-stream-rpc.escript');
function rpc(...args) {
    const result = spawnSync('/usr/bin/escript',[helper,...args],{encoding:'utf8',timeout:12000,maxBuffer:32768});
    assert.equal(result.status,0,'Scoped native stream helper failed');
    return result.stdout.trim();
}
async function run() {
    assert.equal(process.argv.length,2);
    const {chromium} = require(process.env.KZ5_PLAYWRIGHT_ROOT);
    const browser = await chromium.launch({headless:true,args:['--no-sandbox', '--disable-dev-shm-usage', '--host-resolver-rules=MAP kz5-dev.talkchief.io 10.1.0.44']});
    let phase = 'connect';
    let page;
    const checks = [];
    try {
        page = await browser.newPage();
        await page.goto('https://kz5-dev.talkchief.io/',{waitUntil:'domcontentloaded',timeout:15000});
        // No subscriptions, SIP calls or provider API. Normal signing may
        // initialize the fixed acceptance account's missing identity secret.
        async function connect() {
            const issued = JSON.parse(rpc('issue')), tag = 'streamguard-'+randomBytes(16).toString('hex');
            await page.evaluate(async ({token,tag}) => {
                const socket = new WebSocket('wss://kz5-dev.talkchief.io/websocket');
                const state = window.streamTest = {socket,events:[],closed:null};
                socket.onmessage = e => {try {state.events.push(JSON.parse(e.data));} catch (_) {}};
                socket.onclose = e => {state.closed=e.code;};
                await new Promise((resolve,reject) => {
                    const timer=setTimeout(()=>reject(new Error('WSS timeout')),8000);
                    socket.onerror=()=>{clearTimeout(timer);reject(new Error('WSS failed'));};
                    socket.onopen=()=>{clearTimeout(timer);resolve();};
                });
                socket.send(JSON.stringify({action:'ping',auth_token:token,request_id:tag}));
            },{token:issued.token,tag});
            await page.waitForFunction(tag=>window.streamTest.events.some(e=>e.request_id===tag&&e.status==='success'),tag,{timeout:8000});
            return {expires:issued.expires,tag};
        }
        const first=await connect();
        phase='valid-event'; rpc('emit',first.tag,'before-expiry');
        await page.waitForFunction(()=>window.streamTest.events.some(e=>e.action==='event'&&e.data==='before-expiry'),null,{timeout:5000});
        checks.push(phase);
        phase='expired-event-denied';
        await new Promise(resolve=>setTimeout(resolve,Math.max(0,(first.expires+1)*1000-Date.now())));
        rpc('emit',first.tag,'after-expiry');
        await page.waitForFunction(()=>window.streamTest.closed!==null,null,{timeout:5000});
        assert.deepEqual(await page.evaluate(()=>({code:window.streamTest.closed,leaked:window.streamTest.events.some(e=>e.data==='after-expiry')})),{code:1008,leaked:false});
        checks.push(phase);
        const second=await connect();
        phase='mailbox-overload-close'; rpc('overflow',second.tag,'overflow');
        await page.waitForFunction(()=>window.streamTest.closed!==null,null,{timeout:5000});
        assert.equal(await page.evaluate(()=>window.streamTest.closed),1013);
        checks.push(phase);
        console.log(JSON.stringify({status:'PASS',checks,scope:'real WSS, signed expiring fixture JWT and owned socket injection; no binding/broker or transport soak claim'}));
    } catch (_) {
        const expired_event_received = page ? await page.evaluate(()=>Boolean(window.streamTest?.events.some(e=>e.data==='after-expiry'))).catch(()=>null) : null;
        console.error(JSON.stringify({status:'FAIL',phase,checks,expired_event_received})); process.exitCode=1;
    } finally {await browser.close();}
}
run().catch(()=>{console.error('Native stream test failed before protected session setup');process.exitCode=1;});
