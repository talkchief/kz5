#!/usr/bin/env node
'use strict';
// Fault injection executes the real fixture source in a VM. All fixture file
// reads/writes and every API request use memory-only doubles; no live services.
const assert=require('node:assert/strict'), fs=require('node:fs'), path=require('node:path'), vm=require('node:vm');
const crypto=require('node:crypto');
const source=fs.readFileSync(path.join(__dirname,'announcement-queue.cjs'),'utf8');
const A='11111111111111111111111111111111', MASTER='22222222222222222222222222222222';
const Q='33333333333333333333333333333333', F='44444444444444444444444444444444';
const MARK='acdc-announcement-5555555555555555', RUN='/var/log/kazoo-acceptance/isolated-unit';
const SAVED=RUN+'/announcement-fixture.json', BEFORE=RUN+'/announcement-queue-before.json';
const BASE='/etc/kazoo/acceptance-secrets.env', AUTH='/etc/kazoo/installer-secrets.env';
const clone=value=>JSON.parse(JSON.stringify(value));
const encode=values=>Object.entries(values).map(([k,v])=>k+'='+Buffer.from(v).toString('base64')).join('\n');
const tenant={id:A,name:'Kazoo5 Acceptance abcdef123456',realm:'acceptance-abcdef123456.invalid'};

function world(fixture) {
    const files=new Map([
        [BASE,encode({ACCEPTANCE_ACCOUNT_ID:A,ACCEPTANCE_REALM:tenant.realm,ACCEPTANCE_ACCOUNT_NAME:tenant.name})],
        [AUTH,'KAZOO_MASTER_ADMIN_USER=synthetic-admin\nKAZOO_MASTER_ADMIN_PASSWORD=not-a-real-secret\nKAZOO_MASTER_ACCOUNT_REALM=synthetic.invalid\n']
    ]);
    if(fixture)files.set(SAVED,JSON.stringify(fixture));
    return {files,docs:{queues:new Map(),callflows:new Map()},requests:[],writes:[],fault:{},permissions:new Map()};
}
function ownedFixture(extra={}) {return {account:A,marker:MARK,extension:'2099',...extra};}
function queue(extra={}) {return {id:Q,name:MARK,kazoo_acceptance_fixture:MARK,agents:[],announcements:{initial_delay:30,interval:30},...extra};}
function flow(extra={}) {return {id:F,name:MARK,kazoo_acceptance_fixture:MARK,numbers:['2099'],flow:{module:'acdc_member',data:{id:Q},children:{}},...extra};}
function mutations(w) {return w.requests.filter(r=>['PUT','PATCH','POST','DELETE'].includes(r.method)&&r.relative!=='user_auth');}

async function execute(w,action) {
    const messages=[], processDouble={argv:['node','announcement-queue.cjs',action,RUN],env:{},exitCode:0};
    let realmJSON;
    const fsDouble={
        realpathSync:file=>{assert.equal(file,RUN);return file;},
        lstatSync:file=>{assert(w.files.has(file),'Read of unknown in-memory file');return {uid:0,mode:0o600,isFile:()=>true,isSymbolicLink:()=>false,...w.permissions.get(file)};},
        readFileSync:file=>{assert(w.files.has(file),'Read of unknown in-memory file');return w.files.get(file);},
        existsSync:file=>w.files.has(file),
        writeFileSync:(file,body,options)=>{
            assert([SAVED,BEFORE].includes(file),'Unexpected fixture filesystem mutation');
            assert.equal(options.mode,0o600);assert.equal(typeof body,'string');
            w.writes.push({file,body});w.files.set(file,body);
        }
    };
    const fetchDouble=async(url,options)=>{
        const prefix='http://127.0.0.1:8000/v2/';assert(url.startsWith(prefix));
        const relative=url.slice(prefix.length), method=options.method;
        assert(relative==='user_auth'||relative===`accounts/${A}`||relative.startsWith(`accounts/${A}/`),'Out-of-tenant request');
        const data=options.body?JSON.parse(options.body).data:undefined;
        w.requests.push({method,relative,data:clone(data??null)});
        const response=(status,data,extra={})=>({ok:status>=200&&status<300,status,json:async()=>realmJSON(JSON.stringify({status:status<300?'success':'error',data,...extra}))});
        if(relative==='user_auth')return response(200,{account_id:MASTER},{auth_token:'synthetic-token'});
        assert.equal(options.headers['X-Auth-Token'],'synthetic-token');
        if(relative===`accounts/${A}`)return response(200,tenant);
        const match=relative.match(/^accounts\/[a-f0-9]{32}\/(queues|callflows)(?:\/([a-f0-9]{32}))?(\?paginate=false)?$/);
        assert(match,'Unexpected fixture resource path');const [,collection,id,query]=match, docs=w.docs[collection];
        if(method==='GET'&&!id) {
            assert.equal(query,'?paginate=false');
            return response(200,[...docs.values()].map(d=>({id:d.id,name:d.name,numbers:d.numbers})),
                w.fault.incomplete===collection?{next_start_key:'partial-cursor'}:{});
        }
        if(method==='GET')return docs.has(id)?response(200,docs.get(id)):response(404,null);
        if(method==='PUT'&&!id) {
            const created=collection==='queues'?Q:F;
            assert(!docs.has(created),'Unexpected overwrite');
            docs.set(created,{...clone(data),id:created,...(collection==='queues'?{agents:[]}:{} )});
            if(w.fault.lostCreate===collection){delete w.fault.lostCreate;throw Error('Synthetic lost create reply');}
            return response(200,docs.get(created));
        }
        assert(id&&docs.has(id),'Unexpected mutation of absent resource');
        if(method==='PATCH'||method==='POST') {
            docs.set(id,{...docs.get(id),...clone(data)});return response(200,docs.get(id));
        }
        if(method==='DELETE') {
            const old=docs.get(id);docs.delete(id);
            if(w.fault.lostDelete===collection){delete w.fault.lostDelete;throw Error('Synthetic lost delete reply');}
            return response(200,old);
        }
        throw Error('Unexpected synthetic request');
    };
    const context=vm.createContext({
        require:name=>({
            'node:fs':fsDouble,'node:path':path,'node:assert/strict':assert,
            'node:crypto':{createHash:crypto.createHash,randomBytes:size=>Buffer.alloc(size,0x55)}
        }[name]||assert.fail('Unexpected module '+name)),
        process:processDouble,Buffer,fetch:fetchDouble,AbortSignal:{timeout:()=>({mock:true})},
        console:{log:message=>messages.push({kind:'log',message}),error:message=>messages.push({kind:'error',message})}
    });
    realmJSON=vm.runInContext('JSON.parse',context);
    try {await vm.runInContext(source,context,{filename:'announcement-queue.cjs',timeout:2000});}
    catch(error){processDouble.exitCode=1;messages.push({kind:'error',message:error.message});}
    return {code:processDouble.exitCode,messages};
}

async function test(name,fn) {await fn();console.log('PASS '+name);}
(async()=>{
    await test('normal setup/cleanup touches only its marked queue and route, with0600 state',async()=>{
        const w=world();assert.equal((await execute(w,'setup')).code,0);
        const saved=JSON.parse(w.files.get(SAVED));assert.equal(saved.queue_id,Q);assert.equal(saved.callflow_id,F);
        assert.equal((await execute(w,'cleanup')).code,0);assert.equal(w.docs.queues.size+w.docs.callflows.size,0);
        assert(JSON.parse(w.files.get(SAVED)).cleaned_at);
        assert(mutations(w).every(r=>/^accounts\/[a-f0-9]{32}\/(queues|callflows)/.test(r.relative)));
    });
    for(const collection of ['queues','callflows'])await test('lost '+collection+' create reply is recovered only by durable exact marker',async()=>{
        const w=world();w.fault.lostCreate=collection;assert.equal((await execute(w,'setup')).code,1);
        const partial=JSON.parse(w.files.get(SAVED));assert.equal(partial.marker,MARK);
        assert.equal(partial[collection==='queues'?'queue_id':'callflow_id'],undefined);
        assert.equal((await execute(w,'cleanup')).code,0);assert.equal(w.docs.queues.size+w.docs.callflows.size,0);
    });
    await test('same-name resources with another marker are never adopted or removed',async()=>{
        const w=world(ownedFixture());w.docs.queues.set(Q,queue({kazoo_acceptance_fixture:'foreign-marker'}));
        assert.equal((await execute(w,'cleanup')).code,0);assert.equal(w.docs.queues.size,1);assert.equal(mutations(w).length,0);
    });
    await test('duplicate exact markers and incomplete inventories fail before deletion',async()=>{
        const w=world(ownedFixture()), other='66666666666666666666666666666666';
        w.docs.queues.set(Q,queue());w.docs.queues.set(other,queue({id:other}));
        assert.equal((await execute(w,'cleanup')).code,1);assert.equal(mutations(w).length,0);
        const partial=world(ownedFixture());partial.fault.incomplete='queues';
        assert.equal((await execute(partial,'cleanup')).code,1);assert.equal(mutations(partial).length,0);
    });
    await test('saved IDs still require exact markers, route number, and queue target',async()=>{
        for(const changed of [flow({kazoo_acceptance_fixture:'foreign'}),flow({numbers:['2000']}),
            flow({flow:{module:'acdc_member',data:{id:'66666666666666666666666666666666'}}})]) {
            const w=world(ownedFixture({queue_id:Q,callflow_id:F}));w.docs.queues.set(Q,queue());w.docs.callflows.set(F,changed);
            assert.equal((await execute(w,'cleanup')).code,1);assert.equal(mutations(w).length,0);
        }
    });
    await test('lost DELETE reply converges through fresh404 without deleting anything else',async()=>{
        const w=world();assert.equal((await execute(w,'setup')).code,0);w.fault.lostDelete='callflows';
        assert.equal((await execute(w,'cleanup')).code,1);assert.equal(w.docs.callflows.size,0);
        assert.equal((await execute(w,'cleanup')).code,0);assert.equal(w.docs.queues.size,0);
        const before=w.requests.length;assert.equal((await execute(w,'cleanup')).code,0);
        assert(w.requests.slice(before).every(r=>r.relative==='user_auth'||r.relative===`accounts/${A}`));
    });
    await test('wrong tenant and unprotected state are rejected without resource mutations',async()=>{
        const foreign=world(ownedFixture({account:MASTER}));assert.equal((await execute(foreign,'cleanup')).code,1);
        assert.equal(mutations(foreign).length,0);
        const open=world(ownedFixture());open.permissions.set(SAVED,{mode:0o644});
        assert.equal((await execute(open,'cleanup')).code,1);assert.equal(mutations(open).length,0);
    });
    await test('occupied2099 route fails setup without claiming existing resources',async()=>{
        const w=world();w.docs.callflows.set(F,flow({kazoo_acceptance_fixture:'foreign'}));
        assert.equal((await execute(w,'setup')).code,1);assert.equal(mutations(w).length,0);assert(!w.files.has(SAVED));
    });
    console.log('PASS9 memory-only announcement fixture fault groups; no network or filesystem mutation');
})().catch(error=>{console.error(error.message);process.exitCode=1;});
