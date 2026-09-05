#!/usr/bin/env node
'use strict';
// SPDX-License-Identifier: MPL-2.0
// Fake storage + private files only. Never reads a cookie or connects to Kazoo.
const assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {spawnSync}=require('node:child_process');
const m=require('./migrate-monster-app-api-url.cjs');
const clone=value=>JSON.parse(JSON.stringify(value));
let groups=0;
function fixture() {
    const docs=new Map(m.APPS.map(([name,id])=>[id,{_id:id,_rev:'2-abcdef',name,pvt_type:'app',
        pvt_account_id:m.ACCOUNT,pvt_account_db:m.DATABASE,api_url:m.SOURCE,
        custom:{secret:'NEVER-LOG-PRIVATE-CONTENT',nested:['é',false,null,{preserve:42}]},
        _attachments:{'icon.png':{content_type:'image/png',revpos:2,digest:'md5-private-example',length:99,stub:true}}}]));
    let writes=0,reads=0;
    return {docs,get writes(){return writes;},get reads(){return reads;},
        read(id){reads++;assert(docs.has(id));return JSON.stringify(docs.get(id));},
        save(id,rev,hash){
            const raw=JSON.stringify(docs.get(id));assert.equal(rev,docs.get(id)._rev);assert.equal(hash,m.sha(raw));
            const current=docs.get(id);assert.equal(current.api_url,m.SOURCE);
            current.api_url=m.TARGET;current._rev='3-'+String(++writes).padStart(32,'a');
            return {status:'committed',revision:current._rev};
        }};
}
function throwsCode(fn,code){assert.throws(fn,error=>error instanceof m.MigrationError && error.code===code);}
const scratch=fs.mkdtempSync(path.join(os.tmpdir(),'monster-app-url-migration-test.'));fs.chmodSync(scratch,0o700);
try {
    {
        const storage=fixture(),before=clone([...storage.docs]),receipts=[],logs=[];
        const plan=m.makePlan(storage,r=>receipts.push(clone(r)));
        assert.equal(storage.writes,0);assert.equal(storage.reads,10);assert.equal(receipts.length,1);
        assert.equal(m.validateReceipt(plan),plan);
        m.applyPlan(plan,storage,r=>receipts.push(clone(r)),line=>logs.push(line));
        assert.equal(storage.writes,10);assert.equal(plan.state,'complete');
        before.forEach(([id,doc])=>assert.deepEqual(storage.docs.get(id),{...doc,api_url:m.TARGET,_rev:storage.docs.get(id)._rev}));
        assert(!JSON.stringify(logs).includes('NEVER-LOG') && logs.every(e=>e.status==='committed_verified'));
        for(let i=0;i<10;i++) {
            const inFlight=receipts.findIndex(r=>r.apps[i].state==='in_flight');
            const committed=receipts.findIndex(r=>r.apps[i].state==='committed');
            assert(inFlight>0 && committed>inFlight,'In-flight receipt precedes commit');
        }
        const oldWrites=storage.writes;m.applyPlan(plan,storage,()=>{},line=>logs.push(line));
        assert.equal(storage.writes,oldWrites);assert.equal(logs.filter(e=>e.status==='receipt_verified_noop').length,10);
        groups++;
    }
    // Exact ownership checks: never identify an app by name or URL alone.
    for(const mutation of [d=>d._id='f'.repeat(32),d=>d.name='unreviewed',d=>d.pvt_type='user',
        d=>d.pvt_account_id='f'.repeat(32),d=>d.pvt_account_db='account%2Fff',d=>d.api_url=m.TARGET,
        d=>d.api_url='https://custom.invalid/v2/',d=>delete d._rev,d=>d._rev='0-abcd',d=>d.id=d._id,
        d=>d.pvt_deleted=true,d=>d._deleted=true,d=>d.pvt_deleted='true',d=>d._deleted=1,
        d=>d._conflicts=['3-abcd'],d=>d._attachments['icon.png'].data='secret',
        d=>d._attachments['icon.png'].stub=false,d=>d.custom.number=Number.MAX_SAFE_INTEGER+1]) {
        const storage=fixture();mutation(storage.docs.get(m.APPS[0][1]));
        assert.throws(()=>m.makePlan(storage));assert.equal(storage.writes,0);groups++;
    }
    // Change at the final preflight item must prevent writes to earlier apps.
    for(const mutation of [d=>d.api_url=m.TARGET,d=>d.api_url='http://custom.invalid/',d=>d._rev='9-abc',d=>d.custom.nested.push('new')]) {
        const storage=fixture(),plan=m.makePlan(storage);mutation(storage.docs.get(m.APPS[9][1]));
        assert.throws(()=>m.applyPlan(plan,storage));assert.equal(storage.writes,0);groups++;
    }
    for(const mutation of [p=>p.account_id='f'.repeat(32),p=>p.target_url='http://custom.invalid/',p=>p.apps.reverse(),
        p=>p.apps[0].original_sha256='0'.repeat(64),p=>p.apps[0].original_revision='4-abc',
        p=>p.apps[0].original_raw_json=p.apps[0].original_raw_json.replace('NEVER-LOG','changed')]) {
        const storage=fixture(),plan=m.makePlan(storage);mutation(plan);
        assert.throws(()=>m.applyPlan(plan,storage));assert.equal(storage.writes,0);groups++;
    }
    // Failure before in-flight receipt persistence must never invoke a save.
    {
        const storage=fixture(),plan=m.makePlan(storage);
        assert.throws(()=>m.applyPlan(plan,storage,()=>{throw Error('disk-full');}));
        assert.equal(storage.writes,0);groups++;
    }
    // A lost reply after a real commit remains uncertain, not inferred by URL.
    {
        const storage=fixture(),plan=m.makePlan(storage),save=storage.save;let calls=0,durable;
        storage.save=(...args)=>{const result=save(...args);if(++calls===3)throw Error('lost response');return result;};
        throwsCode(()=>m.applyPlan(plan,storage,r=>durable=clone(r)),'save_unconfirmed_manual_reconciliation');
        assert.equal(storage.writes,3);assert.equal(durable.state,'partial');
        assert.deepEqual(durable.apps.map(e=>e.state),['committed','committed','uncertain',...Array(7).fill('planned')]);
        throwsCode(()=>m.applyPlan(durable,storage),'manual_reconciliation_required');assert.equal(storage.writes,3);groups++;
    }
    // A crash between in-flight and response checkpoint is also not replayable.
    {
        const storage=fixture(),plan=m.makePlan(storage);let durable,persistCount=0;
        assert.throws(()=>m.applyPlan(plan,storage,r=>{if(++persistCount===2)throw Error('disk failure');durable=clone(r);}));
        assert.equal(storage.writes,1);assert.equal(durable.apps[0].state,'in_flight');
        throwsCode(()=>m.applyPlan(durable,storage),'manual_reconciliation_required');groups++;
    }
    // A saved commit acknowledgement supports verification-only replay after
    // read-back transport failure, without a second write to that app.
    {
        const storage=fixture(),plan=m.makePlan(storage),read=storage.read;let fail=true,durable;
        storage.read=id=>{if(fail && storage.writes===1){fail=false;throw Error('read failure');}return read(id);};
        assert.throws(()=>m.applyPlan(plan,storage,r=>durable=clone(r)));
        assert.equal(durable.apps[0].state,'committed');assert.equal(durable.state,'partial');
        m.applyPlan(durable,storage);assert.equal(storage.writes,10);assert.equal(durable.state,'complete');groups++;
    }
    // An operator edit to a receipt-proven commit is never silently accepted.
    {
        const storage=fixture(),plan=m.makePlan(storage);m.applyPlan(plan,storage);
        storage.docs.get(m.APPS[0][1]).custom.secret='changed';
        throwsCode(()=>m.applyPlan(plan,storage),'committed_document_changed');assert.equal(storage.writes,10);groups++;
    }
    // Noncommitted documents prechanged to target remain rejected even if the
    // rest of their body matches the saved original snapshot exactly.
    {
        const storage=fixture(),plan=m.makePlan(storage);storage.docs.get(m.APPS[0][1]).api_url=m.TARGET;
        throwsCode(()=>m.applyPlan(plan,storage),'unexpected_api_url');assert.equal(storage.writes,0);groups++;
    }
    // Atomic private receipt writes, exclusive lock and symlink/mode guards.
    {
        const directory=path.join(scratch,'receipt'),store=m.receiptStore(directory,true);
        const plan=m.makePlan(fixture(),store.persist);
        assert.equal(fs.statSync(directory).mode&0o777,0o700);
        assert.equal(fs.statSync(path.join(directory,'receipt.json')).mode&0o777,0o600);
        assert.deepEqual(store.read(),plan);
        assert.throws(()=>m.receiptStore(directory,false),'Concurrent invocations must not share receipt lock');
        store.close();assert(!fs.existsSync(path.join(directory,'migration.lock')));
        fs.chmodSync(path.join(directory,'receipt.json'),0o644);
        assert.throws(()=>m.protectedFile(path.join(directory,'receipt.json'),16*1024*1024));
        fs.chmodSync(path.join(directory,'receipt.json'),0o600);
        const symlink=path.join(scratch,'link');fs.symlinkSync(directory,symlink);
        assert.throws(()=>m.receiptStore(symlink,false));groups++;
        const brokenDir=path.join(scratch,'broken-receipt'),broken=m.receiptStore(brokenDir,true);
        fs.symlinkSync(path.join(scratch,'nonexistent'),path.join(brokenDir,'receipt.json'));
        assert.throws(()=>broken.persist(plan));assert(fs.lstatSync(path.join(brokenDir,'receipt.json')).isSymbolicLink());
        broken.close();groups++;
    }
    // Protocol construction puts only paths, node name and flags in argv;
    // operation details stay in stdin. No subprocess output is logged.
    {
        const privateDummy=path.join(scratch,'dummy-not-a-real-cookie');fs.writeFileSync(privateDummy,'not-an-actual-cookie\n',{mode:0o600});
        const seen=[],rpc=m.rpcStorage({node:'kazoo_apps@'+os.hostname(),cookieFile:privateDummy},(file,args,options)=>{
            seen.push({file,args,input:options.input});return {status:0,stdout:JSON.stringify({status:'committed',revision:'3-abc'})};
        });
        rpc.save(m.APPS[0][1],'2-abcdef','b'.repeat(64));
        assert(!seen[0].args.some(s=>s.includes('2-abcdef')||s.includes('not-an-actual-cookie')||s.includes('b'.repeat(64))));
        assert.deepEqual(JSON.parse(seen[0].input),{action:'save',id:m.APPS[0][1],expected_revision:'2-abcdef',expected_sha256:'b'.repeat(64)});
        const broken=m.rpcStorage({node:'kazoo_apps@'+os.hostname(),cookieFile:privateDummy},()=>({status:1,stdout:'PRIVATE-RESPONSE',stderr:'SECRET'}));
        throwsCode(()=>broken.read(m.APPS[0][1]),'bridge_unconfirmed');groups++;
    }
    // Escript compiles with warnings_as_errors and tests real pure guard code.
    const bridge=spawnSync('/usr/bin/escript',[path.join(__dirname,'monster-app-url-rpc.escript'),'--self-test'],
        {encoding:'utf8',timeout:15000,env:{...process.env,ERL_CRASH_DUMP:'/dev/null',ERL_FLAGS:'',ERL_AFLAGS:'',ERL_ZFLAGS:''}});
    assert.equal(bridge.status,0,bridge.stderr);assert.match(bridge.stdout,/PASS bridge pure guards/);groups++;
    const source=fs.readFileSync(path.join(__dirname,'monster-app-url-rpc.escript'),'utf8');
    assert(source.includes('rpc:call(Node,kz_datamgr,open_doc,[db(),Id],5000)'));
    assert(source.includes('rpc:call(Node,kz_datamgr,save_doc,[db(),Updated,[{publish_change_notice,true}]],5000)'));
    assert(!/rpc:call\([^\n]*(ensure_saved|update_doc|init_app|delete|put_attachment)/.test(source));
    for(const [name,id] of m.APPS)assert(source.includes('{<<"'+name+'">>,<<"'+id+'">>}'));
    groups++;
    console.log('PASS '+groups+' migration groups: exact allowlist, full preservation, CAS/replay, ambiguous-write refusal, partial recovery, protected receipts, stdin-only bridge; fake storage only');
} finally {fs.rmSync(scratch,{recursive:true});}
